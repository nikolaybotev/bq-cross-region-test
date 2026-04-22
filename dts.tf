# BigQuery Data Transfer — scheduled query from source_us_east4_cmek → dest_us with explicit
# destination CMEK (US multi-region key), mirroring `bq cp --destination_kms_key=…`.
#
# DTS has no first-class “copy partition N only” transfer for cross-region BQ→BQ; the usual
# pattern is a daily scheduled_query that filters on the partition column (incremental by day).
#
# EXPECTED FAILURE (cross-region):
# scheduled_query runs as a regular BigQuery query in the DTS config's `location` (US here).
# The source table lives in us-east4, so the US query planner cannot see it and returns:
#   "Access Denied: Table …source_us_east4_cmek.sample_cross_region_test: …does not have
#    permission to query …, or perhaps it does not exist."
# This is a cross-region visibility error (not an IAM issue). Captured as an expected failure
# scenario for CROSS_REGION_TEST_REPORT.md; mitigations: CRR + intermediate dataset, or
# `cross_region_copy` DTS (see `dts_console_imported.tf`).

locals {
  # Google-managed BigQuery Data Transfer service agent (orchestrates runs; may impersonate a user SA).
  bq_dts_service_agent = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"

  dts_dest_table_id = "dts_cmek_from_east4"

  # Idempotent daily load: merge yesterday’s partition from the seeded sample table.
  dts_incremental_merge_query = <<-SQL
MERGE `${var.gcp_project_id}.${google_bigquery_dataset.dest_us.dataset_id}.${local.dts_dest_table_id}` AS T
USING (
  SELECT *
  FROM `${var.gcp_project_id}.${google_bigquery_dataset.source_us_east4_cmek.dataset_id}.sample_cross_region_test`
  WHERE DATE(created_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
) AS S
ON T.id = S.id AND DATE(T.created_at) = DATE(S.created_at)
WHEN NOT MATCHED THEN INSERT (id, label, created_at) VALUES (S.id, S.label, S.created_at)
SQL
}

# Scheduled transfers that set `service_account_name` run the query as this identity. The API rejects
# configs without `service_account_name` / version_info in many projects ("Failed to find a valid credential").
resource "google_service_account" "dts_scheduled_query_runner" {
  account_id   = substr(replace("${var.name_prefix}-dts-sq", "_", "-"), 0, 30)
  display_name = "${var.name_prefix} DTS scheduled query runner"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis["iam.googleapis.com"]]
}

# Lets the DTS service agent mint tokens to act as the runner SA (provider-recommended pattern).
resource "google_project_iam_member" "bq_dts_service_agent_token_creator" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = local.bq_dts_service_agent
}

# DTS must be allowed to attach / run as the user-managed runner SA.
resource "google_service_account_iam_member" "bq_dts_can_use_runner_sa" {
  service_account_id = google_service_account.dts_scheduled_query_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.bq_dts_service_agent
}

resource "google_project_iam_member" "dts_runner_bigquery_job_user" {
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.dts_scheduled_query_runner.member
}

resource "google_bigquery_dataset_iam_member" "dts_runner_can_read_source_cmek" {
  dataset_id = google_bigquery_dataset.source_us_east4_cmek.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.dts_scheduled_query_runner.member
}

resource "google_bigquery_dataset_iam_member" "dts_runner_can_write_dest_us" {
  dataset_id = google_bigquery_dataset.dest_us.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.dts_scheduled_query_runner.member
}

# CMEK wraps DEKs using the BigQuery service agent on `bq-…@bigquery-encryption.iam.gserviceaccount.com`
# (see google_kms_crypto_key_iam_member.bq_service_agent_us_multi in kms.tf), not the query runner SA.

resource "google_bigquery_table" "dts_dest_cmek_incremental" {
  dataset_id = google_bigquery_dataset.dest_us.dataset_id
  table_id   = local.dts_dest_table_id
  project    = var.gcp_project_id

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "created_at"
  }

  schema = jsonencode([
    { name = "id", type = "INTEGER", mode = "NULLABLE" },
    { name = "label", type = "STRING", mode = "NULLABLE" },
    { name = "created_at", type = "TIMESTAMP", mode = "NULLABLE" },
  ])

}

resource "google_bigquery_data_transfer_config" "incremental_cmek_scheduled_query" {
  display_name   = "${var.name_prefix}-incremental-east4-cmek-to-us-cmek"
  location       = "US"
  data_source_id = "scheduled_query"
  schedule       = "every day 07:00"

  service_account_name = google_service_account.dts_scheduled_query_runner.email

  destination_dataset_id = google_bigquery_dataset.dest_us.dataset_id

  params = {
    write_disposition               = "WRITE_APPEND"
    query                           = local.dts_incremental_merge_query
  }

  encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_multi_bq_default.id
  }

  depends_on = [
    google_project_iam_member.bq_dts_service_agent_token_creator,
    google_service_account_iam_member.bq_dts_can_use_runner_sa,
    google_project_iam_member.dts_runner_bigquery_job_user,
    google_bigquery_dataset_iam_member.dts_runner_can_read_source_cmek,
    google_bigquery_dataset_iam_member.dts_runner_can_write_dest_us,
    google_kms_crypto_key_iam_member.bq_service_agent_us_multi,
    google_bigquery_table.dts_dest_cmek_incremental,
  ]
}
