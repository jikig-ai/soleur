---
title: Claude Code stack tuning — deterministic permissions + deferred candidates
date: 2026-05-15
issue: 3789
branch: feat-cc-stack-tuning
draft_pr: 3787
deferred_children: [3790, 3791, 3792, 3793]
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
source: "https://medium.com/data-science-collective/i-spent-6-months-tuning-claude-code-heres-the-exact-setup-that-finally-worked-b41c67628478"
---

# Brainstorm — Claude Code stack tuning

## User-Brand Impact

**Artifact:** the Soleur Claude Code hook layer (`.claude/settings.json` + `.claude/hooks/*.sh`) which governs prod-write surfaces — `git push origin main`, `terraform apply`, `doppler secrets set --config prd`, `gh pr merge --admin`, supabase prod project writes, `gh release create`, `wrangler deploy`, Stripe live writes.

**Vectors (operator-endorsed):**
- **Operator lock-out / ship paralysis** — an over-broad `defer` regex blocks legitimate `git push origin feat-foo` or merges, paralyzes ship velocity, hook gets disabled wholesale.
- **Silent under-enforcement** — a `defer` regex misses a real prod-write path (e.g., `wrangler secret put` against prod env), agent destructive op slips through.
- **Approval audit gap** — operator approves a deferred prod-write without reading the diff, downstream incident has unclear attribution between gate and human.

**Threshold:** `single-user incident`. Any single-user prod-data corruption or credential leak via missed-defer or unaudited approval is brand-survival-critical.

## What We're Building

A **deterministic-permissions umbrella feature** (F1+F2) that converts existing instruction-tier prod-write gates into kernel-enforced telemetry + deferred-approval hooks. Plus four deferred items captured as tracking issues blocked on prerequisites.

**F1 — PermissionDenied telemetry hook (ships first in same PR, enforce-flipped immediately):**
- Extends `.claude/hooks/lib/incidents.sh` `emit_incident` with a new `kind: "permission_denied"` discriminator written to the existing `.claude/.rule-incidents.jsonl` sink.
- Adds a `PermissionDenied` event hook in `.claude/settings.json` that captures kernel-level denials (today's `emit_incident` only catches denials chosen by Soleur's own guard scripts; the kernel may deny things Soleur's hooks never see).
- Adds `.claude/logs/denied.jsonl` to `.gitignore` and `.gitleaks.toml` allowlist exclusion (the file MUST NOT be allowlisted in gitleaks scanner — payloads may contain secrets even after redaction).
- Payload redaction at write time: strip `sk_`, `Bearer `, `eyJ`, `postgres://.*:.*@`, Doppler/AWS key prefixes before fsync.
- 30-day TTL via daily logrotate or `find -mtime +30 -delete` cron.

**F2 — Deferred-permission hook for prod-write paths (ships in same PR, dry-run default):**
- New PreToolUse(Bash) hook `.claude/hooks/prod-write-defer-gate.sh` that returns `permissionDecision: defer` (April 2026 CC feature) for a versioned target manifest of prod-write Bash invocations.
- Target manifest committed at `.claude/hooks/lib/prod-write-targets.json` — versioned, rule-IDed, not hardcoded regex. Initial entries from operator + COO assessment (see Key Decisions table).
- **Dry-run default** via `SOLEUR_DEFER_DRYRUN=1` env var (set in repo `.env.defaults`). Hook short-circuits to log-only via F1's writer, emits `kind: "would_defer"` for two weeks. Operator manually inspects the log, refines manifest against false-positive matches, then flips dry-run off in a follow-up tiny PR.
- Bypass mechanism: `CLAUDE_HOOK_BYPASS=1` env honored by the hook + writes a `kind: "bypass"` incident with operator identity + reason — no silent overrides.
- Approval audit log: separate `.claude/logs/approvals.jsonl` (gitignored, redacted, 1-year TTL) captures `{tool, args_hash, operator_email, timestamp, approval_method}` for every approved defer event. Approval prompt MUST show full resolved command + diff/plan preview + 3-second mandatory read delay on `terraform apply`, `doppler set --config prd`, `gh release create`. (CLO: prompt design is a legal control surface, not just UX.)

## Why This Approach

The synthesis converges across five domain leaders + repo-research + learnings-researcher:

1. **F1 must ship before F2's enforce-mode** to produce empirical data on which prod-write paths actually fire. The bundled PR with dry-run default achieves this in one merge while still gating enforcement on observed behavior.
2. **Soleur's existing hook infrastructure already uses `deny`/`ask`/`allow`** (`.claude/hooks/guardrails.sh`, `ship-unpushed-commits-gate.sh`). `defer` is a genuinely novel layer — but the `emit_incident` telemetry sink, `lib/incidents.sh` library, and `permissionDecision` JSON pattern are all reusable.
3. **Existing workflow-gate rules (`wg-ship-push-before-merge`, `hr-menu-option-ack-not-prod-write-auth`, `hr-dev-prd-distinct-supabase-projects`) remain as belt-and-suspenders for at least one release after F2 lands** — hook coverage gaps (matcher misses, env bypass) are detectable only against the instruction-tier baseline.
4. **The 6-candidate list distilled from the Medium article was over-stated against Soleur's actual state.** Repo-research found that AGENTS sidecars don't exist on disk yet, `apps/web-platform/server/tool-tiers.ts` isn't on main, plugin AGENTS.md mandates `model: inherit` (zero overrides among 67 agents), and `soleur:schedule` uses `claude-code-action@v1` (not direct `claude -p`). Four of six candidates needed deferral or doc-only acknowledgement.
5. **CPO strategic lens:** Phase 4 (Validate + Scale) is active. F1+F2 advance T2 (Secure-Before-Beta) directly — Stripe live-mode activation + container isolation + Doppler prd writes open the blast-radius window NOW. Deferring F3/F5/F6/F7 keeps focus on the 5-of-10 founders-using-2-domains validation work, not contributor-experience polish.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | Ship F1+F2 as a single bundled PR with F2 in `SOLEUR_DEFER_DRYRUN=1` mode; tiny follow-up PR flips to enforce after 2 weeks of telemetry | Operator preference; matches the article's empirical-tuning philosophy | User answer 2026-05-15 |
| 2 | F1 sink: extend `.claude/.rule-incidents.jsonl` with `kind: "permission_denied"`; do NOT create a parallel `.claude/logs/denied.jsonl` for the rule-event surface | CTO: avoid log fan-out; reuse `emit_incident` flock+rotation primitives | User answer 2026-05-15; CTO assessment |
| 3 | Separate `.claude/logs/approvals.jsonl` (gitignored, 1-year TTL) for F2's operator-approved defer events | CLO: approval attribution is a legal control surface distinct from rule-incidents | CLO assessment |
| 4 | F2 target list is a versioned manifest (`.claude/hooks/lib/prod-write-targets.json`), rule-IDed; NOT hardcoded regex | CTO: rule-ID stability; matches `session-rules-loader.sh` precedent | CTO assessment |
| 5 | F2 target list (initial, from operator + COO): `git push origin main`, `terraform apply`, `doppler secrets set --config prd`, `doppler configs tokens create/revoke --config prd`, `gh pr merge --admin`, `gh release create`, `gh release upload`, `git push --force origin main`, `git push --delete origin <protected>`, `wrangler deploy`, `wrangler pages deploy`, `wrangler secret put` (prod), `supabase db push --linked`, `supabase migration up --linked`, `supabase secrets set` (prod), `gh api -X PUT /repos/.../branches/main/protection`, Stripe CLI with `--live` or `STRIPE_API_KEY=sk_live_*`, `git tag -a v*` on main (release trigger) | Operator endorsed; COO expanded from initial 6 entries to 11 categories | Initial list + COO assessment |
| 6 | Approval prompt MUST show full resolved command + diff/plan preview + 3-second mandatory read delay on the highest-risk subset (`terraform apply`, `doppler set --config prd`, `gh release create`) | CLO: prompt design as legal control surface; liability attribution shifts to operator only when prompt is informative | CLO assessment |
| 7 | Bypass via `CLAUDE_HOOK_BYPASS=1` writes a `kind: "bypass"` incident with operator identity; no silent overrides | COO: every bypass produces a record reviewable in weekly ops sweep | COO assessment |
| 8 | Existing `wg-ship-push-before-merge` + `hr-menu-option-ack-not-prod-write-auth` + `hr-dev-prd-distinct-supabase-projects` REMAIN as instruction-tier rules through at least one release after F2 enforces | CTO: belt-and-suspenders against hook matcher misses | CTO assessment |
| 9 | Hook test fixtures synthesized only — never wire tests against real prod paths | `cq-test-fixtures-synthesized-only`; CTO emphasized | CTO assessment |
| 10 | F4 (MCP token discipline) is dropped to a doc-only note. Tool Search Lazy Loading is already active; `maxResultSizeChars` is for in-process MCPs we don't yet own on main | Repo-research §5; CPO assessment | User answer 2026-05-15 |
| 11 | Approval channel architecture for F3 (when un-deferred): Discord ops bot + GH Actions Environments + Cloudflare Worker HMAC resume endpoint | COO assessment; uses only ledger-existing infra | COO assessment (carry-forward) |

## Non-Goals (deferred to tracking issues)

- **F3** — CI defer-then-resume — tracking #3790
- **F5** — Agent model-downshift — tracking #3791
- **F6** — Path-scoped AGENTS sidecars — tracking #3792
- **F7** — Per-skill MCP activation — tracking #3793
- **F4 expanded scope** — rejected as premature

### Detail

- **F3 — CI defer-then-resume in `soleur:schedule`.** Deferred post-Phase 4. Re-evaluation criteria: `soleur:schedule` has 2+ active nightly tasks where defer-on-prod-write is the bottleneck AND F2 has shipped in enforce mode AND COO's approval-channel architecture (Discord bot + GH Env + CFW HMAC) is approved.
- **F5 — Agent model-downshift audit.** Deferred entirely. `plugins/soleur/AGENTS.md` Model Selection Policy mandates `model: inherit` (zero overrides among 67 agents); revising the policy is a separate decision. Re-evaluation criteria: BYOK cost telemetry shows clear waste OR a per-agent quality regression justifies the revision conversation.
- **F6 — Path-scoped rule files (AGENTS.eleventy.md, AGENTS.ruby.md, etc.).** Deferred blocked on `feat-agents-md-change-class-loader` shipping its base sidecars (currently in-flight; AGENTS.{core,docs,rest}.md DO NOT YET EXIST ON DISK). Re-evaluation criteria: sidecars land + 2 weeks of measured token impact + clear ROI on path-glob extension vs. current change-class classifier.
- **F7 — Per-skill MCP activation.** Deferred. Claude Code has no primitive for per-skill MCP activation today; `enabledMcpjsonServers` in `settings.json` is session-wide. Re-evaluation criteria: CC plugin manifest spec adds per-skill MCP scope OR the in-process `soleur_platform` MCP server lands on main and per-tool gating belongs there.
- **F4 expanded scope** (real MCP token-cost audit). Rejected as premature; instrumented baseline measurement would consume engineer-days that pull weight against Phase 4 validation work.

## Open Questions

1. **Defer feature availability.** `permissionDecision: defer` is an April 2026 CC feature. Empirical verification needed: does it work in non-TTY contexts (cron, headless CI)? F2's dry-run mode produces the test data — if defer doesn't fire in some context, the dry-run telemetry will show it before enforce-flip.
2. **Stripe live-mode regex.** Detection by `STRIPE_API_KEY=sk_live_*` env var requires reading process env, which the hook may not see. Fallback: detect `stripe` CLI calls with `--live` flag explicitly. Confirm at plan time.
3. **`anthropics/claude-code-action@v1` interaction with defer.** F2 may fire in scheduled GH Actions contexts via `soleur:schedule`. F3's deferral covers the action wiring; but if `defer` returned from a hook causes the action to hang silently (no human present), we need a deterministic timeout. F1's telemetry will surface this.
4. **Operator identity binding.** F2's `approvals.jsonl` needs to record WHO approved. Possible sources: `git config user.email`, GitHub Actions `${{ github.actor }}`, or a `SOLEUR_OPERATOR_EMAIL` env. Plan-time decision.
5. **Hook ordering against `pre-merge-rebase.sh` and `ship-unpushed-commits-gate.sh`.** Existing PreToolUse(Bash) order matters (per learning `2026-03-28-pretooluse-hook-guard-ordering-matters.md`). F2's gate runs LAST in the chain so any auto-push from `pre-merge-rebase.sh` has already happened. Plan-time test fixture must cover this.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO), Finance (CFO), Operations (COO). Marketing, Sales, Support not relevant — internal dev infra.

### Engineering (CTO)

**Summary:** F1 ship-now (lowest blast-radius, observability only); F2 refine before ship (dry-run scaffold mandatory, versioned target manifest, treat existing `wg-ship-push-before-merge` as belt-and-suspenders for at least one release); F3 defer until F1's denied-call telemetry surfaces real ground-truth from production sessions; F4 split (lazy-loading SHIP, per-skill activation DEFER — no CC primitive); F5 greenfield but enforcement belongs in `skill-security-scan.sh`, not new agent; F6 extend `session-rules-loader.sh` classifier, not parallel layer.

### Product (CPO)

**Summary:** Ship F1, F2 inline with Phase 4 (T2 Secure-Before-Beta + T4 Validate). F4 (model downshift) is the cost-model lever for Phase 4 finance validation but contradicts current plugin policy; deferred per operator. F3 and F5b/F6 are real but second-order — defer to Post-MVP. Pivot-risk check: codifying CLI-plugin hooks deeper does NOT hinder cloud-platform pivot because CaaS architecture reuses the same `plugins/soleur/` directories server-side.

### Legal (CLO)

**Summary:** F1 ship after redaction + gitignore + 30-day TTL. F2 ship after diff-preview prompt + named-operator approval log + mandatory 3-second read delay on highest-risk subset. F6 ship-now. F3 needs scheduled-run approval policy that treats `defer` as `abort` (NOT auto-approve) when no human is present. F4/F5 ship-now (no compliance surface). User-impact-reviewer activation required at PR review for F1, F2, F3 (`Brand-survival threshold: single-user incident`).

### Finance (CFO)

**Summary:** F1/F2/F3 cost-neutral. F4 (model downshift) is the biggest absolute prize (~$200–1500/dev/mo BYOK savings via 5x–15x cost reduction on Sonnet/Haiku review agents) but operator chose to keep `model: inherit` policy; capture as deferred re-evaluation criterion. F5a (MCP lazy-loading + maxResultSize) is mid-ROI but mostly already active in Soleur. ROI sequencing: F4 > F5a > F3 > F6 > F1/F2 (safety, not cost).

### Operations (COO)

**Summary:** F2 missing 5 prod-write categories from initial list — expanded to 11 (wrangler deploy/secrets, Doppler token rotation, supabase admin CLI with --linked, branch protection PUTs, force-push to protected refs, tag-on-main release triggers, Stripe live writes). F3 unusable without approval-channel architecture; recommended design: Discord ops bot + GH Actions Environments + Cloudflare Worker HMAC resume endpoint (uses only ledger-existing infra, zero new spend). Healthy defer baseline: 3–10/week; >25/week signals over-broad regex; <1/week signals dead hook.

## Capability Gaps

(Evidence-cited per skill rule.)

- **No CI-side prompt-auditor / frontmatter-linter exists for agent `model:` enforcement.** Evidence: `grep -rE '^model:' plugins/*/agents/` returns 67 hits all `inherit` (repo-research §4); no linter in `.claude/hooks/skill-security-scan.sh` walks agent frontmatter for model declarations (repo-research §1). Engineering domain. Needed only if F5 is un-deferred.
- **No `defer` decision precedent in any Soleur hook.** Evidence: repo-research §1 enumerated all 6 PreToolUse hooks, all use `deny`/`ask`/`allow`. Engineering domain. F2 introduces this.
- **No CC primitive for per-skill MCP activation.** Evidence: `grep -rE '^mcpServers:' plugins/soleur/skills/*/SKILL.md` returns zero hits; `enabledMcpjsonServers` in `settings.json` is session-wide (repo-research §8). Product/Engineering. F7 deferred until primitive exists.
