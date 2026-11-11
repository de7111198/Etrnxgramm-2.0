-- Persistent profile cover image URL.
alter table public.profiles
  add column if not exists cover_url text;

alter table public.profiles
  add constraint profiles_avatar_url_length
  check (avatar_url is null or char_length(avatar_url) <= 2048);

alter table public.profiles
  add constraint profiles_cover_url_length
  check (cover_url is null or char_length(cover_url) <= 2048);
