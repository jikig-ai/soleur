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
        </div>
      </div>
    );
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

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
            <img
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
