---
title: My sanitizer was bypassed by the line above it, and my fix for that shipped a live defect
date: 2026-09-10
category: security-issues
module: apps/web-platform/infra
issues: [8016, 8036, 8037]
pr: 8026
tags: [redaction, observability, deploy-gate, mutation-testing, vacuity, bwrap]
---

# My sanitizer was bypassed by the line above it

## Problem

The blocking bwrap deploy gate rolled back a production deploy and left one journald line with no
cause and no exit code. The probe ran `docker exec … bwrap … 2>&1` inside an `if !`, so its stderr
merged into the deploy script's stdout while only `logger -t "$LOG_TAG"` lines carried the record.

## The four things that were not obvious

### 1. `if ! VAR=$(cmd)` cannot supply the exit code, and here that is a SAFETY property

`!` consumes the status, so `$?` inside the branch reads **0** (measured: `rc=137 len=0` for the
correct form). That matters more than the message, because the captured output was EMPTY on both
production occurrences — the code is the only discriminator between a bwrap self-failure (`1`),
a docker exec failure (`126/127`), and a signalled child (`128+n`).

And it is not merely diagnostic. Once the rollback branch reads `(( BWRAP_RC != 0 ))`, a wrong `0`
means **the gate stops gating**. Measured under mutation: reverting to the `if !` form emits
**zero** rollback lines — it fails OPEN and ships a broken sandbox.

### 2. A guard's own re-emit can route around the sanitizer applied one line later

The fix sanitized the capture for the `logger` leg and printed the RAW value to stdout seven lines
earlier. `ci-deploy`'s stdout is **not** dark: it runs under `adnanh/webhook -verbose`, which
captures the hook command's combined output and re-logs it, and `vector.toml` allowlists
`SYSLOG_IDENTIFIER="webhook"` next to `"ci-deploy"`.

Verified in production — `Verifying bwrap sandbox...`, a plain `echo`, is queryable in Better Stack
under the webhook tag. The plan had measured this and said in terms that the comment must not repeat
the discard claim. The implementation wrote that claim into a code comment anyway.

**Rule:** when a diff sanitizes for one sink, enumerate EVERY sink the same bytes reach — and check
the diff's own PROSE against the measurement, not only its code.

### 3. A prefix list is the same claim as a name list

Shape-anchored redaction was chosen over name-anchoring because "a name list is a claim about which
vendors exist". A **prefix** list is that same claim differently spelled, and it was already wrong
for the estate's most valuable secret: `BYOK_ENCRYPTION_KEY` is `openssl rand -hex 32` — 64 bare hex
characters, no marker of any kind — and its loss makes every customer's stored BYOK credential
permanently unrecoverable. `ANTHROPIC_API_KEY` (`sk-ant-…`, hyphens) misses the Stripe rule for the
same reason. Thirteen real prd secret classes matched no rule.

The repair needs no prediction: a **value-based arm** substituting the container env file's own
values. Precedent was already in this repo's Art. 30 register — the #6982 `git-data-emit` bracket
records a value arm for "the LUKS passphrase, **which no pattern could match**".

### 4. The fix for the bypass over-corrected into a live defect

`\b` is defeated by any preceding word character (`ZZZZsk_live_…` does not match). Removing it made
the JWT rule match **mid-word**:

```
bwrap: cannot open /usr/lib/x86_64-linux-gnu/libkeyring.so.1  ->  …/libkeyJ.REDACTED
error: /etc/keystore.p12.bak is unreadable                     ->  error: /etc/keyJ.REDACTED …
```

A missing-shared-object error is one of the likeliest real causes of a failing `docker exec … bwrap`
— the 126/127 class — so the sanitizer was destroying the diagnostic the change exists to produce.

**Two mutation batteries were green through this**, because every retention canary in the file
(`SENTINEL_LEAK_CANARY`, `TAILSENTINEL7095`) is a bare `[A-Z_]` token containing no `.`, `:`, `/` or
`ey` — the shape *least* exposed to realistic over-redaction.

Correct form: `(^|[^A-Za-z0-9])` for prefix rules (stricter than `\b` — it admits `_`, so
`FOO_sk_live_…` matches), and a literal `eyJ` with 8-char segments for JWT, self-anchoring because
`eyJ` is base64 for `{"`.

## Key Insight

**Fixture retention with the shapes over-redaction actually eats** — a path, a `sha256:` digest, a
`host:port`, a dotted filename — not with a token chosen for being obviously non-secret. A retention
canary selected for looking un-secret-like is selected for being immune to the failure mode.

## Session Errors

1. **Read a pipeline's status instead of the command's.** `git push … | tail` then `echo "rc=$?"`
   reported **rc=0** on a REJECTED push. The documented trap, hit anyway.
   **Prevention:** capture into a variable on its own line (`out=$(cmd 2>&1); rc=$?`) — never read
   `$?` after a pipe.
2. **Launched the mutation battery detached and it never started.** `setsid nohup … &` from the Bash
   tool was reaped when the tool call's shell exited. No `run.log`, no `results.txt`, no processes —
   and "no rc yet" was byte-identical to "still running" for ~15 minutes.
   **Prevention:** verify a detached launch by its artifacts within one call (does the log file
   exist?), not by the absence of an rc file.
3. **Wrote a code comment asserting a premise the plan had explicitly measured false** and had
   forbidden repeating. See §2.
   **Prevention:** for every causal claim a diff's prose ADDS, name the command that falsifies it
   and run it — and grep the plan for that claim first.
4. **Implemented the raw re-emit where the plan specified the sanitized value.** The plan's own code
   block read `BWRAP_ERR_SAN`.
   **Prevention:** diff the implementation against the plan's literal code blocks, not against its
   narrative.
5. **The first fail-closed test was vacuous.** It shadowed `sed` to force a sanitizer death, but
   `sed` is the pipeline's LAST stage, so the status is non-zero with or without `pipefail` — it
   asserted "the last command failed". Deleting `pipefail` did not red it.
   **Prevention:** to test a MID-pipeline death, shadow a stage that can never be last.
6. **The fail-closed harness broke its own instrument.** It extracted the function under test with
   `sed -n '/^_cred_err_tail()/…'` and then shadowed `sed` — so the shadow broke the extraction and
   the function was never defined. The case "failed" for a reason unrelated to the property.
   **Prevention:** extract under the real PATH; scope the shadow to the call only, with `hash -r`.
7. **`_cet` extracted one of two functions.** After `_cred_err_tail` gained a call to
   `_cred_redact_env_values`, the harness left the arm undefined and every value-based case silently
   measured the shape rules alone.
   **Prevention:** when a function gains a callee, extend every test-side extraction in the same edit.
8. **Used a PCRE negative lookahead with `grep -qE`.** `^((?!X).)*$` is not ERE; grep warned and
   rejected it, so the assertion could never have worked.
   **Prevention:** match the regex dialect to the tool — ERE has no lookarounds.
9. **Bulk-toggled every `tasks.md` checkbox to `[x]`**, including tasks that never shipped. This is
   the documented "an acceptance checkbox is a CLAIM" anti-pattern, committed verbatim.
   **Prevention:** never `replace_all` on `- [ ]`; tick each box against its evidence.
10. **`gh issue create --milestone 4`** — the flag takes the title, not the number.
11. **An unbalanced quote in a throwaway probe script** produced a bash EOF error.

## Near-misses worth keeping

- **`date +%s%3N` is not portable.** This host ships **uutils coreutils 0.8.0**, which ignores the
  `%3N` precision suffix and emits full nanoseconds (19 digits vs GNU's 13). Differencing those is
  garbage on one of the two environments. Use bash's `EPOCHREALTIME`, guard the locale decimal
  separator, and validate numerically before arithmetic — a non-numeric operand inside `$(( ))` is a
  FATAL expansion error that exits **even under `|| true`**.
- **GFM splits a table row on `|` BEFORE inline-code parsing.** Backticks do not protect a pipe in a
  table cell. A CLO-drafted Art. 30 bracket carried eight bare pipes inside backticked regex
  alternations; pasted verbatim the row would have split into nine cells and the amendment would
  have been **discarded at render while surviving in the raw file**.
- **A test helper that owns its own verdict is disarmable independently of `pass()`/`fail()`** and of
  any assertion-count floor. Flipping `failed=1` to `failed=0` voided four scenarios with the
  counters reconciling exactly. The remedy — an in-suite positive control driving the helper with an
  unmatchable input — was already established in the same file at `T-7095-3`, and was re-derived
  rather than found.
- **Region-scoping a mutation verdict hides true positives.** The review seat scored mutants by a
  13-assertion region and reported two survivors that a test outside that region had killed; the
  signature was present and discarded. Mirror of the battery's own failure: one scoped to mutations
  imagined, the other to the region thought to matter.

## Adjacent findings (filed separately, #8036 / #8037)

Both were invisible because a working fallback absorbed them:

- `docker login ghcr.io` fails on **every** deploy (53x in 7 days, `stage=relogin_failed` *after* a
  Doppler re-fetch), masked by the zot mirror.
- Image signature verification has **never** succeeded (53/53 `cosign_absent`), so the soak gating
  `IMAGE_VERIFY_MODE=enforce` can never pass — and flipping it today would fail-closed every deploy.

Same root: `error from registry: denied` on ghcr.io. A control that neither protects anything nor can
be safely enabled, with nothing surfacing that.

## Addendum — 2026-09-11 (ship-time review round, PR #8026)

The first panel ran 5 of the 12 seats the classification called for and emitted no coverage trailer;
with the threshold at `single-user incident` the ship gate blocked ready, so the other seven ran.
Three more findings of the class this file is about, plus one about the instrument that had passed
them.

### 5. A value-based redaction arm is order-dependent, and the test that "covered" it was satisfied by the leak

Substituting env values in file order let a SHORT public value that is a substring of a LONGER
secret rewrite the composite before the composite was matched — a bare `DB_HOST` listed before a
`DATABASE_URL` of the shape `scheme://user:password@host/db` shipped the password in clear beside a
`<redacted:DB_HOST>` marker certifying that redaction ran. The value-arm test asserted only that a
marker appeared, which this output satisfies. Fix: longest value first (pure bash selection — no
`sort`/`awk` on the redaction path, so a missing binary cannot downgrade the arm to a no-op), and the
test asserts the secret's **absence**. The general rule: a redaction test that checks for the marker
is checking that redaction *ran*; only the negative checks that it *worked*.

### 6. A `{1,200}` bound let a 100-char clamp survive the battery — an upper bound is not a length pin

The performance seat asked for a 64 KiB pre-clamp before the value arm (bash literal substitution is
quadratic in match count; a 4 MB stderr of a repeated env value took 148 s on the failure path). The
first mutant I wrote — clamp to 100 instead of 65536 — **survived** 249/249, because the truncation
scenario asserted `bwrap_err="[^"]{1,200}"` and 100 chars satisfy it. Pinned to `{200}` exactly
(nothing in that fixture is redactable, so sanitized length == clamp), plus a value-arm analogue of
F14: an env value straddling the 200-char window must be fully redacted, which a clamp of 230 also
fails. Geometry matters: the value has to be long enough (100 chars) that a straddle, a 230-cut and a
whole marker inside the window can all hold at once — the first geometry could not, and the control
run reddened on the marker being bisected (which is legal and the runbook says so).

### 7. "Not mechanically verifiable" was false — the soak the plan scoped out is exactly what `earliest=` is for

`tasks.md` cut the follow-through probe on the grounds that "landing the marker is its precondition,
so there is nothing to observe yet". The ship soak gate fired on #8016, and the override option
("the close criterion is genuinely not mechanically verifiable") did not apply: a Better Stack count
over a window is the sweeper's native shape, and `earliest=<deploy+7d>` IS the precondition. The probe
now decides between the issue's two closing arms, and never reprints the free-text field into the
public issue.

### Session errors, this round

- **M_clamp survived and I nearly recorded it as equivalent.** It was a test-strength gap (§6).
- **Straddle fixture geometry wrong on the first cut** — the control run reddened because the 23-char
  marker was bisected by the window, which is correct behaviour; I had asserted marker-present on a
  geometry where that cannot hold.
- **`source file | head` runs the source in a subshell** — `CREDS_REQ` came back empty and I briefly
  chased a parser bug that did not exist.
- **Ran a Claude hook script as a CLI** (`pre-merge-auto-close-scan.sh <file>`); it blocked on stdin
  until killed. The ship skill's own `auto-close-scan.sh <body-file>` is the CLI.
- **gitleaks rejected a code COMMENT** carrying a `postgres://u:PASSWORD@host/x` example
  (`database-url-with-password`). Describe the shape in words in comments; keep literal shapes to
  fixtures the scanner is configured for.
- **`--pr` mode of the PIR gate read the wrong "plan"** — it takes the first
  `knowledge-base/project/(plans|specs)/` path in the body, which was the mutation-battery record, and
  reported no signal; the real plan signals. Put the plan link first in the body, or feed the gate
  its corpus on stdin.
- **Preflight Check 10 named a script the PR deliberately did not build** — the archived plan's
  `discoverability_test.command` would have FAILed on a missing file, not on the property. Replaced
  with the real credentialed read under `credentials_required` (SKIP-DECLARED), old command kept in a
  superseded note.
