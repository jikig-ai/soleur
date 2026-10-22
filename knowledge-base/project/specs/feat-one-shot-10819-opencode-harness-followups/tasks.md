# Tasks — fix four OpenCode harness follow-ups (#10819–#10822)

Plan: `knowledge-base/project/plans/2026-10-22-fix-opencode-harness-followups-plan.md`
Branch: `feat-one-shot-10819-opencode-harness-followups`
PR: #10863

Ordering is deliberate: Phase 1 is its own commit, and Phases 2–4 depend on nothing in it. If review
finds a defect in the guard change, re-land the disclosure and record fixes ahead of it.

## Phase 1 — #10819 correlation (own commit)

- [ ] 1.1 `decidesBash(tool)` exported; `guardEnvelope` uses it; capture and consume both gate on it
- [ ] 1.2 `ToolBeforeEvent`, `source` on `PermissionEvaluateEvent`, optional `SetupContext.tool`
- [ ] 1.3 `resolveWorkdir(input, baseDir): WorkdirCapture` — relative against `baseDir`, `realpathSync`,
      unusable kept distinct from absent
- [ ] 1.4 `calls` map keyed `(messageID, id)`, FIFO 500, silent eviction, no delete/re-insert on consume
- [ ] 1.5 Permission hook bound first; capture registration wrapped in `try/catch`; throw == absent
- [ ] 1.6 Consume: non-Bash returns before the map; unusable → `effect = "ask"` + message, guards not run
- [ ] 1.7 `ScriptRun.error` from `spawnSync`; `decideBash` names an unenterable cwd
- [ ] 1.8 Module docblock: capture-only binding + invariant block
- [ ] 1.9 Tests (a)–(o) in a `workdir correlation` suite, all reading `runs[0].stdin`
- [ ] 1.10 Ledger suite: move the row's assertions into a binding case; assert disposition + binding + reason
- [ ] 1.11 `.claude/hooks/opencode-dispositions.tsv` row → `bind`, binding column set, legend extended
- [ ] 1.12 `git commit` Phase 1 alone

## Phase 2 — #10820 disclosure

- [ ] 2.1 Generator paragraph in `instructions()`: absent gate, `exit 75`, scoped `tty-ack`, no receipt
- [ ] 2.2 `bun plugins/soleur/scripts/sync-opencode-adapter.ts` (regenerate, never hand-edit)
- [ ] 2.3 `--check` → `opencode-adapter ok`
- [ ] 2.4 Ledger operator-stage row evidence gains the matrix cross-reference
- [ ] 2.5 Operator-surface sweep over the eight paths; answer the falsifiable question in writing
- [ ] 2.6 File the tracking issue (OpenCode not recognised by `soleur_op_in_agent_harness`; SKILL.md
      receipt wording unqualified); record its number here

## Phase 3 — #10821 records

- [ ] 3.1 ADR-245 `## Amendment — 2026-10-22 (#10821)`, no harness-name restatement
- [ ] 3.2 ADR-245 inline pointer under Decision item 1 (original sentence untouched)
- [ ] 3.3 ADR-291 `## Amendment — 2026-10-22 (#10819)` recording the capture-only binding
- [ ] 3.4 `git grep` for the set phrase: only ADR-245 §Context/Decision item 1 and ADR-291's correct
      occurrences

## Phase 4 — #10822 contributor path

- [ ] 4.1 `CONTRIBUTING.md`: routing line above `### Codex`; `### OpenCode` subsection with install,
      re-install, `--check`, generated-vs-hand-edited, no-CI-gate, bare ids, stay-put, test command,
      ledger obligation, `SOLEUR_OPENCODE_EVENT_LOG`, absent gate, link
- [ ] 4.2 `lib/harness.ts` header count-free
- [ ] 4.3 `lib/workflow-fidelity.ts` "silently for any caller that forgot it"
- [ ] 4.4 `test/components.test.ts`: four phrases — two count-free, two naming devin/codex/grok

## Phase 5 — verification

- [ ] 5.1 Focused suite: 84 + N pass, 0 fail; quote the exact counts
- [ ] 5.2 `sync-opencode-adapter.ts --check`
- [ ] 5.3 Install then `--check` into a `mktemp -d`
- [ ] 5.4 C4 suite green (no component added)
- [ ] 5.5 Six mutations red in a scratch copy, each with its quoted fail count
- [ ] 5.6 PR body disclosures (below)

## Acceptance criteria

See the plan's `## Acceptance Criteria` (AC1–AC14). Note AC13 needs an **exact** count, not `≥`.

## Disclosures

- Overlap preflight: `pr-overlap-preflight.sh --mode start` failed twice with `rc=2`
  (`jq: Argument list too long`). **Overlap was not checked** by that tool. The code-review overlap
  check ran instead and found #8593 (naming `components.test.ts`, comment-only edit here).
- C4: the model has no OpenCode element (#10866). No `.c4` change in this PR; the C4 suite runs green
  because no component is added.
- CI: no workflow runs `sync-opencode-adapter.ts --check` against the committed tree; the drift test
  is fixture-based. Disclosed, not fixed.
- ADR-291 is amended (capture-only binding) as well as ADR-245; both are dated, clause-scoped notes.
- Relative `workdir` resolution is **measured** (session moved to a worktree while the server kept
  the bare checkout as its launch cwd).
- `cwd = workdir` narrows the destructive guard's default-branch set for a repository with no
  `refs/remotes/<remote>/HEAD`. Named residual, not fixed.
- stderr visibility of plugin `console.error` in the TUI is **unmeasured**; every degraded path also
  writes the TSV line, and CONTRIBUTING documents `SOLEUR_OPENCODE_EVENT_LOG`.
- The five other `absent-with-reason` ledger rows remain undisclosed in the matrix; P5 claims one gate.
