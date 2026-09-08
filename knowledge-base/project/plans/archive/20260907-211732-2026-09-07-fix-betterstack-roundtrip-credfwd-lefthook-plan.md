---
title: "fix: read the Better Stack round-trip verdict, confine the ingest-credential destinations, and close the lefthook hop-budget off-by-one"
date: 2026-09-07
slug: fix-betterstack-roundtrip-credfwd-lefthook
branch: feat-one-shot-7867-7873-7886-betterstack-credfwd-lefthook
lane: cross-domain
type: fix
issue: 7873
closes: 7873
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Deepen Pass — 2026-09-07

Run after the eight-reviewer plan-review panel, so its job was the checks the panel does not do:
mechanical verification of the plan's own claims, and of the mechanism it had just chosen.

**One finding would have shipped a vacuous guard.** The plan's chosen mechanism — "add Rule D to
`scripts/lint-shell-trace-credential-refusal.py` and inherit its baseline" — is defeated by that
baseline's granularity: it is **per-file and rule-agnostic** (`if rel not in baseline` drops *all*
rules' findings for that file), it holds **130** entries, and **all seven** Better Stack sites are
already in it. Rule D would have been green over exactly the population it was written for, on the
repo-wide run that is the blocking arm. Corrected: Rule D gets its own baseline, plus mutation row 13
to keep it that way.

**A second finding reversed the `#7886` design, and a third found a live collision.** PR **#7879** is
OPEN and WIP on the same file, taking the mechanism this plan had **rejected** — and on inspection the
rejection was aimed at a strawman. The hook emits **12** decline reasons, five of which are genuine
defects and two of which (`disabled`, `concurrent_apply`) are correct outcomes; gating on the hook's
verdict *with the reasons classified* deletes the duplicate ancestry walk instead of aligning it, and
preserves P6. The plan now adopts that, demotes the `$BASHPID` walk-alignment to a fallback, and
settles PR 1's scope against #7879 at Phase 0 rather than mid-implementation.

**A second unscoped CI blocker**, alongside the xtrace drawdown: `.claude/hooks/` sits in
`guard-vacuity-floor.test.sh`'s `DEFERRED_DIRS`, its population is `git ls-files '*.test.sh'`, and
`MAX_DEFERRED=47` is a shrink-only ratchet — so a floor-bearing new guard there reddens CI unless it
is promoted in the same PR.

**Six smaller corrections**, each measured: the lint has **no ratchet** to inherit (only `--census`
and `--write-baseline`; the four `.highwater` files live elsewhere). **Rule D does NOT add one —
cut at review as subsumed.** Phase 0 cited
a classifier that does not exist yet, so it now *defines* the token set before censusing with it; the
`expect_field` count is **73**, not 74; the plan claimed "9 ADR ordinals" while citing 6; `ADR-197`
was mis-attributed as the shell-trace credential refusal (that is **ADR-202**); and two line citations
were off by one, now replaced with content anchors. AC B6's grep was also unscoped, so the plan —
which quotes the literal — would have matched itself.

**Verified clean.** A twelve-claim verify-the-negative sweep returned **12/12 CONFIRMS, zero
contradictions**, including the SUITE_GLOBS membership claims, the coherence-preflight invocation
sites, the `ignore_changes` coverage, the SessionStart-only hook registration, the refusal-site
ordering at both host scripts, the orphan-linter's 25-orphan synthesis cap, and exit 78's
no-verdict-line path. Cross-checks also confirmed: zero AGENTS rule-ID citations (so no
fabricated-citation risk), no dangling AC cross-references, mutation-row counts matching their ACs,
census figures consistent between plan and tasks, and neither infra workflow's `paths:` filter
matching any PR-0/1/2 path.

---

## Overview

Three separable pieces of work. `lane: cross-domain` is the fail-closed default — no `spec.md`
exists on this branch to carry one forward.

1. **#7867** is an enrolled follow-through tracker, not a code-change request. Run the instrument,
   read the verdict it actually returns, pull the supporting warehouse rows first-hand, branch on it.
2. **#7873** is a credential-confinement gap. The fix the issue suggests is **measurably
   insufficient**, and the population it describes is **measurably ~10× larger** than three sites.
3. **#7886** is a test-harness divergence with a byte-exact reproduction: two independent eight-hop
   ancestor walks whose origins differ by exactly one process.

**This plan was corrected twice by an eight-reviewer panel, and the corrections are the substance.**
Its first draft proposed three guard suites, 25 mutation scenarios and 33 acceptance criteria around
a ~40-line production diff. Worse, it contained four defects the panel *measured*: the prescribed
`#7886` fix was a **no-op**; the prescribed refusal semantics would have **disabled the dark-host
detector** they existed to protect; the prescribed test harness could not work at all because the pin
runs **before curl is invoked**; and the depth-perturbation the acceptance criteria rest on is **not
achievable by the obvious construction**. Each is corrected below with the measurement that settled
it. The reasoning that was cut is preserved in *Alternative Approaches Considered*.

---

## Research Reconciliation — Spec vs. Codebase

Every claim was re-verified in this worktree. Reviewer findings are marked; being told a thing is not
the same as checking it, and one reviewer claim below turned out to be wrong.

| Claim | Codebase reality | Plan response |
|---|---|---|
| #7873: "the constant now declared in `scripts/lib/betterstack-sources.sh`" | Declares `BS_CONTROL_INGEST_HOST` (a host) and `BS_GIT_DATA_INGEST_URL` (the git-data URL). A *new* derived constant turns out to be unnecessary. | Pin site 1 against the literal it already carries; assert parity across the declarations that already exist. **No new constant.** |
| #7873: implies the three sites target different destinations | All three target `2457081`. Byte-verified: expanding `https://${BS_CONTROL_INGEST_HOST}/` equals `local.betterstack_logs_ingest_url` and `zot-inventory.sh`'s default, character for character (md5 `bc1631aa…` on both sides). | One destination, three sites. |
| #7873: a positive equality check closes the gap | **Measured false.** `curl` consults `http_proxy`/`HTTPS_PROXY`/`ALL_PROXY` *before* contacting the pinned host and reads `~/.curlrc` even under `--config`. Reproduced against a local listener. | Pin **plus** transport confinement. |
| #7873: "this is the residual" — three sites | **False by an order of magnitude.** My census: **80** tracked non-test `*.sh` invoke `curl` carrying a credential across **325** `curl` lines; **1** carries `--noproxy`. Reviewers measured 69/72/82/84/86 on different token sets. | Scope restated; enforced by a **ratcheting rule in an existing lint**. |
| **[reviewer, verified]** The count spread is itself a finding | My pattern missed `-u`. `scripts/betterstack-query.sh:118` — this plan's headline vector — uses `-u`, not `--user`. | The classifier covers `-u`, `--user`, `--header @-`, `--netrc`/`--netrc-file`, `--oauth2-bearer`, `--proxy-user`, `-E`. Phase 0 regenerates the census **from the classifier**. |
| **[reviewer, verified] P2 is falsified inside site 1 itself** | `scripts/zot-inventory.sh:179` writes `machine $REGISTRY_HOST … password $ZOT_PULL_TOKEN` into a netrc consumed a couple of lines below via `--netrc-file "$NETRC"`; `REGISTRY_HOST` is derived from `REGISTRY_URL="${ZOT_INVENTORY_REGISTRY_URL:-http://127.0.0.1:5000}"`. Setting that variable writes the attacker's host into the netrc and curl sends the credential. The file's own `:244` comment says an unvalidated value "is an egress escape, not a formatting bug." | **A second credential path in the file #7873 names.** In scope for PR 2; the classifier must catch the netrc chokepoint. |
| **[reviewer, verified]** Draft's `#7886` fix — "walk from a spawned child" | **A no-op.** `$$` survives subshells. Measured: parent `$$=507774`; inside `( )` `$$=507774`, `BASHPID=507779`. A subshell keeping `_p=$$` leaves the cursor at the test's PID while satisfying any guard that checks merely that a fork happened. | The fix names **`$BASHPID`**; the guard asserts the **origin PID value**. |
| **[reviewer, verified]** The depth perturbation the ACs rest on | **Not achievable by the obvious construction.** Measured here: base depth to `claude` = 2; `bash -c` ×1 → 3; `bash -c` ×2 → **3** (the outer `exec`s into the inner, adding no hop); `{ …; } & wait` → 4. Nested `bash -c` adds nothing, so "five extra forks" written the natural way silently tests nothing and the AC passes green. And the base frame varies by runner, so `5` is not a constant. | The primitive is a **real fork** (`& wait`); the target depth is **derived at runtime** from the measured distance to `claude`; the harness **verifies its achieved depth** before invoking the suite. |
| **[reviewer, verified]** Draft assumed the test must reimplement the hook's budget | The test already does `source "$HOOK"` before the gate, and `main` is guarded behind `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`. `MAX_WALK_HOPS` is in scope at the gate. | The gate reads the sourced constant instead of the literal `1 2 3 4 5 6 7 8`. |
| **[reviewer, verified]** Draft's refusal semantics — "exits non-zero rather than posting" | **Would disable the detectors it protects.** At `soleur-host-bootstrap.sh` the ingest post is immediately followed by `soleur-boot-emit … fatal`, the Vector-independent dark-host detector; at `web-private-nic-guard.sh` by the `web_nic_guard` liveness heartbeat. | The refusal is **skip-and-report** with fall-through. |
| **[reviewer, verified]** Draft prescribed `[[ … ]]` at both host sites | The bootstrap's ingest post lives inside a quoted heredoc authoring `/usr/local/bin/soleur-fresh-boot-ready` (`#!/bin/sh`), and the bootstrap is invoked as `sh <file>`, bypassing its shebang. Both run under **dash**. | POSIX `[ … ]` there. |
| **[reviewer, verified]** Draft's harness conversion | **Could not have worked, and was sized against the wrong number.** The pin is a bash string comparison evaluated *before* curl is invoked, so stubbing the curl binary cannot stop `run_inv` — which injects a loopback `ZOT_INVENTORY_INGEST_URL` on **every** case — from being refused on every case. And the blast radius is not 4 assertions: `marker()` reads `INGEST_BODY`, and 73 `expect_field` calls flow through it, against a suite floor of 90. | The conversion is **cut**. The seam is inverted instead — see *Proposed Solution* §2. |
| **[reviewer, verified]** Draft did not scope the xtrace lint | `lint-shell-trace-credential-refusal.py:522` uses an **empty** baseline in `--changed`/`--paths` mode, and `ci.yml`'s `lint-bot-statuses` job runs exactly that (the `--changed --base origin/main` step). Verified: `zot-inventory.sh`, `betterstack-query.sh`, `supabase-advisor-scan.sh` and both host scripts are baselined with **no** preamble. | Touching any of them fails CI until the `case "$-" in *x*)` preamble lands in the same commit. Scoped as explicit work with its own AC. |
| **[reviewer, verified]** `#7867`'s leading unblock option | `apps/web-platform/infra/variables.tf:615` records that `2734275` **was itself minted via `POST /api/v2/sources` on 2026-09-03** — and has never stored a row. Recreation is a second draw from the same urn. | Run a **discriminator** before choosing. |
| **[reviewer, verified]** `#7208`'s `MAX_WALK_HOPS` question | The hook is registered **only** as a `SessionStart` hook (`.claude/settings.json`; no lefthook entry). In production it runs 1–2 hops from `claude`; deeper trees are covered by cgroup inheritance from the SessionStart adoption. | **Retired, not deferred**, and recorded on #7208. |
| **[reviewer claim — checked and WRONG]** "the `betterstack` C4 element records `2734275` as storing nothing" | It does not. `grep -in "never stored\|storing nothing\|no row"` over all three `.c4` files returns zero. That claim lives only at **ADR-192:326** and in `model.c4:630`'s `TARGET state — wired at merge, unobserved` clause. | The plan names the actual target text, so nobody hunts a string that is not there. |
| #7886: "two candidate directions, explicitly unverified" | Direction 2 is **refuted**: at the failing depth a Claude PID *is* discoverable; only the hook, one hop deeper, cannot reach it. | Rejected on evidence. |
| #7886: the count divergence is a second phenomenon | One branch: `if [[ "$outcome" == "applied" && … ]]` gates **8** assertions; its `else` is **1** `fail`. 8 − 1 = 7 = 54 − 47. | One cause, one fix. |
| #7867: the Actions-secret limitation (struck through in the body) | Present in both planes — Doppler `soleur/prd_terraform` and Actions secrets (mirrored `2026-09-06T15:15:30Z`). | The credential rung is **pre-cleared at plan time**. |
| #7867: implies no verdict has been measured | One has: `ROUNDTRIP_NOT_STORED` at `2026-09-06T15:04Z`, before the directive's `earliest=`. | A **prior**, not a conclusion. |

---

## Research Insights

### Premise Validation (Phase 0.6)

All three cited issues are `OPEN`. `#7855`/`#7811` are `CLOSED`; `#7856` is `MERGED`. All 28 cited
paths exist; all 6 cited ADR ordinals resolve; all 10 issue/PR references resolve with the stated states.
No premise was stale; five were incomplete and one reviewer-supplied claim was wrong — all corrected.

### Property List (Phase 0.6b)

| # | Property | Issue |
|---|---|---|
| P1 | Today's actual round-trip verdict for source `2734275` is measured, recorded, and acted on — with the supporting warehouse rows pulled first-hand. | #7867 |
| P2 | No credential-forwarding `curl` **in a tracked `*.sh` file** can have its destination chosen by the environment **through the URL variable, a proxy variable, or `~/.curlrc`**. The plan does **not** claim this holds today: it fixes the sites #7873 names, stops the population growing, and makes the remainder visible and shrinking. | #7873 |
| P3 | A reader of `tests/scripts/test-zot-inventory.sh` cannot mistake "this script has no destination confinement" for an intentional, asserted design property. | #7873 |
| P4 | Editing a host script does not silently ride a live-host re-provision in on a PR whose subject is something else. | #7873 |
| P5 | The pre-commit gate is green on a commit whose diff has nothing to do with the memory backstop. | #7886 |
| P6 | T8 still reddens when the hook genuinely fails to adopt a session a Claude PID *is* reachable for. | #7886 |

**P2's qualifiers are load-bearing.** Two exclusions, stated because a guard must not certify what it
does not check: **transport-binary substitution** (`apps/web-platform/scripts/sentry-monitors-audit.sh:118`'s
`CURL_BIN="${CURL_BIN:-curl}"`, strictly stronger than substituting a destination) and the **`*.sh`
boundary** — seven byte-identical credentialed ingest `curl`s live in cloud-init YAML, and
`cloud-init-inngest.yml:264` hardcodes the very literal this work pins. Both are named in the deferral
issue, not silently outside the walker.

### Cut List (Phase 0.6b, extended twice by review)

| Mechanism | Why cut |
|---|---|
| A new latency constant in the probe | The probe derives its budget as `20 × 17 s`; #7867 exists because writing an unmeasured constant was refused. |
| A stall-detection arm inside the probe | #7867 records this as considered at #7856's ship and **rejected**; the sweeper comments on every run. |
| A 25-line URL-authority parser per site | `betterstack-ingest-probe.sh` needs one because it accepts any vendor subdomain. These pin one literal. |
| A bespoke proxy/`.curlrc` idiom | **Exists.** `scripts/supabase-logs-query.sh` carries the complete idiom *and* the prose explaining why a URL pin alone is insufficient. |
| A bespoke assembly-guard design | **Exists twice.** `lint-supabase-deprecated-endpoints.sh` has the quantifier inversion and a ratchet; `lint-shell-trace-credential-refusal.py` already enumerates tracked `*.sh`, classifies credential-bearing files, and carries a dated 136-entry baseline, a `--changed` mode, a suite and CI + `test-all.sh` wiring — and every site in the draft's table is **already in its baseline**. |
| A new `BS_CONTROL_INGEST_URL` constant | **Cut on review.** It bought no listed property once the host-side inline literal was cut. Parity is asserted over the declarations that already exist. |
| A dedicated host-literal parity guard | **Cut.** It existed only to reconcile copies the draft created. Not inlining removes the need. |
| A permanent nested-fork depth battery | **Cut.** Re-running the systemd suite inside nested forks on every commit, on the interactive pre-commit path, for a fix whose premise is that gate's environment-sensitivity. The repo already kept `memory-backstop-mutation-battery.sh` out of the auto-glob for exactly this reason. |
| **The stubbed-`curl` harness conversion** | **Cut — it could not have worked.** The pin runs before curl is invoked, so a curl stub cannot prevent `run_inv`'s loopback injection being refused on every case; and it was sized against 4 assertions when ~79 read `INGEST_BODY`. |
| A test-only env var carving out loopback | Any predicate the environment can set becomes the hole — `betterstack-sources.sh`'s header records this as *measured*. |
| A `MAX_WALK_HOPS` drift guard | The test **sources the hook**; the gate reads the constant directly. Nothing to keep in sync. |

### Applicable institutional learnings

- `knowledge-base/project/learnings/security-issues/2026-09-06-the-file-i-added-to-fix-a-p1-shipped-a-p1.md` — the PR fixing #7855 shipped three P1-shaped defects **inside its own verification**; its Session Errors name #7873 directly. This plan's draft repeated the pattern four times over, which is why the panel's mechanical verification was the load-bearing step and not a formality.
- `knowledge-base/project/learnings/2026-08-13-my-guard-was-green-with-its-property-inverted-and-three-published-claims-were-false.md` — anchor an assertion positionally to the gate it is about. Directly applied twice: the `#7886` guard asserts the origin **PID value** (because "a fork was spawned" is satisfied by the no-op), and the depth harness asserts its **achieved depth** (because nested `bash -c` adds none).
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — *the cheapest edit that breaks the property while leaving the guard GREEN.* For a URL-only pin: **no file edit at all**.
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` — a floor reports via `printf >&2` + `exit 1` directly; the oracle asserts the **failure-message shape**. Its subshell clause is the same semantics class as the `$$`/`$BASHPID` defect.
- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md` and `#7840` — **checked and excluded**: `scripts/test-all.sh` unsets the nine `GIT_*` variables before dispatching any suite, and a `GIT_INDEX_FILE=` perturbation reproduced `PASSED 54`.
- `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` — `-target` walks dependencies, not dependents.
- `knowledge-base/project/learnings/security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md` — a resource absent from the `-target=` allowlist never applies. **Verified:** `terraform_data.private_nic_guard_install` **is** in the list (12th of 15). That is the hazard, not the reassurance.

### Measured external behaviour (curl, verified live)

Against `curl 8.18.0 / OpenSSL 3.5.5` with a local listener logging the `Authorization` header.

1. **No `-L` means no redirect is followed** — a 302 to a second host never receives the header, in both the `-H` and `--config` forms. `-f` only fires at ≥400, so a bare `-fsS` exits 0 on a 3xx without noticing.
2. **Proxy environment variables defeat a URL pin.** With `http_proxy=http://127.0.0.1:1`, curl logs *"Uses proxy env variable http_proxy"* and attempts the proxy **before** the pinned host. `--noproxy '*'` and `--proxy ''` each disable it.
3. **`~/.curlrc` is read even when `--config` is used**; `--disable` suppresses it **only as the literal first argument**. Doc-derived — no `~/.curlrc` existed here to demonstrate live injection, which is why AC B7 requires the case be *demonstrated* failing pre-fix rather than assumed.
4. **Multiple URL operands are sequential transfers and local options replay** — `curl --config <file> <extra-url>` fetched both, both carrying the same header. The real constraint is therefore **no second URL operand**, not "no argv after `--config`": three options already follow it at `zot-inventory.sh:516` and that is fine.
5. **`--proto '=https'`** rejects a non-`https` URL pre-connect. Kept as **house style** (already at three sites, asserted by two suites), scoped to the ingest call only.
6. **Exact `==`/`!=` on an untouched literal** — never prefix or substring; no normalising, trimming or lowercasing first.

### Destination-confinement census

Tracked non-test `*.sh` invoking `curl` while carrying a credential: **80 files / 325 `curl` lines /
1 compliant**; **16** take their destination from an env-settable variable; **20** ship to installed
users under `plugins/**`; **7** are baked into `local.host_script_files`. Phase 0 regenerates these
from the classifier, because five independent measurements returned five different numbers purely
from token-set differences.

**Verified negatives, recorded so nobody re-derives them:** `web-private-nic-guard.sh`'s second
env-settable URL `WEB_NIC_GUARD_URL` sends no `Authorization` header (a bare heartbeat ping);
`plugins/soleur/skills/flag-set-role/scripts/flip.sh` forwards a write-capable Flagsmith key but its
destination is a `readonly` hardcoded literal — a transport gap, not a pin gap.

### Related issues and PRs

`#7855`, `#7856`, `#7811`, `#7840`/`#7835` (git-env boundary, excluded), `#7208`, `#7169`, `#7409`,
`#7797`/ADR-202 (the lint this plan extends; ADR-197 is a different decision), `#7776`/`#7807` (the inverted brand-survival ladder),
`#7502` (the contributor-hook path that makes this plan's vector reachable).

---

## Open Code-Review Overlap

- **#7208 — memory-backstop post-merge hardening.** Names both hook files. **Acknowledge, and retire
  one of its open questions.** §C proposes extending `_maybe_never_worked` — adjacent, different
  concern. This plan changes only the **test's** gate, and it **answers** §C's `MAX_WALK_HOPS`
  question with evidence, posted as a comment there. #7208 stays open.
- **#2197 — billing refactor.** Matches only on prose about a hypothetical `count = 2` edit to
  `server.tf`, which this plan does not edit. **Acknowledge.** No overlap in fact.

---

## Hypotheses

The Phase 1.4 network-outage gate fires on the SSH `connection` block reached by a merge-triggered
apply. **The host-script work is deferred out of this cycle**, so no apply is scheduled — these are
the preconditions that work must verify when a window opens, in L3→L7 order.

1. **L3 — credential presence for the SSH bridge.** `apply-web-platform-infra.yml` gates its
   SSH-provisioned apply on `steps.ssh_token_gate`, which `::warning::`-skips the whole apply when
   `CI_SSH_ACCESS_TOKEN_ID` is absent or unreadable. **[verified]** — both tokens are present in
   Doppler `soleur/prd_terraform` (names read, values not retrieved). A skip leaves a PR green while
   the change never lands; remediation is automated — the workflow carries `workflow_dispatch` with a
   required `reason` input, and `steps.ssh_token_gate.outputs.ssh_skip_cause` names the cause.
2. **L3 — the transport actually used.** The apply runs after `uses: ./.github/actions/cf-tunnel-ssh-bridge`,
   so the provisioner reaches web-1 through the Cloudflare tunnel's `ssh.` ingress while
   `connection.host` is web-1's public IPv4. **[verified]** — Hetzner-firewall/admin-IP drift is not
   the first hypothesis; CF Access token validity and tunnel-ingress health are.
3. **L3 — routing/DNS.** **Opted out with justification:** the same bridge carried a successful
   `push`-triggered apply at `2026-09-07T10:13:58Z`.
4. **L7 — the provisioner's effect.** It rewrites `/etc/default/web-private-nic-guard` and reinstalls
   the script, unit and timer, **on web-1 only** — both `connection.host` and `triggers_replace`
   hardcode it. **[verification named, no SSH]** — the guard's `SOLEUR_PRIVATE_NIC` line is read out
   of the warehouse with `scripts/betterstack-query.sh`.
5. **L7 — service layer.** No sshd/fail2ban hypothesis: layers 1-4 are verified or have a named
   verification.

---

## Problem Statement

**#7867.** The instrument exists and is enrolled; nobody has read what it says today.

**#7873.** Three scripts hand a bearer token to whatever destination an environment variable names —
and one of them, `zot-inventory.sh`, does it **twice**: once for the ingest bearer and once for a
registry pull token written into a netrc whose `machine` line is derived from another env-settable
URL. The gap is narrower than the issue's framing in one dimension (the proposed fix does not close
it) and far wider in another (~80 files share the class; one is compliant). Meanwhile
`tests/scripts/test-zot-inventory.sh`'s `inv-exfil` asserts the exfil mutant **succeeds**.

**#7886.** The suite reddens the pre-commit gate on diffs touching neither the hook nor its test.

---

## Proposed Solution

### 1. #7886 — seed from `$BASHPID`, read the hook's own constant, and perturb depth with a real fork

The cause: the E2E gate walks up to 8 hops **from the test's own `$$`**; `discover_claude_pid` walks
up to `MAX_WALK_HOPS=8` **from the hook's own `$$`**, and the hook is a *child* of the test. When
`claude` sits at exactly hop 8 from the test, the gate passes and the hook fails, by one.

| Extra forks | `claude` at hop (from test) | Result |
|---|---|---|
| 3 | 6 | `PASSED 54 [live: yes]` |
| 4 | 7 | `PASSED 54 [live: yes]` |
| **5** | **8** | **`FAILED 1 (passed 46)`** + the exact `✗ T8 real hook did not apply (outcome='skipped' reason='claude_pid_not_found')` line |
| 6 | 9 | `PASSED 41 [live: yes, e2e SKIPPED]` — a different mode |

**Delete the second walk; do not align it. [revised at deepen — see the collision note below.]**

The draft aligned the two walks by seeding the gate from `$BASHPID` and reading the sourced
`MAX_WALK_HOPS`. That works, but it keeps two independent walks one frame apart and spends a guard
keeping them synchronized. The better answer is to **remove the gate's walk entirely and ask the hook
for its own verdict**, because the hook is the only thing whose reach actually matters. That
eliminates the defect class rather than managing it.

**It has to be reason-aware, and that is what makes it non-vacuous.** The hook emits **12** distinct
decline reasons — measured: `adoption_unverified`, `cap_out_of_range`, `claude_pid_not_found`,
`concurrent_apply`, `disabled`, `fleet_caps_unverified`, `no_bus`, `no_busctl`, `no_jq`,
`no_terminal_scope`, `pid_reuse_disambiguated`, `scope_caps_unverified`. They are not
interchangeable, so the gate classifies rather than collapsing them:

| Class | Reasons | Gate behaviour |
|---|---|---|
| Environment cannot exercise the arm | `claude_pid_not_found`, `no_bus`, `no_busctl`, `no_jq`, `no_terminal_scope` | **SKIP** — a legitimate context, accounted for by `live_mark` |
| Deliberate opt-out or a concurrent run | `disabled`, `concurrent_apply` | **SKIP** — both are correct outcomes, not defects |
| The hook tried and something was wrong | `adoption_unverified`, `cap_out_of_range`, `fleet_caps_unverified`, `pid_reuse_disambiguated`, `scope_caps_unverified` | **FAIL** — these are the defects T8 exists to catch |

This is what preserves P6, and it is why the draft's blanket rejection of "gate on `outcome`" was
wrong: it rejected the *unclassified* form ("skip whenever `outcome != applied`", which really would
make T8 unable to redden) and mistook it for this one. Corrected.

**Fallback, if the verdict gate cannot be adopted:** seed the gate's walk from **`$BASHPID`**, not
`$$` — measured, inside `( )` `$$` is still the parent's PID and only `BASHPID` moves, so a subshell
keeping `_p=$$` is a no-op that satisfies any guard checking merely that a fork happened — and read
the budget from the sourced `MAX_WALK_HOPS` rather than the literal `for _hop in 1 2 3 4 5 6 7 8`.

**Either way, the depth harness must use a real fork and verify its own depth.** Measured on this
machine: base distance to `claude` = 2; `bash -c` ×1 → 3; `bash -c` ×2 → **3**; `{ …; } & wait` → 4.
Nested `bash -c` adds **no** hop (the outer `exec`s into the inner), and the base frame varies by
runner — so "insert five forks" written the natural way tests nothing and passes green. Use a real
fork per level, **measure the achieved depth against `/proc` before invoking the suite**, and derive
the target at runtime rather than hardcoding 5.

### Collision: PR #7879 is already taking this file

**Verified at deepen time.** PR **#7879** ("WIP: test-fixture env adoption, gdpr-gate ledger
isolation, memory-backstop ancestry", branch
`feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry`) is **OPEN and WIP**, and a comment on issue
7208 dated `2026-09-07T11:17:44Z` states it changes `.claude/hooks/memory-backstop.test.sh` with
exactly the verdict-gate mechanism above — *"the suite now asks the hook for its verdict and gates on
`outcome != "applied"` rather than on any single reason string, since the hook has eleven distinct
decline reasons and two of them (the documented opt-out and `concurrent_apply`) must skip rather than
fail."*

Three facts bound what that means for this plan, all checked rather than assumed:

- The change is **not yet pushed**: `git diff origin/main...origin/feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry`
  over both hook files is **empty**, and the gate at that branch's HEAD still carries `_p=$$` and the
  literal `for _hop in 1 2 3 4 5 6 7 8`. So #7886 is still unfixed on `origin`.
- PR #7879 closes #7849, #7853 and #7854 — **not** #7886.
- Its mechanism is the one this plan now adopts, and the reason-classification fact behind it is real
  (12 reasons, measured above).

**RESOLVED 2026-09-07 — PR 1 is CUT and #7886 is transferred to PR #7879.**

The Phase 0 step 5 re-check ran at the top of this session's `/work` handoff and found more than the
deepen pass could see: PR #7879's fix is **implemented**, in unpushed local commit `4115024f5`
("fix(test): ask the hook for the e2e precondition instead of re-deriving it"), touching
`.claude/hooks/memory-backstop.test.sh` and `.claude/hooks/memory-backstop-mutation-battery.sh`. Its
commit message carries the measured root cause this plan reached independently — the suite's walk and
the hook's walk **start one process apart**, so matching the traversal limit cannot make them agree —
and it gates on `outcome != "applied"` over a reason set derived from the hook's source.

That is the same mechanism this plan adopted at deepen, arrived at independently, and it is further
along. Shipping PR 1 would put two live sessions on one file. So:

- This branch ships **nothing** under `.claude/hooks/**`. PR 1's tasks (1.a–1.h) are struck.
- #7886 is commented with a pointer to #7879's commit, and #7879 must add `Closes #7886` to its body
  so the issue is not orphaned when it merges. That comment is the transfer record.
- The `#7208` note (task 1.g — `MAX_WALK_HOPS` is not raisable-for-benefit) travels with #7886 to
  #7879 rather than being dropped; #7879's own plan already reaches the same conclusion and cuts the
  raise for the same reason.

The paragraph below is retained because it remains the correct reading of the count under the hook,
and #7879's PR will need it for the same reason this one would have.

**What this means under lefthook, so nobody "fixes" the count later.** At the lefthook depth the
corrected gate reports `E2E=no` and `skip()`s seven labels; `skip()` increments neither counter, so
the suite reports **47 and exits 0** — green, honestly skipped. 47-under-the-hook versus 54-direct is
the correct steady state, not a regression, and no acceptance criterion asserts a return to 54.

### 2. #7873 — pin site 1 (both credential paths), invert the seam, add a rule to the lint that owns the assembly

**No new constant.** Site 1 pins against the literal it already carries. Parity is asserted across the
declarations that **already exist** — measured at **six**, not three: `zot-registry.tf` (the local),
`cloud-init-inngest.yml` (hardcoded), `vector.toml` (the sink uri), `registry-userdata-budget.sh`,
`zot-inventory.sh` and `betterstack-ingest-probe.sh`. A parity assertion naming three of six would go
green with the fleet split across two destinations.

**Site 1 has two credential paths, and the issue names one.** The ingest bearer at `:516` gets the
equality pin plus transport confinement — `--disable` first, `--noproxy '*'`, `--proto '=https'` —
scoped to that call only, because the registry leg defaults to `http://127.0.0.1:5000` and
`--proto '=https'` would break both production and the harness. The **netrc path** — the `printf .. machine %s .. > "$NETRC"` write and the `--netrc-file "$NETRC"` read inside `http_get()` —
gets the same treatment on its own terms: `REGISTRY_HOST` is derived from an env-settable URL and
lands in the netrc's `machine` line, so the registry destination needs its own validation before the
netrc is written. The refusal exits non-zero here: no boot depends on it.

**The guard is a new rule in an existing lint, not a fourth walker.**
`scripts/lint-shell-trace-credential-refusal.py` already enumerates tracked `*.sh`, already classifies
credential-bearing files, already carries a dated baseline and a `--changed --base origin/main` mode,
already has its own suite, and is already wired into both `scripts/test-all.sh` and `ci.yml`. It is
also structured for exactly this: `check_rule_a`, `check_rule_b` and `check_rule_c` are separate
functions, so **Rule D** is the established extension shape — *every credentialed `curl` carries
`--disable` first and `--noproxy '*'`; where its destination comes from an env-settable variable, an
exact-equality pin.* That dissolves the registration question the draft spent a section on.

**Two things Rule D must ADD rather than inherit — the deepen pass measured both, and the first would
have shipped a vacuous guard.**

1. **The baseline is per-FILE and rule-agnostic, and every target site is already in it.** The lint
   suppresses violations with `if rel not in baseline`, which drops *all* rules' findings for that
   file, not just the rule that baselined it. The baseline holds **130** entries, and **seven of the
   seven** Better Stack sites are among them — `zot-inventory.sh`, `betterstack-query.sh`,
   `supabase-advisor-scan.sh`, `betterstack-ingest-probe.sh`, both host scripts, and
   `arm-heartbeats.sh`. Sharing it would make Rule D green over precisely the population it was
   written for, on the repo-wide run that is the blocking arm. **Rule D therefore needs per-rule
   baseline granularity** — either its own baseline file or an entry shape that names the rule — with
   a migration preserving the existing 130 as A/B/C-scoped. The `--changed` arm is unaffected:
   `baseline = set() if (args.changed or args.paths)`, so a touched file must satisfy every rule
   including D. The vacuity is confined to the repo-wide sweep, which is exactly where the ratchet
   and the visibility live.
2. ~~**There is no ratchet.**~~ **CUT AT REVIEW (2026-09-07).** A ratchet was built and then
   removed: it is **strictly subsumed** by the repo-wide run. Suppression is `if rel not in supp`,
   so a NEW offender is by definition absent from the baseline, its violations are reported, and
   `scripts/lint-shell-trace-credential-refusal-repo` already exits 1 — `--check-highwater` could
   not fire without that suite having fired first. Verified by measurement, not argument: removing
   a transport flag from `betterstack-query.sh` made the plain repo-wide run `rc=1`.
   The precedent it was copied from (`lint-trap-tempfile-ownership`) is scoped to ADDED LINES and
   carries NO enumerated baseline, which is what makes a population count load-bearing there and
   redundant here. Copying a mechanism because four siblings have one is how a precedent becomes a
   requirement. Two review agents converged on this independently.

The classifier covers `-u` as well as `--user`, plus `--header @-`, `--netrc`/`--netrc-file`,
`--oauth2-bearer`, `--proxy-user` and `-E`. The `*.sh` boundary and `CURL_BIN` are stated exclusions.
**The baseline is honest**: `arm-heartbeats.sh` (a Better Stack API token on argv) and
`cutover-verify.sh` (the `--config` chokepoint) are real members under `apps/web-platform/infra/**`
that this cycle does not fix, so they stay baselined rather than being excluded by a narrowed
classifier that would make the guard lie.

**The xtrace-preamble drawdown is scoped work.** That lint's baseline carries a drawdown trigger and
`--changed` mode bypasses the baseline. Verified: `zot-inventory.sh`, `betterstack-query.sh`,
`supabase-advisor-scan.sh` (and, when they land, the two host scripts) are baselined with no preamble.
**Touching any of them fails CI until the `case "$-" in *x*)` preamble is added in the same commit.**
Model: `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`.

**Invert the seam; do not convert the harness.** The draft's stubbed-`curl` conversion could not have
worked: the pin is a bash comparison evaluated *before* curl runs, so a curl stub cannot stop
`run_inv` — which injects a loopback `ZOT_INVENTORY_INGEST_URL` on every case — from being refused
everywhere. And it was sized against 4 assertions when `marker()` reads `INGEST_BODY` and **74
`expect_field` calls** flow through it, against a suite floor of 90. Instead, invert the direction of
the `mutate_sub` seam the suite already has: **normal cases run a source-mutated copy whose pinned
literal is rewritten to the loopback URL**, so the injected env value matches the copy's pin and all
~79 assertions keep working against the real listener; **`inv-exfil` runs the unmutated script** with
`ZOT_INVENTORY_INGEST_URL` set to the canary and asserts refusal — zero canary requests **and** the
refusal's message anchor present, not a bare non-zero exit (a `set -u` crash also exits non-zero).
A source mutation is not an env carve-out, so this does not reopen the `attacker.example.org` shape.
Note the coupling: `mutate_sub inv-exfil` matches the literal at `:91` and `fail`s if it is absent, so
the pin must not replace that literal with a sourced variable.

**The rest is deferred with numbers.** A tracking issue carries the census, the seven cloud-init YAML
siblings, the four Resend host scripts (`disk-monitor.sh`, `resource-monitor.sh`,
`container-restart-monitor.sh`, `cron-egress-alarm.sh` — each forwarding `RESEND_API_KEY` with no
`--noproxy`), and the `CURL_BIN` seam with an explicit upgrade trigger. The ratchet keeps the
remainder visible on every run.

### 3. #7873 sites 2 and 3 — deferred, and why that is the stronger answer

The host scripts read their destination from `/etc/default/web-private-nic-guard`, **a file Terraform
writes** — changing it requires root on web-1. A pin there defends against an attacker who has already
won, or against Terraform drift, and drift is now caught CI-side by Rule D's parity assertion with no
host edit. Against that: a `terraform_data` replacement re-running an SSH provisioner against the live
serving host, plus an image-coherence window from site 2's effect on `local.host_scripts_content_hash`.

**So the two host scripts get the transport flags as a passenger on the next
`apps/web-platform/infra/**` PR that is already opening a window for its own reasons.** Five facts
that PR must carry, all verified here:

- **The refusal is skip-and-report, never fail-stop.** At `soleur-host-bootstrap.sh` the post is
  followed by `soleur-boot-emit … fatal`, the Vector-independent dark-host detector; at
  `web-private-nic-guard.sh` by the `web_nic_guard` heartbeat. An `exit` above either silences a
  healthy host's beat or a dark host's only signal.
- **Site 2 is silent today.** `web-private-nic-guard.sh:101` has a `[nic] WARN: … unset` line;
  `soleur-host-bootstrap.sh:878-881` has **no `else` branch at all**. Delivering "never a silent skip"
  there means adding a line that does not exist yet.
- **POSIX `[ … ]`, not `[[ … ]]`, at the bootstrap site** — it runs under dash.
- **web-2 will not receive the fix.** The SSH provisioner hardcodes web-1; web-2's copy comes only
  from the image bake, and `ignore_changes = [user_data, image]` means it will not re-create for the
  moved hash. web-2 runs the unpinned script until its next rebirth — an accepted, **tracked** gap,
  not something a green guard should paper over.
- **Confirm the image's `curl` accepts the flags** via `docker run --rm ubuntu:24.04` in CI, not a
  host shell.

### 4. #7867 — run the instrument, open the escalation regardless, then discriminate

Run `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` as the sweeper would, under
`doppler run -p soleur -c prd_terraform`, and pull corroborating rows with `scripts/betterstack-query.sh`.

**The vendor escalation opens on this run, unconditional on the verdict.** #7867 records it as
*deliberately not gated* — hypothesis (b) is already confirmed independently by `CLUSTER_DOESNT_EXIST`
persisting after an acknowledged write. The draft re-gated what was already de-gated; corrected.

| Verdict | Exit | Action |
|---|---|---|
| `ROUNDTRIP_STORED` | 0 | A **state change**. Comment marker, latency and the vendor's `ingest_time - dt`. **Leave closure to the sweeper** — `closed_precheck` re-verifies any close not carrying its own `### Sweeper run: PASS` block, so an agent-authored close re-enters the closed set and is reopened. Correct ADR-192:326 and `model.c4:630`. |
| `ROUNDTRIP_NOT_STORED` | 1 | The substantive finding, reproduced twice. Comment marker + timestamps; issue stays open. Run the discriminator below. Record a **review-by date**: the first sweeper run ≥7 days after the escalation opened, at which "wait for the vendor" ceases to be the default. |
| `ROUNDTRIP_DARK` | 2 | An account-level claim, not one about this source. Comment, and file/append to a `#7811`-shaped issue. **Run once this session; do not loop.** |
| `ROUNDTRIP_UNKNOWN` | 3 | Diagnose in the order #7867 records — **schema first** (`dt`/`raw`/`_row_type`/`ingest_time` were verified against a `vector`-platform table; this source is `http`), credential second. Record the diagnosis **conclusion**, not merely that it was attempted. |
| **any other exit, or no `SOLEUR_BETTERSTACK_ROUNDTRIP` line on stdout** | — | **The probe did not run.** Exit **78** is real and reachable: the probe refuses to run under `set -x` with a live credential bound (#7797) and emits **no verdict line**. Record the raw exit code and output; treat as not-a-verdict; do not close, do not escalate on it. |

**Re-read #7867's state immediately before commenting.** Its cron fires around 19:4x UTC; if the
sweeper reached it first, read that comment and re-run only when the recorded verdict is
`UNKNOWN`/`DARK`. Never post a second contradicting verdict for one window.

**The discriminator, on the `NOT_STORED` branch.** `apps/web-platform/infra/variables.tf` records
(in the comment on `git_data_betterstack_logs_token`) that `2734275` **was itself minted via
`POST /api/v2/sources` on 2026-09-03**, and it has never stored a row. Recreation is therefore a
second draw from the same urn — same account, same `http` platform, same `eu-central-1a` region. So
before choosing:

> **Mint a throwaway Logs source via `POST /api/v2/sources` — same platform, same region — POST one
> marker, read it back.** No Terraform change, no Doppler write, no host touch. `BETTERSTACK_API_TOKEN`
> and `BETTERSTACK_QUERY_*` are already in `prd_terraform`.
>
> - **Throwaway stores** → the defect is object-scoped; recreation is the answer.
> - **Throwaway does not store** → recreation is **refuted**, not merely unevaluated, and the answer
>   becomes escalate + move the birth gate.

Two further verified facts for that decision: **Sentry is already a wired evidence channel** —
git-data bakes a DSN and posts from `bootcmd` onward, and the rung-2 capture already implements a
Sentry read path — so "move the birth gate" is a decision about which channel is *authoritative*, not
a greenfield build. And **repointing at control source `2457081` stays unavailable** by ADR-192 I-2.

The mechanism choice is routed to the `cto` agent with the discriminator's result attached; the
*deadline* is the review-by date above.

**Restated so it is not re-litigated:** the probe must never write to source `2457081`. It refuses by
name, deriving the refusal from `BS_CONTROL_INGEST_HOST`. Nothing here changes that.

---

## Technical Approach

### Delivery — three PRs from this branch, plus one task that is not a PR

The slicing discipline below is a property of **merges**, not commits: `apply-web-platform-infra.yml`
fires on the union of a PR's diff. So these are three separate PRs off this branch, not three commits
in one.

| Unit | Scope | Paths | Rationale |
|---|---|---|---|
| **PR 0** | `--disable` + `--noproxy '*'` into the four sweep-only `scripts/` files, plus the xtrace preamble each needs | `scripts/**` | Lands the named single-user-incident vector (`betterstack-query.sh`) **first**, with no new machinery. Depends on nothing. |
| ~~**PR 1**~~ | ~~#7886 fix + its guard~~ | ~~`.claude/hooks/**`~~ | **CUT 2026-09-07, on operator decision.** The Phase 0 step 5 re-check resolved: PR #7879 has the fix implemented in unpushed local commit `4115024f5`, with the same verdict-gate mechanism and a fuller reason classification. #7886 is transferred to #7879; this branch ships nothing under `.claude/hooks/**`. See §Collision. |
| **PR 2** | #7873 site 1 (both credential paths) + Rule D + the inverted seam + the parity assertion | `scripts/**`, `tests/scripts/**`, `.github/workflows/ci.yml`, `model.c4` | The guard that keeps PR 0's sites honest. |
| **Track D** | #7867 — escalate, run, record, discriminate | none, or ADR/C4 on the branch taken | Runs outside the PR chain, first in wall-clock. Not a PR: on three of four branches it is zero code. Its conditional docs edit folds into whichever PR is in flight when the verdict lands. |
| **Deferred** | #7873 sites 2/3 transport flags | `apps/web-platform/infra/**` | Rides a window opened for another reason. |

**PR 0 exists because the serial chain otherwise puts the highest-value security fix behind two merge
cycles.** If the session's budget expires mid-chain, what must already have shipped is the leak fix.

### Implementation Phases

#### Phase 0 — preconditions

1. Re-run the three `gh issue view` state checks; abort any unit whose issue closed.
2. **Fix the classifier's token set, then run the census with it.** The classifier does not exist yet
   at Phase 0 — so this step *defines* it (a token set covering `-u`, `--user`, `--header @-`,
   `--netrc`/`--netrc-file`, `--oauth2-bearer`, `--proxy-user`, `-E`) and runs a one-off sweep with
   exactly that set. Rule D then implements the same set, and B1's floor is the number this sweep
   returns. Deriving the floor from a *different* token set than the rule ships with is how five
   reviewers got five different counts. State the number.
3. Enumerate which of PR 0's and PR 2's files are baselined in the xtrace lint without a preamble, so
   the drawdown is scoped before the first commit rather than discovered by CI.
4. Measure this runner's base distance to `claude` (`/proc` walk) so the depth harness targets
   `MAX_WALK_HOPS` hops from the hook's frame rather than a hardcoded number.
5. ~~Re-check PR #7879's state.~~ **DONE 2026-09-07 — outcome: PR 1 CUT.** #7879 carries the fix in
   unpushed commit `4115024f5`. #7886 transferred to #7879; this branch ships nothing under
   `.claude/hooks/**`. See §Collision.
6. ~~Check whether the planned `#7886` guard suite will be floor-bearing.~~ **MOOT — PR 1 is cut, so
   no new `.claude/hooks/` suite is added and `MAX_DEFERRED=47` is not perturbed.** The finding stands
   for whoever ships that guard (#7879): `.claude/hooks/` is in `guard-vacuity-floor.test.sh`'s
   `DEFERRED_DIRS` and `MAX_DEFERRED` is shrink-only, so a new deferred suite there reddens CI unless
   it is promoted in the same PR. The xtrace drawdown blocker still applies to PR 0/PR 2.

#### Phase 1 — PR 0 (the sweep)

1. Add the xtrace preamble to each affected file, modelled on `betterstack-roundtrip-latency-7855.sh`.
2. Add `--disable` (first argument) and `--noproxy '*'` to the credentialed `curl` in
   `supabase-advisor-scan.sh`, `betterstack-query.sh`, `betterstack-ingest-probe.sh`,
   `followthroughs/betterstack-roundtrip-latency-7855.sh`. **Flags only — no destination pin**: three
   suites drive these through a `BETTERSTACK_QUERY_HOST=127.0.0.1` env seam, and pinning here would
   send synthetic credentials at the real warehouse from CI.
3. Verify each affected suite still passes.

#### Phase 2 — PR 1 (#7886) — CUT

Settled at Phase 0 step 5: PR #7879 owns this. The only work here is the two transfer comments
(on #7886 and on #7879), described in *Acceptance Criteria* §PR 1.

#### Phase 3 — Track D (#7867), first in wall-clock terms

1. **Open the Better Stack escalation**, unconditional on verdict.
2. Re-read #7867's state and latest comment; if the sweeper already posted a verdict for this window,
   read it rather than re-running.
3. Run the probe under `doppler run -p soleur -c prd_terraform`, capturing full stdout and exit code.
4. Pull the corroborating rows with `scripts/betterstack-query.sh`.
5. Comment verdict, marker, latency and `ingest_time - dt` on #7867, **including the verdict→action
   table**, so the decision procedure survives this plan's archival.
6. Take the branch the verdict names. On `NOT_STORED`, run the throwaway-source discriminator, route
   the mechanism choice to `cto` with its result, and record the review-by date. On `STORED`, write
   the ADR-192:326 and `model.c4:630` corrections.

#### Phase 4 — PR 2 (#7873 site 1 + Rule D)

1. **RED first**: invert the `mutate_sub` seam — normal cases run a copy whose pinned literal is
   rewritten to loopback; `inv-exfil` runs the unmutated script with the canary URL and asserts
   refusal, anchored on the refusal message. It must fail against today's `zot-inventory.sh`.
2. Add the proxy-defeat case and **demonstrate** it failing against the pre-fix script. If the
   `.curlrc` case cannot be made to fail pre-fix (finding 3 is doc-derived), drop it and say so
   rather than shipping a case that proves nothing.
3. Add the xtrace preamble to `scripts/zot-inventory.sh`.
4. Pin + confine **both** credential paths in `zot-inventory.sh`: the ingest `curl` at `:516`, and the
   registry destination whose value reaches the netrc `machine` line at `:179`. Keep the pin's
   comparand the inline literal at `:91` so `mutate_sub` still lands.
5. Add **Rule D** to `scripts/lint-shell-trace-credential-refusal.py` with the widened classifier, its
   baseline regenerated from Phase 0's census, and the six-declaration parity assertion. Mutation rows
   go in that lint's existing suite.
6. Amend the `github -> betterstack` edge description in `model.c4`, then run
   `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
7. File the deferral issue (census, cloud-init YAML siblings, the four Resend host scripts, the
   `CURL_BIN` seam with an upgrade trigger) and the web-2 gap issue.

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **#7886: T8 declares itself SKIPPED on a bare `outcome != "applied"`, unclassified** | **Rejected.** The hook has 12 decline reasons and 5 of them are genuine defects; collapsing them all to a skip makes T8 unable to redden. |
| **#7886: T8 gates on the hook's verdict with the reasons CLASSIFIED** | **ADOPTED at deepen — this reverses the draft.** The draft rejected "gate on outcome" without distinguishing the unclassified form (above) from the reason-aware one, and so rejected the better design along with the worse. Asking the hook for its verdict *deletes* the second walk instead of aligning it, which removes the defect class rather than managing it; the skip/fail classification is what preserves P6. This is also the mechanism PR #7879 is already taking on the same file. |
| **#7886: align the two walks (`$BASHPID` + sourced `MAX_WALK_HOPS`)** | **Demoted to fallback.** Correct and measured, but it keeps two independent walks one frame apart and spends a guard keeping them synchronized. Used only if the verdict gate cannot be adopted. |
| **#7886: raise `MAX_WALK_HOPS`** | **Retired, not deferred.** The hook is registered only as a `SessionStart` hook, where it runs 1–2 hops from `claude`; deeper trees are covered by cgroup inheritance. Raising it buys nothing in production. |
| **#7886: "walk from a spawned child"** (the draft's own wording) | **Rejected as a no-op** — `$$` survives subshells; only `$BASHPID` moves. |
| **#7886: perturb depth with nested `bash -c`** | **Rejected as a no-op** — measured: two nested levels add one hop, not two, because the outer `exec`s into the inner. Use a real fork and verify the achieved depth. |
| **#7886: a permanent depth-perturbation gate** | **Rejected.** Re-running the systemd suite inside nested forks on every commit, on the interactive pre-commit path, for a fix whose premise is that gate's environment-sensitivity. |
| **#7873: a member-list guard over the 8 sites the research read** | **Rejected, with a measurement.** The property names ~80 sites; the list named 8. |
| **#7873: narrow the classifier until only the fixed sites match** | **Rejected.** That makes the guard a member list in structural clothing, and it would exclude `arm-heartbeats.sh` and `cutover-verify.sh` — real members under `infra/**`. An honest baseline plus a ratchet is stronger than a floor of 8 claiming to be a floor of 80. |
| **#7873: a new standalone assembly guard** | **Rejected.** `lint-shell-trace-credential-refusal.py` already owns this assembly, and all eight draft sites are already in its baseline. |
| **#7873: a mechanical sweep across all ~80 now** | **Rejected as scope.** 325 invocation lines, 7 host-baked, 20 customer-shipped. |
| **#7873: a new `BS_CONTROL_INGEST_URL` constant** | **Rejected.** It bought no listed property once the host-side inline literal was cut — and it would break `mutate_sub`'s literal match. |
| **#7873: convert the harness to a stubbed `curl`** | **Rejected — it could not have worked.** The pin runs before curl; a stub cannot stop `run_inv`'s loopback injection being refused everywhere. It was also sized against 4 assertions when ~79 read `INGEST_BODY`. |
| **#7873: open a deployment window for sites 2/3** | **Rejected.** The pin there defends against root-only threats or drift; drift is caught in CI. |
| **#7867: assume the 2026-09-06 `NOT_STORED` still holds** | **Rejected — that is the tracker's whole point.** |
| **#7867: gate the vendor escalation on the verdict** | **Rejected, and already decided** at #7856's CPO sign-off. The draft re-gated it; corrected. |
| **#7867: route the recreate-vs-wait choice without measuring** | **Rejected.** `2734275` was itself API-minted on 2026-09-03 and never stored; the throwaway-source discriminator collapses three of four options for two API calls. |

---

## User-Brand Impact

- **If this lands broken, the user experiences:** for #7886, the pre-commit gate keeps reddening on
  unrelated diffs and the next real memory-backstop failure is waved through, on a machine that then
  OOMs during the user's session. For #7873 site 1, a `zot-inventory` run that refuses its own
  destination stops producing the registry-capacity marker. For the deferred host work, a refusal
  written as `exit` would silence a healthy host's `web_nic_guard` heartbeat or a dark host's only
  Sentry signal — which is why those semantics are specified here rather than left to an implementer.
- **If this leaks, the user's data is exposed via:** `scripts/betterstack-query.sh` carries the
  ClickHouse **read** credential for the Logs warehouse, which holds Vector-shipped journald from
  hosts serving every connected user's push. An `ALL_PROXY` set anywhere that script runs sends that
  credential to a destination of someone else's choosing **with the URL pin fully intact** — measured.
  That credential *is* the access control declared in Article 30 Processing Activity 8's TOM (g)
  ("access restricted to on-call rotation + CLO"), so the defect makes a published Art. 32 technical
  measure defeasible. **Reachable today**: #7502 (open, P0) is the path by which a contributor-supplied
  hook executes in a review worktree and could export the variable.
  **Mitigant, stated so the risk is not over-read:** `apps/web-platform/infra/vector.toml` routes host
  journald through `pii_scrub_*` with `userId → userIdHash` before the Better Stack sink, so what would
  leak is pseudonymized log content, not directly-identifying data.
- **A second exposure in the same file, which the issue does not name:** `scripts/zot-inventory.sh`
  writes `ZOT_PULL_TOKEN` into a netrc whose `machine` line is derived from an env-settable registry
  URL, so that credential too can be sent to a chosen host.
- **If this leaks, the user's workflow is exposed via:** the ingest token permits writing rows to
  source `2457081`, whose any-row liveness is what the rung-2 evidence capture reads as its control
  (ADR-192 I-2) — an attacker holding it can manufacture the liveness that gates a production host's
  birth.
- **Aggregate dimension:** 20 of the ~80 credentialed-curl scripts ship to installed users under
  `plugins/**` (observability layer 7), where the proxy and `.curlrc` environment is not ours.
- **The cost of #7867 staying open, named because the draft did not:** the git-data host has been
  declared in IaC and unprovisioned since 2026-07-01. Two consequences are user-facing —
  `docs/legal/data-protection-disclosure.md` **retracted four disclosed Art. 32 measures** because
  that host was never provisioned, so the published privacy posture is materially weaker than the
  designed one; and `lb-weight-gate.sh` fails closed on the git-data flag, so `replicas = 1` stands
  and web-2 carries serving weight 0, making web-1 a single point of failure. **There is no data-loss
  cost** — `/workspaces` is a persistent volume with GitHub `origin` rehydration and durability is
  intact. Saying that explicitly is what stops a reader escalating a 68-day availability gap into a
  phantom durability emergency.
- **Brand-survival threshold:** `single-user incident`

**The threshold stays `single-user incident` and must not be upgraded.** In this repo the nominally
higher tier procures *less* review: both `/ship` gates and `review`'s `user-impact-reviewer` trigger
grep for that exact literal, so `aggregate pattern` would silently disarm three gates. The inversion
is tracked in #7776 and #7807.

CPO sign-off is required at plan time; `user-impact-reviewer` runs at review time.

---

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_INVENTORY rows in Better Stack Logs source 2457081 — the marker scripts/zot-inventory.sh posts and reads back; per ADR-172 a run is green only after the same ClickHouse path returns the line carrying that run's run_id"
  cadence: "per registry-zot-inventory.yml dispatch"
  alert_target: "the workflow's own failure — the readback is its exit condition — surfaced as a GitHub Actions run conclusion"
  configured_in: ".github/workflows/registry-zot-inventory.yml; scripts/zot-inventory.sh"

error_reporting:
  destination: "GitHub Actions run logs and the workflow conclusion for the CI-side sites; Rule D reports to CI stdout/stderr with a non-zero exit"
  fail_loud: "the refusal prints a named line naming the rejected destination, so refused is distinguishable from unset and from a vendor 5xx. In the CI-side site (scripts/zot-inventory.sh) the refusal exits non-zero. In the deferred host-side sites it MUST NOT exit: the ingest post at soleur-host-bootstrap.sh is immediately followed by soleur-boot-emit (the Vector-independent dark-host detector) and at web-private-nic-guard.sh by the web_nic_guard liveness heartbeat, so an exit there silences a healthy host's beat or a dark host's only signal. There the refusal is skip-and-report with fall-through — and at soleur-host-bootstrap.sh that means ADDING a report line, since that site has no else branch today."

failure_modes:
  - mode: "a credential-forwarding curl site is added, or an existing one edited, without the flags or the pin"
    detection: "Rule D in --changed --base origin/main mode runs with an EMPTY baseline, so any file a PR touches must comply"
    alert_route: "CI failure on the PR that adds it"
  - mode: "the grandfathered population silently grows back"
    detection: "the ratchet fails when the baseline count rises"
    alert_route: "CI failure"
  - mode: "the classifier goes blind and reports a clean repo"
    detection: "an absolute members-checked floor reported with printf >&2 + exit 1 directly, never through a suite helper (ADR-193)"
    alert_route: "CI failure"
  - mode: "the six declarations of the ingest destination drift apart"
    detection: "Rule D's parity assertion compares all six byte for byte"
    alert_route: "CI failure, before anything reaches a host"
  - mode: "a credential reaches a chosen host via the netrc machine line rather than a curl URL"
    detection: "the classifier treats --netrc/--netrc-file as a credential chokepoint and requires the destination feeding the netrc to be validated"
    alert_route: "CI failure"
  - mode: "the memory-backstop suite reddens the pre-commit gate for an environment reason again"
    detection: "the static assertion that the gate's walk origin differs from the test's $$ while its PPid equals it, across all three hook-exec sites"
    alert_route: "CI failure, and the pre-commit gate itself"
  - mode: "a deferred host-script edit ships a fail-stop refusal, darkening a detector"
    detection: "Rule D asserts the refusal branch falls through to the following emit rather than exiting"
    alert_route: "CI failure on that PR"

logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_INVENTORY); GitHub Actions run logs for the lint and the workflow"
  retention: "Better Stack source retention as configured for 2457081; GitHub Actions log retention"

discoverability_test:
  command: "bash scripts/betterstack-query.sh --grep SOLEUR_ZOT_INVENTORY --since 24h --limit 20"
  expected_output: "at least one SOLEUR_ZOT_INVENTORY row carrying enumeration_complete=true from the most recent registry-zot-inventory dispatch, proving the pinned-and-confined invocation still reaches the destination and is stored"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD from Doppler soleur/prd_terraform — the warehouse read has no unauthenticated substitute, and per #7855 an ingest POST would prove only reachability, not storage"
```

---

## Encryption Posture

No persistent store is introduced, moved or re-keyed, and no new cross-component connection is added
— the plan hardens existing HTTPS connections and adds no host-side change in this cycle.

```yaml
at_rest: []
in_transit:
  - connection: "scripts/zot-inventory.sh -> Better Stack Logs ingest (source 2457081)"
    enforced_at: "scripts/zot-inventory.sh — the INGEST_URL equality pin plus the curl --config block carrying the Authorization header"
    tls: "https, TLS 1.2+ as negotiated by the system curl/OpenSSL"
    cert_verification: "on"
    does_not_defend: "a proxy the environment names (which is exactly what --noproxy '*' is added for), a poisoned ~/.curlrc (--disable), a CURL_CA_BUNDLE pointing at an attacker CA, or DNS pointing the pinned host elsewhere. TLS addresses none of these — the finding that reshaped this plan."
    disclosed_as: "knowledge-base/legal/article-30-register.md Processing Activity 8, TOM (g)"
  - connection: "scripts/zot-inventory.sh -> the zot registry (credential carried via --netrc-file)"
    enforced_at: "scripts/zot-inventory.sh — validation of the registry destination before the netrc machine line is written"
    tls: "https when the registry URL is remote; the default is a loopback http origin reached over the CF-Access-gated ingress"
    cert_verification: "on for the remote form"
    does_not_defend: "an env-settable registry URL steering the netrc machine line, which is the gap this work closes; nor an environment-named proxy, which the transport flags close."
    disclosed_as: "not-publicly-claimed"
  - connection: "scripts/betterstack-query.sh -> Better Stack ClickHouse warehouse read"
    enforced_at: "scripts/betterstack-query.sh — the credentialed curl at its query call site, hardened in PR 0"
    tls: "https, TLS 1.2+ as negotiated by the system curl/OpenSSL"
    cert_verification: "on"
    does_not_defend: "an environment-named proxy — the single-user-incident vector, reachable via #7502 — a poisoned ~/.curlrc, or transport-binary substitution, which is out of Rule D's scope and tracked separately."
    disclosed_as: "knowledge-base/legal/article-30-register.md Processing Activity 8, TOM (g)"
```

No `exception` block: nothing runs with `cert_verification: off`, and no store carries a
`plaintext-exception`.

---

## Guard Contract

Two guards. Both extend a mechanism already proven and already wired in this repo.

### Guard 1 — Rule D: credential-forwarding destination and transport confinement

**Property.** No credential-forwarding `curl` in a tracked `*.sh` file can have its destination chosen
by the environment through the URL variable, a proxy variable, or `~/.curlrc`. The guard does **not**
claim the property holds today; it claims the population is enumerated, cannot grow, and can only
shrink. Transport-binary substitution (`CURL_BIN`) and cloud-init YAML call sites are **outside** this
property and named in the deferral issue.

**Assembly.** Keyed on **caller shape**, never on the pinned literal — the quantifier inversion
`lint-supabase-deprecated-endpoints.sh` documents: *a caller whose host has been redirected does not
contain the literal, so a literal-keyed assembly never enumerates the exfil shape it exists to catch.*
Rule D inherits `lint-shell-trace-credential-refusal.py`'s assembly — every tracked `*.sh`, classified
credential-bearing — **widened** to recognise `-u` as well as `--user`, plus `--header @-`,
`--netrc`/`--netrc-file`, `--oauth2-bearer`, `--proxy-user` and `-E`. **Membership is the assertion.**
**Three chokepoints**, all covered: argv, the `--config` file, and the **netrc `machine` line**.
Compliance has two populations: **transport** (`--disable` first, `--noproxy '*'`) over all members,
and **pin** (exact equality against a committed literal) over members whose destination comes from an
env-settable variable. The guard ships with an **honest baseline plus a ratchet**, not a zero-exception
floor: `arm-heartbeats.sh` and `cutover-verify.sh` are real members under `infra/**` this cycle does
not fix, and a classifier narrowed to exclude them would make the guard lie. **That baseline is
Rule-D-scoped, not the lint's existing shared one** — the shared baseline is per-file and
rule-agnostic and already contains all seven Better Stack sites, so inheriting it would make this
guard green over its own target population on the repo-wide run.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `--noproxy '*'` from a compliant member. | RED |
| 2 | Move `--disable` from first position to after `--config`, where it is inert. | RED |
| 3 | Weaken a member's pin to a prefix match. | RED |
| 4 | Neuter the classifier so it matches nothing and reports `0 checked`, exiting 0. | RED — absolute members-checked floor, reported with `printf >&2` + `exit 1` directly (ADR-193) |
| 5 | Add a **second** compliant-looking member after a compliant first, then break only the second. | RED — the guard must not stop at the first member |
| 6 | Add a site carrying `Authorization:` only via a `--config` file, with no pin. | RED — the second chokepoint |
| 7 | Add a site carrying its credential via **`-u`** rather than `--user`. | RED — the exact miss that produced five different reviewer counts |
| 8 | Add a site whose credential reaches an env-derived host via a **netrc `machine` line**, with the URL unvalidated. | RED — the third chokepoint, and the live instance inside `zot-inventory.sh` |
| 9 | Add a new non-compliant file **without** baselining it. | RED — the baseline grandfathers a fixed population, not whatever exists |
| 10 | Add a new non-compliant file **and** baseline it (the smuggling path). | RED via the ratchet — the count may only fall |
| 11 | Change one of the six ingest-URL declarations and leave the other five. | RED — parity is over all six |
| 12 | Write a host-side refusal as `exit 1` above the following emit. | RED — the fall-through requirement, so the fix cannot dark a detector |
| 13 | Point Rule D at the lint's **shared** per-file baseline instead of its own. | RED — all seven target sites are in that 130-entry baseline, so sharing it makes Rule D green over its own population on the repo-wide run. This row is the one that would otherwise ship a vacuous guard. |

**Harness rows:**

| # | Mutation | Expected |
|---|---|---|
| H1 | Replace the exfil-canary assertion body with `true`. | RED — the anti-vacuity floor must catch a suite asserting nothing |
| H2 | Change the oracle from "the refusal message anchor appears" to "exit code is non-zero". | RED — a `set -u` crash also exits non-zero (ADR-193) |
| H3 | **Must-PASS:** a compliant member writing `--noproxy "*"` with double quotes and `--proto '=https'` before the URL. | GREEN — spelling and ordering among non-first arguments is permitted |
| H4 | **Must-PASS:** a compliant member using `--config` with `noproxy = "*"` in the file and `--disable` first on argv, with three non-URL options following `--config`. | GREEN — the constraint is no second URL **operand**, not "nothing after `--config`" |
| H5 | **Must-PASS:** a POSIX `[ … ]` pin in a `#!/bin/sh` member. | GREEN — the dash sites cannot use `[[ … ]]` |

### Guard 2 — every decline reason is classified, and the defect reasons still fail

**Property.** `.claude/hooks/memory-backstop.test.sh` never asserts an adoption the hook was
structurally unable to perform, **and** never converts a real adoption defect into a skip. Every one
of the hook's decline reasons is classified as skip-or-fail; none is unhandled, and none is collapsed
into a blanket "not applied ⇒ skip".

**Assembly.** The set of decline reasons the hook can emit — enumerated **from the hook's source**
(`reason="…"` assignments in `memory-backstop.sh`), never from a list maintained in the test — and the
gate's classification of each. The chokepoint is the enumeration: a reason added to the hook with no
classification in the test must fail the guard, which is what stops the set drifting. Also in the
assembly: the depth harness's own achieved-depth check, since a harness that inserts no hops cannot
exercise any of it. The guard is **static** — it reads both files and spawns nothing, so it costs the
pre-commit gate no processes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a new `reason="…"` to the hook without classifying it in the test. | RED — the enumeration is the chokepoint; an unclassified reason must not default to either arm |
| 2 | Move a defect reason (`adoption_unverified`, `scope_caps_unverified`, `fleet_caps_unverified`, `cap_out_of_range`, `pid_reuse_disambiguated`) from the FAIL class to the SKIP class. | RED — this is the vacuity the draft's blanket-outcome objection was really about |
| 3 | Move a legitimate skip (`disabled`, `concurrent_apply`) into the FAIL class. | RED — the pre-commit gate would then redden on a deliberate opt-out, which is #7886 all over again |
| 4 | Collapse the classification to a single `outcome != "applied" ⇒ skip`. | RED — indistinguishable from mutation 2 for all five defect reasons at once |
| 5 | Neuter the guard's own dispatch so it enumerates zero reasons and exits 0. | RED — absolute floor on reasons-classified, reported with `printf >&2` + `exit 1` directly (ADR-193) |
| 6 | Replace the depth harness's real forks with nested `bash -c`, which adds no hop. | RED — the harness must verify its **achieved** depth, or its floor is satisfiable by a no-op |
| 7 | *(fallback design only)* Seed the gate's walk from `$$` instead of `$BASHPID`, including inside a subshell. | RED — asserted on the origin **PID value** (`origin != $$`, `PPid(origin) == $$`), because "a fork was spawned" is satisfied by the no-op |

**Harness rows:**

| # | Mutation | Expected |
|---|---|---|
| H1 | Change the assertion from "every reason is classified" to "the file mentions each reason somewhere". | RED — a mention is not a classification, and the weaker form is satisfied by a comment |
| H2 | **Must-PASS:** the classification expressed as a case statement rather than an associative array. | GREEN — the contract is the total classification, not one spelling |

The repo-wide `scripts/guard-vacuity-floor.test.sh` already constructs neuter-dispatch mutants for
every tracked `*.test.sh`, so neither guard needs its own copy of that row.

---

## Infrastructure (IaC)

**This cycle changes no `.tf` file and no file whose content hash is a Terraform input.** PR 0, PR 1
and PR 2 touch `.claude/hooks/**`, `scripts/**`, `tests/scripts/**`, `.github/workflows/ci.yml` and
`model.c4` — matching neither `apply-web-platform-infra.yml`'s nor `web-platform-release.yml`'s
`paths:` filter. No infra workflow fires; there is no apply path this cycle. The section is retained
because the **deferred** work has one.

- `web-private-nic-guard.sh` is one of six inputs to
  `terraform_data.private_nic_guard_install.triggers_replace`, and that resource **is** in the
  15-entry `-target=` allowlist (12th). Editing it replaces the resource and re-runs its SSH
  provisioner — a live-host config re-provision over the Cloudflare tunnel bridge, **on web-1 only**.
  Not a host replacement, not a reboot.
- Both files are members of `local.host_script_files`, feeding `local.host_scripts_content_hash` into
  `user_data`. `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`
  on a `for_each` resource, covering **all** hosts, so no host is replaced.
- **Correction to the draft, verified:** the routine push-path apply does **not** run
  `host-image-coherence-preflight.sh` — its only two invocations are in the dispatch-only
  `web_host_create` and `web_host_replace` jobs, and a third mention is text inside an `::error::`
  string. The conclusion (the routine path cannot birth a host) survives via a different mechanism:
  the `host_creates > 0` HALT, which `[ack-destroy]` cannot bypass.
- **The SSH-stage apply is ungraded.** It runs `terraform apply -auto-approve` with its own internal
  plan, so the `host_creates` HALT — which grades the *saved* tfplan from the earlier step — does not
  cover it; and `hcloud_server.web["web-1"]` is dragged into its closure via `connection.host`. The
  `ignore_changes` block is therefore the **sole** guard on the one ungraded auto-approve path that
  reaches the live origin. Any test scenario for that work must read the **SSH stage's own plan**.
- **Both workflows fire on the same merge with no ordering and no shared concurrency group** — the
  apply's push-path job and the release's `deploy` job do not share the `web-1-swap` group. Named so
  the deferred PR schedules around it.
- **The workflow's `paths:` filter is `apps/web-platform/infra/**`, not `*.tf`** despite its own
  header prose, so a `.sh`-only diff does fire it. That is why the deferred work needs a window and
  not merely a small diff.

**Apply path for this cycle: none.** For the deferred work: **(b), existing infra applied by the
merge-triggered workflow**, riding a window opened for another reason, with the `ssh_token_gate`
outcome read explicitly and its `workflow_dispatch` re-run named as the remediation for a skip.

---

## Architecture Decision (ADR/C4)

### ADR

No new ordinal for PR 0, PR 1 or PR 2. One **amendment** is conditional on the #7867 verdict:
**ADR-192:326** currently states source `2734275` *"has never stored one"*; Track D adds today's
verdict, and on `ROUNDTRIP_STORED` that is a correction rather than an addition.

A **new ADR is conditional** on the `NOT_STORED` branch *and* only if the discriminator points at
recreation: that changes a source identity baked into git-data user-data by ADR-198 and would amend
or supersede it. Authored in the same cycle as the decision. Any ordinal is provisional until merge
and re-derived across every `origin/*` ref immediately before merge.

### C4 views

All three model files were read — `model.c4`, `views.c4`, `spec.c4` — not grepped for the feature's
own nouns.

- **External human actors:** none added, removed or re-scoped; no access relationship changes.
- **External systems / vendors:** the only vendor in scope is `betterstack`, already declared as
  `betterstack = system "Better Stack"` with `#external` and already included in **both** the
  `context` and `containers` views. No new vendor, tag or `include` line.
- **Containers / data stores:** `platform.infra.hetzner`, `platform.infra.gitDataStore`,
  `zotRegistry`, `github` — all modeled, none added or removed.
- **Access relationships:** unchanged. The relevant edges already exist — `hetzner -> betterstack`
  (twice), `zotRegistry -> betterstack`, `github -> betterstack` (which already names the literal
  `https://s2457081.eu-fsn-3.betterstackdata.com/` and the `Authorization: Bearer` header this work
  pins), and `gitDataStore -> betterstack`.

**Conclusion: no new C4 element, tag, edge or `view … include` line.** Two **description
corrections**:

1. **PR 2, unconditional, with a writer step (Phase 4 step 6).** The `github -> betterstack` edge
   describes the ingest destination as a literal the CI job posts to; after PR 2 it is pinned and
   transport-confined, and the edge text says so.
2. **Track D, only on `ROUNDTRIP_STORED`.** `model.c4:630`'s `gitDataStore -> betterstack` clause
   *"TARGET state — wired at merge, unobserved until the birth dispatch"* becomes false.
   **A reviewer claim was checked and rejected here:** the `betterstack` **element** description does
   *not* claim the source stores nothing — greps for `never stored` / `storing nothing` / `no row`
   over all three `.c4` files return zero. Only ADR-192:326 and the edge clause carry that claim. A
   reader sent hunting for a string that is not there would either fabricate an edit or drop the step.

After any `.c4` edit, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` run.

---

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** Five findings shaped the plan. (1) The fix issue 7873 suggests is incomplete — a URL
pin leaves the destination environment-choosable via `ALL_PROXY` and `~/.curlrc` — so transport
confinement is part of the fix. (2) The population is ~80 files with 1 compliant, the classifier must
cover `-u` and `--netrc-file`, and the file #7873 names carries a **second** credential path; the work
becomes a rule in the lint that already owns the assembly, with an honest baseline. (3) The draft's
`#7886` fix was a no-op — `$$` survives subshells — and its own guard would have passed it. (4) The
depth perturbation the acceptance criteria rest on is not achievable by nested `bash -c`, which adds
no hop; it needs a real fork and a runtime-derived target. (5) The host-side pin defends against
root-only threats or drift, drift is catchable in CI, and a fail-stop refusal there would dark the
detectors it protects — so that work is deferred with its semantics specified.

### Product/UX Gate

**Tier:** none — no UI surface; no path in Files to Edit or Files to Create matches any UI-surface
glob. Product is recorded as relevant only because `single-user incident` requires a plan-time CPO
acknowledgement of the approach, which is not a UX review.

**Decision:** CPO reviewed — **approved with conditions**, all five applied above: the threshold stays
`single-user incident` with the Art. 30 PA-8 framing and the `pii_scrub_*` mitigant recorded (C1); P2
narrowed to match its qualifiers with `CURL_BIN` explicitly out of scope (C2); a review-by date on the
`NOT_STORED` branch (C3); the vendor escalation opened unconditionally (C4); and the git-data costs
named alongside the explicit no-data-loss statement (C5).

---

## Files to Edit

**PR 0** — `scripts/supabase-advisor-scan.sh`, `scripts/betterstack-query.sh`,
`scripts/betterstack-ingest-probe.sh`, `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`:
`--disable` first, `--noproxy '*'`, plus the xtrace preamble where the baseline requires it.

**PR 1** — CUT. No file under `.claude/hooks/` is edited on this branch.

**PR 2**

- `scripts/zot-inventory.sh` — the xtrace preamble; the ingest pin + transport flags; validation of
  the registry destination that feeds the netrc `machine` line.
- `tests/scripts/test-zot-inventory.sh` — the inverted `mutate_sub` direction; the proxy case.
- `scripts/lint-shell-trace-credential-refusal.py` — Rule D (`check_rule_d`, mirroring the existing
  `check_rule_a`/`b`/`c` shape), the widened classifier, **per-rule baseline granularity**, a
  ~~`--check-highwater` flag~~ (CUT at review — subsumed), and the parity assertion, whose population is DERIVED from the tree rather than the six files listed here (measured at review: **twelve** declaring files across **two** deliberate sources).
- `scripts/lint-shell-trace-credential-refusal.test.sh` — the mutation and harness rows.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `github -> betterstack` edge text.

**Track D, conditional on the verdict**

- `knowledge-base/engineering/architecture/decisions/ADR-192-an-empty-warehouse-read-is-three-states-not-one.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `gitDataStore -> betterstack`
  clause, only on `ROUNDTRIP_STORED`.

**Deferred to a window opened for another reason** — `apps/web-platform/infra/soleur-host-bootstrap.sh`,
`apps/web-platform/infra/web-private-nic-guard.sh`.

## Files to Create

- `scripts/lint-shell-trace-credential-refusal.rule-d.baseline.txt` — Rule D's **own** grandfathered
  population, generated from the Phase 0 census. Distinct from the existing shared
  `…baseline.txt`, which is per-file and rule-agnostic and already contains all seven target sites.
- ~~`scripts/lint-shell-trace-credential-refusal.rule-d.highwater`~~ — **NOT CREATED. Cut at
  review**: strictly subsumed by the repo-wide run (a new offender is absent from the baseline, so
  its violations are reported and the run exits 1). Verified by measurement.
- The static hop-frame guard for `#7886` and its depth harness. Home: `.claude/hooks/*.test.sh`, which
  **is** in `scripts/test-all.sh`'s `SUITE_GLOBS` — so no `run_suite` line is needed and the
  orphan-suite risk does not arise. (`scripts/*.test.sh` is **not** in that array, and `tests/scripts/`
  is absent entirely — a suite placed there needs a hand-written `run_suite` line, as
  `tests/scripts/test-zot-inventory.sh` has.)

---

## Acceptance Criteria

Every criterion is a post-condition that can be false after the work is done. The draft's
slice-boundary and debugging-order criteria were cut — a diff asserting its own shape is not a test.

### PR 0 — the sweep

- **S1.** Each of the four files carries `--disable` as the first argument and `--noproxy '*'` on
  every credentialed `curl`.
- **S2.** `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  passes on PR 0's diff — the xtrace drawdown was done for every touched baselined file.
- **S3.** `tests/scripts/test-git-data-rung2-evidence-capture.sh`,
  `tests/scripts/test-betterstack-ingest-probe.sh` and the `betterstack-query` suites pass — the
  `127.0.0.1` env seam still works, because PR 0 adds flags and **no** pin.

### PR 1 — #7886 — CUT (transferred to PR #7879)

No acceptance criteria: this branch ships nothing for #7886. The work is PR #7879's, which already
carries it in unpushed commit `4115024f5`. The only obligations that survive here are procedural, and
both are discharged during `/work`:

- A comment on #7886 recording the transfer and naming #7879 + the commit.
- A comment asking #7879 to add `Closes #7886` to its body, so the issue closes with the PR that
  actually fixes it rather than being orphaned.

The `#7208` `MAX_WALK_HOPS` note travels with it (see §Collision).

### PR 2 — #7873 site 1 + Rule D

- **B1.** Rule D runs repo-wide and reports a members-checked count ≥ the Phase 0 census. A run
  reporting `0 checked` fails.
- **B2.** In `--changed --base origin/main` mode Rule D uses an **empty** baseline, demonstrated by a
  fixture: a non-compliant file in the changed set fails even though it is in the repo-wide baseline.
- **B3.** Rule D reads a **Rule-D-scoped** baseline, not the lint's shared per-file one. Demonstrated
  by a fixture: a file present in the shared baseline for an A/B/C violation still fails Rule D on the
  repo-wide run. Without this, all seven target sites are exempt and the guard is vacuous.
- ~~**B3b.**~~ **WITHDRAWN at review.** The criterion named a MECHANISM ("mirroring the four in
  `scripts/`") rather than a property, which is how a copied precedent becomes a requirement. The
  property it was reaching for — the deferred population cannot grow silently — is already delivered
  by the baseline. Superseded text: a `.highwater` ratchet exists for Rule D; it fails when
  the count rises and passes when it falls.
- **B4.** Rule D's mutation matrix scores 13/13 RED; harness rows 2/2 RED and 3/3 GREEN.
- **B5.** `scripts/zot-inventory.sh` is **not** in Rule D's baseline — both its credential paths
  comply. (It remains in the *shared* baseline for its xtrace history until that is separately drawn
  down; the two baselines are now distinct, which is the point of B3.)
- **B6.** `inv-exfil` runs the **unmutated** script with the canary URL and asserts refusal: the canary
  receives zero requests **and** the refusal message anchor appears — not a bare non-zero exit, and
  not an absence assertion alone (which would be vacuously true if the destination could never be
  accepted). The old pass-message is gone:
  `grep -c 'the exfil mutant reaches the canary' tests/scripts/test-zot-inventory.sh` is 0. **Scoped
  to that file deliberately** — this plan quotes the literal, so a repo-wide grep would match the
  plan itself and the criterion would be unsatisfiable by construction.
- **B7.** The proxy case **fails against the pre-fix script**, demonstrated. If the `.curlrc` case
  cannot be made to fail pre-fix, it is dropped with a stated reason rather than shipped.
- **B8.** `bash tests/scripts/test-zot-inventory.sh` passes and its case count is ≥ its pre-change
  count — the real listener is retained and no assertion was traded away. The suite's own `total >= 90`
  floor still holds.
- **B9.** `bash scripts/lint-orphan-test-suites.sh` passes. (The **linter** — not its companion suite
  `scripts/lint-orphan-test-suites.test.sh`, which runs against a sandbox copy and *synthesizes*
  registration lines for up to 25 inherited orphans, so it would be green on the exact defect.)
- **B10.** The parity assertion fails when any one of the six ingest-URL declarations is changed alone,
  including by a trailing space.
- **B11.** `model.c4`'s `github -> betterstack` edge text names the pin, and
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **B12.** Two tracking issues exist: the deferral census (files, `curl` lines, compliant count, the
  env-settable/customer-shipped/host-baked splits, the seven cloud-init YAML siblings, the four Resend
  host scripts, and the `CURL_BIN` seam with an explicit upgrade trigger) and the web-2 unpinned-script
  gap.

### Track D — #7867

- **D1.** The vendor escalation was opened **before** the probe ran, unconditional on verdict, and
  carries the marker prefix the probe writes (`SOLEUR_BS_ROUNDTRIP_7855_`) plus the timestamps of both
  the 2026-09-06 run and this one, so the vendor has a specific reproducible round trip to look at.
- **D2.** The probe's full stdout and exit code are recorded verbatim on #7867. **No criterion asserts
  which verdict.**
- **D3.** The corroborating warehouse reads were pulled with `scripts/betterstack-query.sh` and are
  quoted in the comment, along with the verdict→action table.
- **D4.** #7867 was **not closed by this session** on any branch — closure is left to the sweeper, so
  `closed_precheck` cannot reopen an agent-authored close.
- **D5.** If the exit code is outside `{0,1,2,3}` or stdout carries no `SOLEUR_BETTERSTACK_ROUNDTRIP`
  line, it was recorded as "the probe did not run", not as a verdict.
- **D6.** On exit 1: the throwaway-source discriminator was run and its result recorded; the mechanism
  choice was routed to `cto` with that result; a review-by date is on the issue.
- **D7.** No write to source `2457081` occurred, asserted by confirming no row carrying the
  `SOLEUR_BS_ROUNDTRIP_7855_` marker prefix appears in the control table.
- **D8.** If a sweeper comment for the same window already existed, no second contradicting verdict was
  posted.

---

## Test Scenarios

1. **Depth sweep.** Run the suite across the depth range spanning the boundary. Before: `PASSED 54`
   below it, `FAILED 1 (passed 46)` at it, `PASSED 41 [live: yes, e2e SKIPPED]` beyond. After: no
   depth reports `FAILED`.
2. **The no-op mutants.** (a) Wrap the gate's walk in a subshell but keep `_p=$$` — the suite must
   still fail at the boundary **and** Guard 2 must redden. (b) Build the depth harness from nested
   `bash -c` — its achieved-depth check must fail rather than reporting a green suite. These two
   scenarios encode the draft's own defects.
3. **Proxy defeat.** With `ALL_PROXY` pointed at a local recorder, run `zot-inventory.sh`. Before: the
   recorder receives the request **carrying the bearer token**. After: nothing.
4. **Second URL operand.** Append a URL operand after `--config <file>`; the second destination
   receives nothing. (Three non-URL options already follow `--config` and must stay legal.)
5. **Exfil mutant.** `inv-exfil` runs the unmutated script with the canary URL; assert refusal, zero
   canary requests, and the message anchor.
6. **Prefix bypass.** `https://s2457081.eu-fsn-3.betterstackdata.com@evil.example/` must be refused.
7. **Short-form and netrc credentials.** Fixtures carrying `-u user:pass` and a `--netrc-file` whose
   `machine` line derives from an env-settable URL must both be classified and checked.
8. **Vacuity.** Neuter each guard's dispatch; each exits non-zero with its floor message.
9. **Ratchet.** Add a non-compliant file without baselining (RED); with baselining (RED via ratchet);
   remove a baselined file after fixing it (GREEN, count falls).
10. **Six-declaration parity.** Change each of the six ingest-URL declarations alone; the lint reddens
    each time.
11. **Fall-through.** A host-shaped fixture whose refusal branch `exit`s above the following emit must
    redden; one that logs and falls through must pass.
12. **Probe branch coverage.** Walk the returned verdict end to end, including the exit-78 path and the
    "sweeper got there first" path.

---

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| Rule D's classifier is narrower than its property — the defect this plan found in its own draft, and the reason five reviewers returned five different counts. | Phase 0 regenerates the census **from the classifier**; B1's floor comes from it; mutation rows 7 and 8 target the `-u` and netrc misses specifically; the `*.sh` and `CURL_BIN` exclusions are stated in the property. |
| **Rule D inherits the lint's shared baseline and ships vacuous** — the deepen pass measured this: the shared baseline is per-file and rule-agnostic, holds 130 entries, and contains all seven target sites. | Rule D gets its own baseline (AC B3) and mutation row 13 drives the guard RED if it is pointed at the shared one. `--changed` mode was never affected. |
| The baseline becomes a parking lot. | The ratchet permits the count only to fall (AC B3b); the deferral issue carries the census. |
| Touching a baselined file reddens CI on the xtrace lint before Rule D is reached. | Phase 0 step 3 enumerates the affected files; the drawdown is explicit work in Phases 1 and 4; AC S2 asserts it. |
| The depth harness silently tests nothing. | A1 requires it to verify its achieved depth; Guard 2 mutation row 6 and Test Scenario 2(b) drive it RED when built from nested `bash -c`. |
| `inv-exfil` becomes vacuous once the destination can never be accepted. | B6 requires the refusal **message anchor**, not only the absence of canary requests. |
| The `mutate_sub` literal stops matching after the pin lands. | Phase 4 step 4 keeps the pin's comparand the inline literal at `:91`; B6 fails loudly if the mutation does not land. |
| The `.curlrc` case cannot be demonstrated failing pre-fix (finding 3 is doc-derived). | B7 requires demonstration and permits dropping the case with a stated reason. |
| Landing Rule D as advisory only. | `ci.yml`'s `lint-bot-statuses` job is advisory (absent from `scripts/required-checks.txt`); the blocking arm is the existing `scripts/test-all.sh` registration under the required `test` job. |
| Deferring sites 2/3 leaves two known-vulnerable host scripts, and web-2 will not receive the fix even when they land. | Both are root-only-reachable and stay baselined; the drift half is enforced CI-side; the web-2 gap has its own tracking issue rather than being covered by a green guard. |
| A deferred host edit ships a fail-stop refusal and darks a detector. | The semantics are specified here, mutation row 12 enforces fall-through, Test Scenario 11 exercises it. |
| **PR #7879 lands the same harness fix first, or lands it differently.** It is OPEN, WIP, on the same file, with the same mechanism, and it does **not** close #7886. | Phase 0 step 5 settles PR 1's scope against #7879's actual state before a line is written, and this plan adopts #7879's mechanism so the two converge rather than conflict. |
| **The new `#7886` guard suite trips `guard-vacuity-floor.test.sh`'s `MAX_DEFERRED=47` shrink-only ratchet.** `.claude/hooks/` is in that guard's `DEFERRED_DIRS` and its population is `git ls-files '*.test.sh'`. | Phase 0 step 6 decides promotion up front; AC A8 asserts it. Precedent exists (`monitor-supersede-guard.test.sh`, `incident-sandbox-coverage.test.sh`). |
| #7208 lands a conflicting change. | PR 1 touches only the test; the #7208 comment records what this plan settled. |
| The #7867 probe returns `UNKNOWN`, or does not run at all (exit 78). | The diagnosis order is fixed and the credential rung pre-cleared; the fifth branch covers not-a-verdict; `DARK` runs once, not in a loop. |
| The sweeper posts a verdict for the same window first. | Phase 3 step 2 re-reads issue state; D8 asserts no contradicting second verdict. |
| "Wait for the vendor" becomes indefinite. | The escalation opens unconditionally, the discriminator collapses three of four options for two API calls, and the `NOT_STORED` branch carries a review-by date. |

---

## References

- Issues: [#7867](https://github.com/jikig-ai/soleur/issues/7867), [#7873](https://github.com/jikig-ai/soleur/issues/7873), [#7886](https://github.com/jikig-ai/soleur/issues/7886); context [#7855](https://github.com/jikig-ai/soleur/issues/7855), [#7811](https://github.com/jikig-ai/soleur/issues/7811), [#7208](https://github.com/jikig-ai/soleur/issues/7208), [#7409](https://github.com/jikig-ai/soleur/issues/7409), [#7502](https://github.com/jikig-ai/soleur/issues/7502), [#7776](https://github.com/jikig-ai/soleur/issues/7776), [#7807](https://github.com/jikig-ai/soleur/issues/7807), PR [#7856](https://github.com/jikig-ai/soleur/pull/7856).
- ADRs: `ADR-172`, `ADR-180`, `ADR-192`, `ADR-193`, `ADR-198` (its `**Mint** — POST /api/v2/sources` list item, not a heading), `ADR-202` (the carried self-refusal — the xtrace/credential rule).
- Guard templates: `scripts/lint-shell-trace-credential-refusal.py` (the lint Rule D extends) and `scripts/lint-supabase-deprecated-endpoints.sh` (the quantifier inversion).
- Transport idiom: `scripts/supabase-logs-query.sh`, header "HOST PIN — NO ENV OVERRIDE".
- Legal: `knowledge-base/legal/article-30-register.md` PA-8 TOM (g); `docs/legal/data-protection-disclosure.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
- `man curl`: `-K/--config`, `-q/--disable`, `--noproxy`, `--proxy`, `-:/--next`, `--proto`, `--netrc-file`, ENVIRONMENT.
