// The heartbeat arming manifest (#6242 Audit Matrix Deliverable A; extracted from
// heartbeat-reprovision-parity.test.ts for #6537).
//
// A heartbeat's "what feeds this?" answer used to live in a code COMMENT. #6537: the registry's
// said a probe cron had shipped; it had never been written, and the monitor sat inert for 9 days.
// A comment cannot fail CI, so `feeder` below is EXECUTABLE — every arming claim is a file plus a
// syntactic construct the parity test greps on every run. See ADR-117 for the decision, the
// rejected alternatives, and the states this does NOT cover.

/** How a heartbeat's ping is armed — keyed on the MONITORED HOST'S REMEDIATION (CTO, #6242). */
export type Arming =
  | "dedicated-host-boot"
  | "web-host-cron"
  | "app-emit"
  | "external-probe";

/**
 * What actually emits the ping.
 *
 * `cron`/`timer` carry EVIDENCE: a file, and the **arming construct** within it — the line that
 * actually causes the feeder to run (`systemctl enable --now <unit>`, a `- path: /etc/cron.d/<x>`
 * drop-in). Deliberately NOT the unit's bare name: `inngest-heartbeat.timer` appears three times
 * in its bootstrap script, and one of them is a comment — so a bare-name check stays green after
 * the arming line is deleted, i.e. prose alone would satisfy the guard built to kill prose.
 * Matching runs against a COMMENT-STRIPPED view for the same reason.
 *
 * `none` is the honest declaration that nothing pings this heartbeat yet. It is not a loophole: it
 * costs a `tracking_issue`, and the guard asserts the heartbeat has no feeder by EITHER delivery
 * route this repo uses (see `feederDeliveryProbes`).
 */
export type Feeder =
  | {
      kind: "cron" | "timer";
      /** `file` is repo-root-relative; `pattern` is matched as a FIXED string (grep -F). */
      evidence: { file: string; pattern: string };
    }
  | {
      kind: "none";
      /**
       * The Doppler secret holding this heartbeat's ping URL, or null if none is provisioned.
       * When non-null the guard asserts it has zero DEREFERENCING consumers.
       */
      url_secret: string | null;
      /** The issue that owns building the feeder — or deleting the heartbeat. */
      tracking_issue: number;
    };

export interface ManifestEntry {
  /** The resource name (betteruptime_heartbeat.<name>). */
  name: string;
  arming: Arming;
  /** DECLARED paused value; asserted equal to the value parsed from the .tf source. */
  paused: boolean;
  /** What pings it. Executable — see the Feeder docstring. */
  feeder: Feeder;
  /**
   * Required IFF arming === "dedicated-host-boot". `choice` is the apply_target option; `server`
   * is the `hcloud_server.<host>` the job -replaces.
   */
  replace_target?: { choice: string; server: string };
  /** Required for every entry whose arming is NOT dedicated-host-boot. */
  exempt_reason?: string;
  /**
   * Declares that this heartbeat's arming is DELIBERATELY deferred (created paused in Better Stack,
   * to be armed out-of-band later — ADR-117 "FED-but-inert", a legal state at merge). When set, the
   * nightly live-reconcile (#6549 item 2) does NOT raise the `fed-but-paused` alert for this row: a
   * paused-yet-fed monitor is EXPECTED during the owner's deferred-arming window. It costs an owning
   * issue — the honest-declaration idiom mirrors `feeder:{kind:"none", tracking_issue}`. Remove it
   * (at cutover/arming) and a still-paused fed monitor fires for real. It does NOT suppress the
   * `absent-live` alert — a declared-but-not-applied monitor is still surfaced.
   */
  arming_pending?: { tracking_issue: number };
}

/**
 * Regexes that detect a feeder for `<name>`, one per delivery route this repo actually uses.
 * An unfed (`kind:"none"`) row must match NEITHER. Both are needed:
 *
 *  - **deref**: the feeder reads the URL from a Doppler secret (`$INNGEST_HEARTBEAT_URL` in
 *    inngest-bootstrap.sh — the live, armed precedent). Anchored on the DEREFERENCE, never the
 *    bare name: a bare-name grep also matches the secret's own `name = "..."` definition and
 *    plain prose, so it reports feeders that do not exist — the very fiction being replaced.
 *  - **bake**: the feeder gets the URL baked in via `templatefile` (`liveness_heartbeat_url =
 *    betteruptime_heartbeat.registry_prd.url`), dereferencing nothing. This is the route #6537
 *    itself introduced, so a deref-only guard would be blind to the exact shape this repo now
 *    treats as canonical. `value = ...` is excluded: that is a doppler_secret/output DEFINITION,
 *    not a delivery into a template.
 */
export function feederDeliveryProbes(name: string, urlSecret: string | null): RegExp[] {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const probes: RegExp[] = [
    new RegExp(`^\\s*(?!value\\s*=)[A-Za-z0-9_]+\\s*=\\s*betteruptime_heartbeat\\.${esc(name)}\\.url`, "m"),
  ];
  if (urlSecret) probes.push(new RegExp(`\\$\\{?${esc(urlSecret)}\\}?`));
  return probes;
}

// One row per heartbeat. Adding a heartbeat to the .tf files WITHOUT adding a row here FAILS the
// discovered⊆manifest assertion.
export const MANIFEST: ManifestEntry[] = [
  {
    name: "github_webhook_sig_failures",
    arming: "app-emit",
    paused: true,
    // Its source comment claimed the webhook route "deliberately pings" this. Nothing does.
    feeder: { kind: "none", url_secret: null, tracking_issue: 6549 },
    exempt_reason:
      "app/container would emit the ping; remediation is a container ci-deploy, not a dedicated-host reprovision. count=0 under the free tier (betterstack_paid_tier=false), so it is not provisioned live.",
  },
  {
    name: "github_api_429_sustained",
    arming: "app-emit",
    paused: true,
    // Structurally the same unfed shape as its sibling above, at a different cadence (900/120 vs
    // 300/60) — and it never carried the false ping claim; that sat on only one of the two.
    feeder: { kind: "none", url_secret: null, tracking_issue: 6549 },
    exempt_reason:
      "app/container would emit the ping; remediation is a container ci-deploy, not a dedicated-host reprovision. count=0 under the free tier (betterstack_paid_tier=false), so it is not provisioned live.",
  },
  {
    name: "workspaces_luks",
    // #6604 — the daily /workspaces LUKS at-rest probe heartbeat. Two pushers feed it:
    //   1. luks-monitor.timer on web-1, delivered and armed by terraform_data.luks_monitor_install
    //      (workspaces-luks.tf) in the per-merge SSH apply (#8706). Until #8706 the only installer
    //      was the cutover script's tail, which no real cutover reached, so this pusher never ran
    //      (ADR-119 addendum 2026-09-27; ADR-117 amendment 2026-09-27).
    //      Terraform is the PRIMARY installer. The cutover tail still installs the same files, so it
    //      stays a redundant second installer for a future re-cut.
    //   2. The daily workspaces-luks-verify.yml job, which ships its own copy of luks-monitor.sh.
    // The shared beat cannot tell them apart. The runtime proof that pusher 1 runs is
    // logtail_exploration_alert.luks_monitor_host_timer_dark (betterstack-logs-alerts.tf).
    // web-1 is cx33-unrebuildable and never re-runs cloud-init, so there is NO host-replace path:
    // web-host-cron, NOT dedicated-host-boot, and the replace_target requirement does not fire.
    arming: "web-host-cron",
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/workspaces-luks.tf",
        pattern: "systemctl enable --now luks-monitor.timer",
      },
    },
    // No `arming_pending`: it is ARMED. This row carried `arming_pending: { tracking_issue: 6604 }`
    // while the monitor waited for the cutover's first measured beat. The beat has pushed since
    // 2026-08-04 (runbook workspaces-luks-cutover-6604.md, "Failure signals"), and a read-only
    // GET /api/v2/heartbeats/478794 on 2026-09-27 (#8706) read soleur-workspaces-luks-prd
    // `paused:false status:up`. Removal follows OBSERVED arming, not #6604 closing (the
    // inngest_consumer precedent), so the live reconcile's `fed-but-paused` alarm is re-armed for
    // this row: a pause from here on is a real finding. `paused: true` above is SOURCE state only.
    exempt_reason:
      "web-host-resident feeder (luks-monitor.timer on web-1) delivered and armed by the SSH terraform_data provisioner (terraform_data.luks_monitor_install, #8706) as the PRIMARY installer; the cutover script's tail still installs the same files as a redundant second installer for a future re-cut, and web-1 cloud-init boot is NOT a path — web-1 is cx33-unrebuildable and never re-runs cloud-init, so there is NO <host>-host-replace path. The second pusher is the workspaces-luks-verify.yml job; the runtime proof that the host timer fires is logtail_exploration_alert.luks_monitor_host_timer_dark. Not dedicated-host-boot, so ADR-103's replace_target requirement correctly does not fire.",
  },
  {
    name: "git_data_prd",
    arming: "web-host-cron",
    paused: true,
    // #5274 PR C (#6548) SHIPPED the web-host probe — so this row is FLIPPED from the former
    // {kind:"none", tracking_issue:6548} to a fed timer. The forcing function #6537 lacked fired
    // exactly as designed: shipping web-git-data-probe.sh (which dereferences GIT_DATA_HEARTBEAT_URL)
    // reddened the "still unfed by BOTH routes" tripwire, forcing this reconciliation. The feeder is
    // the SSH-provisioner-delivered timer (terraform_data.git_data_probe_install in server.tf).
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/server.tf",
        pattern: "systemctl enable --now web-git-data-probe.timer",
      },
    },
    exempt_reason:
      "web-host-resident feeder (web-git-data-probe.timer on web-1), delivered by the SSH terraform_data provisioner — NOT a git-data cloud-init cron. Reprovisioning git-data would not arm it; its remediation is web-host ci-deploy/provision. (git-data-host-replace exists for immutable-redeploy compliance, not to arm this heartbeat.)",
  },
  {
    name: "web_zot_consumer",
    // #6438 §1 — the zot CONSUMER-perspective serviceability probe. web-host-cron (NOT dedicated-
    // host-boot): web-1 is cx33-unrebuildable and never re-runs cloud-init, so the feeder is
    // delivered by an SSH terraform_data provisioner — there is NO <host>-host-replace path, and
    // ADR-103's replace_target requirement correctly does not fire (mirrors workspaces_luks/
    // git_data_prd). for_each var.web_hosts, so the discovered resource name is web_zot_consumer.
    arming: "web-host-cron",
    // paused in source (ignore_changes=[paused]); the apply-workflow arm gate PATCHes it live after
    // a measured beat (ADR-117 automated). Source stays paused, so this stays true (mirrors
    // inngest_prd/registry_prd: source paused, live unpaused after a one-time measured PATCH).
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/server.tf",
        pattern: "systemctl enable --now web-zot-consumer-probe.timer",
      },
    },
    exempt_reason:
      "web-host-resident feeder (web-zot-consumer-probe.timer on web-1) delivered by the SSH terraform_data provisioner (terraform_data.zot_consumer_probe_install), NOT web-1 cloud-init boot — web-1 is cx33-unrebuildable and never re-runs cloud-init, so there is NO <host>-host-replace path. Not dedicated-host-boot, so ADR-103's replace_target requirement correctly does not fire.",
  },
  {
    name: "web_nic_guard",
    // #6438 §3 — the private-NIC self-report's dedicated liveness beat (pinged every healthy guard
    // run so the SOLEUR_PRIVATE_NIC emitter is observable-when-healthy). Same web-host-cron/SSH-
    // provisioner delivery + arming shape as web_zot_consumer above; PERMANENT and independent of
    // the zot beat (distinct failure domain — folding would re-introduce OR-masking).
    arming: "web-host-cron",
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/server.tf",
        pattern: "systemctl enable --now web-private-nic-guard.timer",
      },
    },
    exempt_reason:
      "web-host-resident feeder (web-private-nic-guard.timer on web-1) delivered by the SSH terraform_data provisioner (terraform_data.private_nic_guard_install), NOT web-1 cloud-init boot — web-1 is cx33-unrebuildable. No <host>-host-replace path, so ADR-103's replace_target requirement correctly does not fire.",
  },
  {
    name: "inngest_consumer",
    // #7228 — the inngest CONSUMER-perspective serviceability beat. web-host-cron, not
    // dedicated-host-boot, and that is the entire point of the design: its feeder runs on web-1
    // and reads 10.0.1.40:8288 over the private net, so it detects a dark dedicated host WITHOUT
    // depending on that host's bootstrap having run and WITHOUT a host replace. web-1 is
    // cx33-unrebuildable and never re-runs cloud-init, so delivery is the SSH terraform_data
    // provisioner and ADR-103's replace_target requirement correctly does not fire (mirrors
    // web_zot_consumer / git_data_prd / workspaces_luks).
    arming: "web-host-cron",
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/server.tf",
        pattern: "systemctl enable --now inngest-consumer-probe.timer",
      },
    },
    // No `arming_pending`: it is ARMED. This row carried `arming_pending: { tracking_issue: 7462 }`
    // while the dedicated inngest host had not bound :8288 (the probe correctly suppressed every
    // beat), and its removal was to follow OBSERVED arming, not #7462 closing. Observed 2026-09-15
    // (#7884 review, read-only GET /api/v2/heartbeats): soleur-inngest-consumer-prd id 482259
    // `paused:false status:up`, with #7462 CLOSED 2026-08-20. So the twice-daily live reconcile's
    // `fed-but-paused` alarm is re-armed for this row: a pause from here on is a real finding.
    exempt_reason:
      "web-host-resident feeder (inngest-consumer-probe.timer on web-1) delivered by the SSH terraform_data provisioner (terraform_data.inngest_consumer_probe_install), NOT cloud-init boot on either host. It monitors the dedicated inngest host from the consumer side precisely so that arming it never requires an inngest-host-replace, so ADR-103's replace_target requirement correctly does not fire.",
  },
  {
    name: "inngest_prd",
    arming: "dedicated-host-boot",
    // Source says paused=true; LIVE is paused=false / up (self-pulled from /api/v2/heartbeats).
    // That divergence is the proof that source is not live: Terraform never sets paused=false, and
    // ignore_changes=[paused] means it never reverts one. It was armed out-of-band once its feeder
    // existed — exactly the step registry_prd never got.
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/inngest-bootstrap.sh",
        pattern: "systemctl enable --now inngest-heartbeat.timer",
      },
    },
    replace_target: { choice: "inngest-host-replace", server: "hcloud_server.inngest" },
  },
  {
    name: "registry_prd",
    // #6537: was `web-host-cron` + an exempt_reason citing an unshipped probe cron — the
    // classification was the bug's hiding place. It is armed by the registry's OWN cloud-init now,
    // so it is dedicated-host-boot, which makes ADR-103's replace_target requirement fire. That is
    // intended: cloud-init is per-instance, so the feeder reaches the host only on a fresh boot.
    arming: "dedicated-host-boot",
    // Stays paused in source; live arming is a one-time API PATCH after a real beat is measured.
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/cloud-init-registry.yml",
        pattern: "systemctl enable --now zot-liveness-heartbeat.timer",
      },
    },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  },
  {
    name: "registry_disk_prd",
    arming: "dedicated-host-boot",
    paused: false,
    // The #6238 exemplar. NOTE its scope, which #6537 mis-stated: it pings on `df` alone, so it
    // alarms HOST death by absence but stays GREEN with zot dead. registry_prd covers that gap.
    // A cron.d drop-in is armed by existing, so its `- path:` delivery IS the arming construct.
    feeder: {
      kind: "cron",
      evidence: {
        file: "apps/web-platform/infra/cloud-init-registry.yml",
        pattern: "- path: /etc/cron.d/zot-disk-heartbeat",
      },
    },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  },
];
