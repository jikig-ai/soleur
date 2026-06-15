import {
  findRepoOwnerInstallationForUser,
  getInstallationAccount,
} from "./github-app";
import { mirrorSelfHealSkip } from "./cc-self-heal-observability";
import { reportSilentFallback } from "./observability";
import { createChildLogger } from "./logger";

const log = createChildLogger("cc-effective-installation");

const GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;

/**
 * Parse the connected repo's owner from a server-resolved github HTTPS URL.
 * Returns `""` for a malformed URL (degrade silently — not a security gate;
 * the caller treats an empty owner as "no promotion possible").
 */
function parseConnectedOwner(repoUrl: string | null): string {
  if (!repoUrl) return "";
  try {
    const parts = new URL(repoUrl).pathname.split("/").filter(Boolean);
    const o = parts[0];
    if (o && GITHUB_NAME_RE.test(o)) return o;
  } catch {
    /* malformed repoUrl → no owner */
  }
  return "";
}

/**
 * Concierge installation self-heal (feat-one-shot-concierge-gh-403): given the
 * stored per-workspace installation id and the connected repo URL, return the
 * EFFECTIVE installation id to authenticate repo operations with for this
 * dispatch.
 *
 * The stored install can be a CROSS-ACCOUNT personal install that can READ the
 * connected repo (so connect-time probe passed) but only holds `issues: read` —
 * `git clone` / `gh issue create` then 403 with the stored install. The fix is
 * SELECTION, not a permission change: when the stored install is a personal
 * (User-type) install that does NOT own the connected repo, promote to the
 * repo-owner installation — but ONLY when the user is ENTITLED to it
 * (`findRepoOwnerInstallationForUser` gates org installs on verified membership,
 * so a read-only outside collaborator cannot escalate to the org's write grant).
 *
 * Extracted from `cc-dispatcher.ts realSdkQueryFactory` (#5340 / #5240) so the
 * COLD factory self-heal AND the per-dispatch warm re-provision
 * (`cc-reprovision.ts`) select the SAME install — otherwise the warm/leader
 * re-clone would use the raw (possibly 403-ing) install while the cold factory
 * used the promoted one, producing a FALSE "workspace reclaimed — couldn't
 * restore" message for org repos a cold turn could recover (review finding).
 *
 * Entirely GitHub-App-JWT driven — NO Supabase service-role. Best-effort: any
 * probe failure keeps the stored install and never throws (mirrors to Sentry).
 * In every non-promotion branch the return equals the stored `installationId`,
 * so this NEVER widens access beyond what the stored install already had.
 */
export async function resolveEffectiveInstallationId(args: {
  userId: string;
  installationId: number | null;
  repoUrl: string | null;
}): Promise<number | null> {
  const { userId, installationId, repoUrl } = args;
  const connectedOwner = parseConnectedOwner(repoUrl);
  if (installationId === null || !connectedOwner) return installationId;

  let effectiveInstallationId = installationId;
  try {
    const storedAccount = await getInstallationAccount(installationId);
    const alreadyCorrect =
      storedAccount.login.toLowerCase() === connectedOwner.toLowerCase();
    // `alreadyCorrect` is a no-op (stored install already owns the repo), NOT a
    // skip — do not mirror it. Every not-already-correct branch either promotes
    // (success log.info) or KEEPS the stored install, and a keep must be a
    // queryable Sentry event (cq-silent-fallback-must-mirror-to-sentry).
    if (!alreadyCorrect) {
      if (storedAccount.type === "User") {
        // Only derive the user's login from a personal (User) install.
        const { installationId: ownerInstall, outcome } =
          await findRepoOwnerInstallationForUser(
            connectedOwner,
            storedAccount.login,
          );
        if (ownerInstall !== null && ownerInstall !== installationId) {
          log.info(
            {
              userId,
              storedInstallationId: installationId,
              ownerInstallationId: ownerInstall,
              owner: connectedOwner,
            },
            "Concierge installation self-heal: stored personal install does not own the connected repo; switching to the entitled repo-owner installation for this dispatch",
          );
          effectiveInstallationId = ownerInstall;
        } else if (ownerInstall === null) {
          // Promotion denied (not-member / transient-indeterminate /
          // token-mint-failed / no-owner-install) — keep the stored install +
          // surface the skip so a residual 403 is explainable from Sentry.
          mirrorSelfHealSkip({
            userId,
            storedInstallationId: installationId,
            owner: connectedOwner,
            membershipProbeOutcome: outcome,
            effectiveInstallationId: installationId,
          });
        }
      } else {
        // Org-type stored install whose account != the connected-repo owner:
        // the user's login is not derivable without a service-role admin lookup,
        // so keep the stored install (fail-safe). Mirror it.
        mirrorSelfHealSkip({
          userId,
          storedInstallationId: installationId,
          owner: connectedOwner,
          membershipProbeOutcome: "org-type-stored-install",
          effectiveInstallationId: installationId,
        });
      }
    }
  } catch (probeErr) {
    reportSilentFallback(probeErr, {
      feature: "cc-dispatcher",
      op: "installation-self-heal-probe",
      extra: { userId },
      message: "Repo-owner installation probe failed; keeping stored installation",
    });
  }
  return effectiveInstallationId;
}
