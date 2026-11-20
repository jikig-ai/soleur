#!/usr/bin/env bash
set -eu
IMG='ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55'
docker rm -f bproto-build >/dev/null 2>&1 || true
docker run --name bproto-build "$IMG" bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus cloud-init ca-certificates iproute2 python3 openssl curl openssh-server systemd-timesyncd systemd-resolved >/dev/null
for p in linux-image-0.0.0-1-generic linux-image-generic; do
  d=/tmp/$p; mkdir -p $d/DEBIAN
  if [ $p = linux-image-generic ]; then v=999:0.0.0-1; dep="Depends: linux-image-0.0.0-1-generic"; else v=0.0.0-1; dep=""; fi
  { echo "Package: $p"; echo "Version: $v"; echo "Architecture: all"; echo "Maintainer: rehearsal fixture"; [ -n "$dep" ] && echo "$dep"; echo "Description: rehearsal fixture (not a kernel)"; } > $d/DEBIAN/control
  dpkg-deb --build $d /tmp/$p.deb >/dev/null
done
dpkg -i /tmp/linux-image-0.0.0-1-generic.deb /tmp/linux-image-generic.deb >/dev/null
cat > /usr/local/sbin/uname <<"SH"
#!/bin/sh
if [ "$1" = "-r" ] && [ "$#" -eq 1 ]; then echo 0.0.0-1-generic; exit 0; fi
exec /usr/bin/uname "$@"
SH
chmod 0755 /usr/local/sbin/uname
rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_*
cloud-init --version
'
docker commit bproto-build bproto:img >/dev/null; docker rm bproto-build >/dev/null
