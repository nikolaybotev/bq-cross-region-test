locals {
  # Dataset id per seed job key — extend this map if you add more copies of the sample table.
  sample_cross_region_test_seed = {
    plain = "source_us_east4"
    cmek  = "source_us_east4_cmek"
  }

  # Single query template: partition on created_at; three rows on three calendar days → three partitions.
  # Replace PROJECT_ID / DATASET_ID in resource (evolve rows and PARTITION BY here only).
  sample_cross_region_test_query = <<-SQL
CREATE OR REPLACE TABLE `PROJECT_ID.DATASET_ID.sample_cross_region_test`
PARTITION BY DATE(created_at)
AS
SELECT * FROM UNNEST([
  STRUCT(1 AS id, 'alpha' AS label, TIMESTAMP '2026-01-15 10:00:00 UTC' AS created_at),
  STRUCT(2 AS id, 'beta' AS label, TIMESTAMP '2026-01-16 11:30:00 UTC' AS created_at),
  STRUCT(3 AS id, 'gamma' AS label, TIMESTAMP '2026-01-17 09:00:00 UTC' AS created_at)
])
SQL
}

resource "google_bigquery_dataset" "source_us_east4" {
  dataset_id                 = "source_us_east4"
  location                   = "us-east4"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  labels = {
    purpose = "cross_region_bq_test"
    role    = "source"
  }

  depends_on = [google_project_service.required_apis["bigquery.googleapis.com"]]
}

resource "google_bigquery_dataset" "source_us_east4_cmek" {
  dataset_id                 = "source_us_east4_cmek"
  location                   = "us-east4"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_east4_bq_default.id
  }

  labels = {
    purpose = "cross_region_bq_test"
    role    = "source_cmek"
  }

  depends_on = [
    google_project_service.required_apis["bigquery.googleapis.com"],
    google_kms_crypto_key_iam_member.bq_service_agent_us_east4,
  ]
}

resource "google_bigquery_dataset" "dest_us" {
  dataset_id                 = "dest_us"
  location                   = "US"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  labels = {
    purpose = "cross_region_bq_test"
    role    = "dest"
  }

  depends_on = [google_project_service.required_apis["bigquery.googleapis.com"]]
}

resource "google_bigquery_dataset" "dest_us_cmek" {
  dataset_id                 = "dest_us_cmek"
  location                   = "US"
  project                    = var.gcp_project_id
  delete_contents_on_destroy = true

  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.us_multi_bq_default.id
  }

  labels = {
    purpose = "cross_region_bq_test"
    role    = "dest_cmek"
  }

  depends_on = [
    google_project_service.required_apis["bigquery.googleapis.com"],
    google_kms_crypto_key_iam_member.bq_service_agent_us_multi,
  ]
}

resource "google_bigquery_job" "sample_cross_region_test" {
  for_each = local.sample_cross_region_test_seed

  project  = var.gcp_project_id
  job_id   = "tf_sample_${substr(md5("${var.gcp_project_id}-${each.key}-sample_cross_region_test-v9"), 0, 12)}"
  location = "us-east4"

  query {
    query = replace(replace(local.sample_cross_region_test_query, "PROJECT_ID", var.gcp_project_id), "DATASET_ID", each.value)

    # Required for DDL: BigQuery rejects jobs that set disposition on CREATE/DDL statements.
    allow_large_results = false
    use_legacy_sql      = false
    create_disposition  = ""
    write_disposition   = ""

    # Match the CMEK job’s stored encryption (same as dataset default) so Terraform does not null it and force replacement.
    dynamic "destination_encryption_configuration" {
      for_each = each.key == "cmek" ? [1] : []
      content {
        kms_key_name = google_kms_crypto_key.us_east4_bq_default.id
      }
    }
  }

  depends_on = [
    google_bigquery_dataset.source_us_east4,
    google_bigquery_dataset.source_us_east4_cmek,
  ]
}
