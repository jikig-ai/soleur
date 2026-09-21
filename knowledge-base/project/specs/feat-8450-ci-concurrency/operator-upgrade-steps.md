# Operator upgrade steps — GitHub Team (issue #8450)

Durable operator artifact for the one step in this plan that requires a human:
the GitHub org plan-tier upgrade is a **payment authorization** and is not
reachable by `gh`, REST, or Terraform (the `github` provider has no
billing/plan resource).

**Runnable form:** `bash bootstrap.sh` (same directory) chains Steps 2–5
behind the Step-1 payment gate — one command instead of this checklist. It
verifies each step's precondition against the vendor, so a re-run skips what
is already done. This document remains the reference for what each stage does
and why.

**Automation status: UNVERIFIED-blocked.** Attempted 2026-09-21: Playwright MCP
cannot launch a browser on this host
(`Chromium distribution 'chrome' not found at /opt/google/chrome/chrome`).
`gh api orgs/jikig-ai` exposes `plan.name` read-only; no mutation endpoint
exists. If a runnable browser profile appears, this step is automatable and the
note above is stale — retry Playwright before doing it by hand.

## Step 1 — Upgrade the org plan

GitHub → org **Settings** → **Billing** → **Upgrade to Team** for `jikig-ai`.

- Price: `$4/user/month` (currently 1 seat; annual prepay ≈ `$3.67/seat/mo` —
  pick whichever; the ledger reconciles at first invoice).
- Payment-card entry is the human gate.

## Step 2 — Verify (record the timestamp)

```bash
gh api orgs/jikig-ai --jq .plan.name   # expect: team
date -u +%FT%TZ                         # record this timestamp
```

Write the timestamp into `measurements.md` as `UPGRADE_NOT_BEFORE` — the
follow-through probe rejects samples that predate it (`plan.name` reports the
current tier, not when it changed).

## Step 3 — Flip the ledger

`knowledge-base/operations/expenses.md` row "GitHub Team (org plan, jikig-ai)":
`approved-not-billing` → `active`, same day as the upgrade.

## Step 4 — Post-merge monitor transition

After the PR merges, immediately shorten the Sentry monitor transition gap:

```bash
gh workflow run apply-sentry-infra.yml
```

Until that apply lands, the workflow schedules run at the new hourly cadence
while the `zot_restart_loop_alarm` monitor still expects `*/30`/margin-30 — one
transient missed-check-in issue is EXPECTED. A second, subsequent miss is a real
signal, not the transition (Sentry repeat-issue silence class, #7142).

## Step 5 — Enroll the soak probe

The follow-through probe `scripts/followthroughs/actions-queue-tail-8450.sh`
enrolls via the repo convention — append this directive to the #8450 **issue
body** (unfenced, column 0 — the sweeper parses bodies, not comments, and skips
fenced/indented directives) with the `earliest=` field set to the
`UPGRADE_NOT_BEFORE` timestamp from Step 2, then add the `follow-through`
label to #8450:

```text
<!-- soleur:followthrough script=scripts/followthroughs/actions-queue-tail-8450.sh earliest=<UPGRADE_NOT_BEFORE> secrets=GH_TOKEN -->
```

## What the upgrade does NOT do

Upgrading to Team does **not** re-enable the merge queue — that stays disabled
(CodeQL `merge_group` reporting unresolved, codeql-action#1537; tracked at
#5840). It satisfies only ADR-032 reopener (iii); reopeners (a) and (b) still
stand.
