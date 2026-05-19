// PR-G (#3947) — Single source of truth for the authorizing_event user-
// facing summary string. Composes `"Stripe invoice.payment_failed for
// {masked}"` from the server-supplied masked customer id.
//
// AC8: this file is the SOLE renderer of the masked-summary string. A
// grep-guard in the audit/ directory (run at AC time) asserts no other
// component constructs this text. Raw event.data.customerId NEVER
// reaches a client component.

interface Props {
  masked: string;
  eventName: string;
}

export function RedactedEventSummary({ masked, eventName }: Props) {
  return (
    <span className="text-sm text-soleur-text-secondary">
      Stripe <code className="text-soleur-text-primary">{eventName}</code> for{" "}
      <code className="text-soleur-text-muted">{masked}</code>
    </span>
  );
}
