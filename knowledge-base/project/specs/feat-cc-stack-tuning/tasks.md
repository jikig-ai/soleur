---
title: Tasks — Deterministic permissions (F1+F2 umbrella)
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-feat-deterministic-permissions-plan.md
spec: knowledge-base/project/specs/feat-cc-stack-tuning/spec.md
issue: 3789
prereq_issue: 3799
followup_issue: 3800
branch: feat-cc-stack-tuning
worktree: .worktrees/feat-cc-stack-tuning/
draft_pr: 3787
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
---

# Tasks — Deterministic permissions

## Prerequisite (separate PR, ship FIRST)

- [ ] **0.0** Open PR for #3799 — extend `scripts/test-all.sh:46-49` discovery loop to also glob `.claude/hooks/*.test.sh`. Run `bash scripts/test-all.sh` from prereq branch. Fix or quarantine any newly-surfaced failing hook test. Merge. **THIS PLAN'S WORK DOES NOT BEGIN UNTIL #3799 MERGES.**

## Phase 0 — Empirical probes (BLOCKING)

- [ ] **0.1** Capture `PermissionDenied` event payload via `CLAUDE_CONFIG_DIR=/tmp/cc-probe-perm-denied claude -p ...` with synthesized stub `settings.json`. Trigger a known-blocked op (agent attempts `git commit` on main). Inspect captured `/tmp/perm-denied-payload.json`. Date-stamp shape into `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` with `claude --version` header.
  - **BLOCKING gate:** if event does not fire OR payload lacks `tool_name`/`tool_input`/`reason`, F1 collapses to roadmap entry; this PR proceeds with F2-only and Phase 1 tasks are deleted.
- [ ] **0.2** Capture `permissionDecision: "defer"` acceptance via the same `CLAUDE_CONFIG_DIR=` mechanism. Stub returns wrapped `{hookSpecificOutput: {permissionDecision: "defer", permissionDecisionReason: "test"}}`. Observe whether agent pauses. If `defer` rejected, fall back to `"ask"`. Date-stamp into `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md`. The `DEFER_VALUE` constant in Phase 2's hook is set from this artifact.

## Phase 1 — F1: incidents.sh extension + PermissionDenied hook

- [ ] **1.1** Audit `emit_incident` callers: `git grep -nE 'emit_incident\s+' .claude/hooks/ plugins/soleur/skills/ scripts/`. Confirm: 17 max callers; no caller passes >5 positionals; slot 5 (`hook_event`) semantics preserved. Capture audit output for PR body.
- [ ] **1.2** RED: extend `.claude/hooks/incidents.test.sh` — 3-arg call defaults `kind="rule_event"`; 5-arg call preserves `hook_event` slot 5 unchanged; 6-arg call emits `kind` correctly in JSONL.
- [ ] **1.3** GREEN: edit `.claude/hooks/lib/incidents.sh` jq invocation at L220-227 — add `--arg k "${6:-rule_event}"` and `kind:$k` field. Update comment block L185-188 documenting the new positional. **No SCHEMA_VERSION bump.**
- [ ] **1.4** RED: create `.claude/hooks/permission-denied-telemetry.test.sh`. Synthesized fixtures (`TEST-FIXTURE-NOT-REAL` token). Cover: payload redaction strips `sk_*`, `Bearer *`, `eyJ*`, `postgres://*:*@*`, `AKIA*`, `ASIA*`, `dp.st.*`; emit_incident receives 6 args with `kind="permission_denied"`; fail-open on jq crash.
- [ ] **1.5** GREEN: create `.claude/hooks/permission-denied-telemetry.sh`. Pattern from `guardrails.sh:30-38` (single jq @sh-escaped eval). Apply redaction function. Call `emit_incident "permission-denied" "denied" "<prefix>" "<cmd_redacted>" "PermissionDenied" "permission_denied"`. Trap → exit 0 (fail open; telemetry never blocks work).
- [ ] **1.6** Wire `"PermissionDenied"` as new top-level event in `.claude/settings.json` (sibling to PreToolUse/PostToolUse). Empty matcher.
- [ ] **1.7** Smoke probe in fresh CC session: trigger a known kernel denial; confirm `.claude/.rule-incidents.jsonl` entry with `kind: "permission_denied"`.

## Phase 2 — F2: prod-write defer gate

- [ ] **2.1** RED: create `.claude/hooks/prod-write-defer-gate.test.sh`. Synthesized fixtures. Cover per starter regex:
  - **2.1.1** canonical form matches
  - **2.1.2** wrapped form `bash session-state.sh with_lock ... -- <cmd>` matches
  - **2.1.3** env-prefixed `env DOPPLER_CONFIG=prd_terraform <cmd>` matches
  - **2.1.4** short-flag `git push -f origin main` matches push-to-main
  - **2.1.5** refspec `git push origin HEAD:main` matches push-to-main
  - **2.1.6** adjacent non-match `git push origin feat-main-update` does NOT match
  - **2.1.7** `--config prd_terraform` matches doppler-prd; `--config prd-staging` does NOT (anchor `(prd|prd_terraform)([[:space:]]|$)`)
  - **2.1.8** dry-run mode: emits `would_defer`, returns `allow`
  - **2.1.9** enforce mode: emits `defer_requested`, returns wrapped JSON with `DEFER_VALUE` from Phase 0.2
  - **2.1.10** bypass with TTY + env reason + operator: emits `bypass`, returns `allow`
  - **2.1.11** non-TTY bypass without env reason+operator: fails CLOSED (`deny` + `kind: "hook_self_fault"`)
  - **2.1.12** synthesized broken regex (test fixture only): fails CLOSED
- [ ] **2.2** GREEN: create `.claude/hooks/prod-write-defer-gate.sh`:
  - `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"` hardcoded default
  - `DEFER_VALUE="defer"` (or `"ask"` per Phase 0.2 artifact)
  - Inline `TARGETS` bash array, 3 entries (POSIX `[[:space:]]`, NOT `\s`)
  - Single jq @sh-escaped stdin parse
  - Inline `resolve_operator_email()`: SOLEUR_OPERATOR_EMAIL > GITHUB_ACTOR > `git config --global` > `unknown@local` (prefer `--global` per bare-repo trap learning)
  - Decision tree per plan §Decision Tree
- [ ] **2.3** Wire `prod-write-defer-gate.sh` in `.claude/settings.json` PreToolUse(Bash) at position 4 (AFTER `ship-unpushed-commits-gate.sh`).
- [ ] **2.4** Inline `append_approval_log()` function: flock-protected; calls `rotate_if_needed .claude/logs/approvals.jsonl 1y`. Schema includes `approval_method ∈ {tty_resume, env_override, ci_actor}` (NO `bypass` — bypass writes `kind: "bypass"` to rule-incidents instead).
- [ ] **2.5** Smoke probe in fresh CC session: synthesized matching fixture confirms `kind: "would_defer"` entry; non-matching command produces no defer event.

## Phase 3 — Documentation + acceptance

- [ ] **3.1** Add `.claude/logs/` to `.gitignore`.
- [ ] **3.2** Update `.claude/hooks/README.md` — 4 sections per plan §3.2:
  - F1 PermissionDenied event hook (cite PERMISSION-DENIED-PAYLOAD-SHAPE.md + F1↔F2 disjoint capture explainer)
  - F2 prod-write defer gate (env vars, bypass policy, approval log, defer-vs-ask citation, 3-entry starter manifest, how-to-add-entries via telemetry-driven follow-up PRs)
  - Audit-trail review cadence (weekly jq one-liner; enforce-flip gated on operator confirmation)
  - External-observability boundary (out-of-scope; DPA review required for piping)
- [ ] **3.3** Add F2 defer-gate test case to `.github/workflows/test-pretooluse-hooks.yml`. Synthesized fixtures externalized via `--body-file` per learning `2026-03-19-pre-merge-hook-false-positive-on-string-content.md`.

## Phase 4 — PR open + review

- [ ] **4.1** Confirm prereq #3799 has merged.
- [ ] **4.2** Confirm followup #3800 (enforce-flip tracker) is open with re-evaluation gate.
- [ ] **4.3** Run `bash scripts/test-all.sh` from feature branch → exits 0.
- [ ] **4.4** Confirm `test-pretooluse-hooks.yml` CI passes.
- [ ] **4.5** Mark draft PR #3787 ready. PR body uses `Refs #3789` AND `Refs #3800` (NOT `Closes`).
- [ ] **4.6** `user-impact-reviewer` agent activated at PR review per `Brand-survival threshold: single-user incident`.
- [ ] **4.7** Address PR feedback; merge.

## Phase 5 — Post-merge dry-run window (2 weeks)

- [ ] **5.1** Daily/weekly: operator runs `jq -c 'select(.kind == "would_defer") | .rule_id' .claude/.rule-incidents.jsonl | sort | uniq -c | sort -rn`.
- [ ] **5.2** For any rule_id with >10 false-positive hits, file a regex-refinement PR (small, targeted, telemetry-cited).
- [ ] **5.3** Confirm none of the 3 starter rules blocks operator-essential workflows lacking bypass.
- [ ] **5.4** End-to-end test bypass flow (with TTY + env reason+operator); verify `kind: "bypass"` incident emit.

## Phase 6 — Enforce-flip (separate PR via #3800)

- [ ] **6.1** Re-evaluation gate per #3800 (all 5 conditions met).
- [ ] **6.2** Open PR: single-line change `${SOLEUR_DEFER_DRYRUN:-1}` → `${SOLEUR_DEFER_DRYRUN:-0}` in `.claude/hooks/prod-write-defer-gate.sh`.
- [ ] **6.3** Merge. `Closes #3800` AND `Closes #3789` (both close once enforce ships).

## Hard gates

- **BLOCKING — Phase 0.1**: F1 viability gate. If `PermissionDenied` event doesn't fire, F1 collapsed and Phase 1 tasks deleted before /work continues.
- **BLOCKING — prereq #3799**: this plan does not begin Phase 0 until #3799 is merged.
- **BLOCKING — followup #3800**: this plan does not merge until #3800 is open.
- **BLOCKING — `user-impact-reviewer`**: PR review approval required.
