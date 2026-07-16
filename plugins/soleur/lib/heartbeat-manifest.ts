// The heartbeat arming manifest (#6242 Audit Matrix Deliverable A; extracted from
// heartbeat-reprovision-parity.test.ts for #6537).
//
// WHY THIS IS A MODULE AND NOT A COMMENT
// --------------------------------------
// #6537: `betteruptime_heartbeat.registry_prd` was provisioned `paused = true` on 2026-07-07 as a
// bootstrap step, to be unpaused once "the web-host probe cron ships". The cron was never written.
// The monitor sat inert for 9 days — and the ONLY record of what was supposed to feed it was a
// COMMENT in zot-registry.tf, which said the opposite of the truth.
//
// That is the whole lesson: a heartbeat's "what feeds this?" answer was PROSE, and prose rots
// silently. Two comments in this repo have been flatly false for months — one of them inside the
// guard built to prevent exactly this class (#6242). A comment cannot fail CI.
//
// So `feeder` below is EXECUTABLE. Every claim about what pings a heartbeat is a file+pattern that
// the parity test greps on every run. A feeder that is deleted, renamed, or never written turns the
// suite RED. The invariant this enforces:
//
//   A heartbeat is either FED (feeder.kind ∈ {cron,timer}, with grep-able on-host evidence) or
//   HONESTLY DECLARED UNFED (feeder.kind === "none", with a tracking issue). There is no third
//   state — and "unfed" is the state that must never be silently unpaused.
//
// The invariant admits TWO legal resolutions for an unfed monitor: feed it, or DELETE it. What it
// forbids is the 9-day middle: a provisioned monitor nobody feeds and nobody owns.

/** How a heartbeat's ping is armed — keyed on the MONITORED HOST'S REMEDIATION (CTO, #6242). */
export type Arming =
  | "dedicated-host-boot"
  | "web-host-cron"
  | "app-emit"
  | "external-probe";

/**
 * What actually emits the ping.
 *
 * `cron` / `timer` carry on-host EVIDENCE: a file that exists and a fixed-string pattern that
 * appears in it. This is the executable replacement for the prose `arming` axis — `arming` says
 * which REMEDIATION class the heartbeat belongs to; `feeder` says what CONCRETELY pings it, and is
 * checkable.
 *
 * `none` is the honest declaration that NOTHING pings this heartbeat yet. It is not a loophole:
 * it costs a `tracking_issue`, and if it names a `url_secret`, the guard asserts that secret still
 * has ZERO consumers — so the day someone ships the feeder, CI goes red and forces this row to be
 * reconciled. That inverse assertion is the forcing function #6537 never had.
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
       * When non-null, the guard asserts it has zero DEREFERENCING consumers (see
       * `countUrlSecretConsumers`) — i.e. the feeder genuinely does not exist yet.
       */
      url_secret: string | null;
      /** The issue that owns building the feeder (or deleting the heartbeat). */
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
}

/**
 * Count REAL consumers of a heartbeat URL secret.
 *
 * ANCHORED ON DEREFERENCE, NOT ON THE BARE NAME. This distinction is load-bearing and was found
 * the hard way: `git grep -c GIT_DATA_HEARTBEAT_URL` returns 2 hits, and NEITHER is a feeder —
 * one is the secret's own `name = "..."` definition in .tf, the other is a line of operator prose
 * inside a `cat <<'HEALTH'` heredoc in git-data-cutover.sh. A bare-name grep therefore reports a
 * feeder that does not exist, which is the very fiction this manifest exists to kill.
 *
 * A real consumer must DEREFERENCE the variable (`$VAR` or `${VAR}`) — prose and definitions never
 * do. Verified against the live counter-example: INNGEST_HEARTBEAT_URL is dereferenced exactly
 * where it should be (`curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL"`, inngest-bootstrap.sh),
 * and that heartbeat is the one that is actually armed and up.
 */
export function countUrlSecretConsumers(
  secret: string,
  searchFile: (pattern: RegExp) => number,
): number {
  // `\$\{?NAME\}?` — matches $NAME and ${NAME}; matches neither `name = "NAME"` nor bare prose.
  const escaped = secret.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return searchFile(new RegExp(`\\$\\{?${escaped}\\}?`));
}

// One row per heartbeat. Adding a heartbeat to the .tf files WITHOUT adding a row here FAILS the
// discovered⊆manifest assertion.
export const MANIFEST: ManifestEntry[] = [
  {
    name: "github_webhook_sig_failures",
    arming: "app-emit",
    paused: true,
    // #6537: the source comment claimed "the webhook route deliberately pings" this on every
    // signature-failure event. That is FALSE — no route pings it; the resource is `count = 0`
    // under the free tier, so nothing has ever exercised the claim. Declared unfed honestly.
    feeder: { kind: "none", url_secret: null, tracking_issue: 6549 },
    exempt_reason:
      "app/container would emit the ping; remediation is a container ci-deploy, not a dedicated-host reprovision. count=0 under the free tier (betterstack_paid_tier=false), so it is not provisioned live.",
  },
  {
    name: "github_api_429_sustained",
    arming: "app-emit",
    paused: true,
    // Same shape as its sibling above, and notably it never carried the false ping claim — the
    // comment was attached to only ONE of the two identical resources.
    feeder: { kind: "none", url_secret: null, tracking_issue: 6549 },
    exempt_reason:
      "app/container would emit the ping; remediation is a container ci-deploy, not a dedicated-host reprovision. count=0 under the free tier (betterstack_paid_tier=false), so it is not provisioned live.",
  },
  {
    name: "git_data_prd",
    arming: "web-host-cron",
    paused: true,
    // The sibling never-unpaused monitor. Its web-host probe cron is genuinely unbuilt: the
    // url_secret assertion below proves GIT_DATA_HEARTBEAT_URL has zero dereferencing consumers.
    // When #5274 PR C ships that probe, this row goes RED and must be reconciled — which is the
    // forcing function #6537 lacked.
    feeder: {
      kind: "none",
      url_secret: "GIT_DATA_HEARTBEAT_URL",
      tracking_issue: 6548,
    },
    exempt_reason:
      "PUSH heartbeat to be armed by an (unshipped, #5274 PR C) WEB-HOST probe cron over the private net — NOT a git-data cloud-init cron. Reprovisioning git-data would not arm it, so its remediation is web-host ci-deploy. (git-data-host-replace exists for immutable-redeploy compliance, not to arm this heartbeat.)",
  },
  {
    name: "inngest_prd",
    arming: "dedicated-host-boot",
    paused: true,
    // The armed precedent this PR mirrors: source paused=true, but LIVE paused=false — it was
    // unpaused out-of-band once its feeder existed. That is the correct order, and it is exactly
    // the step registry_prd never got.
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/inngest-bootstrap.sh",
        pattern: "inngest-heartbeat.timer",
      },
    },
    replace_target: { choice: "inngest-host-replace", server: "hcloud_server.inngest" },
  },
  {
    name: "registry_prd",
    // #6537: was `web-host-cron` + an exempt_reason citing an "unshipped Phase-3 web-host probe
    // cron". That classification was the bug's hiding place. It is now armed by the registry's
    // OWN cloud-init (a systemd timer on the monitored host), so it is dedicated-host-boot — which
    // makes ADR-103's replace_target requirement fire. That is INTENDED, not a workaround: the
    // feeder reaches the host only via a fresh boot, so the reprovision path is genuinely required.
    arming: "dedicated-host-boot",
    // Source stays paused=true; live is armed by API after Phase 4 measures a real beat
    // (ignore_changes=[paused] decouples the two, and the resource is untargeted anyway).
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/cloud-init-registry.yml",
        pattern: "zot-liveness-heartbeat.timer",
      },
    },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  },
  {
    name: "registry_disk_prd",
    arming: "dedicated-host-boot",
    paused: false,
    // The #6238 exemplar: on-host cron (cloud-init-registry.yml) → MUST have a reprovision path.
    // NOTE its scope, which #6537 mis-stated: this pings on `df` alone, so it alarms HOST death by
    // absence but stays GREEN with zot dead. registry_prd's feeder covers that narrower gap.
    feeder: {
      kind: "cron",
      evidence: {
        file: "apps/web-platform/infra/cloud-init-registry.yml",
        pattern: "/etc/cron.d/zot-disk-heartbeat",
      },
    },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  },
];
