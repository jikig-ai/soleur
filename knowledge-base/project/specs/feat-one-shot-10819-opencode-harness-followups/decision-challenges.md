# Decision challenges — plan review panel

Plan: `knowledge-base/project/plans/2026-10-22-fix-opencode-harness-followups-plan.md`
Panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer` (engineering), `cto` (devex), `cpo` (product).
Consolidation: single-signal, per `plan-review`.

## Applied without escalation (mechanical: one right answer, technical)

Every P0/P1 finding below was folded into the plan. Recorded so the diff can be read against them.

| Finding | Source | Applied as |
|---|---|---|
| Absent tool surface announced only to the log, which is off by default | CTO, CPO, spec-flow, simplicity, kieran | stderr **and** log, asserted in AC4 |
| A rejecting `tool.hook` aborts `setup` and can leave the guards unbound | CTO, arch, kieran | bind permission first, `try/catch` registration, throw == absent, test (n) |
| Capture gated on `claudeToolName`, consume on the literal `"shell"` | kieran, arch, CTO | one `decidesBash` predicate on both sides; test (i), mutation 3 |
| Relative `workdir` resolved on an unmeasured assumption | DHH, kieran, arch, spec-flow, CTO, CPO | measured (session-move probe) and added to the measurement record; test (d) |
| Map keyed on a call id alone ("ids are not reused") | kieran | key `(messageID, id)`; test (l) |
| `source.type` unchecked | kieran | non-`tool` sources treated as uncorrelated |
| Unusable captured workdir falls back to the session directory and allows | DHH, kieran | `effect = "ask"` naming the path; guards not run; test (h) |
| `consumed` flag + `workdir-evicted` fire on non-faults | DHH, simplicity, CTO | cut both; a lost capture is loud at the decision (`cause=no-capture`) |
| `runScript` discards `spawnSync.error`, so an unenterable cwd is reported as a moved checkout | CTO, CPO, kieran | `ScriptRun.error`; `decideBash` branches the reason |
| ADR-245 amendment dated 2026-10-14 | arch | 2026-09-23 (the record's own date) |
| Append-only amendment leaves Decision item 1 reading current | arch | inline `*(Amended …)*` pointer at item 1; original untouched |
| AC9's count-not-increase forbids quoting the clause | arch, spec-flow | amendment does not restate the harness names; count held at the branch base |
| ADR-291 records `tool.execute.before` as withdrawn while this PR binds it | arch | dated clause-scoped note: capture-only, withdrawal stands for decisions |
| Ledger legend does not define `bind` for a row that delivers a capture; binding column left `-` | arch, spec-flow | legend extended, binding column set, assertion moved out of the rejected-surfaces case, all three fields asserted |
| Operator-surface sweep cited a nonexistent path and a population that misses the contradiction | arch, CPO, spec-flow | eight real paths; falsifiable question; SKILL.md/`soleur_op_in_agent_harness` gap filed |
| `tty-ack` described as "a real TTY" | CPO, spec-flow | scoped: the harness detector does not recognise OpenCode, so the arm is open here; no receipt can be minted |
| AC11/AC12/AC7 checks cannot see what they claim | spec-flow, cto | heading-bounded `awk`, named-harness rewrite (`grep` → nothing), consequence greps |
| CONTRIBUTING flow omits re-install, test command, ledger obligation, `--target` | spec-flow, CTO | all four added, plus `SOLEUR_OPENCODE_EVENT_LOG` |
| P5 claims "every absent gate" while delivering one | simplicity, spec-flow | narrowed to the approval gate; the other five named in Out of Scope |
| #10820's third ask (marketing clause → link) unmapped | spec-flow | Ask Mapping row 5, descoped to #10815 with the reason |
| AC1's source-shape greps | DHH, simplicity, kieran, CTO | dropped; behaviour + mutation pass carry AC1/AC3 |
| C4 suite waived rather than run | arch | run in Phase 5.4 |

## Declined (taste: surfaced, not applied silently)

| Finding | Source | Why the plan keeps its shape |
|---|---|---|
| Collapse all degradation tokens into one line with a `why=` field | DHH | The tokens are already a closed `cause=` set on one token plus two structural ones; a single line would still need the cause discriminator, and the operator-facing sentence is separate from the TSV token. Net change: none. |
| Cut the Guard Contract from six mutations to the two Phase 5 executes | DHH, simplicity | Phase 5.4 executes all six. The table is the derivation a reviewer checks the suite against, and mutation 3 (the alias) is the one this panel found, so the table earns its length. |
| Stop exporting `resolveWorkdir` | simplicity | The suite imports the exported helpers it drives (`runScript`, `decideBash`, `guardEnvelope` already are); an unexported helper would be tested only through the whole plugin. |
| Use a single "last workdir" slot instead of a map | (considered, not recommended by the panel) | Interleaved calls would inherit each other's directory; the map is the same two lines. |
| Extract `lib/guard-envelope.ts` now so the next harness inherits it | (CTO ruled against) | One consumer today. The durable artefact is the `decidesBash` predicate plus the invariant block, not the constructor. Revisit on the second carrier. |
| Split Phases 2–4 into a separate PR | arch (soft), CPO (explicitly not) | Operator ruled one merged PR. Adopted the isolation instead: Phase 1 is its own commit and Phases 2–4 depend on nothing in it, so they can re-land ahead of it. |

## Escalated to the operator

None. No finding argued that the operator's stated scope should change, and no finding introduced a
new sub-processor, recurring cost, irreversible data operation, or a legal/market claim.

## Standing panel check

`cq-ac-must-not-depend-on-concurrent-sessions`: every acceptance criterion reads the diff, the
suite, or a committed file. AC13's exact pass count is a property of the suite in this tree; no
criterion asserts the absence of an ambient signal or depends on another worktree.
