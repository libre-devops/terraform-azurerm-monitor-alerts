provider "azurerm" {
  features {
    # The example creates a Log Analytics workspace; purge it on destroy rather than leaving a
    # soft-deleted workspace that a same-named recreation would silently resurrect.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }

  storage_use_azuread = true
  use_oidc            = true
}
