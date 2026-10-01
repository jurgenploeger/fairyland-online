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
    try:
        return json.loads((ROOT / path).read_text())
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
songs = {s["id"] for s in load("content/music.json")["songs"]}
appearance = load("content/appearance.json")
art = {a["id"]: a for a in load("art/assets.json")["assets"]}
npcs = {n["id"]: n for m in maps.values() for n in m.get("npcs", [])}

# Icons are the GameIcon cases, which mirror tools/icons.py.
icon_names = set(re.findall(r'^\s+"([a-z0-9-]+)": \(', (ROOT / "tools/icons.py").read_text(), re.M))

for cls in classes["classes"]:
    for unlock in cls["skills"]:
        check(unlock["skill"] in skills, f"class {cls['id']} → unknown skill {unlock['skill']}")
for race in classes["races"]:
    check(race.get("art", "player_walk") in art, f"race {race['id']} → unknown art {race.get('art')}")

for skill in skills.values():
    check(skill.get("icon") in icon_names, f"skill {skill['id']} → unknown icon {skill.get('icon')}")

for monster in monsters.values():
    check(monster["art"] in art, f"monster {monster['id']} → unknown art {monster['art']}")
    for skill in monster["skills"]:
        check(skill in skills, f"monster {monster['id']} → unknown skill {skill}")
    if "variantOf" in monster:
        check(monster["variantOf"] in monsters, f"monster {monster['id']} → unknown base {monster['variantOf']}")

for item in items.values():
    check(item.get("icon") in icon_names, f"item {item['id']} → unknown icon {item.get('icon')}")

for quest in quests.values():
    check(quest["giver"] in npcs, f"quest {quest['id']} → unknown giver {quest['giver']}")
    objective = quest["objective"]
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
    theme = map_def["theme"]
    town = map_def.get("town") or {}
    tiles = [theme["ground"], theme["path"]] + [theme[k] for k in ("accent", "border", "water") if theme.get(k)]
    if "cave" in theme:
        cave = theme["cave"]
        where = f"map {map_def['id']} cave"
        check(set(cave) <= {"rock", "height", "width", "chambers", "branches"}, f"{where} → unknown keys {set(cave) - {'rock', 'height', 'width', 'chambers', 'branches'}}")
        check("rock" in cave, f"{where} → needs a rock tile")
        tiles.append(cave.get("rock", ""))
        check(isinstance(cave.get("height", 40), (int, float)) and 10 <= cave.get("height", 40) <= 120, f"{where} → height must be 10 to 120")
        check(isinstance(cave.get("width", 3), (int, float)) and 1 <= cave.get("width", 3) <= 8, f"{where} → width must be 1 to 8")
        for key in ("chambers", "branches"):
            check(isinstance(cave.get(key, 0), int) and 0 <= cave.get(key, 0) <= 40, f"{where} → {key} must be a whole number from 0 to 40")
        check(map_def["width"] >= 24 and map_def["height"] >= 24, f"{where} → cave maps must be at least 24×24")
    props = [p["art"] for p in theme["props"]] + town.get("lots", []) + list(town.get("streetDecor", {}))
    props += [b["art"] for b in map_def.get("buildings", [])] + [d["art"] for d in map_def.get("decor", [])]
    for art_id in tiles + props:
        check(art_id in art, f"map {map_def['id']} → unknown art {art_id}")
    for npc in map_def.get("npcs", []):
        check(npc["art"] in art, f"npc {npc['id']} → unknown art {npc['art']}")
        for item in npc.get("stock", []):
            check(item in items, f"shop {npc['id']} → unknown item {item}")
        if npc["role"] == "chest":
            check(npc.get("gives") in items, f"chest {npc['id']} → unknown item {npc.get('gives')}")
        if npc["role"] == "boss":
            check(monsters.get(npc.get("monster"), {}).get("boss") is True, f"boss {npc['id']} → unknown boss {npc.get('monster')}")

hex_colour = re.compile(r"^#[0-9A-Fa-f]{6}$")
for map_def in maps.values():
    for prop in map_def["theme"].get("props", []):
        check(prop["art"] in art, f"map {map_def['id']} prop → unknown art {prop['art']}")
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

ambience_keys = {"particles", "butterflies", "clouds", "tint", "tintAlpha", "vignette", "lightPatches", "sunbeams", "sun", "haze", "hazeAlpha", "foreground"}
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
    if "foreground" in ambience:
        for art_id in ambience["foreground"].get("art", []):
            check(art_id in art, f"{where} foreground → unknown art {art_id}")

for kind in ("hair", "outfits", "skin"):
    for preset in appearance[kind]:
        if "unlock" in preset:
            check(preset["unlock"] in quests, f"look {preset['id']} → unknown quest {preset['unlock']}")

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

if errors:
    print(f"✗ {len(errors)} problem(s):")
    for error in errors:
        print("  •", error)
    sys.exit(1)
print(f"✓ Content OK: {len(maps)} maps, {len(monsters)} monsters, {len(skills)} skills, {len(items)} items, {len(quests)} quests")
