---
title: "EXT_RESIDENCE per-member content bound + unclassifiable-dial arm (deferred #9998 hardening)"
issue: [10147, 10148]
branch: feat-one-shot-10147-10148-ext-residence-hardening
lane: single-domain
type: fix
date: 2026-10-12
---

# Spec — #10147 + #10148 EXT_RESIDENCE hardening (deferred #9998 scope-outs)

## Ask

`gh issue view 10147`: a per-member content bound for `EXT_RESIDENCE` — an entry
waives the G2 residence arm for the resource's life, so a member's provisioner
bodies sit outside §1's census and §2's destination sweep with no table diff.
Acceptance: a bound for NEW entries (e.g., pinned provisioner shape or a
dedicated collateral pin requirement), documented in the standing-waiver
comment; the four seeds are already covered by sibling pins.

`gh issue view 10148`: an unclassifiable-dial arm — `dialed_hosts` matches only
the literal `hcloud_server.web["web-N"]` spelling, so `local.*`/`var.*`/
`each.value`/`self`/raw-IP dials outside server.tf skip residence from birth.
Acceptance: flag any `connection {}` outside server.tf whose host expression is
not literally classifiable; battery control G2-C6 (pins the gap green) flips RED.

## Scope

Single-domain (engineering infra tooling): two files under
`apps/web-platform/infra/` — the provisioner-parity guard and its mutation
battery. Plan:
`knowledge-base/project/plans/2026-10-12-fix-ext-residence-hardening-plan.md`.

## Key design choices (see plan §Proposed Solution)

- `EXT_RESIDENCE` entries gain mandatory `pin` (repo-relative `*.test.*` path,
  extant under `REPO`) — the collateral-pin requirement; seeds declare their
  real sibling suites.
- New `unclassifiable` arm flags every outside-server.tf block with empty
  `dialed_hosts`; `EXT_RESIDENCE` gains an `unclassifiable: true` marker as the
  reviewed acknowledgment (single exemption surface preserved).
- Hygiene arm adds a ≥1-swept-block requirement per entry (vacuous
  `hosts ⊆ dialed` at `∅ ⊆ ∅` for flagged entries).
- `SOLEUR_PARITY_EXT_RESIDENCE_PROBE` drives table-internal invariants red
  (additive-only, §5 probe precedent); `.tf`-reachable arms get G2-38 (converted
  G2-C6)/G2-39/G2-40, G2-C3 converts to a red `.tf.json` row.
