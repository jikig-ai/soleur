---
title: "fix(registry): the replace dispatcher decides on the RENDERED user_data, so a zot digest bump delivers"
date: 2026-09-28
slug: fix-registry-dispatcher-render-diff
branch: fix-7582-registry-render-diff
issue: 7582
closes: 7582
type: bug
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix(registry): the replace dispatcher decides on the RENDERED user_data

## Overview

`registry-host-replace-dispatch.yml` delivers a merged registry-host `user_data` change by firing
`apply-web-platform-infra.yml -f apply_target=registry-host-replace`. Its delta gate decides
"did the bytes the host boots change?" by comment-stripping **`cloud-init-registry.yml` alone** at
the delivery watermark and at `github.sha`. But the host's `user_data` is
`base64gzip(replace(templatefile("cloud-init-registry.yml", {...}), local.registry_rationale_strip, ""))`
and the template map carries inputs that live elsewhere — `zot_image` (a `zot-registry.tf` local),
`doppler_sha256`/`doppler_arch` (same file), and `zot_memory_cap_mb` (derived from
`var.registry_server_type`, `variables.tf`). A zot digest bump therefore changes the bytes the host
boots, the push never even triggers the dispatcher (`paths:` lists only the template), and the new
zot sits inert until some unrelated apply replaces the host by surprise.

The fix: trigger on every render input, and let a **render diff** decide —
`registry-userdata-budget.sh <out>` already writes the exact stripped bytes that reach the host,
offline, with no credentials and no state.

This must land before PR 2 of the #8714 5.3b-iii work, which moves `zot_image_*` off `ghcr.io`
(a pure `zot-registry.tf` change — precisely the class this gate cannot see today).

## Research Insights

**Premise Validation.** #7582 is OPEN (re-read live 2026-09-28). Every cited artifact exists on
`origin/main` (`fff36b6172`): the dispatcher's `gate` step (`id: gate`), `registry-userdata-budget.sh`
(its `OUT receives the STRIPPED render` arm), `local.zot_image_amd64` / `_arm64` in `zot-registry.tf`,
and ADR-169 §"Residual, stated rather than discovered", which names this exact gap and this exact
fix shape. The mechanism is not in any ADR's rejected-alternatives list; ADR-169 records it as the
"right shape … not implemented here". No stale premise.

**Measurements (2026-09-28, `origin/main` fff36b6172).**

- Current pins: `zot_image_amd64 = ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`,
  `zot_image_arm64 = ghcr.io/project-zot/zot-linux-arm64:v2.1.20@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`.
- `bash apps/web-platform/infra/registry-userdata-budget.sh --json out` →
  `raw 171413 B, stripped 52847 B, stored 18024 B, headroom 14744 B`, rc 0 (terraform 1.9.8 local).
- The gate today: (1) watermark = head of the last successful run; (2) compare API file list;
  (3) `grep -qx cloud-init-registry.yml` else `deliver=false`; (4) comment-strip both revisions of
  the template and `diff -q`. The `push.paths` filter lists only the template and the workflow file.
- What the budget render **stubs** (so a change there is invisible to any render diff):
  `zot_memory_cap_mb = 3072` (the real value is `data.hcloud_server_type.registry.memory*1024-1024`,
  a live-catalog read), the arch branch (amd64 only), volume id, Doppler token, heartbeat URLs.
  All but the cap/arch are stable per host or length-bounded stubs; the cap and arch both derive
  from `var.registry_server_type` only.
- Sizes: `variables.tf` 66,765 B, `zot-registry.tf` 50,969 B, `cloud-init-registry.yml` 171,173 B —
  all under the contents API's 1 MB base64 ceiling, so the existing `contents?ref=` fetch pattern
  carries every BEFORE input.

**Property List.**

1. A merge that changes the stripped rendered `user_data` — from ANY render input, including a
   `zot-registry.tf`-only digest bump — makes the dispatcher decide `deliver=true`.
2. A merge that leaves the stripped render byte-identical (comment-only template edit, an unrelated
   `zot-registry.tf` / `variables.tf` edit) decides `deliver=false`.
3. A change to `registry_server_type`'s value (which the offline render stubs) decides `deliver=true`.
4. When the render cannot be measured, the gate fails in the safe direction for THAT side: an
   unmeasurable BEFORE cannot prove "unchanged" → deliver; an unmeasurable AFTER, or an AFTER over
   Hetzner's 32,768 B cap that differs, cannot prove the replace's CREATE will succeed → refuse
   (red gate, recorded by the existing `kind=gate-failed` verdict arm).
5. The delivered change is attributed to the PR(s) that touched a render input, not only the template.

**Cut List.**

- "Check out both SHAs" (issue text) → property 1 → cut in favour of the existing
  `contents?ref=<watermark>` fetch: the dispatcher is fetch-depth 1 and already fetches the BEFORE
  template this way; the AFTER tree is the checkout.
- A new terraform render implementation → property 1 → cut: `registry-userdata-budget.sh` already
  renders exactly the stored bytes; the new helper stages BEFORE inputs next to a copy of it.
- A new ADR → cut: ADR-169's residual paragraph is amended (the decision text is unchanged).
- Rendering `variables.tf` through terraform → property 3 → cut: the render stubs the only derived
  input; comparing the `registry_server_type` `default` value is exact and needs no provider.

**Applicable learnings / conventions.** fetch-depth 1 ⇒ never `git diff` against the watermark
(dispatcher comment); the compare API caps `files` at 300 (existing arm kept); fail-closed toward
delivering on "cannot prove unchanged" (existing arms); the budget script fails closed in CI when
terraform is absent (`CI` set) — the dispatch job therefore needs `hashicorp/setup-terraform`
pinned exactly as `infra-validation.yml` pins it (`@5e8dbf3c…` v4.0.0, `terraform_wrapper: false`,
the same `TERRAFORM_VERSION`); workflow `run:` bodies are unit-tested by extracting them with PyYAML
and running under `bash --noprofile --norc -eo pipefail` with a stubbed `gh`
(`plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`); suites under
`apps/web-platform/infra/*.test.sh` are auto-registered into `deploy-script-tests`, whose legs carry
setup-terraform (#8736) — so a terraform-rendering suite belongs there, not in the `test` job.

**Related.** #7552, #7555 (dispatcher), #8279 (attribution helper), #7299/#7282 (budget script),
ADR-169, ADR-190, #8714 (5.3b-iii consumer of this fix).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #7582) | Reality | Plan response |
|---|---|---|
| "Check out both SHAs, run it twice, cmp" | Job is fetch-depth 1; BEFORE files are already fetched via the contents API | Fetch the two BEFORE render inputs via `contents?ref=`, stage them beside a copy of the AFTER budget script |
| "render-diff needs terraform in the dispatch job" | True; the budget script exits 2 in CI without it | Add pinned `hashicorp/setup-terraform` to the job |
| cgroup cap derived from `registry_server_type` is a render input | The offline render stubs it (3072) | Compare the var's `default` value directly (property 3) |
| Widen `paths:` to the three files | `variables.tf` is edited often | Widen; the render diff (not the path) decides, so an unrelated edit is a cheap `deliver=false` run that advances the watermark |

## Implementation Phases

### Phase 1 — RED (tests first)

1. Create `apps/web-platform/infra/registry-render-delta.test.sh` (auto-registered into
   `deploy-script-tests`, whose legs carry setup-terraform). It extracts the workflow's `gate`
   `run:` body with PyYAML and runs it from a sandbox checkout root (the real render inputs + the
   budget script) with a stubbed `gh` answering `run list` (watermark), `compare` (a synthesized
   file list) and `contents?ref=` (base64 of a synthesized BEFORE file, keyed by path AND ref —
   a request for the wrong ref is a stub miss, exit 64). Rows:
   - G1 (the RED): BEFORE `zot-registry.tf` differs from AFTER only in `zot_image_amd64`'s digest;
     template identical; compare lists only `zot-registry.tf` → expect `deliver=true`
     (today: `deliver=false`, "Nothing since the watermark … touched").
   - G1b: G1 plus a comment-only template edit in the same range (a second render input after a
     compliant first) → still `deliver=true`.
   - G2: comment-only template edit → `deliver=false` (must-pass, non-canonical input).
   - G3: unrelated `variables.tf` edit (a different variable's default) → `deliver=false`, and the
     render is NOT run (no terraform needed on this arm).
   - G4: `registry_server_type` default change → `deliver=true`.
   - G4b: `registry_server_type` unparseable on either side → `deliver=true` (fail toward delivering).
   - G4c: AFTER `registry_server_type` starts with `cax` (arm64, which the render cannot see) → `deliver=true`.
   - G5: pin-SHAPE change — BEFORE `zot-registry.tf` carries a pin the AFTER script cannot parse →
     `deliver=true` + `::warning::` (before unmeasurable).
   - G5b: `doppler_sha256` (amd64 branch) bump only → `deliver=true` (the budget script now reads it
     from `zot-registry.tf` instead of a stub copy).
   - G6: AFTER unmeasurable (pin removed) → gate exits non-zero with `::error::` (refusal).
   - G6b: AFTER over the 32,768 B cap → gate exits non-zero.
   - G7: compare lists no render input (workflow-file-only push) → `deliver=false`, no render run.
   - G8: harness row — terraform absent from PATH with `CI` unset on a render arm → the gate must
     NOT report `deliver=false` (empty-vs-empty is unmeasurable, not identical).
   - P1: the workflow's `TERRAFORM_VERSION` equals `apply-web-platform-infra.yml`'s.
   - Success is `FAIL == 0 && PASS == EXPECTED` (equality). Terraform-absent: SKIP locally, exit 2 under `CI`.
2. Extend `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`: V-new — `COMMITS`
   empty, `RANGE=proven`, `RENDER_CHANGED=true` (gate delivered on a non-template render input) →
   the verdict says the change is NOT live and never "unchanged since the delivery watermark".
3. Extend `apps/web-platform/infra/registry-userdata-budget.test.sh`: a sandbox with a removed
   `doppler_sha256` (or `zot_pull_user`) local exits 2; the non-ghcr pin prefix still parses.
4. Run; record RED output (G1/G1b/G4/G5b `deliver=false` on today's gate).

### Phase 2 — GREEN

1. `registry-userdata-budget.sh`: read `doppler_sha256` (amd64 branch), `zot_pull_user`,
   `zot_push_user`, `registry_private_ip`, `betterstack_logs_ingest_url` and
   `registry_host_reserve_mb` (cap = 4096 − reserve, the cpx22 4 GB shape; the server-type arm
   covers memory changes) from `zot-registry.tf`, each anchored on its string/number-literal
   assignment; missing → exit 2. Relax the zot pin regex to be prefix-agnostic
   (`zot_image_amd64 = "<ref>@sha256:<64hex>"`, tag optional), so #8714 PR 2's move off `ghcr.io`
   renders as an ordinary `render=changed`.
2. Workflow `gate` step (inline; no new helper script):
   - `RENDER_INPUTS` = template + `zot-registry.tf`; `variables.tf` is decided ONLY by the
     `registry_server_type` compare (the render never reads it). None changed → `deliver=false`.
   - Server-type arm (when `variables.tf` changed): the `read_default` awk used by
     `apply-web-platform-infra.yml` at both SHAs; differ, unparseable either side, or AFTER `cax*`
     → `deliver=true` with the reason.
   - Render arm (template or tf changed): fetch BEFORE template + tf via `contents?ref=` (fetch
     failure keeps the existing fail-closed-toward-delivering arm); stage them beside a copy of the
     AFTER budget script; run the budget script on each side into an `out` file. AFTER rc≠0 or an
     empty/missing AFTER output → `::error::` + exit 1. BEFORE rc 2 / empty output →
     `deliver=true` + `::warning::`. `cmp` → `deliver=true|false`.
   - Emit `render_changed=true` plus a one-line `why=` naming the changed render inputs whenever
     the non-manual arm delivers.
   - Delete the dead `strip_comments` template diff (the render applies the real strip).
   - `timeout-minutes: 5` on the gate step.
3. `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0` before the gate,
   `terraform_wrapper: false`, workflow `env.TERRAFORM_VERSION: "1.10.5"`,
   `continue-on-error: true` — a HashiCorp download failure must not turn a registration-only or
   `variables.tf` run red; on a render arm the budget script then fails closed (exit 2 in CI) and
   the gate refuses with the script's own message.
4. Widen `push.paths` to `zot-registry.tf` and `variables.tf`. Job `timeout-minutes` 70 → 75 and
   re-derive the header sum (35 + 25 + 5 change + 5 gate = 70 min of step deadlines + checkout/setup).
5. Consumers of the non-template delivery: the dispatch `REASON` appends `why=`; the verdict's
   empty-commit arm says the render change is NOT live when `render_changed=true`, instead of
   "unchanged since the delivery watermark". Attribution stays single-path (template): a
   `zot-registry.tf` listing would attribute deliveries to the ~24 of 27 recent commits that never
   touched a render input (the #8279 defect class); an unattributed render delivery takes the
   existing owned-issue fallback.

### Phase 3 — Docs

1. ADR-169 §"Residual, stated rather than discovered": amend — the gate compares the render; the
   remaining residual is the server-type-derived inputs (value compare + `cax` arm) and the
   stubbed volume id / Doppler token / heartbeat URLs (per-host constants).
2. Runbook `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`: the
   gate's inputs and its new refusal reasons.
3. `zot-registry.tf` FRESHNESS OWNER comment: one line — a pin bump is now delivered by the
   dispatcher's render gate. (Comment-only, so it is also this PR's live proof, AC8.)

## Files to Edit

- `.github/workflows/registry-host-replace-dispatch.yml` (gate step, push paths, setup-terraform, timeouts, dispatch reason, verdict empty-commit arm, header comments)
- `apps/web-platform/infra/registry-userdata-budget.sh` (read tf literals; prefix-agnostic pin)
- `apps/web-platform/infra/registry-userdata-budget.test.sh` (new fail-closed rows)
- `apps/web-platform/infra/zot-registry.tf` (comment only)
- `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` (V-new)
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` (residual amended)
- `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`

## Files to Create

- `apps/web-platform/infra/registry-render-delta.test.sh`

## Open Code-Review Overlap

None (queried 2026-09-28: no open `code-review` issue body names the dispatcher, the delivery
helper, the budget script or ADR-169).

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a zot/Doppler/server-type change that
never reaches the registry host — the fix it carries (e.g. the #8714 ghcr.io-free zot source) is
silently not live, and the next unrelated apply replaces the host by surprise; or (b) a spurious
registry host replace on an unrelated `variables.tf` merge — a volume-preserving outage window
(minutes) on the fleet's sole pull path, during which deploys and web-host restarts cannot pull.

- **If this leaks, the user's data / workflow / money is exposed via:** no new exposure — the gate
reads public repo files and the render uses stub credentials; no secret enters the dispatch job
(the budget script's stubs are length-bounded fakes).

- **Brand-survival threshold:** aggregate pattern — a single spurious replace is a short,
self-recovering pull-path outage behind the existing preflight; the harm is the repeated pattern.

## Observability

```yaml
liveness_signal:
  what: every push touching a render input runs the dispatcher; its gate prints "render=identical|changed" and deliver=true|false in the run log and step summary
  cadence: per push to main touching cloud-init-registry.yml / zot-registry.tf / variables.tf
  alert_target: a red gate (after unmeasurable / over cap) files the existing kind=gate-failed verdict on the delivering PR or an owned issue
  configured_in: .github/workflows/registry-host-replace-dispatch.yml (gate + verdict steps)
error_reporting:
  destination: GitHub Actions run log + the verdict step's PR/issue comment (kind=gate-failed)
  fail_loud: true
failure_modes:
  - mode: setup-terraform or the render fails on the AFTER side
    detection: gate exits 1 with ::error:: naming after=unmeasurable
    alert_route: verdict step kind=gate-failed comment on the derived PR / owned issue
  - mode: BEFORE side cannot be rendered (old watermark, changed pin shape)
    detection: ::warning:: before=unmeasurable; deliver=true
    alert_route: the run proceeds to the preflight; the delivery verdict records the apply result
  - mode: AFTER render exceeds Hetzner's 32768 B cap
    detection: gate exits 1 with ::error:: (budget script rc 1)
    alert_route: verdict kind=gate-failed
  - mode: setup-terraform download fails on a render-arm push (new failure mode)
    detection: budget script exits 2 in CI ("terraform is REQUIRED in CI"); gate exits 1; the watermark does not advance until a later run succeeds or a manual re-fire delivers
    alert_route: verdict kind=gate-failed
logs:
  where: GitHub Actions run logs for registry-host-replace-dispatch.yml
  retention: 90 days (GitHub default)
discoverability_test:
  command: curl -s https://api.github.com/repos/jikig-ai/soleur/actions/workflows/registry-host-replace-dispatch.yml/runs?status=success
  expected_output: "success"
```

## Guard Contract

### Guard 1 — the dispatcher's render-delta gate

**Property.** `deliver=false` is decided only when the stripped rendered `user_data` at the watermark
and at `github.sha` are byte-identical AND `registry_server_type`'s value is unchanged.

**Assembly.** The chokepoint is `hcloud_server.registry.user_data`'s `templatefile` map in
`zot-registry.tf`; every input to it flows from `cloud-init-registry.yml`, `zot-registry.tf` locals,
or `variables.tf` (`registry_server_type`). The render is `registry-userdata-budget.sh` (the single
offline restatement of that chain — the stub residual is named in Property 3's arm). The gate's
decision has exactly three exits that can emit `deliver=false`: the "no render input changed" arm,
the `render=identical` arm, and nothing else — both are in the gate step.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | only `zot_image_amd64`'s digest differs at BEFORE | G1 RED on today's gate (`deliver=false`) |
| M2 | restore the `grep -qx "$CFG"` short-circuit | G1 red |
| M3 | gate renders BOTH sides from the AFTER inputs (stages the wrong dir) | G1 red |
| M4 | drop the `registry_server_type` arm | G4 red |
| M5 | map `before=unmeasurable` to `deliver=false` | G5 red |
| M6 | a second render input after a compliant first (`zot-registry.tf` digest + a comment-only template edit) | still `deliver=true` (G1b) |
| M8 | budget script keeps a stub copy of `doppler_sha256` | G5b red |
| M9 | map "AFTER output empty" to identical | G8 red |
| M7 | the gate never runs the render (dispatch of the guard itself) | G1 red |

**Harness rows.** A stub `gh` that serves the AFTER file for the BEFORE ref must turn G1 red (the
fixture proves it serves the mutated BEFORE); G2/G3 are must-PASS inputs that are not the canonical
tree (a comment edit, an unrelated var edit). The suite's success is `FAIL == 0 && PASS == EXPECTED`
(equality, not a floor).

**Anchor.** The stub residual (arch, cap) is stated in ADR-169; nothing stored is compared.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-169 §"Residual, stated rather than discovered" (no decision change): the delta gate now
compares the render; the remaining residual is the stubbed server-type-derived inputs, covered by a
value comparison.

### C4 views

No C4 impact: the change is internal to an existing GitHub Actions workflow already modeled as the
`github` system's CI; checked `model.c4`/`views.c4`/`spec.c4` for a registry-dispatcher element — none
is modeled at workflow granularity, and no actor, external system or relationship changes.

### Sequencing

Lands before #8714 5.3b-iii PR 2 (its zot pin move is the first delivery this gate must see).
Because this PR makes the budget script's pin regex prefix-agnostic, PR 2's move off `ghcr.io`
renders on both sides and reads as `render=changed`; PR 2 must still update the other
prefix-pinned guards (`zot-image-staleness.test.sh`, `zot-config-deadlines.test.sh`, `rule-audit.yml`).

## Plan Review (applied)

Reviewers: code-simplicity-reviewer, architecture-strategist. Applied (mechanical): inline the
render into the gate (no helper script); drop the multi-path attribution (noise on unrelated
`zot-registry.tf` commits) and fix the false "unchanged" verdict text instead; budget script reads
every tf-literal input (a stub copy made `doppler_sha256` bumps invisible); prefix-agnostic pin;
empty-output ⇒ unmeasurable; refuse on any AFTER rc≠0; server-type arm fails toward delivering and
catches `cax`; `variables.tf`-only pushes never render; setup-terraform `continue-on-error`; gate
`timeout-minutes: 5` and job 75; TERRAFORM_VERSION parity row; AC8 made reachable via a
comment-only `zot-registry.tf` edit. Taste, not applied (persisted to decision-challenges.md):
running the render in a separate least-privilege job.

## Acceptance Criteria

- [ ] AC1 G1 is RED against `origin/main`'s gate body and GREEN after the change (both outputs recorded in the PR body).
- [ ] AC2 G2–G7 and all helper rows pass; the suite asserts `PASS == EXPECTED`.
- [ ] AC3 `registry-userdata-budget.test.sh` passes with its new fail-closed rows (EXPECTED_CHECKS moved).
- [ ] AC4 `registry-host-replace-dispatch-verdict.test.sh` still passes (the change/verdict bodies it extracts are intact).
- [ ] AC5 `push.paths` includes `zot-registry.tf` and `variables.tf`; the job has pinned `setup-terraform` before the gate.
- [ ] AC6 `actionlint` clean on the workflow; `infra-validation` green on the PR head (checked explicitly).
- [ ] AC7 ADR-169 residual amended; runbook updated.
- [ ] AC8 Post-merge: the merge push runs the dispatcher (workflow + `zot-registry.tf` comment changed); its gate renders both sides with terraform in Actions and logs an identical render and `deliver=false` — the live proof the render arm works, with no replace dispatched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI delivery gate).

## Test Scenarios

G1–G8, P1, V-new, the budget-suite rows; AC8 as the live scenario.

## Sharp Edges

- The dispatcher's merge push (AC8) must NOT dispatch a replace: this PR changes no render input,
  so `render=identical` is the expected — and asserted — outcome.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails
  `deepen-plan` Phase 4.6.
- `variables.tf` in `push.paths` fires the dispatcher on unrelated merges; each such run must stay a
  cheap `deliver=false` and advance the watermark — a red there would stick (the watermark only
  advances on success).
