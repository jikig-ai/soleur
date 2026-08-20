---
title: The install step that hung was installing something already there
date: 2026-08-19
category: workflow-issues
module: .github/workflows
tags: [ci, package-install, unbounded-hang, runner-image, guard-vacuity, acceptance-criteria, supply-chain]
related_issues: [7572, 7574, 7613]
related_prs: [7510, 7623]
related_learnings:
  - knowledge-base/project/learnings/2026-08-19-i-hardened-my-verifier-twice-and-its-sample-was-still-a-sample.md
  - knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md
---

# Learning: the install step that hung was installing something already there

## Problem

Three workflows in the `skill-security-scan` family each opened with the same step:

```yaml
- name: Install jq
  run: sudo apt-get update -qq && sudo apt-get install -y -qq jq
```

One run of it hung and blocked a merge for roughly an hour.

The step has no `timeout-minutes` and no retry, and `apt-get` has no useful default timeout of its
own, so a slow or unreachable package mirror stalls for as long as the job is permitted to run. The
job's own limit becomes the failure's duration. Nothing in the step distinguishes "the mirror is
slow" from "the mirror is gone", and nothing bounds either.

The part worth keeping is not that the step lacked a timeout. It is **what it was installing**.

Six workflow files install `jq`, and the split is the whole argument:

```bash
git grep -lE 'apt-get install[^|;]*\bjq\b' origin/main -- '.github/workflows/*.yml' \
| sed 's|^origin/main:||' \
| while read -r f; do
    git show "origin/main:$f" | grep -qE 'which jq' \
      && echo "GUARDED       $f" || echo "UNCONDITIONAL $f"
  done
```

```
GUARDED       .github/workflows/apply-sentry-infra.yml
GUARDED       .github/workflows/deploy-docs.yml
GUARDED       .github/workflows/sentry-audit-gate.yml
UNCONDITIONAL .github/workflows/skill-security-scan-corpus.yml
UNCONDITIONAL .github/workflows/skill-security-scan-postmerge.yml
UNCONDITIONAL .github/workflows/skill-security-scan-pr-trailer.yml
```

Every other installer in the repository checks whether `jq` is already present and no-ops when it
is. These three did not — they were **the only unconditional installers**, and they are the three
this change fixes. Every remaining workflow that uses `jq` simply calls it and has been green.

So the step was buying nothing. `jq` ships in the GitHub-hosted runner image; the install was a
network round-trip, an unpinned package fetch, and an unbounded hang, in exchange for a binary that
was already on the PATH.

### Count what you claim — and say which denominator you counted

Two cautions, both of which this file got wrong before review caught them.

**State the denominator once.** An earlier draft said "38 workflows invoke the jq binary and only 5
install it", then two sentences later described three guarded plus three unconditional installers —
3 + 3 = 6, not 5. Both numbers were correctly measured and they answered *different questions*:
6 is the repo-wide installer count, while 5 counts only installers that ALSO contain a literal `jq`
invocation. `skill-security-scan-corpus.yml` is the sixth, and it drops out of the second set
because it has **zero** non-install `jq` tokens — it reaches `jq` only indirectly, through
`run-self-test.sh` → `run-scan.sh`. A reader who adds 3 + 3 and gets 6 is right, and one denominator
silently became the other mid-paragraph.

**A consumer count is definition-dependent, so publish the command or drop the number.** "How many
workflows invoke the jq binary" ranges from ~35 to ~50 across defensible filters — comment-only
matches, composite actions under `.github/actions/`, and whether install lines count. The argument
here does not need that number: it rests on the installer split above, which is exactly
reproducible. Where a figure IS load-bearing, print the command beside it, per
[[2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix]].

**And exclude `gh --jq`.** `gh` embeds **gojq**, so a `gh api --jq` call proves nothing about
whether the standalone `jq` binary exists. Counting those would have inflated the evidence for the
exact claim the change rests on.

## The trap: deleting it would have been verified by nothing

The obvious fix is to delete the step. That fix is correct and its verification is vacuous, which
is the transferable part.

Every `jq` consumer in `skill-security-scan-pr-trailer.yml` sits inside a step carrying:

```yaml
if: steps.diff.outputs.no_new_skills == 'false'
```

A PR that adds no SKILL or agent files — such as the PR making this very change — leaves all of
them skipped. The gate then reports `success` having never executed `jq` once. A green required
check on the deletion PR would have been **evidence about a code path the run did not take**, and
it would look identical to a green run on a runner where `jq` had been removed.

The fix is to make the proof unconditional rather than to make the removal smaller:

```yaml
- name: Assert jq present (runner-image dependency — no install, no network)
  run: jq --version
```

No network, no package manager, no `if:`. Whenever one of these workflows runs, the assertion runs,
so its green means what it appears to mean — and a future runner image dropping `jq` fails
immediately and legibly instead of surfacing as a confusing `jq: command not found` several steps
later inside a scan script.

**"Unconditional" is a property of the STEP, not a promise that the step executes on your PR.** The
review panel caught this overstated in an earlier draft of this very file. The step has no `if:`,
but the *workflow* still has triggers, and on the PR making this change only one of the three
actually ran:

| workflow | trigger | ran on the PR that changed it |
| --- | --- | --- |
| `skill-security-scan-pr-trailer.yml` | `pull_request`, no `paths:` | **yes** |
| `skill-security-scan-corpus.yml` | `pull_request` + a 6-pattern `paths:` filter | no — the diff matched none of them |
| `skill-security-scan-postmerge.yml` | `push: branches: [main]` only | no — it has no PR trigger at all |

So CI-green on that PR was direct evidence for exactly one workflow. The other two inherited it only
through a separate premise — that all three `runs-on: ubuntu-latest` jobs draw the same runner image
— which the assertion does not itself establish. That premise is sound here, but it is an inference,
and the honest claim names it rather than letting one green check stand in for three.

**The general rule: when you remove a step that provisions a dependency, the assertion that
replaces it must run unconditionally.** If the thing that would catch your mistake is behind a
guard your change does not trigger, you have not verified the change — you have only observed that
nothing objected.

Two of the three sites turned out to have unguarded consumers anyway, which is worth checking
rather than assuming: `corpus` reaches `jq` indirectly (`run-self-test.sh` → `run-scan.sh`, which
calls it throughout), and `postmerge` calls it directly. Only `pr-trailer` — the one originally
scoped, and the only required check of the three — had the guard problem.

**What the assertion still does not prove: a capability floor.** `jq --version` exits 0 on any `jq`,
including builds predating the flags the scanner actually uses — `--rawfile` (jq ≥ 1.6) at
`run-scan.sh`, `--argjson` at `parse-override.sh`, `-Rsn` + `inputs` at `lib.sh`. A capability-shaped
probe such as `jq -n --argjson x '{"a":1}' '$x.a'` would assert the flags rather than mere presence.
This was left as-is deliberately: the removed `apt-get install -y -qq jq` carried no version floor
either, so the exposure is **unchanged**, not newly introduced — and a fix should be scoped as its
own change rather than smuggled in under a diff whose acceptance criteria pin it at two lines.

## Second trap: an acceptance criterion that no implementation could satisfy

The plan's AC3 read *"`actionlint` exits 0 on all three workflows."*

`origin/main` already exits 1. It carries 11 pre-existing shellcheck findings (SC2221, SC2222,
SC2005, SC2016) in scan steps this change does not touch. No reachable implementation of this PR
could satisfy that wording. The two ways to make it pass are both wrong:

1. Fix the unrelated pre-existing warnings — silent scope creep, and the PR's own anti-widening
   criterion forbids it.
2. Quietly run a looser command and report its result as the AC — verifying a weaker claim than the
   one recorded.

The AC was re-keyed onto the property it was actually protecting — *this change adds no lint debt* —
and stated as a delta: the finding set at HEAD must be byte-identical to the same command run
against `git show origin/main:<path>`. Measured 11 at base, 11 at head, `diff` empty, none citing
the new step. Because the replacement is two lines for two lines, no line numbers shift and the
comparison is exact rather than normalized.

**Key an acceptance criterion for a whole-file linter onto the delta, not the absolute**, whenever
the file has pre-existing findings. An absolute AC on a dirty baseline is not a strict criterion;
it is an unsatisfiable one, and unsatisfiable criteria get quietly relaxed at the moment they are
checked — which is the worst time, because the relaxation is invisible in the artifact.

## Third trap: the brief asserted an obligation instead of probing for one

This work was commissioned as *"one file in `knowledge-base/project/learnings/`, closes the
workflow-gate obligation"* for merge `45ea9f7e9`. That obligation did not exist. The merge had
discharged it itself, shipping two learning files in the same commit:

```
$ git show --name-status --format='' 45ea9f7e9 | awk '$1=="A" && $2 ~ /learnings\//'
A  knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-...md
A  knowledge-base/project/learnings/2026-08-19-i-hardened-my-verifier-twice-...md
```

The tempting conclusion is that the repo needs an obligation *tracker* — a persisted record of which
merges still owe a learning. It does not, and the reason is worth stating because the tracker is the
locally obvious repair. **The obligation is derivable from git at any time**, by the one-line probe
above. A stored ledger would add a mechanism whose requirement is already met, and it could not even
answer this instance: a ledger started today says nothing about merges that predate it. That is a
deferral target that cannot reach the defect it was proposed for.

What actually failed was cheaper than any mechanism: the state was *inferred* rather than *probed*,
when the probe was one command and available the whole time. The same shape as the stale-inherited-number
class in [[2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix]] —
an inherited claim about the tree, carried forward without re-running the thing that settles it.

Use `--name-status` filtered to `A` rather than `--stat` when the count matters. A review pass on
this very file reported *three* learning files from `--stat`; the correct answer is two, and
`--name-status` shows it unambiguously along with whether each path was added, modified or renamed.

## What to do next time

- Before adding a package-install step to CI, check whether the runner image already ships the
  tool. `jq`, `curl`, `git`, `python3`, `unzip` and friends are present on `ubuntu-latest`.
- If you genuinely are unsure, guard the install so it no-ops when the tool is already present. Two
  shapes exist in this repo and the right one depends on where the job runs:
  `which <tool> >/dev/null 2>&1 || sudo apt-get install -y <tool>` on a VM runner
  (`apply-sentry-infra.yml`, `sentry-audit-gate.yml`), and the **`sudo`-less** form inside a
  container, where the job is already root — `deploy-docs.yml` runs in the Playwright container and
  its own comment says the bare `apt-get` is correct there. Copying the `sudo` form into a container
  job gets you `sudo: command not found`.
- Note what "the runner image ships it" is scoped to: the **image**. A job with `container:` or on a
  self-hosted runner is a different image and inherits none of this — which is why `deploy-docs.yml`
  installing `jq` is correct rather than redundant, and why it is the weakest of the three guarded
  installers as evidence for the premise.
- Any step that can touch the network needs `timeout-minutes`. An unbounded step turns a transient
  mirror problem into a merge-blocking outage.
- When removing a provisioning step, verify the replacement assertion is reachable on the very PR
  that removes it. Grep the consumers for `if:` guards before trusting the green.

## Cross-references

- **ADR-188** —
  [`knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`](../../engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md).
  The same underlying reality (CI package installs fail transiently and are not a property of the
  code under test) seen from the test-harness side rather than the workflow side.
- [[2026-08-19-i-hardened-my-verifier-twice-and-its-sample-was-still-a-sample]] — a verifier whose
  sample never covered the region that changed. Sibling of the guard-vacuity trap above: there the
  anchors missed the region, here the guard skipped the step.
- [[2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix]]
  — measure at the granularity you will claim.
- The T5 deferral record —
  [`knowledge-base/project/specs/archive/20260816-203421-feat-one-shot-7291-t5-mutation-network-flake/tasks.md`](../specs/archive/20260816-203421-feat-one-shot-7291-t5-mutation-network-flake/tasks.md)
  §5.4, for how that branch dispositioned six proposed scope-out rows into three filings and three
  resolved decisions across two CONCUR rounds.

## Session Errors

**My CI-status monitor reported a false all-green while every check was still pending.**
The poll was `gh pr checks <n> --json name,bucket 2>/dev/null || echo '[]'`, and its terminal
condition was "count of entries whose bucket is `pending` equals zero". A transient `gh` failure
produced `[]`; an empty array trivially satisfies "zero pending"; the monitor emitted
`ALL-CHECKS-SETTLED / all green`. A direct query moments later showed **38 checks, all pending**.

**Recovery:** I pulled the run status independently instead of trusting the notification, which is
the only reason it surfaced. The corrected poll requires a non-empty result set with every member
settled, and reports a probe failure as its own distinct outcome rather than folding it into the
success branch.

**Prevention.** A poll's terminal condition must rest on **positive evidence** — *this many things
exist and all of them are done* — never on the **absence** of a not-done marker. Absence is what
"finished" and "the probe never answered" look like from the outside, and the failure resolves
toward the reassuring one. Two mechanical rules:

- `|| echo '[]'` (or `|| true`, or `2>/dev/null` alone) on a probe converts an error into a
  confident empty answer. Validate the probe's output shape first (`jq -e 'type=="array"'`) and
  branch to a `PROBE-FAILED` arm; a monitor that cannot distinguish "nothing pending" from "could
  not look" is not measuring the thing it names.
- Require a non-empty denominator. `total > 0 && pending == 0` rejects the empty-array case that
  `pending == 0` alone accepts.

This is the same defect the rest of this file is about, committed by the instrument rather than the
CI step: a check whose passing state is indistinguishable from its broken state. It cost nothing
here only because the claim was independently re-derived — which is the habit, not the mechanism.
