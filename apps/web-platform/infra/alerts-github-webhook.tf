# PR-H (#3244) Phase 2 — Better Stack alerts for the GitHub webhook surface.
#
# Three monitors, all gated by `var.betterstack_paid_tier` (free-tier path
# fall-back is the Sentry mirror per cq-silent-fallback-must-mirror-to-sentry,
# already exercised at the webhook route layer).
#
# When `var.betterstack_paid_tier == true`, the policy + monitors land via
# the existing inngest.tf-pattern (policy_id is read off betteruptime_policy).
# When false, no Better Stack resources are created and the operator relies
# on Sentry alerts.

resource "betteruptime_policy" "github_webhook" {
  count = var.betterstack_paid_tier ? 1 : 0

  name           = "soleur-github-webhook-prd"
  incident_token = null
  repeat_count   = 0
  repeat_delay   = 60

  steps {
    type        = "escalation"
    wait_before = 0
    urgency_id  = null
    step_members {
      type = "current_on_call"
    }
  }
}

# 1. Sustained 4xx/5xx response rate on /api/webhooks/github.
resource "betteruptime_monitor" "github_webhook_failures" {
  count = var.betterstack_paid_tier ? 1 : 0

  url                   = "https://soleur.ai/api/webhooks/github"
  monitor_type          = "expected_status_code"
  expected_status_codes = [200, 401, 404]
  check_frequency       = 60
  request_timeout       = 10
  recovery_period       = 60
  confirmation_period   = 180
  pronounceable_name    = "GitHub webhook"
  call                  = false
  sms                   = false
  email                 = true
  push                  = false
  team_wait             = 0
  team_name             = "Your team"
  policy_id             = betteruptime_policy.github_webhook[0].id
}

# 2. Signature-verification failure pager — alerts on a spike (potential attack).
# Implemented as a log-stream / log-search monitor; here we provision a
# secondary heartbeat. Operator-paid; free-tier path relies on the Sentry
# `level: error` mirror.
#
# #6537: this comment previously claimed the heartbeat was one "that the webhook route deliberately
# pings on every signature-failure event". NOTHING pings it — no route emits to it. The claim was
# never exercised because `count = 0` under the free tier, so it was free to stay false. Note the
# asymmetry that made it easy to miss: the claim sat on only ONE of the two identical heartbeats
# below; github_api_429_sustained carried no such comment.
#
# Both are declared `feeder: {kind: "none"}` in plugins/soleur/lib/heartbeat-manifest.ts and tracked
# by #6549. On a paid-tier flip each needs a real emitter or deletion — and per #6210, a ping must be
# verified BEFORE either is unpaused.
resource "betteruptime_heartbeat" "github_webhook_sig_failures" {
  count = var.betterstack_paid_tier ? 1 : 0

  name      = "soleur-github-webhook-sig-failures-prd"
  period    = 300
  grace     = 60
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  paused    = true # Operator unpauses when the webhook lands in prd.
  team_name = "Your team"
  policy_id = betteruptime_policy.github_webhook[0].id
}

# 3. GitHub API 429 (secondary rate limit) sustained heartbeat.
resource "betteruptime_heartbeat" "github_api_429_sustained" {
  count = var.betterstack_paid_tier ? 1 : 0

  name      = "soleur-github-api-429-sustained-prd"
  period    = 900
  grace     = 120
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  paused    = true
  team_name = "Your team"
  policy_id = betteruptime_policy.github_webhook[0].id
}
