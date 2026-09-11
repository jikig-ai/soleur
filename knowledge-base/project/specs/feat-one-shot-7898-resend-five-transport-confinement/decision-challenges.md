# Decision challenges — feat-one-shot-7898-resend-five-transport-confinement

Persisted at plan time (headless pipeline; ADR-084 decision classes). `ship` renders these into the
PR body and files an `action-required` issue for any entry marked user-challenge.

## 1. Merge side-effects on web-1 (record — no decision needed)

**Class:** mechanical (fact record for the PR body)

Editing `disk-monitor.sh`, `resource-monitor.sh`, `container-restart-monitor.sh` and
`cron-egress-alarm.sh` changes the `triggers_replace` hash of four `terraform_data` resources in
`apps/web-platform/infra/server.tf`. `apply-web-platform-infra.yml` fires on the path-glob
`apps/web-platform/infra/**` and its SSH `-target` set names all four, so the merge:

- re-pushes the three monitor scripts to web-1 and re-enables their timers (`disk_monitor_install`,
  `resource_monitor_install`, `container_restart_monitor_install`);
- re-runs `terraform_data.cron_egress_firewall`, whose post-apply assertion restarts
  `cron-egress-firewall.service` on web-1 — gap-free per the 2026-07-11 learning (the loader
  resolves the allowlist before the atomic `nft -f -` flush);
- ALSO rebuilds and redeploys the web-platform container image, because the four scripts are
  `COPY`d into it (`apps/web-platform/Dockerfile`, `local.host_script_files`).

`hcloud_server.web` is NOT recreated. This is the established IaC delivery path for running hosts,
not a host-replacement window. Verified by outcome post-merge (plan AC17-20).

## 2. §1 blocker reasoning in #7898 (user-challenge — for the tracker author)

**Class:** user-challenge

#7898 §1 defers `soleur-host-bootstrap.sh` / `web-private-nic-guard.sh` because "server.tf
triggers_replace re-provisions the live host on merge". `web-private-nic-guard.sh` is delivered by
the same `terraform_data` SSH shape as the four monitors this PR edits, so that reason would make
the monitors equally blocked. The real §1 blocker is different: `soleur-host-bootstrap.sh` is baked
into the image (`local.host_script_files`) and runs only from cloud-init on a fresh host, so an edit
lands nowhere until a host is rebuilt. Surfaced for the tracker author; not acted on here.

## 3. When does #7898 close? (user-challenge — operator question)

**Class:** user-challenge

Do we close #7898 when the *named* problems (sections 1-7) are fixed, or only when *every* script
the scanner still flags (62 after this PR, 58 of them never individually looked at) is fixed?
Choosing "named" means the rest becomes a separate cleanup ticket; choosing "all" means #7898 stays
open for several more months. Recommended default: close at 1-7 and batch the remainder as
`deferred-scope-out` for `drain-labeled-backlog`. Not decided here.

## 4. Fresh-host window between the two merge-triggered workflows (record)

**Class:** mechanical (fact record for the PR body)

`local.host_scripts_content_hash` (server.tf) folds the four monitors and is compared against the
baked image at fresh boot (`cloud-init.yml`, fail-closed `exit 1` on mismatch). It moves on this
merge; live hosts ignore it (`ignore_changes=[user_data]`). A fresh web host birthed between
`apply-web-platform-infra.yml` finishing and `web-platform-release.yml` pushing the new image would
boot against an old image and abort. Pre-existing for every `host_script_files` edit. Do not birth a
web host until the release run for this merge is green (plan AC15).

## 5. Scope add: P9 — crit row on the pre-existing failed/suppressed-send branches

**Class:** taste (plan-review; single-signal)

The operator named five files and "a refused send must still surface". The plan additionally makes a
FAILED or cooldown-SUPPRESSED send emit a PRIORITY-2 `logger` row (one helper call per branch, in
the same five files). Rationale: a send that silently fails after confinement is the one regression
this PR itself could introduce, and today the two Resend-only monitors' failure lines never leave the
host. Cost: one line per branch, ~6 lines total. Kept; surfaced here so it is a decision, not a drift.

## 6. Not adopted: stamp-gated crit row for `RESEND_API_KEY`-unset in disk/resource monitors

**Class:** taste (plan-review; spec-flow proposal)

An unset key is a Terraform-provisioned state (the env file is written by the same `remote-exec`
that installs the script; the apply log shows it). A stamp-gated crit row would add state to two
scripts for a condition already visible at apply time. Not adopted; recorded so it can be revisited
if an env file is ever hand-managed.

## 7. Kept: `SENTRY_PUBLIC_KEY` 32-hex check in container-restart-monitor.sh (header, not URL)

**Class:** taste (plan-review; DHH objection)

DHH: in the monitor the key sits in a header, so the check is symmetry, not a pin. Kept because
`_cron-shared.ts` validates the triple as a unit (one repo-wide definition of a valid triple) and the
parity row requires the two adjudication blocks to be byte-identical. One line; recorded.

## 8. Not adopted: cooldown arms on delivery failure (pre-existing)

**Class:** taste (deepen-plan; silent-failure-hunter proposal)

`container-restart-monitor.sh` writes `COOLDOWN_FILE` after both channels regardless of outcome, so a
tick where Sentry refused AND Resend returned `000` suppresses the next hour. Pre-existing; the
cooldown's purpose is bounding inbox storms, and the failure is now visible off-box via the
`SEND_FAILED` crit rows. Changing it needs `sentry_event()`/`resend_email()` to return non-zero and
the callers to branch — scope beyond confinement. Recorded, not changed.

## 9. Record: the merge cuts in-flight Concierge streams (pre-existing for every web-platform merge)

**Class:** mechanical (fact record for the PR body)

Because the four monitors are `COPY`d into the image, this merge triggers `web-platform-release.yml`
and a prod container stop → start (`ci-deploy.sh` cron-drain block, `docker stop --time=12`).
In-flight streams are cut, identical to every `apps/web-platform/**` merge. Stated so it is not implied.

## 10. Record: the Rule D classifier cannot see the Sentry host pin (work-phase finding)

**Class:** mechanical (fact record for the PR body; candidate follow-up in a different subsystem)

With the host limb of the `sentry-dest-pin` region deleted, `scripts/lint-shell-trace-credential-refusal.py`
still passes both `container-restart-monitor.sh` and `cron-egress-alarm.sh`: the credentialed URL
interpolates the DERIVED `_si_host`, and the classifier's env-settable test does not follow a
derivation from the curl operand back to its env-settable source. The committed exec harness rows
are the guard (every host-limb mutant is RED there). The classifier is untouched (forbidden by
the ask). Upgrade trigger for the classifier, surfaced for `ship`: a destination operand DERIVED one
hop from an env-settable variable should inherit its env-settability.
