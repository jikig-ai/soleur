# Tasks — fix(cutover): scope op=resume G3 host-audibility to the current server generation

Plan: `knowledge-base/project/plans/2026-09-24-fix-cutover-resume-g3-current-host-scope-plan.md`
(deepened 2026-09-24).

## 1. Setup

- [ ] 1.1 Baseline: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` (753/0).
- [ ] 1.2 Baseline: `shellcheck -S warning scripts/cutover-inngest.sh` (3 findings).
- [ ] 1.3 Baseline: `bash scripts/lint-diagnosis-claims.sh` (baseline 1).

## 2. RED (one commit: test file only)

- [ ] 2.1 Define top-level fixture variables:
  - [ ] a synthetic `created` in `+00:00` form, with the floor derived from it once;
  - [ ] give `rows`, `foreign` and `spoofed` an event time and `dt` after `created`.
- [ ] 2.2 Make the `doppler()` mock branch on ARGUMENTS first:
  - [ ] `secrets get HCLOUD_TOKEN_READONLY` / `HCLOUD_TOKEN` return sentinels;
  - [ ] `run … betterstack-query.sh` returns the mode's rows;
  - [ ] Better Stack argv and HCLOUD reads go to separate record files.
- [ ] 2.3 Add a mocked `curl()`:
  - [ ] per-call argv, stdin and exit files, truncated before each call;
  - [ ] the real Hetzner list shape plus `\n<code>`.
- [ ] 2.4 Add a `curl` `exit 99` stub to every harness, including `call_flush_latch_count`.
- [ ] 2.5 Add mode `predecessor` (event time AND `dt` before `created`) and assert `'0'`.
- [ ] 2.6 Bump `_EXACT_FLOOR` in the same commit. The only FAIL must be `predecessor`; quote it.

## 3. GREEN

- [ ] 3.1 Add `_hcloud_created_epoch` (pure):
  - [ ] exact-one name match;
  - [ ] normalize `+00:00` to `Z`;
  - [ ] all jq `2>/dev/null`;
  - [ ] print `__ABSENT__` or `__UNREADABLE__` on failure.
- [ ] 3.2 Add `_inngest_server_created_epoch` (I/O):
  - [ ] read `HCLOUD_TOKEN_READONLY`, then fall back to `HCLOUD_TOKEN`;
  - [ ] if both are empty, warn and skip curl;
  - [ ] `::add-mask::` the token on STDERR;
  - [ ] send it through `printf … | curl -s --proto =https --max-time 20 --get --data-urlencode "name=$INNGEST_HOST" -H @- -w '\n%{http_code}' 2>/dev/null`;
  - [ ] no `-f`, no `-S`, no `--retry`;
  - [ ] split body and code; name the HTTP and rc class in the warning;
  - [ ] epoch bounds: at least 2025-01-01 and at most now+300 s;
  - [ ] always return 0.
- [ ] 3.3 Add `_current_instance_row_counts` (pure): print `<counted> <host_pair> <pre_floor> <malformed> <skew_suspect>`.
  - [ ] Count a row only when its `__REALTIME_TIMESTAMP` ≥ floor×1e6 AND its `dt` ≥ floor.
  - [ ] Pass the floor via `--argjson` after a `^[0-9]+$` check.
- [ ] 3.4 Rewrite `_flip_liveness_count` and `_luks_liveness_count`:
  - [ ] read the anchor first; on failure print `__UNREADABLE__` and skip the Better Stack read;
  - [ ] keep the `rows=$(_bs_query_rows …)` line;
  - [ ] stdout is the first counter only;
  - [ ] stderr gets the breakdown notice (validated values only) and, when counted=0 and age < 600, the young-server warning.
- [ ] 3.5 Write the rationale comment covering AP-027, the invariants, the two-clock conjunct, the exemptions and why H is floored. Stay out of L50–L90 (PR #8690).
- [ ] 3.6 In the harness, awk-extract and eval the three new functions, with non-vacuity asserts.

## 4. Wording, coverage, architecture, runbook

- [ ] 4.1 Reword the resume/LUKS `unreadable` arms to point at the `::warning::` above.
- [ ] 4.2 Make the resume `silent` replace advice conditional on age > 10 min AND counted=0.
- [ ] 4.3 Run `scripts/lint-diagnosis-claims.sh`; the count must stay within baseline.
- [ ] 4.4 Guard 1 rows:
  - [ ] `current`, `mixed` (both orders), `no-ts`, `no-ts+2current`;
  - [ ] `late-ingest`, `clock-ahead-predecessor`, `anchor-late`, `anchor-*`;
  - [ ] `epoch-pre-2025`, `epoch-future`;
  - [ ] the boundary pair;
  - [ ] a LUKS harness (`predecessor`/`current`);
  - [ ] an executed unfloored-latch row;
  - [ ] H1/H2.
- [ ] 4.5 Guard 2 rows:
  - [ ] the decode table;
  - [ ] token only on stdin plus one mask line;
  - [ ] body sentinels (200 non-decodable, 503);
  - [ ] distinct 401/429/503 warnings;
  - [ ] read-only-first order and the fallback;
  - [ ] both names empty means no curl call;
  - [ ] returns 0 under `set -e`;
  - [ ] transport argv pins.
- [ ] 4.6 Guard 3 rows:
  - [ ] the stdout-token shape;
  - [ ] notice fields;
  - [ ] the young-vs-old warning;
  - [ ] a forged `created` never reaches an annotation;
  - [ ] the conditional replace advice.
- [ ] 4.7 Invariant pins: no `create_before_destroy`; no `current_boot_only = false`; no `actions/rebuild` for the inngest server.
- [ ] 4.8 jq self-check row: `fromdateiso8601` and `strptime|mktime` values.
- [ ] 4.9 Confirm the existing pins stay green unmodified (AC8), then set `_EXACT_FLOOR` to the measured count.
- [ ] 4.10 Amend ADR-225 §4, citing AP-027 (ADR-149), ADR-241 D4 and ADR-199, and list the alternatives. Use `soleur:architecture`.
- [ ] 4.11 Add a `github -> hetzner` Cloud API edge to `model.c4` (plus a views include if needed). Run `c4-code-syntax`, `c4-render` and `c4-count-parity`.
- [ ] 4.12 Update `knowledge-base/engineering/operations/runbooks/inngest-server.md` §op=resume G3.
- [ ] 4.13 Confirm shellcheck shows no new findings.

## 5. Verification

- [ ] 5.1 Run the read-only live replay: floor 0 vs floor `created`, over one 18 h `noop-` row set. Put both 5-integer lines in the PR body.
- [ ] 5.2 Run the full suite and confirm it exits 0.
- [ ] 5.3 Walk AC1–AC13.
