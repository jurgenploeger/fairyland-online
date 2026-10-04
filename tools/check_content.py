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

# Icons are the GameIcon cases, which mirror tools/icons.py.
icon_names = set(re.findall(r'^\s+"([a-z0-9-]+)": \(', (ROOT / "tools/icons.py").read_text(), re.M))

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
# Styles anyone can wear, and a sheet's own hair (a gender's), worn only on that walk sheet.
shared = {style["id"] for style in appearance["styles"] if not style.get("sheet")}
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
        worn = sorted(shared) + ([own_style[sheet]] if sheet in own_style else [])
        layers = [f"body_{body}", f"locks_{body}", f"hood_{body}", f"helmet_{body}"] + [f"hair_{style}_{body}" for style in worn]
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
        spread = prop.get("spread", 1)
        check(isinstance(spread, int) and spread > 0, f"map {map_def['id']} prop {prop['art']} → spread must be a positive whole number")

rule_keys = {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue", "to", "shift", "saturation", "value"}
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
    for rule in palette.get("recolor", []):
        check(set(rule) <= rule_keys, f"{where} → unknown recolor keys {set(rule) - rule_keys}")

ambience_keys = {"particles", "butterflies", "clouds", "tint", "tintAlpha", "vignette", "lightPatches", "sunbeams", "sun", "haze", "hazeAlpha", "foreground", "focus"}
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
        check(kind in {"petals", "leaves", "fireflies", "sparkles", "snow", "dust", "motes"}, f"{where} → unknown particles {kind}")
    if "focus" in ambience:
        focus = ambience["focus"]
        check(set(focus) <= {"blur", "band", "near"}, f"{where} focus → unknown keys {set(focus) - {'blur', 'band', 'near'}}")
        check(0 <= focus.get("blur", 1.5) <= 6, f"{where} focus → blur should be 0...6 points")
        check(0 <= focus.get("band", 0.4) <= 0.9, f"{where} focus → band should be 0...0.9")
        check(0 <= focus.get("near", 0.5) <= 1, f"{where} focus → near should be 0...1")
    if "foreground" in ambience:
        for art_id in ambience["foreground"].get("art", []):
            check(art_id in art, f"{where} foreground → unknown art {art_id}")

for kind in ("hair", "outfits", "skin"):
    for preset in appearance[kind]:
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

if errors:
    print(f"✗ {len(errors)} problem(s):")
    for error in errors:
        print("  •", error)
    sys.exit(1)
print(f"✓ Content OK: {len(maps)} maps, {len(monsters)} monsters, {len(skills)} skills, {len(items)} items, {len(quests)} quests")
