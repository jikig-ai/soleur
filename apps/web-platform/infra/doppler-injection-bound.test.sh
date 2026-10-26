#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted mutation bodies are LITERAL shell/unit text written
# into fixture copies by design ($D / ${!KEY} / $VAR must NOT expand here — they are the source
# strings the scanner reads). Mirrors credential-persist-home-guard.test.sh.
#
# Guard 2 (#7761) — every `doppler run` unit BOUNDS its injected secret set.
#
# WHY THIS FILE EXISTS
# ====================
# `doppler run -- <cmd>` injects the WHOLE config into the child's environment. When the child is
# a shell script that takes an environment value in COMMAND POSITION (executes it, or sources a
# path named by it), every unenumerated secret name is a live argv/exec seam: a Doppler secret
# whose name collides with one of the script's seam variables silently redirects what the unit
# executes. That is the class #7761 is about, and `--only-secrets` is the runtime half of the fix
# (the in-script argv gate is Guard 1).
#
# PROPERTY. Every unit in this repo whose ExecStart / ExecStartPre / ExecStartPost passes through
# `doppler run`, AND whose target script uses an environment value in command position (executed
# or sourced) — or which resolves its own secret by INDIRECT expansion (${!NAME_KEY}) — either
# enumerates its secrets with `--only-secrets` (as a `doppler run` FLAG, i.e. before the `--`), or
# appears in ACK_REASONS below with a written reason. ACK_REASONS' cardinality is pinned so the
# escape hatch cannot grow silently.
#
# FOUR SCOPING DECISIONS the naive property gets wrong, each verified against this repo:
#
#   1. ExecStartPre COUNTS. The #6178 arm-atomicity flip-guard ships as
#      `ExecStartPre=/usr/bin/doppler run …`, assigned into FLIP_GUARD_LINE at
#      inngest-bootstrap.sh:1089 and substituted into the inngest-server heredoc at :990. A scan
#      anchored on `^ExecStart=` misses the one instance the plan documented as vulnerable — so
#      the directive regex covers Exec{Start,StartPre,StartPost} AND a fifth extraction surface
#      exists for directives INJECTED by shell assignment rather than written in a heredoc.
#
#   2. THE LITERAL `doppler run` IS NOT THE POPULATION. Five units resolve the binary first:
#        D="$(command -v doppler || true)"; … exec "$D" run --project soleur --config prd -- …
#      (cron-egress-firewall.service, cron-egress-resolve.service, cron-egress-alarm@.service,
#      container-restart-monitor.service, and the web-host vector unit in
#      soleur-host-bootstrap.sh), plus `${DOPPLER_BIN} run` for the heartbeat unit. A grep for the
#      literal misses roughly a third of the population, and a floor row would still pass on the
#      remainder. doppler_run_offset() therefore matches the resolved-variable spelling too.
#
#   3. `runcmd` INVOCATIONS ARE EXCLUDED — structurally, not by predicate. Only `.service` files,
#      `cat > … <<EOF` heredocs and cloud-init `content: |` blocks are enumerated, and a runcmd
#      entry is none of those. The boot isolation self-check at cloud-init-inngest.yml:604-611
#      must see ALL names to do its job; demanding a bound there would self-defeat the
#      provision-time control this guard is the runtime half of. Pinned by a must-PASS row.
#
#   4. AN EXEMPTION CLASS IS REQUIRED, NOT OPTIONAL. Four probe units resolve their own secret by
#      indirect expansion over a per-host key name Terraform bakes in and the tracked unit never
#      contains — `${!WEB_ZOT_CONSUMER_URL_KEY}` — where the key expands to e.g. WEB_ZOT_CONSUMER_URL_WEB_1
#      (the `*_URL_KEY=%s` printf of each server.tf install provisioner builds it; the git-data and inngest
#      keys are identity mappings today — see ACK_REASONS for the measured correction). Three of the four do
#      it in their SCRIPT now and one still does it in the unit's own ExecStart (item 5). A literal
#      `--only-secrets` list in a TRACKED unit cannot name a per-host secret — the unit contains a
#      VARIABLE name, never the secret's name, so there is nothing to enumerate. That alone is the
#      limit, and it is sufficient. An earlier revision also argued "the flag is fail-closed on a
#      listed-but-absent name, so the same unit on a second web host would break"; that is refuted
#      by this very PR, which ships --no-exit-on-missing-only-secrets on the flip unit and thereby
#      makes the flag fail-OPEN. Do not restore it: a future author would route around the stated
#      rationale using the exact flag this repo already uses. It is a real limit of the invariant,
#      not a false positive to predicate away, so it is an ACK with a reason.
#
#   5. THE UNIT WRAPPER MUST NOT EXPAND THE SECRET (#9639). Three of those four probe units used to
#      resolve the key in the unit's own ExecStart (`export URL="${!KEY}"`), which runs before the
#      script's xtrace refusal and so prints the secret on a traced launch. They now run the
#      script directly and the SCRIPT resolves the key after its refusal. Two consequences here:
#      (a) the unit-side `${!` stopped being the reason they are in the population, so a script-side
#      `${!<NAME>_KEY}` is a population reason too (bound to the `_KEY` convention, row G1.9);
#      (b) a wrapper stage fails any doppler-run unit whose Exec directive still expands a secret,
#      unless it is in WRAPPER_ACK_REASONS (the surviving unfixed sibling), whose pin can only ratchet down.
#
# THE LISTS ARE AUTHORED AND COMMENTED, NEVER DERIVED. Two independent exhaustive derivations over
# the same two sibling scripts produced DIFFERENT answers in both directions, and both misses are
# silent under `--no-exit-on-missing-only-secrets`:
#   * cron-egress-resolve.sh:149-157 reads three names by INDIRECT EXPANSION OVER A LITERAL LOOP
#     LIST (`for var in SENTRY_INGEST_DOMAIN NEXT_PUBLIC_SUPABASE_URL SUPABASE_URL; do
#     val="${!var:-}"`). No `$NEXT_PUBLIC_SUPABASE_URL` expansion exists anywhere in that file, so
#     any grep-shaped derivation drops them — and omitting them does not fail loud: :154-155 only
#     warns and forces the tick additive-only with pruning suspended.
#   * git-data-emit's redactor is VALUE-based (cloud-init-git-data.yml:142-150) because the LUKS
#     passphrase is high-entropy and matches no pattern. Under a narrow list `_devalue` degrades
#     to `cat` and repack stderr rides into the emit's detail argument.
# So this guard checks an AUTHORED list against a LOWER BOUND of names the script provably reads.
# It does not, and cannot, reproduce the list. See read_set_lower_bound().
#
# Self-contained: pure bash + python3. No network, root, docker, terraform or cloud-init needed.
# COPIED, NOT SOURCED: infra suites are inlined by policy (ADR-177 §A3) because
# run-registered-suites.sh:422-434 sandboxes a suite with a SINGLE-FILE copy.
set -euo pipefail

# /tmp on the dev host is a 4 GiB tmpfs shared by up to 6 parallel slots of
# run-registered-suites.sh; a DIRECT invocation inherits the bare /tmp. /var/tmp is disk-backed.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="${DOPPLER_BOUND_INFRA_ROOT:-$SCRIPT_DIR}"

# GLOBIGNORE (used by copy_scan_tree) is a COLON-SEPARATED pattern list; a ':' or a glob
# metacharacter in the root silently disables the .terraform exclusion and the 162 MB provider
# cache rides into every sandbox with the run still green. Refuse rather than degrade.
case "$REAL_ROOT" in
  *[][*?:\\]*)
    echo "FATAL: DOPPLER_BOUND_INFRA_ROOT contains ':' or a glob metacharacter: $REAL_ROOT" >&2
    exit 2 ;;
esac

PASS=0
FAIL=0
# fail() MUST return 0 so `set -e` does not abort the harness at the first failing assertion —
# otherwise the summary never prints and later assertions never run. The sole exit chokepoint is
# the final `[[ "$FAIL" -eq 0 ]] || exit 1`.
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ -n "${2:-}" ]] && echo "        $2"; return 0; }

# INSTRUMENT SELF-TEST (#7761 review, P0). Measured on this suite: with the SUT genuinely broken
# (`sys.exit(main())` -> `main(); sys.exit(0)`) it printed 10 real FAIL: lines and, with fail()
# neutered, reported "20/20 passed, 0 failed" and exit 0 — self-consistently, because the
# denominator is PASS+FAIL. CI reads only the exit code. Neutering pass() IS caught (the floor sums
# PASS); neutering fail() was not, because the floor reported THROUGH fail(). Prove both counters
# move, then reset. Output suppressed so the deliberate FAIL row is not misread as a real one.
pass "instrument self-test" >/dev/null
fail "instrument self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: assertion counters are broken (PASS=%s FAIL=%s, expected 1/1).\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT INT TERM HUP

copy_scan_tree() {
  local rc=0
  ( GLOBIGNORE="$1/.terraform"; cp -r "$1"/* "$2"/; ) || rc=$?
  [[ "$rc" -eq 0 ]] || {
    echo "FATAL: sandbox copy failed (rc=$rc) — refusing to scan a truncated tree: $1 -> $2" >&2
    exit 1
  }
  find "$2" -mindepth 1 -type d -name .terraform -prune -exec rm -rf {} + 2>/dev/null || true
}
# SINGLE SOURCE of the exclusion for the comparison side, so the copy and the mutation-landed
# check cannot drift.
scan_diff() { diff -rq --exclude=.terraform "$1" "$2"; }
fresh_sbx() { rm -rf "$TMPROOT"/sbx.*; mktemp -d "$TMPROOT/sbx.$1.XXXXXX"; }

# FROZEN_ROOT: the comparison side, snapshotted ONCE. This suite runs concurrently with ~90
# sibling suites, several of which legitimately write into this same directory; a file appearing
# or vanishing inside a copy->diff window would produce a RED here caused entirely by a DIFFERENT
# suite (#7376). Every copy and diff below reads FROZEN_ROOT, never the live $REAL_ROOT.
FROZEN_ROOT="$TMPROOT/frozen"
mkdir -p "$FROZEN_ROOT"
copy_scan_tree "$REAL_ROOT" "$FROZEN_ROOT"

# ── the scanner ───────────────────────────────────────────────────────────────────────────────
SCANNER="$TMPROOT/scanner.py"
cat > "$SCANNER" <<'PYEOF'
#!/usr/bin/env python3
# Guard 2 scanner. Stages:
#   (1) enumerate unit definitions on FOUR authoring surfaces + a fifth injected-directive
#       extraction, with a PER-SURFACE non-vacuity floor;
#   (2) select the `doppler run` population (literal AND resolved-binary spellings);
#   (3) resolve each unit's target scripts across three script-authoring surfaces;
#   (4) decide bound-required membership (exec/source seam in the target, or ${!VAR} indirect
#       expansion in the unit itself, or a ${!<NAME>_KEY} expansion in its target script (#9639));
#   (5) check the bound is a `doppler run` FLAG (before the `--`) and names at least one secret;
#   (6) reconcile against ACK_REASONS and pin its cardinality;
#   (7) check each AUTHORED list against a LOWER BOUND of names its script provably reads;
#   (8) inner -c stage (#11103): no Exec directive of a doppler-run unit expands an injected
#       name ($NAME/${NAME}/$${NAME}) inside a `bash -c` body — literal or @@SENTINEL@@-delivered.
# Exit: 0 GREEN | 2 violations | 3 census floor | 4 per-surface enumeration floor | 5 ack
#       inconsistency | 6 read-set lower-bound violation.
import os, re, sys

ROOT = os.path.abspath(sys.argv[1])

# ── floors, all DERIVED FROM A GREEN RUN, never guessed ──────────────────────────────────────
#
# WHAT EACH FLOOR IS FOR. These do not guard correctness — they guard against a VACUOUS GREEN.
# Every bound assertion in this suite quantifies over a set the scanner extracted; if an extractor
# silently breaks (a changed heredoc shape, a lost `.tf` `\n`-unescape, a bad glob), that set goes
# empty and every assertion over it passes trivially. The floors are what turn "found nothing" into
# a failure instead of a pass. That is also why they are per-surface: one aggregate floor stays
# satisfied while a single surface's extractor goes dark.
#
# DERIVATION — re-run the suite and read its own `CENSUS:` lines; each floor sits below the value
# printed next to it. Measured on this tree 2026-09-03 (scanned -> floor):
#
#   service       16 -> 12      sh-heredoc     6 -> 4
#   tf-heredoc     4 -> 3       cloud-init     7 -> 5
#   sh-injected    1 -> 1       doppler units 17 -> 12
#   bound-required population 8 -> 5
#
# The gap is deliberate slack: an ordinary deletion of one or two units must not red the suite,
# while a broken extractor — which drops a whole surface at once — must. `sh-injected` has no
# slack available because the population is 1; it is a floor of 1 precisely so that surface
# disappearing is caught, and it will need raising rather than slack if a second one appears.
#
# The `doppler units` figure previously read 16 here, transcribed from the adjacent `service=16`
# rather than measured; the suite's own CENSUS reports 17. Corrected 2026-09-03. Re-derive from
# CENSUS rather than copying this block.
#
# RAISE these in lockstep when the population grows; NEVER lower one to make a run pass — a red
# floor means an extractor stopped seeing a surface, and lowering it re-arms the vacuous green.
MIN_UNITS_BY_SURFACE = {'service': 12, 'sh-heredoc': 4, 'tf-heredoc': 3, 'cloud-init': 5}
MIN_INJECTED_DIRECTIVES = 1
# These two guard the sets every violation assertion quantifies over — stage 2 (the doppler-run
# population) and stage 4 (the bound-required set). Zeroing either used to leave the suite green:
# the anti-vacuity catcher below only walked the per-surface keys. Both are now covered by it.
MIN_DOPPLER_UNITS = 12
MIN_POPULATION = 5

# ── Guard 1's unset list, CONSUMED not re-derived ────────────────────────────────────────────
# Row R3's "non-seam read-set" is the script's read-set MINUS the names Guard 1's in-script argv
# gate unsets. Re-deriving it here would invert the intent: a naive read-set would demand every
# fixture seam appear in `--only-secrets`, i.e. that the unit INJECT the very names the gate
# exists to strip. These are the 38 names Guard 1's gates unset (15 measured 2026-09-03 +
# CUTOVER_BOOT_ID added by #7777's latch-clear record, which stamps the boot the clear was
# recorded under, + CUTOVER_NOOP_THROTTLE_S added by #7696's noop-heartbeat throttle, +
# CUTOVER_NFT_CMD and CUTOVER_PHONE_HOME_CMD added by #10382's measured nftables re-read on
# the noop emit, + the six LUKS key-probe seams added by #9927, + the thirteen #6780 REFRESH_*
# seams); when a Guard-1 gate's list changes,
# this copy moves with it.
GUARD1_UNSET = {
    'CUTOVER_BOOT_ID', 'CUTOVER_CURL_CMD', 'CUTOVER_DONE_OWNER_MARKER', 'CUTOVER_FLAG_SET_CMD',
    'CUTOVER_FLIP_FLAG', 'CUTOVER_GQL_URL', 'CUTOVER_HEALTH_URL', 'CUTOVER_LOGGER_CMD',
    'CUTOVER_NFT_CMD', 'CUTOVER_NOOP_THROTTLE_S', 'CUTOVER_PHONE_HOME_CMD',
    'CUTOVER_REDIS_CLI_CMD', 'CUTOVER_REDIS_DBSIZE',
    'CUTOVER_SYSTEMCTL_CMD',
    # #9927 — the LUKS key-continuity probe's six fixture seams (key path, stamp path, cryptsetup,
    # findmnt, meminfo, oom_score_adj path), unset by the same --fixture-seams argv gate.
    'CUTOVER_CRYPTSETUP_CMD', 'CUTOVER_FINDMNT_CMD', 'CUTOVER_LUKS_KEY_FILE',
    'CUTOVER_LUKS_PROBE_STAMP', 'CUTOVER_MEMINFO', 'CUTOVER_OOM_ADJ_PATH',
    'CUTOVER_VERIFY_INTERVAL_S', 'CUTOVER_VERIFY_WINDOW_S', 'INNGEST_CUTOVER_LATCH',
    'INNGEST_CUTOVER_LATCH_MOUNT', 'INNGEST_CUTOVER_STATE',
    # #6780 — the thirteen REFRESH_* fixture seams inngest-config-refresh.sh's own
    # --fixture-seams argv gate unsets in production (cloud-init-inngest.yml). They are
    # test-only names: the unit must never inject them, so they belong here, not in
    # --only-secrets (the bound is the ONE real input, INNGEST_CONFIG_DIGEST).
    'REFRESH_BUNDLE_REPO', 'REFRESH_COSIGN_IMAGE', 'REFRESH_DOCKER_BIN',
    'REFRESH_IDENTITY_REGEXP', 'REFRESH_INSTALL_CMD', 'REFRESH_LOGGER_CMD',
    'REFRESH_NOOP_THROTTLE_S', 'REFRESH_PHONE_HOME_CMD', 'REFRESH_PULL_TIMEOUT_S',
    'REFRESH_STATE_DIR', 'REFRESH_TRUSTED_ROOT', 'REFRESH_VERIFY_TIMEOUT_S',
    'REFRESH_ZOT_ENV_FILE',
}
GUARD1_UNSET_CARDINALITY = 38

# ── the ack list: AUTHORED, each entry carrying WHY, cardinality pinned ───────────────────────
ACK_REASONS = {
    # -- exemption class A: indirect expansion over a Terraform-supplied key name ---------------
    # These four resolve their own secret as ${!<NAME>_KEY}: the tracked unit never contains the
    # secret's NAME at all, only the name of a variable holding it, which Terraform writes into
    # /etc/default/<unit> per host. A literal `--only-secrets` list in a TRACKED unit therefore
    # cannot name the secret: the unit holds a VARIABLE name, so there is nothing to enumerate.
    #
    # MEASURED, and it corrects the plan: only TWO of the four keys are per-host TODAY.
    # The server.tf provisioners that write `WEB_NIC_GUARD_URL_KEY=%s` / `WEB_ZOT_CONSUMER_URL_KEY=%s` build the key as
    # `<NAME>_${upper(replace("web-1","-","_"))}`, i.e. WEB_NIC_GUARD_URL_WEB_1 / WEB_ZOT_CONSUMER_URL_WEB_1. The ones
    # writing `INNGEST_CONSUMER_URL_KEY=%s` / `GIT_DATA_HEARTBEAT_URL_KEY=%s` are IDENTITY mappings
    # ('INNGEST_CONSUMER_URL' / 'GIT_DATA_HEARTBEAT_URL') because there is one dedicated inngest host and one
    # git-data host. The exemption holds for all four regardless: the name is not in the unit, and those two become
    # per-host on the multi-host path the fleet is opening.
    # (#9639: the web-zot-consumer-probe and web-private-nic-guard units no longer expand the key in their ExecStart;
    # the SCRIPT does, after its xtrace refusal. They stay in the population through the script-side `*_KEY` reason.)
    'web-zot-consumer-probe.service':
        'the script resolves WEB_ZOT_CONSUMER_URL_KEY by indirect expansion (${!WEB_ZOT_CONSUMER_URL_KEY}), which '
        'the WEB_ZOT_CONSUMER_URL_KEY printf in server.tf builds PER HOST (WEB_ZOT_CONSUMER_URL_WEB_1) — no literal list '
        'in a tracked unit can name it',
    'web-private-nic-guard.service':
        'the script resolves WEB_NIC_GUARD_URL_KEY by indirect expansion (${!WEB_NIC_GUARD_URL_KEY}), which '
        'the WEB_NIC_GUARD_URL_KEY printf in server.tf builds PER HOST (WEB_NIC_GUARD_URL_WEB_1) — same fail-closed '
        'multi-host break',
    'web-bash-synthetic.service':
        'the script resolves WEB_BASH_SYNTHETIC_URL_KEY by indirect expansion (${!WEB_BASH_SYNTHETIC_URL_KEY}), which '
        'the WEB_BASH_SYNTHETIC_URL_KEY printf in server.tf builds PER HOST (WEB_BASH_SYNTHETIC_URL_WEB_1 / _WEB_2) — no literal '
        'list in a tracked unit can name it. The script is the same class as its siblings in the one respect that matters here: '
        'its SOLEUR_WBS_* fixture seams (container, PATH prefix, verdict lib) are unset unless it is started with --fixture-seams, '
        'which the unit never passes, so a stray name in the injected prd root steers nothing',
    'inngest-consumer-probe.service':
        'the script resolves INNGEST_CONSUMER_URL_KEY by indirect expansion (${!INNGEST_CONSUMER_URL_KEY}), which '
        'the INNGEST_CONSUMER_URL_KEY printf in server.tf maps to the identity name today (one dedicated inngest '
        'host) — the unit never names the secret, so the list would have to be authored against a variable '
        'rather than a name',
    'web-git-data-probe.service':
        'indirect expansion of GIT_DATA_HEARTBEAT_URL_KEY; the GIT_DATA_HEARTBEAT_URL_KEY printf in server.tf is an '
        'identity mapping today for the single git-data host, with the same never-named-in-the-unit limit',
    # -- exemption class B: the read-set is not authorable from the tracked source ---------------
    'cron-egress-resolve.service':
        'read-set is not derivable: cron-egress-resolve.sh:149-157 reads SENTRY_INGEST_DOMAIN / '
        'NEXT_PUBLIC_SUPABASE_URL / SUPABASE_URL by indirect expansion over a literal loop list, '
        'and omitting one is SILENT under --no-exit-on-missing-only-secrets — :154-155 only warns '
        'and forces the tick additive-only with pruning suspended (an egress firewall that '
        'quietly stops pruning). Bounding it needs a hand-authored list, out of scope for #7761. Tracked in #7775.',
    'git-data-gc.service':
        "git-data-emit's redactor is VALUE-based (cloud-init-git-data.yml:142-150) because the "
        'LUKS passphrase is high-entropy and matches no pattern. Under a list that omits '
        'GIT_DATA_LUKS_KEY, _devalue degrades to `cat` and repack stderr rides into the emit '
        'detail (git-data-gc.sh:138,142) — a passphrase could ship unredacted to Sentry and '
        'Better Stack. Bounding this unit is a security-reviewed change, not a hygiene edit. Tracked in #7775.',
    'container-restart-monitor.service':
        'sources an env-named file (the `. "$ENV_FILE"` source in container-restart-monitor.sh) whose '
        'contents are not in-repo, so the tracked script does not bound the read-set; its Sentry '
        'alarm path also degrades silently on a missing name (:69 returns without emitting). Tracked in #7775.',
    'cron-egress-firewall.service':
        'ADDED by the #7761 review, and it is the sharpest member of class B. '
        'cron-egress-nftables.sh:134 executes "$RESOLVE_SCRIPT" behind an ASSIGNMENT PREFIX '
        '(CRON_EGRESS_FROM_LOADER=1 …), a shape the seam predicate did not match, so this unit '
        'was enumerated but never entered the bound-required population — while its ExecStart '
        'wraps `doppler run --project soleur --config prd`, i.e. the WHOLE shared soleur/prd root '
        'into a root script that then executes an environment-supplied path. That is the #7761 '
        'defect class on a larger config, and the guard said green. It is acked rather than '
        'bounded here for the same reason as its siblings: this PR delivers via '
        'apply_target=inngest-host, which does not reach the web hosts, so a bound added here '
        'would merge green and land nowhere. Tracked in #7775.',
}
# 8 -> 9 (#10455 b): web-bash-synthetic.service, class A (per-host key name; its seams are gated behind --fixture-seams).
# 7 -> 8: cron-egress-firewall.service, added when the review widened the seam predicate. This
# pin exists so the escape hatch cannot grow silently; it should only ever RATCHET DOWN as #7775
# drains it.
ACK_CARDINALITY = 9

# ── wrapper acks (#9639): units whose Exec directive STILL expands a secret by indirect expansion ─────────────────
# An Exec directive that expands a doppler-injected secret runs that expansion before the target script can refuse to
# run under xtrace, so the secret reaches the journal on a traced launch. web-private-nic-guard,
# web-zot-consumer-probe and inngest-consumer-probe were fixed (the script resolves the key after its refusal).
# The survivor has the same wrapper shape and NO xtrace refusal to order a moved lookup against; adding one is a
# separate change, so it is recorded as NOT fixed on #9639. This list can only ratchet DOWN: a fix removes the entry
# and lowers the pin, and an entry for a unit that no longer expands anything is itself a failure. Each entry is
# (the EXACT set of names the unit expands, the reason): an acked unit that gains a second expansion, or swaps the
# one it has, is a finding again.
WRAPPER_ACK_REASONS = {
    'web-git-data-probe.service':
        (('GIT_DATA_HEARTBEAT_URL_KEY',),
         'NOT fixed (#9639): the unit expands GIT_DATA_HEARTBEAT_URL_KEY in its ExecStart wrapper and its script has no '
         'xtrace refusal for a moved lookup to follow; adding one is a separate change'),
}
# 2 -> 1 (#10363): inngest-consumer-probe.service fixed — the script resolves INNGEST_CONSUMER_URL_KEY after an
# unconditional xtrace refusal and the unit's ExecStart expands nothing (the F6 block in
# inngest-consumer-probe.test.sh replays the traced launch).
WRAPPER_ACK_CARDINALITY = 1
# The wrapper stage must examine at least this many doppler-run units; a stage that checks none reports no findings.
# This is a COUNTER-PRESENCE check only: the stage counts once per doppler-run unit, so the number equals doppler_run_units
# (itself floored by MIN_DOPPLER_UNITS) and cannot see a broken INDIRECT_RE. Rows G1.1-G1.3 and G1.10-G1.12 are the
# discriminating ones; G1.4 deletes the counter and proves this floor fires.
MIN_WRAPPER_UNITS = 12

# ── inner-c acks (#11103): units whose bash -c body expands an injected name ──────────────────
# An Exec directive that wraps its target in `bash -c '...'` runs the INNER bash under the full
# `doppler run`-injected environment, and bash's xtrace writes each command AFTER expansion to
# stderr — one SHELLOPTS=xtrace / BASH_ENV / `bash -x` launch prints the resolved credential,
# which journald ships off-box (vector.toml Sources 1/4). This is the plain-$ sibling of the
# ${!...} wrapper stage above (#9639); it flagged NOTHING while inngest-redis.service and the
# rendered inngest-server.service carried `$INNGEST_REDIS_PASSWORD` / `$${INNGEST_SIGNING_KEY}`
# inside an inner -c, because the wrapper stage only knew the ${! grammar. #11103 fixed both:
# the redis unit delivers the password via an aclfile writer's ExecStartPre (ExecStart expands
# nothing, secret never on argv), and the server unit execs a launch script that resolves the
# credentials AFTER an unconditional xtrace refusal. Same ack-guard shape as WRAPPER_ACK_REASONS:
# each entry is (the EXACT set of names the unit expands, the reason), ratchet-down only, and an
# acked unit that gains or swaps an expansion is a finding again.
INNER_C_ACK_REASONS = {}
# 0: both live sites are fixed; an entry is added only with a written reason and lowers nothing.
INNER_C_ACK_CARDINALITY = 0
# Counter-presence floor, same caveat as MIN_WRAPPER_UNITS: equals doppler_run_units by
# construction and cannot see a broken INNER_C_EXPANSION_RE — the mutation rows (restore-
# requirepass, second member, @@-fragment) are the discriminating ones; the own-dispatch row
# deletes the counter and proves this floor fires.
MIN_INNER_C_UNITS = 12

# `bash -c '<body>'` inside an Exec directive — both single-quoted spellings, including the
# nested-escape '\'' form (the web-git-data-probe.service ExecStart nests its inner -c that way).
# `sh -c` is deliberately NOT matched: the exploit class (SHELLOPTS, BASH_ENV, -x propagation) is
# bash-specific — dash honours none of them — so a dash body is out of scope by decision, not by
# miss. If a unit ever swaps a dash body for bash, this stage sees it on the next scan.
INNER_C_BODY_RE = re.compile(r"bash\s+-c\s+'((?:'\\''|[^'])*)'")
# Every expansion spelling that resolves under doppler: $NAME, ${NAME}, and the systemd-escaped
# $$NAME/$${NAME} (unit $$ renders as a literal $ at runtime — all four expand identically).
# Names are pinned to [A-Z][A-Z0-9_]{2,} (>=3 chars) — a doppler secret's shape. ${!...} does NOT
# match here (`!` is not [A-Z]): it stays the wrapper stage's domain, so web-git-data-probe.service
# is covered by its existing WRAPPER ack alone and never double-flagged.
INNER_C_EXPANSION_RE = re.compile(r'\$+\{?([A-Z][A-Z0-9_]{2,})')
# A backslash-escaped literal dollar — the ONLY spelling inside a double-quoted fragment value
# that lands in the render as a live expansion (plain $ constructs are evaluated at render time
# and leave the value behind, not the $; $$ renders the PID's digits). Scanning a double-quoted
# value with the full regex would flag render-side defaults like `SDK_URL="${SDK_URL:-...}"` —
# a false positive on text that never reaches the unit as an expansion.
INNER_C_ESCAPED_RE = re.compile(r'\\\$+\{?([A-Z][A-Z0-9_]{2,})')
INNER_C_SENTINEL_RE = re.compile(r'@@([A-Z][A-Z0-9_]{2,})@@')


def inner_c_fragments(unit):
    """`NAME='...'`/`NAME="..."` assignments in the unit's own source file.

    The render fragments a unit's @@NAME@@ sentinels interpolate are assigned in the file that
    emits the heredoc (u['source'] is '<rel>:<surface>'; the BACKEND_ENV arm in
    inngest-bootstrap.sh is the live example — its value is where the durable arm's
    $${INNGEST_REDIS_PASSWORD} expansion actually lives). (quote, value) pairs are collected per
    name in assignment order — every arm is scanned, not just the last, because any arm's
    fragment can carry the expansion; the quote decides which regex applies (see above).
    """
    rel = unit['source'].rsplit(':', 1)[0]
    src = read(os.path.join(ROOT, rel))
    frags = {}
    for m in re.finditer(
            r'^\s*(?:readonly\s+|local\s+|export\s+)?'
            r'([A-Z][A-Z0-9_]{2,})=(["\'])(.*?)\2\s*$', src, re.M):
        frags.setdefault(m.group(1), []).append((m.group(2), m.group(3)))
    return frags


def inner_c_expansions(body, frags):
    """Expansion names in the body, plus any transitively-referenced @@SENTINEL@@ fragment.

    A directive that writes `bash -c 'x; @@FRAG@@ y'` carries no literal expansion — the fragment
    resolution is what delivers one. Without it the stage would certify the exact site it was
    built to catch (the rendered inngest-server.service reads `@@BACKEND_ENV@@`, not a $). `seen`
    keeps a self-referential fragment finite.
    """
    names = set(INNER_C_EXPANSION_RE.findall(body))
    seen, work = set(), list(INNER_C_SENTINEL_RE.findall(body))
    while work:
        sname = work.pop()
        if sname in seen:
            continue
        seen.add(sname)
        for quote, v in frags.get(sname, []):
            names.update((INNER_C_EXPANSION_RE if quote == "'" else INNER_C_ESCAPED_RE).findall(v))
            work.extend(INNER_C_SENTINEL_RE.findall(v))
    return names


# ── surface enumeration (LIFTED from credential-persist-home-guard.test.sh:506-605) ───────────
# The two non-obvious behaviours a fresh scanner gets wrong SILENTLY are kept verbatim:
#   * the `.tf` \n-unescape — terraform inline arrays are \n-escaped SINGLE-LINE strings that a
#     naive scanner reads as one line and matches nothing, failing OPEN;
#   * the in-place `.terraform/` prune (dirs[:] assignment; rebinding `dirs` does not prune).
EXEC_RE = re.compile(r'^\s*Exec(?:Start|StartPre|StartPost)=(.*)$', re.M)
# systemd continues any directive whose line ends in a backslash. Every directive regex here is
# line-anchored, so WITHOUT this join a multi-line ExecStart is TRUNCATED at the first backslash
# — and the flip unit's bound lives ENTIRELY on continuation lines, so the guard would read every
# unit as unbounded and every row below would be meaningless. `execs` is the UNION of the joined
# and the raw body so no directive can be lost to the join absorbing its successor.
CONT_RE = re.compile(r'\\\n[ \t]*')
HEREDOC_RE = re.compile(
    r'cat\s*>\s*("[^"]*"|\'[^\']*\'|\S+)\s*<<-?\s*["\']?(\w+)["\']?\n(.*?)\n[ \t]*\2', re.S)
# A directive INJECTED by shell assignment rather than written inside a heredoc — the fifth
# extraction. inngest-bootstrap.sh:1089 is the only real member today.
INJECTED_RE = re.compile(
    r'^\s*(?:readonly\s+|local\s+|export\s+)?(\w+)=(["\'])'
    r'(Exec(?:Start|StartPre|StartPost)=.*?)\2\s*$', re.M)
ASSIGN_RE = re.compile(r'^\s*(?:readonly\s+|local\s+|export\s+)?(\w+)="?(/[^"\'\s]+)"?\s*$', re.M)


def _clean(p):
    return p.strip().strip('"').strip("'")


def mk_unit(name, source, surface, body):
    raw = body
    joined = CONT_RE.sub(' ', body)
    execs = [m.group(1).strip() for m in EXEC_RE.finditer(joined)]
    for m2 in EXEC_RE.finditer(raw):
        t = m2.group(1).strip()
        if t not in execs:
            execs.append(t)
    return {'name': name, 'source': source, 'surface': surface, 'execs': execs}


def _heredoc_name(target, assigns):
    t = _clean(target)
    if t.startswith('$'):
        key = t.lstrip('$').strip('{}')
        if key in assigns:
            return os.path.basename(assigns[key])
        return t
    return os.path.basename(t) if '/' in t else t


def heredoc_units(src, assigns):
    for m in HEREDOC_RE.finditer(src):
        yield _heredoc_name(m.group(1), assigns), _clean(m.group(1)), m.group(3)


def cloudinit_blocks(src):
    """Yield (path, body) for every `content: |` block, tagged with the nearest preceding path:.

    cloud-init write_files units are INDENTED YAML block-scalars, NOT heredocs — a `cat >` regex
    finds ZERO here, which is the non-vacuous-zero false-green the per-surface floor guards.
    """
    out = []
    lines = src.split('\n')
    i = 0
    cur_path = None
    while i < len(lines):
        pm = re.match(r'^\s*-?\s*path:\s*(\S+)', lines[i])
        if pm:
            cur_path = _clean(pm.group(1))
        m = re.match(r'^(\s*)content:\s*\|', lines[i])
        if m:
            indent = len(m.group(1))
            j = i + 1
            body = []
            while j < len(lines):
                if lines[j].strip() == '':
                    body.append('')
                    j += 1
                    continue
                li = len(lines[j]) - len(lines[j].lstrip())
                if li <= indent:
                    break
                body.append(lines[j])
                j += 1
            out.append((cur_path, '\n'.join(body)))
            i = j
            continue
        i += 1
    return out


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def is_unit_body(body):
    return bool(re.search(r'^\s*\[Service\]', body, re.M)) or bool(EXEC_RE.search(body))


def enumerate_all(root):
    """Return (units, injected, scripts). scripts maps basename -> (origin, body).

    A script can be authored on THREE surfaces and the same basename can appear on more than one
    (git-data-gc.sh is both a tracked file and a cloud-init `content:` copy). The TRACKED FILE
    always wins: the embedded copies are terraform-templated, so their `$` are written `$$` and
    every seam form silently stops matching — a fail-OPEN that measured as "git-data-gc.service
    is not in the population" while the tracked script plainly carries a `"$EMIT"` seam.
    """
    units, injected, tracked, embedded = [], [], {}, {}
    for dp, dirs, files in os.walk(root):
        # `.terraform/modules/` holds real .tf files as soon as any `module {}` block with a
        # registry/git source is added; enumerating vendored third-party units would RED on code
        # the team does not own. `dirs[:]` in-place assignment is required.
        dirs[:] = [d for d in dirs if d != '.terraform']
        for fn in sorted(files):
            path = os.path.join(dp, fn)
            rel = os.path.relpath(path, root)
            if fn.endswith('.test.sh'):  # test fixtures build unit strings; never real defs
                continue
            if fn.endswith('.service'):
                body = read(path)
                if is_unit_body(body):
                    units.append(mk_unit(fn, rel + ':service', 'service', body))
            elif fn.endswith(('.sh', '.tf')):
                src = read(path)
                if fn.endswith('.tf'):
                    src = src.replace('\\n', '\n')
                surface = 'tf-heredoc' if fn.endswith('.tf') else 'sh-heredoc'
                assigns = dict(ASSIGN_RE.findall(src))
                for name, target, body in heredoc_units(src, assigns):
                    if is_unit_body(body):
                        units.append(mk_unit(name, rel + ':heredoc', surface, body))
                        continue
                    key = target.lstrip('$').strip('{}')
                    resolved = target if target.startswith('/') else assigns.get(key)
                    if resolved:
                        embedded.setdefault(os.path.basename(resolved), (rel + ':heredoc', body))
                for m in INJECTED_RE.finditer(src):
                    injected.append(mk_unit('%s[%s]' % (fn, m.group(1)),
                                            rel + ':injected', surface, m.group(3)))
                if fn.endswith('.sh'):
                    tracked[fn] = (rel, src)
            elif fn.endswith(('.yml', '.yaml')):
                for idx, (cpath, body) in enumerate(cloudinit_blocks(read(path))):
                    if is_unit_body(body):
                        dm = re.search(r'^\s*Description=(.*)$', body, re.M)
                        nm = (dm.group(1).strip()[:40] if dm else 'unit%d' % idx)
                        units.append(mk_unit('%s[%s]' % (fn, nm), rel + ':cloud-init',
                                             'cloud-init', body))
                    elif cpath and cpath.startswith('/'):
                        # cloud-init bodies are rendered through terraform templatefile(), which
                        # escapes a literal `$` as `$$`. Un-escape before any expansion-shaped
                        # regex reads them, or every seam and read-set form matches nothing.
                        embedded.setdefault(os.path.basename(cpath),
                                            (rel + ':cloud-init', body.replace('$$', '$')))
    scripts = dict(embedded)
    scripts.update(tracked)
    return units, injected, scripts


# ── stage 2: the `doppler run` population ────────────────────────────────────────────────────
# TWO spellings, because the literal is not the population:
#   a) `doppler run` / `/usr/local/bin/doppler run`
#   b) `"$D" run` / `${DOPPLER_BIN} run` — the binary resolved into a variable first
DOPPLER_LITERAL_RE = re.compile(r'\bdoppler\s+run\b')
DOPPLER_VAR_RE = re.compile(r'(?:"\$\{?(\w+)\}?"|\$\{(\w+)\}|\$(\w+))\s+run\b')


def doppler_run_offset(exec_text):
    """Offset just past the `run` token of a doppler invocation, or None."""
    m = DOPPLER_LITERAL_RE.search(exec_text)
    if m:
        return m.end()
    for m in DOPPLER_VAR_RE.finditer(exec_text):
        var = m.group(1) or m.group(2) or m.group(3)
        # The variable must demonstrably hold the doppler binary somewhere in the SAME directive.
        if re.search(r'\b%s=[^;]*doppler' % re.escape(var), exec_text) or 'DOPPLER' in var.upper():
            return m.end()
    return None


SEP_RE = re.compile(r'(?<=\s)--(?=\s)')
# `--no-exit-on-missing-only-secrets` CONTAINS the substring `only-secrets`. The negative
# lookbehind on [-\w] is what stops it being read as a bound — anchor on the construct, never the
# bare token (cq-assert-anchor-not-bare-token).
ONLY_SECRETS_RE = re.compile(r'(?<![-\w])--only-secrets(?:[= ]+)([^\s]*)')
# Unit side: ANY indirect expansion in an Exec directive, whatever follows the name: nothing (`${!K}`), an operator
# (`${!K:-}`, `${!K+x}`), a substring or trim or case or replace form (`${!K:0:3}`, `${!K#p}`, `${!K%p}`, `${!K/a/b}`,
# `${!K^^}`, `${!K,,}`), a subscript (`${!K[0]}`), a subscript followed by any of those (`${!K[0]:-x}`) or the prefix forms
# (`${!K@}`, `${!K*}`).
INDIRECT_RE = re.compile(r'\$\{!(\w+)(?:\[[^\]]*\])?(?:[-+=?:#%/^,@*][^}]*)?\}')
# Script side (#9639): a doppler TARGET script that resolves its own secret through a variable named `*_KEY` (the per-host
# key NAME an env file carries), in every spelling the unit-side regex knows (the two share one grammar). The array
# index list `${!MAP_KEY[@]}` matches too: it is not a secret lookup, and a doppler script that iterates a `*_KEY` array
# would enter the population as a false positive, which fails closed (an ack or a bound resolves it). Bound to the `_KEY` convention on purpose: the unrestricted form also matched
# `${!_seam+x}` in the (since retired) inngest-luks-cutover.sh, pulling that unit into the population and turning it red.
SCRIPT_KEY_INDIRECT_RE = re.compile(r'\$\{!(\w*_KEY)(?:\[[^\]]*\])?(?:[-+=?:#%/^,@*][^}]*)?\}')
PATH_TOKEN_RE = re.compile(r'/usr/(?:local/)?bin/([A-Za-z0-9._-]+)')


def analyse_exec(exec_text):
    """None if not a doppler-run directive, else a dict describing its bound."""
    off = doppler_run_offset(exec_text)
    if off is None:
        return None
    seg = exec_text[off:]
    sep = SEP_RE.search(seg)
    prefix = seg[:sep.start()] if sep else seg
    suffix = seg[sep.end():] if sep else ''
    names, empties = [], 0
    for m in ONLY_SECRETS_RE.finditer(prefix):
        raw = m.group(1).strip().strip('"').strip("'")
        vals = [v for v in raw.split(',') if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', v)]
        if vals:
            names.extend(vals)
        else:
            empties += 1
    return {
        'names': names,
        'empty_flags': empties,
        'after_sep_only_secrets': bool(ONLY_SECRETS_RE.search(suffix)),
        'indirect': sorted(set(INDIRECT_RE.findall(exec_text))),
        'targets': sorted(set(PATH_TOKEN_RE.findall(exec_text))),
    }


# ── stage 4: the exec seam predicate ─────────────────────────────────────────────────────────
# "Uses an environment value in COMMAND POSITION (executed or sourced)" — three high-precision
# forms only. Deliberately NARROW: a loose form (matching after `&&`, or inside [[ … ]]) put
# arithmetic and string comparisons into the population when measured, and a false member here is
# a permanently-red guard, not a near miss.
# An optional COMMAND PREFIX may sit between the line start and the variable: an assignment
# (`FOO=1 "$X"`) or a wrapper carrying its own arguments (`env FOO=1 "$X"`, `timeout 5 "$X"`).
# Without it, cron-egress-nftables.sh's `CRON_EGRESS_FROM_LOADER=1 "$RESOLVE_SCRIPT"` was not a
# seam, so cron-egress-firewall.service — a ROOT unit injecting the whole shared soleur/prd
# (~116 names) into a script that then executes an environment-supplied path — was enumerated but
# never entered the bound-required population. Same defect class as #7761, larger config, and the
# guard said green. The prefix is anchored and non-greedy so it cannot swallow a continued
# argument list (see the docstring below for why that exclusion is load-bearing).
# The assignment value excludes `$` and backtick DELIBERATELY. Without that, `DETAIL=$(tail -n 20
# "${DETAIL_SRC}"` parses as assignment-prefix + flag + count + quoted-var and puts
# git-data-gc-failure.service into the population on the strength of a value that is READ as a
# path, never executed — a false member, which per the docstring below is a permanently-red guard
# rather than a near miss. Measured: the widening admitted it, and this exclusion removes it while
# keeping the true positive (`CRON_EGRESS_FROM_LOADER=1 "$RESOLVE_SCRIPT"`).
_CMD_PREFIX = r'(?:(?:env|command|timeout|xargs|nohup|setsid|sudo)[ \t]+)?(?:[A-Za-z_][A-Za-z0-9_]*=[^ \t"$`]*[ \t]+|-[^ \t]+[ \t]+|[0-9]+[ \t]+)*'
CMD_POS_RE = re.compile(r'^[ \t]*' + _CMD_PREFIX + r'"\$\{?([A-Z_][A-Z0-9_]*)(?:[:#%/][^"]*)?\}?"')
SEAM_FORMS = (
    ('exec-var', re.compile(r'\bexec[ \t]+"?\$\{?([A-Z_][A-Z0-9_]*)', re.M)),
    ('sourced-path', re.compile(r'(?:^|[ \t;])(?:\.|source)[ \t]+"?\$\{?([A-Z_][A-Z0-9_]*)', re.M)),
)


def cmd_position_seam(lines):
    """A leading `"$VAR"` is command position ONLY when the line starts a command.

    The exclusion is load-bearing and was measured: git-data-emit's curl payload continues its
    argument list onto a line beginning `"${MSG}" "${LEVEL}" …`, whose predecessor ends in a
    backslash. Read as command position that put git-data-gc-failure.service into the population
    on the strength of a printf ARGUMENT — a false member, i.e. a permanently-red guard.
    """
    prev = ''
    for ln in lines:
        m = CMD_POS_RE.match(ln)
        if m and not prev.rstrip().endswith('\\'):
            return 'cmd-position:%s' % m.group(1)
        if ln.strip():
            prev = ln
    return None


def strip_comments(src):
    # Only a `#` that STARTS a word is a comment: "${VAR#prefix}" must survive, or the seam forms
    # stop matching parameter-expansion spellings and the guard fails open.
    return '\n'.join(re.sub(r'(^|\s)#.*$', r'\1', ln) for ln in src.split('\n'))


def seam_evidence(body):
    src = strip_comments(body)
    hit = cmd_position_seam(src.split('\n'))
    if hit:
        return hit
    for label, rx in SEAM_FORMS:
        m = rx.search(src)
        if m:
            return '%s:%s' % (label, m.group(1))
    return None


# ── stage 7: the read-set LOWER BOUND ────────────────────────────────────────────────────────
SHELL_BUILTINS = {
    'BASH_SOURCE', 'BASH_VERSION', 'BASH_REMATCH', 'BASHPID', 'BASH_SUBSHELL', 'BASH_LINENO',
    'BASH_COMMAND', 'FUNCNAME', 'LINENO', 'RANDOM', 'SECONDS', 'PIPESTATUS', 'OPTARG', 'OPTIND',
    'REPLY', 'IFS', 'PATH', 'HOME', 'PWD', 'OLDPWD', 'SHELL', 'SHLVL', 'USER', 'LOGNAME', 'UID',
    'EUID', 'HOSTNAME', 'HOSTTYPE', 'OSTYPE', 'MACHTYPE', 'TERM', 'TMPDIR', 'LANG', 'LC_ALL',
    'LC_CTYPE', 'COLUMNS', 'LINES', 'EDITOR', 'PAGER', 'EPOCHSECONDS', 'EPOCHREALTIME',
    'GLOBIGNORE', 'PS1', 'PS2', 'PS4', 'DEBIAN_FRONTEND',
}
READ_RE = re.compile(r'\$\{!?([A-Z][A-Z0-9_]{2,})[:\-+#%/}\[]|\$([A-Z][A-Z0-9_]{2,})\b')
ASSIGNED_RE = re.compile(
    r'^\s*(?:readonly\s+|local\s+|export\s+|declare\s+-\w+\s+)?([A-Z][A-Z0-9_]{2,})=', re.M)
FORVAR_RE = re.compile(r'\bfor\s+([A-Z][A-Z0-9_]{2,})\s+in\b')


def read_set_lower_bound(body):
    src = strip_comments(body)
    reads = set()
    for m in READ_RE.finditer(src):
        reads.add(m.group(1) or m.group(2))
    assigned = set(ASSIGNED_RE.findall(src)) | set(FORVAR_RE.findall(src))
    return sorted(reads - assigned - SHELL_BUILTINS - GUARD1_UNSET)


def main():
    units, injected, scripts = enumerate_all(ROOT)

    by_surface = {}
    for u in units:
        by_surface[u['surface']] = by_surface.get(u['surface'], 0) + 1
    print('CENSUS: units=%d injected_directives=%d scripts_indexed=%d'
          % (len(units), len(injected), len(scripts)))
    for s in sorted(MIN_UNITS_BY_SURFACE):
        print('CENSUS: surface=%-11s scanned=%-3d min=%d'
              % (s, by_surface.get(s, 0), MIN_UNITS_BY_SURFACE[s]))
    print('CENSUS: surface=%-11s scanned=%-3d min=%d'
          % ('sh-injected', len(injected), MIN_INJECTED_DIRECTIVES))

    rc = 0
    # PER-SURFACE FLOOR. A scanner that matches zero units on a surface reports zero violators and
    # passes forever; the .tf \n-unescape and the cloud-init block-scalar walk are each one edit
    # away from that, and neither failure is visible in a total.
    # --- BEGIN PER-SURFACE FLOOR (the H2 anti-vacuity row anchors on these markers) ---
    for s, floor in sorted(MIN_UNITS_BY_SURFACE.items()):
        got = by_surface.get(s, 0)
        if got < floor:
            print('SURFACE_FLOOR_FAIL surface=%s scanned=%d min=%d — the extractor for this '
                  'authoring surface matches nothing; a green run would mean "scanned nothing"'
                  % (s, got, floor))
            rc = 4
    if len(injected) < MIN_INJECTED_DIRECTIVES:
        print('SURFACE_FLOOR_FAIL surface=sh-injected scanned=%d min=%d — an ExecStartPre injected '
              'by shell assignment (inngest-bootstrap.sh:1089) is no longer seen'
              % (len(injected), MIN_INJECTED_DIRECTIVES))
        rc = 4
    # --- END PER-SURFACE FLOOR ---
    if rc:
        return rc

    if len(GUARD1_UNSET) != GUARD1_UNSET_CARDINALITY:
        print('ACK_FAIL guard1_unset_cardinality=%d expected=%d'
              % (len(GUARD1_UNSET), GUARD1_UNSET_CARDINALITY))
        return 5
    if len(ACK_REASONS) != ACK_CARDINALITY:
        print('ACK_FAIL ack_cardinality=%d expected=%d — the ack list is the guard\'s only escape '
              'hatch; changing its size must be a deliberate, visible edit'
              % (len(ACK_REASONS), ACK_CARDINALITY))
        return 5
    for name, reason in sorted(ACK_REASONS.items()):
        if len(reason.strip()) < 40:
            print('ACK_FAIL unit=%s — ack entries carry a written reason, not a bare name' % name)
            return 5
    if len(WRAPPER_ACK_REASONS) != WRAPPER_ACK_CARDINALITY:
        print('ACK_FAIL wrapper_ack_cardinality=%d expected=%d — the wrapper-ack list is an escape hatch; '
              'changing its size must be a deliberate, visible edit'
              % (len(WRAPPER_ACK_REASONS), WRAPPER_ACK_CARDINALITY))
        return 5
    for name, (ack_names, reason) in sorted(WRAPPER_ACK_REASONS.items()):
        if not ack_names or len(reason.strip()) < 40:
            print('ACK_FAIL wrapper unit=%s — wrapper-ack entries carry a written reason, not a bare name' % name)
            return 5
    if len(INNER_C_ACK_REASONS) != INNER_C_ACK_CARDINALITY:
        print('ACK_FAIL inner_c_ack_cardinality=%d expected=%d — the inner-c ack list is an escape '
              'hatch; changing its size must be a deliberate, visible edit'
              % (len(INNER_C_ACK_REASONS), INNER_C_ACK_CARDINALITY))
        return 5
    for name, (ack_names, reason) in sorted(INNER_C_ACK_REASONS.items()):
        if not ack_names or len(reason.strip()) < 40:
            print('ACK_FAIL inner_c unit=%s — inner-c ack entries carry a written reason, not a bare name' % name)
            return 5

    doppler = []
    for u in units + injected:
        infos = [i for i in (analyse_exec(e) for e in u['execs']) if i]
        if infos:
            doppler.append((u, infos))
    print('CENSUS: doppler_run_units=%d min=%d' % (len(doppler), MIN_DOPPLER_UNITS))
    if len(doppler) < MIN_DOPPLER_UNITS:
        print('CENSUS_FAIL doppler_run_units=%d (<%d) — the population selector matches nothing, '
              'so every bound assertion below is vacuous' % (len(doppler), MIN_DOPPLER_UNITS))
        return 3

    findings = []
    population = []
    wrapper_checked = 0
    wrapper_hits = set()
    inner_c_checked = 0
    inner_c_hits = set()
    for u, infos in doppler:
        reasons, targets = [], []
        # --- wrapper stage (#9639): no Exec directive of a doppler-run unit expands a secret indirectly -------
        wrapper_checked += 1
        w_ind = sorted({i for info in infos for i in info['indirect']})
        if w_ind:
            wrapper_hits.add(u['name'])
            if u['name'] not in WRAPPER_ACK_REASONS:
                findings.append(
                    'FINDING unit=%s reason=wrapper expands a secret by indirect expansion (%s) in an Exec '
                    'directive that invokes `doppler run`: the expansion runs before the target script can refuse to '
                    'run under xtrace; resolve the key inside the script after its refusal src=%s'
                    % (u['name'], ','.join('${!%s}' % i for i in w_ind), u['source']))
            elif set(w_ind) != set(WRAPPER_ACK_REASONS[u['name']][0]):
                findings.append(
                    'FINDING unit=%s reason=wrapper-acked unit expands %s but its ack names only %s: an ack covers the '
                    'exact expansion it recorded, not the unit src=%s'
                    % (u['name'], ','.join('${!%s}' % i for i in w_ind),
                       ','.join('${!%s}' % i for i in sorted(WRAPPER_ACK_REASONS[u['name']][0])), u['source']))
        # --- inner -c stage (#11103): no Exec directive of a doppler-run unit expands an injected
        #     name inside a `bash -c` body — literal, or delivered through a @@SENTINEL@@ fragment
        #     assigned in the same source file. ${!...} is the wrapper stage's domain (excluded so
        #     web-git-data-probe.service is not double-flagged); `sh -c` is out of scope (dash
        #     honours neither SHELLOPTS nor BASH_ENV — the class is bash-specific).
        inner_c_checked += 1
        ic_bodies = [m.group(1) for e in u['execs'] for m in INNER_C_BODY_RE.finditer(e)]
        ic_names = set()
        if ic_bodies:
            frags = inner_c_fragments(u)
            for b in ic_bodies:
                ic_names |= inner_c_expansions(b, frags)
            if ic_names:
                inner_c_hits.add(u['name'])
                if u['name'] not in INNER_C_ACK_REASONS:
                    findings.append(
                        'FINDING unit=%s reason=inner-bash-c expands a doppler-injected name (%s) inside an '
                        'inner `bash -c` body of a doppler-run Exec directive: a traced launch '
                        '(SHELLOPTS=xtrace / BASH_ENV / bash -x) prints the resolved value to stderr and '
                        'journald ships it off-box; the directive must expand nothing and the target must '
                        'resolve the name after an unconditional xtrace refusal src=%s'
                        % (u['name'], ','.join('$%s' % i for i in sorted(ic_names)), u['source']))
                elif ic_names != set(INNER_C_ACK_REASONS[u['name']][0]):
                    findings.append(
                        'FINDING unit=%s reason=inner-bash-c-acked unit expands %s but its ack names only '
                        '%s: an ack covers the exact expansion set it recorded, not the unit src=%s'
                        % (u['name'], ','.join('$%s' % i for i in sorted(ic_names)),
                           ','.join('$%s' % i for i in sorted(INNER_C_ACK_REASONS[u['name']][0])), u['source']))
        for info in infos:
            for ind in info['indirect']:
                reasons.append('indirect-expansion:%s' % ind)
            for t in info['targets']:
                if t in scripts:
                    ev = seam_evidence(scripts[t][1])
                    if ev:
                        reasons.append('seam[%s]:%s' % (t, ev))
                        targets.append(t)
                    for km in SCRIPT_KEY_INDIRECT_RE.finditer(strip_comments(scripts[t][1])):
                        reasons.append('script-indirect-expansion:%s' % km.group(1))
        names, empty, after_sep = [], 0, False
        for info in infos:
            names += info['names']
            empty += info['empty_flags']
            after_sep = after_sep or info['after_sep_only_secrets']
        print('  UNIT: %-46s surface=%-11s bound=%-5s src=%s'
              % (u['name'], u['surface'], bool(names), u['source']))
        print('  INNER_C unit=%s bodies=%d' % (u['name'], len(ic_bodies)))
        if not reasons:
            continue
        population.append(u['name'])
        print('        POPULATION reason=%s' % '; '.join(sorted(set(reasons))))
        if names:
            lower = set()
            for t in targets:
                lower |= set(read_set_lower_bound(scripts[t][1]))
            missing = sorted(lower - set(names))
            if missing:
                findings.append(
                    'READ_SET_FAIL unit=%s missing-from-only-secrets=%s — the script provably '
                    'reads this name and the AUTHORED list omits it; under '
                    '--no-exit-on-missing-only-secrets that is silent at run time. This is a '
                    'LOWER BOUND, not a derivation: add the name to --only-secrets, or to '
                    "Guard 1's unset list if it is a fixture seam."
                    % (u['name'], ','.join(missing)))
            continue
        if u['name'] in ACK_REASONS:
            continue
        if after_sep:
            findings.append(
                'FINDING unit=%s reason=--only-secrets sits AFTER the `--` separator, where it is '
                'an argument to the CHILD command rather than a `doppler run` flag; the whole '
                'config is still injected src=%s' % (u['name'], u['source']))
        elif empty:
            findings.append(
                'FINDING unit=%s reason=--only-secrets carries an EMPTY value, so it enumerates '
                'nothing src=%s' % (u['name'], u['source']))
        else:
            findings.append(
                'FINDING unit=%s reason=no --only-secrets bound on a `doppler run` whose target '
                'takes an environment value in command position (%s) and which is not in the ack '
                'list src=%s' % (u['name'], '; '.join(sorted(set(reasons)))[:120], u['source']))

    print('CENSUS: bound_required_population=%d min=%d' % (len(population), MIN_POPULATION))
    if len(population) < MIN_POPULATION:
        print('CENSUS_FAIL bound_required_population=%d (<%d) — the seam predicate matches nothing'
              % (len(population), MIN_POPULATION))
        return 3
    print('CENSUS: wrapper_units_checked=%d min=%d' % (wrapper_checked, MIN_WRAPPER_UNITS))
    if wrapper_checked < MIN_WRAPPER_UNITS:
        print('CENSUS_FAIL wrapper_units_checked=%d (<%d) — the wrapper stage examined too few units; a stage '
              'that checks none reports no findings and passes' % (wrapper_checked, MIN_WRAPPER_UNITS))
        return 3
    print('CENSUS: inner_c_units_checked=%d min=%d' % (inner_c_checked, MIN_INNER_C_UNITS))
    if inner_c_checked < MIN_INNER_C_UNITS:
        print('CENSUS_FAIL inner_c_units_checked=%d (<%d) — the inner -c stage examined too few units; a stage '
              'that checks none reports no findings and passes' % (inner_c_checked, MIN_INNER_C_UNITS))
        return 3

    stale = sorted(set(ACK_REASONS) - set(population))
    if stale:
        print('ACK_FAIL stale=%s — acked units no longer in the population; delete the entry and '
              'lower ACK_CARDINALITY rather than leaving a hole open' % ','.join(stale))
        rc = 5

    stale_w = sorted(set(WRAPPER_ACK_REASONS) - wrapper_hits)
    if stale_w:
        print('ACK_FAIL wrapper_stale=%s — wrapper-acked units whose Exec directives no longer expand a secret '
              'indirectly; delete the entry and lower WRAPPER_ACK_CARDINALITY' % ','.join(stale_w))
        rc = 5

    stale_ic = sorted(set(INNER_C_ACK_REASONS) - inner_c_hits)
    if stale_ic:
        print('ACK_FAIL inner_c_stale=%s — inner-c-acked units whose bash -c bodies no longer expand an '
              'injected name; delete the entry and lower INNER_C_ACK_CARDINALITY' % ','.join(stale_ic))
        rc = 5

    for f in findings:
        print(f)
    if any(f.startswith('READ_SET_FAIL') for f in findings):
        rc = 6
    if any(f.startswith('FINDING') for f in findings):
        rc = 2
    return rc


sys.exit(main())
PYEOF

echo ""
echo "--- control: the UNMUTATED tree ---"
CONTROL_OUT="$TMPROOT/control.txt"
if python3 "$SCANNER" "$FROZEN_ROOT" >"$CONTROL_OUT" 2>&1; then
  pass "baseline: the real tree is GREEN (a red baseline would void every mutation row)"
else
  fail "baseline: the real tree is RED — every mutation row below is unattributable" \
    "$(grep -E 'FINDING|_FAIL' "$CONTROL_OUT" | head -5)"
fi

# ── census + identity pins ────────────────────────────────────────────────────────────────────
echo ""
echo "--- census: per-surface breakdown (all four authoring surfaces + injected directives) ---"
grep -E '^CENSUS:' "$CONTROL_OUT" | sed 's/^/  /'

for _s in service sh-heredoc tf-heredoc cloud-init sh-injected; do
  _line="$(grep -E "^CENSUS: surface=${_s}[ ]" "$CONTROL_OUT" || true)"
  if [[ -z "$_line" ]]; then
    fail "census: no scanned count reported for surface '$_s'"
    continue
  fi
  _got="$(sed -E 's/.*scanned=([0-9]+).*/\1/' <<<"$_line")"
  _min="$(sed -E 's/.*min=([0-9]+).*/\1/' <<<"$_line")"
  if (( _got >= _min )) && (( _min >= 1 )); then
    pass "census: surface '$_s' scanned $_got units (floor $_min)"
  else
    fail "census: surface '$_s' scanned $_got units, floor $_min"
  fi
done

# THE SAME ANTI-VACUITY CHECK FOR THE TWO NON-SURFACE FLOORS. The loop above walks only the
# per-surface keys, so MIN_DOPPLER_UNITS and MIN_POPULATION had no meta-floor: setting either to 0
# left the suite fully green. Those two guard the sets EVERY violation assertion quantifies over —
# stage 2 (the doppler-run population) and stage 4 (the bound-required set) — so a zeroed floor
# there is the most load-bearing vacuity available in this file.
for _c in doppler_run_units bound_required_population wrapper_units_checked inner_c_units_checked; do
  _line="$(grep -E "^CENSUS: ${_c}=" "$CONTROL_OUT" | sed -n '1p' || true)"
  if [[ -z "$_line" ]]; then
    fail "census: no count reported for '$_c'"
    continue
  fi
  _got="$(sed -E "s/.*${_c}=([0-9]+).*/\1/" <<<"$_line")"
  _min="$(sed -E 's/.*min=([0-9]+).*/\1/' <<<"$_line")"
  if (( _got >= _min )) && (( _min >= 1 )); then
    pass "census: '$_c' is $_got (floor $_min, and the floor is non-zero)"
  else
    fail "census: '$_c' is $_got, floor $_min (a zero floor makes every assertion over this set vacuous)"
  fi
done

# IDENTITY, not just cardinality. `>= N` is satisfied by ANY member, so a scanner that lost the
# ExecStartPre extraction or the `command -v doppler` spelling still clears every floor. Pin the
# members the four scoping decisions are ABOUT, by name.
_pin_seen() {
  if grep -qE "^  UNIT: +$2" "$CONTROL_OUT"; then
    pass "scan saw $1"
  else
    fail "scan did NOT see $1 — the extraction for this shape is gone" \
      "$(grep -cE '^  UNIT:' "$CONTROL_OUT") units enumerated in total"
  fi
}
# Scoping decision 1: ExecStartPre injected by shell assignment (inngest-bootstrap.sh:1089).
_pin_seen "the ExecStartPre flip-guard injected via FLIP_GUARD_LINE" \
  'inngest-bootstrap\.sh\[FLIP_GUARD_LINE\]'
# Scoping decision 2: units that never contain the literal `doppler run`.
_pin_seen "cron-egress-firewall.service (resolved-binary spelling)" 'cron-egress-firewall\.service'
_pin_seen "container-restart-monitor.service (resolved-binary spelling)" \
  'container-restart-monitor\.service'
_pin_seen "the web-host vector unit from soleur-host-bootstrap.sh (heredoc surface)" \
  'soleur-vector-install'
# The unit this change is about.
_pin_seen "inngest-cutover-flip.service" 'inngest-cutover-flip\.service'
# #6894 (RETIRED, #10112): the LUKS cutover unit was a SECOND root doppler-run unit on this host; its two pins
# (seen, and bound=True) went with the unit when the cutover trio left the image.

# THE JOIN IS LOAD-BEARING. The flip unit's bound lives ENTIRELY on continuation lines; without
# CONT_RE the scanner reads it as unbounded and every row below is meaningless. Assert the
# scanner's own verdict on that unit, not just that it was seen.
if grep -qE '^  UNIT: +inngest-cutover-flip\.service +surface=service +bound=True' "$CONTROL_OUT"
then
  pass "systemd line continuations are joined: the flip unit's multi-line bound is DETECTED"
else
  fail "the flip unit reads as UNBOUNDED — CONT_RE is not joining continuations, so every mutation row pins nothing" \
    "$(grep -E '^  UNIT: +inngest-cutover-flip' "$CONTROL_OUT")"
fi

# Known false positives, each a must-PASS: their targets are vendor binaries, not repo scripts
# with an exec seam, so they must be SEEN but must NOT enter the bound-required population.
_pin_fp() {
  if ! grep -qE "^  UNIT: +$2" "$CONTROL_OUT"; then
    fail "FP pin: $1 was not even enumerated"
    return 0
  fi
  # The POPULATION line is printed directly under its unit; -A1 is the association.
  if grep -A1 -E "^  UNIT: +$2" "$CONTROL_OUT" | grep -c 'POPULATION' >/dev/null; then
    fail "FP pin: $1 entered the bound-required population (false positive)"
  else
    pass "FP pin: $1 is enumerated but not bound-required"
  fi
}
_pin_fp "inngest-server.service (\`inngest start\`, not a repo script)" 'inngest-server\.service'
_pin_fp "inngest-redis.service (redis-server)" 'inngest-redis\.service'
_pin_fp "the inngest-host vector unit" 'vector\.service'
_pin_fp "the web-host vector unit" 'soleur-vector-install'

# ── inner -c stage (#11103): identity pins on the two remediated units ─────────────────────────
# A scanner whose enumeration loses one of these surfaces still clears every floor above; pin
# that the stage SAW each unit (the INNER_C line is emitted once per doppler-run unit) and
# reported NO inner-bash-c finding for it.
for _u in inngest-redis.service inngest-server.service; do
  if grep -qE "^  INNER_C unit=${_u} bodies=" "$CONTROL_OUT"; then
    pass "inner-c stage examined $_u (its INNER_C line is present)"
  else
    fail "inner-c stage did NOT examine $_u — its enumeration of this surface is gone" \
      "$(grep -cE '^  INNER_C unit=' "$CONTROL_OUT") doppler units examined in total"
  fi
  if grep -qE "^FINDING unit=${_u} reason=inner-bash-c" "$CONTROL_OUT"; then
    fail "inner-c stage flagged $_u — a doppler-injected name still expands inside a bash -c body" \
      "$(grep -E "^FINDING unit=${_u}" "$CONTROL_OUT" | head -2)"
  else
    pass "inner-c stage: no inner-bash-c finding for $_u (the #11103 fix holds)"
  fi
done
# Mutation-matrix row 7 is the LIVE pin: web-git-data-probe.service's inner -c expands
# ${!GIT_DATA_HEARTBEAT_URL_KEY} — the wrapper stage's grammar, deliberately excluded here so the
# stages never double-flag. The stage must SEE the body (bodies>=1) yet report no inner-c finding.
if grep -qE '^  INNER_C unit=web-git-data-probe\.service bodies=[1-9]' "$CONTROL_OUT" \
   && ! grep -qE '^FINDING unit=web-git-data-probe\.service reason=inner-bash-c' "$CONTROL_OUT"; then
  pass "inner-c stage: web-git-data-probe.service's \${!...} body is seen but not flagged (wrapper stage's domain)"
else
  fail "inner-c stage mis-handled web-git-data-probe.service's \${!...} body (exclusion or extraction broke)" \
    "$(grep -E 'INNER_C unit=web-git-data-probe|FINDING unit=web-git-data-probe' "$CONTROL_OUT" | head -3)"
fi

# ── mutation battery ──────────────────────────────────────────────────────────────────────────
echo ""
echo "--- mutation battery: each row must independently drive RED, attributed ---"

expect_red() {
  # expect_red <label> <attribution-substring> <mutate-fn>
  local label="$1" attrib="$2" mutate_fn="$3"
  local sbx; sbx="$(fresh_sbx mut)"
  copy_scan_tree "$FROZEN_ROOT" "$sbx"
  if ! python3 "$SCANNER" "$sbx" >/dev/null 2>&1; then
    fail "$label: fresh copy not GREEN before mutation (latent FAIL — attribution unsafe)"
    return 0
  fi
  "$mutate_fn" "$sbx"
  # A mutation that does NOT land reports the baseline, which is indistinguishable from a pass.
  if scan_diff "$FROZEN_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (it pins nothing)"
    return 0
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN on the mutated tree (VACUOUS)"
    return 0
  fi
  if grep -qF "$attrib" <<<"$out"; then
    pass "$label (RED rc=$rc, attributed)"
  else
    fail "$label: RED (rc=$rc) not attributed to '$attrib' — could be a pre-existing latent FAIL" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

expect_green() {
  local label="$1" mutate_fn="$2"
  local sbx; sbx="$(fresh_sbx grn)"
  copy_scan_tree "$FROZEN_ROOT" "$sbx"
  "$mutate_fn" "$sbx"
  if scan_diff "$FROZEN_ROOT" "$sbx" >/dev/null 2>&1; then
    fail "$label: mutation did not change the tree (the GREEN pin is vacuous)"
    return 0
  fi
  local out rc
  out="$(python3 "$SCANNER" "$sbx" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (stayed GREEN)"
  else
    fail "$label: guard went RED (false positive, rc=$rc)" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

FLIPU="inngest-cutover-flip.service"

# R1 — the flip unit loses its bound entirely.
r1() { sed -i '/^  --only-secrets /d' "$1/$FLIPU"; }
expect_red "R1 --only-secrets dropped from the flip unit" \
  "FINDING unit=$FLIPU reason=no --only-secrets bound" r1

# R2 — a SECOND member: a new doppler-run unit whose target has an exec seam and no bound. The
# one-member population is the shape where the guard only knows about the unit it shipped with.
# Written as ExecStartPre= so this row also covers scoping decision 1 end-to-end.
r2() {
  cat > "$1/r2-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$R2_SEAM_CMD" --emit
SH
  cat > "$1/r2-newunit.service" <<'UNIT'
[Unit]
Description=R2 fixture: doppler-run unit with an exec-seam target and no bound
[Service]
Type=oneshot
ExecStartPre=/usr/bin/doppler run --config prd -- /usr/local/bin/r2-seam.sh
ExecStart=/bin/true
UNIT
}
expect_red "R2 new doppler-run ExecStartPre unit with an exec-seam script and no bound" \
  "FINDING unit=r2-newunit.service reason=no --only-secrets bound" r2

# R3 — a name removed from an AUTHORED list while its script demonstrably reads that secret. This
# is the row covering the residual `--no-exit-on-missing-only-secrets` introduces, which is
# otherwise SILENT at run time. It checks the authored list against a LOWER BOUND of names the
# script provably reads; it is not, and cannot be, a complete derivation.
r3() { sed -i '/^  --only-secrets INNGEST_REDIS_PASSWORD /d' "$1/$FLIPU"; }
expect_red "R3 one name removed from the list while the script still reads it" \
  "READ_SET_FAIL unit=$FLIPU missing-from-only-secrets=INNGEST_REDIS_PASSWORD" r3

# R4 — the flag moved AFTER the `--`, where it is an argument to the child command rather than a
# `doppler run` flag. Textually present, semantically absent: the whole config is still injected.
r4() {
  python3 - "$1/$FLIPU" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^  --only-secrets \w+ \\\n', '', s, flags=re.M)
s = s.replace('  -- /usr/local/bin/inngest-cutover-flip.sh',
              '  -- /usr/local/bin/inngest-cutover-flip.sh --only-secrets INNGEST_CUTOVER_FLIP')
open(p, 'w').write(s)
PY
}
expect_red "R4 --only-secrets moved after the \`--\` (child argument, not a doppler flag)" \
  'reason=--only-secrets sits AFTER the `--` separator' r4

# R5 — the scan matches zero units on one surface (the guard's own dispatch). Deleting the only
# .tf that carries inline unit heredocs is the cheapest way to reach a zero surface without
# touching the scanner.
r5() { rm -f "$1/server.tf"; }
expect_red "R5 scan matches zero units on the tf-heredoc surface (per-surface floor)" \
  "SURFACE_FLOOR_FAIL surface=tf-heredoc" r5

# R6 — the list replaced with the empty string. `--only-secrets` is still textually present.
r6() {
  python3 - "$1/$FLIPU" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('  --only-secrets INNGEST_CUTOVER_FLIP \\\n', '  --only-secrets "" \\\n')
s = re.sub(r'^  --only-secrets (INNGEST_REDIS_PASSWORD|DOPPLER_CONFIG) \\\n', '', s, flags=re.M)
open(p, 'w').write(s)
PY
}
expect_red "R6 secret list replaced with the empty string" \
  'reason=--only-secrets carries an EMPTY value' r6

# ── scanner-side mutations (rows whose system under test is the ack list / the floor) ──────────
expect_red_scanner() {
  # expect_red_scanner <label> <attribution-substring> <program>
  local label="$1" attrib="$2" prog="$3"
  local mut="$TMPROOT/scanner.mut.py"
  cp "$SCANNER" "$mut"
  python3 - "$mut" "$prog" <<'PY'
import re, sys
p, prog = sys.argv[1], sys.argv[2]
s = open(p).read()
ENTRY = r"    'container-restart-monitor\.service':\n(?:        .*\n)+"
if prog == 'drop-ack-entry':
    # Remove the ack entry AND lower the pinned cardinality, so the cardinality pin cannot be what
    # reds — this row must be carried by the now-unacked unbounded unit itself.
    #
    # The cardinality is DERIVED, not transcribed. It was hardcoded as `7 -> 6`, so the day the ack
    # list legitimately grew the replace silently no-opped: the mutation did not land, the
    # cardinality pin fired instead of the FINDING, and the row reported a failure that was not
    # about what it claimed. A mutation that does not land is the documented worst case — it
    # reports a verdict about something other than the property under test.
    s = re.sub(ENTRY, '', s)
    m = re.search(r'^ACK_CARDINALITY = (\d+)$', s, re.M)
    if not m:
        raise SystemExit('drop-ack-entry: could not find ACK_CARDINALITY to lower')
    n = int(m.group(1))
    s = re.sub(r'^ACK_CARDINALITY = \d+$', 'ACK_CARDINALITY = %d' % (n - 1), s, count=1, flags=re.M)
elif prog == 'drop-ack-entry-only':
    s = re.sub(ENTRY, '', s)
elif prog == 'ack-extra-name':
    old = "(('GIT_DATA_HEARTBEAT_URL_KEY',),"
    if s.count(old) != 1:
        raise SystemExit('ack-extra-name: expected exactly one %s, found %d' % (old, s.count(old)))
    s = s.replace(old, "(('GIT_DATA_HEARTBEAT_URL_KEY', 'GIT_DATA_EXTRA_KEY'),")
elif prog == 'noop-wrapper-stage':
    # The wrapper stage's own dispatch: make it examine nothing. The new census floor must catch it.
    if s.count('        wrapper_checked += 1\n') != 1:
        raise SystemExit('noop-wrapper-stage: could not find the stage counter')
    s = s.replace('        wrapper_checked += 1\n', '')
elif prog == 'noop-inner-c-stage':
    # The inner -c stage's own dispatch: make it examine nothing. The census floor must catch it.
    if s.count('        inner_c_checked += 1\n') != 1:
        raise SystemExit('noop-inner-c-stage: could not find the stage counter')
    s = s.replace('        inner_c_checked += 1\n', '')
elif prog in ('drop-wrapper-ack', 'wrapper-pin-only', 'add-wrapper-ack'):
    m = re.search(r'^WRAPPER_ACK_CARDINALITY = (\d+)$', s, re.M)
    if not m:
        raise SystemExit('%s: could not find WRAPPER_ACK_CARDINALITY' % prog)
    n = int(m.group(1))
    if prog == 'drop-wrapper-ack':
        # Remove the sibling's wrapper ack AND lower the pin, so the pin cannot be what reds.
        # Only inside WRAPPER_ACK_REASONS: ACK_REASONS carries an entry with the same key.
        head, sep, tail = s.partition('WRAPPER_ACK_REASONS = {\n')
        tail2 = re.sub(r"    'web-git-data-probe\.service':\n(?:        .*\n)+", '', tail, count=1)
        if not sep or tail2 == tail:
            raise SystemExit('drop-wrapper-ack: entry not found')
        s2 = head + sep + tail2
        s = re.sub(r'^WRAPPER_ACK_CARDINALITY = \d+$', 'WRAPPER_ACK_CARDINALITY = %d' % (n - 1), s2, count=1, flags=re.M)
    elif prog == 'wrapper-pin-only':
        s = re.sub(r'^WRAPPER_ACK_CARDINALITY = \d+$', 'WRAPPER_ACK_CARDINALITY = %d' % (n - 1), s, count=1, flags=re.M)
    else:
        # A wrapper ack for a FIXED unit (which no longer expands anything), with the pin raised to match.
        new = ("    'web-private-nic-guard.service':\n"
               "        (('WEB_NIC_GUARD_URL_KEY',), 'a stale wrapper ack for a unit that no longer expands a secret in any Exec directive'),\n")
        s2 = s.replace("WRAPPER_ACK_REASONS = {\n", "WRAPPER_ACK_REASONS = {\n" + new, 1)
        if s2 == s:
            raise SystemExit('add-wrapper-ack: dict not found')
        s = re.sub(r'^WRAPPER_ACK_CARDINALITY = \d+$', 'WRAPPER_ACK_CARDINALITY = %d' % (n + 1), s2, count=1, flags=re.M)
else:
    raise SystemExit('unknown program %s' % prog)
open(p, 'w').write(s)
PY
  if cmp -s "$SCANNER" "$mut"; then
    fail "$label: scanner mutation did not land (it pins nothing)"
    return 0
  fi
  local out rc
  out="$(python3 "$mut" "$FROZEN_ROOT" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label: guard stayed GREEN with the mutated scanner (VACUOUS)"
    return 0
  fi
  if grep -qF "$attrib" <<<"$out"; then
    pass "$label (RED rc=$rc, attributed)"
  else
    fail "$label: RED (rc=$rc) not attributed to '$attrib'" \
      "$(grep -E 'FINDING|_FAIL' <<<"$out" | head -3)"
  fi
}

# R7a — an ack entry removed WITHOUT bounding its unit: the unit becomes an unacked violation.
expect_red_scanner "R7a ack entry removed without bounding its unit" \
  "FINDING unit=container-restart-monitor.service reason=no --only-secrets bound" 'drop-ack-entry'
# R7b — the CARDINALITY row proper: the pin refuses a silent change to the escape hatch's size.
#
# The expected string is DERIVED from the scanner's own ACK_CARDINALITY, not transcribed. Both R7
# rows previously carried the literal (`ack_cardinality=6 expected=7`), so adding a member to the
# ack list — which is a legitimate, reviewed act — silently falsified the mutation rows and the
# suite dropped two assertions. The floor caught it; a transcribed literal in a mutation row is
# the same replicated-literal class this guard exists to police, one level up.
#
# The `|| true` is LOAD-BEARING, not hygiene. Without it the FATAL guard on the line below is
# UNREACHABLE in the one case it exists for: this file runs under `set -Eeuo pipefail`, so a grep
# that matches nothing aborts the script AT THE ASSIGNMENT, and the diagnostic naming the broken
# derivation never prints — the suite just stops, which reads like a harness reap rather than a
# defect in its own accounting. Caught by scripts/lint-shell-capture-exit; the guard-with-an-
# unreachable-guard is the same shape as routing an assertion floor through the helper it
# backstops, which review already found three times in this PR.
ACK_N="$(grep -oE '^ACK_CARDINALITY = [0-9]+' "$SCRIPT_DIR/doppler-injection-bound.test.sh" | grep -oE '[0-9]+$' || true)"
[[ "$ACK_N" =~ ^[0-9]+$ ]] || { printf 'FATAL: could not derive ACK_CARDINALITY for the R7b row (got %s).\n' "${ACK_N:-<empty>}" >&2; exit 1; }
expect_red_scanner "R7b ack cardinality pin (a silent ack edit cannot open a hole)" \
  "ACK_FAIL ack_cardinality=$((ACK_N - 1)) expected=${ACK_N}" 'drop-ack-entry-only'

# G1.4 / G1.6 / G1.7 / G1.8 — the wrapper stage's own machinery (scanner-side mutations).
expect_red_scanner "G1.4 a wrapper stage that examines nothing (own-dispatch floor)" \
  "CENSUS_FAIL wrapper_units_checked" 'noop-wrapper-stage'
expect_red_scanner "G1.6 an unfixed sibling's wrapper ack removed (pin lowered too)" \
  "FINDING unit=web-git-data-probe.service reason=wrapper expands a secret" 'drop-wrapper-ack'
expect_red_scanner "G1.7 a wrapper ack for a FIXED unit is stale" \
  "ACK_FAIL wrapper_stale=web-private-nic-guard.service" 'add-wrapper-ack'
WACK_N="$(grep -oE '^WRAPPER_ACK_CARDINALITY = [0-9]+' "$SCRIPT_DIR/doppler-injection-bound.test.sh" | grep -oE '[0-9]+$' || true)"
[[ "$WACK_N" =~ ^[0-9]+$ ]] || { printf 'FATAL: could not derive WRAPPER_ACK_CARDINALITY for the G1.8 row (got %s).\n' "${WACK_N:-<empty>}" >&2; exit 1; }
expect_red_scanner "G1.8 the wrapper-ack pin refuses a silent edit" \
  "ACK_FAIL wrapper_ack_cardinality=${WACK_N} expected=$((WACK_N - 1))" 'wrapper-pin-only'

# ── #9639 F6: the wrapper stage ───────────────────────────────────────────────────────────────
# No Exec directive of a doppler-run unit may expand a secret by indirect expansion: that expansion runs before the
# target script can refuse to run under xtrace. Fixed units (web-private-nic-guard, web-zot-consumer-probe) stay in the
# Guard-2 population through the SCRIPT-side `*_KEY` reason; the two unfixed siblings are wrapper-acked.
NICU="web-private-nic-guard.service"
OLD_NIC_EXEC='ExecStart=/bin/bash -c '"'"'doppler run --project soleur --config prd -- bash -c '"'"'\'"'"''"'"'export WEB_NIC_GUARD_URL="$${!WEB_NIC_GUARD_URL_KEY}"; exec /usr/local/bin/web-private-nic-guard.sh'"'"'\'"'"''"'"''"'"
set_execstart() {   # <unit file> <full ExecStart line> : replace the unit's ExecStart line (the edit must land)
  python3 - "$1" "$2" <<'PY'
import re, sys
p, line = sys.argv[1], sys.argv[2]
s = open(p).read()
n = len(re.findall(r'^ExecStart=.*$', s, flags=re.M))
if n != 1:
    raise SystemExit('set_execstart: expected exactly one ExecStart line in %s, found %d' % (p, n))
open(p, 'w').write(re.sub(r'^ExecStart=.*$', lambda m: line, s, flags=re.M))
PY
}
# G1.1 — the pre-fix wrapper expansion restored in the nic-guard unit.
g11() { set_execstart "$1/$NICU" "$OLD_NIC_EXEC"; }
expect_red "G1.1 the wrapper expansion restored in a fixed unit" \
  "FINDING unit=$NICU reason=wrapper expands a secret" g11
# G1.2 — a SECOND directive expanding the secret, after a compliant first one: the check quantifies over every directive.
g12() { printf '%s\n' "ExecStartPre=/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export G12_X=\"\$\${!WEB_NIC_GUARD_URL_KEY}\"; true'\\'''" >> "$1/$NICU"; }
expect_red "G1.2 a second Exec directive expands the secret (compliant first member)" \
  "FINDING unit=$NICU reason=wrapper expands a secret" g12
# G1.3 — the operator-suffixed spelling the script itself uses.
g13() { set_execstart "$1/$NICU" "ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export WEB_NIC_GUARD_URL=\"\$\${!WEB_NIC_GUARD_URL_KEY:-}\"; exec /usr/local/bin/web-private-nic-guard.sh'\\'''"; }
expect_red "G1.3 the \${!KEY:-} spelling is a wrapper expansion too" \
  "FINDING unit=$NICU reason=wrapper expands a secret" g13
# G1.5 — the script-side reason is what keeps the fixed unit in the population: strip it and the ack goes stale.
g15() {
  python3 - "$1/web-private-nic-guard.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '${!WEB_NIC_GUARD_URL_KEY:-}'
if s.count(old) != 1:
    raise SystemExit('g15: expected exactly one %s in the script, found %d' % (old, s.count(old)))
open(p, 'w').write(s.replace(old, 'x'))
PY
}
expect_red "G1.5 stripping the script-side indirect expansion drops the unit from the population (its ack goes stale)" \
  "ACK_FAIL stale=$NICU" g15
# G1.9 — the script-side regex is bound to the `*_KEY` convention: ${!FOO_KEY:-} enters the population, ${!_seam+x} does not.
g19a() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'URL="${!G19A_URL_KEY:-}"' 'echo "$URL"' > "$1/g19a.sh"
  printf '%s\n' '[Unit]' 'Description=G1.9a fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g19a.sh' > "$1/g19a.service"
}
expect_red "G1.9a a script resolving \${!FOO_KEY:-} enters the population (unbounded, unacked: RED)" \
  "FINDING unit=g19a.service reason=no --only-secrets bound" g19a
g19b() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'if [ -n "${!_g19b_seam+x}" ]; then echo set; fi' > "$1/g19b.sh"
  printf '%s\n' '[Unit]' 'Description=G1.9b fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g19b.sh' > "$1/g19b.service"
}
expect_green "G1.9b a script using \${!_seam+x} does NOT enter the population (the regex is bound to *_KEY)" g19b
# GH2 — must-PASS non-canonical: the fixed unit written WITHOUT the outer `bash -c` is still compliant and still counted.
gh2() { set_execstart "$1/$NICU" 'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/web-private-nic-guard.sh'; }
expect_green "GH2 a fixed unit written without the outer bash -c stays GREEN (the contract is no expansion, not one spelling)" gh2
# G1.10 — an ack covers the EXACT expansion it recorded: a wrapper-acked unit that gains a second expansion is a finding again.
g110() { printf '%s\n' "ExecStartPre=/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export G110_X=\"\$\${!G110_OTHER_KEY}\"; true'\\'''" >> "$1/web-git-data-probe.service"; }
expect_red "G1.10 a wrapper-acked unit gains a SECOND expansion its ack does not name" \
  "FINDING unit=web-git-data-probe.service reason=wrapper-acked unit expands" g110
# G1.10b/c — the ack is EXACT in both directions: a unit that SWAPS the one name it expands, and an ack that names MORE than the unit expands.
g110b() { sed -i 's/\${!GIT_DATA_HEARTBEAT_URL_KEY}/${!GIT_DATA_SWAPPED_KEY}/' "$1/web-git-data-probe.service"; }
expect_red "G1.10b a wrapper-acked unit SWAPS the name it expands (the ack names the old one)" \
  "FINDING unit=web-git-data-probe.service reason=wrapper-acked unit expands \${!GIT_DATA_SWAPPED_KEY} but its ack names only \${!GIT_DATA_HEARTBEAT_URL_KEY}" g110b
expect_red_scanner "G1.10c a wrapper ack that names MORE than the unit expands is a finding too" \
  "FINDING unit=web-git-data-probe.service reason=wrapper-acked unit expands" 'ack-extra-name'
# G1.11 — every spelling of an indirect expansion the unit-side regex must see, not only the bare and operator forms.
g_spell() {   # <dir> <suffix after the variable name> : the nic unit's ExecStart expands ${!WEB_NIC_GUARD_URL_KEY<suffix>}
  set_execstart "$1/$NICU" "ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export WEB_NIC_GUARD_URL=\"\$\${!WEB_NIC_GUARD_URL_KEY$2}\"; exec /usr/local/bin/web-private-nic-guard.sh'\\'''"
}
g111a() { g_spell "$1" ':0:3'; }
g111b() { g_spell "$1" '[0]'; }
g111c() { g_spell "$1" '@'; }
g111d() { g_spell "$1" '#p'; }
g111e() { g_spell "$1" '/a/b'; }
g111f() { g_spell "$1" '^^'; }
g111g() { g_spell "$1" '[0]:-x'; }
g111h() { g_spell "$1" '[0]#p'; }
for g111 in "a:\${!K:0:3} substring" "b:\${!K[0]} subscript" "c:\${!K@} prefix list" "d:\${!K#p} trim" "e:\${!K/a/b} replace" "f:\${!K^^} case" "g:\${!K[0]:-x} subscript plus operator" "h:\${!K[0]#p} subscript plus trim"; do
  expect_red "G1.11${g111%%:*} the $(printf '%s' "${g111#*:}") spelling is a wrapper expansion too" \
    "FINDING unit=$NICU reason=wrapper expands a secret" "g111${g111%%:*}"
done
# G1.12 — the script-side regex across the operator group, and the comment-stripped body (settled ruling: comments do not count).
g112a() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'URL="${!G112A_URL_KEY}"' 'echo "$URL"' > "$1/g112a.sh"
  printf '%s\n' '[Unit]' 'Description=G1.12a fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g112a.sh' > "$1/g112a.service"
}
expect_red "G1.12a a script resolving the bare \${!FOO_KEY} (no operator) enters the population" \
  "FINDING unit=g112a.service reason=no --only-secrets bound" g112a
g112b() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'URL="${!G112B_URL_KEY:?}"' 'echo "$URL"' > "$1/g112b.sh"
  printf '%s\n' '[Unit]' 'Description=G1.12b fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g112b.sh' > "$1/g112b.service"
}
expect_red "G1.12b a script resolving \${!FOO_KEY:?} enters the population" \
  "FINDING unit=g112b.service reason=no --only-secrets bound" g112b
g112c() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' '# URL="${!G112C_URL_KEY:-}"  (documented only, never executed)' 'echo hello' > "$1/g112c.sh"
  printf '%s\n' '[Unit]' 'Description=G1.12c fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g112c.sh' > "$1/g112c.service"
}
expect_green "G1.12c a \${!FOO_KEY:-} that exists only in a COMMENT does NOT enter the population (the body is comment-stripped)" g112c
g112d() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'URL="${!G112D_URL_KEY:0:3}"' 'echo "$URL"' > "$1/g112d.sh"
  printf '%s\n' '[Unit]' 'Description=G1.12d fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g112d.sh' > "$1/g112d.service"
}
expect_red "G1.12d a script resolving \${!FOO_KEY:0:3} (a substring form) enters the population" \
  "FINDING unit=g112d.service reason=no --only-secrets bound" g112d
g112e() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -u' 'URL="${!G112E_URL_KEY[0]}"' 'echo "$URL"' > "$1/g112e.sh"
  printf '%s\n' '[Unit]' 'Description=G1.12e fixture' '[Service]' 'Type=oneshot' \
    'ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/g112e.sh' > "$1/g112e.service"
}
expect_red "G1.12e a script resolving \${!FOO_KEY[0]} (a subscript form) enters the population" \
  "FINDING unit=g112e.service reason=no --only-secrets bound" g112e

# ── #11103: the inner `bash -c` stage ─────────────────────────────────────────────────────────
# The wrapper stage only knew the ${!...} grammar; inngest-redis.service's
# `--requirepass "$INNGEST_REDIS_PASSWORD"` and the rendered inngest-server.service's signing-key
# strip + BACKEND_ENV durable arm escaped it with PLAIN-$ spellings inside an inner -c (#11103).
# IC rows pin the stage's own machinery: the two remediated sites, its dispatch counter, a second
# member, the @@SENTINEL@@ fragment-resolution arm, and the regex itself.
# IC1 — the pre-fix requirepass ExecStart restored in the redis unit: the plain-$ expansion
# inside the inner -c is the exact live site this stage exists for.
ic1() {
  set_execstart "$1/inngest-redis.service" 'ExecStart=/usr/bin/doppler run --config ${DOPPLER_CONFIG} -- /usr/bin/bash -c '"'"'/usr/bin/redis-server /mnt/data/redis/inngest-redis.conf --requirepass "$INNGEST_REDIS_PASSWORD"'"'"''
}
expect_red "IC1 the pre-fix requirepass bash -c restored in inngest-redis.service" \
  "FINDING unit=inngest-redis.service reason=inner-bash-c" ic1
# IC2 — the stage's own dispatch: a counter deletion leaves the stage examining nothing, and
# only the census floor sees it.
expect_red_scanner "IC2 an inner -c stage that examines nothing (own-dispatch floor)" \
  "CENSUS_FAIL inner_c_units_checked" 'noop-inner-c-stage'
# IC3 — a SECOND member: a fresh doppler-run unit expands a name inside bash -c while every
# pre-existing member is compliant. A check that stops at the first member is the defect.
ic3() {
  cat > "$1/ic3-innerc.service" <<'UNIT'
[Unit]
Description=IC3 fixture: doppler-run unit expanding a secret inside an inner bash -c
[Service]
Type=oneshot
ExecStart=/usr/bin/doppler run --config prd -- bash -c 'export X="$FOO_SECRET"; true'
UNIT
}
expect_red "IC3 a second doppler-run unit expands a name inside bash -c (compliant first member)" \
  "FINDING unit=ic3-innerc.service reason=inner-bash-c" ic3
# IC4 — the @@SENTINEL@@ arm: the directive's -c body carries only @@FRAG@@; the expansion lives
# in the same-file FRAG='...' assignment. A literal-text-only stage certifies the exact site it
# exists to catch (the live site-2 expansion rode @@BACKEND_ENV@@).
ic4() {
  cat > "$1/ic4-gen.sh" <<'SH'
#!/usr/bin/env bash
FRAG='export K="$LEAK_SECRET";'
cat > /etc/systemd/system/ic4-frag.service <<'IC4EOF'
[Unit]
Description=IC4 fixture: expansion delivered through a @@SENTINEL@@ fragment
[Service]
Type=oneshot
ExecStart=/usr/bin/doppler run --config prd -- bash -c 'x; @@FRAG@@ y'
IC4EOF
SH
}
expect_red "IC4 a secret-bearing @@FRAGMENT@@ interpolated into a bash -c body is seen through the sentinel" \
  "FINDING unit=ic4-frag.service reason=inner-bash-c" ic4
# IC5 — the expansion regex is LOAD-BEARING (positive control): neuter it, and the same violating
# tree (IC3's fixture) goes GREEN under the mutated scanner. Without this arm a typo'd regex
# ships a stage that matches nothing and passes forever.
IC5_MUT="$TMPROOT/scanner.noicc.py"
cp "$SCANNER" "$IC5_MUT"
python3 - "$IC5_MUT" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s2, n = re.subn(
    r"INNER_C_EXPANSION_RE = re\.compile\(r'[^']*'\)",
    "INNER_C_EXPANSION_RE = re.compile(r'(?!x)x')", s, count=1)
if n != 1:
    raise SystemExit('IC5: could not neuter INNER_C_EXPANSION_RE (count=%d)' % n)
open(p, 'w').write(s2)
PY
if cmp -s "$SCANNER" "$IC5_MUT"; then
  fail "IC5: the regex-neuter mutation did not land (the control pins nothing)"
else
  _ic5sbx="$(fresh_sbx ic5)"
  copy_scan_tree "$FROZEN_ROOT" "$_ic5sbx"
  ic3 "$_ic5sbx"
  _ic5_real_rc=0
  python3 "$SCANNER" "$_ic5sbx" >/dev/null 2>&1 || _ic5_real_rc=$?
  if [[ "$_ic5_real_rc" -eq 0 ]]; then
    fail "IC5 control precondition: the violating tree is GREEN under the REAL scanner — the row discriminates nothing"
  elif python3 "$IC5_MUT" "$_ic5sbx" >/dev/null 2>&1; then
    pass "IC5 neutering INNER_C_EXPANSION_RE lets the violating tree pass (the regex is load-bearing)"
  else
    fail "IC5: the neutered-regex scanner still went RED — the stage flags something other than expansions" \
      "$(python3 "$IC5_MUT" "$_ic5sbx" 2>&1 | grep -E 'FINDING|_FAIL' | head -3)"
  fi
fi
# IC6 — must-PASS non-canonical: a `sh -c` (dash) body is out of scope by DECISION — dash honours
# neither SHELLOPTS nor BASH_ENV, so the exploit class is bash-specific. Widening is a deliberate
# later edit, not a silent default.
ic6() {
  cat > "$1/ic6-dash.service" <<'UNIT'
[Unit]
Description=IC6 fixture: a sh -c (dash) body is out of the inner -c stage's scope
[Service]
Type=oneshot
ExecStart=/usr/bin/doppler run --config prd -- sh -c 'export X="$DASH_OK"; true'
UNIT
}
expect_green "IC6 a sh -c body expanding \$DASH_OK stays GREEN (dash honours none of the trace vectors)" ic6

# ── harness rows ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- harness rows ---"

# H1 — a \n-ESCAPED unit inside a `.tf` heredoc. Terraform inline arrays are \n-escaped
# SINGLE-LINE strings; a scanner without the unescape reads one line, matches nothing and fails
# OPEN. Without this row, R2 and R5 are both satisfiable by a scanner that misses .tf entirely.
h1() {
  cat > "$1/h1-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$H1_SEAM_CMD" --go
SH
  cat > "$1/h1-fixture.tf" <<'TF'
resource "null_resource" "h1_fixture" {
  provisioner "remote-exec" {
    inline = [
      "cat > /etc/systemd/system/h1-escaped.service <<'EOF'\n[Unit]\nDescription=H1 tf-heredoc fixture\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/doppler run --config prd -- /usr/local/bin/h1-seam.sh\nEOF",
    ]
  }
}
TF
}
expect_red "H1 escaped unbounded unit inside a .tf heredoc (the surface already burned on)" \
  "FINDING unit=h1-escaped.service reason=no --only-secrets bound" h1

# H2 — remove the per-surface floor assertion itself. Two arms, because a deleted floor makes the
# scanner GREENER, not redder: the ANTI-VACUITY pin (ADR-193) is the source pin in arm (a), and
# arm (b) proves the floor was what caught R5 in the first place.
H2_MUT="$TMPROOT/scanner.nofloor.py"
cp "$SCANNER" "$H2_MUT"
python3 - "$H2_MUT" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'    # --- BEGIN PER-SURFACE FLOOR.*?    # --- END PER-SURFACE FLOOR ---\n', '', s,
           flags=re.S)
open(p, 'w').write(s)
PY
if cmp -s "$SCANNER" "$H2_MUT"; then
  fail "H2: floor-removal mutation did not land (both arms below pin nothing)"
else
  # Arm (a) — the anti-vacuity source pin: the floor construct must be present in the scanner.
  if grep -qF 'SURFACE_FLOOR_FAIL surface=%s' "$SCANNER" \
     && grep -qF 'MIN_UNITS_BY_SURFACE.items()' "$SCANNER"; then
    if grep -qF 'MIN_UNITS_BY_SURFACE.items()' "$H2_MUT"; then
      fail "H2a: the anti-vacuity source pin does not notice a deleted floor assertion"
    else
      pass "H2a anti-vacuity (ADR-193): deleting the per-surface floor assertion reds this pin"
    fi
  else
    fail "H2a: the per-surface floor construct is missing from the scanner"
  fi
  # Arm (b) — positive control: with the floor gone, R5's zero-unit tree goes GREEN, which is what
  # makes arm (a) worth having.
  _h2sbx="$(fresh_sbx h2)"
  copy_scan_tree "$FROZEN_ROOT" "$_h2sbx"
  rm -f "$_h2sbx/server.tf"
  if python3 "$H2_MUT" "$_h2sbx" >/dev/null 2>&1; then
    pass "H2b positive control: without the floor, a zero-unit surface passes silently"
  else
    fail "H2b positive control did not reproduce — R5's RED may come from something else"
  fi
fi

# H3 — must-PASS non-canonical: the conditional `command -v doppler` wrap with `--only-secrets`
# inside the exec arm. The contract is the BOUND, not one spelling.
h3() {
  cat > "$1/h3-seam.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
H3_SEAM_CMD="${H3_SEAM_CMD:-/bin/true}"
"$H3_SEAM_CMD" --go "$H3_FIXTURE_SECRET"
SH
  cat > "$1/h3-noncanonical.service" <<'UNIT'
[Unit]
Description=H3 fixture: conditional command -v doppler wrap, bound inside the exec arm
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'D="$(command -v doppler || true)"; if [ -n "$D" ] && [ -n "$DOPPLER_TOKEN" ]; then exec "$D" run --project soleur --config prd --only-secrets H3_FIXTURE_SECRET -- /usr/local/bin/h3-seam.sh; else exec /usr/local/bin/h3-seam.sh; fi'
UNIT
}
expect_green "H3 non-canonical \`command -v doppler\` wrap WITH a bound in the exec arm" h3

# H4 — scoping decision 3: a `runcmd` doppler invocation is NOT flagged. The boot isolation
# self-check at cloud-init-inngest.yml:604-611 must see all names; demanding a bound there would
# self-defeat the provision-time control this guard is the runtime half of.
h4() {
  python3 - "$1/cloud-init.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('runcmd:',
              'runcmd:\n  - doppler run --config prd -- /usr/local/bin/container-restart-monitor.sh',
              1)
open(p, 'w').write(s)
PY
}
expect_green "H4 runcmd doppler invocation is NOT flagged (boot self-check must see all names)" h4

# ── suite-level anti-vacuity floor ────────────────────────────────────────────────────────────
# The sole merge gate is the exit code below, and it reads FAIL alone — so deleting every
# expect_red/expect_green invocation would report FAIL=0 and exit 0. A FLOOR, not equality: bump
# it deliberately when adding assertions; NEVER lower it to make a run pass.
TOTAL=$((PASS + FAIL))
# 25 -> 29 -> 45 -> 61 (#9639: the wrapper-stage rows, then the review round's spelling and ack-exactness rows): set to the measured green count, not below it. Slack in a floor is the budget an
# attacker (or an accidental deletion) gets for free.
# 61 -> 59 (#10112): the two LUKS cutover unit pins (seen, bound) left with the retired unit; set to the measured green count.
# 59 -> 71 (#11103): the inner -c stage (census-floor member, two identity pins, the ${!...}
# no-double-flag pin) + IC1-IC6 mutation rows; measured 71/71.
MIN_ASSERTIONS=71
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  # printf + exit, NOT fail() (ADR-193): routing the floor through the counter it exists to
  # protect means one edit disarms both. See the instrument self-test at the top.
  printf 'FAIL: assertion count %s < floor %s — the battery silently stopped running. An assertion was deleted or an early return skipped a block; this is not a count to lower.\n' \
    "$PASS" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== doppler-injection-bound: Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
