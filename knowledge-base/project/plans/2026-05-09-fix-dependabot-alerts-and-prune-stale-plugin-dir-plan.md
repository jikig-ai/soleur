---
title: "fix: resolve 18 Dependabot alerts and prune stale .plugin/ directory"
date: 2026-05-09
type: fix
classification: security-hygiene
issue: dependabot-alerts-batch-2026-05
pr_draft: 3488
branch: feat-one-shot-dependabot-alerts-fix
worktree: .worktrees/feat-one-shot-dependabot-alerts-fix
detail_level: MINIMAL
requires_cpo_signoff: false
---

# fix: resolve 18 Dependabot alerts and prune stale .plugin/ directory

## Overview

Resolve all 18 open Dependabot alerts on `main` with a minimal security-hygiene PR.

The dominant finding from investigation is that **12 of 18 alerts live in `.plugin/`**, a
fully-orphaned directory left behind by an early OpenHands port (PR #1802/#1803/#1804).
That port was superseded by `.openhands/` (PR #1805 `f449cb6a` — "refactor: migrate 63
OpenHands agents to .openhands/skills/ format"), and the deprecation is documented in
`knowledge-base/project/learnings/workflow-patterns/2026-04-09-openhands-plugin-agent-porting.md`
("**Superseded:** The `.openhands-plugin/agents/` format was an intermediate step. All
63 agents were migrated to `.openhands/skills/<name>/SKILL.md`"). The active OpenHands
integration lives in `.openhands/` (`hooks/`, `hooks.json`, `skills/`).

Deleting `.plugin/` therefore removes 12 alerts at the source — not by patching code we
ship, but by deleting code we never ship.

The remaining 6 alerts split as:

- **1 fast-uri (high) in `apps/web-platform/package-lock.json`** — transitive via `ajv@8.18.0`.
- **5 alerts in `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`**:
  - 1 fast-uri (high) — transitive via `ajv@8.x` under `@modelcontextprotocol/sdk`.
  - 3 hono (1 medium + 2 medium + 1 low across 2 advisories) — transitive via
    `@modelcontextprotocol/sdk → hono@^4.11.4`. Fixed in `hono@4.12.18`.
  - 1 ip-address (medium) — transitive via `express-rate-limit → ip-address@10.1.0`.
    Fixed in `ip-address@10.1.1`.

All patched versions are reachable within existing semver ranges; this is a lockfile-only
bump (no `package.json` edits). Per AGENTS.md `cq-before-pushing-package-json-changes`,
both `bun.lock` and `package-lock.json` must be regenerated where both files exist.

## User-Brand Impact

**If this lands broken, the user experiences:** broken `npm ci` in `apps/web-platform/`'s
Dockerfile, blocking the next deployment. Detection is immediate (CI `npm ci` fails on
PR), so blast radius is the open PR, not production.

**If this leaks, the user's [data / workflow / money] is exposed via:** the four
underlying advisories already DO leak — fast-uri path-traversal + host confusion (could
permit open-redirect/SSRF abuse against any code routing user URLs through `ajv`-validated
schemas), hono cache-leak via `Vary` mishandling (could leak per-user cache state across
sessions if any chat/web surface used hono cache middleware — it doesn't, the package is
indirect), hono JSX HTML/CSS injection, hono JWT NumericDate validation, ip-address
Address6 XSS. The realistic exposure is **bounded** because none of these packages is
directly imported by the production web-platform codebase — they are transitive surface
area only — but Dependabot rates the chain reachable, and unpatched chains accumulate
risk over time.

**Brand-survival threshold:** none

The patches close known-CVE chains; the security improvement is monotonic. No user-facing
behavior changes. Sensitive paths (`apps/web-platform/server`, `apps/web-platform/lib`)
are not modified — only the lockfile in that app, plus deleted scripts in `.plugin/` that
were never reachable from any deployed surface.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (input description) | Reality (codebase) | Plan response |
|---|---|---|
| `.plugin/` "looks like a stale duplicate" of `plugins/soleur/skills/pencil-setup/scripts/` | `.plugin/` is the SUPERSEDED OpenHands "agents-flat" port from PR #1802/#1803/#1804; replaced by `.openhands/` in PR #1805. Zero references from any active code path. Documented in `knowledge-base/project/learnings/workflow-patterns/2026-04-09-openhands-plugin-agent-porting.md`. | Confirmed orphaned — delete entire `.plugin/` directory (not just `.plugin/skills/pencil-setup/scripts/`). |
| Spec mentions only `pencil-setup/scripts/package-lock.json` under `.plugin/` | `.plugin/` contains 22 skill subdirectories. The OTHER skills do not have alerts today, but they are equally orphaned (e.g., `.plugin/skills/gemini-imagegen` had a `pillow` Dependabot bump in PR #2163 — same pattern). | Delete the **entire** `.plugin/` directory in one commit, not just the pencil-setup subtree. This prevents future bot churn against orphan paths. |
| Spec implies remaining `apps/web-platform` fast-uri alert needs a "transitive dep bump" | `fast-uri@3.1.0` is installed via `ajv@8.18.0` (transitive under multiple top-level packages: ajv-formats, ajv-keywords, sharp, schema-utils). Top-level semver allows `fast-uri@^3.0.1`, so a scoped `npm update fast-uri` will bump in-range to `3.1.2` without touching unrelated packages. | Use `npm update fast-uri` (scoped) — NOT `npm update`. Mirror with `bun update fast-uri`. |
| Spec says "bump remaining transitive deps" | Three packages need bumping in `pencil-setup/scripts/`: `fast-uri`, `hono`, `ip-address`. All are in-range under existing semver constraints (hono@^4.11.4, ip-address@10.1.0 → 10.1.1+, fast-uri@^3.0.1). No `bun.lock` exists in `pencil-setup/scripts/` — `package-lock.json` only. | Run `npm update fast-uri hono ip-address` in `plugins/soleur/skills/pencil-setup/scripts/` (single scoped update). |

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` for files matching
`.plugin/`, `apps/web-platform/package-lock.json`, `plugins/soleur/skills/pencil-setup`;
no matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — security-hygiene change scoped to lockfiles +
deletion of a fully-orphaned directory. No user-facing surface modified. No Product, CMO,
CRO, CTO, COO, CLO, CFO concerns at this scope.

## Files to Edit

- `apps/web-platform/package-lock.json` — regen via `npm update fast-uri`
- `apps/web-platform/bun.lock` — regen via `bun update fast-uri`
- `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` — regen via
  `npm update fast-uri hono ip-address` (no `bun.lock` exists here)

## Files to Delete

- `.plugin/` (entire directory) — superseded by `.openhands/` (PR #1805); unreachable from
  any active code path. Verified by:
  1. `grep -rn "\.plugin/"` across `apps/`, `plugins/`, `scripts/`, `.github/`, `docs/`
     returns zero matches outside `.plugin/` itself and `knowledge-base/` historical docs.
  2. The active OpenHands integration lives in `.openhands/{hooks,skills,hooks.json}`.
  3. `git log -- .plugin/` last meaningful change is `771cd7ee` (Dependabot bump);
     last feature commit is `95768099` from the original port (PR #1804) before the
     supersedure.

## Files to Create

None.

## Implementation Phases

### Phase 1: Delete orphaned `.plugin/` directory

Removes 12 of 18 alerts at the source (both fast-uri@3.1.0/3.1.1, all 6 hono advisories, 1
ip-address, 1 fast-uri across `.plugin/skills/pencil-setup/scripts/`).

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-dependabot-alerts-fix
git rm -r .plugin/
git status -- .plugin/  # verify everything is staged for deletion
```

### Phase 2: Bump transitive deps in `apps/web-platform/`

Resolves the 1 remaining fast-uri alert (`apps/web-platform/package-lock.json`).

```bash
cd apps/web-platform/
# Scoped update — DO NOT run `npm update` bare (would touch 16+ packages).
npm update fast-uri
# Verify fast-uri resolved to >= 3.1.2 in package-lock.json:
grep -A1 '"node_modules/fast-uri"' package-lock.json | head -3
# Mirror to bun.lock:
bun update fast-uri
# Verify in bun.lock:
grep "fast-uri" bun.lock | head -3
# Verify diff scope is lockfile-only:
git diff --stat
# Expect: only package-lock.json + bun.lock changed; no package.json edits.
```

### Phase 3: Bump transitive deps in `plugins/soleur/skills/pencil-setup/scripts/`

Resolves the 5 remaining alerts (1 fast-uri high, 3 hono medium + 1 hono low, 1 ip-address
medium).

```bash
cd plugins/soleur/skills/pencil-setup/scripts/
# Scoped update for all three vulnerable packages in one call.
npm update fast-uri hono ip-address
# Verify resolutions:
grep -A1 '"node_modules/fast-uri"\|"node_modules/hono"\|"node_modules/ip-address"' package-lock.json | head -12
# Expected: fast-uri >= 3.1.2, hono >= 4.12.18, ip-address >= 10.1.1
# No bun.lock here — package-lock.json only.
```

### Phase 4: Verify and ship

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-dependabot-alerts-fix
# Lockfile integrity check:
cd apps/web-platform && npm ci && cd ../..
# Type + test smoke pass (catches any unexpected ESM/runtime drift from the deps):
cd apps/web-platform && npm run typecheck && cd ../..
# Note: full `npm run test` is not strictly required for transitive-dep bumps with
# zero diff in source files, but run it if the PR template calls for it.
git status
git diff --stat
git add .plugin apps/web-platform/package-lock.json apps/web-platform/bun.lock \
        plugins/soleur/skills/pencil-setup/scripts/package-lock.json
git commit -m "fix(deps): resolve 18 Dependabot alerts; prune stale .plugin/ directory"
git push
gh pr ready 3488
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.plugin/` directory removed entirely (`git ls-files .plugin/` returns empty).
- [ ] `apps/web-platform/package-lock.json` shows `fast-uri@^3.1.2` (or newer).
- [ ] `apps/web-platform/bun.lock` shows `fast-uri@3.1.2` (or newer).
- [ ] `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` shows
      `fast-uri@^3.1.2`, `hono@^4.12.18`, `ip-address@^10.1.1` (or newer).
- [ ] `git diff --stat` shows ONLY:
      (a) deletion of `.plugin/**`,
      (b) `apps/web-platform/package-lock.json` and `apps/web-platform/bun.lock`,
      (c) `plugins/soleur/skills/pencil-setup/scripts/package-lock.json`.
      No `package.json` edits, no source-file edits.
- [ ] `cd apps/web-platform && npm ci` exits 0 (lockfile integrity).
- [ ] `cd apps/web-platform && npm run typecheck` exits 0.
- [ ] PR body includes `Ref` (not `Closes`) for any alert ids — Dependabot alerts auto-close
      when the underlying vulnerability is patched in the merged commit; no `Closes #N`
      keyword needed.

### Post-merge (auto)

- [ ] All 18 Dependabot alerts auto-close within ~24h of merge to `main`. Verify via:
      `gh api repos/jikig-ai/soleur/dependabot/alerts --paginate | jq '[.[] | select(.state=="open")] | length'`
      should drop from 18 → 0.
- [ ] `dependency-review.yml` workflow on the PR shows zero new high/critical
      vulnerabilities.

## Test Scenarios

This is a transitive-dependency bump with no source-code changes. The existing test suite
in `apps/web-platform/` covers any behavior the bumped packages contribute to.

- **TS1 — Lockfile integrity:** `npm ci` re-installs from `package-lock.json` without
  errors (covered by AC).
- **TS2 — Typecheck stability:** `tsc --noEmit` passes; no type changes from `ajv` or its
  transitive `fast-uri` (covered by AC).
- **TS3 — No source diff:** `git diff --stat` shows only lockfiles + `.plugin/` deletion
  (covered by AC).
- **TS4 — Reachability of `.openhands/`:** Confirm the active OpenHands integration is
  preserved by spot-checking `.openhands/skills/` and `.openhands/hooks/` exist after the
  delete. (Sanity check — `.plugin/` and `.openhands/` are separate top-level directories,
  but a defensive `ls .openhands/skills/ | wc -l` after the delete is cheap.)

## Risks

- **Risk: `npm update fast-uri` in `apps/web-platform/` pulls more than fast-uri.**
  Scoped `npm update <pkg>` only updates the named package within its allowed semver
  range, but if a sibling transitive has a tighter constraint, npm may co-update. Verify
  via `git diff --stat` and roll back if more than the lockfile lines change. The PR
  #1699 precedent (vite bump) used the same scoped form successfully.
- **Risk: hono@4.12.18 is a minor bump from 4.12.14 — could change runtime behavior.**
  hono is transitive (via `@modelcontextprotocol/sdk` peer + dep), and the pencil-setup
  scripts directory is dev-tooling only (used by the local pencil MCP adapter). It is not
  shipped in the web-platform Docker image. Mitigation: the changes are within minor
  range (`^4.11.4` allows `4.12.x`), and the CHANGELOG between 4.12.14 → 4.12.18 only
  contains the security fixes Dependabot is calling out plus minor bug fixes.
- **Risk: deleting `.plugin/` breaks an unknown caller.** Mitigated by:
  (a) zero references in `apps/`, `plugins/`, `scripts/`, `.github/`, `docs/`;
  (b) `.openhands/` is the documented successor (PR #1805);
  (c) the orphan was last touched only by Dependabot bumps for ~6 weeks;
  (d) reversible — `git revert` of the delete-commit fully restores the directory.
- **Risk: a future reintroduction of the OpenHands plugin path.** The
  `knowledge-base/project/specs/openhands-portability/recommendation.md` document is
  marked "CONDITIONAL GO" with a "build when triggered" gate. If the trigger fires later,
  the recommendation explicitly says to scaffold a fresh `.plugin/` at that time —
  deleting the stale one now does NOT prejudice that future work.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's
  threshold is `none` with a defended rationale; the section is complete.
- Per AGENTS.md `cq-before-pushing-package-json-changes`, both `bun.lock` and
  `package-lock.json` must be regenerated when both exist. `apps/web-platform/` has both;
  `plugins/soleur/skills/pencil-setup/scripts/` has only `package-lock.json` — no
  `bun.lock` regen needed there. (Verified via `ls plugins/soleur/skills/pencil-setup/scripts/`.)
- `npm update <pkg>` (scoped) — NOT `npm update` (bare). The bare form would walk every
  outdated package and pull in changes far exceeding the security scope. Precedent: PR
  #1699 explicitly called this out for the vite bump.
- Use `Ref #<alert>` not `Closes #<alert>` in the PR body. Dependabot alerts are not
  GitHub Issues — they are a separate alert type — and they auto-close from the merged
  commit's lockfile diff. No close-keyword needed.
- Phase 4's `npm ci` must succeed in `apps/web-platform/`. The web-platform Dockerfile
  uses `npm ci` (not `npm install`), so a corrupt lockfile would fail every subsequent
  deploy. This is the load-bearing pre-merge check.
- Do NOT delete `.openhands/` — it is the ACTIVE OpenHands integration. The deletion is
  scoped to `.plugin/` only. Watch the `git status` output before commit.
- Re-confirm at deepen-plan time: an `npm view` against the patched versions to ensure
  no regression has shipped between plan-time (2026-05-09) and work-time. fast-uri@3.1.2
  was published 2026-05-05; hono@4.12.18 and ip-address@10.1.1+ also recently. If a
  newer patch ships before merge, npm update will pick the latest in-range automatically.

## Out of Scope

- **Adding `.github/dependabot.yml`** — repository-level Dependabot config is currently
  managed via repo settings, not a YAML file. Adding the YAML is a separate piece of work
  (see #2417 for the CodeQL gate; a similar config-file PR for Dependabot can follow
  separately).
- **Updating `@modelcontextprotocol/sdk` to a major version.** Even though the SDK at
  `^1.27.1` already accepts the patched versions in semver range, a major-version SDK
  upgrade is independent and out of scope here.
- **Refactoring `pencil-setup/scripts/` to use a different MCP adapter library.** The
  vulnerable `hono`/`fast-uri`/`ip-address` chain comes from `@modelcontextprotocol/sdk`'s
  own dependency tree; we don't control it directly. Patching the lockfile is the correct
  fix.
- **Backfilling Dependabot config for `.openhands/skills/pencil-setup/scripts/`** if any
  package-lock.json lives there — out of scope; if alerts surface there, they get a
  follow-up PR.

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Patch each `.plugin/skills/pencil-setup/scripts/` lockfile entry the same way as the live one | The directory is orphaned and re-bumping is rework; deleting eliminates the surface entirely. |
| `npm audit fix` | Touches every direct + transitive dep, well beyond the security scope; risks unrelated breakage. PR #1699 explicitly avoided this approach. |
| Direct-pin `fast-uri` / `hono` / `ip-address` in each `package.json` | Adds direct deps where none exist today, increasing surface and confusing future readers. Scoped `npm update` is the established pattern. |
| Wait for Dependabot to auto-PR each alert | 18 individual PRs per the alert count; high merge churn; precedent (PRs #2404/#2405) shows even one round costs more reviewer time than a single batched fix. |
| Add `.plugin/` to `.gitignore` and leave the files in place | `.gitignore` doesn't untrack already-committed files; alerts persist. |

## Hypotheses

Not applicable — this is a security-hygiene fix, not a network/SSH/connectivity issue.
The `1.4` Network-Outage Hypothesis Check was evaluated against the feature description
("Dependabot alerts", "fast-uri", "hono", "ip-address", "lockfile"); no SSH/firewall/
timeout/handshake keywords matched, so the checklist does not apply.

## References

- AGENTS.md `cq-before-pushing-package-json-changes` — dual-lockfile rule.
- AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` — `Ref` vs `Closes` discipline.
- PR #1699 — vite Dependabot precedent using scoped `npm update`.
- PR #1805 (`f449cb6a`) — supersedure migration that orphaned `.plugin/`.
- `knowledge-base/project/learnings/workflow-patterns/2026-04-09-openhands-plugin-agent-porting.md`
  — documents the supersedure of `.openhands-plugin/` (the spiritual predecessor to
  `.plugin/`) and the `.openhands/skills/` final form.
- `knowledge-base/project/specs/openhands-portability/recommendation.md` — "CONDITIONAL
  GO" gate; deleting `.plugin/` does not prejudice a future re-port.
- GHSA-q3j6-qgpj-74h6, GHSA-v39h-62p7-jpjc — fast-uri advisories.
- GHSA-69xw-7hcm-h432, GHSA-9vqf-7f2p-gf9v, GHSA-hm8q-7f3q-5f36, GHSA-p77w-8qqv-26rm,
  GHSA-qp7p-654g-cw7p — hono advisories.
- GHSA-v2v4-37r5-5v8g — ip-address advisory.
