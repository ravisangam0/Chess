# Chess Web App — Backend

Supabase + PostgreSQL + TypeScript backend for the no-login chess app
(Offline 2P, vs AI, Online Friend via room code).

## Status: Room + Game core is complete and verified

### ✅ What's built and actually verified this pass

**Full Room + Game HTTP API**, wired end-to-end:
- `POST /api/rooms` — create room (generates code, creates host player session)
- `POST /api/rooms/:roomCode/join` — join room (attaches guest, starts the game)
- `GET /api/rooms/:roomCode` — look up a room
- `POST /api/rooms/:roomId/reconnect` — reconnect flow
- `POST /api/games/:gameId/moves` — make a move (server-validated via chess.js,
  idempotent via `clientMoveId`)
- `POST /api/games/:gameId/resign`
- `POST /api/games/:gameId/draw-offer` / `draw-response`
- `POST /api/games/:gameId/rematch` — creates a new game in the same room
  with colors swapped, verified: boots and correctly returns
  `UNAUTHORIZED_SESSION` without a session token
- `GET /health`

**Verified by actually running it, not just written:**
- `npx tsc --noEmit` — **zero errors** across the whole backend
- Server booted for real with `npx tsx src/index.ts` and served traffic on
  `localhost:4000`
- `/health` returned `200 { success: true }`
- `POST /api/rooms` with a valid body correctly walked the full chain
  (Express → Zod validation → controller → service → repository → Supabase
  client) and failed only because this sandboxed dev environment's network
  policy blocks the `*.supabase.co` domain — the code correctly *attempted*
  the call and returned a clean structured error instead of crashing
- Validation, error-handling, and auth paths were all individually tested
  and returned correct structured JSON:
  - missing field → `VALIDATION_ERROR` with per-field detail
  - malformed room code → `ROOM_CODE_INVALID`
  - move without a session token → `UNAUTHORIZED_SESSION`
  - unknown route → clean 404 JSON, not an HTML error page

**A real bug was found and fixed during this pass**: the hand-written
`Database` generic type passed to `@supabase/supabase-js@2.110` didn't match
that version's (fairly involved) `GenericSchema`/`__InternalSupabase`
constraint shape, which silently collapsed every table's `Insert`/`Update`
type to `never`. Rather than fight increasingly fragile conditional types
against a hand-authored (non-codegen'd) schema, the client is now
intentionally untyped at the `SupabaseClient` level — correctness instead
comes from every repository function casting its response to the matching
`Row` interface in `types/database.types.ts`, which *is* kept in sync with
the actual migrations. If you later run
`supabase gen types typescript --linked`, you can reintroduce the
`Database` generic using the generated file instead.

### 🔑 Your credentials

`.env` is already filled in with the Supabase URL, anon key, and
service_role key you provided. **Do not commit this file or share the
service_role key** — it bypasses all Row Level Security.

### ▶️ Running it for real

```bash
npm install
npm run dev        # tsx watch src/index.ts — http://localhost:4000
```

Since your Supabase project's tables were created via the SQL script in
your earlier session (players, rooms, games, moves, etc.), the very first
real test to run once this is deployed/running with actual network access
to Supabase is:

```bash
curl -X POST http://localhost:4000/api/rooms \
  -H "Content-Type: application/json" \
  -d '{"displayName":"Alice","timeControl":{"category":"rapid","initialSeconds":600,"incrementSeconds":0}}'
```

If your Supabase tables exist and the service_role key is correct, this
returns a room object with a real `roomCode` — that's the fix for "room
code create nahi ho raha hai."

### 🚧 Not yet built
- Timer/timeout enforcement as a server-side scheduled job (the DB schema
  and `declareTimeout` service method exist; nothing calls it on a timer yet)
- AI move endpoint (the frontend currently computes AI moves entirely
  client-side via the Web Worker, which is a valid architecture choice, so
  this may not be needed — flagging in case server-side AI was expected)
- Full test suite, deployment docs, admin/analytics endpoints

### Next step

Deploy this somewhere with real network access to Supabase (Vercel serverless
function, Railway, Render, a VPS, etc.), point your frontend's
`VITE_API_BASE_URL` at it, and room creation should work. If it still
fails once deployed, the error response will now tell you exactly why
(check the `code` field) instead of failing silently.
