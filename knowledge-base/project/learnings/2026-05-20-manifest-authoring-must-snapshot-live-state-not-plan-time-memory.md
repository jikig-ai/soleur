# Learning: GitHub App manifest authoring must snapshot live state, not plan-time memory

## Problem

PR #4121 (#4115) committed `apps/web-platform/infra/github-app-manifest.json` based on a plan-time mental snapshot of which permissions the live App had. The /ship Phase 7 Step 3.5 filed three follow-through issues (#4169 PM1, #4170 PM2, #4171 PM3) for first-tick attestation. PM1 was the load-bearing one — a literal byte-for-byte diff of live `GET /app` `.permissions` vs committed `.default_permissions` after `jq --sort-keys`.

The first-tick PM1 verification found drift: live App had `"secrets": "write"`; committed manifest did not. Manifest authoring had missed it. Without a fix-up PR + `MANIFEST_DRIFT_SUPPRESS_UNTIL` file, the next hourly `scheduled-github-app-drift-guard.yml` cron tick would have fired (mode `permission_unexpected_grant`, label `ci/guard-broken` — per `bin/diff-github-app-manifest.sh:78-79` and workflow:341-353).

## Solution

PR #4174 reconciled the drift with three surgical changes:

1. Added `"secrets": "write"` to `default_permissions` in the manifest (alphabetical tail).
2. Created `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` with a strict ISO-8601 UTC timestamp `2026-05-21T16:00:00Z` (24h window) to mute the cron during the reconciliation window. Workflow regex-validates the timestamp (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` at `.github/workflows/scheduled-github-app-drift-guard.yml:313`) and caps the window at 30 days; ignores invalid input (fail-open).
3. Updated `apps/web-platform/test/github-app-manifest-parity.test.ts` `EXPECTED_PERMISSION_KEYS` (the in-band stored-injection guard) to include `secrets`, and rotated the test comment's example "malicious" key from `secrets: "write"` to `packages: "write"` so the sentinel example still illustrates an undeclared permission.

Bonus: fixed a one-line docstring bug in `bin/snapshot-github-app.sh:17`. The example `doppler secrets get GITHUB_APP_PRIVATE_KEY ... | base64 -d > /tmp/app.pem` was wrong — the Doppler secret stores raw PEM. The CI workflow uses a DIFFERENT Doppler secret `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` (base64-encoded). Two secrets, two formats, same underlying key.

## Key Insight

**Source of truth for manifest authoring is the live App `GET /app` response at snapshot time — not the plan-time recollection of which permissions are granted.** The manifest format permits human-readable authoring (alphabetized keys, comments-as-fields), but `default_permissions` is a contract that GitHub's app-create form pre-fills from. Any drift between committed default_permissions and live App permissions is a future PR review trap: a future reviewer cannot tell whether the manifest was wrong from the start or whether a permission was deliberately removed.

**The first-tick PM-class attestation IS load-bearing.** PR #4121 added the drift-guard cron as the ongoing observability, but the FIRST post-merge tick is the canonical authoring-correctness signal. /ship Phase 7 Step 3.5's follow-through filing was the workflow gate that surfaced this drift one cron-window earlier than the cron itself would have. Without PM1, the drift would have surfaced 60-90 minutes post-merge as a `ci/guard-broken` issue, costing one extra triage hop.

**Doppler secret-naming proximity creates docstring-vs-code drift class.** Two related-but-different secrets (`GITHUB_APP_PRIVATE_KEY` raw PEM vs `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` base64-encoded) co-exist for the same App. A docstring that conflates them will eventually mislead an operator into running `base64 -d` against a raw PEM (producing garbage that openssl will reject with cryptic errors). Cheapest gate: when a docstring shows an example pipeline that decodes/transforms a secret, the example must match what the secret with THAT EXACT name actually stores. Mismatches surface only when an operator follows the docstring verbatim — at which point the JWT mint fails with an unhelpful openssl error.

## Process Pattern: Manifest-Class Drift Detection

For any future "committed config mirrors live external state" pattern (GitHub App manifests, Stripe Tax product catalogs, Cloudflare zone settings, Vercel project envs, etc.), the workflow should be:

1. **Authoring step:** Snapshot live state via a script (`bin/snapshot-<thing>.sh`). Commit the snapshot output AS-IS as the manifest. Don't hand-edit; don't reorder; don't drop fields that look "obviously not needed."
2. **Drift-guard cron:** Schedule a workflow that re-runs the snapshot script and diffs against the committed file. Mode-classify drift directions: `live > committed` (live has more — usually authoring miss), `committed > live` (someone added to the manifest without granting live — usually intentional future grant), `mutation` (both diverge — usually upstream change).
3. **First-tick attestation:** /ship Phase 7 Step 3.5 must file a PM-class follow-through for the FIRST drift-guard tick post-merge. Don't trust the cron alone to surface authoring misses — the cron's failure label routing is one extra hop.
4. **Suppress mechanism:** Provide a sidecar file that mutes the guard during reconciliation windows. Strict input validation (regex anchored on both ends, time cap, fail-open on invalid).

## Session Errors

1. **Subagent session-credit limit hit mid-Session-Summary emission.** The /soleur:one-shot planning subagent ran plan + deepen-plan, committed the initial plan (`b372cf2a`), and was emitting Session Summary text when the harness session-limit fired. The deepen-plan diff was uncommitted-on-disk; the parent had to detect the partial-artifact recovery condition and commit manually (`a90a0001`). **Recovery:** the partial-artifact recovery check at one-shot Step 2 (Fallback) caught the on-disk plan and pivoted to inline continuation. **Prevention:** Phase 4 entry-guard's exit-code-2 ("pause-and-commit") could be lifted to a subagent-side checkpoint — emit "## Session Summary" THEN commit, not the reverse. Worth a future skill instruction patch on `soleur:plan` Step 8 / `soleur:deepen-plan` to commit each enhancement section as it lands so a mid-flight crash doesn't strand work on disk.

2. **Bash tool does not persist CWD across calls.** A `cd apps/web-platform && ...` invocation followed by a subsequent `cd ..` chain ran from the worktree subdirectory `apps`, not the worktree root. **Recovery:** absolute paths via `cd /home/jean/.../<worktree>/<app> && <cmd>`. **Prevention:** already documented in compound's own Sharp Edges and in `soleur:work`'s pitfall list ("When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call"). Reinforce: this exact pattern of "chained cd then later relative cd" trips every few sessions; a Bash hook that strips `cd ..` when CWD is already a worktree subdir would be aggressive but reliable.

3. **`Edit replace_all` over-swept tasks.md.** Substituting `- [ ]` → `- [x]` matched every checkbox including operator-driven Phase 5 items (5.1-5.3) that weren't actually done. **Recovery:** manual revert of Phase 4.4 + Phase 5.x lines via a targeted Edit. **Prevention:** when a tasks.md has phase-class checkboxes (pre-merge vs post-merge vs operator), `replace_all` is the wrong tool; use targeted Edits per checkbox or per phase. Worth adding to `soleur:work` Phase 2 Step 7 ("Track Progress") as a Sharp Edge: "Don't `replace_all` on tasks.md when post-merge / operator-driven items exist — they're intentionally pending."

4. **`grep || true` inside `&&` chain still bailed the chain.** A chained verification command `[...] && grep -c -F '| base64 -d' file || true && [next AC]` exited the chain when grep returned 1 (no match = desired state). The `|| true` saved the grep step but the outer `&&` had already short-circuited. **Recovery:** re-ran AC 3.4 in a separate Bash call. **Prevention:** verification chains with negative-grep ACs need explicit grouping: `[...] && { grep -c -F 'pattern' file || true; } && [next]`. Worth a pitfall in `soleur:work` Phase 2 Step 5 ("Test Continuously") about bash-chain short-circuit on `|| true` inside `&&`.

## Tags

category: best-practices
module: github-app-manifest
related: 2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying, 2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts
