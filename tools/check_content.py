#!/usr/bin/env python3
"""Checks content/*.json and art/assets.json for broken references, without Xcode.

The Swift tests (FairylandTests) check the same things, but they need a Mac. This runs
anywhere with Python 3 — handy from a cloud session or a phone — so a push that Xcode Cloud
will build doesn't fail on a typo in the game data.

    python3 tools/check_content.py
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors: list[str] = []


def load(path: str) -> dict:
    def no_duplicates(pairs):
        # A key twice in one object is easy to miss after a merge, and only one of them counts.
        keys = [key for key, _ in pairs]
        for key in {key for key in keys if keys.count(key) > 1}:
            errors.append(f"{path}: \"{key}\" appears twice in one object ({dict(pairs).get('id', '?')})")
        return dict(pairs)
    try:
        return json.loads((ROOT / path).read_text(), object_pairs_hook=no_duplicates)
    except json.JSONDecodeError as error:
        sys.exit(f"{path}: invalid JSON ({error})")


def check(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


classes = load("content/classes.json")
skills = {s["id"]: s for s in load("content/skills.json")["skills"]}
# The stats spells raise and lower in battle (BattleStat in Fairyland/Battle/BattleEngine.swift).
BATTLE_STATS = {"attack", "defense", "magic", "speed"}
monsters = {m["id"]: m for m in load("content/monsters.json")["monsters"]}
items = {i["id"]: i for i in load("content/items.json")["items"]}
quests = {q["id"]: q for q in load("content/quests.json")["quests"]}
maps_file = load("content/maps.json")
maps = {m["id"]: m for m in maps_file["maps"]}
music = load("content/music.json")
songs = {s["id"] for s in music["songs"]}
instruments = {i["id"]: i for i in music.get("instruments", [])}
appearance = load("content/appearance.json")
art = {a["id"]: a for a in load("art/assets.json")["assets"]}
npcs = {n["id"]: n for m in maps.values() for n in m.get("npcs", [])}

# Icons are the GameIcon cases: what tools/icons.py put in the asset catalog (Iconaut's and our own).
icon_names = {path.name.removeprefix("icon-").removesuffix(".imageset")
              for path in (ROOT / "Fairyland/Resources/Assets.xcassets/Icons").glob("icon-*.imageset")
              if not path.name.endswith("-16.imageset")}

for cls in classes["classes"]:
    for unlock in cls["skills"]:
        check(unlock["skill"] in skills, f"class {cls['id']} → unknown skill {unlock['skill']}")
gender_ids = {g["id"] for g in appearance.get("genders", [])}
check(bool(gender_ids), "appearance.json needs a genders list")
for race in classes["races"]:
    check(race.get("art", "player_walk") in art, f"race {race['id']} → unknown art {race.get('art')}")
    for gender, sheet in (race.get("sheets") or {}).items():
        check(gender in gender_ids, f"race {race['id']} → unknown gender {gender}")
        check(sheet in art, f"race {race['id']} ({gender}) → unknown art {sheet}")
# Every style fits every race and gender; a sheet's own hair (a gender's) is the one it starts with.
shared = {style["id"] for style in appearance["styles"] if not style.get("sheet")}
every_style = sorted(style["id"] for style in appearance["styles"])
own_style = {style["sheet"]: style["id"] for style in appearance["styles"] if style.get("sheet")}
hero_sheets = {race.get("art", "player_walk") for race in classes["races"]} | {
    sheet for race in classes["races"] for sheet in (race.get("sheets") or {}).values()}
for style in appearance["styles"]:
    if style.get("sheet"):
        check(style["sheet"] in hero_sheets, f"hairstyle {style['id']} → sheet {style['sheet']} isn't a race's walk sheet")
check(len(own_style) == sum(1 for style in appearance["styles"] if style.get("sheet")),
      "appearance styles → one style of its own per walk sheet at most")
for race in classes["races"]:
    check(race.get("hair") in shared, f"race {race['id']} → hairstyle {race.get('hair')} must be one anyone can wear")
    # The paper-doll layers the hero is stacked from (GameSession.layers): one set per walk sheet,
    # the race's own plus one for each gender with its own sheet.
    bodies = [(race["id"], race.get("art", "player_walk"))] + [
        (f"{race['id']}_{gender}", sheet) for gender, sheet in (race.get("sheets") or {}).items()]
    for body, sheet in bodies:
        layers = [f"body_{body}", f"locks_{body}", f"hood_{body}", f"helmet_{body}"] + [f"hair_{style}_{body}" for style in every_style]
        for layer in layers:
            check((ROOT / "art" / "sprites" / f"{layer}.png").exists(),
                  f"race {race['id']} → art/sprites/{layer}.png is missing (python3 tools/hero_layers.py)")

for monster in monsters.values():
    for drop in monster.get("drops", []):
        check(drop.get("item") in items and 0 < drop.get("chance", 0) <= 1,
              f"monster {monster['id']} → drop {drop} needs a known item and a chance in (0, 1]")

for skill in skills.values():
    check(skill.get("icon") in icon_names, f"skill {skill['id']} → unknown icon {skill.get('icon')}")
    if skill.get("art"):
        check(skill["art"] in art, f"skill {skill['id']} → unknown art {skill['art']}")
        check((ROOT / "art" / "sprites" / f"{skill['art']}.png").exists(),
              f"skill {skill['id']} → art/sprites/{skill['art']}.png is missing (python3 tools/skill_art.py)")
    check(skill["kind"] in ("physical", "magic", "heal", "revive", "buff", "curse", "field"),
          f"skill {skill['id']} → unknown kind {skill['kind']}")
    # Poison and curses: what a skill leaves on the foes it reaches.
    inflicts = skill.get("inflicts")
    if skill["kind"] == "curse":
        check(inflicts is not None, f"skill {skill['id']} → a curse needs `inflicts` (what it leaves on its target)")
    if inflicts is not None:
        where = f"skill {skill['id']} → inflicts"
        check(isinstance(inflicts, dict) and set(inflicts) <= {"effect", "rounds", "power", "chance", "stats"}, f"{where} has unknown keys")
        effect = inflicts.get("effect") if isinstance(inflicts, dict) else None
        check(effect in ("poison", "curse", "freeze"), f"{where} → effect must be poison, curse or freeze")
        if isinstance(inflicts, dict):
            check(isinstance(inflicts.get("rounds"), int) and 1 <= inflicts["rounds"] <= 6, f"{where} → rounds must be 1 to 6")
            top = 2 if effect == "poison" else 0.5   # a curse never takes more than half (BattleEngine.maxCurse)
            power = inflicts.get("power")
            if effect == "freeze":   # a frozen turn is lost whole: there's nothing to scale
                check(power == 0, f"{where} → a freeze's power must be 0")
            else:
                check(isinstance(power, (int, float)) and 0 < power <= top, f"{where} → power must be above 0 and at most {top}")
            chance = inflicts.get("chance", 1)
            check(isinstance(chance, (int, float)) and 0 < chance <= 1, f"{where} → chance must be in (0, 1]")
            if "stats" in inflicts:
                stats = inflicts["stats"]
                check(effect == "curse", f"{where} → only a curse lowers `stats`")
                check(isinstance(stats, list) and stats and set(stats) <= BATTLE_STATS,
                      f"{where} → stats must be some of {sorted(BATTLE_STATS)}")
        check(skill["kind"] in ("physical", "magic", "curse") and skill["target"] in ("enemy", "allEnemies"),
              f"{where} → only skills aimed at foes leave a poison or curse")
    # Buffs: the stats they raise (and any they lower in return) for a few rounds (BattleEngine.statChanges).
    where = f"skill {skill['id']}"
    if skill["kind"] == "buff":
        raises = skill.get("raises")
        check(isinstance(raises, dict) and raises, f"{where} → a buff needs `raises` (stat → share, 0.25 = +25%)")
        for key, changes in (("raises", raises), ("lowers", skill.get("lowers"))):
            if changes is None:
                continue
            check(isinstance(changes, dict) and set(changes) <= BATTLE_STATS, f"{where} → {key} must name some of {sorted(BATTLE_STATS)}")
            if isinstance(changes, dict):
                for stat, amount in changes.items():
                    check(isinstance(amount, (int, float)) and 0 < amount <= (1 if key == "raises" else 0.5),
                          f"{where} → {key} {stat} must be above 0 and at most {1 if key == 'raises' else 0.5}")
        if isinstance(raises, dict) and isinstance(skill.get("lowers"), dict):
            check(not set(raises) & set(skill["lowers"]), f"{where} → raises and lowers the same stat")
        rounds = skill.get("rounds", 3)
        check(isinstance(rounds, int) and 1 <= rounds <= 6, f"{where} → rounds must be 1 to 6")
        check(skill["target"] in ("ally", "allAllies"), f"{where} → a buff is for your own side (ally or allAllies)")
    else:
        check(not {"raises", "lowers", "rounds"} & set(skill), f"{where} → only buffs have raises, lowers or rounds")

# Every skill used in battle looks like no other (a playtest rule): its own `animation`, one the
# scene knows (BattleScene.castSkill and SkillEffects in Fairyland/Battle).
ANIMATIONS = {
    "slash", "smash", "whirlwind", "fire", "embers", "stone", "mud", "boulder", "leaves", "vine", "water", "bubbles", "frost",
    "wild", "roar", "needles", "web", "bounce", "bite", "shadow_bite", "venom_bite", "gold_spin", "gust", "flash",
    "curse", "glare", "poison", "mist", "first_aid", "heart", "paw", "rain", "revive",
    "bless", "shield", "glow", "ward", "spur", "boost", "rage",
}
seen = {}
for skill in skills.values():
    if skill["kind"] == "field":
        continue
    animation = skill.get("animation")
    check(animation in ANIMATIONS, f"skill {skill['id']} → animation must be one the battle draws: {animation}")
    if animation in seen:
        check(False, f"skill {skill['id']} → animation {animation} is {seen[animation]}'s already: every skill needs its own look")
    seen.setdefault(animation, skill["id"])

for monster in monsters.values():
    check(monster["art"] in art, f"monster {monster['id']} → unknown art {monster['art']}")
    check(isinstance(monster.get("lore"), str) and monster["lore"].strip(), f"monster {monster['id']} needs lore for the Monster Book")
    for skill in monster["skills"]:
        check(skill in skills, f"monster {monster['id']} → unknown skill {skill}")
    if "variantOf" in monster:
        check(monster["variantOf"] in monsters, f"monster {monster['id']} → unknown base {monster['variantOf']}")

materials = {i["id"]: i for i in items.values() if i["type"] == "material"}
for item in items.values():
    check(item.get("icon") in icon_names, f"item {item['id']} → unknown icon {item.get('icon')}")
    if item["type"] == "material":
        check(item.get("material") in ("wood", "metal", "gem", "hide"), f"material {item['id']} → unknown kind {item.get('material')}")
        check(isinstance(item.get("level"), int), f"material {item['id']} needs a level (when monsters start dropping it)")
    for material, count in (item.get("recipe") or {}).items():
        check(material in materials, f"recipe for {item['id']} → {material} isn't a material")
        check(isinstance(count, int) and count > 0, f"recipe for {item['id']} → bad count {count} of {material}")
        if material in materials:
            # Every ingredient has to be droppable by monsters no stronger than the item's own level.
            check(materials[material]["level"] <= max(item.get("level", 1), 1),
                  f"recipe for {item['id']} (Lv {item.get('level', 1)}) → {material} only drops from Lv {materials[material]['level']}")

for quest in quests.values():
    check(quest["giver"] in npcs, f"quest {quest['id']} → unknown giver {quest['giver']}")
    objective = quest["objective"]
    check(objective["type"] in ("defeat", "capture", "reachLevel", "chooseClass", "collect", "hatch"),
          f"quest {quest['id']} → unknown objective type {objective['type']}")
    if objective["type"] == "defeat" and objective.get("target"):
        check(objective["target"] in monsters, f"quest {quest['id']} → unknown monster {objective['target']}")
    for answer in (quest.get("question") or {}).get("answers", []):
        check(answer["egg"] in monsters, f"quest {quest['id']} → unknown egg {answer['egg']}")
    for item in quest["reward"].get("items", []) + quest.get("starterItems", []):
        check(item in items, f"quest {quest['id']} → unknown item {item}")
    for required in quest.get("requires", []):
        check(required in quests, f"quest {quest['id']} → unknown quest {required}")

check(maps_file["start"] in maps, f"start map {maps_file['start']} doesn't exist")
opposite = {"north": "south", "south": "north", "east": "west", "west": "east"}
for map_def in maps.values():
    edges = [exit["edge"] for exit in map_def["exits"]]
    check(len(edges) == len(set(edges)), f"map {map_def['id']} has two exits on one edge")
    for exit in map_def["exits"]:
        destination = maps.get(exit["to"])
        check(destination is not None, f"map {map_def['id']} → unknown map {exit['to']}")
        if destination:
            back = any(e["to"] == map_def["id"] and e["edge"] == opposite[exit["edge"]] for e in destination["exits"])
            check(back, f"map {exit['to']} has no {opposite[exit['edge']]} exit back to {map_def['id']}")
        if "requires" in exit:
            check(exit["requires"] in quests, f"map {map_def['id']} road → unknown quest {exit['requires']}")
    for monster in (map_def.get("encounters") or {}).get("monsters", {}):
        check(monster in monsters, f"map {map_def['id']} → unknown monster {monster}")
    if map_def.get("music"):
        check(map_def["music"] in songs, f"map {map_def['id']} → unknown song {map_def['music']}")
    if map_def.get("battleMusic"):
        check(map_def["battleMusic"] in songs, f"map {map_def['id']} → unknown battle song {map_def['battleMusic']}")
    theme = map_def["theme"]
    town = map_def.get("town") or {}
    tiles = [theme["ground"], theme["path"]] + [theme[k] for k in ("accent", "border", "water") if theme.get(k)]
    if "cave" in theme:
        cave = theme["cave"]
        where = f"map {map_def['id']} cave"
        check(set(cave) <= {"rock", "height", "width", "chambers", "branches", "zigzags", "maze"}, f"{where} → unknown keys {set(cave) - {'rock', 'height', 'width', 'chambers', 'branches', 'zigzags', 'maze'}}")
        check("rock" in cave, f"{where} → needs a rock tile")
        tiles.append(cave.get("rock", ""))
        check(isinstance(cave.get("height", 40), (int, float)) and 10 <= cave.get("height", 40) <= 120, f"{where} → height must be 10 to 120")
        check(isinstance(cave.get("width", 3), (int, float)) and 0.5 <= cave.get("width", 3) <= 8, f"{where} → width must be 0.5 to 8")
        for key in ("chambers", "branches", "zigzags"):
            check(isinstance(cave.get(key, 0), int) and 0 <= cave.get(key, 0) <= 40, f"{where} → {key} must be a whole number from 0 to 40")
        check(isinstance(cave.get("maze", 8), int) and 4 <= cave.get("maze", 8) <= 30, f"{where} → maze must be a junction spacing from 4 to 30")
        check(map_def["width"] >= 24 and map_def["height"] >= 24, f"{where} → cave maps must be at least 24×24")
    props = [p["art"] for p in theme["props"]] + town.get("lots", []) + list(town.get("streetDecor", {}))
    props += [b["art"] for b in map_def.get("buildings", [])] + [d["art"] for d in map_def.get("decor", [])]
    for art_id in tiles + props:
        check(art_id in art, f"map {map_def['id']} → unknown art {art_id}")
    for npc in map_def.get("npcs", []):
        check(npc["art"] in art, f"npc {npc['id']} → unknown art {npc['art']}")
        check(npc["role"] in ("healer", "shop", "quests", "guild", "chest", "boss", "smith"), f"npc {npc['id']} → unknown role {npc['role']}")
        for item in npc.get("stock", []):
            check(item in items, f"shop {npc['id']} → unknown item {item}")
        if npc["role"] == "chest":
            check(npc.get("gives") in items, f"chest {npc['id']} → unknown item {npc.get('gives')}")
        if npc["role"] == "boss":
            check(monsters.get(npc.get("monster"), {}).get("boss") is True, f"boss {npc['id']} → unknown boss {npc.get('monster')}")
            # Its minions come from the map's encounter table.
            if npc.get("minions", 9) > 0:
                check(bool((map_def.get("encounters") or {}).get("monsters")), f"boss {npc['id']} → minions need the map's encounters")
        if "minions" in npc:
            check(npc["role"] == "boss" and isinstance(npc["minions"], int) and 0 <= npc["minions"] <= 9,
                  f"npc {npc['id']} → minions is for bosses, 0 to 9")
        # A boss fight comes in waves (3 unless set): the map's monsters first, the boss last.
        if npc["role"] == "boss" and npc.get("waves", 3) > 1:
            check(bool((map_def.get("encounters") or {}).get("monsters")), f"boss {npc['id']} → waves need the map's encounters")
        if "waves" in npc:
            check(npc["role"] == "boss" and isinstance(npc["waves"], int) and 1 <= npc["waves"] <= 5,
                  f"npc {npc['id']} → waves is for bosses, 1 to 5")
        # What beating a boss means: told the first time you win, and kept in the Monster Book.
        if npc["role"] == "boss":
            check("victory" in npc, f"boss {npc['id']} → needs a victory story (title and story)")
        if "victory" in npc:
            victory = npc["victory"]
            where = f"npc {npc['id']} → victory"
            check(npc["role"] == "boss", f"{where} is for bosses")
            check(isinstance(victory, dict) and set(victory) <= {"title", "story"}, f"{where} has only a title and a story")
            title = victory.get("title") if isinstance(victory, dict) else None
            check(isinstance(title, str) and 0 < len(title.strip()) <= 32, f"{where} → title must be 1 to 32 characters")
            story = victory.get("story") if isinstance(victory, dict) else None
            check(isinstance(story, list) and 1 <= len(story) <= 3
                  and all(isinstance(p, str) and 0 < len(p.strip()) <= 220 for p in story),
                  f"{where} → story must be 1 to 3 paragraphs of up to 220 characters (it fits one card)")

# Every monster can be met somewhere: on a map's encounter table, or standing there as a boss.
met = {monster for m in maps.values() for monster in (m.get("encounters") or {}).get("monsters", {})}
met |= {npc["monster"] for npc in npcs.values() if npc["role"] == "boss" and npc.get("monster")}
for monster_id in monsters:
    check(monster_id in met, f"monster {monster_id} → on no map's encounter table and not a boss, so it can never be met")

for item in items.values():
    if item.get("art"):
        check(item["art"] in art, f"item {item['id']} → unknown art {item['art']}")
        check((ROOT / "art" / "sprites" / f"{item['art']}.png").exists() or "derive" in art.get(item["art"], {}),
              f"item {item['id']} → art/sprites/{item['art']}.png is missing (python3 tools/item_art.py)")

WEARS = {"armor": {"vest", "mail", "plate", "robe", "cloak"}, "accessory": {"boots"}}
for item in items.values():
    if "wear" in item:
        check(item["wear"] in WEARS.get(item["type"], set()),
              f"item {item['id']} → wear {item['wear']!r} doesn't fit a {item['type']} ({sorted(WEARS.get(item['type'], []))})")
    for race_id, sheet in item.get("sheets", {}).items():
        check(item["type"] == "armor" and race_id in {r["id"] for r in classes["races"]},
              f"item {item['id']} → sheets: {race_id!r} isn't a race (or the item isn't armour)")
        check((ROOT / "art" / "sprites" / f"{sheet}.png").exists(), f"item {item['id']} → art/sprites/{sheet}.png is missing")
    for rule in item.get("tint", []):
        check("sheets" in item and isinstance(rule.get("hue"), list) and len(rule["hue"]) == 2,
              f"item {item['id']} → tint rules need a hue: [from, to] (and the item needs sheets)")
    if "pattern" in item:
        check(item["type"] == "armor" and item["pattern"] in {"engraved", "scales", "fur", "runes", "pockets"},
              f"item {item['id']} → pattern {item['pattern']!r} must be engraved | scales | fur | runes | pockets, on armour")
    if "glow" in item:
        check(item["type"] == "weapon" and re.fullmatch(r"#[0-9A-Fa-f]{6}", str(item["glow"])) is not None,
              f"item {item['id']} → glow must be a #RRGGBB colour on a weapon")
        at = item.get("glowAt")
        check(isinstance(at, list) and len(at) == 2 and all(isinstance(v, (int, float)) and 0 <= v <= 32 for v in at),
              f"item {item['id']} → glow needs glowAt: [x, y] inside its 32×32 art")
    if "accent" in item:
        check(isinstance(item["accent"], str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", item["accent"]) is not None,
              f"item {item['id']} → accent must be #RRGGBB")

hex_colour = re.compile(r"^#[0-9A-Fa-f]{6}$")
for map_def in maps.values():
    for prop in map_def["theme"].get("props", []):
        check(prop["art"] in art, f"map {map_def['id']} prop → unknown art {prop['art']}")
        # Required by the app's PropPlacement: a missing one stops maps.json loading and crashes at launch.
        check(isinstance(prop.get("count"), int) and not isinstance(prop.get("count"), bool), f"map {map_def['id']} prop {prop['art']} → needs a whole-number count")
        check(isinstance(prop.get("blocking"), bool), f"map {map_def['id']} prop {prop['art']} → needs blocking: true or false")
        within = prop.get("within", 1)
        check(isinstance(within, int) and within > 0, f"map {map_def['id']} prop {prop['art']} → within must be a positive whole number")
        size = prop.get("size", [1, 1])
        check(isinstance(size, list) and len(size) == 2 and all(isinstance(v, (int, float)) and 0.2 <= v <= 3 for v in size) and size[0] <= size[1],
              f"map {map_def['id']} prop {prop['art']} → size must be [smallest, biggest] between 0.2 and 3")
        if "glow" in prop:
            check(bool(hex_colour.match(prop["glow"])), f"map {map_def['id']} prop {prop['art']} → glow must be a #RRGGBB colour")
        check(isinstance(prop.get("shadow", False), bool), f"map {map_def['id']} prop {prop['art']} → shadow must be true or false")
        for key in ("sway", "bob"):
            check(isinstance(prop.get(key, False), bool), f"map {map_def['id']} prop {prop['art']} → {key} must be true or false")
        spread = prop.get("spread", 1)
        check(isinstance(spread, int) and spread > 0, f"map {map_def['id']} prop {prop['art']} → spread must be a positive whole number")

rule_keys = {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue", "to", "shift", "spread", "saturation", "value"}
def check_rules(rules, where):
    """Recolour rules (Recolor.swift): known keys, a hue window in degrees, and `spread` only with
    `to` and a window narrow enough to have a middle."""
    for rule in rules:
        check(set(rule) <= rule_keys, f"{where} → unknown recolor keys {set(rule) - rule_keys}")
        hue = rule.get("hue")
        check(hue is None or (isinstance(hue, list) and len(hue) == 2 and all(0 <= h <= 360 for h in hue)),
              f"{where} → hue must be [from, to] in degrees")
        check(not ("to" in rule and "shift" in rule), f"{where} → a rule sets the hue (to) or turns it (shift), not both")
        if "spread" in rule and hue:
            width = hue[1] - hue[0] if hue[0] <= hue[1] else hue[1] + 360 - hue[0]
            check("to" in rule and width <= 180 and -1.5 <= rule["spread"] <= 1.5,
                  f"{where} → spread needs `to`, a hue window up to 180 degrees wide and a value from -1.5 to 1.5")
        else:
            check("spread" not in rule, f"{where} → spread needs a hue window to find the middle of")

for map_def in maps.values():
    palette = map_def["theme"].get("palette")
    if not palette:
        continue
    where = f"map {map_def['id']} palette"
    palette_keys = {"recolor", "saturation", "shadow", "highlight", "tone", "glow", "light", "lightStrength", "variation"}
    check(set(palette) <= palette_keys, f"{where} → unknown keys {set(palette) - palette_keys}")
    for key in ("shadow", "highlight", "light"):
        if key in palette:
            check(bool(hex_colour.match(palette[key])), f"{where} → {key} must be a #RRGGBB colour")
    for key in ("saturation", "tone", "glow"):
        if key in palette:
            check(isinstance(palette[key], (int, float)) and 0 <= palette[key] <= 2, f"{where} → {key} must be between 0 and 2")
    for key in ("lightStrength", "variation"):
        if key in palette:
            check(isinstance(palette[key], (int, float)) and 0 <= palette[key] <= 1, f"{where} → {key} must be between 0 and 1")
    check_rules(palette.get("recolor", []), where)

ambience_keys = {"particles", "butterflies", "critters", "birds", "clouds", "tint", "tintAlpha", "vignette", "lightPatches", "sunbeams", "sun", "haze", "hazeAlpha", "foreground", "focus", "darkness", "weather"}
weather_kinds = {"clear", "cloudy", "rain", "storm", "fog", "snow"}
for map_def in maps.values():
    ambience = map_def.get("ambience") or {}
    where = f"map {map_def['id']} ambience"
    check(set(ambience) <= ambience_keys, f"{where} → unknown keys {set(ambience) - ambience_keys}")
    for key in ("tint", "sun", "haze"):
        if key in ambience:
            check(bool(hex_colour.match(ambience[key])), f"{where} → {key} must be a #RRGGBB colour")
    for key in ("lightPatches", "sunbeams"):
        if key in ambience:
            lights = ambience[key]
            check(bool(hex_colour.match(lights.get("color", ""))) and isinstance(lights.get("count"), int), f"{where} → {key} needs a colour and a count")
    for kind in (ambience.get("particles") or "").split("+") if ambience.get("particles") else []:
        check(kind in {"petals", "leaves", "fireflies", "sparkles", "snow", "dust", "motes", "bubbles", "dandelions", "sprinkles", "lanterns", "zzz", "notes"},
              f"{where} → unknown particles {kind}")
    # Required by the app's Ambience.Critter: a missing kind or count stops maps.json loading.
    for critter in ambience.get("critters", []):
        check(critter.get("kind") in {"bunny", "frog", "crab"}, f"{where} critters → kind must be bunny, frog or crab: {critter.get('kind')}")
        count = critter.get("count")
        check(isinstance(count, int) and not isinstance(count, bool) and 1 <= count <= 30, f"{where} critters → count must be 1 to 30")
    if "birds" in ambience:
        check(ambience["birds"] in {"songbirds", "gulls", "bats"}, f"{where} → birds must be songbirds, gulls or bats")
    if "focus" in ambience:
        focus = ambience["focus"]
        check(set(focus) <= {"blur", "band", "near"}, f"{where} focus → unknown keys {set(focus) - {'blur', 'band', 'near'}}")
        check(0 <= focus.get("blur", 1.5) <= 6, f"{where} focus → blur should be 0...6 points")
        check(0 <= focus.get("band", 0.4) <= 0.9, f"{where} focus → band should be 0...0.9")
        check(0 <= focus.get("near", 0.5) <= 1, f"{where} focus → near should be 0...1")
    if "darkness" in ambience:
        dark = ambience["darkness"]
        check(set(dark) <= {"radius", "alpha", "color", "light"}, f"{where} darkness → unknown keys {set(dark) - {'radius', 'alpha', 'color', 'light'}}")
        check(80 <= dark.get("radius", 190) <= 500, f"{where} darkness → radius should be 80...500 points")
        check(0 < dark.get("alpha", 0.9) <= 1, f"{where} darkness → alpha should be above 0, up to 1")
        for key in ("color", "light"):
            if key in dark:
                check(bool(hex_colour.match(dark[key])), f"{where} darkness → {key} must be a #RRGGBB colour")
    if "weather" in ambience:
        weather = ambience["weather"]
        check(isinstance(weather, dict) and set(weather) <= weather_kinds,
              f"{where} weather → keys must be {', '.join(sorted(weather_kinds))}")
        check(all(isinstance(w, (int, float)) and not isinstance(w, bool) and w >= 0 for w in weather.values()),
              f"{where} weather → weights must be numbers, 0 or more")
        check(not weather or sum(weather.values()) > 0, f"{where} weather → some weight above 0 (or {{}} for no sky)")
        check(not (weather and "darkness" in ambience), f"{where} weather → a dark map has no sky")
    if "foreground" in ambience:
        for art_id in ambience["foreground"].get("art", []):
            check(art_id in art, f"{where} foreground → unknown art {art_id}")

for kind in ("hair", "outfits", "skin"):
    for preset in appearance[kind]:
        check_rules(preset["recolor"], f"look {preset['id']}")
        if "unlock" in preset:
            check(preset["unlock"] in quests, f"look {preset['id']} → unknown quest {preset['unlock']}")
# The window hair colours widen to on the hero's hair and locks layers (GameSession.hairLayerRules).
window = appearance.get("hairLayer")
if window is not None:
    hue = window.get("hue")
    check(set(window) <= {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue"},
          f"appearance hairLayer → only a window (hue, saturations, values): {set(window)}")
    check(hue is None or (isinstance(hue, list) and len(hue) == 2 and all(0 <= h <= 360 for h in hue)),
          "appearance hairLayer → hue must be [from, to] in degrees")
    check(all(0 <= window[k] <= 1 for k in window if k != "hue"), "appearance hairLayer → saturations and values are 0...1")

# Road routes: hubs, exit waypoints and trails stay inside the map (offsets from the centre, y north).
for map_def in maps.values():
    half_w, half_h = map_def["width"] // 2, map_def["height"] // 2
    def inside(point, what):
        ok = isinstance(point, list) and len(point) == 2 and abs(point[0]) <= half_w - 5 and abs(point[1]) <= half_h - 5
        check(ok, f"map {map_def['id']} {what} {point} should be [x, y] within {half_w - 5}×{half_h - 5} of the centre")
    if "hub" in map_def: inside(map_def["hub"], "hub")
    for exit in map_def["exits"]:
        for point in exit.get("via", []): inside(point, f"road to {exit['to']} waypoint")
        if "at" in exit:
            limit = (half_h if exit["edge"] in ("east", "west") else half_w) - 5
            check(abs(exit["at"]) <= limit, f"map {map_def['id']} exit to {exit['to']}: at {exit['at']} is off the edge")
    for trail in map_def.get("trails", []):
        inside(trail.get("to"), "trail end")
        for point in trail.get("via", []) + ([trail["from"]] if "from" in trail else []): inside(point, "trail waypoint")

for asset in art.values():
    if "derive" in asset:
        check(asset["derive"]["from"] in art, f"art {asset['id']} → unknown base {asset['derive']['from']}")
        check_rules(asset["derive"]["recolor"], f"art {asset['id']} derive")
for item in items.values():
    check_rules((item.get("recolor") or []) + (item.get("tint") or []), f"item {item['id']}")

# Crowds and announcements: whole-number counts, and only placeholders the game fills in.
crowd = load("content/crowd.json")
check(0 <= crowd.get("botDensity", 1) <= 1, "crowd botDensity → between 0 and 1")
for line in crowd.get("traderLines", []):
    check(("{item}" in line) != ("{buy}" in line), f"crowd traderLines → \"{line}\" needs {{item}} or {{buy}} (one of them)")
    check(set(re.findall(r"\{(\w+)\}", line)) <= {"item", "buy", "price"}, f"crowd traderLines → unknown placeholder in \"{line}\"")
for map_def in maps.values():
    for key, value in (map_def.get("crowd") or {}).items():
        check(key in ("adventurers", "villagers", "traders") and isinstance(value, int) and value >= 0,
              f"map {map_def['id']} crowd → {key}: {value} (adventurers, villagers or traders: a whole number)")
    if (map_def.get("crowd") or {}).get("traders"):
        check(map_def.get("fence") is True, f"map {map_def['id']} crowd → traders stand about a town's main square: towns only")
notices = load("content/announcements.json")
every = notices.get("every", [])
check(len(every) == 2 and 0 < every[0] <= every[1], "announcements every → [shortest, longest] real seconds")
for key in ("dawn", "dusk", "community"):
    check(bool(notices.get(key)), f"announcements → needs some {key} lines")
for map_id, lines in notices.get("arrival", {}).items():
    check(map_id in maps, f"announcements arrival → unknown map {map_id}")
    check(bool(lines), f"announcements arrival {map_id} → needs a line")
placeholders = {"dawn": set(), "dusk": set(), "bossNearby": {"boss", "map"},
                "community": {"bot", "level", "boss", "rare", "item", "map"}}
for key, allowed in placeholders.items():
    for line in notices.get(key, []):
        unknown = set(re.findall(r"\{(\w+)\}", line)) - allowed
        check(not unknown, f"announcements {key} → unknown placeholder {sorted(unknown)} in \"{line}\"")
sighting = notices.get("sighting")
if sighting:
    for field in ("text", "end", "minutes", "boost", "chance"):
        check(field in sighting, f"announcements sighting → needs {field}")
    check(0 <= sighting.get("chance", 0) <= 1, "announcements sighting chance → between 0 and 1")
    check(sighting.get("boost", 1) >= 1 and sighting.get("minutes", 1) >= 1, "announcements sighting → boost and minutes at least 1")

changelog = load("content/changelog.json")["releases"]
versions = [r["version"] for r in changelog]
check(len(versions) == len(set(versions)), "changelog → duplicate version")
for release in changelog:
    check(re.fullmatch(r"\d+\.\d+\.\d+", release["version"]) is not None, f"changelog {release['version']} → not x.y.z")
    check(re.fullmatch(r"\d{4}-\d{2}-\d{2}", release["date"]) is not None, f"changelog {release['version']} → date not YYYY-MM-DD")
    check(bool(release.get("title")) and bool(release.get("notes")), f"changelog {release['version']} → needs a title and notes")
as_tuple = [tuple(int(n) for n in v.split(".")) for v in versions if re.fullmatch(r"\d+\.\d+\.\d+", v)]
check(as_tuple == sorted(as_tuple, reverse=True), "changelog → releases must be newest first")
marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text())
check(bool(changelog) and marketing is not None and marketing.group(1) == versions[0],
      f"changelog top version {versions[0] if versions else None} ≠ MARKETING_VERSION {marketing.group(1) if marketing else None} in project.yml")
# Music: every track names a known instrument (or an old chiptune wave), and every note token parses.
NOTE_TOKEN = re.compile(r"^(-|[A-G][#b]?-?\d(\+[A-G][#b]?-?\d)*|[KSHTCRN](\+[KSHTCRN])*):\d+$")
for inst in instruments.values():
    for partial in inst.get("partials", []):
        check(len(partial) == 3, f"instrument {inst['id']}: partial {partial} needs [ratio, level, decay]")
    check(len(inst.get("partials", [])) <= 8, f"instrument {inst['id']}: at most 8 partials")
    check(len(inst.get("vibrato", [0, 0, 0])) == 3, f"instrument {inst['id']}: vibrato is [depth, rate, delay]")
for song in music["songs"]:
    for index, track in enumerate(song["tracks"]):
        where = f"song {song['id']} track {index}"
        if "instrument" in track:
            check(track["instrument"] in instruments, f"{where} → unknown instrument {track['instrument']}")
        else:
            check(track.get("wave") in ("square", "triangle", "noise"), f"{where}: needs an instrument or a wave")
        for token in track["notes"].split():
            if token != "|":
                check(bool(NOTE_TOKEN.match(token)), f"{where}: bad note {token}")
STEP = {"east": (1, 0), "west": (-1, 0), "north": (0, 1), "south": (0, -1)}
places = {}
for map_def in maps.values():
    world = map_def.get("world")
    if not (isinstance(world, list) and len(world) == 2 and all(isinstance(n, int) for n in world)):
        errors.append(f"map {map_def['id']} → needs \"world\": [east, north] for the world map")
        continue
    check(tuple(world) not in places, f"map {map_def['id']} → world spot {world} already taken by {places.get(tuple(world))}")
    places[tuple(world)] = map_def["id"]
for map_def in maps.values():
    for exit_def in map_def["exits"]:
        a, b = map_def.get("world"), maps.get(exit_def["to"], {}).get("world")
        if a and b:
            dx, dy = STEP[exit_def["edge"]]
            check([a[0] + dx, a[1] + dy] == b,
                  f"map {map_def['id']} {exit_def['edge']} exit → {exit_def['to']} isn't one step {exit_def['edge']} on the world map")

# Translations (content/i18n): every listed language has a table, placeholders survive, and every
# L() in the code has a literal key. Missing translations only show in English, so they're reported
# by `python3 tools/i18n.py status`, not here.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import i18n  # noqa: E402
errors += i18n.check()
check(json.loads((ROOT / "content" / "i18n" / "languages.json").read_text())["languages"][0]["code"] == "en",
      "content/i18n/languages.json → English comes first (it's the fallback)")

if errors:
    print(f"✗ {len(errors)} problem(s):")
    for error in errors:
        print("  •", error)
    sys.exit(1)
print(f"✓ Content OK: {len(maps)} maps, {len(monsters)} monsters, {len(skills)} skills, {len(items)} items, {len(quests)} quests")
