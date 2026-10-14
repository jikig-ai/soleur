---
title: I measured the new binary's binds and asserted the OLD one lacked them — the "CHANGED" verdict was an unmeasured diff
date: 2026-09-30
category: engineering
tags: [respike, evidence-discipline, version-bump, review-panel, inngest]
symptoms: [respike doc claimed "v1.45.1 binds *:50052/*:50053/*:8289 — v1.19.4 did not" from measuring only the new binary; review agents found the claim contradicted by the repo's own cloud-init comments and the old bootstrap prose; one local `ss -tln` on the old binary refuted it]
module: Infra version-bump re-spike
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: measured the target artifact but inferred the baseline
severity: medium
---

# A "CHANGED" verdict requires measuring BOTH endpoints

## Problem

In the #7463 inngest CLI re-spike (v1.19.4 → v1.45.1) I ran `ss -tln` on the
v1.45.1 server, saw `*:50052`/`*:50053`/`*:8289`, checked the flag-help diff
(the `--connect-*-grpc-ip` flags were new), and wrote "v1.45.1 opens three
listeners v1.19.4 did not." The claim survived into the provenance sidecar and
the ADR-100 amendment verbatim. It was false: v1.19.4 binds the same three
sockets — proven by booting the old binary and running `ss` — and the repo
already knew (`inngest-bootstrap.sh` said "binds 0.0.0.0:8288 + 8289"). What
was actually new: the advertise-IP *flags*, not the listeners. The composite
wrong-claim then cascaded — "nftables default-deny covers inbound" repeated
a never-true sibling claim (the chain is `policy accept` with drops on
8288/8289 only).

The correction cost one command and five minutes, after five review agents
flagged it. The evidence doc exists to make version claims *measured*, and the
one class of claim I forgot to measure was the diff itself.

## Rule

For every `CHANGED`/`NEW`/`REMOVED` row in a version-delta evidence doc, the
measurement must name the command run against **each** endpoint — the new AND
the old binary/config/source. A help-diff or source-diff showing a flag was
ADDED says nothing about runtime behavior at the old tag. When a claim can be
falsified by the repo's own committed prose (`binds 0.0.0.0:8289` sat in the
bootstrap header all along), grep the claim's subject before asserting it.

## Session Errors

- Respike doc asserted "new listeners" without `ss` on the old binary.
  **Prevention:** the rule above — dual-endpoint measurement for delta claims.
- Follower-claim gate regex was blind to phrasings inside its own follower
  list (`inngest-server v…`, `pinned v…`, bare `vX.Y.Z`, claim split across a
  line wrap). **Prevention:** the gate now enforces one canonical claim shape
  and the sidecar's register states it; five `.test.sh` followers + the tf
  file joined the follower set.
- `MIN_ASSERTIONS` was set below the exact green count (14 vs 17) leaving
  three silent-drop slots. **Prevention:** floor equals the measured green
  count, matching the zot sibling's convention.
- `deploy inngest` prescribed in the plan/ADR as a flip path for a host the
  verb cannot reach (web arm is quiesced-refused). **Prevention:** flip-path
  claims get a "which host does this verb POST to" check; the only dedicated-
  host path is `apply_target=inngest-host-replace`.
- Sed delimiter collision and a line-wrap producing an invisible claim.
  **Prevention:** mutation-battery mutators get a `diff -rq` landed-check
  (already present — caught the no-op class); claims reworded on one line.
- Work subagent died on rate limit mid-phase with zero commits.
  **Prevention:** none structural — recovered by executing the (fully
  prescriptive) plan inline; plan-first saved the run.
- `/tmp` tmpfs filled during harness setup. **Prevention:** the battery
  already exports `TMPDIR=/var/tmp`; reuse that convention for scratch
  harnesses.
- `pkill -f` and broad `rm -rf` rejected by path guards. **Prevention:**
  already enforced — exact PIDs and specific subdirectories only.
- `gh issue create` refused twice (milestone + filing-exit label).
  **Prevention:** the guard's message is self-describing; read it before
  re-firing.
- `--affected` pre-commit gate serialized ~50min behind sibling worktrees.
  **Prevention:** operator authorized `--no-verify` + CI-primary; the local
  gate remains the opt-in path.
- shellcheck SC2034 / markdownlint MD038 minors. **Prevention:** run both
  on new/edited files before commit, not after.

## Related

- #7463 / PR #9201 (the change under review), #7308, #7282 (zot precedent),
  #9219 (dead `inngest pause` follow-up).
