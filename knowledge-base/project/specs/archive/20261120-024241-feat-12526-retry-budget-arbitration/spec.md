---
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Feature: retry-budget ruling

**Vocabulary.** "Arbitration" here means the three-verb ruling (`continue`, `goto`, `fail`) on a classified budget stop. It does not mean legal dispute arbitration, the ADR-030 cross-domain priority surface, or the ADR-161 fleet-cap note. No glossary entry. The hedge is the whole fix.

## Problem Statement

ADR-268 already classifies a hard-cap crossing as `budget-capped` plus a resume prompt. One-shot then halts when a child's session state contains that marker. Nothing in a fresh context reads the attempt evidence and returns one verb the parent executes. The operator sees a stall, or a loop that cannot spend one more bounded iteration without someone raising the cap. Raising the cap inside a skill clears the latch. That is not this feature.

## Goals

- When one-shot halts on a child's `budget-capped` marker, a fresh context returns exactly one verb and the parent executes it.
- `continue` and `goto` share one consumed exemption. The latch stays set and the cap is not raised.
- `fail`, a missing ledger, an empty history, or an unparseable line leaves today's halt and writes an on-disk ledger.
- The second exhaustion is `fail` with no second spawn.
- The change stays inside Soleur's own ledger and the three outcome words.

## Non-Goals

Documented here per `wg-defer-only-after-inline-triage`. These are the same capability on surfaces the ruling excluded. No new GitHub issues.

- One-shot's own `agent_rounds` gate (step 0d), which can stop on an inherited latch before attempt history exists.
- QA's prose retry of three, then a failed step. QA has no tally gate.
- Review's prose cap of two targeted rounds. A review seat stop is in scope only after it has written the child marker the parent greps.
- `test-fix-loop`'s max-iterations path, which reverts every iteration and drops the checkpoint commits.
- A second exemption, a raised cap, or `init --max-*` as a way to continue.
- `goto` into `ship` or `merge`.
- Folding #12532 per-run forensics into this ruling. That agent must not auto-apply.
- A customer-facing product, a public claim that this ships the compared peer, or that peer's "unattended autopilot" positioning.
- Copying the peer's prompts, code, tests, fixtures, comments, schema names, file layout, decision rubric, or docs text.

## Functional Requirements

### FR1: Parent halt is the attachment

The ruling runs when one-shot is about to halt because a child's session state contains `budget-capped`. It does not run on one-shot's own `agent_rounds` stop.

### FR2: One verb

The parent accepts exactly one line from the fresh context: `continue`, `goto <phase>`, or `fail`. The parser accepts the line. Prose does not.

### FR3: continue

`continue` runs exactly one iteration of the exhausted work. `capped=` stays set. The cap is not raised. The spawn does not increment the dimension it is judging.

### FR4: goto

`goto` may name only `plan`, `work`, `review`, `qa`, or `test-fix-loop`. It must not resume `ship` or `merge`. It spends the same single exemption as `continue`.

### FR5: One exemption

`continue` and `goto` share one grant. The next exhaustion of that run is `fail`. There is no second spawn.

### FR6: fail

`fail` is today's halt plus an on-disk ledger a later reader can open. The ledger is written at the halt, in the checkout that owns the counter, and is not the exhausted session's own verdict.

### FR7: Closed failures

A missing ledger, an empty attempt history, or an unparseable line is `fail`. Empty history does not spawn.

### FR8: Review seat marker

A review seat stop is in scope only when that seat has already written the child marker the parent greps.

## Technical Requirements

### TR1: Do not lift the stop

Skills keep the bare `init` ADR-268 requires. `init --max-*` while latched is `capped-reset` and is forbidden as an implementation of `continue`. The stop hook may emit its keep-alive block for this one grant and must not emit it again. The latch, the cap, and the next `gate` stop stay in force.

### TR2: Ledger durability

The ledger write is not a last step that exhaustion can drop. It is on disk before the parent acts on the verb. It records pointers to checkpoint diffs, failure reasons, and gate outputs in Soleur's own names.

### TR3: Clean-room ceiling

Inbound material stops at the three outcome words. The prompt, the ledger schema, and the tests are written from this spec and from Soleur's tally. If someone has already read the peer's source, a different author writes the prompt. PR trailer: derived from Soleur's ledger and this functional spec; zero peer source inspected.

### TR4: No personal data

The ledger does not store personal data, a users foreign key, or customer content. If a later diff does, re-open the CLO before merge. The GDPR gate does not apply to the verb itself: it chooses a workflow phase, not a person.

### TR5: Brand-survival threshold

`single-user incident`. A wrong ruling that continues a broken loop, or that stops a fix with no readable ledger, is the incident this threshold names.
