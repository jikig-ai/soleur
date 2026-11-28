# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# =====================================================================================
# STAGE S7 (argv-bearer sweep, Guard 3 for markdown, #10093): no tracked agent-run markdown teaches a bearer, apikey or webhook-signature header on curl argv.
#
# PROPERTY. No tracked `plugins/**/*.md` carries a `curl` command word together with a `-H`/`--header` whose header name is one of NINE names, outside
# the residual allowlist: Authorization, apikey, X-Api-Key, Private-Token, Api-Key, plus the four more that Rule E of
# scripts/lint-shell-trace-credential-refusal.py names (CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256, X-Soleur-KB-Drift-Signature).
# An agent copies a snippet verbatim, and argv shows in /proc/<pid>/cmdline; the compliant form puts the header on curl's stdin config (`--config -`).
# Rule E does not read markdown, so for the nine names in plugin markdown this stage is the only recurrence guard.
#
# SCOPE, STATED PLAINLY. S7 is the guard for those nine header names, on a curl command word, in `plugins/**/*.md`, and for nothing wider. A green S7 does
# NOT mean "no secret reaches argv anywhere in the repo or in anything an agent reads". The classes below are outside it.
#
# DERIVATION. ONE scan over `git ls-files` (tracked and untracked) `plugins/**/*.md`, excluding the plugin docs site (plugins/soleur/docs/) and any
# `knowledge-base/` tree (an exclusion of convenience, NOT a claim that those files are history: see NOT COVERED). It runs over LOGICAL lines: backslash
# continuations are joined (the `-H` is usually on the second line) and the join STOPS at a code-fence boundary (a continuation ending a line before the
# closing fence is flushed, never glued to the prose after it). A table cell is one physical line and is never split on pipe, semicolon or
# double-ampersand. Matches are pattern-anchored, not line-anchored: `-H`, `--header`, `--header=`, `-H"Authorization` with no space, `-H $'Authorization`
# and `-H $"Authorization` (ANSI-C and locale quoting), a lowercase header name, a short-option cluster ending in H. The curl command word is `curl`,
# `/usr/bin/curl`, `/usr/local/bin/curl`, `./curl` or `\curl`. A `curl` command word must be present, so prose that names `-H` without it, the argv-safe
# `-H @<(printf ...)` form (the header name is inside the process substitution), and the compliant `header = "Authorization: Bearer %s"` on `--config -`
# are all outside the pattern.
# A second rule (reason stdin:<file>): a logical line that holds `curl ... --config -` AND a second stdin consumer (`-d @-`, `--data-binary @-`,
# `-T -`, `-H @-`, a heredoc, or a pipe into curl beside the `< <(...)` feed) is RED, because both consume stdin and the config would be eaten.
#
# EXECUTED ROWS. The scan proves the BAD shape is absent; it never proves the converted snippet works. Three converted blocks (postmerge Phase 3.5,
# preflight Step 1.4, ship's infra-config-status probe) are therefore EXTRACTED from the real files and RUN under bash against a PATH stub `curl` (records
# argv and stdin), a stub `doppler` and `jq`, with a synthesized token: the token must be absent from every recorded argv and present on the recorded stdin
# config, a refused token (a space in it) must make ZERO curl calls, and a control proves the judge goes RED when a block puts the token on argv.
#
# EXPLICIT RESIDUAL ALLOWLIST (S7_ALLOW: file, the exact number of hits): skill-creator/references/api-security.md documents the chat-visibility threat
# model with BAD examples. THE ALLOWLIST IS PINNED, NOT "SHRINK ONLY": the judge's ceiling constant caps the entry count (-le), a count that moved is RED,
# the hit floor (the measured allowlisted count) makes a scan that sees nothing RED, and the ceiling ROW pins the entry and its measured count EXACTLY (-eq,
# as S6's row does), so deleting the entry is a deliberate edit of that row, the floor and the entry together.
#
# NOT COVERED, named (each was measured outside the scan; none is a claim that it is safe):
#   - clients other than curl: wget --header, httpie, `gh api -H`;
#   - credential spellings other than the nine header names on `-H`: `-u/--user user:secret`, `--oauth2-bearer`, `-b/--cookie` and a Cookie header,
#     Proxy-Authorization, X-Auth-Key, X-Auth-Token and any other header name, a token in a URL (`?access_token=`) or in `-d`/`-F` (api-security.md carries one
#     such line, `-F access_token=`, inside the allowlisted file, so it is neither counted nor flagged);
#   - a header carried in a variable (`-H "$AUTH_HEADER"`, `ARGS+=(-H ...)` on a prior line), an `eval`, and the spellings `curl.exe` and `**curl**`;
#   - a second stdin consumer spelled `-F f=@-`, `--form`, `-d @/dev/stdin`, `-T /dev/stdin`, `--data-ascii @-`, `-K-`;
#   - files that are not markdown (scripts are Guards 1 and 2; Rule E covers them), and markdown the scan does not walk: plugins/soleur/docs/, EVERY
#     knowledge-base/ tree (including knowledge-base/engineering/operations/runbooks/*.md, which agents DO read and which hold argv-bearer lines),
#     .github/PULL_REQUEST_TEMPLATE.md (converted by hand, but unscanned), apps/web-platform/infra/sentry/README.md (NOT converted: a path under apps/web-platform/infra/ fires the infra apply workflows on merge, so it waits for a PR that already owns an apply), apps/web-platform/infra/egress-gw-image.provenance.md;
#   - credential text echoed by workflows (`.github/workflows/scheduled-terraform-drift.yml` prints runbook commands).
# =====================================================================================
S7_ALLOW_CEIL=1; S7_HIT_FLOOR=5
S7_ALLOW=(
"plugins/soleur/skills/skill-creator/references/api-security.md	5"
)
# One TSV record per finding. V: a violating logical line (file, start line, text). Q: a curl that reads stdin twice (file, start line).
s7_scan() { # <root>
  python3 -I -c '
import re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "plugins"], capture_output=True, check=True).stdout.decode().split("\0")
cmd = re.compile(r"(?:^|[\s({;|&`\x27\"=])(?:\\|/usr/bin/|/usr/local/bin/|\./)?curl(?=\s|$)")
hdr = re.compile(r"(?<![\w-])(?:-[A-Za-z]*H|--header)(?:\s*=\s*|\s*)\$?[\"\x27]?\s*(?i:Authorization|apikey|X-Api-Key|Private-Token|Api-Key|CF-Access-Client-Id|CF-Access-Client-Secret|X-Signature-256|X-Soleur-KB-Drift-Signature)(?![\w-])")
cfg = re.compile(r"(?<![\w-])(?:--config|-K)(?:\s+|=)-(?=\s|$|[\"\x27])")
two = re.compile(r"(?<![\w-])(?:-[A-Za-z]*d|--data|--data-binary|--data-raw|--data-urlencode|--json)(?:\s*|=)[\"\x27]?@-(?=\s|$|[\"\x27])"
                 r"|(?<![\w-])(?:-[A-Za-z]*T|--upload-file)(?:\s+|=)[\"\x27]?-(?=\s|$|[\"\x27])"
                 r"|(?<![\w-])-H\s+@-(?=\s|$)|<<")
pipe = re.compile(r"\|\s*(?:\\|/usr/bin/|/usr/local/bin/|\./)?curl(?=\s|$)")
feed = re.compile(r"<\s*<\(")
for f in sorted(set(files)):
    if not re.match(r"^plugins/.*\.md$", f) or f.startswith("plugins/soleur/docs/") or "/knowledge-base/" in "/" + f: continue
    try: raw = open(root + "/" + f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError: continue
    logical, cur, start = [], "", 0
    for i, l in enumerate(raw, 1):
        s = l.strip()
        if s.startswith("```") or s.startswith("~~~"):
            if cur: logical.append((start, cur)); cur = ""
            logical.append((i, s)); continue
        if not cur: start = i
        if s.endswith("\\"): cur += s[:-1] + " "; continue
        logical.append((start, cur + s)); cur = ""
    if cur: logical.append((start, cur))
    for n, t in logical:
        if not cmd.search(t): continue
        if hdr.search(t): print("V\t%s\t%d\t%s" % (f, n, " ".join(t.split())[:80]))
        if cfg.search(t) and (two.search(t) or (pipe.search(t) and feed.search(t))): print("Q\t%s\t%d" % (f, n))
' "$1"
}
# The verdict over a root. Sets S7_J_REASONS (empty = GREEN) and S7_J_HITS. Reasons: floor, argv:<file>, allow-count:<file>, ceiling, stdin:<file>.
S7_J_REASONS=""; S7_J_HITS=0
s7_judge() { # <root>
  local root="$1" scan a file want got f
  scan="$(s7_scan "$root")"; S7_J_REASONS=""
  S7_J_HITS="$(grep -c '^V	' <<<"$scan" || true)"
  [[ "$S7_J_HITS" -ge "$S7_HIT_FLOOR" ]] || S7_J_REASONS+=" floor"
  [[ "${#S7_ALLOW[@]}" -le "$S7_ALLOW_CEIL" ]] || S7_J_REASONS+=" ceiling"
  # every file with a violating line must be allowlisted with exactly its count
  while IFS=$'\t' read -r got file; do
    [[ -n "$file" ]] || continue
    want=""; for a in "${S7_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'* ]] && want="${a##*$'\t'}"; done
    if [[ -z "$want" ]]; then S7_J_REASONS+=" argv:$file"; elif [[ "$want" != "$got" ]]; then S7_J_REASONS+=" allow-count:$file"; fi
  done < <(awk -F'\t' '$1 == "V" { n[$2]++ } END { for (k in n) print n[k] "\t" k }' <<<"$scan")
  # an allowlist entry whose file no longer carries a hit is stale (delete the entry and lower the floor together)
  for a in "${S7_ALLOW[@]}"; do
    file="${a%%$'\t'*}"
    got="$(awk -F'\t' -v f="$file" '$1 == "V" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    [[ "$got" -gt 0 ]] || S7_J_REASONS+=" allow-count:$file"
  done
  while IFS= read -r f; do [[ -n "$f" ]] && S7_J_REASONS+=" stdin:$f"; done < <(awk -F'\t' '$1 == "Q" { print $2 }' <<<"$scan" | sort -u)
  S7_J_REASONS="${S7_J_REASONS# }"
}
S7="$TMPD/s7"; assert_fixture_dir "$S7"; mkdir -p "$S7/base" "$S7/mut"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S7/base" || exit 1; git -C "$S7/base" init -q ) \
  || fatal "S7 could not create the scratch repository"
S7_CONVERTED=(
  plugins/soleur/skills/postmerge/SKILL.md
  plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md
  plugins/soleur/skills/postmerge/references/deploy-status-debugging.md
  plugins/soleur/skills/reproduce-bug/SKILL.md
  plugins/soleur/skills/preflight/SKILL.md
  plugins/soleur/skills/ship/SKILL.md
  plugins/soleur/agents/engineering/infra/infra-security.md
  plugins/soleur/agents/engineering/review/deployment-verification-agent.md
  plugins/soleur/skills/flag-delete/SKILL.md
  plugins/soleur/skills/flag-list/SKILL.md
)
S7_APIDOC="plugins/soleur/skills/skill-creator/references/api-security.md"
S7_SAFE=(plugins/soleur/skills/cf-token-scope/references/widen-playbook.md plugins/soleur/skills/trigger-cron/SKILL.md)
for f in "${S7_CONVERTED[@]}" "$S7_APIDOC" "${S7_SAFE[@]}"; do
  [[ -f "$REPO_ROOT/$f" ]] || fatal "S7 fixture source $f is missing"
  mkdir -p "$S7/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S7/base/$f"
done
s7_fresh() { local d="$S7/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S7/base" "$d" && printf '%s' "$d"; }
# A mini tree: the allowlisted documentation file (so the floor is met) plus ONE variant file zz.md holding the text under test.
S7_MINI="$S7/mini"; mkdir -p "$S7_MINI"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S7_MINI" || exit 1; git -C "$S7_MINI" init -q ) || fatal "S7 could not create the mini repository"
mkdir -p "$S7_MINI/$(dirname "$S7_APIDOC")" "$S7_MINI/plugins/zz"; cp "$S7/base/$S7_APIDOC" "$S7_MINI/$S7_APIDOC"
s7_variant() { # <name> <text, printf-%b escapes honoured> -> S7_J_REASONS for a mini tree whose zz.md holds exactly the text
  local d="$S7/mut/v-$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S7_MINI" "$d" || fatal "S7 variant copy"
  printf '%b\n' "$2" > "$d/plugins/zz/zz.md"; s7_judge "$d"
}
S7_Q="'" # a literal single quote for the variant texts
S7_PRINTF="< <(printf ${S7_Q}header = \"Authorization: Bearer %s\"\\\\n${S7_Q} \"\$T\")"

# --- the real tree ---------------------------------------------------------------------
s7_judge "$REPO_ROOT"; S7_REAL_REASONS="$S7_J_REASONS"; S7_REAL_HITS="$S7_J_HITS"
if [[ -z "$S7_REAL_REASONS" ]]; then row "S7 Guard 3: no tracked plugins/**/*.md puts an Authorization, apikey, X-Api-Key, Private-Token, Api-Key, CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256 or X-Soleur-KB-Drift-Signature header on curl argv outside the residual allowlist, and none reads stdin twice ($S7_REAL_HITS hits, all in the allowlisted documentation file)" ok
else row "S7 Guard 3: a markdown snippet puts a credential or signature header on curl argv, or reads stdin twice, outside the residual allowlist" fail "reasons='$S7_REAL_REASONS' hits=$S7_REAL_HITS"; fi
S7_ALLOW_N=0; for a in "${S7_ALLOW[@]}"; do S7_ALLOW_N=$((S7_ALLOW_N + 1)); done
if [[ "$S7_ALLOW_N" -eq "$S7_ALLOW_CEIL" && "$S7_ALLOW_N" -eq 1 && "${S7_ALLOW[0]}" == "$S7_APIDOC"$'\t'"$S7_HIT_FLOOR" ]]; then row "S7 allowlist ceiling: exactly $S7_ALLOW_CEIL residual entry ($S7_APIDOC, $S7_HIT_FLOOR measured hits; pinned exactly, so removing it edits this pin and the hit floor together)" ok
else row "S7 allowlist ceiling: the residual allowlist grew or its measured count moved" fail "entries=$S7_ALLOW_N ceiling=$S7_ALLOW_CEIL"; fi
# The unmodified scratch tree is GREEN first, so every mutation row below changes exactly one thing against a known-good tree.
s7_judge "$S7/base"; S7_BASE_REASONS="$S7_J_REASONS"
if [[ -z "$S7_BASE_REASONS" ]]; then row "S7 control: the unmutated scratch tree (the ten converted files, the documentation file and the argv-safe controls) is GREEN" ok
else row "S7 control: the unmutated scratch tree is not GREEN" fail "reasons='$S7_BASE_REASONS'"; fi

# --- mutation rows (the SAME scan over a scratch tree) ----------------------------------------
# M1: a violating header re-added to a converted file.
S7_M1="$(s7_fresh m1)"; S7_M1F="plugins/soleur/skills/reproduce-bug/SKILL.md"
assert_fixture_dir "$S7_M1"
printf '%s\n' '```bash' 'curl -s -H "Authorization: Bearer $TOK" "https://x.example/api"' '```' >> "$S7_M1/$S7_M1F"
s7_judge "$S7_M1"
if [[ "$S7_J_REASONS" == "argv:$S7_M1F" ]]; then row "S7 mutation 1: the argv bearer header re-added to a converted file is RED, by file identity and nothing else" ok
else row "S7 mutation 1: a re-added argv header in a converted file is not caught" fail "reasons='$S7_J_REASONS'"; fi
# M2: a compliant converted snippet in one file, then a violating one in a different file: only the second is named.
S7_M2="$(s7_fresh m2)"
assert_fixture_dir "$S7_M2"
printf '%s\n' '```bash' "curl --disable --proto '=https' -m 30 -fsS --config - \"\$URL\" $S7_PRINTF" '```' >> "$S7_M2/plugins/soleur/skills/postmerge/SKILL.md"
printf '%s\n' '```bash' 'curl -fsS -H "apikey: $K" "$URL"' '```' >> "$S7_M2/plugins/soleur/skills/preflight/SKILL.md"
s7_judge "$S7_M2"
if [[ "$S7_J_REASONS" == "argv:plugins/soleur/skills/preflight/SKILL.md" ]]; then row "S7 mutation 2: a compliant snippet then a violating one in another file is RED for the second file only (identity, not a count)" ok
else row "S7 mutation 2: the second file's violation is not named, or the compliant snippet is flagged" fail "reasons='$S7_J_REASONS'"; fi
# M3: the allowlist grows by one entry (a new file with a hit, allowlisted with its count): the ceiling is RED.
S7_M3="$(s7_fresh m3)"; assert_fixture_dir "$S7_M3"
printf '%s\n' '`curl -H "Authorization: Bearer $T" "$U"`' > "$S7_M3/plugins/soleur/skills/zz-new.md"
S7_ALLOW_SAVE=("${S7_ALLOW[@]}"); S7_ALLOW+=("plugins/soleur/skills/zz-new.md	1")
s7_judge "$S7_M3"; S7_M3R="$S7_J_REASONS"; S7_ALLOW=("${S7_ALLOW_SAVE[@]}")
if [[ "$S7_M3R" == "ceiling" ]]; then row "S7 mutation 3: the allowlist growing by one entry is RED on the ceiling (and the new entry's own hit is the only thing it hides)" ok
else row "S7 mutation 3: the residual allowlist can grow silently" fail "reasons='$S7_M3R'"; fi
# M3b: one more hit inside the allowlisted documentation file (the entry names a count, not a licence). M3c: an entry whose file carries no hit (stale).
S7_M3B="$(s7_fresh m3b)"; assert_fixture_dir "$S7_M3B"
printf '%s\n' 'curl -sS -H "Authorization: Bearer $T" "$U"' >> "$S7_M3B/$S7_APIDOC"
s7_judge "$S7_M3B"; S7_M3BR="$S7_J_REASONS"
S7_M3C="$(s7_fresh m3c)"; S7_ALLOW_SAVE=("${S7_ALLOW[@]}"); S7_ALLOW=("plugins/soleur/skills/zz-gone.md	1")
s7_judge "$S7_M3C"; S7_M3CR="$S7_J_REASONS"; S7_ALLOW=("${S7_ALLOW_SAVE[@]}")
if [[ "$S7_M3BR" == "allow-count:$S7_APIDOC" && "$S7_M3CR" == *"allow-count:plugins/soleur/skills/zz-gone.md"* ]]; then row "S7 mutation 3 (count, stale): one more hit inside the allowlisted file is RED on its count, and an entry whose file has no hit is RED as stale" ok
else row "S7 mutation 3 (count, stale): the allowlisted count can move, or a stale entry survives" fail "extra-hit='$S7_M3BR' stale='$S7_M3CR'"; fi
# M4: every scanned header word renamed in a scratch tree: the scan sees 0 hits and the floor is RED, never a clean bill.
S7_M4="$(s7_fresh m4)"; find "$S7_M4/plugins" -name '*.md' -exec sed -i -E 's/[Aa]uthorization/Authz/g; s/apikey/apik/g; s/[Xx]-[Aa]pi-[Kk]ey/x-k/g; s/[Pp]rivate-[Tt]oken/priv/g; s/[Aa]pi-[Kk]ey/ak/g; s/[Cc][Ff]-[Aa]ccess-[Cc]lient-/cfx-/g; s/[Xx]-[Ss]ignature-256/xs/g; s/[Xx]-[Ss]oleur-[Kk][Bb]-[Dd]rift-[Ss]ignature/xd/g' {} +
s7_judge "$S7_M4"
if [[ "$S7_J_HITS" -eq 0 && "$S7_J_REASONS" == *floor* ]]; then row "S7 mutation 4: with every scanned header word renamed the scan sees 0 hits and the floor is RED" ok
else row "S7 mutation 4: a scan that sees nothing is not RED" fail "hits=$S7_J_HITS reasons='$S7_J_REASONS'"; fi
# M5: the header on a backslash-continuation line of an otherwise converted snippet (a per-line scan is green over it).
s7_variant m5 "\`\`\`bash\ncurl --disable --proto '=https' -m 30 -fsS --config - \\\\\n  -H \"Authorization: Bearer \$T\" \"\$U\" $S7_PRINTF\n\`\`\`"
S7_M5R="$S7_J_REASONS"
s7_variant m5b "\`\`\`bash\ncurl -fsS \"\$U\" \\\\\n  -H \"\$EXTRA\" \\\\\n  --header 'apikey: x'\n\`\`\`"
if [[ "$S7_M5R" == "argv:plugins/zz/zz.md" && "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]]; then row "S7 mutation 5: the header on a continuation line (also two joins deep) is RED through the logical-line join" ok
else row "S7 mutation 5: a header on a continuation line is not caught" fail "one-join='$S7_M5R' two-join='$S7_J_REASONS'"; fi
# M6: shape variants, one per spelling, each RED: --header=, lowercase name, -H"Authorization with no space, a table cell, a short-option cluster.
S7_M6BAD=""
s7_variant m6a 'curl -sS --header=Authorization:Bearer-x "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" --header="
s7_variant m6b 'curl -sS -H "authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" lowercase"
s7_variant m6c 'curl -sS -H"Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" -H-nospace"
s7_variant m6d '| Error rate | `curl -sS -H "Authorization: Bearer $T" "$U"` divided by x | error_rate > 0.01 |'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" table-cell"
s7_variant m6e 'curl -sSH "Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" cluster"
s7_variant m6f '$ curl --header "Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" --header-space"
s7_variant m6g "curl -sS -H \$'Authorization: Bearer \$T' \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" ansi-c-quote"
s7_variant m6h "curl -sS -H \$\"Authorization: Bearer \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" locale-quote"
if [[ -z "$S7_M6BAD" ]]; then row "S7 mutation 6: --header=, a lowercase header name, -H\"Authorization with no space, a table cell, a short-option cluster, --header and an ANSI-C or locale quote (-H \$'Authorization, -H \$\"Authorization) are each RED" ok
else row "S7 mutation 6: a header spelling slips through" fail "missed=$S7_M6BAD"; fi
# M6-lead: the curl command word is recognised after each lead-in (command substitution, list operators, a pipe, a backtick span, a path).
S7_M6LBAD=""
for lead in '$(' '{' 'a;' 'a|' 'a&&' '`' "'" '"' '=' '/usr/bin/' '/usr/local/bin/' './' "\\\\"; do
  s7_variant "m6l" "x=${lead}curl -sS -H \"Authorization: Bearer \$T\" \"\$U\")"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6LBAD+=" [$lead]"
done
if [[ -z "$S7_M6LBAD" ]]; then row "S7 mutation 6 (lead): a curl directly after \$(, {, ;, |, &&, a backtick, a quote, = and as /usr/bin/curl, /usr/local/bin/curl, ./curl and \\curl is found, each RED" ok
else row "S7 mutation 6 (lead): a curl lead-in slips through" fail "missed=$S7_M6LBAD"; fi
# M6-names: one variant per header-name alternative of the pattern (a control that drives one arm lets the others be deleted unseen).
S7_M6NBAD=""
for nm in Authorization apikey X-Api-Key Private-Token Api-Key; do
  s7_variant "m6n-$nm" "curl -sS -H \"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6NBAD+=" $nm"
done
if [[ -z "$S7_M6NBAD" ]]; then row "S7 mutation 6 (names): each of Authorization, apikey, X-Api-Key, Private-Token and Api-Key on curl argv is RED (the Rule E four follow)" ok
else row "S7 mutation 6 (names): a header name of the pattern is not caught" fail "missed=$S7_M6NBAD"; fi
# M6-names-2: the four Rule E names beyond the original five (the deploy webhook triple and the KB drift signature), each in the spellings the
# first five are proven in: plain, lowercase, no-space after -H, --header=, a table cell and a backslash continuation (the shape tolerance is the same).
S7_M6N2BAD=""
for nm in CF-Access-Client-Id CF-Access-Client-Secret X-Signature-256 X-Soleur-KB-Drift-Signature; do
  lnm="${nm,,}"
  s7_variant "m6p" "curl -sS -H \"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm"
  s7_variant "m6p" "curl -sS -H \"$lnm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(lowercase)"
  s7_variant "m6p" "curl -sS -H\"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(-H-nospace)"
  s7_variant "m6p" "curl -sS --header=\"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(--header=)"
  s7_variant "m6p" "| Probe | \`curl -sS -H \"$nm: \$T\" \"\$U\"\` | status 200 |"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(table-cell)"
  s7_variant "m6p" "curl --disable -fsS --config - \"\$U\" \\\\\n  -H \"$nm: \$T\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(continuation)"
done
if [[ -z "$S7_M6N2BAD" ]]; then row "S7 mutation 6 (names, Rule E set): CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256 and X-Soleur-KB-Drift-Signature on curl argv are each RED in the plain, lowercase, -H-no-space, --header=, table-cell and continuation-line spellings" ok
else row "S7 mutation 6 (names, Rule E set): a Rule E header name or spelling slips through" fail "missed=$S7_M6N2BAD"; fi
# M7: a continuation ending a line just before the closing fence: no false positive (the join stops at the fence), and a real violation on that
# last line is not hidden.
s7_variant m7a "\`\`\`bash\ncurl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" \\\\\n\`\`\`\nSend -H \"Authorization: Bearer \$T\" with it."; S7_M7A="$S7_J_REASONS"
s7_variant m7b "\`\`\`bash\ncurl -fsS -H \"Authorization: Bearer \$T\" \\\\\n\`\`\`\nProse after the fence."; S7_M7B="$S7_J_REASONS"
s7_variant m7c "curl -sS \"\$U\" \\\\\n\`\`\`\\\\\n-H \"Authorization: Bearer \$T\""; S7_M7C="$S7_J_REASONS"
s7_variant m7d "curl -sS \"\$U\" \\\\\n~~~\\\\\n-H \"Authorization: Bearer \$T\""; S7_M7D="$S7_J_REASONS"
if [[ -z "$S7_M7A" && "$S7_M7B" == "argv:plugins/zz/zz.md" && -z "$S7_M7C" && -z "$S7_M7D" ]]; then row "S7 mutation 7: a continuation ending just before the closing fence is no false positive (the join stops at the fence) and hides no curl" ok
else row "S7 mutation 7: the logical-line join crosses a fence boundary, or hides a curl before it" fail "false-positive='$S7_M7A' hidden='$S7_M7B' glued-backtick-fence='$S7_M7C' glued-tilde-fence='$S7_M7D'"; fi
# M8: a second stdin consumer beside --config -: each is RED; a plain -d body beside --config - is not.
S7_M8BAD=""
s7_variant m8a "curl --disable -fsS --config - -d @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -d@-"
s7_variant m8b "curl --disable -fsS --config - --data-binary @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" --data-binary"
s7_variant m8c "curl --disable -fsS --config - -T - \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -T"
s7_variant m8d "curl --disable -fsS --config - \"\$U\" <<EOF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" heredoc"
s7_variant m8e "echo x | curl --disable -fsS --config - \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" pipe-into-curl"
for sc in "-H @-" "--data @-" "--data-raw @-" "--json @-" "--data-urlencode @-" "--upload-file -" "-d@-"; do
  s7_variant "m8x" "curl --disable -fsS --config - $sc \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" [$sc]"
done
s7_variant m8k "curl --disable -fsS -K - -d @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -K"
s7_variant m8f "curl --disable -fsS --config - -d '{\"a\":1}' \"\$U\" $S7_PRINTF"; [[ -z "$S7_J_REASONS" ]] || S7_M8BAD+=" plain--d-flagged"
if [[ -z "$S7_M8BAD" ]]; then row "S7 mutation 8: every second stdin consumer (-d @-, --data(-binary|-raw|-urlencode) @-, --json @-, -T -, --upload-file -, -H @-, a heredoc, a pipe into curl, and -K - as the config) beside --config - is RED; an inline -d body beside it is GREEN" ok
else row "S7 mutation 8: a second stdin consumer beside --config - is not caught (or a plain -d body is)" fail "wrong=$S7_M8BAD"; fi
# Must-PASS: the compliant stdin-config form, the argv-safe -H @<(printf ...) form, prose naming -H with no curl command word, curl's own -H of a
# non-credential header, and the two excluded trees (the plugin docs site and a knowledge-base tree hold no agent-run snippet).
S7_MPBAD=""
s7_variant mp1 "(LC_ALL=C; case \"\$T\" in ''|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo \"token refused\" >&2; exit 1; }\ncurl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" $S7_PRINTF"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" stdin-config"
s7_variant mp2 "curl -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") https://api.cloudflare.com/client/v4/user/tokens/verify"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" argv-safe-H@"
s7_variant mp3 'Pass the token with `-H` and an Authorization header on the request, never on the command line.'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" prose-no-curl"
s7_variant mp4 'curl -sS -H "Content-Type: application/json" -d "{}" "$U"'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" non-credential-H"
s7_variant mp6 'curl -sS -H "Authorizations: x" -H "Api-Keyed: y" -H "apikeys: z" -H "X-Api-Key-Version: 2" "$U"'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" longer-header-names"
s7_variant mp7 "curl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" < <(printf 'header = \"X-Signature-256: sha256=%s\"\\\\nheader = \"CF-Access-Client-Id: %s\"\\\\nheader = \"CF-Access-Client-Secret: %s\"\\\\nheader = \"X-Soleur-KB-Drift-Signature: %s\"\\\\n' \"\$S\" \"\$I\" \"\$C\" \"\$D\")"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" rule-e-names-on-stdin-config"
s7_variant mp8 "curl -sS -H \"CF-Access-Client-Id-Hint: x\" -H \"CF-Access-Client-Secretary: y\" -H \"X-Signature-2560: z\" -H \"X-Signature-256-Version: 2\" -H \"X-Soleur-KB-Drift-Signatures: w\" \"\$U\""; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" longer-rule-e-names"
S7_MPD="$S7/mut/v-mp5"; assert_fixture_dir "$S7_MPD"; rm -rf "$S7_MPD"; cp -a "$S7_MINI" "$S7_MPD"; mkdir -p "$S7_MPD/plugins/soleur/docs" "$S7_MPD/plugins/soleur/knowledge-base/x"
printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/zz/zz.txt"
printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/soleur/docs/zz.md"; printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/soleur/knowledge-base/x/zz.md"
s7_judge "$S7_MPD"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" excluded-trees"
if [[ -z "$S7_MPBAD" ]]; then row "S7 must-pass: the stdin-config form, the argv-safe -H @<(printf ...) form, prose with -H and no curl, non-credential -H headers (including names that only start like a credential name), and the docs site, a knowledge-base tree and a non-markdown file are GREEN" ok
else row "S7 must-pass: a compliant form is flagged" fail "flagged=$S7_MPBAD"; fi
# --- EXECUTED rows: the converted blocks are extracted from the real files and RUN, not only scanned ---------------------------------------
S7_X="$S7/exec"; assert_fixture_dir "$S7_X"; mkdir -p "$S7_X/bin"
cat > "$S7_X/bin/curl" <<'S7X_STUB'
#!/usr/bin/env bash
# Recording stub: argv one per line, stdin only when the call carries `--config -` (as curl would), a canned body.
d="${S7X_REC:?}"; n=0; [[ -r "$d/n" ]] && read -r n < "$d/n"; n=$((n + 1)); printf '%s\n' "$n" > "$d/n"
printf '%s\n' "$@" > "$d/argv.$n"
cfg=0; prev=""; for a in "$@"; do [[ "$prev" == "--config" && "$a" == "-" ]] && cfg=1; prev="$a"; done
if [[ "$cfg" == 1 ]]; then cat > "$d/stdin.$n"; else : > "$d/stdin.$n"; fi
printf '[]\n'
S7X_STUB
cat > "$S7_X/bin/doppler" <<'S7X_STUB'
#!/usr/bin/env bash
# `doppler secrets get NAME ...`: a synthesized value, distinct per NAME so a mix-up between secrets is visible; NAME == S7X_BADNAME gets a
# value with a space in it (a refused shape), so ONE secret at a time can be made bad.
[[ -n "${S7X_BADNAME:-}" && "${3:-}" == "$S7X_BADNAME" ]] && { printf 'bad val'; exit 0; }
case "${3:-}" in
  SENTRY_ORG) printf 'synthorg' ;;
  NEXT_PUBLIC_SUPABASE_URL) printf 'https://sup.example.invalid' ;;
  APP_DOMAIN_BASE) printf 'example.invalid' ;;
  *) printf '%s-%s' "${S7X_TOKEN:-}" "${3:-}" ;;
esac
S7X_STUB
printf '#!/usr/bin/env bash\ncat\n' > "$S7_X/bin/jq"
chmod +x "$S7_X/bin/curl" "$S7_X/bin/doppler" "$S7_X/bin/jq"
S7X_GOOD="synthtok0123.ab_c~d+e/f=g-h"; S7X_BAD="bad val"
S7X_PYDIR="$(dirname "$(type -P python3)")"
# s7x_block <file> <marker>... -> the ONE fenced block of that file holding `--config -` and every marker (a count other than 1 is a failure, never a pass)
s7x_block() {
  python3 -I -c '
import sys
f, marks = sys.argv[1], sys.argv[2:]
blocks, cur = [], None
for l in open(f, encoding="utf-8").read().split("\n"):
    if l.strip().startswith("```"):
        if cur is None: cur = []
        else: blocks.append("\n".join(cur)); cur = None
        continue
    if cur is not None: cur.append(l)
hit = [b for b in blocks if "--config -" in b and all(m in b for m in marks)]
if len(hit) != 1: sys.exit(3)
print(hit[0])
' "$REPO_ROOT/$1" "${@:2}"
}
# s7x_run <row> <block file> [secret NAME made bad]: runs the block under bash in a scrubbed environment; sets S7X_RC, S7X_OUT (stdout+stderr), S7X_N (curl calls), S7X_REC
S7X_RC=0; S7X_OUT=""; S7X_N=0; S7X_REC=""
s7x_run() {
  S7X_REC="$S7_X/rec-$1"; assert_fixture_dir "$S7X_REC"; rm -rf "$S7X_REC"; mkdir -p "$S7X_REC"
  S7X_RC=0; S7X_OUT="$(cd "$S7_X" && env -i PATH="$S7_X/bin:$S7X_PYDIR:/usr/bin:/bin" HOME="$S7_X" S7X_REC="$S7X_REC" S7X_TOKEN="$S7X_GOOD" S7X_BADNAME="${3:-}" bash "$2" < /dev/null 2>&1)" || S7X_RC=$?
  S7X_N=0; [[ -r "$S7X_REC/n" ]] && read -r S7X_N < "$S7X_REC/n"; return 0
}
# s7x_argv_has <needle>: 0 when any recorded argv holds the needle
s7x_argv_has() { local i; for ((i = 1; i <= S7X_N; i++)); do grep -qF -- "$1" "$S7X_REC/argv.$i" && return 0; done; return 1; }
# s7x_good <expected stdin config> <secret>...: reasons (empty = good) for a run on a GOOD token: rc 0, exactly one call, no secret on argv, the config on stdin
s7x_good() {
  local want="$1" r="" nd got; shift
  [[ "$S7X_RC" -eq 0 ]] || r+=" rc=$S7X_RC"
  [[ "$S7X_N" -eq 1 ]] || r+=" calls=$S7X_N"
  for nd in "$@"; do ! s7x_argv_has "$nd" || r+=" argv-has-secret"; done
  got=""; [[ -r "$S7X_REC/stdin.1" ]] && got="$(< "$S7X_REC/stdin.1")"
  [[ "$got" == "$want" ]] || r+=" stdin-differs"
  printf '%s' "${r# }"
}
S7X_PM="$S7_X/blk-pm.sh"; S7X_PF="$S7_X/blk-pf.sh"; S7X_SH="$S7_X/blk-sh.sh"; S7X_DS="$S7_X/blk-ds.sh"
s7x_block plugins/soleur/skills/postmerge/references/deploy-status-debugging.md "hooks/deploy-status" > "$S7X_DS" || { rm -f "$S7X_DS"; }
s7x_block plugins/soleur/skills/postmerge/SKILL.md "monitors/" > "$S7X_PM" || { rm -f "$S7X_PM"; }
s7x_block plugins/soleur/skills/preflight/SKILL.md "rest/v1/" > "$S7X_PF" || { rm -f "$S7X_PF"; }
s7x_block plugins/soleur/skills/ship/SKILL.md "infra-config-status" > "$S7X_SH" || { rm -f "$S7X_SH"; }

# postmerge Phase 3.5 (advisory): good token -> one call, token on stdin only; a refused token -> ZERO calls, a SKIPPED line, exit 0
S7X_BAD_REASONS=""
if [[ -s "$S7X_PM" ]]; then
  s7x_run pm-good "$S7X_PM"; S7X_R1="$(s7x_good "header = \"Authorization: Bearer $S7X_GOOD-SENTRY_AUTH_TOKEN\"" "$S7X_GOOD")"; [[ -z "$S7X_R1" ]] || S7X_BAD_REASONS+=" good:$S7X_R1"
  s7x_run pm-bad "$S7X_PM" SENTRY_AUTH_TOKEN
  [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" refused-made-$S7X_N-calls"
  [[ "$S7X_RC" -eq 0 && "$S7X_OUT" == *"SKIPPED"* && "$S7X_OUT" == *"SENTRY_TOKEN"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" refused-not-a-named-skip(rc=$S7X_RC)"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (postmerge Phase 3.5): the block run under bash puts the token on curl's stdin config only (none on the recorded argv, exactly one call, so the control saw a call), and a token with a space in it makes zero calls, prints a SKIPPED line naming the variable and exits 0 (advisory phase)" ok
else row "S7 executed (postmerge Phase 3.5): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# preflight Step 1.4: the block is self-sufficient in ONE call (it fetches its own URL and key), sends both headers on stdin, refuses a bad key with zero calls and a message naming the variable
S7X_BAD_REASONS=""
if [[ -s "$S7X_PF" ]]; then
  s7x_run pf-good "$S7X_PF"
  S7X_R1="$(s7x_good "$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"' "$S7X_GOOD-SUPABASE_SERVICE_ROLE_KEY" "$S7X_GOOD-SUPABASE_SERVICE_ROLE_KEY")" "$S7X_GOOD")"; [[ -z "$S7X_R1" ]] || S7X_BAD_REASONS+=" good:$S7X_R1"
  s7x_argv_has "https://sup.example.invalid/rest/v1/" || S7X_BAD_REASONS+=" url-not-fetched-in-block"
  s7x_run pf-bad "$S7X_PF" SUPABASE_SERVICE_ROLE_KEY
  [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" refused-made-$S7X_N-calls"
  [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"SERVICE_ROLE_KEY unset or not"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" refused-message(rc=$S7X_RC)"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (preflight Step 1.4): the block run under bash in one call fetches its own URL and key, sends both headers on curl's stdin config only, and a key with a space makes zero calls and a nonzero exit naming SERVICE_ROLE_KEY" ok
else row "S7 executed (preflight Step 1.4): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# ship infra-config-status: the signature and the Access pair (the Rule E names) all ride stdin; any one of them refused -> zero calls
S7X_BAD_REASONS=""
if [[ -s "$S7X_SH" ]]; then
  s7x_run sh-good "$S7X_SH"
  S7X_SIG=""; [[ -r "$S7X_REC/stdin.1" ]] && S7X_SIG="$(sed -n '1s/^header = "X-Signature-256: sha256=\([0-9a-f]\{64\}\)"$/\1/p' "$S7X_REC/stdin.1")"
  S7X_R1="$(s7x_good "$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"' "$S7X_SIG" "$S7X_GOOD-CF_ACCESS_CLIENT_ID" "$S7X_GOOD-CF_ACCESS_CLIENT_SECRET")" "$S7X_GOOD" "$S7X_SIG")"
  [[ -z "$S7X_R1" && -n "$S7X_SIG" ]] || S7X_BAD_REASONS+=" good:${S7X_R1:-no-signature-line}"
  for S7X_NM in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET APP_DOMAIN_BASE; do
    s7x_run "sh-bad-$S7X_NM" "$S7X_SH" "$S7X_NM"
    S7X_VAR="${S7X_NM/CF_ACCESS_CLIENT_/CF_ACCESS_}"
    [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-made-$S7X_N-calls"
    [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"$S7X_VAR unset or not [A-Za-z0-9._~+/=-]"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-message-not-naming-$S7X_VAR(rc=$S7X_RC)"
  done
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (ship infra-config-status): the block run under bash sends X-Signature-256, CF-Access-Client-Id and CF-Access-Client-Secret on curl's stdin config only (none on the recorded argv), and a refused Access id or secret (each made bad alone) makes zero calls and a nonzero exit" ok
else row "S7 executed (ship infra-config-status): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# postmerge deploy-status-debugging: the signature and the Access pair ride stdin, and a refused id or secret (each alone) makes zero calls and names that variable
S7X_BAD_REASONS=""
if [[ -s "$S7X_DS" ]]; then
  s7x_run ds-good "$S7X_DS"
  S7X_SIG=""; [[ -r "$S7X_REC/stdin.1" ]] && S7X_SIG="$(sed -n '1s/^header = "X-Signature-256: sha256=\([0-9a-f]\{64\}\)"$/\1/p' "$S7X_REC/stdin.1")"
  S7X_R1="$(s7x_good "$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"' "$S7X_SIG" "$S7X_GOOD-CF_ACCESS_CLIENT_ID" "$S7X_GOOD-CF_ACCESS_CLIENT_SECRET")" "$S7X_GOOD" "$S7X_SIG")"
  [[ -z "$S7X_R1" && -n "$S7X_SIG" ]] || S7X_BAD_REASONS+=" good:${S7X_R1:-no-signature-line}"
  s7x_argv_has "https://deploy.soleur.ai/hooks/deploy-status" || S7X_BAD_REASONS+=" url-not-called"
  for S7X_NM in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
    s7x_run "ds-bad-$S7X_NM" "$S7X_DS" "$S7X_NM"
    [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-made-$S7X_N-calls"
    [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"$S7X_NM unset or not [A-Za-z0-9._~+/=-]"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-message(rc=$S7X_RC)"
  done
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (postmerge deploy-status-debugging): the block run under bash sends X-Signature-256, CF-Access-Client-Id and CF-Access-Client-Secret on curl's stdin config only (so a dropped --config - or a swapped id and secret is RED), and a refused Access id or secret makes zero calls and a nonzero exit naming that variable" ok
else row "S7 executed (postmerge deploy-status-debugging): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# CONTROL: the judge must go RED on a block that puts the token on argv, and a block whose shape guard is neutralised must make a call for a refused token
S7X_BAD_REASONS=""
if [[ -s "$S7X_PM" ]]; then
  S7X_BLK="$(< "$S7X_PM")"
  S7X_MUT_ARGV="${S7X_BLK//--config - /-H \"Authorization: Bearer \$SENTRY_TOKEN\" }"
  S7X_G="''|*[!A-Za-z0-9._~+/=-]*"; S7X_Q="''"; S7X_MUT_GUARD="${S7X_BLK//"$S7X_G"/$S7X_Q}"
  [[ "$S7X_MUT_ARGV" != "$S7X_BLK" ]] || S7X_BAD_REASONS+=" argv-mutation-did-not-land"
  [[ "$S7X_MUT_GUARD" != "$S7X_BLK" ]] || S7X_BAD_REASONS+=" guard-mutation-did-not-land"
  printf '%s\n' "$S7X_MUT_ARGV" > "$S7_X/blk-mut-argv.sh"; printf '%s\n' "$S7X_MUT_GUARD" > "$S7_X/blk-mut-guard.sh"
  s7x_run mut-argv "$S7_X/blk-mut-argv.sh"; S7X_R1="$(s7x_good "header = \"Authorization: Bearer $S7X_GOOD-SENTRY_AUTH_TOKEN\"" "$S7X_GOOD")"
  [[ "$S7X_R1" == *argv-has-secret* && "$S7X_R1" == *stdin-differs* ]] || S7X_BAD_REASONS+=" argv-token-not-RED('$S7X_R1')"
  s7x_run mut-guard "$S7_X/blk-mut-guard.sh" SENTRY_AUTH_TOKEN
  [[ "$S7X_N" -ge 1 ]] || S7X_BAD_REASONS+=" neutralised-guard-still-made-no-call"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed control: the judge is RED when the block puts the token on argv (token on argv, nothing on stdin), and a block with the shape guard neutralised makes a curl call for a refused token (so the zero-call assertions can fail)" ok
else row "S7 executed control: the executed rows cannot go RED" fail "reasons='${S7X_BAD_REASONS# }'"; fi
echo "=== stage S7: Guard 3 rows (markdown bearer headers off curl argv: derived census, residual allowlist, logical-line join, stdin conflict) done ==="

# =====================================================================================
# CONTROLS FOR THE VERDICT-OWNING HELPERS. Every helper that names failed checks (bk_check, bs_refusal, bs_ok_call, hmx_refused, evaluate_hmac,
# evaluate_body) is driven here with a FABRICATED row directory that is green except for exactly ONE doctored fact, and the row requires the helper's
# output to be exactly that one check's name. A clause with several alternatives (a regex `a|b|c`, a loop over values, an `||` of two files) gets one
# variant PER ALTERNATIVE: a control that drives one arm lets the others be deleted unseen (measured at review: the SYNTHMARK0001 arm of the echo test,
# the -sSu bundle and --user= arms of the user-token test, the username in the value test, -macopt, and two of the three config conjuncts all survived). Without this a clause could be deleted from a helper with the whole battery green (measured at review: 39 of 66
# verdict clauses were deletable, the helpers' own clauses being redundant with a sibling on every real row). The un-doctored directory is
# required to come out GREEN first, so a helper that fails everything cannot satisfy a single row. `evaluate` already has this (kind_row).
# =====================================================================================
ctl_dir() { local d="$ROWS/ctl-$1"; assert_fixture_dir "$d"; mkdir -p "$d/shim/calls" "$d/shim/tools"; printf '%s' "$d"; }
ctl_bad=""
ctl_want() { # <label> <got> <want>: records a mismatch in ctl_bad
  [[ "$2" == "$3" ]] || ctl_bad+=" [$1: got '${2:-<empty>}' want '${3:-<empty>}']"
}
ctl_row() { # <label>: one row from ctl_bad
  if [[ -z "$ctl_bad" ]]; then row "$1" ok; else row "$1" fail "$ctl_bad"; fi
  ctl_bad=""
}

# --- bk_check (the backup arm's mask/argv/stdin/body clauses) ---
bkc_mk() { # <variant> -> row name
  local v="$1" d tok="$BK_CANARY"; d="$(ctl_dir "bkc-$v")"; assert_fixture_dir "$d"
  printf '::add-mask::%s\nSHIMCALL 1\nbackup image id=111 ready\n' "$tok" > "$d/out"
  printf 'curl\0--config\0-\0' > "$d/shim/calls/1.argv"
  printf 'header = "Authorization: Bearer %s"\n' "$tok" > "$d/shim/calls/1.stdin"
  case "$v" in
    good) ;;
    mask-not-first)  printf 'preface\n::add-mask::%s\nSHIMCALL 1\n' "$tok" > "$d/out" ;;
    mask-count)      printf '::add-mask::%s\nSHIMCALL 1\nleaked %s\n' "$tok" "$tok" > "$d/out" ;;
    mask-after-curl) printf '::add-mask::%s\nbackup image id=111 ready\n' "$tok" > "$d/out" ;;
    token-in-argv)   printf 'curl\0-H\0Authorization: Bearer %s\0' "$tok" > "$d/shim/calls/1.argv" ;;
    token-not-stdin) printf 'header = "Authorization: Bearer someone-else"\n' > "$d/shim/calls/1.stdin" ;;
    body-in-output)  printf '::add-mask::%s\nSHIMCALL 1\n%s\n' "$tok" "$BK_BODYCANARY" > "$d/out" ;;
  esac
  CTL_NAME="ctl-bkc-$v"
}
for v in good mask-not-first mask-count mask-after-curl token-in-argv token-not-stdin body-in-output; do
  bkc_mk "$v"; bk_check "$CTL_NAME" "$BK_CANARY"
  want="$v"; [[ "$v" == good ]] && want=""
  ctl_want "bk_check/$v" "$BK_FAIL" "$want"
done
ctl_row "bk_check: a green directory is green, and each of its six clauses (mask first, mask once, mask before curl, token in no argv, token on stdin, body not echoed) fails ALONE when only its fact is doctored (including the argv/stdin pair that used to cover each other)"

# --- bs_refusal (the Better Stack reader's refusal contract) ---
bsr_mk() { # <variant> -> row name; sets BS_RC
  local v="$1" d; d="$(ctl_dir "bsr-$v")"; assert_fixture_dir "$d"
  BS_RC=2
  printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr"
  : > "$d/stdout"
  case "$v" in
    good) ;;
    rc)                   BS_RC=1 ;;
    curl-called)          printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker-line)          printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\n%scontrol_char\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    marker-count)         printf '%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stdout" ;;
    stderr-lines)         printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\nan extra line\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    variable-line)        printf 'betterstack-query.sh: refusing to send a credential (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    other-variable-named) printf 'betterstack-query.sh: refusing BETTERSTACK_QUERY_PASSWORD and BETTERSTACK_QUERY_USERNAME (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    value-in-output)      printf '%s\n' "$BS_CAN" > "$d/stdout" ;;
    injected-url-in-output) printf 'http://evil.example.test/second\n' > "$d/stdout" ;;
    unmodelled-flag)      printf 'x\n' > "$d/shim/unmodelled" ;;
  esac
  CTL_NAME="ctl-bsr-$v"
}
for v in good rc curl-called marker-line marker-count stderr-lines variable-line other-variable-named value-in-output injected-url-in-output unmodelled-flag; do
  bsr_mk "$v"; bs_refusal "$CTL_NAME" token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
  case "$v" in good) want="" ;; rc) want=" rc=1" ;; stderr-lines) want=" stderr-lines=3" ;; *) want=" $v" ;; esac
  ctl_want "bs_refusal/$v" "$BS_BAD" "$want"
done
ctl_row "bs_refusal: a compliant refusal is green, and each of its clauses (exit 2, zero calls, marker line, marker count, two stderr lines, one variable line, the other variable unnamed, value absent, injected URL absent, no unmodelled flag) fails ALONE when only its fact is doctored"

# --- bs_ok_call (the well-formed Better Stack call) ---
bso_mk() { # <variant> -> row name; sets BS_RC
  local v="$1" d; d="$(ctl_dir "bso-$v")"; assert_fixture_dir "$d"
  BS_RC=0
  printf 'curl\0--disable\0--noproxy\0*\0--config\0-\0-d\0%s\0https://%s?query=1\0' "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv"
  printf 'user = "%s"\n' "$BS_PAIR" > "$d/shim/calls/1.stdin"
  printf '%s' "$BS_PAIR" > "$d/shim/calls/1.userpwd"
  : > "$d/stdout"; : > "$d/stderr"
  case "$v" in
    good) ;;
    rc)                BS_RC=1 ;;
    calls)             printf 'curl\0' > "$d/shim/calls/2.argv" ;;
    user-flag)         printf 'flag\n' > "$d/shim/calls/1.userflag" ;;
    injected)          printf 'INJECTED\n' > "$d/shim/calls/1.injected" ;;
    user-token)        printf 'curl\0-u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-bundle) printf 'curl\0-sSu\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-digit)  printf 'curl\0-4u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-hash)   printf 'curl\0-#u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-long)   printf 'curl\0--user\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-eq)     printf 'curl\0--user=svc:x\0-d\0%s\0https://%s?query=1\0' "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    value-in-argv)     printf 'curl\0-d\0%s\0https://%s?query=1\0%s\0' "$BS_SQL" "$BS_HOST" "arg-$BS_PASS" > "$d/shim/calls/1.argv" ;;
    value-in-argv-user) printf 'curl\0-d\0%s\0https://%s?query=1\0%s\0' "$BS_SQL" "$BS_HOST" "arg-$BS_USER" > "$d/shim/calls/1.argv" ;;
    stdin-shape)       printf 'user = "%s"\n# a second directive\n' "$BS_PAIR" > "$d/shim/calls/1.stdin" ;;
    userpwd)           printf 'someone:else' > "$d/shim/calls/1.userpwd" ;;
    sql)               printf 'curl\0-d\0SELECT 2\0https://%s?query=1\0' "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    url)               printf 'curl\0-d\0%s\0https://elsewhere.example.test/\0' "$BS_SQL" > "$d/shim/calls/1.argv" ;;
    value-in-output)   printf '%s\n' "$BS_PASS" > "$d/stdout" ;;
    marker-on-success) printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\n' > "$d/stderr" ;;
    unmodelled-flag)   printf 'x\n' > "$d/shim/unmodelled" ;;
  esac
  CTL_NAME="ctl-bso-$v"
}
for v in good rc calls user-flag injected user-token user-token-bundle user-token-digit user-token-hash user-token-long user-token-eq value-in-argv value-in-argv-user stdin-shape userpwd sql url value-in-output marker-on-success unmodelled-flag; do
  bso_mk "$v"; bs_ok_call "$CTL_NAME"
  case "$v" in
    good) want="" ;; rc) want=" rc=1" ;; calls) want=" calls=2" ;; user-flag) want=" user-flag-in-argv" ;; user-token*) want=" user-token-in-argv" ;; value-in-argv*) want=" value-in-argv" ;;
    stdin-shape) want=" stdin-is-not-exactly-one-user-line" ;; userpwd) want=" userpwd-differs" ;; sql) want=" sql-not-an-argument" ;;
    *) want=" $v" ;;
  esac
  ctl_want "bs_ok_call/$v" "$BS_BAD" "$want"
done
ctl_row "bs_ok_call: a well-formed call is green, and each of its clauses fails ALONE when only its fact is doctored: exit 0, one call, no user flag, no INJECTED, each spelling of the user token (-u, a -sSu bundle, a -4u bundle with a digit, a -#u bundle with the hash, --user, --user=...) and each of the two values (username, password) in argv, exactly one stdin user line, USERPWD equal, SQL an argument, pinned URL, value absent from the output, no marker, no unmodelled flag (the user-line-count clause is unreachable: the exact-stdin clause fails first)"

# --- hmx_refused (every hostile-credential refusal of the parity rows) ---
hmr_mk() { # <variant> -> row name; sets RUN_RC
  local v="$1" d; d="$(ctl_dir "hmr-$v")"; assert_fixture_dir "$d"
  RUN_RC=2
  printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\n' > "$d/stderr"
  : > "$d/stdout"
  case "$v" in
    good) ;;
    rc)              RUN_RC=1 ;;
    curl-called)     printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker-line)     printf 'SOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=control_char\n' > "$d/stderr" ;;
    marker-count)    printf 'SOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\n' > "$d/stdout" ;;
    value-in-output) printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nid was %s\n' "$HMX_CFID" > "$d/stderr" ;;
    value-in-output-mark)  printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nrejected SYNTHMARK0001x\n' > "$d/stderr" ;;
    value-in-output-key)   printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nkey was %s\n' "$HMX_KEY" > "$d/stderr" ;;
    value-in-output-cfsec) printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nsecret was %s\n' "$HMX_CFSEC" > "$d/stderr" ;;
    value-in-output-stdout) printf 'rejected SYNTHMARK0001x\n' > "$d/stdout" ;;
    stub-called)     printf 'gh\n' > "$d/shim/unexpected" ;;
    stub-unmodelled) printf 'x\n' > "$d/shim/unmodelled" ;;
    bash-error)      printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nctl.sh: line 3: boom: command not found\n' > "$d/stderr" ;;
  esac
  CTL_ROW="$d"
}
for v in good rc curl-called marker-line marker-count value-in-output value-in-output-mark value-in-output-key value-in-output-cfsec value-in-output-stdout stub-called stub-unmodelled bash-error; do
  hmr_mk "$v"; hmx_refused "$CTL_ROW" 2 ctl-surface
  case "$v" in good) want="" ;; rc) want=" rc=1" ;; value-in-output*) want=" value-in-output" ;; stub-*) want=" stub-called" ;; *) want=" $v" ;; esac
  ctl_want "hmx_refused/$v" "$HMX_BAD" "$want"
done
ctl_row "hmx_refused: a compliant refusal is green, and each of its clauses fails ALONE when only its fact is doctored: the rc, zero calls, the marker line, one marker, nothing echoed (EACH alternative of the echo test alone: the SYNTHMARK0001 hostile-token marker, the webhook key, the Cloudflare Access id, the Cloudflare Access secret, and the same marker on stdout rather than stderr), no stub (an unexpected tool and an unmodelled flag each), no bash error"

# --- evaluate_hmac (the full-contract judge of the parity script's live status arm) ---
EHM_DIG="$(printf '%064d' 7)"
ehm_stdin() { printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$1" "$2" "$3"; }
ehm_mk() { # <variant> -> row dir
  local v="$1" d; d="$(ctl_dir "ehm-$v")"; assert_fixture_dir "$d"
  printf 'curl\0--config\0-\0' > "$d/shim/calls/1.argv"
  printf 'deploy.soleur.ai' > "$d/shim/calls/1.host"
  ehm_stdin "$EHM_DIG" "$HMX_CFID" "$HMX_CFSEC" > "$d/shim/calls/1.stdin"
  printf 'present\n' > "$d/shim/tools/python3-1.hmackey"
  printf 'python3\0-I\0-c\0program\0' > "$d/shim/tools/python3-1.argv"
  : > "$d/stdout"; : > "$d/stderr"
  case "$v" in
    good|calls-below-min|host) ;;
    stdin-digest)  ehm_stdin "nothex" "$HMX_CFID" "$HMX_CFSEC" > "$d/shim/calls/1.stdin" ;;
    stdin-id)      ehm_stdin "$EHM_DIG" "other-id" "$HMX_CFSEC" > "$d/shim/calls/1.stdin" ;;
    stdin-secret)  ehm_stdin "$EHM_DIG" "$HMX_CFID" "other-secret" > "$d/shim/calls/1.stdin" ;;
    stdin-short)   ehm_stdin "$EHM_DIG" "$HMX_CFID" "$HMX_CFSEC" | head -n 2 > "$d/shim/calls/1.stdin" ;;
    argv-key)      printf 'curl\0%s\0' "$HMX_KEY" > "$d/shim/calls/1.argv" ;;
    argv-id)       printf 'curl\0%s\0' "$HMX_CFID" > "$d/shim/calls/1.argv" ;;
    argv-secret)   printf 'curl\0%s\0' "$HMX_CFSEC" > "$d/shim/calls/1.argv" ;;
    argv-digest)   printf 'curl\0%s\0' "$EHM_DIG" > "$d/shim/calls/1.argv" ;;
    injected)      printf 'INJECTED: line 2\n' > "$d/shim/calls/1.injected" ;;
    tool-key)      printf 'python3\0%s\0' "$HMX_KEY" > "$d/shim/tools/python3-1.argv" ;;
    tool-id)       printf 'python3\0%s\0' "$HMX_CFID" > "$d/shim/tools/python3-1.argv" ;;
    tool-secret)   printf 'python3\0%s\0' "$HMX_CFSEC" > "$d/shim/tools/python3-1.argv" ;;
    tool-hmac)     printf 'openssl\0dgst\0-hmac\0k\0' > "$d/shim/tools/openssl-1.argv" ;;
    tool-macopt)   printf 'openssl\0mac\0-macopt\0hexkey:00\0' > "$d/shim/tools/openssl-1.argv" ;;
    key-not-in-env) rm -f "$d/shim/tools/python3-1.hmackey" ;;
    unexpected-tool) printf 'gh\n' > "$d/shim/unexpected" ;;
    unmodelled-flag) printf 'x\n' > "$d/shim/unmodelled" ;;
    out-key)       printf '%s\n' "$HMX_KEY" > "$d/stdout" ;;
    out-id)        printf '%s\n' "$HMX_CFID" > "$d/stderr" ;;
    out-secret)    printf '%s\n' "$HMX_CFSEC" > "$d/stdout" ;;
    bash-error)    printf 'ctl.sh: line 3: boom: command not found\n' > "$d/stderr" ;;
  esac
  CTL_ROW="$d"
}
for v in good stdin-digest stdin-id stdin-secret stdin-short argv-key argv-id argv-secret argv-digest injected tool-key tool-id tool-secret tool-hmac tool-macopt \
         key-not-in-env calls-below-min host unexpected-tool unmodelled-flag out-key out-id out-secret bash-error; do
  ehm_mk "$v"; min=1; [[ "$v" == calls-below-min ]] && min=2; [[ "$v" == host ]] && min=0
  [[ "$v" == host ]] && printf 'elsewhere.example.test' > "$CTL_ROW/shim/calls/1.host"
  evaluate_hmac "$CTL_ROW" 'deploy\.soleur\.ai' "$min"
  case "$v" in
    good) want="" ;; stdin-*) want="headers-not-on-stdin" ;; argv-*) want="secret-in-argv" ;; tool-*) want="secret-in-tool-argv" ;;
    host) want="unexpected-host" ;; out-*) want="secret-in-output" ;; *) want="$v" ;;
  esac
  ctl_want "evaluate_hmac/$v" "$EV_FAILED" "$want"
done
ctl_row "evaluate_hmac: a compliant row is green, and each of its clauses fails ALONE when only its fact is doctored: three stdin header lines (the digest, the id, the secret and a missing line each), no secret in a curl argv (key, id, secret, digest each) or tool argv (key, id, secret each, and an openssl -hmac operand and an openssl -macopt operand each), HMAC_KEY in python3's environment, the minimum calls, no unexpected host or tool, no INJECTED line, no unmodelled flag, no secret in the output (key, id, secret each), no bash error"

# --- evaluate_body (the JSON-body probes: the body reaches curl on stdin and the password is in no curl or jq argv) ---
# Its `no-calls` clause was the one verdict clause of the family with no control: with zero recorded calls the per-call clauses never run, so a
# row that made no request at all read as GREEN the moment that clause went.
evb_mk() { # <variant> -> row dir
  local v="$1" d; d="$(ctl_dir "evb-$v")"; assert_fixture_dir "$d"; mkdir -p "$d/shim/jq"
  printf 'curl\0--data-binary\0@-\0https://x.example.test/\0' > "$d/shim/calls/1.argv"
  jq -n --arg i "$BODY_ID" --arg p "$BODY_PW" '{identifier:$i,password:$p}' > "$d/shim/calls/1.body"
  printf 'jq\0-n\0{identifier:$ENV.SYNTH_ID_E}\0' > "$d/shim/jq/1.argv"
  case "$v" in
    good) ;;
    no-calls)           rm -f "$d/shim/calls/1.argv" "$d/shim/calls/1.body" ;;
    pw-in-argv)         printf 'curl\0-d\0%s\0' "$BODY_PW" > "$d/shim/calls/1.argv" ;;
    pw-in-jq-argv)      printf 'jq\0--arg\0pw\0%s\0' "$BODY_PW" > "$d/shim/jq/1.argv" ;;
    body-not-recorded)  : > "$d/shim/calls/1.body" ;;
    body-content)       jq -n --arg i "$BODY_ID" '{identifier:$i,password:"someone-else"}' > "$d/shim/calls/1.body" ;;
  esac
  CTL_ROW="$d"
}
for v in good no-calls pw-in-argv pw-in-jq-argv body-not-recorded body-content; do
  evb_mk "$v"; evaluate_body "$CTL_ROW"
  case "$v" in good) want="" ;; body-not-recorded) want="body-not-recorded body-content" ;; *) want="$v" ;; esac
  ctl_want "evaluate_body/$v" "$EV_FAILED" "$want"
done
ctl_row "evaluate_body: a compliant row is green, and each of its clauses (at least one call, password in no curl argv, password in no jq argv, a recorded body, the exact identifier and password in it) fails when only its fact is doctored (an unrecorded body also fails the content clause, which it cannot satisfy)"

