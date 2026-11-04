-- Profile pictures for Dominoes: players pick their own picture (or go back to
-- their Google photo, or none). Names were already editable; this is the
-- picture half. Safe to run more than once.
--
-- Pictures live in a public storage bucket, "avatars", one folder per player
-- (named after their account id), so friends' phones can show them in
-- lobbies and games. The app crops each picture to a square, shrinks it to
-- 256 by 256 and saves it as a small JPEG (about 15 KB) before uploading.

-- The bucket: public to read, JPEG only, 256 KB at most per picture.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 262144, array['image/jpeg'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Each signed-in player can add, list and remove pictures in their own
-- folder only. Seeing a picture needs no rule: the bucket is public.
drop policy if exists "Add your own picture" on storage.objects;
drop policy if exists "See your own pictures" on storage.objects;
drop policy if exists "Remove your own pictures" on storage.objects;

create policy "Add your own picture" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "See your own pictures" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Remove your own pictures" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Sets the signed-in player's picture and returns its address (or null):
--   null      no picture (initials show instead)
--   'google'  back to the photo from their Google account
--   a path    a picture they uploaded, '<their id>/<name>.jpg'
-- Players can't write any address they like into their profile: only their
-- own uploaded picture or their own Google photo.
create or replace function public.set_my_picture(p_picture text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_meta jsonb;
  v_url text;
begin
  if v_me is null then raise exception 'signed_out'; end if;

  if p_picture is null then
    v_url := null;
  elsif p_picture = 'google' then
    select raw_user_meta_data into v_meta from auth.users where id = v_me;
    v_url := coalesce(v_meta ->> 'avatar_url', v_meta ->> 'picture');
    if v_url is null or v_url !~ '^https://' or char_length(v_url) > 500 then
      raise exception 'no_google_picture';
    end if;
  else
    if p_picture !~ ('^' || v_me::text || '/[A-Za-z0-9_-]{1,64}\.jpg$')
       or not exists (select 1 from storage.objects where bucket_id = 'avatars' and name = p_picture) then
      raise exception 'bad_picture';
    end if;
    v_url := 'https://chgnvqvkcifbjtgbboqa.supabase.co/storage/v1/object/public/avatars/' || p_picture;
  end if;

  update public.profiles set avatar_url = v_url where id = v_me;
  if not found then raise exception 'no_profile'; end if;
  return v_url;
end;
$$;

revoke execute on function public.set_my_picture(text) from public, anon;
grant execute on function public.set_my_picture(text) to authenticated;
