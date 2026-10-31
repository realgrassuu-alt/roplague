"""RoPlague: checks every developer product and gamepass in build/products_manifest.json against Roblox
(Open Cloud, the talon-spoofer keyring key; never printed): it exists in our universe, it is for sale,
its stored price is the one the game sells it at, and it has an icon. Read-only.

    C:/Users/PC/Desktop/talon-spoofer/.venv/Scripts/python.exe tools/assets/check_products.py
"""

import asyncio
import json
import os
import sys

sys.path.insert(0, r"C:\Users\PC\Desktop\talon-spoofer\src")
from talon_spoofer.core.auth import AuthBundle  # noqa: E402
from talon_spoofer.core.client import RobloxClient  # noqa: E402

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from target import MANIFEST, UNIVERSE  # noqa: E402
PRODUCT = "https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products/{id}/creator"
PASS = "https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes/{id}/creator"


def pick(d, *names):
    for n in names:
        if n in d and d[n] is not None:
            return d[n]
    return None


async def main():
    m = json.load(open(MANIFEST))
    bad = 0
    async with RobloxClient(AuthBundle.from_keyring(), timeout=60.0) as c:
        for key, e in sorted(m.items()):
            is_pass = key.startswith("pass:")
            url = (PASS if is_pass else PRODUCT).format(u=UNIVERSE, id=e["id"])
            r = await c.request("GET", url, auth_mode="api_key")
            if r.status_code != 200:
                bad += 1
                print("  FAIL %-24s %s %s" % (key, r.status_code, r.text[:160].replace("\n", " ")))
                continue
            d = r.json()
            price = pick(d, "defaultPriceInRobux", "priceInRobux", "price")
            if isinstance(price, dict):
                price = pick(price, "defaultPriceInRobux", "price")
            pinfo = d.get("priceInformation") or {}
            if price is None and isinstance(pinfo, dict):
                price = pick(pinfo, "defaultPriceInRobux", "price")
            for_sale = pick(d, "isForSale", "forSale")
            icon = pick(d, "iconImageAssetId", "iconAssetId", "displayIconImageAssetId")
            ok = str(price) == str(e["robux"]) and for_sale is not False and icon not in (None, 0, "0")
            if not ok:
                bad += 1
            print(
                "  %s %-24s id %-12s price %-5s (want %-4s) for sale %-5s icon %s"
                % ("ok  " if ok else "FAIL", key, e["id"], price, e["robux"], for_sale, icon)
            )
            if not ok:
                print("       keys:", sorted(d.keys()))
            await asyncio.sleep(0.25)
    print("%d of %d wrong" % (bad, len(m)))


if __name__ == "__main__":
    asyncio.run(main())
