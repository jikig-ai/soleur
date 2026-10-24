---
title: Scan the would-be index of a chained git commit, on a copy, with a bounded no-bypass deadline
status: active
date: 2026-10-23
amends: ADR-157 (partial: a failed simulation of the commit's own staging denies; the other ADR-157 rules stand)
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
front of the real one as an alternate), and `scan_root` runs inside that window. The real index
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

**Unknown is opaque (rows 22, 26).** Every strict commit is lexed where perl exists. An expanded, brace, glob or
tilde command word or subcommand, a dashed `git-<verb>`, a staging verb among the words of a non-git command or inside
the string operand of a launcher (`su -c`, `ssh host "..."`, `flock -c`, `sg -c`, `script -c`, `fish -c`, `watch`,
`runuser -c`, `parallel`), an unknown short commit option, a bundle longer than 64 characters and the verbs checkout /
cherry-pick / merge / revert / stash / am / read-tree / restore / pull / switch / rebase / submodule /
sparse-checkout / apply / update-index make the stage opaque and take the superset. `update-index
--add|--cacheinfo|--index-info` and `apply --index|--cached|--3way` (also in a short bundle such as `-v3`) bring
content from outside the working tree: they are denied (`stage-unsimulable`). An abbreviation git accepts is read as
the option it abbreviates: `add --f|--fo|--for|--forc` is a force-add, and so is a bundle past the 64-character cap
that contains an `f`.

**The replay environment is an allowlist (rows 23, 24).** A staging record (an `add`/`stage`, or a commit that
stages) with a `-c` / `--config-env` key under `core. filter. diff. attr. include. includeif. add. apply.
submodule. alias.`, `--namespace`, `--attr-source`, an environment name outside the allowlist (`LC_*` `LANG` `LANGUAGE`
`TZ` `TERM` `NO_COLOR` `CI` `GIT_AUTHOR_*` `GIT_COMMITTER_*` `GIT_EDITOR` `GIT_PAGER` `GIT_TERMINAL_PROMPT`, and by
exact name `HUSKY` `HUSKY_SKIP_HOOKS` `LEFTHOOK` `LEFTHOOK_EXCLUDE` `SKIP` `PRE_COMMIT_ALLOW_NO_CONFIG`, rows 23 and
39), `env -i|-u|-`, `exec -c`, `sudo` `doas` `su` `runuser` `chroot` `nsenter` `setpriv` `bwrap` `systemd-run`
`unshare` in front of it (row 41), or an `export` / `unset` / `set -a` / `set -o allexport` / bare assignment of a
name git can see is refused (`config-refused`): a replay cannot reproduce a different HOME, configuration,
attributes or hooks. An inline alias definition (`-c alias.X=`, `--config-env=alias.X=`, a `GIT_CONFIG_*` prefix) is
refused on ANY git record of a command that also stages or commits (row 40).

**Every replay git call is pinned (rows 18, 28).** `-c core.fsmonitor=false -c core.untrackedCache=false -c
core.splitIndex=false -c core.hooksPath=/dev/null`, one neutralisation per configured filter (clean, process, smudge,
required=false), `LC_ALL=C`, `GIT_OPTIONAL_LOCKS=0` (a dirty submodule's real index is otherwise rewritten by the
child `git add`), and the verb is always the literal `add`. The sim therefore scans RAW bytes. `scan_root` pins
`core.fsmonitor=false` too (rows 19, 29). Every staged path whose `diff` attribute is not `unspecified` or `set` (`-diff`,
or a driver name that may be configured binary or textconv) is re-scanned from its RAW staged blob (row 42): the blob
ids come from `git diff --cached --raw`, the bytes from ONE `git cat-file --batch` split into files named by their
paths (never a checkout, which converts through `working-tree-encoding`, `eol` and `ident` and hid a UTF-16LE secret).
The sanitiser for command-sourced text in a deny (file names, config keys, undeterminable-target texts) replaces every
control, format, line/paragraph-separator, private-use and unassigned character and caps the length.

**One bound, no bypass (rows 20, 30, 31).** One total deadline of 30 s covers every root and the scan inside the
window. The replay `git add` calls, `git diff --cached --raw`, `git check-attr`, `git cat-file --batch` and the two
gitleaks calls run under one perl fork / waitpid / kill program (own process group, TERM then KILL, exit 124 on
expiry, the same sequence and exit 143 on a TERM / INT / HUP sent to the hook's process group; perl `alarm` + `exec`
does not stop gitleaks, a Go program). NOT bounded: the read-only prepare calls (`git rev-parse`, `git config
--get-regexp`, `cp -p` of the index), the git calls of `sim_recovery` and the `gitleaks version` probe (that one has its
own 10 s + 60 s bound): a hung one (NFS, a stuck fsmonitor) is not covered by the deadline (residual 10). Expiry, a
gitleaks exit other than 0 or 1, a non-zero exit with an empty report, a failed or short `check-attr`, an unreadable
blob, and a failed `mktemp` all DENY, in either mode for the `mktemp`. An unexpected error DENIES from the line where
the traps are installed (right after the cheap non-commit gate) while a simulation is due or still undecided: the ERR
trap (`set -E`; inside a substitution or subshell it fails that substitution so the parent's own ERR denies) and an
EXIT latch that turns a hook ending without `allow` or `deny` (a `set -u` abort, an arithmetic error) into a deny. A
failure before that line (hook-input parsing, the gate), and a plain-path failure once `sim_on` is 0, still exit 1.
`CIS_DEADLINE_SECONDS` is a test-only knob that can only lower the ceiling (row 37).

**Why the deny is not a bypass, and why 30 s is safe.** The harness's own hook timeout is non-blocking: a hook that
outruns it lets the tool call proceed (<https://code.claude.com/docs/en/hooks>, retrieved 2026-10-23: default 600 s,
`timeout` non-blocking, `onFailure` continue or block). A deadline that expired into an allow would therefore be
the same failure as a crash. The simulation is bounded far below that ceiling (30 s total; the unrelated gitleaks
probe adds at most 70 s; the unbounded read-only calls above are residual 10), and its own expiry denies. The measured
cost is recorded in
`knowledge-base/project/specs/feat-one-shot-10696-secret-scan-staging-gap/measurements.md` (AC13: the p95 of a
chained commit against the same command on an unstaged tree under the old hook must differ by at most 1.5 s).

## Deny causes (the enumerated words of the ledger row `mode=... cause=...`)

Real findings keep the rule id `git-commit-secret-scan` (row `mode=<exact|superset> cause=finding`). Only a
simulation FAILURE uses `git-commit-secret-scan-sim-deny` (permanent ids; `sim-failed` is retired). `mode=` is the
PLAN's mode, not the attempt's (a replay that fell back to the superset still reads `exact`), and `mode=none` when the
plan had not run (`config-refused`, `stage-unsimulable`, an early `internal-error`). The undeterminable-target and
`lib` denies are a different rule id, `git-commit-secret-scan-undeterminable`, with no `mode=` / `cause=`:

| Cause | Meaning | Repair named in the deny text |
|---|---|---|
| `pathspec-missing` | git said a staged path does not exist | create it in an earlier call or fix the spelling (git's line is appended) |
| `sim-timeout` | the 30 s deadline or a bound expired (a replay `add`, the scan's git calls or gitleaks) | split the staging from the commit (deterministic for a very large tree) |
| `scan-error` | gitleaks errored or wrote no report | investigate and fix gitleaks, then re-run (splitting the staging does not repair a gitleaks that cannot finish) |
| `internal-error` | the ERR trap or the exit latch fired | split the staging from the commit |
| `temp-dir` | `mktemp` failed (a sim directory, or a report file in either mode) | free space in TMPDIR |
| `check-attr-failed` | the `-diff` attribute guard could not run | split the staging from the commit |
| `force-nonliteral` | a `git add -f` with no literal path word (a variable, a glob, stdin, `--pathspec-from-file`) | run the force-add as its own call |
| `force-unproven-dir` | a `git add -f` in a directory the command does not prove (a relative `cd` / `-C`, a `$` / `;` / `|` in the text, another repository) | `cd /abs &&` or `-C /abs` on the add with no expansion in the command, or the force-add as its own call |
| `config-refused` | a config key or environment the replay cannot honour | split the staging from the commit |
| `stage-unsimulable` | content from outside the working tree | run that staging command as its own call |
| `colon-path` | the object directory path contains `:` (not nameable in `GIT_ALTERNATE_OBJECT_DIRECTORIES`) | split the staging from the commit, or move the checkout to a path without `:` |
| `superset-failed` / `fresh-failed` / `copy-failed` / `prepare-failed` / `not-planned` | construction failed | split the staging from the commit |
| (the `lib` deny; rule id `git-commit-secret-scan-undeterminable`, no `cause=`) | the walker or the sim library is missing, unreadable, mismatched or truncated (the install check tests `ctr_collect`, `ctr_resolve_roots`, `cis_build` and both API versions) | `git checkout -- .claude/hooks/lib` |

"Split the staging from the commit" is branched on the command's own style: for `commit -a` run `git add -u` as its
own call and commit again WITHOUT `-a`; for a pathspec commit run `git add <paths>`, check
`git diff --cached --name-only`, and commit WITHOUT the paths; otherwise `git add <paths>` as its own call, then the
commit as a second call. A finding's recovery is chosen from where the file is (already staged: `git restore
--staged <path>` as its OWN call, since chained it is not simulated; tracked: scrub in place, never delete; untracked:
scrub, delete, ignore or stage only the intended files), whether the command acts in the root (when it also names
another repository the text offers both directions - scrub in this one, or put `-C <target>` on BOTH the add and the
commit - and never prescribes a bare `cd`), and why the superset was used (the text names the verb to run as its
own call first for a loop, stash, merge or checkout).

## Named residuals (accepted; the walker reads argv, not effects)

1. What an EARLIER command in the same call changes is not seen: a producer, `sed -i`, `prettier --write`, an edit of
   `.gitignore`, config or attributes, a `git mv` (a rename can move a modified file out of a path-keyed allowlist,
   attribute or `.gitleaksignore` fingerprint, so `git mv x allowed/ && git commit -am` is allowed where the real end
   state denies), a `git stash pop` (it brings never-committed content), `rm`. A superset cannot reproduce a different
   HOME and a producer's later content is unscannable by construction. (Row 43; "removal-only" is not the reason.)
2. A script or wrapper that runs `git add` inside, and user-config aliases (`alias.*` in the user's own gitconfig; inline
   `alias.*` keys are refused). A string-operand launcher is closed only for the verb list: `ssh host "make add"`
   over-matches into the superset, `ssh host "./stage.sh"` is not seen.
3. A host WITHOUT perl reads only a single simple commit unread (row 46): a quoted verb, `"-a"`, `-m x tracked.json`,
   `$a add` and `git-add` are all `tooling` DENIES there, so nothing is allowed on a regex guess. The cost is a false
   deny of routine chained or heredoc commits on a minimal container.
4. The raw-byte scan: a clean filter or Git LFS may record other bytes.
5. checkout, stash, read-tree, cherry-pick, merge, revert, am, restore, mv and rm are opaque, take the superset and
   scan the working tree as it is NOW (see residual 1 for why that is not the content they would leave).
6. The mtime of existing real loose objects and shared indexes may be refreshed by the sim `add`; content, listing
   and index bytes do not change. The incident emitter creates `.git/soleur-session-state/` directories in either mode.
7. A SIGKILL leaves a 0700 temp directory behind (about 8 KB per staged path in RAM on a tmpfs TMPDIR: 405 MB at 50,000
   paths). The next simulation removes only directories that match `commit-sim-*`, are owned by the same user, carry
   the marker file, are older than 60 minutes and are not symlinks (row 45); the `gitleaks-nodiff-*` re-scan directory
   has no marker and is not swept. INT / TERM end the hook with 130 / 143, which the harness treats as non-blocking.
8. A harness that sends no payload cwd (Devin) never has proof (i): a bare `git add a && git commit` takes the
   superset. Proofs (ii) (the same absolute `-C` on every add and the commit) and (iii) (`cd /abs && ...` first) still
   hold, so those commands stay exact.
9. Other tools that stage (an IDE) and a configured `core.fsmonitor` daemon (not started by the sim).
10. A hung read-only git call (NFS, a stuck fsmonitor) in the prepare phase or `sim_recovery` is not covered by the
    deadline, and the harness's own hook timeout is non-blocking.
11. The hook's outer gate (the text must contain `git` and `commit`) lets a concealed commit word through after a
    staging command: `git com""mit`, `git comm\it`, `c=commit; git $c` (row 44, pinned by a test so it stays visible).
12. `mode=` on a failure row is the plan's mode, not the attempt's (see the cause table).

## Consequences

- `lib/commit-index-sim.sh` is policy-free (never denies, allows, emits or runs gitleaks) so the brand-hex gate
  (#10793) can reuse construction: `cis_plan`, `cis_build`, `cis_export` / `cis_unexport`, `CIS_ENV`, `cis_clock_start`,
  `cis_bound_argv`, `cis_pins_build`, `CIS_API=1`. A consumer stub test is part of the suite.
- **Consumer contract** (what a second consumer owns; none of it is enforced by the library): (1) DENY on
  `CTR_STAGE_UNSIMULABLE` (the library treats it as opaque and would scan the working tree, never the content that came
  from outside it); decide on `CTR_STAGE_REFUSE` (the replay forwards nothing from the command, so a consumer that
  does not refuse still replays safely, but it will not honour the config or environment the real command had);
  (2) allocate a 0700 workdir per root and own its cleanup (the library removes it only on a failed build); (3) call
  `cis_plan` once and `cis_clock_start` once per command - a build without either fails closed; (4) when the plan is
  `exact`, build only the root whose toplevel is `CIS_TOP` and scan every other root against its real index; with the
  superset build every root; (5) treat ANY `cis_build` status other than 0 as a deny (`CIS_WHY` is a closed set);
  (6) `cis_unexport` before reading real state.
- A walker or library torn between two versions or truncated (`CTR_STAGE_API` / `CIS_API`, `ctr_resolve_roots`
  present) denies every strict commit rather than silently reverting to the pre-run index.
- Cost: sourcing the two libraries is about 7-9 ms on every command that contains `git` and `commit`; where perl exists
  the lexer adds about 13-25 ms to a plain commit (it was previously skipped for most commits), and a lexer `parse` or
  `bound` failure now DENIES a plain commit that it used to let through (an unparseable message). A chained commit adds
  one bounded simulation. AC13 is recorded in `measurements.md` as a paired difference with a confidence interval; the
  1.5 s gate is a tripwire, the felt cost is the paired median of the new hook against the old hook on the same chained
  command.
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
