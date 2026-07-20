---
date: 2026-07-20
category: logic-errors
module: apps/web-platform/infra, .github/workflows, tests/scripts
issues: [6718, 6712, 6730, 6575]
pr: 6725
tags: [guards, mutation-testing, enumeration, ci, terraform, vacuous-tests]
---

# Learning: adding a second copy of a guarded literal disarms the guard on the first

## Problem

PR #6725 wired an existing `host_creates > 0` HALT into a second CI job so a dispatch
could not transitively birth web-1 (the sole web host) against a mutable `:latest` tag.
Plan-reviewed by seven agents, deepened, TDD'd, 193/193 suites green, 68/68 CI checks
green. Multi-agent review then found **three P1 classes, all introduced by the PR**.

## The three, and what each generalises to

### 1. Adding a copy of a replicated safety literal disarmed the guards on the original

The repo guards the `apply` job's HALT with **whole-file** greps
(`grep -qF "$PATTERN" "$WF"`, `grep -c … -ge 1`). Adding the sibling job's copy took the
literal from **1 → 2 occurrences**. Deleting the *apply* job's numeric-validation clause
then left every guard satisfied **by the new copy**: the apply job ships fail-**open**
(`[[ "null" -gt 0 ]]` passes) with the repo's coherence checks reporting intact.

The guard was not buggy. The *addition* broke it. This is distinct from the documented
`head -1` first-member class — there the guard sampled one member; here a correct
whole-file guard silently became a first-member guard because the population grew.

> **Rule.** When a diff increases the occurrence count of a literal that some guard
> asserts the presence of, that guard degrades from "the thing exists" to "*a* thing
> exists". Count occurrences on `main` vs `HEAD`
> (`git show origin/main:<f> | grep -cF '<lit>'` vs `grep -cF '<lit>' <f>`); if it grew,
> every presence-guard over that literal needs re-scoping to the specific member.

The sharpest part: this PR's own thesis is *"a replicated safety literal needs an
all-members guard."* It proved that for its new copy (a job-scoped assert) and left the
precedent it copied from on whole-file greps its addition had just satisfied.

### 2. "No path does X" was asserted, not enumerated — and was false within a day

"No automated path can birth a web host" shipped into a workflow remediation string,
`server.tf`, **two ADR amendments**, and a **filed GitHub issue's premise**. Review found
`apply-deploy-pipeline-fix.yml`: fires on `push:main` *and* `workflow_dispatch`, runs
`terraform apply -auto-approve` over four `terraform_data` targets that each reference
`hcloud_server.web["web-1"]`, with no counter, no HALT, no `-var image_name` — the
identical composition the PR existed to close.

Nothing caught it because nothing *could*: five artifacts restated one claim, and N
artifacts agreeing is **one** artifact when they share a premise.

> **Rule.** A universal negative is a claim about a **set**. Produce it by walking the
> set, and put the **walk** in the artifact, not the conclusion. "Every route HALTs"
> is unfalsifiable prose; a five-row table naming each route and its gate is checkable —
> and the next reader can spot the missing row.

Fixed by *guarding the second workflow* rather than weakening the claim, so the sentence
became true instead of softer.

### 3. The fix for "the test pins text" pinned position — the same error one level up

`T51a-d` asserted the guard's **content** via `grep`. Recognising that, a `T51e` was added
to assert **line ordering**. Review demonstrated **8 surviving mutants** against all five:
deleting `exit 1` (guard prints three errors and falls through to `terraform apply`);
appending `&& [[ "${SKIP_HOST_GUARD:-yes}" != "yes" ]]` (`grep -qF` is a *substring*
match); parsing `.reboot_updates` into the `host_creates` variable; relocating the whole
block *below* `terraform apply` (offsets are block-relative, so it still reads ordered).

Content and order are both **spelling**. Neither is behaviour.

> **Rule.** For a guard whose correctness is a *behaviour* (it terminates, it reads the
> right key, it fails closed), the test must **execute** it. Extract the step's own bytes,
> stub only what needs live state, and assert the exit code. Litmus: *name a mutation that
> satisfies this assertion while violating the property.* If you can, the assertion is
> spelling.

## Solution

`T52` extracts the workflow's own guard bytes and **runs** them against real captured
tfplan fixtures with the **real** jq filter — only `terraform` is stubbed, being the one
thing needing live cloud state. So a workflow mutation changes what executes. `T53` pins
the containing step is live and precedes the apply. `T54` re-scopes the sibling's guard
per-job. `T55` re-checks a plan-time precondition on every run. `T56` covers the newly
guarded second workflow.

**10 mutations, 10 caught** — each asserted to have **landed** against a pristine backup
before its result was trusted.

## Key Insight — a documented class recurred one day later

`2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`
landed the day before. This session then ran a **2-mutation** battery, saw both go red,
and concluded the tests were sound. Review found 8 more.

A self-run battery is evidence about **the mutations its author imagined**, and its green
is indistinguishable from the green of a fully-covered SUT. That is why the disposition
for a *recurring documented class* is a **mechanical gate, not another learning** — and
why the adversarial prompt that worked was *"find the vacuity the author's battery
missed; do NOT re-run its mutations."*

The generalisation across all three P1s is one sentence: **each was a check certifying a
property adjacent to the one that mattered** — presence instead of per-member presence,
a conclusion instead of an enumeration, spelling instead of behaviour.

## Prevention

- Occurrence-count delta on any safety literal a guard asserts (see rule 1).
- Universal negatives ship as tables, not sentences.
- Guard tests execute; greps are a supplement, never the proof.
- Never trust an author-run mutation battery — including your own — as coverage evidence.

## Session Errors

- **Git trailer did not register.** `Rename-Allowed-By` was placed above a blank line and
  mixed with colon-less `Refs #NNNN` lines. Git parses trailers **only from the last
  paragraph**, and only `Key: value` lines. — *Recovery:* moved it into a pure trailer
  block with `Co-Authored-By`. — *Prevention:* run the consuming guard locally before
  pushing; a trailer's presence in the message is not evidence the parser sees it.
- **A new test aborted the suite instead of failing it.** Four `ln_*=$(grep … | cut …)`
  assignments lacked `|| true`; under `set -euo pipefail` a non-matching grep exits 1 and
  kills the run — **no failure line, no summary, exit 0** — making the anchor-absent
  branch unreachable dead code. — *Recovery:* `|| true` on each, post-mortem comment. —
  *Prevention:* found only by mutation; assume any new `$(grep …)` in a `set -e` harness
  is an abort until proven otherwise.
- **Incomplete sweep, twice.** The first jq comment fix left a second stale claim; review
  found a **third**, and my "corrected" one said `BOTH` where there are three readers. —
  *Prevention:* enumerate consumers with a grep and cite the count; the enumeration now
  lives in exactly one place in that file.
- **Three false claims about sibling jobs** (`apply` pins `image_name` — it does not;
  warm_standby evaluates "outside the `destroy_count` sum" — it has no such sum;
  warm-standby is "DEGRADED" — it is unrunnable). — *Prevention:* every comparative claim
  about a sibling needs a grep of the sibling, not recall.
- **Stale-green risk.** The first full-suite run predated the last test added, recording
  48 where the shipping tree has 49. — *Recovery:* re-ran against the final tree. —
  *Prevention:* a suite result is evidence only about the SHA it ran on.
- **A review prompt carried a false premise** ("the new HALT dropped the sibling's plan
  diagnostic"). The agent falsified it. — *Prevention:* healthy; state premises as
  questions so an agent can refute them.
- **Threshold grep false-negative.** Matching `Brand-survival threshold: single-user
  incident` returned 0 because the artifact bolds the label. Nearly skipped the reviewer
  that found the highest-value latent finding. — *Prevention:* match on the distinctive
  value, not the label+value pair.
- One-offs: `gh issue create` blocked for a missing `--milestone` (hook working as
  intended); label `infra` does not exist in this repo; `ugrep` regex-complexity error on
  an over-built verification pattern.
