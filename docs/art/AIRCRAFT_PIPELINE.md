# Aircraft model pipeline

How a jet goes from Blender into the game: a modular mid-poly model with moving control surfaces and swappable PBR skins. Jets are rebuilt in the order players meet them. The F-5E Tiger II is done; the MiG-21bis is next.

| Stage | Tool | F-5E |
|---|---|---|
| 1. Base mesh measured from reference drawings | `tools/blender/f5e_generate.py` | Done: 35 parts, 10,704 triangles, matches the three-view |
| 2. Hand refinement in Blender | Blender | Skipped so far; optional |
| 3. PBR textures (Body, Wings, Details) | `tools/blender/f5e_paint.py` | Done: Ghost, Desert, Pacific and Lizard skins |
| 4. Import into Studio | Studio 3D Importer | Done |
| 5. Assemble (Root, Hull, hitboxes, attachments, hinges, skin) | `tools/AircraftAssembler.luau`, reading the manifest | Done |
| 6. Validate | Model contract in Studio and CI (Lune) | Passing |

## 1. Structure (F-5E)

Blender axes are X right, Y forward (the nose points to +Y) and Z up, in metres. The FBX exporter (Forward −Z, Up Y) turns Blender +Y into Roblox −Z, which is the nose direction the game expects. The game uses 1 m = 3.5714 studs. Every part is modelled at real size and the assembler converts to studs. The model's origin is the centre of gravity (25% of the mean wing chord), because the flight model rotates the jet about its root part.

The budget is 5,000 to 12,000 triangles for the whole jet. The F-5E has 10,704, about half of them in the fuselage. Roblox allows 20,000 per MeshPart, so the limit comes from performance, not the engine.

Nothing is merged. Each moving part is its own object, with its origin on its hinge line and no rotation. The hinge axis and limits are stored on the object (`afterburner_hinge_axis`) and in the manifest.

| Part | Texture set | Kind | Pivot / hinge | Deflection |
|---|---|---|---|---|
| Fuselage | Body | Static | origin | |
| Intakes (both, D-section) | Body | Static | origin | |
| LERX (both) | Body | Static | origin | |
| CanopyFrame | Body | Static | origin | |
| Canopy | Glass | Static | origin | |
| Fin | Body | Static | origin | |
| Rudder | Body | ControlSurface | hinge line, 72% chord | ±30° |
| WingL / WingR | Wings | Static | origin | |
| LEFlapL / R | Wings | ControlSurface | 13% chord | 0 … +24° |
| FlapL / R | Wings | ControlSurface | 75% chord, inboard | 0 … +30° |
| AileronL / R | Wings | ControlSurface | 75% chord, outboard | ±20° |
| StabilatorL / R (all-moving) | Wings | ControlSurface | spigot at 35% root chord, axis X | −20 … +15° |
| NozzleL / R | Details | Nozzle | origin | |
| AfterburnerL / R (inner cone) | Details | Afterburner | origin | |
| EjectionSeat | Details | Static | origin | |
| WingtipRailL / R | Details | Static | origin | |
| Pitot | Details | Static | origin | |
| NoseGearStrut, MainGearStrutL / R | Details | Gear | retraction hinge | 0 … 95° |
| NoseGearWheel, MainGearWheelL / R | Details | GearWheel | axle | spin |
| NoseGearDoorL / R, MainGearDoorL / R | Details | GearDoor | door hinge | 0 … 85° |

The gear is modelled down. Jets spawn in the air, so the assembler hides it until there is a takeoff and landing feature to use it.

The manifest (`tools/blender/out/F5E_manifest.json`, and `tools/Manifests/F5E.luau` for Studio) lists every part with its texture set, kind, bounding box, pivot and hinge. It also carries the gameplay data: the attachment points (`CockpitEye`, `GunMuzzle`, `Nozzle1/2`, `WingtipL/R`, the dispensers, `ChaseCam`, `Hardpoint1–3`), the collision hull and the six hitboxes. These are placed on the model itself: the cockpit eye is inside the canopy, the muzzle is at the nose guns, the nozzles are at the real exits, and the hitboxes cover the visible parts. The flight data in `AircraftData` is separate and didn't change.

## 2. Textures and skins

### Texture sets

| Set | Parts | Size | Maps |
|---|---|---|---|
| Body | fuselage, intakes, LERX, fin, rudder, canopy frame | 1024² | Color, Normal, Roughness, Metalness |
| Wings | wings, flaps, ailerons, LE flaps, stabilators | 1024² | Color, Normal, Roughness, Metalness |
| Details | nozzles, afterburners, gear, seat, rails, pitot | 512² | Color, Normal, Roughness, Metalness |
| Glass | canopy | none | flat values |

1024² is the largest image Roblox accepts, and two 1024² sets give the airframe twice the texel density of one, which shows in hangar close-ups. Paint is matte (roughness 0.55 to 0.7, metalness 0). Exhausts are bare titanium and steel (metalness 0.8 to 1, roughness 0.3 to 0.45). Panel gaps, rivets and fasteners are only in the normal map, with no geometry of their own.

The canopy doesn't use Roblox's `Glass` material, because Glass draws opaque in front of water. It is SmoothPlastic at transparency 0.6, reflectance 0.15, with a blue-grey tint.

### How skins work

All skins for an airframe share the same UV layout, so a skin is just a set of textures:

```
ReplicatedStorage.Assets.Skins.F5E
├── Ghost          Body / Wings / Details   (a SurfaceAppearance each)
├── Desert         Body / Wings / Details
├── Pacific        Body / Wings / Details
└── Lizard         Body / Wings / Details
```

Each skin's name, price and default flag are in `Shared.Config.Skins`. `Shared.Skins.apply` paints a model by cloning each SurfaceAppearance into the MeshParts whose `TextureSet` attribute matches. Scripts can't change a SurfaceAppearance's images at runtime, so skins are swapped as whole instances. The server paints every jet as it spawns, so all players see the same paint; AI jets get a random skin. The client uses the same function for the hangar previews.

Ownership is saved per jet in `Aircraft[id].Skins`, and the skin in use in `Aircraft[id].Camo`. The default skin is always owned. The others cost 5,000 Credits for now and will move to the shop (Wings or Robux, and season-pass rewards) in Phase 7. The assembler fits the default skin when it builds a model, so a re-import keeps its paint.

Two ideas for later. A skin can use `AlphaMode = Overlay`, where transparent areas of the colour map show the MeshPart's own `Color`, so one texture set could be sold in several colours. Per-player text such as callsigns would go on small `SurfaceGui` panels rather than into the textures.

One skin on one jet is two 1024² sets and one 512² set, four maps each. A server full of the same jet shares one copy of each texture.

### Painting (`tools/blender/f5e_paint.py`)

Skins are painted by a script from the same `.blend` whose FBX is in the game, since the textures follow its UV layout:

```
blender -b tools/blender/out/F5E_base.blend --python tools/blender/f5e_paint.py -- --out <absolute path>/tools/blender/out/textures --skin Ghost --preview
```

For each texture set, Cycles bakes what every texel is: its position on the jet, its normal, which part it belongs to and its ambient occlusion. numpy then computes the Color, Roughness and Metalness maps and a height map, and Cycles bakes the height map into the tangent-space normal map (OpenGL, which Roblox expects). Every texel is painted from its 3D position, so paint and panel lines run across UV seams without a break.

The panel layout has fuselage frames and longerons, access panels with fasteners, wing spars and ribs, fuel panels and rivet rows, all placed at the generator's drawing stations so they line up with the shape. On top go the paint scheme, an anti-glare panel, the radome, non-slip walkways and low-visibility insignia, then wear: a slightly different shade per panel, grime behind the seams, gun and exhaust soot, chipped leading edges, bare-metal intake lips, and titanium nozzles with a heat tint and petal seams.

A scheme is an entry in `SCHEMES`. Ghost is two-tone, with a soft line between the upper and lower colours. The aggressor schemes (Desert, Pacific, Lizard) list three camouflage colours; the script cuts 3D noise into hard-edged wavy bands, so the pattern wraps continuously over the whole jet.

To get a skin into the game:
1. Upload the 12 PNGs (`F5E_<Skin>_<Set>_<Map>.png`). The F-5E's were uploaded through the Studio MCP connection; the Asset Manager's Bulk Import works too. Don't bulk-import the meshes, because that uploads each mesh on its own and loses the layout.
2. Make one `SurfaceAppearance` per set (ColorMap, NormalMap, RoughnessMap, MetalnessMap) under `Assets.Skins.F5E.<Skin>`.
3. Add the skin to `Shared.Config.Skins`.

| F-5E skin | Set | Color | Normal | Roughness | Metalness |
|---|---|---|---|---|---|
| Ghost | Body | 81835012873669 | 82968577363109 | 105714057801586 | 109834815051063 |
| Ghost | Wings | 100916008882277 | 104825289967457 | 82890588585642 | 99740436860517 |
| Ghost | Details | 81974986545670 | 138592182008286 | 107141838096039 | 87789614504400 |
| Desert | Body | 71475764434424 | as Ghost | as Ghost | as Ghost |
| Desert | Wings | 88744784179765 | as Ghost | 132928858941635 | as Ghost |
| Desert | Details | 131932789782406 | as Ghost | as Ghost | as Ghost |
| Pacific | Body | 87157106227464 | as Ghost | as Ghost | as Ghost |
| Pacific | Wings | 88219907366285 | as Ghost | 71010529022486 | as Ghost |
| Pacific | Details | 90139710262027 | as Ghost | as Ghost | as Ghost |
| Lizard | Body | 117608256949978 | as Ghost | as Ghost | as Ghost |
| Lizard | Wings | 74353148664969 | as Ghost | 87930505872254 | as Ghost |
| Lizard | Details | 83889269655804 | as Ghost | as Ghost | as Ghost |

Only the paint changes between schemes, so the normal maps, metalness maps and most roughness maps are byte-identical, and Roblox gave them the same asset IDs.

## 3. Blender workflow

### Generate the base

```
blender -b --python tools/blender/f5e_generate.py -- --out tools/blender/out --manifest-luau tools/Manifests/F5E.luau
blender -b tools/blender/out/F5E_base.blend --python tools/blender/render_views.py -- --out <absolute path>/tools/blender/out
blender -b tools/blender/out/F5E_base.blend --python tools/blender/overlay_reference.py -- --ref <three-view image> --out <absolute path>/tools/blender/out
stylua tools/Manifests
```

This writes `F5E_base.blend` (a collection and a material per texture set, UVs packed per set), `F5E_base.fbx`, the manifest, reference renders, and `F5E_overlay_side.png` and `F5E_overlay_top.png`. The overlays draw the model tinted blue over the three-view at the drawing's own scale, so any mismatch shows as blue outside the red lines. Re-running the generator changes the UV layout only if the shapes change; after that the skins have to be repainted and the model re-imported.

### References

Each jet's reference images are in `docs/art/reference/<Airframe>/`. The folder is kept out of git (it's excluded locally in `.git/info/exclude`), and its `SOURCES.md` records each image's author, licence and link. For the F-5E it has the Wikimedia Commons three-view (`Northrop F-5E Tiger II 3-view.svg`), figures from the USAF flight manual T.O. 1F-5E-1, museum walkarounds, side profiles, detail shots of the intakes, nozzles, canopy and gear, and paint-scheme photos.

The generator's shapes are measured from the three-view. Its stations are written in the drawing's pixel coordinates (`Y(xd)`, `Z(row)`), so every number can be traced back to the drawing. The scale comes from the published 14.45 m length, and it also reproduces the published height and span. The photos are for what a line drawing can't show, such as gear legs and intake lips.

### Hand refinement (optional)

The F-5E went into the game straight from the generator. If a jet needs more shape than the generator gives, refine `F5E_base.blend` by hand:

1. For symmetrical parts, delete the −X half, add a Mirror modifier (axis X, Clipping and Merge on) and edit the +X side. Apply the modifier before export.
2. Keep the lofted section loops as the fuselage's edge flow and shape with proportional editing (Connected only). For the F-5E's shark-nose chine, add one loop each side of the chine line and pull it out.
3. Keep the intakes' D-section loops. Bevel the lip (0.02 m, 2 segments, Limit Method: Weight, with bevel weight on the lip edges only).
4. Don't subdivide the wings and tail: their airfoil sections are already right. Keep the moving surfaces as separate objects with their origins where they are.
5. Use smooth shading by angle (30 to 35°). Use Subdivision Surface only while shaping; if you apply it, apply level 1 at most on the fuselage and check the triangle count.
6. Keep the object names, origins and texture sets, so the manifest stays valid. If anything moves, re-run the generator or update the manifest, then repaint.

## 4. Roblox Studio import checklist

Export (the generator does this; use the same settings if you export by hand):
- [ ] Mesh objects only: no empties, no high-poly collection.
- [ ] Scale 1.0, Apply Scalings: FBX All, Apply Unit on.
- [ ] Forward −Z, Up Y, Apply Transform on.
- [ ] Smoothing: Face. Apply Modifiers on. No leaf bones.
- [ ] Object names unchanged (`AileronL`, `Fuselage`...), because the assembler finds parts by name.

Import (Studio → File → Import 3D):
- [ ] Import as one Model, with Merge Meshes off.
- [ ] Anchored on, so the imported copy doesn't fall during play tests. Scale unit Meter.
- [ ] Upload to Roblox on. Material import doesn't matter: the FBX has no textures, and the assembler clears them anyway.
- [ ] Run the assembler in the command bar (Edit mode):
  ```lua
  print(require(game.ServerStorage.Tools.AircraftAssembler).install("F5E", workspace.F5E_base))
  ```
- [ ] Move the imported Model to `ServerStorage` afterwards.

The assembler matches the imported MeshParts to `tools/Manifests/F5E.luau` by name. It works out any scale or axis change from where the nose, nozzles and wings landed (the F-5E import came in facing backwards and was turned round), then puts every part exactly at its manifest position. It builds Root, Hull, the six hitboxes and the attachment points; joins the moving parts to Root with Motor6Ds at their hinge points (with `Control`, `HingeAxis`, `HingeMin` and `HingeMax` attributes) and the rest with WeldConstraints; sets every part massless and non-colliding; tags each part with `TextureSet` and `Kind`; hides the gear; and fits the default skin. It checks the model contract before installing and prints a report with the scale, any axis correction and how closely the layout fits. The model it replaces moves to `ServerStorage.ReplacedModels`, so nothing is deleted.

The hinges are set from the manifest, not from the imported pivots. The importer places MeshParts by their bounding boxes, and its pivot handling has changed between Studio versions, so this keeps the hinge axes exact whatever it does.

Checks:
- [ ] The model contract passes in Studio (`Model.spec`) and in CI (`lune run scripts/validate-models.luau`).
- [ ] The nose points −Z (the contract fails if `GunMuzzle` is behind the centre).
- [ ] In play, the control surfaces move with the stick and the cockpit eye sits inside the canopy.

## 5. Game side

`tools/AircraftAssembler.luau` turns the manifest and the imported model into a contract-ready jet (section 4).

`AircraftModelContract` lets parts join Root by a WeldConstraint or a Motor6D. Hinged parts need `Control`, `HingeAxis`, `HingeMin` and `HingeMax`, and a jet can have up to 60 parts.

`ControlSurfaceController` moves the surfaces with the rules in `Shared.ControlSurfaces`. It sets each Motor6D's `Transform` on the client only, so it costs no network traffic. Your own jet follows your stick. Other players' jets and AI jets follow how they are actually moving: pitch and roll from their body rates, the rudder from sideslip (in a banked turn the yaw rate is large while the rudder stays near centre). The leading- and trailing-edge flaps come out with angle of attack at lower speeds, like the F-5E's manoeuvring flaps. Surfaces move at 120°/s, and jets more than 1,500 studs from the camera are skipped.

`Shared.Skins`, `Shared.Config.Skins` and the skin picker on the aircraft detail screen handle skins (section 2).
