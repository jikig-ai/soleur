---
title: CI Required Ruleset Drift (bypass_actors · required_status_checks · enforcement)
audience: operator
on_page_for: cron-ruleset-bypass-audit
issues: [3544, 3542, 2719, 3569, 4397, 5759, 6061]
brand_survival_threshold: single-user incident
last_updated: 2026-07-05
---

# CI Required Ruleset Drift

This runbook covers triage and remediation when the **`cron-ruleset-bypass-audit`
Inngest function** files a drift issue titled `[Ruleset Audit] CI Required
ruleset drift`.

> **Mechanism note (2026-06-30).** The audit used to be the GitHub Actions
> workflow `scheduled-ruleset-bypass-audit.yml`. That workflow was deleted in
> #4483 (TR9 Phase 2) and the audit re-implemented as the Inngest cron
> [`cron-ruleset-bypass-audit`](../../../../apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts)
> (daily 06:13 UTC). The original port covered only `bypass_actors`;
> `required_status_checks` + `enforcement` detection and auto-close-on-green
> were dropped and later restored (#4397, #5759). There is no `gh workflow run`
> path any more — fire the audit on demand with the **`soleur:trigger-cron`**
> skill (below).

## Why this audit exists

The R15 mitigation (#3542, PR #3543) made `skill-security-scan PR gate` a
required check on `main` via the "CI Required" repository ruleset (#14145388).
The ruleset is now **Terraform-managed** (`infra/github/ruleset-ci-required.tf`,
applied on merge by `.github/workflows/apply-github-infra.yml`). Three live
properties of that ruleset are security-load-bearing, and an out-of-band GitHub
UI edit to any of them leaves no repo-side trace — GitHub's organization audit
log is the only surface. This daily audit closes that gap with a 24-hour
worst-case detection window:

1. **`bypass_actors`** — who may merge around the required checks. A widened
   entry (new actor, or mode broadened `pull_request` → `always`) lets a
   malicious skill-install PR land without the gate running. One merged
   skill-install = installable-skill code-execution on any operator who pulls.
2. **`required_status_checks`** — which checks are required. Un-requiring a gate
   (e.g. dropping `skill-security-scan PR gate`) silently removes the
   protection. The integration_id is part of the match: `CodeQL` is pinned to
   the GitHub Advanced Security app (57789); a same-named check from
   `github-actions[bot]` (15368) would NOT satisfy the gate.
3. **`enforcement`** — must be `"active"`. If set to `disabled`/`evaluate`,
   **every** required check and bypass guarantee is suspended at once.

Brand-survival threshold: **single-user incident** (inherited from #2719). One
unauthorized merge under a widened bypass — or one un-required gate — is the
brand-ending incident. Threshold change requires CPO + user-impact-reviewer
sign-off.

## Source of truth & the canonical snapshots

The live ruleset's source of truth is **Terraform** (`infra/github/
ruleset-ci-required.tf`). The audit compares the live ruleset against two
canonical JSON snapshots the Inngest function reads via the GitHub contents API:

- `scripts/ci-required-ruleset-canonical-bypass-actors.json`
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`

These snapshots are kept in **lockstep with the `.tf`** by the sync gate
`T-rsc-9` in `tests/scripts/test-audit-ruleset-bypass.sh` (run in CI via
`scripts/test-all.sh`). Editing `ruleset-ci-required.tf` without updating the
matching canonical JSON fails CI. This gate is the root-cause fix for #4397,
where the snapshot silently went stale (5 checks) while Terraform widened the
live ruleset (16) and nothing forced them back into agreement.

## Findings & labels

The audit assembles a list of findings and files **one** combined issue
(`[Ruleset Audit] CI Required ruleset drift`) when any fire, then auto-closes it
on the next green run. Labels: `ci/auth-broken`, `compliance/critical`,
`priority/p1-high`, `domain/legal` (CLO routing).

| Finding | `critical` | Direction that fires |
|---------|------------|----------------------|
| `enforcement` not `active` | yes | ruleset suspended |
| `bypass_actors` widened | yes | actor present live but NOT in canonical |
| `required_status_checks` dropped | yes | check in canonical but NOT enforced live (gate un-required) |
| `required_status_checks` diverged | no | check enforced live but NOT in canonical (snapshot stale — reconcile) |

A critical finding sets the Sentry heartbeat (`scheduled-ruleset-bypass-audit`)
to failing. A divergence-only finding still files the issue (so the stale
snapshot gets reconciled) but keeps the heartbeat green — merge-security is
intact. Guard errors (canonical unreadable, ruleset missing, token under-scoped)
throw and surface via the Sentry monitor + `reportSilentFallback` — **no SSH is
needed to see them** (per `hr-no-ssh-fallback-in-runbooks`; observability layer:
Sentry → the `scheduled-ruleset-bypass-audit` monitor, and Better Stack logs for
the `cron-ruleset-bypass-audit` function).

## CLA Required ruleset drift (#6061)

The same `cron-ruleset-bypass-audit` function audits a **second** ruleset — the
**"CLA Required"** ruleset (id `13304872`) — in its own `step.run` step, and
files a separately-titled issue **`[Ruleset Audit] CLA Required ruleset drift`**
(same labels: `ci/auth-broken`, `compliance/critical`, `priority/p1-high`,
`domain/legal`). A CLA-step fault or drift cannot abort the CI step, and vice
versa.

**Source of truth (differs from CI):** the CLA ruleset is **imperatively
managed** by [`scripts/create-cla-required-ruleset.sh`](../../../../scripts/create-cla-required-ruleset.sh)
— there is **no Terraform** for it yet (Terraform-ifying it is a tracked
follow-up, #6061 Phase 6.1). The audit compares the live ruleset against two
canonical snapshots:

- `scripts/ci-cla-required-ruleset-canonical-bypass-actors.json`
- `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`

kept in lockstep with the create-script's inline blocks by the `T-cla-1` /
`T-cla-1b` sync gates in `tests/scripts/test-audit-ruleset-bypass.sh`, and with
`scripts/required-checks.txt` by Test 7 in
`plugins/soleur/test/required-checks-canonical-parity.test.sh`.

**CLA drift classes:**

| Finding | `critical` | What it means |
|---------|------------|---------------|
| `cla-check` / `cla-evidence` dropped (or the whole RSC rule gone) | yes | a PR could merge without the CLA-signature / CLA-evidence gate |
| `bypass_actors` widened | yes | a named actor can merge around the CLA gate while the gate still looks intact (the quiet defeat vector) |
| `enforcement` not `active` | yes | the entire CLA gate is suspended |
| a NEW `cla-*` context required live but unmirrored to `required-checks.txt` | no (liveness) | bot PRs deadlock (no synthetic posted for the new context) — a green heartbeat does NOT mean "no CLA problem" here |

> The `Integration:1236702/always` bypass actor is the **CLA bot** — it
> legitimately needs `always` to update CLA status and is IN the canonical, so
> the audit flags only *additional* bypass actors.

**Remedy the `domain/legal` recipient must action (NOT just "reconcile the
canonical"):** a real CLA drift means unsigned external contributions may have
merged to `main` without a recorded CLA. Beyond reconciling the ruleset, the
CLO/operator must **chase the contributor's CLA signature post-hoc** (request it
from the identifiable contributor) or, if unobtainable (anonymous/adversarial
author), **revert the unsigned contribution** to keep the IP-provenance chain
auditable. If the drift was an *authorized* change, reconcile
`scripts/create-cla-required-ruleset.sh` **and** the two CLA canonical JSONs
together (the sync gates require both).

**Probe the live CLA state directly** (read-only, admin-scoped workstation):

```bash
gh api repos/jikig-ai/soleur/rulesets/13304872 \
  --jq '{enforcement, bypass_actors, required_status_checks: [.rules[]
        | select(.type=="required_status_checks")
        | .parameters.required_status_checks[]]}'
```

Guard faults on the CLA path (canonical empty/corrupt on `main`, `bypass_actors`
redacted by token scope, network/API error) are routed to Sentry via
`reportSilentFallback` + degrade the heartbeat — they do **NOT** file a
`compliance/critical` drift issue (a corrupt-JSON-on-main fault is an ops/infra
issue for the CTO, not a legal-compliance drift).

## Run the audit on demand (no SSH)

```bash
# From any worktree (not the bare root):
plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  --event cron/ruleset-bypass-audit.manual-trigger
# HTTP 202 = dispatched. Watch the run in the Inngest dashboard / Better Stack;
# on green it auto-closes any open drift issue.
```

Probe the live state directly from an admin-scoped workstation (read-only):

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  --jq '{enforcement, bypass_actors, required_status_checks: [.rules[]
        | select(.type=="required_status_checks")
        | .parameters.required_status_checks[]]}'
```

## Triage by drift kind

### Drift = legitimate authorized change

(e.g. onboarding a 2nd admin to `bypass_actors`, or adding a required check)

1. Verify with the editing actor via the GitHub organization audit log
   (Settings → Audit log → filter `repository_ruleset`).
2. Open a PR that updates **`infra/github/ruleset-ci-required.tf`** (the source
   of truth) AND the matching canonical JSON snapshot in the same change — the
   `T-rsc-9` sync gate requires both. For a `bypass_actors` change, add
   `requires_cpo_signoff: true` to the PR body (inherits #2719's posture) and
   append a row to `knowledge-base/legal/compliance-posture.md` `#2719` section.
3. Merge. `apply-github-infra.yml` reconciles the live ruleset; the next audit
   run auto-closes the drift issue.

### Drift = unauthorized broadening / un-requiring

(a `bypass_actors` widen, a dropped required check, or enforcement turned off,
with no authorizing PR)

1. **Rotate immediately:** if a non-trusted org admin gained write access,
   rotate the org owner credentials (Settings → Organization → Owners).
2. **Restore from Terraform:** the `.tf` is the source of truth. Re-apply it via
   the manual escape hatch (no destructive plan expected):
   ```bash
   gh workflow run apply-github-infra.yml -f reason='restore ruleset after unauthorized drift'
   ```
   Confirm the plan only re-adds the removed/known-good state before it applies
   (CODEOWNERS pins `/infra/github/` to `@deruelle`; a destructive plan also
   needs `[ack-destroy]` per `hr-menu-option-ack-not-prod-write-auth`).
3. **Post-mortem:** file under
   `knowledge-base/project/learnings/security-issues/` with timeline, blast
   radius, remediation, and prevention.
4. **Update compliance-posture.md:** add an entry under Active Items noting the
   incident and its resolution.

### Drift = `enforcement` not active

The ruleset still exists at id `14145388` but `enforcement` is `disabled` or
`evaluate` — every required check is suspended.

1. Confirm: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.enforcement'`.
2. Re-enable via Settings → Rules → Rulesets → CI Required → Enforcement status
   → Active (no `gh` subcommand exists for this today), OR re-apply the `.tf`
   (which pins `enforcement = "active"`) via the escape hatch above.
3. Investigate who/when via the org audit log; if unauthorized, treat as the
   "unauthorized broadening" path (rotate, post-mortem).

### Guard malfunction (the audit itself errored)

The audit threw instead of completing — surfaced via the Sentry monitor
`scheduled-ruleset-bypass-audit` and `reportSilentFallback`, not a drift issue.
Common causes:

| Symptom in logs | Likely cause | Fix |
|---|---|---|
| `missing bypass_actors — installation token may lack administration:read` | driftguard App lost `administration:read`, OR the install was removed | Probe live state first (read-only `gh api` above). If the ruleset is healthy, the App token is the broken surface — see "Token scope" below. |
| `Ruleset "CI Required" not found` | ruleset deleted entirely | **Probe first** (`gh api …/rulesets/14145388`). If 404, restore by re-applying `infra/github/ruleset-ci-required.tf` via `apply-github-infra.yml`. NEVER restore without the probe. |
| `has no required_status_checks rule` | the required-check rule was removed wholesale | Same as "dropped required check" — restore from Terraform. |
| `Unexpected content encoding` / JSON parse error | a canonical JSON snapshot is malformed | `jq -e . scripts/ci-required-ruleset-canonical-*.json` locally; fix syntax. |

### Token scope (driftguard GitHub App)

The function mints an installation token via `mintInstallationToken`
(driftguard App, `administration:read` on this repo). If the token cannot read
`bypass_actors`/rulesets:

1. **Probe live state first** (read-only `gh api` above) — confirm the ruleset
   is actually healthy before touching App config.
2. Confirm the App installation still has admin scope:
   ```bash
   gh api /orgs/jikig-ai/installations --jq \
     '.installations[] | select(.app_slug=="soleur-ai") | {id, repository_selection, permissions}'
   ```
   The `permissions` map MUST include `administration`. If absent, widen via
   Settings → Developer settings → GitHub Apps → `soleur-ai` → Permissions &
   events → Repository permissions → Administration: Read (the org owner must
   accept the new permission).
3. Re-run the audit (`trigger-cron` above). It should complete green and
   auto-close any stale issue.

## Smoke test (safe, no real drift event)

Because the audit reads the canonical snapshots from `main` via the GitHub API
(not a local checkout), a real drift smoke would require editing the live
ruleset — outward-facing and risky. Prefer the safe path:

1. Probe live vs canonical (read-only `gh api` above) → expect a match.
2. Fire `trigger-cron` (above) → expect HTTP 202, green run, no issue filed.
3. The drift→label logic is unit-covered by
   `apps/web-platform/test/server/inngest/cron-ruleset-bypass-audit.test.ts`
   (`compareBypassActors`, `compareRequiredStatusChecks`, `buildFindings`).

## References

- `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts` —
  the audit (Inngest cron).
- `apps/web-platform/test/server/inngest/cron-ruleset-bypass-audit.test.ts` —
  unit coverage of the three drift classes.
- `infra/github/ruleset-ci-required.tf` — Terraform source of truth for the
  ruleset; applied by `.github/workflows/apply-github-infra.yml`.
- `scripts/ci-required-ruleset-canonical-bypass-actors.json` — bypass_actors
  snapshot (read live by the audit).
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` —
  required_status_checks snapshot.
- `tests/scripts/test-audit-ruleset-bypass.sh` — `T-rsc-9` keeps the snapshots
  in lockstep with the `.tf`.
- `plugins/soleur/skills/trigger-cron/SKILL.md` — fire the audit on demand.
- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`
  — parent R15 runbook.
- `knowledge-base/legal/compliance-posture.md` `#2719` row.
- GitHub Rulesets API: https://docs.github.com/en/rest/repos/rules
