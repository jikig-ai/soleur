---
title: "chore(infra): host-side zot consumer probe covers the inngest-bootstrap repo (Step A of #7258)"
date: 2026-10-11
slug: zot-consumer-probe-covers-inngest-bootstrap
branch: feat-one-shot-7258-consumer-probe-covers-inngest-bootstrap
issue: 7258
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: single-domain
---

# chore(infra): host-side zot consumer probe covers the inngest-bootstrap repo (Step A of #7258)

## Enhancement Summary

**Deepened on:** 2026-10-11
**Mode:** mechanical gates plus targeted live verification (read-only); the research fan-out was already spent during planning (learnings researcher, terraform-architect, CTO) and plan review (three reviewers), so no further agent fan-out was added.

### Gate results

- 4.4 precedent-diff: the rate-limit marker is pattern-bound. Precedent is `_canary` in the same file (`case "$last" in ''|*[!0-9]*) last=0`, `[ $((now - last)) -ge 1800 ]`); this plan REUSES it through one extracted helper rather than copying it, and the diff against the precedent is exactly one added arm: a future-dated marker emits (the precedent silences on it). The aggregation loop has no sibling precedent in the repo (the held-branch commit `f6279068df` is the only prior art and is not on `main`): pattern is novel, scrutinize it.
- 4.5 network-outage: Hypotheses carries verified L3 artifacts (Hetzner firewall rule set, bridge REDIRECT scope); no gap.
- 4.55 downtime and cutover: not triggered (no host replace, no lock-taking DDL, no container swap; the probe oneshot runs the new file on the next tick).
- 4.6 user-brand impact: present, threshold `none` with the sensitive-path scope-out bullet (`apps/web-platform/infra/`).
- 4.7 observability: all five fields present; `discoverability_test.command` starts with `bash`, has no `ssh `, is a single bounded query; `expected_output` is a literal; `credentials_required` is a non-placeholder declaration (so row-4 `SKIP-DECLARED` and the baseline bump apply).
- 4.8 PAT scan: no PAT-shaped variable or literal.
- 4.9 UI wireframe: not triggered (no UI surface). 4.10 encryption posture: `.tf` matched, no store or new connection (see `## Encryption Posture`). 4.11 guard contract: `lint-guard-contract.py` green (2 entries). 4.12 scope check: present once, mapped.

### Live verification of cited facts

- Rule IDs cited in the plan all exist as active rules in `AGENTS.md` (`cq-test-fixtures-synthesized-only`, `cq-write-failing-tests-before`, `hr-no-ssh-fallback-in-runbooks`, `hr-ssh-diagnosis-verify-firewall`, `wg-when-deferring-a-capability-create-a`).
- Issue/PR states: #9942 MERGED, #9529 MERGED, #7158 CLOSED unmerged, #7242 CLOSED, #7144 CLOSED (a drift issue), #9920 OPEN, #9956 OPEN, #9597 OPEN, #7577 OPEN, #9217 OPEN, #9979 OPEN draft.
- `_ping` occurs exactly twice in the probe (one definition, one call), as Guard 1's assembly states.
- No GitHub label is prescribed by this plan.

### Key improvements over the first draft (from plan review and deepening)

1. The committed Step B gate script, its suite, a sweeper tracker and Guard 3 were cut (two reviewers); the gate is criteria plus a fixed recipe whose output is recorded on #7258.
2. One shared rate-limit helper instead of a second copy; future-dated markers emit.
3. Positional-only override seam; whitespace and empty-element gates; per-run temp marker paths in every test helper; fault-line assertions filtered so marker lines cannot satisfy them.
4. Delivery-concurrency claim now rests on a historical red run (run 38097457915), not on graph reasoning.
5. The recipe anchors on the apply log timestamp T0 and `floor(ts/1800)` buckets, keeps credentials off argv, and treats a missing canary as not-gradable.

## Overview

The web-host zot consumer probe (`apps/web-platform/infra/web-zot-consumer-probe.sh`) checks, from the web host and with the
host's own pull credential over the private NIC, that the registry can serve ONE repository
(`jikig-ai/soleur-web-platform`). Nothing on the host side checks the second platform repository,
`jikig-ai/soleur-inngest-bootstrap`, which fresh web and inngest hosts pull at first boot. The registry-side script
`zot-entry-gate.sh` is the only other artifact that names that repository, and nothing invokes it.

This change (Step A of #7258, a probe-extension PR only) makes the probe take a comma-separated repository list, classify each
repository with the existing HTTP-code table, and ping the existing per-host heartbeat only when EVERY repository is servable
(all-must-pass; a 401 on any repository still exits 3). One heartbeat per host is kept. Fault lines name the repository, and a
rate-limited per-repo marker line proves a healthy run per repository from telemetry. The second repository is wired through new
locals in `web-probe.tf` (no new variable, no `server.tf` edit), which the existing delivery paths already carry.

Step B (a separate later PR, NOT planned here) deletes `zot-entry-gate.sh` and its registrations once this change is observed green
on a real run. The Step B gate is a stated, telemetry-only criterion with a fixed read recipe (Phase 7), whose result is recorded as a
comment on #7258 (see `## Step B follow-up`).

**PR body must say `Ref #7258`, never a close keyword** (the tracker is closed by Step B).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #7258 / brief) | Reality (verified 2026-10-11) | Plan response |
|---|---|---|
| #7258: the probe "now takes a comma-separated repo list covering both platform repos (authored on `feat-one-shot-resend-inbound-webhook-500`, currently held)" | False on `main`: single `ZOT_PROBE_REPO`, no list parsing. The work exists only as commit `f6279068df` on `origin/feat-one-shot-resend-inbound-webhook-500` (PR #7158 closed unmerged) | Build it here. Salvage the DESIGN only: that commit's curl line is the pre-#9597 `-u "$ZUSER:$ZTOK"` argv form and predates the `000000` normalization and `--canary-only`, so a cherry-pick would regress three shipped fixes |
| That commit added `variable "inngest_bootstrap_repo"` in `variables.tf` | `registry-host-replace-dispatch.yml` lists `apps/web-platform/infra/variables.tf` in its push `paths:` — a variables.tf edit would fire a registry HOST REPLACE | Use new `locals` in `web-probe.tf` only. `variables.tf` and `server.tf` stay untouched (`apply-deploy-pipeline-fix.yml` fires on `server.tf`) |
| Brief: heartbeat is "per host" via `betteruptime_heartbeat.web_zot_consumer` | Confirmed (`for_each = var.web_hosts`). Live (Better Stack API, 2026-10-11): `soleur-web-zot-consumer-web-1` (id 473113) and `-web-2` (id 475781) are `up`, `paused=false`, period 180 / grace 60; no incident on either since 2026-10-08 | Keep both; add no resource |
| Brief: the apply workflow "applies ssh-provisioned resources over the bridge to web-1" | True for web-1. The bridge (`.github/actions/cf-tunnel-ssh-bridge`) installs an iptables REDIRECT for web-1's `SERVER_IP:22` only. The SAME post-bridge apply step also targets `terraform_data.egress_gateway_web2` (web-2 public IP), which times out (`dial tcp 204.168.189.200:22: i/o timeout`) | See `## Hypotheses` and Decision D5: independent of this change; web-1 resources run concurrently and complete (evidence in D5) |
| Brief: "the previous PR #9942 and its apply finished" | Its push apply (run 38106710993) CONCLUDED `failure` at that web-2 step; every push apply since 2026-10-10 21:43Z (PR #9529) is red the same way; a later dispatch (run 38107265749, `registry_host_replace`) succeeded | Treat "finished" as "nothing in flight". Phase 0 re-checks. Observation is telemetry-based, never job-colour-based |
| Brief: `BASELINE_DECLARED_PROBES` "currently 55" | Re-read: `const BASELINE_DECLARED_PROBES = 55;` in `plugins/soleur/test/preflight-discoverability-test.test.ts` | This plan declares `credentials_required`, so bump to 56 with a ledger comment (Phase 4) |
| #7258: delete also "the `run: bash ...zot-entry-gate.test.sh` step in `infra-validation.yml`" | Suite registration is filesystem presence (ADR-252) plus rows in `suite-shard-legs.tsv` and `suite-durations.tsv` | Step B only |
| Brief assumes the new repo is mirrored in zot | Zot's own shipped log rows (Better Stack, 2026-10-11 00:19Z) show retention policy applied for `repository:jikig-ai/soleur-inngest-bootstrap` (17 rows), and the pull user has `read` on `**` (`cloud-init-registry.yml` accessControl) | Existence and ACL are evidenced, but the FIRST real probe run is the only host-side proof; Phase 0 re-queries |

## Research Insights

**Premise Validation.** #7258 is OPEN (priority/p3-low, type/chore); no merged PR closes it. #7242 (the zot bridge outage the
held branch waited on) is CLOSED. #7144 resolves to an unrelated drift issue (CLOSED). The cited artifacts exist on `origin/main`:
`web-zot-consumer-probe.sh`, `web-probe.tf` (`zot_probe_repo`), `web-probe-envwrite.sh`, `zot-entry-gate.sh`. The mechanism
(extend the consumer probe) is not in any ADR's rejected-alternatives table: ADR-096's sentence listing the
"pre-flip zot-entry-gate/soak-gate" already records it as **superseded**; ADR-117 governs heartbeat arming (no new heartbeat is added, so it is untouched).
The previous attempt on this branch family (plan `2026-10-10-fix-registry-template-render-fixture-hold-zot-entry-gate-delete`,
archived) recorded the unblock criteria this plan implements: (1) probe extension, (2) observed green on a real run, (3) then a
pure-delete PR.

**Property List.**

- P1. The per-host heartbeat is ping-eligible only if the host can read the tag list of BOTH platform repositories with the pull
  credential over the private NIC.
- P2. A fault on either repository names THAT repository in a line that is emitted on every faulting run and reaches Better Stack
  Logs without SSH.
- P3. A healthy run is observable per repository from telemetry (one marker row per repository inside every 1-hour window).
- P4. A host that still carries the pre-change single-repo env value behaves identically to today for ping, exit code and fault
  lines (web-2 until its next replace).
- P5. The Step B go/no-go is a stated, telemetry-only criterion with a fixed recipe, not a recollection.

**Cut List.**

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| A second `betteruptime_heartbeat` for the bootstrap repo | P2 | AND-aggregation cannot mask (a ping requires BOTH repos), and per-repo fault lines name the repo. A new heartbeat adds a TF resource, a Doppler secret, a per-host env key, a heartbeat-manifest row and an ARM-gate arm (ADR-117, measured-beat deadlines), for a one-time proof. Cut. (The 2026-07-18 masking learning is about OR across independent feeders; a single feeder with a conjunction is the opposite shape.) |
| `variable "inngest_bootstrap_repo"` (held-branch design) | P1 | A `locals` constant suffices; a variables.tf edit fires a registry host replace. Cut |
| Repair or resurrect `zot-entry-gate.sh` | P1 | Structurally a CI/operator-side gate over the tunnel with Doppler prd credentials; it cannot prove host-side pullability. Step B deletes it |
| A committed Step B gate script, its suite, a sweeper tracker and a `test-all.sh` registration (first draft of this plan; ~320 lines, marked `inferred`) | P5 | Cut at plan review (two independent reviewers): the gate is statable as criteria plus a fixed read recipe, and the thing it gates is the deletion of a script nothing invokes. The recipe's result is recorded on #7258. Optional later automation is a non-goal |
| A second marker file and rate-limit function for the per-repo rows | P3 | Extract the window check from `_canary` into one helper used by both; one rate-limit implementation, two marker files |
| Broadcast seam (one injected code applies to all repos) and three-repo rows | P1 | Positional-only override keeps every existing single-repo row identical and the contract is two repos. Cut |
| Credentialed read-only `terraform plan` as a numbered gate | no-replace evidence | Structural evidence (`ignore_changes`, destroy-guard) already carries it; the plan is opportunistic only |
| New static-parity test file | P1 | Fold into `web-zot-consumer-probe.test.sh`; a new suite needs two tsv registration rows (ADR-252). Cut |
| Staged "report-only for week 1" rollout for the bootstrap repo (CTO suggestion) | false-page risk | Operator direction is all-must-pass from day one; recorded as a decision challenge (`decision-challenges.md`), not applied |
| Fixing `terraform_data.egress_gateway_web2` (red apply stage) | none of P1-P5 | Out of scope; separate tracker (Decision D5) |

**Learnings applied** (`knowledge-base/project/learnings/`): `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking`
(OR-masking is the hazard; this design is a conjunction); `2026-07-28-the-fix-for-a-too-noisy-alarm-shipped-five-new-ways-for-it-to-go-silent`
(a missing, corrupt or FUTURE-dated rate-limit marker must fail toward EMITTING, never toward silence); `2026-07-16-a-mutation-battery-only-covers-what-you-mutate`
and `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect` (mutants proven landed with `cmp`, a positive control
for every absence claim); `2026-07-18-web-1-root-doppler-unit-needs-home-...` (Source 4 delivery is file-delivered, already live);
`2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing` (check what feeds
`triggers_replace`: here both the script file hash and `local.zot_probe_repo`).

**Measured baselines (2026-10-11, read-only API/warehouse reads, no SSH):**

- Heartbeats: `soleur-web-zot-consumer-web-1` id 473113 `up`/`paused=false`; `-web-2` id 475781 same.
- Canary rows (Source 4 alive): 12 rows per 6 h per host; web-1 reports `host_name=soleur-web-platform`, web-2 `soleur-web-2`.
- `.github/workflows/apply-web-platform-infra.yml` is 455,470 B against its 490,000 B cap (not a constraint here).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` models the web user_data against a 24,100 B gzip budget (cap 32,768 B);
  `zot_probe_repo` is a bare reference scored at the default reference length (80 B) which already exceeds the new 62-character value.

## Hypotheses

Triggered by the network-outage checklist (the apply step is an SSH provisioner over a tunnel bridge; the red run reports
`i/o timeout`). L3 is verified before any service-layer hypothesis, per `hr-ssh-diagnosis-verify-firewall`.

| Layer | Verified? | Evidence (2026-10-11) |
|---|---|---|
| L3 firewall allow-list | verified | Hetzner API (read-only token): firewall `soleur-web-platform` is applied to servers 123931471 (web-1, 135.181.45.178) and 169271252 (web-2, 204.168.189.200); tcp/22 is allowed only from seven admin /32 addresses and no GitHub-runner range. A direct runner-to-host connection therefore cannot work; only the CF-tunnel bridge can |
| L3 routing / bridge scope | verified | `.github/actions/cf-tunnel-ssh-bridge/action.yml` installs `iptables -t nat -A OUTPUT -d "$SERVER_IP" -p tcp --dport 22 ... REDIRECT` for ONE address (web-1). `terraform_data.egress_gateway_web2` connects to `hcloud_server.web["web-2"].ipv4_address` with no redirect, so its `i/o timeout` is the firewall working as designed — not an sshd or fail2ban fault |
| DNS | not applicable | Every connection uses an IP literal from `hcloud_server.web[...].ipv4_address`; no hostname is resolved |
| L7 TLS / proxy | not applicable | No HTTPS path; the probe talks plain HTTP to `10.0.1.30:5000` on the private NIC |
| L7 application | deliberately not inspected | No host journal read (no SSH, `hr-no-ssh-fallback-in-runbooks`). A layer above has already dropped the packet, so service-layer hypotheses are not entertained |

Consequence: the post-bridge apply step is RED on web-2 independent of this change, while web-1 resources (including
`terraform_data.zot_consumer_probe_install`) are reachable through the bridge and run concurrently in the same Terraform apply.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "extend the host-side web-zot-consumer probe so it covers BOTH platform repos including the `soleur-inngest-bootstrap` repo, making apps/web-platform/infra/zot-entry-gate.sh redundant" [brief] | AC1-AC5, Phase 2, Phase 3 | mapped |
| 2 | "make the probe accept a comma-separated list, classify per repo with a worst-of / all-must-pass heartbeat rule, keep a single heartbeat per host (do not add a new heartbeat resource unless justified)" [brief] | AC1-AC3, Cut List row 1 (justification recorded) | mapped |
| 3 | "wire the second repo through web-probe.tf and whatever renders /etc/default/web-zot-consumer-probe (find it; likely cloud-init / a provisioner)" [brief] | AC5, AC6, Phase 3, `## Infrastructure (IaC)` (three writers enumerated) | mapped |
| 4 | "Verification is from telemetry only (Better Stack heartbeat + marker rows), NEVER SSH diagnosis; the plan must state how \"green on a real run\" is observed (heartbeat state and a per-repo marker line) and what the Step B gate is" [brief] | AC4, AC12-AC14, Phase 7 recipe, `## Observability`, `## Step B follow-up` | mapped |
| 5 | "Step B (explicitly NOT in this PR; list as follow-up in the plan)" [brief] | `## Step B follow-up` | mapped |
| 6 | "strictly sequential — never two infra applies in flight" [brief] | Phase 0.2, Phase 6.1 | mapped |
| 7 | "`Ref` (not `Closes`) for follow-through-labelled trackers" and "this PR uses `Ref #7258`" [brief] | Overview, AC11 | mapped |
| 8 | "rebase, never merge main into the branch (rename-guard fails on merge commits)" [brief] | Phase 0.1, Phase 6.2 | mapped |
| 9 | "`BASELINE_DECLARED_PROBES` ... must be bumped in the same PR with a ledger entry" [brief] | AC7, Phase 4 | mapped |
| 10 | "new tests must not use a pipe into `grep -q` (guard #9217, .claude/hooks/grep-q-pipe-guard.test.sh); before enqueue run the repo's .claude/hooks/*.test.sh guards" [brief] | Phase 1 test rules, Phase 5 | mapped |
| 11 | "any registry-replace-preflight needs `doppler run -p soleur -c prd_terraform` with output redirected to a file" [brief] | Not applicable: this change fires no registry replace (evidence in `## Infrastructure (IaC)` trigger table). If the work phase finds otherwise it must use that exact form (Phase 0.5) | mapped (conditional) |
| 12 | "the plan needs the `## User-Brand Impact`, `## Observability` (with a discoverability_test), and domain-review sections" [brief] | Those sections below | mapped |
| 13 | "determine, from the apply workflow and web-probe.tf, exactly which apply path a change to these files fires (and whether it can replace any host — it must NOT replace web-1; state the evidence)" [brief] | `## Infrastructure (IaC)` Apply path + trigger table | mapped |
| 14 | "Operator decision recorded 2026-10-10: \"Go: probe PR, then delete\"" [brief] | Overview (Step A only), `## Step B follow-up` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web-zot-consumer-probe.sh` list parsing + aggregation | asks 1-2: "make the probe accept a comma-separated list, classify per repo with a worst-of / all-must-pass heartbeat rule" | asked |
| `web-zot-consumer-probe.test.sh` additions | asks 1-2, ask 10 | asked |
| `web-probe.tf` locals | ask 3: "wire the second repo through web-probe.tf" | asked |
| Per-repo marker line (rate-limited) | ask 4: "heartbeat state and a per-repo marker line" | asked |
| `preflight-discoverability-test.test.ts` baseline bump | ask 9 | asked |
| Step B gate criteria + read recipe (no committed script) | ask 4: "what the Step B gate is" | asked |
| `model.c4` edge prose edit | — | inferred — justification: the `hetzner -> zotRegistry` consumer-probe edge states the probe pings "only on a 200" for `<repo>`; that sentence is false after this change and recorded architecture must not lag it (plan Phase 2.10) |
| `decision-challenges.md`, `tasks.md` under the spec directory | — | inferred — justification: required pipeline artifacts (ADR-084 headless channel for the CTO's report-only suggestion; plan Save-Tasks step) |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `plugins/soleur`, `knowledge-base`
- Planned files: 8 (code/test 5: probe, probe test, web-probe.tf, discoverability test, model.c4; KB 3: this plan, tasks, decision-challenges) | Estimated changed lines: ~420 (probe ~90, probe test ~230, web-probe.tf ~20, one-line edits ~15, model.c4 1)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `web-zot-consumer-probe.sh` accepts `ZOT_PROBE_REPO` as a comma-separated list. For a single-element value, the ping decision, exit code and every pre-existing fault-line prefix are unchanged: the existing suite rows (a)-(h) and the canary rows pass UNCHANGED. (The new per-repo marker line is additional output, not a change to those.)
- [ ] AC2. With two repos, the heartbeat ping is logged iff both classify `200`; any other combination (`200,404`, `404,200`, `200,000`, `200,503`, `200,<unexpected>`) logs NO ping; a `401` on either position exits 3 with no ping; the OTHER repo's line is still emitted; every fault line contains `repo=<path>` and keeps its pre-change prefix.
- [ ] AC3. A list with no non-empty element (`,,`) exits 1 (FATAL) with no ping and no marker; a trailing comma with all other elements `200` still pings; an element containing whitespace exits 1 (FATAL), never builds a URL from it.
- [ ] AC4. A marker line `SOLEUR_ZOT_PROBE_REPO repo=<path> code=<n> verdict=<v> ts=<epoch>` is emitted once per repo per rate-limit window (1800 s) regardless of verdict (including the 401 path, before the exit), and a missing, empty, non-numeric or FUTURE-dated marker file causes an emit (never silence).
- [ ] AC5. `web-probe.tf` derives `local.zot_probe_repo` as the comma join of the image-derived web repo and a `locals` constant for the bootstrap repo; `variables.tf` and `server.tf` are byte-unchanged (`git diff --stat origin/main -- apps/web-platform/infra/variables.tf apps/web-platform/infra/server.tf` is empty).
- [ ] AC6. A static test asserts the bootstrap-repo constant equals the repository path component of the `ZIREF` pins in `cloud-init.yml` AND `cloud-init-inngest.yml` (derived from those files with a non-empty assertion, not restated) and that the join is exactly the two-element set.
- [ ] AC7. `BASELINE_DECLARED_PROBES` is bumped by exactly one over the value re-read at work time (55 -> 56 on today's main) with a dated ledger comment naming this plan.
- [ ] AC8. The `model.c4` consumer-probe edge describes the all-repos rule; `plugins/soleur/test/c4-count-parity.test.sh` and `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] AC9. The Guard 1 and Guard 2 mutation batteries were executed on sandbox copies with each mutant proven landed by `cmp`; a results table is in the PR body.
- [ ] AC10. `terraform fmt -check`/`terraform validate` pass; `terraform-target-parity.test.ts`, `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh`, `cloud-init-user-data-size.test.ts`, `journald-config.test.sh`, `web-ghcr-deny.test.sh`, `cloud-init-web-zot-seed.test.sh` and every `.claude/hooks/*.test.sh` pass locally; no new test pipes into `grep -q`.
- [ ] AC11. PR body: `Ref #7258` (no close keyword), the apply-path evidence table, the web-2 limitation statement, the red-apply-stage note (Decision D5), and the post-merge observation recipe.

### Post-merge (agent-observed, telemetry only; none is an operator checklist)

- [ ] AC12. The push apply run for the merge commit shows `terraform_data.zot_consumer_probe_install: Creation complete` in its log (read with `gh run view --log`, bounded), regardless of the job's overall colour. Its log timestamp is the delivery anchor T0.
- [ ] AC13. Once at least two distinct 30-minute buckets (`floor(ts/1800)`) of marker rows exist after T0 (about 40 minutes): both repos report `code=200 verdict=servable` in each bucket for `host_name=soleur-web-platform`; zero `SUPPRESS ping` / `HARD FAILURE` rows from `web-zot-consumer-probe` on that host since T0, read with the canary positive control alive in the same window; `soleur-web-zot-consumer-web-1` is `up`/`paused=false` with zero incidents since T0.
- [ ] AC14. The recipe's output is posted as a comment on #7258 (the Step B gate record).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Keep the single heartbeat with all-must-pass; no masking path exists (the original repo still gates the ping). Main risk is a false page whose cause reads "zot consumer down" when only the bootstrap repo is faulty; mitigated by per-repo fault lines and the first run being the proof. Confirmed: comma list is safe in the printf and cloud-init writers; empties must fail closed (applied: AC3); 401 must not early-exit so the second repo's line still logs (applied: loop then aggregate); delivery lands concurrently despite the red web-2 stage; web-2 skew is bounded by the host-scripts coherence preflight. Recommendations applied: matrix of A200+B404 / A404+B200 / A401+B200 / both 200 (Test Scenarios T1-T4); existence evidence before merge (Phase 0.3); the Step B recipe anchors on post-delivery rows, checks `HARD FAILURE` (exit 3) rows, and states web-1-only coverage. Recommendation NOT applied (taste, operator direction is the default): ship the bootstrap repo report-only for the first observation window — recorded in `decision-challenges.md`.

Other domains: no cross-domain implications. Product/UX: none (no user-facing surface, no file under a UI path). Legal/GDPR: the marker and fault lines carry repository paths, HTTP codes and epoch timestamps only; no personal data, no new processing activity, no distribution surface (Phase 2.7 triggers (a)-(d) all absent).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is operator-facing: the `soleur-web-zot-consumer-web-1` heartbeat goes absent (an email alert) because the bootstrap repo is unservable to the host's pull credential, or because a logic defect suppresses the ping. No request path, session or workspace is touched.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector is added. The pull credential continues to travel only on curl's stdin config (never argv), the new per-repo lines carry repository paths and HTTP codes only, and the existing refuse-to-trace guard and `_cfg_ok` credential-shape check are retained unchanged.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` rather than `aggregate pattern` because the change is detection-only: it adds a check and an alarm input, and removes nothing a user-facing path depends on; the fresh-boot failure it detects exists independently of this change.

`threshold: none, reason: this change adds a host-side detection check and its test/telemetry only; it touches no user data, no request path and no credential handling beyond reusing the existing stdin-config channel, so a defect can at worst mis-page the operator.`

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat soleur-web-zot-consumer-web-1 (id 473113), pinged by the probe only when EVERY repository in ZOT_PROBE_REPO is HTTP 200; plus per-repo SOLEUR_ZOT_PROBE_REPO marker rows and the existing SOLEUR_PROBE_CANARY positive control; a missing ping IS the alert
  cadence: 60 s timer; heartbeat period 180 s with 60 s grace; marker rows at most once per 30 min
  alert_target: Better Stack heartbeat email escalation (betterstack_paid_tier stays false)
  configured_in: apps/web-platform/infra/web-probe.tf (betteruptime_heartbeat.web_zot_consumer, local.zot_probe_repo) and apps/web-platform/infra/web-zot-consumer-probe.sh
error_reporting:
  destination: journald SyslogIdentifier=web-zot-consumer-probe, shipped by Vector Source 4 (host_scripts_journald allowlist) to Better Stack Logs
  fail_loud: a 401 on any repo exits 3 (unit failed) and logs HARD FAILURE with repo=<path>; every other fault logs a SUPPRESS line with repo=<path> on every faulting run; an empty or whitespace list exits 1 with FATAL
failure_modes:
  - mode: bootstrap repo unservable to the host pull credential (404 empty/detached, 401 auth, 000 unreachable, 5xx wedged)
    detection: Better Stack Logs layer (vector journald Source 4) fault line naming repo=jikig-ai/soleur-inngest-bootstrap with the code, and the heartbeat goes absent
    alert_route: Better Stack heartbeat email on absence; the fault line is read with scripts/betterstack-query.sh
  - mode: aggregation defect masks a faulting repo (any-of, first-only, 401 demoted)
    detection: CI layer, web-zot-consumer-probe.test.sh rows T1-T4 plus the mutation battery in the Guard Contract
    alert_route: required CI check red on the PR
  - mode: Source 4 / vector dead so fault and marker lines never leave the host
    detection: Better Stack Logs layer, SOLEUR_PROBE_CANARY absence (existing positive control, emitted outside the doppler wrapper); the Step B recipe treats an absent canary as not-gradable
    alert_route: existing canary absence assertions; the recipe's output on #7258
  - mode: rate-limit marker file lost, corrupt or future-dated
    detection: the probe emits MORE (fail toward emitting); asserted in test T9
    alert_route: CI layer (suite), no runtime alert needed because the failure direction is louder
  - mode: delivery to web-1 does not land (post-bridge apply step red or skipped)
    detection: workflow run log layer, the apply run log line for terraform_data.zot_consumer_probe_install, and marker-row absence 15 minutes after it
    alert_route: existing notify-apply-failure ops email; AC12 fails the post-merge observation
  - mode: new env list reaches an old probe script on a fresh host (skew)
    detection: Better Stack Logs layer, a 404 or unexpected-code fault line whose repo= value contains a comma; prevented upstream by the host-scripts coherence preflight on the host create and replace jobs
    alert_route: heartbeat email on absence for that host
logs:
  where: Better Stack Logs (source shared with the web hosts; host_name soleur-web-platform for web-1, soleur-web-2 for web-2), journald on the host (not read)
  retention: Better Stack warehouse retention (archive arm included by scripts/betterstack-query.sh mode 2 unless --no-archive)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_PROBE_REPO --limit 5
  expected_output: SOLEUR_ZOT_PROBE_REPO
  credentials_required: BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD via Doppler soleur/prd_terraform — the Logs warehouse read connection is credential-gated; the property (per-repo marker rows from web-1) lands only in that warehouse, which has no unauthenticated read path
```

Affected-surface note (plan 2.9.2, blind surface): web-1 is a no-SSH host. The in-surface probe is the probe's own output: ONE marker row carries `repo`, `code` and `verdict` per repository, which discriminates the competing hypotheses in a single event (repo healthy / repo empty / auth broken / path down / zot wedged / list mangled) — a single boolean could not.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Routing is already IaC: web-1's probe is delivered by `terraform_data.zot_consumer_probe_install` and fresh hosts by cloud-init plus the baked env-writer. Nothing is installed or edited by hand. Reviewed by `soleur:engineering:infra:terraform-architect` (read-only apply-path verification, 2026-10-11); its answers are folded into the tables below.

### Terraform changes

- `apps/web-platform/infra/web-probe.tf` — `locals` only: keep `zot_probe_repo_web = regex("^[^:@]+", replace(var.image_name, "ghcr.io/", ""))`, add `zot_probe_repo_inngest_bootstrap = "jikig-ai/soleur-inngest-bootstrap"` (comment cites the `ZIREF` pins it must equal), and `zot_probe_repo = join(",", [local.zot_probe_repo_web, local.zot_probe_repo_inngest_bootstrap])`. The local KEEPS its name so every consumer is unchanged.
- No new provider, no new sensitive variable, no new `TF_VAR_*`, no Doppler change. `variables.tf`, `server.tf`, `cloud-init.yml`, `web-probe-envwrite.sh` are not edited (the value is comma-safe in all three writers: the SSH `printf '...%s...' '${local.zot_probe_repo}'`, the cloud-init single-quoted `SOLEUR_ZOT_PROBE_REPO='${zot_probe_repo}'`, and the env-writer's `printf ... ZOT_PROBE_REPO=%s`; a comma needs no quoting in a systemd EnvironmentFile).

Consumers of the changed values (verified by grep of every `*.tf`, `*.yml`, `*.sh` under `apps/web-platform/infra/`):

| Consumer | What changes | Executed by |
|---|---|---|
| `terraform_data.zot_consumer_probe_install` `triggers_replace` (hashes the script file AND `local.zot_probe_repo`) | hash changes -> destroy+create (no `when = destroy` provisioner anywhere in the root) -> the three file provisioners and the env-writing remote-exec re-run against web-1 | push `apply` job, post-bridge step `Terraform apply (SSH-provisioned resources, over the bridge)`, `-target=terraform_data.zot_consumer_probe_install` |
| that resource's env-file `printf` | writes `ZOT_PROBE_REPO=<web>,<bootstrap>` | same |
| `hcloud_server.web[*]` `user_data` templatefile (`zot_probe_repo`, `host_scripts_content_hash`) | rendered value changes | NOT applied: `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }` |
| `local.host_script_files` -> `host_scripts_content_hash` | changes (the probe script is in the baked set) | consumed only by `user_data` and by the coherence preflight of the host create/replace dispatches |
| `apps/web-platform/Dockerfile` bakes the script | image content changes | normal `web-platform-release.yml` build (fires on `apps/web-platform/**`) |

### Apply path

Chosen: **(c)-class, already-sanctioned** — the existing SSH-provisioned `terraform_data` resource for web-1 (a state-entry swap of the `terraform_data`, never of the server), plus cloud-init/env-writer for hosts born later. A server `-replace` is not viable and is not needed: web-1 is the cx33 host that cannot be re-ordered in hel1 and `web_host_replace` refuses web-1 by construction (the manifest rationale `exempt_reason` for `web_zot_consumer`).

- Trigger: push to `main` touching `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml`, job `apply` (environment `infra-privileged`). Two Terraform steps run: the saved-plan scoped apply (its `-target` list already contains `betteruptime_heartbeat.web_zot_consumer` and `doppler_secret.web_zot_consumer_url`; both are unchanged, so no diff), guarded by destroy-guard counters (`destroy_count`, `host_creates`, `reboot_updates`, `luks_passphrase_rotations`); then the bridge and the post-bridge apply where `terraform_data.zot_consumer_probe_install` lives. That second step carries no destroy-guard by design (documented in the workflow: pure `terraform_data` state swaps).
- Does it replace or update any host, volume, or network attachment? **No.** Evidence: (1) `hcloud_server.web` has `ignore_changes = [user_data, ...]`, and both changed values reach the server only through `user_data` (`server.tf` templatefile map); (2) no volume, attachment or network resource consumes `local.zot_probe_repo` or the script hash (grep, terraform-architect confirmation); (3) the saved-plan step's destroy-guard would halt on any `hcloud_server` update or create. If backend credentials work, the work phase may additionally run a read-only scoped `terraform plan` (output to a file) and confirm no `hcloud_*` actions; this is opportunistic, not a gate.
- Blast radius / downtime: none for serving traffic. The probe unit is a oneshot timer; the script file is replaced on disk and the next 60 s tick runs the new code. Worst-case run time is 2 x 10 s curl timeouts (20 s) against a 60 s cadence.
- Other workflows the merge fires (path-filter evaluation): `infra-validation.yml`, `validate-vector-config.yml` (`apps/web-platform/infra/*.sh`), `web-platform-release.yml` (`apps/web-platform/**`: a normal image build and canary deploy that bakes the new script), `version-bump-and-release.yml` (the `plugins/soleur/**` test file), plus the unfiltered push workflows. Does NOT fire: `registry-host-replace-dispatch.yml` (needs `variables.tf`, `cloud-init-registry.yml` or `zot-registry.tf`), `mint-inngest-bootstrap-tag.yml` (`inngest*`, `vector.*`, `cat-inngest-*` globs match none of the files), `apply-deploy-pipeline-fix.yml` (needs `server.tf` or its trigger files). So exactly ONE infra apply runs on merge.
- web-2: gets the new env value only at its next replace (its env file is written by cloud-init at first boot; `deploy_pipeline_fix_web2` does not carry the probe). Until then web-2 keeps the old single-repo script AND the old single-repo value, which are consistent with each other (P4). New-env-with-old-script skew on a future born host is blocked by `host-image-coherence-preflight.sh` (the probe script is inside `host_scripts_content_hash`) and re-verified by cloud-init at boot.
- Sequencing: no other infra apply may be in flight (Phase 0.2, Phase 6.1); after merge, no `web-host-create`/`web-host-replace` dispatch until the `web-platform-release` for this merge has deployed (the baked-script hash must match the pinned image).

### Distinctness / drift safeguards

- `dev != prd`: not applicable (no Doppler config or TF variable change).
- `lifecycle.ignore_changes` callouts: `hcloud_server.web` (above, load-bearing for the no-replace claim) and `betteruptime_heartbeat.web_zot_consumer` `ignore_changes = [paused]` (unchanged; the ARM gate's op/state-gate sees the heartbeat already `up` and no-ops).
- State: no secret values added to state; the web_probes token is already hashed with `nonsensitive(sha256(...))` in the same `triggers_replace`.
- Pre-existing, unrelated drift: issue #9920 (drift) reports a pending `hcloud_server.inngest` replace from the bootstrap pin bump; that is the separately gated `inngest-host-replace` dispatch and is outside every `-target` set this change touches.

### Vendor-tier reality check

No new Better Stack resource: free-tier heartbeat limits are not approached. Log volume: +2 marker rows per 30 min per host (about 96 rows/day), against ~47 canary rows/day today; the existing ingest-quota work (#7577) is unaffected.

Encryption posture: not applicable — no persistent store and no new cross-component connection (same endpoint, same credential, same plain-HTTP private-NIC leg as today).

## Encryption Posture

No persistent data store and no new cross-component or network connection is introduced. The probe's existing leg (web host to the registry over the private NIC, plain HTTP, Basic auth read from curl's stdin config) is unchanged: same endpoint, same credential, one additional request path on it. It is therefore not re-declared here; the registry store and transport postures remain governed by ADR-096, ADR-140 and the encryption-posture ledger.

## Architecture Decision (ADR/C4)

No new ADR: this extends an existing probe inside the existing substrate and ADR-096/ADR-117 decisions (no new trust boundary, no new store, no new heartbeat, no reversal). ADR-096's "pre-flip zot-entry-gate/soak-gate ... (**superseded:**" sentence already records `zot-entry-gate` as superseded.

### C4 views

One in-scope task: edit the `hetzner -> zotRegistry` consumer-probe edge description in `knowledge-base/engineering/architecture/diagrams/model.c4` (currently "GETs /v2/<repo>/tags/list ... pings the per-host web_zot_consumer heartbeat only on a 200") to say the probe GETs the tag list of EACH platform repository (web platform and inngest bootstrap) and pings only when all are 200. Completeness check performed across `model.c4`, `views.c4` and `spec.c4` for the feature's actors, systems and relationships: external systems are `hetzner` (web host), `zotRegistry` and `betterstack` — all already modeled, and the `zotRegistry -> betterstack` log edge already covers the new marker rows; no new human actor, no new external system, no new data store, no access-relationship change; no element or `view ... include` line is added, so derived cardinalities do not move. Evidence step: run `plugins/soleur/test/c4-count-parity.test.sh` plus `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` after the edit.

## Guard Contract

### Guard 1 — all-must-pass aggregation in the probe

**Property.** The heartbeat ping is emitted if and only if every non-empty element of `ZOT_PROBE_REPO` classified HTTP 200 in this run, and a 401 on any element exits 3 with no ping.

**Assembly.** One chokepoint: the aggregation block after the per-repo loop in `web-zot-consumer-probe.sh` — the only call site of `_ping` (verified by grep before editing: one definition, one call). The members that must flow through it: the per-repo `case "$CODE"` classification (200, 401, 404, 000, 5xx, catch-all), the `unservable` and `auth_broke` accumulators, the list splitter (`IFS=','`), the `probed` counter with its empty-list and whitespace gates, the status-override seam parser (positional, over non-empty elements in order), and the marker emitter that runs before the exit (including on the 401 path). Writers of the input (SSH `printf`, cloud-init single-quoted assignment, `web-probe-envwrite.sh`) are covered by Guard 2. A second `_ping` call site or a second classification table would make this guard incomplete and must be added to the matrix.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Aggregate any-of (ping if at least one repo is 200) | RED: T2/T3 (`200,404`, `404,200`) log a ping |
| 2 | Loop probes only the first repo (`_REPOS[0]`/early `break`) after a compliant first member | RED: T2 expects no ping and the bootstrap repo named in a SUPPRESS line |
| 3 | Demote 401 to suppress (exit 0) | RED: T4 expects exit 3 for `200,401` and `401,200` |
| 4 | Remove the `probed -eq 0` empty-list gate | RED: T6 (`,,`) expects exit 1, no ping, no marker |
| 5 | Guard's own dispatch: break the splitter so `_REPOS` is empty (or delete the `_ping` call) | RED: T1 (`200,200`) asserts the ping log is NON-empty and that the marker names both repos, so "0 repos checked, exit 0" cannot pass |
| 6 | Treat an unlisted override position as 200 instead of 000 | RED: T5 (a positional list shorter than the repo list) expects no ping |
| 7 | Remove the marker call on the 401 path, or accept a future-dated marker as fresh | RED: T4 asserts markers on the 401 run; T9 asserts a numeric-future marker file still emits |

**Harness rows.** (H1) Neuter the suite helper so it ignores the injected code list (`run_override_multi` passing no override): the T2-T4 rows must go RED because their assertions require the per-repo codes to appear in the emitted marker lines (`code=404` present) and because they run against `ZOT_ENDPOINT=127.0.0.1:1` (no real registry, no 10 s hang) — verified by editing the helper in a sandbox copy of the suite. (H2) Must-PASS non-canonical input: a trailing-comma `a/web,b/boot,` with `200,200` (the contract explicitly permits it), differing from the canonical two-element input; a guard that rejects everything fails it.

**Anchor.** Not applicable as a stored-value comparison: the guard compares live HTTP codes against the classification table in the same file; there is no stored hash or count floor. The classification-table anchor is the pre-existing suite rows (a)-(h), which must pass unchanged (AC1).

### Guard 2 — probed repo list equals the repos the hosts actually pull

**Property.** The repository list the probe is given is exactly {the repo derived from `var.image_name`, the bootstrap repo path hosts pull at boot}.

**Assembly.** Chokepoint: `local.zot_probe_repo` in `web-probe.tf`, the single value flowing to `server.tf` (`triggers_replace` and the env-file `printf`) and to `cloud-init.yml` (`zot_probe_repo` templatefile var -> `SOLEUR_ZOT_PROBE_REPO` -> `web-probe-envwrite.sh` -> `ZOT_PROBE_REPO=`). The pull-side referents are the `ZIREF="$VAR/jikig-ai/soleur-inngest-bootstrap:..."` pins in `cloud-init.yml` and `cloud-init-inngest.yml`. T7 names those anchors (the `ZIREF=` lines and `local.zot_probe_repo`) so the check reads the real files.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Typo the bootstrap constant in `web-probe.tf` | RED: derived-from-pin comparison fails |
| 2 | Drop the `join` (list becomes the web repo only), or add a third element after the compliant two | RED: exact two-element set equality (not a floor) fails |
| 3 | Own dispatch: change the pin format so the extraction regex matches nothing | RED: the test asserts the extracted path is NON-empty before comparing, so it cannot pass vacuously |

**Harness rows.** (H3) Edit the suite so the pin-extraction helper returns the constant itself (a self-comparison): row 3's non-empty-and-independent-source assertion must fail. Must-PASS non-canonical input: run the comparison helper against a synthetic fixture file whose pin path is a different but consistent repo name and assert PASS.

**Anchor.** The pins are referents that change through the inngest bootstrap mint workflow and review, independent of this probe change; the test derives the expected path FROM the pins, so an edit to only the constant fails, and an edit to only the pins fails. One diff that edits both is possible and is then a deliberate change of what hosts pull.

## Implementation Phases

### Phase 0 — Preconditions (read-only; at work start and again immediately before enqueue)

1. Rebase on `origin/main` (`git fetch origin main && git rebase origin/main`); never merge main into the branch (the rename-guard fails on merge commits). Re-read `BASELINE_DECLARED_PROBES` after the rebase.
2. Sequencing: `gh run list` shows no `in_progress` run of `apply-web-platform-infra.yml`, `registry-host-replace-dispatch.yml`, `apply-deploy-pipeline-fix.yml`, `web-platform-release.yml`, `inngest-host-replace`-class dispatches. Strictly sequential — never two infra applies in flight.
3. Existence evidence (telemetry, bounded): `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 12h --grep 'repository:jikig-ai/soleur-inngest-bootstrap' --limit 5 > "$SCRATCH/zot-repo.jsonl"` — expect rows (the registry host was replaced 2026-10-11 03:05Z with its store preserved; zot logs retention for that repository). Record in the PR body.
4. Baselines for the PR body: heartbeat ids 473113 and 475781 `up`/`paused=false`; canary row counts per host; current apply-stage health (`gh run list --workflow apply-web-platform-infra.yml --limit 10`). If the web-2 step is still failing, apply Decision D5 and re-confirm its concurrency evidence on the latest red run (a web-1 `terraform_data` with `Creation complete` in the same run as the web-2 timeout).
5. Registry-side preflights, if the work phase finds any is needed (none is expected): `doppler run -p soleur -c prd_terraform -- <cmd> > "$SCRATCH/preflight.out" 2>&1`, output to a file.

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

Extend `apps/web-platform/infra/web-zot-consumer-probe.test.sh` (no new suite file; no `grep -q` after a pipe — use file arguments or here-strings, as the suite already does). Add a `run_override_multi <repos> <codes>` helper and rows T1-T9 (Test Scenarios). EVERY helper, new and existing (`run_override`, `run_probe`, `run_stub`, `run_canary`, `run_override_multi`), must export a per-run temp `SOLEUR_PROBE_REPOS_MARKER` (and keep the canary marker seam) so a root CI runner never shares `/run` state between rows. Run the suite: the new rows fail before the probe is changed.

### Phase 2 — Probe (`web-zot-consumer-probe.sh`)

- Parse `REPO` with `IFS=',' read -r -a`; skip empty elements; an element containing whitespace is FATAL exit 1; count `probed`; FATAL exit 1 when it is zero (before any curl, ping or marker). Keep the existing unset-`REPO` FATAL.
- Per repo, keep the curl line byte-identical to today except `${r}` for `${REPO}` (the suite's sed mutants (b) and (c) key on its text), and keep the `000000` normalization inside the loop.
- Keep per-repo fault lines with their existing prefixes, appending `repo=<path>` where the text did not already name it. No early exit inside the loop: a 401 sets `auth_broke`, other faults set `unservable`, so every repo's line is emitted.
- Extract the window check from `_canary` into one helper `_window_open <marker-file>` (true when the file is missing, empty, non-numeric, in the future, or older than 1800 s) and call it from both `_canary` (existing marker, unchanged behaviour) and the new `_repo_markers` (`SOLEUR_PROBE_REPOS_MARKER`, default `/run/web-zot-consumer-probe.repos`). The canary rows (existing suite) must pass unchanged. One deliberate behaviour change: the current `_canary` treats a numeric FUTURE-dated marker as fresh (`now - last` is negative, so it never emits), a latent silent-canary defect; the shared helper emits in that case, which fixes the canary as well and is asserted once in T9.
- After the loop: emit the markers (`SOLEUR_ZOT_PROBE_REPO repo= code= verdict= ts=`, one per repo, any verdict), then aggregate: any 401 -> exit 3; else any fault -> exit 0 without ping; else `_ping` and the VERBOSE line, exit 0.
- Seam: `SOLEUR_ZOT_PROBE_STATUS_OVERRIDE` is a positional comma list over the NON-EMPTY elements in order (a single code is the one-repo case; missing positions read `000`).
- `--canary-only` mode and the refuse-to-trace guard are untouched; update the header comment to describe the list contract and the 20 s worst case.

### Phase 3 — Wiring and architecture record

- `web-probe.tf`: the three locals (Terraform Changes). Static parity rows T7 go in the probe suite.
- `model.c4`: the edge description edit (Architecture Decision section).

### Phase 4 — Discoverability baseline

Bump `BASELINE_DECLARED_PROBES` by exactly one in `plugins/soleur/test/preflight-discoverability-test.test.ts` and add a dated ledger comment immediately above it, in the existing format (plan file name, placement, truth statement, no-substitute justification). Run the file's suite.

### Phase 5 — Local verification (bounded output; never the full battery)

1. `shellcheck` on the probe and its suite; `bash apps/web-platform/infra/web-zot-consumer-probe.test.sh`.
2. Guard 1 and Guard 2 mutation batteries on sandbox copies; each mutant diff-verified as landed with `cmp -s` (a green control first); results table into the PR body.
3. Related suites: `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh`, `journald-config.test.sh`, `web-ghcr-deny.test.sh`, `cloud-init-web-zot-seed.test.sh` (confirm it tolerates a comma-valued `zot_probe_repo`), `web-probes-token-rotation.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `plugins/soleur/test/preflight-discoverability-test.test.ts`, `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`.
4. `terraform fmt -check` and `terraform validate`; `python3 scripts/lint-guard-contract.py <this plan>`; `python3 scripts/lint-infra-no-human-steps.py`.
5. Every `.claude/hooks/*.test.sh` guard, including `grep-q-pipe-guard.test.sh` (`for f in .claude/hooks/*.test.sh; do bash "$f" > "$SCRATCH/$(basename "$f").out" 2>&1 || echo "FAIL $f"; done`), before enqueue.

### Phase 6 — Ship

1. Immediately before enqueue repeat Phase 0.2. The merge fires exactly one infra apply (Infrastructure section). Authorization: the operator's recorded decision of 2026-10-10 ("Go: probe PR, then delete") covers the web-1 SSH apply this edit fires.
2. Rebase (never merge main) if the queue demands it; PR body carries `Ref #7258`, the evidence tables, and the recipe below.

### Phase 7 — Post-merge observation recipe (telemetry only; run by the shipping session, which waits with the `Monitor` tool and an until-loop, never a foreground sleep)

R1. Delivery anchor T0: `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 5 --json databaseId,headSha,createdAt,conclusion`, then for the merge commit's run: `gh run view <id> --log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -F 'terraform_data.zot_consumer_probe_install: Creation complete' | head -3` (the log timestamp is T0; AC12).

R2. Marker, fault and control rows (Logs warehouse; decode `.raw | fromjson`, keep rows with `.host_name == "soleur-web-platform"` and `.SYSLOG_IDENTIFIER == "web-zot-consumer-probe"`, text in `.MESSAGE // .message`):
`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 3h --grep SOLEUR_ZOT_PROBE_REPO --limit 200 > "$SCRATCH/m.jsonl"`; the same with `--grep 'SUPPRESS ping' --grep 'HARD FAILURE'` (faults) and `--grep SOLEUR_PROBE_CANARY` (control). Use separate queries with an explicit high `--limit` so a fault flood cannot truncate the marker rows out of one OR query. Grade only rows after T0.

R3. Heartbeat and incidents (credential on curl's stdin config, never argv): look the heartbeat up by NAME `soleur-web-zot-consumer-web-1` in `GET /api/v2/heartbeats?per_page=100` (`status`, `paused`), and `GET /api/v2/incidents?from=<T0 date>&to=<tomorrow>&per_page=100` filtered to that name (zero rows after T0).

Verdicts: AC13 holds -> post the outputs as a comment on #7258 (AC14). A fault row after T0 means the bootstrap repo (or auth) is the problem: the fault line names it; the response is a revert PR (one more sequential apply), not an in-place host edit. No marker row within 15 minutes of T0 means diagnose from the apply run log and the warehouse only (never SSH).

## Decisions

- **D1. One heartbeat, all-must-pass.** A conjunction cannot mask; per-repo lines name the failing repo. Rejected: a second heartbeat (Cut List).
- **D2. `locals`, not a variable.** `variables.tf` is a registry-host-replace trigger path; `server.tf` is a deploy-pipeline-fix trigger path. Keeping the local's name means zero edits to either.
- **D3. Marker, not verbose logging.** A rate-limited per-repo row is the "green on a real run" evidence; `SOLEUR_PROBE_VERBOSE` stays a debug flag. One shared window helper, two marker files.
- **D4. The Step B gate is criteria plus a fixed recipe, not a script.** Two independent reviewers cut the committed gate script, its suite and a sweeper tracker as disproportionate to deleting an uninvoked script; the evidence comment on #7258 is the gate record.
- **D5. The red web-2 apply stage is out of scope and does not block.** Evidence: Hypotheses table, plus a historical red run: push apply run 38097457915 (2026-10-11 00:11Z, concluded failure) shows `terraform_data.egress_gateway: Creation complete after 1m6s` and `terraform_data.cron_egress_firewall: Creation complete after 1m20s` (both web-1 SSH resources) in the same apply as the web-2 timeout, i.e. web-1 resources complete while the web-2 resource fails. File a tracker for the `egress_gateway_web2`/bridge scope defect during the work phase if none exists (none found by search on 2026-10-11; #9956 is a different red). Acceptance never depends on the job's colour.
- **D6. `tags/list` proves the repo is servable, not that the pinned tag survives retention.** The cloud-init-registry retention keeps the 5 most recent `v.*` tags per repo with no carve-out for the boot pin, and the pinned tag could be evicted while the repo still lists 200. Out of scope; tracked as a deferral (below).

## Test Scenarios

Probe suite (`web-zot-consumer-probe.test.sh`, added rows; codes via the positional override seam unless marked behavioural; every helper uses a temp marker path; fault-line assertions filter to `SUPPRESS`/`HARD FAILURE` lines because marker lines name both repos on every run):

- T1. `200,200` -> ping, exit 0, marker rows for BOTH repos, `servable`.
- T2. `200,404` -> no ping, exit 0; a SUPPRESS line names the bootstrap repo and no SUPPRESS line names the web repo.
- T3. `404,200` -> no ping (reversed order); `200,000`, `200,503`, `200,302` (catch-all) -> no ping.
- T4. `200,401` and `401,200` -> exit 3, no ping, the HARD FAILURE line names the right repo, the OTHER repo's line is still emitted, and marker rows exist on the 401 run.
- T5. Positional seam: single repo single code (every pre-existing row unchanged); two repos with override `200` only -> the missing position reads `000`, no ping; `a,,b` with `200,200` -> indices follow non-empty order (both probed, ping).
- T6. `,,` -> exit 1, no ping, no marker; an element with whitespace (`a/b, c/d`) -> exit 1, no URL built, no ping. T6b: `a,b,` with `200,200` -> ping.
- T7. Static (Guard 2): web repo derives from `var.image_name`; the constant equals the pin path in BOTH `cloud-init.yml` and `cloud-init-inngest.yml` (extraction asserted non-empty); the join is exactly the two-element set; no `variable "inngest_bootstrap_repo"` exists.
- T8. Behavioural against the python mock registry extended to serve `known/repo` and `known/second` with auth: both -> ping; `known/repo,nonexistent/repo` and the reverse -> no ping and `EMPTY/DETACHED ... nonexistent/repo`. Stub curl on PATH: invoked once per repo, each argv carries no credential, each stdin is exactly one `user = "..."` line (the (f) assertions generalized).
- T9. Marker: first run emits one line per repo with `repo= code= verdict= ts=`; a second run inside the window emits none; marker file deleted, empty, garbage, or numeric-future -> emits again; the marker is emitted on a faulting run and on a 401 run.
- Existing rows (a)-(h), the canary rows and the `--canary-only` rows pass unchanged (AC1).

## Files to Edit

- `apps/web-platform/infra/web-zot-consumer-probe.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.test.sh`
- `apps/web-platform/infra/web-probe.tf`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (edge prose only)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (baseline +1 and ledger comment)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7258-consumer-probe-covers-inngest-bootstrap/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-7258-consumer-probe-covers-inngest-bootstrap/decision-challenges.md`

NOT touched (hard constraints, verified against the trigger table): `apps/web-platform/infra/variables.tf`, `server.tf`, `cloud-init.yml`, `cloud-init-registry.yml`, `zot-registry.tf`, `web-probe-envwrite.sh`, `web-zot-consumer-probe.service`/`.timer`, `.github/workflows/**`, `scripts/**`, anything matching `apps/web-platform/infra/inngest*`.

## Open Code-Review Overlap

None. Queried 88 open `code-review` issues by path for the probe, its suite, `web-probe.tf`, `model.c4`, the discoverability suite and `zot-entry-gate.sh`: zero matches.

## Non-Goals and tracked deferrals

- Not in this PR: any Step B deletion (see below); fixing `terraform_data.egress_gateway_web2`; web-2 delivery of the list before its replace; a pinned-tag manifest probe (D6); automating the Step B gate as a sweeper script (the first draft of this plan carried one and review cut it; revisit only if the manual recipe is skipped in practice).
- Deferral issue to file during the work phase (`wg-when-deferring-a-capability-create-a`), milestone "Post-MVP / Later" unless `knowledge-base/product/roadmap.md` names a closer phase: "probe the pinned inngest-bootstrap tag manifest and add a retention carve-out for the boot pin" — what: HEAD the pinned tag's manifest, not only `tags/list`; why: retention can evict the pin while the repo lists 200; re-evaluate when the bootstrap pin next changes or a pin-eviction is observed.
- Tracker to file during the work phase if none exists: the push apply's post-bridge step targets `terraform_data.egress_gateway_web2` over a path the bridge does not cover (red since PR #9529).

## Step B follow-up (explicitly NOT in this PR)

Gate: AC13 holds and its recipe output is posted on #7258 (AC14), and `git grep -n zot-entry-gate` is re-censused at that time. Step B is then a pure delete plus two registration rows, accepting that a deletion under `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` and `web-platform-release.yml` (re-state the no-fire proof as "empty plan" at that point):

- Delete `apps/web-platform/infra/zot-entry-gate.sh` and `apps/web-platform/infra/zot-entry-gate.test.sh`.
- Remove the `zot-entry-gate.test.sh` row from `apps/web-platform/infra/suite-shard-legs.tsv` (line 173 today) and from `apps/web-platform/infra/suite-durations.tsv` (line 170 today); then run `plugins/soleur/test/regenerate-shard-manifest.test.sh` and `.github/scripts/test/test-infra-suite-registration.sh`.
- Dangling comment references: `apps/web-platform/infra/ci-deploy.sh` (near line 1410), `.github/workflows/build-inngest-bootstrap-image.yml` (lines 817 and 931), `.github/workflows/reusable-release.yml` (lines 1219 and 1420).
- Fix two stale Slack statements: one in `.github/workflows/build-inngest-bootstrap-image.yml` and one in `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`.
- Historical records (ADR-096, post-mortems, learnings, plans) are left as written. This list is a seed, not the census.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, is filler text only, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it and carries the sensitive-path scope-out bullet.
- The sed mutants (b) and (c) in the existing suite key on the exact text of the probe curl line (`-m 10 --config - "http` and `-s -o /dev/null -w`); moving or reflowing that line silently turns two mutation rows into no-ops. Keep the line shape and re-assert that the strip landed (the suite already does).
- `2>&1` and here-strings only: a `grep -q` after a pipe is rejected by `.claude/hooks/grep-q-pipe-guard.test.sh` (#9217); the existing suite uses file arguments for that reason.
- The marker rate limit lives in `/run` (tmpfs): a reboot resets it, which is intended (emit more, never less). A numeric FUTURE timestamp must also emit; copying `_canary`'s `''|*[!0-9]*` test alone does not cover it.
- `host_name` for web-1 in Better Stack is `soleur-web-platform` (the known hostname mislabel), not `soleur-web-1`; the recipe and the discoverability query must not filter on the latter.
- Do not bump `BASELINE_DECLARED_PROBES` from memory: re-read it after the rebase; another plan may have bumped it.
- Test fixtures are synthesized (`cq-test-fixtures-synthesized-only`); never paste real telemetry rows into a suite.
- A web-host create or replace dispatch before this merge's release has deployed will fail the host-scripts coherence preflight — by design.
- The recipe's bucket arithmetic is `floor(ts/1800)` over the marker `ts=` field, not arrival time: two rows 1800 s apart can share a bucket, so wait for a third marker if needed.
