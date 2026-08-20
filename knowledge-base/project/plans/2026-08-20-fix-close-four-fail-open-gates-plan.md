---
title: "fix: close four fail-open gates (#7629, #7572, #7574, #7613)"
date: 2026-08-20
slug: fix-close-four-fail-open-gates
branch: feat-one-shot-7629-7572-7574-7613-failopen-gates
issue: 7629
closes: [7629, 7572, 7574, 7613]
type: bug
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Four filed defects share one shape: a check reports success on an input it was written to
block.

- **#7629** — the `skill-security-scan PR gate` (a *required* merge check) has two fail-open
  paths. A failed `git diff` is indistinguishable from "nothing was added", and a crashed
  scanner collapses to an `UNKNOWN` verdict compared against nothing. Both report green with
  zero coverage. Review found **four more** sites of the same class in the same two files.
- **#7572** — the S1 mutation arm reports *"S1 is no longer reproducing the measured failure"*
  when the container never completed setup. The container rc is dropped uncaptured, so "ran
  and produced nothing" and "never ran" are the same observation.
- **#7574** — the T5 counted SKIP is bounded per-run but not across runs. Measured this
  session: the enrolled observer has never reached a verdict, and — separately — the carrier
  it is enrolled on retires itself the first time it does.
- **#7613** — three R3-arm guards are narrower than the properties they name. The fix is
  **anchoring the guards**, not rewriting their input; see the Decision Challenge.

Each is closed by driving the guard RED on the concrete input the issue names, then GREEN. No
guard ships without a demonstrated failing direction — and, after a four-reviewer panel found
three guards in this plan's own first draft that could not be driven RED, no guard ships
without that direction having been *measured against the real artifact* rather than assumed.

Lane note: the spec directory carries no `spec.md`, so `lane:` could not be carried forward
and defaults to `cross-domain` (TR2 fail-closed).

---

## Decision Challenge

Recorded per ADR-084 and mirrored to
`knowledge-base/project/specs/feat-one-shot-7629-7572-7574-7613-failopen-gates/decision-challenges.md`
for `/ship` to render into the PR body and file as an `action-required` issue. This is
surfaced, not silently applied: the operator's stated direction remains the default wherever
it is still executable.

**The operator directed** that #7613's fix centre on the shared `.code.sh` comment stripper,
with a RED step and a GREEN step paid per consumer arm rather than once for the shared file.

**Measured against the rendered artifact, the stripper change is a behavioural no-op.**
Rendering `apps/web-platform/infra/cloud-init-git-data.yml` through the module's own strip and
extracting exactly as the suite's Python heredoc does:

| Artifact | Lines | Lines containing `#` after the render strip |
|---|---|---|
| `luks-stage.sh` (the `STAGE=luks_open` entry) | 55 | **0** |
| `runcmd-all.sh` (every runcmd entry concatenated) | 170 | **1** — `STAGE=volume_mount # (#6982) name the stage for the top-armed on_err fatal` |

That one line is read by no R3 predicate: `_r3b_analyze`'s `STAGE` regex matches with or
without the tail, and no arm greps `volume_mount`. There are **zero** `${var#pat}`, `$#`,
`#`-in-string or shebang occurrences in either artifact — those live in `write_files`, which
never enters `.code.sh`.

**What the plan does with that.** The per-arm RED/GREEN discipline the operator required is
kept in full and applied to all eight enumerated arms — but it is paid for the **anchoring**
work (Guards 6, 7, 8), which genuinely re-flows every one of those arms, rather than for the
stripper, which re-flows none. The stripper change is retained per the operator's direction
but re-labelled honestly as **prophylactic hardening**, scoped to two lines, with its
assertions moved onto a synthesized fixture because over the live corpus they would quantify
over the empty set — a vacuous guard inside an anti-vacuity plan.

**The operator's call to make:** keep the prophylactic stripper (current default), or drop it
and close #7613 with the anchoring alone. Dropping it also removes the ADR-152 amendment and
one arm's worth of parity work.

---

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| #7629, #7572, #7574, #7613 all OPEN | `gh issue view <N> --json state,closedAt` | **HOLDS** — all four `OPEN`, `closedAt=null`, 2026-08-20 |
| #7629's two fail-open shapes | read both workflows | **HOLDS** — `added=$(git diff … \| grep -E '…' \|\| true)` under `set -euo pipefail`; `verdict=$(… 2>/dev/null \| head -1 \| grep -oE '…' \|\| echo 'UNKNOWN')` compared only against `HIGH-RISK` |
| `run-scan.sh`'s `Exit code: 0 always (advisory).` is false | read the file | **HOLDS** — the comment sits in the header with `set -euo pipefail` two lines below and two `trap … EXIT` handlers after it |
| "there is no harness that can [drive a step body] today" | searched `scripts/` | **PARTLY STALE** — none for this workflow, but `scripts/follow-through-closure-guard.test.sh` already extracts a `run:` body by step `name` with `python3` + `yaml.safe_load` and executes it under `bash -e` |
| "there are no bats files" | `find . -name '*.bats'` | **HOLDS** — zero |
| `_s1_run()` drops the container rc | read the S1 arm | **HOLDS** — `docker run … >"$TMP/s1out/stdout" 2>&1` with no `$?` capture and no `\|\| true`; `S1_RC` is parsed from the stdout marker `STAGE_RC=`, a different quantity |
| S1 cost is "3 healthy / 4 mutation" | counted the arm | **PARTLY STALE** — 7 total, **5** container-dependent. See Reconciliation |
| `_SKIP_CEILING` is hand-derived from one arm | grep | **HOLDS** — `_SKIP_CEILING=2   # one skip-eligible arm (the T5 mutation arm), declaring a cost of 2` |
| `_r3_ln 'GIT_DATA_LUKS_DETAIL='` is unanchored while `_r2d_ordered` is anchored | read both | **HOLDS** |
| `gpat` reads trailing comments | read `_r3b_analyze` | **HOLDS** — `gpat = re.compile(r'\[\s+-[rs]\s+"?' + re.escape(name))` over a whole-line-only-stripped window |
| `_r3b_n -ge 6` is a count floor where the property is a set | read the stanza | **HOLDS**, and sub-assertion (iv) already does set equality against `_r3b_want` |
| `.code.sh` strips whole-line comments only | `re.match(r'^\s*#', l)` at both sites | **HOLDS** |
| `_b2_strip` is "a correct stripper" (#7613's own words) | executed it on the render | **FALSE as a general claim, true for this corpus.** `s/[[:space:]]*#.*$//` has a zero-width prefix and destroys `${var#pat}`, `$#`, `${v##x}` and `#`-in-string. It is safe on `runcmd` only because that corpus contains none of them; `main.tf` records the same measurement (`a `#`-anywhere rule … breaks four of the six scripts on parameter expansion — measured`) |
| "the template already carries surviving trailing comments — the shape is live" | measured | **HOLDS but is narrower than it reads** — exactly one, on a line no arm reads |
| #7574 has "no counter, no marker reaching an observability layer, no gate that reads it" | read the probe, its directive, the sweeper | **STALE and then re-confirmed for a different reason.** A gate does read it — and both the probe and its carrier are broken. See below |
| ADR-188 "has no analogue" to ADR-181's compensating re-run | read ADR-188 | **HOLDS**, and ADR-188 additionally records the *rejection* of a derived ceiling. See Reconciliation |

### The two measured findings that reshaped this plan

**1. The #7574 observer has never reached a verdict, and repairing it would retire it.**

The 2026-08-19 sweeper comment on #7574 records `TRANSIENT (exit 2)` with twenty repetitions of
`printf: write error: Broken pipe` followed by `TRANSIENT: fetched 20 run log(s), none
containing 'git-data-runcmd-rehearsal:'`. Those two facts contradict each other and together
name the defect. Line 67 is

```bash
printf '%s' "$log" | grep -qF "$SUITE_TERMINAL" || continue
```

under `set -uo pipefail` (line 26). `grep -q` exits on the first match; `printf` then hits
EPIPE and returns non-zero; `pipefail` promotes the pipeline; `continue` discards the
observation. Twenty broken pipes means twenty logs *did* carry the suite's terminal line and
all twenty were thrown away. The probe cannot reach `PASS` or `FAIL`.

Repairing that alone is not enough, and this is the finding that changes the design. The
probe is enrolled on the **follow-through sweeper**, whose contract is one-shot: on exit 0 it
posts a `### Sweeper run: PASS` block and runs `gh issue close`, and `closed_precheck` then
refuses to re-litigate any issue *"carr[ying] the sweeper's own PASS block"*. So a repaired
probe PASSes once, closes its own tracker, and is permanently exempted — after which nothing
bounds the skip again. The follow-through mechanism verifies that a *residual did not
materialise*; #7574 asks for a *standing monitor*. Those are different jobs and the plan now
gives the probe a carrier that matches the second.

**2. Widening the skip marker to a bare prefix would make the observer fail every day.**

`gh run view <id> --log` returns the **whole workflow run's** logs, and
`.github/workflows/infra-validation.yml` runs `infra-config-apply.test.sh` and
`git-data-runcmd-rehearsal.test.sh` in the same run. `infra-config-apply.test.sh` emits
`SKIP (loud): not root, so foreign ownership cannot be expressed here — the structural`, which
fires on **every** GitHub-hosted runner. A bare `SKIP (loud): ` prefix would therefore count a
foreign suite's skip in every sampled log and return exit 1 forever — trading a silent
TRANSIENT for a loud lie. The marker must be an **enumerated set of this suite's own arm
markers**.

### Property List (Phase 0.6b)

| # | Property |
|---|---|
| P1 | When `git diff` cannot enumerate the PR's added files, the gate does not report success. |
| P2 | When the scanner does not produce one of `HIGH-RISK` / `REVIEW` / `LOW-RISK` for an added skill, the gate does not report success, and the scanner's stderr is readable from the run. |
| P2b | **Every** path in `ADDED` produces a verdict. A run where `no_new_skills=false` and zero verdicts were produced does not report success. |
| P3 | `run-scan.sh`'s documented exit contract matches its actual exit behaviour. |
| P4 | The step bodies above have a failing direction a person can execute. |
| P5 | When the S1 container does not complete setup **for a reason nobody owns**, the suite says so as a counted skip; when it fails for a reason this file owns, the suite fails. |
| P6 | `passes + fails + SKIPPED_ASSERTIONS` stays invariant at 7 for S1 across every path. |
| P7 | A transform that drops the S1 execution marker hard-fails instead of skipping forever. |
| P8 | The declared skip budget cannot silently grow: adding a skip-eligible arm forces a deliberate decision. |
| P9 | A loud SKIP that recurs across post-merge runs produces a verdict a person sees. |
| P10 | The cross-run observer cannot report a clean bill of health from an unread sample, and cannot report failure from another suite's skip. |
| P11 | The observer stays live when a second skip-eligible arm is added, and stays live after it first reports. |
| P12 | The R3 predicates quantify over the stage's **code**, not over its commentary. |
| P13 | Each R3 arm downstream of the change has a demonstrated failing direction on the concrete comment-satisfaction input its finding names. |
| P14 | R3(3b)'s reporting-site assertion is keyed to a set, not a count floor. |

### Cut List (Phase 0.6b)

| Mechanism the ask proposed | Property | Verdict |
|---|---|---|
| "a new executable harness for GitHub Actions step bodies" (#7629) | P4 | **Re-scoped, not cut.** `scripts/follow-through-closure-guard.test.sh` already does the extraction; the new suite copies it rather than inventing one. |
| a persisted cross-run counter (#7574) | P9 | **CUT.** The probe already computes the number; the gap was that its verdict never landed anywhere. |
| a Better Stack marker / a new observability layer (#7574) | P9 | **CUT.** A daily job with issue-write permission already exists. |
| a scheduled un-gated re-run mirroring ADR-181's six-hourly compensation (#7574) | P9 | **CUT.** `infra-validation.yml` already runs post-merge; the probe samples its logs. |
| a shrink-only ratchet file for skip counts (#7574) | P9 | **CUT** as an observer — but the ratchet *shape* is adopted for P8. Precedent: `MAX_DEFERRED=47` in `scripts/guard-vacuity-floor.test.sh` ("do NOT raise this number"). #7574's "no precedent" clause is wrong on both counts. |
| **deriving `_SKIP_CEILING` from the `arm_skip` call sites** (#7572's own suggestion) | P8 | **CUT — and this is a reversal of the issue's advice.** `SKIPPED_ASSERTIONS` is the sum of costs *actually taken*; a ceiling equal to the sum of all *declared* costs makes `SKIPPED_ASSERTIONS <= _SKIP_CEILING` an identity that can never fire. ADR-188 already weighed and rejected it: *"Raising it is not detectable by any assertion that would not be text-matching the source, which is the antipattern this suite rejects."* The literal stays; see Phase 3.5. |
| changing `git_data_template_rationale_strip` in `main.tf` (#7613) | P12 | **CUT.** See Non-Goals. |
| **the `.code.sh` stripper as the mechanism for P12** (#7613) | P12 | **Demoted, not cut.** P12 is bought unconditionally by anchoring (Guards 6, 7, 8); the stripper buys it prospectively and changes one line no arm reads. See Decision Challenge. |

### Relevant institutional learnings and principles

| Path | Constraint on this plan |
|---|---|
| `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | Every guard here ships with the cheapest edit that breaks its named property, written down and executed. The first draft of this plan shipped three that could not be driven RED; the panel caught all three. |
| `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` | Every guard carries harness rows and a non-canonical must-PASS row. RED rows cannot detect a guard that rejects everything. |
| `knowledge-base/project/learnings/2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` | A test asserting a guard's *shape* cannot see a guard that does not *run*. The step-body suite executes the real body from disk. |
| `knowledge-base/project/learnings/2026-08-19-the-install-step-that-hung-was-installing-something-already-there.md` | Cited by #7629. The `if: steps.diff.outputs.no_new_skills == 'false'` guards are exactly what turn defect (a) into zero coverage. |
| `knowledge-base/project/learnings/2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md` | Co-presence is not ordering. R3's ordering predicates stay line-number comparisons. |
| `knowledge-base/engineering/architecture/decisions/ADR-181-local-gate-declines-are-counted-verdicts.md` | A decline increments the denominator. P6. |
| `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` | Supplies the **four-rung classification ladder** S1 must adopt, and records the rejection of a derived ceiling. Requires an amendment — see the ADR section. |
| `knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md` | Its Consequences assert the strip *"does not touch mid-line or trailing `#`"*. After this plan that stays true of the render and becomes false of the suite's code corpus. Requires an amendment. |
| `knowledge-base/engineering/architecture/decisions/ADR-176-plan-artifacts-checkpoint-before-research.md` | Never two signals that can silently disagree. Applied to `.code.sh`-vs-`_b2_strip` and to the R3(3b) site key. |
| `knowledge-base/engineering/architecture/principles-register.md` — **AP-021** (diagnostic honesty) and **AP-023** (a counter incremented inside both verdict helpers makes its conservation identity a tautology) | AP-021 governs the S1 classifier's harness-defect rung; AP-023 is the precise name for the derived-ceiling defect the Cut List rejects. |
| `.claude/hooks/skill-security-scan-write.sh` — the `*)` "Unknown verdict → ask, not allow … Architecture review F8" branch | **Layer A already fixed this class.** Guard 2/3 cite F8 as precedent rather than arguing the trade from first principles. |

### Existing lint coverage — measured, not assumed

| Script | Verdict |
|---|---|
| `scripts/lint-shell-capture-exit.py` | **Does not fire, and cannot.** Run explicitly against both workflows it reports `2 script(s) scanned, 0 new findings`; its `collect_targets` defaults to `git ls-files '*.sh'` and never sees `.yml` at all, and the `\|\| true`-over-a-pipeline shape does not match its S1/S2 classes. The answer is "out of scope", not "live" or "baselined". |
| `scripts/lint-workflow-errexit-capture.py` | **Does not fire today — but Phase 2 creates its trigger.** It anchors on exit-status *reads* (`rc=$?`, `rc=${PIPESTATUS[n]}`) under the runner's injected `bash -e`; Phase 2.2 adds exactly such a read. Added to Phase 0.2 and Phase 7.4, and Phase 2.2 prescribes the `set +e` / `\|\| rc=$?` form it requires. |
| `scripts/guard-vacuity-floor.test.sh` | Does not cover the four defects, but constrains **both** new suites: `scripts/skill-security-scan-step-body.test.sh` and `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` both match `COVERED_DIRS='^(scripts/\|plugins/soleur/test/)'`, so each must survive the `command_not_found_handle` mutant. `apps/web-platform/infra/` is in `DEFERRED_DIRS` and the runcmd suite is already counted there, so `MAX_DEFERRED=47` does not move. |

### Registration, corpus and run-cost facts

- `scripts/test-all.sh` `SUITE_GLOBS` does **not** include `scripts/*.test.sh`. Suites there are
  registered by an explicit `run_suite "<label>" bash <path>` line, and those lines sit inside
  `TEST_GROUP` blocks — CI runs `test-all.sh webplat`, `bun` and `scripts`, so both new suites
  must land in the **`scripts`** group or they register without ever running in the shard that
  matters. `scripts/lint-orphan-test-suites.sh` enforces the registration but not the group.
- `python3` + `PyYAML` is the repo's workflow-parsing tool; `yq` is not used.
- The rehearsal suite **hard-exits** unless docker, a live docker daemon, terraform, python3 and
  dash are all present, and `_skip()` under `CI=true` is `exit 1`, not a skip
  (*"A gate that cannot run must not report success."*). The `.code.sh` corpus is produced by a
  terraform render, and the R3 arms sit downstream of eleven `docker run` sites. Any claim that
  an R3 arm can be exercised "without docker" is true of the predicate and false of the suite.
- `scripts/followthroughs/*.test.sh` is an established shape with nine siblings, each with its
  own explicit `run_suite` line.
- The absolute assertion floor is `total < 49`; S1 emits exactly 7 on all its paths.

### Related issues and PRs

#7291 / PR #7510 / ADR-188 (introduced `arm_skip` for T5 only; #7572 and #7574 are its declared
residuals) · #7501 (landed R4's rc capture; the "4 of 6 arms discard rc" figure is stale, the
count is 2) · #7535 (the deferred pre-baked rehearsal image, named by the probe's FAIL message)
· #7534 and #3593 (see Open Code-Review Overlap).

---

## Research Reconciliation — Spec vs. Codebase

| Issue / draft claim | Codebase reality | Plan response |
|---|---|---|
| #7572: skip cost is "3 healthy / 4 mutation" | 7 assertions, **2 container-independent** (the errexit-ordering grep over `runcmd-all.sh`; the mutation-landed grep over two local files) and **5 container-dependent** (2 healthy, 3 mutation). The `else` branch emits 7 `fail`s and the file's own floor comment says S1 *"emits exactly 7 on ALL THREE of its paths"* | Skip the container-dependent 5 only. Costs 2 (healthy) + 3 (mutation), invariant `passes + fails + SKIPPED_ASSERTIONS == 7`. |
| #7572: replace `_SKIP_CEILING` with a grep of the `arm_skip` call sites | That makes the check a tautology (AP-023), and ADR-188 records the rejection explicitly | **Reversed.** Keep the literal, raise it to 5 with an itemised stanza, add a call-site-count assertion. Amend ADR-188. |
| #7572's classifier suggestion (capture rc, guard the arm) implies a 2×2 on `(rc, marker)` | T5 uses a **four-rung ladder** — `ran` / `fixture-defect` / `harness-defect` / `did-not-run` — with an rc **allowlist** `_T5M_ENV_RCS='100 125'`, because *"Reading every non-zero rc as that decline hands the skip bucket every HARNESS defect too"*. `(rc==0, marker absent)` is classified **harness-defect and FAILS**, not skip | Port the ladder and an `_S1_ENV_RCS` allowlist. A 2×2 would have made the plan's own AC classify a harness defect as an environment skip. |
| #7574: "no gate reads it" | A gate reads it; the probe is inert (SIGPIPE) **and** its carrier retires it on first PASS | Repair the probe, enumerate the marker set, and move the carrier to a standing monitor. |
| #7629 names two fail-open sites | **Six.** Both workflows carry the `git diff \| grep \|\| true` union and the `\|\| echo 'UNKNOWN'` verdict; plus `parent=$(git rev-parse HEAD^1 2>/dev/null \|\| git rev-parse HEAD)` in postmerge (a base that cannot be resolved becomes "nothing was added"); plus `gh issue create … \|\| true` (the compliance record can vanish while the step still exits 1); plus the loop's `[ -z "$path" ] && continue` / `[ ! -f "$path" ] && continue` pair, which lets `no_new_skills=false` produce **zero verdicts** and still `exit 0` | All six folded in. |
| Draft claim: `\|\| echo 'UNKNOWN'` appears in exactly two files | **Four** — the two workflows plus `.claude/hooks/skill-security-scan-write.sh` and `.claude/hooks/skill-security-scan.sh`. Both hooks are correct as-is (the write hook's `*)` branch asks rather than allows, per F8; the commit hook is advisory by design) | AC9 is scoped to `.github/workflows/` and says so; the hooks are cited as precedent, not edited. |
| Draft claim: postmerge has "two `run:` bodies" carrying the defects | It has two `run:` steps, of which **one** (`Detect merged HIGH-RISK skills without override`) carries both defects; the other is `jq --version` | Corrected throughout. |
| Draft claim: the assembly is "three step bodies across two files" | **Six** `run:` bodies — four in pr-trailer (`Assert jq present`, `Identify added…`, `Validate override artifacts (if any)`, `Run scanner…`) and two in postmerge | The manifest is defined by a **shape predicate** with an explicit exclusion set. |
| Draft claim: the stripper is "a real behaviour change for all eight consumer arms" | Measured: 0 changed lines in `luks-stage.code.sh`, 1 in `runcmd-all.code.sh`, on a line no arm reads | See Decision Challenge. The per-arm budget moves to the anchoring. |
| Draft claim: `_r3_ln` should be made to "fail loud instead of returning empty" | `_r3_ln` **already** returns empty; the loudness lives at the call sites' `[ -n "$_r3_seed_ln" ]` tests. The function is generic and is already called with an anchored pattern for the trap | The fix is at the **call site** `_r3_ln 'GIT_DATA_LUKS_DETAIL='`, not in the function. |
| Draft claim: after the stripper change B2 remains an independent control | Measured: `runcmd-all.code.sh` would become byte-identical to `_b2_strip("$TMP/runcmd-all.sh")`, i.e. two implementations of one transform (ADR-176) and B2 ceases to be independent evidence | A parity assertion between the two implementations, mirroring `git-data-render-strip-parity.test.sh`'s precedent for the `main.tf`/`budget.sh` mirror; the must-not-change control set widens beyond B2. |

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` (64) and `--label
deferred-scope-out --limit 200` (200), matched against every planned path.

- **#7574**, **#7613** — in scope. **Fold in** (`Closes`).
- **#7534** — *the rung-2 evidence hash cannot see four legitimate payload binding forms*.
  Matches `modules/git-data-userdata/main.tf`. **Acknowledge:** its subject is the evidence-hash
  extractor and payload-reference binding forms; this plan does not edit `main.tf` (Non-Goals),
  so there is no textual overlap. Stays open.
- **#3593** — *extract post-synthetic-checks child composite*. Mentions `skill-security-scan`
  only as a synthetic check-run name. **Acknowledge:** this plan neither renames the job nor
  touches the composite — but see Risks, because that composite is why the pre-merge gate is
  not the only control that matters.

No other open review issue names any planned path.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur plugin update that installs a skill
carrying code-execution or exfiltration content, because `skill-security-scan PR gate` reported
green on a run where the scanner crashed, or where the diff failed, or where every added path
was skipped by a `continue` and zero verdicts were produced. The artifact the user receives is
`plugins/soleur/skills/<slug>/SKILL.md`, executing on their machine through their own CLI.

**If this leaks, the user's workflow and credentials are exposed via:** a HIGH-RISK skill merged
without an override artifact, running in the user's session with their filesystem, Doppler token
and `gh` credentials in reach. The vector is the plugin distribution path (`plugin` → `skills`),
so it reaches the user directly and Soleur learns last.

**Brand-survival threshold:** `single-user incident`.

**Where the pre-merge gate is *not* the control.**
`.github/actions/bot-pr-with-synthetic-checks/action.yml` derives its check names from
`scripts/required-checks.txt` and posts a **success** check-run for each, including
`skill-security-scan PR gate`. For any bot-authored PR the required context is satisfied without
the real gate running. On that path the **post-merge audit is the only control**, which is why
this plan fixes both workflows rather than the pre-merge gate alone, and why claiming the
pre-merge gate as the sole defence would have been false.

---

## Architecture Decision (ADR/C4)

### ADRs — two amendments, and one ADR that is not created

**Amend `ADR-152`, do not create a new ADR.** ADR-152's `## Scope` reads *"This ADR covers the
render-time transformation only"*, and its Consequences assert the strip *"does not touch
mid-line or trailing `#`"* — a sentence that stays true of the render and becomes false of the
suite's code corpus once the prophylactic stripper lands. ADR-152 already reaches into this
suite (it records that B1's byte-identity check compares against the stripped source) and its
#7278 amendment established a **rule table** of "which strip expression for which artifact
class". This plan's decision is literally a third row in that table. A standalone ADR-195 would
duplicate the table, leave ADR-152's sentence reading as repo-wide truth, and drag in the
ordinal-collision gate and a renumber sweep for a two-line change to a test file's heredoc.
*(The next free ordinal was probed anyway — highest claimed across all 63 `origin/*` refs is
ADR-194 — and is recorded here only so a future reader knows the check ran.)*

**Amend `ADR-188`.** This plan reverses two things ADR-188 recorded, and doing that silently is
the defect:

1. **The derived ceiling.** ADR-188 states *"the ceiling constant is not mechanically
   drift-proof. Raising it is not detectable by any assertion that would not be text-matching
   the source, which is the antipattern this suite rejects. The mitigation is procedural and
   declared."* This plan keeps that decision (Cut List) but **raises the constant and adds a
   call-site-count assertion**, which is a partial move toward mechanical detection. Record what
   changed and why the full derivation is still rejected (AP-023: it would be a tautology).
2. **The compensating bound.** ADR-188 grants its carve-out from ADR-181 property 4 on the
   strength of the T5 *primary* arm still failing under a degraded environment. S1 has the same
   property today: `[ "${S1_RC:-none}" = "0" ]` fails when the container is broken. Converting
   both S1 container paths to skips **removes S1's own primary-fails bound**. The composite
   bound probably survives via T5's primary, but ADR-188 must say so explicitly, and Phase 3
   must guard it so a future T5-primary skip does not silently remove the last one.

### C4 views

**No C4 impact.** All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,
views.c4,spec.c4}` were read and enumerated. Citations are content anchors, not line numbers
(`cq-cite-content-anchor-not-line-number`):

- **External human actors** — only `contributor = actor "Contributor / PR Author"` (`#external`)
  is involved, already modelled, and its single edge
  `contributor -> github "Opens untrusted PR — head code runs in fix-constraints Stage A …"`
  already names the untrusted-PR trust boundary this gate sits on. No new actor.
- **External systems** — `github = system "GitHub"` is the only one; the change edits two
  existing workflows and adds no vendor, webhook or outbound API. All 21 `#external` systems
  were enumerated; none gains or loses an edge. Notably `SKILL_SECURITY_SCAN_OFFLINE=1` keeps
  the scanner's only outbound host (`api.osv.dev`, reached from `check-supply-chain.sh`) out of
  the required check's dependency set — so no external-system edge is created by fail-closing.
- **Containers / data stores** — none touched. `plugin.skills` and `plugin.agents`, the
  artifacts the gate protects, already exist.
- **Actor↔surface access relationships** — none change. The fix makes an already-modelled edge
  enforce the check it claims to enforce.
- **Descriptions the change falsifies** — none.
- `skill-security-scan` is not a component in `view components of platform.plugin`, which models
  a curated subset of the plugin's skills; not adding it is consistent with that curation.

### Sequencing

Both amendments land in this PR, in Phase 4, after the Phase 0.7 spike has decided what the
stripper actually does and before Phase 5 ships it.

---

## Observability

```yaml
liveness_signal:
  what: >
    The `skill-security-scan PR gate` required check; the new
    scripts/skill-security-scan-step-body.test.sh suite; and the standing skip monitor.
  cadence: >
    every pull_request synchronize + every merge_group event (gate); every CI run (suites);
    daily (skip monitor).
  alert_target: >
    GitHub required-check status on `main` branch protection (ruleset #14145388); the `test`
    job in .github/workflows/ci.yml; and an operator-visible issue opened/updated by the skip
    monitor on FAIL.
  configured_in: >
    .github/workflows/skill-security-scan-pr-trailer.yml,
    .github/workflows/skill-security-scan-postmerge.yml,
    .github/workflows/scheduled-rehearsal-skip-monitor.yml,
    scripts/test-all.sh (run_suite registration, TEST_GROUP=scripts),
    scripts/required-checks.txt
error_reporting:
  destination: >
    GitHub Actions annotations (`::error::`) on the gate job — observability layer 5, the
    CI/workflow surface, which is the layer of record for a required merge check: a failing
    required check blocks merge and is visible on the PR with no dashboard. The post-merge
    audit additionally files a `compliance/critical` issue, and the skip monitor maintains an
    alert issue.
  fail_loud: true
failure_modes:
  - mode: "`git diff` cannot enumerate added files (unreachable SHA, shallow fetch, force-push race, unresolvable merge base)"
    detection: "the diff step exits non-zero with `::error::` naming the base/head pair"
    alert_route: "required check fails -> merge blocked"
  - mode: "the scanner crashes or emits no verdict token for an added skill"
    detection: "the scan step exits non-zero with `::error::` carrying the scanner's captured stderr"
    alert_route: "required check fails -> merge blocked"
  - mode: "`no_new_skills=false` but zero verdicts were produced (empty ADDED, every path skipped by a `continue`)"
    detection: "scanned-path count != added-path count -> the step exits non-zero"
    alert_route: "required check fails -> merge blocked"
  - mode: "the step-body harness stops extracting a body (renamed step, restructured YAML)"
    detection: "the extraction guard fails loudly rather than reporting zero checked"
    alert_route: "`test` job fails in CI"
  - mode: "the S1 container fails for a reason nobody owns (apt archive state)"
    detection: "`SKIP (loud): S1 …` on the suite's stderr with a declared assertion cost and four discriminating fields"
    alert_route: "post-merge infra-validation.yml run log -> sampled daily by the skip monitor"
  - mode: "the S1 container fails for a reason this file owns (bad mount, rc outside the allowlist, rc 0 with no marker)"
    detection: "the harness-defect rung `fail`s the suite; it is never routed to a skip"
    alert_route: "`infra-validation.yml` fails"
  - mode: "a loud SKIP recurs across post-merge runs (persistent degradation, not transient)"
    detection: "the monitor returns exit 1 with a per-arm breakdown over an enumerated marker set"
    alert_route: "scheduled-rehearsal-skip-monitor.yml opens/updates an alert issue and fails"
  - mode: "the monitor stops observing (marker reworded, log shape moved, gh auth broken)"
    detection: >
      the SUITE_TERMINAL positive control returns TRANSIENT; N consecutive TRANSIENTs escalate
      to a failure; and scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh reddens
      in CI if the probe's verdict logic breaks.
    alert_route: "`test` job fails in CI; the monitor's alert issue records the escalation"
logs:
  where: "GitHub Actions run logs (gate, suites, monitor); the monitor's alert issue"
  retention: "90 days for Actions logs (GitHub default); issue comments are permanent"
discoverability_test:
  command: "bash scripts/skill-security-scan-step-body.test.sh"
  expected_output: >
    a final line of the form `skill-security-scan-step-body: N passed, 0 failed (N assertions)`
    with N at or above the suite's declared floor
```

### Affected-surface observability (Phase 2.9.2)

The rehearsal suite drives `ubuntu:24.04` containers whose interior is not inspectable after
the run, so the S1 fix satisfies the blind-surface extension:

- Detection is an **in-surface** probe — an execution marker emitted from inside the container
  by the mounted `sshd-drive.sh`, above the stage invocation and below the fixture guard,
  mirroring `DRIVER_REACHED_DL`. A host-side rc alone cannot separate "apt failed" from "the
  stage ran and printed nothing".
- The skip message discriminates **all** competing hypotheses in one event: container rc, the
  rc's classification against `_S1_ENV_RCS`, whether the in-container marker was seen, whether
  the S1 *healthy* run reached it (the analogue of `_t5_primary_reached`), and the stdout tail.

### Soak follow-through enrolment (Phase 2.9.1)

The existing directive on #7574 is **retired, not reused**, because the follow-through
sweeper's PASS-closes-and-exempts contract is incompatible with a standing monitor (Research
Insights, finding 1). The probe moves to `.github/workflows/scheduled-rehearsal-skip-monitor.yml`,
which runs it daily and maintains an alert issue on FAIL. No new secret: `GH_TOKEN` from
`secrets.GITHUB_TOKEN` is what the probe already uses.

---

## Guard Contract

**Preamble — the harness meta-property, stated once rather than per guard.** For every guard
below, the fixtures are themselves under test: perturbing a RED fixture so it no longer carries
the motivating input must make the suite RED, proving the fixture drives the verdict rather
than a constant. Individual guards restate this only where the perturbation is non-obvious.
Every guard additionally carries at least one **must-PASS** row that is *not* the canonical
input, because RED rows cannot detect a guard that rejects everything.

### Guard 1 — step-body extraction and dispatch (`scripts/skill-security-scan-step-body.test.sh`)

**Property.** Every fixture below is executed against the *real* `run:` body as it exists on
disk, and a run in which no body was executed cannot report success.

**Assembly.** The extraction function loading both workflow files with `yaml.safe_load` and
selecting steps by `name`. The two files carry **six** `run:` bodies. The manifest is defined
by a **shape predicate** — *a body is in scope iff it invokes `run-scan.sh`, `parse-override.sh`,
or `git diff --diff-filter=A`* — which selects four of the six. The two excluded are
`Assert jq present` in each file, excluded because their whole body is `jq --version`; the
exclusion set is written down with that reason, so "the manifest is incomplete" and "the
manifest excludes something deliberately" are distinguishable. The suite's own dispatch counter
is the second chokepoint.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Rename any in-scope step in either YAML | yes — extraction finds 0 hits and fails loudly, never "0 checked, exit 0" (**guard's own dispatch**) |
| M2 | Add a fifth body invoking `run-scan.sh` without registering it | yes — the shape predicate selects it and the manifest does not contain it (**second member after a compliant first**) |
| M3 | Point the extraction at a copy of the workflow with `\|\| true` restored | yes — this is the only row proving the suite executes the text **on disk**. A byte-equality assertion between "the extracted text" and "the executed text" would compare the extraction to itself and pass always |
| M4 | Neuter the suite's `fail()` via `command_not_found_handle() { return 0; }` | yes — the floor must not route through `fail()`; it is asserted directly against the assertion counter, because `guard-vacuity-floor.test.sh` runs exactly this mutant on `scripts/` |
| M5 | Delete every fixture, leaving extraction intact | yes — the floor reddens on `0 assertions` |

**Must-PASS (non-canonical).** A body reformatted with different indentation and an added
comment line, semantically identical, must pass — the suite asserts behaviour of the fixtures,
not their byte-shape.

### Guard 2 — the diff and base-resolution gate (#7629(a), both workflows)

**Property.** When the added-file set cannot be *determined* — `git diff` fails, or the base
commit cannot be resolved — the step exits non-zero. When it succeeds and matches nothing, the
step exits zero and sets `no_new_skills=true`.

**Assembly.** Three members, not two: pr-trailer's `"$BASE_SHA"..."$HEAD_SHA"` (sourced from
`pull_request` **or** `merge_group`); postmerge's `"$parent"...HEAD`; and **the derivation of
`$parent` itself** — `parent=$(git rev-parse HEAD^1 2>/dev/null || git rev-parse HEAD)`, which
discards stderr and masks status, and whose fallback makes the diff empty and routes to
`echo "No SKILL/agent files added…"; exit 0`. That is defect (a) with a different spelling. The
`grep`'s own `|| true` is a fourth member and must survive.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Re-merge `git diff` and `grep` under one `\|\| true` | yes |
| M2 | Restore the `\|\| git rev-parse HEAD` fallback in postmerge | yes — a fixture whose `HEAD^1` does not resolve must fail the step, not report "nothing added" |
| M3 | Apply the fix to `pr-trailer.yml` only | yes (**second member after a compliant first**) |
| M4 | Replace the diff-failure branch's `exit 1` with `exit 0` | yes |
| M5 | Wrap the assignment in a function using `local raw=$(…)` | yes — `local` masks the command's status; verified. Phase 2.1 names this so a later refactor into a helper cannot silently reopen it |

**Must-PASS (non-canonical).** (i) A PR adding only `README.md` → `no_new_skills=true`, exit 0.
(ii) The **`merge_group` shape** — base/head taken from the merge-queue fields against a fixture
whose refs resolve → exit 0. Without (ii) the queue path is asserted nowhere.

**Motivating input (acceptance anchor).**
`BASE_SHA=0000000000000000000000000000000000000000` against a real two-commit fixture
repository — the shallow-fetch / force-push-race case #7629 names. Verified by hand:
`git diff --name-only --diff-filter=A 000…000...$H` exits 128 with
`fatal: Invalid symmetric difference expression`, and `if ! raw=$(…)` catches it without
tripping errexit. Today the step exits **0** with `no_new_skills=true`; after the fix it must
exit non-zero with an `::error::` naming the pair.

### Guard 3 — the verdict and coverage gate (#7629(b) + P2b, both workflows)

**Property.** For every path in `ADDED`, the step obtains a verdict in
{`HIGH-RISK`, `REVIEW`, `LOW-RISK`}; anything else fails the step with the scanner's stderr
present; and the number of paths that produced a verdict equals the number of paths in `ADDED`.

**Assembly.** Two scan loops, each with four members: the scanner's **exit status**, the
**first line** of its stdout, its **stderr**, and **the loop's own `continue` arms**
(`[ -z "$path" ] && continue`, `[ ! -f "$path" ] && continue`). Today all four are collapsed:
stderr discarded, status lost, `|| echo 'UNKNOWN'` compared against nothing, and the `continue`
arms able to consume every path while `fail=0` still `exit 0`s. Precedent for the fail-closed
disposition: `.claude/hooks/skill-security-scan-write.sh`'s `*)` branch — *"Unknown verdict →
ask, not allow … Architecture review F8."*

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Restore `\|\| echo 'UNKNOWN'` with no branch handling it | yes |
| M2 | Restore `2>/dev/null` on the scanner | yes — an assertion that the crashing fixture's stderr text appears in the step output reddens |
| M3 | Fix `pr-trailer.yml` only | yes (**second member**) |
| M4 | Make the scanner exit 0 while printing no verdict line | yes — exit status alone is not the guard |
| M5 | Make every path fall through `[ ! -f "$path" ] && continue` while `no_new_skills=false` | yes — the scanned-count assertion reddens. **Without this row the gate stays fail-open one step below where the issue cuts** |
| M6 | Delete `SKILL_SECURITY_SCAN_OFFLINE=1` from either call site | yes — a required check must not be coupled to `api.osv.dev`; that env var is the reason fail-closed is safe |
| M7 | Restore `head -1` inside a pipeline whose status is read | yes — `head -1` closes the pipe, the scanner takes EPIPE, `pipefail` promotes it, and a **successful** scan fails the gate. This is the #7574 defect pointed at a required merge check |

**Must-PASS (non-canonical).** (i) A scanner emitting leading blank lines or an `::notice::`
before a valid verdict → exit 0. (ii) `REVIEW` → exit 0. (iii) `HIGH-RISK` with a matching
override artifact → exit 0.

**Motivating input (acceptance anchor).** A `run-scan.sh` that exits non-zero having written a
Python traceback to stderr and nothing to stdout — *"a scanner that crashed reads as a scanner
that passed"*. Driven by placing the stub at the relative path the body invokes inside the
fixture CWD, so the real body runs unmodified. Today: exit **0**. After: exit non-zero with the
traceback in the captured output.

### Guard 4 — the S1 classification ladder and the skip budget (#7572)

**Property.** The S1 arm asserts on the SUT only when the container ran and reached the stage;
when it failed for a reason **nobody owns**, the arm declares a counted skip; when it failed for
a reason **this file owns**, the arm fails. The declared skip budget cannot grow without a
deliberate decision.

**Assembly.** `_s1_run()` (the rc capture), the mounted `sshd-drive.sh` heredoc (the execution
marker), the four-rung classifier with its `_S1_ENV_RCS` allowlist, and — because a counted skip
is only counted if the budget knows about it — every `arm_skip` call site plus `_SKIP_CEILING`.
All five container-dependent assertions flow through the classifier; the two
container-independent ones deliberately do not.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Delete the execution-marker `echo` from the `sshd-drive.sh` heredoc | yes — the structural guard on the **mounted** artifact hard-fails; it must not degrade to "skip forever" (**guard's own dispatch**) |
| M2 | Drop the container rc capture | yes |
| M3 | Classify `(rc==0, marker absent)` as a skip | yes — T5 classifies that as **harness-defect and fails**; a 2×2 would hand the skip bucket every harness defect |
| M4 | Widen `_S1_ENV_RCS` to "any non-zero" | yes — a mistyped `-v` source makes docker exit 125 with no marker, which is a bug in this file |
| M5 | Classify `(rc!=0, marker present)` as a skip | yes — a container that ran and failed is a finding |
| M6 | Add a third `arm_skip` call site without raising `_SKIP_CEILING` | yes — the call-site-count assertion reddens (**second member after a compliant first**) |
| M7 | Raise `_SKIP_CEILING` without adding a call site | yes — the same assertion reddens in the other direction |
| M8 | Skip all 7 S1 assertions instead of the container-dependent 5 | yes — detected by the **S1-specific bound `SKIPPED_ASSERTIONS_S1 <= 5`**, *not* by the cardinality invariant. `0 + 0 + 7 == 7` satisfies the invariant, so routing M8 there would be a guard that cannot be driven RED |

**Must-PASS (non-canonical).** A healthy run whose stdout carries extra apt noise before
`STAGE_RC=` must classify as `ran` and assert normally.

**Motivating input (acceptance anchor).** rc in `_S1_ENV_RCS` with the in-container marker
absent — the `apt-get update` failure under `set -e` that #7572 measured, which today renders
`S1_RC` as `<no marker>` and trips all three mutation assertions. Driven without docker by
calling the extracted classifier with that exact tuple; driven with docker once, end to end,
by mounting a drive script whose apt step is replaced by `exit 1`.

### Guard 5 — the `.code.sh` prophylactic stripper (#7613, contingent on Phase 0.7)

**Property.** `luks-stage.code.sh` and `runcmd-all.code.sh` contain the stage's executable text
and none of its commentary, and the strip removes no executable text and no line.

**Assembly.** The two extraction sites in the Python heredoc, **and** `_b2_strip` — because
after this change the two compute the same transform and can disagree (ADR-176).

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Revert `_all_code` to whole-line-only | yes — over the synthesized fixture, the trailing comment survives |
| M2 | Revert `_code` to whole-line-only while `_all_code` stays fixed | yes — **this is the direction the live corpus cannot detect** (the luks stage has zero comments), which is why the fixture is mandatory (**second member**) |
| M3 | Widen the strip to `_b2_strip`'s zero-width `[[:space:]]*` shape | yes — over the fixture, `${var#pat}`, `$#`, `${v##x}` and `#`-in-string are destroyed. This is the shape #7613 recommends, so the row is the regression test for taking the issue's advice literally |
| M4 | Widen to `[[:space:]]\+#.*$` (drop the "followed by whitespace" clause) | yes — the shebang is destroyed |
| M5 | Make the strip **delete** the line rather than blank the tail in place | yes — a line-count assertion reddens. Deleting renumbers everything below, and R3(1)/(2)/(2b)/(2d) are line-number ordering predicates |
| M6 | Make the strip a no-op | yes — a strip-is-not-a-no-op assertion over the fixture reddens (**own dispatch**), mirroring `git-data-template-strip.test.sh` ARM 3 |
| M7 | Change `_b2_strip` without changing the heredoc sites | yes — the parity assertion reddens |

**Assertions shipped with the change.** Over the **live** artifacts: `mkfs.ext4` and
`git-data-emit` survive; `len(_all_code.splitlines()) >= 40`; line count unchanged; `bash -n`
parses raw and stripped; every hunk of `diff <(raw) <(stripped)` is a pure suffix removal
beginning at `#`; and `runcmd-all.code.sh` equals `_b2_strip("$TMP/runcmd-all.sh")` byte for
byte (the ADR-176 parity assertion, mirroring `git-data-render-strip-parity.test.sh`). Over a
**synthesized fixture** (`cq-test-fixtures-synthesized-only`) carrying `[ "$#" -ge 4 ]`,
`${kv#*=}`, `${v##x}`, `sed -E 's#a#b#'`, `echo "issue #7613"`, an indented `#!/bin/sh`, a
whole-line comment and a genuine trailing comment: every at-risk token and the shebang survive;
only the trailing comment's tail is removed; the line count is unchanged.

**The fixture is mandatory, not belt-and-braces.** Measured, the live corpus contains **zero**
at-risk tokens and zero comments in the luks stage, so the same assertions over the live
artifact iterate the empty set and can never redden.

**Must-PASS (non-canonical).** A stage whose only comment is a whole-line one must produce
output identical modulo that line, and every arm must still pass.

### Guard 6 — R3(1)/(2)/(2b)/(2c) seed anchoring (#7613 finding 1)

**Property.** The seed line number R3 resolves is the line of a real `GIT_DATA_LUKS_DETAIL=`
**assignment**, not of any line mentioning the token.

**Assembly.** The **call site** `_r3_ln 'GIT_DATA_LUKS_DETAIL='` — not `_r3_ln` itself, which is
generic and is already called with an anchored pattern for the trap — plus its three consumers
R3(1)/(2)/(2b) and R3(2c)'s two inline `grep -n 'GIT_DATA_LUKS_DETAIL='` calls, a fourth
consumer the finding does not name.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Unanchor the seed call site back to the bare token | yes — on the motivating input |
| M2 | Anchor the call site but leave R3(2c)'s two inline greps bare | yes (**second member after a compliant first**) |
| M3 | Anchor the seed but not the first-append pattern, so a trailing comment naming `2>>"$GIT_DATA_LUKS_DETAIL` hijacks R3(2) | yes |
| M4 | Anchor everything but delete the `[ -n "$_r3_seed_ln" ]` test at one call site | yes — an empty line number must not silently degrade the comparison into "skip the check" (**own dispatch**). *The loudness lives at the call sites; `_r3_ln` already returns empty, so mutating the function is a no-op and is deliberately not a row here* |

**Must-PASS (non-canonical).** A seed written with leading tabs rather than spaces must resolve.

**Motivating input (acceptance anchor).** The stage with the real `GIT_DATA_LUKS_DETAIL=`
assignment relocated **below** `trap luks_err EXIT`, and a trailing comment naming the token
left on a line **above** the trap — the exact hijack finding 1 describes. Today R3(1), R3(2) and
R3(2b) all PASS on that input. After the fix all three must FAIL.

### Guard 7 — R3(3b) guard-search anchoring (#7613 finding 2)

**Property.** A reporting site is reported `GUARDED` only when a real `[ -r "$x" ]` /
`[ -s "$x" ]` test exists in executable text.

**Assembly.** `gpat = re.compile(r'\[\s+-[rs]\s+"?' + re.escape(name))` and the window it
searches inside `_r3b_analyze`. The fix rejects a match whose line-prefix (the text before the
match on that line) contains a `#` — narrow, local, conservative, and false-negative-only, so it
does not inherit the stripper's lexing problem.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Remove the line-prefix rejection | yes — on the motivating input |
| M2 | Delete a real `[ -s "$_luks_detail" ]` guard **and** its comment | yes — must still report `UNGUARDED`, so R3(3d)'s existing control is not the only detector (**second member**) |
| M3 | Make `gpat` match nothing at all | yes — the "every site is GUARDED" assertion must fail rather than the arm silently reporting zero sites (**own dispatch**, jointly with Guard 8's set assertion) |
| M4 | Apply the rejection to `gpat` but not to the emit-site regex, so a commented-out emit counts as a site | yes |

**Must-PASS (non-canonical).** A guard written `[ -r "$_luks_detail" ]` rather than `-s` must
still count as GUARDED.

**Motivating input (acceptance anchor).** `runcmd-all.code.sh` with one real
`[ -s "$_luks_detail" ]` guard deleted and `git-data-emit … # guarded by [ -s "$_luks_detail" ]`
left behind. Today: `GUARDED`, R3(3b)(ii) passes, the literal-leak branch reopens. After:
`UNGUARDED`, R3(3b)(ii) fails.

### Guard 8 — R3(3b) reporting-site set equality (#7613 finding 3)

**Property.** The set of reporting sites equals the expected set — not "at least six of
something".

**Assembly.** `_r3b_n -ge 6` (the floor being replaced) and sub-assertion (iv)'s existing
message-literal set equality against `_r3b_want`. **The site key is `window|arg4`, deliberately
orthogonal to (iv)'s `msg` keying**, so the fatal-message subset stays pinned in exactly one
place (ADR-176). The replacement's failure message must keep naming vacuity — the floor's
in-file comment reads *"The extraction produced nothing usable, so every verdict below is
vacuous"*, and that reason must survive the rewrite.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Delete one reporting site and add an unrelated one | yes — the motivating input; the `-ge 6` floor holds today |
| M2 | Delete one reporting site without adding any | yes — caught by the floor today, must remain caught |
| M3 | Add a site not in the expected set | yes, naming the unexpected member (**second member**) |
| M4 | Key the site set on `msg` instead of `window\|arg4` | yes — a parity assertion against (iv) reddens, because the fatal subset would then be pinned twice |

**Must-PASS (non-canonical).** Reordering the sites in the source must pass — the property is a
set, not a sequence.

### Guard 9 — the standing skip monitor (#7574)

**Property.** The monitor reports `PASS` only from a sample it actually read; `FAIL` whenever a
loud SKIP **from this suite's own arms** appears in that sample; `TRANSIENT` otherwise; and a
run of consecutive TRANSIENTs escalates rather than repeating forever.

**Assembly.** The log-fetch loop's `SUITE_TERMINAL` positive control; the **enumerated marker
set** (`SKIP (loud): T5 `, `SKIP (loud): S1 `) — after #7572 there are two skip-eligible arms,
and after this change there is one more foreign emitter in the same run log; the five distinct
exit-2 branches; and the carrier workflow that turns a verdict into something a person sees.

**Mutation matrix.**

| # | Edit | Must drive RED |
|---|---|---|
| M1 | Restore `printf '%s' "$log" \| grep -qF …` under `pipefail` | yes — a fixture with the terminal line and a skip must yield exit 1; today it yields exit 2 |
| M2 | Replace the enumerated marker set with the bare `SKIP (loud): ` prefix | yes — **a fixture log carrying `infra-config-apply.test.sh`'s `SKIP (loud): not root…` and no rehearsal skip must yield exit 0.** Verified: that line fires on every non-root runner and both suites share a run log |
| M3 | Narrow the set back to `SKIP (loud): T5 MUTATION` | yes — an S1-only fixture must still yield exit 1 (**second member after a compliant first**) |
| M4 | Remove the `SUITE_TERMINAL` positive control | yes — a sample with no suite output must yield exit 2, never exit 0 (**own dispatch**) |
| M5 | Return PASS on the Nth consecutive TRANSIENT | yes — the escalation must fire |
| M6 | Re-enrol the probe on the follow-through sweeper | yes — a lifecycle assertion reddens: the sweeper closes on PASS and `closed_precheck` then refuses to re-litigate, so the monitor would retire itself after one run |

**Must-PASS (non-canonical).** A fixture log carrying the suite terminal line and `Skipped: 0`
must yield exit **0** — the monitor must not have become one that fails on everything.

**Motivating input (acceptance anchor).** The measured 2026-08-19 sample: 20 logs, each
containing `git-data-runcmd-rehearsal:`, exercised through the real loop. Today: exit 2,
`observed=0`, twenty broken pipes. After: `observed=20` and a real verdict.

---

## Implementation Phases

Dependency-ordered, not file-ordered. **Every RED step is its own commit**, and the separation
is asserted from git history rather than from a pasted transcript.

### Phase 0 — Preconditions (no code)

0.1 Confirm `python3 -c 'import yaml'` locally and note the CI runner's version.
0.2 Run `scripts/lint-shell-capture-exit.py` and `scripts/lint-workflow-errexit-capture.py`
    explicitly against both workflows and record the verdict. Expected, measured: the former
    reports `2 script(s) scanned, 0 new findings` and structurally cannot see `.yml`; the latter
    has no trigger **yet**. Phase 2 creates the latter's trigger, so this is a baseline, not a
    clean bill.
0.3 Measure and record the wall-clock of one full
    `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`. Use the measured figure,
    not #7613's "~4-minute" estimate.
0.4 Record the suite's terminal line and confirm the absolute floor stanza is `total < 49`.
0.5 Confirm `scripts/lint-orphan-test-suites.sh` passes.
0.6 Identify the `TEST_GROUP` block in `scripts/test-all.sh` that CI's `scripts` shard runs, so
    Phases 1.5 and 6.5 register into it rather than into a block that never executes.
0.7 **Stripper spike — before Phase 4's ADR amendments, not after.** Render and extract the two
    real artifacts and re-run the measurement recorded in the Decision Challenge. Confirm: 0
    `#` in `luks-stage.sh`, 1 in `runcmd-all.sh`, zero at-risk tokens in either. Run the three
    candidate strip shapes against the **synthesized fixture** and confirm only
    `[[:space:]]+#([[:space:]].*)?$` preserves all of them. Run `bash -n` before and after on
    both artifacts. **If the spike contradicts the measurement, Phase 5 drops the stripper and
    #7613 closes on Guards 6–8 alone** — the eight-arm enumeration is unchanged either way,
    because the anchoring re-flows the same eight arms.

### Phase 1 — #7629 RED: the step-body harness, failing

1.1 Create `scripts/skill-security-scan-step-body.test.sh`, copying the extraction shape from
    `scripts/follow-through-closure-guard.test.sh` (`python3` + `yaml.safe_load`, select by
    `name`, assert exactly one hit, write the body to a file, execute under `bash -e`).
1.2 Ship the **extraction/dispatch guard first** (Guard 1): the shape predicate, the four
    in-scope bodies, the written-down exclusion set with its reason, and an assertion floor that
    does not route through the suite's own `fail()`.
1.3 Add the fixtures. **Every fixture CWD must carry stubs for *both* scripts the body invokes**
    — `run-scan.sh` **and** `parse-override.sh` — plus `jq` on PATH. Without the
    `parse-override.sh` stub the scan body aborts at its very first assignment under
    `set -euo pipefail` (`bash` exits 127, `pipefail` propagates), which would make a RED
    fixture pass for the wrong reason and fabricate the RED evidence.
    - **1a** two-commit fixture repo, `BASE_SHA=000…000` → assert non-zero exit **and** an
      `::error::` naming the pair.
    - **1b** stub `run-scan.sh` writing a traceback to stderr, exit 1 → assert non-zero exit
      **and** the traceback text present.
    - **1c** stub whose first stdout line is `usage: run-scan.sh [file]`, exit 0 → assert
      non-zero exit **and** that the output names the rejected verdict token, so the assertion
      cannot be satisfied by an unrelated abort.
    - **1d** `no_new_skills=false` with every path unreadable → assert non-zero exit (P2b).
    - **1e** postmerge fixture with an unresolvable `HEAD^1` → assert non-zero exit.
    - **1f** the `merge_group` base/head shape → must-PASS.
    - **1g** the must-PASS rows from Guards 1–3.
1.4 **Run it. It must fail on 1a–1e and pass on 1f/1g against unmodified workflows.**
1.5 Register with an explicit `run_suite "scripts/skill-security-scan-step-body" bash
    scripts/skill-security-scan-step-body.test.sh` inside the `scripts` `TEST_GROUP` block, and
    confirm `scripts/lint-orphan-test-suites.sh` passes.
1.6 Commit — harness only, no workflow edits. The commit message records that it is red by
    design and names Phase 2 as the closer.

### Phase 2 — #7629 GREEN

2.1 pr-trailer diff step: separate `git diff` from `grep`; the `grep`'s `|| true` survives
    verbatim. Keep the assignment at top level — **`if ! local raw=$(cmd)` masks the status**
    (verified), so this must not be refactored into a helper.
2.2 pr-trailer scan step: **capture the scanner's output to a variable or file first, then take
    its first line — never `head -1` inside a pipeline whose status is read** (Guard 3 M7).
    Capture stderr instead of discarding it; capture the exit status using the
    `set +e` / `|| rc=$?` form `lint-workflow-errexit-capture.py` requires; accept only the three
    verdicts; emit the captured stderr in the `::error::`. Apply the same to the
    `parse-override.sh` invocation's `2>/dev/null`. Add the scanned-count assertion (P2b). Keep
    `SKILL_SECURITY_SCAN_OFFLINE=1` at both call sites.
2.3 postmerge: apply 2.1 and 2.2 to its single audit body; fix `parent=$(git rev-parse HEAD^1 …)`
    so an unresolvable base fails rather than reading as "nothing added"; and replace
    `gh issue create … || true` so a lost compliance record is reported rather than swallowed.
2.4 `run-scan.sh`: correct the header's exit-code contract. Verified by fixtures 1b/1c
    demonstrating a non-zero exit, not by a grep for the new comment text.
2.5 Re-run Phase 1's suite: every RED fixture passes, every must-PASS row still passes.
2.6 Do **not** rename the job.

### Phase 3 — #7572: the S1 arm

3.1 **RED first.** Extract the classifier as a pure function over
    `(container_rc, marker_seen, fixture_marker_seen, primary_reached)` returning
    `ran | fixture-defect | harness-defect | did-not-run`, **porting T5's four-rung ladder and
    an `_S1_ENV_RCS` allowlist**. Add its negative controls in the R3(2c) in-file shape and run
    them; they fail today because no such function exists.
3.2 **GREEN.** Emit the in-container execution marker; add the structural guard on the
    **mounted** artifact; capture the container rc; route the five container-dependent
    assertions through the classifier; leave the two container-independent ones unconditional.
3.3 **The skip decision tree, stated explicitly** — the invariant alone cannot police it:
    - errexit-ordering assertion: always runs (1).
    - healthy container: `ran` → 2 assertions; `did-not-run` → `arm_skip … 2`;
      `harness-defect`/`fixture-defect` → 2 `fail`s.
    - mutation-landed check: always runs (1).
    - **if the mutation did not land**, the existing branch already emits 3 substitute `fail`s
      — do **not** also call `arm_skip … 3`, or the arm totals 10.
    - if it landed: `ran` → 3 assertions; `did-not-run` → `arm_skip … 3`; defect rungs → 3
      `fail`s.
    Assert `passes + fails + SKIPPED_ASSERTIONS == 7` for S1 **and** an S1-specific
    `SKIPPED_ASSERTIONS_S1 <= 5`, snapshotting the global counters around the arm and taking the
    snapshot **before** the assertion that reads it so the check does not perturb its own input.
3.4 Skip message carries rc, its `_S1_ENV_RCS` classification, marker seen, healthy-run marker
    seen, and the stdout tail.
3.5 **Raise `_SKIP_CEILING` to 5 with an itemised stanza** in the file's established shape
    (`T5 mutation 2; S1 healthy 2; S1 mutation 3`), and add an assertion that the number of
    `arm_skip` call sites matches the stanza's declared list. **Do not derive the ceiling** —
    doing so makes `SKIPPED_ASSERTIONS <= _SKIP_CEILING` an identity (AP-023) and reverses
    ADR-188's recorded decision without the amendment Phase 4 supplies.
3.6 Record and guard the residual: S1 loses its own primary-fails bound, so the composite bound
    now rests on T5's primary. Assert that T5's primary arm is not itself skip-eligible.
3.7 One full end-to-end suite run; reconcile the terminal line against Phase 0.4.

> **Scope-out with rationale.** T17's and R1's `|| true` rc discards and `run_case()`'s
> `exit 100, expected 0` misclassification are named in #7572's "Adjacent, same file" section;
> the issue itself says `run_case`'s defect *"has a different defect worth its own
> measurement"*. Deferred with a tracking issue.

### Phase 4 — ADR amendments (after Phase 0.7's spike, before Phase 5 ships)

4.1 Amend `ADR-152`: add the `.code.sh` row to its #7278 rule table and correct its
    *"does not touch mid-line or trailing `#`"* sentence to scope it to the render.
4.2 Amend `ADR-188`: record the raised ceiling and the call-site-count assertion, restate why
    full derivation is still rejected (AP-023), and record that S1's primary-fails bound is
    removed and the composite bound now rests on T5's primary.
4.3 No new ADR is created; the ordinal probe is recorded in the Architecture Decision section
    only so a future reader knows it ran.

### Phase 5 — #7613: eight arms, anchored

**5.0 — the prophylactic stripper** (contingent on Phase 0.7). Change both extraction sites to
`[[:space:]]+#([[:space:]].*)?$`, **blanking the tail in place rather than deleting the line**
so line numbers are preserved for the ordering predicates. Ship Guard 5's live assertions, its
synthesized fixture, and the `_b2_strip` parity assertion. State plainly, in the file's own
comment, that this is prophylactic: it changes one line in one artifact and no arm's verdict.

**5.1 — the eight enumerated arms.** Read off the file; the suite's own comment names the second
group (*"its four consumers (R3(3b), R3(3c), R3(3d), R3(2d))"*). The RED for each is the
**anchoring** change, which re-flows all eight — this is where the per-arm budget is paid.

Consumers of **`luks-stage.code.sh`**:

| Arm | RED (must fail before the fix, pass after) | Shares fixture |
|---|---|---|
| **R3(1)** | seed relocated below the trap, trailing comment naming the token above it | A |
| **R3(2)** | same input — ordering by line number, not co-presence | A |
| **R3(2b)** | same input | A |
| **R3(2c)** | its own two inline greps left bare while the seed call site is anchored — the control would otherwise certify an anchoring the arms no longer use | A′ |

Consumers of **`runcmd-all.code.sh`** (`_R3B_SRC`):

| Arm | RED | Shares fixture |
|---|---|---|
| **R3(3b)** | (ii) one real `[ -s "$_luks_detail" ]` deleted with a trailing comment naming it; (i)→set: one site deleted and one unrelated added | B, C |
| **R3(3c)** | its `sed` applied to a source whose only occurrence of the pattern is in a trailing comment — the mutation must land on real code, and its `cmp -s` did-not-land guard must still fire | B′ |
| **R3(3d)** | a source where a trailing comment matches the deletion `sed`'s shape | B |
| **R3(2d)** | `_r2d_ordered`'s anchor removed — this arm is the **control proving the anchoring style works**, so its RED is a mutation of the anchor itself, and its behaviour must otherwise be unchanged | D |

Four distinct fixtures (A, B, C, D) plus two variants; every arm has a real failing direction
and a named verdict.

**5.2 — must-not-change controls.** Enumerate **every** reader of the raw artifacts, not just
B2: `_b2_strip`-based B2, and S1's `_s1_stage_ln` / `_s1_sete_ln` greps over
`$TMP/runcmd-all.sh`. Assert each verdict is unchanged. Note that after 5.0 B2's corpus and
R3's are the same bytes by two routes, so B2 is a **redundant-implementation cross-check**
(guarded by the parity assertion), not independent evidence — the plan says so rather than
claiming a control it no longer has.

**5.3 — verification budget, stated honestly.** At the predicate level all eight arms and the
controls are pure text over `$TMP/*.code.sh`. At the suite level **none is reachable without
docker**: the suite hard-exits on any missing dependency and `_skip()` under `CI=true` is
`exit 1`. So the per-arm loop runs the predicates directly against a corpus captured once from
a full run — a development aid — and the **shipped evidence** is two full suite runs, an
integration RED before 5.0 and an integration GREEN after 5.1. A predicate proven only outside
the suite is the antipattern Guard 1 M3 forbids for #7629.

**5.4 — floor re-derivation.** Replacing R3(3b)'s floor with a set changes the arm's assertion
count. Re-derive the absolute floor and the extraction-failure `else` branches'
cardinality-parity `fail` counts in the same edit; re-record the terminal line.

### Phase 6 — #7574: repair the probe, enumerate the marker, re-home the carrier

6.1 **RED first.** Create `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` with a
    fake `gh` on `PATH` serving fixture logs. Fixtures: (a) terminal line + `SKIP (loud): T5 …`
    → exit 1; (b) terminal line + `SKIP (loud): S1 …` → exit 1; (c) terminal line + no skip →
    exit 0; (d) **terminal line + `infra-config-apply.test.sh`'s `SKIP (loud): not root…` and no
    rehearsal skip → exit 0**; (e) no terminal line → exit 2; (f) `gh` unavailable → exit 2;
    (g) zero successful runs → exit 2. Run it: (a), (b) and (c) fail today, all returning exit 2.
6.2 **GREEN.** Replace the `printf | grep -q` form with one that cannot lose a match to EPIPE
    (a here-string or a captured file). Apply the same form to the counting line **for
    consistency, not for correctness** — `grep -c` reads to EOF and never breaks the pipe.
6.3 Replace `SKIP_MARKER` with the **enumerated set** `SKIP (loud): T5 `, `SKIP (loud): S1 `,
    and make the FAIL message a per-arm breakdown. Keep the `SUITE_TERMINAL` positive control
    untouched — it is the one thing in the file that worked. Fix the denominator inconsistency
    (PASS reports over `observed`, FAIL over `sampled`).
6.4 Add an **N-consecutive-TRANSIENT escalation**, so a permanently broken `gh` auth stops being
    indistinguishable from a healthy quiet window.
6.5 Update the header comment (it describes a T5-only probe) and register the new test with an
    explicit `run_suite` line in the `scripts` `TEST_GROUP`.
6.6 **Re-home the carrier.** Retire the `<!-- soleur:followthrough … -->` directive on #7574 and
    add `.github/workflows/scheduled-rehearsal-skip-monitor.yml`, which runs the probe daily and
    opens/updates an alert issue on exit 1. Rationale in the workflow header: the follow-through
    sweeper closes on PASS and `closed_precheck` then refuses to re-litigate, so a repaired probe
    enrolled there would retire itself after one run.

### Phase 7 — Integration

7.1 Full suite run; reconcile the terminal line against Phase 0.4.
7.2 `bash scripts/test-all.sh` for the affected groups, plus
    `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` — which now
    covers **both** new `scripts/` suites.
7.3 Confirm `MAX_DEFERRED=47` has not moved.
7.4 Re-run Phase 0.2's two linters, now that Phase 2.2 has created the errexit-capture trigger.

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/skill-security-scan-step-body.test.sh` | Guards 1–3. Extracts and executes the four in-scope `run:` bodies across both workflows. |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` | Guard 9. Drives the probe against seven fixture samples through a fake `gh`. |
| `.github/workflows/scheduled-rehearsal-skip-monitor.yml` | Guard 9's carrier — a standing daily monitor that does not retire itself on first PASS. |

No RED-proof transcript files. The RED-before-GREEN property is asserted from git history
instead (AC2, AC29), which is re-derivable by any reviewer forever; a pasted transcript is the
one artifact that is not.

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/skill-security-scan-pr-trailer.yml` | Separate `git diff` from `grep`; capture-then-first-line; capture stderr and exit status via `set +e`/`\|\| rc=$?`; fail closed on any non-verdict; scanned-count assertion; stop discarding `parse-override.sh` stderr; keep `SKILL_SECURITY_SCAN_OFFLINE=1`. |
| `.github/workflows/skill-security-scan-postmerge.yml` | The same, plus the `parent=` base-resolution fix and the `gh issue create … \|\| true` fix. |
| `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` | Correct the false exit-code contract in the header. |
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | S1 rc capture, execution marker, structural guard, four-rung classifier with `_S1_ENV_RCS`; raised `_SKIP_CEILING` + call-site-count assertion; prophylactic `.code.sh` strip + parity assertion; seed and `gpat` anchoring; R3(3b) floor → set keyed on `window\|arg4`; floor and cardinality re-derivation. |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` | EPIPE repair; enumerated marker set with per-arm breakdown; TRANSIENT escalation; denominator fix; header correction. |
| `scripts/test-all.sh` | Two explicit `run_suite` registrations inside the `scripts` `TEST_GROUP` block. |
| `knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md` | Amendment: the `.code.sh` rule-table row; scope the "does not touch mid-line or trailing `#`" sentence to the render. |
| `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` | Amendment: raised ceiling + call-site assertion; why full derivation stays rejected; S1's lost primary-fails bound. |

Every path above was confirmed present in the worktree. No path glob is prescribed.

---

## Acceptance Criteria

### Pre-merge (PR)

**#7629**

- [ ] **AC1** `bash scripts/skill-security-scan-step-body.test.sh` exits 0 with zero failures.
- [ ] **AC2 (RED-before-GREEN, re-derivable)**
      `git log --diff-filter=A --format=%H -- scripts/skill-security-scan-step-body.test.sh`
      yields a SHA whose `git show --name-only <sha>` contains **no**
      `.github/workflows/skill-security-scan-*` path. The harness landed before the fix, and
      anyone can re-check it from history.
- [ ] **AC3** The extracted diff body with `BASE_SHA=0000000000000000000000000000000000000000`
      against a two-commit fixture repo exits **non-zero** and emits an `::error::` naming the
      base/head pair.
- [ ] **AC4** The same body with valid SHAs and no matching added files exits **0** with
      `no_new_skills=true` — the `grep`'s `|| true` survives.
- [ ] **AC5** The extracted scan body against a stub `run-scan.sh` that writes a traceback to
      stderr and exits 1 exits **non-zero**, with the traceback text in the captured output.
- [ ] **AC6** The same against a stub whose first stdout line is `usage: run-scan.sh [file]`
      (exit 0) exits **non-zero**, **and the output names the rejected verdict token** — so the
      assertion cannot be satisfied by an unrelated abort.
- [ ] **AC7** Verdict `REVIEW`, and `HIGH-RISK` with a matching override, both exit **0**; so
      does a scanner emitting leading noise before a valid verdict line.
- [ ] **AC7b** With `no_new_skills=false` and every path failing `[ ! -f "$path" ]`, the step
      exits **non-zero** — scanned-path count must equal added-path count.
- [ ] **AC8** AC3, AC5, AC6 and AC7b hold for postmerge's **single** audit body
      (`Detect merged HIGH-RISK skills without override`); its other `run:` step is
      `jq --version` and is out of scope.
- [ ] **AC8b** A postmerge fixture whose `HEAD^1` does not resolve exits **non-zero** rather
      than reporting "No SKILL/agent files added in this push".
- [ ] **AC8c** The `merge_group` base/head shape against a resolvable fixture exits **0**.
- [ ] **AC9** `grep -rn "|| echo 'UNKNOWN'" .github/workflows/ | wc -l` prints `0`. Measured on
      `main`: `2`. Scoped to `.github/workflows/` deliberately — the two `.claude/hooks/` sites
      are correct as-is and are cited as precedent, not edited.
- [ ] **AC10** `run-scan.sh`'s header no longer claims an unconditional exit 0, and fixture 1b
      demonstrates a non-zero exit from the real script.
- [ ] **AC10b** `SKILL_SECURITY_SCAN_OFFLINE=1` is present at both scan call sites, and neither
      workflow's scan step contains `head -1` inside a pipeline whose status is read.
- [ ] **AC11** `scripts/lint-orphan-test-suites.sh` exits 0, and both new suites are registered
      by explicit `run_suite` lines **inside the `TEST_GROUP` block CI's `scripts` shard runs**.
- [ ] **AC12** `bash scripts/guard-vacuity-floor.test.sh` exits 0 with **both** new suites
      inside `COVERED_DIRS`.
- [ ] **AC13** `grep -c 'name: skill-security-scan PR gate' .github/workflows/skill-security-scan-pr-trailer.yml`
      prints `1`.

**#7572**

- [ ] **AC14** `(rc ∈ _S1_ENV_RCS, marker absent)` → `SKIP (loud): S1 …`, and the arm does not
      emit `S1 is no longer reproducing the measured failure`.
- [ ] **AC15** `(rc != 0, marker present)` → the arm asserts normally.
- [ ] **AC15b** `(rc == 0, marker absent)` → the arm **fails** as a harness defect. It is never
      routed to a skip.
- [ ] **AC15c** `(rc ∉ _S1_ENV_RCS, marker absent)` → the arm **fails** as a harness defect.
- [ ] **AC16** Deleting the execution-marker emission from the mounted artifact makes the suite
      fail loudly, not skip.
- [ ] **AC17** For every S1 path — healthy, mutation, container-skip, extraction-failure, **and
      container-skip × mutation-did-not-land** — S1's
      `passes + fails + SKIPPED_ASSERTIONS == 7`, with the counters snapshotted before the
      assertion that reads them.
- [ ] **AC17b** `SKIPPED_ASSERTIONS_S1 <= 5`. Skipping all 7 must fail this bound; it satisfies
      AC17's invariant (`0 + 0 + 7 == 7`) and so cannot be detected there.
- [ ] **AC18** The two container-independent assertions still execute and count when the
      container path is skipped.
- [ ] **AC19** `_SKIP_CEILING` is the literal `5` with an itemised stanza, **not** derived; and
      an assertion reddens when the `arm_skip` call-site count and the stanza disagree in either
      direction.
- [ ] **AC20** The skip message carries rc, its `_S1_ENV_RCS` classification, marker seen,
      healthy-run marker seen, and the stdout tail.
- [ ] **AC20b** T5's primary arm is asserted not to be skip-eligible, since the composite
      degraded-environment bound now rests on it alone.

**#7613**

- [ ] **AC21** Over the **synthesized fixture**: a trailing comment is removed from both
      `.code.sh` artifacts. *Not over the live artifacts — measured, the luks stage contains
      zero comments, so the live form of this assertion is unsatisfiable.*
- [ ] **AC22** Over the **live** artifacts: `mkfs.ext4` and `git-data-emit` survive;
      `len(_all_code.splitlines()) >= 40`; the line count is unchanged; `bash -n` parses raw and
      stripped; every diff hunk is a pure suffix removal beginning at `#`; and
      `runcmd-all.code.sh` equals `_b2_strip("$TMP/runcmd-all.sh")` byte for byte.
- [ ] **AC22b** Over the fixture: `[ "$#" -ge 4 ]`, `${kv#*=}`, `${v##x}`, `sed -E 's#a#b#'`,
      `echo "issue #7613"` and an indented `#!/bin/sh` all survive; only the trailing comment's
      tail is removed; the line count is unchanged.
- [ ] **AC22c** Applying `_b2_strip`'s shape to the fixture drives AC22b **RED**; applying
      `s/[[:space:]]\+#.*$//` drives it RED on the shebang row.
- [ ] **AC23 (per-arm, `luks-stage.code.sh`)** On the motivating input — the real assignment
      relocated below `trap luks_err EXIT` with a trailing comment naming the token above it —
      **R3(1), R3(2) and R3(2b) each FAIL**, and each PASSes on the unmodified stage. R3(2c)'s
      control lands on real code with its own greps anchored.
- [ ] **AC24 (per-arm, `runcmd-all.code.sh`)** On the motivating input — one real
      `[ -s "$_luks_detail" ]` deleted with a trailing comment naming it — **R3(3b)(ii) reports
      UNGUARDED and FAILs**. R3(3c), R3(3d) and R3(2d) each land their own mutation on real code
      and each flip as designed; R3(2d)'s RED is a mutation of its own anchor.
- [ ] **AC25** R3(3b)'s count floor is replaced by a **set** comparison keyed on
      `window|arg4`: deleting one site and adding an unrelated one FAILs and names both members;
      reordering still PASSes; and a parity assertion prevents the fatal-message subset being
      pinned both here and in sub-assertion (iv).
- [ ] **AC26** The verdicts of **every** raw-artifact reader are unchanged — B2 and S1's
      `_s1_stage_ln`/`_s1_sete_ln`.
- [ ] **AC27** The absolute floor and the extraction-failure cardinality-parity counts are
      re-derived, and the terminal line reconciles against Phase 0.4 with the delta explained.
- [ ] **AC28** `apps/web-platform/infra/modules/git-data-userdata/main.tf` and
      `git-data-userdata-budget.sh` are unchanged
      (`git diff --name-only origin/main | { grep -c 'git-data-userdata' || true; }` prints `0`
      — the brace group is load-bearing, since `grep -c` exits 1 on zero matches), and
      `git-data-template-strip.test.sh` and `git-data-render-strip-parity.test.sh` both pass.

**#7574**

- [ ] **AC29 (RED-before-GREEN, re-derivable)**
      `git log --diff-filter=A --format=%H -- scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`
      yields a SHA whose `git show --name-only <sha>` does not contain
      `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`.
- [ ] **AC30** Fixture (a) terminal line + T5 skip → exit **1**; (b) terminal line + S1 skip →
      exit **1**; (c) terminal line, no skip → exit **0**; (e) no terminal line → exit **2**.
- [ ] **AC31** Fixture (d) — terminal line plus `infra-config-apply.test.sh`'s
      `SKIP (loud): not root…` and **no** rehearsal skip — returns exit **0**. Without this the
      widened marker returns FAIL on every hosted run, forever.
- [ ] **AC32** No `write error: Broken pipe` on any fixture.
- [ ] **AC33** N consecutive TRANSIENTs escalate rather than repeating indefinitely.
- [ ] **AC34** The probe is invoked by `.github/workflows/scheduled-rehearsal-skip-monitor.yml`
      and **not** by a `<!-- soleur:followthrough … -->` directive. Checkable at PR time, unlike
      a claim about issue state after merge.
- [ ] **AC35** The FAIL and PASS messages report over the same denominator.

**Cross-cutting**

- [ ] **AC36** `ADR-152` and `ADR-188` each carry an amendment recording their respective
      reversals; no new ADR ordinal is claimed.
- [ ] **AC37** `grep -oE 'knowledge-base/[A-Za-z0-9/_.<>-]+\.md' <this plan> | sort -u` yields
      only paths that exist. The character class includes `<>` so a `<branch>`-style placeholder
      is caught rather than silently skipped; verified at plan-write time with zero unresolved
      paths.
- [ ] **AC38** The PR body carries `Closes #7629`, `Closes #7572`, `Closes #7574`,
      `Closes #7613` (body, not title).

### Post-merge (operator)

None. Every step runs in CI or locally. No terraform apply, no vendor dashboard, no credential
mint, no SSH. The skip monitor is a scheduled workflow using an already-wired token.

---

## Test Scenarios

| # | Mutation | Guard that must redden |
|---|---|---|
| T1 | Re-merge `git diff` and `grep` under one `\|\| true` | Guard 2 M1 |
| T2 | Restore postmerge's `\|\| git rev-parse HEAD` fallback | Guard 2 M2 |
| T3 | Fix pr-trailer only | Guard 2 M3 |
| T4 | Refactor the diff assignment into a helper using `local` | Guard 2 M5 |
| T5 | Restore `\|\| echo 'UNKNOWN'` | Guard 3 M1 |
| T6 | Restore `2>/dev/null` on the scanner | Guard 3 M2 |
| T7 | Make every path fall through `[ ! -f "$path" ]` | Guard 3 M5 |
| T8 | Delete `SKILL_SECURITY_SCAN_OFFLINE=1` | Guard 3 M6 |
| T9 | Restore `head -1` in a status-read pipeline | Guard 3 M7 |
| T10 | Rename an in-scope step in either YAML | Guard 1 M1 |
| T11 | Add a fifth `run-scan.sh`-invoking step, unregistered | Guard 1 M2 |
| T12 | Point extraction at a workflow copy with `\|\| true` restored | Guard 1 M3 |
| T13 | Neuter the suite's `fail()` | Guard 1 M4 |
| T14 | Delete the S1 execution marker from the mounted artifact | Guard 4 M1 |
| T15 | Restore the bare `docker run` with no rc capture | Guard 4 M2 |
| T16 | Classify `(rc==0, marker absent)` as a skip | Guard 4 M3 |
| T17 | Widen `_S1_ENV_RCS` to any non-zero | Guard 4 M4 |
| T18 | Add a third `arm_skip` call site without raising the ceiling | Guard 4 M6 |
| T19 | Raise the ceiling without adding a call site | Guard 4 M7 |
| T20 | Skip all 7 S1 assertions | Guard 4 M8 (**not** the cardinality invariant) |
| T21 | Revert `_code` to whole-line-only, `_all_code` fixed | Guard 5 M2 |
| T22 | Widen the strip to `_b2_strip`'s shape | Guard 5 M3 |
| T23 | Make the strip delete the line rather than blank the tail | Guard 5 M5 |
| T24 | Change `_b2_strip` without changing the heredoc sites | Guard 5 M7 |
| T25 | Unanchor the seed call site | Guard 6 M1 |
| T26 | Anchor the call site, leave R3(2c)'s inline greps bare | Guard 6 M2 |
| T27 | Delete a call site's `[ -n … ]` test | Guard 6 M4 |
| T28 | Remove `gpat`'s line-prefix rejection | Guard 7 M1 |
| T29 | Delete a real guard **and** its comment | Guard 7 M2 |
| T30 | Delete one reporting site, add one unrelated | Guard 8 M1 |
| T31 | Key the site set on `msg` | Guard 8 M4 |
| T32 | Restore the `printf \| grep -q` form under `pipefail` | Guard 9 M1 |
| T33 | Replace the marker set with the bare prefix | Guard 9 M2 |
| T34 | Remove the `SUITE_TERMINAL` positive control | Guard 9 M4 |
| T35 | Re-enrol the probe on the follow-through sweeper | Guard 9 M6 |
| T36 (must-PASS) | `REVIEW`; `HIGH-RISK` + override; leading scanner noise; `merge_group` shape; tab-indented seed; `-r` instead of `-s`; reordered sites; clean sample with `Skipped: 0`; foreign-suite skip only | all stay GREEN |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Fail-closing a required check can stall the merge queue.** The gate is the sole producer of the required context on `gh-readonly-queue/main/*`; a systematic failure in the queue's ref topology would block every merge repo-wide. | Guard 2's must-PASS `merge_group` fixture (AC8c) is the coverage. `SKILL_SECURITY_SCAN_OFFLINE=1` removes network from the failure set (the scanner's only outbound host is reached from `check-supply-chain.sh` behind that flag), so remaining causes are runner-infrastructure failures that already red the job at checkout. A bounded retry is deliberately **not** added — ADR-188 rejected retry for converting the most likely occurrence class from visible to invisible. |
| **`head -1` under `pipefail` would make a successful scan fail the gate** once the pipeline's status is read — the #7574 defect aimed at a required check. Output scales with findings count. | Guard 3 M7 + AC10b: capture to a variable or file, then take the first line. Never `head -1` in a status-read pipeline. |
| **A trailing-comment strip is not a shell parser.** The shape #7613 recommends destroys `${var#pat}`, `$#` and `#`-in-string; a first refinement destroys the shebang. `main.tf` records the same measurement for its own corpus. | The measured shape `[[:space:]]+#([[:space:]].*)?$`, blank-in-place, gated by Guard 5's live assertions **and** a synthesized fixture — because the live corpus contains none of the at-risk tokens, so live-only assertions would be vacuous. Phase 0.7 re-measures before Phase 4. |
| **After the strip, `.code.sh` and `_b2_strip` are two implementations of one transform** (ADR-176), and B2 stops being an independent control. | A byte parity assertion between them, mirroring `git-data-render-strip-parity.test.sh`; the must-not-change control set widens to every raw-artifact reader; and the plan states B2's demotion rather than claiming a control it no longer has. |
| **The pre-merge gate is bypassable on bot PRs** via `bot-pr-with-synthetic-checks`, which posts a success check-run of the same name. | The post-merge audit is the control on that path, which is why both workflows are fixed. Recorded in User-Brand Impact rather than left implicit. |
| **The absolute floor moves with every assertion added or removed.** | Phase 0.4 baselines it; Phases 5.4 and 7.1 reconcile with the delta explained. |
| **Both new suites land in `guard-vacuity-floor.test.sh`'s `COVERED_DIRS`.** | Floors asserted directly against the assertion counter, not through `fail()`; AC12 runs the mutation guard on both. |
| **A `run_suite` line in the wrong `TEST_GROUP` registers a suite that never runs in CI's shard.** | Phase 0.6 identifies the block; AC11 asserts it. |
| **S1 loses its own primary-fails bound**, so the composite degraded-environment bound rests on T5's primary alone. | Recorded in the ADR-188 amendment and guarded by AC20b. |
| **The monitor's marker literals are hand-copied from the suite.** | The `SUITE_TERMINAL` positive control (untouched) plus Guard 9's fixture rows pin fixture and literal together; the enumerated set is narrower than a prefix and cannot pick up a foreign suite. |
| **`gh` API flakiness** (hit twice during planning). | The probe's TRANSIENT arm handles it, now with an escalation bound; no AC depends on a single `gh` call succeeding first try. |
| **Concurrent sessions.** No AC depends on another in-flight PR's state (`cq-ac-must-not-depend-on-concurrent-sessions`). |

---

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6.
  Filled above with a concrete artifact and a concrete exposure vector.
- **Do not rename the gate job.** `skill-security-scan PR gate` is pinned by ruleset #14145388,
  `scripts/required-checks.txt`, `.github/CODEOWNERS`, and five bot workflows.
- **`scripts/*.test.sh` is deliberately not a `SUITE_GLOBS` entry**, and the explicit `run_suite`
  line must sit in the `TEST_GROUP` block CI actually runs.
- **`grep -q` under `pipefail` loses a successful match to EPIPE.** This is #7574's defect and a
  repo-wide shape: `printf '%s' "$big" | grep -q X` in a `set -o pipefail` script scores a match
  as a miss whenever the producer still has bytes to write. `head -1` in a status-read pipeline
  is the same hazard from the other end.
- **`S1_RC` is not the container rc** — it is a marker parsed from the container's stdout. Any
  reasoning treating it as an exit status is the bug #7572 reports.
- **`_skip()` under `CI=true` is `exit 1`, not a skip.** The rehearsal suite does not degrade
  gracefully in CI, by design.
- **`_r3_ln` already returns empty on a missing anchor.** The loudness lives at the call sites'
  `[ -n … ]` tests; the function's comment claiming otherwise is aspirational.
- **`local x=$(cmd)` masks the command's exit status.** Verified. Relevant to Phase 2.1.
- **The follow-through sweeper is a one-shot closure verifier, not a standing monitor.** It
  closes on PASS and then refuses to re-litigate.
- **`.code.sh` is byte-identical to `.sh` today.** Any claim that the split already protects a
  predicate is false until Phase 5.0 lands — and after it lands, it protects one line no
  predicate reads.

---

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The change is confined to CI workflow shell, two shell test suites, one probe,
one new scheduled workflow, and two ADR amendments. It introduces no runtime code path, no
schema, no vendor, no persistent store and no new network edge — and deliberately preserves the
one env var (`SKILL_SECURITY_SCAN_OFFLINE=1`) that keeps an external host out of a required
check's dependency set. The load-bearing risks are enumerated above; the two that carry most
weight are the deliberate tightening of a required merge check from fail-open to fail-closed
(bounded by Guard 3's must-PASS rows and the `merge_group` fixture) and the S1 classifier's
fidelity to ADR-188's four-rung ladder (a 2×2 would route harness defects into the skip bucket).
The eight-arm enumeration is read off the file and corroborated by the suite's own comment
naming four of them; a four-reviewer panel independently confirmed it is complete and that
nothing else in the repo reads either `.code.sh` artifact.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit`
matched no UI-surface path — every entry is under `.github/workflows/`, `scripts/`,
`apps/web-platform/infra/*.test.sh`, `plugins/soleur/skills/*/scripts/`, or `knowledge-base/`.
No `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`. The semantic sweep also
returns NONE. Product not relevant → Step 2 skipped.

**Domains assessed and not relevant:** product, legal, finance, marketing, sales, support,
operations.

---

## GDPR / Compliance Gate

The canonical regulated-data regex does not match: no `.sql`, no `supabase/migrations/`, no auth
flow, no API route, no schema. Of the four expansion triggers only (b) fires — the plan declares
`single-user incident`. Assessed against it: the change processes **no personal data at any
point**. The workflows read a git diff of repository file paths and a verdict token; the suites
read rendered shell text and container stdout; the monitor reads Actions run logs for fixed
markers. No new processing activity, controller/processor relationship, Article 30 entry,
cross-border transfer or sub-processor. `run-scan.sh`'s `.scan-meta.json` PII redaction is
untouched.

**Verdict:** no compliance findings. Advisory only; not legal advice.

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **#7629: patch the eight lines without a harness.** | The issue is explicit that the verification is the work; a fix asserting "no longer fails open" that was never driven RED is the vacuous-guard class the cited learning documents. |
| **#7629: mock the workflow body inline.** | An inline copy asserts the *shape* of a body, not the body that runs. Guard 1 M3 forbids it. |
| **#7629: extract the two workflows' shared bodies into one script.** | Tempting — the byte-equivalence of the defects *is* copy-paste drift. Declined because the bodies are not identical (different SHA sources, different failure actions: `exit 1` vs filing a `compliance/critical` issue), so extraction is a refactor with its own design riding on a fail-open fix. Guard 3 M3 makes divergence a RED condition instead, closing the drift channel without the refactor. |
| **#7629: bounded retry before failing closed.** | `SKILL_SECURITY_SCAN_OFFLINE=1` removes network from the failure set, so retry buys nothing and incurs the cost ADR-188 rejected it for — converting the most likely occurrence class from visible to invisible. |
| **#7572: a 2×2 classifier on `(rc, marker)`.** | Routes every harness defect into the skip bucket. T5's four-rung ladder with an rc allowlist already exists and already litigated this; the plan ports it. |
| **#7572: derive `_SKIP_CEILING` from the call sites** (the issue's own suggestion). | Makes the assertion an identity (AP-023) and reverses ADR-188's recorded rejection. The literal is a shrink-only ratchet whose value is the decision it forces; a call-site-count assertion gets the drift detection without the tautology. |
| **#7572: a test-only env var to force a setup failure.** | Puts test-only branching into the artifact the suite exists to test faithfully. The extracted classifier plus an in-file negative control gets the same RED with no production-shaped seam. |
| **#7574: a persisted counter / Better Stack marker / six-hourly re-run.** | All buy P9, which the existing probe already computes. Cut at Phase 0.6b. |
| **#7574: keep the follow-through enrolment and just repair the probe.** | Measured: the sweeper closes on PASS and `closed_precheck` then refuses to re-litigate, so a repaired probe retires itself after one run. The mechanism is a one-shot closure verifier; #7574 asks for a standing monitor. |
| **#7574: close it as already-bounded because the probe exists.** | The probe has never reached a verdict, and its carrier would retire it if it did. |
| **#7613: change `git_data_template_rationale_strip` in `main.tf`.** | Production boot blast radius, a byte-mirrored copy under a parity test, and no gain — the findings are about what the *suite's predicates* read. |
| **#7613: the stripper as the primary mechanism.** | Measured no-op: 0 changed lines in the luks stage, 1 in the concatenation on a line no arm reads. Retained as prophylactic hardening per operator direction; see Decision Challenge. |
| **#7613: write a real shell lexer.** | Disproportionate. The measured shape plus the fixture and parity assertions bound the residual, and the artifact is test-only. |
| **#7613: `gpat` sanitises its window with a mini-strip.** | Inherits the lexing problem. Rejecting a match whose line-prefix contains `#` is narrower, local, and false-negative-only. |

---

## Non-Goals

- **Changing `git_data_template_rationale_strip` / `git_data_rationale_strip`** in
  `modules/git-data-userdata/main.tf` or their mirrors in `git-data-userdata-budget.sh`. These
  govern what boots real hosts, are guarded by `git-data-template-strip.test.sh` (five arms,
  including "every shebang survives") and `git-data-render-strip-parity.test.sh`, and ADR-152
  decided their scope. AC28 asserts they are untouched.
- **T17's and R1's `|| true` rc discards** and `run_case()`'s misclassification. Deferred with a
  tracking issue; the issue itself says `run_case` warrants its own measurement.
- **The deferred pre-baked rehearsal image (#7535).** This plan makes the verdict that would owe
  it reachable; it does not pre-empt it.
- **Renaming the gate job**, or touching `bot-pr-with-synthetic-checks` (#3593's subject) — its
  bypass is *documented* in User-Brand Impact and *compensated* by fixing the post-merge audit,
  not closed here.
- **Editing `.claude/hooks/skill-security-scan{,-write}.sh`.** Both handle an unknown verdict
  correctly already; they are cited as precedent.
- **Promoting `apps/web-platform/infra/` out of `guard-vacuity-floor.test.sh`'s
  `DEFERRED_DIRS`.**

### Deferral Tracking

Two issues to file. Labels verified to exist (`follow-through`, `deferred-scope-out`,
`domain/engineering`, `type/chore`, `priority/p3-low`).

1. **T17 / R1 rc discards and `run_case()`'s misclassification.** Re-eval trigger (event-grep):
   `exit 100, expected 0`, or a `|| true`-masked container failure, appearing in any post-merge
   `infra-validation.yml` run log for this suite.
2. **The cross-run skip residual**, tracking whatever the repaired monitor reports. Re-eval
   trigger: `scheduled-rehearsal-skip-monitor.yml` returning exit 1. This issue is a *tracker*,
   not the observer's carrier — the workflow is the carrier, precisely so closing the tracker
   cannot retire the observer.
