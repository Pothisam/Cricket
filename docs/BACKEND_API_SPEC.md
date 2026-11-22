# Cricket Scorer: Backend API and Database Specification

Audience: the backend developer who will build the database and REST API for the Flutter app **Cricket Scorer** (`com.pothi.cricket`).

Today the app stores everything on the device (SharedPreferences) and signs users in with Firebase Auth. This document describes the server that replaces and extends that: user accounts, cloud sync of teams, players and matches, and push notifications through Firebase Cloud Messaging (FCM).

Firebase project: `cricket-run-notification` (project number `592739044483`).

---

## 1. Conventions

| Item | Rule |
|---|---|
| Base URL | `https://<host>/api/v1` (to be supplied) |
| Format | JSON, UTF-8, `Content-Type: application/json` |
| Auth | `Authorization: Bearer <Firebase ID token>` on every endpoint except `/health`. The server verifies it with the **Firebase Admin SDK** (`verifyIdToken`). Never trust a user id sent in the body. |
| IDs | Strings. The app generates ids offline (`newId()`: a microsecond timestamp plus a counter). The server **must accept client-supplied ids** so offline-created data syncs without id remapping. The server may also generate UUIDs when `id` is omitted. |
| Dates | ISO-8601 UTC strings (`2026-11-22T10:15:00.000Z`) |
| Ownership | Every teams, players and matches row belongs to one `user_id`. A user can only read and write their own rows (unless shared, see section 8). |
| Naming | camelCase in JSON, snake_case in SQL |
| Idempotency | `PUT` upserts by id, so retries are safe. |
| Soft delete | Use `deleted_at` so deletes can sync to other devices. |

### Standard error body
```json
{ "error": { "code": "VALIDATION_ERROR", "message": "teamAId is required", "details": [{ "field": "teamAId", "issue": "required" }] } }
```
| HTTP | code | When |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Bad or missing field |
| 401 | `UNAUTHENTICATED` | Missing, invalid or expired token |
| 403 | `FORBIDDEN` | Row belongs to another user |
| 404 | `NOT_FOUND` | Unknown id |
| 409 | `CONFLICT` | Version conflict (see section 9) |
| 429 | `RATE_LIMITED` | Too many requests |
| 500 | `SERVER_ERROR` | Unexpected |

### Standard list envelope
```json
{ "items": [ ... ], "nextCursor": "opaque-or-null" }
```
Query params for lists: `limit` (default 50, max 200), `cursor`, `updatedSince` (ISO date, used for incremental sync).

---

## 2. Enumerations (exact string values the app sends)

| Enum | Values |
|---|---|
| `PlayerRole` | `batter`, `bowler`, `allRounder`, `wicketKeeper` |
| `battingStyle` | `Right-hand bat`, `Left-hand bat` |
| `bowlingStyle` | `None`, `Right-arm fast`, `Right-arm medium`, `Right-arm off spin`, `Right-arm leg spin`, `Left-arm fast`, `Left-arm medium`, `Left-arm orthodox`, `Left-arm chinaman` |
| `ExtraType` | `none`, `wide`, `noBall`, `bye`, `legBye` |
| `WicketType` | `bowled`, `caught`, `lbw`, `runOut`, `stumped`, `hitWicket` |
| `ShotDirection` | `straight`, `midOff`, `cover`, `point`, `thirdMan`, `fineLeg`, `squareLeg`, `midWicket`, `midOn` |
| `ShotLoft` | `ground`, `lofted`, `aerial` |
| `MatchStatus` | `live`, `completed`, `abandoned` |
| `BallOutcome` (derived, not stored) | `dot`, `runs`, `four`, `six`, `wide`, `noBall`, `bye`, `legBye`, `wicket` |
| `platform` (device) | `android`, `ios`, `web` |

Store enums as `VARCHAR` with a CHECK constraint, or as native enums. Do not use numeric codes, because the app serializes the names.

---

## 3. Database schema

SQL below uses PostgreSQL syntax. Adapt it to MySQL or SQL Server if needed.

### 3.1 `users`
```sql
CREATE TABLE users (
  id               VARCHAR(64) PRIMARY KEY,        -- Firebase UID
  email            VARCHAR(255) UNIQUE,            -- null for phone-only users
  phone_number     VARCHAR(20)  UNIQUE,            -- E.164, e.g. +919876543210
  display_name     VARCHAR(120),
  photo_url        TEXT,
  auth_provider    VARCHAR(20) NOT NULL,           -- 'google.com' | 'phone'
  email_verified   BOOLEAN DEFAULT FALSE,
  is_active        BOOLEAN DEFAULT TRUE,
  last_login_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);
```
Link a user who signs in with both Google and phone to one row. Match on email or phone, or use Firebase account linking.

### 3.2 `user_devices` (FCM tokens)
```sql
CREATE TABLE user_devices (
  id               BIGSERIAL PRIMARY KEY,
  user_id          VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token        TEXT NOT NULL UNIQUE,
  device_id        VARCHAR(128),                   -- stable per-install id from the app
  platform         VARCHAR(10) NOT NULL,           -- android | ios | web
  device_model     VARCHAR(120),
  os_version       VARCHAR(40),
  app_version      VARCHAR(20),
  locale           VARCHAR(10),
  notifications_enabled BOOLEAN DEFAULT TRUE,      -- OS-level permission state reported by the app
  is_active        BOOLEAN DEFAULT TRUE,           -- false after logout or FCM UNREGISTERED
  last_seen_at     TIMESTAMPTZ DEFAULT now(),
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_devices_user ON user_devices(user_id) WHERE is_active;
```
A token can move between users (shared phone). On register, **if the token already exists, reassign it to the new user** and set `is_active = true`.

### 3.3 `teams`
```sql
CREATE TABLE teams (
  id          VARCHAR(64) NOT NULL,
  user_id     VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        VARCHAR(80)  NOT NULL,
  short_name  VARCHAR(8)   NOT NULL,
  color_index INT NOT NULL DEFAULT 0,
  version     INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  deleted_at  TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);
```

### 3.4 `players`
```sql
CREATE TABLE players (
  id            VARCHAR(64) NOT NULL,
  user_id       VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          VARCHAR(120) NOT NULL,
  role          VARCHAR(20)  NOT NULL DEFAULT 'batter',
  batting_style VARCHAR(30)  NOT NULL DEFAULT 'Right-hand bat',
  bowling_style VARCHAR(30)  NOT NULL DEFAULT 'None',
  version       INT NOT NULL DEFAULT 1,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  deleted_at    TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);
```

### 3.5 `team_players` (squad membership; the app's `Team.playerIds`)
```sql
CREATE TABLE team_players (
  user_id    VARCHAR(64) NOT NULL,
  team_id    VARCHAR(64) NOT NULL,
  player_id  VARCHAR(64) NOT NULL,
  sort_order INT DEFAULT 0,
  PRIMARY KEY (user_id, team_id, player_id),
  FOREIGN KEY (user_id, team_id)   REFERENCES teams(user_id, id)   ON DELETE CASCADE,
  FOREIGN KEY (user_id, player_id) REFERENCES players(user_id, id) ON DELETE CASCADE
);
```

### 3.6 `matches`
Team and player names are **snapshots**. A match must stay readable after a team or player is edited or deleted, so there are no foreign keys to `teams` or `players` here.
```sql
CREATE TABLE matches (
  id               VARCHAR(64) NOT NULL,
  user_id          VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_a_id        VARCHAR(64) NOT NULL,
  team_b_id        VARCHAR(64) NOT NULL,
  team_a_name      VARCHAR(80) NOT NULL,
  team_b_name      VARCHAR(80) NOT NULL,
  team_a_short     VARCHAR(8)  NOT NULL,
  team_b_short     VARCHAR(8)  NOT NULL,
  overs            INT NOT NULL,                     -- overs per innings
  toss_winner_id   VARCHAR(64) NOT NULL,
  elected_to_bat   BOOLEAN NOT NULL,
  match_date       TIMESTAMPTZ NOT NULL,
  venue            VARCHAR(200) DEFAULT '',
  status           VARCHAR(12) NOT NULL DEFAULT 'live',  -- live|completed|abandoned
  winner_id        VARCHAR(64),
  result_text      VARCHAR(255) DEFAULT '',
  visibility       VARCHAR(10) NOT NULL DEFAULT 'private', -- private|link|public
  share_code       VARCHAR(16) UNIQUE,                    -- for live-follow links
  version          INT NOT NULL DEFAULT 1,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  deleted_at       TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX idx_matches_status ON matches(user_id, status, match_date DESC);
```

### 3.7 `match_players` (playing XI and name snapshot; the app's `teamAPlayers`, `teamBPlayers`, `playerNames`)
```sql
CREATE TABLE match_players (
  user_id      VARCHAR(64) NOT NULL,
  match_id     VARCHAR(64) NOT NULL,
  player_id    VARCHAR(64) NOT NULL,
  team_id      VARCHAR(64) NOT NULL,             -- team_a_id or team_b_id
  player_name  VARCHAR(120) NOT NULL,            -- snapshot
  batting_order INT,
  PRIMARY KEY (user_id, match_id, player_id),
  FOREIGN KEY (user_id, match_id) REFERENCES matches(user_id, id) ON DELETE CASCADE
);
```

### 3.8 `innings`
```sql
CREATE TABLE innings (
  user_id          VARCHAR(64) NOT NULL,
  match_id         VARCHAR(64) NOT NULL,
  innings_no       INT NOT NULL,                  -- 1, 2 (3, 4 reserved)
  batting_team_id  VARCHAR(64) NOT NULL,
  bowling_team_id  VARCHAR(64) NOT NULL,
  striker_id       VARCHAR(64),                   -- current state; null = must be chosen
  non_striker_id   VARCHAR(64),
  bowler_id        VARCHAR(64),
  completed        BOOLEAN NOT NULL DEFAULT FALSE,
  -- denormalized totals, recomputed whenever balls change (see section 6)
  total_runs       INT NOT NULL DEFAULT 0,
  wickets          INT NOT NULL DEFAULT 0,
  legal_balls      INT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, match_id, innings_no),
  FOREIGN KEY (user_id, match_id) REFERENCES matches(user_id, id) ON DELETE CASCADE
);
```

### 3.9 `balls` (one row per delivery, the core table)
```sql
CREATE TABLE balls (
  user_id          VARCHAR(64) NOT NULL,
  match_id         VARCHAR(64) NOT NULL,
  innings_no       INT NOT NULL,
  seq              INT NOT NULL,                  -- 0-based position in the innings; ordering key
  striker_id       VARCHAR(64) NOT NULL,
  non_striker_id   VARCHAR(64) NOT NULL,
  bowler_id        VARCHAR(64) NOT NULL,
  runs             INT NOT NULL DEFAULT 0,        -- runs off the bat
  extra            VARCHAR(10) NOT NULL DEFAULT 'none',
  extra_runs       INT NOT NULL DEFAULT 0,        -- includes the 1-run penalty for wide/noBall
  wicket           VARCHAR(12),                   -- WicketType or null
  out_player_id    VARCHAR(64),
  fielder_id       VARCHAR(64),
  shot_direction   VARCHAR(12),                   -- ShotDirection or null
  shot_path        JSONB,                         -- [[x,y],[x,y],...] or null
  loft             VARCHAR(8),                    -- ShotLoft or null
  created_at       TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, match_id, innings_no, seq),
  FOREIGN KEY (user_id, match_id, innings_no)
    REFERENCES innings(user_id, match_id, innings_no) ON DELETE CASCADE
);
```
Rules the server can validate or derive (the app computes the same):
- `legal` = `extra NOT IN ('wide','noBall')`
- `total_runs` for the ball = `runs + extra_runs`
- Innings `legal_balls` = count of legal balls. `total_runs` = sum of ball totals. `wickets` = count of balls where `wicket IS NOT NULL`.
- Bowler is charged `runs + (legal ? 0 : extra_runs)`. A wicket counts for the bowler unless `wicket = 'runOut'`.
- `shot_path` coordinates are in ground units: radius 1, +y towards the bowler. Store them as given.

### 3.10 `notifications` (log, also the in-app inbox)
```sql
CREATE TABLE notifications (
  id            BIGSERIAL PRIMARY KEY,
  user_id       VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          VARCHAR(30) NOT NULL,       -- see section 7.2
  title         VARCHAR(160) NOT NULL,
  body          VARCHAR(500) NOT NULL,
  data          JSONB,                      -- e.g. {"matchId":"...","inningsNo":1}
  device_id     BIGINT REFERENCES user_devices(id) ON DELETE SET NULL,  -- null = all devices
  fcm_message_id VARCHAR(200),
  status        VARCHAR(12) NOT NULL DEFAULT 'queued',  -- queued|sent|failed
  error         VARCHAR(255),
  read_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now(),
  sent_at       TIMESTAMPTZ
);
CREATE INDEX idx_notif_user ON notifications(user_id, created_at DESC);
```

### 3.11 `notification_preferences`
```sql
CREATE TABLE notification_preferences (
  user_id        VARCHAR(64) PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  login_alerts   BOOLEAN DEFAULT TRUE,
  match_start    BOOLEAN DEFAULT TRUE,
  boundaries     BOOLEAN DEFAULT TRUE,   -- fours and sixes
  wickets        BOOLEAN DEFAULT TRUE,
  milestones     BOOLEAN DEFAULT TRUE,   -- 50 / 100
  innings_end    BOOLEAN DEFAULT TRUE,
  match_result   BOOLEAN DEFAULT TRUE,
  quiet_hours_start TIME,                -- optional
  quiet_hours_end   TIME,
  updated_at     TIMESTAMPTZ DEFAULT now()
);
```

### 3.12 `match_followers` (live follow and topic subscription)
```sql
CREATE TABLE match_followers (
  match_owner_id VARCHAR(64) NOT NULL,
  match_id       VARCHAR(64) NOT NULL,
  follower_id    VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (match_owner_id, match_id, follower_id)
);
```
Only needed for the sharing and following feature in section 8.

---

## 4. Authentication endpoints

### 4.1 `POST /auth/session`: call after every successful sign-in
The app calls this immediately after Firebase sign-in succeeds (Google or phone). It is the **login hook**: it creates or updates the user, registers the FCM token, and **triggers the login notification**.

Request:
```json
{
  "fcmToken": "dQw4w9WgXcQ:APA91b...",
  "deviceId": "9f1c2e7a-...",
  "platform": "android",
  "deviceModel": "Pixel 8",
  "osVersion": "Android 15",
  "appVersion": "1.0.0+1",
  "locale": "en_IN",
  "notificationsEnabled": true
}
```
Server steps:
1. Verify the Bearer ID token. Read `uid`, `email`, `phone_number`, `name`, `picture` and `firebase.sign_in_provider` from the decoded token.
2. Upsert `users` (set `last_login_at = now()`).
3. Upsert `user_devices` by `fcm_token` (reassign to this user, `is_active = true`, `last_seen_at = now()`).
4. If this is a new user, create the default `notification_preferences` row.
5. Send the login notification (section 7.3).

Response `200`:
```json
{
  "user": {
    "id": "uid123",
    "email": "pothi@example.com",
    "phoneNumber": null,
    "displayName": "Pothi",
    "photoUrl": "https://...",
    "authProvider": "google.com",
    "createdAt": "2026-11-22T10:15:00.000Z",
    "lastLoginAt": "2026-11-22T10:15:00.000Z"
  },
  "isNewUser": true,
  "device": { "id": 42, "platform": "android", "registeredAt": "2026-11-22T10:15:00.000Z" },
  "preferences": { "loginAlerts": true, "matchStart": true, "boundaries": true, "wickets": true, "milestones": true, "inningsEnd": true, "matchResult": true }
}
```

### 4.2 `POST /auth/logout`
Called before the app signs out of Firebase. Marks this device inactive so the user stops getting pushes on it.

Request: `{ "fcmToken": "..." }`. Response: `204`.

### 4.3 `GET /me`
Returns the same `user` object as in 4.1.

### 4.4 `PATCH /me`
Request (all optional): `{ "displayName": "Pothi", "photoUrl": "https://..." }`. Response: the updated `user`.

### 4.5 `DELETE /me`
Deletes the account and all of its data (cascade), and deletes the Firebase user. Response: `204`. Required by Google Play and the App Store.

---

## 5. Device and FCM token endpoints

The FCM token changes when the app is reinstalled, data is cleared, or Firebase rotates it. The app listens to `onTokenRefresh` and calls 5.1.

### 5.1 `PUT /devices/token`: register or refresh
Request:
```json
{
  "fcmToken": "new-token",
  "previousToken": "old-token-or-null",
  "deviceId": "9f1c2e7a-...",
  "platform": "android",
  "deviceModel": "Pixel 8",
  "osVersion": "Android 15",
  "appVersion": "1.0.0+1",
  "locale": "en_IN",
  "notificationsEnabled": true
}
```
Behaviour: upsert by `fcm_token`. If `previousToken` is sent, deactivate or delete that row. Response `200`:
```json
{ "id": 42, "fcmToken": "new-token", "platform": "android", "isActive": true, "lastSeenAt": "2026-11-22T10:20:00.000Z" }
```

### 5.2 `GET /devices`
Lists the user's active devices (for a "where you're signed in" screen).
```json
{ "items": [ { "id": 42, "platform": "android", "deviceModel": "Pixel 8", "appVersion": "1.0.0+1", "lastSeenAt": "...", "isCurrent": true } ] }
```

### 5.3 `DELETE /devices/{id}`
Removes a device. Response `204`.

### 5.4 `PATCH /devices/{id}`
Request: `{ "notificationsEnabled": false }`. Used when the user denies or revokes the OS permission. Response: the device.

---

## 6. Data endpoints (teams, players, matches)

All `PUT` calls are upserts by id and return the saved object. `DELETE` returns `204` and soft-deletes. List endpoints exclude soft-deleted rows unless `includeDeleted=true` (the sync client uses this).

### 6.1 Teams

`GET /teams` returns:
```json
{ "items": [
  { "id": "17321...0", "name": "Chennai Kings", "shortName": "CSK", "colorIndex": 2,
    "playerIds": ["p1", "p2", "p3"], "version": 3,
    "createdAt": "2026-11-20T08:00:00.000Z", "updatedAt": "2026-11-22T09:00:00.000Z" }
], "nextCursor": null }
```
`GET /teams/{id}` returns one team object.
`PUT /teams/{id}`: request body is the same shape as the object above (`id`, `name`, `shortName`, `colorIndex`, `playerIds`). It replaces the `team_players` rows. Response: the team.
`DELETE /teams/{id}`: soft delete. It does **not** delete players or matches.

### 6.2 Players

`GET /players` returns:
```json
{ "items": [
  { "id": "p1", "name": "Ravi Kumar", "role": "allRounder",
    "battingStyle": "Right-hand bat", "bowlingStyle": "Right-arm off spin",
    "version": 1, "updatedAt": "2026-11-22T09:00:00.000Z" }
], "nextCursor": null }
```
`GET /players/{id}`, `PUT /players/{id}` (body: `id`, `name`, `role`, `battingStyle`, `bowlingStyle`) and `DELETE /players/{id}` work as above. Deleting a player also removes them from `team_players`. Matches are unaffected because they keep a name snapshot.

### 6.3 Matches

#### Full match object (the exact JSON the app already produces and consumes)
```json
{
  "id": "17321...55",
  "teamAId": "t1", "teamBId": "t2",
  "teamAName": "Chennai Kings", "teamBName": "Mumbai Stars",
  "teamAShort": "CSK", "teamBShort": "MI",
  "overs": 20,
  "tossWinnerId": "t1",
  "electedToBat": true,
  "teamAPlayers": ["p1", "p2", "p3"],
  "teamBPlayers": ["p12", "p13", "p14"],
  "playerNames": { "p1": "Ravi Kumar", "p12": "Arun S" },
  "date": "2026-11-22T10:00:00.000Z",
  "venue": "Chepauk",
  "status": "live",
  "winnerId": null,
  "resultText": "",
  "innings": [
    {
      "battingTeamId": "t1",
      "bowlingTeamId": "t2",
      "striker": "p1",
      "nonStriker": "p2",
      "bowler": "p12",
      "completed": false,
      "balls": [
        {
          "striker": "p1", "nonStriker": "p2", "bowler": "p12",
          "runs": 4, "extra": "none", "extraRuns": 0,
          "wicket": null, "out": null, "fielder": null,
          "shotDirection": "cover",
          "shotPath": [[0.0, 0.0], [0.4, 0.5], [0.8, 0.9]],
          "loft": "ground"
        },
        {
          "striker": "p1", "nonStriker": "p2", "bowler": "p12",
          "runs": 0, "extra": "wide", "extraRuns": 1,
          "wicket": null, "out": null, "fielder": null,
          "shotDirection": null, "shotPath": null, "loft": null
        }
      ]
    }
  ]
}
```
The server accepts and returns this shape (it is the app's `CricketMatch.toJson()`), and maps it onto the tables in 3.6 to 3.9. The order of `innings[]` and `balls[]` is significant: `innings_no = index + 1` and `seq = index`. Derived fields (`target`, totals, `legalBalls`) may also be returned but are ignored on input.

Endpoints:

| Method | Path | Purpose |
|---|---|---|
| GET | `/matches` | List. Filters: `status=live\|completed\|abandoned`, `updatedSince`, `limit`, `cursor`. By default returns **summaries**. Add `?full=true` for full objects. |
| GET | `/matches/{id}` | Full match object |
| PUT | `/matches/{id}` | Upsert the entire match. Used for initial sync and for completing a match. |
| DELETE | `/matches/{id}` | Soft delete |

**Summary item** (for the Matches tab list; avoids sending every ball):
```json
{
  "id": "17321...55", "status": "live", "date": "2026-11-22T10:00:00.000Z", "venue": "Chepauk",
  "overs": 20,
  "teamA": { "id": "t1", "name": "Chennai Kings", "short": "CSK" },
  "teamB": { "id": "t2", "name": "Mumbai Stars",  "short": "MI" },
  "tossText": "Chennai Kings won the toss and chose to bat",
  "innings": [
    { "inningsNo": 1, "battingTeamId": "t1", "runs": 142, "wickets": 6, "legalBalls": 120, "completed": true },
    { "inningsNo": 2, "battingTeamId": "t2", "runs": 88,  "wickets": 3, "legalBalls": 66,  "completed": false }
  ],
  "winnerId": null, "resultText": "", "updatedAt": "2026-11-22T11:00:00.000Z"
}
```

#### Live-scoring endpoints (incremental)
Re-uploading a whole match on every ball is wasteful, and these endpoints are also where the live notifications are triggered (section 7). The app uses them while a match is live.

**`POST /matches/{id}/innings`**: start an innings
```json
{ "inningsNo": 1, "battingTeamId": "t1", "bowlingTeamId": "t2" }
```
Response `201`: the innings object (without balls). If `inningsNo` is 1, set the match to `live`. This triggers the **match-start** notification.

**`PATCH /matches/{id}/innings/{inningsNo}`**: update the crease state or complete the innings
```json
{ "striker": "p1", "nonStriker": "p2", "bowler": "p12", "completed": false }
```
All fields are optional. When `completed` becomes `true`, this triggers the **innings-end** notification.

**`POST /matches/{id}/innings/{inningsNo}/balls`**: record one ball
Request body is one ball object (shape as above) plus the expected position for safe retries:
```json
{
  "seq": 37,
  "striker": "p1", "nonStriker": "p2", "bowler": "p12",
  "runs": 6, "extra": "none", "extraRuns": 0,
  "wicket": null, "out": null, "fielder": null,
  "shotDirection": "midWicket", "shotPath": [[0,0],[-0.5,0.6]], "loft": "aerial"
}
```
Response `201`:
```json
{
  "ball": { "...": "as sent", "seq": 37 },
  "innings": { "inningsNo": 1, "runs": 98, "wickets": 3, "legalBalls": 37, "completed": false },
  "match": { "status": "live", "resultText": "" }
}
```
- If `seq` already exists with identical content, return `200` (idempotent retry). If it exists with different content, return `409`.
- If `seq` is greater than the current count (a gap), return `409` with `{ "expectedSeq": 36 }`.
- The server recomputes the innings totals.
- This triggers the four, six, wicket and milestone notifications (section 7.2).

**`DELETE /matches/{id}/innings/{inningsNo}/balls/last`**: undo the last ball
Response `200`: `{ "innings": { ...updated totals... } }`. No notification is sent for an undo.

**`POST /matches/{id}/complete`**: finish the match
```json
{ "status": "completed", "winnerId": "t1", "resultText": "Chennai Kings won by 54 runs" }
```
`status` can be `completed` or `abandoned`. `winnerId` is null for a tie, no result or an abandoned match. Response: the full match. This triggers the **match-result** notification.

### 6.4 Bulk sync (first login, offline catch-up)

**`POST /sync/push`**: send everything created or changed offline in one call
```json
{
  "teams":   [ { "...team object..." } ],
  "players": [ { "...player object..." } ],
  "matches": [ { "...full match object..." } ],
  "deleted": { "teams": ["id1"], "players": [], "matches": [] }
}
```
Response `200`:
```json
{ "accepted": { "teams": 3, "players": 33, "matches": 3 }, "rejected": [ { "type": "match", "id": "x", "reason": "VALIDATION_ERROR" } ], "serverTime": "2026-11-22T10:30:00.000Z" }
```

**`GET /sync/pull?since=<ISO date>`**: everything changed since a timestamp
```json
{
  "teams": [ ... ], "players": [ ... ], "matches": [ ...full objects... ],
  "deleted": { "teams": ["id"], "players": [], "matches": [] },
  "serverTime": "2026-11-22T10:30:00.000Z"
}
```
Omit `since` for a full download. The client stores `serverTime` and uses it as the next `since`.

### 6.5 Statistics (optional, phase 2)
The app currently derives these on the device from the balls. Offer them from the server if it is faster:
- `GET /players/{id}/stats` returns batting totals (matches, innings, runs, balls faced, fours, sixes, highest score, average, strike rate, 50s, 100s) and bowling totals (overs, runs, wickets, economy, best figures, average).
- `GET /teams/{id}/stats` returns played, won, lost, tied and no result.

Use the rules in section 3.9 to attribute runs and wickets.

---

## 7. Notifications

### 7.1 Sending (server to FCM)
Use the Firebase Admin SDK (`messaging().send` or `sendEachForMulticast`).
- Android channel id: **`cricket_updates`** (already created in the app).
- Send a `notification` block (title and body) plus a `data` block (strings only) for deep links.
- Tokens that FCM reports as `UNREGISTERED` or `INVALID_ARGUMENT` must be set `is_active = false`.
- Respect `notification_preferences` and the user's quiet hours before sending.
- Log every send in `notifications` (status, `fcm_message_id`, error).

Message shape:
```json
{
  "token": "<fcm_token>",
  "notification": { "title": "SIX!", "body": "Ravi Kumar hits a six. CSK 98/3 (14.1)" },
  "data": { "type": "six", "matchId": "17321...55", "inningsNo": "1", "click_action": "OPEN_MATCH" },
  "android": { "priority": "high", "notification": { "channel_id": "cricket_updates" } }
}
```

### 7.2 Notification types and triggers

| `type` | Trigger | Recipients | Example text |
|---|---|---|---|
| `login` | `POST /auth/session` | the user's **other** active devices (and a welcome for new users on the current device) | "New sign-in: Pixel 8 signed in to your account" |
| `match_start` | first innings created | the match owner and followers | "Match started: CSK vs MI (20 overs)" |
| `four` | ball with `runs = 4`, `extra = none` | owner and followers | "FOUR! Ravi Kumar, CSK 54/1 (6.2)" |
| `six` | ball with `runs = 6`, `extra = none` | owner and followers | "SIX! ..." |
| `wicket` | ball with `wicket != null` | owner and followers | "WICKET! Ravi Kumar b Arun S. CSK 60/2 (7.1)" |
| `milestone` | a batter's total reaches 50 or 100 | owner and followers | "Ravi Kumar reaches 50 (34 balls)" |
| `innings_end` | innings `completed = true` | owner and followers | "Innings break: CSK 142/6. MI need 143" |
| `match_result` | `POST /matches/{id}/complete` | owner and followers | "CSK won by 54 runs" |

Rate-limit the boundary notifications for large matches. The server may batch them, for example a maximum of one per over per match.

The `data.type` value must be one of the strings in the table. The app uses `matchId` to open the right screen when a notification is tapped.

### 7.3 Login notification (details)
On `POST /auth/session`:
1. **New user** (`isNewUser = true`): send "Welcome to Cricket Scorer" to the registering device.
2. **Returning user**: if `login_alerts` is on, send a `login` notification to all **other** active devices of the same user. Do not send it to the device that just signed in.
3. Skip it if the same `device_id` signed in within the last 10 minutes, to avoid spam.
4. Always insert a row in `notifications` (type `login`), even if the push could not be delivered. It then appears in the inbox.

### 7.4 Notification endpoints

**`GET /notifications`**: the user's inbox. Params: `limit`, `cursor`, `unreadOnly=true`.
```json
{ "items": [
  { "id": 501, "type": "wicket", "title": "WICKET!", "body": "Ravi Kumar b Arun S. CSK 60/2 (7.1)",
    "data": { "matchId": "17321...55", "inningsNo": "1" }, "readAt": null, "createdAt": "2026-11-22T10:42:00.000Z" }
], "unreadCount": 4, "nextCursor": null }
```
**`POST /notifications/{id}/read`**: marks one as read. Response `204`.
**`POST /notifications/read-all`**: marks all as read. Response `204`.
**`DELETE /notifications/{id}`**: Response `204`.

**`GET /notifications/preferences`** and **`PUT /notifications/preferences`**:
```json
{ "loginAlerts": true, "matchStart": true, "boundaries": true, "wickets": true,
  "milestones": true, "inningsEnd": true, "matchResult": true,
  "quietHoursStart": "23:00", "quietHoursEnd": "07:00" }
```

**`POST /notifications/test`**: sends a test push to the caller's own active devices. Useful for QA.
Request: `{ "title": "Test", "body": "Hello" }`. Response: `{ "sent": 1, "failed": 0 }`.

### 7.5 Internal and admin (optional)
**`POST /admin/notifications/broadcast`** (admin role only): `{ "title": "...", "body": "...", "topic": "all" }`.

---

## 8. Sharing and live follow (phase 2, optional)

| Method | Path | Purpose |
|---|---|---|
| POST | `/matches/{id}/share` | Sets `visibility = link` or `public` and returns `{ "shareCode": "AB12CD", "url": "https://.../m/AB12CD" }`. |
| DELETE | `/matches/{id}/share` | Sets the match back to private. |
| GET | `/public/matches/{shareCode}` | No-auth read-only full match object. |
| POST | `/matches/follow` | Request: `{ "shareCode": "AB12CD" }`. Adds a `match_followers` row. |
| DELETE | `/matches/{ownerId}/{id}/follow` | Unfollow. |
| GET | `/following` | Matches the user follows (summary items). |

Followers receive the notifications in section 7.2 for matches they follow.

---

## 9. Sync and conflict rules

- **Source of truth while scoring:** the scorer's device. Live scoring uses the ball endpoints and is append-only, so conflicts are rare.
- **Teams, players, completed matches:** last-writer-wins by `version`. The client sends `version` on `PUT`. If it is lower than the stored `version`, return `409` with the current object so the client can reconcile.
- **Increment** `version` and `updated_at` on every write.
- **Offline use:** the app keeps working offline and later calls `POST /sync/push`. IDs are client-generated, so there is no remapping.
- **First login on a device that already has local data:** the app pushes local data (`/sync/push`), then pulls (`/sync/pull`).

---

## 10. Other endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | No auth. Returns `{ "status": "ok", "time": "..." }`. |
| GET | `/config` | Returns the minimum supported app version and feature flags: `{ "minAppVersion": "1.0.0", "features": { "sharing": false } }`. |
| POST | `/feedback` | Optional: `{ "message": "...", "appVersion": "..." }`. |

---

## 11. Non-functional requirements

- **TLS only.** Verify the Firebase token on every request and cache Google's public keys.
- **Authorization.** Every query is filtered by the token's `uid`.
- **Validation.** Enforce the enums in section 2. `overs` is 1 to 100. `runs` is 0 to 7 per ball. `extraRuns` is 0 to 10. Reject a ball whose `out` player is not part of the match.
- **Size limits.** A match with 20 overs has roughly 120 to 150 balls. A `shotPath` should have at most 50 points.
- **Rate limits.** Roughly 60 requests per minute per user. The ball endpoint needs a higher limit during live scoring.
- **Audit.** `created_at`, `updated_at` and `deleted_at` on every table.
- **Backups.** Daily database backups.
- **Privacy.** The user's phone and email are personal data. Support account deletion (4.5). Do not log FCM tokens or ID tokens in plain text.
- **Firebase.** The server needs a **service account key** (Firebase Console → Project settings → Service accounts → Generate new private key). Keep it in a secret manager, never in the repository.

---

## 12. Endpoint summary

| # | Method | Path | Section |
|---|---|---|---|
| 1 | POST | `/auth/session` | 4.1 |
| 2 | POST | `/auth/logout` | 4.2 |
| 3 | GET / PATCH / DELETE | `/me` | 4.3 to 4.5 |
| 4 | PUT | `/devices/token` | 5.1 |
| 5 | GET | `/devices` | 5.2 |
| 6 | PATCH / DELETE | `/devices/{id}` | 5.3, 5.4 |
| 7 | GET | `/teams`, `/teams/{id}` | 6.1 |
| 8 | PUT / DELETE | `/teams/{id}` | 6.1 |
| 9 | GET | `/players`, `/players/{id}` | 6.2 |
| 10 | PUT / DELETE | `/players/{id}` | 6.2 |
| 11 | GET | `/matches`, `/matches/{id}` | 6.3 |
| 12 | PUT / DELETE | `/matches/{id}` | 6.3 |
| 13 | POST | `/matches/{id}/innings` | 6.3 |
| 14 | PATCH | `/matches/{id}/innings/{n}` | 6.3 |
| 15 | POST | `/matches/{id}/innings/{n}/balls` | 6.3 |
| 16 | DELETE | `/matches/{id}/innings/{n}/balls/last` | 6.3 |
| 17 | POST | `/matches/{id}/complete` | 6.3 |
| 18 | POST | `/sync/push` | 6.4 |
| 19 | GET | `/sync/pull` | 6.4 |
| 20 | GET | `/notifications` | 7.4 |
| 21 | POST | `/notifications/{id}/read`, `/notifications/read-all` | 7.4 |
| 22 | DELETE | `/notifications/{id}` | 7.4 |
| 23 | GET / PUT | `/notifications/preferences` | 7.4 |
| 24 | POST | `/notifications/test` | 7.4 |
| 25 | GET | `/health`, `/config` | 10 |
| 26 | Optional | stats (6.5), sharing and follow (8), admin broadcast (7.5) | |

---

## 13. What the Flutter app will do (for context)

1. After Google or OTP sign-in, call `POST /auth/session` with the FCM token and device info. The app already obtains the token in `NotificationService` and prints it; it does not send it anywhere yet.
2. On `onTokenRefresh`, call `PUT /devices/token`.
3. On sign-out, call `POST /auth/logout`.
4. Replace the local repositories with API-backed ones, keeping the local copy as a cache. The abstract `TeamRepository`, `PlayerRepository` and `MatchRepository` already exist for this.
5. While scoring, post each ball to the ball endpoint. On undo, call the delete-last endpoint.
6. Handle notification taps by reading `data.matchId` and opening that match.

None of the app-side API calls exist yet. Once the backend is ready, the app work is a separate task.
