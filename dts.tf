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
    write_disposition = "WRITE_APPEND"
    query             = local.dts_incremental_merge_query
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

# ---------------------------------------------------------------------------
# On-demand scheduled_query DTS jobs — DQL (SELECT) variants.
# Deliberately different from the MERGE variant above:
#   1) on-demand (disable_auto_scheduling = true) — runs only on manual backfill
#   2) SELECT DQL with @run_date runtime parameter so DTS routes rows per partition
#   3) Uses the native `scheduled_query` data source params from the data source schema
#      (destination_table_name_template / write_disposition / partitioning_field /
#      destination_table_kms_key) — NOT DDL/DML like MERGE
#   4) Single shared destination table partitioned by created_at (not one per run)
#
# Two jobs below to observe CMEK on/off side by side:
#   * ondemand_select_plain → no `destination_table_kms_key`, no encryption_configuration.
#     dest_us has no default CMEK, so DTS should create the destination table as plaintext.
#   * ondemand_select_cmek  → sets `destination_table_kms_key` in params only. DTS should
#     create the destination table with that CMEK.
#
# Two CMEK knobs exist for scheduled_query and they mean different things:
#   - encryption_configuration.kms_key_name (TransferConfig field; `bq mk --destination_kms_key`)
#     → DTS-level CMEK; covers intermediate on-disk cache AND is propagated to destination tables.
#     Sticky: cannot be added later to a non-CMEK transfer; can only be updated if originally set.
#   - params.destination_table_kms_key (scheduled_query data source param; shown in the DTS
#     console under "Advanced options → Destination table KMS key")
#     → Only applies to the destination table the query writes to; does not cover the cache.
# We use the per-param knob below because that is what the data source schema exposes.
#
# Runtime parameters supported by scheduled_query: @run_time (TIMESTAMP), @run_date (DATE).
# https://cloud.google.com/bigquery/docs/scheduling-queries
#
# EXPECTED FAILURE (cross-region): same root cause as the MERGE variant — the query still
# runs in the config's location (US), so reading the us-east4 source will not work.

locals {
  dts_select_plain_table_id = "dts_sq_select_plain"
  dts_select_ec_table_id    = "dts_sq_select_ec"
  dts_select_ec_cmek_table_id = "dts_sq_select_ec_cmek"

  # @run_date is a DATE parameter automatically injected by DTS.
  dts_select_run_date_query = <<-SQL
SELECT id, label, created_at
FROM `${var.gcp_project_id}.${google_bigquery_dataset.source_us_east4_cmek.dataset_id}.sample_cross_region_test`
WHERE DATE(created_at) = @run_date
SQL
}

# NOTE: these DQL jobs do NOT pre-create the destination table. Per
# https://cloud.google.com/bigquery/docs/scheduling-queries :
#   "If the destination table for your results doesn't exist when you set up the scheduled
#    query, BigQuery attempts to create the table for you."
# With `partitioning_field = "created_at"` DTS creates a time-unit column partitioned table
# on first run, maps the SELECT schema, then WRITE_APPENDs subsequent runs.

resource "google_bigquery_data_transfer_config" "ondemand_select_plain" {
  display_name   = "${var.name_prefix}-ondemand-select-plain"
  location       = "US"
  data_source_id = "scheduled_query"

  service_account_name   = google_service_account.dts_scheduled_query_runner.email
  destination_dataset_id = google_bigquery_dataset.dest_us.dataset_id

  schedule_options {
    disable_auto_scheduling = true
  }

  params = {
    query                           = local.dts_select_run_date_query
    destination_table_name_template = local.dts_select_plain_table_id
    write_disposition               = "WRITE_APPEND"
    partitioning_field              = "created_at"
  }
}

resource "google_bigquery_data_transfer_config" "ondemand_select_ec" {
  display_name   = "${var.name_prefix}-ondemand-select-ec"
  location       = "US"
  data_source_id = "scheduled_query"

  service_account_name   = google_service_account.dts_scheduled_query_runner.email
  destination_dataset_id = google_bigquery_dataset.dest_us.dataset_id

  schedule_options {
    disable_auto_scheduling = true
  }

  encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_multi_bq_default.id
  }

  params = {
    query                           = local.dts_select_run_date_query
    destination_table_name_template = local.dts_select_ec_table_id
    write_disposition               = "WRITE_APPEND"
    partitioning_field              = "created_at"
  }
}

resource "google_bigquery_data_transfer_config" "ondemand_select_ec_cmek" {
  display_name   = "${var.name_prefix}-ondemand-select-ec-cmek"
  location       = "US"
  data_source_id = "scheduled_query"

  service_account_name   = google_service_account.dts_scheduled_query_runner.email
  destination_dataset_id = google_bigquery_dataset.dest_us.dataset_id

  schedule_options {
    disable_auto_scheduling = true
  }

  encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_multi_bq_default.id
  }

  params = {
    query                           = local.dts_select_run_date_query
    destination_table_name_template = local.dts_select_ec_cmek_table_id
    write_disposition               = "WRITE_APPEND"
    partitioning_field              = "created_at"
    destination_table_kms_key       = google_kms_crypto_key.us_multi_bq_default.id
  }
}
