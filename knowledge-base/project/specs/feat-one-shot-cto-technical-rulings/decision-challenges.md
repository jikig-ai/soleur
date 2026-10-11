# Decision challenges - feat-one-shot-cto-technical-rulings

Appended by plan on 2026-10-11 (headless pipeline). Each item carries the `Class:` line this feature introduces, so the
file is also the first fixture of its own schema.

## Technical rulings (decided; not for the owner)

1. **Amend the existing rule body in place rather than migrate it into the enforcer or mint a new id.**
   - Class: technical
   - Ruled by CTO agent, 2026-10-11: amend in place (about 590 bytes); the rule binds at decision time on turns that
     never enter the enforcer, and the migration candidate test fails on the citation sweep. Add a
     `[skill-enforced: ship Technical-Ruling Gate]` tag; ack wording "strictly additive".
2. **Chat-prose Stop-hook arm is cut; the pre-ask hook arm is secondary and narrow.**
   - Class: technical
   - Ruled by CTO agent, 2026-10-11: the observed carrier was an artifact pipeline, not a tool call; exact-label matching is
     brittle and the Stop hook's own record is a 13-of-15 over-block. Narrow the hook exemption to permission-seeking
     shapes. Tracked deferral with a recurrence trigger.
3. **Ship gate shape: a script plus a suite, with `Class: operator (<category>)` required.**
   - Class: technical
   - Ruled by CTO agent, 2026-10-11: parseable fields are what prose gates lose to drift; a bare `Class: operator` is
     invalid; the remedy spawns the CTO rather than only blocking.

## User-Challenge

4. **The CTO recommended citing only the choke points; the brief asked for explicit wiring in seven skills.**
   - Class: operator (scope)
   - *What you said:* "Wire it into the skills where such forks arise (at least: go, one-shot, plan, work, review, ship, brainstorm ...)".
   - *What the CTO recommends:* cite only `decision-principles.md` and `ship`, plus an inline rule in one-shot's subagent
     prompt; the other skills inherit transitively.
   - *Why:* five of the seven SKILL.md files sit within 125 bytes of a ceiling that cannot be raised in the same PR, and
     nine citations are copies that drift.
   - *What context we might be missing:* whether the owner wants the rule visible in each skill for readers, not only enforced.
   - *If we are wrong, the cost is:* if the owner wanted explicit wiring, the cut leaves skills that do not mention the rule.
   - *Plan review (2026-10-11):* the DHH-lens, Kieran-lens and CTO devex seats lean to the narrower form; the simplicity seat
     would keep the brief's list only as byte-neutral pointers.
   - *Default taken:* the brief's direction is kept as byte-neutral pointers; the CTO's form is the fallback for any file
     where Phase 1.0 cannot fund the pointer.

5. **Two plan-review seats recommend making the pre-ask hook arm its own PR by default.**
   - Class: operator (scope)
   - *What you said:* "Extend `.claude/hooks/pre-ask-technical-fork-gate.sh` (and its test file, test-first per cq-write-failing-tests-before)".
   - *What the reviewers recommend:* ship the hook arm as a separate PR (the CTO rated it secondary, and the observed
     carrier was an artifact pipeline, not a tool call, so the hook would not have fired on it).
   - *Why:* the plan crosses two of three split thresholds (about 27 files, 4 subsystem roots) and the hook is repo-local,
     so it does not protect Soleur end users.
   - *What context we might be missing:* whether the owner wants the hook change visible in this PR as the answer to the
     brief's hypothesis 2.
   - *If we are wrong, the cost is:* one extra PR cycle if the owner wanted it together, or a larger review if not.
   - *Default taken:* one PR, ordered commits, hook arm last; it splits out automatically if Phase 0 measures more than 800
     changed lines or review needs a second round.
