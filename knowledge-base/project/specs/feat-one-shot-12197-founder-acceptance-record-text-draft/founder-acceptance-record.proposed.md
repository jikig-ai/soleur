---
version: 2026-11-07
---
How your decisions are recorded and kept

This text describes how Soleur records and keeps the decisions you give on legal texts. Saying Yes here records that you acknowledge this description. Your answer covers this text only: it does not accept any other text and is not given for any other purpose.

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

The record also holds fixed technical labels (a web session, and for a Yes the email code method) and the identifier of the request the decision answers.

How a decision is given

To give a Yes, you enter a code that Jikigai emails to your account address, in your signed-in web session. The code is not stored. No and Request changes are given in your signed-in web session without a code. The record shows that a decision was submitted through a signed-in web session of your account.

An answer is final for this text. To change it, a new version of the text has to be published. Your answer to the earlier version stays on record as you gave it.

How long it is kept

The record is kept after you delete your account. Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided; Article 17(3)(e) GDPR lets it keep data that may be needed for legal claims. The account identifier is not anonymous: someone who holds other Jikigai records could link it to you, so Jikigai treats it as personal data. How long the record is kept: [period to be confirmed by counsel].

Who can read it

- You, for your own records, when you are signed in to the web app.
- Direct access to the stored records is held by the database administrator role. It is held by the operator and by Jikigai's release process. No automated agent session is meant to use it; that is a rule, not a technical block.
- A Jikigai check that holds a step until a decision is recorded can ask whether a decision was made. It receives only the status, the text fingerprint, the time and the checksum result, never your note.

Jikigai's check recomputes the checksum and flags a record that no longer matches. The checksum is not a seal and not proof of who acted: a holder of production credentials could write or change a record and its checksum.

Your note

If you choose Request changes, the note is saved with your decision and kept even if you later delete your account. Please do not write names, email addresses or private details about yourself or anyone else in it. The note is not sent anywhere; it can be read by those who hold the database administrator credential, as described above.

Your rights

You can ask what Jikigai holds, or object, by writing to <legal@jikigai.com> (Articles 15 and 21 GDPR), and you can complain to the CNIL.
