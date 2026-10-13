# Tasks: observability consolidation #4273 — close P0 compliance gap

Plan: `knowledge-base/project/plans/2026-05-22-feat-observability-consolidation-4273-plan.md`
Issue: #4273 (umbrella, OPEN, this PR closes Phase 1 FRs via `Ref`)
Branch: `feat-observability-consolidation-4273`
PR: #4293

## Phase 0: Preconditions + premise verification

- [ ] 0.1 Verify cited PR/issue states (`gh issue view 4273 4296 4297 4298 4300 4321 3814 3815 3865 3866 4211 --json state,closedAt`; `gh pr view 4250 4271 4272 4277 4278 4279 --json state,mergedAt`). Expected: #4211 CLOSED 2026-05-22; all PRs MERGED 2026-05-21; others OPEN.
- [ ] 0.2 Confirm Vector 0.43.1 VRL primitive availability (`hmac()` since v0.29.0, `get_env_var!()` since v0.20, `parse_json()` since v0.13). No bump.
- [ ] 0.3 Verify `SENTRY_USERID_PEPPER` reachable in `vector.service` (`doppler secrets get SENTRY_USERID_PEPPER -p soleur -c prd --plain | wc -c` — read-only, do NOT echo value).
- [ ] 0.4 Better Stack source `2457081` region check via Playwright MCP → record region + per-source ingesting host in PR comment.
- [ ] 0.5 Confirm `hashUserId` exports cleanly via `node -e "require('./apps/web-platform/server/observability').hashUserId('test')"` (test-context dry-run).
- [ ] 0.6 Confirm Phase ordering 0→1→2→3→4→5→6 (Phase 5 depends on Phase 3 placeholders; Phase 4 ships SAME-PR as Phase 2).
- [ ] 0.7 Audit ADR-029 §I4 consumer list for VRL addition (Files to Edit row 3).
- [ ] 0.8 `grep -l 'vector\.toml' .github/workflows/*.yml` — expected only `apply-web-platform-infra.yml`.

## Phase 1: PR description + scope freeze

- [ ] 1.1 Write PR description with FR1/FR2/FR3 framing, premise-inversion flag, bundle-no-statutory-clock justification (per Arch-F9), Art-9 mitigation (FR2 §2.0), `Ref #4273`.

## Phase 2: VRL transforms in `vector.toml` (FR2)

- [ ] 2.0 Add `[transforms.pii_scrub_drop_userdata]` — drops top-level `body`/`content`/`message`/`userMessage`/`prompt`/`chat_message`/`userInput`/`user_input` keys from parsed pino payload (Art-9 mitigation per GDPR-Crit-5).
- [ ] 2.1 Add `[transforms.pii_scrub_structured]` — case-insensitive `userId`/`user_id` ONLY (NOT `workspaceId`/`workspace_id` per SF-P0-3); HMAC-SHA256 + base16 with `SENTRY_USERID_PEPPER`; defensive idempotence (preserve preset `userIdHash`); fail-safe `skipped_pepper_unset` tag.
- [ ] 2.2 Add `[transforms.pii_scrub_string]` — GUARD: skip if `pii_scrub_applied` contains "structured" (Arch-F2 JSON-corruption prevention); length-bound 10000; `(?i)\b(userid|user_id)=[\w-]+` (SF-P0-2 Hole C); email regex; Authorization Bearer/Basic; line-injection chars `\x00-\x1f\x7f  `. **Do NOT redact `/api/auth/callback/*`** (per UI-F1).
- [ ] 2.3 Rewire `[transforms.tag_journald].inputs = ["pii_scrub_string"]`; `[sinks.betterstack].inputs` unchanged.
- [ ] 2.4 Correct `vector.toml:8-12` header comment — generic HTTP is canonical vendor pattern; native sink does NOT exist (Vector PR #19274 closed unmerged).
- [ ] 2.5 Amend ADR-029 §I4 consumer list to add VRL bullet (SF-P0-6).
- [ ] 2.6 Create `apps/web-platform/test/infra/vector-pii-scrub.test.sh` with heredoc fixtures: pino-with-userid, kernel-oops-with-userid-substring, kernel-oops-with-email, authorization-bearer-leak, line-injection-unicode, user-content-body-key (Art-9), null-userid-value, UTF-8-pepper-fixture. Bit-for-bit parity via Node `hashUserId` import + openssl backstop (Arch-F1).

## Phase 3: Better Stack EU endpoint pin (FR3)

- [ ] 3.1 (if 0.4 showed EU) Update `vector.toml:99` `uri = "https://<per-source-ingesting-host>/"`. Add verification comment block (Better Stack dashboard URL + date + region).
- [ ] 3.2 (if 0.4 showed US — atomic ordering per UI-F2):
  - [ ] 3.2.1 Playwright login + create new EU source (old still live); token to `/tmp/bs-token-extracted` via `browser_evaluate(filename: ...)`.
  - [ ] 3.2.2 PR commits new EU URI in `vector.toml`.
  - [ ] 3.2.3 After OCI rebuild + deploy: `doppler secrets set BETTERSTACK_LOGS_TOKEN --plain-stdin -p soleur -c prd < /tmp/bs-token-extracted && shred -u /tmp/bs-token-extracted`.
  - [ ] 3.2.4 Verify Better Stack source-stats shows ingest.
  - [ ] 3.2.5 Revoke OLD source via Playwright.
- [ ] 3.3 Document no-SSH verification (curl Better Stack API; `journalctl` is local-debug-only per IaC-1).

## Phase 4: vector validate + vector vrl CI gate (FR5)

- [ ] 4.1.1 Add `validate-vector-config` job to `.github/workflows/apply-web-platform-infra.yml`; **path-filter on `apps/web-platform/infra/vector.toml` + `apps/web-platform/test/infra/**`** (per UI-F5 cascade fix).
- [ ] 4.1.2 Job step: parse `vector_version` from `vector.tf` at job start (IaC-3 drift safeguard; no hardcoded version in workflow YAML).
- [ ] 4.1.3 Job step: download Vector binary (no `actions/cache` per simplicity-Cut-2).
- [ ] 4.1.4 Job step: `vector validate --no-environment --config-toml vector.toml` with dummy env vars.
- [ ] 4.1.5 Job step (BLOCKING per Arch-F4): `SENTRY_USERID_PEPPER='fixture-only-do-not-use-in-prod' bash apps/web-platform/test/infra/vector-pii-scrub.test.sh`.
- [ ] 4.2 `apply` job `needs: [preflight, validate-vector-config]`; skipped jobs treated as PASS (path-filter outside vector scope).
- [ ] 4.3 Break-glass: document `compliance/critical` labeled-PR + manual approval comment path.

## Phase 5: Legal disclosure corpus update (FR1)

- [ ] 5.0 PA8 §(b)(vi) NEW purpose — "Off-host long-tail operational log aggregation" (GDPR-Crit-1).
- [ ] 5.1.1 PA8 §(c)(ii) — extend "no off-host copies" sentence with Vector + three-transform pipeline reference.
- [ ] 5.1.2 PA8 §(d) — append 2026-05-22 UPDATE block (Better Stack Logs recipient); include future-REMOVED-block-pattern note (Arch-F6).
- [ ] 5.1.3 PA8 §(e) — append Better Stack EU bullet (region from FR3).
- [ ] 5.1.4 PA8 §(f) — replace "No off-host copies" with Better Stack retention `__TBD_BETTERSTACK_RETENTION__` placeholder.
- [ ] 5.1.5 PA8 §(g) — append VRL three-transform TOM + CI gate.
- [ ] 5.1.6 Vendor / Sub-Processor Mapping table — new Better Stack row (Logs role distinguishes from heartbeat).
- [ ] 5.2 `compliance-posture.md` Vendor DPA Status table — new Better Stack row.
- [ ] 5.3 `docs/legal/privacy-policy.md` — NEW §5.11 "Better Stack s.r.o. (Operational Log Aggregation)" (GDPR-Crit-2; NOT append to §5.10).
- [ ] 5.4 `docs/legal/data-protection-disclosure.md` §2.3(m) line 103 — REPLACE FALSIFIED CLAIM with two-recipient-role split.
- [ ] 5.5 `docs/legal/gdpr-policy.md` — add explicit positive "Better Stack Logs IS enabled" disclosure (GDPR-Crit-3 symmetric falsification fix).
- [ ] 5.6 DPD/PP dual-file sync: mirror 5.3 + 5.4 + 5.5 in `plugins/soleur/docs/pages/legal/`. Verify `diff -u` returns zero diff post-frontmatter strip.
- [ ] 5.7 Cross-reference grep audit: `grep -nE '2\.3\(m\)' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` — confirm cross-refs still resolve.

## Phase 6: Spec + sibling-issue corrections (FR10)

- [ ] 6.1 Append `## Plan-Time Corrections` (C1-C6) to spec `feat-observability-consolidation-4273/spec.md`.
- [ ] 6.2 `gh issue edit 4296` — update body with corrected 60-day re-decision criteria (D-native ≡ D-fallback); re-list all surviving evidence axes.
- [ ] 6.3 `gh issue edit 4298` — re-prioritize "DEFERRED indefinitely".
- [ ] 6.4 `gh issue edit 4300` — re-prioritize "More urgent than originally framed".
- [ ] 6.5 (Already done at plan-write time per Deferral tracking check) Verify follow-up issue #4321 (gdpr-gate regex extension `vector.toml$`) exists.

## Phase 7: Verification + PR-ready

- [ ] 7.1 Run all AC pre-merge greps (AC1-AC15); all must pass.
- [ ] 7.2 Push branch; CI must show `validate-vector-config` ran and passed.
- [ ] 7.3 If FR3.2 fired, ensure 5-step atomic ordering checklist + operator ack comments are in PR body (AC8).
- [ ] 7.4 If Better Stack DPA unsigned at PR-ready, file `compliance/critical` follow-up + CLO ack in PR body (AC15).
- [ ] 7.5 PR body anchor strings: `Ref #4273`, `Brand-survival threshold: single-user incident`, `requires_cpo_signoff: true`, bundle-no-statutory-clock citation (AC14).

## Phase 8: Post-merge operator actions (AC16-AC19)

- [ ] 8.1 (AC16, 24h deadline) Push `vinngest-vX.Y.Z` OCI tag (CI mints version). Deploy webhook fires; Better Stack source shows ingest events with `pii_scrub_applied` tag populated within 1h.
- [ ] 8.2 (AC17, 1h) Sentry `scheduled-oauth-probe` cron monitor still green on `jikigai-eu`.
- [ ] 8.3 (AC19, 30d) Better Stack monthly invoice variance ≤15% vs pre-PR baseline. Tracked in `compliance-posture.md` follow-up entry.
- [ ] 8.4 7-day post-merge: query `pii_scrub_applied = "skipped_unparseable"` count; > 100/day triggers follow-up issue for un-fixtured log shapes (per R2).
