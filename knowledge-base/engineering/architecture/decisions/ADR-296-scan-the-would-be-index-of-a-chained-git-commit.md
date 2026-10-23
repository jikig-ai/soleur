---
title: Scan the would-be index of a chained git commit, on a copy, with a bounded no-bypass deadline
status: active
date: 2026-10-23
amends: none
supersedes: none
issue: 10696
related: [10331, 10609, 10793, 10893]
related_adrs: [ADR-157, ADR-165, ADR-256, ADR-295]
brand_survival_threshold: single-user incident
---

# ADR-296: Scan the would-be index of a chained git commit, on a copy, with a bounded no-bypass deadline

## Status

Active — 2026-10-23 (#10696, PR #10893; the closed epic #10331 is referenced, never reopened). This ADR is the
single index of the contract: the construction, the deny causes, the time bound and the named residuals. The code
headers cite it; a second consumer (the brand-hex gate, #10793) reads it first.

## Context

`.claude/hooks/git-commit-secret-scan.sh` is a PreToolUse hook: it runs BEFORE the Bash command it guards. For
`git add -A && git commit`, `git commit -a`, `git commit -am` and `git commit -- <path>` the index on disk does not
yet hold the content the commit will record, so the gate scanned an index that could not contain the leak (issue
#10696 reproduced a synthetic PEM in an untracked or modified file passing every chained form). The
hook's purpose is keeping a credential out of git history, which a revert cannot undo; the failure is a
single-user incident, so every uncertainty resolves to a deny with a one-call repair.

## Decision

**Scan the index the commit WILL record, built on a copy.** `lib/commit-target-roots.sh` (the walker, fed by the
hardened shell lexer `plugins/soleur/hooks/lib/shell-argv.pl`) reads the command's own argv and records its staging
facts (`CTR_*`). `lib/commit-index-sim.sh` copies the real index (`cp -p`, mtime kept so a racily clean entry is not
trusted) into a 0700 directory the hook allocates, replays the staging onto the COPY, exports
`GIT_INDEX_FILE` / `GIT_OBJECT_DIRECTORY` / `GIT_ALTERNATE_OBJECT_DIRECTORIES` (a quarantined object directory in
front of the real one as an alternate), and `scan_root` runs unchanged in logic inside that window. The real index
content, listing and git directory and the working tree are not written; the one stated exception is that the
mtime of an existing object may be refreshed when the content being added is already present.

**Plan once per command (CTO rulings, decision-challenges rows 4, 15, 33).**
- *Exact replay* (`git -C <dir> add <validated options> -- <paths>` in text order, then the commit's own flags:
  `-a`/`-p` become `add -u`; a pathspec becomes `add -u -- <literal paths>`, then `add -u`) runs only when every add
  record is exact, nothing is opaque, the text has no loop or function, and the directory is PROVEN: (i) the
  command names no `cd` / `pushd` / `-C` and the payload cwd is an absolute existing directory, (ii) every add record
  and the commit carry the same absolute `-C`, or (iii) `cd <abs>` is the first record followed only by `&&`-joined
  git records. With proof, only the root whose toplevel is that directory's (`CIS_TOP`) is simulated; every other
  root is a fallback-only root (the hook's cwd, the payload cwd) the command cannot stage into and is scanned against
  its REAL index.
- *Superset* (`git add -A` from the root, plus `git add -f -- <literal words>` in the directory each force-add record
  proves) is used in every root otherwise. It over-scans untracked files, never under-scans. This is what keeps
  `git -C A status; git add -A && git commit` closed.

**Unknown is opaque (rows 22, 26).** Every strict commit is lexed where perl exists. An expanded command word or
subcommand, a dashed `git-<verb>`, a staging verb among the words of a non-git command, an unknown short commit
option, a bundle longer than 64 characters and the verbs checkout / cherry-pick / merge / revert / stash / am /
read-tree / restore / pull / switch / rebase / submodule / sparse-checkout / apply / update-index make the stage
opaque and take the superset. `update-index --add|--cacheinfo|--index-info` and `apply --index|--cached|--3way`
bring content from outside the working tree: they are denied (`stage-unsimulable`).

**The replay environment is an allowlist (rows 23, 24).** A staging record (an `add`/`stage`, or a commit that
stages) with a `-c` / `--config-env` key under `core. filter. diff. attr. include. includeif. add. apply.
submodule. alias.`, `--namespace`, `--attr-source`, an environment name outside LC_* LANG LANGUAGE TZ TERM
NO_COLOR CI GIT_AUTHOR_* GIT_COMMITTER_* GIT_EDITOR GIT_PAGER GIT_TERMINAL_PROMPT, `env -i|-u|-`,
sudo/doas/su/runuser/chroot/nsenter, or an `export`/`unset`/bare assignment of a name git can see is refused
(`config-refused`): a replay cannot reproduce a different HOME, configuration, attributes or hooks.

**Every replay git call is pinned (rows 18, 28).** `-c core.fsmonitor=false -c core.untrackedCache=false -c
core.splitIndex=false -c core.hooksPath=/dev/null`, one neutralisation per configured filter (clean, process, smudge,
required=false), `LC_ALL=C`, `GIT_OPTIONAL_LOCKS=0` (a dirty submodule's real index is otherwise rewritten by the
child `git add`), and the verb is always the literal `add`. The sim therefore scans RAW bytes. `scan_root` pins
`core.fsmonitor=false` too (rows 19, 29) and reads `-diff` blobs with one `checkout-index -z --stdin --prefix` call.

**One bound, no bypass (rows 20, 30, 31).** One total deadline of 30 s covers every root and the scan inside the
window. Every git and gitleaks call in simulation mode runs under one perl fork / waitpid / kill program (own
process group, TERM then KILL, exit 124 on expiry; perl `alarm` + `exec` does not stop gitleaks, a Go program).
Expiry, a gitleaks exit other than 0 or 1, a non-zero exit with an empty report, a failed `check-attr` or
`checkout-index`, an unexpected error (an ERR trap installed with `set -E`) and a failed `mktemp` all DENY when the
simulation is on. `CIS_DEADLINE_SECONDS` is a test-only knob that can only lower the ceiling (row 37).

**Why the deny is not a bypass, and why 30 s is safe.** The harness's own hook timeout is non-blocking: a hook that
outruns it lets the tool call proceed (https://code.claude.com/docs/en/hooks, retrieved 2026-10-23: default 600 s,
`timeout` non-blocking, `onFailure` continue or block). A deadline that expired into an allow would therefore be
the same failure as a crash. The simulation is bounded far below that ceiling (30 s total; the unrelated gitleaks
probe adds at most 70 s), and its own expiry denies. The measured cost is recorded in
`knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/measurements.md` (AC13: the p95 of a
chained commit against the same command on an unstaged tree under the old hook must differ by at most 1.5 s).

## Deny causes (the enumerated words of the ledger row `mode=... cause=...`)

Real findings keep the rule id `git-commit-secret-scan` (row `mode=<exact|superset> cause=finding`). Only a
simulation FAILURE uses `git-commit-secret-scan-sim-deny` (permanent ids; `sim-failed` is retired):

| Cause | Meaning | Repair named in the deny text |
|---|---|---|
| `pathspec-missing` | git said a staged path does not exist | create it in an earlier call or fix the spelling (git's line is appended) |
| `sim-timeout` | the 30 s deadline or a bound expired | split the staging from the commit (deterministic for a very large tree) |
| `scan-error` | gitleaks errored or wrote no report | split the staging from the commit |
| `internal-error` | the ERR trap fired | split the staging from the commit |
| `temp-dir` | `mktemp` failed | free space in TMPDIR |
| `check-attr-failed` | the `-diff` attribute guard could not run | split the staging from the commit |
| `force-nonliteral` / `force-unproven-dir` | a `git add -f` with no literal path word, or in a directory the command does not prove | run the force-add as its own call |
| `config-refused` | a config key or environment the replay cannot honour | split the staging from the commit |
| `stage-unsimulable` | content from outside the working tree | run that staging command as its own call |
| `superset-failed` / `fresh-failed` / `copy-failed` / `prepare-failed` / `colon-path` / `not-planned` | construction failed | split the staging from the commit |
| (the `lib` deny) | the walker or the sim library is missing, unreadable or mismatched | `git checkout -- .claude/hooks/lib` |

"Split the staging from the commit" is branched on the command's own style: for `commit -a` run `git add -u` as its
own call and commit again WITHOUT `-a`; for a pathspec commit run `git add <paths>`, check
`git diff --cached --name-only`, and commit WITHOUT the paths; otherwise `git add <paths>` as its own call, then the
commit as a second call. A finding's recovery is chosen from where the file is (already staged: `git restore
--staged <path>` as its OWN call, since chained it is not simulated; tracked: scrub in place, never delete; untracked:
scrub, delete, ignore or stage only the intended files), whether the command names the root (else `cd <target>` as
its own call), and why the superset was used.

## Named residuals (accepted; the walker reads argv, not effects)

1. What an EARLIER command in the same call changes: a producer, `sed -i`, `prettier --write`, an edit of
   `.gitignore`, config or attributes. A superset cannot reproduce a different HOME and a producer's later content is
   unscannable by construction.
2. A script or wrapper that runs `git add` inside, and user-config aliases (inline `alias.*` keys are refused).
3. A host WITHOUT perl: the lexer cannot run, a commit that needs it is denied (`tooling`), and a positional
   pathspec after `-m "..."` is not seen there.
4. The raw-byte scan: a clean filter or Git LFS may record other bytes.
5. checkout, stash, read-tree, cherry-pick, merge, revert, am, restore, mv and rm: history-sourced or
   removal-only content; `add -A` never adds an ignored path. They take the superset.
6. The mtime of existing real loose objects and shared indexes may be refreshed by the sim `add`; content, listing
   and index bytes do not change.
7. A SIGKILL can leave a 0700 temp directory behind (there is no stale sweep).
8. A harness that sends no payload cwd (Devin) never has proof (i) and always takes the superset.
9. Other tools that stage (an IDE) and a configured `core.fsmonitor` daemon (not started by the sim).

## Consequences

- `lib/commit-index-sim.sh` is policy-free (never denies, allows, emits or runs gitleaks) so the brand-hex gate
  (#10793) can reuse construction: `cis_plan`, `cis_build`, `cis_export` / `cis_unexport`, `CIS_ENV`, `cis_clock_start`,
  `cis_bound_argv`, `cis_pins_build`, `CIS_API=1`. A consumer stub test is part of the suite.
- A walker or library torn between two versions (`CTR_STAGE_API` / `CIS_API`) denies every strict commit rather than
  silently reverting to the pre-run index.
- The hook costs one lexer run per strict commit where perl exists and, for a chained commit, one bounded
  simulation. AC13 (p95 difference at most 1.5 s) is re-measured and recorded in `measurements.md`.
- The suite carries a mutation matrix per guard (recorded in the commit messages of the review-round units).

## Alternatives rejected

- *`git diff HEAD` of the resolved roots* (the issue's candidate): it lists no untracked file, so a new file added
  and committed in one command passes, and it over-scans unstaged edits the commit will not record.
- *Run the real `git add` first*: mutates the real index and object store before the user's command and before the
  allow or deny.
- *Scan the working tree with `gitleaks dir`*: scans everything, not what the commit records.
- *Always the superset*: an unrelated untracked file would deny `git add clean.txt && git commit`.
- *A bypass on timeout*: the harness hook timeout is non-blocking, so this would restore the failure.
- *A pre-filter for the lexer* (the first design): an open-world list of the forms that matter. Row 22 reversed it:
  the lexer is already on for almost every commit, so where perl exists it is on for all of them.
