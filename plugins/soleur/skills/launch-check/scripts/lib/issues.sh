# shellcheck shell=bash
# The issue writer: the only part of launch-check that writes to a customer's tracker, and only from a saved plan.
# Contract with launch-check.sh: TARGET, WORK, FACTS, JUDGED, LC_DRY, REPORT_REL, SKILL_DIR and the ISSUES_* option variables
# are set by cmd_issues. Sourced; never executed. Bash 3.2 safe (no associative arrays, no mapfile).
#
# Four guards (see the plan's Guard Contract and test/issues-guards.test.sh and test/issues-resume.test.sh):
#   1 saved-plan-only writes   lc__gh_exec is the only place the CLI is invoked; lc_gh_read always sends -X GET; lc_gh_write
#                              is a closed allowlist (headless, dry-run, four REST shapes, field keys, confined @file operands).
#   2 authored bytes are scanned bytes   every title, body, label and epic section passes lc_emit_checked (scan-only) on the exact
#                              bytes that are sent; bodies are regenerated from catalog, facts and ids and byte-compared to the plan.
#   3 idempotency and resume   the live identity is the scope label plus the body marker, read through one paginated listing.
#   4 epic edits are confined to the marked section (lc_epic_splice).
# Nothing here prints raw CLI stderr or tracker text: failures are mapped to a closed detail= token set, and every printed
# line passes lc_scrub. Markers are emitted from this file on purpose (outside the telemetry drift guard's walk).

ISSUES_RE_SLUG='^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$'
ISSUES_RE_ID='^[A-Z]+-[A-Za-z0-9-]+$'
ISSUES_RE_TITLE="^[A-Za-z0-9 .,:;()'/+_-]+\$"
ISSUES_CAP=30
LC_TAB=$(printf '\t')
ISSUES_MAX_BYTES=65536
LC_WRITES_DONE=0
LC_GH_HTTP=""; LC_GH_KIND=ok

lc__say() { printf '%s\n' "$(lc_scrub "$*")"; }
# lc__fmt <phrase-key> [values...]: a shipped phrase with its %s slots filled, as one scrubbed line.
lc__fmt() {
  local f; f=$(lc_phrase "$1"); shift
  # shellcheck disable=SC2059  # the format is our own shipped phrase, never repository content
  lc__say "$(printf -- "$f" "$@")"
}
# lc__re <ERE> <value>: the whole one-line value matches (awk, so the same grammar on every platform).
lc__re() { RE_X=$1 awk '{ if (NR == 1 && $0 ~ ENVIRON["RE_X"]) ok = 1; n = NR } END { exit !(ok && n == 1) }' <<<"$2"; }
lc__refuse() { lc_abort write-shape-refused 2 "detail=$1"; }
lc__pbad() { lc_abort plan-invalid 2 "detail=$1"; }
lc__stale() { lc__fmt report_stale_fix; lc_abort report-stale 2 "detail=$1"; }
lc__lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
lc__same_slug() { [ "$(lc__lower "$1")" = "$(lc__lower "$2")" ]; }

# ---------------------------------------------------------------- Guard 1: the gh wrappers
# lc__gh_exec <args...>: the ONLY place the GitHub CLI is invoked. Environment scrubbed (a repository's shell profile cannot
# redirect the call), a neutral working directory (except for the two verbs that resolve the repository from its remotes),
# stderr captured and classified, never printed. Sets LC_GH_HTTP and LC_GH_KIND (ok | rate-limit | http-NNN | failed);
# stdout lands in $WORK/gh.out.
lc__gh_exec() {
  local cwd=$WORK rc=0 bound="" err="$WORK/gh.err"
  local -a scrub=(-u GH_REPO -u GH_ENTERPRISE_TOKEN -u GH_DEBUG -u DEBUG -u GH_CONFIG_DIR -u GH_PATH -u GH_FORCE_TTY -u SSL_CERT_FILE -u SSL_CERT_DIR
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY -u http_proxy -u https_proxy -u all_proxy -u no_proxy)
  case "${1:-}" in auth|repo) cwd=$TARGET ;; esac
  # An enterprise token is the credential of the host that --host named; for github.com it must not steer the call.
  [ "${ISSUES_HOST:-github.com}" != github.com ] || scrub+=(-u GITHUB_ENTERPRISE_TOKEN)
  if command -v timeout >/dev/null 2>&1; then bound="timeout 120"; elif command -v gtimeout >/dev/null 2>&1; then bound="gtimeout 120"; fi
  : > "$WORK/gh.out"; : > "$err"
  # GH_HOST is always the target host (github.com included), so an inherited value or a remote on another host cannot redirect the call.
  # shellcheck disable=SC2086  # $bound is deliberately split into command and argument
  ( cd "$cwd" && exec $bound env "${scrub[@]}" \
      GH_HOST="${ISSUES_HOST:-github.com}" GH_PROMPT_DISABLED=1 NO_COLOR=1 GH_NO_UPDATE_NOTIFIER=1 \
      gh "$@" ) > "$WORK/gh.out" 2> "$err" < /dev/null || rc=$?
  LC_GH_HTTP=""; LC_GH_KIND=ok
  if [ "$rc" -ne 0 ]; then
    LC_GH_HTTP=$(grep -o 'HTTP [0-9][0-9][0-9]' "$err" | tail -n 1 | cut -c6-)
    if grep -qi 'rate limit' "$err"; then LC_GH_KIND=rate-limit
    elif [ -n "$LC_GH_HTTP" ]; then LC_GH_KIND="http-$LC_GH_HTTP"
    else LC_GH_KIND=failed; fi
  fi
  return "$rc"
}

# lc_gh_read <auth status|repo view|api> ...: a read (`auth` takes only `status`, `repo` only `view`). For `api` the method is always sent as -X GET (a field flag would otherwise flip the call
# to POST); any other method is refused.
lc_gh_read() {
  case "${1:-}" in
    auth) [ "${2:-}" = status ] || lc_abort write-shape-refused 2 "detail=read-verb"; lc__gh_exec "$@"; return $? ;;
    repo) [ "${2:-}" = view ] || lc_abort write-shape-refused 2 "detail=read-verb"; lc__gh_exec "$@"; return $? ;;
    api) shift ;;
    *) lc_abort write-shape-refused 2 "detail=read-verb" ;;
  esac
  local -a rest=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -X|--method) [ "${2:-}" = GET ] || lc_abort write-shape-refused 2 "detail=read-not-get"; shift 2 ;;
      -X*|--method=*) lc_abort write-shape-refused 2 "detail=read-not-get" ;;
      graphql|*/graphql) lc_abort write-shape-refused 2 "detail=read-graphql" ;;
      *) rest+=("$1"); shift ;;
    esac
  done
  lc__gh_exec api -X GET ${rest[@]+"${rest[@]}"}
}

# lc__file_ok <path>: a regular file, not a symlink, whose physical location is inside the validated plan copy or the tool's own
# scratch directory for epic bodies.
lc__file_ok() {
  local p=$1 d b real root r
  [ -f "$p" ] && [ ! -L "$p" ] || return 1
  d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
  b=$(basename "$p"); real="$d/$b"
  for root in "${ISSUES_PLAN_DIR:-}" "${WORK:+$WORK/out}"; do
    [ -n "$root" ] || continue
    r=$(cd "$root" 2>/dev/null && pwd -P) || continue
    case "$real" in "$r"/*) return 0 ;; esac
  done
  return 1
}

# lc__write_shape <args as given to lc_gh_write>: abort write-shape-refused unless the call is one of the four allowlisted forms.
lc__write_shape() {
  local method path slug="${ISSUES_REPO:-}" shape="" n key val flag kv allowed=""
  [ "$#" -ge 4 ] && [ "$1" = api ] && [ "$2" = -X ] || lc__refuse not-api
  method=$3; path=$4; shift 4
  [ -n "$slug" ] && lc__re "$ISSUES_RE_SLUG" "$slug" || lc__refuse no-repo
  case "$method $path" in
    "POST repos/$slug/labels") shape="labels"; allowed=" name color description " ;;
    "POST repos/$slug/issues") shape="issue"; allowed=" title body labels[] " ;;
    "POST repos/$slug/issues/"*"/sub_issues") shape="sub"; allowed=" sub_issue_id "
      n=${path#"repos/$slug/issues/"}; n=${n%/sub_issues} ;;
    "PATCH repos/$slug/issues/"*) shape="patch"; allowed=" body "; n=${path#"repos/$slug/issues/"} ;;
    *) lc__refuse shape ;;
  esac
  if [ "$shape" = sub ] || [ "$shape" = patch ]; then
    case "$n" in ''|*[!0-9]*) lc__refuse issue-number ;; esac
    # The target is bound to the epic this run found or created: a PATCH or a link under any other issue is not a form we send.
    [ -n "${EPIC_NUM:-}" ] && [ "$n" = "$EPIC_NUM" ] || lc__refuse epic-bind
  fi
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|-F)
        [ $# -ge 2 ] || lc__refuse flag-value
        flag=$1; kv=$2
        case "$kv" in *=*) ;; *) lc__refuse field-form ;; esac
        key=${kv%%=*}; val=${kv#*=}
        # Whole-word match: a key holding a space ("title body") would otherwise be a substring of the allowed list.
        case "$key" in ''|*[[:space:]]*) lc__refuse field-key ;; esac
        case "$allowed" in *" $key "*) ;; *) lc__refuse field-key ;; esac
        # Every label this tool names, on a label create or on an issue, is one of its own lc: labels.
        case "$key" in name|'labels[]') case "$val" in lc:?*) ;; *) lc__refuse label-name ;; esac ;; esac
        if [ "$flag" = -F ]; then
          case "$key" in
            body) case "$val" in @*) lc__file_ok "${val#@}" || lc__refuse file-operand ;; *) lc__refuse typed-field ;; esac ;;
            sub_issue_id) case "$val" in ''|*[!0-9]*) lc__refuse sub-issue-id ;; esac ;;
            *) lc__refuse typed-field ;;
          esac
        else
          case "$key" in body|sub_issue_id) lc__refuse raw-field ;; esac
        fi
        shift 2 ;;
      --jq) [ $# -ge 2 ] || lc__refuse flag-value; shift 2 ;;
      *) lc__refuse flag ;;
    esac
  done
}

lc__pause() {
  local p
  [ "${LC_WRITES_DONE:-0}" -gt 0 ] || return 0
  p=$(lc_seam LAUNCH_CHECK_PAUSE 1)
  case "$p" in ''|*[!0-9]*) p=1 ;; esac
  [ "$p" = 0 ] || sleep "$p"
}

# lc_gh_write api -X <POST|PATCH> <path> [-f k=v | -F k=v | --jq expr]...: a tracker write. The only caller-visible way to write.
lc_gh_write() {
  if lc_is_headless; then lc_abort headless-write-refused 2 "detail=headless"; fi
  lc__write_shape "$@"
  [ "${LC_DRY:-0}" = 1 ] && return 0
  lc__pause
  local rc=0
  # counted before the call: a write that was in flight when a signal arrived may have reached the tracker
  LC_WRITES_DONE=$((LC_WRITES_DONE + 1))
  lc__gh_exec "$@" || rc=$?
  return "$rc"
}

# ---------------------------------------------------------------- preflight
# lc_issues_preflight: sets ISSUES_REASON (empty when ready), ISSUES_RESOLVED, ISSUES_VIS, ISSUES_FORK, and ISSUES_REPO on success.
lc_issues_preflight() {
  local line v a i p
  ISSUES_REASON=""; ISSUES_RESOLVED=""; ISSUES_VIS=UNKNOWN; ISSUES_FORK=false
  command -v gh >/dev/null 2>&1 || { ISSUES_REASON=gh-missing; return 1; }
  lc_gh_read auth status || { ISSUES_REASON=gh-unauthenticated; return 1; }
  lc_gh_read repo view --json nameWithOwner,isFork --jq '[.nameWithOwner, .isFork] | @tsv' || { ISSUES_REASON=repo-unresolved; return 1; }
  line=$(awk 'NR == 1 { print; exit }' "$WORK/gh.out")
  ISSUES_RESOLVED=$(cut -f1 <<<"$line")
  ISSUES_FORK=$(cut -f2 <<<"$line")
  lc__re "$ISSUES_RE_SLUG" "$ISSUES_RESOLVED" || { ISSUES_REASON=repo-unresolved; return 1; }
  case "$ISSUES_FORK" in true|false) ;; *) ISSUES_FORK=false ;; esac
  lc_gh_read api "repos/$ISSUES_RESOLVED" --jq '[.visibility, (.archived // false), (.has_issues // false), (.permissions.push // false)] | @tsv' \
    || { ISSUES_REASON=repo-unresolved; return 1; }
  line=$(awk 'NR == 1 { print; exit }' "$WORK/gh.out")
  v=$(cut -f1 <<<"$line"); a=$(cut -f2 <<<"$line"); i=$(cut -f3 <<<"$line"); p=$(cut -f4 <<<"$line")
  case "$v" in public) ISSUES_VIS=PUBLIC ;; private) ISSUES_VIS=PRIVATE ;; internal) ISSUES_VIS=INTERNAL ;; *) ISSUES_VIS=UNKNOWN ;; esac
  [ "$a" != true ] || { ISSUES_REASON=repo-archived; return 1; }
  [ "$i" = true ] || { ISSUES_REASON=issues-disabled; return 1; }
  [ "$p" = true ] || { ISSUES_REASON=no-write-permission; return 1; }
  ISSUES_REPO=$ISSUES_RESOLVED
  return 0
}

# The resolved repository must be the one `origin` names, and origin must be on the target host. `--repo <slug>` does not choose the
# target: it acknowledges the repository gh resolved (it must equal that slug) when that differs from origin, e.g. a fork that
# resolves to its upstream. The only ways to change the target are `gh repo set-default` and the origin remote.
lc_issues_origin_check() {
  local url slug ohost
  url=$(git -C "$TARGET" remote get-url origin 2>/dev/null) || url=""
  case "$url" in
    *://*) ohost=$(printf '%s\n' "$url" | sed -e 's#^[^:/]*://##' -e 's#/.*$##' -e 's#^.*@##' -e 's#:.*$##') ;;
    *@*:*) ohost=$(printf '%s\n' "$url" | sed -e 's#^.*@##' -e 's#:.*$##') ;;
    *) ohost="" ;;
  esac
  if [ -n "$ohost" ] && [ "$(lc__lower "$ohost")" != "$(lc__lower "${ISSUES_HOST:-github.com}")" ]; then
    lc__fmt origin_host_fix; lc_abort repo-unresolved 2 "detail=host-differs resolved=$ISSUES_RESOLVED"
  fi
  if [ -n "${ISSUES_REPO_ARG:-}" ]; then
    lc__same_slug "$ISSUES_REPO_ARG" "$ISSUES_RESOLVED" || lc_abort repo-unresolved 2 "detail=repo-flag-differs resolved=$ISSUES_RESOLVED"
    return 0
  fi
  slug=$(printf '%s\n' "$url" | sed -e 's#^.*[:/]\([^/:]*/[^/:]*\)$#\1#' -e 's#\.git$##')
  lc__same_slug "$slug" "$ISSUES_RESOLVED" || lc_abort repo-unresolved 2 "detail=origin-differs resolved=$ISSUES_RESOLVED"
}

# ---------------------------------------------------------------- Guard 3: the live identity
# lc_issues_live: one paginated listing of every issue that carries the scope label, kept as validated rows in $WORK/live.tsv:
# number, database id, state, epic-label flag, author, key (a gap id, @epic, or - for no usable marker). A marker counts only as a
# whole line (a customer note that quotes one mid-text is not a marker; a trailing CR is tolerated). A failed or malformed listing
# is never read as "none found".
lc_issues_live() {
  : > "$WORK/live.tsv"
  if ! lc_gh_read api "repos/$ISSUES_REPO/issues" -f labels=lc:launch-check -f state=all -f per_page=100 --paginate \
    --jq '.[] | select(.pull_request == null) | . as $i | ((.body // "") | ((scan("(?m)^<!-- launch-check:(gap=[A-Z]+-[A-Za-z0-9-]+|epic) -->\r?$") | .[0]) // "-")) as $m | [$i.number, $i.id, $i.state, (("\t" + ([$i.labels[].name] | @tsv) + "\t") | test("\tlc:epic\t")), ($i.user.login // "-"), $m] | @tsv'; then
    lc__incomplete lookup "$LC_GH_KIND"
  fi
  RE_MARK='^(gap=[A-Z]+-[A-Za-z0-9-]+|epic|-)$' RE_LOGIN='^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$' \
  awk -F'\t' -v OFS='\t' '
    NF != 6 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || ($3 != "open" && $3 != "closed") || ($4 != "true" && $4 != "false") || $6 !~ ENVIRON["RE_MARK"] { bad = 1; exit }
    { key = ($6 == "epic") ? "@epic" : ($6 == "-") ? "-" : substr($6, 5)
      login = $5; if (login !~ ENVIRON["RE_LOGIN"]) login = "-"
      print $1, $2, $3, $4, login, key }
    END { if (bad) exit 1 }' "$WORK/gh.out" > "$WORK/live.new" || lc__incomplete lookup malformed
  mv "$WORK/live.new" "$WORK/live.tsv"
}

# lc_live_tables: derive live.items (id, number, database id, state; lowest number wins), live.epics (number, database id, state,
# author) and the ignored issues from live.tsv. An issue is ignored when it carries several distinct markers or none: live.ignored
# holds the count, live.ign.nums their numbers, live.ign.epic the numbers of the several-marker ones that are epic candidates (the
# epic label or an epic marker) and live.ign.keys "number<TAB>gap id" for every gap marker of a several-marker issue.
lc_live_tables() {
  : > "$WORK/live.items"; : > "$WORK/live.epics"; : > "$WORK/live.ignored"; : > "$WORK/live.ign.nums"; : > "$WORK/live.ign.epic"; : > "$WORK/live.ign.keys"
  F_ITEMS="$WORK/live.items" F_EPICS="$WORK/live.epics" F_IGN="$WORK/live.ignored" F_NUMS="$WORK/live.ign.nums" F_IGNE="$WORK/live.ign.epic" F_IGNK="$WORK/live.ign.keys" \
  awk -F'\t' -v OFS='\t' '
    { n = $1
      if (!(n in first)) { first[n] = $6; ord[++cnt] = n; row[n] = $0; nk[n] = 1; ks[n, 1] = $6; ep[n] = ($4 == "true") }
      else { dup = 0; for (j = 1; j <= nk[n]; j++) if (ks[n, j] == $6) dup = 1
             if (!dup) { ks[n, ++nk[n]] = $6; multi[n] = 1 } } }
    END {
      for (i = 1; i <= cnt; i++) {
        n = ord[i]
        if (n in multi) {
          ign++; print n > (ENVIRON["F_NUMS"]); isep = ep[n]
          for (j = 1; j <= nk[n]; j++) { if (ks[n, j] == "@epic") isep = 1; else print n, ks[n, j] > (ENVIRON["F_IGNK"]) }
          if (isep) print n > (ENVIRON["F_IGNE"])
          continue
        }
        split(row[n], f, "\t")
        if (f[6] == "-") { ign++; print n > (ENVIRON["F_NUMS"]); continue }
        if (f[6] == "@epic") { if (f[4] == "true") print f[1], f[2], f[3], f[5] > (ENVIRON["F_EPICS"]); continue }
        k = f[6]
        if (!(k in bn) || n + 0 < bn[k] + 0) { bn[k] = n; bd[k] = f[2]; bs[k] = f[3] }
      }
      for (k in bn) print k, bn[k], bd[k], bs[k] > (ENVIRON["F_ITEMS"])
      print ign + 0 > (ENVIRON["F_IGN"])
    }' "$WORK/live.tsv" || lc__incomplete lookup malformed
  [ -s "$WORK/live.ignored" ] || printf '0\n' > "$WORK/live.ignored"
  sort -o "$WORK/live.items" "$WORK/live.items"
  EPIC_CANDIDATES=$(grep -c . "$WORK/live.epics")
}

# lc__live_gate: stop before any write when the listing holds something the run cannot read safely. A several-marker issue that is
# an epic candidate is an ambiguous epic; one that carries a marker of a gap in this plan could hide that gap, so the run stops
# with one closed reason instead of filing it a second time.
lc__live_gate() {
  [ ! -s "$WORK/live.ign.epic" ] || lc_abort epic-ambiguous 2 "detail=ignored-epic"
  if [ -s "$WORK/live.ign.keys" ]; then
    F_ROWS="$WORK/plan.rows.tsv" awk -F'\t' '
      FILENAME == ENVIRON["F_ROWS"] { id[$1] = 1; next }
      ($2 in id) { hit = 1 }
      END { exit !hit }' "$WORK/plan.rows.tsv" "$WORK/live.ign.keys" && lc_abort issue-ambiguous 2 "detail=several-markers"
  fi
  if [ "$EPIC_CANDIDATES" -gt 1 ]; then lc_abort epic-ambiguous 2 "detail=several-epics"; fi
  return 0
}

# ---------------------------------------------------------------- Guard 2: bodies are built from the catalog, never typed
# lc_issue_body <id> <severity> <domain> <class> <title> <evidence> <closing> <remedy>: one body on stdout. Values reach the
# template through ENVIRON and index()/substr() only, so a backslash or an ampersand in a value (the domain label "Tests & CI/CD")
# is carried as it is. Secret-class findings carry only the fixed count phrase.
lc_issue_body() {
  local ev=$6 cmd=""
  case " $LC_COUNT_ONLY_IDS " in
    *" $1 "*) grep -qE '^[0-9]+ (finding\(s\)|file\(s\)); (locations|names) withheld, run scan --show-secrets locally to see them$' <<<"$ev" || ev=$(lc_phrase sec_withheld) ;;
  esac
  case "$ev" in *'`'*) ev="(evidence withheld)" ;; esac
  [ "$7" = "-" ] || cmd=" Command: \`$7\`"
  V_BANNER=$(cat "$SKILL_DIR/references/banner.txt") V_ID=$1 V_SEVERITY=$2 V_DOMAIN=$(lc_domain_label "$3") V_TITLE=$5 V_EVIDENCE=$ev V_REMEDY=$8 V_COMMAND=$cmd awk '
    { out = ""; s = $0
      while ((i = index(s, "{{")) > 0) {
        rest = substr(s, i + 2); j = index(rest, "}}")
        if (j == 0) break
        out = out substr(s, 1, i - 1) ENVIRON["V_" substr(rest, 1, j - 1)]
        s = substr(rest, j + 2)
      }
      print out s }' "$SKILL_DIR/references/issue-body.template"
}

lc_epic_title() { lc_phrase epic_heading; }
lc_epic_initial() {
  printf '<!-- launch-check:epic -->\n\n%s\n\n# %s\n\n%s\n\n<!-- launch-check:begin -->\n<!-- launch-check:end -->\n\n%s\n' \
    "$(cat "$SKILL_DIR/references/banner.txt")" "$(lc_phrase epic_heading)" "$(lc_phrase epic_intro)" "$(lc_phrase epic_outro)"
}

# lc__labels_for <rows file>: the lc: labels a create of these rows ensures (id, severity, domain, class, action, ...), one line, in the
# order the create ensures them. The preview prints it and the create uses it, so the two cannot differ.
lc__labels_for() {
  awk -F'\t' 'BEGIN { s = "lc:launch-check lc:epic"; seen[s] = 1; seen["lc:launch-check"] = 1; seen["lc:epic"] = 1 }
    $5 == "create" { for (i = 1; i <= 2; i++) { l = (i == 1) ? "lc:severity-" $2 : "lc:domain-" $3; if (!(l in seen)) { seen[l] = 1; s = s " " l } } }
    END { print s }' "$1"
}

lc__label_color() {
  case "$1" in
    lc:launch-check) printf '5319e7' ;; lc:epic) printf '3e4b9e' ;;
    lc:severity-critical) printf 'b60205' ;; lc:severity-high) printf 'd93f0b' ;;
    lc:severity-medium) printf 'fbca04' ;; lc:severity-low) printf '0e8a16' ;;
    *) printf '1d76db' ;;
  esac
}
lc__label_desc() {
  case "$1" in
    lc:launch-check) lc_phrase label_desc_scope ;; lc:epic) lc_phrase label_desc_epic ;;
    lc:severity-*) lc_phrase label_desc_severity ;; *) lc_phrase label_desc_domain ;;
  esac
}

# lc_report_hash: the report's state block, hashed. A finding accepted or reopened after the preview changes it.
lc_report_hash() {
  tr -d '\r' < "$TARGET/$REPORT_REL" | awk '/^```launch-check-state$/ {f=1; next} /^```$/ && f {f=0} f' > "$WORK/state.blk"
  git hash-object --stdin < "$WORK/state.blk"
}

# lc_issues_stale_check <plan report hash or empty> <plan catalog hash or empty>
lc_issues_stale_check() {
  local rep_cat cur_cat cur_rep
  cur_cat=$(git hash-object --stdin < "$CAT")
  rep_cat=$(awk -F= '/^catalog_hash=/ {print $2; exit}' "$TARGET/$REPORT_REL" | tr -d '\r')
  [ "$rep_cat" = "$cur_cat" ] || lc__stale catalog
  F_PREV="$WORK/prev.tsv" awk -F'\t' '
    FILENAME == ENVIRON["F_PREV"] { if ($2 == "open") o[$1] = 1; next }
    !($1 in o) { bad = 1 }
    END { exit bad }' "$WORK/prev.tsv" "$WORK/open.ids" || lc__stale not-open-in-report
  if [ -n "${1:-}" ]; then
    cur_rep=$(lc_report_hash)
    [ "$cur_rep" = "$1" ] || lc__stale report-changed
    [ "$cur_cat" = "${2:-}" ] || lc__stale catalog-changed
  fi
}

# ---------------------------------------------------------------- the saved plan (trust chain)
# lc_plan_load <dir> <strict 0|1>: lstat the directory, copy the recognised files into $WORK/plan, validate the copy against closed
# vocabularies. Sets ISSUES_ORIG_PLAN_DIR, ISSUES_PLAN_DIR (the copy), PLAN_REPO, PLAN_HOST, PLAN_CATHASH, PLAN_REPHASH,
# PLAN_CREATE_N and writes plan.rows.tsv, plan.create.ids in $WORK. Strict mode also checks owner and mode (create); the parse-only
# check skips them so the committed sample is accepted under any umask.
lc_plan_load() {
  local src=$1 strict=$2 real dst="$WORK/plan" bad uid f mode id n sz m vrc=0
  [ -d "$src" ] || lc__pbad not-a-directory
  [ ! -L "$src" ] || lc__pbad plan-dir-symlink
  real=$(cd "$src" 2>/dev/null && pwd -P) || lc__pbad unreadable
  if [ "$strict" = 1 ]; then
    uid=$(id -u)
    for f in "$real" "$real/issues"; do
      [ -d "$f" ] || continue
      [ -n "$(find "$f" -maxdepth 0 -user "$uid" 2>/dev/null)" ] || lc__pbad owner
      mode=$(ls -ld "$f" | cut -c1-10)
      case "$mode" in ?????-??-*) ;; *) lc__pbad mode ;; esac
    done
  fi
  [ -f "$real/plan.tsv" ] && [ ! -L "$real/plan.tsv" ] || lc__pbad plan-file
  [ -f "$real/epic.md" ] && [ ! -L "$real/epic.md" ] || lc__pbad epic-file
  [ -d "$real/issues" ] && [ ! -L "$real/issues" ] || lc__pbad issues-dir
  [ -z "$(find "$real" -type l 2>/dev/null | head -n 1)" ] || lc__pbad symlink
  for f in "$real/plan.tsv" "$real/epic.md"; do
    sz=$(wc -c < "$f" | tr -d ' ')
    [ "$sz" -le "$ISSUES_MAX_BYTES" ] || lc__pbad size
  done
  rm -rf "${dst:?}"; mkdir -p "$dst/issues" || lc__pbad copy
  cp -P "$real/plan.tsv" "$dst/plan.tsv" && cp -P "$real/epic.md" "$dst/epic.md" || lc__pbad copy
  bad=$(CAPN="$ISSUES_CAP" RE_SLUG="$ISSUES_RE_SLUG" RE_ID="$ISSUES_RE_ID" RE_TITLE="$ISSUES_RE_TITLE" awk -F'\t' '
    function fail(t) { print t; failed = 1; exit 1 }
    BEGIN { split("repo host visibility catalog_hash report_hash created", K, " ") }
    NR <= 6 {
      k = K[NR]; if (index($0, k "=") != 1) fail("header")
      v = substr($0, length(k) + 2)
      if (k == "repo" && v !~ ENVIRON["RE_SLUG"]) fail("repo")
      if (k == "host" && (v !~ /^[a-z0-9][a-z0-9.-]*$/ || length(v) > 253)) fail("host")
      if (k == "visibility" && v !~ /^(PUBLIC|PRIVATE|INTERNAL|UNKNOWN)$/) fail("visibility")
      if ((k == "catalog_hash" || k == "report_hash") && (v !~ /^[0-9a-f]+$/ || length(v) < 7 || length(v) > 64)) fail("hash")
      if (k == "created" && v !~ /^[0-9TZ:-]+$/) fail("created")
      next }
    NR == 7 { if ($0 != "id\tseverity\tdomain\tclass\taction\ttitle") fail("columns"); next }
    { if (NF != 6) fail("row")
      if ($1 !~ ENVIRON["RE_ID"] || length($1) > 64) fail("id")
      if ($1 in seen) fail("duplicate-id")
      seen[$1] = 1
      if ($2 !~ /^(critical|high|medium|low)$/) fail("severity")
      if ($3 !~ /^(security|tests-ci|tech-debt|reliability-ops)$/) fail("domain")
      if ($4 !~ /^(readiness|baseline)$/) fail("class")
      if ($5 !~ /^(create|exists|closed|accepted|excluded|capped)$/) fail("action")
      if ($6 !~ ENVIRON["RE_TITLE"] || length($6) > 120 || $6 ~ /GH-[0-9]/) fail("title")
      if ($5 == "create") n++ }
    END { if (failed) exit 1; if (NR < 7) fail("columns"); if (n > ENVIRON["CAPN"] + 0) fail("cap") }' "$dst/plan.tsv") || vrc=$?
  # A validator that died (no awk, a crash) said nothing: that is not "valid".
  if [ "$vrc" -ne 0 ]; then lc__pbad "$(printf '%s\n' "${bad:-validator}" | awk 'NR == 1')"; fi
  [ -z "$bad" ] || lc__pbad "$bad"
  PLAN_REPO=$(sed -n 's/^repo=//p' "$dst/plan.tsv" | head -n 1)
  PLAN_HOST=$(sed -n 's/^host=//p' "$dst/plan.tsv" | head -n 1)
  PLAN_CATHASH=$(sed -n 's/^catalog_hash=//p' "$dst/plan.tsv" | head -n 1)
  PLAN_REPHASH=$(sed -n 's/^report_hash=//p' "$dst/plan.tsv" | head -n 1)
  awk 'NR > 7' "$dst/plan.tsv" > "$WORK/plan.rows.tsv" || lc__pbad validator
  awk -F'\t' '$5 == "create" { print $1 }' "$WORK/plan.rows.tsv" > "$WORK/plan.create.ids" || lc__pbad validator
  PLAN_CREATE_N=$(grep -c . "$WORK/plan.create.ids")
  n=$(find "$real/issues" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  [ "$n" = "$PLAN_CREATE_N" ] || lc__pbad body-files
  while IFS= read -r id; do
    f="$real/issues/$id.md"
    [ -f "$f" ] && [ ! -L "$f" ] || lc__pbad body-file
    sz=$(wc -c < "$f" | tr -d ' ')
    [ "$sz" -le "$ISSUES_MAX_BYTES" ] || lc__pbad size
    cp -P "$f" "$dst/issues/$id.md" || lc__pbad copy
    m=$(grep -o '<!-- launch-check:[^>]*-->' "$dst/issues/$id.md")
    [ "$m" = "<!-- launch-check:gap=$id -->" ] || lc__pbad marker
  done < "$WORK/plan.create.ids"
  m=$(grep -o '<!-- launch-check:[^>]*-->' "$dst/epic.md")
  [ "$m" = "$(printf '<!-- launch-check:epic -->\n<!-- launch-check:begin -->\n<!-- launch-check:end -->')" ] || lc__pbad epic-marker
  [ -z "$(find "$dst" -type l 2>/dev/null | head -n 1)" ] || lc__pbad symlink
  ISSUES_ORIG_PLAN_DIR=$real
  ISSUES_PLAN_DIR=$dst
}

lc_issues_check_plan() {
  lc_plan_load "$ISSUES_PLAN_ARG" 0
  printf 'SOLEUR_LAUNCH_CHECK_PLAN_OK repo=%s host=%s create=%s items=%s\n' "$PLAN_REPO" "$PLAN_HOST" "$PLAN_CREATE_N" "$(grep -c . "$WORK/plan.rows.tsv")"
}

# ---------------------------------------------------------------- shared output helpers
lc__create_cmd() { # <plan-dir> <create-count>
  local c
  c=$(printf 'bash %q issues --create --target %q --facts %q' "$SKILL_DIR/scripts/launch-check.sh" "$TARGET" "$ISSUES_FACTS_ARG")
  [ -z "$ISSUES_JUDGED_ARG" ] || c="$c $(printf -- '--judged %q' "$ISSUES_JUDGED_ARG")"
  c="$c $(printf -- '--plan %q --confirm-repo %q --confirm-count %q' "$1" "$ISSUES_REPO" "$2")"
  [ -z "${ISSUES_REPO_ARG:-}" ] || c="$c $(printf -- '--repo %q' "$ISSUES_REPO_ARG")"
  [ "${ISSUES_HOST:-github.com}" = github.com ] || c="$c $(printf -- '--host %q' "$ISSUES_HOST")"
  lc__say "$c"
}
# lc__public_note: the printed command never carries --confirm-public (a command copied and run whole must not publish a list of
# unfixed gaps on its own); a separate line says when the owner's own yes may append it.
lc__public_note() { [ "${ISSUES_VIS:-PRIVATE}" = PRIVATE ] || lc__fmt confirm_public_append; }

# ---------------------------------------------------------------- preview
lc_issues_partition() {
  F_ACC="$WORK/accepted.ids" F_LIVE="$WORK/live.items" X_DOM="$ISSUES_EXCL_DOM" X_CLS="$ISSUES_EXCL_CLS" CAPN="$ISSUES_CAP" \
  awk -F'\t' -v OFS='\t' '
    FILENAME == ENVIRON["F_ACC"] { acc[$1] = 1; next }
    FILENAME == ENVIRON["F_LIVE"] { lst[$1] = $4; lnum[$1] = $2; next }
    { id = $2; dom = $3; cls = $4
      if (id in acc) a = "accepted"
      else if (index(ENVIRON["X_DOM"], "," dom ",") > 0 || index(ENVIRON["X_CLS"], "," cls ",") > 0) a = "excluded"
      else if (id in lst) a = (lst[id] == "closed") ? "closed" : "exists"
      else if (++made <= ENVIRON["CAPN"] + 0) a = "create"
      else a = "capped"
      print id, $5, dom, cls, a, $6, $7, $8, $9, ((id in lnum) ? lnum[id] : "-") }' \
    "$WORK/accepted.ids" "$WORK/live.items" "$WORK/gaps.tsv" > "$WORK/part.tsv" || lc_abort plan-invalid 2 "detail=validator"
}

lc_issues_preview() {
  local pb="$WORK/pb" plandir="" parent n_create n_exists n_closed n_accepted n_excluded n_capped
  local id sev dom cls act title ev clos rem num c_crit c_high c_med c_low created
  [ -f "$TARGET/$REPORT_REL" ] || { lc__fmt report_missing_fix; lc_abort report-missing 2 "detail=no-report"; }
  if ! lc_issues_preflight; then
    printf 'SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=%s\n' "$ISSUES_REASON"
    lc__fmt "report_only_$ISSUES_REASON"
    exit 0
  fi
  lc_issues_origin_check
  lc_prepare_inputs
  lc_compute_gaps
  lc_issues_stale_check "" ""
  lc_issues_live
  lc_live_tables
  lc_issues_partition
  bad=$(RE_ID="$ISSUES_RE_ID" RE_TITLE="$ISSUES_RE_TITLE" awk -F'\t' '$1 !~ ENVIRON["RE_ID"] || $6 !~ ENVIRON["RE_TITLE"] || length($6) > 120 || $6 ~ /GH-[0-9]/ { print $1; exit }' "$WORK/part.tsv") \
    || lc_abort plan-invalid 2 "detail=validator"
  [ -z "$bad" ] || lc_abort plan-invalid 2 "detail=catalog-title"
  n_create=$(awk -F'\t' '$5 == "create"' "$WORK/part.tsv" | grep -c .)
  n_exists=$(awk -F'\t' '$5 == "exists"' "$WORK/part.tsv" | grep -c .)
  n_closed=$(awk -F'\t' '$5 == "closed"' "$WORK/part.tsv" | grep -c .)
  n_accepted=$(awk -F'\t' '$5 == "accepted"' "$WORK/part.tsv" | grep -c .)
  n_excluded=$(awk -F'\t' '$5 == "excluded"' "$WORK/part.tsv" | grep -c .)
  n_capped=$(awk -F'\t' '$5 == "capped"' "$WORK/part.tsv" | grep -c .)

  # Build the plan in $WORK, scan the exact bytes, and only then put it where the customer can see it.
  mkdir -p "$pb/issues" && chmod 700 "$pb" "$pb/issues"
  created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    printf 'repo=%s\nhost=%s\nvisibility=%s\ncatalog_hash=%s\nreport_hash=%s\ncreated=%s\n' "$ISSUES_REPO" "$ISSUES_HOST" "$ISSUES_VIS" \
      "$(git hash-object --stdin < "$CAT")" "$(lc_report_hash)" "$created"
    printf 'id\tseverity\tdomain\tclass\taction\ttitle\n'
    awk -F'\t' -v OFS='\t' '{ print $1, $2, $3, $4, $5, $6 }' "$WORK/part.tsv"
  } > "$pb/plan.tsv"
  : > "$WORK/blob"
  while IFS=$'\t' read -r id sev dom cls act title ev clos rem num; do
    [ "$act" = create ] || continue
    lc_issue_body "$id" "$sev" "$dom" "$cls" "$title" "$ev" "$clos" "$rem" > "$pb/issues/$id.md"
    { printf '%s\n' "$title"; cat "$pb/issues/$id.md"; } >> "$WORK/blob"
  done < "$WORK/part.tsv"
  lc_epic_initial > "$pb/epic.md"
  { lc_epic_title; cat "$pb/epic.md"; } >> "$WORK/blob"
  for id in lc:launch-check lc:epic; do printf '%s\n%s\n' "$id" "$(lc__label_desc "$id")" >> "$WORK/blob"; done
  lc_emit_checked "$WORK/blob" "" 1

  if [ "${LC_DRY:-0}" = 1 ]; then plandir="-"
  else
    parent=${ISSUES_PLAN_OUT:-${TMPDIR:-/tmp}}
    ( umask 077; mkdir -p "$parent" ) || lc_abort write-failed 2 "detail=plan-out"
    plandir=$(mktemp -d "$parent/lc-issues-plan.XXXXXX") || lc_abort write-failed 2 "detail=plan-dir"
    chmod 700 "$plandir"
    cp -R "$pb/." "$plandir/" || lc_abort write-failed 2 "detail=plan-copy"
    plandir=$(cd "$plandir" && pwd -P)
  fi

  lc__fmt issues_repo_line "$ISSUES_REPO" "$ISSUES_HOST" "$ISSUES_VIS" "$ISSUES_FORK"
  [ "$ISSUES_FORK" != true ] || lc__fmt issues_fork_warn
  [ "$ISSUES_VIS" = PRIVATE ] || lc__fmt issues_public_warn
  if [ "$EPIC_CANDIDATES" -gt 1 ]; then lc__fmt issues_epic_ambiguous_warn
  elif [ "$EPIC_CANDIDATES" = 1 ] && [ "$(cut -f3 "$WORK/live.epics")" = closed ]; then lc__fmt issues_epic_closed_warn
  elif [ "$EPIC_CANDIDATES" = 1 ] && lc_gh_read api user --jq '.login' \
    && [ "$(cut -f4 "$WORK/live.epics")" != "$(awk 'NR == 1 { print; exit }' "$WORK/gh.out")" ]; then lc__fmt issues_epic_author_warn; fi
  n=$(cat "$WORK/live.ignored")
  [ "$n" = 0 ] || lc__fmt issues_ignored "$n" "$(head -n 10 "$WORK/live.ign.nums" | sed 's/^/#/' | paste -s -d, -)"
  [ ! -s "$WORK/live.ign.epic" ] || lc__fmt issues_epic_ambiguous_warn
  if [ -s "$WORK/live.ign.keys" ] && F_PART="$WORK/part.tsv" awk -F'\t' 'FILENAME == ENVIRON["F_PART"] { id[$1] = 1; next } ($2 in id) { hit = 1 } END { exit !hit }' "$WORK/part.tsv" "$WORK/live.ign.keys"; then
    lc__fmt issues_ignored_conflict_warn
  fi
  lc__fmt issues_counts "$n_create" "$n_exists" "$n_closed" "$n_accepted" "$n_excluded" "$n_capped"
  c_crit=$(awk -F'\t' '$5 == "create" && $2 == "critical"' "$WORK/part.tsv" | grep -c .)
  c_high=$(awk -F'\t' '$5 == "create" && $2 == "high"' "$WORK/part.tsv" | grep -c .)
  c_med=$(awk -F'\t' '$5 == "create" && $2 == "medium"' "$WORK/part.tsv" | grep -c .)
  c_low=$(awk -F'\t' '$5 == "create" && $2 == "low"' "$WORK/part.tsv" | grep -c .)
  lc__fmt issues_by_severity "$c_crit" "$c_high" "$c_med" "$c_low"
  lc__fmt issues_cap_rule "$ISSUES_CAP" "$n_capped"
  # Informational lines: a filed issue whose gap is resolved, and one the customer closed while the gap is still open.
  F_CUR="$WORK/cur.ids" F_LIVE="$WORK/live.items" awk -F'\t' '
    FILENAME == ENVIRON["F_CUR"] { cur[$1] = 1; next }
    $4 == "open" && !($1 in cur) { print $2 }' "$WORK/cur.ids" "$WORK/live.items" > "$WORK/resolved.nums"
  while IFS= read -r num; do [ -n "$num" ] || continue; lc__fmt issues_resolved "#$num"; done < "$WORK/resolved.nums"
  while IFS=$'\t' read -r id sev dom cls act title ev clos rem num; do
    [ "$act" = closed ] || continue
    lc__fmt issues_closed_open "#$num"
  done < "$WORK/part.tsv"
  if [ "$n_create" -gt 0 ]; then
    lc__fmt issues_table_hdr
    while IFS=$'\t' read -r id sev dom cls act title ev clos rem num; do
      [ "$act" = create ] || continue
      lc__say "$id | $sev | $title | $ev"
    done < "$WORK/part.tsv"
    lc__fmt issues_labels_line "$(lc__labels_for "$WORK/part.tsv")"
    if [ "${LC_DRY:-0}" = 1 ]; then lc__fmt dry_run_note
    else
      lc__fmt issues_create_hdr
      lc__create_cmd "$plandir" "$n_create"
      lc__public_note
      lc__fmt issues_guard_note
    fi
  else
    lc__fmt issues_none
  fi
  printf 'SOLEUR_LAUNCH_CHECK_ISSUES_PLAN repo=%s host=%s visibility=%s fork=%s create=%s exists=%s closed=%s accepted=%s excluded=%s capped=%s plan=%s\n' \
    "$ISSUES_REPO" "$ISSUES_HOST" "$ISSUES_VIS" "$ISSUES_FORK" "$n_create" "$n_exists" "$n_closed" "$n_accepted" "$n_excluded" "$n_capped" "$plandir"
}

# ---------------------------------------------------------------- Guard 4: epic edits confined to the marked section
# lc_epic_splice <old-body-file> <new-section-file>: the new body on stdout, or rc 1 (nothing printed) when the markers are not
# exactly one begin line followed by one end line. Only the lines between them change; every other byte is carried over (a CR
# before the newline is tolerated when finding a marker, and kept). The new section takes the line ending of the begin marker.
lc_epic_splice() {
  local old=$1 sec=$2 line bare state=0 nb=0 ne=0 crlf=0 out="$WORK/out/splice.tmp" total last
  [ -s "$old" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    bare=${line%$'\r'}
    if [ "$bare" = "<!-- launch-check:begin -->" ]; then nb=$((nb + 1)); [ "$ne" = 0 ] || return 1
    elif [ "$bare" = "<!-- launch-check:end -->" ]; then ne=$((ne + 1)); [ "$nb" = 1 ] || return 1; fi
  done < "$old"
  [ "$nb" = 1 ] && [ "$ne" = 1 ] || return 1
  : > "$out"
  while IFS= read -r line || [ -n "$line" ]; do
    bare=${line%$'\r'}
    case "$state" in
      0) printf '%s\n' "$line" >> "$out"
         if [ "$bare" = "<!-- launch-check:begin -->" ]; then
           state=1; [ "$bare" = "$line" ] || crlf=1
           while IFS= read -r sline || [ -n "$sline" ]; do
             if [ "$crlf" = 1 ]; then printf '%s\r\n' "${sline%$'\r'}" >> "$out"; else printf '%s\n' "$sline" >> "$out"; fi
           done < "$sec"
         fi ;;
      1) if [ "$bare" = "<!-- launch-check:end -->" ]; then state=2; printf '%s\n' "$line" >> "$out"; fi ;;
      2) printf '%s\n' "$line" >> "$out" ;;
    esac
  done < "$old"
  last=$(tail -c 1 "$old" | od -An -tx1 | tr -d ' \n')
  total=$(wc -c < "$out" | tr -d ' ')
  if [ "$last" = 0a ]; then cat "$out"; else head -c $((total - 1)) "$out"; fi
}

# lc__strip_nl <in> <out>: drop the single trailing newline that the CLI's --jq adds to a string.
lc__strip_nl() {
  local sz
  sz=$(wc -c < "$1" | tr -d ' ')
  if [ "$sz" -gt 0 ] && [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" = 0a ]; then head -c $((sz - 1)) "$1" > "$2"; else cp "$1" "$2"; fi
}

# ---------------------------------------------------------------- create
lc__summary() { # <phase>
  local made=${CNT_CREATED:-0}
  printf 'SOLEUR_LAUNCH_CHECK_ISSUES created=%s linked=%s skipped=%s failed=%s fallback=%s epic=%s epic-section=%s plan=%s phase=%s\n' \
    "$made" "${CNT_LINKED:-0}" "${CNT_SKIPPED:-0}" "${FAILED_IDS:--}" "${ISSUES_FALLBACK:-none}" "${EPIC_REF:--}" "${EPIC_STATE:-skipped}" \
    "${ISSUES_ORIG_PLAN_DIR:--}" "$1"
}
# lc__incomplete <phase> <detail>: the run stopped with something unfinished. Print the summary, the rate-limit hint and the exact
# resume command, then abort. Nothing the CLI printed is echoed; detail is one of the closed tokens.
lc__resume_block() { # <phase> <detail>: the summary, the rate-limit hint and the exact resume command
  lc__summary "$1"
  [ "$2" != rate-limit ] || lc__fmt rate_limit_hint
  if [ -n "${ISSUES_ORIG_PLAN_DIR:-}" ]; then
    lc__fmt resume_hint
    lc__create_cmd "$ISSUES_ORIG_PLAN_DIR" "${PLAN_CREATE_N:-0}"
    lc__public_note
  fi
}
lc__incomplete() {
  lc__resume_block "$1" "$2"
  lc_abort issues-incomplete 2 "phase=$1 detail=$2 plan=${ISSUES_ORIG_PLAN_DIR:--}"
}
# A signal ends the run (the exit code is 128 plus the signal). When a write was already attempted, the summary and the exact
# resume command are printed first: a created issue is found again by its marker, so the resume is safe even when the counts lag.
lc__on_signal() { # <exit code>
  trap '' INT TERM HUP
  if [ "${LC_WRITES_DONE:-0}" -gt 0 ]; then
    lc__resume_block interrupted signal
    printf 'SOLEUR_LAUNCH_CHECK_ABORT reason=issues-incomplete phase=interrupted detail=signal plan=%s\n' "${ISSUES_ORIG_PLAN_DIR:--}"
  fi
  exit "$1"
}

# lc__record_failed: the record of what a run created (created.tsv) could not be written. The issue exists and is found again by its
# marker, so the summary and the resume command are printed before the run stops.
lc__record_failed() {
  lc__resume_block create record
  lc_abort write-failed 2 "detail=created-tsv"
}

# lc__parse_pair: the "number<TAB>database id" line a create printed, into NEW_NUM and NEW_ID.
lc__parse_pair() {
  local line
  line=$(awk 'NR == 1 { print; exit }' "$WORK/gh.out")
  lc__re $'^[0-9]+\t[0-9]+$' "$line" || return 1
  NEW_NUM=$(cut -f1 <<<"$line"); NEW_ID=$(cut -f2 <<<"$line")
}

# lc__link <issue database id> <number> <gap id>: link a child under the epic. Only a refusal of the feature itself (403, 404, 410 or
# 422) latches the run to the task list. A rate limit, a transport failure, a timeout or a 5xx says nothing about the feature, so it
# stops the run resumably (phase=link): the re-run links what is still unlinked, and a later run can still use the real links.
lc__link() {
  if lc_gh_write api -X POST "repos/$ISSUES_REPO/issues/$EPIC_NUM/sub_issues" -F "sub_issue_id=$1"; then
    CNT_LINKED=$((CNT_LINKED + 1))
    lc__say "linked: #$2 $3"
  else
    case "$LC_GH_KIND" in
      http-403|http-404|http-410|http-422) ISSUES_FALLBACK=task-list ;;
      *) lc__incomplete link "$LC_GH_KIND" ;;
    esac
  fi
}

# lc__epic_section <old-body-file> <outfile>: the text between the markers, from live state.
lc__epic_section() {
  local old=$1 out=$2 num id state n tick
  awk '
    { l = $0; sub(/\r$/, "", l) }
    l == "<!-- launch-check:begin -->" { s = 1; next }
    l == "<!-- launch-check:end -->" { s = 0; next }
    s && l ~ /^- \[[xX]\] #[0-9]+/ { t = l; sub(/^- \[[xX]\] #/, "", t); sub(/[^0-9].*$/, "", t); print t }' "$old" > "$WORK/ticked.nums"
  lc__fmt epic_counts "$CNT_CREATED" "$CNT_SKIPPED" "$([ "${FAILED_IDS:--}" = - ] && echo 0 || echo 1)" "$ISSUES_FALLBACK" > "$out"
  if [ "$ISSUES_FALLBACK" = task-list ]; then
    # Items that exist now: the live open ones named by the plan, plus what this run made.
    F_ROWS="$WORK/plan.rows.tsv" F_LIVE="$WORK/live.items" F_MADE="$WORK/made.tsv" awk -F'\t' -v OFS='\t' '
      FILENAME == ENVIRON["F_ROWS"] { if ($5 == "create" || $5 == "exists") want[$1] = 1; next }
      FILENAME == ENVIRON["F_LIVE"] { if ($4 == "open" && ($1 in want)) print $2, $1; next }
      { if ($1 in want) print $2, $1 }' "$WORK/plan.rows.tsv" "$WORK/live.items" "$WORK/made.tsv" | sort -t "$LC_TAB" -u -k1,1n > "$WORK/items.nums"
    while IFS=$'\t' read -r num id; do
      [ -n "$num" ] || continue
      tick=" "; grep -qxF "$num" "$WORK/ticked.nums" && tick="x"
      printf -- '- [%s] #%s %s\n' "$tick" "$num" "$id" >> "$out"
    done < "$WORK/items.nums"
  fi
  n=$(awk -F'\t' '$5 == "capped" { printf "%s%s", (c++ ? ", " : ""), $1 }' "$WORK/plan.rows.tsv")
  [ -z "$n" ] || lc__fmt epic_capped "$n" >> "$out"
}

# lc__epic_update: GET the epic body just before the splice, rebuild the marked section, scan it, PATCH only if the result differs.
lc__epic_update() {
  local sec="$WORK/out/section.md" live="$WORK/out/epic.live" raw="$WORK/out/epic.raw" new="$WORK/out/epic.new" rc=0
  [ "$EPIC_REF" != "-" ] || return 0
  lc_gh_read api "repos/$ISSUES_REPO/issues/$EPIC_NUM" --jq '.body // ""' || lc__incomplete epic "$LC_GH_KIND"
  cp "$WORK/gh.out" "$raw"; lc__strip_nl "$raw" "$live"
  lc__epic_section "$live" "$sec"
  if ! lc_epic_splice "$live" "$sec" > "$new"; then EPIC_STATE=markers-damaged; return 0; fi
  ( lc_emit_checked "$sec" "" 1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then EPIC_STATE=blocked; lc__summary complete; exit "$rc"; fi
  if cmp -s "$live" "$new"; then EPIC_STATE=unchanged; return 0; fi
  if lc_gh_write api -X PATCH "repos/$ISSUES_REPO/issues/$EPIC_NUM" -F "body=@$new"; then EPIC_STATE=updated
  else lc__incomplete epic "$LC_GH_KIND"; fi
}

lc_issues_create() {
  local id sev dom cls act title ev clos rem num want lbl made_epic=0 k
  CNT_CREATED=0; CNT_LINKED=0; CNT_SKIPPED=0; FAILED_IDS="-"; ISSUES_FALLBACK=none; EPIC_REF="-"; EPIC_NUM=""; EPIC_STATE=skipped
  mkdir -p "$WORK/out"; : > "$WORK/made.tsv"
  lc_plan_load "$ISSUES_PLAN_ARG" 1
  trap 'lc__on_signal 130' INT; trap 'lc__on_signal 143' TERM; trap 'lc__on_signal 129' HUP
  if [ "$ISSUES_CONFIRM_REPO" != "$PLAN_REPO" ] || [ "$ISSUES_CONFIRM_COUNT" != "$PLAN_CREATE_N" ]; then
    lc__fmt confirm_flags_fix; lc_abort usage 2 "detail=confirm-mismatch"
  fi
  [ "$PLAN_HOST" = "$ISSUES_HOST" ] || lc_abort usage 2 "detail=host-mismatch plan-host=$PLAN_HOST (pass --host $PLAN_HOST, or none for github.com)"
  lc_prepare_inputs
  lc_compute_gaps
  lc_issues_preflight || lc_abort issues-unavailable 2 "detail=$ISSUES_REASON"
  lc__same_slug "$ISSUES_RESOLVED" "$PLAN_REPO" || lc_abort plan-repo-mismatch 2 "detail=resolved-repo-differs resolved=$ISSUES_RESOLVED"
  lc_issues_origin_check
  # An exists or capped row carries no body file, so nothing else ties it to this catalog: it must name a catalog check that is a gap now.
  F_CAT="$WORK/cat.ids" F_GAPS="$WORK/gaps.tsv" awk -F'\t' '
    FILENAME == ENVIRON["F_CAT"] { c[$1] = 1; next }
    FILENAME == ENVIRON["F_GAPS"] { g[$2] = 1; next }
    ($5 == "capped" || $5 == "exists") && (!($1 in c) || !($1 in g)) { bad = 1 }
    END { exit bad }' "$WORK/cat.ids" "$WORK/gaps.tsv" "$WORK/plan.rows.tsv" || lc__pbad row-id
  if [ "$ISSUES_VIS" != PRIVATE ] && [ "$ISSUES_CONFIRM_PUBLIC" != 1 ]; then
    lc__fmt confirm_public_fix; lc_abort confirm-public-required 2 "visibility=$ISSUES_VIS"
  fi
  lc_issues_stale_check "$PLAN_REPHASH" "$PLAN_CATHASH"
  sort "$WORK/plan.create.ids" > "$WORK/plan.create.sorted"
  [ -z "$(comm -23 "$WORK/plan.create.sorted" "$WORK/open.ids")" ] || { lc__fmt report_stale_fix; lc_abort report-stale 2 "detail=row-not-open"; }

  # Regenerate every title and body from the catalog, facts and ids, and byte-compare with the plan copy.
  mkdir -p "$WORK/regen/issues"
  : > "$WORK/blob"
  while IFS=$'\t' read -r _ id dom cls sev title ev clos rem; do
    grep -qxF "$id" "$WORK/plan.create.ids" || continue
    [ "$(awk -F'\t' -v i="$id" '$1 == i' "$WORK/plan.rows.tsv")" = "$(printf '%s\t%s\t%s\t%s\tcreate\t%s' "$id" "$sev" "$dom" "$cls" "$title")" ] || lc_abort plan-invalid 2 "detail=row-mismatch"
    lc_issue_body "$id" "$sev" "$dom" "$cls" "$title" "$ev" "$clos" "$rem" > "$WORK/regen/issues/$id.md"
    cmp -s "$WORK/regen/issues/$id.md" "$ISSUES_PLAN_DIR/issues/$id.md" || lc_abort plan-invalid 2 "detail=body-mismatch"
  done < "$WORK/gaps.tsv"
  [ "$(find "$WORK/regen/issues" -type f | wc -l | tr -d ' ')" = "$PLAN_CREATE_N" ] || lc_abort plan-invalid 2 "detail=row-mismatch"
  lc_epic_initial > "$WORK/regen/epic.md"
  cmp -s "$WORK/regen/epic.md" "$ISSUES_PLAN_DIR/epic.md" || lc_abort plan-invalid 2 "detail=epic-mismatch"

  # Authored bytes are scanned bytes: one blob in send order, before the first write.
  want=$(lc__labels_for "$WORK/plan.rows.tsv")
  while IFS=$'\t' read -r id sev dom cls act title; do
    [ "$act" = create ] || continue
    { printf '%s\n' "$title"; cat "$ISSUES_PLAN_DIR/issues/$id.md"; } >> "$WORK/blob"
  done < "$WORK/plan.rows.tsv"
  { lc_epic_title; cat "$ISSUES_PLAN_DIR/epic.md"; } >> "$WORK/blob"
  for lbl in $want; do printf '%s\n%s\n' "$lbl" "$(lc__label_desc "$lbl")" >> "$WORK/blob"; done
  # The blob is the concatenation of exactly the files that are sent (title line, then the file), in send order, read from the
  # private copy that is also the only place the writes read from; scanning each file again would only repeat it.
  lc_emit_checked "$WORK/blob" "" 1

  # Live state decides what exists.
  lc_issues_live
  lc_live_tables
  lc__live_gate
  if [ "$EPIC_CANDIDATES" = 1 ]; then
    EPIC_NUM=$(cut -f1 "$WORK/live.epics"); EPIC_REF="#$EPIC_NUM"
    if [ "$(cut -f3 "$WORK/live.epics")" = closed ]; then lc__fmt epic_closed_fix; lc_abort epic-closed 2 "detail=epic-closed"; fi
    lc_gh_read api user --jq '.login' || lc__incomplete lookup "$LC_GH_KIND"
    [ "$(cut -f4 "$WORK/live.epics")" = "$(awk 'NR == 1 { print; exit }' "$WORK/gh.out")" ] || { lc__fmt epic_author_fix; lc_abort plan-invalid 2 "detail=epic-author"; }
  fi

  if [ "${LC_DRY:-0}" = 1 ]; then
    while IFS=$'\t' read -r id sev dom cls act title; do
      [ "$act" = create ] || continue
      grep -q "^$id$LC_TAB" "$WORK/live.items" || lc__say "would file: $id | $sev | $title"
    done < "$WORK/plan.rows.tsv"
    lc__fmt dry_run_note
    lc__summary dry-run
    return 0
  fi

  # Labels: only names absent from a fresh listing are created; an existing label is never touched, and nothing is created
  # when the plan files nothing.
  [ "$PLAN_CREATE_N" -gt 0 ] || want=""
  lc_gh_read api "repos/$ISSUES_REPO/labels" -f per_page=100 --paginate --jq '.[].name' || lc__incomplete lookup "$LC_GH_KIND"
  tr '[:upper:]' '[:lower:]' < "$WORK/gh.out" > "$WORK/labels.have"
  for lbl in $want; do
    grep -qxF "$lbl" "$WORK/labels.have" && continue
    if ! lc_gh_write api -X POST "repos/$ISSUES_REPO/labels" -f "name=$lbl" -f "color=$(lc__label_color "$lbl")" -f "description=$(lc__label_desc "$lbl")"; then
      grep -q 'already_exists' "$WORK/gh.out" || lc__incomplete create "$LC_GH_KIND"
    fi
  done

  # The epic.
  if [ -z "$EPIC_NUM" ]; then
    if [ "$PLAN_CREATE_N" -gt 0 ]; then
      lc_gh_write api -X POST "repos/$ISSUES_REPO/issues" -f "title=$(lc_epic_title)" -F "body=@$ISSUES_PLAN_DIR/epic.md" \
        -f 'labels[]=lc:launch-check' -f 'labels[]=lc:epic' --jq '[.number, .id] | @tsv' || lc__incomplete epic "$LC_GH_KIND"
      lc__parse_pair || lc__incomplete epic failed
      EPIC_NUM=$NEW_NUM; EPIC_REF="#$EPIC_NUM"; made_epic=1
      printf 'EPIC\t%s\thttps://%s/%s/issues/%s\n' "$NEW_NUM" "$ISSUES_HOST" "$ISSUES_REPO" "$NEW_NUM" >> "$ISSUES_ORIG_PLAN_DIR/created.tsv" || lc__record_failed
      lc_issues_live
      lc_live_tables
      lc__live_gate
    fi
  fi

  # Orphans: a live open item the plan names that is not under the epic yet is linked, never recreated.
  if [ -n "$EPIC_NUM" ]; then
    : > "$WORK/children"
    if [ "$made_epic" = 0 ]; then
      if lc_gh_read api "repos/$ISSUES_REPO/issues/$EPIC_NUM/sub_issues" --paginate --jq '.[].number'; then cp "$WORK/gh.out" "$WORK/children"
      else
        case "$LC_GH_KIND" in
          http-403|http-404|http-410|http-422) ISSUES_FALLBACK=task-list ;;
          *) lc__incomplete link "$LC_GH_KIND" ;;
        esac
      fi
    fi
  fi
  if [ "$ISSUES_FALLBACK" = none ] && [ -n "$EPIC_NUM" ]; then
    F_ROWS="$WORK/plan.rows.tsv" F_LIVE="$WORK/live.items" F_KIDS="$WORK/children" awk -F'\t' -v OFS='\t' '
      FILENAME == ENVIRON["F_ROWS"] { if ($5 == "create" || $5 == "exists") want[$1] = 1; next }
      FILENAME == ENVIRON["F_KIDS"] { kid[$1] = 1; next }
      $4 == "open" && ($1 in want) && !($2 in kid) { print $3, $2, $1 }' "$WORK/plan.rows.tsv" "$WORK/children" "$WORK/live.items" > "$WORK/orphans.ids"
    while IFS=$'\t' read -r k num id; do
      [ -n "$k" ] || continue
      [ "$ISSUES_FALLBACK" = none ] || break
      lc__link "$k" "$num" "$id"
    done < "$WORK/orphans.ids"
  fi

  # The items, in the saved order. The first failed write stops the run.
  while IFS=$'\t' read -r id sev dom cls act title; do
    [ "$act" = create ] || continue
    if grep -q "^$id$LC_TAB" "$WORK/live.items"; then CNT_SKIPPED=$((CNT_SKIPPED + 1)); continue; fi
    if ! lc_gh_write api -X POST "repos/$ISSUES_REPO/issues" -f "title=$title" -F "body=@$ISSUES_PLAN_DIR/issues/$id.md" \
      -f 'labels[]=lc:launch-check' -f "labels[]=lc:severity-$sev" -f "labels[]=lc:domain-$dom" --jq '[.number, .id] | @tsv'; then
      FAILED_IDS=$id; lc__incomplete create "$LC_GH_KIND"
    fi
    if ! lc__parse_pair; then FAILED_IDS=$id; lc__incomplete create failed; fi
    printf '%s\t%s\thttps://%s/%s/issues/%s\n' "$id" "$NEW_NUM" "$ISSUES_HOST" "$ISSUES_REPO" "$NEW_NUM" >> "$ISSUES_ORIG_PLAN_DIR/created.tsv" || lc__record_failed
    printf '%s\t%s\n' "$id" "$NEW_NUM" >> "$WORK/made.tsv" || lc__record_failed
    CNT_CREATED=$((CNT_CREATED + 1))
    lc__say "created: #$NEW_NUM $id"
    if [ "$ISSUES_FALLBACK" = none ]; then lc__link "$NEW_ID" "$NEW_NUM" "$id"; fi
  done < "$WORK/plan.rows.tsv"

  lc__epic_update
  lc__summary complete
  [ "$EPIC_STATE" != markers-damaged ] || lc__fmt markers_damaged_hint
  return 0
}
