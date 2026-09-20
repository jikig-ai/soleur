# The no-list

Soleur says no out loud, once, and then keeps the reason where anyone can read it. This directory is
that record. Each file names one capability the product deliberately does not offer, what the founder
gets instead, and the condition under which the answer would change. Read it as a map of the edges:
the boundary is here because something better sits on the other side of it, and every entry names
that something. Nothing here is a verdict on what Soleur can build. It is a statement about what
Soleur has chosen to be.

Formally this is the **rejected-concepts record**. In conversation it is **the no-list** — the
founder's phrase, and the shorter one. It is deliberately not called a register: that word already
carries eight distinct compliance meanings in this repository, each with counsel review and an
inclusion test, and a vocabulary document cannot fix an overloaded word by overloading it again.

## What an entry is, and is not

An entry records a **concept** that was refused, not an issue that was closed and not a mechanism
that lost a design bake-off. One file per concept, and the same concept arriving three more times
appends to the one file rather than starting a fourth.

Two things an entry is never:

- **Not a record of something already built.** If a request is declined because the capability
  already exists, that is a redundancy finding, and its record is the closing comment naming where
  the implementation lives — the output of pre-check 1 below. Writing it here would seed the
  duplicate check with refusals that never happened, and every later lookup would inherit the
  mistake.
- **Not a deferral.** A capability waiting on a redesign, a dependency or a decision is still on the
  table. The roadmap holds those. An entry here is an answer, not a queue position.

## Naming

Entries are named `YYYY-MM-DD-<concept-slug>.md`. The date is the day the refusal was recorded, not
the day the request arrived. The slug is the concept in lower-case words joined by hyphens.

This is mechanical, not a matter of taste. A concept-similarity lookup walks this directory, and a
file that does not match the pattern is not an entry — which is precisely how this README stays out
of the results. Without the rule, the first lookup for any concept at all would match the convention
document it is reading and report a refusal nobody ever made.

The filename is also a claim. `2026-09-20-browser-automation.md` reads, to somebody browsing this
directory on the web, as *Soleur does not do browser automation* — regardless of how narrowly the
body is written. So the slug has to fit inside the entry's own `scope`, and a guard checks that it
does.

## The fields

Frontmatter, all required:

| Field | What it holds |
|-------|---------------|
| `aliases` | Every way the same ask actually arrives, in the words people use. This is what makes matching work on the concept rather than on the phrasing: *night theme* has to reach a dark-mode entry, and nothing but an alias list gets it there. |
| `scope` | The exact boundary of the refusal, stated narrowly, and — where a neighbouring capability does ship — naming it as implemented and not refused. A request narrower than the entry must not match it by accident. |
| `why` | The full reason, including the parts that are blunt — and **public, exactly like every other field here**. The split below is about which sentence an agent quotes back to somebody, not about which sentence is confidential: this repository is public and git keeps every version, so nothing written here is internal. Write `why` as the complete reasoning you are willing to publish. |
| `public_note` | The same decision as one sentence that is safe to say outward. An agent quotes this and never `why`. |
| `instead` | What the founder gets in place of the thing refused. An entry with nothing here is either a rare category-level never, or a mechanism refusal filed as a concept — which is a mis-keying, and the guard treats a missing `instead` as one. |
| `revisit_if` | The condition that reopens the question, written so that it can be observed rather than argued. |
| `searched` | The evidence behind `redundancy_check`. One line per query: the command, then what it returned. |
| `redundancy_check` | `not-implemented`, and only that. It asserts that the concept genuinely is absent from the product. |

Optional, and load-bearing when present:

| Field | What it holds |
|-------|---------------|
| `superseded_by` | Set when the answer changes. The entry stays as history, drops out of concept matching, and its `redundancy_check` becomes `superseded`. This is the reopen path: entries are retired, never deleted. |
| `prior_requests` | Issue numbers where the same concept arrived. |

No field names a person. Not the requester, not the decider. A role where a role is genuinely needed
(`a design-partner founder`, `counsel`), never an identity — this repository is public, and a
refusal attached to a name is a personal record published to the world for as long as git history
lasts. `requester`, `requested_by` and `implemented_at` are not optional fields that happen to be
empty; they are absent from the schema, and an entry carrying any of them is rejected outright.

### Writing `searched`

Each line is a command and its result, so that a reader can run it again and get a different answer
if the ground has moved:

```text
searched:
  - "git ls-files | grep -icE 'dark[- ]mode' -> 0"
  - "git grep -ilE 'theme[- ]switch' -- apps -> 0"
```

That re-runnability is the whole point. Inside a single commit a guard can only prove an entry is
internally consistent — that its claim matches the evidence stapled to it. Both halves live in the
same file, so a confidently wrong entry passes. What closes the gap is a reader outside the commit
running the line and seeing a number the entry does not predict.

## How a lookup works

Two checks run before anything is closed, deduplicated or recorded, and they run in this order.

1. **Is it already built?** Search the codebase for the requested behaviour by domain concept rather
   than by the words of the request, and report where you looked. The procedure is specified in
   `plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)`, which
   already carries the functional-noun re-sweep and the name-what-you-searched discipline. It is
   cited, never restated: a second copy would drift from the first, and the drifted copy is the one
   somebody would follow.
2. **Has it been refused before?** Walk this directory, match on concept and `aliases`, and skip any
   entry carrying `superseded_by`.

**Check 1 takes precedence over check 2.** If the capability turns out to exist, the entry is wrong
and the entry is what gets corrected. An existing file never outranks the running code.

**And an entry never outranks the decision it records.** An entry is *evidence that a refusal was
recorded*; it is never the refusal itself. So where an entry and a primary record disagree — a
GitHub issue's own closure, an ADR, a roadmap decision — the primary record wins and **the entry is
STALE**: correct it, or supersede it, and never argue from it. The order is running code, then the
primary record, then the entry. This matters more here than it would in a record of facts, because
an entry is the only artifact in the chain that a single commit can create and that nothing outside
this repository can contradict; a reader who treats it as the decision has skipped the two things
that actually are.

**An uncertain match fails open.** Report the candidate, name the doubt, and hand it to a human.
Silence is not a match, and a near-match is not a match.

## Advisory only

> A rejected-concepts entry may never be the sole basis for closing, labelling or auto-closing an
> issue. A prior-rejection hit is **reported to a human and escalates; it never acts.** In
> particular, `deferred-scope-out` must never be applied on the basis of a no-list hit.

This is the strictest rule here, and it is here because the path from a wrong entry to a
permanently-closed issue is already built and needs no new code:

1. A false entry lands. It is internally consistent, so the guard passes it.
2. An agent reads the hit and applies `deferred-scope-out`.
3. `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` closes the issue
   after ninety days of quiet with `state_reason: "not_planned"`, with nobody in the loop.
4. `scripts/sweep-followthroughs.sh` then declines to reopen it, because a `NOT_PLANNED` closure is
   a deliberate human wontfix and overriding one is the opposite of what that sweep is for.

Two automated hops, and the outcome is an issue closed forever and attributed to a human decision
that never happened. Three lines of policy retire the whole chain, which is cheaper than any amount
of care applied further down it.

## Writing an entry

The machine gate runs before the human gate, in that order, on purpose: there is no reason to ask a
person to confirm a record that is malformed.

1. Run both checks above. If check 1 finds an implementation, stop — this is a redundancy finding.
2. Draft the file at `knowledge-base/project/rejected/YYYY-MM-DD-<concept-slug>.md`.
3. Run `bash scripts/lint-rejected-register.sh <path>`. Fix what it names.
4. Ask for confirmation by **typing the concept**, not by typing `y`. A one-character assent to a
   permanent refusal is a reflex; spelling out `server-side browser automation` is a decision.
5. Only then write the file.

## Neighbouring records, and what is deliberately absent

The rejected-alternatives tables inside the ADRs under
`knowledge-base/engineering/architecture/decisions/` are a **sibling record that a lookup also
reads**. They hold real refusals, but of *mechanisms* — the queue that lost, the library that was
not chosen — and a mechanism refusal filed as a concept reads as a far wider no than anyone decided.
Nothing has been imported from them, and nothing should be.

Two candidates that look like obvious first entries are deliberately not here:

- **The Telegram bridge.** The roadmap records it as *"Removed in April 2026 — will redesign as
  channel connector using unified backend."* That is a deferral awaiting a redesign. Filing it as a
  refusal would end the redesign by recording an answer nobody gave.
- **The ADR rejected-alternatives tables.** See above. Cited, never copied.

Seeding the no-list with something that was never refused is the same defect as recording a built
feature: both put a decision into the record that no one made, and everything downstream treats it
as settled.
