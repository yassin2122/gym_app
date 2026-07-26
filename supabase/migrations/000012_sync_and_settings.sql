-- Offline sync queue — supports the local-first workout session flow
-- described in the original docs/SYNC.md (mobile queues writes locally,
-- pushes when connectivity returns). This table is the server-side
-- record of what was synced and when, useful for conflict debugging and
-- multi-device awareness; the mobile client's local queue itself lives
-- on-device, not here.
create table public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entity_type text not null check (entity_type in ('workout_session', 'workout_session_exercise', 'workout_set', 'weight_history', 'body_measurement')),
  entity_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  payload jsonb,
  status text not null default 'pending' check (status in ('pending', 'synced', 'failed')),
  error_message text,
  created_at timestamptz not null default now(),
  synced_at timestamptz
);

create index sync_queue_user_status_idx on public.sync_queue (user_id, status);

alter table public.sync_queue enable row level security;
create policy "sync_queue_select_own" on public.sync_queue for select using (auth.uid() = user_id);
create policy "sync_queue_insert_own" on public.sync_queue for insert with check (auth.uid() = user_id);
create policy "sync_queue_update_own" on public.sync_queue for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sync_queue_delete_own" on public.sync_queue for delete using (auth.uid() = user_id);

-- Global app configuration — feature flags, minimum supported app
-- version, maintenance-mode flags. Not user data; a single shared table
-- the whole app reads on startup.
create table public.app_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
create policy "app_settings_select_all" on public.app_settings for select using (auth.role() = 'authenticated');
create policy "app_settings_service_write" on public.app_settings for all
  using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
