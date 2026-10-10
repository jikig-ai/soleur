---
title: "infra-validation tail: pin cloud-init-registry.yml render coverage (#6509); hold the zot-entry-gate deletion (#7258)"
date: 2026-10-10
slug: registry-template-render-fixture-hold-zot-entry-gate-delete
branch: feat-one-shot-6509-7258-zot-infra-validation-tail
issue: 6509
closes: [6509]
lane: cross-domain
brand_survival_threshold: none
---

# infra-validation tail: pin cloud-init-registry.yml render coverage (#6509); hold the zot-entry-gate deletion (#7258)

## Enhancement Summary

**Deepened on:** 2026-10-10 (proportionate pass: mechanical halt gates plus citation verification; no broad research fan-out for a small CI-fixture plan, per the invocation).
**Gates run:** 4.6 user-brand (present, threshold `none`, diff reaches no sensitive path), 4.7 observability (5-field block added), 4.8 PAT sweep (no hits), 4.9 UI (not triggered), 4.10 encryption (not triggered: no store or connection), 4.11 guard contract (`lint-guard-contract.py` green), 4.12 scope check (one unfenced section, all rows mapped).
**Citations verified live:** #6454 CLOSED, #6458 MERGED (3e934cf248), #6480 OPEN, #7242 CLOSED by #7244 MERGED (d31d8a2c7d), #7158 CLOSED unmerged, #6778 OPEN draft; no rule IDs cited.

### Key improvements
1. Observability block rewritten to the 5-field schema with a probe that fits Check 10's 15-second cap (pins the arm name `F23a-registry-baseline-renders`).
2. Plan-review (simplicity + correctness) folded in: sampled first+last members in the suite, full sweeps as one-time evidence, cut speculative derivation and the duplicate rc 4 arm, message-attributed assertions, expected baseline regeneration, post-merge criterion corrected for `workflow_run` arms.

### New considerations
- `web-platform-release.yml` and `post-merge-monitor.yml` start on `workflow_run` for every main merge; the correct post-merge assertion is "no release published", not "no run".
- Local terraform is 1.9.8 vs CI 1.10.5; render arms are version-insensitive for these errors, the pin is a CI concern only.

Spec lane note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed). The Domain Review below finds no cross-domain implications.

## Overview

Two small infra-validation follow-ups were bundled into one PR (draft #9906). Premise checks ran BEFORE any design work and changed the shape of both halves:

1. **#6509 (registry template not rendered by CI) — the gap it names no longer exists, but the coverage is unpinned.** `.github/scripts/validate-infra-templates.sh` now discovers `cloud-init-registry.yml` structurally (set A: the `templatefile()` referent in `zot-registry.tf`; set B: the `cloud-init*.yml` glob), derives the var map from the `.tf` call site (not hand-listed), applies the call site's `replace(...)` render strip, and schema-validates the rendered bytes. Measured on this tree: `ok  cloud-init-registry.yml (1206 lines)`, `rendered+validated 9/9`. What is genuinely missing is a **regression fixture**: `fixtures-validate-infra-templates.sh` (F1-F22) is entirely synthetic, so nothing proves the REAL registry template stays inside the rendered set or that its three failure modes (dropped map key, un-doubled `$${...}`, undeclared var) still red the gate. This PR adds that fixture and nothing else. **No edit to `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, any trigger file, or any workflow is needed.**
2. **#7258 (delete `zot-entry-gate.sh`) — the premise is FALSE on `main`, so the deletion is HELD, not executed.** The issue's reason to delete is that "the host-side `web-zot-consumer-probe` now covers both platform repos". It does not: that work lived on `feat-one-shot-resend-inbound-webhook-500` (PR #7158), which was **CLOSED unmerged**. On `main` the probe reads a single `ZOT_PROBE_REPO` derived from `var.image_name` (`web-probe.tf:22`), and `build-inngest-bootstrap-image.yml` (lines ~927-931) states in prose that "there is currently no live probe of jikig-ai/soleur-inngest-bootstrap from the host side". Per the standing instruction, the plan stops at the premise gate and does NOT delete. Independently of the premise, the deletion cannot satisfy the "fires none of the apply/release workflows" proof (see Trigger-Filter Proof): any path under `apps/web-platform/infra/` matches `apply-web-platform-infra.yml` and `web-platform-release.yml`.

**Shipping scope: #6509 only.** `Closes #6509`. #7258 stays OPEN with a comment recording the evidence and the unblock criteria (net-issue-flow: closes 1, files 0).

## Premise Validation (Phase 0.6)

| Cited premise | Check run | Result |
|---|---|---|
| #6509 open; registry template is not rendered by CI | `gh issue view 6509`; ran `validate-infra-templates.sh apps/web-platform/infra` (cloud-init shimmed for the render arms) | Issue OPEN, but **STALE on coverage**: the registry template is already discovered, rendered with the `.tf` call-site key set, strip-applied and validated. Also stale: the issue's "11 vars" (template references 16 distinct `${var}`), and its example `$${ZOT_MEMORY_CAP:-...}` (the real token is `ZOT_MEMORY_CAP_MB=`; 28 distinct `$${...}` tokens exist). The #6458 "git-data not covered by the renderer" aside is also stale (`ok  cloud-init-git-data.yml (593 lines)`). |
| #7258 open; delete script + its CI-registered test + every registration | `gh issue view 7258`; `git grep -n zot-entry-gate origin/main` | OPEN. The issue's "`run: bash ...zot-entry-gate.test.sh` step in infra-validation.yml" **no longer exists**: registration is the filesystem since ADR-252 (`run-registered-suites.sh` derives the set from `git ls-files`); the only registrations are rows in `suite-shard-legs.tsv:173` and `suite-durations.tsv:170`. |
| Nothing invokes the script | grep for every invocation shape across `apps tests scripts plugins .github .claude` | **Holds.** Only comments, the test, the two `.tsv` rows and historical KB records reference it. |
| The host-side consumer probe covers both platform repos and MERGED | read `web-zot-consumer-probe.sh`, `web-probe.tf:22`, `server.tf` (`zot_probe_repo`); `git log -S ZOT_PROBE_REPOS origin/main` (empty); `gh pr view 7158` | **FALSE.** Single repo (`regex("^[^:@]+", replace(var.image_name, "ghcr.io/", ""))`); no comma-list handling; no commit ever introduced a repo list; #7158 CLOSED, never merged. `build-inngest-bootstrap-image.yml:927-931` on main says the same. |
| #7242 fixed by #7244 | `gh issue view 7242`, `gh pr view 7244` | Holds (issue CLOSED, PR MERGED) — but the held probe work was abandoned with #7158, not unblocked. |
| Only open PR touching `infra-validation.yml` is stale draft #6778 | `gh pr list`, `gh pr view 6778 --json files` | Holds: #6778 edits `infra-validation.yml` + `plugins/soleur/test/infra-validation-detect.test.sh` (ci-guards-cannot-fail scope). **This plan does not edit `infra-validation.yml`** (the PR-time path filter already lists the fixtures file), so there is no overlap to resolve. |
| Draft PR #9906 for this branch; #9892 merged | `gh pr view` | Holds (#9906 draft, empty diff; #9892 MERGED). |

## Property List and Cut List (Phase 0.6b)

**Properties the asks buy.**
- P1: the repo's real registry template, rendered under its real `templatefile()` map, is provably part of what CI renders and schema-checks.
- P2: a map key dropped from `zot-registry.tf`, an un-doubled `$${...}`/`%%{...}`, or an undeclared `${var}` in the template turns CI red (not just a static grep).
- P3: P1/P2 cannot decay silently (the gate cannot start skipping the registry template while staying green).
- P4 (#7258): no dead, falsely-gating script remains — conditional on a replacement existing for the one thing it uniquely covered.

**Cut List.**
- "Add `cloud-init-registry.yml` to the validator" -> **cut**: P1's mechanism already exists (discovery A union B; var map derived from the `.tf`). Authority grepped: `validate-infra-templates.sh` lines 142-204 (discovery) and 446-497 (`map_keys_at`), not a consumer.
- "Derive the var map rather than hand-list it" (issue's aside) -> **cut**: already derived.
- "Wire `infra-validation.yml` path filter/steps" -> **cut**: `pull_request.paths` already lists `.github/scripts/validate-infra-templates.sh` and `.github/scripts/test/fixtures-validate-infra-templates.sh`; the fixtures run in `deploy-script-tests-fixed` (step "Fixture tests for validate-infra-templates.sh (#6454)").
- A new standalone suite file -> **cut**: it would need a new workflow step (edits `infra-validation.yml`, overlaps stale #6778, and a `.github/workflows` PR has no agent admin-merge path). Extending the already-wired fixtures file buys the same property with zero workflow edits.
- P4 deletion -> **held**, see Overview.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (measured) | Plan response |
|---|---|---|
| "Extend the validator ... so cloud-init-registry.yml is rendered with the SAME variable map zot-registry.tf passes" | Already true by construction: keys come from the `.tf` call site (`map_keys_at`), values are stubs. | No validator edit. The fixture pins this with a per-key drop loop over the real template's referenced vars. |
| "Mutation-prove it (drop a variable, un-double a `$${...}`)" | Run on scratch copies: 16/16 dropped keys -> rc 2 naming the key; 28/28 un-doubled tokens -> rc 2; `%%{` un-doubled -> rc 2; undeclared var -> rc 2; no `.tf` -> rc 4; extra unused map key -> rc 0. See Research Insights. | The same matrix becomes the fixture arms (derived from the template, not hardcoded). |
| Brief: "if #6509 needs an edit to cloud-init-registry.yml or any trigger file, STOP" | It needs none. | Proceed with #6509 only. |
| Brief: "prove the planned diff (including the DELETION) fires none of the workflows" | Deletion cannot be proven inert: `apps/web-platform/infra/**` matches `apply-web-platform-infra.yml` (push) and `apps/web-platform/**` matches `web-platform-release.yml` (push). The #6509-only diff fires none. | Ship the #6509-only diff; hold the deletion (also premise-false). |
| #7258: "test is registered by a step in infra-validation.yml" | Registration is filesystem presence (ADR-252) plus two `.tsv` rows. | Recorded in the held-deletion checklist. |

## Research Insights

**Files read.** `.github/scripts/validate-infra-templates.sh` (785 lines, exit contract 0-6); `.github/scripts/test/fixtures-validate-infra-templates.sh` (F1-F22, synthetic roots, `run_check`/`assert_rc`/`assert_out`); `.github/workflows/infra-validation.yml` (`on:` filters; jobs `validate`, `deploy-script-tests`, `deploy-script-tests-fixed`); `apps/web-platform/infra/zot-registry.tf` (single `replace(templatefile("${path.module}/cloud-init-registry.yml", {...}))` call at line 553, strip local defined in the same file); `apps/web-platform/infra/web-zot-consumer-probe.sh`; the on-filters and `-target` lists of the apply/release family (see Trigger-Filter Proof).

**Measured mutation evidence (scratch copies in the session scratchpad; no repo file edited).** Harness: copy `cloud-init-registry.yml` + `zot-registry.tf` into an empty dir, mutate the copy, run the real validator with a no-op `cloud-init` shim on PATH (the render arms exit before the schema step; the schema arm is CI-only).

| Mutation (on the copy) | n | Observed |
|---|---|---|
| none (baseline) | 1 | rc 0; `ok  cloud-init-registry.yml (1206 lines)`; `rendered+validated 1/1` |
| delete the `.tf` assignment line(s) of one template-referenced var | 16 (every distinct `${var}`) | 16/16 rc 2; terraform error names `"<key>", referenced at` |
| un-double the first `$${TOKEN` to `${TOKEN` | 28 (every distinct escaped token) | 28/28 rc 2 ("Extra characters after interpolation expression" or "vars map does not contain key") |
| un-double the single `%%{http_code}` | 1 | rc 2 |
| add `${undeclared_var}` to the template | 1 | rc 2, "vars map does not contain key" |
| remove `zot-registry.tf` (template present, no call site) | 1 | rc 4, "has template syntax but NO templatefile() call site" |
| add an UNUSED key to the `.tf` map (must-PASS, non-canonical) | 1 | rc 0 (`templatefile` tolerates unused keys) |
| first sed attempt (harness bug: unescaped brace) | 28 | all reported `NOOP` (copy byte-identical to source) — the no-op anchor works and is kept in the fixture |

Known, deliberate blind spot (already documented as F15): un-doubling a `$${x}` whose NAME equals a map key renders silently. The registry template's escaped tokens are shell variables that collide with no map key (checked: none of the 28), so the derived loop is not vacuous; a future collision would be reported by the loop's own anchor (see Risks).

**Learnings applied.** `2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md` (real render after every edit; comments are not exempt from the Terraform parser); `2026-07-11-col0-templatefile-directive-breaks-raw-yaml-parsers-sweep-all.md`. Guard-contract discipline per plan §2.12 (members drift, assembly is structural): the fixture derives its mutation targets from the template instead of naming them.

**Constraints re-read.** Registry host observation window ends 2026-10-10T01:58Z; nothing here edits any render input.

## Trigger-Filter Proof

Filters were read from the files on `origin/main` (via `yaml.safe_load` of each `on:` block plus a read of every `-target` list that could reach the registry or a web host). "Fires" means the push/pull_request path filter matches at least one changed path.

**Diff A — what ships (this PR):** `.github/scripts/test/fixtures-validate-infra-templates.sh` (edit), `plugins/soleur/test/fixture-relative-assert.baseline.txt` (NOT edited, see Addendum), `knowledge-base/project/plans/…` and `knowledge-base/project/specs/…` (plan artifacts).

| Workflow | Filter (relevant) | Diff A fires? |
|---|---|---|
| `apply-deploy-pipeline-fix.yml` | push main; 30 listed `apps/web-platform/infra/*` trigger files incl. `ci-deploy.sh`, `server.tf` | No (no listed path) |
| `registry-host-replace-dispatch.yml` | push main; `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, itself | No |
| `apply-web-platform-infra.yml` | push main; `apps/web-platform/infra/**` (minus 3 rehearsal roots), itself, `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | No |
| `mint-inngest-bootstrap-tag.yml` | push main; `apps/web-platform/infra/inngest*`, `vector.*`, `cat-inngest-*`, the build workflow, the mint workflow, `.github/scripts/mint-inngest-bootstrap-tag.sh` | No (the fixtures file is not the mint script) |
| `web-platform-release.yml` | push main; `apps/web-platform/**`, `plugins/soleur/**` minus `docs/` and `test/` | No for the PUSH arm (`.github/` and `knowledge-base/` are outside both; `plugins/soleur/test/` is excluded). Its `workflow_run` arm (CI completed on main) starts a run for EVERY main merge regardless of paths; the `check_changed` gate then declines to release, so no version bump, image build or deploy follows. |
| `build-inngest-bootstrap-image.yml` | `workflow_dispatch` only | No (and not edited) |
| `zot-image-mirror.yml` | push/PR on `zot-image-oci-archive.sh`, `zot-registry.tf`, `cloud-init-registry.yml`, probes | No |
| `apply-git-data-root-key`, `apply-github-infra`, `apply-inngest-rls`, `apply-sentry-infra`, `deploy-inngest-image`, `restart-inngest-server`, `version-bump-and-release` | dispatch-only or disjoint path sets (`infra/github/*`, `inngest-rls/`, `infra/sentry/**`, `plugins/soleur/**`) | No |
| `infra-validation.yml` (validation only, no apply) | `pull_request.paths` lists the fixtures file | **Yes — intended**: it is the job that proves the new arms. Push-to-main filter does NOT list it, so it does not re-run on merge. |

**Diff B — the held #7258 deletion (NOT shipping):** delete `apps/web-platform/infra/zot-entry-gate.sh`, `zot-entry-gate.test.sh`; remove rows from `suite-shard-legs.tsv` and `suite-durations.tsv`.

| Workflow | Diff B fires? |
|---|---|
| `apply-web-platform-infra.yml` | **Yes** — `apps/web-platform/infra/**` matches a deleted path. Its push apply is a targeted allow-list (no registry-host `-target`; the web-1 SSH targets `zot_consumer_probe_install` / `registry_insecure_config` hash only the probe files and `docker_daemon_json`, none of which are touched), so the plan would be empty, but the workflow still starts with the `infra-privileged` environment and credentials. The brief's "fires none" condition is therefore NOT met. |
| `web-platform-release.yml` | **Yes** — `apps/web-platform/**`; the inner `path_filter` is `apps/web-platform/` so a release + deploy would run. |
| `apply-deploy-pipeline-fix.yml`, `registry-host-replace-dispatch.yml`, `mint-inngest-bootstrap-tag.yml` | No (none of the deleted paths is in their lists; `zot-entry-gate.*` does not match `inngest*`). |

Conclusion: Diff A is safe to ship; Diff B is blocked twice (false premise; cannot meet the no-fire proof) and stays out of this PR. No file in the registry/web render-input set is edited by either diff.

## Plan Review Record (proportionate panel: simplicity + correctness)

Applied (Mechanical): F23c/F23b assert `terraform failed to render` (decode failure also exits 2); baseline regeneration is expected, not conditional (row 268); post-merge criterion rewritten for the `workflow_run` arms; F23d asserts the quoted name; no-op anchor resets RC/OUT; un-double anchored on a non-identifier char; deletion scoped to the `templatefile(` map; referent derivation and the rc-4 arm cut (F6a covers it); `1/1` asserted literally. Applied (Taste, decided as a technical fork): suite samples first+last members while the full 16/28 sweeps are one-time Phase 2 evidence; Phase 2 suite/SUT table trimmed to 5 rows. Not applied: trimming the Diff B proof (the brief requires the deletion proof) and shortening the #7258 census (kept as the unblock checklist). No User-Challenge items.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Extend the validator (and wire infra-validation.yml if its path filter/steps need it) so cloud-init-registry.yml is rendered with the SAME variable map zot-registry.tf passes to its templatefile() call" | Research Reconciliation row 1 + Phase 1 F23a baseline arm (already satisfied by discovery; pinned by fixture) | mapped |
| 2 | "add a fixture/test proving a missing or mis-escaped variable fails CI" | Phase 1 arms F23b-F23e | mapped |
| 3 | "Mutation-prove it (e.g. drop a variable from the map, un-double a `$${...}`, and confirm red)" | Phase 2 mutation proof + PR-body table | mapped |
| 4 | "DELETE it together with its test and every registration/reference" | Held-deletion checklist (below) | descoped — justification: the stated premise (consumer probe covers both repos and is merged) is false on main and the diff cannot meet the no-fire proof; the brief itself says "stop and report instead of deleting" |
| 5 | "VERIFY THE PREMISE FIRST ... enumerate every reference ... from a grep" | Premise Validation + Held-deletion checklist reference census | mapped |
| 6 | "BEFORE writing any code, read the on.push.paths / paths filters and -target lists ... and prove from those filters that the planned diff ... fires none of them" | Trigger-Filter Proof | mapped |
| 7 | "PR body: Closes #6509 and Closes #7258 ... threshold none ... the mutation table, and the trigger-filter proof" | PR Body Requirements | mapped (the #7258 close line is omitted: descoped per row 4) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `fixtures-validate-infra-templates.sh` | "add a fixture/test proving a missing or mis-escaped variable fails CI" | asked |
| Edit `plugins/soleur/test/fixture-relative-assert.baseline.txt` (conditional) | — | inferred — justification: row-by-row ratchet reddens on any new unguarded relative operand in a tracked fixture; regenerated only if the new code earns a row |
| Derive mutation targets from the template instead of naming vars | "Mutation-prove it" | inferred — justification: hardcoded names make the fixture rot when the template legitimately changes; derivation keeps it a property test |
| Per-key / per-token LOOPS (not first-only) | "drop a variable from the map, un-double a `$${...}`" | inferred — justification: Guard Contract §2.12, a check that stops at the first member is the defect class |
| Comment on #7258 | "stop and report instead of deleting" | asked |

### Split Assessment

- Subsystems touched: 1 — `.github/scripts/test/`
- Planned files: 1-2 (+ plan artifacts) | Estimated changed lines: ~150
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Implementation Phases

### Phase 1 — Fixture arms in `.github/scripts/test/fixtures-validate-infra-templates.sh` (RED first)

Write the new arms to fail first by running them against a deliberately broken copy (Phase 2), then confirm they pass on the real pair. Add after F22, before the `Results:` line. Update the file header comment to state the deliberate carve-out: F23 copies the REAL registry pair and mutates the COPY; the property ("this template renders under its own call site") cannot be synthesized, and mutation targets are derived from the template so growth of `apps/*/infra/` cannot break it.

Review-driven shape (plan-review applied: simplicity + correctness seats). The full 16-var / 28-token sweeps are measured ONCE in Phase 2 and recorded in the PR body, not run on every CI pass: they exercise one terraform code path, so the suite samples the first and last members, which still satisfies the "not first-only" rule.

Helpers (all roots via `newdir`; source rooted at `REPO_ROOT=$(cd "$DIR/../../.." && pwd)`, which resolves correctly from `.github/scripts/test/`):
- `reg_root <name>`: `newdir`, then `cp` exactly `cloud-init-registry.yml` and `zot-registry.tf` (no referent derivation: the map has one referent today; a second one makes the baseline arm red loudly, which is the correct signal). A missing source file is an explicit `bad`, never a skip.
- `mutate_or_bad`: after each mutation, `cmp -s` the copy against its source; if identical, set `RC=0 OUT=""` first (so `bad` does not print the previous run's globals), then `bad "<name>: mutation was a no-op"`.
- Mutations use `cp` and `python3` writes (not `> "$D/..."` redirects) to avoid adding relative-operand sites to the P1b ratchet where possible.

Arms:
- **F23a baseline** (arm name EXACTLY `F23a-registry-baseline-renders`, pinned by the Observability probe) — real pair, rc 0; output contains `ok  cloud-init-registry.yml` and `rendered+validated 1/1 file` (isolated root, exactly one member). This by-name line is the one assertion no other check provides: the `validate` job already runs the gate on the real tree, so rc 0 alone is redundant.
- **F23b a dropped map key reds** — derive the template's distinct vars with `(?<!\$)\$\{\K[a-z_][a-z0-9_]*(?=\})`; for the FIRST and LAST: delete only the key's assignment line INSIDE the `templatefile(` map of the `.tf` copy (python: locate the registry `templatefile(` call, remove the first matching `^\s*key\s*=` line after it, leaving locals untouched); rc 2 and output contains BOTH `terraform failed to render` and `"<key>"` (quoted, as terraform prints it; the decode-failure path also exits 2, so the render message is what attributes the failure).
- **F23c an un-doubled escape reds** — derive distinct `\$\$\{\K[A-Za-z_][A-Za-z0-9_]*` tokens; for the FIRST and LAST plus the single `%%{http_code}`: un-double the first occurrence, anchored on a non-identifier character after the name (`(?![A-Za-z0-9_])`, so a longer token sharing the prefix cannot be hit); `mutate_or_bad` anchor; rc 2 and output contains `terraform failed to render`. A token whose name equals a map key cannot red by design (F15) and is reported as `bad`, naming the token.
- **F23d undeclared var** — insert `${undeclared_var}` into the template copy; rc 2; output contains `terraform failed to render` and `"undeclared_var"` (the quoted name is wrap-stable; the longer "vars map does not contain key" sentence is not asserted because terraform wraps at ~78 columns under ANSI colour).
- **F23e must-PASS, non-canonical** — real pair plus ONE extra unused key in the `.tf` map: rc 0.

The "no call site -> rc 4" arm was CUT: F6a already pins it synthetically; the own-dispatch property is carried by F23a's by-name line plus Phase 2 row 1.

Runtime budget: ~8 renders at ~0.4 s plus one real `cloud-init schema` in F23a, about 5 s.

Verification target: the arms run in CI's `deploy-script-tests-fixed` job (terraform 1.10.5 + cloud-init installed). Locally (terraform 1.9.8 is present; cloud-init is not) run the suite with a no-op `cloud-init` shim on PATH to exercise every render arm; only the real-schema step of F23a is CI-authoritative.

### Phase 2 — Mutation proof (record in the PR body)

(a) **One-time full sweeps** (scratch copies; the Research Insights table is the measured template): every distinct `${var}` dropped (16/16 rc 2) and every distinct `$${TOKEN` un-doubled (28/28 rc 2), plus `%%{`, undeclared var, no-`.tf` (rc 4) and the extra-key must-PASS (rc 0). Re-run them against the finished tree and paste the counts.

(b) **Suite/SUT edits that must redden the suite** (apply, run `bash .github/scripts/test/fixtures-validate-infra-templates.sh` with the shim on PATH, record the arm, restore):

| # | Edit | Must go RED in |
|---|------|----------------|
| 1 | SUT: filter `cloud-init-registry.yml` out of `MEMBERS` (discovery loses the registry template) | F23a (by-name line and `1/1` missing) |
| 2 | SUT: derive stub keys from the template body instead of the `.tf` map | F23b (a dropped key no longer reds) |
| 3 | SUT: pre-escape `${` in the stub before render | F23c |
| 4 | Suite: `reg_root` copies only the template, not the `.tf` | F23a (rc 4) |
| 5 | Harness: shim `terraform` to exit 0 with empty output | F23a red by rc; F23b-d red by the absent `terraform failed to render` message (the decode failure also exits 2, which is why the message is asserted) — proves the arms need the real renderer |

### Phase 3 — Ratchet and registration checks (targeted, local)

1. `bash plugins/soleur/test/fixture-relative-assert.test.sh`. (Superseded at implementation, see Addendum: regeneration was avoided.) Planned expectation was to REGENERATE the baseline: `plugins/soleur/test/fixture-relative-assert.baseline.txt` row 268 holds 58 sites for this very file (all `redirect, root=never-bound` on `newdir`-derived `$D/...`), and the scan is row-by-row equality, so any new `newdir`-rooted write changes the row. Minimise new redirects (use `cp`/`python3`), then run `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` in the SAME commit and state the row delta in the commit message.
2. `bash .github/scripts/test/run-all.sh` is NOT used (the fixtures file stays out of its glob by name; see its contract note). `shellcheck` the edited file.
3. `python3 scripts/lint-guard-contract.py` on this plan (Guard Contract below).
4. Do not run the full battery locally; CI carries it (machine contention).

### Phase 4 — #7258 disposition (no deletion)

At ship time, add ONE comment to #7258 (no new issue is filed): the evidence (single-repo probe at `web-probe.tf:22`; PR #7158 closed unmerged; `build-inngest-bootstrap-image.yml:927-931`), the finding that registration is now filesystem presence + two `.tsv` rows, the trigger consequence (a deletion fires `apply-web-platform-infra.yml` and `web-platform-release.yml`), and the unblock criteria below. Leave the issue OPEN; do not use a close keyword for it in the PR body ("Refs #7258" only).

**Unblock criteria for #7258 (recorded, not scheduled here):**
1. The host-side probe covers `soleur-inngest-bootstrap` (a probe-extension PR that edits `web-zot-consumer-probe.sh` / `web-probe.tf`). That edit changes `terraform_data.zot_consumer_probe_install`'s `triggers_replace` hash and therefore fires a web-1 SSH apply — it must be scheduled outside the registry observation window and with the operator's awareness of the apply, which is why it is not folded in here.
2. That extension has been observed green on a real run.
3. Then the deletion PR is a pure delete + two `.tsv` rows, accepting the `apply-web-platform-infra.yml` + `web-platform-release.yml` starts as expected side effects (the brief's no-fire proof must be re-stated as "empty plan" at that point).

**Reference census for the deletion (from `git grep -n zot-entry-gate origin/main`, not from the issue):**
- Delete: `apps/web-platform/infra/zot-entry-gate.sh`, `apps/web-platform/infra/zot-entry-gate.test.sh`.
- Edit: `apps/web-platform/infra/suite-shard-legs.tsv` (row at line 173), `apps/web-platform/infra/suite-durations.tsv` (row at line 170); then run `plugins/soleur/test/regenerate-shard-manifest.test.sh` and `.github/scripts/test/test-infra-suite-registration.sh`.
- Comment-only references that a deletion leaves dangling (in files this arc is forbidden to touch): `apps/web-platform/infra/ci-deploy.sh:1410` (a `deploy_pipeline_fix` trigger file), `.github/workflows/build-inngest-bootstrap-image.yml:817,931`, `.github/workflows/reusable-release.yml:1219,1420`.
- Historical records, intentionally left: ADR-096 line 496, the 2026-07-29 post-mortem, the 2026-07-09 learning, and ~20 plans/specs.
- NOT references (verified absent): `infra-validation.yml`, any `test-affected-paths` mapping, `.claude/`, `scripts/`, `tests/`, `plugins/`.

## Files to Edit

- `.github/scripts/test/fixtures-validate-infra-templates.sh` — header carve-out note + F23a-F23e.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — NOT edited: the expected regeneration was avoided by routing the copy through python (row stays 58); see `evidence.md`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-6509-7258-zot-infra-validation-tail/tasks.md` (derived task list).

## Files NOT to Touch (hard constraints, verified against the Trigger-Filter Proof)

`apps/web-platform/infra/cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, `ci-deploy.sh`, every file in `apply-deploy-pipeline-fix.yml`'s path list, `.github/workflows/build-inngest-bootstrap-image.yml`, `.github/workflows/infra-validation.yml`, anything under `plugins/soleur/` outside `test/` and `docs/`. No host contact; no apply/replace workflow dispatch.

## Open Code-Review Overlap

None. (Queried 88 open `code-review` issues for `fixtures-validate-infra-templates.sh`, `validate-infra-templates.sh`, `fixture-relative-assert.baseline.txt`, `zot-entry-gate`, `cloud-init-registry.yml`: zero matches.)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the change is a CI fixture; the worst case is a spurious red `Infra Validation` check on PRs that touch the registry template, delaying an infra merge.
- **If this leaks, the user's data/workflow/money is exposed via:** no vector — the fixture copies two committed, secret-free files into a mktemp dir and renders them with stub values (`"x"`); no credential, token, or host is read.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** the diff reaches no runtime path and no user data; the sensitive-path regex does NOT match Diff A (`.github/scripts/test/` is not under `apps/*/infra/` nor a matching workflow filename). `threshold: none, reason: test-only CI fixture over committed template files; the only apps/*/infra/ work in the brief (the #7258 deletion) is held and excluded from this PR.`

## Guard Contract

### Guard 1 — registry-template render coverage fixture (F23)

**Property.** The real `cloud-init-registry.yml`, rendered under `zot-registry.tf`'s real `templatefile()` call, is a member of the set `validate-infra-templates.sh` renders and validates, and every var referenced by the template and every `$${...}`/`%%{...}` escape in it is individually load-bearing: dropping the var's map key, un-doubling the escape, or adding an undeclared var exits the gate non-zero (rc 2), while an unused extra key does not.

**Assembly.** Chokepoint: the validator's single render loop (`terraform console` over `jsonencode(templatefile(...))`, keys from `map_keys_at`) — there is exactly one render path for every member, so the fixture drives the real executor (`$EXEC`), never a re-implementation. Membership flows through discovery A (templatefile referents from `$ROOT/*.tf` and `modules/*/*.tf`) and discovery B (`cloud-init*.yml` glob); the fixture asserts the registry member by NAME in the output and via the N/N counter. The mutation populations are DERIVED at run time from the real template: distinct `${var}` references (16 today) and distinct `$${TOKEN` escapes (28 today), sampled first+last in the suite and swept in full once per change as Phase 2 evidence, plus the `%%{` form (1), so adding or removing a var/escape changes the sample, not the fixture source. Injection sites: the `.tf` map (keys), the template body (vars and escapes), and the root's file set (call-site presence). Anything outside these three sites (e.g. a value expression in the map) is out of the property and is covered by `terraform validate`/plan, not this guard.

**Mutation matrix.** (7 rows here; the full SUT/suite set is in Phase 2.)

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the map key of the FIRST and the LAST referenced var in the `.tf` copy (full 16-var sweep in Phase 2) | rc 2, `terraform failed to render`, error names the key |
| 2 | Un-double the FIRST and LAST `$${TOKEN` and the `%%{http_code}` (full 28-token sweep in Phase 2) | rc 2, `terraform failed to render` |
| 3 | Add `${undeclared_var}` to the template copy | rc 2, error names `"undeclared_var"` |
| 4 | OWN DISPATCH: filter the registry template out of discovery (Phase 2 row 1) | F23a reds on the missing `ok  cloud-init-registry.yml` line and `1/1` counter (the no-call-site rc 4 shape is pinned by existing F6a) |
| 5 | SECOND member after a compliant first: the LAST var/token is mutated while the FIRST stays compliant (and vice versa) | rc 2 for each |
| 6 | Harness: `reg_root` copies only the template (Phase 2 row 4); shim terraform to a no-op (row 5) | F23a red (rc 4); F23b-d red by the missing `terraform failed to render` message |
| 7 | Must-PASS, non-canonical: one extra unused key in the `.tf` map copy | rc 0 (a gate or harness that rejects everything fails here) |

**Anchor.** The fixture does not compare a stored value: it re-derives its populations from the real template on every run, so there is no registry or hash a single diff could edit alongside the thing it protects. The remaining coupling is the validator itself; weakening that requires editing `validate-infra-templates.sh`, which the `pull_request.paths` filter re-runs this suite against (rows 1-3 of Phase 2 are the proof).

## Observability

Layer: CI/test surface (the fixture is the only new executable; it adds no runtime, server, or host code). Declared in full because deepen-plan Phase 4.7 applies to any non-docs Files-to-Edit.

```yaml
liveness_signal:
  what: the `Results: N pass, 0 fail` line of the fixtures suite, including the F23 arms, in the deploy-script-tests-fixed job log
  cadence: every pull request touching a path in infra-validation.yml pull_request.paths (the fixtures file itself is listed)
  alert_target: the PR check status (the job is advisory today, tracked by #6480)
  configured_in: .github/workflows/infra-validation.yml step "Fixture tests for validate-infra-templates.sh (#6454)"
error_reporting:
  destination: the CI job's red status plus the suite's per-arm `FAIL [<arm>]: ... rc=<n> out=<text>` lines
  fail_loud: yes — any failed arm exits 1; a no-op mutation or a missing source file is an explicit `bad`, never a skip
failure_modes:
  - mode: registry template silently dropped from discovery
    detection: F23a by-name line `ok  cloud-init-registry.yml` and `rendered+validated 1/1 file`
    alert_route: red deploy-script-tests-fixed check on the PR
  - mode: a dropped map key or un-doubled escape stops turning the gate red
    detection: F23b / F23c rc 2 plus the `terraform failed to render` message
    alert_route: red deploy-script-tests-fixed check on the PR
  - mode: the harness mutation silently does not apply
    detection: the `cmp` anchor reports `mutation was a no-op`
    alert_route: red deploy-script-tests-fixed check on the PR
logs:
  where: GitHub Actions job log for deploy-script-tests-fixed
  retention: the repository's Actions log retention (default 90 days)
discoverability_test:
  command: grep -o -m1 F23a-registry-baseline-renders .github/scripts/test/fixtures-validate-infra-templates.sh
  expected_output: F23a-registry-baseline-renders
```

The command proves the arm is present in the committed suite without running it (the suite needs terraform and cloud-init and outruns preflight Check 10's 15-second cap); the arm's behaviour is proven by the CI job and the Phase 2 mutation table. The exact arm name `F23a-registry-baseline-renders` is therefore a contract of Phase 1.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to a CI fixture. No UI surface, no regulated data, no new store or network connection (Encryption Posture N/A), no architectural decision (no ADR/C4 impact: no actor, system, container or relationship changes; the C4 count-parity gate is untouched because no workflow count moves).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `fixtures-validate-infra-templates.sh` contains F23a-F23e; all arms PASS in CI's `deploy-script-tests-fixed` job (`Results: N pass, 0 fail`).
- [x] Each Phase 2 mutation row was executed and the named arm went RED; the table (edit -> arm reddened) is in the PR body.
- [x] `git diff --name-only origin/main...HEAD` contains NO path from "Files NOT to Touch" and nothing under `apps/web-platform/`: `git diff --name-only origin/main...HEAD | grep -E '^(apps/web-platform/|\.github/workflows/|plugins/soleur/)' | grep -vE '^plugins/soleur/(test|docs)/'` prints nothing.
- [x] `bash plugins/soleur/test/fixture-relative-assert.test.sh` is green (baseline regenerated in-commit only if required, with the reason in the commit message).
- [ ] `shellcheck .github/scripts/test/fixtures-validate-infra-templates.sh` clean; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] PR body: `Closes #6509` on its own line; `Refs #7258` (NOT a close keyword); threshold `none` with the reason above; the mutation table; the Trigger-Filter Proof (Diff A fires none of the apply/replace/mint/release workflows; Diff B would fire two and is held); the reduced-panel disclosure (proportionate review panel, as on #9892); the net-issue-flow line (closes 1, files 0); ends with the Claude Code attribution line.
- [ ] PR checks: `Infra Validation` ran (path filter match on the fixtures file); post-merge verification per the section below.
- [ ] Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

### Post-merge (operator-free)

- [ ] Run `soleur:postmerge`; confirm for the merge commit: `Infra Validation` ran on the PR only (its push filter does not list the fixtures); ABSENCE of `Apply web-platform infra`, `Apply deploy-pipeline-fix`, `Registry host replace — Delivery Dispatch` and `Mint inngest bootstrap tag` runs; and, because `Web Platform Release` and `post-merge-monitor` start on a `workflow_run` of CI for every main merge, assert instead that NO release was published and the release jobs were skipped/declined (`check_changed` false), not that no run exists.
- [ ] #6509 auto-closes via the PR body; #7258 remains OPEN and carries the evidence comment (Phase 4).

## Test Scenarios

- Given the real registry pair, when the validator runs, then it prints `ok  cloud-init-registry.yml` and an N/N counter, exit 0.
- Given a `.tf` map missing any one referenced var, then exit 2 and the terraform error quotes that var.
- Given any single `$${TOKEN` (or `%%{`) un-doubled, then exit 2.
- Given an undeclared `${var}` in the template, then exit 2.
- Given a template with no call site, then exit 4.
- Given an extra unused map key, then exit 0 (must-PASS).
- Given a no-op mutation (pattern did not match), then the suite reports a named `bad`, not a pass.

## Risks and Sharp Edges

- **Real-corpus fixture vs the suite's "synthetic only" header.** Deliberate, documented carve-out; the property ("this file renders under its call site") cannot be synthesized. Derived populations keep it from rotting. If `zot-registry.tf`'s map ever gains a multi-line value for a template var, dropping only the key's first line leaves continuation lines and the arm reports a non-rc-2 verdict naming the key — a loud, attributable false-red to fix in the fixture, not a silent weakening.
- **Un-double collision.** A future shell variable whose name equals a map key renders silently when un-doubled (F15); the loop names it as `bad` rather than skipping.
- **Runtime.** ~5 s added to a job with a 15 min ceiling; the 120 s per-call `timeout` stays in force per render.
- **`deploy-script-tests-fixed` is advisory** (tracked as #6480): the new arms are a visible-red signal, not a merge-blocking gate, exactly like F1-F22. Stated so the PR body does not overclaim.
- **Mid-run baseline drift.** `origin/main` moved during planning (three infra commits, none touching the registry template); re-run the baseline arm after the Phase 7 sync.
- **User-Brand Impact must stay filled.** A plan whose `## User-Brand Impact` section is empty, boilerplate, or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- **Held half, not dropped.** #7258's unblock path edits a web-1 SSH apply trigger; it must not be folded into any PR that is merged during the registry observation window.

## Addendum — 2026-10-10 (implementation and review, #6509)

- **Baseline not regenerated.** The copy goes through python and `reg_root` binds the root under `$TMP`, so the P1b row for the fixtures file stays at 58 sites; `fixture-relative-assert` is green with no baseline edit. Earlier sentences in this plan that expect a regeneration (Diff A, the review record, Phase 3 step 1) are superseded by this. Measured record: `evidence.md` in the spec directory.
- **Review round (3 seats: test-design, security, simplicity; reduced from the class baseline, disclosed in the PR).** Applied inline: an anti-vacuity floor (`MIN_ASSERTIONS=68`, `printf` + `exit 1`, accepted by `guard-vacuity-floor.test.sh`) so deleting F23 arms cannot read green; the extra-key arm now refuses to write unless the key lands inside the map; `F23a-render-strip-applied` pins the call site's `replace(...)` strip; stale comments, header, last-element expansion and the `read -d ''` return fixed. Not applied (technical taste): collapsing the 7-mode python helper into sed one-liners (one helper keeps landing semantics uniform and keeps the ratchet row unchanged); asserting the mutated line number in F23c (render fault attribution is covered by F23b/F23d naming the key). Disclosed, not filed: `map_keys_at` in the validator harvests keys after `,`/`{` inside map comments (a documented "bias permissive" choice in the validator); a commented `key =` can mask a dropped key. Today's map carries no such comment.
