---
title: "Devin Cloud session surfaces diverge from their local shapes — requiredPlugins needs git-subdir, /handoff carries commits only, sandboxes boot warm images"
date: 2026-09-17
category: integration-issues
module: plugins/soleur
component: tooling
problem_type: integration_issue
resolution_type: config_change
root_cause: config_error
severity: high
symptoms:
  - "repo-level requiredPlugins url+#subdir form resolves locally but 404s in cloud (fragment passed verbatim into the git-manager proxy path)"
  - "/handoff cloud session boots the warm blueprint image on main — declared branch not checked out, no uncommitted/untracked/gitignored content transfers"
  - "drs sandbox-create --repo <name> can boot a pre-existing warm image instead of cloning the named repo"
  - "devin ssh / ssh-info returns 403 on accounts without the permission"
tags: [devin-cloud, requiredplugins, git-subdir, handoff, blueprint, warm-image, git-manager-proxy, probe-methodology]
issues: [8172, 8159, 8234]
---

# Devin Cloud session surfaces diverge from their local shapes

## Problem

Three cloud-session surfaces that look identical to their local counterparts
behave measurably differently (probe record:
`knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md`
§Results — residual arms, 2026-09-17):

1. **`requiredPlugins` string form.** `"https://github.com/owner/repo#subdir"`
   resolves fine locally, but in cloud the fetcher passes the entire string —
   fragment included — to `git-manager.devin.ai` as the repository path:
   `fatal: repository '...soleur#plugins/soleur/' not found`. The requirement
   registers (`origin.scope: "repo"` in `lock.json`) but resolves to nothing.
   Worse, **identity dedup masks the failure**: both forms normalize to the
   same `owner/repo#subdir` identity, so a working managed-manifest install
   makes the broken repo-level requirement invisible in `resolved: []`.
2. **`/handoff` fidelity.** The cloud VM boots the warm blueprint image
   (`~/repos/<repo>` on `main` at the image's SHA) — the declared branch is
   not checked out, and after a manual fetch+checkout only *committed*
   content is present. Tracked modifications, untracked files, and gitignored
   files (including a `.devin/` sentinel) never materialize;
   `git status --porcelain` is empty. Any design premised on handoff
   transporting worktree state is wrong.
3. **Sandbox `--repo` semantics.** `devin cloud drs sandbox-create --repo X`
   may boot an existing warm image rather than clone X — repo-level
   `requiredPlugins` is only discovered from repos cloned *at session start*,
   so a sandbox that never cloned your probe repo cannot measure it.

## Root cause

- The cloud resolver treats the URL-string manifest entry as a verbatim
  repository locator (no fragment stripping) while the local CLI parses
  `#subdir` as a subdir selector. Two parsers, one string.
- Cloud sessions are provisioned from per-repo blueprint images; what lands
  on the VM is the image, not the session config. Git state that was never
  committed cannot cross, because the only transfer channel is git itself.
- `requiredPlugins` discovery is a session-start scan over the clones that
  exist at that moment — there is no second pass.

## Solution

- Use the **`git-subdir` object form** for repo-level `requiredPlugins`:
  `{"source": "git-subdir", "url": "https://github.com/owner/repo.git", "path": "subdir"}` —
  verified resolving on both surfaces (arm D lock.json: `scope: "repo"`,
  resolved SHA, cache populated). The `owner/repo#subdir` shorthand remains
  valid for `devin plugins install` CLI calls only.
- To measure repo-level cloud config for a repo, give it a **blueprint**
  (`environment.yaml` + `devin cloud drs build`) first, then sandbox on it —
  that forces a fresh clone at session start.
- For evidence collection, `devin ssh` is account-gated (403 observed);
  the reliable channels are the session agent pushing findings to a branch
  and `devin cloud drs run` stdout.

## Key Insight

"Same manifest, two parsers" is the defect class: any config whose value is
consumed by both the local CLI and a cloud proxy must be verified on both
surfaces — a locally-green form can be a cloud 404. And dedup is a
measurement hazard: a healthy second requirement can silently mask a broken
first one, so verify per-requirement `resolved` state, not just plugin
presence.

`/handoff` and sandboxes share one provisioning model: **the image is the
filesystem**. Branch declarations steer git, not the boot. If a measurement
needs content that isn't a commit on a fetched branch, it cannot be measured
through either vehicle.

## Session Errors

1. **`devin ssh`/`ssh-info` → 403** on this account (repeated). — Recovery:
   used the findings-push channel (cloud agent pushes to the branch) and
   `drs run` stdout. — Prevention: treat ssh as optional in probe design;
   always arm a push-back or `drs run` evidence channel.
2. **`sandbox-create --repo probe-8172-reqplugins` booted the warm soleur
   image** instead of cloning the probe repo. — Recovery: created a
   blueprint (`environment.yaml`, `drs build`) for the probe repo and
   re-ran the sandbox (arm D). — Prevention: for repo-scope config probes,
   blueprint-first is the only reliable vehicle; verify the session-start
   clone before trusting the lock.
3. **Arm-B handoff assumed the session clones the handed repo.** It boots
   the warm image; the probe repo was never cloned at session start, so its
   `requiredPlugins` was never scanned. — Recovery: superseded by arm D. —
   Prevention: same as #2 — the session-start clone set is the measurement
   boundary; enumerate it before interpreting `lock.json`.
4. **`bun` shim unset in mise** (`No version is set for shim: bun`). —
   Recovery: invoked `~/.local/share/mise/installs/bun/<ver>/bin/bun`
   directly. — Prevention: one-off host env; no action.
5. **`lefthook` not in PATH** at commit (warning only). — Recovery: none
   needed. — Prevention: one-off env.
6. **Orphan worktree dir unremovable** in the session-start cleanup. —
   Recovery: non-blocking, noted. — Prevention: one-off.

## Prevention

- For any dual-surface config value, assert the **cloud** resolution path,
  not just local: grep `lock.json` per-requirement (`scope`, `source`,
  resolved SHA), not just plugin presence.
- Treat dedup as a masking hazard: when two requirements normalize to one
  identity, verify each requirement's own resolve status.
- Blueprint-first for any repo-scope cloud measurement; `--repo` and
  `/handoff` both boot warm images.
- Keep `#8172` cleanup items tracked: throwaway repo
  `jikig-ai/probe-8172-reqplugins`, blueprint
  `snapshot-blueprint-4762b3ff21ec466cb0183c3cdbb13ede`, probe branch
  `probe-8172-handoff-arm`.
