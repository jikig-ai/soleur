---
title: "fix(inngest): re-pin the bootstrap image to a probe_schema=3 build and bind the pin to the bytes it names"
date: 2026-09-07
slug: fix-inngest-bootstrap-pin-and-guard-hardening
branch: feat-one-shot-7695-inngest-image-pin-probe-schema
issue: 7695
refs: [7695, 7761, 7674, 6894]
closes: []
type: fix
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> **Revised 2026-09-07 [Updated].** Three plan reviews found the prior draft over-built and
> P0-blocked. This revision cuts it from 1209 lines by removing machinery the repo already owns,
> redesigning the carrier guard so it is hermetic, and correcting an inverted premise about #7761.
> The `## Plan Revisions` section at the end records every change and why.
>
> **Lane note.** No `specs/feat-one-shot-7695-inngest-image-pin-probe-schema/spec.md` exists, so
> `lane:` defaulted to `cross-domain` (TR2 fail-closed).
>
> **`closes:` is deliberately empty.** None of #7695, #7761, #7674 or #6894 is resolved by a
> code-only change. The PR body uses `Ref #N` for all four. `Closes` would auto-close them at merge,
> before the remediation each tracks has reached a host.

## Enhancement Summary

**Deepened 2026-09-07**, constrained: no agent fan-out. Two research subagents, a
code-simplicity-reviewer and an architecture-strategist had already run and their findings were
folded in, so a second fan-out would have re-researched settled ground and padded the file. The pass
ran the halt gates mechanically and added depth at four named thin spots.

**Gates run:** 4.5 network-outage (fires on `unreachable`; the L3→L7 table in `## Hypotheses`
answers it), 4.6 user-brand impact (**pass** — threshold present and specific), 4.7 observability
(**pass** — five fields, `command` verb `bash` is allowlisted, no `ssh`), 4.8 PAT-shaped (**pass** —
no matches), 4.9 UI wireframe (**skip** — no UI surface), 4.10 encryption posture (**pass** — 15
fields), 4.11 guard contract (**pass** — `lint-guard-contract.py` green over all three guards, and
each Assembly names a chokepoint rather than today's members). 4.55 downtime/cutover **fired** and
produced a new section.

**What this pass added:** the exact digest-capture invocation with every flag verified live against
the installed CLIs; Guard A's extraction shape, including the permissive-count/strict-parse split
that makes partial extraction red rather than quietly guard less; two missing risk rows (the
tag-with-another-tag's-digest residual, and the derived-boundary false-condemnation hazard); an
explicit note that AC1/AC5/AC9 are process assertions rather than mechanical checks; and a
`### Downtime & Cutover` section carrying a finding no earlier pass had: this PR **arms** a
force-replacement of the sole scheduler, and merging does not fire it — measured, not assumed.

**Deliberately skipped, not padded:** `## Research Insights`, `## Research Reconciliation`,
`## Hypotheses`, `## User-Brand Impact`, `## Domain Review`, `## GDPR / Compliance Gate`,
`## Encryption Posture`, `## Observability`, `## Architecture Decision`, `## Non-Goals`,
`## Plan Revisions`. Each is complete or deliberately scoped; expanding them would have restated
existing content in more words.

## Overview

The dedicated Inngest host runs an image whose bytes predate the code the repository says it runs.
Measured, not inferred — the host's own hourly probe row, read off-box:

```
SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=inactive vector_active=active
redis_active=active uptime_s=1620603 boot_id=cb4e3bb0-b625-45d4-8da1-dde39e4a7dbe
image_ref=10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.25@sha256:f23a2a0d730d…faba49
instance_id=hetzner-162809678 cli_version=1.19.4-2c8385ba8 cutover_flag=aborted
```

That row carries **no `probe_schema` field at all**, so Guard 2
(`tests/scripts/lib/inngest-host-dark-gate.sh`, predicate G4) verdicts `stale_schema` and the gated
`inngest-volume-recut` apply target is unreachable. The same stale image is why the merged #7761
root-execution fix has not reached the machine it protects.

This plan re-pins the bootstrap image to a build carrying HEAD's bytes, binds the pin to those bytes
with a guard that has no network dependency, upgrades the two tag-only pin sites to digest pins, and
repairs the one carrier defect that would otherwise ride the new tag unfixed. It dispatches nothing:
no cutover, no host replacement, no recut, no change to the Hetzner volume.

## Research Insights

### Premise Validation (Phase 0.6) — measured this session

Telemetry was self-pulled with
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`, every count paired with a
control in the same window. Nothing below is inferred from configuration.

| # | Claim | Probe | Result |
|---|---|---|---|
| A | The live host runs the pinned image and emits no `probe_schema` | Better Stack, 48 h, `SOLEUR_INNGEST_SERVER_PROBE` | **HOLDS** — 51 probe rows; `probe_schema=3` → 0, `probe_schema=2` → 0, `redis_keys` → 0. Newest 2026-09-07 19:02:37. `image_ref` names the exact pinned digest |
| B | The live host runs the **pre-#7761** flip script | Better Stack, 48 h, `inngest-cutover-flip` state rows | **HOLDS, and it is the sharpest fact in this plan** — 4,204 `emit_state` rows (oldest 09-05 19:24:27, newest 09-07 19:23:07; ~30 s cadence), of which **zero** carry the `guard` field. Zero `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` |
| C | The app-dispatch outage is fixed and holding | Better Stack, since 2026-09-07 16:20:00 | **HOLDS** — `ECONNREFUSED 10.0.1.40:8288` last seen 16:19:59.348; **zero** since, against a control of **9,748** rows in the same window (5,835 from `soleur-web-platform`), newest control row 19:20:59. The channel is instrumented and retention covers the window |
| D | Crons are healthy | same window | **HOLDS** — `cron-membership-health` 19:17:01, `cron-ghcr-token-minter` 19:00:13 and 18:40:01 |
| E | #7761's code fix already merged | `gh pr view 7768` | **HOLDS** — merged 2026-09-03T15:16:38Z, `closingIssuesReferences` empty (prose `Ref #7761`, deliberate). Merge commit `ce639ccd1`, an ancestor of `origin/main` |
| F | HEAD carries the seam gate | read `inngest-cutover-flip.sh` | **HOLDS** — content anchor `if [[ "${1:-}" != "--fixture-seams" ]]`; **fifteen** seam names (12 `CUTOVER_*`, 3 `INNGEST_CUTOVER_*`); refusal marker present. The last list entry has no trailing backslash, so a `\\$`-anchored grep miscounts 14 |
| G | The current pin predates that fix | `git log -1 --format=%ci 5116247a4` | **HOLDS** — 2026-08-20 00:41:16 +0000, two weeks earlier; it moved four literals v1.1.24 → v1.1.25 |
| H | The tag's tree lacks both markers | `git show vinngest-v1.1.25:<file>` | **HOLDS** — `probe_schema=3` → 0 at the tag, 3 at HEAD; `GUARD_REV` → 0 at the tag, 2 at HEAD. This is Guard A, run by hand |
| I | The #7761 follow-through can measure nothing today | run the probe read-only | **HOLDS, and it is a NEW finding** — `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after` does not exist and nothing in the repo writes it, so the probe returns `TRANSIENT: reason=boundary_unknown`, exit 2 — four days past its `earliest=2026-09-05` |
| J | `crane` is available in `deploy-script-tests` | read `.github/workflows/infra-validation.yml` | **REFUTED** — see *Correction 2* |
| K | `emit_state()` is new in #7768 | `git log -S` | **REFUTED, and the plan must not restate it** — `emit_state()` predates #7768 (25 occurrences at `ce639ccd1^`; introduced by #6218, revised by #7457). Only the `guard` **field** is new: `readonly GUARD_REV="7761"`, added by `ce639ccd1` and by nothing else. Call it *the guard-rev stamp*, never *emit_state* |

### Correction 1 — the #7761 framing was inverted, and the inversion drove the whole prior plan

The prior draft treated #7761 as an unfixed open P1 root-execution seam that a re-tag would bake
into a new image. Measured facts E–G and B say the opposite: the fix merged on 2026-09-03, the pin
was set on 2026-08-20, and the live host is running the pre-fix script **right now**, every thirty
seconds. **Rebuilding and re-pinning is the remediation for #7761, not a new exposure.** It is the
only delivery vehicle — the follow-through script's own header says so: *"delivery is a tag -> image
build -> digest bump -> HOST REPLACE of the fleet's sole scheduler."*

That reframes the plan's urgency and its verification. The guard-rev stamp is a **positive delivery
signal**: only the post-#7761 script emits it, so its presence in a post-boundary row is proof the
new bytes are on the host. This plan makes that signal reachable in two places — inside CI, where
Guard A asserts the pinned tag's tree contains `GUARD_REV="7761"`, and later off-box, where the
follow-through reads it from Better Stack.

### Correction 2 — the prior plan's live registry arm would have redded every PR, permanently

Verified against `.github/workflows/infra-validation.yml`, `deploy-script-tests`: `ubuntu-24.04`,
`timeout-minutes: 20`; setup is checkout (`fetch-depth: 0`, `fetch-tags: true`), `setup-terraform`,
`apt-get install cloud-init`, `apt-get install nftables`. `grep -c crane` returns **0**. The job body
contains **zero** `secrets.*` references and the workflow `permissions:` is `contents: read` with no
job-level override, so `GITHUB_TOKEN` carries no `packages: read`. And
`ghcr.io/jikig-ai/soleur-inngest-bootstrap` is private — `cloud-init-inngest.yml` records the AP-016
read PAT as revoked, *"the GHCR leg cannot authenticate and returns a guaranteed 401"*.

So `crane digest` there fails twice: not installed, and anonymous 401. The governing precedent
already exists — `zot-image-staleness.test.sh` is **NO NETWORK, BY DESIGN**: *"`crane digest`
cross-checks are a documented sidecar procedure … not a test dependency — a test that needs the
network reddens on upstream's outage."* Both guards below are hermetic, and live tag→digest
resolution goes where the credentials already are: the apply workflow, which already runs
`docker login ghcr.io` plus `docker buildx imagetools inspect … --format '{{.Manifest.Digest}}'`
immediately before the host is born or replaced.

### Correction 3 — ~65% of the prior plan rebuilt machinery the repo owns

- **Guard B's hermetic arm already exists.** The "digest pin governs BOTH legs" block in
  `cloud-init-inngest-bootstrap.test.sh` extracts the GHCR and zot digests, asserts each matches
  `^sha256:[0-9a-f]{64}$`, and asserts both legs pin the same digest — for `cloud-init-inngest.yml`
  only. The work is to **extend** it to `cloud-init.yml`'s two sites, which carry no digest at all.
- **`host-image-coherence-preflight.sh` is not a reusable Guard A.** It lives under
  `apps/web-platform/infra/scripts/`, *receives* an already-resolved `@sha256` ref and explicitly does
  not re-resolve a tag, uses `docker create` + `docker cp` (no crane), parses no cloud-init file, and
  hinges on `local.host_scripts_content_hash` — for which the inngest host has **no equivalent**
  (`grep content_hash\|filesha256` over `inngest*.tf` returns zero). Generalising it means minting a
  terraform local, templating it into `cloud-init-inngest.yml` and adding a boot verify block: new
  infrastructure. Tracked as follow-on, not built here.
- **The proposed lifecycle marker duplicates two live signals** — the hourly probe row quoted in the
  Overview and the 30-second `emit_state` rows. Cut.

### Property List and Cut List (Phase 0.6b)

**Properties this work must buy:**

- **P1** A host provisioned from the pinned image emits a probe row G4 accepts.
- **P2** An edit to any file the image bakes, merged without a re-tag and re-pin, fails CI.
- **P3** Every pin site names the same tag and the same digest, and no site is tag-only.
- **P4** No generated host artifact can carry the output of a command the renderer never meant to run.
- **P5** The #7761 follow-through can reach a verdict without an operator supplying anything.

**Cut List — removed before anything researched or designed them:**

| Mechanism | Property it was for | Disposition |
|---|---|---|
| Guard B live `crane digest` arm in `deploy-script-tests` | P3 | **Cut.** Correction 2 — unprovisioned and unauthenticated; the hermetic arm carries P3, live resolution moves to the apply path |
| Guard A via `crane export` + diff, or a build-emitted carrier manifest, or a parsed `cp` block | P2 | **Cut, all three.** `crane export` fails for Correction 2's reasons; a manifest is a number a human transcribes, which proves good faith rather than bytes; a parsed `cp` block relocates the snapshot one file over. Replaced by the git-only design below |
| A new `SOLEUR_INNGEST_SERVER_LIFECYCLE` marker + `SyslogIdentifier` + `vector.toml` Source 4 entry | observability | **Cut.** Correction 3 — duplicates two live signals. Removes the Source 4 edit, the `journald-config.test.sh` two-sided lockstep, the probe `TimeoutStartSec` rework and the vendor-quota arithmetic with it |
| Post-`daemon-reload` on-host render self-verification | P4 | **Cut.** Never-executed on-host code riding a tag whose delivery is the point; if it misbehaves the next recut costs another tag cycle |
| A new hermetic render harness (`inngest-bootstrap-render.test.sh`) | P4 | **Cut.** A whole new file for one already-diagnosed defect; a delimiter assertion in the existing suite buys the same property |
| Historical credential-exposure measurement against Better Stack | — | **Cut to a tracked `type/security` issue.** Holding a P1 root-execution delivery hostage to a third-party log query is backwards. Deadline and the two decisive facts move with it |
| Retiring the existing semver-max drift check | — | **Cut. The prior plan's R14 is reversed** — see *Correction 4* |
| A new ADR ordinal (ADR-205) | — | **Stays cut.** The rule belongs in the guard's own header; ADR-199 gets a one-sentence amendment instead |

### Correction 4 — keep the semver-max drift check; there is no red window on `main`

`cloud-init-inngest-bootstrap.test.sh` AC6/AC6b compares each file's pin tag against
`git tag --list 'vinngest-v*' | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`
(`sort -V` deliberately: plain `sort` ranks v1.1.9 above v1.1.10, the bug class that hid the last
drift), plus `PIN_REF_COUNT == 2 && DISTINCT_PINS == 1` per file. Empty tag set → hard FAIL in CI,
visible SKIP locally.

The prior plan retired it, claiming it would otherwise red `main` permanently. That is wrong. After
merge the pin reads v1.1.27 and the newest tag is `vinngest-v1.1.27`, so `main` is green. The only
red interval is **inside this PR**, between the tag-push commit and the pin-bump commit — an
ordinary RED-first interval. Keeping the check preserves coverage and deletes the prior plan's one
net-negative-diff change, its red-window risk row, and the redness half of UC-1.

### Institutional learnings that bind this plan

- `2026-07-18-image-baked-and-latent-is-a-claim-verify-a-published-tag-exists.md` — **this class,
  first occurrence.** Its rule is `git show <tag>:<carrier-file> | grep -c <marker>` non-zero for the
  new tag and zero for the old. Restated twice, failed twice. Guard A stops restating it and runs it.
- `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`
  — the tag push and the pin bump are one coupled unit; this is why Phase 2's ordering is mechanical.
- `2026-03-19-docker-base-image-digest-pinning.md` — when a digest is present Docker ignores the tag,
  so a tag bumped without its digest silently runs the old image.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — the two
  tests each guard below must survive: *what is the cheapest edit that breaks the property while
  leaving the guard green?*, and *the harness needs its own mutation rows, with a must-PASS fixture
  that differs from the canonical.*
- `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — the #6536
  session spent a host replace on a defect that did not exist. The comment block Phase 1 repairs is
  that session's own write-up.

### Governing ADRs

- **ADR-199** (`accepted`) — destructive clearance is a measurement: `inngest-volume-recut` cannot
  reach `terraform plan` unless the dark gate returns the literal `dark`; confirm token
  `RECUT-INNGEST-VOLUME`; `expected_inngest_volume_id` pins the Hetzner id. Amended by this plan.
- **ADR-142** + its 2026-09-03 addendum — `redis_keys > 0` (or unreadable) ⇒ ADR-142 governs
  unamended and the destructive path is refused outright; `redis_keys == 0` under all three pins ⇒
  ADR-199's recut is available.
- **ADR-140** — encryption posture is a design-time default with a resolvable-evidence ledger.
- **ADR-030** (amended) — the loopback-binding claim is struck; isolation is
  `hcloud_firewall.inngest` deny-all plus host-local nftables.

### Observability layer (`hr-observability-layer-citation`)

Per `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`, this change adds
**no new observability layer**. It consumes two existing ones: **Layer 3**, the Vector journald
shipper (`vector.toml`), which already carries `inngest-server-probe` and `inngest-cutover-flip` into
Better Stack source 2457081 — untouched by this PR; and **CI red**, for the three guards.

### Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` (63 open) and searched
every body for each path in `## Files to Edit`. Zero matches.

## Research Reconciliation — Spec vs. Codebase

| Brief's claim | Codebase reality | Plan response |
|---|---|---|
| "Bump BOTH the tag AND the sha256 digest at all four pin sites" | Two of the four (`cloud-init.yml`'s `IREF=` and `ZIREF=`) carry **no digest at all** | Those two are *upgraded* to digest pins, not merely bumped — a distinct change the brief reads as symmetric |
| "Harden the drift guard to compare DIGESTS not just tags" | The existing guard compares the digest **between the two legs of one file** and the tag across both files; **nothing binds the digest to the bytes** | Both hardenings ship: Guard B extends the digest binding to all four sites, Guard A binds the pin to HEAD's carrier bytes. The second is the durable one |
| #7761 must be resolved before re-tagging | Inverted — the fix merged 2026-09-03; the live host runs the pre-fix script (measured, B) | Re-tagging **is** the remediation. `Ref #7761` |
| #7695 "build the gated apply_target" | Already built and merged by `000fa4715` | This PR does not close it; it makes the gate's verdict reachable |
| #7674 "boots but never serves" | Refuted — see H4 | Retitle, do not close |

## Hypotheses

**Network-outage gate (Phase 1.4) fired** on the token `unreachable`. Unlike the prior draft, there
*is* a real network symptom in scope, so the L3→L7 order is answered rather than waived.

| Layer | Finding |
|---|---|
| **L3 — firewall allow-list** | `hcloud_firewall.inngest` is deny-all; 10.0.1.40:8288 is unreachable from the web host **by design** (ADR-030 as amended). This is the correct posture while the host is dark and the fix was **not** to open it |
| **L3 — DNS / routing** | Not applicable — 10.0.1.40 is a private-network literal, so no resolution step exists to fail |
| **L7 — TLS / proxy** | Not applicable — plain HTTP on a private network, no TLS and no proxy in the path |
| **L7 — application layer** | **Answered and resolved.** `ECONNREFUSED 10.0.1.40:8288` ran at ~600/h for 18 days; the fix repointed the client at the co-located scheduler (`cloud-init.yml` content anchor `INNGEST_BASE_URL=http://host.docker.internal:8288`). Measured: last error 2026-09-07 16:19:59.348, zero since against 9,748 control rows. **Repointing back is the second half of the cutover and is out of scope** — doing it early is what caused the 18-day outage |

| # | Hypothesis | Status |
|---|---|---|
| H1 | The pinned image predates the `probe_schema=3` emitter, so G4 verdicts `stale_schema` regardless of host replacement | **CONFIRMED — measured twice.** Statically (H, above) and live (A): the running host's probe row carries no `probe_schema` field |
| H2 | The heartbeat unit is corrupted by command substitution in an unquoted heredoc executing `` `doppler secrets` `` | **CONFIRMED — three independent signals.** `inngest-bootstrap.sh` opens the heartbeat unit heredoc with an unquoted delimiter (content anchor `cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF`), uniquely so among generated artifacts; the unit's comment body carries five backtick pairs, the one at body line 27 being `` # self-check runs `doppler secrets` as ROOT (with HOME=/root and the same ``; and the journald signature matches its substituted output exactly — ~30 × `Missing '=', ignoring line`, `Unknown key name '\| … \| de'`, rendered lines 27-56 |
| H3 | The rendered table carried secret **values**, not only names | **UNKNOWN, and moved out of this PR.** Recorded in the tracked `type/security` issue with its window (2026-07-16 → 2026-08-20) and its deadline (Better Stack source 2457081 retains 90 days; the boot ages out 2026-11-18) |
| H4 | The host "boots but never serves" (#7674's title) | **REFUTED — measured.** At `uptime_s=49` the probe read `http_code=200 server_active=active`. The single non-noop FSM row in the 2026-08-19 → 09-07 archive is `{"flag":"rolled-back","reason":"rolled-back","start_ts":"2026-08-20T00:53:23Z"}`, whose `start_ts` is the exact second of `inngest-server`'s graceful journald shutdown. The rollback arm executing as specified |
| H5 | Once the emitter is live the next verdict is `store_populated`, not `dark` | **PROJECTED, UNMEASURED.** Redis loaded 689 keys from AOF at the 2026-08-20 boot and `inngest-server` has been down since, so nothing consumed them; the live image emits no `redis_keys`, so this cannot be measured until the image ships. An ordering constraint, recorded, not solved here |

## User-Brand Impact

- **Brand-survival threshold:** `single-user incident` — a single user's in-flight job
  payloads sit in the Redis AOF on the host this change delivers to.

**If this lands broken, the user experiences — nothing.** That is measured, not assumed. Their
scheduled work keeps running: app dispatch goes to the co-located scheduler
(`INNGEST_BASE_URL=http://host.docker.internal:8288`), crons fired at 19:17:01, 19:00:13 and
18:40:01 today, and `ECONNREFUSED 10.0.1.40:8288` has been at zero since 16:19:59 against 9,748
control rows. The blast radius is stated once, under `## Infrastructure (IaC)` → Apply path.

**The user-facing harm is the status quo persisting.** The `soleur-inngest` host is live — 18.75
days of uptime, `redis_active=active`, its flip timer polling every ~30 seconds — and it is running
the **pre-#7761** flip script: 4,204 state rows in 48 hours, **zero** carrying the guard-rev stamp.
On that machine a write to any secret **name** in the `soleur-inngest/prd` Doppler config is
arbitrary command execution as root within thirty seconds, against a host whose Redis AOF holds
in-flight Inngest job payloads — per ADR-199, user prompts and agent output. This PR is the only
delivery vehicle for the fix that closes it. Every day it slips is another day a merged P1 fix is
undelivered.

**If this leaks, the user's data is exposed via** the generated heartbeat unit file, into which the
renderer wrote `doppler secrets` stdout for the `soleur-inngest/prd` config. That config carries
`INNGEST_REDIS_PASSWORD`, and the write sets no `umask` — unlike its sibling env-file write, which
is wrapped in `( umask 0137 && … )`. Exposure window opened 2026-07-16 and is **STILL OPEN**: 2026-08-20 is when the PIN was set, not when exposure ended. `git show vinngest-v1.1.25:...inngest-bootstrap.sh` still carries the unquoted delimiter and all five executing spans, and v1.1.25 is the image the host runs today, so the defective renderer fires on every bootstrap invocation. It closes only when a host replace delivers v1.1.27. Whether the
rendered table carried values or only names is **UNMEASURED** and moves to the tracked issue; the
decisive negative that must not be re-derived under pressure is that `INNGEST_REDIS_LUKS_KEY` did
not exist during that window (`inngest-redis-luks.tf` first committed 2026-09-04), so the passphrase
that #6894's remediation depends on is uncompromised.

**Brand-survival threshold:** `single-user incident` — a single exposed `INNGEST_REDIS_PASSWORD`, or
a single root-execution on the scheduler, is a path to one user's prompts and agent output.

## Files to Edit

- `apps/web-platform/infra/inngest-bootstrap.sh` — quote the heartbeat unit heredoc delimiter
  (content anchor `cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF`) and move its two interpolations to
  `@@DOPPLER_BIN@@` / `@@HEARTBEAT_SCRIPT@@` + `sed -i`, the house pattern already used for
  `@@DARK_ARM@@` and `@@FLIP_GUARD_EXECSTARTPRE@@`. **Leave the `DOPPLEREOF` env-file write
  unquoted** — Phase 1.4 states the exemption and its reason once.
- `apps/web-platform/infra/cloud-init-inngest.yml` — bump tag **and** digest at both pin sites
  (`IREF=`, `ZIREF=`); rewrite the drift-guard comment whose current last line reads *"a v1.1.25 tag
  pinned to v1.1.24's bytes — silently, since the drift guard only reads tags"* to describe the new
  binding. Preserve the note explaining the tag literal is retained so the semver-max guard stays armed.
- `apps/web-platform/infra/cloud-init.yml` — bump the tag at both sites **and add the digest to
  both**, which they lack today.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — add Guard A and extend Guard B's
  existing digest-identity block to `cloud-init.yml`'s two sites; add Guard D. **Bump the affected
  anti-vacuity floor in the same edit.** Measured baseline: the suite passes 129/129 today and
  carries **several** exact-equality floors, one per section — `Guard 1 anti-vacuity … (expected 40,
  ran 40)` and `Row7 anti-vacuity … (expected 7, ran 7)` among them. Each added assert must bump the
  floor of *its own* section; a guard added to the wrong section reds a floor nobody edited.
- `apps/web-platform/infra/inngest-host.test.sh` — widen the IREF-shape assertion (content anchor
  `grep -qE '^[[:space:]]*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$'`)
  to cover `cloud-init.yml`'s two sites, which will now also carry digests. **Two shapes are needed,
  not one widened regex:** that file's `IREF=` is bare (`IREF=ghcr.io/…`, so the existing anchor is
  reusable) while its `ZIREF=` is quoted and variable-prefixed (`ZIREF="$ZURL/jikig-ai/…"`). Guard
  B's H2 harness row records the same divergence.
- `.github/workflows/apply-web-platform-infra.yml` — add a live tag↔digest re-resolution to the
  existing inngest host-replace preflight, beside the `docker buildx imagetools inspect` call that
  already runs there with GHCR credentials.
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` — derive the boundary from telemetry
  when neither `FLIP_ROLLOUT_AFTER` nor the sidecar is set, under the provenance split in Phase 4.0.
  **Its header block is amended in the same edit**, so the committed prose records that the
  stale-boundary FAIL arm is scoped to a *supplied* boundary; leaving that sentence unqualified beside
  a provenance-scoped implementation is the contradiction Phase 4.0 exists to prevent.
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh` — cover the derived arm: the
  never-FAIL cap (AC12b), digest-only matching against a zot-prefixed `image_ref`, `dt`
  normalisation, and override precedence.
- `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md`
  — one-sentence amendment to the Phase-2 → Phase-3 interlock.

## Files to Create

**None.** Every guard lands in a suite that already exists and is already wired into CI. This is
deliberate: the prior draft's new harness was the single largest source of its length.

## Implementation Phases

The ordering is mechanical, not stylistic. The image is a **content carrier**: anything this PR
changes in one of the ten baked files reaches the host only if the image is built from a commit that
already contains the change. Guard A is authored **first** and is RED against today's tree — because
today's pin really is stale (premise H). Its red state is the production defect, not a synthetic
mutation, which is what makes authorship precede consumption by construction.

### Phase 0 — Preconditions (no writes)

0.1 Confirm `vinngest-v1.1.27` is unclaimed across every `origin/*` ref, not only `origin/main`
    (tags currently run v1.1.18 … v1.1.25). **Check for a same-named BRANCH, not only a tag** —
    `actions/checkout` resolves a bare `ref:` to a remote branch before a tag, so a branch of that
    name would subvert the build (Guard A residual 3). A tag listing alone does not answer this.
0.2 Record the baselines the acceptance criteria compare against. Measured at plan time:
    `grep -c '@sha256:' apps/web-platform/infra/cloud-init.yml` → **0**;
    `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → **129/129 passed, exit 0**;
    the two per-section floors (**40** and **7**); and the **unquoted-heredoc count in
    `inngest-bootstrap.sh`, which is 2 today** — AC6 asserts a delta from that number and it was
    previously unrecorded. Re-record all four immediately before Phase 1 so the deltas are measured
    against a fresh baseline rather than this one.

### Phase 1 — Carrier repair and the three guards (RED first)

1.1 Write **Guard A**, **Guard B**'s extension and **Guard D** into
    `cloud-init-inngest-bootstrap.test.sh`, with the mutation and harness matrices from
    `## Guard Contract`. Bump the anti-vacuity floor in the same edit.
1.2 Confirm all three are RED against HEAD before any fix lands. Guard A reds on the real stale pin;
    Guard B reds on `cloud-init.yml`'s two tag-only sites; Guard D reds on the unquoted heartbeat
    delimiter.
1.3 Quote the heartbeat delimiter and substitute its two interpolations by sentinel. Every directive
    in the unit body must survive **byte-identical** — `PrivateTmp=true`,
    `RuntimeDirectory=inngest-heartbeat`, `RuntimeDirectoryPreserve=yes` and
    `SyslogIdentifier=inngest-heartbeat` each have their own prior incident.
1.4 **Leave the `DOPPLEREOF` env-file write unquoted.** It is unquoted deliberately, to interpolate
    `$TOKEN` and `$DOPPLER_PROJECT`; its body is four lines with no backtick and no `$(`; and it is
    wrapped in `( umask 0137 && cat > … )` precisely so the token never lands in a world-readable
    file even momentarily. A sentinel rewrite writes a temp file and renames, destroying that
    guarantee — it would regress CWE-732 to fix nothing. Encode the exemption **in Guard D's own
    source**, with the `umask` rationale inline, so the next reader does not "fix" it.
1.5 Guard D goes green. Guards A and B stay RED until Phase 3 — that is the coupling.

### Phase 2 — Bake (freeze, then tag)

2.1 **Freeze first, tag second.** Drive review to green on every carrier file *before* the tag is
    pushed, then land no further carrier edit. Tagging ahead of review makes every review finding on
    a baked file force a fresh tag and rebuild.
2.2 Push tag `vinngest-v1.1.27` at the frozen commit. The build triggers on
    `push: tags: ['vinngest-v*.*.*']`, publishes to GHCR, cosign-signs `${IMAGE}@${DIGEST}` keyless,
    and mirrors to zot.

**No workflow change is needed to read the digest back, and an earlier draft of this plan was wrong
about that.** It asserted the digest reaches only `$GITHUB_STEP_SUMMARY` and proposed uploading it as
an artifact. Measured: the cosign step's second-to-last line is `echo "Signed ${IMAGE}@${DIGEST}"` —
plain stdout, in the run log, and it names the digest that was actually **signed**, which is a
stronger provenance anchor than a freshly-computed artifact. `gh run view <id> --log` is therefore
already a by-command, never-transcribed read. Deleting that item also keeps Phase 2.1's freeze real:
the build workflow leaves this PR's edit set entirely.

### Phase 3 — Pin (the coupled unit)

3.1 Read the digest **programmatically** from the tagged run's log, anchored on the signing line —
    never transcribed, never eyeballed. Every flag below was verified live against the installed CLIs
    on 2026-09-07 (`gh run view --help` → `--log`, `--json`; `gh run list --help` → `-w`, `-b`, `-L`,
    `--json`; `docker buildx imagetools inspect --help` → `--format`). Nothing here is recalled.

```bash
TAG=vinngest-v1.1.27
IMAGE=ghcr.io/jikig-ai/soleur-inngest-bootstrap

# The run id for THIS tag's build. -w pins the workflow, -b the tag ref, so a
# concurrent build of another tag cannot be picked up.
RUN_ID=$(gh run list -w build-inngest-bootstrap-image.yml -b "$TAG" -L 1 \
           --json databaseId --jq '.[0].databaseId')
[ -n "$RUN_ID" ] || { echo "no build run for $TAG"; exit 1; }

# Anchor on the SIGNING line, not on any sha256 in the log. The log also carries
# the inngest-cli and vector tarball sha256s; a bare sha256 grep would match those.
DIGEST=$(gh run view "$RUN_ID" --log \
         | grep -oE "Signed ${IMAGE}@sha256:[0-9a-f]{64}" \
         | grep -oE 'sha256:[0-9a-f]{64}' | sort -u)

# Exactly one. Two means the run signed twice (a retry that moved the digest);
# zero means the signing step did not complete. Both are halts, not warnings.
[ "$(printf '%s\n' "$DIGEST" | grep -c .)" -eq 1 ] || { echo "ambiguous digest"; exit 1; }
```

**Independent cross-check, and what a disagreement means.**
`docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{.Manifest.Digest}}'` re-resolves
the tag from the registry. It requires a GHCR login, so where credentials are unavailable the
cross-check **SKIPs visibly** and the PR body records that it skipped — it never silently passes.
A **disagreement halts the phase and is never reconciled by choosing one value**: it means either
the tag was re-pushed between signing and inspection (the digest moved — Guard A residual 1) or
the tag was re-pointed (residual 2). Both require re-cutting the tag, not picking a winner.

3.1b **Why the signing line and not the step summary.** An earlier draft proposed adding an artifact
    upload to the build workflow on the premise that the digest reached only `$GITHUB_STEP_SUMMARY`.
    That premise was false — the cosign step also echoes `Signed ${IMAGE}@${DIGEST}` to stdout — and
    the signing line is the better anchor besides: it names the digest that was actually signed,
    rather than one recomputed afterwards.
3.2 Bump all four pin sites to `v1.1.27@sha256:<digest>`, adding the digest to `cloud-init.yml`'s two
    sites. Guards A and B go green — and green **only** against these values.
3.3 Verify the deliberately-stale negative-control fixture in
    `cloud-init-inngest-zot-pull-mutation.test.sh` (content anchor
    `docker create --name soleur-inngest-bootstrap-extract ghcr.io/…:v1.1.24@sha256:6cdaa63d…`) is
    still stale. A sweep that "helpfully" updates a negative control destroys the control.
3.4 Guard A must also run against the **post-rebase tree**. A rebase onto a `main` that touched a
    baked file re-opens the gap after the guard last passed.

### Phase 4 — Make the #7761 follow-through measurable

Premise I: the probe returns `TRANSIENT: reason=boundary_unknown` forever, because
`inngest-cutover-flip-rollout-7761.after` does not exist and nothing writes it. The obvious fix —
have the apply workflow commit the sidecar — was rejected: `apply-web-platform-infra.yml` contains no
`git commit` / `git push` / commit-back action of any kind, so it would mean adding write-back
machinery to a gated destructive-apply path for one timestamp. And asking a person to write the file
is forbidden outright (`hr-exhaust-all-automated-options-before`, `hr-ship-message-no-operator-checklist`).

**Derive the boundary from telemetry instead.** The replace has an already-shipped observable: the
earliest `SOLEUR_INNGEST_SERVER_PROBE` row whose `image_ref` carries the pinned digest. The probe
already queries Better Stack, so this needs no sidecar, no workflow write-back and no human. The six
sub-steps below are not polish — each closes a defect that would otherwise make the derivation
inert, or worse, actively wrong.

#### 4.0 The exit-contract conflict, resolved by PROVENANCE — one arm wins, and the other is scoped

The committed script's header states a rule this plan must not silently contradict:

> *"With neither, TRANSIENT. But a boundary that is OLD with still no markers is a FAIL, not a
> TRANSIENT: at a 30-second cadence 'not yet' expires in minutes, and leaving it TRANSIENT forever
> makes a permanently bricked scheduler indistinguishable from a rollout nobody has run."*

That reasoning is **correct, and it stays**, because it rests on the boundary being *authoritative* —
a human or an apply asserted "the replace happened at T", so silence after T really is a bricked
scheduler. A **derived** boundary carries no such assertion. It is an inference, and it can be wrong
in exactly the direction that manufactures a false condemnation: any re-pin to a digest some host
already reported — a rollback re-pin above all — derives a boundary in the past, on the machine the
rollout was supposed to replace. `boundary_age > STALE_AFTER_S` (3600) then converts silence into
`FAIL reason=stale_image`, whose message tells the operator *"the replace kept the old image … the
seam exposure is still live"* **for a replace that never happened** — on a `type/security` tracker.
The script's own header warns against certifying a rollout with evidence from the machine it
replaced; an unbounded derivation reintroduces that hazard inverted, as a false accusation.

**Resolution: the two rules govern disjoint provenances, so neither is overridden.**

| Boundary provenance | Verdicts reachable | Rationale |
|---|---|---|
| **Supplied** — `FLIP_ROLLOUT_AFTER` or the committed `.after` sidecar | PASS / FAIL / TRANSIENT, **unchanged** | Authoritative. The header's stale-boundary FAIL arm applies verbatim; nothing about today's behaviour changes |
| **Derived** — from telemetry, when neither is supplied | **PASS or TRANSIENT only. Never FAIL** | An inference must not condemn. Its job is to let a *real* rollout reach PASS automatically; it is not entitled to declare a regression |

**The anti-brick signal is routed, not lost.** Where the derived arm *would* have failed, it exits 2
with a reason that names the missing authority rather than blaming the host — the plan's proposed
token is `derived_boundary_stale_supply_authoritative_boundary`, distinct from both
`boundary_unknown` and `stale_image`. The reader is told the derived boundary is old and silent and
that supplying `FLIP_ROLLOUT_AFTER` re-arms the authoritative FAIL arm. A bricked scheduler is
therefore still distinguishable — via a reason string that demands the authoritative input, not via
a condemnation built on an inference.

**The never-FAIL property must live in the script's own comments, not only here.** A later edit that
adds a FAIL exit under the derived arm would restore the false-accusation hazard silently. Encode it
as a single guarded exit helper whose comment states the rule and its reason, so the rule is
structural rather than remembered. **The committed header must be amended in the same edit** to
record the provenance split; leaving the header's unqualified sentence standing beside a
provenance-scoped implementation is exactly the contradiction this section exists to prevent.

#### 4.1-4.6 The six integration requirements

4.1 **Order the derivation AFTER its own preflight.** The boundary block is pure env/file I/O and
    sits ahead of everything it would need: the `BETTERSTACK_QUERY_*` check, the `jq` check, and the
    `mine()` definition all come later. Keep the *supplied* read where it is — it has no
    dependencies — but when nothing is supplied, do not exit there. Record that the boundary must be
    derived and continue, then derive after the `jq` preflight. This also yields the right reason for
    free: absent credentials already exit `credentials_unprovisioned`, which is more accurate than a
    boundary complaint.

4.2 **Match on the DIGEST ONLY, never the whole ref.** Measured: the live host's row reads
    `image_ref=10.0.1.30:5000/jikig-ai/…@sha256:f23a2a0d…` — the **zot** ref, because
    `cloud-init-inngest.yml` reassigns `IREF="$ZIREF"` on a successful zot pull and writes that value
    to `/etc/default/soleur-inngest-image`, which the probe reads. The pin literal the derivation
    reads is the **GHCR** ref. A whole-ref comparison therefore never matches and the derivation is a
    permanent silent no-op — the exact class this work exists to retire. Extract
    `@sha256:<64hex>` from the pin and compare against the row's `image_ref` **field**, isolated from
    the decoded object rather than substring-matched against the raw line (#6475). Guard B asserts
    both legs carry the identical digest, which is what makes digest-only matching sound.

4.3 **Normalise the timestamp before validating it, never instead of validating it.**
    `betterstack-query.sh` returns ClickHouse `dt` values that are space-separated with no `T` and no
    `Z`, so handing one to the existing
    `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` validator exits 2
    `boundary_unparseable` — a permanent no-op wearing a different reason string. Normalise
    explicitly (`date -u -d "$dt" +%Y-%m-%dT%H:%M:%SZ`) and then run the **existing** validator over
    the result. Bypassing the validator for a derived value would let a malformed boundary widen the
    window to "any time", which is the failure the validator exists to prevent.

4.4 **`mine()` cannot supply the timestamp; a sibling is required.** It emits `.message` only, and
    the probe row carries no time field inside its message — the emitter writes a flat `key=value`
    string. The timestamp exists only as the row's outer `dt` column. So a sibling selector must
    capture the outer object before descending into `raw` — binding the row, then emitting
    `"\(row.dt) \(.message)"` — rather than parameterising `mine()`. This is a new function, not a
    flag.

4.5 **Inherit the two-field host filter.** The derivation must reuse `mine()`'s
    `.host == $FLIP_HOST and .host_name == $FLIP_HOST_NAME` predicate (#6616 — `host_name` can lie,
    which is why both are checked). This matters more after this PR than before it: the co-located
    web host pulls and execs the same bootstrap image and emits the same
    `SOLEUR_INNGEST_SERVER_PROBE` marker, and this PR bumps **all four** pin sites to one digest — so
    a colocated web host would emit rows carrying the pinned digest. Dormant today
    (`web_colocate_inngest` defaults false), latent tomorrow.

4.6 **"First" is a slice, and the plan says so rather than implying otherwise.** `mine()` passes
    `--limit 500` and the query returns the **newest** N rows before re-sorting, so on a wide window
    the earliest row *found* is not necessarily the earliest that exists — past roughly 500 probe
    rows (~21 days at the hourly cadence) the derivation sees a newest-slice. The script's own header
    names this class: *"reporting a slice as the window."* Two mitigations, and the second is the
    load-bearing one: raise the limit for the derivation query specifically, and — decisively —
    accept that a slice can only make the derived boundary **later** than the true replace. A late
    boundary can delay a PASS; under 4.0's never-FAIL cap it can never manufacture a condemnation.
    The residual is bounded to "PASS arrives on a later sweep", which is the correct direction for an
    inference to err in.

4.7 **What falls out.** Because the derivation reads the pin, every future re-pin moves the boundary
    automatically and the probe measures the *newest* delivery rather than the first one ever — with
    the rollback-re-pin hazard that would otherwise create neutralised by 4.0.

### Phase 5 — Framing corrections and the record

5.1 Retitle #7674 to match H4 — it did not "boot but never serve"; it bound `:8288`, served HTTP 200,
    and the flip FSM's rollback arm stopped it by design. **Do not close it**: its follow-through
    probe is the only standing signal this work is unfinished.
5.2 Amend ADR-199's Phase-2 → Phase-3 interlock (see `## Architecture Decision`).
5.3 File the follow-on tracking issues listed in `## Non-Goals`.
5.4 Record H5's ordering constraint in the PR body, quoting ADR-142's addendum on which world
    `redis_keys > 0` places the recut in. Nothing is drained, flushed or `FLUSHALL`ed.

## Architecture Decision (ADR/C4)

### ADR — an amendment, not a new ordinal

**Ship: a one-sentence amendment to ADR-199.** Its Phase-2 → Phase-3 interlock states that
`apply_target=inngest-host-replace` makes the new cloud-init go live and the boot emit
`probe_schema=3`. That premise is **false while the pin predates the emitter** — the replace boots
the *pinned* image, so it does not discharge `stale_schema` and the interlock's own escape hatch is
closed. That is a false premise inside an `accepted` ADR gating a destructive apply. The amendment
adds the precondition (the pin must carry the emitter, enforced by Guard A) and points at the guard.

**No new ADR ordinal.** The invariant Guard A encodes — *pin correctness is a property of the pinned
bytes relative to HEAD, not a property of the tag string* — belongs in the guard's own header
comment, where the person about to break it will read it, not in a 205th document they will not open.

### C4 views

All three model files were read in full — `model.c4`, `views.c4`, `spec.c4` — not grepped for the
feature's noun. Enumerated: **external human actors** — none added or changed. **External systems /
vendors** — GHCR and the self-hosted zot registry (both already modelled as the Inngest host's image
supply path) and Better Stack (already modelled as the sink Vector ships to); no new vendor edge.
**Containers / data stores** — none added; the Inngest host, its Redis AOF volume and the Vector
agent are all present. **Actor↔surface access relationships** — unchanged; no ownership or sharing
boundary moves. **Derived cardinalities** — no cron monitor, heartbeat slug or workflow count moves,
so `apps/web-platform/test/c4-count-parity.test.sh` is unaffected; it is run green regardless rather
than reasoned about.

**Conclusion: no C4 impact**, with one in-scope confirmation during implementation — that no element
*description* asserts the Inngest host's configuration arrives by cloud-init alone, since the baked
carrier files arrive via the OCI image. If such a description exists, correcting it is in scope and
`c4-code-syntax.test.ts` / `c4-render.test.ts` gate the edit.

### Sequencing

The decision is true at merge. Nothing waits on a later slice.

## Infrastructure (IaC)

Recorded rather than skipped because the Phase 2.8 detector matches `cloud-init.*\.ya?ml$`, and a
silent skip on a plan that edits cloud-init is indistinguishable from an unreviewed one.

### Terraform changes

**None.** No `.tf` file is edited, no resource added, no provider introduced, and no variable —
`TF_VAR_*` or otherwise — created or required. `inngest.tf` and `vector.tf` are read only.

### Apply path

**Cloud-init plus the existing OCI content carrier**, unchanged. No `-replace`, no taint, no
`terraform apply` of any kind is part of this plan. Blast radius on merge: **zero on running hosts** —
nothing reaches `soleur-inngest` until a host replacement, and none is dispatched here. Downtime:
none. `## Downtime & Cutover` below carries the measurement that supports this, rather than leaving
it asserted — and names the force-replace this PR *arms* but does not fire.

### Downtime & Cutover

**The gate fires, and the answer is not the obvious one.** `hcloud_server.inngest` deliberately
carries **no** `lifecycle.ignore_changes = [user_data]` — only `ignore_changes = [ssh_keys]` — and
its own comment states the consequence: *"this host is the SOLE scheduler, so every cloud-init edit
force-replaces it → a cron-outage window — gate all cloud-init edits to the maintenance-window
`apply_target=inngest-host` dispatch."* This PR edits `cloud-init-inngest.yml`. So it **arms a
force-replacement of the sole scheduler.**

**Merging does not fire it, and that is measured rather than assumed.** No `hcloud_server` of any
kind appears in any `-target=` on the merge-triggered apply — `grep -c 'target=hcloud_server'` over
`apply-web-platform-infra.yml` returns **0**. The replace is reachable only through the gated
`apply_target=inngest-host` dispatch. This is the measured support for the blast-radius claim below,
which was previously asserted without it.

**The armed replace is the delivery vehicle, not a hazard to mitigate.** Phase 8 of the #7761
follow-through names exactly this: *"tag -> image build -> digest bump -> HOST REPLACE of the fleet's
sole scheduler."* A cloud-init edit that did **not** arm a replace would be the defect — it is what
lets the new bytes reach the host at all.

**The cron-outage window the comment warns about is currently empty, and this is the strongest
zero-downtime argument available.** The three facts are measured, not projected: the host is already
dark (`server_active=inactive`, and it has been for 18.75 days); app dispatch runs against the
co-located scheduler (`INNGEST_BASE_URL=http://host.docker.internal:8288`), with zero
`ECONNREFUSED 10.0.1.40:8288` since 16:19:59 against 9,748 control rows; and crons are firing on that
co-located scheduler right now. **Replacing a host that is serving nothing costs nothing.** The
window ADR-100 warns about opens only after the *second* half of the cutover repoints dispatch back
at 10.0.1.40 — which is explicitly out of scope here.

One thing the replace must not lose, and it is not downtime: the Redis AOF lives on a **separate**
`hcloud_volume` that survives the replace. The re-attach is verified on replace (the git-data
precedent), and that verification belongs to the gated dispatch, not to this PR.

### Distinctness / drift safeguards

The `dev` / `prd` distinction is untouched: this PR writes no Doppler value in either config and
reads none at build time. The drift safeguards **are** the deliverable — Guard A binds the pinned
tag's bytes to HEAD's carriers, Guard B binds tag to digest across every pin site, and the
pre-existing semver-max check is retained rather than replaced (Correction 4). No
`lifecycle.ignore_changes` is involved and no state file is written, so no secret enters one.

### Vendor-tier reality check

No provider resource is created, so no free-tier creation limit applies. Better Stack ingest volume
is unchanged: the lifecycle marker that would have added ~24 rows/day/host is cut, and this PR emits
nothing new from any host.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_SERVER_PROBE — the host's hourly row, already live, carrying image_ref,
        server_active, vector_active, redis_active, uptime_s, boot_id, instance_id, cli_version and
        cutover_flag; after this change also probe_schema=3 and redis_keys. Alongside it, the
        inngest-cutover-flip state rows carry exit_code, dbsize, reason, flag, start_ts and — once
        delivered — guard=7761
  cadence: probe hourly (OnBootSec=90s, OnUnitActiveSec=1h); flip state rows every ~30s
  alert_target: Better Stack Logs source 2457081, via the Vector journald shipper already on the host
  configured_in: apps/web-platform/infra/inngest-bootstrap.sh and inngest-cutover-flip.sh.
                 vector.toml is deliberately untouched — no Source 1 or Source 4 change

error_reporting:
  destination: Better Stack via Vector; systemd unit failures additionally surface on the existing
               inngest-heartbeat channel through its OnFailure= target
  fail_loud: yes — all three guards fail CI red, and each carries an own-dispatch mutation row, so a
             guard that checks nothing reds rather than passing on zero

failure_modes:
  - mode: a carrier file is edited and merged without a re-tag and re-pin, so the edit is inert on
          the dedicated host
    detection: Guard A, over every COPYed path
    alert_route: CI red
  - mode: a tag is bumped without re-resolving its digest, pinning the new tag to the old bytes
    detection: Guard B across all four pin sites, plus live re-resolution on the apply path
    alert_route: CI red (hermetic); apply aborts before create/destroy (live)
  - mode: a generated host artifact interpolates or executes something the renderer never meant to
    detection: Guard D, over every heredoc writing a generated artifact
    alert_route: CI red
  - mode: the new bytes never reach the host, so the merged #7761 fix stays undelivered
    detection: scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh — post-boundary state rows
               carrying guard=7761, against a boundary derived from the first probe row bearing the
               pinned digest, so it needs nothing from an operator
    alert_route: the daily follow-through sweeper; #7761 stays open until it reads PASS

logs:
  where: Better Stack Logs source 2457081, shipped by the Vector agent on the host
  retention: unchanged — 90 days on that source; no source configuration is edited

discoverability_test:
  command: bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
  expected_output: "BOOTSTRAP_SUITE_OK"
  # A sentinel the suite prints ONLY on a fully green run, and nowhere else in the file.
  # Not a tautology: reaching it requires every assertion to pass AND the unconditional-assertion
  # floor to hold, so a deleted guard section reds it (mutation-proven — removing Guard A gives
  # `111 unconditional ... expected >= 123`, exit 1, sentinel absent).
  # The two obvious alternatives were measured and rejected: `163/163 passed` is HOST-dependent
  # (163 with the full toolchain, 125 with terraform absent), and a bare `OK` appears twice in a
  # FAILING run, so substring-matching it would pass on failure.
```

The wiring property is fully hermetic, so no `credentials_required` declaration is made. The *live*
property — that a host emits a `probe_schema=3` row — cannot be verified by this PR at all, because
no host runs the new image until a replacement, and none is in scope. Claiming otherwise would be an
acceptance criterion that cannot be met.

### Affected-surface observability (§2.9.2)

The Inngest host is a blind execution surface: its bootstrap runs inside an OCI image at first boot.
The in-surface requirement is satisfied by signals that already exist and were read this session
rather than assumed — the probe row's `image_ref` field discriminates *which bytes are running* from
*which bytes the repo holds* in one event, and the guard-rev stamp discriminates *delivered* from
*not delivered* in one field. Both were used above to establish premises A, B and H, which is the
strongest available evidence that they are reachable off-box.

## Encryption Posture

Detection fires on `cloud-init.*\.ya?ml$`. This plan introduces **no persistent store and no new
cross-component connection**; the section is completed because the credential finding touches the
posture of an existing row.

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis (10GB, ext4, attached to the inngest host)
    mechanism: plaintext-exception
    evidence: scripts/encryption-posture-ledger.json, the inngest_redis row; the device binding is
              resolvable through the volume and its attachment, not by name similarity
    defends_against: nothing at rest today — that is the finding, not an omission
    does_not_defend: physical media recovery, snapshot exfiltration, any read of the detached volume.
                     The AOF holds in-flight job payloads — user prompts and agent output
    disclosed_as: the open plaintext row tracked by #6894
    live_verification: the probe emits data_mount_src at probe_schema=3, so the mount substrate
                       becomes readable off-box once this pin ships. It cannot verify THIS row while
                       the mechanism is plaintext (it reports the by-id device either way), but it
                       becomes the live verification the moment the mechanism flips to luks
    unchanged_by_this_plan: true

  - store: the generated heartbeat unit file on the dedicated host
    mechanism: plaintext-on-host, and this plan removes the content that made it sensitive
    evidence: the unquoted heredoc that renders it sets no umask, unlike its sibling env-file write
              which uses ( umask 0137 && … )
    defends_against: after this plan, nothing needs defending — the delimiter is quoted, the
                     substitution cannot execute, and the file no longer receives doppler stdout
    does_not_defend: the exposure written since 2026-07-16, which is STILL LIVE on the running image. That
                     moves to the tracked type/security issue, not to this change
    disclosed_as: to be determined by that issue; the disposition is not pre-selected

in_transit:
  - connection: Vector agent on the dedicated host → Better Stack ingest
    tls: yes
    cert_verification: on
    does_not_defend: anything a log line itself carries — Vector does not scrub credentials embedded
                     in a message. This is why ADR-106 §5's purity rule binds every marker on this
                     channel; no new marker is added by this plan
    disclosed_as: the existing log-shipping disclosure; no new vendor and no new connection
```

No `exception` block is added: the one `plaintext-exception` in scope already carries its ledger row
with `tracking_issue: #6894`, and this plan neither creates a new exception nor alters its terms.

## Guard Contract

Three guards. Each mutation matrix was derived from the design before the guard was written.

**Anti-vacuity floors — each new guard needs its OWN, and this is not optional.** Measured: the
target suite has **two** exact-equality floors, not one — `ZG_SECTION_ASSERTIONS == 40` over the zot
gate's span, and `R7_ASSERTIONS == 7` over the Row 7 span — and **no whole-suite floor**. Guard B's
extension target sits inside the `ZG_` span, so extending it does require bumping 40 in the same
edit. Guards A and D are **new sections**, and that is the trap: appended after the last floor they
change neither number, so an AC that only says "bump the floor" is trivially satisfied while the two
new guards ship with no anti-vacuity floor at all — which is precisely what Guard A's H1 harness row
depends on. Inserted *before* the `ZG_` floor instead, they inflate a number whose own comment scopes
it to the zot gate, conflating three unrelated inventories. So: **mint `GUARDA_ASSERTIONS == N` and
`GUARDD_ASSERTIONS == N`**, following the file's own `ZG_`/`R7_` open-and-close pattern.

### Guard A — carrier coherence (the durable one)

**Property.** Every file the image bakes is byte-identical, at the pinned tag, to HEAD's copy of that
file.

**Assembly.** Hermetic, git-only, zero network. For each carrier path, compare
`git show <pinned tag>:<path>` against HEAD's copy. The pinned tag is read from the pin literal, so
the guard follows the pin rather than a hardcoded version.

**The path set is derived from the `cp` staging lines, not the `COPY` lines, and the two are
cross-checked.** Measured in `.github/workflows/build-inngest-bootstrap-image.yml` (**read by this
guard, never edited by this PR**): the `COPY` lines carry build-context **basenames** only
(`COPY vector.toml /vector.toml`), while the `cp apps/web-platform/infra/<f> "$BUILD_DIR/<f>"`
staging lines carry the real repo paths. Deriving from `COPY` would smuggle in an unstated
`apps/web-platform/infra/` prefix assumption, and mutation row 3 would then hold only for an eleventh
file that happens to live in that directory. So: derive paths from `cp`, derive basenames from
`COPY`, and assert the two sets have the **same cardinality and the same basename set** — which also
catches a file staged but never baked, or baked but never staged.

**The dispatch floor is an exact cross-derived count, not `> 0`.** A zero-floor catches total
breakage but not *partial* extraction: a future `COPY --chmod=0755 x /x`, a multi-source
`COPY a b /dst/`, or a glob shrinks the derived set from ten to N without ever reaching zero, and the
guard would report green over the files it still parses. The floor is therefore `count(cp) ==
count(COPY)` and both `== N`, with N read from the file rather than hardcoded.

**Extraction shape, and how it refuses rather than degrades.** Measured against the real workflow:
`grep -cE '^[[:space:]]*COPY '` returns exactly **10**, the token `COPY` appears nowhere else in the
file, and the heredoc does not break the parse — so this is not fragile *today*. The shape below is
what keeps it non-fragile tomorrow.

```bash
WF=.github/workflows/build-inngest-bootstrap-image.yml

# Repo paths — from the `cp` staging lines, which carry them. Two fields exactly:
# `cp <src> "$BUILD_DIR/<dst>"`. Anything else is a form we do not understand.
mapfile -t CP_PATHS < <(grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$WF" \
                        | awk '{print $2}' | sort -u)

# Baked basenames — from the `COPY` lines. STRICTLY two operands; a third field
# (a flag, a second source) is a form the extractor must NOT silently accept.
mapfile -t COPY_NAMES < <(grep -E '^[[:space:]]*COPY [^ ]+ [^ ]+[[:space:]]*$' "$WF" \
                          | awk '{print $2}' | sort -u)

# REFUSE, do not degrade. A COPY line the strict pattern rejected still counts as a
# COPY line, so a shrunk set is a parse failure — never a smaller job done quietly.
TOTAL_COPY=$(grep -cE '^[[:space:]]*COPY ' "$WF")
[ "${#COPY_NAMES[@]}" -eq "$TOTAL_COPY" ] || die "unparsed COPY form: parsed ${#COPY_NAMES[@]} of $TOTAL_COPY"
[ "${#CP_PATHS[@]}"   -eq "$TOTAL_COPY" ] || die "cp/COPY cardinality mismatch: ${#CP_PATHS[@]} vs $TOTAL_COPY"

# Same FILES, not merely the same count — a swap keeps cardinality intact.
diff <(printf '%s\n' "${COPY_NAMES[@]}") \
     <(printf '%s\n' "${CP_PATHS[@]}" | xargs -n1 basename | sort -u) || die "cp/COPY basename set mismatch"
```

The load-bearing line is `TOTAL_COPY`: it is counted with a **permissive** pattern while the operands
are parsed with a **strict** one, so any `COPY` form the strict pattern cannot read shows up as
`parsed 9 of 10` and reds. An extractor that counted only what it could parse would report ten of ten
and quietly stop guarding the eleventh file — which is mutation row 6.

The instrument is already provisioned: `deploy-script-tests` checks out with `fetch-depth: 0` and
`fetch-tags: true`, and `main-health-monitor.yml` mirrors that checkout.

**Soundness chain, and the three residuals it does not close.** pinned digest (immutable bytes) ← the
build run of tag T ← the git tree at tag T ← byte-identical to HEAD's carriers. The build triggers
only on `push: tags: ['vinngest-v*.*.*']` or a `workflow_dispatch` whose `ref` input is regex-pinned
to `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` *before* checkout, so no free-form ref can build tag T from
another commit. **This proves the tag→source binding, not the registry bytes.** Three residuals, all
requiring repo write — the workflow's own declared collaborator threat model — and all stated here
rather than hidden:

1. **A default dispatch moves the tag's digest.** The workflow header is explicit: the non-`mirror_only`
   path re-runs `docker build` and re-pushes the same tag, so *"the tag's GHCR digest MOVES."* Only
   `mirror_only` cannot move it. (An earlier draft of this section called `mirror_only` "the sole
   re-push path" — that was wrong, and it contradicted the sentence after it.) The conclusion
   survives, because a rebuild still builds from tag T's tree; the guarantee a reader would infer
   does not.
2. **Git tags are mutable.** A force-push re-pointing `vinngest-v1.1.26` after the build leaves Guard
   A comparing HEAD against the *new* tree while the pinned digest carries the old one. No
   tag-protection ruleset in this repo asserts otherwise.
3. **The dispatch regex validates a name shape, not a ref type.** `actions/checkout` resolves a bare
   `ref:` to a remote **branch** of that name before a tag, so a branch named `vinngest-v1.1.26`
   would build from the branch head. Phase 0.1 therefore checks for a same-named branch, not only a
   same-named tag.

**Cosign is NOT a mitigation on this path, and the plan must not imply it is.** The workflow's own
"WHAT THIS SIGNATURE IS, AND IS NOT" block states the signature is *"not a provenance claim any
consumer verifies"* — `ci-deploy.sh` pins `COSIGN_IDENTITY_REGEXP` to a Fulcio subject that matches
neither this workflow nor the tag pattern, and *"the inngest deploy branch does not call
verify_image_signature at all — measured, zero occurrences."*

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Change one byte of `inngest-bootstrap.sh` without re-tagging | RED |
| 2 | Change one byte of `vector.toml`, leaving `inngest-bootstrap.sh` compliant | RED — a **second member after a compliant first**; a guard that stops at the first file passes this repo's actual failure |
| 3 | Add an eleventh staged file (`cp` + `COPY`) and edit it without re-tagging | RED, **with no guard edit** — the set is derived from the `cp` lines, which carry real paths |
| 4 | Point the pin at a tag that does not exist, or run where tags were never fetched | RED, naming the unresolvable tag — never "nothing to compare, pass". One row, because an unfetched tag and a nonexistent one take the same `git show` failure path |
| 5 | Drop one file from the `cp` block while leaving it in `COPY` (or vice versa) | RED — the cross-check catches staged-but-not-baked and baked-but-not-staged, which a single-list derivation is structurally blind to |
| 6 | Shrink the derived set from ten to nine by adding a `COPY` form the extractor cannot parse | RED, reporting the count mismatch — the guard's **own dispatch**, and an exact count rather than `> 0`, because partial extraction never reaches zero |

**Harness rows.**

- **H1 (must-RED, mutates the SUITE):** hollow the comparison so it returns success unconditionally.
  The suite must still red, via **Guard A's own new exact-equality section floor** (see the note on
  floors below) plus the compared-file count fixed to the cross-derived N. A floor of `>= 1` would
  not see this.
- **H2 (must-PASS, NOT the canonical):** a carrier file whose working-copy **mtime and mode** differ
  from the tag's, with byte-identical content, must PASS. The comparison is content-only and the
  contract explicitly permits that difference. A guard that reds on mtime is a guard nobody keeps.

### Guard B — tag↔digest binding across every pin site

**Property.** Every pin site names the same tag and the same 64-hex digest, both present, with no
tag-only site. **This is cross-site *agreement*, and agreement alone would pass on four consistently
wrong digests** — the correctness half is carried by Guard A (the bytes) and AC5 (the digest equals
the one the build signed). The three are only sound together, and the guard's header must say so.

**Assembly.** Extends the existing digest-identity block, which today covers
`cloud-init-inngest.yml`'s two legs, to `cloud-init.yml`'s two. Sites are found by grepping
`apps/web-platform/infra/` for `soleur-inngest-bootstrap:`; **test fixtures are excluded by an
explicit rule**, not by happening not to match — `cloud-init-inngest-zot-pull-mutation.test.sh` pins a
deliberately stale `v1.1.24@sha256:6cdaa63d…` as a negative control, and a sweep that "helpfully"
updates it destroys the control.

**Hermetic only** — Correction 2. Live tag→digest re-resolution runs on the apply path, beside the
`docker buildx imagetools inspect` call that already has GHCR credentials, immediately before the
host is created or destroyed, where a stale resolution actually costs something.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Bump the tag at `cloud-init-inngest.yml`'s `IREF=`, leaving the digest | RED — the exact #7630 shape |
| 2 | Change the digest at one site, leaving the tag | RED |
| 3 | Change only `cloud-init.yml`'s `IREF=`, leaving the other three compliant | RED — second site after a compliant first |
| 4 | Remove the digest from a site that has one, leaving a tag-only pin | RED — a silent downgrade to today's `cloud-init.yml` state must not pass |
| 5 | Point the site sweep at a directory with no pins | RED, reporting `0 pin sites found` — the guard's **own dispatch** |
| 6 | Write `v1.1.26@sha256:<v1.1.25's digest>` at **all four** sites | **GREEN on both hermetic guards — this is the known residual, recorded rather than hidden.** See below |

**The residual neither hermetic guard closes, stated plainly.** Row 6 is the exact production defect
this plan exists to remediate, and it survives Guard A (v1.1.26's tree *is* HEAD's carriers) and
Guard B (four sites, one tag, one well-formed digest, no tag-only site). Nothing in the tree can bind
a digest to a tag without a registry read, and Correction 2 establishes that no PR-gating job can
perform one. Cosign does not help — the deploy path never verifies it.

Two things bound the residual, and both are real:

1. **The pin has exactly one consumer.** Nothing reads it until a host is created or replaced. A
   wrong digest sitting on `main` cannot reach a running host, cannot affect the co-located
   scheduler, and cannot touch user-visible behaviour. Its cost is delayed detection, not an incident.
2. **That one consumer re-resolves live and aborts first.** The apply path already logs into GHCR and
   runs `docker buildx imagetools inspect` before create and before destroy, and this plan adds the
   tag↔digest comparison there. A divergent pin aborts the apply rather than booting old bytes.

The honest summary is therefore: **on the hermetic side, AC5 is the sole control** — a process
assertion that the digest was read by command from the run that signed it, never typed. That is
weaker than a guard and is named as such here, not asserted away.

**Harness rows.**

- **H1 (must-RED):** replace the cross-site comparison with `true`. A checked-in negative-control
  fixture — a pin whose digest is known-wrong — must still red the suite.
- **H2 (must-PASS, non-canonical):** the `ZIREF=` sites' differing quoting and registry prefix
  (`"$ZOT_EP/jikig-ai/…"` and `"$ZURL/jikig-ai/…"` versus the bare `ghcr.io/…` of `IREF=`) must PASS.
  The contract permits the prefix to differ; it is the tag and digest that must not.

### Guard D — quoted delimiters on generated artifacts

**Property.** Every heredoc that writes a generated host artifact uses a non-expanding delimiter, so
no value in its body can be interpolated or executed at render time.

**Assembly.** Every heredoc in `inngest-bootstrap.sh` that writes a generated artifact, derived by
grep over **all four write forms** — `cat > "$X" <<`, `cat >> "$X" <<`, `tee "$X" <<` and
`{ … ; } > "$X" <<` — matching all three unquoted delimiter shapes, `<<WORD`, `<<-WORD` and
`<< WORD`. Both widenings are deliberate: today every heredoc in the file is the `cat >` form and
every delimiter is `<<WORD`, so a narrower assembly would be *accurate today and silently narrower
than its own property* the first time someone writes `tee` or `<<-`. **Scoped to that one file:** the
build workflow's Dockerfile heredoc is legitimately unquoted — it must expand `${INNGEST_VERSION}` —
and a repo-wide rule reds the build on day one.

**One exemption, identified by NAME rather than by line, carrying a content assertion.** The
invariant is: *exactly one unquoted delimiter exists, it is named `DOPPLEREOF`, and its body contains
no backtick and no `$(`.* Naming it rather than anchoring a line number is deliberate — a line-anchor
exemption breaks on any refactor that moves the write, which turns an unrelated edit into a red
suite. The content half is what keeps the exemption honest: it grants "may interpolate", never "may
execute", and cannot silently widen if that body later gains a backtick. Its rationale (Phase 1.4)
goes inline in the guard's source, not only in this plan.

Measured baseline for the assembly: `inngest-bootstrap.sh` carries exactly ten `cat > … <<` sites, of
which exactly two are unquoted today — the heartbeat unit and `DOPPLEREOF`. After Phase 1.6 the
expected count is one.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Unquote any one delimiter | RED — the count rises to two |
| 2 | Unquote a delimiter sitting *after* several compliant ones | RED — proves the scan does not stop at the first match, the failure a `head -1` implementation would pass |
| 3 | Add a new `cat > "$X" <<NEWEOF` with an unquoted delimiter | RED — the assembly is structural, not a fixed list |
| 4 | Add a backtick to the **exempt** body | RED — the exemption grants interpolation, never execution |
| 5 | Make the grep match nothing | RED, reporting `0 heredocs found` — the guard's **own dispatch** |

**Harness rows.**

- **H1 (must-RED):** narrow the pattern so it inspects only the first match. The dispatch floor reds.
- **H2 (must-PASS, non-canonical):** the exempt `DOPPLEREOF` write itself — unquoted, and therefore
  the opposite of every other delimiter in the file — must PASS. This is a real permitted difference
  the contract names, not a fixture invented to satisfy the ritual.

## Acceptance Criteria

**Three of these are process assertions, not mechanical checks, and the distinction is stated rather
than blurred.** AC1 and AC9 require evidence *pasted into the PR body*; AC5 requires that the digest
was *read by command rather than typed*. A reviewer can confirm the evidence is present and
well-formed, but nothing in CI can confirm it was produced honestly. They are listed as criteria
because they are the strongest available control on their properties — AC5 in particular is the only
hermetic-side control on the digest residual — not because they are enforceable. Every other AC below
is a command whose output decides it.

### Pre-merge (PR)

- **AC1** For every path in the build workflow's `COPY` list, `git show vinngest-v1.1.27:<path>` is
  byte-identical to HEAD's copy. Asserted by Guard A, and the per-file output is pasted into the PR
  body — not a summary count.
- **AC2** The same comparison against `vinngest-v1.1.25` is RED for at least
  `inngest-bootstrap.sh` and `inngest-cutover-flip.sh`, demonstrating the guard detects the defect
  that motivated it. Measured baseline: `probe_schema=3` → 0 at v1.1.25 and 3 at HEAD; `GUARD_REV`
  → 0 at v1.1.25 and 2 at HEAD.
- **AC3** `git show vinngest-v1.1.27:apps/web-platform/infra/inngest-cutover-flip.sh | grep -c 'GUARD_REV="7761"'`
  is non-zero. This is the in-PR half of #7761's delivery: the new tag's tree carries the stamp the
  follow-through looks for.
- **AC4** All four pin sites carry the same tag and the same 64-hex digest, and
  `grep -c '@sha256:' apps/web-platform/infra/cloud-init.yml` returns `2` where it returns `0` today.
- **AC5** The digest written into the pins equals the digest the tagged build run **signed**, read
  from that run's log by command (anchored on the `Signed <image>@<digest>` line). The command and
  its output go in the PR body. No digest in this PR was typed by hand.
- **AC6** A grep for all three unquoted-heredoc forms over `inngest-bootstrap.sh` returns exactly
  `1` match, and it is the `DOPPLEREOF` env-file write. `1` and not `0`: an AC asserting `0` would
  drive a change that regresses the `umask 0137` guarantee (Phase 1.4).
- **AC7** `git diff -- apps/web-platform/infra/inngest-bootstrap.sh` shows **exactly** the delimiter
  quote plus the two sentinel substitutions inside the heartbeat unit body, and no other line in that
  body. `PrivateTmp=true`, `RuntimeDirectory=inngest-heartbeat`, `RuntimeDirectoryPreserve=yes` and
  `SyslogIdentifier=inngest-heartbeat` are each named and each confirmed unchanged in that diff. The
  diff *is* the evidence; no captured fixture is created, which is what keeps `## Files to Create`
  honest at **None**.
- **AC8** Every mutation row in all three Guard Contract matrices has been executed and observed RED,
  and every harness must-PASS row observed GREEN. The evidence is the harness's per-row output.
- **AC9** Every anti-vacuity floor whose section gained an assertion was bumped in that same edit,
  and the suite's total rises from its measured 129/129 baseline to exactly the expected new count —
  asserted per section, not as a single total, because the floors are per-section exact equalities.
- **AC10** `git diff origin/main -- apps/web-platform/infra/vector.toml` is empty — asserted as a
  whole-file diff, not as per-source greps, which would pass on a file changed elsewhere.
- **AC11** The deliberately-stale fixture pin in `cloud-init-inngest-zot-pull-mutation.test.sh` still
  names a version older than the new pin.
- **AC12** Run read-only against live telemetry, `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`
  exits 2 with reason `boundary_underivable digest=<pinned>` — **not** `boundary_unknown`, and not a
  verdict on the rollout. An earlier draft of this AC asserted the opposite and was incoherent: this
  PR pins a brand-new digest and dispatches no replacement, so by construction **zero** probe rows
  carry it at merge, and there are no "post-boundary rows" to lack when no boundary was derived. The
  new reason token is what makes the before/after distinction real — before, the probe could not even
  ask the question; after, it asks and reports precisely which digest it found no host reporting.
  Both reasons go in the PR body. A verdict on the merits is reachable only after a host replace,
  which is out of scope by instruction.
- **AC12b** The derived arm cannot return exit 1 under any input. Asserted by a test that supplies a
  deliberately ancient derived boundary with zero post-boundary markers — the shape that returns
  `FAIL reason=stale_image` on the supplied arm — and observes exit 2 with the routed reason instead.
  The same test supplies that identical boundary through `FLIP_ROLLOUT_AFTER` and observes exit 1,
  proving the authoritative arm is unchanged and that the split is by provenance rather than by a
  weakened rule.
- **AC13** ADR-199's Phase-2 → Phase-3 interlock carries the added precondition, and a grep of the
  amended section shows it no longer asserts that a host replace alone makes the boot emit
  `probe_schema=3`. **No new ADR ordinal is minted by this PR.**
- **AC14** The PR body uses `Ref #7695`, `Ref #7761`, `Ref #7674`, `Ref #6894` — never `Closes` — and
  states in its own words that #7674's "boots but never serves" title is refuted, citing the
  `uptime_s=49` / `http_code=200` / `server_active=active` row and the single non-noop FSM row.
- **AC15** The full test battery for the touched shards passes, invoked through each suite's own
  entry point rather than a hand-enumerated file list.

### Post-merge

**None.** No operator step exists in this plan and no automatable step has been deferred: the tag
push, the digest resolution and the pin bump all run as commands. Host replacement, cutover, recut
and any change to the Hetzner volume are **out of scope by instruction** — a different piece of work,
gated by ADR-199 and blocked on a measurement this PR makes possible but does not perform.

## Test Scenarios

**Every guard scenario lives in `## Guard Contract` and is bound by AC8**, which requires each
mutation row observed RED and each harness must-PASS row observed GREEN, with per-row output. They
are deliberately **not** restated here: a second copy of the matrices is a second thing to keep in
sync and asserts nothing the first does not.

What the matrices do not cover is Phase 4's boundary derivation, which has no guard:

| # | Scenario | Expected |
|---|---|---|
| T1 | No row carries the pinned digest — **the state at merge, by construction** | Exit 2, `boundary_underivable digest=<pinned>`. A boundary is never derived from an absent observable |
| T2 | A row carries the pinned digest via the **zot** `image_ref` prefix rather than the GHCR one | Boundary derived correctly — the digest, not the registry prefix, is the match key. The live host's row is zot-prefixed, so this is the common case, not the edge |
| T3 | `FLIP_ROLLOUT_AFTER` or the `.after` sidecar is set | The override wins, derivation does not run, and the header's stale-boundary FAIL arm applies unchanged. Nothing that works today stops working |
| T4 | A raw ClickHouse `dt` (`2026-09-07 19:02:37`) is derived | Normalised to `2026-09-07T19:02:37Z`, then passed through the **existing** validator — never around it |
| T5 | An ancient derived boundary with zero post-boundary markers | Exit **2**, `derived_boundary_stale_supply_authoritative_boundary` — never exit 1. This is the false-`stale_image` hazard, and it is the single most important row in the plan |
| T6 | That identical boundary supplied via `FLIP_ROLLOUT_AFTER` | Exit **1**. The control proving T5 tested the *provenance split* and not a weakened rule |
| T7 | A row from the co-located web host carrying the same pinned digest | Ignored — the two-field `host`/`host_name` filter (#6616) is inherited, so a colocated host cannot supply the dedicated host's boundary |

A dark-gate fixture pair for H5's projected `store_populated` verdict is deliberately **out of
scope**: that gate is already built and merged, this PR does not touch it, and H5 is recorded as
projected rather than solved.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A review fix, rebase or squash lands after the tag is pushed, so the pin carries bytes that no longer match HEAD | This is exactly what Guard A detects, and Phase 3.4 requires it to run on the post-rebase tree. The guard is not only a regression net for future PRs — it protects **this** PR from its own sequencing |
| Guard A's soundness rests on the tag's tree rather than the registry's bytes | Stated in the guard's own Assembly rather than hidden. The residual is covered by the immutable digest pin, keyless cosign signing, and the live re-resolution on the apply path. The alternative — a registry read in `deploy-script-tests` — is unavailable (Correction 2) and would red every PR |
| Adding assertions reds the exact `ZG_SECTION_ASSERTIONS == 40` floor | AC10 makes the bump part of the same edit. This is a known, mechanical property of that suite, not a surprise |
| The heredoc rewrite silently drops a directive whose absence caused a prior incident | AC8 diffs directive lines against a pre-change fixture and names the four load-bearing directives individually. `PrivateTmp=true` and `SyslogIdentifier=inngest-heartbeat` each have their own recorded incident (#6536, twice) |
| The derived #7761 boundary manufactures a PASS from an absent observable | Phase 4.2 fails closed: no row carrying the pinned digest ⇒ TRANSIENT, exactly as today. T12 tests that arm |
| Guard A reds `main` for any later PR that touches a carrier file, with no bounded recovery | This is the intended cost — it is precisely what did **not** happen twice before — but it must be stated, not discovered. Recovery is bounded and named: cut a tag, wait for the build, land the pin bump in the same PR. Any PR touching a carrier file is a re-pin PR by construction, and the guard's failure message must say so in those words |
| **A tag paired with another tag's digest passes both hermetic guards** — `v1.1.26@sha256:<v1.1.25's digest>` is green on Guard A (the tree matches) and green on Guard B (four sites, one tag, one well-formed digest), and the host then boots the old bytes | **The plan's sharpest residual, and it is un-gated hermetically.** Correction 2 establishes no PR-gating job can read the registry, and the build workflow's own header states cosign is "not a provenance claim any consumer verifies" — the inngest deploy branch never calls verification. Bounded by two facts, not by a guard: the pin has exactly one consumer (nothing reads it until a host is created or replaced), and that consumer re-resolves live and aborts before create/destroy. On the hermetic side **AC5 is the sole control**, and it is a process assertion. Guard B mutation row 6 records the shape so a future reader meets it as a known gap rather than discovering it |
| **A derived #7761 boundary condemns a replace that never happened** — any re-pin to a previously-reported digest derives a boundary in the past, and `boundary_age > 3600` then returns `FAIL reason=stale_image` on a `type/security` tracker | Phase 4.0's provenance split: a **derived** boundary can reach PASS or TRANSIENT and **never FAIL**, encoded as a guarded exit helper whose comment carries the rule so a later edit cannot restore the hazard silently. A **supplied** boundary keeps the committed header's FAIL arm verbatim. The anti-brick signal is routed to a distinct TRANSIENT reason that demands the authoritative input rather than blaming the host. AC12b and scenarios T5/T6 test both arms |
| This PR is mistaken for clearance to recut | The plan says plainly, and the PR body repeats it: this makes an image carrying the emitter **exist**; it does not make one **run**. A green CI here is not clearance |

## Non-Goals / Out of Scope

Each is out of scope by instruction or is tracked; none is silently deferred.

- **Any cutover, host replacement or recut dispatch.** Gated by ADR-199, tracked by #7695 and #7674.
- **Repointing `INNGEST_BASE_URL` back to `http://10.0.1.40:8288`.** That is the second half of the
  cutover. Repointing early is what caused the 18-day outage measured in premise C.
- **Any change to the Hetzner volume** — attach, detach, resize, snapshot or `-replace`. Tracked by #6894.
- **Draining, flushing or `FLUSHALL`ing Redis.** ADR-142's addendum is explicit that with
  `redis_keys > 0` the destructive path is refused outright; clearing the store to satisfy G13 would
  invert the gate into a formality.
- **Changing `INNGEST_CUTOVER_FLIP`.** `aborted` is accepted by G19 alongside `rolled-back`.
- **Bumping `probe_schema` to 4.** Deliberately avoided; it would force a lockstep edit across the
  emitter, two test assertions, the dark gate's default and two prose sites, at the exact moment the
  recut depends on the gate.

**Follow-on work, each needing a tracking issue filed in Phase 5.3:**

1. **The historical credential exposure** (`type/security`). Carries H3, its window (opened
   2026-07-16, still open until a host replace delivers v1.1.27), the decisive negative that `INNGEST_REDIS_LUKS_KEY` did not exist during
   it, and the hard deadline: Better Stack source 2457081 retains 90 days, so the 2026-08-20 boot
   ages out **2026-11-18**, after which the off-host-propagation question is permanently unanswerable.
2. **A carrier-coherence preflight for the inngest host**, generalising
   `host-image-coherence-preflight.sh` — needs a terraform content-hash local, a cloud-init verify
   block and a parameterised script path (Correction 3).
3. **The heredoc class in `cloud-init*.yml`**, which are `templatefile` inputs full of shell heredocs
   where `${…}` is Terraform interpolation. Flagged, deliberately not widened here.
4. **Routine rotation of the credentials whose compromise survives host destruction** —
   `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, the `INNGEST_POSTGRES_URI` password,
   `BETTERSTACK_LOGS_TOKEN` — on a normal schedule via the existing `doppler_secret` provider edge.
   `INNGEST_REDIS_PASSWORD` and the LUKS key are explicitly **not** in this set: the recut destroys
   the store they protect, and rotating the LUKS key beforehand risks a store ADR-142's
   preserve-and-copy path may still need to read. They ride the already-gated recut dispatch, which
   keeps the approval surface at one.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Marketing, Sales, Finance, Product, Operations
and Support are not engaged: no user-facing surface, no pricing or messaging, no recurring vendor
expense (Better Stack volume is unchanged — the marker that would have added rows is cut), no new
vendor relationship.

### Engineering (CTO)

**Status:** reviewed

**Assessment.** Carried forward and re-scoped. Both load-bearing diagnoses were confirmed
independently: the heredoc defect reproduces hermetically (five substitutions fire; the rendered
artifact carries the stub's table followed by the trailer `as ROOT (with HOME=/root and the same`,
matching the journald signature), and nothing in the repo binds tag to digest or pin to content.
Three of the advisory's original findings are **superseded by this revision** — the carrier-manifest
design, the `crane`-based Guard A, and retiring the semver-max check — because each rested on a
capability the CI job lacks (Correction 2) or on a red window that does not exist (Correction 4). Its
closing point stands and is recorded once, in the last row of `## Risks & Mitigations`: this PR does
not unblock the recut.

### Legal (CLO)

**Status:** reviewed

**Assessment.** The heredoc finding is **Art. 32 security-of-processing, not an Art. 4(12)
personal-data breach**, and that holds across both branches of the value-versus-name question, so it
does not wait on measurement. No Art. 33 clock runs and no breach-register entry is warranted: the
register's inclusion predicate is conjunctive and expressly excludes credential-only incidents.

The Art. 32 harm is sharper than "secrets on a host": the env file is `0640 root:deploy` and systemd
reads `EnvironmentFile=` as root before dropping privilege, so `deploy` cannot read it; the generated
artifact, written with no mode, is world-readable and `deploy` can. The defect moved credential
material across a privilege boundary the design deliberately maintains. ADR-198's capability test
sharpens it — `BETTERSTACK_LOGS_TOKEN` passes (write-only ingest ceiling) while
`INNGEST_REDIS_PASSWORD` fails outright: read/write against the store holding user prompts and agent
output. Two facts are carried into the tracked issue rather than left to be re-derived under
pressure: the window opened 2026-07-16 and is **still open** on the running image (it closes at the host
replace, not at the pin bump), and `INNGEST_REDIS_LUKS_KEY` **did not exist** during it. Rotation of that password and the LUKS key rides the gated recut, never a
standalone action.

**One finding is materially changed by this revision.** The prior plan treated the #7761 seam as an
exposure this PR would extend. It is an exposure this PR **closes** — the fix is merged and the live
host runs the pre-fix script every thirty seconds. The Art. 32 posture argues for shipping sooner,
not for gating on a historical measurement.

### Product/UX Gate

Not applicable. The mechanical UI-surface override was evaluated against `## Files to Edit` and
`## Files to Create`: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`
or any term in the shared UI-surface list. Product tier is **NONE** by both the semantic sweep and
the mechanical check.

## GDPR / Compliance Gate (Phase 2.7)

The gate fires on trigger (b) — a `single-user incident` threshold is declared — not on the canonical
regex, which this plan does not match (no schema, migration, auth flow, API route or `.sql` file is
touched).

**Discharged by the CLO advisory above**, which covers the same taxonomy at greater depth: Art. 4(12)
versus Art. 32 classification and why it is stable across the unmeasured branch; the Art. 33 clock
(not running); the breach register's conjunctive inclusion predicate and its credential-only
exclusion; and the encryption-posture ledger disposition.

**One Critical-class finding, pre-existing rather than introduced here:** the Art. 30 register's
PA-8 §(g) describes a `pii_scrub` redaction boundary that the host's own measured shipping history
contradicts, aggravated by the open `compliance/critical` finding that Better Stack has no executed
Art. 28(3) instrument (#7529). It is an Art. 30(1)(g) accuracy problem today, independent of how the
credential question resolves. The gate's Critical path would write to `compliance-posture.md` Active
Items and open a labelled issue; both are deferred to `ship`, because this planning task writes only
under `knowledge-base/project/{plans,specs}/`. Deferring the *write* is not deferring the *finding* —
it is recorded here in full, with its remedy named.

## Plan Revisions — this revision

Every design change this revision makes is argued **once**, where the decision lives, and is not
restated here: `### Correction 1` (the inverted #7761 premise), `### Correction 2` (why no CI job can
read the registry), `### Correction 3` (what the repo already owns), `### Correction 4` (why the
semver-max check is kept), and the `Cut List` (what was removed and what property each cut mechanism
was for). This section exists for the one thing those cannot carry — what must **not** come back.

**Retracted, and must not be reintroduced:**

1. **The build-emitted carrier manifest** (the prior plan's R3). A manifest is a number a human
   transcribes; it proves HEAD's files match something someone wrote down, and nothing at all about
   the bytes inside the pinned digest. Guard A measures the tag's tree instead.
2. **Retiring the semver-max drift check** (the prior plan's R14). Its premise — a permanent red
   window on `main` — is false. Correction 4.
3. **A `crane`-based guard in `deploy-script-tests`**, in any form: `crane digest`, `crane export`,
   or a manifest fetch. Correction 2. The job has no crane binary, no `packages: read`, and the
   package is private; any such arm reds every PR forever.
4. **A digest artifact uploaded from the build workflow.** An earlier draft of *this* revision
   proposed it, on the false premise that the digest reaches only `$GITHUB_STEP_SUMMARY`. The cosign
   step also echoes `Signed <image>@<digest>` to stdout, so the run log already carries it — and that
   is the *signed* digest, a stronger anchor. Phase 2 records the correction.
5. **A new render harness, an on-host render self-check, a lifecycle marker, and a new ADR ordinal.**
   All four were cut with reasons in the Cut List; three plan generations have now proposed at least
   one of them.

### Two challenges surfaced, not applied

Per ADR-084 these argue that operator-specified scope should change, so they are persisted to
`knowledge-base/project/specs/feat-one-shot-7695-inngest-image-pin-probe-schema/decision-challenges.md`
rather than silently actioned; `ship` Phase 6 renders them into the PR body and files an
`action-required` issue. Both were narrowed by this revision — UC-1's redness argument is dead
(Correction 4) leaving only tag reachability, and UC-2 is largely resolved because the never-executed
on-host code is now cut.

### Revision — 2026-09-08: the tag was re-cut to `vinngest-v1.1.27`

`vinngest-v1.1.26` was invalidated during ship, by this plan's own mechanism working correctly.

`lint-shell-trace-credential-refusal` (#7797) landed on `main` while this branch was open. It
requires an xtrace refusal in any script binding a live credential and scans CHANGED files only,
so touching `inngest-bootstrap.sh` made it this PR's to fix. That file is a **baked carrier**, so
the edit broke tag/tree coherence and Guard A reported `drifted: inngest-bootstrap.sh` against
v1.1.26 — which is precisely what Guard A exists to do, and the reason the tag had to be re-cut
rather than the mismatch shipping silently.

- New tag `vinngest-v1.1.27` at `d2761a876`, built by run **34215920283**.
- Digest `sha256:6b89bc83031790b63ec21a970c10b98b8206bb5d7b3276f8b9477a42adafa8a4`, read from that
  run's `Signed …@…` line — AC5 re-derived by command: `headSha` equals the tag's commit, and the
  run emits exactly ONE distinct signing-line digest.
- All four pin sites re-pointed. Guard A green: 10 carriers, 0 drifted at v1.1.27.

**Forward-looking references to v1.1.26 in this plan were updated; historical ones were not.** The
mutation-row measurement (`v1.1.26@sha256:<v1.1.25's digest>` passing both hermetic guards) and the
generic tag-mutability hazard note are dated records of what was measured and stay as written, per
the append-only rule for dated records.

**This is the second time UC-1's provenance argument has had teeth.** The decision challenge noted
that a squash merge never places the tagged branch commit into `main`, so `git show <tag>:<path>`
depends on a commit that survives only as a tag. One PR has now cost two tag cuts. The operator's
one-PR shape stands; this is recorded as evidence for the next time the question comes up, not as a
reversal.
