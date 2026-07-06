provider "azurerm" {
  features {
    # The example creates a Log Analytics workspace; purge it on destroy rather than leaving a
    # soft-deleted workspace that a same-named recreation would silently resurrect.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }

  # Smart detector alert rules live in Microsoft.AlertsManagement, which is NOT in the
  # provider's core auto-registration set: a fresh subscription fails with 409
  # MissingSubscriptionRegistration without this (proven live).
  resource_providers_to_register = ["Microsoft.AlertsManagement"]

  storage_use_azuread = true
  use_oidc            = true
}
