-- ============================================================
-- FGOTG — First Goal of the Game
-- Supabase / Postgres Schema
-- Run this in your Supabase SQL editor (Dashboard → SQL Editor → New query)
-- ============================================================

-- ============================================================
-- 0. SETUP
-- ============================================================

-- Enable UUID generation (already enabled in Supabase by default)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. TABLES
-- ============================================================

-- User profiles (extends auth.users)
CREATE TABLE public.profiles (
  id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username   text NOT NULL UNIQUE,
  email      text NOT NULL UNIQUE,   -- duplicated from auth.users for username→email lookups
  team_id    text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Leagues
CREATE TABLE public.leagues (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL,
  team_id           text NOT NULL,
  current_season_id uuid,            -- FK added below after seasons table
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- League membership (member or admin)
CREATE TABLE public.league_members (
  league_id uuid NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES auth.users(id)     ON DELETE CASCADE,
  role      text NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (league_id, user_id)
);
CREATE INDEX league_members_user_idx ON public.league_members(user_id);

-- Seasons
CREATE TABLE public.seasons (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id  uuid NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  name       text NOT NULL,
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
  start_date timestamptz NOT NULL DEFAULT now(),
  end_date   timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX seasons_league_idx ON public.seasons(league_id, status);

-- Add deferred FK from leagues.current_season_id → seasons.id
-- (deferred so we can insert league + season in separate steps)
ALTER TABLE public.leagues
  ADD CONSTRAINT leagues_current_season_fk
  FOREIGN KEY (current_season_id) REFERENCES public.seasons(id)
  ON DELETE SET NULL;

-- Games
CREATE TABLE public.games (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id  uuid NOT NULL REFERENCES public.leagues(id)  ON DELETE CASCADE,
  season_id  uuid NOT NULL REFERENCES public.seasons(id)  ON DELETE CASCADE,
  opponent   text NOT NULL,
  home_away  text NOT NULL DEFAULT 'home' CHECK (home_away IN ('home','away')),
  puck_drop  timestamptz NOT NULL,
  deadline   timestamptz NOT NULL,
  status     text NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming','locked','completed')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX games_league_season_idx ON public.games(league_id, season_id, puck_drop);

-- Picks
CREATE TABLE public.picks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id)    ON DELETE CASCADE,
  game_id      uuid NOT NULL REFERENCES public.games(id)  ON DELETE CASCADE,
  league_id    uuid NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  regular      text NOT NULL,
  darkhorse    text,
  is_shutout   boolean NOT NULL DEFAULT false,
  play_type    text NOT NULL DEFAULT 'es' CHECK (play_type IN ('es','pp','pk')),
  dh_play_type text NOT NULL DEFAULT 'es' CHECK (dh_play_type IN ('es','pp','pk')),
  pts          smallint,
  breakdown    jsonb DEFAULT '{}'::jsonb,
  scored       boolean NOT NULL DEFAULT false,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, game_id)
);
CREATE INDEX picks_game_idx    ON public.picks(game_id);
CREATE INDEX picks_user_league ON public.picks(user_id, league_id);

-- Results
CREATE TABLE public.results (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id          uuid NOT NULL UNIQUE REFERENCES public.games(id) ON DELETE CASCADE,
  first_scorer     text,
  first_play_type  text CHECK (first_play_type IN ('es','pp','pk')),
  is_shutout       boolean NOT NULL DEFAULT false,
  second_scorer    text,
  second_play_type text CHECK (second_play_type IN ('es','pp','pk')),
  entered_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  entered_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz
);

-- Roster (players eligible to be picked in a league)
CREATE TABLE public.league_players (
  league_id   uuid NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  player_name text NOT NULL,
  PRIMARY KEY (league_id, player_name)
);
CREATE INDEX league_players_league_idx ON public.league_players(league_id);

-- Darkhorse-ineligible players
CREATE TABLE public.ineligible_players (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id   uuid NOT NULL REFERENCES public.leagues(id) ON DELETE CASCADE,
  player_name text NOT NULL,
  note        text,
  added_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  added_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (league_id, player_name)
);
CREATE INDEX ineligible_league_idx ON public.ineligible_players(league_id);

-- Notifications
CREATE TABLE public.notifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id)     ON DELETE CASCADE,
  league_id  uuid REFERENCES public.leagues(id)          ON DELETE CASCADE,
  message    text NOT NULL,
  type       text NOT NULL DEFAULT 'system',
  read       boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON public.notifications(user_id, read);
CREATE INDEX notifications_user_time ON public.notifications(user_id, created_at DESC);

-- ============================================================
-- 2. PROFILE CREATION TRIGGER
-- Automatically creates a profiles row when a user signs up.
-- The username is passed via options.data.username in supabase.auth.signUp()
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, username, email, team_id)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'username',
    NEW.email,
    NEW.raw_user_meta_data->>'team_id'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 3. RLS HELPER FUNCTIONS
-- SECURITY DEFINER prevents recursive RLS policy evaluation.
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_league_member(p_league_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM league_members
    WHERE league_id = p_league_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_league_admin(p_league_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM league_members
    WHERE league_id = p_league_id AND user_id = auth.uid() AND role = 'admin'
  );
$$;

-- ============================================================
-- 4. RLS POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leagues            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.league_members     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seasons            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.games              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.picks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.league_players     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ineligible_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications      ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "profiles_select" ON public.profiles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "profiles_insert" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update" ON public.profiles
  FOR UPDATE TO authenticated USING (id = auth.uid());

-- leagues: any authenticated user can browse leagues (to join one)
CREATE POLICY "leagues_select" ON public.leagues
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "leagues_insert" ON public.leagues
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "leagues_update" ON public.leagues
  FOR UPDATE TO authenticated USING (is_league_admin(id));

-- league_members
CREATE POLICY "lm_select" ON public.league_members
  FOR SELECT TO authenticated USING (is_league_member(league_id));

CREATE POLICY "lm_insert" ON public.league_members
  FOR INSERT TO authenticated WITH CHECK (
    is_league_admin(league_id) OR user_id = auth.uid()
  );

CREATE POLICY "lm_update" ON public.league_members
  FOR UPDATE TO authenticated USING (is_league_admin(league_id));

CREATE POLICY "lm_delete" ON public.league_members
  FOR DELETE TO authenticated USING (
    is_league_admin(league_id) OR user_id = auth.uid()
  );

-- seasons
CREATE POLICY "seasons_select" ON public.seasons
  FOR SELECT TO authenticated USING (is_league_member(league_id));

CREATE POLICY "seasons_insert" ON public.seasons
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id));

CREATE POLICY "seasons_update" ON public.seasons
  FOR UPDATE TO authenticated USING (is_league_admin(league_id));

-- games
CREATE POLICY "games_select" ON public.games
  FOR SELECT TO authenticated USING (is_league_member(league_id));

CREATE POLICY "games_insert" ON public.games
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id));

CREATE POLICY "games_update" ON public.games
  FOR UPDATE TO authenticated USING (is_league_admin(league_id));

CREATE POLICY "games_delete" ON public.games
  FOR DELETE TO authenticated USING (is_league_admin(league_id));

-- picks: users write own picks; league admins can update for scoring
CREATE POLICY "picks_select" ON public.picks
  FOR SELECT TO authenticated USING (
    user_id = auth.uid() OR is_league_member(league_id)
  );

CREATE POLICY "picks_insert" ON public.picks
  FOR INSERT TO authenticated WITH CHECK (
    user_id = auth.uid()
    AND is_league_member(league_id)
    AND (SELECT deadline FROM public.games WHERE id = game_id) > now()
  );

CREATE POLICY "picks_update" ON public.picks
  FOR UPDATE TO authenticated USING (
    (user_id = auth.uid()
      AND (SELECT deadline FROM public.games WHERE id = game_id) > now())
    OR is_league_admin(league_id)
  );

-- results
CREATE POLICY "results_select" ON public.results
  FOR SELECT TO authenticated USING (
    is_league_member((SELECT league_id FROM public.games WHERE id = game_id))
  );

CREATE POLICY "results_insert" ON public.results
  FOR INSERT TO authenticated WITH CHECK (
    is_league_admin((SELECT league_id FROM public.games WHERE id = game_id))
  );

CREATE POLICY "results_update" ON public.results
  FOR UPDATE TO authenticated USING (
    is_league_admin((SELECT league_id FROM public.games WHERE id = game_id))
  );

-- league_players
CREATE POLICY "lp_select" ON public.league_players
  FOR SELECT TO authenticated USING (is_league_member(league_id));

CREATE POLICY "lp_insert" ON public.league_players
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id));

CREATE POLICY "lp_delete" ON public.league_players
  FOR DELETE TO authenticated USING (is_league_admin(league_id));

-- ineligible_players
CREATE POLICY "ip_select" ON public.ineligible_players
  FOR SELECT TO authenticated USING (is_league_member(league_id));

CREATE POLICY "ip_insert" ON public.ineligible_players
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id));

CREATE POLICY "ip_delete" ON public.ineligible_players
  FOR DELETE TO authenticated USING (is_league_admin(league_id));

-- notifications
CREATE POLICY "notifs_select" ON public.notifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "notifs_insert" ON public.notifications
  FOR INSERT TO authenticated WITH CHECK (
    is_league_admin(league_id) OR user_id = auth.uid()
  );

CREATE POLICY "notifs_update" ON public.notifications
  FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- ============================================================
-- 5. RPC FUNCTIONS
-- ============================================================

-- Broadcast a notification to all members of a league
CREATE OR REPLACE FUNCTION public.broadcast_notif(
  p_league_id uuid,
  p_message   text,
  p_type      text DEFAULT 'system'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_league_admin(p_league_id) THEN
    RAISE EXCEPTION 'Not authorized: must be league admin';
  END IF;
  INSERT INTO notifications (user_id, league_id, message, type)
  SELECT user_id, p_league_id, p_message, p_type
  FROM league_members WHERE league_id = p_league_id;
END;
$$;

-- Atomically replace the entire roster for a league
CREATE OR REPLACE FUNCTION public.set_league_players(
  p_league_id uuid,
  p_players   text[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_league_admin(p_league_id) THEN
    RAISE EXCEPTION 'Not authorized: must be league admin';
  END IF;
  DELETE FROM league_players WHERE league_id = p_league_id;
  IF array_length(p_players, 1) IS NOT NULL THEN
    INSERT INTO league_players (league_id, player_name)
    SELECT p_league_id, unnest(p_players);
  END IF;
END;
$$;

-- Score all picks for a game after result is entered
-- Admin-only; updates pts/breakdown/scored on each pick
CREATE OR REPLACE FUNCTION public.score_game(p_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_league_id  uuid;
  v_result     results%ROWTYPE;
  v_pick       picks%ROWTYPE;
  v_pts        smallint;
  v_breakdown  jsonb;
  v_dh_scored  boolean;
  v_reg_scored boolean;
  v_pt_pts     smallint;
BEGIN
  -- Check caller is admin
  SELECT league_id INTO v_league_id FROM games WHERE id = p_game_id;
  IF NOT is_league_admin(v_league_id) THEN
    RAISE EXCEPTION 'Not authorized: must be league admin';
  END IF;

  -- Get result
  SELECT * INTO v_result FROM results WHERE game_id = p_game_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No result found for game %', p_game_id;
  END IF;

  -- Score each pick
  FOR v_pick IN SELECT * FROM picks WHERE game_id = p_game_id LOOP
    v_pts := 0;
    v_breakdown := '{}'::jsonb;

    IF v_result.is_shutout THEN
      IF v_pick.is_shutout THEN
        v_pts := 5;
        v_breakdown := '{"shutout": 5}'::jsonb;
      END IF;
    ELSE
      v_dh_scored  := v_pick.darkhorse IS NOT NULL AND v_pick.darkhorse = v_result.first_scorer;
      v_reg_scored := NOT v_dh_scored AND v_pick.regular = v_result.first_scorer;

      IF v_dh_scored THEN
        v_pts := v_pts + 3;
        v_breakdown := v_breakdown || '{"darkhorse": 3}';

        IF v_pick.play_type = v_result.first_play_type THEN
          v_pt_pts := CASE WHEN v_result.first_play_type = 'pk' THEN 3 ELSE 1 END;
          v_pts := v_pts + v_pt_pts;
          v_breakdown := v_breakdown || jsonb_build_object('playType', v_pt_pts);
        END IF;

        -- Bonus: check regular against second goal
        IF v_result.second_scorer IS NOT NULL AND v_pick.regular = v_result.second_scorer THEN
          v_pts := v_pts + 1;
          v_breakdown := v_breakdown || '{"bonusScorer": 1}';
          IF v_pick.play_type = v_result.second_play_type THEN
            v_pt_pts := CASE WHEN v_result.second_play_type = 'pk' THEN 3 ELSE 1 END;
            v_pts := v_pts + v_pt_pts;
            v_breakdown := v_breakdown || jsonb_build_object('bonusPlayType', v_pt_pts);
          END IF;
        END IF;

      ELSIF v_reg_scored THEN
        v_pts := v_pts + 1;
        v_breakdown := v_breakdown || '{"regular": 1}';
        IF v_pick.play_type = v_result.first_play_type THEN
          v_pt_pts := CASE WHEN v_result.first_play_type = 'pk' THEN 3 ELSE 1 END;
          v_pts := v_pts + v_pt_pts;
          v_breakdown := v_breakdown || jsonb_build_object('playType', v_pt_pts);
        END IF;
      END IF;

      v_pts := LEAST(v_pts, 8);
    END IF;

    UPDATE picks SET pts = v_pts, breakdown = v_breakdown, scored = true
    WHERE id = v_pick.id;
  END LOOP;
END;
$$;

-- ============================================================
-- 6. REALTIME — enable publication for live updates
-- ============================================================

-- Add tables to the realtime publication
-- (In Supabase dashboard: Database → Replication → enable for these tables)
-- Or run:
ALTER PUBLICATION supabase_realtime ADD TABLE
  public.games,
  public.results,
  public.picks,
  public.notifications;

-- ============================================================
-- SETUP NOTES
-- ============================================================
-- After running this schema:
--
-- 1. In Supabase Dashboard → Authentication → Settings:
--    • Disable "Email Confirmation" for easy local testing
--      (or keep enabled and handle confirmation in prod)
--
-- 2. In Authentication → URL Configuration:
--    • Set Site URL to wherever you host the app
--
-- 3. In Authentication → Providers:
--    • Email provider is enabled by default — no changes needed
--
-- 4. In your index.html, fill in:
--    const SUPABASE_URL  = 'https://xxxx.supabase.co'
--    const SUPABASE_ANON_KEY = 'eyJ...'
--    (find these in Project Settings → API)
--
-- 5. In Database → Replication, confirm the four tables above
--    have Realtime enabled (INSERT + UPDATE + DELETE).
-- ============================================================
