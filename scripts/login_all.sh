#!/usr/bin/env bash
set -euo pipefail
# Multi-cloud non-interactive login helper.
# Sources .env if present for secrets.
if [ -f .env ]; then
  echo "Loading .env" >&2
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -0 2>/dev/null || grep -v '^#' .env | xargs) || true
fi

# Azure Service Principal login (expects ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID)
if [ -n "${ARM_CLIENT_ID:-}" ]; then
  echo "Azure: logging in with service principal"
  az login --service-principal \
    --username "$ARM_CLIENT_ID" \
    --password "$ARM_CLIENT_SECRET" \
    --tenant   "$ARM_TENANT_ID" >/dev/null
  az account set --subscription "$ARM_SUBSCRIPTION_ID"
else
  echo "Azure: skipping (ARM_CLIENT_ID not set)" >&2
fi

# AWS login via access keys (expects AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, optional AWS_SESSION_TOKEN, AWS_DEFAULT_REGION)
if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
  echo "AWS: exporting credentials env vars"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${aws_region:-us-east-1}}"
else
  echo "AWS: skipping (AWS_ACCESS_KEY_ID not set)" >&2
fi

# GCP service account JSON (expects GOOGLE_APPLICATION_CREDENTIALS path OR inline GCP_SA_KEY_JSON)
if [ -n "${GCP_SA_KEY_JSON:-}" ]; then
  echo "GCP: writing service account key to .gcp-sa.json"
  printf '%s' "$GCP_SA_KEY_JSON" > .gcp-sa.json
  export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/.gcp-sa.json"
fi
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  echo "GCP: activating service account"
  gcloud auth activate-service-account --key-file "$GOOGLE_APPLICATION_CREDENTIALS" >/dev/null
  if [ -n "${gcp_project:-${GCP_PROJECT:-}}" ]; then
    gcloud config set project "${gcp_project:-${GCP_PROJECT}}" >/dev/null
  fi
else
  echo "GCP: skipping (no credentials)" >&2
fi

echo "Validation:"
az account show --output none 2>/dev/null && echo " Azure OK" || echo " Azure not logged in"
aws sts get-caller-identity >/dev/null 2>&1 && echo " AWS OK" || echo " AWS not logged in"
gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1 && echo " GCP OK" || echo " GCP not logged in"

echo "All login attempts done."
