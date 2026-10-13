---
title: "feat: Agent-invokable flag-list / flag-delete + cron-list / cron-delete (CRUD completeness, #5318)"
date: 2026-06-15
type: feat
issue: 5318
branch: feat-one-shot-5318-agent-invokable-flag-crud
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: Agent-invokable flag-list / flag-delete + cron-list / cron-delete (#5318)

## Enhancement Summary

**Deepened on:** 2026-06-15
**Halt gates passed:** 4.6 User-Brand Impact (present, threshold `aggregate pattern`), 4.7 Observability (present + justified-skip), 4.8 PAT-shaped (no match), 4.9 UI-wireframe (skipped — no UI surface), 4.4 scheduled-work (no new job introduced).
**Agents run:** verify-the-negative grep pass, Flagsmith-DELETE API research (Context7 + source), agent-native-reviewer, security-sentinel, code-simplicity-reviewer.

### Key Improvements
1. **Flagsmith DELETE contract resolved** (doc-confirmed): `DELETE /projects/{id}/features/{fid}/` → 204; full DB cascade (no orphan); `?q=` is **substring** so exact-name filter is mandatory before delete. One live probe remains (name-reuse after soft-delete).
2. **Security hardening** (P0): name-validation regex BEFORE interpolation (injection); exact-name id resolution (wrong-feature delete); anchored Doppler `> /dev/null` redirect + no-default-bypass + outcome-audit. AC4 rewritten from a weak 2-grep into 5 hardened assertions.
3. **Simplicity + agent-native convergence** (orthogonal-axis → act): dropped `--with-doppler` (always read Doppler — it's the audit's point); cron skills became **thin pointers** to `schedule` (eliminates 3-way classifier drift).
4. **Read-side completeness** (P1): flag-list now surfaces per-segment/role override state so an agent sees a flag's blast radius before deleting (`2026-05-07` parity learning).
5. **Capability discovery** (P1/P2): flag-cluster and cron-cluster `## When to use this skill vs` disambiguation; cron set names `trigger-cron` (run-now) so the surface isn't half-migrated.

### New Considerations Discovered
- The scheduled-workflow count is **environment-dependent** (4 in this worktree, more in bare-root) — ACs must derive it dynamically, never hardcode. (A verify-the-negative subagent's CWD reset surfaced this.)
- `flag-set-role/scripts/flip.sh:98` hard-rejects unknown flags → a deleted-but-still-mapped flag breaks `flag-set-role`, confirming the 5th-site edit is load-bearing, not padding.

## Overview

The scheduled agent-native audit scored CRUD completeness lowest (5/14 entities, 35.7%). Feature flags have Create (`flag-create`) and Update (`flag-set-role`) but **no agent-invokable Read or Delete**. Scheduled crons have list/delete logic but bundled as `schedule list` / `schedule delete` prose subcommands, not first-class agent-discoverable verbs.

This plan closes the highest-impact slice of that gap by adding **four skills**:

1. **`flag-list`** — Read. Query the Flagsmith management API for all features + per-segment state, cross-reference `server.ts` RUNTIME_FLAGS and the live Doppler env-var values, so an agent can audit active flags before a promotion decision.
2. **`flag-delete`** — Delete. The exact inverse of `flag-create`: remove the feature from Flagsmith, strip the entry from `server.ts` RUNTIME_FLAGS, delete the `FLAG_*=` line from `.env.example`, delete the Doppler secret in `soleur/dev` + `soleur/prd`, AND remove the entry from the hardcoded `FLAG_ENV_VARS` map in `flag-set-role/scripts/flip.sh`.
3. **`cron-list`** — promote `schedule list` to a first-class verb.
4. **`cron-delete`** — promote `schedule delete <name>` to a first-class verb.

**Out of scope (deferred — see Non-Goals + tracking issues):** flag-get (single-flag), flag user-role Create/Read/Delete cohort management, agent CRUD, hook CRUD. These are the audit's items #4 ("longer term") and the user-role/agent/hook rows. The issue's priority order explicitly lists items 1–3 as the work target; item 4 is "longer term."

**Not a work target:** issue **#3807** (expense-ledger CRUD gap) is a separate OPEN issue cited only for contrast. Confirmed OPEN and distinct during premise validation.

This is a **`plugins/`-only change** plus one TypeScript test-constant bump (`SKILL_DESCRIPTION_WORD_BUDGET`). No new infrastructure, no UI surface, no DB migration, no regulated-data surface, no `apps/*/src` runtime code.

## Premise Validation

Checked before research dispatch (plan Phase 0.6):
- **#5318** — `gh issue view 5318` → OPEN. The work target. Held.
- **#3807** — `gh issue view 3807` → OPEN, title "Expense Ledger has 0/4 CRUD operations". Confirmed it is a *separate* gap, NOT a work target. Held (correctly excluded per ARGUMENTS).
- **Cited files all exist on the working tree:** `flag-create/SKILL.md`, `flag-set-role/SKILL.md`, `user-set-role/SKILL.md`, `schedule/SKILL.md`, `apps/web-platform/lib/feature-flags/server.ts`, `apps/web-platform/.env.example`. Held.
- **Gap confirmed real:** `ls plugins/soleur/skills/ | grep -E 'flag|cron'` → only `flag-bootstrap`, `flag-create`, `flag-set-role`, `trigger-cron`. No `flag-list`/`flag-delete`/`cron-list`/`cron-delete`. Held.
- **Mechanism vs. ADR corpus:** no rejected-alternative conflict — these are net-new read/delete verbs mirroring an existing, sanctioned create skill. The skills-vs-commands decision (`2026-02-12-command-vs-skill-selection-criteria.md`) explicitly classes agent-invokable CRUD as skills.

No external premise was stale.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| flag-delete must touch Flagsmith + server.ts + .env.example + Doppler (4 sites) | There is a **5th** site: `flag-set-role/scripts/flip.sh:50` hardcodes a `declare -A FLAG_ENV_VARS` map keyed by flag name. A deleted flag left in that map is stale and would let `flag-set-role` attempt to flip a non-existent flag. `flag-create` does NOT write this map (it predates it / relies on manual sync). | flag-delete edits **5 sites**; flip.sh map removal is an explicit Files-to-Edit entry + AC. (Note as a follow-up: flag-create should also append to this map — filed as deferral, out of scope here.) |
| cron-list/cron-delete are "bundled subcommands" implying shell scripts to extract | `schedule/SKILL.md` is **prose-only, no `scripts/` dir**. `list` (SKILL.md:673–708) and `delete` (SKILL.md:710–720) are agent-executed prose steps (read YAML, classify cron shape, output / `rm` file). | New skills are thin prose SKILL.md that carry the same steps verbatim and point back to `schedule` as the create path. No script extraction needed. |
| "RUNTIME_FLAGS so agents can audit active flags" | `server.ts:39–51` declares `const RUNTIME_FLAGS = { "<kebab>": "FLAG_<UPPER>", ... } as const;`. There is also `ENV_FLAGS` (`dev-signin` only, DCE). | flag-list reads RUNTIME_FLAGS keys as the code-side source of truth; lists ENV_FLAGS separately as a labeled section (don't conflate). |
| budget cap "1,800 words" (AGENTS.md checklist + an older learning) | The **live enforced constant** is `SKILL_DESCRIPTION_WORD_BUDGET = 2071` at `components.test.ts:15`, and the current cumulative total is **2071 — ZERO headroom**. | Plan prescribes bumping the constant by *exactly* the sum of the 4 new descriptions' word counts, against the established zero-headroom-baseline pattern. See §Skill Description Budget. |

## User-Brand Impact

**If this lands broken, the user experiences:** an agent mis-reports active feature-flag state during a promotion decision (flag-list returns stale/wrong enablement), or flag-delete partially removes a flag (e.g., deletes the Flagsmith feature but leaves `server.ts` referencing a now-missing env var), leaving the web platform's flag-evaluation path in an inconsistent state for end users behind that flag.

**If this leaks, the user's data/workflow is exposed via:** these skills read the `FLAGSMITH_MANAGEMENT_API_KEY` and `doppler secrets` (including `doppler secrets delete`, which dumps the **full remaining config** to stdout unless redirected — security learning `2026-05-26`). A leak vector is the management API key or production secret values printed to a shared terminal / CI log.

**Brand-survival threshold:** aggregate pattern. These are operator-/agent-facing capability skills, not a user-facing surface; a single misfire is recoverable (the partial-delete is correctable by re-running). The exposure risk is real but bounded by the existing operator-Doppler trust boundary the sibling skills already operate within. No per-PR CPO sign-off required; the section is present per the gate.

## Research Insights (deepen-plan)

**Flagsmith DELETE contract (doc-confirmed via Flagsmith API source `api/features/views.py`, `api/features/models.py`; one item needs live Phase-0 probe):**
- **Endpoint:** `DELETE /api/v1/projects/{project_id}/features/{feature_id}/` (trailing slash required, Django router). Success → **HTTP 204 No Content**.
- **Cascade:** Deleting a feature **fully cascades** — all `FeatureState` rows (env defaults, identity overrides) AND all `FeatureSegment` rows (segment-override config) AND their `FeatureState` children are `on_delete=CASCADE`. Nothing orphans. **No manual pre-deletion of segment overrides needed**; a single DELETE is sufficient and atomic.
- **`?q=<name>` is SUBSTRING (`name__icontains`), NOT exact** — confirmed in `_filter_queryset`. The client-side exact-name filter (`f['name'] == NAME`, create.sh:68–69) is **mandatory** in delete.sh; without it `?q=foo` could resolve `foo-bar`'s id and DELETE the wrong feature (security+correctness bug — security review P2-2, agent-native none). No "delete by name" shortcut: resolve id, then DELETE by id.
- **Permissions:** `Delete feature` is a project-level RBAC permission; the same `FLAGSMITH_MANAGEMENT_API_KEY` that creates features should carry it (verify in Phase 0). Deletes are project-wide (removes from all environments at once).
- **NEEDS LIVE PROBE (Phase 0.1):** `Feature` extends a soft-delete model (`deleted_at` set rather than hard SQL DELETE), but the queryset filters `deleted_at IS NULL` so a deleted feature is invisible to the API. **Unknown without probe:** whether the same flag *name* can be **re-created** after delete (does the unique `(project, name)` index count soft-deleted rows?). This matters for the create→delete→recreate round-trip in AC3. Probe: after DELETE returns 204, `POST /features/` with the same name and observe 201 (reusable) vs 400 (name conflict).

**Scheduled-workflow count is environment-dependent — do NOT hardcode.** This worktree has 4 `.github/workflows/scheduled-*.yml`; the bare-root/main checkout has more. cron-list/cron-delete ACs MUST derive the count dynamically (`git ls-files '.github/workflows/scheduled-*.yml' | wc -l`), never assert a literal number (a deepen-plan verify-the-negative subagent ran against a different working copy and reported 18 — the count is not a stable invariant).

## Implementation Phases

### Phase 0 — Preconditions (live verification, before any code)

0.1. **Flagsmith DELETE contract probe (load-bearing — novel API op).** Per learning `2026-05-27-flagsmith-segment-rule-structure-verify-before-implementing.md`. The endpoint/cascade/substring facts above are doc-confirmed; the ONE live probe required is **name-reuse after delete** (soft-delete unique-index question). Against a throwaway feature (`flag-create <test-flag-uniq> --flagsmith-only`):
   - `GET /api/v1/projects/39082/features/?q=<name>` → confirm `results[].id` resolves, filter to exact name.
   - `DELETE /api/v1/projects/39082/features/<feature_id>/` → confirm **204**.
   - Re-`GET ?q=<name>` → confirm `results: []` (invisible after delete).
   - `POST /features/` same name → record 201 (reusable) vs 400 (conflict). Pin verified-at date + outcome in the spec.
   - Confirm the management API key has `Delete feature` permission (a 403 on DELETE means the key needs the project-level perm).
0.2. **Doppler delete behavior.** Confirm `doppler secrets delete <NAME> -p soleur -c dev --yes > /dev/null` (the `> /dev/null` is MANDATORY per `2026-05-26-doppler-secrets-delete-dumps-full-config-to-stdout.md` — without it the command prints all remaining secrets). Confirm the verify-deletion read form: `doppler secrets get <NAME> -p soleur -c dev --plain 2>&1 | grep -q 'not found'`.
0.3. **Budget headroom measurement.** Run the Node one-liner (below) and record `total / 2071`. (Already measured at plan time: **2071/2071, headroom 0.**) Re-confirm at /work time in case of merge drift.

### Phase 1 — `flag-list` skill (Read)

Files to create:
- `plugins/soleur/skills/flag-list/SKILL.md`
- `plugins/soleur/skills/flag-list/scripts/list.sh`

`list.sh` contract (mirror create.sh constants + `fs_api` helper verbatim):
- Reuse `FLAGSMITH_PROJECT_ID=39082`, `FLAGSMITH_ENV_DEV_ID=90722`, `FLAGSMITH_ENV_PRD_ID=90721`, `FLAGSMITH_API`, `SERVER_TS`.
- Read `FLAGSMITH_MANAGEMENT_API_KEY` from `doppler secrets get ... -p soleur -c cli_ops --plain` (same source as create.sh:62). `fs_api()` identical to create.sh:65.
- `GET /projects/39082/features/` → list every feature (name, id, default_enabled). Paginate if `next` is present (verify pagination shape in Phase 0 if >N features).
- Cross-reference the code-side RUNTIME_FLAGS keys parsed from `server.ts` (python/awk over the `const RUNTIME_FLAGS = { ... } as const;` block) — flag any feature in Flagsmith **not** code-wired and any code-wired flag **missing** from Flagsmith (the two drift directions an auditor cares about).
- **Always read the live Doppler env-var value per flag** (`doppler secrets get FLAG_<X> -p soleur -c dev --plain` and `-c prd`) and show dev + prd alongside the Flagsmith state. The audit use case ("audit active flags before a **promotion** decision") *is* a dev→prd value comparison, so the Doppler columns are the decision-relevant data, not an optional extra. **`--with-doppler` flag REMOVED** (deepen-plan: simplicity + agent-native reviewers both converged — only ~5 flags = 10 reads, no perf gate justified; gating off the audit's own headline column is the wrong default). Read only the single targeted `FLAG_<X>` key per flag — never `doppler secrets download` / `doppler secrets` (which dump the whole config, same family as the `2026-05-26` hazard).
- **Surface per-segment / per-role override state** (P1, agent-native review + `2026-05-07` parity learning): `flag-set-role` (Update) writes per-role and per-org segment overrides; flag-delete (Delete) destroys them via cascade. A Read that omits them is a half-Read — an agent can't see "this flag has 3 active role cohorts" before deleting. flag-list MUST also enumerate each flag's segment overrides (resolve via `GET /projects/39082/segments/` + per-env feature-states, mirroring flip.sh's `resolve_segment_id` / feature-state read shape) and show which segments/roles each flag targets in dev + prd.
- `--json` flag → emit a JSON array (`name`, `env_var`, `flagsmith_id`, `default_enabled`, `code_wired` bool, `doppler_dev`, `doppler_prd`, `segments` array); default → formatted table.
- **Read-only**: no mutations, no WORM audit append, no `--dry-run` needed (reads don't mutate). The management API key is read via the same `doppler secrets get ... -c cli_ops --plain` + `fs_api` `-H Authorization` pattern (create.sh:62,65) — never echoed.
- List `ENV_FLAGS` (e.g. `dev-signin`) under a clearly separate "build-time env flags (DCE)" heading — do not present them as runtime flags.
- **Disambiguation (P1):** flag-list `SKILL.md` carries a `## When to use this skill vs ...` block naming the full flag verb-set: `flag-create` (Create), `flag-set-role` (Update per-role/org), **`flag-list` (Read — this)**, `flag-delete` (Delete), `flag-bootstrap` (initial wiring). With 5 flag-* skills the routing-conflation risk the plan mitigates for cron applies symmetrically to flags.

### Phase 2 — `flag-delete` skill (Delete, inverse of flag-create)

Files to create:
- `plugins/soleur/skills/flag-delete/SKILL.md`
- `plugins/soleur/skills/flag-delete/scripts/delete.sh`

`delete.sh` contract — the precise inverse of create.sh, **5 mutation sites**, same exit-code map (`0` ok, `1` validation, `2` missing prereq, `3` Flagsmith error, `4` file/audit fail, `5` Doppler fail):
0. **Name validation FIRST, before ANY interpolation (security P0-2).** Apply create.sh:40–41 verbatim: `[[ ! "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && exit 1`. `$NAME` is later interpolated into `python3 -c` source, heredocs, the `?q=` URL, and `grep` patterns; an unvalidated name with `'`, `+`, or a newline is a command-injection / regex-corruption vector. flag-delete is MORE dangerous than create here (it runs a regex-delete against server.ts and Doppler deletes keyed on the derived name). This is the FIRST executable line after arg parse.
1. **Validate the flag exists** in `server.ts` RUNTIME_FLAGS (inverse of create's "already registered" precheck — delete REQUIRES it present). Resolve `ENV_VAR="FLAG_$(echo "$NAME" | tr 'a-z-' 'A-Z_')"` exactly as create.sh:42.
2. **Resolve Flagsmith feature_id** via `GET /projects/39082/features/?q=<name>` then **filter results to EXACT name** (`f['name'] == NAME`, create.sh:68–69 shape) — `?q=` is substring (`name__icontains`), so a bare pick could DELETE the wrong feature (security P2-2; Research Insights). Assert the resolved id belongs to a feature whose name == `$NAME` before issuing DELETE. If absent in Flagsmith, warn but continue the code-side cleanup (drift recovery).
3. **Propose + `--dry-run` + `read -p "Proceed? Type 'yes'"` confirmation** — identical guardrail to create.sh:77–95. Destructive op MUST keep the typed-yes gate.
4. **WORM audit append BEFORE mutating** (create.sh:97–108 pattern), `action="delete"`, `target="global"`, `before`/`after` = the current/`null` enablement. Source `audit_flag_flip_rpc` from `plugins/soleur/scripts/audit-flag-flip.sh`. Abort (exit 4) on audit failure — destructive ops must be audited.
5. **DELETE Flagsmith feature**: `fs_api -X DELETE "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/${FEATURE_ID}/"` — expect **204** (Research Insights). The DB cascade removes all segment overrides + feature-states automatically; **no manual override pre-deletion needed**. Capture the HTTP status (`curl -w '%{http_code}'`); a non-204 → exit 3.
6. **Strip from `server.ts` RUNTIME_FLAGS** via python regex (delete the `  "<name>": "FLAG_<X>",` line inside the `const RUNTIME_FLAGS = { ... } as const;` block; mirror create.sh:161–175 but removing).
7. **Delete the `FLAG_<X>=` line from `.env.example`** (inverse of create.sh:179–194; match `^${ENV_VAR}=` and drop it).
8. **Remove the entry from `flag-set-role/scripts/flip.sh` `FLAG_ENV_VARS` map** (`["<name>"]="FLAG_<X>"` at flip.sh:50–56). **This is the 5th site the issue's 4-site framing misses** (Research Reconciliation row 1). Leaving it stale lets `flag-set-role` try to flip a deleted flag.
9. **Delete Doppler secrets** in both configs with mandatory redirect ON THE DELETE LINE ITSELF (security P0-1 — `doppler secrets delete` prints the full remaining config to **stdout**, `2026-05-26`):
   `doppler secrets delete "$ENV_VAR" -p soleur -c dev --yes > /dev/null || exit 5` and same for `-c prd`. Verify deletion via `doppler secrets get "$ENV_VAR" -p soleur -c dev --plain 2>&1 | grep -q 'not found'` (the `2>&1 | grep -q` is safe — `-q` discards output). Never `echo`/`tee` the delete output. The dump is stdout-only, so `> /dev/null` covers the known vector; do NOT add a stray `2>&1` that re-merges stderr onto a logged stream.
10. **Outcome audit (P1-1):** the pre-mutation WORM row (step 4) records *intent* with `after=null`. Because the 5 sites fail independently (exit 3/4/5), append a SECOND audit signal on completion recording actual end-state (fully-deleted vs partial), OR document per-exit-code recovery state explicitly in `delete.sh` + SKILL.md so an operator can reconstruct "Flagsmith gone but prd Doppler still live" from the exit code. A destructive op's audit trail must distinguish full from half delete.
11. Print the commit hint (mirror create.sh:202–204).

### Phase 3 — `cron-list` and `cron-delete` skills (promote to first-class verbs)

Files to create:
- `plugins/soleur/skills/cron-list/SKILL.md`
- `plugins/soleur/skills/cron-delete/SKILL.md`

These are **thin-pointer prose skills** (no scripts — `schedule` itself has none). **Decision (deepen-plan, simplicity reviewer):** do NOT copy the `schedule` list/delete prose verbatim — that would triplicate the cron-shape classifier + delete steps across `schedule/SKILL.md`, `cron-list`, and `cron-delete`, and the classifier already carries a "keep in sync if Step 3b changes" obligation that would then span 3 files. Instead each new skill is a short pointer: it states its purpose + disambiguation, then instructs the agent to **execute the `### list` / `### delete <name>` section of `plugins/soleur/skills/schedule/SKILL.md`** (one source of truth for the classifier). This satisfies the goal (agent-discoverable first-class verbs, CRUD score) at a fraction of the prose with zero drift liability.
- `cron-list/SKILL.md`: pointer + purpose ("list scheduled cron workflows, classified recurring vs one-time, `--json` supported"). Reference `schedule`'s `### list` steps; note the same V1 limitation (mode + cron only; richer state via `gh workflow view`). Any worked example MUST derive the count dynamically (`git ls-files '.github/workflows/scheduled-*.yml'`) — never hardcode a number (the count is environment-dependent; see Research Insights).
- `cron-delete/SKILL.md`: pointer + purpose. Reference `schedule`'s `### delete <name>` steps (verify `.github/workflows/scheduled-<name>.yml` exists → else point to `cron-list` → confirm → `rm`). Keep the one-time-schedule self-neutralization caveat reference.
- **Disambiguation (avoid namespace conflation, `2026-05-03`; agent-native P2):** each new skill's description AND a `## When to use this skill vs ...` section names the FULL cron verb-set so an agent sees it from any entry point: `soleur:schedule` (Create), **`cron-list` (Read — list), `cron-delete` (Delete)**, and **`soleur:trigger-cron` (Run-now)** — the latter is already a first-class skill and the plan must name it so the cron surface isn't presented as half-migrated. `schedule` remains the create entry point and retains its list/delete prose (canonical source) — cross-link, do not delete.

### Phase 4 — Skill description budget + release docs

4.1. **Bump `SKILL_DESCRIPTION_WORD_BUDGET`** at `plugins/soleur/test/components.test.ts:15` by exactly the **sum of the 4 new descriptions' word counts**, appending a bump-note in the same comment style as the existing entries (`bumped +N for #5318 (flag-list/flag-delete/cron-list/cron-delete skill descriptions, N words, against a 2071/2071 zero-headroom baseline)`). Target each new description at ~30 routing words (4 × ~30 ≈ ~120 words → bump ~+120; compute the exact figure from the authored descriptions, do not estimate in the constant).
   - Alternative if a reviewer objects to a +120 bump: trim sibling descriptions to absorb part of it. Given the established per-skill-bump precedent (every prior skill bumped by its own word count against zero headroom), a clean +sum bump is the convention. Author descriptions tight (~30 words, routing-only, no trigger-phrase bloat) per the budget learning.
4.2. **Release docs** (`release-docs/SKILL.md`): run `bash scripts/sync-readme-counts.sh` (updates root README + plugin README skill counts), then update `plugins/soleur/.claude-plugin/plugin.json` description counts manually (skill count +4). Do NOT touch the `version` field (frozen `0.0.0-dev`).
4.3. **Eleventy build verification** per release-docs Step: build and confirm `component-card` counts in `_site/pages/skills.html` reflect +4 skills.

## Acceptance Criteria

### Pre-merge (PR)
- [x] **AC1 (flag-list reads, incl. Doppler + segments):** `bash plugins/soleur/skills/flag-list/scripts/list.sh --json` returns a JSON array where every `server.ts` RUNTIME_FLAGS key appears with `code_wired: true`, includes `doppler_dev`/`doppler_prd` columns (always-on, no `--with-doppler`), includes a `segments` array per flag, and flags any Flagsmith-only / code-only drift row. Verify array length ≥ RUNTIME_FLAGS key count; each known flag (`kb-chat-sidebar`, `byok-delegations`, …) present; `--with-doppler` flag is absent from the script (`grep -c 'with-doppler' list.sh == 0`).
- [x] **AC2 (flag-delete is the full inverse — 5 sites):** A dry-run `bash .../flag-delete/scripts/delete.sh <test-flag> --dry-run` enumerates all 5 proposed mutations: Flagsmith feature, server.ts RUNTIME_FLAGS, .env.example line, `flip.sh` FLAG_ENV_VARS entry, Doppler dev+prd. Grep the dry-run output for each of the 5 target tokens. (Dry-run should early-exit before the destructive ops; it may still read the management key — acceptable, mirrors create.sh.)
- [x] **AC3 (flag-delete round-trips):** Against a throwaway flag created with `flag-create`, `flag-delete` removes it such that: (a) `flag-list --json` no longer lists it, (b) `grep -c '"<name>"' server.ts == 0`, (c) `grep -c '^FLAG_<X>=' .env.example == 0`, (d) `grep -c '\["<name>"\]' flip.sh == 0`, (e) `doppler secrets get FLAG_<X> -p soleur -c dev --plain 2>&1 | grep -q 'not found'` for both dev and prd, (f) the Flagsmith name is reusable-or-not per the Phase 0.1 probe outcome (don't assert reuse until probed).
- [x] **AC4 (destructive guardrails — hardened per security review):** Grep `delete.sh` source and assert ALL of:
  - **(a) name validation first:** `grep -E '\[\[ ! "\$NAME" =~ \^\[a-z\]\[a-z0-9-\]\*\[a-z0-9\]\$ \]\]' delete.sh` matches, AND it appears before any `python3`/`fs_api`/`grep "$NAME"` interpolation (P0-2 injection guard).
  - **(b) exact-name id resolution:** the feature_id is resolved via an exact `name == NAME` filter, not a bare `?q=` pick (P2-2; `grep -E "f\['name'\] ?== ?'\\\$NAME'|== *\"\\\$NAME\"" delete.sh` or equivalent exact-match guard present).
  - **(c) anchored Doppler redirect:** every `doppler secrets delete` line itself ends in `> /dev/null` — `grep -cE 'doppler secrets delete[^\n]*> ?/dev/null' delete.sh` == count of `doppler secrets delete` calls (≥ 2); and no `doppler secrets (get|delete)` line `echo`/`tee`s its output.
  - **(d) typed-yes, no default bypass:** typed `yes` prompt present (`grep -q "Type 'yes'" delete.sh`); no `--yes`/`--force` flag bypasses the prompt by default (`grep -cE '\-\-(yes|force)\)' delete.sh` == 0, or if present it is a separately-named, audited flag).
  - **(e) WORM audit before mutation + outcome signal:** `grep -c 'audit_flag_flip_rpc' delete.sh` ≥ 1 (pre-mutation intent row), AND per-exit-code recovery state is documented in delete.sh/SKILL.md (P1-1).
- [x] **AC5 (cron-list pointer + dynamic count):** `cron-list/SKILL.md` references `schedule`'s `### list` steps (`grep -q 'schedule' cron-list/SKILL.md`) and contains NO hardcoded scheduled-workflow count (any example uses `git ls-files '.github/workflows/scheduled-*.yml'`). The recurring-vs-one-time classification lives in `schedule/SKILL.md` (single source) — cron-list points to it, does not re-implement.
- [x] **AC6 (cron-delete pointer + disambiguation):** `cron-delete/SKILL.md` references `schedule`'s `### delete <name>` steps and has a `## When to use this skill vs` section naming the full verb-set: `schedule` (create), `cron-list` (read), `cron-delete` (delete), `trigger-cron` (run-now). `grep -q 'trigger-cron' cron-delete/SKILL.md` AND `grep -q 'schedule' cron-delete/SKILL.md`.
- [x] **AC7 (budget gate green):** `bun test plugins/soleur/test/components.test.ts` passes. The constant at `:15` is bumped by exactly the sum of the 4 new descriptions' word counts (verify: re-run the Node one-liner; new `total` ≤ new constant; new constant − old 2071 == sum of 4 new descriptions).
- [x] **AC8 (frontmatter compliance):** Each of the 4 new SKILL.md has `name:` == directory name, `description:` in third person ("This skill should be used when..."), ≤ 1024 chars, and all `scripts/` references use markdown links (`grep -E '^description:' skills/{flag-list,flag-delete,cron-list,cron-delete}/SKILL.md | grep -v 'This skill'` returns nothing).
- [x] **AC9 (release-docs counts):** Root README, plugin README, and `plugin.json` description reflect skill count +4 after `sync-readme-counts.sh`. `version` field unchanged (`0.0.0-dev`).
- [x] **AC10 (no scope leak):** core diff touches only `plugins/soleur/skills/{flag-list,flag-delete,cron-list,cron-delete}/**`, `plugins/soleur/test/components.test.ts`, README files. No `apps/` source, no migrations, no `.tf`. **Review-driven additions (agent-native C#2 discoverability fix):** back-references to the new verbs added to sibling skills `flag-create/SKILL.md`, `flag-set-role/SKILL.md`, `schedule/SKILL.md`, `trigger-cron/SKILL.md`, plus a co-editor comment in `flag-set-role/scripts/flip.sh` (P2-2). Prose/comment-only; completes the agent-native discoverability goal — a legitimate review outcome, not scope creep. **Note:** `flip.sh`'s FLAG_ENV_VARS map is *removed-from at runtime* by `flag-delete`, not pre-edited statically.
- [ ] **AC11 (PR hygiene):** PR body has `## Changelog` + `semver:minor` label (new skills) + `Closes #5318`. Deferral issues filed for the out-of-scope items (Non-Goals).

### Post-merge (operator)
- [ ] **AC12:** None required — pure plugin/docs change; merge to main is the full delivery. (Automation-feasibility gate: no migration apply, no terraform, no external-service mint. All verification is pre-merge.)

## Non-Goals (deferred — each gets a tracking issue per plan Phase 6 deferral check)
- **flag-get** (single-flag detail read) — `flag-list` covers the audit use case; a per-flag get is a thin follow-up. File deferral.
- **Flag user-role Create / Read / Delete** (cohort onboard/list/remove) — only Update exists (`user-set-role`). Audit row "Flag user-roles 1/4." File deferral.
- **Agent CRUD** and **Hook CRUD** — audit rows "Agents 0/4", "Hooks 0/4", issue item #4 ("longer term"). File deferral(s).
- **flag-create should also append to flip.sh `FLAG_ENV_VARS`** — discovered in Research Reconciliation; create currently relies on manual sync of that map. File deferral (out of scope: this plan only removes from the map on delete).

## Risks & Mitigations
- **Flagsmith DELETE shape unverified → wrong verb/path/status.** Mitigation: Phase 0.1 live probe against a throwaway feature; pin verified-at in spec. Vendor docs are silent on cascade behavior (`2026-05-27` learning) — verify empirically.
- **`doppler secrets delete` leaks full config to stdout.** Mitigation: mandatory `> /dev/null` (AC4 greps for it). Security learning `2026-05-26`.
- **Budget zero-headroom: a sloppy long description fails CI for unrelated PRs.** Mitigation: author each description ~30 routing words; bump constant by exact sum; AC7 re-runs the gate.
- **5th-site drift (flip.sh map) missed → flag-delete leaves `flag-set-role` referencing a dead flag.** Mitigation: explicit Files-to-Edit + AC2/AC3(d).
- **Partial-delete inconsistency (Flagsmith deleted, code not).** Mitigation: delete.sh continues code cleanup even if Flagsmith feature is already absent (drift recovery), and the typed-yes + dry-run let the operator review all 5 mutations first.
- **Namespace conflation (`schedule` vs `cron-*`).** Mitigation: disambiguation sections both directions; `schedule` retains its list/delete prose; cross-link only.

**Precedent-diff (Phase 4.4):** No novel pattern. `flag-delete/scripts/delete.sh` is the line-for-line inverse of the established `flag-create/scripts/create.sh` (same constants, `fs_api`, Doppler patterns, WORM-audit-before-mutate, typed-yes, name validation) — the canonical destructive-flag-op shape. `flag-list/scripts/list.sh` reuses create.sh's read helpers + flip.sh's `resolve_segment_id` shape. cron-list/cron-delete point to `schedule/SKILL.md`'s existing list/delete prose. The only genuinely-novel element is the Flagsmith DELETE verb, resolved in Research Insights + Phase 0.1.

## Domain Review

**Domains relevant:** Engineering (CTO — agent-native capability surface). No Product/UX surface (no `components/**/*.tsx`, no `app/**/page.tsx`; pure skill/docs). No Legal/Finance/Marketing/Sales/Support/Ops implications.

Product/UX Gate: **NONE** — mechanical UI-surface scan of Files-to-Create/Edit matches no UI-surface path; the change implements agent-tooling skills + a test constant, not a user-facing surface.

### Engineering (CTO)
**Status:** carried-forward inline (infra/tooling change; CTO lens applied during planning).
**Assessment:** This is a direct agent-native parity improvement — adds Read+Delete to the flag entity and promotes cron Read+Delete to discoverable verbs, exactly the CRUD-completeness axis the audit scores. Key engineering risks captured: (1) the 5th flip.sh map site, (2) Flagsmith DELETE contract verification, (3) Doppler stdout-leak guardrail, (4) zero-headroom description budget. All mirror established sibling-skill patterns (flag-create / schedule), minimizing novel surface. Classification as **skills** (not commands) is correct per `2026-02-12-command-vs-skill-selection-criteria.md` (agents must invoke autonomously).

## Observability

Pure plugin/skill change — no `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or new infrastructure surface. Per plan Phase 2.9 skip condition (no Files-to-Edit under code/infra paths; skills are operator/agent-invoked shell + prose), the 5-field observability schema does not apply. The skills' own failure surfacing is synchronous exit-code + stderr to the invoking operator/agent (mirrors flag-create/trigger-cron), not a background service needing a liveness signal.

## Open Code-Review Overlap
None. (Queried `gh issue list --label code-review --state open`; no open scope-out names `plugins/soleur/skills/flag-*`, `cron-*`, `schedule/SKILL.md`, or `components.test.ts`. Re-run at /work time per the overlap gate.)

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = aggregate pattern.)
- The AGENTS.md Skill Compliance checklist says "under 1,800 words (see #618)" — this is a **stale comment**; the live enforced constant is `2071` at `components.test.ts:15`. Trust the test constant, not the prose. (Optional: fix the AGENTS.md comment in this PR — but that is a docs nit, scope-out unless trivial.)
- `flag-create/scripts/create.sh` does NOT write the `flag-set-role/scripts/flip.sh` `FLAG_ENV_VARS` map; only `flag-delete` (this plan) touches it on the remove side. The create-side asymmetry is a pre-existing gap filed as a Non-Goal deferral — do not silently "fix" create here (scope creep).
- Budget is at exact zero headroom; any description authored > its allotted words fails CI for the whole repo. Author tight, re-measure, bump by exact sum.

## Skill Description Budget (measured at plan time)
- Current: **2071 / 2071 words, headroom 0** (measured via the Node one-liner; constant at `components.test.ts:15`).
- 4 new descriptions at ~30 routing words each ≈ ~120 words → bump constant to ~2191 (compute exact sum from authored text).
- Measurement one-liner (re-run at /work, pre- and post-edit):
```bash
node -e "
const fs=require('fs'),path=require('path');
const root='plugins/soleur/skills';
const dirs=fs.readdirSync(root).filter(d=>{try{return fs.statSync(path.join(root,d)).isDirectory()}catch{return false}});
let total=0;
for(const d of dirs){const f=path.join(root,d,'SKILL.md');if(!fs.existsSync(f))continue;
const c=fs.readFileSync(f,'utf-8');const m=c.match(/^description:\s*\"?([\s\S]*?)\"?\s*\$/m);
if(m)total+=m[1].split(/\s+/).filter(Boolean).length;}
console.log('Total:',total);
"
```
