---
title: "feat: client-pii-grep CI + lefthook gate (#3703)"
type: feat
issue: 3703
milestone: "Phase 4: Validate + Scale"
brand_survival_threshold: none
lane: cross-domain
date: 2026-06-05
---

# feat: client-pii-grep CI + lefthook gate (#3703) ✨

> **Frame:** This is a **signal-quality CI gate, NOT a security control.** Production posture is already guaranteed by the L3 `beforeSend` backstop (`apps/web-platform/sentry.client.config.ts:108` → `stripUserContextFromEvent`), which strips user context from every event regardless of which call site emitted it. This gate exists so a PR author who bypasses the `client-observability.ts` helper and passes `userId`/`user_id`/`email` in `extra` to a **direct** `Sentry.captureException`/`captureMessage` call sees the problem **in the PR diff** — instead of the L3 strip firing silently in a Sentry dashboard nobody reads at review time. No production data has ever been at risk from this gap. `Closes #3703`.

## Overview

Add a `client-pii-grep` gate, wired as **3 consumers sharing ONE implementation (with tests)**:

1. **(c) Shared standalone script** — `.github/scripts/check-client-pii-sentry.sh` (the single implementation both consumers call) + its fixture test `.github/scripts/test/test-check-client-pii-sentry.sh` (auto-discovered by the existing `run-all.sh` harness → already wired into the `guard-script-fixture-tests` CI job).
2. **(a) lefthook command** — a new entry in `lefthook.yml` under **both** `pre-commit` and a **new `pre-push:` top-level section** (lefthook.yml currently has no `pre-push:` block — it must be added).
3. **(b) CI mirror step** — a new `client-pii-grep` job in `.github/workflows/pr-quality-guards.yml`, modeled on the existing `pii-grep` / `userid-bypass-lint` job shape.

The gate **FAILS (exit 1)** when any client-importable file under `apps/web-platform/{lib,components,app}` (excluding `/api/` server routes and the sanctioned helper `client-observability.ts`) passes `userId`/`user_id`/`email` in an `extra` object to a **direct** `Sentry.captureException`/`captureMessage` call.

This is **blocking**, unlike the `gdpr-gate-advisory` precedent (which always exits 0). We model the *shared-script + lefthook + CI-mirror shape* on `gdpr-gate-advisory`, but the exit contract is blocking like `pii-grep` / `userid-bypass-lint`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified 2026-06-05) | Plan response |
|---|---|---|
| Script lives "probably under `plugins/soleur/skills/` or `apps/web-platform/scripts/`" | The canonical shared-guard-script + offline-test precedent is `.github/scripts/<name>.sh` + `.github/scripts/test/test-<name>.sh`, auto-discovered by `.github/scripts/test/run-all.sh`, already run by the `guard-script-fixture-tests` CI job in `pr-quality-guards.yml`. | Place script at `.github/scripts/check-client-pii-sentry.sh`; test at `.github/scripts/test/test-check-client-pii-sentry.sh`. Zero new CI job needed for the *test* — `run-all.sh` picks it up automatically. |
| Model lefthook on `gdpr-gate-advisory` | `gdpr-gate-advisory` **always exits 0** (advisory). This gate must **fail** on violation. | Model the *invocation shape* (lefthook → `bash <script> {staged_files}`) on `gdpr-gate-advisory`, but keep the blocking exit contract of `pii-grep`. Document the divergence inline. |
| Wire to lefthook "pre-commit + pre-push" | `lefthook.yml` has **only** a `pre-commit:` section — **no `pre-push:` block exists.** | Add the command under `pre-commit:` AND add a new top-level `pre-push:` section. |
| Candidate single-line grep is sufficient | The grep is **false-positive-free** (exit 1 on current tree ✅) and catches **same-line** violations, **but MISSES multi-line violations** — and the 4 known existing sites are all written multi-line (`Sentry.captureException(` on line N, `extra: {` on line N+1). The dominant real regression shape would slip the single-line grep. | **The shared script MUST be multi-line-aware** (window/balance the call's argument object), not a literal copy of the single-line pipeline. See Sharp Edges + Design Decision below. This is the load-bearing correctness finding. |
| "4 known direct-Sentry client sites must stay green" | Verified all 4 exist and **none** match the detection (they pass `filename`/`tags`/no-`extra`, never `userId`/`email` in `extra`). A 5th non-`/api/` site `lib/observability-edge.ts` uses `extra: transformedExtra` (a variable, not inline `userId`) — also green. | Calibration fixtures lock all 5 green-sites + ≥2 synthetic red-sites (same-line AND multi-line). |
| New gate duplicates `userid-bypass-lint` (#3698) | `userid-bypass-lint` scopes to **`logger.*` calls in `apps/web-platform/(server|app)/`** — a *different* emit surface (pino logger, server+app) than this gate's surface (**`Sentry.*` in `{lib,components,app}` client-importable**). | Distinct gate; document the boundary in the job comment so a future maintainer does not collapse them. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. A broken gate (false-positive) blocks a contributor's PR/commit; a vacuous gate (false-negative) silently lets a helper-bypass land — but the L3 `beforeSend` backstop still strips the PII at runtime, so no user data leaks regardless.

**If this leaks, the user's data is exposed via:** N/A for this change. The gate is a *static signal* over source text; it processes no user data. The thing it guards (raw `userId`/`email` reaching Sentry) is already structurally prevented at runtime by L3 — this gate only improves PR-author *visibility*, not the production exposure surface.

**Brand-survival threshold:** `none`.

> **Sensitive-path scope-out:** `threshold: none, reason: this PR touches only CI/lefthook gate infrastructure (.github/scripts, lefthook.yml, pr-quality-guards.yml) and a fixture; it adds no migration, auth flow, API route, or .sql, and processes no user data — the production PII posture is unchanged (guaranteed by the pre-existing L3 backstop).`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Shared script exists & is blocking.** `.github/scripts/check-client-pii-sentry.sh` exists, is `chmod +x`, and `exit 1`s when given a path containing a direct `Sentry.captureException`/`captureMessage` with `userId`/`user_id`/`email` in `extra`; `exit 0` otherwise.
- [ ] **AC2 — Non-vacuous, BOTH shapes.** Running the script against a synthetic fixture with a **same-line** violation (`Sentry.captureException(err, { extra: { userId } })`) AND a separate fixture with a **multi-line** violation (`Sentry.captureException(err, {\n  extra: { userId },\n})`) — both produce a non-empty offender list and `exit 1`. *(This is the AC the single-line grep would fail; it is the reason the script must be multi-line-aware.)*
- [ ] **AC3 — False-positive-free against all current sites.** Running the script against the real working tree (`apps/web-platform/{lib,components,app}`) produces **zero** offenders and `exit 0`. Verified-green set: `lib/upload-attachments.ts` (×2), `components/concurrency/upgrade-at-capacity-modal.tsx` (×2), `components/chat/chat-surface.tsx`, `app/global-error.tsx`, `lib/observability-edge.ts` (×2 — `extra: transformedExtra` variable form), `components/dashboard/workspace-identity-tile.tsx`.
- [ ] **AC4 — Helper + api excluded.** The script does NOT flag `lib/client-observability.ts:101` (the sanctioned helper, which legitimately forwards a sanitized `cleanExtra`) and does NOT flag anything under `apps/web-platform/app/api/**` (server routes).
- [ ] **AC5 — Fixture test auto-runs in CI.** `.github/scripts/test/test-check-client-pii-sentry.sh` exists, follows the offline-fixture convention (synthetic inputs, no `gh`/network), passes locally via `bash .github/scripts/test/run-all.sh`, and ends with the harness's `ALL FIXTURE TESTS PASS` line. The existing `guard-script-fixture-tests` CI job runs it with no workflow edit.
- [ ] **AC6 — lefthook pre-commit + pre-push.** `lefthook.yml` gains a `client-pii-grep` command under `pre-commit:` AND a new top-level `pre-push:` section with the same command. Both invoke `bash .github/scripts/check-client-pii-sentry.sh` over the client-importable globs (path-array form per gobwas `**` semantics — see Sharp Edges).
- [ ] **AC7 — CI mirror job.** `.github/workflows/pr-quality-guards.yml` gains a `client-pii-grep` job that runs the same shared script against the checked-out tree and fails the PR on a violation. Job comment cites #3703 and explains the boundary vs `userid-bypass-lint`.
- [ ] **AC8 — Frame in job + script header.** Both the CI job comment and the script header state: "signal-quality gate, NOT a security control; L3 `beforeSend` backstop guarantees prod posture." No opt-out label support (matching `pii-grep`).
- [ ] **AC9 — PR body.** PR body contains `Closes #3703`; milestone set to `Phase 4: Validate + Scale`.

## Implementation Phases

### Phase 1 — Shared script (the single implementation)

Create `.github/scripts/check-client-pii-sentry.sh`:

- **Inputs:** Accept either explicit paths (`{staged_files}` from lefthook) OR, when invoked with no args (CI mirror), default to scanning the client-importable roots `apps/web-platform/lib apps/web-platform/components apps/web-platform/app` for `*.ts`/`*.tsx`.
- **Exclusions:** skip any path under `apps/web-platform/app/api/`; skip `apps/web-platform/lib/client-observability.ts` (the sanctioned helper). *(Match the issue's `grep -v '/api/'` and `grep -v 'client-observability.ts'`.)*
- **Detection (multi-line-aware — load-bearing):** For each candidate file, find every `Sentry.captureException(` / `Sentry.captureMessage(` occurrence and examine the call's **argument span** (the call site line plus a bounded look-ahead window to the matching `)` or a small fixed window, e.g. next ~8 lines), testing whether that span contains an `extra:` object whose body matches `\b(userId|user_id|email)\b`. A line-by-line `grep` pipeline (the issue's candidate) is **insufficient** — it misses the multi-line shape that all 4 real sites use. Implementation options (pick the simplest that passes AC2/AC3): (i) `awk` state machine that turns on a window when it sees the `Sentry.capture*(` token and scans until the call closes; (ii) `grep -Pzo` null-data multi-line match; (iii) `perl -0777` slurp + regex. Prefer `awk` (no PCRE/`perl` dependency assumptions — verify `grep -P` availability before choosing (ii)).
- **Output contract:** print each offender as `path:line: <snippet>`; `exit 1` if any; `exit 0` (silent or one-line notice) otherwise. Header comment carries the AC8 frame string + the boundary-vs-`userid-bypass-lint` note.

### Phase 2 — Fixture test (offline, auto-discovered)

Create `.github/scripts/test/test-check-client-pii-sentry.sh` modeled byte-for-shape on `test-check-auto-commit-density.sh`:

- Build synthetic fixture files in a `mktemp -d`, run the **real script** against them (the script is tree-scanning + offline, so unlike the density test it can exercise the SUT directly — no `gh`/network gating needed).
- Required fixture cases: (1) same-line `userId` violation → expect exit 1; (2) multi-line `userId` violation → expect exit 1; (3) `email` violation → exit 1; (4) `user_id` snake-case → exit 1; (5) clean `extra: { filename }` → exit 0; (6) `tags`-only, no `extra` → exit 0; (7) a file under a synthetic `app/api/` path with a violation → exit 0 (excluded); (8) a synthetic `client-observability.ts` with a violation → exit 0 (excluded); (9) `extra: someVar` variable form (mirrors `observability-edge.ts`) → exit 0.
- End with PASS/FAIL tally and `exit 1` on any FAIL (harness convention).

### Phase 3 — lefthook wiring (consumer a)

Edit `lefthook.yml`:

- Under `pre-commit.commands:`, add `client-pii-grep` (choose a `priority:` consistent with neighbors; glob = path-array of the client-importable subdirs, **not** `**/*` — gobwas `**` silently no-ops without explicit subdirs, per `2026-03-21-lefthook-gobwas-glob-double-star.md`):
  ```yaml
  client-pii-grep:
    priority: 5
    glob:
      - "apps/web-platform/lib/**/*.{ts,tsx}"
      - "apps/web-platform/components/**/*.{ts,tsx}"
      - "apps/web-platform/app/**/*.{ts,tsx}"
    run: bash .github/scripts/check-client-pii-sentry.sh {staged_files}
  ```
- Add a NEW top-level `pre-push:` section (none exists today) with `commands:` containing the same `client-pii-grep` entry. *(Verify the lefthook version in use supports `pre-push` — it does by default; confirm at /work.)*

### Phase 4 — CI mirror job (consumer b)

Edit `.github/workflows/pr-quality-guards.yml`: add a `client-pii-grep` job (sibling to `pii-grep` / `userid-bypass-lint`):

- `runs-on: ubuntu-latest`; `uses: actions/checkout@…` (pin to the same SHA the file already uses); step runs `bash .github/scripts/check-client-pii-sentry.sh` (no args → CI tree-scan mode).
- No opt-out label (match `pii-grep`'s comment rationale, adapted to signal-quality framing).
- Job comment: cite #3703, state the signal-quality (not security) frame, and the boundary vs `userid-bypass-lint` (logger surface) and vs `pii-grep` (Linear CDN URLs).

## Design Decision: multi-line detection (the crux)

The issue's candidate grep is a **single-line pipeline**. Validated 2026-06-05:

- Same-line violation `Sentry.captureException(err, { extra: { userId } })` → **caught** ✅
- Multi-line violation (Sentry call on line N, `extra: {` on line N+1) → **MISSED** ❌
- All 4 named real sites are written multi-line (e.g. `upgrade-at-capacity-modal.tsx:128-130`).

A future regressing author overwhelmingly copies the surrounding multi-line house style → the single-line grep would be **vacuous against the exact regression class the gate is for**. Therefore the shared script must scan the call's argument span, not one line. AC2 enforces this with an explicit multi-line red fixture. (The single-line grep remains the correct *false-positive* oracle — the tree is clean today — but is the wrong *non-vacuity* oracle.)

## Files to Edit

- `lefthook.yml` — add `client-pii-grep` under `pre-commit` + new `pre-push:` section (Phase 3).
- `.github/workflows/pr-quality-guards.yml` — add `client-pii-grep` job (Phase 4).

## Files to Create

- `.github/scripts/check-client-pii-sentry.sh` — the single shared implementation (Phase 1).
- `.github/scripts/test/test-check-client-pii-sentry.sh` — offline fixture test, auto-discovered by `run-all.sh` (Phase 2).

## Open Code-Review Overlap

2 open code-review issues mention the planned files:
- **#3703** — this issue itself (the target). N/A.
- **#3829** — "review: CI gate enforcing 'new Sentry monitor type → sentry-scrub.ts must change'". **Acknowledge** (do NOT fold in): different concern (Sentry *monitor-type carve-out enforcement* on `sentry-scrub.ts`), different file surface, its own cycle. Mentions `pr-quality-guards.yml` only as the host workflow. Remains open.

No other overlaps (`.github/scripts` returned zero open code-review issues).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a CI/lefthook tooling change. No UI surface (Files-to-Create/Edit contain no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`), no regulated-data DDL/auth/API/`.sql`, no new infrastructure, no new vendor/secret/runtime process. Product/UX Gate, GDPR gate (2.7), IaC gate (2.8), and external research are all correctly skipped. The change *guards* a PII-adjacent surface but the gate itself is static source-text analysis processing no user data; the production PII posture is unchanged (owned by the pre-existing L3 backstop).

## Observability

```yaml
liveness_signal:
  what: "client-pii-grep CI job pass/fail status on every PR; lefthook command on every pre-commit/pre-push"
  cadence: "per-PR (CI) + per-commit/per-push (lefthook)"
  alert_target: "GitHub PR checks UI (red X on violation)"
  configured_in: ".github/workflows/pr-quality-guards.yml (client-pii-grep job) + lefthook.yml"
error_reporting:
  destination: "GitHub Actions job log + ::error:: annotation on the offending line(s); lefthook stderr locally"
  fail_loud: true  # blocking exit 1 — not advisory
failure_modes:
  - mode: "false-positive (blocks a legitimate PR/commit)"
    detection: "AC3/AC4 fixtures + working-tree green-sweep; contributor sees the annotation"
    alert_route: "PR check failure; maintainer extends exclusion or refines detection"
  - mode: "false-negative / vacuous (multi-line bypass slips)"
    detection: "AC2 multi-line red fixture in test-check-client-pii-sentry.sh, run by guard-script-fixture-tests on every PR"
    alert_route: "fixture-test CI job fails if detection regresses; L3 beforeSend still strips at runtime (no user impact)"
  - mode: "script regression (always exit 0)"
    detection: "AC2 red fixtures assert exit 1; a broken script fails its own test"
    alert_route: "guard-script-fixture-tests job red"
logs:
  where: "GitHub Actions run logs (pr-quality-guards / client-pii-grep + guard-script-fixture-tests jobs)"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "bash .github/scripts/test/run-all.sh   # NO ssh; runs the fixture suite locally and in CI"
  expected_output: "ALL FIXTURE TESTS PASS"
```

## Test Scenarios

1. **Non-vacuity (same-line):** synthetic file with `Sentry.captureException(err, { extra: { userId } })` → script exit 1, offender printed. *(Validated 2026-06-05: single-line grep catches this.)*
2. **Non-vacuity (multi-line):** synthetic file with the Sentry call and `extra: { userId }` on separate lines → script exit 1. *(Validated 2026-06-05: single-line grep MISSES this; multi-line script must catch it.)*
3. **False-positive-free:** real working tree → exit 0, zero offenders. *(Validated 2026-06-05 against the candidate grep: exit 1 / empty.)*
4. **Exclusions:** synthetic `app/api/...` violation → exit 0; synthetic `client-observability.ts` violation → exit 0.
5. **Variable-form extra:** `extra: someVar` (no inline `userId`) → exit 0 (mirrors real `observability-edge.ts`).
6. **Snake-case + email:** `user_id` and `email` keys each trigger exit 1.
7. **lefthook pre-commit:** stage a synthetic violating `.tsx` under `components/` → `git commit` blocked.
8. **lefthook pre-push:** same violation reaches `git push` (if commit bypassed via `--no-verify`) → push blocked.

## Sharp Edges

- **Single-line grep is vacuous against the real regression shape.** The 4 known sites are multi-line; a regressing author copies that style. The shared script MUST scan the call's argument span. AC2's multi-line red fixture is the gate on this — do not ship a script that passes only the same-line fixture.
- **`gdpr-gate-advisory` is advisory (exit 0); this gate is blocking (exit 1).** Model the *invocation shape* on it, not the exit contract. Don't copy `set -euo pipefail; emit_incident; exit 0` semantics — they'd defeat the gate.
- **lefthook glob must be path-array, not `**/*`.** gobwas `**` silently no-ops without explicit intermediate subdirs (`2026-03-21-lefthook-gobwas-glob-double-star.md`). Use the per-subdir `apps/web-platform/{lib,components,app}/**/*.{ts,tsx}` array form.
- **No `pre-push:` section exists in lefthook.yml today.** Phase 3 adds the first one — verify YAML structure (`pre-push:` is a sibling top-level key to `pre-commit:`, each with its own `commands:` map).
- **Don't collapse with `userid-bypass-lint`.** That gate (#3698) is `logger.*` in `(server|app)`; this is `Sentry.*` in client-importable `{lib,components,app}`. Different surface, different emit primitive. Document the boundary so a future maintainer doesn't merge them.
- **`grep -P` availability.** If the script uses `grep -Pzo` for multi-line matching, verify GNU grep with PCRE is available on `ubuntu-latest` AND the local dev shell; prefer the `awk` window approach to avoid the dependency. Exercise the exact chosen form against a real fixture (not just `--version`).
- **A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled (threshold `none` with a sensitive-path scope-out reason).
- **Frame discipline.** Every operator-facing string (script header, CI job comment, PR body) must call this a *signal-quality* gate, not a security control, and must name the L3 backstop as the actual prod guarantee. Over-claiming "this prevents PII leaks" is false (L3 already does) and invites the centralization-overclaim defect class (#3685).

## Premise Validation

Checked 2026-06-05: Issue #3703 is **OPEN**, milestone already `Phase 4: Validate + Scale` (no change needed). Referenced PR #3700 / issue #3696 (the 3-layer client-PII defense being relied on) confirmed present: `lib/client-observability.ts` ships `ClientExtra`/`stripPiiKeys` (helper), `sentry.client.config.ts:108` ships `beforeSend → stripUserContextFromEvent` (L3 backstop). The candidate detection grep was run against the live tree (false-positive-free) and against synthetic violations (non-vacuous same-line, **vacuous multi-line** — the load-bearing finding). All 4 named green-sites confirmed present and non-matching. The shared-script+test precedent (`.github/scripts/` + `run-all.sh`) and the `pii-grep`/`userid-bypass-lint`/`gdpr-gate-advisory` precedents were all read in-tree. No stale premises.
