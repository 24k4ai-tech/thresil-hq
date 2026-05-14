$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot "777jpg"
$assetDir = Join-Path $repoRoot "web\assets"

if (-not (Test-Path -LiteralPath $sourceDir)) {
  throw "Source image folder not found: $sourceDir"
}

$images = @(Get-ChildItem -LiteralPath $sourceDir -File |
  Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } |
  Sort-Object Name)

if ($images.Count -eq 0) {
  throw "No images found in $sourceDir"
}

New-Item -ItemType Directory -Force -Path $assetDir | Out-Null

$targets = @(
  "casino-playbig.jpg",
  "cr7-casino-white.jpg",
  "musk-cr7-kobe.jpg",
  "oracle777-og-card-wide.jpg"
)

$assetIndex = 0
foreach ($image in $images) {
  $targetName = if ($assetIndex -lt $targets.Count) { $targets[$assetIndex] } else { "oracle777-extra-$assetIndex.jpg" }
  Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $assetDir $targetName) -Force
  ++$assetIndex
}

$logoSource = $images[$images.Count - 1]
Copy-Item -LiteralPath $logoSource.FullName -Destination (Join-Path $assetDir "oracle777-logo.jpg") -Force

Write-Host ("Synced " + $images.Count + " images from " + $sourceDir)
Write-Host ("Logo/banner source: " + $logoSource.Name)
