# Fairyland Online: how the original worked, and where we differ

What Fairyland Online (FO) actually did, collected so we stay faithful and "check before inventing new
systems" (CLAUDE.md). Each fact carries a confidence and its sources are listed at the end. When you verify
something new, add it here with its source. When we build or change a system, update its **Us** line.

- **H**: the official LagerNet wiki, or several sources agree.
- **M**: one fan guide or review.
- **?**: unverified. Our own README and PRs are public and turn up in web searches, so they never count as a
  source.

First collected on 2026-10-03 from search-engine snippets of the pages listed under Sources. The cloud
environment couldn't open the pages themselves, so a session that can should re-check anything marked M or ?.

## Tales of Mysteria (2026)

FO is back under LagerNet as **Tales of Mysteria** (ToM). Its account sign-up page is on LagerNet's own
domain (fairyland.lagernet.com/register), its wiki is at talesofmysteria.com/wiki, and Mysteria is the
continent FO is set on. History:
- FO started in Taiwan in 2003.
- The English version ran from 2007 until LagerNet shut it down on 30 December 2019.
- A video from about May 2026, "Fairyland Online 2026 - How to getting reborn in game", shows it running again.

Not to be confused with **Fairyland Journey**, Lager's new 3D game on Steam (2026, turn-based, "Eudemons").

**The ToM wiki hasn't been read yet** (the domain was blocked in the cloud environment). Check these first:
- The `#character` section: the attribute list, points per level, each race's starting spread, the level cap,
  and the rebirth rules (level, cost, what you keep).
- Class list and advanced-class level.
- Pet modes, intimacy thresholds and capture items.
- Anything ToM changed from the 2007–2019 game.

## World

The continent of Mysteria (H):

| Kingdom | Race | Capital | Land |
|---|---|---|---|
| Faerore (north) | elves | Bluebird | forests and lakes |
| Lucca (centre) | humans | Rainbow City | rich plains |
| Graf | dwarves | Goldburg | hills and mines |

The rest of the world map is fairy-tale lands (H):
- 1001 Nights (Baghdad)
- King's New Clothes
- Little Mermaid (Port Pebbles)
- Thumbelina (Dreamland)
- Alice
- Beauty and the Beast (Sheep Horn Village)
- Wizard of Oz (Emerald City)
- Candy House (Grasha Village)
- Island (Cannibal Island)

A second "levels map" shades areas in 20-level bands (1–20, 21–40, …), used to pick the right capture
capsule (H). Mining spots include Ilium, Kars Mountain and Siwa Oasis (H).

**Us:** 30 maps and 4 towns (Meadowbrook, Rainbow City, Bluebird, Goldburg).
- Everyone starts in Meadowbrook, and all three guild masters are there.
- Fairy-tale fields echo the lands: Genie Desert, Lotus Land (with Thumbelina), Candy Mountain, Snow White
  Forest, Emerald Road.
- Candy Mountain is our nod to the Candy House land (Hansel and Gretel's Grasha Village): a sugar path,
  chocolate ponds, lollipops, cotton-candy trees and presents (palette swaps), and candy canes, gumdrops,
  cupcakes and gingerbread houses. Other fields nod to their lands too: flying carpets and genie lamps in
  the Genie Desert (1001 Nights), poppy fields on Emerald Road (Wizard of Oz), giant ladybugs in Lotus Land
  (Thumbelina), and apples in the Snow White Forest.
- The animals about the maps (bunnies, frogs, crabs, birds, gulls, bats) and particles such as lanterns,
  bubbles and Z's are our own whimsy. No source we could reach describes ambient animals in Fairyland Online.
- None of the other towns exist yet: Baghdad, Port Pebbles, Dreamland, Sheep Horn Village, Emerald City,
  Grasha Village.

## Races

Human, Elf and Dwarf (H). Each race has its own spread of the six attributes, which suits it to one of the
three guilds (M): humans are balanced, elves lean to magic and dwarves to attack.

**Us:** the same three. Each has base HP/MP/ATK/DEF/MAG/SPD (`content/classes.json`) and no home capital.

**Hairstyles (our decision, 2026-10-04):**
- Spiky, Long and Crop fit every race and gender.
- Each gender sheet's own hair stays with that sheet: Ponytail (human female), Bob (human other), Swept (elf
  male), Shoulder (elf other), Braids (dwarf female) and Messy (dwarf other).
- The playtester chose this over sharing them. Don't offer them to other genders.

## Attributes

- **Six attributes: STR, CON, DEX, INT, LUK, CHA (H).** Monsters have them too, e.g. the Puppet (wood) has
  Str 15, Con 15, Dex 16, Int 16, Luk 13, Cha 15.
- **Attribute points (AP) to spend at every level-up (M).** One guild guide's early advice: all into CON up to
  level 10. A blademan guide aims for about 60 CON and 30 INT, then balances STR and DEX.
- **What they do (H, from the pet fusion rules below):** STR adds weapon damage, DEX accuracy, CON defence,
  LUK evasion, INT magic power. CHA's effect isn't documented yet.
- **DEX also sets turn speed (M).** A mage guide says mages need 250+ DEX to act before certain monsters.
- **Skill speed (H).** Every skill has a speed order ("Skill Penalty Priority"): orders 1 to 10 add DEX for
  that turn, 11 is neutral, and 12 to 21 subtract more and more. Warrior's Charge is order 1.

**Us:** no attributes and no points.
- HP/MP/ATK/DEF/MAG/SPD = race base + class growth × (level − 1) + gear (`GameSession.swift`).
- Turn order is SPD + a random 0–3.
- Nothing misses and nothing dodges.
- Crits are a flat 8% for ×1.5, physical only.

## Guilds and classes

You join a guild at level 10 and can't leave it (H). Each guild has three classes, and each class becomes an
advanced class at level 60 (H).

| Guild | Home | Classes (level 10) | Advanced (level 60) |
|---|---|---|---|
| Warrior (also called Soldier) | Goldburg | Blademan, Swordman, Axeman | BladeMaster, SwordSage, Berserker |
| Journeyman | Rainbow City | Martial Artist, Beast Master, Trader | Kung Fu Master, Beast Lord, Merchant Prince |
| Diviner | Bluebird | Mage, Acolyte of Light, Acolyte of Dark | ArchMage, Architect of Light, Schemer of Darkness |

What each class does (H unless marked):
- **Blademan:** blade skills that hit a whole row of targets.
- **Swordman:** enhanced damage.
- **Axeman:** damages the target's armour.
- **Martial Artist:** fights bare-handed (gloves as Kung Fu Master), fast hits and damage boosts.
- **Beast Master:** whips and beast lore.
- **Trader:** a weak fighter but good at making money; loots extra gold from defeated enemies and is good at
  crafting.
- **Acolyte of Light** casts light spells; **Acolyte of Dark** casts curses.

**Us:** one class per guild, chosen from the guild masters in Meadowbrook at level 10, and permanent:
- Fighter (Warrior Guild)
- Mage (Diviner Guild)
- Beast Tamer (Journeyman Guild): ×1.6 capture, full EXP share for the companion

No advanced classes.

## Class skills (M)

- **Warrior:** Charge, Rush, Protection, Impact, Double Combo.
- **Mage:** Fireball, Dancing Fountain, Combustion, Spiritual Lance, Flame Hail, Inferno, Meteor Blast.
- **Acolyte of Light (H, from the wiki's skill list):** Recovery, Revive, Bless, Holy Light, Holy Glow,
  Guardianship, Holy Blast, Rain of Grace.
- **Acolyte of Dark:**
  - Curse (level 1, 10 MP): lowers the target's attack, both its damage and its hit rate.
  - Poison (5, 10 MP): the target's HP drops a little every turn. Lethal Poison (20) drops it faster.
  - Fear (10): enemies flee in terror.
  - Vampirism
  - Life Altar
- **Beast Master:** Beast Lore (Observe at lore level 15), Dodge Whip, Animal Training.
- **Beast Lord:** God of Beast Impact.
- **Trader:** Dodge, Hide, Invisible, bribery and collection.

**Us:**
- 20 hero skills.
- Our Mage carries Recovery, Revive, Bless, Holy Glow and Guardianship, which FO gives the Acolyte of Light,
  and Curse (level 12) and Poison (level 25), the Acolyte of Dark's.
- Like FO's Mage, whose list starts with Fireball, ours learns Fire Bolt on joining the guild at level 10
  (since 0.3.17).
- Status effects (since 0.3.14): Guard, Poison and spells that raise or lower stats (since 0.3.41).
  - Poison: HP lost at the end of each round, 3 times, shown as a green number marked "Poison".
  - Raised or lowered stats (ATK, DEF, MAG, SPD) last the round they land in and 3 more. Each change pops
    up over the fighter with its amount ("DEF +40%"), and a blue arrow up or a violet arrow down by the HP
    bar counts the rounds left. A second spell on a stat doesn't stack; the stronger one counts.
  - Buffs, FO's skill names with our own effects (FO's aren't in any source reachable from a cloud session):
    Protection (Fighter 12, one ally DEF +40%), Holy Glow (Mage 40, one ally MAG +30%), Bless (Mage 45, ATK
    and DEF +25%), Guardianship (Mage 60, the whole party DEF +20%) and Animal Training (Beast Tamer 25,
    ATK +20% and SPD +30%). Raises grow with the skill's level like damage, ×1.8 when mastered.
  - Monsters and companions: Boost (ATK +20%; golden hamsters, wood hogs, red bulls, earth lions) and Berserk
    (ATK +30% but DEF −25%; werewolves, fire bears, black kongs), FO's pet skills. They cast them on
    themselves now and then; friends cast theirs on whoever they'd help most.
  - Curse: lowers ATK and MAG by 20% (up to 36% as the skill grows), so hits and heals both weaken. FO's
    Curse lowers attack and its hit rate; we have no hit rate.
  - No Lethal Poison, Fear or cures yet. Every status ends with the battle.
- Monsters use them too: Venom Bite (snakes and widows, 40% chance to poison), Poison Mist (the Poison
  Skeleton, the whole party) and Evil Eye (phantoms and Idreus, a curse).

## Elements

Seven elements: metal, wood, water, fire, earth, dark and light. A matchup changes damage by up to 50% (H).

**Us:** the same seven plus neutral.
- The five-element cycle runs water > fire > metal > wood > earth > water, at ×1.5 (×0.75 the other way).
- Light and dark hit each other for ×1.5.
- Only magic uses elements.
- The hero is always neutral.
- The calendar's months are named after the five elements.

FO's exact chart (the reverse multiplier, light and dark) is still **?**.

## Pets

**Modes (H):**
- Normal: resting in its capsule.
- Combat: fights beside you.
- Walk: follows you around.

**Fusions, unlocked by intimacy (H):**

| Mode | Intimacy | Effect |
|---|---|---|
| Arms | 30 | Fuses into your weapon: damage from the pet's STR, accuracy from its DEX, and your attacks take its element |
| Armor | 50 | Fuses into your armour: defence from its CON, evasion from its LUK, and your defence takes its element |
| Magic | 60 | Fuses with your mind: magic power from its INT, more again for spells of its element |
| Soul | 80 | Fuses with your soul: magic defence and HP/MP regeneration. Temporary; once the pet is exhausted, Soul can't be used for about 10 minutes |

**Upkeep and intimacy (H):**
- The pet you take along feeds on your MP. If you can't spare it, the pet won't come.
- Intimacy grows with feeding and walks, and drops when the pet wanders off screen.

**In battle (H):** you command your pet each round: whom it attacks and which skill it uses. How well it
obeys depends on intimacy:
- At 30, it doesn't always attack the one you pick, and telling it to use a skill can make it attack you or
  a party member.
- At 50, it always does as it's told.

**EXP (H):** only pets in a mode other than Normal or Walk share battle EXP.

**Growth (H):** 7 stat points per level.
- Mostly by element (M): fire leans STR, water DEX, earth CON, metal INT; light pets heal.
- Dark pets grow with INT (H).
- Then by species.

**Skills (M):** learned by species and element as they level, e.g. Boost, Super Boost, Berserk, Heal and
Full Heal.

**Extras (H):**
- **Pet Toys:** 105 toys that add up to 50 points to a stat you choose. Made by Timmy in Baghdad's toy store.
- **Pet Carts:** pets with Push Cart pull a cart you ride in. The cart lowers the encounter rate, raises HP/MP
  regen and adds pet stats. Made by Sole, also in Baghdad.
- **Collections:** every pet has a number in the pet collection and the card collection, and monsters drop
  cards and dolls (the Puppet drops a Puppet Card and a Puppet Doll).

**Getting pets:**
- The first one hatches from an egg in the tutorial quest (H).
- Higher-level and higher-rank pets are harder to capture, so beginners are told to hatch eggs (H).
- Capture uses capsules in level tiers (M): level 1 catches pets of level 1–20 and is sold in the three
  capitals' pet shops; level 2 catches pets up to level 40 and comes from Baghdad's pet shop or quests.

**Us:**
- Up to 5 companions; only the one you bring along follows you, fights and earns EXP (50%, or 100% for a
  Beast Tamer).
- Capture uses one kind of Seal Stone (60 gold, used up only when it works), on the last monster standing at
  20% HP or less.
- Companions grow as species base + growth × (level − 1) and have a fixed skill list.
- Each round, after your own choice, you pick your companion's: Attack, one of its skills, Guard, or Auto (it
  decides itself). It always obeys, since there's no intimacy. A Settings switch leaves it to fight on its own.
- None of the modes, fusions, intimacy, upkeep, toys or carts exist.

## Work skills and crafting (H)

- Working gathers raw materials to sell or craft with.
- Work skills: woodcutting, fishing, hunting, farming and mining. They're learned from quests and level up the
  more you work, and higher levels give better goods.
- Mining needs a Pickaxe and yields coal, copper, bronze, crystal and amethyst ore, among others. Ore feeds
  Metal Working and Gem Cutting, which make equipment.

**Us:** monsters drop wood, metal, hide and gems, and three town smiths forge weapons from them. There's no
gathering and no crafting level, and forging always works. Monsters also drop equipment from up to their own
level (6% a monster at your level, up to 16% above it, 2% well below; rares 35%, bosses always), mostly for
your class (`GameSession.equipmentDrop`).

## Titles, fame and PvP

- **Titles (H):** collectable, e.g. Rose Queen, War Hero, PK Master, crafting maestros, seasonal and
  anniversary titles.
- **Dolls (H):** collectable too.
- **Fame (M):** quests are the main way to earn it.
- **Kingdom Wars (H):** guild-vs-guild PvP.

**Us:** no titles or fame. Duels are with computer-run adventurers in 9 danger zones; a beaten
adventurer drops everything they carry (the goods they'd sell you that day).

## Unverified, or only our own repo says so

- **Equipment drops:** monsters drop equipment, and stronger fights drop better gear. From a playtester's
  memory (2026-10-04); check the rates on the ToM wiki.
- **PK drops:** a player beaten in PvP drops their items. From a playtester's memory (2026-10-04);
  not in any source reachable from a cloud session. Check on the ToM wiki.
- **Level cap 200; rebirth from level 101** (+5 levels per earlier rebirth) for 20,000 gold × (rebirths + 1),
  keeping 8 levels of growth per rebirth. FO does have rebirth (the 2026 video); the numbers are ours.
- **Capture rules:** at 20% HP or less, on the last monster standing.
- **Party size:** more than two people, each bringing their pet, from a playtester's memory (2026-10-04).
  Not found in any source reachable from a cloud session.
  - Us: you and up to four friends, each with a companion.
  - Past five, the battle line splits: people in front, companions in a row behind.
- **Battle layout:** battle rows (the Blademan's row attack suggests there were rows), equipment slots, and
  the full list of status effects.
- **Boss fights in waves:** ours, asked for in playtesting (2026-10-04); whether FO's bosses came in waves
  isn't in any source reachable from a cloud session.
  - Us (since 0.3.18): two waves of the map's monsters, then the boss with its minions. HP and MP carry
    over, each wave stands a few levels closer to the boss's, and the boss always has the highest level.
  - `waves` and `minions` on the boss NPC (content/maps.json) tune it per boss.
- **Fainting in a party:** ours, asked for in playtesting (2026-10-04). How FO handled a player fainting
  mid-fight (whether the others fought on, and where everyone woke up) isn't in any source reachable from a
  cloud session.
  - Us (since 0.3.21): the fight goes on while a friend stands, and a friend who knows Revive wakes you
    first. Whoever is down at the end wakes at their own checkpoint (you get no EXP if your friends won it),
    and friends still standing when you fell wait where the fight was. Waiting friends stay in the party but
    sit out fights until you walk up to them.
- **Bots, moderators and announcements:** ours, asked for in playtesting (2026-10-04). FO's chat channels,
  GM notices and player stalls (players selling under a sign in town) aren't in any source reachable from a
  cloud session; check the ToM wiki.
  - Us (since 0.3.22): computer-run adventurers wear a BOT tag. A moderator (switched on per device with a
    code typed in the chat, `Moderation`) wears MOD and has a World channel that every map's chat shows.
  - Announcements (content/announcements.json) cover dawn and dusk, arrivals, other adventurers' news, and
    rare sightings that really raise a rare monster's odds on its map for 20 minutes.
  - Goldburg's square has market traders under signs, selling their real deals of the day
    (`crowd.traders`). `botDensity` in content/crowd.json thins out every map's bots.
- **Selling products:** Logistics Trading Officers in the three capitals pay more for products than ordinary
  shops.

## Design questions on our side

- Monster skills with an element but physical damage (Golden Spin, Vine Whip, Web Shot, Rock Throw) ignore
  their element. FO lets physical attacks carry one (Arms fusion).
- Finishing `new_friend` lets you walk to all 30 maps (frog_swamp → goldburg_lake → goldburg), so the other
  quest gates can be walked round.
- No gear above level 105, while levels run to 200.

## Roadmap

Each step is its own PR, after a pass over the ToM wiki:
1. The six attributes with points per level, race spreads, hit and dodge from DEX and LUK, and skill speed.
2. FO's nine classes (three per guild), then the advanced classes at level 60. Recovery, Revive and Bless move
   to the Acolyte of Light.
3. Pet modes, intimacy, MP upkeep and the Arms/Armor/Magic/Soul fusions.
4. Capture capsules by level tier and pet shops; a home capital per race, with its guild hall there.
5. Work skills feeding the smith; titles, dolls and cards.

## Sources

Read through search-engine snippets on 2026-10-03:
- LagerNet wiki (fairyland.lagernet.com/wiki):
  - [Pet System](http://fairyland.lagernet.com/wiki/index.php/Pet_System)
  - [Pet List](http://fairyland.lagernet.com/wiki/index.php/Pet_List)
  - [Pet Toys](http://fairyland.lagernet.com/wiki/index.php/Pet_Toys)
  - [Pet Carts](http://fairyland.lagernet.com/wiki/index.php/Pet_Carts)
  - [Dark pets](http://fairyland.lagernet.com/wiki/index.php/Dark_pets)
  - [Puppet](http://fairyland.lagernet.com/wiki/index.php/Puppet)
  - [World Map](http://fairyland.lagernet.com/wiki/index.php/World_Map)
  - [Mining](http://fairyland.lagernet.com/wiki/index.php/Mining)
  - [Skill Penalty Priority](http://fairyland.lagernet.com/wiki/index.php/Skill_Penalty_Priority)
- The whole old wiki was archived by WikiTeam: [Internet Archive](https://archive.org/details/wiki-fairylandlagernetcom_wiki).
- Silent Gaming FairyLand info site:
  - [background story](https://info.fairyland.online/?pg=bgstory)
  - [titles](https://info.fairyland.online/?pg=titles)
  - [work skills](https://info.fairyland.online/?pg=work&sub=mining)
- Ironwolves guild guides:
  - [classes](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/characterclass.php)
  - [new players](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/newplayers.php)
  - [intro to pets](https://wmomusic.org/fl1/Ironwolves2020/Html_Pages/introtopets.php)
  - [blademan](https://wmomusic.org/fl1/Ironwolves2020/Guides/bladesmanguide.php)
  - [mage](https://www.wmomusic.org/fl1/Ironwolves2020/Guides/mageguide.php)
  - [beastmaster](https://wmomusic.org/fl1/Ironwolves2020/Guides/oldbeastmasterguide.php)
  - [trader](https://wmomusic.org/fl1/Ironwolves2020/Guides/oldtraderguide.php)
- Fairyland Fansite: [Diviner skills](http://flguide.blogspot.com/2007/11/diviner-skills.html)
- Ironwolves [Diviner skill list](https://wmomusic.org/fl1/Ironwolves2020/Skill_Pages/skills-diviner.php) (Curse and Poison, read 2026-10-04)
- Overviews and reviews:
  - [MMORPG.com](https://www.mmorpg.com/fairyland-online)
  - [MMO Reviews](https://www.mmoreviews.com/fairyland-online/)
  - [MMO Game Base](http://mmogamebase.blogspot.com/2011/03/fairyland-online.html)
  - [Free Web Game 360](https://freewebgame360.blogspot.com/2013/07/fairyland-online-review.html)
  - [HexMojo](https://www.hexmojo.com/2019/09/a-walk-down-memory-lane-with-fairyland.html)
- Tales of Mysteria:
  - [sign-up page](https://fairyland.lagernet.com/register)
  - [wiki](https://talesofmysteria.com/wiki)
  - [2026 rebirth video](https://www.youtube.com/watch?v=4Fy55bf7a9w)
- [Fairyland Journey on Steam](https://store.steampowered.com/app/4144910/Fairyland_Journey/) (a different game)
