# Tasks — feat-one-shot-11585-npm-publish-e404

Plan: `knowledge-base/project/plans/2026-10-30-fix-npm-publish-e404-plan.md`
Issue: #11585 (Closes #11585 in PR body)

## Phase 1 — Setup

- [x] 1.1 Confirm the evidence baseline still holds: `curl -s -o /dev/null -w "%{http_code}" "https://registry.npmjs.org/@soleur%2fopencode"` prints `200`, and `gh run list --workflow npm-publish.yml -L 1 --json conclusion` shows the leg still red (premise re-check before editing).

## Phase 2 — Core Implementation

- [x] 2.1 Edit `.github/workflows/npm-publish.yml`:
  - [x] 2.1.1 Add `id-token: write` to `jobs.publish.permissions` (keep `contents: read`).
  - [x] 2.1.2 Remove `registry-url: 'https://registry.npmjs.org'` from `Setup Node` (drops the `.npmrc` `_authToken` line so OIDC auth selection is unmasked).
  - [x] 2.1.3 Remove `NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}` from the publish step `env:`.
  - [x] 2.1.4 Insert `npm install -g npm@^11` before `npm publish` (CLI >= 11.5.1 floor for trusted publishing; npm@^11 pin, not npm@latest).
  - [x] 2.1.5 Wrap `npm publish --access public --ignore-scripts` in a failure arm printing the E404 classification hint (verify the npm trusted-publisher entry for `jikig-ai/soleur` + `npm-publish.yml`) then `exit 1`.
- [x] 2.2 Create `plugins/soleur/test/npm-publish-oidc.test.sh` — parsed-YAML wiring guard per Guard Contract (assert `jobs.publish.permissions['id-token'] == 'write'`; no step env carries `NODE_AUTH_TOKEN`/`_authToken`; the `npm install -g npm@^11` step exists; `npm publish` invocation retained; vacuous-job-dispatch fails RED). Convention: assert on `yaml.safe_load` fields, never grep.
- [x] 2.3 Create `knowledge-base/engineering/architecture/decisions/ADR-310-npm-publish-oidc-trusted-publishing.md` (provisional ordinal — re-verify next-free ADR against `origin/*` refs immediately before merge; on collision renumber and `grep -rn 'ADR-310' knowledge-base/project/{plans,specs}/feat-one-shot-11585-npm-publish-e404/` + this plan to sweep the old ordinal in the same edit). Status `adopting`; decision: publish via OIDC trusted publishing bound to `jikig-ai/soleur` + `npm-publish.yml`; `NPM_TOKEN` retired after first green publish; flips to `accepted` when AC-7 is observed.
- [x] 2.4 Edit `knowledge-base/engineering/architecture/diagrams/model.c4`: add `npmRegistry = system "npm registry (npmjs.org)"` `#external` + `github -> npmRegistry` edge describing the OIDC publish channel (note the consumer-side install edge waits on the recorded OpenCode-harness `DRIFT (2026-10-25)` item).
- [x] 2.5 Edit `knowledge-base/engineering/architecture/diagrams/views.c4`: add `npmRegistry` to the `context` and `containers` view `include` lists (both endpoints must be listed for the edge to render — #7332 rule).
- [x] 2.6 Run `bash scripts/regenerate-c4-model.sh` to regenerate `model.likec4.json` (c4-model-freshness gate).

## Phase 3 — Testing & Verification

- [x] 3.1 `bash plugins/soleur/test/npm-publish-oidc.test.sh` — green; drive each Guard-1 mutation-matrix row RED/PASS as declared.
- [x] 3.2 `bun test apps/web-platform/test/c4-code-syntax.test.ts apps/web-platform/test/c4-render.test.ts` — green.
- [x] 3.3 `bash scripts/test-all.sh` (or the affected-subset runner) — green including the new registered test.
- [x] 3.4 markdownlint clean on all edited/created docs.

## Phase 4 — Operator + End-to-End (post-merge)

- [ ] 4.1 (operator, npm maintainer `deruelle`, npm >= 11.15.0, 2FA on the account, interactive `npm login` — `npm trust` rejects granular tokens with bypass-2FA) `npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish`; verify `npm trust list @soleur/opencode` shows the entry.
- [ ] 4.2 `gh workflow run npm-publish.yml` on main; run concludes `success`.
- [ ] 4.3 `npm view @soleur/opencode version` prints the newest `v*` tag's version.
- [ ] 4.4 (operator) Delete `NPM_TOKEN` repo secret after the first green OIDC publish (or record the deferral in the PR body).
