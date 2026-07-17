---
date: 2026-07-18
type: fix(infra)
branch: feat-one-shot-inngest-bootstrap-v1-1-23-bake-pin
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
umbrella: "#6178 (ADR-100 Inngest dedicated-host cutover)"
status: draft
---

# fix(infra): rebake soleur-inngest-bootstrap image at v1.1.23 + bump the OCI pin (ADR-100 cutover prerequisite)

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-18

**Deepen-plan halt gates — all PASS (no telemetry emitted):**
- 4.6 User-Brand Impact — present, threshold `single-user incident`, non-placeholder.
- 4.7 Observability — present, 5-field schema populated, `discoverability_test.command` is ssh-free.
- 4.8 PAT-shaped variable — none.
- 4.9 UI-wireframe — not a UI surface (cloud-init `.yml`); skip.
- 4.5 Network-outage / 4.55 Downtime & Cutover — do NOT fire: the only reboot/replace referenced is
  the explicitly out-of-scope `inngest-host-replace`; the change touches `hcloud_server` `user_data`
  only, which the running host pins via `lifecycle { ignore_changes = [user_data, image, …] }`
  (`server.tf:265`) — exactly the carve-out 4.55 exempts. No in-scope `terraform apply`, no SSH symptom.

**Live-verified citations (2026-07-18):**
- `origin/main` HEAD `68c2ff458`; `git merge-base --is-ancestor 119861998 origin/main` → 0 (fix is in main).
- `vinngest-v1.1.22` is the semver-max published GHCR tag (built 2026-07-16); no `v1.1.23`.
- `inngest-bootstrap.sh` drift = commit `119861998` (bundle; #6552 CLOSED confirms op=rollback content).
- `vector.toml` drift = commit `938863a9d` (PR #6610, issue #6604 LUKS) — only the `luks-monitor` line;
  `inngest-cutover-flip` was already baked at v1.1.22 (`git show vinngest-v1.1.22:…vector.toml` line 166).
- Umbrella #6178 is OPEN (stays open — close no issues).
- Precedent: this is the canonical pin-bump the drift-guard (`cloud-init-inngest-bootstrap.test.sh`
  AC6/AC6b, #4675 + #6536) was built to enforce — no novel pattern.

**Key improvement over the task background:** corrected the drift provenance (bootstrap.sh via the
#6178 bundle; vector.toml via #6604 LUKS — NOT the flip marker, which was already baked) and surfaced
the load-bearing tag↔pin coupling the drift-guard imposes (pushing the tag red-lines AC6 until the
pins bump). Neither was in the original framing.

## Overview

The dedicated Inngest host (`hcloud_server.inngest`, 10.0.1.40) and any web host with
`web_colocate_inngest=true` cold-boot by `docker pull`-ing a pinned
`ghcr.io/jikig-ai/soleur-inngest-bootstrap:<tag>` image and `docker cp`-ing **both**
`inngest-bootstrap.sh` **and** `vector.toml` (plus the durable-Redis assets and the #6178
cutover-flip trio) out of it, then running the bootstrap. The image is a **content carrier**:
whatever those files look like at the tagged commit is what a freshly-provisioned host runs.

The newest published tag is `vinngest-v1.1.22` (built 2026-07-16, confirmed latest on GHCR).
Since that build, the two extracted carrier files have both drifted on `origin/main`:

- **`inngest-bootstrap.sh`** — `+101/-27` from the #6178 cutover/heartbeat/observability
  bundle (commit `119861998`, PRs #6552/#6553/#6555/#6556): op=rollback
  `INNGEST_HEARTBEAT_URL` delete, the flip-guard `flushed` allowlist entry, `DOPPLER_PROJECT`
  delivered via `/etc/default/inngest-server`, and the journald-tag drift-guard + OnFailure log unit.
- **`vector.toml`** — `+6` from commit `938863a9d` (PR #6610, issue #6604 — the `/workspaces` LUKS
  cutover): the `luks-monitor` entry added to the Source-4 (`host_scripts_journald`)
  `include_matches.SYSLOG_IDENTIFIER` allowlist.

No `vinngest-v1.1.23` tag was ever pushed and the OCI pin still reads `v1.1.22` at all three
sites. A future gated `inngest-host-replace` (`terraform apply -replace=`, which force-replaces
**regardless of any `user_data` diff**) would therefore boot a host from the **pre-bundle**
`inngest-bootstrap.sh` and a `vector.toml` missing the `luks-monitor` drift-log channel. This is
exactly `hr-tagged-build-workflow-needs-initial-tag-push`: main contains the fix, but the build
artifact the host actually consumes was never rebuilt.

**This PR is the SAFE, latent prerequisite only.** It (1) pushes the tag that rebakes the image
at current `origin/main` and (2) bumps the OCI pin `v1.1.22 → v1.1.23` at all three sites. It does
**not** touch the cutover FSM, `op=arm`/`op=flip`, force-replace, or the `INNGEST_BASE_URL`
repoint — those are gated and planned separately under umbrella #6178, which stays open.

## Research Reconciliation — Task Background vs. Codebase (verified 2026-07-18)

| Premise (task background) | Verified reality | Plan response |
|---|---|---|
| Tag points at commit `119861998` | `origin/main` HEAD is `68c2ff458`; **4 commits landed after** the bundle; `119861998` is an ancestor of HEAD. | Tag `origin/main` HEAD **at execution time** (contains the fix). Never hardcode a SHA or the bundle commit; never tag the feature branch. Assert `119861998` is an ancestor of the tag. |
| The bundle `119861998` changed `vector.toml` | `119861998` changed **`inngest-bootstrap.sh`** (+101/-27) but **not** `vector.toml`. `vector.toml` drifted via a **different** commit `938863a9d` (PR #6610, issue #6604 LUKS), adding the `luks-monitor` Source-4 entry. | Rebake still required (both carriers differ from baked v1.1.22). Provenance corrected in Overview. |
| Stale image drops the `inngest-cutover-flip` no-SSH marker (Source-4 allowlist) | `inngest-cutover-flip` was **already** in v1.1.22's `vector.toml` (`vector.toml:166`, verified via `git show vinngest-v1.1.22:…`). It is **not** the drift. | The real `vector.toml` drift is `luks-monitor`; the real `inngest-bootstrap.sh` drift is the #6178 bundle. Flip-marker claim corrected — the marker is not the justification, the bundle + luks drift is. |
| Bump 3 sites; re-grep for a drift-guard fixture that pins the tag | Confirmed 3 real pin sites. The drift-guard test `cloud-init-inngest-bootstrap.test.sh` (AC6/AC6b) derives `LATEST_TAG` **dynamically** from `git tag --list 'vinngest-v*' | sort -V | tail -1` — there is **no hardcoded tag fixture** to bump. Other `v1.x` literals (`ci-deploy.test.sh` v1.0.0/v9.9.9/attacker; `zot-soak-6122.test.sh` v1.1.19) are **synthetic** security/soak fixtures. | Bump exactly the 3 real pins. Edit **no** test/fixture. Explicitly assert the synthetic fixtures are untouched. |

**New load-bearing finding (not in the task background):** the drift-guard couples the tag and
the pins. `cloud-init-inngest-bootstrap.test.sh` AC6 asserts **both** `cloud-init.yml` and
`cloud-init-inngest.yml` pin the semver-max published `vinngest-v*` tag. The moment
`vinngest-v1.1.23` is pushed, `LATEST_TAG` becomes `v1.1.23` and the guard demands `v1.1.23`
pins. This is NOT "bump the pin whenever" — the tag push and the pin bump are a coupled unit, and
the feature branch must carry the bumped pins so its CI validates green against the just-pushed tag.

## User-Brand Impact

**If this lands broken, the user experiences:** a future (separately gated) `inngest-host-replace`
boots the singleton Inngest control-plane host from a stale or nonexistent image — either the OCI
pull FATALs (`cloud-init-inngest.yml:353`) and the host never bootstraps (async cron/event
processing outage for all users), or it boots pre-#6178-bundle `inngest-bootstrap.sh` and the
cutover safety fixes silently never run. This is the operator-blind dark-host failure the #6178
umbrella exists to prevent.

**If this leaks, the user's data is exposed via:** N/A — no secrets or PII in scope. The tag and
the pin are public version strings; no leak vector.

**Brand-survival threshold:** single-user incident — the dedicated Inngest host is a singleton
control plane; a botched prerequisite that later boots a dark/pre-fix host on force-replace is a
single-incident-class, operator-blind failure. `requires_cpo_signoff: true`; `user-impact-reviewer`
runs at review time.

## Sequencing (load-bearing gate order)

1. `git fetch origin`. Confirm `git merge-base --is-ancestor 119861998 origin/main` (the fix is in
   main's history). Create an **annotated** tag `vinngest-v1.1.23` pointing at `origin/main` HEAD
   (matches the annotated-tag convention of prior `vinngest-v*` tags) and push it:
   `git tag -a vinngest-v1.1.23 origin/main -m "…" && git push origin vinngest-v1.1.23`.
2. The push triggers `build-inngest-bootstrap-image.yml` (`on: push: tags: ['vinngest-v*.*.*']`),
   which checks out the tagged commit and bakes its `inngest-bootstrap.sh` + `vector.toml` (+ the
   Redis assets + cutover trio) into `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23`.
   **Wait for the run to conclude `success`** (`gh run watch` / `gh run view`).
3. **Verify v1.1.23 is pullable from GHCR** before merging: `docker manifest inspect
   ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23` exits 0 (or GHCR package-versions lists the
   `v1.1.23` tag).
4. On the feature branch, bump the 3 OCI pins `v1.1.22 → v1.1.23`. The branch's CI now fetches the
   just-pushed tag, so AC6/AC6b validate **green** against `v1.1.23`.
5. **Merge promptly.** Because AC6 keys on the semver-max published tag, pushing `v1.1.23` red-lines
   the drift guard for `main` and for any other in-flight infra PR until this pin bump merges. Keep
   the tag→build→verify→merge window tight.

Why merging is latent (nothing pulls v1.1.23 until the gated force-replace):
- The pin bump edits `.yml` files, not `apps/web-platform/infra/*.tf`, so it does **not** trigger
  `apply-web-platform-infra.yml` (which fires only on `infra/*.tf` merges).
- `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, …] }` (`server.tf:265`), so
  cloud-init changes never re-apply to running web hosts.
- The dedicated host re-reads its cloud-init only on the dispatch-only
  `apply_target=inngest-host-replace` force-replace — a NON-GOAL of this PR.

## Infrastructure (IaC)

No new infrastructure (no new server/service/secret/vendor/DNS/cert). This is a version-pin bump
on an existing image reference plus a git-tag push that triggers an existing build workflow.
**Apply path: NONE** — `terraform apply` / `inngest-host-replace` is an explicit non-goal. The new
pin reaches a host only via the separately-gated force-replace. No `*.tf` edited → the auto-apply
workflow does not fire.

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a mechanical prerequisite implementing the cutover already
recorded in ADR-100 (`inngest-dedicated-single-host-singleton-control-plane`) and ADR-106
(`inngest-cutover-preflight-scan-bounding-and-in-surface-marker`). No new ADR; the umbrella #6178
stays open for the gated cutover.

**C4: no impact (dependency-bump carve-out).** Read against `model.c4` / `views.c4` / `spec.c4`:
the Inngest Server container (`model.c4:188`), its Postgres (`:192`) and Redis (`:196`) are already
modeled. This change bumps the image **tag** the existing container boots from — a version detail,
not a modeled element. No new external human actor, no new external system/vendor, no new
container/data-store, no changed actor↔surface access relationship. Per the gate's explicit
"dependency bump → skip" carve-out, no `.c4` edit is warranted.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — line ~341: `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.22` → `…:v1.1.23` (re-grep for the current line; do not trust the number).
- `apps/web-platform/infra/cloud-init.yml` — line ~698: `IREF=…:v1.1.22` → `…:v1.1.23`; line ~704: `ZIREF="$ZURL/jikig-ai/soleur-inngest-bootstrap:v1.1.22"` → `…:v1.1.23`.

**No test/fixture edits.** The drift-guard derives the expected tag dynamically. Do **not** touch
`ci-deploy.test.sh` (v1.0.0/v9.9.9/attacker synthetic fixtures) or
`scripts/followthroughs/zot-soak-6122.test.sh` (v1.1.19 synthetic soak fixture).

## Files to Create

None.

## Git operations (actions, not file edits)

- `git fetch origin`
- `git merge-base --is-ancestor 119861998 origin/main` (assert exit 0 before tagging)
- `git tag -a vinngest-v1.1.23 origin/main -m "rebake inngest-bootstrap image with #6178 bundle + #6604 luks-monitor vector.toml (ADR-100 cutover prerequisite)"`
- `git push origin vinngest-v1.1.23`

## Open Code-Review Overlap

None — no open `code-review` issue tracks the `cloud-init*.yml` OCI-pin lines (version-string bump only).

## Domain Review

**Domains relevant:** engineering (infrastructure).

### Engineering / Infra

**Status:** reviewed (carry-forward to deepen-plan domain triad)
**Assessment:** Infra-only change (cloud-init OCI pins + git tag). The load-bearing correctness is
the existing drift-guard (`cloud-init-inngest-bootstrap.test.sh` AC6/AC6b) plus the explicit
build-success + GHCR-pullable verification. Latency/apply-path validated against `server.tf`
(`ignore_changes=[user_data]`) and `apply-web-platform-infra.yml` (`*.tf`-only trigger). CPO
sign-off recorded via the `single-user incident` threshold (auto-accepted in pipeline; covered by
deepen-plan's domain agents).

### Product/UX Gate

Not relevant — no UI-surface file in Files to Edit (cloud-init `.yml`, not `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx`). NONE.

## Observability

```yaml
liveness_signal:
  what: build-inngest-bootstrap-image.yml workflow run for the vinngest-v1.1.23 tag
  cadence: on-tag-push (one-shot)
  alert_target: gh run list/watch failure + GitHub Actions UI (non-zero conclusion)
  configured_in: .github/workflows/build-inngest-bootstrap-image.yml
error_reporting:
  destination: GitHub Actions run status (build fails loud, non-zero exit); GHCR publish failure surfaces as an absent v1.1.23 tag
  fail_loud: true
failure_modes:
  - mode: build workflow fails
    detection: gh run list --workflow=build-inngest-bootstrap-image.yml shows conclusion=failure
    alert_route: gh CLI / Actions UI
  - mode: image built but not pullable
    detection: docker manifest inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23 exits non-zero
    alert_route: pre-merge verification AC (in-session)
  - mode: partial pin bump (IREF bumped, ZIREF stale) or missing ref
    detection: cloud-init-inngest-bootstrap.test.sh AC6b (count==2 && distinct==1)
    alert_route: infra-validation CI
  - mode: pin drift vs latest published tag
    detection: cloud-init-inngest-bootstrap.test.sh AC6 (PIN==LATEST_TAG for both cloud-init files)
    alert_route: infra-validation CI
logs:
  where: GitHub Actions run logs for build-inngest-bootstrap-image.yml
  retention: GitHub Actions default
discoverability_test:
  command: gh run list --workflow=build-inngest-bootstrap-image.yml --limit 3 && docker manifest inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23
  expected_output: latest run conclusion=success AND manifest JSON returned (exit 0) — no ssh
```

## Acceptance Criteria

### Pre-merge (PR / in-session)

- [ ] **AC1 — tag provenance.** Annotated tag `vinngest-v1.1.23` exists on `origin`, and
  `git merge-base --is-ancestor 119861998 vinngest-v1.1.23` exits 0 (the #6178 fix is baked). The
  tag is on a `main` commit, never the feature branch.
- [ ] **AC2 — build succeeded.** The `build-inngest-bootstrap-image.yml` run for the tag concluded
  `success` (`gh run view <id> --json conclusion` → `success`).
- [ ] **AC3 — image pullable.** `docker manifest inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23`
  exits 0 (or GHCR package-versions lists tag `v1.1.23`).
- [ ] **AC4 — all pins bumped, none stale.** `git grep -c 'soleur-inngest-bootstrap:v1.1.22'` == 0
  and `git grep -c 'soleur-inngest-bootstrap:v1.1.23'` == 3 (cloud-init-inngest.yml ×1,
  cloud-init.yml ×2).
- [ ] **AC5 — pin consistency.** In `cloud-init.yml`, exactly 2 `soleur-inngest-bootstrap:v*` refs,
  1 distinct tag (AC6b invariant).
- [ ] **AC6 — drift-guard green.** `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  passes (AC6 for both cloud-init files against `LATEST_TAG=v1.1.23`, plus AC6b).
- [ ] **AC7 — no fixture drift.** `ci-deploy.test.sh` and `scripts/followthroughs/zot-soak-6122.test.sh`
  are unchanged; the full infra test suite is green.
- [ ] **AC8 — PR body.** Uses `Ref #6178` (NOT `Closes`); explains the bake-gap reconciliation
  (corrected bootstrap.sh vs vector.toml provenance) and that the change is latent until the
  separately-gated force-replace.

### Post-merge (operator)

None. The gated `inngest-host-replace` that actually consumes v1.1.23 is a separate, explicitly
out-of-scope action under umbrella #6178. No operator step ships with this PR.

## Test Strategy

No new test — the existing drift-guard (`cloud-init-inngest-bootstrap.test.sh`) IS the invariant
this change satisfies; the pin bump is validated *by* it. Run that test plus the infra validation
suite (`.test.sh` bash scripts under `apps/web-platform/infra/`, e.g. via the repo's infra test
harness) after the tag is pushed (so `LATEST_TAG` resolves to `v1.1.23`) and confirm green.

## Non-Goals

- No `terraform apply` / `inngest-host-replace` / force-replace / host re-provision.
- No `op=arm` / `op=flip` / cutover FSM edits / flip-guard changes.
- No `INNGEST_BASE_URL` repoint.
- No Doppler prod writes.
- Close no issues — umbrella #6178 stays open for the gated cutover.
- No test-fixture edits; no `.tf` edits.

## Sharp Edges

- **The `## User-Brand Impact` section must stay filled** — an empty/`TBD` section fails
  deepen-plan Phase 4.6.
- **Tag on `origin/main` HEAD, never the feature branch.** The build bakes the tagged commit's
  files; tagging the branch would (a) violate the drift-guard's authoritative-signal semantics and
  the annotated-tag convention, and (b) bake WIP. Assert `119861998` is an ancestor of the tag.
- **Pushing the tag red-lines AC6 for `main` and every in-flight infra PR** until this pin bump
  merges — merge in a tight window after build-success + pullable verification.
- **Do not bump synthetic fixtures** (`ci-deploy.test.sh` v1.0.0/v9.9.9/attacker;
  `zot-soak-6122.test.sh` v1.1.19). They are security/soak fixtures, not real pins; bumping them
  is a correctness regression.
- **Re-grep line numbers at work time** (`git grep -n 'soleur-inngest-bootstrap:v1.1.22'`) — the
  ~341 / ~698 / ~704 numbers are indicative, per `hr-when-a-plan-specifies-relative-paths`.
