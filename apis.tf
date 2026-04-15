locals {
  required_apis = [
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
  ]
}

resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)

  project = var.gcp_project_id
  service = each.value

  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.gcp_project_id
}
