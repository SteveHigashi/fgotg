# FGOTG — First Goal of the Game

A hockey prediction league where you guess the first goal scorer of your favourite NHL team's games. Play head-to-head with friends over a full season, earn points for correct picks, and claim the throne.

> **Built entirely through prompt engineering** — this app was designed, architected, and iterated using Claude Code (AI CLI). No boilerplate, no starter templates. Every feature was described in plain language and refined through conversation.

---

## How It Works

Before each game's pick deadline, every player submits:

| Pick | Description | Max Points |
|---|---|---|
| **GS — Goal Scorer** | Who you think scores first | 1 pt |
| **DH — Darkhorse** | Surprise scorer (must differ from GS) | 3 pts |
| **— or — Shutout Call** | Predict no goals scored | 5 pts |
| **Play Type (each pick)** | Even Strength · Power Play · Penalty Kill | +1 pt (PK = +3 pts) |

**Maximum: 8 points per game.**

### Scoring
- Darkhorse scores first → **3 pts** + play type bonus
  - If darkhorse scored first and GS scores *second* → **+1 pt** bonus
- Goal Scorer scores first → **1 pt** + play type bonus
- Correct play type → **+1 pt** (Penalty Kill → **+3 pts**)
- Correct shutout call → **5 pts** · Wrong call → **0 pts**

### Tiebreakers
1. Most shutouts correctly called
2. Most darkhorse picks correct
3. Most games participated in

---

## Build Process — Prompt Engineering Showcase

This project was built through iterative AI-assisted development over multiple sessions. Here's what was tackled entirely through prompting:

### Architecture decisions prompted
- Single-file SPA (no build tools, no framework) — keeps deployment dead simple
- Supabase (Postgres + Auth + Realtime) as backend — free tier, zero DevOps
- Hash-based routing, global state object, localStorage-first then migrated to DB
- Row Level Security policies written from plain-English descriptions of access rules

### Features built through prompting
- Full scoring engine (`Score.calc`) with tiebreaker logic
- Real-time leaderboard with podium display
- Per-player play type prediction (GS and DH each get their own ES/PP/PK)
- Pick editing and deletion before game deadline
- Forgot password flow with email reset link
- Social login hooks (Google, Twitter/X, Facebook) — deferred but scaffolded
- Admin panel: schedule import via NHL public API, result entry, roster management
- Supabase Realtime subscriptions for live score/game updates
- CORS proxy for local development

### Debugging done through prompting
- Diagnosed supabase-js v2 internal auth lock contention causing login hangs
- Traced CORS preflight blocking in Chrome vs Safari
- Fixed compressed response (gzip) passthrough in local proxy
- Resolved RLS policy gaps and trigger failures via Supabase Management API

### Schema designed through prompting
10 tables, 6 stored functions, 34 RLS policies — all described in plain English and generated as production-ready SQL.

---

## Tech Stack

- **Frontend**: Single HTML file — vanilla JS, no framework, no build step
- **Backend**: [Supabase](https://supabase.com) (Postgres + Auth + Realtime)
- **Data**: NHL public API (`api-web.nhle.com`) for schedule import
- **Hosting**: Any static host (Netlify, Vercel, GitHub Pages)

---

## Setup

### 1. Supabase project
1. Create a free project at [supabase.com](https://supabase.com)
2. Run `schema.sql` in the SQL Editor
3. Disable email confirmation in **Authentication → Settings** for easier testing
4. Enable Realtime on `games`, `results`, `picks`, `notifications` tables

### 2. Configure credentials
Edit `index.html` near the top of the `<script>` block:
```js
const SUPABASE_URL      = 'https://xxxxxxxxxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJ...your_anon_key...';
```

### 3. Run locally
```bash
python3 /tmp/fgotg_server.py   # starts dev server + CORS proxy on :8080
# then open http://localhost:8080 in Safari
```

### 4. Deploy
```bash
netlify deploy --dir . --prod   # or Vercel, or GitHub Pages
```

---

## Features

### Player
- Sign up, choose NHL team, join or create a league
- Submit GS + DH picks (each with ES/PP/PK) or call a shutout
- Edit or delete picks before the deadline
- Live countdown to pick deadline
- Score breakdown after results posted
- Season standings with podium + tiebreaker sort
- Full game history and in-app notifications

### Admin
- One-click NHL schedule import
- Manual game add/edit/delete
- Enter results → picks auto-scored via server-side RPC
- Roster management (add/remove players, mark DH-ineligible)
- Season management (start, archive, rename)
- Promote/remove league admins

---

## Schema

```
profiles           — username, team, email
leagues            — league name + team
league_members     — role (admin / member)
seasons            — named seasons per league
games              — puck drop + deadline
picks              — GS + DH + play types + shutout flag
results            — first/second scorer + play type
league_players     — eligible roster
ineligible_players — DH-restricted players
notifications      — broadcast messages
```

RLS ensures users only access their own data. Admin actions guarded by `is_league_admin()` server-side helper.

---

## License

MIT
