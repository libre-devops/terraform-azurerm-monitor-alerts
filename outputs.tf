output "activity_log_alert_ids" {
  description = "Map of activity log alert name to its resource id."
  value       = { for k, v in azurerm_monitor_activity_log_alert.this : k => v.id }
}

output "metric_alert_ids" {
  description = "Map of metric alert name to its resource id."
  value       = { for k, v in azurerm_monitor_metric_alert.this : k => v.id }
}

output "resource_group_name" {
  description = "Resource group name parsed from resource_group_id."
  value       = local.rg_name
}

output "scheduled_query_alert_identities" {
  description = "Map of scheduled query alert name to its identity { principal_id, tenant_id } when one is set (for granting the rule reader access on its scopes)."
  value = {
    for k, v in azurerm_monitor_scheduled_query_rules_alert_v2.this : k => try({
      principal_id = v.identity[0].principal_id
      tenant_id    = v.identity[0].tenant_id
    }, null)
  }
}

output "scheduled_query_alert_ids" {
  description = "Map of scheduled query alert name to its resource id."
  value       = { for k, v in azurerm_monitor_scheduled_query_rules_alert_v2.this : k => v.id }
}

output "smart_detector_alert_ids" {
  description = "Map of smart detector alert name to its resource id."
  value       = { for k, v in azurerm_monitor_smart_detector_alert_rule.this : k => v.id }
}

output "subscription_id" {
  description = "Subscription id parsed from resource_group_id."
  value       = local.rg.subscription_id
}

output "tags" {
  description = "The base tags applied to the alert rules."
  value       = var.tags
}
