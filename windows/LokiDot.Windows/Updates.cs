using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace LokiDot;

internal readonly record struct ReleaseVersion(int Major, int Minor, int Patch) : IComparable<ReleaseVersion>
{
    internal static ReleaseVersion Current {
        get {
            var version = typeof(App).Assembly.GetName().Version ?? throw new InvalidDataException("Missing application version.");
            return new(version.Major, version.Minor, version.Build);
        }
    }
    internal static ReleaseVersion Parse(string tag)
    {
        var match = Regex.Match(tag, @"\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z", RegexOptions.CultureInvariant);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out int major) || !int.TryParse(match.Groups[2].Value, out int minor) || !int.TryParse(match.Groups[3].Value, out int patch))
            throw new InvalidDataException("The release tag must be a stable vMAJOR.MINOR.PATCH version.");
        return new(major, minor, patch);
    }
    public int CompareTo(ReleaseVersion other) {
        int result = Major.CompareTo(other.Major);
        if (result == 0) result = Minor.CompareTo(other.Minor);
        return result == 0 ? Patch.CompareTo(other.Patch) : result;
    }
    public override string ToString() => $"{Major}.{Minor}.{Patch}";
}

internal sealed record UpdateRelease(ReleaseVersion Version, Uri Download, long Size, string Sha256)
{
    internal const string AssetName = "LokiDot-Zoomies-win-x64.msi";
    internal const string Repository = "https://github.com/ashrocket/lokidot-zoomies";
    internal const int MetadataLimit = 1024 * 1024;
    internal const long DownloadLimit = 512L * 1024 * 1024;
    internal static readonly Uri Feed = new("https://api.github.com/repos/ashrocket/lokidot-zoomies/releases/latest");

    internal static UpdateRelease Parse(byte[] bytes)
    {
        try { return ParseCore(bytes); }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException) {
            throw new InvalidDataException("GitHub release information is incomplete or invalid. No installer was downloaded.", error);
        }
    }
    static UpdateRelease ParseCore(byte[] bytes)
    {
        SpritePack.Require(bytes.Length <= MetadataLimit, "Release information exceeds 1 MiB.");
        using var document = JsonDocument.Parse(bytes, new() { MaxDepth = 32 });
        RejectDuplicates(document.RootElement);
        var root = document.RootElement;
        SpritePack.Require(root.ValueKind == JsonValueKind.Object, "Release information must be a JSON object.");
        SpritePack.Require(root.GetProperty("draft").ValueKind == JsonValueKind.False && root.GetProperty("prerelease").ValueKind == JsonValueKind.False, "Only published stable releases can be installed.");
        string tag = Text(root, "tag_name");
        var version = ReleaseVersion.Parse(tag);
        SpritePack.Require(Text(root, "html_url") == $"{Repository}/releases/tag/{tag}", "The release belongs to an unexpected repository or tag.");
        var assets = root.GetProperty("assets");
        SpritePack.Require(assets.ValueKind == JsonValueKind.Array, "The release has no asset list.");
        var matches = assets.EnumerateArray().Where(asset => Text(asset, "name") == AssetName).ToArray();
        SpritePack.Require(matches.Length == 1, "The release must contain exactly one Windows MSI asset.");
        var item = matches[0];
        SpritePack.Require(Text(item, "state") == "uploaded", "The Windows MSI is not fully uploaded.");
        string expected = $"{Repository}/releases/download/{tag}/{AssetName}";
        SpritePack.Require(Text(item, "browser_download_url") == expected, "The Windows MSI URL does not match this repository, tag and filename.");
        SpritePack.Require(item.GetProperty("size").TryGetInt64(out long size) && size > 0 && size <= DownloadLimit, "The Windows MSI size must be positive and no larger than 512 MiB.");
        string digest = Text(item, "digest");
        SpritePack.Require(Regex.IsMatch(digest, @"\Asha256:[a-fA-F0-9]{64}\z", RegexOptions.CultureInvariant), "The release must include a complete SHA-256 digest for its Windows MSI.");
        return new(version, new Uri(expected), size, digest[7..].ToLowerInvariant());
    }
    static string Text(JsonElement element, string name) {
        var value = element.GetProperty(name);
        SpritePack.Require(value.ValueKind == JsonValueKind.String, $"Release field {name} must be text.");
        return value.GetString()!;
    }
    static void RejectDuplicates(JsonElement value) {
        if (value.ValueKind == JsonValueKind.Object) {
            HashSet<string> keys = [];
            foreach (var item in value.EnumerateObject()) {
                SpritePack.Require(keys.Add(item.Name), "Release information contains duplicate fields.");
                RejectDuplicates(item.Value);
            }
        } else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) RejectDuplicates(item);
    }
}

internal sealed class UpdateClient : IDisposable
{
    readonly HttpClient http;
    readonly Func<string, UpdateRelease, CancellationToken, Task<InstallerGuardLease>> startInstaller;
    internal UpdateClient() : this(new SocketsHttpHandler {
        AllowAutoRedirect = false, AutomaticDecompression = DecompressionMethods.None,
        UseCookies = false, Credentials = null, DefaultProxyCredentials = null,
        ConnectTimeout = TimeSpan.FromSeconds(10)
    }, InstallerGuard.StartAsync) { }
    // Injected transport is used only by offline self-tests.
    internal UpdateClient(HttpMessageHandler transport, Func<string, UpdateRelease, CancellationToken, Task<InstallerGuardLease>> installerLauncher) {
        startInstaller = installerLauncher;
        http = new(transport) { Timeout = Timeout.InfiniteTimeSpan };
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"LokiDot-Zoomies/{ReleaseVersion.Current}");
    }
    internal async Task<UpdateRelease> CheckAsync(CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var request = new HttpRequestMessage(HttpMethod.Get, UpdateRelease.Feed);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
        // No metadata redirects are followed, even to another API route.
        if (IsRedirect(response.StatusCode)) throw new InvalidDataException("GitHub redirected the release feed; this check was stopped.");
        response.EnsureSuccessStatusCode();
        SpritePack.Require(response.Content.Headers.ContentLength is not long size || size <= UpdateRelease.MetadataLimit, "Release information exceeds 1 MiB.");
        await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false);
        using var data = new MemoryStream();
        byte[] buffer = new byte[16384];
        while (true) {
            int read = await stream.ReadAsync(buffer, timeout.Token).ConfigureAwait(false);
            if (read == 0) break;
            SpritePack.Require(data.Length + read <= UpdateRelease.MetadataLimit, "Release information exceeds 1 MiB.");
            data.Write(buffer, 0, read);
        }
        return UpdateRelease.Parse(data.ToArray());
    }
    internal async Task<PreparedUpdate> DownloadAsync(UpdateRelease release, bool userApproved, CancellationToken cancellation)
    {
        SpritePack.Require(userApproved, "Downloading an update requires your approval.");
        // Revalidate descriptors as well as feed data before any network or filesystem side effect.
        ValidateDescriptor(release);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromMinutes(5));
        using var response = await DownloadResponseAsync(release.Download, timeout.Token).ConfigureAwait(false);
        SpritePack.Require(response.StatusCode == HttpStatusCode.OK, "GitHub did not return a complete MSI download.");
        SpritePack.Require(response.Content.Headers.ContentLength is not long size || size == release.Size, "The downloaded MSI length differs from its release metadata.");
        string directory = UpdateStorage.CreateStagingDirectory();
        string path = Path.Combine(directory, UpdateRelease.AssetName);
        try {
            await using (var input = await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false))
            await using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous | FileOptions.SequentialScan)) {
                await CopyVerifiedAsync(input, output, release, timeout.Token).ConfigureAwait(false);
                await output.FlushAsync(timeout.Token).ConfigureAwait(false);
            }
            // Retain Windows' Internet-origin marker; do not suppress reputation/security prompts.
            File.WriteAllText(path + ":Zone.Identifier", $"[ZoneTransfer]\r\nZoneId=3\r\nReferrerUrl={UpdateRelease.Feed.AbsoluteUri}\r\nHostUrl={release.Download.AbsoluteUri}\r\n", System.Text.Encoding.ASCII);
            // Hold a read handle excluding write/delete sharing through the installer handoff.
            var prepared = new PreparedUpdate(path, release, startInstaller);
            try { await prepared.VerifyAsync(timeout.Token).ConfigureAwait(false); return prepared; }
            catch { prepared.Dispose(); throw; }
        } catch {
            // Only our own incomplete installer is removed; successful downloads are retained for Windows Installer.
            if (File.Exists(path)) File.Delete(path);
            throw;
        }
    }
    internal static void ValidateDescriptor(UpdateRelease release) {
        _ = ReleaseVersion.Parse("v" + release.Version);
        SpritePack.Require(release.Version.CompareTo(ReleaseVersion.Current) > 0, "Only a newer version can be downloaded for installation.");
        string expected = $"{UpdateRelease.Repository}/releases/download/v{release.Version}/{UpdateRelease.AssetName}";
        SpritePack.Require(release.Download.OriginalString == expected && release.Size > 0 && release.Size <= UpdateRelease.DownloadLimit
            && Regex.IsMatch(release.Sha256, @"\A[a-fA-F0-9]{64}\z"), "Invalid Windows update descriptor.");
    }
    async Task<HttpResponseMessage> DownloadResponseAsync(Uri start, CancellationToken token)
    {
        var current = start;
        for (int redirects = 0; redirects <= 5; redirects++) {
            SpritePack.Require(IsAllowedDownloadUri(current), "The MSI download redirected to an untrusted host or protocol.");
            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            if (!IsRedirect(response.StatusCode)) return response;
            Uri? location = response.Headers.Location;
            response.Dispose();
            SpritePack.Require(location != null, "The MSI download redirect has no destination.");
            current = location.IsAbsoluteUri ? location : new Uri(current, location);
            // A GitHub hop must still name the exact original repository/tag/asset.
            SpritePack.Require(current.Host != "github.com" || current.AbsoluteUri == start.AbsoluteUri, "The MSI download redirected to a different GitHub asset.");
        }
        throw new InvalidDataException("The MSI download redirected too many times.");
    }
    internal static bool IsAllowedDownloadUri(Uri uri) => uri.IsAbsoluteUri && uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort
        && uri.UserInfo.Length == 0 && uri.Fragment.Length == 0
        && uri.IdnHost is "github.com" or "release-assets.githubusercontent.com" or "objects.githubusercontent.com" or "github-releases.githubusercontent.com";
    static bool IsRedirect(HttpStatusCode code) => (int)code is >= 300 and <= 399;
    internal static async Task CopyVerifiedAsync(Stream input, Stream output, UpdateRelease release, CancellationToken token)
    {
        ValidateDescriptor(release);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        byte[] buffer = new byte[65536]; long total = 0;
        while (true) {
            int read = await input.ReadAsync(buffer, token).ConfigureAwait(false);
            if (read == 0) break;
            total += read;
            SpritePack.Require(total <= release.Size && total <= UpdateRelease.DownloadLimit, "The MSI download exceeds its declared size.");
            hash.AppendData(buffer, 0, read);
            await output.WriteAsync(buffer.AsMemory(0, read), token).ConfigureAwait(false);
        }
        SpritePack.Require(total == release.Size && CryptographicOperations.FixedTimeEquals(hash.GetHashAndReset(), Convert.FromHexString(release.Sha256)), "The MSI download failed its exact size or SHA-256 verification. Nothing was installed.");
    }
    public void Dispose() => http.Dispose();
}

internal sealed class PreparedUpdate : IDisposable
{
    readonly FileStream lockedFile;
    readonly UpdateRelease release;
    readonly string path;
    readonly Func<string, UpdateRelease, CancellationToken, Task<InstallerGuardLease>> startInstaller;
    bool verified;
    internal string InstallerPath => path;
    internal PreparedUpdate(string path, UpdateRelease release, Func<string, UpdateRelease, CancellationToken, Task<InstallerGuardLease>> installerLauncher) {
        this.path = path; this.release = release; startInstaller = installerLauncher;
        UpdateStorage.RequireLocalPath(path);
        SpritePack.Require((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0, "The staged installer cannot be a link.");
        lockedFile = new(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.Asynchronous | FileOptions.SequentialScan);
    }
    internal async Task VerifyAsync(CancellationToken token) {
        lockedFile.Position = 0;
        var digest = await SHA256.HashDataAsync(lockedFile, token).ConfigureAwait(false);
        SpritePack.Require(lockedFile.Length == release.Size && CryptographicOperations.FixedTimeEquals(digest, Convert.FromHexString(release.Sha256)), "The staged MSI changed after download. Nothing was installed.");
        verified = true;
    }
    internal Task<InstallerGuardLease> LaunchAsync(bool userApproved, CancellationToken token) {
        SpritePack.Require(userApproved && verified, "Installing requires your approval and a verified MSI.");
        // The caller keeps this object alive until a separate helper confirms its
        // independently verified file lock. Failure awaits helper exit before return.
        return startInstaller(path, release, token);
    }
    public void Dispose() => lockedFile.Dispose();
}

internal static class UpdateStorage
{
    internal static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LokiDot", "Zoomies");
    internal static void RequireLocalPath(string path) {
        path = Path.GetFullPath(path);
        SpritePack.Require(Regex.IsMatch(path, @"\A[A-Za-z]:\\") && new DriveInfo(Path.GetPathRoot(path)!).DriveType != DriveType.Network, "Update storage must be on a local drive.");
        for (var folder = new DirectoryInfo(Path.GetDirectoryName(path)!); folder != null; folder = folder.Parent)
            if (folder.Exists) SpritePack.Require((folder.Attributes & FileAttributes.ReparsePoint) == 0, "Update storage cannot use links or reparse points.");
    }
    internal static string CreateStagingDirectory() {
        string path = Path.Combine(Root, "Updates", Guid.NewGuid().ToString("N"));
        RequireLocalPath(Path.Combine(path, UpdateRelease.AssetName));
        using var identity = WindowsIdentity.GetCurrent();
        var user = identity.User ?? throw new IOException("Could not identify your Windows account for private update storage.");
        var security = new DirectorySecurity(); security.SetOwner(user); security.SetAccessRuleProtection(true, false);
        foreach (var sid in new[] { user, new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
            security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        security.CreateDirectory(path);
        RequireLocalPath(Path.Combine(path, UpdateRelease.AssetName));
        return path;
    }
    internal static bool LoadAutomaticChecks() {
        try {
            string path = Path.Combine(Root, "automatic-updates.txt"); RequireLocalPath(path);
            if (!File.Exists(path)) return true;
            SpritePack.Require((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0 && new FileInfo(path).Length <= 8, "Invalid update preference file.");
            return File.ReadAllText(path).Trim() != "0";
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException) { return true; }
    }
    internal static void SaveAutomaticChecks(bool enabled) {
        string path = Path.Combine(Root, "automatic-updates.txt"); RequireLocalPath(path); Directory.CreateDirectory(Root);
        string staging = Path.Combine(Root, $"preference-{Guid.NewGuid():N}.tmp");
        File.WriteAllText(staging, enabled ? "1" : "0"); File.Move(staging, path, true);
    }
}
