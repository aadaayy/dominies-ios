-- Online games with friends. The server runs the game: it deals, keeps every
-- hand hidden (only you can see yours), checks each move, plays the computer
-- seats and keeps the score, so nobody can peek or cheat and the game goes on
-- when someone's phone is locked. The app calls the functions below; players
-- can't write to these tables directly.
--
-- Tiles are stored as one number, low * 10 + high: [2|6] is 26, [0|0] is 0.
-- Seats 0 and 2 are one team (team 0), seats 1 and 3 the other (team 1).
-- Turns go 0, 1, 2, 3.

-- ---------------------------------------------------------------------------
-- Friend codes

-- Six letters and digits that can't be mixed up (no 0/O, 1/I/L).
create function public.dom_new_code()
returns text
language sql volatile set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 6);
$$;

alter table public.profiles add column friend_code text unique;

create function public.profiles_set_friend_code()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.friend_code is null then
    loop
      new.friend_code := public.dom_new_code();
      exit when not exists (select 1 from public.profiles where friend_code = new.friend_code);
    end loop;
  end if;
  return new;
end;
$$;

create trigger profiles_friend_code
  before insert on public.profiles
  for each row execute function public.profiles_set_friend_code();

update public.profiles set friend_code = public.dom_new_code() where friend_code is null;
alter table public.profiles alter column friend_code set not null;

-- Each friendship is two rows, one each way, so "my friends" is one lookup.
create table public.friendships (
  user_id uuid not null references public.profiles (id) on delete cascade,
  friend_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index friendships_friend_idx on public.friendships (friend_id);

-- ---------------------------------------------------------------------------
-- Games

create table public.games (
  id uuid primary key default gen_random_uuid(),
  -- Six letters friends type to join.
  code text not null unique,
  host uuid references public.profiles (id) on delete set null,
  target int not null default 100 check (target in (100, 150, 200, 250)),
  bot_level text not null default 'normal' check (bot_level in ('easy', 'normal')),
  -- lobby: waiting for friends. choosing: a team picks who leads.
  -- playing, over (a game ended), match_over, closed (the host closed it).
  phase text not null default 'lobby'
    check (phase in ('lobby', 'choosing', 'playing', 'over', 'match_over', 'closed')),
  -- The match: points for team 0 and team 1, the game number, the team that
  -- leads the next game, and the winning team.
  score int[] not null default '{0,0}',
  game_number int not null default 0,
  opening_team smallint check (opening_team in (0, 1)),
  match_winner smallint check (match_winner in (0, 1)),
  -- The game in progress. Everything here is seen by every player; the hands
  -- are in game_hands, which only these functions read.
  starter smallint check (starter between 0 and 3),
  current smallint check (current between 0 and 3),
  knocks smallint not null default 0,
  left_open smallint,
  right_open smallint,
  left_len int not null default 0,
  right_len int not null default 0,
  -- Every play and knock this game, in order:
  -- {"s":seat,"t":"play","tile":[low,high],"e":"left"|"right"|null}
  -- {"s":seat,"t":"knock","l":left open,"r":right open}
  log jsonb not null default '[]',
  -- {"kind":"domino"|"blocked"|"tie","seat":n|null,"winner":0|1|null,"points":n,"pips":[team 0, team 1]}
  result jsonb,
  -- Everyone's leftover tiles once a game ends, seat by seat.
  revealed jsonb,
  -- Bumped on every change, so phones know when to fetch.
  version int not null default 0,
  turn_started_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index games_host_idx on public.games (host);

create table public.game_seats (
  game_id uuid not null references public.games (id) on delete cascade,
  seat smallint not null check (seat between 0 and 3),
  -- Null: a computer player.
  user_id uuid references public.profiles (id) on delete set null,
  primary key (game_id, seat),
  unique (game_id, user_id)
);
create index game_seats_user_idx on public.game_seats (user_id);

-- Seats 0 to 3 hold the hands; seat 4 holds the tiles nobody was dealt.
create table public.game_hands (
  game_id uuid not null references public.games (id) on delete cascade,
  seat smallint not null check (seat between 0 and 4),
  tiles int[] not null default '{}',
  primary key (game_id, seat)
);

create table public.game_invites (
  game_id uuid not null references public.games (id) on delete cascade,
  to_user uuid not null references public.profiles (id) on delete cascade,
  from_user uuid references public.profiles (id) on delete cascade,
  status text not null default 'open' check (status in ('open', 'declined', 'joined')),
  created_at timestamptz not null default now(),
  primary key (game_id, to_user)
);
create index game_invites_to_idx on public.game_invites (to_user);
create index game_invites_from_idx on public.game_invites (from_user);

-- ---------------------------------------------------------------------------
-- Tile helpers

create function public.dom_tile(a int, b int) returns int
language sql immutable set search_path = ''
as $$ select least(a, b) * 10 + greatest(a, b) $$;

create function public.dom_has(t int, v int) returns boolean
language sql immutable set search_path = ''
as $$ select t / 10 = v or t % 10 = v $$;

create function public.dom_other(t int, v int) returns int
language sql immutable set search_path = ''
as $$ select case when t / 10 = v then t % 10 else t / 10 end $$;

create function public.dom_pips(tiles int[]) returns int
language sql immutable set search_path = ''
as $$ select coalesce(sum(t / 10 + t % 10), 0)::int from unnest(tiles) t $$;

create function public.dom_tiles_json(tiles int[]) returns jsonb
language sql immutable set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_array(t / 10, t % 10) order by t % 10, t / 10), '[]'::jsonb)
  from unnest(tiles) t
$$;

-- ---------------------------------------------------------------------------
-- Who's who

create function public.dom_is_member(p_game uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.game_seats where game_id = p_game and user_id = (select auth.uid()))
$$;

create function public.dom_me() returns uuid
language plpgsql stable set search_path = ''
as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'not_signed_in'; end if;
  return v;
end;
$$;

create function public.dom_my_seat(p_game uuid) returns smallint
language plpgsql stable set search_path = ''
as $$
declare v smallint;
begin
  select seat into v from public.game_seats where game_id = p_game and user_id = public.dom_me();
  if v is null then raise exception 'not_in_game'; end if;
  return v;
end;
$$;

create function public.dom_display_name(p_user uuid) returns text
language sql stable set search_path = ''
as $$ select nullif(btrim(display_name), '') from public.profiles where id = p_user $$;

-- ---------------------------------------------------------------------------
-- The computer player: the same thinking as the app's Normal bot (Bot.swift).

create function public.dom_bot_score(
  p_hand int[], p_board int[], p_left int, p_right int, p_log jsonb, p_seat int, p_tile int, p_side text
) returns double precision
language plpgsql immutable set search_path = ''
as $$
declare
  v_rest int[] := array_remove(p_hand, p_tile);
  v_score double precision := p_tile / 10 + p_tile % 10;
  v_value int;
  v_e0 int;
  v_e1 int;
  v_follow int;
  v_next int := (p_seat + 1) % 4;
  v_partner int := (p_seat + 2) % 4;
  v_last int := (p_seat + 3) % 4;
  v_n int;
  v_action jsonb;
  m_next int[] := '{}';
  m_partner int[] := '{}';
  m_last int[] := '{}';
  v_seen int[];
  v_unseen int;
begin
  if p_tile / 10 = p_tile % 10 then v_score := v_score + 6; end if;

  -- The opening tile: lead with a heavy double, or the suit we hold most of.
  if p_side is null then
    return v_score + 2 * (select count(*) from unnest(v_rest) t
                          where public.dom_has(t, p_tile / 10) or public.dom_has(t, p_tile % 10));
  end if;

  v_value := case when p_side = 'left' then p_left else p_right end;
  if p_side = 'left' then
    v_e0 := public.dom_other(p_tile, v_value); v_e1 := p_right;
  else
    v_e0 := p_left; v_e1 := public.dom_other(p_tile, v_value);
  end if;

  -- Keep tiles we can follow up with.
  select count(*) into v_follow from unnest(v_rest) t where public.dom_has(t, v_e0) or public.dom_has(t, v_e1);
  v_score := v_score + least(v_follow, 3) * 2.5;
  if v_follow = 0 then v_score := v_score - 6; end if;

  -- Numbers each other seat is known not to hold, from their knocks.
  for v_action in select * from jsonb_array_elements(p_log) loop
    if v_action ->> 't' = 'knock' and (v_action ->> 'l')::int >= 0 then
      if (v_action ->> 's')::int = v_next then
        m_next := m_next || (v_action ->> 'l')::int || (v_action ->> 'r')::int;
      elsif (v_action ->> 's')::int = v_partner then
        m_partner := m_partner || (v_action ->> 'l')::int || (v_action ->> 'r')::int;
      elsif (v_action ->> 's')::int = v_last then
        m_last := m_last || (v_action ->> 'l')::int || (v_action ->> 'r')::int;
      end if;
    end if;
  end loop;

  -- Leave numbers the next opponent can't play; don't starve our partner.
  v_n := (v_e0 = any (m_next))::int + (v_e1 = any (m_next))::int;
  v_score := v_score + case when v_n = 2 then 25 else v_n * 6 end;
  v_score := v_score + 3 * ((v_e0 = any (m_last))::int + (v_e1 = any (m_last))::int);
  v_n := (v_e0 = any (m_partner))::int + (v_e1 = any (m_partner))::int;
  v_score := v_score - case when v_n = 2 then 12 else v_n * 4 end;

  -- A number nobody else can have is ours to control.
  v_seen := p_board || v_rest || p_tile;
  for v_n in select distinct x from unnest(array[v_e0, v_e1]) x loop
    select count(*) into v_unseen from generate_series(0, 9) o
      where not (public.dom_tile(v_n, o) = any (v_seen));
    if v_unseen = 0 and exists (select 1 from unnest(v_rest) t where public.dom_has(t, v_n)) then
      v_score := v_score + 4;
    end if;
  end loop;
  return v_score;
end;
$$;

-- ---------------------------------------------------------------------------
-- The rules (the same as Game.swift and Match.swift). These run inside the
-- functions players call, with the game row locked.

-- Ends a game: scores it, works out who leads next, and shows every hand.
create function public.dom_finish(p_game uuid, p_kind text, p_seat int)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
  v_pips int[] := '{0,0}';
  v_winner int;
  v_points int := 0;
  v_score int[];
  v_opening int;
  v_match int;
  v_revealed jsonb;
begin
  select * into g from public.games where id = p_game;
  select array[
           coalesce(sum(public.dom_pips(tiles)) filter (where seat in (0, 2)), 0),
           coalesce(sum(public.dom_pips(tiles)) filter (where seat in (1, 3)), 0)]::int[],
         jsonb_agg(public.dom_tiles_json(tiles) order by seat) filter (where seat < 4)
    into v_pips, v_revealed
    from public.game_hands where game_id = p_game;

  if p_kind = 'domino' then
    -- Going out wins the other team's pips; the partner's tiles don't count.
    v_winner := p_seat % 2;
    v_points := v_pips[2 - v_winner];
  elsif v_pips[1] = v_pips[2] then
    p_kind := 'tie';
  else
    v_winner := case when v_pips[1] < v_pips[2] then 0 else 1 end;
    v_points := greatest(v_pips[1], v_pips[2]);
  end if;

  v_score := g.score;
  if v_winner is not null then
    v_score[v_winner + 1] := v_score[v_winner + 1] + v_points;
    v_opening := v_winner;
  else
    -- After a tie the team that went second leads.
    v_opening := 1 - g.starter % 2;
  end if;
  if v_score[1] >= g.target then v_match := 0;
  elsif v_score[2] >= g.target then v_match := 1;
  end if;

  update public.games set
    score = v_score,
    opening_team = v_opening,
    match_winner = v_match,
    phase = case when v_match is null then 'over' else 'match_over' end,
    result = jsonb_build_object('kind', p_kind, 'seat', case when p_kind = 'domino' then p_seat end,
                                'winner', v_winner, 'points', v_points, 'pips', to_jsonb(v_pips)),
    revealed = v_revealed,
    current = null,
    turn_started_at = null
  where id = p_game;
end;
$$;

-- Plays a tile for whoever's turn it is. p_side can be null when the tile fits
-- only one end, both ends show the same number, or the table is empty.
create function public.dom_play(p_game uuid, p_tile int, p_side text)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
  v_hand int[];
  v_fits_left boolean;
  v_fits_right boolean;
  v_side text := p_side;
  v_value int;
begin
  select * into g from public.games where id = p_game;
  if g.phase <> 'playing' or g.current is null then raise exception 'not_playing'; end if;
  select tiles into v_hand from public.game_hands where game_id = p_game and seat = g.current;
  if not (p_tile = any (v_hand)) then raise exception 'not_in_hand'; end if;

  if g.left_open is null then
    v_side := null;
    update public.games set left_open = p_tile / 10, right_open = p_tile % 10 where id = p_game;
  else
    v_fits_left := public.dom_has(p_tile, g.left_open);
    v_fits_right := public.dom_has(p_tile, g.right_open);
    if not v_fits_left and not v_fits_right then raise exception 'does_not_fit'; end if;
    if v_side is not null then
      if (v_side = 'left' and not v_fits_left) or (v_side = 'right' and not v_fits_right)
         or v_side not in ('left', 'right') then
        raise exception 'does_not_fit';
      end if;
    elsif v_fits_left and v_fits_right then
      if g.left_open <> g.right_open then raise exception 'choose_an_end'; end if;
      -- Both ends show the same number: the shorter arm.
      v_side := case when g.left_len <= g.right_len then 'left' else 'right' end;
    else
      v_side := case when v_fits_left then 'left' else 'right' end;
    end if;
    v_value := case when v_side = 'left' then g.left_open else g.right_open end;
    if v_side = 'left' then
      update public.games set left_open = public.dom_other(p_tile, v_value), left_len = left_len + 1 where id = p_game;
    else
      update public.games set right_open = public.dom_other(p_tile, v_value), right_len = right_len + 1 where id = p_game;
    end if;
  end if;

  v_hand := array_remove(v_hand, p_tile);
  update public.game_hands set tiles = v_hand where game_id = p_game and seat = g.current;
  update public.games set
    knocks = 0,
    log = log || jsonb_build_object('s', g.current, 't', 'play',
                                    'tile', jsonb_build_array(p_tile / 10, p_tile % 10), 'e', v_side),
    current = (g.current + 1) % 4,
    turn_started_at = now()
  where id = p_game;

  if cardinality(v_hand) = 0 then
    perform public.dom_finish(p_game, 'domino', g.current);
  end if;
end;
$$;

-- Knocks for whoever's turn it is (only with nothing to play).
create function public.dom_knock(p_game uuid)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
begin
  select * into g from public.games where id = p_game;
  update public.games set
    knocks = knocks + 1,
    log = log || jsonb_build_object('s', g.current, 't', 'knock',
                                    'l', coalesce(g.left_open, -1), 'r', coalesce(g.right_open, -1)),
    current = (g.current + 1) % 4,
    turn_started_at = now()
  where id = p_game;
  if g.knocks + 1 >= 4 then
    perform public.dom_finish(p_game, 'blocked', null);
  end if;
end;
$$;

-- The tiles a seat can play now: (tile, side) pairs. Side is null on an empty table.
create function public.dom_moves(p_game uuid, p_seat int)
returns table (tile int, side text)
language sql stable set search_path = ''
as $$
  select t, s from public.games g
  join public.game_hands h on h.game_id = g.id and h.seat = p_seat
  cross join lateral unnest(h.tiles) t
  cross join lateral (values ('left'), ('right'), (null)) sides (s)
  where g.id = p_game
    and ((g.left_open is null and s is null)
      or (s = 'left' and public.dom_has(t, g.left_open))
      or (s = 'right' and public.dom_has(t, g.right_open)))
$$;

-- Plays the computer seats, and knocks for anyone with nothing to play, until
-- it's a person's turn with a tile to play or the game is over.
create function public.dom_run(p_game uuid)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
  v_human boolean;
  v_hand int[];
  v_board int[];
  v_best int;
  v_best_side text;
begin
  for i in 1..200 loop
    select * into g from public.games where id = p_game;
    exit when g.phase <> 'playing' or g.current is null;
    select user_id is not null into v_human from public.game_seats where game_id = p_game and seat = g.current;
    if not exists (select 1 from public.dom_moves(p_game, g.current)) then
      perform public.dom_knock(p_game);
      continue;
    end if;
    exit when v_human;

    select tiles into v_hand from public.game_hands where game_id = p_game and seat = g.current;
    select coalesce(array_agg(public.dom_tile((a -> 'tile' ->> 0)::int, (a -> 'tile' ->> 1)::int)), '{}')
      into v_board from jsonb_array_elements(g.log) a where a ->> 't' = 'play';
    if g.bot_level = 'easy' then
      select m.tile, m.side into v_best, v_best_side from public.dom_moves(p_game, g.current) m order by random() limit 1;
    else
      select m.tile, m.side into v_best, v_best_side from public.dom_moves(p_game, g.current) m
        order by public.dom_bot_score(v_hand, v_board, g.left_open, g.right_open, g.log, g.current, m.tile, m.side)
                 + random() * 0.5 desc
        limit 1;
    end if;
    perform public.dom_play(p_game, v_best, v_best_side);
  end loop;
end;
$$;

-- Shuffles and deals the next game. Deals again if anyone gets five doubles.
create function public.dom_deal(p_game uuid)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
  v_all int[];
  v_ok boolean;
  v_opening int;
  v_starter int;
  v_doubles int[];
begin
  select * into g from public.games where id = p_game;
  loop
    select array_agg(t order by random()) into v_all
      from (select public.dom_tile(a, b) t from generate_series(0, 9) a, generate_series(0, 9) b where a <= b) s;
    select bool_and(n < 5) into v_ok from (
      select (select count(*) from unnest(v_all[s * 10 + 1 : s * 10 + 10]) t where t / 10 = t % 10) n
      from generate_series(0, 3) s) d;
    exit when v_ok;
  end loop;

  delete from public.game_hands where game_id = p_game;
  insert into public.game_hands (game_id, seat, tiles)
    select p_game, s, v_all[s * 10 + 1 : s * 10 + 10] from generate_series(0, 3) s
    union all select p_game, 4, v_all[41:55];

  -- The first game's leading team comes from a fair draw; after that it's set
  -- by the game before.
  v_opening := case when g.game_number = 0 then floor(random() * 2)::int else g.opening_team end;

  update public.games set
    game_number = game_number + 1, opening_team = v_opening,
    starter = null, current = null, knocks = 0,
    left_open = null, right_open = null, left_len = 0, right_len = 0,
    log = '[]', result = null, revealed = null, turn_started_at = now()
  where id = p_game;

  if exists (select 1 from public.game_seats where game_id = p_game and seat % 2 = v_opening and user_id is not null) then
    -- A person on the leading team chooses who plays first.
    update public.games set phase = 'choosing' where id = p_game;
  else
    -- Two computers lead: the one holding more doubles.
    select array_agg((select count(*) from unnest(v_all[s * 10 + 1 : s * 10 + 10]) t where t / 10 = t % 10) order by s)
      into v_doubles from generate_series(0, 3) s;
    v_starter := case when v_doubles[v_opening + 1] >= v_doubles[v_opening + 3] then v_opening else v_opening + 2 end;
    update public.games set phase = 'playing', starter = v_starter, current = v_starter where id = p_game;
    perform public.dom_run(p_game);
  end if;
end;
$$;

-- After a seat changes hands mid-match: if nobody is left to choose who
-- leads, the computers choose; if it's now a computer's turn, it plays.
create function public.dom_after_seat_change(p_game uuid)
returns void
language plpgsql set search_path = ''
as $$
declare
  g public.games;
  v_doubles int[];
  v_starter int;
begin
  select * into g from public.games where id = p_game;
  if g.phase = 'choosing' and not exists (
       select 1 from public.game_seats where game_id = p_game and seat % 2 = g.opening_team and user_id is not null) then
    select array_agg((select count(*) from public.game_hands h, unnest(h.tiles) t
                      where h.game_id = p_game and h.seat = s and t / 10 = t % 10) order by s)
      into v_doubles from generate_series(0, 3) s;
    v_starter := case when v_doubles[g.opening_team + 1] >= v_doubles[g.opening_team + 3]
                      then g.opening_team else g.opening_team + 2 end;
    update public.games set phase = 'playing', starter = v_starter, current = v_starter, turn_started_at = now()
      where id = p_game;
  end if;
  perform public.dom_run(p_game);
end;
$$;

-- Locks a game for a change and checks the player is in it.
create function public.dom_lock(p_game uuid)
returns public.games
language plpgsql set search_path = ''
as $$
declare g public.games;
begin
  select * into g from public.games where id = p_game for update;
  if g.id is null then raise exception 'no_such_game'; end if;
  perform public.dom_my_seat(p_game);
  return g;
end;
$$;

create function public.dom_touch(p_game uuid)
returns void
language sql set search_path = ''
as $$ update public.games set version = version + 1, updated_at = now() where id = p_game $$;

-- ---------------------------------------------------------------------------
-- What the app calls

-- Everything a player's phone shows for one game: the table, the score, the
-- seats with names, and that player's own hand (never anyone else's until the
-- game ends).
create function public.game_state(p_game uuid)
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
    'my_seat', v_seat, 'is_host', g.host = v_me, 'version', g.version,
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
                'you', s.user_id = v_me,
                'host', s.user_id = g.host) order by s.seat)
              from public.game_seats s left join public.profiles p on p.id = s.user_id
              where s.game_id = p_game),
    'hand', (select public.dom_tiles_json(tiles) from public.game_hands where game_id = p_game and seat = v_seat)
  );
end;
$$;

-- A new game with you in the first seat and computers in the other three,
-- until friends join.
create function public.create_game(p_target int default 100, p_level text default 'normal')
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := public.dom_me();
  v_code text;
  v_id uuid;
begin
  if public.dom_display_name(v_me) is null then raise exception 'needs_name'; end if;
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

-- Joins with the game's code, taking the first computer seat: the host's
-- partner first, then the two opponents.
create function public.join_game(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := public.dom_me();
  g public.games;
  v_seat smallint;
begin
  if public.dom_display_name(v_me) is null then raise exception 'needs_name'; end if;
  select * into g from public.games where code = upper(btrim(p_code)) for update;
  if g.id is null then raise exception 'no_such_game'; end if;
  if exists (select 1 from public.game_seats where game_id = g.id and user_id = v_me) then
    return public.game_state(g.id);
  end if;
  if g.phase <> 'lobby' then
    raise exception '%', case when g.phase = 'closed' then 'game_closed' else 'already_started' end;
  end if;
  select seat into v_seat from public.game_seats where game_id = g.id and user_id is null
    order by array_position(array[2, 1, 3, 0], seat::int) limit 1;
  if v_seat is null then raise exception 'game_full'; end if;
  update public.game_seats set user_id = v_me where game_id = g.id and seat = v_seat;
  update public.game_invites set status = 'joined' where game_id = g.id and to_user = v_me;
  perform public.dom_touch(g.id);
  return public.game_state(g.id);
end;
$$;

-- Before the game starts: move to another computer seat (to pick your partner).
create function public.move_seat(p_game uuid, p_seat int)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  g public.games := public.dom_lock(p_game);
  v_mine smallint := public.dom_my_seat(p_game);
begin
  if g.phase <> 'lobby' then raise exception 'already_started'; end if;
  if p_seat <> v_mine then
    if (select user_id from public.game_seats where game_id = p_game and seat = p_seat) is not null
       or p_seat not between 0 and 3 then
      raise exception 'seat_taken';
    end if;
    update public.game_seats set user_id = null where game_id = p_game and seat = v_mine;
    update public.game_seats set user_id = (select auth.uid()) where game_id = p_game and seat = p_seat;
    perform public.dom_touch(p_game);
  end if;
  return public.game_state(p_game);
end;
$$;

-- The host's choices before the game starts.
create function public.set_game_options(p_game uuid, p_target int, p_level text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare g public.games := public.dom_lock(p_game);
begin
  if g.host is distinct from (select auth.uid()) then raise exception 'host_only'; end if;
  if g.phase <> 'lobby' then raise exception 'already_started'; end if;
  update public.games set target = p_target, bot_level = p_level where id = p_game;
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

create function public.start_game(p_game uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare g public.games := public.dom_lock(p_game);
begin
  if g.host is distinct from (select auth.uid()) then raise exception 'host_only'; end if;
  if g.phase <> 'lobby' then return public.game_state(p_game); end if;
  update public.game_invites set status = 'declined' where game_id = p_game and status = 'open';
  perform public.dom_deal(p_game);
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

-- The leading team picks who plays first (either person on it may choose).
create function public.choose_leader(p_game uuid, p_seat int)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  g public.games := public.dom_lock(p_game);
  v_mine smallint := public.dom_my_seat(p_game);
begin
  if g.phase <> 'choosing' then return public.game_state(p_game); end if;
  if v_mine % 2 <> g.opening_team then raise exception 'not_your_team'; end if;
  if p_seat % 2 <> g.opening_team or p_seat not between 0 and 3 then raise exception 'not_your_team'; end if;
  update public.games set phase = 'playing', starter = p_seat, current = p_seat, turn_started_at = now() where id = p_game;
  perform public.dom_run(p_game);
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

-- Plays one of your tiles on your turn. p_end is 'left', 'right' or null.
-- The computers (and anyone with nothing to play) then take their turns.
create function public.play_tile(p_game uuid, p_low int, p_high int, p_end text default null)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  g public.games := public.dom_lock(p_game);
  v_mine smallint := public.dom_my_seat(p_game);
begin
  if g.phase <> 'playing' then raise exception 'not_playing'; end if;
  if g.current is distinct from v_mine then raise exception 'not_your_turn'; end if;
  perform public.dom_play(p_game, public.dom_tile(p_low, p_high), p_end);
  perform public.dom_run(p_game);
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

-- Deals the next game once one ends. p_game_number is the game just finished,
-- so two people pressing Next game at once deal only one.
create function public.next_game(p_game uuid, p_game_number int)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare g public.games := public.dom_lock(p_game);
begin
  if g.phase = 'over' and g.game_number = p_game_number then
    perform public.dom_deal(p_game);
    perform public.dom_touch(p_game);
  end if;
  return public.game_state(p_game);
end;
$$;

-- Someone's phone stopped answering: after a minute on their turn, another
-- player can let a computer take their seat.
create function public.replace_with_computer(p_game uuid, p_seat int)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare g public.games := public.dom_lock(p_game);
begin
  if g.phase <> 'playing' or g.current is distinct from p_seat
     or g.turn_started_at > now() - interval '60 seconds' then
    raise exception 'still_their_turn';
  end if;
  update public.game_seats set user_id = null where game_id = p_game and seat = p_seat;
  perform public.dom_after_seat_change(p_game);
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

-- Leaving. Before the start your seat goes back to a computer (and if you're
-- the host, the game is closed). During a match a computer takes over your
-- tiles. When nobody is left, the game is closed.
create function public.leave_game(p_game uuid)
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
    update public.games set phase = 'closed', current = null where id = p_game;
    update public.game_invites set status = 'declined' where game_id = p_game and status = 'open';
  elsif g.phase in ('choosing', 'playing') then
    perform public.dom_after_seat_change(p_game);
  end if;
  perform public.dom_touch(p_game);
end;
$$;

-- ---------------------------------------------------------------------------
-- Friends and invites

-- Adds a friend by their code. Both of you then see each other in Friends.
create function public.add_friend(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_me uuid := public.dom_me();
  v_friend public.profiles;
begin
  select * into v_friend from public.profiles where friend_code = upper(replace(btrim(p_code), '-', ''));
  if v_friend.id is null then raise exception 'no_such_code'; end if;
  if v_friend.id = v_me then raise exception 'thats_you'; end if;
  if (select count(*) from public.friendships where user_id = v_me) >= 200 then raise exception 'too_many_friends'; end if;
  insert into public.friendships (user_id, friend_id) values (v_me, v_friend.id), (v_friend.id, v_me)
    on conflict do nothing;
  return jsonb_build_object('id', v_friend.id, 'name', coalesce(nullif(btrim(v_friend.display_name), ''), 'Player'),
                            'picture', v_friend.avatar_url);
end;
$$;

create function public.remove_friend(p_friend uuid)
returns void
language sql volatile security definer set search_path = ''
as $$
  delete from public.friendships
  where (user_id = public.dom_me() and friend_id = p_friend) or (user_id = p_friend and friend_id = public.dom_me());
$$;

-- Invites a friend to a game you're in that hasn't started.
create function public.invite_friend(p_game uuid, p_friend uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  g public.games := public.dom_lock(p_game);
  v_me uuid := public.dom_me();
begin
  if g.phase <> 'lobby' then raise exception 'already_started'; end if;
  if not exists (select 1 from public.friendships where user_id = v_me and friend_id = p_friend) then
    raise exception 'not_a_friend';
  end if;
  insert into public.game_invites (game_id, to_user, from_user) values (p_game, p_friend, v_me)
    on conflict (game_id, to_user) do update
      set status = 'open', from_user = excluded.from_user, created_at = now()
      where public.game_invites.status <> 'joined';
  perform public.dom_touch(p_game);
  return public.game_state(p_game);
end;
$$;

create function public.decline_invite(p_game uuid)
returns void
language sql volatile security definer set search_path = ''
as $$
  update public.game_invites set status = 'declined' where game_id = p_game and to_user = public.dom_me();
$$;

-- Home: your name and friend code, your friends (with whether each is
-- invited to or playing in each of your open games), open invites to you,
-- and the games you're in.
create function public.home_state()
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
               'is_host', g.host = v_me,
               'your_turn', (g.phase = 'playing' and g.current = s.seat)
                            or (g.phase = 'choosing' and g.opening_team = s.seat % 2),
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

-- ---------------------------------------------------------------------------
-- Access. Players read only the games they sit in (for live updates) and their
-- own friendships and invites; every change goes through the functions above.
-- Hands are never readable directly.

alter table public.friendships enable row level security;
alter table public.games enable row level security;
alter table public.game_seats enable row level security;
alter table public.game_hands enable row level security;
alter table public.game_invites enable row level security;

create policy "See your friendships" on public.friendships
  for select to authenticated using (user_id = (select auth.uid()));
create policy "See games you're in" on public.games
  for select to authenticated using (public.dom_is_member(id));
create policy "See seats in games you're in" on public.game_seats
  for select to authenticated using (public.dom_is_member(game_id));
create policy "See invites to or from you" on public.game_invites
  for select to authenticated using (to_user = (select auth.uid()) or from_user = (select auth.uid()));

revoke all on public.friendships, public.games, public.game_seats, public.game_hands, public.game_invites
  from anon, authenticated;
grant select on public.friendships, public.games, public.game_seats, public.game_invites to authenticated;

-- Live updates: a phone in a game hears when that game changes, and Home hears
-- new invites.
alter publication supabase_realtime add table public.games, public.game_invites;

-- Only the app-facing functions can be called, only by signed-in players.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig, p.proname from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and (p.proname like 'dom\_%' or p.proname in (
               'game_state', 'create_game', 'join_game', 'move_seat', 'set_game_options', 'start_game',
               'choose_leader', 'play_tile', 'next_game', 'replace_with_computer', 'leave_game',
               'add_friend', 'remove_friend', 'invite_friend', 'decline_invite', 'home_state',
               'profiles_set_friend_code')) loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname not like 'dom\_%' and f.proname <> 'profiles_set_friend_code' then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end;
$$;
-- The row level security check above uses this one.
grant execute on function public.dom_is_member(uuid) to authenticated;
