---
title: "Every verification I wrote passed, and three of them proved nothing"
date: 2026-09-04
issue: 3210
pr: 7828
tags: [verification, mutation-testing, bash, exit-codes, cwd, ratchets, legal-corpus, adr-ordinals]
category: workflow-patterns
---

# Every verification I wrote passed, and three of them proved nothing

Shipping the Corporate CLA mechanism (#3210). The implementation was mostly
uneventful. What was not uneventful was how many of my own *checks* were
satisfiable without the property they claimed to check being true.

## 1. An exit code cannot discriminate when both sites return it

Guard 3 (contribution-triggered entry) is enforced at two places on purpose: the
write path in `ccla-add.sh` and a CI test. I wrote a mutation arm that deleted
the write-side check and asserted the exit code changed.

It did not change. The validator independently returns `4`, because the two
sites are genuinely redundant — which is the design working. So the arm was
scored FAIL, and the honest reading was that **my assertion was wrong, not the
code**. An exit-code assertion there is satisfied by the correct answer and by
the mutant, and it looks rigorous either way.

The fix was to assert on the **producer** of the refusal, not its code: the
baseline refuses at the write path before anything is built; the mutant only
gets as far as the validator. Same verdict, different message, and the message
is the only observable that separates them.

**Generalises to:** any defense-in-depth pair. If two layers return the same
verdict, the verdict cannot test either one. Find what differs — the message,
the ordering, the side effect that did not happen.

## 2. A failing EXIT trap silently overwrites your exit status

`ccla-add.sh` documented exit codes 2 / 3 / 4 for pre-flight, schema and
entry-gate failures. Every one of them was arriving as `1`.

The cause:

```bash
cleanup() { [[ ${#TMP_FILES[@]} -gt 0 ]] && rm -f "${TMP_FILES[@]}"; }
trap cleanup EXIT
```

When there is nothing to clean up the `[[ ]]` is false, the `&&` list returns 1,
and **a failing last command in an EXIT trap replaces the script's exit status.**
The entire documented contract was unobservable, and a test asserting "it fails"
would have passed while asserting nothing about *how*.

```bash
cleanup() {
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then rm -f "${TMP_FILES[@]}"; fi
  return 0          # <- load-bearing
}
```

The same trap also `rm -f`'d a caller-supplied file, because it cleaned paths it
had not created. **Clean up only what you made.**

## 3. CWD persists between tool calls, and a drifted CWD manufactures clean results

Twice I ran `git grep` and got zero hits, and twice the zero was an artifact: an
earlier call had `cd`'d into a subdirectory, so the pathspecs matched nothing.

The failure mode is the dangerous direction — **a drifted CWD produces an empty
result, and an empty result reads as "clean"**. The first time, I nearly recorded
"the plan's six producer sites do not exist". Re-run from an explicit absolute
root: the six were exactly where the plan said.

Prefix with an explicit `cd <abs>` in the same call, and treat any surprising
zero as a measurement bug until the CWD is proven.

## 4. Probe the ordinal you will use, not the maximum

`tasks.md` said to re-derive the ADR ordinal before merge. The maximum moved
between the two probes — ADR-200 at plan time, ADR-202 at merge time — and my
rule ("max moved ⇒ renumber") fired.

It was the wrong question. A per-ordinal probe showed ADR-202 was taken by a
sibling branch and **ADR-201 was held by my branch and no other**. No collision.

A moved maximum is not a collision. And a *stable* maximum would not have proved
the absence of one either — a sibling can take an ordinal below the maximum on
an unmerged ref just as easily. Probe the ordinal you intend to occupy.

## 5. A ratchet may not be relaxed by the author whose edit tripped it

Two ratchets fired on this branch and both were right.

A rewrite of `corporate-cla.md` §0 deleted the only paragraph naming the
Cloudflare/US transfer, and a CI sentinel requires that phrase to survive. My
instinct was that the sentence had always been inapposite for a CCLA, so the
sentinel was over-broad.

The CLO refused: the old sentence was **inapposite, not under-disclosing**, and
the remedy for a scope error is to state the scope, not to delete. Decisively —
the R2 write is *deferred, not refused*, so if it lands the disclosure becomes
true again and the sentinel would be gone with nothing to notice its absence.

**The principle, stated so it outlives the instance:** a ratchet may not be
relaxed in the direction it guards on the say-so of the author whose edit
tripped it.

## 6. The third way through a drift ratchet

The mirror-drift gate blocked a `Last Updated` bump on three published notices,
because those lines carry ~30 kB of pre-existing canonical/mirror divergence and
it reports `CONTENT CHANGED: a line that was already drifting was edited in
place`. The two obvious paths were an out-of-scope 30 kB resync or an override.

There is a third. The gate compares a **sequence of drift lines** and requires
HEAD's to be a subsequence of the baseline's. A line added *identically to both
surfaces* is paired, contributes no entry to that sequence, and passes.

So the amendment ships as a new `**Amended:**` line rather than an edit to the
dated one — which also touches not one byte of the audit trail, making it
strictly better than the in-place bump that was blocked.

**Do not conclude "blocked" from two failed approaches.** Read what the gate
actually compares. And run it before *and* after: a reasoned pass is not a pass.

## 7. Stated reasons rot faster than conclusions

Two reasons I wrote into draft issue bodies were simply false, and review caught
both:

- "a different instrument with its own custodian" — both registers carry
  `custodian: clo`. The distinction did not exist.
- "Proton AG appears in no published document" — it is named in
  `gdpr-policy.md` for the exact correspondence category I claimed was missing.

Both conclusions (file the issues) were right; both *reasons* were wrong, and a
wrong reason in a filed issue sends the next reader to check something that is
not there. **Verify the reason, not just the verdict** — especially a reason
inherited from a plan, which is authoritative for intent and never for facts.

## 8. Registration is never automatic

Two suites went red for the same structural reason: adding a thing does not
enroll it in the guard that governs its class.

- A new assertion floor must be registered with AP-023's vacuity guard, or the
  closure check fails. Registering it in `PROMOTED_FILES` (rather than the
  shrink-only deferral ledger) means the guard now **mutation-tests my floor and
  requires it to fire** — strictly better than being excused.
- A new script with a not-provably-absolute operand adds a row to the
  fixture-relativity baseline. I fixed the code first and regenerated second, so
  the baseline records a real residue rather than a defect I declined to fix.

## What I would do differently

Ask of every check I write: **name a wrong implementation that still satisfies
this.** If I can, the check is a shape assertion wearing a verification's
clothes. That one question would have caught #1, #2 and #4 before they shipped.
