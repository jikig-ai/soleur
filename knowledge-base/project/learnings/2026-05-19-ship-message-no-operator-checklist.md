---
date: 2026-05-19
category: workflow-patterns
topic: Ship-message anti-pattern — operator checklist hides production bugs
trigger_prs:
  - "#4062 (TR9 PR-2 cron-follow-through-monitor)"
related_prs:
  - "#3985 (TR9 PR-1 cron-daily-triage)"
related_issues:
  - "#4017 (P1: PR-1 substrate missed both scheduled fires)"
  - "#4079 (PR-2 follow-through with auto-verification)"
related_rules:
  - "hr-ship-message-no-operator-checklist (NEW)"
  - "hr-no-dashboard-eyeball-pull-data-yourself"
  - "hr-exhaust-all-automated-options-before"
  - "hr-never-label-any-step-as-manual-without"
---

# Ship messages MUST NOT end with operator checklists

## The anti-pattern (what I did wrong on PR-2 #4062)

After merging PR-2, the ship summary I produced ended with:

> **Post-merge operator checklist:**
> 1. `apply-sentry-infra.yml` should fire on the main commit and create the `scheduled-follow-through` Sentry cron monitor — verify in Sentry UI
> 2. Manual-trigger smoke: `inngest send cron/follow-through-monitor.manual-trigger` after Inngest worker picks up the deploy
> 3. Verify GH_TOKEN scope minimization in Doppler (user-impact-reviewer condition)
> 4. First scheduled fire: Monday 09:00 UTC — watch Sentry heartbeat for `status=ok`

The user pushed back: "Soleur users will be overly confused by that and should not get to that level of details, you should find a way to do/validate/verify those yourself automatically."

## Why it's load-bearing (the bug the checklist would have hidden)

When I actually executed the verification myself (instead of dumping it), I found:

```bash
curl -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/monitors/scheduled-daily-triage/checkins/?limit=5"
```

Returned:

| Date (UTC) | Status |
|---|---|
| 2026-05-17 18:18 | `ok` (operator ad-hoc smoke test) |
| 2026-05-18 04:00 | **`missed`** |
| 2026-05-18 07:54 | `timeout` |
| 2026-05-19 04:00 | **`missed`** |

PR-1's `cron-daily-triage` had NEVER fired on schedule since merging (substrate failure). PR-2 was about to inherit this silent failure. The checklist would have left the bug undetected for another day — neither I nor the user would have actioned a "Monday 09:00 UTC heartbeat" check until next Monday.

**Filed:** #4017 reclassified from follow-through → P1 bug with auto-verification one-liner embedded.

## The rule (codified)

`hr-ship-message-no-operator-checklist` in `AGENTS.core.md`:

> Ship-time post-merge verification MUST auto-execute (Doppler→Sentry/Inngest/Cloudflare API, MCP, CLI per `hr-exhaust-all-automated-options-before`) OR file a tracked GitHub follow-through issue carrying an `auto_command:` YAML block; never end a ship summary with a prose "operator checklist" for users to action.

## The Doppler→vendor-API pattern (always-available substrate)

For most "verify the monitor / heartbeat / deployment / secret" needs, the data is reachable via this 3-line preamble:

```bash
SENTRY_AUTH_TOKEN=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_AUTH_TOKEN)
SENTRY_ORG=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_ORG)
SENTRY_API_HOST=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_API_HOST)
```

Then any `https://${SENTRY_API_HOST}/api/0/...` curl works. Same shape for Cloudflare, Stripe (different config keys). Inngest production is self-hosted on the VM (`127.0.0.1:8288`) so its manual-trigger smoke remains operator-on-VM — but that's the exception, not the default.

## What's genuinely operator-only (legit exceptions)

- **Required-reviewer environment approvals** (`apply-sentry-infra.yml` gated on `sentry-infra-apply` environment with `deruelle` as required reviewer). Approving from Claude would defeat `hr-menu-option-ack-not-prod-write-auth`.
- **CAPTCHAs / SSO consent screens** (operator pastes, Soleur drives).
- **Payment/billing entry** at the exact form.
- **VM-local SSH for self-hosted services** when the service binds `127.0.0.1` only (Inngest production is one such case).

For these: the follow-through issue STILL doesn't dump a checklist into chat — it carries the exact command in its body so the issue itself is self-describing.

## Pattern for follow-through issues (`auto_command:` YAML block)

Replace `type: manual` + operator-checklist prose with:

```yaml
type: auto
auto_command: |
  doppler login &&
  SENTRY_AUTH_TOKEN=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_AUTH_TOKEN) &&
  SENTRY_ORG=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_ORG) &&
  SENTRY_API_HOST=$(doppler secrets get --project soleur --config prd_scheduled --plain SENTRY_API_HOST) &&
  curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/monitors/<slug>/checkins/?limit=5" |
    jq -e '.[] | select(.dateAdded >= "<start>" and .dateAdded < "<end>" and .status == "ok")'
sla_business_days: 1
```

Pass: `jq -e` exit 0. Fail: exit 1 → escalate. The daily follow-through monitor (`scheduled-follow-through`, when re-routed through the new TR9 PR-2 Inngest cron) can execute this directly once Doppler-secret access is widened to the worker.

## Trigger phrases to STOP on (self-check)

If you're about to type any of these in a ship/work summary, STOP and pull the data yourself:

- "Post-merge operator checklist:"
- "Operator must:"
- "Verify in [Sentry/Inngest/Cloudflare/etc.] UI"
- "After deploy, run …"
- "First fire: <date> — watch …"

Each is a punt to dashboard-eyeballing the rule already forbids.
