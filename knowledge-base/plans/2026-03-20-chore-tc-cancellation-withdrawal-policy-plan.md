---
title: "chore: add subscription cancellation and EU withdrawal policy to T&C"
type: chore
date: 2026-03-20
---

# Add Subscription Cancellation and EU Withdrawal Policy to T&C

Add a new Section 5 "Subscriptions, Cancellation, and Refunds" to the Terms & Conditions, then renumber all subsequent sections and update internal cross-references. Update both the source copy and the Eleventy copy in sync.

## Acceptance Criteria

- [ ] New Section 5 inserted between current Section 4 (Description of the Service) and current Section 5 (License and IP)
- [ ] Section 5 contains five subsections: 5.1 Billing and Renewal, 5.2 Cancellation, 5.3 Account Deletion with Active Subscription, 5.4 EU Right of Withdrawal, 5.5 Refunds
- [ ] Current sections 5-16 renumbered to 6-17
- [ ] All internal cross-references updated (6 locations identified — see Implementation Details)
- [ ] Section 4.3 updated with forward reference to Section 5
- [ ] Section 14.1b (formerly 13.1b) updated with reference to Section 5.3
- [ ] Survival clause (Section 14.3, formerly 13.3) updated with new section numbers
- [ ] `docs/legal/terms-and-conditions.md` and `plugins/soleur/docs/pages/legal/terms-and-conditions.md` both updated and in sync
- [ ] Link format preserved: source uses `.md` relative links, Eleventy copy uses `/pages/legal/*.html` absolute links

## Test Scenarios

- Given a user reads Section 5, when they look for cancellation terms, then they find that cancellation takes effect at period end with access retained
- Given a user reads Section 5.4, when they look for EU withdrawal rights, then they find the Art. 16(m) waiver with explicit consent requirement
- Given the T&C was previously 16 sections, when the new section is inserted, then it has 17 sections with correct numbering throughout
- Given both T&C copies exist, when the source is updated, then the Eleventy copy has identical content with only link format differences

## Implementation Details

### New Section 5 Content

Insert after line 78 (`docs/legal/terms-and-conditions.md`), before current `## 5. License and Intellectual Property`:

```markdown
## 5. Subscriptions, Cancellation, and Refunds

### 5.1 Billing and Renewal

Subscriptions are billed on a recurring basis (monthly or annually, as selected at checkout). Subscriptions automatically renew at the end of each billing period unless cancelled before the renewal date. Payment is processed by Stripe; card data is handled exclusively by Stripe and never reaches Jikigai servers.

### 5.2 Cancellation

You may cancel your Subscription at any time. Cancellation takes effect at the end of the current billing period. You will retain access to paid features until the end of the period for which you have already paid. No refund is issued for the remaining portion of the current billing period.

### 5.3 Account Deletion with Active Subscription

If you delete your Web Platform account while a Subscription is active, the deletion triggers cancellation of your Subscription effective at the end of the current billing period. Account data is deleted as described in Section 14.1b. No refund is issued.

### 5.4 EU Right of Withdrawal

If you are a consumer in the EU/EEA, you have a 14-day right of withdrawal under Directive 2011/83/EU. However, by subscribing and requesting immediate access to the Web Platform's paid features, you expressly consent to the performance of the digital service beginning immediately and acknowledge that you thereby waive your right of withdrawal in accordance with Article 16(m) of Directive 2011/83/EU. If you do not consent to immediate access, your access to paid features will begin after the 14-day withdrawal period has expired, during which you may withdraw and receive a full refund.

### 5.5 Refunds

Except as required by applicable law (including the EU right of withdrawal described in Section 5.4), all Subscription fees are non-refundable. Jikigai may, at its sole discretion, issue refunds or credits on a case-by-case basis. Any discretionary refund does not entitle you to future refunds in similar circumstances.
```

### Cross-Reference Updates (6 locations in source file)

| Line | Current Text | Updated Text |
|------|-------------|--------------|
| 133 | `see Section 7.1b` | `see Section 8.1b` |
| 162 | `Section 16` | `Section 17` |
| 250 | `Section 13.1b` | `Section 14.1b` |
| 252 | `Sections 5.4, 6, 7, 9, 10, 11, 14, and 15` | `Sections 6.4, 7, 8, 10, 11, 12, 15, and 16` |
| 311 | `Section 7` | `Section 8` |
| 312 | `Section 8` | `Section 9` |

### Section 4.3 Addition

Add to Section 4.3 (after the Stripe Checkout sentence, line 74):

```markdown
Subscription billing, cancellation, and refund terms are described in Section 5.
```

### Section 13.1b → 14.1b Addition

Add to the renamed Section 14.1b (after the data deletion list):

```markdown
If a Subscription is active at the time of account deletion, it is handled as described in Section 5.3.
```

### Dual-File Sync

After updating `docs/legal/terms-and-conditions.md`, replicate all changes to `plugins/soleur/docs/pages/legal/terms-and-conditions.md` with link format adjustments:
- Source: `[Privacy Policy](privacy-policy.md)` → Eleventy: `[Privacy Policy](/pages/legal/privacy-policy.html)`
- Source: `[GDPR Policy](gdpr-policy.md)` → Eleventy: `[GDPR Policy](/pages/legal/gdpr-policy.html)`

## Context

- Brainstorm: `knowledge-base/brainstorms/2026-03-20-tc-cancellation-policy-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-tc-cancellation-policy/spec.md`

## References

- Related issue: #893
- Prior T&C update: PR #880 (added Web Platform service terms)
- EU Consumer Rights Directive: 2011/83/EU, Article 16(m)
