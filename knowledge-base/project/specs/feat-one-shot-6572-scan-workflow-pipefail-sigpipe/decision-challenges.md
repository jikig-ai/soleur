# Decision Challenges — feat-one-shot-6572-scan-workflow-pipefail-sigpipe

Recorded by `soleur:plan` / `soleur:plan-review` in headless (one-shot) mode per ADR-084.
Not auto-applied: each challenges operator-stated direction. `ship` Phase 6 renders this into
the PR body and files an `action-required` issue.

---

## UC-1 — `cto` (devex) challenges the operator's preferred fix (option 3 → option 1)

**decisionClass:** `user-challenge`
**Raised by:** `soleur:engineering:cto` (devex axis), plan-review 2026-07-16
**Status:** NOT applied — plan retains operator-stated direction (capture-once + here-string)

**Your stated direction (the default, retained):**
The task brief states: *"option 3 (capture producer output once into a variable, then match
against it) is **preferred** since it also avoids re-running the producer per check."* The plan
implements that: capture once into `script_code`, match via here-string.

**What the challenge is:**
`cto` recommends **option 1** instead — `<producer> | grep -F P >/dev/null` at all 7 sites —
keeping `script_code()` as a function and not capturing at all.

**Why they argue it:**
1. **Smaller, safer diff.** Per site: delete one `q`, append ` >/dev/null`. Flags, polarity,
   producer and both comment blocks are untouched — so the plan's two top-ranked risks
   (semantic `-F`→`-E` drift, polarity inversion) become *structurally impossible* rather than
   gated by an AC. AC4 exists only because the here-string transform can drift; option 1
   deletes the risk and the AC together.
2. **The capture-once benefit is worth ~zero here.** `script_code` is 8035 bytes read 3×.
   That is the half of the issue author's preference that this plan already proved wrong on
   the other half — deferring to it on the worthless half is backwards.
3. **`:157` readability.** The here-string form nests a command substitution inside a
   here-string (`<<<"$(grep -E '^\s*API=' "$SCRIPT")"`), so read order runs right-to-left
   against the data flow. Option 1 leaves a flat left-to-right pipeline.
4. **It unlocks the repo-wide sweep this plan rejected.** `| grep -q<flags> P` →
   `| grep -<flags> P >/dev/null` is semantics-preserving and applicable **blind**, with no
   per-site judgment — so the 591-site class could be fixed mechanically, which the
   here-string form cannot (it needs a variable per site).

**Why the plan did not apply it:**
- It contradicts your explicit stated preference, and per ADR-084 operator direction is the
  default — a reviewer's taste does not silently override it.
- `dhh` argued the **opposite** and equally strongly: the here-string removes the *class*
  (`producer | grep` is gone), whereas `>/dev/null` leaves the landmine armed — the next
  person who "tidies" `>/dev/null` back to `-q` re-detonates it. *(Counter-note: the Phase 3
  self-check would catch exactly that regression, which weakens dhh's objection.)*
- The here-string is established in-repo precedent (`deploy-status-fanout-verify.test.sh:244`
  is a verbatim match), so it is not an invented idiom.

**Cost if you switch later:** low. Both forms satisfy the close condition, both satisfy the
Phase 3 guard, both are measured 0/100 at 1.3 MB. The decision is reversible in one pass.

**What we need from you:** keep capture-once + here-string (current plan), or switch to
option 1? If you switch, AC4 can be dropped and the 31-file sibling sweep (UC-2) becomes a
mechanical `sed`.

---

## UC-2 — sibling-guard sweep: NOT filed (CONCUR gate dissented; verified)

**decisionClass:** `taste` (surfaced, not a scope change to this PR)
**Raised by:** `architecture-strategist` + `cto`, converging
**Status:** NOT filed — the CONCUR gate dissented at review and the dissent held on inspection (see the plan's Alternatives table). The 230-site figure is a syntax count, not a vulnerability count: 194/233 sites feed a bounded var (one write, no window). Scope of this PR unchanged.

v1 declined to file anything, reasoning that "the shape is legitimate and safe in the
overwhelming majority of cases; a tracking issue would imply a debt that does not exist."
Both reviewers showed that reasoning was argued against the wrong denominator (the 591
repo-wide sites) and never sized the middle tier: **31 files / 235 sites** under
`apps/web-platform/infra/**` that set `pipefail` and carry this shape — same architectural
niche, same runner, same advisory job.

This session's evidence is that the shape is **lucky, not safe**, and that luck is invisible
to local runs (the unfixed guard passes 0/400 locally and still fails on CI). So "no debt
exists" is an over-claim. The plan now files a **narrow** issue scoped to those 31, triaged by
fail-open polarity. Scope of *this* PR is unchanged (one file).

**What we need from you:** nothing. The sweep is neither folded in nor tracked, because no one has
measured which sibling sites are actually at risk (the predicate is per-site: can the producer emit
≥2 writes before the match, and is the polarity match⇒fail?). Filing a 230-site defect claim without
that measurement would assert a population that does not exist. If you want it tracked, the first task
is the measurement, not the conversion.
