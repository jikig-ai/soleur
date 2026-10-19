# shellcheck shell=bash
# context-sanitize.sh — shared context/display boundary sanitizer (#10395).
#
# Sourced lib. Two byte-equal copies exist:
#   .claude/hooks/lib/context-sanitize.sh          (repo-side consumers)
#   plugins/soleur/scripts/lib/context-sanitize.sh (plugin-side consumers)
# Keep them identical — context-sanitize.test.sh pins parity with `cmp`.
#
# Contract: stdin -> stdout pipe filters. All strip C0 + DEL (0x7F) and the
# UTF-8 line-break class (NEL \xc2\x85, LS \xe2\x80\xa8, PS \xe2\x80\xa9);
# variants differ only in which C0 whitespace survives the tr stage.
# The sed patterns MUST use $'...' ANSI-C quoting — BSD sed does not
# interpret bare '\xHH', which would silently strip nothing.
# `\177` is octal: tr does not interpret \xHH.
#
# No `set` options here — this file is sourced into hooks that own their
# own option state.

_soleur_ctx_sed() {
  LC_ALL=C sed -e $'s/\xc2\x85//g' -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g'
}

# strip-all: single-line fields (no C0 survives).
soleur_ctx_sanitize() {
  LC_ALL=C tr -d '\000-\037\177' | _soleur_ctx_sed
}

# keep-lines: multi-line blocks (TAB and LF survive).
soleur_ctx_sanitize_lines() {
  LC_ALL=C tr -d '\000-\010\013-\037\177' | _soleur_ctx_sed
}

# newline-only: LF survives, TAB stripped too.
soleur_ctx_sanitize_nl() {
  LC_ALL=C tr -d '\000-\011\013-\037\177' | _soleur_ctx_sed
}

# Direct execution is a usage error: this is a sourced lib, not a command.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "context-sanitize.sh: source this file; do not execute it" >&2
  exit 1
fi
