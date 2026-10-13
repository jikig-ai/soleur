---
title: TR9 PR-11 — migrate scheduled-ux-audit to Inngest cron (substrate extension)
date: 2026-05-25
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
parent: "#3948"
---

# Brainstorm: TR9 PR-11 — Migrate scheduled-ux-audit to Inngest cron substrate

## What We're Building

The 11th and most-complex TR9 child migration: port `.github/workflows/scheduled-ux-audit.yml` (monthly `0 9 1 * *`) to the Inngest cron substrate. Unlike PR-1..PR-10, this migration is a **substrate extension**, not a clean port — it adds two capabilities to the Hetzner Inngest runner that no prior cron-*.ts handler required:

1. **Playwright Chromium + browser deps** baked into the Hetzner Docker image.
2. **Playwright MCP server** registered for the spawned `claude-code`, with a container-appropriate `--user-data-dir` (the existing `.mcp.json` points at `/home/jean/.cache/...`, an operator-only path).

Plus two ux-audit-specific lifecycle steps that mutate prd Supabase state:

3. **Bot-fixture seed + Supabase signin** to mint a short-TTL storageState JWT for `ux-audit-bot@jikigai.com`.
4. **Findings + screenshot upload** to a private Supabase bucket with 5-min signed URLs (GHA's `actions/upload-artifact` has no Inngest equivalent).

Permanent dry-run policy from the source workflow (per #2378 calibration miss) is mirrored verbatim. Calibration unlock is **explicitly out of scope** — filed as a separate follow-up issue.

## Why This Approach

**Three-PR rollout (A → B → C):** maximum revert isolation per CTO assessment. Each PR independently shippable, each smoke-validated before the next lands.

- **PR-A — substrate-gap closure.** Dockerfile adds Playwright apt deps + `npx playwright install chromium` bake step (~500MB image bloat, acceptable; pull cost paid once per deploy). Adds a minimal `cron-playwright-smoke.ts` handler that opens `https://example.com` and screenshots. Sentry monitor `scheduled-playwright-smoke`. ADR-033 amendment (I4 extension + new I7) ships here.
- **PR-B — bot-fixture lifecycle + Supabase artifact bucket.** Extracts `bot-fixture.ts seed|reset` + `bot-signin.ts` into Inngest-spawnable form. Adds Supabase migration creating `ux-audit-artifacts` private bucket with RLS scoped to the ux-audit-bot tenant. storageState path convention (`mkdtemp` + 0o700 dir + 0o600 file + ~10min JWT TTL + finally-unlink with 3× retry + entry sentinel asserting zero `/tmp/ux-audit-*` survives).
- **PR-C — cron-ux-audit + GHA delete atomic.** The handler itself, the verbatim-extracted prompt file, the per-fire `.mcp.json` overlay (mirrors `.claude/settings.json` overlay pattern at `cron-legal-audit.ts:333-340`), the Supabase upload + signed-URL post to PRIVATE monitoring repo issue, **delete of `.github/workflows/scheduled-ux-audit.yml` in the same commit** (TR9 I-13 hygiene per PR-7..PR-10 precedent). Sentry monitor atomic swap.

**Rejected — single PR:** collapses substrate-mutation + shared-state-mutation + agent-prompt-calibration into one revert unit. A Chromium apt regression would roll back the prompt; a bot-fixture race would roll back the image bake. Per CTO: "root-cause attribution on the first post-deploy Sentry alarm is non-deterministic."

**Rejected — two PRs (A + BC):** bundled bot-fixture+cron-ux-audit PR is ~1000 LoC. CTO + repo-research converge that shared-state mutations and Anthropic-prompt-loop mutations are orthogonal failure modes; bundling them re-creates the single-PR revert-fan-in problem at smaller scale.

## User-Brand Impact

**Vector:** bot-fixture storageState JWT for `ux-audit-bot@jikigai.com` is a Supabase session token for a service-like identity. The threat-model shift from GHA (ephemeral per-job UID, vanishes on runner destroy) to Hetzner Inngest (long-lived container, ~12 cron handlers + bug-fixer share UID) is real. If `mkdtemp` workspace teardown silently fails (bwrap holds fd, ENOSPC), the JWT can linger in `/tmp` and be readable by adjacent handlers that share the same UID inside the container. Authenticated screenshot artifacts (DOM state, route structure) compound the surface.

**Threshold:** `single-user incident` (single founder-tenant data flow; not multi-tenant blast radius today, but the precedent shapes how all future authenticated cron-Playwright work handles auth materials).

**Controls (all required, CLO):**
- mkdtemp with 0o700 dir + 0o600 storageState file
- JWT TTL = 10 minutes (real control; same-UID processes bypass POSIX perms)
- `try/finally` unlink with 3× retry (100ms backoff); on final failure → Sentry `error` + `process.exit(1)`
- Entry sentinel asserting `find /tmp -maxdepth 1 -name 'ux-audit-*' | wc -l == 0` at handler entry; refuse to start if drift detected
- Screenshots upload to Supabase private bucket (AES-256 at rest, RLS by ux-audit-bot tenant); signed URLs ≤5 min; URLs (not bytes) posted to PRIVATE monitoring repo issue
- Public GH issue comment **rejected** (search-indexed; no revocation)
- GitHub `user-images.githubusercontent.com` **rejected** (public-by-obscurity)

Art. 32 "appropriate technical measures" + Art. 5(1)(f) "integrity and confidentiality" both satisfied by the above.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Multi-PR rollout: PR-A (Docker+smoke) → PR-B (bot-fixture+Supabase bucket) → PR-C (cron+delete) | CTO: revert isolation. Aligns with TR9 PR-7..PR-10 same-PR-delete hygiene per `cron-monitors.tf` "TR9 I-13" headers. |
| 2 | Image-bake Playwright Chromium (not handler-startup install) | bwrap categorically blocks apt at handler time (Agent SDK sandbox argv has no privilege-escalation path). Image-bake aligns with PR #3654/#3664 precedent (`mcr.microsoft.com/playwright` container for CI tests). ~500MB image bloat acceptable; pull cost paid once per deploy. |
| 3 | ADR-033 amendment: extend I4 + add I7 | I4 extension acknowledges Chromium revision as a second binary in the pin surface (must track `apps/web-platform/package.json` Playwright devDep). I7 (new): Chromium process-group reaping requirement after SIGKILL window. Both ride PR-A. Add via `[Refined YYYY-MM-DD]` notes per existing ADR-033 pattern. |
| 4 | Concurrency: re-use existing `cron-platform` account-scope key (limit=1). No new `bot-fixture-shared-state` key today. | Repo-research: `cron-platform` already enforces full serialization across ALL cron-* handlers. Dual-key is YAGNI until a NON-cron event-fn touches bot-fixture. **Defer:** if a future event-triggered fn touches `ux-audit-bot` rows, add the `bot-fixture-shared-state` lane in that PR. |
| 5 | Per-fire `.mcp.json` overlay written by the handler | Repo-shipped `.mcp.json` points at `/home/jean/.cache/playwright-mcp-profile` (operator home, doesn't exist in container). Handler materializes a per-fire `.mcp.json` with `--user-data-dir=<mkdtemp>/playwright-mcp-profile/` (per-handler isolation via subdir, NOT `--isolated` per `2026-05-12-playwright-mcp-isolated-flag-wipes-oauth-sessions.md`). Mirrors the `.claude/settings.json` overlay pattern. |
| 6 | claude-code version: NO bump | Repo-research: `package.json:25` pins `2.1.142` (Dockerfile L45's `2.1.79` is a separate global-install pin; the I4 module-load uses `createRequire` against package.json). The workflow's `thinking.type.adaptive` note targets `claude-code-action`, not direct CLI spawn. CLI emits the modern thinking shape internally. |
| 7 | GHA workflow delete: SAME commit as PR-C cron-ux-audit.ts | TR9 I-13 hygiene per PR-7..PR-10 precedent (verified via `git diff-tree` on commits `d1e61d52`, `6a1db695`, `fb135a73`, `f817d450`). Inngest cron `0 9 1 * *` + GHA cron `0 9 1 * *` would fire simultaneously on shared `ux-audit-bot@jikigai.com` Supabase rows (concurrency groups are scheduler-local, not cross-substrate). |
| 8 | Findings/screenshot destination: Supabase private bucket + 5-min signed URLs to PRIVATE monitoring repo issue | CPO + CLO converge. Bucket `ux-audit-artifacts` with RLS scoped to ux-audit-bot tenant. PNG + findings.json upload per-run with path `{run_id}/{route}.png`. AES-256 at rest, GDPR Art. 32 satisfied. Public GH + `user-images.githubusercontent.com` rejected. |
| 9 | Permanent dry-run mirrored. Calibration unlock = separate issue | CPO: "Opus 4.7 will not reliably fix [the agent-prior mismatch] without a fresh calibration pass; bundling that into the substrate migration conflates two concerns." Calibration spike filed as own follow-up. |
| 10 | Monthly cadence unchanged | CPO: founder-attention is the bottleneck, not compute. Weekly would accrete unread artifacts. Revisit if/when calibration unlocks auto-file mode. |
| 11 | I3 (SIGTERM→SIGKILL) verification gate at plan-time Phase 0.3 | CTO + learnings: Chromium grandchild process groups spawned by `npx @playwright/mcp` may orphan after the 5s escalation window. Mirror ADR-033 I3's "verified at Phase 0.3" pattern: spawn claude-code with Playwright MCP active, trigger AbortSignal, `ps -ef --forest` count check, refuse PR-A merge if orphans remain. If orphans observed, add per-fire `pkill -P <claude-pid> chrome` reaper to the handler (I7 control). |

## Open Questions

These are planning-phase decisions, not blockers for this brainstorm:

1. **Smoke handler scope (PR-A).** Does `cron-playwright-smoke.ts` need to roundtrip through claude-code+MCP, or is a direct `playwright-core` chromium-launch + screenshot sufficient? The former proves the full stack (substrate→bwrap→claude-code→MCP→Chromium); the latter is faster but doesn't validate the load-bearing path.
2. **PR-A Sentry monitor lifecycle.** The smoke handler is a temporary diagnostic — does it stay in main after PR-C lands? Two options: (a) keep it monthly as a substrate-health-check; (b) delete in PR-C. Recommend (a) — independent canary for the Playwright bake.
3. **Supabase bucket migration sequencing.** PR-B's `ux-audit-artifacts` bucket needs a Supabase migration. Does the migration ship with PR-B, or as its own PR-B-prereq? Recommend PR-B (standard migration cadence; bucket has no consumers until PR-C lands).
4. **Bot-fixture API in cross-process form.** Current `bot-fixture.ts` is a CLI invoked via `bun`; the Inngest handler needs to invoke it as a `step.run` step. Two shapes: (a) keep CLI, spawn it via `child_process.spawn` inside `step.run`; (b) extract to a library function importable from the handler. Recommend (b) — better deterministic stdout capture per ADR-033 I5, and avoids a second spawn surface stacking on the claude-code spawn.
5. **Calibration re-run plan.** Once PR-C ships, when does the calibration spike fire? Need a separate brainstorm or just an issue with re-evaluation criteria? Recommend the latter — gate on "3 successful Inngest fires + founder-review of findings.json artifacts."

## Domain Assessments

**Assessed:** Marketing (n/a), Engineering, Operations (n/a — image-bake handled by deploy pipeline), Product, Legal, Sales (n/a), Finance (n/a — no new vendor), Support (n/a).

### Engineering (CTO)

**Summary:** Three-PR rollout (A/B/C) with PR-A as substrate-gap closure (Dockerfile + smoke handler). Image-bake Chromium with ADR-033 I4 amendment + new I7 (Chromium process-group reaping). Same-PR GHA delete in PR-C. I3 SIGTERM→SIGKILL escalation needs verification at plan-time Phase 0.3 due to Chromium grandchild process groups under `npx @playwright/mcp`. Net-new bwrap+Chromium+Inngest stacking risk per learnings — treat as unowned risk requiring observability + post-ship learning capture.

### Product (CPO)

**Summary:** Mirror permanent-dry-run policy unchanged. Calibration unlock is a separate spike (Opus 4.7 won't fix agent-prior mismatch without fresh calibration pass; bundling conflates two concerns). Findings upload via Supabase storage (already in stack, RLS-scoped). Monthly cadence stays — founder-attention is the bottleneck, not compute.

### Legal (CLO)

**Summary:** Storage-state JWT lifecycle risk is moderate (long-lived Hetzner container vs ephemeral GHA runner). Controls required: mkdtemp 0o700, file 0o600, short JWT TTL (10 min), `try/finally` unlink with 3× retry + Sentry+exit-1 on final failure, entry sentinel. Screenshot artifacts → Supabase private bucket + 5-min signed URLs to PRIVATE repo monitoring issue. Public GH + `user-images.githubusercontent.com` rejected. Art. 32 + Art. 5(1)(f) satisfied.

## Session Errors

1. **ADR-033 ID collision (pre-existing, not introduced here).** `knowledge-base/engineering/architecture/decisions/` contains THREE files at slot 033: `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` (the cron one), `ADR-033-per-tenant-scope-grants.md`, `ADR-033-runtime-jwt-signing-substrate.md`. Independent ADRs sharing an ID is a numbering bug — the next ADR-numbering brainstorm should reconcile. Out-of-scope for PR-11; flag in plan as "do not re-number ADR-033-cron during the amendment."

2. **CTO assumed `@anthropic-ai/claude-code@2.1.79` from Dockerfile L45.** Repo-research corrected: canonical pin is `package.json:25 → 2.1.142`. The Dockerfile L45 global-install pin is a separate concern (used only for fresh-host bootstrap; cron handlers resolve the binary via `createRequire`). Reconciled in Decision #6.

3. **CTO recommended dual-key concurrency (`cron-platform` + `bot-fixture-shared-state`).** Repo-research corrected: `cron-platform` already enforces limit=1 across ALL cron-* handlers — full serialization. Dual-key is YAGNI today. Reconciled in Decision #4.

4. **CTO assumed `.mcp.json` "just works" from cloned repo.** Repo-research corrected: `.mcp.json` is cloned + not scrubbed, BUT the existing entry points at `/home/jean/.cache/playwright-mcp-profile` (operator home, doesn't exist in container). Reconciled in Decision #5 (handler writes per-fire overlay).

## Productize Candidate

None new. The existing `/soleur:migrate-cron-to-inngest` skill candidate (#3990) is the umbrella productize candidate for TR9 — PR-11 is the substrate-extension proof-of-pattern that would inform whether the skill captures substrate-extension migrations or only clean ports. **Re-evaluation criterion:** if PR-11 ships cleanly and the next substrate-extending cron migration (if any) reuses ≥60% of the PR-A/B/C template, fold this shape into the skill.
