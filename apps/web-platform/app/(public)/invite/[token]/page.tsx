import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { hashToken, type LookupResult } from "@/server/workspace-invitations";
import { InviteActions } from "./invite-actions";

interface Props {
  params: Promise<{ token: string }>;
}

export default async function InvitePage({ params }: Props) {
  const { token } = await params;
  const tokenHash = hashToken(token);

  // Resolve the session first so BOTH the terminal "not available" card and the
  // accept card can branch on auth (spec-flow J7: a dead-end terminal card is a
  // single-user trap — give the user a forward hop).
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const service = createServiceClient();
  const { data } = await service.rpc("lookup_invitation_by_token", {
    p_token_hash: tokenHash,
  });

  const result = data as LookupResult | null;

  if (!result || !result.ok) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-soleur-bg-base p-4">
        <div className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-8 text-center">
          <h1 className="mb-4 text-xl font-semibold text-soleur-text-primary">
            Invitation not available
          </h1>
          <p className="text-soleur-text-secondary">
            This invitation may have expired, already been used, or is no longer valid.
          </p>
          {/* J7 forward CTA — never leave the user at a hard dead-end. */}
          <Link
            href={user ? "/dashboard" : "/login"}
            className="mt-6 inline-block rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent hover:opacity-90"
          >
            {user ? "Go to your dashboard" : "Sign in"}
          </Link>
        </div>
      </div>
    );
  }

  // Compute the invitee match on the server. The lookup result carries only
  // invitee_email (not invitee_user_id), so the client gate is email-based;
  // the route + RPC retain the stronger user_id-OR-email check as the
  // security floor. Lower-cased comparison mirrors accept-invite/route.ts.
  const signedInEmail = user?.email ?? "";
  const isIntendedInvitee =
    !!user &&
    !!result.invitee_email &&
    result.invitee_email.toLowerCase() === signedInEmail.toLowerCase();

  return (
    <div className="flex min-h-screen items-center justify-center bg-soleur-bg-base p-4">
      <div className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-8">
        <div className="mb-6 text-center">
          <span className="mx-auto mb-4 flex h-12 w-12 items-center justify-center overflow-hidden rounded-full">
            <Image
              src="/icons/soleur-logo-mark.png"
              alt="Soleur"
              width={48}
              height={48}
              className="h-full w-full object-cover"
            />
          </span>
          <h1 className="mb-2 text-xl font-semibold text-soleur-text-primary">
            Join {result.workspace_name}
          </h1>
          <p className="text-sm text-soleur-text-secondary">
            {result.inviter_name} invited you to join as a{" "}
            <span className="font-medium text-soleur-text-primary">{result.role}</span>
          </p>
        </div>

        {/* Art. 13 disclosure (FR2 / CLO guardrail): tell the invitee what
            joining shares BEFORE they accept — rendered co-temporally with the
            Accept button, not deferred to onboarding. */}
        <p className="mb-4 text-center text-xs text-soleur-text-muted">
          Members share this workspace&apos;s data, agents, and billing.
        </p>

        <InviteActions
          invitationId={result.invitation_id}
          token={token}
          isAuthenticated={!!user}
          inviteeEmail={result.invitee_email ?? ""}
          isIntendedInvitee={isIntendedInvitee}
          signedInEmail={signedInEmail}
        />

        <p className="mt-6 text-center text-xs text-soleur-text-muted">
          This invitation expires on{" "}
          {new Date(result.expires_at).toLocaleDateString()}
        </p>
      </div>
    </div>
  );
}
