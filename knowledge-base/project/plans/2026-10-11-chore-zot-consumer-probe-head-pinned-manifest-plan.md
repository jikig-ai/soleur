---
title: "chore(infra): consumer probe should HEAD the pinned manifest, not only list tags"
date: 2026-10-11
slug: zot-consumer-probe-head-pinned-manifest
branch: feat-one-shot-10004-probe-head-pinned-manifest
issue: 10004
closes: 10004
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# chore(infra): consumer probe should HEAD the pinned manifest, not only list tags

Spec lacks a valid `lane:` (no spec.md exists for this branch) — defaulted to cross-domain (TR2 fail-closed).

## Overview

The web-host zot consumer probe (`apps/web-platform/infra/web-zot-consumer-probe.sh`) classifies each repository in `ZOT_PROBE_REPO` by the HTTP code of `/v2/<repo>/tags/list`, and pings the per-host heartbeat only when every repository answers 200. That proves the repository is listable to the pull credential. It does not prove that the tag and digest a fresh host actually pulls (the `ZIREF` pin in `cloud-init.yml` and `cloud-init-inngest.yml`) still resolve to a manifest.

zot retention keeps only the 5 most recent `v.*` tags per repository with `deleteUntagged: true`. When a pin falls out of that window, `tags/list` keeps answering 200 while the pinned digest is gone, so the heartbeat stays green and the next host boot or replace fails at the pull. This was measured on 2026-10-11 (see Research Insights, M1-M6): after eviction `tags/list` is 200 while `HEAD` of the pinned digest and of the evicted tag are both 404.

This change lets a `ZOT_PROBE_REPO` element carry a digest ref (`repo@sha256:<64 hex>`). For an element that carries one and whose tag list answered 200, the probe issues one extra authenticated `HEAD` of that manifest and suppresses the heartbeat ping unless it answers 200. `web-probe.tf` derives the bootstrap repository's digest from the `ZIREF` line it must equal and builds a SECOND list, `local.zot_probe_repo_pinned`, that only web-1's provisioner path (`server.tf`: the `triggers_replace` entry and the env-file `printf`) consumes, so the probe follows each pin bump through the existing delivery to web-1. `local.zot_probe_repo` stays the bare list and keeps feeding the cloud-init template, so a host born later never bakes a pin into an env file that nothing will ever update (see the cattle pin-rot row in Research Reconciliation). The pin is a fleet-wide property of one registry, so checking it from one host is sufficient; every host keeps its own anti-masking heartbeat.

Scope reconciliation (see Research Reconciliation): only `jikig-ai/soleur-inngest-bootstrap` has a committed pin. `jikig-ai/soleur-web-platform` has none (its digest is resolved at host-birth dispatch time and never committed), so its element stays a bare repository and its marker row reports `pin_verdict=none` explicitly. That gap is tracked as #10044.

**PR body must say `Closes #10004`** (this PR delivers the issue for every repository that has a pin; the web gap is #10044, which stays open).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #10004 / operator brief) | Reality (verified 2026-10-11) | Plan response |
|---|---|---|
| Brief: HEAD "the ZIREF tag/digest pins the hosts actually pull, for both jikig-ai/soleur-web-platform and jikig-ai/soleur-inngest-bootstrap" | `ZIREF` exists only for the bootstrap repo (`/usr/bin/grep -a -n 'ZIREF=' apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/cloud-init-inngest.yml` returns one line in each, both naming `soleur-inngest-bootstrap`). The web image has no committed pin: `var.image_name` defaults to `ghcr.io/jikig-ai/soleur-web-platform:latest` and the digest is resolved at dispatch (`PINNED="${IMAGE_REPO}@${DIGEST}"` in `apply-web-platform-infra.yml`, `web_host_create`/`web_host_replace`). `ci-deploy.sh` keeps no deployed-ref state file | Cover the bootstrap pin now; web stays a bare repo with an explicit `pin_verdict=none`; deferral tracked as #10044; recorded as a User-Challenge in `decision-challenges.md` (the stated scope shrinks) |
| Brief: "Editing the probe/web-probe.tf changes the triggers_replace hash and fires a web-1 SSH apply" | True, with a new consequence. Today `local.zot_probe_repo` strips tag and digest, so an inngest pin bump (#10027, run 38151764939) refreshed `terraform_data.zot_consumer_probe_install` without recreating it. Once the pin is part of `local.zot_probe_repo`, every pin bump re-delivers the probe to web-1 | Intended and required for correctness (web-1 ignores `user_data`; delivery is the only way it learns a new pin). Stated in the PR body and the runbook |
| CTO finding (2026-10-11): if the pin lived in `local.zot_probe_repo`, it would also reach the cloud-init template var and be written ONCE at birth into every later host's `/etc/default/web-zot-consumer-probe` (`web-probe-envwrite.sh`); `hcloud_server.web` has `ignore_changes = [user_data, ...]` and web-2 has no probe provisioner twin, so that baked pin would never update, and 5 newer `v.*` tags later its probe would false-red until a replace | Real design flaw in the first draft. Split the locals: `local.zot_probe_repo` (bare, unchanged line) keeps feeding cloud-init; a new `local.zot_probe_repo_pinned` feeds only web-1's two `server.tf` sites. This costs a two-line `server.tf` edit, which also fires `apply-deploy-pipeline-fix.yml` (`server.tf` is in its `paths:`); both workflows share the concurrency group `terraform-apply-web-platform-host`, so they serialize (Infrastructure → Apply path) |
| Brief: "if ci-deploy.sh changes, read the Deploy Pipeline Fix Drift Gate" | The only `ci-deploy.sh` text about the probe (`web-zot-consumer-probe.sh is the layer meant to see it: a 403 on its tags/list read`) stays true: a 403 on `tags/list` still lands in the unexpected-code arm | `ci-deploy.sh` is NOT edited; the gate (trigger files listed in `soleur:ship` "Deploy Pipeline Fix Drift Gate") is not triggered. AC checks the diff stat |
| Brief: pre-existing gap "no tab / user-newline control-character rows" | Confirmed narrower: `unsafe_row` has rows for a double quote (user, token), a backslash (token) and a newline (token). Missing: a newline in the USER, a backslash in the USER, a tab in either credential, and a tab in a `ZOT_PROBE_REPO` element (T6 covers a space) | Close all four in the same PR (Phase 1) |
| Brief: "check guard-vacuity-floor PROMOTED_FILES, the deferral ledger and fixture-relative-assert.baseline.txt" | The suite is ALREADY in `PROMOTED_FILES` (`scripts/guard-vacuity-floor.test.sh`, comment "gained an assertion floor in #7258"); the ledger is the in-script `MAX_DEFERRED` count (shrink-only), not a file; `fixture-relative-assert.baseline.txt` row 212 is `1 apps/web-platform/infra/web-zot-consumer-probe.sh`; the suite has `MIN_ASSERTS=199` and currently runs exactly 199 | No ledger change is needed (promoted as a file, never deferred); raise `MIN_ASSERTS` in the same edit as the new rows; re-run the baseline scanner and regenerate only if its count moves |
| Brief: "Bundle the archive of the leftover Step-B plan/spec" | Both exist unarchived on `origin/main`: `plans/2026-10-11-chore-delete-zot-entry-gate-plan.md` and `specs/feat-one-shot-7258-delete-zot-entry-gate/` (`session-state.md`, `tasks.md`). `archive-kb.sh` takes ONE slug; no single slug matches both (plan glob `*<slug>*`, spec glob `specs/feat-<slug>`) | Two invocations (Phase 7), checked with `--dry-run`, committed as one `chore(archive-kb)` commit |
| #10004: "Re-evaluate when: Step B has merged and the first replace of a web or inngest host has shown whether tag-list coverage was enough, or sooner if a pull fails while the heartbeat is green" | Step B merged (#10016, `76da243c20`, 2026-10-11T15:14Z); #7258 is CLOSED. No replace has happened since | Proceed: the measured retention behavior (M1-M6) shows tag-list coverage is NOT sufficient for an evicted pin |
| Brief: apply stage state ("web-2 step red") from the earlier plan family | Latest push apply runs 38151764939 (#10027) and 38150427433 (#10016) concluded `success`; a web-2 forward fix landed (`fix(infra): port the web-2 SSH forward into apply-web-platform-infra`) | Do not rely on this: observation is telemetry-based, never job-colour-based (Phase 9) |

## Research Insights

**Premise Validation.** #10004 is OPEN (`type/chore`, `meta/machinery`, milestone Post-MVP / Later); no merged PR closes it; PR #10041 is the draft for this branch. #7258 (the parent tracker) is CLOSED by #10016. Cited artifacts exist on `origin/main`: `web-zot-consumer-probe.sh`, `web-probe.tf` (`zot_probe_repo`, `zot_probe_repo_inngest_bootstrap`), `web-probe-envwrite.sh`, the two `ZIREF` pins, `deploy-arm.sh`, `archive-kb.sh`, `scripts/guard-vacuity-floor.test.sh`. The proposed mechanism (a manifest HEAD from the host-side probe) is not in any ADR's rejected-alternatives table: ADR-096's consumer-probe passage ("the correct non-redundant complement ... must not be retired") and ADR-172's inventory (`GET` of manifests from CI over the tunnel) neighbour it but decide nothing about a host-side HEAD. `build-inngest-bootstrap-image.yml` already names the gap in prose ("It does not resolve the PINNED tag's manifest") — that sentence becomes false and is in scope.

**Property List.**

- P1. A pinned manifest evicted, never mirrored or garbage-collected from zot suppresses the per-host heartbeat ping within one probe tick, while `tags/list` still answers 200.
- P2. The fault line names the repository AND the ref, reaches Better Stack Logs without SSH, and keeps the existing `repo=<path>` trailer.
- P3. A healthy run is observable per repository: the marker row says whether a pin was checked and what it answered (`pin_verdict`), including the explicit `none` for the unpinned web repository.
- P4. The ref the probe HEADs is the ref the hosts pull: it is derived from the `ZIREF` line, never restated, and follows every pin bump.
- P5. A host still carrying the single-repo, bare-element env value (web-2 until its next replace) behaves exactly as today.
- P6. No host ever bakes a pin into an env file that nothing re-delivers: only web-1's re-delivered env carries a pin, so no pin can rot on a host that cannot be updated.

**Cut List.**

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| A separate `ZOT_PROBE_PINS` env var (new writer slot in `server.tf`, `cloud-init.yml`, `web-probe-envwrite.sh`) | P4 | The existing list value already flows verbatim through the writers (T7 asserts each); a digest ref inside the element reuses them. The only `server.tf` edit is choosing WHICH local web-1's two sites read; `variables.tf` (a registry-replace trigger path), `cloud-init.yml` and `web-probe-envwrite.sh` stay untouched. Cut |
| A tag (`repo:tag@sha256:...`, `repo:tag`) in the element grammar, and a tag HEAD | tag re-pointing | Docker resolves `tag@digest` by the digest, and M2 shows the digest HEAD already detects the eviction; one ref shape (`repo@sha256:<64 hex>`) is one parser branch and one request shape (CTO: drop). The tag is lost from the fault line; the digest maps to a tag by `grep` of the two `ZIREF` lines |
| Pinning born hosts (web-2 and later) by baking the pin into the cloud-init template var | P1 on those hosts | The baked pin would rot (cattle pin-rot row above); the pin is a registry-wide property, checked from web-1, whose env is re-delivered on every bump |
| A second heartbeat for pins | P1 | A conjunction on the existing heartbeat cannot mask (ping needs every repo AND every pin); a new heartbeat adds a TF resource, a Doppler secret, a manifest row and an ARM-gate arm (ADR-117) |
| `Docker-Content-Digest` header equality check on the HEAD response | P1 | Requesting `manifests/<digest>` and getting 200 already means zot served that digest; the header echo adds no property (M2 shows the header equals the digest requested) |
| `Accept` header on the HEAD | P1 | Measured unnecessary (M3): no Accept, docker v2 Accept, OCI-manifest-only Accept and index+manifest Accept all return 200 for an OCI index digest |
| Host-side derivation of the web ref (`docker inspect` of the running container) | P1 for web | Adds a docker dependency and a container-absent branch (a silent-skip shape) to a probe whose absence is the alarm; deferred to #10044 with re-evaluation criteria |
| Report-only first window for the pin check | false-page risk | Recorded as a decision challenge (the operator direction is all-must-pass); the first real run is the proof (Phase 9) |
| A TF `check` block asserting the two `ZIREF` pins are equal | P4 | The pin-bump drift guard (AC6 of `cloud-init-inngest-bootstrap.test.sh`, over the sites `.github/scripts/bump-inngest-bootstrap-pin.sh` rewrites) and T7 already compare them; a TF-side copy would be a third comparator |
| Editing `ci-deploy.sh`'s probe comment | none | Still true (403 on `tags/list`); not editing keeps the Deploy Pipeline Fix Drift Gate out of scope |

**Measured evidence (2026-10-11, local, pinned zot image `ghcr.io/project-zot/zot-linux-amd64:v2.1.22@sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b`, the repo's `cloud-init-registry.yml` retention policy shape with `gcDelay`/`retention.delay` 1 s and `gcInterval` 10 s, no auth, 7 single-arch images pushed as `x/y:v1..v7`, which zot stored as OCI image indexes).** Commands: `docker run -d -p 127.0.0.1:15000:5000 -v cfg.json:/etc/zot/config.json:ro <image>`, `docker push localhost:15000/x/y:vN`, `curl -s -o /dev/null -w '%{http_code}' -I http://127.0.0.1:15000/v2/x/y/manifests/<ref>`.

| # | Observation | Result |
|---|---|---|
| M1 | After retention ran (zot log `module=retention ... applied policy` for `v1`,`v2`,`v3`; `tags/list` went from 7 tags to `["v3".."v7"]`): `tags/list` of the repository | 200 |
| M2 | Same moment: HEAD of the evicted `v1` DIGEST / of the evicted `v1` TAG / of the kept `v7` tag | 404 / 404 / 200 (HEAD response carries `Docker-Content-Digest` equal to the requested digest and `Content-Type: application/vnd.oci.image.index.v1+json`) |
| M3 | Before eviction, HEAD of an index digest with no Accept / `application/vnd.oci.image.manifest.v1+json` only / `application/vnd.docker.distribution.manifest.v2+json` only / index+manifest | 200 / 200 / 200 / 200 |
| M4 | HEAD of a never-pushed digest (`sha256:000...0`) / of a missing repository | 404 / 404 |
| M5 | GET (not HEAD) of the evicted digest | 404 |
| M6 | Not measured here, deliberately: authenticated behavior (401 before repo lookup) and the manifest-endpoint 403 recorded in `zot-image.provenance.md` claim-register row 1 — both are covered by the same classification table and by the suite's mock server | — |

The work phase re-runs M1-M5 once before writing any sentence that cites them (Prose ledger, below). The container and scratch files were removed after measuring.

**Learnings applied** (`knowledge-base/project/learnings/`): `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire` (classify on `-w '%{http_code}'`, never `-f`; model the stub's flags); `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code` (no `--retry` in a probe whose absence is the alarm; the stub must honour `-f`); `2026-07-16-a-mutation-battery-only-covers-what-you-mutate` and `2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in` (count axes; every new function needs a call in the suite); `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards` (never `producer | grep -q`); `2026-07-01-host-ugrep-vs-ci-gnu-grep-bre-backslash-escapes` (assert literal output with `grep -F`; use `/usr/bin/grep -a` when a must-match grep returns nothing); `2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace` (the web servers carry `ignore_changes = [user_data, ...]`, so a rendered-value change is inert there); `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing` (check what feeds `triggers_replace`); `2026-07-28-the-fix-for-a-too-noisy-alarm-shipped-five-new-ways-for-it-to-go-silent` (a missing or corrupt rate-limit marker fails toward EMITTING).

## Hypotheses

Triggered by the network-outage check (the delivery of this change is an SSH provisioner reached over a tunnel bridge, and the probe's `000` verdict is an unreachable-registry class). L3 first, per `hr-ssh-diagnosis-verify-firewall`. This plan proposes no sshd, fail2ban or service-layer hypothesis.

| Layer | Status | Evidence (2026-10-11) |
|---|---|---|
| L3 firewall allow-list | not re-measured at plan time; the delivery path does not depend on it | web-1 delivery goes through the tunnel bridge (`.github/actions/cf-tunnel-ssh-bridge`), not a direct runner-to-host connection. Today's evidence that the path works: `apply-web-platform-infra.yml` push runs 38151764939 and 38150427433 and dispatch run 38151596067 all concluded `success`, and 38151764939's log shows the post-bridge step targeting `terraform_data.zot_consumer_probe_install`. If a delivery step fails at work or post-merge time, the first action is `hcloud firewall describe` against the host plus the egress-IP diff (runbook `admin-ip-drift.md`), before any other hypothesis |
| L3 routing / DNS | not applicable | every connection uses an IP literal (`hcloud_server.web["web-1"].ipv4_address`); the probe talks to `10.0.1.30:5000` by literal |
| L7 TLS / proxy | not applicable | plain HTTP over the private NIC; no HTTPS path |
| L7 application | deliberately not inspected | no host journal read (no SSH, `hr-no-ssh-fallback-in-runbooks`); every verdict is read from Better Stack Logs |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make the web-1 zot consumer probe (web-zot-consumer-probe.sh / web-probe.tf) HEAD the pinned manifest ... not only list tags, so a tag evicted by the 5-tag retention turns the heartbeat red instead of staying green on a 200 tags/list" [issue #10004, brief] | AC1-AC6, Phases 1-3 | mapped |
| 2 | "for both jikig-ai/soleur-web-platform and jikig-ai/soleur-inngest-bootstrap" [brief] | AC7 (bootstrap pinned; web explicit `pin_verdict=none`), #10044 | descoped for the web repository — justification: no committed pin exists to HEAD (Research Reconciliation row 1); tracked as #10044 with re-evaluation criteria |
| 3 | "Editing the probe/web-probe.tf changes the triggers_replace hash and fires a web-1 SSH apply. Do not land it inside a registry observation window; before queueing, check `gh run list --status in_progress` for any in-flight apply (strictly sequential infra applies)" [brief] | Phase 0.2, Phase 8, AC18 | mapped |
| 4 | "Read the Deploy Pipeline Fix Drift Gate in soleur:ship if ci-deploy.sh changes" [brief] | AC13 (`ci-deploy.sh` byte-unchanged; gate not triggered) | mapped |
| 5 | "Every sentence the PR adds to a comment, ADR or runbook needs its falsifying command run first" [brief] | `## Prose ledger`, AC12 | mapped |
| 6 | "Read the failing STEP before calling any CI red a regression; check whether main is red on the same suite" [brief] | Phase 8 | mapped |
| 7 | "If the probe test is touched, the pre-existing gap (no tab / user-newline control-character rows) may be closed in the same PR" [brief] | AC9, Phase 1 | mapped |
| 8 | "if the suite is edited or deleted check guard-vacuity-floor PROMOTED_FILES, the deferral ledger and fixture-relative-assert.baseline.txt (the ledger only shrinks)" [brief] | AC10, Phase 5 | mapped |
| 9 | "Bundle the archive of the leftover Step-B plan/spec for the zot-entry-gate deletion under knowledge-base/project/ (archive-kb.sh) into this PR if convenient" [brief] | AC14, Phase 7 | mapped |
| 10 | "Rebase, never merge main into the branch; do not push while a PR is queued; draft PRs run draft-light CI whose `test` check reads red, read the run created at ready" [brief] | Phase 0, Phase 8 | mapped |
| 11 | "Hooks: a Bash call containing the words terraform and apply together is deferred, so write such text with the Write tool. grep may be ugrep ... semgrep is broken on this host; shellcheck is the gate (compare findings against origin/main)" [brief] | Sharp Edges, Phase 5 | mapped |
| 12 | "Post-merge: deploy-arm.sh find --wait <full-sha>, then confirm served; one apply per trigger-file change. Never ask the operator to watch CI" [brief] | Phase 9, AC17-AC20 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web-zot-consumer-probe.sh` pin HEAD, ref grammar, marker fields | ask 1: "HEAD the pinned manifest ... not only list tags" | asked |
| `web-probe.tf` derived pin local | ask 1 and ask 3: "web-zot-consumer-probe.sh / web-probe.tf" | asked |
| `server.tf` two-line edit (web-1's two sites read `local.zot_probe_repo_pinned`) | — | inferred — justification: without it the pin would also reach the cloud-init template var and be baked once into every born host's env file, which nothing re-delivers, so it would rot into a permanent false red (CTO finding; Research Reconciliation); it is the minimum edit that confines the pin to the one host whose env is re-delivered |
| `web-zot-consumer-probe.test.sh` rows, mutation battery, `MIN_ASSERTS` | asks 1, 7, 8 | asked |
| Control-character rows (tab, user newline, user backslash, tab element) | ask 7: "no tab / user-newline control-character rows" | asked |
| `model.c4` edge text and regenerated `model.likec4.json` | — | inferred — justification: the `hetzner -> zotRegistry` consumer-probe edge says the probe GETs `tags/list` and pings "only when EVERY repository answers 200"; that is incomplete after this change, and `c4-model-freshness.test.sh` byte-diffs the generated JSON (plan Phase 2.10, recorded architecture must not lag the change) |
| `betterstack-log-query.md` runbook paragraph | — | inferred — justification: the page runbook for `soleur-web-zot-consumer-*` tells the responder how to read faults and markers; a new fault class (`pinned manifest MISSING`) and new marker fields need a reading rule or the next page is diagnosed from stale text |
| `build-inngest-bootstrap-image.yml` comment and step-summary sentence | — | inferred — justification: both say the host probe "never resolves a pinned digest"; false after this change, and the summary is what an operator reads when deciding whether a green run licenses a pin |
| `BASELINE_DECLARED_PROBES` bump in `preflight-discoverability-test.test.ts` | — | inferred — justification: this plan's `discoverability_test` declares `credentials_required` (SKIP-DECLARED), which the baseline counts; omitting the bump reddens that suite |
| Archive of Step-B plan and spec | ask 9: "Bundle the archive of the leftover Step-B plan/spec" | asked |
| `decision-challenges.md`, `tasks.md` under the spec directory | — | inferred — justification: required pipeline artifacts (ADR-084 headless channel for the narrowed web scope; plan Save-Tasks step) |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform` (infra), `plugins/soleur` (one test constant), `.github/workflows` (comment-only), `knowledge-base`
- Planned files: 11 (code/test 5: probe, probe test, `web-probe.tf`, `server.tf` (2 lines), discoverability test; docs/generated 4: `model.c4`, `model.likec4.json`, runbook, workflow comment; archive moves 3 files; KB 3: this plan, tasks, decision-challenges) | Estimated changed lines: ~420 (probe ~90, probe test ~260, `web-probe.tf` ~20, prose ~40, generated JSON ~2 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the subsystem-root count (4) meets the threshold only because two roots are a one-line test constant and a comment-only workflow edit that must move with the behavior they describe; splitting would leave a stale false sentence in `main` between the two merges

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. A `ZOT_PROBE_REPO` element is either `<repo>` or `<repo>@sha256:<64 lowercase hex>` and nothing else. Any other shape (a `:tag` in any position including `repo:tag@sha256:...`, a short or uppercase digest, another hash algorithm, a trailing or empty `@`, extra text after the digest) is FATAL exit 1 with no curl, ping or marker. A bare-element list behaves byte-identically to today: the existing rows (a)-(h), T1-T16 and the canary rows pass UNCHANGED, with ONE deliberate exception — the suite's `has_marker` matcher anchors on `ts=[0-9]+$`, so it gains the appended field (and its strictness rows keep their meaning). The existing T13 rows assert the phrase `not a valid repository name`; the new ref-grammar FATAL text contains that exact phrase (`... is not a valid repository name or digest ref ...`) so they pass unchanged.
- [ ] AC2. For an element with a ref whose `tags/list` answered 200, the probe issues exactly one authenticated manifest `HEAD` (request target = the digest). 200 = `pinned`; 404 = `pin-missing` (suppress ping, exit 0, fault line `SUPPRESS ping: 404 ... pinned manifest <ref> is MISSING ... repo=<path>`); 401 = `auth-broke` (exit 3, no ping); 000 = `unreachable`, 5xx = `wedged`, any other code (403 included: the manifest-endpoint accessControl failure `ci-deploy.sh` documents, visible only there) = `unexpected`, with the code in the fault line (each suppresses the ping). The pin verdict reuses the existing classification vocabulary; no new verdict names beyond `pinned` and `pin-missing`. No early exit in the loop: every repository's lines are emitted.
- [ ] AC3. The heartbeat ping is logged iff every repository's `tags/list` is 200 AND every pinned element's HEAD is 200. A pin fault on ANY pinned element (first, last, or the second of two) suppresses it; a pin fault on one element is never cleared by a healthy later element.
- [ ] AC4. When `tags/list` is not 200 for an element, its pin is not HEADed (`pin_verdict=skipped`): during an outage that avoids a second timeout and a duplicate fault line for the same repository (it is NOT the worst-case bound). Worst case is a 200 tag list followed by a hanging HEAD: 20 s for a pinned repository, 10 s for a bare one, so 30 s no-ping on web-1 (10 s on every other host) and 50 s to a ping on web-1 (two `curl -m 10` ping attempts). All of these are under the 60 s timer interval, so no tick is skipped whether `OnUnitActiveSec=60s` is counted from the unit's start or its end, and the 180 s heartbeat period holds in both readings; runs never overlap (a oneshot still activating is not started again).
- [ ] AC5. The marker row keeps its existing prefix and appends one field: `SOLEUR_ZOT_PROBE_VERDICT repo=<r> code=<n> verdict=<v> ts=<epoch> pin_verdict=<none|skipped|pinned|pin-missing|auth-broke|unreachable|wedged|unexpected>` (one appended field; the numeric code is in the fault line for any non-200 outcome). One row per repository per 30-minute window regardless of verdict, emitted before the exit decision (the 401 path included); the missing / corrupt / future-dated marker behavior (fails toward EMITTING) is unchanged.
- [ ] AC6. Every fault line ends with `repo=<path>` (pin fault lines add `ref=<ref>` BEFORE it). The credential never reaches curl's argv: the HEAD request uses the same stdin `--config -` channel, and no `-f`, no `--retry`.
- [ ] AC7. `web-probe.tf` derives the bootstrap digest from the `ZIREF` line of `cloud-init-inngest.yml` (`regex(...)[0]`, because a regex with one capture group returns a list) into `local.zot_probe_digest_inngest_bootstrap`, and defines `local.zot_probe_repo_pinned = join(",", [local.zot_probe_repo_web, "${local.zot_probe_repo_inngest_bootstrap}@${local.zot_probe_digest_inngest_bootstrap}"])`. `local.zot_probe_repo` is BYTE-UNCHANGED (still the bare join of the two repository paths). The bash suite cannot evaluate Terraform `regex()`, so the static rows assert SHAPE: the regex is anchored on `ZIREF="`, reads `file("${path.module}/cloud-init-inngest.yml")`, ends in `[0]`, and NO `sha256:[0-9a-f]{64}` literal appears in `web-probe.tf` (a hard-coded stale digest fails here); the bare local line and the cloud-init templatefile line are unchanged. A `terraform console` row (gated on `command -v terraform`, with an explicit printed SKIP count so a skip cannot read as green and the skip does not count toward `MIN_ASSERTS`) evaluates the derived digest and asserts it equals the digest on the `ZIREF` line of BOTH `cloud-init.yml` and `cloud-init-inngest.yml`, each extracted independently by `sed` with a non-empty assertion. The web element stays bare and its marker reports `pin_verdict=none`.
- [ ] AC8. `server.tf` changes in exactly two lines: the `local.zot_probe_repo,` entry of `terraform_data.zot_consumer_probe_install`'s `triggers_replace` and the `'${local.zot_probe_repo}'` argument of its env-file `printf` both become `local.zot_probe_repo_pinned`; the cloud-init templatefile line `zot_probe_repo = local.zot_probe_repo` is untouched (so no born host receives a pin). `git diff --stat origin/main -- apps/web-platform/infra/variables.tf apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/web-probe-envwrite.sh` is empty. The T7 rows for the writers are updated to name the right local at each site and a new row asserts the cloud-init path value contains no `@`.
- [ ] AC9. New control-character rows: a newline in `ZUSER`, a backslash in `ZUSER`, a tab in `ZUSER`, a tab in `ZTOK`, and a tab inside a `ZOT_PROBE_REPO` element each exit 1 with the existing FATAL text, curl never invoked, value never echoed; each row is proven able to FAIL with ONE mutant per guard arm, each proven landed with `cmp -s`: dropping the `[[:cntrl:]]` arm of `_cfg_ok` reddens the tab and newline credential rows; dropping its `*\\*` arm reddens the backslash row; dropping the `*[[:space:]]*` arm of the element loop reddens the tab-element row.
- [ ] AC10. `MIN_ASSERTS` in the suite is raised in the same edit to the new measured total (never lowered); `bash scripts/guard-vacuity-floor.test.sh` passes with the suite still in `PROMOTED_FILES` and `MAX_DEFERRED` unchanged; `bash plugins/soleur/test/fixture-relative-assert.test.sh` passes, with `fixture-relative-assert.baseline.txt` regenerated (`--write-baseline`) only if the scanner's row for the probe moved, in the same commit.
- [ ] AC11. The Guard 1 and Guard 2 mutation batteries were executed on sandbox copies (`cmp -s` proves each mutant landed; a green unmutated control first); the results table is in the PR body.
- [ ] AC12. Every sentence this PR adds to a comment, runbook, `model.c4` or workflow summary has an entry in the Prose ledger with its falsifying command run and the observed output; the PR body carries the table.
- [ ] AC13. `git diff --stat origin/main -- apps/web-platform/infra/ci-deploy.sh` is empty (Deploy Pipeline Fix Drift Gate not triggered).
- [ ] AC14. (Optional, "if convenient" per the brief; never a ship blocker.) The Step-B plan and spec are archived (`knowledge-base/project/plans/archive/*delete-zot-entry-gate*`, `knowledge-base/project/specs/archive/*feat-one-shot-7258-delete-zot-entry-gate*`), with `git status` showing staged renames and no untracked twins, in one `chore(archive-kb)` commit.
- [ ] AC15. `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` bumped by exactly one over the value re-read after the rebase (59 -> 60 today) with a dated ledger comment naming this plan; the suite passes. `plugins/soleur/test/c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- [ ] AC16. Local verification passes (bounded output): `shellcheck` on the probe and suite (findings compared against `origin/main`, none new); the probe suite; `terraform fmt -check` and `terraform validate` for the root; `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh` (the `server.tf` edit must not add or move an SSH dialer), `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`, `web-probes-token-rotation.test.sh`, `doppler-injection-bound.test.sh` (each reads `server.tf` or the probe unit), `journald-config.test.sh`, `web-ghcr-deny.test.sh`, `cloud-init-web-zot-seed.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`, and every `.claude/hooks/*.test.sh` guard (no new test pipes into `grep -q`).

### Post-merge (agent-observed, telemetry only; none is an operator checklist)

- [ ] AC17. `deploy-arm.sh find --wait <full 40-hex merge sha>` returns an `ARM=<id>` verdict, then `deploy-arm.sh served <sha>` confirms the build is served (the baked probe script rides the normal `web-platform-release` build).
- [ ] AC18. The push apply run for the merge commit shows `terraform_data.zot_consumer_probe_install: Creation complete` in its log (bounded `gh run view --log` read), regardless of the job's overall colour; its log timestamp is the delivery anchor T0. The same merge also fires `apply-deploy-pipeline-fix.yml` (`server.tf` is in its `paths:`); it serializes behind or ahead of the first through the shared `terraform-apply-web-platform-host` concurrency group, and no re-dispatch of either is needed or allowed (one apply per trigger-file class).
- [ ] AC19. Once two new-format marker rows (they carry `pin_verdict=`; filter on it) exist for the host in distinct `floor(ts/1800)` buckets after T0 — the repos marker file lives in `/run` and survives delivery, so the first new-format row can land up to 30 minutes after T0 and the second at least 30 minutes after that, a worst case of about 65 minutes: for `host_name=soleur-web-platform`, `repo=jikig-ai/soleur-inngest-bootstrap` reports `code=200 verdict=servable ... pin_verdict=pinned` in each bucket and `repo=jikig-ai/soleur-web-platform` reports `pin_verdict=none`; zero `SUPPRESS ping` / `HARD FAILURE` rows from `web-zot-consumer-probe` on that host since T0 (a registry replace inside the window, visible in `gh run list -w registry-host-replace-dispatch.yml`, explains and excuses its own rows — the criterion grades the change, not the machine), read with the `SOLEUR_PROBE_CANARY` positive control alive in the same window; `soleur-web-zot-consumer-web-1` is `up`, `paused=false`, with zero incidents since T0.
- [ ] AC20. The AC19 output is posted as a comment on #10004 (the closing record), and #10044 stays open.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO confirmed the measured retention behavior is the right signal and that all-must-pass from day one is correct (escalation is email-only; replace a report-only window with a post-apply telemetry read). Findings applied: (1) HIGH — a pin carried in the list that also feeds the cloud-init template would be baked once into every born host and rot (web servers ignore `user_data` changes; web-2 has no probe twin), so the pinned list is confined to web-1's two `server.tf` sites and born hosts keep the bare list; (2) anchor the regex on `ZIREF="` because a comment in the bootstrap block mentions the pins, and assert the match in T7; (3) the CTO asked for a distinct verdict for a manifest-endpoint 403 (the accessControl failure `ci-deploy.sh` documents as visible only at the manifest endpoint) — NOT applied after plan review (the plan-review simplicity seat found no requirement it serves: a 403 suppresses the ping either way and the fault line carries the code); recorded as DC-4; (4) drop the tag from the ref grammar and the tag HEAD, leaving one shape `repo@sha256:<64 hex>`; (5) document that a manifest HEAD does not prove blobs (Non-Goals); (6) a web-1 SSH failure now also surfaces on bump merges (Apply path). Recommendations NOT applied: `-m 5` for the HEAD (one request site, one timeout; the 50 s worst case fits the cadence) — recorded in `decision-challenges.md`; keeping the 5xx-versus-other verdict split (it is free in the shared classifier and keeps the existing fault wording). The separate-env-var alternative was rejected by the CTO as well.

Other domains: no cross-domain implications. Product/UX: none (no user-facing surface, no file under a UI path). Legal/GDPR: the marker and fault lines carry repository paths, refs (public digests), HTTP codes and epoch timestamps only; no personal data, no new processing activity, no distribution surface (Phase 2.7 triggers (a)-(d) all absent).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is operator-facing: the `soleur-web-zot-consumer-web-1` heartbeat goes absent (an email alert) because a pin check false-reds, or stays green over an evicted pin if the new check is defeated. No request path, session or workspace is touched.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector is added. The pull credential continues to travel only on curl's stdin config (never argv), the new lines carry repository paths, public digests and HTTP codes only, and the refuse-to-trace guard and `_cfg_ok` credential-shape check are retained unchanged.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` rather than `aggregate pattern` because the change is detection-only: it adds an alarm input and removes nothing a user-facing path depends on; the fresh-boot failure it detects exists independently of this change.

`threshold: none, reason: this change adds a host-side detection check, its tests and telemetry only; it touches no user data, no request path and no credential handling beyond reusing the existing stdin-config channel, so a defect can at worst mis-page the operator.`

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat soleur-web-zot-consumer-web-1, pinged by the probe only when EVERY repository's tags/list is HTTP 200 AND every pinned element's manifest HEAD is HTTP 200; plus per-repo SOLEUR_ZOT_PROBE_VERDICT marker rows (now carrying pin_verdict) and the existing SOLEUR_PROBE_CANARY positive control; a missing ping IS the alert
  cadence: 60 s timer; heartbeat period 180 s with 60 s grace; marker rows at most once per 30 min per host
  alert_target: Better Stack heartbeat email escalation (betterstack_paid_tier stays false)
  configured_in: apps/web-platform/infra/web-probe.tf (betteruptime_heartbeat.web_zot_consumer; local.zot_probe_repo_pinned for web-1, the bare local.zot_probe_repo for cloud-init) and apps/web-platform/infra/web-zot-consumer-probe.sh
error_reporting:
  destination: journald SyslogIdentifier=web-zot-consumer-probe, shipped by Vector Source 4 (host_scripts_journald allowlist) to Better Stack Logs
  fail_loud: a 401 on any tags/list or pin HEAD exits 3 (unit failed) and logs HARD FAILURE with repo=<path>; a pin fault logs a SUPPRESS line with ref= and a trailing repo=<path> on every faulting run (404 = pinned manifest MISSING; any other code is named in the line); a malformed list element or ref exits 1 with FATAL before any request
failure_modes:
  - mode: pinned bootstrap manifest evicted by retention, never mirrored, or garbage-collected while tags/list still answers 200
    detection: Better Stack Logs layer 3 (vector journald Source 4) SUPPRESS line "pinned manifest ... MISSING" naming ref= and repo=jikig-ai/soleur-inngest-bootstrap, plus pin_verdict=pin-missing in the marker row; the heartbeat goes absent
    alert_route: Better Stack heartbeat email on absence; the fault line is read with scripts/betterstack-query.sh
  - mode: the pin check is defeated (HEAD never issued, a pin fault dropped from the ping decision, a fault cleared by a later healthy element, 401 demoted)
    detection: CI layer (build-time defect, no runtime layer applies), the new pin rows in web-zot-consumer-probe.test.sh plus the mutation batteries in the Guard Contract and the PR body
    alert_route: required CI check red on the PR
  - mode: the probe is delivered a stale pin (a pin bump merged but the web-1 delivery apply failed) and the old pin is later evicted, producing a false red
    detection: the fault line names ref=<old ref>; comparing it with the ZIREF pin on main distinguishes a stale delivery from a real eviction; the push apply run log for the bump commit shows whether Creation complete ran
    alert_route: Better Stack heartbeat email on absence; apply-web-platform-infra run status
  - mode: a pin baked into a born host's env file rots after 5 newer v.* tags and false-reds that host's heartbeat (cattle pin-rot)
    detection: prevented by construction, not detected: the cloud-init-bound list is bare; CI layer (build-time defect, no runtime layer applies) — T7 asserts `local.zot_probe_repo` contains no `@` and the cloud-init templatefile line still names it; a live check is the marker rows of web-2 and later hosts reporting `pin_verdict=none`
    alert_route: required CI check red on the PR
  - mode: Source 4 / vector dead so fault and marker lines never leave the host
    detection: absence of the SOLEUR_PROBE_CANARY row (emitted independently of zot, from ExecStartPre outside the doppler wrapper) in a 1 h window
    alert_route: the heartbeat is the backstop; the canary is the positive control read by the runbook
logs:
  where: Better Stack Logs source 2457081 (shared), SYSLOG_IDENTIFIER=web-zot-consumer-probe, host_name discriminator
  retention: per the shared source's retention; marker rows are rate-limited to one per repository per 30 min, fault lines are per run
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep pin_verdict=pinned --limit 5
  expected_output: pin_verdict=pinned
  credentials_required: BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD via Doppler soleur/prd_terraform — the Logs warehouse read connection is credential-gated; the property (per-repo marker rows with the pin verdict from web-1) lands only in that warehouse, which has no unauthenticated read path
```

## Infrastructure (IaC)

Routing is already IaC: web-1's probe is delivered by `terraform_data.zot_consumer_probe_install` and fresh hosts by cloud-init plus the baked env-writer. Nothing is installed or edited by hand.

### Terraform changes

- `apps/web-platform/infra/web-probe.tf` — `locals` only. Keep `zot_probe_repo_web`, `zot_probe_repo_inngest_bootstrap` AND the `zot_probe_repo = join(",", [...])` line exactly as they are (bare; cloud-init keeps consuming it). Add `zot_probe_digest_inngest_bootstrap = regex("(?m)^\\s*ZIREF=\"[^\"/]*/${local.zot_probe_repo_inngest_bootstrap}:v[0-9]+\\.[0-9]+\\.[0-9]+@(sha256:[0-9a-f]{64})\"", file("${path.module}/cloud-init-inngest.yml"))[0]` and `zot_probe_repo_pinned = join(",", [local.zot_probe_repo_web, "${local.zot_probe_repo_inngest_bootstrap}@${local.zot_probe_digest_inngest_bootstrap}"])`. The regex shape was evaluated with `terraform console` against BOTH cloud-init files on 2026-10-11 and returns `sha256:25935628...` (a list without `[0]`, a string with it); it anchors on `ZIREF="`, so the comment at the top of the bootstrap pin block that mentions "ZIREF below" cannot match. A pin line that stops matching fails the PLAN loudly, which is the intended direction (the work phase writes the HCL with the Write tool, not inside a shell command).
- No new provider, no new sensitive variable, no new `TF_VAR_*`, no Doppler change. `variables.tf`, `cloud-init.yml` and `web-probe-envwrite.sh` are not edited; `server.tf` changes in exactly two lines (the `triggers_replace` entry and the `printf` argument, both `local.zot_probe_repo` -> `local.zot_probe_repo_pinned`). A value of the form `a/b,c/d@sha256:<hex>` is safe in the SSH `printf '...%s...' '${local.zot_probe_repo_pinned}'` (no quote, backslash or space), and in a unit `EnvironmentFile`.

| Consumer | What changes | Executed by |
|---|---|---|
| `terraform_data.zot_consumer_probe_install` `triggers_replace` (hashes the script file and, after the `server.tf` edit, `local.zot_probe_repo_pinned`) | hash changes now (new script and new value) AND on every future bootstrap pin bump | the post-bridge step of the push apply job, `-target=terraform_data.zot_consumer_probe_install`; its three file provisioners and env-writing remote-exec re-run against web-1 |
| that resource's env-file `printf` (`ZOT_PROBE_REPO=%s`) | writes `<web repo>,<bootstrap repo>@sha256:<digest>` | same |
| `cloud-init.yml` templatefile var `zot_probe_repo` -> `web-probe-envwrite.sh` | UNCHANGED: still `local.zot_probe_repo`, the bare list | fresh hosts at birth |
| `hcloud_server.web[*]` `user_data` (templatefile var `zot_probe_repo`) | rendered value changes | NOT applied: `lifecycle { ignore_changes = [user_data, ...] }` |
| `local.host_script_files` -> `host_scripts_content_hash` | changes (the probe script is in the baked set) | consumed by `user_data` and by the coherence preflight of host create/replace dispatches |
| `apps/web-platform/Dockerfile` bakes the script | image content changes | normal `web-platform-release.yml` build |

### Apply path

(c)-class, already sanctioned: the existing SSH-provisioned `terraform_data` for web-1 (a state-entry swap of the `terraform_data`, never of the server), plus cloud-init and the env-writer for hosts born later. A server `-replace` is neither viable nor needed (web-1 is the cx33 host; `web_host_replace` refuses it).

- Trigger: push to `main` touching `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` (job `apply`, environment `infra-privileged`): a saved-plan scoped apply guarded by destroy counters, then the bridge and the post-bridge apply where this resource lives. Because `server.tf` is in its `paths:`, the same merge ALSO fires `apply-deploy-pipeline-fix.yml` (a routine server.tf-only run skips the seccomp swap and finishes in minutes). Both workflows declare the identical concurrency group `terraform-apply-web-platform-host` (`cancel-in-progress: false`), so they serialize; the Deploy Pipeline Fix Drift Gate in `soleur:ship` is NOT triggered (its trigger-file list excludes `server.tf`; AC13). Does NOT fire: `registry-host-replace-dispatch.yml` (needs `variables.tf`, `cloud-init-registry.yml` or `zot-registry.tf`). One apply per trigger-file class, never a re-dispatch.
- No host, volume or attachment is replaced: the pinned local reaches web-1 only through the SSH provisioner (never `user_data`), and the bare local's rendered value is unchanged, so `hcloud_server.web`'s `user_data` does not change from this edit at all (the script-hash change reaches it too, but `user_data` is `ignore_changes`); the saved-plan destroy-guard would halt on any `hcloud_server` update or create.
- Blast radius: none for serving traffic. The probe is a oneshot on a 60 s timer; the script is replaced on disk and the next tick runs the new code. Worst-case run time is bounded by AC4.
- New recurring consequence: every future bootstrap pin bump (the bump PR edits both `cloud-init*.yml` files) now also recreates this resource in that merge's push apply, because `local.zot_probe_repo_pinned` is a `triggers_replace` input. That is one more SSH delivery per bump, idempotent, and it is the mechanism by which the probe follows the pin. The path that carries it already exists and is evidenced: a bump PR edits `apps/web-platform/infra/cloud-init*.yml`, which matches `apply-web-platform-infra.yml`'s `apps/web-platform/infra/**` push filter, and that run's post-bridge step already names `-target=terraform_data.zot_consumer_probe_install` (run 38151764939, the #10027 bump: the resource was refreshed, not recreated, because the hash did not move; after this change the hash moves); a web-1 SSH failure now also shows up on bump merges. If that delivery fails while the old pin is later evicted, the probe false-reds (Observability failure mode 3); the fault line names `ref=` so the cause is distinguishable.
- web-2 and every later born host (host fan-out classification, per `plan-host-fanout.md`): `birth-covered`, deliberately WITHOUT the pin. They receive the probe via cloud-init and have no provisioner twin; they keep the BARE list (and web-2 the older script) until their next replace, consistent with each other (P5, P6; the runbook already states "web-2 still probes the web image only until its next replace"). The pin is a registry-wide property checked from web-1; each host keeps its own heartbeat, so a healthy host still cannot mask a broken sibling. A new-env-with-old-script skew on a future born host is blocked by `host-image-coherence-preflight.sh` (the probe script is inside `host_scripts_content_hash`) and re-verified by cloud-init at boot; and the bare list is valid for the older single-repo script too.
- Sequencing: no other infra apply in flight (Phase 0, Phase 8); after merge, no `web-host-create` / `web-host-replace` dispatch until the `web-platform-release` for this merge has deployed.

### Distinctness / drift safeguards

- `dev != prd`: not applicable (no Doppler config or TF variable change).
- `lifecycle.ignore_changes`: `hcloud_server.web` (load-bearing for the no-replace claim) and `betteruptime_heartbeat.web_zot_consumer` `[paused]` (unchanged).
- State: no secret values added; the web_probes token stays hashed with `nonsensitive(sha256(...))` in the same `triggers_replace`.

### Vendor-tier reality check

No new Better Stack resource. Log volume: marker rows grow by ~30 bytes each (still one per repository per 30 min); a pin fault adds at most one SUPPRESS line per run for the pinned repository only (a full outage skips the pin, so it never doubles the 2880 rows/day ceiling). A chronic pin-missing state is therefore at most +1440 rows/day per host (about 28% of the ~5.1k/day headroom recorded in ADR-184 and the probe header) until a bump merge or a `mirror_only` dispatch repairs it; the state pages within ~4 minutes, so it is not expected to persist.

## Encryption Posture

No persistent data store and no new cross-component or network connection is introduced. The probe's existing leg (web host to the registry over the private NIC, plain HTTP, Basic auth read from curl's stdin config) is unchanged: same endpoint, same credential, one additional request path on it. It is not re-declared here; the registry store and transport postures remain governed by ADR-096, ADR-140 and the encryption-posture ledger.

## Architecture Decision (ADR/C4)

No new ADR: this extends an existing probe inside the existing substrate and the ADR-096 / ADR-117 decisions (no new trust boundary, no new store, no new heartbeat, no reversal of a decision). The mechanism choice (ref inside the existing list element, pin derived from the `ZIREF` line) is recorded in the probe header and the runbook, where the next editor reads it.

### C4 views

One in-scope task: edit the `hetzner -> zotRegistry` consumer-probe edge description in `knowledge-base/engineering/architecture/diagrams/model.c4` (and its leading comment, which says "HEAD of a known manifest") so it says the probe GETs `tags/list` for each platform repository AND HEADs the pinned manifest of each repository that has a pin (today the inngest bootstrap image), pinging only when all answer 200; then regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh` (the pinned `likec4@1.50.0` renderer; `c4-model-freshness.test.sh` byte-diffs it). Completeness check across `model.c4`, `views.c4` and `spec.c4` (to be re-read at work time before concluding): external systems are `hetzner` (web host), `zotRegistry` and `betterstack`, all already modeled, and the `zotRegistry -> betterstack` and `hetzner -> betterstack` log edges already cover the marker rows; no new human actor, no new external system, no new data store, no access-relationship change; no element or `view ... include` line is added, so derived cardinalities do not move. Evidence step: `plugins/soleur/test/c4-count-parity.test.sh`, `plugins/soleur/test/c4-model-freshness.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`.

## Guard Contract

### Guard 1 — pin HEAD aggregation in the probe

**Property.** The heartbeat ping is emitted if and only if every non-empty element's `tags/list` classified HTTP 200 AND every element that carries a ref classified its manifest HEAD HTTP 200 in this run; a 401 on either request of any element exits 3 with no ping; and a pin fault on any element is never cleared by a later healthy element.

**Assembly.** One chokepoint: the aggregation block after the per-repo loop in `web-zot-consumer-probe.sh` — the only call site of `_ping` (grep before editing: one definition, one call; re-run after the edit). The members that must flow through it: the per-element `tags/list` classification, the new pin classification (200, 404, 401, 000, 5xx, other), the `unservable` and `auth_broke` accumulators (the pin result MUST set the same accumulators, not a parallel flag the aggregation does not read), the list and ref parsers, the existing status-override seam (tag-list codes only; pin codes are driven through the mock registry and the stub curl, not a second seam), the marker emitter (`R_NAME`/`R_CODE`/`R_VERDICT` plus the new pin arrays), and the skip rule (pin not HEADed when `tags/list` was not 200). Members drift; the chokepoint is structural: a new classification arm that sets neither accumulator is exactly the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pin 404 sets no accumulator (the verdict is recorded but the ping still fires) | RED: P2 (`pin 404, tags 200`) asserts NO ping and the `pinned manifest ... MISSING` line |
| 2 | Pin loop stops at the first pinned element (early `break`) after a compliant first member | RED: P2b (two pinned elements, the SECOND evicted) asserts no ping and names the second repo |
| 3 | A per-iteration reset of the pin-fault flag (`unservable=0` reset inside the loop; pin faults share the existing accumulators) | RED: P2c (the FIRST pinned element evicted, the second healthy) asserts no ping — a delete-only battery would not see this; it is an order/lifetime row |
| 4 | Demote a pin 401 to a suppress (exit 0) | RED: P3 asserts exit 3 for `pin 401` in either position |
| 5 | The guard's own dispatch: the HEAD is never issued (the pin function returns 200 unconditionally, or the call is deleted) | RED: P8 asserts the mock recorded a HEAD of the pinned path on a healthy pinned run, and P9's stub-curl run asserts a request carrying `-I` and the manifest path — so "0 pins checked, exit 0" cannot pass |
| 6 | Wrong request shape: add `-f`, drop `-I`, or request something other than the digest (the tag, a bare path) | RED: P9 argv assertions (`-I` present, no `-f`, URL ends in `/manifests/sha256:<digest>`) and P8 (the mock sees a `GET`, or a path that is not the pinned digest) |
| 7 | HEAD the pin even when `tags/list` was not 200 | RED: P5 asserts no HEAD request in the stub argv and `pin_verdict=skipped` |
| 8 | Drop `pin_verdict` from the marker, or emit it only on healthy runs | RED: P10 asserts `pin_verdict=pin-missing` in the marker of a faulting run and of the 401 run |
| 9 | Classify any pin code other than 200, 404 and 401 (403, 503) as `pinned` | RED: P4 asserts no ping for 403 and 503 |

**Harness rows.** (H1) Edit the mock registry so every `HEAD` answers 200: the behavioral eviction row (P8) must go RED, proving the mock discriminates. (H2) Edit the stub curl to answer 200 for every URL: the stub rows for pin 000 / 401 (P3, P4) must go RED. (H3) Must-PASS non-canonical inputs: a list of two valid pinned elements, and a trailing-comma list with a pinned element, each ping with exit 0 — RED rows alone cannot detect a parser that rejects everything.

**Anchor.** Not a stored-value comparison: the guard compares live HTTP codes against the classification table in the same file. The classification-table anchor is the pre-existing rows (a)-(h) and T1-T16, which must pass unchanged (AC1); the pin value's anchor is Guard 2.

### Guard 2 — the ref the probe HEADs equals the ref the hosts pull

**Property.** The digest carried in the bootstrap element of `local.zot_probe_repo_pinned` is exactly the digest on the `ZIREF` line of BOTH `cloud-init.yml` and `cloud-init-inngest.yml`; that list is exactly {the bare web repo, the bootstrap element}; and no pin is ever written to a host that nothing re-delivers (the cloud-init-bound list is bare).

**Assembly.** Two flows from `web-probe.tf`, each with its own chokepoint. (1) `local.zot_probe_repo_pinned` is the ONLY value reaching web-1 (`server.tf`: the `triggers_replace` entry and the env-file `printf`). (2) `local.zot_probe_repo`, bare, is the ONLY value reaching `cloud-init.yml` (`zot_probe_repo` -> `SOLEUR_ZOT_PROBE_REPO` -> `web-probe-envwrite.sh` -> `ZOT_PROBE_REPO=`), so no born host receives a pin. Referents: the two `ZIREF=` lines (and the two `IREF=ghcr.io/...` pin carriers the bump script rewrites). T7 names those anchors by content (the `ZIREF=` lines, the two locals, the two `server.tf` sites), not by line number.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hard-code a stale literal digest in `web-probe.tf` | RED: the static no-`sha256:[0-9a-f]{64}`-literal row, and the `terraform console` equality row when terraform is present |
| 2 | Own dispatch: change the `ZIREF` line shape so the extraction matches nothing | RED: the row asserts the extraction is NON-empty before comparing; the same anchored shape in `web-probe.tf` and in T7 means a reshaped `ZIREF` line reddens CI on the bump PR before it can break every infra plan |
| 3 | Drop the `[0]` index in `web-probe.tf` (the local becomes a list) | RED: a static row asserts the `regex(...)[0]` shape; the `terraform console` evidence step (AC16) shows the type |
| 4 | Build the element without the repository (`@<digest>` only), or add a third element after the compliant two | RED: exact two-element set equality (not a floor) |
| 5 | Make the web element carry a ref, or point the cloud-init template var at the pinned local | RED: the web element must be bare (the web pin does not exist; #10044) and the cloud-init-bound value must contain no `@` (the cattle pin-rot guard) |

**Harness rows.** (H4) A self-comparison edit of the static extraction helper (it returns the TF value itself) must fail the independence row. (H5) A synthetic fixture whose `ZIREF` names a different but consistent repository and digest: the extraction helper must return THAT digest (must-PASS, non-canonical).

**Anchor.** The pins are referents that change through the bootstrap mint workflow and review (`bump-inngest-bootstrap-pin.sh` rewrites exactly the pin sites, and its drift guard reads the tag); the TF value is DERIVED from the file at plan time, never stored, so there is no stored hash or count floor to weaken. A diff that changes only the TF extraction is caught by the independent file-side extraction; a diff that changes the `ZIREF` pins changes what hosts pull and the probe follows it, by design.

## Implementation Phases

### Phase 0 — Preconditions (read-only; at work start and again immediately before enqueue)

1. Rebase on `origin/main` (`git fetch origin main && git rebase origin/main`); never merge main into the branch. Re-read `BASELINE_DECLARED_PROBES` after the rebase. Do not push while a PR for this branch is queued.
2. Sequencing: `gh run list --status in_progress` and `--status queued` show no `apply-web-platform-infra.yml`, `registry-host-replace-dispatch.yml`, `apply-deploy-pipeline-fix.yml`, `web-platform-release.yml` or host-replace dispatch run (strictly sequential infra applies; this merge itself fires two of them, which serialize on the shared concurrency group).
3. No registry observation window is open: no recent registry replace, no open soak or follow-through tracker for the registry, and the recent applies are settled (`gh run list -w apply-web-platform-infra.yml -L 6`). If any is open, hold the merge (do not queue), not the PR.
4. Baselines for the PR body: heartbeat state and canary row counts per host from Better Stack; the current marker rows for the bootstrap repo.
5. Re-run measurements M1-M5 (Research Insights) against the pinned zot image and keep the output for the Prose ledger. Remove the container and scratch files afterwards.

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

Extend `apps/web-platform/infra/web-zot-consumer-probe.test.sh` (no new suite file; no `grep -q` after a pipe; assert literal output with `grep -F`; every helper keeps its own per-run marker paths):

- No new seam: pin codes are driven through the mock registry (a digest-to-code table: 200, 404, 401, 403, 503) and, for a pin transport failure, a stub curl that fails the manifest URL (curl's `000` shape) while answering the tag list. The existing `SOLEUR_ZOT_PROBE_STATUS_OVERRIDE` keeps driving tag-list codes only.
- Mock registry (python): add `do_HEAD`; serve `HEAD /v2/known/second/manifests/sha256:<D>` with auth; 404 for the evicted digest; 401 without auth; record each request's method and path to a file for assertions.
- Rows P1-P10 and P12 (Test Scenarios) plus the control-character rows (AC9) plus `has_marker`-style strictness rows for the pin fields.
- The curl stub (`run_stub`) records argv and stdin per call; assertions use `-F` matches on files.

Run the new rows against the unmodified probe and confirm they are RED for the right reason (pin ignored, ref rejected as a repository name), then GREEN after Phase 2.

### Phase 2 — Probe (`web-zot-consumer-probe.sh`)

- Element parsing (bash pitfalls from review): validate the whole element for whitespace BEFORE any split (the existing arm); branch on `[[ $_e == *@* ]]` first (`${_e#*@}` returns the whole string when there is no `@`); take the repository as `${_e%%@*}` and the remainder as `${_e#*@}` and validate the remainder against `^sha256:[0-9a-f]{64}$` held in a variable under `local LC_ALL=C` (as `_cfg_ok` does), so an empty remainder (`repo@`) fails; the repository part goes through the existing OCI-name glob (a `:` stays outside that alphabet, so a tagged ref is refused). The ref-grammar FATAL text contains the existing phrase `not a valid repository name` (`... is not a valid repository name or digest ref ...`) so the T13 rows pass unchanged. Every path (status seam, skip, bare, 401) appends to the pin arrays (`R_PIN_VERDICT`), so `_repo_markers` can never hit an unset index under `set -u` (add a row: 401 on a pinned element still emits its marker and exits 3). Pass the HEAD flag as a separate leading argument (`${2:+-I}` style), never an empty-array expansion (unsafe on bash < 4.4). Keep the other keep-list gates and their FATAL texts.
- Single request site: factor the curl invocation into one function used by both `tags/list` (GET) and the manifest request (`-I`), keeping the stdin `--config -` channel, `--disable --noproxy '*'`, `-m 10`, `-w '%{http_code}'`, the `000000` normalization and NO `-f`. Keep the matched texts ` -s -o /dev/null -w` and ` -m 10 --config - "http` CONTIGUOUS inside the one function, with `-I` passed earlier as its own argument, so the suite's three argv/flag mutants — (b) auth-channel strip, (c) `-f` injection, (h) argv-credential — still land on BOTH requests; update them in the same edit, prove each landed with `cmp -s`, and add a HEAD-specific `-f` row (Guard 1 row 6). The T8 assertion that stdin holds exactly one line per curl invocation changes with the invocation count (one more per HEADed pin); update it.
- Shared classification: one function maps a code to a verdict and emits the fault line for either request, with the HEAD variant's wording (`pinned manifest <ref> is MISSING ... tags/list still answered 200` on 404; the code in the line for any other fault). Pin results set the SAME `unservable`/`auth_broke` accumulators.
- Marker: append `pin_verdict=` after `ts=`; `none` for a bare element, `skipped` when `tags/list` was not 200.
- Header comment: describe the ref grammar (`repo` or `repo@sha256:<64 hex>`), the skip rule, the worst case (30 s no-ping, 50 s to a ping for web-1's list; 10 s no-ping on every other host; both under the 60 s interval), why only web-1 carries a pin, and cite the measured evidence rows. `--canary-only` and the refuse-to-trace guard are untouched.

### Phase 3 — Wiring (`web-probe.tf`)

The three locals (Infrastructure → Terraform changes) and the two `server.tf` lines. Update the locals' comment to say what is derived from what, why the web element stays bare (#10044), and why born hosts get the bare list (cattle pin-rot). Extend T7 in the probe suite (derived digest vs both `ZIREF` digests; the bare list unchanged; the pinned join; the four writer rows naming the right local).

### Phase 4 — Records and prose (each sentence in the Prose ledger)

`model.c4` edge + comment, regenerate `model.likec4.json`; `betterstack-log-query.md` heartbeat table row and the reading rule for `pin_verdict` / the new fault line (the existing aggregate query already counts the new SUPPRESS line as `other_suppress`); `build-inngest-bootstrap-image.yml` comment and step-summary sentence.

### Phase 5 — Floors, baselines, discoverability

Raise `MIN_ASSERTS`; run `scripts/guard-vacuity-floor.test.sh` and `plugins/soleur/test/fixture-relative-assert.test.sh`; bump `BASELINE_DECLARED_PROBES` by one with the dated ledger comment; run that suite.

### Phase 6 — Mutation batteries

Guard 1 and Guard 2 matrices on sandbox copies, a green control first, `cmp -s` per mutant; the results table goes into the PR body.

### Phase 7 — Archive the Step-B leftovers (optional; last; if the archive does not persist cleanly, drop it and say so in the PR body)

`bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run delete-zot-entry-gate` (matches the plan), then `--dry-run one-shot-7258-delete-zot-entry-gate` (matches the spec directory); run each without `--dry-run`; verify with `git status --short` that the moves are staged renames with no untracked twin (issue #9172: `archive-kb.sh` can leave staged-but-unpersisted renames on a non-committable checkout), and commit with a pathspec (never `git add -A`).

### Phase 8 — Local verification and ship

AC16 in full (bounded output). Mark the draft PR #10041 ready only when the work is verified; read the CI run created at ready (the draft-light run's `test` check reads red by design); read the failing STEP before calling any red a regression and compare with `main` on the same suite. The PR body: `Closes #10004`, the measured-evidence table, the Prose ledger, the mutation results, the apply-path table, the web-gap statement (#10044), and the post-merge recipe. Queue the merge only after Phase 0.2 re-checks clean immediately before.

### Phase 9 — Post-merge observation (agent-run, telemetry only)

`deploy-arm.sh find --wait <full-sha>`, then `served`; read the push apply log for T0 (AC18); wait for two 30-minute buckets; run the AC19 reads (`scripts/betterstack-query.sh` via `doppler run -p soleur -c prd_terraform`, output to a file, bounded); post the result on #10004.

## Prose ledger

Every sentence the PR adds to a comment, runbook, `model.c4` or workflow summary, with the command that falsifies it (run, with its output, before the sentence is written):

| Sentence (paraphrase) | Where | Falsifying command |
|---|---|---|
| "After retention evicts a tag, `tags/list` stays 200 while HEAD of the pinned digest returns 404" | probe header, runbook | Phase 0.5 local zot run (M1, M2) |
| "HEAD needs no Accept header (index digest)" | probe header | M3 |
| "A pin bump now re-delivers the probe to web-1, and only web-1" | runbook, PR body | `terraform console` evaluation of `sha256(join(",", [...]))` with the digest changed in a sandbox copy of `cloud-init-inngest.yml` shows a different hash for the pinned list and an UNCHANGED bare `local.zot_probe_repo`; plus the push apply log for the merge shows `Creation complete` (AC18) |
| "The web repository has no committed pin; its marker says `pin_verdict=none`" | probe header, `model.c4`, runbook | `/usr/bin/grep -a -n 'ZIREF=' apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/cloud-init-inngest.yml` names only the bootstrap repo; the suite row asserting `pin_verdict=none` for a bare element |
| "A pin bump's merge run already targets the probe resource, so the new hash is delivered by the existing path" | runbook, PR body | `gh run view 38151764939 --log` shows `-target=terraform_data.zot_consumer_probe_install` and `Refreshing state` for it; after this change the recreate is read from the first bump's apply log (AC18's shape) |
| "The probe unit starts a run every 60 s and a run is under 60 s" | probe header, AC4 | `/usr/bin/grep -a -n 'OnUnitActiveSec' apps/web-platform/infra/web-zot-consumer-probe.timer`; the worst-case arithmetic is the sum of the `-m 10` bounds in AC4 plus `doppler run` start-up, measured from the run log timestamps in the post-merge read (a start-to-start gap, not a claim about when the timer re-arms) |
| "web-2 keeps the single-repo bare-element probe until its next replace" | runbook (already stated), PR body | the web-2 env file is written at birth only: `/usr/bin/grep -a -n 'web-probe-envwrite' apps/web-platform/infra/cloud-init.yml` and the absence of any `zot_consumer_probe_install_web2` resource: `/usr/bin/grep -a -n 'zot_consumer_probe_install' apps/web-platform/infra/server.tf` |
| "The host probe HEADs the pinned digest of `jikig-ai/soleur-inngest-bootstrap` as committed on main, not the digest this build produced" | workflow comment and step summary | the probe suite rows P1/P9; `/usr/bin/grep -a -n 'ZIREF=' apps/web-platform/infra/cloud-init-inngest.yml` |
| "zot keeps the 5 most recent `v*` tags with `deleteUntagged`" (already in the workflow comment) | unchanged | `/usr/bin/grep -a -n -B2 -A6 'mostRecentlyPushedCount' apps/web-platform/infra/cloud-init-registry.yml` |

## Test Scenarios

Numbering continues the suite's T1-T16; P rows are new.

- P1 both repos healthy, bootstrap pinned (`known/repo,known/second@sha256:<D>`): ping, exit 0; exactly one pin HEAD; marker rows carry `pin_verdict=none` (web) and `pinned` (bootstrap).
- P2 pin 404 with tags 200: no ping, exit 0, the `pinned manifest ... MISSING` line with `ref=` and a trailing `repo=`, marker `pin_verdict=pin-missing`. P2b two pinned elements, the second evicted. P2c two pinned elements, the FIRST evicted.
- P3 pin 401 on the first / second pinned element: exit 3, no ping, the other element's lines still emitted.
- P4 pin 000 (stub transport failure), 503 and 403 (mock): no ping, `pin_verdict` `unreachable` / `wedged` / `unexpected`; the 403 line carries the code.
- P5 `tags/list` 404 / 000 / 503 for a pinned element: no manifest request in the stub argv; `pin_verdict=skipped`.
- P6 bare elements only: no manifest request; `pin_verdict=none`; ping behavior identical to today (the single-repo env of web-2).
- P7 ref grammar: `repo@sha256:<64 hex>` pings; invalid elements (`repo:tag`, `repo:tag@sha256:<hex>`, `repo@sha256:abc`, uppercase hex, `repo@sha512:<hex>`, `repo@`, `repo@sha256:<hex>x`, `repo@sha256:<hex>@sha256:<hex>`) each exit 1 with FATAL, curl never invoked; a trailing-comma list with a pinned element still pings (must-PASS, non-canonical).
- P8 behavioral against the mock: healthy pin => 200 => ping; evicted ref => 404 => no ping; the mock recorded method HEAD and no GET of the manifest path; wrong auth => 401 => exit 3.
- P9 stub curl: the pin request carries `-I` and no `-f`; the credential is NOT on argv and stdin is exactly one `user = "..."` line; the URL is always `/manifests/sha256:<D>`; one curl invocation per bare element, two for a pinned element whose tag list was 200, one for a pinned element whose tag list was not.
- P10 marker: `pin_verdict=` appended after `ts=` and `has_marker` extended to match it (the one deliberate edit to an existing helper); the 30-minute window, and the missing / corrupt / future-dated marker, unchanged. Add a row that a `tags/list` 403 still lands in `unexpected code 403` (`ci-deploy.sh` depends on it) and that the tag request never gets a pin verdict.
- P11 control characters: newline in `ZUSER`, backslash in `ZUSER`, tab in `ZUSER`, tab in `ZTOK`, tab inside a list element => FATAL exit 1, curl not invoked, value not echoed; each row driven RED by a mutated copy of the probe that drops the `[[:cntrl:]]` arm.
- P12 static (T7 extension): the shape rows and the gated `terraform console` row of AC7; `local.zot_probe_repo` is unchanged and bare (the line is byte-identical to origin/main); `local.zot_probe_repo_pinned` is exactly the two-element join; `server.tf`'s `triggers_replace` entry AND its env-file `printf` argument name `local.zot_probe_repo_pinned`; the cloud-init templatefile line still names `local.zot_probe_repo`; the web element is bare; the pin-extraction helper (the same anchored shape as the TF regex, so a reshaped `ZIREF` line reddens the bump PR's CI) against synthetic fixtures H4/H5.
- P13 instrument: `MIN_ASSERTS` equals or is below the measured total and was raised, never lowered.

## Files to Edit

- `apps/web-platform/infra/web-zot-consumer-probe.sh`
- `apps/web-platform/infra/web-probe.tf`
- `apps/web-platform/infra/server.tf` (two lines only: `triggers_replace` entry and the env-file `printf` argument of `terraform_data.zot_consumer_probe_install`)
- `apps/web-platform/infra/web-zot-consumer-probe.test.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated, never hand-edited)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `.github/workflows/build-inngest-bootstrap-image.yml` (one comment block and one step-summary sentence only)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` and its ledger comment)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if the scanner row moved)
- Moves by `archive-kb.sh`: `knowledge-base/project/plans/2026-10-11-chore-delete-zot-entry-gate-plan.md`, `knowledge-base/project/specs/feat-one-shot-7258-delete-zot-entry-gate/{session-state.md,tasks.md}`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10004-probe-head-pinned-manifest/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10004-probe-head-pinned-manifest/decision-challenges.md`

## Open Code-Review Overlap

None. Queried open `code-review` issues for each planned file path (`gh issue list --label code-review --state open`, `jq --arg path ... contains`): no match for the probe, `web-probe.tf`, the probe suite, `model.c4`, the runbook, the workflow, or the discoverability test.

## Non-Goals and tracked deferrals

- The web repository's pin: no committed pin exists; deferred as #10044 (`meta/machinery`, milestone Post-MVP / Later) with re-evaluation criteria (a web birth or replace fails at the pull with `manifest unknown` while the heartbeat is green; the web release flow starts committing a digest pin; the deploy path starts persisting the deployed ref).
- A blob-level check (`crane validate --remote` style): the manifest HEAD detects tag and manifest eviction, not a reclaimed layer (`model.c4`'s restore-path edge records that zot gc can evict a layer while the manifest stays). The build workflow's `crane validate` remains the blob-level gate; this probe is the cheap standing signal.
- `ci-deploy.sh`, `variables.tf`, `cloud-init.yml`, `web-probe-envwrite.sh`: untouched by design (`server.tf` changes in exactly two lines, AC8).
- Pinning hosts other than web-1: a baked pin would rot (Research Reconciliation, cattle pin-rot row); the registry-wide pin is checked from web-1 only.
- CTO suggestion to bound the HEAD at `-m 5`: not applied. One request site with one timeout keeps the single curl text the suite's mutants key on, and the worst case (50 s to a ping on web-1) already fits the cadence; recorded in `decision-challenges.md`.
- A report-only first window for the pin check: recorded in `decision-challenges.md` (operator direction is all-must-pass).
- Accepted trade-offs, stated so the next reader does not rediscover them: (a) the per-host heartbeat now means "this host can consume zot AND, on web-1, the committed pin is servable", so a registry-content fault pages as `soleur-web-zot-consumer-web-1` and the runbook row says so; (b) pin coverage has a single point (web-1): if web-1's probe stops, its own heartbeat goes absent and pages, so coverage is never silently lost, but no sibling re-checks the pin; (c) every pin bump now depends on a web-1 SSH delivery succeeding, and a failed delivery can later false-red on a stale pin (the fault line names `ref=` to tell the two apart).
- A CI-layer alternative (a `crane manifest <repo>@<ZIREF digest>` step at the end of `build-inngest-bootstrap-image.yml` plus a scheduled re-check) was considered (plan-review, DC-5): it fires at push time and cannot see GC, restore or `accessControl` regressions between builds, nor what the host's own pull credential can read; the operator's direction is the host-side probe. Not applied; the workflow comment edit stays.

## Sharp Edges

- `server.tf` is in `apply-deploy-pipeline-fix.yml`'s `paths:` but NOT in the Deploy Pipeline Fix Drift Gate's trigger-file list; do not widen the `server.tf` edit beyond the two named lines, or the second workflow's run stops being a routine no-swap run.
- The cloud-init-bound list MUST stay bare. If a future edit routes `local.zot_probe_repo_pinned` into the templatefile map, every born host bakes a pin that cannot be updated; T7's no-`@` row and Guard 2 row 6 exist for that.
- A `regex()` with one capture group returns a LIST in Terraform; without `[0]` the local is a list and the `join` input is a type error or a wrong value. Evaluate with `terraform console` and keep the static row that asserts the `[0]`.
- The probe suite's sed mutants (b) and (c) key on the curl line's text. Refactoring the curl into one function changes that text; update the mutants in the same edit and prove each landed with `cmp -s`, or they silently stop mutating.
- `curl -I` with `-w '%{http_code}'` and `-o /dev/null` is HEAD; do NOT add `-f` (it destroys the 404 classification) or `--retry` (a probe whose absence is the alarm must not retry its way to green).
- The host `grep` may be ugrep: use `grep -F` for literal assertions and `/usr/bin/grep -a` when a must-match grep returns nothing. semgrep is broken on this host; shellcheck is the gate (compare findings against `origin/main`).
- A Bash call whose text contains the words terraform and apply together is deferred by a hook: write such text with the Write tool, not inside a Bash command.
- `archive-kb.sh` takes one slug and no single slug matches both Step-B artifacts; verify each move with `git status` before committing.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `BASELINE_DECLARED_PROBES` is re-read AFTER the rebase, never copied from this plan (it was 59 at plan time).
- The post-merge observation is telemetry-based; an apply job's overall colour is not evidence of probe delivery. Anchor on the `Creation complete` line of `zot_consumer_probe_install` for T0.
