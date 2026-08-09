---
title: "fix: D10 A2 blob-completeness must verify index children per-child, not gunzip attestations"
type: fix
date: 2026-08-09
issue: 7378
closes: 7378
pr: 7379
branch: feat-one-shot-a2-attestation-validate
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: D10 A2 blob-completeness must verify index children per-child

## Overview

`registry-luks-recut` cannot authorize a recut. Its A2 predicate — the rehearsed restore, which
ADR-169 makes the gate's **pass condition** — fails on every run, so the dispatch is structurally
unfireable while the production registry crash-loops with a 100%-full store.

The cause is a validator false positive, not corruption. `scripts/registry-restore-from-ghcr.sh`
verification 2 (blob completeness) runs `crane validate --remote "$dst"` against the **whole
reference**. `soleur-web-platform` is a buildx OCI image index whose `manifests[1]` is an
attestation manifest carrying one layer of mediaType `application/vnd.in-toto+json` — plain JSON,
never gzipped. `crane validate` walks every index child and attempts to gunzip every layer, so it
fails with `validating layers: gzip: invalid header`. `classify()` has no matching case, so it
falls through to `*)` → `die 6` (could-not-classify).

The fix verifies the index **per child**: real platform children keep today's
`crane validate --remote`; attestation children are verified by **blob presence** without gunzip.
Coverage is preserved — this is not a skip.

## Premise Validation

| Premise | Check | Result |
|---|---|---|
| Issue 7378 open, is the work target | `gh issue view 7378` | OPEN — holds |
| PR 7379 open, draft | `gh pr view 7379` | OPEN, draft — holds |
| All cited paths exist | `test -f` ×5 | all present |
| `--insecure` valid on `manifest`/`blob` | `crane <sub> --help` | supported on all three subcommands |
| Failure is not zot corruption | `crane validate --remote <child-digest>` **at GHCR** | reproduced identically at the pristine source — validator false positive confirmed |
| `crane blob` reads in-toto layer without gunzip | `crane blob <repo>@<layer-digest>` | exit 0, emits the in-toto JSON — fix mechanism viable |
| `soleur-inngest-bootstrap` unaffected | `crane manifest …:v1.1.24` | no `.manifests` — single manifest, no attestations |
| ADR-169 is the governing decision | `ls decisions/` | `ADR-169-what-authorizes-destroying-the-sole-pull-path.md` — amend, do not mint a new ordinal |

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "Add a `manifest` call and the tests keep passing" | The crane stub's `emit()` **exits 70 on any ref without a fixture** — by design, no permissive defaults | Every case reaching verification 2 needs an OCI-manifest fixture. Measured blast radius: **4** cases set a `validate:` fixture in the restore suite, plus `ok_fixtures()`, plus the D10 suite's A2 section |
| "The test helper for manifests already exists" | `write_manifest()` writes the **restore-pins** manifest (`floor`/`entries`), not an OCI manifest | Name new helpers `fx_oci_manifest` / `fx_oci_index` to avoid the collision |
| "One suite covers this" | The D10 suite has its **own** `crane_stub` + `REGISTRY_GATE_CRANE_CMD`, and its A2 section drives the real engine via `REGISTRY_RESTORE_CRANE_CMD` | Both suites need fixtures |
| "Strip the tag with `${dst%:*}`" | The sink ref is `127.0.0.1:5999/jikig-ai/…:tag` — a naive strip breaks on the **port** colon when no tag is present | Repo derivation must only strip a colon that appears **after the last `/`** |

## Hypotheses

Not a network/SSH class change — the network-outage checklist does not apply. The single
hypothesis (validator false positive vs. real corruption) was **decided by measurement**, not
reasoning: the same child digest fails validation at GHCR, which the recut never touches. No
hypothesis remains open.

## Implementation Phases

Phase order is dependency-directed: the contract (`classify`) changes before its consumer.

### Phase 1 — RED: fixtures and failing tests

Add to `tests/scripts/test-registry-restore-from-ghcr.sh`:

- Stub arms for `manifest` and `blob`, keyed `manifest:<ref>` and `blob:<ref>`, both using the
  existing `emit()` (no permissive default — same discipline as `validate`). `blob` must assert
  it received a digest ref; `manifest` must assert `--insecure` was present for sink-directed
  calls, matching the existing sink-flag assertion.
- Helpers `fx_oci_index` (index JSON with an amd64 child + an attestation child) and
  `fx_oci_manifest` (single manifest, and an attestation manifest whose one layer is
  `application/vnd.in-toto+json`).
- Fixtures are **synthesized** — hand-written digests and sizes, never copied from a production
  artifact (`cq-test-fixtures-synthesized-only`).

Four new cases:

1. **Positive control (the production shape).** An index with an in-toto attestation child
   restores and verifies **green**. This is the case that is red today.
2. **Negative control — platform-layer blob missing.** `crane validate --remote` on the platform
   child returns `BLOB_UNKNOWN` → engine still exits **4**. Proves `BLOBMISSING` detection is not
   weakened.
3. **Attestation blob absent at the sink.** `crane blob` on the in-toto layer fails → engine
   exits **4**. Proves presence is *verified*, not skipped.
4. **Classification.** `gzip: invalid header` maps to the new named class, not to exit 6.

Update the 4 existing verification-2 cases and `ok_fixtures()` with single-manifest fixtures so
today's non-index behaviour is pinned unchanged.

### Phase 2 — GREEN (contract): `classify()`

Add a named arm for `gzip: invalid header` → new class `LAYERFORMAT`. Map it to **exit 4**, not 6:
after this fix the only way it can fire is a *platform* layer whose declared mediaType disagrees
with its bytes, which is a genuine verification failure ("do not deploy"). Exit 6 must stay
reserved for shapes the engine truly cannot name.

### Phase 3 — GREEN (consumer): per-child verification 2

Replace the single whole-ref `crane validate` with:

1. `crane manifest $SINK_TLS_FLAG "$dst"` at the **sink** (not GHCR — verification 2 exists to
   prove the *sink* holds the blobs). Classify read failures on the existing 3/5/4 arms.
2. If the payload has no `.manifests` → single manifest → `crane validate --remote "$dst"`
   exactly as today. **Non-index behaviour is unchanged.**
3. Otherwise, for each child:
   - **attestation child** — `.annotations["vnd.docker.reference.type"] == "attestation-manifest"`
     **or** `.platform.architecture == "unknown"`: read its manifest, then
     `crane blob <repo>@<digest> > /dev/null` for its config and every layer.
   - **platform child** — `crane validate --remote <repo>@<digest>`.
4. Repo derivation helper (see Reconciliation): strip `@digest`, then strip a trailing `:tag`
   **only** when the colon falls after the last `/`.

Detection is an **OR** deliberately: `platform.architecture == "unknown"` catches every buildx
attestation manifest (provenance and SBOM alike) even if the annotation shape changes.

### Phase 4 — Runbook + ADR

- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`: extend the exit-4
  row to name a layer-format mismatch; correct the exit-6 row (it is no longer reachable via
  attestation manifests); update the cold-vehicle section to record that the throwaway-zot
  rehearsal — one of the four surfaces ADR-169 flagged as never-executed — **has now executed
  live for the first time**, and what it found.
- Amend **ADR-169** (do not mint a new ordinal): record that A2's blob-completeness obligation is
  per-child, that attestation children are verified by presence rather than by decompression, and
  the near-miss below.

### Phase 5 — Verification

Both suites green; the A2 rehearsal exercised end-to-end through the D10 gate.

## The near-miss (record this, do not bury it)

The real restore runs the **same engine on the same code path**. Had A2 not existed, the recut
would have destroyed the store and only then hit this — leaving production with an empty store,
no pull path (the host→GHCR edge is dead), and an unclassified exit 6. Rehearse-before-destroy is
what caught it. This is evidence *for* ADR-169's independence criterion, and belongs in the ADR.

## User-Brand Impact

**If this lands broken, the user experiences:** either the status quo — every release keeps
failing at the `Mirror image GHCR→zot (crane)` step and no deploy can complete — or, if the fix
weakens verification instead of narrowing it, a recut that destroys the store and reports a green
restore over a **blob-incomplete** registry. The second is worse than the first: tag lookups
succeed for some refs and fail for others, so it presents as a confusing per-image outage, and
the fleet is one container restart away from a hard outage with nothing to pull from.

**If this leaks, the user's data is exposed via:** no new exposure surface. The change reads OCI
manifests and blob bytes already held by the sink; it adds no store, no credential, no network
egress beyond the calls the engine already makes.

**Brand-survival threshold:** single-user incident

## Observability

```yaml
liveness_signal:
  what: registry_pull_path_gate A2 verdict line (verdict=PASS|REFUSED predicate=A2)
  cadence: per registry-luks-recut dispatch
  alert_target: the dispatch fails closed; nothing is destroyed on a REFUSED verdict
  configured_in: .github/workflows/apply-web-platform-infra.yml (registry_pull_path_gate job)
error_reporting:
  destination: GitHub Actions ::error:: annotations from die(), surfaced in the job log and the run summary
  fail_loud: true — every arm exits non-zero with a named exit code; there is no silent-continue path
failure_modes:
  - mode: sink unreadable while enumerating index children
    detection: crane manifest failure classified NETWORK
    alert_route: exit 3 (retryable) — the restore job's own backoff
  - mode: sink rejects the credential mid-verification
    detection: classified DENIED
    alert_route: exit 5, non-retryable; runbook says measure htpasswd_push_matches before rotating
  - mode: platform layer blob missing
    detection: crane validate --remote on the platform child returns BLOB_UNKNOWN
    alert_route: exit 4 — do not deploy
  - mode: attestation layer blob absent at the sink
    detection: crane blob on the in-toto digest fails
    alert_route: exit 4 — do not deploy
  - mode: platform layer content disagrees with its declared mediaType
    detection: gzip: invalid header on a NON-attestation child
    alert_route: exit 4 via the new LAYERFORMAT class (previously exit 6, unclassified)
logs:
  where: GitHub Actions run log for the registry_pull_path_gate and registry_store_restore jobs
  retention: GitHub default (90 days)
discoverability_test:
  command: gh run view <run-id> --log-failed | grep -aE 'A2 ABORT|verdict='
  expected_output: a verdict line naming the predicate and, on abort, the classified exit code — no SSH
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-169** — *what authorizes destroying the sole pull path*. The decision itself
(a recut is authorized only when CI has just proven, by executing it, that the pull path can be
re-materialised) is unchanged. What is refined is what "blob-verified" means for a
**multi-manifest** image: per-child, with attestation children verified by blob presence rather
than decompression. Also record the near-miss above as evidence for the independence criterion.
No new ordinal — this refines an existing decision rather than making a new one.

### C4 views

**No C4 impact.** Checked against all three of `model.c4`, `views.c4`, `spec.c4` for: external
human actors (none added — this path is CI-only, no new correspondent or operator role); external
systems (GHCR and the zot registry are both already modeled, and the change adds no vendor);
containers/data stores (none added — the throwaway rehearsal registry is an ephemeral in-runner
process, not a persistent store, and the sink is the already-modeled registry); access
relationships (unchanged — same CI principal, same `packages: read`, same push credential, no
change to who may reach what).

### Sequencing

Ships in this PR. The ADR amendment describes behaviour this PR makes true, so there is no
`status: adopting` staging.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** assessed inline
**Assessment:** A correctness fix to the gate that authorizes an irreversible destroy of
production's sole pull path. The risk is not the bug being fixed but the fix over-correcting into
a skip: narrowing verification for attestation children must not become skipping them, which is
why the plan requires a negative control asserting an absent attestation blob still fails. Exit-4
(rather than 6) for the residual `LAYERFORMAT` case keeps the gate fail-closed. Scope is
deliberately bounded to the restore engine — the destroy-guard, stock preflight, zero-touch
assert and id-pin are untouched, and no allow-set widens.

Product domain is **NONE**: the mechanical UI-surface override does not fire — Files to Edit
contain no path under `components/`, `app/**/page.tsx`, or `app/**/layout.tsx`.

Agent spawn for domain leaders was withheld under this session's standing no-agent directive; the
sweep itself ran inline. Flagging it so the omission is visible rather than implied.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --limit 200` and matched each of the
three planned code paths against every open issue body — zero matches.

## Infrastructure (IaC)

Not applicable — no new server, service, secret, vendor, DNS record, or persistent runtime
process. The change is confined to a CI-invoked shell script and its test suites.

## Encryption Posture

Not applicable — no persistent store and no new cross-component connection is introduced. The
engine speaks to the same sink over the same already-declared transport.

## GDPR / Compliance

Not applicable — no regulated-data surface. No schema, migration, auth flow, API route, or `.sql`
file is touched; no personal data is read, written, or transmitted. None of the four expansion
triggers fire (no LLM/external-API processing of operator data, no new cron reading learnings, no
new artifact-distribution surface).

## Files to Edit

- `scripts/registry-restore-from-ghcr.sh` — `classify()` new arm; verification 2 per-child rewrite; repo-derivation helper.
- `tests/scripts/test-registry-restore-from-ghcr.sh` — `manifest`/`blob` stub arms, `fx_oci_index`/`fx_oci_manifest`, 4 new cases, 4 existing cases + `ok_fixtures()` updated.
- `tests/scripts/test-registry-pull-path-health.sh` — A2 fixtures for the index shape.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — exit-code table + cold-vehicle section.
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` — amendment.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash tests/scripts/test-registry-restore-from-ghcr.sh` passes with **≥ 47** tests and 0 failures (43 today + ≥4 new).
2. `bash tests/scripts/test-registry-pull-path-health.sh` passes with **≥ 60** tests and 0 failures.
3. The positive-control case — an OCI index with an in-toto attestation child — **passes**, and fails if the per-child branch is reverted (verified by temporarily restoring the whole-ref `crane validate`).
4. The platform-layer-blob-missing case exits **4** (not 6, not 0).
5. The attestation-blob-absent case exits **4** — presence is verified, never skipped.
6. `classify "…gzip: invalid header"` returns the new named class; the engine maps it to exit **4**.
7. Single-manifest (non-index) refs take the unchanged code path, asserted against the stub's `$CALLS` log rather than by reading the suite: for the non-index case the log contains **exactly one** `validate` line for that ref and **zero** `blob` lines. (A "grep the suite for a case that asserts…" AC would be vacuous — it tests that a test exists, not that the behaviour holds.)
8. `bash scripts/test-all.sh` green (full suite), or, if scoped, the registry-suite subset green plus a named record of which commit the last full run covered.
9. No diff outside the five files in **Files to Edit**: `git diff --name-only origin/main...HEAD` returns exactly that set (plus the plan/spec artifacts).
10. The recut's other gates are untouched: `git diff origin/main...HEAD -- tests/scripts/lib/registry-luks-recut-gate.sh tests/scripts/lib/stock-preflight-gate.sh .github/workflows/apply-web-platform-infra.yml` is **empty**.
11. Every `knowledge-base/` path cited in this plan resolves: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'` prints nothing.

### Post-merge (operator)

12. Re-fire `registry-luks-recut` with the same confirm token and the id-pin re-derived at fire time. **Automation:** in-session — the dispatch is a `gh workflow run` call, executed by the agent, not handed to the operator.

## Test Scenarios

1. **Production shape restores green.** Index + amd64 child + in-toto attestation child, all blobs present at the sink → exit 0.
2. **Platform blob missing.** Same index, platform child returns `BLOB_UNKNOWN` → exit 4, message names blob-incompleteness.
3. **Attestation blob missing.** Same index, `crane blob` on the in-toto layer fails → exit 4.
4. **Non-index unchanged.** Single manifest, no `.manifests` → one `crane validate --remote <ref>` call, exit 0.
5. **Sink unreachable mid-enumeration.** `crane manifest` fails with a network shape → exit 3 (retryable).
6. **Residual layer-format mismatch.** A non-attestation child emits `gzip: invalid header` → exit 4 via `LAYERFORMAT`, never exit 6.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The fix over-corrects into skipping attestation children, silently allowing a blob-incomplete store | Test Scenario 3 is the guard: an absent attestation blob **must** still exit 4. Presence is verified, not assumed |
| A future attestation shape is not detected and gets exit 4 spuriously, blocking a recut | Detection is an OR on `platform.architecture == "unknown"`, which is shape-stable across buildx provenance and SBOM manifests, not only on the annotation |
| Adding a `crane manifest` call breaks existing tests via the no-fixture arm (exit 70) | Measured: 4 cases + `ok_fixtures()` + the D10 A2 section. All enumerated in Files to Edit rather than discovered at `/work` |
| Repo derivation mangles the sink's `host:port` | Helper strips a trailing `:tag` only when the colon falls after the last `/`; covered by a unit case |
| Extra CI wall-clock from per-child calls | Cost-neutral: today's whole-ref `crane validate` already downloads the platform layers. Per-child issues the same downloads plus one cheap manifest GET and a 140 KB attestation blob |
| Exit 4 is non-retryable, so a mis-mapped transient becomes a hard stop | Network and credential shapes are classified **before** the `LAYERFORMAT` arm is reached, preserving the 3/5 retry semantics |
