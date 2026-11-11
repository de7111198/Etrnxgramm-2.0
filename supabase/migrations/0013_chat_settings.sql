-- Per-user chat settings: archive state, mute deadline and pin ordering.
create table public.chat_user_settings (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  archived_at timestamptz,
  muted_until timestamptz,
  pinned_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
alter table public.chat_user_settings enable row level security;

create policy "Users read their own chat settings"
  on public.chat_user_settings for select to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users create their own chat settings"
  on public.chat_user_settings for insert to authenticated
  with check (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users update their own chat settings"
  on public.chat_user_settings for update to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id))
  with check (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "Users delete their own chat settings"
  on public.chat_user_settings for delete to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));
