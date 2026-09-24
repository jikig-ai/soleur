---
title: "chore(infra): retire every host-side GHCR boot leg (#8036 item 1d / ADR-096 5.3b-i)"
date: 2026-09-24
slug: chore-retire-host-boot-ghcr-legs
branch: feat-one-shot-8036-1d-retire-boot-ghcr
issue: 8036
closes: none
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(infra): retire every host-side GHCR boot leg (#8036 item 1d / ADR-096 5.3b-i)

## Overview

This is #8036 item 1d, which is also ADR-096 task 5.3b-i. Fresh boots of the web hosts and of
the dedicated inngest host still log in to `ghcr.io` and keep a GHCR pull arm behind the zot
pull. The read credential those arms present (`GHCR_READ_TOKEN`) has been revoked since
2026-07-29, so no arm can succeed: every login 401s and every GHCR pull is `denied`. The arms
now cost a failed login per boot, carry a revoked credential in `user_data`, and emit Sentry
signals (`app_ghcr_fallback`, `app_ghcr_served`, `inngest_ghcr_fallback`) that describe a
fallback which no longer exists.

This plan deletes them in **one PR**:

- the web template (`cloud-init.yml`): the GHCR bake, the seed block's `ghcr_login` and GHCR
  pull arm, the two `app_ghcr_*` emits, the gated colocated-inngest GHCR fallback, and the three
  `|| echo '${image_name}'` sentinel fallbacks;
- the baked host script (`soleur-host-bootstrap.sh`): the whole `STAGE=ghcr_login` subshell;
- the inngest template (`cloud-init-inngest.yml`): the GHCR bake, the `docker login ghcr.io`
  item, and the GHCR fallback pull after a zot miss. A zot miss becomes terminal and emits a new
  **fatal** `inngest_pull_fatal` stage in place of `inngest_ghcr_fallback`.
- the Terraform `templatefile()` arguments that carried `ghcr_read_user`/`ghcr_read_token` into
  both templates. After this PR no host consumes them. The variables, the `doppler_secret` pair
  and the minter are 5.4, a separate follow-up PR.

It then moves the soak gate (`zot-soak-6122.sh`), the Sentry rule
(`sentry_alert.zot_mirror_fallback_rate`) and their op-contract test to the smaller signal set
that remains (FAIL set 4 → 2). It re-pins the soak's `START` to the operator's re-arm literal
`2026-09-24T03:22:41` and enrols the soak on #6122. It also sweeps the stale comments named in
the #8036 addendum and records the change in ADR-096, tasks.md and C4.

After merge, the orchestrator runs `inngest-host-replace` in an ADR-100 window and then a
`web-host-replace` of web-2. It verifies each host reaches `fresh_boot_ready` with
`stage=inngest_zot` / `stage=app_zot`, and then closes #6410 as won't-fix-superseded. The
operator authorized both replaces on #6122 (comment 5811202876, 2026-09-24).

**Out of scope, by operator decision:** CI's GHCR push and read (`DECISION: B3`, ADR-169's
restore source), the anonymous `ghcr.io` pulls of the cosign verifier and zot's own image
(5.3b-iii), and the GHCR egress allow (5.3b-iii).

## Enhancement Summary (deepen-plan, 2026-09-24)

Security review of the plan (security-sentinel). Findings applied to this plan; `soleur:work` executes them:

1. **P1: the web zot-miss page did not fire (measured).** `web_terminal_boot_fatal` uses
   `event_frequency_count value = 1`. The comparison is a strict `>`, and the check runs per issue
   group. The seed fatal `_emit "soleur-hostscript-seed failed" "$STAGE" fatal` has its own group. The
   only such event in 30 days (#8651's dark boot, 2026-09-23T20:10:21Z, `WEB-PLATFORM-4T`, stage=pull,
   fatal) is one event, so it could not page. **Fix in this PR:** set the rule's trigger to `value = 0`,
   as `git_data_boot_warning` already has. This is safe because all five stage conditions
   (`terminal_preamble`, `hostscripts_incomplete`, `doppler_download`, `docker_run`, `pull`) are emitted
   only on failure paths: grep shows only `on_err`'s fatal `_emit` and
   `soleur-boot-emit hostscripts_incomplete fatal`. Rewrite the comment that says `value = 1` works
   "because the shared group is hot". Regenerate `alert-reference.json`. Without this, P2 is false for
   web.
2. **P2: the soak must see web fresh-boot fatals.** Add a separate FAIL arm outside `FAIL_QUERIES`,
   `WEB_FATAL=$(sentry_count 'stage:"pull" level:fatal')`, and FAIL on > 0. It is not an alarm
   operand, so the rule⇔soak parity contract holds and nothing double-pages. Give it its own
   test rows: a fixture where web-pull-fatal > 0 must FAIL.
3. **P2: wording.** The ADR amendment title becomes "no host *presents* a GHCR credential at boot".
   Name the residual that 5.4 closes: `GHCR_READ_TOKEN` stays in Doppler `soleur/prd`, and
   `ci-deploy.sh` downloads that config into the app container env. The value is revoked; re-enabling
   the minter before 5.4 would put a live PAT back there.
4. **P2: Encryption Posture.** Do not claim LUKS for web-1's `/etc/default/soleur-ghcr-read`
   (the root fs is not LUKS). Add the other web-1 residuals: `/var/lib/cloud/instance/user-data.txt`,
   the Hetzner metadata userdata endpoint, and `/root/.docker/config.json`. All carry the revoked value.
5. **P2: Guard 3 anchor.** Do not call the #6122 comment "uneditable". Add a runtime check in the
   soak: read #8660 `mergedAt` via `gh` (GH_TOKEN is already declared) and exit TRANSIENT if the
   default START is later than it. Reword "chosen before measuring": the re-arm was chosen *because*
   the backfilled window could not pass, and its START is the merge of the last fix. List the six
   excluded fallbacks, each with the PR that fixed it, in the soak header.
6. **P2: forgeable PASS.** Keep the PASS echo's "Sentry evidence is forgeable with the public DSN
   — corroborate on Better Stack" clause. The 5.6/#6129 trackers' re-evaluate lines require that
   corroboration, because the sweeper cannot check it itself.
7. **P3:** Add `|| true` to the inngest fatal arm's phone-home call, plus a Guard 4 row: phone-home
   stub rc≠0, and the Sentry emit must still happen.
8. **P3:** ADR/C4 say "digest-pinned (integrity)", never "verified", for fresh-boot images.
9. **P3:** `discoverability_test.expected_output` lists both values: `zot-gate-degraded` and
   `inngest_pull_fatal`.

## Research Reconciliation — Spec vs. Codebase

| Brief / spec claim | Codebase reality (measured 2026-09-24) | Plan response |
|---|---|---|
| (1) Web `cloud-init.yml` has one GHCR leg: the fresh-boot `ghcr_login` + seed-pull arm + `app_ghcr_fallback`/`app_ghcr_served` emits. | Five host-side GHCR sites in this file. (a) `printf 'GHCR_READ_USER=…' > /etc/default/soleur-ghcr-read`, a bake whose consumer (ci-deploy.sh) 1c deleted. (b) The seed block's `STAGE=ghcr_login` + GL + GHCR pull arm. (c) The two emits. (d) The **gated** colocated-inngest block (`%{ if web_colocate_inngest ~}`): `soleur-boot-emit inngest_ghcr_fallback warning`, then `docker pull "$IREF"` of the GHCR ref. (e) Three `"$(cat /run/soleur-image-ref 2>/dev/null \|\| echo '${image_name}')"` fallbacks to the GHCR ref in the terminal region. | All five are removed. (e) is unreachable, because the seed block's `exit 1` aborts the one-shell runcmd before any consumer, so the sentinel always exists there. It is removed anyway, so that no host code names a GHCR ref as a pull source. |
| (2) `soleur-host-bootstrap.sh` `STAGE=ghcr_login`/`ghcr_login_warn` is a GHCR login. | The subshell carries **two** logins: GHCR (baked file, then Doppler fallback) and a zot login that reads `ZOT_REGISTRY_URL`/`ZOT_PULL_*` from Doppler. The subshell sources `/etc/default/webhook-deploy` with a bare `.`, which does not export `DOPPLER_TOKEN`, so its `doppler` calls are tokenless (the #6985 class that #8651's learning measured on the seed block). The seed block's baked zot login (#8660) already runs as root before this script and writes the auths entry every later root pull reuses. | Delete the **whole** subshell, both halves. The zot half duplicates the seed block's login, cannot read its inputs, and carries two stale comments the addendum lists. Alternative (keep the zot half, reword it) is in the Alternatives table. |
| (3) `cloud-init-inngest.yml`: remove `docker login ghcr.io`, the GHCR fallback pull after a zot miss, and the `inngest_ghcr_fallback` emit. | `inngest_ghcr_fallback` (warning) is the **only Sentry signal** this host emits when its bootstrap pull fails. `oci-pull-ALL-LEGS-FAILED` goes to Better Stack only (`issue-alerts.tf`: "there is no alert keyed on oci-pull-ALL-LEGS-FAILED"). Deleting the emit with no replacement would remove the page for a dark sole-scheduler boot. | Replace, do not delete: a zot miss emits `inngest_pull_fatal` at **fatal** on both channels (Sentry `soleur-boot-emit` + Better Stack phone-home) and ends the boot. The redundant second `docker pull "$IREF"` (which existed only to reach the GHCR-seeded ref) goes too. |
| (4) Retire the FAIL_QUERIES entries whose emitters are deleted; move the 4-entry floor in the same edit. | `[appboot]` and `[appserved]` lose their emitters. `[freshboot]`'s emitter is **renamed**, not deleted (row 3). `tests/scripts/test-sentry-alert-live-fidelity.sh` row F27 swaps a `registry`-keyed with a `stage`-keyed condition on this rule. With no stage condition left it would become a NOOP ("mutation did not land") and fail. | FAIL set becomes `{gate, freshboot → stage:"inngest_pull_fatal"}`, floor `4 → 2` in the same edit. The Sentry rule narrows to the same two conditions. The parity test pins `== 2`. |
| (4') Pin START to `2026-09-24T03:22:41`. | `zot-soak-6122.test.sh` pins the default START **≤ 2026-07-17T19:51:49** ("not after the first zot-served pull"). That row forbids the re-arm. | The row is restated. START must equal the literal the operator recorded on #6122. That comment is the anchor outside the commit, and the row names it. |
| (5) Stop passing `GHCR_READ_*` to the boot templates only if no consumer remains. | After this PR the host-side consumers are zero (census below). Remaining non-host consumers: `doppler_secret.ghcr_read_{user,token}` (`ghcr-read-credential.tf`), `var.ghcr_read_*` (`variables.tf`), the disabled `cron-ghcr-token-minter.ts`, and the `-target=doppler_secret.ghcr_read_*` lines in `apply-web-platform-infra.yml`. | Remove the two `templatefile()` arg pairs (`server.tf`, `inngest-host.tf`) and the budget-script stubs **in this PR**. Variables, secrets, minter and workflow targets are **5.4**, the next PR (tracker verified or created in Phase 6). |
| (a repo-research claim) "The per-merge apply `-target`s `hcloud_server.inngest`, so a merged `cloud-init-inngest.yml` edit replaces the host on the next auto-apply." | False. `hcloud_server.inngest` is an `OPERATOR_APPLIED_EXCLUSIONS` member. Its only apply paths are the `inngest-host` dispatch (additive-only, aborts on a replace: `apply-web-platform-infra.yml` "server_touched → hcloud_server.inngest would be updated or replaced") and the `inngest-host-replace` dispatch (`-replace='hcloud_server.inngest'`). The #8539 plan records the same: "The merge apply's `-target` list prunes `hcloud_server.inngest`, so merging alone changes nothing on the host." | Merging changes no host. The inngest replace is a post-merge dispatch (Phase 7). Until it runs, `scheduled-terraform-drift.yml` reports a pending replace, as it did after #8539. |
| (bump-bot coupling, not in the brief) | `.github/scripts/bump-inngest-bootstrap-pin.sh` rewrites "all four tag@sha256 cloud-init pins" (the `IREF=ghcr.io/…` literal and the `ZIREF` literal in both templates). The AC6/AC6b pin-drift guard matches `soleur-inngest-bootstrap:vX.Y.Z`. | The four `…soleur-inngest-bootstrap:v1.1.37@sha256:…` literals **stay**. `IREF=ghcr.io/…` stays as the pin carrier and is never pulled. Deleting it would break the bump bot and disarm the guard. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked on 2026-09-24 against GitHub and `origin/main` (`83977b5b3c`, the branch's init commit
on top of `f2aa5b1bee`):

- **#8036** OPEN (the 1c follow-through is still grading), **#6122** OPEN (the epic),
  **#6410** OPEN (its 2026-09-23 comment names the close condition "closes as
  won't-fix-superseded when #8036 item 1d lands").
- **#8651** OPEN with a `soleur:followthrough` directive. It closes via the sweeper after
  `earliest=2026-09-25`. PR **#8660** is MERGED at `2026-09-24T03:22:41Z`, which is exactly the
  re-armed START.
- **#6500** CLOSED as COMPLETED today, so the soak's `BLOCKER` arm passes on state. #7674
  and #7462 are CLOSED.
- **#6122 comment 5811202876** (2026-09-24T09:07:09Z) records the three operator decisions this
  plan executes: 5.3b-i is released from the soak; the soak is re-armed at `START=2026-09-24T03:22:41Z`
  with a 7-day minimum; and the agent runs `inngest-host-replace` and then `web-host-replace` of
  web-2 after merge. It also says: "The script's START and the enrolment directive land in the
  item 1d PR."
- Every cited file exists on the branch. `cloud-init.yml` no longer contains the `/v2/` probe
  (#8660 removed it), so the seed block's non-zot arm is the GHCR login-gated leg only.
- The mechanism, deleting a fallback with no reachable success arm, is ADR-096's own recorded
  ground for 5.3a ("Amendment 2026-09-23 (#8036 item 1c)") and is the ground the operator applied
  to 5.3b-i. No ADR lists it as a rejected alternative.

### Property List (Phase 0.6b)

- **P1.** No host-side boot code (web template, the baked bootstrap script, the inngest
  template) presents a `ghcr.io` credential or pulls from `ghcr.io/jikig-ai/*`.
- **P2.** A fresh boot whose zot pull fails ends the boot and pages, on both hosts. Web does this
  through the existing `stage=pull` fatal, which `web_terminal_boot_fatal` pages. Inngest does it
  through the new `inngest_pull_fatal` fatal, which `zot_mirror_fallback_rate` pages.
- **P3.** The Sentry rule's watched set, the soak's FAIL set and the live emitters agree, and
  the soak's runtime floor matches the declared set.
- **P4.** The soak measures the window the operator chose (START = the #8660 merge) and is
  enrolled so the sweeper grades it from `2026-10-01T03:22:41Z`.
- **P5.** No `templatefile()` passes a GHCR credential into any host's `user_data`.
- **P6.** Text that tells an engineer or operator how GHCR behaves on a boot is true after the
  merge (comments, runbook, ADR, C4, tasks.md).
- **P7.** The change reaches both hosts (inngest replace, web-2 replace) and is observed there,
  never assumed.

### Cut List (Phase 0.6b)

- **"Also delete the four `ghcr.io/…soleur-inngest-bootstrap` pin literals"** → buys nothing
  for P1 (a literal that is never pulled is not a leg), and the bump bot and AC6 depend on
  it. Kept.
- **"Change `fresh-host-boot-trail.sh`'s `ORIGIN_Q_STAGES` to drop `app_ghcr_*`"** → buys no
  property. The stages can no longer be emitted, and #8651's still-open probe grades that script's
  output, so its format must not move before #8651 closes. Kept as a harmless tripwire.
- **"Retire `oci-pull-ALL-LEGS-FAILED` / the effective-pull bracket as a separate cleanup"** →
  folded into row 3. The second pull exists only to reach the GHCR-seeded ref, so removing it
  is part of P1, not extra work.
- **"Remove `/etc/default/soleur-ghcr-read` from web-1's disk"** → no running-host channel can do
  it (it sits in a root-owned `/etc/default`, and ci-deploy runs as `deploy`). The value is
  revoked, so no property is at stake. Disclosed as a residual.
- **"Add web fresh-boot `stage:"pull"` to the soak FAIL set"** → P2 is already met for web by
  `web_terminal_boot_fatal`. Adding it would break alarm⇔soak parity or double-page. Disclosed
  as a residual in the soak header; see Alternatives.
- **"Split into two PRs"** → see "One PR, not two" below.

### Value-proposition measurement (Phase 0.6c)

Not a cost/performance justification: no saving is claimed. (The arms cost one failed login,
and on inngest one failed pull, per boot. The measure of that is the observed
`ghcr_login=fail` in run 35951886838's detail.)

### One PR, not two: the split decision

The brief asks whether to split web (cloud-init + host-script + soak) from inngest. **Decision:
one PR.**

1. **The soak, the Sentry rule and the op-contract test are one parity unit across both
   templates.** `sentry-zot-mirror-fallback-alert-op-contract.test.ts` asserts that the rule's
   watched set equals the soak's FAIL set and that each value has a live emitter. Two of the four
   values are web emitters (`app_ghcr_*`). One is emitted on both hosts (`inngest_ghcr_fallback`,
   from the inngest template and the gated web colocated block). A split means two edits of the
   same three artifacts, and an intermediate `main` where the parity set names a signal only one
   template still emits.
2. **P5 is only true once both templates drop the variables.** Removing a `templatefile()` arg
   while its template still references `${ghcr_read_user}` fails the plan. In a split, the
   Terraform half waits for whichever PR lands second.
3. **Neither coupling the brief names is a merge-time coupling.** Both happen after the merge.
   - *Image pin / coherence preflight (web).* `web-host-replace` pins web-1's **running** image
     and compares its baked `/opt/soleur/host-scripts` hash to
     `local.host_scripts_content_hash`. `soleur-host-bootstrap.sh` (and the comment-only
     `ci-deploy.sh` edits) are in `local.host_script_files`, so the hash moves. The merge itself
     triggers `web-platform-release.yml` (`push: main`, `paths: apps/web-platform/**`), which
     rebuilds the image with the new scripts and deploys it to web-1. Once that deploy lands,
     web-1's running image matches the tree and the preflight passes with the default pin. A
     separate pin-bump PR is **not** needed; the constraint is ordering: web-2's replace waits
     for the release deploy. A split would not remove this wait; it only moves it.
   - *Inngest replace.* The template edit force-replaces `hcloud_server.inngest` (no
     `ignore_changes=[user_data]`), but only through the `inngest-host-replace` dispatch. The
     per-PR apply excludes the host. The replace does not depend on the web image.
4. **The soak re-arm needs both.** `FAIL(no-inngest-freshboot-evidence)` clears only with an
   inngest boot built from the new template. `APP_ZOT` has one web boot since START already (web-2,
   07:16Z). One PR means one START edit, one enrolment and one ADR amendment.

**Cost accepted:** a larger review surface (three templates' worth of test suites in one diff).
The mitigation is that each template keeps its own test suite and Guard 1 is written per file.

### Structural map of the code under change

| File | Site (content anchor) | Change |
|---|---|---|
| `apps/web-platform/infra/cloud-init.yml` | `# (#6090) Bake the scoped GHCR read-creds.` + `printf 'GHCR_READ_USER=%s\nGHCR_READ_TOKEN=%s\n'` + chmod/chown | delete |
| same | seed block: `soleur-ghcr-login.log` in the `install -m 600` list; `STAGE=ghcr_login` … `unset GHCR_TOKEN`; `GP=not-attempted`; `if [ $OK = 0 ] && [ "$GL" = ok ]; then` … `fi`; `ghcr=[login=%s,pull=%s]` / `ghcr_login=%s` in both detail printfs; `if [ "$REF" = "$IMAGE_REF" ]; then _emit … "app_ghcr_served" …` | delete / collapse (sketch below) |
| same | colocated block: `curl … /v2/` probe, `inngest_ghcr_fallback` emit, trailing `docker pull "$IREF"` | zot pull, else fatal `inngest_pull_fatal` + `exit 1` |
| same | 3× `"$(cat /run/soleur-image-ref 2>/dev/null \|\| echo '${image_name}')"` | `"$(cat /run/soleur-image-ref)"` |
| same | comments: `(STAGE=pull/ghcr_login/extract/verify)`, `falls back to the GHCR ${image_name}`, `# ADR-096 5.3 tripwire (#6285)` ×2 | reword / delete (the tripwire has fired) |
| `apps/web-platform/infra/soleur-host-bootstrap.sh` | `# #6005: authenticate the host docker daemon …` through `fi ) \|\| true` (the `STAGE=ghcr_login` subshell) | delete whole block; reword the `soleur-boot-emit` comment "(the ghcr login/pull errors written by cloud-init)" |
| `apps/web-platform/infra/cloud-init-inngest.yml` | `inngest-redact.sh`: `. /etc/default/soleur-ghcr-read …; vals+=("$GHCR_READ_TOKEN")` + the #7462 comment naming `inngest_ghcr_fallback` | delete line; reword comment |
| same | `# --- Bake scoped GHCR read-creds (#6179/#6161)` block + printf/chmod | delete the bake; keep the CORRECTED digest-pin provenance prose (move it to the pull item) |
| same | daemon.json item `echo "[inngest] no zot endpoint baked — GHCR-only pull path (unchanged)"` | reword: the pull will fail closed |
| same | `# GHCR login from the baked creds …` item (`docker login ghcr.io`, `ghcr-login-ok/FAILED`, `ghcr-creds-EMPTY`) | delete |
| same | zot-login item comments/echoes "falls back to GHCR", "degrade to the GHCR leg" | reword |
| same | pull item: `WHAT THE GHCR LEG IS NOW` paragraph; the `else` arm emitting `inngest_ghcr_fallback`; `pre-oci-pull`/`docker pull "$IREF"`/`oci-pull-rc-$pull_rc`/`oci-pull-ALL-LEGS-FAILED` bracket | zot pull is the only pull; miss → `inngest_pull_fatal` fatal on both channels + `exit`; bracket removed |
| `apps/web-platform/infra/server.tf` | `ghcr_read_user = var.ghcr_read_user` / `ghcr_read_token = var.ghcr_read_token` + the `#8036 1c (2026-09-23) — WHY THIS BAKE SURVIVES A RETIREMENT` comment | delete |
| `apps/web-platform/infra/inngest-host.tf` | same two args + `# Bake the scoped GHCR read-creds (#6179/#6161)` comment; `Trust boundary vs the ghcr_read_* bake above` | delete args; reword |
| `apps/web-platform/infra/inngest-userdata-budget.sh` | `ghcr_read_user`/`ghcr_read_token` stub lines + worst-case-length comment | delete |
| `apps/web-platform/infra/variables.tf` | `ghcr_read_token` description `CONSUMERS — THREE fresh-boot login sites …` | restate: no host consumer since 1d; remaining consumer `doppler_secret.ghcr_read_token` (retired by 5.4) |
| `apps/web-platform/infra/ci-deploy.sh` | header clause "… (1.8) + backfills (1.9) zot, ZOT_REGISTRY_URL is absent in Doppler prd"; `zot_gate_and_login` header "a strict no-op until … (1.8)" | comment-only rewrite (zot was provisioned and backfilled before the 2026-07-17 cutover) |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | `zot_mirror_fallback_rate` `conditions` + its comment block; `web_terminal_boot_fatal` comment's stage list naming `ghcr_login` | narrow to 2; reword |
| `scripts/followthroughs/zot-soak-6122.sh` | header lines 4-14, `COVERED`/`NOT COVERED` blocks, `⚠ NOT YET ENROLLED` block, directive line, `START=` default + its comment, `FAIL_QUERIES`, floor, FAIL echo, `_zot_reports_sentry_stage`, PASS echo | see Phase 4 |

### Off-box consumers of the signals this change deletes or renames

| Signal | Consumer | Disposition |
|---|---|---|
| `stage:"app_ghcr_fallback"`, `stage:"app_ghcr_served"` | `zot_mirror_fallback_rate` conditions; soak `[appboot]`/`[appserved]`; op-contract test; `alert-reference.json`; `zot-registry-revert.md` triage bullets | removed everywhere, in the same PR |
| same | `fresh-host-boot-trail.sh` `ORIGIN_Q_STAGES`; `web-fresh-boot-zot-8651.sh` FAIL branch | **kept**. It becomes a vacuous tripwire. #8651's probe grades this output until #8651 closes. |
| same | `accounted-beacon-live-6462.sh` | kept. #6462 is CLOSED, so the sweeper no longer runs it. |
| `stage:"inngest_ghcr_fallback"` (Sentry + Better Stack phone-home) | rule, soak `[freshboot]`, soak `_zot_reports_sentry_stage`, op-contract, live-fidelity F27, `inngest-boot-emitter.test.sh`, `cloud-init-inngest-*.test.sh`, `zot-soak-6122.test.sh` G6 rows, C4 `inngest -> sentry` edge, runbook | **renamed** to `inngest_pull_fatal` everywhere |
| same | `inngest-zot-boot-7462.sh` (Better Stack) | kept. #7462 is CLOSED and the probe is inert; noted in its header. |
| `oci-pull-ALL-LEGS-FAILED`, `pre-oci-pull`, `oci-pull-rc-N`, `ghcr-login-*`, `ghcr-creds-EMPTY` (phone-home) | inngest tests only; `inngest-zot-boot-7462.sh` (inert) | removed from the template; tests restated |
| `STAGE=ghcr_login` / `stage:"ghcr_login"` / `stage:"zot_login"` (bootstrap `_sentry_emit`) | no alert rule (verified: `grep -n 'ghcr_login\|zot_login' issue-alerts.tf` → comment only) | removed |

### Institutional learnings that apply

- `2026-09-24-the-gate-the-issue-blamed-was-never-reached.md`: bake, don't fetch, at cold
  boot, and `. file` in a subshell does not export. It is the evidence for deleting the bootstrap's
  zot half. Its session errors 5, 13, 16 and 17 are pre-empted in Sharp Edges (sibling suites pin
  exact lines; repo-global ratchets; prose claims; `.sh` tests run with bash, not bun).
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`: any byte change to
  `cloud-init-inngest.yml` replaces the sole scheduler. Every comment edit here is a live-host
  input, and all of them ride the one planned replace.
- `2026-07-18-image-baked-and-latent-is-a-claim-verify-a-published-tag-exists.md` +
  `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`: the web replace ships the new
  bootstrap only if web-1 runs a release built after the merge. Phase 7 verifies the deployed
  version before dispatching.
- `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md`: with the fallback gone,
  the primary's failure must page. That is P2 and the reason `inngest_pull_fatal` is fatal, not
  deleted.
- `2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md`: comments count toward the web byte budget. This PR
  only shrinks `user_data`; the replacement prose lives in `server.tf`/the ADR, not the template.
- The #8036 1c plan (`2026-09-23-fix-retire-host-ghcr-read-path-plan.md`) and its merge
  `25aa2712ed` are the file-for-file template for the rule/soak/op-contract/live-fidelity/
  `alert-reference.json`/runbook/C4 edits (`git show --stat 25aa2712ed`).
- The #8539 plan (`knowledge-base/project/plans/archive/20260923-215442-2026-09-22-fix-inngest-private-nic-boot-race-plan.md`, §Downtime & Cutover) is the
  template for the inngest replace + `op=resume` delivery.

### Conventions in force

- `cq-cite-content-anchor-not-line-number`: every citation above is a content anchor.
- templatefile escaping: every new shell `${…}` in either template is `$${…}`. `%{` is a directive.
- `runcmd` is ONE `/bin/sh`. The seed item's `set -e`/closing `set +e` (H3, #6090) stays, and
  every new fail-open step is `|| true`-guarded.
- `hr-no-ssh-fallback-in-runbooks`: every verification below is off-box (Sentry, Better
  Stack, the replace job's own log).
- `wg-when-deferring-a-capability-create-a`: 5.4 and 5.3b-iii get verified or created trackers
  (Phase 6).

### Related issues and PRs

#8036 (parent; 1a/1b/1c done), #6122 (epic; enrolment target), #6410 (closes won't-fix after
merge), #8651/#8660 (fresh web boot, zot-by-bake), #6500 (inngest Sentry stage), #8539 (inngest
NIC race), #7462 (inngest zot-primary), #6462 (accounted beacon), #6129 (WARN→ENFORCE, gated by
the soak), #6126 (second registry, not a blocker), PR #8600 (1c).

## Problem Statement

Three facts, all measured on 2026-09-24:

1. The GHCR read PAT is revoked (ADR-096 amendment 2026-07-30; 5.5 observed 2026-09-24). Every
   host-side GHCR login and every GHCR pull of a private `jikig-ai/*` package fails.
2. The fresh-boot templates still carry that credential in `user_data` and attempt it on every
   boot. Run 35951886838 (the post-#8660 web-2 replace) shows it plainly: `stage=app_zot`,
   `ghcr_login=fail`, `fresh_boot_ready`. zot served the boot; the GHCR login failed and changed
   nothing.
3. The Sentry rule and the soak still count three GHCR signals as the evidence that retirement is
   safe, although no path that emits them can succeed. The soak's backfilled window cannot pass
   (6 historical fallbacks, each on a path fixed since), so the operator re-armed it at the
   #8660 merge.

What is broken is not availability (zot serves every boot) but **truthfulness and credential
hygiene**. The fleet carries a dead credential into every new host. The inngest host's only Sentry
page for a dark boot is named after a fallback that does not exist. And the gate that authorizes
5.6 watches signals that cannot fire.

## Proposed Solution

Delete every host-side GHCR boot leg. Rename the one signal that still has a real meaning
(a zot miss on the inngest host) and make it fatal. Narrow the rule, soak and parity test to the
two surviving signals. Re-pin and enrol the soak. Deliver it to both hosts by the operator-
authorized replaces, and observe it there.

## Technical Approach

### Architecture

Before: `fresh boot → zot login (baked) → [GHCR login (baked, revoked)] → zot pull → on miss:
GHCR pull (401) → dark`. After: `fresh boot → zot login (baked) → zot pull → on miss: fatal emit →
dark, paged`. The observable difference on a healthy boot is one fewer failed login and a
shorter stage detail. On an unhealthy boot the difference is the signal's name and level.

#### Web seed block after 1d (sketch; `soleur:work` owns the final bytes)

```sh
# apps/web-platform/infra/cloud-init.yml — inside the existing set -e host-script item
    ZL=fail; n=0; R=0
    [ -n "$ZEP" ] && while [ $n -lt 3 ]; do [ $n = 0 ] || sleep 5; n=$((n+1)); printf '%s' '${zot_pull_token}' | timeout 60 docker login "$ZEP" -u '${zot_pull_user}' --password-stdin > /run/soleur-zot-login.log 2>&1 && { ZL=ok; break; } || R=$?; done
    STAGE=pull
    C=none; ZN=0; OK=0
    case "$IMAGE_REF" in ghcr.io/*@sha256:*) REF="$ZEP/$${IMAGE_REF#ghcr.io/}" ;; *) REF=; C=unpinned ;; esac
    [ -n "$REF" ] && [ $ZL = ok ] && while [ $ZN -lt 3 ]; do …unchanged zot pull loop… ; done
    [ $OK = 1 ] || [ $C = unpinned ] || { …unchanged cause classification… ; }
    Z="zot=[login=$ZL,n=$ZN,cause=$C]"
    if [ $OK = 0 ]; then
      T=$( … unchanged redaction … | tail -c 100)
      printf 'nic=%s:%s %s pull_err: %s' "$NIC" "$W" "$Z" "$T" > /run/soleur-stage-detail
      exit 1
    fi
    printf 'zot_login=%s nic=%s:%s %s' "$ZL" "$NIC" "$W" "$Z" > /run/soleur-stage-detail
    printf '%s' "$REF" > /run/soleur-image-ref
    _emit "app image served by zot" "app_zot" info
    : > /run/soleur-stage-detail
    IMAGE_REF="$REF"
```

Load-bearing details:

- **`zot_login=ok` and `stage=app_zot` must survive byte-for-byte on the success path.**
  `web-fresh-boot-zot-8651.sh` grades the newest web-2 replace job with
  `grep -qF "stage=app_zot"` and `grep -qF "zot_login=ok"`, and #8651 stays open until the sweeper
  closes it after 2026-09-25. The Phase 7 web-2 replace may be the run it grades.
- **`unpinned` still fails loud.** `REF=` (empty) makes it explicit that a tag-only ref is
  never sent to plain-HTTP zot (#8660's integrity rule), and the fatal detail keeps
  `cause=unpinned`.
- The `ghcr=[…]` field leaves the fatal detail. `cloud-init-web-zot-seed.test.sh` has a
  cross-template parity row on `'zot=[' 'ghcr=[' 'not-attempted'`. Only `'zot=['` survives on
  both sides, so the row narrows to it.

#### Colocated inngest block (gated, `web_colocate_inngest=false`) after 1d

```sh
    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.37@sha256:<pin>   # pin carrier; never pulled (bump bot + AC6)
    ZURL='${registry_endpoint}'
    ZIREF="$ZURL/jikig-ai/soleur-inngest-bootstrap:v1.1.37@sha256:<pin>"
    if docker pull "$ZIREF"; then IREF="$ZIREF"; soleur-boot-emit inngest_zot info; else soleur-boot-emit inngest_pull_fatal fatal; exit 1; fi
```

The `curl … /v2/` probe goes: it only made sense while a miss had somewhere else to go, and it
was the #8651 anti-pattern (a probe on the resolution path). `exit 1` precedes the item's
composite trap, so the explicit emit is the only fatal. The block is dead code while the toggle
is false. It is edited so that turning the toggle on cannot resurrect an unwatched GHCR arm.

#### Dedicated inngest pull item after 1d

```sh
    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.37@sha256:<pin>   # pin carrier; never pulled
    for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
    . /etc/default/soleur-zot-read 2>/dev/null || true
    ZOT_EP="$ZOT_REGISTRY_ENDPOINT"
    if [ -z "$ZOT_EP" ]; then
      /usr/local/bin/inngest-boot-phone-home.sh inngest_pull_fatal "no zot endpoint baked"
      soleur-boot-emit inngest_pull_fatal fatal "rc=noendpoint" || true
      echo "FATAL: no zot endpoint baked and no second registry (ADR-096 5.3b-i)" >&2; exit 1
    fi
    ZIREF="$ZOT_EP/jikig-ai/soleur-inngest-bootstrap:v1.1.37@sha256:<pin>"
    /usr/local/bin/inngest-boot-phone-home.sh pre-zot-pull "$ZIREF"
    set +e; install -m 600 /dev/null /var/log/inngest-zot-pull.log
    timeout 180 docker pull "$ZIREF" > /var/log/inngest-zot-pull.log 2>&1; zot_rc=$?; set -e
    zot_tail="$(tail -n 4 /var/log/inngest-zot-pull.log 2>/dev/null | /usr/local/bin/inngest-redact.sh | tr '\n' '|' || true)"
    if [ "$zot_rc" -ne 0 ]; then
      /usr/local/bin/inngest-boot-phone-home.sh inngest_pull_fatal "zot miss ep=$ZOT_EP rc=$zot_rc tail=$zot_tail"
      soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc" || true
      echo "FATAL: zot pull failed rc=$zot_rc (no second registry, ADR-096 5.3b-i)" >&2; exit "$zot_rc"
    fi
    IREF="$ZIREF"
    /usr/local/bin/inngest-boot-phone-home.sh inngest_zot "bootstrap image served by zot ep=$ZOT_EP"
    soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
    printf 'INNGEST_BOOTSTRAP_IMAGE=%s\n' "$IREF" > /etc/default/soleur-inngest-image
    … extract / inspect / run unchanged, all following $IREF …
```

Load-bearing details:

- **Both outcome emits stay as lines matching `^\s*soleur-boot-emit inngest_zot\b` and
  `^\s*soleur-boot-emit inngest_pull_fatal\b`** (the call, then a space). The soak's `_zot_reports_sentry_stage` and `_zot_reports_offbox`
  predicates grep those syntax-anchored forms, and `^\s*ZIREF="\$ZOT_EP/` stays for
  `_zot_path_in_code`.
- **`exit "$zot_rc"` with `zot_rc=124`** (timeout) is a non-zero exit, as the old
  `exit "$pull_rc"` was, so the boot aborts either way.
- The `inngest-redact.sh` value list loses the GHCR token and keeps the zot token. The miss arm
  still ships a registry-auth tail, the case the redactor's #7462 comment exists for.

### Implementation Phases

#### Phase 0 — RED first (`cq-write-failing-tests-before`)

Write the Guard Contract rows below as failing assertions **before** touching a template:

- 0.1 Residual-zero census (Guard 1): a new assertion block, in the existing suites, that fails
  on the current tree. `cloud-init.yml`, `soleur-host-bootstrap.sh` and `cloud-init-inngest.yml`
  code lines (comments stripped): 0 `docker login ghcr.io`, 0 `ghcr_read_`, 0
  `soleur-ghcr-read`, 0 `app_ghcr_`, 0 `inngest_ghcr_fallback`, 0 `echo '${image_name}'`. Every
  `docker pull`/`docker create` argument in the three files resolves to `$REF`, `$ZIREF`, `$IREF`
  after `IREF="$ZIREF"`, or the sentinel. Host it in `cloud-init-ghcr-seed-login.test.sh` (its
  invariant 1 inverts) plus one row each in `soleur-host-bootstrap-observability.test.sh` and
  `cloud-init-inngest-bootstrap.test.sh`.
- 0.2 Soak/rule parity at 2 (Guard 2): update the op-contract test's expected size to 2 and the
  emitter legs to `inngest_pull_fatal`. RED until Phase 4.
- 0.3 Soak START pin (Guard 3): restate `zot-soak-6122.test.sh`'s START row to equality with
  `2026-09-24T03:22:41`. RED until Phase 4.
- 0.4 Zot-miss terminality (Guard 4): on the rendered inngest template (and the colocated block),
  a stubbed `docker pull` that fails must produce, in order, the phone-home `inngest_pull_fatal`,
  the `soleur-boot-emit inngest_pull_fatal fatal`, and a non-zero exit, with **no** subsequent
  `docker pull`/`docker create`. Extend `cloud-init-inngest-zot-pull-mutation.test.sh`, which
  already executes the rendered item under stubs.

#### Phase 1 — Web template + baked script

- 1.1 `cloud-init.yml`: every edit in the Structural map rows for this file, using the seed
  sketch. Keep `STAGE=pull` on the zot login/pull span so a failure keeps paging through
  `web_terminal_boot_fatal`'s `stage=pull` condition.
- 1.2 `soleur-host-bootstrap.sh`: delete the `STAGE=ghcr_login` subshell. The next `STAGE=`
  assignment (`STAGE=boot_emit`) is unchanged, so `emit_fail`'s attribution is unaffected.
- 1.3 Re-render and re-measure: `plugins/soleur/test/cloud-init-user-data-size.test.ts` (web
  gzip budget; AC4d's fatal-detail pin), `cloud-init-web-zot-seed.test.sh` (drop the GHCR G-rows,
  narrow the parity row to `'zot=['`, and restate `MIN_ASSERTIONS` to the new total **only**
  after adding the Guard 1 rows, so the floor does not silently fall),
  `soleur-host-bootstrap-observability.test.sh` (AC20/AC21 invert to residual-zero).

#### Phase 2 — Inngest template

- 2.1 `cloud-init-inngest.yml`: the Structural map rows for this file, using the pull sketch.
  Keep the CORRECTED digest-pin provenance paragraph (it is still true and was hard-won, #6617).
  Re-home it above `IREF=` when the GHCR-bake comment it sits in goes away.
- 2.2 Tests: `cloud-init-inngest-bootstrap.test.sh` (Row1/Row3 order rows re-anchored on
  `pre-zot-pull` → outcome emit; the ALL-LEGS row replaced by the Guard 4 row; the "surviving
  GHCR literals" count stays the pin-carrier count), `cloud-init-inngest-zot-pull-mutation.test.sh`,
  `inngest-boot-emitter.test.sh` (the stage-name fixture; its line on the alert reading both
  hosts' events).
- 2.3 `inngest-userdata-budget.sh` passes (the payload shrinks).

#### Phase 3 — Terraform

- 3.1 `server.tf`, `inngest-host.tf`: delete the `ghcr_read_user`/`ghcr_read_token` args and
  their comments. `inngest-userdata-budget.sh`: delete the stubs and the worst-case-length
  notes.
- 3.2 `variables.tf`: restate the `ghcr_read_token` description's consumer list (no host
  consumer since #8036 1d; remaining consumer `doppler_secret.ghcr_read_token`, retired by 5.4).
  Description-only; no state effect.
- 3.3 `terraform validate` + the render legs of the template suites (a leftover
  `${ghcr_read_*}` reference fails the render, not `validate`).

#### Phase 4 — Soak, rule, parity

- 4.1 `issue-alerts.tf` `zot_mirror_fallback_rate`: conditions become
  `registry=zot-gate-degraded` and `stage=inngest_pull_fatal`. Rewrite the comment block. The
  `app_ghcr_served` mute exception, the four-signal count and the "split it into its own
  resource" lever all refer to signals that no longer exist. State what remains: one
  rolling-deploy degrade signal and one terminal fresh-boot signal. Also drop `ghcr_login` from
  the `web_terminal_boot_fatal` comment's stage list. The resource `name` is unchanged
  (`zot-mirror-fallback-rate`), so `alert-reference.json` keys stay.
- 4.2 `alert-reference.json`: regenerate from the PR plan via the reference-gate artifact that
  `apply-sentry-infra.yml` prints on mismatch. Never hand-edit a value the gate does not
  produce.
- 4.3 `tests/scripts/test-sentry-alert-live-fidelity.sh`: re-read F27 (key-selected, needs one
  `registry` and one `stage` condition, still true at 2) and refresh the 1c comments.
- 4.4 `zot-soak-6122.sh`:
  - `FAIL_QUERIES` = `[gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'`,
    `[freshboot]='stage:"inngest_pull_fatal"'`. Floor `!= 4` → `!= 2` **in the same edit**.
  - `START="${ZOT_SOAK_START:-2026-09-24T03:22:41}"`, with the comment rewritten. It is the
    operator's re-arm on #6122 (comment 5811202876), chosen before measuring, and the merge of
    #8660. The late-START false-PASS warning stays and is restated for a re-armed window.
  - `_zot_reports_sentry_stage` greps `^[[:space:]]*soleur-boot-emit inngest_pull_fatal` followed
    by a space, in place of the `inngest_ghcr_fallback` operand.
  - Header: fix line 4 (its "(1.8) + backfills (1.9)" pre-provisioning clause → zot was
    provisioned and backfilled before the 2026-07-17 cutover). Replace "retire GHCR push/egress
    (5.3-5.5)" with what the gate now authorizes: 5.6 (ADR-096 accepted, once 5.3b-iii and 5.4
    are also done) and #6129 (WARN→ENFORCE), per `DECISION: B3`. Rewrite the COVERED/NOT COVERED
    ratio for the new set. Add the disclosed residual: web fresh-boot pull failure is paged by
    `web_terminal_boot_fatal` (`stage=pull`) and gated by the #8651 arm, but is not a FAIL_QUERIES
    member. Replace `⚠ NOT YET ENROLLED` with the enrolment record and the directive.
  - FAIL and PASS echoes: counts named `gate-degraded=` / `inngest-pull-fatal=`; the PASS line
    says what it authorizes (5.6 once 5.3b-iii + 5.4 are done; #6129), not "safe to retire GHCR
    (5.3-5.5)".
- 4.5 `zot-soak-6122.test.sh`: fixtures to the two-signal set; the G6 rows' emitter fixtures to
  `inngest_pull_fatal`; the START row (Guard 3); the floor-parity row to 2; the retired-operand row
  extended to `app_ghcr_*`/`inngest_ghcr_fallback`.
- 4.6 `sentry-zot-mirror-fallback-alert-op-contract.test.ts`: header comment; the emitter legs
  now read `cloud-init-inngest.yml` (for `inngest_pull_fatal`) as well as `cloud-init.yml` (the
  colocated block); `alarm.size == soakFailQueries().size == 2`; the whole-query-string pin; a
  residual-zero leg for the three retired values across rule, soak and both templates.
- 4.7 Wording sweep (item 7): `inngest-zot-client-authz-6500.sh` (header and the success echo:
  "retiring GHCR push/egress" → "5.3b-i / 5.6", noting #6500 is CLOSED), its `.test.sh` line 4,
  `scripts/test-all.sh`'s "the issue that GATES retiring GHCR push/egress" comment.

#### Phase 5 — Records (ADR, C4, tasks, runbooks, comments)

- 5.1 ADR-096: add "Amendment 2026-09-24 (#8036 item 1d) — 5.3b-i done: no host holds a GHCR
  credential at boot" (see the ADR/C4 section). Update the `## Status` bullets: 5.3b-i done;
  the soak re-armed at `2026-09-24T03:22:41Z` and enrolled on #6122 (earliest
  `2026-10-01T03:22:41Z`); the 5.5 bullet's "until 5.3b-i and #8036 item 1d remove them" becomes
  past tense. Status stays **Adopting**, because 5.3b-iii and 5.4 remain.
- 5.2 `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`: tick 5.3b-i with the
  PR reference and the no-reachable-success-arm ground; note the soak re-arm.
- 5.3 C4 `model.c4` (description edits only; see the ADR/C4 section), then
  `scripts/regenerate-c4-model.sh` for `model.likec4.json`.
- 5.4 Runbooks: `zot-registry-revert.md` (the "GHCR fallback above survives only on the
  fresh-boot" superseded note; the triage bullets for `app_ghcr_*`/`inngest_ghcr_fallback`; the
  rule's condition list; a revert to GHCR now needs code and a credential, not a toggle).
  `fresh-host-bootstrap-recovery.md` `pull` row (no GHCR in the seed pull). Post-mortems and older
  ADRs are historical records and are **not** edited.
- 5.5 `ci-deploy.sh` header + `zot_gate_and_login` header: comment-only (addendum item 6).

#### Phase 6 — Tracker hygiene (agent, via `gh`, before ship)

- 6.1 Enrol the soak on #6122. Append to its body
  `<!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=2026-10-01T03:22:41Z secrets=SENTRY_ACTIONS_RO_TOKEN,GH_TOKEN -->`
  and add the `follow-through` label. Both secrets are already wired in
  `scheduled-followthrough-sweeper.yml`. `earliest` is after any realistic merge, so the sweeper
  never grades the pre-merge script.
- 6.2 **The soak's PASS closes #6122.** The sweeper closes the tracker on exit 0, and #6122 is the
  migration epic, while 5.3b-iii, 5.4 and 5.6 remain. Before ship, verify that each of those has
  its own open tracker, and create any that is missing (milestone per `roadmap.md`) with a
  "re-evaluate when" line naming the soak PASS. Record the enrolment-on-the-epic choice as a
  User-Challenge in `knowledge-base/project/specs/feat-one-shot-8036-1d-retire-boot-ghcr/decision-challenges.md`
  (the operator's direction is the default and is followed; the challenge is surfaced, not
  applied).
- 6.3 PR body: the first line answers "does merging this alone mutate production?" (one Sentry
  rule updated in place, the normal release deploy to web-1, a comment-only `ci-deploy.sh`
  re-delivery; no host replaced). Then `Ref #8036`, `Ref #6122`, `Ref #6410` (not `Closes`: #6410
  closes as not-planned after merge, and a `Closes` would record it as completed).

#### Phase 7 — Delivery and verification (post-merge; orchestrator; operator-authorized on #6122)

- 7.1 Confirm the merge-triggered applies: `apply-sentry-infra.yml` applied the narrowed rule;
  the per-PR web-platform apply shows no `hcloud_server.web["web-1"]` diff (`ignore_changes`)
  and no `hcloud_server.inngest` action (excluded).
- 7.2 **Inngest first.** Dispatch `apply-web-platform-infra.yml` `apply_target=inngest-host-replace`
  in an ADR-100 window. Arm a watch on the run (`hr-dispatch-async-must-arm-watch`) and route the
  `web-platform-infra-apply` environment approval to the operator. Then dispatch
  `cutover-inngest.yml -f op=resume`. It holds in `Waiting` for a human approval, which is the
  authorization (runbook `inngest-server.md`).
- 7.3 Verify inngest off-box: Sentry `stage:"inngest_zot" host_name:"soleur-inngest"` ≥ 1 since
  the dispatch, **and** the independent Better Stack channel
  (`scripts/betterstack-query.sh --grep 'stage=inngest_zot'` under `doppler -p soleur -c
  prd_terraform`), and 0 `inngest_pull_fatal`. The heartbeat must be live again after `op=resume`.
- 7.4 **Web second.** Wait until `web-platform-release.yml` for the merge commit has deployed to
  web-1 (its run concluded success and web-1 reports that version). Then dispatch
  `apply_target=web-host-replace`, `web_host_key=web-2`, `confirm=REPLACE-web-2`, with **no
  `image_tag` override** (the default pin is web-1's running, zot-served digest). A coherence
  mismatch here means 7.4's wait was cut short. Re-check the deploy; do not override the pin.
- 7.5 Verify web off-box: the job's `fresh-host-boot-trail.sh` summary shows
  `stage=app_zot … zot_login=ok` and `fresh-host boot reached fresh_boot_ready`. Sentry
  `stage:"app_zot"` for `soleur-web-2` since the dispatch.
- 7.6 Close #6410 as not planned, with a comment naming this PR and the
  "zot retires the GHCR boot pull first" condition from its own re-evaluate clause. Comment on
  #8036 (item 1d delivered, with the two run URLs) and on #6122 (5.3b-i done; enrolment live;
  what the soak now measures).
- 7.7 Read-only soak run with the new script (`SENTRY_ACTIONS_RO_TOKEN` from Doppler): expect no
  `FAIL(no-inngest-freshboot-evidence)` after 7.3. Any remaining FAIL is the window's honest
  state (for example insufficient-sample before 2026-10-01).

## Downtime & Cutover

- **Inngest replace (7.2): offline-inducing.** The template edit force-replaces the sole
  scheduler; crons and background jobs pause from destroy until the new host boots and
  `op=resume` is approved. The last replaces measured about 15 minutes when the NIC wins and 59
  minutes when it lost (#8539, since fixed). Blue-green is unavailable (ADR-100 singleton), and no
  in-place channel can deliver a first-boot change. The ride-along alternative (wait for the next
  replace) is rejected: the operator decision on #6122 requires this replace, because the soak's
  `FAIL(no-inngest-freshboot-evidence)` clears only with a boot built from the new template.
  **Rollback:** revert the PR and run `inngest-host-replace` again. The pre-change `user_data` is
  what `origin/main` renders at this PR's base. The replace job is dispatched against `main` under the
  `infra-privileged` environment, so a rollback is a revert PR through CI plus one dispatch, not a
  single click. That bounds the dark window to roughly one CI
  cycle plus one replace. Guard 4 and the two-channel check in 7.3 exist to make that path
  unlikely.
- **Web-2 replace (7.4): no user-facing downtime.** web-2 is a standby at serving-weight 0
  (ADR-143). web-1 is untouched (`ignore_changes=[user_data]`).
- **Merge:** replaces no host. See the next section for what it does write.

### Does merging this PR alone mutate production?

Yes, through three push-triggered workflows. None of them replaces a host:

| Workflow (trigger) | What it writes | Why it is safe |
|---|---|---|
| `apply-sentry-infra.yml` (`push: main`, sentry root) | `sentry_alert.zot_mirror_fallback_rate` conditions, in place | Same rule, same name; the two surviving conditions already page today |
| `web-platform-release.yml` (`paths: apps/web-platform/**`) | a new web image, deployed to web-1 by `ci-deploy.sh` | The normal per-merge deploy. The bootstrap script is baked, not run, on web-1 (cloud-init never re-runs there) |
| `apply-deploy-pipeline-fix.yml` (`paths:` includes `apps/web-platform/infra/ci-deploy.sh`) | re-delivers `ci-deploy.sh` to the web hosts | The `ci-deploy.sh` diff is comment-only (Phase 5.5); 1c's merge took the same path |

`apply-web-platform-infra.yml`'s per-PR apply writes nothing here: `hcloud_server.web` ignores
`user_data`, and `hcloud_server.inngest` is outside its `-target` set. The PR body's first line
states this answer (Phase 6.3).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Two PRs (web vs inngest) | Parity unit spans both templates; P5 needs both; the couplings are post-merge ordering, not merge-time (see "One PR, not two"). |
| Delete `inngest_ghcr_fallback` without a replacement (the literal brief) | Removes the only Sentry page for a dark sole-scheduler boot (P2), and turns live-fidelity F27 into a NOOP. |
| Name the new stage `inngest_zot_miss` (or any `inngest_zot*` name) | `inngest_zot` would then be a **prefix** of the failure stage. Sentry `stage:` matching is exact, but the Better Stack channel is searched by substring: the soak's own remediation text says `--grep 'stage=inngest_zot'`, and `inngest-zot-boot-7462.sh` / `inngest-host-not-serving-7674.sh` `count_stage inngest_zot`. A failed boot would count as a zot-served one there. `inngest_pull_fatal` shares no prefix with `inngest_zot` or with any existing stage (`git grep -o 'inngest_pull[a-z_]*'` → 0 before this PR). |
| Keep the name `inngest_ghcr_fallback` for the zot-miss emit | It would name a fallback that does not exist. A misleading signal name is how #8036 was misread for seven weeks ("masked by the zot mirror fallback" when GHCR was the dead side). |
| Keep the bootstrap's zot-login half, reworded | It duplicates the seed block's baked login, reads its inputs through tokenless Doppler calls (#6985 class), and keeps two stale comments alive. Deleting it removes a dead Doppler dependency from the boot. |
| Add web `stage:"pull"` to the soak FAIL set | Already paged by `web_terminal_boot_fatal`. Adding it to the soak without adding it to `zot_mirror_fallback_rate` breaks the alarm⇔soak parity contract, and adding it to both double-pages. Disclosed as a residual in the soak header rather than deferred. It is not a new capability; the #8651 blocker arm gates the web boot path by human verdict. |
| Enrol the soak on a dedicated tracker instead of #6122 | The operator directed #6122. Phase 6.2 keeps 5.3b-iii/5.4/5.6 tracked so the epic's close orphans nothing, and records the choice as a User-Challenge. |
| Delete the `IREF=ghcr.io/…` pin literals | Breaks `bump-inngest-bootstrap-pin.sh` ("all four tag@sha256 pins") and disarms the AC6 pin-drift guard. |
| Retire `var.ghcr_read_*`, `doppler_secret.ghcr_read_*` and the minter now | That is 5.4. It touches `ghcr-read-credential.tf`, the minter cron and its test, and two `-target` lines in the apply workflow. Different blast radius; the next PR. |

## Scoped Advisor Consult (Phase 4.5)

One advisor-tier consult on the Overview, the phases and the riskiest phase (2 + 7.2). Applied:

- **Pin carrier.** The census now allows `ghcr.io` on code lines only as the `IREF=` pin carrier
  and the web `case` pattern (Guard 1 row 7), and the ADR amendment records why the literal
  stays. 5.4 does not touch either template, so it implies no second inngest replace.
- **Consumer sweep before deletion.** Extended to the `/run/soleur-image-ref` sentinel (no
  post-reboot reader; one mutation suite anchors on the docker-run prefix) and to the new stage
  name's substring consumers, which led to the `inngest_pull_fatal` name.
- **Whole-runcmd termination.** Guard 4 row 7 asserts that the miss arm's `exit` ends the
  rendered runcmd, not a subshell.
- **Pre-merge plan check.** FR11: the PR's own `terraform plan` shows no action on either server.
- **Rollback.** Stated honestly in Downtime & Cutover: a revert PR through CI plus one dispatch.

## User-Brand Impact

- **If this lands broken, the user experiences:** a delay in background work, not lost data.
  If the new inngest template cannot pull its bootstrap image, the sole scheduler stays dark after
  the planned replace, and every cron and Inngest-driven job (reminders, scheduled syncs, operator
  emails) waits until a revert-and-replace (bounded by one replace window, about 15–60 min). A
  broken web template affects only web-2, a serving-weight-0 standby, so no user request reaches
  it. Postgres-durable Inngest state means delayed, not lost.
- **If this leaks, the user's data is exposed via:** nothing new. The change removes a
  (revoked) GHCR credential from every future host's `user_data` and from the inngest log
  redactor's input. It adds no credential, store or connection. The one new emit carries a
  numeric rc or a fixed token in its detail.
- **Brand-survival threshold:** `none`

*Scope-out override (the diff touches `apps/web-platform/infra/**`, a preflight-sensitive path):*
`threshold: none, reason: the change deletes non-functional registry arms from host boot code and handles no end-user data; its worst failure is a bounded, paged, revertible scheduler delay on a planned replace, not exposure of a user's data or session.`

## Observability

```yaml
liveness_signal:
  what:          "Sentry stage:\"inngest_zot\" host_name:\"soleur-inngest\" (info) on every dedicated-inngest fresh boot and stage:\"app_zot\" (info) on every web fresh boot; their failure twins are stage:\"inngest_pull_fatal\" (fatal, new) and stage:\"pull\" (fatal, existing)"
  cadence:       "per fresh boot (a host replace or create); the soak aggregates them over the re-armed window from 2026-09-24T03:22:41Z"
  alert_target:  "sentry_alert.zot_mirror_fallback_rate (zot-gate-degraded + inngest_pull_fatal, value=0 per 1h) and sentry_alert.web_terminal_boot_fatal (stage=pull among its conditions); the soak via the scheduled follow-through sweeper on #6122 from 2026-10-01T03:22:41Z"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (both rules); apps/web-platform/infra/cloud-init-inngest.yml + cloud-init.yml (emitters); scripts/followthroughs/zot-soak-6122.sh (soak); .github/workflows/scheduled-followthrough-sweeper.yml (grader)"

error_reporting:
  destination:   "Sentry project web-platform via the baked DSN (web: cloud-init _emit; inngest: the host-local soleur-boot-emit), plus the inngest host's Better Stack phone-home (inngest-boot-phone-home.sh) as the independently-credentialed second channel"
  fail_loud:     "inngest: soleur-boot-emit inngest_pull_fatal fatal then a non-zero exit of the pull item; web: on_err emits 'soleur-hostscript-seed failed' with stage=pull at fatal then exit 1"

failure_modes:
  - mode:        "zot miss on a fresh dedicated-inngest boot (NIC late, zot down, auth, manifest GC) — no second registry exists"
    detection:   "Sentry stage:\"inngest_pull_fatal\" level fatal with detail rc=<n>; Better Stack phone-home inngest_pull_fatal with the redacted pull tail"
    alert_route: "sentry_alert.zot_mirror_fallback_rate pages on the first event; zot-soak-6122.sh [freshboot] FAILs the soak"
  - mode:        "zot miss on a fresh web boot (including a tag-only image ref: cause=unpinned)"
    detection:   "Sentry 'soleur-hostscript-seed failed' stage=pull fatal, detail nic=… zot=[login,n,cause] pull_err: …"
    alert_route: "sentry_alert.web_terminal_boot_fatal (stage=pull condition); the web-host-replace job's fresh-host-boot-trail.sh verdict 'booted DARK'"
  - mode:        "The new template never reaches a host (replace not run), so the soak stays blind to the dedicated host"
    detection:   "zot-soak-6122.sh FAIL(no-inngest-freshboot-evidence): 0 host-pinned inngest_zot since START"
    alert_route: "the sweeper comments on #6122 on each FAIL; scheduled-terraform-drift.yml reports the pending hcloud_server.inngest replace"
  - mode:        "Rule / soak / emitter drift after the rename (a stage renamed on one side only)"
    detection:   "apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts parity + residual-zero legs; scripts/sentry-alert-live-fidelity.sh against the live rule"
    alert_route: "CI red on the PR; the release preflight blocks on live drift"
  - mode:        "Sentry delivery fails from the inngest host (DSN/egress), making inngest_pull_fatal silent"
    detection:   "Better Stack phone-home sentry-emit-FAILED stage=inngest_pull_fatal rc=<n> (the emitter reports its own non-delivery)"
    alert_route: "scripts/betterstack-query.sh --grep sentry-emit-FAILED during the Phase 7.3 verification; the soak's FAIL(no-inngest-freshboot-evidence) message names this query"

logs:
  where:         "Sentry issue stream (both hosts' boot stages); Better Stack Logs for the inngest phone-home channel and for journald shipped by Vector once a host is up; the replace job's GitHub Actions log for fresh-host-boot-trail.sh"
  retention:     "Sentry 90 days (the soak's own reconstruction relied on it); Better Stack Logs per the shared prd source retention; GitHub Actions logs 90 days"

discoverability_test:
  command:       "jq -r '.\"zot-mirror-fallback-rate\".actionFilters[0].conditions[].comparison.value' apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "zot-gate-degraded or inngest_pull_fatal"
```

The command reads the committed projection of the live rule (the reference gate keeps it equal
to the plan that `apply-sentry-infra.yml` applies). It needs no credential or network, finishes in
milliseconds, and prints the two watched values, one of which is the literal above.

## Encryption Posture

This plan introduces **no** persistent store and **no** new connection. It **removes** one
(fresh-boot host → `ghcr.io` private-package read, on both hosts) and removes a revoked credential
from every future host's `user_data`. The section is emitted because the diff touches `*.tf` and
`cloud-init*.yml`.

```yaml
at_rest:
  - store:            "/etc/default/soleur-ghcr-read on web-1 (written at its first boot; never re-written, ignore_changes=[user_data])"
    mechanism:        "luks"
    evidence:         "implied by device_binding — /etc is on the host root filesystem; this plan stops creating the file on every future host and does not touch web-1's copy"
    defends_against:  "a seized or RMA'd disk"
    does_not_defend:  "a running host: root, or the deploy user who owns the 0600 file, can read it. The value is a revoked PAT (GET api.github.com/user → 401, measured 2026-09-20 and 2026-09-24), so the residual exposure is a dead string."
    disclosed_as:     "not-publicly-claimed"
    live_verification: "unavailable: no running-host channel reads /etc/default on web-1 without SSH, and the value is revoked, so no probe is warranted"
in_transit:
  - connection:        "fresh web host and dedicated inngest host -> zot registry (10.0.1.30:5000), the ONLY boot-time image read path after this change"
    enforced_at:       "apps/web-platform/infra/cloud-init.yml seed item (`docker login \"$ZEP\"` + `docker pull \"$REF\"`); apps/web-platform/infra/cloud-init-inngest.yml pull item (`ZIREF=\"$ZOT_EP/`)"
    tls:               "none — plain HTTP on the private Hetzner network (10.0.1.0/24, deny-all public)"
    cert_verification: "off"
    does_not_defend:   "an attacker inside 10.0.1.0/24 can read the zot pull credential and the image bytes; integrity is carried by the @sha256 digest pin (only digest-pinned refs are sent to zot), not TLS; confidentiality rests on the private network alone"
    disclosed_as:      "not-publicly-claimed"
  - connection:        "fresh host -> ghcr.io (private jikig-ai/* package read)"
    enforced_at:       "REMOVED by this change — was cloud-init.yml `STAGE=ghcr_login` + the GHCR pull arm, soleur-host-bootstrap.sh `STAGE=ghcr_login`, cloud-init-inngest.yml `docker login ghcr.io` + the GHCR-seeded `docker pull \"$IREF\"`"
    tls:               "not applicable (connection removed)"
    cert_verification: "on"
    does_not_defend:   "not applicable — the posture change is the removal of a revoked bearer credential from every future host's user_data and from each boot's outbound requests"
    disclosed_as:      "not-publicly-claimed"
exception:
  justification:      "The host->zot leg is plain HTTP by an existing, ledgered decision (scripts/encryption-posture-ledger.json row 'web hosts -> zot registry (10.0.1.30:5000)'): integrity via digest pinning, private network only. This plan does not introduce that posture; it removes the (non-functional) second read path at boot."
  tracking_issue:     "#6897"
  reevaluate_when:    "the registry is exposed beyond the private network, TLS is added to the link, or a second registry is built (#6126)"
  expires_on:         "2026-10-22"
```

The exception values are the ledger row's own (`tracking_issue: #6897`, `expires_on: 2026-10-22`).
This plan adds no ledger row.

## Guard Contract

### Guard 1 — host-side GHCR boot residual-zero

**Property.** No host-side boot code path presents a `ghcr.io` credential or pulls from
`ghcr.io/jikig-ai/*`, and no `templatefile()` passes a GHCR credential into a host's `user_data`.

**Assembly.** The chokepoints are structural, not a member list. (1) **Credential
presentation:** every `docker login` in the three boot files (`cloud-init.yml`,
`soleur-host-bootstrap.sh`, `cloud-init-inngest.yml`), asserted as "every `docker login` argument
is `"$ZEP"` or `"$ZOT_EP"`". That survives a new login site being added. (2) **Pull source:**
every `docker pull` / `docker create` image argument in the same three files resolves to a
zot-derived ref (`$REF` after the zot rewrite, `$ZIREF`, `$IREF` only after `IREF="$ZIREF"`, or
the `/run/soleur-image-ref` sentinel), never a `ghcr.io/` literal or `${image_name}`. (3)
**Template inputs:** the `templatefile()` calls in `server.tf` and `inngest-host.tf` that render
those two templates (the git-data and registry templates carry no GHCR vars; the census asserts
that too).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore one `printf '%s' "$T" \| docker login ghcr.io -u …` line in `cloud-init-inngest.yml`, after a compliant web file | RED |
| 2 | Restore `\|\| echo '${image_name}'` on **one** of the three terminal-region sentinel reads, leaving the other two compliant (the second-member row) | RED |
| 3 | Add `ghcr_read_token = var.ghcr_read_token` back to `inngest-host.tf`'s `templatefile()` map only | RED |
| 4 | Put the GHCR fallback back as `if ! docker pull "$ZIREF"; then docker pull "$IREF"; fi` **before** `IREF="$ZIREF"` (a pull of the pin carrier) | RED |
| 5 | **Dispatch row:** point the census at an empty file list (or a misspelled path) | RED — the census asserts it scanned exactly the 3 boot files + 2 `.tf` files and found ≥ 1 `docker login` and ≥ 1 `docker pull`, never "0 scanned, 0 found" |
| 6 | **Harness row (must-PASS, non-canonical):** a comment line reading `# docker login ghcr.io was removed by #8036 1d` | PASS — comments are stripped before the census |
| 7 | Add a code line `echo "fallback: ghcr.io/jikig-ai/soleur-web-platform"` anywhere in the three boot files (a `ghcr.io` occurrence that is neither an `IREF=` pin carrier nor the seed block's `case` pattern) | RED |

**Anchor.** The census reads the committed templates. The external anchor is Phase 7: the
replace jobs' own boot trails (a host built from the tree reports `zot_login=ok` and no GHCR
stage), which no commit can edit.

### Guard 2 — rule ⇔ soak ⇔ emitter parity at two signals

**Property.** The set of values `zot_mirror_fallback_rate` matches equals the soak's FAIL set
(whole query strings), both equal the set of values a boot or deploy emitter can still emit, and
the soak's runtime floor equals the declared set size.

**Assembly.** Three declarations and the emitters: `action_filters[].conditions[]` on
`resource "sentry_alert" "zot_mirror_fallback_rate"`; `declare -A FAIL_QUERIES=(` and the
`${#FAIL_QUERIES[@]} != N` floor in `zot-soak-6122.sh`; the emit call sites
(`zot_gate_degraded_event` in `ci-deploy.sh`, `soleur-boot-emit inngest_pull_fatal` in
`cloud-init-inngest.yml` and in `cloud-init.yml`'s colocated block). The chokepoint is the existing
op-contract test, extended rather than duplicated.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `[freshboot]` but leave the floor at `!= 2` | RED (the permanent-TRANSIENT class the floor exists for) |
| 2 | Rename the emit to `inngest_pull_fatal` in `cloud-init-inngest.yml` only, leaving the colocated block on `inngest_ghcr_fallback` (second emitter after a compliant first) | RED |
| 3 | Leave `stage=app_ghcr_served` in the `.tf` conditions while the soak and emitters agree at 2 | RED |
| 4 | Prefix the soak's `[freshboot]` query with `feature:supply-chain op:image-pull` | RED (the prefix trap: bare stage queries only) |
| 5 | **Harness row (must-PASS, non-canonical):** reorder the two `.tf` conditions | PASS — set equality, not sequence |
| 6 | **Harness row (must-RED):** make `alarmFilterSet()` return an empty set (e.g., anchor on `trigger_conditions = [`) | RED — the non-vacuity floor must fire, never compare ∅ = ∅ |

**Anchor.** `scripts/sentry-alert-live-fidelity.sh` compares the committed rule with the **live**
Sentry rule, a value that moves only after an apply the reviewer sees. The soak's runtime floor
is a literal compared against the array at execution time.

### Guard 3 — the soak window is the operator's re-arm

**Property.** The soak's default START is exactly the timestamp the operator recorded as the
re-arm (`2026-09-24T03:22:41`, the #8660 merge), so a later edit cannot silently move the window
past bad events.

**Assembly.** The single `START="${ZOT_SOAK_START:-…}"` assignment in `zot-soak-6122.sh` (the
only place the default is set; `sentry_count` is the only consumer, and it splices `START` into
the one query URL).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the default one second later (`2026-09-24T03:22:42`) | RED |
| 2 | Restore the old default `2026-07-17T19:45:00` | RED |
| 3 | Add a **second** `START=` assignment after the first (a later override in the script body) | RED — the row asserts exactly one assignment |
| 4 | **Harness row (must-PASS, non-canonical):** `ZOT_SOAK_START=2026-09-25T00:00:00` set in the env of a fixture run | PASS for this row (the pin is on the script default; the override is the documented test/manual seam) |

**Anchor.** The literal is recorded outside the commit in #6122 comment 5811202876 and in PR
#8660's `mergedAt`. The test row cites both, so a diff that moves the literal must also
contradict a record it cannot edit.

### Guard 4 — a zot miss is terminal and loud on the inngest host

**Property.** On any inngest bootstrap-pull failure (dedicated host or colocated block), the host
emits `inngest_pull_fatal` at fatal to Sentry (and, on the dedicated host, to Better Stack) **before**
it exits non-zero, and it attempts no further `docker pull`/`docker create`.

**Assembly.** The pull item of `cloud-init-inngest.yml` (from `IREF=` through the
`INNGEST_BOOTSTRAP_IMAGE` record) and the colocated item in `cloud-init.yml`, each **executed**
from the terraform-rendered bytes under stubbed `docker`/`soleur-boot-emit`/phone-home with a
call log. It is not grepped: the property is about order and lifetime.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | **Reorder:** move the `soleur-boot-emit inngest_pull_fatal fatal` line after `exit` (unreachable) | RED — the call log lacks the emit |
| 2 | **Reorder:** swap the emit level to `warning` | RED |
| 3 | Replace `exit "$zot_rc"` with a fall-through (`:`), so the item continues to `docker create` | RED — the call log shows a `create` after the failed pull |
| 4 | Break the colocated block's `else` arm only (second site after a compliant first) | RED |
| 5 | **Harness row (must-RED):** stub `docker` so the failing pull returns 0 | RED for the miss-case assertion (the harness must see the miss arm, or it is testing the hit arm twice) |
| 6 | **Harness row (must-PASS):** a zot **hit** | PASS — `inngest_zot info` emitted, no `inngest_pull_fatal`, extraction proceeds |
| 7 | Wrap the miss arm's `exit` in a subshell (`( … exit "$zot_rc" )`) so it ends only the subshell | RED — the harness runs the rendered runcmd from the pull item through the **next** item and asserts that item's first command never executes |

**Anchor.** Phase 7.3: the replaced host's own events on two independently-credentialed
channels.

## Architecture Decision (ADR/C4)

### ADR — amend ADR-096 in place (no new ordinal)

Add **"Amendment 2026-09-24 (#8036 item 1d) — 5.3b-i done: no host holds a GHCR credential at
boot"**:

- **Decision.** The fresh-boot GHCR arms are deleted on both templates and in the baked bootstrap
  script, on the no-reachable-success-arm ground that authorized 5.3a. Operator released 5.3b-i
  from the soak (#6122, 2026-09-24). zot is the sole boot-time read path. A zot miss ends the boot
  and pages (`stage=pull` on web, `inngest_pull_fatal` on inngest).
- **Signals.** `app_ghcr_fallback`/`app_ghcr_served` retired. `inngest_ghcr_fallback` renamed
  `inngest_pull_fatal` and raised to fatal. The rule and the soak narrowed 4 → 2.
- **Soak re-armed.** START `2026-09-24T03:22:41Z` (the #8660 merge), enrolled on #6122 with
  `earliest=2026-10-01T03:22:41Z`. The soak now gates 5.6 and #6129 only (B3).
- **What this does NOT do.** No change to CI push/read (B3), to the anonymous `ghcr.io` pulls of
  the cosign verifier and zot's own image, or to the egress allow (5.3b-iii). `var.ghcr_read_*`,
  `doppler_secret.ghcr_read_*` and the minter remain until 5.4. web-1 keeps its first-boot
  `/etc/default/soleur-ghcr-read` (revoked value; no running-host channel removes it).
- Update `## Status` as in Phase 5.1. The ADR stays **Adopting**.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Elements checked, and all
**already modeled**: external actor (none new; no human role changes), external systems `ghcr`,
`projectZot`, `zotRegistry`, `sentry`, `betterstack`, `doppler` (all present and included in
both context views in `views.c4`), containers `hetzner` (web hosts) and `inngest`. No element is
added or removed, so `views.c4`/`spec.c4` are unchanged. **Description edits** that this change
falsifies (edited directly in `model.c4`, then `scripts/regenerate-c4-model.sh`):

- `ghcr` system: "(the FRESH-BOOT seed pull keeps a GHCR leg … its retirement is #8036 1d —
  #8651)" → retired by 1d; no host presents a GHCR credential.
- `hetzner -> zotRegistry`: "(the fresh-boot seed pull keeps a login-gated GHCR leg, #8036 1d,
  which cannot authenticate while the PAT is revoked)" → sole at boot too; a miss is fatal.
- `hetzner -> ghcr`: "The fresh-boot seed pull still has a login-gated private-package GHCR leg
  (#8036 1d …)" → removed; the edge remains the anonymous cosign-verifier pull only.
- `inngest -> sentry`: "stage inngest_zot / inngest_ghcr_fallback" → `inngest_zot` /
  `inngest_pull_fatal` (fatal).
- `inngest -> doppler`: "The remaining consumer is cloud-init's fresh-boot root `ghcr_login`,
  which is 1d scope" → no host consumer remains; the write is declared-but-inert until 5.4.

Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
`plugins/soleur/test/c4-count-parity.test.sh` (bash). No derived cardinality in edge prose moves
(no monitor or rule is added or removed), and the parity run is the evidence for that.

### Sequencing

The decision is true at merge for the templates and at Phase 7 for the hosts. The amendment says
both and records the two run URLs once Phase 7 completes (a follow-up commit on `main` is not
needed; the #8036 and #6122 comments carry the URLs).

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf`, `apps/web-platform/infra/inngest-host.tf`: remove the
  `ghcr_read_user`/`ghcr_read_token` keys from the `templatefile()` maps. No resource is added or
  removed; no provider or version change.
- `apps/web-platform/infra/variables.tf`: description text only.
- `apps/web-platform/infra/sentry/issue-alerts.tf`: one `sentry_alert` updated in place
  (conditions + comments; name, frequency and trigger unchanged).
- Sensitive variables: none added. `TF_VAR_ghcr_read_user`/`_token` stay required by
  `doppler_secret.ghcr_read_*` until 5.4 (sourced from Doppler `prd_terraform`, unchanged).

### Apply path

- Web: (b) cloud-init + existing running-host channels. web-1 is untouched
  (`ignore_changes=[user_data]`). web-2 gets the new `user_data` on the Phase 7.4 replace. The
  bootstrap script reaches web-1 only as baked content of the next release image (it does not
  re-run there; web-1 never re-runs cloud-init).
- Inngest: (c) `-replace` via `inngest-host-replace` (the only path; ADR-100), in an ADR-100
  window, followed by `op=resume`. Expected about 15 min of scheduler pause.
- Sentry: applied by `apply-sentry-infra.yml` on merge.

### Distinctness / drift safeguards

- `hcloud_server.web` `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]`:
  the web template change is inert on web-1.
- `hcloud_server.inngest` has no `ignore_changes` on `user_data`. Between merge and 7.2,
  `scheduled-terraform-drift.yml` reports a pending replace. That is expected and clears at 7.2.
- The inngest replace gate (`tests/scripts/lib/inngest-host-replace-gate.sh`) refuses any plan
  other than the exact scoped recreate and preserves the Redis AOF volume.
- `dev != prd`: no Doppler or Supabase config is touched.

### Vendor-tier reality check

No vendor tier is involved. The replace job's stock preflight covers Hetzner orderability for the
inngest server type.

## Files to Edit

### The change itself

- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/soleur-host-bootstrap.sh`
- `apps/web-platform/infra/cloud-init-inngest.yml`
- `apps/web-platform/infra/server.tf`
- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/infra/inngest-userdata-budget.sh`
- `apps/web-platform/infra/ci-deploy.sh` (comments only)
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json` (regenerated)
- `scripts/followthroughs/zot-soak-6122.sh`

### Consumers that fail loudly (tests)

- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` (invariant 1 inverts; 2 and 3 kept)
- `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`
- `apps/web-platform/infra/inngest-boot-emitter.test.sh`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`
- `tests/scripts/test-sentry-alert-live-fidelity.sh`
- `scripts/followthroughs/zot-soak-6122.test.sh`
- `apps/web-platform/infra/doppler-download-error-channel.mutation.py` (anchors on the terminal
  `docker run` line's `"$(cat /run/soleur-image-ref` prefix; run it, edit only if the anchor moves)

### Operator-facing text that becomes false

- `scripts/followthroughs/inngest-zot-client-authz-6500.sh`, `scripts/followthroughs/inngest-zot-client-authz-6500.test.sh` (wording)
- `scripts/followthroughs/inngest-zot-boot-7462.sh` (header note: tracker closed, stage renamed)
- `scripts/test-all.sh` (one comment)
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`
- `knowledge-base/engineering/operations/runbooks/fresh-host-bootstrap-recovery.md`

### Architecture record

- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerated `model.likec4.json`)
- `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`

### Deliberately NOT edited

- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` (#8651's probe grades its output
  until #8651 closes; its `app_ghcr_*` stages become a vacuous tripwire).
- `scripts/followthroughs/web-fresh-boot-zot-8651.sh`, `accounted-beacon-live-6462.sh` (graders of
  historical/closed windows).
- `.github/scripts/bump-inngest-bootstrap-pin.sh` and the four pin literals.
- `ghcr-read-credential.tf`, `ghcr-minter-doppler-token.tf`, `cron-ghcr-token-minter.ts`, the
  `-target=doppler_secret.ghcr_read_*` workflow lines (5.4).
- Post-mortems and ADRs other than ADR-096 (historical records).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-8036-1d-retire-boot-ghcr/decision-challenges.md`
  (the Phase 6.2 User-Challenge; written by the pipeline, rendered by `ship`).

No new script or test file: every guard extends an existing suite already wired in
`infra-validation.yml` / `scripts/test-all.sh` / the vitest and bun suites.

## Open Code-Review Overlap

3 open `code-review` issues mention a planned file:

- #3216 (`server.tf` resource-boundary regex, resolved inline): **Acknowledge.** Different
  concern (a canary bundle regex); this plan only deletes two `templatefile()` map keys.
- #2197 (`server.tf` `count`/`for_each` vs in-memory throttles): **Acknowledge.** Unrelated; no
  `count`/`for_each` change here.
- #8487 (capability-gate corpus follow-ups naming `cloud-init-inngest-bootstrap.test.sh`'s CI
  predicate): **Acknowledge.** It concerns the "under CI" predicate convergence, which this plan
  does not touch. The suite's rows edited here are the pull-order rows.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled here.
- **Every byte in `cloud-init-inngest.yml` is a live-host input.** Comment edits included, the
  whole file ships only through the Phase 7.2 replace. Do not "tidy" it in a follow-up without a
  planned replace.
- **A new stage name must not extend an existing one.** Better Stack greps are substring
  matches, so `stage=inngest_zot` would also match any `inngest_zot…` stage. That is why the
  failure stage is `inngest_pull_fatal` (Alternatives). Guard 2's residual-zero leg also asserts
  no emitted stage in either template begins with `inngest_zot` other than `inngest_zot` itself.
- **The four pin literals are load-bearing data, not a GHCR leg.** Guard 1's census must exempt
  the `IREF=ghcr.io/…` assignment line and assert it is never a `docker pull`/`create` argument
  before `IREF="$ZIREF"`, not assert "0 `ghcr.io` literals". Tighten it the other way too: in the
  three boot files, `ghcr.io` may appear on code lines **only** as the `IREF=` pin-carrier
  assignment (one per inngest site) and in the web seed block's `case "$IMAGE_REF" in
  ghcr.io/*@sha256:*)` rewrite pattern. Any other code occurrence is RED. The ADR-096 amendment
  records why the literal stays (bump bot + AC6), so a later reader does not "finish the job".
  5.4 will not touch either template (after this PR neither references `ghcr_read_*`), so no
  second inngest replace is implied by 5.4.
- **`/run/soleur-image-ref` has no reader outside first-boot runcmd.** Verified:
  `git grep -n soleur-image-ref` outside tests hits only `cloud-init.yml`, plus
  `doppler-download-error-channel.mutation.py`, which anchors on the `"$(cat /run/soleur-image-ref`
  prefix of the terminal `docker run` line. Keep that prefix byte-identical when dropping the
  `2>/dev/null || echo '${image_name}'` tail, and run that mutation suite. `/run` is tmpfs, but no
  unit reads the sentinel after a reboot, so its absence then is harmless.
- **Before merge, the PR's own `terraform plan` (the apply workflow's plan job) must show no
  `hcloud_server.web` action and no `hcloud_server.inngest` action.** The inngest replace
  belongs to the Phase 7.2 dispatch only; web-1 must stay untouched for the coherence preflight.
- **Grep sibling suites for every exact line rewritten before editing a hot site** (#8651 session
  error 5). `cloud-init-user-data-size.test.ts` AC4d pins the fatal-detail line;
  `cloud-init-web-zot-seed.test.sh` pins the parity tokens and `MIN_ASSERTIONS`.
- **Run the repo-global ratchets before every commit that adds a test or a regex** (#8651 session
  error 13): the `run_suite "scripts/lint-` lines of `scripts/test-all.sh`, plus
  `plugins/soleur/test/fixture-*-assert.test.sh`. Run `.sh` suites with bash, never `bun test`.
- **Derive mutation anchors from the rendered artifact**, not source indentation (#8651 session
  error 2). The inngest mutation suite already renders; reuse its helpers.
- **`alert-reference.json` is produced, not written.** Take it from the reference-gate artifact
  of the PR's own `apply-sentry-infra.yml` plan run.
- **`web-fresh-boot-zot-8651.sh` is still live until #8651 closes.** The success detail must
  keep `zot_login=ok`, and the trail must keep printing `stage=app_zot` on the image-origin line.
- **The soak's `earliest` is 2026-10-01.** A read-only run before then legitimately FAILs on
  insufficient sample or evidence; that is not a regression.
- **Coherence preflight after merge.** `web-host-replace` refuses until web-1 runs the release
  built from the merge commit. Waiting is the fix; an `image_tag` override naming an unmirrored
  release is not.
- **Check every claim the diff's prose asserts** (#8651 session error 16). In particular: the
  web app image and the inngest bootstrap image are **private** GHCR packages; "no host presents
  a GHCR credential" is scoped to host boot code, and CI still reads GHCR (B3); the cosign
  verifier and zot's own image still pull **anonymously** from `ghcr.io` (5.3b-iii).

## Acceptance Criteria

FR1-FR10, NFR1-NFR3 and QG1-QG3 are **pre-merge** (the PR). QG4-QG5 are **post-merge**
(Phase 7, run by the orchestrator under the operator's #6122 authorization; the two human
approvals are the environment gate and `op=resume`).

### Functional Requirements (pre-merge)

- [ ] FR1. On the rendered web template, the baked bootstrap and the rendered inngest template, the
  Guard 1 census reports 0 `docker login ghcr.io`, 0 `ghcr_read_`, 0 `soleur-ghcr-read`, 0
  `app_ghcr_`, 0 `inngest_ghcr_fallback` and 0 `echo '${image_name}'` code lines, and every
  pull/create argument is zot-derived (`cloud-init-ghcr-seed-login.test.sh`,
  `soleur-host-bootstrap-observability.test.sh`, `cloud-init-inngest-bootstrap.test.sh`).
- [ ] FR2. `server.tf` and `inngest-host.tf` pass no `ghcr_read_*` key to `templatefile()`;
  `terraform validate` and both template render legs pass.
- [ ] FR3. A failing zot pull on the rendered inngest item (and the colocated block) produces, in
  order, phone-home `inngest_pull_fatal` (dedicated host), `soleur-boot-emit inngest_pull_fatal fatal`,
  a non-zero exit, and no later pull/create (Guard 4, `cloud-init-inngest-zot-pull-mutation.test.sh`).
- [ ] FR4. A successful web seed pull writes detail `zot_login=ok nic=… zot=[login=ok,…]` and emits
  `app_zot` info. A failing one exits 1 with `nic=… zot=[…] pull_err: …` and `STAGE=pull`
  (`cloud-init-web-zot-seed.test.sh`).
- [ ] FR5. `zot_mirror_fallback_rate` matches exactly `registry=zot-gate-degraded` and
  `stage=inngest_pull_fatal`. `zot-soak-6122.sh` `FAIL_QUERIES` has exactly `[gate]` and
  `[freshboot]='stage:"inngest_pull_fatal"'`, with floor `!= 2`. The op-contract test pins
  `alarm.size == soakFailQueries().size == 2` and asserts residual-zero for the three retired values.
- [ ] FR6. `zot-soak-6122.sh` default START is exactly `2026-09-24T03:22:41` (one assignment), and
  `_zot_reports_sentry_stage` accepts the new template (a CLOSED-COMPLETED #6500 fixture passes the
  code-corroboration arm against the post-change `cloud-init-inngest.yml`).
- [ ] FR7. `alert-reference.json` equals the reference-gate projection of the PR's plan
  (`apply-sentry-infra.yml` reference gate green).
- [ ] FR8. #6122's body carries
  `<!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=2026-10-01T03:22:41Z secrets=SENTRY_ACTIONS_RO_TOKEN,GH_TOKEN -->`
  and the `follow-through` label, verified with `gh issue view 6122 --json body,labels`.
- [ ] FR9. Open trackers exist for 5.3b-iii and for 5.4 (and 5.6 or its equivalent), each named in
  the #6122 comment of Phase 7.6.
- [ ] FR10. ADR-096 carries the 1d amendment and updated `## Status`; tasks.md 5.3b-i is ticked;
  `model.c4` has the five description edits; the stale comments of addendum item 6 and the
  wording of item 7 are gone (a grep for `(1.8) + backfills (1.9)` across `ci-deploy.sh`,
  `soleur-host-bootstrap.sh` and `zot-soak-6122.sh` returns 0).
- [ ] FR11. The PR's own `terraform plan` output (the apply workflow's plan job on the PR) shows
  no action on `hcloud_server.web` and none on `hcloud_server.inngest`.

### Non-Functional Requirements

- [ ] NFR1. Rendered web `user_data` stays under the gzip budget in
  `cloud-init-user-data-size.test.ts` and shrinks relative to `origin/main`. The inngest payload
  passes `inngest-userdata-budget.sh`.
- [ ] NFR2. No `MIN_ASSERTIONS`/floor in any edited suite falls without a same-edit row that
  replaces the deleted coverage (Guard 1/4 rows added before the floor is restated).
- [ ] NFR3. No new `doppler` call anywhere in either template's runcmd (the #8651 census stays
  green).

### Quality Gates

- [ ] QG1. All suites under "Consumers that fail loudly" green; `infra-validation.yml` green;
  vitest (`apps/web-platform`) and bun (`plugins/soleur`) green; the repo-global ratchets
  (`scripts/test-all.sh` `lint-*` lines, `fixture-*-assert.test.sh`) green.
- [ ] QG2. `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-count-parity.test.sh` green.
- [ ] QG3. `lint-guard-contract.py` passes on this plan (4 guards, each with ≥ 3 rows).

### Post-merge (Phase 7)

- [ ] QG4. Post-merge (Phase 7): the inngest replace run and the web-2 replace run both reach
  `fresh_boot_ready`. Sentry shows `stage:"inngest_zot" host_name:"soleur-inngest"` ≥ 1 (corroborated
  on Better Stack) and `stage:"app_zot"` for `soleur-web-2` ≥ 1 since the respective dispatch, with 0
  `inngest_pull_fatal` and 0 web `stage=pull` fatal. `op=resume` approved and the heartbeat live.
- [ ] QG5. #6410 CLOSED as not planned with the superseding comment; #8036 and #6122 carry the
  delivery comments with both run URLs.

## Domain Review

**Domains relevant:** engineering

All eight domains were assessed against this plan. Marketing, sales, finance, legal, support,
product and operations carry no implication. There is no user-facing surface, pricing, billing,
personal-data processing or support-visible behavior. No vendor account, plan or cost moves: both
registries are already provisioned, and the planned inngest replace re-creates an existing server
at the same type. The operations-adjacent facts are covered in the plan body: the replace window
and `op=resume` (Downtime & Cutover), and the 5.4 secret retirement kept as the next PR.

### Engineering

**Status:** pending (CTO assessment is appended below after the Phase 2.5 run)

### Product/UX Gate

Not applicable: Files to Edit/Create contain no UI-surface path (mechanical override checked
against `ui-surface-terms.md`), and the change is infrastructure-only. Tier: none.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- T1 (Guard 1): each residual-zero mutation row reddens its suite; the comment-only row passes.
- T2 (Guard 2): soak/rule/emitter parity rows as in the matrix.
- T3 (Guard 3): START pin rows.
- T4 (Guard 4): executed rendered-item rows (miss, level, fall-through, colocated, harness hit).

### Regression Tests

- R1. A zot **hit** on both templates proceeds exactly as before: `app_zot` info / `inngest_zot`
  info, then extraction and bootstrap, with the same `IREF` consumers (pull, create, inspect,
  record) following the zot ref.
- R2. `cause=unpinned` for a tag-only web image ref still fails loud with that cause.
- R3. The NIC wait and its `private_nic_*` emits are unchanged on both hosts.
- R4. `web-fresh-boot-zot-8651.sh` PASSes against a synthetic trail built from the new success
  detail (`zot_login=ok … stage=app_zot … fresh_boot_ready`).
- R5. The soak's `BLOCKER`/`WEB_BLOCKER` arms behave as before (a fixture with #8651 OPEN still
  yields `FAIL(blocked-web)`).

### Edge Cases

- E1. Empty zot endpoint on the inngest host (compile-time constant, so unreachable in this root):
  fatal `inngest_pull_fatal` with `rc=noendpoint`, never a GHCR attempt.
- E2. zot pull timeout (`rc=124`): same fatal path with `rc=124`.
- E3. Sentry delivery failure from the inngest host: phone-home `sentry-emit-FAILED
  stage=inngest_pull_fatal`, and the boot still exits non-zero.

### Integration Verification (for `soleur:qa`)

- The Phase 7 runs are the integration test. There is no staging host for either template; the
  replace jobs' own trails and the two-channel event check are the evidence.

## Success Metrics

- 0 host-side GHCR boot code paths (Guard 1) and 0 GHCR credentials in any new host's `user_data`.
- Both replaced hosts reach `fresh_boot_ready`, zot-served, on the first dispatch.
- The soak, enrolled, grades from 2026-10-01T03:22:41Z with no `no-inngest-freshboot-evidence`.

## Dependencies & Prerequisites

- #8660 merged (done, `2026-09-24T03:22:41Z`); #6500 CLOSED COMPLETED (done).
- #8651 closes via the sweeper after 2026-09-25. It is **not** a merge prerequisite; it is one of
  the soak's arms.
- The `web-platform-release.yml` deploy of the merge commit to web-1 is a prerequisite of Phase 7.4
  only.
- An ADR-100 window and the operator's environment approval plus `op=resume` approval for Phase 7.2.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The new inngest template cannot pull (zot miss on the replace boot) | Low: the current template is already zot-served, and #8539 fixed the NIC race | Scheduler dark until revert + replace | `inngest_pull_fatal` fatal pages on two channels; rollback is revert + replace; the same failure pre-1d ended in a 401 on GHCR anyway |
| Coherence preflight refuses the web-2 replace | Expected until the release deploy lands | Delay only | 7.4 waits for the deploy; never override the pin |
| A test suite pins an exact line this PR rewrites | High (many suites) | CI red | Sibling-suite grep before each hot-site edit; the census rows land first (Phase 0) |
| The soak PASS closes the epic #6122 while follow-up tasks remain | Certain on PASS | Orphaned 5.3b-iii / 5.4 / 5.6 | Phase 6.2 trackers + User-Challenge record |
| `alert-reference.json` hand-edited and drifts | Medium | Reference gate red | Take the gate's artifact (Sharp Edges) |
| The rename leaves one emitter on the old name (colocated block) | Medium | Unwatched signal if the toggle flips | Guard 2 row 2 |

## Documentation Plan

ADR-096 amendment + Status; tasks.md; `model.c4`; `zot-registry-revert.md`;
`fresh-host-bootstrap-recovery.md`; the soak header. No user-facing docs change.

## References & Research

### Internal

- #8036 comments 2026-09-23 "Item 1d sequencing" and "Addendum 2026-09-24"; #6122 comment
  5811202876; #6410 comment 2026-09-23.
- `knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md` (1c) and merge
  `25aa2712ed`.
- `knowledge-base/project/plans/archive/20260924-005225-2026-09-23-fix-web-host-fresh-boot-zot-primary-plan.md` (#8660).
- `knowledge-base/project/plans/archive/20260923-215442-2026-09-22-fix-inngest-private-nic-boot-race-plan.md` (#8539 delivery).
- `knowledge-base/project/learnings/2026-09-24-the-gate-the-issue-blamed-was-never-reached.md`.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (`op=resume`),
  `web-host-replace.md`.

### Related work

PR #8600 (1c), PR #8660 (#8651), PR #8456 (1a/1b), #6129, #6126, ADR-100, ADR-143, ADR-169.
