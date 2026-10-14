---
date: 2026-08-12
issue: 7440
pr: 7444
category: workflow-patterns
component: registry-zot-log-shipper
problem_type: process_issue
tags: [review, mutation-testing, fixture-design, fail-open, jq, assertion-floor, adr-ordinal]
---

# Every fix I shipped reintroduced the class it closed

## Problem

A 12-agent panel re-reviewed PR #7444 after a first review that was a measured **0 of 12**. It found
~20 P1s — and **most of them were in the nine fixes made the previous round**, not in the original
change. Then, fixing those, I introduced four more defects of the same classes and caught them
inside the same session.

That is the finding. Not "review is valuable" — the specific, measurable shape: **a fix PR's own
fixes are the least-pinned code in the diff**, because they are written after the tests, and nothing
forces coverage for them.

## The four defects my own fixes introduced

All four were caught before merge. Three of them by the **non-vacuity fixture** — "a credential-free
plaintext line must still ship with its content intact" — and not by any of the six leak fixtures.

1. **`$m | fromjson? | .message? // ""` binds NOTHING when the input is not JSON.** `fromjson?`
   emits *no value* on a parse error, so `as $z` never bound and jq dropped the **whole record**.
   Every plaintext line — Go panic traces, docker daemon lines, pre-logger startup errors, i.e. the
   highest-value evidence — vanished at the jq stage with no drop row and no stderr. Strictly worse
   than the bug it was part of fixing. Fix: `(($m | fromjson? | .message?) // "")` — the parens
   apply the alternative to the empty stream.

2. **A residual-check regex backtracked.** `(...)"?[[:space:]]*:[[:space:]]*[^R]` — with `[^R]`
   alone, `[[:space:]]*` matches zero characters and `[^R]` then matches the space itself, so a
   correctly-redacted `Authorization: REDACTED` read as a residual and the row was **dropped**,
   discarding a panic trace whose credential had already been removed. Fix: `[^R[:space:]]`.

3. **`jq` block-buffers on a pipe.** Without `--unbuffered`, a tick killed mid-drain had persisted
   no cursor for rows it had already read. Caught because an existing SIGKILL-durability test went
   RED the moment the single-jq pipeline landed.

4. **Compacting the redactor reintroduced `$keep | index(.key | ascii_downcase)`** — inside
   `index()` the input is the **array**, so `.key` resolves against it and jq errored on every JSON
   row. This is the *exact* bug I had fixed hours earlier in the same session, rewritten straight
   back in while shortening the program for a byte budget.

**Litmus that would have caught all four earlier:** for every transform, name a fixture on the *far
side* of it. A suite whose fixtures all assert "the secret is gone" cannot see a redactor that has
become too aggressive, or one that has stopped emitting anything at all.

## Guards that certified nothing

**An assertion floor over `PASS + FAIL` counts assert CALLS, not evaluations.** The floor added the
previous round was defeated by a one-token edit: moving the increment from the `else` branch to the
`if` branch yielded `=== 131 passed, 0 failed ===` at rc=0 **with nine literal `FAIL:` lines on
screen**. The count-preserving variant (never evaluate `$cond`) did the same. Fixed by deriving both
counters from a record appended at decision time, plus a canary asserting one MUST-fail and one
MUST-pass before any real assertion runs.

**The canary had to be checked IN THE GATE.** Deleting the canary block was itself an undetected
mutation that re-opened the hole the canary closes. There is always a final turtle; make it a
loud one.

**A floor at EOF is deleted by the truncation it detects.** Cutting the suite from T5 onward removed
the floor, the gate *and* the summary line, and both runners branch on rc alone. Moved to an `EXIT`
trap declared near the top. **Two `trap … EXIT` lines is a bug** — bash keeps only the last handler
per signal, so a second one silently discards the gate.

## The cap bounded egress, not work

Cap-dropped rows hit `continue` *before* `persist_cursor`, so the cursor advanced only on delivery.
Three consequences, all measured:

- Draining N entries cost ~N²/CAP scans. A full 512 MB journal is ~806,000 entries → ~2.4M process
  spawns in one tick, 2.7–5.4 h of CPU on a 2-shared-vCPU host, to deliver at most CAP rows.
- `dropped_cum` counted the same physical row once per tick until it eventually shipped: 40 offered,
  40 delivered, **`dropped_cum=140`**.
- Worst: an **exempt** row arriving after capped rows bypassed the cap test and advanced the cursor
  past them. The same 40-row input lost **0 rows or 35 rows** depending only on whether one `gc`
  line trailed it — with a **byte-identical** `n=35 reason=rate_cap` record in both cases.

A capped row is *decided and accounted*, not undelivered. Only an undelivered row may hold the
cursor.

## A fixture can pass for the wrong reason

The first anchoring fixture (30 rows that merely *mention* the envelope mid-line, asserting they do
not count as delivery) **passed while the unanchored mutant survived it**. The rows lacked the
zot-only token, so the probe rejected them via a completely different arm.

A case whose fixture is rejected for a *second* reason proves nothing about the property it names.
Build it **adversarial**: correct in every field the success path reads, except the one under test.

## An instrument must be verified before its output is read

Four measurements I took to check my own work were themselves broken:

- **A mutation battery ran against a RED control** — the sandbox copy broke `SCRIPT_DIR` so the
  suite could not find the template. Every row was void. A second attempt did the same for the probe
  suite, which delegates to the real linter and reads the git index and therefore cannot run outside
  the repo at all.
- **A mutation-landing check was shell-mangled**: `\$` inside double quotes collapsed to an
  end-of-line anchor, so the probe reported "mutation did not land" on a mutation that had.
- **The infra runner was launched while I was still editing the tree**, producing an invalid 90/4.
- **Task notifications reported `exit code 0` while the rc file said `1`** — three times — because
  the notification reports the trailing waiter, not the runner.

Rules that follow: run the **unmutated control first** and treat a red control as voiding every row;
assert the mutation landed against a **pristine backup**, not `HEAD` (the tree is legitimately dirty
during a review pass); confirm the tree is clean before launching a long gate and do not edit under
it; read the **rc file**, never the notification.

## Two more shapes worth naming

**A derivation is stale by the time a review round ends.** The ADR was renumbered **179 → 182 →
184**. The 182 derivation was correct when run at the start of the round; by the end a sibling
branch had claimed 182 *and* 183. What found it was rewriting the section to say "re-derive
immediately before merge" and then actually running that command. A review round is long enough for
the contended range to move underneath you.

**A one-shot verification criterion transcribed into a standing gate becomes a policy nobody
decided.** `headroom >= 20000` was #7299's AC1 — proof that a *measurer* fix had landed. Transcribed
into a regression arm, it silently rationed every future feature on the host to 3,360 B and blocked
a correctness round at 11% over. The CTO ruled it a scope slip (ADR-185): no script enforced it, the
runbook stated the invariant as `headroom > 0` strictly, the sibling host ran at 12,312 B headroom
under a 4× looser budget, and the fingerprint was two constants travelling together where one kept
its referent and one did not. Fixed by **deriving** the floor from the single owning constant.

**Then that very evidence went stale mid-merge, which is the same lesson one level up.** During the
merge poll a BEHIND auto-sync pulled #7264, whose amendment applies the same rationale-strip to
git-data's own cloud-init template and re-measures it at **20,180 B headroom** — so ADR-185's
"a 20,000 B headroom floor would red git-data on contact" became false, by 180 B, hours after it was
written. The measurement had propagated to four sites (the ADR body, its References, a comment in
`registry-userdata-budget.test.sh`, and this file). Corrected everywhere by restating the claim as
what the owning constant *authorises* (`GIT_DATA_BUDGET = 28_000` → headroom as low as 4,768 B),
which is the part that encodes a policy and does not drift.

Two rules fall out. **Cite the constant, not the reading** — a measurement pinned into prose is
false the moment someone else's PR moves it, and the one that moves is disproportionately the one
you leaned on. And **a claim of the form "X would fail this gate" is a measurement wearing an
argument's clothes**: it reads as reasoning and behaves as a reading. The corrected bullet is
stronger than the original, because a host that clears an arbitrary floor by 180 B — and only via an
unrelated compression change — demonstrates the floor is arbitrary better than a host that misses it.

**Ask of any threshold in a standing gate: was this authored as a policy, or as a one-time proof
that something landed?**

## Panel claims are claims

Agent output needed the same verification as everything else. `git-history-analyzer` cleared
ADR-182 as free (it was taken) and reported that only `test-all.sh` would conflict on rebase (four
files did). `architecture-strategist` was right on both. Cheap, checkable, load-bearing facts got
re-measured rather than adjudicated.

Conversely, **convergence was the strongest signal available**: four independent lenses reached the
cap/cursor defect, three the false exit-code claim, and four the exempt-ceiling magnitude.

## Empty captures are not failures

A docker-based suite reported **6** failures on a contended box and **1** on pristine `origin/main`.
The extra five were arms whose captures were empty (`capture-a=[]`, `marker=0`) — which the suite
*itself* declares "proves nothing". Separated environment from regression three ways: the diff
touches zero files in that area; pristine main reproduces the root failure; CI on main is green.

## Session Errors

1. **Ran `ls specs/…` from the bare-repo CWD** instead of the worktree, twice. **Prevention:** on a
   bare-repo root, resolve the worktree path before any relative read.
2. **Mutation-landing regex shell-mangled** (`\$` → anchor inside double quotes), giving a false
   negative. **Prevention:** put mutation scripts in quoted heredocs; never build a regex through a
   double-quoted shell layer.
3. **Mutation battery run against a RED control** (sandbox broke `SCRIPT_DIR`). **Prevention:** run
   and require a GREEN unmutated control before reading any mutation row.
4. **Second sandbox attempt also RED** — the probe suite delegates to the real linter and reads the
   git index. **Prevention:** mutate in place with an echoed backup when a suite is repo-coupled.
5. **Reintroduced `$keep|index(.key|…)` while compacting** — the same bug fixed hours earlier.
   **Prevention:** after any compaction of a program, re-run the adversarial fixture set, not just
   the suite.
6. **`fromjson?` parenthesisation dropped every plaintext row.** **Prevention:** covered by the
   non-vacuity fixture, now permanent.
7. **Residual regex backtracking dropped correctly-redacted rows.** **Prevention:** same fixture.
8. **Missing `--unbuffered`.** **Prevention:** caught by the SIGKILL-durability test; keep it.
9. **My own assertion matched the rationale comment** containing `timeout 240`. **Prevention:**
   scope body-greps to the executable line, never the block, whenever the block documents the thing
   it asserts.
10. **`sed` updated the floor's message but not its quoted comparison**, briefly leaving a
    mismatched pair. **Prevention:** after editing a paired literal, grep both and compare.
11. **Compacted jq at column 0 broke the YAML block scalar.** **Prevention:** re-render after every
    template edit (the validator caught it immediately).
12. **C13b passed for the wrong reason**, so the unanchored mutant survived. **Prevention:** build
    fixtures adversarial; mutation-prove every new guard.
13. **Ran the infra runner while editing the tree**, invalidating it. **Prevention:** confirm
    `git status --porcelain` empty before launching, and do not edit under a live run.
14. **Task notifications reported exit 0 while rc said 1**, three times. **Prevention:** read the rc
    file; never the notification.
15. **Read `tenant-dpa-register-guard` rc=2 as a failure** — it was "no subcommand given".
    **Prevention:** read a non-zero exit's message before classifying it.
16. **`comm` on unsorted input.** **Prevention:** sort both sides.
17. **Stopped after a status report mid-pipeline**; the operator had to ask "why did you stop?".
    **Prevention:** a status summary is not a handoff — the next tool call must continue the
    pipeline in the same response.

## Forwarded from session-state.md

- Planning subagent terminated early (`API Error: Connection lost mid-response`, 406,552 tokens, 78
  tool uses). Recovered from on-disk artifacts; recovery ran once.

## Related

- ADR-184 (the shipper), ADR-185 (the headroom policy this surfaced)
- `knowledge-base/project/specs/feat-one-shot-7440-zot-log-shipping/review-findings.md` (round 1)
- #7291 (the docker suite's local-red class, commented with the S1 measurement)
