---
title: The install step that hung was installing something already there
date: 2026-08-19
category: workflow-issues
module: .github/workflows
tags: [ci, package-install, unbounded-hang, runner-image, guard-vacuity, acceptance-criteria, supply-chain]
related_issues: [7572, 7574, 7613]
related_prs: [7510]
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

The part worth keeping is not that the step lacked a timeout. It is **what it was installing**:

```
$ # workflows invoking the jq binary, excluding `gh --jq` call sites
38
$ # ...of which install it
5
```

Of those five, three (`deploy-docs.yml`, `sentry-audit-gate.yml`, `apply-sentry-infra.yml`) guard
the install behind `which jq >/dev/null 2>&1 ||`, so on a normal runner they no-op. The three
`skill-security-scan-*` files were **the only unconditional installers in the repository**. The
remaining 33 workflows just call `jq` and have been green for as long as they have existed.

So the step was buying nothing. `jq` ships in the GitHub-hosted runner image; the install was a
network round-trip, an unpinned package fetch, and an unbounded hang, in exchange for a binary that
was already on the PATH.

### Count what you claim, not what looks similar

The `38` above excludes `gh api --jq` / `gh ... -q` sites deliberately. `gh` embeds **gojq**, so a
`gh --jq` call proves nothing about whether the standalone `jq` binary exists. Counting them would
have inflated the evidence for the exact claim the change rests on. This is the same discipline as
[[2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix]]:
project the measurement onto the scope you are actually going to assert.

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

No network, no package manager, no `if:`. It runs on every invocation of all three workflows, so
the green check means what it appears to mean, and a future runner image dropping `jq` fails
immediately and legibly instead of surfacing as a confusing `jq: command not found` several steps
later inside a scan script.

**The general rule: when you remove a step that provisions a dependency, the assertion that
replaces it must run unconditionally.** If the thing that would catch your mistake is behind a
guard your change does not trigger, you have not verified the change — you have only observed that
nothing objected.

Two of the three sites turned out to have unguarded consumers anyway, which is worth checking
rather than assuming: `corpus` reaches `jq` indirectly (`run-self-test.sh` → `run-scan.sh`, which
calls it throughout), and `postmerge` calls it directly. Only `pr-trailer` — the one originally
scoped, and the only required check of the three — had the guard problem.

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
- If you genuinely are unsure, use the repo's existing fallback idiom —
  `which <tool> >/dev/null 2>&1 || sudo apt-get install -y <tool>` — which costs nothing on a
  normal runner and does not hang when the tool is already there.
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
