---
date: 2026-07-17
category: test-failures
module: apps/web-platform/infra/ci-deploy.sh
tags: [vacuous-test, positive-only-oracle, mutation-testing, review-findings, telemetry, credential-oracle]
issues: [6565, 6497]
pr: 6577
---

# Every hole was a claim quantified over a set the test only ever sampled once

## Problem

PR #6577 added six errno probes to `ci-deploy.sh` › `_login_kw`, an `errno_chars` field to
`_login_hatch`, and tests for both. The suite was **168/168 green**. A four-mutation battery, run by
the author, went RED on every mutation it tried.

Three independent reviewers then found **five real holes**, and converged — without coordinating — on
one shape:

> **Every hole was a claim quantified over a set the test only ever sampled once.**

That is the third consecutive appearance of this shape in this same file
([[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] is the second; the #6497 defect is the
first). **The recurrence is the finding.**

## The five holes (all measured, none reasoned)

| # | The claim | The set | What it sampled | The falsifier |
|---|---|---|---|---|
| 1 | "each arm fires" | 6 arms × 6 fixtures | each arm on **its own** fixture | Loosen the enomem arm to `*'.docker/config.json'*` — the fixtures **share** that prefix, so it fires on all six. **Full suite byte-identical to control.** Not one assertion moved. |
| 2 | "`errno_chars` bounds all ~130 errnos" | ~130 errnos | **one** (22 chars) | `_errseg="${_e:$(( ${#_e} > 22 ? ${#_e}-22 : 0 ))}"` — hardcodes 22, satisfies every assertion, reduces the field to a constant. |
| 3 | "every arm literal is outside the credential alphabet" (AC4) | every arm | only **single-quoted `case`** arms | A double-quoted / unquoted / `[[ ]]` arm evades the extraction. A live oracle (`token contains 'abc123' → kw='unq,'`) passed GREEN — one bit of token content to Better Stack unscrubbed. |
| 4 | "pull tokens are `[A-Za-z0-9]`" | both credentials | **zot only** | Both GHCR PAT formats carry `_`. `*'_pat_1'*` read as "safe" while matching inside a PAT (~5.9 bits on its first char). |
| 5 | "invariant (5) closes the capitalized-copy class" | every literal | the **token** vocabulary | `Cannot allocate memory` — the C `strerror` rendering issue 6565's own analysis quotes — passes the alphabet check (spaces) and never reaches the token check. The arm most likely to be copied from the issue text was unguarded. |

## Key insight

A **positive-only oracle is true of the correct implementation AND of the broken one.** Asserting "X
happened" over a set you sampled once cannot distinguish "X happens correctly" from "X happens always".
Every hole above is that sentence.

The tell, and it is cheap: **can you name an implementation a reasonable engineer might write next that
satisfies the assertion while violating the property?** If yes, the assertion is decorative. In hole 3
the test *already held its own disproof and was not looking*: the vocabulary extraction counted 17 while
the literal extraction counted 16 — the derivation saw the arm the guard was blind to. The fix was to
compare two numbers the test had already computed.

## Solution

Each fix pairs the positive assertion with the negative one over the **whole** set:

- **Negative oracle** — each fixture must fire **only** its own token (kills 1).
- **Length fidelity across all six measured errnos** + a value assertion on the canary fixture, which
  doubles as the positive control an absence-only assertion was missing (kills 2).
- **`lit_n >= vocab_n` cross-check** — every emitting arm must yield a readable match-form; a shape the
  guard cannot read shows up as a token with no literal (kills 3).
- **`[A-Za-z0-9_]`**, the union, while either credential can reach the function (kills 4).
- **Lowercase invariant scoped to the INFERRED block**, derived so it spans a seventh arm (kills 5).
  The file-wide form the plan asserted is unshippable — main's own arms are legitimately capitalized.
- **Arm/fixture cardinality parity** — a count, not a derivation, so the hand-written family gets teeth
  against arm #17 without feeding a literal back into its own oracle.

All mutation-proven RED in a **sandbox copy** (`cp` to a temp dir), never the tracked file — a
concurrent in-place mutation is reported by every file-reading agent as a false "uncommitted drift P1".

## The second lesson: a review report is a claim ABOUT an artifact

I transcribed a review panel's findings into the plan as mandatory work **without checking them against
the file on disk**. The panel had run against a pre-`deepen-plan` revision; `deepen-plan` had already
fixed every finding and renumbered the ACs. My section ordered fixes for things already fixed and cited
AC numbers that no longer existed — **asserting from a report instead of measuring the artifact, in the
round whose entire thesis is "measure, don't infer."**

The repo already applies this rule to plan-quoted counts, tool-flag units and `session-state.md`
decisions. It had no entry for **review findings**, which go stale the instant a deepen/rebase/fix pass
touches the artifact between the review and its consumption.

A reviewer on this same PR independently hit the mirror image: its first `git diff` calls ran from a
drifted CWD and returned a **stale tree** (5 files, 727 lines) versus the true HEAD (7 files, 789
lines). It half-drafted two findings that were already fixed, then re-ran with explicit `git -C` and
discarded them. Same failure, opposite direction, same session.

## The third: documenting a negation-blind hazard is itself a high-risk act

GitHub's close-keyword parser is negation-blind and honors `#N`, `GH-N`, **and** the full issue URL, and
it reads the **squash commit body**. Four parties handled that hazard this round. **All four armed it
while documenting it**: the brief once; the planner twice (a literal close-keyword in a Sharp Edge, then
a `GH-NNNN` in the very note fixing the first); and me, writing a live `Clos<e>s <issue-URL>` **inside
AC10's own counter-example about that exact form**.

Four for four is not four careless authors. It is a property of the hazard: a negation-blind parser
plus a negation-heavy document. `wg-use-closes-n-in-pr-body-not-title-to` and `auto-close-scan.sh` cover
the *mechanism*; nothing covered the fact that **writing about it is when you arm it**. File contents
are not parsed, so none of these would have fired from the plan alone — the danger is plan prose being
quoted into a PR body at ship.

**Rule for any document that discusses this hazard: placeholders only (`Clos<e>s #NNNN`), even inside an
example of what not to write.**

## What a test cannot tell you — pull the live layer

Self-pulling Better Stack at `/work` (rather than assuming) produced three things no test could:

1. **Premise (A) still live** — a deploy at 09:04:20Z the same day failed on both arms. The round will
   report; the "no deploy runs" worry was moot.
2. **`stderr_chars=97` on the zot arm** (96 on 2026-07-15, 97 on ghcr). The uint32-temp-suffix
   explanation moved from **inference to observation**: a registry-specific cause cannot move the zot
   arm alone between observations while tracking ghcr; a 9-vs-10-digit suffix does exactly that.
3. **The host attribution is unverified.** Every failing row carries `host_name=soleur-inngest-prd`
   while `host=soleur-web-platform`. `vector.toml` states `host_name` is *the sole discriminator*, and
   `server.tf`'s per-host ternary maps `web-1 -> "soleur-web-platform"`. By that field's own contract
   these rows are not web-1's. The brief, the plan and the shipped comments all say "web-1".
   **Deliberately not resolved** — the probe settles it for free, because `kw`/`errno_chars` land in the
   same row as `host_name`, so the first report names its own host. Guessing before the instrument
   reports is the one thing this round exists to prevent.

## Prevention

**A gate, not another learning.** This class has now recurred three times in one file and four times
across the repo in two days. Prose has demonstrably failed it. The cheapest mechanical check, for any
test asserting a property over a derived set:

```bash
# Every emitting arm must yield a readable match-form. A shape the guard cannot
# read surfaces as a token with no literal behind it. Two integers the test
# already computes.
[[ "$LIT_N" -ge "$VOCAB_N" ]] || fail "guard is fail-open: $VOCAB_N emitters, $LIT_N readable"
```

Generalized: **when a test derives a set S from source and asserts a property over S, assert that S's
cardinality matches the producer's cardinality.** A member the extraction cannot see is silently exempt,
and that exemption is invisible to every green run.

## Session Errors

- **My brief named a file that does not exist** (`scripts/ci-deploy.sh`; real: `apps/web-platform/infra/ci-deploy.sh`). Recovery: the planner verified and corrected throughout. **Prevention:** covered by `hr-when-a-plan-specifies-relative-paths-e-g` — a plan-quoted path is a claim, and this one was caught by the existing rule working as designed.
- **I armed the close-keyword landmine** inside AC10's own counter-example. Recovery: scanned added lines only, replaced with placeholders. **Prevention:** see "documenting a negation-blind hazard" above — placeholders only, always, including in negative examples.
- **I transcribed a review report as work without checking disk.** Recovery: rewrote the section as a reconciliation table verified row-by-row against HEAD (an independent reviewer confirmed all 7 rows). **Prevention:** reconcile findings against the artifact before transcribing; a report is a claim about a file at a moment.
- **My first mutation test did not mutate** — the anchor omitted the trailing `# EINVAL (16)` comments, so nothing was inserted, and my land-check was also wrong. It reported a false pass. Recovery: re-ran with a substring anchor + `cmp -s` land-check. **Prevention:** already documented in `review/SKILL.md` ("a mutation that does not mutate reports a false 'the guard works'") — **and it recurred anyway**, which is itself evidence that prose does not hold this class.
- **`pkill -f 'ci-deploy.test.sh'` killed my own shell** (exit 144): the pattern matched the Bash tool's own wrapper, whose command string contains the filename. **Prevention:** match on `/proc/$p/cmdline` with an exact `bash <script>` prefix, never `pkill -f` on a string that appears in your own invocation.
- **I edited the test file while its suite was running.** Bash reads scripts incrementally, so that run's result was untrustworthy. Recovery: killed it, re-ran clean. **Prevention:** never edit a script with a live run against it; kill first.
- **My AC5 verification grep false-matched its own comment prose** (`exit 1` appears in the comment explaining the echoes sit after the last `exit 1`). Recovery: re-ran comment-blind on executable lines only. **Prevention:** `cq-assert-anchor-not-bare-token` applies to verification commands too, not just committed assertions — the check committed the defect it was checking for.
- **Two review agents reported a suite result from before my fixes**, and one reviewed a stale tree from a drifted CWD. **Prevention:** pin agents to the committed HEAD and require `git -C <worktree>`; treat any agent-reported count as needing a re-derive against the current SHA.

## Related

- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the direct predecessor; same file, same shape, one round earlier.
- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]] — the anchoring half; a documented class recurring is a signal for a gate.
- [[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]] — placement-vs-correctness, same week.
- [[2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code]] — why the mutation matrix belongs in a committed harness, not a comment.
