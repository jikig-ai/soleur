---
title: "fix(6969): cloud-init doppler_download error channel — make the boot-stage fatal name its own cause"
date: 2026-07-26
issue: 6969
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-6969-cloud-init-doppler-error-channel
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix(6969): ship the cloud-init boot-stage error channel before any black-box retry

## Enhancement Summary

**Deepened on:** 2026-07-26
**Reviews folded in:** CTO domain review + 4-agent plan-review panel (architecture-strategist,
spec-flow-analyzer, code-simplicity-reviewer, kieran) + deepen-plan verification passes.

### Deepen-plan gate results

| Gate | Result |
|---|---|
| 4.4 Precedent diff | **PASS** — 4 pattern-bound shapes, all with in-repo precedent, none novel |
| 4.5 Network-outage deep-dive | **FIRED** (`timeout` trigger) — layer sweep recorded; telemetry emitted |
| 4.55 Downtime & Cutover | **Does not fire** — `ignore_changes` makes every touched attribute inert on running hosts |
| 4.6 User-Brand Impact | **PASS** — threshold `single-user incident`, concrete artifact + vector |
| 4.7 Observability | **PASS** — all 5 fields present, none empty/placeholder, `discoverability_test.command` is SSH-free |
| 4.8 PAT-shaped variable | **PASS** — no matches |
| 4.9 UI wireframe | **Skip** — no UI surface (the only glob match is this plan's own prose *stating* the globs do not match) |
| 4.10 Encryption Posture | **PASS** — 4 `does_not_defend` entries, zero boilerplate phrases, exception carries `tracking_issue` + `expires_on` |

### Key improvements over the first draft

1. **R15 / R26 — two plan-defeating defects caught and fixed.** The first draft would have shipped a
   `fatal` with an **empty `detail`** (the exact #6969 symptom), and its headline `rc`-capture line
   would have **converted a fail-closed boot into a fail-open one** — worst case a host reporting
   `cloud_init_complete` with no prd secrets. Both were found by review, both re-verified by measurement.
2. **R19 — the failing call is the only unbounded Doppler invocation in the file** (11 bounded siblings).
   A hang emits nothing, so the channel would have been blind to its own leading hypothesis.
3. **R18 — per-stage detail files** replaced a wire-format protocol, dissolving a delimiter collision,
   a legacy migration, and the stale-read hazard in one move, with less code.
4. **R20 — `doppler_download_attempt` string-prefixes `doppler_download`**, which would have made the
   op-contract anti-rename test vacuous. Renamed to `doppler_retry`.
5. **Scope discipline** — the 8-row sweep table (whose last row delivered nothing) narrowed to
   `docker_run`; 23 ACs reduced to a lettered, behavioural set; the nondeterministic "stop at
   `BUDGET − 100`" rule deleted.

### New considerations discovered

- The paging alert's group is **perpetually hot**, so the **first** matching event pages — even a single
  stray `warning` on a filtered stage name would page the founder on a healthy boot (R29).
- `grep -c` exits 1 on zero matches, which **aborts** the `set -euo pipefail` observability suite (R27).
- Behavioural ACs need the existing `awk` heredoc-extraction harness or they silently degrade to greps,
  leaving the R9/R26 defences unverified (R32).
- **This plan's own premises needed probing too.** The deepen passes falsified four of its claims:
  `extra` is *not* unverified (four in-repo emitters ship it); an over-long tag *truncates* rather than
  losing the event; invalid UTF-8 is *sanitized*, not rejected; and the "Sentry drops untrimmed tag
  values" claim is undocumented. Each design decision survived on better grounds — but the plan had been
  resting on claims a single grep or doc-read falsifies, which is the exact failure mode it exists to end.
- The `/store/` endpoint is **deprecated** in favour of `/envelope/`. Out of scope here; folded into the
  tracking issue Phase 3 already requires.

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No spec directory
> exists under `knowledge-base/project/specs/` for this branch, so there is no `lane:` to carry forward.
>
> **Revision note.** This plan was revised after a CTO domain review and a four-agent plan-review panel
> (architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, kieran). The panel found
> **two plan-defeating composition defects** in the first draft, both now fixed and both recorded in
> Research Reconciliation (R15, R18). Every reviewer claim reproduced below was **independently
> re-verified against the codebase** before being folded in.

## Overview

`soleur-web-2` (cpx22, Hetzner id `155488316`) booted DARK on the first real use of the
`web-host-create` birth path. cloud-init reached boot stage `doppler_download` and emitted a Sentry
`fatal` whose entire payload was `stage=doppler_download` + `host_id`. The Doppler CLI's stderr and
exit code — the deciding datum — were discarded at the source behind a generic
`echo "FATAL: Doppler secrets download failed during initial provisioning" >&2; exit 1`.

**This plan does not diagnose the failure. It makes the next occurrence diagnose itself.**

Two findings reshaped the design away from "add a `2>` at one call site":

1. **The gap is the shared emitter, not the call site.** The baked `soleur-boot-emit` — used by every
   boot stage from the bootstrap handoff onward — has **no detail channel at all**, while a
   *different*, inline emitter (`_emit`, early-runcmd only) already has a proven one. Closing the gap
   in the emitter fixes every downstream stage and costs **zero `user_data` bytes**.
2. **The failing call is the only unbounded Doppler invocation in the file.** Measured:
   `grep -c 'timeout [0-9]* doppler' cloud-init.yml` → **11**; the `doppler secrets download` at
   `stage=doppler_download` → **0**. Every sibling is wrapped in `timeout 15` or `timeout 45`. An
   unbounded call that hangs emits **nothing at all**, so the error channel would be structurally
   blind to a hang — and a hang is the most common shape of H1, the leading hypothesis. Bounding it
   is therefore part of the *error channel*, not a separate robustness nicety.

### Why this shape

| Decision | Rationale |
|---|---|
| Bulk logic lands in `soleur-host-bootstrap.sh` (baked), not `cloud-init.yml` (inline) | Baked = **0 `user_data`**. Measured headroom is ~**516 gzipped B**, and *novel* inline shell costs ~**0.46 gzipped B per raw byte** → a working budget of only ~1,100 raw bytes |
| Extend the shared `soleur-boot-emit` | One change gives every later stage the **reader** side of a detail channel. **Not "for free"** — a stage only gets content once a *producer* writes `.d/<stage>`; `doppler_download` and `docker_run` get producers here, the rest are a tracking issue (R23) |
| **Per-stage detail files** (`/run/soleur-stage-detail.d/<stage>`), not a wire format in the legacy file | Eliminates format ambiguity, delimiter escaping, legacy migration **and** the stale-read hazard in one move — and is *less* code than a self-identifying protocol (R18) |
| `timeout 45` per attempt, `rc=124` named | The failing call is the **only** unbounded Doppler call in the file; a hang emits nothing (R19) |
| Capture `rc` via `cmd && rc=0 \|\| rc=$?` **followed immediately by `[ "$rc" = 0 ] \|\| exit "$rc"`** | The `if !` form yields `$? = 0` (R9) — but the AND-OR list is `set -e`-exempt, so **without the re-raise the boot silently continues** and can report "booted clean" on a host with no prd secrets (R26). Both halves are mandatory |
| `tail -c 180` after dropping the `^Using ` preamble | `head -c 200` truncates the cause away; 180 leaves margin under the tag-value limit on a fail-open emitter (R1) |
| Attempt breadcrumbs use `doppler_retry` — **not** `doppler_download_attempt` | The latter is a strict string **prefix superset** of `doppler_download`, which makes the op-contract test's anti-rename guarantee **vacuous** (R20) |
| Sentry **tags** for the searchable fields, message literal **frozen** | Tags are *indexed* — the birth-path gate's `jq` reads `.tags[]` and cannot see `extra`. Changing `message` mints a **new** issue group, where `value = 1` means ">1" — a single fatal would then **not page at all** (R12). (`extra` is *also* available and precedent-backed — see corrected R2 — so it may carry deeper stderr behind the searchable tag.) |

## Research Reconciliation — Spec vs. Codebase

| # | Claim | Codebase reality (verified) | Plan response |
|---|---|---|---|
| R1 | "Capture … the **first N bytes** of that stderr" | **Measured against pinned Doppler CLI v3.75.3**: auth-failure stderr is 246 B, of which the **first 173 B are two `Using DOPPLER_* from the environment…` preamble lines** (both env vars are set by `/etc/default/webhook-deploy`, so both fire on the real host). `head -c 200` ships pure noise and **truncates away** `Doppler Error: Invalid Auth token`. | Use `tail -c`, and **drop the preamble first** — the preamble is what actually broke `head`, so removing it makes the head/tail choice mostly stop mattering. **Stated assumption:** this shape is measured for *auth failure* only; H1/H3 shapes are unmeasured and could put context at the front. Preamble-drop-then-`tail` is the hedge, not a proof. Cap **180**, not 200. |
| ~~R2~~ **R2 (CORRECTED)** | "emit … as Sentry `extra`" | **The first draft's premise was FALSE and is retracted.** It claimed *"no emitter in `apps/web-platform/infra/` sends `extra`; support is unverified"*. A deepen-plan verification pass found **`extra` already shipping to the same `/api/{proj}/store/` endpoint from at least four sites**: `ci-deploy.sh` (`extra: {reason: $r, sdk_version: $s}`, `extra: {ref: $ref, detail: $d}`, and two more), `container-restart-monitor.sh` (`extra: $extra`), `cron-egress-resolve.sh` (`extra: $extra`). `extra` is **proven in production on this exact endpoint** — it was never an unverified gamble. | **The decision does not change, but its justification does.** `detail` stays a **tag** because tags are *indexed and searchable* — the birth-path gate's `jq` reads `.tags[]`, and `extra` is not exposed there — and because tags do not affect grouping (R12). **Upgrade now unlocked:** since `extra` is precedent-backed, the fuller (uncapped-at-180) stderr MAY additionally ride in `extra` as depth behind the searchable tag. Additive and low-risk, not a gamble. |
| R3 | "the failure path is … `exit 1`" | Confirmed. Anchor: `stage=doppler_download` followed by `if ! doppler secrets download --no-file --format docker --project soleur --config prd > "$TMPENV"; then`; the trap is `[ "$rc" = 0 ] \|\| soleur-boot-emit "$stage" fatal`. | Phase 2 replaces this block. |
| R4 | "breadcrumb payload is only `stage=…` — empty entries" | Confirmed **and explained**: the baked emitter's body is `printf '{"message":"soleur-cloud-init boot stage","level":"%s","tags":{"stage":"%s","host_id":"%s","region":"cloud-init"}}'` — no detail field exists. The inline `_emit` **does** carry `detail`; the baked emitter **never reads that file**. | The gap is the emitter. Phase 1. |
| R5 | "Tag with `server_name`/`host_name`" | `SOLEUR_HOST_NAME` is **already** passed into the bootstrap and already consumed for `vector.toml`'s `@@HOST_NAME@@`. TF source: `host_name = each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"`. | Bake a second sentinel via the existing `sed` idiom — **0 `user_data`**. Scoped to the **baked** emitter only (see R22). |
| R6 | "sweep any sibling stage that discards stderr behind a generic FATAL echo" | Only **3** literal `echo "FATAL…"` sites exist. The real sibling set is stages that discard stderr behind the **trap with no echo at all** (`docker_run`, `plugin_seed`, `inngest_bootstrap`). | Narrowed to **`docker_run`** — the one alert-filtered sibling — plus a tracking issue for the rest (R23). |
| R7 | Implied: editing `cloud-init.yml` is safe | **Verified**: `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`. The edit is a **no-op on every existing host** — it cannot repair the dark web-2 and **cannot harm web-1**. | Primary safety fact. |
| R8 | Not in issue | `local.host_scripts_content_hash` is re-verified at boot (`[ "$GOT" = "$HOST_SCRIPTS_HASH" ] \|\| exit 1`). Editing the bootstrap changes it — **but** the birth path already runs `terraform console local.host_scripts_content_hash` + `host-image-coherence-preflight.sh` **pre-apply**. | Fail-closed by an existing gate: a stale image makes the *dispatch refuse*, not a second dark host. RK1 is Medium. |
| **R9** | **Design defect (CTO, re-verified)** | **Measured in bash *and* dash** (cloud-init `- \|` blocks run `/bin/sh` = dash): `if ! (exit 7); then echo $?; fi` → **`0`**. `(exit 7) && rc=0 \|\| rc=$?` → **`7`**. The current code uses exactly the `if !` form. | Blocking. Extending the existing branch to record `$?` would ship `exit_code=0` on **every** failure. AC-E pins it — by a **behavioural stub test**, since a grep is evadable (R24). |
| **R10** | **Design defect (CTO, re-verified)** | `sentry_issue_alert.web_terminal_boot_fatal` is `filter_match = "any"` over four bare `tagged_event { key = "stage" }` filters — including `doppler_download` — with **no `level` filter**, and `event_frequency { value = 1, interval = "1h" }`. | A `warning` reusing a filtered stage name would **page the founder on a healthy boot**. Attempts use a distinct, **non-prefixing** stage (R20). |
| **R12** | Issue implies `message` may change | `issue-alerts.tf`'s sibling comment records that `value = 1` works **only because** "its shared `soleur-boot-emit` group is never new… On a fresh per-deploy group, value = 1 means '>1' and a single event does NOT page." | Freezing the message literal is a **paging-correctness** requirement, not just gate lockstep. |
| **R13** | Not in issue | The alert's inline comment asserts *"Events carry only stage/host_id/region — no cross-tenant content."* | Becomes **false** on merge; corrected in the same change. **Risk framing corrected:** an HCL comment inside a `resource` block produces **no plan diff** — it is the safest possible edit, not a live change as the first draft claimed. |
| **R15** | **Plan-defeating defect — found by two reviewers independently** | Under *any* scheme that scopes or clears the detail buffer per emit, the last failed attempt consumes the buffer, then the terminal EXIT trap emits the **`fatal`** and reads an **empty** buffer. **The headline fatal ships with no detail and every AC still passes** — byte-for-byte the #6969 symptom the PR exists to fix. | **Dissolved by construction** via per-stage files (R18): the helper writes `.d/doppler_download` (the fatal's summary) *and* `.d/doppler_retry` (per attempt). The trap emits `doppler_download` → reads `.d/doppler_download`. **AC-B additionally asserts the fatal's `detail` is non-empty and contains the CLI error line** — the proxy-vs-invariant fix. |
| **R18** | **Architecture, adopted** | The legacy `/run/soleur-stage-detail` has five bare-string producers, one of which **appends a literal `\| `**, and a raw inline consumer with no token gate, `head -c`, and no secret scrub. Layering a `<stage>\|<detail>` protocol on it creates one file, two formats, two parse rules, an unescaped delimiter that already occurs in the content, and a migration nobody owns. | **Give the new channel its own path: `/run/soleur-stage-detail.d/<stage>`.** The emitter reads `.d/$STAGE` if present, else falls back to the legacy file unchanged. Eliminates format ambiguity, delimiter escaping, migration, and the stale-read hazard — and is *less* code. Legacy producers/consumer are **untouched**. |
| **R19** | **Architecture, verified — and a striking asymmetry** | `grep -c 'timeout [0-9]* doppler' cloud-init.yml` → **11**. The failing `doppler secrets download` → **unbounded**. It is the **only** unbounded Doppler call in the file. An unbounded hang emits **nothing**, so the channel would be blind to H1's most common shape. | `timeout 45` per attempt (mirrors the file's own idiom); **`rc=124` recorded as a distinct named condition**. **Observation, not a verdict:** the issue's own trail shows `webhook_bound 16:51:52 → doppler_download fatal 16:51:58` — a **6-second** failure, which is consistent with a fast error rather than a hang. This does **not** refute H1 (a fast NXDOMAIN is also 6 seconds) and no hypothesis is reclassified. |
| **R20** | **Architecture, verified** | `"stage=doppler_download_attempt".includes("stage=doppler_download")` → **true**. The op-contract test asserts `expect(cloudInit).toContain("stage=doppler_download")`, so a prefix-superset name makes that anti-rename guarantee **satisfiable without the real assignment**, and breaks bare-token greps (`cq-assert-anchor-not-bare-token`). | Attempt stage is **`doppler_retry`** — non-prefixing, zero cost. |
| **R21** | **spec-flow** | The plan gated `extra`/`server_name` behind a live ingestion probe (a rejected event on a fail-open emitter is *worse* than today) but then added **four new tags with no equivalent gate**. A rejected 7-tag payload cascades: no event → no page → the gate reports `timeout` with `LAST_STAGE: none observed`. | **Symmetry restored:** the ingestion probe (G2) covers the payload the plan **actually ships**. AC-A's local `jq -e .` is a proxy; the invariant is *the store API ingests it and the tag renders*. |
| **R22** | **simplicity** | `host_name` on the `bootcmd` beacon and the inline `_emit` sweeps in two emitters that are **not on the failing path**, coupling a separable attribution improvement into a P0 error-channel PR. | Scoped to the **baked emitter only** (one `sed` sentinel). The other two are a tracking issue. |
| **R23** | **simplicity + spec-flow** | The 8-row sweep table's last row ("Detail-only via Phase 1; no per-site edit") **delivers nothing** — Phase 1 supplies a *reader*; the channel stays empty with no *producer*. And the stop rule ("stop at `BUDGET − 100`") made the PR's contents a function of measurement order, so no reviewer could know what shipped. | Narrowed to **`docker_run`** only, pinned by AC-G. Table and budget rule deleted. Tracking issue for the rest. |
| **R24** | **spec-flow + architecture** | ACs that stub `soleur-boot-emit` **remove the component under test** (the detail gate lives inside it), and the terminal fatal is emitted by the trap in `cloud-init.yml`, not by the helper — so such a harness cannot observe the deliverable at all. Grep-shaped ACs are likewise evadable (`if ! soleur-doppler-download` reintroduces R9 and passes a `grep 'if ! doppler'`). | ACs are **behavioural and end-to-end**: exercise helper → trap → the **real** emitter, and assert on the emitted body. |
| **R25** | **Architecture, verified — plan was factually wrong** | The first draft said the new helper would be "installed by the same loop" as `soleur-boot-emit`. **False**: `soleur-boot-emit` is authored by a `cat > /usr/local/bin/… <<'EMITEOF'` heredoc, not the `install -D -m 0755 "$SEED/$f"` loop, and is **not** covered by the later `test -x` assertion block. A truncated heredoc still yields `/run/soleur-hostscripts.ok`, and the terminal block then dies `command not found` (127). | Helper is a heredoc **plus its own `FAILED_FILE` + `test -x` assertion**. AC-F pins it. **Heredoc, not a seed file** — a new file under `$SEED` would force edits to `local.host_script_files`, the image bake and the coherence preflight, falsifying *Files to Create*. |
| **R26** | **Kieran — P0 introduced by this plan's own first draft, re-verified** | **`cmd && rc=0 \|\| rc=$?` is an AND-OR list, which `set -e` exempts — so the non-zero is swallowed and execution CONTINUES.** Measured: `dash -c 'set -e; (exit 7) && rc=0 \|\| rc=$?; echo continued'` prints `rc=7` **and** `continued`. The `exit 1` that makes the block fail-closed today lives *inside the `if !` branch the plan deletes*. Two fall-through outcomes, both **worse than #6969**: (a) `$TMPENV` removed → `docker run --env-file` fails → the trap fires with `stage` already advanced → **the fatal is mistagged `docker_run`**; (b) `$TMPENV` empty → `docker run` **succeeds** → boot reaches `cloud_init_complete` and the gate reports **"booted clean" on a host with no prd secrets**. A green-and-broken serving host is strictly worse than a dark one. | **Mandatory: `[ "$rc" = 0 ] \|\| exit "$rc"` immediately after the capture.** Verified to restore fail-closed (`exit=7`). AC-E asserts the *re-raise*, not merely the absence of `if !`. This is the single most dangerous line in the change. |
| **R27** | **Kieran, verified** | **`grep -c` exits 1 when the count is 0.** The observability suite opens with `set -euo pipefail`, so any AC shaped `grep -c … = 0` **aborts the runner** instead of reporting. Measured: `grep -c ZZZ file` → prints `0`, exits **1**. The file's own idiom is `if grep -q …; then ok; else no; fi`. | All absence-checks use the `if grep -q` idiom (or `{ grep -c … \|\| echo 0; }`), and anchor on **non-comment lines** — R28. |
| **R28** | **Kieran — self-reference trap** | An AC asserting `grep 'head -c' = 0` in the sanitizer is **near-certain to red-fail permanently**, because this plan's own R1 and Sharp Edges make the implementer write a comment there explaining *"`tail -c`, not `head -c` — the 173-byte preamble…"*. Same class for any grep forbidding a filtered stage name in a helper that will carry a comment explaining the carve-out. | Absence-greps anchor on **code shape** (non-comment, non-blank lines), never raw token absence. Prefer a **behavioural** assertion wherever one exists — which is why AC-A/AC-B/AC-E are harness-driven rather than grep-driven. |
| **R29** | **Kieran — R10's mechanism was wrong, and the hazard is worse** | The first draft said "2+ attempts in 1h clears `value = 1`, i.e. '>1'", which would imply a *single* warning on the terminal stage is safe. `issue-alerts.tf` states the opposite **twice, verbatim**: the rule is *"reachable only because its shared `soleur-boot-emit` group is always already hot"* and *"works there ONLY because its shared `soleur-boot-emit` group is never new (always already >1)"*. The group is **perpetually over threshold**, so the condition is effectively always satisfied and the **first** matching event pages. | The `doppler_retry` fix is unchanged and correct, but the rationale is corrected: **even one** `warning` carrying a filtered stage name pages the founder. RK9 severity stands. |
| **R30** | **Kieran, verified** | The stderr temp file is `mktemp`'d **inside the baked helper — a separate process running a separate script**. Its variable is not in the caller's scope, so the `cloud-init.yml` EXIT trap **cannot** reference it. The first draft's "extend the terminal trap's cleanup" is unimplementable, and the matching test would verify a cleanup placed where it cannot work. | **The helper owns its own EXIT trap** for its own temp file. The cloud-init trap keeps cleaning `$TMPENV` only. |
| **R31** | **Kieran, verified** | (a) The `$${...}` escaping rule as first written ("any new inline shell variable expansion") is **overbroad** — `templatefile()` interpolates only `${`, and the file's own trap proves it: `rm -f "$${TMPENV:-}"` escapes the brace form while `$?`, `$rc`, `$stage` stay bare. Following the broad rule would render `$$rc`. (b) `issue-alerts.tf` carries the payload claim in **two** places, not one — a pre-resource line and an in-resource line beside `actions_v2`. (c) `tail -c` can split a UTF-8 sequence; on a fail-open emitter an invalid tag value loses the breadcrumb **entirely**. | (a) Rule narrowed to the **brace form only**. (b) **Both** comments corrected (AC-O). (c) An ASCII-only pass **after** the cap (`LC_ALL=C tr -cd '\11\40-\176'` or `iconv -c`), so truncation can never emit a partial multi-byte sequence. |
| **R32** | **Kieran — the ACs need a harness that exists** | The behavioural ACs execute code that lives only as **heredoc text inside `soleur-host-bootstrap.sh`**, which cannot be sourced (it apt-installs, docker-logins, runs under `set -e`). Without a named extraction method they silently degrade to static greps at `/work` time — leaving the R9 and R26 defences **unverified**, which is precisely the failure class this PR exists to end. | **Cite the existing prior art**: `apps/web-platform/infra/fresh-boot-ready.test.sh` extracts a heredoc body with `awk "/cat > \/usr\/local\/bin\/<name> <<'<EOF>'/{f=1;next} f&&/^<EOF>$/{f=0} f{print}"` and then runs it. Every behavioural AC uses this pattern. |

### Premise validation (Phase 0.6)

- `gh issue view 6969` → **OPEN**, `closedByPullRequestsReferences: []`. Premise holds.
- Cited paths and both cited learnings exist (all `knowledge-base/` citations Glob-verified).
- **ADR-082** is `superseded-in-part` by ADR-128, but its **Item 5 (terminal-block boot-emit trap) remains IN FORCE** and is "web-1's sole no-SSH boot page". **ADR-145** owns the birth path. Neither ADR's rejected-alternatives table contains "add a detail channel to the boot emitter" — this is a gap, not a rejected idea.

## Hypotheses

**Every hypothesis below is `UNKNOWN`. None is CONFIRMED and none is REFUTED.**

Written under the standing sharp edge from
`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`:
*a hypothesis table may not read CONFIRMED or REFUTED while the plan's own text says the deciding
datum is unavailable.* The deciding datum — the CLI's stderr and exit code on the failing host — **was
discarded at the source and no longer exists**. Nothing in this plan may be justified by a verdict below.

| # | Hypothesis | Status | What would discriminate it |
|---|---|---|---|
| H1 | Transient network / DNS race at cold boot | **UNKNOWN** | stderr carrying a resolver/dial error — **or `rc=124`**, which only exists once R19's `timeout` lands |
| H2 | Doppler API rate limit or 5xx | **UNKNOWN** | a non-auth `Doppler Error:` line + exit code |
| H3 | `DOPPLER_CONFIG_DIR=/tmp/.doppler` creation/permissions on a fresh host (the prior root-owned finding, #6536) | **UNKNOWN** | a path/permission error in stderr. **This is the hypothesis a prior plan "refuted by reasoning" and which then measured as the actual cause** |
| H4 | CLI-version behaviour at v3.75.3 | **UNKNOWN** | exit code + stderr shape |

**Already ruled out by the issue, not re-litigated:** token scope (HTTP 200 for
`project=soleur&config=prd`; HTTP 400 discriminating control for `prd_workspaces_luks`); server type /
architecture (`cpx22` and `cx23` both x86; `amd64` pinned throughout); stale image pin (`$PINNED`
frozen off-host, coherence preflight passed).

**Not independent evidence:** the absence of Better Stack lines for `soleur-web-2`. Vector's token comes
from the very Doppler fetch that failed, so that silence is *expected*.

**Network-outage checklist (Phase 1.4):** not triggered — none of the trigger substrings appear and no
`provisioner`/`connection` block is in scope. No L3→L7 ordering claim is made. H1 stays UNKNOWN, and
R19's `timeout` is precisely what would give it a signal.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `ignore_changes = [user_data, …]`
means this reaches **no running host**. The realistic broken-landing outcome is a *future* fresh host
that fails to boot (fail-closed, serving-weight 0, behind the anti-pooling `lb-weight-gate`), or a
refused birth dispatch (RK1). Neither touches app.soleur.ai, served by web-1 alone.

**If this leaks, the user's data is exposed via:** the captured stderr payload. This ships
previously-discarded process output to Sentry. If the scrubber fails, or the capture spans **stdout**
(where `--format docker` writes **the entire prd secret set**), a prd credential lands in Sentry — a
credential-exposure path to all user data. This is the sole reason the threshold is not `none`.

**Brand-survival threshold:** `single-user incident` → `requires_cpo_signoff: true`;
`user-impact-reviewer` at review time; escalated plan-review panel (already run).

**CPO sign-off required at plan time before `/work` begins.** No brainstorm preceded this plan.

## Files to Edit

| File | Change | `user_data` cost |
|---|---|---|
| `apps/web-platform/infra/soleur-host-bootstrap.sh` | (a) `soleur-boot-emit`: read `/run/soleur-stage-detail.d/$STAGE` (fallback: legacy file) into a sanitized `detail` tag; add a `host_name` tag via a new `@@SOLEUR_HOST_NAME@@` sentinel + a second `sed -i` splice. (b) New baked helper `soleur-doppler-download` (heredoc) owning `timeout`, retry, stderr capture, scrubbing, per-attempt breadcrumbs, and the final `.d/doppler_download` summary write. (c) `FAILED_FILE` + `test -x` assertions for **both** helpers (R25). | **0** |
| `apps/web-platform/infra/cloud-init.yml` | Terminal block: replace the `if ! doppler …` branch with a call to the helper plus `&& rc=0 \|\| rc=$?`. Extend the trap's cleanup. Deliberately **thin**. | ~**+60 B gzipped** |
| `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` | New ACs (this suite already carries 23 and is the natural home). | n/a |
| `.github/workflows/apply-web-platform-infra.yml` | (a) Interpolate `detail`/`exit_code` into the **`::error::` annotation strings**, not only the trail printer — the annotation is what surfaces at the top of the run page. (b) Add `host_name` to the `LAST_STAGE`/fatal **selection**, not just the printed line. `QUERY` message literals **unchanged**. | n/a |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | **Comment only** (R13). No filter/threshold/action change. | n/a |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | Only if the measured render exceeds `WEB_GZIP_BUDGET`. Prefer not to. | n/a |
| `knowledge-base/engineering/architecture/decisions/ADR-147-*.md` | **New ADR** (see Architecture Decision). | n/a |

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-147-boot-stage-diagnostics-live-in-baked-host-scripts.md`

**No `model.c4` edit.** The enumeration below concludes no new elements and no new edges; amending a
relationship *description string* to list tag names is documentation that rots on the next tag added.

## Open Code-Review Overlap

**None.** Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200`
piped through standalone `jq --arg path … | contains($path)` for `cloud-init.yml`,
`soleur-host-bootstrap.sh`, `apply-web-platform-infra.yml`, and the op-contract test. Zero matches.

## Implementation Phases

### Phase 0 — Preconditions

- **G1 — Byte budget baseline + marginal ratio.** Pre-change render **23,184 B** base64gzip against
  `WEB_GZIP_BUDGET = 23_700` → **~516 B headroom** (hard cap 32,768 → 9,584 B). **Measured marginal cost
  of *novel* inline shell: ~0.46 gzipped B per raw byte** (227 raw B → +104 gzipped B). Do **not** use the
  ~5.8:1 ratio you get from measuring duplicated text. **Working budget: ≈1,100 raw bytes of new inline
  shell, total.** That is what makes the baked-helper decision non-negotiable rather than stylistic.
- **G2 — Ingestion probe for the payload actually shipped (R21; scope reduced by R2-corrected).** POST
  the **full new tag set** (`stage`, `host_id`, `region`, `host_name`, `exit_code`, `detail`) — plus
  `extra` if adopted — to the Sentry store API and confirm **HTTP 200 and that the fields render**. A
  locally-valid JSON body is a proxy; ingestion is the invariant, and on a fail-open emitter a rejected
  payload is *worse than today*. **Corrected risk level:** `extra` is **not** an unknown — four in-repo
  emitters already ship it to this exact endpoint (`ci-deploy.sh`, `container-restart-monitor.sh`,
  `cron-egress-resolve.sh`) — so this probe answers a *field-count and length* question, not a
  *field-support* one. If any field is rejected or silently truncated, drop it rather than ship a silent
  loss. Record the verdict in the PR body.
  <!-- verified: 2026-07-26 doppler v3.75.3 — exit=1, 246 B stderr, head -c 200 → 0 matches of
       "Doppler Error", tail -c 200 → 1; token NOT echoed; ANSI colour present -->

### Phase 1 — The error channel, in the shared baked emitter — **0 `user_data`**

**This is the deliverable. If anything must be cut, everything else goes first and this ships alone.**

1. Add a `@@SOLEUR_HOST_NAME@@` sentinel + a second `sed -i` splice beside the existing DSN splice
   (same non-`/` delimiter idiom, same `${SOLEUR_HOST_NAME:-$(hostname)}` fallback `vector.toml` uses).
   **Assert no residual `@@` survives the splice** — a typo'd sentinel would otherwise ship
   `host_name=@@SOLEUR_HOST_NAME@@` on every event, silently.
2. Give the emitter a `detail` channel reading **`/run/soleur-stage-detail.d/$STAGE`**, falling back to
   the legacy `/run/soleur-stage-detail` when the per-stage file is absent. Legacy producers and the
   inline `_emit` consumer are **untouched** (R18). Sanitizer, in order:
   - drop `^Using ` preamble lines (this is what actually defeated `head`);
   - `LC_ALL=C` pinned — locale-dependent `tr -cd '[:print:]'` can leave a partial multi-byte sequence
     that makes the JSON invalid, and on a fail-open emitter that loses the breadcrumb entirely;
   - strip control characters; drop `"` and `\`; **fold newlines to spaces — load-bearing**, since
     newlines are *documented* as impermissible in Sentry tag values and stderr is multi-line by nature;
   - **trim** leading/trailing whitespace — defensive only; the "Sentry drops untrimmed values" claim is
     **undocumented**, so this is cheap insurance, not a fix for a known vendor behaviour;
   - **`tail -c 180`** (under the documented 200-char tag cap), then an **ASCII-only pass AFTER the cap**.
     Rationale corrected: an over-long or invalid-UTF-8 tag is **silently truncated / sanitized at 2xx**,
     *not* rejected — so this guards against **losing the cause inside a surviving event**, not against
     losing the event. Still worth doing: a silently truncated cause is the failure this PR exists to end.
   Validated at plan time: real stderr → **68 B**, `jq -e .` **VALID JSON**; adversarial fixture with
   quotes, backslashes, ANSI escape, BEL and embedded newlines also **VALID JSON**.
3. **Carry `exit_code` and `attempts` inside the detail string**, not as new positional args. The
   emitter's signature is `soleur-boot-emit <stage> [level]` and the trap calls it with two args from
   three different sites; adding positional tags would leave them empty on exactly the deliverable
   (R-CTO/architecture P1-2). One mechanism, pinned.
4. **Author `/usr/local/bin/soleur-doppler-download`** as a heredoc (the same authoring form as
   `soleur-boot-emit` — **not** the `install -D` loop, which only handles files that come from the seed),
   **and add `FAILED_FILE` + `test -x` assertions for both helpers** (R25).
5. **Do not change** the emitter's `message` literal or any of the four alert-filtered stage names.

### Phase 2 — Bounded, self-reporting download, in the baked helper

1. **Stdout is reserved for the secret payload.** `--format docker` writes the entire prd secret set to
   stdout into `$TMPENV`, which is `--env-file`'d into the container. **Any diagnostic `echo` in this
   helper corrupts `$TMPENV`** → malformed env-file → a fatal that names the wrong stage (`docker_run`).
   All diagnostics go to stderr or the detail files. No `2>&1`, no `&>`.
2. Redirect the CLI's **stderr only** to a `mktemp` file, `chmod 600`, removed on every path.
3. **`timeout 45` per attempt** (mirrors the 11 bounded sibling calls), and record **`rc=124` as a
   distinct named condition** — without it the channel is blind to a hang (R19).
4. **Capture the exit code with `cmd && rc=0 || rc=$?` — and re-raise (R9 + R26).** The AND-OR list is
   `set -e`-exempt, so the capture alone **silently continues the boot**. The call site MUST be:
   ```sh
   soleur-doppler-download "$TMPENV" && rc=0 || rc=$?
   [ "$rc" = 0 ] || exit "$rc"      # ← restores fail-closed; without this the host can boot green and secretless
   ```
5. Invoke with **`NO_COLOR=1`** for a deterministic payload.
6. Bounded retry: **`N = 3` attempts, backoff `sleep 5` then `sleep 10`.** Worst case added latency
   ≈ 3 × 45 s + 15 s = **150 s**, budgeted against the host's own
   `SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900` and the gate's 960 s deadline. Pinning N and the backoff is
   load-bearing: an unbudgeted retry can push the boot past 900 s and convert a *diagnosable* `fatal`
   verdict into an *undiagnosable* `timeout` — the retry would then degrade the very channel it rides on.
7. **Emit ordering inside the loop is load-bearing and must be written in this order** (R-P2-7):
   `rc` capture → scrub → write `.d/doppler_retry` → emit `warning` → increment `n` → exhaust-check →
   sleep. Placing the emit *after* the exhaust-check makes the final attempt emit nothing, which would
   break AC-C. Note `n=$((n+1))` resets `$?`, so `rc` must be captured before it.
8. Each **failed** attempt emits a **`warning`** tagged **`stage=doppler_retry`** (non-prefixing, R20).
   Skip the warning on the *exhausting* attempt: the fatal carries the same rc and attempt count, so it
   is pure duplication and would otherwise make the gate's `LAST_STAGE` read `doppler_retry` on a
   sub-second race.
9. **Before returning non-zero, write the final summary to `.d/doppler_download`** — `rc`, attempt count,
   and the scrubbed stderr. **This is the line that keeps R15 dead**: the terminal trap emits
   `stage=doppler_download` and reads that exact file.
10. **Defence-in-depth scrub:** strip `dp\.[a-z]*\.[A-Za-z0-9_-]*` before any write. The "stderr does not
    echo the token" measurement is pinned to v3.75.3, and *CLI-version behaviour* is itself a live
    UNKNOWN (H4).
11. **The helper owns its own EXIT trap** for its own `mktemp` file (R30). It runs as a **separate
    process**, so the `cloud-init.yml` trap cannot see that variable; that trap keeps cleaning `$TMPENV`
    only.
12. Escaping (R31a): `templatefile()` interpolates **only the `${...}` brace form**. Escape new
    **brace** expansions as `$${...}`; leave `$?`, `$rc`, `$stage` bare — exactly as the file's existing
    trap does (`rm -f "$${TMPENV:-}"` alongside a bare `$?`). The broad "escape everything" rule renders
    `$$rc` and is wrong.

### Phase 3 — `docker_run` sibling (narrowed, R23)

Capture `docker run` stderr into `.d/docker_run`. It is the one alert-filtered sibling, it dies with no
echo at all, and it is the most likely next dark boot. **All other stages: one tracking issue**, filed
before the PR is marked ready (`wg-when-deferring-a-capability-create-a`). The first draft's 8-row table
and its "stop at `BUDGET − 100`" rule are deleted — they made the shipped scope a function of
measurement order.

### Phase 4 — Make the failing *run* self-reporting

1. Interpolate `detail` / `exit_code` / `host_name` into the **`::error::` annotation strings**, not only
   the trail printer. The annotations surface at the top of the run page; summary lines require opening
   the job summary. This is the difference between "go read Sentry" and "the run told you why".
2. Add `host_name` to the `LAST_STAGE` and fatal **selection**, not just the printed line — the gate
   currently matches on message regex with **no host filter**, which is the ambiguity the issue hit.
3. Emit a `::warning::` when a **green** birth's trail contains any `doppler_retry` — otherwise a
   retry-that-succeeded leaves its cause in a green run's collapsed summary, seen by no one.
4. `QUERY` message literals stay **byte-identical**.

### Phase 5 — ADR + tests

Write ADR-147; extend the observability suite; run the full infra set.

## Acceptance Criteria

Lettered to avoid the numbering hazard of the first draft. Every AC is a checkable post-condition;
grep-shaped and prose-shaped criteria were cut (R24).

**Two mechanical rules bind every AC below (R27, R28, R32):**
1. **Never `grep -c … = 0`** — `grep -c` exits **1** on zero matches and the observability suite runs
   `set -euo pipefail`, so such an AC *aborts the runner*. Use the suite's own `if grep -q …; then ok;
   else no; fi` idiom, or `{ grep -c … || echo 0; }`.
2. **Absence-checks anchor on non-comment lines.** This plan's own Sharp Edges guarantee the
   implementer writes comments containing `head -c` and the filtered stage names; a raw token-absence
   grep would red-fail permanently on correct code.
3. **Behavioural ACs use the existing extraction harness.** The helper and emitter live as heredoc text
   inside `soleur-host-bootstrap.sh`, which cannot be sourced. Reuse the prior art in
   `apps/web-platform/infra/fresh-boot-ready.test.sh`, which `awk`-extracts a heredoc body and runs it.
   Without this, every behavioural AC silently degrades to a static grep and the R9/R26 defences ship
   **unverified** — the exact failure class this PR exists to end.

### Pre-merge (PR)

- **AC-A (sanitizer, behavioural)** — The recorded 246-B **synthesized** fixture through the shipped
  sanitizer yields **valid JSON** (`jq -e .`) containing `Doppler Error`, ≤ 180 B, no `[3` ANSI residue,
  no leading/trailing whitespace. Adversarial fixture (`"`, `\`, `\n`, ESC, BEL, 4 KB junk, a
  `dp.st.prd.SYNTHETIC` token) also yields valid JSON with the token pattern absent. Subsumes the
  first draft's `grep 'tail -c'` / `grep '^Using '` / `NO_COLOR` ceremony ACs.
- **AC-B (R15 — the headline invariant, end-to-end)** — Harness stubs `doppler` to fail on all attempts
  and drives **helper → trap → the REAL `soleur-boot-emit`** (never a stubbed emitter — the detail gate
  lives inside it, R24). Asserts exactly one `fatal` with `stage=doppler_download` **whose `detail` is
  non-empty and contains the CLI error line, the exit code, and the attempt count**. *Asserting only
  "one fatal tagged doppler_download" is the proxy that let the first draft ship green.*
- **AC-C (evidence preserved on success)** — Same harness, `doppler` fails once then succeeds: the
  command **succeeds**, and exactly one `warning` tagged `stage=doppler_retry` was captured carrying a
  non-empty detail. No `fatal`.
- **AC-D (no false page, R10/R20)** — (i) No `warning`-level emit carries any of the four alert-filtered
  stage values **at runtime** (asserted in the AC-C capture, not by grep — the terminal block emits via
  a mutable `"$stage"`, so a grep cannot see it). (ii) `doppler_retry` does **not** string-prefix any
  filtered stage. (iii) `issue-alerts.tf`'s filter set still contains exactly the original four values.
- **AC-E (exit code survives AND the boot stays fail-closed, R9 + R26)** — Three arms, all behavioural:
  (i) stub the CLI to exit 7 → the emitted `exit_code` reads **7**;
  (ii) stub it to hang → `timeout` fires and `exit_code` reads **124** (R19);
  (iii) **fail-closed arm** — with the CLI failing, the terminal block must **not** reach
  `docker_run`. Assert the call site contains the re-raise (`[ "$rc" = 0 ] || exit "$rc"`) *and*
  behaviourally that execution stops. **Without (iii) the plan's own headline line silently converts a
  fail-closed boot into a fail-open one**, whose worst outcome is a host reporting `cloud_init_complete`
  with no prd secrets — strictly worse than #6969.
- **AC-F (helper install, R25)** — `soleur-doppler-download` is authored and has a `FAILED_FILE` +
  `test -x /usr/local/bin/soleur-doppler-download` assertion; the `@@SOLEUR_HOST_NAME@@` splice leaves
  **no residual `@@`**.
- **AC-G (sweep, R23)** — `docker_run` stderr is captured to `.d/docker_run`, asserted by emitting for
  `docker_run` and reading back a non-empty detail. A tracking issue exists for the remaining stages.
- **AC-H (no stdout capture / no corruption — see Phase 2 step 1)** — Grep spans **both** `cloud-init.yml` **and** the
  `soleur-doppler-download` body: no `2>&1`, no `&>`, and the helper writes nothing to stdout except
  the secret payload. *This is the most valuable criterion in the plan* — a stray `2>&1` converts this
  feature into credential exfiltration.
- **AC-I (channel isolation, R18)** — Writing `.d/doppler_download` then emitting for `docker_run`
  yields an **empty** detail; and the five legacy payload shapes still produce **byte-identical** output
  through the inline `_emit` path (legacy untouched).
- **AC-J (message lockstep, R12)** — `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
  passes; the four workflow `QUERY` literals still match byte-for-byte (AC8 checks both directions).
- **AC-K (stage lockstep)** — `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-web-terminal-boot-fatal-op-contract.test.ts`
  passes; the `key = "stage"`-only filter invariant still holds.
- **AC-L (byte budget)** — `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes; PR body
  records measured render before/after (baseline **23,184** / budget **23,700**).
- **AC-M (gate self-reporting)** — A synthetic Sentry-events fixture through the extracted `jq` yields
  `stage`, `detail`, `exit_code`, `host_name`; and the `::error::` strings interpolate `detail`/`exit_code`.
- **AC-N (ADR)** — ADR-147 exists, `status: accepted`, and records the four frozen contract constraints.
- **AC-O (alert comments, R13 + R31b)** — **Both** payload claims are corrected, not one: the
  pre-resource line (`Events carry only stage/host_id/region tags — no user content.`) **and** the
  in-resource line beside `actions_v2` (`stage/host_id/region — no cross-tenant content.`). Each must
  name the `detail` tag and state that it is scrubbed and byte-capped. `terraform validate` passes; the
  diff touches no filter/threshold/action attribute. **Note the tension with AC-D(iii):** AC-D asserts
  `doppler_retry` is absent from the alert's **filter values**, while AC-O's corrected comment may
  legitimately *mention* it — so AC-D(iii) must scope to `value = "…"` entries, not the block's raw text.

### Post-merge

- **AC-P** — The image carrying the new baked scripts is built before any birth dispatch. Enforced by the
  existing merge-triggered `web-platform-release.yml` build plus the birth path's coherence preflight,
  which **refuses** on skew rather than birthing a dark host. No SSH, no added step.

**Success definition (not an AC):** the next birth either reaches `cloud_init_complete`, or its
`::error::` names an actual cause. This is evidence-gated on an operator-dispatched birth outside this
PR, so it is a definition of done for the *issue*, not a merge criterion.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed. Found two HIGH defects (R9, R10), both re-verified and fixed; corrected the
sequencing framing (R8) and the tags-vs-`extra` rationale (R12); contributed `NO_COLOR`, whitespace-trim,
`$${...}` escaping, and the token-pattern scrub. Confirmed the `n=0; until …` idiom is safe under `set -e`
(non-final AND-OR members and `until` conditions are exempt) and that `/run` is tmpfs well before `runcmd`.

### Plan-review panel (escalated — `single-user incident`)

**Status:** reviewed. `architecture-strategist`, `spec-flow-analyzer`, `code-simplicity-reviewer`, `kieran`.

- **architecture + spec-flow converged independently on R15** — the plan-defeating empty-`detail`
  composition defect. Fixed by R18's per-stage files plus AC-B's non-empty assertion.
- **architecture contributed R18, R19, R20, R25** — all re-verified before folding in.
- **spec-flow contributed R21, R24**, the `::error::`-vs-trail-printer distinction, the gate's missing
  host filter, and the retry-latency-vs-900s budget.
- **simplicity contributed R22, R23**, the AC/test-scenario reduction, and the `tail`-generalisation
  caveat. Its central recommendation — **cut the retry entirely** — is a scope change to operator-stated
  direction and is therefore recorded as a **User-Challenge**, not silently applied (see below).

### Product/UX Gate

**Not applicable — Tier NONE.** The mechanical UI-surface override does not fire: no path in *Files to
Edit*/*Create* matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Skipped
specialists: none. Pencil: N/A.

### Compliance (GDPR gate, Phase 2.7)

Canonical regex does not match. Invoked only via trigger (b) — the `single-user incident` threshold —
scoped to the one real question: this ships previously-discarded process stderr to Sentry (existing
sub-processor, DE residency, Art. 30 PA8). Controls are the byte cap, the scrubber, and the
stdout/stderr separation (AC-A, AC-H). No personal data: machine output from a boot process.

### Decision challenges (headless — recorded, not applied)

Persisted to `knowledge-base/project/specs/<branch>/decision-challenges.md` for `/ship` to render into
the PR body and file as an `action-required` issue. **Challenge:** two independent signals (the
simplicity reviewer, plus both cited learnings) argue the bounded retry should be **cut** from this PR so
the error channel ships alone. The plan **retains** it because the issue explicitly scopes it — but
Phase 2 is deliberately separable and is the designated descope target.

## Infrastructure (IaC)

### Terraform changes

**None functional.** No resource, variable, vendor account, or secret is added; no `TF_VAR_*`
(`hr-tf-variable-no-operator-mint-default` not engaged). The only `.tf` touch is a **comment** in
`sentry/issue-alerts.tf` (R13) — an HCL comment inside a `resource` block produces **no plan diff**.
Everything else is a `templatefile()` source and a baked shell helper delivered via the existing
image-bake path (ADR-080 / #5921).

### Apply path

**(a) cloud-init-only.** `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`
means the change reaches a host **only at a fresh create**. Downtime: none. Blast radius on existing
hosts: **zero**. `terraform plan` shows **no diff** for the cloud-init half — that is the *expected*
output, **not** evidence the change had no effect.

**Deliberately no running-host delivery path.** The artifact is first-boot-only provisioning logic;
`runcmd` is once-per-instance, so there is no running-host analogue to deliver.

### Distinctness / drift safeguards

`ignore_changes` keeps the edit inert on prod. `local.host_scripts_content_hash` is the coherence
control — an image lacking the new baked scripts fails loudly at `STAGE=verify`, and the birth path's
pre-apply preflight refuses before any create. No secret added to `user_data` or `terraform.tfstate`.

### Vendor-tier reality check

Not engaged — no vendor resource created. The added Sentry events occur only per *fresh host birth*, a
rare gated event; no metered-volume consequence.

## Observability

```yaml
liveness_signal:
  what: "Sentry boot-stage breadcrumb `soleur-cloud-init boot stage` with tags.stage advancing to `cloud_init_complete`"
  cadence: "once per fresh host birth (runcmd is once-per-instance; not periodic)"
  alert_target: "sentry_issue_alert.web_terminal_boot_fatal (first-occurrence page, value=1/1h, IssueOwners + ActiveMembers)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf; emitted by /usr/local/bin/soleur-boot-emit (baked by apps/web-platform/infra/soleur-host-bootstrap.sh)"

error_reporting:
  destination: "Sentry (jikigai-eu/web-platform) via the store API with the baked ${sentry_dsn} — SSH-free by construction; works on a host that never finished booting"
  fail_loud: true

failure_modes:
  - mode: "Doppler secrets download fails fast at first boot (the #6969 symptom)"
    detection: "in-surface: `fatal`, tags.stage=doppler_download, detail carrying the CLI's own stderr + exit_code + attempt count"
    alert_route: "web_terminal_boot_fatal + the birth-path ::error:: annotation (now interpolating detail/exit_code)"
  - mode: "Doppler download HANGS (structurally invisible before this change)"
    detection: "in-surface: `timeout 45` fires; exit_code=124 recorded as a distinct named condition"
    alert_route: "same as above — previously produced NO event at all"
  - mode: "Fails transiently, then succeeds on retry"
    detection: "in-surface: one `warning` tagged stage=doppler_retry per failed attempt, emitted before the backoff sleep"
    alert_route: "no page (host is healthy); a ::warning:: annotation fires on the green run so the cause is not buried"
  - mode: "A later boot stage dies with stderr discarded"
    detection: "in-surface: shared emitter reads /run/soleur-stage-detail.d/<stage>; docker_run wired in Phase 3"
    alert_route: "web_terminal_boot_fatal (stage-filtered)"
  - mode: "Host attribution ambiguous on a shared Sentry project"
    detection: "tags.host_name on boot-stage events, AND used in the gate's LAST_STAGE/fatal selection (not merely printed)"
    alert_route: "n/a — attribution fix; removes the Hetzner API lookup #6969 required"
  - mode: "The emitter itself drops the event (fail-open) or the payload is rejected"
    detection: "NOT observable at runtime by design. Gated PRE-merge by G2's ingestion probe and AC-A/AC-B."
    alert_route: "CI. Named residual: the operator then sees the gate's `timeout` verdict with LAST_STAGE unset."

logs:
  where: "Sentry (primary, SSH-free). Host journald is NOT relied upon: Vector's Better Stack token comes from the very Doppler fetch that can fail."
  retention: "Sentry project retention (jikigai-eu/web-platform)"

discoverability_test:
  command: |
    curl -s --max-time 20 -G -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
      --data-urlencode "per_page=100" --data-urlencode "statsPeriod=1h" --data-urlencode "sort=-timestamp" \
      "https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/events/" \
    | jq -r '.[] | select(((.message // .title) // "") | test("soleur-cloud-init boot stage"))
             | [([(.tags//[])[]?|select(.key=="stage")|.value][0]),
                ([(.tags//[])[]?|select(.key=="host_name")|.value][0]),
                ([(.tags//[])[]?|select(.key=="detail")|.value][0])] | @tsv'
  expected_output: "For the failing boot: stage=doppler_download with a detail string containing the CLI's own error line and exit code — the cause, not merely the stage. NO ssh."
```

Per `hr-observability-layer-citation`: emitting layer = baked `/usr/local/bin/soleur-boot-emit` (authored
in `soleur-host-bootstrap.sh`); alerting layer = `sentry/issue-alerts.tf`; gating layer = the dark-boot
step in `apply-web-platform-infra.yml`.

Per **§2.9.2**: a first-booting host is a blind surface. Every `detection` names an **in-surface** probe.
The fields **discriminate all competing hypotheses in one event**: `exit_code=124` isolates a hang (H1),
a non-auth `Doppler Error:` isolates H2, a path/permission string isolates H3, and the stderr shape
isolates H4 — which the single `stage=doppler_download` tag could not do.

**Soak follow-through (§2.9.1):** not engaged — no AC is time-gated; the success definition is
evidence-gated on a dispatched birth, so there is no `earliest=` directive to enroll.

## Encryption Posture

Detection fired on `cloud-init.*\.ya?ml$`.

```yaml
at_rest:
  - store: "/run/soleur-stage-detail.d/<stage> (new per-stage boot diagnostic buffers)"
    mechanism: plaintext-exception
    evidence: "/run is tmpfs on Ubuntu 24.04 (systemd-provided); never touches a block device, vanishes on reboot"
    defends_against: "at-rest disclosure via disk/volume/snapshot capture — the data never lands on a block device"
    does_not_defend: "a root-capable process reading it live; world-readable by default"
    disclosed_as: "not disclosed — transient boot diagnostics, no personal data"
    live_verification: "findmnt -no FSTYPE /run  →  tmpfs"
  - store: "temp file holding the Doppler CLI's captured stderr"
    mechanism: plaintext-exception
    evidence: "mktemp + chmod 600, removed on every exit path (mirrors the existing $TMPENV handling)"
    defends_against: "other-user read (0600); post-boot persistence (unlinked on all paths)"
    does_not_defend: "root reading it during the boot window; a crash between mktemp and rm leaving it until reboot"
    disclosed_as: "not disclosed — machine stderr, measured NOT to echo the token on the pinned CLI"
    live_verification: "AC-H asserts stdout is never routed here; cleanup asserted by the AC-B/AC-C harness"

in_transit:
  - connection: "booting host → Sentry store API (existing edge, enriched payload)"
    tls: "TLS 1.2+ (https://de.sentry.io)"
    cert_verification: on
    does_not_defend: "Sentry-side exposure once ingested — readable by anyone with project access; this is why the scrubber, the 180-byte cap and the stdout/stderr separation are load-bearing"
    disclosed_as: "Art. 30 PA8 §(e) — Sentry, DE residency"
  - connection: "booting host → Doppler API (existing, unchanged)"
    tls: "TLS 1.2+ (doppler CLI default)"
    cert_verification: on
    does_not_defend: "n/a — unchanged by this plan"
    disclosed_as: "existing sub-processor disclosure"

exception:
  - store: "/run/soleur-stage-detail.d/* and the stderr temp file"
    justification: "Boot diagnostics on a host with no secret store yet — the failing component IS the key source, so any at-rest encryption would need a key from the service that is down. tmpfs + 0600 + unlink-on-all-paths + 180-byte cap + scrubbing is the achievable control set."
    tracking_issue: "#6969 — the controls ship WITH the exception, not deferred"
    reevaluate_when: "the boot path gains a pre-Doppler key source, or a measured stderr is observed carrying secret material"
    expires_on: "2027-01-26"
```

## Architecture Decision (ADR/C4)

### ADR

**New: ADR-147 — "Boot-stage diagnostics live in baked host-scripts, not `user_data`."** Both the CTO
and the architecture reviewer asked for a standalone record rather than an amendment: ADR-082 is
`superseded-in-part`, and burying new forward-looking constraints inside a partially-superseded ADR
forces every future reader to reconstruct which items survive — the exact friction this plan itself hit.

The ordinal **147** is provisional (highest present: ADR-146). A sibling PR can claim it during the
pipeline; `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`. **If renumbered, sweep
the whole feature's artifacts** — `grep -rn 'ADR-147' knowledge-base/project/{plans,specs}/feat-one-shot-6969-*`
— so no AC ends up asserting a nonexistent file.

ADR-147 records the four frozen cross-consumer contract constraints (AC-N):
1. emit **message literals** are frozen — for the birth-path gate *and* for Sentry issue grouping
   (`value = 1` only pages on an already-hot group);
2. **alert-filtered stage names** are frozen;
3. **a non-fatal breadcrumb may never reuse — or string-prefix — an alert-filtered stage name**;
4. **boot-stage retry and diagnostic capture live in the baked host-scripts**, behind the
   `host_scripts_content_hash` coherence gate, not in `user_data` — the budget-vs-sequencing tradeoff.

ADR-082's Item 5 gets a one-line pointer to ADR-147; its own status is unchanged.

### C4 views

**All three model files were read**, not grepped for the feature's own noun.

- **External human actors:** none added — machine-to-machine telemetry only.
- **External systems:** `sentry`, `doppler`, `hetzner`, `ghcr`/`zotRegistry`, `betterstack` — **all
  already modeled** in `model.c4` and **all already present** in the `views.c4` include lines (confirmed
  in both the context and container view include lists).
- **Containers / data stores touched:** `hetzner` (Compute) — already modeled.
- **Actor↔surface access relationships:** none change. No ownership, tenancy, or sharing boundary moves.
- **Relationship edges:** exactly one is relevant and it **already exists** — `hetzner -> sentry`
  ("Host-side fatal + deploy telemetry, POSTed straight to the store API with the baked `${sentry_dsn}`
  — the boot fatal-emit trap armed at the TOP of `runcmd:`…"). Its description already covers this
  behaviour at the right altitude.

**Verdict: no new C4 elements, no new edges, and no edit.** Enumerating tag names inside a relationship
description would rot on the next tag added. This is a cited enumeration, not an unsupported "None", so
no `view … include` line is required and no undefined-element render failure is possible.

## Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| **RK1** | **Image/hash skew.** Editing the bootstrap moves `host_scripts_content_hash`; a pre-merge `image_tag` — which the workflow's own fallback text invites — carries stale baked scripts. | Medium | **Verified fail-closed:** the coherence preflight compares pre-apply, so the outcome is a *refused dispatch*, not a dark host. PR body warns that a pre-merge tag will now fail preflight, so the error is recognised rather than retried. |
| **RK2** | **Lockstep breakage.** Renaming a message literal darks the birth-path gate *and* mints a new Sentry group that no longer pages; renaming a filtered stage darks the alert. Both fail **silently**. | High | AC-J + AC-K pin both directions. **Design rule: add tags, never rename; never string-prefix a filtered stage.** |
| **RK3** | **Secret leak into telemetry.** Captured output reaching Sentry could carry prd secrets — a credential path to all user data. | High | stderr-only capture; stdout structurally reserved for the payload; scrubber + 180-byte cap; measured non-echo; **AC-H spans both files**. |
| **RK4** | **Byte budget.** ~516 gzipped B headroom; novel shell costs ~0.46 gz B/raw B → ~1,100 raw B budget. | Medium | Bulk baked (0 cost); AC-L re-measures. Raising the budget is a **tripwire**, not a capacity limit (hard cap 9,584 B away) and must be justified in-file. |
| **RK5** | **Retry masks the cause**, or its latency pushes the boot past 900 s and converts a diagnosable `fatal` into an undiagnosable `timeout`. | Medium | Per-attempt `warning` before the sleep; N and backoff **pinned** (3 attempts, worst case ≈150 s vs a 900 s window); `::warning::` on green runs. If any of these cannot hold, **cut the retry** (User-Challenge, recorded). |
| **RK6** | **`set -e` / trap interaction**, and the new temp file leaking. | Medium | Capture `rc` immediately; extend the trap cleanup; AC-B/AC-C cover both. CTO confirmed the `until` idiom is `set -e`-safe. |
| **RK9** | **False page on a healthy boot** — the alert has no `level` filter, and its shared group is **perpetually hot**, so the **first** matching event pages (R29). Even a *single* warning carrying a filtered stage name pages the founder. | High | Distinct **non-prefixing** `doppler_retry` (AC-D), asserted at runtime rather than by grep. |
| **RK14** | **Fail-open regression (R26).** The prescribed `rc` capture is `set -e`-exempt; omitting the re-raise lets the boot continue with an empty/absent `$TMPENV`, producing either a **mistagged** fatal or a host reporting `cloud_init_complete` **without prd secrets**. | **High** | Mandatory `[ "$rc" = 0 ] \|\| exit "$rc"`, pinned behaviourally by AC-E(iii). |
| **RK10** | **Stale detail cross-contamination** — a *plausible wrong answer* is worse than no answer. | Medium | Per-stage files (R18); AC-I. |
| **RK11** | **`templatefile()` interpolation** — new inline `${...}` is interpolated at apply time unless written `$${...}`. | Medium | Phase 2 step 10; `validate-infra-templates.sh` renders and schema-checks in CI, and the size test throws on any un-provided `${var}`. |
| **RK12** | **Correlated failure** (full layer sweep in *Research Insights → Network-Outage Deep-Dive*). The emitter's only transport is `curl` to Sentry, so H1 — a cold-boot network fault — can disable the very channel that would discriminate H1. | Medium | **Named, not papered over.** Partially mitigated by `timeout 45` + `rc=124`: a *hang* now produces a named fatal where it previously produced silence. Honest residual: if egress is fully dead, no Sentry event exists and the gate's `timeout` verdict is the only signal — that verdict is itself the documented dark-boot signal. No SSH or console step is prescribed (`hr-no-ssh-fallback-in-runbooks`). |
| **RK13** | **Truncation pressure.** The gate reads `per_page=100` on a **shared** project; extra attempt events make a full page (and thus a false `timeout` on a healthy host) more likely. | Low | Skip the warning on the exhausting attempt; N capped at 3. Pre-existing guard (`TOTAL >= 100` note) still fires. |

## Research Insights (deepen-plan)

### Precedent diff (Phase 4.4) — pattern-bound behaviors

Three of this plan's prescriptions are pattern-bound. All have in-repo precedent; **none is novel**.

| Prescribed shape | Canonical precedent | Adopted verbatim? |
|---|---|---|
| Bounded retry | `n=0; until <cmd>; do n=$((n+1)); [ "$n" -ge N ] && exit 1; sleep S; done` — 6 instances in `cloud-init.yml` (`cf_apt_key` N=3/5 s, `apt_update` N=2/10 s, `apt_install` N=2/10 s, and three `doppler secrets get` loops at N=3/5 s wrapped in `timeout 45`) | **Yes.** N=3 with `timeout 45` matches the Doppler-specific sibling loops exactly, not the apt ones. |
| Baked helper authoring | `cat > /usr/local/bin/<name> <<'<EOF>'` — **6** existing helpers (`soleur-boot-emit`, `soleur-wait-ready`, `soleur-wait-nic`, `soleur-vector-install`, `soleur-luks-structural-gate`, `soleur-fresh-boot-ready`) | **Yes.** Confirms R25: the `install -D` loop is for seed-sourced files only. |
| Heredoc test extraction | `apps/web-platform/infra/fresh-boot-ready.test.sh` — `HELPER="$(awk "/cat > \/usr\/local\/bin\/soleur-fresh-boot-ready <<'FRESHREADYEOF'/{f=1;next} f&&/^FRESHREADYEOF\$/{f=0} f{print}" "$BOOT")"` then runs it | **Yes.** This is the harness every behavioural AC must reuse (R32). |
| Detail-capture + sanitize | The inline `_emit`'s `DETAIL=$(tr -cd '[:print:]' < /run/soleur-stage-detail 2>/dev/null \| tr -d '"\\' \| head -c 200)`, fed by `tail -c 140`/`tail -c 160` writers | **Extended, not copied.** The plan keeps the writer's `tail -c` direction (correct) and fixes three latent bugs the precedent carries: `head -c` on the reader, no whitespace trim, no locale pin. |

**Scheduled-work check:** not applicable — this plan introduces no cron, timer, or recurring job.

### Verify-the-negative pass (Phase 4.45)

Every load-bearing negative claim in the plan was re-probed against the repo. **9 of 10 CONFIRM; 1
CONTRADICTS**, and the contradiction was material enough to change a design justification.

| # | Claim | Verdict |
|---|---|---|
| 1 | Five legacy `/run/soleur-stage-detail` producers + the inline `_emit` consumer are untouched | **CONFIRMS** — exactly 5 writers, all outside the terminal block this plan edits |
| 2 | `soleur-boot-emit` is heredoc-authored, not `install -D`, not in the `test -x` block | **CONFIRMS** — the `test -x` loop iterates a fixed list that excludes it |
| 3 | The failing `doppler secrets download` is the only unbounded Doppler call | **CONFIRMS** — 11 `timeout`-wrapped, 1 not, and the 1 is the failing call |
| 4 | `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` | **CONFIRMS** |
| 5 | Alert has no `level` filter; exactly four `key = "stage"` filters | **CONFIRMS** |
| 6 | Op-contract test asserts `toContain("stage=doppler_download")` | **CONFIRMS** — the prefix hazard (R20) is real |
| 7 | Workflow `QUERY` has exactly four `message:"…"` literals | **CONFIRMS** |
| 8 | `cron-egress-enforce-probe.sh` already self-emits with a `probe_result` tag | **CONFIRMS** — correctly excluded from the sweep |
| 9 | "No emitter in `apps/web-platform/infra/` sends `extra`" | **CONTRADICTS** — see corrected R2 |
| 10 | `fresh-boot-ready.test.sh` awk-extracts a heredoc and runs it | **CONFIRMS** — the harness R32 mandates exists |

**The one contradiction mattered.** The plan had justified tags-only partly on "`extra` is unverified
and a rejected payload is worse than today". That premise was false: `extra` ships to this exact
endpoint from four in-repo emitters. The *decision* survives on the stronger, true ground (the gate's
`jq` reads `.tags[]` and cannot see `extra`; tags don't affect grouping), but the plan no longer rests
on a claim that a single grep falsifies. This is the same discipline the plan preaches — a premise
stated confidently is still a premise until it is probed.

### Sentry store-API contract (framework-docs research)

The one genuinely vendor-dependent surface, now researched with citations. **Three of this plan's own
claims were overstated and are corrected here** — the sanitizer design is unchanged, but its
*justification* is now accurate.

| Question | Answer | Source |
|---|---|---|
| Tag **value** length limit | **200 chars**, and over-length is **silently TRUNCATED at 2xx** — *not* rejected | [Event Payloads](https://develop.sentry.dev/sdk/data-model/event-payloads/) |
| Tag **key** limit / max tag count | 200 chars; **max count undocumented** | same |
| Newlines in tag values | **Not permitted** — documented | [setTag API](https://docs.sentry.io/platforms/javascript/configuration/apis/) |
| Leading/trailing whitespace | **UNDOCUMENTED** — the "Sentry drops untrimmed values" claim is unverified | [getsentry/sentry#64541](https://github.com/getsentry/sentry/issues/64541) |
| `extra` on `/store/` | **Documented optional field.** 16 kB per item, 256 kB total | [Event Payloads](https://develop.sentry.dev/sdk/data-model/event-payloads/) |
| `server_name` on `/store/` | **Documented optional field** | same |
| Rejection behaviour | 2xx on accept; **4xx only on a malformed envelope**. Field over-runs truncate silently | [getsentry/sentry#80434](https://github.com/getsentry/sentry/issues/80434) |
| Grouping | **Tags do NOT affect grouping; `message` DOES** — confirms R12 | [Grouping](https://develop.sentry.dev/backend/application-domains/grouping/) |
| Invalid UTF-8 in a tag | **Sanitized (U+FFFD), not rejected** | [sentry-ruby#1911](https://github.com/getsentry/sentry-ruby/issues/1911) |

**Corrections to this plan's own claims:**

1. **Newline-folding is load-bearing, not cosmetic.** Newlines are *documented* as impermissible in tag
   values, and captured stderr is multi-line by nature. The sanitizer's `fold newlines to spaces` step is
   promoted from tidiness to a correctness requirement.
2. **An over-long tag does NOT lose the event** (this plan said it might). It truncates silently at 2xx,
   so `curl -sf` still succeeds. The 180-byte cap therefore guards against **silent data loss of the
   cause**, not against event loss — a weaker but still sufficient reason to keep it.
3. **Invalid UTF-8 does NOT lose the event either** (R31c overstated this). It is sanitized to U+FFFD.
   The ASCII pass after the cap stays for **determinism and readability**, not survival.
4. **Whitespace-trim is defensive, not a known bug.** The CTO-sourced "Sentry drops untrimmed tag
   values" claim is undocumented; trimming is cheap and harmless, so it stays — but the plan no longer
   asserts a vendor behaviour it cannot cite.

**Forward-looking note (out of scope, worth recording):** the `/store/` endpoint is **deprecated** in
favour of `/envelope/`. Every boot-stage emitter in this repo uses `/store/`, and
`cron-egress-resolve.sh` already carries a comment anticipating the sunset. Migrating the emitter fleet
is **not** in this PR's scope; it belongs in the tracking issue Phase 3 already requires.

### Network-Outage Deep-Dive (Phase 4.5)

**Gate fired** on the `timeout` trigger substring. Telemetry emitted
(`hr-ssh-diagnosis-verify-firewall applied`). This plan is **not** an SSH-connectivity diagnosis and
prescribes no SSH step, but H1 is a network hypothesis, so the layer sweep is recorded honestly:

| Layer | Status for this plan |
|---|---|
| **L3 firewall allow-list** | **Not applicable and not claimed.** No SSH/provisioner path is in scope; the change is delivered by cloud-init on a *fresh* host, and no resource in scope has a `provisioner "file" / "remote-exec" / connection { type = "ssh" }` block. |
| **L3 DNS / routing** | **Explicitly UNVERIFIED, and that is the point.** H1 (cold-boot DNS/dial race) is one of the four live hypotheses. There is no artifact to cite because the deciding datum was discarded — which is precisely what this PR ships. `rc=124` + the stderr body are the artifacts a future occurrence will produce. |
| **L7 TLS / proxy** | Unchanged. The Sentry POST already uses HTTPS with default CA verification; the Doppler CLI likewise. Neither is modified. |
| **L7 application** | The failing component's own error channel is the deliverable. |

**Gap closed by this plan, not before it:** the L3 layer currently has *no* observable at all from the
booting host, because the only unbounded Doppler call in the file emits nothing on a hang (R19). Adding
`timeout 45` + `rc=124` is what makes an L3 fault distinguishable from an L7 auth error at all.

**Honest residual (RK12):** the emitter's only transport is `curl` to Sentry, so a *total* egress failure
disables the discriminator for the hypothesis most likely to have caused it. The plan names this rather
than claiming coverage it does not have. No SSH or console remediation is prescribed
(`hr-no-ssh-fallback-in-runbooks`).

### Downtime & Cutover (Phase 4.55) — gate evaluated, does not fire

No trigger matches, and the reason is load-bearing rather than incidental:

- **Infra reboot/replace class:** no. `hcloud_server.web` pins `user_data`, `ssh_keys`, `image` **and**
  `placement_group_id` under `lifecycle.ignore_changes`, so none of the attributes this plan touches can
  produce a `-/+` on a running host. `terraform plan` shows **no diff** for the cloud-init half. (The
  `placement_group_id` token appears in this plan only inside a *quotation* of that ignore list — it is
  not being changed.)
- **Database lock class:** no migration, no DDL, no backfill.
- **Deploy/router class:** no container swap, no tunnel or connector restructure.

The change reaches a host **only at a fresh create**, which is by definition a host carrying zero
traffic (serving-weight 0, behind the anti-pooling `lb-weight-gate`). Availability of the serving
surface is untouched.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6.
- **`head -c` is wrong for this CLI and the issue text says `head`.** The first 173 B of the auth-failure
  stderr are `Using DOPPLER_*` preamble. Drop the preamble, then `tail -c 180`. Measured 2026-07-26 on
  the pinned v3.75.3 — and that measurement covers **auth failure only**; other failure shapes are unmeasured.
- **`if ! cmd; then … $?` yields 0** in dash and bash. Use `cmd && rc=0 || rc=$?` — **and then
  `[ "$rc" = 0 ] || exit "$rc"`.** The AND-OR list is `set -e`-exempt, so the capture *alone* deletes
  the fail-closed `exit` that lives inside the branch you are replacing. Worst case is not a missing
  diagnostic: it is a host that reports `cloud_init_complete` with **no prd secrets**.
- **`grep -c` exits 1 on zero matches**, and the observability suite runs `set -euo pipefail` — a
  `grep -c … = 0` acceptance check aborts the runner instead of reporting. Use `if grep -q`.
- **Absence-greps must skip comments.** These very Sharp Edges guarantee the code will contain the
  words `head -c` and `doppler_download` in explanatory comments.
- **Never merge the streams.** `--format docker` writes the entire prd secret set to **stdout**. A
  `2>&1`/`&>` — or any stray `echo` inside the helper — turns diagnostics into credential exfiltration
  or an env-file corruption that misattributes the fatal to `docker_run`.
- **Add tags; never rename — and never string-prefix a filtered stage.**
  `"stage=doppler_download_attempt".includes("stage=doppler_download")` is `true`, which would make the
  op-contract test's anti-rename guarantee vacuous.
- **A per-emit buffer clear silences the fatal.** Whatever scheme scopes the detail, the terminal trap
  emits *after* the last attempt — it must find a buffer written for **its own** stage.
- **The fix cannot repair `soleur-web-2`.** `runcmd` is once-per-instance and `ignore_changes = [user_data]`
  means the template never re-reaches a live host. Do not propose a reboot. Destroying the host re-arms
  the `host_creates` HALT (it is declared in `var.web_hosts`).
- **Editing `soleur-host-bootstrap.sh` moves `host_scripts_content_hash`**, which the boot re-verifies
  against the image — even though it costs 0 `user_data`.

## Alternative Approaches Considered

| # | Alternative | Verdict |
|---|---|---|
| **A1** | Patch only the doppler site | **Rejected.** Leaves every sibling blind; costs more `user_data` per unit of coverage than fixing the shared emitter. |
| **A2** | **Ship the error channel alone; cut the retry.** | **Recorded as a User-Challenge, not applied.** The `2026-07-16` learning says the probe ships alone, and explicitly flags *"they ride the same artifact"* as a **circular** justification — so that argument is not used. The retry is retained because the issue scopes it, because it is not a fix for a *diagnosed* cause (all hypotheses UNKNOWN), and because AC-C makes it evidence-**preserving**. The simplicity reviewer's counter — that R10/RK9 exist *only because of* the retry — is the strongest argument against, and is recorded verbatim in `decision-challenges.md`. **Phase 2 is deliberately separable and is the designated descope target.** |
| **A3** | Sentry `extra` / top-level `server_name` | **Re-assessed after verification.** The first draft rejected `extra` as "unverified on the store endpoint" — **that premise was wrong** (corrected R2: four in-repo emitters already ship `extra` to this endpoint). The **tag** remains the load-bearing channel because the birth-path gate reads `.tags[]` and cannot see `extra`; `extra` is now an *available, precedent-backed* place to put deeper stderr behind that tag. Top-level `server_name` remains unadopted — a `host_name` **tag** is what the gate can actually select on. |
| **A4** | Ship stderr via journald → Vector → Better Stack | **Rejected.** Structurally impossible: Vector's token comes from the very fetch that failed. |
| **A5** | `<stage>\|<detail>` wire format in the legacy buffer | **Rejected** in favour of per-stage files (R18) — the wire format created a delimiter collision with existing content, a migration nobody owned, and (via R15) the empty-`detail` defect. |
| **A6** | Amend ADR-082 instead of a new ADR | **Rejected** — it is `superseded-in-part`; new constraints there are hard to read. ADR-147 stands alone. |
| **A7** | Destroy and rebirth `soleur-web-2` in this PR | **Out of scope.** Gated `workflow_dispatch` decision; re-arms the `host_creates` HALT. |

**Deferral tracking:** R22 (`host_name` on the other two emitters) and R23 (remaining sweep stages) each
need a tracking issue filed before the PR is marked ready.

## Test Scenarios

| # | Scenario | Method | Asserts |
|---|---|---|---|
| T1 | Sanitizer, real + adversarial fixtures | shell | AC-A in full |
| T2 | **Exhaustion → fatal carries the cause** | helper → trap → **real** emitter | AC-B (the headline invariant) |
| T3 | Fail-once-then-succeed | same harness | AC-C; no fatal; one `doppler_retry` warning |
| T4 | Exit code 7 and hang→124 | stubbed CLI | AC-E |
| T5 | Temp-file hygiene, both paths | same harness | No residue after success or failure |
| T6 | Stream separation | grep across **both** files | AC-H |
| T7 | Channel isolation + legacy parity | shell | AC-I |
| T8 | Helper install + sentinel splice | observability suite | AC-F |
| T9 | `docker_run` capture | shell | AC-G |
| T10 | Lockstep (message + stage) | existing suites | AC-J, AC-K |
| T11 | Byte budget | `bun test` | AC-L |
| T12 | Gate printer + `::error::` interpolation | fixture through extracted `jq` + grep | AC-M |

### Green baseline (measured 2026-07-26, before any change)

| Suite | Command (verified to run) | Baseline |
|---|---|---|
| Boot observability | `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` | **95 passed, 0 failed** |
| Terminal-boot op contract | `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-web-terminal-boot-fatal-op-contract.test.ts` | **4 passed** (vitest v4.1.0) |
| `user_data` size | `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` | **30 passed**; render **23,184 B** / budget **23,700 B** |

The observability suite already carries 23 numbered ACs and is the natural home for the new ones.

Test-runner note (**verified**): `apps/web-platform` uses **vitest** (`./node_modules/.bin/vitest run <path>`
from inside the package — **not** `npm run -w`, which has no root `workspaces` field); `plugins/soleur`
uses **bun test**; `apps/web-platform/infra/*.test.sh` are plain `bash`. `vitest.config.ts` collects
`["test/**/*.test.ts", "lib/**/*.test.ts"]` (node) and `["test/**/*.test.tsx"]` (jsdom) — a test
co-located under `components/` or `server/` is silently skipped. Put new TS tests in `test/`.
