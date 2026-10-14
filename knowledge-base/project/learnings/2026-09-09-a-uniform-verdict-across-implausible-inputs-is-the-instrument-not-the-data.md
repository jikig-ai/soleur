---
module: Observability / Alerting
date: 2026-09-09
problem_type: logic_error
component: shell_script
symptoms:
  - "three consecutive credential probes each returned an identical verdict for every token, including tokens that could not possibly hold the permission"
  - "a vendor endpoint returned an empty list from a key that lacked scope to read it"
  - "git grep matched zero files because the pattern was a fatal, and the catch reported it as zero matches"
  - "two ops alert paths reported success for 111 days while the vendor refused every message"
root_cause: unvalidated_instrument
severity: high
tags: [instrumentation, measurement, false-negative, guards, alerting, resend, cloudflare, dnssec]
synced_to: [work, review]
---

# A uniform verdict across implausible inputs is the instrument, not the data

## Problem

PR #7989 began as "Cloudflare removed our domain, fix it" and ended as a study in
broken measurement. Every defect in the session — the two production bugs, my three
bad probes, the four gaps in the guard I wrote, and the correction that overreached —
reduced to one shape:

**An instrument that returns the same answer regardless of its input is
indistinguishable from a working one, and it reads as a finding.**

The original production bug is the purest instance. Two Inngest cron alert paths
POSTed to Resend with a `from:` on the **jikigai.com** domain, which carries none of Resend's
verification records. The vendor refused every message. Neither call inspected the
response, so both paths reported success — **for 111 days**, from the GHA→Inngest
port (#4227, 2026-05-21) until this PR. The instrument that was supposed to say
"the alert went out" said it unconditionally.

## Investigation

### The tell: uniformity across members that cannot share an answer

The plan claimed "no existing Cloudflare token can create a zone". Checking it took
three probes, and the first two were worthless in ways that looked like results:

| Probe | Input | Result |
|---|---|---|
| 1 | invalid name, no account | `1002 Invalid domain` — **all 11 tokens** |
| 2 | valid name, bogus account | `1068 Permission denied` — **all 11 tokens** |
| 3 | invalid name, real account | `1002 Invalid domain` — **all 11 tokens** |

Each was individually plausible. What falsifies all three is that the set includes
`CF_API_TOKEN_PAGES` and `CF_API_TOKEN_BOT_MANAGEMENT` — tokens that obviously
cannot create zones. **A verdict that does not discriminate between a
zone-administration token and a Pages token is not measuring permission.**

The underlying fact: Cloudflare validates the domain name *before* authorization, so
`POST /zones` cannot answer "can this token create a zone" without actually creating
one. The question is not answerable non-destructively. The plan asserted it anyway;
the register now records it as withdrawn.

### The control is what separates "nothing there" from "cannot look"

`GET https://api.resend.com/domains` returned `count: 0`, which reads as "no verified
domains". The key is send-only:

```
HTTP=401 {"statusCode":401,"message":"This API key is restricted to only send emails","name":"restricted_api_key"}
```

A known-bad key answers `400`, not `401` — so the 401 is a real scope response and
not a generic rejection. That control is the entire difference between a datum and an
artifact. The conclusion (jikigai.com is unverified) survives, but on
key-independent DNS evidence: `resend._domainkey.jikigai.com` and `send.jikigai.com`
resolve empty, while the soleur.ai equivalents carry a DKIM key and the SES bounce
records.

The plan had made the same mistake, citing the same endpoint. An inherited claim is
not a checked claim.

### A tool's default dialect can make a fatal look like a clean sweep

The guard I wrote enumerates Resend send sites. Its SDK arm used:

```ts
const SDK_PATTERN = "emails\\.send\\(";   // WRONG
```

`git grep` defaults to **basic** regex, where an escaped open-paren opens a group:

```
$ git grep -l -- 'emails\.send\('
fatal: command line, 'emails\.send\(': Unmatched ( or \(     # exit 128
```

My `catch { return []; }` — commented as handling "zero matches" — swallowed exit
128. Four SDK send sites, including `notifications.ts` with eight send calls, were
silently outside the window while the guard reported clean.

## Solution

**The generalizable move: before reading any instrument's output, run it against a
known-positive and a known-negative.** If both arms produce the same answer, the
instrument is the finding.

Concretely, in this PR:

- **Probes**: paired every credential probe with a control (invalid key → 400 vs
  401). Where no discriminating probe exists — the Cloudflare case — the honest
  output is `UNRESOLVED`, not either uniform result.
- **`git grep`**: `-F` for literal patterns, and distinguish exit 1 (no matches,
  legitimate) from exit ≥2 (fatal). A catch that treats them alike converts a broken
  pattern into a clean bill of health.
- **The alert paths**: capture the response, check `!resp.ok`, mirror via
  `reportSilentFallback`, and attach the vendor's **body** — Resend puts the reason
  there, and this workstream had already misread a 401 as an unverified domain.
- **Alerting**: mirroring made the failure *queryable*, not *alerted*. No Sentry rule
  matched the new tags, so "the alert channel is dead again" would have landed in the
  issue stream and paged nobody — the same posture that let the original bug live.
  Added `sentry_alert.ops_email_delivery_failure` plus a contract test that derives
  the rule's feature list from the `.tf` so emit and rule cannot drift.

### The guard I wrote to fix this had four instances of the same class

Reviewed by 14 agents; each found a different instance of one gap — **the guard's
assembly was narrower than its name**:

1. the SDK arm was dead (above);
2. `cron-bug-fixer.ts` was *enumerated* while contributing **zero** senders, because
   its sender is a variable — so the one site whose sender is runtime-overridable was
   the one the guard could not read;
3. a cardinality floor of `>= 5` against 10 real sites, blind to a substitution;
4. the response check was hardcoded to the two files I had fixed, while the docstring
   claimed class scope.

Then my first correction **over-widened** it: matching any quoted `@`-string on a line
mentioning "from" read the RECIPIENT out of `{from: $from, to: ["..."], ...}` and
produced nine false offenders. *A widening moves the error to the side no fixture
covers.* Anchor on the construct, not on proximity.

Finally the test was **named** "never sends from a domain without Resend verification
records" and **implemented** a denylist of one domain — a third unverified domain
passed cleanly until it became an allowlist of verified domains.

## Key Insight

Four rules, in descending generality:

1. **A verdict that does not vary with its input is not a verdict.** Check for
   uniformity across members that cannot share an answer before reading any result.
2. **A control is cheap and is the only thing that distinguishes absence from
   inability.** "Nothing found" and "could not look" are the same bytes.
3. **The fix's own verification is the least-audited surface in the diff.** It is
   written after the tests, while holding the defect in mind, so it inherits the
   defect's framing and nothing forces coverage for it.
4. **A guard's assembly must equal the property its name claims.** Ask: name an
   implementation a reasonable engineer might write next that satisfies this
   assertion while violating the property.

## Prevention

- Pair every probe with a known-positive **and** a known-negative arm; report
  `UNRESOLVED` when they agree.
- Use `-F` for literal `git grep` patterns; never let a catch conflate exit 1 with
  exit ≥2.
- Mutation-prove every new guard, and include a **comment-only** mutation — a guard
  whose assertions can be satisfied by the prose explaining them pins nothing.
- When a correction sweeps a claim, index by **claim and subject**, never by file or
  by remembered phrasing.
- A deferral is not enforced until the durable artifact carries it.

## Session Errors

**Three consecutive degenerate Cloudflare probes read as findings.** Each returned a
uniform verdict across all 11 tokens; I nearly reported the first as evidence.
Recovery: noticed the set included tokens that obviously cannot create zones.
**Prevention:** treat uniformity across implausible members as an instrument failure;
require a discriminating control before reading any probe.

**Read `count: 0` from a send-only Resend key as data.** Recovery: added a control
(invalid key → 400 ≠ 401) and re-established the conclusion from DNS.
**Prevention:** as above. Note the plan made the identical error — an inherited claim
is not a checked claim.

**A `git grep` BRE fatal was swallowed as "zero matches".** Shipped into the guard,
blinding it to four SDK send sites. Recovery: `-F` for literals.
**Prevention:** distinguish exit 1 from exit ≥2 in any grep wrapper.

**Over-widened the sender extractor into nine false positives.** Went from vacuous to
reading `to:` as `from:`. Recovery: anchored on construct. **Prevention:** a widening
moves the error to the side no fixture covers — add a fixture there in the same edit.

**Shipped a guard with four assembly gaps, then named a denylist as an allowlist.**
Recovery: pinned the site SET, made unresolvable senders fail closed, swept the
response check across the class, replaced the denylist with a verified-domain
allowlist. **Prevention:** name the mutation that satisfies the assertion while
violating the property, before committing the guard.

**Swept an EXECUTED K-bis personal-data transfer as "never executed".** The tail I
withdrew had four limbs; only the Terraform ones were never executed. Recovery:
scoped the claim and recorded both non-Terraform limbs' status. **Prevention:** when
withdrawing a compound claim, enumerate its limbs and give each an explicit status.

**Stamped four legal artifacts with an OPEN ISSUE number as though it were the PR.**
Recovery: restamped `#7995 / PR #7989`. **Prevention:** an auditor follows the
citation; issue and PR are different objects.

**Swept by file when the unit of truth was the claim.** Left two live operator
runbooks standing — one of which would repoint a published legal URL at a host with
no route — plus a signed-audit twin. Recovery: bannered both, corrected the register's
"two artifacts" to four. **Prevention:** grep the claim's subject repo-wide and decide
every hit.

**Left the plan and tasks.md reading as live instructions** for work whose task 1.2
restarts the 28-day clock that caused the incident. Recovery: BLOCKED/DEFERRED
banners. **Prevention:** a deferral decision is not enforced until the durable
artifact carries it.

**Baselined a `credentials_required` declaration I doubted** rather than deleting it,
spending the reviewable diff line to avoid the review. Four reviewers independently
said delete: the probe it waived does not exist, so preflight Check 10 was exiting
SKIP-DECLARED before discovering that. Recovery: deleted the declaration, reverted the
baseline 11→10. **Prevention:** if the comment justifying a waiver already argues
against it, that is the answer.

**Misread a background wrapper's `exit 0` as the command's — twice.** One commit was
killed by my own `timeout 900` mid-battery (`EXIT=124`) and reported as complete.
**Prevention:** read the rc file and the runner's own summary; the notification
reports the trailing echo. This class is already documented in `work/SKILL.md` and I
hit it anyway.

**The pre-commit gate's advisory lock turns contention into an OOM, and the commit
silently does not exist.** `bun-test` fires on any staged `*.ts` -- here a COMMENT-ONLY
count edit -- and runs the whole battery. It queued 60 minutes on `flock -w 3600`
behind another worktree, and `tc_acquire` then reported `LOCK_CONTENDED_PROCEEDING`
and ran ANYWAY: the lock is advisory, so the timeout does not fail the commit, it
removes the serialization. With 8 sibling gates live the unserialized run was
OOM-killed 20 minutes in. Net effect: 80 minutes elapsed, no commit, and the only
evidence was the working tree still being dirty. **Prevention:** read `tc_acquire`'s
terminal line -- `LOCK_ACQUIRED` and `LOCK_CONTENDED_PROCEEDING` mean opposite things
about serialization and identical things about whether the run proceeds. Before
retrying a killed gate, gate the RETRY on measured MemAvailable and sibling count
rather than on elapsed time; a retry into the same pressure is killed the same way.
And per `wg-when-a-test-runner-crashes-segfault-oom` a killed battery is UNRESOLVED,
never green -- the staged index surviving intact is not evidence the gate passed.

**One-offs (no recurrence vector):** Playwright MCP disconnected mid-session (worked
around with the local install plus a cached-Chromium `executablePath` — the MCP being
down is not the same as Playwright being unavailable); the CLO agent died on a session
rate limit and was re-run; a process-matching probe was correctly blocked by the
repo's own self-match hook — including, fittingly, when this learning's prose
mentioned the flag; and my own idempotence sentinel collided with an earlier edit in
the same file.

## See also

- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`
- `2026-07-22-a-drift-guard-pr-fails-open-in-the-guard-not-the-guarded-code.md`
- `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`
- `workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md`
