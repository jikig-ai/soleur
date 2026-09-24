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

*(Revised after plan review. The changes and their reasons are in §Plan Review Revisions.)*

Every Better Stack **liveness** count that gates a Doppler write now counts only rows emitted after
the current dedicated server was created. The floor is applied **inside the two readers**, so no
call site changes and all three write-gating gates are covered by construction:

- op=resume G3;
- op=arm G3.7 H;
- op=luks-cutover and op=luks-rollback G3.

1. **Anchor: `_inngest_server_created_epoch`** (I/O).
   - It reads `HCLOUD_TOKEN` from prd_terraform. op=backup already reads that token through the same
     `DOPPLER_TOKEN`.
   - It sends `GET https://api.hetzner.cloud/v1/servers?name=$INNGEST_HOST` and decodes the reply with
     the pure `_hcloud_created_epoch <json> <name>`.
   - It **always prints exactly one token and returns 0**: `<epoch>`, `__ABSENT__` or
     `__UNREADABLE__`. It never exits non-zero, because a bare `x="$(fn)"` under `set -e` without
     `inherit_errexit` would kill the job with no message.
   - On anything but an epoch it writes one `::warning::` to stderr naming the cause:
     - `__ABSENT__`: "no server named `<name>` in the project this `HCLOUD_TOKEN` is scoped to: a
       replace in flight, or a token for another project".
     - `__UNREADABLE__`: "Hetzner API read failed (rc/HTTP class). HCLOUD_TOKEN in prd_terraform,
       or api.hetzner.cloud status. Nothing was written, and re-dispatch is safe."
2. **Pure row filter: `_current_instance_row_count <floor_epoch_s>`.** It reads raw Better Stack
   rows on stdin and prints ONE decimal count. For each row it:
   - decodes `.raw`;
   - keeps only the host pair (`host == $INNGEST_HOST and host_name == $INNGEST_HOST_NAME`);
   - requires `__REALTIME_TIMESTAMP` to be a decimal string;
   - counts the row only when `(.__REALTIME_TIMESTAMP | tonumber) >= floor × 10^6`.

   A missing or non-decimal timestamp EXCLUDES the row and is never defaulted.
3. **Readers.** `_flip_liveness_count` and `_luks_liveness_count` keep their no-argument signature
   and their `rows=$(_bs_query_rows "$…" <tag> 50)` line (pinned by `FLQ_*`). Each one then:
   - calls the anchor. If the result is not an epoch, it prints `__UNREADABLE__`, having already
     printed the anchor `::warning::`. The Better Stack read is skipped entirely.
   - prints one `::notice::` on stderr:
     `liveness scoped to server <name> created <iso> (<age>s ago); rows before it are a predecessor's`.
     This one line lets the operator tell "the replacement has not shipped yet (young age)" from
     "this server is not shipping (#8741 class)".
   - pipes the rows through the filter and prints the count.
4. **Refusal text.** The `unreadable` arms of resume G3 and LUKS G3 currently point only at
   `BETTERSTACK_QUERY_*`. They are reworded to read "the ::warning:: above names which read path
   failed (Better Stack or the Hetzner anchor)", which is arm G3.7's existing wording. The `silent`
   arms gain one sentence: "if the anchor ::notice:: shows the server is under ~5 min old, the
   replacement has not shipped yet: re-dispatch after its first rows land; otherwise suspect Vector
   on the new server".
5. **Explicitly NOT floored:**
   - `_flush_latch_count` (op=arm G3.7's L). The latch lives on `/mnt/data`, which survives the
     replace, so a predecessor's `flip-complete` row is valid PRESENCE evidence for the current
     server. Flooring L would hide it, which is a fail-open on the FLUSHALL guard.
   - `confirm_flip_state` and `confirm_luks_state`. Each is anchored on this dispatch's own write
     instant.

### Why a per-row REALTIME floor, anchored on Hetzner `created`

- **The equivalence depends on one invariant.** A replace destroys the old server before it creates
  the new one: Hetzner names are unique per project, and `hcloud_server.inngest` has no
  `create_before_destroy`. So no predecessor row can carry an event time at or after `created`.
  The suite pins that `inngest-host.tf`'s `hcloud_server.inngest` block contains no
  `create_before_destroy`, so the invariant cannot rot silently.
- **Why REALTIME and not the boot instant.** The first draft filtered on the boot instant
  (`__REALTIME_TIMESTAMP − __MONOTONIC_TIMESTAMP`). REALTIME alone gives the same answer under the
  invariant, needs one field instead of two, and widens the clock-skew margin from ~18 s
  (created → boot) to ~145 s (created → first row, measured 2026-09-24).
- **A reboot of the same server keeps `created`.** It is still "the current server", which is right:
  G3 asks about deliverability, not about a fresh boot.
- **The row's own event time, not Better Stack's `dt`.** `dt` is ingest time: measured, three rows
  from one Vector batch share a single `dt`. The floor reads the row's own event time. The window
  stays `--since 15m`, so the `FLIP_LIVENESS_SINCE="15m"` literal pins are unchanged.
- **Why not a boot or machine pin.** Every channel that carries a boot or instance id is emitted by
  the host itself, so it is not independent of the telemetry under judgment. Those channels are the
  probe row, the cloud-init phone-home and the Sentry boot emit.

### Why op=arm G3.7 H is floored too (review disagreement, resolved technically)

One reviewer argued H should stay unfloored for parity with L: both are about the same volume. The
parity argument does not hold. The two signals answer different questions:

- **L** asks "is there PRESENCE evidence of a flush". Any row from any server on this volume answers
  it.
- **H** exists because L = 0 is an ABSENCE, which a silent host manufactures for free (#7674). What
  H must prove is that the server that could have flushed *unseen* is audible, i.e. the current
  server.

If the replacement ran a flip while its Vector was down (the #8741 state), its `flip-complete` row
never shipped. L reads 0, and an unfloored H counts the predecessor's rows and reports `clear`.
That is exactly the fail-open #7674 closed, reopened by a replace. With H floored, it reads
`silent` and refuses. The change can only ADD refusals.

## Technical Considerations

- **Secrets. This is a public repo's run log.**
  - The token never reaches argv, stdout or stderr. The header goes in on stdin:
    `printf 'Authorization: Bearer %s\n' "$tok" | curl … -H @- …`. (`curl -H @-` was verified locally
    on curl 8.22.)
  - The response body is captured to a variable and never echoed. Only the decoded token leaves the
    function.
  - The token read is `doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain 2>/dev/null`.
  - The op=backup argv form (`-H "Authorization: Bearer $HCLOUD_TOKEN"`) is NOT copied.
- **Transport:** `curl --disable --noproxy '*' -sS -f --proto =https --max-time 20`.
  - Capture as `resp=$(printf … | curl …) || rc=$?`.
  - Non-zero rc means `__UNREADABLE__`. The warning names the rc class: 6/7 egress, 22 HTTP ≥ 400,
    28 timeout, 35/60 TLS.
  - **No `--retry`.** Per the #6500 sharp edge, retry flags can turn a throttled failure into rc 0
    and stretch the time bound. A failure here writes nothing, and the warning says re-dispatch is
    safe.
- **The decoder: `_hcloud_created_epoch <json> <name>`**, a pure function.
  - It runs `[.servers[]? | select(.name == $name)]`, even though the query already filters by name.
  - 0 matches: `__ABSENT__`. More than 1, or non-JSON: `__UNREADABLE__`.
  - `created` is normalized from `+00:00` to `Z` before `fromdateiso8601`. That handles both the
    documented offset form and the `Z` form measured on 2026-09-24.
  - The result must be decimal, otherwise `__UNREADABLE__`.
- **Strict-mode hygiene.**
  - Each new function uses `local x="${1:-}"`.
  - Each I/O function always ends in `return 0`.
  - No new `case` arm in the `arm)` block matches `(clear|latched|unreadable|silent)\)…exit 1`: the
    existing pin at "arm) no G3.7 outcome arm carries its own exit" stays true, because no call site
    changes.
- **Extraction contract.**
  - Signature and closing brace sit at column 0, with no column-0 `}` inside a body. That includes
    multi-line jq programs.
  - Nothing is added inside the case arms. The awk range ends at the first line of 14 spaces
    followed by `;;`, and no call site is edited.
- **Call sites are unchanged** (`RS_LIVE_N="$(_flip_liveness_count)"`,
  `FLIP_LIVENESS_N="$(_flip_liveness_count)"`, `LK_LIVE_N="$(_luks_liveness_count)"`). The #7674 pins
  on those shapes (`RSL_RD < RSL_WR`, `FLV_SITES == 1`) stay green unmodified. `FLQ_SITES == 8`,
  `FLQ_FLIP_SITES == 2` and `FLQ_LUKS_SITES == 2` also hold.
- **Keep message text away from existing negative pins.**
  - The LUKS block must not gain the literal `inngest-cutover-flip`.
  - The resume block must not gain the literal `flush_latch_decide`.
  - New `G3 REFUSING` text stays above the LUKS write (`LK_LASTG3_LN`).
- **Avoid L50–L90** of the script. Draft PR #8690 edits the header comment there.
- **jq in CI.** `fromdateiso8601` and `tonumber` on a 16-digit string are exact below 2^53, and were
  checked on jq 1.8.2 locally. Work phase: print `jq --version` from an `infra-validation.yml` run,
  or add a suite self-check row that evaluates `"2026-09-24T18:57:33Z" | fromdateiso8601 == 1790276253`.
- **Cost.** One Hetzner GET per liveness read: 1 at resume, 1 at arm, 1 at LUKS.

## Implementation Phases

### Phase 1 — RED: reproduce the stale-predecessor pass (tests only, one commit)

In `apps/web-platform/infra/cutover-inngest-workflow.test.sh` §(b2):

1. Extend the `call_flip_liveness_count` harness's mocked `doppler()` to also answer
   `secrets get HCLOUD_TOKEN … --plain` with a synthetic sentinel token. Add a mocked `curl()` that:
   - records its argv to a file and its stdin to another;
   - returns the real Hetzner list shape
     (`{"servers":[{"id":…,"name":"soleur-inngest","created":"2026-09-24T18:57:33+00:00"}],"meta":{"pagination":{…}}}`)
     with synthetic values.
   - Its failure modes mirror real curl 8.x under `-f`: rc 22 with EMPTY stdout, rc 28 and rc 6.
2. Give every existing fixture row (`rows`, `foreign`, `spoofed`) a `__REALTIME_TIMESTAMP` AFTER the
   mocked `created`. Then the `foreign`/`spoofed` 0s stay attributable to the host conjunct (#6616)
   and not to the floor.
3. Add mode **`predecessor`**: two host-pair rows whose `__REALTIME_TIMESTAMP` is BEFORE `created`
   (the 2026-09-24 shape). Assert the output is `'0'`.
4. Bump `_EXACT_FLOOR` in the SAME commit, so the only red row is `predecessor`. Run the suite and
   quote the single FAIL line in the PR body (`cq-write-failing-tests-before`).

### Phase 2 — the filter, the anchor, the readers (GREEN)

In `scripts/cutover-inngest.sh`, beside the liveness readers (~L355-440):

1. Add `_hcloud_created_epoch()` (pure), `_inngest_server_created_epoch()` (I/O) and
   `_current_instance_row_count()` (pure). Put a rationale comment block before them covering:
   - the measured timeline;
   - the destroy-before-create invariant;
   - REALTIME over the boot instant;
   - why L and the confirm readers are exempt;
   - why H is floored.
2. Rewrite `_flip_liveness_count` and `_luks_liveness_count` per Proposed Solution §3. Update both
   readers' guard-note comments.
3. Harness: awk-extract the three new functions, with a non-vacuity assert for each, and `eval` them
   in `call_flip_liveness_count`. Without that, the reader's call is "command not found" and every
   mode reads `__UNREADABLE__`.

### Phase 3 — refusal wording, full test coverage, runbook

1. Reword the `unreadable` and `silent` arms of resume G3 and LUKS G3 per Proposed Solution §4.
2. Add the test rows listed under §Guard Contract and §Acceptance Criteria:
   - a `call_luks_liveness_count` harness, since `_luks_liveness_count` has no executed test today;
   - a stderr capture file for the anchor `::notice::`/`::warning::` rows;
   - the `create_before_destroy` absence pin over `inngest-host.tf`.
3. Set `_EXACT_FLOOR` to the measured dispatched count, and update its arithmetic comment.
4. Correct `knowledge-base/engineering/operations/runbooks/inngest-server.md` §op=resume "G3 is a
   live precondition". Describe the instance scope, the anchor notice with the server's age, and the
   two anchor warnings.
5. `shellcheck -S warning scripts/cutover-inngest.sh` must report no findings beyond the 3
   pre-existing ones.

### Phase 4 — read-only live replay (verification, no dispatch)

Extract `_current_instance_row_count` exactly as the suite does. Feed it one real row set,
`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 18h --grep '"reason":"noop-' --limit 5000`,
twice:

- once with floor `0`;
- once with floor = the current server's `created` epoch, read through the new anchor function.

Record both counts in the PR body. The drop between them is the predecessor's rows, which proves
the predicate against production-shaped rows. It proves the same thing for as long as the
2026-09-24 rows remain in the window. After that, a 15 m window shows equal counts.

## Files to Edit

- `scripts/cutover-inngest.sh`: three new functions, two reader bodies, and the `unreadable` and
  `silent` wording at resume G3 and LUKS G3.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: the harness mocks, the RED fixture,
  the coverage rows and `_EXACT_FLOOR`.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the op=resume G3 paragraph.

## Files to Create

None.

## Open Code-Review Overlap

None. The bodies of `gh issue list --label code-review --state open` were checked for
`scripts/cutover-inngest.sh`, `cutover-inngest-workflow.test.sh`, `_flip_liveness_count` and
`resume_liveness_decide`, and none matched.

## Non-Goals

- Changing what G3 means (deliverability) or its 15 m window.
- Flooring `_flush_latch_count` (fail-open) or the confirm readers.
- Closing the seconds-wide race between G3's read and the write when a replace lands in that gap.
  `cutover-inngest.yml` shares no concurrency group with the replace workflow, so no in-script check
  can close it. A new server also cannot ship rows within seconds, and the flag waits for the next
  host's timer regardless.
- op=backup's argv-token form and its server id `123931471`, which is `soleur-web-platform` by
  design.
- #8714 and #8747 (context only).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Identity filter only (tighten `host`/`host_name`) | Both fields are the same across a replace (measured). That is the defect. |
| Boot-instant floor (`REALTIME − MONOTONIC ≥ created`) | Equivalent under the pinned destroy-before-create invariant, but with an ~8× smaller skew margin and one more field. It was the first draft. |
| Server-side clamp `--since max(now−15m, created)` | Filters on `dt`, which is ingest time. The suite could only check argv, not run the predicate, and it moves the pinned `FLIP_LIVENESS_SINCE` literal. |
| Pin `_MACHINE_ID`/`_BOOT_ID` of the "newest" rows | In the failure window the newest rows ARE the predecessor's. Circular. |
| Join through the probe row's `instance_id=hetzner-<id>` | Still needs the Hetzner read, and depends on an hourly or at-boot row. |
| Freshness bound on the newest row | A heuristic that passes within N s of destroy. Nothing authoritative behind it. |
| Re-read the anchor after the count (`changed` outcome) | Shrinks a seconds-wide race without closing it. Cut in review (see Non-Goals). |
| Anchor read at each call site plus a decider and a shared refusal helper | Three sites of wiring and two extra functions. Putting the anchor inside the readers covers every site by construction, with no call-site change. |
| Fix op=resume only | The shared reader would mean two things, and LUKS G3 and arm G3.7 H carry the same fail-open (see the H rationale). |
| `curl --retry` on the Hetzner read | The #6500 sharp edge: retry can turn a throttled failure into rc 0. Re-dispatch is safe. |

## Guard Contract

### Guard 1 — instance-scoped liveness count

**Property.** Every liveness count consumed by a write-gating decision counts only host-pair rows
whose own `__REALTIME_TIMESTAMP` is at or after the current Hetzner server's `created`. An
unobtainable floor, or a missing or non-decimal timestamp, never widens the count.

**Assembly.** One chokepoint, the two readers that route through it, and the readers deliberately
left out:

- The chokepoint is `_current_instance_row_count`. The row predicate lives only there.
- Its callers are the two liveness readers, `_flip_liveness_count` and `_luks_liveness_count`.
  - `_flip_liveness_count` is consumed by `arm)` G3.7 `FLIP_LIVENESS_N=` and by `resume)` G3
    `RS_LIVE_N=`.
  - `_luks_liveness_count` is consumed by `luks-cutover|luks-rollback)` G3 `LK_LIVE_N=`.
- Outside the assembly by design, and pinned so they stay outside:
  - `_flush_latch_count` (flooring it is a fail-open);
  - the confirm readers;
  - the execute 2.0 and registry-probe gates, which are boot-joined via
    `tests/scripts/lib/inngest-host-dark-gate.sh`.
- The invariant the predicate depends on is `hcloud_server.inngest` having no
  `create_before_destroy`. It is pinned.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the floor `select` from `_current_instance_row_count` | RED: `predecessor` reads `2`, expected `0` |
| 2 | Default a missing timestamp (`// "0"` or `// now`) instead of excluding the row | RED: the `no-ts` fixture expects `0` |
| 3 | Second member after a compliant first: the `mixed` fixture is one predecessor row then two current rows, and the helper is mutated to judge only the first (`first(…)`) | RED: `mixed` expects `2` |
| 4 | Treat `__ABSENT__`/`__UNREADABLE__` as floor `0` in the reader | RED: `anchor-absent` and `anchor-fail` modes expect `__UNREADABLE__` |
| 5 | `_luks_liveness_count` keeps its old inline jq | RED: the executed LUKS `predecessor` case expects `0` |
| 6 | Floor `_flush_latch_count` | RED: pin "the `_flush_latch_count` body does not reference `_current_instance_row_count`/`_inngest_server_created_epoch`" |
| 7 | REORDER: the reader counts rows BEFORE the anchor read and falls back to the unfloored count on anchor failure | RED: the `anchor-fail` mode expects `__UNREADABLE__`, not a count |
| 8 | Add `create_before_destroy = true` to `hcloud_server.inngest` | RED: invariant pin |
| H1 (harness) | Give the `spoofed`/`foreign` rows pre-floor timestamps | RED: fixture self-check (jq over the fixture text asserts those rows' timestamps ≥ the mocked floor) |
| H2 (must-PASS, non-canonical) | A current row with reordered keys, extra journald fields and a timestamp exactly `created × 10^6` | PASS: counted |

### Guard 2 — server anchor

**Property.** The floor comes only from exactly one Hetzner server whose `name` equals
`$INNGEST_HOST` and whose `created` parses. Every other outcome yields a named `::warning::` and a
non-epoch token. The token never appears in argv, stdout or stderr, and the response body is never
echoed.

**Assembly.** The pure decode `_hcloud_created_epoch` is the chokepoint. Its only I/O wrapper is
`_inngest_server_created_epoch`, and its only consumers are the two readers in Guard 1.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Take `.servers[0]` instead of requiring exactly one name match | RED: a two-server fixture expects `__UNREADABLE__` |
| 2 | Second member after a compliant first: body `[{name:"soleur-inngest-old"}, {name:"soleur-inngest"}]` | Must-PASS: the matching server's epoch |
| 3 | Parse only the `Z` form | RED: the `+00:00` fixture expects an epoch |
| 4 | Put the token on argv | RED: token sentinel absent from the recorded curl argv, present on the recorded stdin |
| 5 | Echo the response body on failure | RED: body sentinel from a failing curl absent from the function's stdout+stderr |
| 6 | Return non-zero on failure | RED: under `set -e`, `x="$(_inngest_server_created_epoch)"` in a subshell must reach the next line |

## Observability

```yaml
liveness_signal:
  what: "the conclusion of the latest cutover-inngest.yml run (success = the gate passed and the write landed; failure = a gate refused), plus the reader's anchor ::notice:: (server name, created, age) and the G3 / G3.7 annotation"
  cadence: "per dispatch of op=resume / op=arm / op=luks-cutover / op=luks-rollback"
  alert_target: "the dispatching engineer via the red workflow run (GitHub Actions failure notification); every one of these ops is environment-gated, so a reviewer watches each run"
  configured_in: "scripts/cutover-inngest.sh _flip_liveness_count / _luks_liveness_count (anchor notice + warnings) and the resume) G3, arm) G3.7, luks-cutover|luks-rollback) G3 refusal arms"
error_reporting:
  destination: "GitHub Actions ::warning:: / ::error:: annotations plus a failed job on cutover-inngest.yml"
  fail_loud: "anchor ::warning:: naming the cause (Hetzner rc class / no server named <name> in the token's project) followed by the gate's unreadable ::error::; or the silent ::error:: after an anchor ::notice:: that states the server's age; Better Stack read failures unchanged"
failure_modes:
  - mode: "replacement server not shipping yet; only predecessor rows in the 15m window (the 2026-09-24 shape)"
    detection: "anchor ::notice:: with a young server age, followed by the G3 silent ::error:: before any write"
    alert_route: "red cutover-inngest.yml run, seen by the dispatcher and the environment reviewer"
  - mode: "replacement server up for many minutes but not shipping (Vector down, #8741 class)"
    detection: "anchor ::notice:: with an old server age, followed by G3 silent; the silent text names Vector"
    alert_route: "red cutover-inngest.yml run"
  - mode: "Hetzner API unreadable, HCLOUD_TOKEN missing, or no server by that name (replace in flight / wrong-project token)"
    detection: "anchor ::warning:: naming the cause, then the gate's unreadable ::error:: before any write"
    alert_route: "red cutover-inngest.yml run"
logs:
  where: "GitHub Actions logs of cutover-inngest.yml; the underlying rows in Better Stack Logs source 2457081 (read via scripts/betterstack-query.sh)"
  retention: "GitHub Actions log retention for the repo (90 days default); Better Stack per the source's plan retention"
discoverability_test:
  command: "curl -s --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/cutover-inngest.yml/runs?per_page=1"
  expected_output: "conclusion"
  # Unauthenticated on a public repo (verified 2026-09-24: returned run 36045234529, conclusion success).
  # No shell metacharacters (Check 10 shell-active reject).
```

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - After an inngest host replace, production cron and reminder scheduling stays down longer if
    op=resume refuses a recovery that would have worked. The false-refusal causes are a failed
    Hetzner read or a floor that excludes the new server's own rows.
  - In the fail-open direction, behavior regresses to today's: G3 passes on predecessor rows.
- **If this leaks, the user's data / workflow is exposed via:** the Hetzner project token
  (`HCLOUD_TOKEN`, read/write over every server and volume), if it were ever echoed or put on argv
  in this public repository's run log. The plan feeds it on stdin and never prints it or the
  response body. Guard 2 rows 4-5 test both.
- **Brand-survival threshold:** `aggregate pattern`. The risk is a scheduling-recovery delay that
  affects all users together. The token is already read by op=backup in the same workflow, so this
  adds read sites with stricter handling, not a new credential class.

## Acceptance Criteria

- [ ] AC1 (RED first): the first commit changes only `cutover-inngest-workflow.test.sh`, including
  the `_EXACT_FLOOR` bump. The suite then reports exactly one FAIL, the `predecessor` row, which
  reads `2`. The PR body quotes that line.
- [ ] AC2: every row of the Guard 1 matrix holds, with an executed case for each of these modes:
  `predecessor`→`0`, `current`→`2`, `mixed`→`2`, `no-ts`→`0`, `anchor-absent`→`__UNREADABLE__` and
  `anchor-fail`→`__UNREADABLE__`. `_luks_liveness_count` has its own executed `predecessor`→`0` and
  `current`→`2`.
- [ ] AC3: `foreign` and `spoofed` still read `0`. A fixture self-check proves their timestamps are ≥
  the mocked floor, so the #6616 host-conjunct assertion stays load-bearing.
- [ ] AC4: the `_hcloud_created_epoch` decode table covers the following, with a counter asserting
  every case dispatched:
  - `Z`;
  - `+00:00`;
  - 0 matches → `__ABSENT__`;
  - 2 matches → `__UNREADABLE__`;
  - the non-matching-first must-PASS;
  - missing or garbage `created`;
  - non-JSON input;
  - empty input.
- [ ] AC5: the token sentinel is absent from the recorded curl argv and present on its stdin. A
  failing curl's body sentinel never appears in the function's stdout or stderr. The anchor wrapper
  returns 0 on every failure mode.
- [ ] AC6: the reader's stderr for an anchor failure contains a `::warning::` naming the Hetzner
  cause, and for success an anchor `::notice::` with `created` and the age. It never contains
  `BETTERSTACK_QUERY` for an anchor failure.
- [ ] AC7: `_flush_latch_count` references neither new function (pinned), and
  `hcloud_server.inngest` has no `create_before_destroy` (pinned).
- [ ] AC8: these existing pins stay green UNMODIFIED:
  - `FLQ_SITES == 8`, `FLQ_FLIP_SITES == 2`, `FLQ_LUKS_SITES == 2`;
  - `RS_LIVE_N="$(_flip_liveness_count)"` and `RSL_RD < RSL_WR`;
  - `FLV_SITES == 1`;
  - "arm) no G3.7 outcome arm carries its own exit";
  - `LK_G3TAG`;
  - the `FLIP_LIVENESS_SINCE="15m"` literal pins.

  The diff to the test file adds rows and changes fixtures. It deletes no existing assertion.
- [ ] AC9: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0 with
  `_EXACT_FLOOR` equal to the dispatched count. `shellcheck -S warning scripts/cutover-inngest.sh`
  reports only the 3 pre-existing findings.
- [ ] AC10: the Phase 4 read-only replay is recorded in the PR body: the count with floor `0` and the
  count with floor `created` over one identical row set, with the latter strictly smaller while the
  2026-09-24 predecessor rows are still in the window.
- [ ] AC11: the workflow YAML gains no knob that weakens the floor:
  `! grep -qE 'INNGEST_HOST|FLOOR|SKEW|HCLOUD' .github/workflows/cutover-inngest.yml`. The most
  natural "repair" for a stuck `silent`, a tolerance knob, stays unavailable.
- [ ] AC12: `knowledge-base/engineering/operations/runbooks/inngest-server.md` describes the
  instance-scoped G3, the anchor notice with the server's age, and the two anchor warnings. It no
  longer claims that a freshly replaced host makes G3 refuse.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: a gate predicate
inside an ops script, its test suite and one runbook paragraph. There is no user-facing surface, no
new vendor and no new data processing. (Hetzner and Better Stack are existing processors, already
read by this workflow.)

## Test Scenarios

- **Predecessor rows only.** Given host-pair rows in the window whose event time predates the
  current server's `created`, when op=resume's G3 counts them, then:
  - the count is `0`;
  - the anchor notice states the server's age;
  - G3 refuses `silent` before the write.
- **Current rows.** Given rows from the current server (event time ≥ `created`), then G3 passes
  `audible`.
- **Hetzner read fails.** Given the Hetzner API returns HTTP 401 (curl rc 22), a timeout (rc 28) or
  non-JSON, then:
  - the reader prints a `::warning::` naming the Hetzner cause, followed by `__UNREADABLE__`;
  - op=resume refuses `unreadable`, and the refusal points at the warning above;
  - nothing is written.
- **No server.** Given no server named `soleur-inngest`, then the `::warning::` names the queried
  name and the token's project scope, and op=resume refuses `unreadable`.
- **Arm and LUKS.** Given the same predecessor-only rows:
  - when op=arm reaches G3.7, then H is `0` and `flush_latch_decide` returns `silent`;
  - when op=luks-cutover reaches G3, then it refuses `silent`.
- **Latch unaffected.** Given a predecessor `flip-complete` row within 365 d, when op=arm reads L,
  then L still counts it and G3.7 returns `latched`.
- **Live replay (read-only).** Run the Phase 4 replay. It prints two decimals, and the floored one
  is smaller.

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
  - The mocked `curl` returns rc 22 with EMPTY stdout on HTTP ≥ 400 under `-f`, as curl 8.x does.
    It must not return a body.
  - Success bodies use the real Hetzner list shape.
  - The mocked `doppler secrets get --plain` prints the value plus a newline.

  A fake written from the consumer's reading hides decoder and API mismatches.
- **Hetzner `created` format.** The value measured on 2026-09-24 was the `Z` form. The documented
  form is `+00:00`, and jq's `fromdateiso8601` rejects offsets. The decoder normalizes, and both
  forms are fixtured.
- **New dependency for op=arm and op=luks-*.** During a Hetzner API outage these ops refuse,
  fail-closed. They are rare, reviewer-gated dispatches, and the warning says re-dispatch is safe.
  A replace itself also needs the Hetzner API, so the added exposure is limited to non-replace
  dispatches.
- **Clock skew.** A host clock more than ~145 s behind real time would exclude the new server's own
  first rows, so G3 refuses `silent`. The refusal is visible and self-heals as rows age past the
  floor. No tolerance knob is added, since a tolerance is the fail-open direction (AC11).
- **`_EXACT_FLOOR` is exact.** Measure it by running the suite. Never compute it by hand.
- **`## User-Brand Impact`.** A plan whose section is empty or placeholder, or omits the threshold,
  fails `deepen-plan` Phase 4.6. This plan's section is filled.
- **iac-plan-write-guard.** Plan prose must not contain the literal Doppler write verb. This plan
  says "the Doppler write of the flag" instead.
