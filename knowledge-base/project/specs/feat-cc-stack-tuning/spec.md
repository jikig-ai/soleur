---
title: Deterministic permissions — PermissionDenied telemetry + deferred-permission hook for prod-writes
date: 2026-05-15
branch: feat-cc-stack-tuning
draft_pr: 3787
brainstorm: knowledge-base/project/brainstorms/2026-05-15-cc-stack-tuning-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: draft
---

# Spec — Deterministic permissions (F1+F2 umbrella)

## Problem Statement

Soleur's existing PreToolUse hooks (`.claude/hooks/guardrails.sh`, `ship-unpushed-commits-gate.sh`, `pre-merge-rebase.sh`, etc.) use `permissionDecision: deny` for absolute blocks (commit-on-main, rm -rf worktree). High-stakes prod-write paths (`git push origin main`, `terraform apply`, `doppler secrets set --config prd`, `gh pr merge --admin`, supabase prod writes, `gh release create`, `wrangler deploy`, Stripe live writes) are currently governed by **instruction-tier rules** in `AGENTS.md` (`hr-menu-option-ack-not-prod-write-auth`, `hr-dev-prd-distinct-supabase-projects`, `wg-ship-push-before-merge`) that rely on the agent obeying. There is no kernel-level audit trail of denied tool calls beyond what individual Soleur guard scripts emit via `emit_incident`.

## Goals

1. Add a `PermissionDenied` event hook that captures **kernel-level** denials (not just denials Soleur's own guards choose to emit).
2. Introduce a `permissionDecision: defer` pattern (April 2026 CC feature) for high-stakes-but-legitimate prod-write paths that need out-of-band human approval, replacing instruction-tier rules with a kernel-enforced gate.
3. Ship both in a single PR with the defer gate in **dry-run mode by default** (`SOLEUR_DEFER_DRYRUN=1`) so 2 weeks of telemetry refines the target manifest before enforcement is flipped on.
4. Preserve audit trail integrity: WHO approved, WHEN, with WHAT visible — sufficient for incident attribution.

## Non-Goals

- Replacing existing `deny`-tier hooks (`guardrails.sh`, `ship-unpushed-commits-gate.sh`). They stay.
- Removing the instruction-tier rules (`wg-ship-push-before-merge`, etc.). They remain as belt-and-suspenders for at least one release after F2 enforces.
- CI defer-then-resume in `soleur:schedule` (deferred — separate tracking issue).
- Agent model-downshift / `model:` frontmatter changes (deferred — separate tracking issue).
- Path-scoped AGENTS sidecars (deferred — blocked on `feat-agents-md-change-class-loader`).
- Per-skill MCP activation (deferred — no CC primitive).

## Functional Requirements

**F1 — PermissionDenied telemetry hook**

- **FR1.1** Add a `PermissionDenied` event hook entry to `.claude/settings.json` invoking `.claude/hooks/permission-denied-telemetry.sh`.
- **FR1.2** The hook MUST extend `.claude/hooks/lib/incidents.sh` `emit_incident` to support a `kind` field with values including `permission_denied`. Discriminator field appears in JSONL output. Existing `event_type` field semantics preserved.
- **FR1.3** The hook MUST redact payloads matching `sk_*`, `Bearer *`, `eyJ*`, `postgres://*:*@*`, AWS key prefixes (`AKIA*`, `ASIA*`), Doppler key prefixes (`dp.st.*`) before fsync.
- **FR1.4** Add `.claude/logs/denied.jsonl` to `.gitignore` AND ensure `.gitleaks.toml` does NOT allowlist it (allowlisting would let secret payloads slip past gitleaks scanner).
- **FR1.5** Daily rotation: entries older than 30 days are pruned via cron (`find -mtime +30 -delete`) or logrotate config.
- **FR1.6** Empirical hook-input-shape verification BEFORE writing the consumer, per `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`. Capture stub via `claude -p` child session and date-stamp the verified shape in the hook header.

**F2 — Deferred-permission hook for prod-writes (dry-run default)**

- **FR2.1** Add `.claude/hooks/prod-write-defer-gate.sh` PreToolUse(Bash) hook. Wired AFTER `pre-merge-rebase.sh` and `ship-unpushed-commits-gate.sh` per existing ordering convention (so auto-push side effects have already happened).
- **FR2.2** Target manifest at `.claude/hooks/lib/prod-write-targets.json` containing the 11 categories from brainstorm Decision #5. Each entry has: `rule_id`, `match_pattern` (regex), `severity`, `requires_diff_preview` (boolean), `mandatory_read_delay_sec` (integer, 0-10).
- **FR2.3** Default mode: `SOLEUR_DEFER_DRYRUN=1` (set in `.env.defaults`). In dry-run mode, hook emits `kind: "would_defer"` incident to `.claude/.rule-incidents.jsonl` via F1's writer; does NOT actually defer the tool call (returns `permissionDecision: allow`).
- **FR2.4** Enforce mode: `SOLEUR_DEFER_DRYRUN=0`. Hook returns `permissionDecision: defer` per April 2026 CC feature spec. Agent pauses; operator approves out-of-band; `claude --resume <session_id>` continues.
- **FR2.5** Bypass mechanism: `CLAUDE_HOOK_BYPASS=1` env honored; bypass writes `kind: "bypass"` incident with `bypass_operator` and `bypass_reason` fields (from env or stdin prompt). No silent overrides.
- **FR2.6** Approval log: separate `.claude/logs/approvals.jsonl` (gitignored, 1-year TTL) captures `{tool, args_hash, resolved_command, operator_email, timestamp, approval_method}` for every approved defer event. Operator email from `git config user.email` (interactive) or `${{ github.actor }}` (CI, when F3 un-deferred) or `SOLEUR_OPERATOR_EMAIL` env (override).
- **FR2.7** Approval prompt MUST show full resolved command + diff/plan preview for entries with `requires_diff_preview: true`. Entries with `mandatory_read_delay_sec > 0` MUST delay accept-input by that many seconds (initial: `terraform apply` = 3s, `doppler set --config prd` = 3s, `gh release create` = 3s; others = 0s).
- **FR2.8** Hook test fixtures synthesized only — never wire tests against real prod paths (`cq-test-fixtures-synthesized-only`).

**Follow-up PR (post-2-week telemetry)**

- **FR3.1** Tiny PR flips `SOLEUR_DEFER_DRYRUN=0` after operator reviews `.claude/.rule-incidents.jsonl` for 2 weeks of `kind: "would_defer"` entries, refines target manifest against false-positive matches (e.g., `git push origin feat-foo` accidentally matched), and confirms no critical false-negatives.

## Technical Requirements

- **TR1** Both hooks return JSON to stdout per CC hook contract. Empirical-shape verification per FR1.6 catches drift (e.g., `tool_name:"Agent"` vs `"Task"` per `2026-05-10-claude-code-posttooluse-task-hook-input-shape.md`).
- **TR2** Hook scripts use `set -euo pipefail`, `flock -x` interlock with sibling `emit_incident` callers (per existing `lib/incidents.sh` pattern), and `@sh`-escaped `jq` eval (per `guardrails.sh:32` pattern) to defend against argument injection.
- **TR3** Target manifest changes (`prod-write-targets.json`) require a corresponding rule-ID entry in `AGENTS.md` Hard Rules index so they're discoverable in the rule corpus and surface in `unused-rule` reports.
- **TR4** F1's `kind` discriminator schema versioned: add `schema: "incidents/v2"` field; v1 entries (lacking `kind`) treated as legacy `kind: "rule_event"`.
- **TR5** Tests live in new file `.claude/hooks/test-prod-write-defer-gate.bats` covering: (a) each manifest entry's regex matches intended path, (b) regex does NOT match adjacent non-prod paths (e.g., `git push origin main` matches; `git push origin feat-main-update` does NOT), (c) dry-run vs enforce mode behavior, (d) bypass mechanism + telemetry, (e) approval log redaction.
- **TR6** Add CI workflow `.github/workflows/test-defer-gate.yml` invoking the bats test suite on every PR touching `.claude/hooks/`.
- **TR7** `user-impact-reviewer` agent MUST activate at PR review per `Brand-survival threshold: single-user incident` inheritance.

## Out of Scope (Deferred Tracking Issues)

Each item will be filed as a separate GH issue blocked on its prerequisite:

- **F3 CI defer-then-resume** — blocked on F2 enforce-mode shipping + 2+ active nightly tasks in `soleur:schedule` + COO approval-channel architecture approval.
- **F5 Agent model-downshift** — blocked on `plugins/soleur/AGENTS.md` Model Selection Policy revision discussion.
- **F6 Path-scoped AGENTS sidecars** — blocked on `feat-agents-md-change-class-loader` shipping base sidecars to disk.
- **F7 Per-skill MCP activation** — blocked on CC plugin manifest spec adding per-skill MCP scope primitive.

## Acceptance

- F1 hook fires on every kernel-denied tool call observed during 24h of normal development (operator validates by attempting a known-blocked op like `git commit` on main, sees entry in `.claude/.rule-incidents.jsonl`).
- F2 hook in dry-run mode emits `kind: "would_defer"` for every targeted Bash invocation during 2-week observation window WITHOUT blocking any actual command.
- Telemetry review shows ≥5 distinct prod-write paths exercised by `kind: "would_defer"` entries; manifest refined if any false-positive matches occur.
- Follow-up enforce-flip PR ships with zero changes to `prod-write-targets.json` other than dry-run flag.
- All bats tests pass.
- `user-impact-reviewer` PR review approves.
