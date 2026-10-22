---
title: "fix: inngest config-refresh verify-blob rejects the promoted bundle — SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature"
date: 2026-10-22
slug: inngest-config-refresh-verify-blob-reject
branch: feat-one-shot-10390-verify-blob-reject
issue: 10390
type: fix
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: inngest config-refresh verify-blob rejects the promoted bundle (epic #10390, defect 3)

## Enhancement Summary

**Deepened on:** 2026-10-22 (same session as authoring — plan + deepen ran in one headless pass)

### Key Improvements
1. Named the mechanism gate precisely: cosign v3.1.1 `verify-blob` admits `--trusted-root` only when
   `checkNewBundle(bundlePath)` = `sgbundle.LoadJSONFromPath` succeeds (`verify_blob.go:117,172`;
   `verify_bundle.go:41`) — a load failure reads as the same honest reject as a crypto failure.
2. Verified all three prior suspects dead by live measurement (Sigstore live-root deep-diff, Rekor
   entry SAN + logID decode, offline `--network none` `Verified OK` reproduction).
3. Added the mandatory sections the gates require: Downtime & Cutover (singleton-replace), Guard
   Contract (weakening-flag ban), Network-Outage Deep-Dive, mechanical Scope Check.

### New Considerations Discovered
- `reason=signature` is a classification-overloaded row — the `detail=` fix is the actual
  diagnosability deliverable regardless of which root cause Phase 0 names.
- The distroless cosign image runs UID 65532 — mount-perm arithmetic checked (0755/0644 benign).

## Overview

The dedicated Inngest host's ADR-135 config-refresh timer emits
`SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature offered=4e17987c…` on every ~5-minute tick for the
promoted v3 bundle digest `4e17987c200a355a4c9e51d95d621e9fe1ff0febbb390d3e6d40f825d726d0c1`
(earlier, the same row fired for v2). The channel is alive end-to-end — pointer resolved, bundle
pulled from zot, cosign verifier image staged — and the `verify-blob` step itself returns non-zero.
Because the invocation swallows stderr (`cloud-init-inngest.yml` ~line 2079:
`docker run … verify-blob … >/dev/null 2>&1`), every distinct failure class collapses into one
`reason=signature` row.

Planning-time evidence (gathered live, 2026-10-22): the offline verify machinery **provably works**
— a v0.3 bundle reconstructed from the real Rekor entry's material verifies `Verified OK` under the
exact host invocation (`--network none`, pinned cosign v3.1.1, baked trusted root, pinned identity
regexp). All three suspects named by the prior session (tlog/Rekor fetch under `--network none`,
stale trusted root, identity-regexp/SAN mismatch) are refuted by measurement. The remaining
divergence is inside the real `.sigstore.json` produced by `build-inngest-config-bundle.yml`, or a
host-side failure the coarse `reason=signature` mapping hides.

The plan is diagnosis-first: Phase 0 is a `workflow_dispatch` repro job that pulls the real bundle
with `packages: read` and runs the exact host verify with stderr visible; the measured stderr
selects the fix branch. Independent of root cause, two invariants ship in this PR: (a) the verify
stderr is captured and classified into a bounded `detail=` token on the `VERIFY_FAIL` row so the
next honest reject is self-diagnosing, and (b) the fix ships to the host through the sanctioned
immutable-redeploy path (`inngest-host-replace`), not SSH.

## Research Reconciliation — Spec vs Codebase

| Spec/brief claim | Codebase reality (verified 2026-10-22) | Plan response |
|---|---|---|
| "honest cosign verify-blob reject; docker run reaches the verifier image and the verify step fails" | Confirmed compatible: `reason=signature` is emitted at `verify_fail signature` (~line 2080) on ANY non-zero rc of the `docker run`, including flag-parse errors, docker daemon errors, and `timeout` rc=124 — not only cryptographic rejects | Repro phase captures the real stderr before committing to a fix |
| "NOT the defect-2 pull failure; no member=cosign-image failures" | Confirmed: `member=cosign-image` pull staging exists (~line 2040) and run 39817179495's mirror equality-checked the zot cosign digest | No change to the pull path |
| Three suspects: tlog/Rekor fetch, stale trusted root, identity-regexp/SAN mismatch | All three REFUTED by live measurement (see Research Insights) | Remaining hypotheses enumerated in ## Hypotheses |
| "floor 5→6 pin bump" after fix | Confirmed: `cloud-init-inngest.yml` ~line 1157 comment "The floor stays 5 ON PURPOSE… Bump the floor (here and in inngest-host.test.sh) in the SAME change"; runbook step ties the bump to first promotion | Phase 4 pairs the bump with the next promotion |

## Research Insights

### Premise Validation (Phase 0.6)

All cited references verified: issue #10390 OPEN (epic); #9927, #8620, #7596, #10713, #10751 OPEN
(context only). All 12 cited files exist on `origin/main` (cloud-init-inngest.yml,
cosign-trusted-root.json, inngest-config-bundle-pack.sh, all four named test suites,
build-inngest-config-bundle.yml, ADR-135, the runbook, the defect-2 plan). `INNGEST_CONFIG_DIGEST`
in Doppler `soleur-inngest/prd` reads `4e17987c…` — the promoted-v3 claim confirmed. ADR corpus
checked for the proposed mechanism: ADR-087 (cosign deploy-verify topology), ADR-135 (+ 3
amendments/addenda incl. the defect-2 zot-stage record), ADR-096 (zot-only host pull), ADR-128
(digest-pin coherence) all read; no rejected-alternative collision.

### Property List (0.6b)

- The `reason=signature` VERIFY_FAIL row stops recurring for the promoted digest (the real defect).
- The next honest verify-blob reject is self-diagnosing from the off-box row alone — no SSH, no
  second incident to learn the stderr.
- The fix preserves every signed-bundle invariant in ADR-135 (HARD-1…HARD-12): fail-closed arms,
  offline verify, baked trusted root, monotonic VERSION, set-atomic apply.
- The host change ships through Terraform/cloud-init immutable re-provision only.

### Cut List (0.6b)

- *Operator-minted GHCR read credential for diagnosis* → property "pull the private bundle" → a
  `packages: read` `GITHUB_TOKEN` in a dispatch job already covers it (and `hr-github-app-auth-not-pat`
  forbids new PATs).
- *A second verifier image / cosign version bump* → cut unless Phase 0 measures a need; the pin is
  proven functional by this session's local reproduction.

### Live evidence gathered this session (the load-bearing part)

1. **Local reproduction PASSES.** Manifest regenerated byte-identically (`inngest-config-bundle-pack.sh`
   is deterministic; the regenerated `VERSION=3` manifest's sha256 `b3e718b9…` was found in Rekor's
   public index — proving byte-identical reproduction of the SIGNED blob). A v0.3 sigstore bundle
   hand-assembled from the real Rekor entry's material (leaf cert, signature, inclusion proof, SET,
   canonicalizedBody) verified **`Verified OK`** under the verbatim host invocation:
   `docker run --rm --network none -v bundle:/bundle:ro -v cosign-trusted-root.json:/etc/cosign/trusted_root.json:ro cosign@sha256:57c0e93a… verify-blob --trusted-root … --bundle /bundle/manifest.txt.sigstore.json --certificate-identity-regexp '…build-inngest-config-bundle\.yml@refs/heads/main$' --certificate-oidc-issuer https://token.actions.githubusercontent.com /bundle/manifest.txt`.
2. **Suspect (a) refuted:** `verify-blob --bundle` needs zero egress; the bundle's inclusion proof
   verifies offline against the trusted root's Rekor key (`--network none` run above).
3. **Suspect (b) refuted:** the baked `cosign-trusted-root.json` (capture 2026-07-04) is
   byte-equivalent in key material to today's live `sigstore/root-signing` `trusted_root.json` —
   identical tlog keyIds, CA certs, TSA certs, ctlog keyIds (deep diff run, zero live-only entries).
   The entry's Rekor logID `c0d23d6a…` matches the baked `rekor.sigstore.dev` tlog key exactly.
4. **Suspect (c) refuted:** the real Fulcio cert (decoded from the actual Rekor entry
   `108e9186…`, signed 2026-10-22 16:52:46Z by run 39817179495) carries SAN
   `URI:https://github.com/jikig-ai/soleur/.github/workflows/build-inngest-config-bundle.yml@refs/heads/main`
   — byte-equal to the pinned regexp; issuer `O=sigstore.dev, CN=sigstore-intermediate` chains to
   the baked root; the OIDC-issuer extension matched the flag.
5. **New mechanism-level finding:** cosign v3.1.1 `verify-blob` gates `--trusted-root` on
   `checkNewBundle(bundlePath)` = `sgbundle.LoadJSONFromPath(path) == nil`
   (`cmd/cosign/cli/verify/verify_bundle.go:41`, `verify_blob.go:117,172`). A bundle file that fails
   to LOAD (unparseable, v0.3-validation violation e.g. `x509CertificateChain`, missing inclusion
   proof, or simply **unreadable/nonexistent at the mount path**) drops into the old-format path and
   exits `Error: --trusted-root only supported with --new-bundle-format` → rc=1 → `reason=signature`.
   This is an "honest verify-blob reject" that has nothing to do with cryptography — and this
   session reproduced that exact error shape locally.
6. **Refuted sub-hypotheses:** `REFRESH_*` env overrides are unset by the `--fixture-seams` gate in
   production (cloud-init ~1818); mounted-file permissions (`mktemp -d` 0700 parent, `mkdir -p
   bundle` 0755, extracted files 0644, trusted root 0644) read fine inside the UID-65532 distroless
   image (verified: image `Config.User="65532"`); v3 bundle was built on `main` (run 39817179495)
   so the `@refs/heads/main` SAN form is right; zot-mirrored cosign digest equality-checked in the
   producer run.
7. **Unreachable from this seat:** the real `.sigstore.json` bytes (GHCR private, no `read:packages`
   locally; zot behind Cloudflare Access; `10.0.1.30` private net). A `packages: read` dispatch job
   is the only no-SSH path — hence Phase 0.
8. Repo conventions loaded: `hr-prod-host-config-change-immutable-redeploy` (host changes ship via
   cloud-init + `apply-web-platform-infra.yml -f apply_target=inngest-host-replace`); the drift
   executor's `_summ_row` parses only the keys
   `(version|sha256|reason|verify|rejver|offered|count|member)` — an additive `detail=` field is
   compatible but must be added to that grep set to surface in summaries; `inngest-redact.sh`
   masks non-allowlisted text, so `detail=` stays a bounded alnum-dash token.

## Hypotheses

Ranked, each with the evidence for/against and the Phase-0 discriminator:

| # | Hypothesis | For | Against | Discriminator |
|---|---|---|---|---|
| H1 | The real `.sigstore.json` fails `LoadJSONFromPath` → `checkNewBundle`=false → `--trusted-root only supported with --new-bundle-format` | Reproduced this exact error shape locally with a malformed bundle; deterministic rc=1; matches "honest reject, verify runs" | A v3.1.1 `sign-blob` output should round-trip its own loader | cosign stderr in repro log + `jq` on the real bundle JSON (mediaType, tlogEntries, inclusionProof, x509CertificateChain) |
| H2 | Bundle loads but `VerifyNewBundle` fails on a check my reconstruction didn't exercise (extra `timestampVerificationData` path, multi-entry tlog edge) | `SignData` consults the SigningConfig; sigstore public-good may include TSA URLs by default | My reconstruction covered cert+sig+tlog+identity end-to-end | same stderr |
| H3 | Non-cosign rc≠0 misclassified: docker daemon error, mount failure, `timeout` rc=124, `docker run` exit shape | `>/dev/null 2>&1` maps EVERY nonzero to `signature` | Staging/mount perms verified benign | repro runs the same `docker run` shape incl. a 0700-modeled stage dir + a `--network host` A/B |
| H4 | Host-rendered `/etc/soleur/cosign-trusted-root.json` diverges from the repo file (templatefile render drift) | Cheap to check | `file()` + `indent(6,…)` is whitespace-only and JSON is whitespace-tolerant | repro verifies the repo file; host file drift only checkable via next replace boot log — covered by keeping H3's stderr capture |

## Implementation Phases

### Phase 0 — no-SSH diagnostic reproduction (dispatch workflow)

Create `.github/workflows/diagnose-inngest-verify.yml` (`workflow_dispatch` only,
`permissions: contents: read, packages: read`, no environment gate — it mutates nothing).
Per CTO ruling it carries its own `concurrency` group (never shares
`scheduled-vinngest-digest-freshness`), an explanatory header modeled on
`web-host-escrow-diagnose.yml`, and a paired shape test mirroring
`plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh`:

1. `docker/login-action` to `ghcr.io` with `${{ github.actor }}`/`${{ github.token }}` (the
   vinngest-digest-freshness precedent), `docker pull ghcr.io/jikig-ai/soleur-inngest-config@sha256:4e17987c…`,
   `docker create` + `docker cp` the `/bundle.tar.gz`, extract to a staging dir, and print
   `tar -tzf` + `jq` of `manifest.txt.sigstore.json` (mediaType, `verificationMaterial` content
   type, `tlogEntries | length`, presence/absence of `inclusionProof`, `inclusionPromise`,
   `timestampVerificationData`, `x509CertificateChain`, `certificate`) and the manifest hash.
2. Run the EXACT host verify invocation with stderr VISIBLE (pinned cosign digest, `--network
   none`, baked `apps/web-platform/infra/cosign-trusted-root.json`, pinned regexp + issuer).
3. Discriminators in the same job: (a) re-run with the staging dir `chmod 0700` (models host
   `mktemp -d` perms under the UID-65532 image); (b) `--network host` A/B to isolate the network
   dimension; (c) `sha256sum` of the repo trusted root vs a re-captured one.
4. Record the measured stderr verbatim into `$GITHUB_STEP_SUMMARY` and the plan's decision log.

The job is a **deliverable** (kept, not deleted after): it is the sanctioned no-SSH probe for any
future `reason=signature` row, so it takes `digest` as a workflow input defaulting to
`4e17987c200a355a4c9e51d95d621e9fe1ff0febbb390d3e6d40f825d726d0c1`.

### Phase 1 — root-cause fix (branch on Phase-0 stderr)

- **If the stderr is a `LoadJSONFromPath`/`--new-bundle-format` gate error:** the bundle is
  unloadable-for-the-loader — fix is producer-side (regenerate/republish a conforming bundle via a
  new `build-inngest-config-bundle.yml` dispatch at version N+1 and promote it) or path/perms-side
  per the `jq` evidence. If the file itself is structurally fine and only the host copy is mangled,
  the fix is host-side (see below).
- **If the stderr names a `VerifyNewBundle` check** (tlog inclusion, cert chain, identity,
  timestamp): fix the specific gate — e.g., trusted-root re-capture + provenance-sidecar update per
  the rotation recipe, or a verify-flag correction. Never resolve a tlog/cert failure by adding
  `--insecure-ignore-tlog`/`--insecure-ignore-sct` or `--key` — a verification-weakening flag is a
  security posture change and is out of scope without an ADR-135 amendment.
- **If the stderr is a docker/mount/timeout shape:** fix the invocation in
  `inngest-config-refresh.sh` (e.g., stage-dir modes, mount flags, stderr-visible logging) inside
  `cloud-init-inngest.yml`.
- **If the repro prints `Verified OK`:** the bundle+flags are innocent and the divergence is
  host-state — the fix is the Phase-2 stderr capture shipped via replace, which turns the next
  failing tick's stderr into an off-box row; Phase 4's post-replace watch then reads it.

### Phase 2 — verify stderr capture + `detail=` classification (lands under every branch)

In `inngest-config-refresh.sh` (the templatefile-embedded script in `cloud-init-inngest.yml`):

1. Replace `>/dev/null 2>&1` on the verify `docker run` with stdout kept discarded but stderr
   captured to `$STATE_DIR/verify.stderr` (bounded: `head -c 4096`, mode 0600). Capture must wrap
   the `timeout` invocation — not live inside it — so an rc=124 kill still lands the partial
   stderr for the `timeout` classifier arm.
2. Classify the stderr into a bounded `detail=` token emitted on the `VERIFY_FAIL` row:
   `flag-newbundle` (`only supported with --new-bundle-format`), `tlog` (`log inclusion|tlog|
   rekor`), `identity` (`identity|SAN|issuer`), `chain` (`certificate chain|x509`), `timeout`
   (rc=124), `docker` (`Error response from daemon`), `other`. Token is `[a-z-]{1,24}` so it
   survives `inngest-redact.sh` and the phone-home path.
3. `verify_fail signature` gains the `detail` arg; row shape stays
   `reason=signature offered=<12hex> rejver=<v> detail=<token>` — additive, so the existing
   `reason`/`offered`/`rejver` keys parse unchanged.
4. Add `detail` to the `_summ_row` field regex in `.github/workflows/inngest-config-drift.yml` so
   summaries surface it.

### Phase 3 — tests (TDD; failing rows land BEFORE the fix rows)

In `apps/web-platform/infra/inngest-config-refresh.test.sh`:

- S-row: the verify invocation no longer ends `>/dev/null 2>&1` and captures stderr to a state-dir
  file (grep the script text for the capture pattern + `verify.stderr`).
- S-row: `verify_fail signature` call sites pass a `detail=` token; the classifier's token
  vocabulary is a fixed allowlist (grep the case arms).
- F-row: stub the docker mock so `docker run` emits a fixture stderr string and rc=1; assert the
  emitted row carries `reason=signature` AND the classified `detail=` (three fixtures:
  `flag-newbundle`, `tlog`, `docker`).
- F-row: the bounded `verify.stderr` file is written and capped (`wc -c` ≤ 4097).
- `.github/workflows/inngest-config-drift.yml` row: `detail=` appears in `_summ_row` output for a
  fixture row (grep the regex arm list).
- Producer-side fixes (only if Phase 0 selects one) get their own failing row first in
  `inngest-config-bundle-pack.test.sh` or `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`.
- Floor-bump row lands with Phase 4: `inngest-host.test.sh` floor assertion 5→6 in the same change
  (per the in-file note at ~line 1157).

### Phase 4 — ship path (immutable redeploy) + promotion/floor

1. Merge with all gates green, then host replace:
   `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason="inngest-config-refresh verify-blob stderr capture + fix (#10390 defect 3)"`.
   Preconditions per `hr-prod-host-config-change-immutable-redeploy` and the replace runbook:
   Redis AOF volume re-attach + maintenance window — same shape as run 39818534701.
2. If Phase 1's fix is producer-side, dispatch `build-inngest-config-bundle.yml` at `version=N+1`
   and promote the new digest (Terraform `doppler_secret` write); bump the baked floor 5→6 in the
   SAME change (`cloud-init-inngest.yml` floor note + `inngest-host.test.sh`), per the runbook's
   pairing rule.
3. Post-replace watch (off-box only): `SOLEUR_INFRA_PULL_VERIFY_FAIL` stops for the promoted
   digest; the comparator reads APPLIED/NOOP; no `member=` failures.

### Phase 5 — ADR addendum + PIR + follow-through

- ADR-135 addendum (mirroring the defect-2 addendum): record defect 3's measured root cause and the
  fix, including the `reason=signature` classification-overload lesson.
- Post-incident report under `knowledge-base/engineering/operations/post-mortems/` (constitution:
  incident detected → PIR always — a dead refresh channel on the sole scheduler since v2 promotion
  is a production incident); `## Follow-ups` filed as issues.
- Follow-through enrollment: soak AC below gets `scripts/followthroughs/inngest-verify-clean-10390.sh`
  (exit 0 when no `reason=signature` VERIFY_FAIL row appears in the Better Stack query window after
  deploy), the tracker directive `<!-- soleur:followthrough script=… earliest=<deploy+1d> -->`, and
  any new `secrets=` wired into `scheduled-followthrough-sweeper.yml`.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — verify stderr capture + `detail=` classification
  in `inngest-config-refresh.sh`; floor bump 5→6 (Phase 4, if a new bundle is promoted);
  the root-cause fix itself if host-side.
- `.github/workflows/inngest-config-drift.yml` — add `detail` to the `_summ_row` field regex.
- `apps/web-platform/infra/inngest-config-refresh.test.sh` — new S/F rows (Phase 3).
- `apps/web-platform/infra/inngest-host.test.sh` — floor assertion bump (Phase 4).
- `knowledge-base/engineering/architecture/decisions/ADR-135-…md` — defect-3 addendum (Phase 5).
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` — the `detail=`
  taxonomy + the dispatch-probe pointer (Phase 5).
- Producer-side files ONLY if Phase 0 selects a producer fix:
  `.github/workflows/build-inngest-config-bundle.yml` and/or
  `apps/web-platform/infra/inngest-config-bundle-pack.sh` + their test suites.

## Files to Create

- `.github/workflows/diagnose-inngest-verify.yml` — the Phase-0 dispatch probe (kept).
- `scripts/followthroughs/inngest-verify-clean-10390.sh` — soak probe (Phase 5).
- `knowledge-base/engineering/operations/post-mortems/2026-10-22-inngest-config-refresh-verify-blob-reject.md`
  — PIR (Phase 5).
- `knowledge-base/project/specs/feat-one-shot-10390-verify-blob-reject/tasks.md` — derived tasks.

## Acceptance Criteria

- [ ] AC1: `diagnose-inngest-verify.yml` dispatches, pulls the promoted digest with
  `packages: read`, prints the real bundle's `.sigstore.json` structure AND cosign's stderr for the
  verbatim host invocation; the run's measured stderr is recorded in this plan/PIR.
- [ ] AC2: The selected fix branch is named with the measured stderr line it resolves (paper-
  resolution lint — cite `verify_blob.go:117`/`verify_blob.go:172` or the specific verify error).
- [ ] AC3: `inngest-config-refresh.sh` no longer swallows the verify stderr: a bounded
  `$STATE_DIR/verify.stderr` exists after a failing tick and `VERIFY_FAIL` rows carry `detail=<token>`.
- [ ] AC4: F-rows fail pre-fix and pass post-fix; full `inngest-config-refresh.test.sh` green; no
  existing S/F row weakened.
- [ ] AC5: `inngest-config-drift.yml`'s `_summ_row` surfaces `detail=` on a fixture row.
- [ ] AC6: Host replace run completes; post-replace ticks emit zero `reason=signature` VERIFY_FAIL
  rows for the promoted digest within the first hour (off-box query, no SSH). Under the
  `Verified OK` Phase-1 branch (capture-only fix) this re-scopes per CTO ruling: success is
  `detail=` populated and actionable on the next failing tick, not zero VERIFY_FAIL rows.
- [ ] AC7: Soak: zero `reason=signature` VERIFY_FAIL rows for ≥24h post-replace — enrolled via
  `scripts/followthroughs/inngest-verify-clean-10390.sh` + the tracker directive + sweeper wiring.
- [ ] AC8: ADR-135 addendum + PIR committed; PIR `## Follow-ups` filed as issues.
- [ ] AC9: If a new bundle is promoted, the floor is bumped 5→6 in `cloud-init-inngest.yml` and
  `inngest-host.test.sh` in the SAME change (paired-bump rule).
- [ ] AC10: No verification-weakening flag (`--insecure-ignore-tlog`, `--insecure-ignore-sct`,
  `--key`, `--new-bundle-format`) is added anywhere in the change; `grep -n` proves it.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to the dedicated
host's config-refresh channel, its CI producer/diagnostic surfaces, and runbook/ADR records. No UI
surface, no regulated-data surface, no new vendor.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole production scheduler keeps failing to
  ingest host-script fixes silently — a future urgent script fix (the exact case this channel
  exists for) would sit undelivered while markers read green-ish; worse, a wrongly-loosened verify
  turns the provenance gate into an accept-all on the sole scheduler (full-compromise RCE class,
  per ADR-135's own framing).
- **If this leaks, the user's [workflow] is exposed via:** scheduled jobs (statutory deadlines,
  notifications) that silently never fire or fire on stale logic.
- **Brand-survival threshold:** single-user incident — the change edits the cryptographic
  provenance gate on the sole production scheduler; a false-accept is an RCE, a false-reject is a
  missed-deadline.

`requires_cpo_signoff: true` set in frontmatter; `soleur:engineering:review:user-impact-reviewer`
runs at review-time per the plan-signoff lifecycle.

## Scope Check

### Ask Mapping

| Ask (quoted from the brief) | Plan item | Status |
|---|---|---|
| "root-cause diagnosis of the honest verify-blob reject (enumerate the three suspects plus any you find; the plan should include the reproduction/verification path — a CI dispatch workflow run or equivalent no-SSH probe that captures cosign's stderr)" | Phase 0 dispatch probe + ## Hypotheses + AC1/AC2 | mapped |
| "the fix" | Phase 1 (branched on measured stderr) + Phase 4 ship | mapped |
| "its tests (this repo has shell test suites … follow TDD: failing test first)" | Phase 3 + AC4/AC5 | mapped |
| "how the fix ships to the host (running-prod-host config changes ship via cloud-init/Terraform immutable re-provision — respect hr-prod-host-config-change-immutable-redeploy)" | Phase 4 + ## Infrastructure (IaC) + AC6 | mapped |
| "declare an ## Observability block" | ## Observability + AC3/AC7 | mapped |
| "floor 5→6 pin bump" | Phase 4 item 2 + AC9 (conditional on a new promotion) | mapped |
| "backlog items #9927 items 2+4, #8620, #7596, #10713, #10751 (context only — do not plan their implementation)" | ## Non-Goals + ## Open Code-Review Overlap | mapped |

### Plan-Item Provenance

| Plan item | Provenance | Justification |
|---|---|---|
| Phases 0/1/3/4, tests, immutable redeploy, Observability block, floor bump | asked | Directly named in the brief |
| `detail=` stderr-capture + bounded `verify.stderr` + drift-executor field-regex update | inferred | `reason=signature` maps every nonzero rc to one row — the classification overload is what made this defect un-debuggable for a session; the fix is the smallest change that makes the next reject self-diagnosing without weakening the gate |
| Kept `diagnose-inngest-verify.yml` workflow | inferred | A dispatch probe is the only no-SSH path to the private bundle; keeping it is cheaper than re-deriving it on the next reject |
| ADR-135 addendum + PIR + follow-through enrollment | asked-by-convention | Constitution (incident → PIR), `wg-architecture-decision-is-a-plan-deliverable`, ship soak-gate |

### Split Assessment

- Recommendation: single PR/change arc — diagnosis probe, stderr-capture, fix, tests, and host
  replace are one causal chain; splitting would strand the probe or ship an undiagnosed fix. The
  context-only backlog items are excluded via Non-Goals, not split into siblings.

## Downtime & Cutover

**Offline-inducing operation.** `inngest-host-replace` is a full rebirth of `soleur-inngest-prd`,
the SINGLETON production scheduler (ADR-100) — every cron/notification fire stops while the host is
down and resumes when the new host re-attaches the Redis AOF volume.

**Zero-downtime evaluation.** No zero-downtime path exists for THIS change: the defect lives inside
`inngest-config-refresh.sh`, which ADR-135 HARD-1 deliberately places OUTSIDE the refresh-set — the
engine cannot self-update (a signed bundle that could replace the verifier is the accept-all-shim
RCE it exists to prevent). So the refresh channel cannot ship its own fix; a host replace is the
only sanctioned delivery route, exactly as defect 2's fix (run 39818534701) and the channel bake
itself shipped. Blue-green is also unavailable by design: the scheduler is a singleton with a
single LUKS store — running two schedulers concurrently is the split-brain the singleton decision
forbids.

**Residual downtime (accepted with justification).** Bounded maintenance window identical to the
defect-2 replace: Inngest durable functions replay from Redis AOF post-rebirth (zero data loss per
ADR-142/ADR-105), so missed fires during the window reschedule rather than vanish. The refresh
channel being dead TODAY means nothing user-visible regresses during the window — the scheduler's
cron delivery pauses, not degrades further. Operator authorization for the window is implicit in
dispatching `apply_target=inngest-host-replace` (the same authorization defect 2 used).

**Rollback.** The prior boot's image stays replaceable back; the channel stays fail-closed on the
old boot — a bad fix cannot widen acceptance, only continue emitting `VERIFY_FAIL`.

## Guard Contract

### Guard 1 — verification-weakening-flag ban (AC10 / Test T5)

**Property.** No flag that relaxes signature verification (`--insecure-ignore-tlog`,
`--insecure-ignore-sct`, `--key`, `--new-bundle-format`) lands anywhere in this change's added
lines.

**Assembly.** The diff's added lines to the two verify-invocation surfaces —
`inngest-config-refresh.sh` inside `cloud-init-inngest.yml` and any producer/verify edit the Phase-1
branch touches — i.e., the chokepoint is "added line in the PR diff touching an infra file", not
today's call sites. Checked via a diff-scoped `git grep -nE 'insecure-ignore|(--key[ =])|new-bundle-format'`
over added lines (not whole files — the strings legitimately exist in comments/prose).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | Add `--insecure-ignore-tlog` to the host verify invocation | RED |
| M2 | Add `--key /etc/soleur/pub.pem` to the same invocation | RED |
| M3 | Add `--new-bundle-format` to the invocation or the workflow | RED |
| M4 (harness) | Weaken the grep pattern (drop `new-bundle-format` alternation) | RED on a seeded M3 fixture — the guard's own dispatch is exercised, not vacuous |
| M5 (must-pass) | A benign flag/classifier change (e.g., a new `detail=` token arm) | PASS — the guard keys on the weakening set, not on any edit to the line |

**Anchor.** The ban-list is inside the commit; an attacker editing both the flag and the test in
one diff defeats it — mitigated by review (the `single-user incident` threshold pulls in
`user-impact-reviewer`) and the S-row parity-pins in `inngest-config-refresh.test.sh`.

## Network-Outage Deep-Dive

Trigger pattern `timeout` matched (`VERIFY_TIMEOUT_S`, the `timeout` classifier arm). Layer check:
L3 firewall/DNS — not implicated (the verify is `--network none` by design; zot pull on the private
net is proven working by defect-2's fix and the successful bundle/cosign pulls). L7 — not
implicated (no HTTPS path on the verify leg; the Rekor entry verifies offline). The only
`timeout`-adjacent hypothesis is H3 (rc=124 misclassified as `signature`), covered by the Phase-0
stderr capture and the `detail=timeout` classifier arm. No SSH diagnosis is proposed anywhere.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/inngest-host.tf` — unchanged unless Phase 4's floor bump or a
  `triggers_replace` needs touching (the cloud-init `file()` inputs are content-addressed already;
  the host replace is driven by the apply target, not by a new resource).
- No new Terraform root, no new provider, no new sensitive variable. The promoted pointer write
  (`doppler_secret` for `INNGEST_CONFIG_DIGEST`) rides the existing apply path if Phase 1 selects a
  producer fix.

### Apply path

(b) `terraform apply -replace` equivalent — the sanctioned `inngest-host-replace` dispatch on
`apply-web-platform-infra.yml` (run 39818534701 precedent). Expected blast radius: one scheduler
rebirth within the maintenance window; Redis AOF volume re-attach per the runbook. No SSH, no
in-place mutation (`hr-prod-host-config-change-immutable-redeploy`).

### Host fan-out

Single dedicated host (`soleur-inngest-prd`); no fleet siblings for this surface — web hosts do not
run `inngest-config-refresh`.

### Distinctness / drift safeguards

`soleur-inngest/prd` is isolated from `dev`; `terraform apply` reads `file()` inputs at apply time —
the trusted root and cloud-init render are commit-pinned by the apply that replaces the host; no
`lifecycle.ignore_changes` on this surface.

### Vendor-tier reality check

None — no new vendor resource.

## Observability

```yaml
liveness_signal:    # what / cadence / alert_target / configured_in
  what: "SOLEUR_INFRA_PULL_* family rows (APPLIED/NOOP/FLOOR/VERIFY_FAIL with detail=)"
  cadence: "60 s timer tick on soleur-inngest-prd"
  alert_target: "inngest-config-drift dispatch executor (Better Stack ClickHouse query); absence-heartbeat monitor already enrolled"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (emit/verify_fail); .github/workflows/inngest-config-drift.yml"
error_reporting:
  destination: "journald -> Vector Source 4 -> Better Stack; inngest-boot-phone-home.sh direct POST"
  fail_loud: "VERIFY_FAIL rows carry reason=, offered=, rejver= and now detail=; a dead channel can never silently swallow a reject (dual-channel emit)"
failure_modes:
  - mode: "verify-blob honest reject (this defect's class)"
    detection: "SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature detail=<classified token>"
    alert_route: "drift comparator + runbook triage; detail= selects the branch without SSH"
  - mode: "verifier image pull failure"
    detection: "VERIFY_FAIL reason=pull member=cosign-image"
    alert_route: "drift comparator DIVERGED arm"
  - mode: "dead timer / no rows"
    detection: "absence-heartbeat (no SOLEUR_INFRA_PULL_* in window)"
    alert_route: "Better Stack heartbeat alarm"
  - mode: "classifier itself broken (unclassified stderr)"
    detection: "detail=other rows"
    alert_route: "triage reads bounded verify.stderr via next sanctioned host read; detail taxonomy extended"
logs:
  where: "journald on host (durable), Better Stack Logs source (off-box), $STATE_DIR/verify.stderr (bounded 4 KiB, 0600, on-host)"
  retention: "Better Stack source retention; journald rotation; verify.stderr overwritten per tick (last failure only)"
discoverability_test:
  command: "grep -o 'detail=' apps/web-platform/infra/cloud-init-inngest.yml"
  expected_output: "detail="
```

The grep is illustrative of the pre-merge signal; the POST-deploy discoverability path is the drift
executor's `_summ_row` surfacing `detail=` — a `credentials_required` substitute does not exist
locally, so the shipped AC is AC6/AC7's off-box row check.

## Encryption Posture

```yaml
at_rest:
  - store: "$STATE_DIR/verify.stderr (new, bounded diagnostic file on host volume)"
    mechanism: "host root volume plaintext by #8620-known posture; file mode 0600 root:root; content is cosign stderr (no secrets — verified: the verify path holds no credential material; the zot pull token never reaches this file)"
    defends_against: "local non-root readers"
    does_not_defend: "host-volume compromise, privileged escalation (accepted — diagnostic text only)"
    disclosed_as: "this plan + the PIR"
    live_verification: "fixture row asserts file creation + size cap"
in_transit:
  - connection: "none new — verify stays --network none; the only network arm added is the CI dispatch probe (GHCR HTTPS pull, packages: read)"
    tls: "GHCR HTTPS"
    cert_verification: "on"
    does_not_defend: "n/a"
    disclosed_as: "Phase 0"
```

No new persistent store and no new cross-component connection on the host — the section is required
because `cloud-init*.yml` is in the Files-to-Edit set.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-135** (addendum, mirroring the 2026-10-21 defect-2 addendum): record defect 3 — the
measured root cause, the stderr-capture/`detail=` classification addition, and the lesson that a
rc-only classification (`reason=signature` for every nonzero) made an honest reject un-debuggable
without SSH. If Phase 0 reveals a verify-mechanism change beyond flags (e.g., bundle format), the
addendum names the mechanism divergence explicitly; no ADR reversal is anticipated.

### C4 views

Read of `model.c4`/`views.c4`/`spec.c4` for the rubric: the change's actors/systems/edges are all
already modeled — `projectZot` (pull path), `ghcr` (CI-side, dead host edge), the inngest host +
Redis/LUKS nodes, and the sigstore verify edge (`hetzner -> sigstore` noted in the ghcr node). The
fix mutates a step INSIDE the host's refresh script — no new external actor, system, data store, or
access relationship is introduced, and no element description is falsified. **No C4 impact** — the
enumeration checked: external actors (none new — the dispatch probe runs in CI under the existing
GitHub Actions node), external systems (GHCR already modeled; zot already modeled; Sigstore public
good already implied by the cosign verify edges), containers/data stores (none new — `verify.stderr`
is a diagnostic file, not a modeled store), access relationships (unchanged).

### Sequencing

ADR addendum authored in this PR (status `adopting` unchanged — the channel is still pre-complete
until the first APPLIED lands).

## Open Code-Review Overlap

- **#10751** (`code-review: deferred P3s from PR #10743 cosign-zot-stage panel`, OPEN): disposition
  **acknowledge** — the deferred P3s are about the zot-mirror leg, not the host verify path; left
  open by design. Re-check its body during work; fold in only if one of its items names the verify
  invocation.
- **#7596** (inngest boot-trace allowlist gap, OPEN): **acknowledge** — observability-adjacent but a
  different surface (Vector allowlist); the `detail=` fix here narrows the same blind-spot class
  without touching that issue.
- **#9927 items 2+4, #8620, #10713**: **defer** — named context-only by the epic; no file overlap.

## Test Scenarios

| # | Scenario | Method |
|---|---|---|
| T1 | Dispatch probe reproduces the failing verify with stderr | workflow_dispatch run of `diagnose-inngest-verify.yml`; log + summary hold the stderr |
| T2 | `detail=` classification maps each stderr class | F-rows: stubbed `docker run` stderr → `flag-newbundle`, `tlog`, `docker`, `other` |
| T3 | `verify.stderr` bounded + mode | F-row asserts file exists, size ≤ 4097, mode 0600 |
| T4 | Drift executor surfaces `detail=` | fixture row through `_summ_row` includes `detail=<token>` |
| T5 | No-weakening guard | `grep -nE 'insecure-ignore|(--key[ =])|new-bundle-format'` over the diff returns no added line |
| T6 | Floor bump pairing | `inngest-host.test.sh` floor row reads 6 only when the promotion change is in the same diff |
| T7 | Post-replace row watch | `gh run` of `inngest-config-drift.yml` shows no `reason=signature` row post-replace (AC6/AC7) |

## Non-Goals

- Backlog items #9927 items 2+4, #8620, #7596, #10713, #10751 — context only, not implemented here.
- The WARN→ENFORCE deploy-verify flip (#6129) and the static-key Option-B fallback (ADR-135).
- Bundling the floor bump ahead of a promotion — the bump only lands with a new promoted digest.
- Changing the bundle image layout, the pack script's manifest shape, or the refresh-set membership.
- SSH-based host inspection or any in-place host mutation.

## Risks

- **Repro may not reproduce** (environment delta): mitigated by the A/B arms in Phase 0 (0700 stage
  dir, `--network host`) — and a `Verified OK` repro itself is diagnostic (selects the host-state
  branch).
- **Fix weakens the provenance gate**: explicitly banned in AC10 + Non-Goals; any
  verification-relaxing flag needs an ADR amendment, not a code edit.
- **Host replace fails/rolls back**: same blast-radius controls as every `inngest-host-replace`
  (AOF re-attach, window); the channel stays fail-closed on the old boot.
- **`detail=` row breaks drift parsing**: additive field verified against `_summ_row`'s key list;
  executor regex updated in the same change.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Guess-fix without stderr (bump cosign, re-capture root, retry) | Rejected | All three named suspects already measured dead; a guess-fix burns a host replace per attempt and could land a silently weaker verify |
| SSH onto the host to read cosign stderr directly | Rejected | `hr-no-ssh-fallback-in-runbooks` + deny-all-public posture; the dispatch probe is strictly better |
| Make `VERIFY_FAIL` carry full stderr text in the marker | Rejected | Marker rows cross redaction + parser surfaces; bounded `detail=` token + on-host `verify.stderr` file is the correct split |
| Patch the bundle producer speculatively | Rejected | Producer is innocent until Phase 0's `jq` names it; the manifest is already proven byte-identical to the signed blob |
