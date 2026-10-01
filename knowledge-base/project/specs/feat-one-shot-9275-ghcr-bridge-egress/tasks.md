# Tasks: deny GHCR and docker.pkg.github.com from bridge containers (#9275)

Plan: `knowledge-base/project/plans/2026-10-01-infra-deny-ghcr-from-bridge-containers-plan.md`.
Hard constraint: `apps/web-platform/infra/cloud-init-registry.yml` stays byte-identical (AC1). Stop and
ask the operator if any design change would touch it.

## Phase 1: Failing tests (RED)

- 1.1 Extend `apps/web-platform/infra/test-fixtures/github-meta-sample.json` with a `.packages` key
  (two holes in one allow prefix, one hole equal to an exact `.git` `/32`, one hole outside every allow
  prefix, one `/31`)
- 1.2 `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh`: python3 `ipaddress` oracle,
  golden body, `Excluded` header lines, no carved IP admitted, deterministic no-op, `--check` parity
  - 1.2.1 Guard rows: `.packages` absent, not an array, zero effective holes (WARN, exit 0)
  - 1.2.2 DNS-sanity rows with a `getent` shim first on `PATH` (answer in a hole dies; lookup failure warns)
  - 1.2.3 Instrument floor on IPs checked; must-PASS row with a hole outside every prefix
- 1.3 `apps/web-platform/infra/cron-egress-firewall.test.sh`
  - 1.3.1 Replace the `140.82.112.0/20` literal assertion with a containment assertion over the committed file
  - 1.3.2 Assert the `# Excluded` header and the resolver's probe functions, two ops and `GHCR_PROBE_PORT_` constants at both the curl flag and the sampler
  - 1.3.3 Census checks: sandbox domain list equals exactly github.com + api.github.com, allowlist names no GHCR / pkg.github.com / githubusercontent host, bounded server-tree grep with a files-scanned floor
- 1.4 Probe table test: source `ghcr_probe_verdict` / `ghcr_probe_blind_step` by `awk` extraction; rows for held, hung-resolver, reached, DNS 6, blind at 12, reset on held, reset on reached; stub state dir, clock and `sentry_event`
- 1.5 `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts` (sibling of `sentry-image-verify-alert-op-contract.test.ts`): ops match the rule filter; message literals static

## Phase 2: Generator (GREEN)

- 2.1 `carve_one` / `exclude_holes` in `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` (bash + jq only)
- 2.2 `.packages` extraction, exact-overlap subtraction, header lines, shape guard, DNS-sanity guard (`ghcr-carve-would-cut-github`)
- 2.3 Regenerate `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` with the generator against live `/meta`; `--check` exits 0
- 2.4 Confirm the cron's TS test needs no `.packages` fixture (generator spawn is mocked)

## Phase 3: Probe and sampler (`cron-egress-resolve.sh`)

- 3.1 `GHCR_PROBE_PORT_LO/HI`, `ghcr_probe_verdict`, `ghcr_probe_blind_step`, `run_ghcr_probe` (stamp-file cadence >= 270 s, sequential names, static event messages, extra diagnostics)
- 3.2 Sampler filter for `BLOCK_HITS` / `SAMPLE`: drop a line only when SPT in range and DPT 443 and DST inside an excluded prefix
- 3.3 Avoid `nft ... | grep -q` under `pipefail`; run the shell lint ratchets and add reviewed baseline rows only if needed

## Phase 4: Apply-time assertion

- 4.1 `cron-egress-postapply-assert.sh`: header present, `nft get element` fails for every excluded address (both of a `/31`), one live pinned probe when the container runs
- 4.2 Add the new assertion names to the self-reporting sentinels in `cron-egress-firewall.test.sh`

## Phase 5: Sentry routing

- 5.1 `apps/web-platform/infra/sentry/issue-alerts.tf`: widen `egress_blocked` op filter to `egress_blocked,ghcr_deny_lost,ghcr_deny_probe_blind`; extend the comment; do not rename the resource
- 5.2 Regenerate `alert-reference.json` from the `sentry-alert-reference-expected-<run>` CI artifact

## Phase 6: Decision record and runbook

- 6.1 ADR-096 amendment "2026-10-01 (#9275)" and the top-summary bullet
- 6.2 Read `model.c4`, `views.c4`, `spec.c4`; edit only a falsified statement
- 6.3 Runbook `cron-egress-blocked.md`: GHCR carve section, decode rows, repair ladder keyed by event `extra`, replace the `comm -23` recipe with `--check`

## Phase 7: Tracking and ship

- 7.1 File three follow-up issues (hosts-file docker.pkg.github.com at next registry replace; Better Stack `ghcr_blocked=0` alert; `enforcement_missing` investigation) with `Mandated-By` lines and a milestone
- 7.2 PR body: `Closes #9275`, "cloud-init-registry.yml: no change", the two deviations from `decision-challenges.md`
- 7.3 CI only; ask the operator again before an admin merge of this non-docs diff
