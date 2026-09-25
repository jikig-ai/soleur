---
title: "fix(cutover): scope op=resume G3 host-audibility to the current dedicated server instance"
date: 2026-09-24
slug: fix-cutover-resume-g3-current-host-scope
branch: feat-one-shot-cutover-resume-g3-host-scope
issue: none
type: bug
lane: cross-domain
domain: engineering
priority: p2
brand_survival_threshold: aggregate pattern
related: [8714, 8747, 8690, 7674, 7462, 6616, 8741]
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

# fix(cutover): scope op=resume G3 host-audibility to the current dedicated server instance

## Enhancement Summary

**Deepened on:** 2026-09-24.

**Sections enhanced:** Proposed Solution, Architecture Decision (new), Technical Considerations,
Implementation Phases, Guard Contract (3 guards), Observability, Encryption Posture (new),
Acceptance Criteria, Test Scenarios and Risks (precedent diff).

**Agents used:**

- security-sentinel, observability-coverage-reviewer, test-design-reviewer and
  architecture-strategist;
- a verify-the-negative sweep on the standard tier, which confirmed 10 of 10 plan claims against
  the code;
- at plan review: DHH, Kieran, code-simplicity and CTO (devex).

### Key improvements

1. **Credential tier.** The anchor reads `HCLOUD_TOKEN_READONLY` first, per ADR-241 D4 and the
   #8209 tier map, and falls back to `HCLOUD_TOKEN`. The earlier Tier-B-only read would have broken
   every gate at operator step O10.
2. **Public-log hygiene.** The token is `::add-mask::`ed on stderr. curl's and jq's stderr are
   discarded, since both can quote response bytes. The notice is built only from validated integers
   and `$INNGEST_HOST`. The name is sent with `--data-urlencode`.
3. **Two independent clocks.** A row counts only if both hold:
   - the host's event time is at or after `created`;
   - Better Stack's ingest `dt` is at or after `created`. That is the AP-027 anchor clock.

   Two epoch bounds (no earlier than 2025, no more than 300 s in the future) stop a near-0 floor
   from silently reverting the fix.
4. **Diagnosable refusals.**
   - A counts-only breakdown (`counted`, `host_pair`, `pre_floor`, `malformed`, `skew_suspect`)
     separates "not shipped yet", "clock behind" and "schema drift". This supersedes plan review's
     single-count cut, and it stays on stderr only.
   - A young-server "WAIT, do NOT replace" warning prevents today's `silent` text from
     recommending destroying a healthy replacement.
   - HTTP 401/429/5xx get distinct warnings, and `-f` is dropped.
5. **Architecture record.**
   - An ADR-225 §4 amendment: "audible" is scoped to the current server generation, citing AP-027.
   - A C4 `github -> hetzner` Cloud API edge. It was missing even for today's reads.
   - Invariant pins: no `create_before_destroy`, no `current_boot_only = false`, no
     `actions/rebuild`.
6. **Test design.**
   - The `doppler` mock branches on arguments, which fixes a `fail` row that would otherwise pass
     for the wrong reason.
   - An `anchor-late` row proves the floor comes from the anchor.
   - A curl `exit 99` stub sits in every harness.
   - There is an executed unfloored-latch row.
   - The fixture self-check runs on shared fixture variables.

### New considerations discovered

- The pre-existing op=backup token handling (argv, echoed body, unmasked) was filed as **#8767**.
- The Hetzner API's `created` is returned in `Z` form today (measured), and the decoder accepts
  both forms.
- `DOPPLER_TOKEN` reaches every op on every dispatching branch. A main-only branch rule on the
  `inngest-cutover` environment is worth a separate check. It is noted in Technical Considerations,
  and not in scope here.

## Overview

`scripts/cutover-inngest.sh` op=resume gates its `INNGEST_CUTOVER_FLIP=flushed` write on G3, a
host-audibility check that counts `inngest-cutover-flip` rows from the dedicated host within the last
15 minutes. The host filter keys on `host` + `host_name`, which are identical for the old and the
replacement server, so on the 2026-09-24 host replace the check counted the destroyed host's
leftover rows and reported the replacement as audible before it shipped a single row. This plan
scopes the predicate to the current server instance and adds a failing test first.

## Research Insights

### Premise Validation

- Cited context issues: #8714 (OPEN, ADR-096 GHCR retirement steps) and #8747 (OPEN, off-main tag
  acceptance) are context only, no action here. Draft PR #8690 (OPEN) edits only a header comment
  of `scripts/cutover-inngest.sh` (~L56-60, `betterstack-query.sh --since` form). It does not touch
  G3. This plan adds code near the liveness readers (~L355-440) and the `resume)` / `luks-*)` arms,
  so a textual conflict with #8690 is unlikely.
- **The ask's first suggested mechanism, "filter FSM rows by the new host's identity", does not
  hold as stated. Measured:** the reader ALREADY filters on identity (`host == "soleur-inngest"
  and host_name == "soleur-inngest-prd"`, `_flip_liveness_count`). Both fields are the same on the
  old and replacement servers. `host` is Vector's OS hostname = the Hetzner server name, a TF literal
  (`inngest-host.tf`: `name = "soleur-inngest"`). `host_name` is a sed-rendered literal. Hetzner
  server names are unique per project, and `hcloud_server.inngest` has no `create_before_destroy`,
  so a replace always destroys the old server and then creates a new one with the same name. No
  identity field the reader has today can tell the old host from the new one.
- **Per-instance fields DO exist in every row (measured 2026-09-24, `betterstack-query.sh --since
  15m --grep inngest-cutover-flip`):** the decoded `.raw` carries journald's `_MACHINE_ID`,
  `_BOOT_ID`, `__REALTIME_TIMESTAMP` and `__MONOTONIC_TIMESTAMP` (µs, decimal strings). `vector.toml`
  names none of them, so Vector passes them through unfiltered.
  `boot_instant = __REALTIME_TIMESTAMP - __MONOTONIC_TIMESTAMP` is constant across every row of a
  boot. Over 1,375 rows it gave exactly one value per (machine, boot).
- **Measured incident timeline (2026-09-24):**

  | Instant (UTC) | Event | Source |
  |---|---|---|
  | 2026-09-23T19:36:02Z | old server boot instant (machine `3cff04d3…`, boot `c127d0a4…`) | derived from 1,357 rows |
  | 14:25:05 | old server's last `inngest-cutover-flip` row | Better Stack |
  | 14:29:02 | run 36013051602 op=resume G3: "host is audible (45 … rows … within 15m)", then wrote `flushed` at 14:29:03 | run log |
  | 14:25–18:59 | ZERO rows from any `soleur-inngest` machine | Better Stack |
  | 18:57:33 | current server `soleur-inngest` id 167310350 `created` | Hetzner API |
  | 18:57:51 | current server boot instant (machine `1f034cef…`, boot `4a2506ef…`), 18 s after `created` | derived |
  | 18:59:58 | first row from the current server | Better Stack |
  | 19:00:05 | run 36045048975 G3 correctly REFUSED (0 rows) | run log |
  | 19:02:27 | run 36045234529 G3 passed on 15 rows from the current server; `flushed-resume-no-reflush` landed 19:03:12 | run log + Better Stack |

  A second data point for the creation-to-boot margin: `soleur-web-platform` has `created`
  06:37:09Z and boot instant 06:37:23Z (14 s).
- **"It fails safe" is only partly true, so this plan does not rely on it.** The 14:29 run DID write
  `flushed`. It did no harm only because a `flushed` flag waits for whichever host next runs the
  on-host timer. By 19:00 the flag read `done` again. No host shipped rows in between, so which host
  moved it (a non-shipping interim server during the #8741 Vector-download stall, or something else)
  cannot be read from the telemetry. The defect is that G3 claimed a fact it had not measured.

### Property List (Phase 0.6b)

- P1. op=resume's G3 passes only when the dedicated server that exists NOW has itself shipped at
  least one `inngest-cutover-flip` row inside the window. Rows from a destroyed predecessor that
  had the same name never count.
- P2. When G3 cannot establish which server is current (Hetzner read failed, no server, several
  servers), it refuses before the write. A `::warning::` names that cause and is distinct from both
  the Better Stack credential failure and the dark-host case.
- P3. Every other liveness gate built on the same identity filter (op=arm G3.7 H via the shared
  `_flip_liveness_count`, and the op=luks-cutover/luks-rollback G3 via `_luks_liveness_count`)
  measures the same instance-scoped quantity, so the shared reader cannot mean two things.
- P4. A test fixture reproducing the 2026-09-24 shape (host-pair rows in the window whose boot
  predates the current server) drives the gate RED on today's code before the fix lands.

### Cut List (Phase 0.6b)

- "Filter FSM rows by the new host's identity" (from the ask) buys P1. It is cut as the SOLE
  mechanism because the identity fields do not change across a replace (measured above). The only
  per-instance identity in the rows is `_MACHINE_ID`/`_BOOT_ID`. Every other channel that carries a
  boot or instance id comes from the host itself, so none is independent of the telemetry being
  judged. Those channels are the `SOLEUR_INNGEST_SERVER_PROBE` row (`boot_id`,
  `instance_id=hetzner-<id>`), the cloud-init phone-home (`inngest-boot-phone-home.sh`, which also
  posts to Better Stack) and the Sentry boot emit. The Hetzner API names the server's `id` and
  `created`, but not its machine or boot id. The time floor below covers P1 with that independent
  authority.
- "Require rows newer than the new host's boot/replace time" (from the ask) is KEPT. It is the
  mechanism, anchored on the Hetzner API's `created` for the server named `$INNGEST_HOST`. The
  script already calls the same Hetzner API endpoint and token in op=backup (`HCLOUD_TOKEN` via the
  prd_terraform-scoped `DOPPLER_TOKEN`).

### Relevant files

- `scripts/cutover-inngest.sh`:
  - `INNGEST_HOST` / `INNGEST_HOST_NAME` identity block, with the #6616 rationale.
  - `_bs_query_rows`, the shared Better Stack reader (8 call sites, pinned by the suite).
  - `_flip_liveness_count`, whose `FLIP_LIVENESS_SINCE="15m"` is a pinned literal, not an env var.
  - `_luks_liveness_count`.
  - `resume_liveness_decide`, the pure decider shared by resume G3 and LUKS G3.
  - `flush_latch_decide` (arm G3.7).
  - The `resume)` arm: the G3 block before the Doppler write of the flag.
  - The `luks-cutover|luks-rollback)` arm: the G3 block.
  - The `arm)` arm: the G3.7 block.
  - The `backup)` arm: the Hetzner API precedent.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`:
  - §(b2) `call_flip_liveness_count`, an executed reader with a mocked `doppler`. Modes: rows,
    foreign, spoofed, empty, fail.
  - §(b3) `rsl_case` decide table, plus ordering pins on `RESUME_FILE`.
  - Call-site count pins (`FLQ_SITES == 8`, `FLQ_FLIP_SITES == 2`, `FLQ_LUKS_SITES == 2`).
  - `_EXACT_FLOOR=753`, the anti-deletion floor. It must be bumped by the measured delta.
  - Baseline: 753 passed / 0 failed in 13.6 s locally. CI runs it in `infra-validation.yml`.
- `tests/scripts/lib/inngest-host-dark-gate.sh`: prior art for per-boot joins
  (`_erg_hb_newest` filters on `_BOOT_ID` equal to the probe row's `boot_id`). Nothing here reuses
  it. It answers a different question, keyed on the hourly probe row.
- `apps/web-platform/infra/inngest-cutover-flip.sh` `emit_state`: the emitter. `logger -t
  inngest-cutover-flip "$json"` produces journald rows with the fields above.
- `apps/web-platform/infra/inngest-host.tf`: `hcloud_server.inngest` `name = "soleur-inngest"`,
  `lifecycle { ignore_changes = [ssh_keys] }`, no `create_before_destroy`.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-17-host-name-create-time-render-drift-web1-mislabel.md`
  (#6616): a label rendered at create time is not a runtime identity. Measure the telemetry itself.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  (#7493, this same script). Must-PASS rows must not be the canonical fixture. `mutate()` inside
  `$( )` is vacuous. Suites need a floor on their own dispatch.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`:
  the existing `foreign`/`spoofed` fixtures must keep POST-floor boot instants. Otherwise they would
  read 0 because of the new floor instead of the host conjunct, and the #6616 isolation assertion
  would go vacuous without anyone noticing.
- `knowledge-base/project/learnings/2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`:
  positive-only oracles over a single-shape fixture set cannot tell the fix from its absence. The
  matrix includes mixed old+new rows.

### Conventions (from the SUT's own contracts)

- Pure decide functions are extracted by awk range `/^name\(\) \{$/,/^\}$/`. The signature and the
  closing brace sit at column 0, with no column-0 `}` inside the body.
- Readers never echo a row. They count only, and a non-decimal count becomes `__UNREADABLE__`.
- Distinct outcomes for distinct remediations (the `silent` vs `unreadable` split, #7674).
- Secrets travel on stdin, never argv (the AC6 house rule the arm's Doppler writes follow). The new
  Hetzner read follows it: the header is fed via `curl -H @-`, verified locally on curl 8.22.
- No SSH anywhere (`hr-no-ssh-fallback-in-runbooks`).

### Verified tool behavior (local)

- jq 1.8.2 `tonumber` on the 16-digit µs strings is exact
  (`"1790276905314305" | tonumber - 633512324` = `1790276271801981`).
- `fromdateiso8601` parses `2026-09-24T18:57:33Z` to `1790276253`, and yields nothing on the older
  `+00:00` form, so the decoder normalizes that form first.
- `curl -H @-` reads the header from stdin.

### External research

Skipped. The codebase and live telemetry answer every question, and the Hetzner endpoint is already
in use in this file.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` found no community artifact that overlaps. The
fix is repo-specific.

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask | Reality (measured) | Plan response |
|---|---|---|
| G3 "counts FSM rows from ANY host" | It already filters `host == soleur-inngest AND host_name == soleur-inngest-prd`. "Any host" really means "any *server instance* carrying that name", which the identity pair cannot tell apart. | Keep the identity pair (it still excludes web hosts, #6616). Add an instance floor on top of it. |
| "Filter FSM rows by the new host's identity" | The identity fields are the same across a replace. The only per-instance fields are `_MACHINE_ID`/`_BOOT_ID`, and no authority outside Better Stack names the new server's values. | Rejected as the sole mechanism. A time floor from Hetzner `created` is equivalent here, because destroy-then-create is forced by Hetzner name uniqueness. |
| "Require rows newer than the new host's boot/replace time" | Hetzner `GET /v1/servers?name=` returns `created`. Every row carries `__REALTIME_TIMESTAMP`/`__MONOTONIC_TIMESTAMP`, so each row's boot instant is derivable. Measured boot − created = +18 s (inngest) and +14 s (web). | Adopted. Count only rows whose boot instant is at or after `created`. |
| "It fails safe (nothing is written without the new host)" | The 14:29 run wrote `flushed`. It was harmless only because the flag waits for the next host's timer. | Not relied upon. The fix makes G3's claim true, independent of downstream behavior. |
| The runbook (`inngest-server.md`) says a freshly replaced host "is not audible until Vector is up and shipping", so G3 refuses | False today. The predecessor's rows made G3 pass 4 min after the old host's last row. | The runbook is corrected in this PR to describe the instance-scoped G3. |

## Proposed Solution

*(Revised after plan review and again at deepen-plan. See §Plan Review Revisions and §Enhancement
Summary.)*

Every Better Stack **liveness** count that gates a Doppler write now counts only rows from the
**current server generation**. This is the property AP-027 (ADR-149) names: a `host_name` filter
scopes to the HOST, not its GENERATION. The floor is applied **inside the two readers**, so no call
site changes, and three write-gating gates are covered by construction:

- op=resume G3;
- op=arm G3.7 H;
- op=luks-cutover and op=luks-rollback G3.

### 1. Anchor: `_inngest_server_created_epoch` (I/O)

**Contract.** It always prints exactly one token and always returns 0. The token is `<epoch>`,
`__ABSENT__` or `__UNREADABLE__`. Every non-epoch outcome is preceded by one `::warning::` on stderr
naming its cause.

1. **Token, Tier A first (ADR-241 D4, #8209).**
   - Read `HCLOUD_TOKEN_READONLY` from prd_terraform. Fall back to `HCLOUD_TOKEN` only when that read
     is empty. This is the precedent at `.github/workflows/workspaces-luks-cutover.yml` (the
     `# (#8209 D4) TIER A` block).
   - Measured 2026-09-24: prd_terraform holds only `HCLOUD_TOKEN` today, so the fallback is the
     live path until the read-only name is provisioned. `infra-credential-tiers-8209.md` row
     `cutover-inngest.yml::cutover` already classifies this workflow's Hetzner reads as Tier A.
   - Both reads use `2>/dev/null`.
   - If both are empty, skip curl and print `__UNREADABLE__`, with the cause "neither
     HCLOUD_TOKEN_READONLY nor HCLOUD_TOKEN resolved from prd_terraform".
2. **Mask.** Immediately after a non-empty read, run `printf '::add-mask::%s\n' "$tok" >&2`.
   - It goes to STDERR. The readers run inside `X="$(…)"`, so a mask written to stdout would be
     swallowed into the count.
   - Doppler-read values are not auto-masked by GitHub. Every other Doppler-read secret in this
     script is masked (PG, HB, APP_CK, BS_API).
3. **Request.** This is a GET with the token header on stdin, the name URL-encoded, and curl's own
   stderr discarded:

   ```bash
   printf 'Authorization: Bearer %s\n' "$tok" \
     | curl --disable --noproxy '*' -s --proto =https --max-time 20 \
            --get --data-urlencode "name=$INNGEST_HOST" -H @- \
            -w '\n%{http_code}' https://api.hetzner.cloud/v1/servers 2>/dev/null
   ```

   - No `-f`, so the HTTP code is readable. No `-S`: curl's error text is not a sanctioned egress
     path.
   - No `--retry`, per the #6500 sharp edge.
   - Split the result into the body and the last line (the HTTP code). The body is held in a
     variable only, never echoed and never written to disk.
   - A non-zero curl rc or a code that does not match `^[0-9]{3}$` gives `__UNREADABLE__`, with the
     warning naming the rc class: 6/7 egress, 28 timeout, 35/60 TLS.
   - Any code other than 200 gives `__UNREADABLE__`, with the warning naming the class: 401/403
     token rejected, 429 rate-limited, 5xx Hetzner API outage.
4. **Decode**, via the pure `_hcloud_created_epoch <json> <name>` (§2).
5. **Bounds.** An epoch below `1735689600` (2025-01-01) or more than 300 s in the future gives
   `__UNREADABLE__`. A floor near 0 would re-admit the predecessor, which silently reverts this fix.
6. **Warnings always name the cause and the next step:**
   - Nothing was written, and re-dispatch is safe.
   - For `__ABSENT__`: "no server named `<INNGEST_HOST>` in the Hetzner project this token is scoped
     to: a replace in flight, or a token for another project".

### 2. Decoder: `_hcloud_created_epoch <json> <name>` (pure)

- `[.servers[]? | select(.name == $name)]`, run as a client-side exact match even though the query
  already filters.
- 0 matches: `__ABSENT__`. More than 1, non-JSON or non-object: `__UNREADABLE__`.
- `created` is normalized from `+00:00` to `Z` and parsed with `fromdateiso8601`. The result must
  be decimal, otherwise `__UNREADABLE__`.
- Every `jq` call here gets `2>/dev/null`: jq's error text quotes the input it chokes on.

### 3. Row filter: `_current_instance_row_counts <floor_epoch_s>` (pure)

It reads raw Better Stack rows on stdin and prints ONE line of five integers:
`<counted> <host_pair> <pre_floor> <malformed> <skew_suspect>`.

- It decodes `.raw` and keeps the host pair (`host == $INNGEST_HOST and host_name ==
  $INNGEST_HOST_NAME`).
- **counted** requires BOTH of these:
  - the row's own event time, `__REALTIME_TIMESTAMP` (a decimal string, µs), is `≥ floor × 10^6`;
  - Better Stack's ingest time is `≥ floor`: `dt` with fractional seconds stripped, then
    `strptime("%Y-%m-%d %H:%M:%S") | mktime`. That form was verified on jq 1.8.2, giving UTC.

  Both clocks must be wrong before a predecessor row can pass:
  - A destroyed host cannot be ingested after its destruction. That is the AP-027 `dt` anchor used
    by `scripts/lib/git-data-boot-signal-poll.sh`.
  - A predecessor's event time cannot follow `created` unless its clock ran ahead.
- **malformed:** host-pair rows with a missing or non-decimal `__REALTIME_TIMESTAMP` or an
  unparseable `dt`. They are excluded, never defaulted.
- **pre_floor:** host-pair rows that are well-formed but fail either conjunct.
- **skew_suspect:** pre-floor rows whose `dt ≥ floor` but whose event time is `< floor`. A destroyed
  predecessor cannot produce one, so a non-zero value points at the CURRENT server's clock running
  behind.
- The floor is passed with `--argjson` only after a `^[0-9]+$` check.

### 4. Readers

`_flip_liveness_count` and `_luks_liveness_count` keep their no-argument signature and their
`rows=$(_bs_query_rows "$…" <tag> 50)` line, which the `FLQ_*` pins check. Each reader:

1. Calls the anchor. If the result is not `^[0-9]+$`, the reader prints `__UNREADABLE__` and returns
   0. The anchor's warning has already named the cause, and the Better Stack read is skipped.
2. Reads the rows exactly as it does today.
3. Pipes the rows through the filter. The first integer is the stdout token. A non-decimal token
   becomes `__UNREADABLE__`.
4. Prints one `::notice::` on stderr, built from validated values only: the name from
   `$INNGEST_HOST`, the ISO time from `date -u -d "@$epoch"` (run only after the decimal check), and
   the age as a computed integer. No string from the API response ever reaches an annotation.

   ```text
   liveness scoped to server <name> created <iso> (<age>s ago): counted=<C> host_pair=<N> pre_floor=<P> malformed=<M> skew_suspect=<K>
   ```

5. When `counted == 0` and `age < 600`, also prints a `::warning::` on stderr:

   ```text
   server <name> was created <age>s ago and has not shipped a row yet — WAIT and re-dispatch; do NOT replace it (a replace resets this clock)
   ```

   Measured: the first row came 145 s after `created`, and the #8741 Vector-download retry can take
   longer.

### 5. Refusal text: the arms stay, only the words change

- **`unreadable` at resume G3 and LUKS G3.** Today these point only at `BETTERSTACK_QUERY_*`. They
  become "the ::warning:: above names which read path failed (Better Stack credentials, or the
  Hetzner anchor)". That is arm G3.7's existing wording.
- **`silent` at resume G3.** The existing advice, "If the host is genuinely gone, the path forward is
  an inngest-host-replace", becomes conditional: "only if the anchor ::notice:: above shows the
  server is more than 10 min old AND counted=0; a younger server has simply not shipped yet". This
  stops the refusal from recommending destroying a healthy replacement, which would reset `created`
  and loop.
- **All reworded messages** pass `scripts/lint-diagnosis-claims.sh` (AP-021: a message names only a
  measured cause). The baseline is 1 unmeasured claim and must not grow.

### 6. Explicitly NOT floored

- **`_flush_latch_count`** (op=arm G3.7's L). The latch lives on `/mnt/data`, which survives the
  replace, so a predecessor's `flip-complete` row is valid PRESENCE evidence. Flooring L would be a
  fail-open.
- **`confirm_flip_state` and `confirm_luks_state`.** Each is anchored on this dispatch's own write
  instant, and each is the only polling loop, so the Hetzner read never sits in a loop.
- **The execute 2.0 and registry-probe gates.** They are already boot-joined via
  `tests/scripts/lib/inngest-host-dark-gate.sh`.

### Why this anchor, and why the invariant holds

- **Destroy-before-create is forced.** Hetzner names are unique per project, and
  `hcloud_server.inngest` has no `create_before_destroy`. Verified: `inngest-host.tf` has `name =
  "soleur-inngest"`, and its lifecycle block is `ignore_changes = [ssh_keys]` only. Pinned in the
  suite.
- **A new server cannot ship a predecessor's journal.** Checked in review:
  - `cloud-init-inngest.yml` sets no journald `Storage=`.
  - Neither `/var/log/journal` nor `/var/lib/vector` lives on `/mnt/data`.
  - `vector.toml` reads `/var/log/journal` with the default `current_boot_only`.
  - Pinned: `vector.toml` never sets `current_boot_only = false`.
- **No Hetzner `rebuild` of the inngest server exists in the repo.** A rebuild keeps `created` while
  reinstalling, which is the one path that would defeat the floor. Pinned: no `actions/rebuild`
  under `scripts/` or `.github/`.
- **In-place changes keep the same generation.** A reboot or an in-place `server_type` change keeps
  `created`, and that is correct: G3 asks whether the server that exists can act on the write.
- **Why the row's event time plus `dt`, not the boot instant.** The first draft used `REALTIME −
  MONOTONIC`. Event time plus `dt` needs no subtraction and widens the skew margin from ~18 s
  (created → boot) to ~145 s (created → first row). Adding `dt` closes the "predecessor clock ahead"
  direction the architecture review raised.
- **Why not `--since` on `dt` alone, server-side** (the AP-027 precedent's shape). The suite could
  then only inspect argv and never run the predicate, and the change would move the pinned
  `FLIP_LIVENESS_SINCE` literal. Filtering client-side on `dt` keeps the precedent's clock with the
  suite's executability.

### Why op=arm G3.7 H is floored too (review disagreement, resolved technically)

One reviewer argued H should stay unfloored, for parity with L. The parity does not hold, because
the two signals answer different questions:

- **L** asks whether there is PRESENCE evidence of a flush. Rows from any server generation on this
  volume answer that.
- **H** exists because L = 0 is an ABSENCE, and a silent host manufactures absences for free
  (#7674). H must show that the generation that could have flushed *unseen* is audible, and that is
  the current one.

Consider a replacement that flipped while its Vector was down (the #8741 state). L reads 0, and an
unfloored H counts the predecessor and reports `clear`: that is #7674 reopened by a replace.
Flooring can only ADD refusals. This is recorded in `decision-challenges.md` DC-1.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-225 §4** ("The writer gates on the host being AUDIBLE, on that operation's own tag") via
`soleur:architecture`. Add a dated amendment paragraph covering four points:

1. "Audible" means recent rows under the unit's own tag **from the current server generation**
   (AP-027). A predecessor with the same name does not count.
2. The generation is identified by the Hetzner API's `created` for the server named
   `$INNGEST_HOST`, the one authority independent of the host's own telemetry. The API read happens
   at gate time.
3. An anchor read that fails is `unreadable` and fails closed, like a Better Stack read failure.
4. The read uses the Tier-A token (ADR-241 D4), with the documented fallback until O10.

Add the rejected alternatives to its `## Alternatives considered`: the identity-only filter, the
boot/machine pin and the freshness bound. Cite **ADR-199's** G3 wall-clock paragraph as unchanged.
Also cite AP-027 (ADR-149) in the amendment and in the reader comment.

### C4 views

All three model files were read (`diagrams/model.c4`, `views.c4`, `spec.c4`).

- **External systems.** Checked: Better Stack (`inngest -> betterstack`, `github -> betterstack`
  exist), GitHub (`github`), Hetzner (`hetzner` container "Compute") and Doppler (`github ->
  doppler`).
- **Missing edge.** No `github -> hetzner` edge exists for CI's **Hetzner Cloud API** reads, which
  already happen (op=backup's `create_image`; `workspaces-luks-cutover.yml`'s volume lookup) and
  which this plan adds to three more ops.
- **Task.** Add one `github -> hetzner` relationship describing CI's Hetzner Cloud API calls:
  - Tier-A read GETs: the G3 generation anchor and the LUKS volume-id lookup, on
    `HCLOUD_TOKEN_READONLY` with the Tier-B fallback until ADR-241 O10;
  - op=backup's `create_image` write, which #8767 tracks.

  Include it in the view that already renders `github` and `hetzner` together, if one does.
- **No new actor, container or data store.** The access relationship is unchanged: the operator
  dispatches the op behind the `inngest-cutover` environment reviewer, as today.
- **Validation.** `apps/web-platform/test/c4-code-syntax.test.ts`,
  `apps/web-platform/test/c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The amendment is true at merge. Nothing is soak-gated.

## Technical Considerations

- **Strict mode.** The script runs `set -euo pipefail` without `inherit_errexit` (verified).
  - Every new function uses `local x="${1:-}"`.
  - Every I/O function ends in `return 0`.
  - `set -e` does not stop a failure inside a `$(…)`, so every output that crosses one is
    shape-checked with `^[0-9]+$` before it is used.
- **No new `case` arms in the `arm)` block.** The existing pin, "arm) no G3.7 outcome arm carries
  its own exit", stays true because no call site changes.
- **Extraction contract.**
  - Signature and closing brace sit at column 0, with no column-0 `}` inside a body, including
    multi-line jq programs.
  - Nothing new sits inside a case arm. The awk range ends at the first line of 14 spaces followed
    by `;;`.
- **Call sites and existing pins are unchanged.** Verified: exactly one each of
  `RS_LIVE_N="$(_flip_liveness_count)"`, `FLIP_LIVENESS_N="$(_flip_liveness_count)"` and
  `LK_LIVE_N="$(_luks_liveness_count)"`. The pins `FLQ_SITES == 8`, `FLQ_FLIP_SITES == 2`,
  `FLQ_LUKS_SITES == 2`, `RSL_RD < RSL_WR`, `FLV_SITES == 1`, `LK_G3TAG` and the
  `FLIP_LIVENESS_SINCE="15m"` literal all hold. No existing assertion pins the wording being
  changed (verified).
- **Keep new message text away from negative pins.**
  - No literal `inngest-cutover-flip` in the LUKS block.
  - No `flush_latch_decide` in the resume block.
  - New `G3 REFUSING` text stays above the LUKS write (`LK_LASTG3_LN`).
- **The workflow YAML is unchanged.** `DOPPLER_TOKEN` (prd_terraform) is mapped unconditionally for
  every op (verified, `cutover-inngest.yml` "REQUIRED BY EVERY OP"). `HCLOUD_TOKEN_READONLY`, once
  provisioned, is read through it with no new env mapping.
- **Avoid L50–L90** of the script, where draft PR #8690 edits the header comment.
- **jq in CI.** Add a suite self-check row: `"2026-09-24T18:57:33Z" | fromdateiso8601 == 1790276253`
  and `"2026-09-24 19:08:26.1" | sub(…) | strptime(…) | mktime == 1790276906`. If the runner's jq
  differs, this row fails first, before any gate row.
- **Cost.** One Hetzner GET per liveness read, which is one per dispatch at each gate.
- **Out of scope, noted by security review.** `DOPPLER_TOKEN` (which can read the Hetzner token) is
  mapped for every op and every dispatching branch, and the environment reviewer gates only five
  ops. A main-only branch rule on the `inngest-cutover` environment is worth a separate check.

## Implementation Phases

### Phase 1 — RED: reproduce the stale-predecessor pass (tests only, one commit)

In `apps/web-platform/infra/cutover-inngest-workflow.test.sh` §(b2):

1. **Fixtures at top level.** Define every fixture row as a top-level variable that both the mock
   and the self-checks read.
   - The mocked `created` is a synthetic `+00:00` string. The floor is derived from it once, never
     written twice as a literal.
   - Every existing row (`rows`, `foreign`, `spoofed`) gets `__REALTIME_TIMESTAMP` and `dt` AFTER
     `created`. That keeps their `0`s attributable to the #6616 host conjunct.
2. **Mocks.**
   - `doppler()` branches on its ARGUMENTS first. `secrets get HCLOUD_TOKEN_READONLY` and
     `secrets get HCLOUD_TOKEN` return synthetic sentinels per mode. `run … betterstack-query.sh`
     returns the mode's rows.
   - A mocked `curl()` writes argv, stdin and exit info to per-call files, truncated before each
     call. It returns the real Hetzner list shape with `\n<code>` appended, as `-w '\n%{http_code}'`
     does.
   - Better Stack argv and HCLOUD reads are recorded in separate files.
   - A `curl` stub that `exit 99`s is defined in EVERY harness, including `call_flush_latch_count`,
     so no mutant can reach the real api.hetzner.cloud.
3. **Mode `predecessor`.** Two host-pair rows whose event time AND `dt` are BEFORE `created` (the
   2026-09-24 shape). Assert `'0'`.
4. **Bump `_EXACT_FLOOR` in the same commit** so that `predecessor` is the only red row (it reads `2`
   on today's code). Quote that FAIL line in the PR body (`cq-write-failing-tests-before`).

### Phase 2 — decoder, anchor, filter, readers (GREEN)

In `scripts/cutover-inngest.sh`, beside the liveness readers (~L355–440):

1. Add `_hcloud_created_epoch`, `_inngest_server_created_epoch` and `_current_instance_row_counts`,
   with a rationale block covering:
   - the measured timeline;
   - AP-027;
   - the three pinned invariants;
   - event time plus `dt`;
   - why L, the confirm readers and 2.0 are exempt;
   - why H is floored.
2. Rewrite both readers per §4.
3. **Harness.** Awk-extract and eval the three new functions in `call_flip_liveness_count`, with a
   non-vacuity assert for each. Without them every mode reads `__UNREADABLE__` through "command not
   found".

### Phase 3 — wording, full coverage, ADR/C4, runbook

1. Reword the `unreadable` and `silent` arms per §5, then run `scripts/lint-diagnosis-claims.sh`.
2. Add every Guard 1–3 row and every AC row below, including:
   - a `call_luks_liveness_count` harness;
   - a stderr capture for notice, warning and mask rows;
   - the three invariant pins;
   - the jq self-check.
3. Set `_EXACT_FLOOR` to the measured dispatched count, and update its arithmetic comment.
4. Write the ADR-225 §4 amendment and the C4 `github -> hetzner` edge, then run the three C4 tests.
5. Update `knowledge-base/engineering/operations/runbooks/inngest-server.md` §op=resume "G3 is a live
   precondition" to cover:
   - the generation scope;
   - the notice breakdown and how to read each field;
   - the young-server "wait, do not replace" warning;
   - the anchor warning classes.
6. `shellcheck -S warning scripts/cutover-inngest.sh` must report no findings beyond the 3
   pre-existing ones.

### Phase 4 — read-only live replay (verification, no dispatch)

Run the extracted `_current_instance_row_counts` over one real row set,
`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 18h --grep '"reason":"noop-' --limit 5000`,
twice:

- floor `0`;
- floor = the current server's `created`, read through the new anchor function.

Record both 5-integer lines in the PR body. The drop between them is the predecessor, and `malformed`
and `skew_suspect` should be 0 in both. This reproduces the predecessor while the 2026-09-24 rows
remain in the window.

## Files to Edit

- `scripts/cutover-inngest.sh`: three new functions, two reader bodies, and the reworded
  `unreadable`/`silent` text at resume G3 and LUKS G3.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: mocks, fixtures, the RED row, full
  coverage, the pins and `_EXACT_FLOOR`.
- `knowledge-base/engineering/architecture/decisions/ADR-225-per-operation-latched-flags-are-the-control-channel-for-a-host-with-no-inbound-path.md`:
  the §4 amendment and its alternatives.
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` if needed): the
  `github -> hetzner` Cloud API edge.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the op=resume G3 paragraph.

## Files to Create

None.

## Open Code-Review Overlap

None. The bodies of `gh issue list --label code-review --state open` were checked for
`scripts/cutover-inngest.sh`, `cutover-inngest-workflow.test.sh`, `_flip_liveness_count` and
`resume_liveness_decide`, and none matched. (The new #8767 is `deferred-scope-out`, not
`code-review`. Its disposition here is **acknowledge**: a different op, and this plan does not copy
its pattern.)

## Non-Goals

- Changing what G3 means (deliverability) or its 15 m window.
- Flooring `_flush_latch_count` (a fail-open), the confirm readers or the boot-joined 2.0 gates.
- Closing the seconds-wide race between G3's read and the write when a replace lands in that gap.
  `cutover-inngest.yml` shares no concurrency group with the replace workflow, so no in-script check
  closes it. A new server cannot ship within seconds, and the flag waits for the next host's timer
  regardless.
- op=backup's token handling, tracked in **#8767**.
- #8714 and #8747 (context only).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Identity filter only (tighten `host`/`host_name`) | Identical across a replace (measured). That is the defect. AP-027. |
| Boot-instant floor (`REALTIME − MONOTONIC ≥ created`) | ~8× smaller skew margin, and one more field. It was the first draft. |
| `dt`-only floor, server-side `--since max(now−15m, created)` (the AP-027 precedent's shape) | The suite could only check argv, and the pinned `FLIP_LIVENESS_SINCE` literal would move. The plan keeps `dt` as a client-side conjunct instead. |
| Pin `_MACHINE_ID`/`_BOOT_ID` of the newest rows | In the failure window the newest rows ARE the predecessor's. Circular. |
| Join through the probe row's `instance_id=hetzner-<id>` | Still needs the Hetzner read, and depends on an hourly or at-boot row. |
| Freshness bound on the newest row | A heuristic with nothing authoritative behind it. |
| Re-read the anchor after the count (`changed` outcome) | Shrinks a race without closing it. Cut in review. |
| Anchor read per call site, plus a decider and a refusal helper | More wiring, and two more functions. Putting the anchor inside the readers covers every site by construction. |
| Fix op=resume only | The shared reader would mean two things. LUKS G3 and arm G3.7 H carry the same fail-open. |
| `curl --retry` / `-f` | `--retry`: the #6500 sharp edge. `-f`: hides 401 vs 429 vs 5xx. The plan uses an explicit `-w '%{http_code}'` instead. |
| Tier-B `HCLOUD_TOKEN` only | Breaks at ADR-241 O10, and contradicts the #8209 tier map. The plan reads the read-only name first. |

## Guard Contract

### Guard 1 — generation-scoped liveness count

**Property.** Every liveness count consumed by a write-gating decision counts only host-pair rows
that satisfy both of the following. An unobtainable or out-of-bounds anchor, or any malformed row
field, never widens the count.

- the row's own event time is at or after the current Hetzner server's `created`;
- Better Stack ingested the row at or after that same instant.

**Assembly.** One chokepoint, its two callers, the members left out on purpose, and the invariants
the predicate depends on:

- **Chokepoint.** `_current_instance_row_counts`. The row predicate lives only there.
- **Callers.** The two liveness readers:
  - `_flip_liveness_count`, consumed by `arm)` G3.7 `FLIP_LIVENESS_N=` and by `resume)` G3
    `RS_LIVE_N=`;
  - `_luks_liveness_count`, consumed by `luks-cutover|luks-rollback)` G3 `LK_LIVE_N=`.
- **Outside the assembly on purpose, each pinned or executed so it stays outside:**
  - `_flush_latch_count`;
  - the confirm readers;
  - the 2.0 and registry-probe gates.
- **Invariants the predicate depends on (all pinned):**
  - no `create_before_destroy` on `hcloud_server.inngest`;
  - no `current_boot_only = false` in `vector.toml`;
  - no `actions/rebuild` of the inngest server.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the event-time conjunct | RED: `late-ingest` (event time < created, `dt` ≥ created) expects `0`, and its notice breakdown expects `skew_suspect=2` |
| 2 | Delete the `dt` conjunct | RED: `clock-ahead-predecessor` (event time ≥ created, `dt` < created) expects `0` |
| 3 | Default a missing timestamp to the widening value (`// (now*1e6\|floor\|tostring)`) | RED: `no-ts` expects `0`, and `no-ts+2current` expects `2` (one malformed row must not abort the whole count either) |
| 4 | Second member after a compliant first: `mixed` in both orders (predecessor then current, and current then predecessor), with the filter mutated to judge only the first row | RED: both orders expect `2` |
| 5 | Hard-code the floor instead of reading the anchor | RED: `anchor-late` (the same current rows, mocked `created` set after them) expects `0` while `current` expects `2` |
| 6 | Treat `__ABSENT__`/`__UNREADABLE__`/an out-of-bounds epoch as floor `0` | RED: every `anchor-*` mode plus `epoch-pre-2025` and `epoch-future` expect `__UNREADABLE__`, and the Better Stack argv file stays empty (the read was skipped) |
| 7 | `_luks_liveness_count` keeps its old inline jq | RED: executed LUKS `predecessor` expects `0` |
| 8 | Floor `_flush_latch_count` | RED: executed latch row with pre-floor `flip-complete` rows expects `2` (the curl stub would `exit 99` if the latch reached Hetzner) |
| 9 | Add `create_before_destroy`, `current_boot_only = false`, or an `actions/rebuild` call | RED: invariant pins |
| H1 (harness) | Give `spoofed`/`foreign` pre-floor timestamps | RED: fixture self-check over the SAME top-level fixture variables. It asserts the number of rows checked is 2 (not vacuous) and that all are ≥ the floor |
| H2 (must-PASS, non-canonical) | A current row with reordered keys, extra journald fields, event time exactly `created×10^6` and `dt` exactly `created` | PASS: counted. Its sibling at `created×10^6 − 1` → `0` |

### Guard 2 — server anchor

**Property.** The floor comes only from exactly one Hetzner server whose `name` equals
`$INNGEST_HOST`, with a `created` that parses and falls within bounds. Every other outcome yields a
named `::warning::` and a non-epoch token, returns 0, and writes nothing to stdout except the token.
The token appears only on curl's stdin and on one stderr `::add-mask::` line. No response-body byte
ever reaches stdout or stderr.

**Assembly.** The pure `_hcloud_created_epoch` is the chokepoint. `_inngest_server_created_epoch`
is its only I/O wrapper, and its only consumers are the two Guard-1 readers.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Take `.servers[0]` instead of requiring exactly one name match | RED: the two-server fixture expects `__UNREADABLE__` |
| 2 | Second member after a compliant first: body `[{name:"soleur-inngest-old"}, {name:"soleur-inngest"}]` | Must-PASS: returns the matching epoch |
| 3 | Parse only the `Z` form | RED: the `+00:00` fixture expects an epoch |
| 4 | Put the token on argv | RED: the token sentinel is absent from the recorded argv, present on stdin, and appears on stderr exactly once, as `::add-mask::<sentinel>` |
| 5 | Echo or leak body bytes (a `-S` error, an unsuppressed jq error, a debug echo) | RED: a body sentinel in each of `BODYSENTINEL` (non-JSON, 200), `{"servers":[],"x":"BODYSENTINEL"}`, `{"servers":"BODYSENTINEL"}`, `created:"BODYSENTINEL"` and a 503 body never appears on stdout or stderr |
| 6 | Collapse HTTP classes (e.g. restore `-f`) | RED: 401, 429 and 503 each expect their own warning class, and none yields `__ABSENT__` |
| 7 | Drop the read-only-first order | RED: with both names set, the recorded HCLOUD read order starts with `HCLOUD_TOKEN_READONLY`, and curl's stdin carries the read-only sentinel |
| 8 | Return non-zero on failure | RED: inside a `set -e` subshell, `x="$(_inngest_server_created_epoch)"; echo reached` prints `reached` for every failure mode |
| 9 | Remove the transport arguments | RED: argv pins `--proto =https`, `--max-time`, `-H @-`, `--data-urlencode name=soleur-inngest`, and the absence of `--retry` and `-f` |

### Guard 3 — the reader's operator-facing output

**Property.** Every reader outcome prints exactly one token on stdout. Its diagnostics sit on
stderr: the breakdown notice, the young-server warning and the anchor warnings. They are built
only from validated integers and `$INNGEST_HOST`, and none of them names a cause the counts did not
measure.

**Assembly.** Only the two readers' stderr emission sites are in scope. The call-site refusal arms
keep their existing single-exit shape. Only the wording of their `unreadable`/`silent` arms changes,
and `scripts/lint-diagnosis-claims.sh` covers that wording.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Print the notice on stdout | RED: the stdout token is not `^[0-9]+$` in the `current` mode |
| 2 | Omit the young-server warning when `counted==0` and age < 600 | RED: `predecessor` with a mocked young `created` expects the `WAIT … do NOT replace` warning on stderr |
| 3 | Emit that warning for an old server | RED: `predecessor` with a mocked old `created` expects NO such warning |
| 4 | Interpolate a response string into the notice | RED: a server fixture whose `created` carries a trailing `\n::error::FORGED` expects decoding to fail (`__UNREADABLE__`), and `::error::FORGED` never appears |
| 5 | Leave the resume `silent` text's replace advice unconditional | RED: grep pin over `RESUME_FILE`, requiring the replace advice to sit in the same sentence as the age condition |

## Observability

```yaml
liveness_signal:
  what: "the conclusion of the latest cutover-inngest.yml run (success = the gate passed and the write landed; failure = a gate refused), plus the reader's anchor ::notice:: (server, created, age, counted/host_pair/pre_floor/malformed/skew_suspect) and the G3 / G3.7 annotation"
  cadence: "per dispatch of op=resume / op=arm / op=luks-cutover / op=luks-rollback"
  alert_target: "the dispatching engineer via the red workflow run (GitHub Actions failure notification); every one of these ops is environment-gated, so a reviewer watches each run"
  configured_in: "scripts/cutover-inngest.sh _flip_liveness_count / _luks_liveness_count (notice + warnings) and _inngest_server_created_epoch (anchor warnings); the resume) G3, arm) G3.7, luks-cutover|luks-rollback) G3 refusal arms"
error_reporting:
  destination: "GitHub Actions ::warning:: / ::error:: annotations plus a failed job on cutover-inngest.yml (layer 6: workflow run log)"
  fail_loud: "anchor ::warning:: naming the class (token empty / HTTP 401-403 token rejected / 429 rate-limited / 5xx Hetzner outage / curl rc class / no server by that name in the token's project / out-of-bounds created), then the gate's unreadable ::error::; or a notice breakdown plus the young-server 'WAIT, do NOT replace' warning, then the silent ::error::"
failure_modes:
  - mode: "replacement server not shipping yet; only predecessor rows in the 15m window (the 2026-09-24 shape)"
    detection: "notice counted=0 pre_floor>0 with age < 600s, the young-server ::warning::, then the G3 silent ::error:: before any write (layer 6, workflow run log)"
    alert_route: "red cutover-inngest.yml run, seen by the dispatcher and the environment reviewer"
  - mode: "replacement server up for many minutes but not shipping (Vector down, #8741 class)"
    detection: "notice counted=0 with age >= 600s, then the G3 silent ::error:: whose replace advice now applies (layer 6)"
    alert_route: "red cutover-inngest.yml run"
  - mode: "current server's clock running behind (its own rows excluded)"
    detection: "notice skew_suspect>0 (rows ingested after created but stamped before it), then G3 silent (layer 6)"
    alert_route: "red cutover-inngest.yml run"
  - mode: "Vector/warehouse schema change drops __REALTIME_TIMESTAMP or dt"
    detection: "notice malformed>0 with counted=0 and host_pair>0 (layer 6)"
    alert_route: "red cutover-inngest.yml run"
  - mode: "Hetzner API unreadable, token unresolved, or no server by that name (replace in flight / wrong-project token)"
    detection: "anchor ::warning:: naming the class, then the gate's unreadable ::error:: before any write (layer 6)"
    alert_route: "red cutover-inngest.yml run"
logs:
  where: "the anchor/notice/warning outcomes exist ONLY in the GitHub Actions log of cutover-inngest.yml (layer 6); the host rows they count live in Better Stack Logs source 2457081 (read via scripts/betterstack-query.sh)"
  retention: "GitHub Actions log retention for the repo (90 days default); Better Stack per the source's plan retention"
discoverability_test:
  command: "curl -s --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/cutover-inngest.yml/runs?per_page=1"
  expected_output: "conclusion"
  # Unauthenticated on a public repo (verified 2026-09-24, twice: HTTP 200, key present). No shell
  # metacharacters, so the Check 10 shell-active reject passes; first token `curl` passes the verb gate.
  # It proves the run log is reachable, not that the new notice appears.
```

## Encryption Posture

No new persistent store. One new *call path* reuses a connection op=backup already makes:
GitHub-hosted runner → Hetzner Cloud API. It is now also reached from op=resume, op=arm and
op=luks-*.

```yaml
at_rest: []   # no store introduced; the anchor is read into a shell variable and discarded
in_transit:
  - connection: "cutover-inngest.yml runner (scripts/cutover-inngest.sh _inngest_server_created_epoch) -> https://api.hetzner.cloud/v1/servers"
    enforced_at: "scripts/cutover-inngest.sh _inngest_server_created_epoch — curl --proto =https (refuses any non-HTTPS scheme, including a redirect downgrade) with curl's default certificate verification (no -k / --insecure; --disable ignores any .curlrc that could add one)"
    tls: "HTTPS, TLS 1.2+ negotiated by the runner's curl/OpenSSL"
    cert_verification: on
    does_not_defend: "a leaked HCLOUD_TOKEN (read/write over every server and volume in the project) — TLS protects it on the wire only; exposure in the run log is prevented separately by stdin header delivery and never echoing (Guard 2 rows 4-5), not by TLS"
    disclosed_as: not-publicly-claimed
```

## User-Brand Impact

- **If this lands broken, the user experiences:** after an inngest host replace, production cron
  and reminder scheduling stays down longer, in one of two ways:
  - **False refusal.** op=resume refuses a recovery that would have worked, because the Hetzner
    read failed or the current server's clock runs behind. The run log names the cause, and
    re-dispatch is safe.
  - **Fail-open.** Behavior regresses to today's, and G3 passes on predecessor rows.
- **If this leaks, the user's data / workflow is exposed via:** the Hetzner project token
  (read/write over every server and volume). The exposure would come from echoing it, putting it on
  argv, leaving it unmasked, or letting the API body leak into this public repository's run log. The
  plan reads the Tier-A read-only name first, masks the token on stderr, feeds it on stdin, discards
  curl and jq stderr, and never prints a response byte. Guard 2 rows 4, 5 and 9 test each of these.
- **Brand-survival threshold:** `aggregate pattern`. The failure is a scheduling-recovery delay that
  affects all users together. The token is already read by this workflow (op=backup, tracked in
  #8767), so this adds read sites with stricter handling, not a new credential class.

## Acceptance Criteria

- [ ] AC1 (RED first): the first commit changes only `cutover-inngest-workflow.test.sh`, including
  the `_EXACT_FLOOR` bump. The suite reports exactly one FAIL, the `predecessor` row, which reads
  `2`. The PR body quotes that line.
- [ ] AC2: every Guard 1 row has an executed assertion that goes RED under its mutation. The modes
  are `predecessor`, `current`, `mixed` (both orders), `no-ts`, `no-ts+2current`, `late-ingest`,
  `clock-ahead-predecessor`, `anchor-late`, `anchor-*`, `epoch-pre-2025`, `epoch-future`, the
  boundary pair, LUKS `predecessor`/`current`, and the latch row. Under an anchor failure the Better
  Stack read is skipped (its argv file is empty).
- [ ] AC3: `foreign` and `spoofed` still read `0`, and the H1 self-check proves both of their
  timestamps are ≥ the floor. The self-check reads the same top-level fixture variables and asserts
  that 2 rows were checked.
- [ ] AC4: the `_hcloud_created_epoch` decode table covers `Z`, `+00:00`, 0 matches, 2 matches,
  non-matching-first, missing or garbage `created`, non-JSON, `{"servers":"…"}` and empty input. A
  dispatch counter confirms every case ran.
- [ ] AC5: every Guard 2 row holds.
  - The token appears only on the recorded curl stdin and on exactly one stderr
    `::add-mask::<sentinel>` line.
  - Body sentinels in 200-non-decodable and 503 replies never reach stdout or stderr.
  - The warnings for 401, 429 and 503 differ, and none is `__ABSENT__`.
  - The read-only-first order holds, and the fallback applies when only `HCLOUD_TOKEN` is set.
  - With both names empty, the result is `__UNREADABLE__` and curl is never called.
  - The wrapper returns 0 in every mode.
  - The transport argv pins hold.
- [ ] AC6: every Guard 3 row holds.
  - The stdout token is `^[0-9]+$` or `__UNREADABLE__`.
  - The notice carries all five counters and the age, matched as `[0-9]+s ago`.
  - The young-server warning appears only when the server is young and nothing was counted.
  - An anchor failure's stderr never contains `BETTERSTACK_QUERY`.
- [ ] AC7: the invariant and exemption pins hold:
  - no `create_before_destroy` on `hcloud_server.inngest`;
  - no `current_boot_only = false` in `vector.toml`;
  - no `actions/rebuild` for the inngest server under `scripts/` or `.github/`;
  - an executed, unfloored `_flush_latch_count` row.
- [ ] AC8: these existing pins stay green UNMODIFIED:
  - `FLQ_SITES == 8`, `FLQ_FLIP_SITES == 2`, `FLQ_LUKS_SITES == 2`;
  - `RS_LIVE_N="$(_flip_liveness_count)"` and `RSL_RD < RSL_WR`;
  - `FLV_SITES == 1`;
  - "arm) no G3.7 outcome arm carries its own exit";
  - `LK_G3TAG`;
  - the `FLIP_LIVENESS_SINCE="15m"` literal pins.

  The test-file diff adds rows and changes fixtures. It deletes no existing assertion.
- [ ] AC9: all of these pass:
  - `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0, with `_EXACT_FLOOR`
    equal to the dispatched count;
  - `shellcheck -S warning scripts/cutover-inngest.sh` reports only the 3 pre-existing findings;
  - `bash scripts/lint-diagnosis-claims.sh` reports no more than its baseline of 1;
  - the jq self-check row passes.
- [ ] AC10: the Phase 4 read-only replay is recorded in the PR body. It shows two 5-integer lines
  over one identical row set, with floor `0` and with floor `created`. The floored `counted` is
  strictly smaller while the 2026-09-24 rows remain in the window, and `malformed` and
  `skew_suspect` are 0.
- [ ] AC11: the workflow YAML gains no knob that could weaken the floor:
  `! grep -qE 'INNGEST_HOST|FLOOR|SKEW|HCLOUD' .github/workflows/cutover-inngest.yml`, excluding
  comment lines.
- [ ] AC12: the runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`) covers
  the generation scope, how to read the notice fields, the young-server "wait, do not replace"
  warning and the anchor warning classes. It no longer says a freshly replaced host makes G3 refuse.
- [ ] AC13: the ADR-225 §4 amendment exists, cites AP-027 and ADR-241 D4, and lists the rejected
  alternatives. `model.c4` carries a `github -> hetzner` Cloud API edge. `c4-code-syntax`,
  `c4-render` and `c4-count-parity` all pass.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: a gate predicate
inside an ops script, its test suite, one ADR amendment, one C4 edge and one runbook paragraph.
There is no user-facing surface, no new vendor and no new data processing. Hetzner and Better Stack
are existing processors that this workflow already reads.

## Test Scenarios

- **Predecessor rows only.** Given host-pair rows in the window whose event time and `dt` both
  predate the current server's `created`, when op=resume's G3 counts them, then:
  - the count is `0`;
  - the notice shows `pre_floor>0` and the age;
  - a young server gets the "WAIT, do NOT replace" warning;
  - G3 refuses `silent` before the write.
- **Current rows.** Given rows from the current server, then G3 passes `audible`.
- **Late ingest.** Given rows ingested after `created` but stamped before it, then they are not
  counted, and the notice shows `skew_suspect>0`.
- **Hetzner errors.** Given the Hetzner API returns 401, 429 or 503, times out, or returns non-JSON,
  then:
  - the reader prints a class-specific `::warning::`, then `__UNREADABLE__`;
  - the resume refusal points at that warning;
  - no response byte and no token byte is printed;
  - nothing is written.
- **No server.** Given no server named `soleur-inngest`, then the warning names the queried name and
  the token's project, and the gate refuses `unreadable`.
- **Arm and LUKS.** Given the same predecessor-only rows, op=arm G3.7 gives H = `0`, so
  `flush_latch_decide` returns `silent`, and op=luks-cutover G3 refuses `silent`.
- **Latch unaffected.** Given a predecessor `flip-complete` row within 365 d, op=arm's L still
  counts it, and G3.7 returns `latched`.
- **Live replay (read-only).** Phase 4 prints two 5-integer lines, and the floored one is smaller.

## Plan Review Revisions

The eng panel reviewed the plan (DHH, Kieran, code-simplicity), plus a CTO devex lens. Applied as
Mechanical:

- **Floor on `__REALTIME_TIMESTAMP`, not the boot instant** (CTO, simplicity, DHH). Same result
  under the now-pinned destroy-before-create invariant. One field instead of two, and an ~8× wider
  skew margin.
- **Cut the post-count anchor re-read and the `changed` outcome** (DHH P0, simplicity, CTO). It
  shrank a race it could not close. Moved to Non-Goals.
- **Anchor moved inside the two readers. Cut `instance_anchor_decide` and `_instance_anchor_refusal`**
  (simplicity, DHH). This resolved four of Kieran's P1s by construction: no call-site change, so
  the resume pins, the arm exit pin, the case-arm shape and the Guard-3 wiring are untouched. The
  anchor wrapper always returns 0 (Kieran P1-4).
- **One count, not current plus predecessor. Cut the predecessor notice** (simplicity). The anchor
  notice with the server's age tells "wait" from "investigate" (CTO rec 1).
- **The harness must eval the new functions and mock curl and the HCLOUD read** (Kieran P1-3). Add
  a `call_luks_liveness_count` harness, and capture stderr for the notice and warning rows (Kieran
  P2-1).
- **Bump `_EXACT_FLOOR` in the RED commit** so the RED is isolated (Kieran P2-6).
- **`absent` warning names the queried name and the token's project** (CTO rec 2).
- **No `--retry`** (CTO suggested it; declined per the #6500 sharp edge). The warning says
  re-dispatch is safe instead.
- **Pin the `create_before_destroy` absence** (simplicity, hidden assumption).
- **Dropped:** the name-regex validation (`INNGEST_HOST` is never workflow-mapped), the dispatch
  floor rows and the grep-pin for "every `*_liveness_count` calls the helper". The executed LUKS
  case covers the last one.

**Disagreement resolved technically, not deferred:** whether op=arm G3.7 H should be floored. DHH
said no; the CTO and simplicity panels said yes. It stays floored, per §Why op=arm G3.7 H is
floored too. Recorded in `decision-challenges.md` for visibility.

## Risks & Sharp Edges

- **Fakes must replay the real contracts.**
  - `curl` without `-f` returns rc 0 and the body, followed by `\n<code>`. It returns a non-zero rc
    only for transport faults.
  - Success bodies use the real Hetzner list shape.
  - `doppler secrets get --plain` prints the value plus a newline.
  - The `doppler` mock branches on arguments before modes. A mode-only mock answered the HCLOUD read
    with row JSON, which made the old `fail` row pass for the wrong reason.
- **Hetzner `created` format.** The value measured on 2026-09-24 is the `Z` form. The documented
  form is `+00:00`, which jq's `fromdateiso8601` rejects. The decoder normalizes it, and both forms
  are fixtured.
- **Tier-A token not yet provisioned.** prd_terraform holds only `HCLOUD_TOKEN` (measured). The
  fallback keeps the gate working today. At ADR-241 O10 both names must be satisfied by the
  read-only one, and the warning for "neither resolved" names both.
- **New dependency for op=arm and op=luks-*.** During a Hetzner API outage these ops refuse
  (fail-closed). They are rare, reviewer-gated dispatches, and the warning says re-dispatch is safe.
  A replace also needs the Hetzner API, so the added exposure is limited to non-replace dispatches.
- **Clock skew.**
  - A current-server clock more than ~145 s behind excludes its first rows. G3 then refuses
    `silent`, the notice shows `skew_suspect>0`, and the refusal self-heals once the host's clock
    passes `created`.
  - A predecessor clock running ahead is caught by the `dt` conjunct.
  - No tolerance knob is added, because a tolerance is the fail-open direction (AC11).
- **`_EXACT_FLOOR` is exact.** Measure it by running the suite. Never compute it by hand.
- **`## User-Brand Impact`.** A plan whose section is empty or placeholder, or has no threshold,
  fails `deepen-plan` Phase 4.6. This plan's section is filled.
- **iac-plan-write-guard.** Plan prose must not contain the literal Doppler write verb. This plan
  says "the Doppler write of the flag" instead.
- **Precedent diff (deepen Phase 4.4).**

  | Concern | Precedent in repo | This plan |
  |---|---|---|
  | Hetzner read token | `workspaces-luks-cutover.yml` reads `HCLOUD_TOKEN_READONLY`, then falls back | Same order |
  | Header delivery | Precedent puts the token on argv (`-H "Authorization: Bearer $HCLOUD_TOKEN"`) | Diverges on purpose: stdin (`-H @-`) plus `::add-mask::`, on a public run log |
  | Exact-one match | Precedent asserts `.volumes \| length == 1` | Same, plus a client-side exact-name filter |
  | Generation anchor | `git-data-boot-signal-poll.sh` bounds by server-side `dt > anchor`, refuses with no anchor, adds no slack | Same refusal and no-slack posture. The `dt` conjunct runs client-side, with event time as a second conjunct |
