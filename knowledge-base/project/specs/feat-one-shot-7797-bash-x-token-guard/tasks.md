# Tasks — feat-one-shot-7797-bash-x-token-guard

**Plan:** `knowledge-base/project/plans/2026-09-04-fix-bash-x-secret-trace-guard-plan.md`
**Issue:** #7797
**Lane:** `procedural`

> Lane note: no `spec.md` exists for this branch (it entered at `plan`, with no
> preceding brainstorm), so there was nothing to carry forward. `procedural` is
> taken from the plan's own frontmatter rather than defaulted to the fail-closed
> `cross-domain`, because the domain question was answered twice by measurement:
> plan Phase 2.5 found engineering-only, and plan-review's independent
> relevance gate separately found zero UI-surface paths in Files to
> Create/Edit. Recorded here so the deviation from the default is visible.

## Phase 0 — Preconditions (DONE 2026-09-04)

- [x] 0.1 Run the always-loaded budget authority; verdict `B_ALWAYS=46000`
      (at the ratchet) → the `AGENTS.md` rule edit is dropped.
- [x] 0.2 Confirm highwater/baseline prior art (4 `.highwater` + 2 baseline).
- [x] 0.3 Confirm `--changed --base REF` is opt-out (`New untracked docs count`).
- [x] 0.4 Measure the remediation subset: 22 readers of `SENTRY_AUTH_TOKEN` /
      `BETTERSTACK_API_TOKEN*`, 1 already compliant, 0 test files.
- [x] 0.5 Measure the `exit 64` collision: 57 files already use it as `EX_USAGE`.
- [x] 0.6 Read the sweeper's exit contract and its `env -i` invocation.
- [x] 0.7 Run `lint-guard-contract.py` and `lint-infra-no-human-steps.py` on the
      plan; both exit 0.

## Phase 1 — ADR + principles register

- [ ] 1.1 Determine the next free ADR ordinal across **every** `origin/*` ref,
      not just `origin/main`.
- [ ] 1.2 Write the ADR at the general altitude: enforce a runtime-STATE hazard
      with a self-refusal the artifact carries, gated at commit time by a walker
      over every member — not with a boundary interceptor that must enumerate
      the ways to reach that state.
- [ ] 1.3 Cite ADR-198 and commit `223da596f` (same credential class, argv
      vector) and carry Correction 3, so the two are not later read as
      duplicates.
- [ ] 1.4 Add the matching AP row to
      `knowledge-base/engineering/architecture/principles-register.md`.
- [ ] 1.5 Re-verify the ordinal immediately before merge and sweep every
      artifact citing it if it moved.

## Phase 2 — Mutation matrix, written first

- [ ] 2.1 Encode mutation rows 1–8 and harness rows H1–H4 as executable cases
      **before** the lint exists, derived from the design.
- [ ] 2.2 Build the fixture corpus under `scripts/fixtures/shell-trace-refusal/`:
      per-class secret-signal fixtures, preamble-at-line-200, `set -x`-below-
      preamble, malformed input, populated-credential escape-hatch, and the two
      must-PASS fixtures (non-canonical compliant; excluded `*.test.sh`).

## Phase 3 — The lint

- [ ] 3.1 Walker over every tracked `*.sh`, structurally reused from
      `lint-trap-tempfile-ownership.py`; add `--changed --base REF`.
- [ ] 3.2 **Rule A (prologue):** the preamble must appear within the first
      executable lines, before any command other than `set`/`shopt`.
- [ ] 3.3 **Rule B (below-preamble):** no trace-enabling token after the
      preamble line. Maintain `TRACE_TOKENS` as an explicitly-named member list.
- [ ] 3.4 `SECRET_SIGNALS` = 4 classes; `doppler run` is **excluded** (it binds
      nothing in the parent).
- [ ] 3.5 Escape hatch: refuse only when a signal-named variable is non-empty;
      the refusal message names the path (`re-run with SENTRY_AUTH_TOKEN= to
      trace safely`).
- [ ] 3.6 Scope exclusions with recorded reasons: `*.test.sh` and `tests/**`
      (synthesized fixtures; most in need of traceability), `scripts/lib/*.sh`
      (a sourced `exit` kills the parent).
- [ ] 3.7 Exit codes 0/1/2 mirroring `lint-credential-path-literals.py`;
      unparseable → 2, scoped to the scanned set.
- [ ] 3.8 Violation output names the file, the offending line, and emits
      paste-ready preamble text.
- [ ] 3.9 Add a `--mutate N` mode so CI can re-run the matrix.

## Phase 4 — Remediation

- [ ] 4.1 Add the preamble to the 21 non-compliant credential readers, using
      exit **78** (`EX_CONFIG`), not 64.
- [ ] 4.2 Update `cutover-verify.sh`'s exit code to 78 for consistency.
- [ ] 4.3 Comment the `SHELLOPTS` arm as belt-and-braces (unreachable in bash,
      since `env SHELLOPTS=xtrace` already sets `x` in `$-`) so the next reader
      does not delete the load-bearing `$-` arm.
- [ ] 4.4 Scrub `^\+` lines from captured output in
      `scripts/sweep-followthroughs.sh` before `gh issue comment`.
- [ ] 4.5 Document exit 78 in
      `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.

## Phase 5 — Enumerated baseline

- [ ] 5.1 Generate the baseline **after** Phase 4, as an enumerated path list
      (precedent: `lint-window-closure-assertion.allowlist.txt`), not an integer.
- [ ] 5.2 Assert the baseline contains none of the 22 credential readers.
- [ ] 5.3 Record the drawdown trigger in the file header: any PR that edits a
      listed script must remediate it, enforced by `--changed`.

## Phase 6 — Wiring

- [ ] 6.1 Add the explicit `run_suite` line to `scripts/test-all.sh`
      (`scripts/*.test.sh` is **not** glob-covered).
- [ ] 6.2 Wire the lint into `ci.yml`.
- [ ] 6.3 Add it to `scripts/required-checks.txt` and the ruleset — **blocking,
      not advisory**; the #6049 auto-fabrication content gate applies.

## Phase 7 — Verification

- [ ] 7.1 Run the suite; record the assertion floor from a **measured** green
      run after Phase 4, asserted via a direct `exit 1`.
- [ ] 7.2 Drive every mutation row RED against a pristine copy; restore.
- [ ] 7.3 Assert the malformed fixture exits **exactly 2**.
- [ ] 7.4 Assert a traced probe's output cannot reach an issue-comment body.
- [ ] 7.5 Run `lint-orphan-test-suites.sh`, `lint-guard-contract.py`, and the
      full battery; read the rc file directly rather than inferring from a
      marker line.

## Phase 8 — Follow-ups (each with a re-evaluation trigger)

- [ ] 8.1 PreToolUse hook — residual: ad-hoc `bash -c` and uncommitted scripts.
      Trigger: a second trace-leak from an uncommitted script.
- [ ] 8.2 CI form lint (Guard 2), sibling to `lint-workflow-errexit-capture.py`,
      with its own Guard Contract. Trigger: the first workflow that enables
      tracing.
- [ ] 8.3 argv→stdin sweep, with the **corrected** rationale: it defends the
      traced-caller shape, which no callee preamble can. Trigger: any PR
      touching a listed caller.
