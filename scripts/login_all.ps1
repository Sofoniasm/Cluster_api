Param(
  [string]$EnvFile = ".env"
)
$ErrorActionPreference = 'Stop'
if (Test-Path $EnvFile) {
  Write-Host "Loading $EnvFile"
  Get-Content $EnvFile | Where-Object {$_ -and ($_ -notmatch '^#')} | ForEach-Object {
    $k,$v = $_.Split('=',2)
    if ($k) { [System.Environment]::SetEnvironmentVariable($k,$v) }
  }
}
# Azure
if ($env:ARM_CLIENT_ID) {
  Write-Host "Azure: logging in with service principal"
  az login --service-principal --username $env:ARM_CLIENT_ID --password $env:ARM_CLIENT_SECRET --tenant $env:ARM_TENANT_ID | Out-Null
  if ($env:ARM_SUBSCRIPTION_ID) { az account set --subscription $env:ARM_SUBSCRIPTION_ID | Out-Null }
} else { Write-Host "Azure: skipping (ARM_CLIENT_ID not set)" }
# AWS
if ($env:AWS_ACCESS_KEY_ID) {
  Write-Host "AWS: credentials present (env vars)"
} else { Write-Host "AWS: skipping (AWS_ACCESS_KEY_ID not set)" }
# GCP
if ($env:GCP_SA_KEY_JSON) {
  Write-Host "GCP: writing inline service account JSON to .gcp-sa.json"
  $env:GCP_KEY_PATH = Join-Path (Get-Location) '.gcp-sa.json'
  [IO.File]::WriteAllText($env:GCP_KEY_PATH, $env:GCP_SA_KEY_JSON)
  $env:GOOGLE_APPLICATION_CREDENTIALS = $env:GCP_KEY_PATH
}
if ($env:GOOGLE_APPLICATION_CREDENTIALS) {
  gcloud auth activate-service-account --key-file $env:GOOGLE_APPLICATION_CREDENTIALS | Out-Null
  if ($env:GCP_PROJECT) { gcloud config set project $env:GCP_PROJECT | Out-Null }
} else { Write-Host "GCP: skipping (no credentials)" }

Write-Host 'Validation:'
try { az account show | Out-Null; Write-Host ' Azure OK' } catch { Write-Host ' Azure not logged in' }
try { aws sts get-caller-identity | Out-Null; Write-Host ' AWS OK' } catch { Write-Host ' AWS not logged in' }
try { gcloud auth list --filter=status:ACTIVE --format "value(account)" | Out-Null; Write-Host ' GCP OK' } catch { Write-Host ' GCP not logged in' }
Write-Host 'Done.'
