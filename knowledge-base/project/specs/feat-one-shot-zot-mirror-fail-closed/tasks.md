---
feature: feat-one-shot-zot-mirror-fail-closed
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-29-fix-zot-mirror-fail-closed-and-bridge-false-gate-plan.md
pr: 7071
---

# Tasks — zot mirror fail-closed + stop asserting a dead GHCR fallback

Derived from plan **v2** (post 7-reviewer consolidation). Phase order is dependency-directed:
contract changes land before their consumers. Read the plan's Premise Validation first — two of the
three original Deliverable-B premises were falsified, and one "Confirmed" premise (P0-A) was retracted.

**Scope decisions — all three RESOLVED 2026-07-30** (see `decision-challenges.md` for reasoning):
**UC-1** keep the bridge `/v2/` probe **cut** (already excluded below; the `nc -z` false gate folds
into the 8.2 tracker). **UC-2** **full scope** — 5.1 through 5.4 including the release-preflight arm.
**UC-3** **single PR** — so 6.1's runbook correction ships alongside Phase 3's gate, satisfying the
ordering constraint by construction.

## Phase 0 — Preconditions (no writes)

- [ ] 0.1 Confirm the mirror harness matches on step **name** and asserts on `mirror_status` values:
      `grep -n 'extract_run_block' plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`
- [ ] 0.2 Record the two expected-rc literals to change: `"0 degraded warn 3"` (T1) and
      `"0 degraded warn 0"` (T4).
- [ ] 0.3 Re-run and paste into the PR: GHCR is dead (`401` on `api.github.com/user`, `403 DENIED`
      minting a pull token) and the bridge is healthy (`cloudflared access tcp` → `GET /v2/` → `401`
      from zot).
- [ ] 0.4 Confirm `${DIGEST}` is addressable in zot post-copy — the adjacent
      `cosign sign --yes "${ZOT}@${DIGEST}"` already proves it; note the anchor.
- [ ] 0.5 Measure baselines the ACs depend on:
      `grep -aFc 'tail -c 400 "$perr"' apps/web-platform/infra/ci-deploy.sh` → **6**;
      `grep -cF 'needs.release.result' .github/workflows/web-platform-release.yml` → **0**.

## Phase 1 — FR-C1: stop discarding the zot-pull stderr

- [ ] 1.1 RED: extend `apps/web-platform/infra/ci-deploy.test.sh` to assert the zot-arm log line
      carries the pull reason.
- [ ] 1.2 GREEN: at the `IMAGE_PULL: zot pull failed for` line, append a newline-collapsed
      `tail -c 400 "$perr"` (anchor on content, not the line number).
- [ ] 1.3 Verify AC12: `grep -aFc 'tail -c 400 "$perr"' … ` == 7. **`-F` is mandatory** — without it
      the pattern returns 0 against code containing it 6× (mid-pattern `$` is an ERE anchor).

## Phase 2 — Contract changes inside the extracted `run:` block

- [ ] 2.1 FR-A3: `degraded()` also emits
      `mirror_reason=<bridge|crane_install|copy_v|copy_sha|copy_latest|sign|verify>` — one label per
      call site (≥6 sites).
- [ ] 2.2 FR-A4: rewrite the three operator messages (bridge / copy+verify / sign). Each names a
      cause, a remedy, the "unpublished draft — re-running is safe" line, and
      `apply-deploy-pipeline-fix.yml` as the pipeline-bypass hatch. **The copy-arm message must not
      blame Sigstore** — that was v1's defect.
- [ ] 2.3 FR-B1(1): delete every false claim in the mirror step — the header
      ("must NEVER red a successful release"), `::warning::` "release UNAFFECTED (GHCR
      primary/break-glass)", the step summary "release OK (GHCR primary)", "the host's atomic GHCR
      fallback covers it cleanly", "latency, not availability", the `:713-716` Slack claim, and
      `:782`'s refuted #6416 route prediction + GHCR-fallback reassurance.
- [ ] 2.4 FR-B2: dump `/tmp/cloudflared-registry.log` at the failing bridge step (today only the
      `nc -z` timeout path does).

## Phase 3 — FR-A1 + FR-A2: make it blocking, and assert positively

- [ ] 3.1 Delete `continue-on-error: true` from `zot_mirror`.
- [ ] 3.2 Change `degraded()`'s `exit 0` → `exit 1`.
- [ ] 3.3 Immediately **before** `echo "mirror_status=ok"`, assert
      `crane digest "${ZOT}:v${VERSION}"` resolves **and equals `${DIGEST}`**; else
      `degraded "verify" "<detail>"`. **One crane call — no GHCR-side read** (see plan Alternatives).
- [ ] 3.4 FR-A7: one comment block with four clauses — GHCR coupling (cite ADR-088 arm-b's structural
      denial), CF-Access coupling (name the drift detector), the load-bearing sub-value
      (publish-ordering / version-space integrity), and outcome-vs-conclusion discipline.
- [ ] 3.5 FR-A8: in the same comment, state what the gate does **not** prove — it asserts the manifest
      is readable by the **push** credential over the tunnel, not that the host can pull
      (`ZOT_PULL_*`, private NIC); name `web-zot-consumer-probe.sh` as the complement.
- [ ] 3.6 Update the harness's two expected-rc literals (0.2). Run it — must pass.

## Phase 4 — FR-A5/A6/A9/A10: make the gate actually reach the deploy

- [ ] 4.1 **FR-A5 (the load-bearing fix):** add `needs.release.result == 'success'` to **both**
      `migrate` and `deploy` in `.github/workflows/web-platform-release.yml`. Their `if:` leads with
      `always() &&`, which discards skip-on-failed-`needs`, and `deploy` gates only on the
      `docker_pushed` output — set ten steps before the assertion. Without this the gate may protect
      nothing and can leave prod on new schema + old code.
- [ ] 4.2 FR-A6: `if: failure()` + `./.github/actions/notify-ops-email` on the **release** job and the
      **deploy** job. Body carries `mirror_reason` + the one-sentence remedy, never a checklist.
      Disclose in the PR that this also emails ops for plugin releases via
      `version-bump-and-release.yml` (shared reusable workflow, two consumers).
- [ ] 4.3 FR-A9: add `mirror_verified` to the `release` job `outputs:`; `deploy` echoes it to
      `$GITHUB_STEP_SUMMARY` and `::warning::`s when not `true`. **Not** a blocking conjunct.
- [ ] 4.4 FR-A10: dispatch-only, reason-required override — new input on
      `web-platform-release.yml`, forwarded via `with:`, plus a **defaulted** `workflow_call` input so
      `version-bump-and-release.yml` is unaffected. Gate on
      `github.event_name == 'workflow_dispatch'`. Document that it also bypasses `await-ci` and needs
      the **same `bump_type`** to self-heal. **Do not** reintroduce an `environment:` reviewer clause —
      `jobs.release` has no `environment:`.

## Phase 5 — FR-B3 + FR-B4: detector coverage and wiring

- [ ] 5.1 FR-B3: add an Access-service-token arm to `scripts/check-cloudflare-token-drift.sh` —
      enumerate `[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)` from Doppler (never a hardcoded list) and verify
      by presenting `CF-Access-Client-Id`/`-Secret` to the protected hostname: **200 → LIVE,
      403 → DEAD**. Today's regex `CF_API_TOKEN[A-Z0-9_]*` cannot match the key its own header cites.
- [ ] 5.2 Unit test both verdicts with synthesized fixtures (`cq-test-fixtures-synthesized-only`).
- [ ] 5.3 FR-B4: invoke the detector as a **step in `.github/workflows/scheduled-terraform-drift.yml`**
      (already twice-daily, already `DOPPLER_CONFIG: prd_terraform`, already has `notify-ops-email`).
      No new workflow — a new GHA `schedule:` is off-pattern per ADR-033.
- [ ] 5.4 Add the required release-preflight arm (see UC-2 if descoping).

## Phase 6 — Truthfulness sweep + ADR/C4

- [ ] 6.1 FR-B1(2): correct `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` —
      the "fallback registry is always warm and current" claim (**note: it wraps across lines**, so use
      `tr '\n' ' '` to check), and add the post-change recovery. Fold in the `tcp://` probe trap as a
      section here — **not** a new file. **This must not land in a later PR than Phase 3.**
- [ ] 6.2 FR-B1(3): correct ADR-096's own dead escape hatches — §Cold-boot-dependency axis 1
      ("latency, not availability") and the "Instant revert" bullet.
- [ ] 6.3 FR-B1(4): dated clause on the AP-016 row in
      `knowledge-base/engineering/architecture/principles-register.md` (the interim PAT exception has
      lapsed).
- [ ] 6.4 FR-B1(5): dated note on ADR-088's "interim GHCR break-glass" phrasing.
- [ ] 6.5 ADR-096 amendment, clauses (a)–(h) per the plan. No new ordinal.
- [ ] 6.6 Three `model.c4` description corrections (`ghcr`, `hetzner -> ghcr`,
      `tunnel -> zotRegistry`). Then run `apps/web-platform/test/c4-code-syntax.test.ts` and
      `c4-render.test.ts`.

## Phase 7 — Exit gate

- [ ] 7.1 `bash plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`
- [ ] 7.2 `bash apps/web-platform/infra/ci-deploy.test.sh`
- [ ] 7.3 `actionlint` on `reusable-release.yml` **and** `web-platform-release.yml`; `bash -c` on
      extracted `run:` snippets (never `bash -n` on the YAML).
- [ ] 7.4 Walk AC1–AC18. Every AC is presence-first with `-F` and a missing-anchor guard — do not
      accept an absence-only result as a pass.

## Phase 8 — Trackers (`wg-when-deferring-a-capability-create-a`)

- [ ] 8.1 The inngest image's mirror stays non-blocking; `cloud-init-inngest.yml` hard-pins GHCR with
      no zot path; `build-inngest-bootstrap-image.yml` still carries the live #6416 defect.
- [ ] 8.2 Two more false `/v2/` gates: `zot-entry-gate.sh:40` and `cloud-init.yml:527` use
      `curl -s -o /dev/null` with no `-w '%{http_code}'`, so a 500 or empty 200 passes.
- [ ] 8.3 `zot-entry-gate.sh` is unwired and asserts a stale contract.
- [ ] 8.4 AC-P1: first-release verification, as a follow-through (not an AC bullet).
- [ ] 8.5 The orphan-draft / stale-release-notes leak (FR-A11).
