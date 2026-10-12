# Decision Challenges — feat-one-shot-10147-10148-ext-residence-hardening (#10147, #10148)

Decisions recorded during `soleur:plan` (headless one-shot pipeline, no Agent/Task
tool available — technical rulings are `pending - assumed` per
`technical-ruling-delegation.md`; `soleur:ship` renders this table into the PR body
and files unresolved rows as `action-required` issues).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #10147 mechanism: declared `pin` field vs in-guard provisioner-shape pin vs provisioner-content hash | technical | pending - assumed: declared `pin` field (repo-relative `*.test.*` path, extant) — the issue's own "dedicated collateral pin requirement" sketch; in-guard shape pins duplicate the richer content pins sibling suites already own (second pin surface to keep in sync); a content hash imposes a table diff on every cosmetic member edit (table-diff fatigue) |
| `pin` verification depth: mechanical `is_file()` existence vs declarative-only vs member-name-binding read | technical | pending - assumed: `is_file()` under `REPO` + `*.test.*` shape — a typo'd pin slips a declarative check (the silent-drift class the guard exists to catch); member-name-binding would need a second `read_text(` call site and a reader-shape-pin amendment, deferred as a documented non-goal |
| #10148 waiver surface: `unclassifiable: true` marker on `EXT_RESIDENCE` vs flat flag with no waiver vs a second table | technical | pending - assumed: `unclassifiable: true` marker — a flat flag makes legitimate non-web/indirect dials (e.g., `hcloud_server.git_data.*`, a raw IP) unrepresentable anywhere outside server.tf; a second table breaks the declared single-exemption-surface invariant; the marker keeps every acknowledgment a table diff |
| Unclassifiable arm population: all `blocks` (conn + dyn + .tf.json + winrm-labeled) vs `ssh_blocks` only | technical | pending - assumed: all `blocks` — mirrors `fleet_elsewhere`'s fail-closed precedent (a winrm label or dynamic spelling must not buy invisibility) |
| G2-C3 disposition: convert to a red `.tf.json` unclassifiable row vs delete | technical | pending - assumed: convert — after the arm lands, no green .tf.json-outside-server.tf shape exists; conversion preserves .tf.json coverage of the new arm rather than silently dropping a case |
| Inside-server.tf indirection (non-`terraform_data`/unattributed blocks) | technical | pending - assumed: named residual, out of scope — the issue's acceptance is "outside server.tf"; §1 already pins `terraform_data` member hosts literal (battery row M3) |
| `root_authorized_keys` seed pin = `plugins/soleur/test/terraform-target-parity.test.ts` (wiring-level, not body-level) | technical | pending - assumed: accept and declare — the issue asserts seeds are covered by sibling suites; this is the suite that actually names the resource (exclusion allowlist :108, -target presence :1252); the asymmetry is recorded in the plan's Reconciliation rather than silently padded |
| Agent-spawn steps (research fan-out, spec-flow analyzer, scoped advisor, plan-review panel, domain leaders, CTO ruling on the forks above) | technical | pending - assumed: inline substitution stands — every fork resolves on in-file precedent (§5's `SOLEUR_PARITY_ALLOWLIST_PROBE`, `check_allowlist` reason-mandatory idiom, `fleet_elsewhere` iteration, `EXPECTED_INPUTS`/`DERIVED_INPUTS` reconciliation) plus verified facts |
