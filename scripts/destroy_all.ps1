<#
Automated Terraform destroy with cloud auth helpers (Azure/GCP/AWS) and fallback partial destroy.
Usage: pwsh ./scripts/destroy_all.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[destroy] Starting Terraform destroy automation (PowerShell)"

function Test-Command($Name) { Get-Command $Name -ErrorAction SilentlyContinue | ForEach-Object { return $true }; return $false }

if (-not (Test-Command terraform)) { Write-Error "terraform CLI not found in PATH" }

if (-not (Test-Path terraform.tfstate)) {
  Write-Host "[destroy] No local state file; running terraform init (might be remote backend)."
  terraform init -input=false -upgrade | Out-Null
}

try { $stateResources = terraform state list 2>$null } catch { $stateResources = @() }

# Azure helper
if ($stateResources | Where-Object { $_ -match '^(module\.azure|azurerm_)' }) {
  if (Test-Command az) {
    if (-not (az account show 1>$null 2>$null; if($LASTEXITCODE -eq 0){$true}else{$false})) {
      Write-Host "[destroy] Logging into Azure..."; az login --only-show-errors | Out-Null
    }
    if (az account show 1>$null 2>$null; if($LASTEXITCODE -eq 0){$true}else{$false}) {
      $subId = az account show --query id -o tsv
      $env:ARM_SUBSCRIPTION_ID = $subId
      Write-Host "[destroy] Using Azure subscription $subId"
    } else {
      Write-Warning "Azure auth unavailable; Azure resources may block destroy."
    }
  } else {
    Write-Warning "Azure CLI not installed; Azure resources may block destroy."
  }
}

# GCP helper
if ($stateResources | Where-Object { $_ -match '^google_' }) {
  if (Test-Command gcloud) {
    if (-not (gcloud auth application-default print-access-token 1>$null 2>$null; if($LASTEXITCODE -eq 0){$true}else{$false})) {
      Write-Host "[destroy] Initiating GCP ADC login..."
      try { gcloud auth application-default login | Out-Null } catch { Write-Warning "GCP ADC login failed" }
    }
  } else { Write-Warning "gcloud not installed; ensure GOOGLE_APPLICATION_CREDENTIALS is set" }
}

# AWS helper
if ($stateResources | Where-Object { $_ -match '^(module\.aws|aws_)' }) {
  if (Test-Command aws) {
    aws sts get-caller-identity 1>$null 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "AWS credentials not currently valid; relying on provider fallback" }
  } else { Write-Warning "aws CLI not installed; ensure credentials are configured" }
}

Write-Host "[destroy] Executing full terraform destroy (first attempt)"
terraform destroy -auto-approve
if ($LASTEXITCODE -eq 0) { Write-Host "[destroy] Success: All resources destroyed."; exit 0 }

Write-Warning "Full destroy failed (exit $LASTEXITCODE). Attempting partial non-Azure teardown."
try { $stateResources = terraform state list 2>$null } catch { $stateResources = @() }
if (-not $stateResources) { Write-Host "[destroy] State empty after failure path."; exit 0 }

$partialTargets = @()
foreach ($r in $stateResources) { if ($r -notmatch '^(module\.azure|azurerm_)') { $partialTargets += "-target=$r" } }

if ($partialTargets.Count -gt 0) {
  Write-Host "[destroy] Destroying non-Azure resources ($($partialTargets.Count) targets)"
  terraform destroy -auto-approve $partialTargets
}

try { $remaining = terraform state list 2>$null } catch { $remaining = @() }
if ($remaining | Where-Object { $_ -match '^(module\.azure|azurerm_)' }) {
  Write-Host "[destroy] Azure resources still remain. Authenticate with Azure and re-run script." -ForegroundColor Yellow
  ($remaining | Where-Object { $_ -match '^(module\.azure|azurerm_)' }) | ForEach-Object { Write-Host "  $_" }
  exit 2
}

Write-Host "[destroy] Partial destroy complete; no Azure resources remain."; exit 0
