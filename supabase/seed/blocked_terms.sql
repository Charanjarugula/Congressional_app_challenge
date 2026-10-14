-- Minimal objectionable-content list. Edit in the dashboard; the app embeds the same list for instant feedback.
insert into public.blocked_terms (term) values
  ('nigger'), ('nigga'), ('faggot'), ('fag'), ('kike'), ('spic'), ('chink'), ('tranny'), ('retard'),
  ('kys'), ('rape')
on conflict do nothing;
