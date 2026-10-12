---
title: "security: argv-bearer sweep, held-back HMAC and heartbeat sites, htpasswd argv, inspect-evidence xtrace refusal"
type: fix
date: 2026-10-12
slug: argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence
branch: feat-one-shot-9757-argv-bearer-sweep-combined
issue: 9757
closes: 10089
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix(security): argv-bearer sweep, held-back HMAC and heartbeat sites, htpasswd argv, inspect-evidence xtrace refusal

## Enhancement Summary

**Deepened on:** 2026-10-12 (after plan-review by DHH, Kieran and code-simplicity; CTO assessment; then security-sentinel, architecture-strategist, observability-coverage-reviewer and test-design-reviewer; gates 4.6-4.12 and 4.55 run).

### Key improvements

1. **The registry template merge replaces the production registry host automatically** (`registry-host-replace-dispatch.yml` has a push trigger on `cloud-init-registry.yml`; the first draft said "no live effect"). The registry slice is now the last, one-commit, peel-before-merge slice, recommended as its own PR, with the first-live-execution risk of the boot block retired offline on the shipped host image.
2. **The inngest heartbeat body is POSIX `sh`** (dash): process substitution would have killed the live beat. It uses a heredoc; the shape guard is a negated-class `case`, measured under dash; the three scripts no longer share a byte-identical copy.
3. **The census allowance moved to the single code view** both regex sites already read through, as a fixed-string whole-line match (an ERE built from the canonical python body is fragile), and the S4 stage's own hold-back rows, the `EXPECTED_TESTS` floor and the S2-A literals are named.
4. **Coupling table completed:** `web-platform-release.yml` fires on every `apps/web-platform/**` and non-docs plugin change (a production app deploy); squash-merge means per-commit staging is a pre-merge peel point only.
5. **Test placement corrected:** the real-binary/container rows move to a new infra suite (the `scripts` shard asserts no docker); several existing negative rows go vacuous once the URL leaves argv and are enumerated; `web-git-data-probe.test.sh` never executed its transport line.
6. **Measured:** `htpasswd -i` on `ubuntu:24.04` and `httpd:2.4-alpine` (exit codes, hash cross-verification, 72-byte truncation parity, 255-byte stdin limit); small heredocs are pipes in dash, busybox and bash 5; curl's config parser treats only `\` and `"` specially inside quotes.

### New considerations discovered

- `/etc/zot/htpasswd` is created under the default umask and chmod'd after (a world-readable window the rewritten lines can close at no byte cost).
- Same-class residuals (#10093): three more heartbeat probe scripts, the registry heartbeat curls, the Cloudflare admin token in `apps/cla-evidence/infra/object_lock.tf`, the `psql "$DATABASE_URL"` class, and agent-executed markdown bearer snippets.
- The 60 s inngest heartbeat would flood a persistent refusal marker; it reuses the hourly rate limiter.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The argv-credential sweep (tracker #9597, closed; ADR-280, status `adopting`) moved credentials off process command lines
across scripts, workflows, composites and cloud-init. What it deliberately left is tracked in the open umbrella #9757 and,
for the zot `htpasswd` passwords, in a #9757 comment from S5 (#9986). This plan finishes that residue in one combined PR, at
the operator's explicit direction ("ONE combined PR covering four slices, overriding the earlier one-slice-per-PR rule"):

- **A** (the #9757 checklist): the two held-back `openssl dgst -hmac "$WEBHOOK_SECRET"` arms of `scripts/cutover-inngest.sh`
  plus the two census regexes of `apps/web-platform/infra/cutover-inngest-workflow.test.sh` that forced the hold-back; the
  heartbeat-URL path secrets in `inngest-bootstrap.sh`, `web-git-data-probe.sh`, `luks-monitor.sh`; the `linkedin-setup.sh`
  `write-env` validator and the community-suite manifest row that pins its absence; the Better Stack stderr item (already
  done, see Research Reconciliation); and the review leads (a)-(h) that are tractable.
- **B** (untracked, now added to #9757): `htpasswd -vb` / `htpasswd -Bbn` password-on-argv in `cloud-init-registry.yml` and in
  `.github/workflows/apply-web-platform-infra.yml`.
- **C**: `apps/cla-evidence/scripts/inspect-evidence.sh`, the last cla-evidence row of baseline A. Tracker filed first: #10089.
  It is NOT an argv conversion: the script already passes the R2 pair as per-command environment prefixes to `aws`; what is
  missing is the xtrace refusal (#7797).
- **D**: archive the finished cla-evidence SigV4 plan and spec with `archive-kb.sh`.

Merging A or B fires production workflows (the push-triggered infra apply, and for one file the inngest bootstrap tag mint),
so the section "Production-apply coupling" below is load-bearing: it names exactly which files fire what, what each firing
does to a live host, and recommends the staging. The PR is built, reviewed and QA'd here; it STOPS before merge for explicit
operator approval of the merge and of the apply notice.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / #9757 | Reality on `origin/main` (2026-10-12) | Plan response |
|---|---|---|
| Better Stack stderr is discarded in `scheduled-inngest-health.yml` and `git-data-cutover.yml` (item 4) | **Already done in PR #9811** (comment on #9757 says so; ADR-280 Consequences line records it). Both callers capture to `$BS_ERR`, re-emit the `SOLEUR_CREDENTIAL_REFUSED` line whether or not the classifier library loads, then a `::warning::` carrying `bs_read_scrub_err1`. Only the classifier `source` keeps a `2>/dev/null`. The host-pin `exit 2` refusals in `betterstack-query.sh` (lines ~208-210, ~227-229) print no marker, but the `::warning::` still carries their first stderr line, so they are visible. | No code. Tick the item with PR #9811 evidence; add one verification row (no `2>/dev/null` on either reader invocation) only if the battery lacks it. |
| `inspect-evidence.sh` is an argv-bearer script | It has **no curl** and sources only `_r2-endpoint.sh`. `aws_exec()` passes the pair as env prefixes. The baseline row is Rule A (xtrace refusal missing), not a curl-argv row. | Slice C is the Rule A preamble plus tests plus baseline-row deletion. No transport change. |
| htpasswd sites are "not in #9757's body" | Confirmed: only a #9757 comment from S5 notes them. | Added to #9757's body as two checklist items on 2026-10-12 (done during planning). |
| `cloud-init-registry.yml` can simply be edited | It is the `templatefile` source of `hcloud_server.registry` `user_data`: ForceNew, no `ignore_changes`, Hetzner cap 32,768 B, repo budget `REGISTRY_GZIP_BUDGET = 21_600` in `plugins/soleur/test/cloud-init-user-data-size.test.ts` against **~21,500 B stored** after S5 (`registry-userdata-budget.sh` measures). | The htpasswd edit has **~100 B** of headroom. Measure before and after; if over, strip bytes elsewhere in the same change (never raise the constant to fit). A running registry host never sees the edit until a registry host replace (`registry-host-replace-dispatch.yml`). |
| Lead (a): `-H @-` at `cutover-inngest.sh` ~558 and own `--config -` at ~3117 | Present at 559 (printf at 556) and 3123. | In scope (tractable). |
| Lead (b): seven `::add-mask::` sites | Eight real sites; only 1878 and 3269 shape-check first; six unguarded (550, 2470, 2472, 2488, 2559, 2561). | In scope: shape-check-then-mask at the six. |
| Lead (e): `MARKER_RE` comment in `apps/web-platform/server/git-lock-marker-telemetry.ts` | Present (`MARKER_RE` at 153). Any `apps/web-platform/**` change fires `web-platform-release.yml` (a production app release) and a tsc/vitest cycle for a comment. | **Defer** to its own tracker; filed at implementation as a `deferred-scope-out` issue (milestone Post-MVP / Later). |
| Lead (f): activation/fatal-channel probes refuse before reading evidence | The activation probe (`scripts/followthroughs/infra-config-activation-7220.sh:69-86`) already guards with `_bearer_ok` and TRANSIENT. Fatal-channel probe not verified. | Verification step in Phase 6; code only if a gap exists. |
| Lead (h): no gate runs real bash 3.2 for `hmac-sha1-b64.sh` | Measured now: `docker run bash:3.2` (3.2.57) with `openssl` added: `hmac_sha1_b64` produced the same digest as `openssl dgst -sha1 -hmac ... -binary \| base64`. The construct is fine today; what is missing is a gate. | In scope, small: a digest-pinned bash-3.2 row beside the existing opt-in pinned-image row. |
| "Merging A or B fires the production apply" (brief) | Also fires `web-platform-release.yml` (any `apps/web-platform/**` or non-docs `plugins/soleur/**` change = a production app release and container deploy) and, for `inngest-bootstrap.sh`, `mint-inngest-bootstrap-tag.yml`. | Production-apply coupling table lists all three firings. |
| The three named heartbeat scripts are the heartbeat-URL population | Three more probe scripts (`web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh`), the registry cloud-init heartbeat curls and four skill markdown snippets carry the same class. | Out of the ask; tracker #10093; Guard 2's derived population lists them as a shrinking residual allowlist. |
| The inngest heartbeat can use the bash `< <(printf ...)` transport | `inngest-bootstrap.sh`'s heartbeat body is `#!/bin/sh` (run as `sh` by `inngest.test.sh`); on Ubuntu `/bin/sh` is dash. | Heredoc form for that script (A2 table); dash row. |
| Open draft PR 10073 edits `inngest-bootstrap.sh`; draft PR 7390 edits `apply-web-platform-infra.yml` | Confirmed from `gh pr view` file lists (10073: also `inngest.test.sh`, `cloud-init-inngest.yml`; 7390: also `reusable-release.yml`, `Dockerfile`, AGENTS files, stale since 2026-09-21). | See Dependencies & Risks R4/R5: scopes do not overlap, hunks may. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited and checked: #9757 OPEN (body read in full, three comments read); #9597 CLOSED;
#7797 OPEN; #9905 OPEN (follow-through, not code); #7675 OPEN (cla-evidence plan job, not ours); PR 10086 draft OPEN (this
branch); PR 10073 and 7390 OPEN drafts. Cited paths checked on the branch: `apps/cla-evidence/scripts/inspect-evidence.sh`,
`_r2-sigv4-curl.sh`, baseline row 5, htpasswd lines 637/2558/2559 and 2958, `cutover-inngest.sh` lines 1372/1546, all present.
Stale: the Better Stack stderr item (done), the "seven" mask sites (eight), and two line numbers. Mechanism check against the
ADR corpus: ADR-280 names the held-back sites as an S4 obligation and carries a 2026-10-11 (#9756) addendum; no ADR rejects
`htpasswd -i` or inline heartbeat guards (no ADR mentions htpasswd).

**Property List (Phase 0.6b).**

1. No credential from the five classes below is readable in `/proc/<pid>/cmdline` or `ps` for the life of its child:
   the webhook HMAC key (2 arms), the three heartbeat URLs, the zot pull/push passwords and the rehearsal password.
2. A malformed stored value makes zero requests and prints a value-free refusal line that lands in the same verdict class as
   the old failure (ADR-280 decision 3), so a rotation or storage accident is a visible refusal, not a silent heartbeat gap.
3. The two guards that forced the hold-back (the tool census) still catch a stray tool call in the read-only probe arms.
4. A recurrence is a RED row, not a future sweep: the htpasswd class and the held-back class each get a derived-population row.
5. `inspect-evidence.sh` refuses to run under `bash -x` while the R2 pair is in its environment, and baseline A shrinks by its row.

**Cut List (Phase 0.6b).** Mechanisms the brief or issue named, checked against `origin/main`:

- *A new shared library for heartbeat pings* → cut: the precedent already exists inline (`scripts/inngest-probe-heartbeat-feeder.sh`
  `URL_RE` plus `printf 'url = "%s"\n' | curl --config -`) and the S5 registry template carries an inline guard copy; the
  three host scripts have no checkout, so a sourced library is unreachable there (not in `server.tf` file lists, the image
  `COPY` list, or the luks tar bundles). Shipping `bearer-curl.sh` to hosts would add four file lists to the apply surface.
- *A new htpasswd linter / Rule F in `lint-shell-trace-credential-refusal.py`* → cut: four sites, one derived-population row in
  the existing battery covers recurrence (Property 4) without growing the 2.5k-line linter and its baseline machinery.
- *Lead (c) `flock` + atomic `mv -f` across the four setup scripts and `soleur_op_env_upsert`* → cut from this PR (own tracker):
  it rewrites byte-identical blocks in three scripts the suite pins, for a local-tooling race (measured duplicate keys), and
  buys none of Properties 1-5.
- *Lead (e)* → cut (own tracker): buys no property; costs a production app release.
- *Better Stack stderr surfacing* → cut: already done (#9811).
- *Host pin and `--disable --noproxy '*'` on the heartbeat curls* → cut (reviewer finding, measured reasoning): the only real hazard is config-directive injection through `url = "%s"`, which a charset guard closes without ever mis-refusing a healthy URL; the transport flags are unmeasured on these hosts.
- *A shared census helper function and a "byte-identical copies" parity row for the heartbeat guards* → cut: the allowance goes into the code view both census sites already share; the three guards are different shells and are covered by a derived-population row.
- *A lexer-grade htpasswd scanner and a digest-pinned always-on bash 3.2 row* → cut: a grep with a floor, and a `bash:3.2` run folded into the existing opt-in docker row.
- Considered and kept out: the other `curl` sites that take a heartbeat URL (`cloud-init-registry.yml` ~292 and ~1094,
  baked into `user_data`, already readable through the Hetzner metadata API), the S4 comment's other URL-path secrets (Slack
  webhook URL, `psql` URIs, `seed-live-verify-user.sh`), and the library gaps. They are listed in #9757's comments, not in the
  ask; they stay open there.

**Relevant learnings** (read, applied below):

- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: process
  substitution, never a pipe, for the stdin config; a ratchet keeps the class closed.
- `2026-10-12-a-sigv4-pair-on-argv-needs-a-helper-whose-callers-carry-the-trace-defence.md`: every caller owes the xtrace
  refusal; emptying a baseline breaks anti-vacuity floors and "first real row" mutation rows in the lint suite (check
  `scripts/lint-shell-trace-credential-refusal.test.sh` before deleting row 5).
- `2026-10-09-a-revert-recipe-dry-run-must-run-every-gate-and-no-openssl-flag-reads-an-hmac-key-from-stdin.md`: the only
  argv-safe SHA-256 route is the python3 env-prefix canonical line, already used by 17 copies.
- `2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md`: `htpasswd -vb` exit codes
  (0 match, 3 mismatch, 6 user absent, 1 file unreadable, 127 missing); only 3 is divergence; `$${VAR:-}` escape in
  templatefile; `/etc/zot/htpasswd` is baked once at boot.
- `2026-07-11-col0-templatefile-directive-breaks-raw-yaml-parsers-sweep-all.md`: no column-0 template directives.
- `2026-09-30-bound-every-network-subprocess-emit-marker-per-non-success-arm.md`: bash 3.2 empty-array and `;&` traps.
- `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`: a heartbeat URL feeds one monitor; do not reuse.
- `2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md`: `--changed` drops the baseline for
  any touched file, so debt is paid in the PR that touches it. Run the changed-file lint first (Phase 0).

**Deepen-plan gate evaluation (2026-10-12).** 4.6 user-brand impact: present, `aggregate pattern`. 4.7 observability: five fields present, probe command passes `probe-verb-gate.sh`, has no shell-active character, and prints `FAIL` on `main` by design (the RED reading) and `OK` once Phase 4 lands. 4.8 PAT sweep: no match. 4.9 UI wireframe: no UI surface. 4.10 encryption posture: the path pattern `cloud-init.*\.ya?ml$` matches `cloud-init-registry.yml`, but the plan introduces no persistent store and no connection (it changes how a password reaches `htpasswd` inside an existing boot step), so per plan Phase 2.11 it skips; recorded here rather than as a vacuous section. 4.11 guard contract: `lint-guard-contract.py` green, 4 entries; assembly reads structural (chokepoints named). 4.12 scope check: one unfenced section, no `unmapped` cell, no BLOCKED marker. 4.55 downtime: addressed in `## Downtime & Cutover`. Founder-stated check: skipped (headless).

**Measured now (not argued).** On `httpd:2.4-alpine`: `printf pw | htpasswd -Bin user` hashes; `printf pw | htpasswd -vi file
user` verifies with exit 0 (match), 3 (mismatch), 6 (user absent), 1 (file unreadable) — the same codes the probe branches
on; a trailing newline on stdin still matches; empty stdin reports mismatch (3). On `bash:3.2.57`: the community HMAC helper
agrees with the `openssl` oracle. Tracker #10089 filed; #9757 body updated with the two new items. `plugins/soleur/test/c4-count-parity.test.sh`: green.

## Problem Statement / Motivation

Every item is the same exposure class: a secret that lives for the duration of a child process in a world-readable
`/proc/<pid>/cmdline`. The reader is any local uid on a host or any compromised step on a hosted runner. The class is small
per site and high in aggregate, which is why ADR-280's brand-survival threshold is `single-user incident` for the library and
why this residue is tracked rather than dropped. Residuals that remain after this plan are recorded in the ADR addendum:
same-uid and root readers of `/proc/<pid>/environ`, and the child environment of the python3 HMAC process.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the product surface directly. The failure shape is operational: a
  false credential refusal in a heartbeat script stops the liveness beat, which pages "host down" (git-data reachability,
  workspaces LUKS monitor) or, for the dedicated Inngest host, withholds the beat; a false refusal in the registry probe
  reports `htpasswd_*_matches=unknown` instead of a verdict. Scheduled agent work (Inngest) is the user-visible dependency.
- **If this leaks, the user's workflow is exposed via:** a local reader of `/proc/<pid>/cmdline` seeing the Better Stack
  heartbeat URL (lets an attacker spoof "alive" for a monitor), the webhook HMAC key (lets them sign deploy-webhook calls, the
  highest-value item), or the zot registry pull/push passwords (read/write of the private image registry the web hosts pull from).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** each site is a same-host local-reader exposure of a rotatable credential with no
  user data on the path, so `aggregate pattern` rather than `single-user incident`; the library ADR carries the higher tier
  because a defect in it reaches 22 workflows, which this PR does not touch (`scripts/lib/bearer-curl.sh` is unchanged).

## Proposed Solution

### A1. Held-back HMAC arms (`scripts/cutover-inngest.sh`, census, battery)

- Replace the `SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')` line in the `registry-probe)` arm
  (content anchor: the line after `# ---- registry-probe host-state gate`, ~1372) and in the `doublefire-probe)` arm (~1546) with the CANONICAL form
  already used by the other 17 copies, byte for byte: `SIG=$(printf '' | HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c '...') || SIG=""`
  (same python body as `bc_hmac_sha256_hex` in `scripts/lib/bearer-curl.sh`; the `enumerate)` arm at ~1328 is the exemplar).
  No openssl flag reads an HMAC key from stdin, so the env-prefix form is the only argv-safe one.
- **Census allowance (the ask's "two census regexes").** Both regex sites (`apps/web-platform/infra/cutover-inngest-workflow.test.sh`: the
  `#6617 probe arms make exactly 2 network/tool calls` assertion ~1850 and `check_rpg_tool_count` ~3365) already read the arms through ONE code view,
  `_probe_arms_code_of` (~1815: comments dropped, echo arguments emptied, continuations joined). Put the allowance there, as a final filter that deletes, after trimming leading
  whitespace, only lines **byte-equal to the two exact permitted forms** (the canonical assignment with and without its `|| SIG=""` tail), by fixed-string whole-line
  comparison (`grep -vxF -f <forms>` or `awk '$0==c'`), never an ERE built from the canonical text (its python body carries `.`, `(`, `|` and `[`, and one unescaped
  `|` makes an anchor bind to a single branch). Any appended `; python3 ...` or `; curl ...` leaves the line in the view and the count moves; the filter also hides
  the line from the other predicates on the same view (body flags, doppler, loops), harmless for fixed text and stated in the comment. Before the filter runs, a row
  asserts exactly one canonical line per arm. Neither regex then needs to change, and they cannot drift apart. The deviation from the
  ask's wording (edit the regexes) is deliberate and recorded in Scope Check: the property the regex edit buys is bought once, at the chokepoint.
  The census counts LINES (`grep -cE`), so one canonical line is one allowed line; a second tool on the same physical line is the append mutant above.
- `tests/scripts/test-argv-bearer-sweep.sh` STAGE S2-A part 2 (~1712-1910) encodes the hold-back: 17 converted copies, the `-hmac` operand at exactly the
  two arm anchors, the "one-line comment naming plan decision D1" row, and mutation rows pinned on arm counts. Rewrite to the end state: 19 converted copies,
  zero `-hmac` operands left in the script, the D1 comment row removed with the comments it counted, mutation rows repointed (reverting either arm to `-hmac`
  must red the parity row; the stray-tool mutants red the census). The hold-back comments in `cutover-inngest.sh` are deleted with the sites.
  **The S4 stage encodes the same hold-back and must move in the same commit** (`tests/scripts/test-argv-bearer-sweep.sh`, content anchors): `S4_HMAC_ALLOW="scripts/cutover-inngest.sh:2"` and the census rows that require `S4_CENSUS_HITS >= S4_CENSUS_HIT_FLOOR` and `RAW_N > hits` (they go red at zero hits, and the wrapper control uses the cutover script as its known positive: give it a synthesized positive instead); `S4_HM_COPIES_WANT=24` and `S4_HM_HELD == 2`; the `hm_hmacflag` reader (~2901); the S2-A rows `hm_audit_ok`, the `seq 1 17` loops, `hm_last == 17`, `HM_PYARMS == 0` (false by design now) and the `heldpy`/`heldpy2` mutants. Phase 6(d) also empties `S4_HMAC_MD_ALLOW` (ship/SKILL.md and deploy-status-debugging.md). The battery's literal `EXPECTED_TESTS=730` floor (with `SELFTEST_PASSES`) is re-pinned to the measured total after the row changes; never left loosening silently.
- Leads in the same file. `scripts/cutover-inngest.sh` is not an apply path (`cutover-inngest.yml` triggers only on itself and dispatch):
  (a) at the `-H @-` feed (~556-559, anchor `printf 'Authorization: Bearer %s\n' "$tok"`) run `_bearer_ok "$tok"` first (a refusal takes the existing
  empty-token arm's verdict class and prints the marker the way the other arms do); at the local `--config -` (~3123, anchor `Credential headers ride curl's stdin
  config channel`) judge `$SIG` and both Cloudflare Access values before the call;
  (b) at the six unguarded `::add-mask::` sites (~550, 2470, 2472, 2488, 2559, 2561) shape-check first and mask second (the `backup)` arm's order at ~1878 and ~3269),
  keeping `-n` so an empty read never prints a bare directive;
  (g) at the four body echoes (~1344, ~1511, ~1575, ~1727) print a bounded, scrubbed first line instead of the raw body to the public log.
  Each gets a recording-curl row in the battery's existing S2-A harness. RED edits are local only; every pushed commit is green.

### A2. Heartbeat-URL path secrets (three host scripts, inline guard)

Three scripts curl a Better Stack heartbeat URL whose **path is the secret**, each on a host with no repo checkout (so no sourced library; the S5 registry
template and `scripts/inngest-probe-heartbeat-feeder.sh` are the inline precedents). The three scripts are NOT the same shell, so the guard and the transport
line differ by script (no byte-identical-copy parity row; one derived-population row instead, Guard 2):

| Script (content anchor) | Shell | Transport line | Refusal marker goes to |
|---|---|---|---|
| `luks-monitor.sh` retry loop (`hb_pushed=false` / `curl -gfsS --max-time 10 "$hb_url"`, ~437) | bash, `set -uo pipefail` | `curl -gfsS --max-time 10 --config - >/dev/null 2>&1 < <(printf 'url = "%s"\n' "$hb_url")` | its existing `log` helper (journald, `LOG_TAG=luks-monitor`) |
| `web-git-data-probe.sh` `_ping()` (~40, two `\|\|`-chained attempts) | bash, `set -u` | the same form, one fresh substitution **per attempt**; `-g` is NEW here (the script has none today) | stderr `echo` (no `LOG_TAG`/`logger` in this script; the unit's SyslogIdentifier ships it; a literal `logger -t` would break the vector-pii-scrub drift fixture) |
| `inngest-bootstrap.sh` heredoc `HEARTBEATSCRIPTEOF` (~308, `exec /usr/bin/curl -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL"`) | **POSIX `sh` (dash)** — `#!/bin/sh`, run as `sh` by `inngest.test.sh` | `exec /usr/bin/curl -gfsS --max-time 10 --config - >/dev/null <<HBCFG` with the body `url = "$INNGEST_HEARTBEAT_URL"` and a closing `HBCFG` line (a heredoc, never process substitution, and no line starting with `printf`/`echo`/`logger` that names the URL: `inngest.test.sh` ~608 bans exactly that; the nested `HBCFG` heredoc must not disturb the awk block extraction and `LOG_TAG` derivation at `inngest.test.sh` ~140 and ~320, nor `ci-deploy.test.sh` ~6059's systemctl count, so both suites join the Phase 0 baseline; dash, busybox ash and bash 5 give a small heredoc a pipe, not a file, measured via `/proc/self/fd/0`) | the script's existing `logger -t "$LOG_TAG"` |

- **Shape guard.** With no trimming (a trailing whitespace or any control byte is refused, matching the SigV4 helper), the value must be non-empty, start with
  `https://`, and contain only `[A-Za-z0-9._~:/?&=%+-]` after the scheme. In the POSIX script this is a `case` over the part after the scheme with a **negated** class, never `[[ =~ ]]` and never a positive pattern (a positive `https://[...]*` only constrains the first character, because `*` matches quotes and newlines): `case ${v#https://} in ''|*[!A-Za-z0-9._~:/?\&=%+-]*) refuse ;; esac` (measured under dash: refuses a trailing newline, a quote, a space and `#`; passes a clean URL). A hostile-value row fails a positive-pattern implementation. In curl's config parser only `\` and `"` are special inside quotes (`%`, `&`, `?`, `=`, `+`, `:`, `~`, `#` measured literal on curl 8.22), and `@` is outside the class, so no userinfo redirect. The guard exists to close the one
  real hazard on this path, config-directive injection through `url = "%s"` (a quote, backslash or newline); it deliberately does NOT pin the host, so it cannot
  mis-refuse a healthy URL (it admits a superset of the proven `_url_ok` shape in `apps/web-platform/infra/git-data-liveness.sh`) (a host pin would also force a production test seam). A refusal makes **zero** requests, prints
  `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<NAME>` (value-free; both reasons are already in the closed set the other scripts use),
  and folds into the script's existing failure arm (`heartbeat_push_failed` in `luks-monitor.sh`; the existing WARN path in `web-git-data-probe.sh`; the
  heartbeat unit's nonzero exit). It is never an argv fallback (ADR-280 decision 4).
- **The inngest heartbeat runs every 60 s**: a persistent refusal would ship ~1,440 marker rows a day, so the marker goes through the heartbeat script's existing hourly `dark_arm_emit_due`-style rate limiter (the exit stays nonzero every tick; only the log line is limited), or the quota cost is accepted explicitly in the ADR addendum.
- **`luks-monitor.sh` validates once, before the 3-attempt loop** (not inside the retried curl): a refusal then prints one marker and goes straight to
  `emit_readiness_and_die heartbeat_push_failed` with zero curl calls and no `sleep 2` x2.
- **Transport.** The converted lines keep today's flags and add `--config -` (and `-g` where absent) and a leading `-q` (ignore `~/.curlrc` and `CURL_HOME`: measured, a `.curlrc` `proxy =` line is honored alongside `--config -`, and these scripts run as root). `--disable --noproxy '*'` (ADR-280 decision 6) is NOT added: it is the library's broader transport change, not needed to take the URL off argv, and unmeasured on these hosts. Recorded as a deviation from decision 6 in the ADR addendum; the guard also deviates from decision 7 (no trailing-whitespace trim: it refuses) and has no host pin (a Doppler writer could point the beat at any https host; accepted, recorded as a residual).
- A **read-only shape count precedes the edit** (Phase 0): list the live heartbeat URLs and confirm each stored value passes the shape guard, printing counts only. If any value
  fails, stop and decide then (no pre-designed fallback).
- Test seams: the suites match curl **argv** today. After the change the stub curl reads the stdin config and records the `url = "` line **per attempt, unconditionally**, and fails on a missing line; fixtures keep their stub host (the guard has no host pin). Every consumer is enumerated and repointed, because some existing NEGATIVE rows go vacuous once the URL leaves argv: `luks-monitor.test.sh` ~622 (`! has 'curl .*betterstack.test'`, standby profile) and ~352 (`nhas 'curl .*HEARTBEAT` alternation with `curl -gfsS`) can no longer fail and are repointed to the recorded line; positive rows ~573, ~604, ~638 red loudly and are repointed; `inngest.test.sh` ~611-648 PATH shim and the ~608 ban on `printf`/`echo`/`logger` lines naming the URL stay. **`web-git-data-probe.test.sh` never executes the transport line today**: `_ping` returns at the `SOLEUR_GIT_DATA_PROBE_PING_LOG` seam and both `run_seam` and `run_real` set it; the per-attempt rows need a new harness (seam unset, a PATH curl stub, `SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE=reachable`). The POSIX script gets a **dash** row: `sh -n` and one real run under dash (a local `/bin/sh` may be bash, so a green local run proves nothing; use a container image whose `sh` is dash or busybox, named by digest in the row, in the infra-validation legs that assert docker).

### B. htpasswd passwords off argv

All four sites move to `htpasswd -i` (password on stdin), keeping the exit-code contract. Measured on BOTH `httpd:2.4-alpine` and `ubuntu:24.04` + `apache2-utils`
(the shipped host image): `-Bin` hashes, `-vi` verifies with 0 (match), 3 (mismatch), 6 (user absent), 1 (file unreadable); a hash built with `-Bin` also verifies under the old `-vb`.

1. `cloud-init-registry.yml` `_htp_verify` (content anchor: the function containing `htpasswd -vb /etc/zot/htpasswd "$1" "$2"`, ~637):
   `printf '%s' "$2" | htpasswd -vi /etc/zot/htpasswd "$1" >/dev/null 2>&1`, then the unchanged `case "$?"` mapping (0 true, 3 false, else unknown). `$?` now
   reads the **pipeline** status, which is `htpasswd`'s (last command; the probe script has `set -u` only, no `pipefail`, so `printf` cannot mask it): a row pins
   that 127 (binary missing), 6 and 1 still map to `unknown` through the pipe. `registry-boot-guard.test.sh` pins the probe block (no bare `"$ZOT_*_TOKEN"` expansion,
   `$${ZOT_*_TOKEN:-}` at least twice, `unknown` default, only `3)` maps to false, no `printf .*ZOT_*_TOKEN`); `printf '%s' "$2"` names the function argument, so the pins hold,
   and the rewrite is re-run against them.
2. `cloud-init-registry.yml` boot step (anchor: `htpasswd -Bbn '${zot_pull_user}' "$ZOT_PULL_TOKEN"`, ~2558-2559; inside `doppler run ... -- bash -s <<'ZOTEOF'`, whose
   first line is `set -euo pipefail`): `printf '%s' "$ZOT_PULL_TOKEN" | htpasswd -Bin '${zot_pull_user}' > /etc/zot/htpasswd` then the push line with `>>`.
   Two separate pipelines: a failing first `htpasswd` aborts under `set -e` before the `>>` runs (a row shows nonzero exit, no second line, no half-written second entry).
   The pipeline gives `htpasswd` its own stdin, so it cannot consume the `bash -s` script text from stdin. **The row extracts the actual block text from the YAML
   and renders the templatefile variables (`${zot_pull_user}`, `$${...}` escapes) before executing it through `bash -s`**, so template drift fails offline instead of at boot.
   Usernames stay Terraform-interpolated (non-secret). Reword the comments that still name the argv form (`cloud-init-registry.yml` line 18 trailing comment and the
   ~610 prose, plus `apps/web-platform/infra/zot-image.provenance.md` ~139 "baked with `htpasswd -Bbn`"); the line-18 trailing comment is not stripped from
   `user_data`, so shortening it also buys bytes. Net `user_data` growth is measured with `registry-userdata-budget.sh` before and after; ~100 B of headroom
   is the constraint, a shortfall is paid by stripping non-rationale bytes in the same file, never by raising `REGISTRY_GZIP_BUDGET`.
   The same lines are the world-readable window the plan rewrites anyway: `> /etc/zot/htpasswd` runs under the default umask and `chmod 600` follows, so the bcrypt hashes are 0644 until then. Create the file first with `install -m 600 /dev/null /etc/zot/htpasswd` (replacing the post-hoc `chmod`), keeping the empty-token guards above the pipelines.
3. `.github/workflows/apply-web-platform-infra.yml` (anchor: `docker run --rm httpd:2.4-alpine htpasswd -Bbn "$RU" "$RP"`, ~2958, job `registry_pull_path_gate`,
   `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-luks-recut'`): `printf '%s' "$RP" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin "$RU" > "${RUNNER_TEMP}/zot/htpasswd"`.
   The password is a per-run `openssl rand -hex 24` throwaway, already masked; the exposure is the docker client argv. The step is dispatch-only and destructive-path,
   so it is **not exercised by the merge-triggered push run**; the proof is an offline row plus the measured behavior above, and the first live run is the next
   `registry-luks-recut` dispatch. The workflow file is 464,451 B against the 490,000 B gate; the edit adds under 50 B.
4. Recurrence row (Guard 3): new stage S6 in `tests/scripts/test-argv-bearer-sweep.sh` (derived from `git ls-files`/`git grep` with `:!*.test.sh`, the way the S3-S5 stages derive, so a scratch tree and CI see the same population). The **real-binary and container rows live in a new infra suite**, `apps/web-platform/infra/htpasswd-stdin.test.sh` (auto-registered by the infra glob, ADR-252), because the `scripts` shard that runs the battery asserts no docker and installs no `apache2-utils`, while the infra-validation legs assert docker fail-closed; `registry-boot-guard.test.sh` stays static and docker-free (weight 0). The new suite fails closed on a missing docker or binary in CI and names its image by digest.

`htpasswd` reads at most 255 bytes of password on stdin (`MAX_STRING_LEN`); the tokens are far shorter.

### C. `inspect-evidence.sh` xtrace refusal (#10089)

Add the preamble the lint prints (`case "$-" in *x*) ... exit 78`, naming `AWS_SECRET_ACCESS_KEY` and `R2_CLA_EVIDENCE_SECRET`) as the first thing
after `set -euo pipefail`; add a must-refuse row (`bash -x` with the pair set, rc 78, value-free) and a must-pass row (same argv without `-x`
and a stub `aws`, rc 0 on the happy path, differing from the canonical fixture) to `apps/cla-evidence/scripts/inspect.test.sh`; delete
line 5 from `scripts/lint-shell-trace-credential-refusal.baseline.txt`. Check `scripts/lint-shell-trace-credential-refusal.test.sh` for
rows that read "the first real row" of the baseline before deleting (the SigV4 plan hit exactly this when emptying baseline E).

### D. Archive chore

`archive-kb.sh` derives ONE slug per run and, since #9803, unions a branch-diff discovery that picks up **this branch's own committed
plan and spec** (A/M rows under the KB roots), which would archive the live plan of this very PR. So run it from a clean checkout of
`origin/main` in a throwaway worktree (branch diff empty), twice (spec slug `one-shot-9756-cla-evidence-sigv4-argv`, plan slug
`cla-evidence-r2-sigv4-pair-off-curl-argv`; dry-runs on this branch before the plan was committed listed exactly the right one artifact each), commit
`plan: archive cla-evidence SigV4 plan and spec` there and cherry-pick onto the branch. Do not hand-`git mv`: the script owns the timestamp prefix.

## Production-apply coupling

**Which files fire what on merge to `main`.** Path filters were read from the workflows; the one most easily missed is that **every file under `apps/web-platform/**` and every non-docs, non-test file under `plugins/soleur/**` fires `web-platform-release.yml`**, a production app release and container deploy (`path_filter: apps/web-platform/ plugins/soleur/ ...`, `vendor_plugin: true`), in addition to the infra workflows below. The merge therefore restarts the web app container on production regardless of which slice is in it.

| File in this PR | Workflow(s) it fires | What the firing does to a live system |
|---|---|---|
| any `apps/web-platform/**` file (all of A1's test edit, A2, B1) and any `plugins/soleur/**` file except `docs/` and `test/` (linkedin-setup.sh, ship and postmerge markdown) | `web-platform-release.yml` | A version release, image build and **production deploy of the web app container**. A `plugins/soleur/test/**` edit alone does not fire it. |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (A1) | `apply-web-platform-infra.yml` push apply | No Terraform diff: a no-op plan/apply cycle. |
| `apps/web-platform/infra/web-git-data-probe.sh` + `.test.sh` (A2) | push apply | `terraform_data.git_data_probe_install` is in the post-bridge `-target` list and `triggers_replace` hashes the script: **SSH re-delivery of the script to web-1**, then the (idempotent) timer enable. Live effect: the next 60 s tick runs the converted ping. The script is also in the baked `host_script_files` list whose content hash renders into web cloud-init (`hcloud_server.web` ignores `user_data`, so no replace), but `host-image-coherence-preflight.sh` refuses a host create or replace until the rebuilt image lands: a transient window that the release above closes. |
| `apps/web-platform/infra/luks-monitor.sh` + `.test.sh` (A2) | push apply | `terraform_data.luks_monitor_install` (also `-target`ed; hashes `luks-monitor.sh`): **SSH re-delivery to web-1**; the next daily run uses the converted push. Same `host_script_files` note. |
| `apps/web-platform/infra/inngest-bootstrap.sh` + `inngest.test.sh` (A2) | push apply (no Terraform diff) **and** `mint-inngest-bootstrap-tag.yml` (`apps/web-platform/infra/inngest*`) | The mint workflow mints the next `vinngest-v*` tag, dispatches `build-inngest-bootstrap-image.yml` (environment `infra-privileged`, main-only), publishes the image and runs its pin-bump job. **No host change** until a later image deploy or host replace. |
| `apps/web-platform/infra/cloud-init-registry.yml` + `registry-boot-guard.test.sh` (B1, B2) | push apply (no Terraform diff in its `-target` sets) **and `registry-host-replace-dispatch.yml`**, which has a PUSH trigger on this exact file (`on.push.paths`: `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`; no reviewer gate, no confirm token; its header says "the merge IS the intent to deliver") | The dispatcher renders `user_data` offline at both SHAs and, on a byte change, runs `registry-host-replace` after a read-only preflight that refuses when the fleet is already serving off its last tier. **Merging B1/B2 therefore replaces the production registry host (the sole pull path) automatically**, and the converted `htpasswd -Bin` boot block executes for the first time on the new host at boot. A boot failure under `set -euo pipefail` leaves zot not launched: the #6400 hazard (a degraded registry becoming a deploy outage). The volume is preserved (`store_destroyed==0`). Comment-only changes to whole-line comments are stripped at render and do not count as a byte change; code and the trailing line-18 comment do. |
| `apps/web-platform/infra/zot-image.provenance.md` (B, comment-level sentence) | push apply only (`infra/**`); not a dispatcher input | Docs. |
| `.github/workflows/apply-web-platform-infra.yml` (B) | push apply (the workflow file is its own trigger) | The merge-triggered run executes the new copy; the converted step lives in the dispatch-only `registry_pull_path_gate` job, so it is **not run** by the push. |
| `apply-deploy-pipeline-fix.yml`, `apply-inngest-rls.yml`, `apply-sentry-infra.yml`, `apply-github-infra.yml` | none of this PR's files | Their `paths:` lists do not match any file here (`apply-deploy-pipeline-fix.yml` uses an explicit list; re-check it at implementation). |
| `scripts/cutover-inngest.sh`, `scripts/betterstack-query.sh`, `tests/scripts/**`, `scripts/lint-*`, `scheduled-inngest-health.yml`, `git-data-cutover.yml` | none of the apply, mint or release workflows | Not apply paths (`cutover-inngest.yml` is dispatch-only). |
| `apps/cla-evidence/**` (C) | the CLA workflows (not an apply) | None here: this PR does not touch `apps/cla-evidence/infra` (#7675 stays out). |
| `knowledge-base/**` runbooks, ADR addendum, archive moves | none | Docs. |

**Net live effect of the merge:** one production web-app release and deploy (container restart; routine for any `apps/web-platform` or plugin change), two SSH re-deliveries of probe scripts to web-1, one inngest bootstrap tag and image publication (no host change), **one automatic registry host replace if B1/B2 are in the merge** (the one non-routine, higher-stakes firing), and otherwise no-op applies. The converted heartbeat ping is the only runtime behaviour change and its failure mode is a false page, not data loss. Nothing in this PR dispatches anything by hand (`hr-menu-option-ack-not-prod-write-auth`; #9905 stays an observation tracker, and the merge-triggered push run may itself count toward it). The merge squashes the branch into one commit, so **after the merge there is nothing left to revert** per commit: the staging below is a set of pre-merge peel points, and a post-merge revert is a new PR whose own merge re-fires everything it touches (for the registry file, another host replace). Deliveries are idempotent, so re-delivering the reverted bytes is the recovery.

**Recommendation.** One PR is workable and matches the operator's instruction for everything except the registry template; **recommend staging the registry template (B1, B2) as its own PR merged right after this one**, and keeping B3 (the dispatch-only workflow step) in this PR. Reasons: B1/B2 is the only slice whose merge triggers an unattended replace of the sole pull path, whose first live execution is the boot block itself, and whose preflight can refuse for reasons unrelated to this change (the operator then re-fires by hand); everything else is a no-op, a web-1 file re-delivery or a routine release. The S5 slice recorded the same shape (the registry changes in ONE commit that can be declined only before merge). If the operator keeps one PR, the conditions are:

1. **Commit order is the staging, and it only exists before merge.** Each firing change is a separable commit, peelable before the squash: (1) C + D + docs (no infra apply; the plugin markdown still fires the app release), (2) A1 + leads (a)(b)(g) + linkedin + battery rows (infra apply: no-op only, via the census edit), (3) B3 (workflow step, not run by the push), (4) A2 for `web-git-data-probe.sh` and `luks-monitor.sh`, (5) A2 for `inngest-bootstrap.sh`, (6) **B1 + B2, the registry template, last, with its suites, its battery rows and its ADR text in that one commit**, so declining the replace is one revert before the merge.
2. **Peel (5) if PR 10073 has not merged** (it edits the same file, `inngest.test.sh` and `cloud-init-inngest.yml`; each merge mints a tag), and **peel (6) unless the operator approves the registry replace notice by name**. Both are recorded as decision challenges (C1, C6).
3. **The first-live-execution risk of (6) is retired offline before merge:** the boot block is rendered from the real YAML and executed through `bash -s` inside an `ubuntu:24.04` + `apache2-utils` container (the shipped host image), including the failure arms; the replace preflight is read-only and runs at merge, not before.

The merge is **gated on explicit operator approval** of (i) merging at all and (ii) the apply, release and registry-replace notice above; neither is implied by earlier menu answers. Pre-merge there is no way to prove the SSH re-delivery path except the offline suites; post-merge verification is read-only (below). The PR body's **first line** states whether merging alone mutates production (yes: the list above).

## Implementation Phases

### Phase 0 — Baselines and measurements (read-only, no commits)

1. Run the changed-file lint at the start: `python3 scripts/lint-shell-trace-credential-refusal.py --changed` and record which touched files are baselined (only `inspect-evidence.sh` and `luks-monitor.sh` appear in baseline A; `luks-monitor.sh` already carries the `case "$-"` refusal near its top, so its row looks stale: confirm, and delete it in the commit that touches the file).
2. Green baseline of every suite this PR edits: `cutover-inngest-workflow.test.sh`, `tests/scripts/test-argv-bearer-sweep.sh`, `community-argv.test.sh`, `registry-boot-guard.test.sh`, `luks-monitor.test.sh`, `web-git-data-probe.test.sh`, `inngest.test.sh`, `inspect.test.sh`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `apps/web-platform/infra/registry-userdata-budget.test.sh`, `web-host-provisioner-parity.test.sh`, `ci-deploy.test.sh` (pins `inngest-bootstrap.sh` systemctl counts), `infra-config-gate.test.sh` (scans every infra `*.sh` for byte-length and newline-position invariants, so the new heredoc and process-substitution constructs must pass it), and the vitest `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (walks every `SOLEUR_*` sentinel a plugin skill script emits: `linkedin-setup.sh` emits the already-registered `SOLEUR_CREDENTIAL_REFUSED`, so it should stay green; run it to prove it). Record pre-existing reds, do not absorb them.
3. `registry-userdata-budget.sh` stored size now (~21,500 B vs the 21,600 ratchet; the Hetzner cap is 32,768 B, so this is a repo ratchet and not an outage threshold).
4. Read-only live shape count of the three heartbeat URL values against the shape guard (read-scoped Doppler token, counts only, never the value). If any value fails, stop and decide.
5. `gh pr view 10073 --json state,files` and `gh pr view 7390 ...` again (collision re-probe).

### Phase 1 — C: inspect-evidence xtrace refusal

RED first (`cq-write-failing-tests-before`, local only): the must-refuse row in `inspect.test.sh` fails on main; add the preamble; delete baseline row 5; run the lint suite and the repo-wide lint (the SigV4 slice hit "first real row" mutation rows when emptying a baseline; check them).

### Phase 2 — A1: HMAC arms, census, battery, leads (a)(b)(g)

RED first (local only, never pushed red): edit the census allowance and battery rows to the end state (they fail against the held-back script), then convert the two arms, then the leads.

### Phase 3 — linkedin `write-env`

Copy the `_wenv_class` / `_wenv_refuse` / `_wenv_validate` block verbatim from `x-setup.sh` (~195-225; the suite requires the blocks byte-identical across bsky, discord, x and now linkedin), call `_wenv_validate` on the variable names `cmd_write_env` writes, before the first `mktemp`/`touch`/write. Update `community-argv.test.sh`: `WRITERS` stays the same four; the validated list becomes four, the "one DEFERRED writer" row (~1931) is replaced by a validated-before-first-write row for linkedin, the floor `-eq 4` row stays. Check `plugins/soleur/test/fixture-relative-assert.baseline.txt:295` (`2 linkedin-setup.sh`) for a count move.

### Phase 4 — B: htpasswd (registry template, workflow)

RED first: executable rows (Guard 3) fail on main. B3 (workflow step) is commit 3; B1 + B2 (registry template, comments, suites, battery rows, ADR text) are the LAST commit (6). In the boot block also replace the post-hoc `chmod 600 /etc/zot/htpasswd` with `install -m 600 /dev/null /etc/zot/htpasswd` before the first write (the hashes are world-readable under the default umask until the chmod; byte-neutral, and the empty-token `[ -n ... ]` guards stay above the pipelines). Measure `user_data` size; add a refusing stub-docker row (accepts exactly `run --rm -i httpd:2.4-alpine htpasswd -Bin <user>`, exit 64 on anything else, refusal log asserted empty) for the workflow step: without `-i` docker does not forward stdin and the hash covers an empty password, and the step is dispatch-only so nothing else would notice.

### Phase 5 — A2: heartbeat URLs (commits 4 and 5)

RED first: the stdin-recording stub rows. Convert `web-git-data-probe.sh` and `luks-monitor.sh` (commit 4), then `inngest-bootstrap.sh` (commit 5, the dash row included).

### Phase 6 — Docs and leads

(d) replace the argv `openssl dgst -hmac` form with the canonical env-prefix line in `plugins/soleur/skills/ship/SKILL.md` (anchor `HMAC=$(printf '' | openssl dgst`), `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`, and the runbooks `inngest-server.md` (3 occurrences), `vector-redeliver.md`, `dsar-export-failed-job.md`; derive the population by `git grep -n 'dgst .*-hmac'` over `plugins/` and `knowledge-base/engineering/operations/` at implementation time; test fixtures and learnings that use the form as an oracle stay). (f) verify the fatal-channel probe; code only if a gap exists. (h) fold a `bash:3.2` run into the EXISTING opt-in `COMMUNITY_ARGV_DOCKER` row (`community-argv.test.sh` ~2206) rather than a new digest-pinned always-on row; record the measurement in the #9757 tick. ADR-280 addendum. Tick every #9757 item with evidence; deferral trackers already filed: #10091 (c), #10092 (e), #10093 (residual same-class sites). Run `npx markdownlint-cli2` on the plan and tasks.

### Phase 7 — D archive, then gates

Archive as described; then the full verification list (Acceptance Criteria), the Rollback simulation, and PR assembly. STOP before merge.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-280** with a short `## Addendum — 2026-10-12 (#9757 residue)`; no new ordinal (status stays `adopting`). It records: (1) the held-back HMAC arms close (zero `-hmac` operands in `cutover-inngest.sh`) and the census allowance lives in the single code view; (2) `htpasswd -i` is the stdin form for passwords (not curl, so not the library; Rule E does not see it; recurrence is the S6 derived row); (3) heartbeat URLs on checkout-less hosts use an inline shape guard plus `--config -` and `-q` (heredoc under dash, process substitution under bash): recorded deviations from decision 6 (no `--disable --noproxy`), decision 7 (no trailing-whitespace trim; it refuses) and the library's destination handling (no host pin, so a Doppler writer could redirect the beat; accepted); the inline-wrapper exception is justified by the checkout-less-host property, as the S5 registry copies were; (4) residuals: same-uid `/proc/<pid>/environ` readers, the three further heartbeat probe scripts and the skill markdown snippets (#10093), and that the B3 workflow step is first exercised at the next `registry-luks-recut`. This is a task in Phase 6, not a follow-up issue.

### C4 views

No C4 impact, checked against all three files (`model.c4`, `views.c4`, `spec.c4`, read for the elements below): external human actors (none added; the CLA contributor and operator actors are untouched), external systems (Better Stack heartbeats, Hetzner, Doppler, GHCR, the zot registry, the Inngest host, the deploy webhook behind Cloudflare Access are already modeled; no new vendor or inbound/outbound edge), containers and data stores (no new store; `workspacesVolume`, `inngest`, `gitDataStore` unchanged), and actor-to-surface access relationships (unchanged: this changes how a credential reaches a child process, not who reaches what). Derived cardinalities in edge prose are gated by `plugins/soleur/test/c4-count-parity.test.sh`: green on this branch now; re-run at the end.

### Sequencing

The addendum ships in the same PR as the code it describes; the status flip `adopting` -> `accepted` stays with #9905's follow-through.

## Guard Contract

### Guard 1 — Probe-arm tool census allows exactly the canonical HMAC line

**Property.** The read-only `registry-probe` and `doublefire-probe` arms make exactly two network or tool calls (the two bounded `curl -X GET`), and the only other tool token they may carry is the canonical HMAC line, whole-line and anchored.

**Assembly.** Two regex sites hold the count (`cutover-inngest-workflow.test.sh` ~1850 and `check_rpg_tool_count` ~3365, which feeds the M2.9 mutation rows) and every consumer, including the mutation helpers at ~3314 and ~3364, reads the arms through ONE chokepoint, `_probe_arms_code_of`. The allowance is a filter at the end of that function only; the arms are the range `registry-probe)` .. `rearm)`, so an arm added to that range later is covered. The 17 canonical copies elsewhere in the script are outside this range and stay governed by the S2-A parity row in `tests/scripts/test-argv-bearer-sweep.sh` (extended to 19 copies, zero `-hmac` operands). Independent anchor: that parity row and `bc_hmac_sha256_hex` in `scripts/lib/bearer-curl.sh` carry the canonical python body in two other files, so editing the allowance alone cannot make a divergent line pass the battery.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `; python3 -c 'import os'` (or `|| SIG="" ; curl ...`) to the canonical line's physical line | RED (the line no longer matches the anchored allowance, so the count moves) |
| 2 | Add a second, non-canonical `python3 -I -c ...` line to one arm after the compliant canonical line | RED |
| 3 | Add a second canonical line to the same arm | RED (the exactly-one-canonical-per-arm row before the filter; the S2-A parity count 19 -> 20 is the second line of defence) |
| 3b | Delete the allowance filter in a scratch copy of the suite (harness row) | RED (the canonical lines then read as extra tools) |
| 4 | Rename the arm anchor so the code view is empty | RED (the suite floors arms seen at 2) |
| 5 | Revert one arm to `openssl dgst -hmac` | RED (S2-A parity and zero-`-hmac` rows) |
| 6 | Must-PASS: the canonical line at a different indentation, with and without the trailing `|| SIG=""`, which the contract permits | GREEN |

### Guard 2 — Heartbeat URL reaches curl only on the stdin config, after the shape judgement

**Property.** In the three converted host scripts a heartbeat URL is never an argument of any process, is sent only after passing the shape guard, and a malformed value makes zero requests and prints the value-free marker exactly once.

**Assembly.** Every code path that hands a heartbeat URL to `curl` in `inngest-bootstrap.sh` (the `HEARTBEATSCRIPTEOF` body), `web-git-data-probe.sh` (`_ping`, both attempts) and `luks-monitor.sh` (the retry loop). The population is DERIVED, not listed: a battery row greps every `apps/web-platform/infra/*.sh` for a `curl` whose arguments reference a heartbeat URL variable (`INNGEST_HEARTBEAT_URL`, `URL`, `hb_url`; NOT `INNGEST_HEALTH_URL`, the health curl in the same file) and requires zero on argv outside an explicit residual allowlist (`web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh`, tracked as #10093; the allowlist shrinks by deletion only). Chokepoint: one guarded transport line per file; the `SOLEUR_GIT_DATA_PROBE_PING_LOG` seam routes before it and is unchanged. Not covered and named: the two `cloud-init-registry.yml` heartbeat curls and `workspaces-luks-verify.yml`'s SSH-side push.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Put the URL back on argv in one script (`curl ... "$url"`) | RED (derived-population row; recorded argv contains the URL) |
| 2 | Widen the guard to admit `"` or a newline in one script | RED (hostile-value rows: zero requests, one marker expected) |
| 3 | Add a second heartbeat `curl` outside the guarded line in the same file, after a compliant first | RED (derived-population row) |
| 4 | Stub curl that ignores stdin and records nothing | RED (a missing recorded `url = "` line fails the row; per-attempt count asserted for the two `_ping` attempts) |
| 5 | Move `luks-monitor.sh`'s guard inside the retry loop | RED (refusal must make 0 curl calls and exactly 1 marker) |
| 6 | Make the POSIX script use `[[ ]]` or process substitution | RED (the dash row) |
| 7 | Positive-pattern `case` guard instead of the negated class | RED (hostile-value row) |
| 8 | Must-PASS: a well-formed URL with a different token than the canonical fixture; for the POSIX script, the same row executed under dash | GREEN, one request per attempt |

### Guard 3 — No `htpasswd` invocation carries a password on argv

**Property.** No tracked non-test, non-comment `htpasswd` invocation passes a password as an argument (no `b` in any option cluster).

**Assembly.** Derived by `git ls-files` + a grep over `apps/`, `scripts/`, `.github/` (YAML `run:` bodies and cloud-init heredocs included) that excludes whole-line comments and trailing YAML `# ...` text; the suite reports the sites it saw and floors that at 4 (the four converted calls: two in the boot step, one probe, one workflow). One chokepoint row in the new S6 stage of `tests/scripts/test-argv-bearer-sweep.sh`. Not covered, named in the row's comment: an invocation through a variable or `eval`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `htpasswd -Bbn u "$p"` in one of the four sites | RED |
| 2 | Add a compliant fifth site, then a non-compliant sixth in a different file | RED (sites are asserted by identity, one anchored row per site, never only by count: four hits in one file would satisfy a count) |
| 3 | Rename the scanned binary in the scratch tree so the scan sees 0 sites | RED (floor >= 4) |
| 4 | Executable rows: a stub `htpasswd` records argv (token absent from argv, present on stdin; the stub also reds if it ignores stdin); a real-binary round trip in the new infra suite (`-Bin` hash verified by `-vi` = 0, wrong password = 3, absent user = 6, unreadable file = 1); a refusing stub `docker` for the workflow step (mutations: drop `-i`, put `-b` back) | RED when the call is argv-form, loses `-i`, or the exit-code map drifts |
| 5 | Must-PASS: option cluster in another order/case (`-iB`), and a `-vb` that appears only in a YAML comment | GREEN |

### Guard 4 — `inspect-evidence.sh` refuses to run traced with the pair set

**Property.** `bash -x inspect-evidence.sh <mode> <arg>` with `R2_CLA_EVIDENCE_SECRET` set exits 78 before any `aws` call and prints no value.

**Assembly.** The repo-wide lint (`scripts/lint-shell-trace-credential-refusal.py`, Rules A and B) over every shell script that binds a credential, plus the script's own suite; the one new member is `inspect-evidence.sh`, whose row leaves baseline A (set difference, not a count).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the preamble | RED (the must-refuse row and lint Rule A) |
| 2 | Make the preamble refuse unconditionally | RED (the must-pass row: the same argv without `-x`, with a stub `aws`, runs to rc 0) |
| 3 | Re-add the row to baseline A while the file is compliant | RED or a recorded stale-row finding (verify which in Phase 1; if the lint tolerates it, delete this row) |

## Downtime & Cutover

No operation in this PR takes a serving surface offline, and none schedules a replace. Named, with the zero-downtime path each already follows:

- **`hcloud_server.registry` `user_data` re-render (ForceNew).** The edit makes the render differ, which an untargeted plan shows as `-/+`; the replace was already pending (the S5 and zot-pin changes) and is **not** in the push apply's `-target` sets. The bytes reach a host only through the existing `registry-host-replace-dispatch.yml` gate (it renders `user_data` at both SHAs and delivers on a byte change), whose own preconditions (sole-copy LUKS volume protection set, ADR-282; stock probe; dispatch-only authorization) are unchanged. Zero downtime from this PR; the registry is not touched until a separately authorized replace.
- **web-1 re-delivery of `web-git-data-probe.sh` and `luks-monitor.sh`.** A file copy plus an already-enabled timer; neither unit is a serving surface, no restart of a serving process. A beat or two may be late during the copy; both heartbeat policies carry grace (git-data 180 s).
- **Web app release (`web-platform-release.yml`).** The routine deploy path every `apps/web-platform` change takes, with its existing drain; nothing in this PR changes it.
- **Inngest bootstrap tag mint (commit 5 only).** Publishes an image and a pin; no host change until a later image deploy or replace, each separately gated.

Residual downtime: none accepted, no maintenance window needed. Per-stage rollback: the Rollback section.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file, provider, variable or secret changes. `triggers_replace` hashes of `git_data_probe_install` and `luks_monitor_install` change
because the shipped script bytes change; that is the existing delivery mechanism, not a new resource.

### Apply path

(a)/(b) hybrid per existing resources: web-1 probe scripts via the existing push-apply `terraform_data` SSH provisioners (file + `remote-exec`), the registry
template via cloud-init only (reaches a host at its next replace), the inngest bootstrap via the image mint/build pipeline. Expected downtime: none; a re-delivery
rewrites a script file and re-enables an already-enabled timer.

### Host fan-out

No provisioner is added or edited, so the classification in `plan-host-fanout.md` is unchanged: `git_data_probe_install` and `luks_monitor_install` keep their
existing twin or `ONLY_JUSTIFIED` entries in `web-host-provisioner-parity.test.sh`. Confirm that suite is green; the converted scripts carry no prd credential
beyond the heartbeat URL the web-1 provisioner already writes.

### Distinctness / drift safeguards

No `dev != prd` surface touched. `registry-userdata-budget.sh` and `cloud-init-user-data-size.test.ts` are the drift gate for the registry template.

### Vendor-tier reality check

Better Stack heartbeat behavior is unchanged (same URL, same GET). No paid-tier gate.

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeats git_data_prd (web-git-data-probe), workspaces_luks (luks-monitor daily push), inngest_prd (inngest-heartbeat 60s unit); their continued arrival after the merge-triggered re-delivery is the proof the converted ping works. The beat is the primary alarm, the refusal marker only names a cause"
  cadence: "60s (git-data probe, inngest heartbeat) and daily (luks-monitor)"
  alert_target: "operator email via the existing Better Stack heartbeat policies (git-data.tf, workspaces-luks.tf, inngest.tf)"
  configured_in: "apps/web-platform/infra/git-data.tf:593, apps/web-platform/infra/workspaces-luks.tf, apps/web-platform/infra/inngest.tf"
error_reporting:
  destination: "layer 3, host journald to Vector Source 4 to Better Stack Logs (tags web-git-data-probe, luks-monitor, inngest-heartbeat are allowlisted in vector.toml; no PRIORITY filter; the PII scrub does not touch a value-free SOLEUR_CREDENTIAL_REFUSED line); layer 6 for the cutover script, the GitHub Actions run log"
  fail_loud: "SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> var=<NAME> from a converted heartbeat script (rate-limited hourly on the 60 s inngest unit), plus the existing heartbeat_push_failed and WARN lines; the missed beat itself pages through the heartbeat policy"
failure_modes:
  - mode: "stored heartbeat URL fails the shape guard (rotation, storage accident, Better Stack URL form change)"
    detection: "layer 3: SOLEUR_CREDENTIAL_REFUSED row in Better Stack Logs via scripts/betterstack-query.sh --grep SOLEUR_CREDENTIAL_REFUSED; independent of the beat because a refused script still logs"
    alert_route: "the heartbeat policy pages on the missed beat (the primary alarm, independent of the log path); the marker row only names the cause and rides the same journald, Vector, Better Stack path, so it can be absent exactly when that path is the fault"
  - mode: "htpasswd -vi mis-mapped so the registry probe reports unknown or false for a healthy credential, or the boot-step htpasswd fails on the replaced registry host"
    detection: "layer 3 is NOT Vector here: the registry host POSTs SOLEUR_ZOT_DISK directly from cloud-init-registry.yml (~1029); read htpasswd_pull_matches and htpasswd_push_matches with betterstack-query.sh --grep SOLEUR_ZOT_DISK. A boot-step failure leaves zot not launched, which the same line reports as state_status=unknown and the host heartbeat as missing"
    alert_route: "no alert keys on htpasswd_*_matches today (betterstack-logs-alerts.tf keys SOLEUR_ZOT_DISK on store_luks and store_escrow); detection is query-only for the mismatch, and the missing host heartbeat and the pull-path health gate cover the not-launched case"
  - mode: "registry user_data exceeds the gzip budget"
    detection: "layer 6: cloud-init-user-data-size.test.ts and registry-userdata-budget.sh, a required CI check on the PR run log"
    alert_route: "required CI check fails the PR"
  - mode: "census allowance lets a stray tool call into a read-only probe arm"
    detection: "layer 6: Guard 1 mutation rows in the infra suite (infra-validation run log)"
    alert_route: "infra-validation CI check fails the PR"
  - mode: "a cutover-inngest.sh refusal from leads (a), (b), (g): a malformed token or Cloudflare value now refuses before a request"
    detection: "layer 6: the ::error:: line and SOLEUR_CREDENTIAL_REFUSED marker in the dispatched run's log"
    alert_route: "the dispatching run fails visibly; no host effect"
  - mode: "the registry-luks-recut rehearsal step loses docker -i and hashes an empty password"
    detection: "layer 6: the refusing stub-docker row in CI before merge; at run time the rehearsal's own negative control in the same step"
    alert_route: "required CI check fails the PR"
logs:
  where: "Better Stack Logs (host scripts via Vector; registry host direct POST), GitHub Actions run logs (cutover-inngest.sh markers, suites)"
  retention: "Better Stack Logs team retention; Actions logs 90 days"
discoverability_test:
  command: python3 -c "print('OK' if sum(1 for f in ('apps/web-platform/infra/cloud-init-registry.yml', '.github/workflows/apply-web-platform-infra.yml') for l in open(f) if __import__('re').search(r'htpasswd +-[A-Za-z]*b[A-Za-z]* +[^ (]', l)) == 0 else 'FAIL')"
  expected_output: "OK"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** credential-transport hardening on existing surfaces; no new architecture, no Product, Marketing, Legal or Finance implication (no user-facing surface, no personal data, no new processor). The CTO advisory verified the coupling table against the workflow path filters and found four things now folded into this plan: (1) `web-platform-release.yml` fires on every `apps/web-platform/**` and non-docs `plugins/soleur/**` edit, a production app deploy the first draft listed only for plugin files; (2) the inngest heartbeat heredoc is `#!/bin/sh` so process substitution would have broken the live beat (heredoc form specified); (3) three more same-class heartbeat probe scripts and four skill markdown snippets exist outside the ask (tracked in #10093, derived-population residual allowlist in Guard 2); (4) exit codes re-measured on `ubuntu:24.04` (the shipped host image), and the workflow step needs docker's own `-i`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "held-back HMAC sites in scripts/cutover-inngest.sh (registry-probe, doublefire-probe; update the two census regexes in apps/web-platform/infra/cutover-inngest-workflow.test.sh)" | Proposed Solution A1, Phase 2, Guard 1 | mapped (the allowance sits in the single code view both regex sites read through, so neither regex text changes: the property the regex edit buys is bought once, at the chokepoint) |
| 2 | "heartbeat-URL path secrets (inngest-bootstrap.sh, web-git-data-probe.sh, luks-monitor.sh under apps/web-platform/infra/)" | A2, Phase 5, Guard 2 | mapped |
| 3 | "linkedin-setup.sh write-env validation (update the community suite population-manifest row in the same change)" | Phase 3 | mapped |
| 4 | "Better Stack stderr surfacing in scheduled-inngest-health.yml and git-data-cutover.yml" | Research Reconciliation row 1 (already done in #9811) | mapped (no code) |
| 5 | "plus review leads (a)-(h) in the issue body where tractable" | Phase 2 (a)(b)(g), Phase 6 (d)(f)(h); (c)(e) deferred to #10091 and #10092 | mapped; (c),(e) descoped, see Provenance |
| 6 | "Untracked htpasswd argv sites (NOT in #9757's body today; add them to the issue/PR)" | B, Phase 4, Guard 3; #9757 body edited | mapped |
| 7 | "apps/cla-evidence/scripts/inspect-evidence.sh ... File a tracker issue first and close it from the PR; remove the baseline row when converted." | C, Phase 1, Guard 4, #10089 | mapped |
| 8 | "archive the finished cla-evidence SigV4 plan and spec with bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh" | D, Phase 7 | mapped |
| 9 | "The plan MUST include a \"Production-apply coupling\" section stating exactly which files fire the apply, and recommend whether to ship A+B together with C+D or stage them" | Production-apply coupling | mapped |
| 10 | "Closes #9757 only if every checklist item in it is done, else Ref #9757" | PR assembly in Acceptance Criteria; default `Ref #9757` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Census allowance placed in `_probe_arms_code_of` (the shared code view) | "update the two census regexes" | asked (the code view is the chokepoint; editing two regex copies would let them drift) |
| ADR-280 addendum | "ADR-280 has the addendum" | inferred — justification: the held-back sites, the heartbeat inline guard and the htpasswd rule are decisions future engineers would find undocumented; plan Phase 2.10 makes the ADR a deliverable of the plan that makes the decision |
| Guard 3 derived-population row (htpasswd recurrence) | "Untracked htpasswd argv sites" | inferred — justification: a sweep without a ratchet regressed before (S1 learning); Property 4 |
| Guard 2 derived-population row and residual allowlist | "heartbeat-URL path secrets" | inferred — justification: the three named scripts are not the whole same-class population (three more probe scripts exist); a derived row with a shrinking allowlist is what keeps the class from regrowing silently |
| Lead (h): `bash:3.2` run folded into the existing opt-in docker row | "review leads (a)-(h) in the issue body where tractable" | asked (lead (h)) |
| Deferral trackers #10091, #10092, #10093 | "where tractable" | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracker for each deferral; a deferral without one is invisible |
| Dash row and docker `-i` stub row | "heartbeat-URL path secrets" and "htpasswd argv sites" | inferred — justification: the inngest heartbeat body is POSIX `sh` and the htpasswd workflow step is dispatch-only, so neither is exercised by any other test or by the merge-triggered run |
| Leads (c), (e) descoped | "where tractable" | descoped — justification: (c) rewrites byte-identical pinned blocks in three scripts for a local-tooling race; (e) costs a production app release for a comment; each gets its own tracker |
| Phase 0 heartbeat URL shape count | "heartbeat-URL path secrets" | inferred — justification: a guard that mis-refuses a live URL turns a healthy beat off; a read-only count is the only way to know before the edit |
| Commit-order staging | "recommend whether to ship A+B together with C+D or stage them" | asked |

### Split Assessment

- Subsystems touched: 7 — `apps/web-platform`, `apps/cla-evidence`, `plugins/soleur`, `scripts`, `tests`, `.github`, `knowledge-base`
- Planned files: ~38 (incl. 4 runbooks, 2 archive moves and 3 comment sweeps) | Estimated changed lines: ~900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — natural boundary is (C + D + docs + linkedin + `scripts/cutover-inngest.sh` leads: no infra apply, though the plugin files still fire the web app release) versus (A1 census, B, A2: apply-firing). **Operator override stands: single PR** (ask 9 quotes the instruction), mitigated by the commit order in "Production-apply coupling"; the one slice recommended to peel on collision is `inngest-bootstrap.sh`.

## Files to Edit

- `scripts/cutover-inngest.sh` (HMAC arms 1372/1546; leads (a) 556-559 and 3123, (b) six mask sites, (g) four body echoes; delete hold-back comments)
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (allowance filter in `_probe_arms_code_of`; the two regex sites and the M2.9 mutation rows keep their text; update rows that count tools)
- `tests/scripts/test-argv-bearer-sweep.sh` (S2-A part 2 and the S4 hold-back rows to the end state, `EXPECTED_TESTS` re-pin; new stage S6: heartbeat derived population with its residual allowlist, htpasswd recurrence, executable rows incl. the rendered-block `bash -s` row and the stub-docker `-i` row)
- `apps/web-platform/infra/inngest-bootstrap.sh`, `apps/web-platform/infra/inngest.test.sh` (heartbeat heredoc; commit 5; collision with PR 10073)
- `apps/web-platform/infra/web-git-data-probe.sh`, `apps/web-platform/infra/web-git-data-probe.test.sh`
- `apps/web-platform/infra/luks-monitor.sh`, `apps/web-platform/infra/luks-monitor.test.sh`
- `apps/web-platform/infra/cloud-init-registry.yml`, `apps/web-platform/infra/registry-boot-guard.test.sh`, `apps/web-platform/infra/zot-image.provenance.md` (one comment-level sentence naming the argv form)
- `.github/workflows/apply-web-platform-infra.yml` (one step; byte budget 490,000)
- `plugins/soleur/skills/community/scripts/linkedin-setup.sh`, `plugins/soleur/skills/community/test/community-argv.test.sh` (manifest row, and the opt-in docker row gains a `bash:3.2` run), `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if the count moves)
- `apps/cla-evidence/scripts/inspect-evidence.sh`, `apps/cla-evidence/scripts/inspect.test.sh`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` (delete line 5; `luks-monitor.sh` row if stale)
- `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`, `vector-redeliver.md`, `dsar-export-failed-job.md`
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (addendum)
- D: `knowledge-base/project/plans/2026-10-11-fix-cla-evidence-r2-sigv4-pair-off-curl-argv-plan.md` and `knowledge-base/project/specs/feat-one-shot-9756-cla-evidence-sigv4-argv/` (moved by `archive-kb.sh`, not edited)

## Files to Create

- `apps/web-platform/infra/htpasswd-stdin.test.sh` (real-binary and container rows; fail-closed docker; auto-registered by the infra glob).
- Plus this plan's own artifacts (`knowledge-base/project/specs/feat-one-shot-9757-argv-bearer-sweep-combined/tasks.md`, `decision-challenges.md`); the S6 stage lives in the existing battery on purpose, to keep the apply-firing footprint minimal.

## Open Code-Review Overlap

None (open `code-review` issues queried by body-contains on every planned path; no match).

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] `cutover-inngest.sh` has zero `openssl dgst -hmac` occurrences and 19 byte-identical canonical copies; the allowance lives only in `_probe_arms_code_of` and is an anchored whole-line match that admits the `|| SIG=""` tail (`scripts/cutover-inngest.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `tests/scripts/test-argv-bearer-sweep.sh` S2-A part 2 and the S4 hold-back rows, `EXPECTED_TESTS` re-pinned to the measured total).
- [ ] All Guard 1-4 mutation rows exist and each RED row reds against the mutant; must-PASS rows green.
- [ ] Heartbeat: for each of the three scripts, a recorded-stdin row shows the URL only in the recorded `url = "` line, never in recorded argv, once per attempt (both `_ping` attempts); hostile and empty values make zero requests and print the marker exactly once (`luks-monitor.sh`: validated before the retry loop, no `sleep`); the stub fails on a missing recorded line; the inngest heartbeat body passes `sh -n` and one real run under a dash-or-busybox `sh` named in the row; the derived population over `apps/web-platform/infra/*.sh` finds no heartbeat curl with the URL on argv outside the explicit residual allowlist (`web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh`, `web-private-nic-guard.sh`, #10093) (`tests/scripts/test-argv-bearer-sweep.sh` S6, `luks-monitor.test.sh`, `web-git-data-probe.test.sh`, `inngest.test.sh`; `INNGEST_HEALTH_URL` is not a heartbeat).
- [ ] htpasswd: stub-argv row (token absent from argv, present on stdin) for the probe function (127/6/1 map to `unknown` through the pipe) and for the boot block extracted from the YAML, rendered (templatefile variables and `$${...}` escapes) and executed through `bash -s` (a failing first `htpasswd` aborts before the `>>` line); real-binary round trip in the new `apps/web-platform/infra/htpasswd-stdin.test.sh` (fail-closed on a missing docker or binary in CI; image named by digest): `-Bin` hash verified by `-vi` returns 0/3/6/1 on `ubuntu:24.04` + `apache2-utils` and on `httpd:2.4-alpine`; a refusing stub-docker row for the workflow step (drop `-i` or put `-b` back reds); derived recurrence row floors at 4 sites asserted by identity (one anchored row per site).
- [ ] `registry-boot-guard.test.sh` green; `cloud-init-user-data-size.test.ts` green with `REGISTRY_GZIP_BUDGET` unchanged; `registry-userdata-budget.sh` stored size recorded before and after in the PR body.
- [ ] `inspect-evidence.sh`: `bash -x` with the pair set exits 78; without `-x` it runs; baseline row 5 deleted; `python3 scripts/lint-shell-trace-credential-refusal.py` repo-wide green; `scripts/lint-shell-trace-credential-refusal.test.sh` green.
- [ ] `linkedin-setup.sh` carries the byte-identical validator block called before the first write; community suite manifest lists four validated writers and no deferred row; `apps/web-platform/test/git-lock-marker-telemetry.test.ts` green.
- [ ] Leads: (a), (b), (g) rows green; (d) `git grep -n 'dgst .*-hmac'` over `plugins/` and `knowledge-base/engineering/operations/` returns only oracle/test mentions; (f) verified; (h) the opt-in docker row gains a `bash:3.2` run (opt-in via `COMMUNITY_ARGV_DOCKER`, set nowhere in CI, so it is evidence recorded in the #9757 tick and NOT a gate); (c), (e) and the residual same-class sites have trackers #10091, #10092, #10093 (recorded in the PR body).
- [ ] The registry template (B1, B2) is ONE commit with its suites, battery rows and ADR text; the boot block, rendered from the real YAML, runs through `bash -s` inside `ubuntu:24.04` + `apache2-utils` including the failure arms; `install -m 600 /dev/null /etc/zot/htpasswd` replaces the post-hoc `chmod`; `registry-userdata-budget.sh` before and after is recorded.
- [ ] ADR-280 addendum present (records the deviations from decisions 6 and 7: no `--disable --noproxy`, `-q` only; no trailing-whitespace trim; no host pin); C4 parity green (`plugins/soleur/test/c4-count-parity.test.sh`).
- [ ] D done by script from a clean-`origin/main` worktree and cherry-picked; `git diff --name-status origin/main...HEAD -- knowledge-base/project/plans knowledge-base/project/specs` shows the two archive renames plus this PR's own plan and spec as additions only (the merge-base form, never the moving tip).
- [ ] PR body ends with Closes lines only for completed issues: `Closes #10089`; `Ref #9757` (promote to `Closes #9757` only if (c) and (e) were also done in this PR, which this plan does not intend), `Ref #9597`, `Ref #7797`, `Ref #9905`.
- [ ] PR body: its first line states that merging alone mutates production (one web app release and deploy, two web-1 probe re-deliveries, one bootstrap tag mint if commit 5 is in); it carries the Production-apply coupling table, the commit-order staging and an explicit "merge awaiting operator approval" line. `npx markdownlint-cli2` is clean on the plan and tasks.
- [ ] Review and QA complete; **no merge**.

### Post-merge (operator-approved merge only; read-only checks)

- [ ] The merge-triggered `web-platform-release.yml` run deploys and `apply-web-platform-infra.yml` push run concludes success; the `git_data_probe_install` and `luks_monitor_install` steps report applied or unchanged, not failed.
- [ ] `git_data_prd` heartbeat is up again within two minutes of the re-delivery (`arm-heartbeats.sh --status`, read-only); no `SOLEUR_CREDENTIAL_REFUSED` row for the converted scripts in Better Stack Logs.
- [ ] The mint workflow run (if `inngest-bootstrap.sh` shipped) concludes success; no host change claimed.
- [ ] If B1/B2 shipped: the `registry-host-replace-dispatch.yml` run's verdict is read (delivered, or a named preflight refusal, in which case the operator re-fires by hand); on the new host `SOLEUR_ZOT_DISK` reports `htpasswd_pull_matches=true htpasswd_push_matches=true` and a non-unknown `zot_image_digest` (read with `betterstack-query.sh --grep SOLEUR_ZOT_DISK`, no SSH).
- [ ] The #9757 checklist is updated item by item with evidence; #9905 gets a one-line note if the push run exercised a tracked workflow.

## Test Scenarios

- Given the canonical HMAC line in both probe arms, when the census runs, then it reports two tool calls and passes (unit).
- Given a second `python3` in one arm, or `; python3 ...` appended to the canonical line, when the census runs, then RED (unit, mutation).
- Given a heartbeat URL `https://uptime.betterstack.com/api/v1/heartbeat/<token>` held in the env, when `_ping` runs with a recording curl, then recorded argv lacks the token and the recorded stdin config carries `url = "..."` (integration).
- Given a URL with an embedded quote or newline, when the ping runs, then zero requests and one `SOLEUR_CREDENTIAL_REFUSED` line; for `luks-monitor.sh`, no retry sleep (integration).
- Given the inngest heartbeat body under a dash `sh`, when it runs with a well-formed URL, then one `--config -` curl with the URL only in the heredoc (integration).
- Given `printf pw | htpasswd -Bin user > f`, when `printf pw | htpasswd -vi f user` runs, then rc 0; wrong password rc 3; absent user rc 6 (integration, real binary).
- Given the zot boot block fed to `bash -s`, when the pipeline form runs under `set -euo pipefail`, then the script text is not consumed by `htpasswd` and a failing `htpasswd` aborts (integration).
- Given `bash -x inspect-evidence.sh by-pr 1` with the pair set, then rc 78 and no value in output; the same argv without `-x` and a stub `aws` runs (unit).
- Given `linkedin-setup.sh write-env` with a value outside the allow-list, then refusal marker, exit 1, and no file touched (unit).
- Verification commands for `soleur:qa` (offline, deterministic): `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `bash apps/web-platform/infra/registry-boot-guard.test.sh`, `bash apps/web-platform/infra/registry-userdata-budget.sh`, `python3 scripts/lint-shell-trace-credential-refusal.py`.

## Dependencies & Risks

- **R1: `user_data` byte budget (low).** ~100 B of repo-ratchet headroom (21,500 stored vs 21,600; the Hetzner cap is 32,768 B, so this is a ratchet, not an outage threshold) and a raw delta under 20 B expected. Measure first; pay shortfalls inside the file; never raise the constant.
- **R2: false refusal on a liveness path.** The guard is a charset-and-scheme allowlist (no host pin), a superset of the proven `_url_ok` shape in `apps/web-platform/infra/git-data-liveness.sh`, and Phase 0 counts the live values against it first. A refusal is a false page (the missed beat), not silent, and the marker only names the cause (it rides the same log path).
- **R3: merge-fires-apply.** See the coupling section. Mitigation: commit order, one-commit reverts, merge only on explicit operator approval, no dispatches.
- **R4: collision with PR 10073** (`inngest-bootstrap.sh`, `inngest.test.sh`, `cloud-init-inngest.yml`). Scopes do not overlap (envfile condition gating vs heartbeat transport), hunks may. Re-probe at Phase 0 and before commit 5; rebase onto whichever lands first; commit 5 is the peelable slice.
- **R5: collision with PR 7390** (stale draft, `apply-web-platform-infra.yml` plus `reusable-release.yml`, Dockerfile, AGENTS files). Different hunks (it edits provenance/build-arg paths; this edits one htpasswd line ~2958); the 490,000 B workflow budget is shared, so both must re-measure at rebase.
- **R6: stub fidelity.** Suites that matched curl argv must now read stdin; a stub that records nothing must fail loudly (Guard 2 row 5).
- **R7: `bash -s` stdin.** Any `htpasswd -i` without its own pipe in the boot block would eat the script text; the executed-through-`bash -s` row is the gate.
- **R8: census allowance is a guard weakening.** Anchored whole-line regex in the single code view; the 19-copy parity row and `bc_hmac_sha256_hex` are the independent anchors (Guard 1).
- **R9: archive script traps its own branch's artifacts** (branch-diff discovery). Run from a clean `origin/main` worktree.
- **R10: pre-existing and not ours:** cla-evidence `plan` job (#7675); the other URL-path secrets and library gaps in #9757 comments.
- **R13: the registry template merge replaces the registry host unattended** (`registry-host-replace-dispatch.yml` push trigger). Mitigation: last peelable commit, offline rendered-block execution on the shipped host image, recommended as its own PR, operator approval of the replace notice by name. Residual: the dispatcher's preflight is read-only and runs at merge.
- **R14: local battery runtime.** `tests/scripts/test-argv-bearer-sweep.sh` is green offline in about 3m50s locally (47 s on the CI leg, `suite-durations.tsv`); run the whole battery once per commit and the new stages by name while iterating.
- **R11: the merge deploys the web app.** Any `apps/web-platform/**` or non-docs plugin change fires `web-platform-release.yml`; the operator notice names it. Routine, but a restart of the production container.
- **R12: guard line numbers drift.** Every cited line number is as of 2026-10-12 and is paired with a content anchor; five commits will land before the last slice, so implementers re-anchor by content (`cq-cite-content-anchor-not-line-number`).

## Rollback

Per-commit `git revert` (the commit order in Production-apply coupling is the rollback granularity). A revert undoes the code but not a delivery that already fired (SSH re-delivery to web-1, a minted tag): deliveries are idempotent, so the revert's own merge re-delivers the previous bytes. The recipe is simulated, not assumed: in Phase 7, in a scratch detached worktree, `git revert --no-commit` each apply-firing commit and run the gates the revert PR must pass (the census, the S2-A and S6 battery rows, `registry-boot-guard.test.sh`, `scripts/lint-shell-trace-credential-refusal.py`, the c4 parity test), and write what that run needed into the PR body. Reverting commit 2 alone must also revert its S2-A battery rows, which is why they ship in the same commit.

## Success Metrics

- `git grep` population rows: `openssl dgst -hmac` in `scripts/` = 0; password-on-argv `htpasswd` = 0; heartbeat `curl` with URL argv in the three scripts = 0.
- Baseline A: 29 -> 28 rows (inspect-evidence), -> 27 if the `luks-monitor.sh` row is stale and removed (a delta against the merge base, measured in one environment).
- #9757: every remaining unchecked item has a named tracker or is ticked with evidence.

## Sharp Edges

- `scripts/cutover-inngest.sh` is not an apply path but its suite is: the A1 pair (script and census) must land in the same commit or CI is red on the census.
- Do not use an `htpasswd` invocation without its own pipe inside a `bash -s <<'EOF'` block.
- `-g` must be on every converted heartbeat curl (`web-git-data-probe.sh` has none today and gains it; `--config -` does not subsume it).
- The inngest heartbeat body is POSIX `sh`: no process substitution, no `[[ ]]`, and no line starting with `printf`/`echo`/`logger` that names the URL variable (`inngest.test.sh` bans it). A local `/bin/sh` that is bash proves nothing; the dash row names its image.
- The shape guard runs on the whole value, with no trim (trailing whitespace is refused), before the URL is interpolated into `url = "..."`: a quote, backslash or newline would otherwise inject a config directive.
- Each `_ping` attempt needs its own fresh `< <(printf ...)`: a process substitution is consumed once, so the `||` second attempt would read EOF.
- `$?` after `printf ... | htpasswd -vi ...` is the pipeline status (htpasswd's); do not add `pipefail` to the probe function.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one states `aggregate pattern`.
- `archive-kb.sh` from a feature branch archives that branch's own plan and spec; see R9.
- Never print a token, URL or hash value in a test failure message; rows print counts and field names.

## References

- Tracker: #9757 (open); parent #9597 (closed); #7797; new tracker #10089; deferral trackers #10091, #10092, #10093; follow-through #9905; known-not-ours #7675.
- Predecessors: S2/S3/S4/S5 slices (PRs #9811, #9893, #9986), the SigV4 slice (ADR-280 addendum 2026-10-11).
- Collision drafts: PR 10073, PR 7390.
- ADR-280, ADR-072/217, ADR-166, ADR-282 (sole-copy LUKS volume set).
