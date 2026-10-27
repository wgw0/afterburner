# Aircraft model pipeline

How a jet goes from Blender into the game: a modular mid-poly model with moving control surfaces, swappable PBR skins and its own cockpit interior (section 7). Jets are rebuilt in the order players meet them. The F-5E Tiger II and the MiG-21bis are done; the Mirage IIIE is next. The F-5E is the worked example in this document; the MiG-21bis section at the end lists what differs.

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

## 6. MiG-21bis

The MiG-21bis follows the same pipeline with its own two scripts. `tools/blender/mig21_generate.py` builds the model and `tools/blender/mig21_paint.py` paints it. Both reuse the F-5E scripts' general-purpose helpers: the lofted fuselage with its spine blend, the canopy, the airfoil panels, the baking and the output.

- The reference is the Commons three-view of the MiG-21PF, scaled to the bis's published 7.154 m span (the fin tip then lands within 3% of the published height). The PF has the older, smaller dorsal spine, so the bis's spine is shaped from photos of MiG-21bis jets, including a public-domain walkaround of a Finnish one (`docs/art/reference/MiG21bis/`).
- The fuselage starts at the intake lip, with the duct wall folded back inside it, and the shock cone (`InletCone`) is a separate part.
- The flaps and ailerons are constant-chord strips about 0.48 m deep on the delta wing, so their hinge lines are at a fixed distance from the trailing edge rather than a fixed fraction of the chord.
- There is a single `Nozzle`; the assembler lines a single-nozzle import up with it.
- 29 parts, 10,444 triangles.

The three skins are Natural Metal (Silver, the default), Interceptor Grey (Grey) and Tactical Camouflage (Tactical, tan and greens over light blue undersides). All three have red stars on the fin and wings, a heat-stained bare-metal tail end and a striped air-data boom. Their textures are in `Assets.Skins.MiG21bis`.

## 7. Cockpit interiors

Every jet gets its own cockpit: a low-poly model built in Blender for that jet's canopy and fuselage, which the game shows only to the pilot. It replaces the greybox kit, whose generic panel, coaming and canopy bow collided with the real airframes (the bow cut across the gauges and boxes poked through each other).

| Part | Contents |
|---|---|
| Tub | Lining of the cockpit well: walls, floor and a flange over the sill, with front and rear walls |
| ConsoleL / ConsoleR | Side consoles; the throttle on the left one, a side stick's base on the right one where the jet has one |
| Panel | Instrument panel, tilted back, with bezels and scope hoods as geometry |
| Coaming | Glareshield: a lip over the panel and a hood that narrows and drops forward under the windscreen |
| Gunsight, HUDGlass | Sight body and its combiner glass (`Glass` set) |
| Stick | Centre stick with its boot, or a side stick |
| CanopyFrameInner | Inside of the windscreen bow and the canopy's rear frame, sill rails, and mirrors where the bow is high enough |

The F-5E and MiG-21bis cockpits are about 2,500 triangles each, with one 1024² texture set (`Cockpit`).

### How it fits the jet

The cockpit is modelled in the jet's own axes with the same origin, so its manifest positions are in the jet's Root space. `tools/blender/cockpit_kit.py` builds it from a `COCKPIT` spec in the jet's generator script and from the shapes already measured for the exterior. The panel is narrowed to fit under the canopy glass at its top and inside the well. The glareshield narrows and drops forward to stay inside the windscreen. The canopy frames' insides follow `canopy_ring` just inside the exterior frames. The script warns if a live instrument's top edge is hidden behind the glareshield lip from the eye.

The spec gives these in metres from the `CockpitEye`: the panel's distance, top, bottom, tilt and half width; the glareshield's overhang, length and drop; the consoles' height, width and length; the stick type; the sight; and the palette. The well is given in jet axes: where it starts behind the seat, where it ends just ahead of the panel, its half width and its floor. Each instrument has a panel position (`u` metres right of the centre, `v` metres down from the top edge), a size and a kind (`Dial`, `Scope`, `MFD` or `Lights`). Instruments marked `live` (`Speed`, `Altitude`, `G`, `RPM` or `Radar`) become faces in the manifest, and the rest are painted.

The exterior fuselage used to be closed across the top under the canopy, which would have hidden the tub. The generator now opens a **cockpit well**: after unwrapping, `cockpit_kit.open_well()` pushes the top of the fuselage rings in the well's range down to the cockpit floor. Only vertex positions change. Smart UV Project is deterministic, so a re-run gives exactly the same UVs as before, and the jet's existing skins still fit. This was checked for the F-5E and MiG-21bis by hashing every object's UVs against the `.blend` that was imported into Studio: the UVs were identical, and only the Fuselage's vertices had moved. The tub lines the well, so the pilot never sees its stretched paint. Other players can look into the well through the canopy, so the skin painters paint it cockpit-dark (`cockpit_kit.well_mask`); this takes effect when a skin is next repainted.

### Commands

```
blender -b --python tools/blender/f5e_generate.py -- --out <abs>/tools/blender/out --manifest-luau tools/Manifests/F5E.luau
blender -b --python tools/blender/cockpit_generate.py -- --airframe F5E --out <abs>/tools/blender/out --manifest-luau tools/Manifests/Cockpits/F5E.luau
blender -b <abs>/tools/blender/out/F5E_cockpit.blend --python tools/blender/cockpit_paint.py -- --airframe F5E --out <abs>/tools/blender/out
blender -b <abs>/tools/blender/out/F5E_base.blend --python tools/blender/cockpit_preview.py -- --out <abs>/tools/blender/out --skin Ghost --textures <dir with the skin PNGs>
```

These write `F5E_cockpit.fbx`, `F5E_cockpit.blend`, `F5E_cockpit_manifest.json`, `tools/Manifests/Cockpits/F5E.luau` and the four `F5E_Cockpit_<Map>.png` maps. They also write previews from the eye (`F5E_cockpit_ahead.png`, `_panel` and `_left`) and from outside (`_outside`). A new jet's cockpit needs its generator listed in `cockpit_generate.GENERATORS`.

### Painting

`tools/blender/cockpit_paint.py` paints the same way as the skin painter: it bakes where every texel is, computes the maps in numpy and bakes the normal map from a height map. There are four palettes: `US` (dark gull grey tub, black panels), `Soviet` (turquoise, from the MiG-21bis onwards), `French` (dark grey and black) and `Modern` (charcoal). It paints dial faces with scales and needles, the attitude ball and compass card, caution-light panels, placards, screws and panel seams. The consoles get panels with switches and knobs, the tub gets ribs and a non-slip floor, the glareshield is flat black and the mirrors are glossy. The live instruments are left as plain dark faces, because the game draws its gauges over them.

### Studio

1. Re-import the jet's exterior (`<Id>_base.fbx`) and run `install` as before, so its fuselage has the well. The skins don't change.
2. Upload the four `<Id>_Cockpit_<Map>.png` maps.
3. Import `<Id>_cockpit.fbx` as one Model (Merge Meshes off, Anchored on), then run:
   ```lua
   print(require(game.ServerStorage.Tools.AircraftAssembler).installCockpit("F5E", workspace.F5E_cockpit,
       { Color = <id>, Normal = <id>, Roughness = <id>, Metalness = <id> }))
   ```
   Without the maps table, the cockpit installs untextured.
4. Move the imported Model to `ServerStorage`.

`installCockpit` matches the imported parts to `tools/Manifests/Cockpits/<Id>.luau` by name. It undoes the importer's scale and axes the same way `install` does, but lines the parts up on the coaming, tub and consoles (the manifest's `fit`). It builds `ReplicatedStorage.Assets.Cockpits.<Id>`, which contains:
- a `CockpitRoot` part at the jet's Root frame, with every part welded to it (massless, with collision, touch and query off)
- a `SurfaceAppearance` on each `Cockpit` part
- the HUD glass as tinted SmoothPlastic
- a `Faces` folder of invisible parts, one per live instrument, each with its Back face toward the pilot and `Gauge` and `Style` attributes

A cockpit it replaces moves to `ServerStorage.ReplacedModels`.

When the pilot's jet spawns, `CockpitController` looks for `Assets.Cockpits.<AirframeId>`. If it's there, a copy is pivoted to the jet's Root and welded to it, and a gauge is drawn on each face. A face gets a needle dial, a green-on-black dial if its `Style` is `"Digital"`, or a scope with a sweeping bearing line if its `Gauge` is `Radar`. The cockpit model stays visible in the chase view too, because it sits inside the jet. If there's no cockpit model, the greybox kit is built as before.
