---
title: "Every guard I shipped pinned spelling, not the executed program"
date: 2026-09-19
category: test-failures
issue: 8392
pr: 8394
tags: [mutation-testing, vacuous-guards, model-swap, anthropic, ci-ratchets]
---

# Every guard I shipped pinned spelling, not the executed program

## Problem

`postAnthropicMessage` read `data.content[0].text`. `EXECUTION_MODEL` became
`claude-sonnet-5` on 2026-07-01 (#5849); Sonnet 5 runs adaptive thinking when
`thinking` is omitted, so position 0 holds a thinking block and the
structured-output text sits behind it. From 2026-07-06 (when the cron was enabled,
#6100) every `cron-compound-promote` run read `""`, mirrored
`Empty Anthropic response` to Sentry, and reported `no-qualifying-clusters` —
after paying for the answer. Measured on a live prd fire: 536,632 input /
12,306 output tokens billed and discarded.

Four readers carried the same shape. The fix is one expression each.

## Solution

Select the first block whose `type === "text"`, in all four:

```ts
const text = Array.isArray(data.content)
  ? (data.content.find((b) => b.type === "text")?.text ?? "")
  : "";
```

```bash
jq -r 'first(.content[]? | select(.type == "text") | .text | strings) // empty'
```

## Key Insight

**The fix was four lines and correct on the first pass. Every one of the six
merge-blocking findings was in the machinery I wrote to prove it.** A ten-seat
panel reduced to one structural cause: *each guard pinned SPELLING or TEXT rather
than the EXECUTED program or a construction-complete predicate.*

- The repo-wide **census** I added to the model-launch audit was the claimed
  mechanical guard. `--detect` is the only scheduled caller and `--fix` is the mode
  that PERFORMS the model swap; both return ~200 lines before it. The guard ran only
  when a human typed the skill — the exact cadence that missed the bug for ten weeks.
- **T8** extracted a jq program with `grep … | head -1` over file text. Reverting the
  live reader while leaving the canonical spelling in a comment above it passed 28/28.
  The naive revert was killed; the one that mattered was not.
- The **fixture set** had one text block per response, so `first` / `last` /
  join-all were indistinguishable; and no fixture held a non-thinking non-text block,
  so a `!== "thinking"` DENYLIST survived — which returns undefined on
  `tool_use` / `redacted_thinking`, reopening the very silent-empty class.

The remedy in each case is the same move: assert against what RUNS (the assignment,
comment-stripped; a lint registered in the merge gate; a fixture per member of the
set the guard quantifies over).

### A file-derived fallback is structurally blind to a repo-global ratchet

The full gate was REFUSED (`rc=4`, three sibling worktrees holding it). The
sanctioned fallback is to derive substitute suites from the diff. I did — consumer
suites by changed file, plus the new-vocabulary sweep — and all were green while
`lint-shell-capture-exit-live` sat RED on two lines I had just written. **A ratchet
counts a property across the whole tree and references no file, so no file-derived
query can ever return it.** This is not carelessness and does not improve with
effort; it recurs until the fallback recipe names the ratchets explicitly.

### Known-positive controls earn their cost on the guard you just wrote

My new lint reported clean over the whole repo. Its own known-positive fixture then
failed: `data.content.length - 1` has a dotted path, which my
`[A-Za-z_$][\w$]*\.length` alternation did not match. The live scan's clean verdict
had been vacuous for that spelling, and only a fixture that MUST fail found it.

### Three of the plan's post-merge assertions could never go red

The AC asserted the absence of `Anthropic returned empty content` *in Sentry*.
`reportSilentFallback` passes that string as `safeMessage` to pino;
Sentry gets `captureException(err)`, whose message is `Empty Anthropic response`.
It also prescribed a run-id join whose key the cost marker never emitted (it carried
a constant cron name), via a `sentry-issue.sh --search` flag that does not exist.
Each was seconds to falsify and none had been.

## Prevention

- When a PR's deliverable is a guard, **name the implementation that satisfies every
  assertion while violating the property**, and write the fixture that rejects it.
- On a REFUSED full gate, run the repo-global ratchets/lints **by name** — they are
  invisible to any file-derived substitute set.
- Give every new lint a known-positive fixture per forbidden spelling before trusting
  its clean verdict.
- For every claim a diff's PROSE adds, name the command that falsifies it and run it.
  Three comment claims in this PR were wrong, including my own about bash expansion.
- A guard's verdict must NAME ITS SCOPE. An unqualified "no positional readers" is a
  claim about the class from a scan of two spellings.

## Session Errors

1. **The census I shipped as the guard never ran on the CI rail.** `--detect`/`--fix`
   return before it. Recovery: replaced with `scripts/lint-anthropic-content-position.py`,
   twin-registered in `test-all.sh`. **Prevention:** a standing code invariant belongs
   on the rail that runs every PR, never in a launch-checklist script.
2. **A CI-gating lint was RED and no local gate surfaced it.** Recovery: `|| true` on
   both captures. **Prevention:** see the ratchet section above — routed to `work/SKILL.md`.
3. **T8 could go false-GREEN over a reverted reader.** Recovery: anchored the extraction
   on the assignment with comments stripped. **Prevention:** anchor on what executes.
4. **T8's non-empty guard was unreachable** — `pipefail` aborts the assignment before
   the `if`. **Prevention:** a guard that cannot run is worse than absent; drive it once.
5. **The shell suite could not tell 28-passed from nothing-ran.** Recovery: ADR-193
   instrument self-test + `MIN_ASSERTIONS` floor. **Prevention:** adopt the sibling
   pattern when authoring a suite, not after review finds it.
6. **Three unfalsifiable post-merge assertions.** Recovery: re-based on Better Stack,
   added `markerRunId`. **Prevention:** run every AC's literal command at plan time.
7. **Fixture gaps (≥2 text blocks; non-thinking non-text block).** Recovery: added both
   per reader. **Prevention:** count how many members of the quantified set the fixture
   instantiates — one member is a sample, not a proof.
8. **`${3:-{"content":…}}` mangled the default body** (the JSON's `}` closes the
   expansion). Caught by T3/T4/T6 failing. **Prevention:** assign defaults in their own
   statement when the value contains `}`.
9. **My own comment asserted the wrong mechanism** ("truncated" — measured: mangled).
   **Prevention:** measure the claim, including in a comment.
10. **AC2's grep collided with the comment documenting the fix.** **Prevention:**
    `cq-assert-anchor-not-bare-token` — the lint strips comments; the raw grep did not.
11. **Overstated "four readers"** — `email-triage/summarize.ts` already selected by type.
    **Prevention:** enumerate before claiming a class is closed.
12. **Wrong window start** (07-01 vs 07-06). **Prevention:** the defect is born at the
    swap; it starts RUNNING when the consumer is enabled.
13. **`sed "s|^$ROOT/|…|"` broke on a `|` in the path** — printed neither hit nor `none`.
    **Prevention:** quoted-expansion strip (`${l#"$ROOT"/}`), never interpolation into sed.
14. **New test file unregistered in `REPO_WIDE_SUITES`** — caught by the containment
    ratchet. **Prevention:** the ratchet is the reminder; heed it rather than routing around.
15. **My first lint regex missed a dotted `.length - 1`** — caught by my own fixture.
    **Prevention:** known-positive controls, per spelling.
16. **Shell CWD reset twice** after `cd` into `/tmp`. One-off.
17. **Six CI suites red after the local substitute set reported green** — the substitute
    recipe I had just routed into `work/SKILL.md` selects `lint-*-live` rows by NAME, and
    three of the six (`fixture-relative-assert`, `fixture-dir-operand-assert`,
    `preflight-check10-suite-integrity`) have no `run_suite` line at all: `SUITE_GLOBS`
    auto-registers them, so no `run_suite` grep can return them.
    **Prevention:** select by SHAPE (rows with no path argument) AND expand `SUITE_GLOBS`;
    the corrected recipe is in `work/SKILL.md`. Measured: 221 rows vs the filter's 19.
18. **My new floor scored as a construction failure, not a firing floor** —
    `guard-vacuity-floor` builds its mutant from the floor block plus the CONTIGUOUS simple
    assignments above it, so `MIN_ASSERTIONS` declared with the other constants left the
    mutant unbound under `set -u`. The ratchet read that as a new uncovered floor (15 → 17).
    **Prevention:** declare a floor's threshold on the line IMMEDIATELY above its `if`.
19. **The trap that fixed one ratchet broke another** — giving `mktemp -d` a destination
    under an owned root satisfied `lint-trap-tempfile-ownership` and cost the call its
    absoluteness proof, moving `fixture-relative-assert` from 3 to 20 sites. Redirecting
    `TMPDIR` at the owned root keeps the binding byte-identical and owns the same dirs.
    **Prevention:** after a ratchet fix, re-measure the OTHER ratchets reading those bytes.
20. **I read a ratchet's verdict from a name-filtered grep of the CI log** and concluded
    zero suite-level failures, because my regex anchored `^[FAIL]` while every CI line
    carries a `job\tstep\ttimestamp` prefix. The battery, not the log, surfaced the other
    three. **Prevention:** strip the known prefix before anchoring, and cross-read two
    independent sources before calling a failure set complete.
21. **Ran `lint-window-closure-assertion.py` without `--allowlist`** and read the rc=1 as a
    defect in files I had not touched. Same shape recurred: I ran
    `lint-shell-trace-credential-refusal.py` bare (rc=0, repo-wide mode) when CI runs it
    `--changed --base origin/main`, so the two violations this PR owned were invisible.
    **Prevention:** copy the invocation from its `run_suite` row OR its `ci.yml` step —
    flags select the MODE, and the wrong mode reports on a corpus that is not yours.
22. **A green step is not a clean job: CI aborts at the FIRST failing step.** `lint-bot-statuses`
    reddened twice on two different steps — `Lint tempfile-cleanup ownership`, then, once that
    passed, `shell-trace credential refusal (#7797)` on the same two files, which the job had
    never reached. Each fix bought one more step of visibility and one more CI round.
    **Prevention:** when a JOB fails, extract and run ALL of its steps locally, not just the
    one named in the failure. Parse the job body out of `ci.yml` and run the list.
23. **Watched a job matched by `test("deploy";"i")`, which resolved to "Deploy Documentation
    to Cloudflare Pages" rather than the web-platform deploy arm.** Had it gone green, the prd
    cron would have fired against the PREVIOUS build — the exact #8276 failure the deploy-arm
    rule exists to prevent. Caught before it mattered. **Prevention:** select the arm by
    `name == "Web Platform Release"` AND `event == "workflow_run"`, then the job named exactly
    `deploy`. `postmerge/SKILL.md` already documents this predicate, so this was an execution
    gap, not a doc gap.
24. **Reported a job as hung for 2h24m by comparing a UTC `started_at` against a local-time
    clock.** It was 24 minutes. **Prevention:** read both sides in the same timezone before
    computing an elapsed time.

## Related

- #5849 (EXECUTION_MODEL → claude-sonnet-5), #6100 (cron enabled), #8281/#8293
  (the tracker this unblocks), #8344 (the outcome marker).
- `knowledge-base/project/learnings/2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md`
  — the same class at the Opus 5 launch: a model swap silently broke a parser while
  `audit-models.sh` reported clean.
