---
title: "fix(cron): fleet-wide headless skill resolution for /soleur:* claude-eval producers"
issue: 4993
branch: feat-one-shot-4993-fleet-headless-skill-resolution
type: bug
classification: code-fix
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-06-07
---

# 🐛 fix(cron): fleet-wide headless skill resolution — sibling claude-eval producers can't invoke /soleur:* skills

## Enhancement Summary

**Deepened on:** 2026-06-07
**Sections enhanced:** Premise Validation, Implementation, Precedent-Diff (new)
**Verification done live:** `claude --help` (flag grounding), `git grep` (authoritative
set), content-generator precedent (`cc3e9ab5`).

### Key Improvements
1. **Authoritative set expanded 8 → 10** — `event-ship-merge.ts` and `cron-bug-fixer.ts`
   (both missed by the issue table) confirmed in-scope via prompt grep.
2. **Load-bearing flag claim grounded in live `claude --help`** — `--plugin-dir <path>`
   "Load a plugin from a directory or .zip" is a real documented flag; `Skill`/`Task`
   are valid `--allowedTools` tokens. No fabricated CLI tokens.
3. **Precedent-diff gate satisfied (pattern is NOT novel)** — the fix is a verbatim
   repetition of the merged #4987 content-generator shape (see Precedent-Diff section).

### New Considerations Discovered
- The "cwd-relative discovery" comment is in 9 files (not just the 1 cited), incl.
  two non-skill-invoking producers (roadmap-review, community-monitor) — comment-only fix there.
- 6/10 producers already carry `Task` — the `--allowedTools` edit must be surgical
  (add only missing tokens) to avoid duplicating `Task`.

## Overview

PR #4989 (issue #4987) fixed `cron-content-generator`: a headless `claude --print`
cron eval cannot **resolve or invoke** `/soleur:*` plugin skills unless its spawn
argv carries **`--plugin-dir plugins/soleur`** (registers the symlinked plugin —
the interactive marketplace/`enabledPlugins` trust flow is skipped under `--print`)
**AND** `Skill` in `--allowedTools` (the allowlist gates skill invocation), plus
`Task` where the skill fans out subagents.

Multi-agent review of #4989 found content-generator is **not the only** producer
whose prompt instructs the eval to `Run /soleur:<skill>`. This plan applies the
identical, already-validated #4987 fix to every sibling producer that shares the
gap, reconciles the now-disproven "cwd-relative discovery" comments, and adds a
self-discovering cross-producer parity guard so the gap cannot silently re-open.

This is a **pure code change** against an already-provisioned surface
(`apps/web-platform/server/inngest/functions/`) — no new infrastructure, no schema,
no regulated-data surface. It is a mechanical repetition of a merged, validated fix.

## Premise Validation (Phase 0.6)

- **#4987 / PR #4989** (`cron-content-generator` fix): `gh` confirms merged
  (commit `cc3e9ab5`). The canonical fix is on `main`; this plan extends it. **Holds.**
- **Authoritative producer set re-grepped** (issue says "re-grep to confirm"):
  `git grep -n "/soleur:" apps/web-platform/server/inngest/functions/*.ts` plus a
  prompt-vs-comment audit. The issue's 8-row table is **incomplete** — two more
  producers invoke `/soleur:*` in their eval prompts and were missed:
  - **`event-ship-merge.ts`** → `Run /soleur:ship --headless` (no `Skill`, no `--plugin-dir`)
  - **`cron-bug-fixer.ts`** → `/soleur:fix-issue <N>` (no `Skill`, no `--plugin-dir`)
  Both use the same `setupEphemeralWorkspace` symlink mechanism, so they share the
  identical root-cause gap. **Premise expanded from 8 → 10.**
- **False positives excluded** (mention `/soleur:` but do NOT require the eval to
  invoke a skill): `cron-skill-freshness.ts` (emits `/soleur:archive-kb` as text in
  a generated issue checklist for humans), `cron-nag-4216-readiness.ts` (emits
  `/soleur:go #4216` as nag-message text). Out of scope.
- **Root-cause doc** `feature-request-plugin-dir-settings.md` confirms: headless
  `--print` skips the trust dialog, so `extraKnownMarketplaces`+`enabledPlugins`
  never auto-installs; the supported mechanism is the `--plugin-dir` flag. **Holds.**
- **Empirical probe** (issue suggested step #1): a contaminated local probe
  (passed) was traced to inherited user-level registration — `~/.claude.json`
  carries 60 soleur references; the ephemeral cron container has none. The
  fully-isolated authenticated probe was **infeasible at plan time** (no
  `ANTHROPIC_API_KEY` in this environment). The mechanism is nonetheless
  triple-confirmed (root-cause doc + contamination trace + the already-merged
  #4987 validation against the identical #4982 symptom). A live isolated probe is
  prescribed as a /work Phase 0 precondition (see below) so empirical confirmation
  is not skipped.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| 8 producers invoke `/soleur:*` | 10 do (issue missed `event-ship-merge`, `cron-bug-fixer`) | Fix all 10; document the two additions |
| "none pass `--plugin-dir`, several lack `Skill`" | Confirmed: 0/10 have `--plugin-dir`; 0/10 have `Skill`; 6/10 already have `Task` | Add `Skill,Task` + `--plugin-dir` to all 10 |
| `cron-competitive-analysis.ts:44-45` asserts disproven "cwd-relative" theory | The comment exists in **9** files (agent-native-audit, roadmap-review, legal-audit, growth-execution, seo-aeo-audit, competitive-analysis, community-monitor) + bug-fixer | Reconcile every occurrence, not just the one cited |

## Precedent-Diff (Phase 4.4) — pattern is NOT novel

This fix is a verbatim repetition of the canonical #4987 shape merged in PR #4989
(`cc3e9ab5`). Live-verified evidence:

- **`claude --help` (v2.1.168, grounding the load-bearing claim):**
  ```
  --plugin-dir <path>   Load a plugin from a directory or .zip
  --allowedTools, --allowed-tools <tools...>
  ```
  Confirms `--plugin-dir` is a real, documented flag and `--allowedTools` is the
  allowlist that `Skill`/`Task` must appear in. No fabricated CLI tokens (per the
  CLI-verification gate; addresses the #4989 Session-Error-1 dangling-citation class).

- **Canonical precedent — `cron-content-generator.ts` `CLAUDE_CODE_FLAGS` (target shape per producer):**
  ```ts
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Skill,Task",  // Skill,Task appended
  "--plugin-dir",
  "plugins/soleur",                                                 // inserted before --
  "--",
  ```
  Each of the 10 producers keeps its OWN `--allowedTools` base set + its OWN
  `--model`/`--max-turns`; only `Skill`(+`Task` if missing) is appended and
  `--plugin-dir plugins/soleur` is inserted before `--`.

- **Test precedent — `cron-content-generator.test.ts:133-161`:** three assertions
  (`Skill`+`Task` present; `--plugin-dir plugins/soleur` present; `--plugin-dir`
  index < `--` index) — mirror per producer.

No SQL/atomic-write/lock/RPC pattern is involved. No novel pattern; reviewers can
scrutinize against the merged #4989 diff directly.

## User-Brand Impact

**If this lands broken, the user experiences:** the affected audit/content crons
keep filing their `[Scheduled] …` issues (watchdog stays green) while the eval
silently hand-rolls degraded output instead of running the real skill — invisible
quality decay across content, growth, SEO, UX, legal, competitive, ship, and
bug-fix automation.

**If this leaks, the user's workflow is exposed via:** N/A — no data exposure
vector; this is a quality/observability defect, not a confidentiality one.

**Brand-survival threshold:** aggregate pattern. The blast radius is the *fleet* of
producers degrading together over time (the #4982/#4987 class), not a single-user
data incident. No per-PR CPO sign-off required; section present per Phase 2.6.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `git grep -L '"--plugin-dir"' <each of the 10 in-scope files>` returns
  empty (every in-scope producer carries `--plugin-dir` followed by `"plugins/soleur"`).
- [ ] **AC2** — For each of the 10 producers, the `CLAUDE_CODE_FLAGS` `--allowedTools`
  string contains `Skill` and `Task` (verified by per-producer source-regex test).
- [ ] **AC3** — For each of the 10 producers, `--plugin-dir`'s index in `CLAUDE_CODE_FLAGS`
  is **before** the `--` end-of-options marker (mirrors content-generator test:
  `cron-content-generator.test.ts:155`).
- [ ] **AC4** — The disproven "Plugin resolution is cwd-relative … discovered from
  spawn cwd" comment is corrected in all occurrences:
  `git grep -c "cwd-relative" apps/web-platform/server/inngest/functions/*.ts` returns
  0 lines asserting auto-discovery-without-flag as fact (re-grounded in the
  `--plugin-dir` mechanism). Scope-out: `cron-bug-fixer.ts:29` comment (a) about
  plugin discovery is reworded too.
- [ ] **AC5** — A self-discovering cross-producer parity test exists: it greps every
  `cron-*.ts` + `event-*.ts` in the functions dir, and for any whose **prompt**
  (not comment) contains `Run /soleur:` or `/soleur:<skill>`, asserts the file's
  `CLAUDE_CODE_FLAGS` contains `--plugin-dir`, `Skill`, and `Task`. The test's
  discovered set MUST equal the 10 known producers (a sanity assertion guards
  against the glob silently matching zero, per the awk-self-match / empty-corpus
  Sharp Edges).
- [ ] **AC6** — Full `vitest` suite for `test/server/inngest/` passes
  (`./node_modules/.bin/vitest run test/server/inngest/`); `tsc --noEmit` clean.

### Post-merge (operator)

- [ ] **AC7** — `Ref #4993` (not `Closes`) in PR body; close #4993 after merge via
  `gh issue close 4993` once CI is green. (Standard code-fix; merge IS the
  remediation — no separate operator apply step.)
  *Automation: `gh issue close` runs in /soleur:ship post-merge; no manual step.*

## Implementation Phases

### Phase 0 — Preconditions (/work)

1. **Live isolated probe** (completes the plan-time-infeasible empirical step).
   With an `ANTHROPIC_API_KEY` available in the dev environment, run the substrate
   shape in an **isolated** config to prove the gap and the fix:
   - Set up a temp workspace symlinking `plugins/soleur` into `<tmp>/plugins/soleur`.
   - Run `CLAUDE_CONFIG_DIR=<fresh-tmp> claude --print --max-turns 2 --allowedTools "Bash,Read,Skill" -- "<probe>"` (no `--plugin-dir`) → expect skill UNAVAILABLE.
   - Re-run with `--plugin-dir plugins/soleur` → expect skill AVAILABLE.
   Pin the two outputs into the PR body / spec. If the no-flag probe resolves the
   skill anyway, **stop and reconcile** — #4987's root-cause analysis would be
   incomplete (issue possibility #2). [Automation: feasible — `claude` CLI v2.1.168
   is on PATH; only blocker at plan time was the missing API key.]
2. Re-confirm the authoritative set with the AC5 grep before editing.

### Phase 1 — Apply the #4987 flag fix to all 10 producers

For each file below, edit `CLAUDE_CODE_FLAGS`: (a) append `,Skill,Task` to the
`--allowedTools` string if not already present (6 already have `Task`; none have
`Skill`), and (b) insert `"--plugin-dir", "plugins/soleur",` immediately before the
`"--",` marker. Preserve each producer's existing `--model` and `--max-turns`
(they differ per producer — do NOT homogenize). Mirror the comment block from
`cron-content-generator.ts:53-76` (grounded in `claude --plugin-dir` help text),
adapted per file.

`## Files to Edit`

1. `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts` — add `Skill` (+ keep `Task`) + `--plugin-dir`
2. `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — add `Skill,Task` + `--plugin-dir`
3. `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — add `Skill,Task` + `--plugin-dir`
4. `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` — add `Skill` (+ keep `Task`) + `--plugin-dir`
5. `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — add `Skill` (+ keep `Task`) + `--plugin-dir`; fix cwd-relative comment
6. `apps/web-platform/server/inngest/functions/cron-legal-audit.ts` — add `Skill` (+ keep `Task`) + `--plugin-dir`; fix cwd-relative comment
7. `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — add `Skill,Task` + `--plugin-dir`; fix cwd-relative comment
8. `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — add `Skill,Task` + `--plugin-dir`
9. `apps/web-platform/server/inngest/functions/event-ship-merge.ts` — add `Skill,Task` + `--plugin-dir` *(missed by issue table)*
10. `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` — add `Skill,Task` + `--plugin-dir`; reword comment (a) *(missed by issue table)*

> Rationale for `Skill,Task` on all (not per-skill subagent analysis): mirrors the
> merged #4987 fix verbatim. `--allowedTools` is an allowlist — adding `Task` where
> a skill does not fan out subagents is harmless and avoids fragile per-skill
> fan-out inference. `growth`, `seo-aeo`, `ship` DO spawn subagents; `fix-issue`,
> `campaign-calendar` do not — but uniform `Skill,Task` is the robust, precedent-aligned choice.

### Phase 2 — Reconcile disproven "cwd-relative" comments

`## Files to Edit` (comment-only, additionally to any above):

11. `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — fix cwd-relative comment (prompt does NOT invoke `/soleur:` so NO flag change; comment correction only)
12. `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — fix cwd-relative comment (prompt does NOT invoke `/soleur:`; comment-only)

Replace the "Plugin resolution is cwd-relative — … discovered from spawn cwd"
assertion with the verified mechanism: the symlinked `plugins/soleur` is registered
**only** via `--plugin-dir` under `--print`; cwd-relative discovery does NOT apply
in headless mode. For roadmap-review/community-monitor (no skill invocation), the
comment correction prevents the disproven theory from misleading future edits.

### Phase 3 — Tests (RED → GREEN)

`## Files to Edit / Create`

13. Extend each in-scope producer's existing `*.test.ts` (all 10 exist) with the
    three #4987 assertions (mirror `cron-content-generator.test.ts:133-161`):
    `--allowedTools` includes `Skill`+`Task`; `--plugin-dir plugins/soleur` present;
    `--plugin-dir` before `--`.
14. Add the **self-discovering parity guard**. Preferred home:
    `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts`
    already hosts list-driven cross-producer source-shape tests — add a new
    `describe("headless skill resolution parity (#4993)")` block there, OR create
    `cron-producer-skill-resolution.test.ts` if cleaner. The test:
    - reads every `cron-*.ts` + `event-*.ts` in `server/inngest/functions/`;
    - classifies each as skill-invoking if its **prompt** (a string the eval runs,
      excluding `//` comment lines) contains `/soleur:`;
    - asserts the discovered skill-invoking set === the 10 known files (sanity:
      length > 0 and equals expected, per empty-corpus Sharp Edge);
    - for each, asserts `CLAUDE_CODE_FLAGS` contains `--plugin-dir`, `Skill`, `Task`.

> Test runner: `vitest` (`package.json` `scripts.test`). Files live under
> `test/**/*.test.ts` to match `vitest.config.ts` `include` glob. Run:
> `./node_modules/.bin/vitest run test/server/inngest/`.

## Files to Create

- `apps/web-platform/test/server/inngest/cron-producer-skill-resolution.test.ts`
  *(only if not folded into `cron-producer-output-wiring.test.ts` — decide at /work)*

## Open Code-Review Overlap

None — no open `code-review` issues touch the 12 functions files or the test files
in scope (the only recent overlap, PR #4989, is already merged and is the source of
the pattern this plan extends).

## Domain Review

**Domains relevant:** none

No cross-domain implications — engineering-only tooling change to server-side cron
eval spawn flags. No user-facing UI surface (no `components/**`, `app/**/page.tsx`),
no schema/auth/API route, no infrastructure, no regulated data. Product/UX Gate,
GDPR Gate (2.7), IaC Gate (2.8) all skip.

## Observability

```yaml
liveness_signal:
  what: cron-cloud-task-heartbeat watchdog per producer (existing) + the #4730
        output-aware heartbeat wiring (existing) — unchanged by this PR.
  cadence: per producer's existing cron schedule.
  alert_target: Sentry (existing postSentryHeartbeat sites).
  configured_in: each producer + _cron-claude-eval-substrate.ts (existing).
error_reporting:
  destination: existing Sentry capture sites in each producer; unchanged.
  fail_loud: yes — existing audit-issue fallback (#4988) + heartbeat unchanged.
failure_modes:
  - mode: skill still fails to resolve after fix (flag typo / wrong path)
    detection: Phase 0 live isolated probe + AC5 parity test (CI source-shape gate)
    alert_route: CI red on PR (blocks merge); no runtime regression possible.
  - mode: a NEW producer adds /soleur:* without the flags (gap re-opens)
    detection: AC5 self-discovering parity test fails in CI
    alert_route: CI red on the offending PR.
logs:
  where: existing stdout-tail capture (#4786) routed to Better Stack; unchanged.
  retention: existing Better Stack retention.
discoverability_test:
  command: ./node_modules/.bin/vitest run test/server/inngest/cron-producer-output-wiring.test.ts
  expected_output: parity block passes — all 10 skill-invoking producers carry
                   --plugin-dir + Skill + Task; discovered set length === 10.
```

> Note: this PR changes spawn FLAGS, not the observability layer. The fix's own
> correctness is gated at CI (source-shape parity test) + the Phase 0 live probe,
> not at runtime — there is no new runtime failure mode to instrument. The existing
> heartbeat + audit-issue fallback already cover the runtime silence axis.

## Test Scenarios

1. Each of the 10 producers: `--allowedTools` contains `Skill` and `Task`. (RED before fix.)
2. Each of the 10 producers: `--plugin-dir`,`plugins/soleur` present and before `--`. (RED before fix.)
3. Parity guard: discovered skill-invoking set === 10 expected files; no producer
   in the set lacks any of the three flags. (RED before fix, for the 9 non-content-generator producers.)
4. `tsc --noEmit` clean; full `test/server/inngest/` vitest suite green.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/TODO/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.**
  (This plan's section is filled: threshold = aggregate pattern.)
- The parity test (AC5) MUST distinguish a `/soleur:` token in a **prompt string**
  from one in a `//` comment — `cron-content-generator.ts` and others mention
  sibling skill names in comments. Classify on prompt content only, or the
  discovered set will over-match (e.g., `cron-skill-freshness`, `cron-nag-4216`).
  Sanity-assert the set equals exactly the 10 known files.
- Do NOT homogenize `--model` / `--max-turns` across producers — each was tuned
  per #4987-era PRs (opus vs sonnet; turns 40–80). Only add the two/three flags.
- `Task` is already present in 6/10 producers — appending `,Task` blindly would
  duplicate it. Edit the `--allowedTools` string surgically per file (add only the
  missing tokens), do not string-concat a fixed suffix.
- Mirror the empty-corpus / awk-self-match guard: the parity test's directory walk
  must assert `discovered.length > 0` (and === 10) so a glob that silently matches
  nothing fails loud instead of passing vacuously.

## Related

- #4987 / PR #4989 (`cc3e9ab5`) — content-generator fix (the first instance; pattern source).
- #4982 — verification run that surfaced the content-generator degradation.
- `feature-request-plugin-dir-settings.md` — headless plugin-registration root cause.
- `knowledge-base/project/learnings/2026-06-07-headless-claude-print-plugin-skill-resolution-needs-plugin-dir.md` — captured learning from #4987.
