param([string]$Artifacts = "$PSScriptRoot/artifacts", [switch]$PortableOnly)
$ErrorActionPreference = 'Stop'
$Artifacts = [IO.Path]::GetFullPath($Artifacts)
$publish = (Get-Content -LiteralPath "$Artifacts/publish-path.txt" -Raw).Trim()
$run = (Get-Content -LiteralPath "$Artifacts/run-path.txt" -Raw).Trim()
if (!(Test-Path -LiteralPath $publish -PathType Container) -or [IO.Path]::GetDirectoryName($publish) -ne $run) { throw 'Current publish receipt is missing or inconsistent; run build.ps1 successfully first' }
$evidence = Join-Path $run 'evidence'
# CI discovers the current evidence without guessing a staging directory.
Set-Content -LiteralPath "$Artifacts/evidence-path.txt" -Value $evidence -NoNewline
New-Item -ItemType Directory -Force $evidence | Out-Null
$msi = Join-Path $run 'LokiDot-Zoomies-win-x64.msi'
$installed = Join-Path $env:ProgramFiles 'LokiDot Zoomies Preview'
$exe = Join-Path $installed 'LokiDot.Zoomies.exe'
$shortcut = Join-Path $env:ProgramData 'Microsoft/Windows/Start Menu/Programs/LokiDot Zoomies Preview/LokiDot Zoomies Preview.lnk'

function Msi([string[]]$MsiArgs) {
    $p = Start-Process msiexec.exe -ArgumentList $MsiArgs -Wait -PassThru
    if ($p.ExitCode -notin 0,3010) { throw "msiexec failed: $($p.ExitCode)" }
}
function SelfTest([string]$Program, [string]$Evidence) {
    $p = Start-Process $Program -ArgumentList @('--self-test', '--evidence', "`"$Evidence`"") -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Self-test failed: $($p.ExitCode). See $Evidence" }
}
SelfTest "$publish/LokiDot.Zoomies.exe" "$evidence/portable"
if ($PortableOnly) { return }
if (Test-Path $installed) { throw 'Clean-install prerequisite failed: install folder exists' }
try {
    Msi -MsiArgs @('/i', "`"$msi`"", '/qn', '/norestart', '/l*v', "`"$evidence/install.log`"")
    if (!(Test-Path $exe) -or !(Test-Path $shortcut)) { throw 'Installed app or Start Menu shortcut missing' }
    SelfTest $exe "$evidence/installed"
    # WaitForInputIdle can return when any thread becomes idle, before WPF has
    # decoded the bundled atlases and shown the controller. Observe the actual
    # window instead, with a deadline and a receipt for every failure/success.
    $startup = Start-Process $exe -WorkingDirectory $installed -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $trace = Join-Path $evidence 'startup.txt'
    "Normal entry point PID=$($startup.Id); expected title=LokiDot Zoomies — Windows preview" | Set-Content $trace
    try {
        $ready = $false
        while ($watch.Elapsed.TotalSeconds -lt 30) {
            $startup.Refresh()
            if ($startup.HasExited) {
                "Exited after $($watch.ElapsedMilliseconds) ms; code=$($startup.ExitCode)" | Add-Content $trace
                throw "App exited before its controls window was ready; see $trace"
            }
            $handle = $startup.MainWindowHandle
            $title = $startup.MainWindowTitle
            $responding = $handle -ne 0 -and $startup.Responding
            "elapsedMs=$($watch.ElapsedMilliseconds) handle=$handle responding=$responding title=$title" | Add-Content $trace
            if ($handle -ne 0 -and $title -eq 'LokiDot Zoomies — Windows preview' -and $responding) {
                $ready = $true
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (!$ready) { throw "App did not create a responsive controls window within 30 seconds; see $trace" }
        "PASS actual controls window ready after $($watch.ElapsedMilliseconds) ms" | Add-Content $trace
        if (!$startup.CloseMainWindow()) { throw 'Could not close app normally' }
        if (!$startup.WaitForExit(15000) -or $startup.ExitCode -ne 0) { throw 'App did not exit normally' }
        'PASS normal close exited with code 0' | Add-Content $trace
    } finally { if (!$startup.HasExited) { $startup.Kill(); $startup.WaitForExit() } }
    'PASS clean MSI install, Start Menu shortcut, installed self-test, normal startup and close' | Set-Content "$evidence/lifecycle.txt"
} finally {
    Msi -MsiArgs @('/x', "`"$msi`"", '/qn', '/norestart', '/l*v', "`"$evidence/uninstall.log`"")
}
if ((Test-Path $installed) -or (Test-Path $shortcut) -or (Test-Path 'HKLM:/Software/LokiDot/ZoomiesPreview')) { throw 'Uninstall left app, shortcut or registry marker behind' }
'PASS uninstall removed app, shortcut and registry marker' | Add-Content "$evidence/lifecycle.txt"
