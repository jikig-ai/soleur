---
module: registry-luks-recut / D10 authorization gate
date: 2026-08-05
problem_type: logic_error
component: ci_workflow
symptoms:
  - "two suites at 46/0 and 34/0 certified a gate that could not pass on any dispatch"
  - "an end-anchored classifier arm was dead on arrival and no fixture could see it"
  - "a pre-rehearsal probe exited 0 having measured nothing, on every dispatch"
root_cause: assertion_certifies_a_different_property
severity: critical
tags: [mutation-testing, fail-open, irreversible-destroy, fixture-design, agent-panel]
issue: 7277
pr: 7290
synced_to: [review]
---

# Every green signal certified something other than what it claimed

## Problem

`registry-luks-recut` destroys production's **only** container image store. `scripts/registry-pull-path-health.sh` (D10) is the gate that authorizes it. The PR existed because a previous revision had 23 green assertions and no row asserting the gate could PASS — so a gate rewritten to refuse unconditionally kept every assertion.

Fixing that produced a second gate that also could not pass, for a different reason, and the same class recurred **four more times** inside the fix. At every point the signals were green: two suites at 46/0 and 34/0, a passing plan panel, `tsc`, `actionlint`, `shellcheck`, and two prior mutation batteries reporting 15/15 and 13/13 caught.

## Root cause, stated once

Every defect below is the same shape: **an assertion that certifies a property adjacent to the one it names.** The suites were not weak; they were precise about the wrong thing. The only thing that found any of them was *running the code and reading the bytes*.

## The defects, each with its measurement

### 1. The rehearsal read GHCR anonymously (the gate could not pass)

`registry-restore-from-ghcr.sh` exports a private `DOCKER_CONFIG` before its first GHCR read — deliberately, so a prd credential cannot leak into a shared keychain. crane resolves credentials **only** from `$DOCKER_CONFIG`, with no `$HOME` fallback. So the job's `docker login ghcr.io` was invisible to it.

A1 runs in the gate's own process and resolved four digests successfully with the ambient keychain. A2 shells out to the engine, which starts from an empty keychain, reads PRIVATE packages anonymously, gets `MANIFEST_UNKNOWN`, and exits 2 — printing *"GHCR could not be read"* immediately after A1 proved it readable.

No suite could see it: **every one of them stubs crane.** Three review agents found it independently.

### 2. `tr` leaves a trailing SPACE, and `$( )` does not strip spaces

```
last_err() { tail -c 400 "$1" | tail -n 1 | tr '\n' ' '; }
```

`tail -n 1` keeps the terminating newline; `tr` rewrites it to a **space**; `$( )` strips trailing **newlines** but not spaces. So an end-anchored classifier arm (`*EOF`) was dead on arrival:

```
shipped -> [Error: Get "https://sink/v2/": EOF ] classify=UNKNOWN   exit 6, NOT retryable
fixed   -> [Error: Get "https://sink/v2/": EOF]  classify=NETWORK   exit 3, retryable
```

Post-destroy, with the store already empty, that is the difference between a retry that clears and a permanent verdict.

**Why no fixture saw it:** every `.err` fixture is written with `printf '%s'` — i.e. *without* the terminating newline real crane emits. The whole suite sat on one side of the transform.

### 3. The same function, the opposite defect, earlier

It took the last 400 **bytes** while every comment claimed the last **line**. `classify()` substring-matches, so its **first** `case` arm won over the whole capture:

```
line 1: ... MANIFEST_UNKNOWN: manifest unknown
line 2: ... UNAUTHORIZED: authentication required

byte-tail -> NOTFOUND     line-tail -> DENIED
```

On a **conditional** pin, `NOTFOUND` is a silent declared skip — so a credential rejection could be recorded as *"absent, skipping"*, on the inventory that authorizes destroying the only copy.

**Why no fixture saw it:** every real crane message is under 400 bytes, so byte-tail and line-tail return *identical strings*. The discriminating fixture needs two **different** classifier tokens whose case arms disagree. My first attempt at that fixture led with the generic `HEAD request failed` line, which carries no classifier token — so it passed under both implementations.

### 4. A probe that could not probe

```bash
grep -oE 'default[[:space:]]*=[[:space:]]*"c[a-z0-9]+"' variables.tf | head -1 | grep -oE 'c[a-z0-9]+$'
```

Stage 1's match **ends in a quote**, so the `$` anchor can never match. Measured: `SRV_TYPE=[]` — empty on every dispatch. The step exited 0 through its own *"could not derive"* arm, having probed nothing, forever. `head -1` would have returned `cx33` (the **web** host) rather than `cx23` anyway.

And it queried `.prices[].location` — where a type is **sold**, including datacenters whose stock is exhausted — instead of `.server_types.available`, which is what is orderable now. So the exact incident its own header cited (#6460) was invisible to it.

### 5. A seam-guard hole named by its own convention

The gate refuses any `REGISTRY_GATE_*` variable inside Actions, because those seams replace its external dependencies — `REGISTRY_GATE_RESTORE_CMD=/bin/true` would print `verdict=AUTHORIZED` having proven nothing.

`REGISTRY_RESTORE_CRANE_CMD` replaces crane **inside A2** and inside the post-destroy restore. The engine carries no `GITHUB_ACTIONS` guard at all. It escaped a list that reads as exhaustive **purely because its name says `_RESTORE_` rather than `_GATE_`**.

### 6. A4 fell open on its own grader

The gate aborts when the *detector* is missing — *"a chmod bit is not a safety boundary for an irreversible destroy"* — and then assigned `unmeasured` when the *grader* could not be sourced. `unmeasured` is a token the grader itself produces, routed to DEGRADE, falling through to AUTHORIZED. **The comment above the line asserted fail-closed while the code fell open.**

## Solution: the two mechanisms worth reusing

Eleven learnings already exist on "your mutation battery only covers what you mutate". The novel contribution here is **structural**, not another instance:

**1. `expect_survive` — an exemption that cannot rot.** For a mutation that is genuinely unreachable, record it with a **required** justification rather than deleting it (deleting is how a battery quietly shrinks). It fails in **both** directions: a documented-unreachable mutation that *is* caught fails the battery, so a justification that later becomes false cannot sit there forever.

This immediately proved its worth: I promoted one exemption out on plausible reasoning, and measurement refuted it — with `tail -n 1` the mutant is byte-identical, so it is genuinely undetectable. The two-directional check is what surfaced my error.

**2. A dispatch floor.** Neutering every `mutate`/`expect_survive` call printed:

```
=== 0 caught, 0 survived, 0 documented-unreachable ===
EXIT=0
```

CI green, having asserted nothing — in a file whose own header argues *"the count must stay honest."* A floor (never an equality: the count is developer-incremented) closes it.

**3. Derive the guarded set; never restate it.** The seam list is now `grep -ohE 'REGISTRY_(GATE|RESTORE)_[A-Z_]+'` over **both** SUTs, so a seam added anywhere fails the row. A restated list is a subset check and is blind in exactly the direction that matters.

## Key insight

> A guard's assertion and a guard's property drift apart silently, and every mechanism that reports on the guard reports on the assertion.

Ask of every check: **name the mutation that satisfies this assertion while violating the property.** If you cannot, the check is pinning something else. And prefer one measurement to any number of concurring readings — three review agents read the seam-guard list as exhaustive; a `grep` of what the scripts actually read did not.

## Session Errors

1. **Concurrent review agents contaminated the shared worktree.** Ten agents ran; several applied fixes inline while others read the same files. One attributed another's *uncommitted* edit to my commit and reported a live defect as already-fixed; I reverted to HEAD twice and an agent re-applied after a revert, producing duplicate `env:` keys caught only by `actionlint`. **Prevention:** `review/SKILL.md` documents this hazard for ONE mutating agent; at panel scale the agents must be report-only, or writes serialized. Routed as an amendment.
2. **I promoted mutation E22 out of its exemption on reasoning measurement refuted** (the mutant is byte-identical). **Prevention:** before promoting an exemption, exhibit a capture where the two implementations differ.
3. **I broke the G13 anchor** by inserting a comment between the two lines it spanned, hard-aborting the whole battery (exit 2) — a fragility the file already documents for G09/E17. **Prevention:** anchor on the smallest unique construct; `py_replace` already enforces uniqueness, so a second line buys nothing and costs fragility.
4. **My first discriminating fixture did not discriminate** (it led with a line carrying no classifier token). **Prevention:** state which arm each fixture line hits *before* running it.
5. **I shipped "B3 resolved BY the job split" — false.** `needs:` serializes, so the cheap denies still run strictly AFTER the rehearsal; the split moved where a *timeout* lands, not the order. The CTO ruling asserted it too. **Prevention:** re-derive an ordering claim from the dependency edge, never from the narrative that produced it.
6. **I shipped "read through `local.zot_image`'s arch ternary"** while the code reads `zot_image_amd64` directly and only presence-checks the ternary. **Prevention:** a comment describing a read is a claim; grep the read.
7. **A negative assertion matched the prose** *"push a timeout into `terraform apply`"* in a neighbouring comment — the **third** occurrence of this class in one PR. **Prevention:** comments-stripped by default for any assertion whose literal the file must also document.
8. **The dark stock probe was in code I MOVED** into the new gate job without re-deriving that it worked. **Prevention:** relocating code is not evidence it runs; re-derive its output at the new site.
9. **First full-suite run 264/265** — the job split broke `jobFor`'s one-job-per-option assumption in a sibling test. **Prevention:** when splitting a job, grep for tests that resolve options *to* jobs.
10. **`\'` inside a single-quoted bash string** → syntax error. **Prevention:** bash cannot escape a single quote inside single quotes; rewrite the string.
11. **`--no-verify` on every commit** bypassed the secret-scan hook; gitleaks was run manually *after* several commits. **Prevention:** run the canonical scan before the first commit of a session that uses `--no-verify`, not after.
12. **Over-wide `shellcheck` glob** reported SC2034 on three files outside the diff, briefly reading as my defects. **Prevention:** scope lint globs to `git diff --name-only`.
13. **A chained `sleep 45` was blocked** by the harness. **Prevention:** use an `until`-loop in a background task to wait on a condition.

## Related

- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the class; this entry adds the two mechanisms that make the exemption and the dispatch count honest.
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md` — session error 7 is the same class, third occurrence.
- `2026-07-28-the-property-my-pr-existed-to-buy-was-pinned-by-nothing.md` — the "pinned by nothing" shape, here applied to a deleted predicate.
- ADR-169 — why there is no live-sink predicate.
