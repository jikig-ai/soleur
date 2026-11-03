import { Suspense } from "react";

import { DevSignInPanel } from "@/components/auth/dev-sign-in-panel";
import { LoginForm } from "@/components/auth/login-form";
import {
  ERASURE_PENDING_DETAIL,
  ERASURE_PENDING_HEADLINE,
  ERASURE_RETRY_QUALIFIER,
  NEW_TAB_CUE,
  PRIVACY_POLICY_CITATION,
  PRIVACY_POLICY_URL,
} from "@/lib/legal/account-deletion-copy";

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
    // role="status", not "alert": the node is server-rendered and already present at load, so
    // an alert is not reliably announced; status is the polite live-region equivalent.
    <div
      role="status"
      className="mb-6 rounded-xl border border-amber-700/50 bg-amber-950/20 p-5"
    >
      {/*
        All strings come from lib/legal/account-deletion-copy.ts, derived from the merged
        Privacy Policy ("Pending-erasure record after account deletion"). The copy states ONLY
        what was observed and what the policy says, and is best effort throughout:
          * it does not say the repository copy was, or certainly will be, removed;
          * it does not say a record exists (the record write is best effort and can fail);
          * it says nothing about workspace files or lock-file / progress-marker residue;
          * "our team has been alerted" stays dropped: untrue as a per-user promise.
        "Contact support and reference this deletion" was also dropped: the user's account is
        gone, they cannot log back in to re-read this, and they hold no case id.
      */}
      <h2 className="mb-2 text-base font-semibold text-amber-400">
        {ERASURE_PENDING_HEADLINE}
      </h2>
      <p className="mb-2 text-sm text-soleur-text-secondary">{ERASURE_PENDING_DETAIL}</p>
      <p className="mb-2 text-sm text-soleur-text-secondary">{ERASURE_RETRY_QUALIFIER}</p>
      <p className="text-sm text-soleur-text-secondary">
        Read more in the{" "}
        <a
          href={PRIVACY_POLICY_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="underline hover:text-soleur-text-primary"
        >
          {PRIVACY_POLICY_CITATION}
          <span className="sr-only">{NEW_TAB_CUE}</span>
        </a>
        .
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
