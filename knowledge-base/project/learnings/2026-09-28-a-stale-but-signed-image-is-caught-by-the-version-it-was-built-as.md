---
title: A stale but signed image is caught by the version it was built as, before the swap
date: 2026-09-28
category: integration-issues
tags: [ci-deploy, zot, cosign, supply-chain, deploy-gate, ratchets, mutation-testing]
issue: 6428
---

# Learning: a stale but signed image is caught by the version it was built as

## Problem

After the zot cutover, a registry that served an **old but validly signed** image for a requested tag
passed every pre-swap control. `verify_image_signature` checks the signature of whatever digest the
tag resolved to, and an old image is validly signed. The only check that noticed was the release
workflow's post-deploy `/health` version assertion. That check runs after the stale container is
already serving, and it runs only on the ingress host, so web-2 is never checked.

## Solution

`verify_image_freshness` in `apps/web-platform/infra/ci-deploy.sh` runs right after the
`VERIFIED_REF` assignment and covers both arms (the verified digest and the local-cache rescue). It
runs before the plugin seed, the canary and the swap.

- **Read.** `docker inspect --type image` reads the image config. `BUILD_VERSION` is baked by
  `reusable-release.yml`, the only producer of the web image.
- **Compare.** An exact whole-key comparison with `${TAG#v}`.
- **Fails closed.** A mismatch writes `image_stale_version`. A missing, `dev`, duplicated, or
  uninspectable version writes `image_version_unverifiable`. In both cases the old container stays
  live.
- **Pages.** A Sentry event with `op=image-freshness` and `level=error` pages through a new IaC rule.
- **Liveness.** `IMAGE_FRESHNESS: ok` is the Better Stack liveness marker.

No payload or contract change was needed. Digest pinning through `/hooks/deploy` is the upgrade path.

**Delivery is web-1 only.** `terraform_data.deploy_pipeline_fix` pushes `ci-deploy.sh` to web-1 only.
web-2 gets the check on its next replace (#9151).

## Key Insight

When a control verifies *authenticity* (a signature), freshness is a separate property. The
cheapest freshness check is a **self-consistency value the build already signs into the artifact**:
the version it was built as, compared with the version that was requested. It needs no new plumbing.
It must fail closed, because every image the registry can serve already carries the value, so the
closed arm costs no legitimate deploy.

## Session Errors

1. **The first mutation battery ran on a subtree sandbox copy (`copytree apps/web-platform/infra`),
   and every row, control included, reported the same unrelated failures.** The suite depends on
   repo context outside that directory, so the results were void.
   **Recovery:** re-ran in place against the committed file, restoring from a pristine backup under
   `/var/tmp`. Control 355/355; all 9 mutants were killed; the restored file was verified identical.
   **Prevention:** already documented in `review/SKILL.md` ("run the UNMUTATED control first"). Run
   the control before reading any row.
2. **The first implementation commit failed twice (rc=1) under lefthook.** `bun-test` queued about
   11 minutes behind a sibling worktree's full battery. `web-platform-typecheck` also failed, because
   the fresh worktree had no `node_modules`, and the symlinked main-checkout `node_modules` was stale
   (139 unrelated errors, including missing swr, svix and cmdk).
   **Recovery:** `LEFTHOOK_EXCLUDE=bun-test,web-platform-typecheck`, after running the affected
   suites by hand.
   **Prevention:** `work/SKILL.md` already names `LEFTHOOK_EXCLUDE=bun-test`. Before committing,
   check whether a sibling worktree is running a full gate (`proc.sh list_runs test-all.sh`).
3. **Two red CI suites (test-bun and preflight-check10-suite-integrity) came from one cause.** The
   plan's `discoverability_test` declared `credentials_required`, which moves the
   `BASELINE_DECLARED_PROBES` corpus ratchet (#7393 G1). This lesson is already written TWICE in
   `plan/references/plan-sharp-edges.md`, and the plan phase skipped the §6.5 sharp-edges read.
   **Recovery:** replaced the probe with an unauthenticated grep of the emitter.
   **Prevention:** do not skip plan §6.5. The catalogue already had this exact entry.
4. **A red fixture-relative-assert ratchet.** The new `run_6428` harness, added to an EXISTING suite,
   wrote `"$d/…"` under a caller-supplied directory without the canonical `assert_fixture_dir`.
   `work/SKILL.md` 6.6 scoped that ratchet check to NEW `*.test.sh` files only.
   **Recovery:** added `assert_fixture_dir "$d"`.
   **Prevention:** the ratchet caught it in CI, which is enough. A one-line widening of work 6.6 was
   blocked by `skill-body-budget-lint` (work SKILL.md is at its cap), so it was not applied. When a
   PR adds a helper that writes under a directory to an existing `*.test.sh`, run
   `plugins/soleur/test/fixture-relative-assert.test.sh` before pushing.
5. **The first plan design failed open.** A missing `BUILD_VERSION` was treated as "indeterminate, do
   not abort", and F7 used the same input as F2 (so it could not tell a hard-wired canonical apart).
   **Recovery:** the plan-review simplicity seat pointed out both. Fail-closed and F7 moved to
   `v10.20.30`.
   **Prevention:** in the plan's Guard Contract, require that any must-PASS row differs from the
   canonical.
6. **A junk second `docker inspect` block went into the call site during the first edit** (a thinking
   slip). It was noticed straight away and replaced with the `FRESHNESS_ABORT_REASON` global.
   **Prevention:** a one-off.
7. **Four hook denials, each immediately rerouted:** `git stash list` in a command chain,
   `pgrep -f`, a chained `sleep`, and a background poll loop (use Monitor).
   **Prevention:** already hook-enforced.
8. **`lint-shell-capture-exit.py` run without `--baseline` reported 228 "NEW" findings.**
   **Recovery:** re-ran with the baseline and the file arguments.
   **Prevention:** already documented (work SKILL "A GUARD RUN WITHOUT THE ARGUMENT THAT BOUNDS IT").
9. **The test-design seat found 5 surviving mutants in a suite the author's 9-mutant battery had
   certified.** (a) `_6428_started` looked for `DOCKER_TRACE:create`, but ci-deploy.sh redirects the
   seed `docker create` to /dev/null, so moving the check after the plugin seed survived. (b) The
   state file's `exit_code` was never asserted. (c) The WARN-mode tag-fallback arm of VERIFIED_REF
   had no stale row. (d) The mock could not emit an empty `BUILD_VERSION=` line. (e) The
   `DEPLOY_ABORT` log line was never checked.
   **Recovery:** fixed all five inline, with rows for each.
   **Prevention:** before crediting a battery, check each observable it relies on. An assertion that
   reads a trace marker must be checked against whether the SUT redirects that command's output.
   (This is the existing "a mutation battery only covers what you mutate" rule in review SKILL.md.)
