variable "activity_log_alerts" {
  description = <<-EOT
    Activity log alert rules keyed by name: subscription control-plane events (Administrative),
    Service Health, and Resource Health. criteria.category is required; the service_health and
    resource_health blocks refine their categories.
  EOT
  type = map(object({
    scopes      = list(string)
    description = optional(string)
    enabled     = optional(bool, true)
    tags        = optional(map(string))

    action_group_ids   = optional(list(string), [])
    webhook_properties = optional(map(string))

    criteria = object({
      category                = string
      caller                  = optional(string)
      level                   = optional(string)
      levels                  = optional(list(string))
      operation_name          = optional(string)
      resource_group          = optional(string)
      resource_groups         = optional(list(string))
      resource_id             = optional(string)
      resource_ids            = optional(list(string))
      resource_provider       = optional(string)
      resource_providers      = optional(list(string))
      resource_type           = optional(string)
      resource_types          = optional(list(string))
      status                  = optional(string)
      statuses                = optional(list(string))
      sub_status              = optional(string)
      sub_statuses            = optional(list(string))
      recommendation_category = optional(string)
      recommendation_impact   = optional(string)
      recommendation_type     = optional(string)

      service_health = optional(object({
        events    = optional(list(string))
        locations = optional(list(string))
        services  = optional(list(string))
      }))

      resource_health = optional(object({
        current  = optional(list(string))
        previous = optional(list(string))
        reason   = optional(list(string))
      }))
    })
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.activity_log_alerts) :
      contains(["Administrative", "Autoscale", "Policy", "Recommendation", "ResourceHealth", "Security", "ServiceHealth"], a.criteria.category)
    ])
    error_message = "activity log criteria.category must be one of Administrative, Autoscale, Policy, Recommendation, ResourceHealth, Security, ServiceHealth."
  }
}

variable "location" {
  description = "Azure region for the regional alert rules (scheduled query rules). Metric, smart detector, and activity log alerts are location-less or global."
  type        = string
}

variable "metric_alerts" {
  description = <<-EOT
    Metric alert rules keyed by name. Names are descriptive (they are the alert's display surface):
    static criteria, dynamic (ML thresholds) criteria, and App Insights web test availability
    criteria are all supported; exactly one style per rule. action_group_ids wires the fan-out.
  EOT
  type = map(object({
    scopes      = list(string)
    description = optional(string)
    severity    = optional(number, 3)
    enabled     = optional(bool, true)
    frequency   = optional(string, "PT5M")
    window_size = optional(string, "PT5M")
    tags        = optional(map(string))

    auto_mitigate            = optional(bool, true)
    target_resource_type     = optional(string)
    target_resource_location = optional(string)

    action_group_ids   = optional(list(string), [])
    webhook_properties = optional(map(string))

    criteria = optional(list(object({
      metric_namespace       = string
      metric_name            = string
      aggregation            = string
      operator               = string
      threshold              = number
      skip_metric_validation = optional(bool)
      dimensions = optional(list(object({
        name     = string
        operator = string
        values   = list(string)
      })), [])
    })), [])

    dynamic_criteria = optional(list(object({
      metric_namespace         = string
      metric_name              = string
      aggregation              = string
      operator                 = string
      alert_sensitivity        = string
      evaluation_total_count   = optional(number)
      evaluation_failure_count = optional(number)
      ignore_data_before       = optional(string)
      skip_metric_validation   = optional(bool)
      dimensions = optional(list(object({
        name     = string
        operator = string
        values   = list(string)
      })), [])
    })), [])

    web_test_availability_criteria = optional(object({
      web_test_id           = string
      component_id          = string
      failed_location_count = number
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.metric_alerts) :
      length([for c in [length(a.criteria) > 0, length(a.dynamic_criteria) > 0, a.web_test_availability_criteria != null] : c if c]) == 1
    ])
    error_message = "every metric alert uses exactly one criteria style: criteria, dynamic_criteria, or web_test_availability_criteria."
  }

  validation {
    condition     = alltrue([for a in values(var.metric_alerts) : a.severity >= 0 && a.severity <= 4])
    error_message = "metric alert severity is 0 (critical) to 4 (verbose)."
  }
}

variable "resource_group_id" {
  description = "Resource id of the resource group the alert rules are created in. The resource group name and subscription are parsed from this id."
  type        = string

  validation {
    condition     = try(provider::azurerm::parse_resource_id(var.resource_group_id).resource_type, "") == "resourceGroups"
    error_message = "resource_group_id must be a resource group resource id."
  }
}

variable "scheduled_query_alerts" {
  description = <<-EOT
    Log search (KQL) alert rules keyed by name (scheduled query rules v2). Names are descriptive.
    Count aggregation counts result rows; any other time_aggregation_method requires
    metric_measure_column naming the numeric column (the API rejects it otherwise, proven live).
    Azure validates the KQL against the live workspace schema at rule-create time, so a rule
    that targets a table its own apply creates (for example SecurityIncident on a freshly
    onboarded Sentinel workspace) needs skip_query_validation = true (also proven live).
  EOT
  type = map(object({
    scopes       = list(string)
    description  = optional(string)
    display_name = optional(string)
    severity     = optional(number, 3)
    enabled      = optional(bool, true)
    tags         = optional(map(string))

    evaluation_frequency = optional(string, "PT5M")
    window_duration      = optional(string, "PT5M")

    criteria = object({
      query                   = string
      operator                = string
      threshold               = number
      time_aggregation_method = optional(string, "Count")
      metric_measure_column   = optional(string)
      resource_id_column      = optional(string)
      dimensions = optional(list(object({
        name     = string
        operator = string
        values   = list(string)
      })), [])
      failing_periods = optional(object({
        minimum_failing_periods_to_trigger_alert = number
        number_of_evaluation_periods             = number
      }))
    })

    action_group_ids  = optional(list(string), [])
    custom_properties = optional(map(string))
    email_subject     = optional(string)

    identity = optional(object({
      type         = optional(string, "SystemAssigned")
      identity_ids = optional(set(string))
    }))

    auto_mitigation_enabled           = optional(bool, false)
    skip_query_validation             = optional(bool)
    mute_actions_after_alert_duration = optional(string)
    query_time_range_override         = optional(string)
    target_resource_types             = optional(list(string))
    workspace_alerts_storage_enabled  = optional(bool)
  }))
  default = {}

  validation {
    condition = alltrue([
      for a in values(var.scheduled_query_alerts) :
      a.criteria.time_aggregation_method == "Count" || a.criteria.metric_measure_column != null
    ])
    error_message = "time_aggregation_method other than Count requires metric_measure_column naming the numeric column (Azure rejects the rule otherwise)."
  }

  validation {
    condition     = alltrue([for a in values(var.scheduled_query_alerts) : a.severity >= 0 && a.severity <= 4])
    error_message = "scheduled query alert severity is 0 (critical) to 4 (verbose)."
  }
}

variable "smart_detector_alerts" {
  description = <<-EOT
    Smart detector (anomaly detection) alert rules keyed by name, the App Insights AI-driven
    detectors: FailureAnomaliesDetector, RequestPerformanceDegradationDetector,
    DependencyPerformanceDegradationDetector, ExceptionVolumeChangedDetector,
    TraceSeverityDetector, MemoryLeakDetector. Severity here is the string form (Sev0 to Sev4),
    unlike the numeric severities of the other rule types.
  EOT
  type = map(object({
    detector_type      = string
    scope_resource_ids = list(string)
    description        = optional(string)
    severity           = optional(string, "Sev3")
    enabled            = optional(bool, true)
    frequency          = optional(string, "PT5M")
    tags               = optional(map(string))

    action_group_ids    = list(string)
    email_subject       = optional(string)
    webhook_payload     = optional(string)
    throttling_duration = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.smart_detector_alerts) : contains(["Sev0", "Sev1", "Sev2", "Sev3", "Sev4"], a.severity)])
    error_message = "smart detector severity is the string form Sev0 (critical) to Sev4 (verbose), not a number."
  }
}

variable "tags" {
  description = "Tags applied to the alert rules (unless a rule sets its own)."
  type        = map(string)
  default     = {}
}
