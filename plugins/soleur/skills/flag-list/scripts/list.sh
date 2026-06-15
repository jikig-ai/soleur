#!/usr/bin/env bash
# List all runtime feature flags: Flagsmith state + code-wiring (server.ts
# RUNTIME_FLAGS) + live Doppler env-var values (dev + prd) + per-segment override
# state. Read-only — the audit-before-promotion / audit-before-delete read.
#
# Contract: SKILL.md in the parent directory. The Read verb of the flag CRUD set
# (flag-create=Create, flag-set-role=Update, flag-list=Read, flag-delete=Delete).
#
# Usage: bash list.sh [--json]
#
# Exit codes:
#   0 — success
#   2 — prerequisite missing (token / binaries / server.ts)
#   3 — Flagsmith API error

set -euo pipefail

# --- constants (mirror flag-create/scripts/create.sh + flip.sh) -------------
readonly FLAGSMITH_PROJECT_ID=39082
readonly FLAGSMITH_ENV_DEV_ID=90722
readonly FLAGSMITH_ENV_PRD_ID=90721
readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"
readonly SERVER_TS="apps/web-platform/lib/feature-flags/server.ts"

JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    --*)    echo "unknown flag: $1" >&2; exit 2 ;;
    *)      echo "unexpected arg: $1" >&2; exit 2 ;;
  esac
done

# --- prerequisites ----------------------------------------------------------
command -v curl >/dev/null    || { echo "missing: curl" >&2; exit 2; }
command -v python3 >/dev/null || { echo "missing: python3" >&2; exit 2; }
command -v doppler >/dev/null || { echo "missing: doppler" >&2; exit 2; }
[[ -f "$SERVER_TS" ]] || { echo "missing $SERVER_TS (run from repo root / worktree)" >&2; exit 2; }

TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$TOKEN" ]] && { echo "FLAGSMITH_MANAGEMENT_API_KEY not in Doppler soleur/cli_ops" >&2; exit 2; }

# fs_api — identical to create.sh:65 / flip.sh:131. Never echoes the token.
fs_api() { curl -sS -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" "$@"; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# --- fetch all features (paginate while `next` is non-null) -----------------
echo "→ Fetching Flagsmith features (project $FLAGSMITH_PROJECT_ID)…" >&2
: > "$WORKDIR/features.ndjson"
URL="${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/?page_size=100"
while [[ -n "$URL" && "$URL" != "null" ]]; do
  PAGE=$(fs_api "$URL") || { echo "Flagsmith features fetch failed" >&2; exit 3; }
  URL=$(printf '%s' "$PAGE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for f in d.get("results", []):
    print(json.dumps({"id": f["id"], "name": f["name"], "default_enabled": f.get("default_enabled", False)}))
nxt = d.get("next")
print(nxt if nxt else "", file=sys.stderr)
' 2>"$WORKDIR/next.txt" >>"$WORKDIR/features.ndjson") || { echo "feature page parse failed" >&2; exit 3; }
  URL=$(cat "$WORKDIR/next.txt")
done

# --- fetch all segments (id → name map) -------------------------------------
fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/" \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(json.dumps({s["id"]: s["name"] for s in d.get("results", [])}))
' > "$WORKDIR/segments.json" || { echo "segments fetch failed" >&2; exit 3; }

# --- per (feature, env) segment-override enumeration ------------------------
# Mirrors flip.sh get_live_version_uuid + version-scoped featurestates read.
get_live_version_uuid() {
  local env_id="$1" feature_id="$2"
  fs_api "${FLAGSMITH_API}/environments/${env_id}/features/${feature_id}/versions/" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for v in d.get("results", []):
    if v.get("is_live"):
        print(v["uuid"]); sys.exit(0)
' 2>/dev/null
}

# Write a featurestates blob per (feature, env) so the python assembler can map
# segment overrides → segment names. Env-default (feature_segment=null) is skipped.
while read -r frec; do
  [[ -z "$frec" ]] && continue
  FID=$(printf '%s' "$frec" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for envtag in dev:$FLAGSMITH_ENV_DEV_ID prd:$FLAGSMITH_ENV_PRD_ID; do
    label="${envtag%%:*}"; env_id="${envtag##*:}"
    uuid=$(get_live_version_uuid "$env_id" "$FID")
    if [[ -n "$uuid" ]]; then
      fs_api "${FLAGSMITH_API}/environments/${env_id}/features/${FID}/versions/${uuid}/featurestates/" \
        > "$WORKDIR/fs_${FID}_${label}.json" 2>/dev/null || echo '[]' > "$WORKDIR/fs_${FID}_${label}.json"
    else
      echo '[]' > "$WORKDIR/fs_${FID}_${label}.json"
    fi
  done
done < "$WORKDIR/features.ndjson"

# --- read live Doppler value per RUNTIME_FLAGS env-var (dev + prd) ----------
# Single targeted FLAG_<X> read per env — never `doppler secrets download` /
# `doppler secrets` (which dump the whole config; same hazard family as the
# 2026-05-26 secrets-delete stdout leak). Missing key → "unset".
doppler_val() { # $1=ENV_VAR $2=config
  doppler secrets get "$1" -p soleur -c "$2" --plain 2>/dev/null || echo "unset"
}

# Extract RUNTIME_FLAGS + ENV_FLAGS (name → env-var) from server.ts, then read
# each flag's dev/prd Doppler value into a JSON map for the assembler.
python3 -c '
import json, re
src = open("'"$SERVER_TS"'").read()
def block(const):
    # Anchor on `} as const;` (matching create.sh/delete.sh) so a reformat that
    # splits the closing brace from the suffix cannot match a truncated block.
    m = re.search(r"const " + const + r" = \{(.*?)\}\s*as const;", src, re.DOTALL)
    pairs = re.findall(r"\"([a-z0-9-]+)\"\s*:\s*\"([A-Z0-9_]+)\"", m.group(1)) if m else []
    return dict(pairs)
print(json.dumps({"runtime": block("RUNTIME_FLAGS"), "env": block("ENV_FLAGS")}))
' > "$WORKDIR/code_flags.json" || { echo "server.ts parse failed" >&2; exit 3; }

# Read Doppler for every code-wired runtime env-var.
python3 -c '
import json
d = json.load(open("'"$WORKDIR"'/code_flags.json"))
print("\n".join(d["runtime"].values()))
' | sort -u | while read -r ev; do
  [[ -z "$ev" ]] && continue
  printf '%s\t%s\t%s\n' "$ev" "$(doppler_val "$ev" dev)" "$(doppler_val "$ev" prd)"
done > "$WORKDIR/doppler.tsv"

# --- assemble + render ------------------------------------------------------
JSON_OUT="$JSON_OUT" WORKDIR="$WORKDIR" python3 <<'PY'
import json, os, glob

wd = os.environ["WORKDIR"]
json_out = os.environ["JSON_OUT"] == "1"

features = [json.loads(l) for l in open(f"{wd}/features.ndjson") if l.strip()]
seg_names = {int(k): v for k, v in json.load(open(f"{wd}/segments.json")).items()}
code = json.load(open(f"{wd}/code_flags.json"))
runtime = code["runtime"]          # name -> FLAG_<X>
env_flags = code["env"]            # name -> FLAG_<X> (build-time DCE)

doppler = {}
dp = f"{wd}/doppler.tsv"
if os.path.exists(dp):
    for line in open(dp):
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 3:
            doppler[parts[0]] = {"dev": parts[1], "prd": parts[2]}

def overrides_for(fid, label):
    p = f"{wd}/fs_{fid}_{label}.json"
    if not os.path.exists(p):
        return []
    try:
        rows = json.load(open(p))
    except Exception:
        return []
    out = []
    for fs in rows if isinstance(rows, list) else []:
        seg = fs.get("feature_segment")
        seg_id = seg.get("segment") if isinstance(seg, dict) else None
        if seg_id is None:
            continue  # env default, not a segment override
        out.append({"segment": seg_names.get(seg_id, f"segment#{seg_id}"),
                    "enabled": bool(fs.get("enabled"))})
    return out

fs_names = {f["name"] for f in features}
rows = []
for f in features:
    name = f["name"]
    env_var = runtime.get(name) or ("FLAG_" + name.upper().replace("-", "_"))
    code_wired = name in runtime
    dv = doppler.get(env_var, {"dev": "unset", "prd": "unset"})
    rows.append({
        "name": name,
        "env_var": env_var if code_wired else None,
        "flagsmith_id": f["id"],
        "default_enabled": f["default_enabled"],
        "code_wired": code_wired,
        "doppler_dev": dv["dev"] if code_wired else None,
        "doppler_prd": dv["prd"] if code_wired else None,
        "segments": {"dev": overrides_for(f["id"], "dev"),
                     "prd": overrides_for(f["id"], "prd")},
    })

# code-only drift: RUNTIME_FLAGS key with no Flagsmith feature
for name, env_var in runtime.items():
    if name not in fs_names:
        dv = doppler.get(env_var, {"dev": "unset", "prd": "unset"})
        rows.append({
            "name": name, "env_var": env_var, "flagsmith_id": None,
            "default_enabled": None, "code_wired": True,
            "doppler_dev": dv["dev"], "doppler_prd": dv["prd"],
            "segments": {"dev": [], "prd": []},
            "drift": "code-only (no Flagsmith feature)",
        })

rows.sort(key=lambda r: r["name"])

if json_out:
    print(json.dumps(rows, indent=2))
else:
    print()
    print("Runtime feature flags (Flagsmith × code × Doppler):")
    print(f"  {'NAME':28} {'WIRED':5} {'FS_ID':7} {'DEV':6} {'PRD':6} SEGMENTS(dev|prd)")
    for r in rows:
        segs_dev = ",".join(f"{s['segment']}={'on' if s['enabled'] else 'off'}" for s in r["segments"]["dev"]) or "-"
        segs_prd = ",".join(f"{s['segment']}={'on' if s['enabled'] else 'off'}" for s in r["segments"]["prd"]) or "-"
        drift = r.get("drift", "")
        wired = "yes" if r["code_wired"] else "NO"
        fsid = str(r["flagsmith_id"]) if r["flagsmith_id"] is not None else "-"
        print(f"  {r['name']:28} {wired:5} {fsid:7} {str(r['doppler_dev']):6} {str(r['doppler_prd']):6} {segs_dev} | {segs_prd}  {drift}")
    drift_rows = [r for r in rows if not r["code_wired"]]
    if drift_rows:
        print()
        print("⚠ Flagsmith-only (not code-wired in RUNTIME_FLAGS):")
        for r in drift_rows:
            print(f"  {r['name']} (flagsmith_id={r['flagsmith_id']})")
    if env_flags:
        print()
        print("Build-time env flags (DCE — NOT runtime/Flagsmith):")
        for name, ev in sorted(env_flags.items()):
            print(f"  {name} → {ev}")
    print()
PY
