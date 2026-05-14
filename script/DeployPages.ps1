$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Import-DotEnv {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw ".env not found at $Path"
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      return
    }
    $parts = $line -split "=", 2
    if ($parts.Count -ne 2) {
      return
    }
    [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
    Set-Item -Path ("Env:" + $parts[0]) -Value $parts[1]
  }
}

function Get-WranglerOAuthToken {
  $configPath = Join-Path $env:USERPROFILE ".wrangler\config\default.toml"
  if (-not (Test-Path -LiteralPath $configPath)) {
    return $null
  }

  $match = Select-String -LiteralPath $configPath -Pattern '^oauth_token\s*=\s*"([^"]+)"' | Select-Object -First 1
  if (-not $match) {
    return $null
  }

  return $match.Matches[0].Groups[1].Value
}

function Test-CloudflarePagesToken {
  param(
    [string]$AccountId,
    [string]$ProjectName,
    [string]$ApiToken
  )

  if (-not $ApiToken) {
    return $false
  }

  $headers = @{ Authorization = "Bearer $ApiToken" }
  $uri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$ProjectName"

  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    return [bool]$response.success
  } catch {
    return $false
  }
}

function Resolve-CloudflareApiToken {
  param(
    [string]$AccountId,
    [string]$ProjectName
  )

  $candidates = @()
  if ($env:CLOUDFLARE_API_TOKEN) {
    $candidates += [pscustomobject]@{
      Source = ".env"
      Token  = $env:CLOUDFLARE_API_TOKEN
    }
  }

  $oauthToken = Get-WranglerOAuthToken
  if ($oauthToken) {
    $candidates += [pscustomobject]@{
      Source = "wrangler"
      Token  = $oauthToken
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-CloudflarePagesToken -AccountId $AccountId -ProjectName $ProjectName -ApiToken $candidate.Token) {
      Write-Host ("Using Cloudflare token from " + $candidate.Source)
      return $candidate.Token
    }
  }

  throw "No Cloudflare token with Pages project access was found."
}

function Invoke-WranglerClean {
  param(
    [string]$WorkingDirectory,
    [string[]]$Arguments,
    [string]$ApiToken
  )

  $argString = ($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join " "
  $xdgConfigHome = Join-Path $env:APPDATA "xdg.config"
  $script = @"
[System.Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN', '$ApiToken', 'Process')
`$env:CLOUDFLARE_API_TOKEN = '$ApiToken'
[System.Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', '$xdgConfigHome', 'Process')
`$env:XDG_CONFIG_HOME = '$xdgConfigHome'
Push-Location "$WorkingDirectory"
try {
  npx -y wrangler@4.86.0 $argString
  `$exitVar = Get-Variable LASTEXITCODE -ErrorAction SilentlyContinue
  if (`$null -eq `$exitVar) {
    exit 0
  }
  exit `$exitVar.Value
} finally {
  Pop-Location
}
"@
  & powershell -NoProfile -Command $script
  if ($LASTEXITCODE -ne 0) {
    throw "Wrangler command failed: $($Arguments -join ' ')"
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-DotEnv -Path (Join-Path $repoRoot ".env")

$projectName = $env:CLOUDFLARE_PAGES_PROJECT
$branch = if ($env:CLOUDFLARE_PAGES_BRANCH) { $env:CLOUDFLARE_PAGES_BRANCH } else { "main" }
$siteDir = if ($env:CLOUDFLARE_PAGES_DIR) { Join-Path $repoRoot $env:CLOUDFLARE_PAGES_DIR } else { Join-Path $repoRoot "web" }
$wranglerCwd = Join-Path $env:TEMP "forv-pages-wrangler"

if (-not $projectName) {
  throw "CLOUDFLARE_PAGES_PROJECT is required."
}

if (-not (Test-Path -LiteralPath $siteDir)) {
  throw "Pages directory not found: $siteDir"
}

$resolvedToken = Resolve-CloudflareApiToken -AccountId $env:CLOUDFLARE_ACCOUNT_ID -ProjectName $projectName

New-Item -ItemType Directory -Force -Path $wranglerCwd | Out-Null

Write-Host "Deploying Pages project: $projectName"
Invoke-WranglerClean -WorkingDirectory $wranglerCwd -Arguments @(
  "pages",
  "deploy",
  $siteDir,
  "--project-name",
  $projectName,
  "--branch",
  $branch
) -ApiToken $resolvedToken

Write-Host "Attaching custom domains via Cloudflare API"
try {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "AddPagesDomain.ps1")
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Custom domain attach failed."
  }
} catch {
  Write-Warning ("Custom domain attach failed: " + $_.Exception.Message)
}
