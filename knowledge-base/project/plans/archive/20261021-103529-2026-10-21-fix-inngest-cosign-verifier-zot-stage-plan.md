---
title: "fix: stage the cosign verifier image on zot for the inngest config-refresh channel (#10390 defect 2)"
type: fix
date: 2026-10-21
slug: fix-inngest-cosign-verifier-zot-stage
branch: feat-one-shot-10390-cosign-zot-stage
issue: 10390
lane: cross-domain
domain: engineering/infra
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: stage the cosign verifier image on zot for the inngest config-refresh channel (#10390 defect 2)

## Enhancement Summary

**Deepened on:** 2026-10-21
**Sections enhanced:** Observability (probe corrected), Post-Merge Operations, Guard Contract (verified via `scripts/lint-guard-contract.py`), Scope Check (verified via unfenced-count + row checks)
**Research agents used:** none — Task/Agent spawn unavailable in this harness; all prescribed fan-outs (repo research, learnings, functional/community overlap, domain leaders, spec-flow, advisor consult, per-section deepen agents, verify-the-negative + self-audit passes) were performed inline by the planning orchestrator.

### Key Improvements

1. `discoverability_test.command` rewritten to a single `grep -c` probe — the original `bash -c '… && … && echo STAGED'` form carried `&`, which preflight Check 10's shell-active reject (`no | ; & < > $`, plan-sharp-edges catalogue) would refuse at ship time.
2. All halt gates run mechanically: `lint-guard-contract.py` (2 guard entries, green), unfenced `## Scope Check` count = 1 with no `unmapped` rows and a `Recommendation:` line, PAT-shaped-variable sweep clean, `hcloud_server.inngest` confirmed `ignore_changes = [ssh_keys]` only (user_data force-replace is real), no `provisioner "file"/"remote-exec"`/`connection` blocks in `inngest-host.tf` (network-outage resource-shape trigger does not fire; Overview/Problem trigger-word scan = 0).
3. Live-verified citations: #10390/#10713/#10136/#9060/#10243 OPEN states, fix SHAs `930b8b271b`/`0057ec24605` ancestors of origin/main, `wg-architecture-decision-is-a-plan-deliverable` confirmed in `scripts/migrated-rule-ids.txt` (migrated, still active), full 64-hex cosign digest identical across workflow/test/cloud-init pins.
4. `user_data` cap measured live: 680 B headroom (`inngest-userdata-budget.sh`) — constrains Phase 2 code-line additions; comment lines confirmed stripped by `local.inngest_rationale_strip`.

### New Considerations Discovered

- The brief's option A (`docker tag` → gcr ref) is unimplementable — `docker tag` rejects digest references and no RepoTag satisfies a `name@sha256:` run-ref; recorded as a `pending - assumed:` technical ruling.
- The brief's option B (`REFRESH_COSIGN_IMAGE` env injection) is inert in production — the #7761 seam gate unsets `REFRESH_*` absent `--fixture-seams`; the override is fixture-only. The default must change, not the env.
- `reason=signature` today is a *misattribution* (implicit pull inside `docker run`), so the fix adds `member=cosign-image` reason granularity — a verifier-fetch miss now reads `reason=pull`, never `signature`.

## Overview

The dedicated Inngest host rejects every promoted config bundle with
`SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature`: the refresh consumer runs the
offline verifier inside
`docker run --network none gcr.io/projectsigstore/cosign@sha256:57c0e93a…`, and
the daemon-side implicit image pull needs public egress the deny-all-public host
does not have. The cosign verifier image is the last un-mirrored registry read on
a host whose documented invariant is "zot is the ONLY registry read" (ADR-135,
2026-10-13 amendment). This plan mirrors the pinned cosign image into the private
zot during the bundle producer's existing `zot_mirror` step, repoints the host's
`COSIGN_IMAGE` default at the zot ref, and pins the new copy in both test suites
so the staging cannot silently regress.

This is the third latent first-use defect of the #10390 drain: v1 died at
`docker create` on a command-less scratch image (fixed by the `CMD ["true"]`
merge, sha `0057ec24605`); v2 reached the verify arm for the first time and died
on the verifier image pull. The verify path has never run to APPLIED on this
host — the fix must be proven by a live `SOLEUR_INFRA_PULL_APPLIED` row, not by
suite green alone.

## Problem Statement / Motivation

Host currently emits, every ~5-minute refresh tick:

```
SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature offered=31a917ed4852 rejver=none
```

`reason=signature` is **misattributed**: the `docker run … "$COSIGN_IMAGE"
verify-blob …` at cloud-init-inngest.yml ~line 2061 performs an implicit
daemon-side image pull before the container starts, and the comment above the
call ("the daemon-side implicit pull of the cosign image is unaffected by it" —
correct about `--network none`, but the pull needs *registry* egress) never
accounted for the host being deny-all-public. `docker run` exits non-zero on the
pull failure, the script reads it as a verify failure, and `verify_fail
signature` fires. The channel is fail-closed and safe — the host applies
nothing — but the pull-based config-refresh channel (ADR-135) is dead until the
verifier image is reachable.

Root cause is PROVEN and matches two in-repo invariants:

1. ADR-135 / `inngest-config-refresh.sh` header: "the private zot (the ONLY
   registry read on this host — #8036 deleted the GHCR credential)". A gcr.io
   pull contradicts that claim; the claim is right and the code is wrong.
2. ADR-096 amendment 2026-09-28 (#8714) moved the **web** hosts' verifier pull
   to `gcr.io/projectsigstore/cosign@sha256:57c0e93a…` — the same digest —
   because web hosts have public egress. The inngest host inherited the gcr ref
   when ADR-135 landed its consumer, without inheriting the egress that makes
   gcr reachable.

## Research Insights

**Premise Validation (Phase 0.6).** Every claim in the brief was checked against
`origin/main` (worktree synced, 0 behind): issue #10390 is OPEN (epic); fix SHAs
`930b8b271b` and `0057ec24605` are `merge-base --is-ancestor` of origin/main;
`.github/workflows/build-inngest-config-bundle.yml` `zot_mirror` step exists at
line 147–193 with crane install + retry + `degraded()` machinery;
`cloud-init-inngest.yml` has `COSIGN_IMAGE` at line 1848 with the gcr default,
the bootstrap zot pull at 1315–1344, `[ "$n_inngest" -lt 5 ]` at 1175, and the
DEC-FLOOR note at ~1157; `MIN_ASSERTIONS=90` in
`plugins/soleur/test/inngest-config-bundle-mirror.test.sh:721`, `MIN_ASSERTIONS=98`
in `apps/web-platform/infra/inngest-config-refresh.test.sh:531`,
`INNGEST_HOST_MIN_ASSERTIONS=183`; `inngest-config-refresh-set.txt` has the five
dedicated-host members; `scripts/betterstack-query.sh` exists;
`apply-web-platform-infra.yml` has `apply_target: inngest-host-replace`
(workflow line ~1899) with required `reason` input; #10136 (private-net
in-transit exceptions) and #9060 (promotion route follow-up) are OPEN; #10713
(normalizeRepoUrl flake) is OPEN. **Two brief mechanisms do not survive contact
with the code — see Research Reconciliation.**

**Property List (Phase 0.6b).**

1. The host's `docker run "$COSIGN_IMAGE"` must resolve without public egress.
2. The pinned verifier image must be present on the private zot so the zot ref
   can resolve (supply side).
3. The mirror copy and the host-side repoint must be guard-pinned so neither can
   silently revert (the defect class is a latent, never-exercised path).
4. A verifier-image pull miss must emit a distinguishable reason — not
   `reason=signature`, which misattributes a fetch failure to provenance.

**Cut List (Phase 0.6b).**

- *Provision-time pre-pull + `docker tag` to the gcr ref (brief option A)* —
  buys property 1, but the mechanism is unimplementable: `docker tag` rejects
  digest references (`invalid reference format`), and RepoDigests are created
  only by pulls/pushes through that ref, so no tag can ever satisfy
  `docker run gcr.io/…@sha256:D` locally. The pull half alone leaves
  `COSIGN_IMAGE` pointed at gcr — nothing is fixed. See Reconciliation.
- *`REFRESH_COSIGN_IMAGE` env injection in production (brief option B, literal
  read)* — buys property 1, but is inert by design: the #7761 seam gate
  (`cloud-init-inngest.yml` ~line 1821) unsets every `REFRESH_*` name when
  argv[1] is not `--fixture-seams` and emits `SOLEUR_INFRA_PULL_SEAM_REFUSED`.
  The env override exists **only** as a fixture seam for the test harness.
- *A second `zot_cosign_mirror` step in the workflow* — buys property 2, but
  duplicates the crane install, retry and degraded machinery the `zot_mirror`
  step already carries; a second leg inside the same step is the minimal shape
  (the 2026-10-16 second-leg learning's wiring pins apply either way).
- *Provision-time stage pull even without the tag (best-effort warm)* — buys
  "first tick is instant", a sub-property the explicit tick-side pull already
  covers; a second pull site doubles the pinned surface for ≤60 s of earlier
  signal. Cut; revisit only if first-tick pull latency ever matters.

**Key file paths.** Producer mirror step:
`.github/workflows/build-inngest-config-bundle.yml:147-193` (insert the cosign
leg after the bundle digest check at :192, before `mirror_status=ok` at :193).
Consumer: `apps/web-platform/infra/cloud-init-inngest.yml` — `COSIGN_IMAGE`
default at :1848; `ZOT_EP` resolved at :2003-2008; `BREF` at :2009; bundle pull
at :2030; `docker run` verify at :2061. Guards:
`plugins/soleur/test/inngest-config-bundle-mirror.test.sh` (struct.py leg,
crane stub, arm runner, mutation battery, floor :721);
`apps/web-platform/infra/inngest-config-refresh.test.sh` (S9 pins :239-262,
fixture seams :264-361, F-rows, floor :531).

**Institutional learnings that bind.**

- `2026-10-16-a-second-leg-in-a-shared-job-must-prewrite-its-outputs-…`: a second
  leg in a shared step needs wiring pins (not just body pins) and must not
  suppress the owner leg on exits the owner owns — the cosign copy goes AFTER
  the bundle copy so a cosign failure can never starve the bundle copy, and a
  bridge_down degrade still precedes both.
- `2026-09-28-a-stale-but-signed-image-…`: authenticity ≠ freshness — the
  cosign `crane digest` equality check against the literal pinned digest is the
  freshness/identity pin, not optional polish.
- `2026-07-07-cloud-init-user-data-cap-…` + `inngest-userdata-budget.sh`:
  rendered user_data is at **32,088 B of 32,768 B (680 B headroom, measured
  today)** — the plan's cloud-init code additions are capped accordingly;
  whole-comment lines are stripped by `local.inngest_rationale_strip` so
  rationale prose is free.
- `2026-05-12-pgid-inheritance-and-bash-trap-defer-…` (PR #3704): the bootstrap
  pull's `timeout 180 docker pull … &` + `wait` shape already handles the
  TERM-defer trap; the refresh tick pull uses the simpler foreground
  `timeout "$PULL_TIMEOUT_S" docker pull` form the same script already uses.
- `2026-05-16-sha-pin-prefix-match-false-positive-…`: every digest literal in
  this plan/test pins is the full 64-hex `57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870`
  — pins assert the full literal, not a prefix.

**Conventions.** Mirror-step degrade contract: `degraded <reason> <rc> "<detail>"`
emits `mirror_status=degraded` + `mirror_reason=<reason>` + `::warning::` +
summary line, exits 0 (the step stays `continue-on-error: true` until the
SOLEUR-DEBT note's consumer-readiness flip). Refresh-script emit contract:
`verify_fail <reason> [<rejver>] ["<detail>"]` → `reason=<r> offered=<12hex>
rejver=<n|none> [<detail>]`. Fixture seams: `REFRESH_*` names honored only under
`--fixture-seams`; prod unsets them.

**External research decision (Phase 1.6): skipped.** Root cause is proven, every
mechanism is repo-internal (crane copy + bash default + test pins), and the
binding constraints are local ADRs. Community/functional overlap: none — this is
repo-internal infra plumbing with no community-artifact equivalent (agents not
spawnable in this harness; assessed inline).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "docker pull $ZOT_EP/jikig-ai/cosign@sha256:… && docker tag → gcr ref" makes `docker run gcr.io/…@sha256:…` resolve locally | `docker tag` cannot target a digest reference; a `name@sha256:D` run-ref resolves only via RepoDigests created by a pull/push *through that ref* — unreachable under deny-all-public. Tagging to `gcr.io/…/cosign:v3.1.1` also misses: a tag does not satisfy a `@sha256` ref. | The gcr ref cannot be kept on the run path. Repoint `COSIGN_IMAGE`'s default to the zot ref (same digest = same integrity pin) and stage it with an explicit `docker pull` in the tick. |
| "set REFRESH_COSIGN_IMAGE to the zot ref (env override exists)" | `REFRESH_COSIGN_IMAGE` is honored ONLY under `--fixture-seams`; the #7761 gate unsets it in prod and emits SEAM_REFUSED (~line 1821-1838). Injecting it via the unit's Environment is a live-looking dead wire. | Keep `REFRESH_COSIGN_IMAGE` as the fixture-seam override; change the **default** it falls back to — `${ZOT_EP}/jikig-ai/cosign@sha256:…`, resolved after `ZOT_EP` is read from `/etc/default/soleur-zot-read`. |
| Mirror dst `127.0.0.1:5000/jikig-ai/cosign@sha256:57c0e93a…` | The existing step pushes the bundle to a **tag** (`:v${VERSION}`) and the host pulls it **by digest** — zot serves any stored manifest by digest. A digest-form dst works too but the tag form matches the step's own convention and adds a `crane digest` equality check the digest form cannot express. | Copy to `127.0.0.1:5000/jikig-ai/cosign:v3.1.1`, then `crane digest` the dst and require equality with the pinned gcr digest — digest-preserved is *verified*, not asserted. |

## Proposed Solution

Four parts, one PR:

1. **Producer: mirror the verifier image in `zot_mirror`.** Inside the existing
   step's run body, after the bundle `digest_mismatch` check and before
   `mirror_status=ok`: `retry timeout 180 crane copy
   gcr.io/projectsigstore/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870
   127.0.0.1:5000/jikig-ai/cosign:v3.1.1` routed `|| degraded cosign_copy "$?"
   "…"`, then `timeout 60 crane digest` on the dst with the same shape-check +
   equality-to-pinned-digest pattern the bundle copy uses (`degraded
   cosign_digest_lookup` / `cosign_digest_mismatch`). Ordering is deliberate:
   the bundle copy stays first (a cosign failure can never starve it), and the
   bridge_down gate still precedes both legs.
2. **Consumer: repoint `COSIGN_IMAGE`'s default to zot and stage explicitly.**
   In the embedded `inngest-config-refresh.sh`: line 1848 becomes
   `COSIGN_IMAGE="${REFRESH_COSIGN_IMAGE:-}"` (seam read stays with its
   siblings); immediately after `BREF=…` (~line 2009, where `ZOT_EP` is
   validated non-empty) add
   `COSIGN_IMAGE="${COSIGN_IMAGE:-${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870}"`;
   immediately after the bundle `docker pull` (~line 2030, inside the same
   login window) add `timeout "$PULL_TIMEOUT_S" "$DOCKER_BIN" pull
   "$COSIGN_IMAGE" >/dev/null 2>&1 || verify_fail pull "" "member=cosign-image"`.
   The `docker run` verify call itself is untouched — `--network none` stays
   correct, now true end-to-end because the image is already local.
3. **Pins.** Mirror suite: new `EXPECT_COSIGN_SRC`/`EXPECT_COSIGN_DST` constants
   carrying the full pinned digest; crane stub `copy` arm counts per-dst and
   refuses unknown argv; `digest` arm answers `EXPECT_COSIGN_DST` with
   `STUB_COSIGN_ZOT_DIGEST` (default = the real pinned digest); ok/copyflaky
   arms assert the cosign copy line + bounded digest lookup; a new
   `cosigncopyfail` arm (dst-scoped fail knob) proves `degraded cosign_copy`
   fires at rc with zero cosign copies after three attempts; structural leg
   gains ~4 verdicts (cosign copy line, dst repo, `degraded cosign_copy` route,
   digest equality arm); new mutants `cosign-copy-dropped` and
   `cosign-digest-check-dropped`; floor 90 → measured green (~100). Refresh
   suite: structural pins for `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…` in
   `$SC` and for the explicit `pull "$COSIGN_IMAGE"` line; a fixture arm that
   runs with `--fixture-seams` but WITHOUT `REFRESH_COSIGN_IMAGE` and asserts
   `docker pull`/`docker run` both carry
   `zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` (the repoint proven
   end-to-end); a `FX_FAIL_COSIGN_PULL` arm (stub differentiates pull argv
   containing `cosign`) asserting `reason=pull` + `member=cosign-image`; floor
   98 → measured green (~104).
4. **Docs-of-record.** Runbook `inngest-config-refresh.md` gains the
   `reason=pull member=cosign-image` failure-mode row and the note that
   pre-fix `reason=signature` could mean "verifier image unfetchable";
   ADR-135 gains a short addendum recording defect-2 and that the "zot is the
   ONLY registry read" claim became literally true only with this change;
   `model.c4`'s `hetzner -> zotRegistry` pull-edge description gains
   `jikig-ai/cosign` among served repos for the inngest host (the
   `hetzner -> sigstore` edge stays — it is already scoped to web deploy
   pulls; verified there is no separate inngest→gcr edge to remove).

## Technical Considerations

- **Digest as the integrity anchor is unchanged.** Same 64-hex digest on both
  registries; the digest pin — not the registry host — is the trust anchor
  (ADR-096's own wording for the sigstore edge).
- **Multi-arch safety.** `crane copy` copies the whole index/manifest
  byte-for-byte; `--platform` would re-write and change the digest. The
  `crane digest` equality check proves this property at every run.
- **Ordering vs. the replace window.** The `zot_mirror` leg only runs when a
  bundle is built — so `gh workflow run … -f version=3` is what lands the
  cosign image on zot. The host replace must come AFTER that run's mirror
  leg succeeds, or the fresh host's first tick hits the same wall (now as
  `reason=pull member=cosign-image`, self-healing next tick).
- **user_data cap.** Code-line additions to cloud-init are ~3; comment lines
  are stripped by `local.inngest_rationale_strip`. Verify with
  `bash apps/web-platform/infra/inngest-userdata-budget.sh` post-edit
  (headroom was 680 B on 2026-10-21).
- **Attack surface (supply chain).** What can a malicious/stale zot object do?
  The host only ever pulls `@sha256:` refs — a swapped manifest fails docker's
  digest check at pull; a stale-but-valid cosign image is a *verifier*, not
  executed code on the payload, and its output gate is the bundle's own
  signature + per-member sha + monotonic VERSION. The `crane digest`
  equality check on the producer side catches a tag/digest split at publish
  time. No new credential: the zot pull user/token is the existing
  `/etc/default/soleur-zot-read`.
- **Reason granularity.** `verify_fail pull "" "member=cosign-image"` keeps
  `offered=`/`rejver=` semantics intact while distinguishing
  verifier-fetch failures from bundle-fetch and provenance failures — the
  exact misattribution that hid this defect.
- **Fixture-seam parity preserved.** Under `--fixture-seams`,
  `REFRESH_COSIGN_IMAGE=fixture/cosign` still wins (the late default only
  fills an empty value); in prod the seam gate unsets it and the zot default
  applies — both arms pinned.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole Inngest scheduler
  host fails to boot/provision (if a cloud-init defect is introduced) or the
  config-refresh channel stays fail-closed forever — either way the single
  operator's automation backbone is dark.
- **If this leaks, the user's data is exposed via:** no data exposure vector —
  the cosign image is public upstream content, the digest pin is public, and
  no new credential is introduced (the existing zot pull credential is reused).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the touched surface is the sole
  scheduler host's provenance channel; a boot-bricking edit or a provenance
  regression darkens the platform's automation for its only user — one bad
  merge IS the incident.

## Infrastructure (IaC)

### Terraform changes

None — no `.tf` edits. `cloud-init-inngest.yml` is consumed through
`inngest-host.tf`'s `templatefile` (`hcloud_server.inngest`, line ~469), so the
cloud-init edit is itself the IaC change; delivery is the existing gated
`apply-web-platform-infra.yml -f apply_target=inngest-host-replace` dispatch
(hcloud_server.inngest has **no** `ignore_changes=[user_data]` — a user_data
edit force-replaces the host; that is the sanctioned delivery mechanism, not an
accident).

### Apply path

(b) `terraform apply -replace` equivalent — the `inngest-host-replace`
workflow_dispatch job (separately gated, `reason` required). Preconditions: the
v3 bundle run's mirror leg must have succeeded first (cosign must exist on zot
before the fresh host's first tick needs it).

### Host fan-out

Single serving host (`hcloud_server.inngest`) — the `terraform_data` SSH
provisioner sibling map does not apply (no new provisioner).

### Distinctness / drift safeguards

The inngest host is prd-only (no dev twin — the dark arm64 host reads
`--config prd` exclusively per `inngest-config-digest.tf` header). No
`lifecycle.ignore_changes` interplay: the host does not ignore `user_data`, so
the drift is a deliberate, dispatch-gated replace. Secret values: none enter
state — the change carries refs, not credentials.

### Vendor-tier reality check

n/a — no new vendor resource.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INFRA_PULL_* markers (APPLIED/VERIFY_FAIL/NOOP/FLOOR) emitted by the 60s refresh tick via journald + inngest-boot-phone-home.sh dual channel; provision stages inngest_zot / inngest_pull_fatal per boot"
  cadence: "60s (refresh timer); per provision attempt"
  alert_target: "Better Stack (inngest-config-drift comparator + phone-home rows); Sentry at fatal for provision pull fatals"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (inngest-config-refresh.sh emit()/verify_fail(); soleur-inngest-provision phone-home stages)"
error_reporting:
  destination: "journald -t inngest-config-refresh + Better Stack phone-home detail field; Sentry fatal channel via soleur-boot-emit for provision fatals"
  fail_loud: "SOLEUR_INFRA_PULL_VERIFY_FAIL reason=<pull|signature|extract|…> offered=<12hex> rejver=<n|none>; new detail member=cosign-image distinguishes verifier-image misses from bundle-fetch and provenance failures"
failure_modes:
  - mode: "cosign image absent on zot (mirror gap or pre-v3 replace)"
    detection: "VERIFY_FAIL reason=pull member=cosign-image every tick — self-heals on the tick after the v3 mirror lands"
    alert_route: "Better Stack phone-home rows + drift comparator DIVERGED"
  - mode: "mirror step silently drops the cosign copy"
    detection: "plugins/soleur/test/inngest-config-bundle-mirror.test.sh structural + behavioural pins and the cosign-* mutants (red before merge)"
    alert_route: "required CI gate on the PR"
  - mode: "COSIGN_IMAGE default reverts to gcr or resolves before ZOT_EP"
    detection: "apps/web-platform/infra/inngest-config-refresh.test.sh structural pins + the no-seam fixture arm asserting the zot.internal:5000 ref in the docker run/pull argv"
    alert_route: "required CI gate on the PR"
logs:
  where: "journald tag inngest-config-refresh on-host; Better Stack phone-home detail off-box; GHA run log for the mirror step"
  retention: "host journald retention; Better Stack plan retention; GHA run logs 90d"
discoverability_test:
  command: grep -c 'jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' apps/web-platform/infra/cloud-init-inngest.yml
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "zot registry store (existing — not created or modified by this change)"
    mechanism: luks
    evidence: "apps/web-platform/infra/zot-registry.tf (LUKS cutover #6894, PR #8248 merged)"
    defends_against: "raw volume snapshot / seized-disk disclosure of mirrored image bytes"
    does_not_defend: "a tampered manifest served live — integrity is the @sha256 digest pin + cosign verify, not disk encryption; nor a live unlocked host"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — hcloud volume API under the Tier-B cred recipe"
in_transit:
  - connection: "inngest host docker daemon -> zot registry (private subnet :5000) — pull of jikig-ai/cosign@sha256:57c0e93a…"
    enforced_at: "apps/web-platform/infra/cloud-init-inngest.yml — inngest-config-refresh.sh COSIGN_IMAGE + docker pull (same connection class as the existing bundle pull)"
    tls: "none — plain HTTP on the private subnet"
    cert_verification: off
    does_not_defend: "on-path observation/modification of image bytes in flight — mitigated by the @sha256 digest the daemon verifies on pull, and the bundle's offline cosign verify-blob for payload provenance"
    disclosed_as: "ADR-096 / ADR-135 private-net posture; tracked exception"
exception:
  justification: "private-subnet pull where the @sha256 digest pin — not TLS — is the integrity control, identical to the bundle pull the same script already makes"
  tracking_issue: "#10136"
  reevaluate_when: "private-net TLS termination reaches the zot registry, or the pull plane leaves the private subnet"
  expires_on: "2027-01-19"
```

## Guard Contract

### Guard 1 — mirror suite cosign staging pin (plugins/soleur/test/inngest-config-bundle-mirror.test.sh)

**Property.** Every `build-inngest-config-bundle.yml` run whose bundle copy
succeeds also mirrors the pinned cosign verifier image to
`127.0.0.1:5000/jikig-ai/cosign:v3.1.1` and proves the zot digest equals the
pinned gcr digest — loudly (`degraded cosign_*`), never silently.

**Assembly.** The `zot_mirror` step's `run:` body in
`.github/workflows/build-inngest-config-bundle.yml` is the single chokepoint
every CI→zot image copy flows through (structural leg asserts the step is
found exactly once by name); the cosign leg is the code region between the
bundle digest check and `mirror_status=ok`. The suite's structural
(pin-presence), behavioural (stubbed argv validation + per-dst copy counts)
and mutation legs all quantify over that one extracted body.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the cosign `crane copy` line from the step body | RED — structural leg: cosign copy line check fails |
| 2 | Retarget the cosign dst repo to `jikig-ai/cosign-tools` | RED — structural leg (dst literal) + ok-arm argv assertion |
| 3 | Drop `|| degraded cosign_copy …` off the cosign copy | RED — `cosigncopyfail` arm: failure exits non-degrade |
| 4 | Drop the cosign digest equality check | RED — `cosign-digest-check-dropped` mutant |
| 5 | Suite-harness: crane stub stops counting the cosign dst | RED — ok arm asserts cosign copies == 1 |
| 6 | Must-PASS: reword comments around the cosign block, same commands | PASS — the guard binds argv/commands, not prose |
| 7 | Own-dispatch: extractor run under a nonexistent step name | RED — empty extraction is already a named BAD (`found exactly once`) |

**Anchor.** The pinned digest literal lives in the workflow src, the zot dst
check, the suite's `EXPECT_COSIGN_SRC` and the cloud-init default — a weakening
must move all four in one diff, and the producer's own `crane digest` run-time
check re-verifies the pin against live registry bytes on every publish.

### Guard 2 — refresh suite verifier-ref pin (apps/web-platform/infra/inngest-config-refresh.test.sh)

**Property.** In production the refresh tick runs `docker pull`/`docker run`
against `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…` — never a public-registry
ref — and a verifier-image pull miss reports `reason=pull member=cosign-image`.

**Assembly.** The embedded `inngest-config-refresh.sh` inside
`cloud-init-inngest.yml` is the single write_files entry the suite extracts to
`$WORK/refresh.sh` — the `COSIGN_IMAGE` default expression, the explicit pull
line, and the `docker run` verify call are the three sites the property
quantifies over; the seam gate is the (separate) chokepoint that would let an
env override masquerade as production config and must stay refusing.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the `COSIGN_IMAGE` default to the gcr ref | RED — structural zot-ref pin + no-seam fixture arm |
| 2 | Drop the explicit `docker pull "$COSIGN_IMAGE"` line | RED — structural pull-line pin; F-row asserting the pull argv |
| 3 | Resolve `COSIGN_IMAGE`'s default before `ZOT_EP` is read | RED — no-seam fixture arm asserts the `zot.internal:5000` prefix in argv (an early resolution yields `/jikig-ai/…`) |
| 4 | Delete `member=cosign-image` from the verify_fail detail | RED — F-row greps markers.log for `member=cosign-image` |
| 5 | Suite-harness: docker stub stops logging `pull` calls | RED — F-row asserting `docker pull <zot ref>` sees zero |
| 6 | Must-PASS: `REFRESH_COSIGN_IMAGE=fixture/cosign` under `--fixture-seams` | PASS — seam override still honored in fixture mode |
| 7 | Must-REFUSE (prod): `REFRESH_COSIGN_IMAGE` set without `--fixture-seams` | PASS-if-refused — seam gate unsets it and the zot default applies |

**Anchor.** The pinned digest literal is shared with the workflow + mirror
suite constants (Guard 1's anchor applies); the zot endpoint is runtime-resolved
from `/etc/default/soleur-zot-read`, so no registry host is hardcoded twice.

## Downtime & Cutover

**Offline-inducing operation:** `apply-web-platform-infra.yml -f
apply_target=inngest-host-replace` — `hcloud_server.inngest` carries no
`ignore_changes=[user_data]`, so the cloud-init edit force-replaces the sole
scheduler host. Scheduler downtime ≈ one replace window (minutes).

**Zero-downtime evaluation:** blue-green (a second Inngest host to drain onto)
is the #6178 HA item — deferred epic scope, not available as a same-window
mechanism; rolling is N/A (singleton); a `terraform state mv` does not apply
(the change is user_data content, not addressing); expand-contract N/A. The
replace IS the arc's sanctioned delivery — this is the third inngest-host
replace of the drain (run 39400431311 after key rotation; the v2 promotion
itself rode the same mechanism).

**Residual downtime justification:** bounded maintenance window — the dispatch
is itself the operator-authorization point; the scheduler is already the arc's
replace target and the refresh channel is currently dead (nothing regresses
below status quo). Rollback: re-dispatch the replace at the prior image/vars
(the old cloud-init is the previous templatefile render) — the channel stays
fail-closed either way.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md`
with a short addendum (implementation task, not a follow-up issue): defect-2 —
the verifier image was the one registry read the "zot is the ONLY registry
read" claim missed (inherited from the web-hosts' gcr pull, ADR-096
amendment/#8714, which is correct *for hosts with public egress*); the image
now mirrors to zot in the producer's `zot_mirror` step and the host default is
a zot ref. No new ADR — this closes a code-vs-ADR divergence, it does not make
a new architectural decision.

### C4 views

Read of `model.c4` / `views.c4` / `spec.c4` at plan time: `hetzner ->
zotRegistry` (model.c4 ~line 774) gains `jikig-ai/cosign` in its served-repo
description for the inngest config-refresh channel; `hetzner -> sigstore`
(~line 786) is already scoped to the web deploy path and needs only a scoping
clarification that the inngest host's verifier pull no longer uses it (external
systems checked: sigstore/gcr, zot registry — both modeled; actors checked: no
new human actors; relationships changed: inngest-host→gcr pull moves to the
existing inngest-host→zot relationship — no new element or edge, so no
`views.c4` include edit; `spec.c4` has zero cosign mentions). Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the
edit.

### Sequencing

Both doc-of-record edits ride this PR — the divergence is corrected atomically
with the code that makes the claim true.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (inline — Task subagent spawn unavailable in this harness)
**Assessment:** Infra fix on the ADR-135 channel; the load-bearing technical
forks (mechanism for the host-side fix; mirror dst form; fatal-vs-nonfatal
staging) are analyzed in Research Reconciliation and recorded as
`pending - assumed:` rulings in
`knowledge-base/project/specs/feat-one-shot-10390-cosign-zot-stage/decision-challenges.md`
for CTO confirmation. Product/UX: no UI-surface files → tier NONE (mechanical
override does not fire). Legal/Compliance: GDPR gate dispositioned inline —
the change processes no personal data (public image bytes + infra credentials
under the existing isolation model); no Art. 9 surface, no new processing
activity, no cross-controller movement (internalizes a public pull). Marketing/
Sales/Finance/Support/Operations: not implicated.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "crane cp gcr.io/projectsigstore/cosign@sha256:57c0e93a… → 127.0.0.1:5000/jikig-ai/cosign@sha256:57c0e93a… (digest-preserved; crane/bridge machinery already there)" [brief FIX 1] | Proposed Solution 1; Files-to-Edit `.github/workflows/build-inngest-config-bundle.yml` | mapped |
| 2 | "docker pull $ZOT_EP/jikig-ai/cosign@sha256:57c0e93a… && docker tag → gcr ref, OR set REFRESH_COSIGN_IMAGE to the zot ref" [brief FIX 2] | Proposed Solution 2 (reconciled form); Files-to-Edit `apps/web-platform/infra/cloud-init-inngest.yml` | mapped |
| 3 | "Pins: inngest-config-bundle-mirror.test.sh (new crane copy pin + mutant, bump floor 90→92+) + inngest-config-refresh.test.sh" [brief FIX 3] | Proposed Solution 3; test file edits | mapped |
| 4 | "Merge → gh workflow run build-inngest-config-bundle.yml -f version=3 → approve pending_deployments env 18613770186 (-f comment REQUIRED) → EITHER keep v2 pointer … or promote v3 … → gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace … → next tick: verify betterstack SOLEUR_INFRA_PULL_APPLIED" [brief FIX 4] | Post-Merge Operations phase | mapped |
| 5 | "floor 5→6: cloud-init-inngest.yml `[ \"$n_inngest\" -lt 5 ]` → -lt 6 + inngest-host.test.sh matching pin" [brief, marked NOT this PR's scope] | — | descoped — justification: brief itself bounds it to a post-merge follow-up; tracked in Follow-Ups |
| 6 | "postmerge checks for the two merged fix PRs … Remaining backlog: #9927 items 2+4, #8620 ruling, #7596" [brief, marked NOT this PR's scope] | — | descoped — justification: brief itself bounds them out; tracked in Follow-Ups |
| 7 | "the plan should rule it via the CTO spawn or record `pending - assumed:` if you cannot spawn agents" [brief, technical-ruling note] | decision-challenges.md rows (this branch's spec dir) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `.github/workflows/build-inngest-config-bundle.yml` cosign copy leg | "crane cp gcr.io/projectsigstore/cosign@sha256:57c0e93a… → 127.0.0.1:5000/jikig-ai/cosign@sha256:57c0e93a…" | asked |
| `apps/web-platform/infra/cloud-init-inngest.yml` COSIGN_IMAGE repoint + explicit pull | "docker pull $ZOT_EP/jikig-ai/cosign@sha256:57c0e93a… && docker tag → gcr ref, OR set REFRESH_COSIGN_IMAGE to the zot ref" | asked (reconciled mechanism — see Research Reconciliation) |
| `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` pins/mutants/floor | "new crane copy pin + mutant, bump floor 90→92+" | asked |
| `apps/web-platform/infra/inngest-config-refresh.test.sh` pins/arms/floor | "inngest-config-refresh.test.sh if the env/pull lines are pinned there" | asked |
| `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` failure-mode row | — | inferred — justification: the runbook's failure-modes table is wrong without `reason=pull member=cosign-image`; docs-of-record must not misdescribe the reason space the plan introduces |
| `knowledge-base/engineering/architecture/decisions/ADR-135-*.md` addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the addendum records the corrected divergence in the same change, never a deferred issue |
| `knowledge-base/engineering/architecture/diagrams/model.c4` edge description | — | inferred — justification: C4 completeness mandate — a host→registry relationship changed (inngest→zot now carries the verifier image); the recorded model must not lag the change |
| Post-Merge Operations phase (bundle run v3, env approval, host-replace dispatch, betterstack verify) | "Merge → gh workflow run … → approve pending_deployments env 18613770186 … → EITHER keep v2 pointer … or promote v3 … → apply_target=inngest-host-replace … → verify betterstack SOLEUR_INFRA_PULL_APPLIED" | asked |
| `knowledge-base/project/specs/feat-one-shot-10390-cosign-zot-stage/decision-challenges.md` | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | asked |

### Split Assessment

- Subsystems touched: 4 — `.github`, `apps/web-platform`, `plugins/soleur`, `knowledge-base`
- Planned files: 7 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — nominal trigger fires on root count alone, **overridden**: the docs and test files are the pins and records of THIS fix — splitting them off ships either a red pin or an undocumented mechanism, and the code diff is ~15 functional lines; a split would add rebase risk without a meaningful review boundary (single PR).

## Files to Edit

- `.github/workflows/build-inngest-config-bundle.yml` — cosign copy leg inside `zot_mirror`
- `apps/web-platform/infra/cloud-init-inngest.yml` — `COSIGN_IMAGE` two-step default + explicit `docker pull`
- `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` — constants, stub argv/count arms, new arms + mutants + structural pins, floor
- `apps/web-platform/infra/inngest-config-refresh.test.sh` — structural pins + new F-arms + floor
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` — failure-mode row + reason-misattribution note
- `knowledge-base/engineering/architecture/decisions/ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md` — defect-2 addendum
- `knowledge-base/engineering/architecture/diagrams/model.c4` — zot pull-edge description (`jikig-ai/cosign` served to inngest host)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10390-cosign-zot-stage/tasks.md` (Save Tasks)
- `knowledge-base/project/specs/feat-one-shot-10390-cosign-zot-stage/decision-challenges.md` (ruling rows)

## Implementation Phases

### Phase 1 — Producer mirror leg

1. Edit `zot_mirror` run body: add `COSIGN_SRC`/`COSIGN_DST` constants carrying
   the full pinned digest; `retry timeout 180 crane copy "$COSIGN_SRC"
   "$COSIGN_DST" || degraded cosign_copy "$?" "…"`; `timeout 60 crane digest
   "$COSIGN_DST"` shape-check + `==` pinned digest, routed to
   `degraded cosign_digest_lookup` / `degraded cosign_digest_mismatch`.
   Placement: after the bundle `digest_mismatch` check, before
   `mirror_status=ok`.
2. Extend the mirror suite: `EXPECT_COSIGN_SRC`, `EXPECT_COSIGN_DST`,
   `COSIGN_PIN_DIGEST` constants; crane stub `copy` arm counts per-dst +
   refuses unknown src/dst; `digest` arm answers the cosign dst with
   `STUB_COSIGN_ZOT_DIGEST` (default = pinned digest); ok arm asserts
   `crane copy <src> <dst>` + `timeout 60 crane digest <dst>` exactly once
   each and cosign copies == 1; new `cosigncopyfail` arm +
   `STUB_CRANE_COSIGN_COPY_FAIL_N` knob asserting `degraded cosign_copy` with
   the measured rc and 3 attempts; structural leg adds the four verdicts;
   mutate.py adds `cosign-copy-dropped` + `cosign-digest-check-dropped` rows;
   floor 90 → measured green (~100).
3. Run `bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh` — green
   at the new floor.

### Phase 2 — Consumer repoint + explicit stage

1. In the embedded `inngest-config-refresh.sh`: line 1848 →
   `COSIGN_IMAGE="${REFRESH_COSIGN_IMAGE:-}"`; after `BREF=` (~line 2009) →
   `COSIGN_IMAGE="${COSIGN_IMAGE:-${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870}"`;
   after the bundle pull (~line 2030) → `timeout "$PULL_TIMEOUT_S"
   "$DOCKER_BIN" pull "$COSIGN_IMAGE" >/dev/null 2>&1 || verify_fail pull ""
   "member=cosign-image"`. Comments explaining the gcr-unreachability are free
   (stripped by `local.inngest_rationale_strip`) — add the defect note.
2. Extend the refresh suite: structural pins (`${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…`
   in `$SC`; explicit pull line present); new F-arm — run with
   `--fixture-seams`, all seam envs EXCEPT `REFRESH_COSIGN_IMAGE`, assert
   `docker pull zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` precedes
   `docker run … zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` in
   calls.log; new F-arm — docker stub `pull` arm fails argv containing
   `cosign` under `FX_FAIL_COSIGN_PULL`, assert `reason=pull` +
   `member=cosign-image`, rc=1, nothing installed; floor 98 → measured green.
3. Run `bash apps/web-platform/infra/inngest-config-refresh.test.sh` — green
   at the new floor.
4. Run `bash apps/web-platform/infra/inngest-userdata-budget.sh` — headroom
   still > 0.

### Phase 3 — Docs of record

1. Runbook `inngest-config-refresh.md`: add `reason=pull member=cosign-image`
   to the failure-modes table + a note that pre-fix `reason=signature` masked
   "verifier image unfetchable" (now distinguishable).
2. ADR-135 addendum: defect-2 record (one short section).
3. `model.c4` `hetzner -> zotRegistry` edge description: add `jikig-ai/cosign`
   to served repos for the inngest host; scoping line on `hetzner ->
   sigstore` (web deploy path only). Run
   `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 4 — Post-Merge Operations (operator-gated, prod-mutating)

Sequenced, each step's gate named:

1. Merge the PR (pipeline review path).
2. `gh workflow run build-inngest-config-bundle.yml -f version=3` — the run's
   `zot_mirror` leg is what lands `jikig-ai/cosign` on zot.
3. Approve the `inngest-config-signing` pending deployment (env id
   18613770186, `-f comment` REQUIRED) — production-mutating authorization,
   operator window.
4. Pointer choice: keep v2 (recommended — the pointer already names the
   promoted v2 digest; the host applies it once the verifier resolves) or
   promote v3 via the same `doppler_secret.inngest_config_digest` targeted
   apply recipe (operator window).
5. `gh workflow run apply-web-platform-infra.yml -f
   apply_target=inngest-host-replace -f reason='inngest arc: stage cosign
   verifier image via zot (#10390)'` — AFTER step 2's mirror leg confirmed.
   Run conclusion cannot confirm it: `zot_mirror` degrades with `exit 0`, so a
   `cosign_copy`/`cosign_digest_*` failure still concludes `success`. The
   confirmation check is the step's own output — e.g.
   `gh run view <run-id> --log | grep -c 'mirror_status=ok'` plus absence of
   `reason=cosign_` warnings (or `gh api repos/{owner}/{repo}/actions/runs/<id>/jobs --jq '.jobs[] | select(.name | contains("zot")) | .conclusion'` — assert the mirror output line `mirror_status=ok`, not merely the run's conclusion).
6. Verify (no host login): `doppler run -p soleur -c prd_terraform --
   scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_PULL --limit 12`
   — expect `SOLEUR_INFRA_PULL_APPLIED version=<N> sha256=<digest> verify=ok`
   within the tick window.

## Acceptance Criteria

- [ ] AC1: `bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh` exits 0 with `MIN_ASSERTIONS` raised to the measured green count (~100) and the new cosign arms/mutants present.
- [ ] AC2: `bash apps/web-platform/infra/inngest-config-refresh.test.sh` exits 0 with `MIN_ASSERTIONS` raised to the measured green count (~104) and the new F-arms present.
- [ ] AC3: `grep -qF 'crane copy "gcr.io/projectsigstore/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870"' .github/workflows/build-inngest-config-bundle.yml` — producer mirror carries the full-digest source literal.
- [ ] AC4: `grep -qF 'jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' apps/web-platform/infra/cloud-init-inngest.yml && grep -qF 'pull "$COSIGN_IMAGE"' apps/web-platform/infra/cloud-init-inngest.yml` — consumer default is the zot ref and the explicit stage pull exists.
- [ ] AC5: `bash apps/web-platform/infra/inngest-userdata-budget.sh` reports `headroom` > 0 after the cloud-init edit (the 32,768 B cap gate stays green).
- [ ] AC6: Mirror-suite mutant `cosign-copy-dropped` produces a BAD verdict carrying the cosign check label (the pin can be driven red).
- [ ] AC7: The no-seam fixture arm asserts `zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` in BOTH the `docker pull` and `docker run` argv of calls.log.
- [ ] AC8: `python3 scripts/lint-guard-contract.py` on this plan exits 0.
- [ ] AC9: runbook + ADR-135 + model.c4 edits committed in the same PR; `bun test` on `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] AC10 (post-merge, operator window): `SOLEUR_INFRA_PULL_APPLIED version=<N> sha256=<digest> verify=ok` observed via `scripts/betterstack-query.sh` after the replace — the end-to-end proof no suite can fake.

## Test Scenarios

- Given the canonical workflow, when the mirror step runs under stubs, then exactly one cosign `crane copy` to `jikig-ai/cosign:v3.1.1` and one bounded `crane digest` on it execute after the bundle copy (`unit` — suite arm).
- Given `STUB_CRANE_COSIGN_COPY_FAIL_N=99 rc=42`, when the step runs, then `degraded cosign_copy` fires rc=42 after 3 attempts and `mirror_status=ok` never emits (`unit` — cosigncopyfail arm).
- Given `STUB_COSIGN_ZOT_DIGEST=<other>`, when the step runs, then `degraded cosign_digest_mismatch` fires (`unit` — new arm reusing the digestbad shape).
- Given a refresh run with `--fixture-seams` and no `REFRESH_COSIGN_IMAGE`, when the tick proceeds past the pointer check, then `docker pull zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` and `docker run … zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a…` appear in that order (`unit` — F-arm).
- Given `FX_FAIL_COSIGN_PULL=1`, when the tick runs, then rc=1, `reason=pull`, `member=cosign-image`, nothing installed (`unit` — F-arm).
- Given `REFRESH_COSIGN_IMAGE` set WITHOUT `--fixture-seams`, when the tick runs, then the seam gate unsets it, `SOLEUR_INFRA_PULL_SEAM_REFUSED` is recorded, and the zot default is used (`unit` — extends F9 shape).
- Given the mutants `cosign-copy-dropped` / `cosign-digest-check-dropped`, when evaluated, then the named checks report BAD (`unit` — mutation battery).
- Given the post-merge sequence completes, when the next refresh tick fires, then Better Stack carries `SOLEUR_INFRA_PULL_APPLIED` (`e2e`, pyramid-justified: the defect is a latent live-host path suites cannot reach — the APPLIED row is the only honest oracle).

## Open Code-Review Overlap

One open `code-review` issue mentions a file in scope: #10243 ("nft comment
correction on PR 8945", `cloud-init-inngest.yml`) — a closed-review record with
0 findings, not an open scope-out. Disposition: **acknowledge** — no rework
item to fold; remains open as a record (not this plan's concern).

## Follow-Ups (explicitly out of this PR's scope)

- Floor 5→6: `[ "$n_inngest" -lt 5 ]` → `-lt 6` (cloud-init ~line 1175) +
  `inngest-host.test.sh` matching pins (DEC-FLOOR note ~line 1157;
  `INNGEST_CONFIG_DIGEST` exists in soleur-inngest/prd since the v2 promotion,
  so the bump is now safe) — separate change per the brief.
- Postmerge checks for the two merged fix PRs (`930b8b271b`, `0057ec24605`).
- Backlog: #9927 items 2+4, #8620 ruling, #7596; #10713 flake.
- Promotion-route automation remains #9060.

## Non-Goals

- No change to the signing path, trusted root, identity regexp, or bundle
  membership (`inngest-config-refresh-set.txt` — the cosign image is the
  verifier and can never ride the bundle per HARD-1).
- No new credential, secret, or Doppler write in this PR.
- No provision-time pre-pull (cut — see Cut List); the tick's explicit pull is
  the staging site.
- No `hetzner -> sigstore` edge removal — web deploy pulls still use it.
- No floor-5→6 bump, no host-script refresh-set member changes.

## Alternatives Considered

| Option | Verdict |
|---|---|
| Provision pull + `docker tag` to the gcr digest ref (brief A, literal) | **Impossible** — `docker tag` rejects digest targets; RepoDigests only arise from pulls through that ref. See Reconciliation. |
| `REFRESH_COSIGN_IMAGE` via unit Environment (brief B, literal) | **Inert in prod** — #7761 seam gate unsets all `REFRESH_*` absent `--fixture-seams`; emits SEAM_REFUSED. |
| Repoint `COSIGN_IMAGE` default to zot ref + explicit tick pull (chosen) | Minimal code (~3 lines), preserves the digest pin and the seam contract, self-heals every tick, correct reason granularity. |
| Provision-time best-effort stage pull | Cut by mechanism-minimality — the tick pull covers staging; revisit only if first-tick latency matters. |
| Separate `zot_cosign_mirror` workflow step | Cut — duplicates crane install/retry/degraded; in-step second leg is minimal and already wired. |
| Mirror to digest-form dst `…/cosign@sha256:…` | Works but loses the `crane digest` equality check the tag form enables; tag `:v3.1.1` matches the step's own convention and the host pulls by digest regardless. |
| Keep v2 pointer vs promote v3 post-merge | Either reaches APPLIED; recommend keep-v2 (fewer prod writes; v2 already promoted) — operator's call at the window. |

## Context

Tier-B cred recipe for the operator window (proven): `TF_STATE_AWS_*` /
`HCLOUD_TOKEN` / `CF_API_TOKEN_R2` / `DOPPLER_TOKEN_TF` / `GITHUB_INFRA_APP_*`
from `doppler secrets get X -p soleur-infra-privileged -c prd --plain`; `AWS_*`
env = `TF_STATE_AWS_*` (Tier-A `AWS_*` in prd_terraform is READ-ONLY by
ADR-241); local terraform via `mise exec -- terraform` (1.10.5; system 1.9.8 is
below the backend floor); run under `doppler run --preserve-env -p soleur -c
prd_terraform --name-transformer tf-var`; Doppler writes take the value on
stdin (`--silent`), never argv; per-command go-ahead for each prod write.

Spec lacks `lane:` — no spec.md exists for this branch; defaulted to
cross-domain (TR2 fail-closed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — filled above.
- `docker tag` cannot produce a `name@digest` ref — do not re-introduce the
  tag-based mechanism at implementation time; the repoint is the only shape
  that works.
- Keep comment lines generous (they're stripped from user_data) but keep added
  CODE lines minimal — 680 B headroom measured 2026-10-21.
- The cosign copy MUST come after the bundle copy in the step body — a cosign
  failure may never starve the bundle leg.
- Stage names emitted by provision/refresh must not begin with `inngest_zot`
  (Better Stack substring counts) — the new pull uses the refresh script's own
  `reason=pull` channel, no new stage name needed.
- Pipeline harness note: no Task/Agent spawn exists in this environment — all
  prescribed subagent fan-outs were performed inline; technical forks are
  recorded `pending - assumed:` in `decision-challenges.md`.

## References

- Epic: #10390 (open); merged fixes `930b8b271b` (cosign v3 `--bundle` +
  producer pin), `0057ec24605` (OCI CMD fix); flake tracker #10713.
- ADRs: ADR-135 (pull channel, 2026-10-13 amendment), ADR-096 (zot; amendment
  2026-09-28 / #8714 moved the WEB verifier pull to gcr), ADR-087 (cosign
  verify host), #7761 (fixture-seam gate), #8036 (GHCR credential deleted).
- Runbook: `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`.
- Guards: `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`,
  `apps/web-platform/infra/inngest-config-refresh.test.sh`,
  `apps/web-platform/infra/inngest-host.test.sh` (floor 183 — untouched here),
  `apps/web-platform/infra/inngest-userdata-budget.sh`.
