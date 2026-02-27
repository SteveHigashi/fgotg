-- ============================================================
-- SUPER ADMIN MIGRATION
-- Run this entire block in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- 1. Add is_super_admin column (safe if already exists)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_super_admin boolean NOT NULL DEFAULT false;

-- 2. Grant super admin to the designated accounts
UPDATE public.profiles
  SET is_super_admin = true
  WHERE email IN ('superadmin@fgotg.com', 'steve@higashi.edu');

-- 3. is_super_admin() helper — SECURITY DEFINER avoids RLS recursion
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT is_super_admin FROM profiles WHERE id = auth.uid()),
    false
  );
$$;

-- 4. toggle_super_admin RPC — only super admins can call this
CREATE OR REPLACE FUNCTION public.toggle_super_admin(target_user_id uuid, new_value boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'Forbidden: super admin access required';
  END IF;
  UPDATE profiles SET is_super_admin = new_value WHERE id = target_user_id;
END;
$$;

-- 5. Update RLS policies to allow super admins -------------------------

-- league_members
DROP POLICY IF EXISTS "lm_select" ON public.league_members;
CREATE POLICY "lm_select" ON public.league_members
  FOR SELECT TO authenticated USING (is_league_member(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "lm_insert" ON public.league_members;
CREATE POLICY "lm_insert" ON public.league_members
  FOR INSERT TO authenticated WITH CHECK (
    is_league_admin(league_id) OR user_id = auth.uid() OR is_super_admin()
  );

DROP POLICY IF EXISTS "lm_update" ON public.league_members;
CREATE POLICY "lm_update" ON public.league_members
  FOR UPDATE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "lm_delete" ON public.league_members;
CREATE POLICY "lm_delete" ON public.league_members
  FOR DELETE TO authenticated USING (
    is_league_admin(league_id) OR user_id = auth.uid() OR is_super_admin()
  );

-- leagues
DROP POLICY IF EXISTS "leagues_update" ON public.leagues;
CREATE POLICY "leagues_update" ON public.leagues
  FOR UPDATE TO authenticated USING (is_league_admin(id) OR is_super_admin());

-- seasons
DROP POLICY IF EXISTS "seasons_select" ON public.seasons;
CREATE POLICY "seasons_select" ON public.seasons
  FOR SELECT TO authenticated USING (is_league_member(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "seasons_insert" ON public.seasons;
CREATE POLICY "seasons_insert" ON public.seasons
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "seasons_update" ON public.seasons;
CREATE POLICY "seasons_update" ON public.seasons
  FOR UPDATE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

-- games
DROP POLICY IF EXISTS "games_select" ON public.games;
CREATE POLICY "games_select" ON public.games
  FOR SELECT TO authenticated USING (is_league_member(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "games_insert" ON public.games;
CREATE POLICY "games_insert" ON public.games
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "games_update" ON public.games;
CREATE POLICY "games_update" ON public.games
  FOR UPDATE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "games_delete" ON public.games;
CREATE POLICY "games_delete" ON public.games
  FOR DELETE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

-- results
DROP POLICY IF EXISTS "results_select" ON public.results;
CREATE POLICY "results_select" ON public.results
  FOR SELECT TO authenticated USING (
    is_league_member((SELECT league_id FROM public.games WHERE id = game_id)) OR is_super_admin()
  );

DROP POLICY IF EXISTS "results_insert" ON public.results;
CREATE POLICY "results_insert" ON public.results
  FOR INSERT TO authenticated WITH CHECK (
    is_league_admin((SELECT league_id FROM public.games WHERE id = game_id)) OR is_super_admin()
  );

DROP POLICY IF EXISTS "results_update" ON public.results;
CREATE POLICY "results_update" ON public.results
  FOR UPDATE TO authenticated USING (
    is_league_admin((SELECT league_id FROM public.games WHERE id = game_id)) OR is_super_admin()
  );

-- league_players
DROP POLICY IF EXISTS "lp_select" ON public.league_players;
CREATE POLICY "lp_select" ON public.league_players
  FOR SELECT TO authenticated USING (is_league_member(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "lp_insert" ON public.league_players;
CREATE POLICY "lp_insert" ON public.league_players
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "lp_delete" ON public.league_players;
CREATE POLICY "lp_delete" ON public.league_players
  FOR DELETE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

-- ineligible_players
DROP POLICY IF EXISTS "ip_select" ON public.ineligible_players;
CREATE POLICY "ip_select" ON public.ineligible_players
  FOR SELECT TO authenticated USING (is_league_member(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "ip_insert" ON public.ineligible_players;
CREATE POLICY "ip_insert" ON public.ineligible_players
  FOR INSERT TO authenticated WITH CHECK (is_league_admin(league_id) OR is_super_admin());

DROP POLICY IF EXISTS "ip_delete" ON public.ineligible_players;
CREATE POLICY "ip_delete" ON public.ineligible_players
  FOR DELETE TO authenticated USING (is_league_admin(league_id) OR is_super_admin());

-- 6. Update server-side RPCs to allow super admins --------------------

CREATE OR REPLACE FUNCTION public.broadcast_notif(
  p_league_id uuid,
  p_message   text,
  p_type      text DEFAULT 'system'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_league_admin(p_league_id) AND NOT is_super_admin() THEN
    RAISE EXCEPTION 'Not authorized: must be league admin or super admin';
  END IF;
  INSERT INTO notifications (user_id, league_id, message, type)
  SELECT user_id, p_league_id, p_message, p_type
  FROM league_members WHERE league_id = p_league_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_league_players(
  p_league_id uuid,
  p_players   text[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_league_admin(p_league_id) AND NOT is_super_admin() THEN
    RAISE EXCEPTION 'Not authorized: must be league admin or super admin';
  END IF;
  DELETE FROM league_players WHERE league_id = p_league_id;
  IF array_length(p_players, 1) IS NOT NULL THEN
    INSERT INTO league_players (league_id, player_name)
    SELECT p_league_id, unnest(p_players);
  END IF;
END;
$$;

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
  SELECT league_id INTO v_league_id FROM games WHERE id = p_game_id;
  IF NOT is_league_admin(v_league_id) AND NOT is_super_admin() THEN
    RAISE EXCEPTION 'Not authorized: must be league admin or super admin';
  END IF;

  SELECT * INTO v_result FROM results WHERE game_id = p_game_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No result found for game %', p_game_id;
  END IF;

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

        IF v_pick.dh_play_type = v_result.first_play_type THEN
          v_pt_pts := CASE WHEN v_result.first_play_type = 'pk' THEN 3 ELSE 1 END;
          v_pts := v_pts + v_pt_pts;
          v_breakdown := v_breakdown || jsonb_build_object('playType', v_pt_pts);
        END IF;

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
