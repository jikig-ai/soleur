---
title: "Residual ${CLAUDE_PLUGIN_ROOT} migration — remaining agent-run skill families"
issue: 6154
type: security-migration
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
milestone: "Phase 4: Validate + Scale"
adr: ADR-093 (amend — flip residual-surface consequence OPEN → closed, scoped to the enumerated families)
date: 2026-07-08
---

# 🔒 Fix #6154 — Residual `${CLAUDE_PLUGIN_ROOT}` migration (ADR-093 follow-up)

## Enhancement Summary

**Deepened on:** 2026-07-08 · **Review panel:** security-sentinel, architecture-strategist, code-simplicity-reviewer (parallel).

### Key improvements from review
1. **+3 review-found migration classes the issue's `.sh`-scoped enumeration missed** — all invisible to the AC1 broad grep:
   - `linear-fetch/SKILL.md:79` — a **plugin-deployed redaction gate** (`redact-linear-urls.sh`, bare `./scripts/` anchor). Same single-user-incident class as `redact-sentinel.sh`; omitted from ADR-093's own residual enumeration. **Now a first-class Phase 1 (redaction-gate) deliverable.**
   - `plan/SKILL.md:329` — `bash plugins/soleur/scripts/taste-profile-update.sh` (**`plugins/soleur/scripts/`, no `skills/` segment** → AC1-blind). The plan already edits `plan/SKILL.md`, so leaving this un-migrated 12 lines from an edited site would falsify "CLOSED".
   - `.py` plugin-script execs — `compound-capture:592` (`init_skill.py`) + `skill-creator:144/185/191` (`init_skill.py`, `package_skill.py`). AC1's `\.sh` pattern cannot see them.
2. **AC1 made exhaustive** — added a generalized completeness grep (AC1-EXT) covering `.py`, `plugins/soleur/scripts/` (non-`skills/`), and bare-`scripts/`/`./scripts/` exec forms; generalized AC2 to sweep all bare-anchor redaction gates (incident + linear-fetch).
3. **ADR "CLOSED" language scoped** — closure is bounded to *plugin-deployed skill/plugin-script shell-outs in the enumerated families*; the distinct repo-root `scripts/` CWD-shadow vector (which `${CLAUDE_PLUGIN_ROOT}` cannot anchor) + the same-script `taste-profile-update.sh` siblings in `brainstorm`/`frontend-design` are recorded as a tracked follow-up, not silently implied-closed.
4. **YAGNI trims applied** (code-simplicity): folded AC5→AC5(paren), trimmed AC7 sub-points, deduped Test Scenarios to the one net-new check, collapsed the four single-anchor phases into one anchor-table phase, stated the "var-always-set" fact once.

### Sign-offs
- **security-sentinel:** Q1 (no safe-bash.ts change), Q2 (git-root fallback safe), Q3 (incident bare-anchor + AC2) all **verified correct** against `safe-bash.ts`/`agent-env.ts`/`agent-runner-query-options.ts`/coupling test. Conditional finding (plan:329 + `.py` handling) **resolved** by folding both in → sign-off affirmative.
- **architecture-strategist:** amend-ADR-093 (not new ADR) and "no C4 impact" both **verified correct**; the one concrete enumeration gap (linear-fetch) is folded in.

---

## Overview

Slice C (ADR-093, closed #6121) migrated 14 enumerated agent-run families + `product-roadmap` off
CWD-relative `bash ./plugins/soleur/…/<script>.sh` to the deployment-anchored
`${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/…` form. Deepen-plan review grep-proved a **residual set of
genuinely-distinct agent-run families** still carrying the identical untrusted-code-execution hole: on
the Concierge server (autonomous bash default-on, `permission-callback.ts` autonomous bypass), a
CWD-relative shell-out resolves to the connected repo's **untrusted committed** copy of the script and
runs it **outside the bwrap sandbox** with the dispatch process's env + privileges. This is the exact
face modeled by `connectedRepoPlugin` ("Connected-Repo Plugin Copy", UNTRUSTED, `model.c4:268`).

This plan closes that residual surface **for the enumerated families**. The fix is mechanical and
identical to Slice C: rewrite each sandbox-executed invocation to `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/…`,
preserving the original fallback anchor verbatim. **No product code, no UI, no DB, no infra.**
Deliverables: **14 SKILL.md files (~29 invocation sites)** + a scoped ADR-093 amendment.

**Server-safety invariant (stated once; referenced throughout).** `CLAUDE_PLUGIN_ROOT` is always
injected on both Concierge factories (Slice B `agent-env.ts`; `assertTrustedPluginPath` at the
`buildAgentQueryOptions` chokepoint is the loaded-gun guard). So `${CLAUDE_PLUGIN_ROOT:-…}` → the
platform-deployed `/app/shared/plugins/soleur` on the server; the `:-` default — **including any
`$(git rev-parse …)` fallback — never executes there.** On the CLI (var unset) it falls back to the
local checkout. security-sentinel verified this against `agent-env.ts:201-202`,
`agent-runner-query-options.ts:190-197`, `plugin-path.ts:27`.

## Research Reconciliation — Spec vs. Codebase

Every site was grep-verified against current worktree state. Issue line numbers are approximate
(drifted); the table uses **current verified line numbers**.

| Issue / review claim | Reality (verified) | Plan response |
|---|---|---|
| `plan:327,840 → archive-kb.sh` | `plan:327` = `pencil-setup/scripts/check_deps.sh --auto` (agent-run, un-migrated; brainstorm:431 already migrated); `plan:840` = `archive-kb.sh` (`./` anchor). | Migrate **both**. |
| `incident → redact-sentinel.sh` | `incident:217` execs via **bare `scripts/redact-sentinel.sh`** — does NOT match AC1 broad grep. | Migrate (git-root fallback); AC2 supplementary grep. |
| re-classify set (6 families) | All **agent-run** (`constraint-scaffold` explicitly `agent-only`; none operator-credentialed). | Migrate the **entire** set. |
| **[review] `linear-fetch:79`** | `bash ./scripts/redact-linear-urls.sh` — **plugin-deployed redaction gate** (`git ls-files` confirms the script ships), agent-run, persist-safe secret/URL scrubber, bare `./scripts/` anchor. Missed by ADR-093's own residual enumeration. | **Add as a Phase 1 redaction-gate deliverable** (git-root fallback). |
| **[review] `plan:329`** | `bash plugins/soleur/scripts/taste-profile-update.sh …` — plugin-deployed, **`plugins/soleur/scripts/` (no `skills/`)** → AC1-blind. Plan already edits this file. | Migrate (`${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/…`). |
| **[review] `.py` execs** | `compound-capture:592` (`python3 …/init_skill.py`), `skill-creator:144/185/191` (bare `scripts/init_skill.py`, `scripts/package_skill.py`) — plugin-deployed, `.sh`-scoped AC1 blind. In already-edited families. | Migrate all four (`.py` interpreter/exec form preserved). |
| **[review] repo-root `scripts/` class** | `generate-kb-index.sh` (compound-capture:135, kb-search:58,166) lives at **repo-root `scripts/`** — NOT plugin-deployed; `${CLAUDE_PLUGIN_ROOT}` cannot anchor it. A broader repo-root-`scripts/` CWD-shadow vector exists in *other* families (architecture:282, compound:254, review:272, preflight:909, …). | **Out of scope** (distinct vector). ADR language scoped; follow-up issue filed. |
| **[review] `taste-profile-update.sh` siblings** | Same script also invoked CWD-relative in `brainstorm:426`, `frontend-design:51,61` (outside enumerated families; not a secret-handling gate). | ADR language scoped to named families; siblings tracked in the follow-up. |

**Premise Validation:** #6154 OPEN, no closing PR. ADR-093 Accepted; its Consequences § names #6154 as
the residual open surface. Git-root-fallback pattern already ships at `compound/SKILL.md:289`;
`./plugins/soleur` anchor at `compound/SKILL.md:455`; bare `plugins/soleur` at `brainstorm/SKILL.md:431`
— this migration reuses all three verbatim (not novel forms). No stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** a skill whose migrated path is mistyped fails to locate
its script. For the **three redaction-gate sites** (redact-sentinel: legal-generate/incident;
redact-linear-urls: linear-fetch) the gate **fails closed (halt)** — the draft/summary is never emitted
or persisted — so a broken redaction-gate migration degrades **safely** (no silent secret leak). For
non-gate sites a wrong path is a loud "file not found", never a silent wrong behavior.

**If this leaks, the user's secrets/PII are exposed via:** the *pre-existing* hole this PR closes — a
connected repo shipping its own `plugins/soleur/` could substitute an untrusted `redact-sentinel.sh` /
`redact-linear-urls.sh` that **neuters the redaction gate**, letting a secret pasted into
legal-generate/incident context or a signed Linear CDN URL reach the transcript / a persisted artifact.
This PR removes that vector for all three gates (plus the prod-cron trigger and the security scanners).

**Brand-survival threshold:** single-user incident. — The modified surface includes the three
secret/PII-redaction gates; a neutered gate leaks one user's secret. `requires_cpo_signoff: true` at
plan time; `user-impact-reviewer` verifies the redaction-gate sites at review (server-correct: var
always set; CLI-correct: unset → git-root checkout). The change is risk-*reducing* (closes an open hole)
and fail-closed, so the migration introduces no new single-user exposure.

## Implementation Phases

### Phase 1 — Redaction gates (git-root fallback, elevated single-user-incident stakes)

Fallback form for ALL three: `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`
(matches `compound/SKILL.md:289`). Per the server-safety invariant, the `$(…)` never runs on the server;
it is never auto-approved (never matches `EXACT_LITERAL_SAFE_COMMANDS`; both `$(` and `${` trip
`SHELL_METACHAR_DENYLIST`) → runs via the autonomous path. Quote the whole expansion so a space-bearing
git-root path is safe.

1. **`legal-generate/SKILL.md:60`** — `SENTINEL="$(git rev-parse --show-toplevel)/plugins/soleur/skills/incident/scripts/redact-sentinel.sh"`
   → `SENTINEL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh"`.
2. **`incident/SKILL.md:217`** — ``Run `bash scripts/redact-sentinel.sh <draft-tmpfile>` ``
   → ``Run `bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh" <draft-tmpfile>` `` (incident **owns** this script).
3. **`linear-fetch/SKILL.md:79`** — `bash ./scripts/redact-linear-urls.sh`
   → `bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/linear-fetch/scripts/redact-linear-urls.sh"` (same bare-anchor blind spot as incident; linear-fetch owns its script).

### Phase 2 — Single-anchor bulk migrations

Each site keeps its exact original anchor as the `:-` fallback (**do not homogenize** — the anchor column
is the one bit of signal the drift-guard and Slice C convention key on). Interpreter/exec prefix and
argument tail preserved verbatim; only the anchor changes.

| Site(s) | Script | Anchor (fallback) |
|---|---|---|
| `trigger-cron:40,43,47` | `trigger.sh --list` / `--event …` / fire (no `bash` prefix) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `skill-security-scan:59,66` | `run-scan.sh` (file form + stdin-pipe form) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `skill-creator:213` | `run-scan.sh` (post-scaffold gate) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `skill-creator:144` | `scripts/init_skill.py <skill-name> --path …` (bare exec) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/skill-creator/scripts/init_skill.py` |
| `skill-creator:185,191` | `scripts/package_skill.py …` (bare exec) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/skill-creator/scripts/package_skill.py` |
| `compound-capture:592` | `python3 …/skill-creator/scripts/init_skill.py` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `plan:327` | `pencil-setup/scripts/check_deps.sh --auto` (aligns w/ brainstorm:431) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `plan:329` | `plugins/soleur/scripts/taste-profile-update.sh …` (**non-`skills/`** path) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/taste-profile-update.sh` |
| `plan:840` | `archive-kb.sh` (`./` anchor) | `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` |
| `compound-capture:473` | `archive-kb.sh` (`./` anchor) | `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` |
| `kb-search:117,129` | `kb-search-cache.sh lookup` (in `$(…)`) / `append` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `harvest-debt:44` | `harvest-debt.sh` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `seo-aeo:78,79,103,104` | `validate-seo.sh` / `validate-csp.sh` (78–79 in Task-prompt block; 103–104 in validate steps) | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `drain-labeled-backlog:63` | `group-by-area.sh` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `constraint-scaffold:56,63` | `constraint-scaffold.sh` / `… --refresh-baseline` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |
| `model-launch-review:44,56` | `audit-models.sh` / `… --fix` | `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` |

### Phase 3 — ADR-093 amendment (scoped) + follow-up issue

- Amend `ADR-093` Consequences §: change the **"Residual untrusted-exec surface (OPEN — tracked in #6154)"**
  bullet to CLOSED **scoped to the enumerated families** (the 13 + `linear-fetch`), listing them and citing
  this PR. Extension of the existing decision (not a new ADR — architecture-strategist verified). Optionally
  broaden the `connectedRepoPlugin` description at `model.c4:268-270` to note the CWD-shell-out face is also
  closed (advisory; the "INERT for the SDK" claim is unaffected either way).
- **File a follow-up issue** for the two distinct residual vectors this PR does NOT close, so the ADR does
  not imply blanket closure: (a) the **repo-root `scripts/` CWD-shadow class** (`${CLAUDE_PLUGIN_ROOT}`
  cannot anchor it — architecture:282, compound:254, review:272, preflight:909, feature-tweet, ship, …);
  (b) the **`taste-profile-update.sh` siblings** in `brainstorm:426`, `frontend-design:51,61` (same script,
  outside enumerated families; lower-stakes, not a secret gate).

### Phase 4 — Verify (no code change to safe-bash.ts)

Run the coupling + safe-bash suites (green) and the AC greps. Confirm `safe-bash.ts` unmodified and
`git diff --stat` shows only the 14 SKILL.md + the ADR (+ this plan's artifacts).

## Files to Edit

Redaction gates (Phase 1): `plugins/soleur/skills/legal-generate/SKILL.md`,
`plugins/soleur/skills/incident/SKILL.md`, `plugins/soleur/skills/linear-fetch/SKILL.md`.

Bulk (Phase 2): `plugins/soleur/skills/{trigger-cron,skill-security-scan,skill-creator,plan,compound-capture,kb-search,harvest-debt,seo-aeo,drain-labeled-backlog,constraint-scaffold,model-launch-review}/SKILL.md`.

Architecture (Phase 3): `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` (+ optional `knowledge-base/engineering/architecture/diagrams/model.c4` description line).

**Explicitly NOT edited (documented exclusions):**
- `apps/web-platform/server/safe-bash.ts` — **no change** (no new `list`/`ls`-class verb; Risks R1 + security sign-off).
- `compound-capture:135`, `kb-search:58,166` — `generate-kb-index.sh` targets a **repo-root** script, not plugin-deployed.
- `community/SKILL.md:75–78`, `provision-*`, `flag-*`, `user-set-role`, all `*.test.sh`, scripts-invoked-by-scripts, repo-root `scripts/` execs in non-enumerated families — out of scope (operator-run/CI-run/distinct-vector).

## Files to Create

None (a follow-up GitHub issue is created via `gh`, not a file).

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — broad `.sh` grep over the 14 families** returns only `${CLAUDE_PLUGIN_ROOT}` hits + the one documented prose carve-out (`plan:960` cites `…/run-scan.sh:34` as a code-location, not an invocation):
   `git grep -nE 'plugins/soleur/skills/[^ ]+\.sh' -- $(for f in legal-generate incident linear-fetch trigger-cron skill-security-scan skill-creator plan compound-capture kb-search harvest-debt seo-aeo drain-labeled-backlog constraint-scaffold model-launch-review; do echo plugins/soleur/skills/$f; done)` → every hit contains `CLAUDE_PLUGIN_ROOT` or is `plan/SKILL.md:960`.
2. **AC1-EXT — generalized completeness sweep** (catches the AC1-blind anchors: `.py`, `plugins/soleur/scripts/` non-`skills/`, bare `scripts/`/`./scripts/`):
   `git grep -nE '(bash|python3?|sh)[[:space:]]+"?\$?\{?\.?/?(plugins/soleur/(skills/[^ ]*/)?scripts|scripts)/[^ ]+\.(sh|py)' -- <the 15 family dirs> | grep -v CLAUDE_PLUGIN_ROOT | grep -v generate-kb-index` → **0 hits**. Plus the bare-exec `.py` code-block form: `git grep -nE '^\s*"?scripts/[A-Za-z0-9_/-]+\.(sh|py)' -- plugins/soleur/skills/skill-creator/SKILL.md | grep -v CLAUDE_PLUGIN_ROOT` → **0**. (Prose-only mentions — `rotate_pdf.py` illustrative, named-script references at skill-creator:139/208 — carry no exec verb and are legitimately untouched.)
3. **AC2 — bare-anchor redaction-gate sweep** (broad grep is blind to these): `git grep -nE 'bash "?\.?/?scripts/(redact-sentinel|redact-linear-urls)\.sh' -- plugins/soleur/skills/incident/SKILL.md plugins/soleur/skills/linear-fetch/SKILL.md` → **0 hits**.
4. **Redaction-gate sites server/CLI-correct:** the three gate invocations each expand to `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/…`. Server: var always set → deployed root, `$(…)` never runs. CLI: var unset → git-root checkout regardless of CWD (exercised by T-CLI below).
5. **`plugin-root-list-carveout-coupling.test.ts` green with ZERO `safe-bash.ts` change** (denylist therefore structurally unchanged — no `SHELL_METACHAR_DENYLIST` weakening): `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-list-carveout-coupling.test.ts test/safe-bash.test.ts test/permission-callback-safe-bash.test.ts` → pass; `git diff --name-only origin/main -- apps/web-platform/server/safe-bash.ts` → empty.
6. **Plugin component suite green** (no `description:` frontmatter touched): `plugins/soleur/test/` passes.
7. **security-sentinel sign-off** recorded at review (the single-user-threshold gate): confirms no new auto-approved verb and no denylist relaxation. (`trigger.sh --list` is a flag on a non-git-worktree script — review-gated before and after, unchanged.)
8. **ADR-093 amendment present**, scoped to the enumerated families; **follow-up issue filed** for the repo-root `scripts/` class + `taste-profile-update.sh` siblings. PR body uses `Closes #6154`.
9. **Diff scope** — `git diff --name-only origin/main` = the 14 SKILL.md + the ADR (+ optional model.c4 line) + this plan's own artifacts, nothing else.

## Domain Review

**Domains relevant:** Engineering / Security (single-domain infrastructure-tooling change).

Product/UX = NONE (mechanical UI-surface scan of Files-to-Edit: zero `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`). No Finance / Legal / Sales / Marketing / Support / Ops implications.

### Security
The security invariant (no new auto-approval, no denylist weakening, three redaction gates server/CLI-correct)
is encoded in AC2/AC4/AC5/AC7 and signed off by **security-sentinel** (verified against `safe-bash.ts`,
`agent-env.ts`, `agent-runner-query-options.ts`, the coupling test) + **user-impact-reviewer** at review.
No safe-bash code change.

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-093** (extension, not new decision — architecture-strategist verified: Decision unchanged,
Slices B/C already folded in as in-place amendments; #6154 is Slice D). Flip the residual-surface
consequence to CLOSED, **scoped to the enumerated families**, enumerate them, cite this PR.

### C4 views
**No C4 impact.** All three model files read. Enumeration (already-modeled): external human actors — none
new (`contributor`, `model.c4:19-25`); external systems — none new (`connectedRepoPlugin`, external/UNTRUSTED,
`model.c4:268-271`, the exact threat mitigated); containers/data-stores — none touched; access relationships —
none change (`connectedRepoPlugin -> skillloader` boundary edge `model.c4:326`, `claude -> skillloader`
deployed-root edge `model.c4:316` both unchanged). No element description is falsified. Optional refinement:
broaden the `connectedRepoPlugin` description to name the CWD-shell-out face (advisory, non-blocking).

### Sequencing
None — single atomic PR; the ADR amendment ships with the migration.

## Observability

No new *runtime* code/infra surface (SKILL.md prose + one ADR). The observable surface is **migration
correctness**, gated deterministically at CI/local time; the redaction-gate sites additionally fail closed
at runtime. 5-field schema:

```yaml
liveness_signal:
  what: "grep + vitest assertions (AC1/AC1-EXT/AC2/AC5) that every migrated invocation carries ${CLAUDE_PLUGIN_ROOT} and the safe-bash carve-out stays in lockstep (coupling test)"
  cadence: "every CI run (apps/web-platform vitest + plugins/soleur/test) and on-demand via the AC greps"
  alert_target: "CI red — the merge is gated on the vitest + plugin test suites (PR check failure blocks merge)"
  configured_in: "apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts + apps/web-platform/test/safe-bash.test.ts + plugins/soleur/test/"
error_reporting:
  destination: "agent transcript (command stderr) for a wrong path; a redaction-gate resolution failure surfaces as the shim's fail-closed halt in the legal-generate/incident/linear-fetch flow; a server-side var-unset regression throws via assertTrustedPluginPath into the existing dispatch error path (Sentry)"
  fail_loud: "yes — a mistyped path yields a loud 'No such file' or a fail-closed halt; never a silent wrong behavior"
failure_modes:
  - mode: "migrated path resolves to the untrusted workspace copy (server-side CLAUDE_PLUGIN_ROOT-unset regression)"
    detection: "CLAUDE_PLUGIN_ROOT always injected on both factories (Slice B agent-env.ts); assertTrustedPluginPath loaded-gun guard catches a regression"
    alert_route: "production exception (Sentry) via the buildAgentQueryOptions chokepoint"
  - mode: "residual un-migrated site invisible to the broad grep (bare-scripts / non-skills / .py anchor)"
    detection: "AC1-EXT generalized sweep + AC2 redaction-gate sweep return 0"
    alert_route: "CI red / review gate"
  - mode: "safe-bash carve-out drift (a new list/ls emission not in EXACT_LITERAL_SAFE_COMMANDS)"
    detection: "plugin-root-list-carveout-coupling.test.ts membership assertion (directory-walk over live SKILL.md tree)"
    alert_route: "CI red"
logs:
  where: "no new log surface — SKILL.md prose edits emit no runtime logs; the redaction engines' existing findings output is unchanged"
  retention: "n/a — no new persistent log introduced"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-list-carveout-coupling.test.ts test/safe-bash.test.ts && git grep -nE 'bash \"?\\.?/?scripts/(redact-sentinel|redact-linear-urls)\\.sh' -- plugins/soleur/skills/incident plugins/soleur/skills/linear-fetch | grep -v CLAUDE_PLUGIN_ROOT || echo CLEAN"
  expected_output: "vitest: all pass; grep tail prints CLEAN (no residual bare-anchor redaction-gate invocation)"
```

## Test Scenarios

The ACs are the checkable post-conditions; only the net-new behavior not already covered by an AC is
listed here.

- **T-CLI (net-new):** with `CLAUDE_PLUGIN_ROOT` unset, run from a subdirectory — `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh` and the linear-fetch equivalent resolve to the repo checkout (git-root, CWD-independent). Exercises AC4's CLI-correct half.

## Sharp Edges

- **The broad `.sh` grep is blind to three anchor shapes.** (a) bare `scripts/`/`./scripts/` (incident:217, linear-fetch:79) — no `plugins/soleur/skills/` prefix; (b) `plugins/soleur/scripts/` non-`skills/` (plan:329); (c) `.py` execs (compound-capture:592, skill-creator:144/185/191). AC1-EXT + AC2 are the dedicated sweeps; without them a reviewer greens AC1 while a redaction gate or a `.py` exec stays un-migrated. This is the enumeration-bug class both reviews caught.
- **Prose citation false-positives.** `plan:960` cites `…/run-scan.sh:34`; skill-creator:139/208 name `init_skill.py`/`package_skill.py` in explanatory prose; skill-creator:53/119 mention `rotate_pdf.py` as illustrative-not-included. None are invocations — do NOT "migrate" them. The exec-verb-prefixed / code-block-anchored AC greps naturally exclude them.
- **`generate-kb-index.sh` is a decoy.** Repo-root `scripts/`, not plugin-deployed; `${CLAUDE_PLUGIN_ROOT}` does not anchor it. Leave compound-capture:135 / kb-search:58,166 untouched.
- **Preserve the exact fallback anchor.** `./plugins/soleur` stays `./plugins/soleur`; bare `plugins/soleur` stays bare; git-root form only for the three redaction gates. The Phase 2 anchor column is load-bearing — do not homogenize (the coupling-test drift-guard and Slice C convention key on preserved anchors).
- **`$(…)` in the redaction-gate fallback is safe and must NOT get a safe-bash carve-out.** It never matches `EXACT_LITERAL_SAFE_COMMANDS` and never executes on the server (var always set). Adding a carve-out would be wrong.
- **Scope the ADR "CLOSED" claim.** Closure is bounded to plugin-deployed skill/plugin-script shell-outs in the 14 enumerated families. The repo-root `scripts/` CWD-shadow vector and the `taste-profile-update.sh` siblings in brainstorm/frontend-design are a distinct, tracked follow-up — do not let the amendment imply blanket plugin-wide closure.

## Risks & Mitigations

- **R1 — safe-bash carve-out drift.** *Risk:* a migrated site emits a new auto-approvable read-only verb. *Reality (security-verified):* none of the 14 families emit a `worktree-manager.sh list|ls` (the only carved-out family); the coupling regex is git-worktree-scoped and produces no new match. `trigger.sh --list` is a flag on a different script, review-gated before and after. *Mitigation:* AC5 asserts empty safe-bash.ts diff + coupling test green.
- **R2 — space-bearing git-root path.** *Mitigation:* the three redaction-gate rewrites quote the whole expansion (`bash "…"` / quoted `SENTINEL=`).
- **R3 — incomplete family sweep.** *Mitigation:* AC1 + AC1-EXT + AC2 grep the *whole* family dirs across `.sh` + `.py` + all anchors — this is what surfaced linear-fetch, plan:329, and the `.py` sites at review.
- **R4 — redaction-gate regression (single-user threshold).** *Mitigation:* all three gates fail **closed** on resolution error; AC4 + `user-impact-reviewer` verify server/CLI correctness; T-CLI exercises CLI resolution from a subdirectory.
- **R5 — ADR overclaims closure.** *Mitigation:* Phase 3 scopes the "CLOSED" language to the enumerated families and files a follow-up for the distinct residual vectors (repo-root `scripts/`, taste-profile siblings).

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue names any of the 14 SKILL.md files or ADR-093.)
