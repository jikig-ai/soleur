# Tasks: rule-metrics emit_incident coverage

Plan: `knowledge-base/project/plans/2026-04-24-chore-rule-metrics-emit-incident-coverage-plan.md`

TDD structure: each RED task writes a failing test; the GREEN task implementing it is `blockedBy` the RED task. Infrastructure-only tasks (SKILL.md edits, header comments) are exempt per `cq-write-failing-tests-before`.

## Phase 1: Aggregator + consumer (ship atomically)

- [ ] 1.1 RED — write `scripts/rule-metrics-aggregate.test.sh` with fixtures for mixed event types (deny, bypass, applied, warn, unknown), orphan-id detection, and rule-prune cross-check. Run — confirm fail.
- [ ] 1.2 GREEN — edit `scripts/rule-metrics-aggregate.sh`:
  - [ ] 1.2.1 Extend reduce-initializer at `:110-111` with `applied_count:0, warn_count:0, fire_count:0`
  - [ ] 1.2.2 Extend counting pipeline at `:112-113` for `applied`/`warn`/`fire_count`
  - [ ] 1.2.3 Carry new fields through enrich stage at `:147-155`
  - [ ] 1.2.4 Switch `rules_unused_over_8w` predicate at `:184-187` to `fire_count == 0`
  - [ ] 1.2.5 Exit non-zero when `orphan_rule_ids` non-empty
  - [ ] 1.2.6 Edit `scripts/rule-prune.sh`: `:51` predicate and `:125` prose to `fire_count`
  - [ ] 1.2.7 Run 1.1 — confirm GREEN

## Phase 2: Silent-hook emissions

- [ ] 2.1 RED — write `.claude/hooks/pre-merge-rebase.test.sh` with 4 fixtures (review-evidence, uncommitted-changes, merge-conflict, push-failure); TMPDIR-scoped `HOME`; assert JSONL + exit code. Run — confirm fail.
- [ ] 2.2 GREEN — edit `.claude/hooks/pre-merge-rebase.sh`:
  - [ ] 2.2.1 Source `lib/incidents.sh` at top (follow `guardrails.sh:20` pattern)
  - [ ] 2.2.2 Add `emit_incident` before each of 4 deny `exit 0` statements per ADR-5
  - [ ] 2.2.3 Run 2.1 — confirm GREEN
- [ ] 2.3 RED — extend `.claude/hooks/docs-cli-verification.test.sh` with 3 fixtures (unverified, verified, two-unverified); assert JSONL warn events + stderr UX preserved. Run — confirm fail.
- [ ] 2.4 GREEN — restructure `.claude/hooks/docs-cli-verification.sh`:
  - [ ] 2.4.1 Source `lib/incidents.sh` at top
  - [ ] 2.4.2 Redirect awk stdout (prefixed with sentinel) into bash `while read` loop
  - [ ] 2.4.3 Loop emits `warn` per line, re-prints cleaned line to stderr
  - [ ] 2.4.4 Run 2.3 — confirm GREEN
- [ ] 2.5 RED — extend `.claude/hooks/security_reminder_hook.test.sh` with workflow-injection fixture + concurrency smoke test (two PIDs writing, both lines land). Run — confirm fail.
- [ ] 2.6 GREEN — edit `.claude/hooks/security_reminder_hook.py`:
  - [ ] 2.6.1 Module-level `try: import fcntl`
  - [ ] 2.6.2 Add `emit_incident(rule_id, event_type, prefix, cmd="")` using `os.open` + `O_APPEND` + `fcntl.flock` per ADR-3 ordering
  - [ ] 2.6.3 Duplicate `SCHEMA_VERSION = 1` with cross-reference comment
  - [ ] 2.6.4 Call before workflow-injection deny return
  - [ ] 2.6.5 Wrap helper body in `try/except Exception: pass`
  - [ ] 2.6.6 Run 2.5 — confirm GREEN

## Phase 3: Skill emissions (infra-exempt — no RED tests)

- [ ] 3.1 Edit `plugins/soleur/skills/brainstorm/SKILL.md` — add emission snippet at Phase 0.5 entry (`hr-new-skills-agents-or-user-facing`)
- [ ] 3.2 Edit `plugins/soleur/skills/ship/SKILL.md` — add 4 emission snippets:
  - [ ] 3.2.1 Phase 5.5 entry → `hr-before-shipping-ship-phase-5-5-runs`
  - [ ] 3.2.2 Phase 5.5 Retroactive Gate Application branch → `wg-when-fixing-a-workflow-gates-detection`
  - [ ] 3.2.3 Phase 5.5 Review-Findings Exit Gate branch → `rf-review-finding-default-fix-inline`
  - [ ] 3.2.4 Phase 7 (release/deploy verification) → `wg-after-a-pr-merges-to-main-verify-all`
- [ ] 3.3 Edit `plugins/soleur/skills/plan/SKILL.md` — Phase 1.4 (`hr-ssh-diagnosis-verify-firewall`)
- [ ] 3.4 Edit `plugins/soleur/skills/deepen-plan/SKILL.md` — Phase 4.5 (`hr-ssh-diagnosis-verify-firewall` — second point)
- [ ] 3.5 Edit `plugins/soleur/skills/work/SKILL.md` — Phase 2 TDD Gate (`cq-write-failing-tests-before`)
- [ ] 3.6 Edit `plugins/soleur/skills/compound/SKILL.md` — Step 8 rule budget count (`cq-agents-md-why-single-line`)
- [ ] 3.7 Snippet form (fixed per ADR-2):
      ```bash
      source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
        emit_incident <rule-id> applied "<first-50-chars-of-rule-text>"
      ```
- [ ] 3.8 Grep verification: `grep -c '^[[:space:]]*source.*emit_incident' plugins/soleur/skills/{brainstorm,ship,plan,deepen-plan,work,compound}/SKILL.md` — total 9 (ship=4, others=1 each)

## Phase 4: Documentation (infra-exempt)

- [ ] 4.1 Update `.claude/hooks/lib/incidents.sh` header comment — document extended `event_type` enum (`deny`, `bypass`, `applied`, `warn`)
- [ ] 4.2 Add cross-reference comment in `security_reminder_hook.py` pointing to `incidents.sh` schema

## Phase 5: Pre-merge validation

- [ ] 5.1 `bash scripts/rule-metrics-aggregate.test.sh` — all green
- [ ] 5.2 `bash .claude/hooks/pre-merge-rebase.test.sh` — all green
- [ ] 5.3 `bash .claude/hooks/docs-cli-verification.test.sh` — all green (including new warn-emit fixtures)
- [ ] 5.4 `bash .claude/hooks/security_reminder_hook.test.sh` — all green (including concurrency smoke)
- [ ] 5.5 Manual sanity: `bash scripts/rule-metrics-aggregate.sh --dry-run` against empty JSONL → exit 0, JSON output well-formed
- [ ] 5.6 Manual sanity: seed one JSONL line per rule-id in AGENTS.md → re-run aggregator → exit 0 and `orphan_rule_ids == []`

## Phase 6: Ship

- [ ] 6.1 Run `/soleur:review` — catch remaining issues
- [ ] 6.2 Run `/soleur:compound` — capture any learnings (per `wg-before-every-commit-run-compound-skill`)
- [ ] 6.3 Run `/soleur:ship` — commit, push, PR, merge
- [ ] 6.4 Post-merge: verify first weekly `rule-metrics-aggregate` cron run succeeds (aggregator exit-nonzero guards `orphan_rule_ids == []`; failure notifies via workflow's existing path)
