#!/usr/bin/env bash
# lint-betterstack-emitter-read.sh — the #8875 census guard. Every tracked non-test file
# that INVOKES scripts/betterstack-query.sh — directly or through a seam — must either
# select rows by the journald emitter field or carry an allowlist entry with a reason.
#
# WHY. The `raw` column betterstack-query.sh returns is a double-encoded journald record. A
# reader that selects rows by message substring admits ANY emitter whose payload quotes the
# needle — doppler event-log rows quote issue/PR/comment text verbatim, which is exactly how
# a marker named in a GitHub body counted as an emission. The defect has recurred three
# times (#6475, the 2026-09-17 inngest-host-state.sh false "VERDICT NOT SERVING", #8846);
# #8846 fixed the one marker's readers and deferred this repo-wide census here.
#
# DISCOVERY (two stages, both mechanical — never a hand list):
#   1. `git ls-files` under TREE, minus the doc/test exclusions below and minus this guard
#      pair itself. The producer is the tracked set, so a file added but never committed is
#      invisible — the same lesson varq-ban learned for `-e` vs `git ls-files` (#7490).
#   2. Per file, comments are stripped FIRST (the strip is load-bearing — see below), then a
#      file enters the population when a non-comment line carries `betterstack-query.sh`
#      adjacent to invocation shape — an assignment (`VAR=...betterstack-query.sh`), a mode-2
#      flag (`--grep`/`--since`/`--until`/`--limit`/`--raw-only`/`--no-archive`/`--table`),
#      a `doppler run`/`bash`/`env` exec context, or a `SELECT` — OR when its code calls a
#      known transport seam (`bs_absence_query_script`, `_bs_query_rows`, `run_bq`), which is
#      how lib consumers reach the transport without ever naming it. Doc-mention-only files
#      (path lists, prose strings, comment recipes) never enter the population.
#
# COMMENT STRIPPING IS LOAD-BEARING. `.sh`/`.yml`/`.tf`/`*.py` full-line `#` comments are
# blanked (line numbers preserved — the varq-ban `grep -n`-on-raw-first lesson); C-family
# files (.ts/.js and friends) are stripped of `//` line comments and `/* ... */` blocks with a
# state machine. e.g. apps/web-platform/server/cron-liveness-marker.ts mentions the query
# only inside `//` comments and must never enter the population. Recorded residual: the `//`
# cut runs before string-awareness, so a `.ts` line whose needle sits after a `//` INSIDE a
# string literal would be missed — no live file does this; the direction is fail-open only for
# an exotic shape, never for a comment mention (the measured class).
#
# CLASSIFICATION (per FILE — per-invocation binding was ruled out by the CTO: a `$QUERY`/`$BQ`
# seam cannot be bound statically to its consumer line in bash). A discovered file is:
#   OK-EMITTER      — its non-comment code carries an emitter check: `SYSLOG_IDENTIFIER` in a
#                     jq `select(...)`, a `JSONExtractString(raw,'SYSLOG_IDENTIFIER')`, a
#                     `.SYSLOG_IDENTIFIER`/`get("SYSLOG_IDENTIFIER")`/`os.environ` read, a
#                     serialized-field needle (`SYSLOG_IDENTIFIER":"` / `SYSLOG_IDENTIFIER=` /
#                     an escaped `SYSLOG_IDENTIFIER\"`), a `SYSLOG_IDENTIFIER //` jq
#                     extraction, a `--control-require-field` flag (the closed field form
#                     betterstack-assert-absence.sh already speaks), or a source/def use of
#                     scripts/lib/{bs-emitter-row,inngest-probe-row}.sh or
#                     tests/scripts/lib/inngest-host-dark-gate.sh.
#   OK-ALLOWLISTED  — it holds an ALLOW[<path>]="<reason>" entry below; the reason records
#                     WHY emitter selection does not apply (hint-only text, the transport
#                     itself, a field-scoped read on another axis, an any-emitter property,
#                     or a recorded residual).
#   UNCLASSIFIED    — neither → exit 1. A NEW raw `--grep` reader fails CI here.
#   STALE           — an allowlisted file no longer discovered → exit 1 (dead entries cannot
#                     silently widen the exempt class).
#   BARE-REASON     — an allowlist entry with an empty reason → exit 1.
#   MUST-FIND-MISSING — a MUST_FIND member not discovered → exit 1 (the #8846-review lesson:
#                     a `>= N` floor alone let a heavyweight reader drop out silently).
#
# THE ALLOWLIST IS THE AUDIT. Each reason names the call site and the mechanism that makes
# the file honest (envelope anchor, decoded-field select, host-scoped SQL, hint-only). Entries
# marked `residual:` are reads that DO still substring-match — they are recorded rather than
# papered over; emitter conversion is the caller-side disposition. ALLOW is checked BEFORE the
# emitter classifier so a file whose entry documents a partial exemption (the asymmetry in
# betterstack-assert-absence.sh) reports via its reason instead of hiding behind the check.
#
# ALLOWLIST OVERRIDE (test seam): EMITTER_READ_ALLOW_FILE points at a tab-separated
# `path<TAB>reason` file that REPLACES the embedded map — the mutation battery drives the
# real guard over fixture trees carrying their own allowlists. Production CI never sets it.
#
# FLOORS (production tree only — keyed on the RESOLVED tree so an explicit real-path arg
# cannot bypass them): MIN_POPULATION guards the discovery regex (a broken needle reports
# clean over a corpus it cannot see); breach exits 2 with a printf diagnostic, never a
# verdict line.
#
# Usage:  lint-betterstack-emitter-read.sh [TREE]
#   no arg -> censuses the repo checkout (production run; population floor + MUST_FIND live)
#   TREE   -> censuses that git worktree verbatim (the .test.sh points it at mktemp fixtures)
#
# Exit: 0 = every discovered file classified; 1 = UNCLASSIFIED/STALE/BARE-REASON/MUST-FIND
#       violations; 2 = internal error (not a git tree, unreadable allowlist, population
#       floor breach).

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
TREE="${1:-$REPO_ROOT}"

if [[ ! -d "$TREE" ]]; then
  printf '[FATAL] emitter-read census: tree not found: %s\n' "$TREE" >&2
  exit 2
fi
# The file list comes from git ls-files — TREE must be (or sit inside) a worktree.
TREE_ROOT="$(git -C "$TREE" rev-parse --show-toplevel 2>/dev/null)" || {
  printf '[FATAL] emitter-read census: %s is not inside a git worktree (git ls-files is the producer)\n' "$TREE" >&2
  exit 2
}
resolve() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
is_prod="no"
[[ "$(resolve "$TREE_ROOT")" == "$(resolve "$REPO_ROOT")" ]] && is_prod="yes"

WORK="$(mktemp -d -t bs-emitter-read.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# The allowlist. ALLOW[<repo-relative path>]="<reason naming the call site + mechanism>".
# Reseeded from EMITTER_READ_ALLOW_FILE (path<TAB>reason lines) when the test seam is set.
# ---------------------------------------------------------------------------
declare -A ALLOW=(
  # --- the transport and its immediate seams ------------------------------------------------
  ["scripts/betterstack-query.sh"]="the transport itself — the census's subject, not a reader"
  ["scripts/betterstack-assert-absence.sh"]="residual, recorded per the #8875 CTO ruling: the control arm is already field-closed (--control-require-field -> JSONExtractString(raw,'<name>')='<value>', :202-213) while the absence arm is substring-only raw LIKE (:177) — the asymmetry is that a forged absence-arm match reads 'present' (fail-SAFE) whereas a forged control match would read 'clean' (the dangerous direction the field option exists to close); an --absence-require-field option reusing that machinery is the stricter follow-up"
  ["scripts/lib/betterstack-absence.sh"]="transport-resolver lib: bs_absence_query_script() (:48-56) returns the query path to consumers; its own control read is deliberately NOT producer-anchored — 'is the warehouse receiving anything at all' is emitter-agnostic by property"
  ["scripts/lib/git-data-boot-signal-poll.sh"]="reaches the transport via the bs_absence_query_script seam (:104,:145); its SQL field-extracts stage/host_name/luks_* via JSONExtractString (:62-74) — field-scoped on the boot-signal axis, not the emitter axis"

  # --- hint-only references (operator-facing recipe text; nothing consumes rows) -------------
  ["apps/web-platform/infra/infra-config-gate.sh"]="hint-only: the sole invocation-shaped line is the operator-facing 'next: doppler run ... --grep SOLEUR_INFRA_CONFIG_FATAL' error string (:523)"
  [".github/workflows/apply-deploy-pipeline-fix.yml"]="hint-only: the reference is remediation text inside an ::error:: string (:2108); the step reads no rows"
  [".github/workflows/apply-web-platform-infra.yml"]="hint-only: betterstack-query.sh references are remediation text inside ::error:: strings (e.g. :3664)"
  [".github/workflows/build-inngest-bootstrap-image.yml"]="hint-only: _ptr evidence strings embed the query recipe for the operator (:741,:743)"
  [".github/workflows/scheduled-zot-restart-loop.yml"]="hint-only: references live in remediation printf blocks; BETTERSTACK_QUERY_* env there feeds betterstack-ingest-probe.sh (the write probe) and, since #7521, the fill-rate probe step, which reads rows only through scripts/followthroughs/zot-fill-rate-7341.sh (envelope-anchored, its own entry below)"
  ["scripts/registry-heartbeat-poll.sh"]="hint-only: the reference sits inside a diagnostic heredoc listing reproduce commands (:203)"
  ["scripts/followthroughs/inngest-soak-6178.sh"]="hint-only: BETTERSTACK_HINT (:196) is an operator-facing recipe string interpolated into error text; the probe reads Sentry/issue state, never query rows"
  ["scripts/followthroughs/l3-probe-armed-6438.sh"]="hint-only: 'Diagnose:' echo string (:125); the probe reads the Better Stack REST API, not query output"
  ["scripts/followthroughs/web2-standby-soak-6459.sh"]="hint-only: 'Diagnose:' echo string (:156); the soak reads the Better Stack REST API status, not query output"
  ["scripts/followthroughs/zot-soak-6122.sh"]="hint-only: references are FAIL/PASS echo text embedding the query recipe (:479,:695)"

  # --- evidence capture (rows are artifacts for an operator, not verdict inputs) -------------
  [".github/workflows/reusable-release.yml"]="evidence capture: :1325 tees the --grep SOLEUR_ZOT_DISK read to a log artifact for the operator; no verdict consumes row identity. Remaining references are echo hints (:1096-1123)"

  # --- field-scoped reads on a non-emitter axis (own-field extraction defeats the quote
  #     forgery class; the SYSLOG_IDENTIFIER axis specifically is not what binds the verdict) --
  [".github/workflows/git-data-cutover.yml"]="host-field-scoped: WHERE binds JSONExtractString(raw,'host_name') IN (...) (:544-545) before the git_data_store= presence check; residual: the marker substring is unanchored, so a foreign-emitter row on the named host quoting it could false-positive — emitter conversion is the caller-side disposition"
  ["scripts/followthroughs/git-data-rehearsal-evidence.sh"]="host-field-scoped: both SQL reads bind JSONExtractString(raw,'host_name') (the web hosts, then 'soleur-git-data' with JSONExtractString(raw,'stage')='boot_complete') inside a closed dt window before any substring count, and the output is counts/timestamps only (no row reaches the block); residual, the same one the cutover workflow's own readback records: the git_data_* substring is unanchored, so a foreign-emitter row on a named web host that quotes it could inflate a count or supply a well-formed fingerprint — the rehearsal record is read by the owner against the replace run's printed fingerprint"
  ["scripts/followthroughs/anthropic-admin-key-6297.sh"]="field-scoped: decodes .raw|fromjson and selects on the message object's own fields (.SOLEUR_CLAUDE_COST_DAILY == true, .component == 'claude-cost', :115) — a quoting emitter's string-typed message cannot satisfy"
  ["scripts/followthroughs/anthropic-double-bill-8611.sh"]="field-scoped SQL: JSONExtractString(raw,'message','component') = 'claude-cost' (:86-93) — sub-field extraction, not substring"
  ["scripts/followthroughs/cert-reissue-markers-6698.sh"]="field-keyed grep on the DECODED inner object: '\"source_kind\":\"app_container\"' (:53) is a top-level key of the emitted JSON — a quoting row's nested text cannot set it"
  ["scripts/followthroughs/compound-promote-draft-edit-10552.sh"]="field-scoped: GRADE_JQ decodes .raw|fromjson|.message and selects on the message object's own fields (SOLEUR_COMPOUND_PROMOTE_OUTCOME == true and fn == 'cron-compound-promote'), so a row that merely quotes the marker text as a string cannot be graded; the --grep pattern is only a transport pre-filter"
  ["scripts/followthroughs/compound-promote-outcome-8281.sh"]="field-scoped: decodes .raw|fromjson|.message and selects on the message object's fields (:101-102)"
  ["scripts/followthroughs/inngest-luks-keeper-dark-11265.sh"]="field-scoped: the --grep read (:103) is only a prefilter; every returned row is decoded (.raw|fromjson|.message) and counted only when the decoded message starts with the producer marker (:114-121), the same position-1 anchor the paging SQL uses, so a message that merely contains the marker text never counts; no emitter-field scope (the marker is the producer's own)"
  ["scripts/followthroughs/inngest-hostmetrics-trim-11602.sh"]="field-scoped SQL on the tags axis, no emitter field by construction: host_metrics metric rows ship in native Vector shape (tags.host/tags.collector/name/gauge.value — top-level host, host_name and SYSLOG_IDENTIFIER are all absent), so the emitter axis is empty on this source. The server-side GROUP BY binds JSONExtractString(raw,'tags','host') = 'soleur-inngest' WHERE-side (:127) and the verdict reads only the aggregate's own c/n fields; a quoting journald row has no tags.collector and can never enter the collector set"
  ["scripts/followthroughs/git-data-birth-emitter-6982.sh"]="field-scoped SQL: JSONExtractString(raw,'stage') = 'boot_complete' AND host_name equality (:83-84) — field predicates, not message substring"
  ["scripts/followthroughs/git-data-rung2-evidence-capture.sh"]="field-scoped SQL: JSONExtractString extraction of stage/host_name/rc/luks_* fields with host_name in the WHERE (:589-650)"
  ["scripts/egress-audit-retention-check.sh"]="field-scoped SQL: JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-egress-gw' on the container axis, plus a status allowlist and canary workspace ids; the verdict can only FAIL on a match (n>0 means ingest is not landing), so a forged or quoting row can raise a false alarm but never a false pass"
  ["scripts/followthroughs/hosted-destroy-ask-window-9776.sh"]="field-scoped: selects .CONTAINER_NAME == \$c and the message object's .decision prefix on the decoded row (:129-132) — container axis, not substring"
  ["scripts/followthroughs/hostname-mislabel-web1-6616.sh"]="field-scoped SQL: JSONExtractString(raw,'host_name')/'host' GROUP BY read (:93-98); the verdict keys on host fields, not marker text"
  ["scripts/followthroughs/image-cve-scan-window-9826.sh"]="field-scoped: decoded selects .message == \$m and .marker == \$m (:95-97) — equality on the row's own fields"
  ["scripts/followthroughs/inngest-private-nic-8539.sh"]="field-scoped: decoded .marker == <marker> and .stage prefix selects (:50-52)"
  ["scripts/followthroughs/inngest-tls-soak-10136.sh"]="field-scoped on the DECODED direct-POST envelope, no SYSLOG_IDENTIFIER by construction: the tls-health rows are phone-home POSTs built by inngest-boot-phone-home.sh ({message, marker, stage, detail, host, dt, shipper}), not journald records. The jq projection selects .marker == SOLEUR_INNGEST_BOOT_STAGE, .stage == tls-health and .shipper == cloud-init-phone-home (equality on the row's own fields, one CHECK-ISO-* line each), and a second step requires exactly ONE distinct decoded .host over the window (more than one, or an empty host, is CANNOT ESTABLISH exit 3) — a row that merely QUOTES the stage string, or a foreign writer sharing the series, cannot satisfy it; the suite proves each clause with a foreign-row fixture"
  ["scripts/followthroughs/inngest-provision-unit-8562.sh"]="field-scoped: decoded .marker == \$m and .host == \$h plus a stage-shape regex (:117-121)"
  ["scripts/followthroughs/inngest-zot-boot-7462.sh"]="field-scoped: decoded .marker == <marker> select on .raw|fromjson (:130) — the verdict keys on the row's own marker field"
  ["scripts/followthroughs/run-report-exit-first-contact-8076.sh"]="field-scoped: decoded .component select on the message object (:87-95)"
  ["scripts/followthroughs/send-failed-alert-probe-8097.sh"]="field-scoped SQL via run_bq: JSONExtractString(raw,'PRIORITY') = '2' plus a jq regex on the row's own msg field and a host equality check (:274-284)"
  ["scripts/followthroughs/zot-upload-ceiling-7556.sh"]="field-scoped decode: the python decoder extracts inner['message']/dt and VALIDATE_PY rejects non-row shapes (:141-179); verdict arms key on parsed func/message fields"
  ["scripts/followthroughs/zot-log-channel-7440.sh"]="envelope-anchored on the DECODED message: awk keys verdict fields on index(m, envpfx) == 1 with envpfx 'SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<h> ' (:139,:396) — a quoting row cannot satisfy the anchored prefix"
  ["scripts/probe-inngest-524-count.sh"]="field-scoped: the SQL WHERE binds JSONExtractString(raw,'_SYSTEMD_UNIT') (:35,:42) — unit-axis selection; the emitter axis is not what the count predicate reads"
  ["scripts/followthroughs/inngest-trace-retention-5150.sh"]="field-scoped on the decoded journald object: _SYSTEMD_UNIT equality to inngest-trace-retention.service and message equality to INNGEST_TRACE_RETENTION_OUTCOME=ok. The unit sets no SyslogIdentifier, so the emitter axis is not what binds the verdict. A doppler row that quotes both tokens cannot satisfy the field equality; the suite proves that shape"
  ["scripts/inngest-key-rotate.sh"]="field-scoped on the DECODED direct-POST envelope, no SYSLOG_IDENTIFIER by construction (kr_tls_rows, mirroring the inngest-tls-soak-10136.sh isolation): the tls-health rows are phone-home POSTs, not journald records. The jq projection selects .marker == SOLEUR_INNGEST_BOOT_STAGE, .stage == tls-health, .shipper == cloud-init-phone-home and .host == soleur-inngest (equality on the row's own fields); a failed read or an unparseable result is a read fault (no verdict), never a NOT SERVING claim. The host-state read goes through scripts/inngest-host-state.sh, which is OK-EMITTER on its own. The unverified part is whether live rows carry the .host field; a row without it yields no new boot_id and the run ends host_silent, not a false pass"

  # --- envelope-anchored readers (the #7569 producer-shape discriminator: '"raw":"{\"message\":"MARKER "'
  #     is a position-anchored prefix on the raw envelope; a journald/webhook row quoting the
  #     marker buries it in a nested field and cannot satisfy the prefix) ----------------------
  ["scripts/zot-disk-sample.sh"]="envelope-anchored: rows accepted only via the '\"raw\":\"{\"message\":\"SOLEUR_ZOT_DISK \" prefix (:69) — the direct-POST producer shape"
  ["scripts/zot-inventory-assert-marker.sh"]="anchored on the decoded message: ^<marker> run_id= on .raw|fromjson|.message (:195) — a quoting emitter's string-typed message starts '{' and cannot satisfy the anchor"
  ["scripts/zot-restart-loop-alarm.sh"]="envelope-anchored via zot_envelope_anchor (:471) and the SOLEUR_PRIVATE_NIC raw-envelope prefix (:251); the control arm routes through bs_absence_classify"
  ["scripts/followthroughs/private-nic-converged-6415.sh"]="envelope-anchored '\"raw\":\"{\"message\":\"SOLEUR_PRIVATE_NIC ' (:50)"
  ["scripts/followthroughs/zot-fill-rate-7341.sh"]="envelope-anchored '\"raw\":\"{\"message\":\"SOLEUR_ZOT_DISK ' guard (:130) ahead of every verdict read"
  ["scripts/followthroughs/zot-last-err-redact-7500.sh"]="envelope-anchored (:149, mirrors zot_envelope_anchor from scripts/lib/zot-telemetry-parse.sh)"
  ["scripts/followthroughs/registry-htpasswd-stdin-10119.sh"]="envelope-anchored via zot_envelope_anchor (scripts/lib/zot-telemetry-parse.sh, :151) ahead of every verdict read; each field is then read from the decoded message cut at its FIRST ' zot_last_err=' (:156-160), and a row that merely quotes the marker never passes the anchor"
  ["scripts/followthroughs/registry-clientip-alert-7530.sh"]="two honest reads: (1) the SOLEUR_ZOT_DISK boot read is anchored on the DECODED message at offset 0 (jq startswith(\"SOLEUR_ZOT_DISK \")) and host-scoped on the trusted head, exactly like the 10119 probe; (2) the four raw-SQL engine reads are the COMMITTED alert predicate extracted from betterstack-logs-alerts.tf, whose WHERE is producer-anchored at offset 0 of the stored raw (startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ') OR startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ')) — a quoting journald row starts {\"PRIORITY\" and cannot satisfy it; the suite pins the SQL sent against the committed text"
  ["scripts/followthroughs/registry-luks-live-8386.sh"]="envelope-anchored '\"raw\":\"{\"message\":\"<marker> ' (:317, mirrors zot_envelope_anchor)"

  # --- any-emitter by property ---------------------------------------------------------------
  ["scripts/followthroughs/betterstack-roundtrip-latency-7855.sh"]="any-emitter by property: it measures ingest round-trip latency on its OWN synthetic marker row read back through the source (:361-362 startswith on the decoded message); the emitter tag of the echoed row is not what is measured"

  # --- recorded residuals: substring readers whose dispositions are caller-side conversion ---
  [".github/workflows/inngest-config-drift.yml"]="residual: newest-matching --grep SOLEUR_INFRA_PULL_APPLIED digest read (:62-63) — the marker substring is unanchored, so a foreign-emitter row quoting it could feed a wrong digest; emitter conversion is the caller-side disposition under #8875"
  ["scripts/registry-replace-preflight.sh"]="residual: probe() --grep count reads over registry=local-cache|ghcr-fallback phrases (:204-255) are unanchored substrings; emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh"]="residual: --grep + 'command not allowed' substring counts (:64,:84) are unanchored; emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/inngest-watchdog-functions-query-6407.sh"]="residual: --grep SOLEUR_INNGEST_LIVENESS_VERDICT rows graded by mode= substring greps (:87-101); emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/ship-merge-mergebase-verdict-8151.sh"]="residual: decoded .message substring grep (:95-96) — a quoting row's string-typed message can carry the marker; emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/workspaces-luks-soak-6604.sh"]="residual: --grep 'luks-monitor' + 'OK:' substring count on raw output (:96-110); emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/zot-login-gate-names-failure-6497.sh"]="residual: --grep ZOT_GATE/PRELUDE rows graded by unanchored substring patterns on raw (:92-105); emitter conversion is the caller-side disposition under #8875"
  ["scripts/followthroughs/zot-restart-plateau-6288.sh"]="residual: --grep SOLEUR_ZOT_DISK rows pass through zot_trusted_region (sort + free-text-tail strip) with NO envelope anchor; emitter conversion is the caller-side disposition under #8875"
)

# Test seam: a tab-separated `path<TAB>reason` file REPLACES the embedded map so fixture
# trees can carry their own allowlist (empty file = no exemptions). Production never sets it.
if [[ -n "${EMITTER_READ_ALLOW_FILE:-}" ]]; then
  if [[ ! -r "$EMITTER_READ_ALLOW_FILE" ]]; then
    printf '[FATAL] emitter-read census: allowlist override not readable: %s\n' "$EMITTER_READ_ALLOW_FILE" >&2
    exit 2
  fi
  ALLOW=()
  while IFS= read -r _al_line; do
    [[ -n "$_al_line" ]] || continue
    _al_path="${_al_line%%	*}"
    _al_reason=""
    [[ "$_al_line" == *"	"* ]] && _al_reason="${_al_line#*	}"
    ALLOW["$_al_path"]="$_al_reason"
  done < "$EMITTER_READ_ALLOW_FILE"
  unset _al_line _al_path _al_reason
fi

# ---------------------------------------------------------------------------
# Discovery predicates (ERE). INV_NAME is the needle; INV_SHAPE is the adjacency set. SEAM_RE
# catches consumers that reach the transport through a helper and never spell its name.
# ---------------------------------------------------------------------------
INV_NAME='betterstack-query\.sh'
# Line-level shapes that make a name-bearing line an invocation: a variable assignment, a
# mode-2 flag, a doppler/bash/sh/env exec context, or raw-SQL SELECT on the same line.
INV_SHAPE='(^|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=|--(grep|since|until|limit|raw-only|no-archive|table)([[:space:]]|=|$)|doppler[[:space:]]+run|(^|[[:space:];|&(])(bash|sh|env)[[:space:]]|SELECT[[:space:]]'
SEAM_RE='(^|[^A-Za-z0-9_])(bs_absence_query_script|_bs_query_rows|run_bq)([^A-Za-z0-9_]|$)'

# Emitter-check alternatives on the file's non-comment code (a match anywhere classifies the
# file OK-EMITTER). Assembled in pieces so each fragment stays grep-readable.
EMITTER_RE="select\\([^)]*SYSLOG_IDENTIFIER"                       # jq select on the field
EMITTER_RE+="|\\.SYSLOG_IDENTIFIER([^A-Za-z0-9_]|\$)"              # jq field access (.raw.SYSLOG_IDENTIFIER)
EMITTER_RE+="|SYSLOG_IDENTIFIER[\\\\\"']*[[:space:]]*[:=]"         # field-key needle / assignment ("SYSLOG_IDENTIFIER":"x", SYSLOG_IDENTIFIER=)
EMITTER_RE+="|SYSLOG_IDENTIFIER[[:space:]]*//"                     # jq `// ""` extraction
EMITTER_RE+="|SYSLOG_IDENTIFIER\\\\\\\\"                           # escaped-field needle (SYSLOG_IDENTIFIER\")
EMITTER_RE+="|JSONExtractString\\([^)]*SYSLOG_IDENTIFIER"          # ClickHouse extraction
EMITTER_RE+="|get\\([\"']SYSLOG_IDENTIFIER"                        # python dict .get("SYSLOG_IDENTIFIER")
EMITTER_RE+="|os\\.environ[^#]*SYSLOG_IDENTIFIER"                  # python env read of the field
EMITTER_RE+="|os\\.environ\\[\"INNGEST_PROBE_(EMITTER|MARKER)\"\\]" # the probe lib's env contract
EMITTER_RE+="|--control-require-field"                             # the closed field form
EMITTER_RE+="|select\\([^)]*(inngest_probe_row|bs_emitter_row)([^A-Za-z0-9_]|\$)" # a def call inside select()
EMITTER_RE+="|INNGEST_PROBE_ROW_JQ|BS_EMITTER_ROW_JQ"              # use of the exported programs
EMITTER_RE+="|((^|[[:space:]])(source|\\.)[[:space:]]|[A-Za-z_][A-Za-z0-9_]*=)[^#]*(bs-emitter-row|inngest-probe-row|inngest-host-dark-gate)\\.sh" # sourced emitter-def lib

# strip_code <file> > stripped-code — comment-free code with LINE NUMBERS PRESERVED (blanked
# comment lines stay blank so grep -n on the output still cites the true line).
strip_code() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.mts|*.cts)
      awk '{
        line = $0; out = ""; i = 1
        while (i <= length(line)) {
          if (inblock) {
            if (substr(line, i, 2) == "*/") { inblock = 0; i += 2 } else i++
          } else if (substr(line, i, 2) == "/*") { inblock = 1; i += 2
          } else if (substr(line, i, 2) == "//") { break
          } else { out = out substr(line, i, 1); i++ }
        }
        print out
      }' "$1" ;;
    *)
      awk '{ if ($0 ~ /^[ \t]*#/) print ""; else print }' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Census
# ---------------------------------------------------------------------------
git -C "$TREE_ROOT" ls-files > "$WORK/lsfiles" || {
  printf '[FATAL] emitter-read census: git ls-files failed in %s\n' "$TREE_ROOT" >&2
  exit 2
}

n_walked=0
n_found=0
violations=0
FOUND_LIST="$WORK/found"
: > "$FOUND_LIST"
VERDICTS="$WORK/verdicts"
: > "$VERDICTS"

# Pre-pass (fast tier): a file that never writes the transport name or a seam token ANYWHERE —
# comments included — cannot be a reader; comments cannot invoke. One repo-wide git grep narrows
# the walk to the needle-bearing minority (~66 of 3201); comment-strip + classification still run
# per file below, unchanged. n_walked still counts every eligible file (the census walked it — as
# a candidate check, the same verdict the old per-file strip produced for needle-free files).
grep -vE '^(knowledge-base/|docs/|tests/|.*[.]md$|.*[.]test[.](sh|ts|py|js|tsx)$|scripts/lint-betterstack-emitter-read[.]test[.]sh$|scripts/lint-betterstack-emitter-read[.]sh$)' \
  "$WORK/lsfiles" > "$WORK/eligible" || true
n_walked="$(wc -l < "$WORK/eligible" | tr -d ' ')"
git -C "$TREE_ROOT" grep -lE 'betterstack-query[.]sh|bs_absence_query_script|_bs_query_rows|run_bq' -- . 2>/dev/null | sort > "$WORK/namehits" || true
sort "$WORK/eligible" > "$WORK/eligible.sorted"
comm -12 "$WORK/eligible.sorted" "$WORK/namehits" > "$WORK/candidates"

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  f="$TREE_ROOT/$rel"
  [[ -f "$f" ]] || continue
  strip_code "$f" > "$WORK/code"
  # Adjacency is per LINE: the name-bearing lines alone are tested for invocation shape — a
  # hint string that embeds the recipe still counts (its verdict is the allowlist's "hint"
  # reason), while a bare path listing or prose line does not. `=~` rather than a second grep:
  # the grep -n line-number prefix would un-anchor `^VAR=` assignment lines (`45:QUERY=` has a
  # colon, not a space, before the name — measured: it dropped every line-start assignment).
  # Adjacency sees CONTINUATION-joined name lines: an idiomatic `script \` + `--flag` on the
  # next physical line would otherwise escape discovery entirely (the flag line never contains
  # the name). awk getline walks the continuation chain; INV_NAME on a bare line still joins.
  name_lines="$(awk -v re="$INV_NAME" '$0 ~ re { l=$0; while (l ~ /\\[[:space:]]*$/ && (getline nxt) > 0) { sub(/\\[[:space:]]*$/, "", l); l=l " " nxt } print l }' "$WORK/code" || true)"
  inv_hit=0
  [[ "$name_lines" =~ $INV_SHAPE ]] && inv_hit=1
  seam_hit="$(grep -cE -- "$SEAM_RE" "$WORK/code" || true)"
  if [[ "$inv_hit" -eq 0 && "$seam_hit" -eq 0 ]]; then
    continue
  fi
  n_found=$((n_found + 1))
  printf '%s\n' "$rel" >> "$FOUND_LIST"
  if [[ -n "${ALLOW[$rel]+x}" ]]; then
    if [[ -z "${ALLOW[$rel]}" ]]; then
      printf 'BARE-REASON %s (allowlist entry carries an empty reason)\n' "$rel" >> "$VERDICTS"
      violations=$((violations + 1))
    else
      printf 'OK-ALLOWLISTED %s\n' "$rel" >> "$VERDICTS"
    fi
    continue
  fi
  if grep -qE -- "$EMITTER_RE" "$WORK/code"; then
    printf 'OK-EMITTER %s\n' "$rel" >> "$VERDICTS"
  else
    printf 'UNCLASSIFIED %s (invokes betterstack-query.sh but neither selects on SYSLOG_IDENTIFIER nor carries an allowlist reason — select through the decoded field, source scripts/lib/bs-emitter-row.sh, or record a reason)\n' "$rel" >> "$VERDICTS"
    violations=$((violations + 1))
  fi
done < "$WORK/candidates"

sort -o "$VERDICTS" "$VERDICTS"
cat "$VERDICTS"
grep -E '^(UNCLASSIFIED|STALE|BARE-REASON)' "$VERDICTS" >&2 || true

# STALE: allowlisted paths that were not discovered.
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  if ! grep -qxF -- "$key" "$FOUND_LIST"; then
    printf 'STALE %s (allowlisted but no invocation-shaped reference remains — remove or re-key the entry)\n' "$key" >&2
    violations=$((violations + 1))
  fi
done < <(printf '%s\n' "${!ALLOW[@]}" | sort)

# MUST_FIND — heavyweight readers that must always be discovered (production tree only; a
# fixture tree legitimately contains none of them).
MUST_FIND=(
  "scripts/betterstack-query.sh"
  "scripts/betterstack-assert-absence.sh"
  "scripts/cutover-inngest.sh"
  "scripts/inngest-host-state.sh"
  "scripts/inngest-probe-heartbeat-feeder.sh"
  "scripts/check-deploy-script-parity.sh"
  "scripts/zot-restart-loop-alarm.sh"
  "scripts/zot-disk-sample.sh"
  "scripts/lib/betterstack-absence.sh"
  "scripts/lib/git-data-boot-signal-poll.sh"
  "scripts/registry-replace-preflight.sh"
  "scripts/probe-inngest-524-count.sh"
  "scripts/followthroughs/inngest-provision-unit-8562.sh"
  "scripts/followthroughs/zot-fill-rate-7341.sh"
  ".github/workflows/scheduled-inngest-health.yml"
  ".github/workflows/git-data-cutover.yml"
  ".github/workflows/inngest-config-drift.yml"
)
if [[ "$is_prod" == "yes" ]]; then
  for mf in "${MUST_FIND[@]}"; do
    if ! grep -qxF -- "$mf" "$FOUND_LIST"; then
      printf 'MUST-FIND-MISSING %s (a heavyweight reader escaped discovery — the needle or the exclusions are broken)\n' "$mf" >&2
      violations=$((violations + 1))
    fi
  done
fi

# Population floor (production only): discovery collapsing reports clean over a corpus it
# cannot see. EMITTER_READ_MIN_POP is a TEST-ONLY override (the .test.sh forces the breach on
# the real tree); production never sets it.
MIN_POP="${EMITTER_READ_MIN_POP:-40}"
if [[ "$is_prod" == "yes" ]] && [[ "$n_found" -lt "$MIN_POP" ]]; then
  printf '[FATAL] emitter-read census discovered only %s invocation file(s) in %s — expected at least %s; the discovery needle, comment strip, or exclusions are broken\n' \
    "$n_found" "$TREE_ROOT" "$MIN_POP" >&2
  exit 2
fi

if (( violations > 0 )); then
  printf 'betterstack-emitter-read: FAILED (%s violation(s); %s file(s) walked, %s discovered)\n' "$violations" "$n_walked" "$n_found" >&2
  exit 1
fi
printf 'betterstack-emitter-read: clean (%s file(s) walked, %s discovered, %s allowlisted)\n' \
  "$n_walked" "$n_found" "${#ALLOW[@]}"
exit 0
