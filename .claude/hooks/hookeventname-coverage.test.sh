#!/usr/bin/env bash
# Meta-test: every PreToolUse hook that emits a `permissionDecision` MUST also
# emit `hookEventName: "PreToolUse"` in the same output object — otherwise
# Claude Code silently ignores the decision and the tool call proceeds (the
# deny/ask never takes effect).
#
# This guards the bug class fixed in the hook-deny-enforcement PR: 9 hooks
# (including git-commit-secret-scan, guardrails, no-memory-write) shipped deny
# JSON without hookEventName and were silently non-enforcing. The per-file
# count check below makes that class un-shippable going forward — any new or
# edited hook that adds a permissionDecision without the paired hookEventName
# fails this test.
#
# Source: official Claude Code PreToolUse hook contract — hookEventName is a
# required field in hookSpecificOutput for permissionDecision to be honored.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

for h in "$HOOK_DIR"/*.sh; do
  base="$(basename "$h")"
  # Skip test scripts themselves.
  [[ "$base" == *.test.sh ]] && continue

  # Count non-comment lines that emit a permissionDecision, and lines that
  # emit hookEventName. Comment lines (leading # after optional whitespace)
  # are excluded so the doc-comment describing the shape is not counted.
  # Match the decision FIELD only — `permissionDecision":` / `permissionDecision:`
  # — never `permissionDecisionReason` (which contains "permissionDecision" as a
  # substring and would double-count).
  pd=$(grep -vE '^[[:space:]]*#' "$h" | grep -cE 'permissionDecision"?[[:space:]]*:' || true)
  hen=$(grep -vE '^[[:space:]]*#' "$h" | grep -c 'hookEventName' || true)

  # Same contract on the OTHER side: a SessionStart/UserPromptSubmit hook that
  # emits `additionalContext` inside hookSpecificOutput must pair it with
  # hookEventName, or Claude Code rejects the output ("hookSpecificOutput is
  # missing required field hookEventName") and the injected context is dropped.
  # This is the SessionStart analogue of the permissionDecision bug above —
  # regressed once in session-rules-loader.sh, hence this guard.
  ac=$(grep -vE '^[[:space:]]*#' "$h" | grep -cE 'additionalContext"?[[:space:]]*:' || true)
  if [[ "$ac" -gt 0 && "$hen" -lt "$ac" ]]; then
    echo "FAIL: $base emits $ac additionalContext(s) but only $hen hookEventName(s)."
    echo "      Every hookSpecificOutput with additionalContext must include hookEventName (e.g. \"SessionStart\")."
    fail=1
  fi

  # Per-file count check (count(hookEventName) >= count(permissionDecision)),
  # not per-emission pairing. This catches the realistic regression — a new
  # decision block added without hookEventName bumps `pd` without `hen` and
  # fails. It does NOT catch a contrived case of two hookEventName in one block
  # plus zero in a sibling; that is not reachable today (every block has exactly
  # one) and would require an AST-level parse to detect.
  if [[ "$pd" -gt 0 && "$hen" -lt "$pd" ]]; then
    echo "FAIL: $base emits $pd permissionDecision(s) but only $hen hookEventName(s)."
    echo "      Every permissionDecision output object must include hookEventName: \"PreToolUse\"."
    fail=1
  fi
done

# NB the summary for this first block is deferred to the end of the file: it
# used to print before the three gates below ran, so a run whose AC13 failed
# still OPENED with a PASS line.
pd_hen_ok=$(( fail == 0 ? 1 : 0 ))

# ===========================================================================
# Registration, exec-bit, and single-rewriter gates (issue #7165, ADR-158)
# ===========================================================================
# Folded into this meta-suite rather than a 4th meta-file: all three answer the
# same question this file already asks — "is the hook actually wired up such
# that Claude Code will honour it?"
#
# The exec-bit and registration gates are a LOAD-BEARING PAIR. Either alone is
# vacuous in the direction that matters (#7151, one level up):
#   * exec-bit alone — deleting the settings.json registration leaves the mode
#     gate green while the hook never runs again.
#   * registration alone — a hook registered at mode 100644 is registered and
#     unrunnable.
REPO_ROOT_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
SETTINGS="$REPO_ROOT_DIR/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq missing — registration/exec-bit/single-rewriter gates not run"
elif [[ ! -f "$SETTINGS" ]]; then
  echo "FAIL: $SETTINGS not found — cannot derive the registered hook list."
  fail=1
else
  # Entries are QUOTE-PREFIXED (`"$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh`), so
  # the leading double-quote is part of the JSON string value and must be
  # stripped along with the variable. guardrails.sh appears under more than one
  # matcher and at least one entry is a .py — hence `sort -u` and no .sh filter.
  reg_all="$(jq -r '.hooks | to_entries[] | .value[]? | .hooks[]? | .command' "$SETTINGS" 2>/dev/null \
             | sed 's|^"\$CLAUDE_PROJECT_DIR"/||' | sort -u)"
  reg_bash="$(jq -r '.hooks.PreToolUse[]? | select(.matcher=="Bash") | .hooks[]?.command' "$SETTINGS" 2>/dev/null \
              | sed 's|^"\$CLAUDE_PROJECT_DIR"/||' | sort -u)"

  n_all=$(printf '%s\n' "$reg_all" | grep -c . || true)
  n_bash=$(printf '%s\n' "$reg_bash" | grep -c . || true)

  # NON-VACUITY FIRST. A derivation that silently yields zero entries makes
  # every membership assertion below pass by iterating nothing — the exact
  # shape that lets a dropped registration read as green.
  if [[ "$n_all" -lt 20 || "$n_bash" -lt 15 ]]; then
    echo "FAIL: settings-derived hook list looks empty/short (all=$n_all bash=$n_bash)."
    echo "      The derivation broke; every gate below would pass vacuously."
    fail=1
  else
    echo "PASS: settings-derived hook list is non-empty (all=$n_all, PreToolUse/Bash=$n_bash)."

    # --- AC9: index mode of every REGISTERED hook is exactly 100755 ---------
    # `git ls-files -s` (the INDEX), not `test -x` (the working tree): a local
    # chmod does not travel, and a hook committed 100644 is unrunnable on every
    # other checkout regardless of how it looks here.
    mode_bad=0
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      ls_out="$(git -C "$(dirname "$SETTINGS")/.." ls-files -s "$h" 2>/dev/null)"
      if [[ -z "$ls_out" ]]; then
        echo "FAIL: registered hook '$h' is not tracked by git (git ls-files -s is empty)."
        mode_bad=1; continue
      fi
      mode="$(printf '%s' "$ls_out" | awk '{print $1}')"
      if [[ "$mode" != "100755" ]]; then
        echo "FAIL: registered hook '$h' has index mode $mode, want 100755 (Claude Code execs it directly)."
        mode_bad=1
      fi
    done <<EOF
$reg_all
EOF
    [[ "$mode_bad" -eq 0 ]] && echo "PASS: all $n_all registered hooks are tracked at index mode 100755." || fail=1

    # --- AC14: grep-rewrite.sh is a MEMBER of the PreToolUse/Bash list ------
    case "$reg_bash" in
      *".claude/hooks/grep-rewrite.sh"*)
        echo "PASS: grep-rewrite.sh is registered on the PreToolUse Bash matcher." ;;
      *)
        echo "FAIL: grep-rewrite.sh is NOT in the settings-derived PreToolUse/Bash list."
        echo "      The ugrep shim is un-neutralized; see ADR-158."
        fail=1 ;;
    esac

    # --- AC13: exactly ONE hook source may rewrite tool input ---------------
    # ADR-158 grants the rewrite authority under a single-rewriter invariant:
    # two hooks emitting updatedInput for the same call have undefined
    # precedence, and the loser's rewrite is silently discarded.
    #
    # Comment lines are stripped first — this file's own siblings legitimately
    # DISCUSS updatedInput in prose, and a body-grep sees comments too
    # (cq-assert-anchor-not-bare-token). Anchored on the JSON field shape
    # (`updatedInput":` / `updatedInput:`), never the bare word.
    #
    # The optional BACKSLASH is load-bearing and was found by mutation, not by
    # review: a hook that builds its envelope with printf rather than jq emits
    # `\"updatedInput\":`, and the backslash-free pattern skipped it entirely —
    # a second rewriter added that way passed this gate. printf is not a
    # hypothetical spelling here; lib/hook-input.sh emits its ask envelope
    # exactly that way, precisely because jq may be what is broken.
    # SCOPE. A `"$HOOK_DIR"/*.sh` glob was the obvious loop and it is too narrow
    # in two directions that both matter, and one of which this file's own
    # comment above names:
    #   * lib/*.sh — where a shared rewrite helper would naturally live, and
    #     where lib/hook-input.sh (cited above as the printf-envelope precedent)
    #     actually sits. A second rewriter added there passed the old gate.
    #   * security_reminder_hook.py — a REGISTERED PreToolUse hook. The
    #     registration derivation above already notes "at least one is a .py";
    #     the rewriter scan filtered it out anyway.
    # Union of the settings-derived registration list and the on-disk hook tree,
    # so neither an unregistered new file nor a non-.sh registered hook escapes.
    rewriters=""
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      b="${h##*/}"
      [[ "$b" == *.test.sh ]] && continue
      f="$REPO_ROOT_DIR/$h"
      [[ -f "$f" ]] || f="$h"
      [[ -f "$f" ]] || continue
      c=$(grep -vE '^[[:space:]]*#' "$f" | grep -cE 'updatedInput\\?"?[[:space:]]*:' || true)
      [[ "$c" -gt 0 ]] && case " $rewriters " in *" $b "*) ;; *) rewriters="$rewriters $b" ;; esac
    done <<EOF
$reg_all
$(ls "$HOOK_DIR"/*.sh "$HOOK_DIR"/*.py "$HOOK_DIR"/lib/*.sh 2>/dev/null)
EOF
    rewriters="${rewriters# }"
    if [[ "$rewriters" == "grep-rewrite.sh" ]]; then
      echo "PASS: exactly one rewriting hook (grep-rewrite.sh) — single-rewriter invariant holds."
    else
      echo "FAIL: single-rewriter invariant violated. Rewriting hooks: [${rewriters:-none}]"
      echo "      ADR-158 permits exactly one. Two hooks emitting updatedInput for the same"
      echo "      call have undefined precedence and one rewrite is silently discarded."
      fail=1
    fi
  fi
fi

if [[ "$pd_hen_ok" -eq 1 ]]; then
  echo "PASS: all PreToolUse hooks pair permissionDecision with hookEventName."
fi

exit "$fail"
