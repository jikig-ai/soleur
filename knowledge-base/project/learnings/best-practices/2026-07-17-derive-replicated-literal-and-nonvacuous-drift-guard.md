---
module: web-platform-infra
date: 2026-07-17
problem_type: integration_issue
component: terraform
symptoms:
  - "a config literal (docker insecure-registries endpoint 10.0.1.30:5000) replicated across 3 live files with no drift guard"
  - "the drift guard grepped the delivered file for the literal it itself hardcoded — self-referential, could never detect drift"
root_cause: self_referential_guard_over_replicated_literal
severity: medium
tags: [drift-guard, terraform, templatefile, single-source, bash-set-e, git-mv, mutation-test]
synced_to: [work]
---

# Learning: derive a replicated literal from its single source, and make the drift guard non-self-referential (#6448)

## Problem

`local.registry_endpoint` (`zot-registry.tf:44`, derived from the single-source `local.registry_private_ip`) is the canonical `host:port` for the self-hosted zot registry, but the same `10.0.1.30:5000` value was **independently hardcoded** in three live (non-comment) places — `docker-daemon.json`, `cloud-init.yml`, and a `server.tf` remote-exec probe — with no guard that could detect divergence from the local.

The "guard" (`registry-insecure-config.test.sh`) was **self-referential by construction**: `server.tf` did a static `file()` copy of `docker-daemon.json` and then greped the delivered file for the literal it itself hardcoded. It validated the file against a copy of its own content and *cannot* detect drift from `local.registry_endpoint`. This is the exact silent-failure shape of the #6400 outage: a subnet renumber (`local.registry_private_ip = "10.0.1.31"`) would leave every copy on `.30:5000` while `terraform apply` AND CI stayed GREEN and pulls silently fell back to GHCR.

## Solution

Derive the literal at every live site from the single source, and rebuild the guard to prove derivation instead of self-reference:

1. `git mv docker-daemon.json docker-daemon.json.tmpl`; change the one value line to `["${registry_endpoint}"]`. It renders **byte-identical** to the prior static file at the current value (same `sha256`), so `triggers_replace = sha256(local.docker_daemon_json)` keeps its prior value ⇒ **zero replace/churn** on the running fleet.
2. Add `local.docker_daemon_json = templatefile("…/docker-daemon.json.tmpl", { registry_endpoint = local.registry_endpoint })` and deliver it via `provisioner "file" { content = local.docker_daemon_json }` (first `content=` provisioner in the repo — non-secret rendered content needs no base64 heredoc; `terraform validate` accepts it, and a `source→content` swap does not force replace).
3. Interpolate `${local.registry_endpoint}` into the remote-exec probe and thread `registry_endpoint` into the cloud-init `templatefile()` map so the fresh-host copy derives too.
4. Rebuild the guard around a **shape-based, non-comment residual scan** — count `^[^#]*[0-9]{1,3}(\.[0-9]{1,3}){3}:5000` across the derivation surface and assert **0**. This is the mutation test: a reintroduced hardcoded copy (the exact drift) is a non-comment `IP:5000` literal ⇒ RED. Match by **shape, not the pinned value**, so the guard survives a real renumber (extract-by-shape, `2026-06-11`).

## Key Insight

**A guard that greps a delivered artifact for a literal it also hardcodes can never fail on the drift it exists to catch.** The fix is to make the artifact *derive* the literal from the single source (templatefile + `content=`), and re-anchor the guard on "no hardcoded copy exists on the derivation surface" (shape-scoped, non-comment) rather than "the copy equals the copy." Prove non-vacuity by mutating a **sandbox copy** and confirming RED (never in-place-mutate + `git checkout` restore — it wipes uncommitted work, `#6415`/`#6454`).

Corollary (converged on by two review agents): a cross-artifact "for-all-maps/members" assertion must **scope each member to its own block**, not a file-wide `count >= N` — a coarse count passes vacuously if one member drops the value while an unrelated occurrence appears elsewhere (`cq-assert-anchor-not-bare-token`).

## Session Errors

1. **A new `set -euo pipefail` guard's `grep … | wc -l` aborted mid-script on a zero-match** — the residual-count grep legitimately matches 0 in the success case, and under `pipefail` grep's exit 1 propagates and `set -e` kills the whole script before the results footer (no FAIL, no "Results" line — just a silent early exit). **Recovery:** wrap the failing segment as `{ grep … || true; } | wc -l`, and add `|| true` to any `grep -c` in a command substitution. **Prevention:** any deliberately-zero-match `grep`/`grep -c` inside a `$(…)` under `set -e`/`pipefail` needs `|| true` (recurrence of the documented bash-accumulate-then-exit class — `2026-06-29`).

2. **`git mv old new` then `git add old` (the pre-rename path) aborted the entire `git add`** — the stale pathspec exits fatal `pathspec 'old' did not match any files`, which drops every OTHER path from the same `git add`; the subsequent commit captured only the rename (`0 insertions`). **Recovery:** `git commit --amend` after staging the correct (new) paths. **Prevention:** after a `git mv`, stage the NEW path (or `git add -A <dir>`), and verify `git show --stat HEAD` shows the expected file set before trusting the commit — a rename-only stat (`0 insertions`) on a content change is the tell.

3. **(one-off) `rm -rf` of gitignored `.terraform` artifacts was denied by the workspace guard** — a two-path `rm -rf` resolved onto the protected worktree root. `.terraform` is gitignored so no cleanup was needed. **Recovery/Prevention:** scope destructive deletes to a specific non-protected subdirectory (`cd <dir> && rm -rf ./.terraform`), not a path that can resolve to the worktree/repo root.

## Tags
category: best-practices
module: web-platform-infra
