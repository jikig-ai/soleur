<!-- iac-routing-ack: plan-phase-2-8-reviewed — quotes `terraform apply` / `doppler secrets` verb-phrases inside fenced fixtures, not real prod-write steps -->
---
title: "ci: harden test-pretooluse-hooks Test 6 F2 telemetry assertion (deterministic, agent-independent)"
date: 2026-06-02
type: chore
issue: 4818
branch: feat-one-shot-4818-test6-f2-telemetry-assert
lane: cross-domain
status: planned
---

# 🐛→♻️ ci: harden Test 6 F2 telemetry assertion (deterministic, agent-independent)

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Research Insights (live probes), Risks (precedent-diff), gate verification
**Research agents used:** None spawnable — the planning-subagent context lacks the Task tool (nested subagents inherit prompt text only; see learning `2026-06-02-env-default-flip-breaks-implicit-ci-consumer.md` Session Error #1). All deepen-plan hard gates (4.4 precedent-diff, 4.5 network-outage, 4.6 user-brand-impact, 4.7 observability, 4.8 PAT-halt) and the round-1 realism passes (verify-the-negative) were executed mechanically by the planner.

### Key Improvements
1. Both assertion forms (dry-run positive + enforce/unset negative) probed live against repo HEAD — envelope shapes pinned verbatim in §Research Insights.
2. Corrected the issue body's `INCIDENTS_REPO_ROOT` snippet: the jsonl lands at `$root/.claude/.rule-incidents.jsonl`, not directly under the root (§Research Reconciliation).
3. `env -u` vs `env -i` distinction surfaced (the unit test's `env -i` strips PATH and would break `jq` in CI — §Sharp Edges).
4. Precedent-diff confirms the deterministic step is a CI mirror of the proven `run_hook` unit-test harness, not a novel pattern.

### Gate Results (all PASS)
- **4.4 precedent-diff:** direct-pipe form precedented by `prod-write-defer-gate.test.sh:run_hook`; jsonl-read precedented by `rule-metrics-aggregate.yml`. Not novel.
- **4.5 network-outage:** no triggers.
- **4.6 user-brand-impact:** present, threshold `none`, scope-out reason non-empty; edited file `test-pretooluse-hooks.yml` does NOT match the sensitive-path regex (verified mechanically).
- **4.7 observability:** all 5 fields populated; `discoverability_test.command` uses `gh` (no ssh).
- **4.8 PAT-halt:** no PAT-shaped variables/literals.
- **verify-the-negative:** the sole "do NOT" is a design directive, not a falsifiable code-behavior claim; the "step-scoped env" claim verified live via Probe 2.

## Overview

`.github/workflows/test-pretooluse-hooks.yml` Test 6 ("F2 prod-write defer gate (dry-run telemetry)") is the **only** surface that exercises `prod-write-defer-gate.sh` through the real `claude-code-action` runtime. Its telemetry-content assertion — that a `kind=would_defer` row exists for `prod-write-defer-terraform-apply` — is **soft and non-deterministic**:

1. It depends on the agent *choosing* to issue a raw `terraform apply -no-color` Bash call that the F2 regex matches. On run [26825756941](https://github.com/jikig-ai/soleur/actions/runs/26825756941) the agent reasoned around the missing `terraform` binary and never issued the hooked command, so the row was absent.
2. The "Assert F2 defer-gate dry-run telemetry" step (lines 185-204) **exits 0** when the row is absent — it emits only `::warning::`, never `exit 1`.

Net effect: the assertion that PR #4806's `env: SOLEUR_DEFER_DRYRUN: "1"` pin is meant to protect can **silently no-op**. A future regression that breaks dry-run `would_defer` emission under the pin would pass CI green as long as the agent happens not to run the exact command.

**The fix is pure CI-workflow hardening** — no product code, no hook-logic change. Add a deterministic, agent-independent step that pipes a synthetic payload directly through the hook and hard-asserts (`exit 1` on failure) both the dry-run envelope (`kind=would_defer` + empty decision) AND the negative/enforce envelope (`permissionDecision=defer` + `kind=defer_requested` with the var unset). The hook's behavior is already proven deterministically by the 62-case unit suite (`prod-write-defer-gate.test.sh`, incl. `D4 default-unset enforce` and `G2 invalid-value`); this issue brings the **live-workflow** assertion to the same determinism bar.

Keep the existing agent-driven Test 6 prompt as the real-runtime *smoke* (it still proves the hook fires through `claude-code-action` at all). Only the telemetry-*content* assertion moves to the deterministic direct-pipe step.

## Premise Validation

Checked all referenced artifacts against `origin/main` / live state:

- **Issue #4818** — OPEN, not closed by any PR. Premise holds (this is the work).
- **PR #4806 (F2 enforce-flip)** — MERGED 2026-06-02T14:08:19Z. The `env: SOLEUR_DEFER_DRYRUN: "1"` pin it added is present at `test-pretooluse-hooks.yml:71`. Premise holds.
- **`.github/workflows/test-pretooluse-hooks.yml`** — exists; the soft-assert step (lines 185-204, `::warning::` + `exit 0` on absent row) and the agent-driven Test 6 prompt (lines 138-152) are present exactly as the issue describes.
- **`.claude/hooks/prod-write-defer-gate.sh`** — exists; hardcoded default is `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-0}"` (enforce) at line 35; dry-run branch emits `kind=would_defer` (line 235), enforce branch emits `kind=defer_requested` (line 244).
- **`.claude/hooks/prod-write-defer-gate.test.sh`** — exists; `D4 default-unset enforce` at line 264, `G2` invalid-value at line 363. The isolation pattern is `INCIDENTS_REPO_ROOT="$incidents"` redirecting the jsonl to `$incidents/.claude/.rule-incidents.jsonl` (test lines 37, 52).
- **`.claude/hooks/lib/incidents.sh`** — `_incidents_repo_root()` honors `INCIDENTS_REPO_ROOT` (line 37); writes to `$repo_root/.claude/.rule-incidents.jsonl` (line 209); `emit_incident` calls `mkdir -p` so the `.claude/` subdir is created automatically.
- **Cited learning `2026-06-02-env-default-flip-breaks-implicit-ci-consumer.md`** — exists at the cited path. Documents this exact CI-consumer blast-radius class and the two-move fix that motivated this follow-up.

No stale premises. **Live behavior probed at plan-write time** (2026-06-02, see §Research Insights) — both the dry-run and enforce/unset forms produce the exact envelopes the ACs assert.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (entered via one-shot → plan, no brainstorm). The issue body is the source of truth and was verified against the codebase above. One correction the issue body's proposed snippet needs:

| Issue-body claim | Reality | Plan response |
|---|---|---|
| `INCIDENTS_REPO_ROOT="$(mktemp -d)"` then "read the incidents file under INCIDENTS_REPO_ROOT" | The jsonl lands at `$INCIDENTS_REPO_ROOT/.claude/.rule-incidents.jsonl` (lib `incidents.sh:209`), NOT directly under the root. `emit_incident`'s `mkdir -p` creates the `.claude/` subdir. | AC2/AC3 read `"$root/.claude/.rule-incidents.jsonl"`, matching the unit-test path convention (`test.sh:52`). |
| Snippet calls `.claude/hooks/prod-write-defer-gate.sh` directly via pipe | Hook sources `lib/incidents.sh` via `dirname "${BASH_SOURCE[0]}"`; runs fine when invoked by absolute or repo-relative path. Confirmed live. | Invoke as `.claude/hooks/prod-write-defer-gate.sh` (repo root is the workflow CWD after checkout). |

## User-Brand Impact

This is a CI-only test-harness change; it ships no product surface and no hook-logic change.

- **If this lands broken, the user experiences:** nothing directly — but the *operator* (Soleur maintainer) loses a true-signal CI gate. A broken-but-green assertion means a future regression in the F2 prod-write defer gate's dry-run telemetry ships undetected, which is the safety mechanism that pauses destructive `terraform apply` / `git push origin main` / `doppler secrets` commands before they hit a founder's prod infra.
- **If this leaks, the user's data / workflow / money is exposed via:** N/A — no data path, no secret, no PII. The synthetic payload is a hardcoded `terraform apply` string with no real credentials.
- **Brand-survival threshold:** none — this is a meta-safety CI gate, not a user-facing surface. The diff touches only `.github/workflows/test-pretooluse-hooks.yml`; no sensitive path per the preflight Check 6 canonical regex.

> threshold: none, reason: CI-only workflow hardening; no schema/migration/auth/API/sensitive-path surface touched, no user-facing artifact, no secret handling.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Deterministic step added.** `.github/workflows/test-pretooluse-hooks.yml` gains a step (named e.g. `Assert F2 defer-gate telemetry (deterministic)`) that runs AFTER the agent-driven `Test hooks via claude-code-action` step and is independent of the agent (no `terraform` binary, no agent decision). Verify: `grep -n "deterministic" .github/workflows/test-pretooluse-hooks.yml` returns ≥1 match in a step `name:`.
- [x] **AC2 — Dry-run positive hard-asserts.** The step pipes `'{"tool_input":{"command":"terraform apply"},"session_id":"ci-test6"}'` through the hook with `SOLEUR_DEFER_DRYRUN=1` and a fresh `INCIDENTS_REPO_ROOT="$(mktemp -d)"`, then asserts (a) stdout is empty-allow (`permissionDecision` absent / `{}`) AND (b) `$root/.claude/.rule-incidents.jsonl` contains exactly one row matching `.kind=="would_defer" and .rule_id=="prod-write-defer-terraform-apply"`. On failure the step **exits 1** (NOT `::warning::` + `exit 0`). Verify: `grep -n "exit 1" .github/workflows/test-pretooluse-hooks.yml` shows the deterministic step's failure path uses a hard exit.
- [x] **AC3 — Negative/enforce hard-asserts.** The same step (second probe, fresh `INCIDENTS_REPO_ROOT`) runs the identical payload with `SOLEUR_DEFER_DRYRUN` **unset** (`env -i`-style, mirroring unit-test `D4`), and asserts (a) stdout `permissionDecision=="defer"` and `hookEventName=="PreToolUse"` AND (b) the jsonl contains `.kind=="defer_requested" and .rule_id=="prod-write-defer-terraform-apply"`. On failure the step **exits 1**. This mirrors `D4 default-unset enforce` and proves the enforce default has not silently reverted to dry-run.
- [x] **AC4 — Old soft-assert step disposition.** The pre-existing "Assert F2 defer-gate dry-run telemetry" step (lines 185-204) is EITHER removed (its assertion is now subsumed by the deterministic step) OR explicitly retained as a documented agent-runtime smoke that keeps `exit 0`/`::warning::` semantics (because the agent may legitimately not run the command). The plan's chosen disposition: **fold the content-assertion into the new deterministic step and downgrade the old step to a non-failing informational dump** (keep the agent-runtime jsonl visible without gating on it). Verify the workflow has no remaining step that claims to assert F2 content but exits 0 on absence without an explicit "informational only" comment.
- [x] **AC5 — `actionlint` clean.** `actionlint .github/workflows/test-pretooluse-hooks.yml` reports zero errors (workflow file, NOT a composite action — `actionlint` is correct here). Embedded `run:` shell additionally validated via `bash -n` against the extracted snippet (NOT `bash -n` on the `.yml` itself).
- [x] **AC6 — `if: always()` preserved.** The deterministic step runs with `if: always()` so a failed agent step does not skip it (the agent step is now non-load-bearing for the content assertion, but the deterministic probe must still run to catch hook-logic regressions independent of agent behavior).
- [x] **AC7 — Hook + unit suite untouched.** The PR diff touches ONLY `.github/workflows/test-pretooluse-hooks.yml`. Verify: `git diff --name-only origin/main...HEAD` lists only that workflow file (plus the plan/spec artifacts). No change to `.claude/hooks/prod-write-defer-gate.sh` or `prod-write-defer-gate.test.sh`.

### Post-merge (operator)

- [ ] **AC8 — Live dispatch verification.** After merge, dispatch the workflow (`gh workflow run test-pretooluse-hooks.yml`) and confirm the deterministic step PASSES in a real run. Automation: feasible via `gh` CLI — bake into ship/postmerge as `gh workflow run` + poll. NOT operator-manual.

## Implementation Phases

### Phase 0 — Preconditions (read-only, re-verify against HEAD)

0.1. Re-read `test-pretooluse-hooks.yml:185-204` (soft-assert step) and `:61-71` (the `env: SOLEUR_DEFER_DRYRUN: "1"` pin) to confirm line numbers haven't drifted.
0.2. Confirm `actionlint` is available (`command -v actionlint`); if absent in the work env, note it and rely on the CI `actionlint` job + `bash -n` on the extracted snippet.
0.3. Re-run the two live probes from §Research Insights to confirm envelope shapes still hold on HEAD.

### Phase 1 — Add the deterministic assertion step (RED→GREEN)

1.1. Add a new workflow step after the `claude-code-action` step, named `Assert F2 defer-gate telemetry (deterministic)`, with `if: always()`. The step body (shell, pinned to the verified form):

```bash
# Probe 1: dry-run (SOLEUR_DEFER_DRYRUN=1) → kind=would_defer, allow.
root=$(mktemp -d)
out=$(printf '%s' '{"tool_input":{"command":"terraform apply"},"session_id":"ci-test6"}' \
  | env SOLEUR_DEFER_DRYRUN=1 INCIDENTS_REPO_ROOT="$root" .claude/hooks/prod-write-defer-gate.sh)
jsonl="$root/.claude/.rule-incidents.jsonl"
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""')
[[ "$decision" == "" ]] || { echo "::error::dry-run should allow (empty decision), got: $decision"; exit 1; }
count=$(jq -c 'select(.kind=="would_defer" and .rule_id=="prod-write-defer-terraform-apply")' "$jsonl" 2>/dev/null | wc -l)
[[ "$count" -ge 1 ]] || { echo "::error::dry-run would_defer row absent for terraform apply"; cat "$jsonl" 2>/dev/null; exit 1; }
echo "dry-run OK: $count would_defer row(s)"

# Probe 2: enforce default (SOLEUR_DEFER_DRYRUN unset) → permissionDecision=defer, kind=defer_requested.
root2=$(mktemp -d)
out2=$(printf '%s' '{"tool_input":{"command":"terraform apply"},"session_id":"ci-test6"}' \
  | env -u SOLEUR_DEFER_DRYRUN INCIDENTS_REPO_ROOT="$root2" .claude/hooks/prod-write-defer-gate.sh)
jsonl2="$root2/.claude/.rule-incidents.jsonl"
decision2=$(printf '%s' "$out2" | jq -r '.hookSpecificOutput.permissionDecision // ""')
ename2=$(printf '%s' "$out2" | jq -r '.hookSpecificOutput.hookEventName // ""')
[[ "$decision2" == "defer" && "$ename2" == "PreToolUse" ]] \
  || { echo "::error::enforce default should defer/PreToolUse, got decision=$decision2 event=$ename2"; exit 1; }
count2=$(jq -c 'select(.kind=="defer_requested" and .rule_id=="prod-write-defer-terraform-apply")' "$jsonl2" 2>/dev/null | wc -l)
[[ "$count2" -ge 1 ]] || { echo "::error::enforce defer_requested row absent for terraform apply"; cat "$jsonl2" 2>/dev/null; exit 1; }
echo "enforce-default OK: $count2 defer_requested row(s)"
```

> Note on `env -u`: the hook reads `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-0}"`. The workflow's `claude-code-action` step pins `SOLEUR_DEFER_DRYRUN: "1"` at *that step's* env scope only (line 71) — it does NOT leak into sibling `run:` steps. So in this new step the var is already unset at the job level; `env -u SOLEUR_DEFER_DRYRUN` is belt-and-suspenders to guarantee the unset-default path is exercised regardless of any future job-level env addition. **At /work time, confirm there is no job-level `env: SOLEUR_DEFER_DRYRUN` on `test-hooks`** (`grep -n "SOLEUR_DEFER_DRYRUN" .github/workflows/test-pretooluse-hooks.yml` — expect exactly one hit, the step-scoped pin at line 71); if a job-level pin exists, `env -u` is load-bearing.

1.2. Verify the step locally by extracting the `run:` body and executing it (`bash -n` for syntax, then run end-to-end — both probes must print OK and exit 0 on HEAD). This is the RED→GREEN gate: it is GREEN now (hook is correct); the value is that it goes RED if a future change breaks emission.

### Phase 2 — Downgrade the old soft-assert step (AC4)

2.1. Convert the existing "Assert F2 defer-gate dry-run telemetry" step (lines 185-204) into a non-gating informational dump: keep it printing the agent-runtime jsonl (`cat "$INCIDENTS_FILE"`) for debugging, but add a comment that it is informational-only (the content assertion now lives in the deterministic step) and that its `exit 0`-on-absence is intentional because the agent may legitimately not issue the command. Do NOT leave two steps that both claim to assert the same content with different exit semantics.

2.2. Leave the "Assert rule-incident telemetry emitted" step (lines 170-183, JSON validity check) unchanged — it asserts a different invariant (jsonl is well-formed) and is orthogonal.

### Phase 3 — Validate

3.1. `actionlint .github/workflows/test-pretooluse-hooks.yml` → zero errors.
3.2. `bash -n` on each extracted `run:` snippet.
3.3. `git diff --name-only origin/main...HEAD` → only the workflow file (+ artifacts).

## Open Code-Review Overlap

None. Queried open `code-review` issues for bodies containing `test-pretooluse-hooks.yml` and `prod-write-defer-gate` — zero matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/tooling-only change (a test-harness assertion in a `workflow_dispatch`-only workflow). No Product/UX surface (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` files created). No Legal/GDPR surface (no regulated data, no schema/auth/API). No Finance/Marketing/Growth surface.

## Infrastructure (IaC)

Skip — no new infrastructure. The change edits an existing `.github/workflows/*.yml` test workflow; it introduces no server, secret, vendor account, DNS record, systemd unit, or persistent runtime process. The verb-phrases `terraform apply` / `doppler secrets` appear only as **synthetic test fixtures inside fenced code blocks**, not as provisioning steps (hence the `iac-routing-ack` comment at the top of this plan).

## Observability

This plan edits a code-class file under `.github/workflows/` (CI surface), so the 5-field schema applies. The observed surface is the CI gate itself.

```yaml
liveness_signal:
  what: "Deterministic F2-telemetry assertion step in test-pretooluse-hooks.yml"
  cadence: "On manual workflow_dispatch (the workflow is workflow_dispatch-only; not scheduled)"
  alert_target: "GitHub Actions run status (red check = regression in F2 dry-run/enforce telemetry)"
  configured_in: ".github/workflows/test-pretooluse-hooks.yml (new deterministic step)"
error_reporting:
  destination: "GitHub Actions step log + ::error:: annotation; non-zero exit fails the job"
  fail_loud: true  # exit 1 on missing/wrong row — replaces the prior ::warning::+exit-0 soft-pass
failure_modes:
  - mode: "Dry-run would_defer row absent under SOLEUR_DEFER_DRYRUN=1"
    detection: "jq count==0 on .kind==would_defer + rule_id match"
    alert_route: "exit 1 → red GitHub Actions check"
  - mode: "Enforce default reverted to dry-run (permissionDecision != defer with var unset)"
    detection: "jq on stdout permissionDecision/hookEventName + defer_requested row count"
    alert_route: "exit 1 → red GitHub Actions check"
  - mode: "Hook crashes / emits malformed jsonl"
    detection: "jq parse failure on the incidents file (existing 'Assert rule-incident telemetry emitted' step) + empty stdout"
    alert_route: "exit 1 → red GitHub Actions check"
logs:
  where: "GitHub Actions run logs (ephemeral, ~90-day retention per repo settings); the synthetic incidents jsonl lives in a mktemp dir, discarded with the runner"
  retention: "Run logs per GitHub default; synthetic jsonl is ephemeral by design (no operator sink pollution)"
discoverability_test:
  command: "gh workflow run test-pretooluse-hooks.yml && gh run watch $(gh run list --workflow=test-pretooluse-hooks.yml --limit 1 --json databaseId -q '.[0].databaseId')"
  expected_output: "Job green; deterministic step prints 'dry-run OK' and 'enforce-default OK'"
```

## Test Scenarios

- **T1 (dry-run positive):** `SOLEUR_DEFER_DRYRUN=1` + `terraform apply` payload → stdout `{}` (empty decision), jsonl `kind=would_defer` row present. **Verified live 2026-06-02.**
- **T2 (enforce/negative):** var unset + `terraform apply` payload → stdout `permissionDecision=defer`/`hookEventName=PreToolUse`, jsonl `kind=defer_requested` row present. **Verified live 2026-06-02.**
- **T3 (regression guard):** if a future change makes the dry-run branch stop emitting `would_defer` (or the enforce default silently flips to `:-1`), the corresponding probe's `jq count` is 0 / `decision` mismatches → step `exit 1` → red check. This is the whole point: the soft `::warning::` no longer hides the regression.
- **T4 (`actionlint`):** workflow parses clean; embedded shell `bash -n`-clean.

## Research Insights

**Live behavior probed at plan-write time (2026-06-02), repo HEAD:**

Dry-run (`SOLEUR_DEFER_DRYRUN=1`, fresh `INCIDENTS_REPO_ROOT`):
```
stdout=[{}]
jsonl row: {"...","rule_id":"prod-write-defer-terraform-apply","event_type":"applied","kind":"would_defer",...}
```

Enforce default (`SOLEUR_DEFER_DRYRUN` UNSET, fresh `INCIDENTS_REPO_ROOT`):
```
stdout=[{ "hookSpecificOutput": { "hookEventName": "PreToolUse", "permissionDecision": "defer", ... } }]
jsonl row: {"...","rule_id":"prod-write-defer-terraform-apply","event_type":"deny","kind":"defer_requested",...}
```

**Key facts grounding the ACs:**

- The incidents jsonl path is `$INCIDENTS_REPO_ROOT/.claude/.rule-incidents.jsonl` (`lib/incidents.sh:209`), not directly under the root — the issue's snippet omitted the `.claude/` segment. `emit_incident`'s `mkdir -p` creates `.claude/` automatically, so the probe does NOT need to pre-create it.
- The unit suite (`prod-write-defer-gate.test.sh`) already uses this exact isolation pattern (`run_hook` at lines 31-41; `INCIDENTS_REPO_ROOT="$incidents"` + jsonl at `$incidents/.claude/.rule-incidents.jsonl`). The deterministic workflow step is a CI mirror of the unit harness — reuse the proven form rather than invent one.
- `D4 default-unset enforce` (test line 264) is the unit-suite analogue of Probe 2; `assert_match_dry` (line 46) is the analogue of Probe 1. The workflow step's value is that it runs the SAME assertions through CI on the SAME files the agent-runtime path exercises, closing the live-surface gap.
- The `claude-code-action` step's `env: SOLEUR_DEFER_DRYRUN: "1"` (line 71) is **step-scoped**, not job-scoped — confirmed by reading the YAML structure (the `env:` block is nested under that single `uses:` step). Sibling `run:` steps do not inherit it. Hence Probe 2's unset path is naturally exercised; `env -u` is defensive.

**Precedent-diff (deepen Phase 4.4).** The deterministic step is NOT a novel pattern — it is a CI transcription of the proven unit-test harness:

| Concern | Precedent | This plan's step |
|---|---|---|
| Pipe synthetic payload through hook | `prod-write-defer-gate.test.sh:40` — `printf "%s" "$1" \| "$HOOK"` | `printf '%s' '{...}' \| ... .claude/hooks/prod-write-defer-gate.sh` |
| Redirect incidents jsonl off the real sink | `test.sh:37` — `INCIDENTS_REPO_ROOT="$incidents"` | `INCIDENTS_REPO_ROOT="$(mktemp -d)"` per probe |
| Read the row | `test.sh:52,56` — jsonl at `$incidents/.claude/.rule-incidents.jsonl`, `jq 'select(.kind=="would_defer")'` | identical path + `jq` select |
| Read incidents jsonl in a workflow | `.github/workflows/rule-metrics-aggregate.yml` already reads the incidents jsonl | same read pattern |

The one deliberate divergence from the unit harness: `env -u SOLEUR_DEFER_DRYRUN` (unset one var) instead of `env -i` (clean slate), because the CI step needs `PATH` for `jq`/`bash` — documented in §Sharp Edges.

**Cited learning** `knowledge-base/project/learnings/best-practices/2026-06-02-env-default-flip-breaks-implicit-ci-consumer.md` — documents the implicit-CI-consumer blast radius that PR #4806 surfaced, and notes (Session Errors) that the planning-subagent context lacks the Task tool (deepen/plan-review fan-out runs mechanically) and that the IaC-routing PreToolUse hook false-positives on plan bodies quoting `terraform apply` (handled here via the `iac-routing-ack` comment).

## Sharp Edges

- **`env -u` vs `env -i`:** the unit test uses `env -i` (clean env) because it must also strip `HOME`/`PATH` pollution for hermetic isolation. The workflow step runs inside a job that needs `PATH` (for `jq`, `bash`), so use `env -u SOLEUR_DEFER_DRYRUN` (unset only that one var) rather than `env -i` (which would strip `PATH` and break `jq`). Do NOT copy `env -i` from the unit test verbatim into the workflow.
- **`exit 1` placement:** the failure path MUST `exit 1`, not `echo ::error:: && exit 0`. The entire point of #4818 is that the old step exited 0 on absence. Grep the new step at review to confirm every assertion branch ends in `exit 1` on failure.
- **`if: always()` is load-bearing on the deterministic step.** If the agent step fails (e.g., API hiccup), the job must still run the deterministic probe — it is independent of the agent and is the real regression gate now.
- **Two-step content-assertion drift:** if AC4 retains the old step, do NOT leave two steps that both claim to assert `would_defer` content with different exit semantics — that re-creates the ambiguity #4818 is removing. The plan folds content-assertion into the deterministic step and downgrades the old step to an explicitly-informational dump.
- **A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a non-empty scope-out reason (CI-only, no sensitive path) — satisfies the gate.
- **`actionlint` on a workflow (correct) vs composite action (wrong):** `test-pretooluse-hooks.yml` is a workflow (`on:` + `jobs:`), so `actionlint` is the right validator. Do NOT confuse with composite-action files (`.github/actions/*/action.yml`), where `actionlint` emits spurious schema errors.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Make the agent prompt more forceful so it always runs the raw `terraform apply` | Rejected | Still non-deterministic — agent compliance is not an invariant; the issue explicitly calls for an *agent-independent* assertion. |
| Install a real `terraform` binary on the runner so the agent's command actually runs | Rejected | Doesn't fix determinism (agent may still reason around it) and adds a heavy dependency for zero benefit; the hook fires on the command string regardless of whether the binary exists. |
| Move the whole F2 test out of `claude-code-action` entirely (pure direct-pipe) | Rejected | Loses the real-runtime smoke value — the agent-driven path proves the hook *fires through claude-code-action at all*, which the direct-pipe cannot. Keep both: smoke (agent) + content-assert (deterministic). |
| Add a second `defer_requested` negative probe (chosen) | Adopted | Mirrors unit-suite `D4`; cheaply covers the silent-revert-to-dry-run failure mode in the same step. The issue body explicitly suggests this ("Also consider asserting the negative"). |

No items deferred to a later phase — single-PR scope. No deferral tracking issues needed.
