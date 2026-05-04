---
title: Tasks — Scheduled audits + skill freshness telemetry
plan: knowledge-base/project/plans/2026-05-04-feat-scheduled-audits-skill-freshness-plan.md
issue: 3122
branch: feat-scheduled-audits-skill-freshness
date: 2026-05-04
---

# Tasks

Three independent tracks. Phase 1 (C4) ships first because it's smallest and protects later phases. Phases 2 (C1) and 3 (C3) are independent and can run in either order.

## Phase 0 — Pre-implementation gates (blocking)

- [ ] **0.1** Re-confirm Skill hook input shape: invoke any `/soleur:foo` skill in a session with a temporary `set -x` line at the top of a sandbox hook. Confirm `jq -r '.tool_name'` → `"Skill"` and `jq -r '.tool_input.skill'` → `"<plugin>:<name>"`. If different, halt and update Phase 3 hook script accordingly.
- [ ] **0.2** Verify `actionlint` available locally (`command -v actionlint` || install via `go install github.com/rhysd/actionlint/cmd/actionlint@latest`).
- [ ] **0.3** Read `.github/workflows/scheduled-ux-audit.yml` end-to-end as the canonical pattern for Phase 2.
- [ ] **0.4** Read `.claude/hooks/lib/incidents.sh` end-to-end as the canonical pattern for Phase 3 hook + `flock` idiom.
- [ ] **0.5** Read `scripts/lint-rule-ids.py` end-to-end as the canonical pattern for Phase 1 lint.

## Phase 1 — C4: AGENTS.md enforcement-tag lint

- [ ] **1.1** Write `scripts/lint-agents-enforcement-tags.py`:
  - Argparse: `[AGENTS_MD ...]` positional (default: `AGENTS.md`)
  - Regex `r"\[hook-enforced: ([^\]]+)\]"` and `r"\[skill-enforced: ([a-z][a-z0-9-]*)( [^\]]*)?\]"` over each input file
  - For each `[hook-enforced]` match: split on whitespace, take first token; check existence in `.claude/hooks/`, `scripts/`, OR `plugins/soleur/hooks/`. If first token is `lefthook`, look at the second token and assert it appears in `lefthook.yml` `pre-commit:commands:*:run` lines.
  - For each `[skill-enforced]` match: assert `plugins/soleur/skills/<skill>/SKILL.md` exists.
  - Honor `scripts/retired-rule-ids.txt` — IDs listed there may be absent from AGENTS.md (defensive parity with `lint-rule-ids.py`).
  - Exit 1 with one-line-per-failure error messages. Print `✓ all <N> tags resolve` on success.
- [ ] **1.2** Run `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md` against current AGENTS.md → must exit 0 (13 tags pass — this run is the lint's self-test).
- [ ] **1.3** Sanity-check: insert `[hook-enforced: ghost.sh]` into a working copy, run lint → must exit 1. Revert.
- [ ] **1.4** Add to `lefthook.yml` `pre-commit:commands:agents-enforcement-tag-lint` block, glob `AGENTS.md`, priority `5`, run `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md`.
- [ ] **1.5** `lefthook run pre-commit` from a clean working tree → succeeds.
- [ ] **1.6** Commit Phase 1 alone (one logical unit): `feat(harness): lint AGENTS.md enforcement tags`.

## Phase 2 — C1: missing audit cron workflows

- [ ] **2.1** Create `.github/workflows/scheduled-agent-native-audit.yml`:
  - cron `0 9 15 * *`
  - `name: "Scheduled: Agent-Native Audit"`
  - Preflight via `./.github/actions/anthropic-preflight`
  - claude-code-action pinned to `@ab8b1e6471c519c585ba17e8ecaccc9d83043541` (v1.0.101)
  - timeout-minutes 45, max-turns 50 (ratio 0.9)
  - `permissions: issues: write, contents: read, pull-requests: write, id-token: write`
  - Inline `gh label create scheduled-agent-native-audit --color "0E8A16" 2>/dev/null || true`
  - Prompt embeds explicit MILESTONE / CAP_OPEN_ISSUES=20 / CAP_PER_RUN=5 / Injection-safety rules verbatim from `scheduled-ux-audit.yml`
  - notify-ops-email on failure
- [ ] **2.2** Create `.github/workflows/scheduled-legal-audit.yml`:
  - cron `0 11 1 1,4,7,10 *` (quarterly Jan/Apr/Jul/Oct 1, 11:00 UTC — avoids `0 9 1 * *` collision)
  - timeout-minutes 60, max-turns 60 (ratio 1.0)
  - Same shape as 2.1 with `legal-audit`-specific allowlist
- [ ] **2.3** Verify cron next-fire dates with `python3 -c "from croniter import croniter; from datetime import datetime; ..."` (install `pip install croniter` if needed). Document next 3 fires per workflow in PR body.
- [ ] **2.4** `actionlint .github/workflows/scheduled-agent-native-audit.yml .github/workflows/scheduled-legal-audit.yml` → exits 0.
- [ ] **2.5** Commit Phase 2: `feat(audits): schedule agent-native and legal audits via cron`.

## Phase 3 — C3: skill freshness telemetry

- [ ] **3.1** Write `.claude/hooks/skill-invocation-logger.sh` (~50 lines, mirrors `incidents.sh` writer idiom):
  - Shebang + `set -uo pipefail`
  - Kill-switch: `[[ "${SOLEUR_DISABLE_SKILL_LOGGER:-}" == "1" ]] && exit 0`
  - Repo-root resolution via `cd -P "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P`
  - Read stdin via `INPUT=$(cat)`
  - Extract skill name: `SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || echo "")`
  - Skip if SKILL empty
  - Build line: `jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$SKILL" '{schema:1, ts:$ts, skill:$s, hook_event:"PreToolUse"}' 2>/dev/null` (fail-soft)
  - Append via `( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file" 2>/dev/null || true`
  - Always `exit 0`
- [ ] **3.2** Empirical re-verification: enable hook with `set -x` at top, run `/soleur:help`, confirm `tool_input.skill` extracts correctly. Document the literal payload in script header comment.
- [ ] **3.3** Write `.claude/hooks/skill-invocation-logger.test.sh`:
  - Test 1: kill-switch honored — `SOLEUR_DISABLE_SKILL_LOGGER=1 echo '{...}' | <hook>` produces no output file.
  - Test 2: skill-name extraction — feed `{"tool_name":"Skill","tool_input":{"skill":"soleur:plan"}}`, assert JSONL contains `"skill":"soleur:plan"`.
  - Test 3: bad input JSON — feed `not-json`, hook exits 0, no JSONL line written, no stderr explosion.
  - Test 4: 100 concurrent fires (background loop), all lines parse via `jq -e '.skill' < file`.
- [ ] **3.4** Edit `.claude/settings.json`: add new `PreToolUse` matcher block:
  ```json
  {
    "matcher": "Skill",
    "hooks": [
      {
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/skill-invocation-logger.sh"
      }
    ]
  }
  ```
  Verify with `jq . .claude/settings.json` exits 0. Note: `security_reminder_hook` may flag the Edit on first attempt — retry.
- [ ] **3.5** Edit `.gitignore`: add `.claude/.skill-invocations.jsonl` and `.claude/.skill-invocations-*.jsonl.gz`.
- [ ] **3.6** Verify `git ls-files .claude/.skill-invocations` returns nothing.
- [ ] **3.7** Write `scripts/skill-freshness-aggregate.sh`:
  - Walk `plugins/soleur/skills/*/SKILL.md`. Extract `<skill-name>` from path.
  - If `.claude/.skill-invocations.jsonl` exists: parse line-by-line via `jq -c 'select(.skill != null)' 2>/dev/null`; group by skill name.
  - Compute per-skill: `last_invoked` (max ts), `invocation_count`, `days_since_last`, `status`.
    - `status = "fresh"` if `days_since_last < 180`
    - `status = "idle"` if `180 ≤ days_since_last < 365`
    - `status = "archival_candidate"` if `days_since_last ≥ 365`
    - `status = "never_invoked"` if no invocations
  - Write `knowledge-base/engineering/operations/skill-freshness.json` with shape `{schema:1, generated_at, skills:[...], summary:{total_skills, idle_180d, idle_365d, never_invoked}}`.
- [ ] **3.8** Write `scripts/skill-freshness-aggregate.test.sh`:
  - Test 1: empty JSONL → output has all skills with `status:"never_invoked"`, summary counts correct.
  - Test 2: malformed line in JSONL → skipped without erroring.
  - Test 3: threshold boundaries — synthesize records at 179 days (`fresh`), 180 days (`idle`), 364 days (`idle`), 365 days (`archival_candidate`).
- [ ] **3.9** Create initial `knowledge-base/engineering/operations/skill-freshness.json` by running aggregator locally against an empty JSONL. Commit as the baseline; the aggregator workflow updates it monthly.
- [ ] **3.10** Create `.github/workflows/scheduled-skill-freshness.yml`:
  - cron `0 0 1 * *` (monthly, 1st 00:00 UTC)
  - `permissions: checks: write, contents: write, pull-requests: write` (NOT `statuses: write`)
  - Inline `gh label create scheduled-skill-freshness ...; gh label create do-not-autoclose ...`
  - Run `bash scripts/skill-freshness-aggregate.sh`
  - Open PR via `./.github/actions/bot-pr-with-synthetic-checks` with `add-paths: knowledge-base/engineering/operations/skill-freshness.json`. NOTE: the action does NOT take `milestone` input — milestone applies to issue filing only.
  - Stale-issue filer step:
    - For each skill with `status` in `(idle, archival_candidate)`:
      - Idempotency: `gh issue list --label scheduled-skill-freshness --search "<name> in:title" --state all --limit 5` → skip if any hit.
      - Inject-safe: write title/body to env vars BEFORE `gh issue create`.
      - File with labels `scheduled-skill-freshness,do-not-autoclose`, milestone `"Post-MVP / Later"`.
      - Stop after `CAP_PER_RUN=3` issues filed.
    - `never_invoked` does NOT trigger filing.
  - notify-ops-email on failure
- [ ] **3.11** `actionlint .github/workflows/scheduled-skill-freshness.yml` → exits 0.
- [ ] **3.12** Run aggregator locally after a few real `/soleur:foo` invocations to confirm output shape.
- [ ] **3.13** Commit Phase 3: `feat(harness): skill-invocation telemetry + freshness aggregator`.

## Phase 4 — Plan-mandated follow-up issue files (after merge)

- [ ] **4.1** File issue: "Per-competitor split for scheduled-competitive-analysis.yml"
- [ ] **4.2** File issue: "ux-audit cadence: monthly → weekly per brainstorm prescription"
- [ ] **4.3** File issue: "seo-aeo-audit cadence: weekly → biweekly per brainstorm prescription"
- [ ] **4.4** File issue: "Telemetry persistence gap (rule-incidents + skill-invocations) — close once for both streams"
- [ ] **4.5** File issue: "Add test-pretooluse-skill-hook.yml deterministic CI guard"
- [ ] **4.6** File issue: "Move audit-skill issue-filing semantics from workflow prompt into agent-native-audit + legal-audit SKILL.md (mirror ux-audit pattern)"

## Phase 5 — Pre-merge acceptance verification

Run all `Acceptance Criteria > Pre-merge (PR)` checks from the plan. Stage everything, push, mark draft PR ready.

## Phase 6 — Post-merge verification

Run all `Acceptance Criteria > Post-merge (operator)` checks from the plan after the squash-merge lands on main.
