# Item F prototype (J0c): linearise fenced code of a markdown file. A fence is opened by a line of 3+ backticks or tildes
# (optionally indented, optional info string) and closed by a line of the SAME character with at least as many. Its code lines
# are emitted as "FILE:LINE:text" only when the fence text contains the token "pipefail" (checked at close; an unclosed fence is
# closed at EOF). Prose outside a fence is never emitted. POSIX awk only.
function close_fence(   i) {
  if (hasPf) for (i = 1; i <= n; i++) print FILENAME ":" ln[i] ":" tx[i]
  inf = 0; n = 0; hasPf = 0
}
FNR == 1 { if (inf) close_fence(); inf = 0; n = 0; hasPf = 0 }
{
  line = $0; sub(/\r$/, "", line)
  if (match(line, /^[ \t]*(```+|~~~+)/)) {
    s = substr(line, RSTART, RLENGTH); gsub(/[ \t]/, "", s)
    ch = substr(s, 1, 1); len = length(s)
    if (!inf) { inf = 1; fch = ch; flen = len; n = 0; hasPf = 0; next }
    rest = substr(line, RSTART + RLENGTH)
    if (ch == fch && len >= flen && rest ~ /^[ \t]*$/) { close_fence(); next }
  }
  if (inf) { n++; ln[n] = FNR; tx[n] = line; if (line ~ /pipefail/) hasPf = 1 }
}
END { if (inf) close_fence() }
