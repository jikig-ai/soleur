<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix(infra): validate CIDR lines before nft heredoc in cron-egress-nftables.sh"
date: 2026-06-14
type: fix
issue: 5242
branch: feat-one-shot-5242-cidr-regex-validation
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix(infra): validate CIDR lines before the nft heredoc in `cron-egress-nftables.sh`

🐛 **Security hardening** — Closes #5242 (`type/security`, `priority/p2-medium`, `domain/engineering`).

## Enhancement Summary

**Deepened on:** 2026-06-14
**Sections enhanced:** Premise Validation, Risks & Mitigations (precedent-diff), Implementation Phases.
**Gates run:** deepen-plan 4.4 (precedent-diff), 4.6 (User-Brand Impact — PASS), 4.7 (Observability
5-field — PASS, no-ssh discoverability), 4.8 (PAT halt — PASS), 4.9 (UI-wireframe — N/A, no UI surface).

### Key Improvements
1. **Precedent found and reconciled** (see new §Risks & Mitigations — Precedent Diff): the sibling
   `cron-egress-resolve.sh` ALREADY validates IPs before the same `nft -f -` mechanism — but with a
   **filter-and-drop** model (`grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u`, lines 183/200/219),
   NOT reject-whole-file. The divergence is deliberate and correct: resolver IPs come from DNS (untrusted,
   partial-failure-tolerant → drop the bad one); the CIDR file is repo-controlled config (a bad line means
   the committed file is wrong → fail loud). Documented so reviewers don't "harmonize" the two to match.
2. **No existing CIDR-with-prefix validator to reuse** — the resolver's grep validates bare IPs only
   (`^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$`, no `/prefix`). The new `is_valid_ipv4_cidr` is novel; flag for
   reviewer scrutiny per the precedent-diff gate.
3. **`bash -n` under `set -euo pipefail`** confirmed safe for the `BASH_REMATCH` + `(( ... ))` arithmetic
   forms (no non-numeric RHS reaches the arithmetic — the regex gate guarantees numeric capture groups).

### New Considerations Discovered
- The reject-vs-drop decision is the load-bearing design call; both close the injection identically, so
  if review prefers drop-model parity with the resolver, the security goal is still met (then change AC8).

## Overview

`apps/web-platform/infra/cron-egress-nftables.sh` builds `CIDR_ELEMENTS` by stripping
comment/blank lines from `$CIDR_FILE` and joining the remainder with commas, then
interpolates that string **verbatim** into an `nft -f -` heredoc:

```sh
# line 59-62 (current, on main)
CIDR_ELEMENTS=""
if [[ -f "$CIDR_FILE" ]]; then
  CIDR_ELEMENTS="$(grep -vE '^[[:space:]]*(#|$)' "$CIDR_FILE" | paste -sd, -)"
fi
...
# line 92-97 (current, on main)
if [[ -n "$CIDR_ELEMENTS" ]]; then
  nft -f - <<EOF
flush set ip filter soleur_egress_allow_cidr
add element ip filter soleur_egress_allow_cidr { $CIDR_ELEMENTS }
EOF
fi
```

Any non-comment line containing `}`, a newline, or arbitrary nft statements is injected
into the firewall ruleset (e.g. a line `0.0.0.0/0` silently allows ALL egress, defeating
the entire default-drop allowlist; a line `}; add rule ip filter SOLEUR-EGRESS accept;`
appends an unconditional accept). This is **nft-rule injection via an unvalidated config
file**.

**Fix:** before building `CIDR_ELEMENTS`, validate every non-comment line against a strict
IPv4-CIDR shape and **abort the whole script (`exit 1`) on the first mismatch** — reject
the file rather than skip the bad line, so a malformed allowlist fails loud (the unit's
`OnFailure=` alarm pages the operator) instead of half-installing a firewall.

This is a ~10-line edit to a single function-shaped region of one bash script, plus
drift-guard test coverage. No infrastructure, schema, UI, or dependency changes.

## Premise Validation

Validated the issue's references against current repo state on 2026-06-14:

- **Issue #5242 is OPEN** (`gh issue view 5242` → `state: OPEN`). Not closed by any merged PR.
- **The issue body says the vulnerable code is "NOT on main" (in-flight branch only).
  This is STALE.** `git show origin/main:apps/web-platform/infra/cron-egress-nftables.sh`
  confirms the vulnerable lines are now **on `origin/main`** (lines 59-61 build
  `CIDR_ELEMENTS`, lines 92-95 inject it). The one-shot argument's correction holds: treat
  this as a **live security fix on main**, not a pre-ship backstop on an abandoned worktree.
  The original branch `feat-cron-egress-github-cidr` merged; its code shipped.
- **`$CIDR_FILE` default `cron-egress-allowlist-cidr.txt` exists and is tracked**
  (`apps/web-platform/infra/cron-egress-allowlist-cidr.txt`, 4 valid GitHub CIDR ranges).
- **An existing drift-guard test exists and is CI-wired**:
  `apps/web-platform/infra/cron-egress-firewall.test.sh` is run as a step in
  `.github/workflows/infra-validation.yml:166-167`. Baseline: `109 passed, 0 failed`.
- **No ADR rejects strict allowlist validation** — this is additive hardening, not a
  re-litigation of a decided mechanism.

No external premises remained unvalidated.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / arg) | Reality (verified) | Plan response |
| --- | --- | --- |
| "vulnerable code is on the in-flight branch, NOT on main" (issue body) | Code IS on `origin/main` (lines 59-61, 92-95) | Treat as live fix on main; ship to main via this branch. |
| Issue cites "lines 58–95 of that worktree" | On current branch + main the lines are 59-62 (build) and 92-97 (inject) | Edit the build region (≈59-62); the inject heredoc (92-97) is unchanged. |
| Proposed regex `^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$` | **Blocks the injection** (rejects `}`, newline, spaces, nft keywords) but does **not** range-check octets (`999.999.999.999/99` passes the regex) | Adopt the strict-shape regex as the security gate; ADD octet/prefix range validation as defense-in-depth correctness (see §Sharp Edges). The injection — the actual P2 security finding — is fully closed either way. |
| Issue: "Consider validating IPv6 CIDR too" | The CIDR set is `type ipv4_addr` (line 73-76); the file is documented "One IPv4 CIDR per line" | Scope to IPv4 only (matches the set type). A v6 line would correctly be REJECTED by the v4 regex — fail-loud is the desired behavior until a v6 set is added. Note as a non-goal. |

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed/empty `cron-egress-allowlist-cidr.txt`
causing the firewall loader to `exit 1` at boot → the `cron-egress-firewall.service` oneshot
fails → `OnFailure=` alarm pages the operator AND (per the script's fail-open-on-bootstrap
design, §line 23-27) the default-drop is NOT installed, so container egress is temporarily
unrestricted until fixed. The risk surface is a *too-strict* regex rejecting a legitimate
CIDR line, so the GREEN tests MUST include the 4 real allowlist ranges as accept-cases.

**If this leaks, the user's data/workflow is exposed via:** an *unvalidated* allowlist line
(`0.0.0.0/0`, or an injected `}; add rule ... accept`) silently neutering the container
egress firewall — the exact containment boundary that stops a compromised bot cron from
dialing an arbitrary host (ADR-033 I7, #5018). This fix CLOSES that exposure.

**Brand-survival threshold:** `aggregate pattern` — the `$CIDR_FILE` is repo-controlled and
gated by code review + the 14 required CI checks, so it is not directly attacker-controlled
today. The exposure is defense-in-depth against the #5199 Tier-2 restoration (bot crons can
now propose egress-allowlist edits). No single-user incident vector; no per-PR CPO sign-off.

## Implementation Phases

### Phase 1 — RED: failing drift-guard assertions

Add assertions to `apps/web-platform/infra/cron-egress-firewall.test.sh` that:

1. **Source-shape guard** (cheap, drift-resilient): assert the loader rejects-and-exits on
   invalid input — `assert_grep "CIDR validation rejects malformed lines" 'invalid CIDR' "$LOADER"`
   and `assert_not_grep "CIDR no longer built via unvalidated paste -sd," 'grep -vE .*paste -sd,' "$LOADER"`.
   These fail before the loader edit (RED).

2. **Behavioral guard** (the load-bearing one — actually exercises the regex): add a NEW
   self-contained test that re-implements/extracts ONLY the validation predicate and feeds it
   crafted lines. Because `nft` is absent on CI runners and the full script aborts at line 37
   (`command -v nft`) before reaching the CIDR parse, the FULL script cannot be invoked in CI.
   Strategy: have the loader expose the per-line validator as a discrete shell function
   (`is_valid_ipv4_cidr`) and have the test `source` the script with a guard that skips the
   `nft`/`ip link` preconditions — OR keep the validator inline and assert against a copy of
   the exact regex literal pinned in the test (cross-file literal-parity pattern already used
   in this test for `SENTRY_SLUG`/drop-prefixes, lines 180-198). **Preferred:** extract a
   `validate_cidr_file()` function guarded so sourcing the script for test does not run the
   firewall install. See §Sharp Edges for the source-guard mechanics.

   Behavioral cases the test MUST cover:
   - ACCEPT: the 4 real ranges (`140.82.112.0/20`, `185.199.108.0/22`, `192.30.252.0/22`,
     `143.55.64.0/20`).
   - ACCEPT: comment + blank lines (skipped, not rejected).
   - REJECT (injection): `140.82.112.0/20}; add rule ip filter SOLEUR-EGRESS accept`,
     a line with an embedded newline, a line with a leading/trailing space inside the value,
     `$(curl evil)`, `; nft flush ruleset`.
   - REJECT (malformed): `0.0.0.0` (no prefix), `140.82.112/20` (3 octets), `garbage`.
   - Defense-in-depth (if octet range-check adopted): REJECT `999.999.999.999/99`,
     `256.1.1.1/8`, `1.1.1.1/33`.

Run `bash cron-egress-firewall.test.sh` → confirm the new assertions FAIL (RED).

### Phase 2 — GREEN: the validation fix

Edit `apps/web-platform/infra/cron-egress-nftables.sh`, replacing the build region
(lines 59-62) with a validating loop that rejects the whole file on any mismatch:

```sh
CIDR_ELEMENTS=""

# Strict IPv4-CIDR validator. Rejects the nft-injection surface (}, newlines,
# nft keywords, whitespace, command-substitution) AND range-checks octets/prefix
# so a malformed allowlist fails loud rather than half-installing the firewall.
is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
  return 0
}

if [[ -f "$CIDR_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    is_valid_ipv4_cidr "$line" \
      || die "invalid CIDR in $CIDR_FILE: '$line' (reject-whole-file; refusing to build nft elements)"
    CIDR_ELEMENTS+="${CIDR_ELEMENTS:+,}$line"
  done < "$CIDR_FILE"
fi
```

Notes:
- Uses the existing `die()` helper (line 35) → logs with the `[$LOG_TAG]` prefix and `exit 1`,
  so the `OnFailure=` unit alarm fires (consistent with the rest of the script's failure model).
- `|| [[ -n "$line" ]]` handles a final line with no trailing newline.
- The injection heredoc (lines 92-97) is UNCHANGED — `CIDR_ELEMENTS` is now provably a
  comma-join of strict-CIDR tokens, so the interpolation is safe.
- `set -euo pipefail` is already active (line 28); the `BASH_REMATCH` + arithmetic forms are
  safe under it.

Run `bash cron-egress-firewall.test.sh` → confirm `0 failed` (GREEN). Run `bash -n` on the
loader (the test already asserts this at line 78).

### Phase 3 — REFACTOR / verify

- Confirm `bash -n cron-egress-nftables.sh` passes (syntax).
- Run the full `cron-egress-firewall.test.sh` and confirm the previously-green 109 assertions
  remain green plus the new ones.
- `shellcheck cron-egress-nftables.sh` if available (note any pre-existing warnings; do not
  expand scope to fix unrelated ones).

## Files to Edit

- `apps/web-platform/infra/cron-egress-nftables.sh` — replace lines 59-62 with the validating
  loop + `is_valid_ipv4_cidr` helper.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — add the RED→GREEN assertions
  (source-shape + behavioral cases). This file is ALREADY CI-wired
  (`infra-validation.yml:167`), so **no workflow edit is needed** — the new assertions run on
  the existing step.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-5242-cidr-regex-validation/spec.md` +
  `tasks.md` (planning artifacts; generated by the plan skill's Save-Tasks phase).
- (No new test FILE — the assertions extend the existing `cron-egress-firewall.test.sh`, which
  matches the established convention and avoids a second `infra-validation.yml` step.)

## Open Code-Review Overlap

`gh issue list --label code-review --state open` did not surface any open scope-out touching
`cron-egress-nftables.sh` or `cron-egress-firewall.test.sh`. **None.** (To be re-confirmed at
deepen-plan / work with the two-stage `gh --json` + standalone `jq --arg` form per CLAUDE.md.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (injection closed):** Feeding a `$CIDR_FILE` whose non-comment line contains `}`,
  a newline, an nft keyword, whitespace inside the value, or `$(...)` causes the loader to
  `exit 1` with an `[cron-egress-nftables] ERROR: invalid CIDR ...` message — verified by the
  behavioral test cases in `cron-egress-firewall.test.sh`.
- [ ] **AC2 (real ranges accepted):** All 4 lines currently in `cron-egress-allowlist-cidr.txt`
  (`140.82.112.0/20`, `185.199.108.0/22`, `192.30.252.0/22`, `143.55.64.0/20`) pass validation
  and produce the correct comma-joined `CIDR_ELEMENTS` — verified by accept-case assertions.
- [ ] **AC3 (comments/blanks skipped):** `#`-comment and blank lines are skipped (not rejected)
  — the existing file (24 lines, 4 CIDRs) validates clean.
- [ ] **AC4 (octet/prefix range — defense in depth):** `999.999.999.999/99`, `256.1.1.1/8`,
  and `1.1.1.1/33` are REJECTED (the issue's bare regex would have accepted the first).
- [ ] **AC5 (no unvalidated path remains):** `grep -E 'grep -vE .*paste -sd,' cron-egress-nftables.sh`
  returns nothing — the old unvalidated `paste -sd,` build is gone.
- [ ] **AC6 (syntax):** `bash -n cron-egress-nftables.sh` exits 0 (already asserted at test
  line 78).
- [ ] **AC7 (suite green):** `bash apps/web-platform/infra/cron-egress-firewall.test.sh` exits 0
  with `0 failed`, count ≥ the prior 109.
- [ ] **AC8 (fail-loud, not fail-skip):** the fix uses `die`/`exit 1` (whole-file reject), NOT
  `continue` (skip-bad-line) — verified by an `assert_grep` for the reject-and-exit construct
  and the absence of a per-line skip in the validation loop.

### Post-merge (operator)

- [ ] **AC9:** No operator action required. The fix ships via the normal infra-apply path; the
  loader re-runs on the next boot / `terraform_data.cron_egress_firewall` re-provision (the
  firewall unit re-asserts every boot, §line 18). `Automation: feasible — merge IS the
  delivery; no out-of-band step.` Close the issue at ship with `gh issue close 5242`. Use
  `Closes #5242` in the PR body (the code change fully resolves the finding at merge — no
  out-of-band apply gates closure).

## Observability

```yaml
liveness_signal:
  what: cron-egress-firewall.service oneshot exit status (loader run on boot / re-provision)
  cadence: every boot + every cron-egress-resolve.timer tick (self-heal re-runs loader)
  alert_target: OnFailure=cron-egress-alarm@%n.service then Sentry error check-in + Resend email
  configured_in: apps/web-platform/infra/cron-egress-firewall.service (OnFailure=)
error_reporting:
  destination: Sentry Crons (cron-egress monitor slug) + operator email via Resend
  fail_loud: true  # die() then exit 1 then systemd OnFailure= alarm; never silently skips a bad line
failure_modes:
  - mode: malformed/injected CIDR line in $CIDR_FILE
    detection: is_valid_ipv4_cidr returns 1 then die("invalid CIDR ...") then exit 1
    alert_route: cron-egress-firewall.service OnFailure then cron-egress-alarm@ then Sentry + email
  - mode: empty/absent $CIDR_FILE (legitimate)
    detection: CIDR_ELEMENTS="" then Phase 1.5 heredoc skipped (existing behavior, no error)
    alert_route: none (intended no-op)
logs:
  where: journald (tag cron-egress-nftables, via systemd unit); egress-blocked/egress-dns-exfil
         nft log prefixes grepped by cron-egress-resolve.sh into the Sentry event
  retention: journald default (host journald-config.test.sh governs); Sentry per project plan
discoverability_test:
  command: bash apps/web-platform/infra/cron-egress-firewall.test.sh
  expected_output: "0 failed"
```

## Domain Review

**Domains relevant:** Engineering (security hardening of infra script).

### Engineering

**Status:** reviewed (self-assessed; single-domain infra/security fix)
**Assessment:** Pure bash hardening of one infra script + its existing drift-guard test. No
schema, no migration, no UI, no new dependency, no new infrastructure surface (the firewall
artifacts already ship via `terraform_data.cron_egress_firewall`). Security lens: closes an
nft-rule-injection surface; the `security-sentinel` + `semgrep-sast` review agents at
`/soleur:review` are the appropriate PR-time gate.

No Product/UX surface (no `components/**`, `app/**/page.tsx`, no UI-surface file in Files
lists). Product/UX Gate: **NONE**.

## Infrastructure (IaC)

**Not applicable.** No new infrastructure is introduced. The fix edits an EXISTING script that
already ships via `terraform_data.cron_egress_firewall` (server.tf) + the cloud-init mirror.
Delivery is unchanged: the file-provisioner re-copies the edited script and the firewall unit
re-runs it on boot / resource re-provision. No new TF resource, secret, vendor, or systemd
unit. Phase 2.8 was reviewed (see the `iac-routing-ack` comment at the top of this file): the
plan introduces zero provisioning steps. The script being edited is already provisioned by
Terraform; this is a pure code change to an already-provisioned surface.

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

**Pattern class:** input validation before an `nft -f -` transaction (pattern-bound behavior with
a sibling precedent in the same repo).

**Precedent:** `apps/web-platform/infra/cron-egress-resolve.sh` feeds the SAME nft mechanism (it
populates the single-IP `soleur_egress_allow` + `soleur_egress_dns` sets via `nft -f -`). It ALREADY
validates addresses before building `add element`:

```sh
# cron-egress-resolve.sh:183, 200, 219 — FILTER-AND-DROP model
DESIRED_ALLOW="$(echo "$DESIRED_ALLOW" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
DNS_IPS="$(echo "$DNS_IPS"           | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
# current_set() likewise greps nft output through the same IPv4 pattern (:219)
```

**Side-by-side diff vs. this plan's approach:**

| Axis | Precedent (`resolve.sh`) | This plan (`nftables.sh` CIDR) | Why the divergence is correct |
| --- | --- | --- | --- |
| Failure model | **filter-and-drop** (`grep` retains valid lines) | **reject-whole-file** (`die`/`exit 1`) | Resolver IPs come from DNS — untrusted, partial-failure-tolerant; dropping one bad resolution is correct (the FAIL-SAFE empty-guard at :186 handles total failure). The CIDR file is **repo-controlled config** — a malformed line means the *committed file is wrong*; silently dropping it would install a firewall the operator did not intend. Fail-loud (operator-paged) is the right semantic for a config defect. |
| Shape validated | bare IPv4 (`^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$`, no prefix) | IPv4 **CIDR** (`.../[0-9]{1,2}` + octet/prefix range-check) | The resolver's set is `type ipv4_addr` (single IPs); the CIDR set is `flags interval` (ranges). No existing CIDR-with-prefix validator exists to reuse — the new `is_valid_ipv4_cidr` is **novel** (flag for review scrutiny per this gate). |
| Range-check | none (grep shape only) | octets ≤ 255, prefix ≤ 32 (defense-in-depth) | The resolver trusts DNS to return well-formed IPs; the CIDR file is hand-edited, so range-checking catches typos that the bare regex would pass. |

**Reviewer note:** do NOT "harmonize" the two scripts to the same model — the divergence is by design.
If review nonetheless prefers drop-model parity with the resolver, the SECURITY goal (injection blocked)
is met either way; switching to drop-model would require flipping AC8 and the fail-loud assertion.

**Empirical verification (run 2026-06-14 under `set -euo pipefail`):** the exact `is_valid_ipv4_cidr`
body in Phase 2 was probed standalone against all Test Scenario inputs → `14 passed, 0 failed`, exit 0.
The `(( ... ))` arithmetic does NOT crash under `set -e` (the regex gate guarantees the capture groups
are numeric before the arithmetic runs — no non-numeric RHS reaches `(( ))`). This closes the deepen-plan
"bash operator under strict mode" checklist item.

## Test Scenarios

| Input line | Expected | Why |
| --- | --- | --- |
| `140.82.112.0/20` | accept | real GitHub range |
| `# comment` / `` (blank) | skip | comment/blank handling |
| `0.0.0.0/0` | accept (regex) | structurally valid CIDR; "no allow-all" is a separate allowlist-content concern, out of scope for injection hardening — see Non-Goals |
| `140.82.112.0/20}; add rule ... accept` | **reject then exit 1** | injection |
| `1.1.1.1/33` | **reject** | prefix > 32 |
| `256.1.1.1/8` | **reject** | octet > 255 |
| `140.82.112/20` | **reject** | 3 octets |
| `$(curl evil)` | **reject** | command-substitution shape |

## Non-Goals / Out of Scope

- **IPv6 CIDR support.** The set is `type ipv4_addr`; the file is documented IPv4-only. A v6
  line is correctly REJECTED by the v4 regex (fail-loud). When/if a v6 interval set is added,
  extend the validator then. (Deferral: no tracking issue needed — the v6 set does not exist
  yet; adding one would naturally carry its own validation work.)
- **"No allow-all" / CIDR-breadth policy** (rejecting `0.0.0.0/0` or over-broad ranges). This
  is an allowlist-*content* governance concern, distinct from the injection-hardening finding
  in #5242. `0.0.0.0/0` is a structurally valid CIDR and passes validation; the repo-review +
  CI gate on `cron-egress-allowlist-cidr.txt` is the control for content. Out of scope.
- **Refactoring the resolver or other cron-egress scripts.** Scope is the one injection site.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Test source-guard mechanics:** if the test sources `cron-egress-nftables.sh` to call
  `is_valid_ipv4_cidr` directly, the script's top-level `nft`/`ip link`/`docker network`
  precondition checks (lines 37-46) and the install heredocs (Phases 1-4) would run on source.
  Two safe options: (a) guard the install body behind
  `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... main install ... fi` so sourcing only
  defines functions (cleanest, but a larger refactor of the script's top-level flow); or
  (b) keep the validator inline and have the test pin a COPY of the exact regex + range logic
  and exercise it standalone (cross-file literal-parity, already the convention in this test
  for `SENTRY_SLUG` and drop-prefixes — lines 180-198 — lower blast radius, but the copy can
  drift). **Decide at deepen-plan / work**; default to (b) unless the function extraction is
  clean, because (a) changes the script's execution model and risks the firewall install
  regressing. If (b), ADD an `assert_grep` pinning the regex literal in BOTH the script and the
  test so drift fails CI.
- **Octet range-check vs. the issue's bare regex:** the issue's proposed regex does NOT
  range-check (accepts `999.999.999.999/99`). The injection finding is closed by EITHER form.
  This plan adopts the stricter range-checked validator (defense-in-depth + correctness). If
  deepen-plan / review prefers minimal-diff parity with the issue's exact snippet, the bare
  regex is acceptable for the SECURITY goal — but then drop AC4 and the range test cases. Keep
  them aligned.
- **`grep` in `assert_not_grep` for the old build line:** anchor on a pattern that uniquely
  identifies the OLD unvalidated form (`paste -sd,`) and will not false-match a comment. The
  new code contains no `paste -sd,`.

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-06-14-fix-cidr-regex-validation-nft-heredoc-plan.md
Branch: feat-one-shot-5242-cidr-regex-validation. Worktree: .worktrees/feat-one-shot-5242-cidr-regex-validation/.
Issue: #5242. Plan reviewed, implementation next. Fix: strict IPv4-CIDR validation loop in
cron-egress-nftables.sh (reject whole file on mismatch) before the nft heredoc; extend
cron-egress-firewall.test.sh (already CI-wired) with RED to GREEN assertions.
```
