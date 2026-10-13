---
title: "feat: observability consolidation #4273 — close P0 compliance gap (Better Stack disclosure + VRL PII redaction + EU endpoint pin + vector validate CI gate)"
date: 2026-05-22
issue: 4273
pr: 4293
branch: feat-observability-consolidation-4273
worktree: .worktrees/feat-observability-consolidation-4273/
brainstorm: knowledge-base/project/brainstorms/2026-05-22-observability-consolidation-4273-brainstorm.md
spec: knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
classification: cross-domain-compliance
status: draft
---

# Plan: Observability consolidation #4273 — close P0 compliance gap

## Overview

PRs #4277/#4278/#4279 (all merged 2026-05-21) wired Vector on the Hetzner inngest VM to ship journald + host_metrics to Better Stack Logs via the generic HTTP sink. Three load-bearing gaps surfaced from the brainstorm + 6-agent plan review that **must remediate regardless of the strategic consolidation question** (the 60-day re-decision lives in #4296):

1. **Falsified disclosure** — `docs/legal/data-protection-disclosure.md:103` literally says "Better Stack … carries no personal data, user identifiers, or application content — Better Stack is therefore NOT a sub-processor of personal data under GDPR Article 28 and no SCC/DPA is required." This was true while Better Stack only received opaque heartbeats; after #4279 it is false (journald carries pseudonymous `userIdHash`, conversation IDs, error stack traces under PA8 §(c)(ii)). Article 30(1)(d) recipient cell, Vendor Mapping table, Privacy Policy §5.10, GDPR Policy operational-telemetry bullet — none currently disclose Better Stack as a Logs recipient. **GDPR-gate review surfaced an Art-9 risk class** (inngest function stderr may carry user-content fragments — chat messages, AI prompts) requiring a dedicated drop-transform.
2. **No PII redaction at the Vector boundary** — `apps/web-platform/infra/vector.toml`'s `tag_journald` transform (lines 48-55) forwards raw `message` + `host` fields with zero redaction. Pino's `formatters.log` rewrites top-level `userId`→`userIdHash` before stdout/journald lands, but nested fields, `system_journald` (kernel oops + OOM-killer with userland process args, including plain-text `userid=<uuid>` substrings), and any direct stderr from inngest functions reach Better Stack un-pseudonymised. **Spec-flow review surfaced the kernel-oops `userid=<uuid>` substring case** which the original VRL design missed entirely.
3. **Better Stack ingestion endpoint region unpinned** — `vector.toml:99` uses `https://in.logs.betterstack.com/` (undocumented legacy alias; Better Stack's own integration docs use a `$INGESTING_HOST` placeholder and confirm the source token is cluster-bound). The current source `2457081` (`soleur-inngest-vector-prd`, provisioned via Playwright per #4277) has unknown region — Phase 0 verifies and pins to the per-source EU ingesting host. **User-impact review surfaced URI-typosquat risk** — AC8 must use an explicit allowlist, not an `eu-*` wildcard.

The brainstorm's Phase 2 ("bump Vector for native `better_stack_logs` sink") is **dropped** — see Research Reconciliation §1. Phase 3 (60-day re-decision) is unchanged in spirit but its criteria simplify (no D-native vs D-fallback distinction); this PR amends issue #4296 in §FR10.

**FR8 (gdpr-gate regex extension) cut from this PR per simplicity review** — filed as a separate follow-up issue (see §FR10.7).

## Research Reconciliation — Spec vs. Codebase

| # | Spec / brainstorm claim | Codebase / external reality | Plan response |
|---|---|---|---|
| 1 | Spec FR4 + brainstorm Decision #1 prescribe bumping Vector to ≥0.44.0 for the native `better_stack_logs` sink | **Native `better_stack_logs` sink does not exist in any Vector release.** Vector PR vectordotdev/vector#19274 (proposed sink, opened 2023-11-30) was **closed unmerged 2025-01-27** (verified `gh api repos/vectordotdev/vector/pulls/19274` → `{state: "closed", mergedAt: null}`). The docs URL `https://vector.dev/docs/reference/configuration/sinks/better_stack_logs/` returns HTTP 404. Better Stack's own integration page (`https://betterstack.com/docs/logs/vector/`) prescribes `type = "http"` — generic HTTP IS the canonical vendor-recommended pattern | Drop spec FR4 (Vector substrate bump). Keep `vector validate` + `vector vrl` CI gate (FR5) for VRL safety on future `vector.toml` edits. Update brainstorm and spec via §FR10. Update #4296 60-day re-decision criteria to drop the D-native vs D-fallback distinction (§FR10) |
| 2 | Brainstorm Decision #5 + spec FR2 prescribe a VRL transform that hashes raw `userId`/`workspace_id` with HMAC-SHA256 using `${VECTOR_HMAC_KEY}` | (a) Pino's `formatters.log` (`apps/web-platform/server/logger.ts`) already rewrites top-level `userId`→`userIdHash` BEFORE journald per ADR-029 §I2 (TOP-LEVEL ONLY; `userId` and `user_id` keys ONLY — `workspaceId`/`workspace_id` are NOT in scope for the TS contract). (b) ADR-029 §I4 explicitly requires "single source of truth" for the pepper — a new `VECTOR_HMAC_KEY` would violate. (c) `SENTRY_USERID_PEPPER` is already injected into `vector.service` via the existing `doppler run --project soleur --config prd` ExecStart wrap (`apps/web-platform/infra/inngest-bootstrap.sh:380`). (d) Vector 0.43.1 VRL supports both `hmac(value, key, "SHA-256")` (since v0.29.0) and `get_env_var!()` (since v0.20) | **VRL key scope MUST match TS scope verbatim**: `userId` + `user_id` only (case-insensitive). Drop `workspaceId`/`workspace_id` from VRL (would create cross-vendor boundary divergence). Reuse `SENTRY_USERID_PEPPER` via `get_env_var!()`, compute `hmac(...) -> encode_base16(...)` to match `crypto.createHmac("sha256", pepper).update(userId).digest("hex")` bit-for-bit. Scope = **top-level keys only** (ADR-029 §I2 boundary contract; nested forms explicitly out-of-scope) |
| 3 | Brainstorm references issue #4211 (Inngest cron substrate migration) as IN-PROGRESS / OPEN | **#4211 CLOSED 2026-05-22T07:00:15Z** (verified `gh issue view 4211 --json state`). TR9 PR-3 finished and `scheduled-oauth-probe.yml` was deleted; Inngest function `cron-oauth-probe.ts` (`apps/web-platform/server/inngest/functions/cron-oauth-probe.ts:610-733`) now POSTs the Sentry cron monitor heartbeat | Update spec references from "in-flight" to "closed 2026-05-22". OAuth canary is verified-live; brand-survival framing premise is intact. No scope change |
| 4 | Brainstorm Decision #2 says "Better Stack is currently un-disclosed in Article 30" (implies zero mentions) | DPD §2.3(m) line 103 ALREADY mentions Better Stack — but ONLY as the inngest-server heartbeat recipient with the explicit claim "carries no personal data … NOT a sub-processor of personal data under GDPR Article 28". This is now falsified by the Vector → Better Stack Logs pipeline | The remediation is **disclosure correction** (clarify the existing mention by splitting Better Stack into two recipient roles: heartbeat unchanged, Logs newly added), not just addition. Sharper than the brainstorm framing — Phase 1 must amend a FALSE CLAIM, not fill a blank cell. Per GDPR-gate Crit-3, also amend GDPR Policy with explicit positive "Better Stack Logs IS enabled" to prevent symmetric falsification by future readers |
| 5 | Brainstorm Decision #5 ("PII redaction VRL must ship BEFORE any further Better Stack ingest tuning") implies the redaction is a primary control | Per CLO assessment, learnings file `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`, **and GDPR-gate Crit-5 Art-9 finding**: (a) disclosure language MUST be scope-narrow ("messages routed through the `pii_scrub_*` VRL transforms" — NOT "all Better Stack log lines"); (b) inngest function stderr may transit Art-9 user-content fragments (chat messages, AI prompts, health-related content) via `extra.body`/`extra.content`/`extra.message`/`extra.userMessage`/`extra.prompt`-shaped keys; (c) **string-level regex (`pii_scrub_string`) must additionally catch the `userid=<uuid>` plain-text substring** common in kernel oops + non-pino stderr — spec-flow review's Hole C | FR2 splits VRL into THREE transforms: (a) `pii_scrub_drop_userdata` (drop top-level `body`/`content`/`message`/`userMessage`/`prompt` keys in parsed pino payload — Art-9 mitigation; runs FIRST), (b) `pii_scrub_structured` (key-walker for `userId`/`user_id` rename to `userIdHash` via HMAC), (c) `pii_scrub_string` (string-level regex for raw `userid=`/`user_id=` substring + email + Authorization + line-injection chars — runs ONLY on the pre-parse / non-pino-shape branch per Arch-F2 ordering fix). Disclosure language in FR1 mirrors the three-transform split |
| 6 | Brainstorm OQ2 + spec FR3 ask "Better Stack EU endpoint URI verification" as a single open question | External docs research confirmed Better Stack has **no single regional URL alias**. The ingest host is per-source as `s{source_number}.{cluster}.betterstackdata.com` (e.g. `s95.eu-nbg-2.betterstackdata.com`). Region is chosen at source creation; the source token is cluster-bound. EU residency is on the standard paid Logs tier (no enterprise SKU) for Germany/EU regions. **User-impact review surfaced URI-typosquat risk** — `eu-*` wildcard accepts adversary `eu-foo-99.betterstackdata.com` | FR3 splits into 3a (read current source `2457081` cluster via Better Stack dashboard/API to determine region) + 3b (if not EU, provision new EU source via Playwright + Doppler swap with atomic ordering per UI-F2) + 3c (update `vector.toml:99` URI to per-source ingesting host with explicit allowlist `(eu-nbg-2\|eu-fsn-3)` — NOT regional alias). Phase 0 prerequisite |
| 7 | Spec mentions "Article 33 anchor-of-record" as TR2 with vague resolution | PA8 §(b)(ii) (read in full from `knowledge-base/legal/article-30-register.md:156`) explicitly anchors `first_observed_at` on the Sentry plane. Per learnings `2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md`, the Better Stack analog requires the same 3-axis topology audit | TR2 prescribes: (a) PA8 §(b)(ii) keeps Sentry as the canonical Art. 33 anchor under multi-provider state (D); (b) plan body explicitly defers an ADR for "multi-provider clock-anchor split" to the 60-day re-decision (#4296) IF that decision keeps multi-provider state — not now. Per Arch-F3, also consider creating an ADR for "Vector→Better Stack as second observability processor with shared-pepper VRL boundary" — added to §FR10 as optional sub-task |
| 8 | Spec FR3 mentions VRL `hmac` availability as an Open Question | Verified: VRL `hmac(value, key, "SHA-256")` available since Vector v0.29.0 (Vector 0.43.1 has it). `get_env_var!()` available since v0.20. No fallback needed | Close Open Question. FR2 uses `hmac()` + `encode_base16()` against `${SENTRY_USERID_PEPPER}` (NOT a new key — ADR-029 §I4) |
| 9 | Brainstorm OQ1 ("pause-vector vs bundle-redaction") suggests both paths are viable. Procedural-deadline-disclosure pattern (learning `2026-05-16-...`) implies PR-α/β/γ split under deadline | (a) Multi-leader convergence + CLO P0 ranking make BUNDLE strictly dominant. (b) Per Arch-F9, the split-pattern learning's load-bearing condition is "statutory or contractual deadline" — **no Art. 33 clock is running** today (no breach event; the falsified DPD clause is repo-internal until docs deploy). Therefore split pattern does NOT apply; bundle is correct | Plan adopts BUNDLE. The PR description explicitly cites the absence of statutory clock as the justification for not splitting (Art. 32 §(1) cost-vs-window is secondary justification) |

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (carried forward from brainstorm Phase 0.1, operator confirmation "All of them" across OAuth canary silent failure / log egress / PII region leak / billing surprise vectors).

**If this lands broken, the user experiences:** silent un-pseudonymised exposure of their `userId` in Better Stack Logs (e.g., the VRL transform parses, but its `pii_scrub_applied` tag is missing — a future operator queries logs assuming hashed-only, finds raw IDs, and either (a) DSAR-discloses the leak to the affected user, or (b) the data is inferable to anyone with Better Stack source-token access during the window). Brand-survival incident vector = the user discovers via DSAR response that we processed their identifier in plaintext under an undisclosed sub-processor. **Additional vector surfaced by user-impact review**: the OAuth canary's journald log trail loses callback-discriminator detail because `pii_scrub_string` over-redacts — operator debugging a real canary-fired incident loses critical context.

**If this leaks, the user's data is exposed via:** the falsified DPD §2.3(m) clause is a Privacy-Shield-style enforcement vector — CNIL or a single user can cite the contradicting statement as evidence of bad-faith disclosure (Art. 13(1)(e) breach). **Art-9 vector (GDPR-gate Crit-5)**: an inngest function exception with user-supplied chat-message body in the stack frame lands in journald → Vector → Better Stack. Phase 1 §FR2.0 `pii_scrub_drop_userdata` mitigates by dropping the body/content/message/userMessage/prompt keys at the parsed-pino boundary.

**Brainstorm carry-forward (operator answers):**
- (a) OAuth canary silent failure — mitigated (canary path is on Sentry, unaffected by Phase 1). Additionally, FR2 §2.2 `pii_scrub_string` is now scoped to the pre-parse branch only (Arch-F2 + UI-F1) so it cannot over-redact pino-shaped canary success-event logs.
- (b) Log egress / PII region leak — Phase 1 §FR1/§FR2/§FR3 directly closes this vector.
- (c) Billing surprise — orthogonal to Phase 1; CFO ledger projection (D-fallback ~$39-45/mo at 3 operators) is in tolerance.

**CPO sign-off requirement** (per `requires_cpo_signoff: true`): brainstorm Phase 0.5 spawned CPO; the recommendation ("D-native + 60-day window") was endorsed by the operator at brainstorm exit. CPO sign-off is satisfied via brainstorm carry-forward — no fresh CPO Task spawn at plan time. `user-impact-reviewer` will be invoked at PR review time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## Implementation Phases

### Phase 0: Preconditions + premise verification

**0.1** Verify cited PR / issue states (single-shot, 30s):
```bash
gh issue view 4273 4296 4297 4298 4300 3814 3815 3865 3866 4211 --json state,closedAt
gh pr view 4250 4271 4272 4277 4278 4279 --json state,mergedAt
```
Cross-check against this plan's body. Expected: #4211 CLOSED 2026-05-22; all PRs MERGED 2026-05-21; #4296-#4300 + #3814/#3815/#3865/#3866 OPEN. Any divergence → fix inline before proceeding.

**0.2** Verify Vector 0.43.1 VRL primitive availability (read-only, verified at plan time): `hmac()` since v0.29.0, `get_env_var!()` since v0.20, `parse_json()` since v0.13. No bump required.

**0.3** Verify `SENTRY_USERID_PEPPER` is reachable inside `vector.service`:
- `apps/web-platform/infra/inngest-bootstrap.sh:380` wraps `vector` ExecStart in `doppler run --project soleur --config prd`.
- Doppler `prd` config has `SENTRY_USERID_PEPPER` set. Verify via `doppler secrets get SENTRY_USERID_PEPPER -p soleur -c prd --plain | wc -c` (read-only check; do NOT echo value).
- No new Doppler secret needs to be added.

**0.4** Determine current Better Stack source `2457081` cluster region (operator step — Playwright-automatable per `hr-exhaust-all-automated-options-before`):
- Use Playwright MCP to log in to Better Stack dashboard (operator-driven OAuth).
- Navigate to `Sources → soleur-inngest-vector-prd` → Settings → Data region.
- Read the region name AND the per-source ingesting host (`s{N}.{cluster}.betterstackdata.com`).
- Record both values in Phase 3 PR comment for §FR3a verification.

**0.5** Audit cross-vendor pseudonymisation parity at planning time (Arch-F1): test fixture in §2.5 will import `hashUserId` from `apps/web-platform/server/observability.ts:36` to compute the expected value, NOT just `openssl dgst`. Confirm `hashUserId` exports cleanly via `node -e "const {hashUserId} = require('./apps/web-platform/server/observability'); console.log(hashUserId('test'))"` from a test context.

**0.6** Audit phases 0→7 sequencing per Arch-F7: Phase 5 (legal disclosure) cites the per-source cluster from Phase 3; Phase 5 MUST execute AFTER Phase 3 completes so placeholders are resolved (this plan's phase ordering 0→1→2→3→4→5→6→7 is correct). Phase 4 (CI gate) ships SAME-PR as Phase 2; the gate fires on the SAME diff that introduces the VRL transforms (self-referential — operator must confirm the lefthook pre-commit run order).

**0.7** Verify ADR-029 §I4 single-pepper-reuse claim covers VRL as a new consumer (SF-P0-6). Read `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` §I4; current list is pino + sentry-scrub. Add VRL to that consumer list — this is a Files-to-Edit item (FR2.5).

**0.8** Audit other workflows referencing `vector.toml` (SF-P1-7): `grep -l 'vector\.toml' .github/workflows/*.yml` — expected only `apply-web-platform-infra.yml` (will be amended). If anything else matches, surface in PR body.

### Phase 1: PR description + scope freeze

Write the PR description with:
- Three load-bearing P0 items (FR1, FR2, FR3) explicitly framed.
- Vector-bump premise-inversion (Research Reconciliation §1) prominently flagged so plan reviewers don't recheck.
- The "bundle-not-pause" decision: **no statutory clock applies** (per Arch-F9), Art. 32 §(1) cost-vs-window is secondary.
- The Art-9 mitigation (FR2 §2.0 `pii_scrub_drop_userdata`) explicitly named — this is the GDPR-gate-Crit-5 fold-in.
- Closes citation: **`Ref #4273`** (NOT `Closes` — partial closure of the umbrella).

### Phase 2: PII-redacting VRL transforms in `vector.toml` (FR2)

**Three-transform pipeline** (ordering load-bearing per Arch-F2):

```
sources [inngest_journald, system_journald]
   ↓
[transforms.pii_scrub_drop_userdata]   ← drops top-level body/content/prompt keys (Art-9 mitigation)
   ↓
[transforms.pii_scrub_structured]      ← parses pino-shape; HMAC-renames userId→userIdHash
   ↓
[transforms.pii_scrub_string]          ← runs ONLY on the unparsed/fall-through branch; catches raw userid= substring + email + Authorization + line-injection chars
   ↓
[transforms.tag_journald]              ← adds source_kind/shipper/host_name (unchanged)
   ↓
[sinks.betterstack]                    ← unchanged (generic HTTP)
```

**2.0** `[transforms.pii_scrub_drop_userdata]` (NEW — Art-9 mitigation per GDPR-Crit-5). Inputs: both journald sources. Steps:
- `parsed = parse_json(.message) ?? null`.
- If parsed AND it's an object, drop top-level keys: `body`, `content`, `message`, `userMessage`, `prompt`, `chat_message`, `userInput`, `user_input` (the canonical "user-content fragment" keys per pino + inngest convention).
- Re-serialize: `.message = if parsed != null { encode_json(parsed) } else { .message }`.
- Tag: `.pii_scrub_applied = "drop_userdata"` (or empty if parsed was null).

**2.1** `[transforms.pii_scrub_structured]`. Inputs: `pii_scrub_drop_userdata`. Steps:
- `parsed = parse_json(.message) ?? null`.
- If parsed AND parsed is object AND `parsed.userIdHash` is not present (defensive idempotence — pino already renamed):
  - For each top-level key in parsed (case-insensitive match on `userid` / `user_id` ONLY — **NOT `workspaceId`/`workspace_id`** per SF-P0-3 contract-match-TS):
    - If value is null: `.pii_scrub_applied = .pii_scrub_applied + "+structured_null_sentinel"`; set `parsed.userIdHash = "pepper_unset_null"`; del raw key.
    - Else: `pepper = get_env_var("SENTRY_USERID_PEPPER") ?? null`; if pepper null: `.pii_scrub_applied = .pii_scrub_applied + "+skipped_pepper_unset"`; KEEP raw line unchanged (ADR-029 §I3 fail-safe).
    - Else: `parsed.userIdHash = encode_base16(hmac(value, pepper, "SHA-256"))`; del raw key; `.pii_scrub_applied = .pii_scrub_applied + "+structured"`.
- Re-serialize.
- **Scope is top-level only** matches ADR-029 §I2 boundary; nested forms (`extra.userId`, `ctx.user.id`) are explicitly out-of-scope. Document in plan/spec.

**2.2** `[transforms.pii_scrub_string]`. Inputs: `pii_scrub_structured`. Steps:
- **Guard**: if `.pii_scrub_applied` already contains `"structured"` (parse succeeded), SKIP this transform's regex (`.pii_scrub_applied = .pii_scrub_applied + "+string_skipped_already_parsed"`). Prevents JSON-corruption per Arch-F2.
- Else (raw / unparseable / kernel-oops / non-pino branch):
  - Length-bound: `.message = slice!(.message, 0, 10000)` BEFORE regex (per `2026-04-17-pii-regex-scrubber-three-invariants.md` Invariant 1).
  - **`userid=`/`user_id=` plain-text substring strip** (per SF-P0-2 Hole C): `.message = replace(.message, r'(?i)\b(userid|user_id)=[\w-]+', "$1=[redacted]")`.
  - Email substring: `.message = replace(.message, r'\b[\w.+\-]+@[\w\-]+\.[\w.\-]+\b', "[email]")` (structural shape, not version per Invariant 2).
  - Authorization header value: `.message = replace(.message, r'(?i)(authorization:\s*)bearer\s+\S+', "$1Bearer [redacted]")`; same for `basic`.
  - Line-injection char strip: `.message = replace(.message, r'[\x00-\x1f\x7f  ]', "")`.
  - **Do NOT redact `/api/auth/callback/[\w\-/]+`** (per UI-F1) — this regex was in the original draft but strips OAuth canary discriminators; the structured branch's `pii_scrub_drop_userdata` already handles the body content where OAuth callbacks would carry tokens.
  - Tag: `.pii_scrub_applied = .pii_scrub_applied + "+string"`.

**2.3** `[transforms.tag_journald]` rewire: `inputs = ["pii_scrub_string"]` (was `["inngest_journald", "system_journald"]`); transform body unchanged otherwise. `[sinks.betterstack].inputs = ["tag_journald", "tag_metrics"]` unchanged.

**2.4** **`vector.toml:8-12` header comment correction** (per Arch-F10): the current comment references "Vector's native `better_stack_logs` sink consistently ingests" — rewrite to "Generic HTTP sink against Better Stack is the canonical vendor-recommended pattern (per `https://betterstack.com/docs/logs/vector/`); the native sink does not exist (Vector PR #19274 closed unmerged 2025-01-27)."

**2.5** **ADR-029 §I4 amendment** (per SF-P0-6): add VRL to the single-source-of-truth consumer list. Edit `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` §I4 to add a bullet: "Vector VRL (`apps/web-platform/infra/vector.toml` `pii_scrub_structured` transform; PR #4293) — top-level-only scope; defensive backstop for non-pino sources; HMAC-SHA256 via `get_env_var!('SENTRY_USERID_PEPPER')` + `encode_base16` to match TS `hashUserId` byte-for-byte."

**2.6** VRL fixture tests at `apps/web-platform/test/infra/vector-pii-scrub.test.sh` (single file with multiple fixtures per simplicity-Cut-7):
- Synthetic pepper: `SENTRY_USERID_PEPPER='fixture-only-do-not-use-in-prod'` (per GDPR-Imp). Document NEVER read from Doppler.
- Fixtures (heredoc): pino-with-userid, kernel-oops-with-userid-substring (UI: `userid=abc123`), kernel-oops-with-email, authorization-bearer-leak, line-injection-unicode, user-content-body-key (Art-9), null-userid-value, UTF-8-pepper-fixture (per GDPR-Imp).
- For each fixture, invoke `vector vrl --input <fixture> <transform-source>` and assert output shape + `pii_scrub_applied` tag.
- Bit-for-bit parity: import `hashUserId` from `apps/web-platform/server/observability.ts` via Node helper script and assert VRL output equals TS output for identical `(userId, pepper)` pair (per Arch-F1).
- Tests run in `validate-vector-config` CI job (FR5) as a BLOCKING sub-step (per Arch-F4).

### Phase 3: Better Stack EU endpoint pin (FR3)

**3.1** (depends on Phase 0.4) **If source `2457081` is EU:** update `vector.toml:99` `uri = "https://<per-source-ingesting-host-from-0.4>/"` (e.g., `https://s95.eu-nbg-2.betterstackdata.com/`). Add a verification comment block above the sink declaration with Better Stack dashboard URL + date + region.

**3.2** **If source `2457081` is US:** provision new EU source via Playwright MCP + **atomic ordering per UI-F2**:
- Step 1 (BEFORE PR merge): Playwright login + create new EU source (old still live). Extract token via `browser_evaluate(filename: ...)` per `hr-vendor-token-extraction-via-playwright-must-use-file-output` (token to `/tmp/bs-token-extracted`).
- Step 2 (PR commit): `vector.toml:99` updated to NEW EU URI. PR merged.
- Step 3 (CI runs): OCI rebuild + deploy → Vector restarts with NEW URI + OLD token → ships 401 to NEW endpoint → fails-loud in Better Stack source-stats dashboard.
- Step 4 (after deploy verified): Doppler-swap NEW token (file-stdin per IaC-2): `doppler secrets set BETTERSTACK_LOGS_TOKEN --plain-stdin -p soleur -c prd < /tmp/bs-token-extracted && shred -u /tmp/bs-token-extracted`. Vector picks up new token on next deploy (or via `systemctl restart vector.service` triggered by a follow-up).
- Step 5: Revoke OLD source via Playwright (token revocation cascades).
- Document atomic ordering as a §AC step list.

**3.3** Verification (no-SSH per IaC-1, removing the original `journalctl` reference):
- Primary: `curl -fsS https://uptime.betterstack.com/api/v2/sources/<source-id>/stats -H "Authorization: Bearer $BETTERSTACK_API_TOKEN" | jq '.events_per_second > 0'` (operator-local with Doppler-stored token; no production-host login).
- Secondary: Better Stack public-status URL OR Sentry cron-monitor dashboard (canary unaffected).
- `journalctl` on Hetzner VM is **local-debug-only** (Sharp Edges note).

### Phase 4: `vector validate` + `vector vrl` CI gate (FR5)

**4.1** New job `validate-vector-config` in `.github/workflows/apply-web-platform-infra.yml`:
- `needs: []` (parallel with `preflight`).
- **Path-filter the job** (per UI-F5): only run on PRs that touch `apps/web-platform/infra/vector.toml` OR `apps/web-platform/test/infra/**`. Use `dorny/paths-filter@v3` or equivalent. This prevents the new gate from cascading to block unrelated infra hotfixes (e.g., Hetzner firewall, Doppler service-token rotation).
- `runs-on: ubuntu-latest`, `timeout-minutes: 5`.
- Steps:
  1. `actions/checkout@v4` (pinned SHA).
  2. **Version/sha sync check** (per IaC-3): `grep -oE 'vector_version = "[^"]+"' apps/web-platform/infra/vector.tf` → extract; assert equals the version this job downloads (sourced from the same `vector.tf` locals via `awk`). If workflow YAML hardcodes a version, the assert catches drift; if the workflow always parses from `vector.tf`, no drift possible (preferred).
  3. Download Vector binary (no `actions/cache@v4` per simplicity-Cut-2 — ~10s download on every run is acceptable).
  4. Schema validation: `VECTOR_STRICT_ENV_VARS=false BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=dummy vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` — exit 0 required.
  5. **VRL fixture tests (BLOCKING — promoted from sub-bullet per Arch-F4):** `SENTRY_USERID_PEPPER='fixture-only-do-not-use-in-prod' bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` — exit 0 required. This is the load-bearing transform-body check; `vector validate` covers schema only.

**4.2 Conditional gate**: `apply` job `needs: [preflight, validate-vector-config]` — but `validate-vector-config` only runs (and only blocks) when `vector.toml` or the fixture tests are in the changed paths. Other infra PRs see `validate-vector-config` SKIPPED, which is treated as PASS by GitHub Actions.

**4.3** Break-glass (per UI-F5): document an operator override path via `compliance/critical` labeled PR + manual approval comment, NOT via `workflow_dispatch` input that could be silently exploited.

### Phase 5: Legal disclosure corpus update (FR1 — the P0)

**5.0** **PA8 §(b) Purposes amendment** (per GDPR-Crit-1): add §(b)(vi) explicitly: "Off-host long-tail operational log aggregation (Better Stack Logs, post-PR #4279) for diagnostic recall beyond the 30 MB Hetzner Docker json-file buffer in §(f); enables operator query of journald lines older than ~24h without SSH per `hr-no-ssh-fallback-in-runbooks`."

**5.1 PA8 amendments** (§(c)(ii), §(d), §(e), §(f), §(g)):

- **§(c)(ii)** — extend the "no off-host copies" sentence to name Vector + Better Stack + the VRL three-transform pipeline: "From PR #4279 onward, Vector reads journald (which mirrors pino stdout) and ships to Better Stack Logs as a separate processor under PA8 §(d). The VRL `pii_scrub_drop_userdata` + `pii_scrub_structured` + `pii_scrub_string` transforms in `apps/web-platform/infra/vector.toml` provide defense-in-depth Art-9 user-content drop + `userId`→`userIdHash` rename + string-level scrub before egress (boundary contract: ADR-029 §I4 single-pepper reuse — VRL imports `SENTRY_USERID_PEPPER` via `get_env_var!()`)."

- **§(d) Recipients** — append a 2026-05-22 UPDATE block AFTER the existing 2026-05-19 UPDATE block: "**[2026-05-22 UPDATE: Better Stack s.r.o. (processor — EU region, ingest cluster `<per-source-cluster-from-FR3>`, source ID `<2457081-or-new>`, name `soleur-inngest-vector-prd`) added as recipient of journald + host_metrics shipped by Vector 0.43.1 via the canonical generic HTTP sink (per `https://betterstack.com/docs/logs/vector/`; the native `better_stack_logs` sink does not exist — Vector PR #19274 closed unmerged 2025-01-27). This is a SEPARATE recipient role from the existing Better Stack heartbeat surface (which remains opaque ping payload, no personal data). Pseudonymous `userIdHash` boundary enforced by the three VRL transforms in `vector.toml`; the Doppler-held `SENTRY_USERID_PEPPER` is NOT shared with Better Stack — same Recital 26 pseudonymisation properties as the Sentry plane. **No Art. 33 / Art. 34 notification was warranted by this addition** — data flowed only post-2026-05-21 (#4279 merge) under processor-DPA terms; this Article 30 update is the Art. 30(1)(d) record-keeping discharge, not a breach notification.]**"
  
  **Future-removed-block pattern note** (per Arch-F6): "A future REMOVED block (if 60-day re-decision #4296 selects Path A consolidation and Better Stack Logs is withdrawn) follows the same `**[YYYY-MM-DD UPDATE: recipient withdrawn for reason X; effective date Y; data deletion timeline Z]**` bracket pattern — additive-only contract preserved."

- **§(e) Third-country transfers** — append after the Sentry DE bullet: "Better Stack s.r.o. (CZ — intra-EU; per Better Stack Vendor DPA at `<URL>`; data region `<eu-nbg-2 | eu-fsn-3>` per FR3 verification)."

- **§(f) Retention** — replace "No off-host copies are taken." with: "Better Stack Logs (off-host copy, post-PR #4279): paid-tier default retention `__TBD_BETTERSTACK_RETENTION__` days for journald + host_metrics (operator measurement at FR1 amendment time; mirrors the `__TBD_OBSERVED_VOLUME__` pattern). Logs lines containing `userIdHash` (HMAC-SHA256, Doppler-held pepper) are pseudonymous; on user-account deletion, the hash is allowed to age out per processor retention — no active processor-side erasure call is required (same Art. 17 treatment as the Sentry plane)."

- **§(g) TOMs** — append: "VRL `pii_scrub_drop_userdata` + `pii_scrub_structured` + `pii_scrub_string` transforms in `apps/web-platform/infra/vector.toml` (boundary control before Better Stack Logs egress); CI gate `validate-vector-config` in `.github/workflows/apply-web-platform-infra.yml` enforces `vector validate` (schema) + `vector vrl` fixture tests (transform-body — BLOCKING) on every `vector.toml` change."

- **Vendor / Sub-Processor Mapping table** — append after the Sentry row:
  ```
  | **Better Stack s.r.o.** (processor — Logs role; the heartbeat role is non-personal-data per PA8 DPD §2.3(m)(i)) | CZ → ingest cluster <eu-nbg-2|eu-fsn-3> | Better Stack DPA (standard EU-region terms; signed YYYY-MM-DD) | EU region, intra-EU | 8 | Vector-shipped journald + host_metrics; `userIdHash` pseudonymised at the VRL boundary. |
  ```

**5.2** `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table — append new Better Stack row.

**5.3** `docs/legal/privacy-policy.md` — **new §5.11 "Better Stack s.r.o. (Operational Log Aggregation)"** (per GDPR-Crit-2 — NOT append to §5.10 Sentry). Match the Sentry-entry shape (operator name, role, region, transfer mechanism, pseudonymisation paragraph). Renumber subsequent sub-sections only if any exist after §5.10.

**5.4** `docs/legal/data-protection-disclosure.md` §2.3(m) line 103 — **REPLACE THE FALSIFIED CLAIM** with the two-recipient-role split (heartbeat unchanged, Logs added). Specific text in Spec §FR1 §5.4.

**5.5** `docs/legal/gdpr-policy.md` operational-telemetry bullet (per GDPR-Crit-3): add **explicit positive disclosure** to prevent symmetric falsification — "**Better Stack Logs IS enabled for journald + host_metrics ingestion as of 2026-05-21 (PR #4279); VRL pseudonymisation at the Vector boundary applies — see DPD §2.3(m)(ii).**" The Sentry-Logs-NOT-enabled clause stays (still accurate; Sentry Logs product remains disabled).

**5.6** **DPD/PP dual-file sync** (per learning `2026-03-18-dpd-processor-table-dual-file-sync.md`): every edit in `docs/legal/*.md` MUST also land in `plugins/soleur/docs/pages/legal/*.md`. Acceptance criterion AC-DUAL-FILE.

**5.7** **Cross-reference grep audit** (per GDPR-Imp-DPD): `grep -nE '2\.3\(m\)' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` — confirm all cross-refs still resolve post-edit.

(Phase 5.7 "cross-grep runbooks" REMOVED per simplicity-Cut-6 — filed as follow-up issue in §FR10.7.)

### Phase 6: Brainstorm + spec + sibling-issue corrections (FR10)

(Phase 6 was gdpr-gate regex extension — REMOVED per simplicity-Cut-3, filed as follow-up issue in §FR10.7.)

**6.1** Append `## Plan-Time Corrections` section to `knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md`:
- C1 — Phase 2 "D-native Vector bump" dropped (Vector PR #19274 closed unmerged).
- C2 — Better Stack disclosure is correction-of-falsified-claim, not addition-to-blank-cell.
- C3 — VRL pepper is `SENTRY_USERID_PEPPER` (reused per ADR-029 §I4), NOT `${VECTOR_HMAC_KEY}`.
- C4 — Issue #4211 CLOSED 2026-05-22.
- C5 — FR2 expanded to THREE transforms (drop_userdata for Art-9, structured, string).
- C6 — FR8 gdpr-gate regex extension dropped from this PR (follow-up #4XXX).

(Brainstorm `## Plan-Time Corrections` REMOVED per simplicity-Cut-8 — the brainstorm is a write-once historical artifact; corrections live in the spec only.)

**6.2** Update issue #4296 (60-day re-decision) body via `gh issue edit 4296 --body-file -`:
- Re-evaluation criteria — re-list all surviving axes verbatim (per spec-flow P2 §5).
- Add corrective note: "Vector native `better_stack_logs` sink doesn't exist (PR #19274 closed unmerged); D-native and D-fallback are the same architecture today."

**6.3** Update issue #4298 (Vector staging VM) body — re-prioritize "DEFERRED indefinitely" (no substrate bump scenario).

**6.4** Update issue #4300 (Better Stack residency-check skill) body — re-prioritize "More urgent than originally framed".

(Updates for #4297 and #4273-comment REMOVED per simplicity-Cut-5 — ceremony.)

**6.5** File NEW follow-up issue: `feat: gdpr-gate canonical regex extension to include apps/web-platform/infra/vector.toml$ (carved out from PR #4293 per simplicity review)`. Body cites this plan's §FR8 design + lefthook mirror.

**6.6** (Arch-F3 advisory, optional) Create ADR `knowledge-base/engineering/architecture/decisions/ADR-NNN-multi-provider-observability-shared-pepper-vrl-boundary.md` if 60-day re-decision keeps D. NOT this PR; track in #4296.

## Files to Edit

| Path | Change | FR |
|---|---|---|
| `apps/web-platform/infra/vector.toml` | Header comment correction; add 3 transforms (`pii_scrub_drop_userdata` + `pii_scrub_structured` + `pii_scrub_string`); rewire `tag_journald.inputs`; update `[sinks.betterstack].uri` to per-source EU ingesting host | FR2, FR3 |
| `.github/workflows/apply-web-platform-infra.yml` | Add `validate-vector-config` job (path-filtered) upstream of `apply`; make `apply.needs` include it conditionally | FR5 |
| `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` | §I4 consumer list: add VRL bullet | FR2 §2.5 |
| `knowledge-base/legal/article-30-register.md` | PA8 §(b)(vi) NEW; §(c)(ii), §(d), §(e), §(f), §(g) amendments; Vendor Mapping new Better Stack row | FR1 |
| `knowledge-base/legal/compliance-posture.md` | Vendor DPA Status table — new Better Stack row | FR1 |
| `docs/legal/privacy-policy.md` | NEW §5.11 Better Stack | FR1 §5.3 |
| `docs/legal/data-protection-disclosure.md` | §2.3(m) line 103 FALSIFIED-CLAIM correction | FR1 §5.4 |
| `docs/legal/gdpr-policy.md` | Add explicit positive Better Stack Logs IS enabled bullet | FR1 §5.5 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Mirror | FR1 §5.6 |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Mirror | FR1 §5.6 |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | Mirror | FR1 §5.6 |
| `knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md` | Append `## Plan-Time Corrections` (C1-C6) | FR10 §6.1 |

## Files to Create

| Path | Purpose | FR |
|---|---|---|
| `apps/web-platform/test/infra/vector-pii-scrub.test.sh` | Single fixture file with multiple heredoc cases (per simplicity-Cut-7); VRL fixture tests for all 3 `pii_scrub_*` transforms; bit-for-bit parity assertion via Node `hashUserId` import | FR2 §2.6 |

## Acceptance Criteria

### Pre-merge (PR)

**AC1 (FR1 — Better Stack as Logs recipient disclosed)** — `grep -cE "Better Stack.*(processor|Logs|sub-processor)" knowledge-base/legal/article-30-register.md` returns ≥3 (anchored regex per SF-P0-5 + Sharp Edge; avoids false-positive from pre-existing heartbeat-only mention).

**AC2 (FR1 — DPD falsified-claim correction + dual-file parity)** — `grep -c "NOT a sub-processor of personal data" docs/legal/data-protection-disclosure.md` returns 0. `grep -c "Operational log aggregation" docs/legal/data-protection-disclosure.md` returns ≥1. `diff -u docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (post-frontmatter strip) shows zero diff. Same for `privacy-policy.md` and `gdpr-policy.md`. Cross-ref grep `grep -nE '2\.3\(m\)' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` returns the same line count pre- and post-edit.

**AC3 (FR1 — PA8 §(b)(vi) + GDPR Policy positive disclosure)** — `grep -c "Off-host long-tail" knowledge-base/legal/article-30-register.md` returns ≥1. `grep -c "Better Stack Logs IS enabled" docs/legal/gdpr-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md` returns 2.

**AC4 (FR2 — VRL fixture bit-for-bit parity with Sentry)** — `SENTRY_USERID_PEPPER='fixture-only-do-not-use-in-prod' bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` exits 0. For the pino-with-userid fixture, the output `userIdHash` MUST equal both `node -e "console.log(require('./apps/web-platform/server/observability').hashUserId('test-user-id'))"` (TS contract, per Arch-F1) AND `printf 'test-user-id' | openssl dgst -sha256 -hmac 'fixture-only-do-not-use-in-prod' -hex | awk '{print $2}'` (openssl backstop).

**AC5 (FR2 — three-transform contracts)** — fixture cases asserting: (a) `pii_scrub_drop_userdata` strips top-level `body`/`content`/`message`/`userMessage`/`prompt` keys from parsed pino payload (Art-9); (b) `pii_scrub_structured` rewrites `userId` ONLY (NOT `workspaceId` per SF-P0-3); preserves `userIdHash` if preset; fail-safe `skipped_pepper_unset` tag when env unset; (c) `pii_scrub_string` runs ONLY when `pii_scrub_applied` does NOT contain "structured" (Arch-F2 ordering guard); catches `userid=<uuid>` plain-text (SF-P0-2 Hole C); does NOT redact `/api/auth/callback/...` paths (UI-F1 fix); strips line-injection chars.

**AC6 (FR2 — UTF-8 pepper fixture)** — one fixture exercises a multi-byte UTF-8 pepper value (e.g., containing `é`) and asserts VRL output equals TS output (per GDPR-Imp).

**AC7 (FR3 — EU endpoint pinned with explicit allowlist)** — `grep -cE 'uri = "https://s[0-9]+\.(eu-nbg-2|eu-fsn-3)\.betterstackdata\.com/"' apps/web-platform/infra/vector.toml` returns 1 (per UI-F4 strict allowlist; rejects `eu-*` wildcard typosquats). Verification comment block above the sink declaration cites Better Stack dashboard URL + date + region.

**AC8 (FR3 — atomic token-swap ordering documented in PR body if FR3.2 fires)** — if Phase 0.4 found source `2457081` is US, PR body includes the 5-step atomic ordering checklist (per UI-F2) AND each step is explicitly acknowledged in a PR comment by the operator before merge.

**AC9 (FR5 — vector validate + vector vrl CI gate)** — `gh workflow view apply-web-platform-infra.yml` shows the `validate-vector-config` job with PATH FILTER on `apps/web-platform/infra/vector.toml` + `apps/web-platform/test/infra/**`. `gh run list --workflow apply-web-platform-infra.yml --branch <PR-branch> --limit 1` shows `validate-vector-config` ran and passed. A deliberately-broken `vector.toml` test commit (revert in same PR) makes the job FAIL on EITHER `vector validate` OR `vector vrl` fixture step.

**AC10 (IaC-3 version/sha drift sync)** — the `validate-vector-config` job parses `vector_version` from `vector.tf` locals at job start (NOT hardcoded in workflow YAML); proves drift is impossible.

**AC11 (FR2 §2.5 — ADR-029 §I4 consumer list)** — `grep -c "Vector VRL" knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` returns ≥1.

**AC12 (FR10 — spec correction block present)** — `grep -c "## Plan-Time Corrections" knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md` returns 1, with C1-C6 referenced.

**AC13 (FR10 — sibling issue updates)** — `gh issue view 4296` body contains "D-native and D-fallback are the same architecture today" AND re-lists all surviving 60-day re-decision criteria. `gh issue view 4298` body contains "DEFERRED indefinitely". `gh issue view 4300` body contains "More urgent than originally framed". One new follow-up issue exists (gdpr-gate regex extension — FR10.7).

**AC14 (PR body anchor + bundle-no-statutory-clock justification)** — PR body contains literal anchor strings: `Ref #4273` (NOT `Closes #4273`), `Brand-survival threshold: single-user incident`, `requires_cpo_signoff: true`. PR body summarizes Research Reconciliation §1 (false premise) prominently. PR body explicitly states "Split pattern (`2026-05-16-procedural-deadline...`) does not apply — no statutory clock; falsified DPD clause is repo-internal pre-deploy" per Arch-F9.

**AC15 (DPA signing)** — Better Stack DPA is signed and dated; date reflected in PA8 §(e) Better Stack bullet AND Vendor DPA Status table row. If unsigned at PR-ready time, AC15 escalates to `compliance/critical` follow-up label with explicit CLO ack noted in PR body (per GDPR-Crit-4).

### Post-merge (operator)

**AC16 (OCI deploy lag has explicit deadline)** — within 24h of PR merge, operator MUST push the `vinngest-vX.Y.Z` OCI tag (CI mints the version per `wg-never-bump-version-files-in-feature`; operator confirms via `git tag <tag> <merge-sha> && git push origin <tag>` OR via CI workflow_dispatch). Within 1h of tag push, the deploy webhook fires and Better Stack source shows ingest events with `pii_scrub_applied` tag populated. If 24h deadline missed → `compliance/critical` follow-up filed (per SF-P0-4).

**AC17 (Sentry cron-monitor unaffected)** — within 1h of deploy, OAuth canary cron `scheduled-oauth-probe` on `jikigai-eu` Sentry shows green status (Phase 1 did not regress the canary path). Verification via Sentry public dashboard URL — no SSH.

**AC18 (Issue close)** — Phase 1 closes specific FRs of #4273 via PR-body `Ref #4273`. **Issue #4273 itself stays OPEN** — the umbrella is the 60-day re-decision (#4296).

**AC19 (Better Stack volume baseline for billing variance check)** — 30 days post-merge, Better Stack monthly invoice variance vs pre-PR baseline ≤15% (D-fallback projection: $39-45/mo). Tracked in `compliance-posture.md` follow-up entry.

## Test Strategy

**Unit / VRL fixture tests** (FR2 §2.6 + Phase 4 step 5):
- Single consolidated test file `apps/web-platform/test/infra/vector-pii-scrub.test.sh` with heredoc fixtures.
- AC4–AC6 each map to specific fixture cases.
- BLOCKING in CI per Arch-F4 promotion.

**Schema validation** (Phase 4 step 4):
- `vector validate --no-environment --config-toml vector.toml` exit 0 required.

**Disclosure-vs-implementation parity** (FR1):
- AC1–AC3 grep-based.
- AC15 counsel-driven DPA signing.

**Out of scope for automated tests** (require deployed state — explicit `### Post-merge` AC):
- AC16 (OCI deploy lag deadline)
- AC17 (Sentry canary regression check)
- AC19 (30-day billing variance)

## Risks

**R1 — Better Stack DPA not signed at PR-ready time.** Mitigation: AC15 fallback to `compliance/critical` follow-up + CLO PR-body ack.

**R2 — VRL transform breaks on a journald line shape we didn't fixture-test.** Mitigation: fail-safe contract (FR2 — never drop the line, always pass through with `pii_scrub_applied = "skipped_*"`). Post-deploy: AC19 + a 7-day query of `pii_scrub_applied = "skipped_unparseable"` count tracks unfixtured shapes; > 100/day triggers follow-up issue.

**R3 — Better Stack EU source provisioning (FR3.2) requires Playwright automation; provider doesn't expose Logs source resource.** Mitigation: Playwright-driven per `hr-vendor-token-extraction-via-playwright-must-use-file-output`. If Playwright unavailable, AC7 can be satisfied by manual provisioning + post-merge follow-up issue for Better Stack residency-check skill (#4300).

**R6 — 24h window between PR merge and OCI deploy has the falsified DPD §2.3(m) clause corrected in repo but not yet user-visible.** Mitigation: PR body explicitly notes the lag; git-history-auditable. **Split-pattern (PR-α/β/γ from `2026-05-16-procedural-deadline-...`) does NOT apply — no statutory clock is running** (per Arch-F9). AC16 enforces a 24h OCI-tag-push deadline.

(R3-Vector-binary-cache, R4-cache-wall-clock, R5-gdpr-gate-over-fire, R7-runbook-grep-scope — all REMOVED per simplicity cuts.)

## Open Questions

**OQ1 (FR3a/3b fork)** — Phase 0.4 reads current source region; if US, Phase 3.2 atomic-ordering provisioning fires. Operator-driven Playwright session is the only path; can the operator complete BEFORE the PR is marked ready? Default: if US source, mark PR draft and complete §3.2 as a checkpoint with operator acknowledgement comment; if EU, fast-path.

## Domain Review

**Domains relevant (carry-forward from brainstorm Phase 0.5):** Engineering (CTO), Product (CPO), Legal (CLO), Finance (CFO), Operations (COO). All 5 brainstorm assessments captured in `knowledge-base/project/brainstorms/2026-05-22-observability-consolidation-4273-brainstorm.md` `## Domain Assessments`.

**Brainstorm-recommended specialists:** none beyond the 5 leaders.

### Engineering (CTO) — carry-forward + plan-review updates

**Status:** reviewed (brainstorm + plan-review)
**Assessment:** D-native dissolves into D-fallback (Vector PR #19274 closed unmerged). Three load-bearing FRs (FR1 legal corpus, FR2 three-transform VRL pipeline, FR5 CI gate). Plan-review (architecture-strategist) surfaced: F2 transform ordering (Arch-F2, folded), F4 `vector vrl` blocking promotion (folded), F1 cross-vendor parity assertion (folded), F6 REMOVED-block pattern (folded), F10 vector.toml header correction (folded), F3 ADR for multi-provider boundary (advisory, deferred to #4296 60-day decision).

### Product (CPO) — carry-forward + UI review updates

**Status:** reviewed; CPO sign-off load-bearing per `requires_cpo_signoff: true`
**Assessment:** Path preserves OAuth canary fidelity. User-impact-reviewer surfaced: F1 OAuth canary over-redaction (folded — string-scrub no longer touches callback paths), F2 atomic token-swap ordering (folded), F4 URI allowlist (folded), F5 path-filter the CI gate (folded). Bundle decision retained — no statutory clock applies.

### Legal (CLO) — carry-forward + GDPR-gate updates

**Status:** reviewed
**Assessment:** Article 30 + Vendor DPA + Privacy Policy + DPD + GDPR Policy update closes the falsified-disclosure gap. GDPR-gate (Phase 2.7) folded 5 Criticals: PA8 §(b)(vi) purpose addition, PP §5.11 NEW (not append), GDPR Policy explicit positive Better Stack Logs IS enabled, AC15 DPA-signing pre-merge OR documented operator-ack, Art-9 user-content drop transform (FR2 §2.0).

### Finance (CFO) — carry-forward

**Status:** reviewed
**Assessment:** D-fallback ~$39-45/mo at 3 operators. Path B (Datadog) rejected. Sentry renewal 2026-06-17 is $0 net.

### Operations (COO) — carry-forward + IaC routing updates

**Status:** reviewed
**Assessment:** IaC routing gate (Phase 2.8) folded 3 NEEDS-AMENDMENT: journalctl removed from Phase 3.3 primary, Doppler secret via file-stdin (Phase 3.2), version/sha drift sync (Phase 4.1 step 2).

### Product/UX Gate

**Tier:** none — internal infra + legal corpus edits, no user-facing UI changes. Mechanical-escalation override does not apply.

## Infrastructure (IaC)

### Terraform changes

**None.** No TF resources modified. No new providers, no new variables, no new resources. No new Doppler secrets (`SENTRY_USERID_PEPPER` + `BETTERSTACK_LOGS_TOKEN` already exist in `prd`). The plan does NOT bump `vector_version`/`vector_sha256` (premise inversion — see Research Reconciliation §1).

### Apply path

**Idempotent bootstrap script via OCI tag push.** Flow:
1. Merge PR → `vector.toml` lands on `main`.
2. `apply-web-platform-infra.yml` fires; `validate-vector-config` (path-filtered, BLOCKING) runs `vector validate` + `vector vrl` fixtures.
3. `apply` job runs `terraform plan/apply` (no TF changes for vector.toml itself).
4. **Operator pushes `vinngest-vX.Y.Z` OCI tag within 24h of merge** (AC16 deadline). CI mints version (`wg-never-bump-version-files-in-feature`).
5. OCI build workflow rebuilds image with `vector.toml` embedded.
6. Deploy webhook fires → host pulls + runs new image → `inngest-bootstrap.sh` runs → `systemctl restart vector.service` → new `vector.toml` active.
7. **No operator SSH at any step.** No operator-typed `doppler secrets set X=value` (FR3.2 uses `--plain-stdin < /tmp/bs-token` + `shred -u` per IaC-2).
8. **Reversibility:** revert PR; push new OCI tag; same path replays.

### Distinctness / drift safeguards

- **`dev != prd`:** Vector is prd-only. No dev deploy.
- **`lifecycle.ignore_changes`:** N/A.
- **State-storage:** `vector.toml` in git. Doppler `prd` only.
- **Version/sha drift safeguard** (per IaC-3): `validate-vector-config` job parses `vector_version` from `vector.tf` at job start; no hardcoded version in workflow YAML.

### Vendor-tier reality check

- Better Stack paid Logs tier already active. EU residency on standard paid tier.
- Vector 0.43.1 binary free from `packages.timber.io`.
- No new vendor accounts.

## Observability

```yaml
liveness_signal:
  what: "Better Stack source ingest rate (post-Vector-pii-scrub events/sec) + existing Sentry cron monitor for OAuth canary (scheduled-oauth-probe)"
  cadence: "Continuous (Better Stack); hourly (Sentry cron monitor on jikigai-eu)"
  alert_target: "Better Stack dashboard email; Sentry issue + cron-monitor missing-heartbeat alert"
  configured_in: "apps/web-platform/infra/vector.toml [sinks.betterstack]; apps/web-platform/infra/sentry/cron-monitors.tf scheduled_oauth_probe"
error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN in Doppler prd, de.sentry.io cluster, jikigai-eu org); Better Stack Logs (BETTERSTACK_LOGS_TOKEN in Doppler prd, per-source EU ingesting host post-FR3)"
  fail_loud: "PII-scrub failure surfaces in Better Stack as log lines with pii_scrub_applied=skipped_*; Sentry boot warning if SENTRY_USERID_PEPPER unset (apps/web-platform/server/observability.ts:16-21)"
failure_modes:
  - mode: "VRL transform parse error on an unfixtured journald line shape"
    detection: "Better Stack saved query: pii_scrub_applied contains 'skipped_unparseable' AND _time > now() - 1h"
    alert_route: "Better Stack saved-query alert on threshold > 100 events/hr (configured 7-day post-merge per R2)"
    layer: "Vector journald source + pii_scrub_structured transform (TR9 PR-5 + Phase 2 of this PR)"
  - mode: "Pepper unset on vector.service worker boot"
    detection: "Better Stack saved query: pii_scrub_applied contains 'skipped_pepper_unset' (zero in steady state; > 0 indicates env-injection drift)"
    alert_route: "Better Stack saved-query alert"
    layer: "Vector startup + Doppler env injection at inngest-bootstrap.sh:380"
  - mode: "Better Stack ingest endpoint unreachable (DNS, TLS, 5xx, 401)"
    detection: "Vector internal_metrics emits sink errors to journald (local stdout per [sinks.vector_console]); Better Stack heartbeat-only path (decoupled) catches via existing 60s heartbeat alert"
    alert_route: "Better Stack heartbeat alert (existing); Sentry would not catch directly"
    layer: "Vector sink + Better Stack ingest"
  - mode: "Sentry cron monitor missed heartbeat (OAuth canary)"
    detection: "Sentry scheduled-oauth-probe monitor red within 30min grace window post-cron"
    alert_route: "Sentry issue + alert rule (existing, unchanged)"
    layer: "Sentry cron monitor + Inngest function cron-oauth-probe.ts:690"
  - mode: "FR3.2 token-swap window data loss"
    detection: "Vector internal_metrics shows non-zero sink_error_count during the swap window; Better Stack source dashboard shows ingestion gap"
    alert_route: "Operator follows 5-step atomic ordering in Phase 3.2; sink_error_count check post-deploy"
    layer: "Vector sink (UI-F2 mitigation)"
logs:
  where: "Better Stack Logs (post-FR3 EU ingesting host); Sentry events (errors only, jikigai-eu); journalctl -u vector.service on Hetzner VM (local-only DEBUG fallback per Sharp Edges)"
  retention: "Better Stack paid Logs tier default (recorded in PA8 §(f) as `__TBD_BETTERSTACK_RETENTION__` per GDPR-Imp); Sentry 90 days rolling; journald local rotation per Hetzner config"
discoverability_test:
  command: "gh run list --workflow apply-web-platform-infra.yml --branch main --limit 1 --json conclusion,name | jq -r '.[] | select(.name == \"apply-web-platform-infra\") | .conclusion' | grep -q success && curl -fsS https://uptime.betterstack.com/api/v2/sources/2457081/stats -H \"Authorization: Bearer $BETTERSTACK_API_TOKEN\" | jq '.events_per_second > 0'"
  expected_output: "true (apply succeeded AND Better Stack source is ingesting); operator runs locally with Doppler-injected BETTERSTACK_API_TOKEN — no SSH, no production-host login. Fallback: Better Stack public-status page OR Sentry cron-monitor URL."
```

Layer-citation per `hr-observability-layer-citation`: every failure mode cites layer. No-SSH per `hr-no-ssh-fallback-in-runbooks`: `discoverability_test.command` uses `gh run` + `curl` + `jq`; `journalctl` is local-debug-only per Sharp Edges + IaC-1 fix.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is fully populated.
- When AC1 verification grep runs, the existing heartbeat-context "Better Stack" mention pre-dates this PR. Use anchored regex `grep -cE "Better Stack.*(processor|Logs|sub-processor)"` (per Sharp Edge + SF-P0-5), NOT naive substring count.
- VRL `hmac()` returns RAW BYTES; without `encode_base16()`, the output is non-printable and Better Stack Logs will mangle it. AC4 catches drift via Node import of `hashUserId` + openssl backstop.
- The `validate-vector-config` job's dummy `BETTERSTACK_LOGS_TOKEN=dummy` + `SENTRY_USERID_PEPPER=dummy` env is sufficient for `--no-environment` schema-only validation. VRL fixture tests use a synthetic `SENTRY_USERID_PEPPER='fixture-only-do-not-use-in-prod'` — NEVER reads from Doppler.
- The `validate-vector-config` job is PATH-FILTERED (UI-F5) — does NOT cascade-block unrelated infra apply. Hotfixes on other infra files (Hetzner firewall, Doppler tokens, alerts) see the job SKIPPED.
- FR3.2 token-swap (if it fires) follows a 5-step atomic ordering. Skipping a step or reordering may lose user-incident log lines during the window — explicit operator ack required per AC8.
- The PR body MUST use `Ref #4273` not `Closes #4273` — partial closure of the umbrella decision.
- `journalctl` is local-debug-only (Sharp Edges + IaC-1). Discoverability test command uses `gh run` + `curl` + `jq`.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-observability-consolidation-4273-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-observability-consolidation-4273/spec.md`
- Issue: #4273 (umbrella, OPEN, this plan closes Phase 1 FRs via `Ref`)
- Sibling issues: #4296 (60-day re-decision), #4297 (Sentry-envelope contract test), #4298 (Vector staging VM), #4300 (Better Stack residency-check skill)
- NEW follow-up: gdpr-gate regex extension (`vector.toml$`) — filed per FR10.7 / simplicity-Cut-3
- Adjacent open work: #3814 (Sentry Monitors/Alerts split, p1-high), #3815 (multi-tenant Sentry DPA), #3865 (Sentry residency check skill), #3866 (Doppler TF_VAR_sentry_region)
- Recently merged (all 2026-05-21): #4250, #4271, #4272, #4277, #4278, #4279
- Closed since brainstorm: #4211 (Inngest cron substrate migration, closed 2026-05-22)
- ADR-029 `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` — amended in this PR (§I4 consumer list)
- ADR-031 `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — Sentry plane TF onramp (unchanged)
- Vector PR #19274 (closed unmerged 2025-01-27) — proof native `better_stack_logs` sink does NOT exist
- Better Stack Vector integration docs (`https://betterstack.com/docs/logs/vector/`) — proof generic HTTP IS the canonical pattern
- Plan-review prior-art: `2026-05-12-client-side-pii-strip-when-server-pepper-cannot-ship.md`, `2026-04-17-pii-regex-scrubber-three-invariants.md`, `2026-04-17-log-injection-unicode-line-separators.md`, `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`, `2026-05-16-procedural-deadline-disclosure-is-the-critical-path-not-remediation.md`, `2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md`, `2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`, `2026-03-18-dpd-processor-table-dual-file-sync.md`
- Plan-review 6-agent panel output (2026-05-22): GDPR-gate (legal-compliance-auditor), IaC routing (terraform-architect), spec-flow-analyzer, code-simplicity-reviewer, architecture-strategist, user-impact-reviewer — all findings folded in per `### Domain Review` sub-sections above.
