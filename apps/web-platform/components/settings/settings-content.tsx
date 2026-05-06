import { KeyRotationForm } from "./key-rotation-form";
import { DeleteAccountDialog } from "./delete-account-dialog";
import { ProjectSetupCard, type RepoStatus } from "./project-setup-card";

interface SettingsContentProps {
  userEmail: string;
  hasApiKey: boolean;
  apiKeyProvider: string | null;
  apiKeyLastValidated: string | null;
  repoUrl: string | null;
  repoStatus: RepoStatus;
  repoLastSyncedAt: string | null;
}

export function SettingsContent({
  userEmail,
  hasApiKey,
  apiKeyProvider,
  apiKeyLastValidated,
  repoUrl,
  repoStatus,
  repoLastSyncedAt,
}: SettingsContentProps) {
  return (
    <div className="space-y-10">
      <h1 className="mb-8 text-2xl font-semibold text-soleur-text-primary">Settings</h1>

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

          <KeyRotationForm hasExistingKey={hasApiKey} />
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
