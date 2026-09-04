---
title: "Corporate Contributor License Agreement"
type: corporate-cla
jurisdiction: FR, EU
generated-date: 2026-02-26
---

# Corporate Contributor License Agreement

**Soleur -- Contributor License Agreement (Corporate)**

**Version:** 1.0

**Effective Date:** February 26, 2026

---

Thank you for your organization's interest in contributing to the Soleur project ("Project"), maintained by Jikigai ("We" or "Us"), a company incorporated in France with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

This Corporate Contributor License Agreement ("Agreement") defines the terms under which Contributions are submitted to the Project on behalf of the signing organization. By signing this Agreement, the organization ("You" or "Your") accepts and agrees to the following terms and conditions for present and future Contributions submitted to the Project by Your employees, contractors, or other authorized representatives.

## 0. Legal Nature of This Agreement

This Agreement is a copyright license grant, not a contract requiring ongoing consent under GDPR Article 7. Once signed, the grant is irrevocable for the Contributions covered by Your signature. A withdrawal of signature does not retract the license previously granted, but does indicate that future Contributions will not be made.

The lawful basis for processing the signature record is **legitimate interest** under GDPR Article 6(1)(f) -- maintaining an enforceable record of contributor IP license grants to defend the integrity of the Project's licensing framework.

**Where the record is kept.** No Corporate CLA record is written to the public `cla-signatures` branch, and none is written to the off-site evidence archive described in the Individual Contributor License Agreement -- a storage bucket operated for Us by **Cloudflare, Inc.**, a company established in the **United States**, to which making a record available is a transfer to a third country under Chapter V of the GDPR whatever the physical location of the storage. Those two surfaces carry individual signature records. Because a Corporate CLA record reaches neither of them, no such third-country transfer arises for it today; should that change, We will say so in this Section before it does. A Corporate CLA record rests on three surfaces instead, and the identity fields are on none of the published ones:

- **A public coverage map**, at `apps/cla-evidence/roster/ccla-roster.json` on the default branch of the Project's public GitHub repository. For each Authorized Representative it records that person's GitHub account identifier, the employing organization, the date from which the grant is effective, an optional date on which the designation ended, the record reference, the signing date, and the location and hashes of the Corporate CLA text executed together with a SHA-256 of the executed instrument as received. It records **no name, no title, no email address and no postal address**. Because it is a file tracked in git in a public repository, every entry is world-readable, is copied into every clone, fork and mirror that is taken, and cannot afterwards be recalled from those copies. An account enters this map only as Section 5 describes.
- **A public register index**, at `knowledge-base/legal/ccla-register.md` in the same repository. It records that this Agreement exists, an opaque record reference (`CCLA-0001`, `CCLA-0002`, and so on), Your organization's legal name, the same two hashes, whether an authorised signatory is on file, and the effective date. It carries no name, no title, no email address, no postal address and no signature image, and it never will: those fields are removed from its schema permanently rather than withheld pending a decision. Where Your organization's legal name is itself a natural person's name -- a sole trader, or anyone trading under their own name -- the record reference is published alone and the legal name is held off-repo.
- **The executed instrument**, which is the document that actually bears the authorised signatory's name, title and corporate email address and Your registered address. It is held **off-repo**, in Our own custody, on an encrypted operator drive. It reaches Us by email at <legal@jikigai.com>, a mailbox hosted for Us by **Proton AG**, a company established in **Switzerland**; Switzerland is covered by a European Commission adequacy decision, so no further Chapter V transfer mechanism is required for that leg. The instrument is not published, and no field taken from it is written to any file tracked in the Project's repository.

The register index is an index. The executed instrument is the evidence. Authority to sign is proven by the instrument, not by a published row, which is why the published surfaces need to carry no identity field at all. The employer-to-account association published in the coverage map **is personal data** about the representative, notwithstanding that a GitHub login is public on its own, and We publish it on the same Article 6(1)(f) legitimate-interest basis stated above, assessed separately for that population in the [GDPR Policy](gdpr-policy.md) Section 3.4. To obtain a copy of the safeguards We rely on for any transfer, write to <legal@jikigai.com>.

**How long it is kept.** The record is retained **indefinitely**, on every surface described above. Retention is indefinite because the licence You grant is irrevocable and has no end date, so the evidence that You granted it must remain available for as long as the grant can be relied on or disputed. The ten (10) year write-once retention floor described in the Individual Contributor License Agreement is a property of the off-site evidence archive, and it does not apply here, because no Corporate CLA record is written to that archive.

**Asking Us to erase it.** Two different answers apply, because the record rests on two different kinds of surface, and We would rather say so than offer one procedure that covers neither.

The **executed instrument** is in Our own custody, off-repo. The authorised signatory may ask Us to erase it at any time and We are able to act on that request. Under Article 17(3)(e) We may decline to erase a record that is necessary for the establishment, exercise, or defence of legal claims regarding the Contributions; where that applies, We will say so and why.

The **coverage map and the register index are files tracked in git in a public repository, and for those there is no erasure route at all.** Once a line is committed it is copied into every clone, fork and mirror of the repository; deleting it from Our own copy does not reach any of those, and no administrative action of Ours can recall them. We do not operate, and do not claim to operate, a procedure that erases a published entry. Article 17(3)(b) is **not** available to Us here: no law obliges Us to keep a contributor roster, and an obligation We have imposed on Ourselves is not a legal obligation for the purposes of that provision. Article 17(3)(e) **is** available, and We assess it record by record -- where a representative's entry evidences that a merged Contribution was covered by this Agreement, We rely on it, and We will tell You when We do. What We can do on request is record that a designation has ended, by writing a withdrawal date against the entry. **That is a withdrawal-of-designation marker. It is not erasure, We will not describe it as erasure, and the earlier entry survives in the repository's history and in every copy already taken.**

One thing does not change on either surface: the licence You granted survives, and continues in full effect for Contributions already made.

See the [Privacy Policy](privacy-policy.md) Sections 4.5, 5.11 and 10, and the [GDPR Policy](gdpr-policy.md) Sections 3.4, 6 and 5.3b, for the full retention, international-transfer and data-subject-rights detail.

*(Corrected 2026-08-20, ref #7624: this passage previously stated a ten (10) year retention period, which understated it -- ten years is a floor, not a ceiling -- and disclosed nothing about the off-site archive being held by a processor established in the United States. Both are corrected here.)*

*(Corrected 2026-09-04, ref #3210: this Section previously described the storage and erasure arrangements of the **Individual** Contributor License Agreement -- two copies, one on the public `cla-signatures` branch and one in a Cloudflare-operated off-site evidence archive, and an administrator procedure said to remove the archived object and leave a tombstone in its place. No Corporate CLA record is written to either of those surfaces, and no such procedure reaches a file tracked in git. Both statements were inaccurate before this correction as well as after the surfaces changed. The surfaces on which a Corporate CLA record is actually kept, and the position under Article 17 for each of them, are stated above. The 2026-08-20 correction is preserved unaltered as the audit trail of the earlier period and must not be read as a description of the arrangement as it now stands.)*

## 1. Definitions

- **"You" (or "Your")** means the organization that is entering into this Agreement, and all entities that control, are controlled by, or are under common control with that organization. For the purposes of this definition, "control" means (i) the power, direct or indirect, to cause the direction or management of such entity, whether by contract or otherwise, or (ii) ownership of fifty percent (50%) or more of the outstanding shares, or (iii) beneficial ownership of such entity.

- **"Contribution"** means any original work of authorship, including any modifications or additions to an existing work, that is intentionally submitted by any of Your authorized representatives to the Project for inclusion in, or documentation of, the Project. For the purposes of this definition, "submitted" means any form of electronic, verbal, or written communication sent to the Project or its representatives, including but not limited to communication on mailing lists, source code control systems, and issue tracking systems that are managed by, or on behalf of, the Project, but excluding communication that is conspicuously marked or otherwise designated in writing by You as "Not a Contribution."

- **"Authorized Representative"** means an individual authorized by You to submit Contributions on Your behalf. You must maintain a current list of Authorized Representatives and communicate changes to Us.

## 2. Grant of Copyright License

Subject to the terms and conditions of this Agreement, You hereby grant to Us and to recipients of software distributed by Us a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare derivative works of, publicly display, publicly perform, sublicense, and distribute Contributions submitted by Your Authorized Representatives and such derivative works. You further grant to Us the right to sublicense these rights through multiple tiers of sublicensees, and the right to relicense such Contributions under any license terms selected by Us, including proprietary and commercial license terms.

## 3. Grant of Patent License

Subject to the terms and conditions of this Agreement, You hereby grant to Us and to recipients of software distributed by Us a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer Contributions submitted by Your Authorized Representatives, where such license applies only to those patent claims licensable by You that are necessarily infringed by such Contribution(s) alone or by combination of such Contribution(s) with the Project to which such Contribution(s) was submitted.

This patent license grant does not extend to patents that would be infringed only as a consequence of further modification of the Project after the Contribution is incorporated.

**Note regarding moral rights:** In jurisdictions where moral rights (such as droits moraux under French law) are inalienable and cannot be waived, this Agreement does not require the waiver of such rights. Your Authorized Representatives agree, through Your signing of this Agreement, not to assert any moral rights in a way that would impede the exercise of the licenses granted herein, to the extent permitted by applicable law.

## 4. Representations

You represent that:

(a) You are legally entitled to grant the above licenses. You represent that each Authorized Representative is authorized to submit Contributions on Your behalf.

(b) Each Contribution submitted by Your Authorized Representatives is an original creation that You own or have sufficient rights to submit under the terms of this Agreement.

(c) You have identified all Authorized Representatives who may submit Contributions on Your behalf by providing a list of GitHub usernames to Us.

(d) Contribution submissions include complete details of any third-party license or other restriction (including, but not limited to, related patents and trademarks) of which You or Your Authorized Representatives are aware and which are associated with any part of the Contributions.

(e) You understand that the Project and the Contributions are public, and that a record of each Contribution (including all personal information associated with it, such as GitHub usernames) is maintained indefinitely and may be redistributed consistent with this Agreement and the license(s) involved.

## 5. Authorized Representative Management

You are responsible for maintaining an accurate list of Authorized Representatives. To add or remove Authorized Representatives, contact Us at <legal@jikigai.com> from the corporate email address of the authorised signatory, or from an address that signatory has told Us to accept. Until We are notified of a change, the most recent list of Authorized Representatives on file shall apply. That list is held off-repo with the executed instrument and is not itself published.

**Designating a person does not by itself publish anything about them.** An Authorized Representative's GitHub account is entered in the public coverage map described in Section 0 only at or after the moment that person has themselves signed the Individual Contributor License Agreement on a pull request in the Project's repository. Until they do, the designation is fully effective as between You and Us -- this Agreement covers Your Authorized Representatives' present and future Contributions with no cut-off date -- but no entry about that person exists in any published file, and none is created on Your say-so alone. The consequence is that a first Contribution may be annotated as not yet covered while the coverage map catches up. That is a delay in an annotation, not a condition on the Contribution or on the licence granted for it.

**Withdrawing a designation.** When You notify Us that a person is no longer an Authorized Representative, We record the withdrawal by writing a withdrawal date against that person's entry in the coverage map. Recording a withdrawal is **not erasure** and We will not present it as erasure: the entry, and the association it records, remain in the public history of the repository and in every copy of that repository already taken. Section 0 sets out what We can and cannot do about a published entry, and why.

## 6. Support and Warranty Disclaimer

You are not expected to provide support for Contributions, except to the extent You desire to provide support. You may provide support for free, for a fee, or not at all. Unless required by applicable law or agreed to in writing, Contributions are provided on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE.

## 7. Notification

You agree to notify Us of any facts or circumstances of which You become aware that would make the representations in this Agreement inaccurate in any respect.

## 8. Miscellaneous

(a) This Agreement shall be governed by and construed in accordance with the laws of France, without regard to its conflict of laws provisions. Any disputes arising under or in connection with this Agreement shall be subject to the exclusive jurisdiction of the courts of Paris, France.

(b) This Agreement sets forth the entire agreement between You and Us regarding Contributions made on Your behalf to the Project and supersedes all prior agreements, negotiations, and discussions between the parties relating thereto.

(c) If any provision of this Agreement is held to be unenforceable, such provision shall be reformed only to the extent necessary to make it enforceable, and the remaining provisions shall remain in full force and effect.

(d) A waiver of any provision of this Agreement shall not be deemed a waiver of any other provision, and any failure to enforce any provision shall not constitute a waiver of future enforcement.

(e) The license grants in Sections 2 and 3 of this Agreement are irrevocable and survive termination of this Agreement. If You later request deletion of signature records (for example, under GDPR), the license grants made under this Agreement continue in full effect for all Contributions made prior to such deletion.

---

**Signing:** To sign this Corporate Contributor License Agreement, contact <legal@jikigai.com> with the subject "Corporate CLA -- [Organization Name]." Include:

- Organization legal name and registered address
- Name and title of the authorized signatory
- An **individually-attributable corporate email address for that signatory** -- a mailbox belonging to that named person, not a shared or role address such as legal@, contracts@ or info@. We need it to establish an auditable trail of who signed on Your behalf, and to accept the changes to the list of Authorized Representatives that Section 5 provides for
- List of GitHub usernames authorized to contribute on behalf of the organization

**What is published and what is not.** The authorized signatory's name, title and corporate email address, and Your registered address, are **not published**. They rest only in the executed instrument, held off-repo in Our custody as Section 0 describes. Your organization's legal name **is** published, in the register index in the Project's repository, alongside an opaque record reference and the hashes described in Section 0 -- except where that legal name is itself a natural person's name, as for a sole trader or anyone trading under their own name, in which case the record reference is published alone and the legal name is held off-repo with the instrument. The GitHub usernames You designate are published in the public coverage map, but only once the person concerned has signed the Individual Contributor License Agreement here, as Section 5 explains.

---

> **Note:** This document should be reviewed by qualified legal counsel before reliance. It does not constitute legal advice.

---

> **Related documents:** This Corporate Contributor License Agreement relates to the Project's intellectual property framework. Please review the companion documents:
> - [Individual Contributor License Agreement](individual-cla.md) -- for contributions made by individuals
> - [Terms & Conditions](terms-and-conditions.md) -- governs use of the Soleur platform
> - [Privacy Policy](privacy-policy.md) -- details data practices including CLA signature processing
