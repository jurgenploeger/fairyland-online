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
        check(npc["role"] in ("healer", "shop", "quests", "guild", "chest", "boss", "smith"), f"npc {npc['id']} → unknown role {npc['role']}")
        for item in npc.get("stock", []):
            check(item in items, f"shop {npc['id']} → unknown item {item}")
        if npc["role"] == "chest":
            check(npc.get("gives") in items, f"chest {npc['id']} → unknown item {npc.get('gives')}")
        if npc["role"] == "boss":
            check(monsters.get(npc.get("monster"), {}).get("boss") is True, f"boss {npc['id']} → unknown boss {npc.get('monster')}")

for item in items.values():
    if item.get("art"):
        check(item["art"] in art, f"item {item['id']} → unknown art {item['art']}")
        check((ROOT / "art" / "sprites" / f"{item['art']}.png").exists() or "derive" in art.get(item["art"], {}),
              f"item {item['id']} → art/sprites/{item['art']}.png is missing (python3 tools/item_art.py)")

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
