# Cross-region BigQuery test report

Manual tests performed in the Google Cloud Console using datasets and KMS keys provisioned by this repository’s Terraform (`us-east1` sources → `us-east4` destinations). Project: **feelinsosweet**.

## Scenarios

| Source CMEK | Dest CMEK | DTS | `bq cp` | CRR | CRR (secondary) |
|-------------|-----------|-----|---------|------|-----------------|
| Yes | Yes | ✅ Pass | ✅ Pass | ✅ Pass | ❌ Fail |
| Yes | No | ❌ Fail | ❌ Fail | ✅ Pass | ❌ Fail |
| No | Yes | ❌ Fail | ❌ Fail | ✅ Pass | ❌ Fail |
| No | No | ✅ Pass | ✅ Pass | ✅ Pass | ❌ Fail |

Cross-region **`bq cp`** (`us-east1` → `us-east4`) for `sample_cross_region_test` (project `feelinsosweet`). Example destination IDs use the `from_us_east1*` suffix to distinguish scenarios. **`bq cp`** matches **DTS** on CMEK: Pass when source and destination are both CMEK or both non-CMEK; mixed CMEK fails unless you use **`--destination_kms_key`** or an in-region CMEK staging copy, as BigQuery’s errors describe.

```bash
# Yes / Yes — CMEK → CMEK
bq cp -f \
  feelinsosweet:source_us_east1_cmek.sample_cross_region_test \
  feelinsosweet:dest_us_east4_cmek.from_us_east1_cmek

# Yes / No — CMEK source → non-CMEK dest
bq cp -f \
  feelinsosweet:source_us_east1_cmek.sample_cross_region_test \
  feelinsosweet:dest_us_east4.from_us_east1_cmek

# No / Yes — non-CMEK source → CMEK dest
bq cp -f \
  feelinsosweet:source_us_east1.sample_cross_region_test \
  feelinsosweet:dest_us_east4_cmek.from_us_east1

# No / No — non-CMEK → non-CMEK
bq cp -f \
  feelinsosweet:source_us_east1.sample_cross_region_test \
  feelinsosweet:dest_us_east4.from_us_east1
```

Terraform only creates `sample_cross_region_test` in `source_us_east1`. For the two **Yes** rows in “Source CMEK”, copy or CTAS that table into `source_us_east1_cmek` first (same name), then run the matching `bq cp` above.

- **DTS**: BigQuery Data Transfer Service.
- **CRR**: Cross-region replication when the source-region replica in the destination dataset is the **primary** replica (copying into the destination works in these tests).
- **CRR (secondary)**: Same replication setup, but the source-region replica in the destination dataset is still the **secondary** replica. In that state, **data cannot be copied into the destination dataset** until that replica is promoted to **primary** in the destination dataset.

## Observations

1. **DTS** succeeded only when **source and destination CMEK usage matched** (both CMEK or both non-CMEK). It failed when one side used CMEK and the other did not.
2. **`bq cp`** (cross-region **`us-east1` → `us-east4`**) follows the **same CMEK pairing rule as DTS**: Pass in the **Yes / Yes** and **No / No** rows; Fail in the mixed rows, with BigQuery errors about CMEK unless you supply a destination key or do an in-region CMEK copy first.
3. **CRR** succeeded in **all four** combinations of source/destination CMEK.
4. **CRR (secondary)** failed in every run: with the source-region replica still **secondary** in the destination dataset, copy/load into the destination was not possible. **Promoting that replica to primary** in the destination dataset is required before those operations can succeed.

5. **Cross-region CTAS** (empirical): for `CREATE TABLE … AS SELECT` across regions to work, the dataset you read from needs a **replica in the region where the destination dataset’s primary lives**.

### Why CRR (secondary) fails: secondary replicas are read-only

For a dataset that uses cross-region replication, only the **primary** replica accepts **writes** (new tables, loads, CTAS that materialize in that dataset, `bq cp` into that dataset, etc.). **Secondary** replicas are **read-only**: reads are fine, but anything that would **write** through the secondary regional footprint is rejected until that replica is promoted to primary.

One check used dataset **`dest_us_east4_primary`**, created in the Console with **primary** in **us-east4** and a **secondary** replica in **us-east1** (the source side matches the Terraform-style single-region datasets in this project). A CTAS with `SET @@location='us-east1';` targeting `dest_us_east4_primary` tries to write while the job runs in **us-east1**, i.e. against the **secondary** replica. BigQuery returns an error like:

> Invalid value: The dataset replica of the cross region dataset 'feelinsosweet:dest_us_east4_primary' in region 'us-east1' is read-only because it's not the primary replica.

The dataset **Details** UI lists the same: **Secondary** in `us-east1` with **Make it primary**, and **Primary (Creation region)** in `us-east4`. Until the replica in the region where you need writes is primary, **CRR (secondary)** stays a failed path for copy/load/CTAS into that destination from that region.

## CTAS cross-region transfer

**Goal:** Move data from a **us-east4**-only source to a **US**-only destination using CTAS, without relying on DTS for the whole path, so as to avoid the DTS CMEK restrictions.

**Layout (three datasets):**

1. **Source dataset** — region **us-east4** only; **no** cross-region replicas.
2. **Intermediate dataset** — **us-east4** is **primary**; **US** is a **replica** (same logical dataset, two regional footprints).
3. **Destination dataset** — region **US** only; **no** replicas.

**Overview (three datasets, left to right):**

```mermaid
flowchart LR
  SRC["Source DataSet<br/><br/>us-east4"]
  INT["Intermediate DataSet<br/><br/>us-east4 (Primary)<br/>US (replica)"]
  DST["Destination DataSet<br/><br/>US"]
  SRC --> INT
  INT --> DST
```

The intermediate dataset is one logical dataset: **primary** in **us-east4** and a **replica** in **US** (cross-region replication between those footprints). Arrows are the intended data movement (CTAS steps detailed below).

**CTAS sequence (two writes; replication is automatic between them):**

```mermaid
flowchart LR
  subgraph e4["us-east4"]
    S[Source]
    P[Intermediate<br/>primary]
  end
  subgraph us["US"]
    R[Intermediate<br/>replica]
    D[Destination]
  end
  S -->|"① CTAS (us-east4)"| P
  P -. "CRR" .-> R
  R -->|"② CTAS (US)"| D
```

- ① loads the intermediate **primary** in **us-east4**. After **CRR** materializes the **US** replica.
- ② runs in **US** so the read side matches the destination dataset’s region and the cross-region CTAS rule in observation 4 holds.

## Global queries (alternative to CRR for cross-region CTAS)

[Global queries](https://cloud.google.com/bigquery/docs/global-queries) can drive **cross-region `CREATE TABLE … AS SELECT`** and related work **without** an intermediate dataset and **without** cross-region replication (CRR)—Google routes the job across regions for you.

That path is a poor fit for **large** moves: in the [BigQuery quotas](https://cloud.google.com/bigquery/quotas#copy_jobs), a **single copy job** that is part of a global query cannot move more than **100 GB**. That limit applies to **that** global-query flow; it is **not** the same as saying every `bq cp` or every table copy is capped at 100 GB, but it is the clearest **per-job byte** cap tied to copy-style work in the quota table. Above that size, patterns like the CRR + CTAS layout above, **chunked** queries, or **export / load** remain more realistic.

## Reproducibility

Infrastructure definitions: repository root Terraform (`README.md` in parent directory). Transfers and replication were configured and run manually in the Console; this document only records outcomes.
