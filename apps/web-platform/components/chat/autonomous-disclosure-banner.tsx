"use client";

import { Button } from "@/components/ui/button";

/**
 * feat-bash-autonomous-default-on — first-run consent soft-gate banner.
 *
 * The first non-blocked Bash command that would auto-run under autonomy, when
 * no per-workspace ack exists, is HELD (not auto-approved) while this banner is
 * surfaced. The owner's acknowledgement writes the ack and releases the held
 * command; all subsequent auto-runs are friction-free.
 *
 *   - default-ON workspace (existingWorkspace=false): a single "Got it" ack.
 *   - existing workspace stored `false` (existingWorkspace=true): the one-time
 *     opt-out — "Keep autonomous on" (sets bash_autonomous=true + ack) vs.
 *     "Ask me each time" (leaves false + ack).
 *
 * Sharp 0px corners (`rounded-none`) on card + buttons per brand-guide.md:266.
 * Copy is the LOCKED verbatim disclosure paragraph — do NOT paraphrase.
 */

// LOCKED COPY (re-locked 2026-10-10, #9776 ask-gate; CLO ruling section 1) — verbatim, do not edit.
// Ships and reverts as ONE unit with the hosted must-ask lane (ADR-284, CLO C1): a revert restores the
// 2026-10-08 text together with removing the lane. The test asserts the bytes and the vocabulary guard.
export const AUTONOMOUS_DISCLOSURE_COPY =
  "Soleur runs commands automatically. It blocks a short list of risky " +
  "commands (curl, wget, sudo, …), but no blocklist is perfect. It also " +
  "pauses to ask before common forms of a force-push over, or deletion of, " +
  "your repository's default branch (which can erase its history on " +
  "GitHub), and before terraform destroy. It does not recognise every way " +
  "of writing those commands, or every other way to delete a repository or " +
  "tear down infrastructure, so such a command can still run without " +
  "asking. Other commands that look safe could still change or delete " +
  "files in this workspace. You can watch each step in the chat. Only " +
  "connect repos and accounts you trust.";

export function AutonomousDisclosureBanner({
  gateId,
  existingWorkspace,
  resolved,
  onRespond,
}: {
  gateId: string;
  existingWorkspace: boolean;
  resolved?: boolean;
  onRespond: (gateId: string, selection: string) => void;
}) {
  return (
    <div
      role="alertdialog"
      aria-modal="false"
      aria-label="Autonomous command execution"
      data-message-type="autonomous_disclosure"
      className="flex flex-col gap-3 rounded-none border border-soleur-accent-gold-fg bg-soleur-bg-surface-1 p-4"
    >
      <span className="text-sm font-semibold text-soleur-text-primary">
        Soleur can run commands on its own
      </span>
      <p className="text-xs text-soleur-text-secondary">
        {AUTONOMOUS_DISCLOSURE_COPY}
      </p>
      <div className="flex flex-wrap justify-end gap-2">
        {existingWorkspace ? (
          <>
            <Button
              variant="outlined"
              type="button"
              disabled={resolved}
              onClick={() => onRespond(gateId, "Ask me each time")}
              className="rounded-none border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-primary hover:bg-soleur-bg-surface-2 disabled:opacity-50"
            >
              Ask me each time
            </Button>
            <Button
              variant="gold"
              type="button"
              disabled={resolved}
              onClick={() => onRespond(gateId, "Keep autonomous on")}
              className="rounded-none bg-soleur-accent-gold-fg px-3 py-1.5 text-xs font-semibold text-black hover:opacity-90 disabled:opacity-50"
            >
              Keep autonomous on
            </Button>
          </>
        ) : (
          <Button
            variant="gold"
            type="button"
            disabled={resolved}
            onClick={() => onRespond(gateId, "Got it")}
            className="rounded-none bg-soleur-accent-gold-fg px-3 py-1.5 text-xs font-semibold text-black hover:opacity-90 disabled:opacity-50"
          >
            Got it
          </Button>
        )}
      </div>
    </div>
  );
}
