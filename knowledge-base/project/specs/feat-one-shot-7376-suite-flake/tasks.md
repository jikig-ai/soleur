---
title: "Tasks — -P 4 parallel infra-suite flake close-out (#7376)"
plan: knowledge-base/project/plans/2026-10-20-fix-7376-parallel-suite-flake-attribution-plan.md
issue: 7376
branch: feat-one-shot-7376-suite-flake
lane: cross-domain
date: 2026-10-20
---

# Tasks — #7376 close-out

Derived from `2026-10-20-fix-7376-parallel-suite-flake-attribution-plan.md`. Read the
plan's **Hypotheses & Verdicts**, **Mechanism Minimality Cut List**, and the CTO rulings
in `decision-challenges.md` before starting — several obvious-looking changes are
explicitly rejected (memory-derived `JOBS` cap; bare-`/tmp` write prohibition;
`/tmp/rung2` fix; mandatory local taskset battery).

## Phase 1 — Namespacing fixes (three audited sites)

- [x] 1.1 `apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh:40` —
      `MARKER="$(mktemp -u)"` → `MARKER="$(mktemp)"`. The stub `touch`es the path;
      `touch` on an existing file is identical observable behaviour.
- [x] 1.2 `apps/web-platform/infra/ci-deploy.test.sh:6462` — `st=$(mktemp -u)` →
      derive from the already-unique `pf` (`st="${pf}.state"`) or an owned `mktemp -d`
      dir; property is "name unpredictable and unclaimed", not "name absent".
- [x] 1.3 `apps/web-platform/infra/inngest-redis-luks.test.sh:176` —
      `/tmp/.ilt-block.$$` → `"${TMPDIR:-/tmp}/.ilt-block.$$"` (fallback keeps
      standalone invocation working).

## Phase 2 — Namespacing guard T-case (`apps/web-platform/infra/run-registered-suites.test.sh`)

- [x] 2.1 Derive the execute set as the runner does (`git ls-tree` glob minus
      PRIVILEGED_WHY basenames, or `--enumerate`); assert the set is non-empty
      BEFORE scanning (vacuity floor).
- [x] 2.2 `git grep` the set for `mktemp` with `-u` **and** `--dry-run` (its alias),
      and `mktemp` with a positional `/tmp` template. Zero hits outside
      `# tmpns-exempt: <reason>` marker lines; print each exempted file:line +
      reason.
- [x] 2.3 Strip comment lines and string-payload lines (the
      `workspaces-luks-g4-mutation.test.sh:939` `mktemp -u` payload must NOT
      count) — mirror `_strip_comments` convention from grep-q-pipe-guard.
- [x] 2.4 Planted-hit fixture (SOLEUR_INFRA_DIR fixture root or synthesized line):
      prove the pattern family fires — a "0 checked" suite must RED.
- [x] 2.5 Do NOT assert "no bare `/tmp` writes" — container-heredoc and
      workflow-contract `/tmp` uses are legal (~11 files audited clean).

## Phase 3 — Record

- [x] 3.1 `apps/web-platform/infra/run-registered-suites.sh` header: `ATTRIBUTION
      (#7376)` block beside `DIAGNOSTICS ON RED` — the H1–H4 verdict lines +
      exit-code-first rule (124→H4; signal/UNACCOUNTED→H2; marker FAIL→real/H3).
      Comment-only.
- [x] 3.2 `knowledge-base/engineering/architecture/decisions/ADR-133-*.md`:
      append ONE clause — memory-derived `JOBS` cap is a *rejected* alternative
      (irreproducible width + self-masking evidence + single-file-SUT
      constraint); deterministic class-serialisation is the evidence-gated arm.
- [ ] 3.3 At ship: `gh issue comment 7376` with the plan's Evidence ledger
      (updated with any new soak runs), naming per-hypothesis verdicts and that
      H2 stays unproven-by-absence; PR body carries the same + `Closes #7376`.
- [ ] 3.4 Re-run the soak-run harvest before posting (runs since
      2026-10-19T18:00Z): `gh run list --workflow=main-health-monitor.yml`,
      `gh run view <id> --log | grep -E 'with -P |=== registered infra suites'`.

## Phase 4 — Verify

- [x] 4.1 Mutation-matrix rows 1–5 from the plan's Guard Contract each produce
      the expected verdict.
- [x] 4.2 `bash apps/web-platform/infra/run-registered-suites.test.sh` green.
- [x] 4.3 `bash scripts/test-all.sh` green (or the affected lane covering all
      five touched files).
- [x] 4.4 Confirm `JOBS` computation untouched (`run-registered-suites.sh`
      `min(nproc,6)`), no workflow file modified, no new suite file created.
