# Fairyland

A cozy 2.5D pixel-art RPG for iPhone (portrait and landscape), inspired by Fairyland Online (2007).
Built with SwiftUI + SpriteKit. Art is generated with [Retro Diffusion](https://www.retrodiffusion.ai).

## What's in the game

- **14 isometric maps** you walk between along winding roads: towns (Meadowbrook, Rainbow City, dwarven
  Goldburg) with streets, shops, fairytale buildings and raised stone terraces, and wild zones from Sunny
  Meadow and the Smiling Forest to Frog Swamp, the Valley of Fear, Rat Cavern, Genie Desert, Crystal Mountain,
  Snow White Forest and Moonglow. Quests open the roads onward.
- **Random encounters** in the wild (no monsters on the map), with **turn-based battles** fought where you
  stand. Big spells splash onto nearby monsters. Three bosses wait on their maps.
- **81 monsters** across seven elements, including rare, tougher colour variants.
- **Capture like Fairyland Online:** throw a Seal Stone at the last monster standing once it's below 20% HP.
  It may break free or run away. Keep up to 5 companions; your first hatches from the starter quest's egg.
- **Classes and skills:** start as a Novice, join a guild at level 5. Each level gives a skill point to learn
  a new skill or power one up (levels 1–5), each with its own animation.
- **A living world:** villagers and other adventurers wander and chat (see the chat window), you can befriend
  adventurers and bring two along in your party, and danger zones allow duels.
- **Customisation:** hair, outfit and skin (more unlock through quests); armour recolours your outfit and your
  weapon shows in hand.
- Quests, shops, healers, checkpoints, an in-game calendar and an original storybook soundtrack (flutes, harp, music box, strings and more, synthesized on the device).

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
| `content/music.json` | the songs and their instruments, in a tracker-style note format (`tools/music_preview.py` renders them to WAV) |
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

## Screenshots without a Mac

Every push to a `claude/**` branch runs the **Screenshots** GitHub Action on a macOS runner. It builds the app
for the iOS Simulator, opens each scene in `tools/screenshots.txt` with the debug shortcuts below, and saves
the images to the `screenshots` branch in a folder named after the branch (also attached to the run as an
artifact). On a private repo, macOS runner minutes count 10× against the Actions allowance.

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
Fairyland/Audio/       storybook synth (additive instruments, drums, reverb) + music player
Fairyland/Art/         sprite loading and placeholder art
Fairyland/UI/          SwiftUI HUD, menus, dialogs, battle UI
FairylandTests/        rules and content tests
```

## Working from your phone (no Mac needed)

Pushes to `main` are built by **Xcode Cloud** (`ci_scripts/ci_post_clone.sh` installs XcodeGen and generates
the project). With a TestFlight step in the Xcode Cloud workflow, every build lands on your iPhone through the
TestFlight app:

1. In App Store Connect, create the app (bundle id `com.jurgenploeger.fairyland`) and an internal TestFlight
   group with yourself in it; install **TestFlight** on the iPhone.
2. In Xcode Cloud, edit the workflow: start condition **Branch changes → main**, action **Archive (iOS)** with
   deployment preparation **TestFlight (Internal Testing Only)**, and a post-action **TestFlight Internal
   Testing** for your group.
3. From the Claude app on your phone, open a **Claude Code** cloud session on this repo. It can edit and push
   but can't run Xcode, so check game-data edits with `python3 tools/check_content.py` before pushing.
   To generate art there, add `RETRO_DIFFUSION_API_KEY` to the cloud environment's variables.
