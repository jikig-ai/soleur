---
issue: 7308
branch: feat/7308-inngest-running-version-surface
status: planned
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

## Key design facts (researched)

- The hook script is host-relative: `hooks.json.tmpl` is installed on every
  webhook-bearing host, and `host_id` already disambiguates the answerer. So one
  script change makes the field available on web-1 (quiesced arm — still a valid
  "which binary did the fleet push here" answer) AND on the dedicated inngest host
  (the real running server). No second surface needed.
- The binary lives at `/usr/local/bin/inngest` (cloud-init/bootstrap install path;
  `inngest-server.service` ExecStart points at it). `inngest version` prints a bare
  token, e.g. `1.19.4-2c8385ba8` (verified on the real binary — NO `v` prefix; the
  tf pin is `v1.45.1`-shaped, consumers normalize).
- "Running version" > "installed version": prefer the binary the *running process*
  is executing — `/proc/<MainPID>/exe` — then fall back to the ExecStart-resolved
  path, then to `/usr/local/bin/inngest`. Ordering matters: ExecStart could name a
  different binary than the installed one; the live process is ground truth.
- Sentinel contract (existing convention, must hold): an ABSENT field = old script;
  an EMPTY string = read failure. Never omit the key on failure.
- `set -euo pipefail` — every probe must be `|| true`-guarded like its siblings.
- The emitted token goes into an HTTP response body → sanitize to
  `^[0-9A-Za-z.-]+$` (version charset) before embedding; emit `""` on mismatch.
- Delivery is automatic: `cat-deploy-state.sh` is already in
  `apply-deploy-pipeline-fix.yml`'s `push.paths` — merging applies the new script
  to hosts via the infra-config channel. No operator window, no follow-through
  needed for delivery. (Field appears on hosts on that next apply; absent-field =
  old script is the intended interim signal.)

## Change

`apps/web-platform/infra/cat-deploy-state.sh` — one new resolver + one emitted key:

```bash
# #7308 — inngest_server_version: the version of the binary the inngest-server
# unit is ACTUALLY running (or would run), so /hooks/deploy-status answers
# "which version is live here" by measurement, not by bootstrap-pin inference.
# Resolution order: the running process's exe link (ground truth while active),
# then the ExecStart path, then the installed-binary default. Empty = read
# failure; absent = old script (same contract as HOST_ID / CI_DEPLOY_SHA256).
INNGEST_SERVER_VERSION=""
_isv_bin() {
  # $1 = candidate binary path; emits its `version` token if executable+sane.
  local out
  [[ -x "$1" ]] || return 0
  out="$(timeout 5 "$1" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-0-9A-Za-z.]*' | head -1 || true)"
  [[ -n "$out" ]] && printf '%s' "$out"
}
_isv_pid="$(systemctl show -p MainPID --value inngest-server.service 2>/dev/null || true)"
if [[ "${_isv_pid:-0}" =~ ^[0-9]+$ && "$_isv_pid" -gt 0 ]]; then
  INNGEST_SERVER_VERSION="$(_isv_bin "$(readlink -f "/proc/$_isv_pid/exe" 2>/dev/null || true)")"
fi
if [[ -z "$INNGEST_SERVER_VERSION" ]]; then
  _isv_es="$(systemctl show -p ExecStart --value inngest-server.service 2>/dev/null || true)"
  # systemd>=248 structured form: `{ path=/x ; argv[]=... }` — take the path= token;
  # older/raw form: first token of the command line (strip systemd prefix chars).
  _isv_path="$(grep -oE 'path=[^ ;]+' <<<"$_isv_es" | head -1 | cut -d= -f2 || true)"
  [[ -z "$_isv_path" ]] && _isv_path="$(awk '{print $1}' <<<"$_isv_es" | sed 's/^[-!+@]*//' || true)"
  [[ -n "$_isv_path" ]] && INNGEST_SERVER_VERSION="$(_isv_bin "$_isv_path")"
fi
[[ -z "$INNGEST_SERVER_VERSION" ]] && INNGEST_SERVER_VERSION="$(_isv_bin "${INNGEST_SERVER_BIN:-/usr/local/bin/inngest}")"
readonly INNGEST_SERVER_VERSION
```

emitted inside `services` next to `inngest_server`:

```
inngest_server_version: $isv,
```

Test seams: `INNGEST_SERVER_BIN` (binary override — mirrors `CI_DEPLOY_SH_PATH`
"test harness only" convention); `systemctl`/`timeout` are PATH-stubbed in tests
(existing suite precedent for `systemctl`/`docker` mocks).

## Tests — `apps/web-platform/infra/cat-deploy-state.test.sh`

New rows:

1. Field present in all three payloads (`no_prior_deploy`, `corrupt_state`, OK).
2. Stub binary `version` → emitted value (PATH-stub `inngest`, ExecStart unset →
   falls through to `INNGEST_SERVER_BIN`/`/usr/local/bin` seam).
3. MainPID>0 → `/proc/<pid>/exe` path is used (systemctl stub returns a PID whose
   exe resolves to the stub).
4. Service inactive (MainPID=0) → ExecStart `path=` resolution used.
5. Missing/非-executable binary → `""` (sentinel, not absent).
6. Garbage/binary output (e.g. `inngest version` printing ANSI/junk) → sanitized
   to `""` or the clean token; never raw prose in the JSON body.
7. The `version` invocation is `timeout`-bounded (a hung binary can't wedge the
   hook — webhook returns cmd output; a hang = non-200).

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
