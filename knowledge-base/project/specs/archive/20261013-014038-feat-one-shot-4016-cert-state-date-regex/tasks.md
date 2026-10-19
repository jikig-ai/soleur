---
lane: single-domain
plan: knowledge-base/project/plans/2026-05-18-fix-cert-state-date-regex-plan.md
issue: 4016
---

# Tasks — fix cert-state date regex

## Phase 0 — Preconditions

1. **0.1** [x] Re-read `.github/workflows/scheduled-gh-pages-cert-state.yml:135-141` to lock the exact 7 lines to edit.
2. **0.2** [x] Run `actionlint .github/workflows/scheduled-gh-pages-cert-state.yml` → confirm clean baseline (exit 0).
3. **0.3** [x] Re-confirm GH Pages API contract: `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate'` returns `expires_at` as a date-shape string. Cite output in PR body.

## Phase 1 — Edit (RED → GREEN)

1. **1.1** [x] Replace `.github/workflows/scheduled-gh-pages-cert-state.yml:135-141` with the two-branch form (date-only `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` → EOD UTC; ISO datetime `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}` → as-is; else → original error literal + exit 1). Use `date -u -d` (not `date -d`).
2. **1.2** [x] Add a one-line comment above the new block: `# GitHub Pages API returns "string, format: date" per docs — datetime branch is defensive.`

## Phase 2 — Verify

1. **2.1** [x] Extract the modified `run:` block and exercise three fixtures via `bash -c '<extracted snippet>'`:
   - `EXPIRES_AT="2026-08-16"` → exit 0, `EXPIRES_EPOCH=1786924799`.
   - `EXPIRES_AT="2026-12-31T12:00:00Z"` → exit 0, `EXPIRES_EPOCH=1798718400`.
   - `EXPIRES_AT="not-a-date"` → exit 1 with `::error::Unexpected expires_at format from API: 'not-a-date'`.
2. **2.2** [x] Re-run `actionlint .github/workflows/scheduled-gh-pages-cert-state.yml` → still clean.
3. **2.3** [x] `shellcheck` over the extracted `run:` block (capture baseline first) → no new findings.

## Phase 3 — Ship

1. **3.1** Commit with `Closes #4016` in the PR body (NOT the title).
2. **3.2** `/soleur:ship` post-merge: `gh workflow run scheduled-gh-pages-cert-state.yml --ref main` → confirm green, heartbeat=ok, `days_remaining ≥ 1`.
3. **3.3** Smoke-test the alert path: `gh workflow run scheduled-gh-pages-cert-state.yml --ref main -f state_override=bad_authz` → confirm issue filed; `gh issue close <N>` after verification.

## Notes

- Out of scope: editing `scheduled-cf-token-expiry-check.yml` (its strict-ISO regex is correct for the Cloudflare API contract).
- Out of scope: adding a `jq -e .` JSON validation step in cert-state (a separate hardening; not what #4016 reports).
