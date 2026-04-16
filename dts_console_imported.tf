# BigQuery Data Transfer configs created in the console (data_source_id = cross_region_copy).
# Imported into Terraform state so they can be compared to the scheduled_query + MERGE job in dts.tf.
#
# Import (already run once to attach state; re-import if you recreate configs):
#   terraform import 'google_bigquery_data_transfer_config.console_cross_region_copy["69f28430-0000-2b77-ab5a-94eb2c1c5e20"]' \
#     'feelinsosweet/projects/289720198442/locations/us-east4/transferConfigs/69f28430-0000-2b77-ab5a-94eb2c1c5e20'
#   (repeat for each key in local.console_cross_region_copy_transfers)
#
# List in Cloud / CLI:
#   bq ls --transfer_config --transfer_location=us-east4 --project_id=feelinsosweet

locals {
  # schedule_options copied from current API/ state so plan does not strip end_time.
  console_cross_region_copy_transfers = {
    "69f28430-0000-2b77-ab5a-94eb2c1c5e20" = {
      display_name            = "Copy of source_us_east1_cmek"
      destination_dataset_id  = "dest_us_east4"
      source_dataset_id       = "source_us_east1_cmek"
      schedule_end_time       = "2026-04-16T00:20:26.368Z"
    }
    "69f2b375-0000-2ab7-9e93-089e08e4d843" = {
      display_name            = "Copy of source_us_east1"
      destination_dataset_id  = "dest_us_east4_cmek"
      source_dataset_id       = "source_us_east1"
      schedule_end_time       = "2026-04-16T00:26:58.385Z"
    }
    "69f34b61-0000-298e-83d3-94eb2c1c5e4a" = {
      display_name            = "Copy of source_us_east1_cmek"
      destination_dataset_id  = "dest_us_east4_cmek"
      source_dataset_id       = "source_us_east1_cmek"
      schedule_end_time       = "2026-04-16T00:21:09.416Z"
    }
    "69f43302-0000-2a13-a73c-94eb2c1c5ab6" = {
      display_name            = "Copy of source_us_east1"
      destination_dataset_id  = "dest_us_east4"
      source_dataset_id       = "source_us_east1"
      schedule_end_time       = "2026-04-16T00:26:48.199Z"
    }
  }
}

resource "google_bigquery_data_transfer_config" "console_cross_region_copy" {
  for_each = local.console_cross_region_copy_transfers

  project = var.gcp_project_id

  display_name           = each.value.display_name
  location               = "us-east4"
  data_source_id         = "cross_region_copy"
  destination_dataset_id = each.value.destination_dataset_id

  params = {
    source_project_id           = var.gcp_project_id
    source_dataset_id           = each.value.source_dataset_id
    overwrite_destination_table = "false"
  }

  schedule_options {
    disable_auto_scheduling = false
    end_time                = each.value.schedule_end_time
  }

}
