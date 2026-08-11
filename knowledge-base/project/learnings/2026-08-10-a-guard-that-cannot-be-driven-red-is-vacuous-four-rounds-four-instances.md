---
title: A guard that cannot be driven RED is vacuous — four review rounds, four instances of one shape
date: 2026-08-10
category: security-issues
module: plugins/soleur/skills/preflight
issue: 7393
pr: 7397
tags: [adversarial-review, mutation-testing, anti-vacuity, bubblewrap, sandbox, test-design]
---

# Learning: a guard that cannot be driven RED by breaking its own stated property is vacuous

## Problem

preflight Check 10 executes a plan-declared `discoverability_test.command` on the operator's
workstation, from a markdown file in a public repo — i.e. attacker-authorable content. PR #7397
hardened it (bubblewrap sandbox, a deny-by-default verb allowlist, a declared-credentialed
terminal) and added guards to keep it hardened.

Across **four** adversarial review rounds, every round found a real defect **in the previous
round's fixes**, and the shape never varied:

> The fix lands on the surface the tests read, while the runtime of record stays broken.
> Equivalently: the guard measures the SHAPE OF ITS INPUT rather than the WORK PERFORMED.

The four instances:

1. The TS mirror was hardened while the bash placeholder guard — the runtime of record — stayed broken.
2. A hardened helper was added with **zero call sites** while the live one stayed wired.
3. Guards counted ROWS in a table instead of COMPARISONS actually performed.
4. A test literally named *"the sandbox mount set is CLOSED, not merely populated"* asserted only
   that binds were READ-ONLY. `--ro-bind /home /home` satisfies that. Measured against live
   bwrap, that one added line makes the Doppler config under `~/.doppler/` readable (294 bytes — the live
   service token) and lists `~/.ssh` private keys, **with the suite reporting 115/0 green and the
   anti-vacuity gate reporting 7/7**.

Instance 4 is the sharpest: the test's NAME claimed closure, its ASSERTION delivered writability.
Read-only is entirely sufficient to exfiltrate — Check 10 prints probe stdout, `curl` is an
allowlisted verb, and `--share-net` retains egress.

## Solution

The generalizable question to ask of every guard:

> **What is the cheapest edit that breaks the property this guard NAMES, while leaving the guard
> GREEN?**

A guard that cannot be driven RED by breaking its own stated property is vacuous no matter how
sophisticated it looks. Applied here, it produced six confirmed holes, all now closed and each
proven closed by a mutation that goes RED:

- **Set-compare the SOURCES, not the flag spelling.** `toEqual(["--ro-bind"])` is a *writability*
  predicate, not a *closure* one. Enumerate `--ro-bind` sources and `--tmpfs` targets over the
  array window and set-compare both; close the array-expansion set too, or `FOO_BIND=(--ro-bind
  /home /home)` declared outside the window and expanded inside it walks straight past.
- **Close the DELETION direction.** Removing `--tmpfs /home` re-exposes the operator home exactly
  as an added bind would, and every presence-style assertion stays green when a mount is deleted.
- **Anchor the exec line.** Three independent presence checks (`bwrap`, `${BWRAP_ARGS[@]}`,
  `</dev/null`) permit arbitrary EXTRA flags between the array expansion and the interpreter. A
  closed mount set is worth nothing if the exec line may append to it.
- **`env -i` is load-bearing, and bwrap does NOT scrub the environment.** `DOPPLER_TOKEN`,
  `GH_TOKEN`, `ANTHROPIC_API_KEY` live in the environment ONLY — there is no on-disk store to
  unmount — so the sandbox's "the files are gone anyway" reasoning never reached them. It was
  entirely unasserted, and SKILL.md called it "redundant-but-harmless", which is precisely the
  comment that invites its deletion.

## Key Insight

**A floor indexed to its own input is not a floor.**

`expect(compared).toBeGreaterThanOrEqual(PARITY_CASES.length - K)` falls as rows are deleted. This
was exploitable end-to-end and demonstrated as a chain: delete the six separator rows (whose own
comment reads *"without a row here the divergence is invisible to this harness"*) — still green;
THEN delete `export LC_ALL=C` from the runtime of record — still green, while the gate genuinely
starts accepting `curl<U+2028>evilarg`. With the rows present, that same runtime edit reddens
immediately. Floors must be **absolute** and ratchet upward only.

The corollary, which is the part that generalizes furthest:

> **Slack between a floor and the measured value is not padding — it is the budget an attacker
> spends.**

`MIN_TESTS`/`MIN_ASSERTIONS` sat 7 tests and 37 assertions below the real counts. Two distinct
attacks landed inside that gap: gutting a manifest-listed test's BODY to `expect(true).toBe(true)`
(name intact, so the identity manifest is satisfied), and deleting 5 generated tests the manifest
was structurally blind to.

**An anti-vacuity control needs the same reasoning applied to ITSELF.** The named-test manifest
existed to catch deleted coverage — but an EMPTY manifest passed vacuously, printing
`[ok] all 0 manifest tests still declared`, because the gate checked the manifest EXISTED and
never that it had lines.

**Measure work, not source shape, wherever a measurement exists.** The suppression grep could
always be out-spelled — `describe.todoIf(true)` evaded it and removed four tests while the gate
printed "no tests skipped at runtime". Parsing bun's `todo` COUNT closes that whole family at
once, because it observes the runtime rather than pattern-matching the source.

## Prevention

- For every guard, name the cheapest green-preserving edit that breaks its stated property. If you
  cannot construct one, you have not understood the guard.
- Prefer runtime measurements over source pattern-matching; a pattern can be out-spelled, a count
  cannot.
- Make floors absolute; ratchet them to the measured value. Treat any gap as attack budget.
- Apply the floor reasoning to the anti-vacuity control itself (non-empty manifest, non-zero
  extraction).
- When a design RULING reduces a control, reconcile the plan/spec artifacts in the same change —
  otherwise the documentation asserts a boundary that deliberately does not exist.

## Session Errors

1. **A carried-forward verification claim went stale and was believed.** The inbound handoff
   asserted "bun shard rc=0 (plugins/soleur 2419/0)". That shard was actually RED: an earlier
   round's commit (`3f5087ade`) had introduced a backtick reference to
   `scripts/probe-verb-gate.sh`, violating the markdown-link convention and reddening
   `components.test.ts`. Nobody re-ran it after that commit.
   **Recovery:** re-ran the shard on resume; converted the reference to a markdown link.
   **Prevention:** on RESUME, re-run the verification you are about to rely on. A green produced
   before the last N commits is a claim about a tree that no longer exists.

2. **A mutation silently failed to apply and would have read as a passing guard.** A perl
   one-liner mutating the exec line died on `@]` escaping; the suite then reported 0 failures,
   which is indistinguishable from "the guard caught it" if the landing is not checked.
   **Recovery:** the mandatory `diff -q` against a pristine backup reported "did not land".
   **Prevention:** never diff against HEAD (which conflates "mutation absent" with "file
   unchanged"); always diff against a pristine backup of the sandbox copy, and require a GREEN
   unmutated control before believing any mutation result.

3. **`rm -rf` on a `/var/tmp` sandbox path was blocked by the protected-location guard** because
   the invoking CWD was the worktree root. **Recovery:** used `mktemp -d -p /var/tmp`.
   **Prevention:** allocate throwaway sandboxes with `mktemp -d`; never hand-roll a path plus
   `rm -rf`. One-off — the guard behaved correctly.

4. **Introduced a shellcheck SC1087 error in my own edit** (`"$SUPPRESS_RE[^)]{0,80}"` parses as
   array-index syntax). **Recovery:** braces (`${SUPPRESS_RE}`); verified rc=0 against the HEAD
   baseline. **Prevention:** when a new shell variable is interpolated immediately before `[`,
   brace it; compare shellcheck rc against the pre-change baseline rather than reading a bare
   non-zero as pre-existing.

5. **Plan Test Scenarios rows 6/8 were stale against the CTO ruling** that deleted Layer 2's arg
   and path rules. **Recovery:** executed all 13 rows against the runtime and reconciled the table.
   **Prevention:** see the last Prevention bullet above.

Forwarded from `session-state.md` (earlier pipeline phases, pre-compaction): proxy-vs-invariant
measurement twice (exit code, then credential *discovery* presented as *reachability*), and a
circular trust argument (`git ls-files` interrogates the attacker's own PR-head index, and
preflight runs pre-merge). Both were caught before the plan froze and are recorded in the plan's
Sharp Edges.

## Round five: the rate still had not decayed

A six-agent panel on round four's fixes found more, four of them in the fixes themselves:

- **The closure guard had an open source.** `sandboxWindow()` scopes to `BWRAP_ARGS=( … )`, but
  `GIT_BIND` and `BWRAP_PROC` are ASSIGNED outside it and EXPANDED inside it. A second
  `GIT_BIND=(--ro-bind /home /home)`, an `else` branch, or
  `BWRAP_PROC=(--proc /proc --ro-bind /home /realhome)` each left the suite green — with a live
  bwrap replay reaching the Doppler token, SSH keys and the gh token store. Closure over a window
  that CONTAINS an indirection is not closure.
- **The exec anchor stopped at `PATH=`**, so `DOPPLER_TOKEN="$DOPPLER_TOKEN"` could be appended
  before `HOME=`, forwarding past `env -i` — the control the same commit had just documented as
  load-bearing.
- **The anti-vacuity gate had no floor at its own chokepoint.** Neutering `pass()`/`fail()`
  printed `0 passed, 0 failed` and exited 0; the half-mutation printed a `[FAIL]` line and STILL
  exited 0. Every control routed through two unguarded one-line functions.
- **`test`/`it`/`describe` are rebindable.** `const it = test.failing;` has no `(` after
  `.failing`, so the source grep misses it, and bun scores a failing `.failing` test as a PASS —
  invisible to `n_skip` and `n_todo` alike. Deleting `env -i` and aliasing one test reported 7/7.
- **The distinct-shape gap.** `MIN_COMPARED` counted ITERATIONS, so six duplicate rows held the
  floor at 22 while the separator coverage was deleted — after which removing `LC_ALL=C` from the
  runtime was green again. The headline exploit, one level down.
- **A required CI gate went red.** `credential-path-guard` forbids resolvable credential-file
  path literals in docs, because such a path makes the harness auto-attach the real file into
  model context. The learning file itself tripped it.

The generalizing lesson is not "add these six guards". It is that **a guard's window, its
chokepoint, and its identifiers are each a separate closure question**, and answering one does
not answer the others.

## Verification

- **11/11 adversarial mutations RED**, unmutated control GREEN. Every mutation proven landed via
  `diff -q` against a pristine backup, in `/var/tmp` sandboxes only.
- `plugins/soleur` suite: 2422 pass / 0 fail.
- Integrity gate: 7/7 at 121 tests / 505 assertions (floors ratcheted to the measured values).
- shellcheck rc=0 (baseline 0); ADR-129 trap-ownership lint rc=0.
- Live-bwrap containment re-verified: host 294-byte Doppler config →
  `No such file or directory` inside the sandbox; `~/.ssh` absent; env-resident token
  → `leaked=<scrubbed>`.

## Related

- ADR-175 — preflight probe execution boundary
- #7403 — probe registry, the successor design
- #7412 — `--share-net` retains the host netns (deliberately out of scope here)
