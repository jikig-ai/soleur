#!/usr/bin/env bash
# Admission-partition emulator for vector.toml (#6551).
#
# WHAT IT PROVES. Vector's journald source spawns
# `journalctl --follow --all --show-cursor --output=json` with NO match arguments
# and filters each decoded record client-side (journald.rs @ v0.43.1, pinned at
# vector.tf:13; mechanism verified in ADR-286). The evaluator is:
#
#   drop  — if ANY record field has a value in that field's exclude_matches set
#           (exclude_units merges into exclude_matches._SYSTEMD_UNIT)
#   admit — if include_matches is empty, or ANY record field has a value in that
#           field's include_matches set (include_units merges into
#           include_matches._SYSTEMD_UNIT). Includes are an OR over record fields.
#
# This suite parses vector.toml ONCE with python3 tomllib into a source model,
# then evaluates synthesized journald records through that exact semantics and
# asserts the admitting-source SET per fixture. The #6551 partition contract is
# "every row class reaches Better Stack through exactly ONE source" — a corpus
# row admitting at multiplicity > 1, or a must-ship row admitting nowhere, is a
# CI verdict here rather than a hand-computed table (the defect that produced
# the issue's "no source admits" claim).
#
# DOCUMENTED RESIDUALS (CTO ruling, 2026-10-13): two windows remain open but are
# unreachable today — S2∩S3 (Docker's journald driver emits only PRIORITY 3/6,
# never 0-2) and S3∩S4 (a container row carrying an S4 tag — no container emits
# one). They are pinned in the `residual` lane with their real multiplicity-2
# answer so the windows stay NAMED, and they are excluded from the multiplicity
# aggregate on purpose.
#
# NO vector binary, no journal, no network — pure tomllib + the evaluator model.
# Runner assumption: python3 >= 3.11 (tomllib); ubuntu-24.04 carries 3.12.
#
# Suite-file hygiene (guard-vacuity-floor defect class): this file must never
# carry a bare less-than-less-than or here-string token outside a real heredoc —
# the meta-guard's heredoc blanker reads ANY such token as a heredoc opener and
# would swallow the tail floor. The only occurrences below are the four real
# quoted heredocs feeding python3/cat (the model, the emulator, the structure checker and the mutation harness); all floor/conservation reporting sits
# AFTER them, reports with printf + exit 1, and never routes through ok()/no().

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
REAL_VECTOR_TOML="$REPO_ROOT/apps/web-platform/infra/vector.toml"
# VECTOR_TOML_UNDER_TEST points the whole suite at a different file: the mutation rows below re-run
# THIS suite as a child over a mutated copy and require it to go RED (ADMISSION_MUTATION_CHILD=1
# makes the child skip the mutation section and print verdicts only; the parent carries the floor).
VECTOR_TOML="${VECTOR_TOML_UNDER_TEST:-$REAL_VECTOR_TOML}"

command -v python3 >/dev/null 2>&1 || { echo "SETUP FAILED: python3 absent (need >=3.11 for tomllib)" >&2; exit 2; }
python3 -c 'import tomllib' 2>/dev/null || { echo "SETUP FAILED: python3 tomllib absent (need >=3.11)" >&2; exit 2; }
[[ -f "$VECTOR_TOML" ]] || { echo "SETUP FAILED: vector.toml not found at $VECTOR_TOML" >&2; exit 2; }

TMP="$(mktemp -d)" || { echo "SETUP FAILED: mktemp" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ---------- counters (ADR-193) --------------------------------------------------
# `cases` is the INDEPENDENT case counter: it moves at the call sites
# (expect()/run_case()) and NEVER inside the verdict helpers, so a neutered
# ok()/no() drops a verdict without dropping its count — and the conservation
# check at the bottom catches it.
ok_count=0
no_count=0
cases=0
declare -a LEDGER=()   # append-only failure ledger the verdict reads
ok() { ok_count=$((ok_count + 1)); printf '  ok: %s\n' "$1"; }
no() { no_count=$((no_count + 1)); LEDGER+=("$1"); printf '  NO: %s\n' "$1" >&2; }
# expect <rc> <ok-msg> <no-msg> — the one verdict dispatch; `cases` moves here.
expect() { cases=$((cases + 1)); if [[ "$1" == 0 ]]; then ok "$2"; else no "$3"; fi }

echo "=== vector.toml admission-partition emulator (#6551) ==="

# ---------- ONE parse: vector.toml -> source model (JSON) -----------------------
MODEL="$(python3 - "$VECTOR_TOML" <<'PYEOF'
import json, sys, tomllib

cfg = tomllib.load(open(sys.argv[1], "rb"))
KNOWN = {"type", "include_units", "exclude_units",
         "include_matches", "exclude_matches", "extra_args"}
out = {"sources": {}, "sinks": {}}
for name, src in cfg.get("sources", {}).items():
    if not isinstance(src, dict):
        continue
    entry = {"type": src.get("type"), "include": {}, "exclude": {},
             "other_keys": [], "extra_args": "extra_args" in src}
    for k in src:
        if k not in KNOWN:
            entry["other_keys"].append(k)
    for f, vals in (src.get("include_matches") or {}).items():
        entry["include"][f] = sorted(vals)
    for f, vals in (src.get("exclude_matches") or {}).items():
        entry["exclude"][f] = sorted(vals)
    # JournaldConfig::merged_include_matches — include_units merges into
    # include_matches._SYSTEMD_UNIT; same for the exclude side.
    if "include_units" in src:
        entry["include"]["_SYSTEMD_UNIT"] = sorted(src["include_units"])
    if "exclude_units" in src:
        entry["exclude"]["_SYSTEMD_UNIT"] = sorted(src["exclude_units"])
    out["sources"][name] = entry
bs = (cfg.get("sinks") or {}).get("betterstack") or {}
out["sinks"]["betterstack"] = {"inputs": bs.get("inputs", [])}
print(json.dumps(out))
PYEOF
)" || { echo "SETUP FAILED: tomllib parse of $VECTOR_TOML" >&2; exit 2; }
[[ "$MODEL" == *inngest_journald* ]] || { echo "SETUP FAILED: source model empty — parse produced nothing" >&2; exit 2; }
# A model whose journald sources all lost their type parses without error and would evaluate every
# record against an empty set: refuse, never report "0 checked" as a pass (Guard 1 mutation row 3).
JOURNALD_N="$(python3 -c 'import json,sys; m=json.loads(sys.argv[1]); print(sum(1 for s in m["sources"].values() if s.get("type")=="journald"))' "$MODEL")" \
  || { echo "SETUP FAILED: journald-source count" >&2; exit 2; }
[[ "$JOURNALD_N" =~ ^[1-9][0-9]*$ ]] \
  || { echo "SETUP FAILED: the source model holds zero journald sources (a mutated or renamed type); refusing to evaluate an empty model" >&2; exit 2; }

# ---------- the evaluator (journald.rs filter_matches semantics) ----------------
EVAL_SRC="$(cat <<'PYEOF'
import json, sys

model = json.loads(sys.argv[1])
rec = json.loads(sys.argv[2])
out = []
for name in sorted(model["sources"]):
    src = model["sources"][name]
    if src.get("type") != "journald":
        continue
    dropped = False
    for field, allowed in src["exclude"].items():
        if field in rec and str(rec[field]) in allowed:
            dropped = True
            break
    if dropped:
        continue
    incl = src["include"]
    if not incl:                      # empty include set = admit-all
        out.append(name)
        continue
    for field, allowed in incl.items():
        if field in rec and str(rec[field]) in allowed:
            out.append(name)
            break
print(" ".join(out))
PYEOF
)"

MULTI=""
# run_case <name> <record-json> <expected-set> [main|residual]
# expected-set is a space-joined, sorted source-name list (empty = no source admits).
run_case() {
  local name="$1" rec="$2" exp="$3" lane="${4:-main}" actual="" rc=0 nw=0 w
  cases=$((cases + 1))
  actual="$(python3 -c "$EVAL_SRC" "$MODEL" "$rec")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    no "$name: emulator exited non-zero ($rc)"
    return
  fi
  for w in $actual; do nw=$((nw + 1)); done
  if [[ "$lane" == main && $nw -gt 1 ]]; then MULTI+="$name "; fi
  if [[ "$actual" == "$exp" ]]; then
    ok "$name -> {${exp:-EMPTY}}"
  else
    no "$name: expected {${exp:-EMPTY}}, got {${actual:-EMPTY}}"
  fi
}

echo ""
echo "--- corpus: the verbatim #6551 row and its sibling classes ---"

# The issue's row, verbatim fields (PRIORITY=3, _SYSTEMD_UNIT=init.scope,
# SYSLOG_IDENTIFIER=systemd, UNIT=inngest-heartbeat.service). The issue's table
# called it unadmitted; it has always been admitted — by the PRIORITY arm.
run_case "issue-6551-verbatim (systemd PRIORITY-3, init.scope)" \
  '{"_SYSTEMD_UNIT":"init.scope","SYSLOG_IDENTIFIER":"systemd","PRIORITY":"3","UNIT":"inngest-heartbeat.service","MESSAGE":"fixture"}' \
  "inngest_journald"

# The #9963 positive-control shape: `/usr/bin/logger -t systemd -p err` —
# PRIORITY 3, SYSLOG_IDENTIFIER=systemd, emitted under the probe unit.
run_case "control shape (-t systemd -p err)" \
  '{"_SYSTEMD_UNIT":"inngest-server-probe.service","SYSLOG_IDENTIFIER":"systemd","PRIORITY":"3"}' \
  "inngest_journald"

# The unit arm admits inngest-server.service at EVERY priority.
run_case "inngest-server.service PRIORITY 6 (unit arm, not capped)" \
  '{"_SYSTEMD_UNIT":"inngest-server.service","PRIORITY":"6"}' \
  "inngest_journald"
run_case "inngest-server.service PRIORITY 0 (unit arm; S2 exclude drops it there)" \
  '{"_SYSTEMD_UNIT":"inngest-server.service","PRIORITY":"0"}' \
  "inngest_journald"

# The TLS terminator unit (stunnel4, soleur-inngest-tls.service) rides the same unit arm. Its
# lines carry no <N> prefix, so the journald PRIORITY is derived (systemd's default), not measured on
# the host: the literal rows below cover the values 0 and 2 to 6 a build could assign, and a PRIORITY test can
# never split its LOG3 refusal lines from its LOG5 healthy lines (plan, Sharp Edges).
run_case "terminator soleur-inngest-tls.service PRIORITY 6 (unit arm; the expected default)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"6"}' \
  "inngest_journald"
run_case "terminator soleur-inngest-tls.service PRIORITY 5 (unit arm)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"5"}' \
  "inngest_journald"
run_case "terminator soleur-inngest-tls.service PRIORITY 4 (unit arm AND the {3,4} arm: one source either way)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"4"}' \
  "inngest_journald"
run_case "terminator soleur-inngest-tls.service PRIORITY 3 (stderr class; unit arm AND the {3,4} arm)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"3"}' \
  "inngest_journald"
run_case "terminator soleur-inngest-tls.service PRIORITY 2 (its own crit record: S1 admits, S2 excludes the unit)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"2"}' \
  "inngest_journald"
run_case "terminator soleur-inngest-tls.service PRIORITY 0 (unit arm; S2 exclude drops it there)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"stunnel4","PRIORITY":"0"}' \
  "inngest_journald"
# The unit's ExecStartPre fetch script (soleur-inngest-tls fetch) runs inside the unit: its output
# carries the script's identifier but the unit's name, and it is not an S4 tag, so the unit arm ships it.
run_case "terminator ExecStartPre fetch output (identifier soleur-inngest-tls, PRIORITY 3)" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls.service","SYSLOG_IDENTIFIER":"soleur-inngest-tls","PRIORITY":"3"}' \
  "inngest_journald"
# The #7898 off-box refusal path. The health unit is a DIFFERENT unit from the terminator, so
# exclude_units (an exact unit-name match) does not touch it: its crit refusal record keeps shipping
# through Source 2, and only Source 2 (its identifier is not an S4 tag; Source 1's arm is {3,4}).
run_case "health unit refusal record (inngest-tls-health, PRIORITY 2) still ships through S2 only" \
  '{"_SYSTEMD_UNIT":"soleur-inngest-tls-health.service","SYSLOG_IDENTIFIER":"inngest-tls-health","PRIORITY":"2"}' \
  "system_journald"

# The never-ship class: routine PID-1 PRIORITY-6 chatter.
run_case "systemd PRIORITY-6 Started/Stopped (deliberately unshipped)" \
  '{"_SYSTEMD_UNIT":"init.scope","SYSLOG_IDENTIFIER":"systemd","PRIORITY":"6"}' \
  ""

# Source-4 tagged rows single-ship at EVERY priority post-partition.
run_case "tagged ci-deploy PRIORITY 4 (was S1+S4 before the partition)" \
  '{"_SYSTEMD_UNIT":"cron.service","SYSLOG_IDENTIFIER":"ci-deploy","PRIORITY":"4"}' \
  "host_scripts_journald"
run_case "tagged ci-deploy PRIORITY 2 (was S1+S2+S4 triple before the partition)" \
  '{"_SYSTEMD_UNIT":"cron.service","SYSLOG_IDENTIFIER":"ci-deploy","PRIORITY":"2"}' \
  "host_scripts_journald"
run_case "tagged inngest-heartbeat PRIORITY 5 (dark-arm notice)" \
  '{"_SYSTEMD_UNIT":"inngest-heartbeat.service","SYSLOG_IDENTIFIER":"inngest-heartbeat","PRIORITY":"5"}' \
  "host_scripts_journald"
run_case "tagged sshd PRIORITY 6 (Accepted publickey — the 2026-07-28 channel)" \
  '{"_SYSTEMD_UNIT":"ssh.service","SYSLOG_IDENTIFIER":"sshd","PRIORITY":"6"}' \
  "host_scripts_journald"
run_case "tagged sshd PRIORITY 4 (Failed publickey — was S1+S4 before)" \
  '{"_SYSTEMD_UNIT":"ssh.service","SYSLOG_IDENTIFIER":"sshd","PRIORITY":"4"}' \
  "host_scripts_journald"
run_case "tagged webhook PRIORITY 6" \
  '{"_SYSTEMD_UNIT":"webhook.service","SYSLOG_IDENTIFIER":"webhook","PRIORITY":"6"}' \
  "host_scripts_journald"

# Container rows: Docker's journald driver maps fd1 -> PRIORITY 6, fd2 -> 3.
# Stderr used to double-ship via Source 1's {0..4} arm AND its container source.
run_case "app container stdout PRIORITY 6" \
  '{"CONTAINER_NAME":"soleur-web-platform","PRIORITY":"6"}' \
  "app_container_journald"
run_case "app container stderr PRIORITY 3 (was S1+S3 before the partition)" \
  '{"CONTAINER_NAME":"soleur-web-platform","PRIORITY":"3"}' \
  "app_container_journald"
run_case "egress-gw stdout PRIORITY 6" \
  '{"CONTAINER_NAME":"soleur-egress-gw","PRIORITY":"6"}' \
  "egress_gw_journald"
run_case "egress-gw stderr PRIORITY 3 (was S1+S3b before the partition)" \
  '{"CONTAINER_NAME":"soleur-egress-gw","PRIORITY":"3"}' \
  "egress_gw_journald"

# Canary: stderr has shipped through the arm since #4267 and MUST keep shipping —
# the exclusion deliberately omits soleur-web-platform-canary.
run_case "canary stderr PRIORITY 3 (pre-existing single-ship via the arm)" \
  '{"CONTAINER_NAME":"soleur-web-platform-canary","PRIORITY":"3"}' \
  "inngest_journald"
run_case "canary stdout PRIORITY 6 (never warehoused — local docker logs only)" \
  '{"CONTAINER_NAME":"soleur-web-platform-canary","PRIORITY":"6"}' \
  ""

# vector.service: the moved crit path — its exclusion was dropped from S2 in the
# same change, else the narrowed arm would have darkened the class.
run_case "vector.service PRIORITY 1 (the moved crit path -> S2)" \
  '{"_SYSTEMD_UNIT":"vector.service","SYSLOG_IDENTIFIER":"vector","PRIORITY":"1"}' \
  "system_journald"
run_case "vector.service PRIORITY 3 (unchanged single-ship via S1's arm)" \
  '{"_SYSTEMD_UNIT":"vector.service","SYSLOG_IDENTIFIER":"vector","PRIORITY":"3"}' \
  "inngest_journald"

# Untagged host classes.
run_case "untagged PRIORITY 2 host row (was S1+S2 before the partition)" \
  '{"_SYSTEMD_UNIT":"cron.service","SYSLOG_IDENTIFIER":"cron","PRIORITY":"2"}' \
  "system_journald"
run_case "untagged PRIORITY 0 kernel row" \
  '{"SYSLOG_IDENTIFIER":"kernel","PRIORITY":"0"}' \
  "system_journald"
run_case "untagged PRIORITY 5 row (drops at both arms — unchanged)" \
  '{"_SYSTEMD_UNIT":"cron.service","SYSLOG_IDENTIFIER":"something","PRIORITY":"5"}' \
  ""
run_case "untagged PRIORITY 6 cron row (deliberately unshipped)" \
  '{"_SYSTEMD_UNIT":"cron.service","SYSLOG_IDENTIFIER":"CRON","PRIORITY":"6"}' \
  ""

echo ""
echo "--- corpus: documented residual windows (multiplicity 2, unreachable today) ---"
run_case "residual S2+S3: container row at PRIORITY 1 (Docker never emits 0-2)" \
  '{"CONTAINER_NAME":"soleur-web-platform","PRIORITY":"1"}' \
  "app_container_journald system_journald" residual
run_case "residual S3+S4: container row carrying an S4 tag (no container emits one)" \
  '{"CONTAINER_NAME":"soleur-web-platform","SYSLOG_IDENTIFIER":"ci-deploy","PRIORITY":"6"}' \
  "app_container_journald host_scripts_journald" residual

echo ""
echo "--- aggregate: the partition property over the whole reachable corpus ---"
[[ -z "$MULTI" ]]; expect $? \
  "multiplicity <= 1 over every reachable-class fixture" \
  "multiplicity > 1 on: $MULTI"

echo ""
echo "--- structural pins (non-corpus surface) ---"
# Emits one `name<TAB>rc<TAB>detail` line per pin; the bash loop below dispatches
# each through expect() so every pin is its own counted case.
STRUCT_SRC="$(cat <<'PYEOF'
import json, sys

model = json.loads(sys.argv[1])
S = model["sources"]
JOURNALD = {n: s for n, s in S.items() if s.get("type") == "journald"}

def emit(name, ok, detail=""):
    print("%s\t%d\t%s" % (name, 0 if ok else 1, detail))

emit("journald source census is exactly the five known sources",
     set(JOURNALD) == {"inngest_journald", "system_journald",
                       "app_container_journald", "egress_gw_journald",
                       "host_scripts_journald"},
     "got: %s" % sorted(JOURNALD))

s1 = JOURNALD.get("inngest_journald", {})
s2 = JOURNALD.get("system_journald", {})
s4 = JOURNALD.get("host_scripts_journald", {})

emit("S1 include_matches.PRIORITY is exactly {3,4}",
     s1.get("include", {}).get("PRIORITY") == ["3", "4"],
     "got: %s" % s1.get("include", {}).get("PRIORITY"))
emit("S2 include_matches.PRIORITY is exactly {0,1,2}",
     s2.get("include", {}).get("PRIORITY") == ["0", "1", "2"],
     "got: %s" % s2.get("include", {}).get("PRIORITY"))
TWO_UNITS = ["inngest-server.service", "soleur-inngest-tls.service"]
emit("S1 include_units == [inngest-server.service, soleur-inngest-tls.service]",
     s1.get("include", {}).get("_SYSTEMD_UNIT") == TWO_UNITS,
     "got: %s" % s1.get("include", {}).get("_SYSTEMD_UNIT"))
emit("S2 exclude_units == the same two units (vector.service's crit path stays with S2; the units move together)",
     s2.get("exclude", {}).get("_SYSTEMD_UNIT") == TWO_UNITS,
     "got: %s" % s2.get("exclude", {}).get("_SYSTEMD_UNIT"))
emit("S1 include_units and S2 exclude_units are set-equal (a unit added to one list only double-ships or silences)",
     s1.get("include", {}).get("_SYSTEMD_UNIT") == s2.get("exclude", {}).get("_SYSTEMD_UNIT"),
     "S1-incl: %s S2-excl: %s" % (s1.get("include", {}).get("_SYSTEMD_UNIT"),
                                  s2.get("exclude", {}).get("_SYSTEMD_UNIT")))
emit("S1 exclude_matches.SYSLOG_IDENTIFIER == S4 include tag set",
     s1.get("exclude", {}).get("SYSLOG_IDENTIFIER") ==
     s4.get("include", {}).get("SYSLOG_IDENTIFIER"),
     "S1-excl: %s S4-incl: %s" % (s1.get("exclude", {}).get("SYSLOG_IDENTIFIER"),
                                  s4.get("include", {}).get("SYSLOG_IDENTIFIER")))
emit("S2 exclude_matches.SYSLOG_IDENTIFIER == S4 include tag set",
     s2.get("exclude", {}).get("SYSLOG_IDENTIFIER") ==
     s4.get("include", {}).get("SYSLOG_IDENTIFIER"),
     "S2-excl: %s S4-incl: %s" % (s2.get("exclude", {}).get("SYSLOG_IDENTIFIER"),
                                  s4.get("include", {}).get("SYSLOG_IDENTIFIER")))
containers = sorted((JOURNALD.get("app_container_journald", {})
                     .get("include", {}).get("CONTAINER_NAME") or []) +
                    (JOURNALD.get("egress_gw_journald", {})
                     .get("include", {}).get("CONTAINER_NAME") or []))
emit("S1 exclude_matches.CONTAINER_NAME == union(S3, S3b container includes)",
     s1.get("exclude", {}).get("CONTAINER_NAME") == containers,
     "S1-excl: %s union: %s" % (s1.get("exclude", {}).get("CONTAINER_NAME"),
                                containers))
emit("canary is NOT in S1's CONTAINER_NAME exclusion (its stderr single-ships via the arm)",
     "soleur-web-platform-canary" not in
     (s1.get("exclude", {}).get("CONTAINER_NAME") or []))
emit("no exclude_matches.PRIORITY anywhere (would silence a priority class)",
     all("PRIORITY" not in s["exclude"] for s in JOURNALD.values()))
emit("every journald source carries >=1 include key (a source with none admits the whole journal)",
     all(s["include"] for s in JOURNALD.values()),
     "empty: %s" % [n for n, s in JOURNALD.items() if not s["include"]])
emit("no extra_args on any journald source (would re-introduce journalctl-side matching)",
     all(not s["extra_args"] for s in JOURNALD.values()),
     "carrying: %s" % [n for n, s in JOURNALD.items() if s["extra_args"]])

# Keys the emulator does not model. Anything outside this set on a journald
# source fails LOUD — the model must grow, not silently mis-evaluate. The listed
# keys are journald-source options that do not affect per-record admission
# (stream position / output shaping), plus the admission keys the model covers.
# `remap_priority` is DELIBERATELY absent from MODELED: decode_record applies it BEFORE
# filter_matches (journald.rs:569→579), rewriting PRIORITY values to text ("ERR"/"WARNING")
# — on a PRIORITY-filtered source that silently darkens the whole arm while every literal
# pin stays green. A future `remap_priority` must fail LOUD here until the model covers it.
MODELED = {"journal_directory", "journal_namespace", "batch_size",
           "current_boot_only", "since_now", "since_boot"}
unmodeled = {n: [k for k in s["other_keys"] if k not in MODELED]
             for n, s in JOURNALD.items()}
unmodeled = {n: ks for n, ks in unmodeled.items() if ks}
emit("no journald source carries a key the emulator does not model",
     not unmodeled, "unmodeled: %s" % unmodeled)

emit("sinks.betterstack inputs == [tag_journald, tag_metrics]",
     model["sinks"].get("betterstack", {}).get("inputs") ==
     ["tag_journald", "tag_metrics"],
     "got: %s" % model["sinks"].get("betterstack", {}).get("inputs"))

sysid = set()
for s in JOURNALD.values():
    sysid |= set(s["include"].get("SYSLOG_IDENTIFIER") or [])
    sysid |= set(s["exclude"].get("SYSLOG_IDENTIFIER") or [])
emit("'systemd' is a member of NO SYSLOG_IDENTIFIER match array, include or exclude",
     "systemd" not in sysid, "members: %s" % sorted(sysid))

emit("host_metrics is a non-journald source (metrics records never enter this evaluator)",
     S.get("host_metrics", {}).get("type") == "host_metrics",
     "type: %s" % S.get("host_metrics", {}).get("type"))
PYEOF
)"
STRUCT_OUT="$TMP/structural.tsv"
python3 -c "$STRUCT_SRC" "$MODEL" > "$STRUCT_OUT" || { echo "SETUP FAILED: structural-check pass" >&2; exit 2; }

while IFS=$'\t' read -r pname prc pdetail; do
  [[ -n "$pname" ]] || continue
  if [[ "$prc" == 0 ]]; then
    expect 0 "$pname" "$pname"
  else
    expect 1 "$pname" "$pname${pdetail:+ — $pdetail}"
  fi
done < "$STRUCT_OUT"

# ---------- Guard 1 mutation rows (plan: terminator admission partition) ---------------------
# Each row edits a COPY of vector.toml (never the real file), re-runs this suite as a child over it
# and requires the child to go RED for the INTENDED reason: the expected exit code AND a message only
# that pin prints. An UNMUTATED control child must be green first, or every row below is void; a
# mutation that did not land (the copy equals the original) is a harness failure, never a pass.
# The child skips this section (ADMISSION_MUTATION_CHILD=1), so there is no recursion.
if [[ "${ADMISSION_MUTATION_CHILD:-0}" != 1 ]]; then
  echo ""
  echo "--- Guard 1 mutation rows (suite re-run over a mutated copy of vector.toml) ---"
  MUT_SRC="$(cat <<'PYEOF'
import re, sys

mode, src_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src_path, encoding="utf-8").read()
BOTH = '["inngest-server.service", "soleur-inngest-tls.service"]'

def swap(text, old, new, count=1):
    if old not in text:
        sys.stderr.write("mutation anchor missing: %r\n" % old)
        sys.exit(3)
    return text.replace(old, new, count)

if mode == "control":
    pass
elif mode == "drop_s1_unit":
    text = swap(text, "include_units = " + BOTH, 'include_units = ["inngest-server.service"]')
elif mode == "drop_s2_unit":
    text = swap(text, "exclude_units = " + BOTH, 'exclude_units = ["inngest-server.service"]')
elif mode == "third_unit_s1_only":
    text = swap(text, "include_units = " + BOTH,
                'include_units = ["inngest-server.service", "soleur-inngest-tls.service", "zz-extra.service"]')
elif mode == "rename_journald_types":
    text = swap(text, 'type = "journald"', 'type = "journaldx"', count=text.count('type = "journald"'))
elif mode == "reverse_both_lists":
    rev = '["soleur-inngest-tls.service", "inngest-server.service"]'
    text = swap(text, "include_units = " + BOTH, "include_units = " + rev)
    text = swap(text, "exclude_units = " + BOTH, "exclude_units = " + rev)
else:
    sys.stderr.write("unknown mutation mode %r\n" % mode)
    sys.exit(4)
open(out_path, "w", encoding="utf-8").write(text)
PYEOF
)"
  # mut_row <mode> <want-rc> <needle> <label>: the child must exit <want-rc> and print <needle>.
  mut_row() {
    local mode="$1" want="$2" needle="$3" label="$4"
    local f="$TMP/m-$mode.toml" o="$TMP/m-$mode.out" crc=0 mrc=0
    python3 -c "$MUT_SRC" "$mode" "$REAL_VECTOR_TOML" "$f" || mrc=$?
    if [[ "$mrc" -ne 0 ]]; then
      expect 1 "" "$label: the mutation could not be applied (rc $mrc; anchor drifted, so this row measured nothing)"
      return
    fi
    if [[ "$mode" != control && "$mode" != reverse_both_lists ]] && cmp -s "$REAL_VECTOR_TOML" "$f"; then
      expect 1 "" "$label: the mutation did not land (the copy equals the original; a mutation that does not land reports the baseline)"
      return
    fi
    VECTOR_TOML_UNDER_TEST="$f" ADMISSION_MUTATION_CHILD=1 bash "${BASH_SOURCE[0]}" </dev/null >"$o" 2>&1 || crc=$?
    if [[ "$crc" -eq "$want" ]] && grep -qF -- "$needle" "$o"; then
      expect 0 "$label (child rc $crc, saw: $needle)" ""
    else
      expect 1 "" "$label: expected child rc $want printing [$needle], got rc $crc"
    fi
  }

  mut_row control 0 "PASSED" "control: the unmutated copy is green (a red baseline would void every row)"
  mut_row drop_s1_unit 1 "NO: S1 include_units ==" "mutation 1: terminator unit removed from S1 include_units goes RED"
  mut_row drop_s2_unit 1 "NO: S2 exclude_units ==" "mutation 2: terminator unit removed from S2 exclude_units goes RED"
  mut_row rename_journald_types 2 "zero journald sources" "mutation 3: renamed source types parse to an empty model and exit 2, never 0 checked"
  mut_row third_unit_s1_only 1 "NO: S1 include_units and S2 exclude_units are set-equal" "mutation 4: a third unit added to S1 only goes RED on the set-equality pin"
  mut_row reverse_both_lists 0 "PASSED" "must-pass: both lists in the opposite order are green (this suite compares sorted sets; the PII and 524 suites pin the literal order)"

  # Harness row: edit the SUITE, not the SUT. A copy whose evaluator ignores every exclude map must
  # redden the multiplicity aggregate (S2's exclude_units is what keeps the unit arm single-ship).
  HARNESS_COPY="$TMP/suite-ignores-excludes.sh"
  sed 's/for field, allowed in src\["exclude"\].items():/for field, allowed in []:/' "${BASH_SOURCE[0]}" > "$HARNESS_COPY"
  hrc=0
  if cmp -s "${BASH_SOURCE[0]}" "$HARNESS_COPY"; then
    expect 1 "" "harness row: the suite mutation did not land (the evaluator line drifted)"
  else
    VECTOR_TOML_UNDER_TEST="$REAL_VECTOR_TOML" ADMISSION_MUTATION_CHILD=1 bash "$HARNESS_COPY" </dev/null >"$TMP/m-harness.out" 2>&1 || hrc=$?
    if [[ "$hrc" -eq 1 ]] && grep -qF -- "multiplicity > 1 on:" "$TMP/m-harness.out"; then
      expect 0 "harness row: an evaluator that ignores exclude maps goes RED (multiplicity aggregate)" ""
    else
      expect 1 "" "harness row: expected child rc 1 printing [multiplicity > 1 on:], got rc $hrc"
    fi
  fi
fi

echo ""

# --- Accounting conservation (ADR-193 #3): reported DIRECTLY, never through
# no() — a check dispatched through the verdict helper it polices cannot report
# the fault that corrupted it. ---
if [[ $((ok_count + no_count)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: ok+no (%d) != cases (%d) — a verdict was dropped or a call site lacks its increment\n' \
    "$((ok_count + no_count))" "$cases" >&2
  exit 1
fi

# --- Instrument self-test: drive expect() through BOTH branches and require
# every observable to move, then restore. A one-branch edit on the single
# dispatch site would otherwise print a byte-identical green run (the
# lint-followthrough-varq-ban measured defect). ---
_p=$ok_count; _f=$no_count; _c=$cases; _n=${#LEDGER[@]}
if (( _n > 0 )); then _saved=("${LEDGER[@]}"); else _saved=(); fi
expect 0 "self-test probe (pass branch)" "unreachable"
expect 1 "unreachable" "self-test probe (fail branch; expected, unwound)"
# run_case owns the verdict of every corpus row (the compare against the expected set), so it gets its own
# control: one record whose admitted set is known (the #6551 verbatim row) driven with the right expected
# set and with a wrong one. A compare that always said yes would leave the pass branch alone and never
# record the wrong-expected case as a failure.
SELFTEST_REC='{"_SYSTEMD_UNIT":"init.scope","SYSLOG_IDENTIFIER":"systemd","PRIORITY":"3","MESSAGE":"fixture"}'
run_case "self-test run_case (right expected set)" "$SELFTEST_REC" "inngest_journald" >/dev/null
run_case "self-test run_case (wrong expected set; expected, unwound)" "$SELFTEST_REC" "system_journald" >/dev/null 2>&1
MULTI=""
if (( ok_count != _p + 2 || no_count != _f + 2 || cases != _c + 4 || ${#LEDGER[@]} != _n + 2 )); then
  printf '[FATAL] instrument self-test: expect() did not move every observable (ok %d->%d, no %d->%d, cases %d->%d, ledger %d->%d)\n' \
    "$_p" "$ok_count" "$_f" "$no_count" "$_c" "$cases" "$_n" "${#LEDGER[@]}" >&2
  exit 1
fi
ok_count=$_p; no_count=$_f; cases=$_c
if (( _n > 0 )); then LEDGER=("${_saved[@]}"); else LEDGER=(); fi

# --- Child of a mutation row: verdicts only. The parent carries the floor (a child that went RED by
# tripping a floor sized for the parent's extra rows would satisfy nothing: every row also requires
# the needle only the targeted pin prints). The final accounting line stays, so a child that died
# before reaching here is visible to the parent as a missing needle. ---
if [[ "${ADMISSION_MUTATION_CHILD:-0}" == 1 ]]; then
  printf '\n=== %d ok, %d no (%d cases, child run: floor enforced by the parent) ===\n' "$ok_count" "$no_count" "$cases"
  if (( no_count == 0 && ${#LEDGER[@]} == 0 )); then
    echo "PASSED"
    exit 0
  fi
  printf 'FAILED: %d\n' "$no_count" >&2
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1): literal bound on the executed count, on
# its own if, exiting inside the block — a stranded run must never report clean.
# Ratchet this number in the same commit that adds a case; it is the measured
# green count, zero headroom (the convention the sibling suites use). ---
if [[ "$cases" -lt 58 ]]; then
  printf '[FATAL] anti-vacuity floor: only %d verdicts recorded, floor is 58 — fixtures or pins were deleted\n' "$cases" >&2
  exit 1
fi

printf '\n=== %d ok, %d no (%d cases, floor 58) ===\n' "$ok_count" "$no_count" "$cases"
if (( no_count == 0 && ${#LEDGER[@]} == 0 )); then
  echo "PASSED"
  exit 0
fi
printf 'FAILED: %d\n' "$no_count" >&2
exit 1
