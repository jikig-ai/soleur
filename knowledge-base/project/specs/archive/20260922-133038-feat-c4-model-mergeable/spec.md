---
feature: c4-model-mergeable
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/archive/20260922-133038-2026-09-22-c4-model-mergeable-brainstorm.md
draft_pr: 8538
issue: 8542
deferred: 8541
---

# Spec: mergeable model.likec4.json

## Problem Statement

`model.likec4.json` is one 1.1 MB line, so every pair of PRs that regenerates it conflicts
(0 of 105 replayed real pairs merge), GitHub reports DIRTY, and each affected PR needs a local
resync that restarts CI and requeues it.

## Goals

- G1. Two PRs whose regenerated artifacts don't set the same leaf differently merge cleanly
  on GitHub (measured target: ≥ 36/51 on the gap 1-2 replay set, 0 false-clean).
- G2. The repo writer and the app writer produce byte-identical output.
- G3. Every reader keeps rendering, and the file stays well under `MAX_C4_BYTES`.

## Non-Goals

- Removing Graphviz coordinates from the artifact (a layout-free artifact). Deferred.
- Untracking the artifact (option B), splitting it (C), or auto-resync automation (D).
- Anything for `rule-metrics.json` (verified: no live writer; only #8329 still modifies it).

## Functional Requirements

- FR1. Canonical format: parse likec4's export, set each `views[*].hash` to `""`,
  serialize `JSON.stringify(o, null, 1)` with each line's leading spaces removed, append `\n`.
  Key order is likec4's.
- FR2. Canonicalization is idempotent: canonical(canonical(x)) == canonical(x).
- FR3. `scripts/regenerate-c4-model.sh` publishes canonical bytes (validation stays before
  publish). The size cap applies to canonical bytes.
- FR4. `apps/web-platform/server/c4-render.ts` returns canonical bytes, so `c4-writer.ts`
  commits them to customer repos.
- FR5. The committed artifact in this repo is regenerated in the new format.
- FR6. `resolve-regenerable-conflicts.sh` still regenerates the artifact on real conflicts,
  and that output is canonical.

## Technical Requirements

- TR1. One dependency-free module under `apps/web-platform/lib/` (the Docker build copies only
  `apps/web-platform`), imported by the server and run with `node` by the bash script. jq never
  writes the artifact.
- TR2. A test proves both writers produce identical bytes from the same raw export.
- TR3. A test proves `LikeC4Model.create` accepts a canonical (blank-hash) model.
- TR4. Acceptance test replays real concurrent `.c4` pairs from main history: the old format
  must fail (conflict) and the new one must merge clean and equal a fresh render of the merged
  sources. It includes two positive controls: a real true-overlap pair (sources merge clean,
  artifact must conflict) and a real commit paired with a crafted same-line source edit
  (source conflict, artifact must conflict).
- TR5. Shell suites run CI-style (`HOME=$(mktemp -d) GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_NOSYSTEM=1`), with git identity set in each fixture repo's local config.
- TR6. Keep `RESOLVABLE_PATHS` (1 member) and `kb-caches-untracked.test.sh` `EXPECTED_N=5`
  consistent. Amend ADR-235. Add `linguist-generated=true` for the artifact in `.gitattributes`.
- TR7. The freshness test (`c4-model-freshness.test.sh`) keeps byte-comparing and so
  covers the new format through `--out`.
- TR8. Compound step captures #8384's un-captured learnings: fixture git identity under CI
  env, a clean merge that silently broke `sync-pr-behind.sh`, the six-resync loop, the misread
  of draft-PR CI, and a process check that matched names and missed a running test job.
