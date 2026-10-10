# shellcheck shell=bash
# Shared HCL "effective text" lexer and block extractors (#9879; extracted from
# apps/web-platform/infra/workspaces-luks.test.sh Guard B4, behaviour unchanged).
#
# SOURCED, never executed. Consumers (resolve this file from the REPO ROOT, never from the
# suite's own directory, so a suite that moves cannot silently stop finding it):
#   - apps/web-platform/infra/workspaces-luks.test.sh      (Guard B4, web-1 workspaces volume)
#   - apps/web-platform/infra/inngest-luks-sole-copy.test.sh (Guard 1, inngest sole-copy store)
#
# ONE CHOKEPOINT ON PURPOSE. Every guard that asks "does this attribute hold in the EFFECTIVE
# Terraform text" reads through strip_comments below. Neutering it (for example to the identity
# function) makes a guard blind to a `/* ... */`-wrapped protection, and that must redden BOTH
# consuming suites: Guard B4 rows 8a-8c in workspaces-luks.test.sh, row 3 plus the library-neutering
# harness rows in inngest-luks-sole-copy.test.sh.
#
# Provides: strip_comments, block_of, _b4_block_range, B4_TAIL, _b4_attr_true,
# _b4_prevent_destroy_of, p_b4_no_override_files. Needs only awk, grep, find.

# Strip ALL THREE HCL comment forms. This file's entire job is to forbid constructs
# that workspaces-luks.tf must also DISCUSS in prose, so every predicate that greps
# for a forbidden token must see code only. Knowing just `#` is what let A9
# false-FAIL on its own .tf's comment once already; `//` and `/* */` are the same
# trap wearing different hats.
#
# `/* */` MAY SPAN LINES, and terraform validate honours that. The old one-line sed
# (`s~/\*.*\*/~~g`) only removed a comment that opened and closed on the same line, so
# wrapping `delete_protection = true` or a whole `lifecycle { prevent_destroy = true }` in a
# multi-line comment left the suite green (Guard B4 rows 8a-8c). This is a small lexer:
#   - LINE COUNT IS PRESERVED. Every input line yields exactly one output line (a line wholly
#     inside a block comment comes out blank), because _b4_block_range reports line numbers in
#     the ORIGINAL file from this output.
#   - `/*` opens a block only OUTSIDE a "string" and before any `#` / `//` on the line, so
#     `"/mnt/*"` or `# see /etc/default/*` does not swallow the rest of the file.
#   - Inside an HCL heredoc (opener: two less-than signs, an optional dash, then a marker word;
#     closer: the marker alone on its line) the text is literal; only the whole-line `#` / `//`
#     blanking applies there, as before.
#   - Trailing `#` / `//` comments after code are KEPT (B4_TAIL tolerates them), as before.
strip_comments() {
  awk '
    hd != "" {
      line = $0
      if (line ~ ("^[[:space:]]*" hd "[[:space:]]*$")) hd = ""
      if (line ~ /^[[:space:]]*(#|\/\/)/) line = ""
      print line
      next
    }
    {
      line = $0; out = ""; instr = 0; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2)
        if (inblk) { if (c2 == "*/") { inblk = 0; i += 2 } else { i++ }; continue }
        if (instr) {
          out = out c
          if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
          if (c == "\"") instr = 0
          i++; continue
        }
        if (c == "\"") { instr = 1; out = out c; i++; continue }
        if (c2 == "/*") { inblk = 1; i += 2; continue }
        if (c == "#" || c2 == "//") { out = out substr(line, i); break }
        out = out c; i++
      }
      if (out ~ /^[[:space:]]*(#|\/\/)/) out = ""
      if (!inblk && match(out, /<<-?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) {
        hd = substr(out, RSTART); sub(/^<<-?/, "", hd); sub(/[[:space:]]+$/, "", hd)
      }
      print out
    }
  ' "$1"
}

# Extract one resource block by BRACE DEPTH, not by an `awk /^}/` range.
# The range form terminates at the first column-0 `}`, so a nested block closed at
# column 0 truncates the extraction and hides everything after it — a proven
# false-PASS (a `labels` block closed at col 0 with `for_each` after it reported
# 20/20 green on a for_each'd volume). `terraform fmt` would reject that layout, but
# fmt runs in a DIFFERENT CI job (validate) from this guard (deploy-script-tests),
# so relying on it makes this suite's soundness depend on a gate it never names.
# Brace depth removes the coupling.
block_of() {
  local file="$1" type="$2" name="$3"
  strip_comments "$file" | awk -v t="$type" -v n="$name" '
    $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1 }
    inb {
      print
      d += gsub(/\{/, "{")
      d -= gsub(/\}/, "}")
      if (d <= 0 && NR > 1 && /\}/) { inb = 0 }
    }
  '
}

# Attribute predicates (comment-stripped text, anchored INSIDE the block, never column 0).
# Each value check tolerates extra spacing plus a trailing comment, because strip_comments
# drops only whole-line comments.
B4_TAIL='[[:space:]]*((#|//).*)?$'

# B4-5/6/9 shared body: resource <type> <name> carries exactly one `<attr> = ...` line and its
# value is `true`. A token-present `= false` is the drift (mutations 5, 6 and 9a).
_b4_attr_true() {
  local f="$1" type="$2" name="$3" attr="$4" b
  b="$(block_of "$f" "$type" "$name")"
  if [ -z "$b" ]; then echo 0; return; fi
  [ "$(printf '%s\n' "$b" | grep -Ec "^[[:space:]]+${attr}[[:space:]]*=")" = "1" ] || { echo 0; return; }
  if grep -Eq "^[[:space:]]+${attr}[[:space:]]*=[[:space:]]*true${B4_TAIL}" <<<"$b"; then echo 1; else echo 0; fi
}
# prevent_destroy is only legal inside a lifecycle block — require one in the same resource.
_b4_prevent_destroy_of() {
  local f="$1" type="$2" name="$3" b
  b="$(block_of "$f" "$type" "$name")"
  if [ -z "$b" ]; then echo 0; return; fi
  grep -Eq '^[[:space:]]+lifecycle[[:space:]]*\{' <<<"$b" || { echo 0; return; }
  _b4_attr_true "$f" "$type" "$name" prevent_destroy
}

# B4-10: no override file and no JSON config in the root. Terraform MERGES `*override.tf` /
# `*override.tf.json` over the primary config at load time and loads `*.tf.json` exactly as `*.tf`,
# so either one can drop prevent_destroy / delete_protection / the for_each narrowing while every
# HCL-reading row above stays green on the file it reads. Same refusal as M14 of
# git_data_authorization_map_gate (tests/scripts/lib/git-data-birth-readiness-gate.sh), which the
# git-data-host-create / -replace arms of apply-web-platform-infra.yml run; this row extends it to
# every B4 run. Takes the ROOT DIRECTORY, not a file. Terraform reads the root's top level only.
p_b4_no_override_files() {
  local hits
  hits="$(find "$1" -maxdepth 1 -type f \( -name '*override.tf' -o -name '*override.tf.json' -o -name '*.tf.json' \) -print 2>/dev/null)"
  if [ -z "$hits" ]; then echo 1; else echo 0; fi
}

# Line range [start end] of one resource block in the ORIGINAL file (strip_comments keeps the
# line count, so its line numbers are the file's).
_b4_block_range() {
  local file="$1" type="$2" name="$3"
  strip_comments "$file" | awk -v t="$type" -v n="$name" '
    !inb && $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1; s = NR }
    inb {
      d += gsub(/\{/, "{")
      d -= gsub(/\}/, "}")
      if (d <= 0 && /\}/) { print s, NR; exit }
    }
  '
}
