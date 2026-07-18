---
synced_to: [brainstorm]
---

# Learning: an issue's archaeology ("probably a workaround that became permanent") is a claim to verify against the PR that made the state

## Problem

`/soleur:go 6538` received a `type/bug` issue with an unusually strong evidence
base: live Hetzner and Better Stack probes, exact dispatch run IDs, quoted
`server.tf` lines. It reported three defects in the warm-standby host
`soleur-web-2` and asked for a decision between two remediation options.

Under a section headed **"Why it is in fsn1 (probable)"** it concluded:

> web-2 was almost certainly placed in fsn1 as a stock workaround on 2026-07-13.
> The workaround became permanent.

That sentence is the load-bearing premise of the whole issue — it is what makes
"move web-2 back to hel1" read as *undoing an accident* rather than *reverting a
decision*. It was false.

The PR that moved web-2 is **#6393, merged 2026-07-13 — three days before #6538
was filed**. Its title states the intent verbatim:

> fix(infra): relocate warm-standby web-2 hel1→fsn1 (**cross-DC HA**) — unwedge apply-on-merge

and the rationale is recorded in *two* files. `variables.tf`:

> web-2 sits in a DIFFERENT DC from web-1's hel1 (DC-failure resilience). A same-DC
> warm standby gives no protection against a hel1 outage, and a `-replace` recreate
> DURING a hel1 capacity shortage destroyed web-2 then could not re-place it, wedging
> every apply-on-merge on `resource_unavailable`

fsn1 was not where web-2 ended up by accident. It is where it was deliberately
sent, to fix a repo-wide deploy blocker. The issue's preferred option would have
reverted that fix three days later.

## Root cause

**Speculative-causality language is a trigger token, and the brainstorm skill had
no probe for it.** Phase 1.0.5 carries ~20 premise probes — for stale deferrals,
cited flag symbols, ADR mechanisms, PR merge state, register citations, data-source
granularity. Every one of them checks *whether a claim about current state is still
true*. None checks **a claim about why current state exists**.

That is a distinct failure mode with an asymmetric cost: the deliberate-decision
case and the accident case have **opposite fixes**. Getting it wrong does not
produce a suboptimal plan; it produces a plan that undoes working code.

The issue author was not careless — they measured everything they thought to
measure. Archaeology simply doesn't *feel* like a claim. It feels like context.

## Solution

Before accepting an issue's explanation of how the current state arose, ask the
PR that made it:

```bash
# The state is in a file — ask the line's history directly.
git log -1 --format='%H %ad %s' --date=iso -L <start>,<end>:<path>

# Or find the PR by the state it produced.
gh pr list --state all --search "<the thing that moved>" --json number,title,mergedAt
gh pr view <N> --json title,mergedAt,body
```

Two cheap reads decided this session:

1. `git log -L 115,123:apps/web-platform/infra/server.tf` → PR #6393, 2026-07-13,
   "cross-DC HA" in the title.
2. `gh issue view 6538 --json createdAt` → 2026-07-16.

Merged **before** the issue was filed ⇒ the issue is describing a decision, not an
accident.

**Trigger tokens:** "probably", "almost certainly", "(probable)", "became
permanent", "the workaround stuck", "at some point someone", "presumably", "must
have been". When the issue hedges about causality, the hedge is the tell — the
author is reconstructing, not reporting.

## Key insight

**A PR title is the cheapest intent oracle in the repo, and it is almost never
consulted.** #6393's title contained the exact refutation ("cross-DC HA") in four
words. The issue quoted `server.tf` line-by-line but never read the title of the
commit that wrote those lines.

Corollary: `git blame`/`git log -L` answers "why is this like this?" *better than
the issue reporting it*, because the person who made the state wrote down their
reason at the moment they had it.

## Supporting findings from the same session

These are separate probes; each independently changed the outcome.

### 1. Quoting a comment's first line is not reading the comment

#6538 quoted `server.tf` as evidence the placement group was intended for web-2:

> Spread across distinct physical hosts within the EU location (HA)

The four lines immediately below it say the opposite:

> A Hetzner placement group is LOCATION-scoped: a host in a different DC than web-1
> cannot join web_spread, so it gets null. **That is not a downgrade** — a cross-DC
> host is already spread from web-1 at the DC level (stronger HA than same-DC spread)

**Probe:** when an issue cites a comment as evidence of *intent*, read the whole
comment block. A comment's first line is a topic sentence; its rationale lives
below. This is the same shape as `cq-cite-content-anchor-not-line-number` — a
coordinate citation carries no claim about what surrounds it.

### 2. `ignore_changes` can make a config expression dead code

`server.tf` computes membership with a ternary:

```hcl
placement_group_id = each.value.location == var.web_hosts["web-1"].location ? hcloud_placement_group.web_spread.id : null
```

…and then, on the same resource:

```hcl
lifecycle {
  ignore_changes = [user_data, ssh_keys, image, placement_group_id]
}
```

`placement_group_id` is in `ignore_changes`, so Terraform never reconciles it on an
existing server — it is **create-time only**. Live proof: `soleur-web-spread` has
`servers=[]`, and **web-1 — for whom the ternary is trivially true — is not in it
either**.

So #6538's third defect ("web-2 is outside the HA placement group") was misframed:
nobody is in it, and nobody can join without a recreate. Both the issue *and* the
elaborate comment reasoned about a mechanism that cannot engage — the same class as
[2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md](../2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md).

**Probe:** before reasoning about what a Terraform attribute expression achieves,
grep the resource's `lifecycle` / `ignore_changes` block. An attribute listed there
is documentation, not behaviour.

### 3. "Why can't we reuse the same specs?" hid a supply constraint

Asked mid-session. The instinct is reasonable and the answer is not what it looks
like: **web-1 and web-2 are both `cx33` already.** Spec parity was never the
question. Hetzner simply will not *sell* a cx33 in fsn1 — it is orderable in exactly
one datacenter on Earth (`hel1-dc2`), and was orderable in **zero** for ~3h on
2026-07-15.

A running server is unaffected by stock; **stock binds only at CREATE time**. That
is why web-2 runs happily as a cx33 in a DC that cannot produce one.

**Probe:** when asked "why not just use the same X", check whether X is
*purchasable* in the target context before treating it as a design choice.
`.supported` != `.available` — the trap already documented in
`tests/scripts/lib/stock-preflight-gate.sh`.

### 4. Naming a load-bearing question does not make it the load-bearing one

#6538 declared: *"Decide whether web-2's `workspaces` volume is disposable … This is
the load-bearing question and it is not answered here."*

It was moot. A Hetzner volume force-replaces on a **location** change; the option
that keeps fsn1 never moves the volume, so the question only exists under the option
the brainstorm rejected. (It was also already answered: the volume is empty, and
ADR-068 §1 makes worktrees host-local derived state with GitHub as the durable
rehydration source.)

**Probe:** re-derive which question is load-bearing from the option set *you* end up
with, not from the issue's framing. An author's "load-bearing question" is
load-bearing for *their* preferred option.

### 5. Class name: fleet-sku-orderability drift

IaC pinned to SKUs the vendor stopped selling in our region, discovered only at
apply time. **Two live instances found in one session:**

| host | pinned type | orderable in its pinned location? |
|---|---|---|
| `soleur-web-2` | `cx33` @ fsn1 | No — `hel1-dc2` only |
| `soleur-git-data` | `cax11` | No — entire ARM line is 0 of 3 EU DCs (#6570) |

The second is the root blocker of ADR-068 §(c) → active-active, and explains why
that host has never existed. Audit shape fed to #6460.

## Session Errors

**Hetzner `/v1/servers` jq path returned null for every server** — read
`.datacenter.location.name`; that response shape carries `datacenter: null` with
`location` at the top level, so all five hosts reported `loc=null`. Briefly looked
like an API/token problem rather than a path bug. — Recovery: dumped the raw object
keys, re-queried `.location.name`. — **Prevention:** on `/v1/servers`, location is
`.location.name`; verify a field path against `| keys` before concluding the data is
missing. One-off.

**`sort -t'€'` failed** with `separator must be exactly one character long: '€'` —
the euro sign is multibyte, so it cannot be a `sort` field separator. — Recovery:
emitted the price as a leading numeric TSV field and used `sort -n`, formatting the
currency only at print time. — **Prevention:** never use a currency symbol as a
delimiter; sort on raw numerics and format last. One-off.

**CFO subagent could not read `HCLOUD_TOKEN`** (`hcloud: no active context or
token`) and therefore could not verify whether `soleur-grok-dogfood` was live. It
**correctly flagged the gap rather than guessing** — the desired behaviour. The
orchestrator then verified live: grok-dogfood *is* running (created 2026-07-16) and
occupies 1 of 5 capped slots, while `expenses.md` books it as
`approved-not-billing` / "Not born". — Recovery: orchestrator self-pulled the fact
and recorded it in the brainstorm. — **Prevention:** subagents do not inherit
Doppler-injected env, so they cannot self-pull vendor state. The orchestrator must
thread already-verified live facts into leader prompts (the brainstorm skill's
existing "gather verifiable facts … BEFORE spawning leaders and thread these facts
into every Task Prompt" rule extends to *live infra state*, not just prospect
facts). Recurring.

## Outcome

Decision: **retire web-2** — unanimous across CTO, platform-strategist, CPO and CFO;
CLO legally indifferent (fsn1/hel1/nbg1 are all EU, so residency does not
differentiate). The deciding argument was not cost but topology: `placement_group_id`
is create-time only, so a host born in fsn1 can never join `web_spread`, and the
operator's active-active target requires hosts *born* in hel1 inside the group.
web-2 must be destroyed and reborn regardless — so paying +€27/mo (cpx32, the
cheapest 8GB fsn1 will sell) to make the wrong-shaped host recreatable buys nothing.

Spawned: #6570 (git-data `cax11` unorderable — root blocker of active-active),
#6571 (`web_spread` empty and unreachable-by-design).

## Related

- [2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md](../2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md) — a claim a green signal appeared to support; same "config describes a mechanism that cannot engage" shape
- [2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md](../2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md) — `resource_unavailable` (per-DC stock) vs `resource_limit_exceeded` (account cap); the #6393 incident this session's state descends from
- [2026-07-06-issue-claims-bug-is-external-verify-with-literal-grep-before-routing.md](2026-07-06-issue-claims-bug-is-external-verify-with-literal-grep-before-routing.md) — sibling: an issue's confident claim about *where* the bug lives is also a claim to verify
- [2026-05-18-premise-validation-and-multi-clause-predicate-reading.md](../2026-05-18-premise-validation-and-multi-clause-predicate-reading.md) — the original premise-validation learning

Issues: #6538, #6463, #6393, #6453, #6457, #6459, #6460, #6570, #6571
