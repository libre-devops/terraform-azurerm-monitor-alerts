# Plan-time tests for the module. The provider is mocked, so no credentials, no features block,
# and no cloud calls are needed:
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {}

variables {
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01"
  location          = "uksouth"
  tags              = { Environment = "tst" }

  metric_alerts = {
    "Application errors - Failed requests over threshold" = {
      scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
      action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]

      criteria = [{
        metric_namespace = "microsoft.insights/components"
        metric_name      = "requests/failed"
        aggregation      = "Count"
        operator         = "GreaterThan"
        threshold        = 10
        dimensions       = [{ name = "request/resultCode", operator = "Include", values = ["500"] }]
      }]
    }

    "Latency anomaly - Response time deviates from baseline" = {
      scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
      severity         = 2
      tags             = { Team = "platform" }
      action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]

      dynamic_criteria = [{
        metric_namespace  = "microsoft.insights/components"
        metric_name       = "requests/duration"
        aggregation       = "Average"
        operator          = "GreaterThan"
        alert_sensitivity = "Medium"
      }]
    }

    "Availability - Web test failures across locations" = {
      scopes = [
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/webTests/webtest-ldo-uks-tst-01",
        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01",
      ]
      action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]

      web_test_availability_criteria = {
        web_test_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/webTests/webtest-ldo-uks-tst-01"
        component_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"
        failed_location_count = 2
      }
    }
  }

  scheduled_query_alerts = {
    "Ingestion volume - Billable data over baseline" = {
      scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.OperationalInsights/workspaces/log-ldo-uks-tst-01"]
      severity         = 2
      action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]

      custom_properties       = { team = "platform" }
      email_subject           = "Ingestion over baseline"
      identity                = {}
      auto_mitigation_enabled = true
      skip_query_validation   = true

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
    }
  }

  smart_detector_alerts = {
    "Performance degradation - Response time worse than baseline" = {
      detector_type      = "RequestPerformanceDegradationDetector"
      scope_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
      action_group_ids   = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]
    }
  }

  activity_log_alerts = {
    "Service health - Incidents affecting UK South" = {
      scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
      action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]

      criteria = {
        category = "ServiceHealth"

        service_health = {
          events    = ["Incident"]
          locations = ["UK South"]
        }
      }
    }
  }
}

# Defaults: enabled rules, PT5M cadence, auto-mitigation on for metric alerts and off for
# scheduled query rules (matching the providers' resource defaults), Sev3 smart detectors,
# global activity log alerts.
run "sensible_defaults" {
  command = plan

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].enabled == true
    error_message = "Metric alerts should be enabled by default."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].severity == 3
    error_message = "Metric alert severity should default to 3."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].frequency == "PT5M" && azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].window_size == "PT5M"
    error_message = "Metric alerts should default to a PT5M frequency and window."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].auto_mitigate == true
    error_message = "Metric alerts should auto-mitigate by default."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].evaluation_frequency == "PT5M" && azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].window_duration == "PT5M"
    error_message = "Scheduled query rules should default to a PT5M evaluation frequency and window."
  }

  assert {
    condition     = azurerm_monitor_smart_detector_alert_rule.this["Performance degradation - Response time worse than baseline"].severity == "Sev3"
    error_message = "Smart detector severity should default to Sev3."
  }

  assert {
    condition     = azurerm_monitor_smart_detector_alert_rule.this["Performance degradation - Response time worse than baseline"].frequency == "P1D"
    error_message = "Smart detector frequency should default to the daily cadence (only FailureAnomaliesDetector runs PT1M, and Azure auto-creates that rule per component)."
  }

  assert {
    condition     = azurerm_monitor_activity_log_alert.this["Service health - Incidents affecting UK South"].location == "global"
    error_message = "Activity log alerts are a global service."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].resource_group_name == "rg-ldo-uks-tst-01"
    error_message = "The resource group name should be parsed from resource_group_id."
  }
}

# Tags: module tags apply unless the rule sets its own.
run "tags_fall_back_to_module_tags" {
  command = plan

  assert {
    condition     = azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].tags["Environment"] == "tst"
    error_message = "Rules without their own tags should inherit the module tags."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["Latency anomaly - Response time deviates from baseline"].tags["Team"] == "platform" && !contains(keys(azurerm_monitor_metric_alert.this["Latency anomaly - Response time deviates from baseline"].tags), "Environment")
    error_message = "Rules with their own tags should keep them, not merge the module tags."
  }
}

# Criteria rendering: each criteria style lands in its block, dimensions and failing periods
# included, and exactly one style per rule.
run "criteria_styles_render" {
  command = plan

  assert {
    condition     = tolist(azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].criteria)[0].metric_name == "requests/failed"
    error_message = "Static criteria should render into the criteria block."
  }

  assert {
    condition     = tolist(tolist(azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].criteria)[0].dimension)[0].values[0] == "500"
    error_message = "Criteria dimensions should render."
  }

  assert {
    condition     = tolist(azurerm_monitor_metric_alert.this["Latency anomaly - Response time deviates from baseline"].dynamic_criteria)[0].alert_sensitivity == "Medium"
    error_message = "Dynamic criteria should render into the dynamic_criteria block."
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this["Latency anomaly - Response time deviates from baseline"].criteria) == 0
    error_message = "A dynamic-criteria rule should not also render static criteria."
  }

  assert {
    condition     = tolist(azurerm_monitor_metric_alert.this["Availability - Web test failures across locations"].application_insights_web_test_location_availability_criteria)[0].failed_location_count == 2
    error_message = "Web test availability criteria should render into their block."
  }

  assert {
    condition     = tolist(azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].criteria)[0].metric_measure_column == "IngestedGB"
    error_message = "The measured column should render for non-Count aggregations."
  }

  assert {
    condition     = tolist(tolist(azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].criteria)[0].failing_periods)[0].number_of_evaluation_periods == 1
    error_message = "Failing periods should render inside the criteria block."
  }

  assert {
    condition     = tolist(azurerm_monitor_activity_log_alert.this["Service health - Incidents affecting UK South"].criteria)[0].category == "ServiceHealth"
    error_message = "Activity log criteria should render."
  }

  assert {
    condition     = contains(tolist(tolist(tolist(azurerm_monitor_activity_log_alert.this["Service health - Incidents affecting UK South"].criteria)[0].service_health)[0].locations), "UK South")
    error_message = "The service health refinement block should render."
  }
}

# Action wiring: every rule type fans out to its action groups, and the scheduled query rule's
# system-assigned identity block renders.
run "actions_and_identity_wire_up" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_metric_alert.this["Application errors - Failed requests over threshold"].action) == 1
    error_message = "Metric alert action groups should each render an action block."
  }

  assert {
    condition     = length(tolist(azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].action)[0].action_groups) == 1
    error_message = "Scheduled query rules should carry their action groups."
  }

  assert {
    condition     = tolist(azurerm_monitor_scheduled_query_rules_alert_v2.this["Ingestion volume - Billable data over baseline"].identity)[0].type == "SystemAssigned"
    error_message = "identity = {} should default to a system-assigned identity."
  }

  assert {
    condition     = length(tolist(azurerm_monitor_smart_detector_alert_rule.this["Performance degradation - Response time worse than baseline"].action_group)[0].ids) == 1
    error_message = "Smart detector rules should carry their action group ids."
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.this["Service health - Incidents affecting UK South"].action) == 1
    error_message = "Activity log alert action groups should each render an action block."
  }
}

# Validation: a metric alert must use exactly one criteria style.
run "metric_alert_with_two_criteria_styles_is_rejected" {
  command = plan

  variables {
    metric_alerts = {
      "Bad rule - Two criteria styles" = {
        scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]

        criteria = [{
          metric_namespace = "microsoft.insights/components"
          metric_name      = "requests/failed"
          aggregation      = "Count"
          operator         = "GreaterThan"
          threshold        = 10
        }]

        dynamic_criteria = [{
          metric_namespace  = "microsoft.insights/components"
          metric_name       = "requests/duration"
          aggregation       = "Average"
          operator          = "GreaterThan"
          alert_sensitivity = "Medium"
        }]
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "metric_alert_with_no_criteria_is_rejected" {
  command = plan

  variables {
    metric_alerts = {
      "Bad rule - No criteria" = {
        scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

run "metric_alert_severity_out_of_range_is_rejected" {
  command = plan

  variables {
    metric_alerts = {
      "Bad rule - Severity five" = {
        scopes   = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
        severity = 5

        criteria = [{
          metric_namespace = "microsoft.insights/components"
          metric_name      = "requests/failed"
          aggregation      = "Count"
          operator         = "GreaterThan"
          threshold        = 10
        }]
      }
    }
  }

  expect_failures = [var.metric_alerts]
}

# Validation: non-Count aggregation without the measured column is rejected before Azure gets to
# reject it live.
run "scheduled_query_without_measure_column_is_rejected" {
  command = plan

  variables {
    scheduled_query_alerts = {
      "Bad rule - Average without column" = {
        scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.OperationalInsights/workspaces/log-ldo-uks-tst-01"]

        criteria = {
          query                   = "Usage | summarize AvgQuantity = avg(Quantity)"
          operator                = "GreaterThan"
          threshold               = 50
          time_aggregation_method = "Average"
        }
      }
    }
  }

  expect_failures = [var.scheduled_query_alerts]
}

# Validation: smart detector severity is the string form, not a number.
run "smart_detector_numeric_severity_is_rejected" {
  command = plan

  variables {
    smart_detector_alerts = {
      "Bad rule - Numeric severity" = {
        detector_type      = "FailureAnomaliesDetector"
        scope_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/components/appi-ldo-uks-tst-01"]
        severity           = "3"
        action_group_ids   = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Insights/actionGroups/ag-ldo-uks-tst-01"]
      }
    }
  }

  expect_failures = [var.smart_detector_alerts]
}

# Validation: activity log categories are a fixed set.
run "activity_log_bad_category_is_rejected" {
  command = plan

  variables {
    activity_log_alerts = {
      "Bad rule - Unknown category" = {
        scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000"]

        criteria = {
          category = "Login"
        }
      }
    }
  }

  expect_failures = [var.activity_log_alerts]
}
