locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# Minimal call: one self-contained activity log alert on the resource group, no scope resources
# needed. There is deliberately no action group wired: the module's alerts_have_actions check
# surfaces that as a warning (the complete example shows the full fan-out).
module "monitor_alerts" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  activity_log_alerts = {
    "Administrative_activity_-_Critical_operations_in_the_example_resource_group" = {
      scopes      = [module.rg.ids[local.rg_name]]
      description = "Fires on critical-level administrative operations recorded against the example resource group."

      criteria = {
        category = "Administrative"
        level    = "Critical"
      }
    }
  }
}
