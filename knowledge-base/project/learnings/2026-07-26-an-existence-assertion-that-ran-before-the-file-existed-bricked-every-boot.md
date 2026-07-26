---
title: "An existence assertion that ran before the file existed would have bricked every boot — and my mutation battery could not express the mutation"
date: 2026-07-26
issue: 6969
pr: 6970
category: workflow-patterns
tags: [set-e, ordering, mutation-testing, vacuous-assertions, credential-redaction, boot-path]
---

# An existence assertion that ran before the file existed

## Problem

`soleur-web-2` booted DARK at cloud-init `stage=doppler_download`. The Sentry fatal carried only
the stage name: the Doppler CLI's stderr and exit code were discarded at the source, and the host's
journald never reached Better Stack because Vector's token comes from the very fetch that failed.
No hypothesis could be discriminated after the fact.

The PR that fixed this shipped, at review time, a defect that would have made things **strictly
worse**: it would have darkened *every* new host, unpaged.

## The P0

The change added `test -x` existence assertions for two heredoc-authored helpers. They were placed
in the file's upstream `STAGE=assert` block — which sits ~120 lines **above** the heredocs that
create those files.

`soleur-host-bootstrap.sh` is a straight-line `/bin/sh` script under a top-level `set -e`. So on
every fresh boot:

1. `test -x /usr/local/bin/soleur-boot-emit` fails (the file is authored 120 lines later)
2. `set -e` aborts at `STAGE=assert`
3. `/run/soleur-hostscripts.ok` is never written
4. the cloud-init terminal block `poweroff -f`s the host

And the failure **cannot report itself**: the file being asserted *is* the Sentry emitter. The host
dies silently, from the PR whose entire purpose is ending silent host deaths.

**Why nothing caught it.** The suite's assertion was:

```sh
if grep -qE "FAILED_FILE=$h" "$BOOT" && grep -qF "test -x /usr/local/bin/$h" "$BOOT"; then
```

Two independent whole-file greps. **Co-presence is not ordering.** The assertion passed the entire
time. No test executed the bootstrap top-to-bottom — the suite `awk`-extracts the two heredoc
*bodies* and runs those in a sandbox, so the whole class "helper never created / created too late /
not executable" is structurally invisible to it.

The fix is a line-number comparison:

```sh
a_line="$(grep -nF "test -x /usr/local/bin/$h" "$BOOT" | head -1 | cut -d: -f1)"
c_line="$(grep -nF "cat > /usr/local/bin/$h <<" "$BOOT" | head -1 | cut -d: -f1)"
[ "$a_line" -gt "$c_line" ] || fail
```

## Key insight: a self-authored mutation battery measures the mutations you imagined

Before review, this PR carried a 23-mutation battery reporting **23/23 detected**. That green was
indistinguishable from the green of a fully-covered suite. It could not have caught the P0, because
"move the assertion above the heredoc" was not a mutation its author thought to write — the harness
could not even express it.

A review pass then found **21 further surviving mutants** in the same suite, including:

- `cond=` emitted but never asserted — the field distinguishing a hang from an auth failure
- `attempts=N` printed the *configured* value, never a counted invocation, so a loop that stopped
  early made the shipped detail **lie**
- deleting `chmod 700` / `chmod 600` — both added in response to an earlier review round — was green
- a typo in the production DSN splice (`@@SOLEUR_SENTRY_DS@@`) darkened the entire channel: green,
  because the test harness performed its **own** splice instead of exercising the shipped one

**Rule:** when a PR arrives carrying its own mutation matrix, that matrix is evidence about the
mutations, not about the tests. Ask an independent reviewer to *find the vacuity the battery
missed*, explicitly instructing them **not** to re-run its mutations.

Corollary, and the reason the harness is now committed at
`apps/web-platform/infra/doppler-download-error-channel.mutation.py`: an uncommitted matrix is a
claim nothing re-checks, and "mutation-verified" in a comment reads as protection while
discouraging the next reader from checking.

## Four ways an assertion certified nothing

All four shipped green in the same suite; all four were found by measurement, not reasoning.

1. **A negated class that excludes the guarded shape.** `grep -qE '^\s*(echo|printf)[^>]*$'` was
   meant to stop the helper writing to the env file. `[^>]*$` structurally excludes every line
   containing `>` — i.e. precisely the harmful shape. `printf 'INJECTED=x\n' >> "$OUT"` passed and
   landed in the file `docker run --env-file` ingests. Fixed by *counting write sites* instead of
   pattern-matching prose.

2. **A fixture whose filler displaced the content under test.** The adversarial sanitizer fixture
   appended 4 KB of junk *after* the interesting bytes. The sanitizer keeps the **last** 180 bytes,
   so the detail under assertion was 180 `J` characters — four sanitization assertions were reading
   filler. Split into one fixture per property, each with a precondition self-check that fails as a
   clear FIXTURE error rather than a phantom pass.

3. **A fixture calibrated to the shape that works.** The Doppler token scrub used
   `dp\.[a-z]*\.[A-Za-z0-9_-]*` — a class excluding `.`, so it stopped at the second dot. A
   config-scoped service token is `dp.st.<config>.<entropy>`: **four** segments. The rule redacted
   the *config name* and preserved the credential. The test fixture used a three-segment token,
   which the broken rule handled perfectly. Ask of every security fixture: *does it instantiate the
   shape production actually emits?*

4. **A second copy of a guarded literal disarms the guard.** Adding a `RETRY_DETAIL` capture created
   a second occurrence of the literal that a presence-grep guarded, so neutering either one alone
   left the other satisfying it. This class is already in the review catalogue; it recurred anyway,
   *inside the fix for a different finding*. Presence-greps over a literal that can legitimately
   appear more than once must **count**, not detect.

## The credential path no regex can close

The PR captured `docker run` stderr into the diagnostic channel. `docker run --env-file` is handed
the entire prd secret set, and docker's env-file parser quotes the offending line back verbatim
(`no variable name on line '<line>'`, `invalid utf8 bytes at line N: [<decimal bytes>]`). Any prd
secret containing a newline — a PEM key, a service-account JSON — produces such a line.

Redaction cannot fix this: **a secret value is arbitrary text, not a matchable shape.** Measured:
prd is 129 keys / 129 lines today, so the leak was latent and would go live with the first
multi-line secret. The capture was removed; wiring it safely means classifying the failure without
echoing the stream (tracked in #6971).

Generalisable: when a diagnostic captures the stderr of a process that was handed secrets, ask what
that process *echoes back* on error — not just what it writes on success.

## Two measurement traps

- **`curl -m` is per-transfer, not total.** `curl -m 10 --retry 3` worst case is ~47 s, not 10 s
  (measured: `curl -m 2 --retry 3` against an unreachable host took 7.0 s). Two unbounded in-loop
  emits added ~94 s of *failure-correlated* latency to a boot window — slowest exactly when called,
  since the faults that fail a Doppler fetch are the same ones that hang a Sentry POST.
- **A "this citation had already rotted" claim is itself a claim.** The PR justified replacing a
  `cloud-init.yml:825 of 835` coordinate by asserting it had rotted. It had not: on `origin/main`
  the file was exactly 835 lines and line 825 was exactly the cited anchor. *This* change shifted
  it. Verify against `main` before writing the justification.

## Session Errors

- **`test -x` assertions placed above the heredocs that author the files.** Recovery: moved below
  both, under `STAGE=assert_baked`. **Prevention:** `AC-F3b` now compares line numbers; the review
  spawn prompt should ask "does any existence assertion precede its creation in a `set -e` script?"
- **`grep -q '@@' file && { false; }` would abort the boot on a CLEAN file** (an AND-OR list's own
  status is the statement's). Recovery: rewrote as `if`. **Prevention:** already covered by the
  documented AND-OR class; caught during work.
- **Token scrub fixed in the emitter but not the helper.** Recovery: aligned both to the in-repo
  `redact.ts` pattern. **Prevention:** when a rule exists in two layers, mutate each independently —
  a shared defence masks a single-layer regression.
- **A review fix (URI-userinfo redaction) ate docker image refs** (`img:tag@sha256:` parses as
  userinfo). Recovery: anchored to `://`. **Prevention:** every redaction rule needs a fixture in the
  *preserve* direction, not only the *redact* direction.
- **Byte budget failed at 23,860/23,700 — from my own explanatory comment.** Recovery: moved the
  rationale to the ADR (baked, free) and trimmed `cloud-init.yml` to two lines. **Prevention:**
  `user_data` comments cost cap bytes; rationale belongs in baked files or the ADR.
- **`T5a` was vacuous AND fail-open**: `find … | grep -q` (the SIGPIPE shape this file's own header
  bans) plus a `-newer` reference the stub always rewrote later, so it could never be true.
  Recovery: rewrote to the sibling's shape. **Prevention:** lint a suite against its own stated
  prohibitions — this file's whole thesis is that a green assertion can be worth nothing.
- **The mutation harness scanned only stdout**, while the suite prints `[FAIL]` to stderr — reporting
  **all 15 mutants as SURVIVED**. Recovery: scan both streams. **Prevention:** a harness that reports
  100% survival is far more likely broken than the code being that untested; treat it as a harness
  bug until proven otherwise.
- **A background-task notification reported exit code 0 for a run that exited 1.** The notification
  reflects the trailing `echo`, not the command. Recovery: read the rc file; found a real regression
  (`sentry-zot-mirror-fallback-alert-op-contract`). **Prevention:** for `cmd > log; echo $? > rc`,
  the rc FILE is the signal — never the notification.
- **Ran the wrong gate.** `scripts/test-all.sh` does not cover `apps/web-platform/infra/`, where
  nearly all of this diff lives; an ad-hoc `for f in infra/*.test.sh` loop is not the CI-registered
  set either. Recovery: `run-registered-suites.sh`, which derives its list from
  `infra-validation.yml`. **Prevention:** the runner's own epilogue says this — read it.
- **Three citations rotted by this change's line shifts** (`encryption-posture-ledger.json`, the
  posture audit, a learning file). Recovery: re-pointed and verified each new coordinate resolves to
  the cited content. **Prevention:** after editing a file, `grep -rn '<basename>:[0-9]'` and fix
  every hit in the same cycle.
- **Suite briefly RED (13 failures)** after hardcoding `/run` with no test seam. Recovery: added
  `SOLEUR_DOPPLER_ERRDIR` (default = the real host path). **Prevention:** a production path change
  needs its seam in the same edit.
- `mkdir -p -m 700` → SC2174. One-off; rewrote as `[ -d ] || mkdir -m 700`.
- Repeated perl/python anchor failures authoring the harness. One-off; switched to deriving anchors
  from the file and asserting each matches exactly once.
- **Forwarded from the plan phase:** a PreToolUse block on `manual-infrastructure` framing (a
  proposed serial-console fallback — correctly caught by `hr-no-ssh-fallback-in-runbooks`); three
  dangling cross-references; four plan premises falsified by deepen; one `sleep`-based wait blocked
  by the shell guard.
- **Not ours:** `workspaces-luks-loopback.test.sh` fails `LOOPBACK_UNAVAILABLE` locally (needs
  root/sudo). Reproduced identically on pristine `origin/main` — pre-existing and environmental.

## Related

- ADR-147 — the contract this PR froze
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the class this PR reproduced
- `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md` — recurred here
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
- `2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md`
