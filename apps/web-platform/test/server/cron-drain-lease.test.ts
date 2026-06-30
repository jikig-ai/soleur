import { mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  DEPLOY_LEASE_BASENAME,
  DEPLOY_LEASE_MAX_AGE_MS,
  DeployInProgressError,
  deployLeaseAgeMsIfFresh,
  resolveDeployLeasePath,
} from "@/server/inngest/functions/_cron-shared";
import { setupEphemeralWorkspace } from "@/server/inngest/functions/_cron-claude-eval-substrate";

// #5669 / ADR-068 — deploy-lease drain coordination.
// ci-deploy.sh writes ${CRON_WORKSPACE_ROOT}/.deploy-lease before it drains +
// swaps the container; a FRESH lease means a deploy is mid-swap, so the cron
// substrate must defer spawning claude (the imminent `docker stop` would kill
// it — the :706 spawn-cwd symptom). TTL fail-open: a stale lease (left by a
// SIGKILLed deploy) is treated as absent so a crashed deploy never darks every
// cron indefinitely (CTO ruling guardrail 1).

describe("deploy-lease drain coordination (#5669)", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "cron-drain-lease-test-"));
    vi.stubEnv("CRON_WORKSPACE_ROOT", root);
  });

  afterEach(async () => {
    vi.unstubAllEnvs();
    await rm(root, { recursive: true, force: true });
  });

  it("resolves the lease path under the cron workspace root", () => {
    expect(resolveDeployLeasePath()).toBe(join(root, DEPLOY_LEASE_BASENAME));
  });

  // Write the lease fixture to the mkdtemp-derived `root` path directly (proven
  // equal to resolveDeployLeasePath() by the path-resolution test below) with
  // exclusive-create + 0600. This keeps CodeQL's secure-temp provenance from
  // `mkdtemp` intact — writing via the env-var resolver loses it and trips
  // js/insecure-temporary-file (#5686 CodeQL gate).
  const writeLeaseFixture = () =>
    writeFile(join(root, DEPLOY_LEASE_BASENAME), "", { flag: "wx", mode: 0o600 });

  it("returns a non-negative age when a fresh lease exists (deploy in progress)", async () => {
    await writeLeaseFixture();
    const age = await deployLeaseAgeMsIfFresh();
    expect(age).not.toBeNull();
    expect(age as number).toBeGreaterThanOrEqual(0);
  });

  it("returns null when no lease exists (normal operation proceeds)", async () => {
    expect(await deployLeaseAgeMsIfFresh()).toBeNull();
  });

  it("returns null for a stale lease older than the TTL (fail-open)", async () => {
    const leasePath = join(root, DEPLOY_LEASE_BASENAME);
    await writeFile(leasePath, "", { flag: "wx", mode: 0o600 });
    // Age the lease well past the TTL so a crashed-deploy lease cannot dark crons.
    const old = Date.now() / 1000 - DEPLOY_LEASE_MAX_AGE_MS / 1000 - 600;
    await utimes(leasePath, old, old);
    expect(await deployLeaseAgeMsIfFresh()).toBeNull();
  });

  it("setupEphemeralWorkspace throws DeployInProgressError on a fresh lease, before any clone", async () => {
    await writeLeaseFixture();
    await expect(
      setupEphemeralWorkspace({ installationToken: "x", cronName: "cron-test" }),
    ).rejects.toBeInstanceOf(DeployInProgressError);
  });

  it("setupEphemeralWorkspace proceeds past the lease gate when the lease is absent (no DeployInProgressError)", async () => {
    // No lease → the gate passes; setup proceeds to mkdtemp. Point the root at a
    // nonexistent dir so mkdtemp fails fast with ENOENT (no real clone/network):
    // the failure is NOT DeployInProgressError, proving the gate does not block
    // normal operation.
    vi.stubEnv("CRON_WORKSPACE_ROOT", join(root, "does-not-exist"));
    const err = await setupEphemeralWorkspace({
      installationToken: "x",
      cronName: "cron-test",
    }).catch((e) => e);
    // Pin to the specific mkdtemp ENOENT past the gate — not just "any non-lease
    // error" — so the test can't pass on an incidental unrelated rejection.
    expect(err).not.toBeInstanceOf(DeployInProgressError);
    expect(err).toHaveProperty("code", "ENOENT");
  });
});
