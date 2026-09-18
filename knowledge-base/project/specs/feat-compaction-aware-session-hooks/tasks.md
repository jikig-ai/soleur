---
feature: compaction-aware-session-hooks
lane: cross-domain
branch: feat-compaction-aware-session-hooks
issue: 8323
plan: knowledge-base/project/plans/2026-09-18-feat-compaction-aware-session-hooks-plan.md
---

# Tasks: Compaction-Aware Session Hooks

Derived from the plan **after** its six-agent review. Four mechanisms were deleted at review (checkpoint writer → #8328, token-ratio clause, phase derivation, the `one-shot` Step 8 edit); they are absent here by design, not by omission.

## Phase 0 — Payload probe (blocking)

- [ ] 0.1 Bind a throwaway marker hook to `PreCompact` and `SessionStart` via `.claude/settings.local.json` (gitignored), logging: timestamp, `hook_event_name`, `source`/`trigger`, sorted top-level stdin keys, `transcript_path`, the `compact_boundary` count read from that path, and the last boundary's `trigger`.
- [ ] 0.2 Force one `/compact`; then let one auto-compaction occur.
- [ ] 0.3 Record dated findings in the hook header: the literal `source` value; **whether the observed count includes the compaction that just fired**; `transcript_path` stability; `--fork-session` inheritance.
- [ ] 0.4 If the count excludes the current compaction, switch to the pre-authorized fallback (`PreCompact` appends one line to a per-session `TMPDIR` file; `SessionStart:compact` counts lines there).
- [ ] 0.5 Delete the probe and its `settings.local.json` entry.

## Phase 1 — `compaction-state.sh` read path (FR1, FR2)

- [ ] 1.1 **RED:** write `plugins/soleur/test/compaction-state-hook.test.sh` with the 3 synthesized fixtures (`no-boundary`, `one-auto`, `two-auto`) and scenarios 1–6; confirm it fails against the absent script.
- [ ] 1.2 Create `plugins/soleur/hooks/compaction-state.sh`: dispatch on `hook_event_name`; `SOLEUR_DISABLE_COMPACTION_HOOKS=1` short-circuit; `set -uo pipefail`; `trap 'exit 0' ERR EXIT` (the `EXIT` arm is load-bearing — `set -u` terminates without firing `ERR`).
- [ ] 1.3 **TR1 scope guard:** the `welcome-hook.sh` sentinel (a `plugins/soleur` directory check under the project root) **plus** a Soleur plan/spec artifact. Never "is a git repo".
- [ ] 1.4 Read `transcript_path`; derive `count_auto` **scoped to this session's window** (TR2) and the last boundary's `trigger`.
- [ ] 1.5 Recommendation rule: `trigger == "auto" AND count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}`.
- [ ] 1.6 Build the envelope with `jq -n --arg`; markers and the `claude --version` string go **inside `additionalContext`**; stdout carries JSON only; diagnostics to stderr; truncate at 8,000 chars.
- [ ] 1.7 Static `printf`'d JSON fallback for the `jq`-unavailable path.
- [ ] 1.8 **GREEN:** scenarios 1–10 pass.

## Phase 2 — `PreCompact` summary shaping (FR3)

- [ ] 2.1 ~5 lines of static plain-text stdout naming the identifiers to preserve (branch, worktree, PR #, issue #, plan path, unchecked ACs, operator holds, file paths). Not JSON. Exit 0 always; never exit 2.
- [ ] 2.2 Same TR1 scope guard — this is the path that would otherwise degrade a stranger's summary.
- [ ] 2.3 Scenario 11 passes.

## Phase 3 — Prose retirement + docs (FR5, FR6)

- [ ] 3.1 `plan/SKILL.md`: make the two `/clear` **recommendations** conditional; leave the mandatory resume-prompt blocks byte-identical.
- [ ] 3.2 `work/SKILL.md`: same for the `Tip: After shipping…` display; confirm an end-of-work resume prompt still fires when the hook never speaks.
- [ ] 3.3 `plugins/soleur/README.md`: document `SOLEUR_COMPACTION_COUNT_THRESHOLD` + `SOLEUR_DISABLE_COMPACTION_HOOKS`; add the Grok row.
- [ ] 3.4 One line each in `devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` under `## Hooks and completion`.
- [ ] 3.5 `hooks.json`: add the two bindings; assert no `PostCompact` key.

## Phase 4 — Drift canary (FR7)

- [ ] 4.1 `scripts/followthroughs/compaction-format-drift-8323.sh` — reads real `~/.claude/projects/**/*.jsonl`, exits non-zero on zero `compact_boundary` records across N recent transcripts.
- [ ] 4.2 Register it as a schedule via `soleur:schedule` — **not** a suite case (a suite case breaks CI on a clean box).

## Phase 5 — ADR + C4 + register

- [ ] 5.1 `ADR-228` with all seven Alternatives Considered, including the deleted checkpoint writer and its two P0s; record that this is the first customer-shipped consumer of the transcript format.
- [ ] 5.2 `model.c4`: amend the `hooks` **`technology`** line and its surface-split description.
- [ ] 5.3 `principles-register.md`: amend **AP-020** for the transcript-dereference relationship.
- [ ] 5.4 Reconcile `spec.md` with the four cuts.

## Phase 6 — Verification

- [ ] 6.1 All 21 acceptance criteria checked against real command output.
- [ ] 6.2 `TEST_GROUP=all bash scripts/test-all.sh` green; verdict read from the rc file, never a completion notification.
- [ ] 6.3 `c4-count-parity.test.sh` + `c4-*.test.ts` green.
- [ ] 6.4 `/soleur:review`, then `/soleur:compound`, then `/soleur:ship`.
