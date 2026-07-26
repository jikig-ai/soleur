---
title: "ADR-147: Boot-stage diagnostics live in baked host-scripts, not user_data"
status: accepted
date: 2026-07-26
issue: 6969
supersedes: none
amends: none
---

# ADR-147: Boot-stage diagnostics live in baked host-scripts, not `user_data`

## Status

Accepted — 2026-07-26 (#6969).

## Context

`soleur-web-2` booted DARK on the first real use of the `web-host-create` birth path. cloud-init
reached boot stage `doppler_download` and emitted a Sentry `fatal` whose entire payload was
`stage=doppler_download` plus `host_id`. The Doppler CLI's own stderr and exit code — the only data
that could discriminate the competing hypotheses — were discarded at the source behind a generic
`echo "FATAL: Doppler secrets download failed during initial provisioning" >&2; exit 1`.

The host's journald never reached Better Stack either, because Vector's ingest token comes from the
very Doppler fetch that failed. That silence is *expected* and is therefore not independent
evidence. So after the fact, four hypotheses (cold-boot DNS/dial race, Doppler rate limit or 5xx,
`DOPPLER_CONFIG_DIR` permissions on a fresh host, CLI-version behaviour) were all equally
consistent with the evidence, and none could be ruled in or out.

Three structural facts shaped the response:

1. **The gap was the shared emitter, not the call site.** The baked `soleur-boot-emit` — used by
   every boot stage from the bootstrap handoff onward — had no detail channel at all, while a
   *different*, inline emitter (`_emit`, early-runcmd only) already had a working one. Patching the
   one failing call site would have left every sibling stage equally blind.

2. **`user_data` is a hard budget.** The Hetzner cap is 32,768 B. The web host's base64gzip'd
   render measured 23,180 B against a 23,700 B tripwire budget — about 520 B of headroom — and
   *novel* inline shell costs roughly 0.46 gzipped bytes per raw byte. A retry loop plus stderr
   capture plus a sanitizer does not fit inline. Files listed in `local.host_script_files` are
   baked into the host image and cost **zero** `user_data` bytes.

3. **The failing call was the only unbounded Doppler invocation in the file.** Eleven sibling calls
   are wrapped in `timeout`; this one was not. An unbounded call that hangs emits nothing at all,
   so the error channel would have been structurally blind to the most common shape of the leading
   hypothesis. Bounding it is part of the error channel, not a separate robustness nicety.

## Decision

**Boot-stage retry and diagnostic-capture logic lives in the baked host-scripts, behind the
`host_scripts_content_hash` coherence gate — not in `user_data`.** `cloud-init.yml` carries only
the thin call site and the fail-closed re-raise.

Concretely, this ADR freezes four cross-consumer contract constraints:

1. **Emit `message` literals are frozen.** `"soleur-cloud-init boot stage"` and its three siblings
   are read by the birth-path gate's client-side regex *and* determine Sentry issue grouping.
   Changing a literal darks the gate **and** mints a new issue group — and on a fresh group
   `event_frequency { value = 1 }` means ">1", so a single fatal would stop paging entirely. Add
   tags; never rename the message.

2. **Alert-filtered stage names are frozen.** `sentry_issue_alert.web_terminal_boot_fatal` is
   `filter_match = "any"` over four bare `tagged_event { key = "stage" }` filters with no `level`
   filter. Renaming one darks the alert silently.

3. **A non-fatal breadcrumb may never reuse — or string-prefix — an alert-filtered stage name.**
   `"stage=doppler_download_attempt"` contains `"stage=doppler_download"`, which would make the
   op-contract test's anti-rename guarantee satisfiable without the real assignment. And because
   the alert's shared `soleur-boot-emit` group is perpetually hot, the *first* matching event
   pages: a single `warning` carrying a filtered stage name would page the founder on a healthy
   boot. Retry breadcrumbs therefore use the distinct, non-prefixing stage `doppler_retry`.

4. **Diagnostic detail is carried in a per-stage file, read by the shared emitter.**
   `/run/soleur-stage-detail.d/<stage>`, and nothing else. There is deliberately **no** fallback
   to the legacy single-buffer `/run/soleur-stage-detail`: an earlier revision added one "for
   compatibility", which made all nine `soleur-boot-emit` stages — including INFO emits on
   healthy boots — ship whatever the ghcr/pull producers had left in the shared buffer, i.e.
   another stage's captured output presented as this stage's cause. None of those stages has a
   legacy producer, so the fallback bought nothing and cost cross-stage contamination. A
   plausible WRONG cause is worse than an empty one. The legacy buffer, its five producers and
   the inline `_emit` consumer are untouched.

### Sanitizer contract

The emitter sanitizes in a fixed, load-bearing order:

| Step | Why |
|---|---|
| drop `^Using ` preamble lines | The pinned Doppler CLI v3.75.3 writes two `Using DOPPLER_* from the environment` lines totalling 173 B of the 246 B auth-failure stderr. A leading-bytes cap ships pure noise and truncates the cause away — this is what made `head -c 200` the wrong instrument. |
| strip ANSI CSI sequences | `NO_COLOR=1` is set at the call site, but the sanitizer must not depend on the producer's cooperation. |
| strip control characters | Keeps the payload JSON-safe. |
| drop `"` and `\` | Same. |
| fold newlines/tabs/CR to spaces | Newlines are documented as impermissible in Sentry tag values, and captured stderr is multi-line by nature. Also keeps words separated — the trailing ASCII pass would otherwise concatenate them. |
| trim leading/trailing whitespace | Defensive. The "Sentry drops untrimmed values" claim is undocumented, so this is cheap insurance, not a fix for a known vendor behaviour. |
| `tail -c 180` | Under the documented 200-char tag-value limit. An over-long value is **silently truncated at 2xx**, not rejected — so the cap guards against losing the cause inside a surviving event, not against losing the event. |
| printable-ASCII pass **after** the cap | `tail -c` is byte-wise and can split a multi-byte sequence. Ordering matters: the pass must run after the cut, not before. |

The producer additionally scrubs `dp\.[a-z]*\.[A-Za-z0-9_-]*` before any write. The measurement
that the CLI does not echo its token is pinned to v3.75.3, and CLI-version behaviour is itself an
open hypothesis, so the scrub is defence in depth rather than redundancy.

### Stream separation

`doppler secrets download --format docker` writes **the entire prd secret set to stdout**, and the
caller feeds that file to `docker run --env-file`. Stdout is therefore reserved: the helper writes
no stdout of its own, and `2>&1` / `&>` are forbidden in both the helper and the cloud-init region.
A stray stream merge would convert this feature into credential exfiltration, or corrupt the env
file so the resulting fatal is misattributed to `stage=docker_run`.

### Fail-closed call site

```sh
soleur-doppler-download "$TMPENV" && rc=0 || rc=$?
[ "$rc" = 0 ] || exit "$rc"
```

Both lines are mandatory and must not be collapsed:

- `if ! cmd; then ... $?` yields **0** in dash *and* bash, so the replaced form could only ever
  have recorded `exit_code=0`.
- An AND-OR list is **`set -e`-exempt**, so the capture alone silently continues the boot. The
  `exit 1` that made the old block fail-closed lived inside the `if !` branch being replaced.
  Without the re-raise, the two fall-through outcomes are a fatal mistagged `docker_run`, or a host
  reaching `cloud_init_complete` with an empty `$TMPENV` and no prd secrets. A green-and-secretless
  serving host is strictly worse than a dark one.

## Consequences

**Positive** — from the first host born on an image containing this change. `runcmd` is
once-per-instance and `hcloud_server.web` pins `user_data` under `lifecycle.ignore_changes`, so
hosts running today keep emitting the pre-#6969 payload; only the birth-path gate half is live at
merge. Every boot stage from the bootstrap handoff onward gains the *reader* side of a
detail channel for zero `user_data` bytes. `doppler_download` gets the only producer here.
A hang now produces `rc=124` as a distinct named condition where it previously produced silence.
The birth-path run annotation names the cause instead of only the stage, and boot events carry
`host_name`, removing the Hetzner API lookup that host attribution previously required on a shared
Sentry project.

**Negative / accepted.**

- Editing `soleur-host-bootstrap.sh` moves `local.host_scripts_content_hash` even though it costs
  zero `user_data`. A pre-merge `image_tag` now carries stale baked scripts and fails the
  coherence preflight. This is fail-closed by an existing gate — the outcome is a *refused
  dispatch*, not a second dark host.
- Only `doppler_download` has a detail *producer*. `docker_run` was planned as the second and was
  **cut at review**: `docker run --env-file` is handed the entire prd secret set, and docker's
  env-file parser quotes the offending line back verbatim on a parse error, so capturing that
  stream routes secret bytes into a tag on a paging alert and into the run log. No regex closes
  it — a secret *value* is arbitrary text, not a matchable shape. Measured 2026-07-26: the prd
  config is 129 keys / 129 lines, so the leak was latent, and would go live the day a multi-line
  secret (a PEM key, a service-account JSON) is added. Wiring `docker_run` safely means
  classifying the failure without echoing the stream; tracked with the remaining stages in #6971.
  Every other stage has the reader and an empty channel.
- The bounded retry adds worst case ~114 s: 3 attempts × (`timeout -k 5 20` = 25 s) + 5 s + 10 s
  backoff + 2 × a 12 s-bounded retry breadcrumb. Every term is bounded deliberately. `TMO` is 20 s,
  not 45 s, because the full prd download measures 0.27–0.33 s (129 secrets) — ~60× headroom on
  the success path while bounding the failure path tightly. The in-loop `soleur-boot-emit` calls
  are `timeout`-wrapped because the emitter's transport is `curl -m 10 --retry 3`, and `-m` is
  *per transfer*: one emit's worst case is ~47 s, and it is slowest exactly when it is called
  (the faults that fail the Doppler fetch are the same ones that make the Sentry POST hang).
  Unbounded, two in-loop emits added ~94 s of failure-correlated latency. This matters because
  `soleur-host-bootstrap.sh`'s own 900 s fresh-boot derivation sums to exactly 900 with no slack
  term and does not include this stage at all (the pre-#6969 call was unbounded and implicitly
  costed at zero); overshooting converts a *diagnosable* `fatal` into an *undiagnosable* `timeout`
  and trips the Better Stack absence alert that shares the window as its grace period.
- `rc=0` is not accepted as success on its own. `doppler` can exit 0 having written nothing, and
  `docker run --env-file <empty>` then *starts* the container: the host reaches
  `cloud_init_complete`, the gate reports "booted clean", and it serves with zero prd secrets. A
  green-and-secretless serving host is strictly worse than a dark one, so an empty payload is a
  distinct named failure (`cond=empty_payload`, rc 71).
- Correlated failure is named, not papered over: the emitter's only transport is `curl` to Sentry,
  so a *total* egress failure disables the discriminator for the hypothesis most likely to have
  caused it. In that case the gate's `timeout` verdict is the only signal, and that verdict is
  itself the documented dark-boot signal. No SSH or serial-console step is prescribed.

**Explicitly not addressed.** This ADR does not diagnose the `soleur-web-2` failure. `runcmd` is
once-per-instance and `lifecycle { ignore_changes = [user_data, ...] }` means the template never
re-reaches a live host, so nothing here repairs that host. It makes the *next* occurrence diagnose
itself.

## Alternatives considered

| # | Alternative | Verdict |
|---|---|---|
| A1 | Add `2>` at the one failing call site | **Rejected.** Leaves every sibling stage blind and costs more `user_data` per unit of coverage than fixing the shared emitter. |
| A2 | Ship the error channel alone; cut the bounded retry | **Recorded as a User-Challenge, not applied.** Two independent signals argued for it. Retained because #6969 explicitly scopes it, because it is not a fix for a *diagnosed* cause (all hypotheses remain open), and because the retry is evidence-*preserving* — each failed attempt emits its own breadcrumb. Phase 2 is deliberately separable and is the designated descope target. |
| A3 | Carry the payload in Sentry `extra` rather than a tag | **Partially adopted as available depth.** The initial rejection rested on "no in-repo emitter sends `extra`", which was **false** — four emitters already ship `extra` to this exact endpoint. The decision stands on the true ground: tags are indexed and the birth-path gate's `jq` reads `.tags[]`, where `extra` is not exposed. |
| A4 | Ship stderr via journald → Vector → Better Stack | **Rejected.** Structurally impossible: Vector's token comes from the very fetch that failed. |
| A5 | A `<stage>\|<detail>` wire format in the legacy buffer | **Rejected** in favour of per-stage files. The wire format created a delimiter collision with content that already contains the delimiter, a migration nobody owned, and — because any per-emit buffer clear lets the last failed attempt consume the buffer — an empty `detail` on the terminal fatal, which is byte-for-byte the #6969 symptom. |
| A6 | Amend ADR-082 instead of writing a new ADR | **Rejected** — ADR-082 is `superseded-in-part`, so new forward-looking constraints buried there force every future reader to reconstruct which items survive. |

## Verification

`apps/web-platform/infra/doppler-download-error-channel.test.sh` (registered in
`.github/workflows/infra-validation.yml`) extracts both baked heredoc bodies and drives
helper → trap → the **real** `soleur-boot-emit`, asserting on the emitted body rather than on
source greps. Stubbing the emitter would remove the component under test, since the detail gate
lives inside it; and grep-shaped criteria are evadable (`if ! soleur-doppler-download` reintroduces
the `$?`-is-zero defect while still satisfying a grep for the call).

The suite is mutation-verified by a **committed** harness,
`apps/web-platform/infra/doppler-download-error-channel.mutation.py`: 30 mutations, each neutering
exactly one defence, all detected. The harness is committed rather than asserted because an
uncommitted matrix is a claim nothing re-checks — and this PR is the proof of why that matters.
The first, self-authored battery reported 23/23 detected while the suite could not see that the
`test -x` assertions ran before the files existed (every fresh host would have powered off), nor
21 further mutants a review pass found. A battery only ever covers the mutations its author
imagined; the harness is the floor, not the ceiling.

## References

- #6969 — the dark boot this ADR responds to.
- ADR-082 Item 5 — the terminal-block boot-emit trap this extends (its own status is unchanged).
- ADR-145 — the `web-host-create` birth path whose first real use surfaced the gap.
- ADR-080 / #5921 — the bake-and-extract mechanism that makes baked host-scripts cost 0 `user_data`.
- `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md`
  — the same class: ship the component's own error channel before black-box reproduction.
- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
  — why every hypothesis here stays open rather than being reasoned to a verdict.
