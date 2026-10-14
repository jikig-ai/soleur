# Decision Challenges — feat-one-shot-8054-execute-dark-host-registry-gate

Recorded at plan-review (2026-09-11) per `plan-review/SKILL.md` classifier routing. The pipeline
ran headless under `/soleur:one-shot`, so Taste and User-Challenge findings are persisted here for
`ship` Phase 6 to render into the PR body, rather than paused on. Mechanical findings were applied
directly and are listed in the plan's `## Domain Review` → Plan Review Panel.

## T1 — Keep any freshness bridge at all? (Taste — not adopted)

**Who:** DHH (P0), code-simplicity-reviewer (CUT).
**Claim:** the probe row's own `cutover_flag`, `http_code`, `server_active`, `host_role` fully
establish "dark and not carrying a registry"; a second read for freshness is machinery defending
against imaginary drift. Cut it and ship the five-conjunct row-internal check alone.
**Decision taken:** keep the freshness bridge (D2b′), redesigned from the flip-guard `BLOCK:`
stream (which every reviewer agreed to cut) onto the flip FSM heartbeat, because the probe row is
≤90 min old, the heartbeat proves the flag was outside the arm set ~1 min ago from the component
that owns it, it is read by a function the script already has, and it was measured present
(500 rows/24 h, `_BOOT_ID`-joined) before adoption.
**Why this is Taste, not Mechanical:** both designs are correct against the Property List; they
differ on how much staleness a P0 pre-flip gate should tolerate. Architecture-strategist and CTO
took the opposite view from DHH/simplicity. The operator may reasonably prefer the smaller design.
**Cost of the road taken:** one extra Better Stack read (~1 s), three predicates (E13), two tokens
(`fsm_silent`, `fsm_unreadable`), risk R1.

## T2 — The `::warning::` on the reachable-empty arm (Taste — kept)

**Who:** code-simplicity-reviewer (CUT: out of scope by the plan's own Non-Goals; it edits an arm
the plan says it does not re-decide). Against: CPO condition 4 (keep — a 200 at this step is now
out of sequence and the founder should see that), architecture-strategist 13 (defensible; name
#8072 in it).
**Decision taken:** kept, one line, emitted after the `pre-flight clear` notice so AC7's
decision-logic diff is unaffected, naming #8072.
**Why Taste:** it is the founder's only view of an out-of-sequence host versus one more line in an
arm the plan otherwise leaves alone. Either is defensible.

## T3 — Plan-document ceremony (Taste — not actionable in this PR)

**Who:** DHH (P2).
**Claim:** the `## Hypotheses` L3→L7 walk (25 lines opting out of firewall/DNS for a service that
said "I refused to start" in plain text) and the 13-row premise table are why an eleven-predicate
bash function needs a 900-line plan.
**Decision taken:** both stay. The walk is mandated by the plan skill's network-outage checklist
whenever `unreachable` appears in the brief; the premise table is the record of the four
corrections that changed the design (premises 8–11, 13). The general point — that the plan skill's
mandated sections can outweigh the change — is real and belongs to the skill, not this PR.
