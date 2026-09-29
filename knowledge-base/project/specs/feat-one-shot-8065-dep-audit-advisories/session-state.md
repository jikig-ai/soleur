# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-09-29-chore-deps-resolve-root-js-yaml-and-liquidjs-audit-advisories-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-one-shot-8065-dep-audit-advisories/tasks.md`
- Status: plan written and committed on `feat-one-shot-8065-dep-audit-advisories` (draft PR #9223). Implementation (`soleur:work`) is next.

### Decisions

- **js-yaml needs NO lockfile bump.** PR #7970 (merged 2026-09-24, after
  #8065 was filed) already landed `4.3.2`/`3.15.2` — exactly the patched
  versions of GHSA-2883-xcg3-v3hh on both major lines. Today's
  `npm audit --json` on the root lockfile flags only `liquidjs`. The js-yaml
  residue is the **drain-guard ratchet**: `assert-dependabot-drain.py` floors
  still sit at `4.3.1`/`3.15.1`, below GHSA-2883's patched versions, so a
  regression to a still-vulnerable copy would pass silently (the
  2026-09-29 ratchet learning, #9198).
- **liquidjs target: 10.29.0** via `npx --yes npm@11 update liquidjs` —
  transitive-only (sole consumer `@11ty/eleventy@3.1.5` declares
  `^10.25.0`). Strictest `first_patched_version` across the three open
  advisories is `10.27.2`; no advisory covers `>= 10.27.2`. No
  `package.json`/`overrides` change on the primary path.
- **New drain-guard row:** `("root", "liquidjs", 10, "10.27.2")` +
  `WATCHED_PACKAGES` + `FLOOR_ANCHORS` entry; js-yaml anchors ratchet to
  `3.15.2`/`4.3.2` (keyed per (pkg,major) across manifests — web-platform
  rows move too). Test file gains a `("liquidjs", 10)` fixture entry and
  three new anchor-grep specs. `MIN_ROWS`/`MIN_RESOLVED` ratchet `20` -> `21` (floors track the row count; correction over the plan text).
- **No Dependabot alerts or PRs to supersede** — `dependabot/alerts` API
  returns `[]`; these advisories came through the npm-audit feed.
- **Degradation:** this plan ran inside a subagent with no Task-spawn
  capability; research, domain sweep, spec-flow, and review all ran inline
  (`Reviewed-Coverage: sequential-fallback`, recorded in the plan's Domain
  Review section).
- **`lane: single-domain`** — engineering-only change; no `spec.md` exists
  for this branch to carry a lane forward, so the value was assessed directly
  rather than defaulted.

### Errors

- None. `npm audit --json`, `gh api` advisory queries, and lockfile scans all
  ran clean on the worktree.

### Open questions

- None blocking. Two optional follow-ups the plan names but does not require:
  `apps/web-platform/test/eslint-config.test.ts` comment cites
  `"js-yaml": "^4.3.1"` (pre-existing stale comment, descriptive only — not
  edited to keep the diff off the web-platform tree); `@11ty/eleventy`
  `3.1.5→3.1.6` is available but out of scope (not needed for the
  advisories).

### Components Invoked

- `soleur:plan` (this session, subagent context — fan-outs run inline per
  the degradation note in the plan's Domain Review section)


## Work Phase

- Status: complete. `liquidjs` 10.27.0 → 10.29.0 in root `package-lock.json` (lockfile-only; `npx --yes npm@11 update liquidjs`).
- js-yaml needed no bump — PR #7970 already resolved 3.15.2/4.3.2 on all manifests; the drain-guard floors lagged (3.15.1/4.3.1) and were ratcheted here.
- `assert-dependabot-drain.py`: js-yaml floors → 3.15.2/4.3.2 in REQUIRED + FLOOR_ANCHORS; new `("root","liquidjs",10,"10.27.2")` row + anchor + WATCHED_PACKAGES entry; MIN_ROWS/MIN_RESOLVED 20→21.
- Test fixture: `("liquidjs", 10)` added to root fixture; anchor source-grep specs extended to js-yaml:3/4 + liquidjs:10; floor-message expectations 20→21.
- Verify: `npm ci --ignore-scripts` clean; `npm audit --json` → total 0; `npm run docs:build` green (66 files, liquidjs exercised); drain guard 21/21 OK; test.sh 27/27; floors probe OK; `npm@11 install --package-lock-only` idempotent; no `package.json` diff vs origin/main.
- `test-all.sh` battery deferred to the required `test` CI context per operator direction (precedent #9198).
