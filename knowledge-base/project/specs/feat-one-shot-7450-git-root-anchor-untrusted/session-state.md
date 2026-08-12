# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md`
- Draft PR: #7482
- Closes: #7450 (P0-critical, type/security)
- Status: complete
- Scope verified: `git diff <base>..HEAD --name-only` against base `325a1a5c0` listed only
  `knowledge-base/project/{plans,specs}/` files. No product code touched during planning.

### Collision gate (Step 0a.5 + post-plan re-probe)
- Typed refs checked: #6222 (OPEN), #7426 (MERGED PR — advisory), #7443 (MERGED PR — advisory),
  #7450 (OPEN, work target), #7453 (OPEN). No CLOSED issue refs; abort not triggered.
- #7450 body-probe hits #7443 and #6883 dispositioned by SCOPE intersection (the
  `closingIssuesReferences` discriminator is vacuous for body-probe hits): #6883 empty
  intersection; #7443 intersected only on `preflight/SKILL.md` + `review/SKILL.md`, while all
  five secret-gate anchors remained unmigrated on `main`. Verdict: **citation, not collision**.
- Post-plan re-probe: plan frontmatter `closes: 7450` — no divergence from the cleared target.
  Newly cited refs #5990/#6223/#7418 are CLOSED contextual citations; #7452 is an OPEN related
  follow-up, not a work target.

### Errors
- **4 of 7 review-panel agents failed during deepen-plan.** `security-sentinel` and
  `code-simplicity-reviewer` stalled on the 600s watchdog; `test-design-reviewer` and
  `spec-flow-analyzer` died on API connection errors. This leaves the **core security lens on a
  P0 security plan unreviewed**, plus YAGNI/AC-pruning, mutation-matrix adequacy, and flow /
  dead-end analysis. Recorded in the plan's coverage-gap table. **All four MUST be re-run at
  `/soleur:review` (Step 4) — this is the single most important carry-forward from planning.**
- Guard Contract lint initially failed (Guard 2 matrix missing the `**Mutation matrix**` field
  label the parser scopes to). Fixed; RC=0.
- Plan had an unterminated code fence, which fail-closes `lint-infra-no-human-steps.py`. Fixed.
- A `tasks.md` write was denied by the IaC write-guard on operator-action phrasing. Rephrased
  rather than using the ack opt-out (which would have asserted a review that never happened).
- Three self-authored ACs were mechanically broken and would have failed on `main` (AC1 used
  `git grep -c`, which is per-file not total; AC3 matched ADR-179's own documentation of the
  anti-pattern in `sync.md`; AC11's unscoped count is 2 because one occurrence is a
  must-survive quotation). All corrected.

### Decisions
- **Amend ADR-179; create no new ADR.** The anchor decision AC #1 asked for was already
  ratified — ADR-179 (accepted 2026-08-11) adopted the bare-anchor mechanism, rejected the
  alternatives, and its §R5 names these exact five sites as the subset that "goes first."
  The instrument is therefore *retiring a deferral*, not extending scope. The amendment must
  also replace ADR-179's Decision 2 code block, which ships the `test -d` shape its own
  §(a) Correction measured as bypassable.
- **Stale citation corrected:** the brief's "ADR-177" is wrong. ADR-177 is the test-runner
  result taxonomy; the bare-anchor ADR is **ADR-179**, renumbered from 177 inside commit
  `98ad03aa8`. #7453's GitHub title carries the same wrong ordinal.
- **Bare anchor + mandatory identity preflight with an `exit 2` else branch.** `sync.md` is the
  precedent, NOT `go.md` — `go.md`'s `else` branch does not exit, it continues degraded, and
  copying it onto a secret gate would port a fail-open arm onto the exact control this PR
  hardens. AC5c asserts the exit-2 dispatch, because grepping the condition alone would pass a
  fail-open copy.
- **AC #3 is already satisfied by #7426.** `worktree-manager.sh` now uses a three-level
  in-payload anchor (`$SCRIPT_DIR/../../../scripts/lib/session-state.sh`) to a file that exists
  in the payload. Independently confirmed against `main` before planning began. No work planned.
- **`compound` gets a NON-BLOCKING guard** — it authorises nothing, so fail-closed there is a
  pure operator regression; it stays in scope to preserve the corpus-wide-zero assertion.
- **The two `preflight` git-root sites route to #7453**, but their falsified rationale comment
  is corrected here — leaving a committed argument against the ratified doctrine is rule-corpus
  contamination.
- **A circular-evidence claim was retracted:** `preflight`/`review` were asserted as independent
  skills-surface evidence for the bare anchor, but they landed in the same commit as ADR-179.
  The plan now pays the measurement ADR-179 deferred.
- **Highest-severity finding folded in:** the `linear-fetch` guard as first drafted would have
  converted a refusal into a *leak* — `one-shot` and `brainstorm` are contractually required to
  substitute `persist_safe_summary`, and with it absent they fall back to `agent_context`,
  which carries signed Linear bearer URLs. Both callers added to Files to Edit.

### Sweep result (pre-implementation)
- 6 `:-$(git rev-parse` occurrences: 5 in scope, 1 benign (`--git-common-dir`).
- 45 `SCRIPT_DIR` climbing chains: **zero defects** — 35 test harnesses, 8 in-payload, 2 harness.
- **New site class the brief did not name:** 2 unconditional git-root anchors in
  `preflight/SKILL.md` (routed to #7453).

### Components Invoked
`soleur:plan` · `soleur:deepen-plan` · `soleur:engineering:cto` · `learnings-researcher` ·
`architecture-strategist` · `user-impact-reviewer` · `git-history-analyzer` ·
`security-sentinel` (FAILED) · `code-simplicity-reviewer` (FAILED) ·
`test-design-reviewer` (FAILED) · `spec-flow-analyzer` (FAILED) ·
`lint-guard-contract.py` · `lint-infra-no-human-steps.py` · `probe-verb-gate.sh`
