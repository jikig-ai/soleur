---
title: A security-gate detector nearly shipped the false-green it was built to prevent — three times
date: 2026-07-24
tags: [security, gates, testing, mutation-testing, encryption, false-open]
category: security-issues
issue: 6588
pr: 6885
---

# A security-gate detector nearly shipped the false-green it was built to prevent

Building the encryption-posture Layer A detector (`scripts/lint-encryption-posture.py`, ADR-140) —
the mechanical check meant to stop a store being provisioned plaintext while docs claim encryption —
the detector itself reproduced the **claim-vs-reality false-green** it exists to catch, in three
distinct ways. Each was invisible to the obvious verification and caught only by a stricter one.

## The three fail-opens

1. **Name-similarity join would PASS the incident volume itself.** The first spec resolved a
   `mechanism: luks` row by matching the cited mapper against *any* LUKS apparatus in the tree. The
   repo has `hcloud_volume.workspaces` (plaintext, the incident volume) beside
   `hcloud_volume.workspaces_luks` (encrypted, mapper `workspaces`). A `luks` row on the PLAINTEXT
   volume citing its encrypted sibling's mapper would PASS — certifying the exact volume the feature
   exists to catch. Fix: resolve ONLY via an explicit `device_binding` (the volume's
   `hcloud_volume_attachment` must reference the cited volume, with co-located key resources) — never
   string similarity. This was caught by the **7-agent plan review**, before a line was written.

2. **A parse error silently dropped the whole file → apparatus vanished → plaintext would PASS.**
   The real `workspaces-cutover.sh` `luksOpen` line ends in a shell line-continuation `\`.
   `shlex.split` raised `ValueError` on it, the `except` `continue`d the whole file, and the LUKS
   apparatus disappeared from the index — so a genuinely-encrypted volume FAILed, and the failure
   mode class (silent-drop-on-parse-error) is a fail-open for any volume whose apparatus lives in a
   file with one unparseable line. Caught only by **calibrating against the two REAL LUKS volumes
   with a real seeded ledger** (AC33) — the synthetic fixtures used clean single-line `luksOpen`s and
   never hit it.

3. **R5 (ledger↔legal join) failed open on an unresolvable anchor.** `resolve_disclosed_as()`
   returns `None` for a moved/bogus `docs/legal` anchor; the check was `if region and <asserts
   encryption>: FAIL`, so `region is None` short-circuited to a **silent pass**. A
   plaintext-exception could evade the legal-doc join by pointing `disclosed_as` at a non-resolving
   anchor. Fix: fail CLOSED on an unresolvable non-`not-publicly-claimed` disclosure. Caught by a
   **focused adversarial security review** attacking specifically for fail-open (it found it, then
   the agent stalled on a watchdog — one real finding is still worth the run).

## The rule

A security gate is a claim about reality; **its own verification must be held to the standard it
enforces.** Three things that a naive build treats as "done" but are not proof for a gate:

- **Synthetic fixtures do not calibrate a real-state detector.** Add a fixture that IS the real
  artifact the gate runs against (here: the two genuinely-encrypted volumes, real ledger). The
  false-PASS lives in the gap between the synthetic shape and the real one (the line-continuation).
- **A self-graded mutation battery is not proof.** The build reported "all MB green" while the
  device_binding join and the R5 anchor were both still fail-open. Independently re-mutate the
  load-bearing guard yourself (neuter the span, confirm the suite reds) — do not trust the harness
  that grades itself. (Compounds `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`.)
- **Every `except`/`None`/short-circuit in a gate is a fail-open until proven otherwise.** Grep the
  detector for `except`, `return None`, `if x and`, `continue` — each is a place a violation passes
  silently. A gate must fail CLOSED on every indeterminate outcome, including "I could not parse /
  resolve / measure this."

## Also

- The gate working correctly LOOKS like a failure: on first real sweep it FAILed on 8 resource
  types the `non_store_types` seed missed. That is the fail-closed-on-unknown partition doing its job
  — seed the complete inventory, don't weaken the partition.
- Ship the mechanical check advisory first (measure-then-arm); promote to a required check
  (blast-radius: every PR) only after N green runs. Deferred to #6901.
