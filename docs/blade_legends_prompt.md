# Blade Legends — Full Claude Code Build Prompt

Paste this entire prompt into Claude Code on Fable. Do not start building until you have read every section.

---

## YOUR MISSION

Build a complete, fully playable Roblox game called **Blade Legends** using Luau and Rojo. The game must be ready to publish with zero manual editing required. Pull all 3D weapon models from the Roblox Toolbox/Creator Store using the Roblox API. Every system listed below must be fully implemented and working.

---

## TECH STACK

- **Language:** Luau (Roblox)
- **Build tool:** Rojo (project structure with default.project.json)
- **Asset sourcing:** Roblox Toolbox API (free models only)
- **DataStore:** Roblox DataStoreService for persistence
- **Output:** A compiled game.rbxl file ready to open in Roblox Studio and publish

---

## GAME OVERVIEW

**Blade Legends** is a weapon collection + PVP game. Players open cases to collect weapons, fight in casual and ranked PVP arenas, trade weapons with other players, and climb a global leaderboard. The core loop is: collect → fight → earn → collect more.

---

## WORLD LAYOUT

Build one unified hub map with these distinct zones:

**1. Hub World (center)**
- Large open area where players spawn
- Global leaderboard board (top 10 players by rank rating, updates live)
- NPC vendors for the shop
- Portal/telepad to each zone
- Display cases showing rare weapons owned by top players
- Animated weapon showcase rotating in the center

**2. Case Opening Area**
- Dedicated room with opening animations
- Visual rarity spin effect (like a slot reel)
- Confetti and particle effects for Legendary+ pulls
- Recent pulls ticker showing other players' pulls in real time

**3. Casual PVP Arena**
- Round-based combat area (up to 12 players)
- Various arena map variants that rotate each round
- Coin rewards for kills and wins
- No rank points at stake

**4. Ranked PVP Arena**
- Separate queue from casual
- Matchmaking by rank tier
- 1v1 or 2v2 format (let Claude decide which is more fun)
- Rating points gained/lost based on outcome
- Pre-match lobby showing both players' rank and equipped weapon

**5. Trading Post**
- Dedicated trading area
- UI for sending/receiving trade offers
- Trade window showing both players' offered weapons
- Confirmation system to prevent scams

---

## WEAPON SYSTEM (750+ WEAPONS)

Do NOT source 750 individual Toolbox models. Instead use a **combination generation system**:

**Step 1 — Pull 15 base weapon models from Roblox Toolbox**

Search these keywords via the Toolbox API and take the top free result for each:
- "sword roblox"
- "katana"
- "battle axe"
- "war hammer"
- "spear"
- "magic staff"
- "bow arrow"
- "dagger"
- "scythe"
- "trident"
- "club mace"
- "lance"
- "wand"
- "gauntlet fist"
- "shield weapon"

Store asset IDs in a WeaponConfig module.

**Step 2 — Combination system**

Each weapon is defined by 4 attributes combined:

| Attribute | Options |
|-----------|---------|
| Base type | 15 types above |
| Rarity | Common, Uncommon, Rare, Epic, Legendary, Mythic (6 tiers) |
| Material | Wood, Stone, Iron, Gold, Crystal, Shadow, Fire, Ice, Lightning, Void (10) |
| Size modifier | Tiny, Small, Normal, Large, Giant, Colossal (6) |

Total combinations: 15 × 6 × 10 × 6 = **5,400 unique weapons**

**Step 3 — Weapon stats formula**

Stats scale with rarity and size:
```
BaseDamage = RarityMultiplier × SizeMultiplier × BaseTypeDamage
Speed = BaseTypeSpeed / SizeMultiplier
```

Rarity multipliers: Common=1, Uncommon=1.5, Rare=2.5, Epic=4, Legendary=7, Mythic=12
Size multipliers: Tiny=0.5, Small=0.75, Normal=1, Large=1.5, Giant=2, Colossal=3

**Step 4 — Visual differentiation**

Apply to each weapon in-game:
- **Color:** Each material has a defined BrickColor/Color3
  - Wood=brown, Stone=gray, Iron=slate, Gold=bright yellow, Crystal=cyan, Shadow=dark purple, Fire=red-orange, Ice=light blue, Lightning=yellow-white, Void=black
- **Particle effect:** Rare+ get a particle emitter (fire, sparkle, ice crystals, lightning based on material)
- **Size:** Scale the model by the size modifier
- **Trail:** Legendary+ get a trail effect when swinging

**Step 5 — Weapon naming**

Auto-generate names: `[Material] [Size?] [BaseType]`
Examples: "Void Colossal Scythe", "Fire Katana", "Ice Giant War Hammer"
Only include size in the name if it's not Normal.

---

## CASE SYSTEM

**3 case types:**

| Case | Cost | Rarity weights |
|------|------|----------------|
| Basic Case | 100 coins | Common 60%, Uncommon 30%, Rare 8%, Epic 1.9%, Legendary 0.1% |
| Pro Case | 500 coins | Common 30%, Uncommon 35%, Rare 25%, Epic 8%, Legendary 1.8%, Mythic 0.2% |
| Mythic Case | 2000 coins | Rare 40%, Epic 35%, Legendary 20%, Mythic 5% |

**Opening animation:**
- Spinning reel of weapon silhouettes
- Slows down and lands on the result
- Screen flash based on rarity color
- Particle explosion for Epic+
- Server-wide announcement for Legendary+: "[Player] just unboxed a Mythic Void Scythe!"

**Pity system:**
- Track pulls since last Legendary in DataStore
- After 50 pulls without Legendary in Basic Case → guaranteed Legendary next pull
- Reset counter on Legendary pull

---

## PVP COMBAT SYSTEM

**Combat mechanics:**
- Click to swing weapon
- Damage based on weapon stats
- Hitbox detection server-side (never trust client)
- Cooldown between swings based on weapon speed
- Block mechanic (hold button to reduce damage by 50%, slows movement)
- Dodge roll (tap key to roll in movement direction, 1 second cooldown)
- Health bar displayed above each player
- Kill feed in corner showing recent kills

**Casual Arena:**
- 12 players max
- Free for all or teams (auto-balanced)
- 5 minute rounds
- Coin rewards: 10 per kill, 50 for round win
- Respawn after 5 seconds
- Rotating maps: Colosseum, Sky Arena, Underground Pit, Forest Clearing

**Ranked Arena:**
- Separate queue
- Matchmaking within 200 rating points of each other
- 1v1 format (cleanest for ranking)
- First to 3 kills wins
- No respawn — each kill is a round
- Rating changes:
  - Win vs equal rank: +25 points
  - Win vs higher rank: +35 points
  - Loss vs lower rank: -30 points
  - Loss vs equal rank: -20 points

---

## RANK SYSTEM

6 tiers with visual rank badges:

| Rank | Rating Range | Badge Color |
|------|-------------|-------------|
| Bronze | 0-999 | Brown |
| Silver | 1000-1999 | Silver |
| Gold | 2000-2999 | Gold |
| Diamond | 3000-3999 | Cyan |
| Legendary | 4000-4999 | Purple |
| Mythic | 5000+ | Red-Gold gradient |

**Season system:**
- Season lasts 30 days (tracked in DataStore)
- End of season: send reward coins based on rank achieved
  - Bronze: 500 coins
  - Silver: 1000 coins
  - Gold: 2500 coins
  - Diamond: 5000 coins
  - Legendary: 10000 coins
  - Mythic: 25000 coins + exclusive Mythic Season weapon
- After rewards: reset all ratings to 0, keep weapons and coins
- New season announcement in server chat

---

## LEADERBOARD

**Global leaderboard board in hub world:**
- Shows top 10 players by current rank rating
- Updates every 60 seconds
- Shows: rank position, username, rank tier badge, rating number, equipped weapon name
- Players in top 10 get a golden name tag visible to all players in the server
- Clicking a player's name on the board shows their weapon collection preview

---

## TRADING SYSTEM

- Player walks up to another player and presses E to initiate trade
- Trade window opens showing:
  - Left side: your weapons (scrollable grid)
  - Right side: their weapons (scrollable grid)
  - Both players drag weapons into the offer slots (up to 4 weapons each side)
  - Both must click "Ready" to confirm
  - 3 second countdown then trade executes
  - Either player can cancel before countdown ends
- Server validates both players still own the offered weapons before executing
- Trade logged to DataStore

---

## MONETIZATION

**Game Passes:**
- **2x Coins Pass** — 149 Robux — doubles all coin earnings permanently
- **Lucky Pass** — 299 Robux — increases Legendary chance by 50% permanently
- **VIP Pass** — 499 Robux — 2x coins + lucky boost + VIP chat tag + exclusive VIP weapon case weekly

**Developer Products (repeat purchase):**
- **500 Coins** — 49 Robux
- **1500 Coins** — 129 Robux (BEST VALUE badge)
- **5000 Coins** — 349 Robux
- **Instant Rank Shield** — 99 Robux — protect against losing rating points for 1 ranked loss

**Daily free coins:**
- 50 coins on first login each day
- Streak bonus: day 3 = 150 coins, day 7 = 500 coins, day 30 = 2000 coins

**All Robux transactions must be server-side only. Product IDs start at 0 and are activated when real IDs are assigned post-publish.**

---

## DATA PERSISTENCE

Save to DataStore per player:
```lua
{
  coins = 0,
  weapons = {}, -- array of weapon IDs owned
  equippedWeapon = nil,
  rankRating = 0,
  seasonHighRank = "Bronze",
  totalKills = 0,
  totalWins = 0,
  casesPulled = { basic = 0, pro = 0, mythic = 0 },
  pityCounter = 0,
  lastLoginDate = "",
  loginStreak = 0,
  passes = { coins2x = false, lucky = false, vip = false }
}
```

Use pcall on all DataStore operations. Retry on failure up to 3 times.

---

## UI REQUIREMENTS

Build these GUI screens:

**1. Main HUD**
- Coin count (top left)
- Equipped weapon name and rarity color (bottom center)
- Rank badge and rating (top right)
- Minimap (bottom right)

**2. Inventory Screen (press I)**
- Grid of all owned weapons
- Filter by rarity, type, material
- Sort by damage, rarity, newest
- Click weapon to equip
- Click weapon + right click to offer in trade or discard

**3. Case Opening Screen**
- 3 case buttons with prices
- Opening animation overlay
- Result display with weapon stats
- "Open Again" and "Close" buttons

**4. Shop Screen (press B)**
- Coin bundles
- Game pass descriptions
- Daily deal slot

**5. Leaderboard Screen (press L)**
- Full ranked leaderboard (top 50)
- Your current position highlighted
- Season timer countdown

**6. Ranked Queue Screen**
- "Enter Ranked Queue" button
- Current rank display
- Estimated wait time
- Cancel button

---

## ROJO PROJECT STRUCTURE

```
blade-legends/
├── default.project.json
├── src/
│   ├── ServerScriptService/
│   │   ├── GameManager.server.luau
│   │   ├── CombatService.server.luau
│   │   ├── CaseService.server.luau
│   │   ├── RankService.server.luau
│   │   ├── TradeService.server.luau
│   │   ├── DataService.server.luau
│   │   ├── LeaderboardService.server.luau
│   │   └── MonetizationService.server.luau
│   ├── ReplicatedStorage/
│   │   ├── WeaponConfig.luau
│   │   ├── RarityConfig.luau
│   │   ├── CaseConfig.luau
│   │   ├── RankConfig.luau
│   │   └── RemoteEvents/
│   │       ├── OpenCase.RemoteEvent
│   │       ├── EquipWeapon.RemoteEvent
│   │       ├── InitiateTrade.RemoteEvent
│   │       ├── TradeAction.RemoteEvent
│   │       ├── EnterRankedQueue.RemoteEvent
│   │       ├── LeaveQueue.RemoteEvent
│   │       ├── UpdateHUD.RemoteEvent
│   │       └── Notification.RemoteEvent
│   ├── StarterPlayerScripts/
│   │   ├── CombatClient.client.luau
│   │   ├── UIManager.client.luau
│   │   └── InputHandler.client.luau
│   └── StarterGui/
│       ├── MainHUD.luau
│       ├── Inventory.luau
│       ├── CaseOpening.luau
│       ├── Shop.luau
│       ├── Leaderboard.luau
│       └── RankedQueue.luau
```

---

## BUILD RULES

1. **All combat and economy logic runs server-side only** — never trust the client for damage, coins, or weapon ownership
2. **All RemoteEvents must have server-side argument validation** using typeof() checks
3. **No script may exceed 200KB**
4. **All DataStore calls wrapped in pcall with retry logic**
5. **Toolbox asset IDs must be fetched via the Roblox Toolbox API** — do not hardcode fake IDs. Use the search endpoint to find real free models for each weapon type keyword
6. **The game must compile with rojo build** with exit code 0
7. **No TOS violations** — no realistic weapons, no adult content, no gambling terminology (use "cases" not "gambling", "rarity" not "odds")

---

## ACCEPTANCE CRITERIA

The build is complete when:
- [ ] rojo build exits 0 with no errors
- [ ] All 15 base weapon types have real Toolbox asset IDs
- [ ] Weapon combination system generates correct names, colors, and stats
- [ ] Case opening works with correct rarity weights and pity system
- [ ] Casual PVP arena is playable with kill/win coin rewards
- [ ] Ranked queue, matchmaking, and rating system work
- [ ] Leaderboard updates and displays top 10
- [ ] Trading system works between two players
- [ ] All 6 UI screens open and function correctly
- [ ] DataStore saves and loads correctly on rejoin
- [ ] Daily login streak system works
- [ ] Monetization passes and products are implemented (IDs at 0)
- [ ] Game opens in Roblox Studio with no errors in output

---

## FINAL INSTRUCTION

Build everything in one continuous session. Commit to GitHub after each major system is complete. Do not stop and ask for approval on individual decisions — make the best call and keep building. Only stop if you hit a Roblox API limitation that fundamentally breaks a core system. When done, open the game.rbxl in Roblox Studio and report any errors in the output window.
