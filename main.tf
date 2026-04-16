#
# BigQuery cross-region test foundation (us-east4 source ↔ US multi-region destination).
#
# - apis.tf       — required Google APIs and project data source
# - kms.tf        — KMS key rings (us-east4 + multi-region us), crypto keys, IAM for BigQuery
# - bigquery.tf   — datasets (plain + CMEK) and sample seed table job
# - outputs.tf
# - providers.tf  — Terraform and Google provider
# - variables.tf
# - docs/CROSS_REGION_TEST_REPORT.md — manual DTS / CRR test matrix
#
