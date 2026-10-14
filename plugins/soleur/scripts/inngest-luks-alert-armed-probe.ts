#!/usr/bin/env bun
// Discoverability probe for #8296 PR-1: does the SOURCE declare the Inngest wrong-volume
// Better Stack alert ARMED? Resolves `paused = !var.inngest_luks_cutover_complete` against the
// variable's declared default through the same code path the drift reconciler uses
// (../lib/heartbeat-live-reconcile.ts via discoverLogsAlertsFromInfra), so a regression in either
// the declaration or the resolver prints EXEMPT here before it silences the twice-daily report.
//
// Credential-free and sub-second: it reads apps/web-platform/infra/*.tf only. It says nothing
// about the LIVE alert (a Doppler TF_VAR override, or a vendor-side pause) — that half is the
// reconciler's job on scheduled-terraform-drift.yml, and PR-2's followthrough probe covers the
// device the store is actually on.
//
// This is a standalone file, not a `bun -e` one-liner, because preflight Check 10 (ADR-175)
// runs the plan's discoverability command inside a sandbox behind a shell-active-token reject:
// an arrow function's `=>` and a statement `;` both trip it, by design.
//
// Exit 0 + "ARMED" when the declaration resolves to paused=false; exit 1 + "EXEMPT" otherwise
// (unresolvable variable, non-boolean default, or the alert missing from the root entirely).
import { discoverLogsAlertsFromInfra } from "./reconcile-live-heartbeats.ts";

// argv[2] is a TEST seam only (a synthesized root with the default flipped); the plan's
// discoverability command passes nothing and reads the real root.
const INFRA_DIR = process.argv[2] ?? "apps/web-platform/infra";
const RESOURCE = "inngest_luks_wrong_volume";

const alert = discoverLogsAlertsFromInfra(INFRA_DIR).find((a) => a.resourceName === RESOURCE);
const armed = alert?.pausedResolvesFalse === true;
console.log(armed ? "ARMED" : "EXEMPT");
process.exit(armed ? 0 : 1);
