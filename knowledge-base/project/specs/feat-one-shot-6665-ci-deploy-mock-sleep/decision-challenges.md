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
reviewer's related objection to AC6 (`grep -c 'MOCK_SLEEP_REAL' >= 2` is a
string-count proxy for a property) **was** accepted — AC6 is cut.

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

**The challenge.** The local baseline is `user + sys ≈ 134 s` of pure CPU
(process-spawn cost for thousands of subshells and mock binaries) — which no
sleep mock removes. On a 2-vCPU CI runner the floor is likely higher still.
Planning around 120 s is planning around a number the arithmetic already
refutes; the honest restatement is "eliminate the ~400 s of sleep wait", and the
binding floor should be measured on **CI**, not locally.

**Plan response.** AC1 was restated floor-relative: it reports the measured
floor and the sleep seconds eliminated, and explicitly permits an evidenced miss
of 120 s rather than a silent one. Going below the floor would require a
different architecture (sharding the suite, or reducing subshell/mock-spawn
count) and is out of scope here.

**Operator decision needed:** confirm the restated AC1, or amend #6665's stated
120 s target to match the measured floor.
