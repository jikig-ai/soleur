---
title: "fix(infra): narrow stale agent=true assertion in journald-config + sibling infra tests"
date: 2026-06-03
type: fix
issue: 4864
branch: feat-one-shot-journald-ssh-agent-4864
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 🐛 fix(infra): narrow stale `agent = true` assertion in `journald-config.test.sh` (+ sibling `infra-config-handler-bootstrap.test.sh`)

## Overview

`apps/web-platform/infra/journald-config.test.sh` AC4 asserts the SSH `connection`
block in `terraform_data.journald_persistent` uses **`agent = true`**:

```
FAIL: connection uses the operator SSH agent (agent = true)
=== Results: 32/33 passed ===
```

This assertion is **stale**, not a real bug. PR #4845 (`73bfe290`,
"generalize the CF Tunnel CI-apply bridge to the 7 on-host hardening
resources") deliberately converted every hardening `connection` block —
including `journald_persistent` — from operator-only (`agent = true`) to a
**dual-context** form so the resources auto-apply over the CI SSH bridge
instead of drifting:

```hcl
connection {
  type        = "ssh"
  host        = hcloud_server.web.ipv4_address
  user        = "root"
  private_key = var.ci_ssh_private_key         # null in operator-local context
  agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
}
```

In the CI-apply path `var.ci_ssh_private_key` carries Doppler
`DEPLOY_SSH_PRIVATE_KEY` (non-null), so `agent = false` and the embedded
Go SSH client authenticates with the explicit key — the runner has **no
ssh-agent**. In the operator-local path the var is null, so `agent = true`
uses the operator's ssh-agent. **`agent = true` literally hard-coded would
be the real bug** (CI cannot authenticate), but `server.tf` does **not** do
that — it uses the conditional. Therefore: **`server.tf` is correct; the
test assertion must be narrowed** to assert the dual-context conditional,
not the literal `agent = true`.

`deploy-script-tests` (`.github/workflows/infra-validation.yml:118`) runs
each `infra/*.test.sh` as its own `bash <file>` step; the test ends with
`exit 1` on any failure (`journald-config.test.sh:170-173`), so the step —
and the job — is RED on `main`. The job is **not a required check** (does
not block merges), but a RED `main` normalizes CI breakage and masks
future deploy-script regressions — the exact anti-pattern the
pre-existing-failure rule guards against.

### Sibling finding (load-bearing — do not ship journald alone)

A sibling-query audit (`for f in disk-monitor resource-monitor inngest
infra-config-handler-bootstrap orphan-reaper …; do grep -nE 'agent.*=.*true|operator SSH agent' "$f.test.sh"; done`)
found a **second** test with the identical stale assertion:
`apps/web-platform/infra/infra-config-handler-bootstrap.test.sh:86-87`.

That test currently **PASSES — by accident.** Its `BLOCK` is awk-extracted
from `resource "terraform_data" "infra_config_handler_bootstrap"`
(`server.tf:~370`) to the next column-0 `}`. That block uniquely carries
the `#4829 — DUAL-CONTEXT` explanatory **comment** whose prose contains the
literal string `agent = true` (`server.tf:381`: "… so agent = true uses the
operator's ssh-agent …"). The assertion's `grep -qE 'agent[[:space:]]*=[[:space:]]*true'`
matches that **comment prose**, not real config — a false positive. The
`journald_persistent` block has no such comment, so its identical assertion
fails honestly.

Both assertions are wrong (one fails, one false-passes). **Both must be
narrowed in the same PR** so the bootstrap test does not silently regress
when its comment is later edited, and so the next planner does not
re-discover the same stale-assertion class. This is the "scope a fix from
the named file only and miss the sibling query" backdoor that AGENTS.md
Sharp Edges warn against.

## Premise Validation

- **#4864 (target issue):** OPEN, `type/bug` + `priority/p2-medium`. Not
  closed by a merged PR. Premise holds — this is a *fix*, not a *build*.
- **#4845 (cited origin):** merged as `73bfe290` on 2026-06-03; `git show
  --stat 73bfe290` confirms it touched `server.tf` + the CI bridge action
  and intentionally added the dual-context connection blocks. The commit
  message states the 7 hardening resources were retrofitted "with the
  dual-context connection block, so they auto-apply on merge over the
  bridge instead of drifting." Premise (origin = #4845's connection-block
  change) holds.
- **Cited paths verified on disk:** `apps/web-platform/infra/journald-config.test.sh`
  (114-115), `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`
  (86-87), `apps/web-platform/infra/server.tf` (226-235 journald, 379-399
  bootstrap incl. comment at 381). All present.
- **Reproduced locally:** `bash apps/web-platform/infra/journald-config.test.sh`
  → `32/33`, FAIL on the agent assertion, `exit 1`. `bash …/infra-config-handler-bootstrap.test.sh`
  → `33/33` (false-pass confirmed).
- **Capability claim self-check:** verified the dual-context pattern is
  present in **8** real connection blocks (`grep -cE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key == null' server.tf` → 8) and that the **only** literal `agent[[:space:]]*=[[:space:]]*true` in `server.tf` is the comment at line 381 (`grep -nE 'agent[[:space:]]*=[[:space:]]*true' server.tf` → `381: #  … agent = true …`).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #4864) | Reality (codebase) | Plan response |
|---|---|---|
| "server.tf SSH connection uses `agent=true`" | No connection block hard-codes `agent = true`. All 8 use `agent = var.ci_ssh_private_key == null` (dual-context). The only literal `agent = true` is comment prose at `server.tf:381`. | Triage → **test assertion is stale**, not a server.tf bug. Fix the test, not server.tf. |
| "Triage: real bug (fix server.tf) OR stale assertion (narrow test)" | CI-apply path IS reached (the whole point of #4845) AND is correctly handled by the conditional (`agent=false` + explicit key in CI). | Stale-assertion branch confirmed. Narrow the test to assert the dual-context conditional. |
| Single failing test (`journald-config.test.sh`) | A **second** test (`infra-config-handler-bootstrap.test.sh:86-87`) has the same stale assertion; it false-passes via comment substring match. | Fix **both** tests in this PR (sibling-query audit). |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this
edits two CI test-assertion strings on offline infra drift-guards. The
worst failure mode is a test that still fails (re-RED `deploy-script-tests`)
or a test that goes permanently green-blind to a future real `agent = true`
regression.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no
data path, no secret, no runtime code. The tests are static grep/awk over
committed `.tf`/`.conf`/`.yml`; no credentials are read.

**Brand-survival threshold:** `none`. (Diff touches no sensitive path —
edits are confined to two `apps/web-platform/infra/*.test.sh` assertion
strings; reason recorded for preflight Check 6: test-only assertion
narrowing, no schema/auth/API/secret surface.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — journald assertion narrowed.** `journald-config.test.sh`
  AC4's agent assertion no longer requires literal `agent = true`. It
  asserts the dual-context conditional present in the real block. Verify:
  `grep -nE "agent\[\[:space:\]\]\*=\[\[:space:\]\]\*var\\\\.ci_ssh_private_key == null" apps/web-platform/infra/journald-config.test.sh`
  returns ≥1 match AND
  `grep -nE "agent\[\[:space:\]\]\*=\[\[:space:\]\]\*true" apps/web-platform/infra/journald-config.test.sh`
  returns **0** matches.
- [ ] **AC2 — journald test passes.** `bash apps/web-platform/infra/journald-config.test.sh`
  → `=== Results: 33/33 passed ===`, exit `0`.
- [ ] **AC3 — assertion description updated.** The `assert "…"` description
  string for the agent test no longer reads "connection uses the operator
  SSH agent (agent = true)" — it describes the dual-context shape (e.g.
  "connection uses the dual-context ssh-agent toggle (agent = … == null)").
  Verify: `grep -c "operator SSH agent (agent = true)" apps/web-platform/infra/journald-config.test.sh`
  → `0`.
- [ ] **AC4 — sibling assertion narrowed (bootstrap).** Same narrowing
  applied to `infra-config-handler-bootstrap.test.sh:86-87`. Verify both
  greps from AC1 against that file: conditional present, literal-`true`
  absent, and `grep -c "operator SSH agent (agent = true)" apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`
  → `0`.
- [ ] **AC5 — sibling test still passes (now for the right reason).**
  `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`
  → `33/33`, exit `0`. (It passed before via comment false-match; it must
  still pass after, now matching real config.)
- [ ] **AC6 — anti-false-pass guard.** The new assertion's awk-extracted
  `BLOCK` must match the conditional on a **real config line**, not the
  comment. The narrowed regex `agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key`
  cannot match the comment at `server.tf:381` (which reads `agent = true`,
  not `agent = var…`), so the bootstrap test passes only via the real
  block. Document this in a one-line code comment next to the assertion.
- [ ] **AC7 — no other infra test carries the stale assertion.** Full-class
  sweep:
  `grep -rln "operator SSH agent (agent = true)" apps/web-platform/infra/*.test.sh`
  returns **0 files** after the fix. (Pre-fix it returns exactly the 2
  files above — confirm the universe is 2, not more.)
- [ ] **AC8 — server.tf untouched.** `git diff --stat origin/main -- apps/web-platform/infra/server.tf`
  is empty. The fix is test-only; `server.tf` is correct as-is.
- [ ] **AC9 — full deploy-script-tests suite green locally.** Run every
  `run:` step from `.github/workflows/infra-validation.yml`'s
  `deploy-script-tests` job (`grep -oE 'bash apps/web-platform/infra/[a-z0-9-]+\.test\.sh' .github/workflows/infra-validation.yml | sort -u`)
  and confirm all exit `0` — guards against a stale assertion elsewhere in
  the same job.

### Post-merge (operator)

- [ ] **AC10 — CI confirms green.** After merge, `deploy-script-tests` on
  `main` is green. Verify via `gh run list --workflow=infra-validation.yml --branch main --limit 1`
  and `gh run view <id>` → `deploy-script-tests` conclusion `success`.
  Automation: `gh` CLI (no operator dashboard needed). Folded into
  `/soleur:ship` post-merge verification.

## Hypotheses

This is an SSH/`connection`-block change-class plan (gate fired:
`connection { type = "ssh" }` + provisioners in `server.tf`, keywords `SSH`,
`agent`, `connection`). Per `hr-ssh-diagnosis-verify-firewall`, the L3→L7
checklist is recorded — **but note this plan changes no live SSH path**;
the connection blocks are correct and untouched. The "outage" is a *test
assertion*, not a network failure. Layers are recorded for completeness and
to document why no network remediation is warranted:

1. **L3 — Firewall allow-list.** Not implicated. SSH:22 is allowlisted to
   `var.admin_ips` only (`firewall.tf`; CI-deploy rule removed in #749).
   No handshake is attempted by this PR; the failing artifact is a static
   grep over committed `.tf`. **Verification artifact:** the test runs
   offline (`infra-validation.yml:6` — "Offline jobs … require no secrets")
   — no host is contacted. Opt-out justification: the symptom is a
   `grep`/`awk` assertion mismatch in a file, reproduced locally with no
   network (`bash journald-config.test.sh` offline → 32/33). A firewall
   check cannot change a static-grep result.
2. **L3 — DNS / routing.** Not implicated — no hostname is resolved by the
   test or this PR. Opt-out: offline static test (same artifact as L1).
3. **L7 — TLS / proxy.** N/A — no HTTPS path.
4. **L7 — Application (sshd / Go SSH client).** Not implicated. The
   dual-context `connection` block is *correct* (CI uses explicit key,
   `agent=false`; operator uses ssh-agent, `agent=true`); the embedded Go
   SSH client reads `connection.host`/`private_key` directly and ignores
   `~/.ssh/config` (learning
   `knowledge-base/project/learnings/best-practices/2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md`).
   No sshd or client change is needed.

**Conclusion:** the failure is L8 (test-assertion), above all network
layers. No L3–L7 remediation applies; the fix is to narrow the assertion.

## Files to Edit

- `apps/web-platform/infra/journald-config.test.sh` — narrow the AC4 agent
  assertion (lines 114-115): change the condition regex from
  `agent[[:space:]]*=[[:space:]]*true` to
  `agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null`
  (the real dual-context line), and update the `assert "…"` description
  string to describe the dual-context toggle. Add a one-line comment that
  the literal-`true` form was stale post-#4845 and that the conditional
  regex cannot false-match the `#4829` dual-context comment.
- `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — apply
  the identical narrowing to lines 86-87. Same condition regex + same
  description update + same one-line comment.

## Files to Create

- None.

## Test Strategy

Existing `.test.sh` harness — no new framework. (`command -v bats` → not
required; the convention is the in-repo `assert()` bash harness, confirmed
by the 18 sibling `apps/web-platform/infra/*.test.sh` files.) The change
modifies two existing assertions; the harness already exercises them.

- **RED (current state, pre-fix):** `journald-config.test.sh` → 32/33 (the
  honest failure); `infra-config-handler-bootstrap.test.sh` → 33/33 (the
  false-pass). Capture both as the baseline.
- **GREEN (post-fix):** both → 33/33, both for the *right* reason (matching
  the real `agent = var.ci_ssh_private_key == null` config line, not the
  comment).
- **Anti-false-pass proof:** confirm the narrowed regex matches a real
  config line and NOT the comment, by checking the existing `BLOCK` var
  contains the conditional — the `journald_persistent` block has no
  dual-context comment, so its pass is unambiguous; the
  `infra_config_handler_bootstrap` block contains the comment `agent = true`
  AND the real `agent = var…` line — the narrowed regex matches only the
  latter.

## Sharp Edges

- The `infra_config_handler_bootstrap` block in `server.tf` (lines ~379-399)
  uniquely carries the `#4829 DUAL-CONTEXT` explanatory comment containing
  the literal prose `agent = true` (line 381). Any assertion regex that
  matches `agent[[:space:]]*=[[:space:]]*true` will **false-pass** against
  that comment. The narrowed regex MUST anchor on `agent … = var…` so it
  matches the real config line and never the comment. Verify the new regex
  does NOT match the comment: `awk '/^resource "terraform_data" "infra_config_handler_bootstrap"/{f=1} f{print} f&&/^}/{exit}' server.tf | grep -nE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key'` returns the real line, and the same awk piped to `grep -nE 'agent[[:space:]]*=[[:space:]]*true'` returns only the comment.
- Do **not** "fix" `server.tf` to hard-code `agent = false` or `agent = true`.
  Both break one of the two apply paths. The conditional `agent =
  var.ci_ssh_private_key == null` is load-bearing: it is the single
  mechanism letting the same block serve operator-local apply (ssh-agent)
  and CI-bridge apply (explicit Doppler key). See PR #4845.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This section is filled (threshold `none` with a
  recorded sensitive-path scope-out reason).
- When picking the new assertion description, avoid reusing a phrase that
  punctuation-splits the words you grep for — keep the description and the
  grep-target free of intervening parens so AC verification greps resolve.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change
(two CI test-assertion strings; no UI, no schema, no auth, no data path,
no new infrastructure, no regulated-data surface).

## Infrastructure (IaC)

Skipped — no new infrastructure. This plan edits no `.tf` and introduces no
server, service, cron, secret, vendor, or persistent runtime process. The
only `.tf` mention is read-only (the assertion targets `server.tf` content,
which is **not** modified — see AC8).

## Observability

Skipped — this plan's Files-to-Edit are two `apps/web-platform/infra/*.test.sh`
files (test assertions), not code-class files under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/` (the `.tf`/runtime infra), or
`plugins/*/scripts/`, and it introduces no infrastructure surface. The
feature *is* an observability/CI-health fix (it makes `deploy-script-tests`
green again), but it ships no new liveness/error/log surface of its own —
the existing `deploy-script-tests` job IS the discoverability test
(`gh run view`, no SSH). No 5-field schema required.

## GDPR / Compliance

Skipped — no regulated-data surface (no schema, migration, auth flow, API
route, `.sql`, LLM/external-API processing, cron reading learnings/specs,
or artifact-distribution surface). Two static test-assertion edits.

## Open Code-Review Overlap

None on the edited files. Queried `gh issue list --label code-review --state
open --limit 200` and grepped bodies for the two Files-to-Edit paths:
`journald-config.test.sh` → 0 matches, `infra-config-handler-bootstrap.test.sh`
→ 0 matches. A `server.tf` substring grep returned #3216 (a `fix-dpf-regex-canary-bundle`
review) and #2197 (a billing refactor) — both are **false positives**
(neither names either target test file and `server.tf` is **not** edited by
this plan, per AC8). No fold-in / acknowledge / defer action required.

## References

- Issue: #4864
- Origin PR: #4845 (`73bfe290`) — dual-context CI-apply bridge generalization
- `apps/web-platform/infra/server.tf:226-235` (journald block, dual-context)
- `apps/web-platform/infra/server.tf:379-399` (bootstrap block + comment at 381)
- `.github/workflows/infra-validation.yml:118-157` (`deploy-script-tests` job)
- Learning: `knowledge-base/project/learnings/best-practices/2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md`
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md`
- AGENTS.md: `hr-ssh-diagnosis-verify-firewall`
