# Learning: a diagnostic that can go blind has to say so, and I wrote two claims the tree refutes

PR #10976 (refs #10455, #10548). A server-side diagnostic for the Claude CLI reply "Not logged in · Please run /login":
one routed Sentry event with ten closed-enum tags, observing both runners. It is not the fix.

## Problem

A 13-seat report-only panel plus a 9-seat fix round reviewed the diagnostic. Nothing was P1 from the agent seats, but the
fix commits themselves introduced three defects that a later round found, and two of my own prose claims were false:

1. **A silent blind spot in the diagnostic.** The tap that observes the cc runner's stream returned the query untouched when
   it could not install itself (non-function or non-configurable iterator, hostile object). After an SDK change the
   diagnostic would stop observing one runner while the Sentry rule stayed quiet, which reads as "no failures". The first
   round had already made swallowed faults visible in the probe, and still missed the install path.
2. **A release that credited the wrong thing.** `release()` debited "the current window" and deleted the key
   unconditionally. A failed emit after a window rollover, a clock step back to an equal start value, or a newer claim for
   the same key made it debit or erase something it did not own.
3. **Guards narrower than the property they name.** The contract test walked only `server/` for the literal
   `feature: "agent-auth"`; the canary compared one field of one scope. A `feature: SOME_CONST`, a quoted key, or an emit
   from `app/` or `lib/` passed, and `getCurrentScope().setUser(...)` leaked past a green canary.
4. **Two sentences I wrote were false.** (a) The README said the SDK "documents only four `cli_key_source` values; the others
   are undocumented", read through `cut -c1-300` on `sdk.d.ts`; the cut hid "legacy members that current CLIs never emit".
   (b) The removal checklist said to delete the Sentry rule and apply first, then remove the `alert-reference.json` entry;
   `scripts/sentry-alert-reference-gate.sh` requires both in one PR (plus `[ack-destroy]`).

## Solution

- The tap now warns once, with a constant text, for each install failure; the runners' probe-construction fallback warns once
  per process; the matcher's catch warns once. The warn texts are pinned as exact strings through the real logger path.
- `claim()` returns `{ window, expiry }` (the window OBJECT, not its start value); `release()` credits that object and erases
  only the entry whose expiry it wrote. An event already handed to the sinks is never re-emitted if the scope machinery throws
  afterwards (`emitted` flag).
- Guard 1 walks `server/`, `lib/`, `app/` (`.ts/.tsx/.mts/.js/.jsx/.mjs/.cjs`) and counts the QUOTED feature token anywhere, as
  well as the op token. Guard 2 clears the whole cloned isolation scope and observes user, breadcrumbs, tags, extra and
  contexts of both scopes at capture time, with a positive control for the derived-form detector on a sink outside the
  exact-shape check.
- The README is the single decode table; the `.tf` points to it; contract-test rows pin that the README names every payload
  key, `cli_key_source` value and `match_kind`, and that the checklist lives where both documents say.
- 45 mutants of the new guards were run in a scratch sandbox across the two rounds (control green first, every mutation
  asserted to land); all caught except one EQUIVALENT mutant, whose redundant check was deleted.

## Key Insight

- **For a diagnostic, "it printed nothing" has three meanings: healthy, blind, or suppressed. Every path that can make it
  blind must emit a distinct, constant, payload-free signal, and the docs must list those signals next to "silence is not
  proof of health".** Enumerate the install path, the construction path and the classification path, not only the
  observation path.
- **A release must give back exactly what its claim took, identified by object identity and by the value the claim wrote,
  never by "the current one" or by a number that can repeat.** The defect class is "an undo keyed on something that can
  change under it".
- **A seat's remediation suggestion is a claim, like any other.** The removal order came from a review seat and entered the
  checklist without anyone opening the gate script that decides it; the same seat later caught it. Before writing a
  procedure into a document, read the gate that enforces it.
- **Do not assert what a doc does NOT say from a truncated read.** `cut -c1-300` turns an absence into a false negative.
  Read the whole sentence before writing "undocumented", "only", or "never".
- **A wrong finding is also possible and cheap to refute.** The history seat said value 1441 was free; one `git show` of
  the file it cited showed it taken. Rejecting it with the command kept a false fix out.

## Session Errors

1. **Worktree directory removed between turns** — Recovery: `git worktree add` on the existing branch (clean and pushed, so
   nothing lost), `npm ci`. Prevention: keep every working commit pushed before spawning long-running seats; the recovery
   recipe is in `session-state.md`. Cause not identified; this is the second time in this pipeline.
2. **`sleep` followed by a read was blocked by a hook** — Recovery: waited for the background notification. Prevention: wait
   with the Monitor tool or an until-loop (already the rule), never a foreground sleep.
3. **README claim about the SDK's documented `cli_key_source` values made from a `cut`-truncated read** — Recovery: four seats
   falsified it; rewrote the rows from the full sentence. Prevention: read a doc line in full before asserting what it omits
   (routed to the review fix-round reference).
4. **Removal-checklist order taken from a seat's suggestion without reading the gate** — Recovery: corrected after two seats
   showed `plan_pr` requires one PR. Prevention: treat a seat's remediation advice as a claim and read the enforcing script
   before writing the procedure (routed to the same reference).
5. **A scripted replace aborted on a line-wrap mismatch** — Recovery: re-ran with the exact text (nothing had been written).
   Prevention: edit by slicing between two unique anchors for a multi-line block.
6. **A mock factory did not expose `getCurrentScope`** — the observation silently returned nothing until the factory named it.
   Recovery: added the named re-export. Prevention: the file's own comment already said to name every function used; check
   it when adding a new SDK call to a test.
7. **Ruling gate failed on a table without its header** — Recovery: wrote the review dispositions as prose, not as `technical`
   rows. Prevention: a `technical` row needs a `Ruled by CTO|CLO agent, <date>:` cell; a note is not a ruling.
8. **tsc failure on a new mock's typing found only by the final gate run** — Recovery: cast through `unknown`. Prevention:
   run `tsc --noEmit` after any test edit, not only vitest (the combined-tree gate did catch it).

## Tags
category: logic-errors
module: apps/web-platform/server/agent-auth-failure
