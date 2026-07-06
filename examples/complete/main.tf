locals {
  location     = lookup(var.regions, var.loc, "uksouth")
  rg_name      = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name     = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
  appi_name    = "appi-${var.short}-${var.loc}-${terraform.workspace}-002"
  ag_name      = "ag-${var.short}-${var.loc}-${terraform.workspace}-002"
  webtest_name = "webtest-${var.short}-${var.loc}-${terraform.workspace}-002"
}

data "azurerm_subscription" "current" {}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-monitor-alerts" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# The alert scopes: a workspace for the log search rule, a workspace-based App Insights component
# for the metric and smart detector rules, and a standard web test for the availability criteria.
module "law" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = {
    (local.law_name) = {}
  }
}

module "app_insights" {
  source  = "libre-devops/application-insights/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  workspace_id = module.law.workspace_ids[local.law_name]

  application_insights = {
    (local.appi_name) = {}
  }
}

# Availability test backing the web test criteria metric alert. Support resource for the example,
# not something the module manages.
resource "azurerm_application_insights_standard_web_test" "availability" {
  resource_group_name = local.rg_name
  location            = local.location
  tags                = module.tags.tags

  name                    = local.webtest_name
  application_insights_id = module.app_insights.ids[local.appi_name]
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr"]
  frequency               = 300

  request {
    url = "https://www.example.com"
  }
}

# Where every rule fans out.
module "action_group" {
  source  = "libre-devops/monitor-action-group/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  tags              = module.tags.tags

  action_groups = {
    (local.ag_name) = {
      short_name = "alerts"

      email_receivers = [
        { name = "Notify_platform_team_mailbox", email_address = "platform@example.com" }
      ]
    }
  }
}

# Complete call: all four rule families, every criteria style, descriptive rule names throughout
# (the name IS the alert's display surface, so "For_Each_Incident" style names are banned here).
module "monitor_alerts" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  metric_alerts = {
    "Application_errors_-_Failed_requests_over_threshold" = {
      scopes           = [module.app_insights.ids[local.appi_name]]
      description      = "Fires when more than 10 requests fail in a 5 minute window, split by result code."
      severity         = 1
      action_group_ids = [module.action_group.ids[local.ag_name]]

      criteria = [{
        metric_namespace = "microsoft.insights/components"
        metric_name      = "requests/failed"
        aggregation      = "Count"
        operator         = "GreaterThan"
        threshold        = 10
        dimensions       = [{ name = "request/resultCode", operator = "Include", values = ["500", "503"] }]
      }]
    }

    "Latency_anomaly_-_Response_time_deviates_from_learned_baseline" = {
      scopes           = [module.app_insights.ids[local.appi_name]]
      description      = "Machine-learned threshold on server response time: fires when latency deviates from the component's own baseline rather than a hand-picked number."
      severity         = 2
      action_group_ids = [module.action_group.ids[local.ag_name]]

      dynamic_criteria = [{
        metric_namespace         = "microsoft.insights/components"
        metric_name              = "requests/duration"
        aggregation              = "Average"
        operator                 = "GreaterThan"
        alert_sensitivity        = "Medium"
        evaluation_total_count   = 4
        evaluation_failure_count = 4
      }]
    }

    # Web test availability alerts scope BOTH the web test and the component.
    "Availability_-_Web_test_failing_from_multiple_locations" = {
      scopes           = [azurerm_application_insights_standard_web_test.availability.id, module.app_insights.ids[local.appi_name]]
      description      = "Fires when the availability test fails from two or more test locations at once."
      severity         = 1
      action_group_ids = [module.action_group.ids[local.ag_name]]

      web_test_availability_criteria = {
        web_test_id           = azurerm_application_insights_standard_web_test.availability.id
        component_id          = module.app_insights.ids[local.appi_name]
        failed_location_count = 2
      }
    }
  }

  scheduled_query_alerts = {
    "Ingestion_volume_-_Billable_data_over_expected_baseline" = {
      scopes           = [module.law.workspace_ids[local.law_name]]
      description      = "Fires when billable ingestion into the workspace exceeds the expected baseline: the classic cost early-warning."
      severity         = 2
      action_group_ids = [module.action_group.ids[local.ag_name]]

      evaluation_frequency = "PT1H"
      window_duration      = "PT1H"

      criteria = {
        query                   = "Usage | where IsBillable == true | summarize IngestedGB = sum(Quantity) / 1000.0"
        operator                = "GreaterThan"
        threshold               = 50
        time_aggregation_method = "Total"
        metric_measure_column   = "IngestedGB"

        failing_periods = {
          minimum_failing_periods_to_trigger_alert = 1
          number_of_evaluation_periods             = 1
        }
      }

      custom_properties = { team = "platform" }
      email_subject     = "Workspace ingestion over baseline"

      # The rule evaluates the workspace as itself; grant this identity Log Analytics Reader on
      # the scope for it to read (creation does not require the role, evaluation does).
      identity = {}

      # auto_mitigation_enabled and mute_actions_after_alert_duration are mutually exclusive:
      # auto-mitigation resolves the alert when the condition clears, muting suppresses repeat
      # actions for a fixed spell while leaving the alert open.
      auto_mitigation_enabled = true

      # Azure validates the KQL against the live workspace schema at rule-create time, so rules
      # created in the same apply as their workspace skip validation (proven live: a rule on a
      # freshly Sentinel-onboarded workspace fails on the not-yet-provisioned SecurityIncident
      # table without this).
      skip_query_validation = true
    }
  }

  # Azure auto-creates the FailureAnomaliesDetector rule for every new component and only one
  # may exist per resource (409 ScopeInUse, proven live), so the example demonstrates a daily
  # detector the platform does NOT create for you.
  smart_detector_alerts = {
    "Performance_degradation_-_Response_time_worse_than_learned_baseline" = {
      detector_type      = "RequestPerformanceDegradationDetector"
      scope_resource_ids = [module.app_insights.ids[local.appi_name]]
      description        = "AI-driven daily detector: fires when server response time degrades against the component's learned baseline rather than a fixed threshold."
      action_group_ids   = [module.action_group.ids[local.ag_name]]

      email_subject       = "Response time degradation detected"
      throttling_duration = "PT20M"
    }
  }

  activity_log_alerts = {
    "Administrative_activity_-_Example_resource_group_deleted" = {
      scopes           = [module.rg.ids[local.rg_name]]
      description      = "Fires when the example resource group is deleted: the control-plane tripwire."
      action_group_ids = [module.action_group.ids[local.ag_name]]

      criteria = {
        category       = "Administrative"
        operation_name = "Microsoft.Resources/subscriptions/resourceGroups/delete"
        status         = "Succeeded"
      }
    }

    # Service health alerts evaluate the whole subscription, so they scope to it while living in
    # the resource group like any other rule.
    "Service_health_-_Incidents_affecting_UK_South" = {
      scopes           = [data.azurerm_subscription.current.id]
      description      = "Fires when Azure reports a service incident affecting UK South."
      action_group_ids = [module.action_group.ids[local.ag_name]]

      criteria = {
        category = "ServiceHealth"

        service_health = {
          events    = ["Incident"]
          locations = ["UK South"]
        }
      }
    }

    "Resource_health_-_Resources_made_unavailable_by_platform_faults" = {
      scopes           = [module.rg.ids[local.rg_name]]
      description      = "Fires when a resource in the example resource group goes from Available to Unavailable for a platform-initiated reason."
      action_group_ids = [module.action_group.ids[local.ag_name]]

      criteria = {
        category = "ResourceHealth"

        resource_health = {
          current  = ["Unavailable"]
          previous = ["Available"]
          reason   = ["PlatformInitiated"]
        }
      }
    }
  }
}
