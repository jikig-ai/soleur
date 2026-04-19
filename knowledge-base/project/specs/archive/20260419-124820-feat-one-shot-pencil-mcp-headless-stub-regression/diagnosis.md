# Phase 1 Diagnosis — Pencil MCP "headless stub" regression

Date: 2026-04-19
Branch: feat-one-shot-pencil-mcp-headless-stub-regression

## T1.1 Adapter drift check

| File | SHA-256 | Lines |
|------|---------|-------|
| `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` (installed, 2026-03-25) | `31b572c46a288793ed42eeba84a281a437c84ac51a5f05142f0ca44b3b7b8f99` | 603 |
| `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` (repo, 2026-04-18) | `0f6ff734854909a550902095b45465acdf63c38fb966977ad55898e86a1b2b85` | 654 |

**Hashes differ. Hypothesis B (stale install) CONFIRMED.** Installed adapter is 24 days and 51 lines behind repo source. Missing fixes include `Invalid properties:` error detection, `enrichErrorMessage` import, `sanitizeFilename` import, export-nodes name-based renames, positional insert M() hint.

## T1.2 Env presence check

`claude mcp get pencil` output (user scope):

```
Environment:
  PENCIL_CLI_KEY=pencil_cli_576fd1767b09b064df2e9bf0b0798d751204c9f8
```

Doppler `soleur/dev` `PENCIL_CLI_KEY`: matches baked value (prefix `pencil_cli_576fd176...c9f8`).

**Hypothesis A (missing key) NOT ACTIVE in the current environment.** Key is present and matches Doppler. However, the installed adapter (24 days old) may have lacked recent auth-error classification logic — so even with a valid key, transient auth failures or rate-limit responses could have surfaced as unclassified text passed through as "success."

## T1.3 Live MCP round-trip

Deferred to T5.2 (post-fix validation). `mcp__pencil__get_style_guide_tags` ran successfully during planning — confirms read transport works.

## T1.4 Output-path audit

Residual references to deprecated `knowledge-base/design/`:

| File | Line | Category | Action |
|------|------|----------|--------|
| `knowledge-base/project/plans/2026-03-12-refactor-kb-domain-structure-plan.md` | 50, 110, 159 | Historical plan — documents the #566 migration | Leave (historical narrative) |
| `knowledge-base/project/plans/2026-02-27-refactor-sync-landing-page-pen-plan.md` | 33, 50, 192, 200, 232 | Pre-#566 plan | Leave (archived context) |
| `knowledge-base/project/plans/2026-03-10-feat-x-twitter-banner-plan.md` | 173, 229, 402, 408, 424 | Pre-#566 plan | Leave (archived context) |
| `knowledge-base/project/specs/feat-x-twitter-banner/tasks.md` | 36 | Merged feature's task record | Leave (historical record) |
| `knowledge-base/marketing/brand-guide.md` | 312 | **Active** brand guide — stale source-file path | **FIX** — update to `knowledge-base/product/design/brand/brand-x-banner.pen` |
| `plugins/soleur/agents/product/design/ux-design-lead.md` | (none) | Agent prompt | Already clean (exit code 1 on grep) |
| `plugins/soleur/skills/pencil-setup/SKILL.md` | (none) | Skill doc | Clean |

## T1.4b Related CLI form check

`plugins/soleur/skills/pencil-setup/SKILL.md` contains `claude mcp list -s user` (broken form — `-s` option was dropped). Matches T2.6 expectation.

## T1.5 Hypothesis ranking (final)

| Hypothesis | Status | Evidence |
|------------|--------|----------|
| A. Missing `PENCIL_CLI_KEY` at registration | **Inactive now, likely active during failing session** | Key present/matching in this session; the failing `/ship` session could have registered before Doppler value was current OR inherited a stale registration |
| B. Stale installed adapter | **CONFIRMED** | Installed 603 lines vs repo 654; no drift detection in `check_deps.sh` |
| C. ux-design-lead wrote to deprecated path | **CONFIRMED (on feat-plan-concurrency-enforcement branch)** | `cbd571d1` on other branch committed placeholder at `knowledge-base/design/upgrade-modal-at-capacity.pen`; canonical path is `knowledge-base/product/design/{domain}/` |

**Primary failure chain (reconstructed):** The agent's invocation of `ux-design-lead` on `feat-plan-concurrency-enforcement` used the stale installed adapter (B). When a mutation errored (could be auth, schema, or transient), the stale adapter's weaker error classification let the failure pass through as text. The auto-save ran anyway, producing a 0-byte file. The ux-design-lead agent, receiving a non-error MCP response but a 0-byte file, fabricated the "headless stub" narrative instead of reading the actual error text. The agent also used the deprecated output directory `knowledge-base/design/`, which no automated check catches.

## Scope notes for Phase 3

- **T3.7 (delete placeholder):** The placeholder `knowledge-base/design/upgrade-modal-at-capacity.pen` is committed on `feat-plan-concurrency-enforcement`, not on this branch. We will file a follow-up issue instead of cross-branch deletion. The brand-guide reference IS fixable here.
- **T2.5 (ux-design-lead regression guard):** Already passes. Keep as guard.
- **T2.6 (SKILL.md CLI form):** Fails RED as expected.
