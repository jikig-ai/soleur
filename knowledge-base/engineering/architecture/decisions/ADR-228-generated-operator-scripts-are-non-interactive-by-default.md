# ADR-228: Generated operator scripts are non-interactive by default

- **Date:** 2026-09-18

## Status

Accepted.

## Context

Soleur has two hard rules that mandate a runnable artifact for a multi-step
operator procedure, and neither has ever had an implementation:

- `hr-multi-step-post-merge-bootstrap-script` mandates a `<feature>/bootstrap.sh`.
- `hr-ship-message-no-operator-checklist` mandates an `auto_command:` block.

Measured on 2026-09-18: both greps return **zero** across `plugins/soleur/`. The
machinery that does exist is an *accounting* system —
`wg-block-pr-ready-on-undeferred-operator-steps` blocks a PR whose body declares
an operator step without a tracked automation-gap issue, and `operator-digest`
harvests `action-required` issues weekly. Every part of it answers *"has this
step been deferred correctly?"*; none answers *"can the founder perform it?"*
`ship/SKILL.md` already concedes that **a PR body is not an operator-visible
surface**.

Meanwhile four `provision-*` scripts each hand-roll the same
`read -p "… Type 'yes'"` prompt, and `provision-hetzner.sh` prints a numbered
`echo` walkthrough with no URL opening, no progress counter and no idempotent
re-run.

The peer library `mattpocock/skills` (MIT) supplies the missing half as a
*wizard*: a staged bash script that opens each URL, says what to click, captures
values, writes them where they belong, and confirms before anything
irreversible.

ADR-178 already decided artifact placement and move-not-duplicate; restating it
would be redundant. The ADR-worthy decision is the **generated-artifact
contract** — a cross-cutting invariant with no single-file trigger, which is
what `cq-agents-md-tier-gate` calls ADR-eligible.

**Ordinal.** The plan proposed ADR-226. Measured across every `origin/*` ref,
`origin/main` tops out at ADR-224 and **ADR-225 is claimed three times** — by
`feat-one-shot-adr142-inngest-aof-luks-bluegreen`,
`feat-pluggable-web-agent-engines` and `feat-workflow-fsm-remediation`, with
three different titles. Whichever merge second and third must renumber to 226
and 227, so 225, 226 and 227 are all spoken for. This ADR therefore takes
**228**, the first ordinal free under every resolution (an earlier draft took
227 against a two-claimant count; the third claimant appeared before merge).
That is a measurement, not a reservation: re-derive immediately before merge,
and when renumbering, sweep the whole feature's artifact set for the old
ordinal in the same edit.

## Decision

Seven points, each of which a generated operator script must satisfy.

1. **The generated script SOURCES the shared library; it never inlines it.**
   One distribution mode, not two.

2. **Non-interactive is the default, not a flag.** Every class-1 (ladder value)
   and class-3 (out-of-band barrier) prompt has a named skip variable, so a run
   is expressible with no TTY up to the first destructive-write acknowledgement
   — which by point 3 has no skip variable, so a *complete* unattended run is
   impossible by design and the script says so (point 4) rather than hanging.

3. **The destructive-write acknowledgement takes NO skip variable.** It is the
   one prompt that cannot be pre-answered. A skip variable there would let
   automation acknowledge a billable resource create or an irreversible delete.

4. **No TTY plus an unset skip variable is a refusal, not a hang.** The script
   emits `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` and exits **64** *before* reading,
   naming the variable that would have satisfied it. Every refusal is the
   stdout marker **plus one plain sentence** for the founder, and on a hosted
   agent surface (a cloud session, a CI step) those markers are the only
   durable signal besides the ledger — stdout, never stderr, which agent
   runtimes swallow.

5. **A missing library is a hard exit** (`SOLEUR_BOOTSTRAP_LIB_MISSING`), never a
   degrade-to-stubs. A sourced library that silently no-ops turns every
   downstream guard vacuous.

6. **The run ledger records stage names and outcomes, never values.** One JSON
   line per stage, before and after.

7. **Writes are least-privilege by construction:** `umask 077` inside the
   library; `chmod 600` lands *after* the `mv`, never before, because `mv`
   replaces the inode and its mode; and the `.env` upsert matches on an **exact
   key**, so an upsert of `K` can never remove a different key that merely starts
   with `K`.

## Alternatives considered

**A. Inline the library under an immutable `STAGES` marker (the upstream
shape).** Rejected. A sourced library sets no shell options and carries no
prologue; an inlined region must open with `set -euo pipefail` and the xtrace
prologue above any command. The two regions differ in their first lines by
construction, so no byte-identity guard can hold over both — and a guard over
every generated copy would have to walk every founder's repository to see its
population. Sourcing keeps the consistency invariant the marker
existed to buy (one library file; the skill authors only stages; never
hand-edit it) while deleting the drift class rather than policing it with a
guard that cannot see its own population. It also removes three mutually
contradictory rules from the contract a future author must obey.

**B. Interactive by default with an opt-in `--yes`.** Rejected. It inverts the
failure mode: the default path blocks forever in CI, in a cron, and in a cloud
session, and the failure presents as a hang rather than a message. Point 4 makes
the same situation self-describing.

**C. No run ledger.** Rejected. Without it, "did stage 4 run?" is answerable only
by re-running the script, which for a provisioning wizard means re-doing the
side effects.

**D. Keep the source's prefix-match `.env` upsert (`grep -v '^PREFIX_'`).**
Rejected. It is correct only for a fixed block of keys sharing one prefix;
generalised to arbitrary keys it silently deletes siblings. Three of the four
sibling scripts in this repo already do exact-key matching via a trailing `=`;
the library adopts the majority shape.

**E. Let a missing library degrade to stub functions.** Rejected — it is the
fail-open twin of point 5. A degraded run would print stage banners and write
nothing, which is indistinguishable from success in the ledger and on stdout.

## Consequences

- The two hard rules above become implementable rather than aspirational, and
  each now names `soleur:operator-bootstrap` as the skill that delivers them.
- `provision-hetzner.sh` is the proving consumer; its pre-refactor `--dry-run`
  stdout is pinned byte-for-byte by
  `plugins/soleur/skills/provision-hetzner/test/provision-hetzner-characterization.test.sh`,
  so the refactor is demonstrated behaviour-preserving rather than asserted to
  be. The other three `provision-*` scripts are deliberately left for a
  follow-up: they ship with their own refactors.
- A generated script lives at `knowledge-base/project/specs/feat-<name>/bootstrap.sh`
  — the rule's own `<feature>/` prefix, and tracked, so it survives `ship`
  reaping the worktree and the follow-through issue's `auto_command:` keeps
  pointing at a file that exists. It may be deleted once that issue closes.

## Attribution

The wizard architecture is adapted from `mattpocock/skills`
(`skills/engineering/wizard/`, MIT, Copyright (c) 2026 Matt Pocock). The Soleur
implementation is an extraction rather than a port: five of the six library
primitives already existed in this repository. See `plugins/soleur/NOTICE`.
