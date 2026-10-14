# Item F prototype (J0c): linearise a trailing single bar. Emits "FILE:LINE: | <next code line, left-trimmed>" for every
# line that ends in a single bar (not "||", not a YAML block-scalar indicator, not a comment) joined to the next non-comment,
# non-blank line. POSIX awk only (no gensub, no \b, no 3-argument match). The reader test is NOT here: the shared filter does it.
function flush() { pend = 0 }
FNR == 1 { pend = 0 }
{
  line = $0
  if (pend) {
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) { next }
    t = line; sub(/^[ \t]+/, "", t)
    print FILENAME ":" pn ": | " t
    pend = 0
  }
  if (line ~ /[^|][ \t]*\|[ \t]*$/ || line ~ /^[ \t]*\|[ \t]*$/ || line ~ /\|&[ \t]*$/) {
    if (line ~ /\|\|[ \t]*$/) next
    if (line ~ /:[ \t]*[|>][-+]?[ \t]*$/ || line ~ /^[ \t]*-?[ \t]*[|>][-+]?[ \t]*$/) next
    if (line ~ /^[ \t]*#/) next
    pend = 1; pn = FNR
  }
}
