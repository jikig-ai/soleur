"use client";

import { useRouter } from "next/navigation";
import { DisconnectRepoDialog } from "./disconnect-repo-dialog";
import { ReconnectNotice } from "@/components/repo/reconnect-notice";
import { useReconnect, type ReconnectRepoStatus } from "@/components/repo/use-reconnect";

// Single-sourced from use-reconnect.ts (the lower-level module) so the union
// can't drift across the two files. Re-exported under the existing name for
// settings-content.tsx / dashboard/settings/page.tsx consumers.
export type RepoStatus = ReconnectRepoStatus;

interface ProjectSetupCardProps {
  repoUrl: string | null;
  repoStatus: RepoStatus;
  repoLastSyncedAt: string | null;
  /**
   * #4712 — `ready` repo whose `github_installation_id` is NULL (the #4706
   * silent-freeze class). Suppresses the Connected view and renders the
   * reconnect affordance instead.
   */
  needsReconnect?: boolean;
}

function extractRepoName(url: string): string {
  try {
    const parts = new URL(url).pathname.split("/").filter(Boolean);
    return parts.length >= 2 ? `${parts[0]}/${parts[1]}` : url;
  } catch {
    return url;
  }
}

export function ProjectSetupCard({
  repoUrl,
  repoStatus,
  repoLastSyncedAt,
  needsReconnect = false,
}: ProjectSetupCardProps) {
  const router = useRouter();
  return (
    <section>
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Project</h2>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        {repoStatus === "not_connected" && (
          <div>
            <p className="mb-4 text-sm text-soleur-text-secondary">
              Connect a GitHub project so your AI team has full context on your
              codebase.
            </p>
            <a
              href="/connect-repo?return_to=/dashboard/settings"
              className="inline-block rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:opacity-90"
            >
              Set Up Project
            </a>
          </div>
        )}

        {repoStatus === "ready" && needsReconnect && (
          <ReconnectNotice
            variant="card"
            onReconnected={() => router.refresh()}
          />
        )}

        {repoStatus === "ready" && repoUrl && !needsReconnect && (
          <div className="space-y-4">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <p className="text-sm font-medium text-soleur-text-primary">
                  {extractRepoName(repoUrl)}
                </p>
                <span className="rounded-full bg-green-900/50 px-2 py-0.5 text-xs font-medium text-green-400">
                  Connected
                </span>
              </div>
              {repoLastSyncedAt && (
                <p className="text-sm text-soleur-text-secondary">
                  Last synced:{" "}
                  {new Date(repoLastSyncedAt).toLocaleDateString()}
                </p>
              )}
            </div>
            <DisconnectRepoDialog repoName={extractRepoName(repoUrl)} />
          </div>
        )}

        {repoStatus === "error" && (
          <RepoErrorRecovery repoUrl={repoUrl} />
        )}

        {repoStatus === "cloning" && (
          <div className="flex items-center gap-2">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-soleur-border-default border-t-soleur-text-primary" />
            <p className="text-sm text-soleur-text-secondary">Setting up your project...</p>
          </div>
        )}
      </div>
    </section>
  );
}

/**
 * FIX 1b — the recovery affordance for a broken (`error`) checkout. This is the
 * state that actually renders for a broken workspace (`ReconnectNotice` only
 * mounts for `ready`). The button does what the error copy promises: re-verify
 * the GitHub App, then re-trigger the canonical `POST /api/repo/setup`
 * (wipe-and-reclone) for the connected repo and poll status to terminal —
 * rather than only bouncing the user to `/connect-repo`.
 *
 * On a terminal background-clone failure (`resetupError`) it surfaces an
 * actionable terminal state with a `/connect-repo` escape hatch, so the user is
 * never stuck on a spinner-forever (only the connect-repo page polls otherwise).
 */
function RepoErrorRecovery({ repoUrl }: { repoUrl: string | null }) {
  const router = useRouter();
  const { reconnect, isPending, resetupError } = useReconnect(
    () => router.refresh(),
    { repoUrl, repoStatus: "error" },
  );

  return (
    <div>
      <p className="mb-4 text-sm text-red-400">
        {resetupError
          ? "We couldn't finish setting up your project. Try reconnecting, or re-select the repository."
          : "Something went wrong during project setup."}
      </p>
      <div className="flex flex-wrap items-center gap-3">
        {repoUrl ? (
          <button
            type="button"
            onClick={reconnect}
            disabled={isPending}
            className="inline-flex items-center justify-center rounded-lg border border-red-800 bg-red-950/50 px-4 py-2 text-sm font-medium text-red-400 transition-colors hover:bg-red-900/50 hover:text-red-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending ? "Reconnecting…" : "Reconnect"}
          </button>
        ) : null}
        <a
          href="/connect-repo?return_to=/dashboard/settings"
          className="inline-block rounded-lg border border-red-800 bg-red-950/50 px-4 py-2 text-sm font-medium text-red-400 transition-colors hover:bg-red-900/50 hover:text-red-300"
        >
          Retry Setup
        </a>
      </div>
    </div>
  );
}
