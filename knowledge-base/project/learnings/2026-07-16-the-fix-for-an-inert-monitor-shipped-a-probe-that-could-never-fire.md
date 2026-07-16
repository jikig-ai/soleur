---
module: apps/web-platform/infra (zot registry, Better Stack heartbeats)
date: 2026-07-16
problem_type: integration_issue
component: infrastructure
symptoms:
  - "A feeder built to arm an inert monitor could never emit a single beat"
  - "26 green assertions certified a probe that always failed"
  - "systemd timer interval drifted to 72.6s against a 90s monitor deadline"
root_cause: wrong_assumption
severity: critical
tags: [heartbeat, observability, curl, systemd, test-fixtures, false-green, mutation-testing]
issue: 6537
pr: 6540
synced_to: [review, work]
---

# The fix for an inert monitor shipped a probe that could never fire

## Problem

`betteruptime_heartbeat.registry_prd` was provisioned `paused = true` on 2026-07-07 as a bootstrap
step, to be unpaused "once the web-host probe cron ships". The cron was never written, so the
registry — a deny-all, no-SSH host whose only liveness signal is a push beat — had no liveness alarm
for 9 days. #6537 filed it; PR #6540 fixed it.

The fix shipped a feeder that **could never ping**, and every test was green over it.

```bash
# The feeder, as first written:
curl -fsS -m 10 -o /dev/null "http://${private_ip}:5000/v2/" || PROBE_RC=$?
if [ "$PROBE_RC" -eq 0 ]; then curl ... "${liveness_heartbeat_url}"; fi
```

zot auth-gates `/v2/` (`"auth": {"htpasswd": …}` + `"defaultPolicy": []`), so an anonymous probe
gets **401**. `curl -f` exits **22** on any HTTP >= 400. So `PROBE_RC` was never 0, the guard never
opened, and the heartbeat was never pinged. #6537 would have closed with the registry still
unmonitored — the identical end state it was filed to fix, now with a green CI guard over it.

Measured, not reasoned:

```
$ curl -fsS -m 5 -o /dev/null http://127.0.0.1:8401/v2/   # a 401 responder
curl: (22) The requested URL returned error: 401
exit=22            <- guard never opens => NEVER PINGS
$ curl -sS -m 5 -o /dev/null http://127.0.0.1:8401/v2/
exit=0             <- no -f: correctly reads 401 as alive
```

## Root cause

**The repo had already learned this, ~400 lines below in the same file.** `cloud-init-registry.yml`'s
boot readiness loop says verbatim:

> `# Readiness: /v2/ answers (401 unauth IS healthy — reachable, auth-gated). curl -s`
> `# without -f returns 0 on any HTTP response, non-zero only on connection-refused.`

A second probe of the *same endpoint* was written into the *same file* without reading the contract
the file already documented. The feeder's own comment even reasoned about the wrong failure mode
("`-f`: a 5xx from a wedged zot is NOT liveness") — 5xx was considered; 401 was not.

**The fixture encoded the bug.** The test stub modelled "zot answers" as `curl` **exit 0** — a code
the real host never produces — so the suite was structurally incapable of observing the defect:

```bash
*10.0.1.30:5000*)   exit "${STUB_PRIVATE_RC:-0}" ;;   # T1 = a positive control for a code
                                                      # production never returns
```

## Solution

Discriminate on the **status code**, and make the fixture model the real contract.

```bash
#   200/401 -> zot answered        => alive (401 proves it is up AND enforcing auth)
#   5xx     -> wedged/erroring zot => NOT liveness (what -f was reaching for)
#   000     -> no HTTP response    => connection refused / timeout / absent NIC
HTTP_CODE=$(curl -sS -m 10 -o /dev/null -w '%%{http_code}' "http://${private_ip}:5000/v2/" 2>/dev/null || true)
case "$${HTTP_CODE:-000}" in
  200|401) curl -fsS -m 10 -o /dev/null "${liveness_heartbeat_url}" || true ;;
esac
```

The stub now models `-f` (exit 22 on >=400), `-w` (only `-w '%{http_code}'` prints the code), and
`-m` (hangs without it). T1 is the **401** case. Re-introducing `-f` now fails T1 behaviorally, not
just structurally.

## Key insights

### 1. A fixture must model the response CONTRACT, not a convenient exit code

When a stub stands in for an external service, model what the service actually returns to *this*
request: status codes, auth posture, and which flags change the exit. An exit-code model is a guess
about the service dressed as a fact, and it makes the suite green in exactly the case that matters.

**Litmus, before writing any probe:** "what does this endpoint return to an *unauthenticated* GET?"
— then `grep` the same file for an existing probe of the same endpoint. The contract is very often
already written down within a screen or two of where the new code lands.

### 2. systemd's default `AccuracySec` is 1 MINUTE (genuinely undocumented here — no prior learning)

An `OnUnitActiveSec=60s` timer fires anywhere in `[elapse, elapse+AccuracySec]`, so the interval is
`60s + delta`, structurally bounded at **120s** — against a monitor's 60s period + 30s grace (a 90s
deadline). Measured A/B on the same unit shape:

```
AccuracySec unset (the default):  60.024s  61.959s  72.568s  66.453s   <- drifts
AccuracySec=1s:                   61.005s  60.997s  60.989s  61.003s   <- +/- 16ms
```

72.6s is already inside the deadline's margin; the bound is over it. **Pin `AccuracySec` well inside
any push-monitor's deadline.**

**And: a precedent's greenness is not proof of its correctness.** `inngest-heartbeat.timer` runs the
identical cadence against an identical 60/30 monitor, is live and `up`, and carries the identical
latent defect — it is green *on margin*. systemd's coalescing offset is derived from the **boot ID**
(`perturb = (boot_id.qwords[0] ^ boot_id.qwords[1]) % USEC_PER_MINUTE`), so its greenness is evidence
about one host's current boot and is **re-rolled by every immutable redeploy**. A measured-green first
beat would not generalize to the next boot. Both timers now pin it.

### 3. An assertion scoped to a FILE cannot certify a property that lives on a LINE

Three instances in one PR, all green, all certifying the wrong property:

| Assertion | Certified | Missed |
|---|---|---|
| `readFile(f).includes(pattern)` | the name appears *somewhere* | a **comment** satisfies it — so "delete the feeder and CI goes RED" was **false** for the one live heartbeat |
| `pattern.length > 8` | **length** | `"permissions"` — 11 chars, 9 hits in the same file — passes |
| `grep 'curl.*-m'` over the file | *some* curl is bounded | dropping `-m` from the **probe** alone stays green (the ping's `-m` satisfies it) |

Fixes: match the **arming construct** (`systemctl enable --now <unit>`) on a **comment-stripped**
view; assert pattern **shape + bounded occurrence count**; scope the `-m` grep to the probe line and
pair it with a behavioral test that hangs the stub when `-m` is absent.

**This is a RECURRENCE of `cq-assert-anchor-not-bare-token` / "narrowing is not anchoring"** — and it
recurred *inside the module written to kill prose-satisfies-guard*. See
[[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]] and
[[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]].

**Disposition (per the repo's own doctrine — a recurring documented class warrants a gate, not a
fourth restatement):** the honest answer is that **no cheap mechanical gate exists** for "this
assertion is scoped to a file but names a line-level property" — it needs intent. What *is* cheap and
did work here: the review-spawn prompt naming the class explicitly, plus mandatory mutation-testing.
Both are already in `review/SKILL.md`. The residual gap is that a **new** guard's own assertions are
not themselves mutation-tested by anything except a reviewer who is told to.

### 4. A mutation that does not mutate reports a false "the guard works"

```
$ sed -i 's|200|401)|200|401|503)|' $CI
sed: -e expression #1, char 15: unknown option to `s'
--- M-B: accept 5xx as liveness — T4 must RED
=== 31 passed, 0 failed ===          <- reads like "guard caught it"; the file was never mutated
```

A failed `sed` leaves the SUT pristine, and the suite prints the **baseline**. That is a *null*
result wearing a green result's clothes, and it is trivially mistaken for "the mutation was caught".

**Prevention: assert the mutation LANDED (grep the mutated token) before running the suite.** If a
mutation run reports the baseline pass-count, treat it as un-run, not as evidence.

### 5. A post-merge fix must not be documented in the present tense

ADR-096 and `model.c4` said the heartbeat "**is armed**" while the arming phase (reprovision →
measure a beat → API unpause) is post-merge and unrunnable pre-merge. Nothing catches it: the guard
compares source `paused` to source `paused`, and `ignore_changes = [paused]` decouples both from live.
If Phase 4 stalls, the repo asserts an armed monitor over a paused one — **verbatim #6537, rebuilt
inside the PR fixing it.**

**Rule: the doc claim must be true AT MERGE and true IF THE POST-MERGE PHASE NEVER RUNS.**

### 6. Assert the discriminator, never the count

Written into the manifest and the ADR: *"`git grep -c GIT_DATA_HEARTBEAT_URL` returns **2 hits**, and
NEITHER is a feeder."* No scoping yields 2 (repo-wide 6 on main / 20 on HEAD; `apps/` 3 / 4); the
sentence claimed exhaustiveness while omitting the single most on-thesis hit — a `TODO` comment
describing the feeder that does not exist; and the same commit that wrote it added more hits, so it
was **self-invalidating on arrival**.

The executable layer got it right by asserting the **discriminator** (bare name matches / dereference
does not) and never a literal. Same PR, same class: the plan cited a `zot_health` field that does not
exist. **RECURRENCE of the #6424 comment-fix class** —
[[2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes]].

### 7. A forcing function must enumerate every delivery route — including the one you just added

The unfed-row tripwire counted shell dereferences (`$VAR`) of a Doppler secret. But this PR's own
feeder **bakes** its URL via `templatefile` and dereferences nothing — so a sibling feeder built the
canonical way would land silently while the tripwire stayed green. The guard was blind to the route
the same PR made canonical.

Fix: probe both routes — `$VAR`/`${VAR}` deref, **and** `<var>_url = betteruptime_heartbeat.<name>.url`
(excluding `value = …`, which is a `doppler_secret`/`output` definition rather than a delivery).

### 8. Two silent foot-guns

- **`[^\n]` in POSIX ERE is a bracket expression excluding backslash and the letter `n`** — not "any
  char but newline". grep is line-oriented, so `.*` is correct. `curl[^\n]*-m` could not cross
  `-o /dev/null` (it contains an `n`), which made the **negative** assertions pass vacuously: a broken
  regex never matches, so `! grep` always passes.
- **Terraform `templatefile` scans `%{` as a directive**, including inside comments — so
  `-w '%{http_code}'` must be written `%%{http_code}` or the render fails outright.

### 9. Workflow

- **Review value concentrated where the prompt named THIS repo's documented failure classes and
  demanded mutation-testing.** A generic "review this PR" would not have found the P1; it took an
  agent that went and checked what the endpoint actually returns.
- **A source-only read can "refute" a live-state claim and be wrong.** An agent read `paused = true`
  from `inngest.tf` and marked the "inngest is live-unpaused" claim **REFUTED**. The live API says
  `paused=false, up`. The refutation was itself refuted by self-pulling the API — and source-vs-live
  is precisely what the ADR is about. **When an agent refutes a claim about LIVE state using SOURCE,
  re-pull the live state before believing either side** (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **Counter-example worth naming:** the C4 freshness gate correctly caught an un-regenerated artifact.
  Gates that compare an artifact to its source work; gates that compare prose to intent do not.

## Session Errors

1. **[forwarded from plan phase] `iac-plan-write-guard.sh` blocked two Writes on the phrase
   `out-of-band`**, which the plan quoted only in order to delete. — Recovery: ran the hook against
   the content to diagnose, then removed the trigger phrase rather than using the `iac-routing-ack`
   bypass. **Prevention:** diagnose a hook denial by running the hook against your own content; reach
   for the ack-bypass only when the content genuinely warrants it, not to silence a true positive.
2. **The feeder's `curl -f` against an auth-gated 401 meant it could never ping (P1).** — Recovery:
   status-code discrimination. **Prevention:** grep the same file for an existing probe of the same
   endpoint before writing a new one; the contract was already documented 400 lines away.
3. **The test fixture encoded the P1** (exit-code model instead of the response contract). —
   Recovery: the stub now models `-f`/`-w`/`-m` and status codes. **Prevention:** model the response
   contract; ask "what does the real service return to THIS request, unauthenticated?"
4. **`[^\n]` in ERE made the negative assertions vacuous.** — Recovery: `.*`. **Prevention:** grep is
   line-oriented; `[^\n]` never means "not newline".
5. **`AccuracySec` unset → measured 72.6s against a 90s deadline.** — Recovery: `AccuracySec=1s` on
   both timers + a structural assert. **Prevention:** pin AccuracySec inside any push-monitor deadline.
6. **`checkFeeders` whole-file substring → a comment satisfied the guard.** — Recovery:
   arming-construct match on a comment-stripped view. **Prevention:** anchor on the construct that
   *causes* the behavior, never the name of the thing that has it.
7. **The feeder probe was blind to the templatefile-bake route this PR canonized.** — Recovery: probe
   both routes. **Prevention:** when you add a delivery route, re-check every guard that enumerates
   routes.
8. **ADR-096 + model.c4 asserted the armed state as fact while Phase 4 is unrun.** — Recovery:
   future-tense. **Prevention:** the claim must be true at merge AND if the post-merge phase stalls.
9. **The "2 hits" count was wrong under every scoping and self-invalidating.** — Recovery: dropped
   the number. **Prevention:** assert the discriminator, never the count.
10. **`pattern.length > 8` certified length, not specificity.** — Recovery: shape + bounded
    occurrences. **Prevention:** a proxy metric is not the property.
11. **The `-m` assert was file-scoped, so an unbounded probe stayed green.** — Recovery: scoped to the
    probe line + T5 proves it behaviorally. **Prevention:** file-scope cannot certify a line property.
12. **4 fixtures missing the required `feeder` (TS2741 x4)** — invisible because nothing typechecks
    `plugins/**/*.ts` (70 files; a `lib`-wide `tsc` surfaces 26 pre-existing errors). — Recovery:
    fixtures fixed inline; the repo-wide gap tracked on #6549. **Prevention:** a required field on a
    type in an untypechecked directory is an unenforced claim — the same class as the prose it replaced.
13. **Census `.toBe(6)` would red `main` behind a CORRECT sibling.** — Recovery: removed; the set
    assertions already cover it with a better message. **Prevention:** see the all-members-drift-guard
    class in `review/SKILL.md`.
14. **`gitGrepCount` could sum to `NaN` and report NO violation** — a silent false-green inside the
    module built to kill silent false-greens. — Recovery: throws on an unparseable count.
    **Prevention:** any `Number()` feeding a `> 0` gate needs a finite check.
15. **The ADR-103 cross-link was derived from the ADR's TITLE, not its filename → broken link.** —
    Recovery: caught by a link check before commit. **Prevention:** resolve ADR links against `ls`
    output, never against the title.
16. **A mutation `sed` silently no-op'd and the suite reported the baseline as a mutation result.** —
    Recovery: re-ran with a working delimiter. **Prevention:** assert the mutation landed before
    trusting the run.
17. **A test named "live" derived from SOURCE `paused`.** — Recovery: renamed to `SOURCE-unpaused`.
    **Prevention:** name a test for what it measures, especially in a module whose premise is that
    source != live.
18. **The plan cited a `zot_health` field that does not exist.** — Recovery: read the actual emit and
    listed its real fields. **Prevention:** identifier names in prose are claims; grep them.

## Related

- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]]
- [[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]]
- [[2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes]]
- [[2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument]] — same host;
  its `/usr/sbin`-not-on-cron's-PATH trap is a second, independent reason this feeder is a systemd
  timer rather than a `cron.d` entry.
- [[2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days]] — #6400, the blindness the
  private-IP probe choice exists to avoid rebuilding.
- ADR-116 (executable heartbeat arming) · ADR-096 · ADR-103 · #6548 · #6549
