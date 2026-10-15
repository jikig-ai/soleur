---
title: "fix(registry): Phase 2 batch - htpasswd off argv, clientIP RFC1918 alert, 8408 close-out"
date: 2026-10-14
slug: registry-phase2-batch-htpasswd-stdin-clientip-alert
branch: feat-one-shot-registry-phase2-batch-10119-8408-7530
issue: 10119
type: fix
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# fix(registry): Phase 2 batch - htpasswd off argv, clientIP RFC1918 alert, 8408 close-out

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed). There is no brainstorm and no spec.md for this branch (one-shot path).

## Re-scope addendum (2026-10-15, before ship) - READ FIRST, it supersedes what follows

**What changed.** The owner's parallel session merged PR #10322 (merge commit 8c8401e6fa, 2026-10-15T09:36Z) which carries the whole #10119 registry-template conversion (htpasswd on stdin, both heartbeat curls on a stdin `--config`, the S6 allowlist deleted plus the S6-REG scan, the `htpasswd-stdin.test.sh` boot rows, and its own `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` probe). Its registry host replace ran (dispatcher run 38714214071, apply run 38715505652) and #10119 was closed on that probe's PASS verdict. The collision recorded in the Hand-over below is therefore resolved in favour of #10322, and this branch was re-based onto it by taking main's version of every #10119 file (the template, the stdin/boot-guard/heartbeat/image-fetch suites, ADR-280, the battery, the 10119 probe and its registrations) and keeping only the #7530/#8408 work.

**What this PR is now.** Part B (the standing alert `registry_clientip_not_rfc1918`, Terraform only), Part C (the #8408 close-out, an issue-side action with no repo change), Part D (#7456(c) parked, #7521 measured) and the #7530 half of Part E (one post-merge probe). **Part A and Phase 5 are superseded and absent from this PR: `apps/web-platform/infra/cloud-init-registry.yml` is NOT changed, so merging does not fire `registry-host-replace-dispatch.yml` and no registry host replace happens.** Every statement below about Part A, the replace, the recovery script, the byte table and the "one batch, one replace" framing describes the abandoned shape and is kept only as the dated record of how the decision was reached.

**What still applies at merge.** The push apply of `apps/web-platform/infra/betterstack-logs-alerts.tf` plus the two new `-target` lines creates the exploration and the alert in Better Stack through the logtail provider (no host effect; serialized by the `terraform-apply-web-platform-host` concurrency group), `web-platform-release.yml` fires for the `apps/web-platform/test/infra` file (a routine release), `version-bump-and-release.yml` fires for the one `plugins/soleur/test` edit. Pre-merge: the in-flight read of `apply-web-platform-infra` (status != completed) must be empty; the post-merge evidence is the 7530 probe plus the alert's existence in Better Stack. The owner still gives the explicit go for the merge time (no auto-merge armed).

## Enhancement Summary

**Deepened on:** 2026-10-14
**Method:** mechanical halt gates 4.6 to 4.12 run against the plan (all pass), the Quality Checks verifications, plus the evidence already gathered by the planning pass (CTO, CLO and CPO leaders, a five-agent plan-review panel, a catalogue verification pass, live read-only Better Stack measurements). A full 40-agent fan-out was not repeated: every domain it would cover was already reviewed against this exact text, and a second broad pass over a plan this size would mostly re-find the same items.
**Research agents used:** `soleur:engineering:cto` (x2), `soleur:legal:clo`, `soleur:product:cpo`, `soleur:engineering:review:dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `soleur:product:spec-flow-analyzer`, a learnings researcher, a sharp-edges verification agent, `soleur:gdpr-gate`.

### Key improvements

1. The batch is smaller and truer than the brief: #8408 is already delivered (PR #8456 verified to touch the template, the alert file, the launch-gate and escrow suites), the #7530 "plausible site" is dormant, the readiness rider and the third probe are cut.
2. The #7530 invariant is enforced by a live-validated predicate: 7-day population, positive control and a 16-literal classification table all run through the real engine.
3. Every post-merge read is keyed on the merge SHA, the verdict-comment semantics are corrected (success posts nothing), the P3 premise is corrected, and probe exit arms and run identity are defined.

### New considerations discovered

- A missing follow-through script on main only logs `missing in repo HEAD` (no tracker comment, no red run); the cost of pre-merge enrollment is a daily log line.
- A Better Stack alert added to this file has four mandatory consumers beyond the .tf (send-failed mutation suite count, `betterstack-log-query.md` row, `infra-validation.yml`, orphan-suite registration).
- The alert is correct only while zot writes `clientIP` first; the suite pins the verified zot digest so a bump forces a live re-check.

## Overview

Phase 2 of epic #10205 (the zot registry arc) groups the remaining registry-template work into ONE pull request, so
the production registry host is replaced once, under one deploy freeze. Every issue below is `Ref #N` in the PR
(never a closing keyword, per the decision-challenge #10301); each closes only after post-merge evidence, and the
pipeline never merges this PR (it stops at a green, ready PR and hands the owner the exact merge command and watch
steps, see `## Hand-over`).

What the investigation found changes the batch's shape, so read this table before the rest:

| Issue | What the brief assumed | What is true (measured 2026-10-14) | What the batch does |
|---|---|---|---|
| #10119 (htpasswd off argv, B1/B2) | three template lines to convert, about 100 B of user_data headroom | confirmed; the recipe, the real-binary suite (`htpasswd-stdin.test.sh`) and the S6 stage already exist on main. Measured on a scratch copy of the template: all planned edits cost +36 B stored (21,500 to 21,512 for the htpasswd edits, to 21,536 with both heartbeat curls), leaving 64 B under the 21,600 B `REGISTRY_GZIP_BUDGET` | the only cloud-init-registry.yml change: 3 htpasswd sites, `install -m 600`, the 2 registry heartbeat curls (PR B scope of the PR A plan, #10093 part), comment rewording |
| #8408 (alert, reboot-surviving gate, escrow re-test) | all three parts unbuilt | **all three delivered** by PR #8456 (merge `69b08a4ee`, host replaced 2026-09-22): alert `registry_store_not_luks` armed (`betterstack-logs-alerts.tf`, `-target=` lines present), zot start gated by the `--mount` sentinel bind plus the NIC-guard recovery arm, daily `luksOpen --test-passphrase` re-test with `store_escrow=` on the heartbeat. The owner closed it 2026-09-28 with an evidence table; the follow-through sweeper REOPENED it the same night because its body still carries the `registry-luks-live-8386.sh` directive and that probe exits 5 by design on every sweep | NO cloud-init change and no new probe for #8408 (CTO ruling C1/C2). End the reopen loop (drop the directive and label); the owner closes it after the merge with the batch's read-only posture evidence |
| #7530 (RFC1918 clientIP invariant) | "plausibly in `zot-log-channel-7440.sh`" | that probe has not run since about 2026-08-27: its tracker #7455 was auto-closed by the sweeper's PASS on 2026-08-13 and the sweeper reads closed trackers only inside `CLOSED_LOOKBACK_DAYS=14`. An arm added there would be dormant. The invariant does hold today: about 18,780 envelope rows with a `clientIP` over 7 days (hot plus archive; two runs seconds apart read 18,780 and 18,781), all RFC1918 (`10.0.1.10`/`10.0.1.11`), zero on `SOLEUR_ZOT_DISK` rows, across 5 boots | a standing Better Stack alert `registry_clientip_not_rfc1918` (CTO ruling A2), mirroring `registry_store_not_luks`: no host bytes, no replace of its own |
| #7456(c) (rate-cap retune) | decide with the CTO | CTO ruled: no retune (zero `exempt_cap` drops in the 23,570/day measurement) | none; the ruling and the future evidence bar are recorded on #7521 and #7456 |
| #7079 item 1 survivor (readiness loop) | free rider only | in the same `ZOTEOF` runcmd entry the htpasswd edit touches; measured cost +32 B (to 21,568, 32 B of headroom). Plan review (simplicity and DHH lenses) found it satisfies no property of this batch and the CTO already ruled that its result feeds nothing | **not included** (CTO allowed the drop; the 2 B margin over the 30 B floor and the `%%{` escape hazard are not worth a sole-pull-path boot block). #7079 stays open with the measured cost noted |

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief or issue | Reality | Plan response |
|---|---|---|
| The held-back-sites plan is under `plans/archive/` | it is NOT archived: `knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md` (Part B items 1 and 2 are the recipe); the PR A plan IS archived (`plans/archive/20261014-173446-...-plan.md`, section "PR B") | both read; recipe reused verbatim where still true |
| Post-merge watch includes the `<!-- registry-delivery run=... kind=` PR comment | `registry-host-replace-dispatch.yml` posts that comment ONLY on non-success arms (the step is `if: always() && (job.status != 'success' || steps.poll.outputs.apply_conclusion == 'unverified')`); a clean delivery leaves NO comment | the watch asserts the ABSENCE of a verdict comment on PR #10320 plus the run's step conclusions (Dispatch and Poll steps `success`, which proves `deliver=true`); a comment of any `kind=` is the failure signal |
| #8408 needs two `-target=` lines and a test suite | both exist (`apply-web-platform-infra.yml` carries `logtail_exploration(_alert).registry_store_not_luks`; `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh`, registered in `infra-validation.yml`) | reuse as the template for the #7530 alert |
| #10119: "about 100 B of headroom" | exactly 100 B (stored 21,500 vs `REGISTRY_GZIP_BUDGET` 21,600 in `cloud-init-user-data-size.test.ts`); raw headroom to Hetzner's cap is 11,268 B but the policy budget governs | measured plan, see Research Insights |
| `store_probe_rc` PID bug folded into #8408 (b) | already fixed and closed (#8417); live rows read `store_probe_rc=cs0.bk0` | nothing to do |
| The `zot-log-channel-7440.sh` header: "stays enrolled as a REGRESSION detector" | false in practice (see table above) | separate tracked issue #10321 (CTO ruling); not repaired here |
| A merge-fired web release may fail while the registry is replaced | the replace preflight P3 WAITS up to 2,100 s for the release the merge co-fires, so the replace starts after that release finishes; only a LATER, separately triggered release can overlap the replace | Hand-over states this precisely (this corrects ruling H item 3's premise; recorded in decision-challenges.md) |
| ADR-211 says "owned by #7530" in two places | one prose sentence plus a `related_issues` frontmatter entry; the other owners-of-#7530 statements are in `article-30-register.md` PA-8 sections (c) and (g) and in `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md` ("Not attesting to `clientIP`") | all four named in Files to Edit / CLO routing |

## Research Insights

**Premise Validation (Phase 0.6).** Checked by `gh issue view` and `git grep` on `origin/main` (29c5898294): #10119 OPEN (labels deferred-scope-out, p3-low; claimed for this batch by the owner's comment); #8408 OPEN with `stateReason REOPENED` (closed by the owner 2026-09-28T17:22Z, reopened by github-actions 22:46Z); #7530 OPEN; #7456 and #7521 OPEN; #8386 CLOSED 2026-10-13; #7455 CLOSED 2026-08-13; #10301 OPEN (informational); #7079 OPEN (item 1 survivor verified: the readiness `for` loop's `curl -s -o /dev/null "http://localhost:5000/v2/" && { echo "[zot] listening on :5000"; break; }` line). Stale premise found and carried into the table above: #8408 is delivered in code. ADR corpus grepped for the mechanisms: ADR-280 (stdin config; its 2026-10-12 addendum already prescribes `htpasswd -i` and the heartbeat-URL inline form), ADR-218 (native Better Stack Logs alerts are Terraform-managed via the logtail provider, one amendment per new alert), ADR-211 (assigns the clientIP question to #7530), ADR-184 (the shipper). None rejects the chosen mechanisms.

**Property List (Phase 0.6b).**

1. No registry-template htpasswd password reaches any process argument list (3 sites).
2. `/etc/zot/htpasswd` is never world-readable, not even transiently at boot.
3. The registry heartbeat URLs (Better Stack ping URLs: argv-clean after this change, not secret at rest, ADR-280 residual) reach curl on its stdin config, not argv (2 sites).
4. Any non-RFC1918 address-shaped `clientIP` shipped from the registry plane emails the team, continuously, without a closable tracker.
5. The at-rest posture #8408 delivered is not regressed by this batch's replace (read on the new boot).
6. The production registry replace this batch triggers happens once, is watched to a deadline, and leaves evidence.

**Cut List (Phase 0.6b and plan review).** Mechanism, property it would buy, what already covers it:

- Probe arm in `zot-log-channel-7440.sh` for clientIP: buys 4; dormant (tracker closed outside the lookback). Covered by the alert.
- Host-side fail-closed `redact()` of clientIP in the shipper: buys 4; erases the signal instead of detecting a topology change and needs bytes the 100 B headroom lacks. Cut (CTO A3).
- New #8408 cloud-init work (alert, sentinel gate, escrow): buys 5; delivered by PR #8456 and tested (`registry-luks-launch-gate.test.sh`, `registry-luks-escrow.test.sh`, `registry-store-not-luks-alert.test.sh`). Cut.
- A real-reboot rehearsal of the launch gate: buys 5; boots `5639cc07` and `acdba704` already show the posture surviving. Cut (CTO C1).
- A third follow-through probe closing #8408 automatically: buys 5/6 evidence already read by the Hand-over query and by the #10119 probe's informational posture lines; it also contradicts ruling C2 (the owner closes) and repeats the shared-source forgery trust that `registry-luks-live-8386.sh` deliberately refuses. Cut (plan review: DHH, simplicity).
- Readiness-loop rider (#7079 item 1): buys nothing in the Property List. Cut (plan review).
- Rate-cap retune (#7456 c): buys nothing demonstrated; zero evidence-lane loss. Cut (CTO B).
- A runtime shape guard for the two heartbeat URLs: buys 3 hardening only; the values are provider-generated, bytes are scarce, and ADR-280 already records the no-host-pin residual. Cut; a static row pins the quoting shape.
- Changing `registry-luks-live-8386.sh` to exit 0 once its target closes: buys the end of the reopen loop; removing the directive from the #8408 body does the same without touching another issue's probe. Cut (CTO C2).
- Repairing the dormant `zot-log-channel-7440.sh`: separate concern, tracked as #10321.

**Measurements run during planning (read-only).** (1) `registry-userdata-budget.sh` on a 4-file scratch copy with the planned edits applied: baseline stored 21,500 B; htpasswd edits alone 21,512; plus both heartbeat curls 21,536; (a readiness-loop edit measured 21,568 and was cut). Whole-line comments are stripped at render and cost nothing; the `- apache2-utils` item's trailing comment under `packages:` is not stripped. (2) Better Stack ClickHouse, 7 days hot plus archive: about 18,780 envelope rows carry `clientIP`, 0 non-RFC1918, 0 on `SOLEUR_ZOT_DISK`; 5 distinct boots in the span, all-private across boot windows. The planned predicate, run as written over that population, returned 0; the positive control (private ranges flagged instead) returned the whole population. A 16-literal classification table (documentation addresses) ran live through the same predicate (below). (3) `apply-web-platform-infra.yml` is 473,632 B against the 490,000 B self-limit (two `-target=` lines cost under 200 B). (4) `plugins/soleur/test/c4-count-parity.test.sh`: 13 passed, 0 failed. (5) Live heartbeat row (latest): `htpasswd_pull_matches=true htpasswd_push_matches=true`, `store_mount_src=/dev/mapper/registry`, boot `889b0dca-76b0-4648-90c2-03de21bf7ab1`, uptime 3.15 days.

**Plan review outcomes (2026-10-14, five-agent panel plus domain leaders).** Applied: readiness rider cut; #8408 probe cut; secrets directive syntax comma-separated; probe exit arms and run-identity rules written; stub census for the rendered-block test; missing consumers of a new Logs alert added (send-failed mutation suite count, `betterstack-log-query.md` row, `infra-validation.yml` paths, `test-all.sh` and `test-affected-paths.sh` registration, orphan-suite census); S6 ceiling row rewritten for zero entries; Production-apply table corrected; Hand-over loop keyed on the merge SHA; P3 premise corrected; ADR-184 note and "detected and paged, not masked" wording added; zot-digest pin row added. Recorded as a User-Challenge (default: the owner's direction stands): landing Part B in its own earlier PR.

**Learnings applied** (from `knowledge-base/project/learnings/`): a cloud-init templatefile must never contain `%{` (write `%%{`) or `${...}` in a comment (`2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`); `x="$(helper)"` under `set -euo pipefail` aborts mute, so the new pipelines are separate statements; a `printf | curl` under pipefail gives 141, so curl keeps process substitution (`2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-...`); a probe that reads Better Stack rows must match the decoded message at offset 0, not a substring (`2026-07-18-betterstack-followthrough-probe-must-field-isolate-...`, `2026-10-01-a-decoded-line-is-not-a-row-...`); a fixture stub must use the real JSONEachRow shape; a probe exiting outside the closed set reopens hand-closed trackers for the 14-day lookback (`logic-errors/2026-10-05-closed-set-exit-5-reopened-trackers-...`); a Better Stack alert guard pins sink, `confirmation_period`, `recovery_period` (`2026-10-01-an-alert-guard-pinned-the-declaration-...`); any edit to `cloud-init-registry.yml` is a host replace, so sibling suites that read its text must be censused (`test-failures/2026-10-06-which-files-feed-user-data-...`).

**Network-connectivity deep-dive (keyword trigger only; the plan addresses no connectivity symptom).** The words "firewall" and "timeout" appear because the CLO trigger names the registry firewall; no SSH path or reachability fault is in scope. Layer by layer, with the artifact: (L3 firewall) `hcloud_firewall.registry` in `zot-registry.tf` declares a name and labels and no inbound rule (grep of the resource block: no `rule` block), so public ingress is deny-all and this plan changes no rule; verified by reading the block, not by a live `hcloud firewall describe` (no host is dialled by this plan and no provisioner is added, `grep -c 'provisioner "' zot-registry.tf` returns 0); (L3 DNS and routing) the tunnel ingress `registry.<base>` to `tcp://10.0.1.30:5000` in `tunnel.tf` and `registry_private_ip = "10.0.1.30"` are unchanged by this plan; (L7 TLS) the only HTTPS edge touched is the two heartbeat curls to Better Stack, certificate verification on; (L7 application) the registry `/v2/` 200/401 contract is unchanged and is read by the liveness beat and the post-merge query. Nothing here needs an egress-IP diff because no operator or CI session connects to the host.

## Problem Statement / Motivation

1. The registry template still passes the zot htpasswd passwords as process arguments in three places (the divergence probe `_htp_verify`, and the pull and push lines of the boot step) and creates `/etc/zot/htpasswd` under the default umask with `chmod 600` after the write, so the bcrypt hashes are 0644 until the chmod. The two heartbeat curls put a Better Stack path secret on argv. Everything else in the argv-bearer sweep is converted; these sites are the last in the registry template (`S6_ALLOW` carries exactly them).
2. The CLO's binding ruling (2026-08-13, referred to the CTO) found that "every observable `clientIP` is RFC1918" is a documented condition with nothing enforcing it; if ingress topology drifts (an inbound firewall rule, a proxy change) a public address becomes Art. 4(1) personal data on rows already in flight, silently.
3. #8408 keeps reopening itself and posting a daily comment although its work is delivered.

## User-Brand Impact

- **If this lands broken, the user experiences:** the registry is the sole image-pull path for every user-serving host. A boot block that aborts under `set -euo pipefail`, or an htpasswd file built over an empty password, leaves the replaced registry host unable to authenticate any pull: a web deploy stalls (a security-fix deploy is the highest-stakes thing the stall can block), and any host that must be recreated mid-window cannot fetch its image, so a user whose workspace host needs a rebuild stays on a degraded or unavailable host until the registry is restored. The running app keeps serving from images already pulled.
- **If this leaks, the user's data and workflow are exposed via:** (a) the registry push credential, whose hash was world-readable (0644) between file creation and `chmod` and whose plaintext sits on a process argument list for the life of each `htpasswd` call; a leaked push credential is a supply-chain exposure of the image every user runs; (b) a non-RFC1918 `clientIP` (a real client address) shipped unredacted to Better Stack source 2457081 if the ingress topology drifts, which converts a log field into personal data with no gate noticing.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user stranded on an unavailable host, or one tampered image, is already a brand-level event for a product that runs the user's code; the registry sits upstream of all hosts, so `aggregate pattern` would undersell the first and `none` is excluded by the sensitive-path rule (`apps/web-platform/infra/`).

`requires_cpo_signoff: true` (CPO sign-off granted at plan time, see Domain Review; `soleur:engineering:review:user-impact-reviewer` runs at review time).

## Proposed Solution

### Part A - #10119 plus the PR B registry scope (`cloud-init-registry.yml`, ONE commit, last)

Content anchors, never line numbers. All edits in the template are byte-measured with `bash apps/web-platform/infra/registry-userdata-budget.sh` before and after.

1. **`_htp_verify`** (the function containing `htpasswd -vb /etc/zot/htpasswd "$1" "$2"`): `printf '%s' "$2" | htpasswd -vi /etc/zot/htpasswd "$1" >/dev/null 2>&1`, then the unchanged `case "$?"` (0 true, 3 false, else unknown). The probe script has `set -u` only (no `set -e`, no `pipefail`), so `$?` after the pipeline is `htpasswd`'s; a static row pins that no `set -e` or `pipefail` precedes `_htp_verify`, and a stub row pins that 127, 6 and 1 still map to `unknown` through the pipe.
2. **Boot step** (inside `doppler run ... -- bash -s <<'ZOTEOF'`, first line `set -euo pipefail`): `install -m 600 /dev/null /etc/zot/htpasswd` replaces the post-hoc `chmod 600`; then two separate pipelines `printf '%s' "$ZOT_PULL_TOKEN" | htpasswd -Bin '${zot_pull_user}' > /etc/zot/htpasswd` and the push line with `>>`. The empty-token guards stay above the pipelines. Each `htpasswd` has its own stdin, so it cannot consume the `bash -s` script text. A failing first `htpasswd` aborts under `set -e` before the `>>` runs. Mode 600 root-owned is the same END state production already has (the file is bind-mounted `:ro` into zot today under `chmod 600`); the new property is that it is never wider, even transiently.
3. **Two heartbeat curls** (ADR-280 inline form, CTO Fork 4 of the PR A plan): in the disk feeder the line `curl -fsS -m 10 "${disk_heartbeat_url}" >/dev/null 2>&1 || PING_RC=$?` becomes `curl --disable --noproxy '*' -g -fsS -m 10 --config - < <(printf 'url = "%s"\n' '${disk_heartbeat_url}') >/dev/null 2>&1 || PING_RC=$?`, and in the liveness feeder `if curl -fsS -m 10 -o /dev/null "${liveness_heartbeat_url}"; then PING=ok; else PING=fail; fi` becomes the same form with `-o /dev/null` kept. Process substitution (not a pipe) keeps curl's own status; both feeders are `#!/usr/bin/env bash`. No runtime shape guard (provider-generated literal, bytes scarce; residual recorded in the ADR-280 addendum). No comment line may contain a `${...}` (templatefile interpolates inside comments).
4. **Comments** (whole-line comments are free): reword the comment block above `_htp_verify() {` that names `htpasswd -vb`; shorten the `- apache2-utils # htpasswd -Bbn ...` item's trailing comment under `packages:` (`# htpasswd (bcrypt), built on-host from Doppler tokens`; it is not stripped from `user_data` and buys bytes); reword `zot-image.provenance.md` where it says "baked with `htpasswd -Bbn`".
5. **Byte discipline (CTO drop order):** the measured result is 21,536 B (headroom 64 B). If the final measurement leaves less than 30 B headroom, drop the liveness then the disk heartbeat conversion (record the ADR-280 gap against the PR A plan if both go); never drop the htpasswd conversions or `install -m 600`. `REGISTRY_GZIP_BUDGET` is never raised. The readiness-loop rider of #7079 is not part of this batch.

Tests and battery (the same commit): `tests/scripts/test-argv-bearer-sweep.sh` stage S6: the three registry entries are DELETED from `S6_ALLOW`, `S6_ALLOW_CEIL` becomes 0 and the "S6 allowlist ceiling" row is rewritten to assert `${#S6_ALLOW[@]} -eq 0` (today it requires the allowlist files to equal the registry file, which is false at zero), the floor row keeps counting 4 converted sites in 2 files, the three "S6 residual site" rows become converted-site rows, a new registry-heartbeat row asserts that `heartbeat_url` appears in the template only inside the `< <(printf 'url = ...)` feed (the two converted sites asserted by identity), and `EXPECTED_TESTS` is re-pinned to the measured green total. `apps/web-platform/infra/htpasswd-stdin.test.sh` gains the rendered-boot-block row: the block text comes ONLY from the offline `templatefile` render `registry-userdata-budget.sh` already produces (out-rendered file), extracted from the rendered `ZOTEOF` heredoc, and executed through `bash -s` inside the digest-pinned `ubuntu:24.04` + `apache2-utils` image. The stub list is derived by a census of the command words in the extracted block, not hand-written: it must at least cover `doppler` (the isolation check reads `doppler secrets --only-names --json`), `jq` (absent from that image; without a stub the isolation check hits FATAL before any `htpasswd` runs), `findmnt`, `docker`, `sleep` (30 iterations), `chattr`, `curl`, `head`, plus the fixture file `/run/soleur/zot-image-id` and the files the block creates under `/etc/zot` and `/var/lib/zot`. Failure arms: a failing first `htpasswd` aborts before the `>>` with no half-written second entry; the mode is observed from file creation (the stat is taken inside the first `htpasswd` stub, under `umask 022`). `registry-boot-guard.test.sh` stays green (the probe-block pins hold: `printf '%s' "$2"` names the function argument) and gains the 127/6/1-through-the-pipe row. The three suites that render the heartbeat feeders from the YAML and stub curl (`zot-liveness-heartbeat.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `zot-image-fetch.test.sh`) are updated so the stub honours `--config -` on stdin, reading the `url = "..."` line with a bounded read (`read -t 1` or `timeout 1`, so a stub that is handed an argv URL cannot block) and still recording the URL. `.claude/hooks/grep-q-pipe-guard.test.sh` `PRODUCER_JOIN` and `PJ_TRIPLES` are re-measured by their derivation if any new row adds a stub or producer.

### Part B - #7530: standing alert `registry_clientip_not_rfc1918` (Terraform, no host bytes)

CTO ruling A2 (decision-challenges.md). In `apps/web-platform/infra/betterstack-logs-alerts.tf`, next to `registry_store_not_luks`: a `locals` SQL, a `logtail_exploration` and a `logtail_exploration_alert`, named `soleur-registry-clientip-not-rfc1918-prd`, on `local.vector_prd_source_id`. It is the fourteenth Terraform-managed Logs alert (13 `logtail_exploration_alert` resources today), so ADR-218 gets an amendment naming its signal class: a stateless per-bucket count over producer-anchored rows, which no existing alert covers.

Predicate, as live-probed (the heredoc local, `{{time}}`/`{{source}}` macros as in the sibling):

```sql
SELECT {{time}} AS time, count(*) AS value
FROM {{source}}
WHERE time BETWEEN {{start_time}} AND {{end_time}}
  AND (startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')
    OR startsWith(raw, '{"message":"SOLEUR_ZOT_DISK '))
  AND arrayExists(n -> (match(n, '^[0-9]{1,3}([.][0-9]{1,3}){3}')
        AND NOT match(n, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])'))
      OR length(n) - length(replaceAll(n, ':', '')) >= 2,
    [replaceRegexpOne(extract(JSONExtractString(raw, 'message'), 'clientIP[:=]"?([^ ,}"]+)'), '^[[]?(::ffff:)?', '')])
GROUP BY time
```

Why it is shaped this way: (a) it grades the FIRST `clientIP` in the decoded message only (`extract` returns the first match), because zot writes its own `clientIP` before `method`, `path` and `headers`, so a later client-controlled copy inside a header or path cannot hide a real address (a decoy with no real field is a safe-direction false alert); (b) both producer shapes are anchored at offset 0 (the envelope also host-scoped; the `SOLEUR_ZOT_DISK` marker is host-agnostic exactly as in the sibling alert), so a journald row quoting the text cannot match. The disk arm grades the whole message including the free-text `zot_last_err=` tail ON PURPOSE: that tail is where zot's own log line, and so its `clientIP`, lands on that channel (ADR-211 left it unmasked for this alert); (c) the one-element array binds the extracted value once so the lambda reads it twice without a `WITH` alias; (d) `[.]`, `[[]` and `[^ ,}"]` avoid backslashes in an HCL heredoc. Live classification table (run through the exact predicate, 2026-10-14; flagged = alerts): `10.0.1.10:54321` 0, `172.16.0.1:1` 0, `172.31.255.255:9` 0, `192.168.1.1:80` 0, `::ffff:10.0.0.5` 0, `default` 0; `198.51.100.7:443` 1, `127.0.0.1:5000` 1, `172.15.0.1:1` 1, `172.32.0.1:9` 1, `192.169.0.1:80` 1, `169.254.169.254:80` 1, `100.64.0.1:80` 1, `[2001:db8::1]:80` 1, `2001:db8::1` 1, `::ffff:198.51.100.7` 1 (RFC 5737 / 3849 documentation addresses, synthetic only).

Alert parameters (CTO: no tolerance, no daily-reopen path; the channel is email-only on the free tier): `alert_type threshold`, comparison `higher_than`, `value 0`, `check_period 300`, `query_period 900`, `confirmation_period 0`, `recovery_period 1800`, `on_missing_data treat_as_zero` (silence is NOT this rule's job: `registry_store_not_luks` and the heartbeats own liveness), `paused = false`, the sibling's `email`/`push`/`call`/`sms`/`critical_alert` settings and `escalation_target`, `incident_cause` under the measured 520-character limit, `metadata.runbook` pointing at the new runbook. Shipped unpaused: the 7-day population is all-private across 5 boots, so it is quiet on arrival. **Sampling caveat** (recorded in the .tf comment and the runbook): the shipper rate-caps ordinary rows to 17 per tick, so detection is sampled over SHIPPED rows only; a topology change would produce many public rows, so this is adequate, and rows the shipper drops never reach Better Stack (they remain in the host-local journald log under its size bound, so they are not the Better Stack concern, not "no concern"). **Residual risks recorded with the alert (CLO review):** detection, not prevention (latency up to about 20 minutes: 300 s check, 900 s window, plus ingest), so the legal records say "monitored and alerted by email", never "guaranteed"; a low-rate public prober inside the high-volume private stream can be sampled out for some time; a public address landing in a top-level field other than `clientIP` is not covered; the grade depends on zot writing `clientIP` before `method`, `path` and `headers` and on the field name, and `treat_as_zero` makes a renamed or reordered field read as healthy forever, so the alert suite pins the zot image digest the field order was verified against (a bump of `zot_image_amd64` in `zot-registry.tf` fails the suite until someone re-runs the live population check and updates the pin). **Boot false-positive check** (CTO risk): the first post-replace window is validated by the #7530 probe before it can PASS; the measured boots show no loopback or docker-NAT value (a localhost readiness probe, if it ever surfaced as `127.0.0.1`, alerts by design and the predicate is then narrowed with evidence, not guessed).

Files: `apply-web-platform-infra.yml` gains `-target=logtail_exploration.registry_clientip_not_rfc1918` and `-target=logtail_exploration_alert.registry_clientip_not_rfc1918` beside the sibling's (an untargeted resource is never applied, #5566); a new suite `apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh` modelled on `registry-store-not-luks-alert.test.sh` (mutations run on COPIES in a temp dir through `REGCIP_TF`/`REGCIP_WF` overrides) and registered in `.github/workflows/infra-validation.yml` (the step AND any `paths:` entry the suite's reads need); `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` counts `values = [local.vector_prd_source_id]` with `assert s.count(old) == 13` and goes 13 to 14; `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` gains the row under "Standing alarms over this source"; a new runbook `knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md`. The runbook MUST say (CLO review): the alert is the observable signature of re-evaluation trigger 2, meaning `clientIP` may have become Art. 4(1) data on rows already in flight; fix the cause first (`hcloud_firewall.registry` inbound rules, then `tunnel.tf` forwarding); record the exposure window and the affected row count, counts only; source 2457081 retains rows 90 days plus archive (register #7772), and selective redaction or deletion of affected rows is a CLO decision (verify what Better Stack supports, do not assume selective delete); the alert is not automatically an Art. 33 breach, but if any non-estate address made an authenticated pull, route to `recommended-tools.md#breach-notice-triage` (72 h clock); the CLO agent classifies and the optional veto in the 2026-08 record stands; external counsel is engaged if public ingress is sustained with identifiable clients or there was any authenticated non-estate access; never paste an address into an issue, PR or comment (the "read the rows" step says so); after a zot version bump, re-run the live population check; quoted text names the sampling limit and the Better Stack DPA PENDING status.

The alert resources are applied by the merge's push apply; the file is NOT an input of `registry-host-replace-dispatch.yml` (its watched paths are `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`), so Part B causes no replace by itself. Commit it separately, before the registry commit. Considered and not taken (User-Challenge, default is the owner's one-PR direction): landing Part B in its own earlier PR so it is applied and live-validated on the old host before the replace; it stays batched, and commit 1 is the peel point if the owner prefers the split.

### Part C - #8408 close-out (no template change, no probe)

1. At work time (not merge time): remove the `<!-- soleur:followthrough script=scripts/followthroughs/registry-luks-live-8386.sh ... -->` directive and the `follow-through` label from the #8408 body in ONE `gh issue edit`, which ends the daily sweeper comments and the reopen loop at its source (CTO C2). `registry-luks-live-8386.sh` is not changed (it belongs to #8386, closed).
2. After the merge the owner closes #8408 with the owner's 2026-09-28 evidence table plus the new boot's posture lines (printed informationally by the #10119 probe and by the Hand-over query). The step is tracked by the issue itself staying open; nothing else is left for it.

### Part D - #7456(c) and #7521

No retune. Comment the CTO ruling (the 23,570/day measurement, zero `exempt_cap`, and the future evidence bar: `exempt_cap` > 0 in a 24 h single-boot window, or an incident where a `rate_cap`-dropped row was the missing diagnostic, or a changed offered volume that makes the ordinary lane drop non-routine classes, always stating Better Stack volume headroom) on #7521 and #7456; both stay open under `Ref`.

### Part E - post-merge evidence as two probes

Two pure verdict-emitter probes under `scripts/followthroughs/`, each with a `.test.sh` that stubs `gh` and the Better Stack read (real JSONEachRow shape), each header stating its credential posture, exit contract (0 PASS; 1 FAIL only for a MEASURED contradiction; 2 NOT YET; 3 CANNOT ESTABLISH; any unreadable window, missing baseline or equal boot id is 3 and never 1, because exit 1 on a closed tracker reopens it for the 14-day lookback), refusal to run under xtrace with a credential set (exit 78), a `RETIREMENT:` line, and never a write (no `gh issue close`, no comment; safe under the sweeper's `dry_run`). Reads match the DECODED message at offset 0 (the `zot_envelope_anchor` form), output is counts only (the clientIP probe must never echo an address, because the sweeper posts output verbatim into a public issue), and each is registered in `scripts/lint-betterstack-emitter-read.sh`'s allowlist (and its suite) with the mechanism that makes it honest. Directives use the sweeper's comma syntax: `secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD` (the sweeper splits on commas; a space-separated list forwards only the first name).

- `registry-htpasswd-stdin-10119.sh` (tracker #10119, the design the owner was told about in #10301: the issue closes from a follow-through check after the read-only verdict). Exit 2 until PR #10320 is merged (`gh pr view 10320 --json state,mergeCommit`) and a qualifying dispatcher run exists. The **qualifying run** is the first `registry-host-replace-dispatch.yml` run with conclusion `success` whose `headSha` equals the merge SHA or descends from it (`git merge-base --is-ancestor`; the sweeper checkout is full-history) and whose `Dispatch registry-host-replace` and `Poll the dispatched apply to a conclusion` steps are both `success` in the run's jobs JSON (a `deliver=false` run skips them; an `unverified` poll is exit 3). **Template identity:** `git show <headSha>:apps/web-platform/infra/cloud-init-registry.yml` must hold no argv-form `htpasswd` (the S6 census regex), otherwise exit 3, so a later revert's replace cannot close the tracker. **Fresh boot:** the baseline is the `boot_id` of the newest `SOLEUR_ZOT_DISK` row older than the run's creation (unreadable: exit 3); a row newer than the run's completion with a different `boot_id` must read `htpasswd_pull_matches=true htpasswd_push_matches=true` and a non-unknown `zot_image_digest` for PASS; `htpasswd_*_matches=false` on the new boot is exit 1 (counts only); no new-boot row within 90 minutes of the run's completion is exit 3 (before that, 2). The old host emits the same `true true` row every 5 minutes today, so a fresh-row check alone would close the tracker on pre-replace data. On PASS it also prints informational posture lines for the owner's #8408 close (`store_luks=yes`, `store_mount_src=/dev/mapper/registry`, devid equality as a boolean, `store_escrow` token; the alias and backing device are withheld, as `registry-luks-live-8386.sh` does).
- `registry-clientip-alert-7530.sh` (tracker #7530). Exit 2 until the PR is merged, a push-apply run (`apply-web-platform-infra.yml`, event `push`) for the merge SHA or a descendant concluded `success`, and at least 30 minutes of rows from the newest post-merge boot exist (the apply may be displaced by the workflow's single pending slot: a run for a descendant SHA that succeeds also counts; a failed apply is exit 3 naming the re-fire, never an endless 2). Then: extract the alert SQL from `betterstack-logs-alerts.tf` (the precedent is `luks-monitor-host-timer-8706.sh`; an absent local is exit 2 before the merge reaches main, exit 3 after), run (a) the 16-literal classification table through the extracted predicate (engine semantics, synthetic literals only), (b) the predicate as written over the post-boot window (must be 0 with a positive population), (c) the private-flagged control (must be above 0). PASS iff all three hold; exit 1 (counts only) if (b) is above 0; exit 3 if the population is empty.

Enrollment: the tracker issues carry the directive (`gh issue edit`, unfenced at column 0, `earliest=` the filing time because the merge time is unknown). Before the merge the sweeper finds no script on main and logs `missing in repo HEAD — leaving issue open` to stderr and returns (no tracker comment, no red run: `fail` only prints); the cost is a daily log line until the merge. Before the PR is marked ready, dry-run the real sweeper on the branch (`gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-registry-phase2-batch-10119-8408-7530 -f dry_run=true`) and read each tracker's `exit=` line; copy each probe to the main checkout first (the `gh issue edit` hook resolves `script=` there). The `follow-through` label is added to #10119 and #7530; #8408 loses it (Part C). The probe suites are registered in `scripts/test-all.sh` (`run_suite` lines) and `scripts/lib/test-affected-paths.sh` (siblings are listed by hand there; the orphan census `bash scripts/lint-orphan-test-suites.sh` proves it).

## Hand-over (the PR stops here; nothing below is run by the pipeline)

Per #10301 the pipeline never merges or closes a registry PR. The PR body's FIRST line reads: "Merging this PR replaces the production registry host unattended (registry-host-replace-dispatch.yml push trigger); merge only when the replace can be watched." The PR body then carries the `Ref` lines only (`Ref #10119`, `Ref #8408`, `Ref #7530`, `Ref #7456`, `Ref #7521`, `Ref #7079`, `Ref #10093`, `Ref #10205`; never a closing keyword in body or title), the production-apply table below, the pre-merge `registry-delivery-change.sh` preview, the measured byte table, and this section. The Operator Holds section keeps `soleur:ship` from arming auto-merge.

**Pre-merge checks (all must hold, run immediately before the merge):**

```bash
# 1. nothing in flight in the apply concurrency group or the registry writers (status != completed also catches a
#    pending/waiting run holding the group's single pending slot, which --status in_progress|queued does not):
for w in apply-web-platform-infra registry-host-replace-dispatch web-platform-release build-inngest-config-bundle build-inngest-bootstrap-image apply-deploy-pipeline-fix inngest-provision-rehearsal; do
  echo "== $w"; gh run list --workflow "$w.yml" --limit 30 --json databaseId,status,headSha,createdAt --jq '[.[]|select(.status!="completed")]'
done
# 2. the dispatcher's last success is the delivery watermark:
gh run list --workflow registry-host-replace-dispatch.yml --limit 5 --json databaseId,status,conclusion,headSha,createdAt
# 3. no other open PR about to merge into the infra path (this PR excluded):
gh pr list --state open --limit 200 --json number,title,isDraft,autoMergeRequest,files --jq '[.[]|select(.number!=10320)|select([.files[].path|select(startswith("apps/web-platform/infra/") or .==".github/workflows/apply-web-platform-infra.yml" or .==".github/workflows/registry-host-replace-dispatch.yml")]|length>0)|{number,title,isDraft,auto:(.autoMergeRequest!=null)}]'
gh pr checks 10320
gh pr view 10320 --json isDraft,mergeable,mergeStateStatus
```

Expect `[]` after every `== <workflow>` line, the newest dispatcher run `completed`, every check green, `isDraft false`. The third command's output is a DECISION list, not a pass/fail: `gh pr list --json files` is capped per PR (a large PR with infra files late in its list could be missed), and it always omits this PR. As of 2026-10-15 it listed two live conflicts the owner decides BEFORE the merge: **#10322** (non-draft, `fix(infra): registry template htpasswd and heartbeat URLs off argv (Ref #10119)`, a second PR from another session carrying the same #10119 template change; merging either one fires the registry replace, and the second to merge would fire a second replace of an already-converted template, so close or rebase one onto the other first) and **#10330** (a pin bump with auto-merge ARMED; an infra-path merge evicts a pending replace apply from the workflow's single pending slot, so let it land and finish, or disarm it, before this merge). The list changes by the hour (it also showed #7390, a non-draft WIP touching `apply-web-platform-infra.yml`, on 2026-10-15): decide every non-draft entry, and treat drafts and parked PRs (#10294, #10081, #9051) as not merge candidates. **CI is red on this PR for a reason that is not this PR's:** `cloud-init-inngest-bootstrap.test.sh` fails because main's inngest pin (v1.1.53) is behind the latest tag (v1.1.54); #10330 (auto-merge armed) fixes it. After #10330 lands, update this branch (`gh pr update-branch 10320`, or rebase onto origin/main) and re-read `gh pr checks 10320` before the merge; do not merge red. Record the current `boot_id` (the newest `SOLEUR_ZOT_DISK` row, `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 20m --grep SOLEUR_ZOT_DISK --limit 3`, newest row LAST; READ it at the time: it was `889b0dca-76b0-4648-90c2-03de21bf7ab1` on 2026-10-13 and `23bf40dd-3b3b-4a19-ae7d-8dc6594517de` on 2026-10-15 (first row 08:10 UTC, after a later boot that is not this PR's), so any literal here is stale by the merge). **Prepare the recovery now (do not open it for merge):** a template defect is recovered by a PARTIAL revert PR, not by a re-dispatch and not by `git revert` of the merge commit (which would orphan the alert). The partial revert is the template PLUS the files that pin its converted form, restored from the merge commit's first parent; the template alone cannot merge green because the registered suites pin the converted form (verified red with only the template reverted: `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `zot-liveness-heartbeat.test.sh`, `zot-image-fetch.test.sh` and the S6 stage of `tests/scripts/test-argv-bearer-sweep.sh`; with the nine files below restored together, every suite above and both probe suites were green in a scratch worktree on 2026-10-15):

Write this to a script now (it cannot run before the merge: `${MERGE_SHA}^` does not exist until then) and run it with `bash` straight after a first-boot failure, with `MERGE_SHA` set from `gh pr view 10320 --json mergeCommit --jq .mergeCommit.oid`:

```bash
#!/usr/bin/env bash
# recover-registry-template.sh - partial revert of PR 10320 (template + the files that pin it). Run only AFTER the merge.
set -euo pipefail
: "${MERGE_SHA:?set MERGE_SHA to the merge commit of PR 10320}"
FILES="apps/web-platform/infra/cloud-init-registry.yml apps/web-platform/infra/htpasswd-stdin.test.sh apps/web-platform/infra/registry-boot-guard.test.sh apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh apps/web-platform/infra/zot-liveness-heartbeat.test.sh apps/web-platform/infra/zot-image-fetch.test.sh apps/web-platform/infra/zot-image.provenance.md tests/scripts/test-argv-bearer-sweep.sh .claude/hooks/grep-q-pipe-guard.test.sh"
git fetch origin main
git worktree add -b revert-registry-template ../revert-registry-template origin/main
cd ../revert-registry-template
# shellcheck disable=SC2086 # FILES is a deliberate word list
git restore --source="${MERGE_SHA}^" -- $FILES
git add -- $FILES
git commit -m "fix(infra): restore the pre-#10119 registry template and the files that pin it (partial revert of PR 10320)"
git push -u origin revert-registry-template
gh pr create --title "fix(infra): restore the pre-#10119 registry template (partial revert of PR 10320)" --body "Partial revert after a failed first boot. Replaces the production registry host unattended on merge: see the Hand-over of the plan."
```


**Recommended merge window (CTO ruling H):** no queued security-fix deploy, no planned host recreation, someone available for about 90 minutes, main otherwise green, and no `registry-host-replace` already running. Do not merge when a security-fix deploy is queued.

**Merge:** `gh pr merge 10320 --squash` after explicit go-ahead (the registry host replace is a production-mutating authorization an agent cannot discharge, `hr-menu-option-ack-not-prod-write-auth`).

**Post-merge watch (Monitor an until-loop, never a background poll; deadline 4,800 s, the dispatcher job ceiling is 75 minutes). Every read is keyed on the merge SHA, because the newest run before the merge's own run exists is the previous one. Save the block as a script and run it with `bash` (its `exit` lines would end an interactive shell):**

```bash
MERGE_SHA="$(gh pr view 10320 --json mergeCommit --jq .mergeCommit.oid)"; [ -n "$MERGE_SHA" ] || { echo "no merge SHA: not merged yet"; exit 1; }
SECONDS=0
until [ "$(gh run list --workflow registry-host-replace-dispatch.yml --commit "$MERGE_SHA" --limit 1 --json status --jq '.[0].status // "none"')" = completed ] || [ "$SECONDS" -ge 4800 ]; do sleep 60; done
[ "$SECONDS" -lt 4800 ] || { echo "DEADLINE: dispatcher run not completed in 4800s; read it before any re-fire"; exit 1; }
gh run list --workflow registry-host-replace-dispatch.yml --commit "$MERGE_SHA" --limit 3 --json databaseId,conclusion,headSha,createdAt
# a conclusion of success alone does NOT prove a replace (a deliver=false run is success with both steps skipped): read the steps
RID="$(gh run list --workflow registry-host-replace-dispatch.yml --commit "$MERGE_SHA" --limit 1 --json databaseId --jq '.[0].databaseId')"; gh run view "$RID" --json jobs --jq '[.jobs[].steps[]|select(.name|test("^(Dispatch registry-host-replace|Poll the dispatched apply to a conclusion)"))|{name,conclusion}]'   # both must be success
gh run list --workflow apply-web-platform-infra.yml --commit "$MERGE_SHA" --limit 6 --json databaseId,conclusion,headSha,event,createdAt   # the PUSH apply for the merge SHA
gh run list --workflow apply-web-platform-infra.yml --limit 6 --json databaseId,conclusion,headSha,event,createdAt   # the follow-on workflow_dispatch apply (read it after the dispatcher started)
```

Success is: the dispatcher run for the merge SHA `conclusion success` with its Dispatch and Poll steps `success`; the follow-on apply (`event workflow_dispatch`, created after the dispatcher started) `success`; the PUSH apply for the merge SHA `success` (it creates the alert pair; if Better Stack refuses the fourteenth alert that refusal is the free-tier count-cap measurement and the #7530 probe stays at exit 3 until it is resolved); and **no** verdict comment on the PR (a comment of any kind is the failure signal; the `gh api --paginate --slurp` filter under "Reading a verdict" in `registry-host-replace-dispatch.md`, run with `N=10320`, returns "no verdict"). On `kind=unverified` the poll window closed while the replace may still be running: READ the replace run first and do not re-fire (double-replace hazard); `apply-failed`, `dispatch-failed` and `cancelled` are read the same way. A `kind=refused` is resolved per `registry-host-replace-dispatch.md` and re-fired with `gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=10320`. Then read Better Stack (no SSH): `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK --limit 20` decoded through `jq -r '.raw|fromjson?|.message // empty|select(startswith("SOLEUR_ZOT_DISK "))'` (the query script returns the newest rows in ASCENDING order, so the newest row is the last line): a `boot_id` different from the recorded one, `htpasswd_pull_matches=true htpasswd_push_matches=true`, `store_luks=yes`, `store_mount_src=/dev/mapper/registry`, `store_escrow=pending` (first 2 hours) then `ok`, `state_status=running`, a non-unknown `zot_image_digest`. Also `ping_rc=0` on that row and a green liveness heartbeat, which evidence the two converted heartbeat curls (an OWNER read: the #10119 probe grades the htpasswd fields only, so its PASS alone does not evidence the heartbeat conversion); re-run the read until the `boot_id` changes (up to 90 minutes, the window the #10119 probe uses), because right after the dispatcher completes the old `boot_id` can legitimately still be the newest. The two probes then close #10119 and #7530 by themselves on the daily sweeper (cron `0 18 * * *` UTC); to expedite once the evidence above is in, `gh workflow run scheduled-followthrough-sweeper.yml`, wait for that run to complete (about 7 to 14 minutes: `gh run list --workflow scheduled-followthrough-sweeper.yml --limit 1 --json databaseId,status`), then read `gh issue view 10119 --json state` and `gh issue view 7530 --json state` and the sweeper's comment on each (`gh issue view <n> --comments`). The sweeper dry-run recorded on this branch (run 38639257047) exercised only the probes' first gate (`n_pr_unmerged`, exit 2); the Better Stack reads and the credential forwarding under the real launcher first run after the merge, so read the sweeper's comment on each tracker rather than assuming it closed. The #7530 PASS comment points at the legal re-dating the runbook assigns to whoever reads it. The owner closes #8408 with `gh issue close 8408 --reason completed --comment "<the 2026-09-28 evidence table (the owner's comment on #8408 dated 2026-09-28; copy it from there) plus the new boot's posture lines>"`.

**Merge-fired web release.** The merge also fires `web-platform-release.yml`; the replace preflight (P3) waits up to 2,100 s for that co-fired release to finish and starts the replace after it, so the co-fired release is not expected to overlap the replace. That wait is bounded: `scripts/registry-replace-preflight.sh` records that about 18% of releases exceed the 2,100 s wait, so roughly one merge in five ends in a P3 refusal after ~35 minutes (`kind=refused`, re-fire per the runbook); plan for it rather than treating it as exceptional. A LATER release triggered by a different merge during the replace and boot (about 2 minutes plus boot) can fail on the image mirror pull; nothing user-visible breaks (the running app already holds its images). Rerun it with `gh run rerun <id> --failed` only after the liveness heartbeat is green; if the replace itself failed, hold the rerun until the revert replace is green.

**Credential rotation.** Not required (CTO ruling G): the exposure was a millisecond argv window and a briefly 0644 bcrypt hash on a single-purpose host with a deny-all-public firewall where only root and the zot container run; a bcrypt hash is not a usable credential. The two heartbeat URLs also sat on argv for up to 10 s per beat (the liveness feeder every 60 s); they are Better Stack ping URLs that remain readable on the host and in `user_data` after this change (ADR-280 addendum residual), so the same conclusion holds for the argv window; the standing exposure is the ADR-280 named residual (any local reader of the host, and anything that can reach the hcloud metadata API, can read the URLs and forge a beat, which suppresses the absence alarm on the sole pull path), accepted until the URLs move out of `user_data`. The same `user_data` also carries the registry Doppler service token (rendered to `/etc/default/registry-doppler`), so a metadata-API reader's reach is wider than a forged beat; this change does not alter that pre-existing exposure. Rotate opportunistically at the next replace that happens for another reason.

**Failed first boot (CTO ruling H).** Open the staged recovery PR at once: a re-dispatch re-renders the same template, so use it only when the failure looks transient (a Hetzner or network error). The store volume is preserved. Pause deploys, and merge nothing else that touches the registry or triggers a release, until the liveness heartbeat is green. Recover with the PARTIAL revert staged under the pre-merge checks (the template plus the files that pin its converted form; a template-only revert cannot merge green, and a whole-commit revert would also drop the probes and the legal records and orphan the alert, because removing the alert resource and its `-target=` lines from a TARGETED apply leaves it live in state). Three things differ from a normal merge:

1. **Which arm delivers.** The dispatcher's push arm decides whether to deliver by comparing the rendered bytes with its watermark, the head of the last SUCCESSFUL dispatcher run. If the first run ended `apply-failed`, `cancelled` or `dispatch-failed`, the watermark did not advance, so a revert that restores the pre-merge template renders byte-identical to it: its push run is a green `deliver=false` no-op with no verdict comment, which the success check above reads as healthy. After a non-success first run recover with the MANUAL arm (`gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=10320`), which always delivers.
2. **Preflight refusals.** The push arm is not `--manual`, so preflight P1 (local-cache pulls, the very predicate a registry unavailability trips) can REFUSE it, and `--manual` skips P1 only: P5 (dark container-log channel) and P6 (zot boot-image asset check) still run. P5's window is 24 hours: a recovery that outlasts it with zot dark is refused by the dispatcher, and the exit is `registry-host-replace-dispatch.md` item 4 (`--check-asset`, then `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='<why>'`). If a run is refused, read the verdict comment first.
3. **The co-fired web release.** The recovery PR touches `apps/web-platform/**`, so it also fires `web-platform-release.yml`, a P3 registry writer, while the registry is down. P3 does not skip under `--manual`. Read that release; if it hangs against the dead registry, cancel it before re-firing, or P3 will wait up to 2,100 s and then refuse.

4. **Hold the #10119 tracker.** The #10119 probe grades the template only at the SHA of the FIRST qualifying run, so after the partial revert merges, a reverted host reporting `true/true` could still let it close #10119 while the argv form is live again. When the revert PR merges, remove the `follow-through` label (or the directive line) from #10119 and comment why; restore it only with the re-converted template.

The recovery is therefore a second replace that can itself wait on a manual re-fire: the 75-minute dispatcher ceiling bounds one run, not the whole recovery.

**First-window alert note.** If `registry_clientip_not_rfc1918` emails in the first window after the replace, read the rows before acknowledging: a `127.0.0.1` value from a boot-time readiness probe is a predicate fix with evidence (not an ignore), any other address is the real condition and follows the runbook.

**Abort path.** Until the replace lands `hcloud_server.registry` shows `user_data` drift (the drift alerter may open an issue; expected). A preflight refusal is a named predicate, not a failure of the change. The store volume is preserved (`store_destroyed==0`); a re-dispatch recovers a transient failure, a revert PR (itself another replace) recovers a template defect.

## Production-apply coupling

Path filters read from the workflows (`apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**`, its own file and one jq file; `infra-validation.yml` and `apps/web-platform/test/infra/**` do not fire it). Every file under `apps/web-platform/**` also fires `web-platform-release.yml` (a routine production app release and container deploy); every file under `plugins/soleur/**` fires `version-bump-and-release.yml`.

| File in this PR | Workflow(s) it fires on merge | What the firing does to a live system |
|---|---|---|
| `apps/web-platform/infra/cloud-init-registry.yml` (+ `zot-image.provenance.md`) | `registry-host-replace-dispatch.yml` (PUSH trigger on this exact file; no reviewer gate, no confirm token), the push apply (no Terraform diff in its `-target` sets for user_data), `web-platform-release.yml` | the dispatcher renders `user_data` at the delivery watermark and at head and, on a byte change, runs `registry-host-replace` after a read-only preflight (P3 waits up to 2,100 s for the co-fired release): **the sole image-pull path is replaced unattended**; the converted boot block executes for the first time on the new host. Volume preserved. It also delivers EVERYTHING since the watermark (any earlier undelivered `zot-registry.tf`/`variables.tf` delta ships in the same replace). |
| `apps/web-platform/infra/betterstack-logs-alerts.tf`, `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines) | push apply (the .tf is under `infra/**`; the workflow file is its own trigger), `web-platform-release.yml` (the .tf) | creates the exploration and the alert in Better Stack through the logtail provider; no host effect. Serialized with the registry replace by the workflow-level `terraform-apply-web-platform-host` concurrency group (one running, one pending slot, no cancel-in-progress): a newer arrival can evict a pending run. |
| `apps/web-platform/infra/*.test.sh` (htpasswd-stdin, registry-boot-guard, the three heartbeat suites) | push apply (infra path; no Terraform diff), `web-platform-release.yml` | test-only: a no-op plan, a routine release. |
| `apps/web-platform/test/infra/**`, `.github/workflows/infra-validation.yml` | `web-platform-release.yml` (for `apps/web-platform/**`) only; not the apply workflow | a routine release; CI registration. |
| `plugins/soleur/test/preflight-discoverability-test.test.ts` | `version-bump-and-release.yml` (any file under `plugins/soleur/**`) | a plugin version release; `web-platform-release.yml` is NOT fired by a `plugins/soleur/test/**` edit alone. |
| `scripts/followthroughs/**`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lint-betterstack-emitter-read.sh`, `tests/scripts/**`, `.claude/hooks/*.test.sh` | none of the apply, mint or release workflows | not apply paths. |
| `knowledge-base/**` (ADR amendments, runbooks, legal pointer, plan, tasks) | none | docs. |

**Net live effect of the merge:** one automatic registry host replace (the only non-routine firing), one Better Stack alert pair created, one routine web release (container restart), one plugin version release, otherwise no-op applies. Squash-merge removes per-commit revert points after the merge: the commit order below is a set of pre-merge peel points, and a post-merge revert is a new PR whose own merge re-fires another replace (deliveries are idempotent).

## Operator Holds

(Consumed by ship Phase 6 at the draft exit; a hold that cannot be evaluated STANDS.)

- **Registry PR hold:** do not arm auto-merge and do not merge until the owner gives an explicit go-ahead for the production registry host replace. The PR stays ready (green) with no auto-merge armed; the pipeline's "run the merge" step does not apply to it.
- The alert commit (Part B) is separable pre-merge but ships in the same squash; declining the replace means peeling the single registry commit before the merge, and splitting Part B out is the owner's call (recorded User-Challenge).

## Downtime & Cutover

The replace of `hcloud_server.registry` is the existing, tested path (`registry-host-replace`); it keeps the store volume (`store_destroyed==0`) and the host is cloud-init-only with a ForceNew `user_data`. Expected unavailability of the registry during the replace: the apply step itself measured about 2 minutes in the last delivery of this kind (run 35489418603: 04:33:32Z to 04:35:17Z) plus boot to a green heartbeat (the first heartbeat landed within about 20 s of boot); the dispatcher may first wait up to 35 minutes for the co-fired release. The preflight refuses when the fleet is already serving off its last tier (the #6400 hazard), so a degraded fallback blocks the replace instead of compounding it. Consumers pull at deploy time; a deploy that overlaps the window retries or waits; the running app is unaffected. The residual disruption (a pull in the window fails) is accepted and bounded by the pre-merge checks (no web release in flight or queued). No second replace is scheduled: this is the one freeze.

**Zero-downtime path evaluated (deepen gate 4.55).** A blue-green replace (bring up a second registry host, cut consumers over, retire the old one) needs a second registry host and consumer failover, which is the HA work tracked as #6126 and explicitly outside this epic's arc; the in-place alternative (editing the running host) is not a path for a cloud-init-only, ForceNew `user_data` host. The residual unavailability is therefore accepted, with the justification above, a bounded window (about 2 minutes of apply plus boot, preceded by at most 35 minutes of preflight waiting during which the old host still serves), and the owner's explicit go-ahead at merge time as the sign-off (Operator Holds).

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf`: one `locals` entry, one `logtail_exploration`, one `logtail_exploration_alert` (provider `logtail`, already pinned; no new provider, variable, or secret). `apps/web-platform/infra/cloud-init-registry.yml`: template text only (no `.tf` edit; `zot-registry.tf` is untouched, so no render input moves). No new Doppler secret; the sweeper's existing `BETTERSTACK_QUERY_*` env covers the probes.

### Apply path

(a)/(b) hybrid by existing resource: the registry template reaches a host only through `registry-host-replace-dispatch.yml` (cloud-init-only, ForceNew `user_data`, volume preserved; the default `terraform apply -replace` path for a running host with state on a persistent volume), and the alert pair through the existing push apply `-target` list. Expected downtime: the registry replace window above; none for the alert.

### Host fan-out

No `terraform_data` SSH provisioner is added or edited, so the fleet-sibling classification in `plan-host-fanout.md` is unchanged; `web-host-provisioner-parity.test.sh` stays green and is run as a ratchet.

### Distinctness / drift safeguards

`dev != prd`: the alert is on the prd source only (`local.vector_prd_source_id`), like its siblings. `registry-userdata-budget.sh` and `cloud-init-user-data-size.test.ts` are the byte drift gate; the ADR-218 reconciler reports a live pause on the new alert as drift. State-storage: no new secret lands in state.

### Vendor-tier reality check

Better Stack's free tier has an undocumented Logs-alert count cap (ADR-218 records it); the alert is the fourteenth. If the apply is refused on count, that refusal is the measurement and lands in the ADR-218 amendment; the registry replace is a separate dispatched run and is not blocked by a failed push apply. `var.betterstack_paid_tier` already controls `escalation_target` as in the sibling.

## Encryption Posture

```yaml
at_rest:
  - store: /etc/zot/htpasswd (registry host root disk, ext4, not the LUKS store volume)
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/cloud-init-registry.yml:install -m 600 /dev/null /etc/zot/htpasswd
    defends_against: a local non-root user or a world-readable window reading the bcrypt hashes of the push and pull credentials (mode 600 from file creation, never 0644)
    does_not_defend: a raw snapshot of the root disk, root on the host, or the plaintext tokens still held in the Doppler isolated config and in the boot-time process environment; the hashes are bcrypt, not secret-keeping
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no off-box read of a file mode exists; the mode is asserted offline by the rendered-boot-block row in htpasswd-stdin.test.sh
  - store: hcloud_volume.registry (the zot store, LUKS)
    mechanism: luks
    evidence: scripts/encryption-posture-ledger.json row hcloud_volume.registry (unchanged by this plan; read on the new boot by the Hand-over query)
    defends_against: a seized or snapshotted raw volume
    does_not_defend: a running host with the mapper open, a leaked Doppler key, or the reboot window (measured, not prevented, by the sentinel gate)
    disclosed_as: knowledge-base/legal/article-30-register.md PA-8
    live_verification: available
in_transit:
  - connection: registry host -> Better Stack heartbeat endpoint (the two converted curls)
    enforced_at: apps/web-platform/infra/cloud-init-registry.yml:zot-disk-heartbeat.sh and zot-liveness-heartbeat.sh curl
    tls: https, curl default minimum
    cert_verification: on
    does_not_defend: a compromised Better Stack account or a writer to the Terraform-generated URL redirecting a beat to another https host (the recorded no-host-pin residual of ADR-280)
    disclosed_as: not-publicly-claimed
exception:
  justification: the htpasswd file holds bcrypt hashes only and its mode is 600 from creation; the registry host root disk is not LUKS (a separate exception tracked for the root filesystem as #7456 item a)
  tracking_issue: "#7456"
  reevaluate_when: the registry root disk is moved under LUKS, or a plaintext credential is ever written to the root disk
  expires_on: 2027-01-12
```

## Architecture Decision (ADR/C4)

### ADR

No new architectural decision. Four existing ADRs get dated, append-only amendments as in-scope tasks of THIS plan (not follow-up issues): `ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (amendment 2026-10-14, #7530: the fourteenth Logs alert; signal class = stateless per-bucket count over producer-anchored rows, which no existing alert covers; the sampling and field-order caveats; why an alert and not a follow-through probe: a probe's tracker closes on PASS and drops out of the sweeper's 14-day lookback; the #10321 pointer); `ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md` (the prose sentence "It does **not** mask `clientIP`... owned by #7530" gains "discharged 2026-10-14 by the standing alert: clientIP is DETECTED and ALERTED, not masked"); `ADR-184-registry-host-container-log-shipper.md` (a short note that the shipper's rate-cap sampling and zot's `clientIP` field order are now a consumed contract of the alert); `ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (addendum 2026-10-14: the registry template is converted, the S6 allowlist is at zero, the two heartbeat curls use the inline form with the no-runtime-guard residual). The CLO record `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` gets an appended pointer on frontmatter trigger 2 and `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md` ("Not attesting to `clientIP`") is cross-referenced in the CLO routing; neither changes its conclusion.

### C4 views

No C4 change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`) for the external human actors (the founder paged by `betterstack -> founder`; the public issue reader; no new human), external systems (Better Stack, Doppler, GitHub, Cloudflare tunnel, the zot registry system: all already modelled; the alert is an object inside Better Stack, not a new system), data stores (the zot LUKS store, unchanged), and access relationships (`zotRegistry -> betterstack` shipping edge, `betterstack -> founder`, `hetzner -> zotRegistry` pulls: unchanged; no new edge, no element description falsified: `model.c4` already says the posture alert and sentinel are delivered). `bash plugins/soleur/test/c4-count-parity.test.sh` is green at baseline (13 passed) and is re-run at the end.

### Sequencing

All amendments describe the target state in this PR; nothing is postponed.

## Guard Contract

### Guard 1 - No registry-template htpasswd invocation or heartbeat URL carries a secret on argv, and the file is never wider than 600

**Property.** No tracked non-test, non-comment `htpasswd` invocation passes a password as an argument (no `b` in any option cluster), no `curl` in `cloud-init-registry.yml` holds a `*_heartbeat_url` interpolation on its argument list, and `/etc/zot/htpasswd` is created with mode 600 before its first write.

**Assembly.** The S6 census in `tests/scripts/test-argv-bearer-sweep.sh` (`git ls-files` plus grep over `apps`, `scripts`, `.github`; YAML `run:` bodies and cloud-init heredocs included; whole-line comments and trailing YAML `# ...` excluded) with the site floor at 4 sites in 2 files asserted BY IDENTITY (one anchored row per site), the registry-heartbeat row over the one YAML, and the rendered-block execution in `htpasswd-stdin.test.sh`; all three must agree. `S6_ALLOW` is deleted to zero (the allowlist shrinks by deletion only). The existing S6 mutation rows (fifth-site / sixth-site, renamed-binary floor) stay and keep guarding the census itself. Not covered, named in the row comment: an invocation through a variable or `eval`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `htpasswd -Bbn u "$p"` at any of the three registry sites (one per run) | RED |
| 2 | Put `"${disk_heartbeat_url}"` back on the curl argv | RED (registry-heartbeat row) |
| 3 | Put `htpasswd -Bbn u "$ZOT_PULL_TOKEN"` back while keeping the pipe | RED (an argv-recording wrapper ahead of the real `htpasswd` on PATH logs argv then execs the real binary; a correct hash would not catch this; the argv-form control run must go RED) |
| 4 | Make the boot block's first `htpasswd` fail and keep going (drop the `set -e` effect) | RED (failing first aborts before `>>`; no second entry; the docker launch not reached) |
| 5 | Leave a `$${` unrendered, or hand-edit the extracted block | RED (extraction comes ONLY from the budget script's offline render; non-empty and `bash -n` rows; fails closed in CI on a missing terraform or docker) |
| 6 | Move `install -m 600` after the first write, or change its mode | RED (the stat taken inside the first `htpasswd` stub sees 0644 under umask 022; a delete-only battery would not see a REORDER) |
| 7 | Change the push line's `>>` to `>` | RED (the pull entry is truncated: the file must hold exactly two entries) |

**Harness rows.** (a) A suite edit that empties the rendered-block extraction must RED (non-empty extraction row). (b) The rendered-block arm joins `DECLARED_ROWS` and the `_arm_skip` counts, so a docker-less local run reports skipped rows and the declared floor still counts them. (c) Must-PASS inputs that are not the canonical: option cluster in another order (`-iB`), and a `-vb` that appears only in a YAML comment. **Anchor.** The census compares to the tracked tree, so a diff that edits both a site and the test passes consistency; what outside the commit must also move is the real-binary suite measured on the shipped image digest and the production boot itself (the #10119 probe).

### Guard 2 - A non-RFC1918 address-shaped clientIP on the registry plane alerts

**Property.** For every shipped `SOLEUR_ZOT_LOG` envelope row or `SOLEUR_ZOT_DISK` row from the registry host, the first `clientIP` value, if address-shaped and not in 10/8, 172.16/12 or 192.168/16, makes the alert's count exceed zero; and the alert exists, is applied and is unpaused.

**Assembly.** The predicate in `registry_clientip_not_rfc1918_sql` is the one chokepoint; both producer shapes enter through the same `startsWith` pair; the resource pair and BOTH `-target=` lines are the second assembly (an untargeted resource never exists, #5566); the infra-validation registration is the third (a suite that never runs guards nothing); the pinned zot image digest is the fourth (a field-order change arrives with a digest bump). Not covered, named: IPv4-mapped IPv6 beyond `::ffff:`, non-address tokens (`default`), rows the shipper rate-caps away, a public address in a different top-level field, and the Better Stack evaluator being unavailable (the heartbeats' concern).

**Mutation matrix** (run on COPIES of the .tf and the workflow in a temp dir through `REGCIP_TF`/`REGCIP_WF`, never the tracked files):

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `NOT match(...)` negation (private ranges would alert) | RED |
| 2 | Narrow the private alternation (drop the 172.16/12 arm, or change `3[01]` to `3[0]`) | RED |
| 3 | Remove the IPv6 colon-count clause | RED |
| 4 | Remove the `SOLEUR_ZOT_DISK` startsWith conjunct (the second member) while the envelope conjunct stays | RED |
| 5 | Replace `extract` (first match) with an any-occurrence match | RED (the first-occurrence pin) |
| 6 | Drop or weaken the envelope prefix (the `shipper=zot-log-shipper host=soleur-registry` text with its trailing space), or turn `startsWith` into a substring or `position` match | RED |
| 7 | Delete either of the two `-target=` lines | RED |
| 8 | `paused = true`, `higher_than` to `lower_than`, `value` above 0, `confirmation_period` above 0, or a changed `check_period`/`query_period`/`recovery_period` | RED |
| 9 | Re-point the exploration `source` variable, drop `time BETWEEN` or `GROUP BY`, or remove `metadata.runbook` / `incident_cause` | RED |
| 10 | Bump `zot_image_amd64` in `zot-registry.tf` without updating the suite's verified-digest pin | RED (forces the live field-order re-check) |
| 11 | Remove the suite's registration from `infra-validation.yml` | RED (registration row) |

**Harness rows.** The suite reports `0 passed, 0 failed` as RED (a dispatch floor on its own row count); a suite edit that skips the mutation loop must RED; must-PASS: the same predicate re-wrapped across different whitespace and line breaks (the sibling collapses whitespace at the resource site) and a renamed local that the resource still references. **Anchor.** The offline suite is structural; what outside the commit must also move is the live engine: the #7530 probe runs the extracted predicate over the 16-literal table and the post-boot window, and the ADR-218 reconciler reports live drift.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_DISK heartbeat rows from the registry host (every 5 minutes, direct POST to Better Stack source 2457081) carrying htpasswd_pull_matches, htpasswd_push_matches, store_luks, store_mount_src, store_escrow, boot_id and ping_rc; the absence-based Better Stack heartbeats soleur-registry-prd (60 s liveness) and soleur-registry-disk-prd (900 s); the armed alert soleur-registry-clientip-not-rfc1918-prd (checked every 300 s over 900 s)"
  cadence: "5 minutes (heartbeat row), 60 s (liveness beat), 300 s (alert evaluation)"
  alert_target: "team email via Better Stack for the Logs alert (free tier, no escalation policy); the heartbeats are email-only too (push, call and sms false, no policy on the free tier)"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (zot-disk-heartbeat.sh, zot-liveness-heartbeat.sh), apps/web-platform/infra/zot-registry.tf (betteruptime_heartbeat), apps/web-platform/infra/betterstack-logs-alerts.tf (registry_clientip_not_rfc1918, registry_store_not_luks)"
error_reporting:
  destination: "layer 3, the registry host POSTs directly to Better Stack Logs (this host runs no Vector); layer 6, GitHub Actions run logs for the dispatcher, the apply and the follow-through probes"
  fail_loud: "a boot block that aborts leaves zot not launched, so the liveness heartbeat soleur-registry-prd (HTTP 000, no beat) is the alarm (an email on the missed beat) and the dispatcher's Poll step reports the apply conclusion (the disk heartbeat keeps beating because its cron and the explicit runcmd line run regardless of the zot block; its row reads state_status=unknown with zot_image_digest=unknown and zot_image_fetch=ok, which is the discriminator, not an alarm; the htpasswd_*_matches fields only say WHERE it aborted: unknown/unknown before the htpasswd file exists, a partial true/unknown after the first pipeline, true/true when docker run or the mount gate refused); a wrong htpasswd shows as htpasswd_*_matches=false on the heartbeat row and stops the web consumer probe's authenticated beat; a public clientIP emails the team through the new alert; any dispatcher non-success arm posts a registry-delivery verdict comment on the PR"
failure_modes:
  - mode: "boot block aborts (a failed htpasswd pipeline, install error) so zot never launches on the replaced host"
    detection: "no journald shipper on this host (it POSTs directly to Better Stack Logs, outside layers 1-6) plus layer 6 (the dispatcher workflow run log, Poll step): the liveness absence heartbeat soleur-registry-prd stops; the disk row keeps shipping with state_status=unknown and zot_image_digest=unknown; state_status=unknown with zot_image_fetch=ok means boot-block abort (the htpasswd_*_matches fields then locate it), zot_image_fetch not ok means image-fetch failure"
    alert_route: "Better Stack heartbeat email on the missed beat (free tier: no push, call or sms); verdict comment on PR 10320 if the apply or poll fails"
  - mode: "htpasswd built over an empty or wrong password, so the registry rejects every pull"
    detection: "direct-POST rows outside layers 1-6 (read through the Better Stack query connection): htpasswd_pull_matches=false or htpasswd_push_matches=false on the SOLEUR_ZOT_DISK row of the new boot (the -vi verifier compares the file to the live Doppler token), and the authenticated web-zot-consumer probe beat stops"
    alert_route: "the web consumer probe heartbeat emails on a missed beat; the #10119 probe exits 1 on the new boot and reports the field; no alert keys on htpasswd_*_matches itself (query-only for the mismatch)"
  - mode: "a converted heartbeat curl mis-feeds its config so no beat is sent"
    detection: "direct-POST rows outside layers 1-6: ping_rc non-zero on the SOLEUR_ZOT_DISK row for the disk beat; the missed beat itself for both"
    alert_route: "Better Stack heartbeat policy (the absence is the primary alarm)"
  - mode: "a non-RFC1918 clientIP is shipped (ingress topology drift)"
    detection: "direct-POST rows outside layers 1-6 (a Better Stack Logs alert over them): the new alert predicate over shipped envelope and disk rows, sampled at 17 ordinary rows per tick; email only (free tier, no escalation policy)"
    alert_route: "Better Stack alert email to the team (free tier: no push, call or sms); runbook registry-clientip-rfc1918-7530.md and the CLO re-review trigger"
  - mode: "the new alert is a false positive at boot (a loopback or docker-NAT address), never applied (untargeted, count-cap refusal, displaced push apply) or silently paused"
    detection: "layer 6 (apply workflow run log and follow-through probe output): the #7530 probe runs the extracted predicate as written plus controls over the post-boot window before it can PASS and exits 3 on a failed apply; a refused apply is a red push-apply run; the ADR-218 reconciler reports a live pause as drift"
    alert_route: "red apply run; the probe stays at exit 2/3 and logs daily until resolved"
  - mode: "the dispatcher refuses or the apply fails"
    detection: "layer 6: registry-delivery verdict comment kind=refused|apply-failed|dispatch-failed|cancelled|unverified|gate-failed|undetermined on PR 10320 (posted only on non-success)"
    alert_route: "the red dispatcher run and the PR comment; the owner reads the runbook table"
logs:
  where: "Better Stack Logs source 2457081 (registry host direct POST: SOLEUR_ZOT_DISK, SOLEUR_ZOT_LOG envelopes); GitHub Actions run logs (dispatcher, apply, probes)"
  retention: "Better Stack team retention (hot window about 40 minutes plus the S3 archive); Actions logs 90 days"
discoverability_test:
  command: bash scripts/followthroughs/registry-clientip-alert-7530.sh
  expected_output: "PASS"
  credentials_required: "BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (Doppler soleur/prd_terraform) - the stored registry log stream and the live alert predicate have no unauthenticated read path; the offline suites verify the code and the SQL text, not the stored stream or the engine"
```

The byte budget is a required CI check (`cloud-init-user-data-size.test.ts`, `registry-userdata-budget.sh`), not an operational failure mode.

The declared `credentials_required` makes preflight Check 10 `SKIP-DECLARED` this command, so the plan OWNS the corpus bump: `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` goes 66 to 67, with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment its failure text asks for (placement: a correctly-indented child of this plan's `discoverability_test:` sub-block, value on one line; truth: the probe reads Better Stack through the ClickHouse HTTP connection credential; no substitute: the warehouse has no unauthenticated read path and the host is no-SSH). Run the full `bun` battery once before pushing (the ratchet surfaces only there).

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled all forks on 2026-10-14 (decision-challenges.md): A2 standing alert for #7530 with email-only alert semantics and scope; no retune for #7456(c) with a future evidence bar; #8408 has nothing unbuilt and its reopen loop ends by dropping the directive; the readiness rider is conditional with a stated byte drop order (plan review then cut it); no credential rotation; failed-first-boot stance and merge window. Risks recorded: the unattended replace; mode 600 readability (moot, the END state equals production's today); alert false positives in the first post-replace window; the dormant probe (tracked #10321); sampled coverage.

### Legal (CLO)

**Status:** reviewed
**Assessment:** The alert satisfies the intent of the 2026-08-13 binding ruling (stronger than the probe asked for: continuous, no tracker, count-only email), becoming an enforced invariant only after merge, push apply and the #7530 probe's PASS, and as detection not prevention. Required changes folded in: the runbook content (above), the sampling and field-order residuals, documentation addresses for the synthetic table, and a small Art. 30 register PA-8 amendment (a dated, merge-conditioned bracket in section (c), which says the invariant is "referred to the CTO and tracked separately", and in section (g) TOMs: the alert as a control, its sampling scope, the 90-day retention consequence, conclusion unchanged), to be attested at ship Phase 5.5 (the CLO reviews it). The append-only pointer in `2026-08-counsel-review-7440.md` is acceptable if written "fires on merge of PR #10320" (the #8207 rule), carries a frontmatter pointer key, and puts a `> Superseded` marker under trigger 2's sentence "does not audit shipped values". No GDPR or CCPA gap in the rest of the plan (htpasswd holds bcrypt hashes of service principals, not personal data; counts-only probe output is correct).

**GDPR gate (advisory, `soleur:gdpr-gate`, heuristic, not legal review):** no regulated-data schema surface is touched (no migration, no `.sql`, no auth code); no Art. 6, 5(1)(e), 17 or Art. 9 trigger; no new processor or non-EEA vendor (Chapter V unchanged: the alert lives in the existing Better Stack account); the single Art. 4(1) question (clientIP) is the subject of Part B. No Critical finding; no `compliance-posture.md` write.

### Operations (COO)

**Status:** not spawned
**Assessment:** no new vendor, no new recurring cost (a Better Stack alert inside the existing plan; the alert-count cap is an unmeasured vendor-tier risk recorded in the IaC section), no process change beyond the hand-over; the production-replace scheduling is the owner's, recorded in Operator Holds.

### Product (CPO sign-off)

**Status:** reviewed
**Assessment:** `requires_cpo_signoff` granted with two conditions, both folded into the Hand-over: say what the owner does about the merge-fired web release, and what the owner does on a failed first boot (revert PR first, not a re-dispatch of the same template). The User-Brand framing names the right artifact and vector; `single-user incident` is the right threshold; the Hand-over carries the recommended merge window and the explicit "rotation not required" ruling.

No Product/UX gate: no UI surface (no file under `components/`, `app/**/page.tsx`, `layout.tsx`).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE batch PR (one cloud-init-registry.yml change, one registry host replace, one deploy freeze) for #10119" | Part A, one registry commit last | mapped |
| 2 | "#8408 (standing alert `registry_store_not_luks`; reboot-surviving launch gate asserting /var/lib/zot is backed by /dev/mapper/registry on every container start; escrow passphrase re-test)" | Part C: delivered by PR #8456 (premise correction); reopen-loop removal and the owner close | mapped |
| 3 | "#7530 (enforce the RFC1918 clientIP invariant on the zot log readback; investigate first)" | Part B alert plus the investigation table | mapped |
| 4 | "#7456(c) rate-cap retune only if justified ... ask the CTO while planning and record the ruling" | Part D; decision-challenges.md row | mapped |
| 5 | "Fold PR B's registry scope into THIS batch" | Part A items 1 to 4 (htpasswd x3, install -m 600, heartbeat curls x2, comments) | mapped |
| 6 | "it stops at a green, ready PR and the owner gets the exact merge command and watch steps. Honour that." | Hand-over, Operator Holds | mapped |
| 7 | "plan the pre-merge checks (`gh run list --workflow apply-web-platform-infra.yml --status in_progress\|queued`, `gh run list --workflow registry-host-replace-dispatch.yml`) and the post-merge watch" | Hand-over | mapped |
| 8 | "Plan every issue as `Ref #N` (close only after post-merge evidence)" | Overview, Part E probes, PR body rule | mapped |
| 9 | "The #7079 item-1 survivor ... is a free rider only: fix it only if the batch already touches that block; never alone." | Overview table: considered, not included (plan review), #7079 note | descoped - justification: the rider satisfies no batch property, its result feeds nothing (CTO ruling), and it would leave 32 B of headroom on a sole-pull-path boot block |
| 10 | "Plan the smallest fix. Include acceptance criteria, an `## Observability` block ... a `## User-Brand Impact` section with threshold `single-user incident`, and a Test Scenarios section." | those sections | mapped |
| 11 | "Note `BASELINE_DECLARED_PROBES` is 66 on origin/main; a plan declaring credentials_required owns the bump." | Observability closing paragraph, Files to Edit, AC | mapped |
| 12 | "Any new/edited *.test.sh must be run through the repo ratchets" | Phase 6, Acceptance Criteria | mapped |
| 13 | "Check whether the sibling planning artifacts or merged PRs already cover parts of #8408" | Overview table, Research Reconciliation | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Registry template edits (Part A) | "registry template htpasswd passwords off argv, B1/B2 of the argv-bearer sweep residue" | asked |
| Two heartbeat curls | "Fold PR B's registry scope into THIS batch" | asked |
| Standing alert for clientIP (Part B) | "enforce the RFC1918 clientIP invariant on the zot log readback" | asked |
| New runbook for the alert | asks 3 | inferred - the alert's `metadata.runbook` and `incident_cause` need a target, and the alert's legal consequence must be written where the responder looks |
| Two follow-through probes (Part E) | "Plan every issue as `Ref #N` (close only after post-merge evidence)" | asked |
| Reopen-loop removal on #8408 | "Check whether the sibling planning artifacts or merged PRs already cover parts of #8408 ... so the batch only plans what is still open" | asked |
| ADR-218 / ADR-211 / ADR-184 / ADR-280 amendments and the counsel-review pointer | "Plan the smallest fix" | inferred - ADR-218 requires one amendment per new Logs alert; ADR-211 points at #7530 as the owner of clientIP and would otherwise lie; ADR-184 names the shipper contract the alert now consumes; ADR-280 records each sweep batch |
| Art. 30 register PA-8 brackets (c) and (g) | "enforce the RFC1918 clientIP invariant on the zot log readback" | inferred - the CLO's review requires the register to say the invariant is now monitored (the register currently says it is referred and tracked separately) |
| `BASELINE_DECLARED_PROBES` 66 to 67 | "a plan declaring credentials_required owns the bump" | asked |
| Registration in `scripts/lint-betterstack-emitter-read.sh`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` | "Any new/edited *.test.sh must be run through the repo ratchets" | inferred - the census guard (#8875) and the orphan-suite census red CI on an unregistered reader or suite |
| Consumers of a new Logs alert (send-failed mutation suite 13 to 14, `betterstack-log-query.md` row, `infra-validation.yml` registration) | "enforce the RFC1918 clientIP invariant on the zot log readback" | inferred - the betterstack-logs-alerts.tf header lists them as mandatory steps for any new alert |
| Test updates for three heartbeat-rendering suites | "Fold PR B's registry scope into THIS batch" | asked (the conversion changes what their stubs see) |

### Split Assessment

- Subsystems touched: 6 - `apps/web-platform/infra`, `.github/workflows`, `tests/scripts` and `scripts`, `plugins/soleur/test`, `knowledge-base` (ADRs, runbooks, legal pointers), the `apps/web-platform/test/infra` suite root
- Planned files: about 25 edits plus 6 creates | Estimated changed lines: about 700 (most are tests, probes and docs; the template change is about 12 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The owner's batching decision (one replace, one freeze) is the stated reason; the thresholds trip on test, probe and doc volume, not on production surface. The separable peel points are (1) the alert commit (no host effect), (2) probes and enrollment, (3) the single registry commit, which declines the replace.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` - Part A items 1 to 4
- `apps/web-platform/infra/zot-image.provenance.md` - reword "baked with `htpasswd -Bbn`"
- `apps/web-platform/infra/registry-boot-guard.test.sh` - 127/6/1-through-the-pipe row; probe pins re-run
- `apps/web-platform/infra/htpasswd-stdin.test.sh` - rendered-boot-block rows
- `apps/web-platform/infra/zot-liveness-heartbeat.test.sh`, `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`, `apps/web-platform/infra/zot-image-fetch.test.sh` - curl stub honours `--config -` (bounded stdin read)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` - Part B
- `.github/workflows/apply-web-platform-infra.yml` - two `-target=` lines
- `.github/workflows/infra-validation.yml` - register the new alert suite (step and any `paths:` entry)
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` - the `values = [local.vector_prd_source_id]` count 13 to 14
- `tests/scripts/test-argv-bearer-sweep.sh` - S6 allowlist to zero, ceiling row rewritten, registry-heartbeat row, `EXPECTED_TESTS` re-pin
- `.claude/hooks/grep-q-pipe-guard.test.sh` - `PRODUCER_JOIN` / `PJ_TRIPLES` re-measure (only if new rows change the measured set)
- `scripts/lint-betterstack-emitter-read.sh` (+ `scripts/lint-betterstack-emitter-read.test.sh` if its census floors move) - allowlist the two new readers
- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` - register the two probe suites
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - `BASELINE_DECLARED_PROBES` 66 to 67 with the comment
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - row under "Standing alarms over this source"
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`, `ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md`, `ADR-184-registry-host-container-log-shipper.md`, `ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` - dated amendments
- `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` - appended pointer ("fires on merge of PR #10320"), frontmatter pointer key, `> Superseded` marker under trigger 2's "does not audit shipped values"
- `knowledge-base/legal/article-30-register.md` - PA-8 sections (c) and (g): dated, merge-conditioned brackets (CLO attests at ship Phase 5.5); check for a published legal-docs mirror and update it in the same edit if one exists
- GitHub issue bodies (not repo files): #8408 (drop directive and label in one edit), #10119 and #7530 (directives)

## Files to Create

- `apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh`
- `knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md`
- `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` and `.test.sh`
- `scripts/followthroughs/registry-clientip-alert-7530.sh` and `.test.sh`

## Open Code-Review Overlap

2 open scope-outs touch these files: #8735 (infra-validation notify-main-failure misses cancelled jobs) and #7942 (two `*.mutation.sh` batteries run in no gate), both via `.github/workflows/infra-validation.yml`.

- #8735: **Acknowledge.** This plan adds one suite-registration line to that workflow; the cancelled-job notification gap is a different concern and needs its own cycle.
- #7942: **Acknowledge.** The new alert suite is a plain `.test.sh` registered in the same place as its sibling, not a `*.mutation.sh`; the unrun-battery question is separate.

## Implementation Phases

Commit order is the staging, and it exists only before the squash merge: (1) alert, (2) probes and enrollment, (3) docs and ADRs, (4) the registry template with its suites, battery rows and ADR-280 text, LAST.

### Phase 0 - Baselines (read-only, no commits)

- Record: stored size 21,500 B and headroom 100 B (`bash apps/web-platform/infra/registry-userdata-budget.sh`), `apply-web-platform-infra.yml` size, `EXPECTED_TESTS`, `S6` floors, `PJ_TRIPLES`/`PRODUCER_JOIN`, the c4-count-parity result, and the current `boot_id`.
- Run `bash apps/web-platform/infra/registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh`, `zot-liveness-heartbeat.test.sh`, `zot-disk-heartbeat-redaction.test.sh`, `zot-image-fetch.test.sh` to confirm green on the unedited tree.
- Re-run the 7-day clientIP census and the 16-literal classification table to confirm nothing changed (one number, written once, in the .tf comment).

### Phase 1 - RED first

- New S6 and registry-heartbeat rows, the rendered-boot-block rows and the alert suite fail on `main` (the template still has the argv forms; the alert does not exist). Commit nothing red; run to prove they red, then implement.

### Phase 2 - Part B alert (commit 1)

- `betterstack-logs-alerts.tf` local and resource pair with the live-probe counts as a comment (population, as written 0, control equal to the population, the classification table, the verified zot digest); the two `-target=` lines; the new suite (with the verified-digest pin) and its `infra-validation.yml` registration; the send-failed mutation suite count; the `betterstack-log-query.md` row; the runbook. Verify the suite's mutation rows RED and the must-PASS rows green; confirm `terraform fmt -check` and `terraform validate` (offline, per the repo's infra-validation recipe).
- ADR-218 amendment, ADR-211 and ADR-184 notes.

### Phase 3 - Part E probes and enrollment (commit 2)

- Write the two probes and their suites (RED first), register them in the emitter-read lint, `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`; run the lint, its suite and `bash scripts/lint-orphan-test-suites.sh`.
- Edit #8408 (drop directive and label in one edit); add directives to #10119 and #7530 (copy the probes to the main checkout first; dry-run the real sweeper on the branch).
- `BASELINE_DECLARED_PROBES` 66 to 67 with the comment.

### Phase 4 - Docs (commit 3)

- Counsel-review pointer and PA-8 brackets after the CLO findings are in, `Ref` comments on #7521 and #7456 with the CTO ruling, a note on #7079 recording the measured rider cost (+32 B) and that it was not included.

### Phase 5 - Part A registry template (commit 4, LAST, ONE commit with suites, battery rows and ADR-280 text)

- Edit the template (items 1 to 4), re-measure bytes after each edit group, apply the CTO drop order if headroom falls under 30 B. Update the three heartbeat-rendering suites' curl stubs, `registry-boot-guard.test.sh`, `htpasswd-stdin.test.sh` rendered-block rows, S6 stage (allowlist to zero, ceiling row rewritten, registry-heartbeat row, converted-site rows, `EXPECTED_TESTS`), then the ratchets. ADR-280 addendum.

### Phase 6 - Ratchets and verification

Run, on every new or edited `*.test.sh` and probe: `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash plugins/soleur/test/fixture-relative-assert.test.sh`; `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`; `bash scripts/guard-vacuity-floor.test.sh`; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`; `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt <each new or edited .sh>` (the baseline only shrinks; fix findings, never regenerate it); `python3 scripts/lint-shell-trace-credential-refusal.py`; `bash scripts/lint-orphan-test-suites.sh`; `bash scripts/lint-betterstack-emitter-read.test.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; the registry byte gates (`registry-userdata-budget.sh`, `cloud-init-user-data-size.test.ts`); the full `bun` battery once for the `BASELINE_DECLARED_PROBES` ratchet; `npx markdownlint-cli2` on the plan, tasks and runbook. Use `/usr/bin/grep -a` and `$SECONDS` for timings.

### Phase 7 - PR body and hand-over

- First line as specified, the `Ref` set, the production-apply table, the measured byte table, the pre-merge `bash scripts/registry-delivery-change.sh` preview (confirm this PR is the ONLY render delta, or name the other deltas it delivers), the recorded pre-merge `boot_id`, and the Hand-over section. Mark ready; do not arm auto-merge; do not merge.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md (headless run: no block written) -->

### Pre-merge (PR)

- [ ] `cloud-init-registry.yml` carries no argv-form `htpasswd` (`-Bbn`, `-vb`) and no `*_heartbeat_url` on a curl argument list; `install -m 600 /dev/null /etc/zot/htpasswd` precedes the first write and `chmod 600 /etc/zot/htpasswd` is gone (`tests/scripts/test-argv-bearer-sweep.sh` S6: `S6_ALLOW` empty, `S6_ALLOW_CEIL=0`, the ceiling row asserts zero entries, `EXPECTED_TESTS` re-pinned to the measured total).
- [ ] The rendered boot block (from the offline templatefile render, not hand-substituted; stub list derived by a census of the block's command words and including `jq`, `findmnt`, `sleep`, `chattr`, `docker`, `doppler`, `curl`, `head` and the `/run/soleur/zot-image-id` fixture) runs through `bash -s` inside the digest-pinned `ubuntu:24.04` + `apache2-utils` image: `-Bin` hashes interoperate with `-vi`, a failing first `htpasswd` aborts before the `>>` with no half-written second entry, the file holds exactly two entries, and the stat taken inside the first `htpasswd` call reads mode 600 under `umask 022` (`apps/web-platform/infra/htpasswd-stdin.test.sh`).
- [ ] `registry-boot-guard.test.sh` green; a row pins 127, 6 and 1 mapping to `unknown` through the pipe; a static row pins no `set -e`/`pipefail` before `_htp_verify`.
- [ ] The three heartbeat-rendering suites are green with the converted curls (the stub reads `url = "..."` from stdin with a bounded read and records it).
- [ ] `bash apps/web-platform/infra/registry-userdata-budget.sh` stored size recorded before and after in the PR body (expected 21,536 B); `REGISTRY_GZIP_BUDGET` unchanged; headroom at least 30 B (`cloud-init-user-data-size.test.ts`).
- [ ] The alert resources exist in `betterstack-logs-alerts.tf` with the predicate above, `paused = false`, `higher_than` / `value = 0`, `query_period = 900`, `on_missing_data = "treat_as_zero"`; both `-target=` lines are in `apply-web-platform-infra.yml`; the new suite is registered in `infra-validation.yml`; every mutation row of Guard 2 is RED against its mutant and the must-PASS rows are green (`apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh`); `git grep -c 'values        = \[local.vector_prd_source_id\]' apps/web-platform/infra/betterstack-logs-alerts.tf` equals 14 and `betterstack-send-failed-alert-mutation.test.sh` is green with its count at 14.
- [ ] The live-probe counts in the .tf comment reproduce: population over 7 days, as written 0, private-flagged control equal to the population, and the 16-literal table matching the flags above.
- [ ] The two probes exist with `.test.sh` suites covering every exit arm (0, 1, 2, 3), no write call, counts-only output (the clientIP probe's suite asserts no address-shaped string in output), the rule that a missing baseline, unreadable window or equal boot id is 3 and never 1, the template-identity check, and an emitter-read allowlist entry; the suites are registered in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`; `bash scripts/lint-betterstack-emitter-read.test.sh` and `bash scripts/lint-orphan-test-suites.sh` are green.
- [ ] `BASELINE_DECLARED_PROBES` is 67 with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment; the full `bun` battery is green.
- [ ] ADR-218, ADR-211, ADR-184 and ADR-280 amendments are present; `c4-count-parity.test.sh` green.
- [ ] #8408's body carries NO `soleur:followthrough` directive and no `follow-through` label (one edit); directives for #10119 and #7530 are enrolled with comma-separated `secrets=` and the sweeper dry-run on the branch shows each tracker's `exit=` line.
- [ ] #10321 exists (done) and is referenced from the alert runbook and the ADR-218 amendment.
- [ ] All ratchets in Phase 6 are green for every new or edited `*.test.sh` and shell probe.
- [ ] The PR body's first line is the replace notice; it carries `Ref` lines only (no closing keyword in body or title), the production-apply table, the pre-merge render preview and the recorded `boot_id`.
- [ ] Review and QA complete; **no merge** (Operator Holds).

### Post-merge (owner-approved merge only; automated or read-only evidence)

- [ ] The dispatcher run for the merge SHA concluded `success` with its Dispatch and Poll steps `success`; no `registry-delivery` verdict comment on the PR; the follow-on `registry-host-replace` apply concluded `success`.
- [ ] A new `boot_id` reports `htpasswd_pull_matches=true htpasswd_push_matches=true`, `store_luks=yes`, `store_mount_src=/dev/mapper/registry`, `store_escrow` `pending` then `ok`, a non-unknown `zot_image_digest`; the registry `/v2/` pull path answers (the liveness beat resumes).
- [ ] The push apply created the alert pair; the #7530 probe PASSes (classification table, as written 0 over the post-boot window, control above 0) and the #10119 probe PASSes; both trackers are closed by their probes, not by hand.
- [ ] The owner closes #8408 with the batch's posture evidence; #7521, #7456 and #7079 carry the batch outcome comments; #10205's Phase 2 checklist is updated item by item with evidence.

## Test Scenarios

1. Boot block, success path: both pipelines run, the file holds exactly two entries (`user:$2y$...`), mode 600, `htpasswd -vi` returns 0 for each token.
2. Boot block, first `htpasswd` fails (stub exits 1): `set -e` aborts, no second entry, `docker run` never reached, nonzero exit.
3. Boot block, empty token: the guard exits 1 before any pipeline; no file content written (the file may exist empty at mode 600).
4. Argv recording: a wrapper `htpasswd` ahead of the real one logs argv; neither token appears in argv; both appear on stdin; the real binary then runs.
5. Divergence probe: stub `htpasswd` returning 0, 3, 6, 1 and 127 through the pipe maps to true, false, unknown, unknown, unknown; the token never appears in the probe's output.
6. Heartbeat feeders rendered from the YAML: the disk feeder with a `curl` stub exiting 0 and 22 sets `PING_RC` 0 and 22; the liveness feeder pings only on 200 and 401; the stub receives the URL on stdin config, never argv; a stub handed an argv URL does not block.
7. templatefile render: the rendered YAML contains no `$${` and no `%{`; `bash -n` on the extracted block passes.
8. Alert suite structural rows: envelope conjuncts for both producers, first-occurrence `extract`, the private alternation, the IPv6 clause, the alert parameters, both `-target=` lines, the registration, the verified-digest pin; the Guard 2 mutation rows on copies.
9. Live engine rows (the probe, not CI): the 16-literal table, as-written count 0 with a positive population, private-flagged control above 0.
10. Probe arms for each of the two scripts: not merged (2), merged but no qualifying run or apply yet (2), qualifying run but a reverted template (3), read path unproven or baseline missing or equal boot ids (3), PASS (0), measured contradiction such as `htpasswd_*_matches=false` or `non_rfc1918>0` (1, counts only).
11. Probe safety: each runs unchanged under the sweeper's `env -i` shape and with `dry_run`; none calls `gh issue close`, `gh issue comment` or any write; each refuses to run traced with a credential set (exit 78).
12. Batch invariants: S6 reports exactly 4 invocations in 2 files all stdin form, zero allowlist entries, and the registry-heartbeat row lists exactly the 2 converted sites.
13. Budget: `registry-userdata-budget.sh` exits 0, stored at most 21,600 B, headroom at least 30 B.

## Dependencies & Risks

- **Unattended replace of the sole pull path** (the dominant risk). Mitigations: the real-binary rendered-block test including failure arms; the dispatcher's read-only preflight (refuses when already degraded); the pre-merge checks; volume preserved; a staged revert; the owner chooses the moment (Operator Holds).
- **Delivers more than this PR** if an earlier `zot-registry.tf`/`variables.tf` delta is still undelivered: the pre-merge `registry-delivery-change.sh` preview names every other delta.
- **Byte budget:** 64 B headroom after all edits (measured on a scratch copy); the real implementation may differ by a few bytes, hence the 30 B rule and the CTO drop order. A shortfall never raises the budget.
- **Alert false positive at the first post-replace boot** (CTO): validated by the #7530 probe before PASS; the five observed boots show none.
- **Alert displaced or refused:** the push apply can be evicted from the workflow's single pending slot or refused on the unmeasured Better Stack alert-count cap; the #7530 probe accepts a descendant SHA's successful apply and exits 3 (not an endless 2) on a failed one; the registry replace is a separate dispatched run and is unaffected.
- **Sampled detection and field-order dependence:** only shipped rows are graded and zot must keep writing `clientIP` first; recorded in the .tf, the runbook and ADR-184, and the verified-digest pin forces a re-check on a zot bump.
- **Directive enrollment before the scripts are on main:** until the merge the sweeper logs `missing in repo HEAD` to stderr for the two trackers (no comment, no red run); accepted.
- **Sibling in-flight work on `cloud-init-registry.yml`:** the owner's comment on #10119 asks other sessions to say so before opening a PR; re-check open PRs touching the file at Phase 5 start (`gh pr list --state open --search 'cloud-init-registry.yml in:path'`).

## Rollback

Before the merge: peel the single registry commit (the replace is then not triggered); the alert commit is independent. After the merge: a revert PR re-fires another replace (idempotent; the volume is preserved). The alert is NOT removed by deleting its resource pair and `-target=` lines: a targeted apply that no longer names a resource leaves it live (verified on a scratch root with terraform 1.9.8; CI applies with the pin in `apply-web-platform-infra.yml`, 1.10.5, and the behaviour is the same on both: a plan that omits the resource from configuration but keeps it targeted destroys it). To retire it, keep the `-target=` lines in the PR that removes the resource pair so that apply destroys it. That push apply counts the delete in `resource_deletes` of the destroy guard (`destroy-guard-filter-web-platform.jq`), so the merge commit must carry `[ack-destroy]`. A squash revert of the whole merge commit would orphan the alert in exactly that way, so the recovery for a template defect is the partial revert described under "Failed first boot". Probes are read-only and are retired by deleting the file and the directive; their `RETIREMENT:` headers list the references.

## Success Metrics

- The replace lands once, with a fresh `boot_id` reporting both `htpasswd_*_matches=true`.
- `git grep` census: zero argv-form `htpasswd` invocations and zero heartbeat URLs on a curl argv in tracked non-test, non-comment code.
- The alert exists unpaused and the probe's live controls pass; the seven-day non-RFC1918 count reads 0.
- #10119 and #7530 closed by their probes' PASS; #8408 stops generating sweeper comments and is closed by the owner.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- `%{` anywhere in `cloud-init-registry.yml` (comments included) breaks the templatefile render; write `%%{`. A `${...}` in a comment interpolates.
- The word that the incident-PIR gate keys on must not appear in the plan, the runbook or the PR body; use "unavailable" or "disruption".
- A probe's output is posted verbatim to a public issue: the clientIP probe prints counts only, never an address, and the htpasswd probe withholds the volume alias and backing device.
- The sweeper splits `secrets=` on commas; a space-separated list forwards only the first name.
- `grep` here may be ugrep: use `/usr/bin/grep -a`. There is no `/usr/bin/time`; use `$SECONDS`. Text containing the apply command's name goes through the Write tool, not inline Bash.
- The verdict comment exists only on non-success arms; do not wait for a success comment, and key every run read on the merge SHA.
- Mode-600 readability for zot: the file is bind-mounted `:ro` into the container and is already 600 root-owned in production, so the END state is unchanged; do not "fix" it by loosening the mode.
- `BASELINE_DECLARED_PROBES` surfaces only in the full `bun` battery; run it before pushing.

## References

- Epic #10205; issues #10119, #8408, #7530, #7456, #7521, #7079, #8386, #7455, #10093, #10301 (decision challenge), #10321 (new)
- Archived and live plans: `knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md` (Part B), `knowledge-base/project/plans/archive/20261014-173446-2026-10-13-fix-argv-bearer-followups-registry-inngest-probes-community-plan.md` (PR B)
- ADRs: ADR-280, ADR-218, ADR-211, ADR-184, ADR-096, ADR-172
- Runbooks: `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`, `followthrough-convention.md`
- Legal: `knowledge-base/legal/audits/2026-08-counsel-review-7440.md`, `knowledge-base/legal/article-30-register.md` PA-8
- Decision record: `knowledge-base/project/specs/feat-one-shot-registry-phase2-batch-10119-8408-7530/decision-challenges.md`
