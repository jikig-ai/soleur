<!-- iac-routing-ack: plan-phase-2-8-reviewed (lockfile-only change; introduces no infrastructure) -->
---
title: "fix(security): remediate 9 Dependabot alerts — fast-uri + ip-address lockfile bumps"
date: 2026-09-29
slug: fix-dependabot-fast-uri-ip-address-alerts
branch: feat-one-shot-dependabot-alerts
type: fix
lane: single-domain
brand_survival_threshold: none
labels: [type/security, dependencies]
status: planned
---

# fix(security): Remediate 9 Dependabot alerts — fast-uri + ip-address lockfile bumps 🔒

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** Observability (Check-10-compliant probe), Research
Insights (verified citations + assert-floors snippet), Implementation Phases
(concrete npm@11 commands + verified-integrity fallback), Acceptance Criteria.
**Verification method:** direct `gh api` + npm-registry + repo-grep probes run
inline — this pipeline context cannot spawn Task sub-agents, so the deepen-pass
fan-out (Phases 2–5) ran as sequential in-process verification against the same
sources; the mechanical halt gates (4.6 User-Brand, 4.7 Observability, 4.8 PAT,
4.9 wireframe, 4.10 Encryption, 4.11 Guard Contract) were each evaluated
explicitly (see Disposition below).

### Key Improvements (grounded, all verified this pass)

1. **All 9 alerts re-verified live** against the Dependabot API with per-alert
   numbers, GHSA ids, vulnerable ranges, and `first_patched_version` — the task
   framing's "5 high / 4 moderate" confirmed exactly (205–208 + 235 fast-uri
   HIGH; 233–234 + 237–238 ip-address MEDIUM).
2. **Both packages proven transitive** — absent from every `package.json`;
   each lockfile carries exactly ONE deduped node (no nested copies), so a
   plain `npm@11 update` reaches them and no `overrides` dedup is needed.
3. **`bun.lock` parity eliminated from scope** — `git ls-files` shows zero
   `bun.lock`; ADR-191 (`ADR-191-npm-single-lockfile-of-record.md`) retired it
   and `scripts/lint-dual-lockfile.sh` guards against reintroduction. The
   2026-07-18 precedent plan's bun phases are obsolete.
4. **Discoverability probe corrected to the Check-10 allowlist** — the
   precedent plan's `gh api` command uses a non-allowlisted verb; this plan's
   `discoverability_test.command` is a `node -e` assert-floors probe over the
   two lockfiles (verified live: prints `FAIL 3` on the current vulnerable
   tree, `OK` post-fix). The `gh api` alert-count query is retained as the
   AC/post-merge confirmation, outside Check 10.
5. **Placeholder-token hazard removed** — `liveness_signal` sub-fields no
   longer lead with `N/A`, which deepen-plan Phase 4.7's anchored placeholder
   regex would reject.

### New Considerations Discovered

- **fast-uri's npm `latest` is 4.2.1 — out of range.** Every consumer declares
  `^3.0.1`, so the correct landing is `3.1.8` (what Dependabot PR #9192
  resolves); a naive "bump to latest" would fail or force an override.
- **`npm update` can silently no-op on transitive/peer copies**
  (2026-04-07 learning), and the `ip-address` target is a `peer: true` entry — hence
  the Phase-4 assert-floors gate (not the command's exit code) is the proof,
  with a surgical 3-field edit fallback carrying pre-verified integrity hashes.
- **Supersession beats merging the Dependabot PRs** — #9191+#9192 cover only
  2 of the 3 manifest/package pairs; merging them still requires a third PR for
  web-platform `ip-address`. One PR replicating all three bumps closes all 9
  alerts in one merge, and Dependabot auto-closes its superseded PRs once the
  alerts resolve.

### Deepen-gate dispositions

- 4.6 User-Brand Impact: **pass** (threshold `none` + reason bullet; neither
  lockfile matches the sensitive-path regex).
- 4.7 Observability: **pass** (5 fields populated; probe verb `node`
  allowlisted; sub-second runtime; literal `expected_output`).
- 4.8 PAT sweep: **pass** (zero hits).
- 4.9 UI wireframe / 4.10 Encryption / 4.11 Guard Contract / 4.5 network /
  4.55 downtime: **not triggered** (no UI, store, guard, SSH, or
  downtime-inducing change).
- Precedent-diff (4.4): precedent exists and is followed —
  `plugins/soleur/skills/work/references/work-lockfile-bumps.md` post-ADR-191
  header + plan `2026-07-18-fix-dependabot-undici-jsyaml-lockfile-bumps-plan.md`.

## Overview

Nine open Dependabot alerts on `main` (alert numbers 205–208, 233–235, 237–238,
verified live via `gh api repos/:owner/:repo/dependabot/alerts?state=open` on
2026-09-29) are all **transitive** npm dependencies across **two** tracked
lockfiles. Remediation is **lockfile-only** — every patched version is reachable
inside the existing declared ranges, so **no `package.json` edit is required**.
Deliver ONE security PR labeled `type/security` + `dependencies`, superseding
open Dependabot PRs #9191 and #9192.

Two packages, resolved to their in-range patched versions:

| Package | Manifest | Resolved node | Current | Floor (`first_patched_version`) | Target | Parent chain |
|---|---|---|---|---|---|---|
| `fast-uri` | `apps/web-platform/package-lock.json` | `node_modules/fast-uri` (single deduped copy) | `3.1.5` | `3.1.7` | **3.1.8** (latest 3.x; 4.2.1 is out of `^3.0.1`) | `ajv@8.x` (`"fast-uri": "^3.0.1"`, `peer: true`) via `@modelcontextprotocol/sdk`, `ajv-formats`, `dependency-cruiser`, `schema-utils` |
| `ip-address` | `apps/web-platform/package-lock.json` | `node_modules/ip-address` (single copy) | `10.5.0` | `10.5.1` | **10.7.2** (latest 10.x) | `express-rate-limit@8.5.2` (`"ip-address": "^10.2.0"`, `peer: true`) |
| `ip-address` | `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` | `node_modules/ip-address` (single copy) | `10.5.0` | `10.5.1` | **10.7.2** | `express-rate-limit@8.5.1` (`^10.2.0`) via `@modelcontextprotocol/sdk` |

The 9 alerts map as: 5× HIGH `fast-uri` in `apps/web-platform` — alerts **205**
(`GHSA-jqff-g426-hqxp`, `>=3.0.0,<3.1.6`), **206** (`GHSA-fph4-wmhf-6fwf`,
`>=3.1.2,<3.1.6`), **207** (`GHSA-f65p-4m7j-42xc`, `>=3.0.0,<3.1.6`), **208**
(`GHSA-5jgf-p345-68v8`, `>=3.1.3,<3.1.6`), **235** (`GHSA-qw65-cvwx-89v3`,
`>=3.0.0,<3.1.7`); 2× MEDIUM `ip-address` in `apps/web-platform` — alerts **233**
(`GHSA-2vr4-cq9g-pvrc`, `>=10.2.0,<=10.5.0`) and **234** (`GHSA-rpw4-54j3-4h4q`,
`<=10.5.0`)
(SSRF/trust-boundary bypass: `isLinkLocal` range + NAT64 classifier); 2× MEDIUM
`ip-address` in `pencil-setup/scripts` — alerts **237** and **238**, same GHSAs.

A single bump to `fast-uri@3.1.8` satisfies all five fast-uri ranges (3.1.8 ≥
3.1.7 covers the strictest); a single bump to `ip-address@10.7.2` per manifest
satisfies both ip-address alerts in each.

### Premise Validation (Phase 0.6)

- **Alerts live-verified** (2026-09-29): exactly 9 open — 5 high `fast-uri` +
  4 medium `ip-address` — matching the task framing (5 high / 4 moderate).
- **Patched versions exist on npm:** `fast-uri@3.1.8` (integrity
  `sha512-GZMtZUTN…ZfMg==`) and `ip-address@10.7.2` (integrity
  `sha512-7H/2gFSI…8U7w==`) verified via `npm view`.
- **Both packages are transitive** — absent from `apps/web-platform/package.json`,
  `plugins/soleur/skills/pencil-setup/scripts/package.json`, and root
  `package.json` (`grep '"fast-uri"\|"ip-address"'` → no hits).
- **Open Dependabot PRs confirmed:** #9191 (`ip-address 10.5.0 → 10.7.2`,
  pencil-setup manifest, OPEN) and #9192 (`fast-uri 3.1.5 → 3.1.8`,
  web-platform, OPEN). No open PR covers `ip-address` in web-platform.
- **Adjacent issues confirmed OPEN and out of scope:** #8065 (js-yaml/liquidjs,
  different packages), #8857 (CodeQL SSRF — code-level; the dep bump does not
  resolve it).
- **Repo drift vs. prior art verified:** `bun.lock` no longer exists anywhere in
  the tree (`git ls-files | grep bun.lock` → zero; retired by ADR-191, guarded by
  `scripts/lint-dual-lockfile.sh`). The bun-parity phases in the 2026-07-18
  precedent plan are inapplicable.

## Research Reconciliation — Spec vs. Codebase

| Task framing | Codebase reality (verified) | Plan response |
|---|---|---|
| "both `bun.lock` and `package-lock.json` must be regenerated if both exist" | Only `package-lock.json` exists. `bun.lock` was retired repo-wide (ADR-191 / #7084); `lint-dual-lockfile.sh` fails CI if one reappears, and `work-lockfile-bumps.md`'s header now prescribes `npx --yes npm@11 update <pkg>` + `npm ci --ignore-scripts` for transitive bumps. | npm@11-only path; no bun step anywhere. |
| "4 medium ip-address alerts; NO open PR covers the web-platform manifest" | Confirmed — Dependabot opened #9191 for pencil-setup only. `apps/web-platform` `ip-address@10.5.0` has no open PR. | This PR replicates #9191's bump in pencil-setup AND adds the uncovered web-platform ip-address bump. |
| "fast-uri vulnerable ranges `<3.1.6` and `<3.1.7`; patched `>=3.1.7`" | Live API shows 5 alerts: four `<3.1.6` variants + one `<3.1.7`. npm latest is `4.2.1` — **out of range** for `ajv`'s `^3.0.1`. | Target `3.1.8` (latest 3.x), identical to Dependabot PR #9192's resolution. |

## Property List / Cut List (Phase 0.6b)

**Property:** the default-branch dependency graph resolves **no** `fast-uri <
3.1.7` and **no** `ip-address <= 10.5.0` in any tracked `package-lock.json` —
which auto-dismisses all 9 alerts on Dependabot's next rescan.

**Mechanisms evaluated:**

| Mechanism | Property bought | Disposition |
|---|---|---|
| Merge PRs #9191 + #9192, then a third PR for web-platform `ip-address` | Covers all 9 alerts | **Rejected** — three merge cycles vs one; still needs a hand-rolled PR for the uncovered manifest; Dependabot PRs carry rebase/drift risk. |
| **One PR replicating both Dependabot bumps + the uncovered bump** (chosen) | Covers all 9 alerts atomically | **Adopted** — Dependabot auto-closes its PRs when the alerts resolve; net churn is one PR, one CI run. |
| `overrides` floors in each `package.json` | Same, plus a durable floor | **Fallback only** — each lockfile holds a single deduped node (no nested copies to force), so an override buys nothing `npm update` doesn't; overrides persist and need future cleanup. Kept as the documented fallback if `npm update` cannot reach the `peer: true` copies. |

**Cut list:** `bun.lock` regeneration (mechanism retired — ADR-191, guarded by
`lint-dual-lockfile.sh`); new CI guard (existing `lockfile-sync` job already
covers **all four** lockfile dirs — `ci.yml` regenerates and diffs
apps/web-platform, root, pencil-setup/scripts, and spike); ADR/C4 (a dependency
bump makes no architectural decision); Observability infra (no runtime surface —
section kept for schema completeness per Phase 2.9 because
`plugins/*/scripts/` is in the trigger set).

## Research Insights

- **Authority for the mechanism:**
  `plugins/soleur/skills/work/references/work-lockfile-bumps.md` — post-ADR-191
  header prescribes `npx --yes npm@11 update <pkg>` for transitive-only bumps in
  this repo. Validation: `npm ci --ignore-scripts`.
- **CI gate:** `.github/workflows/ci.yml` `lockfile-sync` job pins `npm@11`
  (`npm install -g npm@11`), regenerates `package-lock.json` in **all four**
  dirs (apps/web-platform, root, pencil-setup/scripts, spike), then
  `git diff --exit-code`s them. A lockfile written by any other npm major fails
  on shape drift. `cq-before-pushing-package-json-changes` pins the same
  regeneration command.
- **Institutional learnings:**
  `2026-04-07-npm-transitive-dep-security-update-mechanics.md` (`npm update` once
  silently no-op'd on a transitive dep — so Phase 4 below includes a hard
  version assertion, and a surgical-edit fallback is documented);
  `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md` (npm rewrites
  lockfile `name` when `package.json` lacks one — **N/A here**: all three
  manifests declare `name`); `2026-07-18` precedent plan
  (`plans/2026-07-18-fix-dependabot-undici-jsyaml-lockfile-bumps-plan.md`) —
  same shape, same gate set.
- **Peer-dep note:** `ip-address` resolves as a `peer: true` entry in
  `apps/web-platform/package-lock.json` (express-rate-limit peer chain);
  `fast-uri` is a plain transitive copy (ajv `^3.0.1`). `npm update <pkg>`
  updates a named package anywhere in the tree; the Phase 4 assertion is what
  proves it.
- **Labels verified:** `type/security` and `dependencies` both exist
  (`gh label list`, 2026-09-29).
- **Verification snippets** — copy-paste for Phase 4:

```bash
# Assert no vulnerable node remains in a lockfile (usage: node -e '<script>' <lockfile>)
node -e '
const fs=require("fs");
const lock=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const cmp=(a,b)=>{const pa=a.split(".").map(Number),pb=b.split(".").map(Number);
  for(let i=0;i<3;i++){if((pa[i]||0)!==(pb[i]||0))return (pa[i]||0)-(pb[i]||0);}return 0;};
let bad=0;
for(const [k,v] of Object.entries(lock.packages||{})){
  if(/(^|\/)fast-uri$/.test(k) && cmp(v.version,"3.1.7")<0){console.log("VULN fast-uri",k,v.version);bad++;}
  if(/(^|\/)ip-address$/.test(k) && cmp(v.version,"10.5.1")<0){console.log("VULN ip-address",k,v.version);bad++;}
}
console.log(bad===0?"OK: no vulnerable fast-uri/ip-address remains":"FAIL: "+bad+" vulnerable node(s)");
process.exit(bad?1:0);
' "$1"
```

```bash
# Alert-state discoverability (pre/post-merge, no dashboard)
gh api "repos/:owner/:repo/dependabot/alerts?state=open" \
  --jq '[.[]|select(.dependency.package.name=="fast-uri" or .dependency.package.name=="ip-address")]|length'
# pre-merge: 9 ; post-merge (after one Dependabot rescan): 0
```

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` and searched
bodies for all four candidate file paths
(`apps/web-platform/package-lock.json`,
`plugins/soleur/skills/pencil-setup/scripts/package-lock.json`,
`apps/web-platform/package.json`,
`plugins/soleur/skills/pencil-setup/scripts/package.json`): zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — both
  packages are transitive and the diff is lockfile-only. Any resolution error
  surfaces as a red `lockfile-sync` / `vitest` / `test-all.sh` CI check
  **pre-merge** and blocks the merge; no route, page, or behavior changes.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — this
  PR *removes* exposure (fast-uri authority-injection/SSRF via IPv6
  normalization and percent-decoding host confusion in ajv's URI validation;
  ip-address `isLinkLocal`/NAT64 trust-boundary bypass in express-rate-limit's
  IP classification). It introduces no new data surface.
- **Brand-survival threshold:** none.
  `threshold: none, reason: transitive lockfile-only security patch with no runtime code change and no user-facing behavior change; package-lock.json is not a sensitive-path file per preflight Check 6, and the change is CI-gated (lockfile-sync + tests) pre-merge.`

## Implementation Phases

> **Golden constraint (read first):** every `package-lock.json` write MUST go
> through **npm@11** via `npx --yes npm@11 …` — never local npm. The CI
> `lockfile-sync` job regenerates all four lockfiles under npm@11 and
> `git diff --exit-code`s them; a lockfile written by another npm major fails on
> shape drift (`cq-before-pushing-package-json-changes`;
> `learnings/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md`).
> **No `package.json` edits** in any phase — the patched versions already
> satisfy the declared ranges (`fast-uri ^3.0.1`, `ip-address ^10.2.0`).

### Phase 1 — Bump `apps/web-platform/package-lock.json` (npm@11)

```bash
cd apps/web-platform
npx --yes npm@11 update fast-uri ip-address
```

Expected: `node_modules/fast-uri` `3.1.5 → 3.1.8`; `node_modules/ip-address`
`10.5.0 → 10.7.2`. `ip-address` resolves as a peer-installed transitive copy
(`fast-uri` is a plain transitive); `npm
update` rewrites the single deduped node for each.

**Fallback (only if `npm update` leaves a node below floor — the
2026-04-07 silent no-op class, possible on `peer: true` entries):** surgical
lockfile edit replicating Dependabot's own diff shape — set `version`,
`resolved` (`https://registry.npmjs.org/<pkg>/-/<pkg>-<ver>.tgz`), and
`integrity` on the `node_modules/<pkg>` entry. Verified integrities:
`fast-uri@3.1.8` = `sha512-GZMtZUTNRpOVIECoXwLNZS5xUGE+mVNbTB8h/7Rwh2TFWcBQiPzTgyZi05BF9UMZKkLJv8XBRJTlU7zg8+ZfMg==`
(same value Dependabot PR #9192 commits — `gh pr diff 9192` is the reference);
`ip-address@10.7.2` = `sha512-7H/2gFSIitxc0hG3nOI1glS8QLo/EHBFFLk8vEUjXY/xu0AdL8jZ9U1IzO2PUm0d2D/ofQcAifb0g6OBkt8U7w==`.
Then validate with `npx --yes npm@11 ci --ignore-scripts` (the install verifies
the integrity sha against the registry tarball).

### Phase 2 — Bump `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` (npm@11)

```bash
cd plugins/soleur/skills/pencil-setup/scripts
npx --yes npm@11 update ip-address
```

Expected: `node_modules/ip-address` `10.5.0 → 10.7.2` (identical to Dependabot
PR #9191's diff). `node_modules/fast-uri` is already `3.1.8` in this manifest —
no action.

### Phase 3 — Verify (prod-fidelity install + tests)

1. `cd apps/web-platform && npx --yes npm@11 ci --ignore-scripts` (reconciles
   `node_modules` to the committed lockfile; validates integrity hashes).
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3. `cd apps/web-platform && ./node_modules/.bin/vitest run` (runner is vitest —
   root has no `workspaces` field, so `npm run -w` fails; use the local bin).
4. `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 ci --ignore-scripts`.
5. `bash scripts/test-all.sh` (repo-root suite).
6. Assert only lockfiles changed:
   `git status --short -- '**/package.json'` → empty.

### Phase 4 — Assert resolution + lockfile-sync idempotency

1. Run the assert-floors script (Research Insights) against
   `apps/web-platform/package-lock.json` AND
   `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`; both MUST
   print `OK`.
2. Idempotency, mirroring the CI gate exactly, in each touched dir:
   `npx --yes npm@11 install --package-lock-only && git diff --exit-code <dir>/package-lock.json` → clean.
3. Map each resolved version ≥ its Dependabot `first_patched_version`:
   `fast-uri 3.1.8 ≥ 3.1.7` (dismisses alerts 205–208 and 235);
   `ip-address 10.7.2 ≥ 10.5.1` (dismisses alerts 233–234 and 237–238).

### Phase 5 — Ship ONE security PR superseding the Dependabot PRs

- Commit ONLY the two lockfiles (plus the planning artifacts the pipeline
  commits separately).
- One PR, labels `type/security` + `dependencies`.
- PR body: alert-number → GHSA → patched-version table for all 9 alerts; states
  `Supersedes #9191 and #9192` (NOT `Closes` — those are PRs, and Dependabot
  auto-closes them once the underlying alerts resolve on `main`).
- Explicit scope-out note: #8065 (js-yaml/liquidjs) and #8857 (CodeQL SSRF)
  are not covered.
- Post-merge follow-through (in the ship phase): after one Dependabot rescan,
  confirm the alert query returns `0`; if #9191/#9192 remain open, close each
  with a `Superseded by #<this-PR>` comment (the bot re-files if its alert is
  still open, so a still-open bot PR is itself the regression signal).

## Observability

Files-to-Edit are two `package-lock.json` files — no runtime service is added,
so there is no new liveness surface. The change's "observability" is entirely
CI + Dependabot (both non-SSH, operator-visible). One touched file lives under
`plugins/*/scripts/`, so the section is emitted per the Phase 2.9 trigger.

```yaml
liveness_signal:
  what: "no new runtime surface — a transitive lockfile-only bump adds no service or process, so there is no heartbeat to declare; the live signal is the CI check suite itself"
  cadence: per-PR (each CI run)
  alert_target: GitHub PR check failure
  configured_in: ".github/workflows/ci.yml — existing lockfile-sync + test jobs (this change adds no new monitor)"
error_reporting:
  destination: GitHub Actions CI (lockfile-sync + vitest + test-all.sh) — a regression fails the PR check loudly; GitHub Dependabot re-scan surfaces any residual vulnerable version.
  fail_loud: true — CI checks are required; a red run blocks merge.
failure_modes:
  - mode: lockfile regenerated with wrong npm major (shape drift)
    detection: CI lockfile-sync job git diff --exit-code across all four lockfile dirs
    alert_route: PR check failure (blocks merge)
  - mode: patched version not actually reached (still below floor)
    detection: assert-floors node script (Phase 4) + post-merge gh api dependabot/alerts still listing the alert
    alert_route: pre-merge Phase-4 gate; post-merge the alert simply stays open on the default branch
  - mode: bump breaks a consumer (ajv URI validation / express-rate-limit IP classification)
    detection: tsc --noEmit / vitest run / test-all.sh failure
    alert_route: PR check failure (blocks merge)
logs:
  where: GitHub Actions run logs (per-PR); Dependabot alerts API/security tab
  retention: GitHub default (Actions logs ~90 days; alert state durable until dismissed)
discoverability_test:
  command: node -e 'const fs=require("fs"),cmp=(a,b)=>{const x=a.split(".").map(Number),y=b.split(".").map(Number);for(let i=0;i<3;i++)if((x[i]||0)!==(y[i]||0))return x[i]-y[i];return 0};let bad=0;for(const f of process.argv.slice(1)){const l=JSON.parse(fs.readFileSync(f,"utf8"));for(const [k,v] of Object.entries(l.packages||{})){if(/(^|\/)fast-uri$/.test(k)&&cmp(v.version,"3.1.7")<0)bad++;if(/(^|\/)ip-address$/.test(k)&&cmp(v.version,"10.5.1")<0)bad++}}console.log(bad===0?"OK":"FAIL "+bad)' apps/web-platform/package-lock.json plugins/soleur/skills/pencil-setup/scripts/package-lock.json
  expected_output: "OK"
```

The Dependabot-API variant is the external pre/post-merge confirmation used by
the Acceptance Criteria (not the Check-10 probe, since `gh` is not on the
probe-verb allowlist): `gh api
"repos/:owner/:repo/dependabot/alerts?state=open" --jq
'[.[]|select(.dependency.package.name=="fast-uri" or
.dependency.package.name=="ip-address")]|length'` → `9` pre-merge, `0`
post-merge after one rescan cycle.

## Domain Review

**Domains relevant:** none

Mechanical security dependency-hygiene change (transitive lockfile bumps). No UI
surface (no `components/**`, `app/**/page.tsx` in Files to Edit), no
infrastructure (Phase 2.8), no regulated-data surface (Phase 2.7 — lockfiles are
not schema/auth/API/`.sql`, and no new artifact-distribution surface is
created), no architectural decision (Phase 2.10 — a dependency bump cannot
mislead a future engineer reading the ADRs), no encryption posture change
(Phase 2.11 — no persistent store or new connection), no guard introduced
(Phase 2.12). Product/UX Gate: NONE.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/package-lock.json`: `node_modules/fast-uri` resolves
      `3.1.8` (or any `3.x >= 3.1.7`); `node_modules/ip-address` resolves
      `10.7.2` (or any `>= 10.5.1`); no `fast-uri < 3.1.7` or
      `ip-address <= 10.5.0` node remains.
- [ ] `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`:
      `node_modules/ip-address` resolves `10.7.2` (or `>= 10.5.1`); `fast-uri`
      remains `>= 3.1.7` (currently `3.1.8`).
- [ ] Assert-floors script prints `OK` against both lockfiles.
- [ ] **No `package.json` modified** — `git status --short -- '**/package.json'`
      empty (unless the documented fallback fired, in which case the plan's
      fallback path and its diff are recorded in the PR body).
- [ ] lockfile-sync idempotency: `npx --yes npm@11 install --package-lock-only`
      produces no `git diff` in each touched directory.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` passes.
- [ ] `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 ci --ignore-scripts` succeeds.
- [ ] `bash scripts/test-all.sh` passes.
- [ ] PR carries `type/security` + `dependencies` labels; body maps all 9 alert
      numbers → GHSAs → resolved versions and states `Supersedes #9191` /
      `Supersedes #9192`; #8065 and #8857 are named as excluded.

### Post-merge (automatic)

- [ ] After merge to `main` and one Dependabot rescan,
      `gh api repos/:owner/:repo/dependabot/alerts?state=open` returns **0**
      `fast-uri`/`ip-address` alerts (all 9 dismissed automatically — Dependabot
      dismisses when the vulnerable version leaves the default-branch
      dependency graph).
- [ ] Dependabot PRs #9191 and #9192 are closed (auto-closed by the alert
      resolution, or closed manually with a `Superseded by` comment if they
      linger past one rescan cycle).

## Sharp Edges

- **npm@11 pin is load-bearing.** Any other npm major produces a divergent
  lockfile shape and fails `lockfile-sync`. Always `npx --yes npm@11 …`.
- **`npm update` may silently no-op on a transitive/peer copy** (2026-04-07
  learning). The Phase 4 assert-floors gate is the proof; do not treat a green
  `npm update` exit code as evidence of the bump. Fallback is the surgical
  3-field entry edit with the verified integrity hashes above — never
  `npm install <pkg>@<ver> --no-save` (that flag blocks lockfile writes too).
- **Do not bump `fast-uri` to 4.x.** npm latest is `4.2.1`, but every consumer
  range is `^3.0.1` — `4.x` is unreachable without an override and is NOT what
  Dependabot targets. `3.1.8` is the correct landing.
- **No `bun.lock` exists** — do not resurrect one (`lint-dual-lockfile.sh`
  fails CI). The bun parity steps in the 2026-07-18 precedent are obsolete.
- **`npm run -w apps/web-platform …` fails** — root `package.json` has no
  `workspaces` field. Use `cd apps/web-platform && ./node_modules/.bin/…`.
- **`gh pr create --label` fails on a nonexistent label** — both labels were
  verified 2026-09-29; re-verify if this plan is executed much later.
- **Do NOT bundle #8065 / #8857** — separate substantive work (different
  packages; code-level SSRF), not lockfile bumps.
- **A Dependabot alert is dismissed by the default-branch graph, not the PR** —
  merging only resolves alerts after the next rescan; a still-open alert or
  still-open #9191/#9192 after one cycle means the bump missed a copy.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits
  the threshold fails `deepen-plan` Phase 4.6 — this plan's section is complete
  (threshold `none` with reason bullet).

## Test Scenarios

1. **Resolution correctness:** after Phases 1–2, `fast-uri` reads `3.1.8` and
   `ip-address` reads `10.7.2` in `apps/web-platform/package-lock.json`;
   `ip-address` reads `10.7.2` in the pencil-setup lockfile; assert-floors
   prints `OK` for both.
2. **CI gate fidelity:** `npx --yes npm@11 install --package-lock-only` in each
   touched dir is idempotent (no diff) — proves the committed lockfile matches
   what CI regenerates.
3. **Prod-fidelity build:** `npx --yes npm@11 ci --ignore-scripts` +
   `tsc --noEmit` + `vitest run` in `apps/web-platform` pass on the bumped tree
   (ajv schema validation / express-rate-limit IP classification are the
   consumer surfaces).
4. **Pencil adapter install:** `npm ci --ignore-scripts` in
   `plugins/soleur/skills/pencil-setup/scripts` succeeds.
5. **Root suite:** `bash scripts/test-all.sh` passes.
6. **Alert-dismiss precondition:** each resolved version ≥ Dependabot
   `first_patched_version`; post-merge rescan yields 0 open fast-uri/ip-address
   alerts and auto-closes #9191/#9192.
