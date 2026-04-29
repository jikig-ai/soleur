---
date: 2026-04-29
category: integration-issues
module: web-platform/infra
issue: 3045
pr: 3046
tags: [docker, bind-mount, deploy-pipeline, observability, partial-copy, sentinel]
---

# Bind-mount seed detection needs a late-written sentinel — manifest checks miss SIGKILL-mid-cp partial copies

## Problem

PR #3046 populates `/mnt/data/plugins/soleur` on prod hosts via `docker cp <ephemeral>:/opt/soleur/plugin/. /mnt/data/plugins/soleur/`. The first reviewer iteration of `verifyPluginMountOnce()` checked three states: path missing, directory empty, manifest missing. Multi-agent review surfaced a fourth: **manifest present but skill files missing**.

`docker cp` ships a tar stream. tar entries extract in archive order, which is generally the producer's filesystem walk order — and `.claude-plugin/plugin.json` lives at the root and extracts very early. If the cp is interrupted mid-extraction (SIGKILL during deploy, OOM, disk full), the manifest can land while later directories (`skills/`, `agents/`, `commands/`) extract partially or not at all.

Result: the boot probe sees populated dir + manifest exists + structure looks fine. Health check passes. SDK loads zero skills because most of `skills/*` is empty. Sentry is silent. Production silently degrades.

## Solution

Write a sentinel file (`.seed-complete`) AFTER `docker cp` returns 0 — i.e., as a separate post-cp filesystem write that only happens when cp succeeded as a whole. Then check the sentinel in the boot probe.

```bash
# In ci-deploy.sh AND cloud-init.yml:
docker cp soleur-plugin-seed:/opt/soleur/plugin/. /mnt/data/plugins/soleur/
docker rm soleur-plugin-seed
# Sentinel — written LAST so SIGKILL during the cp leaves it absent.
printf '%s\n' "seeded $(date -u +%Y-%m-%dT%H:%M:%SZ) tag=$TAG" \
  > /mnt/data/plugins/soleur/.seed-complete
```

```ts
// In server/plugin-mount-check.ts, after the manifest check:
const sentinel = join(pluginPath, ".seed-complete");
if (!existsSync(sentinel)) {
  reportSilentFallback(null, {
    feature: "plugin-mount",
    op: "discovery",
    message: "plugin-mount partial seed",
    extra: { path: pluginPath, sentinel },
  });
  return;
}
```

The sentinel is a **post-condition assertion** for the cp operation: its existence proves the cp returned 0 from the deploy script's perspective. tar extract order, filesystem ordering, and SIGKILL semantics become irrelevant — either the deploy script wrote the marker or it didn't.

## Key Insight

**Late-extracted file inside the payload is not equivalent to a sentinel written AFTER the operation.** They look similar in the happy path but diverge under failure.

A "late-extracted" check (e.g., assert `skills/zzz-marker/SKILL.md` exists) is hostage to:
- tar entry order (producer-defined, may shift across image rebuilds)
- partial-extract semantics (SIGKILL truncates the in-flight file but leaves prior entries intact)
- the marker file's own bytes inside the payload

A sentinel **written by the deploy script after the cp** is hostage only to whether the deploy script reached its post-cp line. It is the canonical post-condition.

This generalizes beyond docker cp: any compound operation where you need to attest "the whole thing succeeded" should write a small, separate post-success marker rather than relying on a property of the payload itself. The same pattern applies to: rsync mirrors, multi-file unzip extractions, image-build artifact bundles, multi-row DB seed scripts.

## Cross-references

- [Plan](../plans/2026-04-29-fix-plugins-soleur-mount-empty-plan.md)
- Issue #3045 (the empty-mount investigation that surfaced the gap)
- Issue #3053 (deferred: empty-mount window during deploy — design venue #2608)
- Issue #2608 (plugin freshness rotation API — design parent for the durable fix)
- `knowledge-base/project/learnings/2026-02-09-plugin-staleness-audit-patterns.md` (related: plugin staleness detection)
- `knowledge-base/project/learnings/2026-03-20-docker-nonroot-user-with-volume-mounts.md` (related: three-file lockstep rule)

## Session Errors

- **PreToolUse security_reminder_hook.py silently rejected workflow edits.** Two `Edit` calls on `.github/workflows/*.yml` returned the hook's reminder text in the result without applying the change; identical retries succeeded. Recovery: grep-verify each workflow edit landed before continuing. **Prevention:** add a step to the work/review pipelines (or a hook) that auto-verifies a workflow edit's `old_string`→`new_string` substitution by post-edit grep, surfacing silent rejections.

- **Bash CWD drift between calls.** A `cd apps/web-platform && <cmd>` call left subsequent calls anchored differently than expected; a follow-up `grep apps/web-platform/...` failed with ENOENT until I prepended `cd <worktree-root>`. Recovery: anchor every Bash call with an absolute path or a `cd <abs> && ...` chain. **Prevention:** treat every Bash call as starting from indeterminate CWD; chain `cd <abs-path> && <cmd>` in one call when CWD matters. Already documented in AGENTS.md as `wg-when-running-test-lint-budget-commands` for test runners — extend the discipline to grep/find/general invocations.

- **session-state.md directory missing.** The work skill expected `knowledge-base/project/specs/<branch>/session-state.md` but the planning subagent wrote the plan to `knowledge-base/project/plans/`, leaving the specs dir uncreated. Had to `mkdir -p` manually. Recovery: created the dir before Write. **Prevention:** the plan skill should create `knowledge-base/project/specs/<branch>/` as part of its contract (even when only the plan is initially written), or the work skill's session-state writer should create-as-needed via Write's auto-mkdir behavior.

- **Scope-out criterion mislabeled twice before reviewer CONCUR.** First pitch used `contested-design` (reviewer DISSENTed: approach (a) treated as trivial). Second pitch used `architectural-pivot` (reviewer DISSENTed: single-pipeline change, not codebase-wide). Third pitch (`contested-design` with corrected cost analysis) got CONCUR. Recovery: re-pitched with each round's substantive critique addressed. **Prevention:** before pitching a scope-out, walk the four criteria definitions explicitly and pre-empt the most likely reviewer objections — particularly cost analysis for any "trivial inline" claim.

## Tags

category: integration-issues
module: web-platform/infra
