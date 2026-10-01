# Decision challenges — feat-one-shot-disk-leak-tmp-cleanup

Persisted by plan-review (headless pipeline) for `ship` to render and file. Plan:
`knowledge-base/project/plans/2026-10-01-fix-dev-machine-disk-leak-scratch-and-cache-cleanup-plan.md`.

## User-Challenge 1 — drop the `--attest` rung (and Guard 3 / ADR A1.2 / Phase 3b)

- **Operator's stated direction:** task e asks for a housekeeping step that prunes stale leftovers older
  than N days and reports sizes; the evidence names `vac*`, `td-*`, `perf-*`, `mut*`, `sdkprobe.*`,
  which no committed writer produces and which ADR-250 classifies as unattributable (retained).
- **Challenge (DHH, CTO, code-simplicity; CPO signs off conditionally):** the rung is the only
  destructive-capable mechanism, carries the single-user-incident threshold and an ADR amendment, and
  exists for a one-time backlog already tracked by #8786. A documented one-off quarantine `find ... -mv`
  (or `--report` only) would reclaim the same bytes.
- **Counter (architecture, spec-flow):** if `td-*`/`vac*` carry `.git`, the rung cannot reach them at
  all; quarantine frees no disk until drain.
- **Default applied:** keep the rung (operator direction), structured as a SEPARABLE Phase 3b that
  `--report` and the runbook do not depend on, with the conjunction hardened per review. Recommended
  fallback if cut: runbook-documented one-off move into the existing quarantine root.
- **Decision actually taken (supersedes the default above): the rung is CUT.** The one-shot lead removed
  Phase 3b, Guard 3 and ADR A1.2 from this PR (plan section "Scope Decision"). Why: 3 of 7 reviewers (DHH,
  CTO, code-simplicity) recommended the cut; task e asks only for a prune of stale leftovers older than N
  days plus a size report, not for an operator-named quarantine glob; the rung was the only
  destructive-capable mechanism and carried the `single-user incident` threshold; and the backlog it
  targeted is already tracked by #8786. What shipped instead is the planned fallback: `--report`
  (per-family bytes, `.git`/non-`.git` split) and runbook procedures A and B (operator-typed, dry-run
  default) for a one-off move of named legacy residue into the existing quarantine root. ADR-250
  Amendment 1 lists the rung as a rejected alternative (A1.2 number reserved). Revisit only if the one-off
  procedure proves repeatedly necessary.

## Taste 2 — split into two PRs

CTO and Kieran recommend PR 1 = Phases 1, 4, 5 + `--report` + runbook; PR 2 = sandbox allocator +
`--attest`. Default applied: one PR, phases ordered so Phase 2 and Phase 3b can be cut.

## Taste 3 — sandbox CLI vs prose-only brief edit

DHH: edit the seat brief to say `git ls-files | tar` into `mktemp -d` and `rm -rf`, no CLI. Counter:
spec-flow shows prose is the enforcement that already failed (#7004 comment, review SKILL.md bullet).
Default applied: keep a minimal `new|rm` CLI (task c), shrunk (no `list`, `--paths`, `--include-dirty`).

## Taste 4 — drop lint rule (d)

DHH/CTO/code-simplicity: rule (d) is a mini static analyzer overlapping Phase 1. Task d requires a lint.
Default applied: keep rule (e) plus a narrow rule (d) (non-test scripts only, `ast` for Python).

## Taste 5 — ship #9117 (durable log GC) separately

code-simplicity: out of P1-P6. Default applied: keep (small, in the leak surface, `Closes #9117`).

## Not Yet Specified / deferrals

Census-driven remainder of class-b sites: tracked by #9341.
