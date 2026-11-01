#!/usr/bin/env bash
# shellcheck shell=bash
# test-cf-lb-overlay-gate.sh — unit tests for tests/scripts/lib/cf-lb-overlay-gate.sh
# (#11181 F3). Feeds synthetic plan JSON; never touches Cloudflare or terraform.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/cf-lb-overlay-gate.sh"
TMP="$(mktemp -d -t cf-lb-gate-test.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT
fail=0
checks=0
ok() { checks=$((checks+1)); if [[ "$2" -eq "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 (want rc $3, got $2)"; fail=1; fi; }
run() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; return $rc; }

source "$LIB"

mk() { printf '%s' "$2" > "$TMP/$1.json"; }

REC_NOOP='{"address":"cloudflare_record.lb_staging","change":{"actions":["no-op"]}}'
REC_CREATE='{"address":"cloudflare_record.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging","type":"A","proxied":true,"content":"203.0.113.10"}}}'
MON='{"address":"cloudflare_load_balancer_monitor.lb_staging","change":{"actions":["create"],"after":{"path":"/health"}}}'
POOL='{"address":"cloudflare_load_balancer_pool.lb_staging","change":{"actions":["create"]}}'
LB='{"address":"cloudflare_load_balancer.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging.soleur.ai"}}}'
WEB1='{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}}'
GA_LB='{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai","enabled":true,"proxied":true}}}'
GA_POOL='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"203.0.113.10"}]}}}'
GA_MON='{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["create"],"after":{"path":"/health"}}}'

# --- record arm ---
mk r1 "{\"resource_changes\":[${REC_CREATE}]}"
run cf_lb_gate_record "$TMP/r1.json"; ok "record: single pinned create passes" $? 0
mk r1b '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"],"after":{"name":"app","type":"A","proxied":true,"content":"203.0.113.66"}}}]}'
run cf_lb_gate_record "$TMP/r1b.json"; ok "record: prod-hostname rename refused" $? 1
mk r1c '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging","type":"CNAME","proxied":true,"content":"x.example"}}}]}'
run cf_lb_gate_record "$TMP/r1c.json"; ok "record: non-A type refused" $? 1
mk r1d '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"],"after":{"name":"lb-staging","type":"A","proxied":false,"content":"203.0.113.10"}}}]}'
run cf_lb_gate_record "$TMP/r1d.json"; ok "record: unproxied refused" $? 1
mk r2 "{\"resource_changes\":[${REC_CREATE},{\"address\":\"cloudflare_record.other\",\"change\":{\"actions\":[\"create\"]}}]}"
run cf_lb_gate_record "$TMP/r2.json"; ok "record: extra create refused" $? 1
mk r3 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["delete"]}}]}'
run cf_lb_gate_record "$TMP/r3.json"; ok "record: delete refused" $? 1
mk r4 "{\"resource_changes\":[${REC_NOOP}]}"
run cf_lb_gate_record "$TMP/r4.json"; ok "record: converged no-op re-dispatch passes" $? 0
mk r5 '{"resource_changes":[]}'
run cf_lb_gate_record "$TMP/r5.json"; ok "record: empty plan refused" $? 1
mk r6 "{\"resource_changes\":[${REC_NOOP},{\"address\":\"data.hcloud_server.web_1\",\"mode\":\"data\",\"change\":{\"actions\":[\"read\"]}}]}"
run cf_lb_gate_record "$TMP/r6.json"; ok "record: deferred data read tolerated" $? 0
mk r7 "{\"resource_changes\":[${REC_NOOP},{\"address\":\"x.y\",\"change\":{\"actions\":[\"forget\"]}}]}"
run cf_lb_gate_record "$TMP/r7.json"; ok "record: forget verb refused" $? 1

# --- overlay arm ---
mk o1 "{\"resource_changes\":[${REC_NOOP},${MON},${POOL},${LB}]}"
run cf_lb_gate_overlay "$TMP/o1.json"; ok "overlay: LB3 creates + converged record + hostname pass" $? 0
mk o2 "{\"resource_changes\":[${REC_NOOP},{\"address\":\"cloudflare_load_balancer.lb_staging\",\"change\":{\"actions\":[\"create\"],\"after\":{\"name\":\"app.soleur.ai\"}}}]}"
run cf_lb_gate_overlay "$TMP/o2.json"; ok "overlay: app.soleur.ai name refused" $? 1
mk o3 "{\"resource_changes\":[${REC_NOOP},${LB},{\"address\":\"hcloud_server.web\",\"change\":{\"actions\":[\"delete\"]}}]}"
run cf_lb_gate_overlay "$TMP/o3.json"; ok "overlay: destructive change refused" $? 1
mk o4 "{\"resource_changes\":[${REC_NOOP},${LB},{\"address\":\"hcloud_volume.x\",\"change\":{\"actions\":[\"create\"]}}]}"
run cf_lb_gate_overlay "$TMP/o4.json"; ok "overlay: out-of-scope create refused" $? 1
mk o5 "{\"resource_changes\":[${MON},${POOL},${LB}]}"
run cf_lb_gate_overlay "$TMP/o5.json"; ok "overlay: absent record (record arm skipped) refused" $? 1
mk o6 "{\"resource_changes\":[${REC_CREATE},${MON},${POOL},${LB}]}"
run cf_lb_gate_overlay "$TMP/o6.json"; ok "overlay: record create in overlay arm refused (sequencing)" $? 1
mk o7 "{\"resource_changes\":[${REC_NOOP},${LB},{\"address\":\"cloudflare_record.app\",\"change\":{\"actions\":[\"forget\"]}}]}"
run cf_lb_gate_overlay "$TMP/o7.json"; ok "overlay: forget verb refused" $? 1
mk o8 "{\"resource_changes\":[${REC_NOOP},${LB},{\"address\":\"hcloud_server.web[\\\"web-1\\\"]\",\"change\":{\"actions\":[]}}]}"
run cf_lb_gate_overlay "$TMP/o8.json"; ok "overlay: empty-actions entry refused" $? 1
mk o9 "{\"resource_changes\":[${REC_NOOP},${LB},{\"address\":\"x.y\",\"change\":{\"actions\":[\"import\"]}}]}"
run cf_lb_gate_overlay "$TMP/o9.json"; ok "overlay: import verb refused" $? 1

# --- teardown arm ---
mk t1 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["delete"]}},{"address":"cloudflare_load_balancer_monitor.lb_staging","change":{"actions":["delete"]}},{"address":"cloudflare_load_balancer_pool.lb_staging","change":{"actions":["delete"]}},{"address":"cloudflare_load_balancer.lb_staging","change":{"actions":["delete"]}}]}'
run cf_lb_gate_teardown "$TMP/t1.json"; ok "teardown: all-four deletes pass" $? 0
mk t2 '{"resource_changes":[{"address":"hcloud_server.web","change":{"actions":["delete"]}}]}'
run cf_lb_gate_teardown "$TMP/t2.json"; ok "teardown: prod delete refused" $? 1
mk t3 '{"resource_changes":[]}'
run cf_lb_gate_teardown "$TMP/t3.json"; ok "teardown: empty (idempotent) passes" $? 0
mk t4 '{"resource_changes":[{"address":"data.hcloud_server.web_1","mode":"data","change":{"actions":["read"]}},{"address":"cloudflare_record.lb_staging","change":{"actions":["delete"]}}]}'
run cf_lb_gate_teardown "$TMP/t4.json"; ok "teardown: deferred data read tolerated" $? 0
mk t5 '{"resource_changes":[{"address":"cloudflare_record.lb_staging","change":{"actions":["create"]}}]}'
run cf_lb_gate_teardown "$TMP/t5.json"; ok "teardown: create refused" $? 1

# --- ga arm ---
mk g1 "{\"resource_changes\":[${WEB1},${GA_MON},${GA_POOL},${GA_LB}]}"
run cf_lb_gate_ga "$TMP/g1.json"; ok "ga: trio creates + no-op dep + pinned attrs pass" $? 0
mk g2 "{\"resource_changes\":[${WEB1},${GA_LB},{\"address\":\"cloudflare_record.app\",\"change\":{\"actions\":[\"delete\"]}}]}"
run cf_lb_gate_ga "$TMP/g2.json"; ok "ga: record delete refused" $? 1
mk g3 "{\"resource_changes\":[${WEB1},${GA_LB},{\"address\":\"doppler_secret.x\",\"change\":{\"actions\":[\"forget\"]}}]}"
run cf_lb_gate_ga "$TMP/g3.json"; ok "ga: forget verb refused" $? 1
mk g4 "{\"resource_changes\":[${WEB1},${GA_LB},{\"address\":\"hcloud_server.web[\\\"web-1\\\"]\",\"change\":{\"actions\":[]}}]}"
run cf_lb_gate_ga "$TMP/g4.json"; ok "ga: empty-actions entry refused" $? 1
mk g5 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"evil.soleur.ai"}}}}]}'
run cf_lb_gate_ga "$TMP/g5.json"; ok "ga: wrong LB hostname refused" $? 1
mk g6 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"6.6.6.6"}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}}]}'
run cf_lb_gate_ga "$TMP/g6.json"; ok "ga: repointed pool origin refused" $? 1
mk g7 '{"resource_changes":[]}'
run cf_lb_gate_ga "$TMP/g7.json"; ok "ga: empty plan refused" $? 1
mk g8 "{\"resource_changes\":[${GA_LB},${GA_POOL}]}"
run cf_lb_gate_ga "$TMP/g8.json"; ok "ga: missing web-1 no-op (origins unverifiable) refused" $? 1
mk g9 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai","enabled":false}}}]}'
run cf_lb_gate_ga "$TMP/g9.json"; ok "ga: disabled LB refused" $? 1
# widened origins pin: web-2's resolved IP is a member of the create-arm allow-set.
mk g10 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"203.0.113.10"},{"address":"203.0.113.20"}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g10.json"; ok "ga: {web-1,web-2} origins ⊆ plan-resolved set pass" $? 0
mk g11 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"203.0.113.10"},{"address":"6.6.6.6"}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g11.json"; ok "ga: third-IP origin beside resolved set refused" $? 1

# --- ga-monitor-fix arm ---
MON_UPD='{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["update"],"after":{"type":"http","port":80,"path":"/health","expected_codes":"200"}}}'
mk mu1 "{\"resource_changes\":[${MON_UPD}]}"
run cf_lb_gate_ga_monitor_update "$TMP/mu1.json"; ok "monitor-fix: pinned http/:80 update passes" $? 0
mk mu2 '{"resource_changes":[{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["update"],"after":{"type":"https","port":443,"path":"/health","expected_codes":"200"}}}]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu2.json"; ok "monitor-fix: https/:443 retained refused" $? 1
mk mu3 '{"resource_changes":[]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu3.json"; ok "monitor-fix: empty plan refused" $? 1
mk mu4 "{\"resource_changes\":[${MON_UPD},{\"address\":\"cloudflare_load_balancer_pool.web_1\",\"change\":{\"actions\":[\"update\"]}}]}"
run cf_lb_gate_ga_monitor_update "$TMP/mu4.json"; ok "monitor-fix: second member smuggled beside refused" $? 1
mk mu5 '{"resource_changes":[{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["delete","create"]}}]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu5.json"; ok "monitor-fix: delete+create (replace) refused" $? 1
mk mu6 '{"resource_changes":[{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["update"],"after":{"type":"http","port":443,"path":"/health","expected_codes":"200"}}}]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu6.json"; ok "monitor-fix: right type wrong port refused" $? 1
mk mu7 "{\"resource_changes\":[${MON_UPD},{\"address\":\"data.hcloud_server.web_1\",\"mode\":\"data\",\"change\":{\"actions\":[\"read\"]}}]}"
run cf_lb_gate_ga_monitor_update "$TMP/mu7.json"; ok "monitor-fix: deferred data read tolerated" $? 0
mk mu8 '{"resource_changes":[{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["update"],"after":{"type":"http","port":80,"path":"/healthz","expected_codes":"200"}}}]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu8.json"; ok "monitor-fix: wrong path refused" $? 1
run cf_lb_gate_ga_monitor_update "$TMP/nonexistent.json"; ok "monitor-fix: unreadable plan refused" $? 1

# --- ga-pool-update arm ---
WEB2='{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}}'
POOL_DRAIN='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}}'
POLICY_UPD='{"address":"cloudflare_notification_policy.web_lb_health","change":{"actions":["update"]}}'
mk pu1 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${POLICY_UPD}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu1.json" drain; ok "pool-update: drain origins {web-1@1,web-2@0} + policy pass" $? 0
mk pu2 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu2.json" drain; ok "pool-update: drain-mode web-2 weight=1 (smuggled flip) refused" $? 1
mk pu3 "{\"resource_changes\":[${WEB1},${POOL_DRAIN}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu3.json" drain; ok "pool-update: web-2 IP unresolvable refused" $? 1
mk pu4 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"6.6.6.6","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu4.json" drain; ok "pool-update: repointed web-1 origin refused" $? 1
mk pu5 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},{\"address\":\"cloudflare_record.app\",\"change\":{\"actions\":[\"update\"]}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu5.json" drain; ok "pool-update: out-of-set address (record.app) refused" $? 1
mk pu6 '{"resource_changes":[]}'
run cf_lb_gate_ga_pool_update "$TMP/pu6.json" drain; ok "pool-update: empty plan refused" $? 1
mk pu7 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu7.json" bogus; ok "pool-update: invalid mode refused" $? 1
mk pu8 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu8.json" serve; ok "pool-update: serve-mode weight=1 admitted (gate chain runs in the job)" $? 0
mk pu9 "{\"resource_changes\":[${WEB1},${WEB2},{\"address\":\"cloudflare_load_balancer_pool.web_1\",\"change\":{\"actions\":[\"create\"],\"after\":{\"origins\":[{\"name\":\"web-1\",\"address\":\"203.0.113.10\",\"weight\":1}]}}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu9.json" drain; ok "pool-update: create verb refused" $? 1
mk pu10 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},{\"address\":\"hcloud_server.web[\\\"web-1\\\"]\",\"change\":{\"actions\":[\"delete\"]}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu10.json" drain; ok "pool-update: destructive host change refused" $? 1

# --- malformed ---
mk m1 'not json'
run cf_lb_gate_record "$TMP/m1.json"; ok "malformed json refused" $? 1
mk m2 '{"resource_changes":[{"address":"x.y","change":{"actions":42}}]}'
run cf_lb_gate_ga "$TMP/m2.json"; ok "unclassifiable actions refused" $? 1

# anti-vacuity floor: the suite must have exercised a real battery, not a stubbed one.
if [[ "$checks" -lt 25 ]]; then echo "FAIL: anti-vacuity — only $checks assertions ran"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL TESTS PASSED ($checks assertions)"; else echo "FAILURES PRESENT"; exit 1; fi
