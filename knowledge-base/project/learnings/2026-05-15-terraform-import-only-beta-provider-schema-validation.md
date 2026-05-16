---
date: 2026-05-15
category: integration-issues
module: terraform-iac
tags:
  - terraform
  - sentry
  - jianyuan-sentry-provider
  - beta-provider
  - import-only-resources
  - lifecycle-ignore-changes
  - plan-vs-reality-drift
related_pr: 3811
related_plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
related_learnings:
  - 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md
  - 2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md
---

# Beta Terraform providers validate `actions_v2 ≥ 1` at config-time even when `lifecycle.ignore_changes` would mask drift

## Problem

PR #3811 adopted `jianyuan/sentry` v0.15.0-beta2 to absorb the 4 existing
`auth-*` Sentry issue-alert rules into Terraform state via `terraform import`
(the rules are operator-keyed by name and managed via REST elsewhere). The
plan called for minimal resource bodies plus `lifecycle.ignore_changes = [
conditions_v2, filters_v2, actions_v2, environment, frequency ]` — the post-
import state is authoritative, so the config bodies were left as empty lists:

```hcl
resource "sentry_issue_alert" "auth_exchange_code_burst" {
  organization  = var.sentry_org
  project       = data.sentry_project.web_platform.slug
  name          = "auth-exchange-code-burst"
  action_match  = "all"
  filter_match  = "all"
  frequency     = 60
  conditions_v2 = []
  filters_v2    = []
  actions_v2    = []  # ← rejected at config-time

  lifecycle { ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency] }
}
```

`terraform fmt -check` passed clean. `terraform init -backend=false -input=false`
fetched the provider. `terraform validate` then failed 4×:

```
Error: Missing attribute configuration
  with sentry_issue_alert.auth_exchange_code_burst,
  on issue-alerts.tf line 30, in resource "sentry_issue_alert" "auth_exchange_code_burst":
  30:   actions_v2 = []
Attribute actions_v2 list must contain at least 1 elements, got: 0
You must add an action for this alert to fire
```

The trap: `lifecycle.ignore_changes` runs at **plan-time** (compares config to
state and silences drift). The provider's per-attribute validation runs at
**config-time** (parses the HCL before any plan). `ignore_changes` cannot
mask a config-shape requirement.

## Solution

Provide a minimal non-empty placeholder action per resource. After import the
state holds the real `actions_v2` (notify-team or notify-email-with-id);
`ignore_changes` then prevents the config-placeholder from re-writing it:

```hcl
actions_v2 = [
  {
    notify_email = {
      target_type      = "IssueOwners"
      fallthrough_type = "ActiveMembers"
    }
  },
]

lifecycle { ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency] }
```

The placeholder semantics are load-bearing: if the operator runs `terraform
apply` BEFORE `terraform import`, Terraform will **create** 4 brand-new rules
with email-only routing — duplicating existing rules under the same name
(Sentry's API allows duplicate names per
`2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`) and silently
halving the paging fanout. The `apply-sentry-infra.yml` workflow is therefore
scoped to `-target=sentry_cron_monitor.*` only — issue-alerts stay
import-only, never auto-applied.

## Key Insight

**`lifecycle.ignore_changes` does NOT mask config-time validation.** It is a
plan-phase compare-and-suppress, not a parse-phase override. Any beta
provider that ships `validate` rules on required-min-length, required-key, or
type-shape will fail before `terraform plan` runs — regardless of how
permissive your `ignore_changes` block is.

For **import-only resource bodies** in beta providers, the rule is:

1. Write the **minimum config that passes `validate`** — exactly one element
   in every "min-length=1" list, exactly the required keys, no more.
2. Choose placeholders whose semantics are **safe under accidental apply**.
   `IssueOwners + ActiveMembers` falls back to all project members, which
   pages SOMEONE; a synthetic email like `placeholder@example.com` would
   silently drop pages. Pick fail-loud over fail-silent.
3. Gate any auto-apply workflow to `-target=` ONLY the resources that are
   create-not-import. Never run unguarded `terraform apply` on an IaC root
   that mixes import-only and apply-friendly resources.
4. Document the placeholder in a header comment — future PRs will reach for
   it and need to know the placeholder is not the actual paging route.

## Prevention

- When proposing `lifecycle.ignore_changes` for a beta provider's import-only
  resource, **run `terraform validate` against the proposed body BEFORE
  finalizing the plan**. The plan author cannot infer from doc strings alone
  whether `actions_v2 = []` will parse.
- For any new IaC root that mixes `terraform import` and `terraform apply`,
  the auto-apply workflow MUST be `-target=`-scoped to the create-not-import
  resources only.
- Add a placeholder semantics comment in any import-only resource that
  defaults its `actions` to `IssueOwners` (or equivalent fail-loud route).

## Session Errors

This learning enumerates errors caught during PR #3811's /work + /review
loop. Each lists the recovery and the proposed prevention.

- **Bare-repo CWD pitfall.** Initial `pwd`+`git status` ran in the bare repo
  root, not the worktree. **Recovery:** explicit `cd
  .worktrees/feat-sentry-monitors-alerts-adapt`. **Prevention:** the `pwd`
  output already shows `/soleur` (no `.worktrees/...`); add this to the
  pre-flight banner. **Already mostly covered** by Phase 0.5's "Not in a
  worktree" WARN; the WARN fired in this session — operator-error to skip
  it.

- **`set -u` × shell-snapshot collision.** `set -uo pipefail` in a
  classification-gate bash block tripped `ZSH_VERSION: unbound variable`
  from the shell snapshot wrapper. **Recovery:** drop `-u`. **Prevention:**
  classification-gate bash in review.SKILL.md uses `set -uo pipefail` —
  drop the `-u` (the existing comment already says "drop the e", we
  should also drop the u for the same shell-snapshot reason).

- **Bash CWD non-persistence across tool calls.** `cd apps/.../sentry &&
  terraform init` succeeded; the next Bash call's `cd apps/...` failed
  because the prior `cd` did NOT persist. **Recovery:** use absolute paths
  or chain operations in a single Bash call. **Prevention:** add a Sharp
  Edge to the work.SKILL.md mentioning that Bash CWD does not persist
  across tool calls (already covered by an existing best-practice line —
  but I forgot it twice in this session).

- **Read-before-Edit on AGENTS.md sidecar pattern.** Three Edit calls
  (gdpr-policy mirror, article-30-register YAML, PP mirror) failed with
  "File has not been read yet" because I read source-form files and
  Edit'd mirror-form files. **Recovery:** explicit Read first.
  **Prevention:** already hook-enforced. The lesson is operational
  (read the mirror before editing it, not just the source).

- **Multi-block Edit insertion artifact.** A complex multi-block Edit on
  `/tmp/inject-sentry-checkin.py` left a stray `EOSPLIT` literal in the
  output. **Recovery:** Read + delete the stray line. **Prevention:**
  prefer multiple smaller Edits over one ambiguous multi-block Edit when
  the surrounding context is shared between blocks.

- **`terraform validate` rejected `actions_v2 = []` despite
  `lifecycle.ignore_changes = [actions_v2]`** — see the main learning body.
  **Prevention:** plan.SKILL.md or its references should add a Sharp Edge:
  "for beta Terraform providers with import-only resources, run
  `terraform validate` against the proposed minimal body BEFORE finalizing
  the plan; `lifecycle.ignore_changes` does NOT mask config-time
  per-attribute validation." This is the **highest-value prevention** from
  this session.

- **Plan-vs-reality drift in AC4 verification commands.** The plan's AC4
  prescribed `diff <(awk '/^---$/{c++;next} c>=2' source.md) <(awk ...
  mirror.md)` and asserted "zero output expected". Mirrors carry an
  Eleventy `<section class="page-hero">` block the source lacks — the diff
  CANNOT be zero. **Recovery:** verified what actually mattered (carve-out
  parity via `grep -c 'Sentry log ingestion (Logs product) is NOT enabled'`
  per file). **Prevention:** plan AC verification commands must be
  exercised against the actual files at plan time, not synthesized from
  the file structure assumption. This is the same class as
  `hr-plan-quoted-numbers-are-preconditions-to-verify` but applied to
  shell-pipeline ACs not just numbers — extend the rule to "plan-prescribed
  verification commands are preconditions to dry-run against the actual
  files at plan time."

- **Plan referenced two `Last Updated` body-form lines that didn't exist.**
  Plan said "lines 11 + 51 — TWO occurrences, both must update" in PP, but
  only line 11 existed. **Recovery:** bumped one line, matching AC4's
  actual "expect 1" grep count. **Prevention:** same class as above —
  plan-prescribed line numbers and occurrence counts are preconditions
  to verify against the live file.

- **PreToolUse `security_reminder_hook` false-positive on workflow edits.**
  Fired 3× on edits whose untrusted inputs were already env-routed. The
  hook is informational (exits 0); the same Edit succeeded on retry.
  **Recovery:** retry the Edit. **Prevention:** the hook's scan logic could
  detect whether the edit's run-block already routes through `env:` before
  emitting the reminder, reducing reviewer noise. Low-priority follow-up.

- **`git diff main..HEAD` (two-dot) vs `main...HEAD` (three-dot).** Initial
  diff showed 66 files including unrelated main-side advances; switched to
  three-dot for branch-only scope. **Recovery:** use three-dot.
  **Prevention:** already a Sharp Edge in `review/SKILL.md` —
  `2026-04-22-markdown-table-parser-papercuts-and-review-diff-direction.md`.
  Operator-error to forget.

## Tags
category: integration-issues
module: terraform-iac
