---
title: "fix: argv-bearer sweep, Tier 2 host/apply scripts and residual non-Bearer argv credentials"
date: 2026-10-06
slug: fix-argv-bearer-sweep-tier2-and-residual-credentials
branch: feat-one-shot-argv-bearer-sweep-tier2-residual
issue: 9597
closes: []
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Continue moving curl credentials off the process argument list (readable by every local user via
`/proc/<pid>/cmdline`) and onto curl's stdin config channel (`--config -`). The previous sweep moved
53 scripts and left a shrink-only ratchet (baseline E). This pass converts:

1. the Tier 2 files still in baseline E, **minus `web-private-nic-guard.sh`** (open draft PR #9632
   already converts it and edits baseline E; the operator chose to skip it here),
2. the credentials the Rule E lint cannot see (Flagsmith `Api-Key`, LinkedIn form fields, CF-Access
   headers, the Supabase PATCH body, X OAuth1, `-u user:token`),
3. the SENTRY_PROJECT pin check, proven by outcome without reading the secret.

Tier 3 (workflow YAML, cloud-init, the `env -i` hop, a YAML/non-Bearer lint arm) is **split out** and
restated on #9597; this PR does not close #9597 and keeps #7797 open (`Ref` only).

## Research Reconciliation — Issue Text vs. Codebase

| Issue / brief claim | Reality (measured on origin/main `ed6083309f`) | Plan response |
|---|---|---|
| fresh-host-boot-trail, verify-tunnel-ingress-origin are under `scripts/` | They live under `apps/web-platform/infra/scripts/` | Use the real paths everywhere. |
| `zot-image-oci-archive.sh` runs "live in the push-triggered infra apply" | It runs in `zot-image-mirror.yml` (`build`/`verify`, on push touching it) and `scripts/registry-replace-preflight.sh`, not in `apply-web-platform-infra.yml`. Its token is an anonymous ghcr.io pull token. It has no xtrace refusal. | Still converted (baseline E), still needs a pre-merge shim row; the workflow that exercises it is `zot-image-mirror.yml`. Add the xtrace refusal the other converted scripts carry only if the lint requires it (Phase 0 check). |
| Tier 3 is "14 files, ~32 sites, apply-web-platform-infra.yml has 8" | `git grep -nE 'Authorization: Bearer' -- '.github/**/*.yml' 'apps/**/cloud-init*.yml'` = **21 files / 55 sites**; apply-web-platform-infra.yml has **12** | Record the measured figures on #9597; sizes the split-out PR. |
| Residual non-Bearer list: `flip.sh` only for Flagsmith | `create.sh`, `delete.sh`, `list.sh` carry the same `fs_api` `Authorization: Api-Key` argv form; `user-set-role/set-role.sh` already uses the stdin form (template) | Convert all four Flagsmith scripts (one helper shape). |
| `linkedin-setup.sh`: `--data-urlencode token=` | Three argv sites: `client_secret=` (lines ~243, ~366) and `token=` (~244) | Convert all three. |
| CF-Access only in `check-cloudflare-token-drift.sh` | Also `verify-tunnel-ingress-origin.sh` (in scope, Phase 1 file), plus `.github/actions/dispatch-web-redeploy/track.sh`, `infra-config-verify.sh`, `push-infra-config.sh` | The first two ride along (already edited). The other three are **deferred** to the Tier 3 follow-up (live in apply/CI workflows). |
| `zot-entry-gate.sh` is host-deployed (with `web-zot-consumer-probe.sh`) | Only `web-zot-consumer-probe.sh` is hashed into a provisioner (`zot_consumer_probe_install`). `zot-entry-gate.sh` is a release-pipeline gate (`reusable-release.yml`, `build-inngest-bootstrap-image.yml`), needs no provisioner window, and a bad edit shows as a red release/image build | Move `zot-entry-gate.sh` to Phase 1 (pre-merge shim row). |
| `verify-tunnel-ingress-origin.sh` has one site | Two curl calls: the Bearer call (~line 69) and the deploy-status call (~line 131) carrying the CF-Access pair **and** `X-Signature-256` (webhook HMAC) | Convert both calls; the HMAC header moves into the config too. Rows per call site. |
| Converting host-deployed scripts happens "in the deployment window" | Each is hashed into an SSH-provisioner `terraform_data` (`disk_monitor_install`, `resource_monitor_install`, `container_restart_monitor_install`, `cron_egress_firewall`, `deploy_pipeline_fix` + `deploy_pipeline_fix_web2` for the inngest pair, `zot_consumer_probe_install`); `user_data` carries `ignore_changes`, so no host replacement. Precedent: the Resend-five conversion merged and was verified by outcome. | Phase 3 groups every host-deployed edit into ONE merge so it costs one provisioner window; postmerge verifies by outcome. |
| `soleur-host-bootstrap.sh` site is at lines 875-879 | The post is now at line ~1049, inside a nested quoted heredoc that authors an embedded `#!/bin/sh` script | Edit the embedded script; POSIX only; add the missing `else` skip-and-report branch. |

## Research Insights

**Premise Validation.** #7797, #9597, #7898 are OPEN. No open PR links them; the previous sweep PR is
merged. #9632 (draft, updated 2026-10-06) overlaps `web-private-nic-guard.sh` and baseline E: skip it
(operator decision). #9348 (held draft) touches `scripts/check-cloudflare-token-drift.test.sh` only:
Phase 2 must not edit that test; new coverage goes in `tests/scripts/test-argv-bearer-sweep.sh`.
No ADR rejects the mechanism (stdin config is the established ADR-backed form from the prior sweep).

**Property List.**
- P1. No credential (Bearer, `Api-Key`, CF-Access, OAuth1 header, `-u`, `--data-urlencode` secret,
  secret-bearing body) appears on the argv of a curl in a converted script.
- P2. A malformed credential never reaches curl (newline/quote injection of config directives is
  refused before the call) and the refusal reports instead of silently skipping.
- P3. A script run by the infra apply or a publish workflow has its changed transport proven BEFORE
  merge, by a test that observes argv and stdin.
- P4. The ratchet only shrinks: baseline E ends containing exactly the unconverted file(s).
- P5. The SENTRY_PROJECT class is known to be inside the pin, or is recorded as unverifiable with why.

**Cut List.** (mechanism → property → what already covers it)
- New "Rule F" lint arm for non-Bearer headers/YAML → P4 for the residual set → cut here; the
  census script plus a one-time `git grep` row in the battery covers this PR, and the arm is designed
  once with the YAML arm in the Tier 3 follow-up (200-300 LOC into a 2,277-line file is its own PR).
- One-off `workflow_dispatch` to read SENTRY_PROJECT → P5 → cut; a green `sentry-audit-gate` run
  already executes the script's pin `case` (`sentry-monitors-audit.sh`, `''|web-platform|soleur-web-platform`),
  and an empty value fails the gate's own presence check, so a green run proves class membership
  without any new workflow (a dispatched workflow also cannot run from a branch).
- A new shared shell library for `_bearer_ok` → P2 → cut; the prior sweep inlines the 1-line guard per
  script, and host scripts cannot source repo files at runtime.

## Scope Check

| Ask item | Disposition | Provenance |
|---|---|---|
| 1. Tier 2 host-deployed (7 + bootstrap) | In: 6 monitors/inngest scripts + bootstrap; **nic-guard out** (#9632) | asked |
| 1. Live-in-apply three | In, with pre-merge shim rows | asked |
| 2. Residual non-Bearer (flip, linkedin, CF drift, configure-auth, x-*, `-u`) | In | asked |
| 2. Flagsmith siblings create/delete/list | In (identical helper; leaving them makes "Flagsmith converted" false) | inferred, justified: same defect, same one-line helper |
| 2. CF-Access in verify-tunnel | In (file already edited in Phase 1) | inferred, justified: no extra file |
| 3. Tier 3 YAML / cloud-init / `env -i` / lint arm | **Split out**; decision recorded on #9597 | asked ("decide") |
| 4. SENTRY_PROJECT | In, by outcome | asked |
| 5. Close/restate #7797 | Restate (Tier 3 split out), keep open | asked |
| track.sh, push-infra-config.sh, infra-config-verify.sh CF-Access | Deferred to Tier 3 follow-up, tracked on #9597 | measured, not asked |

Split rationale: `apply-web-platform-infra.yml` is 485,630 bytes against a 490,000-byte gate and
GitHub's ~512 KB ceiling, and a prior sibling merge crossed that line with comment prose alone
(learning `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so`).
Converting its 12 sites adds bytes and can only be exercised by CI, so it needs its own byte budget
and a lint arm landed first.

## User-Brand Impact

**If this lands broken, the user experiences:** a host monitor (disk, resource, container-restart,
cron-egress, inngest re-arm) silently stops sending its alert or heartbeat after the merge re-installs
it, so an outage or full disk goes unannounced; or a flag/auth script exits non-zero mid-operation.

**If this leaks, the user's workflow is exposed via:** the argv of a short-lived curl (a local
process listing reveals a Resend, Sentry, Cloudflare, Flagsmith, LinkedIn or X credential). The change
removes that vector; a half-converted script that still logs the credential under `bash -x` is the
residual risk, kept closed by the existing xtrace self-refusal.

**Brand-survival threshold:** aggregate pattern

## Implementation Phases

Write the failing rows first (cq-write-failing-tests-before): Phase 0 adds RED rows for every file in
Phases 1-3 to `tests/scripts/test-argv-bearer-sweep.sh`, then each phase turns its rows GREEN. One
push at the end (a push resets a ~35 minute CI cycle).

### Phase 0 — Census, RED rows, lint prerequisites
- Re-run the archived census (`knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py`) and confirm baseline E equals the live set (11 files / 13 sites).
- Read `run_probe`/`evaluate`/shim in `tests/scripts/test-argv-bearer-sweep.sh` (shim at ~125-301 validates stdin against `^header = "[^\"\\]*"$`). **Extend the shim in its own commit, with its harness rows**, so a shim that accepts too much cannot silently make later rows vacuous: (a) decode only `\\` and `\"` in config strings (CR/LF are refused before curl, so `\t`/`\n` need no support); (b) accept `user = "…"` and `data-urlencode = "…"` directives as non-injected and **record their values from stdin** (today `apply_value` discards them); (c) read `--data-binary @file` at curl time so the configure-auth row can assert the secret is in the file and not on argv; (d) model `-I` and `--proto-redir`, which the shim exits 99 on today (`zot-entry-gate.sh`, `zot-image-oci-archive.sh`); (e) replace the Bearer-only `have_auth` match with a per-row expected-credential matcher (Api-Key, CF-Access, OAuth1, `user =` rows would otherwise all get 401).
- Per script, record in the battery the **existing success-path marker and exit code** and the **existing refusal-marker family** (`emit_refusal`-style, e.g. `SOLEUR_DISK_MONITOR_SEND_FAILED`); rows assert the converted script still emits exactly those. Reusing the existing family means no `vector.tf` change (Terraform changes stay "None"); confirm the allowlist matches it before merge.
- One row per converted script/**call site**: token absent from argv; exact config body on stdin; refusal row (token containing CR/LF, quote, space) → curl never invoked, marker emitted, exit semantics unchanged; one must-PASS row with the service's real token shape (Resend `re_…`, Sentry `sntrys_…` with `+/=`, Cloudflare, Flagsmith hex, ghcr JWT dots, LinkedIn, X).
- Name the tests that pin the old argv text and update them in the same phase as their script (`git grep -nE 'Authorization: (Bearer|Api-Key)|CF-Access|-u ' -- '*.test.sh'` per file): at least `soleur-host-bootstrap-observability.test.sh` (post literal AND AC13b2 pinning `Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}` in `fresh-host-boot-trail.sh`), `zot-image-oci-archive.test.sh`, `web-zot-consumer-probe.test.sh` (`-u`), `inngest-rearm-reminders.test.sh`, `scripts/check-cloudflare-token-drift.test.sh` (mock parses `-H CF-Access-Client-Id:*`).
- Check whether the lint requires an xtrace refusal in `zot-image-oci-archive.sh` and the plugin scripts; add one where missing, in the same form as the neighbours.
- Confirm no parity/size test (e.g. `web-host-provisioner-parity.test.sh`, `cloud-init-user-data-size.test.ts`) treats the changed `host_scripts_content_hash` as an error, and that `build-inngest-bootstrap-image.yml` still builds green with the edited bootstrap.

### Phase 1 — Live-in-apply three (pre-merge transport proof)
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` (2 sites, `SENTRY_ACTIONS_RO_TOKEN`; step is `if: always()`, never blocks the apply).
- `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh` (two calls: the Cloudflare Bearer call ~line 69, and the deploy-status call ~line 131 carrying the CF-Access id/secret pair **and** `X-Signature-256`; **failure blocks the apply**, so the refusal path must still exit exactly as today and the success path must be byte-identical downstream). Rows per call site, and one asserting all headers of the second call reach curl in order (they now arrive as one stdin config).
- `apps/web-platform/infra/zot-entry-gate.sh` (`-u user:token`, a release-pipeline gate; no provisioner window; a bad edit shows as a red release/image build, so it gets a pre-merge shim row here, not in Phase 3).
- `apps/web-platform/infra/zot-image-oci-archive.sh` (2 sites, the manifest and blob fetches; anonymous pull token; `build`/`verify` consumers in `zot-image-mirror.yml`, `registry-replace-preflight.sh`).
- Canonical form, `--disable --noproxy '*'` first, process substitution, `_bearer_ok` before the call.

### Phase 2 — Residual non-Bearer argv (plugin and user-run scripts)
- Flagsmith `Api-Key`: `flag-set-role/scripts/flip.sh`, `flag-create/scripts/create.sh`, `flag-delete/scripts/delete.sh`, `flag-list/scripts/list.sh` (copy `user-set-role/scripts/set-role.sh`).
- `community/scripts/linkedin-setup.sh`: three `--data-urlencode` secret fields → config `data-urlencode = "name=value"`. The `_bearer_ok` charset does not fit non-token values: use a `_cfg_ok` that rejects only `"`, `\` and control characters (CR, LF, others), so a valid secret is never refused for its punctuation.
- `community/scripts/x-community.sh` and `x-setup.sh`: OAuth1 `Authorization` header (3 sites). The header contains `"` and spaces, so it uses `_cfg_q` (`\` → `\\`, `"` → `\"`, CR/LF refused); a round-trip row proves the shim decodes it to the exact header, checked against the real curl config parser. Also add the missing `--disable --noproxy '*'` on the unguarded call. Every curl keeps its own `< <(printf …)` (a surrounding `while read` loop would otherwise hand curl the loop's stdin).
- `scripts/check-cloudflare-token-drift.sh`: the CF-Access id/secret headers built into the `args` array (~line 1307) move to a stdin config, **conditional on `$id` being set** (the no-credential control probe must not block reading stdin), with `--disable --noproxy '*'` first. The sibling `check-cloudflare-token-drift.test.sh` mock parses `-H CF-Access-Client-Id:*` and must change with it: make the **minimal mock-only edit** in this PR. Before editing, `gh pr diff 9348` for that file; if the regions overlap, rebase onto it or move the mock change into the battery instead.
- `apps/web-platform/supabase/scripts/configure-auth.sh`: both PATCH bodies (lines ~76 and ~162, carrying RESEND_API_KEY and OAuth client secrets) go through `--data-binary @file` (not `-d @file`, which strips CR/LF) on a 0600 `mktemp -t` file written by `jq` directly (never `-d "$(jq …)"`); keep the explicit JSON `Content-Type`; the trap deletes the file only after the call returns; the repo trap/ownership pattern keeps `lint-trap-tempfile-ownership.py` green. A here-string body is not an option: `--config -` already owns stdin. Confirm with `git grep` that no workflow calls this script (it is run on demand, so nothing changes on merge); both PATCH sites get rows.

### Phase 3 — Host-deployed scripts (one merge, revertable commit group)
- Resend monitors: `container-restart-monitor.sh`, `cron-egress-alarm.sh`, `disk-monitor.sh`, `resource-monitor.sh` (`RESEND_API_KEY`).
- Inngest: `inngest-rearm-reminders.sh`, `inngest-wiped-volume-verify.sh` (`INNGEST_MANUAL_TRIGGER_SECRET`). **`inngest-wiped-volume-verify.sh` is destructive (stop, wipe, start): its `_bearer_ok` guard sits at `read_secret`, before the arm curl and before any wipe step, and refuses through the script's existing `abort`.** A row asserts no `systemctl` call on refusal. Every curl in these loops keeps its own `< <(printf …)` so a `while read` stdin is never consumed by curl.
- `web-zot-consumer-probe.sh` `-u user:token` → config `user = "u:p"` using `_cfg_ok` on user and password (`zot_consumer_probe_install` is its provisioner). `zot-entry-gate.sh` is in Phase 1.
- `soleur-host-bootstrap.sh` (`#!/bin/sh`): edit the embedded ingest-post script at ~line 1049 with the **pipe form** (`printf … | curl --config -`; `printf` is a builtin so the token is never on argv, curl drains stdin, and under `sh -e` without `pipefail` only curl's status counts). The post is already an `if/elif/elif/else` that sets `BS_WHY`: do **not** add an `else`; add an explicit `bad_token_shape` branch **before** the `elif [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ]` arm so a malformed token is not misreported as `unpinned_url`. POSIX only: a bare `case` with no `local`, `LC_ALL=C` set for the bracket class, `[ ]` not `[[ ]]`. Refusal is **skip-and-report, never fail-stop** (runs under `set -e` from cloud-init; the post sits above the dark-host detector). Update `soleur-host-bootstrap-observability.test.sh` (post literal and AC13b2).
- Each refusal keeps the script's existing exit semantics and emits its existing marker family (no new marker, so no `vector.tf` change).
- web-2: `deploy_pipeline_fix_web2` re-delivers the inngest pair; the monitors and bootstrap reach web-2 only through the baked image at its next rebirth. Record that web-2 stays on the old copy for those until then (matches #7898 §1). The bootstrap's latent-until-rebirth fuse is covered by running its embedded script under `sh -n` and real `dash` in CI-run tests.
- These edits are a separate commit group (revertable alone); the merge is the single provisioner window. **Rollback:** revert that commit group and push; the same provisioners re-run the previous content. Deferred siblings (`track.sh`, `infra-config-verify.sh`, `push-infra-config.sh`) keep their CF-Access credentials on argv until the Tier 3 follow-up lands; the PR body says so.

### Phase 4 — Ratchet, docs, tracking
- Delete the converted lines from `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` (deletion only, never edit counts upward); it must end with the single `web-private-nic-guard.sh	1` line. Do not run `--write-baseline-e` against files #9632 touches.
- Rewrite the body of #9597 to the restated remaining scope (Tier 3 measured at 21 files / 55 sites, deferred CF-Access siblings, YAML + non-Bearer lint arm, nic-guard pending #9632) — #9597 stays the single Tier 3 tracker; comment on #7797 with the restated scope and leave it open. (The learning is written by the `compound` step, not planned here.)
- SENTRY_PROJECT (a PR-body line, not a phase): `gh run list --workflow sentry-audit-gate.yml` → latest green run; confirm its log shows the audit step ran past the script's `case "$SENTRY_PROJECT" in ''|web-platform|soleur-web-platform)` pin (never grep the log for the value). Record "class membership verified by outcome (run <id>); equality with the Doppler value is not provable from a masked secret", or "unverifiable" if no run reached the pin.

## Files to Edit

- `apps/web-platform/infra/{container-restart-monitor,cron-egress-alarm,disk-monitor,resource-monitor,inngest-rearm-reminders,inngest-wiped-volume-verify,soleur-host-bootstrap,web-zot-consumer-probe,zot-entry-gate,zot-image-oci-archive}.sh`
- `apps/web-platform/infra/scripts/{fresh-host-boot-trail,verify-tunnel-ingress-origin}.sh`
- Tests pinning the old argv text: `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`, `zot-image-oci-archive.test.sh`, `web-zot-consumer-probe.test.sh`, `inngest-rearm-reminders.test.sh`, `scripts/check-cloudflare-token-drift.test.sh` (mock only)
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh`, `flag-create/scripts/create.sh`, `flag-delete/scripts/delete.sh`, `flag-list/scripts/list.sh`
- `plugins/soleur/skills/community/scripts/{linkedin-setup,x-community,x-setup}.sh`
- `scripts/check-cloudflare-token-drift.sh`
- `apps/web-platform/supabase/scripts/configure-auth.sh`
- `tests/scripts/test-argv-bearer-sweep.sh`
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`
- Owning `*.test.sh` of any converted script that asserts the old argv text (find with `git grep -l 'Authorization: Bearer' -- '*.test.sh'` per file)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-argv-bearer-sweep-tier2-residual/{tasks.md,session-state.md,decision-challenges.md}`

## Open Code-Review Overlap

None. (`code-review`-labelled open issues were searched for every planned path; no body names any of them.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide) exits 0 and baseline E contains exactly one non-comment line (`web-private-nic-guard.sh`).
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 with one row per converted site (row count recorded in the PR body) and the three live-in-apply scripts each have a row that fails when the old argv form is restored.
- [ ] For each converted script: token absent from argv; stdin body exact; newline/quote/space token → curl not invoked and the skip/refusal marker emitted (rows named in the battery).
- [ ] `git grep -nE -- '(-H|--header)[ =]+"?(Authorization: (Bearer|Api-Key)|CF-Access-Client)' -- <converted files>` returns no hit.
- [ ] `bash scripts/lint-shell-trace-credential-refusal.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/lint-supabase-deprecated-endpoints.sh`, `python3 scripts/lint-trap-tempfile-ownership.py` and `--check-highwater`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `bash scripts/guard-vacuity-floor.test.sh` all exit 0.
- [ ] `gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges origin/main..HEAD"` exits 0.
- [ ] PR body: `Ref #7797`, `Ref #9597` (no `Closes`), review coverage stated honestly, and the web-2 note for the monitors and bootstrap.

### Post-merge (verified by outcome, not by "apply succeeded")
- [ ] The infra apply run for the merge commit is green and each provisioner named in Phase 3 reports success.
- [ ] For each converted host script that has a steady success/heartbeat marker (recorded per script in Phase 0), that marker appears in Better Stack within one timer interval after the merge (queried with `scripts/betterstack-query.sh`, no SSH). Alert-only monitors with no steady marker (e.g. disk/resource on a quiet host) are verified by their pre-merge battery rows and the green provisioner run, not by absence of a marker.
- [ ] #9597 body restated; #7797 commented and left open.

## Observability

```yaml
liveness_signal:
  what: each converted monitor's existing heartbeat/ingest marker (disk, resource, container-restart, cron-egress, inngest re-arm) keeps arriving in Better Stack after the merge
  cadence: each monitor's existing timer interval
  alert_target: existing Better Stack heartbeat/alert routes for those monitors
  configured_in: apps/web-platform/infra/ (per-script units and vector.tf allowlist)
error_reporting:
  destination: stdout/logger markers already forwarded by Vector; refusal adds one skip-and-report marker per script
  fail_loud: refusal reports and keeps the script's existing exit code; the bootstrap path never fail-stops
failure_modes:
  - mode: token fails the shape guard (valid token, unexpected character) so alerts stop
    detection: the refusal marker in Better Stack
    alert_route: existing Better Stack alert for the script's marker family
  - mode: provisioner re-run fails on merge
    detection: red apply-web-platform-infra run
    alert_route: workflow failure notification
  - mode: converted live-in-apply script mis-sends its credential
    detection: battery row fails pre-merge; verify-tunnel-ingress-origin exit blocks the apply
    alert_route: CI
logs:
  where: Better Stack (Vector-forwarded journald/stdout), CI logs for the apply
  retention: Better Stack plan default
discoverability_test:
  command: grep -c '^apps/' scripts/lint-shell-trace-credential-refusal-e.baseline.txt
  expected_output: 1
```

## Guard Contract

### Guard 1 — argv-credential battery and baseline E ratchet

**Property.** No curl in a converted script carries a credential on its argument list, and no
credential-shaped value can inject a config directive.

**Assembly.** Every curl call in each converted file, including calls reached through helpers
(`fs_api`, `mgmt_curl`, `bs_api`, the embedded bootstrap script, the `args` array in the drift
probe) — enumerated by running the census script over each whole file, not by the line numbers in
this plan. Two chokepoints: the battery's PATH shim (observes argv and stdin) and Rule E's repo-wide
run against baseline E (equality on path and count).

**Mutation matrix.**

| # | Edit (must drive RED) | Reddens |
|---|---|---|
| 1 | Restore an argv credential (Bearer header, `-u user:token`, CF-Access header) at one converted site, **including a second site added after a compliant first** (e.g. the 2nd call of `zot-image-oci-archive.sh` or `verify-tunnel-ingress-origin.sh`) | battery token-in-argv row for that script and Rule E equality |
| 2 | Make `_bearer_ok` accept a newline | refusal row (injection recorded) |
| 3 | Move `_bearer_ok` after the curl call (for `inngest-wiped-volume-verify.sh`, after the wipe step) | refusal row (curl invoked, or `systemctl` called, on a malformed token) |
| 4 | Drop one script from the battery's dispatch list | row-count floor / vacuity floor |

**Harness rows.** (a) Make the shim record stdin to the wrong path → every stdin row reddens.
(b) Make the shim stop decoding `\"` → the OAuth1 round-trip row reddens. Must-PASS non-canonical
input: a token using every permitted punctuation character (`a.b_c~d+e/f=g-h`), and an OAuth1 header
containing both `"` and `\`.

**Anchor.** Baseline E is shrink-only by equality with the live offender set, and `--check-highwater`
compares against main; a weakening must also move the lint's own equality, which a reviewer sees as a
non-deletion diff in the baseline file.

## Infrastructure (IaC)

### Terraform changes
None. No `.tf` edits. The hashed files (`disk-monitor.sh`, `resource-monitor.sh`,
`container-restart-monitor.sh`, `cron-egress-alarm.sh`, `inngest-*.sh`, `web-zot-consumer-probe.sh`)
change content, which re-runs their existing SSH-provisioner `terraform_data` resources on merge.

### Apply path
(b) existing idempotent provisioners. Blast radius: web-1 services re-installed in place; hosts are
not replaced (`user_data` carries `ignore_changes`). `soleur-host-bootstrap.sh` changes the baked
`host_scripts_content_hash` only for fresh boots.

### Distinctness / drift safeguards
No change to dev/prd distinctness or state. No new secrets or variables.

### Vendor-tier reality check
No new vendor resource.

## Test Scenarios

1. Valid token → curl receives `--config -`, stdin carries the exact `header = "…"` line, argv has no token.
2. Token with `\n`, `"`, space → refusal marker, no curl call, exit code as before.
3. Bootstrap embedded post run under `sh -e` (real dash): token bound → posts; malformed token → `bad_token_shape` reported, **exit 0**, never `unpinned_url`; no token → existing branch unchanged.
4. configure-auth: secret present in the 0600 body file (`--data-binary @file`), absent from argv, both PATCH sites; file removed on exit and on error, and not before the call returns.
5. OAuth1 header with quotes round-trips through the shim's `\\`/`\"` decoder byte-for-byte, cross-checked against the real curl config parser.
8. `inngest-wiped-volume-verify.sh` with a malformed secret: refuses at `read_secret`, no `systemctl` call, volume untouched.
9. `check-cloudflare-token-drift.sh`: with `$id` unset, the control probe makes no `--config -` call and does not block on stdin.
6. `registry-replace-preflight.sh` / `zot-image-mirror` build path still fetches manifest and blobs with the shim (pull token on stdin).
7. verify-tunnel-ingress-origin: success path unchanged; refusal path exits as today (apply stays blocked).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `--changed` and explicit paths bypass the baselines, so any touched listed script must be fully remediated in the same PR; do not leave a half-converted file.
- Never `printf … | curl` in bash scripts (a consumer that does not read stdin gives SIGPIPE); the `#!/bin/sh` bootstrap is the sole pipe-form exception and curl always drains stdin under `--config -`. Each curl gets its own `< <(printf …)`; never share one config across calls.
- `_bearer_ok` covers token shapes only. Anything with spaces, `"`, `:` or `\` (user:password, LinkedIn secrets, OAuth1 header) uses `_cfg_ok`/`_cfg_q`; a too-narrow charset silently refuses a valid credential and the monitor or script goes quiet.
- Keep `_bearer_ok` verbatim (`local LC_ALL=C; case …`) so the lint equality holds; the `#!/bin/sh` copy has no `local`.
- If the merge-queue/CI base moves (e.g. #9632 merges during the ~35 minute cycle), baseline E equality fails for a reason unrelated to the code: rebase, re-run the lint, do not use `--write-baseline-e`.
- Every secret comparison and log check in this work must avoid printing values (no `echo`, no `grep` of a value, no `set -x`).
- Do not run `--write-baseline-e` while #9632 is unmerged; edit baseline E by deleting only the lines this PR converts.
- Merging triggers the push-driven infra apply: after merge, verify by outcome (markers in Better Stack), not by the apply's exit code alone.
- If #9632 merges first, rebase: baseline E then loses the nic-guard line and the equality check must be re-run.
