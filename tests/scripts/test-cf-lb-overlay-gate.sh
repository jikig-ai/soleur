#!/usr/bin/env bash
# test-cf-lb-overlay-gate.sh — unit tests for tests/scripts/lib/cf-lb-overlay-gate.sh
# (#11181 F3). Feeds synthetic plan JSON; never touches Cloudflare or terraform.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/cf-lb-overlay-gate.sh"
TMP="$(mktemp -d -t cf-lb-gate-test.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { if [[ "$2" -eq "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 (want rc $3, got $2)"; fail=1; fi; }
run() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; return $rc; }

source "$LIB"

mk() { printf '%s' "$2" > "$TMP/$1.json"; }

# --- record arm ---
mk r1 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging"}}}]}'
run cf_lb_gate_record "$TMP/r1.json"; ok "record: single create passes" $? 0
mk r2 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"]}},{"address":"cloudflare_record.other","change":{"actions":["create"]}}]}'
run cf_lb_gate_record "$TMP/r2.json"; ok "record: extra create refused" $? 1
mk r3 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["delete"]}}]}'
run cf_lb_gate_record "$TMP/r3.json"; ok "record: delete refused" $? 1

# --- overlay arm ---
mk o1 '{"resource_changes":[
 {"address":"cloudflare_record.lb_staging","change":{"actions":["no-op"]}},
 {"address":"cloudflare_load_balancer_monitor.lb_staging","change":{"actions":["create"]}},
 {"address":"cloudflare_load_balancer_pool.lb_staging","change":{"actions":["create"]}},
 {"address":"cloudflare_load_balancer.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging.soleur.ai"}}}]}'
run cf_lb_gate_overlay "$TMP/o1.json"; ok "overlay: in-set creates + hostname pass" $? 0
mk o2 '{"resource_changes":[{"address":"cloudflare_load_balancer.lb_staging","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_overlay "$TMP/o2.json"; ok "overlay: app.soleur.ai name refused" $? 1
mk o3 '{"resource_changes":[{"address":"hcloud_server.web","change":{"actions":["delete"]}}]}'
run cf_lb_gate_overlay "$TMP/o3.json"; ok "overlay: destructive change refused" $? 1
mk o4 '{"resource_changes":[{"address":"hcloud_volume.x","change":{"actions":["create"]}}]}'
run cf_lb_gate_overlay "$TMP/o4.json"; ok "overlay: out-of-scope create refused" $? 1

# --- teardown arm ---
mk t1 '{"resource_changes":[
 {"address":"cloudflare_record.lb_staging","change":{"actions":["delete"]}},
 {"address":"cloudflare_load_balancer_monitor.lb_staging","change":{"actions":["delete"]}},
 {"address":"cloudflare_load_balancer_pool.lb_staging","change":{"actions":["delete"]}},
 {"address":"cloudflare_load_balancer.lb_staging","change":{"actions":["delete"]}}]}'
run cf_lb_gate_teardown "$TMP/t1.json"; ok "teardown: all-four deletes pass" $? 0
mk t2 '{"resource_changes":[{"address":"hcloud_server.web","change":{"actions":["delete"]}}]}'
run cf_lb_gate_teardown "$TMP/t2.json"; ok "teardown: prod delete refused" $? 1
mk t3 '{"resource_changes":[]}'
run cf_lb_gate_teardown "$TMP/t3.json"; ok "teardown: empty (idempotent) passes" $? 0

# --- ga arm ---
mk g1 '{"resource_changes":[
 {"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"]}},
 {"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["create"]}},
 {"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"]}},
 {"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g1.json"; ok "ga: trio creates + no-op dep pass" $? 0
mk g2 '{"resource_changes":[{"address":"cloudflare_load_balancer.app","change":{"actions":["create"]}},{"address":"cloudflare_record.app","change":{"actions":["delete"]}}]}'
run cf_lb_gate_ga "$TMP/g2.json"; ok "ga: record delete refused" $? 1

# --- malformed ---
mk m1 'not json'
run cf_lb_gate_record "$TMP/m1.json"; ok "malformed json refused" $? 1

if [[ $fail -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "FAILURES PRESENT"; exit 1; fi
