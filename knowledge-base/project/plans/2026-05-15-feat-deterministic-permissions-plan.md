---
title: Deterministic permissions — PermissionDenied telemetry + deferred-permission hook for prod-writes (dry-run default)
date: 2026-05-15
type: feat
issue: 3789
brainstorm: knowledge-base/project/brainstorms/2026-05-15-cc-stack-tuning-brainstorm.md
spec: knowledge-base/project/specs/feat-cc-stack-tuning/spec.md
branch: feat-cc-stack-tuning
worktree: .worktrees/feat-cc-stack-tuning/
draft_pr: 3787
deferred_children: [3790, 3791, 3792, 3793]
prereq_issue: 3799
followup_issue: 3800
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
detail_level: MORE
review_pass: applied — DHH+Kieran+Simplicity converged cuts + P0 correctness fixes
---

# Plan — Deterministic permissions (F1 + F2, dry-run default)

## Overview

Two coupled hooks shipped in one PR with F2 in dry-run mode by default.

**F1** extends `.claude/hooks/lib/incidents.sh` `emit_incident()` with a 6th optional positional `kind` (default `"rule_event"`, back-compat with 17 existing 3-4-arg callers; verified safe against the 5-arg `hook_event` slot). Adds a new top-level `PermissionDenied` event hook in `.claude/settings.json` that captures kernel-decided denials and emits to `.claude/.rule-incidents.jsonl` with `kind: "permission_denied"`. **No `SCHEMA_VERSION` bump** — the `kind` field is additive optional; v1 readers ignore unknown fields. If a downstream reader later breaks on the new shape, bump in a follow-up PR.

**F2** adds a new PreToolUse(Bash) hook `prod-write-defer-gate.sh` at position 4 of the chain. Inline (NOT a separate JSON file) regex array of **3 starter entries**: push-to-main, terraform apply, doppler prd secrets. In dry-run (`SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"` hardcoded default) emits `kind: "would_defer"` and allows; in enforce mode emits `kind: "defer_requested"` and returns the wrapped `permissionDecision` JSON envelope. Agent pauses; operator approves in-terminal via `claude --resume <session_id>`; the approval is recorded to `.claude/logs/approvals.jsonl` (gitignored, 1-year TTL). Bypass via `CLAUDE_HOOK_BYPASS=1` writes `kind: "bypass"` with operator+reason; non-TTY without explicit env reason+operator fails CLOSED.

This is internal developer infrastructure. The "user" is the Soleur operator. Brand-survival threshold is `single-user incident` because the gate governs prod-write surfaces (terraform/doppler-prd/supabase-prod/gh-release) that downstream affect customer data.

## Adjacent prerequisite PR (filed separately, NOT this PR)

`scripts/test-all.sh:46-49` currently only globs `plugins/soleur/test/*.test.sh` — **12 existing `.claude/hooks/*.test.sh` tests have never been in CI**. Folding that fix into this PR was rejected on review (Kieran P1 #7: discovery may surface broken tests that block this PR's merge). Ship as a one-line prereq PR FIRST:

- File: `scripts/test-all.sh`
- Change: extend the discovery loop to also glob `.claude/hooks/*.test.sh`
- Definition of done: `bash scripts/test-all.sh` exits 0 from main; any newly-surfaced failing hook test either fixed in that PR or explicitly quarantined with a tracking issue
- Tracking: file as issue + PR before /work begins on this plan

This plan's ACs assume the prereq PR has merged. **Tracking: #3799.**

## Adjacent follow-up issue (filed BEFORE this PR merges)

Phase 6.4 enforce-flip is a tiny follow-up PR (single-line default change). Kieran P1 #8: if THIS PR uses `Closes #3789`, the umbrella issue auto-closes on merge and the enforce-flip has no tracking surface. Fix: file a new issue "F2 enforce-flip (flip `SOLEUR_DEFER_DRYRUN` default to 0 after 2-week telemetry review)" BEFORE merging this PR. This PR's body uses `Refs #3789` (NOT `Closes`) — `#3789` stays open until enforce-flip ships. **Tracking: #3800.**

## Research Reconciliation — Spec vs. Codebase

5 spec corrections from repo-research that must land before implementation:

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1.4: `denied.jsonl` needs `.gitleaks.toml` allowlist | Gitleaks scans the git **index**; gitignored files never enter the index. | Drop gitleaks paragraph. `.gitignore` alone covers it. |
| FR2.3: `SOLEUR_DEFER_DRYRUN=1` set in `.env.defaults` | `.env.defaults` does not exist; convention is inline `${VAR:-default}`. | Hardcode `${SOLEUR_DEFER_DRYRUN:-1}` at top of hook script. |
| FR2.8/TR5: `bats` test framework | `bats` is NOT installed. Convention is `.claude/hooks/*.test.sh` shell scripts (12 existing). | Use `.test.sh` shell convention verbatim. |
| TR6: new `.github/workflows/test-defer-gate.yml` | Existing `test-pretooluse-hooks.yml` is the canonical PreToolUse-hook test harness. | Add F2 test case to existing workflow. |
| Implicit: `scripts/test-all.sh` discovers `.claude/hooks/*.test.sh` | It does NOT — see "Adjacent prerequisite PR" above. | Prereq PR fixes this BEFORE this plan ships. |

**Critical functional-discovery finding:** `PermissionDenied` event fires only in auto mode and does NOT fire when a PreToolUse hook blocks. F1 and F2 capture DISJOINT event sets — F1 catches kernel-decided denials; F2 returns its own decision before kernel evaluation. Both are needed for complete coverage.

**Critical learnings-researcher finding:** Soleur's canonical hook JSON envelope (per `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`) is `{hookSpecificOutput: {permissionDecision: "...", permissionDecisionReason: "..."}}`. The article's bare `{permissionDecision: "defer", reason: "..."}` is simplified — F2 emits the wrapped form. Phase 0.2 empirically decides whether `"defer"` is accepted as a value in current CC OR fall back to `"ask"`.

## User-Brand Impact

**If this lands broken, the user experiences:** an over-broad `defer` regex blocking legitimate `git push origin feat-foo` and paralyzing ship; OR a missed prod-write path (e.g., `wrangler secret put` against prod) silently slipping past — but only after `wrangler` is added to the manifest in a future telemetry-driven PR (v1 ships 3 entries, NOT 11; wrangler not in v1).

**If this leaks, the operator's workflow audit is exposed via:** `.claude/logs/approvals.jsonl` accidentally committed to a branch with operator-email PII, OR redacted-but-not-redacted-enough secret patterns in `command_snippet`, OR operator identity leaked to a future external observability vendor without DPA review (out of scope per CLO carry-forward — README documents the boundary).

**Brand-survival threshold:** `single-user incident`. `user-impact-reviewer` activation required at PR review. `requires_cpo_signoff: true`.

CPO sign-off: covered by 2026-05-15 brainstorm carry-forward — ship-now (T2 Secure-Before-Beta + T4 Validate); pivot-risk check passed.

## Compliance / GDPR Evaluation (inline gate)

Canonical regex (`hr-gdpr-gate-on-regulated-data-surfaces`) does NOT match — pure hook infrastructure. Trigger (b) "single-user incident threshold" DOES fire. Inline evaluation (CLO carry-forward + supplementary):

- `.claude/.rule-incidents.jsonl`: existing sink + new `kind` discriminator. Operator-machine-local; not committed.
- `.claude/logs/denied.jsonl`: NEW sink (F1 telemetry). Gitignored. 30-day TTL via `rotate_if_needed`.
- `.claude/logs/approvals.jsonl`: NEW sink (F2 audit). Gitignored. 1-year TTL.

Operator email = operator's own data. Operator is controller AND data subject. No third-party data subject content flows. No DPA changes. CLO required separating `approvals.jsonl` from `.rule-incidents.jsonl` because the rule-incidents stream is consumed by aggregators that report rule fire counts — operator-email PII in that stream would leak into aggregator outputs. Maintained as separate sinks (rejected the 3-sinks-to-1 simplification on this basis).

External-observability boundary: out-of-scope. README documents that piping these logs to Sentry/Datadog/Plausible requires DPA review.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance, Operations (carry-forward from brainstorm).

### Engineering (CTO)
**Status:** reviewed (carry-forward). Ship F1+F2 with dry-run scaffold; treat existing `wg-ship-push-before-merge` as belt-and-suspenders for at least one release after enforce-flip.

### Product (CPO)
**Status:** reviewed (carry-forward; sign-off recorded). T2 + T4 alignment. Pivot-risk OK.

### Legal (CLO)
**Status:** reviewed (carry-forward). Ship with gitignore + redaction + retention (30d denied / 1y approvals). `user-impact-reviewer` required at PR.

### Finance (CFO)
**Status:** reviewed (carry-forward). Cost-neutral.

### Operations (COO)
**Status:** reviewed (carry-forward). Bypass mechanism with no silent overrides. Healthy defer baseline 3-10/week.

### Product/UX Gate
**Tier:** none — internal infra; no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`. Spec-flow-analyzer was invoked separately and surfaced 8 gaps (4 folded in, 4 rejected via simplification cuts).

**Brainstorm-recommended specialists:** `user-impact-reviewer` activates at PR review.

## Files to Edit

| File | Change |
|---|---|
| `.claude/hooks/lib/incidents.sh` (L189-248) | Extend `emit_incident()` with 6th optional positional `kind` (default `"rule_event"`). Add `--arg k "${kind:-rule_event}"` + `kind:$k` field to jq object at L220-227. **No SCHEMA_VERSION bump.** |
| `.claude/hooks/incidents.test.sh` | Add test cases: 5-arg legacy preserves `hook_event` slot 5 semantics; 6-arg new emits `kind` correctly; default `kind: "rule_event"` for 3-arg calls. |
| `.claude/settings.json` | Add top-level `"PermissionDenied"` event → `permission-denied-telemetry.sh`. Insert `prod-write-defer-gate.sh` at PreToolUse(Bash) position 4. |
| `.gitignore` | Add `.claude/logs/`. |
| `.github/workflows/test-pretooluse-hooks.yml` | Add F2 defer-gate test case (synthesized fixtures, externalized via `--body-file`). |
| `.claude/hooks/README.md` | 4 new sections: F1 hook, F2 hook + env vars + bypass policy, audit-trail review cadence, external-observability boundary. |

## Files to Create

| File | Purpose |
|---|---|
| `.claude/hooks/permission-denied-telemetry.sh` | F1: redact payload, call `emit_incident` with `kind="permission_denied"`. Fails OPEN. |
| `.claude/hooks/permission-denied-telemetry.test.sh` | F1 tests. |
| `.claude/hooks/prod-write-defer-gate.sh` | F2: inline 3-entry regex array. Dry-run default. Bypass. Approvals log writer. Fails CLOSED. |
| `.claude/hooks/prod-write-defer-gate.test.sh` | F2 tests. |
| `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` | Phase 0.1 dated empirical capture artifact. |
| `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` | Phase 0.2 dated artifact: defer-vs-ask outcome. |

**Cut from prior draft:** `lib/operator-identity.sh` (inline 4-line resolver in F2 hook instead — no second consumer yet), `lib/prod-write-targets.json` (3 inline regexes in bash array), `operator-identity.test.sh` (covered by F2 test).

## Open Code-Review Overlap

None (Phase 1.7.5: 78 open `code-review`-labeled issues grepped against 6 distinct file paths; zero overlap).

## Implementation Phases

### Phase 0 — Empirical probe (BLOCKING)

Two artifacts to capture before writing production code. Both verify hook input/output shape against the installed CC version (per learning `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`).

- **0.1 PermissionDenied event payload capture.** Mechanism: `CLAUDE_CONFIG_DIR=/tmp/cc-probe claude -p ...` with a synthesized `settings.json` containing only a stub PermissionDenied hook that writes stdin to `/tmp/perm-denied-payload.json`. Trigger a known-blocked op (e.g., agent attempts `git commit` on main). Inspect captured payload. Date-stamp the JSON shape into `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` with `claude --version`. **BLOCKING gate:** if `PermissionDenied` event does not fire OR payload lacks tool_name/tool_input/reason fields, F1 collapses to roadmap entry; this PR proceeds with F2-only.
- **0.2 `permissionDecision: "defer"` value verification.** Same `CLAUDE_CONFIG_DIR=` mechanism. Stub PreToolUse(Bash) hook returns wrapped `defer` for a benign synthesized command. Run `claude -p`. Observe: agent pauses → `defer` accepted. Alternative: CC rejects → fall back to `"ask"`. Date-stamp result in `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md`. The hook's emitted decision string in Phase 2 is driven by this artifact.

(Cut from prior draft: Phase 0.3/0.4 inlined as 10-second steps within Phase 1 — `ls .gitignore`, confirm test-all.sh prereq PR has merged.)

### Phase 1 — F1: incidents.sh extension + PermissionDenied hook

- **1.1** Read `.claude/hooks/lib/incidents.sh` L189-248 + L36-53. Audit emit_incident callers: `git grep -nE 'emit_incident\s+' .claude/hooks/ plugins/soleur/skills/ scripts/`. Confirm: **no caller passes >5 args** (slot 5 = `hook_event`). Audit is itself an AC item.
- **1.2** RED: extend `incidents.test.sh` — 3-arg call defaults `kind="rule_event"`; 5-arg call preserves `hook_event` slot 5 unchanged; 6-arg call emits `kind` correctly. Tests fail.
- **1.3** GREEN: edit `lib/incidents.sh` jq at L220-227. Add `--arg k "${6:-rule_event}"` (use positional `${6:-}` directly OR add `local kind="${6:-rule_event}"` at function top — pick whichever matches existing local-var style). Add `kind:$k` field. Update comment block L185-188.
- **1.4** RED: create `permission-denied-telemetry.test.sh`. Synthesized fixtures (`TEST-FIXTURE-NOT-REAL` token). Cover: payload redaction strips `sk_*`, `Bearer *`, `eyJ*`, `postgres://*:*@*`, `AKIA*`, `ASIA*`, `dp\.st\.*`; emit_incident receives 6 args with kind=permission_denied; fail-open on jq crash.
- **1.5** GREEN: create `.claude/hooks/permission-denied-telemetry.sh`. Pattern from `guardrails.sh:30-38` (single jq @sh-escaped eval). Apply redaction function. Call `emit_incident "permission-denied" "denied" "<prefix>" "<cmd_redacted>" "PermissionDenied" "permission_denied"`. Fail-open: trap → exit 0.
- **1.6** Wire `"PermissionDenied"` as new top-level event in `.claude/settings.json` (sibling to PreToolUse/PostToolUse). Empty matcher (catch all).
- **1.7** Smoke probe: trigger a known kernel denial; confirm `.rule-incidents.jsonl` shows entry with `kind: "permission_denied"`.

### Phase 2 — F2: prod-write defer gate

- **2.1** RED: create `prod-write-defer-gate.test.sh`. Synthesized fixtures. Cover for each of 3 starter regexes:
  - canonical form matches
  - wrapped form `bash session-state.sh with_lock ... -- <cmd>` matches (anchor `(^|&&|\|\||;|[[:space:]]--[[:space:]])`)
  - env-prefixed `env DOPPLER_CONFIG=prd_terraform <cmd>` matches
  - **short-flag form** `git push -f origin main` matches push-to-main regex
  - **refspec form** `git push origin HEAD:main` matches push-to-main regex
  - adjacent non-match: `git push origin feat-main-update` does NOT match
  - adjacent non-match: `git push origin feat-foo` does NOT match
  - `--config prd_terraform` matches doppler-prd; `--config prd-staging` (synthesized) does NOT (anchor with `(prd|prd_terraform)([[:space:]]|$)`)
  - **dry-run mode:** emits `would_defer`, returns `allow`
  - **enforce mode:** emits `defer_requested`, returns wrapped `{hookSpecificOutput: {permissionDecision: <0.2-decided-value>, permissionDecisionReason: "<rule_id>: ..."}}`
  - **bypass:** with TTY + `CLAUDE_HOOK_BYPASS=1` + interactive reason prompt → emits `bypass`, returns `allow`
  - **non-TTY bypass without env reason+operator:** fails CLOSED (`deny` + `kind: "hook_self_fault"`)
  - **broken regex (synthesized):** fails CLOSED
- **2.2** GREEN: create `.claude/hooks/prod-write-defer-gate.sh`. Structure:
  ```bash
  #!/usr/bin/env bash
  # Inline regex array (3 starter entries, expand via dry-run telemetry).
  # Regex engine: bash [[ =~ ]] (ERE) — uses POSIX [[:space:]], NOT \s.
  set -euo pipefail
  source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

  SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"
  # Decision value from Phase 0.2 empirical artifact (defer or ask):
  DEFER_VALUE="defer"  # update to "ask" if Phase 0.2 outcome flips

  # Pattern array: rule_id|prose_ref|regex (engine=ERE)
  TARGETS=(
    "prod-write-defer-git-push-main|hr-menu-option-ack-not-prod-write-auth|(^|&&|\|\||;|[[:space:]]--[[:space:]])[[:space:]]*git[[:space:]]+push([[:space:]]+(-f|--force(-with-lease)?))?[[:space:]]+origin[[:space:]]+(main|master|HEAD:main|HEAD:master)([[:space:]]|$)"
    "prod-write-defer-terraform-apply|hr-all-infrastructure-provisioning-servers|(^|&&|\|\||;|[[:space:]]--[[:space:]])[[:space:]]*(terraform|tofu)[[:space:]]+apply([[:space:]]|$)"
    "prod-write-defer-doppler-prd-secrets|hr-menu-option-ack-not-prod-write-auth|(^|&&|\|\||;|[[:space:]]--[[:space:]])[[:space:]]*doppler[[:space:]]+secrets[[:space:]]+set[[:space:]]+.*((--config|-c)[[:space:]]+(prd|prd_terraform)([[:space:]]|$))"
  )

  # ... (stdin parse, match loop, mode branch, emit, return JSON)
  ```
  Operator-email resolution inline (4-line):
  ```bash
  resolve_operator_email() {
    if [[ -n "${SOLEUR_OPERATOR_EMAIL:-}" ]]; then echo "$SOLEUR_OPERATOR_EMAIL"
    elif [[ -n "${GITHUB_ACTOR:-}" ]]; then echo "${GITHUB_ACTOR}@users.noreply.github.com"
    elif email=$(git config --global --get user.email 2>/dev/null); then echo "$email"
    else echo "unknown@local"; fi
  }
  ```
  Per learning `2026-04-24-fake-git-author-bare-repo-bot-override.md`, prefer `--global` over default git config (which silently reads repo-level in bare-repo+worktree topology).
- **2.3** Wire `prod-write-defer-gate.sh` in `.claude/settings.json` PreToolUse(Bash) at position 4 (AFTER `ship-unpushed-commits-gate.sh`).
- **2.4** Approval log writer: inline function `append_approval_log()` in the hook. flock-protected via `rotate_if_needed` against `.claude/logs/approvals.jsonl` (1y TTL). Schema:
  ```json
  {"timestamp":"...","tool":"...","args_hash":"...","resolved_command":"...","operator_email":"...","approval_method":"tty_resume|env_override|ci_actor","rule_id":"...","session_id":"..."}
  ```
  approval_method enum is `{tty_resume, env_override, ci_actor}` — bypass is NOT an approval (it writes `kind: "bypass"` to rule-incidents instead) per Kieran P2 #12.
- **2.5** Smoke probe: synthesized trigger from worktree; confirm zero defer events on a non-matching command; confirm `kind: "would_defer"` on a synthesized matching fixture.

### Phase 3 — Documentation + acceptance

- **3.1** `.gitignore`: add `.claude/logs/`.
- **3.2** `.claude/hooks/README.md` — 4 sections:
  1. **F1 PermissionDenied event hook** — purpose, payload shape (cite PERMISSION-DENIED-PAYLOAD-SHAPE.md), `kind: "permission_denied"` discriminator, fail-open semantic, **F1↔F2 disjoint capture explainer**.
  2. **F2 prod-write defer gate** — env vars (`SOLEUR_DEFER_DRYRUN`, `CLAUDE_HOOK_BYPASS`, `CLAUDE_HOOK_BYPASS_REASON`, `CLAUDE_HOOK_BYPASS_OPERATOR`, `SOLEUR_OPERATOR_EMAIL`), bypass policy (no silent overrides; non-TTY without env-set reason+operator fails CLOSED), approval log location + TTL, defer-vs-ask outcome (cite DEFER-DECISION-PAYLOAD-SHAPE.md), starter 3-entry regex array + how to add entries via telemetry-driven follow-up PRs.
  3. **Audit-trail review cadence** — operator runs `jq -c 'select(.kind == "would_defer") | .rule_id' .claude/.rule-incidents.jsonl | sort | uniq -c | sort -rn` weekly during the 2-week dry-run window. Top-rule-id offenders inform regex refinement. Enforce-flip gated on operator confirmation, NOT automation (`soleur:schedule` cron deferred per CPO).
  4. **External-observability boundary** — `denied.jsonl` and `approvals.jsonl` are local-only; piping to external services requires DPA review.

  **Limitation explicitly stated:** 2-week dry-run window validates OPERATOR'S local manifest hit rate only. CI/scheduled-runs never accumulate telemetry because their `.rule-incidents.jsonl` is ephemeral. Adding `wrangler`, `supabase --linked`, `stripe --live`, `gh release create`, `gh pr merge --admin` regexes is gated on operator-side telemetry showing those patterns in actual workflow.

## Decision Tree (F2 `prod-write-defer-gate.sh`)

```
Read stdin → extract tool_name, command (single jq @sh eval per guardrails.sh:32)
Iterate TARGETS array; first match wins
  ↓ match?
NO  → output {} (no decision, falls through)
YES ↓
  Bypass set (CLAUDE_HOOK_BYPASS=1)?
    ↓ yes
    TTY available AND CLAUDE_HOOK_BYPASS_REASON set AND CLAUDE_HOOK_BYPASS_OPERATOR set?
      → emit_incident kind="bypass" with operator + reason → allow
    Non-TTY AND missing env reason+operator?
      → emit_incident kind="hook_self_fault" → DENY (fail closed)
  ↓ no bypass
  Mode = $SOLEUR_DEFER_DRYRUN:
    "1" (dry-run, default)
      → emit_incident kind="would_defer" rule_id=<matched>
      → output {} (allow)
    "0" (enforce)
      → emit_incident kind="defer_requested"
      → append_approval_log (approval_method=tty_resume pending)
      → print resolved_command + rule_id + session_id + "claude --resume <id>" hint to stderr
      → return {hookSpecificOutput: {permissionDecision: "$DEFER_VALUE", permissionDecisionReason: "<rule_id>"}}
On any unhandled error (regex compile, jq parse, manifest unreadable):
  → emit_incident kind="hook_self_fault" → DENY (fail closed)
```

F1 by contrast FAILS OPEN — trap on any error → exit 0; telemetry never blocks work.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Prereq #3799 merged**: `scripts/test-all.sh` extended to glob `.claude/hooks/*.test.sh`; `bash scripts/test-all.sh` exits 0 from main.
- [ ] PR body uses `Refs #3789` and `Refs #3800` (enforce-flip tracker); NOT `Closes`. #3789 stays open until #3800 ships.
- [ ] Phase 0.1 artifact `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` exists, date-stamped, CC-version-stamped. If event does not fire → F1 collapsed to roadmap entry + spec amendment recorded.
- [ ] Phase 0.2 artifact `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` exists, names the chosen decision value (`defer` or `ask`); `DEFER_VALUE` in `prod-write-defer-gate.sh` matches.
- [ ] **`emit_incident` 5-arg back-compat audit**: `git grep -nE 'emit_incident\s+' .claude/hooks/ plugins/soleur/skills/ scripts/` returns 17 callers max; no caller passes >5 positionals; slot 5 (`hook_event`) semantics preserved in new code. Audit output captured in PR body.
- [ ] **No `SCHEMA_VERSION` bump**. New `kind` field is additive; v1 readers ignore. Document in `.claude/hooks/incidents.test.sh` that a `null kind` predicate falls through correctly.
- [ ] `.claude/hooks/permission-denied-telemetry.sh` + `.test.sh` exist; smoke confirms entry with `kind: "permission_denied"` after a known kernel denial.
- [ ] `.claude/hooks/prod-write-defer-gate.sh` + `.test.sh` exist; `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"` hardcoded default.
- [ ] **All 3 regexes use POSIX `[[:space:]]`, NOT `\s`**. Test fixtures cover: canonical, wrapped (`-- <cmd>`), env-prefixed, short-flag (`git push -f`), refspec (`git push origin HEAD:main`), adjacent non-match (`git push origin feat-main-update`), `--config prd_terraform` AND `--config prd` distinction.
- [ ] approvals.jsonl writer enum = `{tty_resume, env_override, ci_actor}` (no `bypass`). flock-protected. 1-year TTL via `rotate_if_needed`. operator-email resolution inline; bare-repo trap test passes (prefer `--global` over default).
- [ ] `.claude/settings.json` has `PermissionDenied` top-level event + F2 hook at PreToolUse(Bash) position 4.
- [ ] `.gitignore` includes `.claude/logs/`.
- [ ] `.github/workflows/test-pretooluse-hooks.yml` has F2 defer-gate test case (synthesized fixtures externalized via `--body-file`).
- [ ] `.claude/hooks/README.md` 4 sections updated including F1↔F2 disjoint capture explainer + CI-telemetry limitation note.
- [ ] All bash tests pass (`bash scripts/test-all.sh` after prereq PR).
- [ ] `test-pretooluse-hooks.yml` CI passes.
- [ ] `user-impact-reviewer` PR review approves.
- [ ] PR body uses `Refs #3789` and `Closes <enforce-flip-issue>` only if scope includes the flip — which it does NOT for this PR.

### Post-merge (operator, manual)

- [ ] **Manual review cadence** (2 weeks): operator runs the jq one-liner weekly; refines manifest via follow-up PRs for any rule_id with >10 hits + no actual prod-write attempt.
- [ ] **Enforce-flip PR** (~Day 14): single-line change to `prod-write-defer-gate.sh` default `${SOLEUR_DEFER_DRYRUN:-1}` → `${SOLEUR_DEFER_DRYRUN:-0}`. Tracked under followup_issue.

## Test Strategy

- **Unit (`.test.sh`)**: pattern matches `incidents.test.sh:1-50`. Synthesized fixtures with `TEST-FIXTURE-NOT-REAL` token. PASS/FAIL counters; `mktemp -d` per-test root; `source` lib.
- **Integration (`test-pretooluse-hooks.yml`)**: `--max-turns 20`, `ref: main`, externalized fixture via `--body-file` per learning `2026-03-19-pre-merge-hook-false-positive-on-string-content.md`.
- **CI**: `scripts/test-all.sh` (post-prereq-PR) discovers `.claude/hooks/*.test.sh`. Test workflow runs F2 defer-gate test case in PR + main.

## Risks + Sharp Edges (condensed to 4 load-bearing items)

1. **`PermissionDenied` event eligibility (BLOCKING)** — F1 unimplementable if CC doesn't emit. Phase 0.1 gate. If absent, F1 collapses to roadmap entry; PR ships F2-only.
2. **`permissionDecision: "defer"` vs `"ask"` value** — Phase 0.2 empirically decides. `DEFER_VALUE` constant in hook is set from the artifact.
3. **Wrapped-invocation regex coverage from day 1** — per learning `2026-05-12-cross-session-lock-lease-bash-primitives.md` SE1: bash session-state-style `with_lock ... -- gh pr merge` slipped past pre-existing regex. F2 anchors on `(^|&&|\|\||;|[[:space:]]--[[:space:]])` from line 1. Test fixtures cover wrapped + env-prefixed + short-flag + refspec forms.
4. **`.claude/settings.json` is session-immutable** — per learning `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md` Error 2. Existing CC sessions won't pick up settings changes. Phase 0 probes use `CLAUDE_CONFIG_DIR=/tmp/...` child sessions. Post-merge smoke (Phase 6.4 follow-up) runs in a fresh session.

**Secondary considerations (one paragraph each, not full sharp edges):**
- Bare-repo `git config user.email` trap → resolved via `--global` preference in inline operator-email resolver.
- `flock` is inode-bound → existing `lib/incidents.sh` already canonicalizes via `cd -P + pwd -P`; new sinks via `rotate_if_needed` inherit this. PIPE_BUF (4096) not atomic for regular files → `command_snippet` cap stays at 1024 per `incidents.sh:196`.
- CI telemetry limitation: dry-run window only accumulates on operator machines; CI/scheduled-runs have ephemeral incidents. Adding wrangler/supabase/stripe regexes gated on operator-side telemetry.
- Defense relaxation (dry-run is "permissive value" of eventual enforce ceiling): existing `wg-ship-push-before-merge` + `hr-menu-option-ack-not-prod-write-auth` + `hr-dev-prd-distinct-supabase-projects` instruction-tier rules remain belt-and-suspenders through at least one release after enforce-flip.
- GDPR boundary: piping logs to external observability requires DPA review (out of scope; documented in README).
- Approval-log PII: operator emails make `approvals.jsonl` PII-bearing the moment repo accidentally goes public. Reinforces gitignored-local-only design. If accidentally `git add`-ed, operator MUST `git reset HEAD <file>` immediately.

## Hypotheses

n/a (not an SSH/network-outage diagnosis; Phase 1.4 trigger did not fire).

## Open Code-Review Overlap

None.

## Deferred items (carry-forward; no new deferrals from plan)

- #3790 — F3 CI defer-then-resume
- #3791 — F5 Agent model-downshift + plugin policy revision
- #3792 — F6 Path-scoped AGENTS sidecars
- #3793 — F7 Per-skill MCP activation
- Telemetry-driven manifest expansion (wrangler/supabase/stripe/gh-release/etc.) — folded into Phase 5.2 README guidance; not a separate issue (operator files follow-up PRs as patterns surface)

## Implementation time estimate

3 phases × ~half-day each = 1.5-2 engineer-days at human pace. AI pair: ~half-day to bash code + tests; manual verification (Phase 0 probes + smoke) cannot be AI-shortcut.

## Review pass summary

Applied 11 converged cuts (DHH+Simplicity) + 3 P0 correctness fixes (Kieran) + 4 P1 AC additions:
- Phase count: 7 → 3
- Manifest entries: 11 → 3 (telemetry-driven additions)
- Files to create: 8 → 6 (no operator-identity lib, no manifest JSON)
- Sharp edges: 14 → 4 + condensed paragraph
- SCHEMA_VERSION bump: dropped (kind is additive optional)
- Mandatory read delay: dropped
- HEAD-vs-working-tree manifest split: dropped (working-tree only)
- Dedup wrapper: dropped
- Regex engine: POSIX `[[:space:]]` (bash ERE) — was `\s` (engine-undefined)
- Manifest regex defects: short-flag, refspec, prefix-prd, alternation, wrangler-prod — addressed in remaining 3 entries
- Phase 0.1 mechanism: `CLAUDE_CONFIG_DIR=/tmp/...` explicit
- emit_incident 5-arg compat audit: added to ACs
- CI telemetry limitation: stated explicitly
- test-all.sh fold-in: separated to prereq PR
- Closes #3789 → Refs #3789: enforce-flip tracking issue filed before merge

Rejected: 3-sinks-to-1 collapse (CLO blocking — operator-email PII in aggregator stream). Kept: 3 separate sinks (`.rule-incidents.jsonl`, `denied.jsonl`, `approvals.jsonl`) with distinct retention.
