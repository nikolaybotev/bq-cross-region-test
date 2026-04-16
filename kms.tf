resource "google_kms_key_ring" "us_east1" {
  name     = "${var.name_prefix}-us-east1"
  location = "us-east1"
  project  = var.gcp_project_id

  depends_on = [google_project_service.required_apis["cloudkms.googleapis.com"]]
}

resource "google_kms_crypto_key" "us_east1_bq_default" {
  name            = "${var.name_prefix}-bq-us-east1"
  key_ring        = google_kms_key_ring.us_east1.id
  rotation_period = "7776000s"

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

resource "google_kms_key_ring" "us_east4" {
  name     = "${var.name_prefix}-us-east4"
  location = "us-east4"
  project  = var.gcp_project_id

  depends_on = [google_project_service.required_apis["cloudkms.googleapis.com"]]
}

resource "google_kms_crypto_key" "us_east4_bq_default" {
  name            = "${var.name_prefix}-bq-us-east4"
  key_ring        = google_kms_key_ring.us_east4.id
  rotation_period = "7776000s"

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

# BigQuery service agent needs to use the keys for default encryption on datasets.
# as per https://docs.cloud.google.com/bigquery/docs/customer-managed-encryption#assign_role
resource "google_kms_crypto_key_iam_member" "bq_service_agent_us_east1" {
  crypto_key_id = google_kms_crypto_key.us_east1_bq_default.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:bq-${data.google_project.current.number}@bigquery-encryption.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "bq_service_agent_us_east4" {
  crypto_key_id = google_kms_crypto_key.us_east4_bq_default.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:bq-${data.google_project.current.number}@bigquery-encryption.iam.gserviceaccount.com"
}
