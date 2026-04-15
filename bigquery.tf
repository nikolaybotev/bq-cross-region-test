resource "google_bigquery_dataset" "source_us_east1" {
  dataset_id                 = "source_us_east1"
  location                   = "us-east1"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  labels = {
    purpose = "cross_region_bq_test"
    role    = "source"
  }

  depends_on = [google_project_service.required_apis["bigquery.googleapis.com"]]
}

resource "google_bigquery_dataset" "source_us_east1_cmek" {
  dataset_id                 = "source_us_east1_cmek"
  location                   = "us-east1"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_east1_bq_default.id
  }

  labels = {
    purpose = "cross_region_bq_test"
    role    = "source_cmek"
  }

  depends_on = [
    google_project_service.required_apis["bigquery.googleapis.com"],
    google_kms_crypto_key_iam_member.bq_service_agent_us_east1,
  ]
}

resource "google_bigquery_dataset" "dest_us_east4" {
  dataset_id                 = "dest_us_east4"
  location                   = "us-east4"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  labels = {
    purpose = "cross_region_bq_test"
    role    = "dest"
  }

  depends_on = [google_project_service.required_apis["bigquery.googleapis.com"]]
}

resource "google_bigquery_dataset" "dest_us_east4_cmek" {
  dataset_id                 = "dest_us_east4_cmek"
  location                   = "us-east4"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_east4_bq_default.id
  }

  labels = {
    purpose = "cross_region_bq_test"
    role    = "dest_cmek"
  }

  depends_on = [
    google_project_service.required_apis["bigquery.googleapis.com"],
    google_kms_crypto_key_iam_member.bq_service_agent_us_east4,
  ]
}

# Seeds a small native table in the plain us-east1 source dataset for Console copy / transfer tests.
resource "google_bigquery_job" "sample_cross_region_test" {
  project  = var.gcp_project_id
  job_id   = "tf_sample_${substr(md5("${var.gcp_project_id}-source_us_east1-sample_cross_region_test-v1"), 0, 12)}"
  location = "us-east1"

  query {
    query = <<-EOT
      CREATE OR REPLACE TABLE `${var.gcp_project_id}.source_us_east1.sample_cross_region_test` AS
      SELECT * FROM UNNEST([
        STRUCT(1 AS id, 'alpha' AS label, TIMESTAMP '2026-01-15 10:00:00 UTC' AS created_at),
        STRUCT(2, 'beta', TIMESTAMP '2026-01-15 11:30:00 UTC'),
        STRUCT(3, 'gamma', TIMESTAMP '2026-01-16 09:00:00 UTC')
      ])
    EOT

    allow_large_results = false
    use_legacy_sql      = false
  }

  depends_on = [google_bigquery_dataset.source_us_east1]
}
