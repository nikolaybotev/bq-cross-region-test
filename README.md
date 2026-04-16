# BigQuery cross-region test (Terraform)

Terraform for a small GCP footprint used to exercise **BigQuery Data Transfer Service** and **cross-region replication** manually in the Google Cloud Console. This repo only creates the underlying datasets, KMS keys, and a seeded sample table—not the transfers or replication jobs themselves.

**Manual test results** (DTS, cross-region **`bq cp`**, CRR, CMEK combinations): [docs/CROSS_REGION_TEST_REPORT.md](docs/CROSS_REGION_TEST_REPORT.md).

## What gets created

| Resource | Notes |
|----------|--------|
| **Datasets** | `source_us_east4`, `source_us_east4_cmek` (both **`us-east4`**); `dest_us`, `dest_us_cmek` (both **`US`** multi-region). |
| **CMEK** | Key rings in **`us-east4`** (source) and multi-region **`us`** (US destination, per BigQuery CMEK requirements). `_cmek` datasets use those keys as default encryption. IAM grants the BigQuery encryption service account `roles/cloudkms.cryptoKeyEncrypterDecrypter` on each key. |
| **Sample data** | Table `sample_cross_region_test` in **`source_us_east4`** and **`source_us_east4_cmek`** (same schema), **partitioned by `DATE(created_at)`** with three rows on three days (three partitions). Created via query jobs (`local.sample_cross_region_test_query` in `bigquery.tf`). |
| **APIs** | Service Usage, BigQuery, Cloud KMS, BigQuery Data Transfer (plus whatever Terraform needs to manage project services). |

## Prerequisites

- Terraform `>= 1.14`
- Credentials with permission to enable APIs and manage BigQuery, KMS, and IAM in the target project (e.g. `gcloud auth application-default login` with an appropriate user or service account).
- If APIs have never been enabled on the project, you may need to enable **Service Usage API** once (`gcloud services enable serviceusage.googleapis.com --project=YOUR_PROJECT_ID`) before Terraform can turn other APIs on.

## Configuration

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (that filename is gitignored).
2. Set `gcp_project_id` to your GCP project ID.
3. Optionally set `name_prefix` if KMS resource names collide with existing key rings or keys in the same locations.

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
- `kms.tf` — KMS key rings (`us-east4`, multi-region `us`), crypto keys, and KMS IAM for BigQuery
- `main.tf` — File index
- `outputs.tf`, `providers.tf`, `variables.tf`

## Destroy

Datasets use `delete_contents_on_destroy = true` so `terraform destroy` can remove tables inside them. Confirm you are fine losing that data before destroying.
