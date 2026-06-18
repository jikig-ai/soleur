---
title: "feat: Auto-regenerate the LikeC4 model artifact when C4 sources change"
date: 2026-06-18
branch: feat-one-shot-c4-model-autoregen
type: enhancement
lane: procedural
brand_survival_threshold: none
status: ready
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this plan introduces NO infrastructure (no server, secret,
  vendor account, DNS, cert, or persistent runtime process). The only "install"
  is `npm install -g likec4@1.50.0` as a CI-runner tool step, mirroring the
  existing gitleaks-install precedent in the test-scripts shard of ci.yml — a
  build-time dev tool on an ephemeral GitHub Actions runner, not provisioned
  infrastructure. No Terraform applies. The Domain Review and Observability
  sections document the skip rationale.
-->

# feat: Auto-regenerate the LikeC4 model artifact when C4 sources change

## Overview

Today the canonical LikeC4 architecture model can drift: an agent or operator edits a
`.c4` source file (`spec.c4` / `model.c4` / `views.c4`) under
`knowledge-base/engineering/architecture/diagrams/`, but the **compiled artifact the
web Knowledge Base viewer actually renders** — `model.likec4.json` — is only refreshed
by a *manual* `architecture render` step that nobody is forced to run. There is no
pre-commit hook, no CI gate, and no test asserting the JSON matches its sources.

**This plan adds defense-in-depth enforcement so the compiled model is always in sync
with the `.c4` sources, removes the by-hand step, and dogfoods the fix by regenerating
the currently-stale artifact.**

### Premise correction — "c4-model.md" vs `model.likec4.json` (load-bearing)

The feature request says "the c4-model.md visualization file is automatically
regenerated." Reading all three `.c4` files plus the diagrams `README.md` and the web
viewer code reveals an important distinction the plan must honor:

| File | Kind | Drifts? | This plan's treatment |
|---|---|---|---|
| `spec.c4`, `model.c4`, `views.c4` | LikeC4 DSL **source** | n/a (source of truth) | The trigger |
| `model.likec4.json` | **Compiled artifact** (217 KB), REQUIRED by the web viewer at runtime, `npx likec4 export json` output | **Yes — mechanically** | **The thing auto-regenerated + sync-gated** |
| `c4-model.md` | **Hand-authored** view page: a ` ```likec4-view ` embed block + per-level `## Notes` prose with ADR cross-refs | Yes — *conceptually* (prose can lie), but it is NOT a generated file | **Advisory staleness check only** (warn, don't auto-write) |

`c4-model.md` is not a generated file — it cannot be "regenerated" from the sources the
way the JSON can. The embedded view block is static text; the Notes are human prose. So
the **mechanical** auto-regen target is `model.likec4.json`. The plan also adds an
**advisory** freshness reminder for `c4-model.md`'s Notes (a warn-only nudge when `.c4`
elements change but `c4-model.md` is untouched in the same commit) so its prose does not
silently rot — but it never machine-rewrites human prose.

### Current drift evidence (measured at plan time, 2026-06-18)

Regenerating with the pinned CLI shows the committed artifact is **stale**:

```text
committed model.likec4.json:  43 elements, 56 relations, 45 views, 216,958 bytes
fresh likec4@1.50.0 regen:    matches current model.c4 (email-triage + inngest elements present)
```

The committed JSON predates the email-triage (ADR-066) and inngest-durability (#5459)
`.c4` additions — exactly the silent-drift failure this plan eliminates. Phase 4
(dogfood) commits the correctly-regenerated artifact.

### Version pin is load-bearing (sharp edge that shapes the whole plan)

The project **pins `likec4@1.50.0`** in three coupled places, guarded by
`apps/web-platform/test/c4-likec4-version-pin.test.ts`:

- `apps/web-platform/Dockerfile`: `RUN npm install -g likec4@1.50.0`
- `apps/web-platform/package.json`: `@likec4/core` and `@likec4/diagram` both `1.50.0`

The CLI's `export json` schema MUST match the client renderer (`@likec4/diagram`) the
browser loads. **Every regeneration surface this plan adds (script, hook, CI gate) MUST
pin `likec4@1.50.0`, never `@latest`.** The current `architecture` SKILL.md `render`
sub-command uses `npx -y likec4@latest` — that is a latent defect (latest is 1.58.0 in
the wild today) and is fixed in Phase 3. The runtime browser-edit path
(`apps/web-platform/server/c4-render.ts`) already uses the global pinned `likec4` binary,
so the new surfaces stay consistent with it.

## Research Reconciliation — Spec vs. Codebase

| Claim (from request) | Reality (codebase) | Plan response |
|---|---|---|
| "c4-model.md visualization is regenerated when any C4 file changes" | `c4-model.md` is hand-authored prose+embed, not generated; `model.likec4.json` is the generated artifact | Auto-regen targets `model.likec4.json`; `c4-model.md` gets an advisory staleness warning only |
| "decide enforcement point: skill / AGENTS gate / git hook / CI" | lefthook has an exact auto-regen-and-restage precedent (`generate-kb-index`); CI has 3 test shards + a synthetic `test` aggregator; no C4 freshness test exists | Use **all four** as layered defense: (1) lefthook pre-commit auto-regen+restage, (2) CI freshness test, (3) SKILL.md render-step fix + mandate, (4) AGENTS.md workflow gate pointer |
| "regenerate via likec4" | SKILL.md `render` uses `npx likec4@latest`; project pins `1.50.0` (version-pin test) | Pin `1.50.0` everywhere; fix SKILL.md `@latest` to `@1.50.0` |
| committed `model.likec4.json` assumed current | Measured **stale** (43/56/45 vs current source 45/62/4) | Phase 4 dogfoods the regen and commits the fresh artifact |

## User-Brand Impact

**If this lands broken, the user experiences:** the web Knowledge Base C4 diagram
renders a stale architecture (missing the email-triage / inngest elements), OR a
contributor's commit is blocked/auto-modified incorrectly by a misfiring pre-commit hook.

**If this leaks, the user's data is exposed via:** N/A — this touches only
version-controlled architecture documentation tooling. No user data, no secrets, no
runtime request path. The lefthook script reads only `.c4` source and writes only the
committed `model.likec4.json`; the CI test reads source and compares bytes.

**Brand-survival threshold:** none — internal documentation-tooling change. The artifact
is rebuildable from source at any time; a transient drift is cosmetic to a single
internal viewer, recoverable by re-running the regen. No sensitive-path surface is
touched (no schema/migration/auth/API). threshold: none, reason: build-time
documentation tooling only; no user-facing data, secret, or runtime path is touched.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Regen script exists and is idempotent.** `scripts/regenerate-c4-model.sh`
      exists, is `chmod +x`, uses `set -euo pipefail`, pins `likec4@1.50.0`, renders to a
      **temp path** then validates (`jq -e '(.elements | length) > 0'`) before
      publishing onto the tracked path, and is a no-op (zero git diff) when run twice
      against unchanged sources. Verify: run it twice from a clean tree; second run
      leaves `git status --short` clean for `model.likec4.json`.
- [ ] **AC2 — Empty-model clobber protection.** When the script renders an empty model
      (e.g. a broken `.c4`), it exits non-zero with a diagnostic and does NOT overwrite
      the existing good `model.likec4.json`. Verify: temporarily break a `.c4` element
      kind, run the script, assert exit non-zero AND the committed JSON is unchanged
      (`git diff --quiet model.likec4.json`).
- [ ] **AC3 — lefthook pre-commit hook auto-regenerates and restages.** `lefthook.yml`
      has a new pre-commit command (`c4-model-regenerate`) with
      `glob: "knowledge-base/engineering/architecture/diagrams/*.c4"` whose `run` calls
      `scripts/regenerate-c4-model.sh && git add knowledge-base/engineering/architecture/diagrams/model.likec4.json`,
      mirroring the `generate-kb-index` precedent. Verify: stage a `.c4` edit, run
      `lefthook run pre-commit`, assert `model.likec4.json` is regenerated and staged.
- [ ] **AC4 — Advisory `c4-model.md` staleness warning.** The same hook (or a sibling
      warn-only command) prints a non-blocking reminder to review/update `c4-model.md`'s
      `## Notes` when `.c4` model elements changed but `c4-model.md` is NOT in the same
      staged set. Verify: stage only a `.c4` edit, run the hook, assert the warning text
      appears AND exit code is 0 (advisory, never blocking).
- [ ] **AC5 — CI freshness test fails on drift.** A new test (a bash/`node --test` test in
      the `scripts` shard) regenerates `model.likec4.json` with the pinned CLI into a temp
      path and asserts it is byte-identical to the committed artifact; the test FAILS on a
      deliberately-staled fixture and PASSES on the in-sync tree. Verify: run the test on
      the synced tree (pass), hand-stale the JSON (fail), restore.
- [ ] **AC6 — likec4 CLI availability in the CI shard that runs AC5.** The chosen CI job
      installs `likec4@1.50.0` (mirroring the gitleaks-install precedent in the
      `test-scripts` shard) so the freshness test can actually render. The job name does
      NOT add a new *required* branch-protection check unless folded into an existing
      shard; if a standalone job is added, it is wired into the synthetic `test`
      aggregator's `needs`. Verify: read `.github/workflows/ci.yml`; confirm the install
      step + job-graph wiring.
- [ ] **AC7 — Version pin parity preserved.** `apps/web-platform/test/c4-likec4-version-pin.test.ts`
      still passes; the new script/hook/CI all reference `1.50.0`. Verify:
      `grep -rn "likec4@" scripts/ lefthook.yml .github/workflows/ci.yml plugins/soleur/skills/architecture/SKILL.md`
      returns only `1.50.0` (no `@latest`).
- [ ] **AC8 — `architecture` SKILL.md render step fixed + mandate added.** The `render`
      sub-command's two `npx -y likec4@latest` lines become `npx -y likec4@1.50.0`, and
      the `diagram` / `add-*` sub-commands gain an explicit instruction: "After any `.c4`
      edit, regeneration of `model.likec4.json` is automatic on commit via the
      `c4-model-regenerate` pre-commit hook; if committing outside that hook, run
      `scripts/regenerate-c4-model.sh`." Verify: read SKILL.md; `grep -c "1.50.0"` at
      least 2 and `grep -c "@latest" plugins/soleur/skills/architecture/SKILL.md` == 0.
- [ ] **AC9 — Skill description budget unchanged within cap.** No `description:` frontmatter
      is edited (only body prose), so the 1800-word cumulative cap is unaffected. Verify:
      `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] **AC10 — AGENTS.md workflow-gate pointer (only if budget allows).** Evaluate adding
      a `wg-c4-source-edit-regenerates-compiled-model` pointer; if the always-loaded byte
      budget (`AGENTS.md` + `AGENTS.core.md` vs the 23000-byte cap, and per-rule 600-byte
      cap) cannot absorb it, place the mandate in the `architecture` SKILL.md + the
      diagrams `README.md` only and record the budget measurement. Verify: run the budget
      check; record the number in the PR body.
- [ ] **AC11 — Existing C4 test suite green.** All `apps/web-platform/test/c4-*.test.ts`
      / `.tsx` still pass (no regression to render/version/route tests). Verify the
      webplat shard.

### Post-merge (operator) — none

No operator steps. The artifact regen is automatic; the CI gate is mechanical; no infra,
no secrets, no vendor account. (Automation feasibility gate: nothing to defer.)

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

1. Confirm pinned version: `grep -n "likec4@" apps/web-platform/Dockerfile` ->
   `1.50.0`; `grep -n '@likec4/core\|@likec4/diagram' apps/web-platform/package.json`
   -> both `1.50.0`. The script/hook/CI MUST use this exact string.
2. Confirm the lefthook precedent shape (already read at plan time):
   `lefthook.yml` `generate-kb-index` block — `priority: 10`, single-star `glob`,
   `run: <script> && git add <generated-file>`. Mirror it.
3. Confirm `.c4` files are flat in one directory (they are) -> single-star glob
   `knowledge-base/engineering/architecture/diagrams/*.c4` is correct (gobwas `**` would
   skip depth-1 files — see learning `2026-03-21-lefthook-gobwas-glob-double-star.md`).
4. Confirm the freshness test's CI home: read `.github/workflows/ci.yml` `test-scripts`
   shard (bare ubuntu, gitleaks-install precedent at the same shard) vs `test-webplat`
   (vitest). Decide host in Phase 2 (see decision note there).
5. Confirm `jq` and `node` available in the chosen CI shard for the validation step.
6. Run the standard `## Open Code-Review Overlap` query against the final Files-to-Edit
   list (`gh issue list --label code-review --state open --json number,title,body`).

### Phase 1 — `scripts/regenerate-c4-model.sh` (the shared regen primitive)

Model it on `scripts/generate-kb-index.sh` (shebang, `set -euo pipefail`, doc comment,
`SCRIPT_DIR`/`REPO_ROOT` constants, `--help`, dir/file guards). Behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Regenerate the compiled LikeC4 model artifact from the .c4 sources.
# Pinned to likec4@1.50.0 (MUST match apps/web-platform/Dockerfile +
# package.json @likec4/core/@likec4/diagram; guarded by c4-likec4-version-pin.test.ts).
# Renders OFF-TREE to a temp path, validates structurally (exit-0 is not proof:
# likec4 exits 0 even on an empty/degenerate model), then publishes atomically.
# See learnings: 2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md.

LIKEC4_VERSION="1.50.0"
DIAGRAMS_DIR="${REPO_ROOT}/knowledge-base/engineering/architecture/diagrams"
OUT="${DIAGRAMS_DIR}/model.likec4.json"
# guard: all three sources present
for f in spec.c4 model.c4 views.c4; do test -f "${DIAGRAMS_DIR}/${f}" || { echo "missing ${f}" >&2; exit 1; }; done
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
( cd "$DIAGRAMS_DIR" && npx -y "likec4@${LIKEC4_VERSION}" export json -o "${TMP}/model.likec4.json" . )
# validate: non-empty elements (empty_model = failure, do NOT clobber)
jq -e '(.elements | length) > 0' "${TMP}/model.likec4.json" >/dev/null \
  || { echo "likec4 produced an empty model — refusing to overwrite ${OUT}" >&2; exit 1; }
# publish atomically only on success
cp "${TMP}/model.likec4.json" "$OUT"
echo "Regenerated ${OUT} ($(jq '.elements | length' "$OUT") elements, $(jq '.relations | length' "$OUT") relations)"
```

Notes carried from learnings:
- **Off-tree render + validate before publish** (`2026-06-05-render-off-tree-...`,
  `...-external-cli-exit-0-is-not-proof-...`): never `-o` directly onto the tracked path;
  an exit-0 empty export would clobber the good model.
- **Idempotent** (`generate-kb-index.sh` model): rerun produces byte-identical output.
- **Strip `GIT_*` env if spawning git** — this script spawns only `npx`/`jq`, not git, so
  no strip needed; the `git add` lives in the lefthook `run:` line, not the script.
  (Learning `2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`.)

### Phase 2 — CI freshness gate (the contract that survives a hook bypass)

A pre-commit hook can be skipped (`--no-verify`); the CI gate is the backstop. Decision:
**host the freshness test in the `test-scripts` CI shard as a bash/`node --test` test** (it
runs on bare ubuntu, already has the gitleaks-install precedent for installing a CLI, and
the check is "render + byte-diff" which is shell-shaped). Add to `.github/workflows/ci.yml`
`test-scripts` shard: a `npm install -g likec4@1.50.0` step (mirroring the gitleaks
install), then `scripts/test-all.sh scripts` runs the new test.

New test `plugins/soleur/test/c4-model-freshness.test.sh` (or a `node --test` file in the
scripts group — match the existing scripts-shard convention confirmed at Phase 0.4):

1. Render `.c4` -> temp JSON with pinned CLI.
2. Validate non-empty (reuse the script's logic or call the script with an env override
   that writes to a temp path instead of publishing).
3. Assert byte-identical to committed `model.likec4.json`; FAIL with a clear "run
   `scripts/regenerate-c4-model.sh` and commit" message on drift.

**Alternative considered (documented, not chosen):** a vitest under
`apps/web-platform/test/` — rejected because the webplat shard does not install the
likec4 CLI and the existing c4 vitest tests deliberately *mock* spawn / read source to
avoid a CLI dependency; adding a real-CLI vitest would force a CLI install into the
webplat shard for one test. The scripts shard is the cheaper, precedented home.

Wire the job graph: if the freshness test runs inside the existing `test-scripts` job, no
new required check is created (the synthetic `test` aggregator already needs
`test-scripts`). Do NOT add a standalone required check (avoids branch-protection ruleset
coordination).

### Phase 3 — `architecture` SKILL.md fix + mandate

1. **Fix the version defect** (SKILL.md `render` sub-command, ~lines 266-271): replace
   both `npx -y likec4@latest` with `npx -y likec4@1.50.0`. This aligns the skill with the
   Dockerfile/package.json pin and the version-pin test.
2. **Add the no-by-hand-step mandate** to the `diagram`, `add-container`,
   `add-component`, `add-relationship` sub-commands and the `render` sub-command: a short
   note that regeneration of `model.likec4.json` is **automatic on commit** via the
   `c4-model-regenerate` pre-commit hook (and `scripts/regenerate-c4-model.sh` for
   out-of-hook commits), so the operator/agent no longer hand-runs the export. Keep the
   `render` command available (for validation + ad-hoc regen) but reframe it as
   "validate + ad-hoc," not "the thing you must remember to run."
3. **Update the diagrams `README.md` authoring workflow** (the "Authoring workflow" /
   "Regenerate model.likec4.json" steps) to point at the script + hook and the pinned
   version, replacing the `@latest` snippet.
4. Body-prose only — do NOT touch any `description:` frontmatter (keeps AC9 trivially
   green).

### Phase 4 — Dogfood: regenerate the currently-stale artifact

1. Run `scripts/regenerate-c4-model.sh` from a clean tree.
2. Confirm the diff brings `model.likec4.json` in sync with the current `.c4` sources
   (email-triage + inngest elements present; element/relation counts match the live
   render). Commit the regenerated artifact in this PR.
3. Review `c4-model.md`'s `## Notes` against `model.c4` for prose staleness (the
   advisory surface): if the Notes omit a now-modeled system (e.g. inngest / Resend /
   email-triage), surgically add a bullet. This is a human-prose edit, not a machine
   regen. (Per learning `2026-06-04-kb-index-regen-bundles-stale-drift-...`: edit
   surgically, do not bulk-rewrite.)

### Phase 5 — Verify ACs

Run the full AC checklist: script idempotency + clobber test, `lefthook run pre-commit`,
the new CI test (pass on synced, fail on staled), version-pin test, components budget
test, and the existing `c4-*` suite.

## Architecture Decision (ADR/C4)

This plan makes **no architectural data-model decision** — it does not move an ownership
boundary, add a substrate, change a trust boundary, or reverse an ADR. It changes the
*tooling that keeps the recorded architecture honest*. Per the Phase 2.10 gate's skip
test ("would a competent engineer reading only the existing ADRs + C4 be *misled* about
the system after this plan ships?"): **no** — the system's architecture is unchanged; we
are fixing the regeneration pipeline for the model that *describes* it.

### C4 views — completeness check (all three `.c4` files read)

Read in full at plan time: `model.c4`, `views.c4`, `spec.c4`. Enumerated for THIS change:

- **External human actors:** none added/changed (the change is build tooling).
- **External systems/vendors:** the regeneration uses the `likec4` CLI — a *build-time
  developer tool*, not a runtime external system that belongs in the C4 model. No new
  `#external` element warranted.
- **Containers / data-stores:** none added/changed.
- **Actor-to-surface access relationships:** none changed.

**No C4 model edit is in scope** — confirmed against all three files, not a single grep.
(The only `.c4`-adjacent change is regenerating the *compiled artifact* from the
*unchanged* sources, which is the whole point of the feature.) Note: a separate,
pre-existing prose-staleness item in `c4-model.md`'s Notes is addressed in Phase 4 as an
advisory edit, not a model change.

## Domain Review

**Domains relevant:** none

No cross-domain implications — this is an engineering tooling / workflow-enforcement
change (lefthook hook, CI gate, shell script, skill-doc edit). No UI surface (no files
under `components/**`, `app/**/page.tsx`, etc. — the freshness test is a test, not a UI
surface). No regulated-data surface (GDPR/2.7 skip). No new infrastructure provisioning
(2.8 skip — uses the already-pinned `likec4` CLI; no server, secret, vendor, or
persistent process added).

## Observability

This plan's Files-to-Edit include `scripts/*.sh`, a CI workflow, and a test — but the
surfaces are build-time tooling, not a server/runtime error path. The observability
contract is the **CI gate itself** (a drifted artifact fails the `test-scripts` shard,
visible in the PR check) plus the pre-commit hook's stderr diagnostic.

```yaml
liveness_signal:    "CI test-scripts shard runs the C4 freshness test on every PR / push to main; cadence = per-CI-run; alert_target = the PR's required `test` status check; configured_in = .github/workflows/ci.yml"
error_reporting:    "destination = CI job log + failing status check (drift) / pre-commit hook stderr (local); fail_loud = yes — non-zero exit blocks commit (hook) or fails the merge-gating check (CI)"
failure_modes:
  - mode: ".c4 edited but model.likec4.json not regenerated"
    detection: "c4-model-freshness test renders + byte-diffs; mismatch -> test fail"
    alert_route: "CI `test` aggregator status check on the PR"
  - mode: "likec4 produces an empty/degenerate model (exit 0)"
    detection: "regenerate-c4-model.sh jq non-empty validation"
    alert_route: "script exits non-zero with diagnostic; commit blocked / CI fails"
  - mode: "likec4 CLI version drift (CLI != client renderer)"
    detection: "c4-likec4-version-pin.test.ts (existing)"
    alert_route: "webplat shard test failure"
logs:               "where = CI job log (GitHub Actions, retained per repo policy) + local pre-commit stderr; retention = CI default"
discoverability_test:
  command: "bash scripts/test-all.sh scripts   # runs the c4-model-freshness test; no ssh"
  expected_output: "freshness test PASS on a synced tree; FAIL with 'run scripts/regenerate-c4-model.sh and commit' on drift"
```

## Files to Create

- `scripts/regenerate-c4-model.sh` — pinned, off-tree-validated, idempotent regen
  primitive (Phase 1).
- `plugins/soleur/test/c4-model-freshness.test.sh` — CI freshness gate (Phase 2; final
  path/runner to match the scripts-shard convention confirmed at Phase 0.4).

## Files to Edit

- `lefthook.yml` — add `c4-model-regenerate` pre-commit command + advisory `c4-model.md`
  staleness warning (AC3, AC4).
- `.github/workflows/ci.yml` — add a `npm install -g likec4@1.50.0` runner-tool step to
  the `test-scripts` shard so the freshness test can render; ensure job-graph wiring
  (AC5, AC6).
- `plugins/soleur/skills/architecture/SKILL.md` — `@latest` to `@1.50.0`; add the
  auto-regen mandate to `diagram`/`add-*`/`render` (AC8). Body prose only (AC9).
- `knowledge-base/engineering/architecture/diagrams/README.md` — update the "Authoring
  workflow" regen snippet to the script + pinned version + hook (Phase 3.3).
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — regenerated
  (dogfood, Phase 4).
- `knowledge-base/engineering/architecture/diagrams/c4-model.md` — advisory Notes
  freshness edit if stale (Phase 4.3).
- Possibly `AGENTS.md` + the relevant sidecar — only if the budget check (AC10) shows
  headroom for a `wg-c4-source-edit-regenerates-compiled-model` pointer; otherwise skip.

## Open Code-Review Overlap

None recorded at plan time — the overlap query is deferred to /work Phase 0.6 against the
final Files-to-Edit list (the file set is tooling-only: lefthook.yml, ci.yml, a new
script, the architecture SKILL.md, diagrams docs, and the regenerated artifact). If any
open `code-review` issue names one of those paths, fold-in / acknowledge / defer per the
plan-skill Phase 1.7.5 contract.

## Test Scenarios

1. Edit a `.c4` element -> commit -> hook regenerates + stages `model.likec4.json`
   automatically (no by-hand step). AC3
2. Break a `.c4` element kind -> script/CI refuses to clobber the good JSON, exits
   non-zero with a diagnostic. AC2
3. Hand-stale `model.likec4.json` -> CI `test-scripts` shard fails the freshness test.
   AC5
4. Run the regen script twice -> second run is a no-op (idempotent). AC1
5. `grep -rn "likec4@"` across all new/edited surfaces -> only `1.50.0`. AC7
6. Dogfood: regenerate -> committed JSON gains the email-triage/inngest elements. Phase 4

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's
  section is filled (`threshold: none` with a sensitive-path scope-out reason). Fill it
  before requesting deepen-plan or `/work`.
- **Version pin (`1.50.0`, not `@latest`)** is the single most load-bearing constraint:
  every regen surface must pin it, and `c4-likec4-version-pin.test.ts` will fail at merge
  if any surface drifts to `@latest`. The SKILL.md `@latest` was a real pre-existing
  defect.
- **exit-0 is not proof:** `likec4 export json` exits 0 even on an empty/degenerate model.
  The script MUST validate `(.elements | length) > 0` off-tree before publishing, or a
  broken `.c4` silently clobbers the good artifact with a tiny empty one.
- **gobwas glob:** the lefthook `glob` must be single-star
  (`.../diagrams/*.c4`) because the `.c4` files are flat and `**` requires at least one
  intermediate directory under gobwas (skips depth-1 files).
- **`{staged_files}` is pre-commit-only** — this hook is pre-commit, so it is fine; do NOT
  copy the pattern into a pre-push block (use `{push_files}` there).
- **`c4-model.md` is human prose, not generated** — never machine-rewrite it; the hook's
  treatment of it is warn-only.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Auto-regenerate `c4-model.md` itself | It is hand-authored prose + a static embed, not a generated file; there is nothing to mechanically regenerate. Advisory warn-only instead. |
| Hook-only (no CI gate) | A hook is bypassable with `--no-verify`; CI is the backstop that makes sync a merge contract. Defense-in-depth wins. |
| CI-only (no hook) | Forces contributors to discover-then-re-run after a CI failure; the hook removes the by-hand step locally (the feature's stated goal #2). |
| vitest freshness test in webplat shard | The webplat shard does not install the likec4 CLI and existing c4 vitest tests deliberately mock spawn; would force a CLI install for one test. Scripts shard is cheaper + precedented. |
| `npx likec4@latest` | Violates the pinned-version contract; would fail `c4-likec4-version-pin.test.ts` and risk CLI-to-client schema drift in the rendered diagram. |
