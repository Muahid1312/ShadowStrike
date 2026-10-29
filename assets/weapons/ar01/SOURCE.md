# AR-01 — original ShadowStrike viewmodel

This is an original low-poly model constructed for ShadowStrike using the checked-in `tools/build_rifle_asset.py` script and Blender 4.3.2. No third-party weapon model was downloaded or adapted. The asset search did not produce a model with a verified redistribution licence, so the original-model fallback was used.

`AR01.glb` is the actual exported and imported model. `geometry_stats.json` records Blender triangle counts. Components are batched into static body, curved magazine, support/firing hands and forearms; the named Muzzle/OpticAxis locators are in Godot metres with -Z forward.

The model geometry, PBR material definitions and generated 64×64 muzzle sprite are original project assets; no external weapon/texture attribution is required. They are supplied with the project without introducing a separate third-party model licence. The existing Open Sans heading font was used to bake the small AR-01 marking into mesh geometry; its existing OFL licence is at `assets/fonts/LICENSE.txt`. Existing project rifle/reload audio is reused unchanged.

Rebuild from the repository root:

```bash
blender -b --factory-startup --python tools/build_rifle_asset.py
./tools/godot.sh --headless --editor --import --quit
```

Blender may report that its optional Draco encoder is unavailable. This model intentionally exports as ordinary, uncompressed GLB and does not require Draco at runtime. No textures are used on the weapon's PBR surfaces; edge chamfers, machining, vents, ribs and material roughness/metallic variation provide detail. The small flash sprite is the only new texture.
