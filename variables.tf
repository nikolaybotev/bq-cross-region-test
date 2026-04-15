variable "gcp_project_id" {
  description = "GCP project ID where BigQuery datasets and KMS keys are created"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for KMS key ring and crypto key names (must be unique within the project/region)"
  type        = string
  default     = "bq-cross-region-test"
}
