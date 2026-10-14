# Emit "<unit-name>|<hazard>|<has_live_cred>" for each heredoc-authored systemd unit.
# hazard = body has REQUIRED EnvironmentFile=/etc/default/inngest-server AND an ExecStart
#          invoking doppler directly (no [ -n "$DOPPLER_TOKEN" ] gate).
/^[[:space:]]*(readonly[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="\/etc\/systemd\/system\/[^"]+\.service"/ {
  var = $0; sub(/=.*/, "", var); sub(/^[[:space:]]*(readonly[[:space:]]+)?/, "", var)
  path = $0; sub(/^[^"]*"/, "", path); sub(/".*/, "", path)
  name = path; sub(/.*\//, "", name)
  unitvar[var] = name
}
/^[[:space:]]*cat[[:space:]]*>[[:space:]]*/ && /<<-?['"]?[A-Za-z_]+['"]?[[:space:]]*$/ {
  tgt = $0; sub(/^[[:space:]]*cat[[:space:]]*>[[:space:]]*/, "", tgt); sub(/[[:space:]]*<<.*/, "", tgt)
  gsub(/["${}]/, "", tgt)
  cur = (tgt in unitvar) ? unitvar[tgt] : ((tgt ~ /\.service$/) ? tgt : "")
  if (cur != "") { sub(/.*\//, "", cur) }
  mark = $0; sub(/.*<<-?/, "", mark); gsub(/['"[:space:]]/, "", mark)
  if (cur != "") { inb = 1; body = ""; endmark = mark }
  next
}
inb && $0 ~ ("^[[:space:]]*" endmark "[[:space:]]*$") {
  hz = (body ~ /\nEnvironmentFile=\/etc\/default\/inngest-server\n/) && (body ~ /\nExecStart=[^\n]*\/doppler run /)
  live = (body ~ /soleur-doppler-token/)
  if (hz) printf "%s|%s|%s\n", cur, "hazard", (live ? "has-live-cred" : "NO-live-cred")
  inb = 0; next
}
inb { body = body "\n" $0 }
