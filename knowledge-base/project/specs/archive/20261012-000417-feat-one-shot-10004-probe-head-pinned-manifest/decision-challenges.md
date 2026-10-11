# Decision challenges — feat-one-shot-10004-probe-head-pinned-manifest

Headless planning run (one-shot). Each entry departs from, or narrows, the operator's stated direction; the stated direction is the default and the entry is surfaced for `ship` to render into the PR body.

## DC-1 (User-Challenge) — the web image has no committed pin, so "both repositories" narrows to one

- **Operator direction:** "HEAD the pinned manifest (the ZIREF tag/digest pins the hosts actually pull, for both jikig-ai/soleur-web-platform and jikig-ai/soleur-inngest-bootstrap)".
- **Finding:** `ZIREF` exists only for `jikig-ai/soleur-inngest-bootstrap` (`cloud-init.yml`, `cloud-init-inngest.yml`). The web image has no committed pin: `var.image_name` defaults to `ghcr.io/jikig-ai/soleur-web-platform:latest` and the digest a web host birth pulls is resolved at dispatch time (`PINNED=...` in `apply-web-platform-infra.yml`) and never committed; `ci-deploy.sh` keeps no deployed-ref state on the host.
- **Plan response:** the bootstrap repository is pinned and HEADed; the web element stays a bare repository and its marker row reports `pin_verdict=none` explicitly, so the gap is visible in telemetry. Deferred as #10044 with re-evaluation criteria.
- **Alternatives considered:** derive the web ref on the host (`docker inspect` of the running container) — adds a docker dependency and a container-absent branch (a silent-skip shape) to a probe whose absence is the alarm.
- **Reversible by:** a follow-up that supplies a committed or host-persisted web ref.

## DC-2 (Taste) — HEAD timeout stays at the single request site's `-m 10`

- **CTO suggestion:** bound the manifest HEAD at `-m 5`.
- **Not applied:** one request function with one timeout keeps the curl text the suite's mutants key on; the 50 s worst case on web-1 is under the 60 s timer interval, so no tick is skipped.

## DC-3 (Taste) — all-must-pass from day one for the pin check

- **Suggestion (first-pass CTO, earlier plan family):** a report-only first window for a new check.
- **Not applied:** the operator direction is that an evicted pin turns the heartbeat red; the first real run is the proof (AC19), read from telemetry.

## DC-4 (Taste) — no distinct `pin-forbidden` verdict

- **CTO suggestion:** give a manifest-endpoint 403 its own verdict (`pin-forbidden`).
- **Not applied (plan-review simplicity seat):** a 403 suppresses the ping either way and the fault line carries the code, so the extra verdict adds a classification arm, a test row and a mutation row without changing any outcome. The pin verdict reuses the existing classification vocabulary. Reversible by adding the arm later.

## DC-5 (User-Challenge) — host-side probe versus a CI-layer manifest check

- **Operator direction:** the issue and brief name the web-1 host probe as the place for the check.
- **Challenge (plan-review DHH seat):** retention only evicts when a new `v*` tag is pushed, and pushes happen in `build-inngest-bootstrap-image.yml`, which already has the tunnel bridge, crane and zot credentials; a `crane manifest <repo>@<ZIREF digest>` step there plus a scheduled re-check would remove the probe parser, the `web-probe.tf` regex, the `server.tf` edit, the per-bump web-1 delivery and the cattle pin-rot analysis.
- **Plan response:** the stated direction stays the default. The CI check cannot see GC, a restore, or an `accessControl` regression between builds, nor what the HOST's pull credential can read over the private NIC (the whole point of the consumer probe). It is a possible additive follow-up, not a replacement.
- **Reversible by:** adding the CI step later; the probe check does not preclude it.
