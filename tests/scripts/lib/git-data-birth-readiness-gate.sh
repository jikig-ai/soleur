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
  # `#[^"'"'"']*$` deliberately does not strip a `#` inside a quoted string: a sentinel
  # written inside a quoted YAML scalar is real template text that terraform interpolates.
  strip_comments='s/^[[:space:]]*#.*$//; s/[[:space:]]#[^"'"'"']*$//'

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

  if ! grep -qE '^[[:space:]]*RUNG2_BOOT_REHEARSAL[[:space:]]*=[[:space:]]*PASS[[:space:]]*$' <<<"$body"; then
    echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} does not assert RUNG2_BOOT_REHEARSAL=PASS in non-comment text. Fail-closed: an evidence file that does not claim a pass is not a pass."
    return 1
  fi

  url="$(grep -E '^[[:space:]]*RUNG2_EVIDENCE_URL[[:space:]]*=' <<<"$body" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — RUNG2_EVIDENCE_URL in ${evidence} is absent or not a URL (got '${url}'). Fail-closed: an unauditable claim is not evidence."
    return 1
  fi

  claimed_sha="$(grep -E '^[[:space:]]*RUNG2_TEMPLATE_SHA256[[:space:]]*=' <<<"$body" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-F' 'a-f')"
  if [[ ! "$claimed_sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — RUNG2_TEMPLATE_SHA256 in ${evidence} is absent or malformed (got '${claimed_sha}'). Fail-closed."
    return 1
  fi

  # HASH EVERY INPUT THAT SHIPS, not just the template. The first version hashed
  # cloud-init-git-data.yml alone — 1 of the 10 files that compose user_data — so editing
  # git-data-gc.sh, either gc unit, the bootstrap or any forced-command wrapper left rung-2
  # evidence VALID for a payload that had changed. That defeats the whole self-invalidation
  # property this binding exists to provide: what boots is the RENDER, and the template is
  # one input to it.
  #
  # A hash-of-hashes over the template plus every `file()`-bound payload in git-data.tf,
  # sorted for determinism. Derived from the .tf rather than listed here so a newly injected
  # payload is covered the day it is bound. No terraform needed, so the gate stays runnable
  # in CI, in tests, and on a laptop.
  local tf_dir tf_file _inputs=() _f
  tf_dir="$(dirname "$cloud_init")"
  tf_file="${tf_dir}/git-data.tf"
  if [[ ! -r "$tf_file" ]]; then
    echo "git_data_rung2_rehearsal_gate: ABORT — cannot read ${tf_file}, so the payload set backing the evidence hash is unknown. Fail-closed."
    return 1
  fi
  _inputs+=("$cloud_init")
  while IFS= read -r _f; do
    [[ -n "$_f" && -r "${tf_dir}/${_f}" ]] && _inputs+=("${tf_dir}/${_f}")
  done < <(sed -nE 's/^[[:space:]]*[a-z_]+[[:space:]]*=[[:space:]]*(replace\()?file\("\$\{path\.module\}\/([^"]+)"\).*/\2/p' "$tf_file" | sort -u)
  # A floor: the template + nine payloads. A shrunken extraction would silently narrow what
  # the evidence is bound to, which is the same fail-open in a different costume.
  if [[ "${#_inputs[@]}" -lt 10 ]]; then
    echo "git_data_rung2_rehearsal_gate: ABORT — resolved only ${#_inputs[@]} user_data input(s) (expected the template + 9 payloads). The payload-set extraction from ${tf_file} drifted. Fail-closed."
    return 1
  fi
  live_sha="$(printf '%s\n' "${_inputs[@]}" | sort | xargs sha256sum 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1)"
  if [[ ! "$live_sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "git_data_rung2_rehearsal_gate: ABORT — could not hash the ${#_inputs[@]} user_data inputs. Fail-closed."
    return 1
  fi

  if [[ "$claimed_sha" != "$live_sha" ]]; then
    echo "git_data_rung2_rehearsal_gate: HOLD — STALE EVIDENCE. ${evidence} attests a rehearsal of user_data sha256 ${claimed_sha}, but the ${#_inputs[@]} files composing user_data now hash to ${live_sha}. Something that ships to the host changed after it was rehearsed, so the boot that was proven is not the boot that would happen. Re-run the rung-2 rehearsal against the current template and update the evidence."
    return 1
  fi

  echo "git_data_rung2_rehearsal_gate: RELEASED — rung-2 boot evidence at ${evidence} attests PASS for user_data sha256 ${live_sha} (${#_inputs[@]} inputs) (${url}). NOTE: this gate checks the rung-2 boot rehearsal ONLY. It says nothing about the other ADR-149 checklist items, which the sentinel gate's own message enumerates."
  return 0
}
