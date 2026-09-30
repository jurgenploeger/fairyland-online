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

for map_def in maps.values():
    for prop in map_def["theme"].get("props", []):
        check(prop["art"] in art, f"map {map_def['id']} prop → unknown art {prop['art']}")
        within = prop.get("within", 1)
        check(isinstance(within, int) and within > 0, f"map {map_def['id']} prop {prop['art']} → within must be a positive whole number")
        spread = prop.get("spread", 1)
        check(isinstance(spread, int) and spread > 0, f"map {map_def['id']} prop {prop['art']} → spread must be a positive whole number")

hex_colour = re.compile(r"^#[0-9A-Fa-f]{6}$")
rule_keys = {"hue", "minSaturation", "maxSaturation", "minValue", "maxValue", "to", "shift", "saturation", "value"}
for map_def in maps.values():
    palette = map_def["theme"].get("palette")
    if not palette:
        continue
    where = f"map {map_def['id']} palette"
    check(set(palette) <= {"recolor", "saturation", "shadow", "highlight", "tone", "glow"}, f"{where} → unknown keys {set(palette) - {'recolor', 'saturation', 'shadow', 'highlight', 'tone', 'glow'}}")
    for key in ("shadow", "highlight"):
        if key in palette:
            check(bool(hex_colour.match(palette[key])), f"{where} → {key} must be a #RRGGBB colour")
    for key in ("saturation", "tone", "glow"):
        if key in palette:
            check(isinstance(palette[key], (int, float)) and 0 <= palette[key] <= 2, f"{where} → {key} must be between 0 and 2")
    for rule in palette.get("recolor", []):
        check(set(rule) <= rule_keys, f"{where} → unknown recolor keys {set(rule) - rule_keys}")

for kind in ("hair", "outfits", "skin"):
    for preset in appearance[kind]:
        if "unlock" in preset:
            check(preset["unlock"] in quests, f"look {preset['id']} → unknown quest {preset['unlock']}")

for asset in art.values():
    if "derive" in asset:
        check(asset["derive"]["from"] in art, f"art {asset['id']} → unknown base {asset['derive']['from']}")

if errors:
    print(f"✗ {len(errors)} problem(s):")
    for error in errors:
        print("  •", error)
    sys.exit(1)
print(f"✓ Content OK: {len(maps)} maps, {len(monsters)} monsters, {len(skills)} skills, {len(items)} items, {len(quests)} quests")
