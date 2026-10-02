# Red-on-main quarantine (probe dispositions)

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 when the poll reports a failing
check (`bucket == "fail"` or `cancel`). Added for #9402 — a check whose
same-named job is already red on `main` must never cost this PR a rerun cycle,
a `soleur:test-fix-loop` dispatch, or an autonomous fix attempt; it is reported
as a tracked issue instead.

**Plugin root in this file:** this file is Read, not delivered by the skill
loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. Resolve it
exactly as
[settle-then-admin-merge.md](settle-then-admin-merge.md) prescribes (the prefix
of the path you read this file from, cut at its last `/skills/`); a CWD-relative
path runs the checked-out repository's copy, which may not carry the probe.

## The probe

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/check-red-on-main.sh" \
  "<check-name>" --run-id <failing-run-id> --report [--repo owner/repo]
```

`--report` is part of the ONE prescribed call, not a flag you add on a second
run: it files/dedupes the tracker on a red verdict, auto-closes the check's own
sentinel trackers on a green verdict (so a tracker filed today heals itself the
first time a later probe observes main green — the filed issue carries this same
recipe), and is a no-op on `no-evidence`/`error`.

`<check-name>` is the check-run/job NAME verbatim — the join key between
`gh pr checks` output and a run's `jobs[]`. Exact match, including a `(n/m)`
matrix suffix; never prefix a matrix leg against its parent name. The run id
comes from the `link` field of `gh pr checks --json name,link`
(`actions/runs/<run-id>`), or from the `gh run list --commit` recipe in
SKILL.md's "Classify the failing STEP" block.

The probe resolves the failing run's workflow, scans up to 5 completed
`main`-branch runs of that workflow (newest first), and verdicts on the FIRST
run where the job reached a real conclusion — `skipped` and absent jobs are not
evidence, so a path-filtered main push never produces a quarantine.

| Exit | Verdict marker | Meaning |
|---|---|---|
| 0 | `verdict=green-on-main` | Job's latest exercising main run was green — this failure is this PR's to own |
| 1 | `verdict=red-on-main` | Same-named job concluded `failure`/`timed_out`/`cancelled`/`startup_failure` on main — quarantine-eligible |
| 2 | `verdict=no-evidence` | No completed main run in the window exercised the job — NOT quarantined |
| 3 | `verdict=error` | gh/API failure — NOT quarantined |

Every invocation emits exactly one stdout marker:
`SOLEUR_RED_ON_MAIN verdict=<v> check="<name>" main_run=<id> main_conclusion=<c>`.

## Dispositions

**Fail-closed: only `red-on-main` changes behavior.** `green-on-main`,
`no-evidence`, and `error` all fall through to the existing Phase 7 handling
unchanged — the classify-the-step rules, the network-fetch rerun exception, and
the `fix_attempt_count` ladder apply exactly as before. An unproven claim is
worse than a rerun.

Is the check required? The poll loop already fetches the required set once at
entry (`gh api 'repos/{owner}/{repo}/rules/branches/main'`); `gh pr checks
--required` answers it directly for a single check.

| Verdict | Check is advisory | Check is required |
|---|---|---|
| `red-on-main` | The single `--report` probe call has already filed/deduped the `ci/main-broken` tracker — **continue**; the check never gated merge. No `gh run rerun`, no `soleur:test-fix-loop` for it. | The single `--report` call has already filed/deduped the tracker — **escalate immediately**: "main is broken, tracked as #N". NO rerun, NO `soleur:test-fix-loop`, NO merge attempt — a required red still blocks the merge. |
| `green-on-main` | Unchanged existing behavior (`--report` auto-closed any stale tracker for this check) | Unchanged existing behavior (same auto-close) |
| `no-evidence` / `error` | Unchanged existing behavior | Unchanged existing behavior |

One probe call per failing check, at terminal-fail decision time only — never
per-tick (`gh run rerun` operates on completed runs anyway, and the gh budget
is per-failing-check).

## The tracker sentinel

`--report` dedupes open `ci/main-broken` issues by a per-check sentinel comment
line in the issue body:

```text
<!-- soleur:red-on-main check="<name>" -->
```

- On `red-on-main`: an existing open issue carrying this check's sentinel gets
  a comment, not a duplicate; otherwise a new issue is filed. A `gh issue list`
  failure warns and files NOTHING — never a duplicate on a transient error.
- On `green-on-main`: comment-and-close ONLY issues carrying OUR sentinel for
  that exact check name — never a human-filed or monitor-sentinel tracker
  (the #7374 lesson; `soleur:main-health-monitor`'s closer retires only its own
  sentinel, which is why this sentinel is a distinct token).

## Sharp edges

- **Masking is accepted, not ignored.** A check red on main can ALSO be freshly
  broken by this diff. Quarantine suppresses only the rerun/fix loop — the
  tracking issue records the check and the merge gate is unchanged, so the
  signal is not destroyed.
- **`cancelled` counts as red** on main (the same `!= 'success'` convention
  `notify-main-failure` uses), and `startup_failure` is red (the runner never
  got to measure the job — the run IS broken); `skipped`, `stale`,
  `action_required`, and `absent` never count as anything — none is a verdict
  the job reached on code.
- **A renamed job degrades to `no-evidence`** — the safe direction: old
  evidence stops matching rather than quarantining the wrong check.
- Probe stderr/nonzero-other-than-1 is never silent: the marker still prints
  `verdict=error`, and `soleur:ship` treats it as not-quarantined.
