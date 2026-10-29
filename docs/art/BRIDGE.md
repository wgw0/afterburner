# Strait bridge

The bridges from each landmass to the central island are one model, after the **Severn Bridge** (1966): the first
suspension bridge with an aerofoil box-girder deck, and the one with the inclined, zig-zag hangers. It is built at
real size, so a jet can fly under the main span: 47 m clear of the water at midspan (as on the real bridge), 988 m
between the towers.

## Files

| What | Where |
|---|---|
| Generator | `tools/blender/bridge_generate.py` |
| Textures | `tools/blender/bridge_textures.py` |
| Preview renders | `tools/blender/bridge_preview.py` |
| Manifest | `tools/Manifests/Scenery/SevernBridge.luau` (parts, sets, tile sizes, deck profile) |
| Placement (Studio) | `tools/BridgeBuilder.luau` |
| References | `docs/art/reference/SevernBridge/` (kept out of git; see its SOURCES.md) |

```
blender -b --python tools/blender/bridge_generate.py -- --out <abs>/tools/blender/out --manifest-luau tools/Manifests/Scenery/SevernBridge.luau
blender -b --python tools/blender/bridge_textures.py -- --out <abs>/tools/blender/out/textures --skin Severn
blender -b <abs>/tools/blender/out/SevernBridge.blend --python tools/blender/bridge_preview.py -- --out <abs>/tools/blender/out --textures <abs>/tools/blender/out/textures --skin Severn
```

Outputs in `tools/blender/out/`: `SevernBridge.fbx`, `textures/SevernBridge_<Skin>_<Set>_<Map>.png` (4 sets x 4 maps
per skin) and `SevernBridge_<Skin>_{wide,quarter,tower,deck,anchorage}.png`.

## The model

- 1,890 m from abutment to abutment: the 988 m main span, two 305 m side spans, a concrete anchorage at each end of
  them, then a short approach viaduct (two portal piers) and an abutment. The deck follows a parabolic vertical
  curve, 50 m above the water at midspan and 18 m at the ends.
- Two 136 m steel towers (`TowerA`, `TowerB`), each two tapering legs with three cross-beams (top, middle and just
  under the deck), on concrete piers (`TowerPiers`). `TowerLightsA`/`B` are the red aviation lights on the tower
  tops (make them Neon).
- `Deck` (the aerofoil box girder), `Road` (the carriageway surface), `Walkways` (the cantilevered footpath and
  cycle track), `Barriers` (central reservation, verge and outer parapets), `LampPosts`.
- `MainCables` and `Hangers`: the hangers lean alternately, meeting in V-shapes at the deck, as on the Severn Bridge.
- 14 parts, 19,044 triangles, each part under Roblox's limits (the longest is 1,890 m).

Axes: Blender X across the bridge, Y along it, Z up; in Roblox (after the FBX export) x across, y up, z along. The
origin is the middle of the main span at the water line. Units are metres, so 1 stud = 1 m.

## Textures

The bridge is too long for one unique texture to stay sharp, so its surfaces use four tiling PBR sets and their UVs
run past 0..1 (the textures repeat):

| Set | Parts | Tile |
|---|---|---|
| Steel | towers, deck girder, barriers, lamp posts, lights | 6 m, box-projected |
| Concrete | piers, anchorages, approach viaduct, walkways | 8 m, box-projected |
| Road | the carriageway | 22.86 m across x 24 m along: one tile spans the road's width |
| Cable | main cables and hangers | round the cable, every 1.5 m along it |

Steel is painted plate with welded seams, bolt rows, mottling, grime running down and small rust spots; concrete is
board-marked with lift lines, tie holes and rain streaks; the road is asphalt with wheel-path polish, a concrete
central reservation and UK motorway markings (solid edge lines, 3 m lane dashes every 12 m, road studs); the cables
carry their helical wrapping wire. Vertical faces map height to v, so streaks run down them.

Two skins: `Severn` (the real bridge's off-white paint; the default) and `Weathered` (duller grey steel, darker
concrete).

## Placing it in the Strait

`tools/BridgeBuilder.luau` places both bridges. The channels run north to south, so each bridge turns 90 degrees
about y and its length runs along world x; its water line sits on the sea (y = -1.68, `WorldEdge.WATER`).

### Steps in Studio (Edit mode, after the terrain is built)

1. Import `tools/blender/out/SevernBridge.fbx` (Forward -Z, Up Y, as for the jets). It arrives as a Model with 14
   MeshParts; leave it in workspace for now.
2. Upload the 16 `Severn` textures from `tools/blender/out/textures/` (`SevernBridge_Severn_<Set>_<Map>.png`, sets
   Steel, Concrete, Road and Cable, maps Color, Normal, Roughness and Metalness) and note their asset ids. The
   `Weathered` skin is the same 16 files with `Weathered` in their names.
3. Run:

```lua
local B = require(game.ServerStorage.Tools.BridgeBuilder)
print(B.template(workspace.SevernBridge)) -- lays the parts out as ServerStorage.BridgeTemplate
print(B.skin({
	Steel = { Color = 0, Normal = 0, Roughness = 0, Metalness = 0 },
	Concrete = { Color = 0, Normal = 0, Roughness = 0, Metalness = 0 },
	Road = { Color = 0, Normal = 0, Roughness = 0, Metalness = 0 },
	Cable = { Color = 0, Normal = 0, Roughness = 0, Metalness = 0 },
})) -- the uploaded asset ids
print(B.plan()) -- where each crossing fits the real coastline
print(B.place()) -- BridgeWest and BridgeEast in workspace.Map.Bridges
```

4. Delete the imported `workspace.SevernBridge`. `B.clear()` removes the placed bridges; `skin()` can run again at
   any time (it updates the template and the placed copies).

What `template()` does: puts every part where the manifest says (origin at midspan on the water line), works out
the import's scale from the deck's length and warns if part sizes don't match the manifest (a sign the importer
turned the axes). It anchors everything and sets collision: precise for the deck, towers, tower piers, anchorages
and approaches (a convex hull would fill the window between the tower legs and bridge the gaps between pieces that
share a mesh); no collision for the road surface, walkways, barriers, lamp posts, cables, hangers and lights.
Without `skin()` the parts keep plain colours by set; the tower lights are red Neon either way. The models use
`StreamingMesh` level of detail, like the scenery.

What `plan()` does: for each side it tries crossing lines z = -1000 to 1000 (every 20 studs) and, on each, finds
the island's shore and the landmass coast with `StraitBuilder.height` (the coast is the first 150 studs of
unbroken land, so islets don't count). The bridge is centred on the gap. A line fits when both tower piers stand
in water, both abutments (15 studs in from the deck's ends) stand on land, and the ground along the deck (every 8
studs, on the centre line and 16 studs either side) stays below the deck's underside, apart from the last 60 studs
at each end. Of the lines that fit, it picks the gap nearest 1,700 studs, preferring lines near z = -400. The
report gives each chosen line, its gap and how far each end sits into or above the ground.

Without the coastline noise, both channels are about 1,700 m wide on z = -400 (west centre near x = -1,601, east
near x = 1,589); the real coasts wobble by up to about 100 m, which is why `plan()` searches the real heights.

### Follow-ups

- Roads: `SceneryBuilder.roads()` keeps roads off the island and doesn't know about the bridges. Each landmass's
  road network, and a road on the island, need to meet the bridge ends.
- Terrain at the abutments: where `plan()` reports an end several studs into the ground, flatten or cut the
  terrain there so the road meets the deck (or the end reads as an embankment).
- Textures: the bridge's UVs run past 0..1 and rely on `SurfaceAppearance` maps repeating. Check in game that they
  tile. If they clamp instead, the meshes need splitting into tile-sized pieces with UVs inside 0..1.

## Placement in the place (by hand, October 2026)

`BridgeBuilder.place()` put the two bridges at its planned crossings. Will then lined them up by hand in Studio
so both run east–west through the island (BridgeWest at x −1440, BridgeEast at x 1674, both near z 0). He raised
BridgeWest 19 m so its mainland end meets the hillside there instead of running into it, so its towers stood
13 m clear of the sea; they now stand on `TowerFootings` (a copy of `TowerPiers` stretched down to 6 m under the
sea, same concrete). **Don't re-run `place()`**: it would move them back to the planned spots. Roads still don't
reach the bridge ends.
