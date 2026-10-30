$ErrorActionPreference = 'Stop'
$serviceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$resultsRoot = [System.IO.Path]::GetFullPath((Join-Path $serviceRoot 'results'))
$archiveRoot = [System.IO.Path]::GetFullPath((Join-Path $resultsRoot 'archive/2026-10-22'))
$planPath = Join-Path $PSScriptRoot 'plan.json'
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $plan.moves) {
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $serviceRoot $entry.old))
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $serviceRoot $entry.new))
    if ((Split-Path -Parent $sourcePath) -ne $resultsRoot) { throw "Source escapes top-level results: $sourcePath" }
    if (-not $targetPath.StartsWith($archiveRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Destination escapes archive: $targetPath" }
    if (Test-Path -LiteralPath $targetPath) { throw "Destination already exists: $targetPath" }
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Source checksum changed: $sourcePath" }
}
foreach ($entry in $plan.moves) {
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $serviceRoot $entry.old))
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $serviceRoot $entry.new))
    $targetFolder = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetFolder)) { New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null }
    Move-Item -LiteralPath $sourcePath -Destination $targetPath
    if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Moved checksum differs: $targetPath" }
}
Write-Output "Archived $($plan.moves.Count) files without deleting evidence."
