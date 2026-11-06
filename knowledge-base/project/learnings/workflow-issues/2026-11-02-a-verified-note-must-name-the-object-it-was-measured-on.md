# Learning: a "verified" note must name the object it was measured on

## Problem

A runbook sentence said the Better Stack write token's scope on
`POST /api/v2/incidents/<id>/resolve` was UNVERIFIED. It had since been
exercised (HTTP 200, `resolved_at` 2026-11-02T22:32:29Z, recorded in a comment
on the issue for the inngest flip-silent alert). The replacement note carried
the status code and timestamp and cited the comment, but never said which
incident the call ran on. It sat directly under a paragraph naming two other
incidents, so a reader could attach the timestamp to those and skip a resolve
that was still needed. The planning pass, the implementation and the plan's
own acceptance greps all passed; the four-seat review panel found it
independently (a P2, one structural cause).

## Solution

Name the object the measurement was taken on and say what it was not
("HTTP 200 on incident `1045365287`, not one of the two above"). Say
"was exercised on" for one observed call instead of "works on", and cite the
evidence comment by its opening words plus a timestamp, not by "the 22:32
comment".

## Key Insight

A correction that replaces "unverified" with "verified" changes what a
paragraph is *about*, and the evidence usually belongs to a different object
than the paragraph's subject. Before writing a measured fact into prose, ask
"which object was this measured on, and could the reader attach it to a
neighbour?" Acceptance checks that grep for the new phrase pass while this
reading error is live, because the tokens are all present.

## Session Errors

1. **Verified note did not name the incident it was measured on** — Recovery:
   named it in `a1f55e6889`. **Prevention:** when a plan prescribes paste-ready
   "verified" prose, add an AC that the note names the object measured and
   states what it was not.
2. **Plan named a lint command that does not exist locally**
   (`npx markdownlint-cli2`; the repo pins `scripts/markdown-lint.sh`) —
   Recovery: used the wrapper. **Prevention:** plans cite the repo's own lint
   wrapper, read from `lefthook.yml`, not a generic tool name.
3. **Ratchet lane red from a host condition** (`$HOME` is a git repo; #10233) —
   Recovery: confirmed pre-existing from logs dated before this branch.
   **Prevention:** none new; tracked in #10233.
4. **Closing line promised a next step instead of taking it (Stop hook)** —
   Recovery: ended with a `Paused:` line naming the wait. **Prevention:** end a
   waiting turn with `Paused: <what>` rather than a first-person commitment.
5. **A compound `cd` left the shell inside `.git/ratchet-lane`** — Recovery:
   returned to the worktree with absolute paths. **Prevention:** read logs by
   absolute path; never `cd` into a log directory.
6. **AC4 checked two-dot after `main` moved** — Recovery: re-ran three-dot as
   the AC specifies. **Prevention:** the AC's own command is the contract.

## Tags
category: workflow-issues
module: runbooks / knowledge-base
