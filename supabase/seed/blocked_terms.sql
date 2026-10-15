-- Objectionable-content list (slurs, sexual content, threats), matched server-side as whole words in
-- messages, names, group names and court names. Edit here and redeploy the seed step.
insert into public.blocked_terms (term) values
  ('nigger'), ('nigga'), ('faggot'), ('fag'), ('kike'), ('spic'), ('chink'), ('tranny'), ('retard'),
  ('kys'), ('rape')
on conflict do nothing;

-- Slurs, sexual content and threats, matched as whole words after punctuation is stripped.
insert into public.blocked_terms (term) values
  -- racial and ethnic slurs
  ('niggers'), ('niggas'), ('nigguh'), ('niger'), ('negroid'), ('jigaboo'), ('porchmonkey'),
  ('sambo'), ('darkie'), ('darky'), ('kikes'), ('heeb'), ('hymie'), ('yid'), ('spics'), ('spick'),
  ('wetback'), ('wetbacks'), ('beaner'), ('beaners'), ('chinks'), ('gook'), ('gooks'), ('slanteye'),
  ('zipperhead'), ('paki'), ('pakis'), ('raghead'), ('ragheads'), ('towelhead'), ('towelheads'),
  ('sandnigger'), ('camelfucker'), ('redskin'),
  ('redskins'), ('injun'), ('gypo'), ('gyppo'), ('pikey'), ('dago'), ('wop'),
  ('polack'), ('chinaman'), ('coolie'), ('golliwog'),
  -- homophobic and transphobic slurs
  ('faggots'), ('fags'), ('faggy'), ('fagot'), ('dyke'), ('dykes'), ('lesbo'), ('lezzie'), ('trannies'),
  ('shemale'), ('shemales'), ('ladyboy'), ('poofter'), ('bulldyke'),
  -- ableist slurs
  ('retards'), ('retarded'), ('tard'), ('tards'), ('mongoloid'),
  -- sexual content
  ('porn'), ('porno'), ('pornhub'), ('xxx'), ('nudes'), ('dickpic'), ('sexting'), ('blowjob'),
  ('blowjobs'), ('handjob'), ('rimjob'), ('cumshot'), ('creampie'), ('gangbang'), ('bukkake'), ('deepthroat'),
  ('cunnilingus'), ('fellatio'), ('dildo'), ('dildos'), ('buttplug'), ('fleshlight'),
  ('masturbate'), ('masturbating'), ('jerkoff'), ('wank'), ('wanker'), ('cum'), ('cumming'), ('jizz'),
  ('cunt'), ('cunts'), ('twat'), ('twats'), ('pussies'), ('clit'), ('clitoris'),
  ('slut'), ('sluts'), ('slutty'), ('whore'), ('whores'), ('hooker'), ('hookers'),
  ('onlyfans'), ('camgirl'), ('sugardaddy'), ('fwb'), ('bdsm'),
  ('incest'), ('pedo'), ('pedophile'), ('paedophile'), ('loli'), ('lolicon'), ('childporn'),
  ('bestiality'), ('zoophile'), ('molester'), ('rapist'), ('rapists'), ('raping'), ('raped'),
  -- threats and self-harm encouragement
  ('killyourself'), ('kms'), ('neckyourself'),
  ('kkk')
on conflict do nothing;
