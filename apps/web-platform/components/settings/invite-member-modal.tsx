"use client";

import { useCallback, useEffect, useState } from "react";
import { DEFAULT_ORG_NAME, WORKSPACE_NAME_MAX } from "@/lib/workspace-name";

const ATTESTATION_TEXT =
  "I confirm this member is my employee or contractor under written agreement, and I consent to them accessing this workspace's connected repository and knowledge-base.";

// AC-LEGAL-FLIP gate: the wireframe attestation text is the dogfood-acceptable
// shape. CLO recommended a softer revision pre-external-team — tracked on the
// parallel legal PR (feat-team-workspace-legal-scaffolding). The repo/KB-access
// consent clause is the Art. 6(1)(a) lawful basis for a Co-Member's access to
// the workspace owner's connected repository + derived KB post-ADR-044 (#4558);
// it is the migration-058 workspace_member_attestations consent of record.
// DRAFT consent copy — pending CLO/counsel review per #4558.

// AC6: the org name is "still the default" (and so worth prompting for at
// first-invite) when it is empty/NULL or the generic backfill/trigger default
// (DEFAULT_ORG_NAME, shared with the migration literal via lib/workspace-name).

export function InviteMemberModal({
  open,
  workspaceId,
  onClose,
  organizationId,
  organizationName,
}: {
  open: boolean;
  workspaceId: string;
  onClose: () => void;
  /** Org being invited into — enables the optional first-invite rename. */
  organizationId?: string;
  /** Current org name — the rename field only shows while it's still default. */
  organizationName?: string | null;
}) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"member" | "owner">("member");
  const [attested, setAttested] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [workspaceName, setWorkspaceName] = useState("");

  const isDefaultName =
    !organizationName ||
    organizationName.trim() === "" ||
    organizationName.trim() === DEFAULT_ORG_NAME;
  // Only prompt for a name when we know which org to rename AND it's still the
  // default — once named, the rename UI on the team page owns subsequent edits.
  const showNameField = Boolean(organizationId) && isDefaultName;

  // Reset form whenever the modal toggles open. Closes a leaky-state hazard
  // when an operator cancels then reopens for a different invitee.
  useEffect(() => {
    if (!open) {
      setEmail("");
      setRole("member");
      setAttested(false);
      setSubmitting(false);
      setError(null);
      setSuccess(false);
      setWorkspaceName("");
    }
  }, [open]);

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!attested || !email.trim() || !email.includes("@") || submitting) return;
      setSubmitting(true);
      setError(null);
      try {
        // AC6: opportunistic first-invite rename. Best-effort — a rename
        // failure must not block the invite (the invite is the primary action).
        if (showNameField && organizationId && workspaceName.trim()) {
          try {
            await fetch("/api/workspace/rename", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                organizationId,
                name: workspaceName.trim(),
              }),
            });
          } catch {
            // swallow — invite proceeds regardless
          }
        }
        const res = await fetch("/api/workspace/invite-member", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            workspaceId,
            email: email.trim(),
            role,
            attestationText: ATTESTATION_TEXT,
          }),
        });
        if (!res.ok) {
          const body = (await res.json().catch(() => ({}))) as {
            error?: string;
          };
          const msg =
            body.error === "duplicate_pending_invite"
              ? "An invite is already pending for this email."
              : body.error === "invitee_already_member"
                ? "This person is already a workspace member."
                : body.error || `Invite failed (${res.status})`;
          setError(msg);
          setSubmitting(false);
          return;
        }
        setSuccess(true);
        setTimeout(() => {
          onClose();
          window.location.reload();
        }, 1500);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Unknown error");
        setSubmitting(false);
      }
    },
    [
      email,
      role,
      attested,
      submitting,
      workspaceId,
      onClose,
      showNameField,
      organizationId,
      workspaceName,
    ],
  );

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="invite-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4"
    >
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6"
      >
        <div className="mb-4 flex items-start justify-between">
          <div>
            <h2
              id="invite-modal-title"
              className="text-lg font-semibold text-soleur-text-primary"
            >
              Invite member
            </h2>
            <p className="mt-1 text-xs text-soleur-text-muted">
              An invite email with a join link will be sent. They don&apos;t need
              an existing account.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close modal"
            className="text-soleur-text-muted hover:text-soleur-text-primary"
          >
            ✕
          </button>
        </div>

        {success && (
          <div className="mb-4 rounded-md bg-green-500/10 px-3 py-2 text-sm text-green-400">
            Invite sent! They&apos;ll receive an email with a join link.
          </div>
        )}

        {showNameField && (
          <label className="mb-4 block">
            <span className="mb-1 block text-sm font-medium text-soleur-text-primary">
              Name your workspace
            </span>
            <input
              type="text"
              value={workspaceName}
              maxLength={WORKSPACE_NAME_MAX}
              onChange={(e) => setWorkspaceName(e.target.value)}
              placeholder="e.g. Marketing team"
              className="w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted outline-none focus:border-soleur-border-emphasized"
            />
            <span className="mt-1 block text-xs text-soleur-text-muted">
              Optional. Helps teammates tell this workspace apart in the
              switcher. You can change it later in Team settings.
            </span>
          </label>
        )}

        <label className="mb-4 block">
          <span className="mb-1 block text-sm font-medium text-soleur-text-primary">
            Email address
          </span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="colleague@company.com"
            autoComplete="email"
            inputMode="email"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            className="w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-muted outline-none focus:border-soleur-border-emphasized md:text-sm"
          />
        </label>

        <fieldset className="mb-4">
          <legend className="mb-2 block text-sm font-medium text-soleur-text-primary">
            Role
          </legend>
          <label
            className={`mb-2 block cursor-pointer rounded-md border p-3 ${
              role === "member"
                ? "border-soleur-accent-gold-fg"
                : "border-soleur-border-default"
            }`}
          >
            <span className="flex items-center gap-2">
              <input
                type="radio"
                name="role"
                value="member"
                checked={role === "member"}
                onChange={() => setRole("member")}
              />
              <span className="text-sm font-medium text-soleur-text-primary">
                Member
              </span>
            </span>
            <span className="ml-6 block text-xs text-soleur-text-muted">
              Can act in the workspace. Cannot invite or remove members.
            </span>
          </label>
          <label
            className={`block cursor-pointer rounded-md border p-3 ${
              role === "owner"
                ? "border-soleur-accent-gold-fg"
                : "border-soleur-border-default"
            }`}
          >
            <span className="flex items-center gap-2">
              <input
                type="radio"
                name="role"
                value="owner"
                checked={role === "owner"}
                onChange={() => setRole("owner")}
              />
              <span className="text-sm font-medium text-soleur-text-primary">
                Owner
              </span>
            </span>
            <span className="ml-6 block text-xs text-soleur-text-muted">
              Full control. Can invite, remove, change billing, delete
              workspace.
            </span>
          </label>
        </fieldset>

        <label className="mb-4 flex items-start gap-2 rounded-md border border-soleur-border-default p-3">
          <input
            type="checkbox"
            checked={attested}
            onChange={(e) => setAttested(e.target.checked)}
            className="mt-0.5"
          />
          <span>
            <span className="text-sm text-soleur-text-primary">
              {ATTESTATION_TEXT}
            </span>
            <span className="mt-1 block text-xs text-soleur-text-muted">
              Required for GDPR controller-to-controller scope. The audit log
              records this attestation against your user ID.
            </span>
          </span>
        </label>

        {error && (
          <p className="mb-3 text-sm text-red-400" role="alert">
            {error}
          </p>
        )}

        <div className="flex items-center justify-between">
          <button
            type="button"
            onClick={onClose}
            className="px-3 py-2 text-sm text-soleur-text-secondary hover:text-soleur-text-primary"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!attested || !email.trim() || !email.includes("@") || submitting}
            className="rounded-md bg-soleur-accent-gold-fg px-4 py-2 text-sm font-medium text-soleur-bg-surface-1 disabled:cursor-not-allowed disabled:opacity-50 hover:opacity-90"
          >
            {submitting ? "Sending..." : "Send invite"}
          </button>
        </div>
      </form>
    </div>
  );
}
