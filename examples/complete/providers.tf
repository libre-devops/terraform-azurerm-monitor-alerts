provider "azurerm" {
  features {
    # The example creates a Log Analytics workspace; purge it on destroy rather than leaving a
    # soft-deleted workspace that a same-named recreation would silently resurrect.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }

    # Azure auto-creates a "Failure Anomalies - <name>" smart detector rule AND an
    # "Application Insights Smart Detection" action group alongside every new App Insights
    # component; neither is in state, so the resource group delete fails the provider's
    # contains-resources safety check without this (proven live).
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Smart detector alert rules live in Microsoft.AlertsManagement, which is NOT in the
  # provider's core auto-registration set: a fresh subscription fails with 409
  # MissingSubscriptionRegistration without this (proven live).
  resource_providers_to_register = ["Microsoft.AlertsManagement"]

  storage_use_azuread = true
  use_oidc            = true
}
