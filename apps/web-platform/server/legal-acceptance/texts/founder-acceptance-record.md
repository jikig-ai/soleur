---
version: 2026-11-07
---
How your decisions are recorded and kept

This text describes how Soleur records and keeps the decisions you give on legal texts. Saying Yes here records that you were shown this description and that you acknowledge it. It is not consent and it does not affect your rights: Jikigai keeps the record on the grounds stated under How long it is kept, whatever you answer. Your answer covers this text only: it does not accept any other text and is not given for any other purpose. This record applies to whoever signs in and gives an answer here.

What is stored for each decision

- The identifier of your account. It is a random number, not your name or email address.
- The name (key) and the version of the text.
- A fingerprint of the exact text you were shown.
- Your choice: Yes, No or Request changes.
- The time of the decision.
- An identifier of the sign-in session you decided in.
- For a Yes, the time you confirmed the code sent to your email.
- A checksum of the record.
- If you chose Request changes, the note you wrote, up to 1000 characters.

The record also holds fixed technical labels (a web session, and for a Yes the email code method) and the identifier of the request the decision answers. A separate marker, linked to the record's identifier, may note the time the web service reported the decision to Jikigai's monitoring; it can be missing. Because it can be linked to your record, it is personal data too, and it is kept and deleted together with the record.

Each decision also uses a short-lived request record, kept apart from the decision record. It holds your account identifier, the name, version and fingerprint of the text, the identifier of the sign-in session, the number of attempts, and the times of the request. It never holds the code. Jikigai deletes request records older than 30 days when the next request for a decision is made, so one can last longer than 30 days. A request record is not deleted when you delete your account, and it is not covered by the 5 years above.

How a decision is given

To give a Yes, you enter a code that Jikigai emails to your account address, in your signed-in web session. The code itself is not kept in this record. No and Request changes are given in your signed-in web session without a code. The record shows that a decision was submitted through a signed-in web session of your account.

An answer is final for this text. To change it, a new version of the text has to be published. Your answer to the earlier version stays on record as you gave it.

How long it is kept

The record is kept after you delete your account. Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided. Jikigai considers that it may need the record to establish, exercise or defend a legal claim, and keeps it after an erasure request on that ground (Article 17(3)(e) GDPR). The account identifier is pseudonymous, not anonymous: someone who holds other Jikigai records could link it to you. It is personal data, and Jikigai handles it as such. How long the record is kept: 5 years from the date of the decision, and then Jikigai deletes it. This covers the whole record, including any note and the marker described above. If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, Jikigai keeps it until that matter is closed. Jikigai has not yet built the step that deletes a record at the end of this period; it will build it before any record reaches that age, and until then records are kept as they are. Copies in database backups may last for a further period that Jikigai has not measured.

Who can read it

- You, for your own records, when you are signed in to the web app.
- Those who can read the stored records directly include the holders of the database administrator role (the operator and Jikigai's release process); the database host and its backups may also hold them. No automated agent session is meant to use that role; that is a rule, not a technical block.
- A Jikigai check that holds a step until a decision is recorded can ask whether a decision was made. It receives only the status, the text fingerprint, the time and the checksum result, never your note.

Once it is switched on, a Jikigai check can recompute the checksum and treat a record that no longer matches as damaged. This is for Jikigai; it is not shown to you. The checksum is not a seal and not proof of who acted: a holder of production credentials could write or change a record and its checksum.

Your note

If you choose Request changes, the note is saved with your decision and kept for as long as the decision record is kept (5 years from the date of the decision, see How long it is kept), even if you later delete your account. It cannot be removed on its own: it is deleted together with the record. Please do not write names, email addresses or private details about yourself or anyone else in it. The note is not sent anywhere; it can be read by those with direct access to the stored records, as described above.

Your rights

You can ask what Jikigai holds, ask for erasure or restriction, or object, by writing to <legal@jikigai.com> (Articles 15, 17, 18 and 21 GDPR), and you can complain to the CNIL. Jikigai decides each request or objection case by case and tells you its decision; the record is kept where it is needed for a legal claim, and a note cannot be removed from it on its own.
