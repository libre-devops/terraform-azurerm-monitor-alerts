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
