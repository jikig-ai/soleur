# shellcheck shell=bash
# The never-read list and the walker. Every file the skill reads flows through lc_safe_path.
# The first six case arms are a superset of code-to-prd's is_excluded() (pinned by safe-walk-parity.test.sh);
# the rest are launch-check's own classes: state/vars files, SQL and CSV data, sqlite files, fixture data.

LC_EXCLUDED_COUNT=0
LC_SYMLINK_COUNT=0

# master.key is listed for parity with code-to-prd's is_excluded(); *.key already covers it.
#
# The list is matched case-insensitively (a case-insensitive macOS volume treats `.ENV` and `.env` as one file) and
# also covers every credential-bearing name SEC-02 reports (lc_credential_paths below), so a file the scan calls a
# credential is never offered to the AI-assisted review.
lc_safe_path() {
  local old=0 rc=0
  shopt -q nocasematch && old=1
  shopt -s nocasematch
  lc__safe_path_case "$1" || rc=$?
  [ "$old" = 1 ] || shopt -u nocasematch
  return "$rc"
}

# lc_credential_paths: stdin paths -> those whose NAME marks a credential-bearing file (SEC-02). One definition,
# shared by the count and by `scan --show-secrets`.
lc_credential_paths() {
  awk '{ p = tolower($0); b = p; sub(".*/", "", b)
    if (b ~ /\.(example|sample|template|dist|pub)$/) next
    if (b ~ /^\.env($|\.)/ || b ~ /\.env$/ || b == ".envrc" || b ~ /\.(key|p12|pfx|jks|keystore|ppk|tfvars)$/ || b ~ /\.tfstate(\.|$)/ || (b ~ /\.pem$/ && b ~ /(key|priv|secret)/) || b ~ /^(credentials|secrets)(\.|$)/ || b ~ /^id_(rsa|dsa|ecdsa|ed25519)/ || b ~ /^\.(npmrc|netrc|pypirc|htpasswd|git-credentials)$/ || b == ".dev.vars" || b == "kubeconfig" || p ~ /(^|\/)\.(aws|kube)\// || b ~ /service-account.*\.json$/) print $0 }'
}

# shellcheck disable=SC2221,SC2222
lc__safe_path_case() {
  case "$1" in
    .env|.env.*|*/.env|*/.env.*) return 1 ;;
    secrets.*|*/secrets.*) return 1 ;;
    *.pem|*.key) return 1 ;;
    credentials.*|*/credentials.*) return 1 ;;
    master.key|*/master.key) return 1 ;;
    .git/*|*/.git/*) return 1 ;;
    *.tfstate|*.tfstate.*|*.tfvars|*.tfvars.json) return 1 ;;
    *.sql|*.dump|*.csv|*.sqlite|*.sqlite3|*.db) return 1 ;;
    fixtures/*|*/fixtures/*|__fixtures__/*|*/__fixtures__/*|seeds/*|*/seeds/*) return 1 ;;
    *.env|.envrc|*/.envrc|*.p12|*.pfx|*.jks|*.keystore|*.ppk) return 1 ;;
    credentials|*/credentials|secrets|*/secrets|secrets/*|*/secrets/*) return 1 ;;
    id_rsa*|*/id_rsa*|id_dsa*|*/id_dsa*|id_ecdsa*|*/id_ecdsa*|id_ed25519*|*/id_ed25519*) return 1 ;;
    .npmrc|*/.npmrc|.netrc|*/.netrc|.pypirc|*/.pypirc|.htpasswd|*/.htpasswd|.git-credentials|*/.git-credentials) return 1 ;;
    .dev.vars|*/.dev.vars|kubeconfig|*/kubeconfig|.kube/*|*/.kube/*|.aws/*|*/.aws/*|*service-account*.json) return 1 ;;
  esac
  return 0
}

# lc_walk <target> <outfile>: write the readable, tracked-or-untracked-not-ignored paths, one per line.
# Counters are set in this shell (call directly, never inside $( )).
lc_walk() {
  local target=$1 out=$2 p
  : > "$out"
  LC_EXCLUDED_COUNT=0; LC_SYMLINK_COUNT=0
  while IFS= read -r -d '' p; do
    case "$p" in *$'\n'*) LC_EXCLUDED_COUNT=$((LC_EXCLUDED_COUNT + 1)); continue ;; esac
    if ! lc_safe_path "$p"; then LC_EXCLUDED_COUNT=$((LC_EXCLUDED_COUNT + 1)); continue; fi
    if [ -L "$target/$p" ]; then LC_SYMLINK_COUNT=$((LC_SYMLINK_COUNT + 1)); LC_EXCLUDED_COUNT=$((LC_EXCLUDED_COUNT + 1)); continue; fi
    [ -f "$target/$p" ] || continue
    printf '%s\n' "$p" >> "$out"
  done < <(git -C "$target" ls-files -z -c -o --exclude-standard)
}

# lc_stack <filelist>: node | python | ruby | go | other
lc_stack() {
  if grep -qE '(^|/)package\.json$' "$1"; then echo node
  elif grep -qE '(^|/)(pyproject\.toml|requirements\.txt|setup\.py|Pipfile)$' "$1"; then echo python
  elif grep -qE '(^|/)Gemfile$' "$1"; then echo ruby
  elif grep -qE '(^|/)go\.mod$' "$1"; then echo go
  else echo other; fi
}
