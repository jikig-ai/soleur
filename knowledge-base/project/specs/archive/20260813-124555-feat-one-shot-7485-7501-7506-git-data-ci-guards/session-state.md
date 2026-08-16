# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-12-fix-git-data-evidence-hash-and-ci-guards-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: `git diff origin/main...HEAD --name-only` → plans/ + specs/ only. No product code touched during planning.
- Collision re-probe (post-plan): plan frontmatter `closes: [7485, 7501, 7506]` matches the invoked targets exactly — no plan-discovered re-target, so no additional gate run was required.

### Errors
None blocking. Three self-corrections were caught before the plan was finalised:

- The plan's own first-draft #7485 fix introduced a fail-open: aborting only on the payload
  loop left the identical silent drop on the sibling glob while deleting the arithmetic that
  responded to it. Measured — an unreadable sibling returned `rc=0` with a *different* hash.
  Corrected to abort on both conditional loops, plus `*.tf.json` coverage.
- The #7506 defect shape was wrong. Both the plan and the security reviewer described a
  self-satisfying green; measured, the guard reopens *again* (its body satisfies field 1 but
  not fields 2 or 3), so the real hazard is an unbounded reopen loop. Two further selector
  defects surfaced with it: an unpaginated fetch and an attacker-authored issue-body fallback.
- The `bash -e` premise was inverted. The plan pinned `--noprofile --norc -eo pipefail`; the
  repo's own linter records that a step with no `shell:` key runs `bash -e {0}`. Two repo
  files contradict each other on this; the wrong one is corrected in-scope.

Two `python3` heredoc edit scripts aborted on a failed assertion before writing — no partial
state; both re-ran cleanly.

### Decisions
- #7485 fix reshaped from "correct the arithmetic" to "delete it": abort where the drop
  happens, on both loops, with the floor moved onto a payload count. Prototype-verified —
  `rc=0` on the live tree, correct aborts on five mutation shapes, existing suite 58/58
  unchanged (which is itself the proof the fixture was blind).
- Three mechanisms cut after two reviewers converged independently: the third `inconclusive`
  counter (zero mechanical delta against `fail()` once it exits non-zero), the ADR-177
  amendment (its substantive point already exists verbatim in ADR-177), and the retrying
  image pre-pull (the image is already local by R4).
- `inconclusive` stays non-green. The nested runner prints `PASS` for any suite exiting 0 and
  dumps diagnostics only on RED, so a skip-and-pass would be laundered. Recorded as DC-2,
  diverging from #7501's literal wording with the measurement behind it.
- The revert-cleanliness argument was withdrawn, not weakened: `main` is squash-merged
  (200/200 single-parent), so in-branch commit ordering does not survive. DC-1 presents the
  split recommendation without a false mitigation.
- Scope held against four expansions — image pre-bake, the rehearsal workflow's 10-paid-minute
  retry poll, symlink/`realpath` containment, and two closure-guard field weaknesses — each
  filed with its measurement rather than absorbed.

### Components Invoked
- `soleur:plan` → `soleur:plan-review` → `soleur:deepen-plan`
- Planning gates: premise validation, mechanism-minimality, value-proposition measurement,
  skeleton checkpoint, code-review overlap, domain review, Guard Contract (2.12),
  observability (2.9/2.9.2), ADR/C4 (2.10)
- Deepen halts: 4.5 (n/a), 4.6, 4.7, 4.8, 4.9 (n/a), 4.10 (n/a), 4.11 — all passed
- Agents: `soleur:engineering:cto`; review panel `dhh-rails-reviewer`,
  `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`,
  `spec-flow-analyzer`; deepen pass `test-design-reviewer`, `security-sentinel`,
  `git-history-analyzer`, verify-the-negative sweep; three `Explore` agents
- Linters: `lint-guard-contract.py`, `lint-infra-no-human-steps.py --changed --base origin/main`
