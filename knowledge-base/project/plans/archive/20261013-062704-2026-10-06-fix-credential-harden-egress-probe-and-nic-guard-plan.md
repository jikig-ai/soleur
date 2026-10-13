---
title: "fix(infra): credential-harden cron-egress-enforce-probe.sh and web-private-nic-guard.sh (xtrace refusal, curl transport confinement, ingest-URL pin)"
type: fix
date: 2026-10-06
slug: credential-harden-egress-probe-and-nic-guard
branch: feat-one-shot-a3-credential-hardening-egress-probe-nic-guard
issue: 9217
closes: none
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): credential-harden the egress-enforce probe and the web NIC guard

Spec lacks a valid `lane:` (no spec.md for this branch), so it defaults to `cross-domain` (fail-closed).
PR body uses `Ref #9217`, `Ref #7005`, `Ref #6601`, `Ref #7376`, `Ref #7797`, `Ref #9482`; never `Closes` (every one
is a standing tracker that stays open after this pass). Draft PR: #9632.

## Enhancement Summary

**Deepened on:** 2026-10-06
**Method:** deepen gates 4.5-4.12 run mechanically (user-brand impact present with a valid threshold; observability
block present and its probe executable; no PAT-shaped tokens; no UI surface; no store or connection so no encryption
posture; Guard Contract lint green with a structural assembly; Scope Check count 1 and compliant; no downtime-class
trigger); every cited line, ADR and rule id re-read at its source; four review agents (security-sentinel,
observability-coverage-reviewer, architecture-strategist, test-design-reviewer) over the finished plan.

### Key improvements applied

1. Fixed a false detection claim: the per-host uptime monitor cited for the cron-probe failure was retired
   (`uptime-alerts.tf:138`); detection is now the boot trail, and the no-alert modes are stated as such (F7, F8).
2. Corrected the apply-path claims: `ignore_changes` yields NO planned change for `hcloud_server.web`; a green apply can
   hide a skipped SSH leg and a no-op arm step, so AC11/AC12 read the run summary and Better Stack rows; running web-2
   keeps the old guard; the existing off-host image-coherence preflight already covers the baked-script hash trap.
3. Narrowed Guard 1's claim honestly: the property covers the two scripts; the unit wrapper and the deploy-owned env
   file sourced as root sit outside it (F5, F6) instead of being claimed clean.
4. Fixed seven test-design defects before any test exists (a pre-existing row would have flipped in RED from an `env`
   lookup under a stripped PATH; the pinned-POST row is a positive control, not RED; exported variables would have
   leaked between rows; stub argv logging order and format; line-anchored cron stub assertions; the mktemp trap lint;
   non-vacuity of the parity and baseline rows).
5. Added the Network-Outage deep-dive (resource-shape trigger) and three carrier-census rows.

### New considerations discovered

- `doppler run` injects the whole prd config into the guard, so TLS-trust environment variables (F2) are more
  realistic than first weighed.
- The Sentry-curl deferral (F1) is acceptable on the merits, but the call site runs with `HOME=/root`.

## Overview

Pass 1 of the merge-queue flakiness series. The two scripts that carry the last deferred file-exact
`grep -q` rows at the end of `SWEEP_DEFERRALS` (`cron-egress-enforce-probe.sh` 2 hits,
`web-private-nic-guard.sh` 4 hits) cannot be edited by the later conversion pass until
`python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` passes on them. This pass
pays that debt and nothing else: it hardens the credential handling of both scripts and removes them from the
lint baselines. It converts no `grep -q`, and the deferral rows stay at their current ceilings (2 and 4).

Measured today (explicit-path run, which bypasses the baselines exactly as `--changed` does):

| File | Findings |
|---|---|
| `cron-egress-enforce-probe.sh` | Rule A: binds a live credential (`doppler secrets get`) with no xtrace refusal |
| `web-private-nic-guard.sh` | Rule A (no refusal); Rule D (bearer `curl` lacks `--disable` first and `--noproxy '*'`); Rule D (sends to env-settable `$INGEST_URL`, never pinned) |

A prototype of the exact edits below, applied to scratch copies outside the repo, takes the lint to
`OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)` (rc 0), and `lint-shell-capture-exit.py` reports 0
new findings on both. That prototype is evidence the design is sufficient, not a substitute for the tests.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (command or file) | Plan response |
|---|---|---|
| `lint-shell-trace-credential-refusal.py --changed` is "a REQUIRED check in ci.yml" | The step sits in the `lint-bot-statuses` job (`.github/workflows/ci.yml:231`), which the file itself documents as advisory; `grep -c lint-bot-statuses scripts/required-checks.txt` is 0 and the live "CI Required" ruleset (id 14145388, 23 contexts) names no `lint-bot-statuses` context (`gh api repos/jikig-ai/soleur/rulesets/14145388`). The only REQUIRED lane is the repo-wide run `lint-shell-trace-credential-refusal-repo` (`scripts/test-all.sh:4761`), baseline-suppressed. A red advisory `merge_group` job does not eject a PR (`plugins/soleur/skills/ship/references/merge-queue-dequeue.md`) | Keep the pass: `work` SKILL step 6.5 makes touching a baselined script owe its whole debt, and the baseline suppresses by FILE, so a hardened file left in the baseline can regress silently. State the correction in the PR body and on tracker #9217; do not claim the pass unblocks a required gate |
| "Class W deploy files auto-apply on merge" (`apply-deploy-pipeline-fix.yml`) | Neither file is in that workflow's `paths:` filter or in `terraform_data.deploy_pipeline_fix`'s `triggers_replace` (`grep -n 'cron-egress\|nic-guard' .github/workflows/apply-deploy-pipeline-fix.yml` returns nothing; `server.tf` is NOT edited here, so its `server.tf` path trigger does not fire either). What does fire is listed in `## Infrastructure (IaC)` | `[skip-deploy-fix-apply]` is irrelevant to this PR and is never used. Blast radius stated below |
| The two files carry `grep -q` hits that block editing | Both rows are `=` (2 and 4) in `.claude/hooks/grep-q-pipe-guard.test.sh`; the edits add no `grep` at all, so the ceilings hold | Verify by running that suite; do not touch the rows |
| "`--disable` and `--noproxy '*'` on every credentialed curl" | In `cron-egress-enforce-probe.sh` the only credentialed curl is the Sentry POST (`X-Sentry-Auth` key from the DSN). Lint Rule D does not see it (header name not in `CURL_AUTH_HEADER`, variable `$KEY` has no prefix before `_KEY`), and `cron-egress-enforce-probe.test.sh` "Sentry TRANSPORT parity" pins that exact `curl -m 10 --retry 3 -sf -X POST ...` line byte-identical to `soleur-host-bootstrap.sh:58`; a third copy lives in `workspaces-luks-emit.sh:361` | Leave that curl unchanged in this pass (a one-file edit reds the parity guard, and the other two copies are a baked boot installer and a file under LUKS security review). Recorded as a User-Challenge in `decision-challenges.md` and as follow-up F1 (with a filed issue, per `wg-defer-only-after-inline-triage`) |
| Research-agent claim: edits "could cross the 23,800 B user_data budget" and `cron-egress-enforce-probe.sh` is hashed into `private_nic_guard_install` | False. `user_data` carries only `host_scripts_content_hash` (64 hex chars, `server.tf:311-312`, `:401`); script bytes are baked into the image (`Dockerfile`), so `cloud-init-user-data-size.test.ts` is unaffected. `triggers_replace` of `private_nic_guard_install` (`server.tf:896-908`) hashes only `web-private-nic-guard.{sh,service,timer}`, the private IP, the ingest URL and a token digest; `cron-egress-enforce-probe.sh` appears once in `server.tf` (`:201`, `host_script_files`) | Run `cloud-init-user-data-size` anyway as a check; no byte-budget work |

## Research Insights

**Premise Validation.** Cited trackers #9217, #7005, #6601, #7376, #7797 are all OPEN (`gh issue view`); #9482 is the
merge-queue decision-challenge issue (OPEN) and is cited only as the series umbrella; #8022, #7969, #7215, #5634 and
#7432 are OPEN. Cited paths exist on `origin/main`. Nothing in the brief is already resolved. Two premises were
stale (advisory-not-required; Class W scope), see the table above.

**ADR corpus check.** Mechanisms used here are the ones the repo already adopted: the carried xtrace self-refusal
(ADR-202), no env-declared test seam for a destination pin (ADR-214), fail-closed on unparseable input (ADR-157).
Nothing in `knowledge-base/engineering/architecture/decisions/` lists the unconditional refusal or the equality pin
among rejected alternatives. In-repo precedent for the exact pin shape is `soleur-host-bootstrap.sh:1034-1049`
(`readonly INGEST_URL_PINNED=...`, `[ "$INGEST_URL" = "$INGEST_URL_PINNED" ]`, `curl --disable --noproxy '*'`) with
parity test `fresh-boot-ready.test.sh` S4a/S4d and mutation row "bearer sent to any non-empty url".

**Property List.**

1. P1 — neither script executes a command that expands a credential while shell tracing is on.
2. P2 — the Better Stack bearer token (and the secret heartbeat URL) leave the NIC guard only through a curl that
   skips `~/.curlrc` and ignores proxy environment variables.
3. P3 — the bearer token is only ever sent to the one pinned Better Stack source URL, whatever the environment says.
4. P4 — both files stop being grandfathered, so the repo-wide run guards them from regrowth.
5. P5 — no later-pass edit is blocked by this lint, and no deferral ceiling moves.

**Cut List** (mechanism proposed or implied, what covers it):

- Conditional refusal `[ -n "${BETTERSTACK_LOGS_TOKEN:+x}" ]` for the NIC guard — CUT. The refusal must also cover
  `WEB_NIC_GUARD_URL` (a secret-bearing URL, `doppler_secret.web_nic_guard_url`), which Rule C's credential-name
  regex never sees; the unconditional form (already used verbatim at `soleur-host-bootstrap.sh:26` and by the
  lint's own remedy text) covers every credential by construction and is what the cron probe must use anyway (it
  ACQUIRES via `doppler secrets get`, so a `${VAR:+x}` hatch is open by construction).
- Host-suffix pin (`*.betterstackdata.com`, as `scripts/betterstack-ingest-probe.sh` does) — CUT. The exact-equality
  pin against a single `readonly` literal is already the in-repo shape for this very destination, and a suffix
  pin would send the token to any Better Stack tenant.
- New suite files — CUT. Extending the two existing suites needs no `test-all.sh` registration and no
  `lint-orphan-test-suites.sh` change.
- `unset SSLKEYLOGFILE CURL_CA_BUNDLE ... CURL_HOME` and `GIT_TRACE*` hardening (precedent:
  `web-probes-token-rotation` verifier) — CUT from this pass; follow-up F2 (neither script runs git; the TLS-trust
  environment is a separate property from the three the brief names).
- Hardening the IMDS curl (`169.254.169.254`) — CUT. It carries no credential.
- Moving the bearer off argv (`curl -K -`, precedent `cloud-init-inngest.yml:327`) — WAS CUT, DONE IN THE REVIEW ROUND: the sibling Rule E sweep
  merged with this guard baselined, and `--changed` bypasses baselines, so the bearer now rides `--config -` (see `decision-challenges.md`).
  The heartbeat URL is still on argv (#9639).

**Carrier census** (what else reads or pins these two files; found by grepping basenames AND fragments of the old
lines across every `*.test.*`, per `knowledge-base/project/learnings/test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`):

| Consumer | Pin or dependency | Effect of this plan's edit |
|---|---|---|
| `server.tf:173-310` `host_script_files` (both) -> `host_scripts_content_hash` (`:311`) -> `user_data` (`:391-401`) | hash only, 64 B | text of the user_data changes; `hcloud_server.web` carries `ignore_changes = [user_data, ...]` (`server.tf:596-605`) and only `server.tf:391` renders `cloud-init.yml`, so no replace and no size change |
| `server.tf:891-951` `terraform_data.private_nic_guard_install` (NIC guard only) | `triggers_replace` over the guard, unit, timer, private IP, ingest URL, token digest | resource replaces; its provisioner re-runs on web-1 (see IaC section) |
| `Dockerfile:287,300`, `.dockerignore:65,78` (both) | COPY into the image | a new image is built by `web-platform-release.yml` (`apps/web-platform/**`) and deployed the normal way |
| `soleur-host-bootstrap.sh:51-52,79,81,99,179` | install and 0755 assert loops; Sentry transport parity | transport lines untouched, so parity holds |
| `cloud-init.yml:644` (NIC timer enable), `:807` (probe invocation, `poweroff -f` on non-zero) | boot wiring | unchanged text; the probe's new exit 78 is a non-zero exit, same branch |
| `cron-egress-enforce-probe.test.sh` | `'^set -e'`, probe curl regexes, Sentry TRANSPORT parity block, sibling-host parity, delivery lockstep | all still true after the edit; new rows extend this file |
| `web-private-nic-guard.test.sh` | runs the real file with `BETTERSTACK_INGEST_URL="https://synthetic.invalid/ingest"` (`:151`) | that destination will be REFUSED by the pin, so the harness must feed the pinned literal (derived from `zot-registry.tf`, never retyped) |
| `betterstack-send-failed-alert-mutation.test.sh` M18 (`:355-361`) | mutates the NIC guard's `--data-raw "{\"message\":\"$LINE\"}"` payload text; the guard is in its sandbox population (`:74`) | payload text is not edited, so the anchor survives; run the suite |
| `betterstack-send-failed-alert.test.sh` (the guard M18 drives) | walks `apps/web-platform/infra/*.sh` for Better Stack posters | run it; the new flags sit between `curl` and `-fsS` |
| `fresh-boot-parity.test.sh:109-113`, `doppler-injection-bound.test.sh:232`, `arm-heartbeats*.test.sh`, `plugins/soleur/lib/heartbeat-manifest.ts:206-210` | name-level or unit-level references | unaffected; run |
| `web-probe-envwrite.sh:48-49` (fresh-host env file writer), `vector.toml:270` and `web-private-nic-guard.service:22` (`SyslogIdentifier=web-nic-guard`, the Source 4 shipping key), `workspaces-luks-emit.sh:11-23,50` (header claims to mirror the probe's emit boundary), `scripts/followthroughs/l3-probe-armed-6438.sh:62` and `web2-standby-soak-6459.sh:70` (read the NIC-guard heartbeat state) | env value, log identifier, comment parity, heartbeat readers | unaffected by the edits; the env writer must carry the pinned value (it does, from the same local); the log identifier must stay on the refusal line's stderr path |
| `.claude/hooks/grep-q-pipe-guard.test.sh:458-463` (deferral rows 2 and 4) | `=` ceilings | no `grep` added; comment text updated |
| `scripts/lint-shell-trace-credential-refusal.baseline.txt` (lines 10, 21), `...-d.baseline.txt` (line 17) | file-keyed suppression | entries removed (drawdown) |
| `scripts/lint-shell-trace-credential-refusal.test.sh` | scaffold and mutation fixtures; no per-file baseline count found | run it after the baseline edit |

**Touched-file lints in `ci.yml` that can fire on these paths** (checked before editing):

| Lint | Fires on | Verdict |
|---|---|---|
| `lint-shell-trace-credential-refusal.py --changed` (advisory job) and the repo-wide run (required `test` shard) | both `.sh` files | green after the edits; the repo-wide run stays green with the baseline entries removed |
| `lint-shell-capture-exit.py` | `.sh` | 0 new findings on the prototype |
| `lint-trap-tempfile-ownership.py` (rule c is added-lines scoped to `mktemp`) | `.sh` | no `mktemp` added |
| `lint-orphan-test-suites.sh` | new `*.test.sh` | none created |
| `lint-infra-no-human-steps.py --changed` | `knowledge-base/` docs only (not `.sh`) | this plan, tasks, decision-challenges and learnings are the exposure; run on each before commit (Item E, a pre-existing finding, is deferred and not touched) |
| `lint-guard-contract.py` | plan files carrying `## Guard Contract` | run on this plan |
| `grep-q-pipe-guard` (inside the required `test` shard) | `.sh`, `.yml`, `.tf` | new test rows must not add a pipe-fed `grep -q` (use `grep -c ... >/dev/null` or a here-string), because the `apps/web-platform/*.test.sh` row is `<= 180` slack, not tight |

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is edited (`server.tf` in particular is untouched, so `apply-deploy-pipeline-fix.yml` does
not fire through its `server.tf` path trigger either).

### Apply path

(b) existing automation, no new mechanism. On merge to `main`:

1. `apply-web-platform-infra.yml` fires (`on.push.paths: apps/web-platform/infra/**`). Its token-gated leg for the
   SSH-provisioned set includes `-target=terraform_data.private_nic_guard_install`
   (`.github/workflows/apply-web-platform-infra.yml:1192`), so that resource replaces because the guard's sha256 is
   in `triggers_replace`. Its provisioner copies the guard, unit and timer to web-1, rewrites
   `/etc/default/web-private-nic-guard` (umask 0137, same values), reloads the systemd manager and (re)enables the
   timer unit, all idempotent. No container restart, no host restart, no host replace. A timer tick that lands
   during the non-atomic env-file rewrite can read an empty `EXPECTED_IP` and exit 1 once; the next tick recovers
   (a property of every re-provision of this resource, not introduced here).
2. `hcloud_server.web` carries `ignore_changes = [user_data, ...]` (`server.tf:597`), so the new
   `host_scripts_content_hash` produces NO planned change for it: no replace, no downtime. The evidence is the
   absence of any `hcloud_server.web` line in the run's `Plan:` output (post-merge AC11). Nothing else re-plans:
   `host_script_files` and `host_scripts_content_hash` are referenced only in `server.tf` (`:173-310`, `:311`,
   `:401`), no module reads them, and the only `file()` of either script is the NIC guard's own `triggers_replace`.
3. `web-platform-release.yml` (`apps/web-platform/**`) builds and deploys a new image the normal way; both scripts
   reach a FRESH host only through that image (`soleur-host-bootstrap.sh` verifies the baked set against the hash at
   boot and aborts loudly on a stale image, the existing ADR-080 trap that applies to every edit of a baked
   script). A fresh-host dispatch is protected by an existing gate: `web_host_create` and `web_host_replace` run
   `apps/web-platform/infra/scripts/host-image-coherence-preflight.sh` off-host BEFORE any destructive step
   (`apply-web-platform-infra.yml:5074`, `:5504`), so a dispatch between this merge and the new image deploying
   fails loudly and early; a web-2 replace should wait for the new release or pin `image_tag` to it.
4. `cron-egress-enforce-probe.sh` has no running-host delivery path: it executes only at fresh-host boot. The first
   execution of the hardened copy is the next fresh web-host boot.
5. The running web-2 keeps the UNHARDENED NIC guard until it is replaced: `private_nic_guard_install` targets
   `web["web-1"]` only (`server.tf:902`) and `deploy_pipeline_fix_web2` (`server.tf:2135`) has no NIC-guard
   delivery. Fresh hosts get the hardened copy through the image; the running web-2 does not. Stated here so
   the pass is not read as fleet-wide.
6. Gates on that apply, so a green merge is not proof it ran: the SSH-provisioned leg runs only when
   `CI_SSH_ACCESS_TOKEN_ID` is readable in Doppler `prd_terraform` (`apply-web-platform-infra.yml:1118-1146`); when it
   is absent the leg is skipped, the run stays green and only a notice goes out (`:1255-1282`). The heartbeat arm
   step is a no-op for an already-armed monitor (`arm-heartbeats.sh:411-414`), so a refusing guard would not fail
   the apply and would surface as heartbeat absence after about 480 s (`arm-heartbeats.sh:488-491`). Post-merge AC11
   and AC12 therefore read the run summary for "SSH stage: ran" and the Better Stack rows, not just the run
   conclusion. Also: the PR must not carry a commit-message line that is exactly `[skip-web-platform-apply]` or
   `[ack-destroy]` (`:326-350`), and `infra-validation.yml` also fires on `apps/*/infra/**`.

### Network-Outage Deep-Dive (resource-shape trigger)

The post-merge apply drives a resource whose provisioners use `connection { type = "ssh" }`. L3 firewall: the CI
runner reaches web-1 over the Cloudflare tunnel SSH bridge (`.github/actions/cf-tunnel-ssh-bridge`, header of
`apply-web-platform-infra.yml:316-318`), not through `var.admin_ips`, and this plan changes no firewall, DNS or
tunnel resource. L3 DNS/routing: unchanged (bridge host key pinned via `local.web_1_ssh_host_key`). L7 TLS/proxy and
L7 application: not exercised by this change beyond the existing provisioner. Verification artifact: the apply
run's "SSH stage" summary line (AC11). Not verified here and not claimed: current egress-IP reachability of web-1,
because the bridge makes it irrelevant to this path.

`[skip-deploy-fix-apply]` is not used and has nothing to skip here.

### Distinctness / drift safeguards

The pin literal equals `local.betterstack_logs_ingest_url` (`zot-registry.tf:127`), the value `server.tf:944`
writes into the env file and `server.tf:434` renders for cloud-init (and `web-probe-envwrite.sh:48` writes on a
fresh host); a parity row in the suite reads the `.tf` literal at test time. A rotation of that Better Stack
source then reds the suite instead of silently degrading to "refused" at runtime.

### Vendor-tier reality check

Not applicable (no vendor resource is created or changed).

## Architecture Decision (ADR/C4)

Skipped: no architectural decision. The plan applies ADR-202 and ADR-214 as written; no ownership or trust boundary
moves, no new substrate, no reversal of an ADR. A competent reader of the existing ADRs and C4 would not be misled
after this ships.

## Implementation Phases

### Phase 0 — RED (tests first, `cq-write-failing-tests-before`)

Extend the two existing suites; create no files. Every new row below must FAIL against the unmodified scripts for
the stated reason before Phase 1 starts; record the red output in the PR body. Plan review (DHH, Kieran,
code-simplicity) cut the in-suite mutation runner, exact floors, a real-curl listener row, lint-echo rows and
placement-parser rows as ceremony; the mutation matrix below is instead executed ONCE, by hand, on scratch copies
during RED/GREEN, and the result is recorded in the PR body (see `## Guard Contract`). Target about 100 test lines.

**`apps/web-platform/infra/web-private-nic-guard.test.sh`** (new section header `--- #7797 hardening ---`):

- Harness changes (none alters an existing assertion's meaning), all required by the rows below because today
  `run_guard` hard-codes `bash "$SUT"` and discards stdout, stderr and rc:
  (i) `run_guard` takes optional `SUT_UNDER_TEST` (default `$SUT`), a launch-flags array (`bash` flags such as
  `-x`) and an `EXTRA_ENV` array passed through `env`, and records rc plus stdout and stderr into `$RC`, `$OUT`,
  `$ERR`. `ENV_BIN` and `BASH_BIN` are resolved by absolute path once, next to `TIMEOUT_BIN`: the hide-ip arm
  (T3) runs with `PATH=$nobin`, which has no `env`, so an `env` call by name would flip a pre-existing row to
  rc 127 in RED. Everything that varies (`STUB_POST_RC`, `STUB_PING_RC`, `INGEST_URL`, `INGEST_URL_PINNED`,
  `BASH_ENV`, `SHELLOPTS`) travels ONLY through `EXTRA_ENV`, never exported in the test shell (an exported evil
  `INGEST_URL_PINNED` would poison X3c, X4 and every later row), and `$STUB_ARGV` is truncated per run;
  (ii) the `curl` stub logs, BEFORE its early IMDS exit, its argv one argument per line with `printf '%s\n' "$a"`
  (never `echo`: `-n` is a valid curl flag), calls separated by a marker line, to `$STUB_ARGV`, because the
  payload and the `Authorization: Bearer ...` header both contain spaces; the IMDS call is identified by the
  stub's own `*private-networks*` predicate; it also honours
  `STUB_POST_RC` and `STUB_PING_RC` so the `post || post` and heartbeat `||` fallback copies are reachable (the
  stub exits 0 unconditionally today);
  (iii) the synthetic destination becomes `PINNED_URL`, read at test time from `zot-registry.tf` with the `sed`
  expression `fresh-boot-ready.test.sh` S4d already uses (never retyped), and `BETTERSTACK_INGEST_URL="$PINNED_URL"`
  replaces `https://synthetic.invalid/ingest`. Before the pin exists this is a no-op for the old script, so every
  existing row stays green in RED.
- **X1 xtrace refusal fires** (Guard 1): a loop over three launch forms (each form its own labelled `assert`, and a
  failing rc check prints the rc and the first `$ERR` line so a `timeout` rc 124 is not misread as a refusal bug;
  `$TMP/xt.env` is created once before the loop), each with `EXPECTED_IP`, a synthetic token
  `SYNTH-TOKEN-7797` and heartbeat URL `https://synthetic.invalid/beat/SYNTH-BEAT-7797` in the environment:
  `bash -x "$SUT"`, `env SHELLOPTS=xtrace bash "$SUT"`, and `env BASH_ENV="$TMP/xt.env" bash "$SUT"` where `xt.env`
  holds `set -x`. Assert per form: rc is exactly 78; a stderr line NOT beginning with `+` contains
  `refusing to run under xtrace` (xtrace itself echoes `+ printf '[FATAL] refusing ...'`, so an unanchored match
  would pass even if the message never printed; extract with `grep -v '^+' <<<"$ERR" | grep -c ... >/dev/null`,
  which is not a pipe-fed `grep -q`); neither stdout nor stderr contains `SYNTH-TOKEN-7797` or
  `SYNTH-BEAT-7797`; `$STUB_EMIT`, `$STUB_PING` and `$STUB_ARGV` are empty (the stub `curl` is on PATH, so a leak
  would be recorded).
- **X1b unconditional**: one `bash -x` launch with NO credential and `EXPECTED_IP` unset in the environment still
  exits 78 (assert only rc 78; on the pristine script the old fatal path returns rc 1, which is red for the right
  reason, and the refusal must also precede the `EXPECTED_IP` check at lines 28-31). The lint
  accepts a conditional `${TOKEN:+x}` refusal for this file, so this is the only guard that the unconditional
  property holds. The existing T1 healthy run is the untraced positive control.
- **X2 transport argv** (Guard 2): after a healthy run, a POST-failing run (`STUB_POST_RC=1`) and a
  heartbeat-failing run (`STUB_PING_RC=1`), walk `$STUB_ARGV` per call: every call that is not the IMDS probe has
  `--disable` as its FIRST argument, and `--noproxy` is immediately followed by `*` (adjacency over the argument
  array). Floors so the loop cannot pass vacuously: at least 2 POST calls and 2 ping calls across the failing runs.
- **X3 pin** (Guard 3): first assert `$PINNED_URL` is non-empty and matches `^https://` (an empty `sed` result
  would make the parity rows compare empty against empty). Pinned URL (also with a different token and
  `EXPECTED_IP`) -> exactly one POST to `$PINNED_URL`: this row is GREEN on the pristine script and is the
  positive control, not a RED row (it carries Guard 3 mutation 5). Each REFUSED case asserts the POST count is 0
  and the token string appears in no recorded argv (the token legitimately appears in the pinned case, so the
  assertion is scoped to refused cases): an unrelated URL, the pinned host over `http://`, the pinned URL minus its trailing slash,
  `https://<pinned-host>@evil.invalid/`, and `https://evil.invalid/?x=<pinned-host>/` -> ZERO POST calls, a stderr
  line containing `unpinned_url`, the heartbeat still pings (nic_ok path unchanged), rc 0.
- **X3b not redirectable by env**: `INGEST_URL_PINNED=https://evil.invalid/` and
  `BETTERSTACK_INGEST_URL=https://evil.invalid/` both set through `EXTRA_ENV` -> zero POSTs; and the other half as
  a positive control: `INGEST_URL_PINNED=https://evil.invalid/` with the REAL pinned `BETTERSTACK_INGEST_URL` still
  POSTs to the real pinned URL. A token-empty row (pinned URL, no token) makes zero POSTs. (An exported
  `INGEST_URL` alone is GREEN on the pristine script, since the script already overwrites it; not added.)
  ADR-214: no env-declared seam; the only way a test reaches a non-vendor destination is the PATH `curl` stub.
- **X3c parity**: the script's `readonly INGEST_URL_PINNED="..."` line equals the `zot-registry.tf` literal
  byte-for-byte (trailing slash included) and contains no `$` or backtick.
- **X4 drawdown**: the SUT's FULL repo path (`apps/web-platform/infra/web-private-nic-guard.sh`, the form the
  baseline lines carry) is absent from both baseline files (`grep -cxF`; a basename needle would be green on the
  pristine tree). The lint itself
  is not re-run in the suite: the repo-wide run (`test-all.sh:4761`, required `test` shard) already executes it,
  and after the drawdown that run covers both files.

**`apps/web-platform/infra/cron-egress-enforce-probe.test.sh`**:

- Stub dir created with `mktemp -d` under an `EXIT` trap that removes it (`lint-trap-tempfile-ownership.py`
  rule c fires on a `mktemp` with no owning trap; precedent `fresh-boot-ready.test.sh:189`), and PREPENDED to PATH
  per run (`PATH="$STUBS:$PATH" ... bash`, never exported globally, so it cannot shadow `sleep` or `curl` for later
  rows; `run_probe` is wrapped in `timeout 20`; `timeout 15 doppler` and `docker` resolve from PATH):
  `docker` (dispatch on `$1`: `ps` prints `soleur-web-platform`; `exec` returns 0 for `api.github.com` and 28 for
  `example.com`; refuses unknown argv like the `fresh-boot-ready` stubs), `nft` (prints `jump SOLEUR-EGRESS`),
  `systemctl` (`is-active` rc 0), `sleep`, and `doppler` (prints a non-empty synthetic DSN) plus `curl`, each
  logging `name<TAB>argv` to `$STUB_CALLS`, asserted with line-anchored patterns (`^curl`, `^doppler`, `^REFUSED`):
  the healthy path legitimately logs `docker exec ... curl ...`, so an unanchored "curl never called" check would
  go red on a healthy run. A small `run_probe <probe-path> [bash flags]` helper (new; the suite has none)
  captures rc, stdout, stderr and the call log.
- **P-X1** `bash -x`, `env SHELLOPTS=xtrace bash`, and `BASH_ENV` forms: rc exactly 78; a non-`+` stderr line
  contains `refusing to run under xtrace`; `$STUB_CALLS` is EMPTY. The empty log is what proves the refusal sits
  before every probe step AND before `trap emit_fail EXIT` (an armed trap would call the `doppler` stub, and, since
  that stub prints a DSN, `curl`, on exit).
- **P-X1c** the same stubs, untraced: rc 0, prints `egress-enforce-ok`, `doppler` and `curl` stubs never called
  (the clean-success path disarms the trap). This is the cron suite's only positive control (the suite has no
  healthy-run row today).
- **P-L** the probe's full repo path is absent from the A/B/C baseline (`grep -cxF`).
- The existing Sentry TRANSPORT parity block is unchanged and must stay green (it is why the Sentry curl is
  untouched).

Confirm RED by running both suites against the pristine scripts: the failures must be exactly the new rows above
(X1 x3 forms, X1b, X2, the X3 refused cases, X3b, X3c literal row, X4, P-X1 x3, P-L) and no pre-existing row; the
pinned-POST, `INGEST_URL_PINNED`-with-real-URL and untraced rows are GREEN in RED by design (positive controls).

### Phase 1 — GREEN (the two scripts)

`apps/web-platform/infra/cron-egress-enforce-probe.sh`, directly after line 28 `set -e` and before `CONTAINER=`
(so before `trap emit_fail EXIT`, before any `doppler secrets get`, before any bind):

```bash
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
```

preceded by a short comment stating: unconditional because `emit_fail` ACQUIRES the DSN at runtime so a
`${VAR:+x}` hatch would be open by construction; placed before the EXIT trap so the refusal is not itself traced or
re-emitted; the caller (`cloud-init.yml:807`) treats any non-zero exit as "power off the host", so a refusal on a
traced fresh-host boot powers it off, which is the intended fail-closed outcome. No SHIPPED boot path enables
tracing (`grep -n 'set -x\|bash -x\|SHELLOPTS'` over `cloud-init.yml`, `soleur-host-bootstrap.sh` and `server.tf`
returns only the refusal text itself); the one surface that could is the deploy-owned env file `emit_fail`
sources (F5), a pre-existing privilege-boundary question this pass does not change. No other line changes.

`apps/web-platform/infra/web-private-nic-guard.sh`:

1. Directly after line 2 `set -u`, before the header comment and before `EXPECTED_IP=`: the same `case` block
   (unconditional: also covers `WEB_NIC_GUARD_URL`, a secret-bearing URL), with a comment that the guard cannot be
   traced on-host by design and that `web-private-nic-guard.test.sh` (excluded from the lint) is the way to
   observe it.
2. At the credential block (current lines 95-102):

```bash
TOKEN="${BETTERSTACK_LOGS_TOKEN:-}"
INGEST_URL="${BETTERSTACK_INGEST_URL:-}"
# comment: literal equals zot-registry.tf local.betterstack_logs_ingest_url and soleur-host-bootstrap.sh:1038;
# readonly + no expansion so the environment cannot reach it; the parity row in the suite pins the equality.
readonly INGEST_URL_PINNED="https://s2457081.eu-fsn-3.betterstackdata.com/"
if [ -n "$TOKEN" ] && [ "$INGEST_URL" = "$INGEST_URL_PINNED" ]; then
  post() { curl --disable --noproxy '*' -fsS -m 10 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$INGEST_URL" --data-raw "{\"message\":\"$LINE\"}" >/dev/null 2>&1; }
  post || post || echo "[nic] SOLEUR_PRIVATE_NIC egress to Better Stack Logs FAILED: $LINE" >&2
elif [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ]; then
  echo "[nic] unpinned_url: refusing to send the Better Stack token to an unpinned destination — SOLEUR_PRIVATE_NIC not shipped: $LINE" >&2
else
  echo "[nic] WARN: ... (existing text, unchanged)" >&2
fi
```

3. Heartbeat (current line 109): add `--disable --noproxy '*'` as the first arguments of BOTH `curl` invocations on
   that line. The IMDS curl (line 59) is unchanged.

Payload text `--data-raw "{\"message\":\"$LINE\"}"` is byte-preserved (M18 anchor). The refusal line never prints
the URL it refused.

### Phase 2 — drawdown and bookkeeping

- Delete `apps/web-platform/infra/cron-egress-enforce-probe.sh` and `apps/web-platform/infra/web-private-nic-guard.sh`
  from `scripts/lint-shell-trace-credential-refusal.baseline.txt`, and the NIC guard from
  `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`.
- `.claude/hooks/grep-q-pipe-guard.test.sh`, comment above the last two rows (lines 458-462): correct the false
  "ci.yml, a required check" to "advisory job `lint-bot-statuses`" and say the credential precondition is now met
  (no PR number, so it cannot go stale); leave the rows and their ceilings (2 and 4) untouched. Comment only.
  (Taste: code-simplicity asked to cut this edit; kept because it removes a false statement about a gate. See
  `decision-challenges.md`.)

### Phase 3 — verification

Run, and record in the PR body: the two extended suites; `scripts/lint-shell-trace-credential-refusal.test.sh`;
`python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` and the repo-wide form;
`.claude/hooks/grep-q-pipe-guard.test.sh`; the carrier-census suites (`cron-egress-enforce-probe.test.sh`,
`web-private-nic-guard.test.sh`, `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`,
`apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, `fresh-boot-parity.test.sh`,
`doppler-injection-bound.test.sh`, `fresh-boot-ready.test.sh`, `soleur-host-bootstrap-observability.test.sh`,
`plugins/soleur/test/cloud-init-user-data-size.test.ts`); and `bash scripts/test-all.sh --affected` last, with its
verdict line copied verbatim. A skipped or unrun suite is reported as skipped.

### Phase 4 — ship and evidence

PR body: `Ref` lines only; the two premise corrections; the blast-radius paragraph from the IaC section; the RED
and GREEN output; the per-row mutation results; the one-time real-curl measurement (curl 8.22.0, loopback
listener, `proxy` in a poisoned `.curlrc` plus `ALL_PROXY`: the flag pair succeeds, absent or with `--disable`
second exits 7); the deferred list below. File the F1 issue (below) before the PR leaves draft. After merge
(`soleur:postmerge`): confirm the `apply-web-platform-infra.yml` push run for the merge SHA concludes `success`
including the SSH-provisioned leg and that its plan shows only the `user_data` hash diff on `hcloud_server.web`,
then confirm the hardened guard is shipping:
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20`
returns rows with `reboot_count=0 zot_store_mounted=n/a` (the web variant) dated after the apply, and a
`--grep unpinned_url` query returns none. Evidence comments on #9217 and #7797. One learning per finding under
`knowledge-base/project/learnings/` (three, listed in Phase 4 of `tasks.md`).

## Guard Contract

The matrix below was written from the design before the scripts changed. Each row is executed once, by hand, on a
scratch copy of the script (or of the suite where it targets the suite) during RED/GREEN, and the red/green result
per row is pasted into the PR body; no mutation runner ships in the suites (plan review: DHH and code-simplicity
cut it, Kieran found it unimplementable for the cron suite as drafted, so delete beat fix).

### Guard 1 — xtrace refusal (both scripts)

**Property.** Neither `cron-egress-enforce-probe.sh` nor `web-private-nic-guard.sh` executes any command that
expands a credential while shell tracing is enabled, however tracing was enabled.

**Assembly.** The chokepoint is the first command of each script: everything after it (the cron probe's
`trap emit_fail EXIT`, `emit_fail`'s `doppler secrets get` and DSN binds; the NIC guard's `TOKEN=`, `URL=` and env
reads) is covered only if the refusal precedes it, and the refusal tests the STATE (`$-`), not a list of
spellings. Three launch forms reach that state (`bash -x`, `SHELLOPTS=xtrace`, a `BASH_ENV` file with `set -x`,
two of which carry no `-x` token) and a fourth is a later `set -x` inside the file (lint Rule B). Two scripts, so
every row runs per script where it applies; the sibling that already carries the refusal
(`soleur-host-bootstrap.sh:26`) is out of scope. The property is about the two SCRIPTS' own commands. Two
neighbouring surfaces are outside that assembly and recorded as follow-ups, not silently claimed: the unit wrapper
`web-private-nic-guard.service:29` (`doppler run -- bash -c 'export WEB_NIC_GUARD_URL="${!KEY}"; exec guard'`)
expands the secret heartbeat URL in its inner shell BEFORE the guard's refusal can run (F6), and the cron probe's
`emit_fail` sources `/etc/default/webhook-deploy` as root (`cron-egress-enforce-probe.sh:49`), a file chowned to the
`deploy` user (`cloud-init.yml:447-449`) (F5).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the whole `case` block from the NIC guard copy | RED (X1 x3, X1b; lint Rule A) |
| 2 | Change the arm `*x*)` to `*y*)` (a refusal that can never match) | RED (X1) |
| 3 | `exit 78` becomes `exit 0` in the NIC guard copy | RED (X1 rc assertion) |
| 4 | Move the cron probe's refusal BELOW `trap emit_fail EXIT` (REORDER, not delete) | RED (P-X1: `$STUB_CALLS` holds the `doppler` call the armed trap makes; lint Rule A) |
| 5 | Make the NIC guard refusal conditional (`if [ -n "${BETTERSTACK_LOGS_TOKEN:+x}" ]`) | RED (X1b only: the lint accepts this form) |
| 6 | Append `set -x` after the refusal in either copy | RED in the repo-wide lint run (Rule B), the required `test` shard |
| 7 | Second member: add a second credential-binding command ABOVE the refusal in a copy | RED in the repo-wide lint run (Rule A prologue) |

**Harness rows.** H1 — in a scratch copy of the cron suite delete the `$STUB_CALLS`-empty assertion: mutation 4
must stop failing P-X1 (it is the one mutation that assertion alone carries; the lint still reds it, which is why
the lint is the second line). H2 — must-PASS non-canonical: the untraced healthy runs (T1 in the NIC suite, P-X1c
in the cron suite) are not refused.

**Anchor.** The independent anchor is the lint (`scripts/lint-shell-trace-credential-refusal.py`, a separate file
with its own review path) run repo-wide in the required shard, plus the baseline-absence rows (X4, P-L): a diff
cannot weaken the refusal without either failing the lint or re-adding the file to a baseline, which is a second,
visible edit.

### Guard 2 — curl transport confinement (NIC guard)

**Property.** Every curl in `web-private-nic-guard.sh` that carries a credential (the bearer POST, and the
heartbeat ping whose URL is itself the secret) has `--disable` as its first argument and `--noproxy '*'`.

**Assembly.** Call sites: `post()` (one definition, invoked up to twice), the heartbeat line (two `curl`
invocations joined by `||`), and the IMDS probe (exempt by name: no credential). The test quantifies over the
stub's RECORDED argv, not over a fixed list of lines, so a later added call site is judged automatically; the
POST-failing and heartbeat-failing runs are what make the second copy of each reachable.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `--disable` from `post()` | RED (X2; lint Rule D) |
| 2 | Move `--disable` to the second position (`curl -fsS --disable ...`), REORDER | RED (X2 first-argument check; lint Rule D) |
| 3 | Drop `--noproxy '*'` from ONLY the second heartbeat curl (the `\|\|` fallback) | RED (X2 on the heartbeat-failing run only) |
| 4 | Add a third heartbeat-path call site `curl -fsS "$URL"` after the compliant two | RED (X2 on the heartbeat-failing run, which is the only run that reaches a third site) |
| 5 | Replace the harness stub with one that records nothing | RED (X2 call-count floors: at least 2 POST and 2 ping) |

**Harness rows.** H1 — drop the call-count floors from a scratch copy of the suite: mutation 5 must stop failing,
proving the floors carry it. H2 — must-PASS: the IMDS call carries no flags and must not be flagged (the exempt
member is exempt by name, not by absence).

**Anchor.** The lint's Rule D (repo-wide, required shard) plus `fresh-boot-ready.test.sh` S4a, the existing
independent check of the same flag shape in the sibling helper. The flags' real-curl effect was measured once
(curl 8.22.0, loopback listener, `proxy` in a poisoned `.curlrc` plus `ALL_PROXY`: the pair succeeds; absent, or
with `--disable` second, exits 7) and goes in the PR body rather than into a suite.

### Guard 3 — ingest-URL pin (NIC guard)

**Property.** The Better Stack bearer token is sent only to the single pinned source URL, whatever the environment
sets.

**Assembly.** Variables that can name the destination: `BETTERSTACK_INGEST_URL` (env file via systemd, doppler
run), `INGEST_URL` (the script's own variable, which a caller can also export), `INGEST_URL_PINNED` (must not be
reachable). Chokepoint: the single `if` that gates `post`. Test seams: none declared in the environment (ADR-214).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the equality with `[ -n "$INGEST_URL" ]` (the pre-change gate) | RED (X3 refused cases send a POST) |
| 2 | Weaken to a substring glob `*betterstackdata.com*` | RED (the `?x=<host>/` and `@evil` cases) |
| 3 | Weaken to a scheme-anchored prefix glob `https://<pinned-host>*` | RED (the `@evil` and no-trailing-slash cases; a scheme-less glob would red on the healthy POST instead and is not this mutation) |
| 4 | Make the literal env-reachable: `${INGEST_URL_PINNED:-<literal>}` | RED (X3b both-evil export; X3c no-`$` check) |
| 5 | Edit the literal (one character) | RED (X3c parity against `zot-registry.tf`; the pinned-URL POST case) |
| 6 | Second member: add an `elif` after the compliant first branch that posts when the token is set and the host merely contains `betterstackdata.com` | RED (the same X3 refused cases) |

**Harness rows.** H1 — drop the zero-POST-count assertion in a scratch copy of the suite: rows 1 and 2 must stop
failing unless the token-absent-from-argv assertion also fires, so run it with each assertion removed in turn and
record which one carries which row (the two overlap by design). H2 — must-PASS non-canonical: the pinned URL with a
different token value and `EXPECTED_IP` still POSTs.

**Anchor.** `zot-registry.tf:127` is read independently at test time (separate file, outside the script); a
script-only edit of the literal cannot pass X3c, and editing both is visible as a `.tf` diff that the
`apply-web-platform-infra.yml` plan and the carrier census surface.

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat web_nic_guard, pinged on every healthy NIC-guard run (unchanged); plus SOLEUR_PRIVATE_NIC rows shipped by the direct POST
  cadence: per timer tick (web-private-nic-guard.timer)
  alert_target: Better Stack heartbeat absence emails (email=true; call, sms and push are false and betterstack_paid_tier defaults to false, so no escalation policy; apps/web-platform/infra/web-probe.tf:52)
  configured_in: apps/web-platform/infra/web-probe.tf:52 (betteruptime_heartbeat.web_nic_guard)
error_reporting:
  destination: stderr of web-private-nic-guard.service into journald, shipped by Vector to Better Stack Logs (Source 4); the cron probe reports through its existing Sentry emit_fail envelope
  fail_loud: "[nic] unpinned_url: refusing to send the Better Stack token to an unpinned destination" (new, NIC guard); "[FATAL] refusing to run under xtrace" (both scripts, to the caller's stderr)
failure_modes:
  - mode: NIC guard pin mismatch (env file value differs from the literal) so the direct POST is refused while the heartbeat keeps firing
    detection: the journald unpinned_url line above (shipped under SyslogIdentifier=web-nic-guard, listed in vector.toml:270 Source 4, queryable with scripts/betterstack-query.sh --grep unpinned_url), and the absence of fresh SOLEUR_PRIVATE_NIC rows after the post-merge apply (Phase 4 query); the parity rows in the suite prevent the drift at CI time
    alert_route: operator-polled Better Stack Logs query in the post-merge check; NO standing alert exists for this mode and none is added here (the heartbeat stays green while the direct POST is refused, which is the gap); follow-up F8 adds a logtail alert on unpinned_url
  - mode: cron probe launched under tracing on a fresh host, exits 78
    detection: cloud-init treats the non-zero exit as a failed probe and powers the host off (cloud-init.yml:807-809, which echoes to the cloud-init output log and emits nothing else); no Sentry event is emitted by design (running the DSN fetch under trace is the leak being prevented). The host never reaches the `cloud_init_complete` boot-trail stage in Better Stack, which is how a dark fresh host is read (knowledge-base/engineering/operations/runbooks/web-host-birth.md, "Expect cloud_init_complete as the last-reached stage"; scripts/followthroughs/web-fresh-boot-zot-8651.sh). The per-host uptime monitor from #5933 item 1 was retired (uptime-alerts.tf:138) and is NOT a detector here; xtrace cannot occur in a shipped boot path, so this mode is defence only
    alert_route: boot-trail absence read by the web-host-birth runbook and the fresh-boot followthrough probe; no standing page (follow-up F7 adds a boot-emit before the power-off)
  - mode: NIC guard launched under tracing on web-1, exits 78
    detection: unit result failed in journald; the heartbeat lapses because no beat is sent, so the existing absence alarm fires
    alert_route: Better Stack heartbeat absence
logs:
  where: journalctl unit web-private-nic-guard.service (shipped to Better Stack Logs); cloud-init output log for the probe
  retention: Better Stack Logs retention for the shipped rows; journald persistent retention on the host
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/infra/web-private-nic-guard.sh apps/web-platform/infra/cron-egress-enforce-probe.sh
  expected_output: OK: 2 scanned file(s)
```

## User-Brand Impact

- **If this lands broken, the user experiences:** a web host that powers itself off at first boot (cron probe
  refusing under a tracing parent) or a silent loss of the private-NIC fault signal on the sole origin; no user
  data path is touched and both failure shapes are fail-closed or observable-by-absence.
- **If this leaks, the user's workflow is exposed via:** a platform Better Stack ingest bearer or a secret
  heartbeat URL printed into an agent transcript by `bash -x` (the #7797 incident class); the token can write
  log rows and heartbeats for the platform's sources and reaches no user data.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** platform-operational credentials only, no user data, and both defects
  are caught or fail closed; `single-user incident` would apply only if a user-scoped secret were handled here.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO assessment (read-only, verified against the worktree) endorsed the unconditional refusal for
both files (the heartbeat URL is invisible to Rule C's name regex) and the exact-equality pin over a host suffix,
and judged leaving the Sentry curl for the family-wide pass acceptable on the merits (ingest-only public DSN key,
single fresh-host run, three-copy byte-parity guard) provided the deferral is a FILED issue. Folded in: a parity row
for the pin literal (including the trailing slash) and the env-file writers; a distinct greppable `unpinned_url`
token on the refusal line; first-position argv assertions with a stub on PATH for the refusal rows; a `BASH_ENV`
row; a post-merge plan check that only the `user_data` hash differs on `hcloud_server.web`; a comment that the
guard cannot be traced on-host by design; follow-ups F1 (filed issue with trigger) and F4 (argv exposure).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "THIS PASS = the credential-hardening PR only, as its own PR, with NO grep-q conversion in it." | Phase 0-4; no `grep` added; rows untouched | mapped |
| 2 | "Harden both scripts so the lint is green" | Phase 1; Guard 1-3 | mapped |
| 3 | "(a) the xtrace refusal from #7797 (refuse to run under `set -x`/xtrace so a credential cannot be printed into a transcript)" | Phase 1 `case "$-"` blocks; Guard 1 | mapped |
| 4 | "(b) `--disable` and `--noproxy '*'` on every credentialed curl" | Phase 1 items 2-3; Guard 2 | mapped (NIC guard POST and heartbeat); the cron probe's Sentry curl descoped — justification: byte-parity guard across three files and Rule D does not classify it, see `decision-challenges.md` |
| 5 | "(c) an `INGEST_URL` pin" | Phase 1 item 2; Guard 3 | mapped |
| 6 | "Read the lint first to learn exactly what it demands and which files it flags" | Overview table; Research Insights | mapped |
| 7 | "find every consumer, test, and source-text pin over these scripts (grep the OLD line text across every `*.test.*`, not only the basename; check apps/web-platform/infra, terraform file()/templatefile() sha256 pins, cloud-init, and any digest/hash pin" | Carrier census table | mapped |
| 8 | "Class W deploy files auto-apply on merge: NEVER use `[skip-deploy-fix-apply]`; determine whether these files are Class W and what auto-applies on merge, and state the blast radius in the plan" | `## Infrastructure (IaC)`, Reconciliation row 2 | mapped |
| 9 | "Check every other touched-file lint in ci.yml that fires on these paths (including scripts/lint-infra-no-human-steps.py and lint-bot-statuses) before editing" | Touched-file lints table | mapped |
| 10 | "Run `bash scripts/test-all.sh --affected` locally before push and record its result" | Phase 3 | mapped |
| 11 | "Tests first (cq-write-failing-tests-before): add behavioral tests proving the refusal fires under xtrace, that curls carry --disable and --noproxy '*', and that INGEST_URL cannot be redirected by env." | Phase 0; X1, X2, X3/X3b | mapped |
| 12 | "Deferred to LATER passes (document in the plan as follow-ups, do not do now)" | `## Deferred / Follow-ups` | mapped |
| 13 | "Deliverables of this pass: merged PR, evidence comment on tracker #9217 (and #7797 if relevant), a learning for each non-obvious finding under knowledge-base/project/learnings/, and plain statement of anything not fixed." | Phase 4; `tasks.md` Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-egress-enforce-probe.sh` edit | "the two infra scripts" | asked |
| `web-private-nic-guard.sh` edit (refusal, pin, flags) | "(a) the xtrace refusal from #7797" ; "an `INGEST_URL` pin" | asked |
| Heartbeat-curl flags in the NIC guard | "`--disable` and `--noproxy '*'` on every credentialed curl" | asked (the heartbeat URL is itself a secret, `doppler_secret.web_nic_guard_url`) |
| Unpinned-destination stderr refusal branch | "an `INGEST_URL` pin" | asked (a pin needs a defined refused-path behavior) |
| Baseline entry removal | "Harden both scripts so the lint is green" | inferred — justification: the baseline suppresses by FILE; leaving the entries lets the repo-wide run ignore a regression in a hardened file, and `work` SKILL step 6.5 requires the drawdown |
| Comment update in `grep-q-pipe-guard.test.sh` | "converting those 6 greps" (deferred) | inferred — justification: the deferral comment names this lint as the blocker; leaving it stale misleads the next pass; comment only, rows untouched |
| Mutation matrix (run once by hand, recorded in the PR body) | "add behavioral tests proving the refusal fires under xtrace" | inferred — justification: `## Guard Contract` (plan Phase 2.12) requires a mutation matrix for any guard the plan delivers; no runner ships |
| `decision-challenges.md` | "(b) `--disable` and `--noproxy '*'` on every credentialed curl" | inferred — justification: persists the one place the plan narrows the stated direction (headless plan-review channel) |
| Filing the F1 issue | "document in the plan as follow-ups" | inferred — justification: `wg-defer-only-after-inline-triage` and the CTO review require a filed issue with a re-evaluation trigger for the one deferral this plan creates beyond the brief's list |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/infra`, `scripts` (baselines), plus one comment in `.claude/hooks`
- Planned files: 7 edited (2 scripts, 2 suites, 2 baselines, 1 hook-suite comment) + plan artifacts | Estimated changed lines: ~150 (about 25 in scripts, about 100 in suites)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 (the final text also carries `0 baselined (Rule E: 0 site(s))`) `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 and the explicit-path run on both files prints `OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`.
- [x] AC2 Both files are absent from `scripts/lint-shell-trace-credential-refusal.baseline.txt`; the NIC guard is absent from `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`; the repo-wide run (`python3 scripts/lint-shell-trace-credential-refusal.py`) exits 0.
- [x] AC3 The new rows FAILED against the pristine scripts (RED output recorded) and pass against the edited ones; no pre-existing row changed verdict.
- [x] AC4 Every mutation in the Guard Contract tables was run once on a scratch copy and went RED in the stated row (per-row result pasted in the PR body), and the untraced healthy runs stay green.
- [x] AC5 `.claude/hooks/grep-q-pipe-guard.test.sh` passes with the two rows still at `= | 2` and `= | 4` (no `grep` added to either script, no pipe-fed `grep -q` added to either suite).
- [x] AC6 `cron-egress-enforce-probe.test.sh` "Sentry TRANSPORT parity" block and `betterstack-send-failed-alert-mutation.test.sh` M18 stay green.
- [ ] AC7 The carrier-census suites listed in Phase 3 pass; `bash scripts/test-all.sh --affected` result is recorded verbatim in the PR body (a skipped run is stated as skipped).
- [x] AC8 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` pass on the plan, `tasks.md`, `decision-challenges.md` and every new learning.
- [x] AC9 No commit message in the PR carries the `[skip-deploy-fix-apply]` marker (the plan names it only as a non-use), no `.tf` file is edited, and `server.tf` is not edited (`git diff --name-only origin/main...HEAD` has no `.tf` line).
- [ ] AC10 PR body first line answers "does merging THIS alone mutate production?": yes, the push-triggered infra apply re-provisions the NIC guard on web-1 and a normal image release follows; nothing replaces a host. Then: `Ref` lines only, both premise corrections, the blast-radius paragraph, deferred list, and a "not fixed" statement (the Sentry curl, F1, with its issue number).
- [x] AC10b `npx markdownlint-cli2` is clean on the plan and `tasks.md` (hard tabs and list-spacing are the recurring violations).

### Post-merge

- [ ] AC11 (via `soleur:postmerge`) the `apply-web-platform-infra.yml` push run for the merge SHA concludes `success` with no `::error::`, its summary reads "SSH stage: ran" (a skipped SSH leg is green too, so the conclusion alone proves nothing), the apply output shows `terraform_data.private_nic_guard_install` replaced, and no `hcloud_server.web` line appears in any `Plan:` output.
- [ ] AC12 after at least two timer ticks past the apply, `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_PRIVATE_NIC --limit 20` returns web-variant rows (`reboot_count=0 zot_store_mounted=n/a`) dated after the apply, and a `--grep unpinned_url` query returns none; the arm step cannot catch a refusing guard (no-op for an armed monitor), so these rows are the check.
- [ ] AC13 Evidence comments posted on #9217 and #7797; one learning per finding committed.

## Test Scenarios

- Given the NIC guard launched with `bash -x` and synthetic credentials, then it exits 78, prints the refusal, leaks neither value, and sends nothing.
- Given `SHELLOPTS=xtrace` or a `BASH_ENV` file containing `set -x`, then the same refusal fires (state test, not token test).
- Given no tracing, then the guard emits and pings exactly as before (positive control).
- Given `BETTERSTACK_INGEST_URL` set to any of six look-alike destinations, then zero POSTs are made, the token appears in no curl argv, and the heartbeat still pings.
- Given `INGEST_URL` or `INGEST_URL_PINNED` exported by the caller, then the destination is still the pinned literal or nothing.
- Given the cron probe launched under tracing with the stub toolchain, then it exits 78 before any stub is called; without tracing it reaches `egress-enforce-ok`.

## Deferred / Follow-ups

Each is explicitly NOT done in this pass. All ride tracker #9217 unless a row names its own; the evidence comment on
#9217 lists them, and F1 gets its own issue before the PR leaves draft (milestone from
`knowledge-base/product/roadmap.md`).

- F1 Sentry-DSN curl family (call site runs with `HOME=/root`, `cloud-init.yml:347`, so a root `.curlrc` would be
  read; nothing writes one at boot): harden the `curl -m 10 --retry 3 -sf -X POST ".../store/"` transport in
  `cron-egress-enforce-probe.sh`, `soleur-host-bootstrap.sh:58,287` and `workspaces-luks-emit.sh:361` TOGETHER
  (the parity guard forces lockstep), and teach Rule D to classify `X-Sentry-Auth` / DSN-key curls (a lint blind
  spot, belongs with Item F). Re-evaluate when: the next edit to any of the three files, or the LUKS security
  review pass, whichever comes first.
- F2 TLS-trust and git-trace environment hardening (more realistic than it looks: `doppler run` injects the whole
  prd config into the guard and its curls, so anyone who can write that config can set `SSLKEYLOGFILE`,
  `CURL_CA_BUNDLE` or `SSL_CERT_*`; `--proto '=https'` on both curls is cheap defence in depth) (`SSLKEYLOGFILE`, `CURL_CA_BUNDLE`, `SSL_CERT_*`, `CURL_HOME`,
  `GIT_TRACE*`) as a family-wide property.
- F3 Heartbeat-curl flags on the sibling probes (`web-zot-consumer-probe.sh:67`, `web-git-data-probe.sh:40`,
  `inngest-consumer-probe.sh:94-95`): same secret-URL shape, outside this brief's two files.
- F5 `cron-egress-enforce-probe.sh:49` sources `/etc/default/webhook-deploy` as root inside `emit_fail`; that file is
  chowned to the `deploy` user (`cloud-init.yml:447-449`), so a planted `set -x` (or any code) runs in the root
  context after the refusal passed. Pre-existing privilege-boundary issue (security-sentinel P1); fix by reading the
  token with `sed -n` instead of sourcing, with a seam-free fixture row. Not in this pass: it edits the failure
  path of a fail-closed boot script.
- F6 `web-private-nic-guard.service:29` expands `${!WEB_NIC_GUARD_URL_KEY}` in an inner `bash -c` before the guard's
  refusal can run; move the indirect lookup into the guard after the refusal (and the same shape in the sibling
  probe units).
- F7 Emit a boot-trail event (`soleur-boot-emit`) before the probe's `poweroff -f` (`cloud-init.yml:809`) so a
  refused or failed probe is visible without the cloud-init output log (observability review P1).
- F8 A `logtail_exploration_alert` on `SYSLOG_IDENTIFIER='web-nic-guard'` rows containing `unpinned_url`
  (precedent `luks_monitor_host_timer_dark`, `monitor_send_failed` in `betterstack-logs-alerts.tf`), so the
  refused-direct-POST mode has a standing alert instead of the post-merge query only.
- F4 Bearer and heartbeat URL on curl's argv (visible in the process table); precedent for the stdin-config form is
  `cloud-init-inngest.yml:327`.
- Brief-named later passes: converting the 6 greps in these two files; Wave A3 other rows (`cloud-init-*.yml` and
  `git-data-bootstrap.sh` are host-replace carriers; `workspaces-luks.tf` needs luks-monitor G2/G4 security review;
  `inngest-luks-cutover.sh` waits for the next image tag after `vinngest-v1.1.44`); Item B test-harness conversion
  (about 800 hits); Item D live-verify rail leftovers (#8022, #7969, #7215, #5634) after reading what the
  already-merged "rail assert seam" covers; Item E the `lint-bot-statuses` finding in
  `scripts/lint-infra-no-human-steps.py`; Item F guard blind spots; Item G a `--ratchets` selector in
  `scripts/test-all.sh`; Item I the JOBS=1 stopgap measurement (#7432).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body --limit 200`, body search for each
of the seven edited paths; recorded at plan time and re-run at ship.)

## Files to Edit

- `apps/web-platform/infra/cron-egress-enforce-probe.sh`
- `apps/web-platform/infra/web-private-nic-guard.sh`
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh`
- `apps/web-platform/infra/web-private-nic-guard.test.sh`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`
- `.claude/hooks/grep-q-pipe-guard.test.sh` (comment above the last two deferral rows only; corrects "required" to "advisory")

## Files to Create

- `knowledge-base/project/specs/archive/20261007-092219-feat-one-shot-a3-credential-hardening-egress-probe-nic-guard/tasks.md`
- `knowledge-base/project/specs/archive/20261007-092219-feat-one-shot-a3-credential-hardening-egress-probe-nic-guard/decision-challenges.md`
- Three learnings under `knowledge-base/project/learnings/` (topics fixed in `tasks.md` Phase 4; filenames chosen at write time)

## Risks and Sharp Edges

- R0 The heartbeat is a signal whose ABSENCE is the alarm, so `--noproxy '*'` on it must not change reachability.
  Measured: no proxy variable (`http_proxy`, `https_proxy`, `all_proxy`, any case) is set anywhere under
  `apps/web-platform/infra` outside comments (`git grep -niE '(https?|all)_proxy' -- apps/web-platform/infra`
  excluding tests and comment lines returns nothing), and the flags change no exit-code semantics (`-f` and `-m`
  are untouched). The flag pair only removes inputs the host does not use.
- R1 The pin makes a drifted env file silent at runtime (refused POST, heartbeat still green). Mitigations: the
  parity rows, the `unpinned_url` stderr line, and the post-merge Better Stack query (AC12).
- R2 The cron probe's refusal makes a traced fresh-host boot power off. Accepted: no boot path enables tracing, an
  untraced run is unaffected, and the consequence is stated in the script comment and the blast radius.
- R3 The NIC guard's env-file rewrite during re-provision is non-atomic; one tick may exit 1. Pre-existing.
- R4 New test rows must not add a pipe-fed `grep -q` (ceiling slack in the `apps/web-platform/*.test.sh` row).
- R5 Verify every subagent claim against `file:line` before it enters a plan: the carrier census in this plan's
  own research contained a size-budget claim and a `triggers_replace` membership claim that were both false
  (see Reconciliation). Learning L3.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6; this one is filled.

## Plan Review Notes

Panel: DHH, Kieran, code-simplicity (eng baseline, threshold `aggregate pattern`) and CTO (devex lens, earlier).
Classification per ADR-084: Kieran's findings are Mechanical (all applied); simplification cuts that remove only
inferred items are Mechanical where both simplification reviewers converged AND Kieran independently found the same
scope defective (the mutation runner), otherwise Taste (persisted to `decision-challenges.md` items 3 and 4).

Applied (Mechanical):

- Harness gaps: launch-flags knob, rc/stdout/stderr capture, `STUB_POST_RC`/`STUB_PING_RC` knobs, argv one argument
  per line with an adjacency check, a `run_probe` helper and mutation machinery that the cron suite lacked.
- Removed an impossible, unsafe row (Guard 1 "stubs removed so the script dies before the refusal": the refusal is
  the first command, and unstubbed runs would reach the real network, docker, nft and doppler).
- Corrected false Guard Contract claims (H1 rows), Guard 3 mutation 3 (scheme-anchored glob), X3b first half
  (GREEN on pristine, removed), stderr match anchored on non-`+` lines (xtrace echoes the printf), heartbeat-failing
  run required for the third-call-site mutation, cron mutation 4 expectation names the `doppler` call, send-failed
  suites cited at `apps/web-platform/test/infra/`.
- Cuts: in-suite mutation runner, exact row and assertion floors, dispatch rows, real-curl listener row (measurement
  moved to the PR body), lint-echo rows, placement parser, `bash -f`, two redundant X3/X3c rows; learnings 5 -> 3.

Kept against review (reasoned): unconditional refusal in both scripts (the cron probe ACQUIRES its credential, and
a conditional form misses the secret heartbeat URL); exact-equality `readonly` pin; the heartbeat flags;
`decision-challenges.md` (it is the headless channel `ship` renders); the F1 issue; evidence comments (named
deliverable). DHH's point that a traced fresh-host boot powers the host off for an ingest-only key is accepted as
R2: the refusal is what the lint requires and nothing in the boot path enables tracing.

## Addendum — 2026-10-06 (review round, #9632)

Superseded statements above, kept for the record: the Cut List entry that deferred the bearer-off-argv move (done, see its note), the Phase 1
snippet showing `-H "Authorization: Bearer $TOKEN"` (now a stdin config), "the heartbeat still pings" on a refused URL (now withheld), and the
baseline lists naming two files (the Rule E baseline is a third). Added in review: a token-shape guard, a `beat()` wrapper, a golden-argv
allowlist and per-call stdin attribution in the NIC suite, call-site CASES floors in both suites (promoted in `guard-vacuity-floor.test.sh`),
and the `betterstack-ingest-parity.test.sh` floor for `s2457081` raised 7 to 8. Tests grew to roughly 330 lines; the ~100-line target was not met
and the reason is the test-design findings. Follow-up issues: #9638 (F1), #9639 (F5-F8).
