---
title: "feat: converge the CodeQL tracker filers — sweep mode in codeql-main-alert-gate.sh, fixed-state orphan reaping"
type: feat
date: 2026-11-04
slug: feat-codeql-filer-convergence
branch: feat-one-shot-12065-12066-codeql-filer-converge
issue: 12065
closes: [12065, 12066]
priority: priority/p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# feat: converge the CodeQL tracker filers — sweep mode in codeql-main-alert-gate.sh, fixed-state orphan reaping

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed; no `specs/<branch>/spec.md` exists for this one-shot branch).

Reviewed-Coverage: sequential-fallback — this plan ran on a harness that cannot spawn subagents; every prescribed fan-out role (repo research, learnings research, external research, domain leaders, spec-flow, advisor, plan-review panel) was executed sequentially inline against the same agent definition files.

## Overview

Two GitHub issues land in one PR. #12065 converges the two CodeQL tracker filers — the push-time gate (`scripts/codeql-main-alert-gate.sh`, driven by `.github/workflows/codeql-main-alert-gate.yml`) and the daily cron (`.github/workflows/codeql-to-issues.yml` `check-alerts`, inline bash) — into one implementation per the CTO ruling on #12004 (comment 6625921398, 2026-11-04): the gate script gains a sweep mode that skips the push-specific phases 1–2 and resolves its commit input to main HEAD when unset; the cron's `check-alerts` job becomes checkout + `bash scripts/codeql-main-alert-gate.sh`, deleting its inline filing logic; `close-orphans` stays a separate job. #12066 fixes the `close-orphans` reaper predicate so trackers whose referenced alerts are `fixed` (not only `dismissed`) are reaped, keeping the `keep-open` escape hatch.

## Problem Statement / Motivation

The cron filer's dedupe already rotted once in production (a `gh search` query the CLI rejected, masked by `|| true`, produced ~185 duplicate `sec:` trackers — the incident #12000 fixed). The CTO ruled the duplication itself is the defect class: two implementations can diverge, and two of the three #12004 items existed only because they had. The gate script is the strictly better implementation — input-validated, deadline-bounded, fail-closed with a tested `codeql-gate-degraded` durable page, and covered by a 361-assertion suite plus a 50-mutant battery and a parsed-YAML wiring suite — while the workflow's inline block has zero coverage. Under the ruling, items 12004.2 (durable degraded signal; removal of `2>&1 || true` on the ALERTS fetch) and 12004.3 (jq match form `startswith($p)` + next-char-not-digit) land for free because the gate's implementation becomes the only one.

Independently, #12066: `close-orphans` only reaps trackers whose referenced alerts are all `dismissed`; GitHub marks remediated alerts `fixed` (confirmed: REST `state` enum is `open|dismissed|fixed`), so fixed-alert trackers accumulate as permanently open `type/security` issues and inflate the population toward the 200-row `--limit` bound both filers dedupe on.

## Proposed Solution

1. **Sweep mode in the gate script.** New env input `SWEEP` (`true|false`, default `false`, validated like `DRY_RUN`). In sweep mode: `SHA` is optional — when empty, the script resolves main HEAD via `timeout 60 gh api "repos/${GH_REPO}/commits/main"` through the existing `fetch_page` helper and re-validates the 40-hex shape (resolution failure degrades, `api-error`); phases 1–2 (Analyze check-run wait, analyses-settle wait) are skipped inside one mode branch; phase 3 (ref-scoped open critical/high alert read → bot-authored dedupe → file) is identical in both modes. The degraded upsert becomes mode-aware: title `codeql-sweep-degraded` in sweep mode vs `codeql-gate-degraded` in push mode, same `LABELS_P2` and same upsert machinery, with mode-appropriate body text.
2. **Rewire `check-alerts`.** The job becomes: pinned-SHA `actions/checkout` (identical step shape to the gate workflow — `persist-credentials: false`, sparse-checkout of the one script) followed by a single `run: bash scripts/codeql-main-alert-gate.sh`. Env: `GH_TOKEN`, `GH_REPO`, `SWEEP: 'true'`, `GITHUB_RUN_ID`, `DEADLINE_SECONDS: '240'`, `DRY_RUN` mirroring a new optional `dry_run` dispatch input. All inline filing logic is deleted. Workflow `permissions` gains `contents: read` (required by checkout). `timeout-minutes` becomes `10` so the script's deadline (240 s) plus the bounded degraded upsert finishes inside the job kill — the same `deadline + 300s ≤ job timeout` invariant the gate wiring suite pins.
3. **`close-orphans` fixed-state reaping.** The `ALL_DISMISSED` predicate treats `dismissed` and `fixed` alike via an explicit two-state allowlist (any other or unreadable state still keeps the issue open — bias unchanged); the per-alert reason line records the actual state; the close comment reads "dismissed or fixed". `keep-open` is untouched.
4. **Coverage.** New sweep rows (`sw*`) in `codeql-main-alert-gate.test.sh`, a `commits/main` endpoint in the gh shim + a synthesized fixture, new sweep mutants in `mutants.sh`, and a new parsed-YAML wiring suite `codeql-to-issues-sweep-wiring.test.sh` (+ facts fixture) asserting the caller's shape — the same machinery that caught this defect class in the gate.
5. **ADR-270 addendum** recording one-filer/two-triggers; the ADR currently describes the cron as a separate backstop that "swallows API errors with `|| true`" — stale after this lands.

## Technical Considerations

- **Architecture:** establishes the cross-cutting invariant "one CodeQL tracker filer, two triggers" — the script is the only filing path; the push workflow and the daily workflow are both thin callers. `close-orphans` deliberately remains a separate job inside `codeql-to-issues.yml` (ruled).
- **Security:** the sweep inherits the gate's fail-closed fetch semantics, `--author app/github-actions` dedupe scoping (poison-resistance per the 2026-11-03 auto-labeler learning), no-alert-controlled-text filing, `timeout 60` call bounding, and ref-scoped-to-main reads. The new checkout step mirrors the gate workflow's pinned SHA + `persist-credentials: false`; it carries no `ref:` expression (the `actions/untrusted-checkout` sink class requires a head-SHA expression — absent here by construction, per the 2026-11-03 untrusted-checkout learning). Workflow permissions stay least-privilege; the only addition is `contents: read` for checkout.
- **Kill-before-degrade sizing:** the sweep job's `timeout-minutes: 10` pairs with `DEADLINE_SECONDS: '240'` — the gate's own invariant (`job_timeout*60 ≥ deadline + 300`, wiring assertion A21) applied to the new caller, so a stalled sweep degrades-and-pages instead of dying silently at the job kill.
- **Semantic changes (all ruled or derived):** sweep-filed trackers gain `priority/p1-high` + `action-required` labels (deliberate upgrade per the ruling's dissent); branch-only alerts lose trackers (the read is `ref=refs/heads/main`-scoped — ruled correct); the daily run now exits 1 when it files (gate verdict semantics; the filed `action-required` issue is the durable page); on a filing day `close-orphans` is skipped by `needs: check-alerts` and reaps the next green day; gate-filed trackers (body "CodeQL alert #N … is open on main") now get reaped by `close-orphans` once the alert is `fixed`/`dismissed` — the #12066 fix extends to both filers' output, which is the convergence's intent.
- **Test-machinery coupling (the expensive part of this diff):** `s1` counts non-`--paginate` `timeout 60 gh api` CALL SITES in code — `fetch_page` is the shared helper, so a SHA-resolution read routed through it adds no site and the count stays 1 unmodified; the real tightening is pinning the sanctioned `fetch_page` LABEL set (`analyses` + `main HEAD`) so a third ad-hoc single-page read cannot be added silently. `s2` fails on any executable reference to the script outside the gate workflow — the sanctioned sweep caller must be excluded. Several `mutants.sh` sed expressions anchor on `^`-column-0 lines inside phases 1–2; if the mode branch re-indents those blocks the anchors must be updated (keep the phase bodies at column 0 — flat `if SWEEP==true ... else <phases> ... fi` — so existing mutants keep landing). `FLOOR`/`MUTANT_FLOOR`/`CHECKS_PER_RUN` are exact counts re-derived from green runs.
- **NFR:** reliability (one filer instead of two drifting copies), observability (durable degraded page for a no-actor cron), security (fail-closed, scoped dedupe).

## Research Insights

**Relevant paths.** `scripts/codeql-main-alert-gate.sh` (344 lines; inputs 67–74, validation 90–107, `upsert_degraded` 148–169, `degrade` 172–182, `fetch_page(s)` 185–204, phases 1–2 at 214–265, phase 3 at 267–343, dedupe jq at 316–319); `.github/workflows/codeql-to-issues.yml` (211 lines; `check-alerts` inline filer 20–97 incl. the `2>&1 || true` at 31 and the warn+exit-0 dedupe read at 47–55; `close-orphans` 99–211, `ALL_DISMISSED` predicate at 177–195); `.github/workflows/codeql-main-alert-gate.yml` (78 lines; checkout+run shape at 64–78, env at 72–77); `plugins/soleur/test/codeql-main-alert-gate.test.sh` (897 lines; `run_gate` env seam at 129–139, `s1`/`s2` static rows at 772–812, `FLOOR`/`MUTANT_FLOOR` at 48–50); `plugins/soleur/test/codeql-main-alert-gate-workflow-wiring.test.sh` + `fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py` (parsed-YAML assertion engine, `check_wf`, `CHECKS_PER_RUN=32`); `plugins/soleur/test/fixtures/codeql-main-alert-gate/shim/gh` (refuses unknown shapes; endpoint dispatch needs a `commits/main` key); `plugins/soleur/test/fixtures/codeql-main-alert-gate/mutants.sh` (50 `^`-anchored sed mutants).

**Institutional learnings.** `learnings/security-issues/2026-11-03-label-filter-is-not-authorship-bound-auto-labeler-poisons-dedupe.md` (the #12000 incident: `gh search` + `|| true` rot; author-scoping; fail-closed list read; 200-row saturation warning); `learnings/security-issues/2026-11-03-codeql-untrusted-checkout-medium-has-no-if-or-persist-credentials-sanitizer.md` (checkout `ref:` head-SHA expressions are the sink — ours has none); `learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` (close-orphans design: keep-open hatch, fail-biased-open on lookup failure, process-substitution counter pattern); `learnings/security-issues/2026-09-15-the-anchor-was-read-from-the-object-it-protects-and-my-guards-pinned-content-not-wiring.md` (wiring guards must pin binding, not prose — motivates the parsed-YAML sweep suite).

**External docs.** REST code-scanning alert `state` enum is `open|dismissed|fixed` (list filter also accepts `closed`) — docs.github.com/en/rest/code-scanning/code-scanning; `GET /repos/{o}/{r}/commits/{ref}` accepts a branch name and returns `.sha` — docs.github.com/en/rest/commits/commits.

**Related issues/PRs.** #12004 (parent; CTO ruling comment 6625921398); #12000 (dedupe incident + author-scope fix, shipped); #11248 (live `codeql-gate-degraded` precedent — the `action-required` page works); #9454/#9455 (gate + wiring-suite origins); ADR-270 (`knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`, internally headed "ADR-269"; §Alert-gate semantics describes the cron backstop, and its accepted-residuals line "it swallows API errors with `|| true` today" goes stale); ADR-216 (`meta/machinery` on self-findings); archived plan `knowledge-base/project/plans/archive/20261103-213120-2026-11-03-fix-codeql-to-issues-dedupe-plan.md` (the #12004 sibling that hardened the YAML block this change deletes).

**Conventions.** Shell: `#!/usr/bin/env bash` + `set -euo pipefail`, `local` declarations, stderr for diagnostics but operator-protection signals to stdout, `jq '.[0].field // empty'`, no `|| true` on data fetches (gate rule), every `gh` call `timeout 60`-bounded and asserted so by `s1`.

**Premise Validation (Phase 0.6).** #12065 OPEN (`type/feature`, `priority/p2-medium`); #12066 OPEN (`type/bug`, `priority/p3-low`); CTO ruling comment 6625921398 fetched verbatim — convergence design, degraded-signal and jq-match subsumptions, and rejected alternatives all confirmed. All cited files exist on the branch. ADR corpus checked for the proposed mechanism (env-mode script + workflow caller): ADR-270 is the governing record and anticipates extension via addendum; no ADR rejects the mechanism. Filing-surface population check: `git grep 'sec: CodeQL alert'` over code surfaces — exactly two filers (gate workflow, cron workflow); `codeql-gate-degraded` has no title-matching consumer (digest harvests the `action-required` label, so a `codeql-sweep-degraded` title routes identically). Collision pre-check was run by the dispatcher per the brief (not re-run).

**Property List (Phase 0.6b).** P1 one filer for both triggers, fail-closed, deduped, ref-scoped (ruled); P2 a degraded sweep run produces a durable `action-required` page (ruled, via the gate's degrade path); P3 trackers for `fixed` alerts are reaped like `dismissed` (issue #12066); P4 the convergence cannot silently rot — the caller wiring and the mode contract are pinned by suites; P5 the push-mode contract is unchanged (regression protection for the only other caller).

**Cut List.** Nothing in the ask buys a redundant property — every named mechanism is needed. Plan-added items evaluated: extracting `close-orphans` into a script — CUT (out-of-scope; the issue's prescribed fix is a one-condition change and the job stays inline per the ruling; a string-pin in the new wiring suite covers the `fixed` regression class); resolving SHA in the workflow (`SHA: ${{ github.sha }}`) — CUT in favor of script-side resolution: the ruling's "SHA optional / resolves to main HEAD" is exercised in production only if the script resolves it, and API resolution evaluates `main` even when a dispatch runs off another ref.

**Value-Proposition Measurement (Phase 0.6c).** Not a cost/performance-saving plan — the justification is correctness and drift elimination; nothing to quantify.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Codebase reality | Plan response |
|---|---|---|
| "skips the push-specific phases 1–2" | Phases are sequential top-level blocks (lines 214–265), phase 3 at 267+ | Mode branch wraps phases 1–2; phase 3 shared |
| "SHA optional / resolves to main HEAD" | `SHA` validated `^[0-9a-f]{40}$` at line 91, unconditional | Validation becomes mode-aware; empty-in-sweep resolves via `commits/main` + re-validate |
| "the gate's `degrade` path" | `upsert_degraded` hard-codes title `codeql-gate-degraded` and a "for a push to main" body | Parameterize title + body by mode |
| "close-orphans stays a separate job" | Present, `needs: check-alerts`, inline bash | Kept; predicate change only |
| "jq match form lands for free" | Gate matcher at 316–319 is already the `startswith` + next-char-not-digit form | The YAML copy is deleted, so the gate's becomes the only matcher |
| "removes `2>&1 || true` on the ALERTS fetch" | Present at `codeql-to-issues.yml:31` | Deleted with the inline block |
| 200-row dedupe bound | Both filers `--limit 200` + saturation warning | Unchanged; #12066 reduces pressure toward the bound |

## Implementation Phases

1. **Gate script sweep mode** — `scripts/codeql-main-alert-gate.sh`: `SWEEP` env input + validation; mode-aware `SHA` validation (`SWEEP=true` + empty → resolve via `fetch_page "main HEAD" ... "repos/${GH_REPO}/commits/main"` → `.sha` → re-validate; `SWEEP=true` + provided → validate; `SWEEP=false` → unchanged requirement); one flat mode branch skipping phases 1–2 (phase bodies keep column-0 indentation so existing mutant sed anchors keep landing); mode-aware `upsert_degraded` (title + body line per mode; `codeql-sweep-degraded` in sweep); header INPUTS/VERDICT docs updated.
2. **Workflow rewiring** — `.github/workflows/codeql-to-issues.yml`: `check-alerts` becomes checkout + `bash scripts/codeql-main-alert-gate.sh` (delete lines 24–97's run block); env `GH_TOKEN`/`GH_REPO`/`SWEEP: 'true'`/`GITHUB_RUN_ID`/`DEADLINE_SECONDS: '240'`/`DRY_RUN` from a new `dry_run` dispatch input; `timeout-minutes: 10`; add `contents: read` to `permissions`; update the header comment (the job delegates; it no longer "polls and creates" inline). `close-orphans`: two-state `dismissed|fixed` allowlist in the `ALL_DISMISSED` predicate, per-alert `${STATE}` in `REASONS`, "dismissed or fixed" close comment.
3. **Gate suite updates** — `plugins/soleur/test/codeql-main-alert-gate.test.sh`: new `sw*` rows (sweep files trackers with zero check-runs/analyses calls; SHA-unset resolves main-head; resolve failure degrades; `codeql-sweep-degraded` title; dedupe GREEN; invalid `SWEEP` → exit 2; `SWEEP=true` + invalid `SHA` → exit 2; `DRY_RUN` in sweep; phase-3 API failure in sweep is non-green; a second sweep degraded run comments rather than creates); `s1` gains a pin on the sanctioned `fetch_page` label set (`analyses` + `main HEAD` — the non-paginate call-site count stays 1 because the resolution reuses the helper); `s2` sanctioned-caller exclusion for `codeql-to-issues.yml`; `FLOOR`/`MUTANT_FLOOR` re-derived from green runs. Shim: `*/commits/main` endpoint key `main-head` (+`.rc` failure support free via `fail_if_injected`). Fixtures: synthesized `base/main-head.json` commit object, a `scenarios/issue-sweep-degraded.json`. `mutants.sh`: re-anchor any broken patterns + new sweep mutants (phase-guard dropped; resolved SHA unvalidated; degraded title not mode-aware; sweep still requires SHA).
4. **New sweep wiring suite** — `plugins/soleur/test/codeql-to-issues-sweep-wiring.test.sh` + `plugins/soleur/test/fixtures/codeql-to-issues-sweep-wiring/sweep_facts.py`: parsed-YAML assertions (triggers exactly schedule+workflow_dispatch; `check-alerts` = pinned-SHA checkout with `persist-credentials: false` + sparse script + exactly one run step `bash scripts/codeql-main-alert-gate.sh`; env key set and `SWEEP='true'`/`DRY_RUN`/`DEADLINE_SECONDS` evaluation per event; `job_timeout*60 ≥ DEADLINE_SECONDS + 300`; permissions include `contents: read`; no `gh issue create` text in `check-alerts` run blocks; `close-orphans` run text carries the `dismissed|fixed` allowlist + `keep-open`) and mutation rows (`|| true` on the call, `continue-on-error`, missing `SWEEP`, reintroduced inline `gh issue create`, `fixed` dropped from the allowlist, unpinned action, timeout below the invariant).
5. **Registration + records** — `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` rows for the new suite (the shard-totality guard fails otherwise); `.github/CODEOWNERS` rows for the new test + fixture dir mirroring the gate's rows; ADR-270 addendum; verify `components.test.ts`'s `findUnboundedEnumerations` does not flag `gh api repos/.../commits/main` (single-object endpoint — expected clean; if flagged, apply the coded exemption with justification).
6. **Verify** — run the two codeql suites + the new suite + `GATE_MUTANTS=1` battery + affected-surface check (`bash scripts/test-all.sh --affected` or the shard leg for these suites).

## Files to Edit

- `scripts/codeql-main-alert-gate.sh` — FR-1…FR-4 (sweep mode, SHA resolution, mode-aware degrade)
- `.github/workflows/codeql-to-issues.yml` — FR-5/FR-6 (check-alerts rewire, permissions, close-orphans predicate)
- `plugins/soleur/test/codeql-main-alert-gate.test.sh` — `sw*` rows, `s1`/`s2` updates, FLOORs
- `plugins/soleur/test/fixtures/codeql-main-alert-gate/shim/gh` — `commits/main` endpoint
- `plugins/soleur/test/fixtures/codeql-main-alert-gate/mutants.sh` — re-anchored + new sweep mutants
- `scripts/suite-shard-legs.tsv` — register the new suite
- `scripts/suite-durations.tsv` — register the new suite (initial `floor` entry until measured)
- `.github/CODEOWNERS` — rows for the new suite + fixture dir
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — addendum
- `knowledge-base/engineering/operations/runbooks/codeql-bot-coverage.md` — accuracy check only; edit if its description of the cron's machinery is stale

## Files to Create

- `plugins/soleur/test/codeql-to-issues-sweep-wiring.test.sh`
- `plugins/soleur/test/fixtures/codeql-to-issues-sweep-wiring/sweep_facts.py`
- `plugins/soleur/test/fixtures/codeql-main-alert-gate/base/main-head.json`
- `plugins/soleur/test/fixtures/codeql-main-alert-gate/scenarios/issue-sweep-degraded.json`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Extend `scripts/codeql-main-alert-gate.sh` with a sweep mode (skips the push-specific phases 1–2; SHA optional/resolved to main HEAD)" [#12065 / ruling] | FR-1/FR-2/FR-3, Phase 1 | mapped |
| 2 | "have `codeql-to-issues.yml`'s `check-alerts` job checkout + `bash scripts/codeql-main-alert-gate.sh`, deleting the inline filing logic" [#12065 / ruling] | FR-5, Phase 2 | mapped |
| 3 | "`close-orphans` stays a separate job" [#12065 / ruling] | Phase 2 (job retained; `needs:` edge unchanged) | mapped |
| 4 | "treat `dismissed` and `fixed` alike in the ALL_DISMISSED predicate (one condition change + tally-reason string update), keeping the existing `keep-open` label escape hatch" [#12066] | FR-6, Phase 2 | mapped |
| 5 | "items 12004.2 … and 12004.3 … land for free because the gate's implementation becomes the only one" [#12065 context] | FR-4 (durable degraded signal inherited); phase-3 read + matcher become sole implementation | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Gate-script sweep mode (`SWEEP` input, phases 1–2 skip) | "a sweep mode that skips the push-specific phases 1-2 (SHA optional / resolves to main HEAD)" | asked |
| SHA resolution via `commits/main` in the script | "SHA optional / resolves to main HEAD" | asked (locus inferred — see decision-challenges row 2) |
| `check-alerts` = checkout + `bash scripts/codeql-main-alert-gate.sh` | "checkout + `bash scripts/codeql-main-alert-gate.sh`, DELETING its inline filing logic" | asked |
| `close-orphans` `dismissed\|fixed` allowlist | "treat `dismissed` and `fixed` alike in the ALL_DISMISSED predicate (one condition change + tally-reason string update)" | asked |
| Mode-aware degraded title `codeql-sweep-degraded` | "a separate title keeps attribution clean while the shared `action-required` label still routes both to the digest" (ruling 12004.2 rationale) | inferred — justification: ruling prefers attribution across the two trigger signals |
| `contents: read` permission + checkout step shape | "have `codeql-to-issues.yml`'s `check-alerts` job checkout" | asked (shape inferred — justification: checkout requires `contents: read`; the pinned/persist-credentials-false shape is the repo's only sanctioned checkout pattern) |
| `DEADLINE_SECONDS: '240'` + `timeout-minutes: 10` | — | inferred — justification: a `timeout-minutes: 5` job kill precedes the default 1800 s script deadline, so a stalled sweep would die silently — the exact no-durable-signal failure the ruling exists to kill; the pair preserves the gate's own A21 invariant |
| `dry_run` dispatch input | — | inferred — justification: the only zero-write way to verify the rewired caller post-merge; mirrors the gate workflow's existing input contract |
| Sweep wiring suite + `sw*` rows + shim/mutant updates | — | inferred — justification: the gate suite's `s2`/`s1` assertions and the shard-totality guard fail mechanically without them; the ruling's dissent names "the existing suite" as the mitigation for coupled failure |
| `suite-shard-legs.tsv`/`suite-durations.tsv`/CODEOWNERS rows | — | inferred — justification: totality guard and repo convention fail/rot without registration |
| ADR-270 addendum | — | inferred — justification: plan Phase 2.10 — the recorded architecture ("daily cron … swallows API errors" as a separate backstop) goes stale |

### Split Assessment

- Subsystems touched: 4 — `scripts/`, `.github/`, `plugins/soleur/test/` (+fixtures), `knowledge-base/`
- Planned files: ~12 | Estimated changed lines: ~700 (most in new test/fixture code)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the two issues share the same workflow file and test machinery; splitting the #12066 predicate fix out adds a second PR over the same file for one line of logic, and the dispatch explicitly asks for one PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing in the product — the blast radius is the repo's own security-signal channel: either a silently dark CodeQL tracker path (missed `sec:` issues the operator believes are filed) or public noise (duplicate/mislabelled `sec:`/`codeql-sweep-degraded` issues on the public jikig-ai/soleur tracker).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data — the filed issues carry only a validated alert number, a validated rule id, a severity and a synthetic URL (the data-minimized body is pinned by suite rows r1); the exposure is repo-ops noise, not data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-internal machinery whose public artifact is a bounded, deduped, data-minimized issue; a malfunction degrades an internal security signal rather than exposing user data or a product surface — `single-user incident` would require a user-facing artifact, which this change does not produce.
- *Scope-out override:* `threshold: none, reason: the diff touches `.github/workflows/` and a security gate script — sensitive paths by preflight convention — but changes no user-facing surface, credential, or data flow; the public artifacts are deduped bot issues carrying no user data.`

## Observability

```yaml
liveness_signal:
  what: "daily `CodeQL Alert to Issue` run GREEN plus no open `codeql-sweep-degraded` issue; the sweep is the backstop for the push gate"
  cadence: "daily 06:00 UTC + every workflow_dispatch"
  alert_target: "operator digest via the `action-required` label on the degraded issue; GitHub Actions run state"
  configured_in: ".github/workflows/codeql-to-issues.yml (schedule) + scripts/codeql-main-alert-gate.sh (degraded upsert)"
error_reporting:
  destination: "`codeql-sweep-degraded` (sweep) / `codeql-gate-degraded` (push) GitHub issues labelled action-required — precedent #11248 shows the page reaching the digest"
  fail_loud: "script exit 1 + ::error annotation + degraded-issue upsert; a red check-alerts run"
failure_modes:
  - mode: "GitHub API outage or token-permission drift during the sweep"
    detection: "degraded upsert files `codeql-sweep-degraded` with reason api-error"
    alert_route: "operator digest (action-required)"
  - mode: "dedupe issue-list read fails mid-sweep"
    detection: "phase-3 api-error degrade -> same upsert"
    alert_route: "operator digest (action-required)"
  - mode: "runner/job kill before the script's own deadline"
    detection: "sweep wiring suite pins job_timeout*60 >= DEADLINE_SECONDS + 300 so the script deadline always fires first"
    alert_route: "CI red on codeql-to-issues-sweep-wiring.test.sh at PR time"
  - mode: "a bad gate-script edit breaks BOTH signals (the coupling the ruling's dissent names)"
    detection: "361-assertion gate suite + 50-mutant battery + two wiring suites run in CI on every change to the script"
    alert_route: "CI red before merge"
logs:
  where: "GitHub Actions run logs, workflow `CodeQL Alert to Issue`"
  retention: "GitHub-hosted default (~90 days)"
discoverability_test:
  command: bash -c 'grep -q "^SWEEP=" scripts/codeql-main-alert-gate.sh && grep -qF "bash scripts/codeql-main-alert-gate.sh" .github/workflows/codeql-to-issues.yml && printf "converged\n"'
  expected_output: converged
```

## Guard Contract

### Guard 1 — sweep-mode dispatch and SHA contract (gate script + its suite)

**Property.** With `SWEEP=true` the script never touches the `check-runs` or `analyses` endpoints and always holds a 40-hex `SHA` — provided and validated, or resolved from `commits/main` — before the shared phase 3 runs; with `SWEEP=false` the push contract is byte-for-byte unchanged.

**Assembly.** The chokepoint is the input-validation block plus the single mode branch in `scripts/codeql-main-alert-gate.sh` that either resolves `SHA` and jumps to phase 3 or runs phases 1–2; every run of the script in either mode flows through it. Pinned by the `sw*` rows, the `z1d`/`x1` exit-2 family, `s1`'s named non-paginated-call list, and the mutant battery.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the mode guard so sweep still waits on `check-runs` | RED (sw row counting zero `check-runs` calls) |
| 2 | Skip `.sha` re-validation after resolution | RED (sw row feeding a non-hex `main-head.json`) |
| 3 | Resolve `SHA` but keep `SWEEP=true` + provided-invalid `SHA` accepted | RED (sw exit-2 row) |
| 4 | Sweep mode exits 2 when `SHA` is merely unset | RED (sw row requiring resolution, not rejection) |
| 5 | `upsert_degraded` files `codeql-gate-degraded` in sweep mode | RED (sw title row) |
| 6 | Suite mutated to pass `SWEEP=garbage` expecting success | RED (harness row — exit-2 expectation) |
| 7 | A second untracked alert is added to a sweep fixture after a compliant first | RED if the filing loop stopped at the first candidate (must-PASS/second-member row) |

### Guard 2 — sweep caller wiring (`codeql-to-issues-sweep-wiring.test.sh`)

**Property.** The daily workflow's `check-alerts` job runs the gate script — nothing between the trigger and the script can skip it, soften its exit status, dry-run it unexpectedly, or reintroduce inline filing; and the job's kill timeout can never precede the script's own deadline.

**Assembly.** The parsed `.github/workflows/codeql-to-issues.yml`: `on:` triggers, `permissions`, and the `check-alerts` job's steps/env/`timeout-minutes` — the single chokepoint every scheduled filing flows through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `|| true` to the script call | RED |
| 2 | Add `continue-on-error` to the job | RED |
| 3 | Delete the `SWEEP` env (the caller silently becomes a second push-gate invocation shape / loses mode) | RED |
| 4 | Reintroduce an inline `gh issue create` in `check-alerts` | RED |
| 5 | Unpin `actions/checkout` to a tag / set `persist-credentials: true` | RED |
| 6 | `timeout-minutes` below `DEADLINE_SECONDS + 300` | RED (the kill-before-degrade invariant) |
| 7 | Facts helper neutered to report `parse_ok` on an unreadable file | RED (harness row — a green with no parse is vacuous) |
| 8 | Second env key added beyond the pinned set | RED (absence-style exact-set assertion, must-PASS row: a compliant `dry_run` dispatch evaluates `DRY_RUN=true`) |

### Guard 3 — orphan-reaper terminal-state predicate

**Property.** A `sec:` tracker is closed iff every referenced alert is `dismissed` or `fixed` (lookup failure or any other state keeps it open) and it lacks `keep-open`.

**Assembly.** The `ALL_DISMISSED` predicate + `keep-open` check inside the `close-orphans` run block of `.github/workflows/codeql-to-issues.yml` — the only reaper path; the parsed-YAML string assertions in Guard 2's suite are the chokepoint pin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `fixed` from the state allowlist | RED |
| 2 | Allowlist widened to include `open` | RED (assertion pins the exact two-state set, not superset) |
| 3 | Remove the `keep-open` escape hatch | RED |
| 4 | Lookup-failure branch flipped to close | RED (the empty-`STATE` keep-open branch is pinned) |

## Domain Review

**Domains relevant:** Engineering, Support

### Engineering

**Status:** reviewed (via existing ruling — sequential-fallback)
**Assessment:** The architectural decision for this change is the CTO's own 2026-11-04 ruling on #12004 (converge to one implementation, keep two triggers; rejected: convention-parity, shared lib, one trigger). Re-litigating was declined per the ruling record. Residual technical risk: the coupling the dissent names — a bad gate-script edit now breaks both signals — is carried into the plan's coverage phases (FR-7/FR-8) and Guard Contract 1–2.

### Support

**Status:** reviewed (sequential-fallback)
**Assessment:** The tracker/reaper machinery is issue-triage automation on the repo's own security backlog — an internal ops surface, not customer support. Consequence of the change for that surface: fixed-alert orphans stop accumulating (the stated backlog-inflation pressure toward the 200-row dedupe bound is relieved), and sweep-filed trackers now carry `action-required` + `priority/p1-high`, so the digest treats a cron-filed tracker identically to a push-filed one — a deliberate, ruled upgrade. No customer-facing workflow changes; no docs for end users.

### Product/UX Gate

Product domain not relevant — no UI-surface file in Files to Create/Edit (scripts, workflows, tests, docs only); mechanical override did not fire.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` with a dated addendum (its established append-pattern): the daily sweep is no longer a second filer but a second trigger of `scripts/codeql-main-alert-gate.sh` in sweep mode; the accepted-residual "it swallows API errors with `|| true` today" is resolved; sweep-filed trackers carry the P1/action-required label set; a `codeql-sweep-degraded` issue joins `codeql-gate-degraded` as the second durable degraded page; `close-orphans` reaps `dismissed`-or-`fixed`. Cite the CTO ruling (issue #12004 comment 6625921398, 2026-11-04) and #12065/#12066.

### C4 views

**No C4 impact.** Enumerated against `model.c4`/`views.c4`/`spec.c4` (precedent: the 2026-10-24 ADR-270 addendum reached the same conclusion for a same-shaped CI script): (a) external human actors — the only one is the anonymous public-issue reader, already modeled (`model.c4` `public_github_reader`, "the one egress … cannot be retracted once written"); (b) external systems — GitHub (Actions, Issues, code-scanning API) already modeled as the `github` system; no new vendor; (c) containers/data stores — none touched, no new store; (d) access relationships — the file/reap edges are repo-internal CI behavior with the same `GITHUB_TOKEN` scopes (`issues: write`, `security-events: read`, +`contents: read` for checkout — a workflow-internal permission, not a modeled trust edge). The change moves filing between two triggers of one mechanism; no element, tag, edge or view-include changes.

### Sequencing

The addendum ships in this PR (not deferred) — the decision is true on merge.

## Acceptance Criteria

- [ ] AC1: `SWEEP=true` with `SHA` unset runs `bash scripts/codeql-main-alert-gate.sh` end-to-end: zero `gh api` calls to `check-runs`/`analyses` (call log asserted), `repos/{repo}/commits/main` fetched once, phase-3 dedupe+filing identical to push mode. *(gate suite `sw*` row)*
- [ ] AC2: `SWEEP=true` + `SHA` provided (40-hex) behaves identically except no resolution call; `SWEEP=true` + invalid `SHA` → exit 2 before any `gh` call; `SWEEP=garbage` → exit 2; `SWEEP=false` + empty `SHA` → exit 2 (push contract unchanged).
- [ ] AC3: A degraded sweep run upserts exactly one issue titled `codeql-sweep-degraded` with `LABELS_P2`, a body naming the scheduled sweep (not "a push to main"), and exits 1; a second degraded run comments instead of creating. Push mode still upserts `codeql-gate-degraded`.
- [ ] AC4: `.github/workflows/codeql-to-issues.yml` `check-alerts` contains no `gh api`, `gh issue`, `jq`, `ALERTS=`, or `EXISTING=` tokens in any run block — the job is exactly two steps: a pinned-SHA sparse checkout (`uses: actions/checkout@<40-hex>`) and one `run: bash scripts/codeql-main-alert-gate.sh`; `permissions` includes `contents: read`; `SWEEP: 'true'`, `DEADLINE_SECONDS: '240'`, `timeout-minutes: 10`; `DRY_RUN` mirrors a new `dry_run` dispatch input.
- [ ] AC5: `close-orphans` closes a tracker iff every referenced alert is `dismissed` or `fixed`; `keep-open` and lookup-failure keep it open; the close comment reads "dismissed or fixed" and `REASONS` records each alert's actual state.
- [ ] AC6: `plugins/soleur/test/codeql-to-issues-sweep-wiring.test.sh` exists, is registered in `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv`, and its mutation battery reds on: `|| true`, `continue-on-error`, dropped `SWEEP`, reintroduced inline `gh issue create`, dropped `fixed`, unpinned/persisting checkout, and `timeout-minutes` breaching `deadline + 300`.
- [ ] AC7: `codeql-main-alert-gate.test.sh` is green with updated `FLOOR`/`MUTANT_FLOOR` (re-derived from a green run), `s1` names both non-paginated `fetch_page` sites, `s2` exempts the sanctioned caller; `GATE_MUTANTS=1` green including the new sweep mutants.
- [ ] AC8: `codeql-main-alert-gate-workflow-wiring.test.sh` green and UNMODIFIED for the gate workflow (push wiring contract untouched — the gate workflow file itself is not in this diff).
- [ ] AC9: ADR-270 carries a dated addendum recording one-filer/two-triggers, the retired `|| true` residual, the two degraded titles, and the `fixed`-state reaper; no `Follow-up` defers it.
- [ ] AC10: `bun test plugins/soleur/test/components.test.ts` (enumeration-bounds gate) stays green — `gh api repos/.../commits/main` is either unflagged or carries the coded exemption.
- [ ] AC11: `git grep -n 'gh issue create\|gh api\|gh search' .github/workflows/codeql-to-issues.yml` hits only `close-orphans`' `gh api "/repos/${GH_REPO}/code-scanning/alerts/${AN}"` per-alert state read — zero hits inside `check-alerts`.

## Test Scenarios

- Given `SWEEP=true`, `SHA` unset, clean fixtures, when the script runs, then the shim log shows `commits/main` and zero `check-runs`/`analyses` calls, and verdict GREEN with no filings (`unit`/shim row sw1).
- Given `SWEEP=true`, `SHA` unset, an untracked critical alert, when the script runs, then exactly one `sec: CodeQL alert #N — <rule>` issue is created with `LBL_P1` labels and exit 1 (`unit`/shim row sw2).
- Given `SWEEP=true` and a `main-head.rc` failure injection, when the script runs, then it degrades `api-error`, upserts `codeql-sweep-degraded`, exit 1 (`unit`/shim row sw3).
- Given `SWEEP=true` and an existing `codeql-sweep-degraded` open issue, when a second degraded run occurs, then it comments, not creates (`unit`/shim row sw4).
- Given `SWEEP=` invalid values and `SWEEP=true` + invalid `SHA`, when the script runs, then exit 2 with zero recorded `gh` calls (`unit` rows sw5/sw6).
- Given the workflow file mutated per Guard 2/3 matrix rows, when the sweep wiring suite runs, then the owning assertion fails (`integration` — parsed-YAML).
- Given a tracker whose alerts are all `fixed`, when `close-orphans` is inspected by the wiring suite, then the allowlist assertion holds and the `fixed`-dropped mutant reds (`integration`).
- Given `GATE_MUTANTS=1`, when the full battery runs, then every mutant lands and reds including the new sweep mutants (`integration`, slow).

## Open Code-Review Overlap

- #8881 (`review: #8854 test-scripts K=6→K=7 rebalance`) touches `suite-shard-legs.tsv`: **acknowledge** — it is an evidence-record issue (0 defects, all resolved inline), not a scope-out naming rework; our new suite's leg assignment follows the same manifest convention.
- None for `scripts/codeql-main-alert-gate.sh`, `.github/workflows/codeql-to-issues.yml`, or the test files (checked 2026-11-04, 96 open `code-review` issues, two-stage `--json`+`jq --arg` query).

## Non-Goals

- Extracting `close-orphans` into a script file (stays inline per the ruling; coverage is the wiring-suite string pin).
- Changing the `needs: check-alerts` edge (a red filing day simply defers the reaper to the next green day — bounded, conservative).
- One trigger total / deleting either workflow (explicitly rejected by the ruling).
- Reaping `dismissed`-reason nuance (false_positive vs used_in_tests) or `keep-open` semantics.
- Push-workflow (`.github/workflows/codeql-main-alert-gate.yml`) changes — none; its wiring suite must pass unmodified.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Two implementations aligned by convention/test | CTO ruling (a): "the status quo that already failed once" — a parity guard can pin the match expression, not failure semantics/labels/ref-scope. |
| Shared lib sourced by both | CTO ruling (b): a third artifact; breaks the gate's single-file self-containedness the sparse checkout depends on. |
| One trigger total | CTO ruling (c): deleting the gate loses push-time paging (ADR-270); deleting the sweep loses no-push alerts (#11248's "backstop"). |
| Workflow passes `SHA: ${{ github.sha }}`; no script-side resolution | Cut in 0.6b: script-side resolution is what "SHA optional" means, exercises the path in production, and evaluates `main` even for off-main dispatches. |
| Extract `close-orphans` to a tested script | Deferred as scope — the prescribed fix is one predicate; the string-pin covers the regression class; a hardening extraction can follow separately. |
| Shared `codeql-gate-degraded` title for both modes | Pending-assumed rejected: ruling 12004.2's own rationale (attribution) survives convergence as trigger attribution; label routing is identical either way. |

## Context

- The PR body must use `Closes #12065` and `Closes #12066` (body, not title).
- Live verification post-merge: dispatch `CodeQL Alert to Issue` with `dry_run: true` to observe a zero-write sweep — note the script still exits 1 when it *would* file (the designed verdict, same as the gate), so a dry-run red run is the filing signal, not a failure; the next green scheduled run plus absence of a `codeql-sweep-degraded` issue is the steady-state signal.
- The mode branch sits after `WORK`/`trap` setup and before phase 1 (~line 213): `fetch_page` writes into `$WORK`, and the phase-1/2 bodies keep column-0 indentation so the 50 `^`-anchored mutants keep landing.
- Decision-challenges for this run persist to `knowledge-base/project/specs/feat-one-shot-12065-12066-codeql-filer-converge/decision-challenges.md`.

## References

- Issues: #12065, #12066, #12004 (ruling comment 6625921398), #12000, #11248, #9454/#9455
- ADR-270 (file `ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`), ADR-216, ADR-074
- GitHub REST: code-scanning alert `state` enum `open|dismissed|fixed`; `GET /repos/{o}/{r}/commits/{ref}` branch-name resolution
- Learnings: label-filter auto-labeler dedupe poison (2026-11-03); untrusted-checkout sanitizer (2026-11-03); orphan post-dismissal sweep (2026-04-19); anchor-read-from-object wiring guards (2026-09-15)
