"use client";

import { useCallback, useEffect, useState } from "react";

const ATTESTATION_TEXT =
  "I confirm this member is my employee or contractor under written agreement.";

// AC-LEGAL-FLIP gate: the wireframe attestation text is the dogfood-acceptable
// shape. CLO recommended a softer revision pre-external-team — tracked on the
// parallel legal PR (feat-team-workspace-legal-scaffolding).

export function InviteMemberModal({
  open,
  workspaceId,
  onClose,
}: {
  open: boolean;
  workspaceId: string;
  onClose: () => void;
}) {
  const [identifier, setIdentifier] = useState("");
  const [role, setRole] = useState<"member" | "owner">("member");
  const [attested, setAttested] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Reset form whenever the modal toggles open. Closes a leaky-state hazard
  // when an operator cancels then reopens for a different invitee.
  useEffect(() => {
    if (!open) {
      setIdentifier("");
      setRole("member");
      setAttested(false);
      setSubmitting(false);
      setError(null);
    }
  }, [open]);

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!attested || !identifier.trim() || submitting) return;
      setSubmitting(true);
      setError(null);
      try {
        const res = await fetch("/api/workspace/invite-member", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            workspaceId,
            identifier: identifier.trim(),
            role,
            attestationText: ATTESTATION_TEXT,
          }),
        });
        if (!res.ok) {
          const body = (await res.json().catch(() => ({}))) as {
            error?: string;
          };
          setError(body.error || `Invite failed (${res.status})`);
          setSubmitting(false);
          return;
        }
        onClose();
        // Refresh so the new member appears in the list.
        window.location.reload();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Unknown error");
        setSubmitting(false);
      }
    },
    [identifier, role, attested, submitting, workspaceId, onClose],
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
              They must already have a Soleur account. Email-based invites will
              arrive in a later release.
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

        <label className="mb-4 block">
          <span className="mb-1 block text-sm font-medium text-soleur-text-primary">
            User ID or email of existing Soleur user
          </span>
          <input
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="e.g. harry@jikigai.com or usr_abc123"
            className="w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted outline-none focus:border-soleur-border-emphasized"
          />
          <p className="mt-1 text-xs text-soleur-text-muted">
            Lookup is exact-match. The user must already exist in Soleur.
          </p>
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
            disabled={!attested || !identifier.trim() || submitting}
            className="rounded-md bg-soleur-accent-gold-fg px-4 py-2 text-sm font-medium text-soleur-bg-surface-1 disabled:cursor-not-allowed disabled:opacity-50 hover:opacity-90"
          >
            {submitting ? "Adding..." : "Add member"}
          </button>
        </div>
      </form>
    </div>
  );
}
