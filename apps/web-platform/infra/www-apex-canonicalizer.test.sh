#!/usr/bin/env bash
# www-apex-canonicalizer.test.sh — config-drift guard for the www→apex 301 and the
# apex's binding to the Cloudflare Pages project (ADR-194, #7640).
#
# WHAT CHANGED, AND WHY THE OLD PREMISE HAD TO GO
#
# Until the Pages migration this guard asserted five literal GitHub-Pages facts: the
# apex A-record set, the www CNAME, and `plugins/soleur/docs/CNAME`, on the theory that
# GitHub Pages auto-301s every non-primary alias to the primary custom domain. That was
# true and is now false. The 301 moves to an ACCOUNT-level Cloudflare Bulk Redirect
# (`cloudflare_list.www_canonical` bound by a second rule in
# `cloudflare_ruleset.bulk_redirects`), and the apex moves to a Pages custom domain.
# A guard asserting a snapshot of the old facts would have to be deleted at cutover —
# i.e. it would protect nothing across the exact change most likely to break the site.
#
# So this rewrite quantifies over the CHAIN that produces the live behaviour, not over a
# snapshot of current facts. Five links, all asserted:
#
#   1. the redirect DECLARATION  — the `www.soleur.ai/` item in cloudflare_list.www_canonical
#   2. the BINDING CHOKEPOINT    — the second `rules {}` block in cloudflare_ruleset.bulk_redirects,
#                                  declared AFTER the legal_redirects rule. A list nothing binds
#                                  is inert; a rule ordered first silently changes which redirect
#                                  wins, because rules evaluate in declaration order, first-match-wins,
#                                  and the ten legacy /pages/legal/<slug>.html paths match BOTH
#                                  lists on the www host.
#   3. the DNS SUBSTRATE         — one apex origin record, one www record, both proxied
#   4. the CROSS-FILE DEPLOY COUPLING  — deploy-docs.yml's `--branch` == cf-pages.tf's production_branch
#   5. the CROSS-FILE PROJECT COUPLING — deploy-docs.yml's `--project-name` == the project's `name`
#
# Links 4 and 5 are two independent magic strings in HCL and YAML with no compiler between
# them, and link 4 is the highest-ranked risk in the migration plan: editing `--branch`
# leaves every other assertion green while the custom domain silently serves a stale build.
# Both are asserted by CROSS-READING the two files — never by matching two independent
# literals, which is a coupling assertion that cannot fail.
#
# STAGE-AWARE BY CONSTRUCTION, NOT BY SKIPPING
#
# The migration ships as three sequenced PRs, so this file must be green before the deploy
# path moves (PR2) and before the DNS cutover (PR3), and green after. It does that by
# resolving a STAGE and asserting the shape that stage requires — never by skipping a case.
# Every case below executes and produces exactly one verdict in every stage, because a
# skipped case is a vacuity hole and the case count is the anti-vacuity floor's only input.
#
#   stage `github-pages`  — `cloudflare_record.github_pages` still declared (pre-PR3)
#   stage `cf-pages`      — it is gone; the apex is a proxied CNAME at the Pages project
#
# WHY THE COMMENT STRIPPER EXISTS (do not remove it)
#
# Every assertion runs against a COMMENT-STRIPPED, BLOCK-SCOPED view of the file. Both
# things are load-bearing. seo-bulk-redirects.tf's own prose contains the literal text
# `include_subdomains = "enabled"` — describing the OTHER list — and cf-pages.tf's prose
# contains `--branch`. A body-grep for a bare token matches the explanatory comment written
# to explain the token, so the assertion passes by reading documentation instead of config.
# Anchors are syntax (`^\s*key\s*=`), never bare tokens, for the same reason.
#
# NOTE: the apex/www assertions grep the `cloudflare_record` resource TYPE. A future
# cloudflare/cloudflare v4→v5 bump renames `cloudflare_record` → `cloudflare_dns_record`;
# update the type anchors in `hcl_block` calls and `apex_origin_records` when that lands.
#
# Runtime drift of the 301 itself is guarded separately by
# `betteruptime_monitor.soleur_www_redirect` (uptime-alerts.tf, "soleur dot ai www redirect
# 301"; runbook knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md), which is
# the only monitor in the stack that can express it: it asserts `[301]` with
# `follow_redirects = false`. Until
# #7798 this said `sentry_uptime_monitor.soleur_www (equals 301)`, which was never true —
# Sentry follows 3xx and grades the final response, so that assertion was unsatisfiable and
# failed every check it ever ran. This file is the config-drift complement — it blocks the
# regressing PR before merge — and since #7798 it also pins the runtime alarm's own
# load-bearing attributes (see GUARD 1 below), because the alarm is itself a config artifact.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" # apps/web-platform/infra → repo root
DNS_TF="$SCRIPT_DIR/dns.tf"
PAGES_TF="$SCRIPT_DIR/cf-pages.tf"
REDIR_TF="$SCRIPT_DIR/seo-bulk-redirects.tf"
DEPLOY_WF="$REPO_ROOT/.github/workflows/deploy-docs.yml"
CNAME_FILE="$REPO_ROOT/plugins/soleur/docs/CNAME"
UPTIME_TF="$SCRIPT_DIR/uptime-alerts.tf"
SENTRY_TF="$SCRIPT_DIR/sentry/uptime-monitors.tf"
DEPLOY_SENTRY_ARRAY_SRC="$SCRIPT_DIR/cutover-verify.sh"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# The ONE place CASES moves, and it is a WRAPPER: it calls the verdict helpers rather than
# touching PASS/FAIL itself (AP-023, ADR-193 Decision #2). That is what keeps the accounting
# identity at the bottom non-tautological — stub `pass` or `fail` to a no-op and CASES keeps
# climbing while PASS+FAIL does not, so the identity fires. A counter incremented INSIDE both
# verdict helpers (the shape this file used to carry) moves WITH the verdict, so the row and
# its count vanish together and the identity holds under the exact fault it exists to catch.
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
# READERS
# ---------------------------------------------------------------------------------------

# Strip `#` and `//` line comments while tracking string state, so a `#` inside a quoted
# value (seo-bulk-redirects.tf's description carries "…, #3367, #3297.") and a `//` inside a
# URL ("https://soleur.ai/") both survive. Char-by-char rather than a regex because a regex
# that is right about quoting is longer than this loop and harder to check.
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

# Extract one `resource "<type>" "<name>" { … }` block by BRACE DEPTH from the
# comment-stripped file. Depth (not "range to the first ^}") because the redirect list nests
# item{ value{ redirect{ } } } three deep and a flat reader would truncate it at the first
# closing brace, silently making every attribute assertion below read an empty string.
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

# First `key = value` in a block, anchored on the ASSIGNMENT SYNTAX. One awk process, never
# `grep … | head -1`: under `set -o pipefail` head exits after the first line, grep dies of
# SIGPIPE (141), pipefail promotes it and `set -e` kills the run — an early match would make
# the guard abort exactly when it found what it was looking for.
attr() { # <key> <blocktext>
  awk -v k="$1" '
    !seen && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]+$", "")
      print; seen = 1
    }
  ' <<<"$2"
}

# A bracketed list, whitespace-normalised, whether it is written on one line or
# spread across several. `attr` returns the FIRST PHYSICAL LINE after the `=`, so a
# `terraform fmt`-legal `expected_status_codes = [\n    301,\n  ]` reads back as a
# bare `[` and the assertion FALSE-FAILS on a semantically identical file. That is a
# false positive waiting for an innocent reformat, and the M2 case's own claim to be
# "whitespace-normalised so the contract is about VALUES, not formatting" was untrue
# until this existed. Trailing commas are dropped so `[301,]` == `[301]`.
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

# `grep -c` exits 1 on zero matches while still printing `0`, so the `|| true` keeps the
# zero and drops the status. Heredoc input, never a pipe, for the SIGPIPE reason above.
count_matches() { # <ere> <text>
  grep -cE "$1" <<<"$2" || true
}

# Every `cloudflare_record` block that serves the apex ORIGIN: name soleur.ai AND an
# address type. The type filter is what separates the origin record from the apex's live
# Protonmail MX and four TXT records, which share `name = "soleur.ai"` and must not be
# mistaken for it (nor disturbed).
apex_origin_records() {
  strip_comments "$DNS_TF" | awk '
    !inb && /^resource[[:space:]]+"cloudflare_record"[[:space:]]+"/ {
      rn = $0
      sub(/^.*"cloudflare_record"[[:space:]]+"/, "", rn)
      sub(/".*$/, "", rn)
      inb = 1; depth = 0; nm = ""; ty = ""
    }
    inb {
      if ($0 ~ /^[[:space:]]*name[[:space:]]*=/) { nm = $0; sub(/^[^=]*=[[:space:]]*/, "", nm); sub(/[[:space:]]+$/, "", nm) }
      if ($0 ~ /^[[:space:]]*type[[:space:]]*=/) { ty = $0; sub(/^[^=]*=[[:space:]]*/, "", ty); sub(/[[:space:]]+$/, "", ty) }
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) {
        inb = 0
        if (nm == "\"soleur.ai\"" && (ty == "\"A\"" || ty == "\"CNAME\"")) { print rn }
      }
    }
  '
}

# Ordered `--flag value` / `--flag=value` occurrences. `[A-Za-z0-9._/-]+` rather than a
# negated class: `[^\n]` in a POSIX ERE is "not backslash and not the letter n", NOT "any
# char but newline", and a class that is wrong in that direction makes the extraction — and
# every assertion built on it — quietly unfalsifiable.
extract_flag() { # <flag> <text>
  awk -v f="$1" '
    {
      line = $0
      while (match(line, "--" f "(=|[[:space:]]+)[A-Za-z0-9._/-]+")) {
        v = substr(line, RSTART, RLENGTH)
        sub("^--" f "(=|[[:space:]]+)", "", v)
        print v
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' <<<"$2"
}

# ---------------------------------------------------------------------------------------
# DERIVED FACTS — read once, cross-read below
# ---------------------------------------------------------------------------------------

PROJ_BLOCK="$(hcl_block cloudflare_pages_project docs "$PAGES_TF")"
PROJ_NAME="$(unquote "$(attr name "$PROJ_BLOCK")")"
PROD_BRANCH="$(unquote "$(attr production_branch "$PROJ_BLOCK")")"
DOM_APEX="$(hcl_block cloudflare_pages_domain apex "$PAGES_TF")"
DOM_WWW="$(hcl_block cloudflare_pages_domain www "$PAGES_TF")"

LIST_BLOCK="$(hcl_block cloudflare_list www_canonical "$REDIR_TF")"
LIST_NAME="$(unquote "$(attr name "$LIST_BLOCK")")"
LEGAL_BLOCK="$(hcl_block cloudflare_list legal_redirects "$REDIR_TF")"
LEGAL_NAME="$(unquote "$(attr name "$LEGAL_BLOCK")")"
RULESET="$(hcl_block cloudflare_ruleset bulk_redirects "$REDIR_TF")"

GH_APEX_BLOCK="$(hcl_block cloudflare_record github_pages "$DNS_TF")"
if [[ -n "$GH_APEX_BLOCK" ]]; then STAGE="github-pages"; else STAGE="cf-pages"; fi

DEPLOY_TXT=""
if [[ -f "$DEPLOY_WF" ]]; then DEPLOY_TXT="$(strip_comments "$DEPLOY_WF")"; fi

printf 'www-apex-canonicalizer drift-guard (stage: %s)\n' "$STAGE"

# ---------------------------------------------------------------------------------------
# LINK 1 — the redirect DECLARATION
# ---------------------------------------------------------------------------------------

if [[ -n "$LIST_BLOCK" ]]; then
  verdict 0 "cloudflare_list.www_canonical is declared in seo-bulk-redirects.tf"
else
  verdict 1 "cloudflare_list.www_canonical is declared in seo-bulk-redirects.tf"
fi

# Exactly ONE item: zero is the deleted-declaration fault, and a second item is a divergent
# second source of truth that a first-match reader would never see.
eq_case "1" "$(count_matches '^[[:space:]]*item[[:space:]]*\{' "$LIST_BLOCK")" \
  "www_canonical declares exactly one redirect item"

eq_case 'www.soleur.ai/' "$(unquote "$(attr source_url "$LIST_BLOCK")")" \
  "www_canonical source_url is the www host root"
eq_case 'https://soleur.ai/' "$(unquote "$(attr target_url "$LIST_BLOCK")")" \
  "www_canonical target_url is the apex over https"
eq_case '301' "$(attr status_code "$LIST_BLOCK")" \
  "www_canonical redirect is a 301 (permanent, SEO-preserving)"
eq_case 'enabled' "$(unquote "$(attr subpath_matching "$LIST_BLOCK")")" \
  "www_canonical subpath_matching is enabled (whole-host, not just /)"
eq_case 'enabled' "$(unquote "$(attr preserve_path_suffix "$LIST_BLOCK")")" \
  "www_canonical preserve_path_suffix is enabled (path-preserving 301)"
# v4 string enum, not a bool. "enabled" would match hosts to the LEFT of www.soleur.ai.
eq_case 'disabled' "$(unquote "$(attr include_subdomains "$LIST_BLOCK")")" \
  "www_canonical include_subdomains is disabled (exactly one host)"

# ---------------------------------------------------------------------------------------
# LINK 2 — the BINDING CHOKEPOINT and its ORDER
# ---------------------------------------------------------------------------------------

if [[ -n "$RULESET" ]]; then
  verdict 0 "cloudflare_ruleset.bulk_redirects is declared"
else
  verdict 1 "cloudflare_ruleset.bulk_redirects is declared"
fi

eq_case "2" "$(count_matches '^[[:space:]]*rules[[:space:]]*\{' "$RULESET")" \
  "bulk_redirects binds exactly two rules (a third is an unreviewed redirect surface)"

# THE CHOKEPOINT ROW. Ordered, because rules evaluate in declaration order with
# first-match-wins: the legal rule must win for the ten legacy /pages/legal/<slug>.html
# paths, which match BOTH lists on the www host. Removing the second binding leaves the
# list declared and inert; swapping the two collapses those ten paths to the bare apex.
# Both faults leave every other assertion in this file green.
BIND_ORDER="$(awk '
  /^[[:space:]]*name[[:space:]]*=[[:space:]]*cloudflare_list\./ {
    v = $0
    sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*cloudflare_list\./, "", v)
    sub(/\.name.*$/, "", v)
    printf "%s%s", (c++ ? "," : ""), v
  }
' <<<"$RULESET")"
eq_case 'legal_redirects,www_canonical' "$BIND_ORDER" \
  "bulk_redirects binds legal_redirects FIRST and www_canonical SECOND (first-match-wins)"

# The `$name` in each rule's expression is a LITERAL that Cloudflare matches against the
# list's `name` ATTRIBUTE; only `from_list.name` creates the Terraform graph edge. Renaming
# a list without editing its expression (or the reverse) applies clean and 404s the rule.
EXPR_ORDER="$(awk '
  /^[[:space:]]*expression[[:space:]]*=/ {
    if (match($0, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
      printf "%s%s", (c++ ? "," : ""), substr($0, RSTART + 1, RLENGTH - 1)
    }
  }
' <<<"$RULESET")"
eq_case "${LEGAL_NAME},${LIST_NAME}" "$EXPR_ORDER" \
  "each rule expression names the list its from_list actually binds"

RULES_ARMED="$(count_matches '^[[:space:]]*action[[:space:]]*=[[:space:]]*"redirect"' "$RULESET")/$(count_matches '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true' "$RULESET")"
eq_case "2/2" "$RULES_ARMED" \
  "both bulk_redirects rules are action=redirect and enabled=true"

# ---------------------------------------------------------------------------------------
# LINK 3 — the DNS SUBSTRATE
# ---------------------------------------------------------------------------------------

APEX_RECS="$(apex_origin_records)"
APEX_N="$(printf '%s' "$APEX_RECS" | grep -c . || true)"
eq_case "1" "$APEX_N" \
  "dns.tf declares exactly one apex origin record (name soleur.ai, type A or CNAME)"

APEX_REC="$(awk 'NR==1{print}' <<<"$APEX_RECS")"
APEX_BLOCK=""
if [[ -n "$APEX_REC" ]]; then APEX_BLOCK="$(hcl_block cloudflare_record "$APEX_REC" "$DNS_TF")"; fi
APEX_TYPE="$(unquote "$(attr type "$APEX_BLOCK")")"
APEX_CONTENT="$(attr content "$APEX_BLOCK")"

# domains.md MANDATES proxied = true on the apex and www: it is the HSTS-preload commitment
# and, post-cutover, the edge path the Bulk Redirect runs on. Stage-independent.
eq_case 'true' "$(attr proxied "$APEX_BLOCK")" "apex origin record is proxied (HSTS mandate)"

# The apex ORIGIN, stage-resolved. STAGE is derived from whether the github_pages resource
# still exists — NOT from the apex record's own type — so a mutation that repoints the apex
# by rewriting its type as well as its content cannot re-derive the stage to match itself.
apex_shape_rc=1
apex_shape_want=""
if [[ "$STAGE" == "github-pages" ]]; then
  apex_shape_want="cloudflare_record.github_pages, type A"
  if [[ "$APEX_REC" == "github_pages" && "$APEX_TYPE" == "A" ]]; then apex_shape_rc=0; fi
else
  apex_shape_want="proxied CNAME at ${PROJ_NAME}.pages.dev"
  if [[ "$APEX_TYPE" == "CNAME" ]]; then
    if grep -Fq "${PROJ_NAME}.pages.dev" <<<"$APEX_CONTENT"; then apex_shape_rc=0; fi
    if grep -Fq 'cloudflare_pages_project.docs' <<<"$APEX_CONTENT"; then apex_shape_rc=0; fi
  fi
fi
verdict "$apex_shape_rc" "apex origin matches the ${STAGE} stage (${apex_shape_want}); found ${APEX_REC:-<none>} type ${APEX_TYPE:-<none>} content ${APEX_CONTENT:-<none>}"

WWW_BLOCK="$(hcl_block cloudflare_record www "$DNS_TF")"
WWW_TYPE="$(unquote "$(attr type "$WWW_BLOCK")")"
WWW_CONTENT="$(unquote "$(attr content "$WWW_BLOCK")")"
eq_case 'true' "$(attr proxied "$WWW_BLOCK")" "www record is proxied (HSTS mandate + edge redirect path)"

WWW_NAME="$(unquote "$(attr name "$WWW_BLOCK")")"
www_name_rc=1
if [[ "$WWW_NAME" == "www" || "$WWW_NAME" == "www.soleur.ai" ]]; then www_name_rc=0; fi
verdict "$www_name_rc" "www record resolves the www host (name is www or www.soleur.ai); found ${WWW_NAME:-<none>}"

www_shape_rc=1
www_shape_want=""
if [[ "$STAGE" == "github-pages" ]]; then
  www_shape_want='CNAME at jikig-ai.github.io'
  if [[ "$WWW_TYPE" == "CNAME" && "$WWW_CONTENT" == "jikig-ai.github.io" ]]; then www_shape_rc=0; fi
else
  # ADR-194 / plan D1 deliberately DIVERGE from Cloudflare's own www-redirect recipe: www
  # stays a proxied CNAME ATTACHED TO THE PAGES PROJECT, with the Bulk Redirect in front of
  # it ("In case of duplicates, Bulk Redirects will run in front of your Pages project").
  # The divergence buys the FAILURE MODE: if the redirect ever stops firing, www serves the
  # site (duplicate content for one monitor interval) instead of a Cloudflare 522 on an
  # HSTS-preloaded host.
  #
  # The "detection is a wash" half of this was FALSE until #7798 and is corrected here rather
  # than deleted, because it is the justification the dns.tf Camp B ruling leans on.
  # sentry_uptime_monitor.soleur_www was said to assert `equals 301` and page on EITHER
  # outcome; it asserted that and paged on NEITHER, having failed 100% of its checks since
  # the assertion landed. Detection is a wash NOW: betteruptime_monitor.soleur_www_redirect
  # catches the serves-the-site outcome in ~20 min, and the 522 fails both the Better Stack
  # monitor and sentry_uptime_monitor.soleur_www_reachability independently.
  #
  # This arm previously accepted ONLY type A ("proxied A, black-hole behind the Bulk
  # Redirect") — residue of the recipe D1 rejected, contradicting ADR-194, D1, R6 and PF9
  # in the same corpus. Corrected 2026-09-03.
  #
  # Two rejections, both load-bearing:
  #   - a surviving CNAME at jikig-ai.github.io means the cutover left www on the retired
  #     origin;
  #   - ANY `A` record, 192.0.2.1 included, means www left the project. That silently
  #     deletes the property D1 chose, AND makes the PR4 swap a ForceNew replace — a CNAME
  #     and an A cannot coexist at one name, so create_before_destroy cannot rescue it and
  #     the record is NXDOMAIN mid-apply, where the edge redirect cannot help because no
  #     request reaches the edge at all.
  # Accept branches mirror the apex arm above: the pages.dev literal OR the project reference.
  www_shape_want="proxied CNAME at the Pages project (${PROJ_NAME}.pages.dev / cloudflare_pages_project.docs) — NOT an A record, black-hole or otherwise"
  if [[ "$WWW_TYPE" == "CNAME" ]]; then
    if grep -Fq "${PROJ_NAME}.pages.dev" <<<"$WWW_CONTENT"; then www_shape_rc=0; fi
    if grep -Fq 'cloudflare_pages_project.docs' <<<"$WWW_CONTENT"; then www_shape_rc=0; fi
  fi
fi
verdict "$www_shape_rc" "www record matches the ${STAGE} stage (${www_shape_want}); found type ${WWW_TYPE:-<none>} content ${WWW_CONTENT:-<none>}"

# ---------------------------------------------------------------------------------------
# LINKS 4 & 5 — the CROSS-FILE COUPLINGS
# ---------------------------------------------------------------------------------------

# STAGE-AWARE, and the ABSENCE arm is the load-bearing one for PR1/PR2.
#
# The two `cloudflare_pages_domain` resources deliberately do NOT exist until PR3.
# Attaching a production hostname to a Pages project that has zero deployments
# would, under Hypothesis Z, move the apex origin to an empty project — and the
# apply runs on merge, so nothing could gate it. Asserting their ABSENCE here is
# what stops a future edit re-adding them to the substrate PR; asserting the pair
# once they exist is what pins the attachment when PR3 lands.
if [[ -n "$DOM_APEX" || -n "$DOM_WWW" ]]; then
  eq_case 'cloudflare_pages_project.docs.name|cloudflare_pages_project.docs.name' \
    "$(attr project_name "$DOM_APEX")|$(attr project_name "$DOM_WWW")" \
    "both pages_domain resources bind the project by REFERENCE (graph edge, not a literal)"

  eq_case 'soleur.ai|www.soleur.ai' \
    "$(unquote "$(attr domain "$DOM_APEX")")|$(unquote "$(attr domain "$DOM_WWW")")" \
    "pages_domain attaches exactly the apex and the www host"
else
  eq_case '0' \
    "$(strip_comments "$PAGES_TF" | grep -cE '^resource[[:space:]]+"cloudflare_pages_domain"' || true)" \
    "no pages_domain attaches a production hostname yet (pre-PR3): an empty Pages project must not own the apex"
fi

# `wrangler[@A-Za-z0-9._-]*` because the invocation is very likely to be VERSION-PINNED
# (`npx wrangler@4 pages deploy`). A bare `wrangler pages deploy` anchor does not match the
# pinned form, so a pinned publish would read as "no publish yet" and BOTH coupling cases
# below would pass by asserting an absence that is not there. Caught by mutation: the row
# that injects a correct pinned invocation was red for the wrong reason until this widened.
WRANGLER=0
if grep -Eq 'wrangler[@A-Za-z0-9._-]*[[:space:]]+pages[[:space:]]+deploy' <<<"$DEPLOY_TXT"; then WRANGLER=1; fi
BR_VALS="$(extract_flag branch "$DEPLOY_TXT" | sort -u | paste -sd',' -)"
PN_VALS="$(extract_flag project-name "$DEPLOY_TXT" | sort -u | paste -sd',' -)"

# THE HIGHEST-RANKED RISK IN THE MIGRATION. production_branch is the sole determinant of
# whether a deploy reaches the custom domain or is filed as a preview alias, so a `--branch`
# that stops matching it leaves every other assertion in this file green while soleur.ai
# keeps serving the last matching build. Cross-read, never two literals.
#
# Before PR2 there is no wrangler publish yet. That is asserted, not skipped: the case still
# runs and still demands the ABSENCE be total, so a stray `--branch` with no invocation to
# carry it cannot sit in the file unnoticed, and the case flips to the equality the moment
# the invocation lands.
if [[ "$WRANGLER" -eq 0 ]]; then
  eq_case "" "$BR_VALS" "deploy-docs.yml has no wrangler publish yet (pre-PR2) and carries no orphan --branch"
  eq_case "" "$PN_VALS" "deploy-docs.yml has no wrangler publish yet (pre-PR2) and carries no orphan --project-name"
else
  eq_case "$PROD_BRANCH" "$BR_VALS" "deploy-docs.yml --branch equals cf-pages.tf production_branch"
  eq_case "$PROJ_NAME" "$PN_VALS" "deploy-docs.yml --project-name equals cloudflare_pages_project.docs name"
fi

# ---------------------------------------------------------------------------------------
# The GitHub Pages custom-domain file. It no longer PRODUCES the 301 once the Bulk Redirect
# is live, but it is still the live mechanism until PR3 lands, and it must keep reading the
# apex throughout — flipping it to www inverts the canonical direction with zero TF drift.
# ---------------------------------------------------------------------------------------
cname_rc=1
cname_got="<missing>"
if [[ -f "$CNAME_FILE" ]]; then
  cname_got="$(tr -d '[:space:]' <"$CNAME_FILE")"
  if [[ "$cname_got" == "soleur.ai" ]]; then cname_rc=0; fi
fi
verdict "$cname_rc" "plugins/soleur/docs/CNAME is the apex, not www; found ${cname_got}"

# ---------------------------------------------------------------------------------------
# GUARD 1 — the RUNTIME alarm for the 301 (#7798)
# ---------------------------------------------------------------------------------------
#
# Everything above asserts the redirect is DECLARED correctly. This section asserts the
# thing that notices when the declaration stops producing the behaviour — and it exists
# because the alarm that used to hold that role never worked.
#
# `sentry_uptime_monitor.soleur_www` asserted `equals 301` on https://www.soleur.ai/.
# Sentry's uptime checker always follows 3xx and evaluates assertions against the FINAL
# response, so it graded `equals 301` against the apex's 200 — an assertion it cannot
# satisfy. Measured 2026-09-07: the 10 most recent checks were 10/10 failing.
#
# The property moved to `betteruptime_monitor.soleur_www_redirect` — operator-facing name
# "soleur dot ai www redirect 301" — because Better Stack is the only vendor in the stack
# that can express it (`follow_redirects = false`).
#
# WHAT THESE CASES PIN, AND WHY THAT SET CHANGED AT REVIEW. The first draft pinned
# `follow_redirects`, `expected_status_codes` and `remember_cookies` — and Better Stack
# REFUSES all three wrong combinations at create time with HTTP 422, so those cases were
# belt-and-braces over a vendor-enforced invariant. Meanwhile every attribute with NO
# vendor backstop was unasserted, and ten one-line edits were measured to leave the suite
# fully green while silently killing the alarm. Two of them reproduce #7798 exactly:
#   - `url` repointed at the apex  -> no-follow + [301] against a 200: fails forever.
#   - `monitor_type = "status"`    -> the status-code list goes inert and the monitor
#                                     reports GREEN precisely when www serves the site
#                                     instead of redirecting. Fails OPEN.
# and a third, `paused = true`, reproduces the #7798 STATE: declared correctly, checking
# nothing, reporting nothing. The set below is derived from "what can make this alarm
# ineffective", not from "what was I just looking at".
#
# BLOCK-SCOPED, never a whole-file grep. `uptime-alerts.tf` contains two monitors that
# legitimately set `follow_redirects = true`, so a file-level grep for the value we want is
# satisfied by a neighbouring resource — that is the concrete way this guard goes vacuous.
#
# Case ids are W1..Wn. They are deliberately NOT M-numbered: www-apex-canonicalizer-mutation.test.sh
# already owns M1..M10 for the redirect-chain rows, and two disjoint numbering spaces across
# a guard and its own battery is a reader trap.
#
# Runbook: knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md
# Rationale: ADR-204.
WWW_MON="$(hcl_block betteruptime_monitor soleur_www_redirect "$UPTIME_TF")"

# W1 — the guard's own dispatch. A guard that passes when its subject is ABSENT asserts
# nothing at all, and the extractor returns an empty string for a renamed or deleted block.
# Assert the extraction succeeded BEFORE reading any attribute out of it, so "block gone"
# reports as itself rather than as a spray of confusing attribute mismatches.
mon_present=1
if [[ -n "$WWW_MON" ]]; then mon_present=0; fi
verdict "$mon_present" "betteruptime_monitor.soleur_www_redirect is declared in uptime-alerts.tf (the www 301 has a runtime alarm at all)"

# W2 — THE SUBJECT. Repointing this at the apex leaves every other assertion true while the
# monitor watches a URL that never 301s. Vendor-unenforced; nothing else catches it.
eq_case 'https://www.soleur.ai/' "$(unquote "$(attr url "$WWW_MON")")" \
  "soleur_www_redirect probes www, not some other host (repointing it reproduces #7798)"

# W3 — the type that makes the status-code list mean anything. `status` is 2xx-only, so this
# mutation is the FAIL-OPEN one: the monitor goes green exactly when www stops redirecting.
eq_case 'expected_status_code' "$(unquote "$(attr monitor_type "$WWW_MON")")" \
  "soleur_www_redirect is monitor_type=expected_status_code (status is 2xx-only and cannot express a 301)"

# W4 — the single token that separates this monitor from the broken one. Better Stack also
# refuses it at create time (422), so this fails the PR rather than a production apply.
eq_case 'false' "$(attr follow_redirects "$WWW_MON")" \
  "soleur_www_redirect does NOT follow redirects (else it asserts against the apex 200 — the #7798 defect)"

# W5 — exact list, not a 3xx class: a 302/307/308 is a different canonicalization contract,
# and admitting a 2xx admits the exact state this monitor exists to catch. Read via attr_list
# so a fmt-legal multi-line list is accepted (values, not formatting).
eq_case '[301]' "$(attr_list expected_status_codes "$WWW_MON")" \
  "soleur_www_redirect expects exactly [301] (not a widened 3xx class, and never a 2xx)"

# W6 — Phase 0 finding. `remember_cookies` is `computed` in the pinned provider, so OMITTING
# it sends nothing, the API default (true) applies, and Better Stack REFUSES the create:
# HTTP 422 "Cannot keep cookies when redirecting when expecting a 3xx status code".
eq_case 'false' "$(attr remember_cookies "$WWW_MON")" \
  "soleur_www_redirect sets remember_cookies = false (required by the vendor for a 3xx expectation)"

# W7 — a monitor that is not checking is indistinguishable from one with nothing to report.
# This is the #7798 STATE in one token, and no vendor call rejects it.
eq_case 'false' "$(attr paused "$WWW_MON")" \
  "soleur_www_redirect is not paused (a paused monitor is declared, applied, and silent)"

# W8 — delivery. Under the free tier `policy_id` is null, so `email` is the ONLY channel:
# an incident opens and nobody is told. Assert at least one channel is armed rather than
# pinning `email` specifically, so a future paid-tier route does not false-fail.
armed_rc=1
for _ch in email call sms push; do
  [[ "$(attr "$_ch" "$WWW_MON")" == "true" ]] && armed_rc=0
done
verdict "$armed_rc" "soleur_www_redirect has at least one notification channel armed (an incident nobody is told about is not an alarm)"

# W9 — the timer dns.tf's Camp B ruling was re-grounded on. That block says "do not widen it
# without revisiting this ruling"; before this case, nothing enforced it.
eq_case '1200' "$(attr confirmation_period "$WWW_MON")" \
  "soleur_www_redirect keeps confirmation_period = 1200 (dns.tf's Camp B acceptance is re-grounded on this exact bound)"

# W10 — a gate would leave the resource reading correct while provisioning NOTHING. Both
# keywords: `for_each = {}` is the same defect as `count = 0`, and the file's own
# betteruptime_policy is count-gated on the paid-tier flag, so it is the locally idiomatic
# next edit. Asserted as an absence, because no attribute-VALUE check can catch it.
eq_case '0' "$(count_matches '^[[:space:]]*(count|for_each)[[:space:]]*=' "$WWW_MON")" \
  "soleur_www_redirect carries no count/for_each gate (a gated monitor is declared and never created)"

# W11 — `ignore_changes` would stop the pinned attributes converging: the guard keeps reading
# them out of a file Terraform has been told to ignore. This file already contains two
# `ignore_changes` precedents, so a reader has an in-file invitation.
# NOT line-anchored, deliberately: `lifecycle { ignore_changes = [...] }` written on
# ONE line is legal HCL and evaded the anchored form — caught by this guard's own
# mutation battery (W11 survived until this widened). The block is comment-stripped
# before it gets here, so a bare `ignore_changes =` token can only be the attribute.
eq_case '0' "$(count_matches 'ignore_changes[[:space:]]*=' "$WWW_MON")" \
  "soleur_www_redirect has no lifecycle ignore_changes (ignored attributes stop converging while still reading correct)"

# W12 — the ONLY operator-facing string on this resource: betteruptime_monitor has no
# `description` field, so pronounceable_name is what lands in the incident email subject.
# Empty means the alert is titled by the vendor's URL default; equal to a sibling's means the
# two www alarms are indistinguishable in an inbox.
#
# The sibling set is derived from the file rather than remembered — and its NON-EMPTINESS is
# asserted, because `grep -qxF` against an empty set cannot fail, which would make the
# distinctness half vacuous the moment the siblings lose their names. `rn` is reset at EVERY
# resource header, not only at betteruptime_monitor ones, so a pronounceable_name on a later
# resource of another type is not misattributed to this block.
WWW_PN="$(unquote "$(attr pronounceable_name "$WWW_MON")")"
SIBLING_PNS="$(strip_comments "$UPTIME_TF" | awk '
  /^resource[[:space:]]+"/ {
    rn = ""
    if ($0 ~ /^resource[[:space:]]+"betteruptime_monitor"[[:space:]]+"/) {
      rn = $0; sub(/^.*"betteruptime_monitor"[[:space:]]+"/, "", rn); sub(/".*$/, "", rn)
    }
  }
  rn != "" && rn != "soleur_www_redirect" && /^[[:space:]]*pronounceable_name[[:space:]]*=/ {
    v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); sub(/[[:space:]]+$/, "", v); print v
  }
')"
sib_n="$(printf '%s\n' "$SIBLING_PNS" | grep -c . || true)"
eq_case '2' "$sib_n" \
  "the sibling pronounceable_name set is non-empty (distinctness over an empty set is vacuous); found ${sib_n}"

pn_rc=1
if [[ -n "$WWW_PN" ]] && ! grep -qxF "$WWW_PN" <<<"$SIBLING_PNS"; then pn_rc=0; fi
verdict "$pn_rc" "soleur_www_redirect has a pronounceable_name distinct from every sibling monitor; found [${WWW_PN}]"

# W14 — cross-read: cutover-verify.sh's SENTRY_MONITORS array must name exactly the Sentry
# uptime monitors that are declared. Added at #7798 REVIEW, because a comment in
# cutover-verify.sh already claimed this guard performed this check and it did not — a
# correctness claim resting on a gate that did not exist, which is the defect class this
# whole PR is about. The two are magic strings in HCL and bash with no compiler between them,
# and the #7798 rename moved one of them.
SENTRY_NAMES="$(strip_comments "$SENTRY_TF" \
  | awk '/^[[:space:]]*name[[:space:]]*=/ { v=$0; sub(/^[^=]*=[[:space:]]*/,"",v); gsub(/"/,"",v); sub(/[[:space:]]+$/,"",v); print v }' \
  | sort -u | paste -sd',' -)"
ARRAY_NAMES="$(strip_comments "$DEPLOY_SENTRY_ARRAY_SRC" \
  | awk '/^SENTRY_MONITORS=\(/ { v=$0; sub(/^SENTRY_MONITORS=\(/,"",v); sub(/\).*$/,"",v); print v }' \
  | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd',' -)"
# Both operands non-empty, or the equality is the vacuous "" == "" this case exists
# to avoid. Asserted rather than assumed: a broken extractor on BOTH sides passes.
sentry_n="$(printf '%s' "$SENTRY_NAMES" | tr ',' '\n' | grep -c . || true)"
eq_case '4' "$sentry_n" \
  "the sentry_uptime_monitor name set extracted non-vacuously (found ${sentry_n})"
eq_case "$SENTRY_NAMES" "$ARRAY_NAMES" \
  "cutover-verify.sh SENTRY_MONITORS matches the sentry_uptime_monitor name set byte-for-byte"

# W15/W16 — the bracket must not come back, asserted on the PROPERTY rather than on the
# deleted step's spelling. deploy-docs.yml used to PAUSE the Sentry www monitor around each
# publish and resume it after, to hide a deploy-window false page under the old `equals 301`
# assertion. Two reasons that must stay gone:
#
#   1. A failed resume left the monitor paged-off, and the bracket's own comment recorded
#      that the next apply-sentry-infra.yml run was NOT a guaranteed self-heal.
#   2. Pausing halts checks, so Sentry resolves the open downtime issue and a fresh one opens
#      after — laundering the alarm's own failure record. The timestamps supporting that
#      reading are in the #7798 spec's phase-0-measurements.md; it is an inference from the
#      correlation, not a directly observed vendor behaviour.
#
# ANCHORED ON THE CAPABILITY, NOT THE WORDING. The first draft matched the two literal
# strings the deleted steps happened to use, and a reworded reintroduction — carrying the
# credential back — passed cleanly. These two assert what the bracket NEEDED: a Sentry
# credential in this workflow, and a mutating call to the monitor API.
eq_case '0' "$(count_matches 'secrets\.SENTRY_' "$DEPLOY_TXT")" \
  "deploy-docs.yml references no SENTRY_* secret (the pause/resume bracket cannot return without one)"
eq_case '0' "$(count_matches '(detectors/|uptime\.betterstack\.com).*(-X[[:space:]]*(PUT|PATCH|POST)|enabled|paused)|-X[[:space:]]*(PUT|PATCH)[^\n]*(detectors/|monitors/)' "$DEPLOY_TXT")" \
  "deploy-docs.yml makes no monitor-mutating API call (CI must not toggle vendor alarm state)"

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
#
# Both report with `printf >&2` + `exit 1`, NEVER through this suite's own `fail`. A floor
# routed through `fail` runs THROUGH the machinery it exists to witness: neuter `fail` and
# every row goes quiet AND so does the detector, and the suite prints a total and exits 0.
#
# The floor is an EXACT cardinality, not a lower bound. Every case above executes in every
# stage, so the count is stage-independent, and an exact match catches a case that was
# deleted AND a case that was added without being reviewed. Bump this deliberately when you
# add a case; do not derive it from anything this file computes.
printf '\n'

# Stage-dependent by construction, and each arm is a LITERAL — not derived from
# anything this file computes, which would make the floor a tautology. Pre-PR3 the
# pages_domain pair is replaced by a single absence assertion, so the count is one
# lower. Bump the matching arm deliberately when you add a case.
if [[ -n "$DOM_APEX" || -n "$DOM_WWW" ]]; then
  EXPECTED_CASES=41   # PR3 onward: the two pages_domain couplings are live, + 17 Guard 1 (#7798)
else
  EXPECTED_CASES=40   # PR1/PR2: one absence assertion stands in for that pair, + 17 Guard 1 (#7798)
fi
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
