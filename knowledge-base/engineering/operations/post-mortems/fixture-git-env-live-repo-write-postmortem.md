---
title: "Fixture tests wrote to the developer's live repository when run from a git hook"
date: 2026-09-06
incident_pr: 7840
incident_window: "unknown start — 2026-09-04T08:05:50Z (detected)"
recovery_at: "2026-09-04T14:00:00Z"
suspected_change: "none — latent since worktree-based development became the default; surfaced by adding a second git-using suite to plugins/soleur/test/"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - a git hook running a test runner from inside a linked worktree
  - a test that spawns `git` while inheriting the hook's environment
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Tests that build a temporary git fixture wrote into the developer's **real repository**
whenever they ran from a git hook. `git init` in the fixture initialised nothing, and the
fixture's commits landed on the developer's live branch and moved its tip.

No personal data and no production system were involved: the blast radius is a developer's
working repository. It is recorded as an incident because the operator's standing rule is that
any detected incident gets a post-incident report, and because uncommitted work in the affected
repository could have been lost.

## Status

resolved — the write path is closed at the runner boundary by PR #7840.

## Symptom

Repeated phantom `commit: base` / `commit: change` pairs in the reflog of a live feature branch,
whose contents were the fixture paths from `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts`
(`apps/web-platform/app/page.tsx`, `plugins/soleur/skills/ship/SKILL.md`,
`plugins/soleur/test/some-guard.test.ts`). The branch tip moved without the developer committing.

## Incident Timeline

- **Start time (detected):** 2026-09-04T08:05:50Z
- **End time (recovered):** 2026-09-04T14:00:00Z
- **Duration (MTTR):** ~6h from report to a verified fix on the branch

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-04-03 | First occurrence fixed per-file: `welcome-hook.test.ts` scrubbed its own git env. No sweep of sibling suites. |
| human | 2026-09-04T08:05:50Z | Incident detected. Phantom commits observed on `feat-one-shot-7708-p1b-fixture-operand-detector`; #7833 filed with a measured control/hostile comparison. |
| agent | 2026-09-04T~10:00Z | Mechanism reproduced: victim HEAD moves under an inherited `GIT_DIR`; `git -C <abs>` and `cwd:` are both overridden. |
| agent | 2026-09-04T~12:00Z | Fix landed at the runner boundary (`af4ba6abb`), plus the three-layer defence. |
| agent | 2026-09-04T~14:00Z | End-to-end verification: victim HEAD/refs/index unchanged; live-hook commit with 0 phantom commits. |

## Participants and Systems Involved

Local developer environment only: `lefthook` pre-commit, `bun test`, `vitest`, the python suites,
and any test spawning `git`. No production service, no customer data, no third party.

## Detection (+ MTTD)

- **How detected:** external/manual — the operator noticed phantom commits in their own reflog. No monitor existed for this class.
- **MTTD (mean time to detect):** unbounded. The first occurrence was 2026-04-03; the second was detected 2026-09-04. Any occurrence in between would have been silent.

## Triggered by

user — a developer running `git commit`, which fires the hook that runs the test suite.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The fixture's `git -C` operand is wrong or empty | Matches the earlier P1b operand family | Operands were correct and absolute; the victim was still written | rejected |
| The environment overrides the operand | `GIT_DIR=<victim>/.git` with `cwd=<fixture>` → fixture reports "not a git repository", victim HEAD becomes a phantom | — | **confirmed** |

## Resolution

Scrub the git-location environment at the **runner boundary** (`lefthook.yml`,
`scripts/test-all.sh`, `scripts/hooks/pre-push`), not per test file. Three layers, because the
first alone cannot detect its own absence:

1. L1 — the entry-point `unset` (the actual fix).
2. L2 — `hook-git-env-coverage.test.sh`, a ratchet over the closed hook-entry-point set, so a new unscrubbed entry point fails CI.
3. L3 — `lib/git-tripwire.ts`, a fail-loud rc=97 abort for any runner that *starts* holding a git-location variable. This is the only layer that catches a **transitive** spawn, which no source scan can see.

## Recovery verification

Measured on the branch, recorded in the archived
`specs/archive/20260904-163540-feat-one-shot-7833-git-dir-beats-cwd/measurements.md`:
victim repository HEAD, refs and index all unchanged across a hostile-`GIT_DIR` run; a real
lefthook commit produced 0 phantom commits; the tripwire returns rc=97 dirty and rc=0 clean.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the developer's branch tip move?** A fixture's `git commit` ran against the developer's repository.
2. **Why did it target that repository?** The `git` subprocess honoured `GIT_DIR` / `GIT_INDEX_FILE` over both its working directory and `-C`.
3. **Why were those variables set?** A git hook exports them, and in a **linked worktree** they are absolute paths. Every feature branch here is a worktree, so the hazardous arm is the normal one.
4. **Why did the test inherit them?** `execFileSync` inherits `process.env` by default, and the fixture passed only `cwd`.
5. **Why did this survive an earlier fix?** The 2026-04-03 fix was applied to one file. The defect is a property of the *runner's environment*, not of any file, so a per-file fix could not generalise one directory over.

**Final root cause:** the write boundary was treated as the command's operand when it is actually the process's environment.

## Versions of Components

- **Version(s) that triggered the outage:** any revision where a hook ran a git-using suite from a linked worktree without an environment scrub.
- **Version(s) that restored the service:** PR #7840.

## Impact details

### Services Impacted

None. Developer working repositories only.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.
- **Developer / operator running the test suite from a hook: affected** — phantom commits on the live branch, moved branch tip, and a risk to uncommitted work.

### Revenue Impact

None.

### Team Impact

Solo operator. Time cost: recovery on 2026-09-04, plus the earlier 2026-04-03 occurrence.

## Lessons Learned

### Where we got lucky

The reporter recovered without data loss. `git init` failing loudly in the fixture ("not a git
repository") is what made the phantom commits traceable to a specific suite — had the fixture
silently succeeded, the reflog would have shown commits with no attributable source.

### What went well

The reflog contained the fixture's own file paths, which identified the writing suite
unambiguously and turned a vague "my branch moved" into a reproducible measurement within hours.

### What went wrong

- A per-file fix in April was recorded as closing the class. It closed one file.
- No detector existed for the class between April and September, so recurrence was silent.
- The fix's own guards shipped with defects that the guards could not see: a 10/10 mutation score
  coexisted with ten escape corpora the guard wrongly accepted, and two guards from the same PR
  interacted to empty a third's assertion domain. Recorded in
  `knowledge-base/project/learnings/2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md`.

## Addendum — 2026-09-09 (#7987): the fixture-side defence landed, and shipped the same defect three times

Appended, not substituted: everything above is the 2026-09-06 record as written and stands
unchanged. This section records what the follow-on work found.

PR #7987 lands the **shell** half of the defence-in-depth layer that `## Action Items &
Follow-ups` tracks as #7849 — the layer *behind* the runner-boundary fix, for the case where a
suite is invoked without going through `scripts/test-all.sh` at all. It closes #7835 (the
issue filed for this incident's fixture-side residue) and leaves #7849 and #7822 open.

Re-measured on `a50ef75e2` with #7822's own predicate, made `git -C`-aware:

```
                          BEFORE   AFTER
repo-wide                     38      32
  plugins/soleur/test/         5       0     <- discharged by #7987
  remainder                   33      32
    of which .claude/hooks/   12      12     <- untouched by design
```

`test-helpers.sh` adoption across `plugins/soleur/test/*.test.sh` moves 44/88 → 49/89 under the
indirection-resolving encoding. The denominator grows because #7987 adds
`git-fixture-containment.test.sh`, which deliberately does **not** adopt: it controls the
tripwire, so sourcing the helper would abort it in the exact arms it exists to exercise.

### What this adds to `## Lessons Learned`

A seven-agent review found **three P0s in the PR whose entire subject is this incident**, and
each performed the harm recorded in `## Symptom` above. All three were reproduced on synthesized
decoys before being fixed:

- the new containment suite committed the developer's uncommitted work onto their live branch,
  flipped `commit.gpgsign`, and rewrote `user.email` — because it built its victim fixture with
  `git -C "$VICTIM"` *before* deriving its own scrub, and `-C` does not protect against an
  inherited `GIT_DIR`;
- `proc.test.sh` breached the caller while reporting `Total: 61  pass: 61  FAIL: 0`, rc=0;
- `fixture-dir-operand-assert.test.sh` reproduced the 2026-08-20 incident recorded in its own
  file header.

The single cause: **all three had a guard, and all three placed it downstream of the write it
describes.** A precondition detects; only a refusal prevents. The remedy was a refusal above the
first write, derived from the same source of truth rather than transcribed. Full write-up:
`knowledge-base/project/learnings/2026-09-09-a-precondition-detects-only-a-refusal-prevents.md`.

This belongs in the incident record rather than only in a learning file because it is direct
evidence about `## Where we got lucky`: the fixture-side residue was not merely unremediated
between 2026-09-06 and 2026-09-09 — the first attempt to remediate it re-performed it, and
reported green while doing so.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #7849 | Adopt `gitFixtureEnv()` at every remaining fixture-creating suite (defence in depth behind the process-boundary fix) | open |
| #7822 | Lint the remaining population against the sweep predicate — 32 repo-wide after #7987, 12 of them under `.claude/hooks/` (this issue's ask 2; asks 1 and 3 are discharged) | open |
