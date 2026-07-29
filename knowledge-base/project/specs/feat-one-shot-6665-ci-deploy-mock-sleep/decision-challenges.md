# Decision Challenges — feat-one-shot-6665-ci-deploy-mock-sleep

Recorded headless (one-shot pipeline, no TTY) per ADR-084. Each entry is a
finding that argues the **operator's stated direction should change**, or a
Taste finding that was surfaced rather than silently applied. `/soleur:ship`
renders this into the PR body and files it as an `action-required` issue.

---

## DC-1 — Cut the `timeout-minutes` change from this PR entirely

**Class:** `user-challenge` (drops operator-requested scope — issue #6665's AC3
explicitly asks for `timeout-minutes` returned to 8 in this change).
**Raised by:** scoped strong-model consult (plan Step 4.5), independently
echoed in shape by the CTO's "it is a ceiling, not a budget".

**The challenge.** Lowering `timeout-minutes` 12 → 8 **saves nothing** — a
`timeout-minutes` is a ceiling, not spend. Its only effect is to convert runner
variance into flakes. Meanwhile the evidence available inside this PR is `n=1`:
the job includes network-bound, heavy-tailed steps (`apt-get install cloud-init`,
an alpine+bubblewrap docker build, `fetch-depth: 0` checkout) whose variance a
single PR run cannot capture, and "2× one observation" is not a ceiling policy.
The recommendation was: land the speedup with `timeout-minutes` unchanged at 12,
and lower it in a follow-up sourced from the **max over ~a week of main-branch
runs** via `gh api`.

**Why the plan did not adopt it.** The operator's stated direction (AC3) is the
default and this is scope the issue explicitly requested. The plan instead
tightened the evidence bar inside the PR: `timeout-minutes` moves only on ≥2 CI
observations, with the ceiling at ≈2× observed max, and falls back to `10`
rather than `8` if only one observation is available.

**Operator decision needed:** accept the tightened in-PR version, or defer the
budget change to a follow-up issue sourced from a week of main-branch runs.

---

## DC-2 — Drop the `MOCK_SLEEP_REAL` opt-out; make the mock unconditional

**Class:** `taste` (a simplification cut with no single right answer; the panel
split).
**Raised by:** code-simplicity-reviewer. **Opposed by:** CTO (recommended the
opt-out plus a guard), and by the in-repo precedent at
`apps/web-platform/infra/workspaces-luks-harness.sh:308-314`, which says that if
#6665 broadens the gate, "the thing to share is the opt-in convention".

**The challenge.** The plan's own Research Reconciliation proves the exclusion
set is **empty** — no test needs a real `sleep`. An opt-out with zero consumers
is unused surface; delete the gate rather than invert it, and add the opt-out
when a test actually needs one.

**Why the plan did not adopt it.** The opt-out costs approximately nothing (it
is the same `if`, inverted) and buys the plan's only attributability probe: Test
Scenario T2 runs the full suite under `MOCK_SLEEP_REAL=1` and expects wall clock
≈ baseline, which is what proves the speedup came from the mock rather than from
an accidental skip. Without the opt-out that probe is unavailable. The
reviewer's related objection **was** accepted: the count-based assertion
(`grep -c 'MOCK_SLEEP_REAL' >= 2` — a string-count proxy for a property) does not
survive into the final AC list. Note the AC *numbers* were compacted when four
criteria were cut, so the plan's current AC6 is a different, unrelated criterion
(the stale `~12s of slack` grep); the cut one has no surviving number to cite.

**MEASURED AT /work — keeping the opt-out paid for itself immediately, but not
for the reason the plan gave.** The plan defended the opt-out as enabling the T2
attribution probe. T2 did confirm attribution (opt-out run 8m50.139s vs 8m56.685s
baseline). But its actual value was different and larger: **T2 failed, 183/184**,
exposing a defect this PR had introduced. T-6525-8's new schedule assertion reads
`$MOCK_SLEEP_LOG`, which only exists when the mock is installed — so under
`MOCK_SLEEP_REAL=1` it failed on an empty log rather than on a real regression.
Fixed by forcing the mock on for that one arm and restoring the caller's value.

The honest reading cuts both ways. It is **not** evidence that the opt-out is
load-bearing in production terms — with DC-2 adopted (no opt-out at all) the
defect could not have existed, because nothing could have disabled the recorder.
What it does show is that a knob with zero consumers is not automatically inert:
adding it created a reachable state in which a test silently loses its
observation channel, and only exercising that state caught it. The opt-out is
kept, and the arm that depends on the recorder now defends itself against it.

---

## DC-3 — Drop the `$MOCK_SLEEP_LOG` recording rider entirely

**Class:** `taste` (panel split on scope).
**Raised by:** code-simplicity-reviewer ("file as a follow-up").
**Opposed by:** DHH ("six lines, genuinely worth it — but stop lying about
why"), CTO ("in scope, capped at one log and one assertion"), and an in-repo
precedent.

**The challenge, and the factual correction it carried.** The reviewer was
**right about the fact** and the plan's original rationale was **wrong**:
T-6525-8 already sets `MOCK_SLEEP_NOOP=1` (`ci-deploy.test.sh:3951`) and already
pays 0 s, so the inversion removes no coverage. The recording rider is therefore
**net-new coverage for a pre-existing gap**, not regression protection. The plan
was corrected to say so.

**Why the plan kept it.** It is ~6 lines closing a real mutation hole (the
production default backoff schedule `"2 4"` can be mutated to `"9 9"` and the
suite stays green), in the suite that guards the production deploy script — and
it is the **established house pattern**, not an invention: `workspaces-luks-harness.sh`
(#6807, modelled on `nic-wait-gate.test.sh`) already uses a RECORDING no-op
sleep for exactly this reason, with `rec()` at `:163`.

---

## DC-4 — AC1's 120 s target may be arithmetically unreachable

**Class:** `taste` (an acceptance-criterion framing the operator set in the
issue).
**Raised by:** code-simplicity-reviewer and the strong-model consult, converging.

**The challenge.** The measured CPU floor is `user + sys ≈ 117 s` — the
*counterfactual's* CPU (`0m36.572s + 1m20.362s`, measured with the sleep mock
forced on), which is the figure the plan uses consistently in §R2 and AC1. (The
*baseline's* `user + sys ≈ 134 s` is the wrong number to argue from: it includes
CPU burned by processes that also slept.) That ~117 s is process-spawn cost for
thousands of subshells and mock binaries, which no sleep mock removes. On a
2-vCPU CI runner the floor is likely higher still.
Planning around 120 s is planning around a number the arithmetic already
refutes; the honest restatement is "eliminate the ~400 s of sleep wait", and the
binding floor should be measured on **CI**, not locally.

**Plan response.** AC1 was restated floor-relative: it reports the measured
floor and the sleep seconds eliminated, and explicitly permits an evidenced miss
of 120 s rather than a silent one. Going below the floor would require a
different architecture (sharding the suite, or reducing subshell/mock-spawn
count) and is out of scope here.

**MEASURED AT /work — the challenge's premise is REFUTED, and the plan's own
counter-argument was wrong too.** Both sides of this exchange reasoned from a
local number and then guessed about CI. The challenge said "the binding floor
should be measured on **CI**, not locally" — that half was right, and nobody ran
it. Run on this PR: the `Run ci-deploy.sh tests` step completes the identical
**184/184 in 25 s** on the CI runner (run `30302371047`, job total 179 s), which
is *one fifth* of the ~117 s local CPU floor the whole argument rested on. The
local box was clocked at ~1.4-1.5 GHz against a 5.0 GHz maximum during
measurement, so the "floor" was a throttled-laptop artifact, not a property of
the suite. The plan's rebuttal — "on a 2-vCPU CI runner the floor is likely
higher still" — was wrong by an order of magnitude in the opposite direction.

So 120 s is **not** arithmetically unreachable: on CI, where the budget this
issue is about is actually spent, the suite is already ~5× inside it. AC1's
local miss (8m57s → 4m16s, still above 120 s) stands as an *evidenced* miss whose
cause is now named rather than attributed to an inherent floor.

**Operator decision needed — now much narrower:** none required for AC1 on the
merits; #6665's 120 s target is met where it matters (CI). The only remaining
question is whether AC1 should be re-scoped to measure on CI rather than
locally, since the local figure tracks operator hardware and not the code.
