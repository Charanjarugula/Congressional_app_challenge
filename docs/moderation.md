# Handling reports

Apple expects reports on Courtly to be acted on within a day. This is how.

## Where reports arrive

Every report is emailed to the support inbox (`ADMIN_EMAIL`, courtly.support@gmail.com) by the
`report-email` function, with the reason, both players, how many reports the player already has, the
reported message's text when it was a message, and the line to suspend them. Moderators (rows in
`admin_users`) also get an in-app notice. Signing up with the support address makes that account a
moderator automatically.

Report emails need the Gmail app password as the `SMTP_USER` and `SMTP_PASS` GitHub secrets (the
deploy's `secrets` step passes them to the function). Without them the function answers
"email not configured" and only the in-app notice goes out.

## Every day

1. Open the support inbox and read new "Courtly report" emails.
2. Decide:
   - Clear abuse, threats, sexual content, hate, or a second report for the same thing: suspend.
   - A one-off no-show or a misunderstanding: no action; it stays on record.
3. To suspend, run the line from the email in the Supabase SQL editor (prod project):
   `select private.suspend_user('<player id>', true);`
   This cancels their upcoming hits, withdraws their requests, and hides them everywhere. To lift it:
   `select private.suspend_user('<player id>', false);`
4. Reply to the reporter from the inbox if they left a way to reach them.

Reports are kept 90 days, then removed by the `courtly-purge-reports` job.
