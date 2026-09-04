#!/usr/bin/env python3
"""Generate sentry_alert HCL for #7650 Phase 2 from the committed live capture.

The capture is the ONLY authoring source -- never issue-alerts.tf, and never
configure-sentry-alerts.sh (measured 2026-09-04: the script is the drift source,
writing frequency 60 where live carries 60/61/62).
"""
import json, re, sys, io, os

ROOT = os.environ.get("REPO", ".")
CAP = os.path.join(ROOT, "knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json")
OUTDIR = os.environ["OUTDIR"]

EXCLUDE = {"event_unique_user_frequency_count", "new_high_priority_issue", "existing_high_priority_issue"}

def in_scope(w):
    return not any(c["type"] in EXCLUDE for c in w["triggers"]["conditions"])

# Resource labels are derived MECHANICALLY from the live name (- -> _), with an
# explicit override table for the three that are NOT mechanical. Those three
# aliases previously existed only inside the `sentry_issue_alert` blocks this
# migration deletes, so without this table they are an unencoded invariant: a
# future author "correcting" them would rename a Terraform address, which is a
# destroy+create of a live paging rule.
#
# This function deliberately does NOT parse issue-alerts.tf. An earlier revision
# did, and became unrunnable the moment task 3.4 deleted the blocks it read --
# so the script's whole reason to exist (re-run it and diff, rather than reading
# 27 blocks by eye) was void exactly when a reviewer needed it.
LABEL_OVERRIDES = {
    "cron-egress-blocked": "egress_blocked",
    "web-host-private-nic-boot-gate": "web_private_nic_boot_gate",
    "web-host-terminal-boot-fatal": "web_terminal_boot_fatal",
}

def resource_label(live_name):
    return LABEL_OVERRIDES.get(live_name, live_name.replace("-", "_"))

caps = json.load(io.open(CAP, encoding="utf-8"))
scoped = sorted([w for w in caps if in_scope(w)], key=lambda w: w["name"])

name_to_res = {w["name"]: resource_label(w["name"]) for w in scoped}
if len(scoped) != 27:
    sys.exit("FATAL: expected 27 in scope, got %d" % len(scoped))

def q(s):
    return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')

blocks, removed, imports = [], [], []
for w in scoped:
    res, wid = name_to_res[w["name"]], w["id"]
    tcs = []
    for c in w["triggers"]["conditions"]:
        t = c["type"]
        if t in ("first_seen_event", "reappeared_event", "regression_event", "issue_resolved_trigger"):
            tcs.append("    { %s = {} }," % t)
        elif t == "event_frequency_count":
            cmp_ = c["comparison"]
            if not isinstance(cmp_, dict):
                sys.exit("FATAL: bare-boolean comparison on %s would drop to legacy_trigger_conditions" % w["name"])
            tcs.append("    { event_frequency_count = { interval = %s, value = %s } }," % (q(cmp_["interval"]), cmp_["value"]))
        else:
            sys.exit("FATAL: unmapped trigger type %s on %s" % (t, w["name"]))

    afs = []
    for af in w["actionFilters"]:
        conds = []
        for c in (af.get("conditions") or []):
            if c["type"] != "tagged_event":
                sys.exit("FATAL: unmapped filter condition %s on %s" % (c["type"], w["name"]))
            cm = c["comparison"]
            conds.append("        { tagged_event = { key = %s, match = %s, value = %s } }," % (q(cm["key"]), q(cm["match"]), q(cm["value"])))
        acts = []
        for a in (af.get("actions") or []):
            if a["type"] != "email":
                sys.exit("FATAL: unmapped action %s on %s" % (a["type"], w["name"]))
            inner = "target_type = %s" % q(a["config"]["targetType"])
            ft = (a.get("data") or {}).get("fallthroughType")
            if ft:
                inner += ", fallthrough_type = %s" % q(ft)
            acts.append("        { email = { %s } }," % inner)
        afs.append("    {\n      logic_type = %s\n      conditions = [\n%s\n      ]\n      actions = [\n%s\n      ]\n    }," % (q(af["logicType"]), "\n".join(conds), "\n".join(acts)))

    blocks.append(
        'resource "sentry_alert" "%s" {\n'
        "  organization      = var.sentry_org\n"
        "  name              = %s\n"
        "  enabled           = %s\n"
        "  frequency_minutes = %s\n"
        "  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]\n\n"
        "  trigger_conditions = [\n%s\n  ]\n\n"
        "  action_filters = [\n%s\n  ]\n\n"
        "  lifecycle {\n    ignore_changes = [environment]\n  }\n"
        "}\n"
        % (res, q(w["name"]), "true" if w["enabled"] else "false",
           w["config"]["frequency"],
           "\n".join(tcs), "\n".join(afs))
    )
    removed.append("removed {\n  from = sentry_issue_alert.%s\n  lifecycle {\n    destroy = false\n  }\n}\n" % res)
    imports.append('import {\n  to = sentry_alert.%s\n  id = "${var.sentry_org}/%s"\n}\n' % (res, wid))

io.open(os.path.join(OUTDIR, "gen_blocks.tf"), "w", encoding="utf-8").write("\n".join(blocks))
io.open(os.path.join(OUTDIR, "gen_removed.tf"), "w", encoding="utf-8").write("\n".join(removed))
io.open(os.path.join(OUTDIR, "gen_imports.tf"), "w", encoding="utf-8").write("\n".join(imports))
print("generated blocks=%d removed=%d imports=%d" % (len(blocks), len(removed), len(imports)))
