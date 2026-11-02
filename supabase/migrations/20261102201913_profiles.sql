-- Player accounts for Dominoes. Sign-in itself (Google) is Supabase Auth; this
-- adds one profile row per player with the name and picture other players
-- will see later. Applied to the Dominoes project (not the golf project).

-- One row per account, made automatically the first time someone signs in.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 40),
  avatar_url text check (avatar_url is null or (char_length(avatar_url) <= 500 and avatar_url ~ '^https://')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Name and picture from Google, the first time someone signs in.
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_avatar text := coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture');
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '')), 40),
    case when v_avatar ~ '^https://' and char_length(v_avatar) <= 500 then v_avatar end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keeps updated_at honest when a player changes their name.
create function public.touch_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Delete Account in the app: removes the sign-in and, through the cascade,
-- the profile. Apple requires this for apps with accounts.
create function public.delete_my_account()
returns void
language sql security definer set search_path = ''
as $$
  delete from auth.users where id = (select auth.uid());
$$;

-- Access: each player sees and changes only their own profile, and only its
-- name. Nothing for people who aren't signed in.
alter table public.profiles enable row level security;

create policy "See your own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "Change your own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

revoke all on public.profiles from anon, authenticated;
grant select, update (display_name) on public.profiles to authenticated;

revoke execute on function public.handle_new_user(), public.touch_updated_at(), public.delete_my_account()
  from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;
