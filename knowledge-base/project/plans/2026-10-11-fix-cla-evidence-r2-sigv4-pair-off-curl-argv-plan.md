---
title: "security(cla-evidence): R2 SigV4 key id and secret ride curl argv via --user in two upload scripts"
type: fix
date: 2026-10-11
slug: cla-evidence-r2-sigv4-pair-off-curl-argv
branch: feat-one-shot-9756-cla-evidence-sigv4-argv
issue: 9756
closes: 9756
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(cla-evidence): move the R2 SigV4 key id and secret off curl argv onto the stdin config

## Overview

Two scripts on the CLA legal-evidence path hand curl the R2 S3 access key id and secret as
`--aws-sigv4 "aws:amz:auto:s3" --user "$ID:$SECRET"`. Any local reader of `/proc/<pid>/cmdline` or `ps`
sees the pair for the life of the request:

- `apps/cla-evidence/scripts/r2-conditional-put.sh` (the CI upload primitive that `upload-evidence.sh` and
  `upload-bypass.sh` exec), at `put_once`.
- `apps/cla-evidence/infra/bootstrap.sh` (the one-shot bootstrap), at the Step 1 probe PUT.

The Rule E `-u`/`--user` arm added in S2 of the argv-bearer sweep (tracker #9597, ADR-280) baselined both
files as two tracked rows owned by this issue. This plan converts both and removes the rows. It is one slice,
one PR, and touches nothing of the library-gap, URL-path-secret or tainted-egress follow-ups.

Shape of the fix: a new app-local sourced helper, `apps/cla-evidence/scripts/_r2-sigv4-curl.sh`, owns the only
`curl --aws-sigv4` in `apps/cla-evidence`. It judges both values, pins the URL to the canonical R2 host, and runs
`curl --disable --noproxy '*' <caller args> --aws-sigv4 aws:amz:auto:s3 --config - <url>` with
`user = "<id>:<secret>"` fed by a process substitution (never a pipe). A malformed value makes zero requests,
prints a value-free line and `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`, and
returns non-zero. Both scripts source it. This mirrors `apps/cla-evidence/scripts/_cf-admin-token.sh`
(`_cf_admin_curl`, same directory, same sourced-helper shape, same suite convention).

Converting the two files forces three things the brief did not name; each is a hard CI consequence, not
scope growth (see Research Reconciliation): the `--changed` lint drawdown (Rules A and D) on both files, removal
from the A/B/C and D baselines, and a rewrite of the two suites that pin the baseline E rows, because emptying
baseline E breaks their anti-vacuity floors.

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view 9756`: OPEN, no closing PR. Tracker #9597 is already
CLOSED (the plan references it with `Ref`, never `Closes`). Cited paths exist on this branch:
`apps/cla-evidence/infra/bootstrap.sh` (315 lines), `apps/cla-evidence/scripts/r2-conditional-put.sh` (195),
both baseline rows (`scripts/lint-shell-trace-credential-refusal-e.baseline.txt` lines 15-16 and the ceiling
table lines 11-12). ADR corpus grep (`argv`, `bearer`, `stdin config`): ADR-280 owns the pattern and names this
issue as the owner of the two rows; no ADR rejects an app-local helper. The proposed mechanism was measured on
this host (curl 8.22): `--aws-sigv4 aws:amz:auto:s3` with `user = "id:secret"` on `--config -` signs correctly
(the `Authorization` header carried `Credential=<id>/<date>/auto/s3/aws4_request`). Runner curl is 8.5; the plan
re-measures there (AC 12). Repo precedent for the same shape: `scripts/web2-rebirth-recovery-check.sh:91` and
`apps/web-platform/infra/workspaces-luks-provision.sh:565` already send a SigV4 `user =` line on stdin.

**Property List (Phase 0.6b).** P1 the pair appears in no argv of any SigV4 curl in `apps/cla-evidence`.
P2 a malformed value is refused before any request, with the marker and a non-zero exit. P3 a refusal is loud and
never classified as retryable, duplicate (412) or WORM-idempotent. P4 the two baseline rows and ceiling rows are
gone and the gates that pinned them stay meaningful on an empty baseline. P5 the owning suites assert the pair is
absent from every recorded argv, from real recorded wire data. P6 PUT behaviour (key, `If-None-Match: *`, status
classification, retries, WORM arm) is byte-for-byte unchanged.

**Cut List (Phase 0.6b).**

| Mechanism proposed or suggested | Property it would buy | Disposition |
|---|---|---|
| Add a `user =` mode to `scripts/lib/bearer-curl.sh` | P1 | Cut. The library is header-only (ADR-280 Decision 1), library gaps are an explicit non-goal, and `_cf-admin-token.sh` already sets the app-local precedent. |
| Mirror the refusal marker to Sentry (CLO suggestion) | P3 loudness | Cut. The evidence job is a bash step with no Sentry client; adding one adds an egress and a credential to the job that holds the R2 pair. Loudness is bought by the non-zero exit and the `::error::` annotation, the same surface every other failure of this step already uses (the 32/64 length preflight, fatal 4xx). |
| Trim trailing whitespace before judging (ADR-280 item 7) | none here | Cut. The pre-existing exact 32/64 length preflight already refuses a value with a trailing blank; trimming would change which values pass. |
| New ADR | none | Cut (CTO). ADR-280 gets a short addendum recording the conversion and the final baseline E state. |
| Hex-only guard (CTO suggestion) | P2 | Narrowed to the ADR-280 alphabet. A vendor-format guard refused real tokens in #9972; the vendor format (32/64) is already checked by the existing length preflight, so the new guard only needs to close the config-line injection bytes. See Decisions D3. |

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`:
  process substitution never a pipe (`pipefail` turns a stub that never reads into 141); pin the destination before
  the credential is read.
- `test-failures/2026-10-11-a-credential-guard-modeled-on-the-vendor-format-refused-the-vendors-next-format.md`:
  guard by the RFC alphabet, not the vendor format; `lint-shell-trace-credential-refusal.test.sh` requires every
  `_bearer_ok() {` copy to be byte-identical, so the helper must not reuse that name.
- `test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md` and
  `test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`: a stub
  that never reads stdin certifies nothing about the credential path; the new stubs drain and record stdin.
- `2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-...md`: new functions go below the xtrace
  refusal block; append `|| VAR=""` at substitutions under `set -e`; run suites in an `ubuntu:24.04` container
  because CI curl and bash differ from local.
- `2026-10-09-my-gate-pins-were-green-and-left-position-wiring-and-the-request-itself-unpinned.md` and
  `security-issues/2026-10-06-i-claimed-a-mechanism-from-an-outcome-and-my-guards-pinned-the-builder-not-the-wire.md`:
  pin the wire the request sends, not the builder; the plan's suites assert on recorded argv and recorded stdin.
- `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md`: R2 S3 creds are a 32-char key id plus a 64-char secret;
  keep both length asserts.

**Repo facts the plan depends on.**

- CI runs `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  (`.github/workflows/ci.yml:442`). `--changed` bypasses every baseline ("a script that edits a listed script must
  remediate it"). Running the lint on the two explicit paths today reports six violations: Rule A (no xtrace
  refusal) and Rule D (curl not transport-confined) and Rule E, for each file.
- The A/B/C baseline (`scripts/lint-shell-trace-credential-refusal.baseline.txt`) and the D baseline
  (`scripts/lint-shell-trace-credential-refusal-d.baseline.txt`) each list both files.
- `.github/workflows/cla-evidence.yml` runs `upload-evidence.sh` / `upload-bypass.sh` with plain `run:` steps and
  `set -euo pipefail`; a non-zero exit turns the step red. The merge gate for CLA is a different check
  (`license/cla`), so a red evidence step blocks nothing and is the only signal (unchanged by this plan).
- `upload-evidence.test.sh` and `upload-bypass.test.sh` stub `curl` on PATH. The bypass stub reads the **last
  positional argument as the URL**, and neither stub reads stdin. The helper therefore keeps the URL last and the
  suites gain recording stubs.
- `bootstrap.sh` has no suite. `scripts/test-all.sh` auto-registers `apps/cla-evidence/scripts/*.test.sh` (a suite
  placed in `apps/cla-evidence/infra/` would be orphaned; only `main.test.sh` runs there).
- Editing `apps/cla-evidence/**` does not match any production-apply trigger: `apply-web-platform-infra.yml`
  pushes only on `apps/web-platform/infra/**`; `apply-github-infra.yml` only on `infra/github/**`. The
  `infra-validation.yml` matrix runs fmt/validate/`main.test.sh` for `apps/cla-evidence/infra` on a path touch;
  it never applies and `main.test.sh` does not read `bootstrap.sh`.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality | Plan response |
|---|---|---|
| "Remove both rows from baseline E and the ceiling table" is the whole lint fallout. | Both files are also listed in the A/B/C baseline and the D baseline, and CI runs `--changed`, which bypasses baselines. Touching either file fails Rule A and Rule D unless remediated. | Add the xtrace refusal (Rule A) to both scripts, satisfy Rule D through the helper, and delete both rows from the A/B/C and D baselines in the same change. |
| "Owning suites must assert the pair is absent from every recorded argv." | `r2-conditional-put.sh` is owned by `upload-evidence.test.sh` and `upload-bypass.test.sh`, whose stubs record neither argv nor stdin. `bootstrap.sh` has no suite. | Give both suites a recording stub (argv and stdin, drained); add `bootstrap-r2-probe.test.sh` (executes the real bootstrap up to the probe under stubs) and `_r2-sigv4-curl.test.sh` (helper contract). |
| "Same pattern the earlier slices use" (`bc_curl`, `scripts/lib/bearer-curl.sh`). | The library only builds `header` config lines; the `user =` form exists inline in `scripts/betterstack-query.sh` and as an app-local helper in `_cf-admin-token.sh`. | App-local helper per D1; no library change. |
| Emptying baseline E is a pure deletion. | `scripts/lint-shell-trace-credential-refusal.test.sh` fails its anti-vacuity floor (`CC_LISTED -lt 1`) and every census-ceiling mutation row reads "the first real baseline row" (M-raise, M-dup, M-nan, M-empty-count, the control). `tests/scripts/test-argv-bearer-sweep.sh` S5 Guard 1 pins `S5_WANT_ROWS` to the two files and pins `#9756` in both headers, and exempts `apps/cla-evidence/*` from the owner-line rule. | Rewrite those rows over a synthesized baseline/ceiling pair (Guard 2). |
| Baseline E header text says the two rows are owned by #9756. | The header is emitted by the lint writer, committed in both files, and pinned three ways (writer text, committed text, battery). After conversion the sentence is false. | Reword it once in the writer, both committed headers, and the battery pin (D6). |
| `r2-conditional-put.sh` `put_once` ends in `|| echo "000"`. | A helper refusal there would be folded into status `000` and then into "unexpected status", with the marker hidden by `2>/dev/null`. | Judge once before the retry loop and `exit 2` there (D2); the chokepoint re-judges as defence in depth. |

## Decisions

- **D1. App-local sourced helper over inline copies or a library change.** One tested place for the guard, the
  host pin and the stdin config (ADR-280 Decision 2, "one chokepoint"). It carries its own literal URL pin (D4). It carries no `exit` (a sourced `exit` kills the caller) and no
  shebang; the xtrace defence lives in each caller's prologue, as in `_cf-admin-token.sh`.
- **D2. Judge before the loop; the chokepoint re-judges.** `r2-conditional-put.sh` calls the judge right after the
  existing 32/64 length preflight and `exit 2` on refusal, so the marker is visible and no retry or `000`
  classification can see it. `r2_sigv4_curl` judges again, because it is the only place a request starts.
- **D3. Guard alphabet is the ADR-280 token alphabet `[A-Za-z0-9._~+/=-]`, non-empty, per value.** That excludes the
  three bytes that change how a quoted `user = "..."` value parses (`"`, backslash, newline) and the `:` that would
  split the pair. Reason is `control_char` when the value has any `[[:cntrl:]]` byte, else `token_shape`. The 32/64
  length preflight stays first and unchanged (its operator hint about a bearer-valued Doppler secret is load-bearing).
  No trimming (cut list). A real R2 pair (32 and 64 hex) passes by construction; AC 5 proves it.
- **D4. The helper pins the destination with an in-file literal.** `r2_sigv4_curl` returns 64 (not 2, no credential
  marker: a different fault class) unless `[[ "$url" =~ ^https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com/ ]]`. This is
  the form Rule D's `_pin_re` accepts (an anchored `=~` with a literal after the anchor, as `_cf_admin_curl` uses a
  `case` arm); a call to `assert_r2_endpoint` is NOT a recognised pin (the plan's first draft used it; plan review
  linted a draft helper and Rule D reported the URL as unpinned) and `assert_r2_endpoint` takes only an origin. The
  callers keep their existing top-level `assert_r2_endpoint` check; the helper does not source `_r2-endpoint.sh`.
- **D5. URL stays the last curl argument; `--data-binary "$payload"` stays on argv.** The payload is evidence JSON,
  not a credential. Existing PATH stubs that read the last positional argument keep working. `--disable` is the
  first argument, `--noproxy '*'` is present, `--aws-sigv4` stays on argv (a non-secret scope string).
- **D6. Reword the baseline E OWNERS header: drop the sentence naming the two cla-evidence rows, keep the owner-line rule.** The writer text in
  `scripts/lint-shell-trace-credential-refusal.py` (the only source), both committed headers, and the battery's
  `#9756` pin move together. The cla-evidence carve-out in the battery's owner-line rule is deleted: a re-added
  cla-evidence row must now carry an owner line like any other.
- **D7. bootstrap probe body file moves from the fixed `/tmp/r2-probe-body` to `mktemp` with a trap.** Inferred, one
  line of justification: the new bootstrap harness suite executes the real script, and two concurrent runs of a
  shared fixed path would race. It also removes a predictable-path write from the one-shot script.
- **D8. Uniform error class.** A refusal exits 2, the class of the existing credential-shape preflight and of every
  other failure of the upload step. It is never retried, never matched by the 412 or WORM arms, and is not a
  curl exit code (the marker, not the exit status, is the discriminator, as in ADR-280 Decision 3).

## Open Code-Review Overlap

None. Queried open `code-review` issues for every planned file path (both scripts, both upload suites, the lint and
its suite, the battery, both baselines, ADR-280); no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE slice, ONE PR — only the two cla-evidence rows (apps/cla-evidence/infra/bootstrap.sh and apps/cla-evidence/scripts/r2-conditional-put.sh)" [brief] | Files to Edit entries 1-2; Phases 1-3 | mapped |
| 2 | "do NOT touch the library-gap/URL-path-secret follow-ups or the tainted-egress follow-through" [brief] | Non-Goals; Cut List row 1 (no `bearer-curl.sh` edit) | mapped |
| 3 | "Move the SigV4 pair off curl argv onto curl's stdin config behind a shape guard ... `--disable --noproxy '*' ... --config -` with `user = \"<id>:<secret>\"` fed by process substitution (never a pipe)" [brief] | Phase 1 helper; Phases 2-3 call sites; D1, D3, D5 | mapped |
| 4 | "refuse a malformed value with `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape\|control_char>` and a non-zero exit before any request" [brief] | Phase 1 judge; Phase 2 pre-loop judge; D2, D8; Guard 1 | mapped |
| 5 | "Remove both rows from scripts/lint-shell-trace-credential-refusal-e.baseline.txt and scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv in the same change" [brief] | Phase 4 steps 1-2 | mapped |
| 6 | "Owning suites must assert the key id/secret pair is absent from every recorded argv (use synthesized fixtures only)" [brief] | Phase 0 suites; Guard 1 harness rows | mapped |
| 7 | "do not print token values; never use git stash or a pattern-matching process kill; poll with Monitor, not background run polling" [brief] | Sharp Edges; every test prints only labels and lengths | mapped |
| 8 | "do not dispatch any production apply (verify the changed paths do not trigger one; apps/cla-evidence is outside apps/web-platform/infra)" [brief] | AC 14; Research Insights "Repo facts" | mapped |
| 9 | "PR body must say Closes #9756" [brief] | AC 15 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `apps/cla-evidence/scripts/r2-conditional-put.sh` | "only the two cla-evidence rows" | asked |
| Edit `apps/cla-evidence/infra/bootstrap.sh` | "only the two cla-evidence rows" | asked |
| Create `apps/cla-evidence/scripts/_r2-sigv4-curl.sh` | "Move the SigV4 pair off curl argv onto curl's stdin config behind a shape guard" | asked (the guard needs one tested home; D1) |
| Create `apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh` | "Owning suites must assert the key id/secret pair is absent from every recorded argv" | asked |
| Create `apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh` | "Owning suites must assert the key id/secret pair is absent from every recorded argv" | asked (bootstrap has no owning suite today) |
| Edit `upload-evidence.test.sh`, `upload-bypass.test.sh` | "Owning suites must assert the key id/secret pair is absent from every recorded argv" | asked |
| Edit baseline E and the ceiling table | "Remove both rows from scripts/lint-shell-trace-credential-refusal-e.baseline.txt and scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv" | asked |
| Helper refuses caller-supplied `--user`/`-u`/`--config`/`-K`/`--next`/`--disable` (Phase 1) | — | inferred — justification: P1 must hold for every future caller of the only SigV4 curl; without it a later caller can put the pair back on argv through the helper while every suite stays green (advisor consult) |
| Edit the A/B/C baseline and the D baseline (delete two rows each) | — | inferred — justification: CI runs `--changed`, whose drawdown rule requires both files to leave those baselines once remediated; a stale row is a false statement in the tree |
| Add the xtrace refusal (Rule A) to both scripts | — | inferred — justification: the `--changed` lint fails an edited, listed script that binds a live credential without it |
| Edit `scripts/lint-shell-trace-credential-refusal.py` (writer header text and the comment blocks that name the two rows) | — | inferred — justification: the header is emitted by the writer and pinned against the committed files; a stale "owned by #9756" sentence fails the battery's header-identity row |
| Edit `scripts/lint-shell-trace-credential-refusal.test.sh` (census-ceiling rows over a synthesized pair) | — | inferred — justification: an empty baseline E fails its anti-vacuity floor and vacates every mutation row that reads the first real row |
| Edit `tests/scripts/test-argv-bearer-sweep.sh` (S5 Guard 1 rows) | — | inferred — justification: it pins the two rows and `#9756` in both headers, so the removal the user asked for turns it red |
| ADR-280 addendum | — | inferred — justification: the "Final state of baseline E" section names the two rows; the recorded architecture must not lag the change |
| mktemp for the bootstrap probe body (D7) | — | inferred — justification: the bootstrap harness suite runs the real script; a fixed shared path races |

### Split Assessment

- Subsystems touched: 4 — `apps/cla-evidence`, `scripts` (lint, writer, baselines, fixtures), `tests/scripts`, `knowledge-base/engineering` (ADR-280 addendum)
- Planned files: 16 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the four roots are one coupling that cannot be split without a red tree: removing the baseline rows without the conversion fails the equality check; converting without removing them fails "listed but no longer offends"; either one without the suite rewrites fails the lint suite and the battery. The ADR addendum is under 15 lines.

## Observability

```yaml
liveness_signal:
  what: the exit status and the `ok status=<2xx> key=... attempt=N` / `duplicate status=412` line of the "Build and write evidence record" and "Record allowlist-bypass" steps of the cla-evidence workflow (the helper adds no new success line)
  cadence: per CLA signing comment, per allowlist-bypass pull_request_target event
  alert_target: the red step on the PR's `cla-evidence` check (no paging; unchanged by this change; the receipt comment step stays soft-fail)
  configured_in: .github/workflows/cla-evidence.yml
error_reporting:
  destination: GitHub Actions step log, a `::error::<label>: ...` annotation plus the `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>` marker on stderr (value-free; names only the variable)
  fail_loud: exit 2 from the step before any PUT, so the step goes red; never swallowed by `|| echo 000`, never retried, never matched by the 412 or WORM arms
failure_modes:
  - mode: a malformed R2 key id or secret (control byte, quote, backslash, colon, empty) reaches the script
    detection: judge in `_r2-sigv4-curl.sh`, run before the retry loop; marker and annotation in the step log
    alert_route: red `cla-evidence` step; the evidence record for that event is not written, so the event is re-run or backfilled (existing path)
  - mode: the guard false-refuses a valid pair, stopping all evidence capture while reading as a clean failure
    detection: must-PASS rows in `_r2-sigv4-curl.test.sh` (32 lowercase-hex id, 64 lowercase-hex secret, uppercase/mixed, and the `._~+/=-` bytes); a refusal in production reads as the marker with `reason=token_shape`
    alert_route: same red step; bounded because the 32/64 preflight and the alphabet both accept every real R2 pair
  - mode: the helper file is missing or unsourceable in the job
    detection: `source` fails under `set -e` before any request (the checkout lacks `apps/cla-evidence/scripts/`)
    alert_route: red step; there is no argv fallback (a fallback would defeat P1)
  - mode: the signed request is rejected because the config-channel `user` was not applied
    detection: R2 returns a 4xx `SignatureDoesNotMatch` body, surfaced by the existing `body_excerpt` in the fatal-4xx annotation; pre-merge, the real-curl wire row of `_r2-sigv4-curl.test.sh` fails
    alert_route: red step
logs:
  where: GitHub Actions run log (job `cla-evidence`)
  retention: the repository's Actions log retention (GitHub default, 90 days)
discoverability_test:
  command: bash apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh
  expected_output: ALL _r2-sigv4-curl.sh tests passed.
```

Layer citation (`hr-observability-layer-citation`): the surface is CI step logs (layer: the GitHub Actions run), not
Sentry or Better Stack; this is stated in the Cut List. The suite is sized to finish well inside preflight Check 10's
15-second cap (about 20 rows, each a sub-second bash process, one loopback listener); AC 13 measures it and the work
phase trims rows if it does not.

## Domain Review

**Domains relevant:** engineering, legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Helper design is right (precedent `_cf-admin-token.sh`; library stays header-only); reuse the R2
endpoint pin and have the helper source `_r2-endpoint.sh` (taken, D1/D4). Top risks: a refusal folded into the
`|| echo "000"` path (taken, D2: judge before the loop); stub fidelity (taken, Phase 0 recording stubs); real curl
semantics on 8.5 (taken, AC 12). Lint fallout: Rules A and D plus the A/B/C and D baseline rows (taken). Do not empty
baseline E without rewriting the rows that read its first row (taken, Guard 2). No new ADR (taken). Divergence: a
hex-only guard was suggested; the plan keeps the ADR-280 alphabet plus the existing 32/64 length preflight (D3).

### Legal (CLO)

**Status:** reviewed
**Assessment:** No legal-document edit is required (no Art. 30 or TOMs statement names how the credential is carried;
do not add one). The only compliance-relevant change is the new refusal arm: it can lose the off-site evidence record
for a signed CLA (the public signature branch stays canonical), so a refusal must be loud, distinct from the retry and
duplicate classifications, and tested for zero requests after refusal and for no false refusal of a valid pair (all
taken: D2, D3, D8, Guard 1). A red step does not block the merge gate, so a documented re-run or backfill path is the
recovery; that path already exists and is unchanged.

## User-Brand Impact

- **If this lands broken, the user experiences:** a contributor who signs the CLA gets a red `cla-evidence` check
  and no off-site evidence record for the signing event (the public signature record still stands), for every signing
  until the check is re-run; if the guard false-refuses, that is every signing.
- **If this leaks, the user's data is exposed via:** a reader of `/proc/<pid>/cmdline` on the runner or the bootstrap
  host who could take the R2 pair and write forged objects into the evidence bucket (it cannot overwrite or delete:
  Lock Rules); that is the exposure this change closes.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** one signing's evidence is recoverable from the public signature record and
  a re-run, and the pair cannot rewrite sealed objects, so a single failure is not a brand-ending event; a systematic
  false refusal would be an aggregate pattern across every contributor, which is why the must-PASS rows are a hard gate.

## Technical Considerations

- **Attack surface enumeration.** Every path that puts the SigV4 pair in front of a process: (1) `put_once` curl
  (converted); (2) the bootstrap probe curl (converted); (3) the Doppler write at bootstrap Step 2, which passes the
  pair as `NAME=value` arguments to the `doppler` CLI (NOT curl, NOT in Rule E's vocabulary, not converted here;
  a non-goal, tracked by a deferral issue filed in Phase 5); (4) the workflow step `env:` block and Doppler `::add-mask::`
  lines in `cla-evidence.yml` (environment, not argv; unchanged); (5) `object_lock.tf` local-exec curl with a bearer
  header (a different credential, a documented census blind spot, not this issue). Nothing else in `apps/cla-evidence`
  runs `curl --aws-sigv4` (`git grep` over the directory, verified: only the two files).
- **Same-uid residual (stated, not closed).** The stdin config closes `cmdline` and `ps` readers. It does not close a
  same-uid reader of `/proc/<pid>/environ` (the callers' environment still holds the pair) or tampering with the
  helper inside the job. ADR-280's context says the same.
- **`set -e` / `pipefail`.** `curl ... < <(printf ...)` ignores the substitution's status; the writer's stderr is
  silenced inside the substitution so a closed pipe prints nothing under a runner that ignores SIGPIPE. The helper's
  own functions are called as `if`/`||` operands so their non-zero return is handled, never aborting mute.
- **No behaviour change to the PUT.** Same URL, headers, `--data-binary`, `-o "$body_tmp"`, `-w`, `--max-time 30`,
  `2>/dev/null || echo "000"`; only `--user` leaves argv, `--disable --noproxy '*'` and the stdin config arrive.
  `--noproxy '*'` and `--disable` are a transport change recorded in the ADR addendum: no `.curlrc`, no proxy.
- **NFR impacts.** None beyond security hardening; no latency, cost or availability surface changes.

## Implementation Phases

### Phase 0 — RED first (`cq-write-failing-tests-before`)

Write the suites before the code, run them, and watch them fail for the right reason. Every fixture credential is
synthesized at run time from `od /dev/urandom` pieces (never a contiguous literal) and the id and the secret are
DISTINCT values, neither a substring of the other and neither a run of one repeated character: the existing upload
suites use all-zero literals (the 64-zero secret contains the 32-zero id), which would let an argv-absence row pass or
fail by accident, so those fixtures are replaced, keeping their separate length-error fixture.

1. `apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh` (new). Rows (a distinct canary for the refused-value rows):
   - judge: valid pair returns 0; empty id, empty secret; id or secret with `"`, backslash, `:`, space, newline, tab,
     DEL, a high byte; each refused with the marker once, `reason` correct (`control_char` vs `token_shape`), one
     value-free line naming only the variable, return 2, zero curl calls.
   - must-PASS non-canonical: a 32-char lowercase-hex id with a 64-char lowercase-hex secret, uppercase and mixed hex,
     and a value containing `._~+/=-` (the guard must not be a vendor-format guard; a guard that refuses everything
     is caught only by these rows).
   - chokepoint wire (recording stub that drains stdin and records argv and stdin separately): exactly one curl call;
     argv begins `--disable`, contains `--noproxy` `*` and `--aws-sigv4`, ends with the URL, and contains neither value
     (substring of the whole recorded argv, not per element); recorded stdin is exactly `user = "<id>:<secret>"` plus
     a newline. A source row asserts the helper's curl is fed by `< <(printf` and the helper has no `| curl`.
   - helper contract: a caller-supplied `--user`, `-u`, `--config`, `-K`, `--next` or `--disable` in the curl arguments
     returns 64 with zero calls (a future caller cannot put the pair back on argv, or consume the config channel,
     through the helper).
   - destination pin: a non-R2 URL and an R2-lookalike host (`...r2.cloudflarestorage.com.evil.test`) return 64,
     zero calls, no credential marker.
   - real-curl wire row: a PATH stub rewrites only the URL to a loopback HTTP listener (PID captured at start, stopped
     by that PID in a trap) and execs the real curl with every other argument and its stdin untouched; the listener
     records the `Authorization` header; assert `Credential=<id>/` is present (the pair reached curl through the
     config) while the stub's recorded argv has neither value. Requires `python3` and `curl`; a missing tool is a hard
     FAIL, not a skip (CI has both). Prints `curl --version | head -1` so the runner version is in the log.
   - negative canary: the refused-value canary appears in no captured stream (stdout, stderr, argv log, stdin log).
2. Extend the stubs in `upload-evidence.test.sh` and `upload-bypass.test.sh`: record every argv and drain and record
   stdin to files; keep the existing behaviour (code stack, `-o` body copy, last-argument URL). In BOTH suites: after
   a 200 run, the recorded argv contains neither value, the recorded stdin is the `user =` line, and at least one call
   was recorded (an empty log is RED, so a stub that records nothing cannot pass). In `upload-evidence.test.sh` only
   (the bypass script execs the same primitive): a malformed-credential run (control byte in the secret, length still
   64) exits 2, records zero calls, prints the marker exactly once and no value; and one dynamic row that the script
   exits 78 under `bash -x` with the fixture credential set.
3. `apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh` (new, two behavioural rows plus the xtrace row). Runs the real
   `apps/cla-evidence/infra/bootstrap.sh` under PATH stubs for `terraform`, `doppler`, `gh`, `openssl` (presence only)
   and a recording `curl` that answers the Cloudflare token-verify call and the R2 probe call by URL, with `jq` real;
   the probe answers 500 so the script stops at "Refusing to push known-broken creds" before any Doppler write. Rows:
   the probe call's recorded argv has neither value and recorded stdin carries the `user =` line; a malformed pair
   (control byte, correct length) exits non-zero with the marker printed once and zero R2 probe calls (the Cloudflare
   verify call precedes it and is excluded by URL); `bash -x` exits 78 before any stub is called. The probe body temp
   file is gone after both outcomes (D7).

Run them: every new row is RED (helper absent; scripts still pass `--user`).

### Phase 1 — the helper

Create `apps/cla-evidence/scripts/_r2-sigv4-curl.sh` (`# shellcheck shell=bash`, no shebang, no `exit`). Run
`python3 scripts/lint-shell-trace-credential-refusal.py apps/cla-evidence/scripts/_r2-sigv4-curl.sh` FIRST, before
building the callers on it, to confirm Rule D accepts the pin form (D4).

- `_r2_cred_ok VALUE` — the D3 predicate (name chosen so it never matches the byte-identical `_bearer_ok() {`
  census).
- `r2_sigv4_judge SCRIPT ID SECRET` — values are passed as arguments, as `_cf_admin_curl` does (the callers hold them
  in variables already; the xtrace refusal in each caller prologue is the trace defence). Returns 0, or 2 with a
  value-free line (`<NAME> unusable`, naming `R2_CLA_EVIDENCE_ACCESS_KEY_ID` or `R2_CLA_EVIDENCE_SECRET`) and the
  marker. `SCRIPT` is a literal passed by the two callers and is not re-validated. A comment at the `return 2` says
  the marker, not the status, is the discriminator (curl exits 2 too).
- `r2_sigv4_curl SCRIPT ID SECRET URL [curl args...]` — `${4:?}` for the URL, refuses the caller arguments listed in
  Phase 0 (64), pins the URL (D4, 64), judges (2), then runs
  `curl --disable --noproxy '*' "$@" --aws-sigv4 'aws:amz:auto:s3' --config - "$url" 2>/dev/null < <(printf 'user = "%s:%s"\n' "$id" "$secret" 2>/dev/null)`.
  `2>/dev/null` is scoped to the curl itself, so the helper's own refusal lines stay visible to the caller (callers
  drop their trailing `2>/dev/null`).

Run the helper suite: GREEN.

### Phase 2 — `r2-conditional-put.sh`

1. Insert the canonical xtrace refusal (conditional form the lint prints, keyed on `R2_CLA_EVIDENCE_SECRET`) as the
   first thing after `set -euo pipefail`.
2. Source the helper next to the existing `_r2-endpoint.sh` source.
3. After the existing 32/64 length preflight and before `body_tmp`: `r2_sigv4_judge "r2-conditional-put" "$access_key" "$secret" || exit 2`
   (this is the only call site that needs a pre-judge: the retry loop and the `|| echo "000"` fallback would otherwise
   fold a refusal into a status).
4. `put_once`: replace the `curl` with `r2_sigv4_curl "r2-conditional-put" "$access_key" "$secret" "$url" -sS -o "$body_tmp" -w "%{http_code}\n" --max-time 30 -X PUT -H ... --data-binary "$payload" || echo "000"`.
   Update the header comment and the stale `put_once` comment (`--aws-sigv4` now lives in the helper).
5. Everything else, including the ordering-load-bearing WORM arm comment, is untouched.

### Phase 3 — `bootstrap.sh`

1. Insert an unconditional xtrace refusal first after `set -euo pipefail` (the script handles an admin token and the
   R2 pair; there is no legitimate traced run).
2. Source the helper next to the two existing `source` lines.
3. Replace the probe curl with `r2_sigv4_curl "bootstrap" "$R2_ACCESS_KEY" "$R2_SECRET" "$probe_endpoint" -sS -o "$probe_body_file" -w "%{http_code}" --max-time 30 -X PUT -H ... --data-binary "$probe_body" || echo "000"`;
   a refusal there prints the helper's marker and takes the existing `000` arm (exit 1, nothing pushed to Doppler), so
   no separate pre-probe judge is needed. `probe_body_file=$(mktemp)` with `trap 'rm -f "$probe_body_file"' EXIT`
   replaces the three `/tmp/r2-probe-body` uses (D7). Update the header comment at the Step 1 probe block.

### Phase 4 — lint fallout and gates

1. Delete both rows from `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` and
   `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`; reword the OWNERS header (D6) in the lint writer
   (`scripts/lint-shell-trace-credential-refusal.py`, the `--write-baseline-e` text) and both committed headers; update
   only the two lint docstring paragraphs that become false (the USER ARM census paragraph and the S5 paragraph).
2. Delete both rows from `scripts/lint-shell-trace-credential-refusal.baseline.txt` (A/B/C) and
   `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (D). Verify `--write-baseline` and `--write-baseline-d`
   regenerate those files with no diff beyond the two rows.
3. `scripts/lint-shell-trace-credential-refusal.test.sh`: in the census-ceiling block, point `census_ceiling_check` at a
   synthesized pair (`CC_BASE`/`CC_CEIL` written under `$WORK`: two rows, distinct counts, a ceiling above one count)
   instead of `BASE_E_FILE`/`CEIL_FILE`, and leave every M-row, U-row and control row as it is; the `--census`
   equality row keeps reading the live baseline. Replace the floor `CC_LISTED -lt 1` on the live pair with a floor on
   the synthesized pair (`CC_LISTED >= 2`) and add one row that the live pair reads clean (dup=0 bad=0 stale=0, listed
   may be 0). The vacuity control for Rule E dispatch is the existing `e_row` fixture row at the
   `violation-argv-user-multiline-sigv4.sh` line (explicit-path run: a Rule E finding and a non-zero exit); no new
   `--census` control is added (`--census FILE` reports `offenders_e=0` for that fixture, measured).
4. `tests/scripts/test-argv-bearer-sweep.sh` S5 Guard 1: `S5_WANT_ROWS` derives to the registry row only when it still
   offends (empty otherwise); the header row checks the reworded state-neutral owner text (D6) in both files and the
   writer; delete the `apps/cla-evidence/*` carve-out of `s5_owner_bad` and its control rows so a cla-evidence row now
   needs an owner line; update the stage's leading comment.
5. ADR-280: append "Addendum — 2026-10-11 (#9756)", at most 10 lines: the conversion through the app-local helper and
   its alphabet, the final state of baseline E (empty), and the transport change (`--disable --noproxy '*'`, so the
   one-shot bootstrap now needs direct egress to R2). Residuals are not restated (the ADR context states them).

### Phase 5 — verify and ship prerequisites

Run the AC commands below. File one deferral issue (label `deferred-scope-out`, milestone from the roadmap) for the
Doppler write argv at bootstrap Step 2 (NOT curl), citing tracker #9757 as the neighbouring population, before the PR
is marked ready.

## Files to Edit

1. `apps/cla-evidence/scripts/r2-conditional-put.sh`
2. `apps/cla-evidence/infra/bootstrap.sh`
3. `apps/cla-evidence/scripts/upload-evidence.test.sh`
4. `apps/cla-evidence/scripts/upload-bypass.test.sh`
5. `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`
6. `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`
7. `scripts/lint-shell-trace-credential-refusal.baseline.txt`
8. `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`
9. `scripts/lint-shell-trace-credential-refusal.py`
10. `scripts/lint-shell-trace-credential-refusal.test.sh`
11. `tests/scripts/test-argv-bearer-sweep.sh`
12. `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`

## Files to Create

1. `apps/cla-evidence/scripts/_r2-sigv4-curl.sh`
2. `apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh`
3. `apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh`
4. `knowledge-base/project/specs/feat-one-shot-9756-cla-evidence-sigv4-argv/tasks.md`

(Path globs verified: `apps/cla-evidence/scripts/*.test.sh` is the `scripts/test-all.sh` `SUITE_GLOBS` entry and
matches 8 existing suites; `apps/cla-evidence/infra/` is not a suite glob and only `main.test.sh` runs there.)

## Non-Goals

- `scripts/lib/bearer-curl.sh` and its library-gap list, URL-path secrets, the held-back HMAC arms, and the
  tainted-egress follow-through (tracker #9757 and neighbours): untouched.
- The pair on the `doppler` CLI's argument list at bootstrap Step 2, `object_lock.tf`'s bearer-header local-exec curl,
  and agent-executed Markdown that teaches the argv form: separate populations, not Rule E curl sites. The first is
  filed as a deferral in Phase 5.
- No Terraform, no `apps/web-platform/infra/**`, no workflow YAML, no Doppler value, no key rotation.
- No change to what the evidence record contains, to key derivation, or to the status classifier.

## Guard Contract

### Guard 1 — SigV4 pair never on argv; refuse before any request

**Property.** No curl process carrying the R2 SigV4 pair is started unless both values pass the token-alphabet guard
and the URL is a canonical R2 origin, and the pair is on no argument list of any such process.

**Assembly.** Every curl in `apps/cla-evidence` that carries `--aws-sigv4`, derived by
`git grep -l -e '--aws-sigv4' -- apps/cla-evidence ':!*.test.sh'` and required to equal exactly the helper file
(today the two scripts; after the change only `_r2-sigv4-curl.sh`, plus comments). Chokepoint: `r2_sigv4_curl` is the
only place the `curl` token occurs with the pair; two entry paths flow through it (the CI primitive `put_once` and
the bootstrap probe), and two judge call sites exist (the pre-loop judge in `r2-conditional-put.sh`, needed only because of its retry loop,
and the chokepoint's own judge, which bootstrap relies on alone). The owning suites quantify over every recorded call
(argv log and stdin log), not the first.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `--user "$id:$secret"` to the helper's curl (or to `put_once`) | RED (argv-absence row in the helper suite and both upload suites; Rule E) |
| 2 | Delete the judge call inside `r2_sigv4_curl`, keeping the pre-loop judge | RED (helper suite calls the chokepoint directly with a refused value and records a curl call) |
| 3 | Dispatch: make `r2_sigv4_curl` undefined or unsourced so the callers record zero calls | RED (every happy-path row asserts at least one recorded call and the `user =` stdin line; zero calls cannot pass) |
| 4 | Second member: add a `curl --aws-sigv4 ... --user` to a third file under `apps/cla-evidence` | RED (derived `--aws-sigv4`-carrier set identity row; Rule E) |
| 5 | Widen the alphabet to admit `"` (or drop the `:` exclusion) | RED (refused-value rows for quote, backslash, newline, colon) |
| 6 | Reorder: move the pre-loop judge below the retry loop (or below the first `put_once`) | RED (a malformed-credential run in `upload-evidence.test.sh` must record zero calls and print the marker once) |
| 7 | Swallow the refusal: wrap the judge as `... || true` or let the `put_once` `|| echo "000"` fallback absorb it | RED (the run must exit 2, not 0 and not "unexpected status=000") |
| 8 | Replace the process substitution with a pipe (`printf ... \| curl`) | RED (the helper-suite source row asserts the `< <(printf` form and no `\| curl`) |

**Harness rows.** (H1) edit the suite's recording stub so it stops capturing stdin: the "recorded stdin is the `user =`
line" row must go RED. (H2) edit it so it records an empty argv log: the "argv log non-empty and holds `--aws-sigv4`
and the URL" row must go RED. (H3) make the judge refuse everything: the must-PASS rows (32 and 64 lowercase hex,
uppercase and mixed, the `._~+/=-` bytes) must go RED; RED rows alone cannot detect a guard that rejects all.
Must-PASS inputs that are NOT the canonical fixture: mixed-case hex and a value containing `._~+/=-`.

**Anchor.** The guard compares no stored value; the only stored artifact is the derived `--aws-sigv4`-carrier set,
asserted as set identity against the tree at test time, not against a number.

### Guard 2 — baseline E and the census ceiling stay honest when baseline E is empty

**Property.** Baseline E and the census ceiling hold exactly the rows whose files still offend with an owner line
(none after this change), and the harness rows that prove the census-ceiling check can fire are driven by a
synthesized pair, so they cannot vacate when the live baseline shrinks to zero.

**Assembly.** The two live files (baseline E, ceiling table); the lint writer's header text (single source) against
both committed headers; every row of `scripts/lint-shell-trace-credential-refusal.test.sh` that reads
`BASE_E_FILE`/`CEIL_FILE` (floor, M-stale x2, control, M-raise, M-dup x2, M-nan, M-nan-ceiling, M-empty-count x2, the
U-rows over `cc_mutant_row`, the closing control); the S5 Guard 1 rows of `tests/scripts/test-argv-bearer-sweep.sh`
(set identity, header identity, owner-line rule and its control); and the repo-wide lint run itself (equality on path
and count). The rows are quantified by `grep -n 'BASE_E_FILE\|CEIL_FILE' scripts/lint-shell-trace-credential-refusal.test.sh`
at work time, not by the list above.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `apps/cla-evidence/scripts/r2-conditional-put.sh 1` to baseline E only | RED (repo-wide run: listed but no longer offends; battery set identity) |
| 2 | Re-introduce an argv `--user` curl in either script after conversion | RED (Rule E unbaselined offender; the owning suite's argv row) |
| 3 | Add a ceiling row for a clean file | RED (census-ceiling M-stale row, over the synthesized pair) |
| 4 | Dispatch: point the census-ceiling rows back at the live empty pair (no synthesized seed) | RED (floor `CC_LISTED >= 2` on the synthesized pair) |
| 5 | Add a baseline row for a non-cla-evidence file with no owner comment above it | RED (owner-line row; its carve-out is gone) |
| 6 | Edit the writer header text without editing the committed headers (or the reverse) | RED (battery header-identity row) |

**Harness rows.** (H1) edit `census_ceiling_check` to ignore the ceiling column: the M-raise row must go RED.
(H2) the synthesized pair read clean (dup=0 bad=0 stale=0) as a must-PASS that is not the live pair, and the live empty
pair reading clean is a second must-PASS that differs from it.

**Anchor.** The ceiling table is a copy of the baseline and not an independent review (the lint's own comment says
so). What outside the commit must also move for a weakening to pass: the base-ref diff of both files that
`--changed` and a reviewer see. This is a reviewer gate, stated, not mechanised here.

## Plan Review Disposition (2026-10-11)

Panel: DHH, Kieran, code-simplicity (aggregate-pattern threshold, so the 3-agent baseline) plus the Phase 4.5 advisor
consult; the CTO and CLO assessments above served as the named-panel lenses.

| Finding | Class | Disposition |
|---|---|---|
| Rule D does not recognise `assert_r2_endpoint` as a pin (Kieran P1, simplicity F2) | mechanical | Applied: D4 now uses an in-file anchored `=~`; Phase 1 lints the helper first. |
| AC 4 baseline counts wrong; `inspect-evidence.sh` stays in the A/B/C baseline (Kieran P1) | mechanical | Applied: AC 2 and AC 4 carry the measured counts (31 to 29, 7 to 5). |
| `git grep` ignores the untracked helper; `date -u` matches the `-u` grep; all-zero fixtures (Kieran P2) | mechanical | Applied: AC 3 uses `--untracked` and a `curl`-anchored pattern; Phase 0 synthesizes distinct fixtures. |
| Census-ceiling control undefined (Kieran P2, simplicity F3) | mechanical | Applied: rows repointed to a synthesized pair; the existing `e_row` fixture is the dispatch control. |
| Pre-probe judge, `SCRIPT` validation, 70,000-byte row, `--refusal-only`, duplicate bypass-suite rows, docstring and ADR trimming (DHH, simplicity F4-F9) | mechanical | Applied; the helper's `2>/dev/null` is now scoped to curl so its refusal stays visible. |
| `--noproxy`/`--disable` contradict "byte-for-byte unchanged" for bootstrap (DHH P1) | mechanical | Applied: P6 reworded, ADR addendum records the direct-egress requirement; the flags stay (the brief names them). |
| Helper must refuse caller-supplied `--user`/`--config`/`-K`/`--next` (advisor) | mechanical | Applied (Phase 1, Phase 0 contract row). |
| Cut `bootstrap-r2-probe.test.sh` and D7 (DHH P1, simplicity F1) | user-challenge | Kept, shrunk to two rows plus the xtrace row; recorded in `decision-challenges.md`. |
| Split the lint-harness refactor into a preparatory PR (advisor) | user-challenge | Kept as one PR per "ONE slice, ONE PR"; recorded in `decision-challenges.md`. |
| Drop the Guard Contract matrix rows and the Docker AC (DHH P1) | taste | Matrix rows 3 and 4 are required by the gate; row 8 cut. Docker run softened to "when docker is available, else the first CI run". |

## Acceptance Criteria

1. `python3 scripts/lint-shell-trace-credential-refusal.py apps/cla-evidence/infra/bootstrap.sh apps/cla-evidence/scripts/r2-conditional-put.sh apps/cla-evidence/scripts/_r2-sigv4-curl.sh` exits 0 with `OK:` (no A, B, C, D or E finding on explicit paths, which bypass baselines).
2. `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide) exits 0 and the final line reads `29 baselined (A/B/C), 5 baselined (D), 0 baselined (Rule E: 0 site(s))` (it reads 31, 7 and 2 sites today); `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0.
3. `git grep -n -E 'curl.*( -u |--user)' -- apps/cla-evidence/scripts/r2-conditional-put.sh apps/cla-evidence/infra/bootstrap.sh apps/cla-evidence/scripts/_r2-sigv4-curl.sh` prints nothing (`date -u` in `bootstrap.sh` is why the pattern is anchored on `curl`); `git grep --untracked -l -e '--aws-sigv4' -- apps/cla-evidence ':!*.test.sh'` lists exactly `apps/cla-evidence/scripts/_r2-sigv4-curl.sh` (`--untracked` because the helper is not tracked until staged), and the helper suite asserts the same set identity with the same untracked-aware form.
4. `grep -cv -e '^#' -e '^$' scripts/lint-shell-trace-credential-refusal-e.baseline.txt` prints `0` (it prints `2` today), likewise for `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`; `git grep -n 'apps/cla-evidence' -- scripts/lint-shell-trace-credential-refusal.baseline.txt scripts/lint-shell-trace-credential-refusal-d.baseline.txt` prints only the `apps/cla-evidence/scripts/inspect-evidence.sh` line of the A/B/C baseline (five lines today: three A/B/C rows and two D rows; `inspect-evidence.sh` is not part of this change).
5. `bash apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh` exits 0 and prints `ALL _r2-sigv4-curl.sh tests passed.`; it contains the must-PASS rows (32-hex id, 64-hex secret, mixed case, `._~+/=-`), the helper-contract and destination-pin rows, and the refused rows (quote, backslash, colon, space, newline, tab, DEL, high byte, empty) with the correct `reason`.
6. `bash apps/cla-evidence/scripts/upload-evidence.test.sh` and `bash apps/cla-evidence/scripts/upload-bypass.test.sh` exit 0; each asserts, over every recorded call, that neither fixture value appears anywhere in the recorded argv, that recorded stdin is the `user = "..."` line, and that at least one call was recorded; `upload-evidence.test.sh` alone carries the malformed-credential row (exit 2, zero calls, marker once, no value printed) and the `bash -x` row.
7. `bash apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh` exits 0: probe argv free of both values, stdin carries the `user` config line, malformed pair exits non-zero with zero R2 probe calls and one marker, `bash -x` exits 78 before any stub runs, no `/tmp/r2-probe-body` is written or left.
8. `bash scripts/lint-shell-trace-credential-refusal.test.sh` exits 0 with the census-ceiling rows driven by the synthesized pair (floor `>= 2` met) and the live pair reading clean; `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 with the S5 Guard 1 rows reflecting an empty baseline and no cla-evidence carve-out.
9. `shellcheck` is clean on the helper, both edited scripts and the three suites (repo flags: whatever `scripts/test-all.sh` or the lefthook config uses; read it, do not assume), and the CI lint steps that read shell pass: `python3 scripts/lint-trap-tempfile-ownership.py` and `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` (the new `mktemp` and `trap` in `bootstrap.sh` and the suites join its population), `bash scripts/lint-orphan-test-suites.sh` (both new suites registered by the `apps/cla-evidence/scripts/*.test.sh` glob), `python3 scripts/lint-shell-capture-exit.py`, `python3 scripts/lint-window-closure-assertion.py`, and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
10. `rg -n 'SOLEUR_CREDENTIAL_REFUSED' apps/cla-evidence --glob '!*.test.sh'` shows the marker in the helper only (callers never print their own copy), and no test or script prints a fixture credential value: the suites' captured streams are searched for the canary and for both fixture values (zero hits). Telemetry registration needs no edit: `SOLEUR_CREDENTIAL_REFUSED` is already an arm of `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` (annotated MIRRORED-NOT-PAGED), and its drift test walks `skills/*/scripts/*.sh` only, so a marker emitted from `apps/cla-evidence` is a CI-log surface by construction; the work phase runs `apps/web-platform/test/git-lock-marker-telemetry.test.ts` once to confirm it stays green.
11. Both scripts refuse `bash -x` (exit 78) before binding the pair.
12. The real-curl wire row of the helper suite passes on the runner's curl 8.5: run it in `ubuntu:24.04` when docker is available (`docker run --rm -v "$PWD":/w:ro -w /w ubuntu:24.04 bash -c 'apt-get update -qq && apt-get install -y -qq curl jq python3 >/dev/null && bash apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh'`), otherwise the first CI run of the suite is the proof; either way the suite's `curl --version` line goes in the PR body.
13. The `discoverability_test.command` finishes inside 15 seconds (`time bash apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh`); if not, rows are trimmed until it does.
14. `git diff --name-only origin/main...HEAD` contains no path under `apps/web-platform/infra/` and none under `infra/github/`, so neither production-apply workflow triggers on merge; no workflow is dispatched by the work.
15. The PR body says `Closes #9756` (and `Ref #9597`), carries a `## Changelog` section, and the deferral issue for the Doppler-write argv exists and is cited.

## Test Scenarios

- Happy path (`upload-evidence.sh`, stub 200): exit 0, `ok status=200`, one recorded call, argv free of the pair, stdin is the `user =` line.
- Idempotent duplicate (412) and WORM duplicate (409 plus `<Code>ObjectLockedByBucketPolicy</Code>`): exit 0 as before.
- 5xx then 200 retry: two recorded calls, both with the stdin line and clean argv.
- Malformed secret (control byte, correct length): exit 2, zero calls, one marker `reason=control_char`, no value in any stream.
- Malformed id (colon, correct length): exit 2, `reason=token_shape`.
- Bad length (existing preflight): exit 2 with the existing operator hint, no marker (length is the vendor-format arm, unchanged).
- Non-R2 endpoint: `assert_r2_endpoint` exits 64 as before, before any judge.
- Bootstrap probe 500: stops before any Doppler write; argv clean; temp body file removed.
- `bash -x` on either script with the pair set: exit 78.
- Empty baseline E: repo-wide lint prints `0 baselined (Rule E: 0 site(s))`; both lint suites green over the synthesized pair.

## Dependencies & Risks

- **Runner curl 8.5 versus local 8.22.** Mitigated by the container row (AC 12). `--aws-sigv4` landed in 7.75 and the
  config `user` is resolved before signing; the loopback wire row proves it on the runner's curl.
- **False refusal stops evidence capture.** Mitigated by the alphabet (a superset of every real R2 pair), the
  existing 32/64 preflight, and the must-PASS rows being a hard gate.
- **Lint-suite rewrites are the largest part of the diff.** The synthesized-pair rows keep every mutation row
  meaningful; the alternative of leaving the live pair non-empty is not available (the brief removes both rows).
- **Same-uid `environ` reader and helper tampering remain** (ADR-280 context); stated in the addendum.
- **The first production signing after merge is the only live proof beyond the wire row.** There is no scheduled
  probe; the next CLA signing event exercises it. Not a soak-gated close criterion (no days-based condition), so no
  follow-through script is required (`soleur:ship` Phase 5.5 enrollment gate does not apply).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6; it is filled above.
- Do not name the new predicate `_bearer_ok` or spell the literal `_bearer_ok() {` anywhere (comments, tests):
  `lint-shell-trace-credential-refusal.test.sh` counts every occurrence as a copy that must be byte-identical.
- Put new functions in the scripts below the xtrace refusal block; Rule A fails otherwise. The helper has no shebang and
  no `exit`, so the lint's A-D scope does not read it, but Rule E and Rule D's pin check still read its curl.
- A suite that spawns `git` must use the constructed environment (plugin AGENTS.md); these suites spawn no git.
- Fixture credentials are synthesized from pieces at run time. Never write a contiguous token literal, and never
  print a value: print labels, lengths and booleans.
- The census-ceiling rows must not read the live baseline for their mutation inputs (Phase 4 step 3): a live pair that
  shrinks to zero rows vacates every row that reads "the first real row", which is exactly the state this change creates.
  Rule E dispatch vacuity is covered by the existing explicit-path `e_row` fixture row, not by `--census FILE`, which
  reports `offenders_e=0` for the same fixture (measured).
- Poll anything long with Monitor, never a background run loop; never `git stash` (use a WIP commit); no pattern-matching
  process kill (the loopback listener is stopped by PID captured at start, with a trap).
- A refusal exits 2, which collides with curl's own exit 2 (init failure): no caller may branch on `rc == 2`; the
  marker is the discriminator (ADR-280 Decision 3).
- Run suites with `timeout` and bounded output (`hr-never-run-commands-with-unbounded-output`).
