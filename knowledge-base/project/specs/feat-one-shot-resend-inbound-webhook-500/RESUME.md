# RESUME — fix the DEDICATED inngest host; do not co-locate

Operator decision, 2026-08-11: **inngest must not be co-located on web-1 or web-2.** The dedicated
host is the target architecture and it is to be fixed properly. This reverses the approach PR #7158
took, and supersedes ADR-167's rollback-to-co-located reasoning.

Paste the block under "Resume prompt" into a fresh session.

---

## Resume prompt

```
/soleur:go Fix the dedicated inngest host (soleur-inngest, 10.0.1.40) so it actually serves on
:8288. Operator decision 2026-08-11: do NOT co-locate inngest on web-1 or web-2 — the dedicated
host is the target architecture. This reverses PR #7158's repoint and supersedes ADR-167.

VERIFIED LIVE STATE (2026-08-11, pulled from telemetry, not inferred):
- The outage is live and 12 days old. `connect ECONNREFUSED 10.0.1.40:8288` from container
  soleur-web-platform, ~100 rows in a 6-minute window, still firing.
- The host EXISTS and is RUNNING: `soleur-inngest`, cpx22, created 2026-07-30 17:13:06 CEST.
  That creation timestamp IS the outage onset. It boots and never binds :8288.
- main still points at the dead host: INNGEST_BASE_URL=http://10.0.1.40:8288 in ci-deploy.sh
  (2 sites) and cloud-init.yml (1 site). That is now CORRECT per this decision — do not repoint.
- Zot is genuinely healthy (do not re-litigate): registry host recreated 2026-08-11 00:16:50,
  disk 8%, zot_restarts=0, ping_rc=0, and the web-1 consumer probe emits its canary with zero
  suppression. #7267 and #7272 are closed AND the condition is cleared — verified both ways.

START HERE — THE HOST IS DARK, AND THAT IS THE FIRST BUG.
There is no inngest-boot-phone-home.sh on main and ZERO telemetry from soleur-inngest in 24h.
Twelve days of undiagnosability is a missing error channel, not a hard problem. Ship the host's
OWN error channel BEFORE any black-box reproduction:
  - a boot phone-home / SOLEUR_* stdout marker from cloud-init-inngest.yml's terminal trap,
  - inngest-server.service journald into the vector allowlist (apps/web-platform/infra/vector.toml),
  - assert the marker actually reaches Better Stack before trusting any later silence.
This is the documented pattern in
knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md
and hr-no-dashboard-eyeball-pull-data-yourself. Do not SSH (hr-no-ssh-fallback-in-runbooks).

KNOWN PRIOR ART — the obvious cause is ALREADY MITIGATED, so do not stop there.
The status=203/EXEC doppler-path bug (ExecStart=/usr/bin/doppler vs the /usr/local/bin install)
is handled at cloud-init-inngest.yml:196-202 via `ln -sf /usr/local/bin/doppler /usr/bin/doppler`.
Confirm it survived the 2026-07-30 recreate, then look further. Treat "it must be the doppler path"
as a hypothesis to falsify.

WRONG LEVER — do not reach for it. restart-inngest-server.yml drives the DEPLOY WEBHOOK, which
lands on the WEB host's co-located unit. It never touches 10.0.1.40 and will report success having
fixed nothing. tasks.md 0.0b already struck it for this reason.

ALSO IN SCOPE — WE ARE 27 RELEASES BEHIND. inngest.tf:29 pins inngest_cli_version = "v1.19.4"
(published 2026-05-15); latest upstream is v1.41.1 (2026-08-05). Confirm the running server is on
a current version and bump the pin.
  - The bump needs TWO checksums, not one: the dedicated host is DUAL-ARCH (local.inngest_arch,
    inngest-host.tf), so inngest_cli_sha256 (amd64) AND inngest_cli_sha256_arm64 must both come
    from the same signed checksums.txt for the new tag. Using the amd64 SHA on an arm64 type fails
    the download verify — that pairing is why both locals exist.
  - Read the release notes across v1.19 -> v1.41 for breaking changes to the server flags this
    fleet passes (inngest-bootstrap.sh's ExecStart, --sdk-url, the postgres/redis URIs). Three
    months of minors is a real migration surface, not a version-string edit.
  - SEQUENCE IT SECOND, NOT FIRST. v1.19.4 was pinned 2026-05-15 and the host served on it until
    the 2026-07-30 recreate, so the version is unlikely to be the bind failure's cause. Fix
    observability, diagnose the actual fault, THEN bump — changing the binary and the diagnosis
    surface in one move is how a fix gets attributed to the wrong change. If the diagnosis turns
    out to implicate the version after all, that is a finding, not the starting assumption.

FILES: apps/web-platform/infra/{cloud-init-inngest.yml, inngest-bootstrap.sh, inngest-host.tf,
inngest.tf, vector.toml}. ADR-100 is the cutover; ADR-167 documents the rollback this decision
reverses and needs superseding, not deleting.

DEFINITION OF DONE: the dedicated host serves :8288, the app dispatches to 10.0.1.40 with zero
ECONNREFUSED, the host emits its own telemetry so the next failure is diagnosable without SSH, and
inngest_cli_version is current with both arch checksums matching the signed checksums.txt.

SCOPE NOTE: PR #7158 is now contrary to this decision — its core change is the repoint away from
the dedicated host. Do not rebase it (71 commits behind, 16 conflict hunks, and its registry-budget
half is already superseded on main by #7283/#7300/#7325). Read the rest of this RESUME.md for the
two pieces worth salvaging.
```

---

## Why PR #7158 should not be resumed as-is

Its central change is `INNGEST_BASE_URL: 10.0.1.40 → host.docker.internal`, i.e. exactly the
co-location the operator has now ruled out. The branch is also 71 commits behind `origin/main` with
16 conflict hunks across 15 shared files, and its registry-budget half landed on main independently
as a **different implementation** (#7283, #7300, #7325).

Recommended disposition: **close #7158**, superseding ADR-167, after extracting the two items below.

## Two things worth salvaging from #7158

### 1. The entropy defect is LIVE ON MAIN (small, independent, measured)

Main's `registry-userdata-budget.sh` models the Doppler service token as
`join(".", ["dp","st","prd_registry","STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTU"])`. That stub is
compressible, so the gate under-measures the incompressible part of the render — the same class the
gate exists to prevent.

Measured 2026-08-11:

| stub | raw | gzip -9 | ratio |
|---|---|---|---|
| main's `STUBSTUB…` | 43 | 27 | **0.63** |
| real-entropy | 43 | 63 | 1.47 |

The fix is a per-stub compressibility BOUND (not a pin — gzip output for a ~24 B input varies with
dictionary state). Implementation and rationale are on this branch in
`registry-userdata-budget.test.sh`; port the assertion, not the file, since main's implementation
diverged. Ships independently of everything else here.

### 2. The runner fail-open (commit e011c0aa8) — check whether main still has it

`run-registered-suites.sh` counted only suites that reported a verdict:

```
'if bash "{}" …; then echo "PASS {}"; else echo "RED {}"; fi'
RED=$(grep -c '^RED' "$LOG" || true)
(( RED == 0 ))
```

A SIGKILLed suite dies before either `echo`, so it emits neither line — `RED` stays 0, `PASS` comes
up short, `(of N)` is compared against nothing, and the gate exits 0. Measured on this box:
`87 passed, 0 failed (of 88)` with rc=0 while `git-data-runcmd-rehearsal.test.sh` was OOM-killed
under sibling-worktree contention. That suite passes 19/19 in isolation — the kill was
environmental, the fail-open was not.

Fix is on this branch: require `PASS + RED == registered count`, fatal on shortfall, naming the
missing suites by set difference (NOT by grepping for xargs' "terminated by signal N", which goes
to xargs' stderr and never passes through the `tee` that writes the log).

## Open, unrelated to the above

- **web-2 probe is silent.** It emitted the zot-consumer canary on 2026-08-04 and emits none now,
  while still being present in `var.web_hosts` and `running` in hcloud. Not diagnosed.
- **#7158's `verify_inngest_dispatch` 401 arm** — if any part of that branch is salvaged, note the
  arm returns 1 with no retries, runs AFTER the container is live and past the canary rollback
  point, and has no behavioral test (all six assertions grep source text).
