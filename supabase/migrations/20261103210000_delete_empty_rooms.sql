-- Rooms don't pile up: a game is deleted (with its seats, hands and invites)
-- when the host disbands it, when the host leaves before it starts, or when
-- the last person leaves, finished or not. Rooms people simply walked away
-- from are cleaned up too: finished ones after a day, unstarted ones after a
-- day, and anything untouched for two weeks.

create index if not exists games_updated_idx on public.games (updated_at);

-- Deletes old rooms nobody will come back to. Runs whenever someone makes a
-- new game, so no scheduled job is needed.
create or replace function public.dom_cleanup()
returns void
language sql volatile set search_path = ''
as $$
  delete from public.games
  where (phase in ('match_over', 'closed', 'lobby') and updated_at < now() - interval '1 day')
     or updated_at < now() - interval '14 days';
$$;

create or replace function public.leave_game(p_game uuid)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  g public.games := public.dom_lock(p_game);
  v_me uuid := public.dom_me();
begin
  update public.game_seats set user_id = null where game_id = p_game and user_id = v_me;
  if (g.phase = 'lobby' and g.host = v_me)
     or not exists (select 1 from public.game_seats where game_id = p_game and user_id is not null) then
    -- The host disbanded it before the start, or nobody is left: gone.
    delete from public.games where id = p_game;
    return;
  elsif g.phase in ('choosing', 'playing') then
    perform public.dom_after_seat_change(p_game);
  end if;
  perform public.dom_touch(p_game);
end;
$$;

-- The host ends the room for everyone, at any point.
create function public.disband_game(p_game uuid)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare g public.games := public.dom_lock(p_game);
begin
  if g.host is distinct from (select auth.uid()) then raise exception 'host_only'; end if;
  delete from public.games where id = p_game;
end;
$$;

-- Same as before, plus the clean-up of old rooms.
create or replace function public.create_game(p_target int default 100, p_level text default 'normal')
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := public.dom_me();
  v_code text;
  v_id uuid;
begin
  if public.dom_display_name(v_me) is null then raise exception 'needs_name'; end if;
  perform public.dom_cleanup();
  if (select count(*) from public.game_seats s join public.games g on g.id = s.game_id
      where s.user_id = v_me and g.phase not in ('match_over', 'closed')) >= 20 then
    raise exception 'too_many_games';
  end if;
  loop
    v_code := public.dom_new_code();
    exit when not exists (select 1 from public.games where code = v_code);
  end loop;
  insert into public.games (code, host, target, bot_level) values (v_code, v_me, p_target, p_level)
    returning id into v_id;
  insert into public.game_seats (game_id, seat, user_id)
    values (v_id, 0, v_me), (v_id, 1, null), (v_id, 2, null), (v_id, 3, null);
  return public.game_state(v_id);
end;
$$;

-- Yes/no answers are always true or false (never empty) for computer seats
-- and for a host who deleted their account.
create or replace function public.game_state(p_game uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  g public.games;
  v_me uuid := public.dom_me();
  v_seat smallint;
begin
  select * into g from public.games where id = p_game;
  select seat into v_seat from public.game_seats where game_id = p_game and user_id = v_me;
  if g.id is null or v_seat is null then raise exception 'not_in_game'; end if;
  return jsonb_build_object(
    'id', g.id, 'code', g.code, 'phase', g.phase, 'target', g.target, 'level', g.bot_level,
    'my_seat', v_seat, 'is_host', coalesce(g.host = v_me, false), 'version', g.version,
    'score', to_jsonb(g.score), 'game_number', g.game_number, 'opening_team', g.opening_team,
    'match_winner', g.match_winner, 'starter', g.starter, 'current', g.current,
    'log', g.log, 'result', g.result, 'revealed', g.revealed,
    'turn_seconds', case when g.turn_started_at is null then null
                         else floor(extract(epoch from now() - g.turn_started_at))::int end,
    'seats', (select jsonb_agg(jsonb_build_object(
                'seat', s.seat,
                'name', case when s.user_id is null then null else coalesce(public.dom_display_name(s.user_id), 'Player') end,
                'picture', p.avatar_url,
                'person', s.user_id is not null,
                'you', coalesce(s.user_id = v_me, false),
                'host', coalesce(s.user_id = g.host, false)) order by s.seat)
              from public.game_seats s left join public.profiles p on p.id = s.user_id
              where s.game_id = p_game),
    'hand', (select public.dom_tiles_json(tiles) from public.game_hands where game_id = p_game and seat = v_seat)
  );
end;
$$;

create or replace function public.home_state()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_me uuid := public.dom_me();
begin
  return jsonb_build_object(
    'name', public.dom_display_name(v_me),
    'friend_code', (select friend_code from public.profiles where id = v_me),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(nullif(btrim(p.display_name), ''), 'Player'),
                                          'picture', p.avatar_url)
                       order by lower(p.display_name))
      from public.friendships f join public.profiles p on p.id = f.friend_id
      where f.user_id = v_me), '[]'),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object(
               'game_id', g.id, 'code', g.code,
               'from', coalesce(public.dom_display_name(i.from_user), 'A friend'),
               'from_picture', (select avatar_url from public.profiles where id = i.from_user),
               'players', (select coalesce(jsonb_agg(coalesce(public.dom_display_name(s.user_id), 'Player') order by s.seat), '[]')
                           from public.game_seats s where s.game_id = g.id and s.user_id is not null),
               'sent_at', i.created_at)
             order by i.created_at desc)
      from public.game_invites i join public.games g on g.id = i.game_id
      where i.to_user = v_me and i.status = 'open' and g.phase = 'lobby'
        and not exists (select 1 from public.game_seats s where s.game_id = g.id and s.user_id = v_me)), '[]'),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.id, 'code', g.code, 'phase', g.phase, 'game_number', g.game_number,
               'is_host', coalesce(g.host = v_me, false),
               'your_turn', coalesce((g.phase = 'playing' and g.current = s.seat)
                                     or (g.phase = 'choosing' and g.opening_team = s.seat % 2), false),
               'players', (select coalesce(jsonb_agg(coalesce(public.dom_display_name(o.user_id), 'Player') order by o.seat), '[]')
                           from public.game_seats o where o.game_id = g.id and o.user_id is not null and o.user_id <> v_me),
               'invited', (select coalesce(jsonb_agg(i.to_user), '[]') from public.game_invites i
                           where i.game_id = g.id and i.status = 'open'),
               'score', to_jsonb(g.score), 'my_seat', s.seat, 'updated_at', g.updated_at)
             order by g.updated_at desc)
      from public.game_seats s join public.games g on g.id = s.game_id
      where s.user_id = v_me and g.phase in ('lobby', 'choosing', 'playing', 'over')), '[]')
  );
end;
$$;

-- Rooms already closed before this change.
delete from public.games where phase = 'closed';

revoke execute on function public.dom_cleanup() from public, anon, authenticated;
revoke execute on function public.disband_game(uuid) from public, anon;
grant execute on function public.disband_game(uuid) to authenticated;
