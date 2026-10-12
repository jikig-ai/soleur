# Tasks — feat-one-shot-10147-10148-ext-residence-hardening (#10147, #10148)

Plan: `knowledge-base/project/plans/2026-10-12-fix-ext-residence-hardening-plan.md`

## Phase 1 — Guard arms (`apps/web-platform/infra/web-host-provisioner-parity.test.sh`, G2 heredoc)

- [x] 1.1 Extend `EXT_RESIDENCE` entry schema: mandatory `pin` (repo-relative
  `*.test.sh`/`*.test.ts` path), optional `unclassifiable` bool; populate seed
  pins (`luks_monitor_install` + `luks_monitor_token_install` →
  `apps/web-platform/infra/luks-monitor-install.test.sh`;
  `workspaces_boot_unlock_install` →
  `apps/web-platform/infra/workspaces-boot-unlock.test.sh`;
  `root_authorized_keys` → `plugins/soleur/test/terraform-target-parity.test.ts`);
  document both fields in the entry doc comment (:1461-1478).
- [x] 1.2 Add the unclassifiable-dial arm after `fleet_elsewhere`: iterate ALL
  `blocks` (conn + dyn, .tf + .tf.json, winrm-labeled included), skip
  `fpath == "apps/web-platform/infra/server.tf"`; `dialed_hosts(b)` empty →
  exempt only via an `(fpath, addr)` entry carrying `unclassifiable: true`;
  else finding. FAIL literal contains `unclassifiable`.
- [x] 1.3 Extend the `stale_ext` hygiene loop (:1550-1586): `pin` present,
  non-empty string, no leading `/`/`..`, `*.test.*` suffix,
  `(REPO / pin).is_file()` → `EXT_RESIDENCE pin` finding; ≥1 swept block
  attributed to `(fpath, rname)` per entry; `hosts` non-empty unless
  `unclassifiable: true`; existing `hosts ⊆ dialed` + `reason` checks unchanged.
- [x] 1.4 Add `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` env handling: JSON
  `{file: {rname: {...}}}` parsed with §5-probe shape discipline (named FAIL on
  unparseable/non-object/wrong types — never a traceback), `hosts` lists → sets,
  same hygiene checks under an `EXT_RESIDENCE probe` prefix; NEVER merged into
  the `fleet_elsewhere`/unclassifiable exemption consults.
- [x] 1.5 Update the standing-waiver comment (:1470-1476) to document the
  per-member content bound, and the `dialed_hosts` residual comment
  (:1404-1413) now that the gap is closed (G2-C6's pin flips).

## Phase 2 — Battery (`apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`)

- [x] 2.1 Convert `expect_green` G2-C6 (:1705) → `expect_red "G2-38 (…)"` with
  anchor `unclassifiable` (same mutator); add G2-39 (raw-IP dialer with valid
  `host_key`, `unclassifiable`) and G2-40 (two unclassifiable dialers
  `var.*`/`each.value` in one file, `unclassifiable` + second-name needle).
- [x] 2.2 Convert `_g2_json_row` G2-C3 (:1866) → red row anchoring
  `unclassifiable`.
- [x] 2.3 Add `expect_green` G2-C7: a provisioner-body edit inside a
  workspaces-luks member stays GREEN.
- [x] 2.4 Add the `EXT_RESIDENCE` probe helper pair (env var
  `SOLEUR_PARITY_EXT_RESIDENCE_PROBE`) + rows X1-X7 (malformed JSON; missing
  `pin`; dangling `pin`; non-`*.test.*` `pin`; `unclassifiable`-flagged entry
  with no swept block → `stale EXT_RESIDENCE`; negative control — probe entry
  cannot exempt the G2-38 phantom → still `unclassifiable`; well-formed green
  probe naming a real member + real pin).
- [x] 2.5 Add pin-file sandbox copies: `G2_PIN_INPUTS` hardcoded list reconciled
  against `"pin"` values derived from the guard (FATAL on drift, the
  `EXPECTED_INPUTS`/`DERIVED_INPUTS` pattern); copy each into the sandbox under
  its repo-relative path so `(REPO / pin).is_file()` resolves.
- [x] 2.6 Re-derive `FLOOR` (95→98), `PROBE_FLOOR`/`PROBE_RED_FLOOR`
  stay per-family at 7/6 (§5); EXT family gets `EXT_PROBE_FLOOR=20`/
  `EXT_PROBE_RED_FLOOR=19` (review split the floors per family; X-rows
  grew X1-X7 → X1-X20). `cases` re-derived from the battery log; census
  comments updated.

## Phase 3 — Verification

- [x] 3.1 `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` →
  GREEN on the real tree; both new arms print ok-lines.
- [x] 3.2 `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  → all rows pass; `guard still PASSED` does not appear for G2-38; G2-18/19
  anchors still resolve; no pre-existing row flips.
- [x] 3.3 `shellcheck` both files (pre-existing SC1091 tolerance per #10130).
- [x] 3.4 Confirm AC1-AC10 against the battery log; PR body carries
  `Closes #10147` + `Closes #10148` and the merge-effect first line (no `.tf`
  change → no-diff apply).
