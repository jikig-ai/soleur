---
issue: 4692
branch: feat-inngest-dispatch-tag-invariant
pr: 4693
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: ../brainstorms/2026-05-31-inngest-dispatch-tag-invariant-brainstorm.md
spec: ../specs/feat-inngest-dispatch-tag-invariant/spec.md
---

# arch: inngest-bootstrap publish invariant via tag-driven `workflow_dispatch`

## Overview

`.github/workflows/build-inngest-bootstrap-image.yml` publishes `ghcr.io/jikig-ai/soleur-inngest-bootstrap:vX.Y.Z` from two paths. The `workflow_dispatch` path takes a free-form `inputs.tag` and runs `docker push` **without minting a `vinngest-v*` git tag**, so the consumption-side drift-guard (`cloud-init-inngest-bootstrap.test.sh` AC6, PR #4676) — which trusts the semver-max `vinngest-v*` tag as the "image published" signal — can stay green while prod runs a divergent bootstrap. Real incident: `v1.1.11` published via two dispatch runs on 2026-05-30 (`sha=d844b41d`), tag backfilled retroactively.

**Decided approach (brainstorm Option 3):** change `workflow_dispatch` to take an *existing* `vinngest-v*` tag as `inputs.ref` (validated **before** checkout). The dispatch path can then only re-publish a version that already has a tag — a tagless publish becomes structurally impossible. Keep `permissions: contents: read` (no `contents: write` privilege bump). The load-bearing invariant is **input-regex validation + checkout-of-the-named-tag** (prevention); divergence *detection* remains the existing consumer AC6 guard. Extract the tag-derivation (`resolve-tag`) into a unit-testable shell guard, because `workflow_dispatch` can't be live-triggered on a feature branch pre-merge.

Small diff, `single-user incident` threshold (inngest runs user background jobs). CPO sign-off carried from brainstorm; `user-impact-reviewer` runs at PR review.

**Plan-review applied (DHH + Kieran + code-simplicity):** cut the post-push tripwire assertion (tautological on both real paths, fires after the irreversible push, redundant with the resolve-tag unit test and the consumer AC6 guard); cut `fetch-tags: true` (not load-bearing — requested tag is local via checkout's refspec); collapse the guard to a single `resolve-tag` subcommand (the pre-checkout validate must live inline anyway); drop the standalone ADR (rationale lives in brainstorm + this plan). Kieran's correctness fixes folded into the ACs/scenarios.

## Research Reconciliation — Spec vs. Codebase

| Spec/initial claim | Reality (verified this session) | Plan response |
|---|---|---|
| spec TR2: dispatch checkout **needs** `fetch-tags: true` | `actions/checkout` v4.3.1 source (`ref-helper.ts`): a tag-ref checkout writes a local `refs/tags/X` via refspec `+refs/tags/X:refs/tags/X`. The requested/triggering tag is local on both paths with defaults; `fetch-tags` is unneeded. | **Cut `fetch-tags`** (plan-review: YAGNI once the tripwire is gone). Add a one-line checkout comment citing the refspec so the omission is self-documenting. |
| spec referenced a `.test.sh` test | `.github/scripts/test/run-all.sh` (run by `pr-quality-guards.yml:18`) auto-discovers via a `test-*.sh` glob. | Name it `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` (`test-` prefix load-bearing). No `run-all.sh` edit. |
| "every published image needs a producer-side assertion" | The assertion is tautological on both real paths (checkout-of-the-tag ⇒ tag points at HEAD) and fires after `docker push`. Derivation bugs are caught by the `resolve-tag` unit test; divergence by the consumer AC6 guard. | **Cut the post-push assertion** and its subcommand/scenarios. Invariant = input-regex + checkout (prevention); detection = consumer AC6. |
| producer/consumer regex parity | Consumer `cloud-init-inngest-bootstrap.test.sh:~187` matches `^v[0-9]+\.[0-9]+\.[0-9]+$` against an **already-stripped** value (`sed 's/^vinngest-//'` first). Only the guard's *post-strip* regex equals it — NOT the inline `^vinngest-v…$` validate regex (Kieran P1-a). | AC names the `resolve-tag` stripped regex specifically and replicates the consumer's strip-then-match shape. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue referencing `build-inngest-bootstrap-image.yml`.

## User-Brand Impact

**If this lands broken, the user experiences:** background jobs (inngest-driven user work) silently degrade because prod runs a bootstrap image that diverged from what the drift-guard believes is published.
**If this leaks, the user's workflow is exposed via:** n/a — no PII / credentials / data surface (CI build-supply-chain only).
**Brand-survival threshold:** single-user incident. This change strictly *reduces* exposure — closes the tagless-publish vector without the `contents: write` bump approach 1 would add. (Carried from brainstorm.)

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`; scope unchanged).

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward + SpecFlow Phase 3 + 3-agent plan-review).
**Assessment:** Option 3 recommended; keeps `contents: read`, keeps the CVE-rebuild escape hatch, makes the tag a publish precondition. SpecFlow's P0/P1 edge cases were folded into the resolve-tag scenarios; plan-review trimmed the producer-side tripwire as redundant with the consumer AC6 guard.

### Product/UX Gate
**Tier:** none — pure CI plumbing, no end-user surface; no new `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx`. **CPO sign-off** (threshold = single-user incident): covered by brainstorm carry-forward.

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward). No PII / user-data / third-party surface. `contents: read` is the stronger least-privilege/SLSA posture.

### GDPR Gate (2.7)
Trigger (b) fired (threshold), but CLO assessed **zero regulated-data / PII / cross-controller movement** (CI YAML + bash + nothing else). Covered by CLO carry-forward; no separate scan (no-op on a data-free change). Recorded, not skipped silently.

### IaC Gate (2.8)
Skipped — provisions nothing, runs no remote-host commands, mutates no secret store, adds/elevates no permission (stays `contents: read` + `packages: write`).

## Observability

(`.github/workflows/` is outside the Phase 2.9 code-class trigger paths, but the feature *is* CI observability of a publish event.)

```yaml
liveness_signal:
  what: cloud-init pin drift-guard (AC6) comparing the pin to the semver-max published vinngest-v* tag
  cadence: every PR / infra-validation run; every image publish is now tag-anchored
  alert_target: red infra-validation.yml run (AC6) on PRs
  configured_in: .github/workflows/infra-validation.yml + apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
error_reporting:
  destination: GitHub Actions run conclusion (failed step -> failed run, visible in Actions UI + PR checks)
  fail_loud: true  # set -euo pipefail; inline validate exits 1 on a non-tag ref before any publish
failure_modes:
  - mode: dispatch attempts a tagless / non-tag ref
    detection: inline pre-checkout regex rejects it -> red run BEFORE any publish
    alert_route: GitHub Actions failed run on build-inngest-bootstrap-image
  - mode: cloud-init pin drifts from the semver-max published tag
    detection: AC6 in cloud-init-inngest-bootstrap.test.sh (unchanged consumer guard)
    alert_route: red infra-validation.yml run on PRs
logs:
  where: GitHub Actions run logs (build workflow + run-all.sh fixture output in pr-quality-guards.yml)
  retention: GitHub default (90 days)
discoverability_test:
  command: "gh run list --workflow=build-inngest-bootstrap-image.yml --limit 5 --json event,conclusion,headSha  # NO ssh"
  expected_output: "every published headSha has a vinngest-v* tag (git tag --points-at <sha>); no dispatch run without one"
```

## Implementation Phases

### Phase 0 — Preconditions (at /work start)
1. Confirm the seam is still on `main` (dispatch path has no tag-push step).
2. Read `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh:178-209`; copy the consumer's stripped-tag regex (`^v[0-9]+\.[0-9]+\.[0-9]+$`, ~line 187) verbatim — the guard's `resolve-tag` post-strip regex must equal it.
3. Read `.github/scripts/test/test-tag-filter.sh` as the convention template (PASS/FAIL counters, `LC_ALL=C`, `grep -F` YAML-token checks, synthetic corpus).
4. Expect the PreToolUse security hook to advisory-block the first `.github/workflows/*.yml` Edit — retry the identical edit ([learning](../learnings/2026-02-21-github-actions-workflow-security-patterns.md)).

### Phase 1 — Guard script `.github/scripts/inngest-bootstrap-tag-guard.sh` [create]
Single subcommand; `set -euo pipefail` + `export LC_ALL=C` re-established at top (invoked via `bash script.sh`, not sourced).
- `resolve-tag <event_name> <github_ref> <inputs_ref>`:
  - discriminate on `event_name == workflow_dispatch` (NOT on `inputs_ref` emptiness — Kieran P1-b/SpecFlow P1-4);
  - `src` = `inputs_ref` (dispatch) or `github_ref` (push); `tag="${src#refs/tags/}"; tag="${tag#vinngest-}"`;
  - **the post-strip regex is the reject gate** (not the strip): `[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1`; then `[[ -n "$tag" ]] || exit 1` (set-empty isn't caught by nounset); `printf '%s\n' "$tag"`.
  - Relies on the inline validate (dispatch) + the `vinngest-v*.*.*` push glob for the `vinngest-` prefix; the regex re-validates defensively.

### Phase 2 — Fixture test `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` [create]
Auto-discovered (`test-*.sh`). Mirrors `test-tag-filter.sh`. RED before Phase 3, GREEN after. See **Test Scenarios**. Reads `cloud-init-inngest-bootstrap.test.sh` for the parity check (coupling — see Files note).

### Phase 3 — Workflow edit `.github/workflows/build-inngest-bootstrap-image.yml` [edit]
1. `workflow_dispatch.inputs`: replace `tag` with `ref` (desc: "Existing vinngest-vX.Y.Z tag to (re)publish").
2. New **Step 1** (dispatch-only, pre-checkout) "Validate dispatch ref": `if: github.event_name == 'workflow_dispatch'`; `env: REF: ${{ inputs.ref }}`; inline `[[ "$REF" =~ ^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1`. **This inline regex is the canonical full-ref validator** — it must run from the trusted (workflow-file) tree before checkout reaches an untrusted ref's tree. Comment: dispatch requires repo write access (collaborator threat model); a wider grant would make this the sole gate.
3. **Checkout**: `with: { ref: ${{ inputs.ref }} }` (empty on push → triggering tag). Comment: the requested/triggering tag is created locally via `actions/checkout`'s `+refs/tags/X:refs/tags/X` refspec — no `fetch-tags`/`fetch-depth:0` needed.
4. **Resolve image tag** step: `TAG=$(bash .github/scripts/inngest-bootstrap-tag-guard.sh resolve-tag "$GH_EVENT" "$GITHUB_REF" "$INPUTS_REF")` (env-indirected) → `GITHUB_OUTPUT`.
5. Existing pins / GHCR login / build+verify+push: unchanged.
6. `permissions:` unchanged (`contents: read` + `packages: write`). **No post-push assert step.**

## Files to Edit
- `.github/workflows/build-inngest-bootstrap-image.yml` — `inputs.tag`→`ref`; add pre-checkout inline validate; checkout `ref` (no `fetch-tags`, refspec comment); resolve via guard script; permissions unchanged.

## Files to Create
- `.github/scripts/inngest-bootstrap-tag-guard.sh` — `resolve-tag` only.
- `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` — fixtures (auto-discovered).

**Files read by tests (coupling, not edited):** `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — the parity check reads its stripped regex; if that line moves the fixture's parity assertion must follow (Kieran P2-a).

## Acceptance Criteria

### Pre-merge (PR / CI)
- AC1: `bash .github/scripts/test/run-all.sh` passes (auto-includes the new fixture).
- AC2: `bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh` exits 0; all Test Scenarios assert as specified.
- AC3: `grep -nE 'permissions:|contents:|packages:' .github/workflows/build-inngest-bootstrap-image.yml` shows `contents: read` (NOT `write`) and `packages: write` — unchanged.
- AC4: `workflow_dispatch.inputs` contains `ref` and NOT `tag`; a Group-1 shape gate asserts the workflow contains the canonical inline validate literal `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` (grep -F).
- AC5: The guard's `resolve-tag` **post-strip** regex (`^v[0-9]+\.[0-9]+\.[0-9]+$`) equals the consumer's regex at `cloud-init-inngest-bootstrap.test.sh:~187` — asserted by the fixture replicating the consumer's strip-then-match (Kieran P1-a). (Names the stripped regex, NOT the prefixed inline one.)
- AC6: `actionlint .github/workflows/build-inngest-bootstrap-image.yml` clean (local preflight — actionlint is available locally; it is NOT a CI gate, so the Group-1 fixture shape gates are the CI-enforced check). Use `actionlint` for the YAML, NOT `bash -n` on the `.yml`; `bash -n` the guard + test scripts.
- AC7: Existing `cloud-init-inngest-bootstrap.test.sh` AC6 still passes (consumer guard unchanged).

### Post-merge (operator — run via gh, not a dashboard)
- AC8: After merge, `gh workflow run build-inngest-bootstrap-image.yml -f ref=vinngest-v1.1.11` (tag confirmed on remote) → run is **green** and re-publishes `:v1.1.11`. (Cannot run pre-merge — dispatch resolves on the default branch only.)
- AC9: `gh workflow run build-inngest-bootstrap-image.yml -f ref=main` → run **fails at the validate step before any publish**.
- PR body uses `Ref #4692` (not `Closes`) until AC8/AC9 confirm post-merge; then `gh issue close 4692`.

## Test Scenarios (fixture test)

**Group 1 — YAML-shape gates on the workflow** (`grep -F`):
- `contents: read` present; `contents: write` absent.
- `workflow_dispatch` input is `ref`, not `tag`.
- inline validate literal `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` present.
- resolve step invokes `inngest-bootstrap-tag-guard.sh resolve-tag`.

**Group 2 — `resolve-tag` behavior** (synthetic env):
- (`workflow_dispatch`, ``, `vinngest-v1.1.11`) → `v1.1.11`.
- (`push`, `refs/tags/vinngest-v1.1.11`, ``) → `v1.1.11`.
- (`workflow_dispatch`, ``, ``) → exit 1 (dispatch-empty must fail, not fall through — P1-4).
- (`push`, `refs/tags/web-v0.1.0`, ``) → exit 1 (non-vinngest).
- (`push`, `refs/tags/vinngest-v1.1.11-rc1`, ``) → exit 1 (the `vinngest-v*.*.*` glob DOES fire for `-rc1`; resolve must reject — Kieran P1-c).
- (`push`, `refs/heads/main`, ``) → exit 1 (malformed/branch ref — Kieran P1-b).
- (`workflow_dispatch`, ``, `vinngest-vinngest-v1.2.3`) → exit 1 (double-prefix).

**Parity check:** the `resolve-tag` post-strip regex literal equals the consumer's `cloud-init-inngest-bootstrap.test.sh` line-~187 regex (read both; assert equal — Kieran P1-a / AC5).

## Alternative Approaches Considered
| Approach | Why not |
|---|---|
| **1 — auto-tag on dispatch** | Requires `contents: write` (tag-forging primitive; security-sentinel flag). Skip-on-exists idempotency still permits a version-without-tag publish → weaker than a precondition. |
| **2 — drop the dispatch path** | Deletes the legitimate CVE-rebuild path (recoverable only via `git tag -f && git push -f`). |
| **Post-push tag assertion (tripwire)** | Cut at plan-review: tautological on both real paths (checkout-of-tag ⇒ points at HEAD), fires after `docker push`, derivation coverage redundant with the resolve-tag unit test, divergence detection redundant with consumer AC6. |
| **Inline (no extracted guard)** | `workflow_dispatch` isn't live-triggerable on a feature branch, so extracting `resolve-tag` is the only pre-merge unit-test path at this threshold. |

## Non-Goals
- NG1: Changing the AC6 consumer drift-guard (PR #4676 — correct backstop).
- NG2: GHCR image-tag immutability/retention (re-publish over an existing `:vX.Y.Z` is the intended CVE-rebuild escape hatch).
- NG3: **Content-freshness of non-max tags (SpecFlow P0-2).** AC6 only watches the semver-max tag, so a non-max re-publish has "tag exists" true but content-divergence unverified. Out of scope (prod pins the semver-max tag, so a non-max re-publish doesn't change what prod runs); closing it needs a digest check. **File a deferred tracking issue**, re-eval criterion: "if cloud-init ever pins a non-max `vinngest-v*` tag, add a published-digest check."
- NG4: Auto-tag creation / `contents: write`.
- NG5: Standalone ADR (rationale lives in brainstorm + this plan; dropped at plan-review).

## Risks & Mitigations
- **Prevention-only invariant:** there is no producer-side tripwire — the guarantee is FR-style: dispatch input is regex-validated as an existing `vinngest-v*` tag (inline, pre-checkout, from the trusted tree) and checkout-of-that-tag makes a tagless publish structurally impossible. Divergence *detection* is delegated to the unchanged consumer AC6 guard (no redundant second copy). A future non-tag-anchored trigger would need its own guard (out of scope).
- **Untrusted-ref script execution:** the inline validate runs pre-checkout from the workflow-file tree, so the guard script is only ever executed from an already-validated release-tag tree. Dispatch also requires repo write access (collaborator threat model) — noted in the validate-step comment.
- **Precedent diff:** the guard mirrors the `.github/scripts/check-*.sh` + `test/test-*.sh` precedent (`test-tag-filter.sh`, same `vinngest-v*` track). No novel pattern.

## Sharp Edges
- `## User-Brand Impact` is filled (threshold `single-user incident`) — won't fail deepen-plan Phase 4.6.
- The PreToolUse security hook advisory-blocks the **first** `.github/workflows/*.yml` Edit even for safe structured `inputs.*` changes — retry the identical edit once.
- `resolve-tag` must keep `[[ -n "$tag" ]]` after the regex — `set -u` catches *unset*, not *set-empty*.
- Keep `resolve-tag`'s post-strip regex byte-identical to the consumer's `cloud-init-inngest-bootstrap.test.sh` regex; the parity fixture asserts this so they can't silently drift.
