---
title: Fix stale constitution path in no-memory-write hook
type: fix
date: 2026-06-07
lane: single-domain
brand_survival_threshold: none
---

# 🐛 Fix stale constitution path in no-memory-write hook

`.claude/hooks/no-memory-write.sh` line 55 builds the BLOCKED `permissionDecisionReason`
message that fires when an agent attempts to write to `~/.claude/projects/*/memory/`.
That message tells the agent to commit knowledge to one of three committed repo files.
The middle bullet currently reads:

```
  - knowledge-base/overview/constitution.md (architecture + style)
```

The constitution does **not** live at `overview/`. It was relocated to
`knowledge-base/project/constitution.md` (migration recorded in
`knowledge-base/project/plans/2026-03-13-refactor-rename-kb-overview-to-project-plan.md`
and `knowledge-base/project/specs/feat-rename-kb-overview/`). The `overview/` directory
no longer exists in the repo. Every other **live, operative** reference already uses the
correct `project/` path (`knowledge-base/INDEX.md`, `plugins/soleur/commands/sync.md`,
`scripts/rule-audit.sh`, `knowledge-base/project/components/knowledge-base.md`, and the
compound / compound-capture / plan / work skills). This hook is the **only** live file
still pointing at the phantom `overview/` location — so an agent that hits the block is
handed a path that 404s.

The entire functional change is one line.

## Research Reconciliation — Premise vs. Codebase

| Premise (from task) | Verified reality | Plan response |
|---|---|---|
| `no-memory-write.sh:55` says `overview/constitution.md` | Confirmed — `grep -n "overview/constitution" .claude/hooks/no-memory-write.sh` returns line 55 only | Edit line 55 |
| Constitution lives at `project/constitution.md` | Confirmed — `knowledge-base/project/constitution.md` exists (73 KB); `knowledge-base/overview/constitution.md` does **not** exist | Change bullet to `project/` |
| A sibling test may pin the `overview/constitution.md` substring | **No such assertion exists.** `no-memory-write.test.sh` has zero references to `constitution` or `overview`. Its T1 message assertion (line 40) checks only `*"knowledge-base/project/learnings"*` | **No test edit required.** Suite stays green after the fix. (Optional hardening noted under Non-Goals.) |
| `SANCTIONED_DIRS` in `kb-domain-allowlist-guard.sh` must be left alone | Confirmed it does **not** contain `overview` (`engineering finance legal marketing operations product project sales support`) | Out of scope — not touched |
| Remaining `overview/constitution` refs are historical/out-of-scope | Confirmed — all remaining matches are under `knowledge-base/project/{plans,specs,brainstorms,learnings}/` (dated records, incl. the rename plan/spec) or under `apps/web-platform` (user-workspace KB) | Out of scope — not touched |

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent that is correctly blocked from
  writing to CC memory is then told to commit its knowledge to
  `knowledge-base/overview/constitution.md` — a path that does not exist — so the
  redirection fails and institutional knowledge is silently dropped instead of captured.
- **If this leaks, the user's data / workflow / money is exposed via:** N/A. This is a
  static help-string correction inside a deny-path message. It touches no data, no auth,
  no network, no PII surface. The hook's matching regex, deny decision, and incident emit
  are all unchanged.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: a one-line correction to a hook's BLOCKED
help-message string changes no runtime decision, touches no sensitive path, and moves no
user data — it only fixes a dangling doc pointer shown to the agent.*

## Observability

This is a docs-string correction to a hook's BLOCKED message; it changes no runtime
behavior (regex, deny logic, `emit_incident` call are untouched). Its correctness is fully
captured by the existing local bash test suite — no production telemetry surface is added
or modified.

```yaml
liveness_signal:
  what:            "no-memory-write.test.sh bash test suite (T1–T12)"
  cadence:         "per-run (local, pre-commit / CI)"
  alert_target:    "non-zero exit (developer terminal / CI job)"
  configured_in:   ".claude/hooks/no-memory-write.test.sh"

error_reporting:
  destination:     "test runner exit code (no Sentry surface — no runtime change)"
  fail_loud:       "Results line prints 'N passed, M failed' and exits 1 on any failure"

failure_modes:
  - mode:          "BLOCKED message regresses to a non-existent path again"
    detection:     "optional new test assertion (see AC4) fails in no-memory-write.test.sh"
    alert_route:   "developer terminal / CI on the next hook edit"

logs:
  where:           "stdout of bash .claude/hooks/no-memory-write.test.sh"
  retention:       "ephemeral (CI job log / local terminal)"

discoverability_test:
  command:         "bash .claude/hooks/no-memory-write.test.sh"
  expected_output: "Results: <N> passed, 0 failed (exit 0)"
```

## Acceptance Criteria

- [ ] AC1 — `.claude/hooks/no-memory-write.sh` line 55 reads
      `knowledge-base/project/constitution.md (architecture + style)` (was `overview/`).
      Verify: `grep -c "knowledge-base/project/constitution.md (architecture + style)" .claude/hooks/no-memory-write.sh` returns `1`.
- [ ] AC2 — No live reference to `overview/constitution.md` remains in `.claude/hooks/`.
      Verify: `grep -rl "overview/constitution" .claude/hooks/` returns nothing (empty).
- [ ] AC3 — The existing suite is green with no test edits.
      Verify: `bash .claude/hooks/no-memory-write.test.sh` prints `0 failed` and exits 0.
- [ ] AC4 (optional hardening — see Non-Goals) — IF the planner/implementer elects to add a
      regression assertion, T1 in `no-memory-write.test.sh` additionally asserts
      `[[ "$reason" == *"knowledge-base/project/constitution.md"* ]]`. This is the cheapest
      guard against the exact bug recurring. Default: **skip** (keeps the diff to one line);
      include only if explicitly desired.
- [ ] AC5 — Out-of-scope surfaces untouched: `git diff --name-only` lists **only**
      `.claude/hooks/no-memory-write.sh` (and, if AC4 is taken, `.claude/hooks/no-memory-write.test.sh`)
      plus this plan + tasks. No change to `kb-domain-allowlist-guard.sh`, no change to any
      dated file under `knowledge-base/project/{plans,specs,brainstorms,learnings}/`, no change
      to any `apps/web-platform` `overview/` reference, no change to CC-local `MEMORY.md`.

## Test Scenarios

- Given an agent attempts a Write to `~/.claude/projects/<slug>/memory/foo.md`, when the
  hook fires, then the BLOCKED message lists `knowledge-base/project/constitution.md` as the
  architecture+style destination (a path that exists). Covered by T1 (deny decision +
  message substrings) — `bash .claude/hooks/no-memory-write.test.sh`.
- Given the hook source after the edit, when grepped, then it contains zero `overview/constitution`
  substrings: `grep -c overview/constitution .claude/hooks/no-memory-write.sh` returns `0`.
- Given the cited destination path in the corrected message, then the file exists on disk:
  `test -f knowledge-base/project/constitution.md && echo OK` prints `OK`.

## Files to Edit

- `.claude/hooks/no-memory-write.sh` — line 55: change the middle remediation bullet from
  `knowledge-base/overview/constitution.md (architecture + style)` to
  `knowledge-base/project/constitution.md (architecture + style)`. **Single-character-class
  change** (`overview` → `project`); everything else on the line and in the surrounding
  `jq -n` payload is preserved verbatim.
- `.claude/hooks/no-memory-write.test.sh` — **only if AC4 is taken** (optional). Add one
  `&& [[ "$reason" == *"knowledge-base/project/constitution.md"* ]]` clause to the T1
  conditional. Do not change any other test.

## Files to Create

- None. (Plan + tasks artifacts under `knowledge-base/project/` are created by the plan
  workflow, not by the implementation.)

## Out-of-Scope (do NOT modify)

- `SANCTIONED_DIRS` in `.claude/hooks/kb-domain-allowlist-guard.sh` — verified it does not
  list `overview`; we are **not** sanctioning an `overview/` domain.
- Any historical / dated record under `knowledge-base/project/{plans,specs,brainstorms,learnings}/`
  — these (e.g. the `2026-03-13-refactor-rename-kb-overview-to-project-plan.md` plan and the
  `feat-rename-kb-overview/` spec) document the *past* `overview/` state and must keep citing
  the old path.
- Any `apps/web-platform` reference to `overview/...` (vision.md, screenshots, kb-chat
  fixtures) — that is the generated **user-workspace** knowledge-base, a different `overview/`
  dir, and is correct as-is.
- The CC-local `MEMORY.md` (hard rule `hr-never-write-to-claude-code-memory`; it is
  machine-local and must not be edited).

## Non-Goals

- **No broad `overview/` → `project/` sweep.** The task is explicitly the single live hook
  file. The other matches are historical or a different (user-workspace) `overview/`.
- **No mandatory test change.** The strict instruction was "update the test *if* an assertion
  pins the `overview/constitution.md` substring." Investigation confirms **no such assertion
  exists** — so the default plan adds none and the suite stays green. AC4 records the optional
  regression-hardening assertion for the implementer's discretion; it is a Non-Goal to require it.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a one-line correction to a developer-tooling
hook's help-string. No UI surface (no path under `components/**`, `app/**`), no product,
legal, security, finance, marketing, operations, or sales implication. The mechanical
UI-surface override does not fire (Files to Edit contains no UI-surface path). Product/UX
Gate skipped (Product NONE). GDPR/Compliance gate (Phase 2.7) skipped — no regulated-data
surface (no schema, migration, auth flow, API route, or `.sql`; no LLM/external-API
processing of operator data; threshold is `none`; no new cron/distribution surface).
Infrastructure-as-Code gate (Phase 2.8) skipped — no new server, service, cron, secret,
vendor, or persistent runtime process; pure string edit to an existing hook.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is
  filled with a concrete artifact, an explicit N/A exposure rationale, and the `none` threshold
  plus the required scope-out-override reason (sensitive-path-safe).
- The edit is `overview` → `project`, **not** a whole-path rewrite. Preserve the trailing
  ` (architecture + style)` annotation and the exact two-space `  - ` list indentation inside
  the `\n`-joined `jq` string; a stray indentation change would not break behavior but would
  dirty the diff beyond the one intended token.
- Do **not** "helpfully" also fix the historical `overview/constitution` matches surfaced by a
  repo-wide grep — they are point-in-time records (the rename plan/spec literally describes
  moving constitution out of `overview/`) and rewriting them is an explicit Non-Goal.

## References

- Source file: `.claude/hooks/no-memory-write.sh:55`
- Test: `.claude/hooks/no-memory-write.test.sh` (T1 message assertion at line 40 pins
  `knowledge-base/project/learnings`, not the constitution bullet)
- Correct destination: `knowledge-base/project/constitution.md`
- Migration provenance (out of scope, cite-only):
  `knowledge-base/project/plans/2026-03-13-refactor-rename-kb-overview-to-project-plan.md`,
  `knowledge-base/project/specs/feat-rename-kb-overview/`
- Already-correct operative references (no change): `knowledge-base/INDEX.md`,
  `plugins/soleur/commands/sync.md`, `scripts/rule-audit.sh`,
  `knowledge-base/project/components/knowledge-base.md`
