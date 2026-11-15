# logtail exploration / exploration_alert PAIR CENSUS over apps/web-platform/infra/*.tf.
# Shared by the three Inngest logs-alert guards (inngest-registry-empty-alert.test.sh,
# inngest-luks-wrong-volume-alert.test.sh, inngest-luks-key-probe-alert.test.sh), which used to
# carry three byte-identical copies (#12737 review). Invoke: awk -v MARK=<stem> -f <this> <tf...>
# Output: `E|<exploration>|<carries MARK>` and `A|<alert>|<carries MARK>|<bound exploration>`.
# A resource carries MARK when its body, or a local it references (transitively), contains it.
function cv(s) { gsub(/"([^"\\]|\\.)*"/, "\"\"", s); sub(/[[:space:]]*(#|\/\/).*$/, "", s); return s }
function hdopen(c) {
  if (match(c, /<<-?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) { hd = substr(c, RSTART); sub(/^<<-?/, "", hd); sub(/[[:space:]]+$/, "", hd) }
}
FNR == 1 { hd = ""; loc = ""; inb = 0 }
{
  line = $0
  if (hd != "") {
    if (line ~ ("^[[:space:]]*" hd "[[:space:]]*$")) { hd = ""; loc = "" }
    else if (index(line, MARK) > 0) { if (inb) braw[nb] = braw[nb] " " MARK; else if (loc != "") marked[loc] = 1 }
    next
  }
  if (line ~ /^[[:space:]]*(#|\/\/)/) next
  c = cv(line)
  if (!inb) {
    if (match(line, /^[[:space:]]*resource[[:space:]]+"?logtail_exploration(_alert)?"?[[:space:]]+"?[^" {]+"?[[:space:]]*\{/)) {
      kind = (line ~ /logtail_exploration_alert/) ? "A" : "E"
      nm = line
      sub(/^[[:space:]]*resource[[:space:]]+"?logtail_exploration(_alert)?"?[[:space:]]+"?/, "", nm)
      sub(/["[:space:]{].*$/, "", nm)
      nb++; bkind[nb] = kind; bname[nb] = nm; braw[nb] = ""; bcv[nb] = ""; inb = 1; d = 0
    } else {
      if (match(c, /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*<<-?[A-Za-z_]/)) {
        loc = c; sub(/^[[:space:]]*/, "", loc); sub(/[[:space:]]*=.*$/, "", loc)
      } else if (line ~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/) {
        l2 = line; sub(/^[[:space:]]*/, "", l2); sub(/[[:space:]]*=.*$/, "", l2); lbody[l2] = line
        if (index(line, MARK) > 0) marked[l2] = 1
      }
      hdopen(c)
      next
    }
  }
  if (inb) {
    braw[nb] = braw[nb] " " line; bcv[nb] = bcv[nb] " " c
    o = gsub(/\{/, "{", c); x = gsub(/\}/, "}", c); d += o - x
    hdopen(cv(line))
    if (d <= 0) { inb = 0 }
  }
}
END {
  do {
    ch = 0
    for (l in lbody) if (!(l in marked)) for (m in marked) if (lbody[l] ~ ("local\\." m "([^A-Za-z0-9_-]|$)")) { newm[l] = 1; break }
    for (l in newm) { marked[l] = 1; ch = 1 }
    delete newm
  } while (ch)
  for (i = 1; i <= nb; i++) {
    car[i] = (index(braw[i], MARK) > 0)
    for (l in marked) if (bcv[i] ~ ("local\\." l "([^A-Za-z0-9_-]|$)")) car[i] = 1
  }
  for (i = 1; i <= nb; i++) if (bkind[i] == "E") ecar[bname[i]] = car[i]
  for (i = 1; i <= nb; i++) {
    if (bkind[i] == "E") { printf "E|%s|%d\n", bname[i], car[i]; continue }
    b = ""; t = bcv[i]
    if (match(t, /exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.[A-Za-z0-9_-]+\.id/)) {
      b = substr(t, RSTART, RLENGTH); sub(/^.*logtail_exploration\./, "", b); sub(/\.id$/, "", b)
    }
    printf "A|%s|%d|%s\n", bname[i], (b != "" && ecar[b]), b
  }
}
