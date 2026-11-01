using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace LokiDot;

internal static class UpdateTests
{
    internal static void Run(Action<bool, string> check)
    {
        void Reject(Action action, string name) {
            try { action(); }
            catch (Exception error) when (error is InvalidDataException or JsonException or KeyNotFoundException or InvalidOperationException or IOException or ArgumentException) {
                check(true, "update rejects " + name); return;
            }
            throw new InvalidDataException("Update self-test accepted " + name);
        }
        int installerCalls = 0;
        Task<InstallerGuardLease> NoInstall(string path, UpdateRelease release, CancellationToken token) {
            installerCalls++;
            return Task.FromException<InstallerGuardLease>(new InvalidOperationException("The injected test installer launcher cannot run an installer."));
        }
        byte[] payload = [1, 2, 3, 4];
        string hash = Convert.ToHexStringLower(SHA256.HashData(payload));
        byte[] Feed() => JsonSerializer.SerializeToUtf8Bytes(new {
            tag_name = "v1.4.0", draft = false, prerelease = false,
            html_url = UpdateRelease.Repository + "/releases/tag/v1.4.0",
            assets = new[] { new { name = UpdateRelease.AssetName, state = "uploaded", size = payload.Length,
                browser_download_url = UpdateRelease.Repository + "/releases/download/v1.4.0/" + UpdateRelease.AssetName, digest = "sha256:" + hash } }
        });
        byte[] Mutate(Action<JsonObject> change) {
            var node = JsonNode.Parse(Feed())!.AsObject(); change(node); return Encoding.UTF8.GetBytes(node.ToJsonString());
        }
        JsonObject Asset(JsonObject root) => root["assets"]![0]!.AsObject();
        var release = UpdateRelease.Parse(Feed());
        check(ReleaseVersion.Current == new ReleaseVersion(1,3,2), "update application version is 1.3.2");
        check(release.Version.CompareTo(ReleaseVersion.Current) > 0 && release.Size == 4 && release.Sha256 == hash, "update accepts a complete stable release descriptor");
        check(ReleaseVersion.Parse("v1.10.0").CompareTo(ReleaseVersion.Parse("v1.9.9")) > 0
            && ReleaseVersion.Parse("v2.0.0").CompareTo(ReleaseVersion.Parse("v1.99.99")) > 0
            && ReleaseVersion.Parse("v1.3.2").CompareTo(ReleaseVersion.Current) == 0
            && ReleaseVersion.Parse("v1.3.1").CompareTo(ReleaseVersion.Current) < 0, "update versions compare numerically including same/older releases");
        foreach (string version in new[] { "1.4.0", "v01.4.0", "v1.04.0", "v1.4", "v1.4.0.0", "v1.4.0-beta", "v1.4.0+build", "v-1.4.0", "v1.4.0\n", "v999999999999.0.0" })
            Reject(() => ReleaseVersion.Parse(version), "non-stable tag " + version);
        Reject(() => UpdateRelease.Parse(Mutate(root => root["draft"] = true)), "draft release");
        Reject(() => UpdateRelease.Parse(Mutate(root => root["prerelease"] = true)), "prerelease");
        Reject(() => UpdateRelease.Parse(Mutate(root => root.Remove("prerelease"))), "missing prerelease status");
        Reject(() => UpdateRelease.Parse(Mutate(root => root["html_url"] = "https://github.com/other/project/releases/tag/v1.4.0")), "wrong release repository");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["browser_download_url"] = UpdateRelease.Repository + "/releases/download/v9.9.9/" + UpdateRelease.AssetName)), "wrong asset tag");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["browser_download_url"] = "https://github.com/other/project/releases/download/v1.4.0/" + UpdateRelease.AssetName)), "wrong asset repository");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["browser_download_url"] = "https://example.com/" + UpdateRelease.AssetName)), "external asset URL");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["name"] = "alternate.msi")), "wrong asset filename");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["state"] = "new")), "incomplete upload");
        Reject(() => UpdateRelease.Parse(Mutate(root => root["assets"]!.AsArray().Add(Asset(root).DeepClone()))), "duplicate MSI assets");
        foreach (long size in new[] { -1L, 0L, UpdateRelease.DownloadLimit + 1 })
            Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["size"] = size)), "invalid declared asset size " + size);
        foreach (string digest in new[] { "", "sha256:abcd", "sha512:" + hash, "sha256:" + new string('g',64) })
            Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root)["digest"] = digest)), "missing or invalid digest");
        Reject(() => UpdateRelease.Parse(Mutate(root => Asset(root).Remove("digest"))), "absent digest");
        Reject(() => UpdateRelease.Parse(new byte[UpdateRelease.MetadataLimit + 1]), "oversized metadata");
        Reject(() => UpdateRelease.Parse(Encoding.UTF8.GetBytes("{\"draft\":false,\"draft\":true}")), "duplicate metadata key");

        foreach (string uri in new[] {
            "http://github.com/a", "https://github.com.evil.example/a", "https://evil.example/a",
            "https://user@github.com/a", "https://github.com:444/a", "https://release-assets.githubusercontent.com/a#fragment",
            "file:///C:/installer.msi"
        }) check(!UpdateClient.IsAllowedDownloadUri(new(uri)), "update refuses redirect destination " + uri);
        foreach (string host in new[] { "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com" })
            check(UpdateClient.IsAllowedDownloadUri(new("https://" + host + "/asset?token=public-test")), "update permits exact HTTPS GitHub host " + host);

        // Injected transport: no DNS, real HTTP request, UI prompt or installer execution.
        using (var handler = new FixtureTransport(request => {
            check(request.RequestUri == UpdateRelease.Feed && request.Headers.Authorization == null, "update uses the fixed unauthenticated metadata endpoint");
            return Json(Feed());
        }))
        using (var client = new UpdateClient(handler, NoInstall)) {
            var result = client.CheckAsync(CancellationToken.None).GetAwaiter().GetResult();
            check(result == release && handler.Requests == 1, "update check fetches metadata only");
            Reject(() => client.DownloadAsync(release, userApproved: false, CancellationToken.None).GetAwaiter().GetResult(), "download without approval");
            check(handler.Requests == 1, "declining an update makes no download request");
        }
        using (var handler = new FixtureTransport(_ => Redirect("https://api.github.com/elsewhere")))
        using (var client = new UpdateClient(handler, NoInstall)) {
            Reject(() => client.CheckAsync(CancellationToken.None).GetAwaiter().GetResult(), "metadata redirect");
            check(handler.Requests == 1, "metadata redirects are never followed");
        }
        using (var handler = new FixtureTransport(_ => Json(new byte[UpdateRelease.MetadataLimit + 1])))
        using (var client = new UpdateClient(handler, NoInstall))
            Reject(() => client.CheckAsync(CancellationToken.None).GetAwaiter().GetResult(), "oversized metadata HTTP response");
        foreach (string destination in new[] { "https://evil.example/payload", "http://release-assets.githubusercontent.com/payload", UpdateRelease.Repository + "/releases/download/v9.9.9/" + UpdateRelease.AssetName }) {
            using var handler = new FixtureTransport(_ => Redirect(destination));
            using var client = new UpdateClient(handler, NoInstall);
            Reject(() => client.DownloadAsync(release, userApproved: true, CancellationToken.None).GetAwaiter().GetResult(), "untrusted MSI redirect");
            check(handler.Requests == 1, "untrusted redirect stopped before a second request");
        }
        using (var handler = new FixtureTransport(_ => Redirect(release.Download.AbsoluteUri)))
        using (var client = new UpdateClient(handler, NoInstall)) {
            Reject(() => client.DownloadAsync(release, userApproved: true, CancellationToken.None).GetAwaiter().GetResult(), "redirect loop");
            check(handler.Requests == 6, "download redirect count bounded");
        }
        using (var handler = new FixtureTransport(request => request.RequestUri!.Host == "github.com"
            ? Redirect("https://release-assets.githubusercontent.com/fixture.msi")
            : new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(payload) }))
        using (var client = new UpdateClient(handler, NoInstall))
        using (var prepared = client.DownloadAsync(release, userApproved: true, CancellationToken.None).GetAwaiter().GetResult()) {
            check(handler.Requests == 2, "update follows an allowed GitHub asset redirect and verifies its staged bytes");
            Reject(() => prepared.LaunchAsync(userApproved: false, CancellationToken.None).GetAwaiter().GetResult(), "execution after download without install approval");
            // The download client deliberately retains successful MSI staging for the installer.
            // This fixture removes only its own tiny test file after releasing the handle below.
            string downloaded = prepared.InstallerPath;
            check(File.ReadAllText(downloaded + ":Zone.Identifier").Contains("ZoneId=3", StringComparison.Ordinal), "update retains Windows Internet-zone security marking");
            prepared.Dispose(); File.Delete(downloaded); Directory.Delete(Path.GetDirectoryName(downloaded)!);
        }
        using (var input = new MemoryStream(payload))
        using (var output = new MemoryStream()) {
            UpdateClient.CopyVerifiedAsync(input, output, release, CancellationToken.None).GetAwaiter().GetResult();
            check(output.ToArray().SequenceEqual(payload), "update bounded stream verifies full hash and exact size");
        }
        foreach (byte[] invalid in new[] { new byte[] {1,2,3}, new byte[] {1,2,3,4,5}, new byte[] {1,2,3,5} }) {
            using var input = new MemoryStream(invalid); using var output = new MemoryStream();
            Reject(() => UpdateClient.CopyVerifiedAsync(input, output, release, CancellationToken.None).GetAwaiter().GetResult(), "truncated, oversized or tampered MSI bytes");
            check(output.Length <= release.Size, "overrun bytes are never written to staging");
        }
        using (var input = new MemoryStream(payload))
        using (var output = new MemoryStream())
            Reject(() => UpdateClient.CopyVerifiedAsync(input, output, release with { Download = new("https://example.com/a.msi") }, CancellationToken.None).GetAwaiter().GetResult(), "forged descriptor");
        string directory = UpdateStorage.CreateStagingDirectory();
        string path = Path.Combine(directory, UpdateRelease.AssetName);
        try {
            File.WriteAllBytes(path, [1,2,3,5]);
            using (var changed = new PreparedUpdate(path, release, NoInstall)) {
                Reject(() => changed.VerifyAsync(CancellationToken.None).GetAwaiter().GetResult(), "staged installer tampering");
                Reject(() => changed.LaunchAsync(userApproved: true, CancellationToken.None).GetAwaiter().GetResult(), "launch after failed verification");
            }
            File.WriteAllBytes(path,payload);
            using (var prepared = new PreparedUpdate(path, release, NoInstall)) {
                prepared.VerifyAsync(CancellationToken.None).GetAwaiter().GetResult();
                Reject(() => prepared.LaunchAsync(userApproved: false, CancellationToken.None).GetAwaiter().GetResult(), "installer execution without approval");
                Reject(() => File.WriteAllBytes(path,[9,9,9,9]), "writes while verified installer is held");
                var command = InstallerGuard.Command();
                check(command.FileName == Path.Combine(Environment.SystemDirectory,"WindowsPowerShell","v1.0","powershell.exe") && !command.UseShellExecute
                    && command.ArgumentList.Take(4).SequenceEqual(new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand" })
                    && !command.ArgumentList.Contains("-ExecutionPolicy"), "update helper uses fixed OS host, immutable code and separate arguments without policy bypass");
            }
            // Exercise the real fixed OS helper with its harmless wait stand-in.
            // Closing the parent verifier simulates Zoomies exiting after acknowledgement.
            using (var parentLock = new PreparedUpdate(path, release, NoInstall)) {
                parentLock.VerifyAsync(CancellationToken.None).GetAwaiter().GetResult();
                using var helper = InstallerGuard.StartTestAsync(path, release, CancellationToken.None).GetAwaiter().GetResult();
                parentLock.Dispose();
                check(!helper.HasExited, "actual helper acknowledges independent lock ownership");
                Reject(() => File.WriteAllBytes(path,[8,8,8,8]), "MSI overwrite after the parent lock closes");
                Reject(() => File.Delete(path), "MSI deletion after the parent lock closes");
                Reject(() => File.Move(path, path + ".replaced"), "MSI rename after the parent lock closes");
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                helper.CompleteTestAsync(timeout.Token).GetAwaiter().GetResult();
                check(helper.HasExited, "actual helper holds lock until stand-in completion");
            }
            File.WriteAllBytes(path,payload);
            check(File.ReadAllBytes(path).SequenceEqual(payload), "installer lock releases after helper completion");
            Reject(() => InstallerGuard.StartTestAsync(path, release with { Sha256 = new string('0',64) }, CancellationToken.None).GetAwaiter().GetResult(), "helper independently rejects a mismatched hash before acknowledgement");
            Reject(() => InstallerGuard.StartTestAsync(path, release with { Size = 5 }, CancellationToken.None).GetAwaiter().GetResult(), "helper independently rejects a mismatched size before acknowledgement");
        } finally { File.Delete(path); Directory.Delete(directory); }
        check(installerCalls == 0, "update consent/verification guards never reached the injected installer launcher");
    }
    static HttpResponseMessage Json(byte[] data) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(data) };
    static HttpResponseMessage Redirect(string destination) {
        var result = new HttpResponseMessage(HttpStatusCode.Found); result.Headers.Location = new Uri(destination); return result;
    }
    sealed class FixtureTransport(Func<HttpRequestMessage,HttpResponseMessage> respond) : HttpMessageHandler {
        internal int Requests { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            token.ThrowIfCancellationRequested(); Requests++; return Task.FromResult(respond(request));
        }
    }
}
