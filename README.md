# Multi-Cloud Cluster API Terraform Scaffold

This repo provides a modular Terraform setup to provision infrastructure prerequisites for Cluster API (CAPI) management + workload clusters across Azure (CAPZ), AWS (CAPA), and GCP (CAPG). It focuses on infra primitives (networking, IAM, key vaults, service accounts) and helper local-exec steps to run `clusterctl` for initializing CAPI providers.

## Modules
- `modules/azure`: Resource group, VNet, subnet, identity prerequisites, optional Azure Blob (for cluster templates), outputs for CAPZ variables.
- `modules/aws`: VPC, subnets, IAM roles & policies for CAPA controller, key pair, outputs.
- `modules/gcp`: VPC, subnets, service accounts & IAM roles for CAPG controller, outputs.

A separate `kind` local bootstrap (optional) can create a local kind cluster as the initial management cluster, then run `clusterctl init --infrastructure <provider>`.

> NOTE: Terraform does not manage the lifecycle of the Kubernetes clusters created by Cluster API; it only sets up infra + bootstraps provider components via `local-exec`.

## High-Level Flow
1. (Optional) Create local kind cluster.
2. Select target cloud(s) via variables.
3. Terraform provisions infra.
4. Terraform runs `clusterctl init` with requested providers.
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

### Terraform init & apply (all providers)
Option A: via variables flags
```
terraform init
terraform apply -auto-approve \
	-var="enable_azure=true" \
	-var="enable_aws=true" \
	-var="enable_gcp=true" \
	-var="bootstrap_kind=true"
```

Option B: export environment variables (matching variable names upper/lower case not required here) and rely on defaults.
```
# Already enabled in .env example (ENABLE_*) consumed manually when you pass -var flags.
```

The apply step (if `bootstrap_kind=true`) will create a kind cluster and initialize each selected infrastructure provider via `clusterctl init`.

## Variables (root)
- `bootstrap_kind` (bool) - create local kind mgmt cluster.
- `enable_azure`, `enable_aws`, `enable_gcp` (bool) - toggle cloud modules.
- Provider-specific credential variables (see each module README).

## Next
After infra + provider init, create workload cluster, e.g. for Azure:
```
clusterctl generate cluster az-demo --infrastructure=azure | kubectl apply -f -
```

## Disclaimer
This is a scaffold. Harden for production: remote state backend, state locking, secrets management (avoid plain text vars), least-priv IAM, tagging, logging.
