-- Public tennis courts in Palm Beach County. Coordinates are approximate park locations;
-- players can add courts the list is missing. Re-runnable: matched on name.
insert into public.courts (name, address, city, point, surface, lights, source) values
  ('Wellington Tennis Center', '3100 Forest Hill Blvd', 'Wellington', extensions.st_setsrid(extensions.st_makepoint(-80.2493, 26.6536), 4326), 'clay', true, 'seed'),
  ('Village Park', '11700 Pierson Rd', 'Wellington', extensions.st_setsrid(extensions.st_makepoint(-80.2560, 26.6420), 4326), 'hard', true, 'seed'),
  ('Royal Palm Beach Commons Park', '11600 Poinciana Blvd', 'Royal Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.2240, 26.7026), 4326), 'hard', true, 'seed'),
  ('Okeeheelee Park Tennis Center', '7715 Forest Hill Blvd', 'West Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.1585, 26.6558), 4326), 'hard', true, 'seed'),
  ('Lake Lytal Park', '3645 Gun Club Rd', 'West Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.1195, 26.6676), 4326), 'hard', true, 'seed'),
  ('Howard Park Tennis Center', '901 Lake Ave', 'West Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0601, 26.7116), 4326), 'clay', true, 'seed'),
  ('Phipps Park', '4715 S Dixie Hwy', 'West Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0540, 26.6700), 4326), 'hard', true, 'seed'),
  ('Gaines Park', '1501 N Australian Ave', 'West Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0680, 26.7290), 4326), 'hard', true, 'seed'),
  ('Seminole Palms Park', '5151 Lake Worth Rd', 'Greenacres', extensions.st_setsrid(extensions.st_makepoint(-80.1260, 26.6190), 4326), 'hard', true, 'seed'),
  ('Greenacres Community Park', '2905 Jog Rd', 'Greenacres', extensions.st_setsrid(extensions.st_makepoint(-80.1350, 26.6270), 4326), 'hard', true, 'seed'),
  ('John Prince Park', '2700 6th Ave S', 'Lake Worth Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0772, 26.6017), 4326), 'hard', true, 'seed'),
  ('Boynton Beach Tennis Center', '3111 S Congress Ave', 'Boynton Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0890, 26.5000), 4326), 'clay', true, 'seed'),
  ('Caloosa Park', '1300 SW 35th Ave', 'Boynton Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0900, 26.5080), 4326), 'hard', true, 'seed'),
  ('Delray Beach Tennis Center', '201 W Atlantic Ave', 'Delray Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0750, 26.4610), 4326), 'clay', true, 'seed'),
  ('Pompey Park', '1101 NW 2nd St', 'Delray Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0810, 26.4660), 4326), 'hard', true, 'seed'),
  ('Lake Ida Park', '2929 Lake Ida Rd', 'Delray Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0870, 26.4740), 4326), 'hard', false, 'seed'),
  ('Boca Raton Tennis Center', '271 NW Boca Raton Blvd', 'Boca Raton', extensions.st_setsrid(extensions.st_makepoint(-80.0880, 26.3540), 4326), 'clay', true, 'seed'),
  ('Patch Reef Park Tennis Center', '2000 Yamato Rd', 'Boca Raton', extensions.st_setsrid(extensions.st_makepoint(-80.1170, 26.3930), 4326), 'hard', true, 'seed'),
  ('Loggers'' Run Park', '11400 Palmetto Park Rd', 'Boca Raton', extensions.st_setsrid(extensions.st_makepoint(-80.2100, 26.3600), 4326), 'hard', true, 'seed'),
  ('Seaview Park', '340 Seaview Ave', 'Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0390, 26.7120), 4326), 'hard', false, 'seed'),
  ('Burns Road Community Center', '4404 Burns Rd', 'Palm Beach Gardens', extensions.st_setsrid(extensions.st_makepoint(-80.0880, 26.8330), 4326), 'hard', true, 'seed'),
  ('Palm Beach Gardens Tennis Center', '5110 117th Ct N', 'Palm Beach Gardens', extensions.st_setsrid(extensions.st_makepoint(-80.1500, 26.8460), 4326), 'clay', true, 'seed'),
  ('North Palm Beach Tennis', '951 US Hwy 1', 'North Palm Beach', extensions.st_setsrid(extensions.st_makepoint(-80.0590, 26.8180), 4326), 'clay', true, 'seed'),
  ('Jupiter Community Park', '3375 Central Blvd', 'Jupiter', extensions.st_setsrid(extensions.st_makepoint(-80.1160, 26.9090), 4326), 'hard', true, 'seed'),
  ('Abacoa Community Park', '1501 Frederick Small Rd', 'Jupiter', extensions.st_setsrid(extensions.st_makepoint(-80.1090, 26.8930), 4326), 'hard', true, 'seed')
on conflict do nothing;

-- Names are the natural key for the seed; remove duplicates a second run could create.
delete from public.courts c using public.courts d
where c.source = 'seed' and d.source = 'seed' and c.name = d.name and c.created_at > d.created_at;
