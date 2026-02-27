# FGOTG — First Goal of the Game

A hockey prediction league where you guess the first goal scorer of your favourite NHL team's games. Play head-to-head with friends over a full season, earn points for correct picks, and claim the throne.

---

## How It Works

Before each game's pick deadline, every player submits three things:

| Pick | Description | Max Points |
|---|---|---|
| **Regular Pick** | The player you think scores the first goal | 1 pt |
| **Darkhorse Pick** | A surprise scorer (higher reward, different from Regular) | 3 pts |
| **— or — Shutout Call** | Predict no goals scored | 5 pts |
| **Play Type** | Even Strength · Power Play · Penalty Kill | +1 pt (PK = +3 pts) |

**Maximum: 8 points per game.**

### Scoring Breakdown

- Darkhorse scores first → **3 pts** + play type bonus
  - If darkhorse scored first and your Regular scores *second* → **+1 pt** bonus + play type
- Regular scores first → **1 pt** + play type bonus
- Correct play type → **+1 pt** (Penalty Kill shorthanded goal → **+3 pts**)
- Correct shutout call → **5 pts**
- Wrong shutout call → **0 pts**

### Tiebreakers (in order)
1. Most shutouts correctly called
2. Most darkhorse picks correct
3. Most games participated in

---

## Tech Stack

- **Frontend**: Single HTML file — no build tools, no framework, vanilla JS
- **Backend**: [Supabase](https://supabase.com) (Postgres + Auth + Realtime)
- **Data**: NHL public schedule API (`api-web.nhle.com`) for automatic game import
- **Hosting**: Any static host (Netlify, Vercel, GitHub Pages, etc.)

---

## Setup

### 1. Supabase project

1. Create a free project at [supabase.com](https://supabase.com)
2. Open **SQL Editor → New query** and run the contents of `schema.sql`
3. In **Authentication → Settings**, optionally disable email confirmation for easier local testing
4. In **Database → Replication**, confirm that `games`, `results`, `picks`, and `notifications` have Realtime enabled

### 2. Configure the app

Open `index.html` and fill in your project credentials near the top of the `<script>` block:

```js
const SUPABASE_URL      = 'https://xxxxxxxxxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJ...your_anon_key...';
```

Both values are found in **Project Settings → API**.

### 3. Open the file

Open `index.html` in any browser. No server required for local testing.

For public access, deploy the single file to any static host:

```bash
# Netlify (drag-and-drop deploy or CLI)
netlify deploy --dir . --prod

# Vercel
vercel --prod

# GitHub Pages — push to a repo and enable Pages on the main branch
```

---

## Features

### Player side
- Sign up with username + email
- Choose your NHL team and join or create a league
- Submit picks per game before the deadline
- Live countdown to pick deadline
- View your score breakdown after results are posted
- Season standings with podium, tiebreaker sorting
- Full game history
- In-app notifications (new games, results posted)

### Admin side
- Import the full NHL schedule with one click (via NHL public API)
- Add / edit / delete games manually
- Enter game results (first scorer, play type, optional second scorer)
- Picks are automatically scored when results are saved
- Manage team roster (add/remove players)
- Mark players as darkhorse-ineligible
- Season management (start, archive, rename)
- Promote / remove league admins

---

## Game Rules Summary

- Picks lock automatically at each game's deadline
- Darkhorse and Regular picks must be **different** players
- Players marked **DH Ineligible** cannot be selected as a Darkhorse pick
- If a shutout is called and the game has goals → **0 pts**
- If goals are scored and a shutout was predicted → **0 pts**
- Points are capped at **8 per game**

---

## Schema Overview

```
profiles          — user display name, team, email
leagues           — league name + team affiliation
league_members    — membership + role (admin / member)
seasons           — named seasons per league
games             — scheduled games with puck drop + deadline
picks             — user submissions per game
results           — first/second goal scorer + play type
league_players    — roster of eligible scorers
ineligible_players — darkhorse-restricted players
notifications     — in-app messages broadcast to league members
```

Row Level Security ensures users can only read/write their own data. Admin operations are guarded by `is_league_admin()` helper functions.

---

## License

MIT
