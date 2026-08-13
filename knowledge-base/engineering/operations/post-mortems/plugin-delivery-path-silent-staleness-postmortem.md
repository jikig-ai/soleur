---
title: "Plugin delivery path could not deliver: update no-ops on a frozen sentinel, marketplace refresh exceeds its own timeout"
date: 2026-08-12
incident_pr: 7473
incident_window: "2026-05-10 → 2026-08-12"
recovery_at: "2026-08-12"
suspected_change: "ADR-017 (2026-03-27) froze plugin.json / marketplace.json versions at 0.0.0-dev"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - operator ran `claude plugin update soleur@soleur` and measured exit 0 with no delivery
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The Soleur plugin's delivery path could not deliver. Two independent defects meant that code merged
to `main` did not reach an installed user, and — worse than a visible failure — the documented
upgrade path reported success while delivering nothing.

This is an availability/correctness incident with no personal-data dimension. Art. 33/34 are not
triggered: no personal data was exposed, accessed, altered, or lost. The affected population is
installed plugin users (currently one, the operator).

## Status

`resolved` — both defects fixed and measured end to end on the published article (PR #7473).

## Symptom

`claude plugin update soleur@soleur` printed `✔ soleur is already at the latest version
(0.0.0-dev)` and exited **0**, while the installed cache sat three months stale — 64 skills against
96 at source, and `scripts/lib/session-state.sh` absent entirely.

Separately, `claude plugin marketplace update soleur` failed on this repository's size, and on
failure moved the checkout to `.bak`, started a fresh clone, and on timeout left
`~/.claude/plugins/marketplaces/soleur/` holding a `.git` with one object and no HEAD. A later
invocation removed the directory and the `.bak` with it.

## Incident Timeline

- **Start time (detected):** 2026-08-11 (operator measurement on PR #7426)
- **End time (recovered):** 2026-08-12
- **Duration (MTTR):** ~1 day from detection; **~3 months from onset**, undetected

| When | Actor | Event |
|---|---|---|
| 2026-03-27 | `human` | ADR-017 freezes both manifest versions at `0.0.0-dev` to stop feature branches bumping them. The mechanism that prevents drift is the mechanism that will stop delivery. |
| ~2026-05-10 | — | Last successful delivery to the operator's install. Onset of the silent-staleness window. |
| 2026-08-10 | `agent` | #7409/#7426 ships the lock/lease library inside `plugins/soleur/` so marketplace installs can resolve it. The fix is correct and reaches nobody. |
| 2026-08-11 | `human` | Operator measures the installed cache against the marketplace checkout and files #7471 with both defects, each measured rather than inferred. |
| 2026-08-12 | `agent` | Falsification gate measures the `git-subdir` premise before anything is built on it (`measurements.md` §1.0). |
| 2026-08-12 | `agent-with-ack` | Operator authorises the additive marketplace repo and its name; `jikig-ai/soleur-marketplace` created, public. |
| 2026-08-12 | `agent` | Delivery verified on the published repo: `marketplace add` 13 s, install 33 s, 9.66 MiB (§2B). Migration path verified for existing installs (§1.2/1.3). |

## Root Cause

**Defect 1 — a constant is what makes a comparison always succeed.** `claude plugin update`
compares **version strings**. With no `version` key the CLI records the plugin's commit SHA as its
version, so the string changes with every commit and the comparison detects the update. A constant
`0.0.0-dev` never changes, so the comparison always came back equal and the update short-circuited.

ADR-017 froze those fields deliberately, to stop feature branches bumping versions and to make git
tags the source of truth. That goal was met. The unexamined consequence was that the updater's
equality test then had nothing to distinguish.

**Defect 2 — the repository outgrew the client's timeout.** `marketplace add jikig-ai/soleur`
clones the whole monorepo: measured **329 s** against the CLI's 120 s default, ~2.7× over. The
failure is deterministic, not flaky. Its recovery path is destructive (`.bak` then deletion), so a
failed refresh degrades to an unusable checkout rather than a no-op.

**Why it ran for three months undetected.** Both defects present as success. Defect 1 exits 0 with a
green checkmark; defect 2's cache-miss surfaces only on a later unrelated command. Nothing in this
repo observed the delivery path — a plugin executing on a user's machine is observability layer 7,
and the operator's own report was, and remains, the only detection channel.

## Resolution

1. Removed the `version` key from both in-repo manifests, so the CLI records the commit SHA.
2. Published `jikig-ai/soleur-marketplace`, whose keyless, unpinned `git-subdir` entry serves
   `plugins/soleur` alone — install 33 s / 9.66 MiB against 329 s / 342.7 MiB.
3. Adopted the repo into the existing `infra/github/` Terraform root.
4. Added `scheduled-marketplace-drift.yml` as the sole control on the published manifest, with a
   Sentry heartbeat so a schedule that stops firing is itself detectable. *(Superseded 2026-08-12,
   #7490: it is no longer sole — a second job in the same workflow installs the published plugin and
   asserts delivered content. ADR-182, Decision 6.)*
5. Documented recovery, including a migration sequence that never re-clones the monorepo and so
   works *from* the broken state.

Decision record: ADR-182. Measurements: `measurements.md`. Recovery: `plugin-delivery-recovery.md`.

## What Went Well

- The operator measured rather than reported a symptom — the issue arrived with byte counts, skill
  counts, and a reproduction, which is why the diagnosis was not guesswork.
- The falsification gate ran **first**. The remedy's premise (`git-subdir` avoids the whole-repo
  clone) had never been measured, and the run was structured to halt if it failed.
- The multi-agent review found the guard built for this incident was itself a control-shaped object,
  before it shipped.

## What Went Wrong

- **A mechanism was asserted, not measured, and propagated.** During the fix, "a `version` key
  suppresses `gitCommitSha` tracking" was inferred from a control-group correlation and written into
  six governance files and a public README before a two-arm experiment refuted it. The counterexample
  was already in this session's own measurement record.
- **The first drift guard was inert in the ways that mattered.** Six mutations survived it, including
  the two silent reverts it existed to catch; both were carried only by prose in the issue body.
- **The remediation's own liveness was unmonitored** until review caught it: the heartbeat initially
  posted to a Sentry slug with no monitor, and Sentry silently drops check-ins to unknown slugs.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7489 | Retire or accept the `jikig-ai/soleur` marketplace entry — it still clones 181 MiB and its `autoUpdate` is not remotely revocable | agent |
| #7490 | Post-#7471 delivery follow-ups: install canary (closes the layer-7 detection gap), persistent timeout setting, upstream defect reports | agent |
| #7491 | Operator: switch the live install to the new marketplace (4 commands) | human |
| #7493 | Protect `jikig-ai/soleur-marketplace` — sole distribution channel, unreviewed by construction | agent |
| #7497 | `test-all.sh` counts a declined suite as passed (pre-existing, surfaced by this run) | agent |

## Prevention

The generalisable lesson is not about plugin manifests. **A constant used as an identity token
makes every equality test against it succeed**, and a success-shaped failure has no detector by
construction. Where a system compares identity to decide whether to act, the identity must vary with
the thing it identifies.

Second: the delivery path had no observability at all, and still largely does not — the operator's
report is the detection channel (#7490 tracks the canary). Recorded in the runbook so the next
person reading it mid-incident knows there is no dashboard to check against their account.
