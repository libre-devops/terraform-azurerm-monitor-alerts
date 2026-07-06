# Post-plan sanity checks: informational (warn), they never fail an apply.

check "has_alerts" {
  assert {
    condition     = length(var.metric_alerts) + length(var.scheduled_query_alerts) + length(var.smart_detector_alerts) + length(var.activity_log_alerts) > 0
    error_message = "No alert rules are defined: the module call creates nothing."
  }
}

# An alert rule with no action groups evaluates into the void (visible only to whoever browses the
# portal). Legal, occasionally deliberate, always worth seeing.
check "alerts_have_actions" {
  assert {
    condition = alltrue(concat(
      [for a in values(var.metric_alerts) : length(a.action_group_ids) > 0],
      [for a in values(var.scheduled_query_alerts) : length(a.action_group_ids) > 0],
      [for a in values(var.activity_log_alerts) : length(a.action_group_ids) > 0],
    ))
    error_message = "At least one alert rule has no action groups: it fires without notifying anyone."
  }
}
