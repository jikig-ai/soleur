import { Suspense } from "react";

import { DevSignInPanel } from "@/components/auth/dev-sign-in-panel";
import { LoginForm } from "@/components/auth/login-form";

/**
 * (#8094) The erasure-pending notice lives HERE, on the unauthenticated side of the
 * principal boundary, rather than in the Delete Account dialog that produced it.
 *
 * The dialog hard-navigates unconditionally (GAP F, ADR-067 staleTimes): account
 * deletion is the strongest principal-LEAVING boundary, and with staleTimes.dynamic=30
 * a soft navigation serves warm RSC segments from client memory without a middleware
 * round-trip. Holding the user on the authenticated settings page to read a notice —
 * which an earlier cut of this change did — makes that hard nav discretionary and
 * leaves a deleted principal's own shells reachable for as long as they linger.
 *
 * So the fact rides the URL and is rendered after the boundary has been crossed.
 */
function ErasurePendingNotice() {
  return (
    <div
      role="alert"
      className="mb-6 rounded-xl border border-amber-700/50 bg-amber-950/20 p-5"
    >
      <h2 className="mb-2 text-base font-semibold text-amber-400">
        Your account is deleted — one step is still pending
      </h2>
      {/*
        The copy states ONLY what was observed. Two earlier drafts overclaimed and both
        are corrected here:
          * "your account and its data have been deleted" — "its data" includes the
            repository, which the next sentence then retracts. A reader who stops after
            the first sentence takes away the exact claim this feature exists to prevent.
            Narrowed to the stores the cascade actually confirmed.
          * "our team has been alerted" — untrue as built. The cascade emits a Sentry
            exception tagged feature=account-delete op=git-data-bare-repo-erasure, and no
            rule in infra/sentry/issue-alerts.tf matches either tag, so it pages nobody.
            "Recorded as outstanding" is what the code actually guarantees.
        "Contact support and reference this deletion" was also dropped: the user's account
        is gone, they cannot log back in to re-read this, and they hold no case id — the
        instruction dead-ended on something they do not possess.
      */}
      <p className="text-sm text-soleur-text-secondary">
        Your account, your conversations and your workspace files have been deleted. We
        could not confirm that your stored repository was erased from its host, so we are
        not going to tell you that it was. It is recorded as outstanding and will be
        completed; nothing further is needed from you.
      </p>
    </div>
  );
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const params = await searchParams;
  const erasurePending = params.erasure === "pending";

  return (
    <>
      {erasurePending && <ErasurePendingNotice />}
      {/* Renders only when NODE_ENV === "development" AND FLAG_DEV_SIGNIN=1.
          Non-dev returns null per the panel's inline gate; the runtime
          decision happens server-side, so no client JS bytes ship for it. */}
      <DevSignInPanel />
      <Suspense>
        <LoginForm />
      </Suspense>
    </>
  );
}
