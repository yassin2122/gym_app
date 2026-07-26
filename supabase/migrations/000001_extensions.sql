-- Extensions used throughout this schema.
--
-- pgcrypto:   gen_random_uuid() for every table's primary key default.
-- pg_trgm:    trigram similarity indexes for fuzzy/typo-tolerant search
--             on exercise names and aliases.
-- unaccent:   strips accents in search input ("bíceps" matches "biceps")
--             — cheap to add now, meaningfully improves search recall
--             for a dataset with international exercise names.
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists unaccent;
