<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Monitor Alerts

The Azure Monitor alert-rule family in one module: metric alerts, log search (KQL) alerts, smart
detector (anomaly) rules, and activity log alerts, keyed by descriptive names.

[![CI](https://github.com/libre-devops/terraform-azurerm-monitor-alerts/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-monitor-alerts/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-monitor-alerts?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-monitor-alerts/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-monitor-alerts)](./LICENSE)

---

## Overview

Alert rules are where monitoring becomes action, and the four rule families share one shape
(scopes, severity, action groups) while hiding four different resources with four sets of quirks.
The module folds them into sibling maps with the quirks handled:

- **Metric alerts** with all three criteria styles: static thresholds (with dimensions), dynamic
  machine-learned thresholds, and App Insights web test availability. Exactly one style per rule,
  validated at plan time.
- **Log search alerts** (scheduled query rules v2) with the full criteria surface: failing
  periods, dimensions, measured columns, managed identity, and the two proven-live traps
  validated or documented: a non-Count aggregation REQUIRES `metric_measure_column` (validated),
  and Azure checks the KQL against the live workspace schema at create time, so rules created in
  the same apply as their target table need `skip_query_validation = true` (documented on the
  variable).
- **Smart detector rules**, the App Insights AI detectors (failure anomalies, performance
  degradation, exception volume, trace severity, memory leak), with the string `Sev0..Sev4`
  severity oddity validated so a numeric slip fails the plan, not the apply.
- **Activity log alerts** for control-plane, Service Health, and Resource Health events, with the
  category whitelist validated and `location = "global"` handled.

Rule names are the display surface of the alerts experience, so the maps are keyed by descriptive
names ("Application_errors_-_Failed_requests_over_threshold"), never terse identifiers. Rules
without action groups are legal but warn via a `check`: an alert nobody hears is worth seeing at
plan time. The resource group is passed by id and parsed.

## Usage

```hcl
locals {
  alert_scopes = {
    app_insights = module.app_insights.ids["appi-ldo-uks-prd-001"]
    workspace    = module.law.workspace_ids["log-ldo-uks-prd-001"]
  }
}

module "monitor_alerts" {
  source  = "libre-devops/monitor-alerts/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  metric_alerts = {
    "Application_errors_-_Failed_requests_over_threshold" = {
      scopes           = [local.alert_scopes.app_insights]
      severity         = 1
      action_group_ids = [module.action_group.ids["ag-ldo-uks-prd-001"]]

      criteria = [{
        metric_namespace = "microsoft.insights/components"
        metric_name      = "requests/failed"
        aggregation      = "Count"
        operator         = "GreaterThan"
        threshold        = 10
      }]
    }
  }

  scheduled_query_alerts = {
    "Ingestion_volume_-_Billable_data_over_expected_baseline" = {
      scopes           = [local.alert_scopes.workspace]
      severity         = 2
      action_group_ids = [module.action_group.ids["ag-ldo-uks-prd-001"]]

      criteria = {
        query                   = "Usage | where IsBillable == true | summarize IngestedGB = sum(Quantity) / 1000.0"
        operator                = "GreaterThan"
        threshold               = 50
        time_aggregation_method = "Total"
        metric_measure_column   = "IngestedGB"
      }
    }
  }
}
```

The `examples/minimal` stack is the smallest valid call (one self-contained activity log alert);
`examples/complete` exercises all four families, every criteria style, and the fan-out through a
real action group, App Insights component, web test, and Log Analytics workspace.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_activity_log_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_metric_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_monitor_smart_detector_alert_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_smart_detector_alert_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_activity_log_alerts"></a> [activity\_log\_alerts](#input\_activity\_log\_alerts) | Activity log alert rules keyed by name: subscription control-plane events (Administrative),<br/>Service Health, and Resource Health. criteria.category is required; the service\_health and<br/>resource\_health blocks refine their categories. | <pre>map(object({<br/>    scopes      = list(string)<br/>    description = optional(string)<br/>    enabled     = optional(bool, true)<br/>    tags        = optional(map(string))<br/><br/>    action_group_ids   = optional(list(string), [])<br/>    webhook_properties = optional(map(string))<br/><br/>    criteria = object({<br/>      category                = string<br/>      caller                  = optional(string)<br/>      level                   = optional(string)<br/>      levels                  = optional(list(string))<br/>      operation_name          = optional(string)<br/>      resource_group          = optional(string)<br/>      resource_groups         = optional(list(string))<br/>      resource_id             = optional(string)<br/>      resource_ids            = optional(list(string))<br/>      resource_provider       = optional(string)<br/>      resource_providers      = optional(list(string))<br/>      resource_type           = optional(string)<br/>      resource_types          = optional(list(string))<br/>      status                  = optional(string)<br/>      statuses                = optional(list(string))<br/>      sub_status              = optional(string)<br/>      sub_statuses            = optional(list(string))<br/>      recommendation_category = optional(string)<br/>      recommendation_impact   = optional(string)<br/>      recommendation_type     = optional(string)<br/><br/>      service_health = optional(object({<br/>        events    = optional(list(string))<br/>        locations = optional(list(string))<br/>        services  = optional(list(string))<br/>      }))<br/><br/>      resource_health = optional(object({<br/>        current  = optional(list(string))<br/>        previous = optional(list(string))<br/>        reason   = optional(list(string))<br/>      }))<br/>    })<br/>  }))</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the regional alert rules (scheduled query rules). Metric, smart detector, and activity log alerts are location-less or global. | `string` | n/a | yes |
| <a name="input_metric_alerts"></a> [metric\_alerts](#input\_metric\_alerts) | Metric alert rules keyed by name. Names are descriptive (they are the alert's display surface):<br/>static criteria, dynamic (ML thresholds) criteria, and App Insights web test availability<br/>criteria are all supported; exactly one style per rule. action\_group\_ids wires the fan-out. | <pre>map(object({<br/>    scopes      = list(string)<br/>    description = optional(string)<br/>    severity    = optional(number, 3)<br/>    enabled     = optional(bool, true)<br/>    frequency   = optional(string, "PT5M")<br/>    window_size = optional(string, "PT5M")<br/>    tags        = optional(map(string))<br/><br/>    auto_mitigate            = optional(bool, true)<br/>    target_resource_type     = optional(string)<br/>    target_resource_location = optional(string)<br/><br/>    action_group_ids   = optional(list(string), [])<br/>    webhook_properties = optional(map(string))<br/><br/>    criteria = optional(list(object({<br/>      metric_namespace       = string<br/>      metric_name            = string<br/>      aggregation            = string<br/>      operator               = string<br/>      threshold              = number<br/>      skip_metric_validation = optional(bool)<br/>      dimensions = optional(list(object({<br/>        name     = string<br/>        operator = string<br/>        values   = list(string)<br/>      })), [])<br/>    })), [])<br/><br/>    dynamic_criteria = optional(list(object({<br/>      metric_namespace         = string<br/>      metric_name              = string<br/>      aggregation              = string<br/>      operator                 = string<br/>      alert_sensitivity        = string<br/>      evaluation_total_count   = optional(number)<br/>      evaluation_failure_count = optional(number)<br/>      ignore_data_before       = optional(string)<br/>      skip_metric_validation   = optional(bool)<br/>      dimensions = optional(list(object({<br/>        name     = string<br/>        operator = string<br/>        values   = list(string)<br/>      })), [])<br/>    })), [])<br/><br/>    web_test_availability_criteria = optional(object({<br/>      web_test_id           = string<br/>      component_id          = string<br/>      failed_location_count = number<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource id of the resource group the alert rules are created in. The resource group name and subscription are parsed from this id. | `string` | n/a | yes |
| <a name="input_scheduled_query_alerts"></a> [scheduled\_query\_alerts](#input\_scheduled\_query\_alerts) | Log search (KQL) alert rules keyed by name (scheduled query rules v2). Names are descriptive.<br/>Count aggregation counts result rows; any other time\_aggregation\_method requires<br/>metric\_measure\_column naming the numeric column (the API rejects it otherwise, proven live).<br/>Azure validates the KQL against the live workspace schema at rule-create time, so a rule<br/>that targets a table its own apply creates (for example SecurityIncident on a freshly<br/>onboarded Sentinel workspace) needs skip\_query\_validation = true (also proven live). | <pre>map(object({<br/>    scopes       = list(string)<br/>    description  = optional(string)<br/>    display_name = optional(string)<br/>    severity     = optional(number, 3)<br/>    enabled      = optional(bool, true)<br/>    tags         = optional(map(string))<br/><br/>    evaluation_frequency = optional(string, "PT5M")<br/>    window_duration      = optional(string, "PT5M")<br/><br/>    criteria = object({<br/>      query                   = string<br/>      operator                = string<br/>      threshold               = number<br/>      time_aggregation_method = optional(string, "Count")<br/>      metric_measure_column   = optional(string)<br/>      resource_id_column      = optional(string)<br/>      dimensions = optional(list(object({<br/>        name     = string<br/>        operator = string<br/>        values   = list(string)<br/>      })), [])<br/>      failing_periods = optional(object({<br/>        minimum_failing_periods_to_trigger_alert = number<br/>        number_of_evaluation_periods             = number<br/>      }))<br/>    })<br/><br/>    action_group_ids  = optional(list(string), [])<br/>    custom_properties = optional(map(string))<br/>    email_subject     = optional(string)<br/><br/>    identity = optional(object({<br/>      type         = optional(string, "SystemAssigned")<br/>      identity_ids = optional(set(string))<br/>    }))<br/><br/>    auto_mitigation_enabled           = optional(bool, false)<br/>    skip_query_validation             = optional(bool)<br/>    mute_actions_after_alert_duration = optional(string)<br/>    query_time_range_override         = optional(string)<br/>    target_resource_types             = optional(list(string))<br/>    workspace_alerts_storage_enabled  = optional(bool)<br/>  }))</pre> | `{}` | no |
| <a name="input_smart_detector_alerts"></a> [smart\_detector\_alerts](#input\_smart\_detector\_alerts) | Smart detector (anomaly detection) alert rules keyed by name, the App Insights AI-driven<br/>detectors: FailureAnomaliesDetector, RequestPerformanceDegradationDetector,<br/>DependencyPerformanceDegradationDetector, ExceptionVolumeChangedDetector,<br/>TraceSeverityDetector, MemoryLeakDetector. Severity here is the string form (Sev0 to Sev4),<br/>unlike the numeric severities of the other rule types. | <pre>map(object({<br/>    detector_type      = string<br/>    scope_resource_ids = list(string)<br/>    description        = optional(string)<br/>    severity           = optional(string, "Sev3")<br/>    enabled            = optional(bool, true)<br/>    frequency          = optional(string, "PT5M")<br/>    tags               = optional(map(string))<br/><br/>    action_group_ids    = list(string)<br/>    email_subject       = optional(string)<br/>    webhook_payload     = optional(string)<br/>    throttling_duration = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the alert rules (unless a rule sets its own). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_activity_log_alert_ids"></a> [activity\_log\_alert\_ids](#output\_activity\_log\_alert\_ids) | Map of activity log alert name to its resource id. |
| <a name="output_metric_alert_ids"></a> [metric\_alert\_ids](#output\_metric\_alert\_ids) | Map of metric alert name to its resource id. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group name parsed from resource\_group\_id. |
| <a name="output_scheduled_query_alert_identities"></a> [scheduled\_query\_alert\_identities](#output\_scheduled\_query\_alert\_identities) | Map of scheduled query alert name to its identity { principal\_id, tenant\_id } when one is set (for granting the rule reader access on its scopes). |
| <a name="output_scheduled_query_alert_ids"></a> [scheduled\_query\_alert\_ids](#output\_scheduled\_query\_alert\_ids) | Map of scheduled query alert name to its resource id. |
| <a name="output_smart_detector_alert_ids"></a> [smart\_detector\_alert\_ids](#output\_smart\_detector\_alert\_ids) | Map of smart detector alert name to its resource id. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Subscription id parsed from resource\_group\_id. |
| <a name="output_tags"></a> [tags](#output\_tags) | The base tags applied to the alert rules. |
<!-- END_TF_DOCS -->
