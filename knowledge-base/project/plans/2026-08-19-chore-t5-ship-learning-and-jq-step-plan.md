---
title: "Ship-phase learning capture for the T5 counted-skip merge, and replacement of the unbounded jq install steps"
date: 2026-08-19
slug: chore-t5-ship-learning-and-jq-step
branch: feat-one-shot-t5-ship-learning-and-jq-step
type: chore
lane: cross-domain
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Overview

Two small, independent deliverables in one PR.

**A.** One learning file under `knowledge-base/project/learnings/`, scoped to the CI
package-install-hang class — the genuinely uncovered material, and the class deliverable B fixes.

**B.** Replace the unbounded `apt-get install jq` step in the three `skill-security-scan-*`
workflows with a two-line `jq --version` assertion. `jq` ships on GitHub-hosted runners; the install
is redundant on every run and unbounded on failure, and one such stall gated a merge for ~1h.

No issue is closed by this PR. Issues 7572, 7574 and 7613 are context and stay open.

> **Two deviations from the brief, both review-driven, both surfaced rather than applied silently.**
> (1) Deliverable A is re-scoped: the `/compound` obligation it was to discharge was **already
> discharged** — two learning files shipped inside `45ea9f7e9` itself (§D1). (2) Deliverable B
> *replaces* rather than deletes, and covers three files rather than one (§D2, §D3). Both are filed
> to `decision-challenges.md`; the brief pre-authorized the widening *"unless the review phase argues
> otherwise — if it does, say so explicitly rather than silently widening."* Review argued otherwise.
> Saying so explicitly.

> **Plan lacks a spec — `lane:` defaulted to `cross-domain` (TR2 fail-closed).**

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured) | Plan response |
|---|---|---|
| "This closes the outstanding `/compound` ship-phase obligation for that merge." | **Stale.** `45ea9f7e9` itself commits two learning files: `2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md` and `2026-08-19-i-hardened-my-verifier-twice-and-its-sample-was-still-a-sample.md`. `ship/SKILL.md` Phase 2 detects prior capture via `git log --since="1 week ago" -- knowledge-base/project/learnings/`; the merge commit satisfies it. **No outstanding-obligation tracker exists in the repo.** | Re-scope A (§D1); file the tracker gap as an issue (§D4). |
| "seven findings flipped to fix-inline after two CONCUR passes" | **Unverifiable and inconsistent with the record.** Archived `tasks.md` §5.4: *"Six proposed rows became **three filings and three resolved decisions**, after two CONCUR rounds (both DISSENTed, both correctly)."* PR #7510 has **0** GitHub reviews/comments — the panel ran in-session. Likely provenance: the *7-agent panel* named in the 08-16 file's Sequel. | Do not restate the number. |
| "three deferred to the open issues named above" | **Two, not three.** #7574 and #7613 carry `deferred-scope-out`. **#7572 is `type/bug`** — the record says *"Filed as the DEFECT, not as 'S1 lacks arm_skip'."* | Describe #7572 as a filed defect. |
| "the S1 sibling arm carrying the same exposure" | **Holds, and already captured** — the 08-16 file cross-references *"#7572 (the S1 instance)"* and carries `related: [..., 7572, 7574, ...]`. | Cross-reference only. |
| `Install jq` at pr-trailer:63, unbounded | **Confirmed** — no timeout, no retry, no guard. | Replace (§D3). |
| "the sibling `Install psql` has retries and a timeout" | **Confirmed, with a correction:** it is not a sibling step in the same workflow — it is `web-platform-release.yml:340`, with `timeout-minutes: 5`, a 3-attempt retry, and a job cap whose comment cites #5559 hanging ~3h on it. | Cite accurately as cross-workflow precedent. |
| "the identical step in corpus.yml and postmerge.yml" | **Confirmed identical** — but the inventory is incomplete. **Seven jq-install sites exist, not three.** | Corrected inventory below. |
| (implicit) "jq is preinstalled on hosted runners" | **Supported, but the plan's first-draft figure was inflated.** Many workflow hits are `gh api --jq`, which uses gh's embedded gojq and says nothing about the `jq` binary. Re-derivation must exclude `gh --jq` (§Phase 0.4). | Re-measure; do not inherit a number. |
| Commit `45ea9f7e9`; ADR-188; issues OPEN | **All hold.** Merged 2026-08-19T17:43:52Z, closes issue 7291. | Proceed. |

### Corrected jq-install inventory (all seven sites)

The first draft claimed **four**. Wrong, and instructively so: the grep keyed on the step *name*
(`Install jq`), so it missed every **inline** install inside a larger `run:` block. The plan's
headline finding was that the brief's inventory was incomplete — and the plan then committed the same
error one level up. Re-derived with a content grep on the install command itself:

| # | Site | Form | Bounded? | In scope |
|---|---|---|---|---|
| 1 | `skill-security-scan-pr-trailer.yml:63-64` | `sudo apt-get update -qq && sudo apt-get install -y -qq jq` | **No** | **Yes** |
| 2 | `skill-security-scan-corpus.yml:40-41` | byte-identical to #1 | **No** | **Yes** (§D2) |
| 3 | `skill-security-scan-postmerge.yml:27-28` | byte-identical to #1 | **No** | **Yes** (§D2) |
| 4 | `sentry-audit-gate.yml:80-82` | `which jq \|\| install` | Guarded | No |
| 5 | `apply-sentry-infra.yml:532` | same guarded form | Guarded | No |
| 6 | `apply-sentry-infra.yml:673` | same guarded form | Guarded | No |
| 7 | `deploy-docs.yml:195-196` | `if ! which jq …` **and** warn-and-`exit 0` on failure | Guarded **and** degrades | No |

**Three are unconditional** (#1–#3) and constitute the class. **Four are guarded** (#4–#7) and need no
change. Note #7: a line-scoped grep of `:196` reads as unconditional, but line 195 wraps it in
`if ! which jq` — a one-line grep is not a characterization.

## Research Insights

### Premise validation and mechanism cuts

Four cited premises held (commit on `origin/main`; ADR-188 present; all three issues `OPEN`; the step
present and unbounded). Four were stale or imprecise — the outstanding-obligation claim, the "seven
findings" count, the "three deferred" classification, and the site inventory. All tabled above. The
three issues are **context, not work targets**; no artifact may carry a closing keyword for them.

**Properties sought:** P1 the T5 learnings are captured durably · P2 the `/compound` gate for
`45ea9f7e9` is satisfied · P3 the security gate cannot hang unbounded on package installation ·
P4 the review-panel outcome is traceable to the open issues.

| Mechanism proposed | Property | Disposition |
|---|---|---|
| A new learning file restating the T5 work | P1, P4 | **CUT** — already bought by the two files in `45ea9f7e9`, ADR-188, and archived `tasks.md` §5.4. |
| An action to satisfy the compound gate | P2 | **CUT** — `ship` Phase 2's own probe already passes on the merge commit. |
| Amend the 08-19 file's `related_issues` | P4 | **CUT** — the 08-16 parent (which the 08-19 file is a *Sequel* to) already carries 7572 and 7574. |
| Remove the unbounded install | P3 | **KEPT** — the only uncovered property. |

### Relevant institutional learnings

- `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` — a finding
  touching an already-documented pattern is *"routed as an amendment"*, not a new file (§D1). Also
  the precise class of this plan's own AC8 defect.
- `2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md`
  — a tracking row asserting work is outstanding after a PR discharged it re-creates staleness.
- `2026-04-29-bind-mount-seed-detection-needs-late-sentinel.md` — **`.github/workflows/*.yml` edits
  have been silently rejected by a PreToolUse hook**, returning reminder text without applying.
- `2026-06-10-fmt-alignment-blinds-token-anchored-guard-and-file-scoped-sweep-gap.md` and
  `integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md` — a sweep scoped to the
  named file while a sibling carried the identical defect; *"'X is unaffected' is a hypothesis."*
  Both argue for §D2.
- **No learning covers `apt-get` hangs or install timeouts in CI.** That is the gap deliverable A closes.

### Conventions that bind this plan

- **Learning path:** `knowledge-base/project/learnings/YYYY-MM-DD-<slug>.md` at **top level**
  (`compound/SKILL.md:354` routes there when `knowledge-base/` exists). Slugs are long, first-person,
  narrative.
- **No validator exists** for learnings frontmatter/filenames — nothing in CI, `lefthook.yml`, or
  `plugins/soleur/test/`. 5 of the 40 newest top-level files have no frontmatter and merged. The only
  mechanical constraints are the `kb-structure-guard` lefthook (rejects `knowledge-base/learnings/`)
  and the gitleaks-waiver trailer check. **Therefore this plan asserts no frontmatter-shape AC** — it
  would invent a constraint the repo does not have.
- `skill-security-scan PR gate` is a **required check** (`scripts/required-checks.txt:58`). Its
  `name:` carries a DO-NOT-RENAME comment; untouched here.
- `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` is the **canonical** auto-close scanner.
  Its keyword set — `\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)\b`,
  case-insensitive — is far broader than a hand-rolled `(Closes|Fixes|Resolves)`. Reuse, never restate.

### Related issues and PRs

PR #7510 (merged as `45ea9f7e9`, closes issue 7291) · #7565 (closed, rebase base) · **#7572 OPEN** (S1 arm
defect) · **#7574 OPEN** (`deferred-scope-out`, persistence bound) · **#7613 OPEN**
(`deferred-scope-out`) · #5559 (the ~3h `Install psql` hang motivating that step's cap).

## Decisions

### D1 — Deliverable A is re-scoped to the CI install-hang class

**Operator's stated direction (the default, recorded):** one file capturing the T5 counted-skip work.

**Measured obstacle:** that material is captured three times over already, and the 08-16 file states
the hazard in its own words: *"duplicating them would create two copies that can drift."*

**Plan default:** write **one** file whose subject is the **CI package-install-hang class** — no
learning covers it, and the correct bounded pattern sits one workflow away (`web-platform-release.yml:340`).
It pairs with deliverable B, which is what makes it a single coherent narrative.

**Explicitly NOT bundled:** the "obligation already discharged / brief numbers were stale"
meta-finding. Review flagged that bundling two unrelated subjects breaks the corpus convention (one
narrative per file) and makes neither discoverable. That finding is carried by
`decision-challenges.md` and the PR body instead — and the systemic half of it becomes §D4.

**Pinned slug** (not left to `/work` — see §Risks, ship's compound auto-invoke):
`2026-08-19-the-install-step-that-hung-was-installing-something-already-there.md`

**Fallback if review disagrees:** write the T5 restatement as literally briefed; its content is fully
enumerated in the two files plus §5.4, so the fallback is mechanical.

**User-Challenge** (ADR-084) — appended to
`knowledge-base/project/specs/feat-one-shot-t5-ship-learning-and-jq-step/decision-challenges.md`.

**RESOLVED 2026-08-19 — operator upheld the challenge.** Presented the three options (re-scope /
drop A entirely / write the T5 file as literally briefed) with the duplication evidence verified
independently: `git show --name-only 45ea9f7e9` lists both learning files, so the `/compound`
obligation was discharged inside the merge itself. Operator chose **re-scope**. The plan default
above is now the approved path; the fallback is retired and must NOT be taken by review.

### D2 — Scope widens to all three unconditional sites

The brief scoped deletion to pr-trailer *"unless the review phase argues otherwise."* **Review argued
otherwise, and the argument is new information the brief could not have had:**

- §D2's original case for staying narrow rested on blast radius — only pr-trailer is a required check.
  That establishes different **urgency**, not different **correctness**.
- What silently propped it up was a *verification* asymmetry: the narrow change looked self-verifying
  while widening looked post-merge-only. **The AC8 vacuity finding (§D3) dissolves that** — the
  pr-trailer change was not self-verifying either. The marginal verification cost of widening is now
  exactly **zero**.
- Leaving two known-defective copies preserves a **copy-source for regression**: the next
  `skill-security-scan-*` workflow will be authored by copying one of them, reintroducing the
  unbounded step into a family containing a required check.
- Correction to the original framing: `corpus.yml` is **`pull_request`**-triggered (path-filtered on
  `plugins/soleur/skills/skill-security-scan/**`), not schedule-driven. It does run on PRs.
- Holding narrow cost ~35 lines of plan and two ACs to justify not making a two-line change.

**Decision: widen to sites #1–#3.** The four guarded sites stay out of scope on any reading.

**RESOLVED 2026-08-19 — operator approved the widening and the §D3 replacement together.** The brief's
"unless the review phase argues otherwise" pre-authorization was not taken silently: the deviation was
put to the operator explicitly, against the alternative of deleting in `pr-trailer.yml` alone, with the
AC8 vacuity evidence confirmed independently (all four guarded `jq` sites sit behind
`if: steps.diff.outputs.no_new_skills == 'false'`; only the install step is unconditional). Operator
chose replace-across-three.

### D3 — Replace the step; do not merely delete it

Two independent reviewers (security, architecture) converged on this unprompted.

Pure deletion converts an *explicit* dependency into an *undeclared, unasserted* one. Worse, it
leaves the premise unverified: **every `jq` call site in pr-trailer sits inside a step guarded by
`if: steps.diff.outputs.no_new_skills == 'false'`**, and this PR adds no SKILL/agent files — so on
this PR the gate concludes `success` having never run `jq`. A green check would be identical in a
world with no `jq` at all. The failure would relocate to some future contributor's skill-adding PR.

**Replacement, at all three sites:**

```yaml
      - name: Assert jq present (runner-image dependency — no install, no network)
        run: jq --version
```

Two lines, no `apt-get`, no `sudo`, no network, bounded by construction, and **unconditional** — so it
executes on this PR's own run and on every future run. It removes the unbounded tail (the operator's
actual goal), keeps the dependency declared, and converts the verification from vacuous to real.

**Security bonus, worth stating in the PR body:** `apt-get update && apt-get install` was an
unpinned, root, network install running *inside the security-gate job immediately before the gate
runs* — able to replace the very binary that computes the verdict. `actions/checkout` and
`setup-bun` in the same file are SHA-pinned; this was the sole unpinned supply-chain input. Do **not**
overclaim: `jq` is not version-pinned before or after. The honest claim is "one fewer unpinned
network fetch in a required check."

### D4 — The systemic gap gets an issue, not just a learning

`wg-when-a-workflow-gap-causes-a-mistake-fix`: *"a learning is not a fix... Record a learning only
when no code change can address the gap."* The root cause behind the stale premise is that **nothing
records the result of `ship` Phase 2's compound probe** where a later session can read it. A code
change plainly could close that — but it belongs in `ship/SKILL.md`, not in this chore PR.

**Action: file a tracking issue** for the missing compound-obligation record. Also file one for the
two **pre-existing** P1 swallows security review found in the target workflow (below). Filing issues
is not closing them — the no-closure constraint is untouched.

**Pre-existing findings to track (NOT fixed here — out of scope, each deserves its own cycle):**
- `skill-security-scan-pr-trailer.yml:73-74` — `git diff … || true` conflates *"git diff failed"*
  with *"nothing added"*, yielding `no_new_skills=true` → both scan steps skip → green with zero
  coverage.
- `:138` — a scanner failure collapses to `verdict=UNKNOWN`, which is compared against nothing, so
  `fail=0` and the gate passes. Compounded by `run-scan.sh:8` claiming *"Exit code: 0 always
  (advisory)"* while `:10` sets `set -euo pipefail` — the comment is false.

## User-Brand Impact

**If this lands broken, the user experiences:** the `skill-security-scan PR gate` required check fails
on every pull request, blocking all merges to `main` until reverted.

**If this leaks, the user's data is exposed via:** no user data is in scope. The only theoretical
vector is a learning file quoting session output containing a credential — covered by `secret-scan.yml`
and the `lint-fixture-content` lefthook.

**Brand-survival threshold:** `none`

`threshold: none, reason: this PR replaces a redundant package-install step with a no-network version
assertion in three CI workflows and adds one documentation file — it touches no user data, no auth
surface and no persistent store, and the modified gate fails closed if jq is absent.`

## Observability

```yaml
liveness_signal:
  what: the `skill-security-scan PR gate` check-run conclusion, plus the new unconditional
        `Assert jq present` step which executes on every run regardless of diff content
  cadence: once per PR push and once per merge-queue entry
  alert_target: GitHub branch protection — a non-success conclusion blocks merge, visible on the PR,
        with no dashboard or shell access required
  configured_in: .github/workflows/skill-security-scan-{pr-trailer,corpus,postmerge}.yml and
        scripts/required-checks.txt:58
error_reporting:
  destination: GitHub Actions `::error::` annotations and the check-run conclusion
  fail_loud: partial — and the boundary is stated deliberately. A MISSING jq BINARY fails loudly at
        the new `jq --version` step. A jq PARSE failure inside the scanner does NOT: `:138` collapses
        it to `verdict=UNKNOWN`, which nothing tests. That pre-existing gap is tracked per §D4 and is
        not claimed as covered here.
failure_modes:
  - mode: jq absent from the runner image
    detection: the unconditional `Assert jq present` step exits non-zero on every run
    alert_route: required check concludes failure — merge blocked, surfaced on the PR
  - mode: unbounded apt stall during package installation (the mode this change removes)
    detection: previously reached the 6h GitHub job default with no step cap; the step no longer
        performs a network install, so the mode is eliminated rather than monitored
    alert_route: eliminated by construction
  - mode: scanner produces no verdict (pre-existing, §D4)
    detection: currently none — collapses to UNKNOWN and passes
    alert_route: tracked by the §D4 issue; explicitly NOT closed by this PR
logs:
  where: GitHub Actions run logs for the `skill-security-scan PR gate` job
  retention: 90 days (GitHub Actions default for this repository)
discoverability_test:
  command: bash -c 'test "$(grep -c apt-get .github/workflows/skill-security-scan-pr-trailer.yml || true)" -eq 0 && echo OK'
  expected_output: "OK"
```

## Files to Edit

- `.github/workflows/skill-security-scan-pr-trailer.yml` — replace the `Install jq` step with the
  `Assert jq present` step (§D3).
- `.github/workflows/skill-security-scan-corpus.yml` — same replacement (§D2).
- `.github/workflows/skill-security-scan-postmerge.yml` — same replacement (§D2).

## Files to Create

- `knowledge-base/project/learnings/2026-08-19-the-install-step-that-hung-was-installing-something-already-there.md`
- `knowledge-base/project/specs/feat-one-shot-t5-ship-learning-and-jq-step/decision-challenges.md`

## Open Code-Review Overlap

Queried 64 open `code-review` issues against the planned file set. No match on any of the three
workflow paths. **#3593** (*extract post-synthetic-checks child composite*) matches `skill-security-scan`
broadly — **acknowledge**: it concerns the synthetic-checks composite, not these steps; remains open.
Six issues match `knowledge-base/project/learnings` in prose; only **#3321** (CODEOWNERS coverage for
the subtree) is adjacent — **acknowledge**, adding one file neither advances nor conflicts with it.
All remain open.

## Implementation Phases

### Phase 0 — Preconditions (re-derive; inherit nothing)

1. `git fetch origin main` first — a stale fetch silently moves the three-dot merge base used by
   AC2/AC4/AC9.
2. Confirm `45ea9f7e9` still carries both learning files:
   `git show --name-only --format='' 45ea9f7e9 | grep -c 'project/learnings/'` → `2`.
3. Confirm 7572, 7574, 7613 are still `OPEN`. **If any has closed:** do *not* halt the run — the
   closure changes only the framing of §D1's context paragraph, not either deliverable. Record the
   new state in the PR body and continue. (A bare "stop" has no resume path in a headless pipeline.)
4. Re-anchor each target by **content**, not line number:
   `grep -n 'apt-get install -y -qq jq' .github/workflows/skill-security-scan-*.yml` → 3 hits.
5. Re-measure the preinstalled-jq evidence, **excluding `gh api --jq` sites** (gh embeds gojq and
   proves nothing about the `jq` binary). Record the figure derived at write time.

### Phase 1 — Deliverable B: replace the step at three sites

1. Replace the two-line `Install jq` step with the `Assert jq present` step (§D3) in each of the
   three workflows.
2. **Immediately grep to confirm each edit landed** — `.github/workflows/*.yml` edits have been
   silently rejected by a PreToolUse hook before, returning reminder text without applying.
3. Run `actionlint` on all three (workflows, not composite actions — the composite false-positive
   trap does not apply). Confirm `actionlint` is on PATH first; a missing binary must not read as a pass.
4. Confirm the six `jq` call sites in pr-trailer and both `set -euo pipefail` anchors in the
   jq-consuming steps are untouched.

### Phase 2 — Deliverable A: the learning file

1. Write the pinned-slug file (§D1). Subject: the CI package-install-hang class only.
2. Cross-reference — do not restate — the two existing T5 learning files, ADR-188, and the archived
   `tasks.md` §5.4.
3. Carry no closing keyword for 7572 / 7574 / 7613, **including in commit messages** (§AC9).
4. Append the §D1 and §D2/§D3 challenges to `decision-challenges.md`.

### Phase 3 — Verification and tracking

Run the Acceptance Criteria. File the §D4 issues.

## Acceptance Criteria

All pre-merge. **`grep -c` exits 1 when the count is 0**, so every zero-expecting criterion below is
written as `test "$(… | grep -c … || true)" -eq 0` — a bare `grep -c … == 0` fails under `set -e` or
any harness reading exit status.

### Deliverable B

- **AC1** — no install remains at any of the three sites:
  `test "$(grep -rc 'apt-get' .github/workflows/skill-security-scan-{pr-trailer,corpus,postmerge}.yml | grep -v ':0$' | wc -l)" -eq 0`.
- **AC2** — the change is an exact **2-for-2 swap** in each workflow and touches nothing else, so the
  six `jq` call sites survive byte-identical:
  `git diff --numstat origin/main...HEAD -- .github/workflows/skill-security-scan-pr-trailer.yml`
  → `2	2	<path>` (two added, two removed). Cheap regression net alongside it:
  `test "$(grep -c 'jq' .github/workflows/skill-security-scan-pr-trailer.yml)" -eq 8` — six call
  sites plus the assertion step's `name:` and `run:` lines.

  > **Both numbers were verified by simulating the edit, not asserted.** An added-line proxy
  > (`grep -c '^+'` → 0) was rejected twice over: it returns `1` on any pure deletion because the
  > unified-diff `+++ b/<path>` header matches `^+`, and *any* deletion-only change satisfies "no
  > added lines" — including deleting a `jq` call site. A first draft of this AC expected `7` and
  > would have failed on a correct implementation.
- **AC3** — `actionlint` introduces **no new finding** on the three workflows: its finding set at
  HEAD is byte-identical to the same command's finding set against `git show origin/main:<path>`,
  and `command -v actionlint` succeeded first.

  > **Amended at /work, 2026-08-19 — the original AC was mechanically unsatisfiable.** It read
  > *"`actionlint` exits `0` on all three workflows."* Measured, `origin/main` **already** exits 1
  > with 11 pre-existing shellcheck findings (SC2221/SC2222/SC2005/SC2016) in the scan steps at
  > `pr-trailer:113` and `postmerge:35` — code this change does not touch. No reachable
  > implementation of this PR could have satisfied the original wording, so passing it would have
  > required either fixing unrelated pre-existing warnings (silent scope creep, and AC4 forbids it)
  > or quietly running a looser command and reporting the result as the AC. Re-keyed onto the
  > property the AC was actually protecting — *this change adds no lint debt*. Verified: 11
  > findings at base, 11 at HEAD, `diff` empty, and none cite the assertion step. The replacement
  > is 2 lines for 2 lines, so no line numbers shift and the comparison is exact rather than
  > normalized. The 11 pre-existing findings are recorded in §D4's tracking issue, not fixed here.
- **AC4** — the touched-workflow set is exactly the three intended files:
  `git diff --name-only origin/main...HEAD -- .github/workflows/` returns exactly those three. *This
  is the anti-widening gate; changing scope means editing this AC, never drifting past it.*
- **AC5** — **fail-closed anchors intact.** Both jq-consuming steps (`Validate override artifacts`,
  `Run scanner against each added SKILL/agent`) still open with `set -euo pipefail`. Assert the
  anchors, not a bare count (`cq-assert-anchor-not-bare-token`); for reference the file carries three
  occurrences in total, the third being the unconditional diff step which uses no `jq`.
  *(The first draft asserted `2` and would have failed on a correct implementation.)*
- **AC6** — **the real runtime proof.** The `skill-security-scan PR gate` run on this PR's head shows
  the `Assert jq present` step with conclusion `success` and `jq --version` output in the log. This is
  genuine end-to-end evidence **because the new step is unconditional** — unlike the pre-existing
  jq steps, which are `if:`-guarded on `no_new_skills == 'false'` and do not execute on this PR.

  > **Why this AC exists.** The first draft asserted only that the check concluded `success`. Three
  > independent reviewers found that vacuous: with every `jq` call `if:`-guarded and this PR adding no
  > SKILL/agent files, a green check was compatible with `jq` being wholly absent. §D3's unconditional
  > step is what makes AC6 pin anything.

  > **Scope corrected at review — AC6 covers ONE of the three edited workflows.** "Unconditional" is a
  > property of the STEP; the WORKFLOW still has triggers. Resolved against this PR's 8-file diff:
  > `pr-trailer` runs (`pull_request`, no `paths:`); `corpus` does **not** (its `pull_request` arm
  > carries a 6-pattern `paths:` filter matching none of the changed files); `postmerge` does **not**
  > (no PR trigger — `push: branches: [main]` only). So this PR's green is direct evidence for
  > `pr-trailer` alone, and the other two inherit it only through the separate premise that all three
  > `runs-on: ubuntu-latest` jobs draw the same runner image — sound, but an inference the assertion
  > does not itself make. AC7 closes `postmerge` on the post-merge push; `corpus` is first exercised
  > by its own `push:main` arm. Found by the structural-enumeration seat.

- **AC7** — post-merge, the `push:main`-triggered `skill-security-scan-postmerge.yml` run shows its
  `Assert jq present` step succeeding. `wg-after-merging-a-pr-that-adds-or-modifies` is **honoured,
  not waived**; note `gh workflow run` is inoperable on pr-trailer (no `workflow_dispatch`), so the
  merge-triggered postmerge run is the verification vehicle.

### Deliverable A

- **AC8** — exactly one file is added under `knowledge-base/project/learnings/`, at top level, with
  the pinned slug from §D1, and it cross-references the four existing artifacts (the two T5 learning
  files by filename, `ADR-188`, and the archived `tasks.md`).

### Whole-PR

- **AC9** — **no auto-close, checked over title + body + commit messages.** Delegate to the canonical
  scanner rather than restating a weaker regex:
  `bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh <body-file>` emits no line referencing
  7572/7574/7613, and the same scan over `git log origin/main..HEAD --format=%B` is clean.
  **Commit messages are load-bearing:** this repo squash-merges, and the squash body is built from
  branch commit messages, so a keyword there auto-closes even with a clean PR body. GitHub's parser
  is also negation-blind — *"does not `clo`​`se` #7572"* (adjacency broken here on purpose) still closes it.
- **AC10** — the PR body records the seven-site inventory, the §D2/§D3 deviations, and the §D4
  tracking issues, so no finding is lost at archive time.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **A green check is mistaken for runtime proof.** All pre-existing jq steps are `if:`-guarded and never execute on this PR. | **Realised** — this was a live defect in the first draft, found by three reviewers | §D3's unconditional `jq --version` step; AC6 asserts that step specifically. |
| The change breaks a required check, blocking all merges. | Low | AC3 (actionlint) + AC6 (live run). Revert is a 2-line restore per file (the step is two lines). |
| `ship`'s compound auto-invoke writes a **second** learning file, breaking AC8. | Medium | §D1 pins the slug so ship Phase 2's glob arm resolves; AC8 is evaluated after ship Phase 2, not before. |
| A closing keyword reaches a commit message and auto-closes a context issue. | Medium | AC9 scans commit messages via the canonical scanner, not just the diff. |
| The workflow edit is silently rejected by a PreToolUse hook. | Medium (has happened) | Phase 1 step 2 — post-edit grep; AC1/AC2 are the recorded evidence. |
| The learning file duplicates existing material. | Medium | §D1 scopes it to the uncovered class and forbids bundling; AC8 requires cross-references. |
| Pre-existing swallows at `:74` / `:138` leave the gate weaker than "fail loud" suggests. | High (pre-existing) | Not claimed as covered — Observability `fail_loud` states the boundary; §D4 files them. |

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| Write the T5 restatement exactly as briefed. | A third copy of material already in two learning files + ADR-188 + archived `tasks.md`; reproduces the drift hazard those files warn about. Retained as §D1's fallback. |
| Plain deletion with no assertion (the brief's literal ask). | Leaves the premise unverified on this PR and most future PRs; relocates the failure to a future contributor's skill-adding PR. §D3. |
| Add `timeout-minutes` + retry to the jq step. | Retries an install that is unnecessary on every run. The `Install psql` retry is correct only because `postgresql-client` is genuinely absent from the image. |
| Hold the narrow one-file scope. | Preserves a copy-source for regression; the verification asymmetry that justified it dissolved with the AC6 finding. §D2. |
| Fix the `:74` / `:138` swallows inline. | Genuine P1s, but pre-existing and unrelated to the install step; each needs its own cycle and test. §D4 files them. |
| Amend the two merged T5 learning files. | They are point-in-time records; carrying a new session's findings into them blurs provenance. |

## Non-Goals

- Closing, editing or re-labelling issues 7572, 7574 or 7613.
- Changing the four **guarded** jq sites (#4–#7).
- Renaming the `skill-security-scan PR gate` check or touching the required-check ruleset.
- Fixing the pre-existing `:74` / `:138` swallows (tracked, §D4).
- Modifying the two existing T5 learning files, ADR-188, or archived spec artifacts.
- Adding a learnings-frontmatter validator (none exists; inventing one is out of scope).

## Gate Results

- **2.7 GDPR** — skipped: no regulated-data surface; none of triggers (a)–(d) fire.
- **2.8 IaC** — skipped: no new infrastructure; the plan prescribes no remote-shell, dashboard, or
  secret-write action of any kind.
- **2.9 Observability** — **declared in full above.** Plan Phase 2.9 would permit a deletes-only skip,
  but deepen-plan Phase 4.7's trigger is mechanically stricter (a `.yml` path is not in its pure-docs
  skip list), and the surface being changed is itself a monitoring surface. *(An earlier draft claimed
  both "skipped" and "declared in full"; that contradiction is resolved in favour of declaring.)*
- **2.9.1 Soak follow-through** — not triggered: no time-gated close criterion.
- **2.10 ADR/C4** — skipped; detection did not fire. No ownership/tenancy move, no new substrate, no
  resolver or trust-boundary change, no ADR reversed. ADR-188 is **cited, not amended**.
- **2.11 Encryption Posture** — skipped: no persistent store and no new cross-component connection.
- **2.12 Guard Contract** — skipped: the deliverable adds no guard, lint or anti-vacuity control.
  The `jq --version` step is a dependency assertion, not a guard over an assembly.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (4-agent panel: security-sentinel, architecture-strategist, spec-flow-analyzer,
code-simplicity-reviewer)

**Assessment:** CI hygiene plus a documentation artifact, against a branch-protection-required check,
so a regression is merge-blocking repo-wide. The panel's decisive finding was that the first draft's
verification was **vacuous** — every `jq` call site is `if:`-guarded, so a green check proved nothing
about the premise the change rests on. Two reviewers independently converged on the same remedy (an
unconditional `jq --version` step), which is now §D3 and makes AC6 real. The panel also drove the
scope widening (§D2), corrected the site inventory from four to seven, corrected two mechanically
broken ACs, and surfaced two pre-existing P1 swallows now tracked under §D4. No cross-domain
implications: no user-facing surface, no data handling, no legal, financial, sales, marketing or
support impact.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire — Files to Edit/Create contain no
path matching the UI-surface term list or glob superset. Product assessed **NONE**.
