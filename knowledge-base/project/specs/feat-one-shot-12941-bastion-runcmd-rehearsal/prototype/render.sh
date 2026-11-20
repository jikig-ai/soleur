#!/usr/bin/env bash
# render.sh <template> <egress-sh> <out.yml> [ingest_host]
set -eu
P="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$P/tf" "$P/k"
[ -f "$P/k/key" ] || ssh-keygen -q -t ed25519 -N '' -C fixture -f "$P/k/key"
ING="${4:-o1.ingest.de.sentry.io}"
printf 'templatefile("%s", { host_name="soleur-bastion", sentry_dsn="https://pubkey123@o1.ingest.de.sentry.io/4242", sentry_ingest_host="%s", private_ip="10.0.1.70", host_ssh_ed25519_private_key=file("%s"), host_ssh_ed25519_public_key=trimspace(file("%s")), bastion_egress_b64=base64encode(file("%s")) })\n' \
  "$1" "$ING" "$P/k/key" "$P/k/key.pub" "$2" | terraform -chdir="$P/tf" console > "$3.raw"
python3 - "$3.raw" "$3" <<'PY'
import sys
L=open(sys.argv[1]).read().splitlines()
if L and L[0].lstrip().startswith("<<"): L=L[1:-1]
open(sys.argv[2],"w").write("\n".join(L)+"\n")
PY
