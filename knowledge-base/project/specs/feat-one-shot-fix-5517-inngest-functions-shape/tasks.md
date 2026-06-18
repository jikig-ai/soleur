---
issue: 5517
branch: feat-one-shot-fix-5517-inngest-functions-shape
lane: single-domain
plan: knowledge-base/project/plans/2026-06-18-fix-inngest-inventory-functions-shape-plan.md
---

# Tasks — fix(inngest): op=inventory /v1/functions shape correction (#5517)

## Phase 0 — Capture the REAL /v1/functions shape (BLOCKING; no-SSH)

- [ ] 0.1 Add a bounded raw-shape diagnostic to `inngest-inventory.sh` FATAL/stderr path
      (bytes → stderr/journald only, NOT success-path stdout — #5503 purity).
- [ ] 0.2 Ship that diagnostic commit; let it deliver via the infra-config push.
- [ ] 0.3 Trigger `op=inventory` (`gh workflow run cutover-inngest.yml -f op=inventory`); read
      the captured raw `/v1/functions` bytes from the `::error::` cause line / journald.
- [ ] 0.4 Capture `/health` 200 alongside (settle H1 vs H2 — healthy-server-returns-number).
- [ ] 0.5 Determine the real shape + paste the captured bytes into the PR body. Decide:
      REST-shape-correction (default) vs GraphQL fallback (requires its own /v0/gql schema-pin).

## Phase 1 — RED: failing test against the captured fixture

- [ ] 1.1 Land the captured shape as a fixture (inline `make_functions` rewrite or `fixtures/` file).
- [ ] 1.2 Add a test driving the corrected projection against the captured fixture; assert the
      correct `functions` value. Must FAIL against the current `:119` array projection.
- [ ] 1.3 Confirm Test 1 (#5503 purity) and Test 9 (fail-loud) still pass.

## Phase 2 — GREEN: correct projection + guard + contract

- [ ] 2.1 Update guard shape check `inngest-inventory.sh:111` (`type=="array"` → captured-shape check).
- [ ] 2.2 Update projection `:119` to the captured shape (names / count / unwrap / GraphQL-pinned).
- [ ] 2.3 Update header (`:8`, `:16-19`) + emitted-object contract + add `# verified: 2026-06-18`;
      remove stale "JSON array of registered functions" prose.
- [ ] 2.4 IF `functions` type changed: reconcile `cutover-inngest.yml:239` (`.functions | length`)
      and `:246` (diff block) in the SAME commit (AC8).
- [ ] 2.5 Run `bash apps/web-platform/infra/inngest-inventory.test.sh` → exit 0 (AC6).
- [ ] 2.6 `shellcheck apps/web-platform/infra/inngest-inventory.sh` clean (AC7).

## Phase 3 — REFACTOR + sibling cross-check

- [ ] 3.1 Fold the same shape correction into `inngest-wiped-volume-verify.sh:132-134` (the
      `type=="array" → length else 0` tolerated-zero → false `no_functions` abort on real shape).
- [ ] 3.2 Extend `inngest-wiped-volume-verify.test.sh` for the corrected shape.
- [ ] 3.3 Confirm FILE_MAP↔DEST_SPEC parity test needs NO count bump (no new/renamed delivered script).

## Phase 4 — Verify + ship

- [ ] 4.1 Full suite green for touched infra scripts.
- [ ] 4.2 PR body: `Ref #5517` (NOT Closes — see below); quote captured bytes; pre/post-merge AC split.
- [ ] 4.3 Post-merge (AC9): re-run `op=inventory` via `gh workflow run` + `gh run watch`; confirm
      `::notice::inventory: functions=<corrected>` with no FATAL. Then `gh issue close 5517` if clean.

> Use `Ref #5517` in the PR body if the AC9 confirmation is post-merge-operator-style; otherwise
> `Closes #5517` is fine since all behavioral ACs (AC1–AC8) are pre-merge and AC9 is an automatable
> re-run, not a manual gate.
