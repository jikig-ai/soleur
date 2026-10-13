---
title: "fix: Better Stack admission partition for #6551 + repo-wide emitter-selection census for #8875"
date: 2026-10-13
slug: fix-6551-8875-betterstack-emitter-guards
branch: feat-one-shot-6551-8875-betterstack-emitter-guards
issue: 6551
closes: [6551, 8875]
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-13 (manual sequential pass — this harness has no Task/Agent tool; the per-section fan-out, skills fan-out, learnings fan-out and review-agent fan-out ran inline by the author, `Reviewed-Coverage: sequential-fallback` — no independent review is claimed)
**Sections enhanced:** Hypotheses (the #6551 enumeration resolves against ADR-286's verified evaluator, and a FOURTH double-admission window — container stderr — was found while tracing the partition), Proposed Solution (the exclude_matches partition with the vector.service crit-path move), Guard Contract (two guards: the admission emulator and the reader census), Dependencies & Risks (9963i excludes-`SYSLOG_IDENTIFIER` pin must be widened deliberately — an exclude entry for `systemd` would SILENCE the channel rather than over-ship).

### Key Improvements

1. The issue's "no source admits" table is refuted by git history: `include_matches.PRIORITY = ["0".."4"]` has sat on `[sources.inngest_journald]` since #4267 (commit 29290a07f9ec), predating image v1.1.19; the row ships legitimately under OR-over-fields admission (ADR-286), so the residual engineering is the semantic fix `vector.toml` assigns to #6551 twice ("the dedupe fix belongs to #6551").
2. A new discovery during planning: container stderr (Docker's journald driver maps fd 2 → PRIORITY 3) is admitted by `app_container_journald`/`egress_gw_journald` AND Source 1's PRIORITY arm — a third double-ship window the file's comments do not name. The partition closes it too.
3. The 9963i canonical-form pin in `journald-config.test.sh` ("EVERY SYSLOG_IDENTIFIER occurrence lives on an include_matches.SYSLOG_IDENTIFIER line") must be widened to the `exclude_matches.SYSLOG_IDENTIFIER` spelling — and the never-add pin must cover the EXCLUDE arrays, where a `systemd` member silently STOPS shipping the systemd class rather than over-shipping it.

### New Considerations Discovered

- `cat-deploy-state.sh` already exposes `vector_config_identity` (sha256 + mtime of the live `/etc/vector/vector.toml`) — the issue's "Next probes" item 3 (diff the running config, no SSH) is already instrumented; the plan asserts the field still ships.
- Vector's journald `exclude_matches` is confirmed against the `JournaldConfig` source surface (`exclude_matches: HashMap<String, HashSet<String>>`, "if any are present, excludes the entry"; `exclude_units` merges into `exclude_matches._SYSTEMD_UNIT`) — present since before the 0.43.1 pin.

## Overview

One PR covers two issues. **#6551 (bug, p2):** a live Better Stack row (`PRIORITY=3`, `_SYSTEMD_UNIT=init.scope`, `SYSLOG_IDENTIFIER=systemd`, `UNIT=inngest-heartbeat.service`, `host_name=soleur-inngest-prd`) appeared to ship through no admissible source. The mystery is resolved: Vector's journald source streams the whole journal and filters client-side with OR-over-record-fields (ADR-286, verified against journald.rs @ v0.43.1), so Source 1's `include_matches.PRIORITY = ["0".."4"]` arm admits the row regardless of unit — the same path the #9963 `SOLEUR_SYSTEMD_JOURNALD_CONTROL` emit was built to prove. What remains — and what `vector.toml` twice assigns to #6551 — is the semantic fix: the OR-arm creates three double-admission windows (S1∩S2 on host CRIT+, S1∩S4 on tagged rows at PRIORITY ≤4, and the newly-found S1∩S3/S3b on container stderr). This plan re-architects admission into an exact partition — every journald record is admitted by AT MOST one source — and lands the regression guard the issue asks for: an admission emulator that evaluates synthesized journald records against the real `vector.toml` match sets, so "no source admits" / "two sources admit" is a CI verdict, not a hand-computed table.

**#8875 (chore, deferred-scope-out of #8846):** every `betterstack-query.sh` reader must select rows by journald emitter (`SYSLOG_IDENTIFIER` or a sourced emitter def), not by message substring — the third recurrence of the wrong-emitter defect (#6475, the 2026-09-17 `inngest-host-state.sh` false `VERDICT NOT SERVING`, #8846). This plan ships the repo-wide census guard `scripts/lint-betterstack-emitter-read.sh` + mutation battery `scripts/lint-betterstack-emitter-read.test.sh` on the `lint-followthrough-varq-ban` pattern, plus a generalized emitter-selection lib `scripts/lib/bs-emitter-row.sh` built on the #8846 contract.

## Research Insights

**Premise validation (Phase 0.6, 2026-10-13).** Checked with `gh` and `git grep` on this branch: **#6551** OPEN (`type/bug`, `priority/p2-medium`, `domain/engineering`); **#8875** OPEN (`type/chore`, `priority/p3-low`, `deferred-scope-out`, `observability`, `meta/machinery`, `Mandated-By: wg-when-deferring-a-capability-create-a`, re-evaluate by 2026-10-25 or next reader of that class). **ADR-286** exists at `knowledge-base/engineering/architecture/decisions/ADR-286-vector-journald-source-admits-by-or-and-the-systemd-path-control.md` (status `adopting`, issue 9963, `related: [9963, 6551, 8875, 9939]` — its Consequences literally hand this PR its scope: "#6551 and #8875 inherit the verified mechanism; their remaining work is the semantic decision this ADR explicitly does not take"). **#9963** CLOSED — it shipped the mechanism documentation + `SOLEUR_SYSTEMD_JOURNALD_CONTROL` + the `9963a..l` pins in `journald-config.test.sh` + `PRIORITY_ARM_EXEMPTIONS`/`AC3d` in `vector-pii-scrub.test.sh`. `scripts/lib/inngest-probe-row.sh` exists with its census suite `scripts/lib/inngest-probe-row.test.sh` (auto-globbed via `scripts/lib/*.test.sh`). Vector pin: `vector.tf:13` `vector_version = "0.43.1"`; `vector validate --no-environment --config-toml` runs in `validate-vector-config.yml` on every vector.toml PR.

**Git-history check on the issue's table.** `git log -S 'include_matches.PRIORITY' -- apps/web-platform/infra/vector.toml`: the Source-1 arm `["0", "1", "2", "3", "4"]` was added by #4267 (commit 29290a07f9ec, "vector.toml uses include_matches.PRIORITY (not bogus include_priorities)"), long before image v1.1.19. The issue's Source-1 row lists only `include_units` — the arm was never in the table. Under the real evaluator the row was always admissible; "the image vs repo difference was ruled out" is consistent because BOTH configs carry the arm.

**The exclude semantics needed for the partition** are in-tree-verified doctrine: `vector.toml`'s own Source-2 header records "includes are OR'd over record fields; excludes then drop on any match", and the vendor source surface confirms `exclude_matches` + `exclude_units` merging into `exclude_matches._SYSTEMD_UNIT`. `exclude_matches` is NOT used anywhere in the repo today (`grep -rn exclude_matches` — zero hits), so the new lines are a first-use, covered by `vector validate` + the emulator's parse.

**Institutional precedents used.** `inngest-probe-row.test.sh` Guard 1 (the census: `discover`/`selects_with_def`/`contract_missing`/`census` with `ALLOW` reason-map + `MUST_FIND` + `STALE`/`UNCLASSIFIED`/`CONTRACT`/`ALLOWLISTED-READER` verdicts + mktemp fixture-tree mutations — the #8875 census is this shape generalized from one marker to every invocation); `lint-followthrough-varq-ban.test.sh` (guard script + mutation battery driving the REAL guard over sandboxed trees, DISPATCH rows proving each grep is the mechanism, floor-breach exits 2); `journald-config.test.sh` (`assert`/`PASS`/`FAIL`/`TOTAL` + `MIN_TOTAL` floor reporting directly via `printf`/`exit 1`); `vector-pii-scrub.test.sh` (ADR-193 conservation — `CASES` incremented at call sites, `PASS+FAIL == CASES`, `[FATAL]` floor outside helpers); `scripts/guard-vacuity-floor.test.sh` (its `heredoc_lines_of` treats a literal `<<`/`<<<` token in ANY line — comments, needle strings — as a heredoc opener: new suite text must never carry a bare `<<`/`<<<` outside a real heredoc; assemble needles via `_lt='<'` etc., and keep tail floors outside any heredoc-blanked span, self-exiting via `printf` sentinel + `exit 1`).

**Property List.**

- P1. The #6551 fixture row resolves to exactly one admitting source (`inngest_journald`) — the answer is mechanical, not hand-computed.
- P2. Every synthesized journald record in the corpus is admitted by AT MOST one source — the three double-admission windows are closed.
- P3. No row that ships today stops shipping: inngest-server.service at every priority (unit arm), host CRIT+/ERR/WARN via the surviving arms, tagged emitters via Source 4, vector.service CRIT via Source 2 (newly un-excluded), the `-t systemd -p err` control via the {3,4} arm.
- P4. A `systemd` member can never enter ANY `SYSLOG_IDENTIFIER` match array — include (over-ship) or exclude (silence) — pinned tokenized over all layout variants.
- P5. Every tracked non-test `betterstack-query.sh` invocation is discovered and classified: emitter-selected, or allowlisted with a reason — new raw readers fail CI.
- P6. Both guards are mutation-covered, floor-bearing, and report with `printf` + `exit 1` outside their verdict helpers (ADR-193), and no new `.test.sh` text carries a bare `<<`/`<<<` outside a real heredoc (guard-vacuity-floor defect class).

**Cut List (mechanism → property → what already covers it).**

- Runtime `dedupe` transform: cut — stateful cache (`cache.num_events`), drops a REAL second record on a timestamp+content collision (journald µs timestamps make it rare, not impossible), and its value — catching admission drift — is better served by making the emulator fail on drift instead of silently absorbing duplicates.
- AND-composition re-architecture of Source 1 (split into per-unit sources): cut — Vector's journald source cannot AND across fields; expressing it would need a post-source filter transform carrying the same logic the partition expresses natively at the source boundary.
- Extending `inngest-probe-row.sh` itself with the generalized def: cut — its suite pins a probe-scoped contract (`INNGEST_PROBE_*` names, marker-anchored predicate); a new sibling lib keeps that contract unchurned.
- Per-invocation census granularity: cut — per-file classification matches the shipped census shape; allowlist reasons name the exempt call sites (recorded as a pending ruling).
- Hand-maintained caller list in the plan: cut — the guard derives the population from `git ls-files`; this plan's caller table is the audit seed, not the mechanism.

## Hypotheses

For #6551, enumerate the candidate explanations for "a live Better Stack row ships that NO source in vector.toml admits" and rule each in/out:

1. **H1 — the row IS admitted; the table omitted Source 1's PRIORITY arm.** RULED IN. `include_matches.PRIORITY = ["0","1","2","3","4"]` sits on `[sources.inngest_journald]` (vector.toml:81), merged from #4267 — the issue's table lists only `include_units` for that source. Under OR-over-fields admission (contains_match = `record.iter().any(...)`, journald.rs @ v0.43.1, ADR-286), `PRIORITY=3` admits the row from ANY `_SYSTEMD_UNIT`/`SYSLOG_IDENTIFIER`; it flows `pii_scrub_* → tag_journald → sinks.betterstack` → Logs source 2457081. This is byte-for-byte the `SOLEUR_SYSTEMD_JOURNALD_CONTROL` path #9963 pinned. The "mystery" was a stale AND-model evaluation, not a ghost shipper.
2. **H2 — deployed-config drift (the running host renders an older vector.toml).** RULED OUT as the explanation (the arm predates the pulled image v1.1.19; the issue's own image extraction shows the image's sources are an older-but-equivalent shape). Residual instrumented: `cat-deploy-state.sh` emits `vector_config_identity` (`sha256=` + `mtime=` of the live `/etc/vector/vector.toml`) and the probe row carries `image_ref=` — the running config is diffable no-SSH; the plan adds a suite pin that the field still emits.
3. **H3 — a second shipper/config on the host.** RULED OUT by enumeration: `inngest-bootstrap.sh` installs exactly one binary (`/usr/local/bin/vector`, sha256-verified) and exactly one config (`install -m 0644 /tmp/vector.toml /etc/vector/vector.toml`, staged from the image); `vector.service` is a single unit; no `--config-dir`, no `vector.d/`, no `extra_args` on any journald source (the emulator pins `extra_args` absent — a `--match`/`--unit` extra arg would re-introduce journalctl-side matching outside the verified evaluator).
4. **H4 — a transform rewrites fields post-admission.** RULED OUT by reading every transform: writes are confined to `.message`, `.pii_scrub_applied`, `.source_kind`, `.shipper`, `.host_name`, `.metric.*`; pin `9963j` already asserts no VRL assigns `.SYSLOG_IDENTIFIER`, and no transform creates `PRIORITY`/`UNIT`/`_SYSTEMD_UNIT`.
5. **H5 — host_name forgery (a web-host row stamped soleur-inngest-prd).** RULED OUT: `@@HOST_NAME@@` renders to `soleur-inngest-prd` only on the inngest path (`inngest-bootstrap.sh` sed); web hosts render `soleur-web-platform`/`soleur-web-2`. A forged stamp would require editing the sed — outside any failure mode observed.
6. **H6 — journalctl-side `UNIT=` matching (issue probe 1).** RULED OUT by mechanism: the source spawns `journalctl --follow --all --show-cursor --output=json` with NO match args; `include_units` merges into `include_matches._SYSTEMD_UNIT`, and `UNIT=` is a different field the evaluator never consults. `UNIT=inngest-heartbeat.service` played no role in admission.
7. **H7 — Source 2 silently ignoring `include_matches.PRIORITY` (issue probe 2, the #4267 bogus-key class).** RULED OUT/moot: the row needs no Source-2 admission; Source 2's `{0,1,2}` correctly excludes PRIORITY 3 under any reading. `vector validate` + the emulator's parse both fail loudly on a misspelled key going forward.

The residual defects the issue surfaced (this PR's actual scope): **R1** — `PRIORITY {0..2} ⊆ {0..4}` double-admits every non-excluded host CRIT+ row via Sources 1+2 (documented, ~2× quota on that class); **R2** — Source-4 tagged rows at PRIORITY ≤4 double-admit via Sources 1+4 (tagged crit rows triple-admit via 1+2+4); **R3** — discovered this pass: container stderr (fd 2 → PRIORITY 3 under Docker's journald driver) double-admits via Source 1's arm and Sources 3/3b; **R4** — the doctrine gap: nothing mechanical answers "which sources admit row X", which is how the issue's hand table went wrong. R4 is the regression guard the issue requests.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (read 2026-10-13, this branch) | Plan response |
|---|---|---|
| "all four vector.toml sources should reject it" (issue's table) | Source 1 admits it: `include_units` OR `include_matches.PRIORITY {0..4}` (vector.toml:78-81); the arm was in the file since #4267 and is now pinned by `vector-pii-scrub.test.sh` Source-1 drift row | Hypotheses H1; the semantic fix partitions the arms rather than dropping the row |
| "The image vs repo difference was ruled out" | Consistent — image v1.1.19's vector.toml predates `webhook`/`@@HOST_NAME@@` but carries the same PRIORITY arms; either config admits the row | H2; `vector_config_identity` sha pin asserts the live-config hash stays observable |
| "there may be an inngest-host-specific vector config or the image may carry its own" | One config: the image bakes `/vector.toml` (Dockerfile:355 COPY `/app/infra/vector.toml`), bootstrap installs it to `/etc/vector/vector.toml` and renders `@@HOST_NAME@@`→`soleur-inngest-prd`; web hosts get the same file via `terraform_data.journald_persistent` (triggers_replace on its sha256) | No sibling config exists; H3 ruled out; apply-path section records the two delivery routes |
| "a regression guard pinning that only admitted fields ship" | No admission-emulating suite exists today; `vector-pii-scrub.test.sh` pins literals, `journald-config.test.sh` pins the tag set + the control emit; nothing evaluates "which sources admit record X" | New `apps/web-platform/test/infra/vector-admission.test.sh` — the emulator + multiplicity pin |
| "scripts/lib/inngest-probe-row.sh exists on main — a sourced jq def for emitter-field selection, generalized" | Confirmed: exports `INNGEST_PROBE_ROW_JQ`/`INNGEST_PROBE_EMITTER`/`INNGEST_PROBE_MARKER` + selftest + a load contract; its predicate is probe-scoped (emitter AND marker-prefix) | New sibling lib `scripts/lib/bs-emitter-row.sh` exports the emitter-parameterized def; probe lib untouched |
| "~20 non-test callers need audit" | ~55 tracked non-test files carry non-comment invocation-shaped lines (`betterstack-query.sh` with `--grep`/`--since`/SQL or via `QUERY`/`BQ`/`QUERY_CMD`/`run_bq`/`_bs_query_rows` seams), plus ~10 workflow files; many are hint-echo or mention-only after comment-stripping | The census discovers by `git ls-files` + comment-strip; the audit dispositions each |

## Problem Statement

`vector.toml`'s Source-1 `include_matches.PRIORITY {0..4}` arm is a host-wide ERR+ shipper that overlaps Source 2's `{0..2}` window and Source 4's tag allowlist — every overlapping row ships twice (triple for tagged crit rows), which is real quota spend documented but never fixed. #9963 verified and pinned the mechanism but explicitly deferred the semantic decision to #6551. Separately, the wrong-emitter read defect has recurred three times (#6475, inngest-host-state 2026-09-17, #8846); the #8846 fix covered one marker's readers and deferred the repo-wide census to #8875, whose re-evaluation window (2026-10-25) is now due.

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/feat-one-shot-6551-8875-betterstack-emitter-guards/decision-challenges.md`; technical rows are `pending - assumed:` where they fork (a `soleur:engineering:cto` consult at review may supersede).

1. **Partition the priority/tag/container admission windows (`apps/web-platform/infra/vector.toml`).**
   - `[sources.inngest_journald]`: `include_matches.PRIORITY` narrowed `["0","1","2","3","4"]` → `["3","4"]`; `include_units` unchanged (`["inngest-server.service"]`). Add `exclude_matches.SYSLOG_IDENTIFIER = [<the exact Source-4 tag set>]` and `exclude_matches.CONTAINER_NAME = ["soleur-web-platform", "soleur-egress-gw"]`.
   - `[sources.system_journald]`: `include_matches.PRIORITY = ["0","1","2"]` unchanged; `exclude_units` narrowed `["inngest-server.service", "vector.service"]` → `["inngest-server.service"]` — the vector.service exclusion only ever routed its crit rows through Source 1's 0-2 sub-arm, which this change removes; leaving the exclusion would silently drop vector.service CRIT rows entirely. Add `exclude_matches.SYSLOG_IDENTIFIER = [<the same Source-4 tag set>]` (tagged crit rows ship once via Source 4 — the #7898 off-box refusal path is preserved through the tag channel).
   - Net effect: a row is admitted by a source iff (unit arm / PRIORITY arm / tag arm / container arm) matched AND no exclusion matched — and the partition is disjoint: PRIORITY 0-2 → Source 2 (or S4 if tagged); PRIORITY 3-4 → Source 1 (or S3/S3b/S4 per emitter); tagged → S4 at every priority; containers → S3/S3b. Every corpus row admits at multiplicity ≤1; every row that shipped before still ships.
   - Comments rewritten: the `DOUBLE-ADMISSION`/`OVERLAP` paragraphs and both "dedupe fix belongs to #6551"/"#6551 tracks the semantic fix" sentences are replaced by the partition contract; the `systemd` never-add warning is extended to name the EXCLUDE direction (an exclude entry would silence the class).
2. **Admission emulator suite (`apps/web-platform/test/infra/vector-admission.test.sh`, new).** Parse `vector.toml` ONCE into a source model (python3 `tomllib` → JSON of every `[sources.*]`'s type/include/exclude maps — `pending - assumed` over the grep/awk convention; the journald-config suite's own documented residual names tomllib as the closing move, and the emulator needs ALL `include_matches.*` fields, not only SYSLOG_IDENTIFIER). Evaluate each synthesized journald record under the documented semantics (includes = OR over field-value sets; `include_units` merged into `_SYSTEMD_UNIT`; excludes = drop on any match; absent include set = admit-all — pinned ABSENT: every journald source must carry ≥1 include key, and `extra_args` must be absent). Assert per fixture the exact admitting-source SET, and over the whole corpus that multiplicity ≤1. Corpus includes: the #6551 row verbatim; the control shape (`-t systemd -p err` → PRIORITY 3); inngest-server rows at PRIORITY 6 and 0; systemd PRIORITY-6 Started/Stopped (assert `∅` — deliberately unshipped); tagged rows at PRIORITY 4 and 2; container stdout PRIORITY 6 and stderr PRIORITY 3 (both container names); canary stderr PRIORITY 3 (asserts the pre-existing single-ship via the arm is unchanged); a vector.service PRIORITY-1 row (→ `{system_journald}` — the moved path); an untagged PRIORITY-6 cron row (→ `∅`); host_metrics-shaped records excluded by type before journald evaluation. Structural rows: S1 and S2 `exclude_matches.SYSLOG_IDENTIFIER` arrays tokenized-equal to the S4 include array; S1 `exclude_matches.CONTAINER_NAME` equal to the union of S3/S3b `include_matches.CONTAINER_NAME`; no `exclude_matches.PRIORITY` anywhere; sinks.betterstack `inputs` still exactly `["tag_journald", "tag_metrics"]`. Anti-vacuity: `CASES`-style independent counter + `PASS+FAIL == CASES` conservation + literal `MIN_CASES` floor + instrument self-test; verdicts reported through `pass`/`fail`, floors via `printf`+`exit 1`. **No bare `<<`/`<<<` token outside a real heredoc anywhere in the file** (guard-vacuity-floor defect class — assemble needle strings via `_lt='<'`).
3. **Existing suite updates.** `vector-pii-scrub.test.sh`: the Source-1 pin becomes `["3", "4"]` with rewritten reasoning (the 0-2 window now lives solely on Source 2); the Source-2 pin becomes `exclude_units = ["inngest-server.service"]` with the vector.service-move rationale; the `#7898` comment notes tagged crit rows now single-ship via S4; floor ratchet 39 → measured. `journald-config.test.sh`: `9963d` description updated to the `{3,4}` arm (the `-t systemd -p err` argv pin is unchanged — PRIORITY 3 is still inside); `9963i` widened to accept canonical `exclude_matches.SYSLOG_IDENTIFIER` lines AND new `9963m` asserts NO `exclude_matches.SYSLOG_IDENTIFIER` array carries `systemd` (tokenized, all layout variants — the silence direction of the never-add class); `9963i-bis` gains the `exclude_matches = {` bare-table spelling; `MIN_TOTAL` ratcheted. `fresh-boot-parity.test.sh`, `workspaces-boot-unlock.test.sh`, `luks-monitor.test.sh`, `inngest.test.sh`: audited for arm-shape/tag-list references — their `include_matches.SYSLOG_IDENTIFIER` anchors are unaffected (`exclude_matches.` never matches that pattern), re-run only.
4. **#8875 census guard (new pair).** `scripts/lint-betterstack-emitter-read.sh`: discovery = `git ls-files` minus `knowledge-base/**`, `docs/**`, `*.md`, `*.test.*`, `tests/**`, the guard pair itself; within each file, invocation = a NON-COMMENT line (strip `#`-comments for `.sh`/`.yml`/`.tf`, `//`/`/*`/`*`-comments for `.ts`) carrying `betterstack-query.sh` adjacent to invocation shape (`--grep`, `--since`, `SELECT`, seam assignment to `QUERY`/`BQ`/`QUERY_CMD`, or a `doppler run … betterstack-query.sh` wrapper) — doc-mention-only files never enter the population; classification = the file's non-comment code carries an emitter check (`SYSLOG_IDENTIFIER` in a `select(`/`JSONExtractString`/`os.environ`/`-t`/comparison context, `--control-require-field`, or a source line for `bs-emitter-row.sh`/`inngest-probe-row.sh`/`inngest-host-dark-gate.sh`) → OK-EMITTER; else an `ALLOW[<path>]="<reason>"` entry → OK-ALLOWLISTED; else `UNCLASSIFIED` → exit 1. Plus `STALE` (allowlisted file no longer discovered), `BARE-REASON` (empty reason), `MUST_FIND` list seeded with the known heavyweight readers, and a `MIN_POPULATION` floor on the discovered count. Verdicts printed per file; direct `printf`+`exit 1` on floor/internal errors (exit 2).
   `scripts/lint-betterstack-emitter-read.test.sh`: drives the REAL guard over mktemp fixture trees — GREEN compliant reader (jq `select(.SYSLOG_IDENTIFIER=="x")` or sourced def), RED unclassified raw `--grep` reader, RED stale allowlist entry, RED bare reason, RED an allowlisted file whose invocation is comment-only now (STALE), COMMENT-only mention skipped (must-PASS), DISPATCH row proving the discovery grep is the mechanism, floor-breach → exit 2 on the real tree via the test override; conservation counter + floor + instrument self-test per ADR-193.
   `scripts/lib/bs-emitter-row.sh` (new): exports `BS_EMITTER_ROW_JQ` (`def bs_emitter_row($e): type == "object" and .SYSLOG_IDENTIFIER == $e;`) and `BS_EMITTER_MARKER_ROW_JQ` (`def bs_emitter_marker_row($e;$m): bs_emitter_row($e) and ((.message | type) == "string") and (.message | startswith($m + " "));`), the same `unset`/`source`/`selftest` load contract and `selector_unavailable`/`selector_failed` vocabulary as `inngest-probe-row.sh`, plus a `--selftest` executed mode for discoverability. In-scope for the census's "sourced def" coverage.
5. **Caller audit + dispositions (the bulk of #8875).** Run the guard once to emit the discovered population; then each file is either converted (add the emitter predicate — most `--grep <marker>` readers gain a `fromjson`-decoded `select(.SYSLOG_IDENTIFIER == "<tag>")` or the sourced def) or allowlisted with a reason. Expected classes: (a) converted — readers whose verdict depends on a marker (the `SOLEUR_*`/`stage=`/canary readers — e.g. `zot-*`, `inngest-*`, `registry-*` followthroughs, `inngest-host-state.sh`, `cutover-inngest.sh` gate already dark-gate-covered); (b) allowlisted-as-any-emitter — readers whose property is "ANY row of this shape" (e.g. `betterstack-roundtrip-latency-7855.sh` measures ingest latency, `probe-inngest-524-count.sh` already field-extracts `_SYSTEMD_UNIT`, host_metrics readers — metrics rows carry no `SYSLOG_IDENTIFIER`); (c) allowlisted-as-hint — operator-facing echo text embedding a query recipe (e.g. `zot-soak-6122.sh` advisory lines); (d) the transport itself (`betterstack-query.sh`, `betterstack-assert-absence.sh` — the latter's disposition decided in the audit: its `--control-require-field` already field-scopes the control; the `--absence` arm may need a field-scope option or an allowlist reason). Registration: two `run_suite` lines in `scripts/test-all.sh` (live + unit, beside the varq-ban pair at ~5461) + the new suite's run line in `validate-vector-config.yml` (path filter already covers `apps/web-platform/test/infra/**` and `vector.toml`).
6. **Docs.** ADR-286 dated addendum: the deferred semantic decision is taken — the arms are partitioned; the `systemd` row ships once via the {3,4} arm; the double-admission windows are closed; status note keeps the path-scoped control contract. `vector.toml` comment rewrite per item 1. Optional learning entry on the hand-computed-admission failure class.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| `type = "dedupe"` transform before the sink | Stateful cache with `num_events` eviction; collapses windows generically but drops a real second record on a timestamp+fields collision (rare, nonzero) and silently absorbs FUTURE admission drift — the partition fails the drift loud instead |
| Delete Source 2, widen Source 1 to {0..4} for everything | Loses the unit-level `exclude_units` carve-out that keeps inngest-server.service's own rows on one stream; also re-couples the crit sink #7898 pins to a source whose unit arm exists for a different purpose |
| Keep the arm at {0..4}, add `exclude_matches.PRIORITY` to Source 2 | Cannot express "PRIORITY 0-2 AND NOT (Source-1-admitted)" — S1's arm is a superset region; only narrowing the arm makes the windows disjoint |
| Add vector.service to Source 1's `include_units` instead of un-excluding it from Source 2 | Ships ALL vector.service rows including PRIORITY 5-6 routine chatter — a standing quota cost for a signal nobody queries; S2 un-exclusion ships exactly its CRIT rows like every other host unit |
| Marker-scoped extension of `inngest-probe-row.test.sh`'s census | Its discovery keys on the probe marker literal; #8875's population is every caller regardless of marker — a separate guard with invocation-shape discovery is the assigned shape |
| Per-invocation census (parse each call site) | Static bash parsing cannot reliably bind a `$QUERY` seam to its output consumer per line; per-file classification + reasons naming call sites is the shipped census shape and keeps the allowlist honest at file granularity |
| Convert all ~20-30 callers, no allowlist | Several readers are legitimately emitter-agnostic (ingest-latency measurement, host_metrics readers with no SYSLOG_IDENTIFIER, verdict-by-count); the allowlist-with-reason is the deliberate record of WHY, and it goes stale-loud when the file stops invoking |

## Boot-budget / runtime-cost analysis

- The partition REDUCES Better Stack ingest: previously double- (and triple-) shipped rows now ship once. No new source, tag, or cadence is added; the standing `SOLEUR_SYSTEMD_JOURNALD_CONTROL` cost (~24 rows/day) is unchanged.
- The emulator suite is pure CPU (one tomllib parse + jq per fixture; no vector binary, no network) — well inside the validate-vector-config job's budget.
- The census guard is a `git ls-files` + per-file greps — comparable to `lint-followthrough-varq-ban.sh` (seconds).

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** Author `vector-admission.test.sh` with the full corpus and the partitioned expectations — expect RED on the double-admission fixtures (they currently admit at multiplicity ≥2) and on the exclusion-mirror pins (no exclude arrays exist yet). Update `vector-pii-scrub.test.sh` Source-1/Source-2 pins — expect RED. Author `lint-betterstack-emitter-read.sh` + `.test.sh`; the guard's live run emits the initial UNCLASSIFIED population (that is the audit input — expected non-zero), while the sandbox battery must go green against the finished guard. Add the `9963m` exclude-direction pin to `journald-config.test.sh` — expect RED (an exclude array does not exist yet; write it as a must-PASS-on-absence + must-RED-on-member fixture so it is load-bearing).

**Phase 1 — the partition.** Edit `vector.toml`: narrow the Source-1 arm to `["3","4"]`, add both `exclude_matches` maps to Source 1, add `exclude_matches.SYSLOG_IDENTIFIER` to Source 2, narrow Source-2 `exclude_units` to `["inngest-server.service"]`, rewrite the affected comment blocks. Keep the Source-4 tag list byte-stable (the exclusion arrays mirror it — do not touch the include array itself).

**Phase 2 — the census.** Author `scripts/lib/bs-emitter-row.sh`, run the guard, disposition every discovered file (convert or reasoned allowlist entry), register `run_suite` lines + the `validate-vector-config.yml` run line.

**Phase 3 — green + floors.** All named suites green; floors ratcheted to measured counts; `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` green (locally if `vector` is on PATH/`VECTOR_BIN`, else the CI step); `scripts/lint-orphan-test-suites.sh` clean; `bash scripts/lib/inngest-probe-row.test.sh` still green (its census is unaffected — any file it covers that this PR converts keeps its contract lines).

**Phase 4 — docs.** ADR-286 addendum; vector.toml header comments already updated in Phase 1; PR body first line answers the production-mutation question.

## Files to Edit

- `apps/web-platform/infra/vector.toml` — Source 1 arm `["3","4"]` + two `exclude_matches` maps; Source 2 `exclude_units` narrowed + `exclude_matches.SYSLOG_IDENTIFIER`; comment rewrite of the DOUBLE-ADMISSION/OVERLAP/`#6551`/`#8875` passages.
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — Source-1 arm literal, Source-2 `exclude_units` literal, `#7898` reasoning text, floor ratchet.
- `apps/web-platform/infra/journald-config.test.sh` — `9963d` description text, `9963i` widened to the exclude spelling, new `9963m`/`9963i-bis` exclude-direction pins, `MIN_TOTAL` ratchet.
- `scripts/test-all.sh` — two `run_suite` registrations for the new lint pair.
- `.github/workflows/validate-vector-config.yml` — one `run:` line for the new admission suite.
- `knowledge-base/engineering/architecture/decisions/ADR-286-vector-journald-source-admits-by-or-and-the-systemd-path-control.md` — dated addendum recording the partition decision.
- The caller files the audit converts (population enumerated by the guard at implementation; each converted reader gains the emitter predicate or sources `bs-emitter-row.sh`).

## Files to Create

- `apps/web-platform/test/infra/vector-admission.test.sh` — the admission emulator suite.
- `scripts/lint-betterstack-emitter-read.sh` — the census guard.
- `scripts/lint-betterstack-emitter-read.test.sh` — its mutation battery.
- `scripts/lib/bs-emitter-row.sh` — the generalized emitter-selection lib.

Not edited, by design: `scripts/lib/inngest-probe-row.sh` and its suite (probe-scoped contract stays pinned as-is; the new lib is a sibling), `apps/web-platform/infra/inngest-bootstrap.sh` (the control emit is unchanged — `-t systemd -p err` still lands inside the {3,4} arm), `betterstack-query.sh` (the transport's contract is untouched), Source 3/3b/4/5 definitions (only the exclusion mirrors reference them).

## Open Code-Review Overlap

None relevant. Queried open `code-review` issues (200 limit) on 2026-10-13 and filtered for vector/betterstack/journald/emitter/probe/followthrough/inngest/zot: the nearest are #9705 (inngest wrong-volume alert dead-probe — a probe spec, not a vector.toml or query-reader file) and #8595 (monitor registry guard gaps — different files). No overlap with Files to Edit/Create.

## User-Brand Impact

**If this lands broken, the user experiences:** degraded observability of the agent platform — wrongly narrowed admission silently drops diagnostic channels (a scheduler-host fault reads as silence instead of evidence), or a wrongly widened census false-alarms CI. End-user-visible harm is indirect: a real prod incident diagnosed slower because a channel went dark.
**If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the change NARROWS what ships to the existing EU-region Better Stack source and never bypasses `pii_scrub_*` (the sink's `inputs` and the scrub-chain membership are re-pinned); the census guard reads only repo text.
- **Brand-survival threshold:** `aggregate pattern` (planner choice — `apps/web-platform/infra/` is a sensitive path and the sibling plan's gate wanted non-`none` there; the blast radius is fleet-wide telemetry fidelity, not single-user data; every wrong direction is fail-loud in CI or via the existing `unshipping` verdicts).

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_SYSTEMD_JOURNALD_CONTROL (-t systemd -p err, PRIORITY 3) still rides the Source-1 {3,4} arm on soleur-inngest-prd — the positive control is unchanged; the admission contract itself is a static property whose signal is the CI suite"
  cadence: "control row hourly via inngest-server-probe; admission + census suites per PR"
  alert_target: "Better Stack soleur-inngest source (the --control-require-field 'SYSLOG_IDENTIFIER=systemd' read in betterstack-assert-absence.sh); infra-validation + validate-vector-config CI red on drift"
  configured_in: "apps/web-platform/infra/vector.toml; apps/web-platform/test/infra/vector-admission.test.sh; scripts/lint-betterstack-emitter-read.sh"
error_reporting:
  destination: "CI suite output — census prints UNCLASSIFIED/STALE/BARE-REASON per file; the emulator names the fixture and expected-vs-actual source set; vector validate stderr on a schema break"
  fail_loud: "both guards exit non-zero; floors report '[FATAL]' directly via printf+exit 1, never through the verdict helpers they watch"
failure_modes:
  - mode: "a journald source added with no include constraint (streams the whole journal)"
    detection: "emulator structural pin: every journald source carries >=1 include key; extra_args pinned absent"
    alert_route: "validate-vector-config.yml PR gate"
  - mode: "Source-4 tag list drifts from the exclusion mirrors (a tag double-ships or silently drops)"
    detection: "tokenized set-equality asserts — S1/S2 exclude_matches.SYSLOG_IDENTIFIER == the S4 include array; S1 exclude_matches.CONTAINER_NAME == union(S3,S3b includes)"
    alert_route: "CI red in vector-admission.test.sh"
  - mode: "a new betterstack-query.sh reader selects rows by message substring only"
    detection: "census UNCLASSIFIED verdict + the mutation battery proving discovery/classification fire"
    alert_route: "CI red in lint-betterstack-emitter-read"
  - mode: "the arm narrowing silently drops a shipped class (e.g. vector.service CRIT)"
    detection: "corpus fixtures pin each preserved path — vector.service PRIORITY-1 -> {system_journald}, the control shape -> {inngest_journald}, tagged crit -> {host_scripts_journald}"
    alert_route: "CI red in vector-admission.test.sh"
  - mode: "a 'systemd' member added to an exclude_matches.SYSLOG_IDENTIFIER array (silences the class instead of over-shipping it)"
    detection: "journald-config.test.sh 9963m tokenized never-add over exclude arrays"
    alert_route: "CI red"
logs:
  where: "unchanged channel — journald -> Vector -> pii_scrub_* -> tag_journald/tag_metrics -> Better Stack source 2457081; multiplicity reduced to 1"
  retention: "unchanged (Better Stack source retention); quota direction improves by the removed double-ship"
discoverability_test:
  command: grep vector-admission .github/workflows/validate-vector-config.yml
  expected_output: vector-admission
```

## Encryption Posture

```yaml
at_rest: []
in_transit: []
```

No new store and no new cross-component/network connection. The change narrows the admission set of the existing journald→Better Stack TLS path (`sinks.betterstack` → `s2457081.eu-fsn-3.betterstackdata.com`, Bearer via `BETTERSTACK_LOGS_TOKEN`); rows that still ship traverse the unchanged three-stage `pii_scrub_*` chain — the sink `inputs` pin and the scrub-membership asserts are re-verified by the suites. `exclude_matches` drops rows BEFORE any transform, strictly shrinking the egress surface.

## Guard Contract

### Guard 1 — Every journald record is admitted by an exact, documented set of sources (multiplicity ≤ 1)

**Property.** For every synthesized record in the corpus, the set of admitting journald sources equals the fixture's expectation — and never contains two sources. Equivalently: no shipped row pays double quota, and every row that must ship (control, unit, tag, container, crit) provably still does.

**Assembly.** The single admission emulator in `vector-admission.test.sh`, fed by ONE parse of the real `vector.toml` (tomllib → JSON model; `include_units`/`exclude_units` merged into `_SYSTEMD_UNIT` maps exactly as `JournaldConfig::merged_*_matches` does) — the chokepoint is the merged-match evaluator: every fixture and every future source flows through it. Structural pins cover the non-fixture surface: no `extra_args`, ≥1 include key per journald source, closed sink `inputs`, mirror-array set-equality.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Source-1 arm widened back to `["0".."4"]` | RED: PRIORITY-0-2 untagged fixture admits via {1,2} — multiplicity pin fires |
| 2 | `exclude_matches.SYSLOG_IDENTIFIER` deleted from Source 1 | RED: tagged PRIORITY-4 fixture admits via {1,4} |
| 3 | `exclude_matches.SYSLOG_IDENTIFIER` deleted from Source 2 | RED: tagged PRIORITY-2 fixture admits via {2,4} |
| 4 | `exclude_matches.CONTAINER_NAME` deleted from Source 1 | RED: container stderr fixture admits via {1,3} |
| 5 | vector.service left in Source 2 `exclude_units` | RED: vector.service PRIORITY-1 fixture admits via `∅` — a shipped class silently dropped |
| 6 | the emulator ORs excludes instead of dropping-on-any-match (evaluator bug) | RED: an excluded tagged fixture still resolves to its include source |
| 7 | a new journald source with no include key added to a fixture config | RED: admit-all pin fires (it would ship the entire journal) |
| 8 | `systemd` appended to a Source-4 member list OR an exclude array | RED: 9963h/9963m tokenized never-adds (both directions) |

**Harness rows.** (a) Suite-side mutation that must RED it: force the tomllib parse to emit an empty source map — the corpus then grades everything `∅` and the floor + the must-ship fixtures both fire. (b) Must-PASS inputs that are not canonical: the PRIORITY-6 systemd Started/Stopped row and the untagged PRIORITY-6 cron row assert `∅` (unshipped is a verdict, not an error); the canary stderr row asserts `{inngest_journald}` (pre-existing single-ship, unchanged). (c) Floors: `MIN_CASES` literal + `PASS+FAIL == CASES` conservation + instrument self-test.

**Anchor.** `vector validate --no-environment --config-toml` runs on every vector.toml PR (validate-vector-config.yml); the suite's run line is added to the same workflow (path-filter already covers it); `vector.tf:13` pins the evaluator's reference version 0.43.1.

### Guard 2 — Every `betterstack-query.sh` reader selects by emitter or carries a reason

**Property.** Every tracked non-test invocation of `scripts/betterstack-query.sh` is discovered, and each discovered file either selects rows by `SYSLOG_IDENTIFIER` (direct check, `JSONExtractString`, `--control-require-field`, or a sourced emitter def) or holds an `ALLOW` entry with a non-empty reason; stale entries fail; a population below the floor fails closed.

**Assembly.** `git ls-files` discovery (never a hand list — the #8846 review lesson: a `>= N` floor on a HAND list let the watchdog workflow drop out silently; `MUST_FIND` names the heavyweight readers so discovery regressions are loud) + comment-stripped invocation detection + per-file classification. Chokepoint: the one `census` pass every file flows through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | new raw `--grep` reader added to a fixture tree | RED: UNCLASSIFIED names it |
| 2 | reader calls the def name in a comment only | RED: comment-stripped classification — not a use |
| 3 | allowlist entry for a file that stopped invoking | RED: STALE |
| 4 | allowlist entry with an empty reason | RED: BARE-REASON |
| 5 | guard COPY with the discovery grep deleted, run on an unclassified fixture | GREEN-exit-0 proves the grep IS the mechanism (dispatch row) |
| 6 | guard COPY with `MIN_POPULATION` forced above the live count | exit 2, diagnostic names the floor (not a classification verdict) |
| 7 | doc-mention-only file (`.ts` `//` comment containing `betterstack-query.sh --grep`) | must-PASS: never enters the population — mention is not invocation |
| 8 | a converted reader that gained the emitter check | must-PASS: reclassification is allowed to leave the allowlist via STALE detection driving removal |

**Harness rows.** Must-PASS: compliant reader (both spellings — inline `select(.SYSLOG_IDENTIFIER …)` and sourced `bs-emitter-row.sh`), allowlisted-hint file, empty sandbox (floor keys on the resolved tree, sandbox exempt). Floors: `MIN_ASSERTIONS` + conservation + instrument self-test; all tail floors outside any heredoc-blanked span and self-exiting.

**Anchor.** `run_suite` registration runs the live guard in `test-all.sh` (the same chokepoint every lint pair uses); `scripts/lint-orphan-test-suites.sh` diffs the glob set so the new `.test.sh` cannot silently unregister.

## Infrastructure (IaC)

### Terraform changes

None — no `.tf` edit. `vector.toml` is already a `triggers_replace` input of `terraform_data.journald_persistent` (web-1) and `journald_persistent_web2` (web-2), so the sha move is the intended delivery — no trigger wiring changes.

### Apply path

Code+config only at merge. Web hosts: next `apply-web-platform-infra` run re-delivers the file over SSH + restarts `vector.service` (seconds of buffering — Vector's journald cursor persists in `data_dir`, no row loss). Dedicated inngest host: the file reaches it via the image build + the next sanctioned `inngest-host-replace` dispatch — `inert until dispatched`; no dispatch runs from this PR.

### Host fan-out

Existing provisioners unchanged; no new SSH path.

### Vendor-tier reality check

`exclude_matches` is a documented `JournaldConfig` field on the pinned 0.43.1 surface; `vector validate` schema-checks the new keys in CI. Journald admission is client-side (no journald version dependency).

## Architecture Decision (ADR/C4)

### ADR

`ADR-286` gains a dated addendum (`soleur:architecture`, in-PR task): the deferred semantic decision is taken — the arms are partitioned (`{3,4}`/`{0..2}` disjoint, tag and container exclusions on the armed sources, vector.service's crit path moved to Source 2); the #6551 row's admission is the {3,4} arm, verified; the three double-admission windows are closed; the never-add contract for `systemd` now covers both include and exclude directions.

### C4 views

No C4 change expected — no new external system, container, or data flow (the Vector→Better Stack edge exists); a `c4-count-parity.test.sh` re-run confirms.

## Downtime & Cutover

- **Offline-inducing operations:** none in the PR. Web-host apply performs a `systemctl restart vector.service` inside the existing provisioner — a seconds-scale shipper gap, buffered by the journald cursor; the dedicated host takes the change only on an operator-gated `inngest-host-replace`.
- **Zero-downtime evaluation:** the restart is the pre-existing delivery mechanism; the change itself introduces no new downtime surface.

## Domain Review

**Domains relevant:** none

No cross-domain implications among the eight business domains — infra observability plumbing + lint guards. Technical forks are recorded as `pending - assumed:` rows in `decision-challenges.md` (no Agent tool on this harness); a `soleur:engineering:cto` ruling at review supersedes them. Product/UX gate: no UI-surface file — the mechanical override does not fire. GDPR gate: egress narrows, never widens; scrub chain untouched and re-pinned.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "[#6551] a live Better Stack row ships that NO source in vector.toml admits … Read apps/web-platform/infra/vector.toml carefully (all sources, transforms, routing — including any fallback/default sink or a transform that rewrites fields post-hoc), plus any sibling vector configs" | Hypotheses H1-H7; Research Reconciliation rows 1-3 (all sources + all transforms read; single config confirmed; sinks enumerated — `betterstack` + `vector_console`, no default sink) | mapped |
| 2 | "[#6551] The fix likely needs a regression guard pinning that only admitted fields ship — look for existing test suites covering vector.toml … and follow their conventions" | Proposed Solution 2 (emulator suite) + 3 (suite updates); Guard 1 | mapped |
| 3 | "[#8875] a repo-wide guard over every betterstack-query.sh invocation in tracked scripts — each caller must select rows by SYSLOG_IDENTIFIER (or the sourced emitter def), not message substring, or carry an allowlist entry with a reason … Build on scripts/lib/inngest-probe-row.sh (a sourced jq def for emitter-field selection, generalized)" | Proposed Solution 4 (census pair + generalized lib); Guard 2 | mapped |
| 4 | "[#8875] ~20 non-test callers need audit … an inventory, an allowlist mechanism for legitimate non-emitter readers, and mutation coverage per this repo's conventions" | Proposed Solution 5 (audit + dispositions); Implementation Phase 2 | mapped |
| 5 | "[brief] Output artifacts only under knowledge-base/project/; do NOT implement; commit artifacts only" | Files to Create/Edit list the implementation's files; this plan's own writes stay in knowledge-base/project/; the commit carries only spec+plan artifacts | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Admission partition in vector.toml | "the dedupe fix belongs to #6551" (vector.toml's own assignment, twice) + "the fix likely needs a regression guard" | inferred — justification: the file names #6551 as the dedupe owner; the partition is the dedupe |
| Admission-emulator suite | "a regression guard pinning that only admitted fields ship" | asked |
| Container-stderr exclusion (W4) | — | inferred — justification: discovered while tracing the partition; closing it is required for the multiplicity-≤1 property the dedupe fix defines |
| vector.service un-exclusion on Source 2 | — | inferred — justification: narrowing the arm without it silently drops vector.service CRIT rows (P3: nothing that ships today may stop) |
| Census guard pair + generalized lib | "a repo-wide guard … Build on the shared library #8846 introduces … generalized to any emitter tag" | asked |
| Caller audit + allowlist | "~20 non-test callers need audit … or carry an allowlist entry with a reason" | asked |
| ADR-286 addendum | — | inferred — justification: the ADR explicitly defers "the semantic decision" to these issues; taking it is an architecture record, not a follow-up |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `scripts`, `.github`
- Planned files: ~6 edited + ~30 caller dispositions (audit-bounded) + 4 created | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the caller audit dominates file count but each edit is small and the pair ships as one guard rollout; a split would land the census with no compliant callers)

## Acceptance Criteria

- [ ] `bash apps/web-platform/test/infra/vector-admission.test.sh` exits 0: the #6551 verbatim row (`PRIORITY=3`, `_SYSTEMD_UNIT=init.scope`, `SYSLOG_IDENTIFIER=systemd`, `UNIT=inngest-heartbeat.service`) resolves to exactly `{inngest_journald}`; every corpus fixture admits at multiplicity ≤1; the must-ship fixtures each resolve to their intended single source; the `∅` fixtures (PRIORITY-6 systemd, untagged PRIORITY-6) resolve to no source; floor at measured count.
- [ ] `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` exits 0 (CI step in `validate-vector-config.yml`, which also runs the new suite).
- [ ] `grep -cE 'exclude_matches' apps/web-platform/infra/vector.toml` >= 3 (S1 SYSLOG_IDENTIFIER + CONTAINER_NAME, S2 SYSLOG_IDENTIFIER); the two SYSLOG_IDENTIFIER exclusion arrays tokenize-equal to the Source-4 include array (asserted by the emulator suite, not a bare grep).
- [ ] `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` exits 0 with the ratcheted floor; its Source-1 pin reads `["3", "4"]` and its Source-2 pin reads `exclude_units = ["inngest-server.service"]`.
- [ ] `bash apps/web-platform/infra/journald-config.test.sh` exits 0 with ratcheted `MIN_TOTAL`; `9963i` accepts the `exclude_matches.SYSLOG_IDENTIFIER` spelling; `9963m` pins `systemd` absent from every exclude array.
- [ ] `bash scripts/lint-betterstack-emitter-read.sh` exits 0 on the live tree: every discovered invocation classified (emitter-selected or reasoned allowlist); zero UNCLASSIFIED/STALE/BARE-REASON; every `MUST_FIND` member found.
- [ ] `bash scripts/lint-betterstack-emitter-read.test.sh` exits 0: the mutation battery covers unclassified/stale/bare-reason/comment-mention/dispatch/floor-breach rows; `MIN_ASSERTIONS` + conservation hold.
- [ ] `bash scripts/lib/inngest-probe-row.test.sh` exits 0 — the existing probe census stays green; any file it covers that this PR touches keeps its `[census]` contract lines.
- [ ] `bash scripts/lib/bs-emitter-row.sh --selftest` prints its discoverability literal and exits 0; `scripts/lint-orphan-test-suites.sh` reports no orphans (the new `.test.sh` files are registered via `run_suite`).
- [ ] Re-run of the audited siblings: `bash apps/web-platform/infra/fresh-boot-parity.test.sh`, `workspaces-boot-unlock.test.sh`, `luks-monitor.test.sh`, `inngest.test.sh` exit 0 (their `include_matches.SYSLOG_IDENTIFIER` anchors are unaffected by `exclude_matches` lines).
- [ ] ADR-286 carries the dated addendum; `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
<!-- lint-infra-ignore start -->
- [ ] PR body's FIRST line answers "does merging this mutate production?" (`no — code+config only; vector.toml reaches web hosts on the next apply via the existing journald_persistent triggers_replace, and the dedicated host on the next sanctioned inngest-host-replace — no dispatch, apply, Doppler write, or reboot was run from this branch`), and the body says `Closes #6551` and `Closes #8875`.
<!-- lint-infra-ignore end -->

## Test Scenarios

- Given the verbatim #6551 record fields, when the emulator evaluates the shipped config, then exactly `{inngest_journald}` admits it — the "no source admits" claim is now a CI-checked verdict. (`emulator`, unit)
- Given an untagged host row at PRIORITY 2 (e.g. a `logger -p user.crit` refusal), then only `{system_journald}` admits — the pre-fix answer was {1,2}. (`emulator`, unit)
- Given a tagged emitter row at PRIORITY 4 (`ci-deploy` user.warning) and at PRIORITY 2, then only `{host_scripts_journald}` admits each. (`emulator`, unit)
- Given container stderr (`CONTAINER_NAME=soleur-web-platform`, PRIORITY 3) and egress-gw stderr, then only `{app_container_journald}`/`{egress_gw_journald}` admit — the discovered W4 window is closed. (`emulator`, unit)
- Given canary stderr (`CONTAINER_NAME=soleur-web-platform-canary`, PRIORITY 3), then `{inngest_journald}` still admits — pre-existing single-ship unchanged, pinned so a "fix" that orphans it is loud. (`emulator`, unit)
- Given a `vector.service` row at PRIORITY 1, then `{system_journald}` admits — the moved crit path is exercised, not just grepped. (`emulator`, unit)
- Given the `SOLEUR_SYSTEMD_JOURNALD_CONTROL` shape (`-t systemd -p err` → PRIORITY 3, `SYSLOG_IDENTIFIER=systemd`), then `{inngest_journald}` admits — the positive-control channel survives the partition. (`emulator`, unit)
- Given a PRIORITY-6 `systemd` Started/Stopped row, then `∅` admits — the never-ship class stays unshipped. (`emulator`, unit)
- Given a fixture config whose Source-1 arm is restored to `{0..4}`, when the suite runs, then the multiplicity pin fails — the drift direction the whole change exists to catch. (`mutation`, unit)
- Given a tracked file adding `betterstack-query.sh --grep FOO` with no emitter check, when the census guard runs, then it exits 1 naming the file UNCLASSIFIED. (`census`, unit)
- Given an allowlisted reader whose invocation is removed, when the census runs, then it exits 1 with STALE — dead allowlist entries cannot silently widen the exempt class. (`census`, unit)
- Given a `.ts` file whose only mention is a `//` comment containing `betterstack-query.sh --grep`, when the census runs, then the file never enters the population — mention is not invocation. (`census`, unit)
- Verification (read-only, local, no dispatch): `bash apps/web-platform/test/infra/vector-admission.test.sh`, `bash scripts/lint-betterstack-emitter-read.sh`, `bash scripts/lint-betterstack-emitter-read.test.sh`, `bash apps/web-platform/infra/journald-config.test.sh`, `bash scripts/lib/inngest-probe-row.test.sh`.

## Dependencies & Risks

- **Evaluator-fidelity risk (the emulator is a model of Vector semantics, not Vector itself).** Mitigated by: the semantics are pinned to the 0.43.1 `journald.rs` reading (ADR-286) and `vector.tf:13` pins that version; `vector validate` schema-checks the config; the suite fails loudly on a config key it does not model (unknown `include_matches.*`/`exclude_matches.*` fields force the emulator to grow rather than silently mis-evaluate). Residual: a Vector version bump could change semantics — recorded in the ADR-286 addendum and the suite header.
- **tomllib availability.** `python3 >= 3.11` is required for `tomllib`; local toolchain is 3.15.0. If a runner carries older python3, fall back to the awk/sed extraction the sibling suites use — the decision row records this as `pending - assumed:`.
- **Caller-audit size.** ~55 non-test files carry invocation-shaped lines; after comment-stripping and doc-only exclusion the reader population is expected at ~20-30. Each disposition is small; the risk is a misclassified reader — mitigated by fail-closed classification (unknown shape = UNCLASSIFIED) and per-file reasons naming call sites.
- **Overlap with the delivered `#9963` contract.** The 9963 pins in `journald-config.test.sh` must be widened carefully — `9963i`'s canonical-form pin will go RED on the new `exclude_matches.SYSLOG_IDENTIFIER` lines until widened, which is the intended RED; `9963m` adds the silence direction. `PRIORITY_ARM_EXEMPTIONS`'s `systemd` entry in `vector-pii-scrub.test.sh` stays valid — the control still rides the {3,4} arm.
- **Suite-file hygiene (`guard-vacuity-floor` defect class).** New `.test.sh` text must never carry a bare `<<`/`<<<` outside a real heredoc (needle strings assembled via `_lt='<'`), and every floor must sit outside any heredoc-blanked span, self-exiting with `printf` + `exit 1`.
- **Order-of-delivery skew.** After merge but before the next web-host apply, web-1/web-2 keep the old config while CI enforces the new one — a benign skew (the old config still ships; it double-ships, which is the pre-existing state). The dedicated host keeps the old config until replace — likewise benign; `vector_config_identity` lets the live-vs-repo sha be checked no-SSH at any time.
