---
title: A census cell naming two markers reports the union as each member
date: 2026-09-18
category: workflow-patterns
module: plugins/soleur/skills/brainstorm
issue: 8299
tags: [measurement, premise-validation, harness, census, counts]
---

# A census cell naming two markers reports the union as each member

## Problem

Issue #8299 opened with a measurement table. Its headline row read:

> Skills carrying a harness marker block (`grok-harness-invoke` / `soleur-cloud-mode`) — **64 of 99**

That row is the entire basis for the issue's scope: 64 covered, 35 to backfill. Read
naturally, it says Grok coverage is 65%. Measured against `origin/main`:

```console
$ git grep -l 'grok-harness-invoke:start' -- 'plugins/soleur/skills/*/SKILL.md' | wc -l
12
$ git grep -l 'soleur-cloud-mode:start'  -- 'plugins/soleur/skills/*/SKILL.md' | wc -l
64
$ comm -23 <(git grep -l 'grok-harness-invoke:start' -- 'plugins/soleur/skills/*/SKILL.md' | sort) \
           <(git grep -l 'soleur-cloud-mode:start'  -- 'plugins/soleur/skills/*/SKILL.md' | sort)
          # empty — grok is a strict SUBSET of cloud
```

The 64 is a **Devin/cloud** number. Grok is named on **12** skills — the pipeline set
only. **Codex is named by zero markers and zero skills.** The real gap was roughly four
times the reported one, and it was concentrated in a harness the row appeared to cover.

## Root cause

An `A / B` alternation inside one census cell computes `|A ∪ B|` and presents it under
a label that names both. Every reader — including the issue's author, three domain
leaders, and me — resolves that label distributively: "64 carry a grok block *and* a
cloud block." Nothing in the cell signals that one marker contributes 12 and the other
64, still less that one is a subset of the other.

The tell is grammatical, not numerical: **the cell has one number and two nouns.** No
sanity check on the number catches it, because the number is correct — it is correct
about a population nobody asked about.

## Solution

Before quoting any count whose label names more than one thing, split the alternation
and measure each member, then measure the relationship between them:

```bash
# per-member, then the set relation — three commands, ~10 seconds
git grep -l '<marker-A>' -- '<glob>' | wc -l
git grep -l '<marker-B>' -- '<glob>' | wc -l
comm -23 <(git grep -l '<marker-A>' -- '<glob>' | sort) \
         <(git grep -l '<marker-B>' -- '<glob>' | sort)   # empty ⇒ A ⊆ B
```

An empty `comm -23` is the finding. Subset relations are the case where the union
number is *most* misleading, because it equals the larger member exactly and therefore
looks like a clean measurement of it.

## Key Insight

**A claim about the repository's own measurement or examination state is a claim to
verify, and it is the cheapest high-yield probe available.** #8299 carried four such
claims. Every one was false, and each was refuted by a single command:

| Claim | Probe | Result |
| --- | --- | --- |
| "64 of 99 carry a harness marker block (`A` / `B`)" | split the alternation, then `comm -23` | 12 / 64, and A ⊆ B |
| "Tests asserting marker-block parity: **0**" | `git grep -ln 'soleur-cloud-mode' -- 'plugins/soleur/test/'` | `devin-cloud-mode.test.ts:450` — `describe("soleur-cloud-mode marker fleet")`, byte-identity + `expect(marked.length).toBe(67)` |
| "the `GROK_PLUGIN_ROOT` question … **today it is unexamined**" | grep the ADR corpus for the *mechanism* | ADR-179, accepted 2026-08-11: bare anchor canonical, a `:-` default **is the vector**; residual tracked by open #7453 |
| "Soleur ships to **four harnesses**" | `git ls-files \| grep -oE '^\.[a-z0-9_-]+/' \| sort -u` | six trees in three kinds — path-shared, generated, hand-ported |

The pattern across all four: an issue author writes "unexamined", "zero tests", "four
harnesses" from **their own reading history**, not from the repository's state. The
words are sincere and they are load-bearing, and they are exactly the sentences no
gate checks. Grep the *mechanism* before letting such a claim bound the option space —
the "unexamined" probe alone invalidated an entire work item and redirected another to
an already-open issue.

Corollary, and the part that stings: **a hand-listed count reproduces the very bug the
issue reports, one level up.** #8299 exists because a skill edit considered only the
author's own harness. Its own framing then enumerated four harnesses when six exist.
The CPO named it: *"a snapshot that was already wrong before the issue was filed — that
is the failure mode repeating itself one level up."* The remedy is the same at both
levels and is already repo doctrine — **ADR-193 §5: "The population is DERIVED, never
listed."**

## Prevention

- Split every multi-noun census cell before quoting it; run `comm` for the set relation.
- Treat "unexamined" / "nothing does X" / "0 tests" as the **highest-yield** premise
  probes in an issue body, ahead of any numeric claim.
- Grep the ADR corpus for the proposed **mechanism**, not the cited issue numbers.
- When a subagent's count conflicts with yours, name **both populations** rather than
  picking a winner. That is what resolved Session Error 1 below.

## Session Errors

1. **I made the same error class myself, one level down.** I reported "74 skills use the
   `${CLAUDE_PLUGIN_ROOT:-…}` fallback." 74 is the count of SKILL.md files *mentioning*
   the variable; most use the **correct bare anchor**. The fallback population is 28
   SKILL.md / 32 files / 105 occurrences — and 105 matches ADR-179's own "~105 non-gate
   sites" exactly, which would have been the confirming cross-check had I looked.
   I verified the numerator and inherited the denominator.
   **Recovery:** the CLO subagent returned 32 against my 74; I reconciled the
   denominators (`-l` vs `-o`, `SKILL.md` vs the whole tree) instead of assuming the
   subagent was wrong.
   **Prevention:** when a subagent's count conflicts with the orchestrator's, the
   resolution is to print both populations explicitly — `files`, `lines`, `occurrences`
   — never to pick a winner. A conflict is evidence the denominators differ, not that
   one side miscounted.

2. **All three `/soleur:go` session gates no-op'd.** Step 0.0 emitted
   `SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=plugin-root-unverified`,
   Step 0.5 `SOLEUR_CLOUD_DETECT_SKIPPED reason=script-unreachable`, Step 0
   `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified` — because neither
   `CLAUDE_PLUGIN_ROOT` nor `GROK_PLUGIN_ROOT` is exported into the Bash tool
   environment (measured twice this session; independently measured three ways in
   ADR-179). So `wg-at-session-start-run-bash-plugins-soleur` has been a no-op on this
   harness, and the `.mcp.json` restore chained after it never ran.
   **Recovery:** re-ran `cleanup-merged` by hand against an identity-verified in-repo
   root; it reaped 188 temp dirs and surfaced a long-hidden
   `SOLEUR_ORPHAN_UNREMOVABLE … errno=EACCES names=feat-one-shot-supabase-bind-loopback`.
   **Prevention:** filed **#8308**. Distinct from #7453 — that one is about not
   executing the *customer's* file (fail-open on safety); this is fail-closed on safety
   but **fail-open on "did the gate run"**. Remedy 1 there is ADR-179's own prescription
   for payload scripts: resolve from `${CLAUDE_PROJECT_DIR}` then `BASH_SOURCE`, never
   CWD, keeping the identity preflight intact. Remedy 2 is a Better Stack monitor on
   `reason=plugin-root-unverified`, which would have surfaced this months ago rather
   than a brainstorm noticing it in passing.

3. **`gh issue create` hook-rejected for a missing `--milestone`.** The skill's own
   snippet carries the flag; I dropped it.
   **Recovery:** re-ran with `--milestone "Post-MVP / Later"`.
   **Prevention:** none needed — already hook-enforced, and the hook did its job.

4. **Pre-existing orphan worktree, surfaced not caused.**
   `SOLEUR_ORPHAN_UNREMOVABLE count=1 cleaned=0 errno=EACCES
   names=feat-one-shot-supabase-bind-loopback reason=rm-partial`. Triaged **recurring
   but pre-existing** and out of this session's scope.
   **Prevention:** none added here — it is a real standing condition that #8308's
   remedy 2 (alarming on the session-start markers) would surface on a schedule
   rather than by accident. Remediation path is `git-worktree` SKILL.md §Sharp Edges.

5. **`playwright` MCP server failed to connect.** Ambient; no bearing on this task,
   which needed no browser. Triaged **one-off**.
   **Prevention:** none — reporting a connection failure as a missing capability would
   have been the actual error, and it was avoided.

6. **Stray-backslash warnings from an over-escaped `grep -E` pattern** inside a
   double-quoted heredoc-adjacent command (`grep: warning: stray \ before "`). Output
   was still correct. Triaged **one-off**, cosmetic.
   **Prevention:** none — but note the warning was *visible*, which is why it was
   caught; a silently-wrong pattern is the failure mode worth fearing, and the
   per-member `comm` cross-check in the Solution above is what guards against it.

## Related

- `knowledge-base/project/brainstorms/2026-09-18-cross-harness-parity-gate-brainstorm.md`
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` §5
- `knowledge-base/engineering/architecture/decisions/ADR-224-slash-name-uniqueness-across-harness-component-namespaces.md` §1
- `knowledge-base/project/learnings/2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`
- `knowledge-base/project/learnings/2026-09-10-three-measurement-instruments-and-two-were-wrong-before-they-were-right.md`
- `knowledge-base/project/learnings/2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md`
- Issues: #8299 (re-scoped), #8306, #8307, #8308, #7453 (pre-existing)
