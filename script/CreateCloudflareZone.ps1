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

function Invoke-CloudflareApi {
  param(
    [string]$Method,
    [string]$Path,
    [string]$Token,
    [object]$Body = $null
  )

  $headers = @{ Authorization = "Bearer $Token" }
  $uri = "https://api.cloudflare.com/client/v4/$Path"
  $params = @{
    Method  = $Method
    Uri     = $uri
    Headers = $headers
  }

  if ($null -ne $Body) {
    $params.ContentType = "application/json"
    $params.Body = $Body | ConvertTo-Json -Compress -Depth 8
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    $message = $_.Exception.Message
    if ($null -ne $_.ErrorDetails -and $null -ne $_.ErrorDetails.Message) {
      $message = $_.ErrorDetails.Message
    }
    throw $message
  }
}

function Get-WorkingToken {
  $candidates = @()
  if ($env:CLOUDFLARE_API_TOKEN) {
    $candidates += [pscustomobject]@{ Source = ".env"; Token = $env:CLOUDFLARE_API_TOKEN }
  }

  $oauthToken = Get-WranglerOAuthToken
  if ($oauthToken) {
    $candidates += [pscustomobject]@{ Source = "wrangler"; Token = $oauthToken }
  }

  foreach ($candidate in $candidates) {
    try {
      $test = Invoke-CloudflareApi -Method Get -Path "accounts/$env:CLOUDFLARE_ACCOUNT_ID" -Token $candidate.Token
      if ($test.success) {
        Write-Host ("Using Cloudflare token from " + $candidate.Source)
        return $candidate.Token
      }
    } catch {
      Write-Host ("Skipping Cloudflare token from " + $candidate.Source + ": " + $_)
    }
  }

  throw "No Cloudflare token with account access was found."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-DotEnv -Path (Join-Path $repoRoot ".env")

if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
  throw "CLOUDFLARE_ACCOUNT_ID is required."
}

$domain = if ($env:CLOUDFLARE_CUSTOM_DOMAIN) { $env:CLOUDFLARE_CUSTOM_DOMAIN } else { "777x.space" }
$token = Get-WorkingToken

$existing = Invoke-CloudflareApi -Method Get -Path ("zones?name=" + [uri]::EscapeDataString($domain)) -Token $token
if ($existing.success -and $existing.result -and $existing.result.Count -gt 0) {
  $zone = $existing.result[0]
  Write-Host ("Zone already exists: " + $zone.name + " [" + $zone.status + "]")
  Write-Host "Nameservers:"
  $zone.name_servers | ForEach-Object { Write-Host $_ }
  exit 0
}

$body = @{
  name       = $domain
  account    = @{ id = $env:CLOUDFLARE_ACCOUNT_ID }
  type       = "full"
  jump_start = $true
}

$created = Invoke-CloudflareApi -Method Post -Path "zones" -Token $token -Body $body
if (-not $created.success) {
  throw ($created | ConvertTo-Json -Depth 8)
}

$zone = $created.result
Write-Host ("Created zone: " + $zone.name + " [" + $zone.status + "]")
Write-Host "Nameservers:"
$zone.name_servers | ForEach-Object { Write-Host $_ }
