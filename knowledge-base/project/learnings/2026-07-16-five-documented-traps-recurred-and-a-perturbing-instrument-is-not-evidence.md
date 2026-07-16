---
date: 2026-07-16
category: test-failures
module: apps/web-platform/infra/supabase-advisor
issue: 6572
pr: 6573
tags: [pipefail, sigpipe, mutation-testing, vacuous-gates, false-precision, measurement]
---

# Five documented traps recurred in one PR — and a perturbing instrument is not evidence

## Problem

`scan-workflow.test.sh` (the nightly Supabase advisor RLS shape guard) sets `set -uo pipefail`
and had 7 checks shaped `<producer> | grep -q P`. `grep -q` exits on first match; the
producer's next `write()` takes SIGPIPE (141); `pipefail` promotes 141 to the pipeline status
and **inverts the `if`**. At the 3 match⇒fail sites that inversion is a **silent pass** — on
the assertion the file's own comment calls "THE headline assertion".

The fix was 7 mechanical line changes. Everything expensive was about **evidence**.

## The generalisable lessons

### 1. A perturbing instrument does not measure the unperturbed system

I ran `strace` on the real 8 KB producer, saw `write(1,…) = -1 EPIPE` → `killed by SIGPIPE`,
and reported it as proof the bug fires at current size. It is not. Unperturbed, the same
pipeline is **0/200**, `PIPESTATUS=0 0`. **strace caused the SIGPIPE** by slowing the producer
so the reader won the race. A 20 KB run under the same strace showed *no* SIGPIPE — same
instrument, opposite result, because it is a race, not a threshold.

What strace legitimately proves: **the window is real** (a mere perturbation loses it). What
it cannot prove: what happens without it. When your instrument changes the timing of the thing
you are timing, it is a *window detector*, not a *frequency meter*. Say which one you used.

### 2. Convergence is not proof when the agents share a wrong model

Three independent reviewers concluded the defect was "latent, not live", all reasoning that
SIGPIPE requires filling the 64 KB pipe buffer. It does not — it requires a **second
`write()`**. The refutation was already in hand: #6572 carries a CI log (`grep: write error:
Broken pipe`) at an 8 KB producer. A fourth agent tried to falsify the two-write model, failed,
strace'd it, and reversed itself.

Agreement between reviewers raises confidence only if their errors are independent. When they
inherit the same mental model, three agents are one agent. Ask *what model are they all using*
before counting votes — and prefer one irrefutable artifact (a production log) over any number
of concurring inferences.

### 3. …and a right verdict can rest on a wrong reason

The CONCUR gate DISSENTed on my sibling-sweep filing using that same wrong 64 KB model. The
dissent was still **correct**, on grounds I verified independently:

- **A syntax count is not a vulnerability count.** 194 of 233 matching sites feed `printf`/`echo`
  of a bounded shell var — one write, no second write, no window. I had called all ~230 "silent
  passes". False.
- **The close trigger could never fire.** The enumeration matched 5 *comment* lines — including
  the PR's own documentation of the bug. Reaching "0 matches" meant deleting the guardrail's
  own comments.
- **The criterion was defeated by its own text.** `cross-cutting-refactor` names
  `apps/web-platform/` as a top-level directory; every candidate lived under it.

Evaluate the verdict and the reasoning separately. I rejected the model and accepted the verdict.

### 4. A mutation that does not mutate reports the BASELINE — and it reads exactly like a pass

My attestation harness had a `mutate()` helper that appended `"\n"` to the search string, so a
**mid-line** anchor matched nothing, `str.replace` silently no-oped, and it returned **success**
with an unmodified copy. The caller then measured the pristine guard and reported it broken.

This happened *inside the arm written to detect that exact trap*. The rule "assert the mutation
landed" is not enough — the helper must be **structurally incapable** of a silent no-op: exit
non-zero when the anchor is absent AND when output equals input. Test the tester.

### 5. Five traps this repo already documents recurred anyway

| Trap | Already documented in |
|---|---|
| assert must-not-contain X, then document X → self-match | `cq-assert-anchor-not-bare-token`, and this file's own header |
| background `cmd; echo "EXIT=$?"` → notification reports the *echo's* exit | `work/SKILL.md` |
| `comm` without `LC_ALL=C` → input read as unsorted → set-diff undefined, runs blind | `review/SKILL.md` |
| a mutation that does not land reports the baseline | `review/SKILL.md` |
| editing the bare-repo checkout while a worktree is active | `compound/SKILL.md`, `hr-when-in-a-worktree-never-read-from-bare` |

I had all five rules in context and walked into all five. Four were caught by **running something**; the fifth (bare-repo write) was caught by a
**hook** — the only one prose-plus-diligence did not have to catch, and the cheapest of the five. This is the repo's own "hooks beat documentation"
thesis, restated: for a trap whose failure mode is *silent and green*, prose cannot help — the
reader cannot tell they are in it. The disposition for a recurring documented class is a
mechanical gate, not another paragraph.

The self-match one is the sharpest: I hit it in the **first draft of the guard against it**.
The fix that generalises is not "remember" — it is to strip string literals before matching, so
the collision is structurally impossible and messages can name what they forbid.

### 6. Honest uncertainty beats a clean model

Issue #6572 said: *"Not fully explained: the producer's output is only ~8 KB … Runner
scheduling/buffering appears to decide it."* That was the most accurate artifact in the whole
chain. The plan replaced it with "arms at one stdio block (4096 B)" — tidier, falsifiable,
false. I then propagated it into a code comment.

A plan that converts the issue's *"we don't know why"* into a mechanism has not learned
anything; it has laundered uncertainty into confidence. When the source says "not fully
explained", that clause is a finding — carry it forward.

## Solution

- Capture each producer once; match via here-string (`grep -q P <<<"$var"`). No pipe, no
  producer, no SIGPIPE. In-repo idiom (`deploy-status-fanout-verify.test.sh:244`).
- **The issue's own preferred fix does not work**: `printf '%s' "$c" | grep -q` is still a
  producer feeding a pipe the reader closes early — 100/100 false-negatives at 1.3 MB. Adopted
  its capture-once half; replaced its match half. Pinned by attestation arm D2 so a future
  "simplification" back to it cannot pass silently.
- Committed `scan-workflow-mutation.test.sh` (registered in `infra-validation.yml`; nothing
  auto-discovers these). It pins what the guard cannot pin about itself: the differential, both
  halves of the residual guard's non-vacuity, that each normalisation is load-bearing, and both
  mutation polarities.

## Key Insight

**A guard's value claim is worth exactly what re-runs it.** The repo already knew this —
`inngest-rls-mutation.test.sh` sits 8 lines away in the same workflow and its header says it
exists *because a session crash destroyed an ad-hoc, uncommitted matrix*. This PR regressed to
ad-hoc anyway and claimed "mutation-proven" in a commit message with nothing behind it. Review
caught it; the harness now exists.

Corollary for comments: in a file whose thesis is *every warning here is true*, a false hazard
claim is the most expensive line you can add. Three shipped in the first commit — a fail-open
that measurement showed does not exist, a count of "seven" that was four, and an arming
threshold that was a race. Each read as diligence.

## Session Errors

1. **Plan-phase probe timed out mid-mutation, leaving an injected `.lints[]?` in tracked
   `scripts/supabase-advisor-scan.sh`.** Recovery: `git checkout --`. **Prevention:** the
   `SCRIPT_OVERRIDE` seam + `mktemp -d` sandbox — no mutation can reach tracked source, so an
   interrupted run leaves nothing behind. (Recurring → fixed inline.)
2. **Plan-phase measurement contaminated** — a 1/200 false-FAIL reading was a concurrent
   reviewer agent mutating the shared script, not a real signal. Re-measured 0/400.
   **Prevention:** same seam; mutate sandbox copies, never the shared tree. (Recurring.)
3. **Throwaway sweep scripts emitted `[: integer expected`** (unquoted `grep -c` in a loop).
   Cosmetic, results unaffected. **Prevention:** none warranted. (One-off.)
4. **The residual self-check's own fail message named the forbidden construct**, so it matched
   itself and reported 8 sites instead of 7 — it could never have reached 0. **Prevention:**
   strip double-quoted strings before matching (N1a/N1b now pin both halves). (Recurring →
   fixed inline.)
5. **A Monitor `until` condition matched a mid-run line**, reporting "test-all finished" while
   the suite was still executing. **Prevention:** gate the exit condition on the terminal
   marker only, never a substring that can appear mid-stream. (Recurring → caught by verifying.)
6. **A background task's "exit code 0" was the trailing `echo`'s exit**, not the suite's.
   **Prevention:** already documented in `work/SKILL.md`; always read the real `EXIT=` marker
   and the runner's own summary. (Recurring → caught.)
7. **I broke `REPO_ROOT` depth** (`../../..` for `../../../..`) while adding `DIR_SELF`.
   **Prevention:** the guard FATALs loudly on a bad root; caught on the next run. (One-off.)
8. **Attestation v1 placed the guard copy in a bare sandbox**, so `REPO_ROOT` resolved to an
   empty dir, the guard FATALed on missing artifacts, and every R/N arm measured the FATAL
   rather than the guard. **Prevention:** symlink-mirror the repo levels + assert the mirror is
   complete before trusting any result. (Recurring → fixed inline.)
9. **`mutate()` appended `\n` to the anchor**, so mid-line anchors silently no-oped and it
   returned success with an unmodified file — the caller then reported a working guard broken.
   **Prevention:** the helper now exits non-zero on absent-anchor AND on output==input. Test
   the tester. (Recurring → fixed inline.)
10. **I cited a strace as evidence the bug fires at current size**, but strace perturbs the
    timing it measures. **Prevention:** name the instrument's effect; a perturbing instrument
    detects a window, it does not measure a frequency. (Recurring → corrected.)
11. **`comm` without `LC_ALL=C`** printed "input is not in sorted order" — the set-diff was
    undefined and AC4 would have run blind. **Prevention:** already documented in
    `review/SKILL.md`; pin `LC_ALL=C` on every `sort`+`comm` set-diff. (Recurring → fixed.)
12. **I propagated the plan's "arms at 4096 B" false precision into a code comment.**
    **Prevention:** when the source issue says "not fully explained", that is a finding to
    carry, not a gap to fill. (Recurring → fixed inline.)
13. **My sibling tracking issue had an unsatisfiable trigger and a syntax-count premise.**
    **Prevention:** before filing an enumeration-triggered issue, run the enumeration and check
    it can reach its own close condition (mine matched its own comments). (Recurring → not
    filed; CONCUR gate caught it.)
14. **The FATAL comment claimed a fail-open that measurement disproved** (inherited from the
    plan). **Prevention:** for any comment asserting a hazard, ask "if this were false, what
    would fail?" — then go make it fail. (Recurring → fixed inline.)

15. **I tried to route this learning into `plugins/soleur/skills/review/SKILL.md` at the BARE
    REPO path while a worktree was active** — the `guardrails` PreToolUse hook denied the write
    and named the correct worktree path. **Prevention:** already documented in
    `compound/SKILL.md` ("always use worktree-absolute paths … verify with `git status --short`
    that the file is listed as modified"). It is the fifth documented trap this session, and the
    only one caught *mechanically* rather than by me running something — which is the whole
    argument of §5. (Recurring → hook-enforced, no action needed.)

## Related

- `knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md`
  — the lesson this PR re-learned the hard way.
- `knowledge-base/project/learnings/2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md`
  — same "documented class recurred" shape, one day earlier.
- `apps/web-platform/infra/inngest-rls/inngest-rls-mutation.test.sh` — the committed-attestation
  precedent this PR should have reached for first.
