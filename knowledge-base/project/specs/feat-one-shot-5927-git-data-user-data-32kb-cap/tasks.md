# Tasks — fix(infra): gzip git-data cloud-init user_data under Hetzner 32KB cap (#5927)

Plan: `knowledge-base/project/plans/2026-07-03-fix-git-data-userdata-32kb-gzip-plan.md`
Lane: cross-domain (no spec.md → TR2 fail-closed default; substantively single-domain infra/CTO)
Brand-survival threshold: none (pre-provisioning infra; fail-closed at #5887 readiness gate)

## Phase 1 — Apply the fix (git-data.tf)

- [x] 1.1 Precondition: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` green; `terraform -chdir=apps/web-platform/infra fmt -check` clean.
- [x] 1.2 In `apps/web-platform/infra/git-data.tf`, wrap the `user_data` expression: `templatefile("${path.module}/cloud-init-git-data.yml", { … })` → `base64gzip(templatefile(...))`. Var map unchanged (5 `base64encode(file())` args intact). `base64gzip` is a TF core builtin — no provider add.
- [x] 1.3 Update the comment block above `user_data`: why gzip-first (no-docker; #5921 bake-and-extract does not transfer); decode contract (Hetzner rejects binary user-data → base64-decodes stored string via cloud-init `DataSourceHetzner.maybe_b64decode`, ≥20.3 → raw gzip → auto-gunzip → byte-identical `#cloud-config`); measured ~21.9 KB base64gzip vs 32,768 cap.
- [x] 1.4 DO NOT edit `cloud-init-git-data.yml` or any `git-data-*.sh` — they stay byte-identical.

## Phase 2 — Size verification

- [x] 2.1 `terraform validate` + `fmt -check` pass (via `infra-validation.yml`).
- [x] 2.2 Pre-merge byte estimate from the corrected node test (Phase 3), not `terraform console` (git-data volume/token refs are `known after apply` → console returns `(known after apply)`). Pin the estimate in the PR body + ADR; note byte-exact confirmation deferred to #5887's first `terraform plan`.

## Phase 3 — Size-guard test (CRITICAL: gzip REAL content, not placeholders)

- [x] 3.1 In `plugins/soleur/test/cloud-init-user-data-size.test.ts`, add a helper modeling the render with **real** `base64encode(file())` content for the 5 script args (read + base64 each file; keep the string), placeholder-substituting only small secrets/ids. Then `gzipSync(Buffer.from(render), { level: 9 })` (node:zlib) → base64 → length. Do NOT gzip the `"x".repeat(N)` render (collapses ~1000:1 → non-discriminating).
- [x] 3.2 Rewrite the git-data test: assert `b64gzipLen < HETZNER_CAP` AND `< GIT_DATA_BUDGET` (`28_000`, ≥6 KB headroom over ~21,929 B; loose for Go-vs-node zlib + jitter) AND `> GIT_DATA_FLOOR` (`10_000`). Inline comment per constant (mirror WEB_BUDGET/WEB_FLOOR). Delete `GIT_DATA_CEILING`.
- [x] 3.3 Update file-header comment (lines 18-22): git-data now UNDER cap via gzip-first (#5927); model gzips real script content.
- [x] 3.4 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` green (web unchanged + git-data new).
- [x] 3.5 Discrimination sanity-check: temporarily add a dummy `base64encode(file())`-shape arg to the modeled map; confirm modeled b64gzip size rises materially; remove.

## Phase 4 — ADR-080 amendment + C4

- [x] 4.1 Amend `ADR-080` scope-boundary note (lines 229-234): flip #5927 → resolved-via-`base64gzip()`; record mechanism + source-confirmed decode contract (`DataSourceHetzner.maybe_b64decode`, cloud-init ≥20.3) + measured estimate + #5887 empirical gate + security forward-note (gzip is encoding not encryption; future tfstate/plan-output secret scanners must decode first).
- [x] 4.2 Confirm no C4 change: re-read `model.c4`/`views.c4`/`spec.c4`; `gitDataStore` (model.c4:194) + `claude→gitDataStore` (model.c4:309) already modeled; no new external actor/system/store/edge (gzip needs no R2/GHCR). Cite the enumeration in the ADR. `.c4` files not touched → no need to run c4 render/syntax tests.

## Phase 5 — Verification / closure

- [ ] 5.1 PR body: `Ref #5927` (not `Closes`); pin the byte estimate; note decode-path is source-confirmed with #5887 first-provisioning as the empirical fail-closed gate.
- [ ] 5.2 Annotate #5887 that its first git-data provisioning is the decode-path confirmation gate.
- [ ] 5.3 Close #5927 with readiness-check evidence at #5887 provisioning (or at merge if the team accepts source-confirmed decode + treats #5887 as standing gate — operator choice).

## Acceptance Criteria (see plan for full AC1-AC9)

- Pre-merge: AC1 (base64gzip wrap, map unchanged), AC2 (template/scripts byte-identical), AC3 (node-test byte estimate < 32768), AC4 (test asserts real-content b64gzip < cap/budget, discrimination check passes), AC5 (web test unchanged), AC6 (validate/fmt), AC7 (ADR amended), AC8 (`Ref #5927`).
- Post-merge: AC9 (#5887 readiness check = decode confirmation).
