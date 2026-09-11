# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-09-feat-battery-tag-author-guard-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- **Self-inflicted, recovered:** an MD038 cleanup regex used `\s`, which matched newlines and joined
  lines across a table and a fence. The recovery (`git checkout --`) then discarded ~a dozen
  uncommitted deepen-plan edits. All were redone edit-by-edit with independent hit/miss reporting.
  **Prevention:** commit before a bulk regex; never `\s` inside a single-line code-span pattern.
- The `post-edit consistency audit` subagent stalled in a self-imposed "wait for file stability"
  loop, returning no findings across ~10 minutes; it could not be stopped (ownership). The sweep was
  performed manually instead — stale identifiers, AC numbering, literal drift and numeric
  self-consistency all verified clean. **Prevention:** give a delegated audit a bounded, terminating
  instruction; never a "wait until stable" predicate with no clock.
- Two commits blocked by markdownlint MD038; fixed at the source rather than bypassed.
- **Parent-side (this session), for the record:** the parent read the plan's `396` as stale by
  measuring `--enumerate | wc -l` (397) instead of anchoring on `^SUITE_REGISTRATION` (396). The
  plan was correct; the instrument was not. A control run is what caught it before the "correction"
  propagated. Same class as the six broken instruments in the softening session.

### Decisions

- **The property was reframed — the plan's load-bearing decision.** "No battery `git fetch` writes
  tags into the *live* repo" is not statically decidable: CWD is set by callers frames away.
  Demonstrated by `.claude/hooks/ship-runbook-ssh-gate.sh`, which IS battery-executed yet safe only
  via a `cd` three frames up — which is precisely why two prior passes disagreed. The guard instead
  asserts a DECLARATION-based property: every tag-authoring command is either suppressed on its own
  command line or carries a declared exemption in the `-B2` window.
- **Scope moved from a verb to a class.** ADR-207 cell 6 softens a tag creation by ANYTHING, so a
  fetch-scoped guard is green over `git pull` (two live sites in the file ADR-207 itself names) and
  over a suite's direct `git tag -a`.
- **A `SCOPED` verdict was designed, then deleted as fail-open** — `git -C ""` is a documented
  no-op, measured directly (`git -C "" rev-parse --show-toplevel` prints the enclosing repo).
- **Constraint 1 honoured by a stronger mechanism than prescribed:** `scripts/test-all.sh
  --enumerate` (pre-existing, from the await-ci ceiling work) already walks the real registration
  path and takes NO lock. Two reviewers argued for cutting its use; refused, because "never
  hand-type it" is the operator's stated direction — but their P0 was adopted: it must set
  `_ENUMERATE=1`, since nine sites gate that mode and one is the entire "takes no lock" property.
- **Measurement stays the deliverable.** A plan-time reconnaissance adjudicated 0 live-repo
  offenders; recorded explicitly as NOT adopted as a verdict, because it is a third static
  adjudication of the kind that already produced two contradictory answers.

### Components Invoked

`soleur:plan`, `soleur:deepen-plan`; agents: repo-research-analyst, learnings-researcher,
general-purpose measurement walk, `soleur:engineering:cto`, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, test-design-reviewer, spec-flow-analyzer,
best-practices-researcher, general-purpose consistency audit (stalled); gates:
`lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `probe-verb-gate.sh`, markdownlint, plus
baseline runs of `guard-vacuity-floor.test.sh`, `lint-orphan-test-suites.sh`,
`scripts-shard-totality.test.sh`, `repo-write-boundary.test.sh`, `c4-count-parity.test.sh`.

## Collision Gate (one-shot Step 0a.5) — override recorded

PR #7908 surfaced as a MERGED PR linked to OPEN #7917. The two prescribed discriminators DISAGREED:
`closingIssuesReferences`=[7795] (citation, so continue) against a 4-path scope intersection
(collision, so abort-by-default, which wins on a dedupe hit). Overridden on measured evidence: no
guard file exists on main, no suite sweeps the root set, and PR #7908's diff added none — so #7917
is unimplemented and this is the documented cited-predecessor false positive: PR #7908 FILED it.
The second body-probe hit, PR #4778, discriminated clean (0-path intersection).
`linear-fetch` was NOT fired: the preflight regex matches `ADR-207`, a repo-internal decision
record, not a Linear ID.
