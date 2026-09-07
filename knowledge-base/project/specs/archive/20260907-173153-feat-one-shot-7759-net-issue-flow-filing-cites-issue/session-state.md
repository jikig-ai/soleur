# Session State

> **Superseded 2026-09-07 (#7896 review):** the "0 of 33" measurement below is FALSE. It classified cited numbers issue-vs-PR by range membership, which cannot work because GitHub issues and PRs share one number space here. Re-measured on `.pull_request`: **21 of 66 cited numbers are PRs and 20 of the 33 issues cite at least one**, over 29 pairs (one being #7710 -> #7702, the case #7759 was filed about). The exemption was under-reached, not inert. Likewise the "16 filing sites / 11 emit no PR number" figure: re-measured as **19 files / 48 invocations**, 14 files with no PR reference. And the `Possible unattributed filings:` mechanism described below was REMOVED in review — it reported numbers it had itself counted. See ADR-155 amendment and ADR-206.

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-net-issue-flow-filing-cites-issue-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verified: only `plans/`, `specs/`, and the generated `INDEX.md` changed — plan-only mandate respected.
- Collision re-probe after planning: plan targets `closes: [7759]`, the same ref cleared at Step 0a.5. No new target discovered, so no re-probe was required.

### Errors

1. markdownlint MD038 on the first plan commit (code span with a trailing space) — fixed, recommitted.
2. **A fail-open defect in the plan's own first-draft code**, found by probing and confirmed by two
   agents: `grep -oE … | jq … || _fail_open` under the gate's `set -uo pipefail` makes grep's
   no-match exit 1 fail the gate OPEN for every PR whose body names no issue (measured 46/300 PRs),
   and converts the deliberately fail-CLOSED unbalanced-fence path into a fail-open. Designed out by
   deriving the sets inside the existing `jq` pass. Notable: the plan's own draft reproduced the
   defect family the plan exists to fix.
3. A stale ADR ordinal in `tasks.md` after a 205→206 renumber — caught by the plan's own prescribed
   sweep, i.e. the sweep caught the failure it exists to catch.

### Decisions

- **The design fork is resolved as NEITHER issue option in its stated form.** The gate COUNTS only a
  declared `Filed:`/`Tracks:`/`Refs:` line in the PR body, and REPORTS-without-counting every other
  post-PR number the body mentions. Widening the match (option 2) attributes transitively through a
  third party and breaks stated property P4. The Source-line sweep (option 1) is rejected at 16
  filing sites (11 emit no PR number; 5 mutually incompatible citation shapes) but ADOPTED at one —
  `/ship` Phase 6's body template — where producer and gate ship in the same skill.
- **Bare-`#N` counting was drafted then rejected on measurement over 300 PRs:** it attributes 9
  issues to two PRs each and flips 25 PRs (8.3%) PASS→BLOCK with an unmeasured false-positive rate.
- **Consequence to carry into review:** for PRs predating the producer, the blind spot becomes
  SELF-REPORTING rather than closed. That is a deliberate trade (fail-visible over fail-open), and
  it is the thing to challenge if the reviewer disagrees.
- **A second, independent defect folded in:** ADR-155's mandated-filing exemption is inert — 0 of 33
  whole-line `Mandated-By:` issues cite a PR, so none has ever been a FILED candidate. The fix
  revives it; ADR-155 gets an amendment because its recorded consequences are falsified.
- **The PreToolUse hook needs no change** (verified, not assumed): it delegates and re-implements no
  query logic. The four pinned call-shape properties survive because the `gh issue list` argv is
  byte-identical — plus a NEW assertion pinning the `--json` field list, since dropping `createdAt`
  is an uncovered always-pass path.
- ADR-206, not 205: 205 reads free under a tree-scan of origin refs but is claimed on an unmerged
  branch, visible only to `git log --all`.

### Components Invoked

`soleur:plan` → `soleur:deepen-plan`; agents: general-purpose ×2, architecture-strategist,
code-simplicity-reviewer, test-design-reviewer, silent-failure-hunter, spec-flow-analyzer,
git-history-analyzer. Gates: deepen-plan 4.5–4.11. Lints: lint-guard-contract.py,
lint-infra-no-human-steps.py, markdownlint, gitleaks.

### Verification note (parent)

The parent re-probed two load-bearing claims. The `0 of 33` figure is correct under the gate's own
whole-line predicate; a parent probe returning 37/37 was asking a different question ("contains any
`#N`") and the plan had already documented 37 as the loose count. No correction needed.

## Work Phase

- Status: complete — all 41 plan tasks checked.

### Phase 2 §9 exit gate — REAPED, not red

The `scripts` and `bun` shards were launched sequentially and killed for low memory before either
finished. Classified as a harness reap on the runner's own three-way contract: **no rc entries, no
terminal `=== N/M suites passed ===` marker, zero `[FAIL]` lines** in either log. Not a verdict
about this diff.

Conditions: `--capacity` reported `CAPACITY_CONTENDED reason=sibling_runs measured_runs=3`, `/tmp`
at 1633 MB against a 1024 MB floor, and memory reached 2 GB available. Ownership was resolved
before touching anything — every surviving `test-all.sh` belongs to a foreign worktree (7826,
7849, 7874), so there were no orphans of mine to reap and none of those were mine to kill.

Not retried: a fourth attempt would reap again and would degrade three other sessions' runs for a
signal CI reproduces on clean runners. CI's required `test` context runs the same shards on the PR
head and is the merge gate.

What WAS run, all green:

| Check | Result |
|---|---|
| `net-issue-flow.test.sh` | 104 assertions ALL PASS |
| Mutation matrix M1–M8 | 8/8 RED, no survivors |
| Harness rows H2, H3 | both fire, both restored |
| `rule-metrics-aggregate` ×2 suites | rc=0 |
| 6 bun suites pinning `ship/SKILL.md` | 77 pass, 0 fail |
| `concurrent-ship`, `ship-followthrough-directive` | rc=0 |
| shellcheck (3 changed shell files) | clean |
| markdownlint | parity with `origin/main` (16 pre-existing in `ship/SKILL.md`, 0 added) |
| `check-adr-ordinals.sh` | pass |
| AC-G3 `gh issue list` argv | byte-identical to `origin/main` |
| AC-G9 hook diff | empty |

## Review Phase — panel coverage

Spawned 9 lenses. Two died on an Anthropic **session limit** (HTTP 429, resets 18:50
Europe/Paris) with no findings delivered:

| Lens | Status |
| --- | --- |
| code-simplicity-reviewer (design pass) | returned |
| architecture-strategist (design pass) | returned |
| security-sentinel | returned |
| general-purpose (structural-enumeration seat) | returned |
| test-design-reviewer | in flight at time of writing |
| pattern-recognition-specialist | in flight at time of writing |
| data-integrity-guardian | in flight at time of writing |
| code-quality-analyst | **DIED — session limit, 0 findings** |
| git-history-analyzer | **DIED — session limit, 0 findings** |

`performance-oracle` was deliberately replaced by the structural-enumeration seat
(guard-shaped PR; no economics claim in the design). `agent-native-reviewer`,
`semgrep-sast` (bash-only diff — vacuous by construction, `shellcheck` substituted and
clean) and `user-impact-reviewer` (threshold is `aggregate pattern`, not
`single-user incident`) were not applicable.

**What the two dead lenses were assigned, and what is therefore NOT covered.**
`code-quality-analyst` owned prose-accuracy sweep of every causal/universal claim the
diff adds. `git-history-analyzer` owned verification of the diff's empirical claims:
the "~300 PRs" measurement, the "sixteen filing sites / 11 emit no PR number / 5
mutually incompatible shapes" count, the ADR-155 "33 issues, 0 of 33 cite a PR"
re-measurement, and the #7702 / #7841 motivating stories.

The lead independently falsified four of the prose claims by hand (ADR-155's "range
membership" and "for every row admitted via that route"; the `$bodyonly` "post-PR"
comment; the suite's conservation-check comment) and verified the `/work`-files-before-
`gh pr create` timing at `work/SKILL.md:1146`. That is partial substitution, not
equivalent coverage: **the four empirical counts above remain UNVERIFIED**, and the
review trailer records the panel as degraded.
