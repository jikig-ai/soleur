# Tasks — perf(test-all): relevance-gate the C4 producer suite and the .github fixture runner

Plan: [`knowledge-base/project/plans/2026-08-12-perf-test-all-gate-c4-producer-and-github-scripts-plan.md`](../../plans/2026-08-12-perf-test-all-gate-c4-producer-and-github-scripts-plan.md)
Issue: #7494 · Branch: `feat-one-shot-7494-test-all-diff-gate-suites` · Lane: `single-domain`

**Read the plan's Cut List before starting.** An earlier draft proposed a new test suite, a
`skip_suite` pairing check in the linter, and hoisting the c4 suite out of the glob loop. All three
were cut after review proved the pairing check reds a clean tree (`RELEVANCE_ARRAYS` holds file
paths, `skip_suite` takes display labels, and they differ for both existing arrays). Do not
reintroduce them.

---

## 1. Preconditions

- [ ] 1.1 `grep -c '_diff_touches "\${' scripts/test-all.sh` → `2`.
- [ ] 1.2 Run the Phase 0.2 pathspec loop; expect no `UNRESOLVED:` output (all nine, including the
      four directory pathspecs).
- [ ] 1.3 `grep -nE 'git -C "\$REPO_ROOT"|\$REPO_ROOT/[A-Za-z.]' .github/scripts/test/test-*.sh` —
      only `test-infra-suite-registration.sh` and its mutations sibling should read the real tree.
      A third hit means `GITHUB_SCRIPTS_SUITE_PATHS` needs a third element.

## 2. RED — extend the gate harness first (`cq-write-failing-tests-before`)

All in `scripts/test-all-infra-coverage-notice.test.sh`. **Extend; do not fork.**

- [ ] 2.1 Replace `REGISTRY_LABEL` / `CFTUNNEL_LABEL` with the `GATED` table (label|array, four
      rows) and drive every existing loop from it: the `RECORDED_SUITE:` greps in `run_gate_arm`,
      the `check_element_arms` calls, and the `docs-only` / `force-all` / `ci-set` /
      `undeterminable` / `rename-old-path` / denominator arms.
- [ ] 2.2 Add `+ ${#C4_PRODUCER_PATHS[@]} + ${#GITHUB_SCRIPTS_SUITE_PATHS[@]}` to `MIN_ASSERTIONS`.
      It currently enumerates two of four arrays — leaving it reproduces the enumerated-vs-structural
      defect task 5.4 exists to fix.
- [ ] 2.3 Add the `dir-child` arm: `run_gate_arm dir-child 'plugins/soleur/lib/anything.ts'` →
      the c4 suite runs. This is the only assertion the existing harness did not already buy.
- [ ] 2.4 Add two **source anchors** (the seam replaces `_diff_names` wholesale, so a fixture arm
      pins the matcher, not the assembly): the `git ls-files --others --exclude-standard --
      "${TEST_RELEVANCE_PREFIXES[@]}"` line is still present in `$TARGET`, and `plugins/soleur` is
      present in `TEST_RELEVANCE_PREFIXES`. Mirror the existing `--name-status -M` precedent.
- [ ] 2.5 Widen the file header to name its real scope (infra coverage claim **and** ADR-181
      relevance gate).
- [ ] 2.6 Run it — the new arms must FAIL. Do not proceed until they do.

## 3. Declare the predicates — `scripts/lib/test-relevance-paths.sh`

- [ ] 3.1 Add the `HOW TO ADD A RELEVANCE GATE — five sites` block at the top of the file.
- [ ] 3.2 Refresh the stale header ("the two heavy mutation batteries", "guard two run_suite
      calls" — both false at four arrays).
- [ ] 3.3 Add `C4_PRODUCER_PATHS` (6 elements) with its why-comments, the directory-form
      justification, and the `KNOWN LIMIT` paragraph naming `.bun-version` + the likec4 pin trio and
      the degrade's dual nature.
- [ ] 3.4 Add `GITHUB_SCRIPTS_SUITE_PATHS` (4 elements), with the comment explaining why
      `apps/web-platform/infra` is load-bearing and why the SELF entry is dead for matching.
- [ ] 3.5 Add `plugins/soleur` to `TEST_RELEVANCE_PREFIXES`.

## 4. Wire the two gates — `scripts/test-all.sh`

- [ ] 4.1 Gate the c4 suite **in place** inside the `plugins/soleur/test/*.test.sh` glob loop, with
      a **literal** label and **nested `if` blocks** (never `[[ … ]] && continue` — the form
      `_diff_touches`'s own header forbids). Leave `run_suite "$f" bash "$f"` byte-for-byte
      unchanged.
- [ ] 4.2 Convert the `.github/scripts/test/run-all.sh` registration to the ADR-181 if/else,
      preserving the `run_suite … bash <path>` command shape `REQUIRED_RUNNERS` anchors on.
- [ ] 4.3 Extend the `MIN_SUITES` floor comment: a decline is a different outcome from an empty run,
      and the floor is not evaluated at all when the runner is declined.
- [ ] 4.4 Print the force-all lever in the epilogue when `skipped > 0`:
      `SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh`. Today the variable appears once in the
      whole runner and is printed nowhere, while a docs-only run now declines five suites.

## 5. Linter fixes — `scripts/lint-orphan-test-suites.sh` (5.1–5.3), harness (5.4)

- [ ] 5.1 Add both entries to `RELEVANCE_ARRAYS`. All **five** existing per-array checks then apply
      for free.
- [ ] 5.2 Add the **derived** dispatch floor (`want=$(grep -cE '_diff_touches "\$\{[A-Z_]+\[@\]\}"'
      "$RUNNER")`), not a literal `4`, plus the `${RELEVANCE_ARRAYS[@]+"${RELEVANCE_ARRAYS[@]}"}`
      guard on the loop below it (bash 3.2 `set -u`).
- [ ] 5.3 Add the `TEST_RELEVANCE_PREFIXES` coverage check inside the per-array loop. This is the
      only guard buying a property nothing else buys.
- [ ] 5.4 In `scripts/test-all-infra-coverage-notice.test.sh`: re-point the `a CI run declines
      neither battery` assertion from `($REGISTRY_LABEL|$CFTUNNEL_LABEL)` to "no `(relevance)`
      decline under `CI=1`"; capture `CI_GATE_OUT="$GATE_OUT"` right after the `ci-set` arm. The
      `MIN_FIXED` delta is **zero** unless a second assertion is genuinely added.

## 6. GREEN and mutations

- [ ] 6.1 `bash scripts/test-all-infra-coverage-notice.test.sh` passes.
- [ ] 6.2 `bash scripts/lint-orphan-test-suites.sh` prints `orphan test suites: none`.
- [ ] 6.3 Guard 1 matrix M1–M4 — each reddens the linter **with its own named message**, reverted
      between rows, green after the last. M1 against the linter only (an empty array crashes the
      full runner under bash 3.2 `set -u` — a crash is not a verdict).
- [ ] 6.4 Guard 2 matrix N1–N6 — each reddens the harness; revert and re-green between rows.

## 7. ADR amendment

- [ ] 7.1 Add `## Addendum — 2026-08-12 (#7494)` to
      `ADR-181-local-gate-declines-are-counted-verdicts.md`. **Append-only — do not edit the body
      in place** (the corpus convention; ADR-181 itself wrote a dated addendum into ADR-177).
- [ ] 7.2 The addendum carries all seven items from the plan's `## Architecture Decision`:
      the extended gated set + predicate-shape rule; `N-3/N` → `N-5/N`; mitigation layer 3 does not
      generalise to a degrading suite (plus the re-run-command-can-exit-green corollary); the
      dispatch-floor and prefixes soundness gaps; the five-site declaration contract; the two
      rejected alternatives; and the ceiling-qualified absolute saving + asymmetric CI protection.

## 8. Verification and the deferral

- [ ] 8.1 Re-replay both skip rates with `grep -F`-over-blob semantics for the predicates **as
      declared**; record as ceilings.
- [ ] 8.2 Time both suites in isolation; capture the c4 render markers (`status=ok`,
      `relationships=3`, no `reason=likec4-unavailable`). Wall-clock is disclosure, never a gate.
- [ ] 8.3 `bash scripts/test-all.sh` explicitly (lefthook's `bun-test` glob never fires on a
      `.sh`-only PR). Both newly-gated suites must be shown **running** — this PR edits
      `scripts/lib/test-relevance-paths.sh`, which both arrays declare.
- [ ] 8.4 `gh issue create --label deferred-scope-out` for the `apps/web-platform` deferral,
      carrying: the D3 scoping, the 51 % counterfactual + its command, the dead-trigger note, both
      unsoundness findings, D5's runtime observation, the **open question** of whether the ~60
      `server/inngest/cron-*.test.ts` files move (it decides whether 51 % holds), the fact that the
      app-local share of 516 s is **unmeasured**, and a back-reference to `#7494`.
- [ ] 8.5 Write the new issue number into the ADR addendum and into the plan's D3.

## 9. Ship

- [ ] 9.1 Verify all six ACs.
- [ ] 9.2 PR body carries `Closes #7494`, the measured numbers from 8.1/8.2 as ceilings, and both
      mutation transcripts.
