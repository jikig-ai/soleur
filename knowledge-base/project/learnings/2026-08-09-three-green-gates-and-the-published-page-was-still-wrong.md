---
title: "Three green gates and the published page was still wrong — verifying legal-corpus changes"
date: 2026-08-09
category: workflow-patterns
tags: [legal, verification, mirrors, checklists, contracts, review]
issues: [7347, 7387]
pr: 7372
---

# Three green gates and the published page was still wrong

Companion to [[2026-08-09-legal-decisions-route-to-clo-not-operator]], which covers the routing and
prohibition-sweep halves of the same session. This file is about **verification**: four ways a
legal-corpus change passed every check available to it and was still wrong.

## 1. A canonical↔mirror ORDERING change is invisible to every gate that exists

The §8.1 carve-out landed **last** on the canonical and **first** on the mirror. Same content,
different sequence — so the published page presented a reader's rights in an order the record did not.

What each gate actually compares:

| Gate | Compares | Sees an ordering change? |
|---|---|---|
| `legal-doc-consistency.test.ts` | `##`/`###` heading SEQUENCE, source vs mirror | No — prose bodies are never compared |
| `check-tc-document-sha.sh` | canonical file hash vs a committed literal | No — the mirror is not hashed (body equivalence is T&C-only) |
| `lint-encryption-posture.py` | encryption claims vs a ledger | Unrelated |

All three were green. It surfaced only because per-document normalised drift moved **58 → 60** against
the merge base.

**The reusable technique: assert drift EQUALS the baseline, not zero.** The corpus carries substantial
pre-existing divergence (56 / 58 / 63 / 18 / 2 lines, tracked separately), so a zero assertion is
unshippable and would be switched off within a day. Equality is enforceable today and ratchets down on
its own as the drift is repaid. Reuse `normalize_canonical` / `normalize_plugin` / `collapse` from
`apps/web-platform/scripts/check-tc-document-sha.sh` rather than writing a second normaliser — a second
normaliser is a second thing to drift.

Filed as gate 2 of #7387.

**Why the mirror is where this bites:** `eleventy.config.js` sets `INPUT = "plugins/soleur/docs"`, so
`docs/legal/**` is in no Eleventy input tree and is read by no route. The canonical is the source of
record and is published *nowhere*; the mirror IS the public document. Every mirror-side defect is a
defect on the only surface anyone reads.

## 2. A checklist row can assert a PROXY for the quantity it names

A row pinned "DPD scope blocks land at exactly 8" and greps `^\*\*Scope\.\*\*` — anchored at column 0,
so it counts **flush-left** blocks, not blocks. Two blocks were list-indented and invisible to it. The
`8` was an artifact of the anchor.

That mattered because the fix (moving the indented blocks flush-left) raises the count to 10 and
**fails the row** — so the checklist actively blocked the correction it existed to enforce.

This happened INSIDE the instrument built to catch exactly this class. The author (the CLO agent)
overturned its own row and **struck it in place rather than rewriting it**, on the stated ground that
a checklist which silently repairs itself teaches nothing. That disposition is worth copying.

Generalisation: for every checklist row, ask *does this grep measure the quantity the row NAMES, or a
property that happens to correlate with it today?*

## 3. The pre-edit validation that makes a checklist trustworthy

Run **every obligation row against the pre-edit tree and require it to FAIL.**

A row that passes before the work is done can never detect the work not being done. The CLO ran this
for all 37 rows and reported the two that legitimately passed (deliberate preserve-assertions, where an
original clause must survive an append) with their pairing labelled inline — so a reader can tell a
valid pre-pass from a vacuous one.

Companion rule for deletions: **assert an exact post-count, never an absence.** A `grep -c … == 0` on a
deletion is prohibition-shaped and reports an untouched file as a pass. The rows here read "exactly 8,
down from 9, with the §4.2 site specifically gone" — a count, a direction, and a positional check.

## 4. An indented paragraph is a LEGAL-EFFECT defect, not a rendering one

Under CommonMark a two-space-indented paragraph after a list item is a **continuation of that item**.
So a scope note reading "This **section** describes plugin-local processing", indented between bullets
(a) and (b), qualifies bullet (a) alone.

In `data-protection-disclosure.md` §3.1 that left limbs **(b)** and **(d)** unqualified — the two limbs
this corpus already knows to be falsified by an in-plugin script that POSTs to a Soleur-operated host
(#7375). The worst possible bullets to miss, chosen by an indentation.

The review reported it as a rendering nit. It is not: which sentences are qualified is the whole
content of a scoping clarification.

## 5. Contract shape is the lever on rework

Two implementation rounds, same corpus, same implementer class, very different outcomes:

| Round | Contract shape | Outcome |
|---|---|---|
| 1 | ten fixed STRINGS, no per-site placement | template-pasted into 9 sections that were not plugin-local; 10 P1s |
| 2 | 14 BLOCKS, each labelled target file + section + mirror yes/no | applied cleanly; deviations were contract bugs, not placement errors |

A string without a placement decision delegates the placement decision — and placement was where every
mechanically-detectable defect lived. Of the 10 P1s, 6–7 were greps; they consumed a four-agent panel,
a CLO adjudication round, and a full re-implementation.

**Reviews were not what lengthened the pipeline. Rework was.**

## Session Errors

- **Planning subagent stalled at the 600 s watchdog.** Recovery: on-disk partial-artifact check found a
  complete 62 KB plan; continued from plan-review instead of re-running planning.
  **Prevention:** bound an agent's read scope explicitly; "read all N target files, then edit" is the
  shape that stalls.
- **Implementation subagent stalled, same cause.** Recovery: resumed (not respawned — a resume keeps the
  transcript) with per-document scope and a commit after each. **Prevention:** as above; and prefer
  resume over respawn, which is already recorded in `review/SKILL.md`.
- **Misread `PUSH_RC=0`** — it was `tail`'s exit, not `git push`'s, so a non-fast-forward rejection read
  as success. **Prevention:** the repo rule already says capture `rc=$?` directly and never through a
  pipe; it applies to `git` exactly as to test runners.
- **`pkill -f 'test-all.sh'` killed my own shell (exit 144)** because the pattern appeared in the
  invoking command line. Documented in `review/SKILL.md` and hit anyway. **Prevention:** resolve PIDs by
  `/proc/<pid>/cwd` and kill by PID. The deeper lesson is that a documented trap inside an ~80-entry
  catalogue is not a gate — see #7387.
- **My implementation brief kept a site my own amendment A9 said to cut** (privacy §11 Security). The
  brief and the amendment list disagreed and nothing compared them. **Prevention:** generate the brief's
  site list FROM the amendment list rather than restating it.
- **Prohibition-only verification passed 6/6 while two binding amendments were silently dropped.**
  Covered in the companion learning; gate added to `work/SKILL.md`.
- **Escalated three legal decisions to the operator instead of the CLO.** Covered in the companion
  learning; gate added to `work/SKILL.md` and a fourth disposition to `review/SKILL.md`.
- **Over-claimed reviewing an authored sentence** — quoted it one sentence short and reported that the
  instrument hand-off had been dropped. It had not; the next sentence carried it. **Prevention:** when a
  finding turns on what a passage does or does not say, quote the passage to its paragraph boundary
  before drawing the conclusion.
- **Told the operator twice that condition C6 gated what the notice could say.** It did not — A2 did,
  and the silence would persist with C6 confirmed. **Prevention:** same class as the above; I asserted a
  causal claim I had not traced. Both instances are the repo's documented "measure, don't assert" class.
- **Introduced a canonical↔mirror ordering regression** (§1 above). Caught by drift-vs-baseline.
- **Ran the full suite three times where one was warranted.** The repo rule already says re-run only
  when inputs changed and to say which commit the green run covered. **Prevention:** derive the targeted
  set from changed paths; the derived set here was ~6 suites against 269.
- **`comm` without `LC_ALL=C`** returned "not in sorted order" and silently produced garbage output that
  looked like a result. One-off, but note that a sort-order mismatch degrades to plausible-looking
  wrong output rather than an error.
