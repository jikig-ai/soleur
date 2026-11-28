# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S6 (argv-bearer sweep, Guard 3, #9757): no `htpasswd` invocation carries a password on argv.
#
# PROPERTY. No tracked, non-test, non-comment `htpasswd` invocation passes a password as an argument: no option cluster holds a lowercase `b`
# (`-b` is the password-on-the-command-line flag; `-B` is bcrypt and is fine, in any order and combination: -Bin, -iB, -vi pass; -Bbn, -Bb, -bi,
# -vb, -nbB and a split `-B -b` fail).
#
# DERIVATION. `git grep` (tracked AND untracked, so an uncommitted file is seen) over apps/, scripts/ and .github/, minus `*.test.sh` and `*.md`,
# for `htpasswd` followed by an option token; whole-line comments and trailing YAML comments (` # ...`) are dropped before the invocation is
# looked for. The scan is a FUNCTION OF A ROOT, so the mutation rows run the same text on a scratch repository. NOT COVERED, named: an invocation
# through a variable, an `eval` or a `bash -c` string whose `htpasswd` is not followed by an option on the same line, and an invocation hidden
# behind ` # ` inside a quoted string earlier on the same line.
#
# NO RESIDUAL. The registry template (apps/web-platform/infra/cloud-init-registry.yml: the `_htp_verify` probe and the two boot-step htpasswd lines)
# was carried here as an explicit residual allowlist (S6_ALLOW) while its conversion waited for its own PR, because merging that file replaces the
# production registry host unattended. #10119 converted all three sites and DELETED the allowlist: S6_ALLOW is empty and S6_ALLOW_CEIL is 0, so a site
# that goes back to argv form is `bad:<file>` with no entry to hide behind. The allowlist machinery stays (an entry the scan no longer sees is RED,
# "stale-allowlist"; the ceiling row pins the entry count) so growing it again is an edit to literals this stage asserts, never a quiet addition.
#
# FLOOR. The scan sees 4 invocations in 2 files on the real tree: 1 in the workflow + 3 in the registry template (the boot step's two entries and the
# probe), all stdin form. The floor is 4 sites in 2 files; it did not move when the allowlist was deleted.
# A scan that sees fewer (renamed binary, moved roots, a broken regex) is RED, never a clean bill.
#
# The executable rows run the REAL step text (PyYAML-extracted from the workflow, up to and including the htpasswd line) under
# `bash --noprofile --norc -eo pipefail` against a REFUSING stub `docker` that accepts exactly `run --rm -i httpd:2.4-alpine htpasswd -Bin <user>`
# and reads stdin: without docker's own `-i` docker forwards nothing and the hash covers an EMPTY password, and the step is dispatch-only, so
# nothing else would notice. The real-binary round trip lives in apps/web-platform/infra/htpasswd-stdin.test.sh (needs docker; this battery does not).
# All passwords are synthesized or per-run throwaways; no value is printed.
# =====================================================================================
S6_WF=".github/workflows/apply-web-platform-infra.yml"
S6_REG="apps/web-platform/infra/cloud-init-registry.yml"
S6_SITE_FLOOR=4; S6_FILE_FLOOR=2; S6_ALLOW_CEIL=0
S6_WF_LINE="$(cat <<'S6EOF'
printf '%s' "$RP" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin "$RU" > "${RUNNER_TEMP}/zot/htpasswd"
S6EOF
)"
# The residual allowlist: <file><TAB><the whole stripped line>. EMPTY since #10119 deleted the three registry entries; it shrinks by deletion only.
S6_ALLOW=()
# The three registry-template sites, by identity (file and the whole stripped line), all stdin form.
S6_REG_PROBE="printf '%s' \"\$2\" | htpasswd -vi /etc/zot/htpasswd \"\$1\" >/dev/null 2>&1"
S6_REG_PULL="printf '%s' \"\$ZOT_PULL_TOKEN\" | htpasswd -Bin '\${zot_pull_user}'  > /etc/zot/htpasswd"
S6_REG_PUSH="printf '%s' \"\$ZOT_PUSH_TOKEN\" | htpasswd -Bin '\${zot_push_user}' >> /etc/zot/htpasswd"
S6_ERE='(^|[^[:alnum:]_./-])htpasswd[[:space:]]+-[A-Za-z]'
S6_ERE_INV='(^|[^[:alnum:]_./-])htpasswd([[:space:]]+-[A-Za-z]+)+'

# One TSV record per invocation: file, line number, the option tokens, the whole stripped code line.
s6_scan() { # <root>
  local root="$1" rec file rest ln text body code m
  while IFS= read -r rec; do
    file="${rec%%:*}"; rest="${rec#*:}"; ln="${rest%%:*}"; text="${rest#*:}"
    body="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$text")"
    [[ "$body" == '#'* ]] && continue
    code="$(sed -E 's/[[:space:]]#.*$//; s/[[:space:]]+$//' <<<"$body")"
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      printf '%s\t%s\t%s\t%s\n' "$file" "$ln" "$(sed -E 's/^.*htpasswd[[:space:]]+//' <<<"$m")" "$code"
    done < <(grep -oE -e "$S6_ERE_INV" <<<"$code")
  done < <(git -C "$root" grep -nIE --untracked -e "$S6_ERE" -- apps scripts .github ':!*.test.sh' ':!*.md' 2>/dev/null)
}
# The verdict over a root. Sets S6_J_REASONS (empty = GREEN), S6_J_SITES, S6_J_FILES. Reasons: floor, bad:<file>, workflow-identity, stale-allowlist.
S6_J_REASONS=""; S6_J_SITES=0; S6_J_FILES=0
s6_judge() { # <root>
  local root="$1" scan file ln opts code a seen
  scan="$(s6_scan "$root")"
  S6_J_REASONS=""
  S6_J_SITES="$(grep -c . <<<"$scan" || true)"
  S6_J_FILES="$(cut -f1 <<<"$scan" | sort -u | grep -c . || true)"
  [[ "$S6_J_SITES" -ge "$S6_SITE_FLOOR" && "$S6_J_FILES" -ge "$S6_FILE_FLOOR" ]] || S6_J_REASONS+=" floor"
  while IFS=$'\t' read -r file ln opts code; do
    [[ -n "$file" ]] || continue
    if [[ "$opts" == *b* ]]; then
      seen=0; for a in "${S6_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'"$code" ]] && seen=1; done
      [[ "$seen" == 1 ]] || S6_J_REASONS+=" bad:$file"
    fi
  done <<<"$scan"
  [[ "$(awk -F'\t' -v f="$S6_WF" -v c="$S6_WF_LINE" '$1 == f { n++; if ($4 != c) o++ } END { print n + 0 "/" o + 0 }' <<<"$scan")" == "1/0" ]] || S6_J_REASONS+=" workflow-identity"
  for a in "${S6_ALLOW[@]}"; do
    grep -qxF -- "$a" < <(awk -F'\t' '{ print $1 "\t" $4 }' <<<"$scan") || S6_J_REASONS+=" stale-allowlist"
  done
  S6_J_REASONS="${S6_J_REASONS# }"
}
S6="$TMPD/s6"; assert_fixture_dir "$S6"; mkdir -p "$S6/base" "$S6/mut" "$S6/bin" "$S6/real"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S6/base" || exit 1; git -C "$S6/base" init -q ) \
  || fatal "S6 could not create the scratch repository"
for f in "$S6_WF" "$S6_REG"; do mkdir -p "$S6/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S6/base/$f"; done
# A fresh copy of the scratch tree per mutant (the scan is the SAME function over a root, so a mutant and the real tree are judged by one text).
s6_fresh() { # <name>: prints the new root
  local d="$S6/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S6/base" "$d" && printf '%s' "$d"
}
s6_put() { # <root> <relative path> <line>: write one line into a scratch tree
  assert_fixture_dir "$1"; printf '%s\n' "$3" > "$1/$2"
}
s6_edit() { # <file> <old> <new> [<count>]: replace exactly <count> (default 1) occurrences, rc 1 when the edit did not land
  python3 -I -c '
import sys
p, old, new, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
t = open(p).read()
if t.count(old) != n: sys.exit(1)
open(p, "w").write(t.replace(old, new))' "$1" "$2" "$3" "${4:-1}"
}

# --- the real tree --------------------------------------------------------------------
s6_judge "$REPO_ROOT"
S6_REAL_REASONS="$S6_J_REASONS"; S6_REAL_SITES="$S6_J_SITES"; S6_REAL_FILES="$S6_J_FILES"
S6_REAL_SCAN="$(s6_scan "$REPO_ROOT")"
if [[ -z "$S6_REAL_REASONS" ]]; then row "S6 Guard 3: no tracked htpasswd invocation outside the residual allowlist carries a password on argv ($S6_REAL_SITES invocations in $S6_REAL_FILES files, derived by git grep over apps/ scripts/ .github/)" ok
else row "S6 Guard 3: an htpasswd invocation carries a password on argv outside the residual allowlist, or the workflow site or an allowlist entry drifted" fail "reasons='$S6_REAL_REASONS' sites=$S6_REAL_SITES files=$S6_REAL_FILES"; fi
if [[ "$S6_REAL_SITES" -ge "$S6_SITE_FLOOR" && "$S6_REAL_FILES" -ge "$S6_FILE_FLOOR" && "$S6_REAL_SITES" -eq 4 && "$S6_REAL_FILES" -eq 2 ]]; then row "S6 floor: the scan saw $S6_REAL_SITES invocations in $S6_REAL_FILES files (workflow 1 + registry template 3: the floor is $S6_SITE_FLOOR sites in $S6_FILE_FLOOR files)" ok
else row "S6 floor: the scan saw an unexpected population (the floor is $S6_SITE_FLOOR sites in $S6_FILE_FLOOR files; exactly 4 in 2 are expected)" fail "sites=$S6_REAL_SITES files=$S6_REAL_FILES"; fi
# One anchored row per site: identity (file and the whole stripped line), never only a count.
s6_site_is() { # <file> <whole line> <expect-b: 0|1>: exactly one record of <file> has that line, and its options hold a lowercase b iff <expect-b>
  awk -F'\t' -v f="$1" -v c="$2" -v b="$3" '$1 == f { n++; if ($4 == c && (($3 ~ /b/) ? 1 : 0) == b) ok++ } END { exit !(n == 1 && ok == 1) }' <<<"$S6_REAL_SCAN"
}
s6_site_in_file_is() { # <file> <whole line> <expect-b>: the file holds exactly one record of that line (the file may hold other sites)
  awk -F'\t' -v f="$1" -v c="$2" -v b="$3" '$1 == f && $4 == c { n++; if ((($3 ~ /b/) ? 1 : 0) == b) ok++ } END { exit !(n == 1 && ok == 1) }' <<<"$S6_REAL_SCAN"
}
if s6_site_is "$S6_WF" "$S6_WF_LINE" 0; then row "S6 site (workflow): the registry-luks-recut rehearsal step's single htpasswd invocation is exactly the stdin form with docker's own -i, and its options hold no b" ok
else row "S6 site (workflow): the rehearsal step's htpasswd line is not the exact stdin form (printf '%s' \"\$RP\" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin \"\$RU\" > ...)" fail "records=$(awk -F'\t' -v f="$S6_WF" '$1 == f' <<<"$S6_REAL_SCAN" | cut -f2,3 | tr '\t\n' ' :')"; fi
S6_SITE_I=0
for a_line in "$S6_REG_PROBE" "$S6_REG_PULL" "$S6_REG_PUSH"; do
  S6_SITE_I=$((S6_SITE_I + 1))
  case "$S6_SITE_I" in 1) a_name="the _htp_verify probe (htpasswd -vi, password piped from printf)" ;; 2) a_name="the boot step's pull entry (htpasswd -Bin, creates the file)" ;; *) a_name="the boot step's push entry (htpasswd -Bin, appends)" ;; esac
  if s6_site_in_file_is "$S6_REG" "$a_line" 0; then row "S6 registry site $S6_SITE_I (cloud-init-registry.yml): $a_name is the stdin form, present exactly once, and its options hold no b" ok
  else row "S6 registry site $S6_SITE_I (cloud-init-registry.yml): $a_name is not present exactly once in its stdin form" fail "line=$(cut -c1-70 <<<"$a_line")"; fi
done
# The ceiling is a predicate over a count so a grow-by-one mutant can be judged by the SAME function: 0 passes, 1 must not.
s6_ceiling_ok() { [[ "$1" -eq "$S6_ALLOW_CEIL" && "$S6_ALLOW_CEIL" -eq 0 ]]; }
if s6_ceiling_ok "${#S6_ALLOW[@]}" && ! s6_ceiling_ok $((${#S6_ALLOW[@]} + 1)); then row "S6 allowlist ceiling: the residual allowlist is EMPTY (ceiling $S6_ALLOW_CEIL; #10119 deleted the three registry entries), and a grow-by-one allowlist is judged RED by the same predicate" ok
else row "S6 allowlist ceiling: the residual allowlist is not empty, or the ceiling predicate accepts a grown allowlist" fail "entries=${#S6_ALLOW[@]} ceiling=$S6_ALLOW_CEIL"; fi

# --- mutations, on a scratch repository ----------------------------------------------------
# M1 reintroduce the argv form in the workflow site.
S6_M1="$(s6_fresh m1)"
if s6_edit "$S6_M1/$S6_WF" 'htpasswd -Bin "$RU"' 'htpasswd -Bbn "$RU" "$RP"'; then
  s6_judge "$S6_M1"
  if [[ "$S6_J_REASONS" == *"bad:$S6_WF"* && "$S6_J_REASONS" == *workflow-identity* ]]; then row "S6 mutation 1: reintroducing -Bbn in the workflow site is RED (an argv password outside the allowlist, and the site's identity row)" ok
  else row "S6 mutation 1: the workflow site reverted to -Bbn is not caught" fail "reasons='$S6_J_REASONS'"; fi
else row "S6 mutation 1: the -Bin -> -Bbn edit did not land on the workflow (the converted site is missing)" fail "no 'htpasswd -Bin \"\$RU\"' once in the workflow"; fi
# M2 a compliant fifth site is GREEN; a non-compliant one in a DIFFERENT file then makes it RED (identity, not a count: five sites in four files).
S6_M2="$(s6_fresh m2)"; assert_fixture_dir "$S6_M2"; mkdir -p "$S6_M2/scripts" "$S6_M2/apps/web-platform/infra"
printf '%s\n' "printf '%s' \"\$p\" | htpasswd -Bin svc > \"\$out\"" > "$S6_M2/scripts/zz-ok-fifth.sh"
s6_judge "$S6_M2"; S6_M2_OK="$S6_J_REASONS"; S6_M2_SITES="$S6_J_SITES"
s6_put "$S6_M2" scripts/zz-bad-sixth.sh 'htpasswd -Bbn svc "$p"'
s6_judge "$S6_M2"
if [[ -z "$S6_M2_OK" && "$S6_M2_SITES" -eq $((S6_REAL_SITES + 1)) && "$S6_J_REASONS" == *"bad:scripts/zz-bad-sixth.sh"* && "$S6_J_SITES" -eq $((S6_REAL_SITES + 2)) ]]; then
  row "S6 mutation 2: a compliant fifth site is GREEN (and is seen), a non-compliant sixth site in a different file is RED" ok
else row "S6 mutation 2: the fifth/sixth-site pair is judged wrong" fail "fifth='$S6_M2_OK' sites=$S6_M2_SITES sixth='$S6_J_REASONS' sites=$S6_J_SITES"; fi
# M3 a fourth argv invocation inside the ALLOWLISTED file (a different line) is RED: the allowlist is by line identity, not by file.
S6_M3="$(s6_fresh m3)"; assert_fixture_dir "$S6_M3"
printf '%s\n' "    htpasswd -Bbn 'extra' \"\$EXTRA_TOKEN\" >> /etc/zot/htpasswd" >> "$S6_M3/$S6_REG"
s6_judge "$S6_M3"
if [[ "$S6_J_REASONS" == *"bad:$S6_REG"* && "$S6_J_SITES" -eq $((S6_REAL_SITES + 1)) ]]; then row "S6 mutation 3: a fourth argv htpasswd line added to the registry file is RED (a site is judged by its line, never by its file)" ok
else row "S6 mutation 3: an extra argv line in the allowlisted file slips through" fail "reasons='$S6_J_REASONS' sites=$S6_J_SITES"; fi
# M4 every spelling of the password-on-argv option cluster is RED, in any order and combination.
S6_M4="$(s6_fresh m4)"; assert_fixture_dir "$S6_M4"; mkdir -p "$S6_M4/scripts"; S6_M4_MISS=""
for v in '-Bb' '-bB' '-bi' '-vb' '-nbB' '-Bbn' '-bBn' '-B -b' '-i -vb' '-vb -B'; do
  printf '%s\n' "htpasswd $v svc \"\$p\" > \"\$out\"" > "$S6_M4/scripts/zz-variant.sh"
  s6_judge "$S6_M4"; [[ "$S6_J_REASONS" == *"bad:scripts/zz-variant.sh"* ]] || S6_M4_MISS+=" $v"
done
if [[ -z "$S6_M4_MISS" ]]; then row "S6 mutation 4: each option cluster holding a b (-Bb -bB -bi -vb -nbB -Bbn -bBn, a split -B -b, -i -vb, -vb -B) is RED" ok
else row "S6 mutation 4: an option cluster holding a b is not caught" fail "missed:$S6_M4_MISS"; fi
# M5 the scanned binary renamed in the scratch tree: the scan sees 0 sites and must be RED, never a clean bill.
S6_M5="$(s6_fresh m5)"
for f in "$S6_WF" "$S6_REG"; do sed -i -E 's/htpasswd([[:space:]]+-)/htpassw0\1/g' "$S6_M5/$f"; done
s6_judge "$S6_M5"
if [[ "$S6_J_SITES" -eq 0 && "$S6_J_REASONS" == *floor* ]]; then row "S6 mutation 5: with the scanned binary renamed the scan sees 0 sites and the floor is RED" ok
else row "S6 mutation 5: a scan that sees nothing is not RED" fail "sites=$S6_J_SITES reasons='$S6_J_REASONS'"; fi
# M6 an allowlist entry the scan no longer sees is RED. The real allowlist is empty now, so the mutant INJECTS an entry for a line the scan cannot see (the
# retired argv probe line); a compliant extra site keeps the floor from being what trips.
S6_M6="$(s6_fresh m6)"; assert_fixture_dir "$S6_M6"; mkdir -p "$S6_M6/scripts"
printf '%s\n' "printf '%s' \"\$p\" | htpasswd -Bin svc > \"\$out\"" > "$S6_M6/scripts/zz-ok.sh"
S6_ALLOW_SAVE=("${S6_ALLOW[@]}")
S6_ALLOW+=("$S6_REG	htpasswd -vb /etc/zot/htpasswd \"\$1\" \"\$2\" >/dev/null 2>&1")
s6_judge "$S6_M6"; S6_M6_R="$S6_J_REASONS"
S6_ALLOW=("${S6_ALLOW_SAVE[@]}")
if [[ "$S6_M6_R" == "stale-allowlist" ]]; then row "S6 mutation 6: an allowlist entry for a site that is gone (the retired -vb probe line) is RED (stale-allowlist, and nothing else)" ok
else row "S6 mutation 6: a stale allowlist entry is not (only) reported" fail "reasons='$S6_M6_R'"; fi
# M8 reintroduce each of the three registry sites in argv form, one at a time, with NO allowlist to hide behind: each is RED by its own identity.
S6_M8_MISS=""; S6_M8_I=0
for old_new in \
  "$S6_REG_PROBE"$'\x1f'"htpasswd -vb /etc/zot/htpasswd \"\$1\" \"\$2\" >/dev/null 2>&1" \
  "$S6_REG_PULL"$'\x1f'"htpasswd -Bbn '\${zot_pull_user}' \"\$ZOT_PULL_TOKEN\"  > /etc/zot/htpasswd" \
  "$S6_REG_PUSH"$'\x1f'"htpasswd -Bbn '\${zot_push_user}' \"\$ZOT_PUSH_TOKEN\" >> /etc/zot/htpasswd"; do
  S6_M8_I=$((S6_M8_I + 1)); S6_M8="$(s6_fresh "m8-$S6_M8_I")"
  if s6_edit "$S6_M8/$S6_REG" "${old_new%%$'\x1f'*}" "${old_new##*$'\x1f'}"; then
    s6_judge "$S6_M8"; [[ "$S6_J_REASONS" == *"bad:$S6_REG"* ]] || S6_M8_MISS+=" site$S6_M8_I(not-red:$S6_J_REASONS)"
  else S6_M8_MISS+=" site$S6_M8_I(edit-missed)"; fi
done
if [[ -z "$S6_M8_MISS" ]]; then row "S6 mutation 8: reintroducing the argv form at the probe, the pull entry or the push entry of the registry template is RED each time (the allowlist is empty, so nothing hides it)" ok
else row "S6 mutation 8: an argv registry site is not caught" fail "missed:$S6_M8_MISS"; fi
# Must-PASS: other order/case (-iB, -iBn, -vi, -Bin, -Bn), `-vb` only in comments (a whole-line comment, a trailing YAML comment), and files outside the population.
S6_M7="$(s6_fresh m7)"; assert_fixture_dir "$S6_M7"; mkdir -p "$S6_M7/scripts" "$S6_M7/.github/workflows" "$S6_M7/apps/web-platform/infra" "$S6_M7/knowledge-base"
{ printf '%s\n' "printf '%s' \"\$p\" | htpasswd -iB svc > \"\$out\""
  printf '%s\n' "printf '%s' \"\$p\" | htpasswd -iBn svc > \"\$out\""
  printf '%s\n' "printf '%s' \"\$p\" | htpasswd -vi \"\$f\" svc"
  printf '%s\n' "# htpasswd -vb \"\$f\" svc \"\$p\" would carry the password on argv"
  printf '%s\n' "    # htpasswd -Bbn svc \"\$p\"   (an indented whole-line comment)"; } > "$S6_M7/scripts/zz-orders-and-comments.sh"
printf '%s\n' "  - apache2-utils # htpasswd -vb f u p (a trailing YAML comment)" > "$S6_M7/.github/workflows/zz-trailing-comment.yml"
printf '%s\n' 'htpasswd -Bbn svc "$p"' > "$S6_M7/apps/web-platform/infra/zz-fixture.test.sh"      # a *.test.sh is not in the population
printf '%s\n' 'run `htpasswd -Bbn svc "$p"` to see it' > "$S6_M7/scripts/zz-docs.md"               # nor is a *.md
printf '%s\n' 'htpasswd -Bbn svc "$p"' > "$S6_M7/knowledge-base/zz-notes.sh"                      # nor a path outside apps/ scripts/ .github/
s6_judge "$S6_M7"
if [[ -z "$S6_J_REASONS" && "$S6_J_SITES" -eq $((S6_REAL_SITES + 3)) ]]; then row "S6 must-pass: other option orders and cases (-iB, -iBn, -vi), -vb only inside whole-line and trailing YAML comments, and a test file, a markdown file and a path outside the roots are GREEN (the three compliant sites are seen)" ok
else row "S6 must-pass: a compliant or excluded form is flagged, or the compliant sites were not seen" fail "reasons='$S6_J_REASONS' sites=$S6_J_SITES want=$((S6_REAL_SITES + 3))"; fi

# --- the registry template's two heartbeat curls (#10093): the URL is a stdin config line, never an argument ----------------------------------------------
# PROPERTY. In cloud-init-registry.yml no `curl` argument holds a `*_heartbeat_url` interpolation: the URL's path is the secret, argv is readable by every local
# user. DERIVATION: every LOGICAL line of the YAML (backslash continuations joined), whole-line comments dropped, with a `curl` command word AND `heartbeat_url`
# is a heartbeat site; with the stdin feed `< <(printf 'url = "%s"\n' '<literal>')` removed, a site that still holds `heartbeat_url` is VIOLATING. The two converted
# sites (disk, liveness) are asserted by IDENTITY. A comment line is never continued by a trailing backslash (bash does not continue it either), and an absolute
# path (`/usr/bin/curl`) is a curl command word. NOT COVERED, named: a URL carried through a variable or an `eval`, another HTTP client (wget, python), a
# template variable of another name, and any file other than the registry template.
S6R_PY="$S6/regheartbeat.py"
cat > "$S6R_PY" <<'S6RPY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
i, out = 0, []
while i < len(lines):
    ln = i + 1
    t = lines[i]
    while not t.lstrip().startswith("#") and t.rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        t = t.rstrip()[:-1] + " " + lines[i].strip()
    i += 1
    s = t.strip()
    if s.startswith("#"):
        continue
    if not re.search(r"(^|[^A-Za-z0-9_.-])curl([^A-Za-z0-9_-]|$)", s) or "heartbeat_url" not in s:
        continue
    feed = re.sub(r"< <\(printf 'url = \"%s\"\\n' '[^']*'\)", "", s)
    out.append(("V" if "heartbeat_url" in feed else "S", ln, s))
for k, ln, s in out:
    print("%s\t%d\t%s" % (k, ln, s))
S6RPY
S6R_DISK="curl --disable --noproxy '*' -g -fsS -m 10 --config - >/dev/null 2>&1 < <(printf 'url = \"%s\"\\n' '\${disk_heartbeat_url}') || PING_RC=\$?"
S6R_LIVE="if curl --disable --noproxy '*' -g -fsS -m 10 -o /dev/null --config - < <(printf 'url = \"%s\"\\n' '\${liveness_heartbeat_url}'); then PING=ok; else PING=fail; fi"
S6R_REAL_SCAN="" ; S6R_J_REASONS="unscanned"   # non-empty until s6r_judge has actually run: deleting the real-tree call must not read as GREEN
s6r_judge() { # <root>: sets S6R_J_REASONS (empty = GREEN) and S6R_REAL_SCAN. Reasons: floor, argv, disk-identity, liveness-identity.
  local scan sites
  scan="$(python3 -I "$S6R_PY" "$1/$S6_REG" 2>/dev/null)" || { S6R_J_REASONS="scan-failed"; return 0; }
  S6R_REAL_SCAN="$scan"; S6R_J_REASONS=""
  sites="$(grep -c . <<<"$scan" || true)"
  [[ "$sites" -ge 2 ]] || S6R_J_REASONS+=" floor"
  grep -q $'^V\t' <<<"$scan" && S6R_J_REASONS+=" argv"
  # ENVIRON, not -v: awk -v interprets backslash escapes, and these lines carry a literal \n inside the printf format.
  [[ "$(S6R_C="$S6R_DISK" awk -F'\t' '$1 == "S" && $3 == ENVIRON["S6R_C"] { n++ } END { print n + 0 }' <<<"$scan")" == 1 ]] || S6R_J_REASONS+=" disk-identity"
  [[ "$(S6R_C="$S6R_LIVE" awk -F'\t' '$1 == "S" && $3 == ENVIRON["S6R_C"] { n++ } END { print n + 0 }' <<<"$scan")" == 1 ]] || S6R_J_REASONS+=" liveness-identity"
  S6R_J_REASONS="${S6R_J_REASONS# }"
}
s6r_judge "$REPO_ROOT"; S6R_REAL="$S6R_J_REASONS"
if [[ -z "$S6R_REAL" ]]; then row "S6-REG heartbeat: the registry template's two heartbeat curls (disk, liveness) carry their URL only in the stdin config feed, never on curl argv, each by exact identity ($(grep -c . <<<"$S6R_REAL_SCAN") sites seen)" ok
else row "S6-REG heartbeat: a registry heartbeat URL is on curl argv, or a converted site drifted from its exact stdin form" fail "reasons='$S6R_REAL'"; fi
# M-R1 put the URL back on the curl argument list (disk): RED by the derived scan, not only by the identity row.
S6R_M1="$(s6_fresh r1)"
if s6_edit "$S6R_M1/$S6_REG" "curl --disable --noproxy '*' -g -fsS -m 10 --config - >/dev/null 2>&1 < <(printf 'url = \"%s\"\\n' '\${disk_heartbeat_url}') || PING_RC=\$?" "curl -fsS -m 10 \"\${disk_heartbeat_url}\" >/dev/null 2>&1 || PING_RC=\$?"; then
  s6r_judge "$S6R_M1"
  if [[ "$S6R_J_REASONS" == *argv* && "$S6R_J_REASONS" == *disk-identity* ]]; then row "S6-REG mutation 1: the disk heartbeat URL back on curl argv is RED (the derived scan and the site's identity)" ok
  else row "S6-REG mutation 1: an argv heartbeat URL in the registry template is not caught" fail "reasons='$S6R_J_REASONS'"; fi
else row "S6-REG mutation 1: the argv edit did not land on the disk heartbeat curl (re-anchor with the template)" fail "the converted disk curl was not found once"; fi
# M-R2 argv URL on the liveness curl too, as a SECOND site, while the first stays compliant: identity per site, not a count.
S6R_M2="$(s6_fresh r2)"
printf '%s\n' "      curl -fsS -m 10 -o /dev/null \"\${liveness_heartbeat_url}\"" >> "$S6R_M2/$S6_REG"
s6r_judge "$S6R_M2"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 2: an extra argv heartbeat curl appended after the compliant two is RED (a violating logical line, not a count)" ok
else row "S6-REG mutation 2: an extra argv heartbeat curl slips through" fail "reasons='$S6R_J_REASONS'"; fi
# M-R3 the scanned word renamed everywhere: the scan sees 0 sites and must be RED (floor), never a clean bill.
S6R_M3="$(s6_fresh r3)"; sed -i 's/heartbeat_url/hb_url/g' "$S6R_M3/$S6_REG"
s6r_judge "$S6R_M3"
if [[ "$S6R_J_REASONS" == *floor* ]]; then row "S6-REG mutation 3: with the scanned variable renamed the scan sees no heartbeat site and the floor is RED" ok
else row "S6-REG mutation 3: a scan that sees nothing is not RED" fail "reasons='$S6R_J_REASONS'"; fi
# Must-pass: a whole-line comment naming curl and the variable is not a violation.
S6R_M4="$(s6_fresh r4)"
printf '%s\n' "      # curl -fsS -m 10 \"\${disk_heartbeat_url}\" would carry the URL on argv" >> "$S6R_M4/$S6_REG"
s6r_judge "$S6R_M4"
if [[ -z "$S6R_J_REASONS" ]]; then row "S6-REG must-pass: a whole-line comment that names curl and the heartbeat variable is not a violation" ok
else row "S6-REG must-pass: a comment line is flagged" fail "reasons='$S6R_J_REASONS'"; fi

# Evasions the first scanner missed: a comment line ending in a backslash swallowed the live line under it; an absolute curl path was not a command word.
S6R_M5="$(s6_fresh r5)"
printf '%s\n' "      # a note that ends in a backslash \\" "      curl -fsS -m 10 \"\${disk_heartbeat_url}\"" >> "$S6R_M5/$S6_REG"
s6r_judge "$S6R_M5"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 5: a live argv curl under a comment line that ends in a backslash is RED (a comment is never continued)" ok
else row "S6-REG mutation 5: a comment ending in a backslash hides the live line under it" fail "reasons='$S6R_J_REASONS'"; fi
S6R_M6="$(s6_fresh r6)"
printf '%s\n' "      /usr/bin/curl -fsS -m 10 \"\${liveness_heartbeat_url}\"" >> "$S6R_M6/$S6_REG"
s6r_judge "$S6R_M6"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 6: an argv heartbeat curl spelled with an absolute path is RED" ok
else row "S6-REG mutation 6: /usr/bin/curl is not seen as a curl command word" fail "reasons='$S6R_J_REASONS'"; fi
S6R_M7="$(s6_fresh r7)"
printf '%s\n' "      curl -fsS -m 10 \\" "        \"\${disk_heartbeat_url}\"" >> "$S6R_M7/$S6_REG"
s6r_judge "$S6R_M7"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 7: an argv heartbeat curl split across two physical lines by a backslash continuation is RED (the logical line is joined)" ok
else row "S6-REG mutation 7: a continuation-split argv heartbeat curl slips through" fail "reasons='$S6R_J_REASONS'"; fi

# --- the executable rows: the REAL workflow step under a refusing stub docker -----------------
# The step is extracted with PyYAML (job registry_pull_path_gate, step id `throwaway`) and cut at the htpasswd line: everything before it (the zot pin
# read, the mkdir, the throwaway user and password) runs for real; the later `docker run` of zot is not part of the property.
S6_STEP="$S6/step.sh"
python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["registry_pull_path_gate"]["steps"]
run = [s["run"] for s in steps if isinstance(s, dict) and s.get("id") == "throwaway"]
if len(run) != 1: sys.exit(3)
out = []
for line in run[0].split("\n"):
    out.append(line)
    if "htpasswd" in line and "docker run" in line: break
else: sys.exit(4)
open(sys.argv[2], "w").write("\n".join(out) + "\n")' "$REPO_ROOT/$S6_WF" "$S6_STEP" || fatal "S6 could not extract the rehearsal step (id throwaway) of $S6_WF up to its htpasswd line"
for t in bash grep sed head openssl mkdir cat tr cut sha256sum wc od rm; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -sf "$p" "$S6/real/$t"
done
cat > "$S6/bin/docker" <<STUB_EOF
#!$BASH_BIN
# REFUSING stub docker. Accepts exactly: run --rm -i httpd:2.4-alpine htpasswd -Bin <user>, with a non-empty password on stdin.
# Anything else is refused with exit 64 and one line in \$S6_LOG/refusals (argument COUNT and the first six words only: the password is never logged).
# A real docker forwards no stdin without -i; the stub models that by refusing the call outright.
set -u
L="\${S6_LOG:?}"
pw="\$(cat)"   # drain first, on every arm: a refusing arm that exits unread would make the producer's printf take SIGPIPE/EPIPE under pipefail
if [[ \$# -eq 7 && "\$1" == run && "\$2" == --rm && "\$3" == -i && "\$4" == httpd:2.4-alpine && "\$5" == htpasswd && "\$6" == -Bin && -n "\$7" && "\$7" != -* ]]; then
  if [[ -z "\$pw" ]]; then printf 'refused-empty-stdin\n' >> "\$L/refusals"; exit 64; fi
  printf '%s\n' "\$7" > "\$L/user"
  printf '%s' "\$pw" | sha256sum | cut -d' ' -f1 > "\$L/stdin.sha"
  printf '%s\n' "\$#" > "\$L/argc"
  printf '%s:\$2y\$05\$stubstubstubstubstubstuXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n' "\$7"
  exit 0
fi
printf 'refused argc=%s a1=%s a2=%s a3=%s a4=%s a5=%s a6=%s\n' "\$#" "\${1-}" "\${2-}" "\${3-}" "\${4-}" "\${5-}" "\${6-}" >> "\$L/refusals"
exit 64
STUB_EOF
chmod +x "$S6/bin/docker"
S6_RUN_RC=0
s6_run_step() { # <step file> <row dir>: the step under `bash --noprofile --norc -eo pipefail`, PATH = the stub + the few real tools
  local step="$1" d="$2"; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/log" "$d/run"
  env -i PATH="$S6/bin:$S6/real" HOME="$d" TMPDIR="$d" GITHUB_WORKSPACE="$REPO_ROOT" RUNNER_TEMP="$d/run" S6_LOG="$d/log" \
    "$BASH_BIN" --noprofile --norc -eo pipefail "$step" > "$d/stdout" 2> "$d/stderr"
  S6_RUN_RC=$?
}
s6_nrefusals() { if [[ -f "$1/log/refusals" ]]; then grep -c . "$1/log/refusals" || true; else echo 0; fi; }
# The password of the run is the one `::add-mask::` line the step prints; it is compared by hash, never printed.
s6_step_ok() { # <row dir>: rc 0, nothing refused, one 7-word call, an entry for the recorded user, and the stub read the masked password on stdin
  local d="$1" maskhash
  maskhash="$(sed -n 's/^::add-mask:://p' "$d/stdout" | head -1 | tr -d '\n' | sha256sum | cut -d' ' -f1)"
  [[ "$S6_RUN_RC" -eq 0 && "$(s6_nrefusals "$d")" -eq 0 && "$(cat "$d/log/argc" 2>/dev/null)" == 7 ]] \
    && [[ -s "$d/run/zot/htpasswd" && -n "$(cat "$d/log/user" 2>/dev/null)" && "$(cut -d: -f1 "$d/run/zot/htpasswd")" == "$(cat "$d/log/user")" ]] \
    && [[ -n "$maskhash" && "$maskhash" == "$(cat "$d/log/stdin.sha" 2>/dev/null)" ]]
}
# Instrument control: the stub itself refuses a wrong shape and an empty stdin, and accepts the right one (otherwise every row below proves nothing).
S6_C="$S6/ctl"; mkdir -p "$S6_C"; S6_CTL_BAD=""
s6_stub() { rm -rf "$S6_C/log"; mkdir -p "$S6_C/log"; local stdin="$1"; shift; printf '%s' "$stdin" | env -i PATH="$S6/real" S6_LOG="$S6_C/log" "$S6/bin/docker" "$@" >/dev/null 2>&1; }
s6_stub secret run --rm -i httpd:2.4-alpine htpasswd -Bin u || S6_CTL_BAD+=" right-shape-refused"
for variant in "run --rm httpd:2.4-alpine htpasswd -Bin u" "run --rm -i httpd:2.4-alpine htpasswd -Bbn u pw" "run --rm -i httpd:2.4-alpine htpasswd -Bn u" "run -i httpd:2.4-alpine htpasswd -Bin u" "run --rm -i httpd:2.4-alpine htpasswd -Bin" "run --rm -i httpd:2.4-alpine htpasswd -Bin -x"; do
  # shellcheck disable=SC2086
  if s6_stub secret $variant; then S6_CTL_BAD+=" accepted[$variant]"
  elif [[ "$(s6_nrefusals "$S6_C")" -ne 1 ]]; then S6_CTL_BAD+=" unlogged[$variant]"; fi
done
if s6_stub '' run --rm -i httpd:2.4-alpine htpasswd -Bin u; then S6_CTL_BAD+=" accepted-empty-stdin"; fi
if [[ -z "$S6_CTL_BAD" ]]; then row "S6 instrument: the stub docker accepts exactly 'run --rm -i httpd:2.4-alpine htpasswd -Bin <user>' with a password on stdin and refuses (exit 64, one logged refusal) a missing -i, a -b form, a missing user, a wrong word and an empty stdin" ok
else row "S6 instrument: the stub docker accepts a wrong shape, refuses the right one or does not log" fail "$S6_CTL_BAD"; fi
s6_run_step "$S6_STEP" "$S6/row-good"
if s6_step_ok "$S6/row-good"; then row "S6 executable: the REAL rehearsal step, run under bash -eo pipefail against the refusing stub docker, makes exactly one call (7 words, -i, -Bin <user>), nothing is refused, the password (by hash) arrived on stdin and the htpasswd file holds the entry" ok
else row "S6 executable: the real rehearsal step did not make the one accepted stdin-form call" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-good") argc=$(cat "$S6/row-good/log/argc" 2>/dev/null) stderr=$(head -c 160 "$S6/row-good/stderr" | tr '\n' ' ')"; fi
# Mutations of the step text itself: drop docker's -i; put -b back (the original argv form).
cp "$S6_STEP" "$S6/step-noi.sh"; cp "$S6_STEP" "$S6/step-b.sh"
if s6_edit "$S6/step-noi.sh" 'docker run --rm -i httpd:2.4-alpine' 'docker run --rm httpd:2.4-alpine'; then
  s6_run_step "$S6/step-noi.sh" "$S6/row-noi"
  if [[ "$S6_RUN_RC" -ne 0 && "$(s6_nrefusals "$S6/row-noi")" -ge 1 ]] && ! s6_step_ok "$S6/row-noi"; then row "S6 mutation (executable): dropping docker's own -i from the step is RED (the stub refuses: docker would forward nothing and the hash would cover an empty password)" ok
  else row "S6 mutation (executable): the step without docker -i is not caught" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-noi")"; fi
else row "S6 mutation (executable): the -i drop did not land on the step text (the step is not the stdin form)" fail "no 'docker run --rm -i httpd:2.4-alpine' once in the extracted step"; fi
if s6_edit "$S6/step-b.sh" "printf '%s' \"\$RP\" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin \"\$RU\"" 'docker run --rm httpd:2.4-alpine htpasswd -Bbn "$RU" "$RP"'; then
  s6_run_step "$S6/step-b.sh" "$S6/row-b"
  if [[ "$S6_RUN_RC" -ne 0 && "$(s6_nrefusals "$S6/row-b")" -ge 1 ]] && ! s6_step_ok "$S6/row-b"; then row "S6 mutation (executable): putting -b back (the original password-on-argv call) is RED (the stub refuses anything but the stdin form)" ok
  else row "S6 mutation (executable): the step with -b back is not caught" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-b")"; fi
else row "S6 mutation (executable): the -b edit did not land on the step text (the step is not the stdin form)" fail "the printf-piped docker call was not found once in the extracted step"; fi
echo "=== stage S6: Guard 3 rows (htpasswd password off argv: workflow site, residual allowlist, executable stub) done ==="

# =====================================================================================
# STAGE S6-HB (argv-bearer sweep, Guard 2, #9757): a heartbeat URL reaches curl only on the stdin config, after the shape judgement.
#
# PROPERTY. A Better Stack heartbeat URL's PATH is the credential. In the converted host scripts it is never an argument of any process: it rides curl's
# stdin config (`--config -`), after a shape guard that refuses (zero requests, one value-free marker) a scheme other than https://, an empty rest and any
# byte outside [A-Za-z0-9._~:/?&=%+-]. The behavioural rows (hostile values, per-attempt stdin, zero requests, zero sleeps, the dash run) live in the
# scripts' own suites (luks-monitor.test.sh, web-git-data-probe.test.sh, inngest.test.sh); this stage owns the DERIVED POPULATION.
#
# DERIVATION. Every tracked-or-untracked apps/web-platform/infra/*.sh (not *.test.sh) whose non-comment code mentions `heartbeat` is a heartbeat script (a
# file that names no heartbeat, e.g. a Pages probe whose own variable is also called URL, is outside the population). In such a file every logical line
# (continuations joined, whole-line comments dropped) has its `< <(...)` stdin feed removed, is split into segments on `||`, `&&`, `;` and `|`, and every
# segment holding a `curl` command word whose remaining text names `$URL`, `$hb_url` or a `*HEARTBEAT_URL` variable is a VIOLATION: the URL is on argv.
# (`$INNGEST_HEALTH_URL`, the local health probe in the same file as the heartbeat, is not a heartbeat variable.) The curl word may carry a path prefix
# (`/usr/local/bin/curl`), a leading backslash (`\curl`) or a backtick. NOT COVERED, named (a text heuristic, not exhaustive; these pre-date PR C, see ADR-280 PR C
# follow-up): a URL carried in a variable that is none of those names, an `eval`, curl inside a quoted string, producer and consumer split across segments,
# other HTTP clients, a quoted metacharacter before the URL, files in subdirectories or not named *.sh, and units. The registry template's own heartbeat curls
# are S6-REG's (above).
#
# EXPLICIT RESIDUAL ALLOWLIST (S6H_ALLOW: file, the segment text, the exact number of occurrences): EMPTY since PR C (#10120 converted the inngest heartbeat
# body, #10093 the three probe scripts), so every heartbeat curl carries its URL on stdin and any argv URL is a plain violation. The mechanism stays: an entry
# the scan no longer sees, or a count that moved, is RED, and the ceiling is 0 (a grown allowlist is RED by the same predicate).
# CONVERTED SCRIPTS (S6H_CONVERTED): exactly one stdin config line (`url = "..."`) each, and exactly one copy of the shape-guard class, on a line BEFORE it.
# =====================================================================================
S6H_DIR="apps/web-platform/infra"
S6H_CONVERTED=(luks-monitor.sh web-git-data-probe.sh inngest-bootstrap.sh web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh web-bash-synthetic.sh)
S6H_FILE_FLOOR=7
S6H_ALLOW_CEIL=0
S6H_CLASS='[!A-Za-z0-9._~:/?\&=%+-]'
S6H_ALLOW=()
# One TSV record per finding. V: a violating segment (file, segment). C: a stdin config line (file, line number). G: a guard class literal (file, line
# number). P: a heartbeat-population file (file).
s6h_scan() { # <root>
  python3 -I -c '
import re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True).stdout.decode().split("\0")
pat = re.compile(r"^apps/web-platform/infra/[^/]+\.sh$")
cmd = re.compile(r"(?:^|[\s({;|&`\\])(?:/(?:[A-Za-z0-9_.-]+/)*)?curl(?=\s|$)")
var = re.compile(r"\$\{?(?:URL|hb_url|[A-Z0-9_]*HEARTBEAT_URL)(?![A-Za-z0-9_])")
cfg = re.compile(r"url = \"(?:%s|\$\{?[A-Za-z_]*HEARTBEAT_URL)")
cls = sys.argv[2]
for f in sorted(set(files)):
    if not pat.match(f) or f.endswith(".test.sh"): continue
    try: raw = open(root + "/" + f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError: continue
    logical, cur, start = [], "", 0
    for i, l in enumerate(raw, 1):
        s = l.strip()
        if not cur and s.startswith("#"): continue
        if not cur: start = i
        if s.endswith("\\"): cur += s[:-1] + " "; continue
        logical.append((start, cur + s)); cur = ""
    if cur: logical.append((start, cur))
    if not any(re.search(r"heartbeat", t, re.I) for _, t in logical): continue
    print("P\t" + f)
    for n, t in logical:
        if cfg.search(t): print("C\t%s\t%d" % (f, n))
        if cls in t: print("G\t%s\t%d" % (f, n))
        u = re.sub(r"<\s*<\(.*?\)", "", t)
        for seg in re.split(r"\s*(?:\|\||&&|;|\|)\s*", u):
            seg = " ".join(seg.split())
            if cmd.search(seg) and var.search(seg): print("V\t%s\t%s" % (f, seg))
' "$1" "$S6H_CLASS"
}
# The verdict over a root. Sets S6H_J_REASONS (empty = GREEN) and S6H_J_FILES. Reasons: floor, argv:<file>, stale-allowlist, cfg:<file>, guard:<file>.
S6H_J_REASONS=""; S6H_J_FILES=0
s6h_judge() { # <root>
  local root="$1" scan a file seg want got c g cl gl f
  scan="$(s6h_scan "$root")"; S6H_J_REASONS=""
  S6H_J_FILES="$(grep -c '^P	' <<<"$scan" || true)"
  [[ "$S6H_J_FILES" -ge "$S6H_FILE_FLOOR" ]] || S6H_J_REASONS+=" floor"
  # every violating (file, segment) must be allowlisted with exactly its count
  while IFS=$'\t' read -r got file seg; do
    [[ -n "$file" ]] || continue
    want=""; for a in "${S6H_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'"$seg"$'\t'* ]] && want="${a##*$'\t'}"; done
    [[ "$want" == "$got" ]] || S6H_J_REASONS+=" argv:$file"
  done < <(awk -F'\t' '$1 == "V" { k = $2 "\t" $3; n[k]++ } END { for (k in n) print n[k] "\t" k }' <<<"$scan")
  for a in "${S6H_ALLOW[@]}"; do
    file="${a%%$'\t'*}"; seg="${a#*$'\t'}"; seg="${seg%$'\t'*}"; want="${a##*$'\t'}"
    got="$(awk -F'\t' -v f="$file" -v s="$seg" '$1 == "V" && $2 == f && $3 == s { n++ } END { print n + 0 }' <<<"$scan")"
    [[ "$got" == "$want" ]] || S6H_J_REASONS+=" stale-allowlist"
  done
  for f in "${S6H_CONVERTED[@]}"; do
    file="$S6H_DIR/$f"
    c="$(awk -F'\t' -v f="$file" '$1 == "C" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    cl="$(awk -F'\t' -v f="$file" '$1 == "C" && $2 == f { print $3; exit }' <<<"$scan")"
    g="$(awk -F'\t' -v f="$file" '$1 == "G" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    gl="$(awk -F'\t' -v f="$file" '$1 == "G" && $2 == f { print $3; exit }' <<<"$scan")"
    [[ "$c" == 1 ]] || S6H_J_REASONS+=" cfg:$file"
    [[ "$g" == 1 && -n "$gl" && -n "$cl" && "$gl" -lt "$cl" ]] || S6H_J_REASONS+=" guard:$file"
  done
  S6H_J_REASONS="${S6H_J_REASONS# }"
}
S6H="$TMPD/s6h"; assert_fixture_dir "$S6H"; mkdir -p "$S6H/base" "$S6H/mut"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S6H/base" || exit 1; git -C "$S6H/base" init -q ) \
  || fatal "S6-HB could not create the scratch repository"
mkdir -p "$S6H/base/$S6H_DIR"
# The scratch tree holds every converted script the real verdict names, plus two controls: a non-heartbeat probe whose own variable is also called URL (outside the
# population: it must NOT be flagged) and the already-converted git-data-liveness.sh (a stdin-form heartbeat script that is not in S6H_CONVERTED).
for f in "${S6H_CONVERTED[@]}" pages-build-identity-probe.sh git-data-liveness.sh; do
  cp "$REPO_ROOT/$S6H_DIR/$f" "$S6H/base/$S6H_DIR/$f"
done
s6h_fresh() { local d="$S6H/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S6H/base" "$d" && printf '%s' "$d"; }

# --- the real tree ---------------------------------------------------------------------
s6h_judge "$REPO_ROOT"; S6H_REAL_REASONS="$S6H_J_REASONS"; S6H_REAL_FILES="$S6H_J_FILES"
if [[ -z "$S6H_REAL_REASONS" ]]; then row "S6-HB Guard 2: no heartbeat curl in apps/web-platform/infra/*.sh carries its URL on argv outside the residual allowlist, and each converted script has exactly one guarded stdin config line ($S6H_REAL_FILES heartbeat scripts derived)" ok
else row "S6-HB Guard 2: a heartbeat URL is on curl argv outside the residual allowlist, an allowlist entry is stale, or a converted script lost its guarded stdin config line" fail "reasons='$S6H_REAL_REASONS' files=$S6H_REAL_FILES"; fi
S6H_SCAN="$(s6h_scan "$REPO_ROOT")"
s6h_ncfg() { awk -F'\t' -v f="$S6H_DIR/$1" '$1 == "C" && $2 == f { n++ } END { print n + 0 }' <<<"$S6H_SCAN"; }
s6h_inpop() { awk -F'\t' -v f="$S6H_DIR/$1" '$1 == "P" && $2 == f { n++ } END { print n + 0 }' <<<"$S6H_SCAN"; }
for f in "${S6H_CONVERTED[@]}"; do
  if [[ "$(s6h_ncfg "$f")" -eq 1 && "$(s6h_inpop "$f")" -eq 1 ]]; then row "S6-HB converted $f: in the derived heartbeat population, exactly one stdin config line (the single guarded transport), no violating segment" ok
  else row "S6-HB converted $f: not in the population, or not exactly one stdin config line" fail "cfg=$(s6h_ncfg "$f") inpop=$(s6h_inpop "$f")"; fi
done
S6H_ALLOW_FILES="$(for a in "${S6H_ALLOW[@]}"; do printf '%s\n' "${a%%$'\t'*}"; done | sort -u | grep -c . || true)"
s6h_ceiling_ok() { [[ "$1" -eq "$S6H_ALLOW_CEIL" && "$S6H_ALLOW_CEIL" -eq 0 ]]; }
if s6h_ceiling_ok "${#S6H_ALLOW[@]}" && ! s6h_ceiling_ok $((${#S6H_ALLOW[@]} + 1)); then row "S6-HB allowlist ceiling: the residual allowlist is EMPTY (ceiling $S6H_ALLOW_CEIL; PR C deleted the four residual entries of #10120 and #10093), and a grow-by-one allowlist is judged RED by the same predicate" ok
else row "S6-HB allowlist ceiling: the residual allowlist is not empty, or the ceiling predicate accepts a grown allowlist" fail "entries=${#S6H_ALLOW[@]} files=$S6H_ALLOW_FILES want=$S6H_ALLOW_CEIL"; fi

# --- mutation rows (the SAME scan over a scratch tree) ------------------------------------
# M1 (Guard 2 row 1): the URL back on argv in a converted script.
S6H_M1="$(s6h_fresh m1)"
if s6_edit "$S6H_M1/$S6H_DIR/web-git-data-probe.sh" '--config - 2>/dev/null < <(printf '"'"'url = "%s"\n'"'"' "$URL"); }' '"$URL" 2>/dev/null; }'; then
  s6h_judge "$S6H_M1"
  if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/web-git-data-probe.sh"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/web-git-data-probe.sh"* ]]; then row "S6-HB mutation 1: the URL back on curl argv in a converted script is RED (an argv violation, and the script's stdin config line is gone)" ok
  else row "S6-HB mutation 1: an argv heartbeat URL in a converted script is not caught" fail "reasons='$S6H_J_REASONS'"; fi
else row "S6-HB mutation 1: the argv edit did not land (re-anchor with web-git-data-probe.sh)" fail "no transport line once in the scratch copy"; fi
# Guard-copy parity (Guard 2): the shape guard and the per-attempt curl are four byte-identical inline copies (checkout-less hosts cannot source a library), so
# one drift between them is a silent fork of the credential gate. Extract both definitions from each bash copy and require ONE distinct digest.
s6h_guard_digest() { # <file> -> md5 of the _hb_url_ok function and the _hb_curl line, empty when either is missing
  python3 -I -c '
import hashlib, sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
out, i = [], 0
while i < len(src):
    if src[i].startswith("_hb_url_ok() {"):
        j = i
        while j < len(src) and src[j] != "}": j += 1
        out.extend(src[i:j + 1]); i = j
    elif src[i].startswith("_hb_curl() {"):
        out.append(src[i])
    i += 1
if len([l for l in out if l.startswith("_hb_url_ok() {")]) != 1 or len([l for l in out if l.startswith("_hb_curl() {")]) != 1: sys.exit(0)
print(hashlib.md5("\n".join(out).encode()).hexdigest())
' "$1"
}
S6H_PARITY_FILES=(web-git-data-probe.sh web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh)
S6H_PARITY_SET=""; S6H_PARITY_EMPTY=0
for f in "${S6H_PARITY_FILES[@]}"; do
  S6H_D="$(s6h_guard_digest "$REPO_ROOT/$S6H_DIR/$f")"
  if [[ -z "$S6H_D" ]]; then S6H_PARITY_EMPTY=$((S6H_PARITY_EMPTY + 1)); else S6H_PARITY_SET+="$S6H_D"$'\n'; fi
done
S6H_PARITY_N="$(printf '%s' "$S6H_PARITY_SET" | sort -u | grep -c . || true)"
if [[ "$S6H_PARITY_EMPTY" -eq 0 && "$S6H_PARITY_N" -eq 1 ]]; then row "S6-HB guard-copy parity: _hb_url_ok and _hb_curl are byte-identical across the ${#S6H_PARITY_FILES[@]} bash copies (one digest, none missing a definition)" ok
else row "S6-HB guard-copy parity: the inline guard copies drifted or one lost a definition" fail "distinct=$S6H_PARITY_N missing=$S6H_PARITY_EMPTY"; fi
S6H_MPA="$(s6h_fresh mpa)"
if s6_edit "$S6H_MPA/$S6H_DIR/web-zot-consumer-probe.sh" '  case "$1" in https://*) ;; *) return 1 ;; esac' '  case "$1" in http*://*) ;; *) return 1 ;; esac'; then
  S6H_DA="$(s6h_guard_digest "$S6H_MPA/$S6H_DIR/web-zot-consumer-probe.sh")"; S6H_DB="$(s6h_guard_digest "$S6H_MPA/$S6H_DIR/web-git-data-probe.sh")"
  if [[ -n "$S6H_DA" && -n "$S6H_DB" && "$S6H_DA" != "$S6H_DB" ]]; then row "S6-HB guard-copy parity mutation: loosening the scheme test in ONE copy changes its digest (the parity row would be RED)" ok
  else row "S6-HB guard-copy parity mutation: a one-copy edit of the guard is not visible to the digest" fail "a=$S6H_DA b=$S6H_DB"; fi
else row "S6-HB guard-copy parity mutation: the edit did not land (re-anchor with the scheme case line)" fail "no scheme case line once in the scratch copy"; fi
# web-bash-synthetic.sh (#10455) carries a FIFTH copy of the shape guard but NOT of the full pair: its `_hb_curl` takes the URL as "$1" (finish() appends `/fail`
# to the path, so the curl must take the target as an argument), where the four siblings read "$URL". It stays out of S6H_PARITY_FILES ON PURPOSE and is pinned in
# two parts instead: (1) its `_hb_url_ok` digest equals the siblings', and (2) its `_hb_curl` line equals the siblings' line with "$URL" replaced by "$1".
s6h_urlok_digest() { # <file> -> md5 of the _hb_url_ok function alone, empty when it is missing or defined twice
  python3 -I -c '
import hashlib, sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
heads = [i for i, l in enumerate(src) if l.startswith("_hb_url_ok() {")]
if len(heads) != 1: sys.exit(0)
j = heads[0]
while j < len(src) and src[j] != "}": j += 1
print(hashlib.md5("\n".join(src[heads[0]:j + 1]).encode()).hexdigest())
' "$1"
}
s6h_curl_line() { [[ "$(grep -cF '_hb_curl() {' "$1")" == 1 ]] && grep -F '_hb_curl() {' "$1"; } # the one definition line, rc 1 when absent or repeated
S6H_WBS_FILE="$REPO_ROOT/$S6H_DIR/web-bash-synthetic.sh"
S6H_UO_SET=""; S6H_UO_EMPTY=0
for f in "${S6H_PARITY_FILES[@]}" web-bash-synthetic.sh; do
  S6H_D="$(s6h_urlok_digest "$REPO_ROOT/$S6H_DIR/$f")"
  if [[ -z "$S6H_D" ]]; then S6H_UO_EMPTY=$((S6H_UO_EMPTY + 1)); else S6H_UO_SET+="$S6H_D"$'\n'; fi
done
S6H_UO_N="$(printf '%s' "$S6H_UO_SET" | sort -u | grep -c . || true)"
S6H_SIB_CURL="$(s6h_curl_line "$REPO_ROOT/$S6H_DIR/web-git-data-probe.sh" || true)"
S6H_WBS_CURL="$(s6h_curl_line "$S6H_WBS_FILE" || true)"
S6H_WBS_WANT="${S6H_SIB_CURL//\"\$URL\"/\"\$1\"}"
if [[ "$S6H_UO_EMPTY" -eq 0 && "$S6H_UO_N" -eq 1 ]]; then row "S6-HB guard-copy parity (web-bash-synthetic): its _hb_url_ok is byte-identical to the ${#S6H_PARITY_FILES[@]} sibling copies (one digest, none missing)" ok
else row "S6-HB guard-copy parity (web-bash-synthetic): its _hb_url_ok drifted from the siblings' or lost its definition" fail "distinct=$S6H_UO_N missing=$S6H_UO_EMPTY"; fi
if [[ -n "$S6H_SIB_CURL" && -n "$S6H_WBS_CURL" && "$S6H_WBS_CURL" != "$S6H_SIB_CURL" && "$S6H_WBS_CURL" == "$S6H_WBS_WANT" ]]; then row "S6-HB guard-copy parity (web-bash-synthetic): its _hb_curl is the siblings' line with the URL taken as \$1 (the one intended divergence)" ok
else row "S6-HB guard-copy parity (web-bash-synthetic): its _hb_curl is not the siblings' line with \"\$URL\" replaced by \"\$1\"" fail "sib='$S6H_SIB_CURL' wbs='$S6H_WBS_CURL'"; fi
S6H_MWU="$(s6h_fresh mwu)"
if s6_edit "$S6H_MWU/$S6H_DIR/web-bash-synthetic.sh" '  case "$1" in https://*) ;; *) return 1 ;; esac' '  case "$1" in http*://*) ;; *) return 1 ;; esac'; then
  S6H_DA="$(s6h_urlok_digest "$S6H_MWU/$S6H_DIR/web-bash-synthetic.sh")"; S6H_DB="$(s6h_urlok_digest "$S6H_MWU/$S6H_DIR/web-git-data-probe.sh")"
  if [[ -n "$S6H_DA" && -n "$S6H_DB" && "$S6H_DA" != "$S6H_DB" ]]; then row "S6-HB guard-copy parity (web-bash-synthetic) mutation: loosening the scheme test in the synthetic's copy changes its _hb_url_ok digest" ok
  else row "S6-HB guard-copy parity (web-bash-synthetic) mutation: a one-copy edit of the synthetic's guard is not visible to the digest" fail "a=$S6H_DA b=$S6H_DB"; fi
else row "S6-HB guard-copy parity (web-bash-synthetic) mutation: the edit did not land (re-anchor with the scheme case line)" fail "no scheme case line once in the scratch copy"; fi
S6H_MWC="$(s6h_fresh mwc)"
if s6_edit "$S6H_MWC/$S6H_DIR/web-bash-synthetic.sh" "curl --disable --noproxy '*' -gfsS -m 10" "curl --disable --noproxy '*' -gsS -m 10"; then
  S6H_CA="$(s6h_curl_line "$S6H_MWC/$S6H_DIR/web-bash-synthetic.sh" || true)"; S6H_CB="$(s6h_curl_line "$S6H_MWC/$S6H_DIR/web-git-data-probe.sh" || true)"
  if [[ -n "$S6H_CA" && "$S6H_CA" != "${S6H_CB//\"\$URL\"/\"\$1\"}" ]]; then row "S6-HB guard-copy parity (web-bash-synthetic) mutation: dropping -f from the synthetic's _hb_curl breaks the line pin (a 404 would read as a delivered ping)" ok
  else row "S6-HB guard-copy parity (web-bash-synthetic) mutation: a flag dropped from the synthetic's _hb_curl is not visible to the line pin" fail "a='$S6H_CA'"; fi
else row "S6-HB guard-copy parity (web-bash-synthetic) mutation: the edit did not land (re-anchor with the curl flags)" fail "no curl flag string once in the scratch copy"; fi
# M-var/M-curl (scanner reach, CTO-ruled 2026-10-15): the stage contract says *HEARTBEAT_URL, which includes the bare name, and the curl word may be path-prefixed,
# backslashed or inside backticks. Each spelling is appended to a converted script (no allowlist to hide behind) and must be an argv violation.
S6H_MV="$(s6h_fresh mv)"; assert_fixture_dir "$S6H_MV"; printf '%s\n' 'curl -fsS "$HEARTBEAT_URL" >/dev/null' >> "$S6H_MV/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_MV"
if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB scanner reach: a curl carrying the bare \$HEARTBEAT_URL (the stage contract's *HEARTBEAT_URL includes it) is an argv violation" ok
else row "S6-HB scanner reach: the bare HEARTBEAT_URL variable is not matched" fail "reasons='$S6H_J_REASONS'"; fi
S6H_MC_BAD=""; S6H_MC_I=0
for S6H_SP in '/usr/local/bin/curl -fsS "$URL" >/dev/null' '\curl -fsS "$URL" >/dev/null' 'x=`curl -fsS "$URL"`'; do
  S6H_MC_I=$((S6H_MC_I + 1)); S6H_MC="$(s6h_fresh "mc$S6H_MC_I")"; assert_fixture_dir "$S6H_MC"; printf '%s\n' "$S6H_SP" >> "$S6H_MC/$S6H_DIR/luks-monitor.sh"
  s6h_judge "$S6H_MC"; [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/luks-monitor.sh"* ]] || S6H_MC_BAD+=" [$S6H_SP]"
done
if [[ -z "$S6H_MC_BAD" ]]; then row "S6-HB scanner reach: a path-prefixed curl, a backslashed curl and a backtick-substituted curl carrying \$URL are each an argv violation" ok
else row "S6-HB scanner reach: a curl spelling is not matched" fail "missed:$S6H_MC_BAD"; fi
# M1b (Guard 2 row 1, the POSIX heredoc script): the URL back on argv in the heartbeat-body curl. The mutant is built from the real transport line.
S6H_M1B="$(s6h_fresh m1b)"
if s6_edit "$S6H_M1B/$S6H_DIR/inngest-bootstrap.sh" 'printf '"'"'url = "%s"\n'"'"' "$INNGEST_HEARTBEAT_URL" | /usr/bin/curl --disable --noproxy '"'"'*'"'"' -gfsS --max-time 10 --config - >/dev/null' '/usr/bin/curl --disable --noproxy '"'"'*'"'"' -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null'; then
  s6h_judge "$S6H_M1B"
  if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/inngest-bootstrap.sh"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/inngest-bootstrap.sh"* ]]; then row "S6-HB mutation 1 (POSIX sh script): the URL back on curl argv in the inngest heartbeat body is RED (an argv violation, and its stdin config line is gone)" ok
  else row "S6-HB mutation 1 (POSIX sh script): an argv heartbeat URL in the inngest heartbeat body is not caught" fail "reasons='$S6H_J_REASONS'"; fi
else row "S6-HB mutation 1 (POSIX sh script): the argv edit did not land (re-anchor with the printf-piped curl line in inngest-bootstrap.sh)" fail "no printf-piped curl transport line once in the scratch copy"; fi
# M1c (Guard 2 row 1, the three probes): the URL back on argv in each probe's per-attempt curl, one scratch copy per probe.
S6H_M1C_BAD=""
for S6H_PF in web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh; do
  S6H_M1C="$(s6h_fresh "m1c-${S6H_PF%.sh}")"
  if s6_edit "$S6H_M1C/$S6H_DIR/$S6H_PF" '--config - 2>/dev/null < <(printf '"'"'url = "%s"\n'"'"' "$URL"); }' '"$URL" 2>/dev/null; }'; then
    s6h_judge "$S6H_M1C"
    [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/$S6H_PF"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/$S6H_PF"* ]] || S6H_M1C_BAD+=" $S6H_PF(reasons=$S6H_J_REASONS)"
  else S6H_M1C_BAD+=" $S6H_PF(edit-missed)"; fi
done
if [[ -z "$S6H_M1C_BAD" ]]; then row "S6-HB mutation 1 (the three probes): the URL back on curl argv in the web-zot-consumer, inngest-consumer or private-NIC probe is RED (an argv violation, and its stdin config line is gone)" ok
else row "S6-HB mutation 1 (the three probes): an argv heartbeat URL in a converted probe is not caught, or the edit did not land" fail "bad='$S6H_M1C_BAD'"; fi
# M3 (Guard 2 row 3): a second heartbeat curl outside the guarded line after a compliant first. Both spellings: URL on argv, and an unguarded second stdin config line.
S6H_M3="$(s6h_fresh m3)"; assert_fixture_dir "$S6H_M3"; printf '%s\n' '[ -n "$hb_url" ] && curl -fsS "$hb_url" >/dev/null 2>&1' >> "$S6H_M3/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_M3"; S6H_M3A="$S6H_J_REASONS"
S6H_M3B="$(s6h_fresh m3b)"; assert_fixture_dir "$S6H_M3B"; printf '%s\n' "curl --disable --noproxy '*' -gfsS --config - >/dev/null < <(printf 'url = \"%s\"\\n' \"\$hb_url\")" >> "$S6H_M3B/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_M3B"; S6H_M3BR="$S6H_J_REASONS"
if [[ "$S6H_M3A" == *"argv:$S6H_DIR/luks-monitor.sh"* && "$S6H_M3BR" == *"cfg:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB mutation 3: a second heartbeat curl after the compliant one is RED, both as an argv URL and as a second (unguarded) stdin config line" ok
else row "S6-HB mutation 3: a second heartbeat curl in a converted script is not caught" fail "argv='$S6H_M3A' cfg='$S6H_M3BR'"; fi
# M-guard: the shape-guard class altered or missing in a converted script.
# M3c (Guard 2 row 3, a probe): a second heartbeat curl after the compliant first. Both spellings: URL on argv, and an unguarded second stdin config line.
S6H_M3C="$(s6h_fresh m3c)"; assert_fixture_dir "$S6H_M3C"; printf '%s\n' '[ -n "$URL" ] && curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null' >> "$S6H_M3C/$S6H_DIR/web-private-nic-guard.sh"
s6h_judge "$S6H_M3C"; S6H_M3CA="$S6H_J_REASONS"
S6H_M3D="$(s6h_fresh m3d)"; assert_fixture_dir "$S6H_M3D"; printf '%s\n' "curl --disable --noproxy '*' -gfsS --config - >/dev/null < <(printf 'url = \"%s\"\\n' \"\$URL\")" >> "$S6H_M3D/$S6H_DIR/web-private-nic-guard.sh"
s6h_judge "$S6H_M3D"; S6H_M3DR="$S6H_J_REASONS"
if [[ "$S6H_M3CA" == *"argv:$S6H_DIR/web-private-nic-guard.sh"* && "$S6H_M3DR" == *"cfg:$S6H_DIR/web-private-nic-guard.sh"* ]]; then row "S6-HB mutation 3 (a probe): a second heartbeat curl after the compliant first is RED, both as an argv URL and as a second unguarded stdin config line" ok
else row "S6-HB mutation 3 (a probe): a second heartbeat curl in a converted probe is not caught" fail "argv='$S6H_M3CA' cfg='$S6H_M3DR'"; fi
# MGb (Guard 2 row 3, the POSIX script): any edit of the shape-guard class literal in inngest-bootstrap.sh is RED by identity. The dangerous direction (a class that
# ADMITS a quote) is caught only by the runtime hostile-value rows of inngest.test.sh, not by this identity check.
S6H_MGB="$(s6h_fresh mgb)"
if s6_edit "$S6H_MGB/$S6H_DIR/inngest-bootstrap.sh" "$S6H_CLASS" '[!A-Za-z0-9]'; then s6h_judge "$S6H_MGB"; S6H_MGBR="$S6H_J_REASONS"; else S6H_MGBR="edit-missed"; fi
if [[ "$S6H_MGBR" == *"guard:$S6H_DIR/inngest-bootstrap.sh"* ]]; then row "S6-HB mutation (guard, POSIX sh script): an altered shape-guard class in inngest-bootstrap.sh is RED" ok
else row "S6-HB mutation (guard, POSIX sh script): an altered shape-guard class in inngest-bootstrap.sh is not caught" fail "reasons='$S6H_MGBR'"; fi
S6H_MG="$(s6h_fresh mg)"
if s6_edit "$S6H_MG/$S6H_DIR/luks-monitor.sh" "$S6H_CLASS" '[!A-Za-z0-9]'; then s6h_judge "$S6H_MG"; S6H_MGR="$S6H_J_REASONS"; else S6H_MGR="edit-missed"; fi
if [[ "$S6H_MGR" == *"guard:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB mutation (guard): a converted script without the exact shape-guard class is RED" ok
else row "S6-HB mutation (guard): a missing or altered shape-guard class is not caught" fail "reasons='$S6H_MGR'"; fi
# M-stale: an allowlist entry that the scan does not see is RED (and nothing else). The real allowlist is empty, so the mutant INJECTS an entry for a
# converted script whose line is gone (the retired argv beat line of the NIC guard); the array is saved and restored around the judge call (as stage S6 does).
S6H_MS="$(s6h_fresh ms)"
S6H_ALLOW_SAVE=("${S6H_ALLOW[@]}")
S6H_ALLOW+=("$S6H_DIR/web-private-nic-guard.sh	beat() { curl --disable --noproxy '*' -fsS -m 10 -o /dev/null \"\$URL\" 2>/dev/null	1")
s6h_judge "$S6H_MS"; S6H_MS_R="$S6H_J_REASONS"
S6H_ALLOW=("${S6H_ALLOW_SAVE[@]}")
if [[ "$S6H_MS_R" == "stale-allowlist" ]]; then row "S6-HB mutation (stale): an allowlist entry for an already-converted script is RED (stale-allowlist, and nothing else)" ok
else row "S6-HB mutation (stale): a stale allowlist entry is not (only) reported" fail "reasons='$S6H_MS_R'"; fi
# M-grow: a new argv heartbeat curl in a new file, and one in a converted probe script (the allowlist is empty, so any argv URL is a violation).
S6H_MN="$(s6h_fresh mn)"; assert_fixture_dir "$S6H_MN"; printf '%s\n' 'NOTE=heartbeat' 'curl -fsS "$HB_HEARTBEAT_URL" >/dev/null' > "$S6H_MN/$S6H_DIR/zz-new-heartbeat.sh"
s6h_judge "$S6H_MN"; S6H_MNA="$S6H_J_REASONS"
S6H_MN2="$(s6h_fresh mn2)"; assert_fixture_dir "$S6H_MN2"; printf '%s\n' '  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null' >> "$S6H_MN2/$S6H_DIR/web-zot-consumer-probe.sh"
s6h_judge "$S6H_MN2"; S6H_MNB="$S6H_J_REASONS"
if [[ "$S6H_MNA" == *"argv:$S6H_DIR/zz-new-heartbeat.sh"* && "$S6H_MNB" == *"argv:$S6H_DIR/web-zot-consumer-probe.sh"* ]]; then row "S6-HB mutation (growth): a new heartbeat script with its URL on argv is RED, and so is a violating curl appended to a converted probe (no allowlist to hide behind)" ok
else row "S6-HB mutation (growth): the residual allowlist can grow silently" fail "new='$S6H_MNA' extra='$S6H_MNB'"; fi
# M-floor: the scanned population renamed away: 0 heartbeat scripts must be RED, never a clean bill.
S6H_MF="$(s6h_fresh mf)"; sed -i -E 's/[Hh][Ee][Aa][Rr][Tt][Bb][Ee][Aa][Tt]/hrtbt/g' "$S6H_MF/$S6H_DIR"/*.sh
s6h_judge "$S6H_MF"
if [[ "$S6H_J_FILES" -eq 0 && "$S6H_J_REASONS" == *floor* ]]; then row "S6-HB mutation (floor): with every heartbeat word renamed the scan sees 0 scripts and the floor is RED" ok
else row "S6-HB mutation (floor): a scan that sees nothing is not RED" fail "files=$S6H_J_FILES reasons='$S6H_J_REASONS'"; fi
# Must-PASS (Guard 2 row 8, population half): the control probes. A non-heartbeat probe whose variable is also named URL is outside the population; the
# local health curl next to a heartbeat is not a heartbeat variable. The unmodified scratch tree is GREEN first (so the controls are the only change).
s6h_judge "$S6H/base"; S6H_BASE_REASONS="$S6H_J_REASONS"; S6H_BASE_FILES="$S6H_J_FILES"
S6H_MP="$(s6h_fresh mp)"; assert_fixture_dir "$S6H_MP"
printf '%s\n' 'NOTE=heartbeat' 'INNGEST_HEALTH_URL="${X:-http://127.0.0.1:8288/health}"' 'curl -fsS "$INNGEST_HEALTH_URL" >/dev/null' > "$S6H_MP/$S6H_DIR/zz-health-next-to-heartbeat.sh"
printf '%s\n' 'URL="${PROBE_URL:?}"' 'curl -sS --max-time 20 "$URL" >/dev/null' > "$S6H_MP/$S6H_DIR/zz-plain-url-probe.sh"
s6h_judge "$S6H_MP"
if [[ -z "$S6H_BASE_REASONS" && -z "$S6H_J_REASONS" && "$S6H_J_FILES" -eq $((S6H_BASE_FILES + 1)) ]]; then row "S6-HB must-pass: a local health curl beside a heartbeat, and a non-heartbeat probe whose variable is also named URL, are GREEN (only the first joins the population)" ok
else row "S6-HB must-pass: a control probe is flagged, or the population moved unexpectedly" fail "base='$S6H_BASE_REASONS' reasons='$S6H_J_REASONS' files=$S6H_J_FILES base_files=$S6H_BASE_FILES"; fi
echo "=== stage S6-HB: Guard 2 rows (heartbeat URL off curl argv: derived population, residual allowlist, converted-script identity) done ==="

