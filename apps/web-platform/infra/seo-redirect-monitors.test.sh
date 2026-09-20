#!/usr/bin/env bash
# seo-redirect-monitors.test.sh — guard for the three SAMPLED runtime 301 probes
# (#8364, ADR-204 second amendment).
#
# WHAT THIS GUARDS. The declaration-time guards (this suite's siblings, the
# seo-aeo drift guard, the tombstone gate) prove the redirect set is DECLARED
# correctly. They cannot see a post-apply edge failure: an emptied
# cloudflare_list, a lost rules{} block, a token-scope loss, or a dashboard edit
# all apply clean and stay drift-green while the live 301 is gone. The three
# betteruptime_monitor.seo_redirect_* resources in uptime-alerts.tf are the only
# layer that pages on that class — Sentry cannot express the assertion at all
# (its checker follows 3xx and grades the terminal response), so Better Stack's
# `follow_redirects = false` is the whole capability.
#
# SAMPLED, not exhaustive — one probe per INDEPENDENT failure mechanism:
#
#   seo_redirect_zone_ruleset  zone ruleset rule     — cloudflare_ruleset.seo_page_redirects
#                              (seo-rulesets.tf; covers "a rules{} block was lost")
#   seo_redirect_bulk_item     explicit list item     — a literal item of
#                              cloudflare_list.legal_redirects (covers "list emptied /
#                              one item dropped")
#   seo_redirect_blog_pair     generated list item    — a local.blog_redirect_pairs
#                              expansion (covers for_each/local breakage end-to-end)
#
# THE MEMBERSHIP ASSERTION IS THE POINT, NOT A DECORATION. A probe URL that is
# not a member of the declared redirect source set watches a URL nothing else
# guards — the sample must stay anchored to the redirect set or it drifts into
# arbitrary-URL monitoring. Membership is checked PER CLASS (a zone-ruleset
# probe repointed at a bulk-list URL still satisfies "is a redirect source" but
# silently uncovers the ruleset class), and the seo_redirect_* NAME SET is an
# exact equality, so a fourth probe — declared source or not — fails here.
#
# STRUCTURE mirrors www-apex-canonicalizer.test.sh: comment-stripped,
# block-scoped reads (a neighbouring monitor legitimately carries
# `follow_redirects = true`, so a whole-file grep for the values we want is the
# concrete way this guard would go vacuous), brace-depth block extraction, and
# an exact-cardinality floor at the bottom.
#
# Case ids are S1..S<n>. Runbook:
# knowledge-base/engineering/operations/runbooks/seo-redirect-alarm.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" # apps/web-platform/infra → repo root
UPTIME_TF="$SCRIPT_DIR/uptime-alerts.tf"
REDIR_TF="$SCRIPT_DIR/seo-bulk-redirects.tf"
RULESETS_TF="$SCRIPT_DIR/seo-rulesets.tf"
APPLY_WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# The ONE place CASES moves, and it is a WRAPPER (AP-023, ADR-193 Decision #2 —
# see www-apex-canonicalizer.test.sh for the full rationale).
verdict() { # <rc> <name>
  CASES=$((CASES + 1))
  if [[ "$1" -eq 0 ]]; then pass "$2"; else fail "$2"; fi
}

eq_case() { # <want> <got> <name>
  if [[ "$2" == "$1" ]]; then
    verdict 0 "$3"
  else
    verdict 1 "$3 — want [$1], got [$2]"
  fi
}

# ---------------------------------------------------------------------------------------
# READERS — verbatim from www-apex-canonicalizer.test.sh; keep the two copies identical.
# ---------------------------------------------------------------------------------------

# Strip `#` and `//` line comments while tracking string state, so a `#` inside a quoted
# value and a `//` inside a URL both survive. Char-by-char rather than a regex.
strip_comments() { # <file>
  awk '
    {
      line = $0; out = ""; q = ""; i = 1; n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        if (q != "") {
          if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
          if (c == q) { q = "" }
          out = out c; i++; continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; out = out c; i++; continue }
        if (c == "#") { break }
        if (c == "/" && substr(line, i + 1, 1) == "/") { break }
        out = out c; i++
      }
      print out
    }
  ' "$1"
}

# Extract one `resource "<type>" "<name>" { … }` block by BRACE DEPTH.
hcl_block() { # <type> <name> <file>
  strip_comments "$3" | awk -v t="$1" -v n="$2" '
    !inb && $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1; depth = 0 }
    inb {
      print
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) { inb = 0 }
    }
  '
}

# First `key = value` in a block, anchored on the ASSIGNMENT SYNTAX. One awk process,
# never `grep … | head -1` (SIGPIPE under pipefail — see the canonicalizer's copy).
attr() { # <key> <blocktext>
  awk -v k="$1" '
    !seen && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]+$", "")
      print; seen = 1
    }
  ' <<<"$2"
}

# A bracketed list, whitespace-normalised, one-line or multi-line (values, not
# formatting — a `terraform fmt`-legal `[\n  301,\n]` reads back identically).
attr_list() { # <key> <blocktext>
  awk -v k="$1" '
    !done && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", "")
      buf = $0
      while (buf !~ /\]/ && (getline nxt) > 0) { buf = buf nxt }
      gsub(/[[:space:]]/, "", buf)
      sub(/,\]$/, "]", buf)
      print buf; done = 1
    }
  ' <<<"$2"
}

unquote() { local s="$1"; s="${s#\"}"; s="${s%\"}"; printf '%s' "$s"; }

# `grep -c` exits 1 on zero matches while still printing `0`; the `|| true` keeps the
# zero and drops the status. Heredoc input, never a pipe (SIGPIPE reason above).
count_matches() { # <ere> <text>
  grep -cE "$1" <<<"$2" || true
}

# ---------------------------------------------------------------------------------------
# THE DECLARED REDIRECT SOURCE SET — three producers, one per probe class.
#
# These are SCHEME-LESS `host/path` forms (Bulk Redirects match
# http.request.full_uri), so a probe URL participates after stripping its
# `https://` prefix.
# ---------------------------------------------------------------------------------------

# (a) Literal `source_url = "…"` items in seo-bulk-redirects.tf. Quoted-literal
# only: the dynamic block's `source_url = item.value.source` is a template
# reference, not a member of the set.
LITERAL_SOURCES="$(strip_comments "$REDIR_TF" | awk '
  match($0, /^[[:space:]]*source_url[[:space:]]*=[[:space:]]*"[^"]*"/) {
    v = substr($0, RSTART, RLENGTH)
    sub(/^.*=[[:space:]]*"/, "", v)
    sub(/"$/, "", v)
    print v
  }')"

# (b) `*_redirect_pairs` map expansions in seo-bulk-redirects.tf. Each `"<key>" =
# "<target>"` entry generates three source shapes (dir-slash, /index.html, bare)
# because full_uri matching is exact. `blog_redirect_pairs` keys are blog
# date-slugs → `soleur.ai/blog/<key>{,/,/index.html}`; any other *_redirect_pairs
# local (e.g. a future tombstone map) uses the bare source-prefix form
# `soleur.ai/<key>{,/,/index.html}`.
PAIR_SOURCES="$(strip_comments "$REDIR_TF" | awk '
  /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*_redirect_pairs[[:space:]]*=[[:space:]]*\{/ {
    inmap = 1
    isblog = ($0 ~ /blog_redirect_pairs/) ? 1 : 0
    depth = 0
  }
  inmap {
    d = gsub(/\{/, "{"); depth += d
    d = gsub(/\}/, "}"); depth -= d
    if ($0 ~ /^[[:space:]]*"[^"]+"[[:space:]]*=/) {
      k = $0
      sub(/^[[:space:]]*"/, "", k)
      sub(/"[[:space:]]*=.*$/, "", k)
      if (isblog) {
        print "soleur.ai/blog/" k "/"
        print "soleur.ai/blog/" k "/index.html"
        print "soleur.ai/blog/" k
      } else {
        print "soleur.ai/" k "/"
        print "soleur.ai/" k "/index.html"
        print "soleur.ai/" k
      }
    }
    if (depth <= 0) inmap = 0
  }')"

# (c) `http.request.uri.path eq "…"` literals inside cloudflare_ruleset.
# seo_page_redirects ONLY (block-scoped — the sibling seo_response_headers
# ruleset carries an `eq "/blog/feed.xml"` literal that is a noindex rewrite,
# not a redirect source). HCL renders the inner quotes escaped: `eq \"…\"`.
RULESET_BLOCK="$(hcl_block cloudflare_ruleset seo_page_redirects "$RULESETS_TF")"
RULESET_SOURCES="$(awk '
  {
    line = $0
    while (match(line, /http\.request\.uri\.path[[:space:]]+eq[[:space:]]+\\"[^"]+\\"/)) {
      tok = substr(line, RSTART, RLENGTH)
      sub(/\\"$/, "", tok)
      sub(/^[^"]*"/, "", tok)
      print "soleur.ai" tok
      line = substr(line, RSTART + RLENGTH)
    }
  }' <<<"$RULESET_BLOCK")"

# The seo_redirect_* monitor names actually declared — the SUT of the equality
# case, derived from the file rather than remembered.
SEO_MON_NAMES="$(strip_comments "$UPTIME_TF" | awk '
  /^resource[[:space:]]+"betteruptime_monitor"[[:space:]]+"seo_redirect_[A-Za-z0-9_]*"/ {
    n = $0
    sub(/^.*"betteruptime_monitor"[[:space:]]+"/, "", n)
    sub(/".*$/, "", n)
    print n
  }' | sort)"

EXPECTED_NAMES="$(printf '%s\n' \
  'seo_redirect_blog_pair' \
  'seo_redirect_bulk_item' \
  'seo_redirect_zone_ruleset' | sort)"

# Every betteruptime_monitor's pronounceable_name — the operator-facing string
# (the resource has no `description` field), so it is what lands in the incident
# email subject. Distinctness is asserted per-probe below.
ALL_PNS="$(strip_comments "$UPTIME_TF" | awk '
  /^resource[[:space:]]+"/ {
    inmon = ($0 ~ /^resource[[:space:]]+"betteruptime_monitor"[[:space:]]+"/) ? 1 : 0
  }
  inmon && /^[[:space:]]*pronounceable_name[[:space:]]*=/ {
    v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); sub(/[[:space:]]+$/, "", v); print v
  }')"

# The `-target=` allow-list side. Read RAW, not comment-stripped: this file is
# YAML, and a bare `https://` outside quotes would eat the rest of the line
# under the `//` rule. A `-target=` inside a comment is itself the SC2215 defect
# the workflow's own comment warns about, so raw reading is also the stricter one.
WF_TXT="$(cat "$APPLY_WF")"
TARGETED_SEO="$(awk '
  match($0, /-target=betteruptime_monitor\.seo_redirect_[A-Za-z0-9_]+/) {
    v = substr($0, RSTART, RLENGTH)
    sub(/^-target=betteruptime_monitor\./, "", v)
    print v
  }' <<<"$WF_TXT" | sort -u)"

printf 'seo-redirect-monitors guard (#8364)\n'

# ---------------------------------------------------------------------------------------
# S-VAC — the three derived source sets must be non-empty, or every membership
# case below passes vacuously the day its producer moves or renames.
# ---------------------------------------------------------------------------------------
src_vac=1; [[ -n "$RULESET_SOURCES" ]] && src_vac=0
verdict "$src_vac" "the seo_page_redirects path-literal source set extracted non-vacuously"
src_vac=1; [[ -n "$LITERAL_SOURCES" ]] && src_vac=0
verdict "$src_vac" "the explicit bulk-list source_url set extracted non-vacuously"
src_vac=1; [[ -n "$PAIR_SOURCES" ]] && src_vac=0
verdict "$src_vac" "the *_redirect_pairs expansion source set extracted non-vacuously"

# ---------------------------------------------------------------------------------------
# S-SET — the seo_redirect_* monitor set is exactly the three reviewed probes.
# Equality, not a count: a fourth probe (declared source or not) is an
# unreviewed runtime surface, and a renamed one fails here rather than
# vanishing from coverage.
# ---------------------------------------------------------------------------------------
eq_case "$EXPECTED_NAMES" "$SEO_MON_NAMES" \
  "the seo_redirect_* monitor set is exactly {blog_pair, bulk_item, zone_ruleset}"

# ---------------------------------------------------------------------------------------
# Per-probe block assertions. Each probe is checked against the declared-source
# set of ITS OWN class — a probe repointed at another class's URL still reads
# as "a redirect source" under a flat membership check while silently
# uncovering the mechanism it was sampled to watch.
# ---------------------------------------------------------------------------------------
for spec in \
  "seo_redirect_zone_ruleset RULESET" \
  "seo_redirect_bulk_item LITERAL" \
  "seo_redirect_blog_pair PAIR"; do
  name="${spec%% *}"
  cls="${spec##* }"
  case "$cls" in
    RULESET) src_set="$RULESET_SOURCES" ; cls_desc="the seo_page_redirects zone-ruleset path literals" ;;
    LITERAL) src_set="$LITERAL_SOURCES" ; cls_desc="the explicit cloudflare_list source_url items" ;;
    PAIR)    src_set="$PAIR_SOURCES"    ; cls_desc="the *_redirect_pairs expansions" ;;
  esac

  MON="$(hcl_block betteruptime_monitor "$name" "$UPTIME_TF")"

  # Dispatch: assert the extraction succeeded BEFORE reading attributes out of
  # it, so "block gone" reports as itself rather than a spray of mismatches.
  present=1
  [[ -n "$MON" ]] && present=0
  verdict "$present" "$name is declared in uptime-alerts.tf"

  # The type that makes the status-code list mean anything: `status` is
  # 2xx-only, so this mutation FAILS OPEN — green exactly when the 301 dies.
  eq_case 'expected_status_code' "$(unquote "$(attr monitor_type "$MON")")" \
    "$name is monitor_type=expected_status_code (status cannot express a 301)"

  # Exact list, not a 3xx class: a 302/307/308 is a different canonicalization
  # contract, and a 2xx admits the exact state the probe exists to catch.
  eq_case '[301]' "$(attr_list expected_status_codes "$MON")" \
    "$name expects exactly [301] (not a widened 3xx class, never a 2xx)"

  # The single token that separates this probe from a vacuous one: with
  # follow_redirects = true it grades the redirect TARGET's response — the
  # #7798 defect. Better Stack also refuses the combination (HTTP 422).
  eq_case 'false' "$(attr follow_redirects "$MON")" \
    "$name does NOT follow redirects (else it grades the target's 200)"

  # `computed` in the pinned provider: omitting it lets the API default (true)
  # apply and Better Stack REFUSES the create — "Cannot keep cookies when
  # redirecting when expecting a 3xx status code" (measured at #7798 Phase 0).
  eq_case 'false' "$(attr remember_cookies "$MON")" \
    "$name sets remember_cookies = false (vendor-required for a 3xx expectation)"

  # A paused monitor is declared, applied, and silent — the #7798 STATE.
  eq_case 'false' "$(attr paused "$MON")" \
    "$name is not paused (a paused probe is checking nothing)"

  # Under the free tier policy_id is null, so email is the ONLY channel.
  # Assert at least one channel armed rather than pinning email specifically,
  # so a future paid-tier route does not false-fail.
  armed_rc=1
  for _ch in email call sms push; do
    [[ "$(attr "$_ch" "$MON")" == "true" ]] && armed_rc=0
  done
  verdict "$armed_rc" "$name has at least one notification channel armed (a silent incident is not an alarm)"

  # A gate would leave the resource reading correct while provisioning NOTHING.
  # for_each is also unsupported by the ADR-222 reconcile parser
  # (parseMonitorBlocks throws UnresolvableDeclaration) — these blocks must
  # stay plain static declarations.
  eq_case '0' "$(count_matches '^[[:space:]]*(count|for_each)[[:space:]]*=' "$MON")" \
    "$name carries no count/for_each gate (a gated monitor is declared and never created)"

  # lifecycle{ignore_changes} would stop the pinned attributes converging while
  # still reading correct; `lifecycle {` on one line is legal HCL, so assert
  # both spellings on the comment-stripped block.
  eq_case '0' "$(count_matches '(lifecycle[[:space:]]*\{|ignore_changes[[:space:]]*=)' "$MON")" \
    "$name has no lifecycle block / ignore_changes (ignored attributes stop converging)"

  # THE MEMBERSHIP ROW. Strip the scheme and require the bare host/path to be a
  # member of this probe's OWN class set — a probe on an undeclared URL watches
  # nothing the redirect set owns, and a probe on another class's URL uncovers
  # the mechanism it was sampled for.
  probe_url="$(unquote "$(attr url "$MON")")"
  bare="${probe_url#https://}"; bare="${bare#http://}"
  member_rc=1
  grep -qxF "$bare" <<<"$src_set" && member_rc=0
  verdict "$member_rc" "$name probes a declared ${cls} source URL (member of ${cls_desc}); found [${probe_url}]"

  # pronounceable_name is the only operator-facing string on the resource:
  # empty means the alert is titled by the vendor's URL default; duplicated
  # means two alarms are indistinguishable in an inbox.
  pn="$(unquote "$(attr pronounceable_name "$MON")")"
  pn_n="$(grep -cxF "$pn" <<<"$ALL_PNS" || true)"
  pn_rc=1
  if [[ -n "$pn" && "$pn_n" == "1" ]]; then pn_rc=0; fi
  verdict "$pn_rc" "$name has a non-empty pronounceable_name distinct from every other monitor; found [${pn}]"
done

# ---------------------------------------------------------------------------------------
# S-TARGET — the apply path. apply-web-platform-infra.yml's `-target=` allow-list
# is the only route these resources reach prod through, and nothing mechanical
# forces a new monitor onto it (terraform-target-parity is one-directional over
# SSH terraform_data). Per-name presence, then set equality so a -target
# pointing at an undeclared seo_redirect_* name fails too.
# ---------------------------------------------------------------------------------------
for name in seo_redirect_zone_ruleset seo_redirect_bulk_item seo_redirect_blog_pair; do
  tgt_rc=1
  grep -qxF "$name" <<<"$TARGETED_SEO" && tgt_rc=0
  verdict "$tgt_rc" "apply-web-platform-infra.yml targets betteruptime_monitor.$name (else it never reaches prod)"
done

eq_case "$EXPECTED_NAMES" "$TARGETED_SEO" \
  "the workflow's seo_redirect_* -target set equals the declared monitor set (no orphan targets)"

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
# Exact cardinality, reported with `printf >&2` + `exit 1`, NEVER through this
# suite's own `fail` (a floor routed through `fail` runs through the machinery it
# exists to witness). Bump deliberately when you add a case; do not derive it.
printf '\n'
EXPECTED_CASES=41 # 3 source-set vacuity + 1 name-set + 11x3 per-probe + 3 targets + 1 target-set
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[FATAL] vacuity floor: %d assertion cases executed, expected exactly %d — a case was deleted, skipped, or added without updating EXPECTED_CASES\n' \
    "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi

if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '[FATAL] accounting: %d verdicts recorded across %d cases — a verdict helper was neutered or a case produced no verdict\n' \
    "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

if [[ "$FAIL" -ne 0 ]]; then
  printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"
  exit 1
fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
