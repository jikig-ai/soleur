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
WEB2='{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}}'
GA_LB='{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai","enabled":true,"proxied":true}}}'
GA_POOL='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1,"enabled":true},{"name":"web-2","address":"203.0.113.20","weight":0,"enabled":true}]}}}'
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
mk g1 "{\"resource_changes\":[${WEB1},${WEB2},${GA_MON},${GA_POOL},${GA_LB}]}"
run cf_lb_gate_ga "$TMP/g1.json"; ok "ga: trio creates + no-op deps + pinned attrs pass" $? 0
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
mk g10 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"203.0.113.10","weight":1},{"address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g10.json"; ok "ga: {web-1,web-2} origins ⊆ plan-resolved set pass" $? 0
mk g11 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"address":"203.0.113.10"},{"address":"6.6.6.6"}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g11.json"; ok "ga: third-IP origin beside resolved set refused" $? 1
# web-2's resolved IP is load-bearing since the drained member landed: a plan
# missing web-2's no-op entry cannot prove the origins set even when every
# origin happens to be web-1.
mk g12 "{\"resource_changes\":[${WEB1},${GA_MON},${GA_POOL},${GA_LB}]}"
run cf_lb_gate_ga "$TMP/g12.json"; ok "ga: missing web-2 no-op (origins unverifiable) refused" $? 1
# Drained-shape pin on create (mirrors the drain arm's IP-bound discipline): a
# create that lands web-2 HOT bypasses the serve-window gate chain, and a create
# without web-2's member is the un-drained shape.
mk g13 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g13.json"; ok "ga: web-2 origin created at weight 1 (not drained) refused" $? 1
mk g14 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["create"],"after":{"name":"app.soleur.ai"}}}]}'
run cf_lb_gate_ga "$TMP/g14.json"; ok "ga: create without web-2 member refused" $? 1

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
mk mu9 '{"resource_changes":[{"address":"cloudflare_load_balancer_monitor.web","change":{"actions":["update"],"after":{"type":"http","port":80,"path":"/health","expected_codes":"2xx"}}}]}'
run cf_lb_gate_ga_monitor_update "$TMP/mu9.json"; ok "monitor-fix: expected_codes drift refused" $? 1
run cf_lb_gate_ga_monitor_update "$TMP/nonexistent.json"; ok "monitor-fix: unreadable plan refused" $? 1

# --- ga-pool-update arm ---
# The REAL first-dispatch plan shape is {pool=update, lb=update, policy=create} —
# the notification policy is a NEW resource, so its first plan emits ["create"]
# and the gate must admit it (pool/LB stay update-only).
# The pool entries carry before.id so the repoint pin can resolve the web_1
# pool's identity ("0123abcd" — the same literal GA_LB_UPD's pool references use).
POOL_DRAIN='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}}'
POOL_SERVE='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}'
POOL_NOOP='{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["no-op"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}}'
GA_LB_UPD='{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","enabled":true,"proxied":true,"session_affinity":"none","default_pool_ids":["0123abcd"],"fallback_pool_id":"0123abcd"}}}'
POLICY_CREATE='{"address":"cloudflare_notification_policy.web_lb_health","change":{"actions":["create"],"after":{"enabled":true,"alert_type":"load_balancing_health_alert"}}}'
POLICY_UPD='{"address":"cloudflare_notification_policy.web_lb_health","change":{"actions":["update"],"after":{"enabled":true,"alert_type":"load_balancing_health_alert"}}}'
mk pu1 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${GA_LB_UPD},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu1.json" drain; ok "pool-update: drain {pool=update,lb=update,policy=create} first-dispatch passes" $? 0
mk pu1b "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${POLICY_UPD}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu1b.json" drain; ok "pool-update: update-verb policy also admitted" $? 0
mk pu2 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_SERVE}]}"
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
mk pu8 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_SERVE},${GA_LB_UPD},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu8.json" serve; ok "pool-update: serve-mode 0→1 flip passes (gate chain runs in the job)" $? 0
mk pu9 "{\"resource_changes\":[${WEB1},${WEB2},{\"address\":\"cloudflare_load_balancer_pool.web_1\",\"change\":{\"actions\":[\"create\"],\"after\":{\"origins\":[{\"name\":\"web-1\",\"address\":\"203.0.113.10\",\"weight\":1}]}}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu9.json" drain; ok "pool-update: create verb on the pool refused" $? 1
mk pu9b "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${GA_LB}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu9b.json" drain; ok "pool-update: create verb on the LB refused" $? 1
mk pu10 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},{\"address\":\"hcloud_server.web[\\\"web-1\\\"]\",\"change\":{\"actions\":[\"delete\"]}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu10.json" drain; ok "pool-update: destructive host change refused" $? 1
# Per-IP drain pin: a renamed origin block still resolving web-2's IP is bound by
# the pin regardless of name.
mk pu11 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"standby","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu11.json" drain; ok "pool-update: renamed origin at web-2 IP @1 (drain) refused" $? 1
# Duplicate names: a second name=="web-2" @1 must not hide behind the pinned @0.
mk pu12 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu12.json" drain; ok "pool-update: duplicate web-2 origins (@0 hides @1) refused" $? 1
# Origins ⊆ is never enough alone: a pool whose after-state dropped web-1 serves
# nothing at all.
mk pu13 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-2","address":"203.0.113.20","weight":0}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu13.json" drain; ok "pool-update: dropped web-1 (no serving member) refused" $? 1
mk pu14 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu14.json" drain; ok "pool-update: empty origins list refused" $? 1
out=$(cf_lb_gate_ga_pool_update "$TMP/pu14.json" drain 2>&1); rc=$?
[[ $rc -eq 1 && "$out" == *"no origins in pool after-state"* ]]; ok "pool-update: empty origins gets the distinct refusal (not a weight verdict)" $? 0
mk pu14b '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu14b.json" drain; ok "pool-update: absent origins key refused" $? 1
# REMNANT-ONLY plans (partial-apply re-dispatch): no pool.web_1 update in the
# graded set is ADMITTED iff the allow-set + attr pins pass on the entries that
# exist — a {policy:create}-only re-dispatch must not wedge into the ungraded
# manual apply. The pool's no-op row carries its id for the repoint pin.
mk pu15 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_NOOP},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu15.json" drain; ok "pool-update: remnant {policy:create}-only plan admitted" $? 0
out=$(cf_lb_gate_ga_pool_update "$TMP/pu15.json" drain 2>&1); rc=$?
[[ $rc -eq 0 && "$out" == *"no cloudflare_load_balancer_pool.web_1 change — grading the remaining change(s) only"* ]]; ok "pool-update: remnant admission prints the distinct degraded-grade notice" $? 0
mk pu15b "{\"resource_changes\":[${WEB1},${WEB2},${POOL_NOOP},${GA_LB_UPD},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu15b.json" drain; ok "pool-update: remnant {lb=update,policy=create} with pool-id-matching LB admitted" $? 0
# ...but a remnant carrying a drifted LB still refuses — admission grades
# whatever entries exist, it does not skip grading.
mk pu15c "{\"resource_changes\":[${WEB1},${WEB2},${POOL_NOOP},{\"address\":\"cloudflare_load_balancer.app\",\"change\":{\"actions\":[\"update\"],\"after\":{\"enabled\":false}}}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu15c.json" drain; ok "pool-update: remnant {lb.app update enabled:false} refused" $? 1
# An LB naming pool ids when the pool itself is not in the plan AT ALL is
# unprovable — fail closed (no no-op row to read the id off).
mk pu15d "{\"resource_changes\":[${WEB1},${WEB2},${GA_LB_UPD},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu15d.json" drain; ok "pool-update: remnant LB pool ids with unresolvable pool identity refused" $? 1
out=$(cf_lb_gate_ga_pool_update "$TMP/pu15d.json" drain 2>&1); rc=$?
[[ $rc -eq 1 && "$out" == *"cannot be resolved from the plan's own entries"* ]]; ok "pool-update: unresolvable pool id emits the fail-closed refusal" $? 0
# Serve-mode weight invariant: the drained shape under mode=serve is a refused
# no-flip, not a pass.
mk pu16 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${GA_LB_UPD},${POLICY_CREATE}]}"
run cf_lb_gate_ga_pool_update "$TMP/pu16.json" serve; ok "pool-update: serve-mode drained web-2 (no flip) refused" $? 1
# Resource after-state pins refuse EXPLICIT bad values.
mk pu17 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","enabled":false}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu17.json" drain; ok "pool-update: lb.app enabled=false refused" $? 1
mk pu18 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","session_affinity":"cookie"}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu18.json" drain; ok "pool-update: lb.app session_affinity!=none refused (ADR-068 b.3)" $? 1
mk pu19 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_notification_policy.web_lb_health","change":{"actions":["create"],"after":{"enabled":false,"alert_type":"load_balancing_health_alert"}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu19.json" drain; ok "pool-update: policy enabled=false refused" $? 1
mk pu20 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"","weight":0}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu20.json" drain; ok "pool-update: empty-address origin refused" $? 1

# --- SYMMETRIC-BY-IP escapes (fix-round 2, all verified green pre-fix) ---
# serve: web-1's IP fully dropped — every origin sits at web-2's IP.
mk pu21 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.20","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu21.json" serve; ok "pool-update[serve]: web-1 IP fully dropped refused" $? 1
# serve: a third member shadowing at web-1's IP.
mk pu22 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":1},{"name":"extra","address":"203.0.113.10","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu22.json" serve; ok "pool-update[serve]: third member shadowing web-1 IP refused" $? 1
# drain: web-1 under full weight — the drained shape is {1,0}, not {>0,0}.
mk pu23 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":0.5},{"name":"web-2","address":"203.0.113.20","weight":0}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu23.json" drain; ok "pool-update[drain]: web-1 at weight 0.5 refused" $? 1
# drain: a shadow member at web-1's IP carrying hot weight.
mk pu24 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0},{"name":"extra","address":"203.0.113.10","weight":9}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu24.json" drain; ok "pool-update[drain]: shadow member at web-1 IP @9 refused" $? 1
# serve: name/IP swap — canonical names parked on the wrong hosts' IPs.
mk pu25 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.20","weight":1},{"name":"web-2","address":"203.0.113.10","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu25.json" serve; ok "pool-update[serve]: name/IP swap refused" $? 1
# drain: dup-address shadow member at web-2's IP (two records, same address).
mk pu26 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0},{"name":"shadow","address":"203.0.113.20","weight":0}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu26.json" drain; ok "pool-update[drain]: dup-address shadow member refused" $? 1

# --- pin isolators (each isolates ONE pin from the others) ---
# dup name="web-2" parked at web-1's IP @1: every address is in the allow-set,
# so only the name-dup pin (not the IP pins) can refuse it.
mk pu27 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0},{"name":"web-2","address":"203.0.113.10","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu27.json" drain; ok "pool-update: dup name=web-2 at web-1 IP isolates the name-dup pin" $? 1
# serve with the web-2-IP origin RENAMED: the named-web-2 weight pin is what
# refuses (the IP pins alone would pass the renamed member).
mk pu28 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"standby","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu28.json" serve; ok "pool-update[serve]: renamed web-2-IP origin isolates the named-web-2 weight pin" $? 1
# serve with web-1 under 1: isolates the web-1 weight pin.
mk pu29 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":0.5},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu29.json" serve; ok "pool-update[serve]: web-1 weight != 1 isolates the web-1 weight pin" $? 1

# --- repoint pins (lb.app pool identity) ---
mk pu30 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","default_pool_ids":["deadbeef00"]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu30.json" drain; ok "pool-update: lb.app default_pool_ids repointed to a foreign pool refused" $? 1
mk pu31 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","default_pool_ids":[]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu31.json" drain; ok "pool-update: lb.app default_pool_ids present-empty refused" $? 1
mk pu32 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"before":{"id":"0123abcd"},"after":{"id":"0123abcd","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_load_balancer.app","change":{"actions":["update"],"after":{"name":"app.soleur.ai","default_pool_ids":["0123abcd"],"fallback_pool_id":"deadbeef00"}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu32.json" drain; ok "pool-update: lb.app fallback_pool_id repointed refused" $? 1
# coercion: a STRING "false" origin enabled pin must not escape tostring.
mk pu33 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0,"enabled":"false"}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu33.json" drain; ok "pool-update: string \"false\" origin enabled refused (tostring coercion)" $? 1
# alert_type pins on update too, not just create.
mk pu34 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0}]}}},{"address":"cloudflare_notification_policy.web_lb_health","change":{"actions":["update"],"after":{"enabled":true,"alert_type":"ssl_recommendation"}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu34.json" drain; ok "pool-update: policy UPDATE alert_type drift refused" $? 1
# boolean enabled:false must refuse too — `.enabled // true` maps false→true in jq
# (the // operator treats boolean false as empty); the pins use the null-only default.
mk pu35 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0,"enabled":false}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu35.json" drain; ok "pool-update: boolean enabled:false origin refused (drain)" $? 1
mk pu36 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["update"],"after":{"origins":[{"name":"web-1","address":"203.0.113.10","weight":1,"enabled":false},{"name":"web-2","address":"203.0.113.20","weight":1}]}}}]}'
run cf_lb_gate_ga_pool_update "$TMP/pu36.json" serve; ok "pool-update: boolean enabled:false web-1 refused (serve w1_ok)" $? 1
mk g15 '{"resource_changes":[{"address":"hcloud_server.web[\"web-1\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.10"}}},{"address":"hcloud_server.web[\"web-2\"]","change":{"actions":["no-op"],"after":{"ipv4_address":"203.0.113.20"}}},{"address":"cloudflare_load_balancer_pool.web_1","change":{"actions":["create"],"after":{"name":"web-1","origins":[{"name":"web-1","address":"203.0.113.10","weight":1},{"name":"web-2","address":"203.0.113.20","weight":0,"enabled":false}]}}}]}'
run cf_lb_gate_ga "$TMP/g15.json"; ok "ga-overlay: boolean enabled:false origin refused (create)" $? 1
# Output-capturing assertions: the pass-message suffix is mode-accurate (the old
# ${mode/drain/...} printed a literal "serve" in serve mode).
mk pc1 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_DRAIN},${GA_LB_UPD},${POLICY_CREATE}]}"
out=$(cf_lb_gate_ga_pool_update "$TMP/pc1.json" drain 2>/dev/null); rc=$?
[[ $rc -eq 0 && "$out" == *"ga-pool-update:drain"*", web-2 weight=0"* ]]; ok "pool-update: drain pass message carries the weight=0 suffix" $? 0
mk pc2 "{\"resource_changes\":[${WEB1},${WEB2},${POOL_SERVE},${GA_LB_UPD},${POLICY_CREATE}]}"
out=$(cf_lb_gate_ga_pool_update "$TMP/pc2.json" serve 2>/dev/null); rc=$?
# The "}serve" discriminator is load-bearing: the pre-fix lib expanded
# ${mode/drain/...} into the pass line, printing "...{web-2:<ip>}serve — pass" —
# under it THIS assertion goes red (the old output contains the garble it
# guards against).
[[ $rc -eq 0 && "$out" == *"ga-pool-update:serve"*"pass"* && "$out" != *"web-2 weight=0"* && "$out" != *"}serve"* ]]; ok "pool-update: serve pass message carries NO drain suffix and no }serve garble" $? 0

# --- malformed ---
mk m1 'not json'
run cf_lb_gate_record "$TMP/m1.json"; ok "malformed json refused" $? 1
mk m2 '{"resource_changes":[{"address":"x.y","change":{"actions":42}}]}'
run cf_lb_gate_ga "$TMP/m2.json"; ok "unclassifiable actions refused" $? 1

# anti-vacuity floor: the suite must have exercised a real battery, not a stubbed one.
if [[ "$checks" -lt 98 ]]; then echo "FAIL: anti-vacuity — only $checks assertions ran"; fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL TESTS PASSED ($checks assertions)"; else echo "FAILURES PRESENT"; exit 1; fi
