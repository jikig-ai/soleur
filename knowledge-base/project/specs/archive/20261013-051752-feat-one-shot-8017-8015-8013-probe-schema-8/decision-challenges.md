---
title: "Decision challenges — probe_schema=8 planning"
branch: feat-one-shot-8017-8015-8013-probe-schema-8
phase: plan
---

# Decision challenges

Four reviewers ran against the plan (a strong-model scoped consult, a correctness panel, a
simplicity panel, and a flow-completeness panel). Mechanical findings were applied directly. The
entries below are the judgement calls — recorded because they are the ones a reader might have
decided differently, not because they are unresolved.

None of them challenges the operator's stated direction, which was: fix #8017 and fold #8015 and
#8013 into the same `probe_schema` bump, and do not dispatch `inngest-volume-recut`. Both held.

## Accepted against the original plan

- **No new ADR.** The plan first proposed ADR-216. The simplicity panel argued the decision content
  already has a home — ADR-199's Decision C1 names the mount pin — so the honest record is an
  amendment, and the generalisable lesson is learning-shaped rather than decision-shaped. Accepted;
  it also removes a provisional ordinal and its renumber-sweep hazard.
- **`lsblk -s` instead of a hand-rolled `/sys/block/<dm>/slaves` walk.** Same panel. Measured before
  accepting: `lsblk -s` does the device-mapper descent and the partition→parent normalisation in one
  documented flag, and it is a binary, so it stubs on `PATH` like the existing `findmnt` stub. This
  halves the fixture seams and removes the highest-risk new code.
- **The by-id reverse map stays; the alias is not composed from `lsblk`'s SERIAL.** The panel's
  further suggestion was to compose `scsi-0HC_Volume_${serial}` and drop the glob entirely. Rejected
  on measurement grounds: the serial↔volume-id identity cannot be verified before the host replace,
  whereas the by-id alias's existence is measured (cloud-init mounts from it and the live row shows
  the mount succeeded). Recorded as a follow-up if a live host ever establishes the identity.

## Kept against a reviewer's recommendation

- **`__NOMATCH__` stays a distinct sentinel** rather than reusing `__NONE__`. The two fields'
  negatives are not the same claim: one says the store is empty, the other says the mount is on
  something that is not the pinned volume, and their remedies differ. The emitter already sets the
  precedent for keeping a negative measurement distinct from an absent one. A third value,
  `__AMBIGUOUS__`, was *added* on a different reviewer's finding, converting a single-alias premise
  into a measurement.
- **The ADR-142 and runbook corrections stay in scope.** One panel argued they are unrelated
  pre-existing drift and widen a P0's blast radius. Kept: both are wrong *about the field family
  this change renumbers*, both are one-token fixes, and the runbook's wrong pin count is precisely
  what produces a partial bump. Labelled as pre-existing-gap fixes rather than folded in silently.

## Corrections the plan makes to its own earlier drafts

Recorded because each is an instance of a class this repo has paid for before, and the plan text
now names them at the point where they were wrong:

- `__NOMATCH__` was first described as "the root-disk fallback this predicate exists to catch". It
  is not: `findmnt` is called without `-T`, so a non-mountpoint yields no output and the emitter
  binds `__UNREADABLE__`. The first draft built a sentinel out of a state production cannot produce
  and then fixtured that state — the 2026-09-02 learning reproduced inside its own fix.
- The hash-tag collapse rule was first written as "collapse to the pre-colon prefix", which leaves
  a `{<ULID>}:runs:x` tag shipping the identifier verbatim.
- The `discoverability_test` command first used a bare `--grep`, which matches rows that merely
  quote the marker; the measured output carried markdown fragments where a field value should have
  ended.
- Three guards were written against a harness that, for six of fifteen rows, did not exist —
  `inngest.test.sh` has no mutation helper and the #7674 probe has no suite at all. Both are now
  deliverables.
- The plan claimed `scripts/test-all.sh` reaches the three `apps/web-platform/infra/*.test.sh`
  suites. It does not, verified with `--enumerate all`.
- Follow-through enrollment was first declared "not required" on the grounds that nothing here is
  time-gated. True, but the closing observation depends on a host replace that is not part of this
  pull request, which is a deferred closure and exactly what the sweeper exists to catch.

## Deepen-plan round (four more agents)

Four further reviewers ran against the plan after it was committed: security, observability
coverage, test design, and a mechanical verify-the-negative sweep. Findings applied. The ones a
reader would want to know about, because each changed the design rather than the prose:

- **The key-name fix was brace-aware and the property is identifier-aware.** Measured: the
  brace-free shape `estate:<ULID>:runs:1` ships the ULID through the two-segment reduction with no
  brace rule involved. The collapse-only fix would have closed #8013 for the shape the issue quoted
  and left the identical leak standing one shape over — with an acceptance criterion, derived from a
  brace corpus, passing over it. The reduction now tests segments for identifier shapes.
- **The G14 rewrite had dropped a control and could be turned into a wildcard.** The two-line
  replacement omitted the numeric validation of `expected_volume_id`, a raw dispatch string, and an
  unquoted `[[ ]]` right-hand side makes `*` match every Hetzner alias — reproduced on bash 5.3.9.
  The predicate is now five lines and each of the other four is load-bearing.
- **The closure condition was unreachable.** The delivery probe required a non-empty `registry_fns`.
  `INNGEST_DIAGNOSTIC_BOOT` is a Doppler variable, so it survives a host replace, and it is
  currently `1` — the probe would have returned TRANSIENT forever *after* the replace that delivered
  all three fixes. The gate is now `^[0-9]+$`; `0` is a measurement.
- **`Closes #` would have made every follow-through directive a permanent silent no-op**, because
  the sweeper lists `--state open`. The PR body uses `Ref`, one directive per issue body.
- **The delivery probe verified nothing about #8013** and would have auto-closed it on evidence of a
  different fix. It gained a no-identifier conjunct on `redis_key_patterns`.
- **Property P2 had no test.** A G14 written with the expected id hardcoded would have passed every
  RED row, every harness row, and the only must-PASS. A second must-PASS varying the pin was added.
- **The gate battery ran the gate more permissively than production** — `mutate()` uses a bare
  `bash -c` while the dispatch step runs `set -uo pipefail`, so `[[ "" == "" ]]` passed in the
  harness and aborted in production. Fixing the harness is now a Phase 1a task.
- **`__UNREADABLE__` was a three-way collision sold as a two-way split.** A `data_mount_base` field,
  free from the `lsblk` call already being made, separates "nothing mounted" from "resolution
  broken" from "wrong device".
- **The tag re-issue rule was keyed on the wrong signal.** The build pushes before it signs and
  mirrors, so a late failure has already published; the test is a `crane manifest` 404, not the
  run's conclusion.
- **The discoverability command was wrong in five ways** — no `doppler run`, no `-R`/`fromjson?`, no
  host isolation, `--limit` too small, and a per-field grep destroying the same-row conjunction —
  and `credentials_required` makes preflight skip it, so nothing mechanical would have caught it.
- **One claim was overstated rather than wrong:** the scope-out said the change "strictly narrows an
  existing identifier leak". It narrows one and adds another (the Hetzner volume id, same class as
  the `instance_id` already shipping). The mechanism stands; the claim was corrected.
