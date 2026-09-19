# Decision challenges — feat-one-shot-8288-reproduce-bug-red-loop

Persisted by `soleur:plan` (headless) from the Step 4.5 advisor consult and the `soleur:plan-review` panel, per ADR-084. `soleur:ship` renders these into the PR body and files the `action-required` issue. Plan: `knowledge-base/project/plans/2026-09-19-feat-reproduce-bug-red-loop-tagged-instrumentation-bite-proof-plan.md` (§Plan Review, §Plan Review Revisions).

## 1. User-Challenge — attribution scope of the emitted README (plan D8, R30)

- **Operator direction:** "Every file taking peer prose carries the MIT attribution comment from the issue verbatim."
- **Plan reading:** the `server/README.md` the scaffold emits into a founder's repo is Soleur-authored and shares no sentence with the peer file (AC2's 8-word shingle check must return 0), so the constraint does not reach it by content. The template in Soleur's distribution carries the comment; the emitter strips it per constitution line 192 (vendored credit stays in the corpus, is stripped from emitted user output; MIT is satisfied by `plugins/soleur/NOTICE`). CPO and CMO concurred.
- **Default if unanswered:** the constitution rule (no comment in the emitted README). If any peer sentence ever survives into the README, the default flips to keeping the comment.
- **Revert cost:** one inline `sed` expression in `emit_readme()`, parity row 7's expected transform, and the dogfood `apps/web-platform/server/README.md` — one commit.

## 2. Taste — refresh-mode bite-proof (plan D7, R39)

- DHH: install-time only; the config is agent-owned and parity-pinned. CTO + issue text ("every scaffold run"): keep, for config/runner drift on the real target.
- **Plan keeps it.** Cost measured in Task 0.4 (three runner passes + one worktree pair per refresh). Revert: drop one call and one test case.

## 3. Taste, applied and recorded — founder-facing wording (R31)

Two named reviewers (CPO, CMO) converged; applied because it changes no scope. Originals for a one-line revert:

| Site | Applied | Original |
|---|---|---|
| D5 digest phrase | "we cannot yet add an automatic test that keeps this bug from coming back" | "this part of your product cannot yet be locked down" |
| D1 Phase 5 opener | "Here are the 3–5 likeliest causes, ranked" | "Here are the 3–5 things I think could be causing it, ranked" |
| D1 Phase 5 column render | "what else you'd see if this is it" (agent template keeps `Discriminator`) | "Discriminator" |

## 4. Taste, resolved — the Phase 2 "captured artifact" ask (R29)

CPO flagged the ask as founder data retrieval against `reproduce-bug` line 43. Kept: it is imported peer text, bounded to after the ladder and the instrumentation route are exhausted, and the one thing instrumentation cannot capture (a founder's local device state). Ordered last with a default of not asking; headless takes the instrumentation arm.

## 5. Taste — one bullet in `ship`'s pre-PR checklist (R24)

Architecture-strategist: `ship` is the last skill to touch a tree before a PR, so the `[DEBUG-<hex4>]` shape grep belongs there too. The issue did not name `ship`; the edit is one line under the ADR-229 ratchet (7 896 B headroom measured). Revert: delete one line.

## 6. Declined user-challenges (recorded for transparency)

- DHH R40: drop Phase 4 minimise and the Phase 6 perf branch as outside B1–B7 — **declined**; both are named in the issue body (B3 "Also import minimisation", B2 "Also import the perf branch").
- Advisor: split the Phase 5 repo-global ratchets into a follow-up PR — **declined**; they are existing CI gates run locally, not gates this bundle adds.
