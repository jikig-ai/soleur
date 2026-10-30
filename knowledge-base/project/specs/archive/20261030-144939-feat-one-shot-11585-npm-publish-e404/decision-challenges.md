# Decision Challenges — feat-one-shot-11585-npm-publish-e404

Headless one-shot plan phase. Rulings recorded per
`technical-ruling-delegation.md`; the CTO role was executed inline (Devin CLI has
no Task/Agent tool) against `agents/engineering/cto.md`'s Rule interface.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 mechanism to restore the npm publish leg (issue's fork: claim the `@soleur` scope vs repoint the publish step at another registry vs remove the leg) | technical | Ruled by CTO agent, 2026-10-30: adopt npm OIDC trusted publishing (`id-token: write` + npm CLI >= 11.5.1 in `.github/workflows/npm-publish.yml`), dropping `NODE_AUTH_TOKEN` - the issue's premise is disproven: `GET https://registry.npmjs.org/@soleur%2fopencode` returns 200 with maintainer `deruelle` and ~60 published versions through 3.363.0 (2026-10-29T20:02Z), so the scope is claimed and E404-on-PUT is npm's authz-masking signal for a dead publish credential (`NPM_TOKEN` secret untouched since 2026-10-22T21:55Z; first E404 ~7.0 days later, consistent with a short-lived granular-token expiry). Trusted publishing removes the long-lived-token class that produced the outage, matches the repo's existing OIDC precedent (`id-token: write` in `reusable-release.yml`), and needs only declarative YAML plus a one-time npmjs.com trust entry. Rejected: claim the scope (premise false); repoint at GitHub Packages (breaks the documented `npx @soleur/opencode install` path — GH Packages requires auth even for public installs); remove the leg (abandons a live public channel with ~60 versions and docs references); rotate `NPM_TOKEN` (keeps the expiry/rotation class that caused the incident — recorded only as fallback if npm-side trusted-publisher configuration proves impossible). Dissent: if the npmjs.com trusted-publisher entry cannot be completed, fall back to rotating `NPM_TOKEN` with the longest permitted expiry and file a follow-up to revisit OIDC |
| T1a authorization to change the npm package's publisher trust configuration on npmjs.com and retire the `NPM_TOKEN` repo secret after the first green OIDC publish | operator (production-mutating) | Authorize the operator (npm maintainer `deruelle`) to add a GitHub Actions trusted publisher for package `@soleur/opencode` (org `jikig-ai`, repo `soleur`, workflow filename `npm-publish.yml`, no environment) at npmjs.com package settings, and to delete the `NPM_TOKEN` repo secret after the first successful OIDC publish. Split from T1 — third-party system, operator-owned credential surface; no Terraform provider or public API exists for npm trusted-publisher configuration |
| T2 whether to backfill versions 3.363.1-3.364.3 that were tagged on GitHub but never reached npm | technical | Ruled by CTO agent, 2026-10-30: do not backfill; publish only the resolved latest tag - npm has no sequential-version requirement, `npx @soleur/opencode` resolves `latest`, and the six skipped versions contain no distribution-critical delta the newest tag does not supersede; a one-off republish is recoverable by manual `npm publish` of a tag if a later need ever appears. Rejected: scripted backfill of each skipped tag (six extra publish runs for zero consumer-visible gain) |

## Notes

- Plan-time CPO assessment (inline, no Task tool): restoring a documented public
  install channel is product-neutral repair work; no new user-facing surface,
  flow, or claim is introduced. Brand-survival threshold declared in the plan:
  `aggregate pattern` (a stale package harms all new installers mildly rather
  than one user severely).
- Collision precheck reported PR #11598 — that is this pipeline's own auto-draft
  on the same branch, not a foreign duplicate. The foreign `test-all.sh` proc in
  `.worktrees/feat-11556-required-check-time` is unrelated to #11585.
