# Handling reports

Courtly’s published support policy promises to review reports within 24 hours. Apple’s user-generated content rules require timely responses. This is the operating procedure for meeting that commitment.

## Where reports arrive

Every report is emailed to the support inbox (`ADMIN_EMAIL`, courtly.support@gmail.com) by the
`report-email` function, with the reason, both players, how many reports the player already has, the
reported message's text when it was a message, and the line to suspend them. Moderators (rows in
`admin_users`) also get an in-app notice. Signing up with the support address makes that account a
moderator automatically.

Report emails need the Gmail app password as the `SMTP_USER` and `SMTP_PASS` GitHub secrets (the
deploy's `secrets` step passes them to the function). Without them the function answers
"email not configured" and only the in-app notice goes out.

## Launch owner

Charan Jarugula confirmed on October 16, 2026 that he can access courtly.support@gmail.com and will monitor it daily. The two production reports were reviewed on October 16, 2026 under owner authorization and marked `reviewed`: one was an explicit delivery test and the other contained an ordinary tennis invitation with no abusive content. No suspension was warranted; the original records remain intact.

## Every day

1. Open the support inbox and read new "Courtly report" emails.
2. Decide:
   - Substantiated abuse, threats, sexual content, or hate: consider suspension based on the evidence and severity. Repeated reports warrant investigation, not automatic punishment.
   - A one-off no-show or a misunderstanding: no action; it stays on record.
3. To suspend, run the line from the email in the Supabase SQL editor (prod project):
   `select private.suspend_user('<player id>', true);`
   This cancels their upcoming hits, withdraws their requests, and hides them everywhere. To lift it:
   `select private.suspend_user('<player id>', false);`
4. Record the decision on the specific report: set `status` to `reviewed` if no enforcement is warranted, or `actioned` after an enforcement action. Keep the report itself; do not delete evidence to clear the queue. For example:
   `update public.reports set status = 'reviewed' where id = '<report id>' and status = 'open';`
5. Reply to the reporter from the inbox if follow-up is needed and they left a way to reach them. Never disclose another player's private information.

Reports are kept 90 days, then removed by the `courtly-purge-reports` job.
