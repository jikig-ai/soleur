#!/usr/bin/env bash
# test-check-inngest-bootstrap-build.sh — parity + no-publish guard for the #8781 candidate
# build lane (option a). Two sides:
#
#   CHECK = .github/workflows/check-inngest-bootstrap-build.yml +
#           .github/scripts/check-inngest-bootstrap-build.sh
#   AUTHORITY = .github/workflows/build-inngest-bootstrap-image.yml's inline
#               "Build + verify + push" step (the publish path the lane mirrors).
#
# GUARDED PROPERTIES (each independently mutation-checkable — see the mutator battery):
#   P1  CARRIER PARITY — the sorted basename set of the `cp` staging lines is identical on
#       both sides (a carrier added to the publish build without landing here = a lane that
#       greens while the real build would miss the file).
#   P2  DOCKERFILE PARITY — the heredoc-rendered Dockerfile (FROM/RUN/ENV/COPY/ENTRYPOINT
#       lines, whitespace+var-name normalized) is identical on both sides.
#   P3  SHA-VERIFY PARITY — the download + `sha256sum`-verify block is identical
#       (normalized) on both sides.
#   P4  NO-PUBLISH — the check workflow + script contain no `docker push`, `cosign`,
#       `crane`, `id-token`, `packages:`, `environment:`, or `docker login` token; the
#       workflow carries `permissions: contents: read` only, and the script's `docker`
#       invocations are `build` only.
#   P5  PATHS-COVER-CARRIERS — the check workflow's `on.pull_request.paths` covers every
#       `cp` staging source (a carrier edit that cannot fire the lane is the defect #8781
#       exists to close).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CHECK_WF="$ROOT/.github/workflows/check-inngest-bootstrap-build.yml"
CHECK_SH="$ROOT/.github/scripts/check-inngest-bootstrap-build.sh"
BUILD_WF="$ROOT/.github/workflows/build-inngest-bootstrap-image.yml"
for f in "$CHECK_WF" "$CHECK_SH" "$BUILD_WF"; do
  [[ -f "$f" ]] || { echo "FAIL: $f not found"; exit 1; }
done

passes=0; fails=0
ok()  { passes=$((passes + 1)); echo "  ok   $1"; }
bad() { fails=$((fails + 1)); echo "  FAIL $1"; }

# ── extraction (python; shared by every property) ───────────────────────────────────────
PY=/tmp/$$.extract.py
cat > "$PY" <<'PYEOF'
import re, sys, json

def read(p): return open(p).read()

def cp_sources(text):
    # `cp <repo-path> "$BUILD_DIR/<basename>"` — the carrier staging lines.
    return sorted(re.findall(r'cp\s+(apps/web-platform/infra/[^\s"]+)\s+"\$BUILD_DIR/', text))

def dockerfile_lines(text):
    # The Dockerfile heredoc body — every FROM/RUN/ENV/COPY/ENTRYPOINT/# line inside
    # the `<<DOCKERFILE` block, whitespace-normalized.
    m = re.search(r'<<DOCKERFILE\n(.*?)DOCKERFILE', text, re.S)
    if not m: return []
    out = []
    for ln in m.group(1).splitlines():
        ln = ln.strip()
        if not ln: continue
        # normalize: strip leading heredoc indentation already handled; collapse spaces
        out.append(re.sub(r'\s+', ' ', ln))
    return out

def shverify_block(text):
    # the download+verify span: from the curl line to the "Build-time SHA256 verified" line.
    m = re.search(r'(curl -fsSL.*?Build-time SHA256 verified[^\n]*)', text, re.S)
    if not m: return ""
    return re.sub(r'\s+', ' ', m.group(1)).strip()

def pin_greps(text):
    # the tf pin extraction greps — inngest_cli_version, inngest_cli_sha256,
    # vector_version, vector_sha256, vector_sha256_arm64.
    return sorted(set(re.findall(r'grep -E [^\n]*?(?:inngest\.tf|vector\.tf)[^\n]*', text)))

mode = sys.argv[1]
if mode == "cp":
    print("\n".join(cp_sources(read(sys.argv[2]))))
elif mode == "df":
    print("\n".join(dockerfile_lines(read(sys.argv[2]))))
elif mode == "sha":
    print(shverify_block(read(sys.argv[2])))
elif mode == "pins":
    print("\n".join(pin_greps(read(sys.argv[2]))))
PYEOF
trap 'rm -f "$PY"' EXIT

CP_CHECK="$(python3 "$PY" cp "$CHECK_SH")"
CP_AUTH="$(python3 "$PY" cp "$BUILD_WF")"
[ -n "$CP_AUTH" ] || { echo "FATAL: authority side produced no cp staging lines — extraction broken" >&2; exit 1; }
[ -n "$CP_CHECK" ] || { echo "FATAL: check side produced no cp staging lines — extraction broken" >&2; exit 1; }

# ── P1: carrier parity ──────────────────────────────────────────────────────────────────
if [[ "$CP_CHECK" == "$CP_AUTH" ]]; then
  ok "P1: cp carrier sets identical ($(printf '%s\n' "$CP_CHECK" | grep -c .) carriers)"
else
  bad "P1: carrier drift"; comm -3 <(printf '%s\n' "$CP_CHECK") <(printf '%s\n' "$CP_AUTH") | sed 's/^/      /' >&2
fi

# ── P2: Dockerfile parity ───────────────────────────────────────────────────────────────
DF_CHECK="$(python3 "$PY" df "$CHECK_SH")"
DF_AUTH="$(python3 "$PY" df "$BUILD_WF")"
[ -n "$DF_AUTH" ] || { echo "FATAL: no Dockerfile heredoc in the publish Build step" >&2; exit 1; }
if [[ "$DF_CHECK" == "$DF_AUTH" ]]; then
  ok "P2: Dockerfile bodies identical ($(printf '%s\n' "$DF_CHECK" | grep -c .) lines)"
else
  bad "P2: Dockerfile body drift"; diff <(printf '%s\n' "$DF_AUTH") <(printf '%s\n' "$DF_CHECK") | sed 's/^/      /' | head -20 >&2
fi

# ── P3: sha256-verify parity ────────────────────────────────────────────────────────────
SHA_CHECK="$(python3 "$PY" sha "$CHECK_SH")"
SHA_AUTH="$(python3 "$PY" sha "$BUILD_WF")"
[ -n "$SHA_AUTH" ] || { echo "FATAL: no sha256-verify block in the publish Build step" >&2; exit 1; }
if [[ "$SHA_CHECK" == "$SHA_AUTH" ]]; then
  ok "P3: sha256 download+verify block identical"
else
  bad "P3: sha256-verify block drift"; printf '      AUTH: %s\n      CHECK: %s\n' "$SHA_AUTH" "$SHA_CHECK" >&2
fi

# ── P3b: pin-grep parity ────────────────────────────────────────────────────────────────
PIN_CHECK="$(python3 "$PY" pins "$CHECK_SH")"
PIN_AUTH="$(python3 "$PY" pins "$BUILD_WF")"
if [[ "$PIN_CHECK" == "$PIN_AUTH" ]]; then
  ok "P3b: tf pin greps identical ($(printf '%s\n' "$PIN_CHECK" | grep -c .) sites)"
else
  bad "P3b: pin grep drift"; diff <(printf '%s\n' "$PIN_AUTH") <(printf '%s\n' "$PIN_CHECK") | sed 's/^/      /' | head -20 >&2
fi

# ── P4: no-publish ──────────────────────────────────────────────────────────────────────
# Token greps run over COMMENT-STRIPPED text: the lane's own comments name the forbidden
# operations to document the exclusion (that's the load-bearing documentation), so only a
# code-line occurrence is a violation.
CHECK_WF_CODE="$(grep -vE '^[[:space:]]*#' "$CHECK_WF" || true)"
CHECK_SH_CODE="$(grep -vE '^[[:space:]]*#' "$CHECK_SH" || true)"
for tok in 'docker push' 'cosign' 'crane' 'id-token' 'packages:' 'environment:' 'docker login' 'login-action'; do
  if printf '%s' "$CHECK_WF_CODE" | grep -qF "$tok" || printf '%s' "$CHECK_SH_CODE" | grep -qF "$tok"; then
    bad "P4: forbidden token '$tok' present in a code line of the check lane"
  else
    ok "P4: no '$tok' token in code"
  fi
done
# the script may only run `docker build` — no other docker subcommand.
DOCKER_SUBS="$(printf '%s\n' "$CHECK_SH_CODE" | grep -oE '\bdocker [a-z-]+' | sort -u)"
if [[ "$DOCKER_SUBS" == "docker build" ]]; then
  ok "P4: the script's only docker subcommand is 'build'"
else
  bad "P4: unexpected docker subcommand(s): $DOCKER_SUBS"
fi
# permissions: contents: read, and nothing more.
perm_line="$(python3 - "$CHECK_WF" <<'PYEOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
print("PERMS_OK" if doc.get("permissions") == {"contents": "read"} else "PERMS_BAD")
PYEOF
)"
[[ "$perm_line" == "PERMS_OK" ]] && ok "P4: permissions == contents:read only" || bad "P4: permissions not contents:read-only"

# ── P5: paths cover every cp carrier ────────────────────────────────────────────────────
PATHS="$(python3 - "$CHECK_WF" <<'PYEOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
paths = ((doc.get(True) or {}).get("pull_request") or {}).get("paths") or []
print("\n".join(paths))
PYEOF
)"
[ -n "$PATHS" ] || { echo "FATAL: no pull_request paths filter in the check workflow" >&2; exit 1; }
uncovered=0
while IFS= read -r src; do
  [ -z "$src" ] && continue
  hit=0
  while IFS= read -r g; do
    case "$src" in $g) hit=1 ;; esac
  done <<< "$PATHS"
  [ "$hit" -eq 1 ] || { uncovered=1; bad "P5: carrier $src is not covered by on.pull_request.paths"; }
done <<< "$CP_CHECK"
[ "$uncovered" -eq 0 ] && ok "P5: every cp carrier is covered by the paths filter"
# and the lane's own definition files are covered (a lane edit must re-run the lane).
for req in '.github/workflows/check-inngest-bootstrap-build.yml' '.github/scripts/check-inngest-bootstrap-build.sh'; do
  printf '%s\n' "$PATHS" | grep -qxF "$req" \
    && ok "P5: paths filter lists $req" \
    || bad "P5: paths filter does not list $req (lane edits would not re-run the lane)"
done

echo "test-check-inngest-bootstrap-build.sh: ${passes} passed, ${fails} failed"
[ "$fails" -eq 0 ] || exit 1
