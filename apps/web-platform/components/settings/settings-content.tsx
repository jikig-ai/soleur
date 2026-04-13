import Link from "next/link";
import { KeyRotationForm } from "./key-rotation-form";
import { DeleteAccountDialog } from "./delete-account-dialog";
import { ProjectSetupCard, type RepoStatus } from "./project-setup-card";
import { BillingSection } from "./billing-section";

interface SettingsContentProps {
  userEmail: string;
  hasApiKey: boolean;
  apiKeyProvider: string | null;
  apiKeyLastValidated: string | null;
  repoUrl: string | null;
  repoStatus: RepoStatus;
  repoLastSyncedAt: string | null;
  subscriptionStatus: string | null;
  stripeCustomerId: string | null;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  conversationCount: number;
  serviceTokenCount: number;
  createdAt: string;
}

export function SettingsContent({
  userEmail,
  hasApiKey,
  apiKeyProvider,
  apiKeyLastValidated,
  repoUrl,
  repoStatus,
  repoLastSyncedAt,
  subscriptionStatus,
  stripeCustomerId,
  currentPeriodEnd,
  cancelAtPeriodEnd,
  conversationCount,
  serviceTokenCount,
  createdAt,
}: SettingsContentProps) {
  return (
    <div className="space-y-10">
      <h1 className="mb-8 text-2xl font-semibold text-white">Settings</h1>

      {/* Account Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-white">Account</h2>
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <div className="space-y-1">
            <p className="text-sm text-neutral-400">Email</p>
            <p className="text-sm font-medium text-white">{userEmail}</p>
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
        <h2 className="mb-4 text-lg font-semibold text-white">API Key</h2>
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          {/* Key status */}
          <div className="mb-6">
            {hasApiKey ? (
              <div className="space-y-1">
                <p className="text-sm text-neutral-300">
                  Provider:{" "}
                  <span className="font-medium text-white capitalize">
                    {apiKeyProvider}
                  </span>
                </p>
                {apiKeyLastValidated && (
                  <p className="text-sm text-neutral-400">
                    Last validated:{" "}
                    {new Date(apiKeyLastValidated).toLocaleDateString()}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-sm text-neutral-400">No key configured</p>
            )}
          </div>

          <KeyRotationForm hasExistingKey={hasApiKey} />
        </div>
      </section>

      {/* Connected Services Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-white">
          Connected Services
        </h2>
        <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <p className="mb-4 text-sm text-neutral-400">
            Manage API tokens for Cloudflare, Stripe, GitHub, and other
            third-party services. Tokens are encrypted and available to your
            agent sessions.
          </p>
          <Link
            href="/dashboard/settings/services"
            className="inline-flex items-center rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-500"
          >
            Manage Services
          </Link>
        </div>
      </section>

      {/* Billing Section */}
      <BillingSection
        subscriptionStatus={subscriptionStatus}
        stripeCustomerId={stripeCustomerId}
        currentPeriodEnd={currentPeriodEnd}
        cancelAtPeriodEnd={cancelAtPeriodEnd}
        conversationCount={conversationCount}
        serviceTokenCount={serviceTokenCount}
        createdAt={createdAt}
      />

      {/* Danger Zone Section */}
      <section>
        <h2 className="mb-4 text-lg font-semibold text-red-400">Danger Zone</h2>
        <div className="rounded-xl border border-red-900/30 bg-neutral-900/50 p-6">
          <p className="mb-4 text-sm text-neutral-400">
            Permanently delete your account and all associated data. This action
            is irreversible and complies with GDPR Article 17 (Right to Erasure).
          </p>
          <DeleteAccountDialog userEmail={userEmail} />
        </div>
      </section>
    </div>
  );
}
