<#!
.SYNOPSIS
    PowerShell equivalent of set_github_secrets.sh to capture multi-cloud identifiers
    and push them as GitHub repository secrets via gh CLI.

.EXAMPLE
    ./scripts/set_github_secrets.ps1 -Repo OWNER/REPO -AzureClientId <guid> -AwsOidcRoleArn arn:aws:iam::123:role/capi -GcpWiProvider projects/.../providers/github -GcpServiceAccountEmail capi-terraform@proj.iam.gserviceaccount.com -LinodeToken <pat>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$Repo,
  [string]$AzureClientId = $env:AZURE_CLIENT_ID,
  [string]$AwsOidcRoleArn = $env:AWS_OIDC_ROLE_ARN,
  [string]$GcpWiProvider = $env:GCP_WORKLOAD_IDENTITY_PROVIDER,
  [string]$GcpServiceAccountEmail = $env:GCP_SERVICE_ACCOUNT_EMAIL,
  [string]$GcpProjectId = $env:GCP_PROJECT_ID,
  [string]$LinodeToken = $env:LINODE_TOKEN,
  [switch]$SkipAzure,
  [switch]$SkipAws,
  [switch]$SkipGcp,
  [switch]$SkipLinode,
  [switch]$NonInteractive
)

function Test-Tool($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return $false } else { return $true }
}

function Get-Value([string]$current, [string]$prompt, [bool]$required=$true) {
  if ($current) { return $current }
  if ($NonInteractive) { if ($required) { throw "Missing required value for $prompt" } else { return $null } }
  return Read-Host $prompt
}

if (-not (Test-Tool 'gh')) { throw 'gh CLI not installed' }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'gh not authenticated. Run: gh auth login' }

function Set-Secret($name, $value) {
  if (-not $value) { $msg = "Cannot set secret '{0}' - empty value" -f $name; throw $msg }
  $b = [System.Text.Encoding]::UTF8.GetBytes($value)
  $stdin = [System.IO.MemoryStream]::new($b)
  $si = New-Object System.Diagnostics.ProcessStartInfo
  $si.FileName = 'gh'
  $si.Arguments = "secret set $name --repo $Repo --body -"
  $si.RedirectStandardInput = $true
  $si.RedirectStandardOutput = $true
  $si.RedirectStandardError = $true
  $si.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($si)
  $stdin.CopyTo($p.StandardInput.BaseStream)
  $p.StandardInput.Close()
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { $msg = "Failed setting secret '{0}' - {1}" -f $name,$p.StandardError.ReadToEnd(); throw $msg }
  Write-Host ("Set secret '{0}'" -f $name) -ForegroundColor Green
}

if (-not $SkipAzure) {
  if (Test-Tool 'az') {
    $sub = (az account show --query id -o tsv 2>$null); if ($LASTEXITCODE -ne 0) { $sub = $null }
    $ten = (az account show --query tenantId -o tsv 2>$null); if ($LASTEXITCODE -ne 0) { $ten = $null }
  }
  $sub = Get-Value $sub 'Azure Subscription ID'
  $ten = Get-Value $ten 'Azure Tenant ID'
  $AzureClientId = Get-Value $AzureClientId 'Azure App Registration (Client) ID'
  Set-Secret AZURE_SUBSCRIPTION_ID $sub
  Set-Secret AZURE_TENANT_ID $ten
  Set-Secret AZURE_CLIENT_ID $AzureClientId
}

if (-not $SkipAws) {
  $AwsOidcRoleArn = Get-Value $AwsOidcRoleArn 'AWS OIDC Role ARN'
  Set-Secret AWS_OIDC_ROLE_ARN $AwsOidcRoleArn
}

if (-not $SkipGcp) {
  if (-not $GcpProjectId -and (Test-Tool 'gcloud')) {
    $GcpProjectId = (gcloud config get-value project 2>$null)
  }
  $GcpProjectId = Get-Value $GcpProjectId 'GCP Project ID'
  $GcpServiceAccountEmail = Get-Value $GcpServiceAccountEmail 'GCP Service Account Email'
  $GcpWiProvider = Get-Value $GcpWiProvider 'GCP Workload Identity Provider resource name'
  Set-Secret GCP_PROJECT_ID $GcpProjectId
  Set-Secret GCP_SERVICE_ACCOUNT_EMAIL $GcpServiceAccountEmail
  Set-Secret GCP_WORKLOAD_IDENTITY_PROVIDER $GcpWiProvider
}

if (-not $SkipLinode) {
  $LinodeToken = Get-Value $LinodeToken 'Linode Personal Access Token'
  Set-Secret LINODE_TOKEN $LinodeToken
}

Write-Host "All requested secrets set for $Repo" -ForegroundColor Cyan
