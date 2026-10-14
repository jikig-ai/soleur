---
title: "My class-closing invariant closed a subset, and the battery that was supposed to prove it ran against a red control"
date: 2026-08-06
issue: 7286
pr: 7301
category: test-failures
module: apps/web-platform/infra
tags: [invariant-population, mutation-battery, scrubber, observability, incident]
---

# My class-closing invariant closed a subset, and my battery had a red control

#7286 was a 17-hour P1: `inngest-redis.service` crash-looped on prod, every background job
stopped, and the only fact any remote surface could establish about the failing component was
"it exited non-zero". The fix was small. Everything expensive in this session was about
**guards that looked like protection and were not** — including the ones I wrote to close the
incident, and the battery I used to prove they worked.

## 1. Ask what SET the invariant quantifies over, not whether it passes

I shipped a "class-closing" invariant asserting that every unit which reads the pinned Doppler
copy and runs `doppler run` unconditionally must carry a credential drop-in across the full
delivery lockstep. It walked `infra/*.service`.

That is not the hazard class. Three of the units carrying
`EnvironmentFile=/etc/default/inngest-server` are written as **heredocs inside
`inngest-bootstrap.sh`** (`inngest-server`, `vector`, `inngest-heartbeat`), so the invariant
closed only the subset that happens to be a checked-in file. Measured: a heredoc unit with the
full hazard shape and **zero** delivery wiring left the suite **190/190 green**, while the
identical unit as a tracked `.service` file goes RED with 8 failures.

Coverage was a function of which authoring form the next author picked — and the uncovered form
is the one this incident's own siblings use.

**The question to ask of any `∀ x ∈ S` guard:** *what is S, and is S the same set as the hazard
class?* A guard whose population is "files matching a glob" is only as good as the assumption
that the hazard cannot exist outside that glob. Here it demonstrably could, and did, three times.

Fix: extract heredoc-authored units (`readonly X="/etc/systemd/system/<n>.service"` +
`cat > "$X" <<EOF`) and run the SAME predicate over both populations, each with its own
cardinality guard so neither can silently empty.

## 2. A red control voids the battery — and rc≠0 is not attribution

I built a mutation battery to prove the new guards were load-bearing. It reported all mutations
caught. It was worthless, for two independent reasons:

- **The control was RED.** The sandbox copied only `apps/web-platform/infra/`, so a guard's
  relative path to `.github/workflows/` did not resolve and the unmutated tree already failed.
  Every row measured against an already-failing baseline is noise wearing a result's clothes.
- **rc≠0 was read as "caught".** One mutation's RED came from an unrelated pre-existing
  assertion (`PrivateTmp=true`), not from the guard under test. The guard might have survived;
  the battery could not tell.

Re-run with a green control and per-mutation attribution (`did MY named assertion fire?`), all
seven guards were genuinely load-bearing — but that was luck, not evidence, until it was
measured. **Both properties are required: a green control, and a per-case assertion match.**

## 3. A "port" of an existing rule set is a claim to diff, not to re-derive

I added scrubber rules to `cat-deploy-state.sh` and documented them as a port of `vector.toml`'s
`pii_scrub`, reasoning explicitly that "a second scrubber would drift from this one."

It **was** a second scrubber, and it had already drifted — weaker — from the one it cited:

| | vector.toml | what I shipped |
|---|---|---|
| DSN rule | scheme-agnostic `([a-z][a-z0-9+.-]*://)…` | redis-only `(rediss?)://…` |
| case | case-insensitive | case-**sensitive** |

Consequence: `postgres://inngest:<pw>@db.<ref>.supabase.co:5432/postgres` survived **verbatim**
into an HTTP response body — on the very tail that surfaces `INNGEST_POSTGRES_URI`. And because
redis matches config directives with `strcasecmp` and echoes the **original** casing on a parse
error, `REQUIREPASS "…"`, `RequirePass …`, `Masterauth …` and `REDIS://default:<pw>@…` all passed
through unredacted.

**When porting a rule set, diff against the source.** Re-deriving it from memory produces
something that reads like the original and is weaker in the specific places you did not think
about.

## 4. Absence-only assertions cannot see over-redaction

The scrub tests asserted `! grep <secret>` plus "the tail is non-empty". Appending
`s/^.*(requirepass|masterauth|dp\.).*$/LINE-NUKED/gI` to the pipeline passed **113 assertions**:
secrets gone, tail non-empty, and even the `NOAUTH Authentication required` preservation assert
passed — because that line carries none of the three tokens. Meanwhile every line carrying the
actual diagnosis (`*** FATAL CONFIG FILE ERROR ***`, `Bad directive`, `Doppler Error`) was
destroyed.

Over-redaction is the **natural** failure mode of hardening a scrubber, and this one was hardened
twice inside a single review round. Pair every secret-REMOVAL assert with a signal-RETENTION
assert. This matters most in exactly this PR's shape: it deleted the runbook's last-resort host
login, so the scrubbed tail is the only surface left.

## 5. Ask whether the two sides of a comparison can ever be equal

`vector_config_identity` emitted a sha256 of the on-host `/etc/vector/vector.toml` so it could be
compared against the repo file — and my code comment said "comparing this hash to the repo file
answers that directly."

It cannot. The on-host file is a **render**: `vector.toml` carries four `@@HOST_NAME@@` sentinels
and three different renderers substitute them differently. The hashes never match on any host, so
the field degraded to "did it change between two reads" — not the question. Replaced with a
membership answer (`redis_allowlisted=yes|no`), anchored on the quoted allowlist entry so the
comment 14 lines above the real entry cannot satisfy it.

**For any identity/comparison field, ask whether the two operands can ever be equal in
production.** If not, the field is decoration and its comment is a false claim.

## 6. Token-presence is not relation-presence

The dominant anti-pattern across every guard I wrote: `grep` for a name and `grep` for an envname
in the same file proves neither **pairing** nor **provenance**.

- Swapping the `envname` values between two `hooks.json.tmpl` bridge entries kept all four tokens
  present → both guards green, each unit receiving the OTHER's drop-in.
- Pointing the redis payload key at `10-inngest-heartbeat-doppler-token.conf` → both guards green.

Taken together the five-surface chain was proven **for names at every hop and for content at
zero hops**. Assert the relation (name→envname on one entry; payload key→source file on one
line), not co-occurrence in a file.

## 7. A probe must not be able to hang the surface it protects

`stat`/`df` on `/mnt/data` ran unbounded. That is a **network-backed** Hetzner volume, so on a
detached or IO-erroring volume they block in uninterruptible sleep — and `2>/dev/null ||` catches
**errors, not hangs**, while `webhook.service` sets no command timeout. The probe would have hung
the endpoint under precisely the condition it was added to report, in the PR that removed the SSH
fallback. Everything is under `timeout` now, and a wedged probe reports `probe-timeout` rather
than a clean `absent`.

## Session Errors

- **`| tail -8` masked a script's exit code** — reported `MAIN_EXIT=0` while the script exited 1.
  I was enforcing this exact trap on other people's commands throughout the session and committed
  it myself. **Prevention:** for any command whose pass/fail is load-bearing, `cmd > "$log" 2>&1;
  rc=$?` and inspect `rc` — never read a verdict through a pipe.
- **Mutation battery ran against a RED control** and attributed a catch to an unrelated
  assertion. **Prevention:** run the unmutated control first and require GREEN; assert the
  intended assertion fired by name, never `rc != 0`.
- **Asserted a check was a merge blocker without reading the ruleset.**
  `registry-userdata-budget` is not in the required-contexts set. **Prevention:** resolve
  `gh api repos/:owner/:repo/rulesets` before calling anything a blocker.
- **Reported a CANCELLED job as failed.** `gh pr checks` renders `cancelled` and `failure`
  identically; the jobs API showed `"conclusion":"cancelled"` (fail-fast collateral).
  **Prevention:** read `gh api …/jobs` before attributing a red.
- **Inherited a wrong plan claim** ("the only hook of six" lacking the error-body flag; measured:
  one of three, of eight GET hooks). **Prevention:** plan-quoted enumerations are claims to
  re-derive, like plan-quoted counts.
- **First bare-PATH fixture removed `jq`/coreutils**, so exit 127 was the harness failing, not the
  SUT. **Prevention:** a robustness fixture must remove exactly the dependency under test and
  keep the interpreter's own toolchain; pin the interpreter absolutely.
- **Left two verified edits uncommitted** across a long test run, surfaced only when
  `filter-branch` refused. **Prevention:** commit each verified unit immediately.
- CWD drift between Bash calls broke a `terraform` invocation. **Prevention:** `terraform -chdir=`
  with an absolute path; never rely on ambient CWD.
- A transient `gh` network failure on the first call. One-off; retry succeeded.
- The plan `Write` was blocked by the IaC-routing hook (forwarded). Resolved via `iac-routing-ack`.
- No `spec.md` on this branch, so `lane:` fail-closed to `cross-domain` (forwarded). Expected.
- `rm -rf` with variables was blocked twice by the destructive-path guard. The guard was right
  both times; use literal paths in sandbox teardown.
- **Shipped a "class-closing" invariant whose population was the wrong set** (§1). Caught by
  review, not by my own battery — my battery only ever mutated the "delete a delivery surface"
  axis. **Prevention:** for any `∀ x ∈ S` guard, state S and ask whether it equals the hazard
  class; mutate by ADDING a member, not only by editing one.
- **Shipped a scrubber documented as a port that was a weaker fork** (§3). **Prevention:** diff
  against the source rule set; a port is a claim to verify, not to re-derive.
- **Shipped a comparison field whose operands can never be equal** (§5), with a comment asserting
  it worked. **Prevention:** for any identity field, check whether the two sides can match in
  production before writing the comment that says they do.
- **Shipped an unbounded probe on a network-backed volume** (§7) that could hang the one
  diagnostic surface the same PR left standing. **Prevention:** every probe on a remote/network
  path goes under `timeout`, and "could not measure" must be its own value, never a clean absence.

## The through-line

Six of the seven findings reduce to one sentence: **a check that cannot fail is
indistinguishable from one that passed.** The population was wrong (1), the baseline was wrong
(2), the rules were weaker than their source (3), the assertions were one-directional (4), the
operands could never be equal (5), and the greps proved co-occurrence instead of relation (6).

Every one of them was green.
