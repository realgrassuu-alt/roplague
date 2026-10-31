"""RoPlague: write the ids of build/products_manifest.json (tools/assets/create_products.py) into
src/shared/Data/Products.luau, Strains.luau and Gamepasses.luau. Every id that is not ours (the original
developer's products, their staging copies) becomes 0.

    .venv/Scripts/python.exe tools/assets/write_product_ids.py
"""

import json
import os
import re
import sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
DATA = os.path.join(REPO, "src", "shared", "Data")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from target import MANIFEST  # noqa: E402

m = json.load(open(MANIFEST))


def rw(name, fn):
    p = os.path.join(DATA, name)
    s = open(p, encoding="utf-8").read()
    s2 = fn(s)
    open(p, "w", encoding="utf-8", newline="\n").write(s2)


def products(s):
    def line(mo):
        key = mo.group(1)
        body = mo.group(2)
        ours = m.get(key)
        new_id = str(ours["id"]) if ours else "0"
        body = re.sub(r"id = \d+", "id = " + new_id, body, count=1)
        body = re.sub(r",\s*staging = \d+", "", body)
        return "\t%s = {%s}" % (key, body)

    s = re.sub(r"\t(\w+) = \{(\s*id = \d+[^\n]*?)\}", line, s)
    s = s.replace("staging = f.staging or 0,", "staging = 0,")
    return s


def strains(s):
    def line(mo):
        key = mo.group(1)
        ours = m.get("strain_" + key)
        txt = mo.group(0)
        if ours and "product =" in txt:
            txt = re.sub(r"product = \d+", "product = %d" % ours["id"], txt)
        elif ours:
            txt = txt[:-2].rstrip() + ", product = %d }," % ours["id"]
        return txt

    s = re.sub(r'\{ key = "(\w+)", name = "[^"]+", rarity = "(?:rare|epic|legendary)"[^\n]*\},', line, s)
    hb = m.get("shopset_halloween")
    if hb:
        s = re.sub(r"halloween = \{ product = \d+ \},", "halloween = { product = %d }," % hb["id"], s)
    return s


def passes(s):
    for k, e in m.items():
        if k.startswith("pass:"):
            s = re.sub(r"\b%s = \{ id = \d+" % k[5:], "%s = { id = %d" % (k[5:], e["id"]), s)
    return s


rw("Products.luau", products)
rw("Strains.luau", strains)
rw("Gamepasses.luau", passes)
print("ok")
