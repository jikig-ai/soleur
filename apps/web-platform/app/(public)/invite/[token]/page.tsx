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
      <div className="flex min-h-screen items-center justify-center bg-[#0A0A0A] p-4">
        <div className="w-full max-w-md rounded-lg border border-[#2A2A2A] bg-[#141414] p-8 text-center">
          <h1 className="mb-4 text-xl font-semibold text-white">
            Invitation not available
          </h1>
          <p className="text-[#9a9a9a]">
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

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#0A0A0A] p-4">
      <div className="w-full max-w-md rounded-lg border border-[#2A2A2A] bg-[#141414] p-8">
        <div className="mb-6 text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-[#2563eb]/10">
            <span className="text-lg font-bold text-[#2563eb]">S</span>
          </div>
          <h1 className="mb-2 text-xl font-semibold text-white">
            Join {result.workspace_name}
          </h1>
          <p className="text-sm text-[#9a9a9a]">
            {result.inviter_name} invited you to join as a{" "}
            <span className="font-medium text-white">{result.role}</span>
          </p>
        </div>

        <InviteActions
          invitationId={result.invitation_id}
          token={token}
          isAuthenticated={!!user}
          expiresAt={result.expires_at}
        />

        <p className="mt-6 text-center text-xs text-[#6a6a6a]">
          This invitation expires on{" "}
          {new Date(result.expires_at).toLocaleDateString()}
        </p>
      </div>
    </div>
  );
}
