# Decision Challenges — feat-one-shot-6578-sibling-guard-reachability

Recorded by `soleur:plan` / `soleur:plan-review` in headless (one-shot) mode per ADR-084.
Not auto-applied: each challenges operator-stated direction. `ship` Phase 6 renders this into
the PR body and files an `action-required` issue.

---

## UC-1 — the brief asks for two classes; the plan ships two classes **plus an explicit `UNDECIDED` bucket**

**decisionClass:** `user-challenge`
**Raised by:** plan-time reconciliation against `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
**Status:** NOT applied as written — plan adds a third, explicitly-reported bucket. Operator can revert to a strict binary.

**Your stated direction (the default):**

> "Classify every site into one of those two classes with per-site evidence." — reachable vs
> structurally incapable.

**What the challenge is:**

The plan reports **two decision classes plus an `UNDECIDED` bucket** that must be either empty or
justified per-site. If the classifier decides everything, `UNDECIDED` is empty and your binary
holds unchanged — you lose nothing. It is non-empty only where a site's deciding datum genuinely
cannot be obtained by this method.

**Why:**

The reachability predicate R3 asks whether a producer can emit ≥2 writes before the match. For a
var-fed site (`printf '%s' "$var" | grep -q P`), that depends on the var's **maximum** size, which
depends on where the var came from. Where the assignment traces to an unbounded source
(`$(bash ./ci-deploy.sh ...)`), R3 is TRUE. Where it traces to a literal, R3 is FALSE. Where it
traces to something the classifier cannot bound, **R3 is genuinely undecided**.

Forcing that third case into "structurally incapable" is not a rounding error — it is precisely how
the figure this task exists to replace was produced. The prior record's "194 of 233 feed a bounded
var (one write, no window)" is a write-count claim over sites whose var sizes were never
established. The governing learning is explicit:

> "When the deciding datum is unavailable, every hypothesis is UNKNOWN — including the ones that
> feel refuted."

A binary that hides its undecided cases would hand you a *smaller, cleaner, and equally unmeasured*
number — the same defect in a new PR, which is the one outcome this task cannot afford.

**Why this is surfaced rather than just done:**

It deviates from your explicit instruction, and per ADR-084 operator direction is the default. It
is recorded so you can overrule it, not resolved silently.

**Cost if you switch later:** negligible. Reverting to a strict binary is a reporting change — fold
`UNDECIDED` into whichever class you prefer. But note that folding it into "structurally incapable"
restores the exact over-claim the prior filing was rejected for, and folding it into "reachable"
over-states the remediation scope.

**What we need from you:** nothing to proceed. If you want a strict two-class ledger, say so and
the bucket is folded on your instruction (name which class it folds into).

---

## UC-2 — the brief's "capture-once closes the empty-read-back hole" is imprecise; the plan pins the **pairing** instead

**decisionClass:** `mechanical` (a factual correction, applied — recorded for visibility)
**Raised by:** plan-time verification against `apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh:277-291`
**Status:** APPLIED — the constraint is implemented as specified in intent, not as worded.

**Your stated direction:**

> "The capture-once-then-match style that shipped closes that hole. Any site converted here must
> preserve that property — an empty read-back must fail loudly, never pass silently."

**The correction:**

Capture-once **alone does not close the hole.** The merged PR measured this and says so in the file
itself. `scan-workflow.test.sh:277-283` annotates the `[[ -n "$script_code" ]]` FATAL line:

> "NOT a fail-open guard, despite appearances — measured: delete this line, point `$SCRIPT` at an
> all-comment file, and the check below DOES take its `pass` branch, but the non-vacuity check
> after it catches the empty capture and the run still exits 1. This line is here for the
> DIAGNOSTIC."

What actually fails loudly on an empty read-back is the **paired non-vacuity rung** at `:291`
(`grep -qF '.lints[]' <<<"$script_code"` → fail if absent).

**Why it matters that this is stated precisely:** a converter who believes capture-once closes the
hole will convert a site, add no pairing, and ship the hole believing it closed. Your *intent* —
an empty read-back must fail loudly — is preserved exactly; the plan implements it as the pairing
rule (FR4), which is the thing that actually delivers it, plus the non-empty guard for the
diagnostic. The pinning test (E1/E2) asserts the pairing, and E2 asserts E1 is not vacuous.

**What we need from you:** nothing. Recorded because it corrects a premise in your brief, and this
PR's whole subject is premises that sounded rigorous but were not.

---

## UC-3 — two reviewers argue the measurement should not happen at all: convert the class blind

**decisionClass:** `user-challenge`
**Raised by:** `dhh` + `cto` (converging), plan-review 2026-07-17
**Status:** NOT applied — plan retains your stated direction (measure first, then scope). Reversible in one pass.

**Your stated direction (the default, retained):**

> "The operator has now chosen the step that was actually missing: do the measurement first, rather
> than the unmeasured conversion." … "If the reachable set is small, convert those sites in this
> PR. If large, ship ONLY the measurement."

**What the challenge is:**

Skip the measurement. Apply `| grep -q<flags> P` → `| grep -<flags> P >/dev/null` to the class
blind. It removes the early-exit, therefore the window, therefore the bug — at every site, with no
per-site judgment and nothing left to measure.

**Why they argue it — and the parts that are measured, not asserted:**

1. **The transform is semantics-preserving.** `dhh` ran it: `producer | grep -q P` inverts;
   `producer | grep -F P >/dev/null` does not. Both agree on the match/no-match verdict.
2. **Measurement cannot triage this class anyway.** Verified: the `pipefail` filter eliminates ≤16
   of 284; the rc-consumption filter ~0 (zero `|| true` overlap, and `set -e` in 32/44 files is
   itself the consumer). So window-existence decides everything — and it is undecidable for the
   dominant var-fed class without exactly the byte model #6573 retracted. **The apparatus cannot
   produce the number your scope rule consumes.**
3. **The cost asymmetry is real.** `cto` priced it: one mechanical diff and zero ongoing
   maintenance, versus a probe script, a CI registration, an audit note, and a standing
   regenerate-on-drift obligation — to decide the fate of 46 production sites.
4. **This is not new.** #6573's `cto` already argued it (UC-1 point 4 of that PR: option 1 "unlocks
   the repo-wide sweep… applicable **blind**, with no per-site judgment"). You declined it there.

**Why the plan did not apply it:**

- It reverses your explicit stated direction, and per ADR-084 operator direction is the default. A
  reviewer's cost argument does not silently override a decision you have now made twice.
- `dhh` argued the opposite on #6573 and still would: `>/dev/null` leaves the landmine armed — the
  next person who "tidies" it back to `-q` re-detonates it. The here-string removes the *class*.
- The specific `sed` proposed is **unsafe as written**: appending `-F` to `-qE` yields conflicting
  flags. The correct transform is `-q<flags>` → `-<flags>` plus `>/dev/null`. It is mechanical, but
  it is not the one-liner it was pitched as.
- Dropping `-q` makes `grep` read its input to EOF. Harmless on bounded producers; a **hang** on an
  unbounded one. Blind application needs that ruled out first — which is itself a measurement.

**What the plan does instead:** it found the split the argument missed. **238 of 284 sites are
`*.test.sh` internals; only 46 are production, across 11 files.** Nobody had partitioned the corpus.
That makes the production class tractable *without* the undecidable window analysis — so the plan
converts production (per your "small ⇒ convert" arm) and tracks the test-harness subset. If that
holds at /work time, UC-3 is moot: you get the fix *and* the measured basis for it.

**Cost if you switch later:** low. If you prefer the blind sweep, the plan's Phase 1-2 output tells
you exactly which 46 production sites to hit first, and the transform is one pass.

**What we need from you:** nothing to proceed. Say so if you want the blind sweep instead of the
partitioned conversion.
</content>

---

## UC-4 — the plan's AC1 mechanism was falsified at /work; implemented to its intent instead

**decisionClass:** `mechanical` (a correctness fix, applied — recorded because it overrides a written AC)
**Raised by:** /work Phase 0, measuring the authoring host before trusting the plan's premise
**Status:** APPLIED — AC1 implemented as a behavioural probe, not the identity check it specifies.

**The plan says:**

> **AC1** — the probe ... **exits non-zero** when `grep` resolves to a non-GNU implementation
> (verify by running it with a ugrep/BusyBox shim first on `PATH`).

and, in Reconciliation (b), attributes the authoring session's 0/200 readings to
`type grep → dispatches to ugrep 7.5.0`.

**What was measured:**

```
command -v ugrep                    → not found          # ugrep is not installed on this host
/bin/grep --version                 → grep (GNU grep) 3.12
type grep                           → grep is a function                 (an arg-filtering wrapper)
bash slowprod.sh | /bin/grep -q M   → PIPESTATUS=141 0   0.016s          (early-exit: defect LIVE)
bash slowprod.sh | grep -q M        → PIPESTATUS=0   0   5.256s          (drained: defect INVISIBLE)
unset -f grep; …| grep -q M         → PIPESTATUS=141 0   0.015s
```

The plan's **conclusion was right and its mechanism was wrong**: the drain is real and would have
produced a false all-clear, but ugrep is not on this host at all — a shell **function** was
shadowing GNU grep.

**Why this is not a footnote.** AC1 as written cannot catch what actually happened here. The
resolved binary **was** GNU grep 3.12, so an identity/`--version` assertion **passes** while every
reading is 0/N. The plan's own stated intent — *"No verdict may be taken from a host whose `grep` is
not the CI `grep`"* — is undeliverable by the mechanism it prescribes.

**What was implemented:** the probe asks the question that discriminates — *when a match arrives
early, does this grep exit and let the producer die?* (`PIPESTATUS[0] == 141`) — and refuses to emit
a verdict otherwise. This catches ugrep, this host's function wrapper, and any future draining grep.
The attestation's T3 rung pins it with a shim that reports `grep (GNU grep) 3.12` **and drains**:
under the plan's AC1 that shim passes; under the implemented gate it is refused.

**What we need from you:** nothing. The AC's intent is met more strictly than its text. Recorded
because it overrides a written AC, and because this PR's subject is premises that sounded rigorous
and were not — including its own.

---

## UC-5 — the plan's headline partition (its "most decision-relevant fact") was itself unnormalised

**decisionClass:** `mechanical` (a correction, applied — recorded for visibility)
**Raised by:** /work Phase 1, re-deriving the plan's Reconciliation row 9 rather than adopting it
**Status:** APPLIED — the note reports the normalised figures; the plan's raw ones are not restated.

**The plan says** (Reconciliation row 9, flagged **"the single most decision-relevant fact in this
table"**): 238 of 284 sites are `*.test.sh`; **46 production across 11 files**.

**Measured, after normalisation:** **124** test-harness, **34 production across 8 files**; 158 real
sites of 280 raw hits.

**Why they differ:** row 9's command is a bare `git grep` + per-file `grep -c`. It counts comments,
fail-message strings, and heredoc bodies — and it counts `||` as a pipe. **122 of the 280 raw hits
(44%) are the repo documenting the shape it forbids**, and `cmd_a || grep -q P FILE` feeds grep no
stdin at all.

So the plan's partition — the fact it leaned on to declare the production class tractable — is a
syntax count. That is a milder instance of the exact defect the plan was written to correct, sitting
in the row the plan calls its most decision-relevant. Noted without irony: the same trap caught this
probe's first draft, and the earlier fix twice.

**What changed as a result:** nothing in the disposition. 34/8 and 46/11 both sit inside the
convert threshold, and the security-rung auto-forfeit overrides both. The correction matters for the
artifact's honesty, not its conclusion — which is stated in the note so the precision is not
mistaken for load-bearing.

**What we need from you:** nothing.
