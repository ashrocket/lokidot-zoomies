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
    # Normal entry point must remain alive and create its controls window.
    $startup = Start-Process $exe -PassThru
    try {
        if (!$startup.WaitForInputIdle(15000)) { throw 'App did not become input-idle' }
        $startup.Refresh()
        if ($startup.HasExited -or $startup.MainWindowHandle -eq 0) { throw 'App startup did not create a controls window' }
        if (!$startup.CloseMainWindow()) { throw 'Could not close app normally' }
        if (!$startup.WaitForExit(15000) -or $startup.ExitCode -ne 0) { throw 'App did not exit normally' }
    } finally { if (!$startup.HasExited) { $startup.Kill(); $startup.WaitForExit() } }
    'PASS clean MSI install, Start Menu shortcut, installed self-test, normal startup and close' | Set-Content "$evidence/lifecycle.txt"
} finally {
    Msi -MsiArgs @('/x', "`"$msi`"", '/qn', '/norestart', '/l*v', "`"$evidence/uninstall.log`"")
}
if ((Test-Path $installed) -or (Test-Path $shortcut) -or (Test-Path 'HKLM:/Software/LokiDot/ZoomiesPreview')) { throw 'Uninstall left app, shortcut or registry marker behind' }
'PASS uninstall removed app, shortcut and registry marker' | Add-Content "$evidence/lifecycle.txt"
