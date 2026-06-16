import { KeyRotationForm } from "./key-rotation-form";
import { DeleteAccountDialog } from "./delete-account-dialog";
import { ProjectSetupCard, type RepoStatus } from "./project-setup-card";
import { RenameWorkspaceAction } from "./rename-workspace-action";
import { WorkspaceLogoSettings } from "./workspace-logo-settings";
import type { WorkspaceIdentity } from "@/server/workspace-identity-resolver";

interface SettingsContentProps {
  userEmail: string;
  hasApiKey: boolean;
  apiKeyProvider: string | null;
  apiKeyLastValidated: string | null;
  repoUrl: string | null;
  repoStatus: RepoStatus;
  repoLastSyncedAt: string | null;
  needsReconnect: boolean;
  /**
   * feat-operator-cc-oauth — operator+kill-switch gated; surfaces the
   * subscription-token toggle in the key form. Default false (non-operator).
   */
  canUseOauthCredential?: boolean;
  /**
   * #4916 follow-up: workspace-identity controls (logo + rename) relocated here
   * from the flag-gated Team page so they are reachable for all users. Absent →
   * the controls don't render (e.g. an unresolvable workspace).
   */
  workspaceIdentity?: WorkspaceIdentity | null;
}

export function SettingsContent({
  userEmail,
  hasApiKey,
  apiKeyProvider,
  apiKeyLastValidated,
  repoUrl,
  repoStatus,
  repoLastSyncedAt,
  needsReconnect,
  canUseOauthCredential = false,
  workspaceIdentity = null,
}: SettingsContentProps) {
  return (
    <div className="space-y-10">
      <h1 className="mb-8 text-2xl font-semibold text-soleur-text-primary">Settings</h1>

      {/* Workspace Section — identity (name + logo). Relocated from Team so it is
          reachable regardless of the team-invite flag (#4916). */}
      {workspaceIdentity && (
        <section>
          <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Workspace</h2>
          {workspaceIdentity.organizationId && workspaceIdentity.canRename && (
            <RenameWorkspaceAction
              organizationId={workspaceIdentity.organizationId}
              organizationName={workspaceIdentity.organizationName}
              isOwner={workspaceIdentity.isOwner}
            />
          )}
          <WorkspaceLogoSettings
            workspaceId={workspaceIdentity.workspaceId}
            workspaceName={workspaceIdentity.organizationName ?? ""}
            isOwner={workspaceIdentity.isOwner}
            initialHasLogo={workspaceIdentity.hasLogo}
          />
        </section>
      )}

      {/* Account Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Account</h2>
        <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
          <div className="space-y-1">
            <p className="text-sm text-soleur-text-secondary">Email</p>
            <p className="text-sm font-medium text-soleur-text-primary">{userEmail}</p>
          </div>
        </div>
      </section>

      {/* Project Section */}
      <ProjectSetupCard
        repoUrl={repoUrl}
        repoStatus={repoStatus}
        repoLastSyncedAt={repoLastSyncedAt}
        needsReconnect={needsReconnect}
        // ADR-044 PR-1 (FR3): members of a team workspace see the read-only
        // connection summary (no connect/disconnect). Solo users (no identity,
        // or owner of their own workspace) keep the full controls.
        isOwner={workspaceIdentity?.isOwner ?? true}
        ownerLabel={workspaceIdentity?.organizationName ?? null}
      />

      {/* API Key Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">API Key</h2>
        <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
          {/* Key status */}
          <div className="mb-6">
            {hasApiKey ? (
              <div className="space-y-1">
                <p className="text-sm text-soleur-text-secondary">
                  Provider:{" "}
                  <span className="font-medium text-soleur-text-primary capitalize">
                    {apiKeyProvider}
                  </span>
                </p>
                {apiKeyLastValidated && (
                  <p className="text-sm text-soleur-text-secondary">
                    Last validated:{" "}
                    {new Date(apiKeyLastValidated).toLocaleDateString()}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-sm text-soleur-text-secondary">No key configured</p>
            )}
          </div>

          <KeyRotationForm
            hasExistingKey={hasApiKey}
            canUseOauthCredential={canUseOauthCredential}
          />
        </div>
      </section>

      {/* Privacy Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">
          Privacy
        </h2>
        <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
          <p className="mb-4 text-sm text-soleur-text-secondary">
            Request a copy of your data, view your export history, or contact
            legal@jikigai.com for manual fulfilment of GDPR rights.
          </p>
          <a
            href="/dashboard/settings/privacy"
            className="inline-block rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-2 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2"
          >
            Manage privacy
          </a>
        </div>
      </section>

      {/* Danger Zone Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-red-400">Danger Zone</h2>
        <div className="rounded-xl border border-red-900/30 bg-soleur-bg-surface-1/50 p-6">
          <p className="mb-4 text-sm text-soleur-text-secondary">
            Permanently delete your account and all associated data. This action
            is irreversible and complies with GDPR Article 17 (Right to Erasure).
          </p>
          <DeleteAccountDialog userEmail={userEmail} />
        </div>
      </section>
    </div>
  );
}
