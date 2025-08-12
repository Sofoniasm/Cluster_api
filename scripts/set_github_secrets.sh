#!/usr/bin/env bash
set -euo pipefail

# Purpose: Collect (or prompt for) multi-cloud identifiers from current CLI sessions
# and push them as GitHub repository secrets via gh CLI.
#
# Derivation limits:
#  - AZURE_CLIENT_ID (service principal / app registration) cannot be inferred from a user login; supply via env or flag.
#  - AWS_OIDC_ROLE_ARN cannot be inferred automatically; supply via env or flag.
#  - GCP Workload Identity Provider resource name & Service Account email may need explicit input if multiple exist.
#  - LINODE_TOKEN cannot be read back after login; supply via env.
#
# Usage:
#   ./scripts/set_github_secrets.sh --repo OWNER/REPO \
#       [--azure-client-id <appId>] [--aws-oidc-role-arn <arn>] \
#       [--gcp-wi-provider <provider_resource_name>] \
#       [--gcp-sa-email <service_account_email>] \
#       [--non-interactive] [--skip-azure] [--skip-aws] [--skip-gcp] [--skip-linode]
#
# Pre-req: az, aws, gcloud, gh installed & authenticated (gh auth login).

REPO=""
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AWS_OIDC_ROLE_ARN="${AWS_OIDC_ROLE_ARN:-}"
GCP_WORKLOAD_IDENTITY_PROVIDER="${GCP_WORKLOAD_IDENTITY_PROVIDER:-}"
GCP_SERVICE_ACCOUNT_EMAIL="${GCP_SERVICE_ACCOUNT_EMAIL:-}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
LINODE_TOKEN="${LINODE_TOKEN:-}"
NON_INTERACTIVE=false
SKIP_AZURE=false
SKIP_AWS=false
SKIP_GCP=false
SKIP_LINODE=false

err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }

want_val() {
  local var="$1" prompt="$2" current="${!var:-}"; shift 2 || true
  if [ -n "$current" ]; then return 0; fi
  if $NON_INTERACTIVE; then err "Missing required value for $var (non-interactive)."; return 1; fi
  read -rp "$prompt: " val
  export "$var"="$val"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --azure-client-id) AZURE_CLIENT_ID="$2"; shift 2;;
    --aws-oidc-role-arn) AWS_OIDC_ROLE_ARN="$2"; shift 2;;
    --gcp-wi-provider) GCP_WORKLOAD_IDENTITY_PROVIDER="$2"; shift 2;;
    --gcp-sa-email) GCP_SERVICE_ACCOUNT_EMAIL="$2"; shift 2;;
    --non-interactive) NON_INTERACTIVE=true; shift;;
    --skip-azure) SKIP_AZURE=true; shift;;
    --skip-aws) SKIP_AWS=true; shift;;
    --skip-gcp) SKIP_GCP=true; shift;;
    --skip-linode) SKIP_LINODE=true; shift;;
    *) err "Unknown flag $1"; exit 1;;
  esac
done

if [ -z "$REPO" ]; then err "--repo OWNER/REPO is required"; exit 1; fi

if ! command -v gh >/dev/null 2>&1; then err "gh CLI not installed"; exit 1; fi
if ! gh auth status >/dev/null 2>&1; then err "gh not authenticated (run: gh auth login)"; exit 1; fi

set_secret() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then err "Cannot set secret $name: value empty"; return 1; fi
  printf "%s" "$value" | gh secret set "$name" --repo "$REPO" --body - >/dev/null
  info "Set secret $name"
}

# Azure
if ! $SKIP_AZURE; then
  if command -v az >/dev/null 2>&1; then
    if AZ_SUB_ID=$(az account show --query id -o tsv 2>/dev/null); then :; else AZ_SUB_ID=""; fi
    if AZ_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null); then :; else AZ_TENANT_ID=""; fi
    [ -z "$AZ_SUB_ID" ] && warn "Azure subscription id not auto-detected" || info "Azure subscription: $AZ_SUB_ID"
    [ -z "$AZ_TENANT_ID" ] && warn "Azure tenant id not auto-detected" || info "Azure tenant: $AZ_TENANT_ID"
  else
    warn "az CLI not found; skipping auto-detect"
  fi
  want_val AZ_SUB_ID "Azure Subscription ID" || exit 1
  want_val AZ_TENANT_ID "Azure Tenant ID" || exit 1
  want_val AZURE_CLIENT_ID "Azure App Registration (Client) ID" || exit 1
  set_secret AZURE_SUBSCRIPTION_ID "$AZ_SUB_ID"
  set_secret AZURE_TENANT_ID "$AZ_TENANT_ID"
  set_secret AZURE_CLIENT_ID "$AZURE_CLIENT_ID"
fi

# AWS
if ! $SKIP_AWS; then
  if [ -z "$AWS_OIDC_ROLE_ARN" ]; then
    if ! $NON_INTERACTIVE; then
      read -rp "Enter AWS OIDC Role ARN (e.g., arn:aws:iam::123456789012:role/capi-gh-oidc): " AWS_OIDC_ROLE_ARN || true
    fi
  fi
  [ -z "$AWS_OIDC_ROLE_ARN" ] && { err "AWS_OIDC_ROLE_ARN required"; exit 1; }
  set_secret AWS_OIDC_ROLE_ARN "$AWS_OIDC_ROLE_ARN"
fi

# GCP
if ! $SKIP_GCP; then
  if command -v gcloud >/dev/null 2>&1; then
    if [ -z "$GCP_PROJECT_ID" ]; then GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true); fi
  fi
  want_val GCP_PROJECT_ID "GCP Project ID" || exit 1
  if [ -z "$GCP_SERVICE_ACCOUNT_EMAIL" ] && ! $NON_INTERACTIVE; then
    read -rp "GCP Service Account Email (for Terraform/CAPI): " GCP_SERVICE_ACCOUNT_EMAIL || true
  fi
  [ -z "$GCP_SERVICE_ACCOUNT_EMAIL" ] && { err "GCP Service Account Email required"; exit 1; }
  if [ -z "$GCP_WORKLOAD_IDENTITY_PROVIDER" ] && ! $NON_INTERACTIVE; then
    read -rp "GCP Workload Identity Provider resource name (projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>): " GCP_WORKLOAD_IDENTITY_PROVIDER || true
  fi
  [ -z "$GCP_WORKLOAD_IDENTITY_PROVIDER" ] && { err "GCP Workload Identity Provider required"; exit 1; }
  set_secret GCP_PROJECT_ID "$GCP_PROJECT_ID"
  set_secret GCP_SERVICE_ACCOUNT_EMAIL "$GCP_SERVICE_ACCOUNT_EMAIL"
  set_secret GCP_WORKLOAD_IDENTITY_PROVIDER "$GCP_WORKLOAD_IDENTITY_PROVIDER"
fi

# Linode
if ! $SKIP_LINODE; then
  if [ -z "$LINODE_TOKEN" ] && ! $NON_INTERACTIVE; then
    read -rp "Linode Personal Access Token: " LINODE_TOKEN || true
  fi
  [ -z "$LINODE_TOKEN" ] && { err "LINODE_TOKEN required for Linode secret"; exit 1; }
  set_secret LINODE_TOKEN "$LINODE_TOKEN"
fi

info "All requested secrets set for $REPO"
