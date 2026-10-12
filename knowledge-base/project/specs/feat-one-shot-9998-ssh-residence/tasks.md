# Tasks — feat-one-shot-9998-ssh-residence (#9998)

Plan: `knowledge-base/project/plans/2026-10-12-fix-provisioner-parity-ssh-residence-plan.md`

## Phase 1 — Guard arm (`apps/web-platform/infra/web-host-provisioner-parity.test.sh`, G2 heredoc)

- [x] 1.1 Add `dials_fleet(b)` beside `dials_web_1`/`dials_web_2` (~:1200): same
  whitespace/`\\"` normalization + `json.dumps` for dict blocks; returns the set of
  `hcloud_server.web["web-N"]` names a block textually dials (regex
  `hcloud_server\.web\["(web-\d+)"\]` — any N, not just `FLEET_SSH_HOSTS`).
- [x] 1.2 Extend the `blocks`/`ssh_blocks` collection loop (~:1136-1180) to carry
  the enclosing resource address: nearest preceding `resource "<type>" "<name>"`
  header in the comment-stripped `.tf` (ANY type — a `connection {}` inside a
  `null_resource`/`hcloud_server` must still attribute or fail closed);
  `.resource.<type>.<name>` segment of the `json_blocks` path for
  `.tf.json`. Unresolvable → sentinel matching no allowance entry (fail-closed).
- [x] 1.3 Define `EXT_RESIDENCE` (`file → {resource_name: {hosts, reason}}`) seeded
  with `ci-ssh-key.tf:root_authorized_keys→{web-1}` and
  `workspaces-luks.tf:{luks_monitor_token_install,luks_monitor_install,workspaces_boot_unlock_install}→{web-1}`;
  empty/missing reason is itself a finding.
- [x] 1.4 Replace the `w2_elsewhere` arm (~:1249-1257) with `fleet_elsewhere`:
  flag every `ssh_blocks` member whose `dials_fleet` set is non-empty, whose file
  is not `apps/web-platform/infra/server.tf`, and whose `(file, resource)` pair is
  not covered by an `EXT_RESIDENCE` entry supersetting `dialed`. Keep the literal
  `outside server.tf` in the fail text (G2-18/G2-19..21 anchors).
- [x] 1.5 Add the stale-allowance check: every `EXT_RESIDENCE` entry resolves to a
  swept block dialing a host in the entry's `hosts` set, AND its `reason` is
  non-empty (guard-internal self-check — the battery mutates `.tf` inputs only,
  so this invariant fails loudly at guard runtime and is verified by code
  review). FAIL text carries the literal `stale EXT_RESIDENCE entry` (distinct
  from the residence arm's `residence allowance` phrasing so G2-22 anchors
  correctly).
- [x] 1.6 Update the header scope comment (residence is fleet-symmetric; the
  allowance is the single exemption surface).

## Phase 2 — Battery rows (`apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`)

- [x] 2.1 `expect_red "G2-19 (a web-1-dialing block WITH the correct local in a DIFFERENT .tf)" tunnel.tf "outside server.tf"` — phantom `terraform_data` carrying `host_key = local.web_1_ssh_host_key`.
- [x] 2.2 `expect_red "G2-20 (a second phantom web-1 dialer in an allowlisted file)" workspaces-luks.tf "outside server.tf"` — proves resource-granularity.
- [x] 2.3 `expect_red "G2-21 (a web-2 dialer in an allowlisted file)" workspaces-luks.tf "outside server.tf"` — proves host-scoping.
- [x] 2.4 `expect_red "G2-22 (residence allowance entry gone stale)" ci-ssh-key.tf "stale EXT_RESIDENCE"` — mutator removes the `connection {}` block.
- [x] 2.5 Bump `FLOOR` (`mutations_run` floor) 58 → 65 (+7 landed `expect_red`
  rows — G2-19..22 as planned plus G2-23/24/25 from the review design pass) and
  update the comment: `+7 #9998 residence rows (G2-19..25)`. `FLOOR_BLOCKS`
  raised 23 → 25 to equal the measured census (was lagging by 2 — slack lets
  blocks vanish unflagged). `PROBE_FLOOR`/`PROBE_RED_FLOOR`/`FLOOR_RESOURCES`
  unchanged.

## Phase 3 — Verification

- [x] 3.1 `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` exits
  0 on the real tree; the new arm prints its ok line covering the four declared
  dialers (AC2).
- [x] 3.2 `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  exits 0; G2-19..22 pass on their anchors and no existing row flips (G2-18's
  `outside server.tf` anchor still resolves).
- [x] 3.3 Confirm §1 untouched: `ssh_resources`/`uncovered`/`stale`/`_fleet_extra`
  remain `srv`-scoped (AC7); reason-mandatory `EXT_RESIDENCE` entries enforced
  (AC8).
