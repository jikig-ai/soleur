---
title: "fix(infra): provisioner-parity G2 residence is web-2-only — web-fleet SSH dialers outside server.tf escape fleet classification"
type: fix
date: 2026-10-12
slug: fix-provisioner-parity-ssh-residence
branch: feat-one-shot-9998-ssh-residence
issue: 9998
closes: 9998
lane: single-domain
priority: p2-medium
domain: engineering
---

# fix(infra): provisioner-parity G2 residence is web-2-only — web-fleet SSH dialers outside server.tf escape fleet classification

## Enhancement Summary

**Deepened on:** 2026-10-12
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive), Proposed Solution
(FLOOR semantics, stale-anchor literal, dual-host dial edge), Acceptance Criteria
(AC8 honesty fix), new Risks & Mitigations with precedent-diff.
**Research agents used:** none — this session has no Agent/Task tool; the
deepen-plan fan-out (skill sub-agents, learnings agents, per-section research,
review panel) was performed inline by the planning agent and the substitution is
recorded in `specs/feat-one-shot-9998-ssh-residence/decision-challenges.md`.

### Key Improvements

1. `FLOOR` is `mutations_run` (landed mutations), not `cases` — 4 new `expect_red`
   rows raise it 58 → 62, comment re-derived per file convention.
2. AC8 corrected: the battery mutates `.tf` inputs only and cannot reach the
   guard's `EXT_RESIDENCE` table, so the reason-mandatory invariant is a
   guard-internal self-check folded into the stale-allowance arm — not a
   battery-proven assertion.
3. Residence scope deliberately covers ANY `web-\d+` dialer (superset of the
   issue's "all declared fleet hosts") — a future web-3 dialer outside server.tf
   fails closed, matching M4i's declared-roster philosophy.
4. Stale-allowance FAIL text pinned to the literal `stale EXT_RESIDENCE entry` so
   battery row G2-22 anchors on its own arm, not the residence arm's
   `residence allowance` phrasing.

### New Considerations Discovered

- The issue's "currently zero" premise was false (4 legit external web-1 dialers)
  — the plan's allowance design, already load-bearing, is confirmed by this
  deepening, not weakened.
- `apply-web-platform-infra.yml` triggers on `apps/web-platform/infra/**` — the
  merge fires the routine apply even though no `.tf` changes; PR body must carry
  the merge-effect first line.
- Zero `.tf.json` files exist in the repo; `.tf.json` coverage stays a defensive
  shape (mirrors G2-13/14/C3), not a live-input requirement.

## Overview

Guard 2 of `apps/web-platform/infra/web-host-provisioner-parity.test.sh` sweeps every
`.tf`/`.tf.json` file in the repo and checks each SSH `connection` block's `host_key`
against a pinned-local contract (ADR-237), but its residence rule flags only
web-2-dialing blocks outside `apps/web-platform/infra/server.tf`. A web-1-dialing (or
future web-N-dialing) SSH `terraform_data` resource born in any other `.tf` file —
carrying a correctly pinned `host_key = local.web_1_ssh_host_key` — passes every
Guard 2 rule while escaping the §1 fleet classification (`ssh_resources`,
`uncovered`, `stale`, `_fleet_extra`), which is server.tf-scoped by construction.

The fix extends the residence check from `dials_web_2` to every textual web-fleet
dialer, and adds the mechanism the naive extension cannot ship without: a
reason-mandatory, host-scoped, per-resource **residence allowance** for the four
legitimate one-off web-1 dialers that already live outside server.tf today
(`terraform_data.root_authorized_keys` in `ci-ssh-key.tf`; `luks_monitor_token_install`,
`luks_monitor_install`, `workspaces_boot_unlock_install` in `workspaces-luks.tf`), plus
a stale-allowance arm so an entry cannot outlive the resource it names. The mutation
battery gains the rows that prove the arm fires on the issue's escape shape and does
not over-fire on the declared exceptions.

## Problem Statement / Motivation

Filed as a deferred follow-up after PR #9992 merged (#9998, `type/bug`,
`priority/p2-medium`, found by the structural-enumeration review seat).

- §1 of the guard scopes `ssh_resources`, `_all_tf_names`, `_dialed_hosts`,
  `_fleet_extra` and the `uncovered`/`stale` classification to `srv` — the
  comment-stripped text of `server.tf` alone (`web-host-provisioner-parity.test.sh:135`,
  `:285`, `:390`).
- G2's residence rule (`web-host-provisioner-parity.test.sh:1249-1257`) flags only
  `dials_web_2` blocks outside server.tf, pinned by battery row G2-18
  (`web-host-provisioner-parity-mutation.test.sh:1272`).
- Battery row G2-4 (`web-host-provisioner-parity-mutation.test.sh:1289`) appends a
  web-1 dialer in `tunnel.tf` but reds only via the missing-`host_key` count arm;
  the same block carrying `host_key = local.web_1_ssh_host_key` stays GREEN — verified
  by reading the four G2 checks (exactly-one `host_key`, allow-set membership,
  web-1→`local.web_1_ssh_host_key`, web-2-only residence): each is satisfied.

Fleet classification is asymmetric by accident, not by design: a genuinely deployed
SSH delivery channel outside server.tf would apply unclassified — no `uncovered`/`stale`
finding, no sibling-class credential/destination check — while the parity guard reports
clean.

## Research Insights

**Premise validation (Phase 0.6).** Checked: issue #9998 is OPEN with the labels and
milestone the plan assumes; PR #9992 (`fix(infra): provisioner-parity battery
control-C -> expect_green + M4j sibling (#9970)`) is MERGED, matching the issue's
"deferred follow-up" framing; issue #9970 is CLOSED by it. Every line-number citation
in the issue verified within drift tolerance against the worktree (`srv` scoped read
at guard:135; `ssh_resources` population at ~285; `FLEET_SSH_HOSTS`/`_dialed_hosts`/
`_fleet_extra` at ~382-390; `w2_elsewhere` at 1249-1257; G2-4 at battery:1289; G2-18
at battery:1272). `guard:1251-1257` in the issue is off by ~2 lines from the actual
`w2_elsewhere` block — cosmetic drift, not a stale premise.

**Premise correction — the issue's "currently zero" claim is false.** The issue's
re-evaluation trigger says "before any `.tf` file other than `server.tf` adds an SSH
`terraform_data` resource — currently zero". Four SSH `terraform_data` resources with
web-1-dialing `connection` blocks already live outside server.tf:

| File | Resource | Line |
|---|---|---|
| `apps/web-platform/infra/ci-ssh-key.tf` | `root_authorized_keys` | 68 (connection at 71) |
| `apps/web-platform/infra/workspaces-luks.tf` | `luks_monitor_token_install` | 171 (connection at 174) |
| `apps/web-platform/infra/workspaces-luks.tf` | `luks_monitor_install` | 262 (connection at 289) |
| `apps/web-platform/infra/workspaces-luks.tf` | `workspaces_boot_unlock_install` | 676 (connection at 706) |

Each dials `hcloud_server.web["web-1"].ipv4_address` with
`host_key = local.web_1_ssh_host_key`. ADR-237 itself records the split layout
("17 in `server.tf` and 1 in `ci-ssh-key.tf`") — these are declared one-off infra
provisioners, not fleet artifacts, and they legitimately escape §1 because their
destinations are not dual-delivered web-host config. A blanket "every web-N dialer
must live in server.tf" rule reds the real tree on all four; the fix must therefore
ship the exemption surface in the same change. This correction is the load-bearing
fact of the plan.

**Baseline.** `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` on the
unmutated worktree: `18 passed, 0 failed` (§1-§5) + `Guard 2: 9 passed, 0 failed`,
~2.4s. Swept 25 SSH connection blocks (floor 23) across 88 `.tf`/`.tf.json` files
(floor 70).

**Property List (Phase 0.6b).**

- P1 — An SSH `connection` block outside `apps/web-platform/infra/server.tf` that
  textually dials a web-fleet host is a finding, regardless of which `web-N` it dials.
- P2 — The four declared one-off external dialers stay GREEN; the exemption must be
  a reviewable diff (reason-mandatory), host-scoped (a web-1 allowance covers no
  web-2 dialer), and per-resource (a second phantom cannot hide behind the first).
- P3 — An allowance entry that outlives its resource is itself a finding (the
  "claim that silently outlives the set it described" class the guard's own header
  names).
- P4 — The new arm is mutation-proven: battery rows exist and anchor on the arm's
  own `[FAIL]` text, not a side-effect.

**Cut List (Phase 0.6b).**

- *Extend §1's `srv` census to all `.tf` files* → buys "external dialers get
  classified" — REJECTED: §1's classification demands fresh-boot parity for every
  swept destination, which would red all four legitimate one-off dialers (their
  destinations are not dual-delivered artifacts), and the residence arm already
  buys P1 by forcing fleet dialers into either server.tf (where §1 sees them) or a
  declared allowance. Nothing cheaper covers the property; the mechanism named in
  the ask is the minimal one.
- *Move the four external resources into server.tf* → would make residence absolute
  — REJECTED: out of the issue's scope, reverts an ADR-237-recorded layout, and
  conflates "is this resource classified" with "where does it physically live".

**Key files.** `apps/web-platform/infra/web-host-provisioner-parity.test.sh` —
Guard 2 heredoc (`G2EOF`): the `git ls-files` walk + `read_text()` at ~1106-1157
(the battery pins exactly one `"ls-files"` call site and one `read_text(` site),
`is_winrm`/`ssh_blocks` at ~1177-1180, `FLOOR_BLOCKS = 23` at ~1181, `dials_web_1`/
`dials_web_2` normalizers at ~1200-1207, `ALLOWED_HOST_KEYS` at :1062, `w2_elsewhere`
residence arm at 1249-1257. `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` —
`expect_red`/`expect_green` helpers at :285/:312, G2 rows at :1251-1449, `FLOOR=58`
case-count comment at :1481, accounting-conservation trailer (ADR-193 #3) after it.

**Repo conventions to reuse.** Reason-mandatory keyed allowlists (`ALLOWLIST` at
guard:148, `ONLY_JUSTIFIED` at :391 — "Adding an entry is a reviewable diff");
non-vacuity floors on every sweep; `expect_red` anchors that are substrings of the
arm's own `[FAIL]` text; `FLOOR`/`cases` comments re-derived when rows are added;
comment-stripped inputs (`strip_hcl` covers `#`, `//`, `/* */`; `strip_comments` is
string-aware).

**Learnings.** `2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md`
(anchor attribution, not bare non-zero exits); `2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md`;
`2026-09-24-the-gate-the-issue-blamed-was-never-reached.md`;
`2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
(the Guard Contract class this plan must satisfy); ADR-193 (battery accounting
conservation); ADR-237 (host_key pinning + the recorded two-file layout); ADR-114
(do-not-repoint connection hosts rationale).

**External research.** Skipped — internal guard machinery with strong local
precedent; no external API, framework, or security-protocol decision is involved.

**Functional overlap.** `web-hosts-fanout-parity.test.sh` pins `var.web_hosts` keys
against workflow readback loops — different property. `terraform-target-parity.test.ts`
pins the SSH `-target=` sets in `apply-web-platform-infra.yml` — different property
(it would only catch an external dialer that someone ALSO `-target=`ed). No repo
mechanism buys P1; community-artifact discovery is not applicable to an internal
guard (no discovery agent spawn available — continued silently per
`plan-functional-overlap.md` Step 3).

## Hypotheses

The `hr-ssh-diagnosis-verify-firewall` gate fired on the `SSH` token in the feature
description (telemetry emitted). This plan proposes no connectivity diagnosis: the
guard is static source analysis — the battery itself pins that Guard 2 reads files
only through one `git ls-files` enumeration and one `read_text()` call site, so no
live SSH session exists anywhere in the code path under change. Opt-out per
`plan-network-outage-checklist.md` §Opt-out:

1. **L3 firewall / L3 DNS / L7 TLS / L7 application** — not applicable: the defect
   class is a classification asymmetry in a text sweep, not an unreachable host.
   Verification artifact: the mutation battery's reader-shape pin at
   `web-host-provisioner-parity-mutation.test.sh:188-194` (exactly one `"ls-files"`
   and one `read_text(` site, zero `open(`/ `glob(` sites), plus the issue's own
   demonstration that the escape is observable with `git grep` alone.

### Network-Outage Deep-Dive

Deepen-plan Phase 4.5 enforcement layer fired on the `SSH` token (telemetry
re-emitted). Layer-by-layer verification status against the checklist:

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | not applicable — no live dial | Guard 2 reads files only via one `git ls-files` + one `read_text()` (reader-shape pin at `web-host-provisioner-parity-mutation.test.sh:188-194`); no egress exists to allowlist |
| L3 DNS / routing | not applicable — no live dial | same artifact |
| L7 TLS / proxy | not applicable — no HTTPS path under change | same artifact |
| L7 application | not applicable — no service under diagnosis | the defect is a text-sweep classification asymmetry, reproduced statically by battery row G2-4's shape plus a `host_key` line |

No open hypothesis requires a service-layer probe before the fix; the firewall-first
ordering rule is satisfied vacuously because nothing in the change path touches a
network.

## Proposed Solution

Two parts, one atomic PR — the guard arm without its battery row is unproven, and
the battery row without the arm reds CI today (the issue's own observation that
G2-19 "currently fails 'guard still PASSED'").

### Part 1 — Guard-side (`web-host-provisioner-parity.test.sh`, G2 program)

1. **Fleet-dial predicate.** Add `dials_fleet(b)` returning the set of
   `hcloud_server.web["web-N"]` names a connection block textually dials — same
   normalization as `dials_web_1`/`dials_web_2` (whitespace-stripped,
   `\\"`-unescaped, `json.dumps` for dict blocks so `.tf.json` is covered). Regex
   shape: `hcloud_server\.web\["(web-\d+)"\]` over the normalized text. Any `web-N`
   counts, not just declared `FLEET_SSH_HOSTS` — a future web-3 dialer outside
   server.tf is exactly the fail-closed case (mirrors M4i's "roster is declared,
   not discovered" philosophy).

2. **Enclosing-resource resolution.** Extend G2's block collection so each
   `ssh_blocks` entry also carries the enclosing resource address:
   for `.tf`, the nearest preceding `resource "<type>" "<name>"` header before the
   block's byte offset (HCL resources do not nest, so last-header-wins is exact);
   for `.tf.json`, the `.resource.<type>.<name>` segment already present in the
   `json_blocks` path. Unresolvable name → a sentinel that matches no allowance
   entry (fail-closed — an unnameable external dialer is a finding, never a pass).

3. **`EXT_RESIDENCE` allowance.** A reason-mandatory dict, keyed
   `file → {resource_name: {"hosts": frozenset, "reason": str}}`, seeded with
   exactly the four known members:
   - `apps/web-platform/infra/ci-ssh-key.tf` → `root_authorized_keys` → `{web-1}`
   - `apps/web-platform/infra/workspaces-luks.tf` → `luks_monitor_token_install`,
     `luks_monitor_install`, `workspaces_boot_unlock_install` → `{web-1}`
   Reason strings name why each resource lives outside server.tf (one-off infra
   provisioner, not a dual-delivery fleet artifact — ADR-237 records the layout).
   Per-resource granularity, not per-file: a file blanket lets a second phantom
   `terraform_data` hide inside an allowlisted file — the second-member class the
   Guard Contract exists to catch.

4. **Residence arm.** Replace `w2_elsewhere` with `fleet_elsewhere`: for each
   `(loc, body, resource_name)` in `ssh_blocks`, compute `dialed = dials_fleet(b)`;
   skip when empty or when the file IS server.tf; otherwise require an
   `EXT_RESIDENCE` entry for `(file, resource_name)` whose `hosts` superset covers
   `dialed`. Superset semantics handle the multi-dial edge: a block dialing BOTH
   web-1 and web-2 in an allowlisted file is flagged (`{web-1,web-2}` is not a
   subset of `{web-1}`), as is any `web-\d+` not in the entry's set. Fail text keeps
   the literal `outside server.tf` so the existing G2-18
   anchor and the new G2-19 anchor both resolve: `"G2: web-fleet-dialing connection
   block(s) outside server.tf — they escape the sibling-class credential/destination
   checks in §1 and carry no residence allowance: "`.

5. **Stale-allowance arm.** Every `EXT_RESIDENCE` entry must resolve to a swept
   block: the file is present in the walk, the resource name resolves, and at
   least one swept block at `(file, resource_name)` has `dials_fleet`
   intersecting the entry's `hosts` — AND the entry's `reason` is non-empty
   (guard-internal self-check; the battery mutates `.tf` inputs only and cannot
   reach the table, so this invariant is verified by code review and fails loudly
   at guard runtime if violated). An entry whose resource lost its connection
   block, or repointed it off every declared host, is a finding — the exemption
   cannot rot in place after its resource is deleted or repointed. FAIL text
   carries the literal
   `stale EXT_RESIDENCE entry` so the battery row anchors on THIS arm rather than
   the residence arm's `residence allowance` phrasing.

6. **Header comment.** Extend the G2 section's scope note: residence is
   fleet-symmetric; the allowance is the single exemption surface.

### Part 2 — Battery-side (`web-host-provisioner-parity-mutation.test.sh`)

| Row | Mutation | Anchor | Proves |
|---|---|---|---|
| G2-19 | Append a web-1-dialing `terraform_data` WITH `host_key = local.web_1_ssh_host_key` to `tunnel.tf` (the issue's demonstrated escape) | `outside server.tf` | P1 — the arm fires where today it cannot |
| G2-20 | Append a SECOND phantom web-1-dialing `terraform_data` (different resource name) to `workspaces-luks.tf` | `outside server.tf` | P2 — allowance is resource-granular, not a file blanket |
| G2-21 | Append a web-2-dialing block to `workspaces-luks.tf` (an allowlisted file) | `outside server.tf` | P2 — allowance is host-scoped; web-2 residence keeps zero exceptions |
| G2-22 | Delete the `connection {}` block from `ci-ssh-key.tf` | `stale EXT_RESIDENCE` | P3 — the orphaned entry is a finding |

Green coverage stays with the existing baseline row: the real tree's four declared
dialers are the must-PASS members, swept on every run.

Accounting (`web-host-provisioner-parity-mutation.test.sh:1481`): `FLOOR` floors
`mutations_run` (landed `expect_red`/`expect_green` mutations), not `cases` — four
new `expect_red` rows raise it 58 → 62 and the annotation is re-derived per the
file convention (`+4 #9998 residence rows (G2-19..22)`). `PROBE_FLOOR`/
`PROBE_RED_FLOOR` are untouched (no probe rows added), as are `FLOOR_BLOCKS`/
`FLOOR_RESOURCES` in the guard — the battery mutates the sandbox, not the real
tree.

## Technical Considerations

**Attack surface enumeration** (this is a classification-boundary fix — the surface
is "ways an SSH delivery channel can exist in the tree"):

- (a) `server.tf` — covered by §1's `ssh_resources`/`uncovered`/`stale` census. Checked.
- (b) non-server.tf `.tf` — **this fix**. Checked after the change.
- (c) `.tf.json` — the same arm covers it (`dials_fleet` handles dict blocks via
  `json.dumps`; resource name from the JSON path). Checked after the change.
- (d) indirect host spellings — `var.web_hosts["web-1"].private_ip`,
  `local.<alias>`, module outputs, literal IPs — NOT covered: `dials_*` is textual
  matching, and an alias chase is a different mechanism. **Residual gap**, carried
  forward verbatim from the issue's re-evaluation trigger:
  `git grep -l 'type[[:space:]]*=[[:space:]]*"ssh"' -- '*.tf' ':!server.tf'` in CI
  is the suggested tripwire if desired. Named gap, justification: resolving HCL
  indirection in a text sweep is a larger design (alias resolution, cross-file
  locals) than this issue's fix-shape; the textual class covers the demonstrated
  escape.
- (e) winrm `connection` blocks — excluded by `is_winrm`; out of the SSH class.
- (f) commented-out `connection` text — `strip_hcl` removes `#`, `//`, `/* */`
  before the walk; pinned by G2-C2.
- (g) untracked-but-unignored `.tf` files — swept (`git ls-files --cached --others
  --exclude-standard`); ignored paths are unreachable by construction.

**Why residence and not census.** §1's classification is destination-keyed
dual-delivery parity: sweeping non-server.tf files into it would demand fresh-boot
counterparts for the four one-off provisioners' destinations — a red on the real
tree for resources that are not fleet artifacts. The residence arm buys the actual
property (a fleet-dialing SSH channel must either live where §1 sees it or be a
declared, reason-carrying exception) without re-scoping §1.

**Sequencing.** Guard arm and battery rows land in the same PR. Interim state
(guard merged without battery) is proven-but-unproven — the arm exists but nothing
asserts it; interim state (battery without guard) is red-on-main.

## Open Code-Review Overlap

None — checked 2026-10-12 against open `code-review` issues: no open issue body
mentions `web-host-provisioner-parity.test.sh`,
`web-host-provisioner-parity-mutation.test.sh`, or the `web-host-provisioner-parity`
prefix.

## User-Brand Impact

- **If this lands broken, the user experiences:** a genuinely deployed SSH delivery
  channel outside server.tf applies unclassified — the parity guard reports clean on
  a fleet delivery path nobody accounted for, so a later config drift on that path
  reaches web-1 with no `uncovered`/`stale` finding (the issue's stated user-impact).
  The over-fire arm is symmetric: a false residence finding reds infra PRs and
  degrades the fix path on live hosts.
- **If this leaks, the user's workflow is exposed via:** an unaudited SSH channel to
  a web host — a delivery path invisible to classification can drift without any
  finding surfacing until a host-level symptom does.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the touched artifacts are
  test-classification machinery; the worst outcome is a wrong CI verdict (missed or
  noisy), not a user-facing surface, data store, or credential change — so `none`,
  not `single-user incident`.
- `threshold: none, reason: files under apps/web-platform/infra/ match the
  sensitive-path regex by directory, but this diff edits guard/test scripts only —
  no Terraform resource, credential, or delivery-path change reaches a host.`

## Observability

```yaml
liveness_signal:
  what: infra-validation CI leg runs run-registered-suites.sh, which glob-derives and executes both suites on infra-touching PRs
  cadence: per-PR + merge pipeline
  alert_target: GitHub required-check status on the PR
  configured_in: .github/workflows/infra-validation.yml:687 (bash apps/web-platform/infra/run-registered-suites.sh); suite registration via suite-durations.tsv rows 147-148
error_reporting:
  destination: GitHub Actions job log for the infra-validation leg
  fail_loud: non-zero exit with "=== web-host-provisioner-parity Guard 2: N passed, M failed ===" printed by the guard itself
failure_modes:
  - mode: residence arm regression (arm deleted or predicate narrowed)
    detection: mutation battery rows G2-19/G2-20/G2-21 redden on their anchors
    alert_route: CI check failure blocks the PR
  - mode: allowance rot (entry outlives its resource)
    detection: stale-allowance arm + battery row G2-22
    alert_route: CI check failure blocks the PR
  - mode: extraction drift (walk or block-body parse degrades)
    detection: existing swept floors (FLOOR_BLOCKS, FLOOR_FILES, accounting conservation)
    alert_route: CI check failure blocks the PR
logs:
  where: GitHub Actions job output for the infra-validation leg
  retention: GitHub Actions default retention
discoverability_test:
  command: bash apps/web-platform/infra/web-host-provisioner-parity.test.sh
  expected_output: 0 failed
```

Measured at ~2.4s on the worktree — under preflight Check 10's 15s cap; first token
`bash` is on `PROBE_VERB_ALLOWLIST`; `0 failed` is the literal substring the guard
prints on a clean run. The mutation suite (~101s measured per suite-durations.tsv)
is deliberately NOT the probe.

## Guard Contract

### Guard 1 — G2 fleet-dialer residence arm

**Property.** Every Terraform SSH `connection` block that textually dials a
web-fleet host (`hcloud_server.web["web-N"]`, any N) lives in
`apps/web-platform/infra/server.tf`, unless its `(file, terraform_data resource)`
pair carries a declared `EXT_RESIDENCE` entry whose host set covers every host the
block dials — and every declared entry must resolve to a swept block.

**Assembly.** The chokepoint is Guard 2's single enumeration:
`git ls-files --cached --others --exclude-standard -- '*.tf' '*.tf.json'` at
`web-host-provisioner-parity.test.sh:~1108` feeding `blocks`/`ssh_blocks`
(`:1136-1180`), the one place every connection block in the repo flows through —
the battery pins exactly one `"ls-files"` and one `read_text(` call site, so no
second reader can take a file the walk misses. The property quantifies over every
member of `ssh_blocks` (winrm excluded); the exemption surface is `EXT_RESIDENCE`
alone — there is exactly one.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append a web-1-dialing `terraform_data` carrying `host_key = local.web_1_ssh_host_key` to `tunnel.tf` (the #9998 escape — satisfies every existing G2 check) | RED via `outside server.tf` |
| 2 | (dispatch) Neuter the walk so tunnel.tf leaves `ssh_blocks`' file set — e.g. drop `tunnel.tf` from the sandbox's tracked files while the phantom sits in it | RED — the phantom is swept or the swept-file/block floors fire; an arm that can report "0 external dialers" over a file it never saw is vacuous |
| 3 | (second member) Append a SECOND phantom web-1-dialing `terraform_data` under a different resource name to `workspaces-luks.tf` (an allowlisted file already holding three compliant members) | RED via `outside server.tf` — the allowance must be resource-granular; a file-level pass is the defect |
| 4 | (host scoping) Append a web-2-dialing block to `workspaces-luks.tf` | RED via `outside server.tf` — a web-1 allowance covers no web-2 dialer |
| 5 | (precondition-held-property-failed) Append a web-1 dialer to `tunnel.tf` inside a resource that is NOT `terraform_data`… or under any name: the residence question is about the block, so no resource shape may exempt an undeclared file | RED via `outside server.tf` |
| 6 | (stale) Delete the `connection {}` block from `ci-ssh-key.tf` | RED via the stale-allowance text — the orphaned `EXT_RESIDENCE` entry is itself a finding |
| 7 | (harness must-PASS, non-canonical) Add a comment mentioning `connection {` and `hcloud_server.web["web-1"]` to `tunnel.tf` | GREEN — `strip_hcl` removes it before the walk (extends G2-C2's pin to the fleet predicate) |
| 8 | (harness must-PASS) Real tree unchanged — the four declared external dialers | GREEN via `EXT_RESIDENCE` — the baseline row is the live proof the exemption is not vestigial |

**Anchor.** `EXT_RESIDENCE` is a stored value compared against the swept set: a
weakening that edits both the table and adds a phantom in one diff is the declared
shape of the mechanism (the entry IS the review surface — every allowance change is
a diff a reviewer reads). What bounds it: entries are reason-mandatory (empty reason
= finding), resource-granular (a phantom under a new resource name in an
allowlisted file reds — row 3), host-scoped (row 4), and stale-checked (row 6), so
the table cannot silently widen or rot.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Guard-side: extend the G2 residence rule from `dials_web_2` to all declared fleet hosts (or add a `w1_elsewhere` arm) so an SSH `connection {` block outside server.tf is a finding regardless of dialed host." [issue #9998] | Proposed Solution Part 1 (items 1, 4) / Phase 1 / `web-host-provisioner-parity.test.sh` Files-to-Edit entry | mapped |
| 2 | "Battery-side: `expect_red \"G2-19\" tunnel.tf \"outside server.tf\"` appending a web-1-dialing block WITH `host_key = local.web_1_ssh_host_key` — currently fails \"guard still PASSED\"." [issue #9998] | Proposed Solution Part 2 row G2-19 / Phase 2 / `web-host-provisioner-parity-mutation.test.sh` Files-to-Edit entry | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `dials_fleet` predicate + `fleet_elsewhere` residence arm | "extend the G2 residence rule from `dials_web_2` to all declared fleet hosts" | asked |
| `EXT_RESIDENCE` allowance (per-resource, host-scoped, reason-mandatory) + stale-allowance arm | — | inferred — justification: the issue's "currently zero" premise is false; four declared web-1 dialers live outside server.tf today, so a residence rule with no exemption surface reds main. Host-scoping preserves the web-2 arm's zero-exception semantics; per-resource granularity and the stale arm are required by this plan's own Guard Contract (rows 3 and 6). |
| Battery rows G2-20/G2-21/G2-22 (beyond the asked G2-19) | "Battery-side: `expect_red \"G2-19\" tunnel.tf \"outside server.tf\"`" | inferred — justification: the allowance surface the guard now needs is itself a mechanism that must be driven red (granularity, host-scoping, staleness) or it is a hole the fix just opened; the Guard Contract mandates the rows. |
| Enclosing-resource resolution in the G2 walker | — | inferred — justification: the per-resource allowance cannot be evaluated without it; fail-closed on unresolvable names. |
| Header-comment scope update | — | inferred — justification: the file's own convention documents every scope decision in the header; a symmetric-residence rule with no comment would misstate scope. |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 2 | Estimated changed lines: ~120-160 (guard ~70-100 incl. allowance + arms; battery ~40-60 incl. 4 rows + FLOOR comment)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to a
CI guard and its mutation battery. Mechanical UI-surface override: no path in
`## Files to Edit`/`## Files to Create` matches the UI-surface term list or glob
superset (`.sh` under `infra/` only).

## Implementation Phases

### Phase 1 — Guard arm (`web-host-provisioner-parity.test.sh`, G2 heredoc)

1. Add `dials_fleet(b)` beside `dials_web_1`/`dials_web_2` (same normalization;
   returns the set of `web-N` names; handles dict blocks via `json.dumps`).
2. Extend the block-collection loop to carry the enclosing resource address
   per block (nearest preceding `resource "<type>" "<name>"` header for `.tf` —
   ANY type, not just `terraform_data`: a `connection {}` inside a
   `null_resource`/`hcloud_server` in an undeclared file must still attribute
   or fail closed on the sentinel; `.resource.<type>.<name>` path segment for
   `.tf.json`; unresolvable → sentinel matching no allowance entry).
3. Define `EXT_RESIDENCE` with the four seeded entries and mandatory `reason`
   strings; an empty/missing reason is itself a finding.
4. Replace the `w2_elsewhere` arm with `fleet_elsewhere` (fail text retains
   `outside server.tf`; success text states the fleet-symmetric property and the
   allowance).
5. Add the stale-allowance check (every entry resolves to a swept fleet-dialing
   block on a declared host).
6. Update the header scope comment.

### Phase 2 — Battery rows (`web-host-provisioner-parity-mutation.test.sh`)

1. Add rows G2-19 through G2-22 per the table in Proposed Solution Part 2.
2. Re-derive `FLOOR`/`cases` accounting comments from the battery log and update
   the `FLOOR=58` annotation.

### Phase 3 — Verification

1. `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` — GREEN on
   the real tree; the four declared dialers pass via `EXT_RESIDENCE`.
2. `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` —
   all rows pass, including the four new ones; `guard still PASSED` must NOT appear
   for G2-19 (that is today's defect signature).
3. Confirm no existing row flips (G2-18's `outside server.tf` anchor still resolves
   against the new arm's fail text).

## Files to Edit

- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — G2 program:
  `dials_fleet`, enclosing-resource resolution in the block-collection loop,
  `EXT_RESIDENCE` table, `fleet_elsewhere` arm replacing `w2_elsewhere`,
  stale-allowance arm, header scope comment.
- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — rows
  G2-19, G2-20, G2-21, G2-22; `FLOOR=58` comment re-derived.

## Files to Create

None.

## Acceptance Criteria

- [ ] AC1: A `terraform_data` SSH `connection` block dialing
  `hcloud_server.web["web-1"]` with `host_key = local.web_1_ssh_host_key`, appended
  to `apps/web-platform/infra/tunnel.tf`, fails the guard via a `[FAIL]` line
  containing `outside server.tf` (battery row G2-19).
- [ ] AC2: `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` exits
  0 on the real tree — the four declared external dialers
  (`root_authorized_keys`, `luks_monitor_token_install`, `luks_monitor_install`,
  `workspaces_boot_unlock_install`) pass via `EXT_RESIDENCE` and print the new
  arm's success line.
- [ ] AC3: A second phantom web-1-dialing `terraform_data` (new resource name) in
  `workspaces-luks.tf` reds via `outside server.tf` — allowance is
  resource-granular (battery row G2-20).
- [ ] AC4: A web-2-dialing block in `workspaces-luks.tf` reds via
  `outside server.tf` — allowance is host-scoped, and web-2 residence keeps zero
  exceptions (battery row G2-21); G2-18 still passes on its anchor.
- [ ] AC5: Deleting the `connection {}` block from `ci-ssh-key.tf` reds via the
  stale-allowance `[FAIL]` text (battery row G2-22).
- [ ] AC6: `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  exits 0; the `FLOOR`/`cases` comments match the new row count.
- [ ] AC7: §1's census is untouched — `ssh_resources`, `uncovered`, `stale`, and
  `_fleet_extra` remain `srv`-scoped; the fix is G2-side only (per the issue's
  guard-side fix-shape).
- [ ] AC8: The guard carries a runtime self-check that an `EXT_RESIDENCE` entry
  with an empty/missing `reason` fails loudly (guard-internal invariant folded
  into the stale-allowance arm — the battery mutates `.tf` inputs only and cannot
  reach the table, so this is verified by code review, matching the
  `ALLOWLIST`/`ONLY_JUSTIFIED` reason-mandatory convention).

## Test Scenarios

- Given the real tree, when `web-host-provisioner-parity.test.sh` runs, then Guard
  2 reports `0 failed` and the fleet-dialer residence check prints its ok line
  covering server.tf + declared allowances. (`integration`)
- Given a web-1-dialing `connection` block with a correctly pinned
  `local.web_1_ssh_host_key` appended to `tunnel.tf`, when the guard runs, then it
  exits non-zero with `outside server.tf` in `[FAIL]` output. (`integration`,
  battery row G2-19 — regression for #9998)
- Given a second web-1-dialing `terraform_data` under a fresh resource name in
  `workspaces-luks.tf`, when the guard runs, then it reds via `outside server.tf`
  — the allowance does not blanket the file. (`integration`, battery row G2-20)
- Given a web-2-dialing block in `workspaces-luks.tf`, when the guard runs, then
  it reds via `outside server.tf` — the web-1 allowance does not cover web-2.
  (`integration`, battery row G2-21)
- Given `ci-ssh-key.tf` with its `connection {}` block removed, when the guard
  runs, then it reds via the stale-allowance text — the orphaned entry cannot rot.
  (`integration`, battery row G2-22)
- Given `tunnel.tf` carrying only comment mentions of `connection {` and
  `hcloud_server.web["web-1"]`, when the guard runs, then it stays green —
  `strip_hcl` precedes the walk. (`integration`, control extending G2-C2's pin)

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The allowance becomes a file-level blanket that a second phantom hides behind | Resource-granular `(file, resource_name)` keys; battery row G2-20 reds on exactly that shape |
| A web-2/web-N dialer slips in under a web-1 allowance | Host-scoped `hosts` sets with superset coverage; battery row G2-21 reds on it |
| Allowance rots after its resource is deleted or repointed | Stale-allowance arm + G2-22; FAIL literal `stale EXT_RESIDENCE entry` |
| Anchor drift: renaming the fail text silently un-pins G2-18 | `outside server.tf` retained verbatim in the new arm's message; AC4 asserts G2-18 still passes |
| Textual-dial scope misses indirect host spellings | Named residual gap (Technical Considerations item d) with the issue's `git grep` tripwire carried forward — a deliberate scope cut, not an oversight |
| Enclosing-resource resolution mis-attributes a block | Fail-closed: unresolvable name matches no allowance entry and reds; `.tf` uses last-preceding-`resource` (HCL resources do not nest), `.tf.json` uses the `json_blocks` path |
| Merge fires the apply workflow on `infra/**` | No `.tf`/`triggers_replace` change → no-diff apply; PR body carries the merge-effect first line (Context section) |

**Precedent-diff (deepen-plan Phase 4.4).** Pattern-bound elements against their
canonical repo precedents:

- `EXT_RESIDENCE` vs `ALLOWLIST` (`web-host-provisioner-parity.test.sh:148`) and
  `ONLY_JUSTIFIED` (`:391`): same dict-with-mandatory-reason shape, extended from
  flat `key → reason` to `key → {hosts, reason}` because the exemption needs a
  second dimension (which hosts). Divergence is minimal and deliberate.
- `dials_fleet` vs `dials_web_1`/`dials_web_2` (`:1200-1207`): identical
  normalization (`re.sub(r'\s+','',text).replace('\\"','"')`, `json.dumps` for
  dict blocks); the only change is `findall` on `hcloud_server\.web\["(web-\d+)"\]`
  returning a set instead of a per-host boolean.
- G2-19..22 rows vs G2-18 (`mutation.test.sh:1272`): same
  `expect_red "<label>" <file> <anchor> '<python mutator>'` form; G2-19's mutator
  mirrors G2-18's appended-resource heredoc, differing only in the dialed host
  (web-1) and the added `host_key` line — the exact delta the issue demonstrates.
- Stale-allowance arm vs the file's own rot-guards (`ALLOWLIST` header comment:
  "a claim that silently outlives the set it described is the exact defect") —
  the arm mechanizes the same convention.

## Non-Goals

- Indirect host spellings (`var.web_hosts`, `local.*`, module outputs, literal
  IPs) in `connection.host` — textual-dial scope only; residual gap named in
  Technical Considerations with the issue's re-evaluation trigger.
- Extending §1's `srv` census to other files — rejected in the Cut List.
- Relocating the four declared external resources into server.tf — ADR-237
  records the layout; not this issue's scope.
- A `-target=`/workflow-delivery audit of external dialers — `terraform-target-parity.test.ts`
  owns that property.

## Context

- **Merge-side production effect (PR body first line):** the diff edits only
  `*.test.sh` files — zero `.tf` change, zero `triggers_replace` change, so the
  routine per-merge apply delivers nothing new. `apply-web-platform-infra.yml`
  does still fire on merge because its push `paths:` filter is
  `apps/web-platform/infra/**` (all files, not `.tf` only): the workflow runs its
  normal `-target=` plan/apply, which is a no-diff apply for terraform state but
  re-fires the web-1 SSH delivery provisioners exactly as every infra merge does
  (by design; ADR-114). No extra mutation authorization is needed beyond the merge
  itself; state the sentence in the PR body's first line per the sharp-edge rule.
- Guard file: `apps/web-platform/infra/web-host-provisioner-parity.test.sh` (1292
  lines; Guard 2 heredoc ~1080-1292). Suite runs in ~2.4s.
- Battery: `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  (1515 lines; ~101s measured per `suite-durations.tsv:147`).
- Both suites registered via `run-registered-suites.sh` glob derivation; executed
  by `.github/workflows/infra-validation.yml:687`.
- Baseline measured on this worktree: `18 passed, 0 failed` + `Guard 2: 9 passed,
  0 failed`; 25 SSH connection blocks swept (floor 23), 88 files walked (floor 70).

## References

- Issue: #9998 (this fix); closed-by PR body must carry `Closes #9998`
- Prior PR: #9992 (merged; filed this gap as deferred scope-out)
- Related: #9970 (normalization battery work — closed), #9151 (web-2 sibling +
  G2-15..17 rows), #8632/#8706/#9123 (the three workspaces-luks external blocks +
  ci-ssh-key history), #7226 (Guard 2 origin), #7000 (guard origin)
- ADRs: ADR-237 (host_key pinning; records the two-file layout), ADR-114
  (connection hosts must not be repointed), ADR-193 (battery accounting
  conservation)
- Learnings: `knowledge-base/project/learnings/2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md`,
  `2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md`,
  `2026-09-24-the-gate-the-issue-blamed-was-never-reached.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  deepen-plan — filled above with the sensitive-path scope-out bullet (the diff
  touches `apps/*/infra/`).
- `discoverability_test.command` runs inside preflight Check 10's sandbox under a
  15s cap — the main guard (~2.4s) is the probe, never the ~101s mutation suite.
- The battery's `expect_red` anchor must be a substring of the arm's own `[FAIL]`
  text — `outside server.tf` is kept verbatim in the new arm's message so G2-18 and
  G2-19..21 all attribute to the same arm.
- `FLOOR`, `cases`, and the swept-count comments are re-derived after adding rows —
  a stale floor comment is the "claim that outlives the set" defect in miniature.
- The `EXT_RESIDENCE` reason field is mandatory by check, not by convention —
  matching the file's ALLOWLIST/ONLY_JUSTIFIED idiom where the reason is the
  reviewable content.
- Enclosing-resource resolution must fail closed: a block whose resource name
  cannot be resolved matches no allowance entry and reds — never skip silently.
- When `w2_elsewhere` is replaced by `fleet_elsewhere`, keep the `outside server.tf`
  literal in the new fail text — G2-18 anchors on it and renaming it silently
  un-pins a green row.
- This planning session ran without an Agent/Task tool: the research fan-out,
  spec-flow analyzer, scoped advisor, plan-review panel, and CTO technical-ruling
  spawns were performed inline by the planning agent; technical forks are recorded
  `pending - assumed` in `specs/feat-one-shot-9998-ssh-residence/decision-challenges.md`.
