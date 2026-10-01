---
title: A gate leg wired to a quiesced emitter reads zero forever — re-anchor evidence, never deploy into the quiesce
date: 2026-09-29
category: workflow-patterns
tags: [followthrough, soak-gate, vacuity, sentry, unreachable-emitter, zot]
issue: '#9097'
---

# Learning: a gate leg wired to a quiesced emitter reads zero forever — re-anchor evidence, never deploy into the quiesce

## Problem

`zot-soak-6122.sh` arm (b) required `MIN_SAMPLE` zot-served deploy pulls per image, including
`registry:"zot" image:"inngest"`. After the 2026-09-15 dedicated-host cutover the sole emitter
(`ci-deploy.sh deploy inngest`, sent only by a manual `deploy-inngest-image.yml` dispatch)
targets the *quiesced* web scheduler — so the count could only ever be 0 and the soak could
never PASS. The arm was not "thin"; it was structurally dead, and no amount of waiting fixes a
dead emitter.

The tempting wrong fixes both preserve the *name* while breaking the *contract*: dispatching
into the quiesced scheduler violates the architecture the cutover established (the scheduler
refuses anyway, `inngest_quiesced_deploy_refused` fires before the pull), and simply deleting
the leg removes the vacuity protection — a window with no inngest evidence would then pass
silently.

## Solution

Re-source the leg onto evidence the dedicated host already emits: the
`stage:"inngest_zot" host_name:"soleur-inngest"` boot beacon — already fetched as the
denominator count (`INNGEST_ZOT`), so the fix costs *minus one* Sentry query, not plus one:

- Arm (b) becomes two-legged: `ZOT_WEB >= MIN_SAMPLE` (unchanged) AND `INNGEST_ZOT >= 1`.
- The inngest floor is **hardcoded 1**, not `MIN_SAMPLE`: the host pulls only at boot, once per
  host-replace, so a sample-sized floor would recreate the same unreachable arm in a new shape.
- Deliberate redundancy with the denominator `INNGEST_ZOT == 0` FAIL: both removal shapes stay
  fail-closed (drop the FAIL block → the leg refuses; drop the assignment → `set -u` aborts
  exit 1). Document both shapes at the producer, and pin the surgical one with a mutant row.
- Host-pin the evidence (`host_name:"soleur-inngest"`) so a colocated web host's emit cannot
  satisfy the dedicated host's leg.
- Pin the retired operand at *both* layers: source (comment-stripped code scan, quoted AND bare
  `image:inngest` spellings) and wire (the stub's URL log on a PASS run — with a positive
  control: the run must have reached PASS and the sink must be non-empty before absence is
  evidence).

## Key Insight

- **Emit-site existence ≠ evidence reachability.** When a deploy path is quiesced or
  re-routed, every gate arm that counted its events becomes permanently unreachable even though
  the emit code still compiles. The audit question is "can anything still *send* this", not
  "does the emit site exist".
- **A denominator count is valid sample evidence when the event is once-per-lifecycle.** Per-
  image pull counts measure cadence; a boot beacon measures occurrence. Floors must match the
  quantity's cadence — reusing `MIN_SAMPLE` across both is a category error.
- **Absence assertions need positive controls.** `grep -q absent` on a sink from a run that
  died before emitting is vacuous green; assert the run's verdict and a non-empty sink first.
- **Test file:** `bash scripts/followthroughs/zot-soak-6122.test.sh` — rows NB1–NB8b; floor
  `SOAK_MIN_PASSES` raised in the same edit (77→81).

## Session Errors

1. **Nested parameter expansion `bad substitution`** (NB6 first draft wrote
   `${${HEALTHY/...}/...}`) — bash rejects it; fixed as two sequential substitutions plus a
   landed-check so a no-op degenerate is loud. **Prevention:** never nest `${var/pat/rep}` —
   chain assignments, and pin the substitution landed.
2. **Backticks inside an unquoted stub heredoc** — a comment line containing
   `` `else error("no data array")` `` inside `make_stubs`'s `<<STUB` was command-substituted
   at every stub write ("syntax error near unexpected token `else'"), mangling the comment.
   Tests stayed green; the noise was the tell. **Prevention:** no backticks/`$(` in unquoted
   heredoc comment text; the durable fix is the quoted-heredoc rewrite in #9209.
3. **`gh issue create` gate rejections** — first for a missing `--milestone`, then for a
   missing machinery classification. Both gates behaved correctly. **Prevention:** machinery
   findings file with `--milestone "Post-MVP / Later" --label meta/machinery`.
4. **`bun test <file>` filter miss** (×2) — the web-platform suite is vitest, not bun test;
   `bun test` needs a different filter form anyway. **Prevention:** `npx vitest run <path>` for
   `apps/web-platform/test/*.test.ts`.

## Prevention

- When re-arming or extending a soak/gate, grep for each operand's *sender* (workflow payload,
  deploy dispatch), not just its emit site.
- Reviewer's map-not-findings discipline (the structural-enumeration seat): enumerate every
  channel to `exit 0`, ask per channel what guard covers it.
