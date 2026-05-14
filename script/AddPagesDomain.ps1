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
    [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1])
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

function Add-PagesDomain {
  param(
    [string]$AccountId,
    [string]$ProjectName,
    [string]$ApiToken,
    [string]$Domain
  )

  if (-not $Domain) {
    return
  }

  $headers = @{
    Authorization = "Bearer $ApiToken"
  }

  $uri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$ProjectName/domains"
  $body = @{ name = $Domain } | ConvertTo-Json -Compress

  $existing = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
  if ($existing.success -and $existing.result) {
    $matched = $existing.result | Where-Object { $_.name -eq $Domain } | Select-Object -First 1
    if ($matched) {
      Write-Host ("Domain already attached: " + $Domain + " [" + $matched.status + "]")
      return
    }
  }

  try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $body
    Write-Host ("Attached domain: " + $Domain)
    $response | ConvertTo-Json -Depth 8 | Write-Host
  } catch {
    $message = $_.Exception.Message
    if ($null -ne $_.ErrorDetails -and $null -ne $_.ErrorDetails.Message) {
      $message = $_.ErrorDetails.Message
    } elseif ($_.Exception.Response -and $_.Exception.Response.GetResponseStream) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $raw = $reader.ReadToEnd()
      if ($raw) {
        $message = $raw
      }
    }
    if ($message -match "already exists" -or $message -match "custom domain is already in use") {
      Write-Host ("Domain already attached: " + $Domain)
      return
    }
    throw $message
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-DotEnv -Path (Join-Path $repoRoot ".env")

$accountId = $env:CLOUDFLARE_ACCOUNT_ID
$projectName = $env:CLOUDFLARE_PAGES_PROJECT
$rootDomain = $env:CLOUDFLARE_CUSTOM_DOMAIN
$wwwDomain = $env:CLOUDFLARE_CUSTOM_DOMAIN_WWW

if (-not $accountId) {
  throw "CLOUDFLARE_ACCOUNT_ID is required."
}
if (-not $projectName) {
  throw "CLOUDFLARE_PAGES_PROJECT is required."
}

$apiToken = Resolve-CloudflareApiToken -AccountId $accountId -ProjectName $projectName

Add-PagesDomain -AccountId $accountId -ProjectName $projectName -ApiToken $apiToken -Domain $rootDomain
Add-PagesDomain -AccountId $accountId -ProjectName $projectName -ApiToken $apiToken -Domain $wwwDomain
