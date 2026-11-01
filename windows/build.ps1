param([string]$Output = "$PSScriptRoot/artifacts")
$ErrorActionPreference = 'Stop'
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force $Output | Out-Null
# Every payload and deliverable starts in a new directory. Previous runs remain intact.
$run = Join-Path $Output ("runs/" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $run | Out-Null
$publish = Join-Path $run 'publish'
dotnet publish "$PSScriptRoot/LokiDot.Windows/LokiDot.Windows.csproj" -c Release -r win-x64 --self-contained true -o $publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

# Inspect the whole Characters tree, including hidden entries. No nested directories,
# extra files, links or reparse points may enter either download.
$characters = Join-Path $publish 'Characters'
if (!(Test-Path -LiteralPath $characters -PathType Container)) { throw 'Missing Characters payload' }
$tree = @((Get-Item -LiteralPath $characters -Force)) + @(Get-ChildItem -LiteralPath $characters -Force -Recurse)
if (@($tree | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -ne 0) {
    throw 'Characters payload contains a link or reparse point'
}
$directories = @($tree | Where-Object { $_.PSIsContainer -and $_.FullName -ne $characters } | ForEach-Object { [IO.Path]::GetRelativePath($characters, $_.FullName).Replace('\', '/') } | Sort-Object)
if (($directories -join ',') -ne 'beagle,robot-loki,whippet') { throw "Unexpected Characters directories: $directories" }
$files = @($tree | Where-Object { !$_.PSIsContainer } | ForEach-Object { [IO.Path]::GetRelativePath($characters, $_.FullName).Replace('\', '/') } | Sort-Object)
$expected = @('beagle/atlas.png', 'beagle/manifest.json', 'robot-loki/atlas.png', 'robot-loki/manifest.json', 'whippet/atlas.png', 'whippet/manifest.json')
if (($files -join ',') -ne ($expected -join ',')) { throw "Unexpected Characters files: $files" }

$zipName = 'LokiDot-Zoomies-win-x64.zip'
$msiName = 'LokiDot-Zoomies-win-x64.msi'
Compress-Archive -Path "$publish/*" -DestinationPath "$run/$zipName"
$tools = Join-Path $Output 'tools'
# See official WiX tool / Files schema references in docs/windows.md.
if (!(Test-Path "$tools/wix.exe")) {
    dotnet tool install wix --version 5.0.2 --allow-roll-forward --tool-path $tools
    if ($LASTEXITCODE -ne 0) { throw 'WiX installation failed' }
}
$version = & "$tools/wix.exe" --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^5\.0\.2(?:[.+-]|$)') { throw "Expected pinned WiX 5.0.2; found $version" }
& "$tools/wix.exe" build "$PSScriptRoot/installer/Package.wxs" -arch x64 -d "PublishDir=$publish" -o "$run/$msiName"
if ($LASTEXITCODE -ne 0) { throw 'WiX build failed' }
Get-FileHash "$run/$zipName", "$run/$msiName" | Format-Table | Out-String | Set-Content "$run/SHA256.txt"
# Stable current-run entry points; the complete original output remains under runs/<id>.
Copy-Item -LiteralPath "$run/$zipName", "$run/$msiName", "$run/SHA256.txt" -Destination $Output -Force
Set-Content -LiteralPath "$Output/publish-path.txt" -Value $publish -NoNewline
Set-Content -LiteralPath "$Output/run-path.txt" -Value $run -NoNewline
Write-Host "Current verified publish directory: $publish"
