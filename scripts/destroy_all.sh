#!/usr/bin/env bash
set -euo pipefail

# Automated full destroy with Azure/GCP/AWS auth helpers and fallback partial destroy.
# Safe to re-run; idempotent until state is empty.

echo "[destroy] Starting Terraform destroy automation"

if ! command -v terraform >/dev/null 2>&1; then
  echo "[destroy][error] terraform CLI not found in PATH" >&2
  exit 1
fi

if [ ! -f "terraform.tfstate" ]; then
  echo "[destroy] No local terraform state file present (remote backend maybe). Running terraform init just in case." 
  terraform init -input=false -upgrade || true
fi

# Capture current resources (may be empty)
STATE_RESOURCES=$(terraform state list 2>/dev/null || true)

has_prefix() { case "$1" in $2*) return 0 ;; *) return 1 ;; esac }

# --- Azure auth helper ------------------------------------------------------
if echo "$STATE_RESOURCES" | grep -E '(^| )module\.azure|azurerm_' >/dev/null 2>&1; then
  if ! command -v az >/dev/null 2>&1; then
    echo "[destroy][warn] Azure resources in state but Azure CLI (az) not installed; Azure destroy will likely fail."
  else
    if ! az account show >/dev/null 2>&1; then
      echo "[destroy][info] Logging into Azure (interactive). Close browser when done." 
      az login --only-show-errors >/dev/null
    fi
    if az account show >/dev/null 2>&1; then
      SUB_ID=$(az account show --query id -o tsv)
      export ARM_SUBSCRIPTION_ID="$SUB_ID"
      echo "[destroy][info] Using Azure subscription $SUB_ID"
    else
      echo "[destroy][warn] Unable to establish Azure account; will attempt partial destroy excluding Azure."
    fi
  fi
fi

# --- GCP auth helper --------------------------------------------------------
if echo "$STATE_RESOURCES" | grep -E '(^| )google_' >/dev/null 2>&1; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "[destroy][warn] GCP resources present but gcloud not installed; ensure GOOGLE_APPLICATION_CREDENTIALS or ADC set."
  else
    if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
      echo "[destroy][info] Initiating GCP Application Default Credentials login." 
      gcloud auth application-default login || echo "[destroy][warn] GCP ADC login failed; continuing." 
    fi
  fi
fi

# --- AWS auth helper --------------------------------------------------------
if echo "$STATE_RESOURCES" | grep -E '(^| )module\.aws|aws_' >/dev/null 2>&1; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "[destroy][warn] AWS resources present but aws CLI not installed; ensure env vars or credentials file present." 
  else
    aws sts get-caller-identity >/dev/null 2>&1 || echo "[destroy][warn] AWS credentials not currently valid; relying on Terraform provider auth fallback."
  fi
fi

echo "[destroy] Executing full terraform destroy (first attempt)"
set +e
terraform destroy -auto-approve
DESTROY_EXIT=$?
set -e

if [ $DESTROY_EXIT -eq 0 ]; then
  echo "[destroy] Success: All resources destroyed."
  exit 0
fi

echo "[destroy][warn] Full destroy failed (exit $DESTROY_EXIT). Attempting partial non-Azure teardown (common when Azure auth missing)."

STATE_RESOURCES=$(terraform state list 2>/dev/null || true)
if [ -z "$STATE_RESOURCES" ]; then
  echo "[destroy] State already empty after failure path. Exiting."
  exit 0
fi

PARTIAL_TARGETS=()
while IFS= read -r RES; do
  # Skip empty lines
  [ -z "$RES" ] && continue
  if echo "$RES" | grep -E '(^| )azurerm_|module\.azure' >/dev/null 2>&1; then
    continue
  fi
  PARTIAL_TARGETS+=("-target=$RES")
done <<< "$STATE_RESOURCES"

if [ ${#PARTIAL_TARGETS[@]} -eq 0 ]; then
  echo "[destroy] No non-Azure resources left to destroy."
else
  echo "[destroy] Destroying non-Azure resources (${#PARTIAL_TARGETS[@]} targets)"
  terraform destroy -auto-approve "${PARTIAL_TARGETS[@]}" || echo "[destroy][warn] Partial destroy encountered errors; manual review needed."
fi

REMAINING=$(terraform state list 2>/dev/null || true)
if echo "$REMAINING" | grep -E '(^| )azurerm_|module\.azure' >/dev/null 2>&1; then
  echo "[destroy][info] Azure resources remain in state. After authenticating Azure, re-run this script to remove them." 
  echo "Remaining Azure entries:" 
  echo "$REMAINING" | grep -E '(^| )azurerm_|module\.azure'
  exit 2
fi

echo "[destroy] Completed partial destroy; no Azure resources found."
exit 0
