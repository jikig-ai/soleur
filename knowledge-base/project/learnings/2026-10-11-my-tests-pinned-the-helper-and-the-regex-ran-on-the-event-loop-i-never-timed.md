# Learning: a guard's helper was pinned, its input bound was not, and its premise had moved

## Problem

PR #10043 (Ref #9860) added a Sentry mirror for Bash `tool_result` sandbox denials plus a docker regression suite for the sandbox `/proc` mask. Six review seats found four defects that a green local battery had not:

1. **Quadratic scrub on tenant-controlled text.** `WORKSPACE_PATH_RE` ran on a line that only needed `bwrap` and `EPERM` somewhere in it. 100k slash-heavy characters took 17 s (38 s for `"/"` x 100k), on the Node event loop shared by every tenant. `try/catch` bounds exceptions, not time, and the `.slice(0, 300)` ran after the scrub.
2. **Untagged Sentry event.** `mirrorWithDebounce(new Error(...))` makes the pino mirror capture the Error first as `feature=pino-mirror` with no user, and Sentry drops the tagged second capture (#8629). The unit test mocked `mirrorWithDebounce`, so it could not see this.
3. **Unpinned call site.** Replacing the only production call with `void 0` left 21 tests green.
4. **Control arm without a positive control.** "Real bwrap is refused under docker's masks" is satisfied by any EPERM (AppArmor, seccomp), so it did not prove the mask was the cause.

Separately, the plan's premise had gone stale: PR #10039 merged mid-session and fixed #10032 a different way. I did not re-read `origin/main` history when `work` started, so the first implementation (the `systempaths=unconfined` flag) was built, measured, and then re-scoped.

## Solution

- Cap each line (2000 chars) before any regex; scrub with linear regexes (every absolute path token, anchored on a token boundary with a lookbehind, so bwrap's own `/newroot/{proc,dev,sys,tmp}` targets survive); add a hostile-line timing test.
- Pass `null` plus `message` to the mirror; add a test through the real `reportSilentFallback` asserting tags, user and absence of a `pino-mirror` capture.
- Pin the call site with a comment-stripped source assertion that the call exists once and precedes the posture gate.
- Add the positive control (same argv, masks lifted, must succeed) and pin the Dockerfile `COPY` that installs the shim.

## Key Insight

For every function that runs on a shared loop over text a tenant controls, the property to pin is a *time bound over the worst input*, and the bound must sit upstream of the first regex. A helper test, a mocked emitter and a mutation battery run by the author all observe the helper; none observe the wire to its caller or its worst-case cost. Same family as `2026-05-29-blocking-gate-fail-closed-key-parse-and-redos-line-cap.md` and `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`: the recurrence is the finding, so the review seat that times the regex is the standing check, not memory.

## Session Errors

- **Stale premise: #10039 landed mid-session.** Recovery: re-scoped with the operator (option A). **Prevention:** at `work` start run `git log --oneline origin/main -20 -- <files in the plan>` and `gh pr list --state merged --search <issue>`; the `plan` Phase 0.6 premise check does not re-fire after a long gap.
- **Quadratic scrub shipped to review.** Recovery: line cap plus linear regexes. **Prevention:** time any new regex on tenant text with a 100k-char hostile line before the first commit; the timing test now lives in `sandbox-startup-classifier.test.ts`.
- **Real Error passed to the Sentry mirror (#8629 class).** Recovery: `null` plus `message`. **Prevention:** a mirror test must run the real `reportSilentFallback`, not a mocked debouncer.
- **Control arm without a positive control.** Recovery: added. **Prevention:** a negative-control assertion needs a paired arm that removes only the suspected cause and must flip.
- **Stub-passing mutant (`no-replay`) survived the first battery.** Recovery: non-vacuity now requires `"reason":"ok"` and the fixture's `sdkVersion`. **Prevention:** an assertion satisfiable by a stub that prints the token is not an assertion.
- **Wrong jq field case; doubled `doppler run`; `git stash` and `pkill -f` blocked by hooks; Write refused on stale files; `MIN_ASSERTIONS=9` above the reachable 8.** One-offs, each self-corrected in one step (hooks and read-before-write already enforce the rest).

## Tags

category: logic-errors
module: apps/web-platform/server/sandbox-startup-classifier, cc-dispatcher, infra/sandbox-masked-proc-docker.test.sh
