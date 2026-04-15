output "gcp_project_id" {
  value = var.gcp_project_id
}

output "dataset_ids" {
  value = {
    source_us_east1      = google_bigquery_dataset.source_us_east1.dataset_id
    source_us_east1_cmek = google_bigquery_dataset.source_us_east1_cmek.dataset_id
    dest_us_east4        = google_bigquery_dataset.dest_us_east4.dataset_id
    dest_us_east4_cmek   = google_bigquery_dataset.dest_us_east4_cmek.dataset_id
  }
}

output "kms_keys" {
  value = {
    us_east1 = google_kms_crypto_key.us_east1_bq_default.id
    us_east4 = google_kms_crypto_key.us_east4_bq_default.id
  }
}

output "sample_table" {
  description = "Fully qualified name of the seeded test table (us-east1 source, non-CMEK dataset)"
  value       = "${var.gcp_project_id}.source_us_east1.sample_cross_region_test"
}
