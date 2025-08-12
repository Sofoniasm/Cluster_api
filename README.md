# Multi-Cloud Cluster API Terraform Scaffold

This repo provides a modular Terraform setup to provision infrastructure prerequisites for Cluster API (CAPI) management + workload clusters across Azure (CAPZ), AWS (CAPA), GCP (CAPG), and Linode/Akamai (experimental). It focuses on infra primitives (networking, IAM, key vaults, service accounts) and helper local-exec steps to run `clusterctl` for initializing CAPI providers.

## Modules
- `modules/azure`: Resource group, VNet, subnet.
- `modules/aws`: VPC, subnet (scaffold; extend with IAM for production).
- `modules/gcp`: VPC, subnet (scaffold).
- `modules/linode`: Tag + optional SSH key registration (Akamai/Linode experimental support).

A separate `kind` local bootstrap (optional) can create a local kind cluster as the initial management cluster, then run `clusterctl init --infrastructure <provider>`.

> NOTE: Terraform does not manage the lifecycle of the Kubernetes clusters created by Cluster API; it only sets up infra + bootstraps provider components via `local-exec`.

## Quick Multi‑Provider Enable (All Four)
Minimal end‑to‑end steps to stand up Azure, AWS, GCP and Linode providers locally + CI:
1. Create / configure cloud identities:
	- Azure: App Registration (no client secret needed when using GitHub OIDC federated credential) with Contributor (or least‑priv) on target subscription.
	- AWS: IAM Role with trust to `token.actions.githubusercontent.com` subject `repo:OWNER/REPO:ref:refs/heads/main` and policy allowing VPC, EC2, IAM PassRole (scoped), ELB, AutoScaling (adjust least‑priv later).
	- GCP: Workload Identity Pool + OIDC Provider + Service Account with `roles/compute.admin` + `roles/iam.serviceAccountUser`, binding for repository attribute.
	- Linode: Personal Access Token with required scopes (linodes:read/write, sshkeys:read/write as needed).
2. Add GitHub Secrets:
	- Azure: `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` (no secret).
	- AWS: `AWS_OIDC_ROLE_ARN`.
	- GCP: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_PROJECT_ID`.
	- Linode: `LINODE_TOKEN`.
3. (Optional) Choose remote backend: copy a sample from `infra/backends/*` to `backend.tf` and edit names; then `terraform init -migrate-state`.
4. Local: copy `.env.example` -> `.env`, set values, export env (or `source .env`), then:
```
terraform init
terraform apply -auto-approve \
  -var="enable_azure=true" \
  -var="enable_aws=true" \
  -var="enable_gcp=true" \
  -var="enable_linode=true" \
  -var="bootstrap_kind=true"
```
5. Verify provider controllers:
```
kubectl get pods -A | grep -E 'capi|infrastructure'
```
6. (Optional) Create sample workload clusters (one at a time to limit quota):
```
clusterctl generate cluster az-demo  --infrastructure=azure  | kubectl apply -f -
clusterctl generate cluster aws-demo --infrastructure=aws    | kubectl apply -f -
clusterctl generate cluster gcp-demo --infrastructure=gcp    | kubectl apply -f -
clusterctl generate cluster linode-demo --infrastructure=linode | kubectl apply -f - || echo "Verify Linode provider name if this fails"
```
7. CI: workflow already enables all four via env toggles (see `terraform.yml`). Ensure secrets exist; on merge to `main` it will plan + apply with kind bootstrap.

That is the complete fast path; harden next with least‑priv IAM, remote state, policy scanning (tflint/tfsec), and secret management.

### Optional Automation Flags
- `auto_workload_examples=true` will create one demo workload cluster per enabled provider (names: az-demo, aws-demo, gcp-demo, linode-demo) during apply. Disable for production.

### Least Privilege Policy Skeletons
See `policies/` directory for starter examples:
- `aws_least_privilege_example.json`
- `azure_role_definition_example.json`
- `gcp_least_privilege_bindings.txt`

Refine & scope these before production use (they are broad starting points).

## High-Level Flow
1. (Optional) Create local kind cluster.
2. Select target cloud(s) via variables.
3. Terraform provisions infra.
4. Terraform runs `clusterctl init` with requested providers (including Linode if enabled: provider name may differ until upstream stable).
5. Use generated environment exports & sample templates to create workload clusters.

## Requirements
- Terraform >= 1.5
- `clusterctl` installed & in PATH
- `kubectl` installed
- Cloud CLIs (az, aws, gcloud) authenticated with sufficient privileges
- Docker (for kind)

## Quick Start
1. Copy `.env.example` to `.env` and populate credentials.
2. Run the multi-cloud login helper.
3. Run Terraform (plan/apply) with all providers enabled or selectively.

### Populate .env
```
cp .env.example .env
# edit .env with real secrets (never commit it)
```

### Non-interactive logins (Linux/macOS WSL Bash)
```
chmod +x scripts/login_all.sh
./scripts/login_all.sh
```

### Non-interactive logins (Windows PowerShell)
```
powershell -ExecutionPolicy Bypass -File scripts/login_all.ps1
```

You should see Azure/AWS/GCP OK lines for each configured set of credentials.

For Linode/Akamai add to `.env` (or export) before login script:
```
LINODE_TOKEN=your_personal_access_token
LINODE_REGION=us-east
LINODE_SSH_PUBLIC_KEY="ssh-ed25519 AAAA... user@example"
```
The Terraform module consumes linode_region / linode_ssh_public_key variables. The provider reads LINODE_TOKEN.

### Terraform init & apply (all providers)
Option A: via variables flags
```
terraform init
terraform apply -auto-approve \
	-var="enable_azure=true" \
	-var="enable_aws=true" \
	-var="enable_gcp=true" \
	-var="enable_linode=true" \
	-var="bootstrap_kind=true"
```

Option B: export environment variables (matching variable names upper/lower case not required here) and rely on defaults.
```
# Already enabled in .env example (ENABLE_*) consumed manually when you pass -var flags.
```

The apply step (if `bootstrap_kind=true`) will create a kind cluster and initialize each selected infrastructure provider via `clusterctl init`.

## Variables (root)
- `bootstrap_kind` (bool) - create local kind mgmt cluster.
- `enable_azure`, `enable_aws`, `enable_gcp`, `enable_linode` (bool) - toggle cloud modules.
- Provider-specific credential variables (see each module README).

## Next
After infra + provider init, create workload cluster, e.g. for Azure:
```
clusterctl generate cluster az-demo --infrastructure=azure | kubectl apply -f -
```

## Disclaimer
This is a scaffold. Harden for production: remote state backend, state locking, secrets management (avoid plain text vars), least-priv IAM, tagging, logging.

## CI/CD (GitHub Actions)
Workflow `.github/workflows/terraform.yml` runs plan on PR and apply on main using OIDC:
- Azure: azure/login with federated credentials (no client secret required)
- AWS: assumes role via `AWS_OIDC_ROLE_ARN` secret
- GCP: Workload Identity Federation (provider + service account email secrets)
- Linode: `LINODE_TOKEN` secret (currently disabled by default in CI)

Required GitHub Secrets:
- `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`
- `AWS_OIDC_ROLE_ARN`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_PROJECT_ID`
- `LINODE_TOKEN` (optional)

Enable Linode in CI by setting env `ENABLE_LINODE: true` (modify workflow or add an override step).

Add a remote backend (e.g., Azure Storage / S3 / GCS) before relying on multi-user applies.
