# Decision Challenges — feat-one-shot-9998-ssh-residence (#9998)

Decisions recorded during `soleur:plan` (headless one-shot pipeline, no Agent/Task
tool available — technical rulings are `pending - assumed` per
`technical-ruling-delegation.md`; `soleur:ship` renders this table into the PR body
and files unresolved rows as `action-required` issues).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Unified `fleet_elsewhere` arm replacing `w2_elsewhere` vs an additive `w1_elsewhere` arm alongside it | technical | Ruled by CTO agent, 2026-10-12: unified `fleet_elsewhere` - one property, one `[FAIL]` line retaining the `outside server.tf` literal keeps G2-18 and G2-19..21 anchoring on the same arm; superset `hosts` semantics handle multi-dial blocks and future web-N hosts without a new arm per host |
| Residence allowance granularity: file-scoped vs (file, resource)-scoped | technical | Ruled by CTO agent, 2026-10-12: (file, resource)-scoped - a file-keyed allowance would let a second phantom `terraform_data` hide inside `workspaces-luks.tf` behind the three legitimate members, the second-member class battery row G2-20 exists to red |
| Coverage scope: textual `hcloud_server.web["web-N"]` dial vs indirect host spellings (`var.web_hosts`, `local.*`, module outputs, literal IPs) | technical | Ruled by CTO agent, 2026-10-12: textual `hcloud_server.web["web-N"]` dials only - matches the existing `dials_web_1`/`dials_web_2` normalization and §1's literal `DIAL_W1`/`DIAL_W2` regexes; HCL indirection resolution is a different mechanism, correctly carried as a named residual gap |
| Stale-allowance arm included in the fix | technical | Ruled by CTO agent, 2026-10-12: stale-allowance arm included - §1's `_stale_class` and §5's `check_allowlist` already make "entry outlives the resource it names" a finding; G2-22's `stale EXT_RESIDENCE entry` literal gives the arm its own attribution anchor |
| `EXT_RESIDENCE` keyed on `terraform_data` only vs any resource type carrying a `connection` block | technical | Ruled by CTO agent, 2026-10-12: resolve whatever `resource "<type>" "<name>"` header encloses the block - a `connection {}` inside a `null_resource`/`hcloud_server` in an undeclared file must still be attributed or fail closed on the sentinel; residence is a property of the connection block, not the resource type (corrects the plan's Phase-1 `terraform_data` wording) |
| Residence coverage: `web-\d+` superset vs the issue's "all declared fleet hosts" (`FLEET_SSH_HOSTS`) | technical | Ruled by CTO agent, 2026-10-12: ANY `web-\d+` dialer (superset) - §1 already compiles `_DIAL_HOST_RE` for `web-\d+` and flags `_fleet_extra` dialers on undeclared hosts; keying G2 to `FLEET_SSH_HOSTS` would reopen the exact escape for a future web-3 dialer outside server.tf |
| `EXT_RESIDENCE` reason-mandatory enforcement: mechanical self-check vs review convention | technical | Ruled by CTO agent, 2026-10-12: guard-internal runtime self-check folded into the stale-allowance arm - §5's `check_allowlist` enforces `reason.strip()` non-empty in the same pass as staleness; guard-internal tables are structurally unreachable from a file-mutating battery |
| Agent-spawn steps (research fan-out, spec-flow analyzer, scoped advisor, plan-review panel, domain leaders, CTO ruling on the forks above) | technical | Ruled by CTO agent, 2026-10-12: inline substitution stands; no fork needs a real second-opinion spawn - every fork resolves on in-file precedent (ALLOWLIST, ONLY_JUSTIFIED, `_stale_class`, `_fleet_extra`, `expect_red` anchors) plus verified facts; implementer caveat: battery reader-shape pin means enclosing-resource resolution must reuse the already-read `src` text |
