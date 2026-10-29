#!/usr/bin/env bash
# Shared, REFUSING `gh` stub for the registry-host-replace dispatcher's `gate` step (#10650).
# Both suites that execute the gate body install a copy of this file as `gh` on PATH:
#   plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh   (terraform-free rows)
#   apps/web-platform/infra/registry-render-delta.test.sh                (render rows, needs terraform)
# One stub, so the two harnesses cannot drift on what the gate is allowed to ask.
#
# Not a `*.test.sh`, so no suite auto-glob runs it as a test.
#
# CONTRACT. The stub answers ONLY the requests the gate really makes, with the flags it really
# passes (learning 2026-09-25: a stub must mirror the real CLI's flags):
#   gh run list ...                              -> $STUB_WATERMARK
#   gh api repos/<r>/compare/<W>...<A>           -> $STUB_COMPARE   (the exact range only)
#   gh api repos/<r>/contents/<p>?ref=<ref> --jq .content
#                                                -> base64 of the file, WATERMARK ref only
#   gh api repos/<r>/contents/<p>?ref=<ref> --jq 'select(.type=="file")|.sha'
#                                                -> the git BLOB sha of the file at <ref>
# Everything else (including `gh workflow run`) is REFUSED: exit 64, and the refusal is appended
# to $STUB_ERR, because the gate discards gh's stderr (`2>/dev/null`) and a refusal visible only
# on stderr would be swallowed and the row would pass for the wrong reason. Each harness asserts
# $STUB_ERR is empty after every gate run.
#
# ENV (set by the harness):
#   GH_LOG          every argv, one line per call
#   STUB_ERR        refusal file
#   STUB_WATERMARK  the watermark sha (also the answer to `run list`)
#   STUB_AFTER      the head sha (the gate's AFTER_SHA)
#   STUB_COMPARE    the compare JSON
#   STUB_BEFORE     tree served for ref == STUB_WATERMARK
#   STUB_HEAD       tree served for ref == STUB_AFTER (blob reads only)
#   STUB_INPUTS     space-separated repo paths the blob route serves (the three render inputs)
# Modelled API failures (NOT refusals: the gate asked the right question):
#   STUB_CONTENTS_FAIL=1          every `.content` read fails (HTTP 502)
#   STUB_SHA_FAIL=<path>@<ref>    the blob read of <path> at <ref> fails (HTTP 502), every attempt
#   (a path in STUB_INPUTS that is absent from the tree answers `Not Found (HTTP 404)`, exit 1)
#
# The blob sha is computed WITHOUT spawning git (a test that spawns git needs the constructed
# environment from plugins/soleur/AGENTS.md; the pure sha1sum form needs none):
#   sha1("blob <size>\0<bytes>")
printf '%s\n' "$*" >> "$GH_LOG"
refuse() { printf 'stub: %s\n' "$*" | tee -a "$STUB_ERR" >&2; exit 64; }

if [[ "${1:-} ${2:-}" == "run list" ]]; then printf '%s\n' "$STUB_WATERMARK"; exit 0; fi
[[ "${1:-}" == "api" ]] || refuse "unrouted gh call: $*"

url="${2:-}"
case "$url" in
  */compare/*)
    [[ "$#" -eq 2 ]] || refuse "compare called with unexpected extra args: $*"
    [[ "$url" == *"/compare/${STUB_WATERMARK}...${STUB_AFTER}" ]] || refuse "compare for an unexpected range: $*"
    printf '%s' "$STUB_COMPARE"; exit 0 ;;
  */contents/*)
    [[ "$#" -eq 4 && "${3:-}" == "--jq" ]] || refuse "contents read with unexpected args: $*"
    p="${url#*/contents/}"; ref="${p##*\?ref=}"; p="${p%%\?ref=*}"
    case " ${STUB_INPUTS:-} " in *" $p "*) ;; *) refuse "contents read for an unexpected path '$p'" ;; esac
    case "${4:-}" in
      .content)
        [[ "$ref" == "$STUB_WATERMARK" ]] || refuse "content read for unexpected ref '$ref' (only the watermark's bytes are ever fetched)"
        [[ -n "${STUB_CONTENTS_FAIL:-}" ]] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
        f="$STUB_BEFORE/$p"
        [[ -f "$f" ]] || refuse "no BEFORE fixture for $p"
        # The real API wraps base64 at 60 columns; the gate pipes `.content` through `base64 -d`.
        base64 -w 60 "$f"; exit 0 ;;
      'select(.type=="file")|.sha')
        case "$ref" in
          "$STUB_WATERMARK") tree="$STUB_BEFORE" ;;
          "$STUB_AFTER") tree="$STUB_HEAD" ;;
          *) refuse "blob read for unexpected ref '$ref'" ;;
        esac
        [[ "${STUB_SHA_FAIL:-}" == "$p@$ref" ]] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
        f="$tree/$p"
        [[ -f "$f" ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        { printf 'blob %s\0' "$(wc -c < "$f" | tr -d '[:space:]')"; cat "$f"; } | sha1sum | cut -d' ' -f1
        exit 0 ;;
      *) refuse "contents read with an unexpected --jq program: $4" ;;
    esac ;;
esac
refuse "unrouted gh call: $*"
