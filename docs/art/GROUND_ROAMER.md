# The Ground Roamer

A drivable 4x4 for exploring the map from the ground (DEVELOPMENT.md §36). It is modelled on a classic British
short-wheelbase soft-top utility vehicle of the 1970s, built to the same standard as the jets, with no maker's names
or badges anywhere: its grille badge reads GROUND ROAMER and its plates read GR 88 MAP.

## Files

| What | Where |
|---|---|
| Model | `tools/blender/groundroamer_generate.py` → `GroundRoamer.fbx`, `tools/Manifests/Vehicles/GroundRoamer.luau` |
| Skins | `tools/blender/groundroamer_paint.py` → `textures/GroundRoamer_<Skin>_<Set>_<Map>.png` |
| Badge and plates | `tools/blender/groundroamer_decals.py` (Python 3 with Pillow) → `textures/GroundRoamer_Decals_<Map>.png` |
| Studio template | `tools/GroundRoamerBuilder.luau` |
| References | `docs/art/reference/GroundRoamer/` (kept out of git; see its SOURCES.md) |

```
blender -b --python tools/blender/groundroamer_generate.py -- --out <abs>/tools/blender/out --manifest-luau tools/Manifests/Vehicles/GroundRoamer.luau
python tools/blender/groundroamer_decals.py --out <abs>/tools/blender/out/textures
blender -b <abs>/tools/blender/out/GroundRoamer.blend --python tools/blender/groundroamer_paint.py -- --out <abs>/tools/blender/out/textures --skin BronzeGreen --preview --decals <abs>/tools/blender/out/textures
```

## The model

Built at real size from the published dimensions (2,235 mm wheelbase, 1,310 mm track, 3,620 mm long, 1,680 mm wide,
1,970 mm high with the tilt, 7.50-16 tyres) and the reference photos. Commons has no scale drawing of these vehicles,
so the shapes are from photos rather than measured from a drawing as the jets are.

Its shapes are built the way a car body is, not from raw boxes: panels are bevelled, the round wheel arches and the
headlamp bowls are cut with booleans, the canvas tilt is lofted over its hoops and sags between them, and the tyres
and dished steel rims are revolved from real sections. Each part is assembled from temporary objects with Bevel and
Boolean modifiers and then evaluated.

| Part | What |
|---|---|
| `Body` | front wings with headlamp bowls and round arches, bonnet, grille panel, bulkhead with its vent flaps, doors and window frames, the rear tub with its arches, galvanised cappings, tailgate, floor, wheel boxes |
| `Frame` | the windscreen frame, raked back 6 degrees |
| `Tilt` | the canvas hood |
| `Glass`, `DoorGlass` | windscreen and door glass |
| `Chassis` | ladder frame, bumper, crossmember, axles and differentials, leaf springs, dampers, propshafts, track rod, exhaust and silencer, fuel tank, mudflaps |
| `Lamps` | headlamps (chrome rings, lenses), side lamps, indicators, rear lamps, the slatted grille, mirrors, wipers, hinges, handles |
| `Cab` | dashboard with the centre instrument binnacle, steering wheel and column, seats, levers |
| `WheelFL`, `WheelFR`, `WheelRL`, `WheelRR` | the road wheels, origin on the hub |
| `SpareWheel` | lying on the bonnet |
| `Decals` | badge and number plates |

14 parts, about 18,000 triangles. The origin is on the ground midway between the axles; axes as the jets'.

## Skins

Texture sets Body (1024), Canvas (512) and Details (1024) per skin, plus Decals (shared). The painter bakes world
position, normal, part and AO per texel (the jets' pipeline) and paints:
- Body: paint with door shut lines, the waist crease, rivet rows, galvanised cappings, dust on the flat tops and
  mud thrown up low down
- Canvas: woven canvas, stitched seams, stains
- Details: black chassis and bumper with a little rust, tyres with a moulded tread (normal map), painted rims with
  their nuts, chrome-ringed headlamps with reflectors, amber indicators, red rear lamps, the silver grille's slats

| Skin | |
|---|---|
| `BronzeGreen` (default) | bronze green, olive canvas |
| `Sand` | desert sand |
| `PastelGreen` | pastel green, black canvas, pale rims |
| `Red` | red, black canvas, pale rims |

## In Studio

1. Import `tools/blender/out/GroundRoamer.fbx` (it arrives as a model, e.g. `workspace.GroundRoamer`).
2. Upload the textures: for each skin, `GroundRoamer_<Skin>_{Body,Canvas,Details}_{Color,Normal,Roughness,Metalness}.png`
   (48 images), and the 4 `GroundRoamer_Decals_*.png`.
3. Run, with the uploaded ids:
   ```lua
   require(game.ServerStorage.Tools.GroundRoamerBuilder).template(workspace.GroundRoamer, {
       BronzeGreen = { Body = { Color = id, Normal = id, Roughness = id, Metalness = id }, Canvas = {...}, Details = {...} },
       Sand = {...}, PastelGreen = {...}, Red = {...},
       Decals = { Color = id, Normal = id, Roughness = id, Metalness = id },
   })
   ```
   It reports the import scale and how well the parts match the manifest, and writes
   `ServerStorage.Vehicles.GroundRoamer`. Without `maps` it is untextured (coloured by set).
4. Delete the import, play, press DRIVE in the Hangar.
