---
title: "The design pass deleted the mechanism the panel would have reviewed, and my own fix created the next P1"
date: 2026-09-18
category: workflow-patterns
module: review, operator-bootstrap
issue: 8287
pr: 8297
tags: [review, design-validity, guard-vacuity, coverage-consult, locale, second-order-effects]
---

# The design pass deleted the mechanism the panel would have reviewed

## Problem

PR #8297 shipped a shared bash library, a generator skill, a refactored proving consumer and
two guard suites reporting 55/0 and 18/0. Every gate was green. The property the whole PR
existed to buy — *an unattended run cannot create a billable resource* — was asserted by
nothing that could fail.

## What the instruments found, in the order they ran

| Instrument | Yield |
|---|---|
| Design-validity pass (2 lenses, before the panel) | Deleted a whole mechanism; found the P1 the founder journey dies on |
| 9-seat panel | 5 P1 / 22 P2, incl. 3 vacuous guards no gate could see |
| Coverage consult (1 question) | 3 classes all nine lenses missed, 2 verified by probe |
| QA end-to-end | 3 plan scenarios describing controls that no longer exist |

No instrument dominated. The panel could not have found the locale class; the consult could
not have found the vacuous guards.

## Key insights

### 1. Run the design pass BEFORE the panel, and let it delete

Two lenses cut the entire resume mechanism (`verify-bootstrap-run.sh`, `stage_should_run`,
`START_STAGE`) because the per-stage "already satisfied?" precondition the skill already
mandates **is** resume — and the proving consumer never called the deleted code, so the
verifier's printed remedy was false for the only real script. Had the panel run first, nine
seats would have reviewed machinery that was about to be removed.

### 2. A correct fix creates the next P1, and the second-order effect needs its own guard

The design pass correctly moved the generated `bootstrap.sh` from a gitignored directory to a
tracked one, so it survives ship's worktree reaping. That put its `.env` — and the `mktemp`
sibling `.env.XXXXXX` — into a directory the ship flow commits. Three independent seats
reached "founder pushes a live token."

**The relocation was right. Its consequence needed a `git check-ignore` probe before the first
write.** After any fix that MOVES an artifact, ask what else lives at the destination's
lifecycle: who commits it, who reaps it, who scans it.

### 3. A guard pins a spelling when the observation instrument already exists

The suite had built an argv-logging `gh` stub and never drove the secret helper through it. A
pty was on the host and no fixture ever typed `no`. Measured:

- delete the billable ack from the consumer -> both suites 55/0 and 18/0 **green**
- replace the ack's `yes` check with `:` -> 55/0 **green**

The property was asserted about the library helper and never about the call site fronting the
create. **Litmus: if the suite already built an instrument that can OBSERVE the property, a
`grep` for its spelling is a choice, and the wrong one.**

### 4. Three counters where one was needed — reproduced while citing the rule against it

Both bash suites, including the characterization suite written earlier in the same session, had
`fail()` incrementing `fails` AND `FAIL_COUNT`, with the ADR-193 instrument self-test reading
`FAIL_COUNT` and the verdict reading `fails`. Drop one increment: the suite prints `[FAIL]`
lines and reports `0 failed`, exit 0.

Knowing the class does not prevent it. The mechanical form is: **the self-test, the
anti-vacuity floor and the verdict must all read the same variable**, and a known-negative must
drive each assertion helper in both directions.

### 5. The convention that makes instruments deterministic decoupled them from production

`grep` without `-a` applies its binary-file heuristic to `.env`. Measured:

- under a UTF-8 locale, one cp1252 byte silently drops a line, rc=0
- a NUL byte anywhere wipes **every** pre-existing key under both locales, rc=0, ledger records success

Nine seats missed it because **every suite pins `export LC_ALL=C`** — the pin this repo adopted
to make instruments deterministic is exactly what made them blind to the founder's locale.

Ask of any instrument convention: *what does pinning this hide?*

### 6. An API gate can admit the only incompatibility that can occur

`[[ ${SOLEUR_OP_LIB_API:-0} -ge 1 ]]`. The library auto-updates with the plugin; the generated
script is frozen in the founder's repo. So "library newer than script" is the ONLY
incompatibility reachable — and `-ge` admits it. Measured: a bumped-and-breaking library passes
the gate, writes two ledger lines, then dies `command not found` with no marker.

**For a version gate, name which side moves. If only one side moves, `-ge` is backwards.**

### 7. A stale test scenario is worse than a missing one

Three of twelve scenarios named controls the review round had deleted, and one asserted
behaviour the shipped design contradicts (`T1` "exits 0" vs the class-2 ack having no skip
variable by design). A missing scenario is a visible gap; a stale one reads as coverage. QA is
the last phase that reads the plan whole while there is still time.

## Session Errors

1. **`shellcheck` misread as available** — a mise shim with no version set resolves on PATH but cannot execute. **Prevention:** probe with `<tool> --version`, never `command -v`.
2. **ADR ordinal went stale mid-session** — two claimants became three. **Prevention:** re-derive across all `origin/*` refs immediately before merge, not at Phase 0.
3. **`decision-challenges.md` not updated by two later reconciliations** — it contradicted the plan body and I briefly read the body as authoritative. **Prevention:** when a plan carries a supersession block, check the artifact's last-touching commit before trusting either.
4. **Over-claimed a naming convention** — "all 99 skills use `<noun>-<verb>`" is false. **Prevention:** a claim quantified over a corpus needs the command that measures it, in the same edit.
5. **`prod-data` matched `PROD_RE`** — would have armed the incident-PIR gate on every PR declaring that blast radius. **Prevention:** before adding an enum value consumed by a gate, grep the gate's regex against the literal.
6. **A fix created a P1** — the tracked-home relocation exposed `.env`. **Prevention:** see insight 2.
7. **Reproduced the counter-split vacuity class.** **Prevention:** see insight 4.
8. **`git status --short --cached`** — no such flag; the error text tripped my own monitor's `error:` grep into a false positive. **Prevention:** a monitor filter must not match the noise of the command it monitors.
9. **`rm -rf "$SB"` blocked twice** — the protected-path guard reads the unexpanded command text, so a variable path resolves as empty. **Prevention:** pass literal paths to destructive commands in guarded environments. The guard is correct; the invocation was wrong.
10. **A commit queued 13 minutes on the advisory lock, indistinguishable from a hang.** **Prevention:** see the `work/SKILL.md` bullet added by this session.
11. **A fix agent misreported a "second writer"** — its own lefthook-delayed commit. **Prevention:** verify authorship and timestamps before accepting a contamination claim; `git log --format='%h %an %cI'`.
12. **Two fan-out agents ended on a status line instead of their deliverable.** **Prevention:** put "your final assistant message IS the deliverable" in the SPAWN prompt, not only on resume.
13. **Three plan Test Scenarios went stale.** **Prevention:** see insight 7.

## Related

- ADR-228 — the generated-artifact contract this PR establishes
- `2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md` — sibling: a stub that put the seam above the thing under test
- `2026-08-19-my-battery-reverted-the-fix-it-was-testing.md` — sibling: instrument verification before reading a verdict
