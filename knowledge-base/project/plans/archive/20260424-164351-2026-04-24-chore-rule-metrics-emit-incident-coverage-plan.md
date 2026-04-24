---
title: chore(telemetry) — fix rule-metrics emit_incident coverage
date: 2026-04-24
issue: 2866
branch: feat-one-shot-2866-rule-metrics-emit-incident-coverage
worktree: .worktrees/feat-one-shot-2866-rule-metrics-emit-incident-coverage
brainstorm: knowledge-base/project/brainstorms/2026-04-24-rule-metrics-emit-incident-coverage-brainstorm.md
spec: knowledge-base/project/specs/feat-one-shot-2866-rule-metrics-emit-incident-coverage/spec.md
---

# Plan: rule-metrics emit_incident coverage (hooks + skills)

## Overview

Close the telemetry gap causing every AGENTS.md rule to show `hit_count=0, first_seen=null`. Three silent hooks (`pre-merge-rebase.sh`, `security_reminder_hook.py`, `docs-cli-verification.sh`) need emissions; 8 skill-enforced rules (9 emission points) need a self-report path. Aggregator and rule-prune need small updates so the new `applied`/`warn` event types correctly gate orphan-rule decisions.

Success: after merge + one weekly cron cycle, `scripts/rule-prune.sh --dry-run` output shrinks from ~101 false-positive "unused" rules to only the rules that genuinely have not fired, and `orphan_rule_ids` stays empty. CI enforces the orphan-free invariant by failing the aggregator run when it's violated.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Brainstorm / spec: "10 skill-enforced rules have no self-report path" | `grep -oE '\[skill-enforced: [^]]+\]' AGENTS.md` shows **8 distinct tags**. `hr-ssh-diagnosis-verify-firewall` has a combined tag `[skill-enforced: plan Phase 1.4, deepen-plan Phase 4.5]` (2 emission points, 1 rule). Total: 8 rules, 9 emission points. | Authoritative count: 8 rules, 9 emission points (see Skill Emission Points table below). |
| Brainstorm: "aggregator counts `hit_count = deny + bypass + applied + warn`" | `rule-metrics-aggregate.sh:112` currently increments `hit_count` ONLY on `event_type == "deny"`. Bypasses already go to `bypass_count`, not `hit_count`. Changing `hit_count` would break `prevented_errors = max(hit_count - bypass_count, 0)` at `:153`. | Introduce new `fire_count` field = sum of all event types per rule. `hit_count` and `bypass_count` semantics unchanged. `rule-prune.sh:51` and aggregator summary `rules_unused_over_8w` predicate at `:184` switch from `hit_count == 0` to `fire_count == 0`. |
| Brainstorm: "`event_type` enum extension within v1 is backward-compatible" | Confirmed — aggregator counting is `if .event_type == "deny" then ...` (ignores unknown types). | Ship aggregator + consumer + emissions atomically in one PR. Rejected 2-PR split (reviewer suggestion): solo-ops context, single PR is cheaper. |
| Brainstorm Non-Goal: "historical backfill skipped" | `git log --all --oneline --grep='LEFTHOOK=0\|--no-verify'` returns 2 matches, both on feature branches. | Confirmed. Skip. |
| Original plan (pre-review): "`pre-merge-rebase.sh` has 3 deny paths" | Reading `pre-merge-rebase.sh:117-124` shows a 4th deny path (uncommitted-changes). | 4th emission added (mapping in ADR-5). |
| Original plan: "`docs-cli-verification.sh` emit at each stderr-warn branch" | Flagging happens inside a single `awk` pipeline (`:36-81`) that writes directly to `/dev/stderr` — no bash-callable hook per match. | Restructure: awk writes flagged token lines to stdout with a sentinel prefix; bash reads lines, emits `warn` per line, re-prints the cleaned line to stderr to preserve existing UX. (See T2.4.) |

## Open Code-Review Overlap

**None.** Ran `gh issue list --label code-review --state open` (21 open issues) and cross-referenced against planned file edits. Zero matches.

## Architecture Decisions

### ADR-1 — New `fire_count` field; `hit_count` stays deny-only

Aggregator introduces per-rule `fire_count` = count of all events (any `event_type`) for that rule_id. `rule-prune.sh:51` and the aggregator's summary `rules_unused_over_8w` predicate switch from `hit_count == 0` → `fire_count == 0`. `orphan_rule_ids` logic unchanged.

**Why:** Preserves `hit_count` as "rule prevented a violation" (deny events only; `prevented_errors = deny - bypass` stays meaningful). Extending `hit_count` to include applied/warn would conflate telemetry-of-application with prevention-of-violation — wrong semantics for `prevented_errors`.

### ADR-2 — Skills emit at phase entry; worktree-root-resolved source path

Each `[skill-enforced: <skill> Phase <N>]` rule gets a one-line bash snippet in the named SKILL.md at phase entry:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident <rule-id> applied "<first-50-chars-of-rule-text>"
```

The source path uses `$(git rev-parse --show-toplevel)` rather than a relative `.claude/hooks/lib/incidents.sh` because the agent's Bash tool CWD during skill execution is frequently a worktree subdirectory (e.g., `plugins/soleur/skills/brainstorm/`); a relative path would silently fail to source. The library's `_incidents_repo_root()` (`.claude/hooks/lib/incidents.sh:19-21`) uses `BASH_SOURCE[0]`, which resolves to the library's path once sourced — so the emitter finds the right repo root regardless of CWD, but the `source` itself needs an absolute path first.

Each SKILL.md edit places the snippet in a fenced bash block with a labeled instruction ("Emit rule-application telemetry:") so the agent reliably runs it.

### ADR-3 — Python emitter inline in `security_reminder_hook.py`

Add a ~30 LOC helper `emit_incident(rule_id, event_type, prefix, cmd="")` with this strict ordering:

1. `try: import fcntl` at module top (module-level, guarded).
2. `mkdir -p` the parent directory of `.claude/.rule-incidents.jsonl` (fire-and-forget).
3. `fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)` — append-mode atomic on Linux for writes ≤ `PIPE_BUF` (4096 bytes). A JSONL line is ~200 bytes, well under the limit.
4. `fcntl.flock(fd, fcntl.LOCK_EX)` — advisory POSIX lock on the inode; interlocks with bash `flock -x` at `incidents.sh:67`.
5. `os.write(fd, line.encode("utf-8") + b"\n")`.
6. `fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd)`.
7. All wrapped in `try/except Exception: pass` — fire-and-forget.

Duplicates `SCHEMA_VERSION = 1` constant with a cross-reference comment `# schema mirror: .claude/hooks/lib/incidents.sh`. Same cross-reference goes into the bash library header.

**Why not subprocess-shellout (reviewer suggestion):** rejected in brainstorm Decision 3 — adds bash-exec latency per PreToolUse fire (hook runs on every bash command), and the Python hook runs on every Write/Edit tool call. The ~30 LOC cost is one-time; the latency cost would be permanent.

### ADR-4 — No drift-guard lint

All three plan-reviewers (DHH, Kieran, code-simplicity) flagged the originally-planned `scripts/lint-skill-enforced-emissions.sh` as premature: it hardens against a drift class that has occurred zero times and is naturally detected by the weekly aggregator (a missing emission appears as `fire_count == 0` in `rule-metrics.json`, surfacing in the next `rule-prune.sh --dry-run`).

Replace with a single acceptance-criterion grep run at plan-verification time:

```bash
grep -c '^[[:space:]]*source.*emit_incident' \
  plugins/soleur/skills/{brainstorm,ship,plan,deepen-plan,work,compound}/SKILL.md
# Expect output: 9 total across the 6 files (ship gets 4, others get 1 each)
```

If, post-merge, a new `[skill-enforced: ...]` rule ever gets added without an emission, the weekly aggregator will surface it as a zero-fire-count rule within one week. YAGNI — file the lint then.

### ADR-5 — `pre-merge-rebase.sh` deny path mapping (4 paths, not 3)

| Hook deny branch | File:line | rule-id | event_type |
|---|---|---|---|
| Review-evidence gate | `pre-merge-rebase.sh:93-100` | `rf-never-skip-qa-review-before-merging` | `deny` |
| Uncommitted changes | `pre-merge-rebase.sh:117-124` | `hr-when-a-command-exits-non-zero-or-prints` | `deny` |
| Merge-conflict exit | `pre-merge-rebase.sh:156-162` | `hr-when-a-command-exits-non-zero-or-prints` | `deny` |
| Push-failure exit | `pre-merge-rebase.sh:169-175` | `hr-when-a-command-exits-non-zero-or-prints` | `deny` |

Zero AGENTS.md byte growth. `hr-when-a-command-exits-non-zero-or-prints` receives 3 distinct sources; accepted because the rule is intentionally broad ("failed step ≠ success").

## Files to Edit

| Path | Change |
|---|---|
| `.claude/hooks/pre-merge-rebase.sh` | Source `lib/incidents.sh` at top; add 4 `emit_incident` calls per the ADR-5 mapping. |
| `.claude/hooks/docs-cli-verification.sh` | Source `lib/incidents.sh` at top. Restructure awk→stdout (sentinel-prefixed); bash read-loop emits `warn` per line and re-prints to stderr (preserves existing UX). Hook still exits 0. |
| `.claude/hooks/security_reminder_hook.py` | Add inline Python `emit_incident()` per ADR-3; call on workflow-injection deny. |
| `.claude/hooks/lib/incidents.sh` | Update header comment to document extended `event_type` enum (`deny`, `bypass`, `applied`, `warn`) and schema cross-reference to the Python emitter. Zero behavior change. |
| `scripts/rule-metrics-aggregate.sh` | (a) Extend the reduce-initializer at `:110-111` with `applied_count:0, warn_count:0, fire_count:0`. (b) Extend the counting pipeline at `:112-113` to tally `applied` → `applied_count`, `warn` → `warn_count`, and increment `fire_count` on any event. (c) Carry new fields through the enrich stage at `:147-155`. (d) Switch summary `rules_unused_over_8w` predicate at `:184-187` to use `fire_count == 0`. (e) Exit non-zero if `orphan_rule_ids` is non-empty (new invariant — see Acceptance Criteria). Preserve malformed-line tolerance. |
| `scripts/rule-prune.sh` | Switch orphan predicate at `:51` from `hit_count == 0` to `fire_count == 0`. Update the prose at `:125` to print `fire_count` instead of `hit_count`. |
| `plugins/soleur/skills/brainstorm/SKILL.md` | Add emission snippet at Phase 0.5 entry — rule `hr-new-skills-agents-or-user-facing`. |
| `plugins/soleur/skills/ship/SKILL.md` | Add 4 emission snippets: Phase 5.5 entry (`hr-before-shipping-ship-phase-5-5-runs`); Phase 5.5 Retroactive Gate Application branch (`wg-when-fixing-a-workflow-gates-detection`); Phase 5.5 Review-Findings Exit Gate branch (`rf-review-finding-default-fix-inline`); Phase 7 (`wg-after-a-pr-merges-to-main-verify-all`). |
| `plugins/soleur/skills/plan/SKILL.md` | Emission snippet at Phase 1.4 (`hr-ssh-diagnosis-verify-firewall`). |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | Emission snippet at Phase 4.5 (same rule, second emission point). |
| `plugins/soleur/skills/work/SKILL.md` | Emission snippet at Phase 2 TDD Gate (`cq-write-failing-tests-before`). |
| `plugins/soleur/skills/compound/SKILL.md` | Emission snippet at Step 8 rule budget count (`cq-agents-md-why-single-line`). |

## Files to Create

| Path | Purpose |
|---|---|
| `.claude/hooks/pre-merge-rebase.test.sh` | 4 fixtures (one per deny path); assert `.claude/.rule-incidents.jsonl` gets the expected JSON line. Follow `security_reminder_hook.test.sh` pattern (PASS/FAIL/TOTAL, `set -euo pipefail`, subshell isolation, preflight `command -v`). Use a `TMPDIR`-scoped `$HOME` so emissions don't pollute the operator's real file. |
| `scripts/rule-metrics-aggregate.test.sh` | Feed fixture JSONL with mixed event types (deny, bypass, applied, warn, unknown). Assert: (a) `applied_count`/`warn_count`/`fire_count` correct per rule, (b) `hit_count` still deny-only, (c) `prevented_errors = max(deny - bypass, 0)` unchanged, (d) `rules_unused_over_8w` uses `fire_count`, (e) unknown `event_type` emits `::warning::` but run completes exit 0, (f) rule-prune.sh --dry-run against a baked metrics JSON does not flag rules with `fire_count > 0` even when `hit_count == 0`, (g) aggregator exits non-zero if orphan_rule_ids non-empty. |

Test files for the other hooks are edits to existing `docs-cli-verification.test.sh` and `security_reminder_hook.test.sh`.

## Skill Emission Points (Authoritative)

| # | Rule ID | Skill file | Phase / section |
|---|---|---|---|
| 1 | `hr-new-skills-agents-or-user-facing` | `plugins/soleur/skills/brainstorm/SKILL.md` | Phase 0.5 (Domain Leader Assessment) |
| 2 | `hr-before-shipping-ship-phase-5-5-runs` | `plugins/soleur/skills/ship/SKILL.md` | Phase 5.5 (conditional domain leader gates) |
| 3 | `wg-when-fixing-a-workflow-gates-detection` | `plugins/soleur/skills/ship/SKILL.md` | Phase 5.5 Retroactive Gate Application branch |
| 4 | `rf-review-finding-default-fix-inline` | `plugins/soleur/skills/ship/SKILL.md` | Phase 5.5 Review-Findings Exit Gate branch |
| 5 | `wg-after-a-pr-merges-to-main-verify-all` | `plugins/soleur/skills/ship/SKILL.md` | Phase 7 (release/deploy verification) |
| 6 | `hr-ssh-diagnosis-verify-firewall` | `plugins/soleur/skills/plan/SKILL.md` | Phase 1.4 (network-outage hypothesis check) |
| 7 | `hr-ssh-diagnosis-verify-firewall` | `plugins/soleur/skills/deepen-plan/SKILL.md` | Phase 4.5 (same rule, second emission point) |
| 8 | `cq-write-failing-tests-before` | `plugins/soleur/skills/work/SKILL.md` | Phase 2 TDD Gate |
| 9 | `cq-agents-md-why-single-line` | `plugins/soleur/skills/compound/SKILL.md` | Step 8 (rule budget count) |

## Implementation Phases

Numbered phases are RED → GREEN pairs. Infrastructure-only tasks (SKILL.md edits, header comments) are exempt per the TDD Gate.

### Phase 1: Aggregator + consumer (ship atomically)

**T1.1 (RED):** Write `scripts/rule-metrics-aggregate.test.sh` with fixtures:
- Rule A: 3 `deny` + 1 `bypass` → expect `hit_count=3, bypass_count=1, applied_count=0, warn_count=0, fire_count=4, prevented_errors=2`.
- Rule B: 2 `applied` → expect `hit_count=0, applied_count=2, fire_count=2, prevented_errors=0`.
- Rule C: 1 `warn` → expect `warn_count=1, fire_count=1`.
- Rule D: 1 unknown `event_type="bogus"` → expect run completes exit 0, `::warning::` emitted, no field incremented.
- Fixture with only `applied`/`warn` events: assert `rules_unused_over_8w` does NOT include those rules.
- Fixture with a `rule_id` NOT present in AGENTS.md: assert aggregator exits non-zero and `orphan_rule_ids` contains it.
- Fixture baked as `rule-metrics.json` input: invoke `scripts/rule-prune.sh --dry-run`; assert rules with `fire_count > 0` are NOT flagged even when `hit_count == 0`.

Run T1.1. Confirm RED.

**T1.2 (GREEN):** Edit `scripts/rule-metrics-aggregate.sh`:
- `:110-111` — extend the reduce-initializer object with `applied_count:0, warn_count:0, fire_count:0`.
- `:112-113` — extend the counting pipeline:
  - `applied` → `.applied_count += 1`
  - `warn` → `.warn_count += 1`
  - any event (including `deny`/`bypass`) → `.fire_count += 1`
- `:147-155` — extend the `$c` default in the enrich stage with the same three fields; carry them through to the emitted object.
- `:184-187` — change `rules_unused_over_8w` predicate from `.hit_count == 0` to `.fire_count == 0`.
- After the summary is computed, add an exit-nonzero guard: `if ($report.summary.orphan_rule_ids | length) > 0 → exit 5 with stderr diagnostic`.

Edit `scripts/rule-prune.sh`:
- `:51` — `hit_count == 0` → `fire_count == 0`.
- `:125` — prose reference updated.

Run T1.1. Confirm GREEN.

### Phase 2: Silent-hook emissions

**T2.1 (RED):** Write `.claude/hooks/pre-merge-rebase.test.sh` with 4 fixtures (one per ADR-5 row). Each fixture invokes the hook with PreToolUse JSON input that triggers the specific deny branch; sets `HOME` to a `mktemp -d` so `.claude/.rule-incidents.jsonl` writes to the temp dir. Assert: (a) exit code per hook contract, (b) JSONL file contains exactly one line with the expected `rule_id` and `event_type=deny`, (c) no JSONL contamination between tests.

**T2.2 (GREEN):** Edit `.claude/hooks/pre-merge-rebase.sh`:
- Source `lib/incidents.sh` at top (follow `guardrails.sh:20` pattern).
- Add `emit_incident` calls BEFORE each of the 4 `exit 0` statements per ADR-5. Each call passes the rule-id, `deny`, a ≤50-char prefix of the rule text, and the incoming command snippet from `$INPUT`.

Run T2.1. Confirm GREEN.

**T2.3 (RED):** Extend `.claude/hooks/docs-cli-verification.test.sh`:
- Fixture 1: markdown with a fabricated CLI invocation inside an unverified fence. Assert (a) stderr contains the existing `[docs-cli-verify]` warning (UX preserved), (b) JSONL receives one `warn` event with `rule_id=cq-docs-cli-verification`.
- Fixture 2: markdown with a verified fence (`<!-- verified: ... -->`). Assert no JSONL line, no stderr.
- Fixture 3: markdown with two unverified fences. Assert two JSONL lines.

**T2.4 (GREEN):** Restructure `.claude/hooks/docs-cli-verification.sh`:
- Source `lib/incidents.sh` at top.
- Change the awk `printf` target at `:58` from `/dev/stderr` to stdout, prefixed with a sentinel string (`[docs-cli-verify-emit] ` before the existing message). Redirect awk stdout to a bash `while read line` loop.
- In the bash loop: call `emit_incident "cq-docs-cli-verification" warn "When prescribing a CLI invocation that lands in user-facing docs" "<line>"`, then strip the sentinel and re-print the line to stderr (preserves the existing `[docs-cli-verify] ...` UX for operators).
- Hook still exits 0.

Run T2.3. Confirm GREEN.

**T2.5 (RED):** Extend `.claude/hooks/security_reminder_hook.test.sh`:
- Fixture: Bash PreToolUse payload with `echo "${{ github.event.issue.title }}"` in a workflow `run:` block. Assert (a) hook denies, (b) JSONL receives one `deny` event with `rule_id=hr-in-github-actions-run-blocks-never-use`, (c) assert a second invocation from a different PID produces a second JSONL line (concurrency smoke test — both writes land, no truncation).

**T2.6 (GREEN):** Edit `.claude/hooks/security_reminder_hook.py` per ADR-3. Add module-level `try: import fcntl`. Add `emit_incident()` helper. Call it immediately before the workflow-injection deny return.

Run T2.5. Confirm GREEN.

### Phase 3: Skill-enforced emissions (9 emission points, infrastructure-only)

**T3.1 (infra-exempt):** Edit each of the 6 skill SKILL.md files to add emission snippets per the Skill Emission Points table. Snippet form is fixed per ADR-2:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident <rule-id> applied "<first-50-chars-of-rule-text>"
```

Each snippet sits in a fenced bash block with a labeled instruction line so the agent reliably executes it.

**T3.2 (validation):** Run a one-off grep verification — the ADR-4 acceptance-criterion check:

```bash
grep -c '^[[:space:]]*source.*emit_incident' \
  plugins/soleur/skills/{brainstorm,ship,plan,deepen-plan,work,compound}/SKILL.md
# Expect: brainstorm=1, ship=4, plan=1, deepen-plan=1, work=1, compound=1 → total 9
```

### Phase 4: Pre-merge validation

**T4.1:** Run `bash scripts/rule-metrics-aggregate.test.sh` — full suite green.
**T4.2:** Run `bash .claude/hooks/pre-merge-rebase.test.sh` and extended hook tests — all green.
**T4.3:** Run `scripts/rule-metrics-aggregate.sh --dry-run` locally with an empty JSONL → assert exit 0 and JSON output is well-formed (no schema drift).
**T4.4:** Manually seed `.claude/.rule-incidents.jsonl` with one line per rule-id in AGENTS.md; re-run aggregator → assert `orphan_rule_ids: []` and exit 0.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Aggregator emits `applied_count`, `warn_count`, `fire_count` per rule in `rule-metrics.json`.
- [ ] Aggregator exits non-zero if `summary.orphan_rule_ids` is non-empty (new invariant).
- [ ] `rule-prune.sh` orphan predicate uses `fire_count == 0`.
- [ ] 3 silent hooks (`pre-merge-rebase.sh`, `docs-cli-verification.sh`, `security_reminder_hook.py`) emit incidents on all firing paths (4 + N + 1 respectively).
- [ ] 9 skill emission points added per the Authoritative table. Grep verification: `grep -c '^[[:space:]]*source.*emit_incident' plugins/soleur/skills/{brainstorm,ship,plan,deepen-plan,work,compound}/SKILL.md` totals 9.
- [ ] All new and extended `*.test.sh` files pass locally: `pre-merge-rebase.test.sh`, `rule-metrics-aggregate.test.sh`, and extended `docs-cli-verification.test.sh` + `security_reminder_hook.test.sh`.
- [ ] No new AGENTS.md rules (no byte growth — ADR-5 reuses existing rule-ids).

### Post-merge (automated)

- [ ] First weekly `rule-metrics-aggregate` cron run post-merge completes exit 0 (implies `orphan_rule_ids == []` — aggregator now gates on this).
- [ ] `rule-metrics.json` in the post-cron commit shows `fire_count > 0` for at least one skill-enforced rule and one hook-enforced rule.

No "manual operator verification" step — the aggregator's exit-nonzero invariant automates post-merge validation; a failure trips the existing workflow's notification path.

## Test Strategy

- **Pattern:** `.test.sh` scripts follow the existing `security_reminder_hook.test.sh` convention — `set -euo pipefail`, PASS/FAIL/TOTAL counters, subshell isolation per test, `command -v python3/jq` preflight, inline `printf` / heredoc fixtures.
- **Isolation:** each hook test scopes `HOME` (or the incident-file parent) to a `mktemp -d` so emissions don't pollute the operator's real `.claude/.rule-incidents.jsonl`.
- **Framework:** pure bash + `jq` + `python3` — already in use. No new dependencies.
- **Test-harness wiring:** existing CI runs `*.test.sh` via the repo's test-runner convention; the two new tests (`pre-merge-rebase.test.sh`, `rule-metrics-aggregate.test.sh`) sit in the same directories and are picked up automatically. No new wiring required.

## Rollout Order (within the single PR)

1. Aggregator extension (`scripts/rule-metrics-aggregate.sh` + tests).
2. Consumer switch (`scripts/rule-prune.sh` to `fire_count`).
3. Silent-hook emissions (pre-merge-rebase, docs-cli-verification, security_reminder_hook).
4. 9 skill emission points.
5. Header comment update in `incidents.sh` documenting extended enum.

Each step is independently testable; sequencing is for review-ergonomics, not correctness (all 5 can land in any intra-PR order).

## Risks

- **R1 — Python `fcntl` absent on exotic platforms.** Mitigation: module-level `try: import fcntl`; silent no-op on ImportError. Linux/macOS only for this repo.
- **R2 — `fire_count` field name collision.** Mitigation: grepped `fire_count` across `scripts/`, `.claude/`, `knowledge-base/` — zero existing uses.
- **R3 — Skill emission pollutes `.claude/.rule-incidents.jsonl` with high-frequency `applied` events.** A dev running `brainstorm` 50×/week generates 50+ events for `hr-new-skills-agents-or-user-facing`. Desirable (high-fire rule → definitively not orphan); weekly rotation at `rule-metrics-aggregate.sh:258-262` handles file growth.
- **R4 — Skill emissions fire on every phase entry, including aborted flows.** Accepted: `applied_count` semantics = "skill entered phase." `prevented_errors` stays narrow (deny-only) for the stronger claim.
- **R5 — Rotation race with cached fds.** `rule-metrics-aggregate.sh` rotation does `: > "$INCIDENTS"` under `flock`; a concurrent bash or Python writer with a cached fd on the old inode would produce orphaned writes. Pre-existing (not a regression). Not blocking; noted for future work.
- **R6 — Aggregator schema change breaks downstream readers.** Only two consumers: `rule-prune.sh` (updated in this PR) and the compound skill's rule budget step (reads `summary.rules_unused_over_8w`, semantics preserved). Grepped `rule-metrics.json` + `hit_count` across the repo — no other readers.

## Non-Goals

- Historical backfill.
- Schema v2.
- New AGENTS.md rule-ids for pre-merge-rebase paths.
- Bypass detection v2 (`--force` on main, `--no-gpg-sign`, `--amend` after deny).
- Automated rule retirement.
- Drift-guard lint script (all three plan-reviewers agreed: premature; weekly aggregator is a free self-detector).

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change, no user-facing surface, no content, no pricing, no legal implications, no new external resources. No domain leaders spawned.

Product/UX Gate: **NONE** (no new page/component files; no user-facing flows).

## References

- Issue #2866
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-24-rule-metrics-emit-incident-coverage-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-one-shot-2866-rule-metrics-emit-incident-coverage/spec.md`
- Prior plan: `knowledge-base/project/plans/2026-04-15-fix-rule-metrics-aggregator-pr-pattern-and-prune-backfill-plan.md`
- Prior learning: `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`
- Aggregator: `scripts/rule-metrics-aggregate.sh:110-113, :147-155, :184-187, :258-262`
- Consumer: `scripts/rule-prune.sh:51, :125`
- Silent hooks: `pre-merge-rebase.sh:93-100, :117-124, :156-162, :169-175`; `docs-cli-verification.sh:36-81`; `security_reminder_hook.py` (workflow-injection deny branch)
- Emitter library: `.claude/hooks/lib/incidents.sh:19-21, :50-51, :67`
- Schema constants: `scripts/lib/rule-metrics-constants.sh`

## Review Log

Plan reviewed 2026-04-24 by DHH-reviewer, Kieran-reviewer, code-simplicity-reviewer (parallel).

**Applied:**
- Drop drift-guard lint script (ADR-4 now states the decision and the 3-reviewer consensus).
- Fix skill snippet path: `$(git rev-parse --show-toplevel)` prefix (Kieran #1 blocker).
- Python emitter strict ordering: open → flock → write → unlock + PIPE_BUF atomicity note (Kieran #2).
- T1.2 explicit about reduce-initializer default object at `:110-111` (Kieran #3).
- 4th deny path in pre-merge-rebase.sh (uncommitted-changes at `:117-124`) added (Kieran #4).
- docs-cli-verification.sh restructure: awk-stdout + bash-loop emit (Kieran #6).
- Post-merge AC automated via aggregator exit-nonzero on orphans (Kieran omission).
- Rotation-race pre-existing issue noted as R5 (Kieran #7).
- Collapsed T1.3/T1.4 into T1.1/T1.2 (code-simplicity #3).
- Deleted tautological `wc -c AGENTS.md` AC and the 4-weeks-post-merge check (code-simplicity #5).
- Simplified ADR-5 to the mapping table; deleted Risk R5-original (code-simplicity #4).

**Rejected with reasons:**
- DHH #5 (split into 2 PRs): solo-ops context, single PR is cheaper. Bundling atomic.
- Code-simplicity #2 (subprocess Python emitter): user chose inline in brainstorm Decision 3 with explicit latency reasoning (hook runs on every Write/Edit tool call).
- DHH #3 (collapse emissions across skills): already one per skill file. `hr-ssh-diagnosis-verify-firewall` has two emission points because it's tagged on two distinct skills; aggregator handles duplicates correctly (each skill-file edit produces at most one emission per phase invocation).
