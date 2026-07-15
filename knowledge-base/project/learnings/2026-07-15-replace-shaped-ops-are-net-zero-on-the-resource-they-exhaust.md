---
date: 2026-07-15
module: web-platform-infra
problem_type: logic_error
component: terraform
severity: high
root_cause: wrong_mental_model
symptoms:
  - "Issue asked for a `free_slots == 0` preflight that would have failed every recreate"
  - "Hetzner 5/5 server cap blamed for an incident that threw a different error code"
  - "`expenses.md` billing `active` for a host that has never existed"
tags: [hetzner, terraform, quota, preflight, premise-validation, guard-design, phantom-resource]
issue: 6453
pr: 6457
synced_to: [brainstorm]
---

# Learning: a `-replace`-shaped op is net-zero on the resource it appears to exhaust

## Problem

Issue #6453 reported the Hetzner account at its 5-server cap and argued:

> Every recreate-shaped remediation is a **destroy-then-create**. At a hard cap with
> zero headroom … a destroy that cannot re-place leaves the fleet **short a host**
> with no rollback.

It asked for a cap-headroom preflight that fails a recreate when free slots == 0.

**The premise is false**, and the falseness is not obvious — it survived four of six
participants (the issue author, the CPO, the platform-strategist, and the brainstorm
orchestrator, who wrote the wrong decision into the doc before the CTO caught it).

## Solution

**Trace whether the operation actually CONSUMES the resource at the moment it runs.**

A terraform `-replace` **destroys first — freeing its own slot — then creates.** It is
**net-zero** on the server count:

| step | servers |
|---|---|
| before | 5/5 |
| destroy | 4/5 |
| create | 5/5 |

The cap **never engages on a recreate.** A `free_slots == 0` preflight would have
failed every recreate, for no reason, forever. The cap only blocks *additive* creates
(a scratch probe host, git-data's birth, web-3) — and those fail **safely**, because
nothing was destroyed first.

So the guard belongs on the **additive** path, if anywhere — and there it is nearly
worthless, since an additive create already fails cleanly with `resource_limit_exceeded`
and zero blast radius.

## Key Insight

**Before scoping a guard for "resource X is exhausted blocks operation Y", trace
whether Y consumes X at the moment it runs.** A replace/swap/rotate-shaped operation
frees its own unit before taking one. "No headroom" is intuitively alarming and
almost always mis-aimed at the replace path.

Corollary — **check which error code the cited incident actually threw**:

| code | scope | fixed by | bit us in |
|---|---|---|---|
| `resource_limit_exceeded` | account-wide, region-blind | vendor Console form (`GET /v1/limits` → **404**; no API self-serve) | #6416 (no slot for a probe host) |
| `resource_unavailable` | **per-DC stock**, time-varying | not pinning a DC | **#6393** (web-2 wedge) |

#6393 threw the **second**. The requested cap preflight would have returned green
while the apply destroyed web-2 — it would close the issue without touching the bug.
Evidence: `bug-fixes/2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md:12`
records `error during placement (resource_unavailable)`.

**And slots were never what blocked blue-green anyway.** `create_before_destroy`
appears nowhere in `apps/web-platform/infra/*.tf`, and the singleton hosts have
hard-coded names (`git-data.tf:119`, `inngest-host.tf:182`, `zot-registry.tf:227`)
plus pinned private IPs (`network.tf:51` → `10.0.1.20`). A create-before-destroy
collides on **both** before it ever reaches the cap. Blue-green needs an IaC
redesign, not a quota change (filed: #6459).

## Secondary insights

### An issue's own table can refute its prose

#6453 asserted "all five slots are load-bearing" while its own table listed
`hermes-agent`'s role as `—`. **The blank cell was the finding:** zero IaC references,
no private-net attachment, no `expenses.md` row, 49 days running. A premise-probe must
read an issue's *tables and structured data* against the IaC, not just its prose — a
placeholder cell in an otherwise-complete table is a high-signal canary that the
author didn't know either.

### The phantom-resource class (filed: #6460)

`hcloud_server.git_data` is declared unconditionally (`git-data.tf:118` — no
`count`/`for_each`/`removed`) but excluded from every apply allow-list, so
`soleur-git-data` has **never existed**. Yet a whole corpus reasons about it:

- `expenses.md:14-16` bill it **`active`** (~$5.12/mo phantom)
- **ADR-103** calls it *"the fleet's most irreplaceable data store"*
- **ADR-115** raises a normative `luksOpen` blocker about it
- **PR #6242** shipped a `git-data-host-replace` path (`apply-web-platform-infra.yml:2079-2179`)
  that is a scoped `-replace` and therefore **has never been runnable** — ~100 lines
  plus `tests/scripts/lib/git-data-host-replace-gate.sh` guarding nothing

`terraform-target-parity.test.ts` asserts git-data **is excluded**; nothing asserts it
therefore **exists**. This is `hr-verify-repo-capability-claim-before-assert` failing
at ADR scale.

### Probe leader hypotheses about live infra — the orchestrator holds the credentials

The CTO agent explicitly flagged it had **no hcloud token** and could verify no live
fact. Its one unverifiable hypothesis — a live GDPR Art. 17 erasure bug, since
`removeGitDataRepo` is deliberately not flag-gated (`git-data-replication.ts:141`) and
would SSH to a phantom `10.0.1.20` — was **refuted in 5 seconds**:
`GIT_REMOVE_SSH_PRIVATE_KEY` is absent from Doppler `prd` *and* `dev`, and the code
early-returns (`git-data-replication.ts:151-152`).

Subagents reason **without credentials**; the orchestrator must probe their live-state
hypotheses before those hypotheses become artifacts. The CTO labelling its own
uncertainty is the behaviour to reward — it is what made the hypothesis cheap to kill.

## Session Errors

1. **`hcloud server list -o columns=name,server_type,...` → `invalid value for output
   option columns: server_type`.** Recovery: the column key is `type`, not
   `server_type`. **Prevention:** one-off; run bare `hcloud server list` first rather
   than guessing column keys.
2. **`hcloud` invoked with no token → `hcloud: no active context or token`.** Recovery:
   `export HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)`.
   **Prevention:** one-off/expected — the token lives in Doppler `prd_terraform`, not
   the shell. Recorded here so the next session skips the discovery step.
3. **Read `apps/web-platform/server/lib/git-data-replication.ts` (guessed path); the
   actual path is `apps/web-platform/server/git-data-replication.ts`,** so the first
   read returned empty. **Prevention:** one-off; `git ls-files | grep -i <name>` before
   `sed`/`grep` on a guessed path.
4. **The orchestrator wrote the cap-preflight decision into the brainstorm doc as
   correct, then had to reverse it when the CTO's assessment landed.** Recovery:
   rewrote the Why table and Decisions 3-5. **Prevention:** RECURRING — routed to
   `brainstorm/SKILL.md` Phase 1.0.5. When a brainstorm's core ask is a guard against
   resource exhaustion, trace the consumption model *before* writing decisions, and
   prefer waiting for the engineering leader on mechanism questions.
5. **`WebFetch` of `https://docs.hetzner.cloud/reference/cloud` returned navigation
   chrome only** (SPA shell), no endpoint content. Recovery: WebSearch plus a direct
   `curl` probe of `/v1/limits` (→ 404). **Prevention:** one-off; for SPA-rendered
   vendor docs, probe the API directly — a 404 is stronger evidence than a doc page.
6. **A `cd` into the worktree was reset mid-command ("Shell cwd was reset"),** producing
   an empty grep that briefly looked like a real absence. Recovery: re-ran against
   `main` from the repo root. **Prevention:** one-off; known bare-repo/worktree CWD
   class — use absolute paths or `git grep <pattern> main --` rather than `cd`.

## See also

- `bug-fixes/2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md` — the
  #6393 incident this learning re-reads. That file records the cross-DC footgun; this
  one records why the *guard proposed in response* was aimed at the wrong counter.
- `best-practices/2026-06-18-capacity-monitor-threshold-from-live-value-not-plan-target.md`
  — thresholds must assert the live value, not the plan target.
- #6459 (blue-green via add/drain/remove — needs an ADR), #6460 (fleet-capacity-audit).
</content>
