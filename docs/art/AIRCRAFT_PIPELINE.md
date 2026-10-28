# Aircraft model pipeline

How a jet goes from Blender into the game: a modular mid-poly model with moving control surfaces, swappable PBR skins and its own cockpit interior (section 7). Jets are rebuilt in the order players meet them. The F-5E Tiger II, the MiG-21bis and the Mirage IIIE are done (the Mirage on the `art/mirage3` branch); docs/art/ROSTER_STATUS.md tracks the rest. The F-5E is the worked example in this document; the MiG-21bis section at the end lists what differs.

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

## 8. Mirage IIIE

The Mirage IIIE uses the same pipeline. `tools/blender/mirage3_generate.py` builds it, `tools/blender/mirage3_paint.py` paints it, and both use the F-5E scripts' helpers the way the MiG-21bis does. Its generator also holds its cockpit spec.

- The reference is the Commons line drawing of the Mirage III by Lirdon, rendered 3840 px wide. Its side view is drawn nose-right, so stations are pixels aft of the pitot tip. Its top view is drawn at 45° and was turned upright to measure the half widths. All three views share one scale, set from the published 8.22 m span (177.1 px/m). At that scale the length without the probe comes out within 1% of the published 15.03 m. How it was measured is in `docs/art/reference/MirageIII/SOURCES.md`.
- The half-round side intakes use the kit's D-section intake builder, with an almost unswept lip. Their half-cone centre bodies are a separate part, `InletCones`.
- It is a tailless delta, so there are no stabilators. Each wing has two elevons, `ElevonIn` and `ElevonOut`, hinged on a line square across the jet. They are driven by the new `ElevonL` and `ElevonR` controls in `Shared.ControlSurfaces`, which mix pitch and roll (±15° each, within ±20°).
- There is a brake-chute fairing over the nozzle (`ChuteFairing`) and a dorsal fillet into the fin.
- The kit's dorsal spine used to bulge below the fuselage as well as above it. The Mirage sets `SPINE_UPPER_ONLY`, so its fuselage keeps the drawn underside. The F-5E and MiG-21bis still have that keel (about 0.4 m below their drawn undersides), because changing it would change their UVs and their uploaded skins. Fix it the next time their skins are repainted.
- 28 parts, 10,752 triangles. The cockpit is 2,304 triangles, with a French-palette panel: the radar scope under the sight, flight instruments to its left and engine instruments to its right.

There are four skins: Armée de l'Air camouflage (`Tactical`, dark green and grey over aluminium-lacquered undersides, the default), `Silver` (natural metal), `Desert` (sand and brown over light blue) and `Grey` (two-tone air-superiority grey). The `Tactical` and `Silver` skins carry French roundels and a tricolour fin flash. `Desert` and `Grey` have grey low-visibility roundels and no flash.

## 9. Shared skin painter

Jets from the Mirage IIIE on are painted by `tools/blender/jet_paint.py`. Each jet's paint script is just a layout and its schemes. The layout says where the panel frames and lines are, which parts are the body, wings, moving surfaces, tail and fin, and where the radome, anti-glare panel, intake lips, ducts, hot tail end and gun ports are. It also places the insignia and fin flash and gives the nozzles' positions. The painter does the rest the same way for every jet. The insignia can be a roundel in any three colours, the Soviet star or the US star and bar, each with a low-visibility grey version. A scheme is either camouflage over an underside colour, two tones, or natural metal (`metal`). It can also have an aluminium-lacquered underside (`underside_metal`), low-visibility markings (`markings = "lowvis"`) or no markings (`"none"`). Repainting the Mirage IIIE through the shared painter changed its textures only in the panel lines on the moving surfaces (a mean difference of about 0.1/255).

## 10. Mirage F1C

`tools/blender/miragef1_generate.py` builds the F1C and `tools/blender/miragef1_paint.py` paints it.

- The only usable three-view on Commons is a 574 px public-domain drawing. It's approximate, so it gives the outline and the published figures set the scale: the side view's length is the published 15.30 m (18.95 px/m). The top view is drawn about 2% shorter, so its stations are stretched to match the side view, and its widths are scaled so the wing without its tip rails spans 8.20 m. In the overlays the model sits on the drawing's lines. The trailing edge is the drawing's aft-most line; the line ahead of it is the flap hinge.
- The shoulder wing comes from the F-5E's wing builder: a 47.5° leading edge, full-span leading-edge flaps, flaps, ailerons and wingtip launch rails. There are all-moving stabilators, a fin with a rudder, two canted ventral fins, half-round intakes behind the cockpit with half-cone centre bodies, and the main gear folding into the fuselage.
- 34 parts, 10,708 triangles. The cockpit is 2,280 triangles (French palette, with the Cyrano IV scope under the sight).

There are four skins: `Interceptor` (two blue-greys over light grey, the default), `Tactical` (green and grey), `Desert` (sand and brown over light blue) and `Grey` (overall light grey). The first two carry French roundels and a fin flash; the other two have low-visibility markings.

## 11. F-4E Phantom II

`tools/blender/f4e_generate.py` builds the F-4E and `tools/blender/f4e_paint.py` paints it.

- The reference is Kaboldy's Commons three-view of the F-4E, rendered 3840 px wide, with the side and top views both nose left. The scale comes from the published 11.71 m span (153.4 px/m), which also gives the published 5.02 m height. The drawing's length then comes out 18.6 m against the published 19.2 m, and the drawing's shape was kept. In the overlays the model sits on the drawing's lines.
- The wing has inner panels with leading-edge flaps, flaps and ailerons, and outer panels (`WingOuterL` and `WingOuterR`) folded up 12° with their own leading-edge flaps. The all-moving stabilators have the Phantom's anhedral (about 25°). There are big D-section intakes with splitter plates, the M61 gun fairing under the nose (`GunFairing`, with the splitter plates in the same part), twin nozzles, and a tail boom over the nozzles, painted bare metal.
- The canopy has three frames: the windscreen bow and the two cockpits' rear frames. The cockpit kit now takes the windscreen bow and the first frame behind the pilot, so tandem canopies work.
- The jet has 37 parts and 11,572 triangles. The cockpit is 2,280 triangles: US palette, with the radar scope at the top of the panel and twin engine gauges.

There are four skins: `SEA` (Southeast Asia tan and two greens over light grey, the default), `HillGray` (two greys), `EuroOne` (dark greens and grey all round) and `Desert` (no national markings). The shared painter now draws the full-colour US star and bar, with an outline-only low-visibility version.

## 12. MiG-23MLD

`tools/blender/mig23_generate.py` builds the MiG-23MLD and `tools/blender/mig23_paint.py` paints it.

- The reference is Kaboldy's Commons three-view of the MiG-23MF, rendered 3840 px wide; the MF and MLD airframes are the same shape at this level of detail. The scale comes from the published 16.70 m length (180 px/m). The spread span then comes out 13.3 m against the published 13.97 m.
- The wings are swing wings. The top view shows one spread (16°), and that wing was measured and turned 29° about its pivot to the 45° combat sweep. The wing parts have their origin on the pivot, so sweep could be animated later; for now they're fixed. The overlay was checked with the wings left spread, where the model sits on the drawing's spread wing.
- The fixed gloves with their dogtooth, the splitter plates and the GSh-23L gun pack are one part, `Gloves`. There are leading-edge slats (`LEFlap`) and trailing-edge flaps (`Flap`), a ventral fin, and a long dorsal fillet into the fin.
- The MiG-23 rolls with its all-moving tailplanes (tailerons), which mix pitch and roll the way elevons do, so `StabilatorL` and `StabilatorR` use the `ElevonL` and `ElevonR` controls.
- The jet has 30 parts and 10,164 triangles. The cockpit is 2,280 triangles, in Soviet turquoise, with the Sapfir-23 scope under the sight and a wing-sweep gauge.

There are four skins: `Tactical` (tan and two greens over light blue, the default), `TwoTone` (grey-green and dark grey), `Grey` (air-defence grey) and `Desert` (low-visibility markings). The red stars are on the fin and on both wings, top and bottom. The shared painter takes the wing's leading and trailing edges at the combat sweep.

## 13. F-16A Fighting Falcon

`tools/blender/f16a_generate.py` builds the F-16A and `tools/blender/f16a_paint.py` paints it.

- The reference is Marek Cel's Commons three-view of the F-16A (CC0), rendered 3840 px wide, with the side and top views both nose left. The scale comes from the published 15.03 m length (175.4 px/m), which gives a span over the tip rails of 9.37 m against the published 9.45 m. In the overlays the model sits on the drawing's lines.
- The canopy is a frameless bubble with a single frame behind the seat. The cockpit kit now handles a single-frame canopy: the frame inside is drawn behind the pilot, and the sill rails run from the canopy's front.
- The chin intake is a closed rounded section (`Intake`), with a dark recessed mouth (`IntakeDuct`). The leading-edge extensions and the shelves the tailerons sit on are one part, `Strakes`.
- The wing comes from the F-5E's wing builder, with full-span leading-edge flaps, flaps, ailerons and tip rails. On the real jet the flaps and ailerons are one surface (flaperons), but they're split here so the existing flap and aileron controls drive them. The all-moving tailerons have anhedral and use the `ElevonL`/`ElevonR` controls, which mix pitch and roll. There are also the fin on its base fairing, the rudder, and two ventral fins.
- The jet has 35 parts and 10,728 triangles. The cockpit is 2,008 triangles: a wide HUD, the up-front control panel, the radar display (an MFD-style face) upper right, the threat display upper left, and a side stick.

There are four skins: `Falcon` (the three greys, the default), `Blue`, `Desert` (no national markings) and `Euro`. All of them except `Desert` carry low-visibility insignia.

## 14. MiG-29A

`tools/blender/mig29_generate.py` builds the MiG-29A and `tools/blender/mig29_paint.py` paints it.

- The reference is Kaboldy's Commons three-view of the MiG-29, rendered 3840 px wide, with the side and top views both nose left. The scale comes from the published 17.37 m length (171.8 px/m), which gives an 11.27 m span against the published 11.36 m. In the overlays the model sits on the drawing's lines.
- The MiG-29 is a lifting body, so its parts differ from the earlier jets. `Fuselage` is the narrow forward fuselage running back as a central spine between the engines. `Nacelles` are the two engine nacelles under the wing roots, with raked intake lips, and their recessed mouths are a separate dark part, `IntakeDucts`. `Strakes` holds the big leading-edge extensions, the flat centre section over the nacelles and the tail booms.
- The wing comes from the F-5E's wing builder, with leading-edge flaps, flaps, ailerons and tip rails. The stabilators sit on the booms and use the elevon controls (pitch and roll mixed). The twin fins (`FinL` and `FinR`) are canted out 6°, each with a rudder (`RudderL` and `RudderR`) on the `Rudder` control.
- The jet has 38 parts and 11,916 triangles. The cockpit is 2,248 triangles: turquoise, with the head-up display on the glareshield and a small radar repeater upper right. The jet has 7 hardpoints for its 6 missiles.

There are four skins: `Grey` (Soviet grey and grey-green with a light radome, the default), `Euro`, `BlueGrey` (both low-visibility) and `Desert` (no national markings). The red stars are on both fins and on the wings.

## 15. F-14A Tomcat (art only)

`tools/blender/f14a_generate.py` builds the F-14A and `tools/blender/f14a_paint.py` paints it. The F-14A has no flight data yet, so this is the art for when it does: the model, skins, cockpit and manifests, with the Id `F14A`.

- The reference is Niyansfarn's Commons drawing of the F-14D (CC BY 3.0). Its top and side views are at the same scale, set from the published 19.10 m length (121.2 px/m), which gives the swept span 11.54 m against the published 11.65 m. The F-14D's airframe is the F-14A's apart from the chin pod, which is left smaller. In the overlays the model sits on the drawing's lines, apart from the wings.
- The drawing's wings are fully swept (68°). The model measures that wing and turns it 30° forward about the published pivot (half width 2.72 m), to 35°. As on the MiG-23, the wing parts have their origin on the pivot. There are slats (`LEFlap`) and flaps (`Flap`).
- The jet is built from the forward fuselage with the tandem canopy (three frames) and the flat centre body (the "pancake") ending in the beavertail. Alongside it are the separated `Nacelles` with box intakes and dark `IntakeDucts`, and the fixed `Gloves`. The tail has tailerons on the elevon controls, twin fins canted 5° (`FinL` and `FinR`) with rudders, and ventral fins.
- The jet has 35 parts and 11,308 triangles, with 8 hardpoints. The cockpit is 2,000 triangles: the HUD, the vertical display indicator (the radar face) and the horizontal situation display below it.
- The shared painter gained a `ducts` key, which paints recessed intake mouths as dark ducts. Before this, the F-16A and MiG-29A painted them in the radome colour, which on the MiG-29's Grey skin was white. That skin has been repainted.

There are four skins: `Navy` (two greys, low-visibility markings, the default), `Gull` (light gull grey over white, full-colour markings), `Ghost` (three-tone grey, low-visibility) and `Desert` (no national markings).

## 16. Mirage 2000C (art only)

`tools/blender/mirage2000_generate.py` builds the Mirage 2000C and `tools/blender/mirage2000_paint.py` paints it. Its Id is `Mirage2000C`; it has no flight data yet.

- The Mirage 2000 is laid out like the Mirage III: half-round intakes with half-cone centre bodies, a tailless delta with two elevons a side, and a single fin. So the script uses the Mirage IIIE's builders (`mirage3_generate.py`), switching that module's settings the way the jets switch the F-5E kit's. The fin with its curved dorsal fillet and the pitot are built in the script itself.
- The reference is a small (1000 px) CC BY-SA three-view of the Mirage 2000C. Its top view is drawn nose-right, and its side view has the canopy open, so the closed outline was used. The scale comes from the published 14.36 m length (42.0 px/m), which gives a 9.29 m span against the published 9.13 m. In the overlays the model sits on the drawing's lines.
- The jet has 27 parts and 10,208 triangles, with 7 hardpoints. The cockpit is 2,120 triangles: the HUD, with the radar display under it (an MFD face).

There are four skins: `AirDefence` (blue-greys over light grey, with French roundels and fin flash; the default), `Grey` (low-visibility), `Tactical` and `Desert` (no national markings).

## 17. F-15C Eagle (art only)

`tools/blender/f15c_generate.py` builds the F-15C and `tools/blender/f15c_paint.py` paints it. Its Id is `F15C`; it has no flight data yet.

- The reference is Kaboldy's Commons drawing of the F-15A (CC BY-SA 4.0), mirrored nose left. The F-15C's airframe is the F-15A's. The scale comes from the published 19.43 m length (144.5 px/m), which gives a 13.07 m span against the published 13.05 m. In the overlays the model sits on the drawing's lines; the wing's trailing edge is a straight line, where the drawing has an unswept flap and a swept aileron.
- The jet is built from the forward fuselage with the bubble canopy, running back as a central spine between the engines. Alongside it are the `Nacelles`, which run from the raked box intakes (with dark `IntakeDucts`) back to the engines, which meet at the centreline. `Strakes` holds the curved leading-edge gloves and the tail booms. The tail has tailerons on the elevon controls and twin upright fins with rudders and tip pods. The F-15 has no nose probe, so `Pitot` is the two probes on the sides of the nose.
- The F-15 has fixed leading edges, but the kit always builds `LEFlap` parts, so they are a thin strip (6% of the chord).
- The jet has 38 parts and 11,400 triangles, with 9 hardpoints: two rails on each wing pylon, four fuselage stations and the centreline. The cockpit is 2,128 triangles: the HUD, the radar display upper left (an MFD face) and the threat display upper right.

There are four skins: `ModEagle` (two ghost greys, low-visibility markings; the default), `Blue` (Air Superiority Blue, full-colour markings), `Aggressor` (blue camouflage) and `Desert` (no national markings).

## 18. F/A-18C Hornet (art only)

`tools/blender/fa18c_generate.py` builds the F/A-18C and `tools/blender/fa18c_paint.py` paints it. Its Id is `FA18C`; it has no flight data yet.

- The reference is NASA's public-domain three-view of the F/A-18, rebuilt as a composite with both views nose left. The scale comes from the published 17.07 m length (107.8 px/m), which gives an 11.54 m span over the wingtips against the published 11.43 m. In the overlays the model sits on the drawing's lines.
- The jet is built from the fuselage (the radome, the bubble canopy, the dorsal spine and the wide engine bay) and `Strakes`, the long leading-edge extensions, which slope down from the windscreen into the wing roots. Under them are the D-shaped intakes (`Nacelles`, with dark `IntakeDucts`). The wing has the big leading-edge flaps (22% of the chord), flaps, ailerons and wingtip rails. The tail has tailerons on the elevon controls and twin fins canted out 18 degrees with rudders. `Pitot` is the two probes on the sides of the nose.
- The jet has 38 parts and 10,812 triangles, with 9 hardpoints: the wingtip rails, four wing pylons, the two fuselage stations on the intakes and the centreline. The cockpit is 1,624 triangles: the HUD, the up-front control panel, the two digital displays (the left one is the radar face) and the map display below.

There are four skins: `Navy` (two greys, low-visibility markings; the default), `Gull` (gull grey over white, full-colour markings), `Adversary` (tan, brown and green, no national markings) and `Ghost` (three-tone grey, low-visibility).

## 19. Su-27S Flanker (art only)

`tools/blender/su27s_generate.py` builds the Su-27S and `tools/blender/su27s_paint.py` paints it. Its Id is `Su27S`; it has no flight data yet. The script reuses the F-15C's builders (separated nacelles, booms, twin fins), with the Su-27's own shapes and its nose probe.

- The reference is Malyszkz's public-domain Commons three-view, rendered from its SVG and rebuilt as a composite with both views nose left. Both views come out at the same scale (86.0 px/m), giving the length 22.0 m against the published 21.94 m. In the overlays the model sits on the drawing's lines.
- The jet is built from the fuselage (the drooped nose, the bubble canopy, the dorsal hump and the wide, flat centre body over the engines, ending in the tail sting). `Nacelles` are the engine nacelles under the body, with raked box intakes and dark `IntakeDucts`. `Strakes` holds the long leading-edge extensions and the tail booms. The tail has tailerons on the elevon controls and twin upright fins with rudders.
- The jet has 38 parts and 11,272 triangles, with 10 hardpoints: the wingtip rails, four wing pylons, one under each intake and the tandem pair in the tunnel. The cockpit is 2,232 triangles, in the Soviet turquoise: the HUD with the radar display under it.

There are four skins: `Flanker` (the three blue-greys over light blue, with red stars on the fins; the default), `Grey` (low-visibility), `Naval` (dark blue over light grey) and `Desert` (no national markings).

## 20. Tornado F3 (art only)

`tools/blender/tornadof3_generate.py` builds the Tornado F3 and `tools/blender/tornadof3_paint.py` paints it. Its Id is `TornadoF3`; it has no flight data yet.

- The only F3 (ADV) drawing on Commons is 533 px wide, so the reference is the large public-domain three-view of the IDS, rebuilt as a composite with both views nose left. The scale comes from the span with the wings at 25 degrees (13.91 m, 110.8 px/m). The F3 differs from the IDS by a longer radome and a fuselage plug behind the rear cockpit. The generator measures the IDS and maps every station through `stretch()`, which adds 0.60 m to the radome and spreads 1.36 m over the plug, giving 18.84 m against the published 18.68 m. With `TORNADO_IDS=1` it builds the drawing's IDS proportions instead. The overlays (`TornadoF3_overlay_*.png`) are of that build, and the model sits on the drawing's lines.
- The wings are modelled at 25 degrees of sweep, fixed, with slats (`LEFlap`), flaps and the outer surfaces on the aileron controls. The fixed `Gloves` run from the intakes out to the wing roots. `Nacelles` are the raked box intakes running back into the rear fuselage, with dark `IntakeDucts`. The tail has tailerons on the elevon controls and a single fin with its rudder and tip pod. `EjectionSeat` holds both seats.
- The jet has 36 parts and 10,648 triangles, with 8 hardpoints: two missile rails on each wing pylon and the four semi-recessed stations under the fuselage. The cockpit (the front one) is 2,256 triangles: the HUD with the radar repeater under it.
- The painter's `roundel_colours` run from the outer ring to the centre, so RAF roundels are blue, white, red.

There are four skins: `AirDefence` (two light greys, low-visibility roundels; the default), `DarkGrey` (low-visibility), `Splinter` (grey splinter camouflage, full-colour roundels) and `Desert` (desert pink, no national markings).

## 21. F-16C Block 50 (art only)

`tools/blender/f16c_generate.py` builds the F-16C Block 50 and `tools/blender/f16c_paint.py` paints it. Its Id is `F16C`; it has no flight data yet.

- The F-16C's airframe is the F-16A's, so the script imports `f16a_generate.py` (its measurements, overlays and builders) and changes what the Block 50 changes: the larger "big mouth" intake for the F110 engine, and four IFF blade antennas on the nose (`Antennas`). The painter reuses the F-16A's panel layout.
- The jet has 36 parts and 10,776 triangles, with the F-16A's 7 hardpoints. The cockpit is 1,528 triangles, with the side stick: the HUD over the up-front controls, two multifunction displays (the left one is the radar face) and the standby instruments.

There are four skins: `Viper` (two greys, low-visibility markings; the default), `Ghost` (two blues, low-visibility), `Arctic` (white and grey aggressor splinter, no national markings) and `Night` (overall dark grey, low-visibility).

## 22. F-15E Strike Eagle (art only)

`tools/blender/f15e_generate.py` builds the F-15E and `tools/blender/f15e_paint.py` paints it. Its Id is `F15E`; it has no flight data yet.

- The F-15E's airframe is the F-15C's, so the script imports `f15c_generate.py` (its measurements, overlays and builders) and changes what the F-15E changes. The canopy runs back over the rear seat, with a frame between the cockpits, and the spine rises behind it. `ConformalTanks` run along the outsides of the intakes, under the wing roots (body texture set). `Pods` are the navigation and targeting pods under the intakes, and `RearSeat` is the second seat. The painter reuses the F-15C's panel layout, with the fuselage star moved onto the tanks.
- The jet has 41 parts and 12,076 triangles, with 9 hardpoints: the four on the tanks' lower corners replace the F-15C's fuselage stations. The cockpit (the front one) is 1,648 triangles: the HUD over the up-front controls, three displays (the left one is the radar face) and standby instruments.

There are four skins: `Strike` (gunship grey all over, low-visibility markings; the default), `Ghost` (two light greys, low-visibility), `Splinter` (three-grey splinter, full-colour markings) and `Desert` (no national markings).

## 23. Su-30SM (art only)

`tools/blender/su30sm_generate.py` builds the Su-30SM and `tools/blender/su30sm_paint.py` paints it. Its Id is `Su30SM`; it has no flight data yet.

- The Su-30SM's airframe is the Su-27S's, so the script imports `su27s_generate.py` (its measurements, overlays and builders) and changes what the Su-30SM changes. The canopy runs back over the rear seat (`RearSeat`) and the dorsal hump starts behind it. The all-moving canards (`CanardL` and `CanardR`, origin on their spigots, on the elevon controls) sit on the leading-edge extensions. Two more wing pylons give 12 hardpoints. The painter reuses the Su-27S's panel layout, with the canards painted like the tailerons.
- The jet has 41 parts and 11,676 triangles. The cockpit (the front one) is 1,720 triangles, in charcoal: the HUD over two colour displays (the left one is the radar face), with standby instruments under them.

There are four skins: `VKS` (two blue-greys over light grey, red stars; the default), `Blue` (overall blue-grey, low-visibility), `Naval` (dark blue over light grey) and `Desert` (no national markings).

## 24. MiG-29SMT (art only)

`tools/blender/mig29smt_generate.py` builds the MiG-29SMT and `tools/blender/mig29smt_paint.py` paints it. Its Id is `MiG29SMT`; it has no flight data yet.

- The SMT's airframe is the MiG-29A's, so the script imports `mig29_generate.py` (its measurements, overlays and builders) and changes what the SMT changes. The dorsal hump (more fuel) is raised and widened from the canopy back to between the fins, and the retractable refuelling probe (`RefuellingProbe`) is on the left of the nose. The painter reuses the MiG-29A's panel layout.
- The jet has 39 parts and 11,996 triangles, with the MiG-29A's 7 hardpoints. The cockpit is 1,768 triangles, in charcoal: the HUD over two colour displays (the left one is the radar face), with standby instruments under them.

There are four skins: `VKS` (two greys, red stars; the default), `Blue` (overall blue-grey, low-visibility), `Splinter` (grey-green splinter) and `Desert` (no national markings).

## 25. Gripen C (art only)

`tools/blender/gripenc_generate.py` builds the Gripen C and `tools/blender/gripenc_paint.py` paints it. Its Id is `GripenC`; it has no flight data yet.

- The reference is Kaboldy's Commons three-view of the Gripen (CC BY-SA 3.0), mirrored nose left. The scale comes from the published span over the wingtip rails (8.4 m, 101.9 px/m), which gives the length 14.2 m against the published 14.1 m. In the overlays the model sits on the drawing's lines; the wing's leading edge is one straight line, where the drawing has a small dogtooth.
- The jet is built from the fuselage (the radome, the one-piece canopy and the dorsal spine) and `Intakes`, the D-shaped intakes beside the cockpit, with dark `IntakeDucts`. The all-moving canards (`CanardL` and `CanardR`, origin on their spigots, on the elevon controls) sit just ahead of the wing. The cropped delta wing has leading-edge flaps, two elevons a side (`Flap` inboard, `Aileron` outboard) and wingtip rails. There is a single fin with its rudder.
- The jet has 33 parts and 9,508 triangles, with 7 hardpoints: the wingtip rails, four wing pylons and the centreline. The cockpit is 1,544 triangles, in charcoal: the HUD over three colour displays (the middle one is the radar face), with standby instruments under them.
- The national marking is a simplified Swedish roundel: a blue disc with a yellow ring.

There are four skins: `Grey` (two greys, low-visibility markings; the default), `DarkGrey` (low-visibility), `Splinter` (greens and brown, full-colour markings) and `Arctic` (white and light grey, no national markings).

## 26. F/A-18E Super Hornet (art only)

`tools/blender/fa18e_generate.py` builds the F/A-18E and `tools/blender/fa18e_paint.py` paints it. Its Id is `FA18E`; it has no flight data yet.

- Commons has no three-view of the Super Hornet (the only US Navy drawing of it is an artwork with its weapons), so the script builds it from the F/A-18C (`fa18c_generate.py`) and the published differences. It is 1.24 m longer (18.31 m): a 0.86 m plug behind the cockpit and 0.38 m in the rear fuselage. Stations are mapped through `stretch()` before the F/A-18C module computes anything, so all of its shapes, parts and attachments follow. The wing is larger (span 13.62 m over the wingtip rails, chords 15% longer), and so are the leading-edge extensions, the tailerons and the fins. The intakes are boxier and raked more, for the caret intakes.
- The jet has 38 parts and 10,816 triangles, with 11 hardpoints: the wingtip rails, three pylons under each wing, two on the intakes and the centreline. The cockpit is the F/A-18C's layout (1,624 triangles).
- The painter reuses the F/A-18C's panel layout on the stretched stations, with the larger wing.

There are four skins: `Navy` (two greys, low-visibility markings; the default), `CAG` (the greys with full-colour markings), `Adversary` (blue splinter, no national markings) and `Ghost` (overall dark grey, low-visibility).

## 27. Su-35S (art only)

`tools/blender/su35s_generate.py` builds the Su-35S and `tools/blender/su35s_paint.py` paints it. Its Id is `Su35S`; it has no flight data yet.

- The Su-35S's airframe is the Su-27S's, so the script imports `su27s_generate.py` (its measurements, overlays and builders) and changes what the Su-35S changes: the longer, thicker tail sting, the refuelling probe on the left of the windscreen (`RefuellingProbe`), and two more wing pylons (12 hardpoints). The painter reuses the Su-27S's panel layout.
- The jet has 39 parts and 11,352 triangles. The cockpit is 1,720 triangles, in charcoal: the HUD over two large colour displays (the left one is the radar face), with standby instruments under them.

There are four skins: `VKS` (blue-grey splinter, red stars; the default), `Dark` (overall dark grey, low-visibility), `Flanker` (the Su-27's blues) and `Desert` (no national markings).

## 28. Eurofighter Typhoon (art only)

`tools/blender/typhoon_generate.py` builds the Typhoon and `tools/blender/typhoon_paint.py` paints it. Its Id is `Typhoon`; it has no flight data yet.

- The reference is Inductiveload's public-domain Commons line drawing of the Typhoon, rebuilt as a composite with both views nose left. The scale comes from the published 15.96 m length (118.1 px/m), which gives a 10.9 m span against the published 10.95 m. In the overlays the model sits on the drawing's lines.
- The jet is built from the fuselage (the radome, the bubble canopy and the spine, widening over the twin engines) and `Intakes`, the chin intake under the fuselage with its splitter, with dark `IntakeDucts`. The all-moving canards (`CanardL` and `CanardR`, origin on their spigots, on the elevon controls) sit beside the cockpit. The cropped delta wing has leading-edge flaps, two elevons a side (`Flap` inboard, `Aileron` outboard) and wingtip pods. There is a single fin with its rudder, and twin nozzles. The builders are the Gripen C's, with twin engines.
- The jet has 35 parts and 9,528 triangles, with 11 hardpoints: three pylons under each wing, four semi-recessed under the intake trunk and the centreline. The cockpit is 1,520 triangles, in charcoal: the HUD over the up-front controls and three colour displays (the middle one is the radar face).

There are four skins: `AirDefence` (light grey, low-visibility roundels; the default), `TwoTone` (two greys, full-colour RAF roundels), `DarkGrey` (low-visibility) and `Desert` (no national markings).

## 29. Rafale C (art only)

`tools/blender/rafalec_generate.py` builds the Rafale C and `tools/blender/rafalec_paint.py` paints it. Its Id is `RafaleC`; it has no flight data yet.

- The reference is Kaboldy's Commons three-view of the Rafale (CC BY-SA 3.0), cropped inside its border and scaled to 2000 px, with both views nose left. The scale comes from the published 15.27 m length (127.5 px/m), which gives a 10.8 m span against the published 10.9 m. The drawing is the two-seat Rafale B: the C's single-seat canopy is shorter, with a spine behind it. In the overlays the model sits on the drawing's lines, apart from the B's rear canopy.
- The jet is built from the fuselage (the radome, the canopy and the spine, widening forward into the canard roots and over the twin engines) and `Intakes`, either side of the cockpit under the canard roots, with dark `IntakeDucts`. The all-moving canards (`CanardL` and `CanardR`, on the elevon controls) are close-coupled ahead of the cropped delta wing, which has leading-edge flaps, two elevons a side (`Flap` inboard, `Aileron` outboard) and wingtip rails. There is a single fin with its rudder and tip pod, and twin nozzles. `Pitot` holds the nose probe and the fixed refuelling probe. The builders are the Gripen C's and the Typhoon's.
- The jet has 35 parts and 9,864 triangles, with 11 hardpoints: the wingtip rails, three pylons under each wing, two under the intakes and the centreline. The cockpit is 1,484 triangles, in charcoal, with the side stick: the HUD over the radar display (the middle face) and a colour display either side.

There are four skins: `AirDefence` (light grey, low-visibility roundels; the default), `TwoTone` (two greys, full-colour roundels), `DarkGrey` (low-visibility) and `Desert` (no national markings).
