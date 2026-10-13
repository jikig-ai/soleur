---
title: "fix(ci): pin npm version in lockfile-sync gate so committed lockfile is reproducible across operator/CI/Docker"
issue: 4337
branch: feat-one-shot-lockfile-sync-4337
type: fix
lane: single-domain
date: 2026-05-22
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): pin npm version in lockfile-sync gate so committed lockfile is reproducible across operator/CI/Docker

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** Overview / Hypotheses / Files to Edit / Phase 1 / Phase 3 / Risks / Sharp Edges / Citations
**Verification gates executed:** Phase 4.6 (User-Brand Impact — PASS, threshold `none` with explicit non-sensitive-path scope-out reason); Phase 4.7 (Observability — PASS, all 5 fields populated, `discoverability_test.command` does not invoke `ssh`); Phase 4.8 (PAT-shaped variable halt — PASS, zero matches); Phase 4.5 (Network-outage deep-dive — N/A, no SSH/handshake keywords in plan).

### Live verification artifacts (executed at deepen time)

| Claim | Verification command | Result |
|---|---|---|
| Issue #4337 OPEN | `gh issue view 4337 --json state,title` | `OPEN`, title matches plan body |
| PR #4287 OPEN (discovery PR, downstream blocker) | `gh pr view 4287 --json state,title` | `OPEN`, "feat(supabase): mig 062 workspace_member_actions audit log (#4231)" |
| PR #4331 MERGED (regression introducer) | `gh pr view 4331 --json state,title` | `MERGED`, "feat(feature-flags): identity-aware Flagsmith with per-role targeting" |
| PR #4334 MERGED (hotfix attempt) | `gh pr view 4334 --json state,title` | `MERGED`, "fix(web-platform): sync package-lock.json with flagsmith-nodejs (PR #4331 hotfix)" |
| PR #4014 MERGED (prior same-class fix, operator-side workaround) | `gh pr view 4014 --json state,title` | `MERGED`, "fix(deps): regen package-lock.json with npm 10 to match CI shape" |
| Three consecutive `main` CI failures | `gh run list --branch main --workflow ci.yml --limit 5` | `cefea1e8`, `d8354607`, `4dbaa327` — all `failure` |
| Diff shape on failing CI run | `gh run view 26283770057 --log-failed` | Pure `+      "dev": true,` lines on optional transitive entries (`@emnapi/runtime`, `@img/sharp-*` darwin/linux/win32 variants) |
| `actions/setup-node@v4.4.0` has no `npm-version` input | `gh api /repos/actions/setup-node/contents/action.yml \| jq -r .content \| base64 -d \| grep -E '^  [a-z-]+:'` | Inputs: `node-version`, `node-version-file`, `architecture`, `check-latest`, `registry-url`, `scope`, `token`, `cache`, `package-manager-cache`, `cache-dependency-path`, `mirror`, `mirror-token`. **No `npm-version`.** |
| `npm@11` latest channel | `npm view npm@latest version` | `11.15.0` (channel active; floor pinned at major) |
| `npm@11` dist-tag exists | `npm view npm dist-tags --json \| jq '."latest"'` | `"11.15.0"` |
| Local repro: npm 10.9.8 diverges from committed lockfile | `cp lock; npx --yes npm@10.9.8 install --package-lock-only; diff` | 17 `+ "dev": true,` lines added (matches CI failure shape exactly) |
| Local repro: npm 11.15.0 matches committed lockfile | `cp lock; npx --yes npm@11.15.0 install --package-lock-only; diff \| wc -l` | `0` (byte-identical) |
| Docker `node:22-slim` ships npm 10.9.4 | `docker run --rm node:22-slim@<sha> npm --version` | `10.9.4` (proves Docker `npm ci` unaffected by gate fix — npm 10 tolerates npm 11 lockfile shape for install, only the regenerate-and-diff strict check trips) |
| `web-platform-build` job (npm ci) is GREEN on every failing run | `gh run view <id> --json jobs --jq '.jobs[] \| {name, conclusion}'` | `web-platform-build: success` on all 3 failed runs (`cefea1e8`, `d8354607`, `4dbaa327`); only `lockfile-sync` is red |
| `lockfile-sync` block is lines 137-157 | `sed -n '137,160p' .github/workflows/ci.yml \| wc -l` | 24 lines, matches plan citation |
| 4 cited AGENTS.md rule IDs are ACTIVE | `for id in hr-weigh-every-decision-against-target-user-impact wg-use-closes-n-in-pr-body-not-title-to hr-gdpr-gate-on-regulated-data-surfaces hr-observability-as-plan-quality-gate; do grep -qE "\[id: $id\]" AGENTS.md && echo OK; done` | 4/4 OK |
| Prior learning exists (`2026-04-03-lockfile-sync-ci-check-pattern.md`) | `git log --oneline -- knowledge-base/project/learnings/2026-04-03-lockfile-sync-ci-check-pattern.md` | Last edit `8a4f1d6d`, file exists |
| No precedent for `npm install -g` in any workflow | `grep -rnE "npm install -g " .github/workflows/` | zero hits — first usage of pattern (low-blast-radius scope) |
| Existing README.md exists, 64 lines, has setup section | `wc -l apps/web-platform/README.md && grep -nE '^##' apps/web-platform/README.md` | 64 lines, sections include `## Requirements`, `## Running locally` — README append-target identified |
| No PAT-shaped variables in plan | Phase 4.8 regex sweep | Zero matches |

### Key Improvements

1. **`actions/setup-node@v4.4.0` input schema verified live**, not paraphrased. Confirms `npm-version` is not a valid input — the `npm install -g npm@11` pattern is the only available pin mechanism (rules out a class of failed plan reviews that would suggest `with: npm-version: 11`).
2. **Negative reproduction codified.** Phase 0.1 and the Test Strategy now both contain the npm 10 repro that PROVES the gate's failure mode is real. Without this, the gate's value is hand-wavy.
3. **Docker-side confirmation.** Documented explicitly that `node:22-slim` ships npm 10.9.4 AND `npm ci` tolerates the npm 11 lockfile shape — this is what makes the fix one-sided (gate only, not Docker). A future operator reading the plan won't worry "does this break production deploy?" — the citation answers it.
4. **First-usage-of-`npm install -g` note.** Verified by grep that no other workflow uses this pattern. The single-job scope is intentional; do NOT generalize.
5. **README append-target validated.** `apps/web-platform/README.md` exists, is 64 lines, and has both `## Requirements` and `## Running locally` sections — Phase 3.2's `grep -nE '^#'` precondition is already satisfied; the new `## Lockfile note` will append cleanly.
6. **Two-recurrence framing.** Plan now explicitly identifies PR #4014 + this PR as the **same defect class**, making the case for codifying the pin in the workflow rather than repeating the operator-side workaround. This unblocks the "should we just do the operator workaround again?" objection at PR-review time.

### New Considerations Discovered

- **`actions/setup-node@v4.4.0` ships `package-manager-cache` input** (auto-caching when `package.json` declares a `packageManager`/`devEngines.packageManager`). The `lockfile-sync` job does NOT use `cache: npm`, so this auto-cache is inactive. But: if a future contributor adds `"packageManager": "npm@10.x"` to `apps/web-platform/package.json`, the auto-cache would activate AND would honor the `packageManager` pin. **This is a stronger long-term solution than the workflow-side `npm install -g npm@11`** because it pins the npm version at the `package.json` level (Corepack-style, but for npm). Out of scope for this PR (it would couple developer machines to the pin via Corepack), but recorded as a future-direction note in the learning Phase 4.4 will write.
- **GitHub-hosted runner's Node 22.x patch version drift is real and observed within a single hour.** Captured runs at the time of plan writing show Node 22.22.1 / 22.22.2 / 22.22.3 across three jobs on the SAME failing run (`4dbaa327`). This is normal — `actions/setup-node` honors `node-version: 22` as a satisfying-spec match and the tool-cache rotates as runners get refreshed. Confirms that pinning Node beyond the major (e.g., `node-version: 22.22.2`) would add maintenance burden without correctness gain.
- **The `latest-N` dist-tag enumeration** (`latest-1: 1.4.29`, `latest-3: 3.10.10`, `latest-4: 4.6.1`, `latest-5: 5.10.0`, `latest-6: 6.14.18`, `latest-7: 7.24.2`, `latest: 11.15.0`) confirms npm published a major-only floating tag pattern. **There is no `latest-10` or `latest-11`** at the npm registry — `npm@11` resolves via semver range, not a floating tag. The semver-range form is more robust against npm registry tag-management mistakes than a hypothetical `npm@latest-11` would be.

## Overview

The `lockfile-sync` CI gate has been red on `main` since `cefea1e8` (PR #4331, flagsmith adoption), and PR #4334's hotfix did not resolve it — three consecutive `main` runs (`cefea1e8`, `d8354607`, `4dbaa327`) failed. Every PR's auto-merge is blocked at this gate. This is the **second recurrence of the same defect class** (PR #4014 "regen package-lock.json with npm 10 to match CI shape" patched it once with an operator-side workaround; the defect has now re-surfaced because the workaround was not codified in the gate itself).

**Verified root cause** (reproduced locally on this worktree):

The committed `apps/web-platform/package-lock.json` is in **npm 11.x shape**: optional transitive packages (`@emnapi/runtime`, `@img/sharp-darwin-*`, `@img/sharp-linux-*`, `@img/sharp-linuxmusl-*`, `@img/sharp-win32-*`, `fsevents`) are emitted WITHOUT a `"dev": true` flag. CI runs `npm install --package-lock-only` under **npm 10.9.x** (the npm version bundled with `node:22.22.x` on the GitHub-hosted runner via `actions/setup-node@v4.4.0`), which **adds** `"dev": true` to those same entries on every regeneration. The diff is purely 17 `+      "dev": true,` lines on optional/dev-pulled transitive packages; no version, integrity, or `resolved` URL drift.

Reproduction performed at plan-write time on this worktree (Node 22.22.1, restored after):

```
$ npx --yes npm@10.9.8 install --package-lock-only   # adds 17 "dev": true lines
$ diff committed regen | wc -l → 34   (17 +<line> + 17 unified-diff scaffolding)
$ npx --yes npm@11.15.0 install --package-lock-only  # zero diff
$ diff committed regen | wc -l → 0
```

This proves: (a) the committed lockfile is the npm 11 shape; (b) CI's npm 10 will always disagree with it; (c) the issue is deterministic and version-keyed, not flake.

The fix is to **pin the npm version inside the `lockfile-sync` job to the version operators are expected to use locally**, then regenerate the committed lockfile under that pinned version, then add a body-of-job remediation hint that names the pinned version. The cheapest pin is `npm install -g npm@11` as the first step of the job — `actions/setup-node@v4` does not have a per-job `npm-version:` input, so `npm install -g` is the canonical pattern.

**Why npm 11 and not npm 10:** The committed lockfile is already in npm 11 shape (`d8354607` was generated by an operator-local `npm install --package-lock-only` on npm ≥ 11). Pinning to npm 11 in CI is a one-line gate change. Pinning to npm 10 would require regenerating the lockfile (operator-side) AND every contributor would need to remember to use npm 10. The npm 11 direction has lower coupling to operator environments: `bun add`-derived hotfixes (the PR #4334 pattern) tend to produce npm 11 output because `bun add` updates only `bun.lock`, leaving operators to run `npm install --package-lock-only` under whatever npm they have — modern Node installers (Node 23+, fresh Volta/asdf installs) ship npm 11.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "Diff appears to include platform-optional dependency entries (`fsevents`, `@emnapi/runtime`, OS-specific `@img/*` packages) that may resolve differently between local dev and the GitHub Linux runner depending on npm's optional-platform handling." | Confirmed via local repro: diff is purely 17 `+ "dev": true,` lines on optional/dev-pulled transitive packages. Cause is **npm 10 vs 11**, NOT optional-platform handling (CPU/OS arrays are stable). | Pin npm version; do NOT touch `--include=optional`. |
| "Consider pinning npm version explicitly in the CI workflow via `actions/setup-node`'s `npm-version` or installing a specific patch via `npm i -g npm@<version>`" | `actions/setup-node@v4.4.0` has no `npm-version` input (only `node-version`, `node-version-file`, `cache`, `registry-url`, etc. — checked at `49933ea` SHA). The `npm i -g npm@<version>` form is the only available mechanism. | Use `npm install -g npm@11` as the first step in the `lockfile-sync` job. |
| "Consider switching `lockfile-sync` to `npm ci --dry-run` (which fails loud on any drift rather than regenerating)" | `npm ci --dry-run` validates that `node_modules` would match the lockfile; it does NOT validate that `package-lock.json` matches `package.json`. The defect class this gate exists to catch (PR #4014, PR #4334) is `bun add`-updates-package.json-but-not-lockfile, which `npm ci --dry-run` would PASS on the stale lockfile because the stale lockfile is internally consistent. | Reject `npm ci --dry-run` substitution. Keep the regenerate-and-diff form; fix the npm-version skew underneath it. Document the rejection in Risks. |
| "Hotfix PR #4334 was intended to resolve this but did not" | PR #4334 ran `npm install --package-lock-only` locally on operator's npm 11.x and committed. The committed file was correct shape for npm 11, but CI runs npm 10 → diff. The hotfix did not fail; the CI gate failed because of the version skew the hotfix introduced. | Plan codifies the fix that PR #4334 needed but did not have. |
| "Every PR (mine: #4287) is blocked at the `lockfile-sync` gate" | Confirmed: the synthetic `test` aggregator is a separate gate, but `lockfile-sync` is a required check on branch-protection ruleset (per `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md:56` — Tier 2 correctness gate). | Critical to fix promptly; merge blocker for the whole repo. |

## Hypotheses

Single hypothesis, verified at plan-write time:

- **H1: npm version skew between operator/CI/Docker** — CI (`actions/setup-node` + `node-version: 22`) ships npm 10.9.x; operator-local npm is 11.x (when bun-add hotfixes are involved) or 10.x (bare Node install). Lockfile shape diverges on the `"dev": true` flag for optional transitive packages. **Status: CONFIRMED** (reproduced locally with both npm 10.9.8 and 11.15.0; diff is byte-for-byte the 17 lines CI reports).

Rejected:

- **H2: optional-platform handling (`--include=optional`)** — would change `os:`/`cpu:`/`libc:` arrays, not just `"dev": true`. The diff shape disagrees with this hypothesis.
- **H3: Different lockfileVersion** — both produce `"lockfileVersion": 3`. Not the cause.
- **H4: Cached `node_modules` interference** — `lockfile-sync` job has no cache step (`actions/setup-node@v4.4.0` is invoked without `cache: npm`); `--package-lock-only` does not write `node_modules`. Not the cause.

## User-Brand Impact

**If this lands broken, the user experiences:** Continued auto-merge failures across all PRs touching `main`; operators forced to admin-merge or manually re-trigger CI; queue of in-flight PRs (notably #4287) stalls.

**If this leaks, the user's data/workflow/money is exposed via:** No exposure path. This is a CI-strictness gate; the underlying `npm ci` in Docker (production deploy) is unaffected because npm ci tolerates the `"dev": true` flag difference (verified: `node:22-slim` ships npm 10.9.4 and `web-platform-build` job ran `npm ci` successfully against the committed npm-11-shape lockfile in every failed run — only `lockfile-sync` is red, not `web-platform-build`).

**Brand-survival threshold:** none. CI-internal gate; no user-facing surface. Scope-out: this change touches `.github/workflows/ci.yml` and `apps/web-platform/package-lock.json` — neither matches the canonical sensitive-path regex (no schema, no migration, no auth flow, no API route, no `.sql` file). The `package-lock.json` edit is a regeneration with npm-11 (no version drift), not a security-class edit. `threshold: none, reason: CI-strictness gate; no user-facing data surface; npm-version pin is hygiene, not a regulated-data-surface change.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (deterministic gate):** `lockfile-sync` job passes on this PR's CI run. Verification: `gh run view <PR-CI-id> --json jobs --jq '.jobs[] | select(.name == "lockfile-sync") | .conclusion'` returns `success`.
- [ ] **AC2 (npm version pinned in workflow):** `.github/workflows/ci.yml` `lockfile-sync` job contains a step that installs `npm@11` globally BEFORE the `Regenerate package-lock.json` step. Verification: `awk '/^  lockfile-sync:/,/^  [a-z][a-z-]*:/' .github/workflows/ci.yml | grep -c 'npm install -g npm@11'` returns `1` (exactly one match within the lockfile-sync block).
- [ ] **AC3 (npm version pin is exact):** The pin is `npm@11` (major-only), not `npm@latest` or `npm@11.x` or a wildcard. Verification: `grep -nE 'npm install -g npm@[0-9]+(\.[0-9]+){0,2}$' .github/workflows/ci.yml` returns at least one line, and the captured version starts with `11`.
- [ ] **AC4 (remediation hint names the pin):** The `::error::` message in the `Check lockfile sync` step names the pinned npm version so a contributor running `npm install --package-lock-only` locally under a non-matching version sees the cause. Verification: `grep -F 'npm@11' .github/workflows/ci.yml` returns ≥ 1 (in the `echo "::error"` line OR a nearby line referenced from it).
- [ ] **AC5 (committed lockfile is reproducible under the pinned npm version):** Running `npx --yes npm@11 install --package-lock-only` in `apps/web-platform/` produces a zero-byte diff against the committed lockfile. Verification command in PR description: `cp apps/web-platform/package-lock.json /tmp/before && (cd apps/web-platform && npx --yes npm@11 install --package-lock-only) && diff /tmp/before apps/web-platform/package-lock.json | wc -l` returns `0`.
- [ ] **AC6 (committed lockfile is the npm 11 shape, not npm 10):** The lockfile contains zero false-add lines from the npm 10 regenerator. Verification: spot-check that `@emnapi/runtime` entry does NOT contain `"dev": true` (it has `"optional": true` only). `jq '.packages["node_modules/@emnapi/runtime"] | has("dev")' apps/web-platform/package-lock.json` returns `false`.
- [ ] **AC7 (Docker build still passes):** `web-platform-build` job (which runs `npm ci`) passes on the PR's CI run. Verification: `gh run view <PR-CI-id> --json jobs --jq '.jobs[] | select(.name == "web-platform-build") | .conclusion'` returns `success`. This proves the npm 10 in `node:22-slim` Docker image still accepts the npm 11 lockfile (the `"dev": true` flag is non-load-bearing for `npm ci`, only for regenerate-and-diff).
- [ ] **AC8 (CONTRIBUTING / dev docs mention the pin):** A one-line note is added to `apps/web-platform/README.md` (or the closest existing dev-onboarding doc) directing contributors to use `npm@11` when regenerating the lockfile locally. Verification: `grep -F 'npm@11' apps/web-platform/README.md` returns ≥ 1.
- [ ] **AC9 (PR body uses `Closes #4337`):** Per `wg-use-closes-n-in-pr-body-not-title-to`. Verification: `gh pr view <N> --json body --jq '.body' | grep -E 'Closes #4337'` returns 1.
- [ ] **AC10 (no scope creep):** Diff touches exactly `.github/workflows/ci.yml`, `apps/web-platform/package-lock.json`, `apps/web-platform/README.md`, and the canonical knowledge-base files (plan + tasks + learning). Verification: `gh pr view <N> --json files --jq '.files | map(.path) | sort'` matches the expected set.

### Post-merge (operator)

- [ ] **AC11 (main is green):** First post-merge CI run on `main` shows `lockfile-sync: success`. Verification: `gh run list --branch main --workflow ci.yml --limit 1 --json conclusion,headSha --jq '.[0]'` returns `success`. Automation: `/soleur:ship` Phase 7 already polls this.
- [ ] **AC12 (issue closes):** Issue #4337 closes via `Closes #4337` keyword in PR body, fires at merge time. Verification: `gh issue view 4337 --json state --jq '.state'` returns `CLOSED`.
- [ ] **AC13 (downstream PR #4287 unblocks):** PR #4287 (cited in #4337 as the discovery PR) can pass `lockfile-sync` after a CI re-run. Verification: `gh pr view 4287 --json statusCheckRollup --jq '.statusCheckRollup[] | select(.name == "lockfile-sync") | .conclusion'` returns `SUCCESS` after `gh workflow run ci.yml --ref <4287-branch>`.

## Files to Edit

- `.github/workflows/ci.yml` — `lockfile-sync` job block (lines 137-157). Add a step (`Pin npm version`) before `Regenerate package-lock.json` that runs `npm install -g npm@11`. Update the `Check lockfile sync` step's `::error::` line to name the pinned version. Diff is ~3 added lines + 1 modified line.
- `apps/web-platform/package-lock.json` — Regenerated under npm 11 (already in npm 11 shape; running the regenerator should produce zero diff; if it produces a diff, commit the regeneration). The committed file at HEAD is already correct shape — this is a no-op regeneration the workflow verifies.
- `apps/web-platform/README.md` — Add a one-line "Lockfile note" pointing at npm 11 for `npm install --package-lock-only`. Mention the CI pin so contributors don't drift.
- `knowledge-base/project/plans/2026-05-22-fix-ci-lockfile-sync-npm-version-pin-plan.md` — this plan file.
- `knowledge-base/project/specs/feat-one-shot-lockfile-sync-4337/tasks.md` — generated by plan skill.
- `knowledge-base/project/learnings/<topic>.md` — capture the npm-version-pin lesson (filename: `npm-version-pin-required-for-lockfile-sync-gate.md`, date selected at write time per `2026-04-19-do-not-prescribe-exact-learning-filenames` learning).

## Files to Create

None beyond the knowledge-base artifacts above.

## Open Code-Review Overlap

Procedure: queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned file path through `jq -r --arg path "<file>" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'`.

Result: None. No open `code-review` issue touches `.github/workflows/ci.yml`, `apps/web-platform/package-lock.json`, or `apps/web-platform/README.md` in a way that overlaps with this plan's edit scope.

## Implementation Phases

### Phase 0 — Preconditions (one-line probes, ≤ 5 min)

0.1 **Verify reproduction in this worktree.** Already performed at plan-write time (results above). Re-run only if the worktree state changes:

```
cp apps/web-platform/package-lock.json /tmp/lock-before.json
(cd apps/web-platform && npx --yes npm@10.9.8 install --package-lock-only)
diff /tmp/lock-before.json apps/web-platform/package-lock.json | head -5   # expect 17 +"dev": true lines
cp /tmp/lock-before.json apps/web-platform/package-lock.json                 # restore
diff /tmp/lock-before.json apps/web-platform/package-lock.json | wc -l       # expect 0
```

0.2 **Confirm `actions/setup-node@v4.4.0` does not expose `npm-version`.** The action's input schema at SHA `49933ea` (pinned in `ci.yml:143`) lists only `node-version`, `node-version-file`, `architecture`, `check-latest`, `registry-url`, `scope`, `token`, `cache`, `cache-dependency-path`, `always-auth`, `mirror-url`, `mirror-license-url`. No `npm-version`. Confirmed at plan time.

0.3 **Confirm npm 11.x produces a stable lockfile against the committed one.** Already performed: `npx --yes npm@11.15.0 install --package-lock-only` → 0-byte diff. Re-verify if `package.json` has changed since 2026-05-22.

0.4 **Confirm `node:22-slim` Docker image's npm version.** Verified at plan time: `npm 10.9.4` (via `docker run --rm node:22-slim@<sha> npm --version`). The Docker `npm ci` runs under npm 10.9.4 against the committed npm 11 lockfile and succeeds — `web-platform-build` job is green on every failing run cited in #4337. This is load-bearing: it proves the fix is one-sided (gate only); Docker does not need a change.

### Phase 1 — Write the workflow edit (TDD: GREEN by direct verification on CI)

1.1 **Edit `.github/workflows/ci.yml` `lockfile-sync` block.** Insert a new step between `Setup Node.js` and `Regenerate package-lock.json`:

```yaml
      - name: Pin npm version
        # The lockfile shape diverges between npm 10 (ships with node:22.x on
        # the runner) and npm 11 (the version operators typically have locally
        # when `bun add` updates package.json without touching package-lock.json
        # and they run `npm install --package-lock-only` to sync). Pinning to
        # npm 11 here matches the committed lockfile's shape. See
        # knowledge-base/project/learnings/<date>-npm-version-pin-required-for-lockfile-sync-gate.md.
        run: npm install -g npm@11
```

1.2 **Update the `Check lockfile sync` error message** to name the pinned version (so a contributor running `npm install --package-lock-only` under a non-matching npm version sees the cause):

```yaml
      - name: Check lockfile sync
        run: |
          if ! git diff --exit-code apps/web-platform/package-lock.json; then
            echo "::error::package-lock.json is out of sync with package.json in apps/web-platform/."
            echo "::error::Run 'npx --yes npm@11 install --package-lock-only' in apps/web-platform/ and commit the updated package-lock.json. (CI pins npm@11 — using a different npm version locally will produce a divergent lockfile shape.)"
            exit 1
          fi
```

1.3 **Verify the workflow YAML parses.** `actionlint` is the canonical YAML+expression linter for GitHub Actions:

```
actionlint .github/workflows/ci.yml
```

If `actionlint` is not in PATH, fall back to `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'` for a YAML-only parse check (covers the structural class).

### Phase 2 — Confirm the committed lockfile is the npm 11 shape (no-op regen)

2.1 **Regenerate under npm 11; expect zero diff.** This phase is the no-op confirmation that the committed file is already correct shape:

```
cp apps/web-platform/package-lock.json /tmp/lock-pre-phase2.json
(cd apps/web-platform && npx --yes npm@11 install --package-lock-only)
diff /tmp/lock-pre-phase2.json apps/web-platform/package-lock.json | wc -l   # expect 0
```

If the diff is non-zero, the committed lockfile drifted since plan-write (likely a different operator pushed in the meantime). In that case, commit the regenerated file; do NOT revert to the prior state. The "npm 11 regenerated, byte-stable" property is what AC5 verifies on CI.

### Phase 3 — Update operator-facing docs

3.1 **Edit `apps/web-platform/README.md`** to add a "Lockfile note" subsection (after the existing setup instructions). Suggested copy:

```markdown
### Lockfile note

`apps/web-platform/package-lock.json` is regenerated by CI under **npm 11**.
If you run `npm install --package-lock-only` locally to sync the lockfile
after a `package.json` change (or a `bun add`), use:

    npx --yes npm@11 install --package-lock-only

Using a different npm version will produce a divergent lockfile shape (npm 10
emits `"dev": true` on optional transitive packages where npm 11 does not),
and the `lockfile-sync` CI gate will fail on the PR.
```

3.2 **Verify the README edit lands in a section that exists** (do not invent a new top-level heading if the current README has no setup section). `grep -nE '^#' apps/web-platform/README.md` first; if no setup section exists, append at end of file under a new `## Lockfile note` H2.

### Phase 4 — Validation

4.1 **Push, open PR, wait for CI.**

4.2 **AC1 verification** — confirm `lockfile-sync` job is green on the PR's CI run.

4.3 **AC7 verification** — confirm `web-platform-build` is still green (proves Docker `npm ci` unaffected).

4.4 **Capture session learning.** Write `knowledge-base/project/learnings/<YYYY-MM-DD>-npm-version-pin-required-for-lockfile-sync-gate.md` covering: why the gate's `npm install --package-lock-only` form is npm-version-sensitive; why `npm ci --dry-run` is NOT a substitute; the two-recurrence pattern (PR #4014 + this PR) as evidence that the operator-side workaround was insufficient.

## Test Strategy

- **No new unit tests.** This is a CI workflow edit; the gate's behavior is verified by the gate running on the PR.
- **No new e2e tests.** Out of scope.
- **Manual verification command (also encoded in AC5):**

  ```
  cp apps/web-platform/package-lock.json /tmp/before
  (cd apps/web-platform && npx --yes npm@11 install --package-lock-only)
  diff /tmp/before apps/web-platform/package-lock.json | wc -l   # MUST be 0
  ```

- **Negative reproduction (to prove the gate would catch a future drift):**

  ```
  cp apps/web-platform/package-lock.json /tmp/before
  (cd apps/web-platform && npx --yes npm@10.9.8 install --package-lock-only)
  diff /tmp/before apps/web-platform/package-lock.json | wc -l   # MUST be > 0
  cp /tmp/before apps/web-platform/package-lock.json             # restore
  ```

  This verifies that the gate would still fire if a future contributor regenerates under npm 10. CI is now pinned to npm 11; this manual probe shows what happens to operators who skip the README note.

## Observability

```yaml
liveness_signal:
  what: lockfile-sync job conclusion on main (and on PRs)
  cadence: every push/PR to apps/web-platform/package*.json (workflow trigger is on: pull_request and on: push to main, default-filter — every commit to main re-runs CI)
  alert_target: GitHub Actions UI; failure surfaces as a red required-check on PR (auto-merge blocks); ci/main-broken label on main breakage (existing convention)
  configured_in: .github/workflows/ci.yml lockfile-sync job
error_reporting:
  destination: GitHub Actions logs (gh run view <id> --log) + GitHub status check on PR
  fail_loud: yes — workflow exits 1 with annotated ::error:: lines naming the pinned npm version and the remediation command
failure_modes:
  - mode: package-lock.json drift (package.json changed but lockfile not regenerated)
    detection: regenerate-and-diff returns non-empty
    alert_route: PR check fails → auto-merge blocks
  - mode: lockfile generated by a non-pinned npm version (e.g., contributor on npm 10 or npm 12)
    detection: same — regenerate-and-diff returns non-empty
    alert_route: same; ::error:: message now names npm@11 as the canonical version
  - mode: npm 11.x ships a breaking lockfile-shape change in a future patch
    detection: this PR's job runs `npm install -g npm@11` (major pin); a npm 11.x patch shifting the shape would fail in CI on the next run after the upstream npm release; visible in `gh run list --branch main --workflow ci.yml`
    alert_route: same; remediation = tighten the pin to `npm@11.<minor>` and regenerate the committed lockfile
logs:
  where: GitHub Actions log retention (90 days by default for public repos; 90 days for this repo per current settings)
  retention: 90 days
discoverability_test:
  command: |
    gh run list --branch main --workflow ci.yml --limit 5 --json conclusion,headSha --jq '.[] | "\(.conclusion) \(.headSha[0:8])"'
  expected_output: |
    success <sha>
    success <sha>
    success <sha>
    success <sha>
    success <sha>
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure CI/infrastructure-tooling change. Per the 8-domain assessment from `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`:

- **Product (CPO):** No user-facing surface. NONE.
- **Legal (CLO):** No regulated-data surface. NONE.
- **Marketing (CMO):** No brand surface. NONE.
- **Operations (COO):** No vendor or hosting change. NONE.
- **Sales (CRO):** No funnel impact. NONE.
- **Finance (CFO):** No cost impact (CI minutes unchanged). NONE.
- **Support (CCO):** No user-facing change. NONE.
- **Engineering (CTO):** Yes — but this IS the engineering domain assessing itself; the entire plan is the engineering response. NONE additional.

## Infrastructure (IaC)

Skipped — pure workflow YAML edit on an existing CI file, no new infrastructure surface (no server, secret, vendor, persistent process, DNS record, TLS cert, or firewall rule introduced). Per Phase 2.8's "skip silently if the plan introduces no new infrastructure (pure code change against an already-provisioned surface)".

## GDPR / Compliance Gate

Skipped — canonical sensitive-path regex matches none of the edit targets (`.github/workflows/ci.yml`, `apps/web-platform/package-lock.json`, `apps/web-platform/README.md`, `knowledge-base/project/plans/`, `knowledge-base/project/specs/feat-*/tasks.md`, `knowledge-base/project/learnings/`). None of the (a)–(d) extended triggers fire either (no new LLM-bound processing, no `single-user incident` threshold, no new cron, no artifact-distribution surface).

## Risks

- **R1: npm 11.x ships a future patch with a different lockfile shape.** Mitigation: the major-only pin (`npm@11`) accepts patches; if a 11.x patch changes shape, CI breaks loudly and the fix is a one-line tightening to `npm@11.<minor>`. Probability low — npm's lockfile-shape changes are flagged as `lockfileVersion` bumps (3 → 4), not silent within-version drift. Live verification at plan time: `npm@11` currently resolves to `11.15.0`; the `latest` dist-tag at the npm registry IS `11.15.0` (no separate `latest-11` floating tag — semver range resolution is the contract).
- **R2: Docker's `node:22-slim` later ships npm 11.** Then Docker and CI would converge on the same npm version. No harm — the lockfile is already npm 11 shape.
- **R3: Operator runs `npm install --package-lock-only` under npm 10 (or npm 12), commits, opens PR.** The lockfile-sync gate fires, naming `npm@11` in the error. The contributor switches versions and re-pushes. This is the gate doing its job; not a regression. Mitigation = README note from Phase 3.
- **R4: `npx --yes npm@11` is slow on first run** (~5 s download). Negligible vs. CI wall-clock (~30 s for the regenerate step). Acceptable. NB: the workflow itself uses `npm install -g npm@11` (not `npx`); `npx` is only the operator-local recommendation in the README note (Phase 3.1) because it avoids polluting an operator's global npm install.
- **R5: `npm ci --dry-run` substitute (rejected).** As covered in the Research Reconciliation table: `npm ci --dry-run` validates lockfile-vs-node_modules consistency, NOT package.json-vs-lockfile consistency. The defect class this gate exists to catch is the latter (a `bun add` updates package.json without touching package-lock.json — the lockfile is INTERNALLY consistent but DOES NOT match package.json's new dep). `npm ci --dry-run` would pass on that stale lockfile. Keep the regenerate-and-diff form.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled.
- **npm version skew is a recurrence-class defect.** This is the **second** recurrence in 2 months (PR #4014 patched it; PR #4334 re-introduced it without codifying the pin in the gate). The pin in the workflow itself is the only durable fix — operator-side discipline (the README note) is necessary but not sufficient. The 2026-04-03 lockfile-sync learning's "no `.npmrc` or version skew concerns when both CI and Docker use the same Node version" statement is **now wrong** at npm scale; same Node version no longer implies same npm version when bun-add hotfixes and post-Node-23 contributors are in the mix. Update the learning at Phase 4.4.
- **Do NOT switch to `npm ci --dry-run`.** It does not catch the `bun add` defect class.
- **Do NOT add `cache: npm` to the `lockfile-sync` job's `actions/setup-node` step.** Caching defeats the regenerate-from-scratch property the gate depends on.
- **Do NOT introduce a `.nvmrc` or `.npmrc`-based pin without first checking** that none of the other workflows (`deploy-docs.yml`, `scheduled-realtime-probe.yml`, `scheduled-growth-execution.yml`, `scheduled-content-generator.yml`, `scheduled-seo-aeo-audit.yml` — all `npm ci` against this lockfile or the root lockfile) would regress on the change. The narrow `npm install -g npm@11` form in the single `lockfile-sync` job has zero blast radius.
- **The CI runner's Node patch version drifts** (observed Node 22.22.1, 22.22.2, 22.22.3 across the same hour of failing runs — three jobs on the same `4dbaa327` run picked up different patches from the tool cache). Pinning Node beyond `22` (the major) is unnecessary and would create maintenance burden. The npm pin is what matters.
- **Future direction: Corepack-style npm pin via `packageManager` field.** `actions/setup-node@v4.4.0` ships a `package-manager-cache` input that honors a top-level `"packageManager": "npm@<version>"` in `package.json`. Adding that field would pin npm at the package.json level (not just in CI) — stronger long-term solution than this PR's workflow-side pin. Out of scope here because it couples every contributor to Corepack semantics and would require a separate rollout (Corepack on, all contributors run `corepack enable`). The future PR can swap the workflow's `npm install -g npm@11` for the `packageManager`-field approach without breaking anything.
- **`npm@11` major-pin resolves via semver range, not dist-tag.** npm registry's `latest` dist-tag points to `11.15.0` (current); there is no `latest-11` floating tag. `npm install -g npm@11` resolves through the semver `^11.0.0`-like range automatically, picking up the highest 11.x at install time. Probability of a 11.x patch breaking the lockfile shape mid-window is low (covered in R1) but the gate would fail loudly if it ever happens.
- **Bump the existing learning too.** `knowledge-base/project/learnings/2026-04-03-lockfile-sync-ci-check-pattern.md` line 18 currently says "No `.npmrc` or version skew concerns when both CI and Docker use the same Node version." Edit at Phase 4.4 to add: "**Update 2026-05-22**: Wrong — same Node major does not imply same npm version once operators are on Node 23+ or use `bun add` hotfixes. Pin npm explicitly in the gate (`npm install -g npm@<major>`)."

## Citations (verified at plan-write AND deepen-pass time)

All citations are pinned to live `gh`, `npm view`, `git`, `docker`, and `grep` outputs. See the "Live verification artifacts" table in the Enhancement Summary for the canonical row-by-row table with command + result columns. Quick-reference list:

- `gh issue view 4337 --json state,title` → `OPEN`, title matches plan body
- `gh pr view 4287 --json state,title` → OPEN, "feat(supabase): mig 062 workspace_member_actions audit log (#4231)"
- `gh pr view 4331 --json state,title` → MERGED, "feat(feature-flags): identity-aware Flagsmith with per-role targeting" (regression introducer)
- `gh pr view 4334 --json state,title,files` → MERGED, "fix(web-platform): sync package-lock.json with flagsmith-nodejs (PR #4331 hotfix)" (hotfix that regenerated under npm 11 without pinning CI; touched only `apps/web-platform/package-lock.json`, +67/-18 lines)
- `gh pr view 4014 --json state,title` → MERGED, "fix(deps): regen package-lock.json with npm 10 to match CI shape" (prior same-class fix; operator-side `npx npm@10` workaround; this PR codifies the durable fix)
- `gh run list --branch main --workflow ci.yml --limit 5` → 3 consecutive failures on `cefea1e8`, `d8354607`, `4dbaa327`
- `gh run view 26283770057 --log-failed` → diff is `+      "dev": true,` on `@emnapi/runtime` + `@img/sharp-{darwin,linux,linuxmusl,win32}-*` + `fsevents` (transitive optional packages)
- `gh api /repos/actions/setup-node/contents/action.yml` (live, SHA `49933ea` = v4.4.0) → confirmed no `npm-version` input. Actual inputs: `node-version`, `node-version-file`, `architecture`, `check-latest`, `registry-url`, `scope`, `token`, `cache`, `package-manager-cache`, `cache-dependency-path`, `mirror`, `mirror-token`.
- `npm view npm@latest version` → `11.15.0`
- `npm view npm dist-tags --json` → `latest: 11.15.0`, `next-11: 11.15.0` (semver-range resolution path; no `latest-11` floating tag)
- `docker run --rm node:22-slim@sha256:4f77a690… npm --version` → `10.9.4` (proves Docker `npm ci` tolerates the npm 11 lockfile shape — gate fix is one-sided, no Docker-side change needed)
- Local reproduction on this worktree: `cp lock; (cd apps/web-platform && npx --yes npm@10.9.8 install --package-lock-only); diff` → 17 `+ "dev": true,` lines; same probe with `npm@11.15.0` → 0 diff. Lockfile restored to HEAD state after each probe.
- `grep -rnE "npm install -g " .github/workflows/` → 0 hits (no precedent; this PR introduces the pattern, scoped to a single job — low blast radius)
- AGENTS.md rule-ID verification (4 cited rules, 4/4 active): `hr-weigh-every-decision-against-target-user-impact`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-observability-as-plan-quality-gate`
- `gh label list --limit 200` → `bug` label exists; this plan does not prescribe any non-default labels.
