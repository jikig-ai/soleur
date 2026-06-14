---
title: "nft-rule injection via unvalidated config file — validate then reject-whole-file"
date: 2026-06-14
category: security-issues
module: apps/web-platform/infra
issue: 5242
pr: 5268
tags: [nftables, injection, bash, input-validation, infra, egress-firewall]
---

# Learning: nft-rule injection via an unvalidated config file

## Problem

`cron-egress-nftables.sh` built `CIDR_ELEMENTS` by stripping comment/blank lines from a
repo-controlled allowlist file and interpolating the result **verbatim** into an `nft -f -`
heredoc:

```sh
CIDR_ELEMENTS="$(grep -vE '^[[:space:]]*(#|$)' "$CIDR_FILE" | paste -sd, -)"
...
add element ip filter soleur_egress_allow_cidr { $CIDR_ELEMENTS }
```

Any non-comment line containing `}`, an nft keyword, whitespace, a newline, or
command-substitution was injected into the live firewall ruleset. A line `0.0.0.0/0`
silently installs allow-all (defeating the egress containment boundary); a line
`}; add rule ip filter SOLEUR-EGRESS accept` appends an unconditional accept. The file is
gated by code review + CI today, so it is defense-in-depth — but #5199 restored bot crons
that can propose egress-allowlist edits, widening the surface.

## Solution

Validate every non-comment line against a strict IPv4-CIDR predicate BEFORE building the
element string, and **reject the whole file** (`die` → `exit 1`) on the first mismatch:

```sh
is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
}
```

The fully-anchored regex (`^...$`, `[0-9]`/`.`/`/` alphabet only) excludes every injection
metacharacter. The `(( ))` range-check adds defense-in-depth correctness the issue's bare
regex lacked (`999.999.999.999/99` passes a bare regex).

## Key Insight

**Trust provenance dictates the fail-mode — and the two correct fail-modes diverge.** The
sibling `cron-egress-resolve.sh` feeds the SAME `nft -f -` mechanism but uses
**filter-and-drop** (`grep -E ... | sort -u`) because its input is untrusted DNS output
(partial-failure-tolerant → dropping one bad resolution is correct, with a fail-safe
empty-guard). A **repo-controlled config file** is the opposite: a malformed line means the
committed file is wrong, so silently dropping it would install a firewall the operator never
authored. Fail-loud (reject-whole-file → systemd `OnFailure=` page) is the right semantic.
Do NOT "harmonize" the two scripts — the divergence is by design; document it inline so a
future consistency-refactor doesn't collapse them.

Two reusable bash edges surfaced (now documented in-code):

- **`(( ))` + leading-zero capture = octal parse.** `(( 08 <= 255 ))` throws "value too
  great for base". On the LHS of `|| return 1` under `set -e`, the failure is swallowed by
  the `||` and the line safely REJECTS (does not crash) — a canonical allowlist shouldn't
  carry leading zeros anyway. Do NOT "fix" with a `10#` radix prefix: that would then ACCEPT
  `010.0.0.0/8`, which is worse for a canonical-form allowlist.
- **`read -r` retains a trailing `\r`.** A CRLF-saved file fails the `$`-anchored regex →
  whole-file reject. This is correct (the old paste-build silently injected the `\r`), but
  document it so a `die` on a "valid-looking" file isn't mystifying.

**Drift-guard for an inline validator with no unit harness:** `nft` is absent on CI, so the
full script can't run there. Pin a behavioral COPY of the predicate in the test AND assert
cross-file literal parity (`grep -qF` the regex AND the range-check arithmetic in both the
loader and the test) — same convention as this repo's SENTRY_SLUG/drop-prefix parity. The
behavioral copy proves correctness; the parity asserts catch drift. Anchor source-shape
asserts on the executable form (`o1 <= 255`), never the bare `<= 255` which also matches the
explanatory comment (comment-prose false-pass class).

## Session Errors

1. **Plan `Write` blocked by the `hr-all-infrastructure-provisioning-servers` PreToolUse
   hook** during the plan phase, because the plan QUOTED IaC detection-pattern strings
   (`ssh <user>@<host>`, `doppler secrets set`) while explaining what the fix does NOT do.
   **Recovery:** added the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`
   opt-out (Phase 2.8 genuinely reviewed — the fix is a pure code change to an
   already-Terraform-provisioned script, zero provisioning steps).
   **Prevention:** already-enforced. The `iac-routing-ack` opt-out is the sanctioned escape
   hatch for infra-fix plans that must quote provisioning verbs to scope them OUT. No new
   rule warranted — recurring class with an existing documented mitigation.

## Tags
category: security-issues
module: apps/web-platform/infra
