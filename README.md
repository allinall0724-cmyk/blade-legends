# Blade Legends

A complete, publish-ready Roblox game: collect weapons from cases, fight in casual
and ranked PVP, trade with other players, and climb a global leaderboard.

Built with **Luau + Rojo 7.6.1**. Server-authoritative for all combat, economy and
ownership. `rojo build` produces `game.rbxl`, ready to open in Roblox Studio.

## Build

```sh
rojo build --output game.rbxl
```

Open `game.rbxl` in Studio and press Play. To enable saving and Toolbox model
loading, turn on **Game Settings → Security → Enable Studio Access to API Services**
(the game runs fine without it — DataStore falls back to in-memory and weapons use a
generated placeholder mesh).

## Project layout

```
src/
  ReplicatedStorage/        shared config + Net (replicates as ReplicatedStorage.Shared)
    RarityConfig, WeaponConfig, CaseConfig, RankConfig, WorldConfig, Net
  ServerScriptService/
    Bootstrap.server.luau   entry point -> Services.GameManager.init()
    Services/               DataService, CombatService, CaseService, RankService,
                            TradeService, LeaderboardService, MonetizationService,
                            WorldBuilder, GameManager
  StarterPlayerScripts/
    Bootstrap.client.luau   entry point -> Controllers
    Controllers/            UIManager, CombatClient, InputHandler
    UI/                     UIKit + MainHUD, Inventory, CaseOpening, Shop,
                            Leaderboard, RankedQueue, Trade
```

Services are ModuleScripts started in order by `GameManager.init()`; cross-service
calls go through hooks (e.g. `_pushHud`, `CombatService.onKill`) so there are no
circular requires.

## Weapon system — 5,400 weapons from 15 models

15 base 3D models are pulled from the **real Roblox Toolbox** (toolbox-service
marketplace search, category 10 = Models). Each weapon is a deterministic
combination of `baseType(15) × rarity(6) × material(10) × size(6)` packed into a
single integer id in `[1, 5400]` (`WeaponConfig.encode/decode`). Stats, name, color,
particles and trail are all derived from that id.

| Keyword | Asset ID |
|---|---|
| sword | 47433 |
| katana | 15283548889 |
| battle axe | 401083997 |
| war hammer | 13106821277 |
| spear | 8865050093 |
| magic staff | 107585195482186 |
| bow arrow | 11490959971 |
| dagger | 11746816357 |
| scythe | 8186983320 |
| trident | 95617739938869 |
| club mace | 78784820401093 |
| lance | 15445540711 |
| wand | 6265215909 |
| gauntlet fist | 14913098471 |
| shield weapon | 121179389531601 |

## Controls

| Key | Action |
|---|---|
| LMB | Swing (server-side hitbox) |
| Hold RMB | Block (50% damage reduction, slows you) |
| Q | Dodge roll (i-frames) |
| I | Inventory |
| C | Cases |
| B | Shop |
| L | Leaderboard |
| K | Arenas (ranked queue + casual join) |
| E | Trade nearest player |

## Going live (monetization)

`MonetizationService.PASSES` and `.PRODUCTS` ship with `id = 0` placeholders. After
publishing, create the game passes / developer products in the Creator Dashboard and
paste the real asset ids into those tables — purchasing, the receipt processor and
pass-ownership sync activate automatically.

| Item | Robux | Field |
|---|---|---|
| 2x Coins Pass | 149 | `PASSES.coins2x.id` |
| Lucky Pass | 299 | `PASSES.lucky.id` |
| VIP Pass | 499 | `PASSES.vip.id` |
| 500 / 1500 / 5000 Coins | 49 / 129 / 349 | `PRODUCTS.coinsXXX.id` |
| Instant Rank Shield | 99 | `PRODUCTS.rankShield.id` |

## Notes

- All RemoteEvent handlers validate argument types server-side; the client only ever
  sends intent.
- DataStore reads/writes are wrapped in `pcall` with up to 3 retries; autosave every
  120s and a `BindToClose` flush.
- Casual maps (Colosseum / Sky Arena / Underground Pit / Forest Clearing) rotate each
  5-minute round. Ranked is 1v1 first-to-3 with rating gains/losses by tier and a
  30-day season that pays out and resets ratings.
