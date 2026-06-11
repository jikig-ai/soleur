---
title: "Pencil collapse-guard — deterministic auto-recovery of tracked .pen files truncated by open_document"
type: feature
issue: 4859
branch: feat-one-shot-pencil-collapse-recovery-4859
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-11
---

# feat: Pencil collapse-guard — deterministic auto-recovery of tracked .pen files truncated by `open_document`

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Close issue **#4859** (the deferred upstream non-goal from #3274: "`open_document` destructively wipes `.pen` on disk, returns success") with a **two-part deliverable**:

- **Part A (primary code deliverable):** a new **PostToolUse** hook `.claude/hooks/pencil-collapse-guard.sh` that fires AFTER `mcp__pencil__open_document` returns and **auto-recovers** a *tracked* `.pen` file that was silently collapsed to ~41-byte empty document state (`{"version":"...","children":[]}`). This is the deterministic backstop that the agent prose HARD-GATEs (PR #4855) and the PreToolUse `pencil-open-guard.sh` (PR #2754) are not.
- **Part B (satisfies #4859 re-evaluation criterion (a)):** file the root-cause bug upstream against the **public** Pencil bug channel `highagency/pencil-desktop-releases` (issues enabled, active MCP-bug track record), then record the filing outcome on #4859.

The PR body uses **`Closes #4859`**.

### Why the existing controls do not cover this

| Control | Stage | What it covers | The gap |
|---|---|---|---|
| `pencil-open-guard.sh` (PR #2754) | PreToolUse | DENIES `open_document` on **untracked** `.pen` (no recovery path) | Lets **tracked** `.pen` through — they still collapse on disk |
| ux-design-lead / brand-workshop prose HARD-GATEs (PR #4855) | agent prose | snapshot/collapse + commit-after-save discipline | Relies on agent discipline; not deterministic |
| **`pencil-collapse-guard.sh` (this plan)** | **PostToolUse** | tracked `.pen` collapsed to empty → `git show HEAD:<rel> > file` restore | — |

The collapse recurred **2026-06-02** on a committed file (zeroed twice; recovered by hand from `git HEAD`). PostToolUse hooks cannot block (the write already happened) but **can run a command** — so the hook restores from `HEAD` and emits a loud incident + a system message.

## Research Reconciliation — Spec vs. Codebase

| Claim (from scope / issue) | Reality (verified in repo) | Plan response |
|---|---|---|
| `open_document` param is `filePath` | Confirmed: `.claude/settings.json:185` matcher `mcp__pencil__open_document`; `pencil-open-guard.sh:23` keys on `.tool_input.filePath` | Key the new hook on `.tool_input.filePath` (same as sibling). |
| Mirror the `cq-before-calling-mcp-pencil-open-document` rule for the AGENTS.md pointer + `[hook-enforced]` tag | **That rule ID is RETIRED** — `scripts/retired-rule-ids.txt:37` (`2026-04-23 \| #2865`). Per `cq-rule-ids-are-immutable` it cannot be reintroduced. It currently has **no AGENTS index line and no sidecar entry**; its body lives in the `pencil-open-guard.sh` header + pencil-setup SKILL §"Untracked .pen safety" + README roster. | Do **NOT** add a new AGENTS.md sidecar rule. Per `cq-agents-md-tier-gate`, a Pencil-domain rule is **domain-scoped → edit the owning artifact, not AGENTS.md.** Mirror the *retired-rule pattern*: canonical body in the new hook header, a §"Tracked .pen collapse recovery" subsection in pencil-setup SKILL, and a README roster row. The `[hook-enforced: pencil-collapse-guard.sh]` tag lives in the hook header + SKILL pointer (where the sibling's tag lives), **not** in an AGENTS sidecar. See Sharp Edges. |
| PostToolUse hooks have a JSON output shape used by siblings | Only 2 PostToolUse hooks exist: `docs-cli-verification.sh` (advisory, `exit 0` + stderr warn, **no `hookSpecificOutput`**) and `agent-token-tee.sh`. PostToolUse `additionalContext` is the system-message surface. | Hook emits a `PostToolUse` `hookSpecificOutput.additionalContext` system message on restore, and is otherwise fail-open `exit 0`. See §Hook contract. |
| `incidents.sh` `emit_incident` exists | Confirmed `.claude/hooks/lib/incidents.sh:198`; signature `emit_incident <rule_id> <event> <prefix> [cmd] [hook_event] [kind]`; `hook_event` slot 5 = `"PostToolUse"`. | Call `emit_incident <new-rule-id> warn "<prefix>" "$REL_PATH" PostToolUse`. |
| Pencil MCP has no public contributor channel (issue says "not vendored") | `npm view @pencil.dev/cli` → repository/bugs/homepage all `null` (server is closed-source). **BUT** vendor "High Agency, Inc." has public `highagency/pencil-desktop-releases` with **issues enabled** + active MCP-bug history (#17–#21: "Bug: … MCP tool …"). | Part B is **automatable** via `gh issue create --repo highagency/pencil-desktop-releases`. Re-evaluation criterion (a) is **met**. |

## User-Brand Impact

**If this lands broken, the user experiences:** a tracked `.pen` design file the founder spent a session building is silently zeroed by `open_document` and stays zeroed (the hand-recovery on 2026-06-02 is the exact incident); OR — if the hook itself is buggy — the hook *overwrites a legitimately-edited working tree* with stale `HEAD` content, destroying in-progress design work.

**If this leaks, the user's workflow is exposed via:** N/A — no PII, no secrets, no network egress. The hook reads `git show HEAD:<rel>` and writes one tracked file in the local worktree.

**Brand-survival threshold:** `single-user incident` — a Soleur operator's design artifact is single-copy working-tree state; one destructive event is brand-damaging. The hook MUST be **fail-open and non-destructive on every error path** (a buggy guard that clobbers good work is strictly worse than the bug it fixes). `requires_cpo_signoff: true` — CPO sign-off required at plan time; `user-impact-reviewer` invoked at review-time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Hook exists & wired.** `.claude/hooks/pencil-collapse-guard.sh` exists, is executable, and `.claude/settings.json` `hooks.PostToolUse` contains a block with `matcher: "mcp__pencil__open_document"` invoking it via `"$CLAUDE_PROJECT_DIR"/.claude/hooks/pencil-collapse-guard.sh`. Verify: `jq -e '.hooks.PostToolUse[] | select(.matcher=="mcp__pencil__open_document")' .claude/settings.json`.
- [ ] **AC2 — Restore on collapse.** Given a tracked `.pen` whose committed blob is non-empty and whose current on-disk content is collapsed empty state, the hook restores the file byte-identical to `git show HEAD:<rel>` AND emits `hookSpecificOutput.additionalContext` naming the file + that `open_document` truncated it. Verified by `.test.sh` case.
- [ ] **AC3 — No-op when healthy.** Given a tracked `.pen` whose on-disk content is non-empty (has `children`), the hook makes **no write** and emits no restore message (`exit 0`, working tree unchanged). Verified by `.test.sh` (assert mtime/bytes unchanged).
- [ ] **AC4 — No-op when committed blob also empty.** If `git show HEAD:<rel>` is itself empty/collapsed (legitimate fresh scaffold), the hook does **not** write. Verified by `.test.sh`.
- [ ] **AC5 — No-op when untracked.** If `filePath` is not git-tracked (PreToolUse should have blocked, defense-in-depth), the hook `exit 0` with no write. Verified by `.test.sh`.
- [ ] **AC6 — Fail-open on every error.** Missing `filePath`, file outside any git repo, `git` failure, `jq` failure, or unreadable file → `exit 0`, **no destructive write**. Verified by `.test.sh` (empty payload, non-repo path, malformed JSON). The hook never `set -e`-aborts mid-write.
- [ ] **AC7 — Test suite green.** `bash .claude/hooks/pencil-collapse-guard.test.sh` exits 0 with `Fail: 0`, following the existing `.test.sh` convention (`INCIDENTS_REPO_ROOT` redirect, stdin payload via `mk_payload`-style helper, `Total/Pass/Fail` summary). It does NOT invoke the real Pencil MCP.
- [ ] **AC8 — Incident telemetry.** On restore the hook calls `emit_incident <new-rule-id> warn "<prefix>" "<relpath>" PostToolUse`; `.test.sh` asserts a line with the new `rule_id` and `event_type:"warn"` lands in the redirected `.rule-incidents.jsonl`. The new `rule_id` is **not** in `scripts/retired-rule-ids.txt` and is **not** the retired `cq-before-calling-mcp-pencil-open-document`.
- [ ] **AC9 — SKILL doc.** `plugins/soleur/skills/pencil-setup/SKILL.md` gains a §"Tracked .pen collapse recovery" subsection (under or adjacent to §"Untracked .pen safety") naming `pencil-collapse-guard.sh`, the restore behavior, and the `[hook-enforced: pencil-collapse-guard.sh]` tag. Skill `description:` frontmatter is **unchanged** (no budget check needed — verify via `grep '^description:'` diff is empty).
- [ ] **AC10 — README roster.** `.claude/hooks/README.md` "Telemetry-only hooks (PostToolUse …)" table gains a `pencil-collapse-guard.sh` row.
- [ ] **AC11 — No AGENTS sidecar churn.** `git diff --name-only origin/main..HEAD` does **not** include `AGENTS.md`, `AGENTS.core.md`, `AGENTS.docs.md`, or `AGENTS.rest.md` (tier-gate: Pencil-domain rule lives in the owning artifacts). If a reviewer insists on an index pointer, it is the *only* permitted AGENTS edit and must carry a fresh non-retired `[id]`.
- [ ] **AC12 — PR body.** PR body contains `Closes #4859` (not in title).

### Post-merge (operator) — none required for Part A

### Part B — upstream filing (in-session, automatable)

- [ ] **AC13 — Upstream issue filed.** A bug titled (draft) "Bug: `open_document` overwrites a non-empty tracked `.pen` with empty document state and returns success" is filed via `gh issue create --repo highagency/pencil-desktop-releases` with a body drafting the truncation report (repro: open a non-empty committed `.pen`; observe on-disk collapse to `{"version":"...","children":[]}` + success return; expected: `isError:true`, leave source untouched). The filed URL is captured.
  - **Automation:** feasible — `highagency/pencil-desktop-releases` has `hasIssuesEnabled:true` and an active MCP-bug history (#17–#21). Confirm with operator before firing the `gh issue create` (one AskUserQuestion), since it posts to an external public repo under the operator's `gh` identity.
- [ ] **AC14 — Fallback artifact.** If the operator declines external filing OR the repo rejects the create, write the drafted report to `knowledge-base/project/specs/feat-one-shot-pencil-collapse-recovery-4859/upstream-pencil-report.md` and present for approval. (Belt-and-suspenders: write the artifact regardless, so the drafted report is version-controlled even when filed externally.)
- [ ] **AC15 — Issue #4859 updated.** `gh issue comment 4859` records the Part-A landing + the Part-B filing outcome (upstream URL or artifact path), explicitly noting re-evaluation criterion (a) is satisfied.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
1. Re-read `.claude/hooks/pencil-open-guard.sh` (path resolution + `git ls-files --error-unmatch` tracked-check pattern) and `lib/incidents.sh` `emit_incident` signature.
2. Confirm the new rule-id is not in `scripts/retired-rule-ids.txt` (`grep -n '<new-id>' scripts/retired-rule-ids.txt` → empty). **Choose a NEW id** (e.g. `cq-pencil-collapse-auto-recover`); the original `cq-before-calling-mcp-pencil-open-document` is retired and immutable.
3. Confirm `jq` available; confirm PostToolUse `additionalContext` is the correct system-message field (vs PreToolUse `permissionDecisionReason`).

### Phase 1 — Hook script `.claude/hooks/pencil-collapse-guard.sh`
**Contract** (mirror `pencil-open-guard.sh` header style; canonical rule body lives here):
- `set -uo pipefail` (NOT `-e`: must never abort mid-flight and leave a half-write). Source `lib/incidents.sh`.
- Read stdin JSON; `FILE_PATH=$(jq -r '.tool_input.filePath // ""')`. Empty → `exit 0`.
- Resolve to absolute (same `[[ ! /* ]]` prefix trick as sibling); resolve `REPO_ROOT` via `git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel`; empty → `exit 0`. `REL_PATH` via `realpath --relative-to`; empty → `exit 0`.
- Tracked check: `git -C "$REPO_ROOT" ls-files --error-unmatch "$REL_PATH"` fails → untracked → `exit 0` (AC5).
- **Collapse detection (on-disk):** parse current file with `jq`. Treat as collapsed when the file parses as a document object whose `.children` is `[]`/absent (and/or byte size ≤ a small threshold consistent with `{"version":"...","children":[]}`). Detection MUST be conservative — *only* the unambiguous empty-document shape triggers a restore; any parse ambiguity → treat as healthy → `exit 0` (fail-open toward NOT overwriting).
- **Committed-blob check:** `git show "HEAD:$REL_PATH"` → if that is also empty/collapsed (or `git show` errors) → `exit 0` (AC4).
- **Restore:** only when (tracked) AND (on-disk collapsed) AND (HEAD blob non-empty): `git show "HEAD:$REL_PATH" > "$FILE_PATH"`. Then `emit_incident <new-id> warn "<~50-char rule prefix>" "$REL_PATH" PostToolUse` and emit the system message (Phase 2).
- Every branch ends `exit 0`; wrap risky calls so a failure falls through to no-op.

### Phase 2 — System-message output (additionalContext)
On restore, emit:
```
jq -n --arg f "$REL_PATH" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("AUTO-RESTORED: open_document silently truncated tracked .pen file " + $f + " to empty document state. Restored from git HEAD. Do NOT re-run open_document on this file without snapshotting; this is the #4859 collapse class.")}}'
```
Confirm the exact `additionalContext` key against the installed Claude Code PostToolUse schema in Phase 0; if the field differs, fall back to a loud stderr line (still `exit 0`) so the restore is never blocked on output-shape uncertainty.

### Phase 3 — Test `.claude/hooks/pencil-collapse-guard.test.sh` (TDD: write BEFORE Phase 1 per `cq-write-failing-tests-before`)
Follow `iac-plan-write-guard.test.sh` conventions: `SCRIPT_DIR`/`HOOK`, `PASS/FAIL/TOTAL`, `command -v jq || SKIP`, `INCIDENTS_REPO_ROOT` redirect to a tmp dir, payloads via stdin. Build a throwaway `git init` repo per case with a tracked `.pen`. Cases: AC2 (collapsed→restored, message emitted, incident logged), AC3 (healthy→untouched, assert bytes+mtime), AC4 (HEAD-also-empty→untouched), AC5 (untracked→untouched), AC6 (empty payload / non-repo path / malformed JSON → exit 0, no write).

### Phase 4 — Wire `.claude/settings.json`
Append a PostToolUse block: `{matcher:"mcp__pencil__open_document", hooks:[{type:"command", command:"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pencil-collapse-guard.sh"}]}`. Verify `jq -e` (AC1) and that the file remains valid JSON.

### Phase 5 — Docs (owning-artifact rule placement, NOT AGENTS sidecar)
- pencil-setup SKILL §"Tracked .pen collapse recovery" (AC9) with the `[hook-enforced: pencil-collapse-guard.sh]` tag + new rule-id.
- README roster row (AC10).
- Verify AC11 (no AGENTS.{md,core,docs,rest} in the diff).

### Phase 6 — Part B upstream filing
1. Draft the report (title + body) into `knowledge-base/project/specs/feat-one-shot-pencil-collapse-recovery-4859/upstream-pencil-report.md` (AC14, always written).
2. AskUserQuestion: file to `highagency/pencil-desktop-releases` now? On yes → `gh issue create --repo highagency/pencil-desktop-releases --title ... --body-file <artifact>`; capture URL.
3. `gh issue comment 4859` with Part-A + Part-B outcome (AC15).

## Test Scenarios
Covered by `pencil-collapse-guard.test.sh` (AC2–AC8). No prod/external calls; synthetic `git init` fixtures only (`cq-test-fixtures-synthesized-only`).

## Observability

```yaml
liveness_signal:
  what: rule-incident JSONL line (rule_id=<new-id>, event_type=warn) on each auto-restore
  cadence: per open_document collapse event (rare; event-driven)
  alert_target: scripts/rule-metrics-aggregate.sh weekly rollup (warn_count for the new rule_id)
  configured_in: .claude/hooks/lib/incidents.sh emit_incident + scripts/rule-metrics-aggregate.sh
error_reporting:
  destination: stderr (headless_or_stderr) + .rule-incidents.jsonl; hook is fail-open so failures are silent-by-design but the restore event is loud
  fail_loud: true (additionalContext system message + emit_incident on every restore)
failure_modes:
  - mode: hook fails to detect a real collapse (false negative)
    detection: absence of a warn incident after a known collapse; covered by .test.sh AC2
    alert_route: aggregator warn_count stays 0 despite a hand-observed collapse → re-open
  - mode: hook restores over legitimate edits (false positive)
    detection: .test.sh AC3/AC4 assert no-write on healthy/HEAD-empty; conservative collapse detector
    alert_route: would surface as an unexpected warn incident on a non-collapsed file
logs:
  where: <repo>/.claude/.rule-incidents.jsonl (flock-guarded, rotated by log-rotation.sh)
  retention: governed by existing log-rotation.sh
discoverability_test:
  command: "bash .claude/hooks/pencil-collapse-guard.test.sh"
  expected_output: "Total: N  Pass: N  Fail: 0"
```

## Domain Review

**Domains relevant:** Product (Pencil/design tooling — advisory; CPO sign-off carried by single-user-incident threshold)

This is a tooling/hooks change with no UI surface (no files under `components/**`, `app/**/page.tsx`, etc.). The Product relevance is the *design-artifact-safety* dimension, not a UI build. Product/UX Gate tier: **NONE** (no `.pen`/UI surface produced or modified by this plan). CPO sign-off is required at plan time via the `single-user incident` threshold (frontmatter `requires_cpo_signoff: true`), and `user-impact-reviewer` runs at review-time.

No legal/regulated-data, infra, or finance implications — no schemas, no PII, no network egress, no new persistent runtime process.

## Infrastructure (IaC)

None — pure code change (one shell hook + one settings.json entry + docs). No server, secret, vendor account, DNS, cron, or systemd unit introduced. Phase 2.8 skip.

## GDPR / Compliance

Skip — no regulated-data surface (no schema/auth/API/`.sql`), no LLM processing of operator data, no new distribution surface beyond a single public upstream bug report containing no personal data. The Part-B upstream report contains only the technical truncation repro.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Vendor the Pencil adapter and fix `open_document` in-repo | Rejected — server is closed-source (`@pencil.dev/cli` has no repo URL); satisfies #4859 criterion (b) but is out of scope and infeasible. |
| Reintroduce `cq-before-calling-mcp-pencil-open-document` as the AGENTS rule | Rejected — ID is retired & immutable (`cq-rule-ids-are-immutable`); also tier-gate forbids a Pencil-domain AGENTS sidecar rule. |
| PreToolUse block on tracked `.pen` too | Rejected — would block all legitimate opens of tracked design files; the bug is post-write truncation, which only a PostToolUse recovery can address. |
| Snapshot-to-tmp before open + diff after | Rejected as primary — `git HEAD` is already a durable snapshot for tracked files; tmp snapshot adds state with no benefit for the tracked case (and untracked is already PreToolUse-denied). |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (63 issues) returned zero matches for `pencil-collapse-guard.sh`, `.claude/settings.json`, `plugins/soleur/skills/pencil-setup/SKILL.md`, or `pencil-open-guard.sh`.

## Sharp Edges

- **The mirror target rule is RETIRED.** `cq-before-calling-mcp-pencil-open-document` is in `scripts/retired-rule-ids.txt` (line 37). Do NOT reintroduce it. The new hook needs a fresh, non-retired `[id]`, and per `cq-agents-md-tier-gate` the rule body lives in the hook header + pencil-setup SKILL + README roster — **NOT** an AGENTS.{core,docs,rest} sidecar. AC11 enforces no AGENTS diff.
- **PostToolUse cannot block.** The destructive write has already happened when this hook runs. Its only job is recovery + a loud message; it can never prevent the truncation (that is Part B's upstream fix).
- **Fail-open is load-bearing at `single-user incident` threshold.** Use `set -uo pipefail` (no `-e`); every error path is `exit 0` with NO write. A guard that clobbers good work with stale `HEAD` is strictly worse than the bug. Collapse detection must be conservative — restore ONLY on the unambiguous empty-document shape.
- **`additionalContext` field name.** Confirm the exact PostToolUse system-message key against the installed Claude Code schema in Phase 0; if uncertain, fall back to a stderr line (still `exit 0`).
- **CLA-signed author for any recovery-anchor stub.** Per `wg-cla-signed-author-before-merge`, if a `.pen` recovery stub is committed by a subagent, the author must be CLA-signed before merge (the `cla-check` modal source is exactly a Pencil recovery-anchor stub).
- A plan whose `## User-Brand Impact` section is empty/`TBD`/placeholder fails `deepen-plan` Phase 4.6 — this one is filled with a concrete threshold.

## References

- `.claude/hooks/pencil-open-guard.sh` — sibling PreToolUse hook (path resolution, tracked-check, incident emit).
- `.claude/hooks/lib/incidents.sh` — `emit_incident` signature (`hook_event` slot 5 = `PostToolUse`).
- `.claude/hooks/docs-cli-verification.sh` — sibling PostToolUse hook (fail-open `exit 0` + stderr pattern).
- `.claude/hooks/iac-plan-write-guard.test.sh` — `.test.sh` convention (stdin payloads, `INCIDENTS_REPO_ROOT`, Pass/Fail summary).
- `.claude/settings.json:185` — existing `mcp__pencil__open_document` PreToolUse matcher (wiring shape).
- `scripts/retired-rule-ids.txt:37` — retired `cq-before-calling-mcp-pencil-open-document`.
- `plugins/soleur/skills/pencil-setup/SKILL.md:164` — §"Untracked .pen safety".
- Part B channel: `https://github.com/highagency/pencil-desktop-releases` (issues enabled; MCP-bug history #17–#21).
