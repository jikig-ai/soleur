# Tasks — zot pin bump + freshness cadence (#7282)

**Plan:** `knowledge-base/project/plans/2026-08-04-chore-zot-image-pin-bump-and-freshness-cadence-plan.md`
**Branch:** `feat-one-shot-7282-zot-pin-bump-cadence` · **PR:** #7283 · **Issue:** #7282
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (`requires_cpo_signoff: true`)

> **STATUS NOTE (2026-08-05).** This task list was authored during the PLAN phase, which was scoped
> plan-only. Implementation commits for these tasks already exist on this branch and are pushed to
> PR #7283 — they were produced by review agents during the planning phase, outside that scope
> (see the plan's revision note and the session summary). Treat every box below as **claimed but
> unverified against the plan-phase contract**: re-verify each against the diff before trusting it.
> The pre-implementation tip is preserved at tag `salvage/7282-agent-implementation`.

---

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Re-run `crane digest ghcr.io/project-zot/zot-linux-{amd64,arm64}:v2.1.20`; FAIL on any mismatch with the plan's target table.
- [ ] 0.2 Re-list `gh api repos/project-zot/zot/releases`; if a release newer than v2.1.20 exists, re-run the config-compatibility analysis before moving the target.
- [ ] 0.3 Assert (do not assume) that the `zot_last_err` scraper's alternation covers all three slog/zerolog level shapes.
- [ ] 0.4 Read `apps/web-platform/infra/zot-registry.tf` in full before editing (`hr-always-read-a-file-before-editing-it`).
- [ ] 0.5 **Measure** whether the drift detector already reports a pending `hcloud_server.registry` replace. Record verbatim in the PR body. Do not infer.
- [ ] 0.6 Record PR #7280's merge state — it determines which base the byte-delta AC is measured on.

## Phase 1 — RED: the staleness/coherence gate

- [ ] 1.1 Read `apps/web-platform/infra/cosign-trusted-root-staleness.test.sh`; adopt its `assert`/`PASS`/`FAIL` harness and terminal contract verbatim.
- [ ] 1.2 Write `apps/web-platform/infra/zot-image-staleness.test.sh` — files-present, pin-form (exactly one match per arch, decoy-proof), sidecar↔pin digest coherence, sidecar↔pin version coherence, age gate.
- [ ] 1.3 `MAX_AGE_DAYS=90` as a named constant with its cadence justification **in the script**, not only in the plan.
- [ ] 1.4 Distinct exit codes: `0` fresh, a dedicated non-1 code for stale, anything else = detector failure. Do not overload `1`.
- [ ] 1.5 Guard future dates and unparseable dates → FAIL, never a silent pass.
- [ ] 1.6 Failure messages are runbook lines naming the remedy.
- [ ] 1.7 No network in the test.
- [ ] 1.8 Confirm RED for the right reasons (sidecar absent, pin untagged).

## Phase 2 — Provenance sidecar

- [ ] 2.1 Create `apps/web-platform/infra/zot-image.provenance.md`.
- [ ] 2.2 Capture-date row byte-compatible with the sibling parser: `| Capture date (UTC) | **YYYY-MM-DD** |`.
- [ ] 2.3 Record version, both digests, and the exact `crane digest` commands.
- [ ] 2.4 Record the config-compatibility table with upstream **content anchors**, never line numbers.
- [ ] 2.5 Record non-adoption decisions (`storage.FastRestart`, `keepUntagged`) and the version-scoped claim register.

## Phase 3 — GREEN: the pin bump

- [ ] 3.1 Both locals → `ghcr.io/project-zot/zot-linux-<arch>:v2.1.20@sha256:<arch digest>`.
- [ ] 3.2 Rewrite the freshness comment; **must not claim a bot manages this pin** — a cron files an issue, a human opens the PR.
- [ ] 3.3 Do not touch `hcloud_server.registry`'s `lifecycle`; do not add `ignore_changes = [user_data]`.
- [ ] 3.4 Confirm GREEN.

## Phase 4 — Register on BOTH triggers

- [ ] 4.1 (4a) Register the gate in `.github/workflows/infra-validation.yml` beside the cosign staleness step — per-PR coherence.
- [ ] 4.2 (4b) Add `- name: Detect zot pin staleness` to `.github/workflows/rule-audit.yml`, cloned from `Detect model drift`; idempotent `zot-pin-drift` issue via find-or-update.
- [ ] 4.3 (4b-ii) Extend that step with a live upstream poll comparing the pinned version to `gh api repos/project-zot/zot/releases/latest`.
- [ ] 4.4 `actionlint` clean on both workflow files.

## Phase 5 — Remove the inert `renovate.json5`

- [ ] 5.1 Delete `renovate.json5` (zero Renovate PRs ever; no Dependency Dashboard — the config never executed).
- [ ] 5.2 Do **not** replace it with a disabled/commented variant.
- [ ] 5.3 State the residual gap plainly in the PR body: Actions SHA pins and Dockerfile base-image digests have no freshness mechanism; removing the file reveals an existing gap rather than creating one.
- [ ] 5.4 Do **not** install Renovate as part of this PR.

## Phase 6 — Re-verify the two version-scoped capability claims

- [ ] 6.1 Run the pinned v2.1.20 image locally with the repo's exact `config.json` + htpasswd.
- [ ] 6.2 Re-measure the `ci-deploy.sh` claim: `GET /v2/` answers 200-or-401, never 403. If it does not hold, STOP — downgrade the claim and file, do not ship a false comment.
- [ ] 6.3 Re-scope the `cloud-init-registry.yml` gc-endpoint claim off the v2.1.2 name.
- [ ] 6.4 Replace the stale `zot-registry.tf:55` citations with content anchors.
- [ ] 6.5 Record both outcomes in the sidecar's claim register.

## Phase 7 — `zot_image_digest` telemetry

- [ ] 7.1 Append `{{.Config.Image}}` to the **existing** `docker inspect` call — do not add a second (`#7247` comment forbids it); `RepoDigests` is an image field, not a container field.
- [ ] 7.2 Widen the consuming `read -r`.
- [ ] 7.3 Emit only the leading 12 hex chars to keep the line bounded.
- [ ] 7.4 Add `ZOT_IMAGE_DIGEST=none` to the existing sentinel arm.
- [ ] 7.5 Keep `zot_last_err` the **final** field (`zot-telemetry-parse.sh` strips that literal tail).

## Phase 8 — ADR-096 amendment + C4

- [ ] 8.1 Amend ADR-096 with the "Pin freshness" clause, including why `renovate.json5` was removed.
- [ ] 8.2 `model.c4`: add the upstream `projectZot` external system + edge; **no `renovate` element**.
- [ ] 8.3 `model.c4`: fix `zotRegistry`'s false `cx33` → `cx23` and `7168m` → `3072m`.
- [ ] 8.4 `views.c4`: add `projectZot` to the context and containers `include` lists only (not the L3 plugin view).
- [ ] 8.5 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 9 — Follow-throughs

- [ ] 9.1 Apply-tracking issue (`action-required`) with the exact dispatch invocation and the blocking conditions. *(#7287 filed during the plan phase — verify contents.)*
- [ ] 9.2 Record the #7247 falsifiable check as a follow-through, **not** an acceptance criterion.
- [ ] 9.3 Generalization issue for the other unmanaged pins. *(#7288 filed during the plan phase — verify contents.)*

## Exit gate

- [ ] E.1 Full suite green; every AC1–AC15 verified with recorded command output.
- [ ] E.2 AC3's mutation battery demonstrably reddens the gate (a gate never seen red is not a gate).
- [ ] E.3 Byte delta measured with terraform's own `base64gzip`, never `gzip -9`.
- [ ] E.4 No `ssh` verb in any runbook or AC command.
- [ ] E.5 PR body records the Phase 0.5 drift measurement and #7280's merge state.
