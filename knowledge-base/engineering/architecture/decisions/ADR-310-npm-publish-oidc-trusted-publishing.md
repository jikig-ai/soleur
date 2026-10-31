---
title: npm Publish authenticates to registry.npmjs.org via OIDC trusted publishing, never a long-lived token
status: adopting
date: 2026-10-30
issue: 11585
supersedes: null
related: [10723]
related_adrs: [ADR-241]
---

# ADR-310: npm Publish authenticates to registry.npmjs.org via OIDC trusted publishing, never a long-lived token

## Context

The `npm Publish` leg of the release pipeline failed `npm error 404 Not Found -
PUT https://registry.npmjs.org/@soleur%2fopencode` on every merge to main for
~30 hours (six consecutive red runs starting 2026-10-29T22:26 UTC), while the
release leg succeeded and `latest` on the registry stalled at 3.363.0. The
issue's premise — an unclaimed `@soleur` scope — was disproven: the package
returns 200 with maintainer `deruelle` and ~60 published versions, and
publishing worked until the first failure with no workflow change in between.
E404 on PUT is npm's authz-masking signal: the `NPM_TOKEN` repo secret, last
updated 2026-10-22T21:55Z, died ~7.0 days after it was set — consistent with a
short-lived granular-token expiry or revocation.

`npx @soleur/opencode install` is the documented public install path for the
OpenCode harness (#10723), so the leg is a real delivery channel: every
installer got a stale package for the duration, loudly red in CI but silent to
the consumer.

## Decision

CI publishes `@soleur/opencode` via **npm OIDC trusted publishing** bound to
`jikig-ai/soleur` + `npm-publish.yml`. No long-lived npm credential exists in
CI: the publish job mints a short-lived OIDC token (`id-token: write`), npm
exchanges it for a publish credential scoped to this repo and workflow
filename, and the token dies with the job.

- `jobs.publish.permissions` gains `id-token: write` (GA since 2025-07-31;
  public repo, so provenance attestations attach free).
- `NODE_AUTH_TOKEN` env and `registry-url` `with:` are removed **together** —
  setup-node's `registry-url` writes `//registry.npmjs.org/:_authToken=…` into
  `.npmrc`, and a stale `_authToken` line can mask OIDC auth selection
  (npm/cli#8976).
- The job installs `npm@^11` explicitly: trusted publishing needs CLI >=
  11.5.1 and `npm trust` needs >= 11.15.0; Node 22's bundled npm is 10.x. An
  in-major pin (`^11`) is deterministic unlike `npm@latest` and covers both
  floors.
- The npm-side trust entry (package `@soleur/opencode`, repo `jikig-ai/soleur`,
  workflow filename `npm-publish.yml`, no environment) is created once by the
  maintainer via `npm trust github … --repo jikig-ai/soleur --allow-publish` —
  a third-party, operator-owned credential surface with no Terraform provider
  or public API, so it stays an operator step (decision-challenges row T1a).
- `NPM_TOKEN` is retired (repo secret deleted) after the first green OIDC
  publish; the leg no longer reads it.
- The wiring is pinned by `plugins/soleur/test/npm-publish-oidc.test.sh`:
  `id-token: write` present, no `*_AUTH_TOKEN`/`_authToken`/`registry-url`
  wiring, the `npm@^11` step present, `npm publish` retained — all asserted on
  `yaml.safe_load` fields, never grep, so comments cannot satisfy the guard.

Rejected: claiming the `@soleur` scope (premise false — it is already owned);
repointing at GitHub Packages (requires auth even for public installs, breaks
the documented `npx` path); removing the leg (abandons a live documented
channel); rotating `NPM_TOKEN` (restores the leg but keeps the
expiry/rotation class that caused the incident — retained only as fallback if
the npm-side trust entry proves impossible). No backfill of the six skipped
versions (3.363.1–3.364.3): npm has no sequential-version requirement and
`latest` moves to the newest tag.

## Consequences

- The credential-expiry failure class is deleted, not rotated: there is no
  storable, leakable publish token, and a token minted elsewhere cannot publish
  the package once `NPM_TOKEN` is retired (publish identity is
  repo+workflow-bound).
- **Ordering is fail-safe:** the YAML can merge before the trust entry exists;
  the leg keeps failing E404 with a printed classification hint naming the
  trusted-publisher entry to check, until the maintainer runs `npm trust
  github`. First green publish is the end-to-end proof (acceptance criterion
  AC-7 in the feature plan); this ADR flips `adopting` → `accepted` when that
  run is observed.
- `npm install -g npm@^11` adds ~10–15 s per publish run; accepted for
  determinism over trusting the runner image's bundled npm.
- Detection stays loud-by-construction: a red `npm Publish` run + the
  classification hint in the job log is the contract; a dedicated dead-leg
  monitor was considered and cut (triage latency, not missing signal).

## Amendment 2026-10-31

The failure signature is not only `E404`. With the OIDC wiring in place and no matching
trusted-publisher entry, npm swallows the exchange failure at verbose log level and dies
`ENEEDAUTH`. The `npm Publish` job now runs a failure-only step that replays the exchange
and prints one `NPM_OIDC_VERDICT=` line with the values the entry must carry; the leg
stays red until the owner step lands (no soft-skip). See
`knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`.
Status stays `adopting`.
