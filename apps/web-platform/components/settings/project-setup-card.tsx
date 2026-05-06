"use client";

import { DisconnectRepoDialog } from "./disconnect-repo-dialog";

export type RepoStatus = "not_connected" | "ready" | "error" | "cloning";

interface ProjectSetupCardProps {
  repoUrl: string | null;
  repoStatus: RepoStatus;
  repoLastSyncedAt: string | null;
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
}: ProjectSetupCardProps) {
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

        {repoStatus === "ready" && repoUrl && (
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
          <div>
            <p className="mb-4 text-sm text-red-400">
              Something went wrong during project setup.
            </p>
            <a
              href="/connect-repo?return_to=/dashboard/settings"
              className="inline-block rounded-lg border border-red-800 bg-red-950/50 px-4 py-2 text-sm font-medium text-red-400 transition-colors hover:bg-red-900/50 hover:text-red-300"
            >
              Retry Setup
            </a>
          </div>
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
