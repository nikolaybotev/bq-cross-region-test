# BigQuery Data Transfer — scheduled query from source_us_east4_cmek → dest_us with explicit
# destination CMEK (US multi-region key), mirroring `bq cp --destination_kms_key=…`.
#
# DTS has no first-class “copy partition N only” transfer for cross-region BQ→BQ; the usual
# pattern is a daily scheduled_query that filters on the partition column (incremental by day).

locals {
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

# Lets the BQ DTS service agent create query jobs (same pattern as provider docs for scheduled_query).
resource "google_project_iam_member" "bq_dts_service_agent_token_creator" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "bq_dts_service_agent_job_user" {
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset_iam_member" "dts_can_read_source_cmek" {
  dataset_id = google_bigquery_dataset.source_us_east4_cmek.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset_iam_member" "dts_can_write_dest_us" {
  dataset_id = google_bigquery_dataset.dest_us.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "bq_dts_service_agent_us_multi" {
  crypto_key_id = google_kms_crypto_key.us_multi_bq_default.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

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

  destination_dataset_id = google_bigquery_dataset.dest_us.dataset_id

  params = {
    destination_table_name_template = local.dts_dest_table_id
    write_disposition               = "WRITE_APPEND"
    query                           = local.dts_incremental_merge_query
  }

  encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_multi_bq_default.id
  }

  depends_on = [
    google_project_iam_member.bq_dts_service_agent_token_creator,
    google_project_iam_member.bq_dts_service_agent_job_user,
    google_bigquery_dataset_iam_member.dts_can_read_source_cmek,
    google_bigquery_dataset_iam_member.dts_can_write_dest_us,
    google_kms_crypto_key_iam_member.bq_dts_service_agent_us_multi,
    google_bigquery_table.dts_dest_cmek_incremental,
  ]
}
