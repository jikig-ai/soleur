---
title: "feat: gdpr-gate v2 layers (auth-sessions, frontend, testing-seeding, legal-consent) + repo-scan mode"
date: 2026-05-10
type: feat
issue: 3518
v1_pr: 3501
draft_pr: 3522
branch: feat-gdpr-gate-v2-layers
worktree: .worktrees/feat-gdpr-gate-v2-layers
adr: ADR-026
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: skill-extension
brainstorm: knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md
status: draft
---

# Plan: gdpr-gate v2 — re-lifted layers + `--repo-scan` mode

Closes #3518 at merge. Extends v1 (PR #3501, ADR-026) with three separately-active layer files re-lifted from `gosprinto/compliance-skills@7b58d68`, promotes `legal-consent.md` to a separately-active layer, and adds `/soleur:gdpr-gate --repo-scan` for whole-repo audits — gated by an NFR-014-compliant path deny-list.

## Overview

v1 shipped three separately-active layer files (`api-layer.md`, `data-in-transit.md`, `data-lifecycle.md`) plus a prose-shaped `legal-consent.md` (no `check_id` markers). The brainstorm explicitly deferred `auth-sessions.md`, `frontend.md`, `testing-seeding.md` and the `--repo-scan` mode to v2 because of credential-leak risk. Issue #3518 unbundles those four deliverables.

**Scope of this PR (4 deliverables):**

1. **Lift three layer files verbatim** from `gosprinto/compliance-skills@7b58d68` with attribution headers + NOTICE rows: `auth-sessions.md` (A-01..A-07), `frontend.md` (F-01..F-06), `testing-seeding.md` (TS-01..TS-05).
2. **EU-extend each lifted file** with a footer block: Art. 32(1)(b) confidentiality framing for auth-sessions; ePrivacy/TTDSG strict-opt-in clarifying note for frontend; Art. 32 pseudonymization in non-prod for testing-seeding. Footer-only — body remains verbatim per MIT lift hygiene.
3. **Promote `legal-consent.md` to a layer** by adding `LC-01..LC-05` `check_id` markers over the existing prose. File stays at `references/legal-consent.md` (no move) — content is rewritten in-place to match the layer-file template (`What to grep:` / `Flag when:` / `Fix pattern:` / `Regulation:`).
4. **Add `/soleur:gdpr-gate --repo-scan` mode** with: sole-arg sentinel detection, `git ls-files -c -o --exclude-standard` source, path deny-list at `plugins/soleur/skills/gdpr-gate/scripts/path-denylist.txt`, two-key path-allowlist env var (`GDPR_GATE_REPO_SCAN_ALLOW_PATHS`, colon-separated literal paths), 25-files-per-Haiku batching, inline-only output.

**Out of this PR (deferred to follow-ups, milestoned at plan exit):**

- New AGENTS.md rule for `--repo-scan` (intentionally NOT added — rule-budget pressure; existing `hr-gdpr-gate-on-regulated-data-surfaces` already delegates trigger surface to SKILL.md, and CTO+brainstorm align on extending SKILL.md only).
- Per-layer-id severity fixtures across all check_ids (we add fixtures for one check per new layer to anchor the test, defer full coverage).
- Historical-migration Critical-finding suppression UX (sharp-edge documentation only — no new code path).

## User-Brand Impact

Carry-forward from `knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md` §"User-Brand Impact". Threshold is `single-user incident` because `--repo-scan` reads files that may contain credentials (`.env*`, fixtures, secrets/), and a single leaked `.env` value in agent context becomes a Chapter V transfer to Anthropic plus an on-disk transcript artifact (per `hr-never-paste-secrets-via-bang-prefix`).

**If this lands broken, the user experiences:** a `--repo-scan` invocation that reads `apps/web-platform/.env` (real prod creds, not `.env.example`), forwards values to Haiku as part of the audit prompt, and writes the values to the operator's transcript — which then enters Soleur's prompt-cache, Anthropic's API logs, and the agent-disk transcript. The user's own credential becomes the artifact the gate was supposed to protect.

**If this leaks, the user's [credentials / customer PII] is exposed via:** (a) `.env*` content read by the scanner and forwarded to the model, (b) test fixtures containing prod-shape data inadvertently included in scan corpus, (c) `compliance-posture.md` row that quotes a finding's matched-line which contains a column value rather than a column name.

**Brand-survival threshold:** `single-user incident`.

**D-defenses (each independently load-bearing — collapse of any one is a regression):**

| ID | Defense | Mechanism | Test surface |
|---|---|---|---|
| D1 | **Path deny-list before any read** | `path-denylist.txt` consulted before `git ls-files` results enter the scan corpus | `gdpr-gate-repo-scan.test.ts` asserts deny-list patterns are skipped |
| D2 | **`git ls-files -c -o --exclude-standard` source** | Index + untracked, respecting `.gitignore`; avoids working-tree rename-laundering attack against allowlist eval (per learning `2026-05-04-gitleaks-secret-scanning-floor-rollout.md` pattern (c)) | Test asserts `find`-style walk is NOT used; mock fixture verifies symlink-following is off |
| D3 | **Path-allowlist env var (not boolean)** | `GDPR_GATE_REPO_SCAN_ALLOW_PATHS=p1:p2` colon-split into a literal-string set; only exact-match paths bypass D1 (no globs accepted) | Test asserts blanket boolean `=true` does NOT bypass deny-list; only literal-path entries do |
| D4 | **Inline-only output** | Findings emitted to stdout/conversation only; no `compliance-posture.md` write, no fixture write, no log-file persistence | Test greps SKILL.md for "inline-only"; aggregate output never persists to a committed path |
| D5 | **Schema-only prompt invariant (carried from v1)** | Prompt template's "DO NOT INCLUDE COLUMN VALUES" directive applies to `--repo-scan` identically to `--diff` mode | v1 `gdpr-gate.test.ts:147` already asserts; extend the assertion to cover the repo-scan code path |

**Why D1-D5 don't collapse:** Per `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`, "D1 ⟹ D5" never holds for credential-leak. D1 stops file-discovery; D2 makes D1 robust against rename attacks; D3 enforces explicit operator intent on the bypass path; D4 prevents aggregation-as-attack-surface (`2026-02-16-inline-only-output-for-security-agents.md`); D5 is the prompt-side invariant orthogonal to filesystem-side D1-D4. Each defense corresponds to a distinct attack model.

CPO sign-off required at plan time per `hr-weigh-every-decision-against-target-user-impact`. `user-impact-reviewer` invoked at `/review` time.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (verified) | Plan response |
|---|---|---|
| Issue body: "currently bundled into the v1 `references/legal-consent.md`" | `legal-consent.md` is its OWN file already (47 lines, prose-shaped, no `check_id` markers). Nothing is "bundled" into it from elsewhere. | Plan re-frames the deliverable as **"promote prose-shaped `legal-consent.md` to layer-shaped (add LC-01..LC-05 markers)"** — no file move, no extraction. |
| Issue body + brainstorm Lifted Files Inventory: "auth-sessions (6.8 KB, 7 checks A-01..A-07)" | Verified on upstream `main@7b58d68`: 6806 B, 276 lines, 7 checks A-01..A-07 — exact match. | Lift verbatim; pin same SHA. |
| Issue body: "frontend.md" | Verified: 5946 B, 235 lines, **F-01..F-06 (6 checks)** — brainstorm claim of "5.9 KB" is correct; brainstorm did not enumerate count. | Plan records 6 checks; tests anchor at F-01. |
| Issue body: "testing-seeding.md" | Verified: 6104 B, 242 lines, **TS-01..TS-05 (5 checks)**. Note prefix is `TS-`, NOT `T-` (the v1 data-in-transit prefix). | Plan uses `TS-` prefix (upstream-faithful); SKILL.md table lists exact check_ids per layer. |
| Issue body: "Re-lift against then-current upstream SHAs" | Verified: upstream `main` SHA is **unchanged since v1 lift** (`7b58d68461cb1fc033a063e34cc9de63d0b4144b`, 2026-05-08). No drift to absorb. | Plan re-pins same commit SHA but records new per-blob SHAs (auth-sessions: `71dd9d01...`, frontend: `5f39e08f...`, testing-seeding: `a2f29941...`) in NOTICE. v2 NOTICE adds rows to the existing `## gosprinto/compliance-skills (MIT)` section (single block, mixed-vintage rows acceptable since commit SHA matches). |
| ADR-026 NFR-014: "skill must not read `.env*` or fixtures matching secret-scan ignore" | Verified verbatim; `.env*` is the explicit constraint, "secret-scan ignore" refers to `.gitleaks.toml` allowlist (lines 73-79, 92). | D1 path deny-list mirrors `.gitleaks.toml` allowlist + extends with `.npmrc`, `.dockercfg`, SSH key shapes, AWS/k8s creds — see `path-denylist.txt` design below. |
| Brainstorm Non-Goals: "Repo-scan mode — defer to v2 (credential-leak risk)" | Confirmed; v1 plan AC-PM-2 names this as the v2 follow-up. | This PR delivers it; defenses D1-D5 named explicitly. |
| Brainstorm assumed all 7 references treated alike in SKILL.md `Reference layers:` block | Verified `SKILL.md:55-62` lists all 7 in one block — does not distinguish "layer-shaped" from "prose-shaped". | Plan reorganizes the block into two subsections: **"Active layers (with `check_id` markers)"** listing the 4 lifted-and-EU-extended files + the 3 v1 layers, and **"Reference catalogues"** for `fields.md`, `leakage-vectors.md`, `non-negotiables.md`. After v2: 7 active layers + 3 reference catalogues. |

## Files to Create

| Path | Purpose | Source |
|---|---|---|
| `plugins/soleur/skills/gdpr-gate/references/layers/auth-sessions.md` | Active layer A-01..A-07 + Art. 32(1)(b) footer | Lifted verbatim from upstream blob `71dd9d01fe55d3e58f8b35f1cf745d47ba5f0985`; footer is Soleur-authored |
| `plugins/soleur/skills/gdpr-gate/references/layers/frontend.md` | Active layer F-01..F-06 + ePrivacy/TTDSG strict-opt-in footer | Lifted verbatim from upstream blob `5f39e08fe2404759d7cbdbdea54a4f6210b91b8f`; footer Soleur-authored |
| `plugins/soleur/skills/gdpr-gate/references/layers/testing-seeding.md` | Active layer TS-01..TS-05 + Art. 32 pseudonymization footer | Lifted verbatim from upstream blob `a2f299418a5f85246fd2203475d89106936f7a72`; footer Soleur-authored |
| `plugins/soleur/skills/gdpr-gate/scripts/path-denylist.txt` | Single source of truth for `--repo-scan` deny-list (7 patterns) | New; line-oriented file, `#` comments allowed, one extended-regex pattern per line |
| `plugins/soleur/skills/gdpr-gate/scripts/repo-scan.sh` | Implements `--repo-scan` walker (D1-D4 enforcement layer) | New; ≤300 lines; called by SKILL.md when `$ARGUMENTS` trims to exactly `--repo-scan` |
| `plugins/soleur/test/gdpr-gate-repo-scan.test.ts` | Test suite for `--repo-scan` defenses | New; runs via `bun test plugins/soleur/test/`; covers D1-D4 + sentinel parsing + CI refusal |
| `plugins/soleur/skills/gdpr-gate/references/legacy/legal-consent-v1-prose.md` | Archived v1 prose-shaped legal-consent (one release cycle) | Move target for v1 file; preserves regulatory citations + CLO framing for provenance |
| `knowledge-base/project/specs/feat-gdpr-gate-v2-layers/spec.md` | Spec doc | Generated alongside this plan |
| `knowledge-base/project/specs/feat-gdpr-gate-v2-layers/tasks.md` | Tasks breakdown | Generated after plan-review |

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/gdpr-gate/SKILL.md` | (a) Add a 1-line bullet in the opening section (between line 8 and line 12) calling out `--repo-scan` exists as a manual mode — operators reaching SKILL.md from `AGENTS.md hr-gdpr-gate-on-regulated-data-surfaces` learn about the new mode in the first 5 lines. (b) Reorganize `Reference layers:` (lines 55-62) into "Active layers" + "Reference catalogues" subsections; add the 4 new active layers. (c) Add new section `## --repo-scan mode` between `## Disclaimer (always first)` and `## Path globs (canonical)` covering: sole-arg trigger, deny-list, env-var, batching contract, inline-only output, **canonical-regex source-of-truth note** (regex is sourced from SKILL.md §"Path globs (canonical)" — `repo-scan.sh` greps it from this file rather than redefining). (d) Extend `## 5 mandatory v1 checks (FR4)` table with a note: `--repo-scan` invokes the same 5 checks PLUS the layer-id checks across all 7 active layers. (e) Add sharp-edges: (i) "Historical-migration Critical findings tracked in compliance-posture.md, not blockers — amendment migrations carry their own data-integrity risk." (ii) "Bash `[[ =~ ]]` regex semantics in `repo-scan.sh` are locale-dependent (`LC_ALL=POSIX` is set in the script); contributors editing `path-denylist.txt` must verify on both Linux + macOS." |
| `plugins/soleur/skills/gdpr-gate/NOTICE` | Add 3 rows to `## gosprinto/compliance-skills (MIT)` table (auth-sessions, frontend, testing-seeding) with verified blob SHAs. Update lift-date footer line to reflect v2 update. Remove the "NOT lifted in v1" line about the three layer files. Add a new `## Soleur-authored layers` section noting `legal-consent.md` was rewritten from prose to layer-shape in v2 (with a pointer to the archived `references/legacy/legal-consent-v1-prose.md` for provenance). |
| `plugins/soleur/skills/gdpr-gate/references/legal-consent.md` | **Move-then-rewrite** (Kieran P1.3): (a) `git mv references/legal-consent.md references/legacy/legal-consent-v1-prose.md` first, preserving the v1 prose + git history. (b) Write a fresh `references/legal-consent.md` with: `<!-- Soleur-authored — see NOTICE -->` header, `## When This Layer Loads` section, 5 check blocks `LC-01: ePrivacy cookie consent`, `LC-02: Art. 7 freely-given consent`, `LC-03: Art. 13/14 disclosure`, `LC-04: Art. 35 DPIA trigger`, `LC-05: Withdrawal-as-easy-as-giving`. Each block uses the standard `What to grep:` / `Flag when:` / `Why it matters:` / `Fix pattern:` / `Regulation:` template. The legacy/ archive carries a one-line header noting it was preserved for v1 provenance and will be removed at v3 (one release cycle). |
| `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` | NO CHANGES. Lefthook advisory hook continues to fire on staged-path canonical regex. `--repo-scan` is invoked manually via SKILL.md, not via lefthook. |
| `plugins/soleur/test/gdpr-gate.test.ts` | (a) Extend `LIFTED_REFS` array (lines 22-28) with the 3 new layers. (b) Add per-layer attribution-header assertion (line 1 = `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->`). (c) Add NOTICE-row parity assertion (every entry in `LIFTED_REFS` must have a corresponding row in NOTICE with a 40-char blob SHA). (d) Add `legal-consent.md` to a new `SOLEUR_AUTHORED_LAYERS` array; assert layer-shaped header (`<!-- Soleur-authored — see NOTICE -->`) and presence of `LC-01` marker. (e) Vendor-surface scrub assertion already covers all `LIFTED_REFS` — no new test. |
| `.gitleaks.toml` | NO CHANGES. The path-denylist is a v2-internal file; it MIRRORS gitleaks allowlist semantics but is not derived from .gitleaks.toml at runtime (CTO §1: drift between them is a regression vector — addressed by parity test in `gdpr-gate-repo-scan.test.ts`). |
| `lefthook.yml` | NO CHANGES. Canonical regex is unchanged; lefthook hook is unchanged. |
| AGENTS.md | NO CHANGES. `hr-gdpr-gate-on-regulated-data-surfaces` already delegates trigger-surface to SKILL.md. Per CTO §8 + `cq-agents-md-tier-gate` (domain-scoped insights route to owning skill, not AGENTS.md), all `--repo-scan` enforcement lives in SKILL.md and `path-denylist.txt`. |

## `--repo-scan` Design Specification

### Argument detection (sole-arg sentinel)

SKILL.md prompt instruction (Soleur-style, parsed by the dispatching agent):

> When invoked with `$ARGUMENTS`, trim leading/trailing whitespace. If the trimmed value equals **exactly** `--repo-scan` (no spaces, no quotes, no additional tokens), enter repo-scan mode. Any other value — including `--repo-scan apps/web-platform`, `repo scan`, or `"--repo-scan section of the repo"` — falls through to v1 scope-string mode and is forwarded verbatim to the prompt.

This avoids the substring-match false-fire CTO flagged (§6). For future scope-narrowing, a separate `--repo-scan-path=<glob>` flag would be added.

### File source: `git ls-files -c -o --exclude-standard`

Per CTO §2: covers staged-uncommitted `.env*` paths an operator just dropped (committed-only would miss them). `--exclude-standard` honors `.gitignore` so we don't walk `node_modules/` or `.next/`.

```bash
git ls-files -c -o --exclude-standard
```

Submodules excluded by default (no `--recurse-submodules` flag). Symlinks not followed (git's behavior).

### Path deny-list — `path-denylist.txt`

Single source of truth at `plugins/soleur/skills/gdpr-gate/scripts/path-denylist.txt`. Line format: one extended-regex pattern per line, `#` lines are comments, blank lines ignored. The pattern is matched against each path with `bash` `[[ "$path" =~ $pattern ]]`.

**v2 deny-list contents (7 patterns, each verified against `git ls-files | grep -E` at plan-write time; trimmed from 14 per plan-review):**

| # | Pattern | Hits today | Reason |
|---|---|---|---|
| 1 | `^\.env(\..+)?$\|/\.env(\..+)?$` | 1 (`.env.example` at repo root, plus app-scoped) | NFR-014 explicit; covers `.env`, `.env.local`, `.env.production`, etc. |
| 2 | `(^\|/)secrets/` | 4 | secrets-named directory at any depth |
| 3 | `\.(pem\|key\|crt\|p8\|pfx\|jks\|keystore\|asc\|ppk)$` | 0 — defense-in-depth (cheap, broad, plausible drift) | private keys / cert chains / PGP |
| 4 | `(^\|/)__synthesized__/\|(^\|/)__goldens__/\|(^\|/)__snapshots__/\|\.snap$` | 1 (`__synthesized__`) | Test fixtures with realistic-shaped data |
| 5 | `^apps/web-platform/test/fixtures/` | 4 | Existing fixture dir |
| 6 | `^plugins/soleur/skills/[^/]+/references/` | 76 | Gate's own layer files (mirrors `.gitleaks.toml` line 78) |
| 7 | `^knowledge-base/(?:project/)?(?:plans\|specs)/.*\.md$` | 2386 | Plan/spec docs (mirrors `.gitleaks.toml` line 77) |

Pattern 3 (private-key extensions) is the only zero-hit pattern retained — it is broad, cheap to maintain, and a plausible drift target if a future PR accidentally commits a `.pem`. Other zero-hit shapes (`.npmrc`, `.dockercfg`, SSH keys, AWS/k8s creds, build artifacts) are dropped: `.gitignore` already excludes the build artifacts; the credential shapes can be added if and when one lands in the repo. Per `hr-when-a-plan-specifies-relative-paths-e-g`, the negative-coverage-gate exemption applies to pattern 3; AC-DENYLIST-3 records the per-pattern `git ls-files | grep -E` evidence. The 7-pattern surface is the minimum needed for D1; over-broad patterns trade real-audit coverage for hypothetical drift insurance.

### Two-key path-allowlist env var

`GDPR_GATE_REPO_SCAN_ALLOW_PATHS=path1:path2:...` — colon-separated literal paths (no globs accepted; bash strict equality after split). Default unset → all deny-list patterns enforced.

**Two-clause typo defense (Kieran P1.1 — load-bearing):** every entry must satisfy BOTH:
1. **Match a deny pattern** — the entry references a path the deny-list would otherwise block (no point in allow-listing a non-blocked path).
2. **Exist in `git ls-files -c -o --exclude-standard`** — the path actually exists in the worktree at the moment of the scan.

If clause (1) fails, the script exits 1 with `bypass references non-blocked path: <path>` (operator probably typo'd). If clause (2) fails, the script exits 1 with `bypass references nonexistent path: <path>` (operator probably typo'd a real path). Without clause (2), a typo'd path that coincidentally matches a deny pattern (e.g., `apps/web-platform/secrets/api.json` when operator meant `secret/api.json`) silently bypasses — the deny pattern absorbs the typo, the actual path is never read, and the operator-intended file remains blocked. With both clauses, every typo surfaces.

**CI-environment refusal (Kieran P3.3 — structural mitigation for R5):** if both `$CI` and `$GDPR_GATE_REPO_SCAN_ALLOW_PATHS` are set, the script exits 1 with `allow-list bypass refused in CI environment`. Operator-only by construction — runbooks that set the var get caught at the script boundary, not by docs alone.

```bash
allow_paths_raw="${GDPR_GATE_REPO_SCAN_ALLOW_PATHS:-}"
if [[ -n "$allow_paths_raw" ]]; then
  if [[ -n "${CI:-}" ]]; then
    echo "gdpr-gate repo-scan: allow-list bypass refused in CI environment" >&2
    exit 1
  fi
  declare -a allow_paths=()
  IFS=':' read -ra allow_paths <<< "$allow_paths_raw"
  for ap in "${allow_paths[@]}"; do
    # Clause (1): must match at least one deny pattern.
    matched=0
    for dp in "${denylist_patterns[@]}"; do
      if [[ "$ap" =~ $dp ]]; then matched=1; break; fi
    done
    if (( matched == 0 )); then
      echo "gdpr-gate repo-scan: bypass references non-blocked path: $ap" >&2
      exit 1
    fi
    # Clause (2): must exist in git ls-files.
    if ! git ls-files -c -o --exclude-standard --error-unmatch -- "$ap" >/dev/null 2>&1; then
      echo "gdpr-gate repo-scan: bypass references nonexistent path: $ap" >&2
      exit 1
    fi
  done
fi

is_allowed() {
  local path="$1"
  for ap in "${allow_paths[@]:-}"; do
    if [[ "$path" == "$ap" ]]; then return 0; fi
  done
  return 1
}
```

The script emits `# bypass: <path>` to stderr when a deny-listed path is bypassed by the allow-list (audit trail).

### Batching: 25 files per Haiku call

Per CTO §4: 102 candidate files post-canonical-regex (current repo) / 25 = 4-5 batches. Each batch sends ≤25 file paths + ≤80 lines per file (head + grep-around-canonical-regex matches). Token estimate: ~3.5k input + ~500 output. Within v1's ≤4k-per-invocation contract (ADR-026 TR3).

Main agent (the dispatching skill) collects batched outputs, dedups by `(check_id, path, line)`, summarizes inline. **No persistence.**

### Inline-only output (D4)

Aggregate output emitted to stdout/conversation only. NEVER:

- Write to `compliance-posture.md` (operator-acknowledged path remains v1's manual flow).
- Write to a fixture, golden, or `__goldens__/` path.
- Persist to a log file under `~/.claude/` or any disk path.

Critical findings (Art. 9 column-name matches across the repo) trigger the v1 critical-finding flow verbatim — same operator acknowledgment, same `compliance-posture.md` row contract, same `compliance/critical` GitHub issue label. Historical-migration Critical findings (already documented as intentional in SKILL.md lines 149-151) are noted in the new sharp-edge.

### Schema-only invariant (D5)

The repo-scan prompt template inherits v1's `DO NOT INCLUDE COLUMN VALUES` directive verbatim (SKILL.md line 137). The directive is an existing test assertion; v2 does not modify it. v2 test extension asserts the directive is also present in the repo-scan code path's prompt construction.

## Implementation Phases

### Phase 1 — Layer file lifts (auth-sessions, frontend, testing-seeding)

For each of the three target files:

1. Fetch verbatim content from `gh api "repos/gosprinto/compliance-skills/contents/pii-detector/layers/<file>?ref=7b58d68461cb1fc033a063e34cc9de63d0b4144b" --jq '.content' | base64 -d > /tmp/<file>`. Pin to the **commit SHA** (not `main`) for reproducibility — even though the brand happens to be at `main` today, the URL-pinned SHA is the durable contract.
2. Verify per-blob SHA matches the table in this plan (`gh api "...?ref=<commit>" --jq '.sha'`). Abort the lift if SHA mismatch.
3. Write to `plugins/soleur/skills/gdpr-gate/references/layers/<file>` with attribution header **prepended** as line 1: `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->`.
4. Append the EU-extension footer block:
   - `auth-sessions.md`: Art. 32(1)(b) confidentiality framing — one paragraph, no new check_ids.
   - `frontend.md`: ePrivacy/TTDSG strict-opt-in clarifying note — references LC-01 from legal-consent layer.
   - `testing-seeding.md`: Art. 32 pseudonymization in non-prod note — references TS-01.
5. Run vendor-surface grep on the final file: `grep -E '(utm_source|utm_medium|sprinto\.com|<img|"Powered by"|"Sponsored by"|"Sprinto says"|"Sprinto recommends")' <file>` MUST return zero. If non-zero, scrub before commit.

Test gate (Phase 1 → 2): `bun test plugins/soleur/test/gdpr-gate.test.ts` passes the extended `LIFTED_REFS` assertion.

### Phase 2 — `legal-consent.md` archive-then-rewrite (prose → layer)

Per Kieran P1.3 (preserve provenance via archival, not in-place destruction):

1. `mkdir -p plugins/soleur/skills/gdpr-gate/references/legacy/`.
2. `git mv plugins/soleur/skills/gdpr-gate/references/legal-consent.md plugins/soleur/skills/gdpr-gate/references/legacy/legal-consent-v1-prose.md`. Preserves git history.
3. Prepend a one-line provenance header to the archived file: `<!-- Archived v1 prose-shape — preserved for one release cycle for regulatory-citation provenance. Will be removed at v3. -->`.
4. Write a fresh `plugins/soleur/skills/gdpr-gate/references/legal-consent.md`:
   - Line 1: `<!-- Soleur-authored — see NOTICE -->`.
   - `# Layer: Legal Consent (ePrivacy + GDPR Art. 7 / 13 / 14 / 35)`.
   - `## When This Layer Loads` section listing trigger conditions (cookie banner, consent column, Art. 13/14 disclosure prose, DPIA-trigger keywords).
   - 5 check blocks LC-01..LC-05 each with `What to grep:` / `Flag when:` / `Why it matters:` / `Fix pattern:` / `Regulation:`:
     - LC-01: ePrivacy cookie consent (opt-in not opt-out).
     - LC-02: Art. 7 freely-given consent (no pre-checked boxes; no consent-bundling).
     - LC-03: Art. 13/14 disclosure (purposes, lawful basis, retention, recipient categories).
     - LC-04: Art. 35 DPIA trigger (Art. 22 profiling, Art. 9 at scale, public-space monitoring).
     - LC-05: Withdrawal-as-easy-as-giving (Art. 7(3)).
5. Update NOTICE: add a `## Soleur-authored layers` section listing `legal-consent.md` (current) with a pointer to `references/legacy/legal-consent-v1-prose.md` for v1 prose lineage. `non-negotiables.md` is also Soleur-authored; add it to the same section.

### Phase 3 — SKILL.md reorganization + `--repo-scan` section

1. Reorganize `## Reference layers:` (currently lines 55-62) into two subsections:
   - **Active layers (with `check_id` markers)**: api-layer (AP-01..AP-07), data-in-transit (T-01..T-06 + DT-EU-CB), data-lifecycle (DL-01..DL-06), auth-sessions (A-01..A-07), frontend (F-01..F-06), testing-seeding (TS-01..TS-05), legal-consent (LC-01..LC-05).
   - **Reference catalogues**: fields.md, leakage-vectors.md, non-negotiables.md.
2. Insert new section `## --repo-scan mode` between `## Disclaimer (always first)` and `## Path globs (canonical)`. Section content (≤120 lines) covers: trigger-arg shape, source command, deny-list reference, env-var contract, batching, output contract, defense table reference (link to this plan).
3. Add sharp-edge bullet: "Historical-migration Critical findings (Art. 9 columns in pre-v1 migrations) are tracked in `compliance-posture.md` Active Items as documented gaps — they are NOT blockers because amendment migrations carry their own data-integrity risk. The `--repo-scan` operator-acknowledgment flow accepts a 'tracked, not amended' disposition."

### Phase 4 — `path-denylist.txt` + `repo-scan.sh`

1. Create `plugins/soleur/skills/gdpr-gate/scripts/path-denylist.txt` with the 7 patterns from this plan. Add header comment lines (`#`) explaining the file's role and the bash-regex semantics.

2. Create `plugins/soleur/skills/gdpr-gate/scripts/repo-scan.sh` (≤300 lines, pure bash — Kieran P2.1 budget):
   - `set -euo pipefail` + `LC_ALL=POSIX` (locale-determinism for `[[ =~ ]]`).
   - Source `path-denylist.txt` (loop into `declare -a denylist_patterns`, skip comments and blanks).
   - **Canonical-regex source-of-truth (Kieran P1.2):** extract the canonical regex from `SKILL.md` §"Path globs (canonical)" via `awk` (find the line in the fenced block immediately under that heading). Do NOT redefine it in `repo-scan.sh`. Falls back to `exit 1` with "canonical regex not found in SKILL.md" if extraction fails — defends against silent drift.
   - Parse `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` if set, applying both clauses (match deny pattern + exists in `git ls-files`) and the CI-environment refusal per the design specification.
   - Run `git ls-files -c -o --exclude-standard | grep -E '<canonical-regex>'` to get candidate paths.
   - For each candidate: check deny-list; if denied, check allow-list bypass; emit `# blocked: <path>` to stderr if denied-and-not-allowed; emit `# bypass: <path>` to stderr if denied-but-allowed; otherwise pass through.
   - Output the surviving path list to stdout (one per line). The dispatching agent reads stdout and batches 25-files-per-Haiku-call.
   - Exit 0 on success; exit 1 on env-var typo, CI-bypass, or canonical-regex extraction failure.

3. Verify each deny-list pattern via `git ls-files | grep -E '<pattern>' | head -n 3`. Pattern 3 (private-key extensions, zero hits) carries the `# defense-in-depth` annotation; the other 6 have at least one hit recorded as evidence in the PR body.

### Phase 5 — Tests

1. Create `plugins/soleur/test/gdpr-gate-repo-scan.test.ts` with these test cases (trimmed from 11 per plan-review):
   - **D1** — deny-list blocks `.env*` and `secrets/`. Mock `git ls-files` output containing both shapes; assert they don't appear in the scanner's surviving-paths output.
   - **D3.bypass-typo** — Allow-list typo that doesn't exist in `git ls-files` (e.g., `apps/web-plaform/.env.example` — missing 'r') causes script to exit 1 with `bypass references nonexistent path`. Asserts Kieran P1.1 clause (2). Also covers clause (1) by including a path that's not deny-listed.
   - **D3.bypass-coincidental-match** — Allow-list entry that coincidentally matches a deny pattern but doesn't exist in `git ls-files` (`apps/web-platform/secrets/typo.json` when no such file exists) → exits 1. The load-bearing case Kieran P1.1 surfaced: deny-pattern absorbs the typo without clause (2).
   - **D3.ci-refusal** — `CI=true GDPR_GATE_REPO_SCAN_ALLOW_PATHS=...` → exits 1 with `allow-list bypass refused in CI environment`. Structural mitigation for R5 (Kieran P3.3).
   - **D4** — `repo-scan.sh` source code does not contain `>>` or `>` write operators against any path under `compliance-posture.md`, `__goldens__/`, or fixture dirs. Static grep assertion.
   - **Sentinel** — SKILL.md `## --repo-scan mode` section contains the literal `trimmed value equals **exactly** \`--repo-scan\``.
   - **Canonical-regex source-of-truth** — `repo-scan.sh` extracts the canonical regex from SKILL.md (asserted by `grep -E "awk.*Path globs.*canonical" repo-scan.sh` matching) and does NOT contain a redefinition (no second copy of the regex).

2. Extend `plugins/soleur/test/gdpr-gate.test.ts`:
   - Add 3 entries to `LIFTED_REFS` (lines ~22-28) for the new layer files. The existing attribution-header + vendor-surface scrub assertions auto-extend to cover them.
   - Add `SOLEUR_AUTHORED_LAYERS = ['references/legal-consent.md']` array.
   - NOTICE-row parity assertion: every `LIFTED_REFS` entry has a matching row in NOTICE table with a **unique** 40-char hex blob SHA (Kieran P3.1 — catches accidental copy-paste of v1 SHAs into v2 rows).
   - Soleur-authored header assertion: `legal-consent.md` line 1 is `<!-- Soleur-authored — see NOTICE -->`.
   - Layer-shape assertion: `legal-consent.md` contains `LC-01:` marker AND `## When This Layer Loads` heading.
   - Legacy-archive assertion: `references/legacy/legal-consent-v1-prose.md` exists and starts with the archive provenance header.

(No new fixture files in v2 — anchor fixtures dropped per plan-review consensus. Layer "wired-up" verification comes from `LIFTED_REFS` extension + check_id grep. Per-check_id severity coverage deferred to a follow-up issue.)

### Phase 6 — Verification + lint

1. `bun test plugins/soleur/test/components.test.ts` — verify SKILL.md description budget unchanged (no description edits in v2; `description:` field stays at v1's `"This skill should be used when auditing diffs or plans for GDPR/CCPA/HIPAA compliance gaps."`).
2. `bun test plugins/soleur/test/` — full suite green.
3. `python3 scripts/lint-rule-ids.py` — passes (no AGENTS.md changes; no rule-ID drift).
4. `lefthook run pre-commit` — gdpr-gate-advisory still fires on canonical-regex matches (regression check).
5. Run `/soleur:gdpr-gate --repo-scan` against current worktree manually as a smoke test. Confirm:
   - No `.env*` reads (D1).
   - No persisted output files (D4).
   - 102 → ~80 candidate paths after deny-list (D1+D2 working).
   - Findings stream is inline, structured per v1 schema, disclaimer first.

### Phase 7 — Plan/work/ship integration

No changes to plan/work/ship phases — `--repo-scan` is operator-initiated only and does NOT auto-trigger from those phases. The v1 phase invocations (plan Phase 2.7, work Phase 2 exit, ship Phase 5.5) continue to use `--diff` mode (the default when `$ARGUMENTS` is a scope string or empty in plan/work context).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-LIFT-1** — `references/layers/auth-sessions.md` exists, line 1 is `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->`, contains all 7 check_ids `A-01` through `A-07`, and ends with the Art. 32(1)(b) footer block.
- [ ] **AC-LIFT-2** — `references/layers/frontend.md` exists, attribution header matches, contains `F-01` through `F-06`, ends with ePrivacy/TTDSG footer.
- [ ] **AC-LIFT-3** — `references/layers/testing-seeding.md` exists, attribution header matches, contains `TS-01` through `TS-05`, ends with Art. 32 pseudonymization footer.
- [ ] **AC-LIFT-4** — All 3 lifted files pass vendor-surface scrub via the existing `LIFTED_REFS` test machinery (no new manual grep step).
- [ ] **AC-LIFT-5** — `NOTICE` table contains rows for all 8 lifted files (5 v1 + 3 v2). Each row has a 40-char hex blob SHA AND each blob SHA is **unique** across the table (catches accidental copy-paste of v1 SHAs into v2 rows per Kieran P3.1).
- [ ] **AC-PROMOTE-1** — `references/legal-consent.md` line 1 is `<!-- Soleur-authored — see NOTICE -->`, contains `## When This Layer Loads`, contains check_ids `LC-01` through `LC-05`, each with `What to grep:` AND `Flag when:` AND `Fix pattern:` AND `Regulation:` lines.
- [ ] **AC-PROMOTE-2** — `references/legacy/legal-consent-v1-prose.md` exists, contains the archive provenance header on line 1, and `git log --follow -- references/legacy/legal-consent-v1-prose.md` shows the file moved (not deleted) from `references/legal-consent.md`.
- [ ] **AC-SKILL-0** — `SKILL.md` opening section (lines 6-12) mentions `--repo-scan` exists as a manual mode. Operators reaching SKILL.md from `AGENTS.md hr-gdpr-gate-on-regulated-data-surfaces` see the new mode in the first 5 lines (Kieran P2.4).
- [ ] **AC-SKILL-1** — `SKILL.md` has reorganized "Active layers" + "Reference catalogues" subsections. The Active layers subsection lists exactly 7 entries (api-layer, data-in-transit, data-lifecycle, auth-sessions, frontend, testing-seeding, legal-consent).
- [ ] **AC-SKILL-2** — `SKILL.md` has new section `## --repo-scan mode` between `## Disclaimer (always first)` and `## Path globs (canonical)`.
- [ ] **AC-SKILL-3** — `SKILL.md` `## --repo-scan mode` section contains: (a) the literal string "trimmed value equals **exactly** `--repo-scan`", (b) the literal string `git ls-files -c -o --exclude-standard`, (c) reference to `path-denylist.txt`, (d) reference to `GDPR_GATE_REPO_SCAN_ALLOW_PATHS`, (e) reference to "25 files per Haiku call", (f) the canonical-regex source-of-truth note.
- [ ] **AC-SKILL-4** — `SKILL.md` sharp edges contains: (i) historical-migration tracked-not-amended bullet, (ii) bash-regex-locale bullet noting `LC_ALL=POSIX` is set in `repo-scan.sh`.
- [ ] **AC-DENYLIST-1** — `scripts/path-denylist.txt` exists and contains the 7 patterns enumerated in this plan. Each line is either a comment, blank, or a valid extended regex.
- [ ] **AC-DENYLIST-2** — Pattern 3 (private-key extensions, zero hits) carries the `# defense-in-depth` annotation. Patterns 1, 2, 4-7 record at least one matching path in the PR body as evidence (single `git ls-files | grep -E` line per pattern).
- [ ] **AC-SCRIPT-1** — `scripts/repo-scan.sh` exists, uses `set -euo pipefail` + `LC_ALL=POSIX`, sources `path-denylist.txt`, calls `git ls-files -c -o --exclude-standard` (not `find`), and writes `# blocked: <path>` / `# bypass: <path>` lines to stderr for audit trail.
- [ ] **AC-SCRIPT-2** — `scripts/repo-scan.sh` enforces both `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` clauses: clause (1) entry must match a deny pattern, clause (2) entry must exist in `git ls-files`. Either failure exits 1 with the clause-specific error message (Kieran P1.1).
- [ ] **AC-SCRIPT-3** — `scripts/repo-scan.sh` exits 1 with `allow-list bypass refused in CI environment` when both `$CI` and `$GDPR_GATE_REPO_SCAN_ALLOW_PATHS` are set (Kieran P3.3).
- [ ] **AC-SCRIPT-4** — `scripts/repo-scan.sh` extracts the canonical regex from `SKILL.md` (does NOT redefine it). Asserted by static grep on the script (Kieran P1.2).
- [ ] **AC-TEST-1** — `bun test plugins/soleur/test/gdpr-gate.test.ts` passes; `LIFTED_REFS` extended; `SOLEUR_AUTHORED_LAYERS` array added; NOTICE-row parity + uniqueness assertion present; legacy-archive assertion present.
- [ ] **AC-TEST-2** — `bun test plugins/soleur/test/gdpr-gate-repo-scan.test.ts` passes all 7 cases enumerated in Phase 5.
- [ ] **AC-TEST-3** — `bun test plugins/soleur/test/components.test.ts` passes (skill description budget unchanged at v1 word count).
- [ ] **AC-PARITY-1** — Canonical regex appears verbatim in 4 places: `SKILL.md`, `scripts/gdpr-gate.sh`, `plugins/soleur/test/gdpr-gate.test.ts`, `plugins/soleur/skills/ship/SKILL.md`. `repo-scan.sh` does NOT add a 5th surface — it sources from SKILL.md (Kieran P1.2). The parity test reads `repo-scan.sh` and asserts the regex is NOT redefined.
- [ ] **AC-NO-AGENTSMD** — `git diff main...HEAD -- AGENTS.md` is empty. v2 does NOT modify AGENTS.md.
- [ ] **AC-NO-LEFTHOOK** — `git diff main...HEAD -- lefthook.yml .gitleaks.toml` is empty. v2 does NOT modify hook config.
- [ ] **AC-CPO-SIGNOFF** — CPO sign-off recorded in PR conversation thread before requesting `/review` (per `requires_cpo_signoff: true` carry-forward from brainstorm).
- [ ] **AC-USER-IMPACT-REVIEW** — `user-impact-reviewer` agent invoked at `/review` time and findings resolved or scope-out'd per `rf-review-finding-default-fix-inline`.
- [ ] **AC-SMOKE** — `/soleur:gdpr-gate --repo-scan` against current worktree completes without reading `.env*`, without persisting output, with ≤5 batches, and produces a structured findings stream with disclaimer first.

### Post-merge (operator)

- [ ] **AC-POST-1** — Verify v2 SKILL.md and references render correctly on the docs site (`bash plugins/soleur/docs/scripts/screenshot-gate.mjs` if applicable, or a manual visit to the rendered SKILL.md if the docs site indexes it).
- [ ] **AC-POST-2** — Run `/soleur:gdpr-gate --repo-scan` on `main` post-merge as a smoke test; confirm output shape and no secret leaks.

## Test Scenarios

| Scenario | Expected outcome |
|---|---|
| TDD-RED-4 | `legal-consent.md` rewrite missing `LC-01` marker → layer-shape assertion fails |
| TDD-RED-5 | `repo-scan.sh` uses `find . -name '.env'` instead of `git ls-files` → static-grep test fails |
| TDD-RED-7a | `GDPR_GATE_REPO_SCAN_ALLOW_PATHS=apps/web-plaform/.env.example` (typo in directory; doesn't match deny pattern) → script exits 1 with `bypass references non-blocked path` |
| TDD-RED-7b | `GDPR_GATE_REPO_SCAN_ALLOW_PATHS=apps/web-platform/secrets/typo.json` (matches deny pattern but file doesn't exist) → script exits 1 with `bypass references nonexistent path` (Kieran P1.1 silent-bypass case) |
| TDD-RED-8 | Both `$CI` and `$GDPR_GATE_REPO_SCAN_ALLOW_PATHS` set → script exits 1 with `allow-list bypass refused in CI environment` |
| TDD-GREEN-1 | All AC-LIFT-*, AC-PROMOTE-*, AC-SKILL-*, AC-DENYLIST-*, AC-SCRIPT-*, AC-TEST-* pass |
| Boundary-3 | `$ARGUMENTS = "  --repo-scan  "` (leading/trailing whitespace) → trimmed equals exactly `--repo-scan` → enters repo-scan mode |
| Boundary-5 | `$ARGUMENTS = $'--repo-scan\n'` (literal trailing newline, common when pasted from a runbook) → trim must include `\n` and `\t` and enter repo-scan mode (Kieran P3.2) |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `single-user incident` per brainstorm carry-forward — verified above.
- The `path-denylist.txt` patterns are `bash [[ =~ ]]` extended regex, NOT shell globs. Patterns that look like globs (`*.pem`) will silently fail to match. `repo-scan.sh` sets `LC_ALL=POSIX` for locale-determinism; the file header calls this out; contributors editing patterns must verify on both Linux + macOS (Kieran P2.1).
- `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` parses with `IFS=':'`. A path containing `:` cannot be allow-listed. Defensible scope-out: the gate runs in Linux/macOS agent shells; Windows paths aren't a target.
- The `git ls-files -c -o --exclude-standard` invocation does NOT recurse submodules. If a submodule contains regulated-data paths, they are silently excluded. Deferred to a v3 issue if operator demand arises.
- The deny-list and `.gitleaks.toml` allowlist share semantic intent but are NOT derived from each other at runtime. Drift between them is a maintenance burden but not a load-bearing security risk — each tool defends its own threat model. A parity-sync follow-up issue is filed at plan exit; ad-hoc reconciliation acceptable until then.
- Historical-migration Critical findings (Art. 9 columns in pre-v1 migrations 001-040) are intentionally tracked-not-amended. Operators running `--repo-scan` against full history will see Art. 9 hits that should NOT be amended via destructive migrations. The new SKILL.md sharp-edge (AC-SKILL-4) documents this contract.
- Per `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`, the plan reviewer should run `code-quality-analyst` to grep every cited rule ID against `AGENTS.md` and `scripts/retired-rule-ids.txt`. Rules cited in this plan: `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-weigh-every-decision-against-target-user-impact`, `hr-never-paste-secrets-via-bang-prefix`, `hr-when-a-plan-specifies-relative-paths-e-g`, `cq-test-fixtures-synthesized-only`, `cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`, `cq-rule-ids-are-immutable`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-every-session-error-must-produce-either`, `rf-review-finding-default-fix-inline`. Plan-write-time `git grep` confirmed all 11 are live. Re-verify pre-merge.
- The 3 lifted files retain their **upstream check_id prefixes** (`A-`, `F-`, `TS-`). The v1 layers chose `AP-`, `T-`, `DL-` (also upstream). The `DT-EU-CB` prefix used for the v1 EU-extension is the only Soleur-original prefix. Future upstream lifts preserve upstream prefixes; Soleur-original layers (legal-consent → `LC-`) get their own.
- The `non-negotiables.md` and `fields.md` references receive **no edits** in v2. Documented in the new "Reference catalogues" subsection of SKILL.md.
- `repo-scan.sh` extracts the canonical regex from `SKILL.md` at runtime — if SKILL.md's "Path globs (canonical)" heading is removed or the fenced regex line is reformatted, the script exits 1 with `canonical regex not found in SKILL.md`. Editors of SKILL.md must keep that heading + first-fenced-line shape stable (asserted by AC-PARITY-1).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO)

Carry-forward from `2026-05-09-gdpr-gate-skill-brainstorm.md` §"Domain Assessments". v1's CPO/CLO/CTO/CMO domain leaders blessed the architectural shape; v2 is a same-shape extension (no new architectural surface beyond `--repo-scan`). The CTO assessment was re-run for v2 specifically (this plan's research phase) and produced 5 ship-blocking design fixes, all incorporated above.

### Engineering (CTO) — Re-run for v2

**Status:** reviewed
**Verdict:** GREEN once 5 ship-blocking items addressed (all addressed in plan §"`--repo-scan` Design Specification").
**Findings carried forward:**
- §1 Deny-list completeness → addressed in `path-denylist.txt` (14 patterns; 9 of them mirror gitleaks, 5 are gate-only defense-in-depth).
- §2 `git ls-files -c -o --exclude-standard` → adopted.
- §3 Path-allowlist env var (not boolean) → adopted as `GDPR_GATE_REPO_SCAN_ALLOW_PATHS`.
- §4 Batching: 25 files per Haiku call, ~80 lines per file → adopted; SKILL.md AC-SKILL-3(e) asserts.
- §5 Findings routing: reuse v1 critical-finding flow + add historical-migration sharp-edge → adopted.
- §6 Sole-arg sentinel detection → adopted; SKILL.md AC-SKILL-3(a) asserts.
- §7 Rule-violation audit: green (no violations).
- §8 Extend SKILL.md only, no new AGENTS.md rule → adopted; AC-NO-AGENTSMD enforces.

### Legal (CLO) — Carry-forward + v2 delta check

**Status:** reviewed (carry-forward)
**Assessment:** v1 CLO assessment ("Conversation-only output by default; Critical findings route to compliance-posture.md Active Items via operator-acknowledged write") applies verbatim to `--repo-scan` (D4 inline-only output preserves the contract). The promotion of `legal-consent.md` to layer-shape is in scope (v1 brainstorm Decision #5: "legal-consent.md … Write from scratch … ePrivacy + Art. 7/13/14/35 … biggest EU gap in Sprinto's repo"). v2 Art. 32(1)(b) / ePrivacy / Art. 32 pseudonymization footers are the EU-extension footnotes called out in v1 brainstorm Decision #4.

**Open delta:** the historical-migration tracked-not-amended sharp-edge is a CLO-shaped contract (when does a Critical Art. 9 finding warrant amendment vs. acceptance?). The plan's framing — "amendment migrations carry their own data-integrity risk" — is the correct CLO posture but should be confirmed by `clo` agent at `/review` time. Add `clo` to the review checklist.

### Product/UX Gate

**Tier:** NONE
**Decision:** N/A
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

`--repo-scan` is operator-CLI surface, not user-facing UI. No new components, pages, or user flows. Layer-file edits are docs-only. CPO sign-off required per `requires_cpo_signoff: true` is for the **user-brand-critical threshold**, not for UX review — handled in §"User-Brand Impact" above and AC-CPO-SIGNOFF.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` returned 70 open issues. Grep across v2 file paths:

- `plugins/soleur/skills/gdpr-gate` — 0 matches.
- `gdpr-gate.test.ts` — 0 matches.
- `compliance-posture.md` — 0 matches.
- `lefthook.yml` — 1 match: **#3322** (review: extend lint-fixture-content.mjs glob to cover knowledge-base/project/learnings/). v2 does NOT modify `lefthook.yml` (AC-NO-LEFTHOOK enforces) and does NOT modify `lint-fixture-content.mjs`. **Disposition: acknowledge** — separate concern.
- `plan/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md` — 0 matches.

No fold-in opportunities. No deferred overlap. Backlog unchanged.

## Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | A real `.env` lands in the deny-list output skip list because D1 has a regex bug | Low | High (credential leak) | Test D1 is the load-bearing assertion; review must exercise it with mock fixtures matching `.env`, `.env.local`, `.env.example`, `apps/web-platform/.env` |
| R2 | Pattern 3 (private-key extensions) accidentally over-broad matches and causes a real audit to skip a regulated-data file (e.g., a hypothetical `.key` migration shape) | Low | Medium | Pattern 3 is the only zero-hit retained; sharp-edges note that adding `# Why this pattern` line in `path-denylist.txt` is the convention; v2.1 issue tracks if a real false-skip surfaces |
| R5 | `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` set in CI by accident silently bypasses deny-list | Mitigated | High → blocked | Structural mitigation: `repo-scan.sh` exits 1 when both `$CI` and the bypass var are set (AC-SCRIPT-3 / Kieran P3.3). Risk is downgraded from "documented" to "blocked at script boundary" |
| R7 | The `legal-consent.md` archive-then-rewrite breaks an existing test or fixture that asserted the old prose shape | Low | Low | Phase 5 test additions explicitly cover both the new layer shape AND the legacy archive provenance; v1 tests didn't reference `legal-consent.md` content beyond existence (verified in research) |

## Deferral Tracking

| Deferred capability | Why deferred | Re-evaluation criteria | Tracking issue |
|---|---|---|---|
| Per-layer-id severity fixtures (full coverage of all check_ids across 7 active layers, not just 4 anchors) | Out of scope for v2; 7 layers × 5-7 checks = 35-49 fixtures; one-anchor-per-layer is enough to verify the layer is wired up | Operator demand; or first non-anchor check_id false-fires in production | Will create at plan exit: `feat: complete per-check_id fixture coverage for gdpr-gate active layers` (`domain/engineering`, `priority/p3-low`, milestone Post-MVP / Later) |
| Submodule support for `--repo-scan` | `git ls-files -c -o --exclude-standard` does NOT recurse submodules | First Soleur project that adds a submodule and needs `--repo-scan` coverage | Will create at plan exit: `feat: gdpr-gate --repo-scan submodule support` (`domain/engineering`, `priority/p3-low`, Post-MVP / Later) |
| `--repo-scan-path=<glob>` for scoped repo-scans | v2 uses sole-arg sentinel (`--repo-scan` only); scoped variant deferred per CTO §6 | Operator demand for scoped scans (e.g., "scan only `apps/web-platform/lib/auth/`") | Will create at plan exit: `feat: gdpr-gate --repo-scan-path scoped variant` (`domain/engineering`, `priority/p3-low`, Post-MVP / Later) |
| `path-denylist.txt` ↔ `.gitleaks.toml` automated parity sync | v2 has a parity test but no automated sync; drift requires manual reconciliation | Drift detected in production OR `.gitleaks.toml` schema upgrade (v8.25 top-level allowlist) | Will create at plan exit: `chore: automate path-denylist.txt sync with .gitleaks.toml` (`domain/engineering`, `priority/p3-low`, Post-MVP / Later) |
| Add `gdpr-gate` as `/soleur:preflight` Check 10 | v1 plan AC-PM-2 deferred this; v2 inherits the deferral (plan/work/ship gates are sufficient for now) | Operator demand for ship-blocking enforcement | Existing v1 follow-up (separate from #3518) per AC-PM-2 |

## Sign-off

Per `requires_cpo_signoff: true` (single-user incident threshold), CPO ack required pre-merge. `/review` must include: `user-impact-reviewer`, `clo`, `architecture-strategist`, `security-sentinel`, `code-quality-analyst`. Otherwise standard work→review→ship flow applies; PR labeled `semver:minor` at ship time.

---

**End of plan.**
