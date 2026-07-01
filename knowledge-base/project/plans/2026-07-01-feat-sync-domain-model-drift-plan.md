---
type: feat
feature: sync-domain-model
issue: 5754
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-01
branch: feat-sync-domain-model
pr: 5869
brainstorm: knowledge-base/project/brainstorms/2026-07-01-sync-domain-model-register-brainstorm.md
spec: knowledge-base/project/specs/feat-sync-domain-model/spec.md
follow_ups: [5871, 5872]
plan_reviewed: [dhh, kieran, code-simplicity, spec-flow-analyzer]
---

# Plan — `/soleur:sync domain-model`: auto-fill + drift-detect the business-rules register

## Enhancement Summary

**Deepened:** 2026-07-01 · **Triad:** data-integrity-guardian, security-sentinel, architecture-strategist (P0: architecture "unusually well-grounded"). See `## Deepen Research Insights` for binding requirements.

**Key hardening added:**
1. **`.down.sql` exclusion** from policy replay (P0 — else a rollback DROP silently deletes a live fact).
2. **Fail-closed secret-shape scan** before emit + write (P0 — the report is committed; RLS predicates embed literals).
3. **Path-confinement + injection safety** for generic-`--repo` (realpath-confine, `--` terminators, no eval, markdown-escape).
4. **Anchor = full-filename + table-qualified object** (14 shared migration numbers; non-unique policy names).
5. **`ALTER POLICY` merge semantics** + `DO $$`/`EXECUTE format()` → `blind_spots` (leaky-abstraction honesty).
6. **Atomic register write** (mktemp+mv) + heading re-validate (TOCTOU); **`LC_ALL=C`/`jq -S`** idempotency pins.
7. **Contract made real for #5871:** `schema_version` in the JSON now + pinned `drift` exit codes (0/1/2).
8. **`scripts/lib/domain-model-lib.sh` tokenizer** factored for #5871 reuse; conventional-path defaults (AP-010).

## Overview

Add a `domain-model` area to the `/soleur:sync` command that analyzes a repo's data model and
reconciles it against the business-rules register (`knowledge-base/engineering/architecture/domain-model.md`,
already created by PR #5773). It emits a **two-way drift report** and supports **approval-gated
auto-write** of newly-inferred rows into an `## Auto-inferred (unreviewed)` section. Full scope
(auto-write + drift + generic-repo) is an operator decision over the 5-agent read-only recommendation.

**What the tool guarantees (bounded honestly — SpecFlow P0-2).** It detects *structural documentation
coverage*: whether each statically-extractable structural invariant (a live RLS policy after
migration replay, a UNIQUE/CHECK/FK/PK constraint, a `SECURITY DEFINER` signature, a named TS guard)
has a register row, and whether each register citation still resolves to a real source. It does **NOT**
prove semantic access-control correctness — predicate logic inside function bodies, dynamically-composed
RLS (`EXECUTE format()`), and service-role bypasses are out of static reach and are disclosed as
blind spots, never counted as "no drift."

**Idempotency insight.** The drift report is computed by a deterministic script
(`scripts/domain-model-drift.sh`) as a pure set-diff between the extractor's normalized+sorted live
facts and the register's parsed citations. No LLM in that path ⇒ CI-safe, diff-free re-runs. The LLM
touches only optional statement-phrasing at interactive approval; statements otherwise use a deterministic template.

## Premise Validation

- **#5773 MERGED 2026-06-30** — register + ADR-maintenance wiring exist; this plan is the analyzer only.
- **#5871, #5872 OPEN** — enforcement gates + scheduled cron are out of scope.
- **No pre-existing ADR** for domain-model drift extraction (ADR-013 is the unrelated product domain-gate).
- **Mechanism vs ADR corpus:** no rejected-alternative collision in `decisions/`.

## Research Reconciliation — Spec vs. Codebase (incl. plan-review corrections)

| Claim | Reality | Plan response |
|---|---|---|
| "~120 migrations" | **221** `.sql` in `apps/web-platform/supabase/migrations/`; **39 `CREATE POLICY` vs 72 `ALTER`/`DROP POLICY`** | Extractor walks the tree AND **replays CREATE/ALTER/DROP POLICY in migration order (last-writer-wins)** — grep-all-CREATE would mix dead+live predicates (SpecFlow P0-1) |
| ~~Register cites stale guard `resolveActiveWorkspace`~~ **(WRONG — my truncated grep)** | `resolveActiveWorkspace` **EXISTS** at `workspace-resolver.ts:398`; the citation is **live, not stale** (Kieran P0, SpecFlow P0-3) | Use it as the **negative control** (must NOT be flagged); positive stale case via synthesized fixture. Resolution is **exact-token, scoped to the cited file** (else `resolveActiveWorkspaceKbRoot` substring false-matches) |
| Parse the register's `Source` column | The `resolveActiveWorkspace` citation is in BR-WS-2's **Statement** cell; `Source` cells are heterogeneous free prose (`"#5733; ADR-073; ADR-044 (amendment); RPC #5756"`) | Citation parser scans the **whole row** (Statement + Source) with a defined **citation-token grammar** (`ADR-\d+`, `migration \d+ › <obj>`, `<file>.ts › <symbol>`, `#\d+`) (Kieran P0, SpecFlow P1-4) |
| sync areas are prompt-only | `rule-prune` ships `scripts/rule-prune.sh` **and** `tests/commands/test-sync-rule-prune.sh` (test-all.sh:131) | Mirror BOTH: `scripts/domain-model-drift.sh` (+`.test.sh`) AND `tests/commands/test-sync-domain-model.sh` (Kieran P1) |
| "migrations append-only ⇒ citations never drift" | False for *effective* schema (DROP/ALTER replay) | Stated as a **documented assumption** on filenames only; correctness comes from replay, not append-only |

## Files to Create

- `scripts/domain-model-drift.sh` — deterministic entry point. **Two modes:**
  - `extract [--repo <path>]` → normalized, sorted JSON of **live** structural facts after policy replay
    (tables, PK/UNIQUE/CHECK/FK, live `CREATE POLICY` predicate, `SECURITY DEFINER` signatures, named TS
    guard symbols), each with a **table-qualified, content-anchored** citation (`migration 053 › workspace_members_pkey`,
    `workspace-resolver.ts › resolveActiveWorkspace()`), plus a `blind_spots` list (dynamic `EXECUTE format()`/`DO` policy blocks it could not statically analyze).
  - `drift --repo <path> --register <path>` → two-way markdown drift report (pinned template + completeness
    disclaimer + explicit blind-spots line). Internally calls `extract`.
  - (Idempotency is a **test property**, verified in the test — not a shipped CLI mode. Code-simplicity.)
  - Graceful degradation: no Supabase migrations dir ⇒ disclaimered empty report (exit 0), never garbage.
- `scripts/domain-model-drift.test.sh` — golden-fixture tests (synthesized fixtures only, `cq-test-fixtures-synthesized-only`):
  extractor facts; **last-writer-wins** (fixture where a later migration DROP+CREATEs a policy with a new predicate → only the live one appears);
  idempotency (unchanged→byte-identical; mutate→differs); stale-direction (fixture register citing a non-existent symbol/migration-object → flagged) + negative control (a live citation NOT flagged); undocumented-direction; dynamic-SQL fixture → appears in `blind_spots`, not silently dropped; non-Supabase repo → disclaimered empty, exit 0.
- `tests/commands/test-sync-domain-model.sh` — command-wiring test (mirror `test-sync-rule-prune.sh`): `domain-model` is a valid area, excluded from `all`, dispatches to the script.
- `knowledge-base/engineering/architecture/decisions/ADR-0XX-domain-model-drift-extraction.md` — concise ADR recording the **durable** convention: deterministic-first extraction, **last-writer-wins policy replay**, content-anchored citations, and the **structural-not-semantic** scope boundary. (JSON consumer contract for #5871 is explicitly deferred until #5871 constrains its shape — DHH/code-simplicity.)

## Files to Edit

- `plugins/soleur/commands/sync.md`: L4 argument-hint + L20 Valid areas + L22 area-note (add `domain-model`,
  excluded from `all`); L69 Parse Area Filter branch (skip Phase 2-4, like `rule-prune`); new `#### Domain Model Analysis`
  section (mirror `Rule Prune Analysis` L149) — invoke the script, present the report, then a **self-contained**
  approval-gated accept/skip/edit write into `## Auto-inferred (unreviewed)` (a reuse of the review UX, NOT a Phase-2 re-entry — Kieran P2). Never write curated `## Business Rules`; never mint `BR-*`.
- `scripts/test-all.sh`: register `run_suite "scripts/domain-model-drift" bash scripts/domain-model-drift.test.sh`
  and `run_suite "tests/commands/sync-domain-model" bash tests/commands/test-sync-domain-model.sh` (mirroring L124/L131).
- `knowledge-base/engineering/architecture/domain-model.md`: add the **completeness disclaimer** to the header;
  add the (empty) `## Auto-inferred (unreviewed)` section; document the **promotion flow** (`Auto-inferred → curated BR-*`
  is a human edit that assigns an ID + keeps the source anchor, so the row is never re-proposed); link the ADR;
  update the maintenance note that #5754's auto-fill is now live.

## Implementation Phases

**Phase 1 — Extractor + tests (RED→GREEN).** Test-first (synthesized fixtures). `extract` mode with
last-writer-wins policy replay, table-qualified content-anchored citations, `blind_spots` for dynamic SQL,
deterministic sort. Register both suites in `test-all.sh`. Includes the idempotency + degradation fixtures.

**Phase 2 — Drift diff + register-citation parser.** `drift` mode: whole-row citation-grammar parser → set-diff
(stale + undocumented) → pinned report + disclaimer + blind-spots line. Prove AC5 (positive fixture flagged; live
`resolveActiveWorkspace` negative-control NOT flagged, via exact-token file-scoped resolution).

**Phase 3 — Command wiring + approval-gated write + ADR.** Add the `domain-model` area + command test; approval-gated
write into `## Auto-inferred (unreviewed)`; register-header disclaimer + promotion-flow note; author the ADR via
`/soleur:architecture create` and link it.

## Architecture Decision (ADR/C4)

### ADR
Author **ADR-0XX — Domain-model drift extraction (deterministic-first, last-writer-wins, content-anchored)** as a
Phase-3 task. Pins the durable convention only: deterministic extractor vs LLM boundary; last-writer-wins policy
replay; content-anchored citation format (no line numbers); structural-not-semantic scope. **Deferred:** the
machine-readable JSON schema #5871 will consume — recorded as an open item, finalized when #5871 constrains it.

### C4 views
**No C4 impact.** Enumerated against `model.c4`/`views.c4`/`spec.c4`: (a) no new external human actor (operator-run
dev tooling, covered by existing operator/agent actor); (b) no new external system/vendor (reads local repo files
only); (c) no new container/data-store (writes a markdown file already in the repo); (d) no actor↔surface access
relationship changes (analyzer READS the product model, never alters ownership/tenancy). Dev tooling isn't in the
product C4; the register is documentation, not a runtime container.

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong/empty drift report — a maintainer trusts "no drift"
  while an undocumented structural invariant exists, OR an auto-inferred row misstates a rule.
- **If this leaks, the user's data/workflow is exposed via:** false confidence — the register mis-cited as a
  governance control while dynamic/function-body invariants sit unrecorded. **Named false-negative (review, fixed):**
  a repo whose migrations dir moved/renamed would yield an empty extract; the drift report now fails LOUD
  (`## Source not analyzable`, exit 2) instead of reading identical to a clean repo (the #2887 fail-open shape).
- **Brand-survival threshold:** single-user incident.

Mitigations: deterministic drift (no hallucinated drift, no LLM in the detection path); the guarantee is bounded to
structural coverage with dynamic-SQL/function-body blind spots **disclosed in every report**, so the report cannot
be honestly mis-read as an access-control audit; auto-write is approval-gated + segregated from curated rows;
completeness disclaimer in register header + every report. `user-impact-reviewer` runs at PR review. CPO sign-off carried forward from brainstorm.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). Deterministic-first hybrid extraction, content-anchored citations, generic-repo
degrade-gracefully, enforcement gates separate (#5871). No capability gaps.

### Product (CPO)
**Status:** reviewed (carry-forward). Drift report is the product, auto-write is the liability; operator chose full
scope; write-mostly risk mitigated by approval-gate + segregated unreviewed section + content-anchor keying (no re-proposal churn).

### Legal (CLO)
**Status:** reviewed (carry-forward). Governance immaterial (read-only, no personal data). Guardrail kept: completeness
disclaimer — now strengthened by the explicit structural-not-semantic scope + disclosed blind spots.

### Product/UX Gate
Not run — no UI surface (no `components/**/*.tsx`, `app/**/page.tsx|layout.tsx` in Files lists; mechanical override did not fire). Tier: NONE.

## Compliance & Infra Gates

- **GDPR (2.7):** No regulated-data *code* surface in Files-to-Edit (command prompt, two scripts, a command test, a
  markdown register, an ADR — migrations are read-only *input*, not modified). Single-user-incident trigger (b) answered by CLO carry-forward + disclaimer.
- **IaC (2.8):** Skipped — no server/cron/secret/DNS/vendor introduced (cron deferred #5872). <!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- **Observability (2.9):** the tool is an interactive/CI-invoked dev CLI at repo-root `scripts/` (not `apps/*` nor
  `plugins/*/scripts`, not a cron/server/infra runtime) — matching `rule-prune.sh`/`extract-api-spend.sh` precedent.
  The `## Observability` block below states this honestly (no Sentry/Better Stack surface exists for a local CLI).

## Observability

```yaml
liveness_signal:
  what: N/A — interactive/CI-invoked CLI, not a long-running service (no heartbeat/cadence)
  cadence: on-demand (via /soleur:sync domain-model; and in CI via test-all.sh)
  alert_target: CI job failure (test-all.sh); terminal exit code for interactive runs
  configured_in: scripts/domain-model-drift.sh
error_reporting:
  destination: stderr + non-zero exit code to the invoking terminal / CI job (no external sink)
  fail_loud: yes — parse error, unreadable register, or (per security pass) secret-shape hit exits non-zero, never silent
failure_modes:
  - mode: migration/SQL parse error
    detection: non-zero exit + stderr message naming the file
    alert_route: CI job failure (test-all.sh) / terminal
  - mode: register file unparseable or hand-edited mid-run
    detection: non-zero exit before any write
    alert_route: terminal / CI
  - mode: idempotency divergence (report differs across two identical runs)
    detection: scripts/domain-model-drift.test.sh assertion fails
    alert_route: test-all.sh / CI
logs:
  where: stdout (the drift report) + stderr (diagnostics); no persistent log
  retention: none — ephemeral CLI output
discoverability_test:
  command: bash scripts/domain-model-drift.test.sh
  expected_output: "domain-model-drift.test.sh: N passed, 0 failed" (exit 0)
```

## Acceptance Criteria (all pre-merge — no operator/post-merge steps)

- [ ] `/soleur:sync domain-model` runs the extractor + emits a two-way drift report; `domain-model` is a valid area, excluded from `all` (verified by `tests/commands/test-sync-domain-model.sh`).
- [ ] Every emitted candidate/row carries a table-qualified, content-anchored citation (no line numbers).
- [ ] Report lists both directions (stale register rows + undocumented structural invariants) AND an explicit blind-spots line (dynamic-SQL/function-body items not statically analyzed) — never a silent zero.
- [ ] **Last-writer-wins:** a fixture where a later migration DROP+CREATEs a policy with a new predicate yields only the live predicate as a fact.
- [ ] Re-running on an unchanged repo produces a byte-identical report (idempotency — verified by `domain-model-drift.test.sh`).
- [ ] **AC5 (canonical):** a synthesized fixture register row citing a non-existent symbol/migration-object is flagged `stale`; the **live** `resolveActiveWorkspace` citation (workspace-resolver.ts:398) is **NOT** flagged (exact-token, file-scoped resolution).
- [ ] Unsupported stack (no Supabase migrations) → disclaimered empty report, exit 0.
- [ ] Approval-gated write lands accepted rows in `## Auto-inferred (unreviewed)`; curated `## Business Rules` untouched; no `BR-*` minted; re-run does NOT re-propose an already-accepted row (content-anchor keyed).
- [ ] Completeness disclaimer (structural-not-semantic) in register header + every report.
- [ ] Both bash suites registered in `test-all.sh` and green.
- [ ] ADR-0XX created and linked from the register.
- [ ] **`.down.sql` excluded from replay** — fixture: a down-file DROPping a live policy does NOT delete that fact.
- [ ] **Fail-closed secret-shape scan** before emit AND before write — fixture: a migration with a planted secret-shaped literal → refuse to emit, exit non-zero.
- [ ] **No command injection / no eval over migration bytes**; SQL treated as data (`grep -F --`, awk `-v`).
- [ ] **Markdown-injection safe write** — fixture: a predicate containing `|` + a forged `BR-WS-9` row is escaped, not structurally injected; templated rows matching `^BR-`/`^##` rejected.
- [ ] **Atomic register write** (mktemp+mv) + `## Auto-inferred` heading re-validated immediately before write.
- [ ] **`--repo`/`--register` realpath-confined** (register write resolves under repo root; symlinks denied on the walk).
- [ ] **Idempotency pinned:** `LC_ALL=C` sorts + `jq -S` emits.
- [ ] **`extract` JSON carries `schema_version`** (marked internal/unstable); **`drift` exit codes** `0`=clean / `1`=drift / `2`=error.

## Open Code-Review Overlap

None — no open `code-review` issue references `commands/sync.md`, `domain-model.md`, or `domain-model-drift`.

## Test Scenarios

Synthesized fixtures only: (1) mini migration dir (PK, CHECK, `CREATE POLICY`, `SECURITY DEFINER`) → assert facts;
(2) later-migration DROP+CREATE same policy new predicate → only live predicate extracted (last-writer-wins);
(3) unchanged→byte-identical, mutate→differs; (4) fixture register with a stale citation + a missing constraint →
one `stale` + one `undocumented`; live-citation negative control not flagged; (5) `EXECUTE format()` policy → appears
in `blind_spots`; (6) non-Supabase repo → disclaimered empty, exit 0; (7) command test: `domain-model` valid, excluded from `all`.

## Deepen Research Insights (2026-07-01 — data-integrity, security, architecture triad)

These are **binding implementation requirements** folded in from the deepen-plan domain triad. Grouped by concern.

### Extraction correctness (data-integrity P0/P1, architecture P1)

- **P0 — Exclude `.down.sql` from replay.** 78 rollback files exist; some carry `CREATE`/`DROP`/`ALTER POLICY`. A naive
  `*.sql` glob lets a down-file `DROP` execute in replay and **silently delete a live policy fact** (the exact silent-loss
  the tool exists to prevent). Extractor globs base migrations only (`*[0-9].sql`, exclude `*.down.sql`); dedicated fixture.
- **Replay order:** `LC_ALL=C` lexical sort == apply order for zero-padded base files (verified) — *after* the down-exclusion.
- **`ALTER POLICY` is merge-not-replace** — `ALTER … USING(...)` leaves `WITH CHECK` intact. Replay merges USING/WITH CHECK
  onto prior policy state; if a merged predicate can't be deterministically reconstructed, the policy goes to `blind_spots`, never a mis-counted fact.
- **Content-anchor = full base-filename + table-qualified object** (NOT the 3-digit number, NOT a bare policy name).
  14 numbers are shared across distinct files (017×4, 053×2, 075×3); policy names are not globally unique. The register-citation
  parser resolves a cited `migration NNN` to the base (non-`.down`) file and flags a genuinely-ambiguous number.
- **`blind_spots` detector triggers on `DO $$` bodies AND `EXECUTE format(`** (53 files) — a `DO` block emitting a static
  `CREATE POLICY` via plpgsql string is line-parser-invisible and must still reach `blind_spots`, plus schema-qualified / cross-table same-name policies that can't be disambiguated.

### Idempotency (data-integrity P1)

- **Pin `LC_ALL=C` on every sort and `jq -S` on every JSON emit** — no precedent script pins locale; without it the
  byte-identical AC breaks on a different-locale CI runner.

### Security (security P0×2, P1×2 — extract-api-spend.sh is the template)

- **P0 — Fail-closed secret-shape scan before emit AND before write.** RLS predicates / `SECURITY DEFINER` bodies embed
  literals (JWT claims, `current_setting()` tokens, seeded UUIDs, old connection strings); the report is **committed**.
  Port extract-api-spend.sh's `grep -qiE 'sk-ant|sk_(live|test)|ghp_|ghs_|github_pat_|AKIA[0-9A-Z]{16}|xoxb-|sbp_|-----BEGIN'`
  over every assembled row → refuse + exit non-zero on hit. Extractor projects the **citation anchor**, not full predicate bodies. AC + planted-secret fixture.
- **P0 — Path handling:** `set -euo pipefail`; quote every expansion; parse args with `--` terminators; `realpath`-confine
  `--repo`/`--register` (the register write MUST resolve under the repo root, else reject); `[[ -L ]]` symlink-deny on the migration walk.
- **P1 — No command injection:** treat all SQL as data — never `eval`, never interpolate migration content into `$(...)`,
  patterns via `grep -F -- "$pat"` / awk `-v`. AC asserts no dynamic-command construction over migration bytes.
- **P1 — Markdown/table injection on write:** escape `|`→`\|`, strip/encode newlines + control chars (`\x7f`, ` `,
  ` `), reject templated rows matching `^BR-` or `^##`, validate every field against the citation-token grammar. Fixture: a predicate containing `|` + a forged `BR-WS-9` row → escaped, not structurally injected.

### Register-write integrity (data-integrity P1, architecture)

- **Atomic whole-file rewrite** via `mktemp` + `trap` + `mv` (precedent `scripts/rule-metrics-aggregate.sh:48,334`) — a
  non-atomic partial write on interrupt can corrupt the curated `## Business Rules` pipe-table.
- **Re-parse the `## Auto-inferred` heading offset immediately before write; abort on a missing/duplicate anchor** (TOCTOU —
  a hand-edit relocating the heading between extract and write could split the curated table).

### Contract for #5871 (architecture P1 — makes the deferral real)

- **`extract` JSON emits a `schema_version` field now** and is marked **internal/unstable** in the ADR + script header —
  otherwise Phase 1 ships the de-facto contract while "deferring" it, producing the exact v1→v2 break the deferral meant to avoid.
- **Exit-code contract, pinned now:** `drift` mode → `0` = no drift, `1` = drift found, `2` = error. #5871 (enforcement gate under `set -e`) keys on `1`. Breaking change if discovered later.

### Placement & reuse (architecture P2, AP-010)

- **Location = repo-root `scripts/`** (confirmed): generic-`--repo` forces repo-agnosticism; `apps/web-platform/scripts/`
  parsers are app-locked (`MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"`, no repo arg).
- **Reuse idioms, not app code:** copy house style (`SCRIPT_DIR` sourcing, `scripts/lib/` constants, `run_suite` registration);
  do NOT import the web-platform parsers. **Factor the policy tokenizer into `scripts/lib/domain-model-lib.sh`** so #5871 reuses it rather than re-parsing.
- **AP-010 defaults:** `extract`/`drift` default to conventional paths (`apps/web-platform/supabase/migrations`, the canonical
  register) when flags are omitted; flags are for generic-repo override only.
- **ADR cross-references `run-migrations.sh`** — documenting the deliberate text-replay-vs-authoritative-PG-replay divergence (no-DB / deterministic / generic-repo trade).

## Alternatives Considered

| Approach | Rejected because |
|---|---|
| Read-only drift-report only (DHH/CPO recommendation) | Operator chose full scope; recorded here — auto-write + generic-repo are in-scope by operator decision |
| Naive grep-all-`CREATE POLICY` | Mixes dead+live predicates (72 ALTER/DROP) → false green (SpecFlow P0-1) |
| Parse only the `Source` column | Misses in-Statement citations → AC5 unreliable (Kieran P0/SpecFlow P1-4) |
| LLM-computed drift diff | Non-deterministic ⇒ fails idempotency; re-introduces hallucinated drift |
| Auto-write into curated `## Business Rules` | Corrupts curated supersession lineage (BR-WS-3) |
| Two-file model (`domain-model.generated.md`) | Loses single-register goal; in-file segregated section isolates equally |
| Ship `--verify-idempotency` as a CLI mode | Test-only property; not a product surface (code-simplicity) |
| Pin #5871's JSON contract now | Consumer unbuilt; guarantees churn — defer (DHH/code-simplicity) |
| Full multi-stack extractor v1 | YAGNI — zero tenant demand; Supabase+TS engine + graceful degradation covers the AC |

## Sharp Edges

- **The "append-only migrations" claim is false for effective schema** — 72 `ALTER`/`DROP POLICY` mean a policy's live
  predicate is the last writer. Correctness depends on replay, not filename immutability.
- **Citation resolution must be exact-token AND file-scoped** — `resolveActiveWorkspace` substring-matches
  `resolveActiveWorkspaceKbRoot`/`RepoMeta`; a repo-wide substring check false-passes the AC5 negative control.
- **The drift diff MUST be in the script (deterministic)** — an LLM-computed diff fails idempotency and re-introduces hallucinated drift.
- **`test-all.sh` registers named suites individually** (L124/L131) — both new suites must be added explicitly or they silently never run.
- **Superseded-but-live constraints** (e.g. migration 075 single-owner, superseded by BR-WS-3): the curated row must
  cite the anchor to mark it documented; otherwise it reads as `undocumented` (acceptable — it prompts a human to record the supersession).
- A `## User-Brand Impact` section that is empty/`TBD` fails `deepen-plan` Phase 4.6 — it is filled above.
