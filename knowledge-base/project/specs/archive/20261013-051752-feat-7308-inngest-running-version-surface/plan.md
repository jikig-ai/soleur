---
issue: 7308
branch: feat/7308-inngest-running-version-surface
status: implemented
---

# #7308 remainder — surface the running inngest version on `/hooks/deploy-status`

## Premise

#7308 asked for three things: the pin-freshness monitor (done — #7463 PR-A offline
gate + PR-B `Detect inngest CLI pin drift` poll, merged as #9222/#9242), the server
upgrade (done — pin now v1.45.1), and the SDK major (tracked separately as #8628).
What remains is the issue's "smaller adjacent finding": **the running version is not
observable**. The binary never logs its version and no `SOLEUR_*` marker carries it,
so the only evidence a host matches `inngest.tf` is bootstrap pinning — inference,
not measurement.

`/hooks/deploy-status` (`apps/web-platform/infra/cat-deploy-state.sh`, invoked by
adnanh/webhook per `hooks.json.tmpl`) is the named home: it already reports
`host_id`, `ci_deploy_sha256`, `seccomp_profile_sha256`, `vector_config_identity`,
and `services.inngest_server` (the unit state — but not what the binary IS).

## Key design facts (researched + review-corrected)

- Reachability: the public `/hooks` ingress terminates on web-1
  (`scripts/inngest-host-state.sh`'s measured note); the dedicated host serves the
  same hooks.json only over the private path the cutover machinery uses. So the
  field answers per-host: web-1 = the quiesced arm's installed pin; the inngest
  host = its installed pin, reachable through the internal channel.
- **Running-process resolution is structurally dead** (verified, review finding):
  `inngest-server.service`'s ExecStart is `doppler run -- bash -c '… exec
  /usr/local/bin/inngest start …'` — `doppler run` forks, so `MainPID` = doppler,
  `ExecStart.path=` = /usr/bin/doppler, and `doppler version` is not a registered
  subcommand; and same-UID non-descendant `/proc/<pid>/exe` readlinks are denied
  under `kernel.yama.ptrace_scope=1` (verified on this host). The shipped field is
  therefore the **installed** binary's self-reported version — honest semantics:
  bootstrap pins it by version+sha256 and immutable-redeploy keeps
  installed≈running outside a seconds-wide replace window.
- `inngest version` prints a bare token, e.g. `1.19.4-2c8385ba8` (verified on the
  real binary — NO `v` prefix; the tf pin is `v1.45.1`-shaped, consumers
  normalize).
- Sentinel contract: an ABSENT field = old script; failures emit the
  discriminating tokens `absent` / `unknown-no-timeout` / `version-unreadable`
  (the `inngest_redis_binary` convention).
- `set -euo pipefail` — every probe must be `|| true`-guarded like its siblings.
- The emitted token goes into an HTTP response body → sanitize to
  `^[0-9A-Za-z.-]+$` (version charset) before embedding; emit `""` on mismatch.
- Delivery is automatic: `cat-deploy-state.sh` is already in
  `apply-deploy-pipeline-fix.yml`'s `push.paths` — merging applies the new script
  to hosts via the infra-config channel. No operator window, no follow-through
  needed for delivery. (Field appears on hosts on that next apply; absent-field =
  old script is the intended interim signal.)

## Change

`apps/web-platform/infra/cat-deploy-state.sh` — one helper + one emitted key
(see the file's own comment block for the dead-leg analysis):

```bash
INNGEST_SERVER_VERSION="version-unreadable"  # discriminating sentinels below
_isv_bin() { … timeout -k 1 5 <bin> version | grep -oE '<semver>' | head -c 64 … }
INNGEST_SERVER_VERSION="$(_isv_bin "${INNGEST_SERVER_BIN:-/usr/local/bin/inngest}")"
# tokens: absent / unknown-no-timeout / version-unreadable; absent KEY = old script
```

emitted inside `services` next to `inngest_server`:

```
inngest_server_version: $isv,
```

Test seam: `INNGEST_SERVER_BIN` (binary override — mirrors the
`CI_DEPLOY_SH_PATH` "test harness only" convention). No systemd seam needed —
the shipped design deliberately does not consult systemctl.

## Tests — `apps/web-platform/infra/cat-deploy-state.test.sh`

New rows (as shipped — all in `cat-deploy-state.test.sh`):

1. Installed binary stub → emits its `version` token.
2. Prose-embedded token (`inngest version 1.45.1`) → extracts `1.45.1` (a
   whole-output regression must not pass).
3. Binary absent → `absent` AND key present.
4. Executable directory → `absent` (the `-f` guard, not just `-x`).
5. Garbage/ANSI output → `version-unreadable`, never raw text in the body.
6. Hung binary → killed by `timeout -k 1 5`, `version-unreadable` (<20s).
7. Presence under `no_prior_deploy` AND `corrupt_state`; measured value survives
   the sentinel merge.

## Guard/parity pins

- No external consumer enumerates `services.*` keys (verified — additive is safe).
- `hooks.json.tmpl` unchanged (same script path).
- infra-config delivery list already contains the file — no registration edits.

## Observability / Downtime / Rollback

- Read-only additive field; the risk class is "hook returns wrong/empty value",
  bounded by the existing sentinel contract. Rollback = revert; the next
  infra-config apply ships it.
- This PR IS the observability surface — the plan gate is satisfied by the field
  itself plus the test rows; no separate marker needed.
- No `systemctl start|restart` added under infra/ → `ci-deploy.test.sh` not
  mandated by the repo-global rule (the diff adds `systemctl show` reads only —
  but the rule keys on start/restart writers; still cheap to run that suite).

## Out of scope

- SDK 3.x → 4.x major (#8628 tracks it).
- A parity/comparison alert (running vs pinned) — the surface is the deliverable;
  comparison, if wanted, is a separate monitor. The offline gate
  (`inngest-cli-staleness.test.sh`) could later add a consumer leg.
- `inngest-inventory.sh` — redundant: `deploy-status` is installed on the inngest
  host too and `host_id` disambiguates; one field on one script covers both hosts.

## PR shape

One PR, non-workflow diff (cat-deploy-state.sh + its test + this spec dir) →
admin-mergeable once CI is green (per operator's standing authorization).
Ship checklist: focused suite (`cat-deploy-state.test.sh`) +
`ci-deploy.test.sh` (start-writer inventory is repo-global) + shellcheck +
review panel (code class) → QA (fixture-level; no UI) → ship → merge →
post-merge: dispatch `apply-deploy-pipeline-fix` is NOT needed (merge-triggered),
verify by waiting for the auto-apply run to go green and (once applied) reading
the field off the hook — observation only, no host writes by us.
