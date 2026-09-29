# Fairyland

A cozy 2.5D pixel-art RPG for iPhone (portrait and landscape), inspired by Fairyland Online (2007).
Built with SwiftUI + SpriteKit. Art is generated with [Retro Diffusion](https://www.retrodiffusion.ai).

## What's in the game

- **Isometric maps** you walk between by leaving along a road: Meadowbrook (town), Sunny Meadow,
  Pineapple Shore and Twilight Woods. Each has its own ground, scenery, ambience and music.
- **Random encounters** in the wild (no monsters on the map), with **turn-based battles** fought where you stand:
  Attack, Skills, Items, Guard, Run, and **Capture** once a monster is below half HP.
- **Companions:** your first comes from the pet egg in the "Hope of Meadowbrook" quest (your answer to the
  elder decides which one hatches). After that, capture monsters. Companions fight beside you and level up.
- **Classes:** start as a Novice; at level 5 join a guild as a Fighter, Mage or Beast Tamer.
- **Skills** with levels 1–5 (one skill point per level-up). Every skill has its own battle animation that grows with its level.
- **Quests, a shop, a healer**, equipment, the seven-element chart, an in-game calendar, and an original chiptune soundtrack.

## Run it

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make open        # generates Fairyland.xcodeproj and opens it in Xcode
```

Pick a simulator or your iPhone in the Xcode toolbar and press ⌘R (or run `make sim`).

### On your iPhone

1. Connect the iPhone with a cable (the first time; after that Wi-Fi works), unlock it, and tap **Trust**.
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
3. In Xcode, pick your iPhone in the device menu and press ⌘R.
4. First launch only: **Settings → General → VPN & Device Management** → trust your Apple ID.

With a free Apple ID the app expires after 7 days. Press ⌘R again to reinstall.

## Editing the game (no code needed)

| File | What's in it |
|---|---|
| `content/maps.json` | maps, exits, themes, scenery, ambience, NPCs, encounter tables |
| `content/monsters.json` | species stats, elements, capture rates |
| `content/classes.json` | races, classes, stat growth, skill unlocks, class-choice level |
| `content/skills.json` | skills and spells, power, MP, element, battle animation |
| `content/items.json` | potions, eggs, equipment |
| `content/quests.json` | quests, objectives, rewards, the elder's question |
| `content/music.json` | the songs, in a tracker-style note format |
| `art/assets.json` | every sprite and its Retro Diffusion prompt |

Rebuild after editing. The unit tests (⌘U) check that every reference between these files resolves.

## Art pipeline (Retro Diffusion)

```bash
cp .env.example .env         # paste your API key (retrodiffusion.ai → Dev Tools)
make art-list                # what's defined, what's generated
make art-cost                # free: what generating the missing sprites would cost
make art                     # generate missing sprites → art/sprites/<id>.png
```

Anything not generated yet shows as built-in placeholder pixel art.
`python3 tools/rd.py generate <id> --force --variants 4` gives you options, and `python3 tools/rd.py use <id> <file>` picks one.
Every generation is kept in `art-variants/<id>/`.

The app icon and title logo come from the Figma file and live in `Fairyland/Resources/Assets.xcassets`.

## Debug shortcuts

Set `FAIRYLAND_DEBUG` in the scheme's environment variables (comma-separated):
`newgame`, `level=5`, `map=sunny_meadow`, `battle`, `menu=companions`, `npc=elder`, `landscape`.

## Project layout

```
project.yml            XcodeGen spec (source of truth for the Xcode project)
content/               game data (JSON)
art/                   sprite manifest + generated PNGs
tools/rd.py            Retro Diffusion client (Python standard library only)
Fairyland/App/         app, coordinator, SpriteKit host, debug launch
Fairyland/Model/       save data, session rules (levels, quests, items), calendar
Fairyland/World/       isometric maps, walking, NPCs, ambience
Fairyland/Battle/      battle engine, controller, scene, skill effects
Fairyland/Audio/       chiptune synth + music player
Fairyland/Art/         sprite loading and placeholder art
Fairyland/UI/          SwiftUI HUD, menus, dialogs, battle UI
FairylandTests/        rules and content tests
```
