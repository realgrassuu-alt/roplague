"""RoPlague: put the store icons (build/product_icons, tools/assets/make_product_icons.py) on our developer
products and gamepasses. Open Cloud wants the image itself in the update form ("imageFile" for a
product, "file" for a gamepass); an icon asset id given at creation is silently ignored. Only the image
is sent (PATCH is partial: names, prices and descriptions are untouched).

    C:/Users/PC/Desktop/talon-spoofer/.venv/Scripts/python.exe tools/assets/set_product_icons.py [--only key,key]
"""

import argparse
import asyncio
import json
import os
import sys

sys.path.insert(0, r"C:\Users\PC\Desktop\talon-spoofer\src")
from talon_spoofer.core.auth import AuthBundle  # noqa: E402
from talon_spoofer.core.client import RobloxClient  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
ICONS = os.path.join(REPO, "build", "product_icons")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from target import MANIFEST, UNIVERSE  # noqa: E402
PRODUCT = "https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products/{id}"
PASS = "https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes/{id}"


def icon_for(key):
    k = key.replace("pass:", "").replace("shopset_halloween", "strain_bloodmoon")
    return os.path.join(ICONS, k + ".png")


async def main(only):
    m = json.load(open(MANIFEST))
    async with RobloxClient(AuthBundle.from_keyring(), timeout=120.0) as c:
        for key, e in sorted(m.items()):
            if only and key not in only:
                continue
            path = icon_for(key)
            if not os.path.exists(path):
                print("  no icon for", key)
                continue
            data = open(path, "rb").read()
            if key.startswith("pass:"):
                url, field = PASS.format(u=UNIVERSE, id=e["id"]), "file"
            else:
                url, field = PRODUCT.format(u=UNIVERSE, id=e["id"]), "imageFile"
            r = await c.request("PATCH", url, auth_mode="api_key", files={field: (os.path.basename(path), data, "image/png")})
            print("  %s %s %s" % (key, r.status_code, r.text[:120].replace("\n", " ")))
            await asyncio.sleep(0.5)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    asyncio.run(main(set(k for k in a.only.split(",") if k)))
