"""RoPlague: the experience the product tools work on (create_products, set_product_icons,
check_products, write_product_ids). Each experience has its own manifest of ids, because developer
products and gamepasses belong to one universe and can never be moved.

2026-10-30: the game moved to the group (439068166); the old user-owned universe 10773573507 keeps its
manifest (build/products_manifest_10773573507.json) and is no longer what the code ships.
"""

import os

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
UNIVERSE = 10773823004
GROUP = 439068166
USER = 3007483
MANIFEST = os.path.join(REPO, "build", "products_manifest_%d.json" % UNIVERSE)
