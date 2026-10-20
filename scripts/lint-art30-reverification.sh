#!/usr/bin/env bash
# Partial actuation of re-verification triggers 2, 4, and 5.
# Triggers 1, 3, 6, and 7 stay unactuated.
# The manifest is the only hit predicate. A manifest edit is not the PA-8 review.
set -euo pipefail

export GIT_TERMINAL_PROMPT=0
export LC_ALL=C

MANIFEST_REL="knowledge-base/legal/art30-reverification-triggers.yml"
REGISTER_REL="knowledge-base/legal/article-30-register.md"
RUNBOOK_REL="knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md"

emit_error() {
  local msg="$1"
  msg="${msg//[$'\n\r']/}"
  printf '::error::%s\n' "$msg" >&2
}

if [[ "${EVENT_NAME:-}" == "merge_group" && -z "${MERGE_GROUP_BASE_SHA:-}" ]]; then
  emit_error "merge_group base sha is empty"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_LIB="$SCRIPT_DIR/lib/legal-base-ref.sh"
if [[ ! -f "$BASE_LIB" ]]; then
  emit_error "shared base resolver missing"
  exit 2
fi
# shellcheck source=lib/legal-base-ref.sh
. "$BASE_LIB"

base_out=""
base_rc=0
base_out=$(legal_resolve_base "") || base_rc=$?
if (( base_rc != 0 )); then
  exit 2
fi
if [[ "$base_out" != *$'\t'* ]]; then
  emit_error "resolver returned no merge base field"
  exit 2
fi
MERGE_BASE="${base_out#*$'\t'}"
if [[ -z "$MERGE_BASE" ]]; then
  emit_error "resolver returned an empty merge base"
  exit 2
fi

declare -A CLASS=()
declare -A ROOT_SEEN=()
declare -A TRIGGER_SEEN=()
declare -A CLASS_SEEN=()
declare -A SITE_KEY_SEEN=()
SITE_KINDS=()
PATH_TOKEN_PATHS=()
FILE_PATHS=()
GROUP_TOKENS=()
GROUP_FIRES=()
FILE_FIRES=""
PATH_TOKEN_HAS_FIRES=0
FILE_HAS_GROUPS=0

shape_fail() {
  emit_error "manifest shape rejected"
  exit 1
}

parse_manifest() {
  local file="$1" line raw stripped content indent key id path tok norm
  local in_triggers=0 in_sites=0 in_paths=0 in_groups=0
  local current_trigger="" site_index=-1 site_kind=""
  local pending_token="" pending_open=0
  [[ -f "$file" ]] || { emit_error "manifest missing"; exit 1; }

  close_group() {
    if [[ "$pending_open" == 1 ]]; then
      emit_error "manifest unparseable"
      exit 1
    fi
  }

  note_site_key() {
    local slot="${site_index}|$1"
    if [[ -n "${SITE_KEY_SEEN[$slot]:-}" ]]; then
      emit_error "manifest duplicate key $1"
      exit 1
    fi
    SITE_KEY_SEEN[$slot]=1
  }

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    raw="$line"
    if [[ "$raw" == *$'\t'* ]]; then
      emit_error "manifest unparseable"
      exit 1
    fi
    stripped="${raw#"${raw%%[! ]*}"}"
    indent=$(( ${#raw} - ${#stripped} ))
    if (( indent % 2 != 0 )); then
      emit_error "manifest unparseable"
      exit 1
    fi
    content="$stripped"
    case "$indent" in
      0)
        close_group
        in_paths=0
        in_groups=0
        current_trigger=""
        if [[ "$content" =~ ^([A-Za-z0-9_-]+):[[:space:]]*$ ]]; then
          key="${BASH_REMATCH[1]}"
          if [[ -n "${ROOT_SEEN[$key]:-}" ]]; then
            emit_error "manifest duplicate key ${key}"
            exit 1
          fi
          ROOT_SEEN[$key]=1
          in_triggers=0
          in_sites=0
          if [[ "$key" == "triggers" ]]; then
            in_triggers=1
          elif [[ "$key" == "sites" ]]; then
            in_sites=1
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        else
          emit_error "manifest unparseable"
          exit 1
        fi
        ;;
      2)
        close_group
        in_paths=0
        in_groups=0
        if [[ "$in_triggers" == 1 ]]; then
          if [[ "$content" =~ ^([0-9]+):[[:space:]]*$ ]]; then
            id="${BASH_REMATCH[1]}"
            if [[ -n "${TRIGGER_SEEN[$id]:-}" ]]; then
              emit_error "manifest duplicate key ${id}"
              exit 1
            fi
            TRIGGER_SEEN[$id]=1
            current_trigger="$id"
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        elif [[ "$in_sites" == 1 ]]; then
          if [[ "$content" =~ ^-[[:space:]]kind:[[:space:]]*(path-token|file)[[:space:]]*$ ]]; then
            site_index=$((site_index + 1))
            site_kind="${BASH_REMATCH[1]}"
            SITE_KINDS+=("$site_kind")
            note_site_key "kind"
            current_trigger=""
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        else
          emit_error "manifest unparseable"
          exit 1
        fi
        ;;
      4)
        close_group
        if [[ "$in_triggers" == 1 && -n "$current_trigger" ]]; then
          if [[ "$content" =~ ^class:[[:space:]]*(unactuated|actuated)[[:space:]]*$ ]]; then
            if [[ -n "${CLASS_SEEN[$current_trigger]:-}" ]]; then
              emit_error "manifest duplicate key class"
              exit 1
            fi
            CLASS_SEEN[$current_trigger]=1
            CLASS[$current_trigger]="${BASH_REMATCH[1]}"
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        elif [[ "$in_sites" == 1 && "$site_index" -ge 0 ]]; then
          if [[ "$content" == "paths:" ]]; then
            note_site_key "paths"
            in_paths=1
            in_groups=0
          elif [[ "$content" == "groups:" ]]; then
            note_site_key "groups"
            if [[ "$site_kind" == "file" ]]; then
              FILE_HAS_GROUPS=1
            fi
            in_groups=1
            in_paths=0
          elif [[ "$content" =~ ^fires:[[:space:]]*\[([0-9,[:space:]]*)\][[:space:]]*$ ]]; then
            note_site_key "fires"
            norm="${BASH_REMATCH[1]//[[:space:]]/}"
            if [[ ! "$norm" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
              emit_error "manifest unparseable"
              exit 1
            fi
            if [[ "$site_kind" == "file" ]]; then
              FILE_FIRES="$norm"
            else
              PATH_TOKEN_HAS_FIRES=1
            fi
            in_paths=0
            in_groups=0
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        else
          emit_error "manifest unparseable"
          exit 1
        fi
        ;;
      6)
        if [[ "$in_paths" == 1 && "$site_index" -ge 0 ]]; then
          close_group
          if [[ "$content" =~ ^-[[:space:]]([^[:space:]]+)[[:space:]]*$ ]]; then
            path="${BASH_REMATCH[1]}"
            if [[ "$site_kind" == "path-token" ]]; then
              PATH_TOKEN_PATHS+=("$path")
            elif [[ "$site_kind" == "file" ]]; then
              FILE_PATHS+=("$path")
            else
              emit_error "manifest unparseable"
              exit 1
            fi
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        elif [[ "$in_groups" == 1 ]]; then
          if [[ "$content" =~ ^-[[:space:]]token:[[:space:]]*(--[A-Za-z0-9-]+)[[:space:]]*$ ]]; then
            if [[ "$pending_open" == 1 ]]; then
              emit_error "manifest unparseable"
              exit 1
            fi
            pending_token="${BASH_REMATCH[1]}"
            pending_open=1
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        else
          emit_error "manifest unparseable"
          exit 1
        fi
        ;;
      8)
        if [[ "$in_groups" == 1 ]]; then
          if [[ "$content" =~ ^fires:[[:space:]]*\[([0-9,[:space:]]*)\][[:space:]]*$ ]]; then
            if [[ "$pending_open" != 1 ]]; then
              emit_error "manifest duplicate key fires"
              exit 1
            fi
            norm="${BASH_REMATCH[1]//[[:space:]]/}"
            if [[ ! "$norm" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
              emit_error "manifest unparseable"
              exit 1
            fi
            GROUP_TOKENS+=("$pending_token")
            GROUP_FIRES+=("$norm")
            pending_open=0
            pending_token=""
          else
            emit_error "manifest unparseable"
            exit 1
          fi
        else
          emit_error "manifest unparseable"
          exit 1
        fi
        ;;
      *)
        emit_error "manifest unparseable"
        exit 1
        ;;
    esac
  done < "$file"
  close_group
}

check_shape() {
  local n got want p
  for n in 1 2 3 4 5 6 7; do
    [[ -n "${CLASS[$n]:-}" ]] || shape_fail
  done
  for n in "${!CLASS[@]}"; do
    case "$n" in
      1|2|3|4|5|6|7) ;;
      *) shape_fail ;;
    esac
  done
  [[ "${CLASS[1]}" == "unactuated" ]] || shape_fail
  [[ "${CLASS[2]}" == "actuated" ]] || shape_fail
  [[ "${CLASS[3]}" == "unactuated" ]] || shape_fail
  [[ "${CLASS[4]}" == "actuated" ]] || shape_fail
  [[ "${CLASS[5]}" == "actuated" ]] || shape_fail
  [[ "${CLASS[6]}" == "unactuated" ]] || shape_fail
  [[ "${CLASS[7]}" == "unactuated" ]] || shape_fail
  [[ "${#SITE_KINDS[@]}" -eq 2 ]] || shape_fail
  [[ "${SITE_KINDS[0]}" == "path-token" && "${SITE_KINDS[1]}" == "file" ]] || shape_fail
  [[ "$PATH_TOKEN_HAS_FIRES" == 0 && "$FILE_HAS_GROUPS" == 0 ]] || shape_fail
  got="$(printf '%s\n' "${PATH_TOKEN_PATHS[@]}" | LC_ALL=C sort)"
  want="$(printf '%s\n' \
    "apps/web-platform/infra/ci-deploy.sh" \
    "apps/web-platform/infra/cloud-init.yml" | LC_ALL=C sort)"
  [[ "$got" == "$want" ]] || shape_fail
  got="$(printf '%s\n' "${FILE_PATHS[@]}" | LC_ALL=C sort)"
  want="apps/web-platform/infra/journald-soleur.conf"
  [[ "$got" == "$want" ]] || shape_fail
  [[ "${#GROUP_TOKENS[@]}" -eq 3 && "${#GROUP_FIRES[@]}" -eq 3 ]] || shape_fail
  [[ "${GROUP_TOKENS[0]}" == "--log-driver" && "${GROUP_FIRES[0]}" == "2,4" ]] || shape_fail
  [[ "${GROUP_TOKENS[1]}" == "--log-opt" && "${GROUP_FIRES[1]}" == "2,4" ]] || shape_fail
  [[ "${GROUP_TOKENS[2]}" == "--restart" && "${GROUP_FIRES[2]}" == "4" ]] || shape_fail
  [[ "$FILE_FIRES" == "5" ]] || shape_fail
  for p in "${PATH_TOKEN_PATHS[@]}" "${FILE_PATHS[@]}"; do
    [[ "$p" != *"daemon.json" ]] || shape_fail
  done
}

ids_match_closed_list() {
  local text="$1" id n count=0
  local -A seen=()
  while IFS= read -r id || [[ -n "${id:-}" ]]; do
    [[ -z "${id:-}" ]] && continue
    seen["$id"]=1
  done <<< "$text"
  for n in 1 2 3 4 5 6 7; do
    [[ -n "${seen[$n]:-}" ]] || return 1
  done
  for n in "${!seen[@]}"; do
    count=$((count + 1))
  done
  [[ "$count" -eq 7 ]]
}

runbook_ids_text() {
  local text="$1" line p=0
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    if [[ "$line" == "### Re-verification triggers" ]]; then
      p=1
      continue
    fi
    if [[ "$p" == 1 && "$line" == "### "* ]]; then
      break
    fi
    if [[ "$p" == 1 && "$line" =~ ^([0-9]+)\. ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done <<< "$text"
  [[ "$p" == 1 ]]
}

# The cell is the committed blob, not a worktree read. Exactly one PA-8
# heading and exactly one line that contains the table marker
# "| **(f) Retention**" in that section. A prose mention of (f) Retention
# is not the cell. A
# symlink blob is the link text, so mode 120000 cannot supply the cell.
pa8_cell_text() {
  local text="$1" line p=0 found=0 headings=0 cell=""
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    if [[ "$line" == "## Processing Activity 8 "* ]]; then
      headings=$((headings + 1))
      p=1
      continue
    fi
    if [[ "$p" == 1 && "$line" == "## Processing Activity 9 "* ]]; then
      p=0
      continue
    fi
    if [[ "$p" == 1 && "$line" == *"| **(f) Retention**"* ]]; then
      cell="$line"
      found=$((found + 1))
    fi
  done <<< "$text"
  [[ "$headings" -eq 1 && "$found" -eq 1 ]] || return 1
  printf '%s\n' "$cell"
}

bold_ids_text() {
  local tmp="$1"
  while [[ "$tmp" =~ \*\*\(([0-9]+)\)\*\* ]]; do
    printf '%s\n' "${BASH_REMATCH[1]}"
    tmp="${tmp#*"${BASH_REMATCH[0]}"}"
  done
}

token_matches() {
  local content="$1" token="$2" re
  re="(^|[[:space:]]|'|\")${token}(\$|=|[[:space:]]|'|\")"
  [[ "$content" =~ $re ]]
}

add_fire_ids() {
  local spec="$1" id
  local -a ids=()
  IFS=',' read -ra ids <<< "$spec"
  for id in "${ids[@]}"; do
    [[ -n "$id" ]] || continue
    FIRED["$id"]=1
  done
}

parse_manifest "$MANIFEST_REL"
check_shape

token_dir="$(mktemp -d)"
cleanup_tokens() {
  if [[ -n "${token_dir:-}" && -d "$token_dir" ]]; then
    rm -rf -- "$token_dir"
  fi
}
trap cleanup_tokens EXIT

cell_rc=0
head_blob="$token_dir/head-register"
head_register=""
nul_bytes=0
git cat-file blob "HEAD:${REGISTER_REL}" > "$head_blob" || cell_rc=$?
if (( cell_rc == 0 )); then
  nul_bytes=$(tr -cd '\0' < "$head_blob" | wc -c) || cell_rc=$?
fi
if (( cell_rc == 0 && nul_bytes > 0 )); then
  cell_rc=1
fi
if (( cell_rc == 0 )) && git ls-tree HEAD -- "$REGISTER_REL" | grep -q '^120000'; then
  cell_rc=1
fi
if (( cell_rc == 0 )); then
  head_register=$(cat "$head_blob") || cell_rc=$?
fi
HEAD_CELL=""
if (( cell_rc == 0 )); then
  HEAD_CELL=$(pa8_cell_text "$head_register") || cell_rc=$?
fi
if (( cell_rc != 0 || ${#HEAD_CELL} == 0 )); then
  emit_error "id census rejected"
  exit 1
fi

rb_rc=0
rb_file="$token_dir/runbook"
rb_blob=""
nul_bytes=0
git cat-file blob "HEAD:${RUNBOOK_REL}" > "$rb_file" || rb_rc=$?
if (( rb_rc == 0 )); then
  nul_bytes=$(tr -cd '\0' < "$rb_file" | wc -c) || rb_rc=$?
fi
if (( rb_rc == 0 && nul_bytes > 0 )); then
  rb_rc=1
fi
if (( rb_rc == 0 )); then
  rb_blob=$(cat "$rb_file") || rb_rc=$?
fi
RB_IDS=""
if (( rb_rc == 0 )); then
  RB_IDS=$(runbook_ids_text "$rb_blob") || rb_rc=$?
fi
if (( rb_rc != 0 )); then
  emit_error "id census rejected"
  exit 1
fi
MF_IDS=""
for n in 1 2 3 4 5 6 7; do
  if [[ -n "${CLASS[$n]:-}" ]]; then
    MF_IDS+="${n}"$'\n'
  fi
done
for n in "${!CLASS[@]}"; do
  case "$n" in
    1|2|3|4|5|6|7) ;;
    *) MF_IDS+="${n}"$'\n' ;;
  esac
done
BOLD_IDS="$(bold_ids_text "$HEAD_CELL")"
if ! ids_match_closed_list "$RB_IDS" || ! ids_match_closed_list "$MF_IDS" || ! ids_match_closed_list "$BOLD_IDS"; then
  emit_error "id census rejected"
  exit 1
fi

declare -A FIRED=()
declare -A FIRED_PATH=()
saw_binary=0
current_path=""

filter_rc=0
flag_diff=""
flag_diff=$(git diff --no-ext-diff --no-textconv --no-color "${MERGE_BASE}...HEAD" -- "${PATH_TOKEN_PATHS[@]}") || filter_rc=$?
if (( filter_rc != 0 )); then
  emit_error "git diff of watched flag paths failed"
  exit 2
fi

while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "$line" ]] && continue
  if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/ ]]; then
    current_path="${BASH_REMATCH[1]}"
    continue
  fi
  if [[ "$line" =~ ^---[[:space:]] ]] || [[ "$line" =~ ^\+\+\+[[:space:]] ]]; then
    continue
  fi
  if [[ "$line" =~ ^Binary\ files\ .+\ differ$ ]]; then
    saw_binary=1
    continue
  fi
  [[ "$line" == [+-]* ]] || continue
  body="${line:1}"
  trim="${body#"${body%%[![:space:]]*}"}"
  [[ -z "$trim" || "${trim:0:1}" == "#" ]] && continue
  gi=0
  while (( gi < ${#GROUP_TOKENS[@]} )); do
    if token_matches "$trim" "${GROUP_TOKENS[$gi]}"; then
      add_fire_ids "${GROUP_FIRES[$gi]}"
      if [[ -n "$current_path" ]]; then
        FIRED_PATH["$current_path"]=1
      fi
    fi
    gi=$((gi + 1))
  done
done <<< "$flag_diff"

if [[ "$saw_binary" == 1 ]]; then
  for spec in "${GROUP_FIRES[@]}"; do
    add_fire_ids "$spec"
  done
  for p in "${PATH_TOKEN_PATHS[@]}"; do
    FIRED_PATH["$p"]=1
  done
  path_msg=""
  id_msg=""
  for p in "${PATH_TOKEN_PATHS[@]}"; do
    path_msg+="${path_msg:+ }${p}"
  done
  for n in 1 2 3 4 5 6 7; do
    if [[ -n "${FIRED[$n]:-}" ]]; then
      id_msg+=" ${n}"
    fi
  done
  emit_error "watched ${path_msg} fired ids${id_msg}"
  exit 1
fi

ns_rc=0
ns_out=""
ns_out=$(git diff --name-status --no-renames --no-textconv "${MERGE_BASE}...HEAD" -- "${FILE_PATHS[@]}") || ns_rc=$?
if (( ns_rc != 0 )); then
  emit_error "git diff name-status of the journald path failed"
  exit 2
fi
while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  add_fire_ids "$FILE_FIRES"
  for p in "${FILE_PATHS[@]}"; do
    FIRED_PATH["$p"]=1
  done
  break
done <<< "$ns_out"

fired_count=0
for n in 1 2 3 4 5 6 7; do
  if [[ -n "${FIRED[$n]:-}" ]]; then
    fired_count=$((fired_count + 1))
  fi
done
if (( fired_count == 0 )); then
  exit 0
fi

show_rc=0
base_file="$token_dir/base-register"
base_register=""
nul_bytes=0
git cat-file blob "${MERGE_BASE}:${REGISTER_REL}" > "$base_file" || show_rc=$?
if (( show_rc != 0 )); then
  emit_error "cannot read the base register"
  exit 2
fi
nul_bytes=$(tr -cd '\0' < "$base_file" | wc -c) || show_rc=$?
base_cell_rc=0
if (( show_rc != 0 || nul_bytes > 0 )); then
  base_cell_rc=1
fi
if (( base_cell_rc == 0 )) && git ls-tree "$MERGE_BASE" -- "$REGISTER_REL" | grep -q '^120000'; then
  base_cell_rc=1
fi
if (( base_cell_rc == 0 )); then
  base_register=$(cat "$base_file") || base_cell_rc=$?
fi
REMOVED_CELL=""
if (( base_cell_rc == 0 )); then
  REMOVED_CELL=$(pa8_cell_text "$base_register") || base_cell_rc=$?
fi
if (( base_cell_rc != 0 || ${#REMOVED_CELL} == 0 )); then
  emit_error "id census rejected"
  exit 1
fi

removed_tokens="$token_dir/removed"
added_tokens="$token_dir/added"
read -ra removed_parts <<< "$REMOVED_CELL"
: > "$removed_tokens"
if ((${#removed_parts[@]})); then
  for token in "${removed_parts[@]}"; do
    printf '%s\n' "$token" >> "$removed_tokens"
  done
fi
read -ra added_parts <<< "$HEAD_CELL"
: > "$added_tokens"
if ((${#added_parts[@]})); then
  for token in "${added_parts[@]}"; do
    printf '%s\n' "$token" >> "$added_tokens"
  done
fi
diff_rc=0
diff "$removed_tokens" "$added_tokens" > "$token_dir/token.diff" || diff_rc=$?
if (( diff_rc == 2 )); then
  emit_error "token diff failed"
  exit 2
fi
if (( diff_rc != 0 && diff_rc != 1 )); then
  emit_error "token diff failed"
  exit 2
fi

ADDED_TOKENS=()
if (( diff_rc == 1 )); then
  while IFS= read -r dline || [[ -n "${dline:-}" ]]; do
    if [[ "$dline" == "> "* ]]; then
      ADDED_TOKENS+=("${dline:2}")
    fi
  done < "$token_dir/token.diff"
fi

date_ok=0
word_ok=0
if ((${#ADDED_TOKENS[@]})); then
  for tok in "${ADDED_TOKENS[@]}"; do
    if [[ "$tok" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      if [[ "$REMOVED_CELL" != *"$tok"* ]]; then
        date_ok=1
      fi
    elif [[ "$tok" =~ [[:alpha:]] ]]; then
      word_ok=1
    fi
  done
fi

ids_ok=1
for n in 1 2 3 4 5 6 7; do
  [[ -n "${FIRED[$n]:-}" ]] || continue
  found=0
  if ((${#ADDED_TOKENS[@]})); then
    for tok in "${ADDED_TOKENS[@]}"; do
      if [[ "$tok" =~ (^|[^0-9])${n}([^0-9]|$) ]]; then
        found=1
        break
      fi
    done
  fi
  if [[ "$found" != 1 ]]; then
    ids_ok=0
  fi
done

if [[ "$date_ok" == 1 && "$word_ok" == 1 && "$ids_ok" == 1 ]]; then
  exit 0
fi

path_msg=""
id_msg=""
for p in "${PATH_TOKEN_PATHS[@]}" "${FILE_PATHS[@]}"; do
  if [[ -n "${FIRED_PATH[$p]:-}" ]]; then
    path_msg+="${path_msg:+ }${p}"
  fi
done
for n in 1 2 3 4 5 6 7; do
  if [[ -n "${FIRED[$n]:-}" ]]; then
    id_msg+=" ${n}"
  fi
done
emit_error "watched ${path_msg} fired ids${id_msg}"
exit 1
