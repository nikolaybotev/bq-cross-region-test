output "gcp_project_id" {
  value = var.gcp_project_id
}

output "dataset_ids" {
  value = {
    source_us_east4      = google_bigquery_dataset.source_us_east4.dataset_id
    source_us_east4_cmek = google_bigquery_dataset.source_us_east4_cmek.dataset_id
    dest_us              = google_bigquery_dataset.dest_us.dataset_id
    dest_us_cmek         = google_bigquery_dataset.dest_us_cmek.dataset_id
  }
}

output "kms_keys" {
  value = {
    us_east4 = google_kms_crypto_key.us_east4_bq_default.id
    us       = google_kms_crypto_key.us_multi_bq_default.id
  }
}

output "sample_tables" {
  description = "Seeded sample_cross_region_test (partitioned by DATE(created_at)) per source dataset key"
  value = {
    for k, id in local.sample_cross_region_test_seed :
    k => "${var.gcp_project_id}.${id}.sample_cross_region_test"
  }
}

output "sample_table" {
  description = "Plain (non-CMEK) source table — same as sample_tables[\"plain\"]"
  value       = "${var.gcp_project_id}.source_us_east4.sample_cross_region_test"
}
