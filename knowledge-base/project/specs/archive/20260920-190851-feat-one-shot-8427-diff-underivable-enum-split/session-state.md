# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-20-fix-compound-promote-diff-underivable-enum-split-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verified: `git diff origin/main...HEAD --name-only` empty; working tree carries only
  `knowledge-base/project/{plans,specs}/` paths. No source, workflow or CHANGELOG edits.
- Integrity verified: all three artifacts are UTF-8 text with zero control characters
  (the subagent reported two control-character injections during authoring and repaired both;
  independently re-checked here rather than taken on report).
- Collision gate re-probed after planning (the gate is point-in-time, not a lock):
  plan frontmatter is `issue: 8427` / `closes: 8427`; #8427 still OPEN, no linked PRs,
  no open or merged body-probe hits. Only #8428 (this pipeline's own draft PR) references it.

### Errors
1. Bad splice while authoring the plan — `index("## Guard Contract")` matched a prose mention
   and destroyed ~200 lines. Reconstructed; later splices match whole heading lines.
2. Control characters injected twice via the Write tool (escape text JSON-decoded into real
   control bytes, rendering the plan a binary file). Repaired both times; verified clean here.
3. One subagent terminated early (`authentication_failed`) during the sharp-edges pass;
   re-spawned and completed.
4. One survey result was wrong — it reported `:240` as an apply-arm row; it is
   `checkDiffPaths("")`. Caught independently by two reviewers and verified against source.
5. `lint-infra-no-human-steps.py` fails repo-wide with 518 PRE-EXISTING findings; the plan file
   contributes zero. Pre-existing, not introduced by this branch.

### Decisions
- Prefix-stable split with one honest exception: the five `underivable-*` values keep the
  `diff-underivable` prefix so existing prefix matches survive; `diff-empty` deliberately does
  not, and that is documented as a RECLASSIFICATION, not backward compatibility — a saved
  Better Stack query stops matching exactly the rows whose meaning changed.
- The empty-diff refusal lives INSIDE `checkDiffPaths`, not at the call site (testability, one
  chokepoint, avoids reformatting a byte-pinned mutation anchor). Deliberate deviation from the
  work target's wording, with reasons recorded.
- Minimisation is a write-channel control, not a disclosure control. At two arms `detail` is a
  model-CHOSEN string, so it is classified against a fixed prefix set rather than relayed.
- The guard census is AST-based, not regex-based; an arm the first draft called untestable is
  covered via a PATH shim.
- Two simplification proposals were NOT applied (cutting `len`/`headerPair`; collapsing the four
  shape fields into one enum). Better designs, but they drop scope the work target named
  explicitly — routed to `decision-challenges.md` as User-Challenges rather than silently cut.

### Most consequential findings
- Sink minimisation was defeated UPSTREAM by two pre-existing truncations.
- `detail` reaches two other sinks bare, one landing in the same Better Stack source.
- The widened row would have crossed Vector's 10,000-character slice and been SILENTLY DROPPED —
  reintroducing the exact blind spot this telemetry exists to close. D4 ("strip, redact,
  classify, then cap") is the response.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: Explore x2,
learnings-researcher, functional-discovery, legal:clo, dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, engineering:cto, security-sentinel, observability-coverage-reviewer,
test-design-reviewer, general-purpose x2; gates: lint-guard-contract.py,
lint-infra-no-human-steps.py, c4-count-parity.test.sh, deepen-plan halts 4.5-4.11.
