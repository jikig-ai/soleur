---
feature: cloud-init-strip-helpers-extraction
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-18-refactor-cloud-init-strip-helpers-extraction-plan.md
created: 2026-09-18
---

# Tasks — extract the cloud-init strip helpers (#7968)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No edits under
`apps/web-platform/infra/`. Two files change: one edited, one created.

## Phase 0 — Preconditions (measure)

- [ ] **0.1** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → `47 pass / 0 fail`.
- [ ] **0.2** Save the 47 titles: `grep -oE '^\s*test\("[^"]+"' <file> | sort > /tmp/titles.before`.
- [ ] **0.3** If the three `.tf` files moved on `origin/main` since the merge-base, re-run the
      anchor/definition uniqueness probe (plan §Problem Statement); proceed only on 1/1 and no `\\`.

## Phase 1 — Failing fixture arms first (`cq-write-failing-tests-before`)

- [ ] **1.1** Add `describe("shared strip helpers are structural (#7968)")` with arms A1–A9 (plan
      §The fixture arms) over synthetic `x_`-host HCL strings; A5–A8 mirror the inngest hoisted-locals
      chain, A9 the registry `user_data = base64gzip(replace(templatefile(` shape.
- [ ] **1.2** `bun test` is RED: `extractStripRegex` / `stripIsApplied` undefined.

## Phase 2 — GREEN: two shared functions, six wrappers

- [ ] **2.1** Add `STRIP_LITERAL_RE` and `extractStripRegex(tfSrc, localName, fileLabel)` per plan
      §Proposed Solution (left-anchored pattern, comment-strip first, exactly-one, slash + `(?m)`,
      universal `\\` refusal).
- [ ] **2.2** Add `stripIsApplied(tfSrc, anchorRe, localName, chain = [])` (comment-strip first,
      zero anchors → `false`, more than one → throw, balance from the anchor's first `(`,
      `local.<name>\b` inside the span, every chain link).
- [ ] **2.3** Replace the six bodies with one-line `const <name> = (tf: string) => …` wrappers (one
      space around `=`); inngest predicate passes its two chain regexes; add the anchor-contract docblock.
- [ ] **2.4** Move the M3/M4b/M14 rationale docblocks onto the two shared functions once.
- [ ] **2.5** `bun test` → `56 pass / 0 fail`; `git diff` shows no change inside the
      `rendered user_data size` describe block.

## Phase 3 — Mutation battery

- [ ] **3.1** Create `plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` in the
      `kb-index-check-guard-mutation.test.sh` shape (header, prelude, `mktemp -d` scratch tree three
      dirs deep with `apps/web-platform/{infra,Dockerfile,.dockerignore}` symlinked, one comment
      naming the depth invariant).
- [ ] **3.2** Implement `run_suite`, `mutate` (function-scoped python substitution, `count == 1`,
      RETURNS 2 on a missing anchor / zero-byte edit), `expect_red` (rc ≠ 0, named `(fail)` arm,
      no `error` line, `Ran N` == pristine), `expect_green`.
- [ ] **3.3** Control precondition (exit 2 on failure): pristine copy green, `Ran 56`, walker arm in
      the pass list.
- [ ] **3.4** Rows R1, R2, R3, R4, R6 and H1, H2, H3 exactly as the plan's Guard Contract; `CASES`
      counter before each assertion; final `rows=8 ok=8`; exit 1 on any mismatch.
- [ ] **3.5** `bash plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` → exit 0,
      `rows=8 ok=8`.
- [ ] **3.6** `git add` the suite, then `bash scripts/lint-orphan-test-suites.sh` exits 0 and
      `bash scripts/test-all.sh --print-suite-globs` expands over it.

## Phase 4 — Verification

- [ ] **4.1** AC1–AC11 in the plan, each by its stated command (merge-base diffs, scoped
      `git status`).
- [ ] **4.2** `grep -cF '((?:[^"\\]|\\.)*)' <file>` = 1; the `^const … _(FLOOR|BUDGET) =` lines are
      unchanged against the merge-base.
- [ ] **4.3** Do not run `scripts/test-all.sh` here; `/ship`'s full-battery checkpoint does.
