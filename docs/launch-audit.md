# Launch audit (2026-10-06, at 0.3.60)

What stands between Storyleaf and the App Store, what's broken or off-balance, and what would bring players
back. Six read-throughs of the code and content (battle, saves and app lifecycle, world and performance, UI with
accessibility and translation, content and balance, App Store readiness), Python battle simulations that copy the
engine's formulas, and the CI screenshots. Every finding here was checked against the code; numbers marked
*est.* come from simulations or models, not from a phone. Tick items off or delete them as they're done.

## Fixed in 0.3.60

- A fight froze for good when AUTO was tapped while the battle buttons wiggled to be rearranged.
- A beaten boss could miss its promised gear drop when two followers dropped gear first; the boss now rolls first.
- Capture waits for a boss's last wave: a monster sealed in an earlier wave was lost, Seal Stone and all, if the
  player then lost or ran.
- Music comes back after a call, Siri, an alarm or a change of headphones or speaker.
- The first title screen speaks the chosen language (the default hero name); save cards' dates follow it, and
  "Played {time}" no longer reads as play time in seven languages.
- `CFBundleLocalizations` lists the 11 languages, so the App Store page and system screens (the Files pickers)
  aren't English-only.
- `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, file timestamps C617.1 and DDA9.1), and CI fails without it.
- The intro's last page buttons no longer overflow; two node retain cycles in `GearArt`; the Silverfang Warden's
  victory text no longer says "Lieutenant".
- Villagers' names are translated (`villagerNames` was missing from `content/i18n/fields.json`, so they were the
  only names left in English).

## Before you submit

### Blockers

1. **Privacy policy.** App Store Connect requires a Privacy Policy URL for iOS apps, and guideline 5.1.1(i) also
   wants a link inside the app. Host a short page (nothing is collected; saves stay on the device; no ads,
   analytics, accounts or network) somewhere neutral, then add a "Privacy policy" link to Settings → About,
   translated. App Privacy can honestly say "Data Not Collected".
2. **Support URL, copyright and App Review contact.** All required. The Support URL "must lead to actual contact
   information".
3. **Screenshots.** At least one for "iPhone with Dynamic Island (medium display)" is required, and 1206×2622 (the
   CI size) is accepted. But "Images can't include alpha channels or transparencies", and CI's PNGs are RGBA;
   Debug builds also show SpriteKit's FPS and node counter in map and battle shots (only `demo` hides it). The
   6.5" set is required unless the large Dynamic Island set (1320×2868) is provided, so shoot the store scenes
   once on an iPhone 17 Pro Max simulator too. Flatten to JPEG (`sips -s format jpeg`) and add a `clean` debug
   flag for the counter. Lead with gameplay, not the title screen (2.3.3).
4. **Hidden moderator mode (2.3.1, "hidden, dormant, or undocumented features").** `/mod <code>` unlocks a MOD
   badge and the World channel, and any other `/` command answers "Unknown command. The only one is /mod."
   Compile it out of Release (`Moderation.isOn` false outside DEBUG, no `/mod` handling or hint; the `mod`
   debug flag keeps working for screenshots), or give the code in the review notes.
5. **Age rating.** Expect 13+: frequent cartoon or fantasy violence is 13+ on its own, and infrequent alcohol
   references (the Drunk Dragon and its hangover quest) are 13+ too. Don't choose Made for Kids.
6. **Where it's sold.** Untick China mainland (games need an NPPA approval number) and Vietnam (games must be
   licensed there). Declare your EU trader status (DSA) in App Store Connect.

### Strongly recommended

- **Rename Red Bull and Shadow Red Bull** (`content/monsters.json`): a famous trademark, with translations.
- **Ship as 1.0.0 with a launch changelog.** The title screen's "What's new" lists 60+ pre-release entries (crash
  fixes, playtests), which reads like a beta (2.2), and one note promises a feature that doesn't exist ("They
  stand in for other players until Storyleaf goes online", `content/changelog.json`).
- **Say the adventurers are computer-run.** The first-play tour says "Adventurers wander Storyleaf too. Read what
  they say and chat back here." (`CoachMarks.swift`) without saying they're bots. Mention it there and in the
  review notes, and keep chat and MOD shots out of the listing, so nothing reads as real players' content (1.2).
- **Iconaut's MIT notice.** MIT asks for its copyright and permission notice in copies; Settings only says
  "icons by Iconaut (MIT)" and `third_party/iconaut/LICENSE` isn't in the bundle. Add an Acknowledgements screen.
- **Test where reviewers look.** iPhone-only apps run on iPads in compatibility mode, and reviewers often use
  iPads; also try a 375-pt iPhone (SE). iPhone apps are offered on Apple silicon Macs and Vision Pro by default:
  opt out unless you've tried them there.
- **Profile on an older iPhone (A12/A13)** with Instruments before launch (see Performance below).
- **Keep the listing clean of the original**: no Fairyland Online, LagerNet, Tales of Mysteria, "tribute",
  "remake", "inspired by", "MMO", "online" or "multiplayer" in the name, subtitle, keywords, description,
  screenshots or review notes.
- **App preview (optional).** 15-30 s, 886×1920 portrait, at most 30 fps, H.264 with stereo AAC audio. The CI
  `gameplay` recording is 58 s at 1206×2622 with no sound, so cut and convert it (ffmpeg) before uploading.
- `art/spend-log.jsonl` (Retro Diffusion prompts and spend) ships inside the app, because `art/` is a folder
  reference. Nothing secret, but move it out of `art/`.

### Review notes (ready to paste)

> Storyleaf is a single-player RPG that runs entirely offline: no accounts, no network connections, no ads, no
> in-app purchases, no tracking and no data collection. Everyone else in the world is computer-controlled:
> villagers, traders and the adventurers marked BOT, who wander, post pre-written chat lines, can be befriended
> to join your party, and may challenge you to duels in danger zones. There are no other human players. The chat
> window is part of this simulation: what you type stays on your device, and bots may answer with canned lines.
> Saves stay on the device; Settings > Back up to Files exports a save, and Import a backup on the title screen
> restores it. Quick tour: New game, then the story and a short tour; walk into Sunny Meadow for battles; weaken
> the last monster below 20% HP and use Capture with a Seal Stone; tap a BOT adventurer, then Befriend.

## Bugs and balance, most important first

### High

1. **Frost Breath locks the party out of its turns.** It costs 0 MP, hits everyone and always freezes (no
   `chance` in `content/skills.json`), freezes refresh every round, and there's no immunity after thawing. It's
   the only attack skill of Snowman, Shadow Snowman and Frost Bear: about 60% of Briarmere's encounter weight
   (groups of 3-10) and 38% of Snow White Forest's. *Est.:* the hero acts in about 40% of rounds against 3
   casters and 24% against 5. Fix: `"chance": 0.3` (Venom Bite has 0.4) and/or a round of immunity after thawing.
2. **The first fights are a coin flip.** Sunny Meadow rolls monster levels 1-8 evenly in groups of 1-3, so a
   level-1 hero regularly meets level-6 to 8 monsters. *Est.:* a level-1 hero with the egg companion wins about
   half to two thirds of fights from full HP, and most new players faint within their first 15 fights. Pineapple
   Harvest has no `minLevel` and sends level-3 heroes to Pineapple Shore (8-18). The Wisdom answer hatches a Jelly
   Puff, clearly weaker than the other two eggs. Fix: Sunny Meadow levels [1,4] and groups [1,2] (Windswept Downs
   [3,10]), `"minLevel": 8` on Pineapple Harvest, or cap wild levels at hero + 2 on maps that start at 10 or below.
   Friends are the biggest difficulty lever (*est.* hero and companion alone win 9-83% of fights on mid-level maps,
   54-100% with two friends), yet neither How to play nor the first-play tour mentions befriending adventurers:
   add a tip or a coach mark.
3. **The 10-second turn timer is always on** (`BattleController.turnSeconds`). There's no setting, it keeps
   running in the Skills, Items and target menus, and targets are SpriteKit nodes VoiceOver can't reach, so
   VoiceOver and Switch Control players, slow readers and children run out of time. Fix: a Settings choice (Off,
   10, 20, 30 s), hold it while VoiceOver or Switch Control runs, and give the timer an accessibility value.
4. **Performance on the wooded maps** (*est.*, needs a phone). Nothing is culled: every prop, shadow, glow and
   swaying tree stays in the scene graph with its endless actions, about 10-12k nodes and 3.5-4.7k actions on
   Twilight Woods, Snow White Forest, Smiling Forest and Frog Swamp, against a few hundred on screen. Profile on
   an iPhone XS or 11; if it's heavy, parent scenery to chunks and attach only those near the camera.
5. **Memory grows with every map visit** (*est.* rate). Each new villager or adventurer look caches a recoloured
   sheet in `ArtLibrary` for good; nothing evicts them and nothing handles memory warnings. Fix: an LRU cap on
   runtime looks, and a purge on memory warnings.

### Medium

6. **Save failures are silent.** `SaveStore.save` only prints the error, and `GameSession.save()` sets `lastSaved`
   anyway, so with full storage the HUD keeps saying "Saved" and "Save and leave" quits. Return success, warn the
   player, and only show "Saved" when it worked.
7. **Some battle results are only saved after Continue.** A captured monster waiting for a party slot
   (`pendingPet`) lives only in memory, and the boss's rare drop and "defeated" flag run when the result card
   closes. A call or a crash on the result card loses them. Roll them before the victory's save; persist the
   waiting companion.
8. **The save format is fragile for updates.** Synthesized `Codable` makes every non-optional field required
   (`SaveData.version`, `MonsterSighting.defeated`, `Adventurer.id`/`hostile` despite their defaults), and
   `SaveStore.all()` drops a save it can't decode with `try?`. One new non-optional field in an update would hide
   every player's game from the title screen. Write `init(from:)` with `decodeIfPresent`, and add a test that
   decodes a saved 0.3.x file.
9. **Quest gates can be walked round, and some roads are level cliffs.** Windswept Downs → Pineapple Shore and Swan
   Lake → Snow White Forest have no gate while other roads into the same maps do. Ungated roads jump from Frog
   Swamp (21-35) to Ingothold Lake (58-72), from Ingothold Lake to Briarmere (135-155) and from Moonwhisper
   (85-105) to Whispering Hollow (165-185). Either gate every road in (and have `check_content.py` check it) or
   drop the barricades and show recommended levels.
10. **Quest rewards are out of scale.** The Elder, Chief and Mayor chain pays 6-15% of a level (The Rat King: 900
    EXP at level 45, 9%; Who's Afraid of the Big Bad Wolf?: 3,000 at 82, 9%), while newer quests pay 21-124% (The
    Wandering Flock: 88%). Aim for 0.5-1× a level at `minLevel` (more for bosses) and add a ratio check to
    `check_content.py`.
11. **The late game thins out.** Gear stops at level 105 for weapons, 78 for armour and 58 for accessories while
    levels run to 200 (Snow Cloak ends up on every late hero and bot), and late maps reuse low-EXP species, so
    *est.* 25-30 fights per level at 160-180 against 4-6 before 100. Extend the gear lines (free `derive`
    recolours) and add a per-map EXP multiplier.
12. **Classes run out of things to learn.** Mage attack spells cover fire, earth and wood only, so there's no
    weak-spot spell for 72 of 105 species or the final Emerald Dragon (wood). Fighters have 5 skills (last at 40)
    and Tamers 6, so their points pile up after about level 50-60. Advanced classes (below) fix this properly.
13. **Selling takes one tap, with no confirmation**, and when a stack runs out the next row slides under your
    finger, so the next tap sells something else. Keep sold-out rows in place until the panel reopens; confirm
    for gear and gems.
14. **Layout.** The guild's "This choice is permanent" row, the smith's weapon tabs, the adventurer card in danger
    zones and the first quest's three answers don't fit in some languages; in landscape the world map's close
    button is cut off and the NPC bubble sits under the Dynamic Island.
15. **"Leave {name} behind" deletes the companion for good**, with no confirmation (`GameSession.leaveBehind`).
    Say "Release" and confirm.
16. **Rare soft-lock.** With five companions the starter egg can't hatch and there's no release button, which
    blocks Hope of Meadowbrook (a hatch quest) and the Elder's quests after it.
17. **The English tagline is part of the logo** ("a cozy pixel adventure" in `Logo.png`), shown in every
    language. It's already a translated string: draw it as text under the art.
18. **The music synth runs all the time**, muted or not (*est.* a few % of a core for the whole session). Stop the
    engine while muted or at volume 0.

### Low

- Losing a fight doesn't write the companion's damage back (`syncParty()` isn't called on defeat).
- Revive spends its MP when its target was already revived; potions can be used on full-HP targets and show
  "+0 MP".
- No Dynamic Type, several tap targets under 44 pt (the minimap's music toggle sits next to its ✕), and looping
  pulses that ignore Reduce Motion.
- `L()` replaces placeholders one at a time, so a hero named "{level}" gets substituted.
- Backgrounding mid-battle saves the potions and Seal Stones already used without the fight's progress.
- A battle or map change can start while a dialog is open; a pinch starts a walk; tap-walking cuts tree corners.
- Walking up or down covers twice the ground per second as walking sideways (the joystick moves in screen points),
  so encounters come twice as often.
- `UIRequiresFullScreen` is deprecated and does nothing for an iPhone-only app.

## Gamification and new mechanics

Fix High 1 and 2 first: dying in the first ten minutes loses more players than any reward system wins back. The
rest is ranked by value for effort, built on Fairyland Online's own systems where it had them
(`docs/fairyland-online.md`), and all of it works offline. Keep it cozy: gifts rather than punishing streaks, and
no loot boxes, energy timers or paid currency.

**Before launch (small):**

1. **Titles that double as achievements.** FO had collectable titles (Rose Queen, War Hero, crafting and seasonal
   ones). `SaveData` already records bosses beaten, the Monster Book, maps visited, quests, rebirths and friends,
   so existing saves earn theirs on day one. A chosen title shows under the name, and bots wear them too.
   `content/titles.json` (translated through `fields.json`); Game Center achievements can mirror it later.
2. **Monster Book milestones.** Rewards at 10, 25, 50, 75 and all 105 species, plus element sets; FO numbered every
   pet in its collections. A long goal the game already counts.
3. **A daily bounty board and a small daily gift**, on the element calendar the game already runs: a few
   level-scaled tasks per day ("defeat 8 water monsters", "seal a rare") with a town board to collect from. The
   main reason to come back on day 2 and day 7.
4. **Rebirth worth doing.** Today a reborn hero keeps worn gear and gains about 4% of stats at 200 for re-climbing
   1.69M EXP. Give each rebirth a title, a name colour and bonus skill points (FO had rebirth and fame).

**Soon after launch:**

5. **Seasonal events.** Halloween falls in the launch window: a dated `content/events.json`, a sighting boost, a
   recoloured outfit via `derive` and an event title.
6. **Opt-in local notifications** for the daily board and rare sightings. No server needed.
7. **Cards and dolls** (FO): monster drops collected in the Book, with set bonuses.

**Bigger (1.1 and on), already on the roadmap in `docs/fairyland-online.md`:**

8. **Companion intimacy and fusions** (FO's Arms, Armor, Magic and Soul at 30, 50, 60 and 80): a reason to raise a
   favourite, and a way to grow strong without leaning on bot friends.
9. **Advanced classes at level 60** (FO), each new skill with its own animation: fills the empty skill points and
   the late game.
10. **Work skills feeding the smith** (FO's woodcutting, mining and others), and a forging fee as a gold sink.
11. **Hall of Fame and leaderboards**, ranked against the bots, who keep growing; later a weekly guild contest
    modelled on FO's Kingdom Wars.

## Sources

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- App preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
- App information (Privacy Policy URL, China mainland, Vietnam):
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version information (Support URL, copyright, review contact):
  https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Age ratings: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Required-reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
