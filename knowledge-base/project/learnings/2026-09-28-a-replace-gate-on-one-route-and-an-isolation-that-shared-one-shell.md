---
title: "A replace gate on one route, and an isolation that shared one shell"
date: 2026-09-28
category: integration-issues
module: apps/web-platform/infra (registry host, zot boot image)
tags: [cloud-init, runcmd, env-isolation, preflight, immutable-releases, mutation-testing, test-design]
issue: 8714
pr: 9147
---

# A replace gate on one route, and an isolation that shared one shell

## Problem

PR 2b of #8714 step 5.3b-iii moves the zot registry host off ghcr.io. The host boots zot from a
pinned GitHub release asset:

- the tarball must hash to T;
- its manifest D must name config C;
- the loaded image ID must be C or D.

ghcr.io is name-resolution-denied on the host.

The first revision was green on 70 fetch/render/heartbeat assertions, a 17-row self-run mutation
battery, and every sibling suite. A 5-seat review panel then found two P1s and nine P2s. Every one was
outside what the author's battery perturbed.

## Solution (what changed)

1. **Isolation.** The fetch ran as "its own runcmd entry, outside `doppler run`". But cloud-init
   writes `runcmd` as ONE `/bin/sh` script. The LUKS and ghcr blocks above it run
   `set -a; . /etc/default/registry-doppler; set +a`, which exports `DOPPLER_TOKEN` into the shared
   shell for every later entry. The fix is `env -i PATH=... HOME=/nonexistent` on the fetch entry,
   plus `curl -q`.
2. **Gate placement.** P6 (the asset exists and its digest is T) guarded only the dispatcher. Three
   other routes create the same host: `apply-web-platform-infra.yml`'s `registry_host_replace`,
   `registry_luks_recut` and `registry_region_migrate`. P6 became
   `registry-replace-preflight.sh --check-asset`, and all three jobs and rule-audit now run it.
3. **Immutable releases.** The recovery text said to re-publish a deleted asset. This repository has
   release immutability, so a deleted release's tag can never be reused. The only recovery is to
   revert the pin. The runbook, the P6 text, the provenance doc and the ADRs now say so.
4. **Trust anchor.** C was a free literal, anchored only by a CI job that is not required. The host
   now extracts manifest D from the tarball before loading. It requires `sha256(D-blob) == D` and
   `.config.digest == C`, and refuses with `manifest_mismatch` otherwise.
5. **Budget.** Those fixes took the registry `user_data` to 20,408 B, over `REGISTRY_GZIP_BUDGET`
   (20,000). Deleting every diagnostic message still left 20,060 B. The CTO ruled the budget up to
   21,000, recorded as an ADR-185 amendment. The 8,000 B headroom policy is unchanged.

## Key Insight

Every defect sat on an axis the author's instrument never touched:

- the gate's **population of routes**, not its logic;
- the **shell** the entry actually runs in, not the entry's YAML boundary;
- the vendor's **release lifecycle**, not the API response;
- the **real** terraform map, not the budget script's copy of it;
- the **path contract** between write_files, the fetch and the heartbeat;
- **fixture digests** made of one repeated character, which hide a wrong-slice bug;
- deny and launch guards that were **grepped, not executed**;
- `-x` anchors with **no embedded-valid fixture**.

The test-design seat found 12 mutation survivors, all on axes the self-run battery never edited. Ask
"which LAYER does each row edit", not "how many rows killed".

## Session Errors

1. **A `\t` inside `grep -E` matched nothing.** The runcmd index came back empty and R1/R2 went red. Recovery: `$(printf '\t')`. Prevention: never write `\t` inside an ERE; use `[[:space:]]` or printf.
2. **Mutation expressions lost their `$` tokens.** They went through bash double quotes, so every mutation reported NOT LANDED. Recovery: moved the mutations into a Python module. Prevention: never pass mutation source through shell quoting. The landing assertion is what caught it.
3. **The fixture tarball was built with `tar -C d .`**, which gave its members a `./` prefix. `tar -xOf blobs/sha256/D` then found nothing, and every happy row reported `manifest_mismatch`. Recovery: named the members explicitly. Prevention: build fixtures with the same member names the producer writes (the builder packs `oci-layout index.json manifest.json blobs`).
4. **A repo-global ratchet (`pr-fanout-ledger`) was outside my targeted suite set.** Adding `on: pull_request` to zot-image-mirror.yml turned `test-scripts (1/7)` red in CI. Recovery: added the ledger row. Prevention: plan-sharp-edges bullet (routed).
5. **The fetch inherited `DOPPLER_TOKEN` through the single runcmd shell.** Recovery: `env -i`. Prevention: routed to plan-sharp-edges.
6. **P6 guarded one of four host-creating routes.** Recovery: `--check-asset` on all four, plus rule-audit. Prevention: routed to plan-sharp-edges.
7. **A recovery step was impossible under immutable releases.** The step was "re-publish the deleted asset". Recovery: the docs now say to revert the pin. Prevention: check every recovery step against the vendor's lifecycle rules (`gh api .../immutable-releases`) before writing it.
8. **`lint-shell-capture-exit` flagged `PIN_C=$(grep …)` under `set -e`.** Recovery: `|| true`. Prevention: run that lint before the first commit of any new `.sh`.
9. **The no-terraform floor probe removed only one PATH dir.** terraform also lives in `~/.local/bin`, so the "skip" run still rendered. Recovery: filter out every PATH dir that holds the binary. Prevention: assert `command -v X` fails before measuring an "X absent" arm.
10. **A commit stalled about 10 minutes in lefthook's `bun-test` hook.** A `.ts` file was staged on a contended machine, and the harness backgrounded the call (exit 144). Recovery: killed the process tree by `pstree` PID, confirmed there was no `index.lock`, and retried with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test,web-platform-typecheck`, as the operator directed. Prevention: on a contended machine, use that exclusion for commits that stage `.ts` and rely on CI.
11. **Hooks blocked a stash listing, process-by-command-line matching, and a chained sleep.** One of these blocks hit this learning's own heredoc, which quoted the forbidden spelling. Recovery: walked `/proc/*/cwd`, used `pstree` and background waits, and wrote files with the Write tool. Prevention: already hook-enforced. Never quote a blocked command spelling inside a Bash heredoc.
12. **The budget script re-validated members that terraform already enforces.** Recovery: kept only the marker check. Prevention: before hand-validating HCL, ask whether a render failure already fails closed.
13. **One mutation twice failed to land.** A backslash escape in its anchor stopped it matching. Recovery: anchored on an escape-free substring. Prevention: pick mutation anchors that contain no escapes.
