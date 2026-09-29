# inngest CLI — pin provenance

Analysis of record for the `inngest_cli_version` / `inngest_cli_sha256` /
`inngest_cli_sha256_arm64` pins in `inngest.tf`. Read by
`inngest-cli-staleness.test.sh` (CI gate, per-PR) and by the
`Detect inngest CLI pin drift` poll step in `.github/workflows/rule-audit.yml`
(detection, 1st + 15th). Mirrors the shape of `zot-image.provenance.md` so the
sidecars share one parseable format.

**inngest-server is the entire background-job substrate.** A wrong pin here does not
degrade the scheduler — the bootstrap sha256-verify refuses the tarball and the host
never runs it. Treat every row below as load-bearing.

| Field | Value |
|---|---|
| Pinned version | **v1.45.1** |
| Upstream release date | 2026-09-17T20:51:40Z |
| Capture date (UTC) | **2026-09-29** |
| Superseded | v1.19.4 (2026-05-15) — 29 stable releases behind at time of bump (#7463) |

## Current pin

| Arch | sha256 (`inngest_<ver>_linux_<arch>.tar.gz`) |
|---|---|
| amd64 | `52c07d837088a6712acd15b8edd4191f961b69884541f468a3c1b9bb4348a4e5` |
| arm64 | `58db59dbe39afd7472c7c59bd7cc9f82f5da5810dabdac40b2bde3a8338aa7b5` |

Both rows come from ONE release-shipped checksums manifest (a plain sha256sum file —
release-shipped, not GPG-signed):

`https://github.com/inngest/inngest/releases/download/v1.45.1/checksums.txt`

Each row was re-verified by downloading the tarball and re-hashing it against the
embedded value — command + output recorded in
`knowledge-base/project/specs/feat-one-shot-7463-inngest-cli-pin-bump/phase0-respike-evidence.md`.

## Previous known-good pin

**This is the rollback target.** The bump deliberately erases these checksums from
`inngest.tf`, so without this section they survive only in git history — a
git-archaeology exercise under incident pressure on a host with no shell and no SSH.
Asserted by staleness check 8; rotate it on every bump.

| Arch | sha256 | Superseded |
|---|---|---|
| amd64 | `d023b26659275fdbe9348b6518077ce1ea9906a449898e49ddced91bfc6fd757` (v1.19.4) | 2026-09-29 |
| arm64 | `30a3f01474cb2266c24545cdc83930baeae14232d629c87aeeb8f21118948199` (v1.19.4) | 2026-09-29 |

Recovery procedure: see the plan's `## Rollback`. In short — revert the `inngest.tf`
locals to the above and rotate THIS section to the pin being rolled back from (a
naive revert that leaves previous==current reds the gate, deliberately), merge
(host-inert by `OPERATOR_APPLIED_EXCLUSIONS`), then re-run the apply-window path.

## Drift threshold (the poll's trip point — recorded here so the two cannot diverge)

The `rule-audit.yml` poll files the `inngest-pin-drift` issue when the pinned version
is **`>= 5` stable releases behind `releases/latest` OR the pinned release's upstream
date is `>= 45` days old**. inngest ships ~weekly, so an any-delta rule would mint a
permanently-open ticket within days of every bump. The offline `MAX_AGE_DAYS=60` in
`inngest-cli-staleness.test.sh` (and `inngest-cli-pin-probe.sh`) is the backstop for
the poll's OWN failure — the two mechanisms are different failures, not redundancy.

## Re-verification table (v1.19.4 → v1.45.1)

Every claim below was re-measured against the v1.45.1 binary/source at bump time —
evidence in `phase0-respike-evidence.md`. These are **measurements**, not inferences.

| Claim | Verdict |
|---|---|
| Every flag the repo passes exists (`--host --port --sqlite-dir --sdk-url --signing-key --event-key --poll-interval --tick --postgres-uri --redis-uri --postgres-max-open-conns --postgres-max-idle-conns --postgres-conn-max-idle-time`) | **HOLDS** — `start --help` diff is additions-only (four `--connect-*-grpc-*` flags) |
| `--postgres-conn-max-idle-time` unit | **MINUTES — holds** (`* time.Minute`, `pkg/devserver/devserver.go:202` at tag) |
| `--postgres-conn-max-lifetime` unit (not passed; recorded) | **MINUTES** (`devserver.go:203`) |
| `--postgres-max-open-conns` durable-backend sentinel | **HOLDS**; v1.45.1 adds `>1` and `idle<=open` validation — repo's `5`/`2` pass |
| `signkey-prod-` strip required | **HOLDS** — prefixed key rejected `must be hex string`, bare hex boots |
| `inngest pause` drain verb | **ABSENT on BOTH endpoints** — pre-existing dead call (`inngest-bootstrap.sh` `|| warn` path); follow-up issue, not an upgrade regression |
| Route-once fan-out (multi `--sdk-url`, same app id) | **HOLDS** — 4/4 events on last-writer URL, 0 on sibling |
| `runs(filter: RunsFilterV2!)` + `startedAt`/`queuedAt` | **HOLDS** |
| `scheduled_tick` absent; `eventName` null | **HOLDS** |
| `cronSchedule` on run nodes | **CHANGED** — now populated (`"* * * * *"`) on v1.45.1; was null on v1.19.4. The doublefire probe buckets on `startedAt` — version-agnostic, no logic change needed |
| Epoch `Time!` bound rejected | **HOLDS** ("time should be RFC3339Nano formatted string") |
| `GET /v1/functions` unauthenticated → 404 | **HOLDS** |
| `eventsV2` envelope (`inngest/scheduled.timer` + nested `runs`) | **HOLDS** |
| `inngest/function.cancelled` + ULID run ids | **HOLDS** |
| FLUSHALL mandate (PG swap, retained Redis) | **HOLDS** — stale continuation + cron fired against empty PG-B; `{cs}` keys survived |
| Step-524 alert needles in `betterstack-logs-alerts.tf` | **HOLDS** — all three error texts still in v1.45.1 source |
| Connect listeners | **CHANGED** — v1.45.1 binds `*:50052`, `*:50053`, `*:8289` wildcard (the `--connect-*-grpc-ip` flags are ADVERTISE, not bind). nftables default-deny gates inbound on the dedicated host; nobody should assume loopback-only |
| `--poll-interval` self-heal semantics | **UNCHANGED mechanism** — `cmd/start` never sets `Opts.Poll` on either tag; the loop re-pings only errored apps on both |
| Goose migrations on `start` | 5 new Postgres migrations — incl. **destructive** `000006_apps_unique_active_name` (force-archive+rename dup app names) and DROPs in 000007/000009/000010. Pre-flip Postgres backup is a precondition of the apply window (follow-through tracker) |

## Version-scoped claim register

The staleness gate's check 7 enforces that `inngest vX.Y.Z` claims in these files name
the pinned version. The two REQUIRED claim locations (each must carry >=1 claim) are
`inngest-inventory.sh` and `inngest-doublefire-probe.sh`.

| Claim | Location | Status |
|---|---|---|
| Schema pinned for the GQL probes (functions/runs/eventsV2 shapes) | `inngest-inventory.sh`, `inngest-enumerate-reminders.sh`, `inngest-doublefire-probe.sh`, `inngest-wiped-volume-verify.sh`, `ci-deploy.sh` | Re-verified vs v1.45.1 — see respike doc |
| Step-524 error-text needles | `betterstack-logs-alerts.tf` | Re-verified vs v1.45.1 source |
| Idle-time flag is MINUTES | `inngest-bootstrap.sh` | Re-verified vs v1.45.1 `cmd/start` source |
| `inngest start` host topology | `inngest-host.tf` | Re-stamped |

## Known coupling

- `inngest-userdata-budget.sh` embeds the amd64 sha as a SIZE FIXTURE — not part of
  this gate's assembly, but the bump updates it anyway so the old-sha grep sweep
  returns zero.
- `inngest_cli_sha256_arm64` is NOT in `mint-inngest-bootstrap-tag.yml`'s watched
  `PINS` set — an arm64-only drift mints no `vinngest-v*` tag. Harmless today (amd64
  host); recorded so nobody assumes arm64 bumps propagate by image alone.
- `tests/scripts/test-inngest-host-dark-gate.sh` carries `cli_version=v1.19.4` as a
  fixture row — it exercises the parser, not the pin; the fixture is version-agnostic
  and deliberately not re-stamped.

## Refresh recipe (capture date aged out, pin unchanged)

Use when the age gate reddens but upstream has **not** moved: re-confirm the pinned
tarballs still resolve upstream (`curl -fsSI` the two `inngest_<ver>_linux_<arch>.tar.gz`
URLs), then re-stamp `Capture date (UTC)`.

**Do not re-stamp the date to clear a red gate without doing the work.** The date is
an attestation that the analysis above is current; typing today's date makes the
backstop permanently green while the analysis rots. If upstream HAS moved, use the
bump procedure below instead — it is a materially heavier procedure, not the same one.

## Bump procedure

The recipe above re-stamps a date. **This one re-does the analysis**, and it is what
the staleness gate's failure message points at. Do all of it, in order:

1. **Rotate `## Previous known-good pin`** to the pin you are about to replace — both
   arches, with today's date. Do this FIRST; it is the step that is easiest to forget
   and the one that matters during an incident.
2. **Resolve the target:** `gh api repos/inngest/inngest/releases/latest` → tag.
   Compute the delta with a tag-ordered walk over stable (`^v\d+\.\d+\.\d+$`,
   non-prerelease) tags — never restate a remembered count.
3. **Fetch the ONE `checksums.txt`** at the target tag; extract the `linux_amd64` and
   `linux_arm64` rows; download both tarballs and `sha256sum -c` each against its row.
   Update `## Current pin` and the three locals in `inngest.tf` together, plus the
   stub row in `inngest-userdata-budget.sh`.
4. **Re-verify the flag surface:** `inngest start --help` diff between tags (no flag
   the repo passes may vanish); units against `cmd/start/cmd.go` + `pkg/devserver`
   source at the NEW tag, never docs (the `--postgres-conn-max-idle-time` MINUTES
   precedent, #6258).
5. **Re-run the re-spike** per
   `knowledge-base/project/specs/feat-one-shot-7463-inngest-cli-pin-bump/phase0-respike-evidence.md`'s
   harness: route-once, `RunsFilterV2` shape, `/v1/functions` 404, epoch `Time!`
   bound, `eventsV2` envelope, the Postgres-swap/FLUSHALL experiment, and the
   migration census (`pkg/db/postgres/migrations` diff between tags — every
   destructive/cleanup migration gets a named line here and in the follow-through
   tracker, because that is the irreversible half of the apply window).
6. **Re-stamp `Capture date (UTC)`** and run `bash inngest-cli-staleness.test.sh` —
   it must exit 0 — and `bash inngest-cli-staleness-mutation.test.sh` — all rows must
   behave as expected.
7. **Merge is pipeline-active:** `mint-inngest-bootstrap-tag.yml` auto-fires on the
   `inngest*` pin change → `vinngest-v*` tag + bootstrap image + ADR-232
   auto-authored cloud-init pin PR. The LIVE flip needs that auto-PR merged plus an
   operator-gated dispatch (`deploy inngest` or `inngest-host-replace`) in its own
   window — after the shared-Postgres concurrency check and a pre-flip Postgres
   backup, because upstream runs goose migrations on `start` and the delta can
   contain destructive cleanup migrations.

Agent entry point:

```
/soleur:one-shot "refresh the inngest CLI pin provenance sidecar per apps/web-platform/infra/inngest-cli.provenance.md section 'Bump procedure'"
```
