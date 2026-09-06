---
title: "A 10/10 mutation score, and ten escapes it could not see"
date: 2026-09-04
category: test-failures
issue: 7833
pr: 7840
tags: [mutation-testing, vacuity, guards, escape-testing, git-environment, test-fixtures]
---

# A 10/10 mutation score, and ten escapes it could not see

## Problem

Issue #7833 is one line. A git hook in a linked worktree exports `GIT_DIR` and
`GIT_INDEX_FILE` as absolute paths; a `git` subprocess honours them over both its
working directory and `-C`. So a fixture that correctly passes `cwd` still writes
into the developer's real repository — `git init` initialises nothing, and the
fixture's commits land on the live branch and move its tip. The fix is an `unset`
in front of one lefthook test runner.

Around that one line I built three guards, two mutation batteries, a parity test
and a measurements record. A ten-agent panel then found ~30 findings. **Every
single one was in the verification, not the fix.** The `unset` reproduced correctly
end to end from the first measurement onward and was never touched.

This is the second time in two days ([2026-09-04, #7801](2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md)),
which moves it out of "a thing that happened" and into a property of guard-shaped
PRs: **the fix gets the scrutiny, the scaffolding gets the trust.**

## The four that generalize

### 1. Mutation rows and escape rows answer different questions, and only one of them found the real defects

Guard 2's mutation battery scored 10/10. Every perturbation of the guard was
caught. Then I fed the *pristine* guard ten corpora it should have refused, and
several were green.

The distinction is exact:

- A **mutation row** damages the guard and asks *can this thing fail at all?*
- An **escape row** leaves the guard untouched and feeds it input it should reject,
  asking *is the predicate actually the property the guard's name claims?*

No mutation could have surfaced these. The guard was working exactly as written.
It was written to check the wrong thing.

The sharpest one: `SCRUB_RE` required only the literal `GIT_DIR`, so mutating the
shipped fix down to `unset GIT_DIR && bun test` — the fix minus one variable — read
GREEN. **This PR's own measurement §M-3 proves that is insufficient**: with `GIT_DIR`
scrubbed, an absolute `GIT_INDEX_FILE` still stages into the victim's index. The
measurement and the guard were written by the same person, hours apart, and the
guard did not protect the fix it exists to protect.

Another was `bash scripts/test-all.sh && bun test plugins/` — literally the #7833
defect shape, waved through because a name the guard recognised appeared earlier in
the line.

**Take:** a mutation score is a claim about the battery's sensitivity, not about
the predicate's correctness. Run both. Budget for escape rows first — they found
every P1 here.

### 2. Two guards from one PR can make each other vacuous

Guard 1 asserted that the helper's deny-list removes each git-location variable:

```ts
for (const k of GIT_LOCATION_VARS) expect(env[k]).toBeUndefined();
```

Guard 3 is a tripwire that aborts any runner starting with one of those variables
set (rc=97).

So Guard 1's loop can only ever execute in an environment where those variables are
already absent — the tripwire guarantees it. Deleting five of the seven names from
the deny-list left the suite **byte-identical green**, 6 pass / 0 fail.

Neither guard is vacuous alone. The vacuity is in the interaction, and it is
invisible from inside either file. It only appeared when the battery mutated the
*other* guard's subject.

**Take:** when a PR ships more than one guard, ask what each one guarantees about
the environment the others run in. A precondition enforced elsewhere in the same PR
is exactly the kind of thing that silently empties an assertion's domain.

### 3. A deny-list is a claim about a vocabulary someone else controls

`origin/main` landed `plugins/soleur/test/lib/git-clean-env.ts` mid-session, stating
the rule in capitals:

> EXCLUSION BY PREFIX, NEVER BY NAME LIST — a hardcoded list is a claim about which
> variables git honours, and it is wrong the moment git adds one.

My list was missing four, and review found all four in one pass:

| Missing | Why it matters |
|---|---|
| `GIT_TEMPLATE_DIR` | **Proven arbitrary code execution.** `git init` copies template hooks in *before* any config is consulted, so the config hardening is no defence — the fixture's own `git commit` executed a copied hook. |
| `GIT_EXEC_PATH` | Same class: names a directory of programs git runs. |
| `GIT_SSH` | A `GIT_SSH_COMMAND` prefix rule **structurally cannot** match it — the prefix is longer than the name. |
| `GIT_TRACE*` | Appends to an absolute path: a write outside the fixture, i.e. the exact property the helper exists to establish. |

The final helper layers on main's sweep rather than competing with it. The list that
remains (`GIT_LOCATION_VARS`) is **not** used to build the environment — the prefix
sweep does that. It exists only because the tripwire and the `unset` need concrete
words: a tripwire cannot refuse *every* `GIT_` variable (`GIT_AUTHOR_NAME` is
harmless and a hook exports it on every commit). Where a list is unavoidable, pin it
with a parity test across every language it is transcribed into, not a "keep in
sync" comment.

### 4. Detect-set and remediate-set must be the same set

The tripwire refused nine variables. The remedy it printed named three. An operator
who pasted the remedy would clear the message and hit the same abort — a loop.

The fix was to derive the remedy from what was actually found, and to add
`git-env-list-parity.test.sh` asserting the subset direction across six sites in four
languages: **every name the tripwire refuses must appear in every `unset`.** That
asymmetry is the one a prose drift comment could never have caught, because it is a
relationship between two files, not a property of either.

## Session Errors

**1. `split_statements` silently dropped the last statement.** `printf '%s'` with no
trailing newline made `while read` return non-zero on the unterminated final line, so
the last statement of every command was never examined. Six escape probes (npm test,
bun run test:ci, python3 -m unittest, folded scalar, subshell, quoted echo) all passed
GREEN — because in each, the runner *is* the last statement.
**Recovery:** `printf '%s\n'` plus `|| [[ -n "$st" ]]` on the read.
**Prevention:** found by running the probes, not by reading the code. A shell loop
over a `printf`-built here-string needs a probe whose expected verdict is RED.

**2. I publicly called `git-clean-env.ts` "fabricated" and was wrong.** A review agent
cited it; I checked my own HEAD instead of `origin/main` and dismissed it.
`origin/main` had moved to `44f93dd2b` mid-session.
**Recovery:** corrected the record explicitly, rebased, took main's version of the
three converted suites and layered on it rather than shipping a second module.
**Prevention:** an agent report is a claim about a tree at a moment. Verify a
"file does not exist" dismissal against freshly-fetched `origin/main`, never local HEAD.

**3. Mutation rows M4/M6 survived because the hostile env was injected via
`process.env`.** Under Bun a `delete`/assignment on `process.env` does not reach a
child spawned without an explicit `env`; the child gets process-start values. Node
propagates it, so the divergence only shows for an *inherited* variable.
**Recovery:** spawn a child bun process with the hostile env at process START.
**Prevention:** to simulate inheritance, inherit. Setting a variable in-process and
calling it "inherited" tests a different thing under every runtime.

**4. J1 survived: erasing the guard body erased its own floors.** The
assertion-count floors lived inside the guard, so `exit 0` deleted guard and floors
together.
**Recovery:** `SOLEUR_GUARD2_RECEIPT`, verified by an external caller.
**Prevention:** a floor that shares a lifetime with what it guards is not a floor.
(AP-023 already says floors report via `printf` + `exit`, never through the helper
they backstop — this is the same rule one level up.)

**5. The receipt that fixed J1 had no CI consumer.** Its only reader was a
`.mutation.sh`, which matches no `SUITE_GLOBS` entry, so nothing in CI ever read it.
**Recovery:** added `hook-git-env-receipt.test.sh`, registered by the
`plugins/soleur/test/*.test.sh` glob.
**Prevention:** after adding a field to close a gap, grep for who reads it and confirm
that reader is registered. An unread receipt is a comment.

**6. H1 survived because the ledger records positionally.**
**Recovery:** floored on Bun's own `expect() calls` count, which the suite cannot forge.
**Prevention:** prefer a count the runner emits over one the suite maintains.

**7. N3/N4 "survived" against a pristine corpus.** A guard weakening is only
observable against a *discriminating* corpus; against a fully-compliant one, a
weakened guard and a correct guard agree.
**Recovery:** re-polarised those rows — expected GREEN, proving the predicate is
load-bearing.
**Prevention:** state each row's expected verdict and *why*, before running it.

**8. My own tripwire made my own test vacuous.** See §2 above.
**Recovery:** assert against a synthetic *injected* env (safe mid-test — the tripwire
already ran at import).
**Prevention:** when a PR ships several guards, enumerate what each guarantees about
the others' environment.

**9. `*/` inside a JSDoc block closed the comment early.** Writing
`GIT_AUTHOR_*/GIT_COMMITTER_*` in a `/** … */` produced a Syntax Error.
**Recovery:** reworded to prose.
**Prevention:** no `*/` inside a block comment, glob or not.

**10. An `unset`-matching regex could never match the first variable.** It required a
preceding space, which the first name after the `unset` keyword does not have.
**Recovery:** extract the `unset` line, then word-match within it.
**Prevention:** for a list-after-keyword pattern, test the first and last elements
explicitly — they are the two with asymmetric neighbours.

**11. I wrote a comment claiming a preload "still fires" without measuring it.** The
`apps/web-platform/bunfig.toml` preload does not fire for the invocation I claimed.
**Recovery:** measured (rc=0, no FATAL), reverted the comment, and aimed at
`plugins/soleur/` — the real gap, confirmed live.
**Prevention:** this is the repo's standing rule (`hr-…`, ADR-166 class): for every
causal claim the diff's prose *adds*, name the command that falsifies it and run it.
I wrote this one about my own code, in the same PR whose subject is unverified
environment assumptions.

**12. AC13's first attempt tested nothing.** The lefthook glob is
`plugins/soleur/**/*.md`, which requires at least one subdirectory and does not match
`plugins/soleur/AGENTS.md`.
**Recovery:** retried with a subdirectory `.md`; hit a pre-existing MD032 on main,
fixed inline; then passed (depth +1, 0 phantom commits).
**Prevention:** before using a path to trigger a glob, confirm the glob matches it.

**13. I reported a push as successful when it had failed.** An `echo` after a piped
`git push` read the pipeline's last command, not the push.
**Recovery:** acknowledged and re-pushed with `--force-with-lease`.
**Prevention:** the repo already documents the `$?`-after-a-pipe trap. Never `echo`
a success message downstream of a pipe; check the push's own status.

**14. Unbounded output.** `git ls-files 'plugins/soleur/*.md'` matched recursively and
burned ~7k tokens (`hr-never-run-commands-with-unbounded-output`).
**Recovery:** none needed; cost only.
**Prevention:** `--name-only`, `| head`, or a bounded pathspec on every listing.

**15. Guard 1's mutation battery went stale after the helper redesign.** Its anchors
no longer existed, so it reported LANDING-FAILED rather than a verdict.
**Recovery:** rewrote the battery against the new design.
**Prevention:** an anchor-based battery is coupled to the shape it mutates; redesign
the subject, re-derive the battery.

**16. `conftest.py` labelled aborts "pytest" when running under unittest.**
**Recovery:** moved the call into `pytest_configure()`.
**Prevention:** a runner-named message needs a runner-specific hook.

### Forwarded from `session-state.md` (plan phase, pre-compaction)

**17. deepen-plan gate 4.7 rejected the first run** — `## Observability` lacked the
required `logs:` field. **Recovery:** added `where`/`retention`.
**Prevention:** read the gate's required-field list before writing the section.

**18. AC15's citation loop flagged a forward reference** the plan had introduced
(`mutation-matrices.md`, created later by `/work`). **Recovery:** cited the directory.
**Prevention:** a plan may not cite a file it has not yet created; cite the directory.

**19. The first-draft architecture was wrong and was replaced before commit** — it
aimed a new `fixture-scan.py --rule gitenv` at ~900 test files. Two independent
reviews converged on the hook entry points being the real closed set.
**Prevention:** prefer a guard over an enumerable, closed set to a shape rule over an
open corpus. Working as intended: the challenge gate caught it pre-commit.

**20. Cross-reference nit** — `decision-challenges.md` cites `## Deferral`; the
section is `### Deferral`. Content anchor still resolves. One-off.
**Prevention:** cite by heading TEXT, not heading LEVEL — `cq-cite-content-anchor-not-line-number`
already prefers the anchor, and the level is the part that drifts when a section is nested.

### Found during compound, filed rather than fixed

**21. `gdpr-gate-self-test.test.sh` writes fabricated `deny` events into the
operator's real `.claude/.rule-incidents.jsonl`** — the file `compound` Phase 1.5
step 3.5 reads as *deviation evidence*, and that `rule-metrics-aggregate.sh` rolls
into the committed `rule-metrics.json`. Measured: one run appends 8 rows, two of them
`event_type: deny` with synthetic staleness, plus an `applied` row naming
`apps/web-platform/lib/auth/foo.ts` — a path that has never existed. 47 such rows were
already present.
**Recovery:** none in this PR — different subsystem. Filed as #7853; ledger restored
from a copy after measurement.
**Prevention:** the same class as #7833 itself, and the second miss of the same sweep
(`d0d3b5d68` sandboxed the *hook* suites; this one execs the gate script instead). See
`hr-write-boundary-sentinel-sweep-all-write-sites`.

**22. I ran `git stash list` in a worktree.** The hook denied it
(`hr-never-git-stash-in-worktrees`), correctly — the rule covers even the read-only
`list` subcommand.
**Recovery:** re-ran the check with `git show HEAD:<path>` into a scratch file, which
is what the rule's own remediation text says to do.
**Prevention:** the rule is unconditional; there is no read-only exemption to reason
my way into. `git show <commit>:<path>` answers every question `stash list` would.

**23. A path-repointing sweep keyed on the string form, not the subject.** After
archiving the spec directory I rewrote its four citations with a `sed` on the
fully-qualified `knowledge-base/project/specs/...` path. `INDEX.md` cites the same
directory *relative* (`project/specs/...`), so it was missed — and a residual grep
for the fully-qualified form would have come back clean.
**Recovery:** caught by grepping for the bare directory name rather than the path I
had just substituted; fixed both `INDEX.md` entries and verified all three archived
targets resolve on disk.
**Prevention:** exactly the failure the `compound` skill warns about — grep the
**subject** (the directory, the resource, the claim's referent), never the phrasing
you happen to have used. A residual-zero count is evidence about a string, never
about a claim. Then verify each rewritten target actually exists.

**24. A pre-existing lint failure surfaced by an archival `git mv`.** `session-state.md`
carried MD022/MD032 violations that no gate had seen, because the file had never been
staged; the `git mv` restaged it and the pre-commit `lint-fixture-content` step failed.
**Recovery:** fixed the seven heading/list blank-line violations inline.
**Prevention:** a `git mv` is a staging event for content nobody wrote today. Expect
an archival commit to surface latent lint on every file it moves, and budget for it
rather than treating the failure as a regression.

**25. My completion monitor's exit condition was satisfied by the wrong state.** I keyed
"the commit finished" on `[ -s "$LOG" ]` — log file non-empty — but the pre-commit hook
writes progressively, so it fired seconds after the run started and reported an unchanged
HEAD as though it were the result.
**Recovery:** re-armed on the commit's actual PID.
**Prevention:** a monitor's predicate is an assertion, and it needs the same question as
any other: *what states satisfy this besides the one I mean?* "Log has bytes" is true from
the first line onward.

**26. `pgrep -f 'git commit -F -'` matched its own command line; the monitor died exit 144.**
**Recovery:** switched to `kill -0 <pid>` against a PID captured beforehand.
**Prevention:** the repo already documents this exact trap — `review/SKILL.md` carries
"a `pgrep -f 'test-all\.sh'` matched its own command line and killed the invoking shell
(exit 144)" — in the same bullet list I appended to earlier in this session. Reading the
rule did not transfer to the command I typed ten minutes later, which is a better argument
for a mechanical check than for another prose bullet. Never `pgrep -f` a pattern the waiter's
own command line contains; capture the PID or use a sentinel.

**27. I reported the commit as successful when it had FAILED — the same defect as #13, in the
phase that documented #13.** The background task returned exit 0; that was `tail`'s status,
because the commit was followed by `echo` and `tail` in the same compound command. HEAD was
unchanged and the full gate had reported `363/369 suites passed, 3 failed`.
**Recovery:** caught by checking `git log` rather than trusting the reported code.
**Prevention:** capture the status of the command you care about *into a variable on its own
line* (`git commit -F - >log 2>&1; rc=$?`), and verify the OUTCOME (HEAD moved) rather than
any exit code. This is now the second occurrence in one session; prose has not been enough.

**28. Two of my four new guard suites' floors were invisible to the repo's own vacuity
meta-guard.** `scripts/guard-vacuity-floor.test.sh` blocked the commit with
`mutant-construction failures GREW to 18 (ratchet is 15)` naming three of my suites, plus
`hook-git-env-coverage.test.sh` scoring NO_FIRE. The floors were **not** vacuous — they fired
correctly under a neutered assertion machinery — but they emitted `FLOOR: …`, which is not in
the oracle's sentinel vocabulary (`[FATAL]`, `FAIL:`, `vacuit`, `assertion floor`, …), so a
correct firing scored as a failed mutant construction.
**Recovery:** renamed the sentinel to `[FATAL] assertion floor: …` in all four suites. The
meta-guard then went to 23/23, the covered firing population grew 69 -> 73, and construction
failures returned to the ratchet at 15.
**Prevention:** when a repo runs a meta-guard over guards, the guard's OUTPUT is part of its
contract, not just its behaviour. Read the oracle's accept-vocabulary before inventing a
sentinel spelling. My own review, two mutation batteries and a ten-agent panel all missed
this; the meta-guard caught it in 33 seconds.

**29. A suite that passes standalone and fails under the hook (not mine, but confirmed).**
`.claude/hooks/memory-backstop.test.sh` returns `RESULT: PASSED 54 [live: yes]` rc=0 when run
directly, and fails inside `lefthook run pre-commit` with
`T8 real hook did not apply (outcome='skipped' reason='claude_pid_not_found')` — it cannot
locate the live Claude PID from inside the hook's process tree.
**Recovery:** none; confirmed pre-existing and out of scope (`wg-when-tests-fail-and-are-confirmed-pre`).
**Prevention:** worth noting that this is #7833's own theme one directory over — a test whose
verdict depends on what the surrounding process environment happens to provide.

**30. A two-day stall that was neither my code nor the tests: an orphaned run held a
repo-global lock.** The compound commit sat in `flock -w 3600 -x 10` on
`.git/soleur-session-state/locks/test-all.lock` for 1d22h. The holder was another session's
`test-all.sh` for PR #7838, started Sep 4 18:31 and **reparented to `systemd --user`** — its
Claude session was gone, and no live session existed in that worktree.
**Recovery:** confirmed the orphan (PPID 1, zero live sessions in the 7791 worktree, PR
untouched for two days), killed it with operator approval, and removed its partial
`/var/tmp/ship7791/all.log`; no `all.rc` had been written, so no false verdict was left for a
resuming session.
**Prevention:** the lock's own `-w 3600` did not save us — the waiter sat 46x its timeout. A
lock whose holder has been reparented to init is mechanically detectable; the contention
preamble reports tmp-entry deltas but not holder liveness. Worth a guard.

**31. The full gate was skipped on this commit, and that is disclosed rather than hidden.**
After the lock cleared, the commit was killed by the harness for low memory: swap was 100%
exhausted (8 KiB free of 2 GiB) with `Committed_AS` at 37 GB against 30 GB RAM, 13 Claude
sessions holding ~6.1 GB and a browser ~5.5 GB. With operator approval the commit was made
`--no-verify`.
**Evidence standing in for the gate**, all re-run AFTER the final edit: guard-vacuity-floor
23/23 (covered firing population 73, construction failures 15 = ratchet);
hook-git-env-coverage 8/0; git-tripwire 24/0; hook-git-env-receipt 6/0; git-env-list-parity
10/0; markdownlint clean on every touched file; the python sibling imports. The staged content
is markdown, an archival move, six citation-string edits and four one-line sentinel changes.
**Prevention:** a skipped gate must be named in the artifact, not just in the conversation —
ship's Phase 4 still owes a full battery, and whoever reads this commit should know the
pre-commit gate did not run on it.

## Instrument yield

Worth recording because it changes the running order. Each instrument found a
**disjoint** set:

| Instrument | Cost | Found |
|---|---|---|
| shellcheck, semgrep, repo lints | seconds | a real defect in code I wrote hours earlier |
| mutation batteries | minutes | guard-erasure and floor vacuity |
| escape probes | minutes | every P1 in the matchers |
| ten-agent panel | ~1M tokens | the deny-list shape, the ceiling symlink, the missing preload |

`lint-trap-tempfile-ownership` hit code from this same session that neither my own
review nor two mutation batteries caught. On a guard-shaped PR, **run the cheap
deterministic lints before the panel** — they are seconds against six figures of
tokens, and they are not looking for the same things.

## Key Insight

On a PR whose subject is a guard, the guard is the part everyone checks and the
scaffolding is the part everyone trusts. Invert it. Specifically:

1. Write **escape rows before mutation rows**. A mutation score says the battery is
   sensitive; it says nothing about whether the predicate is the property.
2. When a PR ships more than one guard, ask what each **guarantees about the
   environment the others run in** — that is where an assertion's domain silently
   empties.
3. **Detect-set and remediate-set are one set**, and the relationship between them
   needs its own test, because it is a property of neither file.
4. Where the vocabulary belongs to someone else — git's environment, a platform's
   API — **sweep by shape, never enumerate**. A list is a claim that goes stale
   without notice, and the four names I missed included a proven code-execution
   vector.

## Related

- [Every defect the panel found was in my verification, not my fix](2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md) — same headline, #7801, two days earlier
- [A guard that cannot be driven red is vacuous — four rounds, four instances](2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md)
- [Every check I shipped was narrower than the name it carried](2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md)
- [Four of my checks certified something narrower than their names](2026-09-04-four-of-my-checks-certified-something-narrower-than-their-names.md)
- Measurements: `knowledge-base/project/specs/archive/20260904-163540-feat-one-shot-7833-git-dir-beats-cwd/measurements.md`
- Follow-ups: #7849 (adopt `gitFixtureEnv()` at every fixture-creating suite), #7853 (incident-ledger leak)

## Tags

category: test-failures
module: test-fixtures
