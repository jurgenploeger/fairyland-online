#!/usr/bin/env python3
"""Generate Fairyland art with the Retro Diffusion API.

Reads art/assets.json, sends each asset's `request` to Retro Diffusion and saves the
first image as art/sprites/<id>.png, which the game picks up on its next build.
Every image (and the request that made it) is also kept in art-variants/<id>/.

    python3 tools/rd.py list                        # what's defined / already generated
    python3 tools/rd.py credits                     # remaining balance
    python3 tools/rd.py generate --dry-run          # what it would cost (free)
    python3 tools/rd.py generate                    # every missing sprite
    python3 tools/rd.py generate tree --force --variants 4
    python3 tools/rd.py use tree art-variants/tree/20260929-120000_2.png

Needs RETRO_DIFFUSION_API_KEY in the environment or in .env (see .env.example).
Standard library only — no pip install needed.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

API = "https://api.retrodiffusion.ai/v2"
ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
MANIFEST = ART / "assets.json"
SPRITES = ART / "sprites"
VARIANTS = ROOT / "art-variants"
LEDGER = ART / "spend-log.jsonl"   # one line per paid generation, read by the budget dashboard
POLL_SECONDS = 2
TASK_TIMEOUT_SECONDS = 600


class APIError(Exception):
    pass


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text())


def api_key() -> str:
    key = os.environ.get("RETRO_DIFFUSION_API_KEY", "").strip()
    env_file = ROOT / ".env"
    if not key and env_file.exists():
        for line in env_file.read_text().splitlines():
            name, _, value = line.partition("=")
            if name.strip() == "RETRO_DIFFUSION_API_KEY":
                key = value.strip().strip("\"'")
    if not key or key == "rdpk-...":
        sys.exit(
            "Missing RETRO_DIFFUSION_API_KEY. Copy .env.example to .env and paste your key "
            "from https://www.retrodiffusion.ai/app/devtools"
        )
    return key


def call(method: str, path: str, key: str, body: dict | None = None, idempotency_key: str | None = None) -> dict:
    headers = {"X-RD-Token": key, "Accept": "application/json", "User-Agent": "fairyland-art-pipeline/1.0"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if idempotency_key:
        # Same key on every retry, so a retried paid request is never charged twice.
        headers["Idempotency-Key"] = idempotency_key

    for attempt in range(6):
        request = urllib.request.Request(API + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            if error.code == 429 or error.code >= 500:
                delay = retry_after(error, attempt)
                print(f"  {error.code} from Retro Diffusion, retrying in {delay:.0f}s…")
                time.sleep(delay)
                continue
            raise APIError(f"{method} {path} → HTTP {error.code}: {detail}") from None
        except urllib.error.URLError as error:
            delay = 2**attempt
            print(f"  network error ({error.reason}), retrying in {delay}s…")
            time.sleep(delay)
    raise APIError(f"{method} {path} kept failing, giving up")


def retry_after(error: urllib.error.HTTPError, attempt: int) -> float:
    try:
        return float(error.headers.get("Retry-After"))
    except (TypeError, ValueError):
        return float(2**attempt)


def submit(payload: dict, key: str) -> dict:
    """POST an inference and wait for its result."""
    if payload.get("check_cost"):
        # Free cost checks are answered inline, and the API rejects an Idempotency-Key on them.
        return call("POST", "/inferences", key, payload)
    accepted = call("POST", "/inferences", key, {**payload, "async": True}, idempotency_key=str(uuid.uuid4()))
    if "task_id" not in accepted:
        return accepted
    deadline = time.monotonic() + TASK_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        task = call("GET", f"/inferences/tasks/{accepted['task_id']}", key)
        if task.get("status") == "succeeded":
            return task["result"]
        if task.get("status") == "failed":
            raise APIError(f"generation failed: {task.get('error')}")
        time.sleep(POLL_SECONDS)
    raise APIError(f"task {accepted['task_id']} timed out")


def png_size(data: bytes) -> tuple[int, int] | None:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def save(asset_id: str, payload: dict, result: dict) -> None:
    images = [base64.b64decode(item) for item in result.get("base64_images", [])]
    if not images:
        raise APIError(f"no images in result: {json.dumps(result)[:300]}")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    folder = VARIANTS / asset_id
    folder.mkdir(parents=True, exist_ok=True)
    for index, image in enumerate(images):
        extension = "gif" if image[:4] == b"GIF8" else "png"
        (folder / f"{stamp}_{index}.{extension}").write_bytes(image)
    meta = {"request": payload, "result": {k: v for k, v in result.items() if k != "base64_images"}}
    (folder / f"{stamp}.json").write_text(json.dumps(meta, indent=2))
    log_spend(asset_id, payload, result, datetime.now())

    first = images[0]
    size = png_size(first)
    if size is None:
        print(f"  ! got a non-PNG (GIF?) — for animations set \"return_spritesheet\": true. Kept in {folder.relative_to(ROOT)}/")
        return
    SPRITES.mkdir(parents=True, exist_ok=True)
    (SPRITES / f"{asset_id}.png").write_bytes(first)
    print(
        f"  ✓ art/sprites/{asset_id}.png  {size[0]}×{size[1]}px  "
        f"cost {result.get('balance_cost')}  balance left {result.get('remaining_balance')}"
    )
    if len(images) > 1:
        print(f"    {len(images)} variants in {folder.relative_to(ROOT)}/ — pick one with: python3 tools/rd.py use {asset_id} <file>")


def log_spend(asset_id: str, payload: dict, result: dict, when: datetime) -> None:
    entry = {
        "date": when.isoformat(timespec="seconds"),
        "asset": asset_id,
        "style": payload.get("prompt_style"),
        "size": f"{payload.get('width')}x{payload.get('height')}",
        "images": payload.get("num_images", 1),
        "cost": result.get("balance_cost"),
        "balance": result.get("remaining_balance"),
        "prompt": payload.get("prompt"),
    }
    with LEDGER.open("a") as ledger:
        ledger.write(json.dumps(entry) + "\n")


def touch_art_folder() -> None:
    # Xcode copies art/ as a folder reference; bumping its mtime makes the next build re-copy it.
    for path in (ART, SPRITES):
        os.utime(path)


def select(manifest: dict, ids: list[str]) -> list[dict]:
    assets = manifest["assets"]
    if not ids:
        return assets
    known = {asset["id"]: asset for asset in assets}
    unknown = [i for i in ids if i not in known]
    if unknown:
        sys.exit(f"Unknown asset id(s): {', '.join(unknown)}. Known: {', '.join(known)}")
    return [known[i] for i in ids]


def cmd_list(_: argparse.Namespace) -> None:
    for asset in load_manifest()["assets"]:
        request = asset.get("request")
        generated = (SPRITES / f"{asset['id']}.png").exists()
        if generated:
            mark = "✓"
        elif asset.get("derive"):
            mark = "~"
        else:
            mark = "·"
        if asset.get("derive") and not generated:
            detail = f"derived from {asset['derive']['from']} (free)" + (" · upgradable" if request else "")
        elif request:
            detail = f"{request['prompt_style']:<36} {request.get('width')}×{request.get('height')}"
        else:
            detail = ""
        print(f"{mark} {asset['id']:<22} {asset['kind']:<11} {detail}")
    print("\n✓ generated   ~ derived for free (palette swap)   · using placeholder art")


def cmd_credits(_: argparse.Namespace) -> None:
    credits = call("GET", "/inferences/credits", api_key())
    print(f"Balance: ${credits.get('balance')}  (credits: {credits.get('credits')})")


def cmd_generate(args: argparse.Namespace) -> None:
    manifest = load_manifest()
    key = api_key()
    defaults = manifest.get("defaults", {})
    generated = failed = 0
    total_cost = 0.0

    for asset in select(manifest, args.ids):
        asset_id = asset["id"]
        if "request" not in asset:
            if args.ids:
                print(f"~ {asset_id}: derived from {asset['derive']['from']} for free; add a `request` to generate its own art")
            continue
        if asset.get("derive") and not args.ids:
            # Derived sprites already look fine for free; only generate them when asked by name.
            continue
        if (SPRITES / f"{asset_id}.png").exists() and not args.force:
            print(f"· {asset_id}: already generated (use --force to redo)")
            continue
        payload = {**defaults, **asset["request"]}
        if args.variants:
            payload["num_images"] = args.variants
        if args.dry_run:
            payload["check_cost"] = True
        print(f"→ {asset_id}  {payload['prompt_style']} {payload.get('width')}×{payload.get('height')}  “{payload.get('prompt', '')}”")
        try:
            result = submit(payload, key)
        except APIError as error:
            print(f"  ✗ {error}")
            failed += 1
            continue
        if args.dry_run:
            cost = result.get("balance_cost", result.get("cost"))
            if isinstance(cost, (int, float)):
                total_cost += cost
                print(f"  would cost ${cost}")
            else:
                print(f"  {json.dumps(result)}")
            continue
        try:
            save(asset_id, payload, result)
            generated += 1
        except APIError as error:
            print(f"  ✗ {error}")
            failed += 1

    if args.dry_run:
        print(f"\nEstimated total: ${total_cost:.2f}")
    if generated:
        touch_art_folder()
        print(f"\n{generated} sprite(s) ready — rebuild the app to see them.")
    if failed:
        sys.exit(f"{failed} asset(s) failed.")


def cmd_use(args: argparse.Namespace) -> None:
    select(load_manifest(), [args.id])
    source = Path(args.file)
    if png_size(source.read_bytes()) is None:
        sys.exit(f"{source} is not a PNG")
    SPRITES.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, SPRITES / f"{args.id}.png")
    touch_art_folder()
    print(f"✓ art/sprites/{args.id}.png ← {source}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Retro Diffusion art pipeline for Fairyland")
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("list", help="show assets and which are generated").set_defaults(run=cmd_list)
    commands.add_parser("credits", help="show remaining balance").set_defaults(run=cmd_credits)

    generate = commands.add_parser("generate", help="generate sprites (missing ones by default)")
    generate.add_argument("ids", nargs="*", help="asset ids (default: all)")
    generate.add_argument("--force", action="store_true", help="regenerate even if the sprite exists")
    generate.add_argument("--dry-run", action="store_true", help="only report the cost (free)")
    generate.add_argument("--variants", type=int, metavar="N", help="generate N options to pick from")
    generate.set_defaults(run=cmd_generate)

    use = commands.add_parser("use", help="promote a variant to the game sprite")
    use.add_argument("id")
    use.add_argument("file")
    use.set_defaults(run=cmd_use)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
