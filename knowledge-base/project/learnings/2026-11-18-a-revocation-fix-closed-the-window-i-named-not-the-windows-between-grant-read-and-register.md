---
title: A revocation fix closed the window I named, not every window between grant read and register
date: 2026-11-18
category: security-issues
module: apps/web-platform/server (egress-forwarder, cc-dispatcher, permission-callback)
tags: [revocation, race, consent, sandbox-network-access, review-fix-round, cla]
issue: 12585
pr: 12897
---

# Learning: a revocation fix closed the window I named, not the windows between grant read and register

## Problem

PR #12897 added a deny-only `SandboxNetworkAccess` arm. Turning web access off tears down the workspace's egress forwarders. The full review panel found two problems.

- **The grant was a snapshot.** `webEgressGranted` was read when the session was dispatched. After a toggle-off, every deny still said "web access is on but isn't working", and it paged the degraded-egress alert.
- **A spawn race.** If the toggle-off landed while a spawn was starting, the forwarder outlived it.

The CTO ruled on both. R1: a toggle-off marks the conversation revoked. R4: a per-workspace epoch that the spawn re-checks.

I applied R4 inside `spawnEgressForwarder`: read the epoch when the spawn starts, and re-check it after registering and after the bind. The targeted fix round then found four more windows on the same consent path.

1. **The epoch was read too late.** About 22 awaits sit between the dispatcher's grant read (`resolveWebEgress`) and the spawn, including the repo clone. A toggle-off in that gap still produced a live forwarder.
2. **Aborts were not marked revoked.** If the toggle-off landed during the gateway probe, nothing was registered yet, so the conversation was never marked. Those denies paged as degraded: the original K1 defect, inside the R4 window.
3. **A stale mark could hide a real failure.** The mark was cleared only by a successful spawn. Toggle off, then on, then a failed spawn: the arm reported "turned off", and the alert stayed silent for a real outage.
4. **One teardown path never marked.** The warm re-resolve also tears down (it sees the other web host's toggle-off), and it did not mark the conversation.

Two of my own fixes were also defective.

- **The post-register check could crash the process.** It threw before the child process's `error` listener was attached, so a late async spawn error would go unhandled.
- **The post-bind teardown hit the wrong forwarder.** It was not identity-guarded, so it could kill a newer spawn's forwarder.

## Solution

- Read the epoch next to the grant read and pass it into the spawn (`egressRevocationEpoch`, `spawnEgressForwarder(conv, ws, epochAtGrant)`). The spawn checks it at start, after the gateway probe, and on a failed bind (a toggle-off kills the registered child, so the bind fails).
- Every revoked abort marks the conversation, but only when no newer spawn owns the registry entry. It throws a typed `EgressRevokedError`, which the dispatcher logs at info with no Sentry event: turning web access off is the owner's choice, not a failure.
- A spawn attempt clears an old mark, and so does a successful spawn. A superseded older spawn may have marked the conversation while the newer one was starting.
- Every teardown that withdraws consent marks the conversation: the toggle route and the warm re-resolve.
- Each epoch window is pinned on its own. A slow fake forwarder writes a marker file when it starts and binds 600 ms later. This separates "the process never started" (check 2) from "it started and was killed during the bind" (check 3). Before this, disabling any single check left the suite green.

## Key Insight

A consent-revocation fix has to cover the whole interval from where consent is READ to where the resource is REGISTERED. Covering only the awaits inside the function being fixed is not enough. List every await on that path, and every teardown site that can withdraw consent, before writing the fix. A ruling that says "re-check after X and after Y" names the windows the reviewer saw, and that is not the complete set. The same applies to a revoked flag: list every path that sets it, every path that should clear it, and every path that aborts and should set it.

## Session Errors

1. **Commit 76ac3b2672 had author and committer `t@t`, so the CI `cla-check` failed.** Recovery: `git filter-branch --env-filter`, rewriting only `t@t` to the configured identity, then a force-push with lease. The panel sha moved from 5272dd01fc to 69009ccbdf. The only `t@t` writers in the repo are hook-test temp repos (`.claude/hooks/*.test.sh`, `git config user.email t@t` inside a subshell). How it reached a real commit is UNVERIFIED. **Prevention:** `cla-signed-author-gate.sh` already blocks `gh pr ready` and `gh pr merge`. Before the first push, also run `git log origin/main..HEAD --format='%ae %ce' | sort -u` and stop on any address that is not the configured `user.email`.
2. **Two Bash calls containing `git stash list` were blocked by the stash hook.** Recovery: re-ran without it. **Prevention:** already hook-enforced. Never put a `git stash` token in a probe, even a read-only one.
3. **Multi-edit Python scripts aborted on their first failed assert.** The edits after it never ran, and nothing said so. The route-comment edit was missing until `git status` showed the file unchanged. **Prevention:** after any scripted multi-file edit, check that `git status --short` lists every file you meant to touch. Or give each file its own script.
4. **An edit anchor typed an ASCII `K` where the source held the literal Kelvin sign U+212A**, so the assert failed. **Prevention:** anchor on a line substring (`"before lowercasing" in line`) when the source may hold non-ASCII lookalikes.
5. **The R1 and R4 fixes covered only the windows the ruling named.** The fix round found four more (see Problem). **Prevention:** see Key Insight. A plan-sharp-edges bullet was added.
6. **One of my fixes threw before the child's error listener was attached** (a process-crash class). **Prevention:** in a spawn helper, never throw between `spawn()` and the point where its `error` and `exit` listeners are attached. Put the check before the spawn or after the listeners.
7. **An earlier affected-gate run exited 124 (timeout).** It was recorded as NOT a pass, and CI is the gate. **Prevention:** run it with `run_in_background` and a long timeout. Never read an RC of 124 as green.
8. **The first scan-gate run returned `refuse`.** I had invoked the bare-root copy, so ROOT resolved to the bare repo. Recovery: ran the worktree copy. **Prevention:** inside a worktree, run review scripts from the worktree path.
9. **A vitest `--changed` run failed `broker-mechanism-spike.test.ts` under load.** It passed standalone, so the cause was contention. **Prevention:** one-off. Re-run standalone before treating a failure as a regression.
10. **I consolidated the fix-round seat set.** `fix-round-seats.sh` resolved about 12 seats. I ran 5 agents covering those lenses plus 1 verifier. The lead quoted the semgrep and shellcheck receipts and ran gdpr-gate. Disclosed in the Review-Evidence comment. **Prevention:** where seats are merged, name each lens a merged seat covered.

## Tags
category: security-issues
module: web-platform egress forwarder / canUseTool
