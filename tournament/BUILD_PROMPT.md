# Build Prompt: One-Time Obby Tournament System (Roblox)

> Copy everything below this line into a new AI chat that is connected to Roblox Studio through an MCP server.

---

## Your role

You are a senior Roblox/Luau engineer working **directly inside my open Roblox Studio place** through the Studio MCP server. Your job is to **build, test, and fix** a complete one-time Obby Tournament system, exactly as specified below. You build it, you playtest it, you read the Output for errors, and you fix problems yourself until it works.

**Talk to me in simple Bengali (বাংলা).** Keep messages short. Code, instance names, and comments stay in English.

## Background

- My game is an existing, live Roblox game with its own scripts, gamepasses (some gamepasses give players tools), and shop UIs with purchase buttons.
- I will run a **single tournament, one time only**, and record it for a **YouTube video**. About **100 players** will take part. I will raise the server's max player count myself on the day.
- Everything happens **in the same server** as the main game. The tournament area is a separate map I will design myself, floating in the empty sky away from the main map.
- Players join the game normally and spawn at the main game's spawn. Nobody starts in the tournament area. There is **no registration**: every normal player in the server takes part.
- After the event I want to **delete the whole system in seconds** without breaking my game.

## Hard rules

1. **Isolation (most important).** Put everything in exactly these two folders:
   - `ServerScriptService/Tournament`: all code (server scripts, client LocalScripts, shared ModuleScripts, UI, assets, config).
   - `Workspace/Tournament`: all physical parts (start box area, respawn, checkpoints, finish line, platforms, statue spots, podium).
   At runtime, the server clones whatever the client needs (shared modules, remotes, client scripts inside a `ScreenGui` with `ResetOnSpawn = false` parented to each `PlayerGui`, assets) into a `ReplicatedStorage/Tournament_Runtime` folder that it creates itself. **Do not place anything in StarterGui, StarterPlayerScripts, StarterCharacterScripts or ReplicatedStorage at edit time.** Deleting the two folders must remove the system completely. If something truly cannot work this way, stop and ask me first.
2. **Do not edit, move, or delete any existing script, UI, or part of my game.** Read them only. If a change outside the two folders is unavoidable, ask me first and explain why in Bengali.
3. **Kill switch:** `Config.Enabled` (default `true`). When `false`, nothing in the system runs.
4. **Server-authoritative.** The client only sends requests. The server checks permissions for every request, validates every argument (types, ranges, string lengths, that target players exist), and rate-limits remotes. Checkpoints, finishes, rankings and results are decided **only on the server**. Never trust client positions or client claims.
5. **Text filtering.** Any text typed by staff and shown to other players (announcements, kick reasons) must go through `TextService:FilterStringAsync` before display, as Roblox requires.
6. **Performance for 100 players.** No heavy per-frame server loops. Use events plus debounces. Batch and throttle network updates (for example, broadcast ranking changes at most about once per second, and only when something changed). Disconnect all connections on `PlayerRemoving` and on character removal. No memory leaks.
7. Use `--!strict` Luau where practical, clear module boundaries, and readable names.
8. All tunable values (IDs, timings, sizes, text) live in one `Config` ModuleScript with comments, so I can edit them without reading code.

## Folder layout (suggested)

```
ServerScriptService/Tournament
  Config            (ModuleScript: all settings, documented)
  Server/           (server Scripts and ModuleScripts: roles, state machine, race, ranking, staff, logs, data)
  Client/           (LocalScripts and modules: panel UI, announcements, spectate and cameras, top 10, HUD)
  Shared/           (types, remote names, pure logic such as ranking and permissions)
  Assets/
    CheckpointEffect  (EMPTY placeholder; I will put my own effect here later)
    RewardTool        (placeholder Tool; I will replace it with my own)
    Sounds/           (checkpoint sound, countdown sounds, win sound; use free Roblox sounds as placeholders, IDs in Config)

Workspace/Tournament
  StartBoxArea      (invisible, CanCollide = false, Anchored Part: defines the start box volume)
  RespawnPoint      (Part: where racers respawn after dying)
  Checkpoints/      (Parts named "1", "2", "3", ...; can be invisible)
  FinishLine        (invisible Part)
  WinnerPlatform    (Part: finishers are sent here)
  StatueSpots/      (Parts "1", "2", "3": where the giant winner statues stand)
  Podium/           (Parts "1", "2", "3" at different heights: for the ceremony)
```

Create every Workspace part as a clearly visible placeholder at a sensible spot in the sky, labelled, so I can move and resize them in Studio. **All code must read positions and sizes from these parts at runtime**, never hard-coded. Resizing `StartBoxArea` must automatically resize the generated walls and gate.

## Roles and permissions

Roles, from highest to lowest: **Main Owner > Owner > Admin > Moderator > Recorder > Player**.

- **Main Owner:** the place's creator, detected automatically (`game.CreatorType` / `game.CreatorId`; for a group game, the group owner). Optional extra UserIds in `Config.MainOwnerUserIds`. The Main Owner can never be removed, demoted, kicked, exploded, frozen, or have powers turned off by anyone, including other Owners.
- **Owner:** highest power below Main Owner. Can add or remove staff, change anyone's role, add other Owners, kick staff, and turn individual permissions on or off for a role or for a single person. An Owner can also give a specific person the right to grant permissions.
- **Admin, Moderator, Recorder:** see the permission table.
- **Player:** normal player. Every tournament power acts **only on normal players**. Staff are never affected by Bring All, Free/Freeze, tool stripping, UI hiding, Pause, and so on.
- **Hierarchy rule:** nobody can act on someone with an equal or higher role.

**Staff storage:** the staff list (UserId, role, per-user permission overrides) is saved in a **DataStore**. In the panel, an Owner types a **Username**; the server resolves it to a **UserId** and saves the UserId, so roles survive name changes. Anyone added gets their role automatically the next time they join. No Studio edits needed. Use safe DataStore patterns (pcall, retries with backoff, `UpdateAsync`).

**Default permission table** (every cell must be editable per role in Config and per person in the panel):

| Permission | Owner | Admin | Moderator | Recorder |
|---|---|---|---|---|
| Open panel (Alt) | ✅ | ✅ | ✅ | ✅ (own Recorder panel) |
| Spectate + all camera modes | ✅ | ✅ | ✅ | ✅ |
| Kick (with reason) | ✅ | ✅ | ✅ | ❌ |
| Explode | ✅ | ✅ | ✅ | ❌ |
| Bring / Go To / Send to Box / Freeze one / Highlight | ✅ | ✅ | ✅ | ❌ |
| Bring All Players, Free mode, Freeze mode | ✅ | ✅ | ❌ | ❌ |
| Announcements | ✅ | ✅ | ❌ | ❌ |
| Start / Cancel countdown | ✅ | ✅ | ❌ | ❌ |
| Pause All / Resume | ✅ | ✅ | ❌ | ❌ |
| End race | ✅ | only if granted | ❌ | ❌ |
| Disqualify a finisher | ✅ | ✅ | ❌ | ❌ |
| Podium ceremony | ✅ | ✅ | ❌ | ❌ |
| Pass through invisible walls | ✅ | ✅ | ✅ | ❌ (can be turned on) |
| View staff log | ✅ | ✅ | ❌ | ❌ |
| Manage staff and permissions | ✅ | ❌ | ❌ | ❌ |

**Staff visibility:** Admins and Moderators are **visible** in the world but pass through the tournament's invisible walls and the gate (use collision groups). The Recorder is visible too, with wall pass-through off by default.

**Staff tags:** `[OWNER]`, `[ADMIN]`, `[MOD]`, `[REC]` tags are shown **only inside the staff panel** (next to names in lists). Normal players never see them.

**Staff log:** every staff action (who, what, target, time) is recorded and shown in a Log tab. Keep it in memory and also save it to a DataStore.

## Tournament flow (server state machine)

`Idle → Gathering → (Rules) → Countdown → Racing ⇄ Paused → Ended`, and from `Ended`, **Bring All Players** goes back to `Gathering` for a new race.

### 1. Bring All Players (`Gathering`)

- Teleports every normal player **one by one, quickly** (about 0.1 s apart, so 100 players take about 10 s) into the start box.
- From this moment, for every normal player:
  - **Strip tools:** clear the Backpack and any equipped Tool. Remove any tool **the instant it is added** (watch Backpack and Character `ChildAdded`). As a backup, run a check every 10 s. After every respawn, check 2–3 more times over the first few seconds, because gamepass tools come back on respawn. **Never remove the winner reward tool.**
  - **Equal stats:** the same WalkSpeed and JumpPower/JumpHeight for everyone (values in Config). Re-apply on respawn and if anything changes them.
  - **Hide main-game UI:** disable every ScreenGui in the player's PlayerGui that does not belong to the tournament (shops, purchase buttons, etc.). Remember exactly which ones were enabled. Also catch ScreenGuis added later (for example ones that reset on spawn). Tournament UI stays visible.
  - **Overhead name:** a simple, large name above the head (Display Name only, never Username), readable from far away.
  - **No player collision:** players do not collide with each other inside the box (collision groups). Make race-time collision a Config option, default off.
- **Respawn location:** while `Gathering` or `Countdown`, a player who dies respawns **inside the start box** (or is moved back into it right after spawning). While `Racing`, a player who dies respawns on `RespawnPoint`.

### 2. Start box

- The `StartBoxArea` part defines the volume. Generate **thick walls on all sides and a roof** from its size, so nobody can get out. The **front wall is the gate**, and it spans the whole front side, so the front row has as little advantage as possible.
- **Free mode:** players move and jump freely inside.
- **Freeze mode:** players are arranged in **neat rows in a grid** inside the box (for example 10 × 10 for 100 players, computed from the box size), facing the gate, in **random order**, and frozen in place (anchored, no movement). The layout must fit any box size and player count.
- An Admin can switch between Free and Freeze at any time before the race.

### 3. Announcements

- Staff type a message and set **how many seconds** it stays (default 10).
- It appears at the **top of every player's screen**: nice looking, fairly large and easy to notice, but it must not block gameplay.
- Each announcement shows a **circular countdown ring** that shows how much time is left, then fades out.
- New announcements **stack** with older ones (all visible together), up to **4** at once; when a 5th arrives, the oldest is removed.
- Filter the text (Hard rule 5).

### 4. Rules screen and start

- When an Admin presses **Start**, every player first sees the **rules** for a few seconds (text in Config, for example "If you die you restart from the beginning", "Cheating means disqualification").
- Then a **10-second countdown** shows in **large text in the middle of the screen with sound** (10 … 1, GO!).
- During the countdown, Free-mode players can still move around in the box, and Freeze-mode players stay frozen.
- An Admin can **Cancel** the countdown.
- At GO: everyone is unfrozen, the gate drops or slides away (with a nice tween), and the race starts.

### 5. Checkpoints (anti-shortcut only)

- `Checkpoints/1..N` may be invisible.
- Checkpoints are **not respawn points.** Dying always sends the player back to `RespawnPoint` and **resets their checkpoint progress to 0**.
- A checkpoint only counts if it is the **next one in order**. Skipping one does not count.
- The first time a player reaches a checkpoint in their current run: play a **sound** (ID in Config) and show a **small notification only to that player**, such as "Checkpoint 5". Do not repeat it while they stand on it.
- **Effect hook:** if `Assets/CheckpointEffect` contains anything, clone it and play it at the checkpoint, visible to everyone (it must work even when the checkpoint part is invisible). If the folder is empty, do nothing. I will add my own effect later.
- Use touch events with per-player debounce, validated on the server (check the character is really near the part).

### 6. Finish and winners

- Touching `FinishLine` counts only if the player has **all checkpoints in order**, the race is in `Racing`, and they have not already finished. Each player counts **once**.
- Finishers are teleported to `WinnerPlatform`, so they do not block the line.
- **1st, 2nd, 3rd:** an announcement to everyone (for example "🥇 Name finished 1st!") that lasts **10 seconds**, using the announcement system. **No avatar on screen.**
- **1st place:** confetti or fireworks plus a sound.
- **Giant statues:** build each top-3 player's avatar (for example `Players:CreateHumanoidModelFromUserId`), scale it up a lot (`Model:ScaleTo`), place it on `StatueSpots/1..3`, and make it **dance in a loop**. **Each place has its own dance**; the three Animation IDs are in Config. A new race's winners replace the statues.
- **Winner rewards (temporary):** the top 3 get a **special overhead tag** (for example 🥇 CHAMPION, 🥈, 🥉) and a copy of `Assets/RewardTool`. Both last until the player leaves the game. If they die, they get the tool again. Do not save them.
- **Disqualify:** an Admin can disqualify a finisher. Everyone below moves up one place, and the announcements, statues and rewards update.
- **Podium ceremony** (Admin button): teleport the top 3 onto `Podium/1..3`, freeze them, play their dances, drop confetti, and let a camera orbit them.
- The race **keeps going after the top 3** until an Admin presses End.
- **Results** (race number, place, UserId, name) are saved to a DataStore **per race** ("Race 1", "Race 2", …). Nothing is ever overwritten.

### 7. Live top 10 (every player's screen)

- A small panel on the side shows the current **top 10**: rank, round profile picture (headshot thumbnail) and Display Name.
- Below it: **"You: #47 / 100"**.
- Ranking: finishers first (by finish order), then everyone else by highest checkpoint reached. On a tie, whoever reached it **earlier** ranks higher.
- A small button slides the panel off to the side and brings it back, so it does not bother anyone.
- Recorder can turn it off completely.
- Calculate on the server and send throttled updates.

### 8. Pause All / Resume

- **Pause All:** move every racer to **their last reached checkpoint** (or `RespawnPoint` if they have none) and freeze them there, so nobody is frozen in mid-air.
- **Resume:** unfreeze everyone and continue.

### 9. End (keep it simple: a safety switch)

- Needs a confirmation ("Are you sure?") and the End permission.
- Everyone sees the notification **"Obby Match Ended"**.
- **Nobody is teleported.** Players can keep playing.
- **Results are kept** and nothing is deleted.
- Finishes after End do not count.
- **Main-game UI is restored** exactly as it was. Stop stripping tools and forcing stats, so gamepass tools come back normally on the next respawn.
- To run another race: **Bring All Players** again, then Start.

### 10. Late joiners and rejoiners

- If someone joins (or rejoins) while a race is running, they are sent to `RespawnPoint` and start from 0. Apply all tournament rules to them (tools stripped, UI hidden, overhead name, ranking). No server lock.
- If they join during `Gathering` or `Countdown`, bring them into the start box.

## Staff panel (client UI)

- Toggled with **Alt** (LeftAlt or RightAlt): press once to open, press again to close. PC only, no mobile support needed. The mouse must be free while the panel is open.
- Each role sees only the buttons it has permission for. The **Recorder has its own panel**.
- **Player list:** every player with a **large Display Name and Roblox profile picture**. A **search box** that matches **Display Name or Username**. No location or status column is needed.
- Click a player to get actions: **Spectate, Explode, Kick (with a reason the player sees), Bring, Go To, Send to Box, Freeze/Unfreeze, Highlight** (a glowing outline). Kick, Explode and End ask for confirmation.
- **Explode:** a visible explosion effect that kills only that player and does not hurt anyone else.
- **Tournament controls:** Bring All Players, Free mode, Freeze mode, Start, Cancel countdown, Pause All, Resume, End, Podium ceremony, Announcement (message plus seconds).
- **Results tab:** current standings, with a Disqualify button.
- **Staff tab** (Owners only): add by Username, choose a role, remove, and toggle each permission for a role or for one person.
- **Log tab.**
- Design: clean, modern, dark, rounded corners, readable at 1080p. Use `UIScale` or relative sizing so it works on any PC resolution.

## Recorder and spectate

- **Clean screen:** when the panel is closed, a Recorder sees **no UI at all**. Turn off all CoreGui (chat, player list, backpack, health, emotes). Only Roblox's own top-left menu button cannot be hidden, and that is acceptable.
- **Recorder toggles** (all off or hidden by default where it makes sense): overhead names on/off (for close-up shots), live top 10 on/off, a "Finished: 12 / 100" counter on/off, and the spectated player's name at the bottom on/off.
- **Spectate controls**, for any staff who is spectating:
  - **← / →:** previous or next player.
  - **↑ / ↓:** previous or next camera mode.
  - **P:** opens a small camera-mode menu listing all modes, with the current one highlighted. Clicking a mode selects it and **closes the menu automatically**. P also closes it.
  - **Do not use number keys 1–9** (they conflict with Roblox tool slots).
  - While spectating, the arrow keys must **not** move the staff member's own character or turn the default camera. Sink those inputs with `ContextActionService` at high priority.
  - **No on-screen mode-name popup** when switching modes.
  - Sliders in the panel for camera **speed, distance and zoom (FOV)**.
- **Loading far-away areas (StreamingEnabled):** do **not** keep moving the spectator's character after the target, because that causes lag. Primary method: keep the spectator's character where it is and stream the target's area using Roblox's built-in features (`Player.ReplicationFocus` set by the server to the target's root part, and/or `Player:RequestStreamAroundAsync`). Fallback, only if that is not enough: when spectating starts, move the spectator's character **once** near the target, invisible and non-colliding, and move it back and make it visible again when spectating stops. This applies to all staff.

### Camera modes (all smooth, eased, with no jitter)

1. **Normal:** the standard Roblox-style spectate camera attached to the player, with mouse orbit and zoom, so everything they do is clearly visible.
2. **Follow:** smooth chase camera behind the player with a slight, cinematic lag, like a real camera operator.
3. **Fixed height:** follows the player but **does not bob up and down when they jump**.
4. **Side view:** side-on tracking shot. Best for showing obby jumps.
5. **Orbit:** slowly circles the player. Speed and direction (left/right) can be changed.
6. **Crane down:** starts high above and slowly descends towards the player, then **automatically switches to Follow** when it reaches the bottom.
7. **Face cam:** in front of the player, looking at their face.
8. **First person:** through the player's eyes.
9. **Drone shot:** very high and far away, showing the whole area around the player.
10. **Free cam:** fly anywhere freely with WASD plus up/down keys and the mouse, not attached to any player. Selected from the P menu.

Extras:
- **Auto director mode:** switches between modes (and optionally between leading players) every few seconds, like a TV broadcast.
- **Cinema bars:** press **B** to toggle black letterbox bars at the top and bottom.
- **No clipping:** the camera never goes inside walls or parts (raycast and pull in).

## How to work

1. **Explore first (read-only).** Inspect the place and give me a short report in Bengali covering: how gamepass tools are given, which ScreenGuis exist, whether StreamingEnabled is on, existing collision groups, the existing spawn setup, and anything that could conflict with this system. Do not change anything in this step.
2. **Build in phases** and test each phase before moving on:
   1. Folders, Config, placeholder parts, roles, permissions and the staff DataStore.
   2. Bring All, start box generation, Free/Freeze, tool stripping, UI hiding, overhead names.
   3. Announcements, rules, countdown, gate.
   4. Checkpoints, finish, ranking, live top 10, winners, statues, rewards, results saving.
   5. Staff panel (all tabs), Pause/Resume, End, logs.
   6. Spectate, camera modes, Recorder clean screen and toggles.
3. **Test** with whatever your Studio MCP tools allow: run playtests, read the Output for errors and warnings, run pure-logic checks (ranking, permissions, grid layout) with test cases, and use dummy rigs to stand in for players when checking the freeze grid, statues and podium. Fix every error you find and test again.
4. Remind me that DataStores only work in Studio when **Game Settings → Security → Enable Studio Access to API Services** is on.
5. Some things can only be tested with real players (100-player load, multi-client spectate). For those, write me a short **manual test checklist in Bengali**, which I will run with friends in a rehearsal (Studio **Test → Clients and Servers**, then a real server).
6. At the end, give me in Bengali:
   - what was built and where,
   - which Config values I will probably want to change (Animation IDs, sound IDs, rules text, speeds, and so on),
   - how to move and resize the parts,
   - how to turn the system off (`Config.Enabled`) and how to delete it completely (delete the two `Tournament` folders),
   - any known limitations.

If anything in this spec is unclear or contradicts what you find in my place, **ask me before guessing**.
