# Tasks — feat-one-shot-7578-ap021-claim-blind-spot

Plan: `knowledge-base/project/plans/2026-08-19-fix-ap021-gate-operator-line-and-claim-blind-spots-plan.md`
Closes: #7578, #7318

## Phase 1 — Fixtures first (RED before GREEN)

- 1.1 Read `scripts/lint-diagnosis-claims.test.sh` fixture convention (`LINT_DIAGNOSIS_ROOT`
      + `LINT_DIAGNOSIS_MIN_FILES=1` over a temp tree — fixtures are built in-suite, not
      committed as files).
- 1.2 Add RED fixture: `DETAIL="… — Better Stack unreachable / creds unset"` (verbatim).
- 1.3 Add RED fixture: `NIC_DETAIL="…"` sibling, placed after a compliant assignment
      (second-member row — a check that stops at the first member is the class defect).
- 1.4 Add RED fixture: continuation-line carrier `|| degraded sign "$?" "… is the fix"` (#7318).
- 1.5 Add must-PASS fixture H3: measured dash-appendix carrying `# MEASURED-BY:`.
- 1.6 Add must-PASS fixture H4: interpolating appendix `http=$code — (zot unreachable)`.
- 1.7 Confirm 1.2–1.4 RED and 1.5–1.6 GREEN **before** editing the scanner.

## Phase 2 — Widen OPERATOR_LINE

- 2.1 Add assignment alternative `^\s*(?:local\s+|export\s+|readonly\s+)?[A-Za-z_][A-Za-z0-9_]*="`.
- 2.2 Un-anchor the helper-call alternative for `||`/`&&`/`;`/`|` continuations (#7318).
- 2.3 Comment each with its measured yield (+1 each), matching the file's existing style.

## Phase 3 — Widen CLAIM

- 3.1 Add static-prose appendix alternative `[—–][^"$]{0,60}?\b(?:<closed predicate list>)\b`.
- 3.2 Document why the `$`-exclusion and 60-char bound are load-bearing (measured 19→10) and
      why the predicate list is CLOSED.

## Phase 4 — Triage the 10 newly-visible lines

Per the plan's disposition table. Nine `MEASURED-BY:` annotations naming the specific
measuring variable, one reword (`git-data-bootstrap.sh:265`, which names a consequence not a
cause). Do **not** touch `scripts/followthroughs/zot-soak-6122.sh:319` — that is the
pre-existing baselined `1`.

- 4.1 `.github/workflows/reusable-release.yml:1378`
- 4.2 `apps/web-platform/infra/ci-deploy.sh` ×3 (1673, 2565, 2614)
- 4.3 `apps/web-platform/infra/git-data-bootstrap.sh:265` — reword
- 4.4 `apps/web-platform/infra/inngest-bootstrap.sh:984`
- 4.5 `scripts/followthroughs/hostname-mislabel-web1-6616.sh:102`
- 4.6 `scripts/sync-readme-counts.sh` ×2 (50, 52)
- 4.7 `scripts/zot-restart-loop-alarm.sh:387`

## Phase 5 — Hold the ratchet

- 5.1 Leave `.highwater` at `1`.
- 5.2 Extend its comment: the widening, per-alternative measured deltas, and an explicit
      statement that the SCOPE carve-out was available and deliberately NOT used.

## Phase 6 — ADRs

- 6.1 Amend ADR-166 `## Decision` (AND-of-two-filters reasoning; carrier *syntaxes* not
      accumulated alternatives) and `## Alternatives Considered` (CLAIM-only widening, with
      the measurement showing it misses the motivating line).
- 6.2 Add an ADR-187 §Scope pointer closing the deliberately-deferred loop.

## Phase 7 — Verify

- 7.1 Full suite green; each mutation row individually RED (AC2, AC3, AC6).
- 7.2 `bash scripts/lint-diagnosis-claims.sh` exits 0 on the live tree.
- 7.3 `python3 scripts/lint-guard-contract.py`.
- 7.4 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (its own
      invocation — it derives its input set; do not hand-enumerate paths).
