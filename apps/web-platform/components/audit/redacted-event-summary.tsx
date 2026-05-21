// PR-G (#3947) — Single source of truth for the authorizing_event user-
// facing summary string. Composes `"{eventLabel} for {masked}"` from the
// server-supplied masked customer/entity id.
//
// #4067-followup: dropped the literal `"Stripe"` prefix. Originally
// correct when Stripe was the only audit source, but PR-H widened to
// GitHub/external/infra event sources. The prop is now `eventLabel`
// (a human-readable title from `ACTION_CLASS_COPY[ac].title`), not a
// raw event name.
//
// AC8: this file is the SOLE renderer of the masked-summary string. A
// grep-guard in the audit/ directory (run at AC time) asserts no other
// component constructs this text. Raw event.data.customerId NEVER
// reaches a client component.

interface Props {
  masked: string;
  eventLabel: string;
}

export function RedactedEventSummary({ masked, eventLabel }: Props) {
  return (
    <span className="text-sm text-soleur-text-secondary">
      <span className="text-soleur-text-primary">{eventLabel}</span> for{" "}
      <code className="text-soleur-text-muted">{masked}</code>
    </span>
  );
}
