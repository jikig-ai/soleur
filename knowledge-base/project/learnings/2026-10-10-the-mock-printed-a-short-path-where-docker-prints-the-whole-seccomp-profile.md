# Learning: the mock printed a short path where docker prints the whole seccomp profile, and eight review seats found the same defect

## Problem

PR #9884 added a read-only diagnostics bundle (`SOLEUR_CANARY_SANDBOX_DIAG`) to the production deploy script so the next failing canary names its own
root cause (#9871 closed, #9860 open). It was written, mutation-tested and green (29 new rows, floor raised) before review. Twelve review seats then found:

1. **The `host` row was unreadable on real docker.** The canary starts with `--security-opt seccomp=<file>`, and the docker CLI inlines the whole ~12 KB
   profile into `HostConfig.SecurityOpt`. The row was `capadd=… secopt={{.HostConfig.SecurityOpt}} priv=… aa=… | head -c 600`, then the scrubber keeps the LAST 200
   characters, so the output was a fragment of profile JSON and `capadd`/`capdrop`/`priv`/`aa` (the whole H5 hypothesis) were gone. **Eight seats** reported it.
   The mock `docker inspect` returned `seccomp=/etc/docker/…json` (a path), and the one row that read the field only grepped the prefix `val="capadd="`.
2. **The in-container script was never executed by any test.** Gutting it to `echo gutted` left 29/29 green; the mock returned a canned body whose format had drifted
   from the script's real output (`caps none count=0` vs `caps bwrap=none others_in_usr=0`).
3. A dead state latch (`CANARY_DIAG_EMITTED`) with a vacuous row, a discarded `docker exec` exit status (so "ran and found nothing" looked like "never ran"),
   unbounded host-side docker calls on the rollback path, a `direct_probe` that is predetermined green under the faithful trigger, a runbook with no H1-H5
   table and a wrong reading of `caps`, and a clamp bypassed by 64-bit wraparound.
4. **Round 2** (the fix round) found that my fix to (1) was itself pinned by a substring: the rewritten mock keyed on `*'printf "%.'*` and returned a hard-coded
   40-character form, so cut widths 5, 400 and 0, a comment-wrapped `printf`, and an appended `{{json .Config}}` (a credential leak path) all stayed green.
5. **The gate (not the slice) caught two repo-global ratchets** my new rows tripped: `grep-q-pipe-guard` (189 hits against a ceiling of 180, from `producer | grep -q`
   in the new rows) and `lint-shell-capture-exit` (4 unprotected captures).

## Solution

- Make the mock model the vendor's real response contract: it now PARSES the `docker inspect -f` template (every `{{field}}` must be one the bundle may read;
  the SecurityOpt range cuts at the width the template names; a bare range returns the inlined 12 KB form). A template that bundles posture with a bare
  SecurityOpt loses its tail in the test exactly as it does in production.
- Split the row so every field fits the scrubber's 200-char tail (`host` = four short posture fields, `hostsec` = each SecurityOpt entry cut to 40 chars),
  and end the bundle with a `done` row carrying the exec's own exit status, line count, cap flag and byte count.
- Execute the REAL container script in a row (under `sh` and `bash`), and pin the mock's default body and that run to ONE shared section list so the mock
  cannot drift.
- Bound every host-side docker call (`timeout 3`), the exec (`timeout -k 3`), clamp the knob to 60 with a length-bounded regex, allowlist the in-container section
  names so only the emitter can mint `host`/`hostsec`/`kernel`/`done`, and remove the latch.
- Convert every new `producer | grep -q` to a here-string helper (`has_f`/`has_e`) and put `|| true` on the four captures.
- Verify each new pin by mutating it out in an allocated sandbox: 16 (round 1) + 17 + 9 + 1 mutations, each killed by the row named for it.

## Key Insight

**A mock that returns the shape the author was thinking about makes every assertion above it a statement about the mock.** Here the author's picture was
"`SecurityOpt` holds the profile *path*", and the production value is the profile *body*. Eight independent seats converged because each read the same one-line
template and asked what docker prints for it, which no amount of mutation of the implementation can ask: the SUT was behaving exactly as written. The cheap
instrument is a single question per mock, asked at write time: **"what does the real vendor print for this exact input, and is that in my mock?"** — answered by
running the real command once (or reading the repo's own prior note: `audit-bwrap-uid.sh` already documented the inlining, 40 lines from the code I wrote).

Two corollaries, both already documented elsewhere and both recurred here:

- A fix to a vacuous assertion is vacuous the same way at least as often as not (the round-2 mock keyed on a substring). Prove each new pin in BOTH directions by
  mutating it out in a sandbox.
- A file-selected suite set cannot see a repo-global ratchet (this was the fourth measurement). The two ratchets that failed here run in
  `test-all.sh --affected` but in no pre-commit hook.

## Session Errors

- **Mock modelled a short path where docker prints the profile body; the `host` row shipped unreadable.** — Recovery: the mock now parses the template; row split. —
  **Prevention:** at write time, run the real vendor command for the exact input once and paste its shape into the mock; for any `-f`/`--format` template, a
  template-aware mock (unknown field = error).
- **Slice iteration missed two repo-global ratchets (`grep-q-pipe-guard` ceiling, `lint-shell-capture-exit`).** — Recovery: the affected gate named them; fixed
  inline. — **Prevention:** (null guardrail, unwired) run `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` and
  `bash .claude/hooks/grep-q-pipe-guard.test.sh` whenever a `*.test.sh` is in the diff, before committing; wiring both into the existing lefthook pre-commit for
  staged `*.test.sh` is the proposal (not applied here: different subsystem, needs its own PR).
- **`# shellcheck disable=SC2163 -- reason` is unparseable (shellcheck 0.11).** — Recovery: repo convention `disable=SCxxxx  # reason`. — **Prevention:** use the
  in-repo directive form; grep an existing `# shellcheck disable=` before writing one.
- **My D1g regex missed the template's trailing space.** — Recovery: ran the slice, read the detail line, fixed. — **Prevention:** print the emitted line before
  writing an anchored regex over it.
- **Mutation anchors M12/M13 matched twice (comment and code), so NOT-LANDED.** — Recovery: the count-equals-1 assertion reported it; re-anchored on the code
  form. — **Prevention:** anchor a mutation on the call form, never a phrase the file also documents.
- **`sleep 100` was blocked by the hook; a stop hook fired on a closing line naming a future action.** — Recovery: Monitor; `<stop>` form. — **Prevention:** none
  needed (the hooks worked).
- **A queued gate that acquires the lock reads the live tree, so edits during it would void the run; the sandbox is a partial copy (no `.git`, no
  `knowledge-base/`).** — Recovery: code developed in a sandbox, docs applied live after the gate finished. — **Prevention:** check `ps` for the gate before
  editing a live tree; keep doc edits as a script applied after the run.
- **A stray 312 KB `.nonexistent` (a byte copy of `ci-deploy.sh`) appeared in the worktree during seat runs.** — Recovery: deleted; my full gate did not recreate
  it, so it was a seat's side effect. — **Prevention:** `git status --short` after every panel returns (already in the review skill's sharp edges).
- **Forwarded from the work phase:** the local affected gate had not completed (queued behind sibling worktrees). — Recovery: it ran during review. —
  **Prevention:** none (resolved).

## Tags
category: test-failures
module: apps/web-platform/infra/ci-deploy.sh, ci-deploy.test.sh
