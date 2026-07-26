-- RLS policies (000011) restrict WHICH rows a role can touch — but
-- Postgres separately requires table-level GRANTs before RLS is even
-- evaluated. Supabase's platform pre-configures default privileges so
-- new tables automatically grant to anon/authenticated/service_role,
-- which is why this migration is easy to forget is even necessary — but
-- a "ready to apply with minimal manual work" deliverable shouldn't
-- depend on an implicit, undocumented-in-this-repo platform behavior.
-- Explicit grants here mean this schema is correct even if applied
-- somewhere that behaves differently (e.g. a self-hosted Supabase
-- instance with different default privilege configuration).

grant usage on schema public to authenticated, anon, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant all on all tables in schema public to service_role;

grant usage, select on all sequences in schema public to authenticated, service_role;

grant execute on all functions in schema public to authenticated, service_role;

-- Ensures tables created by FUTURE migrations also get these grants
-- automatically, without needing another grants migration each time.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant select on tables to anon;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant execute on functions to authenticated, service_role;
