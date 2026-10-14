# Decision Challenges — feat-one-shot-7471-plugin-delivery-path

Persisted because this plan ran headless (a `Task` subagent invoked with a plan-file-path
argument). Per ADR-084, a challenge to the operator's **stated direction** is never auto-applied;
`ship` Phase 6 renders this file into the PR body and files it as an `action-required` issue.

---

## UC-1 — Ship the dedicated marketplace source now, rather than deferring it

**Class:** User-Challenge (challenges the direction stated in issue #7471 and adopted by this
plan). Raised at plan Step 4.5, which is a **both-signals** gate — the scoped strong-model
consult and the session model agree, which is the condition that makes this a challenge rather
than advice.

**The operator's stated direction (the default, and what ships absent a decision):** issue #7471
asks to "make marketplace refresh viable for a repo this size (shallow/partial clone or a raised
timeout default)". This plan implements the only in-repo lever — a persistent timeout setting,
documented — and defers the structural fix (publishing a small dedicated marketplace source whose
plugin entry uses `{"source":"git-subdir","url":"…/soleur.git","path":"plugins/soleur",…}`) to a
milestone-targeted follow-up issue.

**What the challenge says:** ship the marketplace source in this PR instead.

**Why, from three independent reviewers:**

1. **The deferral's stated reason does not describe the proposed change.** The plan deferred
   option F as "a breaking change to the documented install path for every existing install".
   That is true only if `jikig-ai/soleur` is *replaced* as the marketplace. CTO review raised the
   **additive** shape — a second ~50 KB repo alongside the existing one. Existing installs keep
   working; new installs clone 50 KB instead of 181 MiB. The cost is a new repo and a plugin-ID
   change (`soleur@soleur-marketplace`), not breakage. The deferral was argued against a shape
   nobody proposed.
2. **Phases 2 and 4 are exactly the artifacts a later marketplace change rewrites.** This plan
   reconciles five governance sites (including ADR-178's hard-coded cache path), writes a new
   ADR, amends two more, and models the installed-user delivery path in C4 **for the first time**.
   Every one of those describes the current delivery shape. Landing them now and changing the
   delivery shape later means writing them twice. If the deferral genuinely holds, the correct
   response is to narrow Phases 2 and 4 to statements that stay true under *either* shape — which
   is itself a material change to this plan.
3. **The compliance findings are gate-shaped, not follow-up-shaped.** The GDPR gate returned two
   Important findings that attach specifically to the whole-repo clone: it industrialises an
   Art. 17 erasure impossibility that `article-30-register.md` PA-32 §(f) already records, and it
   fails Art. 5(1)(c)/Art. 25(2) minimisation by delivering ~93% non-product files — including the
   Art. 30 register itself and 41 counsel-review memoranda — to every installer. Options that
   narrow the payload retire those findings; the stopgap-only path preserves them. An unresolved
   Art. 30 finding on a *shipping* delivery path is not obviously deferrable.

**The case for keeping the operator's direction (why this is a genuine choice, not a correction):**
CPO review accepted the architectural deferral explicitly, on the grounds that changing the
distribution surface earns a design pass and should not be rushed into a bug-fix PR. The
version-key deletion is small, measured, and independently valuable; coupling it to a new
distribution surface enlarges the blast radius of the one change that is currently well-evidenced.
Beta users = 1, so the cohort-scale argument is prospective, not present.

**Recommended framing for the decision:** the question is not "defer or not" but "does this PR
land Phases 2 and 4 as written". Three coherent outcomes:

- **(a) Keep the deferral, narrow the records.** Ship Phase 1 + Phase 3; scope Phases 2 and 4 to
  claims that survive a delivery-shape change. Cheapest, and avoids writing the ADR twice.
- **(b) Ship the additive marketplace source in this PR.** Resolves defect 2 structurally, retires
  the compliance findings, and lets Phases 2 and 4 describe the final shape once.
- **(c) Ship as currently planned.** Accepts that ADR-183 and the C4 model will be rewritten when
  option F lands, and that the Art. 17 / Art. 25(2) findings stay live in the interim.

**Status:** RESOLVED 2026-08-11 by operator decision — **outcome (b): ship the additive marketplace
source in this PR.** The challenge is upheld; the plan's deferral of option F is withdrawn.

Consequences the plan must absorb (not optional follow-ups):

1. **The premise is still unmeasured and gates the rest.** Option (b) rests on `git-subdir` avoiding
   the whole-repo clone. That was never measured — it was task 1 of the deferred follow-up. It moves
   to the FRONT of Phase 0 as a falsification gate: if a `git-subdir` marketplace entry still clones
   181 MiB, outcome (b) does not resolve defect 2 and the run halts for a new decision rather than
   building on a false premise.
2. **Phases 2 and 4 now describe the final shape, once.** The governance reconciliation, ADR, and C4
   model target the marketplace-source delivery path — not the current one — so they are written a
   single time. ADR-178's hard-coded cache path is reconciled against the new plugin ID.
3. **The GDPR findings are retired by construction, not argued away.** A ~50 KB payload carrying only
   `plugins/soleur` no longer ships the Art. 30 register or the 41 counsel-review memoranda to every
   installer, which is what the Art. 5(1)(c) / Art. 25(2) minimisation finding turned on.
4. **New-repo creation is an outward-facing step.** Creating the marketplace repo is authorised by
   this decision, but its name and visibility are confirmed with the operator at execution time
   rather than assumed here.
5. **Additive, not a replacement.** `jikig-ai/soleur` remains a valid marketplace; existing installs
   keep working. The plugin ID changes for new installs only.

---

## UC-2 — The GDPR gate's own posture is stale, and this plan relies on its output

**Class:** User-Challenge (surfaces a pre-existing condition this plan inherits rather than a
change this plan proposes).

`/soleur:gdpr-gate` emitted `POSTURE_FAIL` when invoked here: its vendored rules are **93 days
stale** (`last-verified: 2026-05-10`), and the anti-backdating cron binding that would
independently evidence that date is **inert** (#7255 — the workflow moved to Inngest, so the
`gh run list` probe matches nothing and falls through). The date is operator-attested with no
liveness evidence behind it.

This plan quotes that gate's findings as an input to UC-1. The findings are reasoned rather than
pattern-matched, so their force does not depend on rule freshness — but the `POSTURE_FAIL` itself
is an open loop that this plan surfaces and does not close.

**Status:** unresolved — not in this plan's scope to fix; recorded so it is not lost.
