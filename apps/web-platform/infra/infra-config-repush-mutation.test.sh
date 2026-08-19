#!/usr/bin/env bash
# Mutation battery for the #7104 PR-B bounded re-push — Guard 1 and Guard 2 (tasks 4.3, 8.2).
#
# AC21: "Every Guard 1 and Guard 2 mutation row is committed and drives the suite RED when
# applied, including the two rows that target the guard's own dispatch." A matrix in a plan is a
# claim; this file is the measurement. Every sibling bash mutation battery in this directory is
# `*-mutation.test.sh` AND registered in .github/workflows/infra-validation.yml
# (workspaces-luks-g4, web-host-provisioner-parity, inngest-rls, scan-workflow,
# zot-image-staleness), so this one follows both halves of that convention. An unrun battery is
# a claim, not a guard.
#
# (An earlier revision of this header also cited `cf-tunnel-liveness-gate` as a sibling "in this
# directory". It is not: it lives in scripts/ and is named `-mutations.test.sh`, plural. The
# citation was inherited verbatim from the zot battery's header, where it was correct.)
#
# WHAT IT DRIVES. Each row copies a minimal repo skeleton, applies exactly one mutation, and runs
# the real suite that is supposed to catch it — infra-config-gate.test.sh for the Guard 1 and
# Guard 2 rows, infra-config-verify.test.sh for the stub-fidelity row. The tracked tree is never
# mutated.
#
# WHICH AXES THIS BATTERY EDITS, stated so the omissions are visible rather than implied:
#   dispatch           — G1-4 (the predicate's own `declare -F`), D1 (the harness's fail())
#   fixture shape      — G1-6 (the fixture builder's default supplying the asserted value)
#   member cardinality — G1-5 (a SECOND member added to the success set)
#   population growth  — G2-3 (a SECOND production apply site ADDED, not an edit to the first)
#   region boundaries  — G2-5 (a nested `done` inside the pinned region)
#   authority input    — D2 (the output the workflow's `if:` literals are validated against)
#   assertion count    — G2-7 (the anti-vacuity floor, via deletion of a pinned block)
#   harness stubbing   — S1-S4 (the PATH stubs' argv contract: the URL path, the HOST, the HMAC
#                        VALUE and the secret NAME. S2-S4 were added after measuring that the
#                        stubs pinned PRESENCE only, so a body polling the wrong host, signing
#                        with an empty HMAC, or reading the wrong secret stayed green)
#   temporal contract  — S5 (the retry/settle budget. `sleep` was stubbed to a bare `exit 0`,
#                        which makes a suite fast and simultaneously blind to the timing
#                        contract it is supposed to hold)
#   fixture direction  — I4/I5 in the verify suite: the equality boundary
#                        (start_ts == APPLY_START_EPOCH) and the ordinary FRESH-frame arm, both
#                        previously uninstantiated. See the note below, which this supersedes.
#   the floor          — G1-7 (the predicate's one passing arm; without it the predicate could be
#                        `return 1` unconditionally and every refusal row would stay green)
#   stay-green control — STAY-GREEN (the only rc=0 row). Without it a suite that has become
#                        impossible to satisfy scores identically to a correct one. It appended a
#                        COMMENT until #7104 PR-B review (F6) — and every scanner in this
#                        directory strips comments as its first act, so the control perturbed
#                        nothing any guard could see and was a duplicate of the mandatory
#                        unmutated baseline. It is a scanner-VISIBLE pure helper now.
#   composite cancellation — D3-BYPASS. Two mutations that each break a guard, applied together
#                        so the guard's scalar comes back to its passing value. This is the one
#                        the panel executed against the previous pass and it reported 132/0.
#   noise policy       — D5/D6/D7 cross the SHAPES the allow-list sweep must see (a trampoline
#                        inside the allow list, a path form, a bare redirection) rather than
#                        varying the wrapper on one shape, which is what let D3 evade 8 ways
#                        while the 12-row control battery scored 12/12.
#   alert dispatch     — A1-A3. Previously unrowed entirely, while P0-B was a mis-dispatch.
#
# AXES THIS BATTERY DOES **NOT** EDIT:
#   demotion — leaving asserted bytes identical and rewording the prose above them so the
#     prescription reads as conditional.
#
#     THIS ENTRY PREVIOUSLY READ "not applicable rather than skipped", on the reasoning that
#     ADR-189 is a decision record rather than an enforced contract. That is contradicted by this
#     PR's own record: a DEMOTION was its top surviving mutant. It is SKIPPED, not inapplicable,
#     and it is skipped because the demotable surfaces here are prose (the ADR's rulings, this
#     header's own claims) with no gate reading them — which is a description of the gap, not a
#     defence of it. Anyone adding a prose-enforcing gate to this chain should add the row.
#
#   `::error::` severity — a verify.sh arm could be demoted from `::error::` to `::warning::`
#     with its exit codes untouched. Nothing here reads annotation severity, so the row would
#     have no detector to name. Stated rather than omitted.
#
#   the ledger's destructive-append guards — the `gh issue view` failure path, the header check
#     and the length check are workflow `run:` bodies with no suite driving them end to end. The
#     alert step's body IS driven (drive_step), and extending that harness to the ledger step is
#     the obvious next move; it is not done here.
#   (fixture direction WAS listed here as "not applicable, there is no second direction to
#     sample". That was wrong and is corrected above: the predicate's input is an ORDERING, so it
#     has three directions — below, equal, and above the baseline — and only the strict ones were
#     ever instantiated. The equality boundary is precisely what distinguishes `-lt` from `-le`,
#     which is the mutation G1-3 applies. Measuring it also surfaced that production's inline
#     freshness comparison decides staleness BEFORE delegating to the predicate, so the
#     predicate's own `-lt` is a redundant second evaluation and the unit matrix's equality arm
#     is unreachable from the shipped call path.)
#   the cf-tunnel-ssh-bridge composite action — the third production-reachable path named in
#     Guard 2's assembly. Pre-existing, unmodified by this PR, and out of scope by decision (see
#     the assembly note in infra-config-gate.test.sh); mutating it would test a guard this PR did
#     not build.
#
# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a battery that builds a
# sandbox per case must not have its verdicts depend on another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

GATE_SUITE=apps/web-platform/infra/infra-config-gate.test.sh
VERIFY_SUITE=apps/web-platform/infra/infra-config-verify.test.sh
# #7104 PR-B review (F3): the alert step's DISPATCH had no row at all — the whole of
# red-alert.sh was on the omission list — while P0-B was a mis-dispatch that told the operator
# three false things on the one failure with no fallback lever. It is a graded suite now.
ALERT_SUITE=scripts/infra-config-red-alert.test.sh

# --- the mutators -------------------------------------------------------------------------------
# Defined before the child-mode dispatch below, because bash resolves a function at call time and
# the child block runs before anything further down the file.
#
# Every mutation asserts its own anchor cardinality and exits 3 on a miss. A mutator that silently
# no-ops reports the BASELINE, which is indistinguishable from "the suite did not detect this".
_mutate_impl() {
  python3 - "$1" "$2" <<'PYEOF'
import os, re, sys

box, case = sys.argv[1], sys.argv[2]
INFRA  = os.path.join(box, 'apps/web-platform/infra')
GATE   = os.path.join(INFRA, 'infra-config-gate.sh')
TEST   = os.path.join(INFRA, 'infra-config-gate.test.sh')
VERIFY = os.path.join(INFRA, 'infra-config-verify.sh')
WF     = os.path.join(box, '.github/workflows/apply-deploy-pipeline-fix.yml')

def die(msg):
    sys.stderr.write('MUTATOR-FAIL[%s]: %s\n' % (case, msg))
    sys.exit(3)

def sub(path, old, new, want=1):
    s = open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != want:
        die('anchor occurs %d time(s) in %s, expected %d -- anchor: %r'
            % (n, os.path.basename(path), want, old[:100]))
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, want))

def sub_in_fn(path, name, old, new, want=1):
    s = open(path, encoding='utf-8').read()
    m = re.search(r'^%s\(\)\s*\{\s*$' % re.escape(name), s, re.M)
    if not m:
        die('no function %s() in %s' % (name, os.path.basename(path)))
    e = re.search(r'^\}\s*$', s[m.end():], re.M)
    if not e:
        die('function %s() is unterminated' % name)
    a, b = m.end(), m.end() + e.start()
    body = s[a:b]
    n = body.count(old)
    if n != want:
        die('anchor occurs %d time(s) inside %s(), expected %d -- anchor: %r'
            % (n, name, want, old[:100]))
    open(path, 'w', encoding='utf-8').write(s[:a] + body.replace(old, new, want) + s[b:])

def delete_block(path, start_literal, end_line='fi'):
    """Delete from the line holding start_literal through the next line equal to end_line."""
    lines = open(path, encoding='utf-8').read().splitlines(keepends=True)
    starts = [i for i, l in enumerate(lines) if start_literal in l]
    if len(starts) != 1:
        die('start anchor occurs %d time(s), expected 1: %r' % (len(starts), start_literal))
    i = starts[0]
    for j in range(i + 1, len(lines)):
        if lines[j].rstrip('\n') == end_line:
            open(path, 'w', encoding='utf-8').writelines(lines[:i] + lines[j + 1:])
            return
    die('no terminating %r line after the start anchor' % end_line)

# ---- Guard 1 — infra_config_should_repush (the re-push decision) -------------------------------
if case == 'G1-1':
    # Row 1 — THE PRIMARY ROW. Drop the dpf-replaced clause so the predicate decides on frame
    # shape alone. Three merge classes replace no DPF and legitimately publish no frame; each
    # would then become a spurious production re-push, which is the defect PR-A shipped to stop.
    sub(GATE, '  [[ "$dpf_replaced" == "true" ]] || return 1',
              '  : # MUTATED G1-1: dpf-replaced clause dropped')

elif case == 'G1-2':
    # Row 2 — relax the polarity guard, so a non-canonical reading (jq's string `null` on a
    # missing key, an address rename, an empty resource_changes[]) stops being discriminated and
    # reads as "no push expected" permanently and silently.
    sub_in_fn(GATE, 'infra_config_should_repush', '^(true|false)$', '^.*$')

elif case == 'G1-3':
    # Row 3 — -lt becomes -le, so a frame published in the same whole second as the baseline
    # re-pushes. Equality is FRESH: that frame was delivered, and re-pushing on it writes
    # production for a run that already succeeded.
    sub_in_fn(GATE, 'infra_config_should_repush',
              '[[ "$start_ts" -lt "$baseline" ]]', '[[ "$start_ts" -le "$baseline" ]]')

elif case == 'G1-4':
    # Row 4 — THE GUARD'S OWN DISPATCH. Rename the predicate, leaving every call site in place.
    # A decision function that is silently absent must never read as "do not re-push" or as
    # success.
    sub(GATE, 'infra_config_should_repush() {', 'infra_config_should_repush_RENAMED() {')

elif case == 'G1-5':
    # Row 5 — add a SECOND member to the success set: an unreadable frame becomes licence to
    # write production, "because we cannot rule the race out". Allow-list semantics are the whole
    # contract, and treating uncertainty as licence inverts the polarity.
    #
    # The verdict is flipped in place rather than by DELETING the numeric guard, and the reason is
    # measured. Deleting it (`if false; then`) lets a non-numeric start_ts reach
    # `[[ "$start_ts" -lt "$baseline" ]]`, where bash's arithmetic context treats `notanumber` as
    # a VARIABLE NAME — so under this suite's `set -u` the guard's absence is a FATAL abort, not a
    # failed assertion. The suite exits 1 having printed no verdict at all, which this battery
    # correctly refuses to score as detection: an abort is equally compatible with a suite that
    # became incapable of passing for an unrelated reason. Flipping the return keeps the mutation
    # on the axis the row is about — the size of the success set.
    sub_in_fn(GATE, 'infra_config_should_repush',
              'is not a stale frame" >&2\n    return 1',
              'is not a stale frame" >&2\n    return 0')

elif case == 'G1-6':
    # Row 6 — VACUITY. Make the fixture builder's default supply the value the case also asserts
    # on. Cases that return the same verdict under two different decision rules measure nothing.
    sub(TEST, '''    printf '{"exit_code":0,"start_ts":%s}\\n' "$2" > "$1"''',
              '''    printf '{"exit_code":0,"start_ts":1000}\\n' > "$1"''')

elif case == 'G1-7':
    # Row 7 — THE FLOOR / positive control. Make the predicate refuse unconditionally. Without a
    # passing row it could be `return 1` always and every refusal row would still be green.
    sub_in_fn(GATE, 'infra_config_should_repush',
              '[[ "$start_ts" -lt "$baseline" ]]', 'return 1')

# ---- Guard 2 — the production call-site pin ----------------------------------------------------
elif case == 'G2-1':
    # Row 1 (pre-existing #6594) — move the content assert INSIDE the poll loop, so it becomes an
    # any-of-N coin flip across fresh connector selections. The pin's original property must
    # still hold after PR-B re-points it across the extraction boundary.
    sub(VERIFY,
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\ndone\n',
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\n'
        '  adjudicate_infra_config "$STATUS_RESPONSE" . infra-config-apply.sh || true\n'
        'done\n')

elif case == 'G2-2':
    # Row 2 — delete the predicate call and inline an equivalent condition. Guard 1's entire
    # matrix would then certify a predicate production does not run.
    sub(VERIFY,
        'if infra_config_should_repush "$STATUS_RESPONSE" "$DPF_REPLACED" "$APPLY_START_EPOCH"; then',
        'if [[ "$DPF_REPLACED" == "true" ]]; then')

elif case == 'G2-3':
    # Row 3 — BOUNDEDNESS, as re-derived by plan R22.6. The latch this row originally named was
    # pruned with the inline design; the replacement property is "exactly one step in the job
    # invokes terraform apply against tfplan-repush". Add a SECOND production apply.
    sub(WF,
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n',
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n'
        '          terraform apply -no-color -input=false -lock-timeout=120s tfplan-repush || rc=$?\n')

elif case == 'G2-4':
    # Row 6 (the one R22.6 keeps from R18.2) — wrap the predicate call in a function. Bash
    # suspends errexit for a CONDITION context and the suspension propagates into the function
    # body, so a production terraform apply downstream of it would run with -e off.
    sub(VERIFY,
        '      if infra_config_should_repush "$STATUS_RESPONSE" "$DPF_REPLACED" "$APPLY_START_EPOCH"; then',
        '      repush_once() { infra_config_should_repush "$@"; }\n'
        '      if repush_once "$STATUS_RESPONSE" "$DPF_REPLACED" "$APPLY_START_EPOCH"; then')

elif case == 'G2-5':
    # Row 5 — REGION BOUNDARY. Add a nested loop between the pinned anchors. The pin's original
    # first-match `awk '... $1=="done" {print NR; exit}'` scan was structurally blind to this;
    # only the counting pass added by task 8.1 can see it.
    #
    # The loop is written across THREE LINES on purpose, and the first attempt at this row is why:
    # a one-liner `for _mutant in 1; do :; done` leaves `$1` equal to `for`, so it adds no
    # `$1=="done"` line and does not perturb the axis the guard counts at all. It landed (the
    # diff-vs-pristine check passed) and the suite stayed green — a mutation that measures nothing
    # while looking like a survivor. `done` has to be the first FIELD of its own line, which is
    # exactly the shape the pin quantifies over.
    sub(VERIFY,
        '# --- Final adjudication (fail loud; no silent pass) ---',
        'for _mutant in 1; do\n  :\ndone\n'
        '# --- Final adjudication (fail loud; no silent pass) ---')

elif case == 'G2-6':
    # Row 6' (R20.7 §1) — the SOURCED library is production-reachable and invisible to every grep
    # over the workflow, and it is the file this PR adds a function to. Add a command-position
    # production write to it.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_write() {\n  terraform apply -auto-approve\n}\n')

elif case == 'G2-7':
    # Row 7 — ASSERTION COUNT. Delete the pinned block itself. The GATE_MIN_ASSERTIONS floor is
    # the only thing that makes a silent truncation loud rather than clean-looking.
    delete_block(TEST, 'if [[ ! -f "$APPLY_WF" ]]; then')

# ---- dispatch, authority and stub-fidelity rows ------------------------------------------------
elif case == 'D1':
    # THE HARNESS'S OWN DISPATCH. Neuter fail(). Measured BEFORE task 8.1's correction: this
    # reported `127 passed, 0 failed`, exit 0, with the known-negative self-test GREEN, because
    # that self-test redefined fail() inside its own subshell and so could not observe the real
    # one being neutered.
    sub(TEST, 'fail() { echo "  FAIL: $1"; fail=$((fail + 1)); }', 'fail() { :; }')

elif case == 'D2':
    # AUTHORITY / ROOT INPUT. The workflow's `if:` literals are validated against what
    # infra-config-verify.sh can EMIT, so the emitter is the guard's root input. Delete the output
    # the whole re-push chain is keyed on: every downstream step then silently skips and the job
    # greens having verified nothing — #6594's latched false-green, reintroduced by its remedy.
    sub(VERIFY, '        echo "repush_needed=true" >> "$GITHUB_OUTPUT"\n', '')

elif case == 'S1':
    # HARNESS STUBBING. Corrupt the production curl invocation's URL. A PATH stub that answers
    # identically regardless of argv puts the test seam ABOVE the code under test, and the query
    # shape then ships unpinned.
    sub(VERIFY, '"https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status"',
                '"https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-STATUS-TYPO"')

elif case == 'S2':
    # STUB ARGV — THE HOST, not the path.
    #
    # `deploy.attacker.test`, NOT `elsewhere.example` (#7104 PR-B review, F5). The old target
    # failed the stub's own `https://deploy.*/hooks/infra-config-status` glob, so the stub
    # `exit 64`d and the body's `|| echo "000"` turned it into a generic transport failure —
    # which reds `#7104 I1 pass 1:`, the SAME marker S1 and S3 land on. Three rows, one
    # detector, and the row's stated subject (the HOST) was never the thing measured.
    #
    # `deploy.attacker.test` SATISFIES the stub's glob and fails only I6d's exact-host
    # assertion, so this row now isolates the property it names. Measured.
    sub(VERIFY, '"https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status"',
                '"https://deploy.attacker.test/hooks/infra-config-status"')

elif case == 'S3':
    # STUB ARGV — THE HMAC VALUE. The header was pinned by PRESENCE only (`X-Signature-256:*`),
    # so an empty or malformed signature passed. In production that request 401s and the gate
    # reports a transport failure it cannot explain.
    sub(VERIFY, 'X-Signature-256: sha256=${HMAC}', 'X-Signature-256: sha256=')

elif case == 'S4':
    # STUB ARGV — THE SECRET NAME.
    #
    # Swapped to `CF_ACCESS_CLIENT_SECRET`, an ALLOW-LISTED name, not a typo (#7104 PR-B review,
    # F5). A typo'd name makes the doppler stub `exit 64`, which collapses into the same generic
    # transport failure S1/S2/S3 all produced — so the row proved the stub rejects unknown names,
    # not that the body reads the RIGHT one. An allow-listed substitute passes the stub and fails
    # only I6c, which is the assertion that actually names this property. Measured.
    #
    # It is also the more realistic mutation: signing with a real-but-wrong secret is what a
    # copy-paste from the sibling CF_ACCESS lookups four lines above would produce, and it 401s
    # in production while every presence-only check stays green.
    sub(VERIFY, 'doppler secrets get WEBHOOK_DEPLOY_SECRET --plain',
                'doppler secrets get CF_ACCESS_CLIENT_SECRET --plain')

elif case == 'S5':
    # RETRY / SLEEP CARDINALITY. `sleep` was stubbed to a bare `exit 0`, so the documented 8 s
    # settle preamble — which exists because the async handler takes ~5-8 s, and without it
    # attempt 1 is always wasted — could be deleted or retimed with no case able to see it.
    sub(VERIFY, 'sleep 8', 'sleep 0')

elif case == 'STAY-GREEN':
    # THE STAY-GREEN CONTROL, and the only row that expects rc=0.
    #
    # Every other row asserts that a mutation drives the suite RED. A battery composed entirely
    # of must-trip rows cannot distinguish "these guards detect the right things" from "these
    # guards have become impossible to satisfy" — a suite that reds on everything scores 17/17
    # exactly like a correct one. This row perturbs the tree in a way that is genuinely
    # IRRELEVANT to every guarded property and requires the suite to stay GREEN. It is the far
    # side of the transform, in the fixture-direction sense.
    #
    # IT MUST BE VISIBLE TO THE SCANNERS (#7104 PR-B review, F6). This appended a COMMENT, and
    # every scanner in this directory strips comments as its first act — so the row perturbed
    # nothing any guard could see, which makes it a duplicate of the mandatory unmutated baseline
    # rather than a control. A control that cannot reach the thing it controls for measures the
    # harness twice and the property zero times.
    #
    # A pure helper function is visible to all three: it is real code, it changes the file's
    # token stream and line count, and the allow-list sweep reads its command-position tokens.
    # `printf` is a builtin and `local` is allow-listed, so nothing here may legitimately trip —
    # which is exactly the claim being controlled for.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_noop() {\n'
                 '  local x="${1:-}"\n'
                 '  printf \'%s\' "$x"\n'
                 '}\n')

# ---- #7104 P0-A: the pass-2 absolute freshness pin ---------------------------------------------
elif case == 'FR1':
    # THE P0 ITSELF. Delete the absolute pin, leaving pass 2's only assertion RELATIVE. Any
    # unrelated frame advance — a queued handler invocation, a concurrent trigger, a host clock
    # step — then certifies the recovery while the frame still predates this apply.
    sub(VERIFY,
        '      if [[ "$FRAME_START_TS" -lt $((FRESHNESS_REF_EPOCH - INFRA_CONFIG_CLOCK_SKEW_S)) ]]; then',
        '      if false; then')

elif case == 'FR2':
    # THE PIN WITHOUT ITS TOLERANCE — the naive AND the finding warns against. Both operands of
    # the RELATIVE check are host-clock so skew cancels; this one crosses clocks, so removing the
    # allowance red-lines a real delivery on a host whose clock lags the runner.
    sub(VERIFY, '$((FRESHNESS_REF_EPOCH - INFRA_CONFIG_CLOCK_SKEW_S))', '"$FRESHNESS_REF_EPOCH"')

elif case == 'FR3':
    # THE ADVANCE UNBOUNDED. Ignore the re-push's own start stamp and bound only by the ORIGINAL
    # apply, so a frame published moments after that apply began — which the re-push cannot have
    # produced — reads as VERIFIED.
    sub(VERIFY,
        'if [[ "${REPUSH_START_EPOCH:-}" =~ ^[0-9]+$ ]] && [[ "$REPUSH_START_EPOCH" -ge "$APPLY_START_EPOCH" ]]; then',
        'if false; then')

elif case == 'FR4':
    # THE TWO DIAGNOSES COLLAPSED. Verdict unchanged, lever lost: "the frame moved but still
    # predates this apply" and "the frame did not move" send the operator to different places.
    sub(VERIFY, '::error::STALE FRAME AFTER RE-PUSH:', '::error::RE-PUSH DID NOT DELIVER:')

# ---- #7104 D1/D2/D3: the three fixes the panel defeated ----------------------------------------
elif case == 'D3-BYPASS':
    # D1, EXECUTED — and it is a COMPOSITE, which is the whole point. Neither half is detected
    # alone by the pre-fix guards, and together they cancel:
    #
    #   * the content assert MOVES INTO the poll loop, restoring #6594's any-of-3 coin flip
    #     across fresh connector selections (this is G2-1's move);
    #   * `for _n in 1; do :; done` puts a `done` back between the two anchors, so the
    #     done_count == 1 scalar comes back to 1;
    #   * `[[ $PHASE == done ]]` decrements the loop depth at the assert to 0 and
    #     `[[ $PHASE == do ]]` rebalances the file, so the depth check and the balance check
    #     both pass.
    #
    # Measured before the shared strip_noise stripped `[[ ]]` spans: gate 132/0, verify 29/0,
    # rc=0, printing the reassuring `maxdepth=2 ADJ=0 CI=1 — terminal-ness is structural`.
    #
    # A FIRST ATTEMPT AT THIS ROW ADDED ONLY THE PHANTOMS, without moving the assert. It landed,
    # and it was correctly NOT detected — balanced phantoms around an assert that is genuinely
    # terminal perturb nothing. Recorded because the survivor looked like a guard failure and
    # was a fixture failure, which is the distinction this battery exists to keep.
    sub(VERIFY,
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\ndone\n',
        '  if [[ "$attempt" -lt 3 ]]; then\n    sleep 5\n  fi\n'
        '  for _n in 1; do :; done\n'
        '  [[ $PHASE == done ]] || :\n'
        '  adjudicate_infra_config "$STATUS_RESPONSE" . infra-config-apply.sh && break\n'
        '  [[ $PHASE == do ]] || :\n'
        'done\n')
    sub(VERIFY,
        '  if ! adjudicate_infra_config "$STATUS_RESPONSE" . infra-config-apply.sh; then\n'
        '    cat "$STATUS_RESPONSE" >&2 2>/dev/null || true\n'
        '    exit 1\n'
        '  fi\n',
        '')

elif case == 'D4-TALLY':
    # D2, EXECUTED. One edit moves the counter AND the PASS log, because both lived in the same
    # one-line pass(). Measured at 264 passed, 0 failed, OK, rc=0, floor cleared, 66 real
    # assertions deletable. The suite's captured STDOUT is the producer this cannot reach.
    sub(TEST,
        'pass() { echo "  PASS: $1"; printf \'PASS\\n\' >> "$PASSLOG"; pass=$((pass + 1)); }',
        'pass() { echo "  PASS: $1"; printf \'PASS\\nPASS\\n\' >> "$PASSLOG"; pass=$((pass + 2)); }')

elif case == 'D5-AWK-TRAMPOLINE':
    # D3, the sharpest class: `awk` is ON the allow list as a pure text transform, and it has
    # system(). strip_noise blanks quoted spans, so the program body was invisible BY
    # CONSTRUCTION — the sweep had deleted the evidence before looking for it.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_awk() {\n'
                 '  awk \'BEGIN{system("terraform apply -auto-approve")}\'\n'
                 '}\n')

elif case == 'D6-PATH-FORM':
    # D3: the token regex required a leading [A-Za-z_], so an absolute path captured NO TOKEN AT
    # ALL — no token, no hit, silence that reads as approval.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_path() {\n'
                 '  /usr/bin/terraform apply -auto-approve\n'
                 '}\n')

elif case == 'D7-REDIRECT-WRITE':
    # D3: a write that invokes no command at all, so no command-position allow list can see it.
    with open(GATE, 'a', encoding='utf-8') as fh:
        fh.write('\n_infra_config_mutant_redir() {\n'
                 '  echo pwned > /etc/default/soleur-doppler-token\n'
                 '}\n')

# ---- #7104 P0-B: alert-step dispatch, which had NO row at all ----------------------------------
elif case == 'A1-LIVENESS-ID':
    # P0-B's root cause. Remove the probe's `id:` and its outcome becomes unreadable, so a
    # re-push that BRICKED the sole no-SSH channel falls through every arm to the gate-never-ran
    # catch-all — which tells the operator the gate never ran on a run whose gate ran, graded,
    # deferred and re-pushed.
    sub(WF, '        id: webhook_liveness\n', '')

elif case == 'A2-GATE-NEVER-RAN-WIDE':
    # The catch-all predicate, restored to `!= failure`. Since PR-B pass 1 SOFT-FAILS with exit
    # 0, so `success` is the outcome on every recovery path and this arm swallows all of them.
    sub(WF,
        'if [[ -z "${GATE_OUTCOME:-}" || "${GATE_OUTCOME:-}" == "skipped" ]]; then',
        'if [[ "${GATE_OUTCOME:-}" != "failure" ]]; then')

elif case == 'A3-REPUSH-FAILED-MODE':
    # The fifth reach mode, reverted to reusing `reachable` — whose body opens "the files
    # themselves reached the server", false on the plan-failure path where nothing was written.
    sub(WF, '${LEVER}" "repush_failed" || true', '${LEVER}" "reachable" || true')

# ---- #7104 F3: guards the omission list named as UNROWED ---------------------------------------
elif case == 'C1-CARDINALITY-LITERAL':
    # GUARD 3 / CARDINALITY PIN — the m18 fix itself, previously unrowed. Widening the apply's
    # keyed literal re-opens the transitive -target blast radius task 4.0 measured shut.
    sub(WF, "        if: steps.repush_plan.outputs.repush_graded == '1'\n",
            "        if: steps.repush_plan.outputs.repush_graded == '2'\n")

elif case == 'C2-ADDRESS-SET':
    # The address-set assert. `GRADED == 1` says one managed resource changes, never WHICH — a
    # plan replacing one entirely different production resource satisfies cardinality alone.
    sub(WF, 'if [[ "$addrs" != "terraform_data.deploy_pipeline_fix" ]]; then',
            'if false; then')

elif case == 'C3-CLEARTEXT-TRAP':
    # The trap that reclaims tfplan-repush.json, which carries the live prd Doppler token and
    # the webhook HMAC in CLEARTEXT — terraform's JSON serialization ignores `sensitive`.
    sub(WF, "          trap 'rm -f tfplan-repush.json' EXIT\n", "")

elif case == 'C4-AC18-ERROR-TOLERANCE':
    # AC18's forbidden key. `continue-on-error: true` pins a step's `conclusion` to success while
    # leaving `outcome` real, and scripts/followthroughs/moved-block-wedge-5887.sh reads
    # `conclusion` — so it would feed that follow-through GREEN over a red.
    sub(WF, '        id: repush_apply\n',
            '        id: repush_apply\n        continue-on-error: true\n')

# ---- #7104 F7: the SIBLING suites' tallies, previously unprotected and unrowed -----------------
elif case == 'F7-VERIFY-TALLY':
    VTEST = os.path.join(INFRA, 'infra-config-verify.test.sh')
    sub(VTEST, '  PASS=$((PASS + 1))\n}', '  PASS=$((PASS + 2))\n}')

elif case == 'F7-ALERT-TALLY':
    ATEST = os.path.join(box, 'scripts/infra-config-red-alert.test.sh')
    sub(ATEST, 'ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }',
               'ok()   { echo "  PASS: $1"; PASS=$((PASS + 2)); }')

else:
    die('unknown case id')
PYEOF
}

# --- child mode (one row) ----------------------------------------------------------------------
# Rows are independent by construction — each gets its own sandbox copy — so they run
# concurrently. The gate suite alone is ~13 s, and 16 sequential rows would put this battery at
# ~4 min on the merge-gate critical path. Self-invocation keeps the mutator definitions
# single-sourced rather than duplicating them into a helper script.
#
# The child writes ONE result line to a file and never prints to stdout, so the parent renders
# rows in matrix order rather than completion order. Interleaved output from a parallel fan-out is
# how a battery's verdict becomes unreadable at exactly the moment it matters.
if [[ "${1:-}" == "--row" ]]; then
  _id="$2"; _suite="$3"; _want_rc="$4"; _marker="$5"; _result="$6"; _pristine="$7"

  # OWNING TRAP, REGISTERED BEFORE THE ALLOCATION IT RECLAIMS, AND WIDENED TO INT TERM HUP
  # (#7104 PR-B review). The child used bare `rm -rf` at each exit path and no trap at all, so a
  # killed run — which is routine here: this battery runs under a parent fan-out on a machine
  # with sibling worktrees, and long runs get reaped — leaked one sandbox copy of the infra tree
  # per row. Measured: 12 entries left behind by one interrupted run. /tmp is a machine-global
  # 4 GiB tmpfs, so the leak is other sessions' problem too.
  _CHILD_TMPS=()
  _child_cleanup() { [[ ${#_CHILD_TMPS[@]} -gt 0 ]] && rm -rf "${_CHILD_TMPS[@]}"; return 0; }
  trap _child_cleanup EXIT INT TERM HUP

  _box="$(mktemp -d -t "repushmut-$_id.XXXXXXXX")" || {
    printf 'SETUPFAIL|%s|0|mktemp box\n' "$_id" > "$_result"; exit 0; }
  _CHILD_TMPS+=("$_box")
  cp -a "$_pristine/." "$_box/" || {
    printf 'SETUPFAIL|%s|0|cp box\n' "$_id" > "$_result"; exit 0; }

  if ! _muterr="$(_mutate_impl "$_box" "$_id" 2>&1)"; then
    printf 'SETUPFAIL|%s|0|mutator did not apply: %s\n' "$_id" "${_muterr//|/ }" > "$_result"
    exit 0
  fi

  # Prove the mutation LANDED, against the PRISTINE copy — never against git HEAD, which is
  # legitimately dirty mid-PR. A mutation that did not land reports the baseline, and a baseline
  # result is indistinguishable from "the suite did not detect this".
  if diff -rq "$_pristine" "$_box" >/dev/null 2>&1; then
    printf 'SETUPFAIL|%s|0|mutation changed nothing (the mutator is a no-op)\n' "$_id" > "$_result"
    exit 0
  fi

  _log="$(mktemp -t "repushmut-$_id.XXXXXXXX.log")" || {
    printf 'SETUPFAIL|%s|0|mktemp log\n' "$_id" > "$_result"; exit 0; }
  _CHILD_TMPS+=("$_log")
  bash "$_box/$_suite" > "$_log" 2>&1; _rc=$?

  # Assert the EXPECTED rc, not merely non-zero, AND that a check NAMING the property reported.
  # "Some assertion failed" is not detection: it is equally compatible with a suite that has
  # become incapable of passing for an unrelated reason.
  #
  # THE MARKER IS MATCHED ONLY ON FAIL LINES (#7104 PR-B review), AND THAT IS THE WHOLE POINT.
  #
  # This used to be a bare `grep -qF -- "$_marker" "$_log"` over the entire log. Every marker is
  # the leading text of an assertion's message, and `pass()` and `fail()` print the SAME message
  # under different prefixes — so a marker matched the log of a suite in which that assertion had
  # PASSED. Measured against a green baseline: 11 of the 17 markers were present, which means 11
  # rows had silently degenerated to `rc == 1` and were scoring "some assertion, somewhere,
  # failed" as detection of the specific property they name.
  #
  # Filtered through a variable rather than `grep '^  FAIL:' "$_log" | grep -qF ...`: under this
  # file's `set -o pipefail`, `grep -q` closes the pipe on its first match and the producer takes
  # SIGPIPE (141), which pipefail then promotes — so the pipeline can report FAILURE on a
  # successful early match. A herestring has no pipe and cannot flake that way.
  #
  # `-F` throughout: markers legitimately contain regex metacharacters (`#7104 Guard 2 (5):`).
  _why=""
  [[ "$_rc" == "$_want_rc" ]] || _why="rc=$_rc want=$_want_rc"
  # The `      - ` lines are the PROBLEM details a failing multi-part guard prints beneath its
  # `  FAIL:` header (`sed -n 's/^PROBLEM=/      - /p' >&2`). They are emitted ONLY from a fail
  # branch, so including them cannot match a passing assertion — and excluding them forced every
  # row targeting a sub-check of a composite guard to share that guard's single header marker,
  # which is the "N rows, one detector" shape F5 flags. A row can now name the specific problem
  # it causes rather than the block that reports it.
  _faillines="$(grep -E '^  FAIL:|^      - ' "$_log" || true)"
  if [[ -z "$_why" ]] && [[ "$_want_rc" != "0" ]] && ! grep -qF -- "$_marker" <<<"$_faillines"; then
    _why="rc ok but NO FAILING check named the property (the marker appears only on passing lines, if at all)"
  fi
  # A stay-green row asserts the inverse: the suite must pass AND the named property must not be
  # reported as failing by anything.
  if [[ -z "$_why" ]] && [[ "$_want_rc" == "0" ]] && grep -qF -- "$_marker" <<<"$_faillines"; then
    _why="suite passed overall but '$_marker' was reported as FAILING"
  fi
  if [[ -n "$_why" ]]; then
    printf 'NOTASEXPECTED|%s|%s|%s\n' "$_id" "$_rc" "$_why" > "$_result"
    grep -E '^  FAIL|FLOOR|self-test' "$_log" | head -3 | sed 's/^/          /' >> "$_result"
  else
    printf 'RED|%s|%s|\n' "$_id" "$_rc" > "$_result"
  fi
  exit 0
fi

# ================================================================================================
# parent mode
# ================================================================================================
echo "infra-config-repush-mutation.test.sh (#7104 PR-B — Guard 1 + Guard 2)"

for tool in python3 jq git diff; do
  command -v "$tool" >/dev/null || { echo "SETUP-FAIL: $tool not on PATH" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "SETUP-FAIL: python3 pyyaml unavailable" >&2; exit 2; }

# --- the minimal skeleton the two suites read ---------------------------------------------------
# Both resolve REPO_ROOT as SCRIPT_DIR/../../.., so the sandbox must reproduce that shape.
# Copying the top-level TRACKED files only: apps/web-platform/infra also holds an untracked
# .terraform provider cache (~168 MB), and `cp -a` of the whole directory would put that on the
# critical path of every row.
# OWNING TRAP FIRST, THEN THE ALLOCATIONS (#7104 PR-B review). The trap used to be registered
# AFTER BOTH mktemp -d calls, so a failure or a signal between the two leaked $PRISTINE — which
# is a full copy of the infra tree — with nothing owning it. Registered before the first
# allocation, appending as each succeeds, and widened from bare EXIT to EXIT INT TERM HUP so a
# reaped or interrupted run reclaims too.
_PARENT_TMPS=()
_parent_cleanup() { [[ ${#_PARENT_TMPS[@]} -gt 0 ]] && rm -rf "${_PARENT_TMPS[@]}"; return 0; }
trap _parent_cleanup EXIT INT TERM HUP

PRISTINE="$(mktemp -d -t repushmut-pristine.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp pristine" >&2; exit 2; }
_PARENT_TMPS+=("$PRISTINE")
RESULTS="$(mktemp -d -t repushmut-results.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp results" >&2; exit 2; }
_PARENT_TMPS+=("$RESULTS")
mkdir -p "$PRISTINE/apps/web-platform/infra" "$PRISTINE/.github/workflows" \
  || { echo "SETUP-FAIL: mkdir skeleton" >&2; exit 2; }

EXPECTED_FILES="$(git -C "$REPO_ROOT" ls-files apps/web-platform/infra | awk -F/ 'NF==4' | wc -l)"
copied=0
while IFS= read -r rel; do
  cp "$REPO_ROOT/$rel" "$PRISTINE/apps/web-platform/infra/" || { echo "SETUP-FAIL: cp $rel" >&2; exit 2; }
  copied=$((copied + 1))
done < <(git -C "$REPO_ROOT" ls-files apps/web-platform/infra | awk -F/ 'NF==4')
# Cardinality check on the SETUP itself: an empty or truncated skeleton would make every row below
# a statement about a directory that does not contain the code under test.
#
# DERIVED, NOT A FLOOR OF 50 (#7104 PR-B review). The measured population is 268, so `>= 50` left
# 218 files that could vanish with the check still clean — slack four times larger than the
# quantity guarded. A flush literal was the other option and was rejected: this directory gains
# files routinely (the rebase for this very PR added one), so a hardcoded 268 would red this
# battery for unrelated sibling PRs, which is how a guard gets weakened by the person it
# inconveniences. Comparing the copy count against the enumeration it iterates is exact, needs no
# maintenance, and catches the real failure — a `cp` loop that stopped partway.
[[ "$copied" -eq "$EXPECTED_FILES" ]] || {
  echo "SETUP-FAIL: copied $copied infra files but git ls-files enumerated $EXPECTED_FILES — the skeleton is truncated" >&2; exit 2; }
# ...and the enumeration itself must not be empty, which is the one thing the comparison above
# cannot see (0 == 0 passes).
[[ "$copied" -ge 50 ]] || { echo "SETUP-FAIL: enumerated only $copied infra files (expected >= 50) — git ls-files returned nothing usable, so every row below would grade an empty directory" >&2; exit 2; }

# IDENTITY, NOT ONLY CARDINALITY. A count cannot tell you the files under test are present.
for _need in infra-config-gate.sh infra-config-gate.test.sh infra-config-verify.sh \
             infra-config-verify.test.sh infra-config-apply.sh; do
  [[ -s "$PRISTINE/apps/web-platform/infra/$_need" ]] || {
    echo "SETUP-FAIL: the skeleton is missing $_need — every row below would grade a tree that does not contain the code under test" >&2; exit 2; }
done

for wf in infra-validation.yml apply-deploy-pipeline-fix.yml; do
  cp "$REPO_ROOT/.github/workflows/$wf" "$PRISTINE/.github/workflows/" \
    || { echo "SETUP-FAIL: cp $wf" >&2; exit 2; }
done

# The alert suite and the emitter it grades. Both resolve relative to scripts/, and the suite
# reaches ../.github/workflows/ for the caller/callee lockstep — which the skeleton above
# already reproduces.
mkdir -p "$PRISTINE/scripts" || { echo "SETUP-FAIL: mkdir scripts" >&2; exit 2; }
for s in infra-config-red-alert.sh infra-config-red-alert.test.sh; do
  cp "$REPO_ROOT/scripts/$s" "$PRISTINE/scripts/" || { echo "SETUP-FAIL: cp $s" >&2; exit 2; }
  [[ -s "$PRISTINE/scripts/$s" ]] || { echo "SETUP-FAIL: $s is empty in the skeleton" >&2; exit 2; }
done

# --- the UNMUTATED control ----------------------------------------------------------------------
# A red baseline voids every row below: each would then be reporting the baseline's failure and
# calling it detection. Run it first, on the pristine skeleton, for BOTH suites.
for suite in "$GATE_SUITE" "$VERIFY_SUITE" "$ALERT_SUITE"; do
  log="$(mktemp -t repushmut-base.XXXXXXXX.log)" || { echo "SETUP-FAIL: mktemp base log" >&2; exit 2; }
  bash "$PRISTINE/$suite" > "$log" 2>&1; base_rc=$?
  if [[ "$base_rc" -ne 0 ]]; then
    echo "SETUP-FAIL: baseline for $(basename "$suite") is NOT green (rc=$base_rc) — every mutation verdict below would be meaningless" >&2
    grep -E 'FAIL' "$log" >&2
    rm -f "$log"; exit 2
  fi
  echo "  baseline $(basename "$suite"): GREEN (rc=0) — $(grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1)"
  rm -f "$log"
done
echo

# --- the matrix ---------------------------------------------------------------------------------
# id | suite | expected-rc | marker the failing check must print | description
ROWS=(
  "G1-1|$GATE_SUITE|1|#7104 P1:|G1 r1 dpf-replaced clause dropped (primary)"
  "G1-2|$GATE_SUITE|1|#7104 P2b:|G1 r2 polarity guard relaxed off ^(true|false)"
  "G1-3|$GATE_SUITE|1|#7104 P4:|G1 r3 freshness -lt -> -le (equality re-pushes)"
  "G1-4|$GATE_SUITE|1|the predicate is not defined|G1 r4 predicate renamed (OWN DISPATCH)"
  "G1-5|$GATE_SUITE|1|#7104 P5:|G1 r5 second success member: unreadable frame"
  "G1-6|$GATE_SUITE|1|#7104 P0 (builder fidelity):|G1 r6 builder default supplies asserted value"
  "G1-7|$GATE_SUITE|1|#7104 P3:|G1 r7 predicate refuses always (FLOOR)"
  "G2-1|$GATE_SUITE|1|is not terminal|G2 r1 content assert moved INSIDE the poll loop"
  "G2-2|$GATE_SUITE|1|#7104 Guard 2 (5):|G2 r2 predicate decision inlined in the script"
  "G2-3|$GATE_SUITE|1|#7104 Guard 2 (7):|G2 r3 a SECOND production apply site added"
  "G2-4|$GATE_SUITE|1|#7104 Guard 2 (6):|G2 r6 predicate call wrapped in a function"
  "G2-5|$GATE_SUITE|1|done-lines-strictly-between=2|G2 r5 nested done inside the pinned region"
  "G2-6|$GATE_SUITE|1|#7104 Guard 2 (8):|G2 r6' write added to the sourced library"
  "G2-7|$GATE_SUITE|1|assertion-count floor|G2 r7 the pin block itself deleted"
  "D1|$GATE_SUITE|1|harness self-test|harness fail() neutered (OWN DISPATCH)"
  "D2|$GATE_SUITE|1|#7104 WORKFLOW-REF PIN:|repush_needed output never written"
  "S1|$VERIFY_SUITE|1|#7104 I1 pass 1:|production status URL path corrupted (stub argv)"
  "S2|$VERIFY_SUITE|1|#7104 I6d:|stub argv: the status HOST repointed elsewhere"
  "S3|$VERIFY_SUITE|1|#7104 I1 pass 1:|stub argv: the HMAC signature VALUE emptied"
  "S4|$VERIFY_SUITE|1|#7104 I6c:|stub argv: the signing SECRET NAME changed"
  "S5|$VERIFY_SUITE|1|#7104 I6a:|retry cardinality: the 8s settle preamble retimed to 0"
  # ---- #7104 P0-A: the pass-2 absolute freshness pin (4 rows, 4 distinct detectors) ----
  "FR1|$VERIFY_SUITE|1|#7104 I7a:|P0-A: the absolute freshness pin deleted from pass 2"
  "FR2|$VERIFY_SUITE|1|#7104 I7b:|P0-A: the pin without its cross-clock skew allowance"
  "FR3|$VERIFY_SUITE|1|#7104 I7c:|P0-A: the advance unbounded by the re-push's own start"
  "FR4|$VERIFY_SUITE|1|#7104 I7a-diag:|P0-A: the two diagnoses collapsed into one message"
  # ---- #7104 D1/D2/D3: the three fixes the panel DEFEATED, each re-applied here ----
  "D3-BYPASS|$GATE_SUITE|1|loop-structure check failed|D1: the [[ ]] phantom-line loop-depth bypass"
  "D4-TALLY|$GATE_SUITE|1|assertion-count reconciliation (stdout)|D2: pass() inflates counter AND log together"
  "D5-AWK-TRAMPOLINE|$GATE_SUITE|1|awk-exec|D3: awk system() — a trampoline ON the allow list"
  "D6-PATH-FORM|$GATE_SUITE|1|/usr/bin/terraform|D3: an absolute path captured no token at all"
  "D7-REDIRECT-WRITE|$GATE_SUITE|1|redirect-literal-path|D3: a write that invokes no command"
  # ---- #7104 P0-B: alert-step dispatch, previously unrowed entirely ----
  "A1-LIVENESS-ID|$ALERT_SUITE|1|liveness probe has no id|P0-B: the probe's outcome made unreadable"
  "A2-GATE-NEVER-RAN-WIDE|$ALERT_SUITE|1|the residue arm claims the gate never ran|P0-B: catch-all predicate re-widened"
  "A3-REPUSH-FAILED-MODE|$ALERT_SUITE|1|#7104 alert honesty: a failed re-push|P0-B: fifth mode reverted to reachable"
  # ---- #7104 F3: guards the previous omission list named as unrowed ----
  "C1-CARDINALITY-LITERAL|$GATE_SUITE|1|#7104 CARDINALITY PIN:|Guard 3: the apply's keyed literal widened"
  "C2-ADDRESS-SET|$GATE_SUITE|1|CHANGING ADDRESS SET|the address-set assert neutered"
  "C3-CLEARTEXT-TRAP|$GATE_SUITE|1|no longer traps|the cleartext-credential trap removed"
  "C4-AC18-ERROR-TOLERANCE|$GATE_SUITE|1|#7104 AC18|AC18: continue-on-error added to the apply"
  "F7-VERIFY-TALLY|$VERIFY_SUITE|1|assertion-count reconciliation (stdout)|F7: the verify suite's tally inflated"
  "F7-ALERT-TALLY|$ALERT_SUITE|1|assertion-count reconciliation (stdout)|F7: the alert suite's tally inflated"
  "STAY-GREEN|$GATE_SUITE|0|#7104|a scanner-VISIBLE but irrelevant helper must NOT red the suite (control)"
)

# Bounded fan-out. Rows are hermetic, but this machine runs parallel worktrees and the suites
# each build their own mktemp sandboxes, so the cap stays well under the core count.
JOBS=$(( $(nproc 2>/dev/null || echo 4) - 2 ))
[[ "$JOBS" -gt 4 ]] && JOBS=4
[[ "$JOBS" -lt 1 ]] && JOBS=1
echo "running ${#ROWS[@]} rows, ${JOBS} at a time (fresh sandbox copy each; expected rc AND the named check are both asserted):"

for row in "${ROWS[@]}"; do
  IFS='|' read -r id suite want marker _desc <<< "$row"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$suite" "$want" "$marker" "$RESULTS/$id" "$PRISTINE"
done | xargs -P "$JOBS" -d '\n' -I{} bash -c 'IFS=$'"'"'\t'"'"' read -r a b c d e f <<< "{}"; bash "$0" --row "$a" "$b" "$c" "$d" "$e" "$f"' "${BASH_SOURCE[0]}"

RED=0; NOTASEXPECTED=0; N=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r id _suite _want marker desc <<< "$row"
  N=$((N + 1))
  rf="$RESULTS/$id"
  if [[ ! -s "$rf" ]]; then
    echo "SETUP-FAIL: row $id produced no result file — the child never completed" >&2
    exit 2
  fi
  IFS='|' read -r status _rid rc why < <(head -1 "$rf")
  case "$status" in
    SETUPFAIL)
      echo "SETUP-FAIL: row $id — $why" >&2
      exit 2 ;;
    RED)
      RED=$((RED + 1))
      if [[ "$_want" == "0" ]]; then
        printf '  %-10s %-52s GREEN rc=%-2s (control: must NOT trip)\n' "$id" "$desc" "$rc"
      else
        printf '  %-10s %-52s RED   rc=%-2s [%s]\n' "$id" "$desc" "$rc" "$marker"
      fi ;;
    *)
      NOTASEXPECTED=$((NOTASEXPECTED + 1))
      printf '  %-10s %-52s NOT-AS-EXPECTED (%s)\n' "$id" "$desc" "$why"
      tail -n +2 "$rf" ;;
  esac
done

echo
echo "---"
echo "infra-config-repush-mutation.test.sh: $RED/$N rows behaved as expected, $NOTASEXPECTED did not"
# Cardinality floor: a battery that silently ran zero rows would otherwise print 0/0 and exit 0.
if [[ "$N" -lt 40 ]]; then
  echo "  FAIL: only $N rows ran, expected >= 40 (7 Guard 1 + 7 Guard 2 + 2 dispatch/authority + 5 stub-argv/cardinality + 4 P0-A freshness + 5 D1/D2/D3 + 3 alert dispatch + 4 previously-unrowed guards + 2 sibling-suite tallies + 1 stay-green control)" >&2
  exit 1
fi
# The stay-green control must actually be present, not merely counted. A battery of
# must-trip rows cannot distinguish working guards from guards that red on everything.
if ! printf '%s\n' "${ROWS[@]}" | grep -q '^STAY-GREEN|'; then
  echo "  FAIL: the stay-green control row is absent — with every row expecting rc=1, a suite that has become impossible to satisfy scores a perfect result" >&2
  exit 1
fi
[[ "$NOTASEXPECTED" -eq 0 ]] || exit 1
echo "OK"
