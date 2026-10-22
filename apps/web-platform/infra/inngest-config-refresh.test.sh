#!/usr/bin/env bash
#
# Guard suite for #6780 (ADR-135, 2026-10-13 amendment): the host-side consumer of the
# pull-based signed config-refresh channel — the baked inngest-config-refresh.sh, its
# systemd service+timer, the baked infra-config-install + cosign-trusted-root.json
# payloads, the applied.version floor seed, and the runcmd arming.
#
# THE INPUT IS THE TERRAFORM RENDER — the bytes that reach the host. inngest-userdata-budget.sh
# renders cloud-init-inngest.yml through terraform's own templatefile + the payload comment
# strip, so a missed `$${`/`%%{` escape or an over-cap payload reds HERE at Phase 0, not on the
# host. (Convention lifted from cloud-init-inngest-provision-unit.test.sh.)
#
# LAYERS.
#   S-rows (static): read the rendered doc — file placement/modes/ownership, unit keys,
#       the --only-secrets bound, HARD-1 engine exclusion, refresh-set <-> DEST_SPEC lockstep,
#       the Vector Source-4 tag, the cosign verify-blob argument shape, byte-parity of the two
#       file()-embedded payloads, runcmd arming position.
#   F-rows (fixture): run the EXTRACTED refresh script under `bash` against stub seams
#       (--fixture-seams argv gate + REFRESH_* env overrides): empty-pointer noop,
#       same-digest noop, happy-path pull->verify->apply->APPLIED, signature failure,
#       rollback/replay reject, manifest sha mismatch, missing/corrupt applied.version ->
#       FLOOR, mid-set install failure leaves the version un-advanced, seam refusal, and the
#       xtrace-with-credential refuse.
#
# Every F row FAILS on an unexpected exit code — rc 127 (a missing stub) is an instrument
# fault, not a pass.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET="$DIR/inngest-userdata-budget.sh"

passes=0; fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }
ok()   { if [ "$1" -eq 0 ]; then pass; else fail "$2"; fi }

for t in bash python3 terraform sha256sum; do
  command -v "$t" >/dev/null 2>&1 || { echo "FATAL: $t required" >&2; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PRISTINE="$WORK/pristine.yml"
bash "$BUDGET" "$PRISTINE" >/dev/null 2>&1 || { echo "FATAL: render/budget gate failed" >&2; exit 1; }
[ -s "$PRISTINE" ] || { echo "FATAL: no stripped render" >&2; exit 1; }
[ "$(head -1 "$PRISTINE")" = "#cloud-config" ] || { echo "FATAL: render does not start with #cloud-config" >&2; exit 1; }

# Extract the consumer payloads from the rendered doc (the bytes that reach the host).
python3 - "$PRISTINE" "$WORK" <<'PYEOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
out = sys.argv[2]
want = {
    "/usr/local/bin/inngest-config-refresh.sh": "refresh.sh",
    "/usr/local/bin/infra-config-install": "install.sh",
    "/etc/soleur/cosign-trusted-root.json": "trusted-root.json",
    "/var/lib/inngest-config/applied.version": "applied.version",
    "/etc/systemd/system/inngest-config-refresh.service": "refresh.service",
    "/etc/systemd/system/inngest-config-refresh.timer": "refresh.timer",
}
wf = {w["path"]: w for w in doc.get("write_files", [])}
for path, name in want.items():
    w = wf.get(path)
    if w is None:
        open(f"{out}/{name}.MISSING", "w").write("")
        continue
    open(f"{out}/{name}", "w").write(str(w.get("content", "")))
    open(f"{out}/{name}.meta", "w").write(f"{w.get('permissions','')} {w.get('owner','')}")
# runcmd items, verbatim (arming-order pin reads it)
open(f"{out}/runcmd.txt", "w").write("\n---ITEM---\n".join(str(i) for i in doc.get("runcmd", [])))
PYEOF

for f in refresh.sh install.sh trusted-root.json applied.version refresh.service refresh.timer; do
  [ -f "$WORK/$f" ] || { echo "FATAL: $f not extracted (missing write_files entry)" >&2; exit 1; }
done
chmod +x "$WORK/refresh.sh" "$WORK/install.sh"

SVC="$(cat "$WORK/refresh.service")"; TMR="$(cat "$WORK/refresh.timer")"; SC="$(cat "$WORK/refresh.sh")"

# ── S-rows: static pins against the render ─────────────────────────────────────────────────

# S1: the script lands once, executable, root-owned, bash.
grep -q '^0755 root:root$' "$WORK/refresh.sh.meta" && pass || fail "S1: refresh.sh not 0755 root:root"
grep -qx '#!/usr/bin/env bash' < <(head -1 "$WORK/refresh.sh") && pass || fail "S1: refresh.sh shebang"
bash -n "$WORK/refresh.sh" && pass || fail "S1: refresh.sh bash -n"
bash -n "$WORK/install.sh" && pass || fail "S1: install.sh bash -n"

# S2: service shape — oneshot, bounded, hardened, tagged, with the --only-secrets bound.
for pin in 'Type=oneshot' 'TimeoutStartSec=' 'SyslogIdentifier=inngest-config-refresh' \
           'StateDirectory=inngest-config' 'ConditionPathExists=/etc/default/inngest-server' \
           'EnvironmentFile=/etc/default/inngest-server'; do
  grep -qF "$pin" <<<"$SVC" && pass || fail "S2: service missing $pin"
done
grep -q 'ExecStart=.*doppler run .*--only-secrets INNGEST_CONFIG_DIGEST' <<<"$SVC" \
  && pass || fail "S2: ExecStart lacks --only-secrets INNGEST_CONFIG_DIGEST"
grep -q 'ExecStart=.*--only-secrets INNGEST_CONFIG_DIGEST.*-- .*inngest-config-refresh\.sh' <<<"$SVC" \
  && pass || fail "S2: bound must sit before the -- separator"
grep -qF -- '--no-exit-on-missing-only-secrets' <<<"$SVC" \
  && pass || fail "S2: missing --no-exit-on-missing-only-secrets (count-gated pointer must not hard-fail)"
# The bound admits exactly the ONE pointer — no second secret sneaks in.
only_n="$(printf '%s' "$SVC" | grep -oE -- '--only-secrets[ =][A-Z_]+' | wc -l)"
[ "$only_n" -eq 1 ] && pass || fail "S2: --only-secrets count=$only_n (want 1)"

# S2b: under ProtectSystem=strict the unit must ReadWritePaths every writable
# surface the script touches — /usr/local/bin is the infra-config-install mktemp
# dest (EROFS forever otherwise; webhook.service precedent), and /root/.docker
# must be dash-prefixed (a non-existent entry fails mount-namespace setup).
grep -qE 'ReadWritePaths=.*[[:space:]]/usr/local/bin([[:space:]]|$)' <<<"$SVC" \
  && pass || fail "S2b: ReadWritePaths missing /usr/local/bin (install dest is EROFS under ProtectSystem=strict)"
grep -qE 'ReadWritePaths=.*-/root/\.docker([[:space:]]|$)' <<<"$SVC" \
  && pass || fail "S2b: /root/.docker must be dash-prefixed in ReadWritePaths"

# S2c: the sandboxing trio is verbatim-pinned (the flip suite pins the same lines —
# stripping ProtectSystem=strict must RED, not silently widen), plus the relational
# bound the flip suite pins: worst-case tick (login 60 + pull + verify defaults,
# extracted from the rendered script) strictly under TimeoutStartSec — a kill
# mid-gate emits no marker.
for pin in 'NoNewPrivileges=yes' 'ProtectSystem=strict' 'PrivateTmp=true'; do
  grep -qF "$pin" <<<"$SVC" && pass || fail "S2c: service missing sandbox pin $pin"
done
grep -qF 'PrivateTmp=yes' <<<"$SVC" && fail "S2c: PrivateTmp=yes mis-spelling (want PrivateTmp=true)" || pass
_ts="$(printf '%s' "$SVC" | grep -oE 'TimeoutStartSec=[0-9]+' | cut -d= -f2)"
_pto="$(printf '%s' "$SC" | grep -oE 'REFRESH_PULL_TIMEOUT_S:-[0-9]+' | grep -oE '[0-9]+$' | head -1)"
_vto="$(printf '%s' "$SC" | grep -oE 'REFRESH_VERIFY_TIMEOUT_S:-[0-9]+' | grep -oE '[0-9]+$' | head -1)"
[ "$((60 + 2 * ${_pto:-0} + ${_vto:-0}))" -lt "${_ts:-0}" ] \
  && pass || fail "S2c: worst-case tick (60+2*${_pto:-?}+${_vto:-?}) not under TimeoutStartSec=${_ts:-?}"

# S3: timer shape — 60 s cadence, enabled on timers.target, persistent.
for pin in 'OnBootSec=' 'OnUnitActiveSec=60s' 'Persistent=true' 'WantedBy=timers.target'; do
  grep -qF "$pin" <<<"$TMR" && pass || fail "S3: timer missing $pin"
done

# S4: payload byte-parity — baked installer == strip(repo file); trusted root == repo file.
par_i="$(python3 - "$WORK" "$DIR" <<'PYEOF'
import re, sys
work, infra = sys.argv[1], sys.argv[2]
strip = re.compile(r"^[ \t]*#([ \t][^\n]*)?\n", re.M)
a = open(f"{work}/install.sh").read()
b = strip.sub("", open(f"{infra}/infra-config-install.sh").read())
print("ok" if a == b else "BAD")
PYEOF
)"
[ "$par_i" = "ok" ] && pass || fail "S4: baked infra-config-install != strip(repo file)"
par_r="$(python3 - "$WORK" "$DIR" <<'PYEOF'
import sys
work, infra = sys.argv[1], sys.argv[2]
a = open(f"{work}/trusted-root.json").read()
b = open(f"{infra}/cosign-trusted-root.json").read()
print("ok" if a == b else "BAD")
PYEOF
)"
[ "$par_r" = "ok" ] && pass || fail "S4: baked cosign-trusted-root.json != repo file"

# S5: floor seed is 0, mode/owner right.
[ "$(cat "$WORK/applied.version")" = "0" ] && pass || fail "S5: applied.version seed != 0"
grep -q '^0644 root:root$' "$WORK/applied.version.meta" && pass || fail "S5: applied.version not 0644 root:root"

# S6: runcmd arms the timer AFTER /etc/default/inngest-server exists.
arm_line="$(grep -c 'systemctl enable --now inngest-config-refresh.timer' "$WORK/runcmd.txt")"
[ "$arm_line" -eq 1 ] && pass || fail "S6: arming item count=$arm_line (want 1)"
pos_arm="$(grep -n 'enable --now inngest-config-refresh.timer' "$WORK/runcmd.txt" | head -1 | cut -d: -f1)"
pos_env="$(grep -n '> /etc/default/inngest-server' "$WORK/runcmd.txt" | head -1 | cut -d: -f1)"
{ [ -n "$pos_arm" ] && [ -n "$pos_env" ] && [ "$pos_arm" -gt "$pos_env" ]; } \
  && pass || fail "S6: timer armed before /etc/default/inngest-server write (arm=$pos_arm env=$pos_env)"

# S7: HARD-1 + AC18 — refresh-set = the five dedicated carriers, all in DEST_SPEC, no engine.
SET_FILE="$DIR/inngest-config-refresh-set.txt"
members="$(grep -vE '^\s*(#|$)' "$SET_FILE" | sort)"
want_members="$(printf '%s\n' \
  apps/web-platform/infra/cat-inngest-cutover-state.sh \
  apps/web-platform/infra/inngest-cutover-flip.sh \
  apps/web-platform/infra/inngest-luks-cutover.sh \
  apps/web-platform/infra/inngest-redis-bootstrap.sh \
  apps/web-platform/infra/inngest-server-flip-guard.sh | sort)"
[ "$members" = "$want_members" ] && pass || fail "S7: refresh-set != the five dedicated carriers"
missing=0
while IFS= read -r m; do
  base="/usr/local/bin/$(basename "$m")"
  grep -qF "[\"$base\"]" "$DIR/infra-config-install.sh" || { missing=1; echo "  refresh-set member $base not in DEST_SPEC" >&2; }
done <<< "$members"
while IFS= read -r m; do
  base="$(basename "$m")"
  grep -qF "|/usr/local/bin/$base|" "$DIR/infra-config-apply.sh" || { missing=1; echo "  refresh-set member $base not in FILE_MAP" >&2; }
done <<< "$members"
[ "$missing" -eq 0 ] && pass || fail "S7: refresh-set member(s) absent from DEST_SPEC or FILE_MAP (AC18 lockstep)"
# engine exclusion (HARD-1): no engine path may appear in the set, DEST_SPEC, or FILE_MAP.
engine_ok=1
for eng in inngest-config-refresh infra-config-install cosign-trusted-root applied.version \
           inngest-config-refresh.service inngest-config-refresh.timer; do
  grep -q "$eng" "$SET_FILE" 2>/dev/null && { grep -qE '^\s*[^#].*'"$eng" "$SET_FILE" && engine_ok=0; }
  grep -qF "\"/usr/local/bin/$eng" "$DIR/infra-config-install.sh" && engine_ok=0
  grep -qF "|/usr/local/bin/$eng|" "$DIR/infra-config-apply.sh" && engine_ok=0
done
[ "$engine_ok" -eq 1 ] && pass || fail "S7: engine path present in refresh-set, DEST_SPEC, or FILE_MAP (HARD-1)"

# S8: the journald tag is shipped — vector.toml Source 4 allowlist contains it.
# Scoped to the [sources.host_scripts_journald] include block — a file-wide grep
# would pass on a moved/commented entry (the journald-config.test.sh lesson).
hsj="$(awk '/^\[sources\.host_scripts_journald\]/{f=1} f{print} f&&/^include_matches\.SYSLOG_IDENTIFIER/{l=1} l&&/\]/{exit}' "$DIR/vector.toml")"
grep -qF '"inngest-config-refresh"' <<<"$hsj" \
  && pass || fail "S8: inngest-config-refresh absent from vector.toml host_scripts_journald SYSLOG_IDENTIFIER allowlist"

# S8b — D2 (#6780): the phone-home detail sanitizer must let a LABELED `sha256=<64hex>`
# digest survive while still redacting unlabeled secrets — else the drift comparator can
# never see the applied digest. Replay the baked sed chain against a probe line: the
# labeled digest survives, a Doppler token shape is scrubbed, a BARE 64-hex run (not
# labeled, i.e. possibly a token) is still scrubbed.
python3 - "$PRISTINE" "$WORK" <<'PYEOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
wf = {w["path"]: w for w in doc.get("write_files", [])}
ph = wf.get("/usr/local/bin/inngest-boot-phone-home.sh")
open(f"{sys.argv[2]}/phone-home.sh", "w").write(str(ph.get("content", "")) if ph else "")
PYEOF
SED_LINE="$(grep -oE 'sed -E .*REDACTED.*' "$WORK/phone-home.sh" | head -1)"
[ -n "$SED_LINE" ] || { fail "S8b: could not locate the phone-home detail sanitizer line"; }
# The sanitizer's three-part shape: uppercase-fold the labeled digest FIRST, run the generic
# 32+ hex scrub, lowercase-restore LAST. Order is the mechanism — pin it.
grep -q 'sha256=\[0-9a-f\]{64}#\\U&' <<<"$SED_LINE" \
  && pass || fail "S8b: sanitizer lost the sha256= fold-up leg"
grep -q 'SHA256=\[0-9A-F\]{64}#\\L&' <<<"$SED_LINE" \
  && pass || fail "S8b: sanitizer lost the SHA256 restore leg"
if [ -n "$SED_LINE" ]; then
  # the sed program is single-quoted in the source (it can contain no single quote):
  # take the span between the first and last ' on the line.
  SED_EXPR="$(printf '%s' "$SED_LINE" | sed -E "s/^sed -E '(.*)' .*\$/\\1/")"
  probe_out="$(printf 'applied sha256=%s tok=dp.st.AA11BB22CC33DD44EE55 bare=%s\n' \
    "aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111" \
    "bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222" \
    | sed -E "$SED_EXPR")"
  grep -q 'sha256=aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111' <<<"$probe_out" \
    && pass || fail "S8b: labeled sha256= digest did NOT survive the sanitizer (D2 broken): $probe_out"
  ! grep -q 'dp.st.AA11BB22CC33DD44EE55' <<<"$probe_out" \
    && pass || fail "S8b: Doppler token survived the sanitizer"
  ! grep -q 'bbbb2222bbbb2222bbbb2222bbbb2222' <<<"$probe_out" \
    && pass || fail "S8b: bare 64-hex run survived the sanitizer (must still be scrubbed)"
fi

# S9: the verify-blob call shape — offline, trusted root, single sigstore bundle (cosign
# 3.x dropped the 2.x detached sig/cert flags entirely; #10390), keyless identity + OIDC
# issuer, pinned cosign image.
for pin in 'verify-blob' '--trusted-root' '--bundle /bundle/manifest.txt.sigstore.json' \
           '--certificate-identity-regexp' '--certificate-oidc-issuer' \
           'token.actions.githubusercontent.com' '--network none'; do
  grep -qF -- "$pin" <<<"$SC" && pass || fail "S9: verify call missing $pin"
done
# Negative pin: no dropped-2.x flag spelling may survive — on the producer side v3.1.1
# removed sign-blob's --output-* flags entirely (the #10390 flag-parse failure), while
# verify-blob's detached --signature/--certificate spellings are merely deprecated and
# would silently diverge from the --bundle contract rather than die. `--certificate `
# (with the space) does not false-positive on
# --certificate-identity-regexp / --certificate-oidc-issuer.
! grep -qF -- '--signature' <<<"$SC" \
  && ! grep -qE -- '--certificate[[:space:]]' <<<"$SC" \
  && pass || fail "S9: verify call still carries a dropped cosign-2.x flag"
grep -q 'cosign@sha256:57c0e93a' <<<"$SC" \
  && pass || fail "S9: cosign image not the pinned v3.1.1 digest"
# Defect-2 pins (#10390): the prod default is the ZOT ref — resolved AFTER ZOT_EP (an early
# resolution would yield a leading-slash ref), staged by an explicit pull before `docker run`.
grep -qF 'jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' <<<"$SC" \
  && pass || fail "S9: COSIGN_IMAGE default not the zot ref"
grep -qF 'COSIGN_IMAGE:-${ZOT_EP}/jikig-ai/cosign' <<<"$SC" \
  && pass || fail "S9: COSIGN_IMAGE default not resolved from ZOT_EP"
grep -qF 'pull "$COSIGN_IMAGE"' <<<"$SC" \
  && pass || fail "S9: no explicit cosign-image stage pull"
grep -qF 'member=cosign-image' <<<"$SC" \
  && pass || fail "S9: cosign pull miss not distinguished (member=cosign-image)"
grep -q 'IDENTITY_REGEXP.*build-inngest-config-bundle' <<<"$SC" \
  && pass || fail "S9: identity regexp does not name the bundle workflow"
# Install goes through the allowlisted root helper, never a direct cp/install.
grep -q 'INSTALL_CMD.*infra-config-install' <<<"$SC" \
  && pass || fail "S9: install path not infra-config-install"

# S10 (defect 3): the verify stderr is no longer swallowed — a bounded capture file exists
# and a classified detail= token rides the VERIFY_FAIL row. Anchored on syntax, not prose:
# the negative pin asserts the verify run does NOT end `>/dev/null 2>&1` under any
# spelling, and the capture pin asserts the redirect target, not the filename alone
# (a comment or the later head/mv lines can satisfy a bare 'verify.stderr' grep).
grep -qF '2>"$STAGE/verify.stderr"' <<<"$SC" \
  && pass || fail "S10: no verify.stderr stderr redirect on the verify run"
! grep -qF -- '/bundle/manifest.txt >/dev/null 2>&1' <<<"$SC" \
  && ! grep -qF -- '/bundle/manifest.txt 2>&1 >/dev/null' <<<"$SC" \
  && ! grep -qF -- '/bundle/manifest.txt &>/dev/null' <<<"$SC" \
  && ! grep -qF -- '/bundle/manifest.txt > /dev/null 2>&1' <<<"$SC" \
  && pass || fail "S10: verify-blob stderr still swallowed by /dev/null"
grep -qF 'detail=' <<<"$SC" \
  && pass || fail "S10: no detail= classification on the VERIFY_FAIL row"
# The classifier's token vocabulary is a fixed allowlist — every named arm present.
# Pinned on the assignment shape `_cls=<tok>`: a bare-token grep is vacuous (it
# matches prose and flag names), this one fails if the arm is deleted.
for tok in flag-newbundle tlog identity chain timeout docker other; do
  grep -qF "_cls=$tok" <<<"$SC" \
    && pass || fail "S10: classifier arm missing token $tok"
done
# Ordering pin (panel finding): the identity arm MUST precede the chain arm — cosign's
# canonical identity-mismatch stderr contains 'certificate', so a chain-first order
# misclassifies it. Anchored on the arm bodies' relative position in the render.
_id_ln="$(grep -nF 'elif grep -qiE '"'"'identity|issuer' <<<"$SC" | head -1 | cut -d: -f1)"
_ch_ln="$(grep -nF "elif grep -qiE 'certificate chain|x509|signed by'" <<<"$SC" | head -1 | cut -d: -f1)"
{ [ -n "$_id_ln" ] && [ -n "$_ch_ln" ] && [ "$_id_ln" -lt "$_ch_ln" ]; } \
  && pass || fail "S10: identity arm must precede chain arm (bare 'certificate' shadows identity)"
# The emit-channel charset bound is enforced, not just documented: a future arm that
# yields a non-[a-z-] token must degrade to `other`, never inject into the row.
grep -qF '*[!a-z-]*) _cls=other' <<<"$SC" \
  && pass || fail "S10: _cls charset clamp missing (token bound is comment-only)"
# detail= must be additive after rejver= on the reason=signature call (row-shape pin),
# and it must be the ONLY signature call site — a second one without detail= is
# CI-invisible (the grep above finds the pinned one) and surfaces only as probe FAIL.
grep -qE 'verify_fail signature "" "detail=' <<<"$SC" \
  && pass || fail "S10: verify_fail signature call site does not pass detail="
[ "$(grep -cE 'verify_fail signature' <<<"$SC")" -eq 1 ] \
  && pass || fail "S10: a second verify_fail signature call site would evade the detail= pin"
# No call site may interpolate stderr text into verify_fail's free-text $3 — the
# phone-home sed chain has no general-secret arm, so raw stderr in $3 ships unredacted.
! grep -qE 'verify_fail [a-z-]+ "" "[^"]*\$\(' <<<"$SC" \
  && pass || fail "S10: verify_fail call interpolates a command substitution into \$3"
# A VERIFY_FAIL row must never carry version=/sha256= — the drift comparator filters
# them out today, but a widened state-row grep would parse a failure as applied state.
! grep -qE 'verify_fail [a-z-]+ "" "[^"]*(version|sha256)=' <<<"$SC" \
  && pass || fail "S10: verify_fail \$3 carries a comparator-parseable key"
# AC5 pin: the drift summarizer's _summ_row allowlist must carry `detail` or the
# token is emitted but never surfaces in run summaries (a regex revert goes red).
# Membership-based (member AND detail inside one (…|…)= alternation), not the
# 'member|detail' adjacency substring — reordering the alternation stays green,
# dropping either key goes red. Anchored at $DIR like every sibling file access.
DRIFT_WF="$DIR/../../../.github/workflows/inngest-config-drift.yml"
[ -f "$DRIFT_WF" ] && pass || fail "S10: inngest-config-drift.yml not found at $DRIFT_WF"
grep -oE '\([a-zA-Z0-9_|]*member[a-zA-Z0-9_|]*\)=' "$DRIFT_WF" | grep -q 'detail' \
  && pass || fail "S10: _summ_row regex in inngest-config-drift.yml lost the detail alternation"

# ── F-rows: run the extracted script under fixture seams ─────────────────────────────────

FX="$WORK/fx"; mkdir -p "$FX/bin" "$FX/state" "$FX/dest"

cat > "$FX/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$FX_LOG"
case "$1" in
  login) cat >/dev/null; exit 0 ;;
  pull)  [ "${FX_FAIL_PULL:-0}" = "1" ] && exit 1
         [ "${FX_FAIL_COSIGN_PULL:-0}" = "1" ] && case "$2" in *cosign*) exit 1 ;; esac
         exit 0 ;;
  create) echo "fixture-cid"; exit 0 ;;
  cp)    cp "$FX_BUNDLE_TGZ" "$3" 2>/dev/null || exit 1 ;;
  rm)    exit 0 ;;
  run)   if [ "${FX_COSIGN_FAIL:-0}" = "1" ]; then
           [ -n "${FX_COSIGN_STDERR:-}" ] && printf '%s\n' "$FX_COSIGN_STDERR" >&2
           exit "${FX_COSIGN_RC:-1}"
         fi
         exit 0 ;;
  *)     exit 0 ;;
esac
EOF

cat > "$FX/bin/logger" <<'EOF'
#!/usr/bin/env bash
# args: -t <tag> <msg...>
t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="$2"; shift 2;; *) break;; esac; done
echo "$*" >> "$FX_MARKERS"
exit 0
EOF

cat > "$FX/bin/phone-home" <<'EOF'
#!/usr/bin/env bash
# args: <stage> <detail>
echo "PHONE_HOME $2" >> "$FX_MARKERS"
exit 0
EOF

cat > "$FX/bin/infra-config-install" <<'EOF'
#!/usr/bin/env bash
# args: <dest> <mode> <owner>, payload on stdin. FX_INSTALL_FAIL_AFTER=N fails the (N+1)th call.
dest="$1"
case "$dest" in /usr/local/bin/*.sh) ;; *) echo "rejected $dest" >> "$FX_LOG"; exit 3;; esac
n=$(cat "$FX_NSEEN" 2>/dev/null || echo 0)
if [ "$n" -ge "${FX_INSTALL_FAIL_AFTER:-999}" ]; then echo "install FAIL $dest" >> "$FX_LOG"; exit 9; fi
echo "install $dest" >> "$FX_LOG"
cat > "$FX_DEST/$(basename "$dest")"
n=$((n + 1)); echo "$n" > "$FX_NSEEN"
exit 0
EOF

chmod +x "$FX/bin/"*

cat > "$FX/zot.env" <<'EOF'
ZOT_REGISTRY_ENDPOINT=zot.internal:5000
ZOT_PULL_USER=puller
ZOT_PULL_TOKEN=fixture-token
EOF
printf '{"tuf":true}\n' > "$FX/trusted-root.json"

# build a fixture bundle tarball: manifest.txt + manifest.txt.sigstore.json (the cosign 3.x
# --bundle output the producer now ships; a fixture stub — the docker mock never parses it)
# + member files (real sha256s)
mk_bundle() {  # $1=version $2=dir-with-members -> writes $FX/bundle.tar.gz
  local v="$1" mdir="$2" bd="$FX/bundle-$1"
  rm -rf "$bd"; mkdir -p "$bd"
  cp "$mdir"/*.sh "$bd/"
  {
    echo "VERSION=$v"
    ( cd "$bd" && for f in *.sh; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"; done )
  } > "$bd/manifest.txt"
  printf '{"fixture":"sigstore-bundle"}\n' > "$bd/manifest.txt.sigstore.json"
  tar -C "$bd" -czf "$FX/bundle.tar.gz" .
}
mkdir -p "$FX/members"
echo '#!/bin/sh' > "$FX/members/inngest-redis-bootstrap.sh"
echo 'echo redis-bootstrap' >> "$FX/members/inngest-redis-bootstrap.sh"
echo '#!/bin/sh' > "$FX/members/inngest-cutover-flip.sh"
echo 'echo flip' >> "$FX/members/inngest-cutover-flip.sh"
echo '#!/bin/sh' > "$FX/members/cat-inngest-cutover-state.sh"
echo 'echo state' >> "$FX/members/cat-inngest-cutover-state.sh"

run_refresh() {  # env: INNGEST_CONFIG_DIGEST + FX_* fault knobs
  env -i HOME="$FX/home" PATH="$FX/bin:/usr/bin:/bin" \
    REFRESH_DOCKER_BIN="$FX/bin/docker" \
    REFRESH_INSTALL_CMD="$FX/bin/infra-config-install" \
    REFRESH_LOGGER_CMD="$FX/bin/logger" \
    REFRESH_PHONE_HOME_CMD="$FX/bin/phone-home" \
    REFRESH_STATE_DIR="$FX/state" \
    REFRESH_ZOT_ENV_FILE="$FX/zot.env" \
    REFRESH_TRUSTED_ROOT="$FX/trusted-root.json" \
    REFRESH_COSIGN_IMAGE="${FX_COSIGN_SEAM_IMAGE-fixture/cosign}" \
    REFRESH_BUNDLE_REPO="fixture/repo" \
    REFRESH_IDENTITY_REGEXP="^fixture$" \
    FX_LOG="$FX/calls.log" FX_MARKERS="$FX/markers.log" \
    FX_BUNDLE_TGZ="$FX/bundle.tar.gz" FX_DEST="$FX/dest" FX_NSEEN="$FX/nseen" \
    FX_FAIL_PULL="${FX_FAIL_PULL:-0}" FX_COSIGN_FAIL="${FX_COSIGN_FAIL:-0}" \
    FX_COSIGN_STDERR="${FX_COSIGN_STDERR:-}" FX_COSIGN_RC="${FX_COSIGN_RC:-}" \
    FX_FAIL_COSIGN_PULL="${FX_FAIL_COSIGN_PULL:-0}" \
    REFRESH_NOOP_THROTTLE_S="${FX_NOOP_THROTTLE_S:-0}" \
    FX_INSTALL_FAIL_AFTER="${FX_INSTALL_FAIL_AFTER:-999}" \
    INNGEST_CONFIG_DIGEST="${INNGEST_CONFIG_DIGEST:-}" \
    ZOT_PULL_TOKEN="${ZOT_PULL_TOKEN:-}" \
    bash "$WORK/refresh.sh" --fixture-seams
}

reset_fx() { rm -f "$FX/calls.log" "$FX/markers.log" "$FX/nseen"; rm -rf "$FX/state"; mkdir -p "$FX/state"; rm -rf "$FX/dest"; mkdir -p "$FX/dest"; }
docker_calls() { local _n; _n="$(grep -c '^docker ' "$FX/calls.log" 2>/dev/null || true)"; printf '%s' "${_n:-0}"; }

PTR="1111111111111111111111111111111111111111111111111111111111111111"
PTR2="2222222222222222222222222222222222222222222222222222222222222222"

# F1 — empty pointer: throttled NOOP, exit 0, ZERO docker calls.
reset_fx
INNGEST_CONFIG_DIGEST="" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F1: empty-pointer rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_NOOP reason=empty-pointer' "$FX/markers.log" && pass || fail "F1: no empty-pointer NOOP row"
[ "$(docker_calls)" -eq 0 ] && pass || fail "F1: docker called on empty pointer ($(docker_calls) calls)"

# F2 — pointer == applied digest: NOOP same-digest, exit 0, ZERO docker calls.
reset_fx
echo 3 > "$FX/state/applied.version"
printf '{"applied_version":3,"bundle_sha256":"%s"}\n' "$PTR" > "$FX/state/applied.json"
INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F2: same-digest rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_NOOP reason=same-digest' "$FX/markers.log" && pass || fail "F2: no same-digest NOOP row"
[ "$(docker_calls)" -eq 0 ] && pass || fail "F2: docker called on same-digest noop"

# F3 — happy path: pull -> extract -> verify-blob -> sha256check -> install -> APPLIED.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 4 "$FX/members"
INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F3: happy path rc=$rc"
grep -q "SOLEUR_INFRA_PULL_APPLIED version=4 sha256=$PTR verify=ok" "$FX/markers.log" \
  && pass || fail "F3: no APPLIED row"
[ "$(cat "$FX/state/applied.version" 2>/dev/null)" = "4" ] && pass || fail "F3: applied.version not advanced"
grep -q '"bundle_sha256":"'"$PTR"'"' "$FX/state/applied.json" 2>/dev/null && pass || fail "F3: applied.json missing bundle sha"
[ -f "$FX/dest/inngest-redis-bootstrap.sh" ] && [ -f "$FX/dest/inngest-cutover-flip.sh" ] && [ -f "$FX/dest/cat-inngest-cutover-state.sh" ] \
  && pass || fail "F3: members not installed"

# F4 — verify-blob failure: VERIFY_FAIL reason=signature, nothing installed, version kept.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 5 "$FX/members"
FX_COSIGN_FAIL=1 INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F4: signature-fail rc=$rc (want 1)"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature' "$FX/markers.log" \
  && pass || fail "F4: no VERIFY_FAIL reason=signature row"
[ "$(cat "$FX/state/applied.version")" = "0" ] && pass || fail "F4: version advanced on verify fail"
[ "$(ls "$FX/dest" | wc -l)" -eq 0 ] && pass || fail "F4: files installed despite signature failure"

# F5 — rollback/replay: manifest VERSION <= applied.version → reject, nothing installed.
reset_fx
echo 9 > "$FX/state/applied.version"
printf '{"applied_version":9,"bundle_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' > "$FX/state/applied.json"
mk_bundle 3 "$FX/members"   # VERSION=3 < applied 9
INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F5: rollback rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=rollback-or-replay' "$FX/markers.log" \
  && pass || fail "F5: no rollback-or-replay row"
[ "$(ls "$FX/dest" | wc -l)" -eq 0 ] && pass || fail "F5: files installed on rollback"

# F6 — manifest sha mismatch: corrupt a member after packing -> reason=sha, nothing installed.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 6 "$FX/members"
# rebuild the tarball with a corrupted member (sha in manifest now stale)
echo 'corrupted' >> "$FX/bundle-6/inngest-cutover-flip.sh"
tar -C "$FX/bundle-6" -czf "$FX/bundle.tar.gz" .
INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F6: sha-mismatch rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=sha' "$FX/markers.log" \
  && pass || fail "F6: no VERIFY_FAIL reason=sha row"
[ "$(ls "$FX/dest" | wc -l)" -eq 0 ] && pass || fail "F6: files installed despite sha mismatch"

# F7 — missing/corrupt applied.version → FLOOR row; run still converges.
reset_fx   # no applied.version at all
mk_bundle 7 "$FX/members"
INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F7: missing-version rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_FLOOR version=floor' "$FX/markers.log" \
  && pass || fail "F7: no FLOOR row for missing applied.version"
grep -q 'sha256=0000000000000000000000000000000000000000000000000000000000000000' "$FX/markers.log" \
  && pass || fail "F7: FLOOR row lacks the zeros sentinel"
reset_fx
echo 'garbage-not-a-number' > "$FX/state/applied.version"
mk_bundle 8 "$FX/members"
INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
grep -q 'SOLEUR_INFRA_PULL_FLOOR version=floor' "$FX/markers.log" \
  && pass || fail "F7: no FLOOR row for corrupt applied.version"
[ "$(cat "$FX/state/applied.version")" = "8" ] && pass || fail "F7: version did not advance from floor"

# F8 — MID-SET install failure (member #2 of 3 refuses): version must NOT advance, and the
# ledger must record the failure so the next tick re-drives the whole pull->verify->apply.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 9 "$FX/members"
FX_INSTALL_FAIL_AFTER=1 INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F8: install-fail rc=$rc"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=install' "$FX/markers.log" \
  && pass || fail "F8: no VERIFY_FAIL reason=install row"
[ "$(cat "$FX/state/applied.version")" = "0" ] && pass || fail "F8: version advanced despite install failure"
grep -q '"verify_result":"verify-fail:install"' "$FX/state/applied.json" \
  && pass || fail "F8: applied.json did not record the failure"
# and the torn set is visible: exactly one member landed before the failure.
[ "$(ls "$FX/dest" | wc -l)" -eq 1 ] && pass || fail "F8: expected exactly one landed member, got $(ls "$FX/dest" | wc -l)"

# F9 — seam refusal: REFRESH_* env without --fixture-seams must be ignored. The logger stub
# sits on PATH so the refusal row (emitted through the DIRECT `logger` call inside the gate,
# not a seam var) is observable; REFRESH_DOCKER_BIN must be unset so the fixture docker stub
# records zero calls even though it is also on PATH.
reset_fx
env -i HOME="$FX/home" PATH="$FX/bin:/usr/bin:/bin" \
  REFRESH_DOCKER_BIN="$FX/bin/docker" REFRESH_STATE_DIR="$FX/state" REFRESH_LOGGER_CMD="$FX/bin/logger" \
  REFRESH_PHONE_HOME_CMD="$FX/bin/phone-home" \
  FX_LOG="$FX/calls.log" FX_MARKERS="$FX/markers.log" \
  INNGEST_CONFIG_DIGEST="" bash "$WORK/refresh.sh"; rc=$?
[ $rc -eq 0 ] && pass || fail "F9: no-seam run rc=$rc"
[ ! -f "$FX/calls.log" ] && pass || fail "F9: REFRESH_DOCKER_BIN honoured without --fixture-seams"
grep -q 'SOLEUR_INFRA_PULL_SEAM_REFUSED' "$FX/markers.log" \
  && pass || fail "F9: no SEAM_REFUSED row"

# F10 — xtrace refuse with a live credential: bash -x + ZOT_PULL_TOKEN -> exit 78.
reset_fx
env -i HOME="$FX/home" PATH="/usr/bin:/bin" ZOT_PULL_TOKEN=live-token bash -x "$WORK/refresh.sh" >/dev/null 2>&1; rc=$?
[ $rc -eq 78 ] && pass || fail "F10: xtrace+credential rc=$rc (want 78)"

# F11 — a hostile pointer must not poison the ledger: a quote-bearing digest is
# charset-gated to "invalid" in attempted_sha256 (never a smuggled second
# bundle_sha256 key), and a follow-up run with the SMUGGLED digest must NOT hit
# the same-digest noop — it must proceed to the pull path (docker calls > 0).
reset_fx
echo 0 > "$FX/state/applied.version"
INNGEST_CONFIG_DIGEST='x","bundle_sha256":"'"$PTR"'"' run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F11: hostile pointer rc=$rc (want 1)"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=pointer-malformed' "$FX/markers.log" \
  && pass || fail "F11: no pointer-malformed row"
grep -q '"attempted_sha256":"invalid"' "$FX/state/applied.json" \
  && pass || fail "F11: hostile pointer not charset-gated in applied.json"
mk_bundle 10 "$FX/members"
INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ "$(docker_calls)" -gt 0 ] \
  && pass || fail "F11: smuggled digest hit the same-digest noop — ledger was poisoned"

# F12 — torn-ledger repair: applied.version advanced + applied.json pinning the
# PRIOR digest (same VERSION, different digest) is the torn-ledger signature —
# the run must self-heal (install + rewrite both files + REPAIRED row), not wedge
# on rollback-or-replay.
reset_fx
echo 9 > "$FX/state/applied.version"
printf '{"applied_version":9,"bundle_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' > "$FX/state/applied.json"
mk_bundle 9 "$FX/members"
INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F12: repair rc=$rc (want 0)"
grep -q 'SOLEUR_INFRA_PULL_REPAIRED version=9' "$FX/markers.log" \
  && pass || fail "F12: no REPAIRED row"
grep -q '"bundle_sha256":"'"$PTR2"'"' "$FX/state/applied.json" \
  && pass || fail "F12: ledger not re-pinned to the promoted digest"
[ -f "$FX/dest/inngest-redis-bootstrap.sh" ] && pass || fail "F12: members not installed on repair"

# F13 — pull failure: VERIFY_FAIL reason=pull, nothing installed, version kept.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 11 "$FX/members"
FX_FAIL_PULL=1 INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F13: pull-fail rc=$rc (want 1)"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=pull' "$FX/markers.log" \
  && pass || fail "F13: no VERIFY_FAIL reason=pull row"
[ "$(cat "$FX/state/applied.version")" = "0" ] && pass || fail "F13: version advanced on pull failure"
[ "$(ls "$FX/dest" | wc -l)" -eq 0 ] && pass || fail "F13: files installed despite pull failure"

# F14 — no-seam cosign repoint: with --fixture-seams but REFRESH_COSIGN_IMAGE set EMPTY
# (`:-`-equivalent to absent for the code under test; the prod seam gate unsets it anyway), the zot
# default must resolve after ZOT_EP and BOTH the stage pull and the verify run must carry
# the zot.internal:5000/jikig-ai/cosign@sha256:… ref, pull before run (#10390 defect 2).
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 12 "$FX/members"
FX_COSIGN_SEAM_IMAGE="" INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 0 ] && pass || fail "F14: no-seam cosign run rc=$rc (want 0)"
CPULL_LN=$(grep -n '^docker pull .*jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' "$FX/calls.log" | head -1 | cut -d: -f1)
CRUN_LN=$(grep -n '^docker run .*jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' "$FX/calls.log" | head -1 | cut -d: -f1)
[ -n "$CPULL_LN" ] && pass || fail "F14: no zot-ref cosign stage pull in calls.log"
[ -n "$CRUN_LN" ] && pass || fail "F14: no zot-ref cosign verify run in calls.log"
{ [ -n "$CPULL_LN" ] && [ -n "$CRUN_LN" ] && [ "$CPULL_LN" -lt "$CRUN_LN" ]; } \
  && pass || fail "F14: cosign pull does not precede the verify run"
grep -q 'zot.internal:5000/jikig-ai/cosign@sha256:57c0e93a' "$FX/calls.log" \
  && pass || fail "F14: cosign ref not resolved through the zot endpoint"

# F15 — cosign stage-pull failure: VERIFY_FAIL reason=pull member=cosign-image (never
# reason=signature — the pre-fix misattribution), nothing installed, version kept.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 13 "$FX/members"
FX_FAIL_COSIGN_PULL=1 INNGEST_CONFIG_DIGEST="$PTR" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F15: cosign-pull-fail rc=$rc (want 1)"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=pull' "$FX/markers.log" \
  && pass || fail "F15: no VERIFY_FAIL reason=pull row"
grep -q 'member=cosign-image' "$FX/markers.log" \
  && pass || fail "F15: pull failure not attributed to the cosign image"
! grep -q 'reason=signature' "$FX/markers.log" \
  && pass || fail "F15: fetch failure misattributed to signature"
[ "$(cat "$FX/state/applied.version")" = "0" ] && pass || fail "F15: version advanced on cosign pull failure"
[ "$(ls "$FX/dest" | wc -l)" -eq 0 ] && pass || fail "F15: files installed despite cosign pull failure"

# F16 — verify stderr classification (defect 3): a stubbed cosign stderr string must land
# as the classified detail= token on the VERIFY_FAIL row AND write the bounded
# $STATE_DIR/verify.stderr file. Fixtures cover ALL classifier arms including the
# identity/chain ordering (cosign's identity-mismatch stderr contains 'certificate'
# — a chain-first order misclassifies it). mk_bundle runs ONCE up front: the tarball
# persists across reset_fx, and every arm's verify fails before VERSION is read.
reset_fx
echo 0 > "$FX/state/applied.version"
mk_bundle 14 "$FX/members"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='Error: --trusted-root only supported with --new-bundle-format' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: flag-newbundle rc=$rc (want 1)"
grep -q 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature' "$FX/markers.log" \
  && pass || fail "F16: no VERIFY_FAIL reason=signature row"
grep -q 'detail=flag-newbundle' "$FX/markers.log" \
  && pass || fail "F16: new-bundle gate error not classified detail=flag-newbundle"
[ -f "$FX/state/verify.stderr" ] && pass || fail "F16: no bounded verify.stderr file written"
# The persisted file = one `# ts=` binding header + ≤4 KiB of stderr.
head -1 "$FX/state/verify.stderr" | grep -qE '^# ts=[0-9T:Z-]+ offered=[0-9a-f]{12} rc=1$' \
  && pass || fail "F16: verify.stderr missing the ts/offered/rc binding header"
_vc="$(wc -c < "$FX/state/verify.stderr" 2>/dev/null || echo 9999)"
[ "$_vc" -le 4200 ] && pass || fail "F16: verify.stderr not bounded (${_vc} bytes)"
[ "$(stat -c %a "$FX/state/verify.stderr")" = "600" ] \
  && pass || fail "F16: verify.stderr mode != 0600 (umask subshell missing)"
[ ! -e "$FX/state/verify.stderr.new" ] && pass || fail "F16: verify.stderr.new left behind (mv not atomic)"

reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='error verifying tlog entry: rekor lookup failed' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: tlog rc=$rc (want 1)"
grep -q 'detail=tlog' "$FX/markers.log" \
  && pass || fail "F16: tlog stderr not classified detail=tlog"

reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='Error response from daemon: no such image' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: docker rc=$rc (want 1)"
grep -q 'detail=docker' "$FX/markers.log" \
  && pass || fail "F16: daemon stderr not classified detail=docker"

# identity BEFORE chain: cosign's canonical identity-mismatch text carries the word
# 'certificate' — under the pre-fix order it classified `chain`, misrouting triage.
reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 \
  FX_COSIGN_STDERR='Error: none of the expected identities matched what was in the certificate, got subjects [https://x] with issuer https://y' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: identity rc=$rc (want 1)"
grep -q 'detail=identity' "$FX/markers.log" \
  && pass || fail "F16: identity-mismatch stderr classified wrong (chain shadows identity)"
! grep -q 'detail=chain' "$FX/markers.log" \
  && pass || fail "F16: identity-mismatch misclassified detail=chain"

# Overlapping-token fixture — discriminates ORDER, not just presence: 'issuer'
# reaches the identity arm AND 'x509' reaches the chain arm, so this stderr
# classifies identity only under the new order (chain-first would misroute).
reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='x509: certificate issuer mismatch' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: overlap rc=$rc (want 1)"
grep -q 'detail=identity' "$FX/markers.log" \
  && pass || fail "F16: issuer-bearing x509 stderr should classify detail=identity under new order"

reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='x509: certificate signed by unknown authority' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: chain rc=$rc (want 1)"
grep -q 'detail=chain' "$FX/markers.log" \
  && pass || fail "F16: x509 chain stderr not classified detail=chain"

# Empty stderr (verify fails without cosign diagnostics) still reaches `other`.
reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: empty-stderr rc=$rc (want 1)"
grep -q 'detail=other' "$FX/markers.log" \
  && pass || fail "F16: empty stderr did not classify detail=other"

reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='some unclassified failure text' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: other rc=$rc (want 1)"
grep -q 'detail=other' "$FX/markers.log" \
  && pass || fail "F16: unrecognized stderr did not fall through to detail=other"

# The 4 KiB bound must actually bind: a >4 KiB stderr lands header + exactly 4096
# bytes — the `head -c 4096`→`cat` mutation (or a removed cap) goes red here.
reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_STDERR="$(head -c 5000 /dev/zero | tr '\0' 'x')" \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: oversize-stderr rc=$rc (want 1)"
_vc="$(wc -c < "$FX/state/verify.stderr" 2>/dev/null || echo 9999)"
{ [ "$_vc" -gt 4096 ] && [ "$_vc" -le 4200 ]; } \
  && pass || fail "F16: verify.stderr cap did not bind (${_vc} bytes from 5001 input)"

# rc=124 (timeout kill) classifies timeout regardless of stderr content.
reset_fx
echo 0 > "$FX/state/applied.version"
FX_COSIGN_FAIL=1 FX_COSIGN_RC=124 FX_COSIGN_STDERR='partial output before kill' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: timeout rc=$rc (want 1)"
grep -q 'detail=timeout' "$FX/markers.log" \
  && pass || fail "F16: rc=124 not classified detail=timeout"

# VF_STAMP keys reason:detail — a detail flip inside the 3600 s throttle window
# re-emits a second row; reason-only keying (the reverted form) suppresses it.
reset_fx
echo 0 > "$FX/state/applied.version"
FX_NOOP_THROTTLE_S=3600 FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='some unclassified failure text' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: stamp arm1 rc=$rc (want 1)"
FX_NOOP_THROTTLE_S=3600 FX_COSIGN_FAIL=1 FX_COSIGN_STDERR='error verifying tlog entry: rekor lookup failed' \
  INNGEST_CONFIG_DIGEST="$PTR2" run_refresh; rc=$?
[ $rc -eq 1 ] && pass || fail "F16: stamp arm2 rc=$rc (want 1)"
# (line-anchored: the phone-home stub echoes the marker text with a PHONE_HOME prefix —
#  an unanchored count would read 2 lines per emit and 4 total.)
[ "$(grep -c '^SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature' "$FX/markers.log")" -eq 2 ] \
  && pass || fail "F16: detail flip did not re-emit inside the throttle window"
grep -q 'detail=other' "$FX/markers.log" && grep -q 'detail=tlog' "$FX/markers.log" \
  && pass || fail "F16: stamp rows missing expected detail= tokens"

# Anti-vacuity floor — the inngest.test.sh convention: a deleted block must red,
# not silently pass fewer assertions. Raise it when adding rows.
MIN_ASSERTIONS=162
[ "$passes" -ge "$MIN_ASSERTIONS" ] \
  || { echo "FLOOR: ${passes} assertions < floor $MIN_ASSERTIONS — a block stopped running"; fails=$((fails+1)); }

echo "inngest-config-refresh.test.sh: ${passes} passed, ${fails} failed"
[ "$fails" -eq 0 ] || exit 1
