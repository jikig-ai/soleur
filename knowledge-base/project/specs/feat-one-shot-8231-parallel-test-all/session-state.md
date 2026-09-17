# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: PASS — `git diff origin/main...HEAD --name-only` empty; only untracked
  `plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md` and
  `specs/feat-one-shot-8231-parallel-test-all/`. No source, workflow, or CHANGELOG edits.
  Planning subagent made no commits.

### Scope decision (operator, pre-plan)
Operator was shown that #7454 Item 1 is a near-duplicate of #8231 and blocks it on #7376
closing, then chose **"Diagnose first, then parallelize"** over an opt-in-flag shape. Plan is
ordered accordingly: diagnose the #7376 interference -> fix shared-resource collisions ->
parallelize with a contention test.

Reconciliation already posted (not deferred):
- #7454 comment 5713378548 — Item 1 marked superseded by #8231; Items 2 and 3 left open.
- #8231 comment 5713381406 — the missing #7376 precondition + adjacent constraints recorded.

### Errors
None blocking. Five factual errors in the plan's own first draft were found by the review panel
and corrected in place, each by reading the authority rather than by argument:

1. `bash scripts/test-all.sh --enumerate all` returns zero enumeration records at rc 1 on this
   host. `actual=$(bun --version)` (scripts/test-all.sh ~:318-325) aborts under `set -e`.
   Anti-vacuity floors written as `derived >= derived` would have been `0 >= 0`.
   **Independently re-verified by the lead after the subagent returned** (token-discipline rule 4:
   an inherited verification claim is a statement about a tree that may no longer exist):
   EXIT=1, zero records, five `mise` stderr lines. Root cause confirmed — `command -v bun`
   succeeds because a mise shim exists at `~/.local/share/mise/shims/bun`, but `bun --version`
   fails with "No version is set for shim", so the `command -v` guard is too weak. One-character
   guard is in Files to Edit.
2. The capacity probe asserted rc 0; measured,
   `systemd-run --user --scope -p AllowedCPUs=0-3 -- nproc` returns 16, not 4 — a proxy-vs-invariant
   substitution the plan polices elsewhere.
3. `_site/` is a producer/**producer** pair, not producer/consumer: `seo-aeo-drift-guard.test.ts`
   builds into a `mkdtemp` dir and `validate-blog-links.sh` is itself the producer. The in-tree
   comment describing it is stale.
4. A nested `test-all.sh` **refuses** (ADR-196, exit 4 at :1326, before `tc_acquire` at :1495); it
   does not block for an hour. The deadlock exists only under an inherited
   `SOLEUR_ALLOW_FULL_GATE=1`, which changes what Phase 0.5 must measure.
5. The terraform-cache "zero hits" row was two hits, both benign workflow assertions.

One design defect found by probing bash rather than reading it: a backgrounded brace group keeps
the parent's argv, so every worker would have read as a sibling `test-all.sh` run to any other
worktree — corrupting the sibling census, `--capacity`, and ADR-196's refusal. Fixed with one
token: `( exec "$@" ) &`.

### Decisions
- Three ordered movements behind two go/no-go gates. The Amdahl ratio (`total / longest_suite`)
  and the nested-spawn wall-clock share can each cancel the work before a line is written.
  Reaching a stop verdict is a PASSING outcome and routes to #8045.
- Only suite-body execution becomes concurrent. Accounting, classification, log shape, the
  terminal marker and the exit contract stay serial and in registration order. Per-child rc comes
  from `wait -n -p` (measured returning 143 from a SIGTERM'd child), satisfying ADR-187 §2's
  "directly observed" constraint by construction — which is also why #7554's rc-forgery channel
  cannot arise at this layer.
- Concurrency eligibility is derived, not hand-declared. A hand table with a fail-closed
  drain-barrier default would have left ~420 of 434 registrations demanding an empty pool — a
  parallel mode slower than serial. The classifier reads each suite's own source; a small override
  table covers what it cannot see.
- Fault injection is the correctness gate; repeat runs are an observation. A green-tree repeat run
  cannot detect misattribution (any index->rc mapping satisfies "identical verdict sets" when every
  rc is 0). Five clean runs bound the flake rate only at p < 0.45, so the plan records that
  arithmetic rather than gating on it.
- Nothing but #8231 closes. #7376, #7432, #7454, #7554, #7076, #8045, #6496 stay open with stated
  dispositions; the #7432 `JOBS: 1` removal is named as soak-gated and explicitly NOT done here.

### Collision re-probe (post-plan, per one-shot gate)
Plan frontmatter `closes: 8231` — already cleared at Step 0a.5. One new ref surfaced in the plan
body: #7866, which is a MERGED PR (derived-vs-hardcoded counts prior art), so advisory-only per
the gate's MERGED branch. No new work targets. Gate clear.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents Explore, learnings-researcher,
spec-flow-analyzer, soleur:engineering:cto, dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist; gates lint-guard-contract.py,
lint-infra-no-human-steps.py, c4-count-parity.test.sh, plus deepen-plan halts 4.6-4.11.

## Compound Phase

- Learning: `knowledge-base/project/learnings/2026-09-17-command-v-is-a-resolvability-probe-and-every-guard-i-wrote-to-pin-it-was-narrower-than-its-name.md`
- Session errors inventoried: 14 (5 forwarded from the planning phase), each with a Prevention line.
- Rule budget: `[OK] B_ALWAYS=42640`, linter exit 0. 98 rules, longest 596 chars.
  `constitution.md` at 307 bullets vs the 300 advisory ceiling — flagged, not this PR's to fix.

### Archival DELIBERATELY not run

`compound`'s auto-consolidation archives a feature's plan and spec once the feature is done.
This feature is **not** done: it is descoped to Phase 0 with #8231 OPEN, `tasks.md` carries the
BLOCKED banner, and **36 tasks remain unchecked**. Archiving would move the plan and the spec out
of the live path that the resumption needs.

So `archive-kb.sh` was not run, and that is the decision — not the "an agent driving compound's
phases by hand misses Step E" failure that skill warns about. The precondition for archival is a
COMPLETED feature. When #8231's remaining phases land, archival belongs to THAT branch.

### Resume prompt

The parallel scheduler is blocked on a green baseline, not on design. Phase 0 measured the gate at
**6.22x** (floor 2.0x), so the prize is real and roughly twice the plan's own estimate. What blocks
Phase 1 is that 20 suites are red for reasons unrelated to this work, only ~8 of them
toolchain-adjacent, so fault-injection cannot distinguish "interference reddened this" from
"already red". Re-entry: fix the non-toolchain reds (overlaps #8112), then resume at Phase 1.
