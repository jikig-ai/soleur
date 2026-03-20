---
title: "chore: add subscription cancellation and EU withdrawal policy to T&C"
type: chore
date: 2026-03-20
---

# Add Subscription Cancellation and EU Withdrawal Policy to T&C

Add a new Section 5 "Subscriptions, Cancellation, and Refunds" to the Terms & Conditions, then renumber all subsequent sections and update internal cross-references. Update both the source copy and the Eleventy copy in sync.

## Acceptance Criteria

- [ ] New Section 5 inserted between current Section 4 (Description of the Service) and current Section 5 (License and IP)
- [ ] Section 5 contains four subsections: 5.1 Cancellation, 5.2 Account Deletion with Active Subscription, 5.3 EU Right of Withdrawal, 5.4 Refunds
- [ ] Current sections 5-16 renumbered to 6-17
- [ ] All internal cross-references updated — verified by exhaustive grep for `Section [0-9]` in both files
- [ ] Section 14.1b (formerly 13.1b) updated with reference to Section 5.2
- [ ] Survival clause (Section 14.3, formerly 13.3) updated with new section numbers AND includes new 5.4
- [ ] "Last Updated" date line updated with description of this change
- [ ] `docs/legal/terms-and-conditions.md` and `plugins/soleur/docs/pages/legal/terms-and-conditions.md` both updated and in sync
- [ ] Link format preserved: source uses `.md` relative links, Eleventy copy uses `/pages/legal/*.html` absolute links

## Test Scenarios

- Given a user reads Section 5, when they look for cancellation terms, then they find that cancellation takes effect at period end with access retained
- Given a user reads Section 5.3, when they look for EU withdrawal rights, then they find the Art. 16(m) waiver with explicit consent requirement and a reference to the model withdrawal form
- Given the T&C was previously 16 sections, when the new section is inserted, then it has 17 sections with correct numbering throughout
- Given both T&C copies exist, when the source is updated, then the Eleventy copy has identical content with only link format differences
- Given the T&C is updated, when searching for `Section [0-9]`, then every reference resolves to the correct heading

## Implementation Details

### New Section 5 Content

Insert after line 78 (`docs/legal/terms-and-conditions.md`), before current `## 5. License and Intellectual Property`:

```markdown
## 5. Subscriptions, Cancellation, and Refunds

Subscriptions renew automatically at the end of each billing period (monthly or annually, as selected at checkout) unless cancelled.

### 5.1 Cancellation

You may cancel your Subscription at any time. Cancellation takes effect at the end of the current billing period. You will retain access to paid features until the end of the period for which you have already paid.

### 5.2 Account Deletion with Active Subscription

If you delete your Web Platform account while a Subscription is active, the deletion triggers cancellation of your Subscription effective at the end of the current billing period. Account data is deleted as described in Section 14.1b.

### 5.3 EU Right of Withdrawal

If you are a consumer in the EU/EEA, you have a 14-day right of withdrawal under Directive 2011/83/EU. However, by subscribing and requesting immediate access to the Web Platform's paid features, you expressly consent to the performance of the digital service beginning immediately and acknowledge that you thereby waive your right of withdrawal in accordance with Article 16(m) of Directive 2011/83/EU. If you do not consent to immediate access, your access to paid features will begin after the 14-day withdrawal period has expired, during which you may withdraw and receive a full refund. To exercise your right of withdrawal, contact legal@jikigai.com or use the model withdrawal form available upon request.

### 5.4 Refunds

Except as required by applicable law (including the EU right of withdrawal described in Section 5.3), all Subscription fees are non-refundable. Jikigai may, at its sole discretion, issue refunds or credits on a case-by-case basis. Any discretionary refund does not entitle you to future refunds in similar circumstances.
```

### Cross-Reference Updates

After inserting the new section and renumbering headings, update all internal cross-references. Line numbers below refer to the **pre-insertion** source file — they will shift after insertion.

| Pre-insertion Line | Current Text | Updated Text |
|--------------------|-------------|--------------|
| 133 | `see Section 7.1b` | `see Section 8.1b` |
| 162 | `Section 16` | `Section 17` |
| 250 | `Section 13.1b` | `Section 14.1b` |
| 252 | `Sections 5.4, 6, 7, 9, 10, 11, 14, and 15` | `Sections 5.4, 6.4, 7, 8, 10, 11, 12, 15, and 16` |
| 311 | `Section 7` | `Section 8` |
| 312 | `Section 8` | `Section 9` |

**Verification step:** After all updates, grep both files for `Section [0-9]` and verify each reference resolves to the correct heading.

### Section 14.1b (formerly 13.1b) Addition

Add to the renamed Section 14.1b, after the data deletion list and before the Privacy Policy reference:

```markdown
If a Subscription is active at the time of account deletion, it is handled as described in Section 5.2.
```

### Survival Clause Update

The renamed Section 14.3 (formerly 13.3) survival clause must include the new Section 5.4 (Refunds) since the refund policy applies to post-termination disputes:

```
Sections 5.4, 6.4, 7, 8, 10, 11, 12, 15, and 16 survive termination.
```

### "Last Updated" Line

Update the "Last Updated" line (line 14) to append: `; added subscription cancellation, refund, and EU withdrawal policy (Section 5).`

### Dual-File Sync

After updating `docs/legal/terms-and-conditions.md`, replicate all changes to `plugins/soleur/docs/pages/legal/terms-and-conditions.md` with link format adjustments:
- Source: `[Privacy Policy](privacy-policy.md)` → Eleventy: `[Privacy Policy](/pages/legal/privacy-policy.html)`
- Source: `[GDPR Policy](gdpr-policy.md)` → Eleventy: `[GDPR Policy](/pages/legal/gdpr-policy.html)`

### Out of Scope (track separately)

- Checkout flow must capture EU withdrawal waiver consent on a "durable medium" (email confirmation) per Art. 16(m)
- Checkout flow must present withdrawal right information pre-contractually per Art. 6(1)(h)

## Context

- Brainstorm: `knowledge-base/brainstorms/2026-03-20-tc-cancellation-policy-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-tc-cancellation-policy/spec.md`

## References

- Related issue: #893
- Prior T&C update: PR #880 (added Web Platform service terms)
- EU Consumer Rights Directive: 2011/83/EU, Article 16(m)
