# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-03-chore-supabase-followups-art30-register-orphan-linter-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` → only `plans/` + `specs/`. No breach.
- Post-plan collision re-probe: plan `closes: [7717, 7716, 7718, 6489]`. #6489 was discovered by
  planning (not passed at Step 0a.5) and re-probed: OPEN, zero linked PRs, zero merged body/title
  hits, no `origin/main` grep hit. Clean.

### Errors
- Self-inflicted, caught in-session: a Python slice anchored on `## Alternative Approaches
  Considered` matched a backticked *mention* of that heading and duplicated the Technical Approach
  section. Excised. Same anchor-matched-a-mention class as `cq-cite-content-anchor-not-line-number`
  / `cq-assert-anchor-not-bare-token`.
- Six acceptance criteria were defective on first writing (AC8 unsatisfiable, AC17 grepping an
  absent literal, Guard 1 highwater row inverted, AC19/AC21 asserting proxies, AC22 contradicting
  its own escape hatch). All found by running every AC against the untouched tree, and fixed.
- Non-blocking: `plugin:github:github` MCP server failed to connect; all GitHub work used `gh` CLI.

### Decisions
- W1 promotes the deprecated-endpoint guard via one `run_suite` line on the already-required
  `test` context, NOT the issue's prescribed four-file public-ABI route. The ADR-139
  `ALLOWED_PATHS ∩ SCAN_DIRS` intersection re-derives to EMPTY, so #7716's mandated bot-PR
  preflight reproduction does not apply. Aggregator-union invariant lands as an ADR-139
  amendment, not a new ADR ordinal.
- W6 creates a distinct `knowledge-base/legal/breach-register.md` (CLO ruling): Art. 33(5) is not
  an Art. 30 artifact. Follows the existing `article-30-2-register.md` precedent; an index, not a
  transcription. `__TBD_BETTERSTACK_RETENTION__` and `__TBD_OBSERVED_VOLUME__` resolve to
  `NOT RECORDED` with reasons; `__TBD_DPA_DATE__` to `NOT EXECUTED`.
- W7 cut from a union design to two narrow directory loops on a measurement (53 files → 1 orphan,
  4 → 1), removing the exclusions, seventh surface, 21 ACK entries and parallel covered-set
  derivation as structurally unnecessary.
- #7716 part 2 (`advisors/*`) stays monitor-only as the issue states, but the plan records that
  the "monitor" has no mechanism today and files the designed-but-unbuilt spec-diff poller.
- #7716 part 5's 66-runbook `triggers:` backfill deferred with reasons; the shape-pin and three
  defect fixes ship.
- #6489 folded in as a duplicate of #7716 part 3, with better evidence (the `SUPABASE_PAT` it
  names is a live 401).

### Open decision escalated to operator
- DC-1: two independent reviewers recommend shipping #7717 (statutory) as its own PR. The plan's
  mitigation for bundling was FALSIFIED — `ship` merges `--squash`, so there is no independently
  revertable statutory commit. Coupling recorded as real and unmitigated. Awaiting operator call
  before Step 3 (`/work`).

### Components Invoked
- Skills: `soleur:plan`, `soleur:gdpr-gate`, `soleur:plan-review`, `soleur:deepen-plan`
- Research: `repo-research-analyst`, `learnings-researcher`, `functional-discovery`, 4x `Explore`
- Domain review: `soleur:engineering:cto`, `soleur:legal:clo`, `soleur:product:cpo`
- Plan-review panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, plus `cto` (devex) and `cpo` (delta)
- Gates: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, deepen-plan halts 4.5-4.11,
  live verification of 13 rule IDs, 17 issue citations, 10 labels, every AC against the tree

## Work Phase (2026-09-03)

- Status: Phase 0, 1 and the W6 slice of Phase 7 complete. Phase 8 sweep run.
- Scope: W6 only (#7717) per the operator's DC-1 resolution. #7716 + #7718 + #6489 carry to a
  follow-on PR against the same plan; Phases 2-6 recoverable from `git show f8d4cd787`.

### Acceptance criteria — W6 block
AC1-AC13 verified by running each criterion's LITERAL command (not a normalized variant).
AC7 verified across all three sibling files. AC14 pending the CLO attestation (1.13).
AC4 is four rows, not seven — see the CLO ruling below.
AC8 was rewritten before it could be satisfied: the corpus-wide form was unsatisfiable.

### Split-boundary check (8.5) — verified, not assumed
All nine W1/W7/W3/W4/W5 files are absent from the diff. Two shared files carry W6-only edits:
`scripts/test-all.sh` (+4 legal `run_suite` rows; 0 W1/W7 rows touched) and
`plugins/soleur/skills/incident/SKILL.md` (+15 lines, 0 `triggers:` lines — the register routing
only, which ADR-200 needed in order to be true).

### CLO rulings obtained and applied
1. **4 indexed / 3 waived, not 7/0.** The plan derived its determination set from the pinned
   regex two paragraphs after warning that "no regex makes a legal judgement". Three of the six
   `audits/` matches fail the inclusion predicate's first limb (a breach-shaped fact pattern):
   one is a regex false positive describing a statutory-deadline catalog, one assesses a
   *prospective* PA-8 amendment, one never cites Art. 4(12) and attributes its conclusion to the
   operator's framing. Each carries a committed `NOT_TRANSCRIBED` waiver with a reason.
   The 2026-08-06 determination IS indexed — the closest-run Art. 4(12) call in the corpus, whose
   source preserves the contrary argument as "not frivolous".
2. **`controller:`, not `processor:`** — AC1 overruled. The 30(2) register carries `processor:`
   because that field names the capacity the register is kept in, and Art. 33(5) binds the
   controller on its face.

One CLO-supplied cell was corrected against its source before landing (AC4 requires
grep-validation): the Sentry row's inconclusive cell cited a pre-Phase-9 statement. Phase 9
closed both the ownership question (Sentry support confirmed both orgs operator-owned, 2026-05-19)
and the enumeration question (population enumerated). The row now records the actual residual.

### Defects found in the plan and corrected (measured, not inherited)
- AC8 unsatisfiable as written; rescoped to the register files, matching the guard's own scope.
- Corpus counts stale by one each: 115 files carry `art_33_triggered`, 102 post-mortems (not
  114/101). Swept at all five asserting sites by grepping the OLD value.
- Phase 1 preamble still asserted the DC-1 mitigation that was falsified.
- ADR-198/199 are contended by sibling branch plans; ADR-200 is the only uncontended ordinal.
- `## Files to Edit` named the wrong runbook for the `knowledge-base/legal/` token hit.
- The delegate guard has FOUR couplings, not the three the plan anticipated (also section-anchored
  to `## Rows`).
- The plan called the plan-SKILL threshold inversion "a one-paragraph edit". It is six
  behaviour-gating sites, and `review/SKILL.md`'s literal-text match is the one that actually
  invokes the agent — fixing fewer would have changed nothing.
- The plan said `gdpr-policy.md` carries the literal "no off-host log shipping is configured".
  It carries "no off-host copies" — a different wording, same claim, so a sweep on the first
  literal misses it. Recorded in #7786.
- The plan said `check-pa-22.sh` assertion (iv) was vacuous. Measured: the range DOES over-span
  four headings, but the only `TOMs` literal in the over-spanned region was PA-22's own, so it
  was LATENT rather than live. Planting one made the removal pass. Range tightened; both arms
  pinned.

### Defects found in my own work by mutation
- `lint-legal-registers.sh` assertion (c) tested membership with `grep -F` over the whole
  register, and the register's §Excluded records table lists the waived paths — so a file listed
  as EXCLUDED counted as INDEXED and every waiver was unfalsifiable. Anchored on the index
  table's canonical-source column, plus a disjointness check.
- `check-pa-22.sh` assertion (i) used a prefix match, so a heading renamed to `22-RENAMED` still
  counted as present. The first fix (`[^0-9]`) was also wrong — `-` satisfies it.
- Two of my own battery rows were mislabelled before being re-run with the mutation asserted to
  have landed.
- Three broken relative links in `register-update-pr-pattern.md` (depth 4 needs five `../`); two
  were pre-existing and my new one copied the mistake.

### Issue flow
Closing 1 (#7717). Filing 2: #7786 (published-disclosure contradiction, `compliance/critical`),
#7787 (guard promotion, with its trigger). Net +1, both justified — the first fires the three-way
`docs/legal/**` lockstep, the second is temporally blocked by construction.
Executed, not filed: `action-required` on #7529; #7125 re-milestoned to Phase 4.

### Open
- 1.13 CLO attestation (in flight).
- 8.2 `/soleur:gdpr-gate` on the cumulative diff.
- 8.3 full battery at `/ship` Phase 4 — deferred: a sibling worktree's full-gate run was in
  flight, so `test-all.sh` exited 4 (REFUSED, measured sibling condition #7553). Targeted suites
  run instead and all green.
