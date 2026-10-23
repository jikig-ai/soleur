---
title: "fix: inngest config-bundle producer emits a .sigstore.json the pinned verify-blob cannot load"
date: 2026-10-23
slug: inngest-bundle-producer-loadjson
branch: feat-one-shot-10390-verify-blob-producer
issue: 10390
type: fix
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: inngest config-bundle producer emits a .sigstore.json the pinned verify-blob cannot load (epic #10390, defect 3 — Phase-1 producer fix)

## Enhancement Summary

**Deepened on:** 2026-10-23 (same session as authoring — plan + deepen ran in one headless pass;
sequential-fallback: no Task/Agent tool on this harness, fan-outs executed inline)

### Key Improvements

1. **Prime suspect refuted by measurement, not prose:** `tlog_entries`/`timestamp_verification_data`
   are NOT mutually exclusive in bundle v0.3 (protobuf-specs v0.5.1 source: independent fields; the
   oneof covers only key material). Live A/B on the pinned cosign image proved a fixture bundle
   loads WITH both present — the fix is therefore emit-surface control + verbatim-error capture,
   not "delete tsvd".
2. **Failure locus narrowed to `validate()` → `TlogEntries()` → `ParseTransparencyLogEntry`** by
   elimination (protojson.Unmarshal cannot fail on protojson.Marshal output; all other validate
   arms verified vacuous on the observed field set). Phase 0's Go repro prints the verbatim check
   name `checkNewBundle` currently swallows.
3. **Verify-before-publish guard added** — the producer never self-verified its artifact against
   the consumer's pinned loader (`sign.Bundle` in-process validate skips when TrustedRoot is nil,
   and in-memory validate ≠ the on-disk load path). The new step hard-fails pre-push.
4. **Floor-bump ordering hazard made explicit:** floor 6 merged while `INNGEST_CONFIG_DIGEST` is
   still absent FATALs the next boot — merge→promote must ride the same window; no host-replace
   dispatch between them.

### New Considerations Discovered

- Rekor-v2 emit hypothesis: `SignData` REQUIRES a TSA when a Rekor-v2 service is selected —
  `timestampVerificationData` presence is consistent with either a v1+TSA sign or a v2 sign;
  `tlogEntries[0].kindVersion.version` (0.0.1 vs 0.0.2) discriminates.
- `--signing-config <path>` alone suffices: `LoadTrustedMaterialAndSigningConfig` prefers the
  explicit path over `--use-signing-config` default-true-unset (mutual exclusivity only when both
  are explicitly set).

## Overview

Defect 3 follow-up. The prior arc (plan `archive/20261023-130322-…-verify-blob-reject-plan.md`,
merged as PR #10864 e002f2bc + host replace 2026-10-23) shipped Phases 0/2/3:
`diagnose-inngest-verify.yml` (run 40007850907) measured the verbatim host invocation failing rc=1
with `Error: --trusted-root only supported with --new-bundle-format`, and post-replace host rows
(first 2026-10-23T20:46:30Z, ~5-min cadence) carry `detail=flag-newbundle` — the
`sgbundle.LoadJSONFromPath`/`checkNewBundle` gate. The producer — `cosign sign-blob --bundle`
v3.1.1 in `.github/workflows/build-inngest-config-bundle.yml` — emits a `.sigstore.json` whose
envelope the pinned consumer cannot load, while the signing material verifies `Verified OK` under a
hand-built v0.3 reconstruction.

This session's fresh measurement narrowed the locus further (Research Insights). The headline:
**the "tlogEntries + timestampVerificationData are mutually exclusive" prime suspect is REFUTED** —
they are independent proto fields (protobuf-specs v0.5.1: the oneof covers only the key material
`public_key|x509_certificate_chain|certificate`), sigstore-go v1.2.0's `validate()` has no such
check, and a live A/B on the pinned cosign image shows a fixture bundle loads fine WITH both
present. The failure must live inside `validate()` → `TlogEntries()` → `tlog.ParseTransparencyLogEntry`
(nil-field arms / `inclusionProof.checkpoint` empty-or-absent / canonicalizedBody failing both the
Rekor-v1 and Rekor-v2 parsers) — which of those fields the REAL promoted bytes trip requires one
more off-box probe (verbatim-error capture, Phase 0 below). The fix then lands producer-side:
a repo-pinned SigningConfig constraining `sign-blob`'s emit surface to the proven-verifying shape
(Rekor v1 + Fulcio + no TSA), plus a verify-before-publish self-check so this defect class can never
reach GHCR again.

## Research Reconciliation — Spec vs Codebase

| Spec/brief claim | Verified reality (this session, 2026-10-23) | Plan response |
|---|---|---|
| "Prime suspect: tlogEntries and timestampVerificationData are mutually exclusive in bundle v0.3" | **REFUTED.** protobuf-specs v0.5.1 `VerificationMaterial` — `tlog_entries` (field 3) and `timestamp_verification_data` (field 4) are independent repeated/message fields; the `oneof content` covers only `public_key|x509_certificate_chain|certificate`. No mutual-exclusivity check exists in sigstore-go v1.2.0 `validate()`. Live A/B on the pinned image: fixture bundle WITH `timestampVerificationData` passes the load gate (fails later at verify-level checkpoint parsing of the hand-built fixture). | Fix design is not "delete timestampVerificationData" — it is "constrain the emit surface to the proven-verifying shape + verbatim-error the real bytes" |
| "sign-blob populated both via SigningConfig" | Confirmed plausible: default TUF `signing_config.v0.2.json` lists Rekor v1 + `tsaUrls: timestamp.sigstore.dev` (added 2025-07-04); a `signing_config_rekor_v2.v0.2.json` variant adds `log2025-1.rekor.sigstore.dev` (v2, valid from 2026-01-01). `SignData` line ~136 REQUIRES a TSA when a Rekor-v2 service is selected — tsvd presence is consistent with EITHER a v1 sign + TSA or a v2 sign (which forces TSA). | Phase 0's extended jq prints `tlogEntries[0].kindVersion.version` — the v1-vs-v2 discriminator |
| "fix the producer so sign-blob emits a LoadJSONFromPath-conforming bundle" | `LoadJSONFromPath` = `protojson.Unmarshal` + `validate()` (sigstore-go v1.2.0 `pkg/bundle/bundle.go:208-243,83-133`). Since the emitted file IS protojson.Marshal output, unmarshal cannot fail; by elimination the failure is inside `validate()` — realistically `ParseTransparencyLogEntry` | Phase 0 captures the verbatim error before the fix |
| "floor bump 5→6 in the same PR" | Confirmed semantics: the floor is the Doppler admit-set NAME count (`n_inngest -lt 5` in `cloud-init-inngest.yml` ~line 1157 note + `inngest-host.test.sh` ~line 502-506). `INNGEST_CONFIG_DIGEST` is admitted-but-absent; the bump is safe only once the `doppler_secret` exists — i.e., once this arc's post-merge promotion apply runs. Ordering hazard: a host boot/replace BETWEEN this PR's merge and the promotion apply would FATAL (5 names < floor 6). | Floor bump ships in this diff; PR body + merge comment carry the "no replace until promoted" ordering gate |

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #10390 OPEN (epic), no `closedByPullRequestsReferences`. All 8 cited files exist on
  `origin/main` (build/diagnose/apply workflows, pack.sh + pack.test.sh, mirror test,
  cloud-init-inngest.yml, inngest-host.test.sh). Epic comments 6374842238 + 6372614463 confirmed
  live (`detail=flag-newbundle`, diagnose run 40007850907). ADR-135 (+ amendments), ADR-087,
  ADR-096, ADR-128 read via the prior plan's Premise Validation — the proposed mechanism
  (producer-side signing-config pin + verify-gate step) does not collide with a rejected
  alternative: ADR-135's verify topology is host-pinned-offline and unchanged by this fix.
- The `.pen`/UI surface is absent — no wireframe gate.

### Property List (0.6b)

- The producer emits a `.sigstore.json` that `sgbundle.LoadJSONFromPath` accepts at sigstore-go
  v1.2.0 (the pin on the host verify image).
- The host's next tick after a new promotion emits APPLIED (not `detail=flag-newbundle` VERIFY_FAIL)
  — the refresh channel becomes live for the first time.
- A producer regression (emitting an unloadable bundle) can never again reach the published image —
  the workflow fails pre-publish.
- The next `flag-newbundle`-class reject is self-diagnosing WITHOUT re-deriving this session's
  source spelunking — the dispatch probe prints the verbatim `LoadJSONFromPath` error.
- No verification-weakening flag lands anywhere (AC10 carry-over from the parent plan).
- The Doppler admit-set floor reflects reality: 6 once `INNGEST_CONFIG_DIGEST` is materialized.

### Cut List (0.6b)

- *Post-processing the emitted JSON (`jq del(.verificationMaterial.timestampVerificationData)`)* →
  cut as PRIMARY fix: my A/B proves tsvd co-presence loads fine, and a jq-rewrite cannot repair a
  malformed tlog entry if Phase 0 names that locus. Kept only as a named fallback branch.
- *Bump the cosign pin* → cut: the pin parity (same v3.1.1 both ends) is the property being tested;
  moving it widens scope without evidence the producer pin is the bug.
- *A second verifier / alternative bundle layout* → cut: the envelope contract is ADR-135's, not
  renegotiated here.

### Live evidence gathered THIS session (load-bearing)

1. **The gate confirmed in source at the pin.** cosign v3.1.1 `verify_blob.go:114`:
   `NewBundleFormat: c.KeyOpts.NewBundleFormat && checkNewBundle(c.BundlePath)` where
   `--new-bundle-format` defaults **true** (`options/verify.go:69`) — so the observed
   `--trusted-root only supported with --new-bundle-format` fires exactly when
   `sgbundle.LoadJSONFromPath` errors. `checkNewBundle` swallows the error (returns bool) — the
   verbatim error is invisible to the current probe; Phase 0 fixes that.
2. **Mutual exclusivity refuted twice.** (a) protobuf-specs v0.5.1 proto source:
   `tlog_entries`/`timestamp_verification_data` are NOT oneof siblings. (b) Live A/B: rebuilt the
   real v1 Rekor entry (logIndex 3394133887, logID `c0d23d6a…`, hashedrekord/0.0.1) into a v0.3
   bundle (cert + sig + promise + proof) — ran the pinned image's verbatim invocation: passes the
   load gate both WITHOUT and WITH `timestampVerificationData` injected (each run reached
   verify-level checkpoint verification, i.e., past `checkNewBundle`).
3. **By elimination, the failure is inside `validate()` → `TlogEntries()` →
   `ParseTransparencyLogEntry`** (`pkg/tlog/entry.go` at sigstore-go v1.2.0): nil-field arms
   (`canonicalizedBody`, `logIndex < 0`, `logId.keyId`, `kindVersion`), `inclusionProof` present
   but `checkpoint` nil / `envelope == ""` ("inclusion proof missing required checkpoint" /
   "inclusion proof checkpoint empty"), or `canonicalizedBody` failing both
   `unmarshalRekorV2Entry` (needs `spec.spec` = `Spec_HashedRekordV002` + `apiVersion=="0.0.2"`)
   and `unmarshalRekorV1Entry` → "entry body is not a recognizable Rekor v1 or Rekor v2 type".
4. **The Rekor-v2 emit hypothesis.** cosign's `SignData` (`pkg/cosign/bundle/sign.go:111-138`):
   a Rekor-v2 service selection sets `usingRekorV2` and REQUIRES a TSA — consistent with
   `timestampVerificationData` appearing in the emitted bundle at all. If the TUF-published signing
   config at sign time selected the v2 endpoint, the emitted TLE's canonicalizedBody is a
   `rekortilespb.Entry` whose `apiVersion`/spec-shape may not satisfy the sigstore-go v1.2.0 pin's
   `unmarshalRekorV2Entry` (rekor-tiles June-2026 pin) → the load error above. The v1 index hit for
   the manifest sha256 (entryUUID `108e9186…`, logIndex 3394133887) shows a v1 entry also exists —
   the emitted bundle's `kindVersion.version` (v1 `0.0.1` vs v2 `0.0.2`) discriminates. **Note:**
   the default `signing_config.v0.2.json` source in `sigstore/root-signing` lists ONLY Rekor v1 —
   if the published TUF copy still matches, the emitted TLE is v1 and the failing field is subtler
   (empty `checkpoint.envelope` from the create-response is the next suspect). Phase 0 resolves it.
5. **Producer never self-verified.** `sign.Bundle` runs `verifyBundle.NewBundle(bundle)` —
   `validate()` — only `if opts.TrustedRoot != nil`; and even when set, in-memory validate ≠ the
   on-disk load path. `cosign sign-blob` does not assert its own output loads. That is the
   self-test gap this defect exploited — the verify-before-publish step closes it.
6. **Fix lever confirmed at v3.1.1:** `--signing-config <path>` flag on `sign-blob`
   (`options/signblob.go:115-118`; mutually exclusive with `--use-signing-config` only when BOTH
   are explicitly set — `--use-signing-config` defaults true-but-unset, so the path alone works;
   `LoadTrustedMaterialAndSigningConfig` prefers `signingConfigPath != ""`). A repo-pinned
   `SigningConfig` JSON (mediaType `application/vnd.dev.sigstore.signingconfig.v0.2+json`) is a
   committed, reviewable input — same shape as the baked `cosign-trusted-root.json` precedent.
7. **The floor is a Doppler NAME count, not a bundle VERSION.** `-lt 5` in
   `cloud-init-inngest.yml` (~line 1157 note) + `inngest-host.test.sh` (~line 502 FLOOR extract +
   ~506 `== "5"`). Next monotonic bundle VERSION is **4** (v3 promoted). Bump ordering: floor=6
   merged with a 5-name live set makes the next boot FATAL → merge+promote must ride the same
   window; no host replace may dispatch between them.
8. **Sequential-fallback disclosure.** This run has no Task/Agent tool — the Phase-1 research
   fan-out (repo-research-analyst, learnings-researcher, functional-discovery, spec-flow-analyzer)
   and the Plan Review panel were executed sequentially inline by the orchestrator.
   `Reviewed-Coverage: sequential-fallback` — no independent review agent ran.

## Hypotheses

Network-outage checklist fired on the `SSH` substring in the brief; all layers opted out by
artifact: the failure is a cryptographic-envelope load reject reproduced in CI (run 40007850907),
not a connectivity event — verify runs `--network none` by design, and zot pull/extract already
succeed (defect-2 fix proved the path). L3 firewall/DNS: not implicated (repro on CI egress hits
the same reject as the private-net host). L7: not implicated (no HTTPS on the verify leg).

Remaining root-cause hypotheses for the REAL emitted bytes, ranked — each resolved by Phase 0's
verbatim-error capture (`LoadJSONFromPath` error text) + the extended field dump:

| # | Hypothesis | For | Against | Discriminator |
|---|---|---|---|---|
| H1 | `tlogEntries[0]` is a Rekor-v2 tiles entry whose `canonicalizedBody` fails `unmarshalRekorV2Entry` at the sigstore-go v1.2.0 pin (`apiVersion`/`spec.spec` mismatch) → "entry body is not a recognizable Rekor v1 or Rekor v2 type" | v2 sign forces a TSA → explains `timestampVerificationData`; sign-time drift window (TUF config moves under the producer) | default signing_config.v0.2 lists Rekor v1 only in the repo source; a v1 entry exists in the public index | verbatim error text + `kindVersion.version` + decoded `canonicalizedBody` head |
| H2 | `inclusionProof` present but `checkpoint` nil or `envelope == ""` (create-response emitted an empty checkpoint that only later GETs populate) | the only `ParseTransparencyLogEntry` arms that fire on a populated-looking v1 proof; jq proved the proof KEY exists, not its contents | rekor v1 create responses have carried synchronous checkpoints for years | `jq` of `inclusionProof.checkpoint` + error text |
| H3 | A mandatory scalar absent/empty in the emitted TLE (`canonicalizedBody`, `logId.keyId`, `kindVersion`) → `ErrNilValue` | `GenerateTransparencyLogEntry` populates all — but a nil `Verification.InclusionProof` short-circuit or an empty `Body` in the create payload would slip through unguarded | the fetched entry has all fields | extended jq key census |
| H4 | protojson-level defect in the emitted file (duplicate key, invalid UTF-8 string, wrong-type field) | last-resort catch-all | protojson.Marshal output round-trips through Unmarshal on identical descriptors | verbatim error names it |

## Implementation Phases

### Phase 0 — verbatim-error diagnostic (extend the kept dispatch probe)

`.github/workflows/diagnose-inngest-verify.yml` gains, in the existing `repro` job:

1. **Extended field dump** — jq on the real `.sigstore.json`: top-level keys,
   `verificationMaterial.tlogEntries[0] | keys` (assert `canonicalizedBody`, `kindVersion`,
   `logId`, `integratedTime` presence), `kindVersion.version` (v1 `0.0.1` vs v2 `0.0.2` —
   discriminates H1), `.inclusionProof.checkpoint.envelope | length` (empty/absent → H2),
   `.canonicalizedBody | @base64d | .[0:200]` head (v1 `{kind:…}` vs v2 `{apiVersion,spec:…}` shape),
   `verificationMaterial.timestampVerificationData` shape, `messageSignature`/`dsseEnvelope` census.
2. **Verbatim `LoadJSONFromPath` error** — a ~25-line Go probe run in the job (actions/setup-go +
   `go mod init probe && go get github.com/sigstore/sigstore-go@v1.2.0 && go run probe.go
   "$S/bundle/manifest.txt.sigstore.json"`): `bundle.LoadJSONFromPath`, print `err` verbatim (or
   `LOAD_OK` + `b.Version()`). Same vendored version as the pinned verify image — this prints the
   EXACT check name (e.g. `inclusion proof missing required checkpoint`, `not a recognizable Rekor
   v1 or Rekor v2 type`, nil-value), which `checkNewBundle` currently swallows. This is a KEEPABLE
   deliverable — the next `flag-newbundle` row self-diagnoses.
3. Dispatch the workflow on the current failing digest (default input `4e17987c…`); record the
   verbatim error in the plan/decision log → selects the fix arm. Arm shape unchanged; the new
   steps are additive.

### Phase 1 — producer fix (primary arm; branches on Phase-0 text)

**Primary fix — pin the emit surface (covers H1 and H3-by-construction, shrinks the envelope):**

1. Commit `apps/web-platform/infra/inngest-signing-config.json` — a signingconfig v0.2 document
   modeled on `sigstore/root-signing/targets/signing_config.v0.2.json`: `caUrls` = Fulcio v1,
   `oidcUrls` = oauth2.sigstore.dev v1 (schema fidelity; the Actions OIDC ambient token path does
   not consume it), `rekorTlogUrls` = **`https://rekor.sigstore.dev` majorApiVersion 1 only**,
   `rekorTlogConfig.selector: ANY`, `tsaConfig.selector: ANY` with **`tsaUrls` omitted entirely** —
   no TSA → no `timestampVerificationData` in the emitted bundle, one less moving surface (the host
   verify never consults tsvd; integratedTime+inclusionProof is its validity path). Header comment
   block documents the capture date + pin rationale (mirror the trusted-root file's comment style).
2. `build-inngest-config-bundle.yml` sign step:
   `cosign sign-blob --yes --bundle "${MANIFEST}.sigstore.json" --signing-config apps/web-platform/infra/inngest-signing-config.json "${MANIFEST}"`.
   Implementer verifies `cosign sign-blob --help` token (`--signing-config`) on the runner's
   installed v3.1.1 before pushing (CLI-verification gate; `cosign signing-config create --help`
   documents the schema if the file is generated rather than hand-authored).
3. **Verify-before-publish self-check** — new step between sign and `Assemble bundle tarball`:
   run the pinned cosign (the installer already put v3.1.2→v3.1.1 on PATH; use it — or the pinned
   image via docker) `verify-blob --trusted-root apps/web-platform/infra/cosign-trusted-root.json
   --bundle <produced> --certificate-identity-regexp <derived> --certificate-oidc-issuer
   https://token.actions.githubusercontent.com <manifest>` on the runner (network available — the
   Fulcio cert chain + Rekor proof are verified live). The identity regexp is derived from the
   run's ref so branch dispatches also pass: pin `^https://github\.com/jikig-ai/soleur/\.github/workflows/build-inngest-config-bundle\.yml@${GITHUB_REF}$`
   (escape ref metacharacters; the host-side baked regexp for `main` is unchanged). The step
   hard-fails (`exit 1`) unless it prints `Verified OK` — an unloadable bundle can no longer reach
   the push steps. This is the never-again guard for the defect class.

**Fallback arms (only if Phase 0's error falsifies the primary):**

- H2-confirmed (checkpoint empty in create-response TLE): add a repair step — refetch the entry via
  Rekor `GET /api/v1/log/entries/{uuid}` (uuid derivable from the create response / search by
  hash), rebuild `tlogEntries[0]` fields from the GET payload (jq), re-emit the JSON. Deterministic
  and produces the byte-shape the loader wants; keep the pinned signing config too.
- H4-confirmed (protojson shape defect): the smallest emitter-side correction the error names
  (e.g. drop/repair the malformed field via jq), still behind the verify-gate so a mis-repair is
  caught pre-publish.
- NEVER under any arm: `--insecure-ignore-tlog`, `--insecure-ignore-sct`, `--key`, or
  `--new-bundle-format` on a cosign argv (AC10).

### Phase 2 — TDD (failing rows land BEFORE the fix)

- `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` (the build-workflow's guard suite):
  - S-row: the sign step's `run:` body carries `--signing-config` referencing
    `apps/web-platform/infra/inngest-signing-config.json` and does NOT carry a weakening flag
    (extends the existing step-extraction harness).
  - S-row: a step named to verify the produced bundle runs BEFORE `Assemble bundle tarball` /
    `docker build` (YAML step-order assertion via the parsed workflow).
  - S-row: `inngest-signing-config.json` parses as signingconfig v0.2, `rekorTlogUrls` is
    exactly one entry at majorApiVersion 1, and `tsaUrls` is absent (jq assertions on the
    committed file — a shape row, not a network call).
  - Mutation battery rows: removing `--signing-config` / re-adding a `tsaUrls` entry / deleting the
    verify step each drive the suite RED (guard is not vacuous).
- `apps/web-platform/infra/inngest-config-bundle-pack.test.sh`: keep manifest invariants; add one
  row only if the fix arm changes what the pack script emits (it does not under the primary arm —
  the manifest is the signed blob, untouched; record `no change required` if so rather than a
  vacuous row).
- `plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh`: S-rows asserting the new
  field-dump + Go-load-probe steps exist (step-name + content greps against the parsed YAML), and
  that the probe pins `sigstore-go@v1.2.0` literally.
- `apps/web-platform/infra/inngest-host.test.sh`: floor row `FLOOR == "5"` → `== "6"` —
  fails pre-bump, passes post-bump; the companion `-lt 5` → `-lt 6` greps ride together
  (paired-bump rule; the in-file note names both files).

### Phase 3 — floor bump (rides this diff)

`cloud-init-inngest.yml`: the isolation self-check `-lt 5` → `-lt 6` + update the surrounding
"floor stays 5 ON PURPOSE" comment to record that `INNGEST_CONFIG_DIGEST` materializes in this
arc's promotion apply. `inngest-host.test.sh` floor assertions 5→6. Ordering hazard documented in
the PR body + a PR merge comment: no `inngest-host-replace` dispatch may run between merge and the
promotion apply (a 5-name live set under floor 6 FATALs boot).

### Phase 4 — post-merge follow-through (dispatch + promote; normal gates apply)

1. Dispatch `build-inngest-config-bundle.yml` at `version=4` (next monotonic after promoted v3;
   HARD-9: pointer version must exceed applied). The new verify-before-publish step proves the
   emitted bundle loads+verifies before the image exists.
2. Dispatch `diagnose-inngest-verify.yml` against the NEW published digest: verbatim probe prints
   `LOAD_OK`, verify arm prints `Verified OK` under the verbatim host invocation. Record as AC
   evidence.
3. Promote: `TF_VAR_inngest_config_digest=<new digest>` on the `soleur/prd_terraform` apply path
   (apply-web-platform-infra.yml — the `doppler_secret.inngest_config_digest` write per runbook
   step 3). This materializes the secret the floor bump counts on — ordering gate above applies.
4. Off-box watch: next ~5-min tick emits `SOLEUR_INFRA_PULL_APPLIED` for version 4; zero
   `detail=flag-newbundle` VERIFY_FAIL rows. `inngest-config-drift` comparator reads the digest
   match.
5. Standing Delegation on #10390 covers only scheduled-terraform-drift + revert-PRs — steps 1-3
   follow normal dispatch gates (operator authorization in the PR body's ship notes).

### Phase 5 — records (amend, not re-author)

- ADR-135 addendum (append to the defect-3 record): producer-side root cause as measured in
  Phase 0, the emit-surface pin + verify-before-publish mechanism, and the lesson that a producer
  must verify its own artifact against the CONSUMER's pinned loader — sign-time validate() is not
  the on-disk load path.
- Amend `knowledge-base/engineering/operations/post-mortems/2026-10-22-inngest-config-refresh-verify-blob-reject.md`
  `## Follow-ups` to close the loop on the producer root cause.
- Runbook `inngest-config-refresh.md`: note the pinned signing-config input + the verify-gate as
  part of the producer contract.
- Follow-through: `scripts/followthroughs/inngest-verify-clean-10390.sh` is already enrolled —
  extend its earliest window / note the second-leg clean signal (APPLIED v4) rather than a new
  probe.

## Files to Edit

- `.github/workflows/build-inngest-config-bundle.yml` — `--signing-config` on the sign-blob argv;
  new verify-before-publish step between sign and assemble/push.
- `.github/workflows/diagnose-inngest-verify.yml` — extended field-dump jq + the
  `LoadJSONFromPath` verbatim-error Go probe step + a LOAD_OK verdict line.
- `apps/web-platform/infra/cloud-init-inngest.yml` — floor `-lt 5` → `-lt 6` + comment update
  (Phase 3).
- `apps/web-platform/infra/inngest-host.test.sh` — floor assertions 5→6.
- `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` — sign-step + verify-gate + config-file
  shape rows + mutation battery.
- `plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh` — S-rows for the new probe steps.
- `knowledge-base/engineering/architecture/decisions/ADR-135-…md` — defect-3 producer-side addendum.
- `knowledge-base/engineering/operations/post-mortems/2026-10-22-inngest-config-refresh-verify-blob-reject.md`
  — root-cause closure note.
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` — producer contract note.
- `scripts/followthroughs/inngest-verify-clean-10390.sh` + its test — window/wording amendment only
  if the probe's verdict needs it (check at work time; else leave untouched).

## Files to Create

- `apps/web-platform/infra/inngest-signing-config.json` — pinned signingconfig v0.2 (Fulcio v1 +
  OIDC v1 + Rekor v1 only; no TSA).
- `knowledge-base/project/specs/feat-one-shot-10390-verify-blob-producer/tasks.md` — derived tasks.

## Acceptance Criteria

- [ ] AC1: `diagnose-inngest-verify.yml` (extended) prints the verbatim `LoadJSONFromPath` error
  for the real promoted digest via the sigstore-go@v1.2.0 probe, and the extended jq field map;
  the named check is recorded in this plan/decision log.
- [ ] AC2: `build-inngest-config-bundle.yml`'s sign step passes `--signing-config` pointing at a
  committed repo file; the file's `rekorTlogUrls` is Rekor v1 only and carries no `tsaUrls`.
- [ ] AC3: A verify-before-publish step runs `verify-blob` with the baked trusted root + ref-derived
  identity regexp on the produced bundle BEFORE any push; it exits non-zero unless `Verified OK`
  prints. (The mutation battery in the mirror suite proves the guard goes red.)
- [ ] AC4: TDD discipline: the new rows fail pre-fix (evidence captured in commit history / PR
  notes) and pass post-fix; no existing row weakened.
- [ ] AC5: Floor `-lt 5`/`== "5"` → 6 in `cloud-init-inngest.yml` + `inngest-host.test.sh` in this
  same diff (paired-bump rule); the PR body carries the merge→promote ordering gate.
- [ ] AC6: Post-merge: `build-inngest-config-bundle.yml` dispatched at version=4 succeeds — the
  verify-gate prints `Verified OK` in its step log.
- [ ] AC7: `diagnose-inngest-verify.yml` on the NEW digest prints `LOAD_OK` from the probe AND
  `Verified OK` from the verbatim host arm.
- [ ] AC8: The promotion apply writes `doppler_secret.inngest_config_digest` with the new digest;
  host ticks emit `SOLEUR_INFRA_PULL_APPLIED` (version=4) within 15 min and zero
  `detail=flag-newbundle` rows — off-box evidence only (Better Stack query / drift executor; no SSH).
- [ ] AC9: ADR-135 addendum + PIR follow-up amendment + runbook note committed.
- [ ] AC10: No verification-weakening flag (`--insecure-ignore-tlog`, `--insecure-ignore-sct`,
  `--key`, `--new-bundle-format`) added on any cosign argv in this diff; `grep -n` proves it.
- [ ] AC11: No host replace is required for this fix — the refresh channel applies the fixed bundle
  on the existing host (asserted by AC8 evidence, not a dispatch).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI producer workflow + infra script changes on the
established signed-bundle channel; no UI surface, no regulated-data surface, no new vendor.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole production scheduler stays unable to
  ingest host-script fixes (status quo — the channel is already dead) OR, worse, a falsely-green
  verify gate lets a bad bundle publish and the host still rejects it — a wasted incident day.
  A wrongly-loosened verify gate remains the accept-all RCE class from ADR-135's framing — the
  AC10 ban carries forward verbatim.
- **If this leaks, the user's workflow is exposed via:** scheduled jobs silently running stale
  logic (statutory deadlines, notifications).
- **Brand-survival threshold:** single-user incident — this edits the provenance channel's
  producer contract; false-accept at the verify-gate would publish a bundle the brand cannot
  afford to have applied.

`requires_cpo_signoff: true` carried in frontmatter; `user-impact-reviewer` runs at review-time.

## Scope Check

### Ask Mapping

| Ask (quoted from the brief) | Plan item | Status |
|---|---|---|
| "fix the producer (build-inngest-config-bundle.yml and/or inngest-config-bundle-pack.sh) so sign-blob emits a LoadJSONFromPath-conforming bundle" | Phase 1 (pinned SigningConfig + verify-gate) | mapped |
| "TDD failing rows first in the pack/mirror test suites" | Phase 2 (mirror suite rows; pack suite row only if the fix arm touches it) | mapped |
| "extend diagnose-inngest-verify.yml to assert the new bundle LOADS via LoadJSONFromPath if useful" | Phase 0 (verbatim-error probe + field dump; LOAD_OK verdict) | mapped |
| "dispatch build at VERSION=N+1, promote the new digest via the Terraform doppler_secret write on apply-web-platform-infra.yml" | Phase 4 steps 1+3 | mapped |
| "bump the baked floor 5→6 in cloud-init-inngest.yml + inngest-host.test.sh — rides IN THIS PR's diff" | Phase 3 + AC5 | mapped |
| "NO verification-weakening flags … no SSH; host-side untouched" | Constraints + AC10/AC11 | mapped |
| "Prime suspect to verify against sigstore-go v3.1.1 validation semantics" | Verified at vendored sigstore-go v1.2.0 (cosign v3.1.1 go.mod) — REFUTED, documented | mapped |

### Plan-Item Provenance

| Plan item | Provenance | Justification |
|---|---|---|
| Phases 1-4, tests, floor bump, promotion | asked | Directly named in the brief |
| Phase 0 verbatim-error probe (Go LoadJSONFromPath repro) | inferred | `checkNewBundle` swallows the error — without the verbatim check name the fix is guesswork; this session's source audit already refuted the stated prime suspect once |
| Verify-before-publish step in the producer | inferred | The self-test gap that let an unloadable bundle reach GHCR — smallest structural fix for the defect class, required by `hr-observability-as-plan-quality-gate` (a producer asserting its own artifact before publish) |
| PIR/runbook/ADR amendments | asked-by-convention | ADR deliverable rule + incident record completeness |

### Split Assessment

- Recommendation: single PR/change arc — the probe extension, producer fix, tests, and floor bump
  are one causal chain (the floor's safety depends on the promotion this arc delivers). No sibling
  split.

## Downtime & Cutover

**No host replace, no downtime.** The defect is producer-side: once a conforming bundle is
published + promoted, the EXISTING host's next ~60-s tick verifies and applies it. The only
production-mutating steps are CI dispatches and the Terraform `doppler_secret` write — both are
the channel's normal promotion path, not host mutation. Ordering hazard (not downtime, a brick
gate): floor=6 merged while `INNGEST_CONFIG_DIGEST` is still absent would FATAL the next boot —
the merge and the promotion apply must ride the same window; stated in the PR body.

**Rollback:** the previous pointer digest remains the last-known-good promotion input — a bad new
bundle keeps emitting VERIFY_FAIL (fail-closed), never a false apply.

## Guard Contract

### Guard 1 — verification-weakening-flag ban (AC10, carried from parent plan)

**Property.** No `--insecure-ignore-tlog`/`--insecure-ignore-sct`/`--key`/`--new-bundle-format`
token lands in flag position on any cosign argv in this diff.

**Assembly.** Added lines to `.github/workflows/build-inngest-config-bundle.yml` and
`.github/workflows/diagnose-inngest-verify.yml` (the two cosign-invocation surfaces); diff-scoped
`git grep -nE 'insecure-ignore|(--key[ =])|new-bundle-format'` over added lines. The diagnose
shape suite already greps whole-file for the ban set — extend identical coverage to the build
workflow via the mirror suite's step-extraction harness.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | Add `--insecure-ignore-tlog` to the verify-gate step | RED |
| M2 | Add `--key foo.pem` to the sign or verify argv | RED |
| M3 | Add `--new-bundle-format` to any cosign argv | RED |
| M4 (harness) | Drop the `new-bundle-format` alternation from the guard regex | RED on a seeded M3 fixture |
| M5 (must-PASS) | A benign argv change (e.g. new `--signing-config` flag itself) | PASS |

**Anchor.** Ban-list is inside the commit; both the flag and the test editable in one diff —
mitigated by review at the single-user-incident threshold (`user-impact-reviewer`).

### Guard 2 — verify-before-publish (the producer self-check)

**Property.** The workflow cannot reach the image-push steps with a bundle that fails
`LoadJSONFromPath` or the pinned host verify.

**Assembly.** The step-order chokepoint in `build-inngest-config-bundle.yml`: sign → **verify
(exit-gated on `Verified OK`)** → assemble → login → build+push. The guard asserts (a) a verify
step exists between sign and assemble, (b) its argv carries the pinned trusted-root + bundle +
identity-regexp + issuer, (c) it hard-fails on non-zero rc.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | Delete the verify step entirely | RED (S-row: step exists) |
| M2 | Reorder verify AFTER `docker build`/push | RED (step-order row) |
| M3 | Make the verify step `continue-on-error: true` | RED (hard-fail row) |
| M4 | Add a second push path bypassing the gate (e.g. `if: steps.verify.outcome != 'success'` branch that still pushes) | RED — push steps must not carry outcome-insulating conditions |
| M5 (harness) | Neuter the step-name grep (wildcard `.*` for the step name) | RED on a no-verify-step fixture |
| M6 (must-PASS) | Rename a DIFFERENT step or reorder login before verify | PASS |

**Anchor.** Structural gate on workflow YAML inside the commit; review coverage as Guard 1.

## Network-Outage Deep-Dive

Trigger pattern `SSH` matched (the "no SSH" constraint in the brief). All checklist layers opted
out with artifacts — this is an envelope-load defect, not connectivity:

- L3 firewall/DNS — the CI runner (public egress) reproduced the identical reject as the
  private-net host (run 40007850907) → not network-layer.
- L7 TLS/proxy — the verify leg is `--network none` by design; zot pull/extract succeed on the
  host (defect-2 fix + live APPLIED-adjacent rows reaching the verify stage).
- L7 application — host journal surfaces via VERIFY_FAIL rows with `detail=flag-newbundle`
  (Better Stack), already the off-box channel. No SSH diagnosis proposed anywhere.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/inngest-config-digest.tf` — unchanged; the promotion apply writes the
  new digest value into `doppler_secret.inngest_config_digest` (count-gated, springs on non-empty
  `TF_VAR_inngest_config_digest` in `soleur/prd_terraform`). No new resource, provider, or root.
- `cloud-init-inngest.yml` floor edit is cloud-init text (applies next boot — no replace required
  for this fix's effect; it must merely be in-tree before any NEXT provision after the secret
  exists).

### Apply path

(b)-adjacent, promotion-only: `apply-web-platform-infra.yml` with `TF_VAR_inngest_config_digest`
set in `soleur/prd_terraform` — the sanctioned pointer write (runbook step 3). NOT a host replace.
No SSH, no in-place host mutation.

### Host fan-out

Single dedicated host (`soleur-inngest-prd`); no fleet siblings on this surface.

### Distinctness / drift safeguards

`soleur-inngest/prd` remains isolated; the digest write is one secret name already admitted in the
isolation regex. The floor bump is commit-pinned to this diff — the hazard window (floor 6 merged,
secret absent) is bounded by the merge→promote ordering gate in the PR body.

### Vendor-tier reality check

None — no new vendor resource.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INFRA_PULL_APPLIED version=4 (first live apply) + zero detail=flag-newbundle rows"
  cadence: "60 s host tick; ~5-min VERIFY_FAIL re-emit cadence on failure"
  alert_target: "inngest-config-drift dispatch executor + Better Stack absence-heartbeat (enrolled)"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (emit path, unchanged); .github/workflows/inngest-config-drift.yml"
error_reporting:
  destination: "journald -> Vector -> Better Stack; producer-side: workflow step logs + $GITHUB_STEP_SUMMARY"
  fail_loud: "verify-before-publish step hard-fails the run pre-publish; the diagnose probe prints the verbatim LoadJSONFromPath error"
failure_modes:
  - mode: "producer emits another unloadable bundle (any future cause)"
    detection: "build workflow fails at the verify-gate step — never reaches push; GHCR digest never published"
    alert_route: "workflow run failure notification + step log holds the verbatim error"
  - mode: "new bundle loads but fails a deeper verify check"
    detection: "verify-gate stderr names the check (tlog/identity/chain) — and diagnose probe's verbatim arm reproduces it on the published digest"
    alert_route: "runbook triage via detail= taxonomy"
  - mode: "promotion applies but host still VERIFY_FAILs"
    detection: "SOLEUR_INFRA_PULL_VERIFY_FAIL detail=<token> persists post-promotion"
    alert_route: "drift comparator DIVERGED; diagnose dispatch on the promoted digest"
logs:
  where: "workflow run logs + $GITHUB_STEP_SUMMARY (producer/diagnose); host journald -> Better Stack (consumer)"
  retention: "Actions log retention; Better Stack source retention"
discoverability_test:
  command: "grep -c 'signing-config' .github/workflows/build-inngest-config-bundle.yml"
  expected_output: "1"
```

The grep is the pre-merge signal (the sign step carries exactly one `--signing-config`
occurrence); the post-deploy signal is AC8's off-box APPLIED row.

## Encryption Posture

```yaml
at_rest:
  - store: "none new — inngest-signing-config.json is a public service-URL document (no secrets; same class as cosign-trusted-root.json)"
    mechanism: "n/a — public endpoints list only"
    defends_against: "n/a"
    does_not_defend: "n/a — no sensitive material"
    disclosed_as: "this plan"
    live_verification: "shape-row in the mirror suite asserts the file's service set"
in_transit:
  - connection: "producer verify-gate: runner -> fulcio/rekor/tsa+GHCR HTTPS (existing sign path) — no NEW connection class"
    tls: "HTTPS"
    cert_verification: "on"
    does_not_defend: "n/a"
    disclosed_as: "Phase 1"
```

Required because `cloud-init-inngest.yml` is in the Files-to-Edit set (floor bump — no encryption
surface touched).

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-135** — append to the defect-3 addendum: producer-side root cause (as measured by
Phase 0), the emit-surface pin (`--signing-config` repo file), and the verify-before-publish
self-check. No ADR reversal: the channel contract (HARD-1…12) is unchanged — this fixes a producer
that violated the consumer's envelope contract. If Phase 0 names a Rekor-v2 emit as the cause, the
addendum also records "producer pins Rekor v1 while the v1→v2 transition is out-of-scope" as a
bounded decision with a re-evaluation hook.

### C4 views

Read `model.c4`/`views.c4`/`spec.c4` per the rubric: all actors/systems already modeled — GitHub
Actions node (producer), GHCR + zot (publish/pull), sigstore verify edge, the inngest host. The
change adds no new external actor, system, container, or data store (the signing-config file is a
config input, not a store; the verify step runs inside the existing Actions job). **No C4 impact**
— enumeration checked: external actors (none new), external systems (fulcio/rekor/tsa endpoints
are all already-implied cosign edges; GHCR/zot/sigstore already modeled), access relationships
(unchanged — same OIDC + packages:write scopes).

### Sequencing

ADR addendum authored in this PR (status `adopting` unchanged — first real APPLIED lands via this
arc's promotion).

## Open Code-Review Overlap

- **#10243** (`review: nft comment correction on PR 8945`, OPEN) — mentions
  `cloud-init-inngest.yml`. **Acknowledge** — comment-text fix, different surface; does not
  touch the floor or refresh script. Re-check body at work time; fold in only if it names the
  admit-set/floor region.
- **#10112** (`review: finish the #9786 residuals…`, OPEN) — mentions `cloud-init-inngest.yml`.
  **Acknowledge** — #9786 residual list (rollback arm / rehearsal volume / blank-prd DR / reopen
  arms), unrelated to this defect. Left open.
- No open code-review issues touch `build-inngest-config-bundle.yml`, the pack/mirror/diagnose
  suites, `inngest-host.test.sh`, or `cosign-trusted-root.json` (queried 2026-10-23, two-stage
  `gh --json` + standalone `jq` per the arg-forwarding learning).

## Test Scenarios

| # | Scenario | Method |
|---|---|---|
| T1 | Verbatim `LoadJSONFromPath` error captured for the real digest | Phase-0 dispatch; step log holds the Go probe output |
| T2 | Producer emits v1-only Rekor + no tsvd | jq assertions on `inngest-signing-config.json` (mirror suite) + the produced bundle's keys at next dispatch |
| T3 | Verify-gate blocks an unloadable bundle | Mutation battery M1-M4 rows (structural); live evidence: a seeded bad bundle in a dispatch test would fail the step |
| T4 | New digest loads + verifies | diagnose dispatch on the new digest: `LOAD_OK` + `Verified OK` (AC7) |
| T5 | No weakening flags | `grep -nE 'insecure-ignore\|(--key[ =])\|new-bundle-format'` over added lines → clean (AC10) |
| T6 | Floor pairing | `inngest-host.test.sh` reads 6 only with the promotion change in the same diff |
| T7 | Channel goes live | off-box APPLIED version=4 row; zero flag-newbundle rows (AC8) |

## Non-Goals

- Host-side changes (the `detail=` capture is already live; no script edits, no replace).
- Rekor v1→v2 transition planning; Fulcio/Rekor2/TSA architecture evaluation beyond the pin.
- Bundling the floor bump WITHOUT the promotion in this arc (it is forbidden by the same rule that
  includes it — the two ride together).
- `#9927`, `#8620`, `#7596`, `#10713`, `#10751` backlog items — context only.
- Amending `inngest-config-bundle-pack.sh` unless a Phase-0 arm requires it (manifest untouched by
  the primary fix).

## Risks

- **Phase-0 error names an unanticipated locus** — mitigated: fix arms are branched on the
  measured error, not on the prime suspect (already refuted once).
- **Rekor v1 deprecation**: pinning v1 is a bounded decision — the addendum names the
  re-evaluation hook (sigstore's public v1 sunset announcements).
- **Ordering hazard (floor 6 vs absent secret)**: a host replace dispatched between merge and
  promotion FATALs boot — the PR body + merge comment carry the gate; blast radius = one boot
  failure with a known remedy (promote, then replace).
- **Identity-regexp derivation for branch dispatches**: the verify-gate uses `${GITHUB_REF}`; a
  ref containing regex metacharacters (e.g. `+`) is escaped before assembling the regexp —
  implementer note, pinned by a row in the mirror suite.
- **`--signing-config` + default `--use-signing-config` flag interplay**: mutually-exclusive only
  when both are explicitly set — `--signing-config` alone takes precedence
  (`LoadTrustedMaterialAndSigningConfig` prefers `signingConfigPath`); implementer verifies the
  token on the runner's installed cosign before pushing (CLI-verification gate).

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| jq `del(.verificationMaterial.timestampVerificationData)` post-sign | Rejected as primary; kept as H2/H4 fallback shaping | tsvd co-presence is PROVEN innocent (live A/B); post-processing can't repair a malformed TLE; adds a hand-edited artifact between sign and publish |
| Bump cosign pin (producer and/or host) | Rejected | Same-version parity is the property under test; no evidence the pin is the defect |
| Fix the emitted TLE by re-uploading / re-fetching the Rekor entry | Fallback arm only (H2) | Adds a second network dependency at sign time; only correct if the measured error names the proof/body |
| Host-side `--new-bundle-format` or loosening flags | Forbidden (AC10) | Verification-weakening = security posture change; ADR-135 amendment territory, not a patch |
| New verifier image / alternative bundle layout | Rejected | Envelope contract is ADR-135's; not renegotiated for a producer defect |

## Decision Log (technical rulings — no Agent tool this session; per technical-ruling-delegation
each row is `pending - assumed: <default>`)

| Item | Class | Ruling |
|---|---|---|
| Fix shape: pinned SigningConfig (v1+no-TSA) vs post-process emitted JSON | technical | pending - assumed: pinned SigningConfig primary, jq-repair fallback arm |
| Whether Phase-0 verbatim-error probe (Go repro) precedes the fix | technical | pending - assumed: yes — the check name selects the arm |
| Floor 5→6 ordering vs promotion apply | technical | pending - assumed: same-window merge→promote gate documented in PR body |
