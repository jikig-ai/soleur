#!/usr/bin/env bash
# operator-ack-guard.test.sh — Guards 1 and 2 of #8486 (ADR-249).
#
# The class under test: an operator script that writes to production behind a
# prompt that piped stdin or a flag can satisfy, so an agent's tool subprocess
# (no TTY) completes the write unattended. The fix gates every such write on the
# library's class-2 ack (plugins/soleur/scripts/lib/operator-script.sh
# soleur_op_ack_or_die: no skip variable, no flag) plus an early no-TTY precheck
# right after argv parsing.
#
# Guard 1 — census. No tracked shell script outside the library asks for a human
#   confirmation through a raw prompt, or offers a flag that skips one, unless it
#   is a classified exemption. Population DISCOVERED (git ls-files), exemptions
#   held to set identity both ways.
# Guard 2 — behavioural. For every write arm of every script that calls the ack
#   (population grep-derived, set identity against the arm table both ways):
#   no TTY -> exit 64 and ZERO stub calls of any kind; a pty answered `no` ->
#   exit 1 and zero mutating calls; a pty answered `yes` -> at least one mutating
#   call (the positive control) and, for the flag scripts, a WORM body carrying
#   "p_approval_method":"tty-ack"; every read-only row -> exit 0 without a TTY and
#   zero mutating calls. Every ack prompt must be observed in some pty run.
#
# Every mutation row runs against a COPY (a mirror tree or a fixture tree), and
# every copy is proven to differ from its source before its verdict is read: a
# mutation that does not land re-runs the baseline, and a baseline pass is
# indistinguishable from a real one.
#
# Run via:  bash plugins/soleur/test/operator-ack-guard.test.sh
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Arms the #7833 tripwire: an inherited GIT_DIR/GIT_INDEX_FILE aborts the suite
# (rc 97) instead of letting `git -C` below read another repository.
# shellcheck source=./lib/git-fixture-env.sh
source "${SUITE_DIR}/lib/git-fixture-env.sh"

REPO_ROOT="$(cd "${SUITE_DIR}/../../.." && pwd)"
ARMS="${SUITE_DIR}/fixtures/operator-ack-arms.tsv"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }

# assert_red <guard> <label> <args...> — the guard must exit non-zero.
assert_red() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "${label}: drove ${guard} RED"
    G_LAST_OUT="$out"
  else
    fail "${label}: ${guard} stayed GREEN over the mutation — the guard does not see it"
    G_LAST_OUT="$out"
  fi
}

# assert_green <guard> <label> <args...> — the guard must exit zero.
assert_green() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "${label}: ${guard} GREEN"
  else
    fail "${label}: ${guard} unexpectedly RED:
${out}"
  fi
  G_LAST_OUT="$out"
}
G_LAST_OUT=""

# reason <label> <ERE> — the RED just recorded must be for the NAMED cause. A row
# that goes red for an incidental reason proves nothing about its mutation.
reason() {
  if grep -qE -- "$2" <<<"$G_LAST_OUT"; then pass "$1: red for the named reason"
  else fail "$1: red for a different reason than named (/$2/): $(head -3 <<<"$G_LAST_OUT" | tr '\n' ' ')"; fi
}

# --- ADR-193 instrument self-test -------------------------------------------
# Reported through printf + exit, never through the helpers it backstops.
_st_p=$PASS_COUNT; _st_f=$FAIL_COUNT
pass "instrument self-test: pass() reached" >/dev/null
fail "instrument self-test: fail() reached (expected, not a real failure)" 2>/dev/null
if [[ "$PASS_COUNT" -ne $((_st_p + 1)) || "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: pass/fail helpers did not both move (pass %s->%s, fail %s->%s)\n' \
    "$_st_p" "$PASS_COUNT" "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
_st_f=$FAIL_COUNT
assert_red true "instrument self-test known-negative" >/dev/null 2>&1
if [[ "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_red did not register a failure for a guard that exited 0\n' >&2
  exit 2
fi
_st_f=$FAIL_COUNT
assert_green false "instrument self-test known-negative" >/dev/null 2>&1
if [[ "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_green did not register a failure for a guard that exited 1\n' >&2
  exit 2
fi
# The two known-negatives and the fail() probe are expected failures, not real
# ones: take them back out so the verdict below counts only guard rows.
PASS_COUNT=0
FAIL_COUNT=0

SB="$(mktemp -d -t operator-ack-guard.XXXXXXXX)" || { printf 'cannot create sandbox\n' >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# The canonical fixture-dir guard (byte-for-byte the helper the fixture ratchets
# recognise, e.g. .claude/hooks/cla-signed-author-gate.test.sh): every write
# under a sandbox root is preceded by it, so an unbound or relative root aborts
# instead of writing into the caller's working directory.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# =============================================================================
# Guard 1 — typed-yes census
# =============================================================================
#
# Detector (a): a `read` that starts a command (the library suite's READ_SITE_RE
# shape: line-initial, after a separator, or after `IFS=`) whose own line
# mentions yes / y/N, OR whose read variable is later compared to y/yes. The
# comparison arm is what catches `printf 'Type yes: '; IFS= read -r ans` (M5),
# where the prompt text is not on the read line.
# Detector (b): a `case` arm label among the confirm-skip flags.

G1_EXEMPT=(
  "plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh|class-3 attest barrier (TF apply complete?) followed by independent verification; gates no production write of its own (brainstorm Non-Goals)"
  "plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh|class-3 attest barrier followed by independent verification (brainstorm Non-Goals)"
  "plugins/soleur/skills/provision-github/scripts/provision-github.sh|class-3 attest barriers (TF apply complete?, App installed?) followed by independent verification (brainstorm Non-Goals)"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh|local worktree cleanup prompts; no production write"
  "plugins/soleur/skills/feature-video/scripts/check_deps.sh|local dependency-install prompt on the founder's own machine; no production write"
  "plugins/soleur/skills/pencil-setup/scripts/check_deps.sh|local dependency-install prompt on the founder's own machine; no production write"
)

READ_SITE_RE='(^[[:space:]]*|[;&|][[:space:]]*|IFS=[[:space:]]*)read([[:space:]]|$)'
CONFIRM_FLAGS_RE='^(--confirmed|--yes|-y|--assume-yes|--no-confirm|--no-prompt)$'
CASE_ARM_RE='^[[:space:]]*\(?[[:space:]]*-[-A-Za-z0-9|]*\)'

# The comment stripper every census reads through: comment lines are BLANKED, not
# deleted, so a reported line number is the file's real one. A variable so
# harness row H1 can prove it is load-bearing by swapping in `cat`.
g1_strip() { sed -E 's/^[[:space:]]*#.*$//' "$1" 2>/dev/null || true; }
G1_STRIPPER=g1_strip

g1_population() { # <root> -> repo-relative *.sh paths, discovered
  local root="$1"
  if [[ -e "$root/.git" ]]; then
    git -C "$root" ls-files -- '*.sh'
  else
    ( cd "$root" && find . -type f -name '*.sh' | sed 's|^\./||' )
  fi | grep -vE '\.test\.sh$|(^|/)test/|(^|/)fixtures/|(^|/)scripts/lib/operator-script\.sh$|(^|/)operator-bootstrap/template\.sh$|^knowledge-base/' \
     | sort
}

# g1_hits_file <abs> <rel> -> "rel:line:kind" per hit
g1_hits_file() {
  local f="$1" rel="$2" stripped ln line words w label alt
  stripped="$("$G1_STRIPPER" "$f")"
  # (a) read sites
  while IFS=: read -r ln line; do
    [[ -n "$ln" ]] || continue
    if grep -qiE "yes|y/n|\[y[/|]" <<<"$line"; then
      echo "${rel}:${ln}:typed-yes-prompt"; continue
    fi
    # Candidate read variables: identifier words after `read`, quoted text and
    # options removed (a prompt string never names the variable).
    words="$(sed -E "s/.*(^|[;&|[:space:]=])read[[:space:]]//; s/[;&|<)].*$//; s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$line")"
    for w in $words; do
      [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      if grep -qE "\\\$\\{?${w}([,^]+)?\\}?\"?[[:space:]]*(==|!=|=)[[:space:]]*\"?(y|yes|Y|YES|Yes)\"?([^A-Za-z0-9_]|$)|\\\$\\{?${w}([,^]+)?\\}?\"?[[:space:]]*=~[[:space:]]*\\^?\\(?\\[?[Yy]" <<<"$stripped"; then
        echo "${rel}:${ln}:typed-yes-compare(${w})"; break
      fi
      if grep -qE "case[[:space:]]+\"?\\\$\\{?${w}([,^]+)?\\}?\"?[[:space:]]+in" <<<"$stripped" \
         && grep -qE '^[[:space:]]*\(?[[:space:]]*(y|yes|Y|YES|\[[Yy]\])[^A-Za-z0-9_]*[|)]' <<<"$stripped"; then
        echo "${rel}:${ln}:typed-yes-case(${w})"; break
      fi
    done
  done < <(grep -nE "$READ_SITE_RE" <<<"$stripped")
  # (b) confirm-skip flag case arms
  while IFS=: read -r ln line; do
    [[ -n "$ln" ]] || continue
    label="$(sed -E 's/^[[:space:]]*\(?[[:space:]]*//; s/\).*$//' <<<"$line")"
    IFS='|' read -r -a alt <<<"$label"
    for w in "${alt[@]}"; do
      if [[ "$w" =~ $CONFIRM_FLAGS_RE ]]; then echo "${rel}:${ln}:confirm-skip-flag(${w})"; break; fi
    done
  done < <(grep -nE "$CASE_ARM_RE" <<<"$stripped")
}

# g1_check <root> <exempt-file> — census + exemption set identity
g1_check() {
  local root="$1" exf="$2" v=0 n=0 rel allhits="" h hitfiles exempt f
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    n=$((n + 1))
    h="$(g1_hits_file "$root/$rel" "$rel")"
    [[ -n "$h" ]] && allhits+="${h}"$'\n'
  done < <(g1_population "$root")
  if [[ "$n" -eq 0 ]]; then
    echo "g1: census scanned 0 files — nothing was checked"
    return 1
  fi
  hitfiles="$(cut -d: -f1 <<<"$allhits" | grep -v '^$' | sort -u)"
  exempt="$(cut -d'|' -f1 "$exf" | grep -v '^$' | sort -u)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    echo "g1: unclassified raw confirmation gate in ${f}: $(grep -F "${f}:" <<<"$allhits" | tr '\n' ' ')"
    v=1
  done < <(comm -23 <(printf '%s\n' "$hitfiles") <(printf '%s\n' "$exempt"))
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    echo "g1: stale exemption ${f}: it names no live census hit (renamed, deleted or no longer prompting) — remove it"
    v=1
  done < <(comm -13 <(printf '%s\n' "$hitfiles") <(printf '%s\n' "$exempt"))
  echo "g1: scanned ${n} files; hits in: $(tr '\n' ' ' <<<"$hitfiles")"
  return "$v"
}

# g1_token_check <root> — no `--confirmed` token on any model-read skill surface
# or skill script (AC8's skill half).
g1_token_check() {
  local root="$1" hits
  hits="$(cd "$root" && grep -lF -- '--confirmed' plugins/soleur/skills/*/SKILL.md plugins/soleur/skills/*/scripts/*.sh plugins/soleur/commands/*.md 2>/dev/null)"
  if [[ -n "$hits" ]]; then
    echo "g1: --confirmed still appears in: $(tr '\n' ' ' <<<"$hits")"
    return 1
  fi
  return 0
}

echo "== Guard 1 — typed-yes census =="

EXEMPT_FILE="$SB/g1-exempt.txt"
printf '%s\n' "${G1_EXEMPT[@]}" > "$EXEMPT_FILE"
EMPTY_EXEMPT="$SB/g1-exempt-empty.txt"; : > "$EMPTY_EXEMPT"

assert_green g1_check "live tree" "$REPO_ROOT" "$EXEMPT_FILE"
echo "$G_LAST_OUT" | grep -E '^g1: scanned' | sed 's/^/    /'
assert_green g1_token_check "live tree carries no --confirmed on skill surfaces" "$REPO_ROOT"

# Fixture trees. Each starts from a CLEAN script so a RED is attributable to the
# one edit the row makes.
g1_fixture() { # <name> -> fresh fixture root with one clean script in it
  local d="$SB/g1/$1"
  mkdir -p "$d/apps/web-platform/scripts"
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho clean\n' > "$d/apps/web-platform/scripts/clean.sh"
  printf '%s' "$d"
}
g1_copy() { # <fixture-root> <repo-rel> — copy a live script into the fixture
  mkdir -p "$1/$(dirname "$2")"
  cp "$REPO_ROOT/$2" "$1/$2"
}

DELETE_REL="plugins/soleur/skills/flag-delete/scripts/delete.sh"
FLIP_REL="plugins/soleur/skills/flag-set-role/scripts/flip.sh"

d="$(g1_fixture baseline)"; g1_copy "$d" "$DELETE_REL"; g1_copy "$d" "$FLIP_REL"
assert_green g1_check "g1 fixture baseline (clean + live delete.sh + live flip.sh)" "$d" "$EMPTY_EXEMPT"

# M1 — a raw typed-yes re-added to delete.sh
d="$(g1_fixture m1)"; g1_copy "$d" "$DELETE_REL"
assert_fixture_dir "$d"
printf '\nread -r -p "Proceed? Type %s: " ACK\n[[ "$ACK" == "yes" ]] || exit 0\n' "'yes'" >> "$d/$DELETE_REL"
if [[ "$(md5_of "$d/$DELETE_REL")" != "$(md5_of "$REPO_ROOT/$DELETE_REL")" ]]; then
  assert_red g1_check "g1-M1 raw typed-yes re-added to delete.sh" "$d" "$EMPTY_EXEMPT"
else fail "g1-M1 mutation did not land"; fi

# M2 — the confirm-skip flag re-added to flip.sh
d="$(g1_fixture m2)"; g1_copy "$d" "$FLIP_REL"
perl -0777 -pi -e 's{(\n[ \t]*--dry-run\)[^\n]*\n)}{$1    --confirmed)     CONFIRMED=1; shift ;;\n}' "$d/$FLIP_REL"
if [[ "$(md5_of "$d/$FLIP_REL")" != "$(md5_of "$REPO_ROOT/$FLIP_REL")" ]]; then
  assert_red g1_check "g1-M2 --confirmed case arm re-added to flip.sh" "$d" "$EMPTY_EXEMPT"
reason "g1-M2" "confirm-skip-flag\\(--confirmed\\)"
else fail "g1-M2 mutation did not land"; fi

# M3 — own dispatch: an empty tree must not report "0 violations"
mkdir -p "$SB/g1/m3-empty"
assert_red g1_check "g1-M3 census over an empty tree" "$SB/g1/m3-empty" "$EMPTY_EXEMPT"

# M4 — a second member after a compliant first
d="$(g1_fixture m4)"
assert_fixture_dir "$d"
printf '#!/usr/bin/env bash\nread -r -p "Delete everything? Type %s: " a\n[[ "$a" == yes ]] || exit 1\n' "'yes'" > "$d/apps/web-platform/scripts/new-writer.sh"
assert_red g1_check "g1-M4 new raw typed-yes script beside a clean one" "$d" "$EMPTY_EXEMPT"
if grep -qF 'new-writer.sh' <<<"$G_LAST_OUT"; then pass "g1-M4 names the new file"; else fail "g1-M4 RED did not name new-writer.sh: $G_LAST_OUT"; fi

# M5 — prompt text on a printf, not on the read line
d="$(g1_fixture m5)"
assert_fixture_dir "$d"
printf '#!/usr/bin/env bash\nprintf "Type yes: "\nIFS= read -r ans\nif [[ "$ans" == "yes" ]]; then echo go; fi\n' > "$d/apps/web-platform/scripts/sneaky.sh"
assert_red g1_check "g1-M5 comparison-only typed-yes (printf prompt, IFS= read)" "$d" "$EMPTY_EXEMPT"
reason "g1-M5" "typed-yes-compare\\(ans\\)"

# M6 — stale exemption (set identity, exemption side)
d="$(g1_fixture m6)"
printf 'plugins/soleur/skills/provision-github/scripts/provision-github.sh|renamed away\n' > "$SB/g1-exempt-m6.txt"
assert_red g1_check "g1-M6 exemption names a file that is not in the tree" "$d" "$SB/g1-exempt-m6.txt"
if grep -qF 'stale exemption' <<<"$G_LAST_OUT"; then pass "g1-M6 reports it as stale"; else fail "g1-M6 RED for the wrong reason: $G_LAST_OUT"; fi

# M7 — --confirmed back on a skill surface
d="$SB/g1/m7"; mkdir -p "$d/plugins/soleur/skills/flag-set-role"
printf 'Run `flip.sh <flag> prd on --confirmed` after the operator says yes.\n' > "$d/plugins/soleur/skills/flag-set-role/SKILL.md"
assert_red g1_token_check "g1-M7 --confirmed in flag-set-role/SKILL.md" "$d"

# H1 — the comment stripper is load-bearing
d="$(g1_fixture h1)"
assert_fixture_dir "$d"
printf '#!/usr/bin/env bash\n# retired: echo go; read -r -p "Type %s: " ACK\n# [[ "$ACK" == "yes" ]]\necho fine\n' "'yes'" > "$d/apps/web-platform/scripts/commented.sh"
assert_green g1_check "g1-H1 baseline: a commented-out prompt is not a gate" "$d" "$EMPTY_EXEMPT"
G1_STRIPPER=cat
assert_red g1_check "g1-H1 stripper replaced by cat scans the comment" "$d" "$EMPTY_EXEMPT"
G1_STRIPPER=g1_strip

# H2 — must-PASS: a yes comparison on a variable no read ever filled
d="$(g1_fixture h2)"
assert_fixture_dir "$d"
printf '#!/usr/bin/env bash\nwith=yes\nx="$(printf %%s "$with")"\nif [[ "$x" == "yes" ]]; then echo rolled; fi\n' > "$d/apps/web-platform/scripts/apex-rollback.sh"
assert_green g1_check "g1-H2 yes comparison on a non-read variable" "$d" "$EMPTY_EXEMPT"

# H3 — must-PASS: -y inside argv, not a case label
d="$(g1_fixture h3)"
assert_fixture_dir "$d"
printf '#!/usr/bin/env bash\napt-get install -y jq\ncurl -y 30 https://example.invalid/\n' > "$d/apps/web-platform/scripts/argv-y.sh"
assert_green g1_check "g1-H3 -y as a tool option" "$d" "$EMPTY_EXEMPT"

# =============================================================================
# Guard 2 — behavioural: no mutating call without a person at a TTY
# =============================================================================

command -v script >/dev/null 2>&1 || { fail "Guard 2: script(1) is not installed — the pty arms cannot run"; }
SCRIPT_BIN="$(type -P script)"
BASH_BIN="$(type -P bash)"
TIMEOUT_BIN="$(type -P timeout)"

# Network-capable binaries that must NEVER be reachable from the sandbox PATH
# except as a logging stub.
NET_BINS='^(curl|doppler|wget|gh|hcloud|ssh|scp|sftp|nc|ncat|socat|psql|terraform|tofu|script|expect|unbuffer)$'

g2_population() { # <root> -> rel paths of scripts that CALL the ack
  local root="$1" rel
  if [[ -e "$root/.git" ]]; then
    git -C "$root" grep -l -e 'soleur_op_ack_or_die' -- '*.sh'
  else
    ( cd "$root" && grep -rl --include='*.sh' -e 'soleur_op_ack_or_die' . | sed 's|^\./||' )
  fi | grep -vE '\.test\.sh$|(^|/)test/|(^|/)scripts/lib/operator-script\.sh$|(^|/)operator-bootstrap/template\.sh$|^knowledge-base/' \
     | sort | while IFS= read -r rel; do
         # A call is the name as a command word on a non-comment line; a mention
         # in prose or inside an error string is not one.
         grep -vE '^[[:space:]]*#' "$root/$rel" \
           | grep -qE '(^|[;&|({][[:space:]]*|[[:space:]]\|\|[[:space:]]*|^[[:space:]]+)soleur_op_ack_or_die([[:space:]]|$)' \
           && printf '%s\n' "$rel"
       done
}

g2_arm_rows() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# --- stubs -------------------------------------------------------------------
# Both stubs append one line per call to $STUB_LOG ("curl <argv %q>" /
# "doppler <argv %q>") and a raw "BODY <data>" line for any request body.
make_stubs() { # <dir> <logging:1|0>
  local d="$1" logging="$2"
  mkdir -p "$d"
  assert_fixture_dir "$d"
  cat > "$d/doppler" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_LOGGING:-1}" == 1 ]] && printf 'doppler %s\n' "$(printf '%q ' "$@")" >> "$STUB_LOG"
if [[ "${1:-}" == secrets && "${2:-}" == get ]]; then
  case "${3:-}" in
    OPERATOR_EMAIL) echo "op@example.com" ;;
    SUPABASE_URL|NEXT_PUBLIC_SUPABASE_URL) echo "https://stub.supabase.invalid" ;;
    *) echo "stub-${3:-value}" ;;
  esac
fi
exit 0
STUB
  assert_fixture_dir "$d"
  cat > "$d/curl" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_LOGGING:-1}" == 1 ]] && printf 'curl %s\n' "$(printf '%q ' "$@")" >> "$STUB_LOG"
url="" out="" wfmt="" method="GET" data="" prev=""
for a in "$@"; do
  case "$prev" in
    -o) out="$a" ;; -w) wfmt="$a" ;; -X|--request) method="$a" ;;
    -d|--data|--data-binary|--data-raw) data="$a" ;;
  esac
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
if [[ "$data" == "@-" ]]; then data="$(cat)"; fi
[[ -n "$data" && "${STUB_LOGGING:-1}" == 1 ]] && printf 'BODY %s\n' "$data" >> "$STUB_LOG"
code=200
q="${url#*\?q=}"; q="${q%%&*}"
case "$url" in
  *"/rpc/audit_flag_flip"*) body='"11111111-1111-4111-8111-111111111111"' ;;
  *"/features/?q="*)
    if [[ "$q" == "${STUB_ABSENT_FLAG:-}" ]]; then body='{"results":[]}'
    else body="$(printf '{"results":[{"id":777,"name":"%s","default_enabled":false}]}' "$q")"; fi ;;
  *"/projects/"*"/features/")
    body='{"id":888,"name":"new"}' ;;
  *"/feature-segments/"*) body='{"results":[{"id":555,"segment":101,"priority":1}]}' ;;
  *"/segments/"[0-9]*)
    body='{"id":104,"name":"codex-engine-orgs","rules":[{"type":"ALL","rules":[{"type":"ANY","conditions":[]}],"conditions":[]}]}' ;;
  *"/segments/"*)
    if [[ "$method" == POST ]]; then body='{"id":104,"name":"codex-engine-orgs"}'
    else body='{"results":[{"id":101,"name":"role-prd"},{"id":102,"name":"role-dev"},{"id":103,"name":"org-targeted"},{"id":104,"name":"codex-engine-orgs"}]}'; fi ;;
  *"/featurestates/"*)
    body='[{"id":1,"enabled":false,"feature_segment":null},{"id":2,"enabled":false,"feature_segment":{"id":555,"segment":101}}]' ;;
  *"/versions/"*)
    if [[ "$method" == POST ]]; then body='{"uuid":"v-uuid"}'
    else body='{"results":[{"uuid":"v-uuid","is_live":true}]}'; fi ;;
  *"/identities/"*"/traits/"*) body='{"trait_key":"role","trait_value":"dev"}' ;;
  *"/identities/"*)
    en=false; [[ -n "${STUB_MEMBER_ORG:-}" && "$data" == *"$STUB_MEMBER_ORG"* ]] && en=true
    body="$(printf '{"flags":[{"feature":{"name":"codex-engine"},"enabled":%s}],"traits":[]}' "$en")" ;;
  *"/rest/v1/users"*) body='[{"id":"3b1f4c2a-0000-4000-8000-00000000000a","email":"u@example.com","role":"prd"}]' ;;
  *"/api/0/organizations/"*"/searches/"*) body='[{"id":"2","name":"s","query":"op:tool-label-scrub extra.text:foo"}]' ;;
  *"/api/0/organizations/"*"/dashboards/"*) body='[]' ;;
  *"/api/0/organizations/"*"/discover/saved/"*) body='[]' ;;
  *"/api/0/projects/"*"/rules/"*) body='[]' ;;
  *"/api/0/organizations/"*) body='{"links":{"regionUrl":"https://sentry.io"}}' ;;
  *) body='{}' ;;
esac
if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
if [[ -n "$wfmt" ]]; then w="${wfmt//%\{http_code\}/$code}"; printf '%b' "$w"; fi
exit 0
STUB
  chmod +x "$d/doppler" "$d/curl"
  assert_fixture_dir "$d"
  printf '%s\n' "$logging" > "$d/.logging"
}

# The coreutils the scripts need, DERIVED: every word in the scripts, the
# library and the audit helper that resolves to a binary on the real PATH, minus
# every network-capable binary. A missing tool shows up as `command not found`
# (a failing row), never as a silent pass.
make_tooldir() { # <dir> <files...>
  local d="$1" t p; shift
  mkdir -p "$d"
  while IFS= read -r t; do
    [[ "$t" =~ $NET_BINS ]] && continue
    p="$(type -P "$t" 2>/dev/null)" || continue
    [[ -n "$p" && ! -e "$d/$t" ]] && ln -s "$p" "$d/$t"
  done < <(grep -ohE '[A-Za-z_][A-Za-z0-9_.+-]*' "$@" 2>/dev/null | sort -u)
  # The pty wrapper execs $SHELL; bash is referenced by absolute path below.
  return 0
}

g2_is_mutating_log() { # <log> -> count of mutating calls
  awk '
    /^curl / {
      if ($0 ~ /(^| )(-X|--request) (POST|PUT|PATCH|DELETE)( |$)/) { n++; next }
      if ($0 ~ /(^| )(-d|--data|--data-binary|--data-raw) / && $0 !~ /(-X|--request) GET/) { n++; next }
    }
    /^doppler secrets (set|delete|upload)( |$)/ { n++ }
    END { print n + 0 }
  ' "$1"
}

# Hostile environment (M5): every SOLEUR_* / _SOLEUR_* / *_ACK* name the script or
# the library mentions, set to "yes"; plus an exported no-op ack function, the
# library's load marker, and a pre-set ack state. None may buy a write.
g2_hostile_env() { # <files...> -> NAME=value lines
  local n
  while IFS= read -r n; do
    [[ "$n" == SOLEUR_BOOTSTRAP_LEDGER ]] && continue
    printf '%s=yes\n' "$n"
  done < <(grep -ohE '(^|[^A-Za-z0-9_])(_?SOLEUR_[A-Z0-9_]+|[A-Z0-9_]*_ACK[A-Z0-9_]*)' "$@" 2>/dev/null \
            | sed -E 's/^[^A-Za-z0-9_]//' | sort -u)
  printf '%s\n' '_SOLEUR_OPERATOR_SCRIPT_LOADED=1' 'SOLEUR_OP_ACKED=tty-ack' 'BASH_FUNC_soleur_op_ack_or_die%%=() {  :; }'
}

# g2_seed <root> <scratch> — the repo-relative files the flag scripts read and
# write in place, copied so no run can touch the real tree.
g2_seed() {
  local root="$1" s="$2" f
  for f in apps/web-platform/lib/feature-flags/server.ts apps/web-platform/.env.example \
           plugins/soleur/skills/flag-set-role/scripts/flip.sh; do
    mkdir -p "$s/$(dirname "$f")"
    assert_fixture_dir "$s"
    cp -p "$root/$f" "$s/$f" 2>/dev/null || cp -p "$REPO_ROOT/$f" "$s/$f"
  done
}

# g2_run <root> <rel> <how:notty|pty> <answer> <stubdir> <argv...>
#   -> G2_OUT, G2_RC; the stub log is at $G2_LOG
g2_run() {
  local root="$1" rel="$2" how="$3" answer="$4" stubdir="$5"; shift 5
  local scratch cmd rc logging
  scratch="$(mktemp -d "$SB/run.XXXXXXXX")" || { G2_RC=250; G2_OUT="mktemp failed"; return 0; }
  g2_seed "$root" "$scratch"
  G2_LOG="$scratch/stub.log"; : > "$G2_LOG"
  logging="$(cat "$stubdir/.logging")"
  local -a envv=(
    HOME="$scratch" TERM=dumb SHELL="$BASH_BIN" LC_ALL=C
    PATH="${stubdir}:${TOOLDIR}"
    STUB_LOG="$G2_LOG" STUB_LOGGING="$logging" STUB_ABSENT_FLAG=probe-new-flag
    STUB_MEMBER_ORG=70a70ab0-0000-4000-8000-000000000001
    SOLEUR_BOOTSTRAP_LEDGER="$scratch/ledger.jsonl"
    SENTRY_AUTH_TOKEN=stub-token SENTRY_ORG=stub-org SENTRY_PROJECT=stub-project
    EVAL_POLL_SLEEP=0 EVAL_POLL_TRIES=1
  )
  local line
  while IFS= read -r line; do envv+=("$line"); done < <(g2_hostile_env "$root/$rel" "$root/plugins/soleur/scripts/lib/operator-script.sh")
  if [[ "$how" == notty && "${G2_NOTTY_VIA_PTY:-0}" != 1 ]]; then
    # stdin is a PIPE carrying "yes": the exact shape an agent would use.
    G2_OUT="$( cd "$scratch" && printf '%s' "$answer" \
      | env -i "${envv[@]}" "$TIMEOUT_BIN" 20 "$BASH_BIN" "$root/$rel" "$@" 2>&1 )"
    rc=$?
  else
    printf -v cmd '%q ' "$BASH_BIN" "$root/$rel" "$@"
    # PIPESTATUS[1] is the script(1) run's own status, not tr's.
    G2_OUT="$( cd "$scratch" && printf '%s' "$answer" \
      | env -i "${envv[@]}" "$TIMEOUT_BIN" 20 "$SCRIPT_BIN" -qec "$cmd" /dev/null 2>&1 | tr -d '\r'
      exit "${PIPESTATUS[1]}" )"
    rc=$?
  fi
  G2_RC="$rc"
  G2_SCRATCH="$scratch"
}

# g2_check <root> <arms> <stubdir> [only-script-rel]
g2_check() {
  local root="$1" arms="$2" stubdir="$3" only="${4:-}"
  local v=0 ran=0 script mode argv profile muts pop tabled rel p prefix seen_all=""
  local -a av

  if [[ ! -r "$arms" ]]; then echo "g2: arm table unreadable: $arms"; return 1; fi

  # --- set identity, both ways ------------------------------------------------
  pop="$(g2_population "$root")"
  tabled="$(g2_arm_rows "$arms" | cut -f1 | sort -u)"
  if [[ -z "$pop" ]]; then echo "g2: the ack-caller population is EMPTY — nothing was checked"; return 1; fi
  while IFS= read -r rel; do [[ -n "$rel" ]] && { echo "g2: ${rel} calls soleur_op_ack_or_die but has no row in the arm table"; v=1; }
  done < <(comm -23 <(printf '%s\n' "$pop") <(printf '%s\n' "$tabled"))
  while IFS= read -r rel; do [[ -n "$rel" ]] && { echo "g2: arm table names ${rel}, which does not call soleur_op_ack_or_die"; v=1; }
  done < <(comm -13 <(printf '%s\n' "$pop") <(printf '%s\n' "$tabled"))
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    g2_arm_rows "$arms" | awk -F'\t' -v s="$rel" '$1==s && $2=="write"' | grep -q . \
      || { echo "g2: ${rel} has no write row"; v=1; }
  done <<<"$tabled"

  # --- behavioural rows -----------------------------------------------------
  while IFS=$'\t' read -r script mode argv profile; do
    [[ -n "$script" ]] || continue
    [[ -n "$only" && "$script" != "$only" ]] && continue
    [[ "$profile" == external:* ]] && continue
    [[ -f "$root/$script" ]] || { echo "g2: arm table names missing file ${script}"; v=1; continue; }
    if [[ "$argv" == "-" ]]; then av=(); else read -r -a av <<<"$argv"; fi
    ran=$((ran + 1))
    case "$mode" in
      write)
        g2_run "$root" "$script" notty $'yes\n' "$stubdir" "${av[@]}"
        if [[ "$G2_RC" != 64 ]]; then echo "g2: ${script} ${argv}: piped-yes/no-TTY run exited ${G2_RC}, expected 64: $(tail -3 <<<"$G2_OUT" | tr '\n' ' ')"; v=1; fi
        grep -qF 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED' <<<"$G2_OUT" || { echo "g2: ${script} ${argv}: no-TTY run printed no SOLEUR_BOOTSTRAP_INPUT_REQUIRED"; v=1; }
        if [[ -s "$G2_LOG" ]]; then echo "g2: ${script} ${argv}: no-TTY run made $(grep -cE '^(curl|doppler) ' "$G2_LOG") stub call(s) before refusing: $(head -2 "$G2_LOG" | cut -c1-160 | tr '\n' ' ')"; v=1; fi

        g2_run "$root" "$script" pty $'no\n' "$stubdir" "${av[@]}"
        muts="$(g2_is_mutating_log "$G2_LOG")"
        if [[ "$G2_RC" != 1 ]]; then echo "g2: ${script} ${argv}: pty answered 'no' exited ${G2_RC}, expected 1: $(tail -3 <<<"$G2_OUT" | tr '\n' ' ')"; v=1; fi
        if [[ "$muts" -ne 0 ]]; then echo "g2: ${script} ${argv}: pty answered 'no' made ${muts} mutating call(s)"; v=1; fi
        seen_all+="$G2_OUT"$'\n'

        g2_run "$root" "$script" pty $'yes\n' "$stubdir" "${av[@]}"
        muts="$(g2_is_mutating_log "$G2_LOG")"
        if [[ "$muts" -lt 1 ]]; then echo "g2: ${script} ${argv}: positive control observed 0 mutating calls on a pty answered 'yes' (rc ${G2_RC}): $(tail -4 <<<"$G2_OUT" | tr '\n' ' ')"; v=1; fi
        if [[ "$profile" == flag ]] && ! grep -qF '"p_approval_method":"tty-ack"' "$G2_LOG"; then
          echo "g2: ${script} ${argv}: the WORM body did not carry \"p_approval_method\":\"tty-ack\""; v=1
        fi
        seen_all+="$G2_OUT"$'\n'
        # 2.6: in-place writes keep their mode under the library's umask 077.
        local f
        for f in apps/web-platform/lib/feature-flags/server.ts apps/web-platform/.env.example plugins/soleur/skills/flag-set-role/scripts/flip.sh; do
          if [[ -e "$G2_SCRATCH/$f" && "$(stat -c %a "$G2_SCRATCH/$f")" != "$(stat -c %a "$REPO_ROOT/$f")" ]]; then
            echo "g2: ${script} ${argv}: ${f} mode changed to $(stat -c %a "$G2_SCRATCH/$f") after a yes run"; v=1
          fi
        done
        ;;
      readonly)
        g2_run "$root" "$script" notty '' "$stubdir" "${av[@]}"
        muts="$(g2_is_mutating_log "$G2_LOG")"
        if [[ "$G2_RC" != 0 ]]; then echo "g2: ${script} ${argv}: read-only run without a TTY exited ${G2_RC}, expected 0: $(tail -3 <<<"$G2_OUT" | tr '\n' ' ')"; v=1; fi
        if [[ "$muts" -ne 0 ]]; then echo "g2: ${script} ${argv}: read-only run made ${muts} mutating call(s)"; v=1; fi
        # Guard 3 H3 (escape/parser agreement): the defer hook ALLOWS this row
        # without a PTY wrapper, so the script must treat it as read-only even
        # when a person answers yes — a mode the hook calls read-only must never
        # write, whatever is typed.
        g2_run "$root" "$script" pty $'yes\n' "$stubdir" "${av[@]}"
        muts="$(g2_is_mutating_log "$G2_LOG")"
        if [[ "$muts" -ne 0 ]]; then echo "g2: ${script} ${argv}: a read-only row answered yes on a pty made ${muts} mutating call(s)"; v=1; fi
        ;;
      *) echo "g2: unknown mode '${mode}' for ${script}"; v=1 ;;
    esac
  done < <(g2_arm_rows "$arms")

  if [[ "$ran" -eq 0 ]]; then echo "g2: 0 arms run — nothing was checked"; return 1; fi

  # --- coverage anchor: every ack prompt observed in some pty run -----------
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -n "$only" && "$rel" != "$only" ]] && continue
    g2_arm_rows "$arms" | awk -F'\t' -v s="$rel" '$1==s' | cut -f4 | grep -q '^external:' && continue
    while IFS= read -r p; do
      prefix="$(sed -E 's/^[^"]*soleur_op_ack_or_die[[:space:]]+"//; s/[$"].*$//' <<<"$p")"
      if [[ "${#prefix}" -lt 8 ]]; then echo "g2: ${rel}: ack prompt has no static prefix of 8+ chars: ${p}"; v=1; continue; fi
      grep -qF -- "$prefix" <<<"$seen_all" || { echo "g2: ${rel}: ack prompt '${prefix}' was never observed in any pty run"; v=1; }
    done < <(grep -vE '^[[:space:]]*#' "$root/$rel" | grep -E 'soleur_op_ack_or_die[[:space:]]+"')
  done <<<"$pop"

  echo "g2: ran ${ran} arm row(s)"
  return "$v"
}

echo "== Guard 2 — no mutating call without a person at a TTY =="

STUBS_OK="$SB/stubs/ok"; make_stubs "$STUBS_OK" 1
STUBS_SILENT="$SB/stubs/silent"; make_stubs "$STUBS_SILENT" 0
TOOLDIR="$SB/tools"
mapfile -t _g2_files < <(g2_population "$REPO_ROOT" | sed "s|^|$REPO_ROOT/|")
make_tooldir "$TOOLDIR" "${_g2_files[@]}" "$REPO_ROOT/plugins/soleur/scripts/lib/operator-script.sh" "$REPO_ROOT/plugins/soleur/scripts/audit-flag-flip.sh"

WT_STATUS_BEFORE="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)"

assert_green g2_check "live scripts" "$REPO_ROOT" "$ARMS" "$STUBS_OK"
grep -E '^g2: ' <<<"$G_LAST_OUT" | sed 's/^/    /'

if [[ "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" == "$WT_STATUS_BEFORE" ]]; then
  pass "tree isolation: the real worktree's git status is unchanged by the pty-yes runs"
else
  fail "tree isolation: the pty-yes runs changed the real worktree: $(git -C "$REPO_ROOT" status --porcelain | head -5 | tr '\n' ' ')"
fi

# --- mutation rows run against a MIRROR tree ---------------------------------
# The scripts resolve the library and the audit helper through SCRIPT_DIR, so a
# mutated copy must sit at the same depth beside real copies of both.
MIRROR_PRISTINE="$SB/mirror-pristine"
mk_mirror_pristine() {
  local rel
  mkdir -p "$MIRROR_PRISTINE"
  while IFS= read -r rel; do
    mkdir -p "$MIRROR_PRISTINE/$(dirname "$rel")"; cp -p "$REPO_ROOT/$rel" "$MIRROR_PRISTINE/$rel"
  done < <( { g2_population "$REPO_ROOT"; printf '%s\n' plugins/soleur/scripts/lib/operator-script.sh plugins/soleur/scripts/audit-flag-flip.sh \
              apps/web-platform/lib/feature-flags/server.ts apps/web-platform/.env.example; } | sort -u )
}
mk_mirror_pristine

# g2_mutate <label> <rel> -> sets G2_MIRROR; the perl program is on stdin. Called
# directly, never in $( ), so its pass()/fail() reach the counters.
g2_mutate() {
  local label="$1" rel="$2" prog m
  prog="$(cat)"
  m="$(mktemp -d "$SB/mirror.XXXXXXXX")"
  cp -a "$MIRROR_PRISTINE/." "$m/"
  perl -0777 -pi -e "$prog" "$m/$rel"
  if [[ "$(md5_of "$m/$rel")" == "$(md5_of "$MIRROR_PRISTINE/$rel")" ]]; then
    fail "mutation '${label}' did NOT land (md5 identical) — its row would re-run the baseline"
    return 1
  fi
  if ! bash -n "$m/$rel" 2>/dev/null; then
    fail "mutation '${label}' produced a script that fails bash -n"
    return 1
  fi
  pass "mutation '${label}' landed (md5 differs; bash -n clean)"
  G2_MIRROR="$m"
}

# --- AC14/AC15: the command each skill tells the agent to PRINT works in a real
# terminal. Extracted from the SKILL.md (never retyped here), run on a pty with
# `no` typed: it must reach its own ack prompt and stop with exit 1 before any
# mutating call. -----------------------------------------------------------------
echo "== Guard 2 — the printed operator command reaches its ack =="

g2_run_cmd() { # <root-for-hostile-env-rel> <rel> <answer> <cmd> -> G2_OUT, G2_RC, G2_LOG
  local root="$1" rel="$2" answer="$3" cmd="$4" scratch line rc
  scratch="$(mktemp -d "$SB/cmd.XXXXXXXX")" || { G2_RC=250; G2_OUT="mktemp failed"; return 0; }
  G2_LOG="$scratch/stub.log"; : > "$G2_LOG"
  local -a envv=(
    HOME="$scratch" TERM=dumb SHELL="$BASH_BIN" LC_ALL=C
    PATH="${STUBS_OK}:${TOOLDIR}"
    STUB_LOG="$G2_LOG" STUB_LOGGING=1 STUB_ABSENT_FLAG=probe-new-flag
    STUB_MEMBER_ORG=70a70ab0-0000-4000-8000-000000000001
    SOLEUR_BOOTSTRAP_LEDGER="$scratch/ledger.jsonl"
    SENTRY_AUTH_TOKEN=stub-token SENTRY_ORG=stub-org SENTRY_PROJECT=stub-project
    EVAL_POLL_SLEEP=0 EVAL_POLL_TRIES=1
  )
  while IFS= read -r line; do envv+=("$line"); done < <(g2_hostile_env "$root/$rel" "$root/plugins/soleur/scripts/lib/operator-script.sh")
  G2_OUT="$( cd "$scratch" && printf '%s' "$answer" \
    | env -i "${envv[@]}" "$TIMEOUT_BIN" 20 "$SCRIPT_BIN" -qec "$cmd" /dev/null 2>&1 | tr -d '\r'
    exit "${PIPESTATUS[1]}" )"
  rc=$?
  G2_RC="$rc"
}

for skill in flag-create flag-delete flag-set-role user-set-role; do
  md="$REPO_ROOT/plugins/soleur/skills/$skill/SKILL.md"
  tmpl="$(awk '/<!-- operator-write-command -->/{f=1; next} f && /^```bash/{g=1; next} g && /^```/{exit} g{print}' "$md")"
  if [[ "$tmpl" != "cd <WORKTREE> && bash <WORKTREE>/"* ]]; then
    fail "AC14 ${skill}: the marked operator command is missing or does not start with 'cd <WORKTREE> && bash <WORKTREE>/': ${tmpl:0:120}"
    continue
  fi
  pass "AC14 ${skill}: the printed command is worktree-pinned (cd <absolute path> && …)"
  rel="${tmpl#cd <WORKTREE> && bash <WORKTREE>/}"; rel="${rel%% *}"
  argv="$(awk -F'\t' -v s="$rel" '$1==s && $2=="write" {print $3; exit}' "$ARMS")"
  prefix="$(grep -vE '^[[:space:]]*#' "$REPO_ROOT/$rel" | grep -E 'soleur_op_ack_or_die[[:space:]]+"' | head -1 \
            | sed -E 's/^[^"]*soleur_op_ack_or_die[[:space:]]+"//; s/[$"].*$//')"
  cmd="${tmpl//<WORKTREE>/$MIRROR_PRISTINE}"; cmd="${cmd//<ARGS>/$argv}"
  g2_run_cmd "$MIRROR_PRISTINE" "$rel" $'no\n' "$cmd"
  muts="$(g2_is_mutating_log "$G2_LOG")"
  if [[ "$G2_RC" == 1 && "$muts" -eq 0 ]] && grep -qF -- "$prefix" <<<"$G2_OUT"; then
    pass "AC14 ${skill}: run on a pty answered 'no', it reached '${prefix}' and exited 1 with 0 mutating calls"
  else
    fail "AC14 ${skill}: rc ${G2_RC}, ${muts} mutating call(s), prompt '${prefix}' seen: $(grep -cF -- "$prefix" <<<"$G2_OUT") — $(tail -3 <<<"$G2_OUT" | tr '\n' ' ')"
  fi
  if grep -qF 'wg-block-pr-ready-on-undeferred-operator-steps' "$md"; then
    pass "AC15 ${skill}: names the handoff as a blocking operator step"
  else
    fail "AC15 ${skill}: does not name wg-block-pr-ready-on-undeferred-operator-steps"
  fi
done

fsr="$REPO_ROOT/plugins/soleur/skills/flag-set-role/SKILL.md"
if awk '/^## Incident rollback/{f=1} f' "$fsr" | grep -q 'own terminal' \
   && awk '/^## Incident rollback/{f=1} f' "$fsr" | grep -qE "not through Claude Code's .!. prefix|Not through Claude Code's .!." \
   && awk '/^## Incident rollback/{f=1} f' "$fsr" | grep -q 'Flagsmith dashboard'; then
  pass "AC15 flag-set-role: incident-rollback block (own terminal, not the ! prefix, dashboard break-glass on exit 4)"
else
  fail "AC15 flag-set-role: the incident-rollback block is missing or incomplete"
fi

CREATE_REL="plugins/soleur/skills/flag-create/scripts/create.sh"
SETROLE_REL="plugins/soleur/skills/user-set-role/scripts/set-role.sh"

assert_green g2_check "mirror control: pristine copies, flip.sh rows" "$MIRROR_PRISTINE" "$ARMS" "$STUBS_OK" "$FLIP_REL"

# M1 — delete the early precheck from create.sh
if g2_mutate "g2-M1 create.sh early precheck removed" "$CREATE_REL" <<'PROG'
s{\[\[ -t 0 \]\] \|\| soleur_op_input_required "destructive-write-ack\(no-skip-variable-by-design\)" ack}{:}
PROG
then assert_red g2_check "g2-M1 no-TTY run reaches Doppler/curl before refusing" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$CREATE_REL"; reason "g2-M1" "no-TTY run made [0-9]+ stub call"; fi

# M2 — delete the ack from flip.sh's gate (precheck kept)
if g2_mutate "g2-M2 flip.sh gate ack removed" "$FLIP_REL" <<'PROG'
s{(gate_or_confirm\(\) \{.*?)\n[ \t]*soleur_op_ack_or_die "[^\n]*\n}{$1\n}s
PROG
then assert_red g2_check "g2-M2 pty 'no' is not refused by flip.sh" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$FLIP_REL"; reason "g2-M2" "pty answered .no. (exited|made)"; fi

# M3 — REORDER: delete.sh's ack moved after the first Flagsmith DELETE
if g2_mutate "g2-M3 delete.sh ack moved after the first DELETE" "$DELETE_REL" <<'PROG'
s{\n(soleur_op_ack_or_die "[^\n]*\n)}{\n}; my $ack=$1; s{(\n[^\n]*-X DELETE[^\n]*\n)}{$1$ack}
PROG
then assert_red g2_check "g2-M3 a write or an audit append precedes the ack" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$DELETE_REL"; reason "g2-M3" "pty answered .no. (exited [^1]|made)"; fi

# M4 — a second ack caller with no arm-table row
m="$(mktemp -d "$SB/mirror.XXXXXXXX")"; cp -a "$MIRROR_PRISTINE/." "$m/"
printf '#!/usr/bin/env bash\nsoleur_op_ack_or_die "Rotate everything now? Type yes: "\n' > "$m/apps/web-platform/scripts/new-ack-caller.sh"
assert_red g2_check "g2-M4 new ack caller with no arm row (set identity)" "$m" "$ARMS" "$STUBS_OK" "$CREATE_REL"
reason "g2-M4" "new-ack-caller.sh calls soleur_op_ack_or_die but has no row"

# M5 — an env skip added in front of both checks in set-role.sh
if g2_mutate "g2-M5 set-role.sh SOLEUR_ACK env skip" "$SETROLE_REL" <<'PROG'
s{\[\[ -t 0 \]\] \|\| soleur_op_input_required}{[[ -n "\${SOLEUR_ACK:-}" ]] || [[ -t 0 ]] || soleur_op_input_required}g; s{\nsoleur_op_ack_or_die }{\n[[ -n "\${SOLEUR_ACK:-}" ]] || soleur_op_ack_or_die }g
PROG
then assert_red g2_check "g2-M5 SOLEUR_ACK=yes in the environment buys a no-TTY write" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$SETROLE_REL"; reason "g2-M5" "no-TTY run made [0-9]+ stub call"; fi

# M5b — flip.sh's audit append moved above its ack (role path)
if g2_mutate "g2-M5b flip.sh audit append above the ack" "$FLIP_REL" <<'PROG'
s{\ngate_or_confirm\n(.*?)(audit_append "role:[^\n]*\n)}{\n$1$2gate_or_confirm\n}s
PROG
then assert_red g2_check "g2-M5b audit append before the ack exits 4, not 1" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$FLIP_REL"; reason "g2-M5b" "pty answered .no. exited 4"; fi

# M6 — own dispatch: an arm table with no rows
printf '# empty\n' > "$SB/arms-empty.tsv"
assert_red g2_check "g2-M6 empty arm table" "$MIRROR_PRISTINE" "$SB/arms-empty.tsv" "$STUBS_OK"
reason "g2-M6" "0 arms run|has no row in the arm table"
assert_red g2_check "g2-M6b unreadable arm table" "$MIRROR_PRISTINE" "$SB/no-such-arms.tsv" "$STUBS_OK"
reason "g2-M6b" "arm table unreadable"

# M7 — an ack prompt no arm reaches
if g2_mutate "g2-M7 unreachable ack prompt in flip.sh" "$FLIP_REL" <<'PROG'
s{\z}{\nnever_called_gate() {\n  soleur_op_ack_or_die "Unreachable production rewrite? Type yes: "\n}\n}
PROG
then assert_red g2_check "g2-M7 coverage anchor: a prompt never observed" "$G2_MIRROR" "$ARMS" "$STUBS_OK" "$FLIP_REL"; reason "g2-M7" "Unreachable production rewrite.*was never observed"; fi

# H1 — the curl/doppler stubs stop logging: the positive control must fail
assert_red g2_check "g2-H1 non-logging stubs (positive control reads the log)" "$MIRROR_PRISTINE" "$ARMS" "$STUBS_SILENT" "$SETROLE_REL"
reason "g2-H1" "positive control observed 0 mutating calls"
# H2 — the no-TTY arms run on a pty instead: the exit-64 assertion must fail
G2_NOTTY_VIA_PTY=1
assert_red g2_check "g2-H2 no-TTY arms driven through a pty" "$MIRROR_PRISTINE" "$ARMS" "$STUBS_OK" "$SETROLE_REL"
reason "g2-H2" "expected 64"
G2_NOTTY_VIA_PTY=0

# --- Anti-vacuity floor ------------------------------------------------------
# REPORTS DIRECTLY (printf + exit 1), never through pass()/fail() (ADR-193).
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
FLOOR=62
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi

echo "Total: $((PASS_COUNT + FAIL_COUNT)) assertions, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
