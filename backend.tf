// Remote backend (Azure Storage) scaffold.
// To enable, ensure the storage resources exist, then run:
// terraform init -backend-config="resource_group_name=<rg>" \
//   -backend-config="storage_account_name=<stgacct>" \
//   -backend-config="container_name=<container>" \
//   -backend-config="key=clusterapi.tfstate"
// In GitHub Actions, set USE_REMOTE_BACKEND=true and supply secrets or env for these values.
// For S3 or GCS, replace with respective backend block.
// Remote backend disabled by default to prevent CI failure without required storage resources.
// To enable, replace the commented block with a configured backend and run:
// terraform init -reconfigure -backend-config="resource_group_name=<rg>" \
//   -backend-config="storage_account_name=<stgacct>" \
//   -backend-config="container_name=<container>" \
//   -backend-config="key=clusterapi.tfstate"
// terraform {
//   backend "azurerm" {}
// }
