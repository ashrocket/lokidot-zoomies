using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace LokiDot;

internal sealed class InstallerHandoffException(string message, Exception? inner = null) : IOException(message, inner);

// A fixed OS-hosted helper outlives the installed app without holding its binaries.
// All dynamic input is one bounded JSON line; it is never evaluated as script.
internal static class InstallerGuard
{
    const string Script = """
        $ErrorActionPreference = 'Stop'
        $PSModuleAutoLoadingPreference = 'None'
        $file = $null
        $child = $null
        $crypto = $null
        $code = 1
        try {
            $builder = [Text.StringBuilder]::new()
            while ($true) {
                $character = [Console]::In.Read()
                if ($character -lt 0) { throw 'Missing helper input.' }
                if ($character -eq 10) { break }
                if ($builder.Length -ge 4097) { throw 'Invalid helper input length.' }
                [void]$builder.Append([char]$character)
            }
            $line = $builder.ToString().TrimEnd([char]13)
            if ($line.Length -gt 4096) { throw 'Invalid helper input length.' }
            Import-Module -Name ([IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')) -ErrorAction Stop
            $data = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $line
            [string[]]$keys = @($data.PSObject.Properties.Name)
            [Array]::Sort($keys, [StringComparer]::Ordinal)
            if (($keys -join ',') -cne 'hash,nonce,path,size,tag,test') { throw 'Invalid helper input fields.' }
            if ($data.path -isnot [string] -or $data.hash -isnot [string] -or $data.nonce -isnot [string] -or $data.tag -isnot [string] -or $data.test -isnot [bool]) { throw 'Invalid helper input types.' }
            if ($data.hash -cnotmatch '\A[a-f0-9]{64}\z' -or $data.nonce -cnotmatch '\A[a-f0-9]{32}\z') { throw 'Invalid helper digest or nonce.' }
            if ($data.tag -cnotmatch '\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z') { throw 'Invalid helper version.' }
            $version = [Version]($data.tag.Substring(1))
            if ($version -le [Version]'__CURRENT_VERSION__') { throw 'Installer is not a newer version.' }
            if (($data.size -isnot [int] -and $data.size -isnot [long]) -or $data.size -le 0 -or $data.size -gt 536870912) { throw 'Invalid helper size.' }
            $path = $data.path
            if ($path -cnotmatch '\A[A-Za-z]:\\' -or $path.IndexOf('"') -ge 0) { throw 'Invalid local installer path.' }
            foreach ($character in $path.ToCharArray()) { if ([char]::IsControl($character)) { throw 'Installer path contains control characters.' } }
            if ([IO.Path]::GetFullPath($path) -cne $path -or [IO.Path]::GetFileName($path) -cne 'LokiDot-Zoomies-win-x64.msi') { throw 'Unexpected installer path.' }
            $folder = [IO.Path]::GetDirectoryName($path)
            $root = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'LokiDot', 'Zoomies', 'Updates')
            if (![string]::Equals([IO.Path]::GetDirectoryName($folder), $root, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($folder) -cnotmatch '\A[a-f0-9]{32}\z') { throw 'Installer is outside private update staging.' }
            $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($path))
            if ($drive.DriveType -eq [IO.DriveType]::Network) { throw 'Network update staging is not allowed.' }
            for ($node = [IO.DirectoryInfo]::new($folder); $null -ne $node; $node = $node.Parent) {
                if (($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked update staging is not allowed.' }
            }
            if (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked installer is not allowed.' }
            $file = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $crypto = [Security.Cryptography.SHA256]::Create()
            $hash = [BitConverter]::ToString($crypto.ComputeHash($file)).Replace('-', '').ToLowerInvariant()
            if ($file.Length -ne $data.size -or $hash -cne $data.hash) { throw 'Installer verification failed inside the helper.' }
            if ($data.test) {
                # The only test stand-in is a wait gate. It cannot name or run an executable.
                [Console]::Out.WriteLine(('READY|{0}|{1}|0' -f $data.nonce, $PID))
                [Console]::Out.Flush()
                $release = [Console]::In.ReadLine()
                if ($release -cne ('RELEASE|' + $data.nonce)) { throw 'Test stand-in release was not confirmed.' }
                $code = 0
            } else {
                $command = [Diagnostics.ProcessStartInfo]::new()
                $command.FileName = [IO.Path]::Combine([Environment]::SystemDirectory, 'msiexec.exe')
                $command.UseShellExecute = $false
                $command.WorkingDirectory = [Environment]::SystemDirectory
                # Windows PowerShell's .NET Framework lacks ArgumentList. This is native
                # process quoting of one absolute path: quotes/control characters were
                # rejected above, and its fixed .msi suffix cannot escape the closing quote.
                $command.Arguments = '/i "' + $path + '" /norestart'
                $child = [Diagnostics.Process]::Start($command)
                if ($null -eq $child) { throw 'Windows Installer did not start.' }
                try {
                    [Console]::Out.WriteLine(('READY|{0}|{1}|{2}' -f $data.nonce, $PID, $child.Id))
                    [Console]::Out.Flush()
                } catch { } # A closed parent pipe must never release the installer lock.
                $child.WaitForExit()
                $code = $child.ExitCode
            }
        } catch {
            # If anything fails after native launch, the child still owns the lifetime.
            # Never kill it or release verified bytes merely because acknowledgement failed.
            if ($null -ne $child) { try { $child.WaitForExit() } catch { } }
            try { [Console]::Error.WriteLine('Installer handoff failed: ' + $_.Exception.Message) } catch { }
        } finally {
            if ($null -ne $crypto) { $crypto.Dispose() }
            if ($null -ne $file) { $file.Dispose() }
            if ($null -ne $child) { $child.Dispose() }
        }
        exit $code
        """;

    internal static Task<InstallerGuardLease> StartAsync(string path, UpdateRelease release, CancellationToken token) => StartCoreAsync(path, release, test: false, token);
    internal static Task<InstallerGuardLease> StartTestAsync(string path, UpdateRelease release, CancellationToken token) => StartCoreAsync(path, release, test: true, token);

    internal static ProcessStartInfo Command()
    {
        var command = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")) {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            WorkingDirectory = Environment.SystemDirectory
        };
        command.Environment["PSModulePath"] = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "Modules");
        command.ArgumentList.Add("-NoLogo"); command.ArgumentList.Add("-NoProfile"); command.ArgumentList.Add("-NonInteractive");
        command.ArgumentList.Add("-EncodedCommand");
        command.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(Script.Replace("__CURRENT_VERSION__", ReleaseVersion.Current.ToString(), StringComparison.Ordinal))));
        return command;
    }
    static async Task<InstallerGuardLease> StartCoreAsync(string path, UpdateRelease release, bool test, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        UpdateClient.ValidateDescriptor(release);
        UpdateStorage.RequireLocalPath(path);
        string nonce = Guid.NewGuid().ToString("N");
        string data = JsonSerializer.Serialize(new { path, size = release.Size, hash = release.Sha256, nonce, tag = "v" + release.Version, test });
        SpritePack.Require(data.Length <= 4096, "The private installer path is too long for a safe handoff.");
        var process = Process.Start(Command()) ?? throw new IOException("The Windows installer helper could not start.");
        var lease = new InstallerGuardLease(process, nonce, test);
        // Drain diagnostics immediately so a failed helper cannot block on a full stderr pipe.
        Task<string> errors = process.StandardError.ReadToEndAsync();
        try {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(30));
            await process.StandardInput.WriteLineAsync(data.AsMemory(), deadline.Token).ConfigureAwait(false);
            await process.StandardInput.FlushAsync(deadline.Token).ConfigureAwait(false);
            if (!test) process.StandardInput.Close();
            string? acknowledgement = await process.StandardOutput.ReadLineAsync(deadline.Token).ConfigureAwait(false);
            var values = acknowledgement?.Split('|');
            bool valid = values is { Length: 4 } && values[0] == "READY" && values[1] == nonce
                && int.TryParse(values[2], out int guardPid) && guardPid == process.Id
                && int.TryParse(values[3], out int installerPid) && (test ? installerPid == 0 : installerPid > 0);
            SpritePack.Require(valid, "The installer helper did not confirm verified lock ownership.");
            // If a fast child already exited, the helper has completed its protected
            // lifetime; otherwise it still owns the lock independently of this app.
            if (process.HasExited && process.ExitCode != 0 && process.ExitCode != 3010)
                throw new IOException("Windows Installer ended before handoff completed.");
            return lease;
        } catch (Exception error) {
            // Do not kill a helper that may have launched msiexec. Keep this await
            // (and the caller's MSI lock) until it exits, even on cancellation/timeout.
            try { process.StandardInput.Close(); } catch (Exception closeError) when (closeError is IOException or InvalidOperationException) { }
            await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
            string detail = await errors.ConfigureAwait(false);
            lease.Dispose();
            throw new InstallerHandoffException("The installer handoff could not be confirmed. The helper was allowed to finish; check Windows Installer before trying again. " + detail.Trim(), error);
        }
    }
}

internal sealed class InstallerGuardLease(Process process, string nonce, bool test) : IDisposable
{
    internal int ProcessId => process.Id;
    internal bool HasExited => process.HasExited;
    internal async Task CompleteTestAsync(CancellationToken token)
    {
        SpritePack.Require(test, "Only the harmless helper stand-in accepts a release signal.");
        await process.StandardInput.WriteLineAsync(("RELEASE|" + nonce).AsMemory(), token).ConfigureAwait(false);
        await process.StandardInput.FlushAsync(token).ConfigureAwait(false);
        process.StandardInput.Close();
        await process.WaitForExitAsync(token).ConfigureAwait(false);
        SpritePack.Require(process.ExitCode == 0, "The helper stand-in did not finish successfully.");
    }
    // Disposing our process reference does not terminate the independent helper.
    public void Dispose() => process.Dispose();
}
