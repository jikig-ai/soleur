// Shared display mapping for email-triage items — used by both the inbox
// row (client component) and the detail page (server component). Pure and
// client-free by design: no React, no "use client", no server-only imports.

export const MAIL_CLASS_LABELS: Record<string, string> = {
  vendor: "Vendor",
  billing: "Billing",
  security: "Security",
  newsletter: "Newsletter",
  "legal-review": "Legal review",
  other: "Other",
};

export interface TriagePillInput {
  /** Non-null marks the item statutory — takes precedence over mail_class. */
  statutory_class: string | null;
  mail_class: string | null;
}

/** Pill text: "Statutory" wins, then the mail-class label, then "Email". */
export function triagePillLabel({
  statutory_class,
  mail_class,
}: TriagePillInput): string {
  if (statutory_class !== null) return "Statutory";
  return MAIL_CLASS_LABELS[mail_class ?? ""] ?? "Email";
}

/** Pill classes: red for statutory, amber for legal-review, blue otherwise. */
export function triagePillClass({
  statutory_class,
  mail_class,
}: TriagePillInput): string {
  if (statutory_class !== null) return "bg-red-500/10 text-red-500";
  if (mail_class === "legal-review") return "bg-amber-500/15 text-amber-400";
  return "bg-blue-500/10 text-blue-400";
}
