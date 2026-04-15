# BigQuery cross-region test (Terraform)

Terraform for a small GCP footprint used to exercise **BigQuery Data Transfer Service** and **cross-region replication** manually in the Google Cloud Console. This repo only creates the underlying datasets, KMS keys, and a seeded sample table—not the transfers or replication jobs themselves.

## What gets created

| Resource | Notes |
|----------|--------|
| **Datasets** | `source_us_east1`, `source_us_east1_cmek` (both `us-east1`); `dest_us_east4`, `dest_us_east4_cmek` (both `us-east4`). |
| **CMEK** | Key rings and symmetric keys in `us-east1` and `us-east4`; `_cmek` datasets use those keys as default encryption. IAM grants the BigQuery service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on each key. |
| **Sample data** | Table `sample_cross_region_test` in `source_us_east1` (three rows: `id`, `label`, `created_at`), created via a query job. |
| **APIs** | Service Usage, BigQuery, Cloud KMS, BigQuery Data Transfer (plus whatever Terraform needs to manage project services). |

## Prerequisites

- Terraform `>= 1.14`
- Credentials with permission to enable APIs and manage BigQuery, KMS, and IAM in the target project (e.g. `gcloud auth application-default login` with an appropriate user or service account).
- If APIs have never been enabled on the project, you may need to enable **Service Usage API** once (`gcloud services enable serviceusage.googleapis.com --project=YOUR_PROJECT_ID`) before Terraform can turn other APIs on.

## Configuration

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (that filename is gitignored).
2. Set `gcp_project_id` to your GCP project ID.
3. Optionally set `name_prefix` if KMS resource names collide with existing key rings or keys in the same regions.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

Outputs include fully qualified dataset IDs, KMS key IDs, and the sample table name (`project.dataset.table`).

## Layout

- `apis.tf` — Project API enablement and `google_project` data source
- `bigquery.tf` — Datasets and sample table seed job
- `kms.tf` — Regional key rings, crypto keys, and KMS IAM for BigQuery
- `main.tf` — File index
- `outputs.tf`, `providers.tf`, `variables.tf`

## Destroy

Datasets use `delete_contents_on_destroy = true` so `terraform destroy` can remove tables inside them. Confirm you are fine losing that data before destroying.
