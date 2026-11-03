#!/usr/bin/env bash
# gh-stub.sh: a stateful fake of the GitHub CLI for test/issues-common.sh (sourced by issues-guards.test.sh and issues-resume.test.sh). The suite copies this file to <bin>/gh and
# puts <bin> first on PATH. It never touches the network and never reads a credential.
#
# STUB CONTRACT. Each emulated shape is marked either
#   [verified 2026-11-03]  checked against a real response by the plan author (gh 2.103.3), or
#   [UNVERIFIED-STUB-ONLY] invented here from documentation; a suite row that depends on it is tagged in its label.
# The live check of the unverified shapes is the tracked follow-up (#11956); nothing here is proof of GitHub's behaviour.
#   gh auth status [--hostname H]                      exit 0, or 1 under GH_STUB_AUTH=fail     [UNVERIFIED-STUB-ONLY]
#   gh repo view --json F[,F] [--jq E]                 F in nameWithOwner,isFork,isArchived,visibility,url,name,owner;
#                                                      any other field exits 1 "Unknown JSON field" [UNVERIFIED-STUB-ONLY]
#   gh api -X GET <path> [-f k=v]... [--jq E] [--paginate] [--hostname H]
#     repos/O/R                 object with visibility, archived, has_issues, fork, permissions.push [UNVERIFIED-STUB-ONLY]
#     repos/O/R/issues          listing: labels, state, per_page, page; default page size 30; --jq runs per page;
#                               rows carry number, id, state, title, body (may be null), labels, user.login, and
#                               pull_request only for a PR               [verified 2026-11-03: rows and the -X GET -f ... --paginate form]
#     repos/O/R/issues/N        one issue                                [UNVERIFIED-STUB-ONLY]
#     repos/O/R/issues/N/sub_issues   200 and a list of children        [verified 2026-11-03: the 200 on a real repository]
#     repos/O/R/labels          listing                                  [UNVERIFIED-STUB-ONLY]
#     user                      {"login": GH_STUB_LOGIN}                 [UNVERIFIED-STUB-ONLY]
#   gh api -X POST repos/O/R/labels -f name= -f color= -f description=   201, or 422 already_exists [UNVERIFIED-STUB-ONLY]
#   gh api -X POST repos/O/R/issues -f title= -F body=@file|-f body= -f labels[]=...
#                                                      201 with .number and .id (a database id far above 2^31);
#                                                      a label that does not exist is a 422 (stricter than GitHub) [UNVERIFIED-STUB-ONLY]
#   gh api -X POST repos/O/R/issues/N/sub_issues -F sub_issue_id=<integer>
#                                                      GH_STUB_SUBISSUE=ok|403|404|410|422 [UNVERIFIED-STUB-ONLY bodies];
#                                                      a string-typed sub_issue_id (-f) or a second parent is a 422
#   gh api -X PATCH repos/O/R/issues/N -F body=@file   the only accepted field keys are body and title [UNVERIFIED-STUB-ONLY]
#   Failure output: stderr "gh: <message> (HTTP <code>)" and the JSON error body on stdout. [UNVERIFIED-STUB-ONLY]
#   gojq differs from jq on null handling; this stub runs real jq, so null-body rows are tagged UNVERIFIED-STUB-ONLY.
#
# Contract enforcement (a stub that accepts anything proves nothing): an unknown subcommand, flag or method exits 64 with a
# REFUSE line in refused.log; a field key outside title, body, labels[], sub_issue_id, name, color, description exits 64;
# an api call that carries no explicit -X is written to violations.log (a field flag flips an implicit call to POST).
#
# State directory (GH_STUB_STATE): repo.json, labels.json, issues.json, calls.log (JSON lines, one per MATCHED call,
# written inside the dispatch branch only), refused.log, violations.log, pages.log, bodies/<seq>-<key> (the bytes
# received for every body field, stored independently of the caller's own files).
# Failure injection (environment): GH_STUB_AUTH=ok|fail; GH_STUB_REPO=ok|unresolved|ambiguous; GH_STUB_HOST (default
# github.com); GH_STUB_LOGIN (default stub-user); GH_STUB_FAIL_AFTER=<n> (every item create after the n-th fails, the
# epic is not counted); GH_STUB_FAIL_KIND=server|ratelimit|secret; GH_STUB_TRANSPORT_ERROR_AFTER_CREATE=<n> (alias
# GH_STUB_KILL_AFTER_CREATE: right after storing the n-th item create exit 1 with no output, once; the harness is never
# killed); GH_STUB_SUBISSUE=ok|403|404|410|422|ratelimit|502 (the link POST only); GH_STUB_SLEEP=<seconds> (an item create sleeps that long after storing the issue, before it answers: a window for a signal); GH_STUB_PER_PAGE=<n> (forces pagination); GH_STUB_EDIT_EPIC_BETWEEN=get|write (a customer
# edit of the epic body: before serving the first epic GET that follows a listing, or after the first item create);
# GH_STUB_CRLF=1 (the epic body is stored with CRLF line endings); GH_STUB_LIST=ok|fail|malformed (the issue listing).
set -u
S=${GH_STUB_STATE:-}
if [ -z "$S" ] || [ ! -d "$S" ]; then printf 'gh-stub: REFUSE GH_STUB_STATE unset or missing\n' >&2; exit 64; fi
mkdir -p "$S/bodies"
HOST=${GH_STUB_HOST:-github.com}
LOGIN=${GH_STUB_LOGIN:-stub-user}

refuse() { printf '%s\n' "$*" >> "$S/refused.log"; printf 'gh-stub: REFUSE %s\n' "$*" >&2; exit 64; }
violation() { printf '%s\n' "$*" >> "$S/violations.log"; }
counter() { # counter <name>: increment and print
  local n; n=$(( $(cat "$S/$1" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$S/$1"; printf '%s' "$n"
}
secret_shaped() { printf '%s%s' 'ghp_' 'Q3nW8tY1kD6vB2xM9cL5hZ7pR4aE0sJ2fG1u'; }
http_fail() { # http_fail <code> <message> [extra stderr line]
  printf '{"message":"%s","status":"%s"}\n' "$2" "$1"
  printf 'gh: %s (HTTP %s)\n' "$2" "$1" >&2
  [ -n "${3:-}" ] && printf '%s\n' "$3" >&2
  exit 1
}
env_json() { # names of the hostile variables that are set, with their values (never a token)
  local v out='{}'
  for v in GH_REPO GH_HOST GH_ENTERPRISE_TOKEN GH_DEBUG GH_CONFIG_DIR HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy; do
    if [ -n "${!v+x}" ]; then
      case "$v" in GH_ENTERPRISE_TOKEN) out=$(jq -nc --argjson o "$out" --arg k "$v" '$o + {($k): "(set)"}') ;;
        *) out=$(jq -nc --argjson o "$out" --arg k "$v" --arg val "${!v}" '$o + {($k): $val}') ;; esac
    fi
  done
  printf '%s' "$out"
}
record() { # record <class> <method> <path> <explicit 0|1> [extra-json-object]
  local seq; seq=$(counter seq)
  CUR_SEQ=$seq
  jq -nc --argjson seq "$seq" --arg class "$1" --arg method "$2" --arg path "$3" --argjson explicit "$4" \
    --argjson fields "${FIELDS:-[]}" --arg jq "${JQEXPR:-}" --argjson paginate "${PAGINATE:-0}" --arg hostname "${HOSTNAME_FLAG:-}" \
    --argjson env "$(env_json)" --arg cwd "$PWD" --argjson token "$([ -n "${GH_TOKEN:-}" ] && echo true || echo false)" \
    --argjson extra "${5:-{\}}" \
    '{seq:$seq,class:$class,method:$method,path:$path,explicit_method:($explicit==1),fields:$fields,jq:$jq,paginate:($paginate==1),hostname:$hostname,env:$env,cwd:$cwd,token_present:$token} + $extra' >> "$S/calls.log"
}
jq_out() { # jq_out <json> : apply --jq (real jq -r) or print compact JSON
  if [ -n "${JQEXPR:-}" ]; then printf '%s' "$1" | jq -r "$JQEXPR" || exit 1; else printf '%s' "$1" | jq -c .; fi
}
repo_field() { jq -r "$1" "$S/repo.json"; }
need_auth() { if [ "${GH_STUB_AUTH:-ok}" = fail ]; then printf 'gh: To use GitHub CLI, run: gh auth login\n' >&2; exit 4; fi; }

sub=${1:-}; [ $# -gt 0 ] && shift
case "$sub" in
  --version)
    record other VERSION "--version" 0; printf 'gh version 2.103.3 (stub)\n'; exit 0 ;;
  auth)
    [ "${1:-}" = status ] || refuse "auth subcommand ${1:-}"
    shift; host=""
    while [ $# -gt 0 ]; do case "$1" in --hostname) host=${2:-}; shift 2 ;; *) refuse "auth status flag $1" ;; esac; done
    FIELDS='[]'; HOSTNAME_FLAG=$host; record auth GET "auth status" 0
    if [ "${GH_STUB_AUTH:-ok}" = fail ]; then printf 'You are not logged into any GitHub hosts. To log in, run: gh auth login\n' >&2; exit 1; fi
    printf '%s\n  Logged in to %s account %s (keyring)\n' "$HOST" "$HOST" "$LOGIN"; exit 0 ;;
  repo)
    [ "${1:-}" = view ] || refuse "repo subcommand ${1:-}"
    shift; json=""; JQEXPR=""
    while [ $# -gt 0 ]; do case "$1" in --json) json=${2:-}; shift 2 ;; --jq|-q) JQEXPR=${2:-}; shift 2 ;; *) refuse "repo view argument $1" ;; esac; done
    [ -n "$json" ] || refuse "repo view without --json"
    FIELDS='[]'; record repo GET "repo view" 0 "$(jq -nc --arg j "$json" '{json:$j}')"
    need_auth
    case "${GH_STUB_REPO:-ok}" in
      unresolved) printf 'none of the git remotes configured for this repository point to a known GitHub host. To tell gh about a new GitHub host, please use `gh auth login`\n' >&2; exit 1 ;;
      ambiguous) printf 'multiple remotes detected. please specify which repo to use by providing the -R, --repo argument, or run `gh repo set-default`\n' >&2; exit 1 ;;
    esac
    obj='{}'
    IFS=, read -r -a want <<<"$json"
    for f in "${want[@]}"; do
      case "$f" in
        nameWithOwner) v=$(repo_field '.full_name') ;;
        name) v=$(repo_field '.name') ;;
        owner) v=$(repo_field '.owner.login') ;;
        isFork) v=$(repo_field '.fork') ;;
        isArchived) v=$(repo_field '.archived') ;;
        visibility) v=$(repo_field '.visibility|ascii_upcase') ;;
        url) v="https://$HOST/$(repo_field '.full_name')" ;;
        *) printf 'Unknown JSON field: "%s"\n' "$f" >&2; exit 1 ;;
      esac
      case "$f" in isFork|isArchived) obj=$(jq -nc --argjson o "$obj" --arg k "$f" --argjson v "$v" '$o + {($k): $v}') ;;
        *) obj=$(jq -nc --argjson o "$obj" --arg k "$f" --arg v "$v" '$o + {($k): $v}') ;; esac
    done
    jq_out "$obj"; exit 0 ;;
  api) ;;
  *) refuse "subcommand $sub" ;;
esac

# ---- gh api ----
METHOD=""; EXPLICIT=0; JQEXPR=""; PAGINATE=0; HOSTNAME_FLAG=""; ENDPOINT=""; FIELDS='[]'
FK=(); FV=(); FT=()
while [ $# -gt 0 ]; do
  case "$1" in
    -X|--method) [ $# -ge 2 ] || refuse "api flag $1 needs a value"; METHOD=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]'); EXPLICIT=1; shift 2 ;;
    -f|--raw-field|-F|--field)
      [ $# -ge 2 ] || refuse "api flag $1 needs a value"
      t=f; case "$1" in -F|--field) t=F ;; esac
      kv=$2; case "$kv" in *=*) ;; *) refuse "api field without =: $kv" ;; esac
      FK+=("${kv%%=*}"); FV+=("${kv#*=}"); FT+=("$t"); shift 2 ;;
    --jq|-q) [ $# -ge 2 ] || refuse "api flag $1 needs a value"; JQEXPR=$2; shift 2 ;;
    --paginate) PAGINATE=1; shift ;;
    --hostname) [ $# -ge 2 ] || refuse "api flag $1 needs a value"; HOSTNAME_FLAG=$2; shift 2 ;;
    -*) refuse "api flag $1" ;;
    *) [ -z "$ENDPOINT" ] || refuse "api extra positional $1"; ENDPOINT=$1; shift ;;
  esac
done
[ -n "$ENDPOINT" ] || refuse "api without an endpoint"
nf=${#FK[@]}
if [ -z "$METHOD" ]; then
  if [ "$nf" -gt 0 ]; then METHOD=POST; else METHOD=GET; fi
fi
case "$METHOD" in GET|POST|PATCH) ;; *) refuse "api method $METHOD" ;; esac
ENDPOINT=${ENDPOINT#/}
QUERY=""; case "$ENDPOINT" in *\?*) QUERY=${ENDPOINT#*\?}; ENDPOINT=${ENDPOINT%%\?*} ;; esac
# Field-key allowlist (an independent witness of the wrapper's own list).
i=0
while [ "$i" -lt "$nf" ]; do
  case "${FK[$i]}" in
    title|body|'labels[]'|sub_issue_id|name|color|description) ;;
    *) if [ "$METHOD" != GET ]; then refuse "field key ${FK[$i]}"; fi ;;
  esac
  i=$((i + 1))
done
[ "$EXPLICIT" = 1 ] || violation "implicit-method $ENDPOINT"

# Build the fields JSON (and store every body-like field's bytes independently).
CUR_SEQ=$(( $(cat "$S/seq" 2>/dev/null || echo 0) + 1 ))
i=0
while [ "$i" -lt "$nf" ]; do
  k=${FK[$i]}; v=${FV[$i]}; t=${FT[$i]}
  if [ "$t" = F ] && [ "${v#@}" != "$v" ]; then
    path=${v#@}
    [ "$path" != "-" ] || refuse "stdin field operand"
    if [ ! -f "$path" ]; then printf 'open %s: no such file or directory\n' "$path" >&2; exit 1; fi
    if [ "$METHOD" != GET ]; then cp "$path" "$S/bodies/$CUR_SEQ-${k//[^A-Za-z0-9]/_}"; fi
    FIELDS=$(jq -nc --argjson a "$FIELDS" --arg k "$k" --arg v "$v" --arg t "$t" --arg file "$path" --rawfile c "$path" \
      --arg stored "bodies/$CUR_SEQ-${k//[^A-Za-z0-9]/_}" '$a + [{k:$k,v:$v,t:$t,file:$file,content:$c,stored:$stored}]')
  else
    FIELDS=$(jq -nc --argjson a "$FIELDS" --arg k "$k" --arg v "$v" --arg t "$t" '$a + [{k:$k,v:$v,t:$t}]')
    if [ "$METHOD" != GET ] && [ "$k" = body ]; then printf '%s' "$v" > "$S/bodies/$CUR_SEQ-body"; fi
  fi
  i=$((i + 1))
done

fld() { # fld <key>: first value of a field (or query) key
  jq -rn --argjson f "$FIELDS" --arg k "$1" --arg q "$QUERY" '
    ([$f[] | select(.k == $k) | .v] | first) // ([$q | split("&")[] | select(startswith($k + "=")) | sub("^[^=]*="; "")] | first) // empty'
}
fld_all() { jq -rn --argjson f "$FIELDS" --arg k "$1" '$f[] | select(.k == $k) | .v'; }
fld_type() { jq -rn --argjson f "$FIELDS" --arg k "$1" '[$f[] | select(.k == $k) | .t] | first // empty'; }

repo_ok() { # the path's owner/name must be the stub's repository
  local want; want=$(repo_field '.full_name' | tr '[:upper:]' '[:lower:]')
  [ "$(printf '%s/%s' "$1" "$2" | tr '[:upper:]' '[:lower:]')" = "$want" ]
}
issue_pub='del(.parent)'
PATTERN_REPO='^repos/([^/]+)/([^/]+)$'
PATTERN_SUB='^repos/([^/]+)/([^/]+)/issues/([0-9]+)/sub_issues$'
PATTERN_ONE='^repos/([^/]+)/([^/]+)/issues/([0-9]+)$'
PATTERN_LIST='^repos/([^/]+)/([^/]+)/(issues|labels)$'

paginate_emit() { # paginate_emit <json array>: pages of per_page (default 30), jq per page, pages.log
  local arr=$1 per page=1 total n s pages=0 slice
  per=$(fld per_page); per=${per:-30}; [ -n "${GH_STUB_PER_PAGE:-}" ] && per=$GH_STUB_PER_PAGE
  total=$(jq 'length' <<<"$arr")
  if [ "$PAGINATE" = 0 ]; then
    slice=$(jq -c --argjson s 0 --argjson n "$per" '.[$s:$s+$n]' <<<"$arr"); pages=1; jq_out "$slice"
  else
    s=0
    while :; do
      n=$(jq -r --argjson s "$s" --argjson n "$per" '.[$s:$s+$n] | length' <<<"$arr")
      slice=$(jq -c --argjson s "$s" --argjson n "$per" '.[$s:$s+$n]' <<<"$arr")
      pages=$((pages + 1)); jq_out "$slice" || exit 1
      s=$((s + per)); [ "$n" -ge "$per" ] && [ "$s" -lt "$total" ] || break
    done
  fi
  printf '%s\t%s\n' "$CUR_SEQ" "$pages" >> "$S/pages.log"
}

route="$METHOD $ENDPOINT"
case "$route" in
  "GET user")
    record read GET "$ENDPOINT" "$EXPLICIT"; need_auth
    jq_out "$(jq -nc --arg l "$LOGIN" '{login:$l}')"; exit 0 ;;
esac

if [[ "$ENDPOINT" =~ $PATTERN_REPO ]]; then
  if [ "$METHOD" = GET ]; then
    record read GET "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" || http_fail 404 "Not Found"
    jq_out "$(cat "$S/repo.json")"; exit 0
  fi
fi

if [[ "$ENDPOINT" =~ $PATTERN_LIST ]]; then
  o=${BASH_REMATCH[1]}; r=${BASH_REMATCH[2]}; kind=${BASH_REMATCH[3]}
  if [ "$METHOD" = GET ] && [ "$kind" = labels ]; then
    record read GET "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    paginate_emit "$(cat "$S/labels.json")"; exit 0
  fi
  if [ "$METHOD" = POST ] && [ "$kind" = labels ]; then
    record write POST "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    name=$(fld name); color=$(fld color); desc=$(fld description)
    [ -n "$name" ] || http_fail 422 "Validation Failed"
    if jq -e --arg n "$name" 'map(.name | ascii_downcase) | index($n | ascii_downcase)' "$S/labels.json" >/dev/null; then
      http_fail 422 "Validation Failed" '{"resource":"Label","code":"already_exists","field":"name"}'
    fi
    new=$(jq -nc --arg n "$name" --arg c "${color:-ededed}" --arg d "$desc" '{name:$n,color:$c,description:$d}')
    jq -c --argjson l "$new" '. + [$l]' "$S/labels.json" > "$S/labels.json.new" && mv "$S/labels.json.new" "$S/labels.json"
    jq_out "$new"; exit 0
  fi
  if [ "$METHOD" = GET ] && [ "$kind" = issues ]; then
    record read GET "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    case "${GH_STUB_LIST:-ok}" in
      fail) http_fail 500 "Server Error" ;;
      malformed) printf '<<not a listing>>\n\037\n'; exit 0 ;;
    esac
    st=$(fld state); st=${st:-open}; lab=$(fld labels)
    touch "$S/listing_seen"
    arr=$(jq -c --arg st "$st" --arg lab "$lab" '
      [.[] | select($st == "all" or .state == $st)
           | select($lab == "" or ((.labels | map(.name)) as $n | ($lab | split(",")) | all(. as $w | $n | index($w))))
           | del(.parent)]' "$S/issues.json")
    paginate_emit "$arr"; exit 0
  fi
  if [ "$METHOD" = POST ] && [ "$kind" = issues ]; then
    record write POST "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    title=$(fld title); [ -n "$title" ] || http_fail 422 "Validation Failed"
    labs=$(fld_all 'labels[]' | jq -R . | jq -sc .)
    epic=false; jq -e 'index("lc:epic")' <<<"$labs" >/dev/null && epic=true
    missing=$(jq -nr --argjson l "$labs" --slurpfile all "$S/labels.json" '[$l[] | select(. as $w | ($all[0] | map(.name) | index($w)) == null)] | join(",")')
    [ -z "$missing" ] || http_fail 422 "Validation Failed"
    if [ "$epic" = false ]; then
      done_n=$(cat "$S/creates" 2>/dev/null || echo 0)
      if [ -n "${GH_STUB_FAIL_AFTER:-}" ] && [ "$done_n" -ge "$GH_STUB_FAIL_AFTER" ]; then
        case "${GH_STUB_FAIL_KIND:-server}" in
          ratelimit) http_fail 403 "You have exceeded a secondary rate limit. Please wait a few minutes before you try again." ;;
          secret) http_fail 502 "Server Error" "request id token=$(secret_shaped)" ;;
          *) http_fail 502 "Server Error" ;;
        esac
      fi
    fi
    bodyf="$S/bodies/$CUR_SEQ-body"; [ -f "$bodyf" ] || : > "$bodyf"
    crlf=false; [ "$epic" = true ] && [ "${GH_STUB_CRLF:-0}" = 1 ] && crlf=true
    num=$(( $(cat "$S/next_number" 2>/dev/null || echo 100) + 1 )); printf '%s' "$num" > "$S/next_number"
    id=$((4000000000 + num * 13))
    new=$(jq -nc --argjson n "$num" --argjson id "$id" --arg t "$title" --rawfile b "$bodyf" --argjson crlf "$crlf" --arg login "$LOGIN" --argjson l "$labs" \
      '{number:$n,id:$id,state:"open",title:$t,body:(if $crlf then ($b | gsub("\n"; "\r\n")) else $b end),labels:($l|map({name:.})),user:{login:$login},parent:null,html_url:("https://example.invalid/issues/"+($n|tostring))}')
    jq -c --argjson i "$new" '. + [$i]' "$S/issues.json" > "$S/issues.json.new" && mv "$S/issues.json.new" "$S/issues.json"
    if [ "$epic" = false ]; then
      made=$(counter creates)
      if [ "${GH_STUB_EDIT_EPIC_BETWEEN:-}" = write ] && [ ! -e "$S/epic_edit_write_done" ]; then
        : > "$S/epic_edit_write_done"
        jq -c '(.[] | select(.labels | map(.name) | index("lc:epic"))) |= (.body += "\nCUSTOMER-EDIT-MIDRUN\n")' "$S/issues.json" > "$S/issues.json.new" && mv "$S/issues.json.new" "$S/issues.json"
        printf 'epic edited after item create %s\n' "$made" >> "$S/events.log"
      fi
      [ -z "${GH_STUB_SLEEP:-}" ] || sleep "$GH_STUB_SLEEP"
      tx=${GH_STUB_TRANSPORT_ERROR_AFTER_CREATE:-${GH_STUB_KILL_AFTER_CREATE:-}}
      if [ -n "$tx" ] && [ "$made" = "$tx" ] && [ ! -e "$S/transport_fired" ]; then : > "$S/transport_fired"; exit 1; fi
    fi
    jq_out "$(jq -c "$issue_pub" <<<"$new")"; exit 0
  fi
fi

if [[ "$ENDPOINT" =~ $PATTERN_SUB ]]; then
  o=${BASH_REMATCH[1]}; r=${BASH_REMATCH[2]}; n=${BASH_REMATCH[3]}
  cls=read; [ "$METHOD" = POST ] && cls=write
  [ "$METHOD" = GET ] || [ "$METHOD" = POST ] || refuse "sub_issues method $METHOD"
  record "$cls" "$METHOD" "$ENDPOINT" "$EXPLICIT"; need_auth
  repo_ok "$o" "$r" || http_fail 404 "Not Found"
  case "${GH_STUB_SUBISSUE:-ok}" in
    ok) ;;
    403) http_fail 403 "Forbidden" ;;
    404) http_fail 404 "Not Found" ;;
    410) http_fail 410 "Gone" ;;
    422) http_fail 422 "Validation Failed" ;;
    ratelimit) http_fail 403 "You have exceeded a secondary rate limit. Please wait a few minutes before you try again." ;;
    502) http_fail 502 "Server Error" ;;
  esac
  jq -e --argjson n "$n" 'map(select(.number == $n)) | length > 0' "$S/issues.json" >/dev/null || http_fail 404 "Not Found"
  if [ "$METHOD" = GET ]; then
    paginate_emit "$(jq -c --argjson n "$n" '[.[] | select(.parent == $n) | del(.parent)]' "$S/issues.json")"; exit 0
  fi
  sid=$(fld sub_issue_id)
  if [ "$(fld_type sub_issue_id)" != F ] || ! [[ "$sid" =~ ^[0-9]+$ ]]; then
    violation "sub_issue_id-not-integer $sid"; http_fail 422 "Validation Failed"
  fi
  jq -e --argjson id "$sid" 'map(select(.id == $id)) | length > 0' "$S/issues.json" >/dev/null || http_fail 404 "Not Found"
  if jq -e --argjson id "$sid" 'map(select(.id == $id and .parent != null)) | length > 0' "$S/issues.json" >/dev/null; then http_fail 422 "Validation Failed"; fi
  jq -c --argjson id "$sid" --argjson n "$n" '(.[] | select(.id == $id) | .parent) |= $n' "$S/issues.json" > "$S/issues.json.new" && mv "$S/issues.json.new" "$S/issues.json"
  jq_out "$(jq -c --argjson n "$n" '.[] | select(.number == $n) | del(.parent)' "$S/issues.json")"; exit 0
fi

if [[ "$ENDPOINT" =~ $PATTERN_ONE ]]; then
  o=${BASH_REMATCH[1]}; r=${BASH_REMATCH[2]}; n=${BASH_REMATCH[3]}
  if [ "$METHOD" = GET ]; then
    record read GET "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    if [ "${GH_STUB_EDIT_EPIC_BETWEEN:-}" = get ] && [ -e "$S/listing_seen" ] && [ ! -e "$S/epic_edited" ] \
       && jq -e --argjson n "$n" '.[] | select(.number == $n) | .labels | map(.name) | index("lc:epic")' "$S/issues.json" >/dev/null; then
      : > "$S/epic_edited"
      jq -c '(.[] | select(.labels | map(.name) | index("lc:epic"))) |= (.body += "\nCUSTOMER-EDIT-MIDRUN\n")' "$S/issues.json" > "$S/issues.json.new" && mv "$S/issues.json.new" "$S/issues.json"
      printf 'epic edited before the first GET after a listing\n' >> "$S/events.log"
    fi
    one=$(jq -c --argjson n "$n" '[.[] | select(.number == $n)] | first // empty | del(.parent)' "$S/issues.json")
    [ -n "$one" ] || http_fail 404 "Not Found"
    jq_out "$one"; exit 0
  fi
  if [ "$METHOD" = PATCH ]; then
    record write PATCH "$ENDPOINT" "$EXPLICIT"; need_auth
    repo_ok "$o" "$r" || http_fail 404 "Not Found"
    bad=$(jq -rn --argjson f "$FIELDS" '[$f[] | select(.k != "body" and .k != "title") | .k] | join(",")')
    [ -z "$bad" ] || refuse "PATCH field $bad"
    jq -e --argjson n "$n" 'map(select(.number == $n)) | length > 0' "$S/issues.json" >/dev/null || http_fail 404 "Not Found"
    if [ -f "$S/bodies/$CUR_SEQ-body" ]; then
      jq -c --argjson n "$n" --rawfile b "$S/bodies/$CUR_SEQ-body" '(.[] | select(.number == $n) | .body) |= $b' "$S/issues.json" > "$S/issues.json.new" && mv "$S/issues.json.new" "$S/issues.json"
    fi
    jq_out "$(jq -c --argjson n "$n" '.[] | select(.number == $n) | del(.parent)' "$S/issues.json")"; exit 0
  fi
fi

violation "unrouted $METHOD $ENDPOINT"
printf '{"message":"Not Found","status":"404"}\n'; printf 'gh: Not Found (HTTP 404)\n' >&2
exit 1
