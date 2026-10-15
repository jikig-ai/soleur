---
title: "chore: verify peer-plugin-audit sub-mode against travisvn/awesome-claude-skills"
type: chore
date: 2026-05-15
lane: procedural
issue: 2749
parent_pr: 2734
---

# Verify `peer-plugin-audit` sub-mode against `travisvn/awesome-claude-skills`

Follow-through verification (per ship Phase 7 Step 3.5 of #2734) confirming the
`soleur:competitive-analysis peer-plugin-audit <repo-url>` sub-mode works
beyond its seeding corpus (`alirezarezvani/claude-skills`). The expected
deliverable is a structured advisory entry written to the appropriate tier of
`knowledge-base/product/competitive-intelligence.md`, then issue `#2749` closed
with the artifact linked.

## Enhancement Summary

**Deepened on:** 2026-05-15
**Detail level:** MINIMAL (procedural verification — see "Implementation Detail Level" below)
**Live verifications run during deepen-pass:**

- `gh pr view 2734 --json state` → `MERGED` ✓ (citation accurate)
- `gh issue view 2749 --json state` → `OPEN` ✓ (citation accurate)
- `gh repo view travisvn/awesome-claude-skills --json licenseInfo,stargazerCount,forkCount` → `licenseInfo: null`, 12,561 stars, 1,363 forks ✓
- `gh api "repos/travisvn/awesome-claude-skills/git/trees/HEAD?recursive=1" --jq '.tree[].path \| select(endswith("SKILL.md"))'` → empty (zero SKILL.md files) ✓ — load-bearing finding driving the Research Reconciliation pivot from 4-section report to "Non-audit outcome" branch.
- AGENTS.md rule-ID citation grep over plan body → zero matches (no fabricated/retired rule IDs to fix).
- SSH / network-outage keyword scan → no triggers (Phase 4.5 skipped per spec).
- User-Brand Impact section validation → present, non-empty, threshold `none` with valid scope-out reason; `Files to Edit` does not match the canonical sensitive-path regex (single internal CI markdown file).

**Per-section deepen agent fan-out — intentionally not spawned.** This plan is a single-skill invocation against a documented branch of an existing procedure (`peer-plugin-audit.md` §"Non-audit outcome") with one file edited. The load-bearing risks (procedure routing, non-audit branch coverage, single-file scope, Closes-keyword automation) are encoded in 12 ACs + 4 Sharp Edges already; spawning architecture-strategist / pattern-recognition / type-design / data-integrity agents on a markdown advisory entry would inflate the artifact without changing the work shape. The autonomous-loop API-budget operator preamble (`hr-autonomous-loop-skill-api-budget-disclosure`) authorizes scoping deepen-plan fan-out down for procedural lanes.

## Research Reconciliation — Issue Body vs. Codebase Reality

Plan-time probe of the target repo (`gh repo view travisvn/awesome-claude-skills` +
`gh api .../git/trees/HEAD?recursive=1`) surfaces three facts the issue body and
the source PR `#2734` did not enumerate. Each materially changes what the
verification actually exercises.

| Issue / PR claim | Codebase reality | Plan response |
|---|---|---|
| "verify peer-plugin-audit works against a second repo" implies a skill-library audit producing a 4-section overlap-matrix entry | Target repo contains **zero `SKILL.md` files** (`gh api ... \| select(endswith("SKILL.md"))` returned empty). It is an awesome-list — a curated README of links to *other* skill libraries, not a skill library itself. | Verification target shifts from the **happy-path 4-section report** to the procedure's documented **non-audit outcome branch** (`peer-plugin-audit.md` §"Non-audit outcome"): write a short advisory entry "category mismatch; no audit produced", do NOT add an Overlap Matrix row. The verification still confirms the sub-mode works beyond seeding corpus — it confirms *the error branch* works, which the seeding corpus did not exercise. The 4-section report is **not producible** for this target by design. |
| Issue body: "Expected: 4-section report with inventory / high-value gaps / overlap / architectural patterns" | Procedure's Step 2 + "Non-audit outcome" branch: zero SKILL.md → short advisory note instead of 4-section report. | Honor the procedure as authored, not the issue body's pre-probe expectation. The deliverable is the **advisory entry**; the report-shape mismatch is a finding to record in the verification artifact. |
| Target repo `licenseInfo: null` per `gh repo view` (no LICENSE file detected) | License classification per procedure Step 1.4: "default all recommendations to 'inspire only'". Combined with the awesome-list shape, no port recommendations are even applicable. | Note "LICENSE not detected" in advisory entry per procedure Step 1.4 + Step 2 short-form. |

Stars/forks at audit time (for the audit-trail line): **12,561 stars / 1,363 forks** (`gh repo view --json stargazerCount,forkCount` at 2026-05-15).

## User-Brand Impact

- **If this lands broken, the user experiences:** stale `competitive-intelligence.md` (no entry for the audited repo) + a still-open follow-through issue (`#2749`) that misrepresents the sub-mode's coverage. No user-facing surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — read-only audit of a public GitHub repo, no operator-session data, no third-party API beyond `gh`/`WebFetch` against `github.com`.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: this is a follow-through verification touching a single knowledge-base markdown file (an internal CI report) and closing one GitHub issue — no production code, no user-facing surface, no regulated data, no schema/auth/API edits.`

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` returned no entry whose body references either `competitive-intelligence.md` or `peer-plugin-audit.md`. **None.**

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Sub-mode invoked end-to-end.** Run `skill: soleur:competitive-analysis peer-plugin-audit https://github.com/travisvn/awesome-claude-skills` from `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2749`. Skill exits without abort.
- [x] **AC2 — Procedure routing correct.** SKILL.md Step 1 routes to `references/peer-plugin-audit.md` before the `--tiers` branch (verifiable via skill output mentioning peer-plugin-audit; procedure says "checked first").
- [x] **AC3 — `gh repo view` succeeds at Step 1.** No HTTP 404/401 during input validation; license recorded as "not detected" per `licenseInfo: null`.
- [x] **AC4 — Step 2 inventory enumeration confirms zero SKILL.md.** The skill's Step 2 `gh api ... | select(endswith("SKILL.md"))` invocation against the target returns empty. This is the load-bearing check that triggers the non-audit branch.
- [x] **AC5 — Non-audit outcome branch fires.** Per `peer-plugin-audit.md` §"Non-audit outcome": skill writes a short advisory note (or log-only note) and does NOT add an Overlap Matrix row. Verify by reading the diff to `competitive-intelligence.md`: the diff MUST NOT contain a new row in the Tier 0 or Tier 3 Overlap Matrix table (`| **<name>** | ... |` shape). The diff MAY contain a short prose advisory under an existing tier OR a new "Peer-plugin audits" log section, with the words "category mismatch" and "no audit produced".
- [x] **AC6 — Advisory entry includes audit-trail metadata.** The advisory entry contains: repo URL, license classification ("not detected"), audit date (`2026-05-15`), auditor (`soleur:competitive-analysis peer-plugin-audit`), star/fork counts at audit time, and a one-line statement that the repo is an awesome-list (no SKILL.md files).
- [x] **AC7 — Frontmatter timestamp updated.** `competitive-intelligence.md` frontmatter `last_updated:` and `last_reviewed:` set to `2026-05-15`.
- [x] **AC8 — No parallel files written.** Verify no file created under `knowledge-base/product/research/peer-plugin-audits/` (procedure §"Output routing": "Single destination prevents stale copies"). `find knowledge-base/product/research/ -type f -newer .` returns nothing peer-plugin-audit-shaped.
- [x] **AC9 — Single-repo update.** `git diff --name-only main..HEAD` lists exactly `knowledge-base/product/competitive-intelligence.md` (plus the plan/spec/tasks artifacts emitted by the pipeline itself).
- [ ] **AC10 — PR body cites verification artifact.** PR body links to the modified `competitive-intelligence.md` line(s) via GitHub permalink AND uses `Closes #2749`. _(deferred to ship phase)_

### Post-merge (operator)

- [ ] **AC11 — Issue closed via `Closes #2749` automation.** GitHub auto-closes `#2749` at merge. No manual `gh issue close` needed.
- [ ] **AC12 — Verification recorded.** `gh issue view 2749 --json closedAt,closedByPullRequestsReferences` shows `closedAt: <merge time>` and the closing PR linked.

## Test Scenarios

- **Given** the target repo has zero SKILL.md files, **when** the skill invokes Step 2 inventory enumeration, **then** the Step 2 `gh api ... select(endswith("SKILL.md"))` returns empty AND the procedure routes to §"Non-audit outcome" instead of §"Step 3 — Depth-assessment sampling".
- **Given** the procedure §"Non-audit outcome" branch, **when** the skill writes to `competitive-intelligence.md`, **then** the diff adds a short advisory entry (no Overlap Matrix row).
- **Given** `licenseInfo: null` from `gh repo view`, **when** the procedure classifies license at Step 1.4, **then** the advisory entry records "LICENSE not detected" verbatim per the procedure's prescribed string.
- **Given** the verification artifact lives at the canonical destination, **when** the PR merges with `Closes #2749`, **then** issue `#2749` auto-closes and the closing PR is linked.

## Files to Edit

- `knowledge-base/product/competitive-intelligence.md` — add advisory entry (per procedure §"Non-audit outcome") + bump `last_updated` / `last_reviewed` frontmatter to `2026-05-15`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-2749/tasks.md` — pipeline-emitted, derived from this plan (Save Tasks phase).

## Plan-Time Procedure Verification

Two pre-execution greps confirm the procedure's routing matches what `/work` will hit:

1. **SKILL.md routes peer-plugin-audit before `--tiers`:** Step 1 sub-mode-detection block at `plugins/soleur/skills/competitive-analysis/SKILL.md:21-27` checks the literal `peer-plugin-audit` argument prefix and reads `references/peer-plugin-audit.md`, THEN halts (`Stop (do not fall through to tier selection)`). Verified.
2. **Non-audit outcome is canonical, not a workaround:** `references/peer-plugin-audit.md:208-209` ("Non-audit outcome") explicitly handles the zero-SKILL.md case with a "short advisory entry (or log-only note)" and the prescription "do not add an Overlap Matrix row". Verified.

## Sharp Edges

- **Plan-time `gh repo view` already happened during this planning session** (12,561 stars, 1,363 forks recorded above). `WebFetch` results are session-cached per `peer-plugin-audit.md` §"Session-caching note", but the `gh` CLI calls hit the live GitHub API on each invocation and will re-fetch at /work time — expect star/fork counts to drift between plan-time and /work-time. Use the /work-time numbers in the actual advisory entry, not the plan-time ones (this plan's "12,561 stars" line is for plan-record only).
- **Do NOT invent a "Skill Library" tier.** Procedure §"Output routing" forbids inventing new tiers in this sub-mode (CI-team decision). If the audited repo does not fit any existing tier, the procedure's instruction is to "flag this in the report and request taxonomy guidance from the CI team" — for an awesome-list, the appropriate placement is a short note under Tier 3 (closest semantic neighbor) OR a brief "log-only" footnote section. The advisory entry's title MUST NOT introduce a new `## Tier <N>: ...` heading.
- **The seeding-corpus audit (`alirezarezvani/claude-skills`) was added by the 2026-04-18 monthly CI scan (PR `#2697`) and is still present on `main`** as the `**alirezarezvani/claude-skills**` row in the Tier 3 Overlap Matrix (line 56 of the file at plan time). PR `#2734` introduced the `peer-plugin-audit` sub-mode and dropped a *parallel* "Skill Library" tier seed from its own branch (commit `e91e7bf6` was internal to that PR's branch and is not reachable from `main`); it did NOT remove the alirezarezvani row, which had landed via `#2697` a week earlier. Net effect: this verification's advisory entry is the first **non-audit outcome** artifact (sub-section `### Peer-Plugin Audit Log (non-audit outcomes)`); the happy-path audit pattern is already represented above by the alirezarezvani row. Match the file's existing prose style.
- **Awesome-list ≠ skill library is the load-bearing finding.** If during /work the agent observes that `gh api .../SKILL.md` returns one or more files (e.g., via a future repo restructuring), abort the non-audit branch and run the full 4-section procedure. The plan-time probe is a cheap re-verification, not a guarantee. The /work agent MUST re-run `gh api "repos/travisvn/awesome-claude-skills/git/trees/HEAD?recursive=1" --jq '.tree[].path | select(endswith("SKILL.md"))'` itself and act on the actual result.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled above with `threshold: none` + scope-out reason.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a procedural verification of an existing CI sub-mode that updates a single internal markdown report. No new code, no UX, no schema, no infra, no legal/regulated-data surface, no marketing distribution. The CPO already owns `competitive-intelligence.md` (per its frontmatter `owner: CPO`); appending a verification-artifact advisory entry to a CPO-owned report under the existing taxonomy does not warrant a fresh CPO assessment for a single-line procedural update.

## Implementation Detail Level

**MINIMAL.** This is a procedural verification (run an existing skill against a new target, record the outcome, close the issue). No architectural decisions, no API design, no test framework selection. The procedure file (`peer-plugin-audit.md`) IS the implementation spec.

## References

- Issue: #2749
- Source PR (sub-mode introduced + revert of seeding): #2734
- Procedure: `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md`
- Skill entry: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Output destination: `knowledge-base/product/competitive-intelligence.md`
- Target repo: <https://github.com/travisvn/awesome-claude-skills>
