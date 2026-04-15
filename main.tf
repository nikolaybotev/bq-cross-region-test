#
# BigQuery cross-region test foundation (us-east1 ↔ us-east4).
#
# - apis.tf       — required Google APIs and project data source
# - kms.tf        — regional KMS key rings, default BigQuery crypto keys, IAM
# - bigquery.tf   — datasets (plain + CMEK per region) and sample seed table job
# - outputs.tf
# - providers.tf  — Terraform and Google provider
# - variables.tf
#
