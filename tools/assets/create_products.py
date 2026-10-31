"""RoPlague: create our developer products and gamepasses in OUR experience (tools/assets/target.py), with
their store icons (tools/assets/make_product_icons.py), and record every id in
build/products_manifest.json the moment it exists. Dev products can never be deleted, so a key already in
the manifest is never created again: re-running only makes what is missing.

Runs with the talon-spoofer venv (Open Cloud key in its keyring, never printed):
    C:/Users/PC/Desktop/talon-spoofer/.venv/Scripts/python.exe tools/assets/create_products.py [--dry]
"""

import argparse
import asyncio
import json
import os
import re
import sys

sys.path.insert(0, r"C:\Users\PC\Desktop\talon-spoofer\src")
from talon_spoofer.core import assets, dev_products, gamepasses  # noqa: E402
from talon_spoofer.core.auth import AuthBundle  # noqa: E402
from talon_spoofer.core.client import RobloxClient  # noqa: E402
from talon_spoofer.core.models import DevProduct, GamePass  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from target import MANIFEST, REPO, UNIVERSE, USER  # noqa: E402
ICONS = os.path.join(REPO, "build", "product_icons")
PRICES = {"rare": 49, "epic": 99, "legendary": 149}

PRODUCTS = [
    ("unlock_head_start", "Head Start", 29, "Start every match with 6 extra DNA."),
    ("unlock_bubble_magnet", "Bubble Magnet", 49, "DNA bubbles appear 45 percent more often."),
    ("unlock_super_spreader", "Super Spreader", 59, "Patient zero starts with 250 infected."),
    ("unlock_sea_legs", "Sea Legs", 79, "Send infected ships from the start, and sail further."),
    ("unlock_gene_bank", "Gene Bank", 99, "Every evolution costs 15 percent less DNA."),
    ("unlock_slow_science", "Slow Science", 129, "The cure takes 15 percent longer."),
    ("unlock_mutagen", "Mutagen", 149, "A free evolution at the start of every match."),
    ("unlock_stars2x", "2x Stars", 59, "Every match pays double Stars, forever."),
    ("starter_pack", "Starter Pack", 39, "Super Spreader, Sea Legs and 2x Stars, for good."),
    ("crate", "Cosmetic Crate", 49, "A cosmetic you do not own yet."),
    ("crate_first", "First Cosmetic Crate", 15, "Your first cosmetic crate, at a discount."),
    ("crate3", "3 Cosmetic Crates", 100, "Three cosmetic crates."),
    ("crate10", "10 Cosmetic Crates", 299, "Ten cosmetic crates."),
    ("takeover", "Take Over", 25, "Take over the nation that eliminated you."),
]
BUNDLES = [("shopset_halloween", "Halloween Colours", 199, "All four Halloween infection colours.")]
PASSES = [
    ("rename", "Rename Your Plague", 19, "Give your plague any name you like."),
    ("auto_pop", "Auto Pop Bubbles", 99, "Every bubble pops by itself half a second after it appears: DNA, cure and hotspots."),
]


def strains():
    src = open(os.path.join(REPO, "src", "shared", "Data", "Strains.luau"), encoding="utf-8").read()
    out = []
    for m in re.finditer(r'\{\s*key = "(\w+)",\s*name = "([^"]+)",\s*rarity = "(\w+)".*', src):
        k, name, rarity = m.groups()
        # (crate colours come out of crates only: never a product of their own)
        if rarity in PRICES and "crate = true" not in m.group(0):
            out.append(("strain_" + k, name + " Infection", PRICES[rarity],
                        "Your plague turns %s on the map." % name))
    return out


NO_ICON = True


def load():
    if os.path.exists(MANIFEST):
        return json.load(open(MANIFEST))
    return {}


def save(m):
    json.dump(m, open(MANIFEST, "w"), indent=1, sort_keys=True)


async def main(dry, limit=0):
    m = load()
    items = PRODUCTS + strains() + BUNDLES
    todo = [it for it in items if it[0] not in m] + [("pass:" + p[0],) + p[1:] for p in PASSES if "pass:" + p[0] not in m]
    if limit > 0:
        todo = todo[:limit]
    print("to create:", len(todo), [t[0] for t in todo])
    if dry:
        return
    async with RobloxClient(AuthBundle.from_keyring(), timeout=120.0) as c:
        for key, name, price, desc in todo:
            icon_key = key.replace("pass:", "").replace("shopset_halloween", "strain_bloodmoon")
            path = os.path.join(ICONS, icon_key + ".png")
            icon = None
            # (the store icon goes on afterwards with set_product_icons.py: an icon asset id given at
            # creation is ignored, so uploading one here only spends the upload quota)
            if os.path.exists(path) and not NO_ICON:
                try:
                    icon = await assets.upload_icon(c, path, creator_user_id=USER, display_name=name[:50])
                except Exception as e:  # an icon is nice to have, never worth stopping for
                    print("  icon failed for", key, ":", str(e)[:160])
            if key.startswith("pass:"):
                gp = await gamepasses.create(c, GamePass(universe_id=UNIVERSE, name=name, description=desc,
                                                          price_in_robux=price, icon_asset_id=icon))
                m[key] = {"id": gp.id, "icon": icon, "robux": price}
            else:
                p = await dev_products.create(c, DevProduct(universe_id=UNIVERSE, name=name, description=desc,
                                                             price_in_robux=price, icon_asset_id=icon))
                m[key] = {"id": p.id, "icon": icon, "robux": price}
            save(m)
            print("  made", key, m[key]["id"])
            await asyncio.sleep(0.6)
    print("done:", len(m), "in the manifest")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    asyncio.run(main(a.dry, a.limit))
