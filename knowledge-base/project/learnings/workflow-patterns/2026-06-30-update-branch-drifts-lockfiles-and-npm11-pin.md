# Learning: `gh pr update-branch` silently drifts both lockfiles; the `lockfile-sync` gate pins npm@11

## Problem

When draining a batch of open PRs, `gh pr update-branch <pr>` merges the current
`main` into a behind branch on the GitHub side. For any PR that touches
`apps/web-platform/package.json` (every Dependabot bump, plus feature branches
that changed deps), that server-side merge regularly leaves the **lockfiles out
of sync with the merged `package.json`** — and the drift is invisible until CI
fails, because `update-branch` does not run a package manager.

Two distinct gates fire on this, and they are NOT the same file or tool:

1. **`bun install --frozen-lockfile`** (the `test-webplat` / `e2e` install steps)
   fails with `error: lockfile had changes, but lockfile is frozen` when
   `apps/web-platform/bun.lock` no longer matches `package.json`. This reads as a
   *test* failure (the shard goes red) even though no test ran — the install
   step itself exited 1.

2. **`lockfile-sync`** (a dedicated CI job) regenerates
   `apps/web-platform/package-lock.json` and diffs it. It **pins npm@11**
   (`npm install -g npm@11` on Node 22, because `setup-node@v4.4.0` ships npm
   10.9.x). A `package-lock.json` regenerated with a *different* local npm major
   (e.g. the machine's npm 10.1.0) produces a divergent lockfile shape and fails
   this gate even when `package.json` is correct.

Concretely (PR-drain session 2026-06-30): #5490 (claude-code bump) and #5432
(otel/sentry multi-bump) both showed `test-webplat (1/2)`, `test-webplat (2/2)`,
`e2e`, `test` red after `update-branch`. The failures looked like real
breakage; the actual cause was bun.lock drift. After regenerating bun.lock, a
SECOND failure surfaced on #5432: `lockfile-sync` red because the local
`npm install --package-lock-only` ran under npm 10.1.0, not npm@11. #5432 also
hit a genuine merge conflict in BOTH lockfiles (main had advanced both).

## Solution

After any `update-branch` / `git merge origin/main` on a PR that touches
`apps/web-platform/package.json`, regenerate **both** lockfiles and verify
**both** gates locally before trusting CI:

```bash
cd apps/web-platform
bun install                                  # resyncs bun.lock to package.json
bun install --frozen-lockfile                # must exit 0 (the CI gate)
npx --yes npm@11 install --package-lock-only # MUST be npm@11, not local npm
git diff --stat apps/web-platform/bun.lock apps/web-platform/package-lock.json
```

- Commit whichever lockfiles changed. A clean dep-bump merge usually touches
  only `bun.lock` (~10 lines); a multi-package bump touches `package-lock.json`
  too (~hundreds of lines — that volume is expected, not a red flag).
- On a lockfile **merge conflict**, resolve by regenerating, not by hand-picking
  hunks: `git checkout --ours -- <lockfiles>` then re-run the two regen commands
  against the merged `package.json`.
- The `update-branch` itself can ALSO add a fresh merge commit on the remote
  after you fetched. If `git push` is rejected as non-fast-forward, the remote
  moved (your own earlier `update-branch`): `git fetch` + `git reset --hard
  origin/<branch>`, re-regenerate, push.

The existing rule `cq-before-pushing-package-json-changes` covers "regenerate
both lockfiles"; this learning adds the two things that bit during the drain:
the **npm@11 pin** (local-npm divergence is a silent `lockfile-sync` failure)
and the fact that `update-branch` — not a human edit — is a common drift source.

## Related

- `cq-before-pushing-package-json-changes` (AGENTS.rest.md) — now references the npm@11 pin.
- The strict-up-to-date branch protection that forces `update-branch` in the first place: see the merge-queue adoption learning (`2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`).
