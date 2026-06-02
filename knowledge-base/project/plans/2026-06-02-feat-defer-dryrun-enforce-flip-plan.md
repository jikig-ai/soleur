---
title: "F2 enforce-flip — SOLEUR_DEFER_DRYRUN default 1 → 0"
date: 2026-06-02
type: feat
issue: 3800
parent_issue: 3789
branch: feat-one-shot-3800-defer-dryrun-enforce-flip
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- This plan is ABOUT a PreToolUse hook that *defers* terraform/doppler prod-write commands for operator approval. It provisions no infrastructure. The doppler/terraform tokens appearing below are quoted command-strings the hook matches, not provisioning steps. Phase 2.8 reviewed: ## Infrastructure (IaC) section = Skipped (no new infra). -->

# feat: F2 enforce-flip — flip `SOLEUR_DEFER_DRYRUN` default 1 → 0

## Enhancement Summary

**Deepened on:** 2026-06-02

### Deepen-plan hard gates (all PASS)
- **Phase 4.6 User-Brand Impact halt** — section present, concrete, threshold `single-user incident`. PASS.
- **Phase 4.7 Observability gate** — all 5 fields present + non-placeholder; `discoverability_test.command` is `ssh`-free. PASS.
- **Phase 4.8 PAT-shaped variable halt** — no PAT-shaped TF var / env var / literal token. PASS.

### Verify-the-negative pass (Phase 4.45)
- **"sole consumer of the default"** — `grep SOLEUR_DEFER_DRYRUN` across `*.ts/*.sh/*.js/*.yml` returns exactly: the hook, its test, and `test-pretooluse-hooks.yml`. The plan already names the CI workflow as the implicit third consumer (handled by AC5) — claim CONFIRMED, correctly qualified.
- **"provisions nothing / no new infra"** — all 4 Files-to-Edit are `.claude/hooks/*` + a `.github/workflows/*.yml` test; none under `apps/*/infra/`. CONFIRMED.

### Live citation verification
- PR #3787 — `MERGED` 2026-05-15 (18-day dry-run window CONFIRMED).
- Issue #3800 — `OPEN` (target; `Closes #3800` in body). Issue #3789 — `OPEN` (parent stays open). CONFIRMED.
- Issue #4029 — `OPEN` (the security issue behind the doppler-stdout rule widening; symmetric issue-probe after the PR-probe returned not-a-PR). Plan's "pre-#4029 rename" reference CONFIRMED accurate.
- No AGENTS.md rule-IDs cited in the plan body → zero fabrication-class risk.

### Precedent-diff (Phase 4.4)
- No new scheduled job, no SQL `SECURITY DEFINER/INVOKER`, no lock/atomic-write/RPC pattern. The only pattern-bound idiom is the bash `${VAR:-default}` env-default — sibling precedent is the hook's own line 35 (the line being flipped). No novel pattern.

### Note on agent fan-out
The skills/learnings/research/review sub-agent fan-out (deepen-plan Phases 2, 3, 4, 5) requires the Task tool, which is unavailable in this planning-subagent context. The load-bearing deepen value — the three mandatory halt-gates, the verify-the-negative pass, and live citation verification — was executed mechanically (above) and all pass. The plan required no corrections from the deepen pass. The 5-agent plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) is likewise Task-gated; a self-review against those lenses found no findings (plan is a minimal one-line flip + consumer syncs; the blast-radius catch — CI Test 6's implicit default dependency — was already surfaced and handled by AC5; the flow-gap catch — the default-unset path — is AC3/D4).

---

> Original plan below (preserved verbatim).

## Overview

The F2 prod-write defer gate (`.claude/hooks/prod-write-defer-gate.sh`, shipped dry-run-default by PR #3787, merged 2026-05-15) has run in dry-run mode for 18 days (gate: ≥14 days — SATISFIED). This PR performs the **enforce-flip** anticipated by PR #3787 and documented in `.claude/hooks/README.md:251` and `:322`: change the hardcoded fallback

```bash
SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"   # before  (dry-run: emit would_defer, allow)
SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-0}"   # after   (enforce: emit defer_requested, return defer envelope)
```

at `.claude/hooks/prod-write-defer-gate.sh:35`.

In enforce mode, a matched prod-write command (`git push origin main`, `terraform apply`, doppler prod-secret writes) is paused for explicit operator approval via the CC `permissionDecision: "defer"` envelope, with an `approvals.jsonl` audit row appended and a `claude --resume <session_id>` hint emitted to stderr.

This is a **one-line behavioral flip plus two consumer-side edits** (CI workflow + docs prose that paraphrase "default is 1"). The hook's enforce path, bypass path, and fail-closed path are already implemented and tested (60/60 in `prod-write-defer-gate.test.sh`); this PR does not add new logic — it changes which path is the default.

**Re-evaluation gate (verified at plan time — all three SATISFIED). See "Research Reconciliation" below for evidence.**

## Research Reconciliation — Re-Evaluation Gate (Spec vs. Telemetry)

The issue defines a 3-part gate that MUST hold before flipping. All three were verified against the canonical telemetry log `/home/jean/git-repositories/jikig-ai/soleur/.claude/.rule-incidents.jsonl` (6,812 events; the worktree's copy does not exist — the log is `.gitignore`d and per-machine, living only in the main checkout).

| Gate criterion | Reality (verified 2026-06-02) | Verdict |
|---|---|---|
| **≥14 days dry-run elapsed** | PR #3787 merged 2026-05-15; today 2026-06-02 = **18 days** | PASS |
| **(1) No rule_id >10 false-positives WITHOUT a corresponding real prod-write attempt** | See per-rule breakdown below | PASS |
| **(2) None of the 3 starter rules blocks an operator-essential workflow lacking a bypass** | All 3 have the `CLAUDE_HOOK_BYPASS` flow + read-only escapes (`-help`/`-version`, `get`/`list`/`download`); verified by C9–C24 nomatch tests | PASS |
| **(3) `CLAUDE_HOOK_BYPASS=1` + REASON + OPERATOR flow tested E2E** | Tiers E1 (bypass allow), F1 (missing reason → fail-closed), D1–D3 (enforce envelope), H1 (approvals row) — 60/60 pass | PASS |

### Gate (1) — `would_defer` false-positive analysis (48 total entries)

```
27  prod-write-defer-terraform-apply
15  prod-write-defer-doppler-secrets-stdout
 6  prod-write-defer-doppler-prd-secrets    (retired rule_id — pre-#4029 rename)
 0  prod-write-defer-git-push-main
```

Per-record classification (one logical command per record, classified on the first command line; heredoc / `gh issue`-body matches are false-positives because the regex matched the literal verb-phrase *inside an issue/PR body or runbook heredoc*, not an actual invocation):

| rule_id | total | REAL prod-write attempts | false-positives | Gate (1) verdict |
|---|---|---|---|---|
| `prod-write-defer-terraform-apply` | 27 | **~13** genuine prd-config terraform-apply invocations | **~14** (7 `gh issue/pr` with the verb in the body; 4 `cat>`/`mkdir`/heredoc; 3 `#`-comment / `echo "→ …"` doc lines) | PASS — >10 FPs BUT abundant real attempts co-occur |
| `prod-write-defer-doppler-secrets-stdout` | 15 | **15** genuine prod-secret set/delete (11 prd/prd_terraform, 4 dev) | 0 | PASS |
| `prod-write-defer-doppler-prd-secrets` (retired) | 6 | 6 genuine | 0 | PASS |
| `prod-write-defer-git-push-main` | 0 | 0 | 0 | PASS (no traffic — operator uses feature branches + `gh pr merge`) |

**Interpretation of the gate wording.** The criterion is: *"No rule_id may have >10 false-positive hits **without a corresponding actual prod-write attempt**."* Only `terraform-apply` exceeds 10 false-positives (~14), but it ALSO has ~13 genuine prod-write attempts in the same window — the false-positives are an artifact of the operator authoring infra runbooks / issue bodies that *contain the literal verb-phrase*, not of a phantom-matching regex on a rule nobody uses. The gate's intent (a chronically-noisy regex on a rule with no real demand) is NOT met → **no regex refinement required before the flip.** Consistent with the issue's "Out of scope: new manifest regexes."

**Residual note (documented, not blocking):** the false-positive class for `terraform-apply` is "the regex fires on the verb appearing inside a `gh issue create --body "$(cat <<EOF … EOF)"` or a `cat > runbook.md <<EOF`". In enforce mode these now *defer the documentation-write command* — annoying but (a) bypassable via `CLAUDE_HOOK_BYPASS=1`, (b) out of scope per the issue (regex refinement deferred), (c) tracked as a follow-up below. It does not block the flip because the bypass exists and the gate criterion is about phantom rules, not heredoc-body noise. (This very plan tripped that exact false-positive at write time — the IaC-routing hook matched a quoted doppler verb-phrase in this document — confirming the class empirically; opted out via the reviewed `iac-routing-ack`.)

### Gate (2) — operator-essential workflows all have a bypass

The 3 starter rules and their operator escapes (verified via the nomatch test tier C9–C24 and `READONLY_FLAG_PATTERNS` in the hook):

- `git push origin main` — deferred intentionally (operator workflow is feature-branch + `gh pr merge`, gated separately). Bypass: `CLAUDE_HOOK_BYPASS=1`.
- `terraform apply` — operator-essential (drift remediation). Escapes: read-only `-help`/`-version`/`-h`/`-v` (C9–C12 nomatch), `terraform plan` not matched (C3), and `CLAUDE_HOOK_BYPASS=1` for the genuine apply.
- doppler prod-secret writes (`set`/`delete --config prd*`) — operator-essential. Escapes: `get`/`list`/`download`/`--help`/`-h` all read-only and unmatched (C15, C17, C18, C19, C20, C21); equals-form `--config=prd` unmatched (C16, C23); `prd-staging`/`stg`/`preview` unmatched (C5, C6, C22, C25). Genuine prod write: `CLAUDE_HOOK_BYPASS=1`.

No operator-essential workflow is blocked without a bypass. **Gate (2) PASS.**

### Gate (3) — bypass flow tested E2E

`prod-write-defer-gate.test.sh` already covers the full env-override bypass lifecycle (run at plan time: **60/60 PASS**):
- **E1** — `CLAUDE_HOOK_BYPASS=1` + `CLAUDE_HOOK_BYPASS_REASON` + `CLAUDE_HOOK_BYPASS_OPERATOR` → `kind=bypass`, allow (empty decision).
- **F1** — `CLAUDE_HOOK_BYPASS=1` with NO reason → `permissionDecision=deny` + `kind=hook_self_fault` (fail-closed).
- **D1–D3** — enforce mode (`SOLEUR_DEFER_DRYRUN=0`) → `permissionDecision=defer`, `hookEventName=PreToolUse`, `kind=defer_requested` for all 3 rules.
- **H1** — enforce mode appends an `approvals.jsonl` row.

Every enforce/bypass test already sets `SOLEUR_DEFER_DRYRUN=0` explicitly, so **the flip changes no existing test outcome** — the tests pin the env var rather than relying on the default. **Gate (3) PASS.**

## Research Reconciliation — Downstream Consumers of the Default

The hook is the **sole consumer** of the `SOLEUR_DEFER_DRYRUN` default (grep across `*.ts`/`*.sh`/`*.js` returned only the hook + its test). But the *prose* and a CI test rely on the default value:

| Surface | Current state | Impact of flip | Plan response |
|---|---|---|---|
| `.claude/hooks/prod-write-defer-gate.sh:15` (comment) | `# Mode (controlled by SOLEUR_DEFER_DRYRUN, default 1):` | comment becomes stale | update to `default 0` |
| `.claude/hooks/prod-write-defer-gate.sh:35` (the flip) | `${SOLEUR_DEFER_DRYRUN:-1}` | the behavioral change | flip to `:-0` |
| `.github/workflows/test-pretooluse-hooks.yml:130` + Test 6 + assertion `:186` | Test 6 NEVER exports the env var; it relies on the hardcoded default being 1 and asserts `kind=would_defer` for `terraform apply` | **BREAKS:** after flip, Test 6 runs in enforce mode → emits `defer_requested` (not `would_defer`) AND returns `permissionDecision=defer`, which the agent's own rubric (`:141`) judges as FAIL ("hook returns deny/blocks the call") | **Load-bearing edit:** add `env: SOLEUR_DEFER_DRYRUN: "1"` to the Test-6 step so it still exercises dry-run telemetry, and update the `:130` prose to "SOLEUR_DEFER_DRYRUN=1 is pinned for this test (the hardcoded default is now 0 / enforce)." |
| `.claude/hooks/README.md:248–252`, `:322–323` | documents "DEFAULT, hardcoded fallback" = 1, and "enforce-flip ships in a separate follow-up PR (#3800)" | prose becomes stale; #3800 IS this PR | update Modes section to state the default is now 0 (enforce); rewrite `:322` to past tense ("shipped in PR #3800") |

**Why the CI edit is load-bearing, not optional:** `test-pretooluse-hooks.yml` is the only place that exercises the hook through the real claude-code-action runtime (vs. the unit-test harness which injects stdin directly). If Test 6 silently flips to enforce mode, it will (a) report FAIL in the agent summary table and (b) emit a `::warning::` from the line-186 assertion. The test does not hard-`exit 1` (it `exit 0`s on missing telemetry), so it won't red the build — but it produces a false-negative signal that would confuse the next operator. The consumer edit ships in the same PR as the flip.

## User-Brand Impact

- **If this lands broken, the user experiences:** every prod-write command silently pauses mid-session with no clear resume path — OR (worse failure mode) the flip is mistyped (`:-0` → some invalid value) and the hook hits the `*)` arm → `deny_self_fault` DENIES every matched command unconditionally (fail-closed paralysis). The bypass (`CLAUDE_HOOK_BYPASS=1 CLAUDE_HOOK_BYPASS_REASON=…`) is the escape hatch, documented in README.
- **If this leaks, the user's data/workflow is exposed via:** no new exposure surface — this PR changes a default, not a logging path. The pre-existing `approvals.jsonl` argv-secret caveat (doppler prod-secret `set NAME=<value>` captures the value verbatim) is unchanged by this PR and already documented (README:290–303). Enforce mode now *writes* `approvals.jsonl` rows on every prod-write (dormant in dry-run), so the argv-secret caveat becomes live — but the file is `.gitignore`d and the caveat already covers the share-into-tracker surface.
- **Brand-survival threshold:** single-user incident. (A broken defer gate either blocks all of the operator's prod-writes or — if the failure inverts — allows an un-approved prod-write the operator wanted gated. Both are single-operator-blast-radius but brand-defining for a tool whose pitch is deterministic prod-write safety.) → `requires_cpo_signoff: true`.

CPO sign-off required at plan time before `/work`. CPO was a brainstorm-time leader for the parent #3789 effort (PR #3787 carries `brand_survival_threshold: single-user incident`); this PR is the pre-agreed enforce-flip of that same control, not a new approach — confirm CPO has acked the flip or invoke CPO if not covered. `user-impact-reviewer` will run at review time per `review/SKILL.md` conditional-agent block.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — the flip.** `.claude/hooks/prod-write-defer-gate.sh:35` reads `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-0}"`. Verify: `grep -n ':-0}' .claude/hooks/prod-write-defer-gate.sh` returns line 35; `grep -c ':-1}' .claude/hooks/prod-write-defer-gate.sh` returns 0.
- [x] **AC2 — comment synced.** `.claude/hooks/prod-write-defer-gate.sh:15` says `default 0` not `default 1`. Verify: `grep -n 'default 0' .claude/hooks/prod-write-defer-gate.sh` matches the Mode comment.
- [x] **AC3 — default-when-unset behavior is enforce.** Add a unit-test case (Tier D) that runs the hook with **no** `SOLEUR_DEFER_DRYRUN` set against `terraform apply` and asserts `permissionDecision=defer` + `kind=defer_requested`. This is the one behavior the existing suite does NOT cover (all current tests pin the env var). Verify: the new case is named (e.g. `D4 default-unset enforce`) and `bash .claude/hooks/prod-write-defer-gate.test.sh` reports the new total with FAIL=0.
- [x] **AC4 — existing suite still green.** `bash .claude/hooks/prod-write-defer-gate.test.sh` → `FAIL=0` (was 60/60; AC3 raises the total by 1).
- [x] **AC5 — CI Test 6 pinned to dry-run.** `.github/workflows/test-pretooluse-hooks.yml` Test-6 claude-code-action step has `env: SOLEUR_DEFER_DRYRUN: "1"` (or equivalent pin) so it still emits `would_defer`; the `:130` prose is updated to state the default is now 0/enforce and dry-run is pinned for the test. Verify: `grep -n 'SOLEUR_DEFER_DRYRUN' .github/workflows/test-pretooluse-hooks.yml` shows the env pin; `actionlint .github/workflows/test-pretooluse-hooks.yml` passes (workflow file, not composite action).
- [x] **AC6 — README synced.** `.claude/hooks/README.md` Modes section states the default is now `0` (enforce), and `:322–323` is rewritten to past tense crediting PR #3800. Verify: `grep -n 'DEFAULT' .claude/hooks/README.md` no longer claims `SOLEUR_DEFER_DRYRUN=1` is the default.
- [ ] **AC7 — `Closes #3800` in PR body, NOT title; parent #3789 untouched.** Verify: PR body contains `Closes #3800`; PR title has no `#`; `gh issue view 3789 --json state` remains `OPEN` after merge.

### Post-merge (operator)

- [ ] **AC8 — first real enforce on next prod-write.** Automation: not feasible to assert pre-merge (requires a real prod-write in a live session). On the operator's next gated command, confirm the session pauses and `claude --resume <id>` resumes it; confirm one row appended to `.claude/logs/approvals.jsonl`. Verify (read-only): `tail -1 .claude/logs/approvals.jsonl | jq .` shows the row.

## Implementation Phases

### Phase 1 — RED: pin the new default behavior
1. Add Tier-D test case `D4 default-unset enforce` to `.claude/hooks/prod-write-defer-gate.test.sh`: invoke the hook for `terraform apply` with `SOLEUR_DEFER_DRYRUN` **unset** in the env; assert `permissionDecision=defer`, `hookEventName=PreToolUse`, `kind=defer_requested`. Run the suite — this case FAILS against the current `:-1` default (it would emit `would_defer` / allow). (RED.)

### Phase 2 — GREEN: the flip + comment
2. `.claude/hooks/prod-write-defer-gate.sh:35` — `:-1}` → `:-0}`.
3. `.claude/hooks/prod-write-defer-gate.sh:15` — comment `default 1` → `default 0`.
4. Re-run `bash .claude/hooks/prod-write-defer-gate.test.sh` → all green incl. D4. (GREEN.)

### Phase 3 — consumer-side edits (CI + docs)
5. `.github/workflows/test-pretooluse-hooks.yml` — add `env: SOLEUR_DEFER_DRYRUN: "1"` to the Test-6 claude-code-action step; update the `:130` prose to "dry-run pinned for this test; the hardcoded default is now 0 (enforce)". Keep the `:186` `would_defer` assertion (now correct because the env pin restores dry-run for the test). Run `actionlint` on the file.
6. `.claude/hooks/README.md` — Modes section: mark `SOLEUR_DEFER_DRYRUN=0` as the new DEFAULT; `:322–323` to past tense.

### Phase 4 — verify + ship
7. Run AC1–AC6 verification commands; capture output.
8. Ship per `/soleur:ship`; PR body uses `Closes #3800` (NOT in title); body notes parent #3789 stays open; body lists the heredoc-body false-positive follow-up (below).

## Files to Edit

- `.claude/hooks/prod-write-defer-gate.sh` — line 35 (the flip) + line 15 (comment). **The load-bearing change.**
- `.claude/hooks/prod-write-defer-gate.test.sh` — add `D4 default-unset enforce` (AC3, RED-first).
- `.github/workflows/test-pretooluse-hooks.yml` — pin `SOLEUR_DEFER_DRYRUN=1` for Test 6 + prose at `:130` (AC5; prevents false-FAIL/`::warning::` on the live-runtime test).
- `.claude/hooks/README.md` — Modes section (`:248–252`) + enforce-flip note (`:322–323`) to reflect the now-shipped flip (AC6).

## Files to Create

- None.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` queried; no open code-review issue references `prod-write-defer-gate.sh`, `test-pretooluse-hooks.yml`, or `SOLEUR_DEFER_DRYRUN`. **None.**

## Deferred / Follow-Up (tracked, not in scope)

- **Heredoc-body false-positive on `terraform-apply` (and doppler rules):** in enforce mode the operator will be paused on `gh issue create --body "$(cat <<EOF … EOF)"` and `cat > runbook.md <<EOF` because the regex matches the literal verb-phrase inside the heredoc body. The leading anchor `(^|&&|\|\||;|\(|[[:space:]]--[[:space:]])` treats a heredoc-internal newline + leading whitespace as a match boundary. **File a follow-up issue** (label `type/chore`, `domain/engineering`): "prod-write-defer-gate: heredoc/issue-body false-match on prod-write verb-phrases — scope the regex to exclude matches inside a `<<EOF … EOF` body or a `gh issue/pr` `--body`." Re-evaluation: after the flip, if enforce-mode `defer_requested` telemetry shows the operator repeatedly bypassing on doc-write commands. Milestone: Phase 4 (Validate + Scale) per `roadmap.md`. Explicitly **out of scope for #3800** (issue says "no new manifest regexes").

## Domain Review

**Domains relevant:** Engineering (CTO). Product/CPO sign-off carried from parent #3789 brainstorm (single-user-incident threshold).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Single-line default flip on an already-implemented, already-tested hook. No new code paths. The only non-obvious blast radius is the CI live-runtime test (`test-pretooluse-hooks.yml` Test 6) which relies on the default value rather than pinning it — handled by AC5. Fail-closed posture preserved (`set -uo pipefail`, `*)` arm denies on invalid value). The flip moves the hook from "observe" to "enforce" on three deterministic prod-write rules whose telemetry shows real operator demand and zero phantom-rule noise. No infra provisioned, no schema touched, no secret created.

### Product/UX Gate

**Tier:** none (no user-facing surface — operator-only CLI hook behavior). Product threshold (`single-user incident`) drives the CPO sign-off requirement in `## User-Brand Impact`, not a UX wireframe gate.
**Decision:** auto-accepted (pipeline) — orchestration/tooling change, no new UI.

## Infrastructure (IaC)

Skipped — no new infrastructure. This PR edits `.claude/hooks/*.sh`, `.claude/hooks/README.md`, and a `.github/workflows/*.yml` test workflow. No server, secret, vendor, DNS, cron, or persistent runtime process is introduced. The hook *defers* `terraform apply` / doppler prod-secret writes for operator approval, but provisions nothing itself. Phase 2.8 reviewed; the `iac-routing-ack` comment in the frontmatter documents the opt-out (the gate matched a quoted command-string in the plan body, not a provisioning step).

## Observability

```yaml
liveness_signal:
  what: "kind=defer_requested rows in .claude/.rule-incidents.jsonl + rows in .claude/logs/approvals.jsonl"
  cadence: "on every matched prod-write command (event-driven, not periodic)"
  alert_target: "none (operator-local; the operator observes the in-session pause + stderr resume hint directly)"
  configured_in: ".claude/hooks/prod-write-defer-gate.sh (emit_incident + append_approval_log in the SOLEUR_DEFER_DRYRUN=0 case arm)"
error_reporting:
  destination: "fail-closed self-fault path: emit_incident kind=hook_self_fault + permissionDecision=deny (deny_self_fault); operator sees the deny reason in-session"
  fail_loud: true
failure_modes:
  - mode: "invalid SOLEUR_DEFER_DRYRUN value (mistyped flip)"
    detection: "case *) arm -> deny_self_fault"
    alert_route: "kind=hook_self_fault in .rule-incidents.jsonl + in-session deny message"
  - mode: "regex compile failure"
    detection: "[[ =~ ]] rc>=2 -> deny_self_fault"
    alert_route: "kind=hook_self_fault + deny"
  - mode: "bypass without reason"
    detection: "CLAUDE_HOOK_BYPASS=1 && empty REASON -> deny_self_fault"
    alert_route: "kind=hook_self_fault + deny"
  - mode: "CI Test 6 silently enforce-mode (regression of AC5)"
    detection: "Test 6 agent summary FAIL + line-186 warning: missing would_defer"
    alert_route: "GitHub Actions run annotation on test-pretooluse-hooks.yml"
logs:
  where: ".claude/.rule-incidents.jsonl (telemetry, gitignored) + .claude/logs/approvals.jsonl (audit, gitignored, 1-year TTL via rotate_if_needed)"
  retention: "approvals.jsonl: 365 days; rule-incidents.jsonl: per weekly-aggregator cadence"
discoverability_test:
  command: "echo '{\"tool_input\":{\"command\":\"terraform apply\"},\"session_id\":\"t\"}' | .claude/hooks/prod-write-defer-gate.sh | jq -r '.hookSpecificOutput.permissionDecision'"
  expected_output: "defer  (with the flip applied and SOLEUR_DEFER_DRYRUN unset)"
```

## Test Scenarios

- Existing unit suite (`prod-write-defer-gate.test.sh`, bash `.test.sh` convention — NOT bats; `command -v bats` not required): Tier A (canonical match, dry-run), Tier B (anchor/wrap variants), Tier C (nomatch / read-only escapes), Tier D (enforce envelope), Tier E (bypass allow), Tier F (bypass fail-closed), Tier G (broken regex fail-closed), Tier H (approvals row). 60 cases, all PASS pre-flip.
- New: Tier D4 — default-unset → enforce (AC3).
- CI: `test-pretooluse-hooks.yml` Test 6 (live claude-code-action runtime) with dry-run pinned (AC5).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled above.)
- **The flip's failure mode is asymmetric and must be tested at the default-unset path.** Every existing test pins `SOLEUR_DEFER_DRYRUN` explicitly, so a flip that *silently no-ops* (e.g., a later edit reverting `:-0` back to `:-1`) would pass all 60 existing tests. AC3 (D4) is the only guard against a silent revert — keep it.
- **`test-pretooluse-hooks.yml` is the only consumer that depends on the default value rather than pinning it.** A grep for `SOLEUR_DEFER_DRYRUN` consumers returns only the hook + its unit test; the CI workflow's dependency is implicit (it never exports the var and asserts `would_defer`). This implicit dependency is exactly the kind a one-line flip silently breaks — AC5 makes it explicit.
- **Enforce mode activates the dormant argv-secret write path.** `append_approval_log` now runs on every prod-write; a doppler prod-secret `set NAME=<value>` writes the value verbatim into `approvals.jsonl resolved_command`. Pre-existing, documented (README:290–303), `.gitignore`d, out of scope (F1 redaction deferred to roadmap) — reviewers should not flag it as newly-introduced.
- **The plan body itself triggers the IaC-routing PreToolUse hook** because it quotes prod-write verb-phrases the F2 gate matches — the same false-positive class this very PR's follow-up tracks. Opted out via the reviewed `iac-routing-ack` comment in frontmatter. Do not strip that comment.
