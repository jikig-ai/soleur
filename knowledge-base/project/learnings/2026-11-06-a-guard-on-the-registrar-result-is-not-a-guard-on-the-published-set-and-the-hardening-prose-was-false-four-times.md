# Learning: assert the published set, and treat hardening prose as a claim to falsify

## Problem

PR 12188 registered the approval-gated `github_push_branch` in the cc `soleur_platform` MCP server behind the
ADR-309 gate. Two defect classes recurred across the review panel, the fix round and the verification pass.

1. **The seam guard checked the wrong object.** `assertCcApprovalSetWired` validated what the registrar RETURNED. The
   dispatcher then appended that result to `approvalTools` / `approvalToolNames` and handed those to
   `createSdkMcpServer`. A second registrar appended later, or an exception between assignments, escaped the
   assertion. The first fix asserted the result; the structural seat found the published sets unguarded (P1 by the
   standing rule). Closing it took four moves: re-assert on the published sets immediately before
   `createSdkMcpServer`, reject duplicates, compute the fallible value (`ccPushPromptAddendum`) BEFORE the first
   assignment, and pin the one-server key set.
2. **The hardening prose overclaimed, in four successive forms.** "clears every HTTP proxy / extra-header knob",
   "closed by this PR", "the support-persona arm is the only thing keeping the write tool off a support dispatch"
   (it is the second of two guards; support resolves no installation upstream), and "none of the entries git reads
   or writes through may be a symlink" (`objects/pack` and the fan-out directories were unchecked). Each was refuted
   by one grep or one trace.

A third class sat in the tests: refusal tests that pass for the wrong reason (a symlink target holding an empty repo
makes `cat-file` throw the same typed error), a "no planted hook ran" test against an unreachable URL where the
unhardened form also leaves no marker, and an env-allowlist test whose permitted-key set was a hand copy of the
allowlist.

## Solution

- Guard the object the consumer reads, not the producer's return value; compute anything fallible before the first
  mutation so a catch has nothing to unwind.
- For every causal or universal sentence a hardening change adds, name the command that falsifies it and run it.
  Name the residual explicitly (`http.<url>.*`, `curloptResolve`, `sslVerify`, `pushInsteadOf`, `commondir`,
  `url.ext::`) instead of "everything".
- A refusal test must make the target contain the approved commit, so the only way to refuse is the check under test;
  assert the message and that nothing was spawned. Import the allowlist in its own test and set a canary for every
  secret the server holds.

## Key Insight

A fix commit is the least-audited surface in the diff: here each fix round reintroduced one overclaim of the class
it closed. The structural defence is to enumerate by CLASS (every site that asserts the claim; every consumer of the
set) and to put a negative assertion over the whole sequence, not to patch the instance the last seat named.

## Session Errors

1. **`decision-challenges.md` row lacked the `Ruled by CTO agent, <date>:` shape (gate FAIL).** Recovery: rewrote the
   row start; gate PASS. **Prevention:** copy the row shape from an existing ruled row before appending.
2. **Planning-subagent "waiting on own background work" notifications read as live work.** Recovery: confirmed the
   plan was complete and treated them as leftover timers. **Prevention:** one-off; check the plan file and
   session-state status before waiting.
3. **Registrar guard placed on the result, not the published set.** Recovery: re-asserted on the published sets with
   duplicate rejection and source pins. **Prevention:** the review checklist question "name the edit that reverts
   this central change and say which test reds" applied to every seam.
4. **Four rounds of false hardening prose.** Recovery: reworded at all sites, grep of the OLD claims. **Prevention:**
   run the falsifying command for each added causal sentence before commit (already in the work skill; this is a
   compliance miss, not a missing rule).
5. **Vacuous new tests (symlink refusal, unreachable-URL hook, env canary set).** Recovery: rebuilt with a
   commit-bearing target, a rejecting `pre-receive` remote with an unhardened control, and an allowlist-derived
   canary set. **Prevention:** every new refusal test pairs with a control that proves the refused action would
   otherwise succeed.
6. **Collision pre-check exit 10 hits were other worktrees' test runners.** One-off; reported and continued.
7. **Stop-hook feedback required explicit `Paused:` / `Blocked:` endings on non-final turns.** One-off; followed.
8. **`GIT_ALLOW_PROTOCOL=https` blocked the `file` transport the real-git tests push through.** Recovery: the tests
   wrap `buildHardenedGitEnv` to allow `file`; production value untouched. **Prevention:** when a clamp narrows a
   transport, list the test fixtures that rely on it before adding it.

## Tags

category: security-issues
module: apps/web-platform/server (cc-dispatcher, cc-github-push, push-branch, git-hardened-env)
