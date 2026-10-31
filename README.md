# RoPlague

A Roblox game: start a plague in one real country, spread it across the world's 174 countries, evolve it
with DNA and race the cure. Multiplayer is RoWorld's war mode.

## Licence

RoPlague is a modified version of [RoWorld](https://github.com/lukechatton/roworld) (© 2026 Snick Co.),
itself a modified version of [OpenFront](https://github.com/openfrontio/OpenFrontIO)
(© OpenFront and Contributors). RoPlague's changes, made from 2026-10-25 on, are © 2026 the RoPlague
developers.

RoPlague is free software under the GNU Affero General Public License, version 3, with the additional
terms in [LICENSE](LICENSE). It comes with ABSOLUTELY NO WARRANTY.

RoPlague is not affiliated with or endorsed by OpenFront, RoWorld or Ndemic Creations.

## Credits

- Maps from Natural Earth and NOAA ETOPO1 data (public domain).
- Country flags from Wikimedia Commons (public domain).
- Music by Rodrigo Flores (Orchestral Ambients), licensed under CC BY 4.0.
- Sound effects: public Roblox Creator Store audio, played by asset id; each one and its creator are
  listed in `src/shared/Assets/Audio.luau`. The plague sounds are our own (`tools/assets/make_plague_sfx.py`).

## Building

The place is built with [Rojo](https://rojo.space):

```
rojo build default.project.json -o RoPlague.rbxl
```

Tests run with [Lune](https://github.com/lune-org/lune): `lune run tests/<name>.luau`.
