---
feature: feat-one-shot-7091-prod-version-drift-alert
issue: 7091
plan: knowledge-base/project/plans/2026-08-01-feat-prod-version-drift-alerter-plan.md
date: 2026-08-02
---

# Pre-merge Acceptance Evidence (#7091)

Each row records the command that was RUN and what it returned — not a restatement of the
criterion. Plan ACs 1–18 (`## Acceptance Criteria` → `### Pre-merge (PR)`).

| AC | Criterion | Command | Result |
| --- | --- | --- | --- |
| 1 | suite exits 0, `Total` ≥ `MIN_ASSERTIONS` | `bash scripts/prod-version-drift-check.test.sh` | **exit 0**, `Total: 102 Pass: 102 Fail: 0` (A=53 B=38 C=11), floors `MIN_ASSERTIONS=102` + per-part `A=53 B=38 C=11` |
| 2 | Part A covers the fixture table, each asserting an EXIT CODE | `DRIFT_TEST_PARTS=A bash …test.sh` | **53 PASS**, covering A1–A25 (a superset of the plan's A1–A17); every row asserts `$rc`. A21–A25 drive `main()`, which had zero coverage until the review |
| 3 | Part C: 10 axes, each mutation asserted LANDED, control green FIRST | full suite run | `C0 unmutated control is GREEN` printed before any axis; all 10 axes caught, and each now names the assertion it targets — axis 2 was VACUOUS (a syntax-error mutant caught by A0, never by B8) until the review |
| 4 | axis 3 — dropping `--first-parent` goes red | Part C | `C-axis3-drop-first-parent … caught (child exit 1)` |
| 5 | axis 4 — newest-commit clock fails A6 | Part C | `C-axis4-newest-not-oldest … caught (child exit 1)` |
| 6 | axis 5 — bare `!cancelled()` fails B3 **and** B4 | Part C | `C-axis5-bare-not-cancelled … caught (child exit 1)` |
| 7 | axis 6 — deleting the label bootstrap fails B5 | Part C | `C-axis6-drop-label-bootstrap … caught (child exit 1)` |
| 8 | axis 7 — deleting close-on-recovery fails B6 | Part C | `C-axis7-drop-close-on-recovery … caught (child exit 1)` |
| 9 | axis 9 — `fetch-depth: 1` fails B2 | Part C | `C-axis9-fetch-depth-1 … caught (child exit 1)` |
| 10 | orphan-suite lint clean | `bash scripts/lint-orphan-test-suites.sh` | **exit 0**, `orphan test suites: none` |
| 11 | step-env-ref lint clean **with the new workflow in scope** | `python3 scripts/lint-workflow-step-env-refs.py` | **exit 0**, `0 findings across 71 workflow file(s)`. Scope PROVEN by removal: the same command reports **70** with the new file moved aside, so it is genuinely parsed rather than assumed |
| 12 | encryption-posture repo sweep clean | `python3 scripts/lint-encryption-posture.py --repo-sweep` | **exit 0**, `16 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS` |
| 13 | `actionlint` clean; `bash -n` on each extracted `run:` body | `actionlint` on both workflows; PyYAML-extracted bodies | actionlint **rc=0**; all **6** extracted `run:` bodies pass `bash -n` |
| 14 | line 1 carries the gate-override marker | `head -1 …/scheduled-prod-version-drift.yml` | `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` |
| 15 | `sentry-monitor-iac-parity.test.ts` passes (slug parity) | `vitest run …/sentry-monitor-iac-parity.test.ts` | **exit 0** (bundled run: 3 files, 32 tests passed) |
| 16 | `c4-code-syntax.test.ts` + `c4-render.test.ts` pass | `vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` | **exit 0**, 32 tests passed; `model.likec4.json` regenerated (65 elements, 125 relations, 67 views) |
| 17 | three historical cases as OFFLINE fixtures; NO live-network assertion pre-merge | quoted-string-stripped scan for `curl`/`wget` at command position; `main()` call scan | **0 network invocations**; `main()` is never invoked — the suite drives only `classify_drift` and `oldest_epoch_from_log`. The four `curl` hits are assertion *description strings*, not calls |
| 18 | `bash scripts/test-all.sh scripts` exits 0 (the gate's own invocation) | `bash scripts/test-all.sh scripts` | **rc=0** read from the rc FILE (not a background notification), terminal marker `=== 235/235 suites passed ===`, `scripts/prod-version-drift-check` `[ok]` in 5718ms |

## Coverage boundary — the runner that AC18 does NOT cover

`test-all.sh` announced in its own preamble:

> `NOTE: your diff touches apps/web-platform/infra/, which this runner does NOT cover.`

This diff edits `apps/web-platform/infra/sentry/cron-monitors.tf`, so AC18's green is evidence
for less than the whole diff. The authoritative runner for that directory is
`apps/web-platform/infra/run-registered-suites.sh`, which DERIVES its suite list from
`.github/workflows/infra-validation.yml` and reports unregistered orphans — an ad-hoc
`for f in infra/*.test.sh` loop is not the CI-registered set. It was run separately; see the
Infra runner row below. (`terraform fmt -check apps/web-platform/infra/sentry/` also passes.)

| Runner | Result |
| --- | --- |
| `apps/web-platform/infra/run-registered-suites.sh` | **rc=0** read from the rc FILE, terminal marker `=== registered infra suites: 87 passed, 0 failed (of 87) ===`, no unregistered orphans reported |
| `terraform fmt -check apps/web-platform/infra/sentry/` | **rc=0** |

## Two defects this evidence pass would have missed, and what caught them

Both are the same class — **a text gate cannot distinguish code from prose** — and neither is
visible in a green suite, because in each case the suite WAS green for the wrong reason.

1. **B3/B4/B5 false-failed on the workflow's own comments.** The Part B extractor greps step
   bodies, and comments are part of a body. A comment naming `gh issue create` above the label
   bootstrap made the ordering pin read the prose as the call site.
2. **Axes 3, 4 and 9 SURVIVED against a correct artifact.** Each mutator rewrote the FIRST
   occurrence of its token, and each token is documented in a comment ABOVE the code that uses
   it — so the sabotage landed in prose and the real code was untouched. A mutation that cannot
   reach the property is not evidence about the property. The mutators now skip comment lines.

   The same pass found **B8b was genuinely vacuous**: `grep -c -- '--first-parent'` counts
   comment mentions, so it stayed green with the flag deleted from the git invocation as long as
   any comment still named it. It is now anchored on the command shape
   (`^[^#]*git (log|rev-list)[^|]*--first-parent`), which a `#`-leading line cannot satisfy.

## Post-review corrections (2026-08-02)

Two rows above were recorded before the sanitiser commit and never re-derived, so they
understated the suite (75/75 and 35) — failing the standard this file's own preamble sets. They
are corrected against a fresh run rather than edited to look consistent.

The review itself is the substantive addendum: ten agents found the alarm could go silent four
independent ways, all in the alerting state machine rather than the classifier, and 16 of 20 new
mutations survived the then-green suite. The fixes and their evidence are in commit
`68ff78602`; the mutation-proofs are reproducible from the assertions named there.

Two figures worth carrying forward because they were MEASURED and contradicted in-repo comments:

- GHA `schedule:` delivery on this repo: 59 consecutive `*/30` runs, min 61 / median 114 /
  max 243 minutes apart, **0 within the nominal+margin window**. This refutes the
  `margin == interval` rationale that two sibling monitors still rely on (pre-existing, out of
  scope here, tracked in the follow-up).
- `--first-parent` changes the answer on **279 of 800** on-chain bases. It is not the "verified
  no-op" the original comment claimed.
