---
date: 2026-07-30
category: integration-issues
module: ci-workflows
pr: 7071
issues: []
symptoms:
  - "A GitHub Actions step exits 1 and prints NOTHING, while continue-on-error hides the abort"
  - "`rc=$?` after a script invocation never executes; the whole `case \"$rc\"` below it is unreachable"
  - "A gitleaks allowlist entry silences a finding under `gitleaks dir` and reddens the scan under `gitleaks git`"
  - "Capturing a command's exit code flips a step's `outcome` to success and silently disarms a later gate"
  - "A python heredoc inside a `run: |` block makes the whole workflow YAML unparseable"
tags: [github-actions, bash, set-e, gitleaks, fail-closed, review]
---

# The step that could not report, and the guard that worked in one scan mode

Five measured findings from the third review round on PR #7071. Each has a reproduction;
none is inferred. Two extend existing learnings rather than restating them — see
[[2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential]] and
[[2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it]].

## 1. `set -uo pipefail` does NOT clear `-e`, so a bare invocation eats everything below it

**The defect.** A release-preflight step existed to turn a failure 15 minutes later into one
named up front. It read:

```yaml
run: |
  set -uo pipefail
  bash scripts/check-cloudflare-token-drift.sh --only REGISTRY_PUSH_ACCESS_TOKEN
  rc=$?
  case "$rc" in
    0) echo "verified live" ;;
    1) echo "::warning::…is STALE…" ;;
    *) echo "::warning::…could NOT run…" ;;
  esac
```

**Root cause.** `set -u` and `set -o pipefail` do not touch `-e`, and Actions runs a `run:`
block with no `shell:` key under `bash --noprofile --norc -eo pipefail {0}`. So a non-zero
exit from the script aborts the step *at that line*: `rc=$?` never runs, and the entire
three-valued diagnosis is unreachable. Only the `rc=0` arm was reachable, and
`continue-on-error: true` then hid the abort — a failed-but-tolerated step with no
annotation and no cause.

**Measured**, under both `bash -e {0}` and the real Actions shell:

```
$ bash --noprofile --norc -eo pipefail pf.sh   # script exits 1
step_rc=1                                       # …and NOTHING printed
$ bash pf.sh                                    # without -e
REACHED: ::warning:: STALE
$ bash -e -c 'set -uo pipefail; case "$-" in *e*) echo "-e STILL ACTIVE";; esac'
-e STILL ACTIVE
```

**Fix.** `rc=0; cmd || rc=$?`. Verified all three arms reachable at rc 0/1/2.

**Prevention.** Any `run:` block that inspects `$?` must capture with `|| rc=$?`. A step
whose diagnosis is its entire purpose deserves one offline run per arm — this is the
"a check that cannot report is indistinguishable from one that passed" class, and here the
check *was* the reporting.

## 2. …and capturing rc can disarm the gate the step feeds

Fixing (1) introduced its inverse, caught before commit. Adding `|| rc=$?` to a
token-drift step made the block **succeed**, which pins the step's `outcome` to `success`
forever. A later enforce step gated on `steps.token_drift.outcome == 'failure'` would then
never fire: present, readable as a gate, structurally inert.

**Fix.** Re-raise `exit "$rc"` *after* writing `$GITHUB_OUTPUT`. Outputs written before a
non-zero exit are still visible to later steps, and `continue-on-error: true` keeps the job
walking to its reporting steps.

**Prevention.** When you change how a step terminates, grep for every consumer of that
step's `outcome`/`conclusion` before committing. Exit-code capture and `outcome` are the
same signal viewed from two places.

## 3. A guard can work in one scan mode and silently no-op in another

A gitleaks allowlist bypass (see §4) is genuinely closed by `regexTarget = "line"` — under
`gitleaks dir`. Under `gitleaks git` (diff mode) the finding's `Line` field is **null**, so
a line-targeted allowlist matches nothing, the carve-out stops applying entirely, and the
scan reddens.

CI's PR job scans `--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"` — git mode. So the
"fix" would have disabled the exemption in the exact scan that gates every PR. Measured:
suite 46/46 green, branch history scan `leaks found: 1`.

**Prevention.** Before adopting a targeting/scoping change on any scanner, enumerate every
mode CI actually invokes (`grep -n 'gitleaks \(git\|dir\)' .github/workflows/`) and verify
the change in each. A guard that works in one mode and no-ops in another is worse than the
gap it closes, because the no-op is silent.

## 4. An anchored allowlist value bounds the CAPTURED TOKEN, not the credential

Extends [[2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential]],
which established the string-vs-credential divergence. The new instance is the **delimiter**
axis, which that file does not reach.

`generic-api-key` captures `([A-Za-z0-9_\-]{16,})`, so the capture ends at the first
character outside the class. An allowlist entry anchored `^<fixture>$` therefore matches
`KEY="<fixture>.<real-credential>"` exactly — the fixture is the whole Secret, and the
material after the `.` gets no finding of its own.

Reproduced on gitleaks 8.24.2 for `. : / + = @ ~ % ! , ; | ( # *`, space and `"`:

```
exempt path,   fixture + appended credential  -> findings=0
other path,    same content                   -> findings=1
```

Because (3) rules out the only mechanism that closes it, this shipped as a **documented
residual gap** with the measurement recorded at the entry — not as a reassurance.

**Prevention.** For any allowlist regex, state which of {secret, match, line} it is matched
against and what the rule's capture class is. "Anchored" is not a property of the
credential; it is a property of whatever the scanner handed the allowlist.

## 5. Marking a retracted claim: index nothing, and mark the surface the operator reads

Extends [[2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it]].
The orphaned-tail class recurred **four times** in one PR, and the fourth recurrence was
inside the commit that marked the third. Two new shapes:

**(a) A hand-maintained index of corrections is a second thing to keep true.** Replacing a
blanket "the rest of this bullet remains current" with a four-item index of what had been
marked: three of those markers did not exist, and the fourth named a phrase that occurs
nowhere in the repo except the index itself. It was false the day it was written — the same
"records coverage that isn't there" defect the commit was fixing one clause away. Mark items
in place; do not build a register of your own marks.

**(b) Mark the CALLER, not just the script.** A pre-destroy gate's premise was retracted and
the script header was marked. Its only caller — the workflow page an operator reads before
firing a typed-confirm destroy dispatch — still stated the retracted premise verbatim. The
marking landed everywhere except where the decision is made.

**Prevention.** After marking a retraction, `git grep` the retracted claim's distinctive
phrase and confirm every *call site* and *operator-facing* surface is marked, not only the
definition. Ask "where is this decision actually taken?" and mark there first.

## 6. A contention banner is a prompt to confirm, not a licence to dismiss

Two full-suite failures in this session, both while a sibling worktree ran the same runner
and `SIBLING_RUN_DETECTED` fired. They needed opposite dispositions:

- **Real, and mine.** `tests/scripts/registry-pull-path-health` — the suite for the script
  the branch had just changed to fail closed, still asserting `zero degraded => PASS rc=0`.
  Dismissing it as contention would have shipped a contract change with the contract
  asserting the reverse.
- **Real, and not mine.** `pdf-text-extract.test.ts` timed out at 15000ms; isolated re-run
  29/29 green at `tests 12.92s` against that 15s ceiling, in a file the branch does not
  touch. Third issue in that file's history (#3383/#3424/#3687, all closed).

**Prevention.** The discriminator is cheap and it is not the banner: does the failing suite
name something in `git diff --name-only origin/main...HEAD`? If yes, assume it is yours until
an isolated run says otherwise.

## Session Errors

- **SSH push/fetch rejected (`Permission denied (publickey)`)** despite the agent-loaded key
  being the one registered on the account — Recovery: pushed over HTTPS with a repo-local
  `gh auth git-credential` helper — Prevention: probe `git ls-remote` early in any session
  that will push; do not discover it at ship time.
- **Scratchpad under `/tmp` reaped twice mid-session**, destroying a running `test-all` log
  and its rc file — Recovery: relaunched with logs under `/var/tmp` — Prevention: never put
  a long-running log under `/tmp` here; it is a shared 4 GiB tmpfs with a reaper.
- **A failed `cd` into the reaped scratchpad wrote probe files into the worktree root** —
  Recovery: removed before staging — Prevention: `cd X && cmd` in one call, so a failed `cd`
  cannot leave the write to land somewhere else.
- **`git stash list` hook-denied** — used as a read-only probe — Recovery: dropped it —
  Prevention: the guardrail matches the verb, not the subcommand; there is no read-only
  exception.
- **`regexTarget = "line"` broke the branch history scan** — Recovery: reverted, documented
  as a measured residual — Prevention: §3 above.
- **A mutation of the new step-order suite over-captured the block** and reddened it for the
  wrong reason (4 "not found" instead of "sits AFTER") — Recovery: redone surgically, all 23
  step names preserved — Prevention: a mutation whose failure message doesn't match its
  intent is an un-run mutation; read the message, not just the colour.
- **A `python3 - <<'PY'` heredoc inside a `run: |` block broke the workflow YAML** (body at
  column 0 terminates the scalar) — Recovery: one-line python parse + a bash ladder —
  Prevention: keep embedded interpreters to one line inside block scalars.
- **`|| rc=$?` disarmed the enforce step** — Recovery: `exit "$rc"` after outputs —
  Prevention: §2 above.
- **Two blocking misses shipped in a review commit** (phantom-marker index; unmarked caller)
  — Recovery: both fixed after `code-simplicity-reviewer` DISSENT — Prevention: §5 above.
- **A python-patch escaping attempt failed with `SyntaxError`** — Recovery: used the Edit
  tool — Prevention: for multi-level-quoted shell/regex edits, use the editor, not a nested
  heredoc.
- **PR body diffstat stale twice** (`+3187` → `+3192` → `+3680`) — Recovery: re-derived from
  `git diff --shortstat` — Prevention: re-derive the diffstat at ship time, never carry one
  forward across commits.
- **`test-all` rc=1 from the gate's own suite** after making it fail closed — Recovery:
  updated the suite to the new contract, mutation-proven — Prevention: when changing a
  script's exit contract, run *its* suite before the full runner.
