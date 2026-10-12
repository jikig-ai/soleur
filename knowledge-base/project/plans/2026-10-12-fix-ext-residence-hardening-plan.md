---
title: "fix(infra): EXT_RESIDENCE per-member content bound + unclassifiable-dial arm — deferred #9998 hardening"
type: fix
date: 2026-10-12
slug: fix-ext-residence-hardening
branch: feat-one-shot-10147-10148-ext-residence-hardening
issue: 10147
closes: [10147, 10148]
lane: single-domain
priority: p2-medium
domain: engineering
---

# fix(infra): EXT_RESIDENCE per-member content bound + unclassifiable-dial arm — deferred #9998 hardening

## Overview

Two sibling hardening arms for Guard 2's residence machinery in
`apps/web-platform/infra/web-host-provisioner-parity.test.sh`, both deferred
scope-outs of #9998 (merged via PR #10130).

**#10147 — per-member content bound.** An `EXT_RESIDENCE` entry waives the G2
residence arm for the whole *resource* for the life of the entry — a member's
provisioner bodies sit outside §1's server.tf census and §2's destination sweep
by residence alone, so a future credential-bearing edit inside a member resource
needs no table diff. The bound: every entry declares a collateral `pin` — a
repo-relative path to the test file that pins the member's provisioner content —
enforced at guard runtime (present, `*.test.*`-shaped, extant) in the same
hygiene arm that already enforces `reason`.

**#10148 — unclassifiable-dial arm.** `dialed_hosts` matches only the literal
`hcloud_server.web["web-N"]` spelling, so a `connection {}` outside server.tf
dialing through indirection (`host = local.x`, `var.y`, `each.value`, `self`,
a raw IP, or any non-web literal) engages no residence arm: an existing member
cannot switch to indirection (the stale arm fires on `hosts ⊆ ∅`) but a NEW
indirect dialer skips residence from birth. The arm flags every unclassifiable
outside-server.tf block; `EXT_RESIDENCE` gains an `unclassifiable` marker as the
reviewed acknowledgment path — the single exemption surface stays single.
Battery control G2-C6, which pins this gap green today, flips to an
`expect_red` row.

## Problem Statement / Motivation

Filed as deferred scope-outs of PR #10130 (`type/bug`-class infra-guard
hardening, `deferred-scope-out` label on both).

- **#10147.** `EXT_RESIDENCE` (guard:1479-1505) is a per-resource waiver: the
  moment an entry exists, the member's *content* is permanently outside the
  classified surface. The guard's own standing-waiver comment
  (guard:1470-1476) records the exposure: "a member's provisioner bodies sit
  outside §1's census and §2 by residence alone … future credential-bearing
  edits inside a member need no table diff." The four seeded members happen to
  be covered by sibling suites; nothing forces the NEXT entry to be.
- **#10148.** `dialed_hosts` (guard:1414-1415) is a literal
  `hcloud_server\.web\["(web-\d+)"\]` match — the load-bearing declared residual
  at guard:1404-1413. The `fleet_elsewhere` arm (guard:1513-1548) skips any
  block whose `dialed` set is empty, so indirection is invisibility. Battery
  control G2-C6 (`web-host-provisioner-parity-mutation.test.sh:1698-1719`)
  deliberately pins the gap green with the note "If an unclassifiable-dial arm
  lands later, this control flips RED — deliberately."

User impact is the same class as #9998: an SSH delivery channel outside
server.tf that either mutates silently inside a waived member (#10147) or is
born unclassifiable (#10148) applies with the parity guard reporting clean.

## Research Insights

**Premise validation (Phase 0.6).** Checked: #10147 and #10148 are both OPEN
with `deferred-scope-out`; parent #9998 is CLOSED via merged PR #10130 — the
"deferred hardening" framing holds. Every cited artifact verified in the
worktree: `EXT_RESIDENCE` at guard:1479 (four seeded members — ci-ssh-key.tf
`root_authorized_keys`; workspaces-luks.tf `luks_monitor_token_install`,
`luks_monitor_install`, `workspaces_boot_unlock_install`); `dialed_hosts`
literal-only at guard:1414-1415 with the residual declared at :1404-1413;
`fleet_elsewhere` at :1513-1548; stale-allowance arm at :1550-1586;
`expect_red`/`expect_green` at battery:293/320; G2-C6 at battery:1698-1719;
`FLOOR=95` census comment at battery:1913; `expect_probe_red`/`expect_probe_green`
helpers at battery:1036/1060 hardcoding `SOLEUR_PARITY_ALLOWLIST_PROBE`;
probe floors `PROBE_FLOOR=7`/`PROBE_RED_FLOOR=6` at :1929-1930; the G2
reader-shape pin (exactly one `"ls-files"`, one `read_text(`, zero `open(`/
`glob(`) at battery:187-194. Two cosmetic drifts: issue #10147 cites the
waiver comment at "~line 1450" (actual: 1461-1478); issue #10148's "allowlist-able
literal set" maps to `hcloud_server.web["web-\d+"]`.

**Premise nuance — "the four seeded members are covered by sibling pins".**
Verified per member: `luks_monitor_install` + `luks_monitor_token_install` are
body-pinned by `apps/web-platform/infra/luks-monitor-install.test.sh` (Guard 2
there enumerates provisioners, command order, sources); `workspaces_boot_unlock_install`
by `apps/web-platform/infra/workspaces-boot-unlock.test.sh` (TF1 exact-header +
provisioner checks + -target wiring); `root_authorized_keys` by
`plugins/soleur/test/terraform-target-parity.test.ts` (:108 exclusion allowlist
membership, :1252 `terraform_data.root_authorized_keys` -target presence) —
wiring-level, not body-level: no suite pins its provisioner content. The `pin`
field makes that asymmetry a declared, reviewable fact per member rather than a
uniform assumption.

**Baseline.** Real-tree connection blocks outside server.tf: exactly the four
literal web-1 dialers above (verified — the `connection` grep hits in
`betterstack-logs-alerts.tf`, `dns.tf`, `git-data.tf`, `github-app.tf`,
`inngest-host.tf`, `inngest.tf`, `sentry/issue-alerts.tf`, `tunnel.tf`,
`variables.tf` are comment/prose only, pinned by G2-C2). Zero unclassifiable
outside-server.tf blocks exist → both new arms fire zero times on the pristine
tree.

**Property List (Phase 0.6b).**

- P1 (#10148) — A swept `connection` block outside
  `apps/web-platform/infra/server.tf` whose `dialed_hosts` is empty is a
  finding; no unclassifiable SSH channel is born without a table diff.
- P2 (#10148) — The exemption surface stays single: a legitimate unclassifiable
  dial is acknowledged through `EXT_RESIDENCE` (an explicit marker), never
  through a second table; literal-dial semantics are unchanged.
- P3 (#10147) — Every `EXT_RESIDENCE` entry names a collateral pin covering the
  member's provisioner content — mandatory, shaped (`*.test.sh`/`*.test.ts`),
  repo-relative, extant — enforced at guard runtime like `reason`.
- P4 — The new arms are proven: `.tf`-reachable behavior gets `expect_red`
  rows anchoring on each arm's own `[FAIL]` text; table-internal invariants
  get an additive-only probe (`SOLEUR_PARITY_EXT_RESIDENCE_PROBE`, never
  merged into the exemption consults — the §5 `SOLEUR_PARITY_ALLOWLIST_PROBE`
  precedent), and must-PASS controls prove the arms discriminate.

**Cut List (Phase 0.6b).**

- *In-guard per-member provisioner-shape pin (anchors on member bodies)* →
  buys "member content is bound" — REJECTED: duplicates the richer content
  pins sibling suites already own (`luks-monitor-install.test.sh` enumerates
  the same bodies in far more detail), creating a second pin surface that
  must be kept in sync. The gap is not "no pin exists" but "nothing forces a
  new member to carry one" — the declared-`pin` requirement closes exactly
  that.
- *Provisioned-content hash in the entry* → REJECTED: per-edit churn — a
  cosmetic provisioner edit would demand a table diff every time, training
  table-diff fatigue on the surface whose diffs are supposed to be rare and
  reviewed.
- *Resolving HCL indirection (alias/var/each chase)* → buys "the dial target
  is known" — REJECTED: a different, larger mechanism (cross-file locals,
  module outputs); the issue asks for flagging, not resolution. Carried as a
  design note under Technical Considerations.
- *Arm coverage inside server.tf* → REJECTED (scope): §1 already pins literal
  hosts on `terraform_data` members (battery row M3 reds `local.web1_ip` via
  `not-web-1-or-web-2-pinned=`); a non-`terraform_data` indirect dialer inside
  server.tf is a named residual, not this issue's scope ("outside server.tf").
- *A second `UNCLASSIFIABLE_DIALERS` table* → REJECTED: `EXT_RESIDENCE` is the
  declared single exemption surface; an `unclassifiable` marker field keeps it
  single.
- *Declarative-only `pin` (non-empty string, no existence check)* → REJECTED:
  a typo'd pin path slips silently — the exact silent-drift class this guard
  exists to catch; `is_file()` under `REPO` makes it mechanical at ~zero cost.

**Key files.** Guard 2 heredoc `G2EOF` in
`apps/web-platform/infra/web-host-provisioner-parity.test.sh`: block collection
with span-containment attribution at :1218-1337 (`blocks` tuples
`(loc, body, addr, kind)`), `dropped_hdrs`/`dup_addrs` at :1344-1369,
`dialed_hosts`/`is_ssh_conn` at :1414-1424, host_key arms at :1426-1459,
`EXT_RESIDENCE` + standing-waiver comment at :1461-1505, `fleet_elsewhere` at
:1507-1548, `stale_ext` hygiene at :1550-1586, local shape pins at :1588-1615.
Battery `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`:
`EXPECTED_INPUTS`/`DERIVED_INPUTS` reconciliation at :81-93, sandbox + copy loop
at :223-245, `expect_red`/`expect_green` at :293/:320, probe helpers at
:1036-1071, §5 probe rows P1-P7 at :1073-1120, G2 rows at :1265-1882 (G2-C5
:1681, G2-C6 :1698, G2-4 :1721, G2-10/11 :1782-1799, G2-12 :1803, G2-C2 :1869,
`_g2_json_row` + G2-13/14/C3 at :1845-1867), accounting + floors at :1885-1944.

**Repo conventions to reuse.** Reason-mandatory table fields enforced in the
same hygiene pass (`reason.strip()`); additive-only env probes for
table-internal invariants (`SOLEUR_PARITY_ALLOWLIST_PROBE` → `check_allowlist`,
with the P4 negative control proving the probe can never suppress a real
finding); `expect_red` anchors as substrings of the arm's own `[FAIL]` text;
`FLOOR`/`cases`/`PROBE_*` comments re-derived when rows are added; reader-shape
pins making any new guard input a deliberate two-file edit.

**Learnings.** `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
(the Guard Contract class both arms must satisfy — a guard over a structured
language lexes, never scans columns; the swept `blocks` set is the chokepoint);
`2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md`
(anchor attribution); `2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md`
(census over the swept set, not the plan's name list — the unclassifiable arm
IS the red unclassified bucket for outside-server.tf dials);
`2026-10-12-the-guards-own-normalizer-is-attack-surface-treat-text-preprocessing-as-fail-open.md`.
ADR-237 (host_key pinning + the recorded two-file layout); ADR-193 (battery
accounting conservation); ADR-114 (do-not-repoint connection hosts).

**External research.** Skipped — internal guard machinery with strong local
precedent; no external API, framework, or security-protocol decision.

**Functional overlap.** `web-hosts-fanout-parity.test.sh` pins `var.web_hosts`
keys (different property); `terraform-target-parity.test.ts` pins `-target=`
sets (different property — becomes a `pin` value here, not an overlapping
mechanism); the luks/workspaces suites pin member *content* but not the
*requirement to be pinned* — that requirement is what #10147 adds. No repo
mechanism buys P1 or P3.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| Waiver comment at `web-host-provisioner-parity.test.sh` "~line 1450" | Comment block spans :1461-1478 | Cosmetic drift; comment updated in place |
| "the four seeded members are covered by sibling pins (workspaces-luks / ci-ssh-key suites)" | 3 luks members have dedicated body-pin suites; `root_authorized_keys` has a wiring-level pin (`terraform-target-parity.test.ts`), no body-level suite | `pin` populated per member with its real suite; the asymmetry is declared in the table and reviewed per entry — the bound's job is forcing the declaration |
| "battery control G2-C6 pins the gap green" | `expect_green` at battery:1705 with the "flips RED — deliberately" note | Row converts to `expect_red` G2-38, same mutator, anchor `unclassifiable` |
| `.tf.json` connection pinned to the local stays GREEN (G2-C3) | After the arm lands, EVERY outside-server.tf unclassifiable block — `.tf` or `.tf.json` — is flagged; no green .tf.json-outside-server.tf shape exists | G2-C3 converts to a red `_g2_json_row` pinning the arm's .tf.json coverage (a control whose premise dies gets converted, not deleted — the mutation it kills is preserved) |

## Hypotheses

The `hr-ssh-diagnosis-verify-firewall` gate fired on the `SSH` token (telemetry
emitted). Same opt-out as the parent plan: the change is static source
analysis — the battery pins that Guard 2 reads files only through one
`git ls-files` enumeration and one `read_text()` call site, so no live SSH
session exists anywhere in the code path under change.

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | not applicable — no live dial | reader-shape pin at `web-host-provisioner-parity-mutation.test.sh:187-194` |
| L3 DNS / routing | not applicable — no live dial | same |
| L7 TLS / proxy | not applicable — no HTTPS path | same |
| L7 application | not applicable — no service under diagnosis | defect class is a text-sweep classification gap, reproduced statically |

## Proposed Solution

Two parts, one atomic PR — the guard arms without their battery rows are
unproven, and the battery rows without the arms red CI today (G2-C6's mutation
is green now precisely because the arm does not exist).

### Part 1 — Guard-side (`web-host-provisioner-parity.test.sh`, G2 program)

1. **`EXT_RESIDENCE` schema gains two fields.** Each entry becomes
   `{"hosts": frozenset, "reason": str, "pin": str, "unclassifiable": bool}`:
   - `pin` (mandatory): repo-relative path to the `*.test.sh`/`*.test.ts` file
     that pins the member's provisioner content. Seeds:
     `luks_monitor_install` and `luks_monitor_token_install` →
     `apps/web-platform/infra/luks-monitor-install.test.sh`;
     `workspaces_boot_unlock_install` →
     `apps/web-platform/infra/workspaces-boot-unlock.test.sh`;
     `root_authorized_keys` →
     `plugins/soleur/test/terraform-target-parity.test.ts` (wiring-level
     coverage — declared residual, see Reconciliation).
   - `unclassifiable` (optional, default false): declares that the member's
     dials may be non-literal/non-web — the reviewed acknowledgment a new
     indirect or non-web dialer needs. `hosts` may be empty only when the flag
     is set.
2. **Unclassifiable-dial arm** (after `fleet_elsewhere`): iterate ALL `blocks`
   (conn + dynamic-spelled, `.tf` + `.tf.json`, winrm-labeled included — the
   fleet arm's fail-closed precedent), skip `fpath ==
   "apps/web-platform/infra/server.tf"`; when `dialed_hosts(b)` is empty,
   exempt only if the `(fpath, addr)` entry exists AND carries
   `unclassifiable: true`; otherwise append to `unclassifiable`. FAIL text
   carries the literal `unclassifiable`:
   `"G2: unclassifiable connection dial(s) outside server.tf — the host
   expression is not a literal hcloud_server.web[\"web-N\"] reference the guard
   can classify: …"`. A block with no `host` at all is unclassifiable by
   construction (empty dialed — fail-closed).
3. **Hygiene arm extension** (the existing `stale_ext` loop, :1550-1586): per
   entry additionally require — `pin` present, non-empty string, no leading `/`
   or `..` segment, `*.test.sh`/`*.test.ts` suffix, `(REPO / pin).is_file()`
   (a stat, not a read — the reader-shape pin is untouched); ≥1 swept block
   attributed to `(fpath, rname)` (new check — required for `unclassifiable`
   entries where `hosts ⊆ dialed` is vacuous at `∅ ⊆ ∅`, and a tightening for
   literal entries where it was only implied); `hosts ⊆ dialed` unchanged;
   `reason` non-empty unchanged. FAIL literals: `EXT_RESIDENCE pin` for the pin
   checks, `stale EXT_RESIDENCE` retained for resolution.
4. **`SOLEUR_PARITY_EXT_RESIDENCE_PROBE`** (env, JSON
   `{file: {rname: {"hosts": [...], "reason": "…", "pin": "…",
   "unclassifiable": bool}}}`): parse with the §5 probe's shape discipline
   (unparseable JSON / non-object / wrong field types each get a named
   `[FAIL]`, never a traceback), normalize `hosts` lists to sets, and run the
   SAME hygiene checks reporting `EXT_RESIDENCE probe` findings. **Probe
   entries are never merged into the `fleet_elsewhere`/unclassifiable
   exemption consults** — additive-only, the P4 precedent.
5. **Comment updates:** the standing-waiver comment (:1470-1476) documents the
   bound — every entry must carry `pin` naming the suite that bounds the
   member's provisioner bodies; the `dialed_hosts` residual comment
   (:1404-1413) is updated (the gap is closed; G2-C6's pin flips); the
   `EXT_RESIDENCE` doc comment (:1461-1478) documents both new fields.

### Part 2 — Battery-side (`web-host-provisioner-parity-mutation.test.sh`)

| Row | Mutation / probe | Anchor | Proves |
|---|---|---|---|
| G2-38 (was G2-C6) | Same mutator — `terraform_data.g2_indirect` in `tunnel.tf` with `host = local.web_1_ipv4` + valid `host_key` | `unclassifiable` | P1 — the pinned gap is now the pinned coverage |
| G2-39 | Raw-IP dialer `host = "203.0.113.10"` WITH `host_key = local.web_1_ssh_host_key` in `tunnel.tf` | `unclassifiable` | P1 — isolates the arm: every host_key arm passes, only unclassifiability fires |
| G2-40 | TWO unclassifiable dialers (`host = var.web1_ip`, `host = each.value.ipv4`) in `tunnel.tf` | `unclassifiable` (+ second resource name) | iteration completeness — the arm does not stop at the first member |
| G2-C3 → red | `.tf.json` connection `{"host":"192.0.2.14","host_key":"${local.web_1_ssh_host_key}"}` in `zz-g2.tf.json` | `unclassifiable` | P1 — `.tf.json` is swept by the same arm |
| G2-C7 (green) | A provisioner-body edit inside a workspaces-luks member | — | must-PASS: the bound is the pin requirement, not in-guard content matching — member content is NOT re-pinned here |
| X1 (probe red) | `SOLEUR_PARITY_EXT_RESIDENCE_PROBE='{oops'` | `not parseable JSON` | probe input discipline (P6 analog) |
| X2 (probe red) | entry missing `pin` | `pin` | P3 — the field is mandatory |
| X3 (probe red) | `pin` naming a nonexistent path (e.g. `apps/web-platform/infra/nope.test.sh`) | `pin` | P3 — existence is mechanical |
| X4 (probe red) | `pin` not `*.test.*`-shaped (e.g. `apps/web-platform/infra/server.tf`) | `pin` | P3 — the pin must be a test artifact |
| X5 (probe red) | `unclassifiable: true` entry for a fake resource in a real member file | `stale EXT_RESIDENCE` | the ≥1-swept-block requirement reaches flagged entries |
| X6 (probe red, negative control) | mutator adds the G2-38 phantom AND a probe entry covers `(tunnel.tf, terraform_data.g2_indirect)` with `unclassifiable: true` | `unclassifiable` | probe can never exempt — the P4 analog |
| X7 (probe green) | well-formed entry naming a real member (`ci-ssh-key.tf` / `root_authorized_keys`) with hosts `[web-1]` + real pin | — | the probe discriminates; well-formed entries pass |

**Pin-file sandbox copies.** The seeds' `pin` existence check resolves under
`REPO` (= `SOLEUR_TF_REPO` in the sandbox), so the three pin files are added to
the sandbox file set (the `../../../`-relative copy convention already used for
`infra/github/main.tf`): derived from the guard's own `"pin"` values and
reconciled against a hardcoded `G2_PIN_INPUTS` list — divergence is FATAL, the
`EXPECTED_INPUTS`/`DERIVED_INPUTS` pattern. A new entry whose pin is not yet
sandboxed fails loudly on the baseline row.

**Accounting.** `mutations_run`: G2-C6 was `expect_green` (uncounted); G2-38/39/40
add 3 → `FLOOR` 95 → **98** (G2-C3's `_g2_json_row` stays counted, direction
changes only). Probes: +6 red +1 green → `PROBE_FLOOR` 7 → **13**,
`PROBE_RED_FLOOR` 6 → **12**. `cases` +10. All three comments re-derived from
the battery log per file convention.

## Technical Considerations

**Attack-surface enumeration** (an SSH delivery channel outside server.tf can
exist as):

- (a) literal `hcloud_server.web["web-N"]` dial → `fleet_elsewhere` + entry — unchanged.
- (b) indirect spelling (`local.*`, `var.*`, `each.value`, `self`) → **this fix** —
  unclassifiable arm.
- (c) raw IP / arbitrary string → **this fix** — same arm (a fleet host's
  current IP spelled literally is the same escape).
- (d) literal non-web reference (`hcloud_server.git_data.*`, module outputs) →
  **this fix** — equally invisible to `dialed_hosts`; flagged unless an
  `unclassifiable`-flagged entry acknowledges it.
- (e) `.tf.json` → covered (dict blocks flow through the same `blocks` set).
- (f) `dynamic "connection"` spelling → covered (`kind == "dyn"` bodies are
  swept; the arm iterates `blocks`, not `ssh_blocks`).
- (g) winrm-labeled → covered (same fail-closed precedent as `fleet_elsewhere`:
  label does not buy invisibility).
- (h) inside server.tf → §1's census owns `terraform_data` members (M3 proves
  `local.*` repoint reds via `not-web-1-or-web-2-pinned=`). **Named residual:**
  a non-`terraform_data`/unattributed indirect dialer inside server.tf escapes
  §1 AND this arm — out of both issues' scope; flagged here as the next gap
  candidate if it ever materializes.
- (i) member provisioner bodies → **this fix** (#10147) — `pin` field forces a
  declared collateral pin per entry.

**Probe safety.** `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` mirrors §5: additive-only
validation, never merged into the exemption consults — X6 is the negative
control proving a probe entry cannot suppress a real unclassifiable finding.
The `unclassifiable: true` *exemption* path itself remains table-internal —
battery-unreachable, runtime + review verified, the same standing limitation
the table already carries (documented in the guard comment).

**Reader-shape pin.** `is_file()` is a stat — `"ls-files"` stays 1,
`read_text(` stays 1, `open(`/`glob(` stay 0; the battery's reader-shape pin is
untouched. Pin-file *content* verification (member name appears inside the pin
file) would require a second `read_text(` — deferred: declared + review-verified
name-binding beats a reader-pin amendment for this pass.

**Sequencing.** Guard and battery land in one PR; interim (guard alone) is
proven-but-unproven, interim (battery alone) is red-on-main (G2-38's mutation
reds only once the arm exists).

## Open Code-Review Overlap

None — checked 2026-10-12 against open `code-review` issues (200 fetched): no
open issue body mentions `web-host-provisioner-parity.test.sh`,
`web-host-provisioner-parity-mutation.test.sh`, or the
`web-host-provisioner-parity` prefix.

## User-Brand Impact

- **If this lands broken, the user experiences:** under-fire — a new
  unclassifiable SSH channel or a member content edit slips through with the
  guard reporting clean (the #9998-class silent delivery path); over-fire — a
  false `unclassifiable`/`pin` finding reds legitimate infra PRs and degrades
  the fix path on live hosts.
- **If this leaks, the user's workflow is exposed via:** an unaudited SSH
  delivery channel to a web host — invisible to classification, drifting
  without a finding.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: files under apps/web-platform/infra/ match the
  sensitive-path regex by directory, but this diff edits guard/test scripts
  only — no Terraform resource, credential, or delivery-path change reaches a
  host.`

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
  - mode: unclassifiable-dial arm regression (arm deleted or predicate narrowed)
    detection: mutation rows G2-38/G2-39/G2-40 + converted G2-C3 redden on `unclassifiable`
    alert_route: CI check failure blocks the PR
  - mode: pin requirement rot (field dropped, check neutered, stale pin path)
    detection: probe rows X2/X3/X4 redden on `pin`; unsandboxed pin fails the baseline row
    alert_route: CI check failure blocks the PR
  - mode: probe turned fail-open (merged into exemption consults)
    detection: negative-control row X6 reddens
    alert_route: CI check failure blocks the PR
  - mode: stale/indirect entry rot
    detection: stale-allowance arm + probe row X5
    alert_route: CI check failure blocks the PR
logs:
  where: GitHub Actions job output for the infra-validation leg
  retention: GitHub Actions default retention
discoverability_test:
  command: bash apps/web-platform/infra/web-host-provisioner-parity.test.sh
  expected_output: 0 failed
```

The guard runs ~2.4s on the worktree — under preflight Check 10's 15s cap;
`bash` is on `PROBE_VERB_ALLOWLIST`; `0 failed` is the literal substring the
guard prints. The ~101s mutation suite is deliberately NOT the probe.

## Guard Contract

### Guard 1 — unclassifiable-dial arm

**Property.** Every swept `connection` block outside
`apps/web-platform/infra/server.tf` is classifiable — its `dialed_hosts` is
non-empty (the `fleet_elsewhere` arm owns it) — or it is covered by an
`EXT_RESIDENCE` entry for its `(file, type.name)` carrying
`unclassifiable: true`. There is no third state.

**Assembly.** Guard 2's single enumeration — `git ls-files --cached --others
--exclude-standard -- '*.tf' '*.tf.json'` feeding `blocks` — is the one
chokepoint every connection block in the repo flows through (the battery pins
exactly one `"ls-files"` and one `read_text(` call site). The property
quantifies over every `blocks` member whose `fpath` is not server.tf; the only
exemption consult is `EXT_RESIDENCE`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `terraform_data` with `host = local.web_1_ipv4` + valid `host_key` to `tunnel.tf` (the pinned gap — G2-38) | RED via `unclassifiable` |
| 2 | Append a raw-IP dialer with valid `host_key` to `tunnel.tf` (G2-39) | RED via `unclassifiable` — isolates the arm from every host_key arm |
| 3 | (second member) Append TWO unclassifiable dialers (`var.*`, `each.value`) in one file (G2-40) | RED via `unclassifiable`, both named — iteration does not stop at the first |
| 4 | (.tf.json shape) `zz-g2.tf.json` raw-IP dial (converted G2-C3) | RED via `unclassifiable` |
| 5 | (precondition-held → different arm) literal `hcloud_server.web["web-1"]` dialer in `tunnel.tf` | RED via `outside server.tf` — NOT `unclassifiable`; classification routes the block to the right arm (G2-19) |
| 6 | (dispatch) neuter the arm's iteration so `blocks` outside server.tf is never inspected | RED — the phantom rows above stop firing; swept floors (`FLOOR_BLOCKS`, accounting conservation) catch a silently-empty set |
| 7 | (harness must-PASS) real tree unchanged | GREEN — zero unclassifiable blocks exist today (verified) |
| 8 | (harness must-PASS, non-canonical) provisioner-body edit inside a member (G2-C7) | GREEN — member content is not re-pinned in this guard |

**Anchor.** The arm compares swept reality to the exemption table: a weakening
must edit `EXT_RESIDENCE` AND land the dialer — the entry IS the review surface.
`unclassifiable: true` declarations are themselves hygiene-checked (≥1 swept
block, pin extant), so the marker cannot be asserted over nothing.

### Guard 2 — EXT_RESIDENCE collateral-pin bound + flagged-entry hygiene

**Property.** Every `EXT_RESIDENCE` entry is content-bound and resolves:
`pin` names an extant repo `*.test.*` file (the member's collateral pin),
`reason` is non-empty, the resource still sweeps ≥1 block at its declared
`(file, type.name)`, and `hosts ⊆ dialed` (with `hosts` empty only under
`unclassifiable: true`).

**Assembly.** The single `EXT_RESIDENCE` table + the `stale_ext` hygiene loop —
table-internal and unreachable from `.tf` mutation, so the probe injects
entries through the SAME checks (`SOLEUR_PARITY_EXT_RESIDENCE_PROBE`,
additive-only, never consulted by the exemption arms).

**Mutation matrix (probe-driven):**

| # | Mutation | Expected |
|---|---|---|
| 1 | Probe entry missing `pin` | RED via `pin` |
| 2 | Probe `pin` naming a dangling path | RED via `pin` |
| 3 | Probe `pin` not `*.test.*`-shaped | RED via `pin` |
| 4 | (dispatch) Probe entry naming a resource that sweeps no block | RED via `stale EXT_RESIDENCE` — the ≥1-swept-block check reaches flagged entries |
| 5 | (second member) a malformed SECOND probe entry after a well-formed first | RED — hygiene iterates every entry |
| 6 | (negative control) `unclassifiable: true` probe entry covering a phantom whose mutation is also applied | still RED via `unclassifiable` — the probe cannot exempt |
| 7 | (harness must-PASS) well-formed probe entry naming a real member + real pin | GREEN — hygiene discriminates |
| 8 | (harness must-PASS) real tree: all four seeds' pins resolve | GREEN — the baseline row is live proof the field is not vestigial |

**Anchor.** `pin` is a stored path compared against the repo enumeration — a
weakening must forge both the table entry and a real file in one diff, which is
the declared shape of the mechanism (the entry IS the review surface).
Existence-only (not content-binding) is the deliberate scope: what the named
suite covers is review-verified, as with `reason`.

## Architecture Decision (ADR/C4)

None required — detection does not fire. This change tightens an existing CI
guard's classification boundary; it moves no ownership/tenancy boundary,
introduces no substrate or integration, changes no resolver/dispatch contract,
and diverges from no ADR (ADR-237's host-key pinning and ADR-114's
no-repoint rule are untouched — the guard is their enforcement surface, being
hardened). C4 check performed against `diagrams/model.c4`, `views.c4`,
`spec.c4`: no new external actor, external system, container/data-store, or
access relationship is introduced — CI test suites are not modeled elements,
and every actor/system the suites touch (GitHub Actions, the `.tf` corpus) is
already modeled.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "#10147 — a per-member content bound (e.g., pinned provisioner shape or a dedicated collateral pin requirement for NEW entries, documented in the guard's standing-waiver comment at ~line 1450)" | `pin` field + hygiene-arm enforcement + seeds + comment update (Proposed Solution Part 1, items 1/3/5; Phases 1-2) | mapped |
| 2 | "#10148 — an unclassifiable-dial arm — any `connection {}` outside `server.tf` whose host expression is not in the allowlist-able literal set gets flagged for review" | `unclassifiable` arm + `unclassifiable` entry marker (Part 1 items 1/2) | mapped |
| 3 | "#10148 — battery control `G2-C6` (which currently pins the gap green) flips RED to force the acknowledgment" | G2-C6 → `expect_red` G2-38 (Part 2) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `pin` field + runtime existence/shape check | "a dedicated collateral pin requirement for NEW entries" | asked — the existence check is the mechanical form of "requirement" (declarative-only rejected, Cut List) |
| `unclassifiable: true` entry marker as the review path | "gets flagged for review" | inferred — a flag with no waiver makes legitimate non-web/indirect dials unrepresentable; the marker keeps `EXT_RESIDENCE` the single exemption surface while every acknowledgment still costs a table diff |
| `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` + rows X1-X7 | — | inferred — table-internal invariants are unreachable from `.tf` mutation; the §5 probe precedent is the repo's own mechanism for driving them red |
| ≥1-swept-block requirement per entry | — | inferred — `unclassifiable` entries make `hosts ⊆ dialed` vacuous at `∅ ⊆ ∅`; without it a vanished flagged member's entry rots silently |
| G2-39/G2-40 rows (beyond the asked G2-38 flip) | — | inferred — the Guard Contract requires ≥3 mutations per guard incl. a second-member row; G2-39 additionally isolates the arm from host_key arms |
| G2-C3 conversion (green → red) | — | inferred — the row's green premise dies with the arm; converting preserves .tf.json coverage instead of silently dropping a case |
| G2-C7 green control | — | inferred — a must-PASS row pinning that member content is NOT re-checked in-guard (prevents a future "shape-pin creep" from turning the bound into the rejected mechanism) |
| Pin-file sandbox copies + `G2_PIN_INPUTS` derivation | — | inferred — the `is_file()` check resolves under `SOLEUR_TF_REPO`; without copies the arm fires spuriously on every sandboxed run |
| server.tf-internal indirection residual | — | inferred — the issue scopes to "outside server.tf"; §1 already pins `terraform_data` member hosts literal (M3) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (two files under `infra/`)
- Planned files: 2 | Estimated changed lines: ~200-280 (guard ~80-120 incl.
  schema + arm + probe; battery ~120-160 incl. rows + sandbox copies +
  re-derived floors)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications — infrastructure/tooling change confined to a CI
guard and its mutation battery. Mechanical UI-surface override: no path in
`## Files to Edit`/`## Files to Create` matches the UI-surface term list or glob
superset (`.sh` under `infra/` only).

## Implementation Phases

### Phase 1 — Guard arms (`web-host-provisioner-parity.test.sh`, G2 heredoc)

1. Extend `EXT_RESIDENCE` entry schema (`pin` mandatory, `unclassifiable`
   optional); populate the four seeds' pins; extend the entry doc comment.
2. Add the unclassifiable-dial arm after `fleet_elsewhere` (iterate all
   `blocks`, skip server.tf `fpath`, exempt via `unclassifiable: true` entries;
   FAIL literal contains `unclassifiable`).
3. Extend the `stale_ext` hygiene loop: `pin` shape (`*.test.*`, repo-relative,
   no `..`/`/`-leading) + `(REPO / pin).is_file()`; ≥1 swept block per entry;
   `hosts` non-empty unless `unclassifiable: true`; existing `hosts ⊆ dialed`
   and `reason` checks unchanged.
4. Add `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` parsing + shape validation + the
   same hygiene checks on probe entries (`EXT_RESIDENCE probe` FAIL prefix) —
   never merged into the exemption consults.
5. Update the standing-waiver comment (:1470-1476) to document the bound and
   the `dialed_hosts` residual comment (:1404-1413) now that the gap is closed.

### Phase 2 — Battery (`web-host-provisioner-parity-mutation.test.sh`)

1. Convert G2-C6 → `expect_red "G2-38 …"` (same mutator, anchor
   `unclassifiable`); add G2-39, G2-40.
2. Convert G2-C3 to a red `_g2_json_row` anchoring `unclassifiable`.
3. Add G2-C7 green control (member provisioner-body edit).
4. Add the `EXT_RESIDENCE` probe helper pair (env var
   `SOLEUR_PARITY_EXT_RESIDENCE_PROBE`) + rows X1-X7.
5. Add pin-file sandbox copies derived from the guard's `"pin"` values,
   reconciled against hardcoded `G2_PIN_INPUTS` (FATAL on drift).
6. Re-derive `FLOOR` (95→98), `PROBE_FLOOR` (7→13), `PROBE_RED_FLOOR` (6→12),
   `cases` (+10) from the battery log; update comments.

### Phase 3 — Verification

1. `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` — GREEN
   on the real tree; both new arms print ok-lines.
2. `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
   — all rows pass; `guard still PASSED` must not appear for G2-38 (today's
   defect signature); no existing row flips (G2-18/19 anchors resolve).
3. `shellcheck` both files (pre-existing SC1091 artifact tolerance per #10130).

## Files to Edit

- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — G2 program:
  `EXT_RESIDENCE` schema + seed pins, unclassifiable-dial arm, hygiene-arm
  extension, `SOLEUR_PARITY_EXT_RESIDENCE_PROBE`, standing-waiver + residual
  comments.
- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` —
  G2-38/39/40 rows, G2-C3 conversion, G2-C7 control, probe helper + X1-X7,
  pin-file sandbox copies + `G2_PIN_INPUTS`, floor re-derivations.

## Files to Create

None.

## Acceptance Criteria

- [ ] AC1: A `terraform_data` block in `tunnel.tf` with
  `host = local.web_1_ipv4` and `host_key = local.web_1_ssh_host_key` reds via a
  `[FAIL]` line containing `unclassifiable` (battery row G2-38 — the converted
  G2-C6, closing the pinned gap).
- [ ] AC2: A raw-IP dialer with a valid pinned `host_key` outside server.tf
  reds via `unclassifiable` while every host_key arm passes (G2-39); two
  unclassifiable dialers in one file are both named (G2-40); a `.tf.json`
  unclassifiable dial reds (converted G2-C3).
- [ ] AC3: `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh`
  exits 0 on the real tree — zero unclassifiable blocks exist, all four
  `EXT_RESIDENCE` seeds pass pin + stale hygiene and print the ok-line.
- [ ] AC4: Every `EXT_RESIDENCE` entry carries `pin` naming an extant
  repo-relative `*.test.sh`/`*.test.ts` file; probe rows prove missing pin,
  dangling pin, and non-`*.test.*` pin each red via `pin` (X2/X3/X4).
- [ ] AC5: An `unclassifiable: true` entry is the only waiver for an
  unclassifiable block; a flagged entry resolving to no swept block is stale
  (X5); `hosts` may be empty only under the flag.
- [ ] AC6: `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` is additive-only — a probe entry
  covering a swept unclassifiable phantom does not suppress its `unclassifiable`
  finding (X6); malformed probe input is named, never a traceback (X1); a
  well-formed probe entry passes (X7).
- [ ] AC7: The standing-waiver comment in `web-host-provisioner-parity.test.sh`
  documents the per-member content bound — every entry must carry `pin` naming
  the suite that bounds the member's provisioner bodies (#10147's explicit ask).
- [ ] AC8: `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  exits 0; `FLOOR`/`PROBE_FLOOR`/`PROBE_RED_FLOOR`/`cases` comments match the
  re-derived census; no pre-existing row flips.
- [ ] AC9: A provisioner-body edit inside a workspaces-luks member keeps the
  guard GREEN (G2-C7) — the bound is the pin requirement, not in-guard content
  matching.
- [ ] AC10: §1's census and the `fleet_elsewhere` arm are untouched — literal
  fleet dials still route to the residence arm (G2-19's `outside server.tf`
  anchor still resolves).

## Test Scenarios

- Given the real tree, when the guard runs, then it reports `0 failed` — zero
  unclassifiable blocks, all four seeds' pins resolve. (`integration`, baseline)
- Given `host = local.web_1_ipv4` in a new `terraform_data` in `tunnel.tf`,
  when the guard runs, then it exits non-zero with `unclassifiable` in `[FAIL]`
  output. (`integration`, G2-38 — regression for #10148)
- Given `host = "203.0.113.10"` with a valid pin outside server.tf, when the
  guard runs, then it reds via `unclassifiable` only. (`integration`, G2-39)
- Given two unclassifiable dialers in one file, when the guard runs, then both
  appear in the findings. (`integration`, G2-40)
- Given an `EXT_RESIDENCE` probe entry with no `pin`, when the guard runs, then
  it reds via the `pin` finding. (`probe`, X2)
- Given a probe entry covering a real unclassifiable phantom, when the guard
  runs, then the phantom still reds via `unclassifiable` — the probe cannot
  exempt. (`probe`, X6 — negative control)
- Given a member with a benign provisioner-body edit, when the guard runs,
  then it stays green — content is bounded by the declared pin, not re-pinned
  in-guard. (`integration`, G2-C7)

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `pin` field becomes ceremonial (names a file that pins nothing) | Same standing as `reason`: the field is mandatory + shaped + extant, adequacy is review-verified; seeds name real suites as the model |
| An indirect member's `unclassifiable` flag rots (resource deleted, flag stays) | New ≥1-swept-block check per entry; probe row X5 reds on exactly that shape |
| Probe merged into exemption consults → fail-open | Probe entries never join `EXT_RESIDENCE` for `fleet_elsewhere`/unclassifiable; X6 is the negative control proving non-suppression |
| Pin-file `is_file()` fails under the battery sandbox | `G2_PIN_INPUTS` copies + derivation reconciliation; an unsandboxed pin fails loudly on the baseline row |
| `.tf.json` green control premise dies silently | G2-C3 converted to a red row, not deleted — .tf.json coverage of the arm preserved |
| Anchor drift: renaming FAIL text un-pins existing rows | `unclassifiable`/`pin`/`stale EXT_RESIDENCE` literals specified; G2-18/19's `outside server.tf` untouched |
| Inside-server.tf indirection perceived as closed | Named residual (Technical Considerations h) — scope is "outside server.tf" per the issue; §1 already covers `terraform_data` members |
| Merge fires the apply workflow on `infra/**` | No `.tf`/`triggers_replace` change → no-diff apply; PR body carries the merge-effect first line |

**Precedent-diff.** `pin` vs `reason` (guard `ALLOWLIST`/`ONLY_JUSTIFIED` idiom:
mandatory field, same hygiene pass); probe vs `SOLEUR_PARITY_ALLOWLIST_PROBE`
(same parse-shape discipline, additive-only, dedicated negative control);
`unclassifiable` arm vs `fleet_elsewhere` (same `blocks` iteration, same
fail-closed philosophy incl. winrm/dynamic kinds); G2-38 conversion vs the
battery's own "control that pins a gap flips RED" note; `G2_PIN_INPUTS` vs
`EXPECTED_INPUTS`/`DERIVED_INPUTS` (hardcoded list reconciled against
guard-derived values, FATAL on drift).

## Non-Goals

- Resolving HCL indirection (alias/var/each/module-output chase) — the arm
  flags unclassifiable dials; it does not resolve them.
- Inside-server.tf indirection under non-`terraform_data` types — named
  residual; the issue scopes to outside server.tf and §1 already pins
  `terraform_data` member hosts literal.
- Pin-file *content* verification (member name appearing inside the pin file)
  — would require a second `read_text(` call site and a reader-shape-pin
  amendment; declared + review-verified name-binding is the bound for this
  pass.
- Body-level coverage upgrade for `root_authorized_keys` beyond its declared
  `terraform-target-parity.test.ts` pin — the asymmetry is declared, not
  silently fixed.
- Relocating the seeded members or re-scoping §1's census — parent plan's Cut
  List stands.

## Context

- **Merge-side production effect (PR body first line):** the diff edits only
  `*.test.sh` files — zero `.tf` change, zero `triggers_replace` change, so the
  routine per-merge apply delivers nothing new. `apply-web-platform-infra.yml`
  still fires on merge (its `paths:` filter is `apps/web-platform/infra/**`):
  a no-diff apply for terraform state that re-fires the web-1 SSH provisioners
  exactly as every infra merge does (by design; ADR-114).
- Guard: `apps/web-platform/infra/web-host-provisioner-parity.test.sh` (1621
  lines; G2 heredoc ~1032-1618). Battery:
  `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` (1947
  lines; ~101s measured per `suite-durations.tsv:147`). Both registered via
  `run-registered-suites.sh` glob derivation; executed by
  `.github/workflows/infra-validation.yml`.
- Baseline: 25 SSH connection blocks swept (`FLOOR_BLOCKS=25`: 21 server.tf +
  1 ci-ssh-key.tf + 3 workspaces-luks.tf), ≥70 `.tf`/`.tf.json` files walked;
  `FLOOR=95` mutations, `PROBE_FLOOR=7`, `PROBE_RED_FLOOR=6`.

## References

- Issues: #10147, #10148 (this fix — `Closes #10147` and `Closes #10148` in the
  PR body); parent #9998 (closed via PR #10130); grandparents #7226 (Guard 2
  origin), #9151 (web-2 sibling), #9970 (normalization battery)
- Plan: `knowledge-base/project/plans/2026-10-12-fix-provisioner-parity-ssh-residence-plan.md`
  (the sibling mechanism this plan hardens)
- Spec: `knowledge-base/project/specs/feat-one-shot-9998-ssh-residence/spec.md`
  + `decision-challenges.md` (the CTO rulings on textual-dial scope and
  reason-mandatory enforcement this plan extends)
- ADRs: ADR-237 (host_key pinning), ADR-114 (connection hosts must not be
  repointed), ADR-193 (battery accounting conservation)
- Learnings:
  `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`,
  `knowledge-base/project/learnings/2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md`,
  `knowledge-base/project/learnings/2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md`,
  `knowledge-base/project/learnings/2026-10-12-the-guards-own-normalizer-is-attack-surface-treat-text-preprocessing-as-fail-open.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails deepen-plan — filled above with the sensitive-path scope-out bullet
  (the diff touches `apps/*/infra/`).
- `discoverability_test.command` runs inside preflight Check 10's sandbox under
  a 15s cap — the main guard (~2.4s) is the probe, never the ~101s mutation
  suite.
- `expect_red` anchors must be substrings of the arm's own `[FAIL]` text —
  `unclassifiable`, `pin`, and `stale EXT_RESIDENCE` literals are specified so
  each new row attributes to its own arm.
- `FLOOR`, `PROBE_FLOOR`, `PROBE_RED_FLOOR`, `cases` comments are re-derived
  after adding rows — a stale floor comment is the "claim that outlives the
  set" defect in miniature.
- The probe must be additive-only (never merged into the exemption consults)
  and carry its own negative control — the P4 precedent; X6 is that row here.
- `is_file()` is chosen over a second `read_text(`/`ls-files` site deliberately
  — the battery's reader-shape pin makes a second reader a loud, deliberate
  edit; this plan does not need pin-file content, only existence.
- A converted control beats a deleted one: G2-C3's green premise dies with the
  arm, so it becomes a red row pinning the same coverage (the mutation it was
  meant to kill is preserved, re-scored).
- Table-internal invariants cannot be `.tf`-mutated — they get probe rows
  (X1-X7), matching the §5 mechanism rather than asserting-by-review alone.
- This planning session ran without an Agent/Task tool: the research fan-out,
  spec-flow analyzer, scoped advisor, plan-review panel, and CTO
  technical-ruling spawns were performed inline by the planning agent;
  technical forks are recorded `pending - assumed` in
  `specs/feat-one-shot-10147-10148-ext-residence-hardening/decision-challenges.md`.
