---
date: 2026-07-27
category: security-issues
module: tests/scripts/lib, apps/web-platform/infra
issue: 6969
pr: 6973
tags: [fail-open, jq, terraform, mutation-testing, stale-claims, gate-design, observability, telemetry-attribution]
---

# The safety rationale I wrote was false, and the gate it justified failed open three ways

## Problem

I built `web-host-replace-gate.sh` — the only check standing between an operator dispatch and
`terraform apply` destroying a production Hetzner web host. It shipped with 38/38 green, a
12-mutation battery proving every arm load-bearing, `run-registered-suites.sh` 72/72, and
`test-all.sh` exit 0.

An 11-agent review found **six P1s**. All were mine. Three were fail-opens in the gate's own
detection logic; three were false claims in the prose justifying it. Every one was measured —
I reproduced each against the tracked code before fixing.

## The three fail-opens, and the one property they share

Each was in the **jq** that computes the counters, not in the bash arms that decide on them.

### 1. `if jq -e '<negative search>'; then` reads a jq ERROR as "false"

The shape guard searched for offenders:

```bash
if jq -e '[.resource_changes[] | select((.change.actions | type) != "array")] | length > 0' \
     < "$plan_json" >/dev/null 2>&1; then
```

`.change.actions` with no `?`. When `.change` is a **scalar**, jq raises
`Cannot index string with "actions"` and exits **5** — and `if` reads a non-zero exit as
"condition false", i.e. *no offenders found*. The counting filter's `.change.actions?`
swallowed the identical error and dropped the entry from every `select`.

Measured — this plan returned **rc=0 PASS**:

```json
{"address":"hcloud_volume.workspaces[\"web-2\"]","type":"hcloud_volume","change":"delete"}
```

`workspaces_volume_destroyed=0`, `out_of_scope=0`. Every user worktree on the host, destroyed,
invisible to all three arms that exist to name it.

**Fix — a POSITIVE assertion, so an error lands on the abort side:**

```bash
if ! jq -e 'all(.resource_changes[];
                (.change | type) == "object"
                and (.change.actions | type) == "array"
                and all(.change.actions[]; type == "string"))' < "$plan_json" >/dev/null 2>&1; then
```

The inner `all(...; type=="string")` also closes `"actions": [["delete"]]`, which passes a bare
`type=="array"` check and then compares an array to a string in every `any(. == "delete")` —
false forever.

**Generalisable:** a guard written as *"search for something bad, abort if found"* fails open on
any input its own filter cannot parse. Write it as *"assert everything is well-formed"*.

### 2. A verb ALLOW-list is the fail-open direction

```jq
select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
```

Anything terraform grows next is classified **inert**. My comment asserted the opposite:

> *"an allow-list of verbs stays correct as the action vocabulary grows"*

Backwards. Terraform has already grown it once (`forget`, 1.7). Measured: `["destroy"]` on the
LUKS volume returned PASS. Only a **deny-list of the known-inert verbs** survives growth:

```jq
select([.change.actions[]] - ["no-op", "read"] | length > 0)
```

### 3. A test anchored on a bare token is satisfied by a comment

```js
expect(jobBlock).toContain("web_host_replace_gate");
```

`extractJobBlock` does not strip comments, and the token appears in the step's prose and in a
`# shellcheck source=` directive. Measured: replacing the real invocation with `if false; then`
left the suite **82/0 green** — on the only check guarding a production host destroy. Re-anchored
on the source **command** and the call **with its argument**; mutation-proven 81/1. The birth job
had the identical defect, while ADR-145 claimed the pairing was pinned.

## Why my mutation battery could not see any of them

All 12 mutations were the same shape: a bash `if [[ … ]]; then` → `if false; then`.

**The tell is uniformity.** N mutations of one shape is one mutation. My battery proved the
*decision* layer load-bearing and never touched the *detection* layer that feeds it — ~90 lines
of jq computing every counter. Before trusting a battery, ask **which layers does it touch?**, not
just how many mutations passed. If every mutation edits the same construct, an entire layer is
uncovered and the green says nothing about it.

Folded into [`2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`](./2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md)
as the layer axis, distinct from that file's unimagined-mutation axis.

## The false claims — and why documentation can be worse than a wrong comment

### "An untargeted resource cannot be planned for destroy" — false

`-target` prunes **dependents**, not **dependencies**. I asserted this in four places as the
preservation mechanism. `hcloud_volume.workspaces[key]` **is** in the plan graph (the targeted
attachment references it) and shows as a no-op. What preserves it is `prevent_destroy` — a
**plan-time** error — plus two gate arms. The LUKS volume is genuinely outside the graph but has
**no** `prevent_destroy`, so two arms are its only guards. Stating the real mechanism per address
is the difference between a reader who knows which guard to preserve and one who doesn't.

### A refusal whose unlock condition already reads as met

I refused a web-1 replace citing an *"AMBIGUOUS `scsi-0HC_Volume_*` glob"*, quoting a
`workspaces-luks.tf` comment that went stale when **#6604** pinned the mount by-id nine days
earlier. The repo carries a live assertion (`AC6b`) that the glob stays gone. I **quoted, not
measured** — in a plan whose Research Reconciliation table opens *"Every row measured this session
against the worktree, not recalled."*

Worse: I named the unblock as *"ADR-119 §Sequencing's volume-ID mount pin"* — **a section that does
not exist**, for a pin that **already shipped**. So the refusal read as relaxable *today*, and a
reviewer following my own instruction would have deleted it and inherited three hazards with **no
gate arms at all** (`-target` is upstream-only, so none can appear in a plan).

**The real hazard is the opposite of ambiguity — determinism pointed at the wrong volume.**
`/mnt/data` pins by-id to `hcloud_volume.workspaces[key]`, which on web-1 is the **plaintext**
volume the 2026-07-23 LUKS cutover **superseded**. Nothing on a fresh boot opens the mapper
(crypttab keyfile `none`; guest-side unlock deferred to **#6931**). A rebuilt web-1 boots healthy
and serves every worktree **rolled back to 2026-07-23**.

**Generalisable:** when you defer a capability behind a stated condition, that condition is a
**trap if it is already satisfied**. Verify the unblock exists and is *unmet* before writing it —
a deferral whose gate reads green invites the next reader to walk through it.

### A same-named predecessor defeats an unanchored telemetry read

The boot-trail reader queries Sentry `statsPeriod=1h` and attributes by `host_name` — which is
**identical** for a destroyed host and its replacement (`soleur-<key>`). Iteration 1 reads the
**predecessor's** terminal event: a healthy predecessor yields `TERMINAL=complete` and a **green
run with the replacement's boot never verified**. That is #6969's originating incident re-created
inside the mechanism built to prevent it.

Structural to **replace** — a birth has no same-named predecessor, which is why the inline
original lacked it. Fix: callers stamp an epoch before `apply`; the reader drops older events and
**fails closed on undatable ones**. Pinned on both sides (the predicate exists; every one of the 9
host-scoped selections applies it; each job stamps the epoch) — a predicate nothing calls is
decoration, and a stamp nobody reads is inert.

## Key Insight

**A gate can be green, mutation-proven, and comprehensively documented while failing open — when
the battery covers one layer, the assertions anchor on tokens the file also mentions in prose, and
the rationale was quoted rather than measured.** The three failure modes are independent, and each
produces evidence that looks exactly like the healthy case.

## Prevention

- Write guards as **positive assertions** over the whole input, never as negative searches — a
  filter that errors is a filter that found nothing.
- Verb/action classification is a **deny-list of known-inert values**, never an allow-list of
  known-mutating ones.
- Before trusting a mutation battery, **enumerate the layers it touches**. Uniform mutation shape
  ⇒ an unmutated layer.
- Any assertion whose token also appears in a comment in the scanned scope is satisfiable by that
  comment. Anchor on syntax the prose cannot produce (a command, a call-with-argument).
- A deferral's unblock condition must be **verified unmet** at the time of writing.
- Telemetry attributed by a name a predecessor also bore needs a **run anchor**, failing closed on
  events it cannot date.

## Session Errors

1. **Non-object `.change` PASSed a workspaces-volume destroy.** Recovery: positive `all(...)`
   assertion. Prevention: write guards as positive assertions over the whole input.
2. **Verb allow-list classified unknown verbs inert**, with a comment asserting the reverse.
   Recovery: deny-list of `no-op`/`read`. Prevention: classify actions by a deny-list of
   known-inert verbs, never an allow-list of known-mutating ones.
3. **Gate-invocation assertion satisfied by comments.** Recovery: anchored on the source command
   and the call-with-argument, both jobs. Prevention: `cq-assert-anchor-not-bare-token` — anchor
   on syntax prose cannot produce, and mutation-prove every assertion over a file that also
   documents the thing asserted.
4. **Web-1 rationale false in six places.** Recovery: retracted in place and replaced with the
   measured hazard. Prevention: measure, do not quote — especially a comment in another file.
5. **Unlock condition named a nonexistent section for a shipped pin.** Recovery: restated as
   #6931 + arms + rehearsal; tracker #6964 cited. Prevention: verify a deferral's gate is unmet.
6. **Boot-trail read the predecessor's verdict.** Recovery: run anchor, pinned both sides.
   Prevention: anchor any name-attributed telemetry read.
7. **`tainted`/`absent` self-refuting**, sending the operator to the remedy the birth gate
   refuses. Recovery: split by state with a Hetzner probe to discriminate. Prevention: when a failure has
   two reachable end-states, document the discriminator before the remedies.
8. **`nic-wait-gate` extractor blind** — quote class `'?` while both targets are double-quoted, so
   it asserted "found 0". Recovery: widened + non-vacuity floor + named carve-out. Prevention: every extractor-based
   assertion needs a floor proving the extractor still finds the known-good members.
9. **"Untargeted cannot be destroyed" asserted in four places.** Recovery: corrected per address.
    Prevention: state the mechanism that actually preserves each address, not a general theory.
10. **Provisioner count 8, actual 15.** Recovery: re-derived by grep. Prevention: publish the
    command next to any count (`cq-cite-content-anchor-not-line-number` sibling).
11. **Four stale "exactly one dispatch job" claims.** Recovery: amended, not deleted. Prevention:
    index a sweep by PROPOSITION, not by file — the claim lives where the diff never opens.
12. **Ended a turn on "I'm continuing…" instead of a tool call.** Recovery: resumed on the next
    message. Prevention: **already covered** by `hr-when-a-workflow-concludes-with-an` — no new
    rule warranted; the existing one is correct and was simply not followed.
13. **Plan's provisional ADR-146 was taken.** Recovery: swept five refs to 148. Prevention: the
    plan already flagged the ordinal as provisional; the gate worked.
14. **Malformed `sincok` jq def passed `bash -n`.** `bash -n` validates the *shell*, not an
    embedded jq program — only a behaviour matrix caught it. Prevention: exercise any embedded
    DSL against a truth table before wiring it.
15. **Malformed-`.change` fixtures hand-escaped through a `printf` format** were malformed for a
    *different* reason than the one under test — the exact trap `rc_noactions`' own comment warns
    about. Recovery: added `rc_change()` emitting `.change` verbatim via jq. Prevention: build fixtures
    with the same serializer the SUT reads; hand-escaping is how a fixture fails for the wrong
    reason.
16. **Sibling-NIC fixture mislabelled** as proving key-scoping; type-scoping the arm leaves the
    suite green (it is layered behind `out_of_scope`). Recovery: relabelled to what it proves. Prevention: before labelling a case a sole-guard proof,
    mutate the arm and confirm the case actually reds.
17. **A `python` edit script asserted out AFTER computing but BEFORE `write()`**, silently losing
    the `rc_change` helper; the next run then failed for a confusing reason. Prevention: write
    incrementally, or assert every anchor up front before any mutation.
18. **`pkill -f 'run-registered-suites'` matched its own shell**, killing the call before its
    commit (exit 144). Prevention: match on the script suffix (`\.sh`) or use the recorded PID.
19. **`yaml.safe_load(wf)['on']` → `KeyError`.** YAML 1.1 parses bare `on:` as boolean `True`.
    Prevention: `d[True] if True in d else d['on']`.
20. **`grep 'test($re)'` under BRE matched nothing**; `-F` was required. Prevention: use `-F` for
    any literal containing regex metacharacters. One-off.
21. **`sed` delimiter collision** (`|` in the expression vs `|` as delimiter). Prevention: prefer a
    scripted edit with explicit anchors over `sed` for multi-metacharacter payloads. One-off.
22. **Five `python` replace anchors missed** on line-wrapping/escaping differences; line-indexed
    edits were needed. Prevention: read the exact bytes before authoring an anchor. One-off.
23. **Background output file lost to `ENOENT`** (another process's startup cleanup) mid
    mutation-proof. Prevention: none available (external process). External; re-ran.

## Related

- [A mutation battery only covers what you mutate](./2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md) — the layer axis is folded in there
- [An existence assertion that ran before the file existed bricked every boot](./2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md) — #6969's sibling, same gate family
- ADR-148 — web-host replacement is a distinct gated dispatch
- #6931 (fresh-boot guest-side LUKS unlock), #6964 (web-1 replace tracker)
