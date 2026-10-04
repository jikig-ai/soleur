#!/usr/bin/env bash
# check-web-host-escrow-config.sh -- the web-host escrow-split contract (#9377, ADR-263 R4 narrowing).
#
# THE SPLIT. A web host born through the fresh-boot path (hcloud_server.web[*], cloud-init) reads its LUKS
# passphrase and its own header-escrow credentials from the Doppler branch config `prd_workspaces_luks_web`;
# web-1 keeps `prd_workspaces_luks`. A token scoped to the web config therefore cannot resolve web-1's R2
# escrow pair, and (decision A1) the web-class passphrase is its OWN random_password.workspaces_luks_web, not
# web-1's. This script checks that contract in two modes.
#
#   --static [--root DIR]   Repo only, no Doppler, no network. A CENSUS of every occurrence of the web-1 config
#                           name under apps/web-platform/infra/ (or DIR): every web-class path must select
#                           prd_workspaces_luks_web, every web-1 path must keep prd_workspaces_luks, and no
#                           other file may name it. It also asserts the passphrase split, as a NAME census over
#                           *.tf, *.tf.json, *.yml/*.yaml, *.sh, *.tpl/*.tftpl and *.service (a value handed to a
#                           host travels through cloud-init and templates, so those are in scope): the word-bounded
#                           addresses random_password.workspaces_luks and doppler_secret.workspaces_luks_key (web-1's
#                           generator and its Doppler copy; NOT the `_web` ones) may be named in code only by the
#                           file workspaces-luks.tf (exact relative-path match), no Doppler data source
#                           (data "doppler_secret(s)") may appear outside web-1's own files, and
#                           workspaces-luks-header-web.tf must exist (`census-empty` otherwise). It proves that no
#                           file NAMES those addresses, not that no value flows by another route (a variable, a
#                           remote state, an out-of-band copy), and never value distinctness. Prints `escrow-split-contract:ok` (rc 0) or one
#                           `escrow-split-contract:FAIL <file>: <why>` line per violation (rc 1). An empty
#                           census (no file found, e.g. a broken path glob) is `census-empty` (rc 1), never a
#                           pass. This is a CI guard, not production detection: it fails the PR that moves a
#                           web-class path back onto web-1's config.
#   --live                  Reads Doppler NAMES only (`doppler secrets --only-names`, never a value, never
#                           `get`/`run`/`download`). Needs DOPPLER_TOKEN in the environment (a read token); it
#                           never falls back to an ambient login. Asserts that prd_workspaces_luks_web holds the
#                           five names (WORKSPACES_LUKS_KEY, WORKSPACES_HEADER_BUCKET,
#                           WORKSPACES_HEADER_R2_ENDPOINT from Terraform; WORKSPACES_HEADER_R2_ACCESS_KEY_ID and
#                           WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY from the deferred mint), that web-1's pair and
#                           the passphrase are ABSENT from the `prd` root (a branch config inherits `prd`, so a
#                           name there would hand it to the web-class token), and lists `prd`-root names
#                           matching R2|CLOUDFLARE|AWS_|HCLOUD|HETZNER|CF_|GITHUB|DOPPLER as an advisory scan
#                           (never changes the rc; a token resolves ~116 inherited secrets, so isolation is
#                           "narrowed", not proven). Prints `escrow-split-contract:live-ok` (rc 0).
#                           NECESSARY, NOT SUFFICIENT. It reads NAMES only, so a mis-pasted credential pair (right
#                           names, wrong values) passes, and so does a WORKSPACES_LUKS_KEY copied from web-1's
#                           config: value distinctness is NOT checkable from names (the --static census proves
#                           the naming census instead). A FAILURE prints one `escrow-split-contract:CAUSE` line per
#                           missing-name family (Terraform-created names: consistent with the push-apply not having
#                           created them; the R2 pair: with the live mint not having been done; both marked
#                           unmeasured), and an unreadable web config prints a NOTE (usually consistent with the
#                           push-apply not having created it). ESCROW_ADVISORY=count (set by the preflight, the repo
#                           being public) prints the advisory scan as a count only. This mode is ENFORCED by the workflow: the
#                           web_host_create and web_host_replace jobs of apply-web-platform-infra.yml run it through
#                           scripts/web-host-escrow-preflight.sh before any Terraform command, and the runbooks'
#                           step 0 dispatches the read-only diagnostic workflow (web-host-escrow-diagnose.yml), which
#                           runs the same preflight. It needs a token that can read
#                           BOTH configs (a workplace-scope token; a config-scoped service token exits 3).
#
# EXIT CODES: 0 ok | 1 contract violated | 2 usage | 3 live read unreadable (a failed, empty or unrecognised
# read is NEVER treated as "absent": a zero count from a command that failed is not evidence of absence).
#
# DOPPLER CLI CONTRACT this script relies on (scripts/check-web-host-escrow-config.test.sh replays it):
# `doppler secrets --only-names -p P -c C` prints a table (header NAME, a rule, one name per row; the checker
# tokenises it and requires the NAME header so an unrecognised shape is refused rather than read as "no names");
# a failed read exits 1 with `Unable to fetch secret names` / `Doppler Error: <reason>` on STDERR and nothing on
# stdout (measured against v3.76 with an invalid token).
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${DOPPLER_TOKEN:+x}${WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY:+x}${WORKSPACES_LUKS_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

MODE=""
ROOT=""
while (($#)); do
  case "$1" in
    --static) MODE=static ;;
    --live) MODE=live ;;
    --root) ROOT="${2:-}"; shift ;;
    -h|--help) sed -n '2,59p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: check-web-host-escrow-config.sh --static [--root DIR] | --live" >&2; exit 2 ;;
  esac
  shift
done
[[ -n "$MODE" ]] || { echo "usage: check-web-host-escrow-config.sh --static [--root DIR] | --live" >&2; exit 2; }

# ---------------------------------------------------------------------------------------------------
# LIVE
# ---------------------------------------------------------------------------------------------------
if [[ "$MODE" == live ]]; then
  [[ -z "$ROOT" ]] || { echo "usage: --root is a --static option" >&2; exit 2; }
  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    echo "escrow-split-contract:usage: --live needs DOPPLER_TOKEN (a read token) in the environment; it never falls back to an ambient login" >&2
    exit 2
  fi
  command -v doppler >/dev/null 2>&1 || { echo "escrow-split-contract:usage: doppler CLI not found on PATH" >&2; exit 2; }

  WEB_CFG=prd_workspaces_luks_web
  ERRF="$(mktemp "${TMPDIR:-/var/tmp}/escrow-live-err.XXXXXXXX")" || exit 2
  trap 'rm -f "${ERRF:?}"' EXIT

  # read_names <config> -> sets NAMES (one per line, header excluded) or exits 3.
  read_names() {
    local cfg="$1" out rc
    out="$(doppler secrets --only-names -p soleur -c "$cfg" --no-check-version 2>"$ERRF")"; rc=$?
    if [[ "$rc" -ne 0 ]]; then
      # Redact any Doppler token shape (dp.<kind>.<body>) BEFORE truncating: the stderr is CLI-controlled text and a
      # future CLI version could echo the credential it was handed.
      echo "escrow-split-contract:unreadable: config ${cfg} (rc=${rc}): $(LC_ALL=C tr -c '\040-\176' ' ' <"$ERRF" | sed -E 's/dp\.[A-Za-z]+\.[A-Za-z0-9._-]+/dp.REDACTED/g' | head -c 300)" >&2
      # An absent web-class config is the state BEFORE the reviewed push-apply, and the read failure alone reads like a
      # Doppler outage. Say what this is consistent with, and that it is unmeasured (a failed read is not proof of absence).
      if [[ "$cfg" == "$WEB_CFG" ]] && grep -qF 'Could not find requested config' "$ERRF"; then
        echo "escrow-split-contract:NOTE ${cfg} was not found; this is usually consistent with the web-platform push-apply (apply-web-platform-infra.yml) not having created it yet (unmeasured: the read failed, absence of the config is not proven)" >&2
      fi
      exit 3
    fi
    # Tokenise the table: every run of [A-Za-z0-9_] on its own line. Borders and rules fall away.
    local toks; toks="$(printf '%s\n' "$out" | tr -c 'A-Za-z0-9_\n' '\n' | grep -E '^[A-Za-z0-9_]+$' || true)"
    if ! grep -qx 'NAME' <<<"$toks"; then
      echo "escrow-split-contract:unreadable: config ${cfg}: output shape unrecognised (no NAME header), refusing to read it as an empty listing" >&2
      exit 3
    fi
    NAMES="$(grep -vx 'NAME' <<<"$toks" || true)"
    if [[ -z "$NAMES" ]]; then
      echo "escrow-split-contract:unreadable: config ${cfg}: the listing is empty, which a failed read and a truly empty config both produce; not treated as absence" >&2
      exit 3
    fi
  }

  read_names "$WEB_CFG"; WEB_NAMES="$NAMES"
  read_names prd; PRD_NAMES="$NAMES"

  viol=0; miss_tf=0; miss_r2=0
  for n in WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT; do
    if ! grep -qx "$n" <<<"$WEB_NAMES"; then
      echo "escrow-split-contract:FAIL missing in ${WEB_CFG}: ${n}"; viol=1; miss_tf=1
    fi
  done
  for n in WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY; do
    if ! grep -qx "$n" <<<"$WEB_NAMES"; then
      echo "escrow-split-contract:FAIL missing in ${WEB_CFG}: ${n}"; viol=1; miss_r2=1
    fi
  done
  # The cause map (one line per family, here and only here; the runbooks point at this output).
  [[ "$miss_tf" -eq 0 ]] || echo "escrow-split-contract:CAUSE a missing WORKSPACES_LUKS_KEY, WORKSPACES_HEADER_BUCKET or WORKSPACES_HEADER_R2_ENDPOINT is consistent with the web-platform push-apply (apply-web-platform-infra.yml) not having created it yet (unmeasured)"
  [[ "$miss_r2" -eq 0 ]] || echo "escrow-split-contract:CAUSE a missing WORKSPACES_HEADER_R2_ACCESS_KEY_ID or WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY is consistent with the live R2 credential mint (#9377) not having been done yet (unmeasured)"
  for n in WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY WORKSPACES_LUKS_KEY; do
    if grep -qx "$n" <<<"$PRD_NAMES"; then
      echo "escrow-split-contract:FAIL present in the prd root: ${n} (a branch config inherits prd, so the web-class token would resolve it)"; viol=1
    fi
  done
  # Advisory only: the token resolves the whole inherited root, so these names are reachable from a web host.
  # ESCROW_ADVISORY=count (set by scripts/web-host-escrow-preflight.sh): the repo is public and the preflight runs on
  # every birth, so the CI log carries a COUNT, never the credential-name inventory. A direct --live run lists the names.
  if [[ "${ESCROW_ADVISORY:-}" == count ]]; then
    adv_n="$(grep -cE 'R2|CLOUDFLARE|AWS_|HCLOUD|HETZNER|CF_|GITHUB|DOPPLER' <<<"$PRD_NAMES" || true)"
    echo "advisory: ${adv_n} prd-root name(s) are reachable from a web-class token (names withheld in CI; run scripts/check-web-host-escrow-config.sh --live locally to list them)"
  else
    while IFS= read -r n; do
      [[ -n "$n" ]] && echo "advisory: ${n} (prd root; reachable from a web-class token)"
    done < <(grep -E 'R2|CLOUDFLARE|AWS_|HCLOUD|HETZNER|CF_|GITHUB|DOPPLER' <<<"$PRD_NAMES" || true)
  fi

  if [[ "$viol" -ne 0 ]]; then exit 1; fi
  echo "escrow-split-contract:live-ok"
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
# STATIC
# ---------------------------------------------------------------------------------------------------
[[ -n "$ROOT" ]] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/web-platform/infra"

# BARE: the web-1 config name NOT followed by a name character (so prd_workspaces_luks_web / _marker do not match).
BARE='prd_workspaces_luks([^A-Za-z0-9_]|$)'

WEB_FILES=(cloud-init.yml workspaces-luks-provision.sh workspaces-luks-reopen.sh workspaces-luks-reopen.service
           workspaces-luks-reopen-failure.service luks-monitor.sh workspaces-luks-fresh-boot.tf server.tf
           soleur-host-bootstrap.sh)
# The explicit web-1 exclusion list, itself pinned: each file must still exist and still name the web-1 config.
WEB1_FILES=(workspaces-luks.tf workspaces-luks-header.tf luks-monitor-token-refresh.sh workspaces-cutover.sh uptime-alerts.tf)
# Data files that legitimately list the name (not a path executed on any host).
DATA_FILES=(doppler-config-inventory.txt)

V=()
viol() { V+=("escrow-split-contract:FAIL $1: $2"); }

# code <file>: the file with comment-only lines removed, so a comment that mentions the name never trips the census.
code() { grep -vE '^[[:space:]]*(#|//)' "$1" 2>/dev/null || true; }
bare_count() { code "$1" | grep -cE "$BARE" || true; }
# tf_block <file> <type> <name>: a resource block (comment-stripped), brace-depth extracted.
tf_block() {
  code "$1" | awk -v t="$2" -v n="$3" '
    $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1 }
    inb { print; d += gsub(/\{/, "{"); d -= gsub(/\}/, "}"); if (d <= 0 && NR > 1 && /\}/) { inb = 0 } }'
}
tf_attr() { printf '%s\n' "$1" | sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\\1/p" | head -1; }

# The web-class passphrase file (decision A1). Missing it is `census-empty`, never a clean pass: a root without it
# cannot prove the web-class passphrase is generated independently.
HEADER_WEB_FILE=workspaces-luks-header-web.tf

# --- census-empty guard --------------------------------------------------------------------------------
found=0
for f in "${WEB_FILES[@]}" "${WEB1_FILES[@]}"; do [[ -f "$ROOT/$f" ]] && found=$((found + 1)); done
if [[ "$found" -eq 0 ]]; then
  echo "escrow-split-contract:FAIL census-empty: none of the census files exists under ${ROOT} (a broken path glob or wrong root must not read as a clean tree)"
  exit 1
fi
for f in "${WEB_FILES[@]}" "${WEB1_FILES[@]}"; do
  [[ -f "$ROOT/$f" ]] || viol "$f" "census file missing under ${ROOT}"
done
[[ -f "$ROOT/$HEADER_WEB_FILE" ]] || viol census-empty "${HEADER_WEB_FILE} is missing under ${ROOT} (the web-class passphrase census has nothing to check; a missing file must not read as a clean tree)"

# --- web-class paths ---------------------------------------------------------------------------------
ci="$ROOT/cloud-init.yml"
if [[ -f "$ci" ]]; then
  [[ "$(code "$ci" | grep -c 'WORKSPACES_DOPPLER_CONFIG=')" == 1 ]] || viol cloud-init.yml "expected exactly one WORKSPACES_DOPPLER_CONFIG= line in code"
  code "$ci" | grep -E 'WORKSPACES_DOPPLER_CONFIG=' | grep -qE 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web([^A-Za-z0-9_]|$)' \
    || viol cloud-init.yml "the boot env file must name prd_workspaces_luks_web (web-class host)"
  [[ "$(bare_count "$ci")" == 0 ]] || viol cloud-init.yml "names web-1's prd_workspaces_luks in code"
fi

pv="$ROOT/workspaces-luks-provision.sh"
if [[ -f "$pv" ]]; then
  code "$pv" | grep -qE -- '--config[[:space:]]+prd_workspaces_luks([^A-Za-z0-9_]|$)' && viol workspaces-luks-provision.sh "hardcodes --config prd_workspaces_luks"
  code "$pv" | grep -qE -- '--config "\$CFG"' || viol workspaces-luks-provision.sh 'the key read must select the config from the boot env file (--config "$CFG")'
  code "$pv" | grep -q 'prd_workspaces_luks_web' || viol workspaces-luks-provision.sh "does not accept prd_workspaces_luks_web (a web host whose boot env names it would fail closed at config)"
fi

ro="$ROOT/workspaces-luks-reopen.sh"
if [[ -f "$ro" ]]; then
  code "$ro" | grep -qE -- '--config "\$WORKSPACES_DOPPLER_CONFIG"' || viol workspaces-luks-reopen.sh 'the key read must use --config "$WORKSPACES_DOPPLER_CONFIG"'
  [[ "$(bare_count "$ro")" == 0 ]] || viol workspaces-luks-reopen.sh "names web-1's prd_workspaces_luks in code (the config comes from the boot env file)"
fi

rs="$ROOT/workspaces-luks-reopen.service"
if [[ -f "$rs" ]]; then
  [[ "$(bare_count "$rs")" == 0 ]] || viol workspaces-luks-reopen.service "names web-1's prd_workspaces_luks in code"
fi

rf="$ROOT/workspaces-luks-reopen-failure.service"
if [[ -f "$rf" ]]; then
  # The ONE allowed bare occurrence is the documented absent-file default of the env-file variable.
  bad="$(code "$rf" | grep -E "$BARE" | grep -vcE '\$\{WORKSPACES_DOPPLER_CONFIG:-prd_workspaces_luks\}' || true)"
  [[ "$bad" == 0 ]] || viol workspaces-luks-reopen-failure.service "names prd_workspaces_luks other than as the \${WORKSPACES_DOPPLER_CONFIG:-...} absent-file default"
fi

mon="$ROOT/luks-monitor.sh"
if [[ -f "$mon" ]]; then
  mcode="$(code "$mon")"
  kr="$(grep -E 'secrets get WORKSPACES_LUKS_KEY' <<<"$mcode" || true)"
  [[ -n "$kr" ]] || viol luks-monitor.sh "no WORKSPACES_LUKS_KEY read found"
  if [[ -n "$kr" ]]; then
    while IFS= read -r l; do
      grep -qE -- '--config "\$[A-Za-z_]+"' <<<"$l" || viol luks-monitor.sh "a WORKSPACES_LUKS_KEY read is not parameterized (--config \"\$VAR\"): ${l:0:120}"
    done <<<"$kr"
  fi
  hb="$(grep -E 'secrets get WORKSPACES_LUKS_HEARTBEAT_URL' <<<"$mcode" || true)"
  if [[ "$(grep -cE -- '--config prd_workspaces_luks([^A-Za-z0-9_]|$)' <<<"$hb" || true)" != 1 ]]; then
    viol luks-monitor.sh "the heartbeat read must stay on prd_workspaces_luks (exactly one; the standby profile skips it)"
  fi
  # Every other bare line must be the documented fallback default or the closed-set arm.
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    grep -qE 'WORKSPACES_LUKS_HEARTBEAT_URL' <<<"$l" && continue
    grep -qE '^[[:space:]]*KEY_CONFIG=prd_workspaces_luks[[:space:]]*(#.*)?$' <<<"$l" && continue
    grep -qE '^[[:space:]]*prd_workspaces_luks\|prd_workspaces_luks_web\)' <<<"$l" && continue
    viol luks-monitor.sh "an undocumented bare prd_workspaces_luks occurrence: ${l:0:120}"
  done < <(grep -E "$BARE" <<<"$mcode" || true)
fi

fb="$ROOT/workspaces-luks-fresh-boot.tf"
if [[ -f "$fb" ]]; then
  wt="$(tf_block "$fb" doppler_service_token workspaces_luks_fresh_boot_web)"
  if [[ -z "$wt" ]]; then
    viol workspaces-luks-fresh-boot.tf "doppler_service_token.workspaces_luks_fresh_boot_web not found"
  elif [[ "$(tf_attr "$wt" config)" != 'doppler_config.workspaces_luks_web.name' ]]; then
    viol workspaces-luks-fresh-boot.tf "the web-class fresh-boot token must read doppler_config.workspaces_luks_web.name (got: $(tf_attr "$wt" config))"
  fi
  wc="$(tf_block "$fb" doppler_config workspaces_luks_web)"
  [[ "$(tf_attr "$wc" name)" == '"prd_workspaces_luks_web"' ]] || viol workspaces-luks-fresh-boot.tf "doppler_config.workspaces_luks_web must be named prd_workspaces_luks_web"
  # The pre-split token is left in place on web-1's config (retired later by an acknowledged destroy); it is the
  # ONE bare occurrence this file may carry.
  legacy="$(tf_block "$fb" doppler_service_token workspaces_luks_fresh_boot)"
  outside="$(code "$fb" | grep -cE "$BARE" || true)"
  inside="$(printf '%s\n' "$legacy" | grep -cE "$BARE" || true)"
  [[ "$((outside - inside))" == 0 ]] || viol workspaces-luks-fresh-boot.tf "names prd_workspaces_luks outside the pre-split token resource"
fi

sv="$ROOT/server.tf"
if [[ -f "$sv" ]]; then
  code "$sv" | grep -qE '^[[:space:]]*workspaces_luks_fresh_boot_token[[:space:]]*=[[:space:]]*doppler_service_token\.workspaces_luks_fresh_boot_web\.key[[:space:]]*$' \
    || viol server.tf "user_data must carry doppler_service_token.workspaces_luks_fresh_boot_web.key (the web-class token), not the pre-split one"
  [[ "$(bare_count "$sv")" == 0 ]] || viol server.tf "names web-1's prd_workspaces_luks in code"
fi

bs="$ROOT/soleur-host-bootstrap.sh"
if [[ -f "$bs" ]]; then
  [[ "$(bare_count "$bs")" == 0 ]] || viol soleur-host-bootstrap.sh "names web-1's prd_workspaces_luks in code"
fi

# --- web-1 paths keep the un-suffixed name -------------------------------------------------------------
for f in "${WEB1_FILES[@]}"; do
  p="$ROOT/$f"; [[ -f "$p" ]] || continue
  [[ "$(bare_count "$p")" -ge 1 ]] || viol "$f" "web-1 path no longer names prd_workspaces_luks (a stale exclusion entry, or a broken scan, must not read as clean)"
  code "$p" | grep -qE 'prd_workspaces_luks_web' && viol "$f" "web-1 path names prd_workspaces_luks_web (web-1 keeps its own config)"
done
wl="$ROOT/workspaces-luks.tf"
if [[ -f "$wl" ]]; then
  code "$wl" | grep -E "WORKSPACES_DOPPLER_CONFIG=%s" | grep -qE "'prd_workspaces_luks'" \
    || viol workspaces-luks.tf "web-1's SSH installer must keep writing WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks"
fi

# --- sweep: no OTHER file may name the web-1 config ----------------------------------------------------
declare -A CLASSIFIED=()
declare -A WEB1_SET=()
for f in "${WEB1_FILES[@]}"; do WEB1_SET["$f"]=1; done
for f in "${WEB_FILES[@]}" "${WEB1_FILES[@]}" "${DATA_FILES[@]}"; do CLASSIFIED["$f"]=1; done
# Token-address census (Guard 3, the credential side). The pre-split token (scoped to web-1's config) must be
# addressed nowhere in code, so a templatefile map key or a locals/output re-pointed at it cannot hand a web-class
# host web-1's pair; web-1's own token (doppler_service_token.workspaces_luks, word-bounded so _fresh_boot*/_marker*
# do not match) is addressed only from its definition file. The workflows' -target lists are outside ROOT.
PRE_TOK='doppler_service_token\.workspaces_luks_fresh_boot([^A-Za-z0-9_]|$)'
W1_TOK='doppler_service_token\.workspaces_luks([^A-Za-z0-9_]|$)'
W1_TOK_FILE=workspaces-luks.tf
# Passphrase census (Guard 1, decision A1): web-1's generator address, word-bounded so the web-class
# random_password.workspaces_luks_web does not match, may be named in code only by web-1's own file.
W1_PW='random_password\.workspaces_luks([^A-Za-z0-9_]|$)'
W1_PW_FILE=workspaces-luks.tf
# The same value reaches Terraform a second way: web-1's Doppler copy, doppler_secret.workspaces_luks_key (its .value / .id),
# also confined to W1_PW_FILE; and a Doppler data source (data "doppler_secret(s)", HCL or JSON spelling) can materialize
# web-1's passphrase from its config by name, so none may be declared or referenced outside web-1's own files.
W1_COPY_RE='doppler_secret\.workspaces_luks_key([^A-Za-z0-9_]|$)'
W1_DATA='data[[:space:]]+"doppler_secrets?"|data\.doppler_secrets?\.|"doppler_secrets?"[[:space:]]*:'
w1_tok_in_def=0
total_bare=0
while IFS= read -r -d '' abs; do
  rel="${abs#"$ROOT"/}"
  c="$(bare_count "$abs")"
  total_bare=$((total_bare + c))
  case "$rel" in
    *.tf|*.tf.json|*.yml|*.yaml|*.sh|*.tpl|*.tftpl|*.service)
      if [[ "$(code "$abs" | grep -cE "$PRE_TOK" || true)" -ge 1 ]]; then
        viol "$rel" "addresses the pre-split token doppler_service_token.workspaces_luks_fresh_boot in code (it is scoped to web-1's config and must be referenced nowhere; a web-class path uses ..._fresh_boot_web)"
      fi
      if [[ "$rel" != "$W1_PW_FILE" && "$(code "$abs" | grep -cE "$W1_PW" || true)" -ge 1 ]]; then
        viol "$rel" "names web-1's random_password.workspaces_luks in code outside ${W1_PW_FILE} (the web-class passphrase is its own random_password.workspaces_luks_web; no other path may derive a value from web-1's generator)"
      fi
      if [[ "$rel" != "$W1_PW_FILE" && "$(code "$abs" | grep -cE "$W1_COPY_RE" || true)" -ge 1 ]]; then
        viol "$rel" "names web-1's doppler_secret.workspaces_luks_key in code outside ${W1_PW_FILE} (it is a copy of web-1's passphrase; the web-class value must not derive from it)"
      fi
      if [[ -z "${WEB1_SET[$rel]:-}" && "$(code "$abs" | grep -cE "$W1_DATA" || true)" -ge 1 ]]; then
        viol "$rel" "declares or references a Doppler data source (data \"doppler_secret(s)\") outside web-1's own files (a data source can read web-1's passphrase from its config)"
      fi
      t1="$(code "$abs" | grep -cE "$W1_TOK" || true)"
      if [[ "$rel" == "$W1_TOK_FILE" ]]; then w1_tok_in_def="$t1"
      elif [[ "$t1" -ge 1 ]]; then
        viol "$rel" "addresses web-1's token doppler_service_token.workspaces_luks in code outside its definition file ${W1_TOK_FILE}"
      fi
      ;;
  esac
  if [[ "$c" -ge 1 && -z "${CLASSIFIED[$rel]:-}" ]]; then
    viol "$rel" "names prd_workspaces_luks in code but is classified neither as a web-class path nor as a web-1 path (a new web-class path must select prd_workspaces_luks_web; a web-1 path must be added to the pinned exclusion list)"
  fi
done < <(find "$ROOT" -type f \
           ! -path '*/.terraform/*' ! -path '*/node_modules/*' ! -path '*/fixtures/*' ! -path '*/test-fixtures/*' ! -path '*/tests/*' \
           ! -name '*.test.sh' ! -name '*.test.ts' ! -name '*.test.py' -print0 2>/dev/null)
[[ ! -f "$ROOT/$W1_TOK_FILE" || "$w1_tok_in_def" -ge 1 ]] || viol census-empty "the token-address census found no reference to doppler_service_token.workspaces_luks in ${W1_TOK_FILE} (a broken scan must not read as clean)"
[[ "$total_bare" -ge 1 ]] || viol census-empty "the sweep enumerated zero occurrences of prd_workspaces_luks (a broken scan must not read as clean)"

if [[ "${#V[@]}" -gt 0 ]]; then
  printf '%s\n' "${V[@]}"
  exit 1
fi
echo "escrow-split-contract:ok"
exit 0
