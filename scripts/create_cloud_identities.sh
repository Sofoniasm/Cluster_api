#!/usr/bin/env bash
set -euo pipefail
# Automated (idempotent where possible) creation of OIDC / Workload Identity plumbing
# for Azure, AWS, GCP to permit GitHub Actions OIDC federation without static secrets.
# Linode only needs a PAT (manual).
#
# REQUIREMENTS:
#   - az (>=2.45), aws, gcloud CLIs authenticated with org/subscription level perms.
#   - jq
#   - Environment variables below or pass flags:
#       GITHUB_REPO (e.g. owner/repo)
#       AZ_SUBSCRIPTION_ID (current if omitted)
#       AZ_TENANT_ID (auto-detect)
#       AZ_APP_DISPLAY_NAME (default: capi-gh-oidc)
#       AWS_ACCOUNT_ID (auto from sts)
#       AWS_ROLE_NAME (default: capi-gh-oidc)
#       GCP_PROJECT_ID (current gcloud config if omitted)
#       GCP_POOL_ID (default: capi-pool)
#       GCP_PROVIDER_ID (default: github)
#       GCP_SA_NAME (default: capi-terraform)
#       BRANCH_REF (default: refs/heads/main)
#
# OUTPUT: prints export lines for GitHub secrets.
# NOTE: Adjust IAM policies for least-privilege before production.

GITHUB_REPO="${GITHUB_REPO:-}"
AZ_APP_DISPLAY_NAME="${AZ_APP_DISPLAY_NAME:-capi-gh-oidc}"
AWS_ROLE_NAME="${AWS_ROLE_NAME:-capi-gh-oidc}"
GCP_POOL_ID="${GCP_POOL_ID:-capi-pool}"
GCP_PROVIDER_ID="${GCP_PROVIDER_ID:-github}"
GCP_SA_NAME="${GCP_SA_NAME:-capi-terraform}"
BRANCH_REF="${BRANCH_REF:-refs/heads/main}"

err(){ echo "[ERROR] $*" >&2; }
info(){ echo "[INFO]  $*"; }

[ -z "$GITHUB_REPO" ] && { err "Set GITHUB_REPO=owner/repo"; exit 1; }
REPO_OWNER=${GITHUB_REPO%%/*}
REPO_NAME=${GITHUB_REPO##*/}

# Azure -----------------------------------------------------------------
if command -v az >/dev/null 2>&1; then
  info "Azure: detecting subscription/tenant"
  AZ_SUBSCRIPTION_ID=${AZ_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)} || true
  AZ_TENANT_ID=${AZ_TENANT_ID:-$(az account show --query tenantId -o tsv)} || true
  [ -z "$AZ_SUBSCRIPTION_ID" ] && err "Azure subscription not found" || info "Subscription: $AZ_SUBSCRIPTION_ID"
  APP_ID=$(az ad app list --filter "displayName eq '$AZ_APP_DISPLAY_NAME'" --query '[0].appId' -o tsv)
  if [ -z "$APP_ID" ]; then
    info "Creating Azure App Registration $AZ_APP_DISPLAY_NAME"
    APP_ID=$(az ad app create --display-name "$AZ_APP_DISPLAY_NAME" --query appId -o tsv)
  else
    info "Azure App already exists"
  fi
  # Add federated credential (idempotent by name)
  FCREDS=$(az ad app federated-credential list --id "$APP_ID" -o tsv 2>/dev/null || true)
  FED_NAME="gh-${REPO_OWNER}-${REPO_NAME}-${BRANCH_REF//\//-}"
  if ! echo "$FCREDS" | grep -qi "$FED_NAME"; then
    info "Adding federated credential $FED_NAME"
    az ad app federated-credential create --id "$APP_ID" --parameters "{\"name\":\"$FED_NAME\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:$GITHUB_REPO:ref:$BRANCH_REF\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
  else
    info "Federated credential already present"
  fi
  # Assign Contributor role (broad; replace with custom) to SP at subscription scope
  SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)
  if [ -z "$SP_ID" ]; then
    info "Creating Service Principal"
    az ad sp create --id "$APP_ID" >/dev/null
    SP_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)
  fi
  ASSIGN=$(az role assignment list --assignee "$APP_ID" --scope "/subscriptions/$AZ_SUBSCRIPTION_ID" --query '[0].id' -o tsv)
  if [ -z "$ASSIGN" ]; then
    info "Assigning Contributor role"
    az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal --role Contributor --scope "/subscriptions/$AZ_SUBSCRIPTION_ID" >/dev/null || true
  else
    info "Role assignment already exists"
  fi
  echo "export AZURE_SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID"
  echo "export AZURE_TENANT_ID=$AZ_TENANT_ID"
  echo "export AZURE_CLIENT_ID=$APP_ID"
fi

# AWS -------------------------------------------------------------------
if command -v aws >/dev/null 2>&1; then
  AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)}
  [ -z "$AWS_ACCOUNT_ID" ] && err "Cannot detect AWS account" || info "AWS Account: $AWS_ACCOUNT_ID"
  IAM_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$AWS_ROLE_NAME"
  if ! aws iam get-role --role-name "$AWS_ROLE_NAME" >/dev/null 2>&1; then
    info "Creating IAM Role $AWS_ROLE_NAME"
    cat > /tmp/trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:ref:$BRANCH_REF"},
        "StringLike": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"}
      }
    }
  ]
}
EOF
    # Ensure OIDC provider exists (GitHub public):
    if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" >/dev/null 2>&1; then
      info "Creating AWS OIDC provider"
      aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
    fi
    aws iam create-role --role-name "$AWS_ROLE_NAME" --assume-role-policy-document file:///tmp/trust.json >/dev/null
    # Attach a broad policy (customize later)
    aws iam attach-role-policy --role-name "$AWS_ROLE_NAME" --policy-arn arn:aws:policy/AdministratorAccess >/dev/null 2>&1 || aws iam attach-role-policy --role-name "$AWS_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null
  else
    info "IAM Role exists: $IAM_ROLE_ARN"
  fi
  echo "export AWS_OIDC_ROLE_ARN=$IAM_ROLE_ARN"
fi

# GCP -------------------------------------------------------------------
if command -v gcloud >/dev/null 2>&1; then
  GCP_PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}
  [ -z "$GCP_PROJECT_ID" ] && err "Set GCP_PROJECT_ID" || info "GCP Project: $GCP_PROJECT_ID"
  gcloud config set project "$GCP_PROJECT_ID" >/dev/null
  if ! gcloud iam service-accounts describe "$GCP_SA_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com" >/dev/null 2>&1; then
    info "Creating service account"
    gcloud iam service-accounts create "$GCP_SA_NAME" --display-name "CAPI Terraform" >/dev/null
  else
    info "Service account exists"
  fi
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:$GCP_SA_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
    --role roles/compute.admin >/dev/null 2>&1 || true
  gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:$GCP_SA_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
    --role roles/iam.serviceAccountUser >/dev/null 2>&1 || true

  if ! gcloud iam workload-identity-pools describe "$GCP_POOL_ID" --location=global >/dev/null 2>&1; then
    info "Creating Workload Identity Pool $GCP_POOL_ID"
    gcloud iam workload-identity-pools create "$GCP_POOL_ID" --location=global --display-name "$GCP_POOL_ID" >/dev/null
  fi
  POOL_RESOURCE="projects/$(gcloud projects describe $GCP_PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/$GCP_POOL_ID"
  if ! gcloud iam workload-identity-pools providers describe "$GCP_PROVIDER_ID" --location=global --workload-identity-pool="$GCP_POOL_ID" >/dev/null 2>&1; then
    info "Creating OIDC Provider $GCP_PROVIDER_ID"
    gcloud iam workload-identity-pools providers create-oidc "$GCP_PROVIDER_ID" \
      --location=global --workload-identity-pool="$GCP_POOL_ID" \
      --display-name="$GCP_PROVIDER_ID" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.sub" >/dev/null
  fi
  gcloud iam service-accounts add-iam-policy-binding "$GCP_SA_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
    --member "principalSet://iam.googleapis.com/$POOL_RESOURCE/attribute.repository/repo:$GITHUB_REPO:ref:$BRANCH_REF" \
    --role roles/iam.workloadIdentityUser >/dev/null 2>&1 || true

  echo "export GCP_PROJECT_ID=$GCP_PROJECT_ID"
  echo "export GCP_SERVICE_ACCOUNT_EMAIL=$GCP_SA_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com"
  echo "export GCP_WORKLOAD_IDENTITY_PROVIDER=$POOL_RESOURCE/providers/$GCP_PROVIDER_ID"
fi

info "Done. Use the export lines above with gh secret set or run set_github_secrets.sh."
