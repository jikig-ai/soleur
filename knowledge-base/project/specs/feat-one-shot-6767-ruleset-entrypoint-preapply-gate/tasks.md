---
feature: feat-one-shot-6767-ruleset-entrypoint-preapply-gate
issue: 6767
lane: single-domain
plan: knowledge-base/project/plans/2026-07-22-feat-ruleset-entrypoint-preapply-gate-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — Pre-apply entrypoint-enumeration gate + retrospective drift audit (#6767)

Derived from the post-plan-review plan (6-agent panel applied). ADOPTION
(deliverable 1) is already merged via #6746 — do NOT re-implement it.

## Phase 0 — Preconditions (verify before writing)

- [x] 0.1 Capture a real `terraform show -json` (TF 1.10.5, cloudflare 4.52.7) and
  confirm: pure create = `actions == ["create"]` + `before == null` +
  `importing == null` (NOT `index("create")`); CBD first-create still `["create"]`;
  import signal is `change.importing`; adopted `seo_config_settings` is
  `["update"]`/`["no-op"]` in both phases.
- [x] 0.2 Confirm zone AND account entrypoint contracts (200/404/403);
  `CF_API_TOKEN_RULESETS` can read account rulesets; CI read path
  (`DOPPLER_TOKEN` + `doppler secrets get … --plain`).
- [x] 0.3 Re-read the destroy-guard cap-coupling convention.

## Phase 1 — Gate script (`tests/scripts/lib/preapply-entrypoint-gate.sh`)

- [x] 1.1 `set -euo pipefail`; token guard `[[ -n "$PREAPPLY_CF_TOKEN" ]]` → distinct fail-closed.
- [x] 1.2 Input validation: `jq -e '.resource_changes | type == "array"'` → fail-closed on parse error/non-array/empty.
- [x] 1.3 Pre-filter: `type == "cloudflare_ruleset"` AND `actions == ["create"]` (exact) AND `before == null` AND `importing == null`; iterate ALL `resource_changes[]` (never the `-target` list); aggregate a `fail` sentinel; `::notice::` matched+probe count; zero matches → exit 0, no API calls.
- [x] 1.4 Control probe once (known-populated phase, `curl --max-time`); non-200 → fail-closed "gate environment invalid".
- [x] 1.5 Per row: kind allowlist (zone/root → URL; other → fail-closed); null URL field → fail-closed; `curl --max-time`.
- [x] 1.6 Default-deny HTTP: 200+rules>0 → fail + copy-pasteable singular-form import remedy; 200+empty/404 → pass; everything else → fail-closed catch-all; jq parse fail → fail-closed.
- [x] 1.7 Loop end: `fail` → exit non-zero.
- [x] 1.8 Fetch-injection seam `PREAPPLY_ENTRYPOINT_FETCH` for test stubbing.

## Phase 2 — Wire into apply workflow (`.github/workflows/apply-web-platform-infra.yml`)

- [x] 2.1 Add `terraform show -json tfplan > tfplan.json` once in the "Terraform plan" step; destroy-guard jq reads that file.
- [x] 2.2 New separate "Pre-apply entrypoint gate" step AFTER "Terraform plan", BEFORE the MAIN "Terraform apply"; `working-directory: INFRA_DIR`; `env: DOPPLER_TOKEN`; `set -euo pipefail`; export `PREAPPLY_CF_TOKEN` from `CF_API_TOKEN_RULESETS`; run `--gate tfplan.json`. NO `[ack-destroy]` bypass.
- [x] 2.3 Record the dispatch-job / sibling-workflow exemption rationale (host/secret-scoped `-target`; transitivity toward deps).

## Phase 3 — Retrospective drift audit (`--audit`)

- [x] 3.1 `--audit` static: enumerate declared `cloudflare_ruleset`, classify zone/account, `-target` + in-state/import status.
- [x] 3.2 `--audit` live (read-only): control-probe; GET each entrypoint; report live rule counts. (Implemented; live enumeration is CI-only — not runnable at /work without creds.)
- [x] 3.3 Add guarded `entrypoint-audit` dispatch value + mutually-exclusive `if:`; own concurrency group; `permissions: contents: read, issues: write` (GitHub App token); no `terraform apply`.
- [ ] 3.4 Findings → single #6767 comment (system-of-record). MECHANISM shipped (entrypoint_audit job posts via App token); the actual post happens on the ship-time CI run.
- [ ] 3.5 Ship dispatches the audit in-session + blocks PR-ready on findings posted (NOT a post-merge checkbox). SHIP-PHASE action — owned by the orchestrator, not run at /work.
- [x] 3.6 Write `knowledge-base/engineering/operations/runbooks/cloudflare-whole-list-entrypoint-audit.md` (METHOD + static table + context; `## Results` link).

## Phase 4 — Tests + parity + CODEOWNERS

- [x] 4.1 `tests/scripts/test-preapply-entrypoint-gate.sh` — every branch (create-nonempty/404/control-non200/403/000/429/5xx/non-numeric/empty-token/malformed-json/account/unclassified-kind/replace-no-fire/import+steady-state-exempt/untargeted-fire/multi-row-aggregate/`--audit`), stubbed fetch, no live API.
- [x] 4.2 Wiring assertions (whitespace-normalized/independent-token greps; gate before MAIN apply pinned by name; no ack bypass).
- [x] 4.3 Parity test: FAIL if a dispatch `-target` gains a `cloudflare_ruleset` w/o gate; FAIL if a new `cloudflare_*` type is un-adjudicated (cross-ref destroy-guard class table).
- [x] 4.4 Synthesized fixtures: create (zone+account rows), create-untargeted, import, steady-state, replace.
- [x] 4.5 CODEOWNERS rows; wire test into `scripts/test-all.sh` (and/or infra-validation.yml).

## Phase 5 — ADR-135 + ADR-130 cross-note + C4 + docs

- [x] 5.1 ADR-135 (thin; re-verify ordinal at ship): Decision + Inclusion Principle + class-adjudication table + discriminator + control-probe/404-seam + iterate-all invariant + dispatch-job boundary; reference plan Alternatives (do not re-type).
- [x] 5.2 ADR-130 "see ADR-135" cross-note.
- [x] 5.3 C4: read all three `.c4`; confirm/add CI→cloudflare read edge; run c4 tests; cite the enumeration.
- [x] 5.4 Docs: plan/SKILL.md Sharp Edge (prose → gate); `seo-config-rules.tf` comment update.

## Verification / exit gate

- [x] `bash tests/scripts/test-preapply-entrypoint-gate.sh` green.
- [x] `test/seo-config-rules.test.ts` still green (adoption untouched).
- [x] c4 validation tests green.
- [x] All ACs in the plan's Pre-merge section satisfied.
