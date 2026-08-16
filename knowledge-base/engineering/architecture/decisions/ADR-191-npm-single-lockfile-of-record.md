# ADR-191 — npm is the single lockfile of record; bun is runtime and test-runner only

- **Status:** Accepted
- **Date:** 2026-08-16
- **Issue:** #7084
- **Supersedes in part:** ADR-079 (the `bun.lock`↔`package-lock.json` parity arm)

## Context

`apps/web-platform` carried two lockfiles for one dependency set:

- `package-lock.json` — what production installs from (`apps/web-platform/Dockerfile`:
  `RUN npm ci`, `RUN npm ci --omit=dev`);
- `bun.lock` — what CI's `test-webplat` and `e2e` shards installed from
  (`bun install --frozen-lockfile`).

Dependabot updates `package.json` and `package-lock.json`. It has no notion of `bun.lock`.
So the moment a bump changed a resolved version, `bun install --frozen-lockfile` failed
with `lockfile had changes, but lockfile is frozen`, failing the **required** `test` and
`e2e` checks. Every `apps/web-platform` Dependabot PR was born red.

The failure was also systematically misread. `lockfile-sync` stayed **green** throughout —
it regenerates `package-lock.json` under npm@11 and diffs, and never looks at `bun.lock` —
so the PR presented as "the dependency bump broke the tests" rather than "a second lockfile
is unsynced". Observed on all four web-platform PRs in the 2026-07-30 drain, with identical
failing sets. By 2026-08-16 the backlog was 39 open Dependabot alerts (20 high) and ten
stalled PRs, the oldest from 2026-08-03.

## Decision

**npm is the single lockfile of record. `bun.lock` is deleted. bun remains the test runner
and script runtime.**

Concretely:

- both `bun.lock` files are deleted, and `scripts/lint-dual-lockfile.sh` fails if one
  reappears anywhere in the tree;
- every install site runs `npm ci --ignore-scripts`, enforced by
  `scripts/lint-workflow-install-sites.sh`;
- `lockfile-sync` is extended to cover **all four** tracked `package-lock.json` directories
  (root, `apps/web-platform`, `plugins/soleur/skills/pencil-setup/scripts`, `spike`) and to
  invoke both guards, so no new required status check is created. Gating all four rather
  than the two carrying the most alerts matters because `pencil-setup/scripts` holds 9 of
  the 39 baseline alerts and is bumped here; all four were verified to regenerate
  byte-identically under `npm@11` before being gated, so none fails on its own introduction;
- the supply-chain release-age floor moves from `bunfig.toml` `minimumReleaseAge = 259200`
  (seconds) to `.npmrc` `min-release-age=3` (days) — the same 72 hours;
- both `bunfig.toml` files keep their `[test]` blocks byte-for-byte. Those are
  independently load-bearing for vitest/happy-dom isolation (#1469) and have nothing to do
  with installing.

### Why not the alternatives

**Option 3 — keep both lockfiles, add a parity gate that fails with "regenerate bun.lock".**
Rejected. It fails the acceptance bar: the Dependabot PR is still red and still needs a
human to regenerate a lockfile by hand. It converts an opaque failure into a legible one,
which is worth something, but the cost — a human step on every dependency bump forever — is
the thing #7084 exists to remove. It would also have shipped RED on day one, against drift
that already existed.

**Option 1 — a job that regenerates `bun.lock` on Dependabot branches and pushes.**
Rejected. Pushing to a Dependabot branch detaches it from Dependabot's own management, so
the remedy quietly breaks the mechanism it is servicing. It also adds machinery to sustain
a duplication rather than removing the duplication.

**Deleting `package-lock.json` instead, and standardizing on bun.** Rejected, and this is
the decisive asymmetry rather than a preference: **Dependabot security-scans only the npm
lockfile.** The evidence is in-repo and predates the change:
`knowledge-base/project/specs/feat-one-shot-7084-dependabot-bunlock-alert-drain/alerts-baseline.tsv`
captures all 39 alerts as they stood *while `bun.lock` still existed*, and not one names a
`bun.lock` manifest — 27 point at `apps/web-platform/package-lock.json`, 9 at
`plugins/soleur/skills/pencil-setup/scripts/package-lock.json`, 3 at the root. There is also
no `.github/dependabot.yml`, so these are dependency-graph-driven security updates rather
than a configured ecosystem list, which strengthens the inference. Dropping `bun.lock` costs zero alert coverage. Dropping `package-lock.json`
would eliminate it — the repository would stop receiving the alerts this work exists to
drain. `package-lock.json` is also what production installs from.

### Root is included

Converting the repo root as well *removed* mechanism rather than adding it. Had root stayed
on bun, this change would have needed a JSONC parser for `bun.lock`, a two-key-shape version
extractor, an allowlist of directories exempt from the guard, and a surgical `bun.lock`
resync procedure for the root bumps in Phase 3. All four dissolve.

## The root `.npmrc` exemption (measured, not assumed)

The release-age floor is applied in `apps/web-platform`,
`plugins/soleur/skills/pencil-setup/scripts`, and `spike` — **three** directories. The
repository root is deliberately exempt.

npm applies `min-release-age` to **exact pins**, not just to ranges. Measured against npm
11.12.1:

```
npm install -g likec4@1.50.0 --min-release-age=3650 --dry-run   → rc=1
  npm error code ETARGET
  npm error notarget No matching version found for likec4@1.50.0 with a date before …
npm install -g likec4@1.50.0 --min-release-age=3    --dry-run   → rc=0   (control)
```

Root-cwd commands carry global exact pins: `npm install -g likec4@1.50.0`,
`npm install -g "@anthropic-ai/claude-code@${CLI_VERSION}"`, and
`npm install --no-save playwright@1.60.0`. A root `.npmrc` would therefore fail on exactly
the PR that repins one of them to a freshly published release — which is what
`/soleur:model-launch-review` does on every Anthropic model launch. The floor would break
the flow it is least able to afford breaking, on the day it runs.

One file per directory is a necessity, not redundancy: npm reads `./.npmrc` from the
install cwd and does not traverse to a parent. Measured behaviorally — a parent floor of
3650 days made an install in the parent fail ETARGET and an install in its child succeed.
(`npm config get min-release-age` is **not** a valid probe for this: it returns `null` even
in the directory that owns the `.npmrc`, so it cannot distinguish "not inherited" from "not
visible", and read literally would prove the floor never works anywhere.)

The floor is load-bearing on `lockfile-sync`'s existing `npm@11` pin: npm 10.x ignores the
key silently, so a downgrade there disables the floor with no error.

**Recorded asymmetry the exemption creates.** `lockfile-sync` now runs
`npm install --package-lock-only` at the root as well as in the three floored directories,
and those are the only steps in the repo that *resolve* versions from the registry rather
than replay a lockfile. The root one is therefore unfloored, and this change also adds a
root `overrides` block with caret ranges (`js-yaml: ^4.3.1`, `brace-expansion: ^1.1.16`)
that that step resolves. The blast radius is bounded and the bound is why this is recorded
rather than closed: `--package-lock-only` executes no package code, and every root `npm ci`
carries `--ignore-scripts`. Flooring the root step alone would also desynchronise CI from a
local regeneration and fail the gate on its own introduction. Stated here so the exemption
is not read as covering more than the global-exact-pin case that motivates it.

## Consequences

**The acceptance bar.** A Dependabot-shaped bump to `apps/web-platform/package.json` now
reaches green required checks with no human lockfile regeneration.

**`--ignore-scripts` is behavior-preserving, and one part of it is a remediation.**
`apps/web-platform` declares no `trustedDependencies`, so bun already ran zero install
scripts; `npm ci --ignore-scripts` reproduces that exactly. The four pre-existing bare
`npm ci` sites are a different matter and are converted for a different reason: `ci.yml`
triggers on `pull_request`, a fork PR controls `apps/web-platform/package.json`, and
`web-platform-build` therefore already executes all ten `hasInstallScript` packages —
including `@sentry/cli`'s network binary download — on untrusted code. That is a live
arbitrary-execution and egress path today, which this change closes rather than introduces.

**The production Dockerfile keeps its bare `npm ci`** and is an explicit, asserted boundary
of Guard 2 — it builds trusted, already-merged code and needs its install scripts.

**ADR-079's parity arm is retired, its presence arm is not.** `sdk-bump-sandbox-gate.sh`
section 1 becomes PRESENCE. The `[[ -z "$pv" ]]` check must survive: section 2's bump
detection is `[[ -n "$base_v" && -n "$head_v" && … ]]`, which short-circuits to green on an
empty `head_v`, so the presence arm is the only remaining catch for an SDK package that
vanishes from the lockfile — the #5849 silent-green class that gate exists to close.
`lint-dual-lockfile.test.sh` row 8 asserts the arm still exists; the gate's own suite
asserts it still works.

**Tenant repositories.** `constraint-scaffold`'s emitted workflows are converted too. The
`constraint-gates` template has no choice — `parity.test.sh` byte-diffs it against this
repo's workflow — and the Stage A template follows for coherence, since one skill emitting
two different install commands would be incoherent. A bun-based tenant repo is a known
limitation of the emitted scaffold. It **will be** recorded in the post-merge follow-up
(spec task 6.5) rather than silently accepted — future tense deliberately, because that
issue does not exist at merge time and an ADR asserting a record that has not been made is
precisely the defect this sentence exists to avoid.

**`cq-before-pushing-package-json-changes` is left unedited.** Its clause regenerates both
lockfiles "if both exist", which is self-disarming now that only one does, so it is safe as
written. Editing a rule **body** is human-gated by the per-change hash-bound WORM ack of
AP-017 / ADR-092 and enforced by the always-run `rule-body-lint` required check; spending
that budget to delete a clause that can no longer fire is not worth it. Recorded here so the
choice is visible rather than an omission.

**CI caching changes shape.** All four hand-rolled `actions/cache` blocks are deleted rather
than re-pointed: `npm ci` deletes `node_modules` unconditionally, so caching it is worse
than useless. `setup-node`'s `cache: npm` caches the npm download cache — the part `npm ci`
can reuse — matching what `web-platform-build` already did.
