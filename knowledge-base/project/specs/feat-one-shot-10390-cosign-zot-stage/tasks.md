# Tasks — feat-one-shot-10390-cosign-zot-stage

Plan: `knowledge-base/project/plans/2026-10-21-fix-inngest-cosign-verifier-zot-stage-plan.md`
Issue: #10390 (epic — defect 2). Lane: cross-domain (defaulted; no spec.md).

## 1. Producer mirror leg (build-inngest-config-bundle.yml)

- [ ] 1.1 In `zot_mirror` run body, after the bundle `digest_mismatch` check and
      before `echo "mirror_status=ok"`, add `COSIGN_SRC`/`COSIGN_DST` constants
      (full 64-hex digest; dst `127.0.0.1:5000/jikig-ai/cosign:v3.1.1`), the
      `retry timeout 180 crane copy "$COSIGN_SRC" "$COSIGN_DST" || degraded
      cosign_copy "$?" "…"` leg, and the `timeout 60 crane digest "$COSIGN_DST"`
      shape-check + pinned-equality check routed to
      `degraded cosign_digest_lookup` / `degraded cosign_digest_mismatch`.
- [ ] 1.2 Extend `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`:
      `EXPECT_COSIGN_SRC`/`EXPECT_COSIGN_DST`/`COSIGN_PIN_DIGEST` constants;
      crane stub `copy` arm counts per-dst and refuses unknown src/dst;
      `digest` arm answers cosign dst with `STUB_COSIGN_ZOT_DIGEST` (default =
      pinned digest); ok/copyflaky arms assert cosign copy + digest lines and
      counts; new `cosigncopyfail` arm with dst-scoped
      `STUB_CRANE_COSIGN_COPY_FAIL_N` knob.
- [ ] 1.3 Structural leg verdicts: cosign copy line present, dst literal
      `jikig-ai/cosign:v3.1.1`, `degraded cosign_copy` route, cosign digest
      equality arm.
- [ ] 1.4 mutate.py: `cosign-copy-dropped` and `cosign-digest-check-dropped`
      mutants + ROWS entries asserting named-BAD labels.
- [ ] 1.5 Bump `MIN_ASSERTIONS` 90 → measured green count (~100);
      `bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh` green.

## 2. Consumer repoint + explicit stage (cloud-init-inngest.yml)

- [ ] 2.1 `COSIGN_IMAGE="$${REFRESH_COSIGN_IMAGE:-}"` at ~line 1848 (seam read
      stays with siblings).
- [ ] 2.2 After `BREF=` (~line 2009, ZOT_EP validated non-empty):
      `COSIGN_IMAGE="$${COSIGN_IMAGE:-$${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870}"`.
- [ ] 2.3 After the bundle pull (~line 2030):
      `timeout "$PULL_TIMEOUT_S" "$DOCKER_BIN" pull "$COSIGN_IMAGE" >/dev/null 2>&1 || verify_fail pull "" "member=cosign-image"`.
- [ ] 2.4 Rationale comments on all three edits (free — stripped by
      `local.inngest_rationale_strip`); keep code-line additions minimal.

## 3. Refresh suite pins (inngest-config-refresh.test.sh)

- [ ] 3.1 Structural pins: `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…` in `$SC`;
      explicit `pull "$COSIGN_IMAGE"` line present.
- [ ] 3.2 F-arm: run `--fixture-seams` WITHOUT `REFRESH_COSIGN_IMAGE`; assert
      `docker pull zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` precedes
      `docker run … zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` in
      calls.log.
- [ ] 3.3 F-arm: `FX_FAIL_COSIGN_PULL=1` (docker stub `pull` arm fails argv
      containing `cosign`) → rc=1, `reason=pull`, `member=cosign-image`, zero
      installed.
- [ ] 3.4 Bump `MIN_ASSERTIONS` 98 → measured green count (~104);
      `bash apps/web-platform/infra/inngest-config-refresh.test.sh` green.
- [ ] 3.5 `bash apps/web-platform/infra/inngest-userdata-budget.sh` — headroom > 0.

## 4. Docs of record

- [ ] 4.1 Runbook `inngest-config-refresh.md`: `reason=pull member=cosign-image`
      row + note that pre-fix `reason=signature` masked verifier-image misses.
- [ ] 4.2 ADR-135 addendum: defect-2 record (verifier image now mirrored; "zot
      is the ONLY registry read" literally true).
- [ ] 4.3 `model.c4`: `jikig-ai/cosign` into the `hetzner -> zotRegistry`
      pull-edge description; scope line on `hetzner -> sigstore` (web deploy
      only); run `bun test` c4-code-syntax + c4-render suites.

## 5. Post-Merge Operations (operator-gated — NOT work-skill scope)

- [ ] 5.1 Merge PR → `gh workflow run build-inngest-config-bundle.yml -f version=3`.
- [ ] 5.2 Approve `inngest-config-signing` pending deployment (env 18613770186,
      `-f comment` required) — operator window.
- [ ] 5.3 Pointer: keep v2 (recommended) or promote v3 via
      `doppler_secret.inngest_config_digest` targeted apply.
- [ ] 5.4 `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='inngest arc: stage cosign verifier image via zot (#10390)'` — AFTER 5.2's mirror confirmed.
- [ ] 5.5 Verify `SOLEUR_INFRA_PULL_APPLIED` via
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_PULL --limit 12`.

## 6. Follow-ups (separate changes — do not implement here)

- [ ] 6.1 Floor 5→6 (`-lt 5` → `-lt 6` + inngest-host.test.sh pin) — digest
      secret now exists; safe per DEC-FLOOR.
- [ ] 6.2 Postmerge checks for `930b8b271b` + `0057ec24605`; backlog #9927
      items 2+4, #8620, #7596, #10713.
