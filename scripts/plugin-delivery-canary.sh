#!/usr/bin/env bash
# Guard 1 — fresh-install delivery canary for the published `soleur` plugin (#7490).
#
# WHY THIS EXISTS. The plugin is published out of this monorepo's `plugins/soleur`
# subtree through a separate marketplace repo. A previous defect delivered 64
# skill directories where 96 were expected — an UNDER-DELIVERY — while every
# metadata field on the install read correct. That is the failure shape every
# cheap check is blind to: `claude plugin list` was right, the recorded version
# was right, the recorded commit was right, and the bytes on disk were wrong.
# So the only honest question is whether a FRESH install materialises the
# complete, correct, current content, and the only honest way to ask it is to
# perform the install and compare what landed against what the repo serves.
#
# THREE CONJUNCTS, QUANTIFIED SEPARATELY. The property has three independent
# halves and this script evaluates each one on its own axis, because a guard that
# collapses them passes on the failure the other two would have caught:
#
#   COMPLETENESS — the delivered file list compared AS A SET against the list the
#     repo serves at the delivered commit, with an explicit cardinality
#     assertion. Never a hand-declared subset: the historical defect was
#     under-delivery, and a subset comparison is STRUCTURALLY blind to it — every
#     member of the subset can be present and byte-perfect while a third of the
#     tree is missing. The reference listing is the unauthenticated GitHub trees
#     API. When that listing is unavailable, rate-limited, or TRUNCATED, the
#     conjunct is declared UNAVAILABLE (`reference_unreadable`) and the run fails
#     closed. Silently downgrading to "compare what we could see" is the same
#     blindness wearing a different hat.
#
#   INTEGRITY — every delivered file's digest against the digest of the same path
#     fetched from raw.githubusercontent, PINNED TO THE DELIVERED COMMIT rather
#     than to `main`. The pin is not a nicety: a merge landing mid-run would
#     otherwise move the reference under the comparison and manufacture a
#     mismatch on files nobody touched.
#
#   FRESHNESS — the delivered commit EQUALS `main` HEAD. No tolerance window: a
#     tolerance that is never stated cannot be tested, and "roughly current" is
#     not a property. The one sanctioned exception is a merge landing between the
#     install and the read; that is detected by re-reading `main` HEAD once and
#     reported as a DISTINCT, non-alarming outcome rather than as staleness.
#
# THE METADATA BOUNDARY IS OVER FIELDS, NOT FILES. `claude plugin list --json` is
# a projection of `installed_plugins.json`, so reading the CLI does not escape
# the metadata — it just launders it. `installPath` is consumed here as a
# LOCATION and `gitCommitSha` as the reference PIN, which are both statements
# about WHERE to look. Neither `version` nor `gitCommitSha` is ever allowed to
# stand in for a content comparison. That matters concretely: the recorded
# version is a compound like `0d6443960662-31fddb37` whose 8-char half is
# CONSTANT across different delivered commits, so it identifies nothing about
# content and a verdict satisfied by it is a verdict satisfied by noise.
#
# `compared=` AND `expected=` ARE BOTH PRINTED, ALWAYS, and disagreement is a
# failure — as is `compared=0`. Without that pairing, a run that compared nothing
# at all reports "no differences found", which is the single most dangerous
# sentence a verification script can emit.
#
# STDOUT IS A CONTRACT, consumed by the `canary` job in
# .github/workflows/scheduled-marketplace-drift.yml. Exactly two line families
# are emitted on stdout:
#
#   canary-finding| <token>: <detail>      one line per finding, or, when there
#                                          are none, the single line
#                                          `canary-finding| every delivery
#                                          assertion holds at <sha>`
#   canary-counts|  compared=<N> expected=<M>
#
# Everything else — conjunct breakdown, verdict, mid-run-merge note — goes to
# STDERR, which that workflow discards. Every interpolated value is passed
# through `sanitize` first, with the same three rules as the sibling `check`
# step: control characters deleted, the `##[` workflow-command prefix rewritten,
# length bounded. Those bytes arrive from a FETCHED REFERENCE, so they are
# untrusted; a raw newline in a path would forge an extra finding line and a raw
# `##[` would forge a workflow command.
#
# THE SEAM. Every acquisition step (install, reference listing, reference fetch,
# `main` HEAD) is injectable through a `CANARY_*` environment variable, so the
# assertion logic can be driven against a local fixture tree with NO network and
# NO credentials. `scripts/plugin-delivery-canary.test.sh` and `--self-test` both
# drive THIS script through that seam rather than re-implementing its logic in a
# heredoc — a battery whose fixture re-declares the good idiom only asserts that
# a known-good snippet is known-good.
#
# Exit codes: 0 = the property holds (or `main` moved mid-run). 1 = at least one
# finding. 2 = the canary could not run at all.

# A DIRECT invocation would otherwise inherit the bare /tmp tmpfs, and this
# script materialises a whole plugin tree plus a scratch HOME into it; a
# full-tmpfs sandbox turns setup failures into confident wrong verdicts rather
# than missing ones. Mirrors scripts/test-all.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

# ---------------------------------------------------------------------------
# Fixed facts about the delivery path. These are the thing under test, not
# configuration — an operator who needs to change one of them is changing what
# the canary is a canary FOR.
# ---------------------------------------------------------------------------
REPO="jikig-ai/soleur"
MARKETPLACE_REPO="jikig-ai/soleur-marketplace"
PLUGIN_ID="soleur@soleur-marketplace"
PLUGIN_SUBDIR="plugins/soleur"

# Hard cap on the inherent delivered-vs-tracked delta. A scratch install
# materialised 891 files against 894 tracked, so a small delta exists. It is NOT
# pre-forgiven here: the exclusion list below ships EMPTY, so the delta surfaces
# as `incomplete_delivery` with each path named, and a path is only ever excused
# after it has been individually identified and justified. A blanket allowance
# sized to swallow an unattributed delta is exactly the under-delivery blindness
# this guard exists to prevent — 32 missing skill directories would fit inside a
# generous one. The cap is asserted whether or not the list is populated.
EXCLUSION_CAP=4
DEFAULT_EXCLUSIONS=(
  # MEASURED on a live run, and the only entry that has earned its place so far.
  # The CLI writes a lock directory INTO the install path — an observed member was
  # `.in_use/143463`, the name being a pid. It is runtime bookkeeping owned by the
  # CLI, not content the repository serves, so it appears in the delivered tree and
  # can never appear in the reference. Excluding it is not forgiving a delta: it is
  # declining to compare a file that is not part of the artefact under test.
  #
  # Note the DIRECTION. This is delivered-MORE. The 891-vs-894 delivered-FEWER
  # delta noted above is a different question and stays unattributed, so it will
  # still surface as `incomplete_delivery` with each path named. Excusing an extra
  # file says nothing about a missing one, and conflating the two is how a missing
  # skill directory would get waved through.
  '.in_use/*'
)

# ---------------------------------------------------------------------------
# THE HERMETIC SEAM. Each of these replaces exactly one ACQUISITION step. None
# of them replaces any part of the assertion logic — that is the whole point:
# the fixture supplies the inputs, the script under test supplies the verdict.
# ---------------------------------------------------------------------------
DELIVERED_ROOT="${CANARY_DELIVERED_ROOT:-}"          # skip the install; treat this dir as delivered
DELIVERED_SHA="${CANARY_DELIVERED_SHA:-}"            # the commit the install resolved (the reference PIN)
REFERENCE_DIR="${CANARY_REFERENCE_DIR:-}"            # serve listing + file bodies from here instead of GitHub
MAIN_HEAD="${CANARY_MAIN_HEAD:-}"                    # `main` HEAD, first read
MAIN_HEAD_RECHECK="${CANARY_MAIN_HEAD_RECHECK:-}"    # `main` HEAD, second read (mid-run-merge detection)
INSTALLED_PLUGINS="${CANARY_INSTALLED_PLUGINS:-}"    # read this installed_plugins.json instead of installing
CLI="${CANARY_CLI:-claude}"                          # the CLI binary to install with
EXCLUDE_RAW="${CANARY_EXCLUDE:-}"                    # colon-separated extra exclusion globs

SELF_TEST=0
KEEP_SCRATCH=0

usage() {
  cat <<'USAGE'
Usage: plugin-delivery-canary.sh [options]

  --self-test          Exercise the assertion logic against a synthesized
                       fixture with no network and no credentials, then exit
  --keep-scratch       Do not delete the scratch HOME / temp files
  -h, --help           This message

Hermetic seam (environment):
  CANARY_DELIVERED_ROOT      directory to treat as the delivered plugin tree
  CANARY_DELIVERED_SHA       delivered commit (used as the raw.githubusercontent pin)
  CANARY_REFERENCE_DIR       directory serving the reference listing and bodies
  CANARY_MAIN_HEAD           `main` HEAD, first read
  CANARY_MAIN_HEAD_RECHECK   `main` HEAD, second read
  CANARY_INSTALLED_PLUGINS   installed_plugins.json to read instead of installing
  CANARY_CLI                 CLI binary used for the install
  CANARY_EXCLUDE             colon-separated extra exclusion globs
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    --keep-scratch) KEEP_SCRATCH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }

# sha256 spelling differs between Linux and macOS; resolve once so the loop below
# is not re-deciding per file.
if command -v sha256sum >/dev/null 2>&1; then
  DIGEST_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  DIGEST_CMD=(shasum -a 256)
else
  echo "FATAL: no sha256 tool (sha256sum or shasum) available" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Finding accumulation. Findings are DATA: the loop never stops at the first
# one, because "the second file is corrupt" and "files two through forty are
# corrupt" are different diagnoses and only a full sweep can tell them apart.
# ---------------------------------------------------------------------------
FINDING_COUNT=0

# Applied to EVERY value that reaches a `canary-finding|` line. Deletes NUL and
# control characters — which is also what stops a path fetched from the
# reference from forging a second finding line, and the consumer counts findings
# by counting lines — rewrites the `##[` workflow-command prefix to a fixed
# point, and bounds the length so one long path cannot bury the rest.
sanitize() {
  printf '%s' "${1-}" | LC_ALL=C tr -d '\000-\037\177' \
    | sed -E ':a; s/##\[/#-[/g; ta' | cut -c1-200
}

finding() { # <token> <detail...>
  local token="$1"; shift
  FINDING_COUNT=$((FINDING_COUNT + 1))
  printf 'canary-finding| %s: %s\n' "$token" "$(sanitize "$*")"
}

# The full vocabulary, listed so a reader can see the closed set without
# grepping the control flow: content_mismatch, incomplete_delivery,
# stale_delivery, install_failed, installpath_unresolved, reference_unreadable,
# cli_unavailable.

SCRATCH=""
cleanup() {
  [[ "$KEEP_SCRATCH" -eq 1 ]] && return 0
  [[ -n "$SCRATCH" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
  return 0
}
trap cleanup EXIT

mkscratch() {
  SCRATCH="$(mktemp -d "${TMPDIR}/delivery-canary.XXXXXXXX")" || {
    echo "FATAL: mktemp failed — cannot build the canary sandbox" >&2
    exit 2
  }
}

# ---------------------------------------------------------------------------
# Digests. A symlink is digested over its TARGET TEXT rather than followed,
# because that is what the repository stores for a mode-120000 blob: following
# it would compare the linked file's bytes against the link's bytes and report a
# mismatch on a tree that is correct. `plugins/soleur` tracks four such entries.
# ---------------------------------------------------------------------------
digest_path() { # <path>
  if [[ -L "$1" ]]; then
    printf '%s' "$(readlink -- "$1")" | "${DIGEST_CMD[@]}" | awk '{print $1}'
  else
    "${DIGEST_CMD[@]}" -- "$1" | awk '{print $1}'
  fi
}

# list_tree <root> — relative paths of every file AND symlink, LC_ALL=C sorted.
# Symlinks are listed as members in their own right for the same reason they are
# digested as text: the repository serves them as blobs, so omitting them would
# make the delivered set smaller than the reference set for no real reason.
list_tree() { # <root>
  ( cd "$1" && find . \( -type f -o -type l \) -print 2>/dev/null \
      | sed 's|^\./||' | LC_ALL=C sort )
}

# ---------------------------------------------------------------------------
# Body classification. raw.githubusercontent answers a missing path with an HTML
# error document, and a truncated or refused response can arrive as an empty
# body. Either one, compared naively, yields "the reference differs" at best and
# "nothing to compare, therefore no differences" at worst. Both are classified
# here so they can be reported as `reference_unreadable` — a transport failure,
# not a content verdict.
#
# EMPTINESS IS NOT UNCONDITIONALLY SUSPECT. `plugins/soleur` tracks four
# genuinely zero-byte files (.gitkeep / .nojekyll markers and an intentionally
# empty fixture diff). So an empty reference body is a transport symptom only
# when the delivered counterpart is NOT empty; when both are empty they agree,
# and calling that unreadable would alarm on every single run.
# ---------------------------------------------------------------------------
classify_body() { # <file> -> empty | html | bytes
  if [[ ! -s "$1" ]]; then
    printf 'empty\n'; return 0
  fi
  local sniff
  sniff="$(head -c 512 -- "$1" | tr -d '\r\n\t ' | cut -c1-16)"
  case "$sniff" in
    '<!DOCTYPE'*|'<!doctype'*|'<html'*|'<HTML'*|'<?xmlversion'*'<html'*) printf 'html\n' ;;
    *) printf 'bytes\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Reference acquisition. Two transports, one contract: the listing either
# arrives COMPLETE or the conjunct is declared unavailable.
# ---------------------------------------------------------------------------

# reference_list <outfile> -> 0 on success, 1 when the listing is unusable
# Materialize the whole reference tree in ONE request, at the pinned commit.
#
# WHY, MEASURED. The first live run fetched every file individually from
# raw.githubusercontent — ~890 sequential requests for this plugin. It had not
# finished after 30 minutes against a job budget of 15, and it produced
# intermittent `reference_unreadable` findings on files that fetch fine in
# isolation (verified: the named file returns HTTP 200, and ten rapid fetches of
# it all succeed). So the per-file transport fails in two ways at once — too slow
# to complete, and flaky enough to raise findings about the channel that are
# really findings about the canary. A daily alarm that cries wolf is worse than
# no alarm, because it trains the operator to ignore the one signal this adds.
#
# One archive at the same pinned SHA collapses that to a single request, and the
# extracted tree then flows through the LOCAL reference path — the branch the
# battery already covers — so this changes the transport without changing the
# comparison logic or what any conjunct means.
# THREE TRANSPORTS WERE MEASURED. Only the third is viable, and the two that are
# not are recorded here so nobody re-derives them:
#
#   * Per-file over raw.githubusercontent: ~890 sequential requests. Unfinished
#     after 30 min against a 15 min job budget, with intermittent failures on
#     files that return 200 in isolation.
#   * Whole-repo tarball from codeload: timed out at 300 s having received only
#     28 MB of a ~181 MiB archive. Worse than what it replaced.
#   * `git archive` from the checkout this job already has: no network at all,
#     and exact.
#
# WHAT THIS CHANGES ABOUT THE ASSERTION, STATED PLAINLY. The reference now comes
# from the repository's own git objects at the delivered commit rather than from
# what a CDN serves for that commit. Content-wise those are the same thing — a
# commit sha is a content address, so a tree that hashes to it cannot differ —
# and it is what the integrity conjunct actually means: delivered bytes equal the
# repo's bytes at the commit the install resolved. What it no longer covers is a
# CDN that serves something other than git for the same sha, which was never this
# guard's threat model; the delivery path it watches is the CLI's clone, and that
# reads git too.
materialize_reference() { # <sha> -> prints the plugin subdir on success
  local sha="$1" dest="$SCRATCH/reference" root
  command -v git >/dev/null 2>&1 || return 1
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$root" ]] || return 1

  # The delivered commit is usually `main` HEAD, which a default checkout has.
  # It is NOT guaranteed: a stale delivery resolves to an older commit, and a
  # shallow checkout will not carry it. Fetch it rather than failing, so the
  # freshness conjunct can still report staleness instead of the whole run
  # collapsing into `reference_unreadable` — which would report the canary as
  # broken in exactly the case it is supposed to catch.
  if ! git -C "$root" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    git -C "$root" fetch --depth 1 origin "$sha" >/dev/null 2>&1 || return 1
  fi

  mkdir -p "$dest" || return 1
  git -C "$root" archive "$sha" -- "$PLUGIN_SUBDIR" 2>/dev/null | tar -x -C "$dest" 2>/dev/null || return 1
  [[ -d "$dest/${PLUGIN_SUBDIR}" ]] || return 1
  printf '%s' "$dest/${PLUGIN_SUBDIR}"
}

reference_list() {
  local out="$1"

  # Network mode: materialize once, then fall through to the local branch below.
  # Assigning REFERENCE_DIR here is safe because this function is CALLED
  # DIRECTLY, not in a command substitution — inside `$( )` the assignment would
  # happen in a subshell and be silently discarded, leaving every later
  # reference_fetch back on the per-file transport this exists to replace.
  if [[ -z "$REFERENCE_DIR" ]]; then
    local materialized
    if materialized="$(materialize_reference "$DELIVERED_SHA")" && [[ -n "$materialized" ]]; then
      REFERENCE_DIR="$materialized"
    fi
  fi

  if [[ -n "$REFERENCE_DIR" ]]; then
    [[ -d "$REFERENCE_DIR" ]] || return 1
    list_tree "$REFERENCE_DIR" > "$out" || return 1
    return 0
  fi

  local body="$SCRATCH/trees.json" code
  code="$(curl -sS -o "$body" -w '%{http_code}' \
    "https://api.github.com/repos/${REPO}/git/trees/${DELIVERED_SHA}?recursive=1" 2>/dev/null || true)"
  [[ "$code" == "200" ]] || return 1

  # A TRUNCATED tree is the dangerous response: it is valid JSON, it parses, and
  # it lists FEWER paths than exist. Consuming it would hand the completeness
  # conjunct a short reference list and every missing file would read as
  # "correctly absent" — the under-delivery defect, re-created inside the guard.
  local truncated
  truncated="$(jq -r '.truncated // false' -- "$body" 2>/dev/null || echo "true")"
  [[ "$truncated" == "false" ]] || return 1

  jq -r --arg p "${PLUGIN_SUBDIR}/" '
    (.tree // [])[]
    | select(.type == "blob")
    | select(.path | startswith($p))
    | .path[($p | length):]
  ' -- "$body" 2>/dev/null | LC_ALL=C sort > "$out" || return 1

  [[ -s "$out" ]] || return 1
  return 0
}

# reference_fetch <relpath> <outfile> -> prints transport | empty | html | bytes
reference_fetch() {
  local rel="$1" out="$2"
  : > "$out"
  if [[ -n "$REFERENCE_DIR" ]]; then
    local src="$REFERENCE_DIR/$rel"
    if [[ -L "$src" ]]; then
      printf '%s' "$(readlink -- "$src")" > "$out" || { printf 'transport\n'; return 0; }
    elif [[ -f "$src" ]]; then
      cp -- "$src" "$out" || { printf 'transport\n'; return 0; }
    else
      printf 'transport\n'; return 0
    fi
  else
    # PINNED TO THE DELIVERED COMMIT, never to `main`. See the header: an
    # unpinned reference makes a mid-run merge look like corruption.
    local code
    code="$(curl -sS -o "$out" -w '%{http_code}' \
      "https://raw.githubusercontent.com/${REPO}/${DELIVERED_SHA}/${PLUGIN_SUBDIR}/${rel}" 2>/dev/null || true)"
    [[ "$code" == "200" ]] || { printf 'transport\n'; return 0; }
  fi
  classify_body "$out"
}

# read_main_head <which> -> prints a sha, or nothing when unreadable
read_main_head() { # <first|recheck>
  if [[ "$1" == "first" && -n "$MAIN_HEAD" ]]; then printf '%s\n' "$MAIN_HEAD"; return 0; fi
  if [[ "$1" == "recheck" && -n "$MAIN_HEAD_RECHECK" ]]; then printf '%s\n' "$MAIN_HEAD_RECHECK"; return 0; fi
  # An injected first read with no injected recheck means the fixture is
  # asserting a STABLE head; re-reading the network there would make the fixture
  # depend on the network it was written to avoid.
  if [[ -n "$MAIN_HEAD" ]]; then printf '%s\n' "$MAIN_HEAD"; return 0; fi

  local body="$SCRATCH/head-$1.json" code
  code="$(curl -sS -o "$body" -w '%{http_code}' \
    "https://api.github.com/repos/${REPO}/commits/main" 2>/dev/null || true)"
  [[ "$code" == "200" ]] || return 0
  jq -r '.sha // empty' -- "$body" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Acquisition: perform the fresh install, or consume an injected fixture.
# Sets DELIVERED_ROOT and DELIVERED_SHA, or emits a finding and returns 1.
# ---------------------------------------------------------------------------
resolve_from_installed_plugins() { # <installed_plugins.json>
  local file="$1" line
  [[ -r "$file" ]] || { finding installpath_unresolved "installed_plugins.json unreadable at $file"; return 1; }

  # MEASURED SHAPE: `.plugins["<name>@<alias>"]` is an ARRAY of records, not one
  # object. Reading it as a single object silently sees only the first install.
  # The object spelling is accepted too so a differently-versioned CLI does not
  # crash the canary.
  line="$(jq -r --arg k "$PLUGIN_ID" '
    (.plugins[$k] // empty)
    | (if type == "array" then . elif type == "object" then [.] else [] end)
    | map(select(((.installPath // "") | length) > 0))
    | (first // empty)
    | "\(.installPath)\t\(.gitCommitSha // "")"
  ' -- "$file" 2>/dev/null || true)"

  if [[ -z "$line" ]]; then
    finding installpath_unresolved "no install record with an installPath for ${PLUGIN_ID} in $file"
    return 1
  fi

  DELIVERED_ROOT="${line%%$'\t'*}"
  local sha="${line#*$'\t'}"
  # `gitCommitSha` is consumed here ONLY as the reference PIN — a statement about
  # WHERE to fetch the reference from. It is never compared against itself to
  # decide whether the content is right.
  [[ -n "$DELIVERED_SHA" ]] || DELIVERED_SHA="$sha"

  if [[ ! -d "$DELIVERED_ROOT" ]]; then
    finding installpath_unresolved "installPath '$DELIVERED_ROOT' is not a directory"
    return 1
  fi
  return 0
}

perform_install() {
  if ! command -v "$CLI" >/dev/null 2>&1; then
    finding cli_unavailable "'$CLI' is not on PATH; a fresh install cannot be performed"
    return 1
  fi

  local home="$SCRATCH/home"
  mkdir -p "$home" || { echo "FATAL: mkdir failed under $SCRATCH" >&2; exit 2; }

  # MEASURED: the whole sequence runs FULLY UNAUTHENTICATED. The auth variables
  # are cleared rather than merely left unset so that a canary run inheriting an
  # operator's session cannot pass for a reason a customer's machine would not
  # share. PREFER_HTTPS skips the SSH attempt the CLI makes first — on a runner
  # with no key that attempt is a pure delay before the same HTTPS fallback.
  # ORDER IS LOAD-BEARING: every `-u` must precede the first NAME=VALUE operand.
  # `env` stops parsing options at the first non-option argument, so with the
  # assignments first it treats `-u` as the COMMAND TO RUN and dies with
  # `env: '-u': No such file or directory` before the CLI is ever invoked. That
  # failure surfaced as `install_failed`, which reads exactly like a broken
  # delivery channel — the canary would have blamed the thing it was watching for
  # a defect in its own invocation. Only a live run catches it: the hermetic
  # fixtures stub the CLI, so nothing there executes this array.
  local -a env_wrap=(
    env
    -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN
    "HOME=$home"
    "CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1"
  )

  if ! "${env_wrap[@]}" "$CLI" plugin marketplace add "$MARKETPLACE_REPO" >"$SCRATCH/add.log" 2>&1; then
    finding install_failed "marketplace add ${MARKETPLACE_REPO} failed; see $SCRATCH/add.log"
    return 1
  fi
  if ! "${env_wrap[@]}" "$CLI" plugin install "$PLUGIN_ID" --scope user >"$SCRATCH/install.log" 2>&1; then
    finding install_failed "plugin install ${PLUGIN_ID} failed; see $SCRATCH/install.log"
    return 1
  fi

  resolve_from_installed_plugins "$home/.claude/plugins/installed_plugins.json"
}

acquire() {
  if [[ -n "$INSTALLED_PLUGINS" ]]; then
    resolve_from_installed_plugins "$INSTALLED_PLUGINS"
    return $?
  fi
  if [[ -n "$DELIVERED_ROOT" ]]; then
    if [[ ! -d "$DELIVERED_ROOT" ]]; then
      finding installpath_unresolved "CANARY_DELIVERED_ROOT '$DELIVERED_ROOT' is not a directory"
      return 1
    fi
    return 0
  fi
  perform_install
}

# ---------------------------------------------------------------------------
# Exclusions. Every excluded path must match a DECLARED glob, and the number of
# paths excused is capped. Both halves matter: an unbounded list excuses an
# arbitrary amount of under-delivery, and an uncapped one excuses an arbitrary
# amount per glob.
# ---------------------------------------------------------------------------
EXCLUSIONS=()
load_exclusions() {
  EXCLUSIONS=(${DEFAULT_EXCLUSIONS[@]+"${DEFAULT_EXCLUSIONS[@]}"})
  if [[ -n "$EXCLUDE_RAW" ]]; then
    local IFS=':' g
    for g in $EXCLUDE_RAW; do
      [[ -n "$g" ]] && EXCLUSIONS+=("$g")
    done
  fi
}

is_excluded() { # <relpath>
  local p="$1" g
  for g in ${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}; do
    # shellcheck disable=SC2053 — glob match is the intent, not string equality.
    [[ "$p" == $g ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# THE THREE CONJUNCTS.
# ---------------------------------------------------------------------------
COMPARED=0
EXPECTED=0
COMPLETENESS="unevaluated"
INTEGRITY="unevaluated"
FRESHNESS="unevaluated"
HEAD_MOVED=0

evaluate_completeness() { # <ref-list-file> <delivered-list-file> <out: kept-list-file>
  local reflist="$1" dellist="$2" keep="$3"

  # Exclusions are stripped from BOTH sides before the set comparison, and the
  # count of what was stripped is capped. Stripping from one side only would
  # turn an exclusion into a licence to deliver anything.
  local ref_kept="$SCRATCH/ref.kept" del_kept="$SCRATCH/del.kept"
  local excluded=0 p
  : > "$ref_kept"; : > "$del_kept"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if is_excluded "$p"; then excluded=$((excluded + 1)); else printf '%s\n' "$p" >> "$ref_kept"; fi
  done < "$reflist"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if is_excluded "$p"; then excluded=$((excluded + 1)); else printf '%s\n' "$p" >> "$del_kept"; fi
  done < "$dellist"

  if [[ "$excluded" -gt "$EXCLUSION_CAP" ]]; then
    finding incomplete_delivery "exclusion cap breached: $excluded paths excused, cap is ${EXCLUSION_CAP}"
    COMPLETENESS="red"
  fi

  # SET comparison, both directions. `comm` needs both inputs sorted; both come
  # from LC_ALL=C sorts above.
  local missing extra
  missing="$(comm -23 "$ref_kept" "$del_kept" || true)"
  extra="$(comm -13 "$ref_kept" "$del_kept" || true)"

  local missing_n=0 extra_n=0
  [[ -n "$missing" ]] && missing_n="$(printf '%s\n' "$missing" | grep -c . || true)"
  [[ -n "$extra" ]] && extra_n="$(printf '%s\n' "$extra" | grep -c . || true)"

  if [[ "$missing_n" -gt 0 ]]; then
    finding incomplete_delivery "$missing_n path(s) served by ${REPO}@${DELIVERED_SHA} were not delivered: $(printf '%s' "$missing" | head -n 10 | tr '\n' ' ')"
    COMPLETENESS="red"
  fi
  if [[ "$extra_n" -gt 0 ]]; then
    finding incomplete_delivery "$extra_n delivered path(s) are not served by ${REPO}@${DELIVERED_SHA}: $(printf '%s' "$extra" | head -n 10 | tr '\n' ' ')"
    COMPLETENESS="red"
  fi

  EXPECTED="$(grep -c . "$ref_kept" || true)"
  cp -- "$del_kept" "$keep" || { echo "FATAL: cp failed building the compare list" >&2; exit 2; }

  [[ "$COMPLETENESS" == "red" ]] || COMPLETENESS="green"
}

evaluate_integrity() { # <compare-list-file>
  local list="$1" rel status delivered_class d_ref d_del
  local refbody="$SCRATCH/ref.body"
  local mismatches=0 unreadable=0

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    local dpath="$DELIVERED_ROOT/$rel"
    if [[ ! -e "$dpath" && ! -L "$dpath" ]]; then
      # Already reported by completeness; not double-counted, and NOT compared —
      # counting it would let `compared` reach `expected` without a comparison.
      continue
    fi

    status="$(reference_fetch "$rel" "$refbody")"
    delivered_class="$(classify_body "$dpath")"

    case "$status" in
      transport)
        finding reference_unreadable "reference fetch failed for '$rel' at ${REPO}@${DELIVERED_SHA}"
        unreadable=$((unreadable + 1)); continue ;;
      html)
        if [[ "$delivered_class" != "html" ]]; then
          finding reference_unreadable "reference for '$rel' returned an HTML document where the delivered file is not HTML"
          unreadable=$((unreadable + 1)); continue
        fi ;;
      empty)
        if [[ "$delivered_class" != "empty" ]]; then
          finding reference_unreadable "reference for '$rel' returned an empty body where the delivered file is non-empty"
          unreadable=$((unreadable + 1)); continue
        fi ;;
    esac

    d_ref="$(digest_path "$refbody")"
    d_del="$(digest_path "$dpath")"
    COMPARED=$((COMPARED + 1))
    if [[ "$d_ref" != "$d_del" ]]; then
      # The loop does NOT stop here. Stopping at the first mismatch reports one
      # corrupt file whether one or four hundred are corrupt.
      finding content_mismatch "'$rel' delivered=${d_del:0:12} reference=${d_ref:0:12}"
      mismatches=$((mismatches + 1))
    fi
  done < "$list"

  if [[ "$mismatches" -gt 0 || "$unreadable" -gt 0 ]]; then
    INTEGRITY="red"
  else
    INTEGRITY="green"
  fi
}

evaluate_freshness() {
  local head1 head2
  head1="$(read_main_head first || true)"
  if [[ -z "$head1" ]]; then
    finding reference_unreadable "could not read ${REPO} main HEAD; the freshness conjunct is UNAVAILABLE"
    FRESHNESS="unavailable"
    return 0
  fi

  if [[ "$DELIVERED_SHA" == "$head1" ]]; then
    FRESHNESS="green"
    return 0
  fi

  # The ONE sanctioned exception: a merge landing between the install and this
  # read. Re-read once. A head that MOVED explains the difference without any
  # claim about delivery, so it is a distinct outcome — reporting it as
  # staleness would page someone every time a PR merges during the canary run.
  head2="$(read_main_head recheck || true)"
  if [[ -n "$head2" && "$head2" != "$head1" ]]; then
    HEAD_MOVED=1
    FRESHNESS="head-moved"
    printf 'canary-note| %s main HEAD moved during the run (%s -> %s); freshness is not asserted for this run\n' \
      "$REPO" "${head1:0:12}" "${head2:0:12}" >&2
    return 0
  fi

  finding stale_delivery "delivered commit ${DELIVERED_SHA:0:12} != ${REPO} main HEAD ${head1:0:12}"
  FRESHNESS="red"
}

run_canary() {
  mkscratch
  load_exclusions

  if ! acquire; then
    # Acquisition failed. The conjuncts stay unevaluated and `compared=0` is
    # printed, which the verdict below treats as a failure — a run that compared
    # nothing must never read as a run that found nothing.
    report
    return 1
  fi

  if [[ -z "$DELIVERED_SHA" ]]; then
    finding installpath_unresolved "no delivered commit resolved; the reference cannot be pinned"
    report
    return 1
  fi

  local reflist="$SCRATCH/ref.list" dellist="$SCRATCH/del.list" cmplist="$SCRATCH/compare.list"
  if ! reference_list "$reflist"; then
    # UNAVAILABLE, not "downgrade to whatever we can see". Without the reference
    # listing there is no set to compare against, and a subset comparison is
    # structurally blind to the under-delivery this guard exists to catch.
    finding reference_unreadable "reference listing for ${REPO}@${DELIVERED_SHA} is unavailable, rate-limited, or truncated; the COMPLETENESS conjunct is UNAVAILABLE"
    COMPLETENESS="unavailable"
    report
    return 1
  fi

  list_tree "$DELIVERED_ROOT" > "$dellist" || { echo "FATAL: could not list $DELIVERED_ROOT" >&2; exit 2; }

  evaluate_completeness "$reflist" "$dellist" "$cmplist"
  evaluate_integrity "$cmplist"
  evaluate_freshness

  report
}

report() {
  # `compared` and `expected` are ALWAYS both printed, and disagreement is a
  # failure. "0 comparisons" can never be allowed to read as "0 differences".
  printf 'canary-counts| compared=%s expected=%s\n' "$COMPARED" "$EXPECTED"

  # The cardinality check raises a real FINDING rather than a separate verdict
  # channel. That is what keeps the zero-findings line honest: without it a run
  # could print "every delivery assertion holds" and exit 1 on a count nobody
  # named, which is a contradiction the consumer would have to guess at.
  if [[ "$COMPARED" -eq 0 ]]; then
    finding incomplete_delivery "compared=0: nothing was verified, so no delivery assertion was evaluated"
  elif [[ "$COMPARED" -ne "$EXPECTED" ]]; then
    finding incomplete_delivery "compared=${COMPARED} disagrees with expected=${EXPECTED}: the comparison count and the reference cardinality do not match"
  fi

  printf 'canary-conjuncts| completeness=%s integrity=%s freshness=%s\n' \
    "$COMPLETENESS" "$INTEGRITY" "$FRESHNESS" >&2

  if [[ "$FINDING_COUNT" -eq 0 ]]; then
    printf 'canary-finding| every delivery assertion holds at %s\n' "$(sanitize "$DELIVERED_SHA")"
    if [[ "$HEAD_MOVED" -eq 1 ]]; then
      printf 'canary-verdict| head-moved-during-run\n' >&2
    else
      printf 'canary-verdict| ok\n' >&2
    fi
    return 0
  fi

  printf 'canary-verdict| findings (%s)\n' "$FINDING_COUNT" >&2
  return 1
}

# ---------------------------------------------------------------------------
# --self-test. Drives THIS script as a subprocess through the seam, against a
# synthesized fixture, with no network and no credentials. Re-invoking the real
# binary rather than calling the functions in-process is deliberate: it proves
# the seam that the mutation battery depends on, and it exercises the exit codes
# a workflow will branch on.
# ---------------------------------------------------------------------------
ST_ASSERTIONS=0
ST_UNEXPECTED=0

st_check() { # <name> <expected> <actual>
  ST_ASSERTIONS=$((ST_ASSERTIONS + 1))
  if [[ "$2" != "$3" ]]; then
    ST_UNEXPECTED=$((ST_UNEXPECTED + 1))
    printf 'SELF-TEST UNEXPECTED: %s (expected %q, got %q)\n' "$1" "$2" "$3" >&2
  fi
}

self_test() {
  local root
  root="$(mktemp -d "${TMPDIR}/delivery-canary-selftest.XXXXXXXX")" || {
    echo "FATAL: mktemp failed — cannot build the self-test fixture" >&2; exit 2; }
  # Fixture setup failures exit 2 rather than continuing: a sandbox that could
  # not be built produces a confident WRONG verdict, not a missing one.
  mkdir -p "$root/ref/a" "$root/del/a" || { echo "FATAL: mkdir failed under $root" >&2; exit 2; }

  local f
  for f in a/one.md a/two.md three.sh; do
    mkdir -p "$root/ref/$(dirname "$f")" "$root/del/$(dirname "$f")" \
      || { echo "FATAL: mkdir failed for $f" >&2; exit 2; }
    printf 'content of %s\n' "$f" > "$root/ref/$f" || { echo "FATAL: write failed" >&2; exit 2; }
    cp -- "$root/ref/$f" "$root/del/$f" || { echo "FATAL: cp failed" >&2; exit 2; }
  done

  local sha_current="1111111111111111111111111111111111111111"
  local sha_old="2222222222222222222222222222222222222222"
  local out rc

  st_run() { # <delivered-root> <ref-dir> <delivered-sha> <main-head> <recheck>
    set +e
    out="$(CANARY_DELIVERED_ROOT="$1" CANARY_REFERENCE_DIR="$2" \
           CANARY_DELIVERED_SHA="$3" CANARY_MAIN_HEAD="$4" CANARY_MAIN_HEAD_RECHECK="$5" \
           CANARY_INSTALLED_PLUGINS="" \
           bash "$SELF_PATH" 2>&1)"
    rc=$?
    set -e
  }

  # 1. Positive control. Without this every RED below could be red for a reason
  #    that has nothing to do with the mutation.
  st_run "$root/del" "$root/ref" "$sha_current" "$sha_current" ""
  st_check "green fixture exits 0" "0" "$rc"
  st_check "green fixture verdict" "ok" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-verdict| \(.*\)$/\1/p')"
  st_check "green fixture compared 3" "compared=3 expected=3" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-counts| //p')"
  st_check "green fixture emits the holds line" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| every delivery assertion holds at ' && echo yes || echo no)"

  # 2. A missing delivered file — the under-delivery shape.
  rm -f "$root/del/a/two.md"
  st_run "$root/del" "$root/ref" "$sha_current" "$sha_current" ""
  st_check "missing file exits 1" "1" "$rc"
  st_check "missing file reports incomplete_delivery" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| incomplete_delivery: ' && echo yes || echo no)"
  cp -- "$root/ref/a/two.md" "$root/del/a/two.md" || { echo "FATAL: cp failed" >&2; exit 2; }

  # 3. The SECOND file in sort order corrupted, the first identical — a loop
  #    that stops at the first member reports green here.
  printf 'tampered\n' > "$root/del/a/two.md"
  st_run "$root/del" "$root/ref" "$sha_current" "$sha_current" ""
  st_check "second-file corruption exits 1" "1" "$rc"
  st_check "second-file corruption names the file" "yes" \
    "$(printf '%s\n' "$out" | grep -qE "^canary-finding\| content_mismatch: 'a/two\.md' " && echo yes || echo no)"
  cp -- "$root/ref/a/two.md" "$root/del/a/two.md" || { echo "FATAL: cp failed" >&2; exit 2; }

  # 4. An OLDER but internally consistent commit: freshness RED alone.
  st_run "$root/del" "$root/ref" "$sha_old" "$sha_current" "$sha_current"
  st_check "stale delivery exits 1" "1" "$rc"
  st_check "stale delivery conjuncts" "completeness=green integrity=green freshness=red" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-conjuncts| //p')"

  # 5. HEAD moved mid-run: a DISTINCT, non-alarming outcome.
  st_run "$root/del" "$root/ref" "$sha_old" "$sha_current" "3333333333333333333333333333333333333333"
  st_check "head-moved exits 0" "0" "$rc"
  st_check "head-moved verdict" "head-moved-during-run" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-verdict| \(.*\)$/\1/p')"

  # 6. An empty reference body where the delivered file is not empty.
  : > "$root/ref/three.sh"
  st_run "$root/del" "$root/ref" "$sha_current" "$sha_current" ""
  st_check "empty reference body exits 1" "1" "$rc"
  st_check "empty reference body is reference_unreadable" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| reference_unreadable: ' && echo yes || echo no)"

  # 7. An HTML error page where the delivered file is not HTML.
  printf '<!DOCTYPE html>\n<html><body>404</body></html>\n' > "$root/ref/three.sh"
  st_run "$root/del" "$root/ref" "$sha_current" "$sha_current" ""
  st_check "html error page exits 1" "1" "$rc"
  st_check "html error page is reference_unreadable" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| reference_unreadable: ' && echo yes || echo no)"
  printf 'content of three.sh\n' > "$root/ref/three.sh"

  # 8. No reference listing at all: the completeness conjunct is UNAVAILABLE and
  #    the run fails closed rather than comparing a subset.
  st_run "$root/del" "$root/ref-does-not-exist" "$sha_current" "$sha_current" ""
  st_check "absent reference listing exits 1" "1" "$rc"
  st_check "absent reference listing is UNAVAILABLE" "completeness=unavailable" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-conjuncts| //p' | grep -oE 'completeness=[a-z-]+' || true)"
  st_check "absent reference listing prints compared=0" "compared=0 expected=0" \
    "$(printf '%s\n' "$out" | sed -n 's/^canary-counts| //p')"

  # 9. An unresolvable installPath — compared=0 must FAIL, never green-by-vacuity.
  printf '{"version":1,"plugins":{}}\n' > "$root/installed_plugins.json"
  set +e
  out="$(CANARY_INSTALLED_PLUGINS="$root/installed_plugins.json" \
         CANARY_REFERENCE_DIR="$root/ref" CANARY_MAIN_HEAD="$sha_current" \
         bash "$SELF_PATH" 2>&1)"
  rc=$?
  set -e
  st_check "unresolved installPath exits 1" "1" "$rc"
  st_check "unresolved installPath token" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| installpath_unresolved: ' && echo yes || echo no)"
  st_check "unresolved installPath fails on cardinality" "yes" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| incomplete_delivery: compared=0' && echo yes || echo no)"
  st_check "unresolved installPath never claims the assertions hold" "no" \
    "$(printf '%s\n' "$out" | grep -qE '^canary-finding\| every delivery assertion holds' && echo yes || echo no)"

  rm -rf "$root"

  if [[ "$ST_UNEXPECTED" -ne 0 ]]; then
    printf 'SELF-TEST FAILED: %s assertions exercised, %s unexpected\n' "$ST_ASSERTIONS" "$ST_UNEXPECTED"
    exit 1
  fi
  printf 'SELF-TEST OK: %s assertions exercised, 0 unexpected\n' "$ST_ASSERTIONS"
  exit 0
}

SELF_PATH="${BASH_SOURCE[0]}"

if [[ "$SELF_TEST" -eq 1 ]]; then
  self_test
fi

run_canary
