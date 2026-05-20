---
title: "Tasks — Sentry residency reframe PR-1"
date: 2026-05-19
plan: knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md
spec: knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md
brand_survival_threshold: single-user incident
lane: cross-domain
---

## Phase 0 — Preflight

- [ ] 0.1. Verify worktree: `git rev-parse --show-toplevel` ends with `.worktrees/feat-sentry-residency-reframe-3861`; `git branch --show-current` = `feat-sentry-residency-reframe-3861`.
- [ ] 0.2. Verify Doppler `prd` token: `doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain >/dev/null && echo OK`.
- [ ] 0.3. Verify PIR pre-edit state: `sed -n '7,20p' knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` shows `status: resolved`, `art_33_triggered: true`, `art_33_deadline`, `classification_override.chosen: none`. Halt if reality differs.
- [ ] 0.4. Verify Playwright MCP reachable + Sentry UI session logged in as `jean.deruelle@jikigai.com`.

## Phase 1 — Probe (3 steps, retry policy + halt table)

- [ ] 1.1. Step 1 — prd token vs `jikigai` via curl; capture `STEP1`. Retry policy: 3 × 30s `--max-time` × 5s linear backoff on 429/5xx/timeout.
- [ ] 1.2. Step 2 — prd token vs `jikigai-eu` (control); capture `STEP2`.
- [ ] 1.3. Step 3 — Playwright opens `https://jikigai.sentry.io/settings/account/api/auth-tokens/`.
- [ ] 1.4. Operator-ack gate: chat prompt with explicit scope/org/label/lifetime. Operator types `ACK` or `ABORT`. On `ABORT`, close Playwright tab and exit.
- [ ] 1.5. Mint token (org:read on jikigai, shortest UI-bucket lifetime, label `probe-2026-05-19-revoke`). Capture `PROBE_TOKEN_MINTED_AT` from `https://jikigai.sentry.io/settings/audit-log/` (poll up to 60s with `browser_wait_for`).
- [ ] 1.6. Run probe Step 3 curl with new token; capture `STEP3`. Token VALUE stays in memory only.
- [ ] 1.7. Revoke token IMMEDIATELY in same Playwright session. Capture `PROBE_TOKEN_REVOKED_AT` (poll up to 60s).
- [ ] 1.8. Apply halt table (plan Phase 1.4). If `STEP1 != 401` OR `STEP2 != 200` OR `STEP3 != 200` OR audit-log evidence missing OR token scope mis-granted, HALT. Do NOT proceed to Phase 2. Surface to operator with the verdict row.

## Phase 2 — Screenshots + redaction

- [ ] 2.1. Playwright `browser_take_screenshot`: audit-log page (mint + revoke entries visible).
- [ ] 2.2. Playwright screenshot: token list page (probe-2026-05-19-revoke + post-revoke state).
- [ ] 2.3. TR9 redaction sweep per screenshot (token values, card numbers, non-operator emails, non-public Sentry IDs, CSRF/sudo cookies). Use ImageMagick CLI: `convert in.png -draw "rectangle x1,y1 x2,y2" -fill black out.png`. Opaque rectangles only.
- [ ] 2.4. Save redacted PNGs to `knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/{mint,revoke,audit-log}.png`.

## Phase 3 — Write report + edit PIR + edit script + breadcrumbs

- [ ] 3.1. Write `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md` per plan §3.1 structure (Purpose, Probe sequence, Results table, Verbatim Sentry replies, Audit log evidence, Verdict, Forward pointer).
- [ ] 3.2. Edit PIR frontmatter: DELETE `art_33_triggered` line; DELETE `art_33_deadline` line; flip `status: resolved` → `open`; update `classification_override.chosen` → `superseded-2026-05-19`; prefix `classification_override.reason` value with `"[Superseded 2026-05-19 per Phase 9 Gate-3b correction.] "`; ADD `gate_3_resolution: 3b`; ADD `gate_3_resolution_evidence: <probe-report-path>`.
- [ ] 3.3. Append `## Phase 9 — Gate 3b Correction (2026-05-19)` section to PIR body with (a) both Sentry replies verbatim, (b) what original framing got wrong (3 bullets), (c) probable root cause + probe report link + workflow-defect learning link, (d) Closes #3962 + supersedes notice for PR-α/PR-γ corpus (PR-2 retracts).
- [ ] 3.4. YAML parse gate: `python3 -c "import yaml,sys; doc=open('<pir>').read().split('---')[1]; yaml.safe_load(doc); print('PIR YAML OK')"` returns exit 0. On failure, `git checkout` PIR and retry 3.2-3.3.
- [ ] 3.5. Edit `apps/web-platform/scripts/sentry-monitors-audit.sh` lines 127-128 + insert one new line per plan "Files to Edit" §2. Operational header at L72 UNCHANGED.
- [ ] 3.6. Run `bash -n apps/web-platform/scripts/sentry-monitors-audit.sh` — must return exit 0.
- [ ] 3.7. Breadcrumb in `knowledge-base/legal/article-30-register.md` PA8 §(d): append `**[2026-05-19 NOTE: ...]**` at end of cell. Original prose verbatim.
- [ ] 3.8. Breadcrumb in `knowledge-base/legal/compliance-posture.md` row 89: append ` **[2026-05-19 NOTE: ...]**` at end of row's narrative cell.
- [ ] 3.9. Breadcrumb in `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md` frontmatter: add `superseded_by_note: "..."` key.

## Phase 4 — Commit + push + transition draft → ready

- [ ] 4.1. `git status --short` — verify expected staged + untracked set.
- [ ] 4.2. `git add` explicit file list (no `-A`).
- [ ] 4.3. Commit subject `feat: PR-1 — token-scope probe + PIR Gate-3b reopen + breadcrumbs`. Body cites probe verdict + Closes #3962 + Refs #3861 + Refs #3849 + threshold + triad sign-off.
- [ ] 4.4. `git push`.
- [ ] 4.5. `gh pr edit 4044 --body "<PR body>"` (Summary + 5-bullet What changed + Test plan mirroring AC1-AC11 + Closes/Refs lines + threshold).
- [ ] 4.6. `gh pr ready 4044`.

## Phase 5 — Review gates

- [ ] 5.1. `/soleur:gdpr-gate` against `gh pr diff 4044`. Critical findings block merge per compliance-posture.md auto-write.
- [ ] 5.2. user-impact-reviewer at PR review (label or approving comment).
- [ ] 5.3. (Advisory) security-sentinel for screenshot leak check; data-integrity-guardian for PIR delete-not-blank verification.

## Operator-driven parallel (anytime; migrates post-merge if not done by Phase 5)

- [ ] AC12. Operator replies to Sentry billing thread choosing "transfer credit to jikigai-eu" + card-last-4 + expiry direct to Sentry (NOT through agent conversation). Captures acknowledgment screenshot for PR-1 evidence if obtained pre-merge.

## Post-merge (operator)

- [ ] AC13.a. Verify #3962 auto-closed via `Closes #3962`.
- [ ] AC13.b. `gh issue edit 3861 --body ...` — append PR-1 number + "PR-2 corpus sweep next."
- [ ] AC13.c. `gh issue edit 3849 --body ...` — append probe-report link + partial-unblock note.
