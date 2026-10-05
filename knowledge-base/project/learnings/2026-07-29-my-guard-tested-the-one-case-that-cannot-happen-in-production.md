---
title: "My guard tested the one case that cannot happen in production, and pinned the wrong pair against an automerging bot"
date: 2026-07-29
category: test-failures
module: apps/web-platform/scripts
issue: 7007
tags: [mutation-testing, vacuity, anti-vacuity, guard-design, tar, exit-status, renovate, drift-guard, bash]
---

# My guard tested the one case that cannot happen in production

> **SUPERSEDED IN PART, 2026-08-05 (#7282).** This document states that `renovate.json5`
> enables the `dockerfile` manager and extends `default:automergeDigest` + `platformAutomerge`,
> and its Prevention section instructs the reader to *"check `renovate.json5` for whether a bot
> mutates it."* **Renovate has never run against this repository** — zero Renovate-authored PRs
> in its entire history, no Dependency Dashboard issue — so the config was inert and #7282
> deleted it. The reasoning below is sound and worth keeping; only the mechanism is wrong, and
> it inverts rather than disappears: with nothing moving the leader, the risk is not a fast
> automerged bot bump outrunning its followers, it is **the whole set rotting in agreement**,
> which strengthens the case for leader-anchoring. When applying the Prevention step, ask "what
> moves this leader, if anything?" rather than grepping a file that no longer exists.
> See the ADR-096 "Pin freshness" amendment.

## Problem

#7007 asked for a one-line perf fix: two in-image container verifiers ran `cp -r /src /build`,
dragging ~2 GB of `node_modules` and a 247 MB `.terraform` cache into a build dir that `npm ci`
immediately rebuilds. I falsified the issue's proposed `GLOBIGNORE` mechanism (it cannot express a
nested exclusion), replaced it with a shared `tar --exclude` script, and shipped a hermetic suite
plus a mutation proof.

Ten review agents found **four P1s. None was in the copy mechanism** — the exclusion semantics were
independently confirmed exact against the real tree (`tar member set 2978 == expected 2978`). Every
P1 was in the **guards**, on a PR whose entire safety story is the guards: neither CI gate's trigger
regex names these files, and a cold CI checkout has neither excluded directory, so **CI is
structurally incapable of observing a regression here**. The suite is the only detector that can
ever fire.

## Root cause

Two novel failure shapes, plus two recurrences of already-documented classes.

### 1. The discriminating test case was unreachable in the shipping environment

My assertion 5 proved `set -o pipefail` load-bearing by planting a `chmod 000` file: producer tar
exits 2, the guard fires. It ran green, it was mutation-proven, and it SKIPs as root — which I
wrote, and which should have been the tell.

**Production runs as root.** Root reads everything, so the unreadable-member case cannot occur
there. The guard was never exercised in the environment where it ships.

Worse, GNU tar **overloads its exit status**, and the class that *is* reachable as root has the
opposite meaning:

```
2 = ERROR    unreadable member, truncated archive  -> DEST incomplete, refuse
1 = WARNING  "file changed as we read it"          -> DEST COMPLETE, member may be torn
```

My `if ! tar | tar` collapsed both into `exit 1` + *"refusing to verify a truncated tree"*. So the
only reachable class produced a **false FATAL on a complete copy** — and `/src` is read-only to the
*container*, not the host, so any editor autosave, `tsc --watch`, or even a file deletion (which
bumps the parent directory's mtime) during the ~0.44 s window would redden the gate on the
operator's warm tree: the one machine the optimisation exists for. `cp -r` tolerated all of it.

The plan predicted this as a risk and dismissed it with *"cannot occur in CI"* — true, and
irrelevant, because CI is exactly where the change is inert. It also declined
`--warning=no-file-changed` as "unverified"; measured, that flag suppresses the **message** and
leaves the status at 1, so it could never have worked.

### 2. The guard pinned the two followers and left the leader unpinned

Both helpers carry `# Pin to the same base as apps/web-platform/Dockerfile`. I read that as
"helpers must agree" and wrote a helper-vs-helper digest comparison. The comment names a **leader**.

```
Dockerfile:2, :42   node:22-slim@sha256:...   <- LEADER, bumped by Renovate + AUTOMERGED
helper H1:30        node:22-slim@sha256:...   <- follower
helper H2:30        node:22-slim@sha256:...   <- follower
```

`renovate.json5` enables the `dockerfile` manager (`managerFilePatterns: ["(^|/)Dockerfile$"]`) and
extends `default:automergeDigest` with `platformAutomerge: true`. The two `.sh` helpers are outside
every configured manager. So the only drift that can occur — bot bumps the Dockerfile, automerges,
helpers stay stale — leaves **both followers equally stale and the guard green**, silently breaking
ADR-079's `capture-env == replay-env == deploy-image` invariant that these helpers exist to enforce.

Review also showed the guard was weaker still: putting bare `node:22-slim` on the `IMG=` line while
leaving the old digest in a comment passed, so a helper could become **fully unpinned** with the
guard green. It asserted "both files contain equal digest strings somewhere", not "both are pinned".

### 3–4. Two recurrences of documented classes

- **A PR that builds a verifier fails open in the verifier, and a self-run mutation battery is a
  floor.** Mine was ONE mutation; review found eight survivors, including a full revert of the
  optimisation passing 8/8 (`grep -qF` matched comments, and my own file carries the invocation
  literal as usage text — I wrote the template for defeating my own guard) and the absence of any
  assertion that the assertions RAN (deleting every block: `0 passed, 0 failed`, exit 0).
- **A mutation that lands on the comment documenting a construct reports a fabricated survivor.**
  My battery reported one survivor; inspection showed the replace had hit the explanatory paragraph,
  not the code — and my `diff -rq` landing check passed *because the file differed*.

Both are already documented in `plugins/soleur/skills/review/SKILL.md`. Recurrence is the finding.

## Solution

Discriminate on tar's status instead of collapsing it, capturing `PIPESTATUS` as a **whole array**
(reading one element is itself a simple command that resets it — I shipped that bug into my own
first draft and it was caught only by running all four cases):

```bash
set +e; set +o pipefail
tar -C "$SRC" --exclude=./node_modules --exclude=./.next --exclude=./out --exclude=.terraform \
  -cf - . | tar -C "$DEST" --no-same-owner -xf -
rc=("${PIPESTATUS[@]}")
set -e; set -o pipefail

if [ "${rc[1]}" -ne 0 ] || [ "${rc[0]}" -ge 2 ]; then
  echo "FATAL: in-image copy failed ($SRC -> $DEST) - refusing to verify a truncated tree" >&2
  exit 1
fi
[ "${rc[0]}" -eq 1 ] && echo "WARN: $SRC changed during copy; $DEST is complete" >&2
```

Pinned by a **stubbed-`tar`** assertion (producer distinguishable from consumer by `-cf` vs `-xf`)
so both classes are deterministic and neither skips as root — only the external tool is faked, the
script under test is the real shipped artifact.

The digest guard now extracts from the **Dockerfile plus each helper's `IMG=` pin line**, requires
**exactly one** digest per helper, and `sort -u` must yield one.

Added: a `MIN_ASSERTIONS` floor (a floor, not equality; SKIP counts so the root path degrades
observably); comment-blind call-site matching with a ban on any `cp`/`rsync` touching `/src`;
membership assertions for the over-reach sentinels (a cardinality floor alone lets a sentinel be
swapped for an ordinary file); a symlink survivor pinning tar's non-dereferencing.

## Key insight

**Ask which of your test's cases can actually occur in production — not just whether the test
passes.** A green, mutation-proven assertion that exercises an environment-impossible case leaves
the reachable case untested, and the reachable case is where the failure direction matters. The tell
was in my own code: I wrote `SKIP as root` and did not ask what *else* runs as root.

**A "keep in sync with X" comment names X. Pin against X, not against the other followers.** And
check whether X has an automated mutator — a bot that bumps the leader and automerges converts
"unlikely drift" into "the only drift that can occur", against which a follower-vs-follower guard is
green by construction.

**A file-level landing check cannot validate a mutation.** `diff -rq` passing means *something*
changed; for any construct you documented nearby, the first occurrence is the comment. Assert the
anchor occurs exactly once, and treat a baseline-identical result as UN-RUN, never as evidence.

## Prevention

- Post-fix battery: **16 RED + 1 documented GREEN**, each verified landed against a pristine backup,
  against a green sandbox baseline. The GREEN is `--no-same-owner`, which a non-root suite is
  structurally unable to pin — now stated in both the script and suite headers rather than implied
  by a green run.
- For any guard, name the environment it runs in and enumerate which of its cases are reachable
  there. If the discriminating case is not, add a root-independent test (stub the external tool).
- For any "keep in sync" guard, grep the named leader and ask what MOVES it, if anything.
  (SUPERSEDED 2026-08-05 / #7282 — see the note at the top of this file: the original wording
  said "check `renovate.json5` for whether a bot mutates it", and that file no longer exists
  because Renovate never ran here. "Nothing moves it" is a real answer, and the more dangerous
  one.) The original wording, kept for the record: check `renovate.json5` for whether a bot
  mutates it.

## Session Errors

**1. `gh issue create` denied for missing `--milestone`.** Recovery: re-ran with `Post-MVP / Later`.
**Prevention:** none needed — the hook worked as designed.

**2. `rm -rf` denied twice on worktree paths (relative, then absolute).** Recovery:
`find <dir> -mindepth 1 -delete` + `rmdir`. **Prevention:** the guardrail is correct; the workaround
belongs in skill notes so the next session does not burn two calls rediscovering it.

**3. `git push` rejected non-fast-forward.** I rebased onto `origin/main` after the draft PR was
already pushed. Recovery: verified the remote carried only my own commits, then `--force-with-lease`.
**Prevention:** rebase before the draft PR exists, or expect the force-push.

**4. `bc: command not found` in `node:22-slim`.** The A/B timing silently produced empty values.
Recovery: bash integer arithmetic on `date +%s%N`. **Prevention:** slim images have no `bc`; use
shell arithmetic when measuring in a container.

**5. `/tmp` tmpfs hit 100% (ENOSPC) and a command's output was lost.** My own 120 MB fixtures filled
it. Recovery: cleaned only my own fixtures, moved to `/var/tmp`. **Prevention:** benchmark fixtures
go to `/var/tmp` (disk), never the 4 GB shared tmpfs — a heredoc there silently yields a 0-byte file
with exit 0.

**6. Foreground `test-all.sh scripts` timed out at 10m under sibling contention.** Two other
worktrees were running the same suite. Recovery: relaunched detached with an explicit rc file +
Monitor. **Prevention:** run the shard detached from the start when `git worktree list` shows
siblings; read the rc FILE, never the background task's exit code.

**7. Four mutation anchors failed to match (`\\` escaping through bash → python).** Recovery:
shorter unique anchors. **Prevention:** none — this is the strict-anchor assert working correctly,
refusing to produce a verdict rather than silently mutating the wrong text.

**8. My mutation battery reported a FABRICATED survivor.** The replace landed on the comment, not
the code. Recovery: inspected the survivor instead of accepting it; re-ran with exactly-once
anchors, it goes RED. **Prevention:** assert the anchor occurs exactly once before replacing; a
file-level `diff` is not a landing check.

**9. `PIPESTATUS[1]: unbound variable` in my own proposed classifier.** Reading `${PIPESTATUS[0]}`
into a variable resets the array. Recovery: whole-array capture. **Prevention:** capture
`rc=("${PIPESTATUS[@]}")` in one assignment, always.

**10. I added `.next`/`out` exclusions without matching over-reach sentinels.** My own battery caught
it (`next_unanchor` survived). **Prevention:** every new exclusion needs a nested survivor in the
same commit — the exclusion and its over-reach guard are one unit.

**11–14. Four P1 guard defects found by review** (leader/follower digest; decoy-comment revert;
no assertion-count floor; tar status conflation). **Prevention:** documented above as the key
insights; the recurrence of two already-documented classes argues for a mechanical gate.

**15. Three false claims shipped in prose** — stale perf figures in the shipped code header,
`(exit 2)` where the code says `exit 1`, and `~57×` / "interleaved" / `perf(ci)` (the win is local;
CI is perf-neutral within noise). **Prevention:** sweep by CLAIM, not by file — I corrected the
figures in two spec docs and missed the code header, then wrote a containment sentence asserting
the figures lived "only in the plan document", which was false as written.
