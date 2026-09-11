# Mutation battery — #8016 blocking bwrap probe self-report

Method: every row restores from a **pristine copy** of the committed tree (never `git checkout`,
which restores to HEAD and would silently revert the fix under test). Every mutation asserts it
**landed** via an md5 comparison before the suite runs — a mutation that does not land reports the
baseline, which is indistinguishable from a pass.

**Control:** unmutated tree `223/223 passed, 0 failed` (exit 0). A red control voids every row below.

## SUT rows

| # | Mutation | Result | Suite |
|---|---|---|---|
| M1 | Revert the capture to the `if ! VAR=$(cmd)` form | **KILLED** | 216/223 |
| M3 | Drop the `:-<empty>` sentinel | **KILLED** | 222/223 |
| M4 | Log the raw output instead of `_cred_err_tail`-sanitizing it | **KILLED** | 222/223 |
| M5 | Move the re-emit inside the failure arm (swallows pass-path chatter) | **KILLED** | 219/223 |
| M8 | Append a field *after* `bwrap_err` (breaks the end-anchored trusted region) | **KILLED** | 220/223 |
| M9 | Emit the rollback line twice | **KILLED** | 219/223 |
| M10 | Compute `err_chars` from the **sanitized** value | **KILLED** | 222/223 |

Two of these are worth reading closely rather than counting.

**M3 and M10 each red exactly one test.** That is the signature of a guard that discriminates: the
scenario built for the property is the scenario that catches its removal, and nothing else moves.

**M1 red seven — and for a reason the row did not predict.** The failure is not a missing field, it
is `expected exactly 1 rollback line, got 0`. Reverting the capture form leaves `BWRAP_RC=0` on a
failing probe, so `(( BWRAP_RC != 0 ))` never fires and **the gate stops gating**: it fails OPEN and
ships a broken sandbox rather than rolling back. The rc is therefore a safety property of the gate,
not only a diagnostic field. That finding is now recorded at the capture site in `ci-deploy.sh` so a
future simplification cannot re-introduce it quietly.

## Harness rows

| # | Row | Result |
|---|---|---|
| H1 | Neuter the SUITE: replace the spoken scenario's five field anchors with a bare `DEPLOY_ROLLBACK` | **SURVIVED — EQUIVALENT** |
| H4 | Assert `MOCK_LOGGER_CAPTURE_FILE` / `MOCK_BWRAP_FAIL_RC` / `MOCK_BWRAP_FAIL_STDERR` / `MOCK_BWRAP_FAIL_SLEEP` unset after the scenarios | **PASS** (in-suite) |

**H1 is labelled EQUIVALENT rather than left as a bare survivor.** Weakening an assertion against a
*correct* implementation cannot red — a weaker predicate on a passing subject still passes, so this
mutation changes no verdict by construction. It is recorded as surviving rather than quietly dropped.

A combined run (neutered suite **and** M1-broken SUT) was executed to try to isolate the anchors and
is **inconclusive for that question**: under M1 the rollback line is not emitted at all, so the count
assertion trips before any field assertion is reached.

**Per-anchor discrimination is instead proven by the pre-implementation RED run**, which is the
cleaner evidence and was obtained for free. There the old code *did* emit the rollback line (so the
count assertion passed), and each of the five anchors then reported its own field missing,
independently:

```
(missing field pattern: rc=1)
(missing field pattern: ms=[0-9]+)
(missing field pattern: cstate=)
(missing field pattern: err_chars=[0-9]+)
(missing field pattern: bwrap_err="[^"]*No permissions to create new namespace[^"]*"$)
```

Five separate misses on a line that existed. No anchor is decorative.

## Second round — the axes the first round declared unproven

The first round closed with two axes explicitly declared unproven. Both were then closed with
direct unit tests on `_cred_err_tail`, and mutating those tests is what found the interesting
result.

| # | Mutation | Result | Suite |
|---|---|---|---|
| M11 | Delete `set -o pipefail` from `_cred_err_tail` | **KILLED** (after the harness fix below) | 228/229 |
| M12 | Delete the JWT redaction rule | **KILLED** | 227/229 |

### The fail-closed test was vacuous, and only mutation showed it

The first version of the fail-closed case shadowed **`sed`** on PATH to force a tool death. It
passed. M11 then **survived** — deleting `pipefail` changed no verdict — which is the tell.

The reason: `sed` is the **last** stage of the pipeline, so a failing `sed` sets the pipeline's exit
status with or without `pipefail`. The case was asserting "the last command failed", which is not
the property. `tr` is stage 2 and never last, so its death is observable *only* through `pipefail` —
and a mid-pipeline death is the actual failure being guarded, because it is the one that leaves
later stages returning 0 over partially sanitized bytes.

Re-pointed at `tr`, the discrimination is exact:

| `_cred_err_tail` with `tr` dying | output |
|---|---|
| with `pipefail` (shipped) | `<sanitize_failed>` |
| without `pipefail` (mutant) | *empty string* |

The mutant's output is worse than "partially sanitized". An empty return renders through
`${BWRAP_ERR_SAN:-<empty>}` as **`<empty>`** — i.e. it would report *"the probe said nothing"* when
what actually happened is *"the sanitizer died"*. That is exactly the ambiguity this entire change
exists to remove, reintroduced one layer down.

### A harness note worth keeping

The first fail-closed harness extracted the function under test with
`sed -n '/^_cred_err_tail()/,/^}/p'` and then shadowed `sed`. The shadow broke the *extraction*, so
the function was never defined and the case failed for a reason unrelated to the property. The
extraction now runs under the real PATH and the shadow is scoped to the call, with `hash -r` because
bash caches resolved command paths and would otherwise keep using the real binary.

## Axes NOT edited, stated plainly

- **Sentry delivery** — not implemented in this change; the observability path is
  journald → Vector → Better Stack (`ci-deploy` allowlisted at `vector.toml:178`).
- **Three of the four added redaction rules individually.** M12 isolates the JWT rule; the Stripe,
  webhook-secret and GitHub-PAT rules have their own passing unit cases but no row deletes them one
  at a time, so their individual discrimination is asserted rather than measured.
- **`cstate` provenance.** The field is asserted present, never asserted to reflect the container's
  actual state — the docker mock returns no state, so `cstate=unknown` satisfies every scenario.
- **The `docker inspect` failure path.** `|| true` plus the `:-unknown` default is reasoned about,
  not driven.


---

# Round 3 — the review panel, and what it found that two batteries did not

Five review seats ran against the pushed branch. They found **one live product defect introduced by
my own round-2 fix**, one shipped security gap, and eight test vacuities. All are fixed. The battery
above is retained unedited as the record of what it did and did not cover.

## The live defect — my fix for a bypass over-corrected

The security seat showed the `\b` anchors on rules 2-4 were defeated by any preceding word
character (`ZZZZsk_live_…` does not match). I removed `\b` — and that made the JWT rule match
**mid-word**, so:

```
bwrap: cannot open /usr/lib/x86_64-linux-gnu/libkeyring.so.1  ->  …/libkeyJ.REDACTED
error: /etc/keystore.p12.bak is unreadable                    ->  error: /etc/keyJ.REDACTED …
```

A missing-shared-object error is one of the likeliest real causes of a failing `docker exec … bwrap`
— the 126/127 class this change exists to surface — and the sanitizer was destroying it. Both
batteries were green throughout, because every retention canary in the file (`SENTINEL_LEAK_CANARY`,
`TAILSENTINEL7095`) is a bare `[A-Z_]` token containing no `.`, `:`, `/` or `ey` — i.e. the shape
*least* exposed to realistic over-redaction.

Fixed with `(^|[^A-Za-z0-9])` for the prefix rules (stricter than `\b`: it admits `_`, so
`FOO_sk_live_…` matches) and a literal `eyJ` + 8-char segments for the JWT rule, which is
self-anchoring because `eyJ` is base64 for `{"`. Five retention cases now use the shapes
over-redaction actually eats: a shared-object path, a dotted filename, a `sha256:` digest, a
`host:port`, and an underscore identifier.

## The shipped gap — the premise in my own comment was false

`ci-deploy`'s stdout is **not** dark. It runs under `adnanh/webhook -verbose`, which captures the
hook command's combined output and re-logs it, and `vector.toml:191` allowlists
`SYSLOG_IDENTIFIER="webhook"` next to `"ci-deploy"`. Verified in production: `Verifying bwrap
sandbox...` — a plain `echo` — is queryable in Better Stack under the webhook tag.

So the raw `printf` re-emit was shipping **unsanitized** bytes off-box, seven lines before the same
bytes were sanitized for the `logger` leg. The plan had measured this and said so explicitly
(*"the Task 1 comment must not repeat the discard claim"*); the implementation repeated it anyway.
Both are corrected: the re-emit prints `BWRAP_ERR_SAN`, and the comment now states the measured
topology and the real reason for the dedicated `logger` line (latency, structure, queryability —
not darkness).

## The axis both batteries missed: the helper owns its own verdict

`assert_blocking_probe_line` decides its own pass/fail, so it is disarmable **independently** of
`pass()`/`fail()` and of any assertion-count floor. Measured by the review seat: flipping one
character (`failed=1` → `failed=0`) voids every field anchor in four scenarios with `TOTAL`/`PASS`/
`FAIL` reconciling exactly; replacing the body with an unconditional pass still prints four
`PASS: #8016 …` lines. No verdict-machinery control in the file could see it.

Closed with an in-suite **positive control** that drives the helper with an unmatchable pattern and
requires it to report failure — the pattern `T-7095-3` already established in this same file, which
I should have found rather than re-derived.

## Two findings the seat retracted

It initially reported the head-vs-tail and clamp mutants as survivors; both are in fact **killed** by
the pre-existing `T-7095-3` hygiene test via the Doppler caller. It had region-scoped its verdict to
the 13 `#8016` assertions and filtered out the signal. Recorded because the retraction is the useful
part: `#8016 PASS=13` was true for *every* mutant it ran, killed ones included — the discrimination
lived entirely in the column it was discarding. Same failure as my own battery, mirrored: mine scoped
to mutations I thought of, its scoped to the region it thought mattered.

## Everything else closed

| Gap | Fix |
|---|---|
| `_cred_redact_env_values` had **zero** coverage — the arm protecting `BYOK_ENCRYPTION_KEY` | four cases: bare-hex, hyphenated vendor key, and **both sides** of the 12-byte floor |
| Alternation treated as one rule; narrowing it to `(ghp\|whsec)` leaked six token classes green | one unit case per member |
| `cstate` decorative — mock never answered `inspect`, and the anchor was a bare `cstate=` | mock branch + `cstate=exited` pinned on the rc=137 scenario, where it is the only discriminator |
| `ms` satisfied by a single constant (`1100` passed every arm) | fast scenarios bounded `[0-9]{1,3}`, slow sleep raised to 2.0s — a bound, never a pin |
| `SANDBOX_PROBE_OK` unasserted | asserted in the pass-with-chatter scenario |
| fail-closed harness inherited `pipefail` state from ~2000 lines up | states `set +o pipefail` explicitly; M11 re-scoped to "self-sufficient when sourced", since `ci-deploy.sh:2` covers the deploy path |
| purity scenario's non-ASCII leg vacuous (`\x` unexpanded in `"…"`) | `$'…'` |
| `_cet` extracted only `_cred_err_tail` | extracts both — caught by my own new value-arm cases failing |

**H1 is deleted as a row.** Not because it is equivalent, but because "cannot red by construction"
describes *every* test-side mutation including the two that genuinely disarm four scenarios. Test-side
mutations need a composite or an in-suite positive control; the control above is the durable answer.

**Final: 245/245, exit 0, stable across three consecutive runs. `shellcheck -S warning`: no findings
in changed regions.**
