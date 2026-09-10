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
