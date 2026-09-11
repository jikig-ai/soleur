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
# ── ONE DERIVATION, TWO CONSUMERS (#8043 NFR2 / Guard 4) ─────────────────────────────
#
# The enumeration below used to be the first half of git_data_rung2_user_data_sha256. It is
# now its own function because a SECOND consumer arrived: the evidence-provenance guard
# (git_data_rung2_evidence_provenance_gate) needs the same 13-file roster the hash binds —
# and needs it to be the SAME walk, not a second list that agrees today. A provenance guard
# over a hand-listed subset passes the moment a payload is bound that the list does not name,
# which is the "attests a byte set that is not what ships" class one function over. The hash
# consumes this function's output; so does the guard; there is nothing else to drift.
#
# The split is HASH-NEUTRAL by construction: every ABORT check that used to run before the
# hash loop still runs here, in the same order, with the same messages, and the hash function
# below hashes exactly the lines this prints. Measured on the live tree at the split:
# bbe1a1426667ee8898f1883505f95aca8fe6e723b639cb5900e9b3560cedbb1a before and after.
#
# Usage:  git_data_rung2_bound_files <cloud-init-git-data.yml>
#         # prints the ABSOLUTE path of every file that composes user_data, one per line —
#         # the template, the render module's .tf/.tf.json files, and every file()-bound
#         # payload — and returns 0; on failure prints a fail-closed ABORT diagnostic on
#         # stdout and returns 1. Order: template, main.tf, siblings (glob order), payloads
#         # (sorted). The hash sorts its own lines, so this order is not load-bearing there.
git_data_rung2_bound_files() {
  local cloud_init="${1:-}"
  local tf_dir module_dir module_tf _inputs=() _f _n_uniq

  if [[ -z "$cloud_init" || ! -f "$cloud_init" ]]; then
    echo "git_data_rung2_bound_files: ABORT — cloud-init template missing or not supplied ('${cloud_init}'). Fail-closed: with no template there is nothing to hash."
    return 1
  fi

  tf_dir="$(dirname "$cloud_init")"
  module_dir="${tf_dir}/modules/git-data-userdata"
  module_tf="${module_dir}/main.tf"
  if [[ ! -r "$module_tf" ]]; then
    echo "git_data_rung2_bound_files: ABORT — cannot read ${module_tf}, so the payload set backing the evidence hash is unknown. The render module is where the templatefile map lives (#7025 R7); if it moved again, this derivation and every consumer of it must move with it. Fail-closed."
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
  #
  # Measured against `origin/main`, and stated precisely because an earlier draft of this
  # comment got it wrong in the flattering direction: on the LIVE tree the shipped code aborted
  # (`contains 9 … but only 11 resolved`) whether or not a sibling was readable — that abort IS
  # #7485. The rc=0-over-a-narrower-set fail-open reproduced on a module directory with ONE
  # sibling (inputs 11, resolved 9, refs 9, old floor `-lt 11` satisfied), and on one with the
  # siblings absent entirely. So the two literals did NOT cancel on the live tree, and the
  # shipped code was more broken than "it happened to work here" implies.
  #
  # THE ENUMERATION IS GUARDED, NOT JUST THE FILES. A directory that is executable but not
  # readable (`chmod 111`) leaves `main.tf` openable BY NAME — so the `-r "$module_tf"` check
  # above passes — while pathname expansion silently yields the unexpanded patterns, both fail
  # `[[ -e || -L ]]`, and every sibling drops. Measured: rc=0 with digest 3a1d7198…, which is
  # byte-identical to the digest with both siblings DELETED. The function cannot distinguish
  # "deleted, and the hash correctly reflects it" from "present but unenumerable", so the
  # unreadable-directory case has to refuse before the loop runs.
  if [[ ! -r "$module_dir" || ! -x "$module_dir" ]]; then
    echo "git_data_rung2_bound_files: ABORT — the render module directory '${module_dir}' cannot be listed (needs both read and execute). Its Terraform files would be silently omitted from the hash, producing a well-formed digest over a NARROWER set than ships. Fail-closed."
    return 1
  fi
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
      echo "git_data_rung2_bound_files: ABORT — module Terraform file '${_f}' cannot be read (present and unreadable, or a dangling symlink), so the render inputs backing the evidence hash are incomplete. Hashing the rest would produce a well-formed digest over a NARROWER set than ships. Fail-closed."
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
  # THE HONEST BOUND on this predicate is a SINGLE-LINE LITERAL form, and as of #7534 the
  # non-canonical forms are INADMISSIBLE rather than INVISIBLE. Four forms fall outside it:
  # a multi-line `file(\n "…"\n)`; an indirected `file(local.p)`; a second `templatefile()`;
  # and — the fourth, undocumented until #7534 — a single-line literal whose prefix is not
  # `${path.module}/`, i.e. `file("${path.root}/x")`, `file("../x")`, `file(abspath(…))`,
  # each of which resolves in Terraform and renders into user_data. Before #7534 every one of
  # them rendered while the nine literal payloads still resolved and the floor still passed,
  # so the evidence attested a byte set that was not what shipped.
  #
  # The canonical-shape assertion below closes that by NARROWING the admissible module shape
  # rather than widening the extractor: full HCL parsing cannot reach `file(local.p)` either
  # (that needs evaluating the module, not parsing it), so the "complete" option is itself
  # partial while costing a new binary dependency inside a gate whose contract is fail-closed.
  # The residual, stated honestly: a future change that legitimately needs a non-canonical
  # form reddens this gate, and a human must restore the canonical form or extend the gate
  # deliberately. That is the intended trade — for an evidence gate, refusing is correct and
  # hashing an incomplete set is not.
  # ONE comment-strip, consumed by BOTH the canonical-shape assertion and the extractor.
  # They must not each run their own: a divergence about what counts as a comment would
  # reintroduce exactly the class #7534 closes — a binding one side sees and the other does
  # not. The sed BLANKS comment lines rather than deleting them, so line numbers in the
  # abort messages below are the real ones in "$module_tf".
  local _stripped _shape_src _f
  _stripped=$(sed 's/^[[:space:]]*#.*$//' "$module_tf")

  # THE SHAPE ASSERTION QUANTIFIES OVER THE WHOLE MODULE DIRECTORY, not over main.tf.
  #
  # Scoping it to main.tf was a measured FAIL-OPEN, and it is the #7534 defect class
  # reproduced one file over: Terraform loads every `.tf`/`.tf.json` in the module dir, so
  # `locals { x = file("${path.root}/../../evil.sh") }` in outputs.tf RENDERS INTO user_data
  # while main.tf stays canonical — the gate produced a digest with no abort, and editing
  # evil.sh afterwards did not move it. The sibling FILES are hashed (the input set globs
  # them), but the PAYLOADS they bind were never in the set, which is precisely the
  # "attests a byte set that is not what ships" failure this gate exists to refuse.
  #
  # `_shape_src` is the comment-stripped concatenation of every loaded file; `_stripped`
  # stays main.tf-only because the PAYLOAD EXTRACTOR must keep resolving `${path.module}`
  # against the module dir exactly as before. The two are deliberately different scopes: the
  # extractor answers "which payloads does the canonical binding site name", the shape
  # assertion answers "can anything ANYWHERE in this module bind outside that form".
  _shape_src=""
  for _f in "$module_dir"/*.tf "$module_dir"/*.tf.json; do
    [[ -e "$_f" || -L "$_f" ]] || continue          # unexpanded glob literal (no nullglob)
    [[ -r "$_f" ]] || continue
    _shape_src+="$(sed 's/^[[:space:]]*#.*$//' "$_f")"$'\n'
  done

  _payload_refs() {
    printf '%s\n' "$_stripped" \
      | grep -oE '(^|[^A-Za-z])file(base64|sha256|sha512|md5)?\("\$\{path\.module\}/[^"]+"' \
      | sed -E 's/.*\("\$\{path\.module\}\///; s/"$//'
  }

  # Every `file`-family occurrence NOT in the strict single-line `"${path.module}/…"` form.
  # Line-scoped so the abort can name a location; a line carrying both a strict and a
  # non-strict call is reported, which is the safe direction for a fail-closed gate.
  # THE WHOLE `file`-PREFIXED FAMILY, not an enumerated alternation. `filesha1(`,
  # `filebase64sha256(`, `filebase64sha512(`, `fileset(` and `fileexists(` all sat OUTSIDE
  # `(base64|sha256|sha512|md5)?` on BOTH sides of the count comparison, so each was silent
  # in both operands and the gate could not see it — an enumerated member set rotting exactly
  # the way this file's own comments say enumerated member sets rot. `templatefile(` is
  # excluded explicitly because it is checked separately above (and the previous
  # `(^|[^A-Za-z])` boundary excluded it only incidentally).
  _nonstrict_file_sites() {
    printf '%s\n' "$_shape_src" \
      | grep -nE '(^|[^A-Za-z])file[a-z0-9]*\(' \
      | grep -vE 'templatefile\(' \
      | grep -vE '(^|[^A-Za-z])file[a-z0-9]*\("\$\{path\.module\}/[^"]+"'
  }
  #
  # THE SECOND CONDITIONAL CHOKEPOINT, and the one the deleted arithmetic below used to police
  # by counting. Aborting HERE — where the drop actually happens — names the offending payload,
  # which the count never could: it could only report that two integers disagreed.
  #
  # THE `-n "$_f"` GUARD IS RETAINED. Written as a bare `-r` test, an empty `_f` yields
  # `-r "${module_dir}/"`, which is TRUE for a directory — so a blank extraction line would
  # append the module directory itself to the hash input set.
  # ── #7534 — CANONICAL MODULE SHAPE, asserted BEFORE the extraction is trusted ────────
  #
  # The extractor is provably complete over a NARROWED module shape, and these two checks are
  # what narrow it. Any deviation ABORTs in the same voice as the per-payload abort below,
  # naming the offending occurrence — the lesson that abort already encodes, and the one the
  # deleted referenced-vs-resolved arithmetic could never satisfy (it could report that two
  # integers disagreed, never WHICH binding).
  #
  # (1) EXACTLY ONE `templatefile(`, with the known argument. `grep -o | wc -l` counts
  #     OCCURRENCES; `grep -c` counts LINES, so two calls on one physical line would read as
  #     one and a second template would slip through the check written to catch it.
  local _n_tf
  _n_tf=$(printf '%s\n' "$_shape_src" | grep -oE 'templatefile\(' | wc -l | tr -d '[:space:]')
  if [[ "$_n_tf" != "1" ]]; then
    echo "git_data_rung2_bound_files: ABORT — ${module_tf} contains ${_n_tf} \`templatefile(\` occurrence(s); the canonical shape has exactly 1. A second template renders into user_data and is invisible to the payload extractor, so the evidence digest would attest a byte set that is not what ships. Restore the canonical single-template shape, or extend this gate deliberately. Fail-closed."
    return 1
  fi
  #     The argument must be a strict single-line "${path.module}/…" literal — the SAME form
  #     the payload rule requires, for the same reason: the template's bytes are hashed by
  #     path, so a statically-resolvable path is what makes the digest bind what ships.
  #
  #     THE FORM IS PINNED, NOT THE FILENAME. The plan prescribed asserting the exact
  #     "${path.module}/../../cloud-init-git-data.yml" literal; measured, that is both wrong
  #     and unusable. Unusable: every synthesized module tree in this gate's own suite binds
  #     "${path.module}/../../ci.yml" (per cq-test-fixtures-synthesized-only), so the filename
  #     pin ABORTs 31 arms on this branch (measured 2026-09-03 by re-adding it on a sandbox
  #     copy: 46 passed, 31 failed). An earlier revision said "25 arms — including the
  #     must-PASS rows #7534 adds"; 25 is the figure on origin/main, so it EXCLUDES those
  #     rows rather than including them. The conclusion is unchanged and stronger at 31.
  #     Wrong on the merits too: a MOVED template
  #     that keeps this form still hashes correctly, because the digest binds the file at the
  #     resolved path. Only INDIRECTION (`templatefile(local.t)`, a multi-line call, a
  #     non-`path.module` prefix) breaks the binding, and that is exactly what this form check
  #     catches. A filename pin would assert a different property — identity, not
  #     admissibility — and would buy the digest nothing.
  if ! printf '%s\n' "$_shape_src" | grep -qE 'templatefile\("\$\{path\.module\}/[^"]+"'; then
    echo "git_data_rung2_bound_files: ABORT — ${module_tf}'s sole \`templatefile(\` argument is not a single-line \"\${path.module}/…\" literal. An indirected or multi-line template reference is not statically resolvable, so the evidence digest cannot bind the bytes that render into user_data. Fail-closed."
    return 1
  fi

  # (2) EVERY `file`-family occurrence matched the strict single-line literal form.
  #
  #     The boundary `(^|[^A-Za-z])` is load-bearing on BOTH sides and is the extractor's own:
  #     without it `templatefile(` counts as a `file(` and the rule aborts on the shipped
  #     module. Measured against the comment-stripped main.tf: naive = 10, boundary-aware = 9,
  #     strict-resolved = 9.
  #
  #     The resolved side is counted PRE-`sort -u`. Post-dedup it would false-ABORT the moment
  #     two bindings legitimately referenced the same payload — occurrences 10, deduped 9 —
  #     which is a shape this rule has no business rejecting. The floor below is the one that
  #     is deliberately post-dedup, because it counts distinct payload FILES.
  local _n_occ _n_strict
  _n_occ=$(printf '%s\n' "$_shape_src" | grep -oE '(^|[^A-Za-z])file[a-z0-9]*\(' | grep -vcE 'templatefile\(' || true)
  # Counted over the SHAPE source, so both operands quantify over the same text. The
  # extractor (_payload_refs) stays main.tf-scoped for RESOLUTION; this is a count of
  # strict-form occurrences anywhere in the module.
  _n_strict=$(printf '%s\n' "$_shape_src" | grep -oE '(^|[^A-Za-z])file[a-z0-9]*\("\$\{path\.module\}/[^"]+"' | grep -vc 'templatefile(' || true)
  if [[ "$_n_occ" != "$_n_strict" ]]; then
    echo "git_data_rung2_bound_files: ABORT — ${module_tf} has ${_n_occ} \`file\`-family occurrence(s) but only ${_n_strict} in the strict single-line \"\${path.module}/…\" form. The remainder render into user_data while the extractor cannot see them, so the evidence digest would not move when they change. Offending site(s), as line:content in ${module_tf}:"
    _nonstrict_file_sites | sed 's/^/  /'
    echo "git_data_rung2_user_data_sha256: restore the canonical form, or extend this gate deliberately. Fail-closed."
    return 1
  fi

  local _n_payloads=0
  while IFS= read -r _f; do
    [[ -n "$_f" ]] || continue
    if [[ ! -r "${module_dir}/${_f}" ]]; then
      echo "git_data_rung2_bound_files: ABORT — ${module_tf} references payload '${_f}', but '${module_dir}/${_f}' cannot be read (absent, or present and unreadable). That payload renders into user_data, so hashing without it would bind the evidence to fewer files than ship. Fail-closed."
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
    echo "git_data_rung2_bound_files: ABORT — the payload extraction from ${module_tf} resolved only ${_n_payloads} payload(s); ship binds 9. The extraction drifted, or bindings were removed. If the payload set legitimately grew or shrank, the floor literal in git_data_rung2_bound_files() is where the new count belongs. Fail-closed."
    return 1
  fi

  _n_uniq="$(printf '%s\n' "${_inputs[@]}" | while IFS= read -r _f; do basename "$_f"; done | LC_ALL=C sort -u | wc -l)"
  if [[ "$_n_uniq" -ne "${#_inputs[@]}" ]]; then
    echo "git_data_rung2_bound_files: ABORT — the ${#_inputs[@]} user_data inputs carry only ${_n_uniq} distinct basenames. The hash is basename-keyed for path invariance, so a collision would silently bind the evidence to fewer files than ship. Fail-closed."
    return 1
  fi

  printf '%s\n' "${_inputs[@]}"
  return 0
}

# Usage:  git_data_rung2_user_data_sha256 <cloud-init-git-data.yml>
#         # prints the 64-hex hash on stdout and returns 0; on failure prints a
#         # fail-closed ABORT diagnostic on stdout and returns 1.
git_data_rung2_user_data_sha256() {
  local cloud_init="${1:-}"
  local _roster _inputs=() _f
  # EVERY refusal lives in the enumeration; this function only hashes what it is handed.
  if ! _roster="$(git_data_rung2_bound_files "$cloud_init")"; then
    printf '%s\n' "$_roster"
    return 1
  fi
  while IFS= read -r _f; do
    [[ -n "$_f" ]] && _inputs+=("$_f")
  done <<<"$_roster"
  if [[ "${#_inputs[@]}" -eq 0 ]]; then
    echo "git_data_rung2_user_data_sha256: ABORT — the bound-file enumeration returned 0 inputs without refusing. Hashing nothing would produce a well-formed digest of an empty set. Fail-closed."
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
#
# THE THREE PUBKEYS ARE NOT AN IDENTITY DIVERGENCE — THEY ARE A CAPABILITY ONE (#8009).
#
# The other five members name WHICH host, WHICH volume, WHICH credential — they select an
# instance and say nothing about what the host is authorized to do. git_transport_pubkey,
# git_provision_pubkey and git_remove_pubkey are different in kind: together they ARE the
# host's SSH authorization map, deciding which identity may invoke the Article 17 erasure
# path. Their presence here is still correct — rung2-rehearsal/rehearsal.tf sets all three
# to one tls_private_key, so the rehearsal genuinely does diverge on them and the evidence
# must declare it — but the reason is not the reason the other five are here.
#
# The consequence is what matters, and it is why this list ALONE is not enough. Because the
# rehearsal collapses the three deliberately, a production edit that collapses them is a
# NO-OP there: boot_complete still emits, no fatal appears, the evidence still records PASS,
# and RUNG2_TEMPLATE_SHA256 moves so the file even looks freshly re-rehearsed. Allowing the
# divergence is correct; inferring from it that the divergence is harmless is not. That
# inference is closed by git_data_authorization_map_gate, a STATIC assertion over the
# production root which needs no rehearsal to run — see the head of this file.
GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST="host_name git_data_volume_id git_data_luks_volume_id doppler_token doppler_config_name git_transport_pubkey git_provision_pubkey git_remove_pubkey"

# ── GUARD 4 (#8043 NFR2): A VOIDED ATTESTATION CANNOT BE MADE TO LOOK FRESH ──────────
#
# THE PROPERTY. git-data-rung2-boot-evidence.env is never MODIFIED in the same change as any
# of the hash-bound files it attests. It may be DELETED in such a change (this batch's own
# shape: the attestation is void, and deleting the file says so), or CREATED by a rehearsal
# PR that touches none of them.
#
# WHY THE GATE BELOW CANNOT SEE THIS ON ITS OWN. git_data_rung2_rehearsal_gate binds the
# evidence to the template by hash, and that binding is what makes a stale attestation
# self-invalidating. It does NOT bind the evidence to a REHEARSAL: its only provenance check
# is that RUNG2_EVIDENCE_URL is shaped like an Actions run URL for this repo — it never
# fetches the run. So a change that edits a payload and hand-edits RUNG2_TEMPLATE_SHA256 to
# the moved digest, leaving the URL alone, is hash-VALID evidence citing a rehearsal that
# never booted the shipped bytes. The hash says "fresh"; the attestation is void; the birth
# route releases. This guard makes that shape a HOLD.
#
# ONE DERIVATION. The roster this guard quantifies over is git_data_rung2_bound_files — the
# SAME walk the hash consumes — so the set the guard watches cannot drift from the set the
# digest binds. That is the reason the enumeration was split out of the hash function.
#
# TWO ARMS, ONE FUNCTION, ONE INTERSECTION.
#
#   birth  (ARM 1, BLOCKING) — wired INSIDE git_data_rung2_rehearsal_gate, so every caller
#          of that gate gets it for free: the birth job (apply-web-platform-infra.yml
#          git-data-host-create), the rehearsal route, and the CI freshness step. It inspects
#          the ONE commit that last touched the evidence (`git log -1 -- <evidence>`) and
#          HOLDs if that commit also touched any bound file (`git diff-tree --no-commit-id
#          --name-only -r --root -m <sha>`). `--root` is load-bearing: without it a root
#          commit diffs as NOTHING, so the one commit that provably touched all fourteen
#          files would intersect as empty. `-m` makes a merge commit diff against each
#          parent rather than as nothing, which over-approximates toward HOLD.
#   range  (ARM 2, ADVISORY) — the same intersection over `git diff --name-only
#          --diff-filter=AM <range>`, for a CI step that sees the whole PR before it merges.
#          A DELETION of the evidence is the permitted shape and is deliberately outside the
#          filter. It runs in infra-validation.yml's deploy-script-tests job, which is not a
#          required check — a visible red, not a merge gate.
#
# FAIL-CLOSED ON EVERYTHING IT CANNOT MEASURE, and every such case is NAMED, because "could
# not measure" and "measured clean" must never share a message:
#   - a SHALLOW checkout (`git rev-parse --is-shallow-repository` = true). Provenance cannot
#     be read from a depth-1 clone, and actions/checkout is depth-1 unless told otherwise.
#     This is what makes forgetting `fetch-depth: 0` on the birth job fail CLOSED (a HOLD
#     naming the shallow clone) rather than open (a pass over history it could not see).
#   - the evidence has no commit at all (untracked, or never committed): there is no
#     provenance to read. This is also what an operator hits running the gate on a freshly
#     downloaded evidence file BEFORE committing it — commit it alone, then re-run.
#   - the evidence differs from its committed state (a working-tree edit): the commit that
#     `git log` names is not the bytes the gate is reading.
#   - a range whose base does not resolve — including the all-zeros branch-create sentinel
#     that `github.event.before` carries on a first push. `git diff` against it FAILS and
#     prints nothing, which a naive reader takes for "no changes". It is a HOLD, and it is
#     worded so it cannot be mistaken for the empty-diff pass.
#   - a roster below its structural floor. The enumeration yields at least 11 entries by
#     construction (template + main.tf + the 9-payload floor), so fewer means the derivation
#     itself broke — and an empty roster intersects as empty, which would be a fail-open.
#   - a bound file outside the evidence's repository (no shared toplevel): the paths cannot
#     be compared, so nothing was measured.
#
# COMPARED BY REPO-RELATIVE PATH, derived from `git rev-parse --show-toplevel` of the
# evidence's own directory and each input's PHYSICAL path — never from the caller's cwd or
# `--show-prefix` of wherever the caller happens to stand. Production calls this with
# ${GITHUB_WORKSPACE}/… ; the suite calls it from a temp dir; a laptop calls it from anywhere.
#
# RESIDUAL, STATED SO NOBODY READS THIS AS A PROOF. ARM 1 inspects ONE commit. A PR that
# edits a bound file in commit A and the hash in commit B and lands by REBASE-MERGE (all
# three merge methods are enabled on this repo) presents an evidence commit touching only
# the evidence, and passes ARM 1; only ARM 2 sees it, pre-merge, and ARM 2 is advisory.
# Closing that requires resolving the run RUNG2_EVIDENCE_URL names and binding its head SHA
# — #8010's scope, not this guard's. This is the structural mitigation for the single-commit
# shape (squash, the one-shot pipeline's default), and it says so.
#
# Usage:  git_data_rung2_evidence_provenance_gate <cloud-init> <evidence> [birth]
#         git_data_rung2_evidence_provenance_gate <cloud-init> <evidence> range <rev>...
#         # 0=PASS, 1=HOLD. One line on stdout naming the verdict and its reason. <rev>... is
#         # handed to `git diff` verbatim: `origin/main...HEAD`, or `<before> HEAD`.

# _git_data_repo_rel <path> <toplevel> — the repo-relative form of <path>, whose DIRECTORY
# must exist (the file itself need not: a deleted evidence file still has a repo path).
# Physical (`cd -P`) so `${module_dir}/../../name` and a symlinked checkout both normalise
# to what git prints. Returns 1 when <path> is not under <toplevel>.
_git_data_repo_rel() {
  local _p="$1" _top="$2" _d _full
  _d="$(cd -P "$(dirname "$_p")" 2>/dev/null && pwd -P)" || return 1
  [[ -n "$_d" && "${_d}/" == "${_top}/"* ]] || return 1
  _full="${_d}/$(basename "$_p")"
  # Parameter expansion, not sed: the toplevel is a path, and a path is not a regex.
  printf '%s\n' "${_full#"${_top}"/}"
}

git_data_rung2_evidence_provenance_gate() {
  local cloud_init="${1:-}" evidence="${2:-}" mode="${3:-birth}"
  local _me="git_data_rung2_evidence_provenance_gate"
  local _n=$#
  if [[ "$_n" -ge 3 ]]; then shift 3; else shift "$_n"; fi   # "$@" is now <rev>... (range only)

  if [[ -z "$cloud_init" || ! -f "$cloud_init" ]]; then
    echo "${_me}: HOLD — cloud-init template missing or not supplied ('${cloud_init}'). Fail-closed: with no template there is no bound-file roster to compare against."
    return 1
  fi
  if [[ -z "$evidence" ]]; then
    echo "${_me}: HOLD — no evidence path supplied. Fail-closed."
    return 1
  fi
  case "$mode" in
    birth|range) ;;
    *) echo "${_me}: HOLD — unknown mode '${mode}' (expected 'birth' or 'range'). Fail-closed: a misspelt arm must not select the more permissive one."; return 1 ;;
  esac

  # THE ROSTER, from the one derivation. Every ABORT in the enumeration is a HOLD here.
  local _roster _bound=() _f
  if ! _roster="$(git_data_rung2_bound_files "$cloud_init")"; then
    echo "${_me}: HOLD — the bound-file roster could not be derived, so no provenance was measured. ${_roster}"
    return 1
  fi
  while IFS= read -r _f; do
    [[ -n "$_f" ]] && _bound+=("$_f")
  done <<<"$_roster"
  if [[ "${#_bound[@]}" -lt 11 ]]; then
    echo "${_me}: HOLD — the derived bound-file roster has only ${#_bound[@]} entries; the enumeration yields at least 11 by construction (template + main.tf + the 9-payload floor). The derivation is broken, and an empty roster intersects as empty — which would release. Fail-closed."
    return 1
  fi

  # THE REPOSITORY, from the evidence's own directory — never the cwd.
  local _ev_dir _top
  _ev_dir="$(dirname "$evidence")"
  if [[ ! -d "$_ev_dir" ]]; then
    echo "${_me}: HOLD — the evidence directory '${_ev_dir}' does not exist, so there is no repository to read provenance from. Fail-closed."
    return 1
  fi
  if ! _top="$(git -C "$_ev_dir" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$_top" ]]; then
    echo "${_me}: HOLD — '${_ev_dir}' is not inside a git work tree, so the evidence has no readable provenance. Fail-closed."
    return 1
  fi
  local _shallow
  _shallow="$(git -C "$_top" rev-parse --is-shallow-repository 2>/dev/null || echo unknown)"
  if [[ "$_shallow" != "false" ]]; then
    echo "${_me}: HOLD — SHALLOW CHECKOUT (is-shallow-repository=${_shallow}). Provenance cannot be read from a clone that does not carry the commit history; actions/checkout is depth-1 unless the step sets fetch-depth: 0. Fail-closed rather than passing over history this gate could not see."
    return 1
  fi

  # REPO-RELATIVE PATHS for the evidence and every bound file.
  local _ev_rel _b _rel _bound_rel=()
  if ! _ev_rel="$(_git_data_repo_rel "$evidence" "$_top")"; then
    echo "${_me}: HOLD — the evidence path '${evidence}' is outside the repository at ${_top}. Fail-closed."
    return 1
  fi
  for _b in "${_bound[@]}"; do
    if ! _rel="$(_git_data_repo_rel "$_b" "$_top")"; then
      echo "${_me}: HOLD — bound file '${_b}' is outside the evidence's repository (${_top}), so its provenance cannot be compared with the evidence's. Nothing was measured. Fail-closed."
      return 1
    fi
    _bound_rel+=("$_rel")
  done

  # THE CHANGED SET, per arm.
  local _changed="" _sha=""
  if [[ "$mode" == "birth" ]]; then
    if [[ ! -f "$evidence" ]]; then
      echo "${_me}: HOLD — no evidence file at ${evidence}. Fail-closed."
      return 1
    fi
    # UNTRACKED and DIRTY are told apart, because their remedies differ: an untracked file
    # is the operator running the gate on a freshly downloaded evidence file before the
    # commit (commit it alone, then re-run); a dirty tracked file is an edit on top of a
    # commit (revert it, or land it alone). Both are refused.
    if [[ -z "$(git -C "$_top" ls-files -- "$_ev_rel" 2>/dev/null)" ]]; then
      echo "${_me}: HOLD — ${_ev_rel} is not tracked, so no commit touches it and its provenance cannot be read. Commit the evidence in a commit that touches ONLY the evidence, then re-run. Fail-closed."
      return 1
    fi
    if [[ -n "$(git -C "$_top" status --porcelain -- "$_ev_rel" 2>/dev/null)" ]]; then
      echo "${_me}: HOLD — ${_ev_rel} differs from its committed state (an uncommitted edit). The bytes this gate would read are not the bytes any commit attests, so there is no provenance to check. Revert the edit, or land it in a commit that touches ONLY the evidence, then re-run. Fail-closed."
      return 1
    fi
    _sha="$(git -C "$_top" log -1 --format=%H -- "$_ev_rel" 2>/dev/null || true)"
    if [[ ! "$_sha" =~ ^[0-9a-f]{40}$ ]]; then
      echo "${_me}: HOLD — no commit touches ${_ev_rel} (git log -1 returned '${_sha}'), so its provenance cannot be read. Fail-closed."
      return 1
    fi
    if ! _changed="$(git -C "$_top" diff-tree --no-commit-id --name-only -r --root -m --no-renames "$_sha" 2>/dev/null)"; then
      echo "${_me}: HOLD — could not list the files touched by ${_sha}, the commit that last modified ${_ev_rel}. Fail-closed."
      return 1
    fi
  else
    if [[ "$#" -eq 0 ]]; then
      echo "${_me}: HOLD — range mode was called with no range. Fail-closed: an absent range is not an empty diff."
      return 1
    fi
    local _rev
    for _rev in "$@"; do
      if [[ "$_rev" == *0000000000000000000000000000000000000000* ]]; then
        echo "${_me}: HOLD — the range names the all-zeros branch-create sentinel ('${_rev}'), so the base is unresolvable. \`git diff\` against it fails and prints nothing, which is NOT an empty diff. Fail-closed."
        return 1
      fi
    done
    if ! _changed="$(git -C "$_top" diff --name-only --diff-filter=AM --no-renames "$@" -- 2>/dev/null)"; then
      echo "${_me}: HOLD — the range '$*' does not resolve in ${_top} (a missing base, an unfetched ref, or a merge base a shallow history cannot reach). Nothing was measured. Fail-closed."
      return 1
    fi
    local _ev_in_range=0 _c
    while IFS= read -r _c; do
      [[ "$_c" == "$_ev_rel" ]] && _ev_in_range=1
    done <<<"$_changed"
    if [[ "$_ev_in_range" -eq 0 ]]; then
      echo "${_me}: PASS — ${_ev_rel} is untouched (not added or modified) in range '$*'; a deletion is the permitted shape and is not in the filter. Bound-file edits without an evidence edit are the STALE EVIDENCE case, which the rehearsal gate's hash check reports."
      return 0
    fi
  fi

  # THE INTERSECTION. Same loop for both arms.
  local _hits="" _c
  while IFS= read -r _c; do
    [[ -n "$_c" ]] || continue
    for _rel in "${_bound_rel[@]}"; do
      [[ "$_c" == "$_rel" ]] && _hits+="${_c} "
    done
  done <<<"$_changed"
  if [[ -n "$_hits" ]]; then
    if [[ "$mode" == "birth" ]]; then
      echo "${_me}: HOLD — VOIDED ATTESTATION. ${_ev_rel} was last modified in commit ${_sha}, which also changed hash-bound input(s): ${_hits}. An evidence file edited in the same change as the bytes it attests is not a rehearsal record of those bytes — the rehearsal ran on the bytes BEFORE the edit, if it ran at all — and the URL-shape check cannot tell the difference. The permitted shapes are: delete the evidence in a change that edits bound files (the birth then HOLDs for lack of evidence, honestly), or create it in a rehearsal change that edits none. Re-run the rung-2 rehearsal against the current tree and land its evidence in its own commit. Fail-closed."
    else
      echo "${_me}: HOLD — VOIDED ATTESTATION. Range '$*' adds or modifies ${_ev_rel} AND changes hash-bound input(s): ${_hits}. An evidence file edited alongside the bytes it attests is not a rehearsal record of those bytes. Either delete the evidence in this change (the birth then HOLDs honestly) or land the rehearsal's evidence in its own change that touches none of the bound files."
    fi
    return 1
  fi
  if [[ "$mode" == "birth" ]]; then
    echo "${_me}: PASS — ${_ev_rel} was last modified in commit ${_sha}, which touched none of the ${#_bound_rel[@]} hash-bound inputs."
  else
    echo "${_me}: PASS — range '$*' modifies ${_ev_rel} and none of the ${#_bound_rel[@]} hash-bound inputs (a rehearsal-PR shape)."
  fi
  return 0
}

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
      echo "git_data_rung2_rehearsal_gate: HOLD — ${evidence} declares that the rehearsal diverged from production on '${_tok}', which is not a declared-divergent render var. The permitted set is not homogeneous: five members are identity-shaped (they name WHICH host, volume or credential), while the three pubkeys are a CAPABILITY divergence — they are the host's SSH authorization map, and the rehearsal collapses them onto one key by design (#8009). The evidence hash binds 13 files (the template, the render module's own .tf files, and the nine file()-bound payloads); it does NOT bind templatefile arguments, so a divergence here yields hash-valid evidence for a boot that is not the boot production would get. Permitted: ${GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST// /, }. Fail-closed."
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

  # ── GUARD 4, ARM 1 (#8043 NFR2): the evidence's own provenance, checked AFTER the hash ──
  #
  # A hash match says the evidence names the bytes that would ship. It does not say a
  # rehearsal ever booted them: a payload edit plus a hand-edited RUNG2_TEMPLATE_SHA256 in the
  # same commit matches perfectly. So the last question is who wrote the evidence — the ONE
  # commit that last touched it must have touched none of the inputs it attests.
  #
  # AFTER the hash, deliberately. A stale hash and a voided attestation are different defects
  # with different remedies; the hash check's STALE EVIDENCE message is the one an ordinary
  # payload PR should see, and this arm speaks only once the hash has nothing left to say —
  # which is exactly when the forged shape would otherwise release. Every refusal below is
  # fail-closed and named (shallow clone, uncommitted evidence, unresolvable commit); see the
  # function's header for the full list and for the rebase-merge residual that is #8010's.
  local _prov_out
  if ! _prov_out="$(git_data_rung2_evidence_provenance_gate "$cloud_init" "$evidence" birth)"; then
    echo "git_data_rung2_rehearsal_gate: HOLD — the evidence is hash-valid but its provenance refuses it. ${_prov_out}"
    return 1
  fi

  echo "git_data_rung2_rehearsal_gate: RELEASED — rung-2 boot evidence at ${evidence} attests PASS for user_data sha256 ${live_sha} (${url}); declared render-var divergence: ${divergence}; provenance: ${_prov_out#*: }. NOTE: this gate checks the rung-2 boot rehearsal ONLY. It says nothing about the other ADR-149 checklist items, which the sentinel gate's own message enumerates."
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────
# git_data_authorization_map_gate — CPO condition C1 / #8009.
#
# THE PROPERTY. On the production render path the three SSH forced-command slots on the
# git-data host — transport, provision, erase — are held by three pairwise-distinct public
# keys, AND the private half of each is published under the Doppler name whose consumer
# holds exactly that authority.
#
# The second clause is not decoration. Distinctness of the PUBLIC halves is satisfiable
# while the map is fully inverted: three distinct keys can render into the template while
# the app's transport secret carries the erase key. A guard naming only the first clause
# certifies something other than what its own HOLD message claims.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. It is a STATIC assertion over the Terraform
# source: it proves what the production root RENDERS. It does not, and cannot, prove what
# the live host HONOURS — that is a property of a running sshd and of files the host owns,
# and it is why #8009's siblings (the authorized_keys2 fall-through, the hooksPath
# ownership, the AcceptEnv pin) are tracked separately rather than closed here. No live
# host exists to probe: birthing it is what this gate stands in front of.
#
# WHY STATIC IS THE RIGHT SHAPE ANYWAY. The rung-2 rehearsal collapses all three slots onto
# one tls_private_key by design, so it never exercised this map — and because they were
# ALREADY identical there, a production edit collapsing them is a NO-OP in the rehearsal:
# boot_complete still emits, no fatal appears, the evidence still records PASS, and
# RUNG2_TEMPLATE_SHA256 moves so the file even looks freshly re-rehearsed. Only a static
# assertion over the production root can see it, and it needs no paid rehearsal to run.
#
# SCOPING IS POSITIVE (ADR-149 D3). The root is derived from the argument, and the *.tf glob
# is NON-RECURSIVE. That is what keeps rung2-rehearsal/rehearsal.tf — which collapses the
# three slots deliberately — outside the assembly, without naming it in an exclusion list
# that would rot the moment a second such root appeared.
#
# Usage:  git_data_authorization_map_gate <cloud-init-git-data.yml>
# Exit:   0 RELEASED | 1 HOLD (property violated) | 2 ABORT (cannot measure — fail-closed)
#
# ABORT IS NOT HOLD. A gate that cannot parse its inputs has measured nothing, and reporting
# that as a clean release is the exact defect class this gate exists to close. Every
# unparseable, ambiguous or unexpectedly-shaped input returns 2 with a message naming which.
git_data_authorization_map_gate() {
  local cloud_init="${1:-}"

  # THE THREE AUTHORITIES, HARDCODED FROM THE DESIGN — never parsed back out of
  # the artifact under test. Deriving this set from the template would make the assertion
  # S == S. The forced-command script name and the Doppler secret name are anchored to a
  # THIRD artifact: apps/web-platform/server/git-data-replication.ts, whose header prose
  # documents GIT_PROVISION_SSH_PRIVATE_KEY -> git-data-provision.sh and the transport
  # equivalent. Neither file under test is the authority for this table.
  #
  # WHERE EACH AUTHORITY IS ACTUALLY DESIGNED, stated precisely because a false citation
  # propagates further than a missing one: ADR-068 designs TRANSPORT and PROVISION (its
  # CTO-ruling amendment introduces the provision key as "A SECOND ED25519 key"). It does NOT
  # design the ERASE authority — it names GIT_REMOVE_SSH_PRIVATE_KEY exactly once, inside a
  # blast-radius argument for the scoped Doppler token, and git-data-remove.sh not at all. The
  # erase authority is designed in git-data-replication.ts's removeGitDataRepo, which is also
  # the third artifact this table is anchored to, and ships as a payload per ADR-152.
  local -a _authorities=(
    "transport|git-data-transport-wrapper.sh|GIT_TRANSPORT_SSH_PRIVATE_KEY"
    "provision|git-data-provision.sh|GIT_PROVISION_SSH_PRIVATE_KEY"
    "remove|git-data-remove.sh|GIT_REMOVE_SSH_PRIVATE_KEY"
  )
  # The literal 3 lives here and nowhere else in this function: it must agree across the
  # slot count, the terminal count, the resource count and the secret count, and four
  # independent 3s is four places to drift.
  local _n_authorities="${#_authorities[@]}"

  if [[ -z "$cloud_init" || ! -r "$cloud_init" ]]; then
    echo "git_data_authorization_map_gate: ABORT — cloud-init template missing or not supplied ('${cloud_init}'). Fail-closed: with no template there is no authorization map to read."
    return 2
  fi

  local root module_tf
  root="$(cd "$(dirname "$cloud_init")" && pwd)" || {
    echo "git_data_authorization_map_gate: ABORT — cannot resolve the Terraform root containing '${cloud_init}'."
    return 2
  }
  module_tf="${root}/modules/git-data-userdata/main.tf"
  if [[ ! -r "$module_tf" ]]; then
    echo "git_data_authorization_map_gate: ABORT — cannot read ${module_tf}. The render module is where the templatefile argument map lives; if it moved, this gate and every consumer of it must move with it. Fail-closed."
    return 2
  fi

  # M14 — Terraform MERGES *override.tf / *override.tf.json over the primary config at load
  # time. This gate reads the files it is handed, so an override re-pointing a local at
  # apply time is invisible to it. Refuse rather than release a verdict about a
  # configuration that is not the one Terraform will load.
  local _ovr
  for _ovr in "$root"/*override.tf "$root"/*override.tf.json; do
    [[ -e "$_ovr" ]] || continue
    echo "git_data_authorization_map_gate: ABORT — an override file is present in the root ($(basename "$_ovr")). Terraform merges *override.tf over the primary configuration, so the authorization map this gate can read is not the map that would be applied. Fail-closed."
    return 2
  done

  # A ROOT *.tf.json IS LOADED EXACTLY AS A *.tf, AND THIS GATE CANNOT PARSE JSON.
  # Reading only *.tf here while git_data_rung2_user_data_sha256 — in this same file —
  # globs both extensions is an asymmetry a second module can hide in: a `module` block
  # declared in extra.tf.json is invisible to the single-instance check below while
  # Terraform renders it happily. Refuse rather than release a verdict about a
  # configuration this gate has only partly read.
  local _json
  for _json in "$root"/*.tf.json; do
    [[ -e "$_json" ]] || continue
    echo "git_data_authorization_map_gate: ABORT — the root contains $(basename "$_json"). Terraform loads *.tf.json exactly as it loads *.tf, and this gate parses HCL only — so the authorization map it can read is a strict subset of the one that would be applied. Fail-closed."
    return 2
  done

  # ── Link 1: the authorized_keys slots ───────────────────────────────────────────────
  #
  # Extracted as the CONTIGUOUS non-blank run inside the write_files entry for
  # /home/git/.ssh/authorized_keys. The block is read whole rather than grepped for
  # `command=` lines, because M26 is a line with NO `command=`: grepping for forced
  # commands cannot see a key that is not one, and that key falls through to the raw
  # `git-shell -c "$SSH_ORIGINAL_COMMAND"` path the transport wrapper exists to replace.
  local _ak_block
  _ak_block="$(awk '
    # `want` IS RESET BY THE NEXT LIST ITEM. Without that it latched forever, so an entry
    # whose content is NOT a `content: |` literal — e.g. the `encoding: b64` +
    # `content: ${...}` shape this same template already uses for its script payloads —
    # made the extractor skip ahead and read the NEXT entry`s block instead. The gate then
    # RELEASED, naming three distinct keys that were not on authorized_keys at all. Zero
    # extraction was already an ABORT; extraction from the WRONG entry was not.
    $0 ~ /^[[:space:]]*-[[:space:]]*path:/ { want=0 }
    $0 ~ /^[[:space:]]*-[[:space:]]*path:[[:space:]]*\/home\/git\/\.ssh\/authorized_keys[[:space:]]*$/ { want=1; next }
    want && $0 ~ /^[[:space:]]*(encoding|content):[[:space:]]*[^|[:space:]]/ { print "__NOT_A_LITERAL_BLOCK__"; exit }
    want && $0 ~ /^[[:space:]]*content:[[:space:]]*\|[[:space:]]*$/ { inblock=1; next }
    inblock {
      # The block ends at the next YAML key at the entry indent level (owner:, permissions:)
      # or at the next list item.
      if ($0 ~ /^[[:space:]]*(owner|permissions|defer|append|encoding):/ || $0 ~ /^[[:space:]]*-[[:space:]]/) { exit }
      if ($0 ~ /^[[:space:]]*$/) next
      print
    }
  ' "$cloud_init")"

  if [[ "$_ak_block" == "__NOT_A_LITERAL_BLOCK__" ]]; then
    echo "git_data_authorization_map_gate: ABORT — the /home/git/.ssh/authorized_keys entry in ${cloud_init} does not use a literal \`content: |\` block (it is base64, an interpolation, or another encoding). This gate reads the authorization map as text; it cannot see through an encoded payload, and releasing here would certify a map it never read. Fail-closed."
    return 2
  fi
  if [[ -z "$_ak_block" ]]; then
    echo "git_data_authorization_map_gate: ABORT — found no /home/git/.ssh/authorized_keys content block in ${cloud_init}. Extraction yielded nothing, which is a broken instrument, not an empty authorization map. Fail-closed."
    return 2
  fi

  # EXACTLY ONE write_files ENTRY MAY WRITE THAT PATH. The extractor above stops at the end
  # of the FIRST matching entry, and cloud-init applies write_files IN ORDER — so a second
  # entry for the same path later in the file is what actually lands on the host, and the
  # gate would have certified the first one. Measured rc=0 with a second entry granting the
  # transport key the erase command.
  # NOTHING ELSE IN THE TEMPLATE MAY TOUCH THAT FILE. write_files is not the only statement
  # that writes it: `runcmd` runs AFTER write_files, so one appended line there adds a key
  # the gate's block-scoped read can never see. The property is "what this template puts on
  # authorized_keys", not "what the first write_files entry says".
  if grep -nE '/home/git/\.ssh/authorized_keys' "$cloud_init" \
     | grep -vE ':[[:space:]]*-[[:space:]]*path:' | grep -qvE ':[[:space:]]*#'; then
    echo "git_data_authorization_map_gate: HOLD — ${cloud_init} references /home/git/.ssh/authorized_keys outside its write_files path declaration (a runcmd, a bootcmd, or another statement). cloud-init runs runcmd AFTER write_files, so any such statement decides the final authorization map and this gate reads only the write_files block."
    return 1
  fi

  local _n_ak
  _n_ak="$(grep -cE '^[[:space:]]*-[[:space:]]*path:[[:space:]]*/home/git/\.ssh/authorized_keys[[:space:]]*$' "$cloud_init" || true)"
  if [[ "${_n_ak:-0}" -ne 1 ]]; then
    echo "git_data_authorization_map_gate: HOLD — ${_n_ak} write_files entries target /home/git/.ssh/authorized_keys; exactly 1 is canonical. cloud-init applies write_files in order, so a later entry overwrites the map this gate read."
    return 1
  fi

  # OWNER AND PERMISSIONS ARE PART OF THE MAP. The extractor terminates ON the `owner:` line,
  # so neither was ever in the gate's view. A world-writable or group-writable authorized_keys
  # is an authorization map anything on the host can rewrite; sshd's StrictModes refuses it at
  # runtime, which is a backstop this gate neither knows about nor should depend on.
  local _ak_meta
  _ak_meta="$(awk '
    $0 ~ /^[[:space:]]*-[[:space:]]*path:[[:space:]]*\/home\/git\/\.ssh\/authorized_keys[[:space:]]*$/ { want=1; next }
    want && $0 ~ /^[[:space:]]*(owner|permissions):/ { print; n++ }
    want && n >= 2 { exit }
  ' "$cloud_init")"
  # (#8043 F7) ROOT-OWNED. This arm used to require `owner: git:git` on the rationale that "an
  # authorization map owned by anyone else is either unreadable by sshd or writable by a second
  # principal" — MEASURED FALSE in the pinned ubuntu-24.04 image: a `root:root 0644` map inside a
  # `root:git 0750` .ssh authenticates the git key, and StrictModes permits uid 0. What git:git
  # actually meant was that the CONSTRAINED PRINCIPAL owned its own authorization map and could
  # rewrite it in place. The mode is 0644, NOT 0600: sshd opens the file under the target
  # user's uid, so `root:root 0600` is "Permission denied" (measured) and every push is refused.
  if ! grep -qE "^[[:space:]]*owner:[[:space:]]*root:root[[:space:]]*$" <<< "$_ak_meta"; then
    echo "git_data_authorization_map_gate: HOLD — the authorized_keys write_files entry is not owned by root:root. The forced commands run as the git user, and a map the git account owns is a map the constrained principal can rewrite in place — the shortest persistence path for code execution as git (#8043 F7). sshd reads the file as the git uid, so root ownership at 0644 stays readable."
    return 1
  fi
  if ! grep -qE "^[[:space:]]*permissions:[[:space:]]*'0644'[[:space:]]*$" <<< "$_ak_meta"; then
    echo "git_data_authorization_map_gate: HOLD — the authorized_keys write_files entry does not declare permissions '0644'. Under root ownership 0600 is UNREADABLE by sshd (it opens the map as the target user; measured 'Permission denied' in the pinned image) and refuses every push; any group- or world-WRITABLE mode makes the map rewritable by a second principal. 0644 is the one mode that is both readable by the git uid and writable by root only."
    return 1
  fi

  local _ak_lines
  _ak_lines="$(printf '%s\n' "$_ak_block" | wc -l | tr -d ' ')"
  if [[ "$_ak_lines" -ne "$_n_authorities" ]]; then
    echo "git_data_authorization_map_gate: HOLD — the authorized_keys block holds ${_ak_lines} non-blank line(s); ADR-068 pins exactly ${_n_authorities}, one per authority. A line beyond the three is an SSH identity nobody's forced command fences; a line short of them is a missing authority."
    return 1
  fi

  # Each line must be a forced command with the canonical option set. M26 is a line with no
  # `command=` at all; M27 is an extra option appended to one — invisible to a script-name
  # assertion, and live the moment anything sets PermitUserEnvironment yes.
  # AN EXACT-MATCH CONTRACT ACROSS A HASH-BOUND BOUNDARY. This literal must equal the option
  # string in cloud-init-git-data.yml's authorized_keys block. That file is hash-bound and this
  # one is not, so a legitimate future option addition reddens this gate BEFORE the template can
  # be changed — which is the intended fail-closed direction (an added option is exactly M27),
  # but it means the fix is deliberate co-editing, not a surprise. Widening this to a
  # subset-match would forfeit M27 entirely.
  local _canon_opts='no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty'
  declare -A _slot_var=()          # script name -> template variable name
  local _line _script _tvar
  while IFS= read -r _line; do
    [[ -n "$_line" ]] || continue
    if [[ ! "$_line" =~ ^[[:space:]]*command=\"/usr/local/bin/([A-Za-z0-9._-]+)\",([^[:space:]]*)[[:space:]]+\$\{([A-Za-z0-9_]+)\}[[:space:]]*$ ]]; then
      echo "git_data_authorization_map_gate: HOLD — an authorized_keys line is not a canonical forced-command entry terminating in a single \${…} interpolation: '${_line}'. A key on this file that no forced command fences reaches the raw git-shell path, which is the unfenced surface git-data-transport-wrapper.sh exists to replace."
      return 1
    fi
    _script="${BASH_REMATCH[1]}"
    if [[ "${BASH_REMATCH[2]}" != "$_canon_opts" ]]; then
      echo "git_data_authorization_map_gate: HOLD — the forced-command options for ${_script} are '${BASH_REMATCH[2]}', not the canonical '${_canon_opts}'. An added option is invisible to a script-name assertion and becomes live the moment sshd permits it — environment= plus PermitUserEnvironment is a rooted rm -rf assembled out of two individually-invisible edits."
      return 1
    fi
    _tvar="${BASH_REMATCH[3]}"
    _slot_var["$_script"]="$_tvar"
  done <<< "$_ak_block"

  # Every authority the design names must have a slot, and there must be no slot beyond them.
  local _entry _auth _dopname
  for _entry in "${_authorities[@]}"; do
    IFS='|' read -r _auth _script _dopname <<< "$_entry"
    if [[ -z "${_slot_var[$_script]:-}" ]]; then
      echo "git_data_authorization_map_gate: HOLD — no authorized_keys slot pins /usr/local/bin/${_script} (the ${_auth} authority). ADR-068 pins one forced command per authority."
      return 1
    fi
  done
  if [[ "${#_slot_var[@]}" -ne "$_n_authorities" ]]; then
    echo "git_data_authorization_map_gate: HOLD — the authorized_keys block resolves to ${#_slot_var[@]} distinct forced command(s); ADR-068 pins ${_n_authorities}. Two slots naming one script is a duplicate authority, not a distinct one."
    return 1
  fi

  # ── Link 2: the templatefile() argument map ─────────────────────────────────────────
  #
  # Links 2 and 3 are pure identity maps (git_transport_pubkey = var.git_transport_pubkey;
  # git_transport_pubkey = local.git_transport_pubkey). You TRAVERSE an identity map; you do
  # not assert on it. Five independent per-link assertions would be five extractors, five
  # normalisers and five messages over three files — and would still miss a hop nobody
  # anticipated. Resolving instead means an unanticipated hop BREAKS THE WALK rather than
  # slipping past five checks, and the diagnostic names the hop at which two chains met.
  local _mod_src
  if ! _mod_src="$(_git_data_hcl_nocomment "$module_tf")"; then
    echo "git_data_authorization_map_gate: ABORT — ${module_tf} carries an HCL // or /* comment outside a string. This gate strips only # comments, so it cannot be trusted to have read the file as Terraform would. Fail-closed."
    return 2
  fi

  # SCOPED TO THE templatefile() CALL, NOT TO main.tf. Scanning the whole module file for
  # `X = var.Y` was last-wins, so a trailing `locals { git_remove_pubkey = var.git_remove_pubkey }`
  # restored the identity binding AFTER the real map entry had been permuted, and the gate
  # RELEASED with the render collapsed (measured). The map that renders is the one inside
  # templatefile(); nothing else in the file participates.
  # THE GATE MUST READ THE TEMPLATE THE MODULE ACTUALLY RENDERS. Nothing tied the file
  # passed in to the path inside templatefile(), so link 1 and link 2 were joined by
  # assumption: re-point the module at cloud-init-git-data-v2.yml and the gate happily
  # certifies the map in the file it was handed while the host boots the other one. The
  # sibling parity test already binds the READINESS gate's path this way; the binding was
  # never extended to this gate.
  local _tpl_ref _ci_base
  _ci_base="$(basename "$cloud_init")"
  _tpl_ref="$(grep -oE 'templatefile\("\$\{path\.module\}/[^"]+"' <<< "$_mod_src" | head -1 | sed 's|.*/||; s|"$||')"
  if [[ -z "$_tpl_ref" ]]; then
    echo "git_data_authorization_map_gate: ABORT — could not resolve the template path from ${module_tf}'s templatefile( call, so the gate cannot confirm it is reading the file the module renders. Fail-closed."
    return 2
  fi
  if [[ "$_tpl_ref" != "$_ci_base" ]]; then
    echo "git_data_authorization_map_gate: HOLD — the render module renders '${_tpl_ref}', but this gate was pointed at '${_ci_base}'. It would have certified an authorization map in a file the host never boots."
    return 1
  fi

  local _tf_map
  # `[(]`, NOT `\(`. This pattern is a DYNAMIC awk regex (`$0 ~ open_re`), and the two awk
  # implementations disagree about a backslash-escaped paren: mawk treats `\(` as a literal
  # paren, while gawk STRIPS the backslash and then cannot compile the bare `(` —
  # `fatal: invalid regexp: Unmatched ( or \(`. Ubuntu ships mawk, GitHub runners ship gawk,
  # so `\(` passes every local run and makes the gate ABORT on every CI run: it could never
  # RELEASE, which also means the birth-dispatch interlock could never pass. A bracket
  # expression is literal in both engines. Pinned by the gawk-hostile-escape arm in the suite.
  _tf_map="$(_git_data_hcl_block "$_mod_src" 'templatefile[(]')"
  if [[ -z "$_tf_map" ]]; then
    echo "git_data_authorization_map_gate: ABORT — no templatefile( call found in ${module_tf}. The render module is where the argument map lives; extraction yielded nothing, which is a broken instrument, not an empty map. Fail-closed."
    return 2
  fi
  declare -A _tvar_modvar=()       # template variable -> module variable
  while IFS= read -r _line; do
    if [[ "$_line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*var\.([A-Za-z0-9_]+)[[:space:]]*$ ]]; then
      if [[ -n "${_tvar_modvar[${BASH_REMATCH[1]}]:-}" ]]; then
        echo "git_data_authorization_map_gate: ABORT — the templatefile argument map in ${module_tf} binds '${BASH_REMATCH[1]}' more than once. Terraform would reject a duplicate key, so this gate is reading something it does not understand rather than a map that could render. Fail-closed."
        return 2
      fi
      _tvar_modvar["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done <<< "$_tf_map"

  # ── Links 3, 4, 5: the root ─────────────────────────────────────────────────────────
  #
  # NON-RECURSIVE by construction — this is the positive scoping of D3. rung2-rehearsal/
  # lives one directory down and collapses all three slots deliberately; a recursive walk
  # would make this gate permanently red, and an exclusion list naming that directory would
  # rot the moment a second such root appeared.
  local _root_src="" _f _one
  local _n_tf=0
  for _f in "$root"/*.tf; do
    [[ -e "$_f" ]] || continue
    if ! _one="$(_git_data_hcl_nocomment "$_f")"; then
      echo "git_data_authorization_map_gate: ABORT — ${_f} carries an HCL // or /* comment outside a string. This gate strips only # comments, so it cannot be trusted to have read the root as Terraform would. Fail-closed."
      return 2
    fi
    _root_src+="$_one"$'\n'
    _n_tf=$((_n_tf + 1))
  done
  if [[ "$_n_tf" -eq 0 ]]; then
    echo "git_data_authorization_map_gate: ABORT — no *.tf files found in ${root}. Extraction yielded nothing, which is a broken instrument, not an empty root. Fail-closed."
    return 2
  fi

  # M15 — exactly ONE module instance renders user_data, and hcloud_server.git_data's
  # user_data is pinned to THAT instance's whole expression. A second
  # module "git_data_userdata_v2" with collapsed arguments, with the server re-pointed at
  # it, leaves this gate reading the block it was told to read and releasing. Pinning the
  # WHOLE base64gzip(module.<label>.rendered) expression — not just the label — is what
  # stops a coalesce() or a conditional slipping a second render in beside it.
  local _n_mod_labels _mod_label
  _n_mod_labels="$(awk '
    /^[[:space:]]*module[[:space:]]+"[A-Za-z0-9_]+"[[:space:]]*\{/ { inmod=1; depth=0 }
    inmod {
      n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m
      if ($0 ~ /source[[:space:]]*=[[:space:]]*"\.\/modules\/git-data-userdata"/) hit=1
      if (depth<=0) { if (hit) c++; inmod=0; hit=0 }
    }
    END { print c+0 }
  ' <<< "$_root_src")"
  if [[ "$_n_mod_labels" -ne 1 ]]; then
    echo "git_data_authorization_map_gate: HOLD — ${_n_mod_labels} module instance(s) in ${root} declare source = \"./modules/git-data-userdata\"; the canonical shape has exactly 1. A second render module is a second authorization map, and this gate would read only the one it was pointed at."
    return 1
  fi
  _mod_label="$(awk '
    /^[[:space:]]*module[[:space:]]+"[A-Za-z0-9_]+"[[:space:]]*\{/ { inmod=1; depth=0; lbl=$0; sub(/^[^"]*"/,"",lbl); sub(/".*$/,"",lbl) }
    inmod {
      n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m
      if ($0 ~ /source[[:space:]]*=[[:space:]]*"\.\/modules\/git-data-userdata"/) hit=1
      if (depth<=0) { if (hit) { print lbl; exit } ; inmod=0; hit=0 }
    }
  ' <<< "$_root_src")"

  # A HERESTRING, NOT A PIPE. `producer | grep -q` under `set -o pipefail` is a FALSE
  # NEGATIVE whenever the match is early and the producer exceeds the 64 KiB pipe buffer:
  # grep -q closes the pipe on first match, the producer takes SIGPIPE (141), and pipefail
  # promotes that to a failing pipeline EVEN THOUGH GREP MATCHED. Measured here — the root
  # source is ~160 KB and git-data.tf sorts early, so this gate HELD on a canonical tree
  # under `set -uo pipefail` while RELEASING under a plain shell. The suite and every CI
  # `run:` block set pipefail, so the shipped behaviour was the broken one. A herestring is
  # backed by a temp file the SHELL owns and reaps, so it cannot take SIGPIPE at all — and it
  # is the idiom this function already uses for the same string at its two `while read` loops.
  # An earlier fix materialized the root by hand instead. That worked, but it put a SECOND
  # representation of one string in the function and made every future `return` owe one of 18
  # cleanup calls with no trap to catch a miss — a standing correctness tax on a fail-closed
  # gate. One mechanism for one string.
  # EXTRACTED, NOT GREPPED. This predicate claims something about hcloud_server.git_data, and
  # a root-wide grep mentions neither the resource type nor its label — so the canonical
  # string parked in ANY unrelated block (an output, a locals, a null_resource trigger)
  # satisfied it while the real server rendered something else entirely. Measured rc=0.
  # Absence of the server is its own ABORT: a rename made the ignore_changes awk below
  # silently vacuous while this grep still matched, and nothing noticed the resource the
  # whole gate is about had ceased to exist.
  local _server_block
  _server_block="$(_git_data_hcl_block "$_root_src" '^resource[[:space:]]+"hcloud_server"[[:space:]]+"git_data"[[:space:]]*\{')"
  if [[ -z "$_server_block" ]]; then
    echo "git_data_authorization_map_gate: ABORT — no resource \"hcloud_server\" \"git_data\" block found in ${root}. Every predicate below is about that server; with it absent or renamed the gate would be certifying a map for a host nothing creates. Fail-closed."
    return 2
  fi
  if ! grep -qE "^[[:space:]]*user_data[[:space:]]*=[[:space:]]*base64gzip\(module\.${_mod_label}\.rendered\)[[:space:]]*$" <<< "$_server_block"; then
    echo "git_data_authorization_map_gate: HOLD — hcloud_server.git_data's own user_data is not exactly base64gzip(module.${_mod_label}.rendered). The gate resolves the authorization map through that module; if the server renders anything else, the map this gate proved is not the map that boots."
    return 1
  fi

  # EXACTLY ONE SERVER MAY RENDER A MODULE. A second hcloud_server fed by a second module —
  # under any source path, so the single-instance check above cannot see it — is a second
  # git-data host whose authorization map this gate never walks. Measured rc=0.
  local _n_rendering
  _n_rendering="$(grep -cE '^[[:space:]]*user_data[[:space:]]*=[[:space:]]*base64gzip\(module\.[A-Za-z0-9_]+\.rendered\)[[:space:]]*$' <<< "$_root_src" || true)"
  if [[ "${_n_rendering:-0}" -ne 1 ]]; then
    echo "git_data_authorization_map_gate: HOLD — ${_n_rendering} resources in ${root} render a module into user_data; exactly 1 is canonical. A second rendering server is a second host with its own authorization map, and this gate walks only the one it was pointed at."
    return 1
  fi

  # M25 — the guard's own premise. ADR-115 bars git-data from the reboot primitive and
  # user_data is ForceNew, so a REPLACE is the only post-birth route by which a re-rendered
  # authorized_keys block reaches the host. An ignore_changes on user_data silently deletes
  # that premise: the map could then drift with no apply able to correct it, and every
  # interlock downstream of this one would be guarding a path nothing travels.
  # THE LIST, NOT ONE LINE. Requiring `ignore_changes` and `user_data` on the same physical
  # line missed the ordinary multi-line list form that `terraform fmt` preserves — and
  # git-data.tf already carries `ignore_changes = [ssh_keys]`, so adding a second element is
  # exactly the edit a person makes. Measured rc=0. This joins the whole extracted server
  # block and matches across newlines instead.
  if tr '\n' ' ' <<< "$_server_block" | grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*\buser_data\b'; then
    echo "git_data_authorization_map_gate: HOLD — hcloud_server.git_data declares lifecycle.ignore_changes on user_data. That deletes this gate's own premise: user_data is ForceNew and ADR-115 bars git-data from the reboot primitive, so a replace is the ONLY route by which a corrected authorization map reaches the host. With it ignored, the map can drift with no apply able to correct it."
    return 1
  fi

  # Link 3 — the module call's pubkey arguments, scoped to the ONE module block M15 pinned.
  local _mod_block
  _mod_block="$(awk -v lbl="$_mod_label" '
    $0 ~ "^[[:space:]]*module[[:space:]]+\"" lbl "\"[[:space:]]*\\{" { inmod=1; depth=0 }
    inmod {
      print
      n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m
      if (depth<=0) exit
    }
  ' <<< "$_root_src")"
  declare -A _modvar_local=()      # module variable -> local name
  while IFS= read -r _line; do
    if [[ "$_line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*local\.([A-Za-z0-9_]+)[[:space:]]*$ ]]; then
      _modvar_local["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done <<< "$_mod_block"

  # Link 4 — the locals. Read from the WHOLE root, not from git-data.tf, which is what makes
  # M23 (a pubkey local moved to a sibling .tf in the same root and re-pointed) visible:
  # Terraform merges locals across every file in the root, so a file-scoped gate would be
  # reading a subset of the configuration that actually applies.
  # SCOPED TO `locals {}` BLOCKS. The previous scan read every line of the root regardless of
  # its enclosing block and was last-wins, so an ordinary diagnostic `output` block naming the
  # three keys silenced a genuine collapse of the real local — measured rc=0 on the headline
  # collapse this gate exists to catch. Root-WIDE is still right (Terraform merges locals
  # across every file in the root, which is what makes a sibling-file relocation visible);
  # root-wide WITHOUT block-scoping is what was wrong.
  declare -A _local_terminal=()    # local name -> tls_private_key.<name>
  declare -A _local_attr=()        # local name -> attribute read
  declare -A _local_rhs=()         # local name -> raw RHS, for diagnostics
  local _locals_src _rhs _lname _nref
  # More than one `locals` block is legal and common, so collect them all.
  _locals_src="$(awk '
    /^[[:space:]]*locals[[:space:]]*\{/ && depth == 0 { inb = 1 }
    inb {
      print
      n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m
      if (depth <= 0) { inb = 0 }
    }
  ' <<< "$_root_src")"
  while IFS= read -r _line; do
    [[ "$_line" =~ ^[[:space:]]*([A-Za-z0-9_]+_pubkey)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
    _lname="${BASH_REMATCH[1]}"
    _rhs="${BASH_REMATCH[2]}"
    if [[ -n "${_local_rhs[$_lname]:-}" ]]; then
      echo "git_data_authorization_map_gate: ABORT — the root binds local '${_lname}' more than once (Terraform would reject that, so this gate is not reading a configuration that could apply). Fail-closed rather than picking a winner."
      return 2
    fi
    _local_rhs["$_lname"]="$_rhs"
    # AMBIGUITY IS NOT A TERMINAL. A compound RHS — a ternary, a coalesce(), a try() — can
    # name several keys, and taking the first match silently picked one at random while the
    # OTHER branch is what renders under the default. Measured: a `var.x ? remove : transport`
    # ternary released with the remove slot carrying the transport key. If the gate cannot say
    # which key wins, it must not say the map is correct.
    _nref="$(grep -o 'tls_private_key\.' <<< "$_rhs" | wc -l | tr -d ' ')"
    if [[ "${_nref:-0}" -gt 1 ]]; then
      echo "git_data_authorization_map_gate: ABORT — local.${_lname} references ${_nref} tls_private_key resources in one expression: ${_rhs}. Which key renders depends on a value this static gate cannot evaluate, so it cannot certify the map. Fail-closed."
      return 2
    fi
    if [[ "$_rhs" =~ tls_private_key\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+) ]]; then
      _local_terminal["$_lname"]="tls_private_key.${BASH_REMATCH[1]}"
      _local_attr["$_lname"]="${BASH_REMATCH[2]}"
    fi
    # PREDICATE 2 RUNS ON EVERY RHS, NOT ONLY WHERE EXTRACTION FAILED. It used to live inside
    # the "no terminal" branch, so any expression that mentioned a tls_private_key at all
    # skipped it — and `coalesce(tls_private_key.git_remove.public_key_openssh, var.emergency)`
    # therefore passed with a variable as a live fallback terminal.
    if [[ "$_rhs" == *var.* || "$_rhs" == *data.* || "$_rhs" == *file\(* || "$_rhs" == *ssh-* ]]; then
      echo "git_data_authorization_map_gate: HOLD — local.${_lname} mixes a NON-RESOURCE terminal into its expression: ${_rhs}. Every slot must terminate at a tls_private_key.<name> this root creates. A variable carrying a default, a data source, a file() or an inline literal can hold any key at all — including another slot's — and no address-distinctness predicate can see it."
      return 1
    fi
  done <<< "$_locals_src"

  # Link 5 — the private-half distribution. This is the half the application actually holds:
  # git-data-replication.ts reads GIT_TRANSPORT_SSH_PRIVATE_KEY for ordinary push and fetch,
  # GIT_PROVISION_SSH_PRIVATE_KEY to provision, and GIT_REMOVE_SSH_PRIVATE_KEY to erase. It
  # is the ONLY edge in the whole map with zero pre-existing coverage: the app-side tests
  # vi.stubEnv the env NAMES with stub values, which proves the app reads the right variable
  # and is structurally incapable of seeing which Terraform resource fills it.
  # KEYED ON (name, project, config) — NOT ON name ALONE, AND NOT LAST-WINS.
  #
  # Keying on the Doppler NAME across the whole root meant two blocks publishing one name
  # collided and the last file in the lexical glob won. Measured: permuting the real `prd`
  # secret to the transport key and adding an innocuous `config = "dev"` mirror of the same
  # name RELEASED the gate — while the `prd` secret, the only one in the birth job's -target
  # list, published the transport key as the app's Art. 17 erasure credential. That is
  # verbatim the inversion link 5 exists to catch.
  #
  # The config matters on its own: the three secrets must land in `prd`, because that is the
  # config the host and the app read. A secret retargeted at `dev` publishes nothing the
  # production app will ever see, and the previous scan could not tell.
  declare -A _secret_terminal=()   # Doppler secret NAME -> tls_private_key.<name>
  declare -A _secret_attr=()
  declare -A _secret_rhs=()
  declare -A _secret_seen=()       # NAME -> count of prd bindings, to refuse duplicates
  local _sec_name _sec_cfg _sec_val _sec_label
  while IFS='|' read -r _sec_label _sec_name _sec_cfg _sec_val; do
    [[ -n "$_sec_name" ]] || continue
    # A stray publisher of any of the three PRIVATE halves under an unexpected name hands the
    # key to whatever reads that name. The authority loop below only ever visits the three
    # known names, so without this it is invisible.
    if [[ "$_sec_val" =~ tls_private_key\.(git_transport|git_provision|git_remove)\.private_key_openssh ]]; then
      case "$_sec_name" in
        GIT_TRANSPORT_SSH_PRIVATE_KEY|GIT_PROVISION_SSH_PRIVATE_KEY|GIT_REMOVE_SSH_PRIVATE_KEY) ;;
        *)
          echo "git_data_authorization_map_gate: HOLD — doppler_secret.${_sec_label} publishes the PRIVATE half of tls_private_key.${BASH_REMATCH[1]} under the name '${_sec_name}', which is outside the three-authority map. Whatever consumer reads that name holds that authority, and no distinctness predicate over the three known names can see it."
          return 1 ;;
      esac
    fi
    case "$_sec_name" in
      GIT_TRANSPORT_SSH_PRIVATE_KEY|GIT_PROVISION_SSH_PRIVATE_KEY|GIT_REMOVE_SSH_PRIVATE_KEY) ;;
      *) continue ;;
    esac
    # ONLY THE prd BINDING IS THE MAP. A dev/staging mirror of the same name is legitimate,
    # so it is SKIPPED rather than refused -- refusing it would be over-aggression, and it
    # would also mask the real defect by short-circuiting before the prd binding is judged.
    # A secret retargeted AWAY from prd needs no special case: its name then has no prd
    # binding at all and the walk breaks at link 5 on its own.
    [[ "$_sec_cfg" == "prd" ]] || continue
    _secret_seen["$_sec_name"]=$(( ${_secret_seen[$_sec_name]:-0} + 1 ))
    if [[ "${_secret_seen[$_sec_name]}" -gt 1 ]]; then
      echo "git_data_authorization_map_gate: ABORT — ${_sec_name} is published by more than one doppler_secret in config prd. Which value Doppler ends up holding is apply-order dependent, so this gate cannot say which key the application would authenticate with. Fail-closed."
      return 2
    fi
    # SAME AMBIGUITY RULE AS LINK 4. It was applied there and not here, and `try(remove,
    # transport)` renders the FALLBACK on any error while reading as address-distinct and
    # bijective to every other predicate. A rule stated once must be applied to every site
    # whose precondition it names.
    local _nsref
    _nsref="$(grep -o 'tls_private_key\.' <<< "$_sec_val" | wc -l | tr -d ' ')"
    if [[ "${_nsref:-0}" -gt 1 ]]; then
      echo "git_data_authorization_map_gate: ABORT — doppler_secret.${_sec_label} references ${_nsref} tls_private_key resources in one expression: ${_sec_val}. Which private half is published depends on a value this static gate cannot evaluate. Fail-closed."
      return 2
    fi
    _secret_rhs["$_sec_name"]="$_sec_val"
    if [[ "$_sec_val" =~ tls_private_key\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+) ]]; then
      _secret_terminal["$_sec_name"]="tls_private_key.${BASH_REMATCH[1]}"
      _secret_attr["$_sec_name"]="${BASH_REMATCH[2]}"
    fi
  done < <(awk '
    /^resource[[:space:]]+"doppler_secret"[[:space:]]+"[A-Za-z0-9_]+"[[:space:]]*\{/ {
      inres=1; depth=0; nm=""; val=""; cfg=""; lbl=$0
      sub(/^[^"]*"[^"]*"[[:space:]]+"/, "", lbl); sub(/".*$/, "", lbl)
    }
    inres {
      n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth+=n-m
      if ($0 ~ /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/)   { nm=$0;  sub(/^[^"]*"/,"",nm);  sub(/".*$/,"",nm) }
      if ($0 ~ /^[[:space:]]*config[[:space:]]*=[[:space:]]*"/) { cfg=$0; sub(/^[^"]*"/,"",cfg); sub(/".*$/,"",cfg) }
      if ($0 ~ /^[[:space:]]*value[[:space:]]*=/)               { val=$0; sub(/^[[:space:]]*value[[:space:]]*=[[:space:]]*/,"",val); sub(/[[:space:]]*$/,"",val) }
      if (depth<=0) { if (nm != "" && val != "") print lbl "|" nm "|" cfg "|" val; inres=0 }
    }
  ' <<< "$_root_src")

  # The resource blocks named by the walk must actually EXIST in the root (M11). Three
  # dangling aliases satisfy every reference-distinctness predicate while resolving to
  # nothing Terraform will create.
  declare -A _resource_exists=()
  while IFS= read -r _line; do
    [[ "$_line" =~ ^resource[[:space:]]+\"tls_private_key\"[[:space:]]+\"([A-Za-z0-9_]+)\" ]] || continue
    _resource_exists["tls_private_key.${BASH_REMATCH[1]}"]=1
  done <<< "$_root_src"

  # ── The resolution walk ─────────────────────────────────────────────────────────────
  declare -A _slot_terminal=()     # authority -> tls_private_key.<name> reached from link 1
  declare -A _seen_terminal=()
  local _tvar2 _modvar _lname2 _term _attr

  for _entry in "${_authorities[@]}"; do
    IFS='|' read -r _auth _script _dopname <<< "$_entry"

    _tvar2="${_slot_var[$_script]}"
    _modvar="${_tvar_modvar[$_tvar2]:-}"
    if [[ -z "$_modvar" ]]; then
      echo "git_data_authorization_map_gate: ABORT — the walk broke at link 2 for the ${_auth} authority: the template variable \${${_tvar2}} has no 'X = var.Y' binding in ${module_tf}. The gate resolves rather than asserting per-link precisely so an unanticipated hop breaks the walk instead of slipping past. Fail-closed."
      return 2
    fi
    _lname2="${_modvar_local[$_modvar]:-}"
    if [[ -z "$_lname2" ]]; then
      echo "git_data_authorization_map_gate: ABORT — the walk broke at link 3 for the ${_auth} authority: module \"${_mod_label}\" passes no 'X = local.Y' for module variable ${_modvar}. Fail-closed."
      return 2
    fi
    _term="${_local_terminal[$_lname2]:-}"
    if [[ -z "$_term" ]]; then
      _rhs="${_local_rhs[$_lname2]:-<no local of that name in the root>}"
      # PREDICATE 2 — every terminal must be a tls_private_key.<name> address. A var., a
      # data. source, a file() or a hardcoded "ssh-ed25519 …" literal is address-free and
      # would otherwise fall THROUGH the extractor rather than be rejected by it.
      if [[ "$_rhs" == *var.* || "$_rhs" == *data.* || "$_rhs" == *file\(* || "$_rhs" == *ssh-* ]]; then
        echo "git_data_authorization_map_gate: HOLD — the ${_auth} authority resolves to a NON-RESOURCE terminal: local.${_lname2} = ${_rhs}. Every slot must terminate at a tls_private_key.<name> this root creates. A variable carrying a default, a data source, a file() or an inline literal can hold any key at all — including the same key as another slot — and no address-distinctness predicate can see it."
        return 1
      fi
      echo "git_data_authorization_map_gate: ABORT — the walk broke at link 4 for the ${_auth} authority: local.${_lname2} = ${_rhs} yields no tls_private_key.<name>.<attr>. Resolving 2 of 3 slots is a broken instrument, not a two-key authorization map. Fail-closed."
      return 2
    fi
    _attr="${_local_attr[$_lname2]}"

    # PREDICATE 5 (public half) — a pubkey local reading .private_key_openssh is
    # address-distinct, terminal-valid and bijective, and it bakes a PRIVATE key into
    # user_data, which is gzipped into Hetzner instance metadata.
    if [[ "$_attr" != "public_key_openssh" ]]; then
      echo "git_data_authorization_map_gate: HOLD — the ${_auth} slot reads tls_private_key.*.${_attr}; the authorized_keys file takes public_key_openssh. Reading a private attribute here bakes the private half into user_data, which Hetzner stores as instance metadata."
      return 1
    fi
    # PREDICATE 3 — the named resource must exist (M11).
    if [[ -z "${_resource_exists[$_term]:-}" ]]; then
      echo "git_data_authorization_map_gate: HOLD — the ${_auth} authority resolves to ${_term}, but no such resource block exists in ${root}. Three dangling aliases are pairwise distinct and create nothing."
      return 1
    fi
    _slot_terminal["$_auth"]="$_term"
    _seen_terminal["$_term"]=1
  done

  # PREDICATE 1 — slot count == distinct terminal count == the design's count. De-duplication
  # keys on the extracted ADDRESS, never the raw RHS string: M9 (an alias or extra whitespace
  # making two RHS strings differ) and M24 (the same resource read through two different
  # attributes) both produce byte-different right-hand sides for one key.
  if [[ "${#_seen_terminal[@]}" -ne "$_n_authorities" ]]; then
    local _map=""
    for _entry in "${_authorities[@]}"; do
      IFS='|' read -r _auth _script _dopname <<< "$_entry"
      _map+="${_auth} -> ${_slot_terminal[$_auth]}; "
    done
    echo "git_data_authorization_map_gate: HOLD — the ${_n_authorities} forced-command slots resolve to only ${#_seen_terminal[@]} distinct key(s): ${_map}A collapse here hands one SSH identity more than one authority. If the transport key gains git-data-remove.sh, sshd matches by key and takes the FIRST match, so it never surfaces as a failure — only as the identity the web app uses for ordinary push and fetch being able to erase a user's repositories."
    return 1
  fi

  # PREDICATE 4 — THE AUTHORITY MAP IS AN ORDERED COMPOSITION, NOT A BIJECTION.
  #
  # This is the predicate that earns the whole five-link walk. A permutation — transport and
  # provision exchanging terminals, or a 3-cycle through the three doppler_secret values — is
  # perfectly bijective, three-distinct, all-resources-present, and passes every cardinality
  # predicate above while handing each authority the wrong key. The assertion is therefore
  # per-authority and joined on the extracted address, so it stays independent of how the
  # resource is spelled.
  for _entry in "${_authorities[@]}"; do
    IFS='|' read -r _auth _script _dopname <<< "$_entry"
    _term="${_secret_terminal[$_dopname]:-}"
    if [[ -z "$_term" ]]; then
      _rhs="${_secret_rhs[$_dopname]:-<no doppler_secret publishes that name>}"
      echo "git_data_authorization_map_gate: ABORT — the walk broke at link 5 for the ${_auth} authority: the Doppler secret ${_dopname} resolves to '${_rhs}', which yields no tls_private_key.<name>.<attr>. This is the half the application actually holds; an unresolvable terminal here means the gate cannot say which key the app would authenticate with. Fail-closed."
      return 2
    fi
    _attr="${_secret_attr[$_dopname]}"
    # PREDICATE 5 (private half) — a doppler_secret publishing .public_key_openssh hands the
    # app a public key as its authentication material. Green under every address-only predicate.
    if [[ "$_attr" != "private_key_openssh" ]]; then
      echo "git_data_authorization_map_gate: HOLD — ${_dopname} publishes tls_private_key.*.${_attr}; the application authenticates with private_key_openssh. Publishing a public key as authentication material is address-distinct and bijective, and the app cannot authenticate with it."
      return 1
    fi
    if [[ -z "${_resource_exists[$_term]:-}" ]]; then
      echo "git_data_authorization_map_gate: HOLD — ${_dopname} resolves to ${_term}, but no such resource block exists in ${root}."
      return 1
    fi
    if [[ "$_term" != "${_slot_terminal[$_auth]}" ]]; then
      echo "git_data_authorization_map_gate: HOLD — THE AUTHORIZATION MAP IS PERMUTED at the ${_auth} authority. The forced command /usr/local/bin/${_script} is held by ${_slot_terminal[$_auth]}, but the application reads its ${_auth} credential from ${_dopname}, which publishes the private half of ${_term}. Both halves are three-distinct and perfectly bijective, so every cardinality check passes — and each authority holds the wrong key. If ${_dopname} is the transport credential, every ordinary push authenticates into whichever forced command ${_term} holds."
      return 1
    fi
  done

  local _summary=""
  for _entry in "${_authorities[@]}"; do
    IFS='|' read -r _auth _script _dopname <<< "$_entry"
    _summary+="${_script} + ${_dopname} -> ${_slot_terminal[$_auth]}; "
  done
  echo "git_data_authorization_map_gate: RELEASED — the ${_n_authorities} forced-command slots in $(basename "$cloud_init") resolve through the render module and ${root}'s locals to ${#_seen_terminal[@]} pairwise-distinct tls_private_key resources, and each authority's private half is published under the matching Doppler name: ${_summary}"
  echo "git_data_authorization_map_gate: NOTE — this proves what the production root RENDERS, not what a live host HONOURS. It is a static assertion over Terraform source: no live host is probed, and none exists to probe. Runtime routes to the erase capability that a static walk structurally cannot see — an authorized_keys2 fall-through, hooksPath ownership, an unpinned AcceptEnv — are tracked separately and are NOT closed by this gate. On the git-data-host-replace path this gate is supplied by the branch it polices (that job has no environment: and therefore no deployment_branch_policy), so it holds against an accidental collapse merged and dispatched from main, and NOT against a deliberate actor with repository write access."
  return 0
}

# _git_data_hcl_block <text> <awk-regex-for-the-opening-line> — emit the whole block,
# brace-balanced, including its opening line. Emits nothing when the block is absent.
#
# WHY THIS EXISTS AS A SHARED PRIMITIVE. Every fail-open this gate has had was a scan that
# was ROOT-wide where the property is BLOCK-scoped: a `locals` predicate satisfied by an
# `output` block that merely mentions the same names, a `doppler_secret` map keyed on the
# secret NAME across every file, a `user_data` pin satisfied by the canonical string parked
# anywhere in the root. Root-scoping is right for FINDING declarations Terraform merges
# across files; it is wrong for deciding what a particular resource is bound to. Both scans
# are needed and they are not the same scan.
_git_data_hcl_block() {
  awk -v open_re="$2" '
    $0 ~ open_re && depth == 0 { inb = 1 }
    inb {
      print
      n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m
      if (depth <= 0) { inb = 0 }
    }
  ' <<< "$1"
}

# _git_data_hcl_nocomment <file> — strip `#` comments from HCL, QUOTE-AWARE.
#
# Returns 0 with the stripped text on stdout, or 9 if the file carries a `//` or `/*`
# comment outside a string — which this stripper deliberately does NOT handle.
#
# WHY QUOTE-AWARENESS IS THE WHOLE POINT, AND WHY THE // ARM ABORTS RATHER THAN STRIPS.
# Measured on the live root (2026-09-10): 81 occurrences of `//` across 19 of 48 .tf files,
# and NONE of them is an HCL comment — every one is either inside a string (`"https://…"`,
# `"tcp://10.0.1.30:5000"`) or inside a `#` comment quoting one. So a naive `//`-strip would
# corrupt URLs into truncated strings, and a naive `//`-ABORT would make this gate BORN RED
# on the live tree and stay red until someone deleted the arm — a gate that reds on every
# pull request is a gate that gets removed, not a gate that protects anything.
#
# Handling `#` first, and only outside strings, is what makes both classes disappear: a `//`
# inside a `#` comment is never reached, and a `//` inside a string is never a comment. What
# remains — a genuine `//` comment outside any string — this function refuses to guess about,
# because stripping it correctly requires the block-comment handling it does not implement,
# and a stripper that silently mis-parses its input yields a well-formed verdict about a
# configuration that is not the one Terraform loads.
_git_data_hcl_nocomment() {
  local f="${1:-}"
  [[ -r "$f" ]] || return 9
  awk '
    # HEREDOC BODIES ARE DATA, NOT HCL — pass them through untouched. Terraform heredocs
    # (<<EOT / <<-EOT) carry arbitrary text, so applying comment rules to them is wrong in
    # both directions: a body line containing a URL trips the `//` arm and ABORTs the whole
    # interlock (fail-closed but spurious), and a body line with an odd unescaped quote
    # leaves this per-line parser mid-string so a real trailing `#` comment survives into
    # the text every predicate then scans. No heredoc exists in the root today; this exists
    # so the first one to land does not silently change what the gate sees.
    heredoc != "" {
      if ($0 ~ ("^[[:space:]]*" heredoc "[[:space:]]*$")) { heredoc = "" }
      print ""
      next
    }
    match($0, /<<[-~]?"?'"'"'?[A-Za-z_][A-Za-z0-9_]*/) {
      tag = substr($0, RSTART, RLENGTH)
      sub(/^<<[-~]?"?'"'"'?/, "", tag)
      heredoc = tag
    }
    {
      line = $0
      out = ""
      instr = 0
      i = 1
      n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        nxt = (i < n) ? substr(line, i + 1, 1) : ""
        if (instr) {
          if (c == "\\") { out = out c nxt; i += 2; continue }
          if (c == "\"") { instr = 0 }
          out = out c; i++; continue
        }
        if (c == "\"") { instr = 1; out = out c; i++; continue }
        # `#` outside a string starts a comment: drop the rest of the line. Checked BEFORE
        # the `//` arm, so a `//` quoted inside a `#` comment is never seen as one.
        if (c == "#") { break }
        if (c == "/" && nxt == "/") { exit 9 }
        if (c == "/" && nxt == "*") { exit 9 }
        out = out c; i++
      }
      print out
    }
  ' "$f"
}
