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
  - 1.2.1 Guard rows: `.packages` absent, not an array, zero effective holes (dies `ghcr-carve-no-effective-holes`; changed from WARN/exit 0 at the 2026-10-01 review)
  - 1.2.2 DNS-sanity rows with a `getent` shim first on `PATH` (answer in a hole dies; lookup failure warns)
  - 1.2.3 Instrument floor on IPs checked; must-PASS row with a hole outside every prefix
  - 1.2.4 Hostile `.packages` rows (a `/8` or `/0` hole, more than 64 holes, nested holes, leading-zero octet) and add `.packages` to the existing inline-JSON `assert_reject` cases
- 1.3 `apps/web-platform/infra/cron-egress-firewall.test.sh`
  - 1.3.1 Replace the `140.82.112.0/20` literal assertion with a containment assertion over the committed file
  - 1.3.2 Assert the `# Excluded` header and the resolver's probe functions, two ops and `GHCR_PROBE_PORT_` constants at both the curl flag and the sampler
  - 1.3.3 Census checks: sandbox domain list equals exactly github.com + api.github.com, allowlist names no GHCR / pkg.github.com / githubusercontent host, bounded server-tree grep with a files-scanned floor
- 1.4 Probe table test: source `ghcr_probe_verdict` / `ghcr_probe_blind_step` by `awk` extraction; rows for held, hung-resolver, reached, DNS 6, blind at 12 (inconclusive and container-absent), reset on held, reset on reached, hostile output (`time_connect='a[$(touch pwned)]'`, 10 kB line, non-IPv4 `remote_ip`); stub state dir, clock and `sentry_event`
- 1.5 `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts` (sibling of `sentry-image-verify-alert-op-contract.test.ts`): ops match the rule filter; message literals static; the four `ASSERT-FAILED` names and `ghcr-carve-would-cut-github` match the runbook decode rows

## Phase 2: Generator (GREEN)

- 2.1 `carve_one` / `exclude_holes` in `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` (bash + jq only)
- 2.2 `.packages` extraction, exact-overlap subtraction under `LC_ALL=C`, `(.web // [])`, header lines `# Excluded (GitHub Packages frontends): <cidr>` (pattern documented once in the generator header), shape guard, hole guards (skip holes shorter than `/28` with a WARN; die above 64 effective holes or 2048 output lines), DNS-sanity guard (`ghcr-carve-would-cut-github`), `10#` arithmetic
- 2.3 Regenerate `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` with the generator against live `/meta`; `--check` exits 0
- 2.4 Confirm the cron's TS test needs no `.packages` fixture (generator spawn is mocked)

## Phase 3: Probe and sampler (`cron-egress-resolve.sh`)

- 3.1 `GHCR_PROBE_PORT_LO/HI`, `ghcr_probe_verdict`, `ghcr_probe_blind_step`, `run_ghcr_probe` (stamp-file cadence >= 270 s, sequential names, `rc=0; out=$(...) || rc=$?`, skip when `$SECONDS` > 60, `curl -q --noproxy '*'`, untrusted-output validation and `awk -v` float compare, static event messages, extra diagnostics, counted container-absent skips)
- 3.2 Sampler filter for `BLOCK_HITS` / `SAMPLE`: drop a line only when SPT in range and DPT 443 and DST inside an excluded prefix; header CIDRs re-validated (`/28` or longer), suppress nothing on any parse problem
- 3.3 Avoid `nft ... | grep -q` under `pipefail`; run the shell lint ratchets and add reviewed baseline rows only if needed

## Phase 4: Apply-time assertion

- 4.1 `cron-egress-postapply-assert.sh`: header present, positive control (set exists, first allow prefix found), `nft get element` fails for every excluded address (both of a `/31`), one live pinned probe when the container runs; single-line guarded commands between `chmod +x` and `echo host-egress-ok`
- 4.2 Add the new assertion names to the self-reporting sentinels in `cron-egress-firewall.test.sh`

## Phase 5: Sentry routing

- 5.1 `apps/web-platform/infra/sentry/issue-alerts.tf`: widen `egress_blocked` op filter to `egress_blocked,ghcr_deny_lost,ghcr_deny_probe_blind`; extend the comment; do not rename the resource
- 5.2 Regenerate `alert-reference.json` from the `sentry-alert-reference-expected-<run>` CI artifact

## Phase 6: Decision record and runbook

- 6.1 ADR-096 amendment "2026-10-01 (#9275)" (including the running-web-2 residual) and the top-summary bullet; short ADR-052 amendment (generator-owned CIDR set, carve-only narrowing, why the sampler filter is not the DST-range suppression it rejects)
- 6.2 Read `model.c4`, `views.c4`, `spec.c4`; edit only a falsified statement
- 6.3 Runbook `cron-egress-blocked.md` (anchor `ghcr-carve-9275`): GHCR carve section, decode rows, repair ladder keyed by event `extra` with the `gh workflow run apply-web-platform-infra.yml --ref main` re-apply verb (read its inputs first), once-per-unresolved-group note, replace the `comm -23` recipe with `--check` (needs live `/meta`)

## Phase 7: Tracking and ship

- 7.1 Follow-ups already filed: #9390 (hosts-file docker.pkg.github.com at next registry replace), #9391 (Better Stack `ghcr_blocked=0` alert), #9392 (`enforcement_missing` investigation), #9393 (carved firewall artifacts to running web-2); cite them in the PR body and ADR text
- 7.1b Post-merge: re-read the monitor environment mute state for `cron-egress-resolve` and `cron-github-cidr-refresh`; Sentry reads for the two error ops (absence over 24 h)
- 7.2 PR body: `Closes #9275`, "cloud-init-registry.yml: no change", the two deviations from `decision-challenges.md`
- 7.3 CI only; ask the operator again before an admin merge of this non-docs diff
