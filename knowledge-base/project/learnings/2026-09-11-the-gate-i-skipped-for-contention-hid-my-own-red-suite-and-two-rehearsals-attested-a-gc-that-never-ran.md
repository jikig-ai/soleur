---
title: "The gate I skipped for contention hid my own red suite, and two rehearsals attested a gc that never ran"
date: 2026-09-11
category: test-failures
module: git-data
tags: [review, touched-shard-gate, rehearsal, safe-directory, verify-the-negative, propagation, hash-bound]
issue: 8043
pr: 8052
related:
  - 2026-09-10-every-instrument-i-verified-was-verified-inside-its-own-blind-spot.md
  - 2026-09-10-six-instruments-reported-could-not-measure-as-clean.md
  - 2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md
  - 2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md
  - workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md
---

# The gate I skipped for contention hid my own red suite, and two rehearsals attested a gc that never ran

## Problem

PR #8052 batched the six hash-bound git-data pre-birth items (#8043) so the rung-2 template
digest would move once. The work phase ended with "every touched suite green individually" and a
touched-shard gate that had **refused, rc=4**, because two sibling full-gate runs were in flight.
I reported that honestly as skipped-for-contention and listed seventeen green suites.

A ten-seat review then found, in this order of cost:

1. **A registered suite was RED on the branch.** `tests/scripts/test-git-data-rung2-evidence-capture.sh`
   was 78/1: its producer/consumer row calls `git_data_rung2_rehearsal_gate` — the function I had
   just extended with a provenance arm that HOLDs on evidence outside a git work tree — against a
   fixture in a plain temp dir. It was not in my list of seventeen because I enumerated suites from
   memory of what I had *edited*, not from what *consumes* the file I had changed. The refused gate
   would have run it.
2. **The branch was in a real merge conflict with `main`** (`PROMOTED_FILES` in
   `guard-vacuity-floor.test.sh`; a sibling PR promoted a file in the same literal). GitHub said
   `CONFLICTING/DIRTY`. Nothing in my pre-review routine fetches `main`.
3. **A causal claim I had written into four files and an issue body was false.** "`sshWithPrivateKeyAuth`
   returns stdout only, so a refused erasure is indistinguishable from a reachability blip." The
   helper is `promisify(execFile)`; the rejection carries `stderr`, `code` and the remote refusal
   line, and `reportSilentFallback` ships that Error to Sentry. Refuting it took one probe:

   ```js
   const { execFile } = require("node:child_process"); const { promisify } = require("node:util");
   promisify(execFile)("sh", ["-c", "echo 'remote: refused (fail-closed)' >&2; exit 1"])
     .catch((e) => console.log(e.code, JSON.stringify(e.stderr)));   // 1 "remote: refused (fail-closed)\n"
   ```

   The sentence came from the plan. I re-derived every *number* the plan carried and none of its
   *sentences*.
4. **I had corrected a mechanism and left thirteen sites asserting the old one.** The design pass
   measured that sshd runs `command=` as `<login shell> -c`, so `git-shell` kills every forced
   command (rc=128) — and switched the shell to `/bin/sh`. Afterwards the transport wrapper's
   header still said "defense-in-depth ON TOP of git-shell", the bootstrap's step-2 comment still
   listed git-shell as installed, `git-data.tf` still said "per-key `command=` overrides the login
   shell" at two sites, and the placeholder hook still promised delivery "via the web-platform
   deploy pipeline" that ADR-149 records was never built. I had grepped for the new wording.
5. **Four host-trust seams the rehearsal cannot see**, all measured in the pinned image by the
   structural seat:
   - root's weekly gc sets `safe.directory=$REPO_ROOT/*` system-wide. The trailing-`/*` form
     needs git ≥ 2.46; ubuntu-24.04 ships **2.43.0**, where it matches nothing — every run fails
     every repo with "dubious ownership", exits 0, and emits `gc_report warning` **that no Sentry
     rule routed**. The bootstrap comment above that line says "reproduced, rc=128" about the
     defect it believed it fixed. Two paid rehearsals attested a boot; neither runs the timer.
   - the gc lock lived in `/var/lock` (`/run/lock`, `1777`): a git-uid pre-created file makes
     root's `exec 9>` fail under `fs.protected_regular`, parking the store unmaintained.
   - a repo-local `core.hooksPath` (the repo is `git:git`) outranks the system value the
     bootstrap sets, so code-exec-as-`git` unfences one workspace without touching the root-owned
     hook F9 had just protected. Measured: `core.hooksPath=/nonexistent` → push accepted, no hook.
   - the transport wrapper — the forced command that *writes* user source — had none of the
     store-mounted/root-on-store guard the plan had just added to provision and remove, on the
     argument "it already rejects a non-existent repo". Absent ≠ off-store: a root resolved onto
     the root disk beside a healthy mount exec'd `git-receive-pack` there, rc=0.

## Solution

- Suite 1: the fixture is a repository (`git_fixture_env`), the bound tree committed once, the
  SUT's evidence copied in and committed **alone** — the release path's own shape — with a `cmp`
  row so the fixture cannot quietly rewrite what it hands the gate. 80/80.
- Rebase onto `origin/main`, union-resolve the literal.
- Reword the four sites and amend #8094 with the probe; the fix shape there is the catch block,
  not the SSH helper.
- Grep the **subject** (`git-shell`, `overrides the login shell`, `deploy pipeline`), read every
  hit, decide each. Thirteen edits.
- `git-data-gc.sh` passes `-c safe.directory="$repo"` per command (the `/workspaces` LUKS prober
  already used this idiom; command-line scope is the one repo config cannot override); the lock
  moves to `RuntimeDirectory=git-data-gc`; the transport wrapper execs
  `git -c core.hooksPath=$HOOKS_DIR <verb>`, carries the mount+containment guard, honours
  `.cutover-freeze`; `rm -rf --one-file-system`; the per-workspace lock is never unlinked
  (unlink-while-held lets the next opener hold a fresh inode) and a symlink at its path is
  refused. `gc_report` joins the warning rule and the op-contract's (b) derivation now reads the
  gc payload — the corpus was the template, the host runs nine payloads too.
- Every new row went RED under a sandbox mutant before it was accepted (writer census: seven
  survivors on one axis; birth-gate G27–G29 kill three lib mutants; op-contract trailing-comment
  `STAGE=` with a runcmd parse floor).

## Key Insight

**A refused gate is not a skipped gate — it is a gate you now have to reconstruct, and memory is
the wrong instrument.** "Every touched suite green" is a claim about a *list*, and the list has to
be derived from the tree: `git grep -l '<basename of each changed file>' -- '*.test.sh'
tests/scripts` over the registered suites, not from what you remember editing. The suite that
reds is disproportionately the one that *consumes* your change through a shared lib rather than
the one you opened.

**A rehearsal attests what it runs.** Two green rung-2 rehearsals released a maintenance path that
had never executed once, because the timer fires weekly and the rehearsal lasts minutes. The
evidence's own disclosure ("attests the final stage was REACHED with nothing fatal") was accurate;
it was the *reader* who extended it to the gc. When a pinned image carries a version-gated
directive (`safe.directory` with `/*`, `AuthorizedKeysFile` forms, `sshd -T` normalisation), the
version on the image is the falsifier, and it is one `docker run … git --version` away.

**Inherited numbers get re-derived; inherited sentences get believed.** The plan's "stdout only"
claim survived a deepen pass, a work phase, an Art. 30 entry and an issue filing because every
reader treated it as established — it was, in the plan. For every causal or universal sentence a
diff *adds* about a library's behaviour, name the probe that falsifies it and run it before the
sentence reaches a second file.

**Correcting a mechanism is a subject-grep, not a wording-grep.** After changing *what* confines
the account, grep the old control's *name* everywhere it could be asserted as live — headers,
`.tf` comments, runbooks, the register — and read each hit. A residual count over the new
phrasing is structurally blind to the sites still carrying the old.

## Prevention

- **Touched-shard refusal (rc=4):** before claiming per-suite coverage, derive the list:
  `for f in $(git diff --name-only origin/main...HEAD); do git grep -l "$(basename "$f")" -- '*.test.sh' tests/scripts plugins/soleur/test; done | sort -u`, run every hit, and say which commit each covered. (Routed to `work/SKILL.md`.)
- **Before spawning review seats:** `git fetch origin main && git merge-tree --write-tree origin/main HEAD >/dev/null; echo rc=$?` — a conflict found by a seat costs a rebase and a second review round. (Routed to `review/SKILL.md`.)
- **Version-gated directives on a pinned image:** when a config line's semantics depend on the
  tool version (`safe.directory` globs, sshd keywords), measure on the pinned image in the same
  PR that writes the line, and pin the *effect* (a per-repo command that must exit 0), not the
  config value.
- **Payload emitters are corpus:** an op-contract that derives the emitter's vocabulary from the
  template alone under-counts a host that renders payloads; include every file()-bound payload
  that emits.
- **Runtime rows that can only SKIP:** a fixture that needs a shared mount root to be writable
  will skip on every runner and count as pass; give the sentinel a test-only path seam (the same
  `GIT_DATA_CUTOVER_FREEZE` the pre-receive already carries) instead.

## Session Errors

1. **Wrong Better Stack table** — `--table` silently dropped in raw-SQL mode; concluded a boot was dark. Recovery: `export BS_TABLE=…`; then Guard 5 makes the flag work (pre-scan) with rows G5.1–G5.7. **Prevention:** a flag the script accepts must either take effect or refuse loudly; a pre-scan that lifts flags must step over valued flags (G5.6 pins it).
2. **Planning subagent died on a weekly rate limit.** Recovery: re-login, `SendMessage` resume with partial-artifact recovery. **Prevention:** one-off; keep plan artifacts on disk so a resume can pick up the `## Acceptance Criteria` boundary.
3. **`pgrep -f` self-match blocked by hook.** Recovery: `plugins/soleur/scripts/lib/proc.sh list_runs`. **Prevention:** already hook-enforced.
4. **`setsid`/`nohup` background run vanished** (sandbox reap). Recovery: tracked `run_in_background`. **Prevention:** already in `work/SKILL.md`.
5. **Edited a test while a baseline run was reading it** → bogus syntax error. Recovery: re-run. **Prevention:** already in `work/SKILL.md` — never edit under a running suite.
6. **Ubuntu mirrors unreachable ~1h** → docker apt arms wedged. Recovery: non-docker work first, re-run later (92/92). **Prevention:** one-off, external.
7. **Comments quoting the deleted `mkdir -p "$REPO_ROOT"` literal tripped FR4's grep.** Recovery: reword. **Prevention:** a negative grep over a script must run on the comment-stripped corpus, or the comment must not quote the forbidden literal.
8. **Guard 1 rows 3/4 equivalent at the mkdir's original position.** Recovery: rootless-mounted fixtures (T10/T7) so above-guard placement reds; plan row qualified. **Prevention:** state the position at which a re-add mutant is non-equivalent.
9. **Curated-PATH fixture: `command -v grep` returned the ugrep shim FUNCTION** → dangling symlink. Recovery: `docker() { return 1; }; export -f docker` to mask instead. **Prevention:** `command -v` in a shell with shim functions is not a path; use `type -P`.
10. **S6 anchor re-pinned twice.** Recovery: anchored on table rows, then compared to the last writer. **Prevention:** anchor on the construct AND compare the literal (review found the presence-only form).
11. **guard-vacuity-floor ledger growth; floor mutant unconstructible.** Recovery: promoted the file; ADR-193 shape with `_declared=${SKIPPED:-0}`. **Prevention:** new suites with declared skips use the ADR-193 shape from the start.
12. **Pre-commit battery (2.6 h) failures**: capture-exit lint (`|| true` inside `$()`), tempfile-trap lint, fixture-relative baseline, git-fixture-env under a hook (#8051 pre-existing), rehearsal red from the outage. Recovery: each fixed; baseline regenerated. **Prevention:** run the explicit linters before the battery; commit under `LEFTHOOK=0` only with those linters run.
13. **R3(3b)(ii)/S2(k) red on a literal detail.** Recovery: guarded-file shape with rc in the file. **Prevention:** the emitter contract is a file path or a literal fallback — mirror the sibling arm.
14. **Filing hook rejected issue bodies; preamble appends lost with the blocked call.** Recovery: `Mandated-By:` on its own line; appends in a separate step. **Prevention:** one write per `gh` call; never chain a doc append behind a hook-gated command.
15. **`git stash list` typed twice** → hook deny. Recovery: none needed. **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`).
16. **A registered suite was RED on the branch and reported green** (item 1 above). Recovery: fixture as a repo, 80/80. **Prevention:** derive the touched-suite list from consumers of changed files when the gate refuses (routed to `work/SKILL.md`).
17. **Merge conflict with `main` found by a review seat.** Recovery: rebase, union-resolve. **Prevention:** `merge-tree` check before spawning (routed to `review/SKILL.md`).
18. **False "stdout only / indistinguishable" claim propagated to four sites + #8094.** Recovery: probe, reword, amend the issue. **Prevention:** run the falsifier for every added causal sentence about a library call (`work/SKILL.md` already says so — the rule existed, the probe was skipped).
19. **Thirteen stale git-shell / pipeline-delivery sites after the mechanism changed.** Recovery: subject grep, thirteen edits. **Prevention:** grep the old control's NAME after replacing it (`work/SKILL.md` "PROPAGATED is a measurement").
20. **T12 freeze fixture could only SKIP** (shared mount root never writable). Recovery: `GIT_DATA_CUTOVER_FREEZE` seam, default pinned on the line. **Prevention:** a row whose fixture depends on runner privileges is a row that never runs; give the sentinel a seam.
21. **`gh issue create --label engineering` (no such label); `lint-rule-bodies.py` without `--check`.** Recovery: copy the tracker's label set; `--check`. **Prevention:** one-off.
22. **`gdpr-gate-staleness` hook deny ×2** (compliance posture 124 days stale) during the work-phase gdpr pass. Recovery: recorded in the pre-compaction segment; `tasks.md` marks the gate passed. **Prevention:** already hook-enforced; the posture refresh is its own tracked item.
23. **Inherited: `safe.directory=/*` inert on git 2.43**, comment claimed the fix reproduced. Recovery: per-repo `-c safe.directory`, S9a pin, `gc_report` routed, ADR-149 row. **Prevention:** measure version-gated directives on the pinned image; pin the effect.
