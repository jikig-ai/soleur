# shellcheck shell=bash
# Birth-readiness interlock for the git-data host CREATE dispatch (#6977).
#
# WHAT THIS REFUSES, AND WHY IT IS NOT PROSE. When this gate was written,
# `cloud-init-git-data.yml` emitted NOTHING off-host: 0 occurrences of sentry_dsn, sentry,
# vector, betterstack, journald, heartbeat, against the web host's 9 / 17 / 14 / 2 / 7 / 1
# on the same six tokens, counted with `grep -ci`.
#
# THAT MEASUREMENT IS HISTORY, NOT THE CURRENT STATE. #6982 shipped the emitter, so this
# gate RELEASES today and stands as a regression check rather than a hold. Re-derive rather
# than trusting either number:
#
#   grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-git-data.yml \
#     | grep -c 'sentry_dsn'          # => 2 as of #6982 (the sentinel; 0 is what held)
#
# State the counting convention, and count only tokens you list: an earlier revision named
# eight tokens against seven values (so the mapping was undeterminable) and reported
# heartbeat as 4, which is 1.
#
# The consequence is the whole reason this file exists: A GREEN `terraform apply` AND A
# DARK HOST ARE INDISTINGUISHABLE FOR GIT-DATA. ADR-145's readiness gates presuppose the
# host reports — gate #1 asserts SENTRY_DSN is non-empty, gate #3 polls the boot through
# R2-R5 — and neither has an analogue here, because there was nothing to poll. Combine
# that with the fact that nothing in the boot path failed closed (the Doppler runcmd had
# no `set -e`, and the LUKS block's `set -euo pipefail` is line 1 of the heredoc that
# `doppler run` executes, so on a missing or wrong-arch binary it never ran) and a birth
# could land a host with its encrypted volume unmounted, no private NIC, or a failed
# bootstrap — and report success.
#
# BOTH HALVES OF THAT ARE NOW CLOSED BY #6982 and the tenses above are historical: the
# runcmd path is armed with a top-level `trap`/`set -e` ahead of the checksum block, and
# `stage:boot_complete` gives the birth job something to poll. So the route no longer
# refuses; this gate stays armed as the regression check that the emitter's DSN threading
# cannot silently disappear, which is what makes the ordering mechanical instead of a
# sentence in a runbook that the next person may not read.
#
# WHY THE SENTINEL IS AN INTERPOLATION AND NOT A WORD. A bare grep for "sentry" is
# satisfied by a comment saying "TODO: add sentry". The sentinel here is the terraform
# interpolation `${sentry_dsn}` appearing in NON-COMMENT template text, which means:
#   • it cannot be satisfied by prose — a YAML comment is excluded explicitly;
#   • it is self-enforcing at plan time — `templatefile` FAILS on a template variable the
#     caller does not supply, so the marker cannot exist without git-data.tf actually
#     threading the DSN into the host;
#   • `$${sentry_dsn}` (the escaped literal) does not count, because terraform renders it
#     as text rather than substituting anything.
#
# WHAT IT DOES NOT CLAIM. This makes a dark boot unreachable FROM THIS ROUTE. It does not
# make it impossible: a break-glass untargeted apply from an operator laptop is unaffected
# by anything in this repository. An earlier draft of the ADR said "impossible"; that
# overstated it and is corrected here.
#
# RELEASE CONDITION — the checklist #6982 inherits (recorded in full in ADR-149):
#   1. the sentinel is present in non-comment template text;
#   2. the emitter's credential is reachable within doppler_service_token.git_data's
#      single-config scope — an emitter reading a DSN from Doppler is dark BY
#      CONSTRUCTION today, so wiring the sentinel without this is theatre;
#   3. any new address the emitter introduces is added to the -target set, the gate's
#      allow-set and the parity const, all three;
#   4. a post-apply signal exists to replace ADR-145's dropped R2-R5 boot poll;
#   5. GIT_DATA_SSH_HOST is produced (it has no producer today, and resolveGitDataSshHost()
#      THROWS in production without it — so a birth turns Art. 17 erasure into a 100 %
#      false-alarm path);
#   6. the firewall-attachment entailment correction is in place;
#   7. THIS GATE'S OWN MECHANISM is replaced by a direct assertion on the emitter resource
#      and this gate's text check is deleted (operator decision 2026-07-27, DC-2) — a dispatch
#      precondition, not a post-release cleanup, which is why it sits ahead of (8). NOTE: what
#      is deleted is THIS GATE's grep, not the ${sentry_dsn} interpolation in cloud-init, which
#      (1) still requires; and the replacement asserts a different fact than (1), so (1)'s
#      threading is not automatically covered by it;
#   8. the DO-NOT-DISPATCH banner in git-data-birth.md is cleared (terminal: the runbook
#      clears it only when every item above is done).
#
# This gate mechanically enforces only the THREADING half of (1) — a non-comment line that
# merely references the variable releases it. It cannot check the remaining items, and saying
# so here is deliberate: a gate that is believed to cover more than it does is worse than one
# whose scope is written down.
#
# Usage:  source tests/scripts/lib/git-data-birth-readiness-gate.sh
#         git_data_birth_readiness_gate <cloud-init-git-data.yml>   # 0=RELEASED, 1=HOLD

git_data_birth_readiness_gate() {
  local cloud_init="${1:-}"
  local hits

  if [[ -z "$cloud_init" ]]; then
    echo "git_data_birth_readiness_gate: ABORT — no cloud-init path supplied. Fail-closed: a readiness gate with nothing to inspect has not found readiness."
    return 1
  fi

  if [[ ! -f "$cloud_init" ]]; then
    echo "git_data_birth_readiness_gate: ABORT — cloud-init template not found: ${cloud_init}. Fail-closed: an unreadable template is not evidence of an emitter."
    return 1
  fi

  # The two patterns are hoisted onto their own lines rather than inlined into the
  # pipeline, so each is independently anchorable — both by a reader and by the suite's
  # mutation battery, which must be able to neuter exactly one of them at a time. An
  # inlined pipeline can only be mutated as a whole, which collapses two distinct
  # properties into one assertion.
  local strip_comments sentinel_re

  # Strips BOTH comment forms. `sed` rather than `grep -v`, because a whole-line filter
  # cannot see a TRAILING comment — and the live cloud-init-git-data.yml already uses one
  # on its `- util-linux # provides flock …` line. Measured: appending
  # `TODO(#6982): emit boot status to ${sentry_dsn}` to that existing trailing comment
  # flipped the gate from HOLD to RELEASED, so a prose marker in the single most natural
  # place to write one disengaged the whole interlock. The header claimed "it cannot be
  # satisfied by prose"; that was true only of whole-line comments.
  #
  # A comment-only back-reference pointing at #6982 is explicitly PERMITTED and desirable
  # in either form — it must not release the interlock.
  #
  # THE QUOTE-FREE-TAIL FORM FAILED OPEN. `s/[[:space:]]#[^"'"'"']*$//` strips a trailing
  # comment only when its tail contains no quote character, so any comment that happens to
  # carry one survives — and a surviving comment can satisfy the sentinel. Measured (#7066
  # review): `# TODO emit to ${sentry_dsn} for the host'"'"'s boot` passes the strip and
  # SATISFIES the sentinel, re-entering the exact defect this block was written to close.
  #
  # The intent was to protect a `#` INSIDE a quoted scalar, which is real template text. That
  # is a claim about whether the `#` is quoted, not about what follows it — so test the
  # PREFIX: strip a trailing comment only when the part of the line before the `#` has an
  # even number of quote characters, i.e. the `#` is not inside an open quote.
  strip_comments='s/^[[:space:]]*#.*$//; :a; s/^\(\([^"'"'"'#]*\("[^"]*"\|'"'"'[^'"'"']*'"'"'\)\)*[^"'"'"'#]*\)[[:space:]]#.*$/\1/; ta'

  # Matches the terraform interpolation while refusing the escaped literal
  # `$${sentry_dsn}`, which terraform renders as text and substitutes nothing. The
  # `\(^\|[^$]\)` prefix is what makes that distinction; without it a shell snippet
  # referencing a same-named shell variable would release the gate.
  sentinel_re='\(^\|[^$]\)\${sentry_dsn}'

  # `|| true` because grep exits 1 on no-match and this function runs under a caller that
  # may have `set -e`; the count, not the exit status, is the signal.
  hits=$(sed "$strip_comments" "$cloud_init" 2>/dev/null \
         | grep -c "$sentinel_re" || true)

  if [[ ! "$hits" =~ ^[0-9]+$ ]]; then
    echo "git_data_birth_readiness_gate: ABORT — sentinel count did not evaluate (got '${hits}'). Fail-closed."
    return 1
  fi

  if [[ "$hits" -eq 0 ]]; then
    cat <<'HOLD'
git_data_birth_readiness_gate: HOLD — the git-data birth route is INTERLOCKED and will not apply.

WHY: cloud-init-git-data.yml still emits nothing off-host. The sentinel this gate looks
for — the terraform interpolation ${sentry_dsn} in non-comment template text — is absent,
which means the host has no way to report a failed boot. For this host specifically that
is not a monitoring gap, it is a correctness gap: nothing in the boot path fails closed,
so a host whose LUKS volume never mounted, whose private NIC never attached, or whose
bootstrap died is INDISTINGUISHABLE from a healthy one. A green terraform apply would be
the only signal you get, and it would be wrong.

TO RELEASE THIS INTERLOCK — this is #6982's handoff, and the full checklist is ADR-149:
  1. Ship the off-host emitter in cloud-init-git-data.yml and thread sentry_dsn through
     git-data.tf's templatefile vars block. `templatefile` fails on an unsupplied
     variable, so the sentinel cannot be faked — wiring it IS the work.
  2. Confirm the emitter's credential is reachable inside
     doppler_service_token.git_data's single-config scope. An emitter that reads its DSN
     from Doppler is dark by construction today; wiring the sentinel without this
     releases the gate and changes nothing observable.
  3. Add any new address the emitter introduces to ALL THREE of: the -target set in
     apply-web-platform-infra.yml, `def allow:` in git-data-host-birth-gate.sh, and
     GIT_DATA_BIRTH_TARGET_BASES in terraform-target-parity.test.ts.
  4. Provide a post-apply signal to replace ADR-145's R2-R5 boot poll, which has no
     analogue here because there is currently nothing to poll.

  (The numbered items above are the subset this message spells out; ADR-149 carries the
  full checklist, including GIT_DATA_SSH_HOST production and the firewall-attachment
  entailment correction.)

ALSO MANDATED, and read this before you start rather than after: replace THIS GATE's own
mechanism with a direct assertion on the emitter resource, and delete this gate's
${sentry_dsn} text check. Operator decision 2026-07-27 (DC-2); recorded on the ADR-149
release checklist as "Replace this interlock's mechanism with a direct assertion on the
emitter resource". What gets deleted is THIS GATE's grep -- NOT the ${sentry_dsn}
interpolation in cloud-init-git-data.yml, which item 1 above still requires. Note the
replacement asserts a different fact than item 1 does, so item 1's threading check is not
automatically covered by it.

THEN clear the DO-NOT-DISPATCH banner at the top of
knowledge-base/engineering/operations/runbooks/git-data-birth.md.

Do NOT work around this by applying from a laptop. An untargeted apply runs neither the
destroy-guard nor the stock preflight, and a plan of that shape taken 2026-07-27 carried
NINE destroys. This interlock makes a dark boot unreachable from the dispatch route; it
cannot protect a break-glass path, which is exactly why the break-glass path is not the
answer here.
HOLD
    return 1
  fi

  echo "git_data_birth_readiness_gate: RELEASED — ${hits} non-comment \${sentry_dsn} interpolation(s) found in ${cloud_init}; the host has an off-host emitter wired. NOTE: this gate enforces only the THREADING half of item 1 of the ADR-149 release checklist — a non-comment line that merely references the variable satisfies it. EVERY OTHER item on the ADR-149 release checklist — Doppler scope reachability, address registration, the post-apply signal, GIT_DATA_SSH_HOST production, the firewall-attachment entailment correction, this gate's own mandated replacement by a direct assertion on the emitter resource (operator decision 2026-07-27, DC-2), and clearing the runbook banner — is NOT machine-checked here. The rung-2 boot rehearsal is checked SEPARATELY by git_data_rung2_rehearsal_gate, which the dispatch job runs alongside this one."
  return 0
}

# ── THE SECOND INTERLOCK: rung-2 boot evidence (#6982 A3) ─────────────────────────────
#
# WHY THIS EXISTS. #6982 shipped the emitter, so the sentinel gate above now RELEASES. That
# retired the ONLY mechanical hold on the birth route, leaving the dispatch held by prose:
# the DO-NOT-DISPATCH banner in git-data-birth.md and the ADR-149 checklist. ADR-149's own
# Alternatives table rejects exactly that posture — "a capability held only by prose is held
# until the first person who reads the runbook and not the plan" — and the workflow's own
# comment now reads "THE BIRTH-READINESS INTERLOCK IS RELEASED", which INVITES the dispatch
# the banner forbids. The banner lives in a different file from the button.
#
# WHAT IT CHECKS, and nothing more. That the rendered cloud-init has been booted once on a
# throwaway host (rung 2) and that the evidence is for THE TEMPLATE BEING DISPATCHED. It is
# deliberately NOT a proxy for the rest of the ADR-149 checklist.
#
# THE HASH BINDING IS THE POINT. Requiring only "some evidence file exists" would be
# satisfied forever by a rehearsal of a template that has since been edited — and this
# template is edited constantly. Pinning RUNG2_TEMPLATE_SHA256 to the live file's hash makes
# the evidence SELF-INVALIDATING: any later edit to cloud-init-git-data.yml re-holds the
# route until it is re-rehearsed. That is the property prose cannot have.
#
# Rung 1 (the container harness this PR shipped) deliberately does NOT satisfy this. It never
# boots the rendered template, so it cannot evidence a real boot. #7025 carries rung 2 as its
# own precondition and is the issue that lands this file.
#
# Comments are stripped before matching, for the reason the sentinel gate learned the hard
# way: a prose marker in a comment must never disengage a mechanical hold.
#
# ── THE SHARED HASH DERIVATION ────────────────────────────────────────────────────────
#
# (#7025) Extracted out of the gate so the EVIDENCE-CAPTURE SCRIPT calls the same function
# the gate does. This is the point of the extraction, and it is worth stating plainly: if the
# capture script hand-rolled the derivation, "the evidence matches the gate" would be a
# property maintained by two people remembering to edit two files. One call makes
# disagreement structurally impossible rather than merely tested.
#
# WHAT IT HASHES. A hash-of-hashes over the cloud-init template plus every `file()`-bound
# payload in the render module, sorted for determinism. Derived from the .tf rather than
# listed here so a newly injected payload is covered the day it is bound. No terraform
# needed, so it stays runnable in CI, in tests, and on a laptop.
#
# (#7025, R7) THE MAP LIVES IN THE MODULE. It used to be inline in git-data.tf; it is now
# modules/git-data-userdata/main.tf, which BOTH the production root and the rung-2 rehearsal
# root call. Reading git-data.tf here would resolve ZERO payloads and trip the floor below —
# fail-closed, but for a reason that would read as drift rather than as a moved file, so the
# ABORT names the module explicitly.
#
# (#7025, R4) PATH-INVARIANT, AND THIS IS A FIX TO A SHIPPED DEFECT. The first version piped
# the resolved PATHS through `xargs sha256sum`, whose output embeds each path — so the same
# bytes hashed differently depending on the caller's cwd. Measured on the live tree:
#
#   apps/web-platform/infra/<name>   -> aa1447f2b3bfa964707e1d8a0f51f866b0de1b917eb628a92575d6fe52349ff3
#   <name>            (cwd = infra)  -> dcaa128171114639a3d011c77fe354510f03903ed547d8851a3075c5dd677733
#   /abs/path/<name>                 -> b77f4998413b684860aa6dd55f69b089ab0c1818962628625ab8fd7dc4b89a59
#
# Three hashes, identical bytes. Production invokes this with ${GITHUB_WORKSPACE}/… ; a
# capture script running from the repo root, or an operator on a laptop, would not. Evidence
# captured at one cwd would read STALE EVIDENCE forever, and the message would blame a
# template edit that never happened — a diagnosis that is both actionable and false, which is
# the expensive kind of wrong. Hashing `<sha>  <basename>` under LC_ALL=C removes the cwd from
# the answer. It was free to fix only because no evidence file exists yet.
#
# BASENAMES REQUIRE UNIQUENESS, so that is asserted rather than assumed: two payloads with the
# same basename in different directories would collapse into one line and silently narrow the
# binding, which is the same fail-open the floor exists to catch.
#
# Usage:  git_data_rung2_user_data_sha256 <cloud-init-git-data.yml>
#         # prints the 64-hex hash on stdout and returns 0; on failure prints a
#         # fail-closed ABORT diagnostic on stdout and returns 1.
git_data_rung2_user_data_sha256() {
  local cloud_init="${1:-}"
  local tf_dir module_dir module_tf _inputs=() _f _n_uniq

  if [[ -z "$cloud_init" || ! -f "$cloud_init" ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — cloud-init template missing or not supplied ('${cloud_init}'). Fail-closed: with no template there is nothing to hash."
    return 1
  fi

  tf_dir="$(dirname "$cloud_init")"
  module_dir="${tf_dir}/modules/git-data-userdata"
  module_tf="${module_dir}/main.tf"
  if [[ ! -r "$module_tf" ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — cannot read ${module_tf}, so the payload set backing the evidence hash is unknown. The render module is where the templatefile map lives (#7025 R7); if it moved again, this derivation and every consumer of it must move with it. Fail-closed."
    return 1
  fi

  _inputs+=("$cloud_init")
  # THE MODULE .tf IS ITSELF A USER_DATA INPUT, and omitting it was a live fail-open.
  #
  # It holds `local.git_data_rationale_strip` — the `replace()` transform applied to ALL NINE
  # payloads at render time — so it materially decides what boots. Measured on the live tree:
  # relaxing that expression from `[^!\n]` to `[^\n]` (which strips the SHEBANG from
  # git-data-provision.sh, -remove.sh and -transport-wrapper.sh, all invoked via
  # authorized_keys `command="…"`, so they silently fall back to dash) left the hash
  # BYTE-IDENTICAL at ec52960784d6f4… and the gate reporting RELEASED.
  #
  # #7025 moved the render into a module to kill a SECOND copy of that expression, on the
  # argument that two copies which drift hash identically while rendering differently. The
  # move fixed the two-copies variant and created the one-copy-edited variant: one file, still
  # unhashed. Hashing it closes both.
  _inputs+=("$module_tf")
  # AND ITS SIBLING .tf FILES. main.tf was added because it holds the strip expression and so
  # materially decides what boots; that argument does not stop at one file. variables.tf
  # carries render-var DEFAULTS (doppler_config_name defaults to prd_git_data), so a future
  # default would decide what boots for any caller that stops passing it explicitly, and
  # outputs.tf is where a second arch derivation could be written unseen. Binding the
  # directory costs one glob and is free only while no evidence file exists yet.
  #
  # THIS LOOP APPENDS CONDITIONALLY, so it is a chokepoint and must ABORT rather than drop.
  # Measured on the shipped code: with one sibling made unreadable the function returned rc=0
  # and a WELL-FORMED digest over a narrower set — a fail-open, not a refusal. The
  # referenced-vs-resolved arithmetic below happened to mask it on the live tree only because
  # its two literals cancelled there.
  #
  # ABSENT vs UNREADABLE IS LOAD-BEARING AND IS WRITTEN EXPLICITLY. No `nullglob` is set here,
  # so a pattern matching nothing yields the literal string — and the live module has no
  # `.tf.json` at all, so `*.tf.json` iterates once on an unexpanded literal. A naive
  # `[[ -r ]] || abort` would therefore abort on `main`: the very defect being fixed,
  # reintroduced at the new contributor. Testing only `-e` is the opposite error — it silently
  # skips a dangling symlink, a file Terraform fails on but the hash would quietly exclude.
  #
  #   candidate                        -e     -L     verdict
  #   unexpanded literal (no matches)  false  false  skip
  #   present, readable                true   —      hash it
  #   present, unreadable              true   —      abort
  #   dangling symlink                 false  true   abort
  #
  # `.tf.json` IS INCLUDED because Terraform loads it exactly as it loads `.tf`; the old glob
  # missed it, so a render knob written there decided what boots while staying out of the hash.
  #
  # NO SIBLING FLOOR. A deleted sibling is a real directory change the hash correctly reflects,
  # and a floor here would be precisely the stale literal this change removes — it would break
  # the first time `variables.tf` is legitimately folded into `main.tf`.
  for _f in "${module_dir}"/*.tf "${module_dir}"/*.tf.json; do
    [[ -e "$_f" || -L "$_f" ]] || continue
    [[ "$_f" == "$module_tf" ]] && continue
    if [[ ! -r "$_f" ]]; then
      echo "git_data_rung2_user_data_sha256: ABORT — module Terraform file '${_f}' is present but cannot be read, so the render inputs backing the evidence hash are incomplete. Hashing the rest would produce a well-formed digest over a NARROWER set than ships. Fail-closed."
      return 1
    fi
    _inputs+=("$_f")
  done
  # Payload paths are written relative to the MODULE (`${path.module}/../../<name>`), so they
  # resolve against module_dir — not against tf_dir, which would land two levels too high and
  # drop every payload out of the set.
  #
  # Key class is `[A-Za-z0-9_]+`, not `[a-z_]+`: a binding named `boot_probe2` or `bootProbe`
  # was silently unextracted, so its payload rendered into user_data while edits to it left the
  # hash unchanged (the floor did not fire — the original ten were all still present).
  # ONE RULE: every `file("${path.module}/…")` on a NON-COMMENT line, excluding `templatefile(`
  # (the template is added separately, above). It had a second consumer — a referenced-vs-
  # resolved count — which #7485 deleted, because counting a drop is strictly weaker than
  # refusing at the drop: the count could report that two integers disagreed, never WHICH
  # payload was missing. Comment-stripping and the `templatefile(` exclusion remain load-bearing
  # for the extraction itself, independently of that deleted consumer.
  # Deliberately wrapper-agnostic — `replace(file(…))`, bare `file(…)`, `trimspace(file(…))`,
  # `base64encode(file(…))` all resolve, because the previous key-anchored form silently
  # skipped any binding whose wrapper or key shape it did not anticipate, and a skipped payload
  # renders into user_data while edits to it leave the evidence hash unchanged.
  # THE WHOLE `file`-FAMILY, not just `file(`. A payload bound via `filebase64(` was invisible
  # to the extraction, so it rendered into user_data while edits to it left the hash unchanged
  # — measured. This was ALSO the standing argument for why the referenced-vs-resolved count
  # could never catch that class: the count called this same extractor on both sides, so its
  # blind spot WAS this regex's blind spot. Widening the regex is what closed it; the count
  # contributed nothing and is gone.
  #
  # THE HONEST BOUND on this predicate is a SINGLE-LINE LITERAL form. A multi-line `file(\n
  # "…"\n)`, an indirected `file(local.p)`, and a second `templatefile()` are all invisible to
  # it, and each would render into user_data while the nine literal payloads still resolve and
  # the floor still passes. That is pre-existing, not introduced by deleting the count — which
  # was equally blind — and it is recorded so this mechanism is not read as complete.
  _payload_refs() {
    sed 's/^[[:space:]]*#.*$//' "$module_tf" \
      | grep -oE '(^|[^A-Za-z])file(base64|sha256|sha512|md5)?\("\$\{path\.module\}/[^"]+"' \
      | sed -E 's/.*\("\$\{path\.module\}\///; s/"$//'
  }
  #
  # THE SECOND CONDITIONAL CHOKEPOINT, and the one the deleted arithmetic below used to police
  # by counting. Aborting HERE — where the drop actually happens — names the offending payload,
  # which the count never could: it could only report that two integers disagreed.
  #
  # THE `-n "$_f"` GUARD IS RETAINED. Written as a bare `-r` test, an empty `_f` yields
  # `-r "${module_dir}/"`, which is TRUE for a directory — so a blank extraction line would
  # append the module directory itself to the hash input set.
  local _n_payloads=0
  while IFS= read -r _f; do
    [[ -n "$_f" ]] || continue
    if [[ ! -r "${module_dir}/${_f}" ]]; then
      echo "git_data_rung2_user_data_sha256: ABORT — ${module_tf} references payload '${_f}', but '${module_dir}/${_f}' cannot be read (absent, or present and unreadable). That payload renders into user_data, so hashing without it would bind the evidence to fewer files than ship. Fail-closed."
      return 1
    fi
    _inputs+=("${module_dir}/${_f}")
    _n_payloads=$((_n_payloads + 1))
  done < <(_payload_refs | sort -u)

  # A FLOOR ON THE PAYLOAD COUNT — not on `#_inputs`, whose composition is what went stale.
  #
  # The old floor was `#_inputs -lt 11`. With two siblings present that reads `4 + N < 11`, so
  # it fired only when N < 7: the shipped floor TOLERATED LOSING TWO OF THE NINE PAYLOADS. It
  # was loose, not merely stale.
  #
  # THIS IS HONESTLY STILL A LITERAL, and the honest statement is that it goes LOOSE by one
  # when a tenth payload lands — it will not abort, it will tolerate losing one. There is no
  # automatic trigger for that and this code does not pretend otherwise: when the payload set
  # grows, THIS LITERAL IS WHERE THE NEW COUNT GOES. It is one literal instead of two, which is
  # an improvement, not immunity.
  #
  # It stays alongside the per-reference abort because the two are orthogonal: deleting five
  # bindings from main.tf leaves every REMAINING reference resolving perfectly while the hash
  # binds four files fewer than ship.
  if [[ "$_n_payloads" -lt 9 ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — the payload extraction from ${module_tf} resolved only ${_n_payloads} payload(s); ship binds 9. The extraction drifted, or bindings were removed. If the payload set legitimately grew or shrank, the floor literal in git_data_rung2_user_data_sha256() is where the new count belongs. Fail-closed."
    return 1
  fi

  _n_uniq="$(printf '%s\n' "${_inputs[@]}" | while IFS= read -r _f; do basename "$_f"; done | LC_ALL=C sort -u | wc -l)"
  if [[ "$_n_uniq" -ne "${#_inputs[@]}" ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — the ${#_inputs[@]} user_data inputs carry only ${_n_uniq} distinct basenames. The hash is basename-keyed for path invariance, so a collision would silently bind the evidence to fewer files than ship. Fail-closed."
    return 1
  fi

  local _line _digest
  # THE PER-FILE rc IS CHECKED. Measured (#7066 review) by shadowing sha256sum to fail on one
  # payload: the inner substitution yielded an EMPTY digest field, the outer sha256sum hashed
  # the resulting line just fine, and the ^[0-9a-f]{64}$ guard below could not see it — rc=0
  # with a well-formed hash of the wrong thing. Deterministic causes make both sides agree on
  # that wrong value, which is worse than disagreeing.
  # ACCUMULATED IN A VARIABLE, not a tempfile. This is a LIBRARY function, so an owning
  # `trap ... EXIT` would clobber the caller's — and ADR-129 rule (c) correctly refuses an
  # allocation nothing reclaims. Not allocating is the better answer than annotating the leak.
  local _acc="" _d
  for _f in "${_inputs[@]}"; do
    _d="$(sha256sum "$_f")" || {
      echo "git_data_rung2_user_data_sha256: ABORT — could not hash ${_f}. A skipped input would produce a well-formed digest of an incomplete set. Fail-closed."
      return 1
    }
    _acc+="${_d%% *}  ${_f##*/}"$'\n'
  done
  _line="$(printf '%s' "$_acc" | LC_ALL=C sort | sha256sum | cut -d' ' -f1)"
  if [[ ! "$_line" =~ ^[0-9a-f]{64}$ ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — could not hash the ${#_inputs[@]} user_data inputs. Fail-closed."
    return 1
  fi
  printf '%s\n' "$_line"
  return 0
}

# (#7025, R6) THE RENDER-VAR DIVERGENCE ALLOWLIST.
#
# The hash above binds the template and the nine payloads. It does NOT bind the templatefile
# ARGUMENTS — host_name, the volume ids, the Doppler token and config, the pubkeys, the arch
# pair, the DSN, the Better Stack URL are `templatefile` inputs, not hashed files. So a
# rehearsal that diverged on the wrong one produces HASH-VALID evidence for a boot that is not
# the boot production would get.
#
# doppler_arch and doppler_sha256 are the case that makes this mandatory rather than tidy:
# they select WHICH BINARY is downloaded and WHICH CHECKSUM verifies it, so a mis-derived pair
# verifies the tarball it just chose and `sha256sum -c -` passes. That is the #6570
# boot-brick class, and a rehearsal that diverged there would prove the absence of a failure
# mode production still has.
#
# The gap is closed by DECLARATION, not by inference: the rehearsal writes RUNG2_VAR_DIVERGENCE
# and anything outside this list refuses. The list is CLOSED — an unrecognised name refuses
# too, because a typo'd or newly-introduced var is exactly where "not on a deny list" and
# "safe" come apart.
GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST="host_name git_data_volume_id git_data_luks_volume_id doppler_token doppler_config_name git_transport_pubkey git_provision_pubkey git_remove_pubkey"

# Usage:  git_data_rung2_rehearsal_gate <cloud-init-git-data.yml> [evidence-file]
#         # 0=RELEASED, 1=HOLD
git_data_rung2_rehearsal_gate() {
  local cloud_init="${1:-}"
  local evidence="${2:-}"
  local body live_sha claimed_sha url

  if [[ -z "$cloud_init" || ! -f "$cloud_init" ]]; then
    echo "git_data_rung2_rehearsal_gate: ABORT — cloud-init template missing or not supplied ('${cloud_init}'). Fail-closed: with no template there is nothing to bind evidence to."
    return 1
  fi

  # Default beside the template it attests to, so the two move together in review.
  if [[ -z "$evidence" ]]; then
    evidence="$(dirname "$cloud_init")/git-data-rung2-boot-evidence.env"
  fi

  if [[ ! -f "$evidence" ]]; then
    cat <<HOLD
git_data_rung2_rehearsal_gate: HOLD — the git-data birth route is INTERLOCKED and will not apply.

WHY: no rung-2 boot evidence at ${evidence}.

The emitter shipped in #6982, so the \${sentry_dsn} threading interlock released. That was
the only MECHANICAL hold on this route. What still holds it is the DO-NOT-DISPATCH banner in
knowledge-base/engineering/operations/runbooks/git-data-birth.md — prose, in a different
file from this button. This gate exists so that hold is mechanical too.

WHAT IS MISSING: the rendered cloud-init has never been booted on real hardware. #6982
reached rung 1 only — a CONTAINER harness that never boots the rendered template — and that
was deliberately NOT inherited as a rung-2 pass. So the first real boot of this template
would be the production host that holds every connected user's source code.

TO RELEASE: run the rung-2 rehearsal (boot the rendered template once on a throwaway host,
outside the hcloud_server.git_data address), then commit ${evidence} containing:

  RUNG2_BOOT_REHEARSAL=PASS
  RUNG2_EVIDENCE_URL=<workflow run or write-up URL>
  RUNG2_TEMPLATE_SHA256=<hash-of-hashes over the template + every file()-bound payload>

Carried by #7025, which owns rung 2 as its own precondition. Nothing has been planned or
created.
HOLD
    return 1
  fi

  # Strip whole-line AND trailing comments, same two forms the sentinel gate strips.
  body="$(sed 's/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//' "$evidence" 2>/dev/null)"

  # EXACTLY-ONCE ON EVERY KEY, and this is a fail-open fix rather than tidiness.
  #
  # The PASS assertion was `grep -qE` (matches ANY line) while every other key uses `head -1`.
  # So the gate read FIRST-WINS while `source`/dotenv semantics are LAST-WINS, and a file
  # containing both `RUNG2_BOOT_REHEARSAL=PASS` and `RUNG2_BOOT_REHEARSAL=FAIL` RELEASED —
  # measured. A git merge of two evidence files, or a careless append, produces a file whose
  # meaning differs between this gate and any human or shell that reads it.
  #
  # RUNG2_VAR_DIVERGENCE is REQUIRED PRESENT for the same reason: an absent key left
  # `divergence` empty, the allowlist loop iterated zero times, and the closed allowlist
  # refused nothing. Declaring "nothing diverged" must be explicit (`RUNG2_VAR_DIVERGENCE=none`),
  # never inferred from silence.
  local _k _n
  for _k in RUNG2_BOOT_REHEARSAL RUNG2_EVIDENCE_URL RUNG2_TEMPLATE_SHA256 RUNG2_VAR_DIVERGENCE; do
    # `(export[[:space:]]+)?` is load-bearing. Measured: an evidence file carrying
    #   RUNG2_BOOT_REHEARSAL=PASS
    #   export RUNG2_BOOT_REHEARSAL=FAIL
    # counted as ONE occurrence and RELEASED, while a shell that `source`s the same file
    # sees FAIL — reinstating verbatim the divergence-of-meaning this loop's own error
    # message describes. `export` is the one dotenv decoration a human is most likely to
    # write, and it was the only one of five tested shapes that got through.
    _n="$(grep -cE "^[[:space:]]*(export[[:space:]]+)?${_k}[[:space:]]*=" <<<"$body" || true)"
    if [[ "$_n" -ne 1 ]]; then
      echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} carries ${_n} '${_k}' line(s); exactly 1 is required. Fail-closed: this gate reads first-wins while dotenv semantics are last-wins, so a duplicated key means the file's meaning differs between this gate and every other reader of it. An ABSENT key is equally refused — 'nothing diverged' must be declared, not inferred from silence."
      return 1
    fi
  done

  if ! grep -qE '^[[:space:]]*RUNG2_BOOT_REHEARSAL[[:space:]]*=[[:space:]]*PASS[[:space:]]*$' <<<"$body"; then
    echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} does not assert RUNG2_BOOT_REHEARSAL=PASS in non-comment text. Fail-closed: an evidence file that does not claim a pass is not a pass."
    return 1
  fi

  url="$(grep -E '^[[:space:]]*RUNG2_EVIDENCE_URL[[:space:]]*=' <<<"$body" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  # (#7025, R8) AN ACTIONS RUN IN THIS REPO, not merely something URL-shaped. `^https?://`
  # was satisfied by anything a person could type, and that is load-bearing here in a way it
  # would not be elsewhere: `main` carries NO `pull_request` ruleset — no required approving
  # reviews — and `can_approve_pull_request_reviews: true`, so a hand-authored evidence file
  # citing https://example.com would release the LAST mechanical hold on the host that stores
  # every connected user's source code.
  #
  # This does not make the pointer unforgeable, and claiming otherwise would repeat the
  # "impossible" overstatement corrected in the sentinel gate's header. What it buys is that
  # the claim now names an artifact which either exists in this repository's run history or
  # does not — a thing a reviewer can check in one click, rather than a string.
  #
  # NOT anchored at the end: GitHub's own links carry `/job/<id>` and `/attempts/<n>`
  # suffixes, so an end-anchored pattern would refuse the URLs the workflow actually emits.
  if [[ ! "$url" =~ ^https://github\.com/jikig-ai/soleur/actions/runs/[0-9]+ ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — RUNG2_EVIDENCE_URL in ${evidence} is not an Actions run URL for this repository (got '${url}'; expected https://github.com/jikig-ai/soleur/actions/runs/<id>). Fail-closed: an unauditable claim is not evidence, and this repository's main branch has no required-review ruleset standing behind a hand-typed one."
    return 1
  fi

  claimed_sha="$(grep -E '^[[:space:]]*RUNG2_TEMPLATE_SHA256[[:space:]]*=' <<<"$body" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-F' 'a-f')"
  if [[ ! "$claimed_sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — RUNG2_TEMPLATE_SHA256 in ${evidence} is absent or malformed (got '${claimed_sha}'). Fail-closed."
    return 1
  fi

  # (#7025, R6) THE DECLARED RENDER-VAR DIVERGENCE, checked BEFORE the hash.
  #
  # Ordered first among the two remaining refusals on purpose: a divergence violation and a
  # stale hash are different defects with different remedies (re-run the rehearsal with prod
  # values vs. re-run it against the current template), and reporting the hash first would
  # send the reader to the wrong one whenever both are true.
  local divergence _tok _allowed
  divergence="$(grep -E '^[[:space:]]*RUNG2_VAR_DIVERGENCE[[:space:]]*=' <<<"$body" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  # A PRESENT KEY WITH AN EMPTY VALUE IS NOT A DECLARATION. The cardinality loop above counts
  # lines matching the KEY; it never required a VALUE, so `RUNG2_VAR_DIVERGENCE=` counted as
  # exactly 1, `divergence` came back empty, `read -ra` yielded zero tokens, the closed
  # allowlist iterated zero times, and the gate RELEASED — measured. The release message then
  # printed `${divergence:-none}`, asserting a declaration of "none" that nobody made.
  #
  # This is the same property the block above states ("Declaring 'nothing diverged' must be
  # explicit, never inferred from silence") applied to the case it did not cover: that fix
  # closed ABSENT and left EMPTY open. Whitespace-only is the same silence with extra bytes,
  # so it is stripped before the test — and `--divergence` upstream validates with `-z` only,
  # which `$'\n'` passes.
  if [[ -z "${divergence//[[:space:]]/}" ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} carries RUNG2_VAR_DIVERGENCE with an EMPTY value. 'Nothing diverged' must be declared explicitly as RUNG2_VAR_DIVERGENCE=none; an empty value is silence, and silence cannot release this gate. Fail-closed." >&2
    return 1
  fi
  # `read -ra` + noglob, NOT an unquoted expansion. Caught in review: `for _tok in
  # ${divergence//,/ }` subjects the evidence file's value to PATHNAME EXPANSION, so a
  # `RUNG2_VAR_DIVERGENCE=*` is replaced by whatever happens to be in the caller's cwd.
  # Measured: with files named `host_name` and `sentry_dsn` present, `*` expanded to exactly
  # those two names and both are on the allowlist.
  #
  # At the real cwd (repo root / GITHUB_WORKSPACE) the expansion yields README.md, apps,
  # scripts … none allowlisted, so today it fails CLOSED. Fixed anyway: a gate whose verdict
  # is a function of ambient directory contents is wrong regardless of which way the current
  # accident happens to point, and nothing pins that cwd.
  local _old_glob; _old_glob="$(set +o | grep noglob)"
  set -o noglob
  # shellcheck disable=SC2086
  read -ra _div_toks <<<"${divergence//,/ }"
  eval "$_old_glob"
  for _tok in "${_div_toks[@]+"${_div_toks[@]}"}"; do
    [[ -z "$_tok" ]] && continue
    # The explicit no-divergence declaration. Required because an ABSENT key is now refused
    # outright, so a rehearsal that genuinely diverged on nothing needs a way to say so.
    [[ "$_tok" == "none" ]] && continue
    _allowed=0
    for _a in $GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST; do
      [[ "$_tok" == "$_a" ]] && { _allowed=1; break; }
    done
    if [[ "$_allowed" -eq 0 ]]; then
      echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} declares that the rehearsal diverged from production on '${_tok}', which is not an identity-shaped render var. The evidence hash binds the template and the nine payloads; it does NOT bind templatefile arguments, so a divergence here yields hash-valid evidence for a boot that is not the boot production would get. Permitted: ${GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST// /, }. Fail-closed."
      return 1
    fi
  done

  # HASH EVERY INPUT THAT SHIPS, not just the template. The first version hashed
  # cloud-init-git-data.yml alone — 1 of the 10 files that compose user_data — so editing
  # git-data-gc.sh, either gc unit, the bootstrap or any forced-command wrapper left rung-2
  # evidence VALID for a payload that had changed. That defeats the whole self-invalidation
  # property this binding exists to provide: what boots is the RENDER, and the template is
  # one input to it.
  #
  # (#7025) Delegated to git_data_rung2_user_data_sha256 — the SAME function the evidence
  # capture script calls. The extraction is the point: two hand-rolled derivations agreeing
  # is a property maintained by memory, and this one has to hold across a file the capture
  # script writes and this gate later reads.
  local _sha_out
  if ! _sha_out="$(git_data_rung2_user_data_sha256 "$cloud_init")"; then
    echo "$_sha_out"
    return 1
  fi
  live_sha="$_sha_out"

  if [[ "$claimed_sha" != "$live_sha" ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — STALE EVIDENCE. ${evidence} attests a rehearsal of user_data sha256 ${claimed_sha}, but the files composing user_data now hash to ${live_sha}. Something that ships to the host changed after it was rehearsed, so the boot that was proven is not the boot that would happen. Re-run the rung-2 rehearsal against the current template and update the evidence."
    return 1
  fi

  echo "git_data_rung2_rehearsal_gate: RELEASED — rung-2 boot evidence at ${evidence} attests PASS for user_data sha256 ${live_sha} (${url}); declared render-var divergence: ${divergence}. NOTE: this gate checks the rung-2 boot rehearsal ONLY. It says nothing about the other ADR-149 checklist items, which the sentinel gate's own message enumerates."
  return 0
}
