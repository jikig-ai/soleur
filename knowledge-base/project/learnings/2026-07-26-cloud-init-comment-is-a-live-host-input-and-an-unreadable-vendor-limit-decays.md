---
date: 2026-07-26
issue: 6966
pr: 6967
tags: [terraform, hetzner, cloud-init, user_data, vendor-limits, drift, infra]
category: infra
---

# A cloud-init comment is a live-host input; and a vendor limit with no API path decays silently

Two findings from the #6966 web-2 repin (`cx23` → `cpx22`). Unrelated mechanically, but they share
a shape: **a fact nobody could mechanically check went stale, and the staleness was about to cost a
host.**

## 1. Editing a comment in a cloud-init template can destroy a host you cannot recreate

### What happened

The PR corrected a factual claim ("whichever of cax11 / cx23 has Hetzner stock") that the live probe
had falsified. The same false claim appeared in two places, so both were corrected:

- `apps/web-platform/infra/zot-registry.tf` — a `.tf` comment. Harmless.
- `apps/web-platform/infra/cloud-init-registry.yml` — **not harmless.**

`hcloud_server.registry` sets `user_data = base64gzip(templatefile("cloud-init-registry.yml", …))`,
and the resource **deliberately carries no `lifecycle.ignore_changes = [user_data]`** — the rationale
is written at the resource: omitting it "preserves a clean replace-to-reprovision path". So the
template's *entire byte content*, comments included, is an input to a `ForceNew` attribute. A pure
comment edit re-renders `user_data` and plans `delete, create` on a live host.

That host runs `cx23`, which as of 2026-07-26 is orderable in **0 of 3 EU DCs**. Destroy would
succeed; create would fail `resource_unavailable`; the registry would be stranded — the #6393 shape
the stock preflight exists to prevent.

### The generalisation

**Before editing any `cloud-init-*.yml`, read the consuming resource's `lifecycle` block.**

- No `ignore_changes = [user_data]` → the file is a live-host input. Put prose in the `.tf` instead.
- Has `ignore_changes = [user_data]` → comment edits are inert **and so are real edits** on an
  already-booted host (they reach only fresh creates). `hcloud_server.web` is this case, which is
  exactly why web-1 can never receive a cloud-init change without a rebirth.

The two cases look identical in a diff and have opposite consequences. Neither `tsc`, nor
`terraform validate`, nor any test suite distinguishes them — only `terraform plan` does, and only
if you read the resource-level actions rather than the `Plan:` summary.

### Addendum (2026-07-27, #6981): the SECOND reason a comment is not free — it costs bytes

`ignore_changes = [user_data]` makes comment edits inert on an already-booted host, so by the rule
above `hcloud_server.web` looks like the safe case. It is not fully safe: `user_data` is
`base64gzip(templatefile(…))` against Hetzner's **32,768 B cap**, with a 23,700 B sub-cap budget
guarded by `plugins/soleur/test/cloud-init-user-data-size.test.ts`. Prose is payload.

In #6981 a 33-line explanatory comment took the rendered `user_data` from 23,016 B to **23,852 B** —
over budget. Nothing local caught it: the infra suites (72/72) and the PR's own new assertions
(104/0) do not model the render. Only `scripts/test-all.sh` did.

**And the obvious hand-check is wrong.** Measuring the source directly reads ~400 B LOW, because the
file is a terraform *template* and the test renders it with real variable values first:

```
gzip -9 -c cloud-init.yml | base64 -w0 | wc -c   → 23,444   (under budget — WRONG)
bun test cloud-init-user-data-size.test.ts       → 23,852   (over budget — the real number)
```

Acting on the first number would have "fixed" the overrun on a value that was never the measurement.

**So, before adding prose to any `cloud-init-*.yml`, check both axes:**

1. **Does the consuming resource carry `ignore_changes = [user_data]`?** No → the comment can replace
   a live host (§1 above).
2. **Is there byte headroom?** Run the size test, not a hand-rolled `gzip`. If headroom is thin, put
   the rationale in the ADR / issue / post-mortem — those have no byte budget — and leave a pointer.

Full write-up: [[2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it]].

### Attribution matters, and it is cheap

The registry planned `delete, create` / `replace_because_cannot_update` **even with a pristine
template** — driven by the new `random_password.registry_luks` + `doppler_secret.registry_luks_key`
that `user_data` references (the #6929 LUKS-recut vehicle shipped unfired). So the comment edit was
a *redundant contributor* to an existing diff, not the cause.

Establish that before concluding either "my change is dangerous" or "my change is fine":
`git checkout -- <file>` (never `git stash` in a worktree — `hr-never-git-stash-in-worktrees`), then
re-plan `-target` on the single resource. Two minutes, and it separates panic from a real finding.

## 2. A vendor limit with no API endpoint is a fact with a decay date, not a constant

### What happened

Every artifact in the session — the task framing, the issue body, the first draft of the plan —
stated a **5-server Hetzner cap with one free slot**. The live cap is **10, with 4 running**: six
free slots. The raise had been requested and granted around 2026-07-15 (the cap-headroom
workstream's "long pole"), but **the granted value was never written back into the repo**.

The reason it survived unchallenged is mechanical: **`GET /v1/limits` returns 404 on this account.**
There is no API path to the cap. No gate, no audit, no test could read it, so nothing in the system
was capable of contradicting a wrong number. It propagated into a brainstorm, a plan, an issue body,
and an expense-ledger row, each citation making it look better-sourced.

Two decisions were nearly made on it:

1. Drafting a Console request for a raise that already existed.
2. Weighing the retirement of `soleur-grok-dogfood` "to free a slot" — an **irreversible** loss,
   since its `cx33` is orderable nowhere and the cheapest orderable 8 GB replacement is `cpx32` at
   4.2× the price. Traded for a slot that was already free six times over.

It was caught only because the operator opened the Console and posted a screenshot.

### The generalisation

When a constraint has **no machine-readable source**, it must be recorded as an *observation* with
provenance and an expiry, never as a bare number in prose:

```markdown
| Hetzner Cloud servers | 4 / 10 | 2026-07-26 | … <!-- estimate verify_by=2026-10-26 owner=coo
source="Hetzner Cloud limits page (no API endpoint)" --> |
```

The existing `verify_by` marker convention already does this for *prices*; it works just as well for
*limits*, and the `expenses-verify-by-check.sh` gate then makes the decay loud instead of silent.

**The diagnostic question:** for any number a plan leans on, ask *"what would contradict this?"* If
the answer is "nothing in the repo can read it," it is an observation with a half-life — and the
older it is, the more confidently everything downstream will cite it.

### Corollary — check reversibility before spending a resource to buy headroom

"Retire X to free a slot" is only cheap if X can come back. Three of four running hosts (web-1
`cx33`, grok-dogfood `cx33`, registry `cx23`) are on types Hetzner no longer sells: they run fine,
but **none can be rebuilt on its current type**. Retiring any of them is a one-way door. That is a
different question from whether the host still earns its keep — decide them separately, and never
let a slot-pressure argument (which may be false) settle a reversibility question (which is not).

## Related

- `2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md` — why the
  registry stock prose was corrected alongside web-2's rather than left standing.
- `2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md` — `resource_unavailable`
  (per-DC stock) vs `resource_limit_exceeded` (account cap): different counters, routinely conflated.
- ADR-143 addendum (2026-07-26) — the repin decision and the reduced choice set.
- #6460 — fleet-capacity audit; owns making both of these self-checking.
