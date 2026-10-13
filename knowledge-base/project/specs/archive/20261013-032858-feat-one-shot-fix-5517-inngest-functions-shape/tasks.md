---
issue: 5517
branch: feat-one-shot-fix-5517-inngest-functions-shape
lane: single-domain
plan: knowledge-base/project/plans/2026-06-18-fix-inngest-inventory-functions-shape-plan.md
---

# Tasks — fix(inngest): op=inventory /v1/functions shape correction (#5517)

## Phase 0 — Capture the real functions shape (BLOCKING; no-SSH)

> deepen-plan research (2026-06-18): `GET /v1/functions` is an UNREGISTERED route in v1.19.4 (bare
> number = router fallback). GraphQL `functions: [Function!]` at `/v0/gql` EXISTS and is PREFERRED
> (reuses enumerate's eventsV2 machinery, no appName discovery). REST `/v1/apps/{appName}/functions`
> is the array fallback.

- [x] 0.1 Add a bounded raw-shape diagnostic ONLY on the `inngest-inventory.sh` FATAL/exit-1 path
      (novel stderr pattern — never success-path; #5503 purity prohibits success stderr).
- [x] 0.2 Ship that diagnostic commit; let it deliver via the infra-config push.
- [x] 0.3 Trigger `op=inventory` (`gh workflow run cutover-inngest.yml -f op=inventory`); read the
      captured raw bytes from the `::error::` cause line / journald.
- [x] 0.4 Live-probe `POST /v0/gql { functions { slug name triggers } }` (introspect the real
      `Function` field set) AND `/health` 200 alongside (settle H1 vs H2).
- [x] 0.5 Decide per the plan's decision tree: GraphQL `functions` (default) → REST
      `/v1/apps/{appName}/functions` → count-only. Paste captured bytes + `Function` fields into PR body;
      pin the GraphQL `functions` shape in `inngest-graphql-schema.md`.

## Phase 1 — RED: failing test against the captured fixture

- [x] 1.1 Land the captured shape as a fixture (inline `make_functions` rewrite or `fixtures/` file).
- [x] 1.2 Add a test driving the corrected projection against the captured fixture; assert the
      correct `functions` value. Must FAIL against the current `:119` array projection.
- [x] 1.3 Confirm Test 1 (#5503 purity) and Test 9 (fail-loud) still pass.

## Phase 2 — GREEN: correct projection + guard + contract

- [x] 2.1 Update guard shape check `inngest-inventory.sh:111` (`type=="array"` → captured-shape check).
- [x] 2.2 Re-point projection `:119` to the GraphQL `functions` query (default; mirror enumerate's
      eventsV2 fetch+jq) — or REST `/v1/apps/{appName}/functions` array / count-only per Phase 0.
      Pin the GraphQL `functions` + `Function` field set in `inngest-graphql-schema.md`.
- [x] 2.3 Update header (`:8`, `:16-19`) + emitted-object contract + add `# verified: 2026-06-18`;
      remove stale "JSON array of registered functions" prose.
- [x] 2.4 IF `functions` type changed: reconcile `cutover-inngest.yml:239` (`.functions | length`)
      and `:246` (diff block) in the SAME commit (AC8).
- [x] 2.5 Run `bash apps/web-platform/infra/inngest-inventory.test.sh` → exit 0 (AC6).
- [x] 2.6 `shellcheck apps/web-platform/infra/inngest-inventory.sh` clean (AC7).

## Phase 3 — REFACTOR + sibling cross-check

- [x] 3.1 Fold the same shape correction into `inngest-wiped-volume-verify.sh:132-134` (the
      `type=="array" → length else 0` tolerated-zero → false `no_functions` abort on real shape).
- [x] 3.2 Extend `inngest-wiped-volume-verify.test.sh` for the corrected shape.
- [x] 3.3 Confirm FILE_MAP↔DEST_SPEC parity test needs NO count bump (no new/renamed delivered script).

## Phase 4 — Verify + ship

- [x] 4.1 Full suite green for touched infra scripts.
- [ ] 4.2 PR body: `Ref #5517` (NOT Closes — see below); quote captured bytes; pre/post-merge AC split.
- [ ] 4.3 Post-merge (AC9): re-run `op=inventory` via `gh workflow run` + `gh run watch`; confirm
      `::notice::inventory: functions=<corrected>` with no FATAL. Then `gh issue close 5517` if clean.

> Use `Ref #5517` in the PR body if the AC9 confirmation is post-merge-operator-style; otherwise
> `Closes #5517` is fine since all behavioral ACs (AC1–AC8) are pre-merge and AC9 is an automatable
> re-run, not a manual gate.
