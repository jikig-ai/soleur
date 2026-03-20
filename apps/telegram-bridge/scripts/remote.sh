#!/usr/bin/env bash
set -euo pipefail

HOST="${BRIDGE_HOST:?Set BRIDGE_HOST env var}"

case "${1:-help}" in
  status)
    ssh "root@$HOST" "docker ps; echo '---'; free -h; df -h /"
    ;;
  logs)
    ssh "root@$HOST" "docker logs --tail ${2:-100} soleur-bridge"
    ;;
  restart)
    ssh "root@$HOST" "docker restart soleur-bridge"
    ;;
  health)
    ssh "root@$HOST" "curl -s localhost:8080/health | jq ."
    ;;
  *)
    echo "Usage: remote.sh {status|logs [N]|restart|health}"
    ;;
esac
