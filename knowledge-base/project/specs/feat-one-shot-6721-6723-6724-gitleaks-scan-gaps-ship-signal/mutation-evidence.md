# Mutation evidence (AC21)

Every claim below is a captured run, not a description of one. An unexercised
mutation claim is the defect class this PR exists to fix, so each mutation is
asserted to have LANDED by diffing against a pristine backup taken before any
edit — never against `HEAD`, which is dirty during a review pass. A mutation
that does not land reports a false result in both directions, so
"baseline-identical" is recorded as UN-RUN, never as evidence. The restore is
verified after every mutation.

Battery source: `scratchpad/mutation-battery.sh` (one-off; the assertions it
exercises are committed in `plugins/soleur/test/gitleaks-merge-commit.test.sh`).

## #6721 — `.github/workflows/secret-scan.yml`

Baseline: suite GREEN before mutating (asserted; a red baseline aborts the
battery, since mutation results against a red baseline are meaningless).

```
MUTATION: AC2: drop -m from cron log-opts
  landed: 4 line(s) changed
  RESULT: CAUGHT (suite exit 1)
      FAIL: shipped cron log-opts ('--all') MISSED merge-exclusive secret (rc=0) — #6721 is not fixed
      FAIL: expected log-opts="-m --all" in secret-scan.yml; found none

MUTATION: swap -m for --cc (silent no-op trap)
  landed: 4 line(s) changed
  RESULT: CAUGHT (suite exit 1)
      FAIL: shipped cron log-opts ('--cc --all') MISSED merge-exclusive secret (rc=0) — #6721 is not fixed
      FAIL: expected log-opts="-m --all" in secret-scan.yml; found none
      FAIL: a step ships --cc in log-opts (2) — T2 proves that gate cannot fire

MUTATION: T7: PR step switches to -m BASE..HEAD
  landed: 4 line(s) changed
  RESULT: CAUGHT (suite exit 1)
      FAIL: a PR/merge_group step uses '-m BASE..HEAD' (2) — coupling is confirmed above

MUTATION: delete all './gitleaks dir .' invocations
  landed: 4 line(s) changed
  RESULT: CAUGHT (suite exit 1)
      FAIL: expected >=2 './gitleaks dir .' invocations (cron + PR-side); found 0

MUTATION: reinstate stale '#6721 unfixed' comment
  landed: 2 line(s) changed
  RESULT: CAUGHT (suite exit 1)
      FAIL: push:main comment still describes #6721 as unfixed ('direction 1 would invert it')

  caught=5 gaps=0
  VERDICT: every mutation caught
```

## 1.5.1 — the `-m` PR-range coupling measurement (AC6c)

The plan recorded this as **INCONCLUSIVE**: the first attempt returned rc=0 on
both arms because the fixture never reached the state under test, and a silent
rc=0/rc=0 reads exactly like "no coupling". It was rebuilt deliberately with
explicit preconditions and is now **CONFIRMED**, not cleared.

Mechanism: GitHub sets `BASE_SHA` to `pull_request.base.sha` — main's TIP at
PR-event time, not the merge-base — so a routine "merge main into my branch"
puts main's own commits inside `BASE..HEAD`.

Fixture: clean main-sync merge, no conflict anywhere (deliberately NOT the
#6721 conflict shape). Preconditions asserted: planted secret fires standalone;
M is a genuine 2-parent merge; merge was clean; secret present in merged tree;
range is non-degenerate.

| arm | log-opts | rc | meaning |
|---|---|---|---|
| 1 (shipped) | `--no-merges BASE..HEAD` | 0 | trunk's secret NOT attributed to the PR |
| 2 (candidate) | `-m BASE..HEAD` | 1 | trunk's secret DOES count against the PR |
| 3 (contrast) | `--no-merges A..HEAD` | 1 | fork-point BASE puts it in range regardless |
| 4 (contrast) | `-m A..HEAD` | 1 | — |

**Verdict: COUPLING-CONFIRMED.** Adding `-m` to the PR job would make every
branch that syncs main inherit main's findings as its own. This is why the PR
and merge_group jobs get a full-tree `gitleaks dir` scan — an understood
failure mode — rather than `-m`. Pinned by T7, including the two preconditions,
so a future invalid fixture fails loudly instead of fabricating a clean result.

## #6723 — AC11 / AC12

AC11 (full main-ancestry scan under the shipped config), re-run after merging
the current `origin/main`, which had moved `plugins/soleur/skills/review/SKILL.md`
— the exact file the path carve-out anchors on:

```
--log-opts="--no-merges origin/main"   3099 commits scanned   no leaks found   rc=0
--log-opts="-m origin/main"            3134 commits scanned   no leaks found   rc=0
```

AC12 (working-tree findings, baseline config vs shipped config, same tree)
surfaced a real regression that the 29/29 suite could not see:

```
baseline: 8 findings   shipped: 9 findings
INTRODUCED: database-url-with-password  plugins/soleur/test/gitleaks-rules.test.sh:182
REMOVED:    (none)
```

Both `:182` and `:208` were explanatory **comments** carrying contiguous
credential-shaped literals — the fixtures themselves were already
runtime-assembled and safe. This mattered concretely because this same PR adds
`gitleaks dir .` steps to the PR, merge_group and push:main jobs, so those two
findings would have redded the gate on the very commit that introduces it.
Confirmed against a CI-equivalent tracked-only checkout:

```
before fix:  leaks found: 2   rc=1
after fix:   no leaks found   rc=0
```

The remaining 7 findings in the working-tree scan are all in an untracked,
gitignored local `.env` that no CI checkout ever contains.

## #6724 — AC14 mutation proofs

Against a pristine backup of `.claude/hooks/pre-merge-rebase.sh`:

```
MUTATION: Check 1 reverted to repo-global grep
  landed: 4 line(s) changed
  RESULT: CAUGHT — T-V1 went RED
    FAIL: T-V1 vacuity: todos/ on main only must NOT count as branch evidence
          (no incidents jsonl; exit=0 decision=)

MUTATION: remove Reviewed-By-Soleur trailer support
  landed: 5 line(s) changed
  RESULT: CAUGHT — T-V2 went RED
    FAIL: T-V2 zero-finding review with trailer was DENIED (the P0: clean branches deadlock)
```

Note the T-V1 failure shape: `decision=` empty. Under the old grep the gate does
not deny — it waves an unreviewed branch straight through, which is the defect
rather than a side effect of it.

**T-V2 initially SURVIVED the second mutation.** Its fixture subject was
`review: no findings`, which matches the *legacy* Signal 2 message pattern, so
the legacy signal was what allowed the branch and the test proved nothing about
the trailer it was named for. The subject is now neutral (`chore: post-review
checkpoint`), and the mutation is caught. T-V3 still survives that mutation by
design — the real script emits a `review: ` subject deliberately, for backward
compatibility — and its docstring now states that scope rather than reading as
trailer proof.

## AC18 — in-flight branch impact (measured, not assumed)

The plan required enumerating this rather than assuming it empty. It is not
empty: **17 of 18 open PRs** currently carry no review evidence under any of the
three signals, and will be denied at merge until review runs.

| Signal | Branches satisfying it |
|---|---|
| 1 — branch-scoped `todos/` | 0 of 18 |
| 2 — `review:` / `refactor:` commit | 1 of 18 (#6348) |
| 2 — `Reviewed-By-Soleur:` trailer | 0 of 18 (new; nothing has emitted it yet) |
| 3 — `code-review` labelled issue referencing the PR | 0 of 18 (queried per PR) |

Denied: 6729, 6727, 6726, 6725, 6659, 6640, 6299, 6279, 6190, 6150, 6089, 5997,
5705, 5653, 5210, 4970, 3729. Allowed: 6348.

This is the fix working, not a regression — those branches genuinely have no
review evidence, and the old gate passed them only because it could not fail.
But it is a real operational cost and it is why this is surfaced here rather
than discovered at the first blocked merge.

Clearing a branch is one command, no re-review required if review already ran:

```bash
bash plugins/soleur/skills/review/scripts/emit-review-trailer.sh --findings <n>
```

Branches that genuinely have not been reviewed should run `/soleur:review`,
which now emits the trailer as step 3.

**This PR is itself in the denied set (#6727)** — its own merge runs the new
hook, so it must carry the trailer like any other branch. The normal pipeline
produces that.
