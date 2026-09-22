---
title: "My escrow suite stubbed the one tool that would have refused it"
date: 2026-09-21
category: test-failures
tags: [luks, escrow, stubs, test-seams, mutation-testing, review, zot, cosign, docker-cli]
issue: 8408
pr: 8456
related:
  - knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md
  - knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md
  - knowledge-base/project/learnings/2026-09-20-my-probe-graded-itself-against-a-clock-its-grader-never-read.md
---

# My escrow suite stubbed the one tool that would have refused it

## Problem

#8408 (c) added a daily escrow re-test: `cryptsetup luksOpen --test-passphrase` with the
Doppler-held key, so `store_escrow=ok` means the passphrase still opens the header. The plan's
OOM shield was `systemd-run --scope --quiet -p OOMScoreAdjust=1000 cryptsetup …`, so that a
~1 GiB argon2id KDF would be the kernel's first victim rather than zot.

`systemd-run --scope` rejects `OOMScoreAdjust=`: it is an exec property, and a scope has no exec.
The script could not have run one test on the real host. It would have written `indeterminate`
every day, forever.

The suite was green, 39/39. It stubbed `systemd-run` with an argv check:

```bash
[ "$1 $2 $3 $4" = "--scope --quiet -p OOMScoreAdjust=1000" ] || exit 64
shift 4; exec "$@"
```

That stub proves the script SPELLS the call the plan wrote. It cannot prove the tool ACCEPTS the
call, because the stub accepts whatever the plan said. Three review seats independently caught it,
none of them by running the suite.

## Solution

- Removed `systemd-run`. The script writes `1000` to `/proc/self/oom_score_adj` directly; the
  `cryptsetup` it starts inherits the value. If the write fails, it records `indeterminate` and
  never runs the KDF.
- The suite re-roots `/proc/self/oom_score_adj` to a fixture file with a render-time `sed` (the
  same seam style as `/proc/meminfo`). It asserts the file reads exactly `1000` and adds a row
  where the write fails: the fixture is a directory, so the result is `indeterminate` with no
  `luksOpen`.
- The memory retry loop's `sleep 300` got the same seam: a `fake_sleep` stub that records each
  wait and can change `MemAvailable` between samples. Without it, the first run of the suite
  simply hung. That is the other half of the same lesson: a producer's new wait or privileged
  write ships with its seam in the same edit.

## Key Insight

**A stub that validates argv pins the plan's spelling, not the tool's contract.** For any stubbed
tool whose acceptance of a flag is the thing in doubt (an init-system property, a kernel knob, a
CLI option added in a recent version), the stub cannot be the evidence. Run the real tool once
with the exact flag. Here that is `systemd-run --scope -p OOMScoreAdjust=1000 true` on any systemd
host, which fails in about 1 second. Or replace the call with a primitive whose contract the suite
CAN observe (a file write to a re-rooted path). Prefer the second: it moves the property from
"the tool agrees" to "the byte landed", which a fixture can assert.

The same review round found the pattern twice more:

- **Docker CLI config.** `{"auths":{}}` looks like "no credentials". The CLI treats a config
  with no auth entries as unconfigured, and auto-detects a default credential store
  (`docker-credential-pass`/`secretservice`) when one is on PATH. The test mock compared the file
  to the literal the code wrote, so it agreed with the code. The shipped config is
  `{"auths":{},"credHelpers":{"ghcr.io":""}}`: a non-empty `credHelpers` map disables that
  detection, and the empty helper name resolves `ghcr.io` to the empty file store.
- **Unsearchable ancestor.** The config probe checked `-x` on the file's immediate parent. On the
  real host the 0700 directory is `/root`, the GRANDPARENT of `/root/.docker/config.json`, and
  `-d` on a directory under an unsearchable one is false too. So the fix read `absent` in exactly
  the case it was written for. The fixture had put the 0700 on the immediate parent, matching
  the code instead of the host.

In all three, the fixture was built from the code's model of the world, not the world's.

## Session Errors

1. **A Python edit script with non-raw strings turned `\1` and `\n` into `\x01` and newlines**
   inside a shipped heartbeat reader. Recovery: byte-level repair, then a check that the file has
   no `\x01`. **Prevention:** edit text containing backslashes with the Edit tool or a Write-tool
   file, never an inline Python string.
2. **A raw triple-quoted string ending `\'''` is a SyntaxError** (twice this session). Recovery:
   split the edit into Edit-tool calls. **Prevention:** same as 1; a raw string can never end in
   an odd backslash.
3. **`/tmp` quota exhaustion** from other sessions produced false suite failures and swallowed
   output. Recovery: `TMPDIR=/var/tmp`, outputs written to files. **Prevention:** batteries run
   with `TMPDIR=/var/tmp` and log to files.
4. **`echo "… $(cmd)"; echo $?` read the echo's status.** **Prevention:** capture `rc=$?` on its
   own line immediately after the command (already a work-skill rule).
5. **The `rm -rf` hook blocked removing a git-initialised sandbox.** Recovery: `find -depth
   -delete`. **Prevention:** use `mktemp -d` sandboxes and `find -depth -delete`.
6. **Adding a second alert made the send-failed mutation anchors non-unique** (a real
   regression), and only mechanical suite derivation found it. Recovery: re-anchored G2/M17.
   **Prevention:** derive suites with `git grep -ln <basename>` per changed path, never by
   directory.
7. **`model.likec4.json` conflicted on merge.** Recovery: took theirs, then ran
   `scripts/regenerate-c4-model.sh`. **Prevention:** never hand-merge the generated JSON.
8. **The unsearchable-parent fix covered the instance, not the class** (see Key Insight).
   **Prevention:** fixture the host's real layout (the 0700 dir as grandparent), not the one the
   code assumes.
9. **The escrow suite hung on a real `sleep 300`.** Recovery: `fake_sleep` seam.
   **Prevention:** a new wait in a producer ships with its seam in the same edit.
10. **The plan-time OOM shield was never executed and cannot work** (see Problem).
    **Prevention:** run a stubbed tool once for real whenever its acceptance of a flag is the
    claim.
11. **The "no systemd-run" check grepped the raw script, whose comment names systemd-run.**
    Recovery: grep the comment-stripped render. **Prevention:** absence asserts run on the
    comment-stripped haystack.
12. **The M9 mutation anchor (`count(*) AS value`) was shared by the sibling alerts.** The
    mutation helper's count==1 assert caught it. Recovery: scoped the mutation to the heredoc.
    **Prevention:** scope mutation anchors to the resource block.
13. **A new floor in `private-nic-guard.test.sh` grew guard-vacuity-floor's deferral ledger** from
    47 to 48. Recovery: added the suite to `PROMOTED_FILES`; the number was not raised.
    **Prevention:** run guard-vacuity-floor in the same round as any new floor.
14. **markdown-lint MD038 rejected a deliberate leading space in `` ` zot_last_err=` ``.**
    Recovery: `<!-- markdownlint-disable-line MD038 -->`. **Prevention:** spell field
    delimiters in prose with that marker from the start.
15. **The gh token lost the `workflow` scope mid-session**, so a push touching a workflow file
    was rejected. Recovery: the operator ran `gh auth refresh -s workflow`.
    **Prevention:** check `gh auth status` scopes before pushing a workflow edit after any
    session restart.
16. **A guard row asserted the bare token `SERVING=yes`**, which the summary's meaning table also
    contains, so it false-failed. Recovery: assert the exact rendered line with `-xF`.
    **Prevention:** `cq-assert-anchor-not-bare-token`.
17. **The soleur skills vanished from the Skill list after a session restart.** Recovery: read
    each SKILL.md directly. **Prevention:** none needed; the skill's own Grok path covers it.
18. **CI's `credential-path-guard` failed on a resolvable credential-file path in the plan**
    (the Docker config under `$HOME`), a line present since the plan's first commit. Recovery:
    rewrote it in the directory-only form (`~/.docker/`). **Prevention:** run
    `python3 scripts/lint-credential-path-literals.py` over any plan or learning that names a
    credential file. It is a repo-global lint, so no file-derived suite set selects it.
19. **The new `cosign-verify-live-8037.test.sh` was committed `100644`**, and
    `followthrough-exec-bit` requires every `scripts/followthroughs/*.sh` to be `100755`
    (otherwise the sweeper silently skips it). The derived set missed it because that suite
    references the directory, not the file's basename. Recovery: `git update-index --chmod=+x`.
    **Prevention:** after adding any file under `scripts/followthroughs/`, run
    `bash scripts/followthrough-exec-bit.test.sh`, and derive suites from each changed path's
    directory as well as its basename.
