# The alert-rule family in one module: metric alerts (static, dynamic, and web test criteria),
# log search alerts (scheduled query rules v2), smart detector (anomaly) rules, and activity log
# alerts, as sibling maps sharing the scopes/severity/action-group shape. Rule names are
# descriptive on purpose: they are the display surface of the alerts experience. The resource
# group is passed by id and parsed.
locals {
  rg      = provider::azurerm::parse_resource_id(var.resource_group_id)
  rg_name = local.rg.resource_group_name
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.metric_alerts

  resource_group_name = local.rg_name
  tags                = each.value.tags != null ? each.value.tags : var.tags

  name        = each.key
  description = each.value.description
  severity    = each.value.severity
  enabled     = each.value.enabled
  frequency   = each.value.frequency
  window_size = each.value.window_size
  scopes      = each.value.scopes

  auto_mitigate            = each.value.auto_mitigate
  target_resource_type     = each.value.target_resource_type
  target_resource_location = each.value.target_resource_location

  dynamic "action" {
    for_each = toset(each.value.action_group_ids)

    content {
      action_group_id    = action.value
      webhook_properties = each.value.webhook_properties
    }
  }

  dynamic "criteria" {
    for_each = each.value.criteria

    content {
      metric_namespace       = criteria.value.metric_namespace
      metric_name            = criteria.value.metric_name
      aggregation            = criteria.value.aggregation
      operator               = criteria.value.operator
      threshold              = criteria.value.threshold
      skip_metric_validation = criteria.value.skip_metric_validation

      dynamic "dimension" {
        for_each = criteria.value.dimensions

        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "dynamic_criteria" {
    for_each = each.value.dynamic_criteria

    content {
      metric_namespace         = dynamic_criteria.value.metric_namespace
      metric_name              = dynamic_criteria.value.metric_name
      aggregation              = dynamic_criteria.value.aggregation
      operator                 = dynamic_criteria.value.operator
      alert_sensitivity        = dynamic_criteria.value.alert_sensitivity
      evaluation_total_count   = dynamic_criteria.value.evaluation_total_count
      evaluation_failure_count = dynamic_criteria.value.evaluation_failure_count
      ignore_data_before       = dynamic_criteria.value.ignore_data_before
      skip_metric_validation   = dynamic_criteria.value.skip_metric_validation

      dynamic "dimension" {
        for_each = dynamic_criteria.value.dimensions

        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
    }
  }

  dynamic "application_insights_web_test_location_availability_criteria" {
    for_each = each.value.web_test_availability_criteria != null ? [each.value.web_test_availability_criteria] : []

    content {
      web_test_id           = application_insights_web_test_location_availability_criteria.value.web_test_id
      component_id          = application_insights_web_test_location_availability_criteria.value.component_id
      failed_location_count = application_insights_web_test_location_availability_criteria.value.failed_location_count
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each = var.scheduled_query_alerts

  resource_group_name = local.rg_name
  location            = var.location
  tags                = each.value.tags != null ? each.value.tags : var.tags

  name         = each.key
  description  = each.value.description
  display_name = each.value.display_name
  severity     = each.value.severity
  enabled      = each.value.enabled
  scopes       = each.value.scopes

  evaluation_frequency = each.value.evaluation_frequency
  window_duration      = each.value.window_duration

  criteria {
    query                   = each.value.criteria.query
    operator                = each.value.criteria.operator
    threshold               = each.value.criteria.threshold
    time_aggregation_method = each.value.criteria.time_aggregation_method
    metric_measure_column   = each.value.criteria.metric_measure_column
    resource_id_column      = each.value.criteria.resource_id_column

    dynamic "dimension" {
      for_each = each.value.criteria.dimensions

      content {
        name     = dimension.value.name
        operator = dimension.value.operator
        values   = dimension.value.values
      }
    }

    dynamic "failing_periods" {
      for_each = each.value.criteria.failing_periods != null ? [each.value.criteria.failing_periods] : []

      content {
        minimum_failing_periods_to_trigger_alert = failing_periods.value.minimum_failing_periods_to_trigger_alert
        number_of_evaluation_periods             = failing_periods.value.number_of_evaluation_periods
      }
    }
  }

  action {
    action_groups     = each.value.action_group_ids
    custom_properties = each.value.custom_properties
    email_subject     = each.value.email_subject
  }

  dynamic "identity" {
    for_each = each.value.identity != null ? [each.value.identity] : []

    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  auto_mitigation_enabled           = each.value.auto_mitigation_enabled
  skip_query_validation             = each.value.skip_query_validation
  mute_actions_after_alert_duration = each.value.mute_actions_after_alert_duration
  query_time_range_override         = each.value.query_time_range_override
  target_resource_types             = each.value.target_resource_types
  workspace_alerts_storage_enabled  = each.value.workspace_alerts_storage_enabled
}

resource "azurerm_monitor_smart_detector_alert_rule" "this" {
  for_each = var.smart_detector_alerts

  resource_group_name = local.rg_name
  tags                = each.value.tags != null ? each.value.tags : var.tags

  name               = each.key
  description        = each.value.description
  detector_type      = each.value.detector_type
  scope_resource_ids = each.value.scope_resource_ids
  severity           = each.value.severity
  enabled            = each.value.enabled
  frequency          = each.value.frequency

  throttling_duration = each.value.throttling_duration

  action_group {
    ids             = each.value.action_group_ids
    email_subject   = each.value.email_subject
    webhook_payload = each.value.webhook_payload
  }
}

resource "azurerm_monitor_activity_log_alert" "this" {
  for_each = var.activity_log_alerts

  resource_group_name = local.rg_name
  # Activity log alerts are a global service.
  location = "global"
  tags     = each.value.tags != null ? each.value.tags : var.tags

  name        = each.key
  description = each.value.description
  enabled     = each.value.enabled
  scopes      = each.value.scopes

  dynamic "action" {
    for_each = toset(each.value.action_group_ids)

    content {
      action_group_id    = action.value
      webhook_properties = each.value.webhook_properties
    }
  }

  criteria {
    category                = each.value.criteria.category
    caller                  = each.value.criteria.caller
    level                   = each.value.criteria.level
    levels                  = each.value.criteria.levels
    operation_name          = each.value.criteria.operation_name
    resource_group          = each.value.criteria.resource_group
    resource_groups         = each.value.criteria.resource_groups
    resource_id             = each.value.criteria.resource_id
    resource_ids            = each.value.criteria.resource_ids
    resource_provider       = each.value.criteria.resource_provider
    resource_providers      = each.value.criteria.resource_providers
    resource_type           = each.value.criteria.resource_type
    resource_types          = each.value.criteria.resource_types
    status                  = each.value.criteria.status
    statuses                = each.value.criteria.statuses
    sub_status              = each.value.criteria.sub_status
    sub_statuses            = each.value.criteria.sub_statuses
    recommendation_category = each.value.criteria.recommendation_category
    recommendation_impact   = each.value.criteria.recommendation_impact
    recommendation_type     = each.value.criteria.recommendation_type

    dynamic "service_health" {
      for_each = each.value.criteria.service_health != null ? [each.value.criteria.service_health] : []

      content {
        events    = service_health.value.events
        locations = service_health.value.locations
        services  = service_health.value.services
      }
    }

    dynamic "resource_health" {
      for_each = each.value.criteria.resource_health != null ? [each.value.criteria.resource_health] : []

      content {
        current  = resource_health.value.current
        previous = resource_health.value.previous
        reason   = resource_health.value.reason
      }
    }
  }
}
