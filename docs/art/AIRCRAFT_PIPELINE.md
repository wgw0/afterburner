# Aircraft model pipeline

How every jet goes from Blender into the game: a modular, mid-poly model with animated control surfaces and swappable PBR skins. The jets are rebuilt in the order players meet them; the **F-5E Tiger II** is first.

| Stage | Who | Status (F-5E) |
|---|---|---|
| 1. Base mesh from published dimensions | `tools/blender/f5e_generate.py` (automatic) | ✅ 35 parts, 8,322 triangles |
| 2. Refine shapes, add detail | Blender, by hand | ⬜ |
| 3. Bake + paint PBR textures (Body, Wings, Details) | Blender / Substance Painter, by hand | ⬜ |
| 4. Import into Studio | Studio 3D Importer | ⬜ |
| 5. Assemble (Root, Hull, hitboxes, attachments, hinges, skin) | `AircraftAssembler` tool, reads the manifest | ⬜ to build |
| 6. Validate | Model contract in Studio and CI (Lune) | ✅ in place |

---

## 1. Structure (F-5E)

**Axes and scale.** Blender: X right, **Y forward (nose toward +Y)**, Z up, metres. The FBX exporter (Forward −Z, Up Y) turns Blender +Y into Roblox −Z, the nose direction the game expects. The game uses **1 m = 3.5714 studs**. Every part keeps the real-world size; the assembler scales to studs.

**Budget.** 5,000–12,000 triangles for the whole jet (the F-5E base is 8,322). Roblox allows 20,000 per MeshPart, so the limit is performance, not the engine.

**Separate objects.** Nothing is merged. Moving parts have their **origin on the hinge line** with identity rotation (aligned to world axes); the hinge axis and limits are stored on the object (`afterburner_hinge_axis`) and in the manifest.

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

The gear is modelled down; in flight the game keeps it retracted (hidden until the takeoff and landing work).

**The manifest** (`tools/blender/out/F5E_manifest.json`, and `tools/Manifests/F5E.luau` for Studio) lists every part with its texture set, kind, pivot and hinge, plus the gameplay data the game already uses: attachment points (`CockpitEye`, `GunMuzzle`, `Nozzle1/2`, `WingtipL/R`, dispensers, `ChaseCam`, `Hardpoint1–3`), the collision hull and the six hitboxes. These are carried over from the greybox F-5E, so the new model plays exactly the same.

---

## 2. Textures and skins (PBR)

### Texture sets

| Set | Parts | Size | Maps |
|---|---|---|---|
| **Body** | fuselage, intakes, LERX, fin, rudder, canopy frame | 1024² | Color, Normal, Roughness, Metalness |
| **Wings** | wings, flaps, ailerons, LE flaps, stabilators | 1024² | Color, Normal, Roughness, Metalness |
| **Details** | nozzles, afterburners, gear, seat, rails, pitot | 512² | Color, Normal, Roughness, Metalness |
| **Glass** | canopy | none | flat values (see below) |

1024² is the largest image Roblox accepts. Two 1024² sets give the airframe twice the texel density of one, which matters for close-up hangar views.

**Look.**
- **Paint:** matte tactical paint, roughness 0.55–0.7, metalness 0.
- **Weathering:** in Color and Roughness: exhaust soot behind the nozzles, gun-port soot, walkway scuffs, rain streaks.
- **Exhausts:** exposed titanium and steel at metalness 0.8–1, roughness 0.3–0.45, with heat tint near the nozzles.
- **Panel gaps, rivets, fasteners:** only in the Normal map. No extra geometry for them.

**Canopy glass.** Don't use Roblox's `Glass` material, which draws opaque over water. The canopy uses SmoothPlastic with transparency 0.55–0.65, reflectance 0.15 and a faint blue-grey tint (or a `SurfaceAppearance` with `AlphaMode = Transparency` and roughness 0).

### How skins work (built for selling them)

Every skin for an airframe shares the **same UV layout**, so a skin is only a set of textures:

```
ReplicatedStorage.Assets.Skins.F5E
├── Default        Body / Wings / Details   (SurfaceAppearance each)
├── Aggressor      Body / Wings / Details
└── ...
```

- **Applying a skin** means cloning that skin's `SurfaceAppearance` into each MeshPart of the matching set (every MeshPart carries a `TextureSet` attribute). Roblox doesn't let scripts change a SurfaceAppearance's images at runtime, so skins are swapped as whole instances, never edited.
- **Cheap colour variants.** A skin can use `AlphaMode = Overlay`: where the Color map's alpha is transparent, the MeshPart's own `Color` shows through. So one texture set gives many paint colours (sell or reward recolours without new art), while markings, weathering and panel lines stay on top.
- **Numbers and squadron markings** go in the skin's Color map. Per-player text (callsigns) is a later feature using `SurfaceGui` on small flat panels.
- **Ownership and selling.** The save already has `Cosmetics.Camos` and `Aircraft[id].Camo`. The server checks ownership and stamps the skin id on the jet at spawn (a `Camo` attribute). The skin is applied on the server, so every player sees it. Sold through the shop in Phase 7 (Wings or Robux, plus season-pass rewards).
- **Memory.** One skin per jet in a match is about 2 × 1024² + 512² × 4 maps. A full server of the same jet shares one copy of each texture.

---

## 3. Blender workflow

### Generate the base

```
blender -b --python tools/blender/f5e_generate.py -- --out tools/blender/out --manifest-luau tools/Manifests/F5E.luau
blender -b tools/blender/out/F5E_base.blend --python tools/blender/render_views.py -- --out <absolute path>/tools/blender/out
stylua tools/Manifests
```

This gives `F5E_base.blend` (collections per texture set, one material per set, UVs packed per set), `F5E_base.fbx`, the manifest and reference renders.

### Refine (by hand, starting from `F5E_base.blend`)

1. **Work on one half.** For symmetrical parts, delete the −X half, add a **Mirror** modifier (axis X, Clipping on, Merge on), and keep editing the +X side. Apply the modifier before export.
2. **Fuselage curves.** Keep the lofted section loops as your edge flow. Shape with proportional editing (Connected only), never by adding loops at random. For the F-5E's shark nose chine, add one loop either side of the chine line and pull it out.
3. **Intakes.** Keep the D-section loops. Add a **Bevel** modifier on the lip (width 0.02 m, 2 segments, Limit Method: Weight; bevel-weight only the lip edges). Add a thin splitter plate as a separate object on the fuselage.
4. **Wings and tail.** The airfoil sections are already correct; don't subdivide them. Mark the leading edges sharp only if a Bevel modifier rounds them (Limit Method: Angle 30°, 1 segment). Keep the surfaces as separate objects and leave their origins where they are.
5. **Smoothing.** Use smooth shading by angle (30–35°). Use a **Subdivision Surface** modifier only while shaping. If you apply it, apply level 1 at most on the fuselage, then check the triangle count.
6. **High-poly for baking.** Duplicate the Body and Wings objects into a `HighPoly` collection. Add Subdivision level 2, then cut panel lines with knife and Bevel, and add rivet rows with an array of small cylinders (or Boolean). Never export this collection.
7. **Bake.** In Cycles, select the high-poly then the mid-poly and bake Normal (Selected to Active, cage extrusion ~0.02 m) into each set's 1024² image. Also bake Ambient Occlusion and Curvature as masks for weathering.
8. **Paint.** In Blender texture paint or Substance Painter, paint Color, Roughness and Metalness per set. Export PNGs named `F5E_<Set>_<Map>.png` (for example `F5E_Body_Normal.png`), in OpenGL normal format (Roblox expects OpenGL, Y+).
9. **Re-run the checks.** Keep the object names, origins and texture sets the same, so the manifest stays valid. If anything moves, re-run the generator or update the manifest.

---

## 4. Roblox Studio import checklist

**Export (Blender → FBX).** The generator does this; repeat these settings if you export by hand:
- [ ] Selected objects only: mesh objects, no empties, no HighPoly collection.
- [ ] Scale 1.0, **Apply Scalings: FBX All**, **Apply Unit** on.
- [ ] **Forward: −Z Forward, Up: Y Up**, Apply Transform (bake space transform) on.
- [ ] Geometry: Smoothing Face, Apply Modifiers on, no leaf bones.
- [ ] Object names unchanged (`AileronL`, `Fuselage`…): the assembler finds parts by name.

**Import (Studio → File → Import 3D).**
- [ ] Import as a **single Model** (not as separate assets). This keeps every part in place relative to the others.
- [ ] **Anchored** on, "Insert using scene position" on.
- [ ] File unit: **Meter**. The assembler checks the imported length against the manifest (14.45 m = 51.6 studs) and rescales if the importer got it wrong.
- [ ] Textures: don't import materials. Skins are made separately (below).
- [ ] Put the imported Model in `ServerStorage` and run the **AircraftAssembler** with its manifest. It builds the game model in `ReplicatedStorage.Assets.Aircraft.F5E`:
  - Root, Hull and the six hitboxes
  - the attachment points
  - **Motor6D joints on the hinge points** for the control surfaces and gear
  - WeldConstraints for the static parts
  - Massless, collisions off, CollisionFidelity Box, RenderFidelity Automatic
  - a `TextureSet` attribute on each part
  - the Default skin

  It then runs the model contract.

**Textures (Asset Manager).**
- [ ] Use **Bulk Import** for the PNGs (12 per skin). This is the right tool for images.
- [ ] Don't bulk-import the meshes: Bulk Import uploads each mesh as a standalone asset and loses the hierarchy and positions.
- [ ] Create a `SurfaceAppearance` per set (ColorMap, NormalMap, RoughnessMap, MetalnessMap), named after the set, under `Assets.Skins.F5E.<SkinId>`.

**Why pivots don't depend on the importer.** The 3D importer positions MeshParts by their bounding boxes, and pivot handling has changed between Studio versions. The control-surface hinges are set from the manifest, so the flight scripts get exact hinge axes whatever the importer does with origins.

**Checks.**
- [ ] The model contract passes in Studio (`Model.spec`) and in CI (`lune run scripts/validate-models.luau`).
- [ ] The nose points −Z: the contract fails if `GunMuzzle` is behind the centre.
- [ ] In play: the control surfaces move with the stick, and the cockpit eye sits inside the canopy.

---

## 5. Game-side work still to do (before the first new model goes in)

1. **AircraftAssembler** (Studio tool): manifest + imported model → contract-ready jet (see the checklist).
2. **Model contract update**: allow MeshParts, Motor6D joints for parts of kind `ControlSurface`, `Gear`, `GearDoor` and `GearWheel` (instead of welds), a `TextureSet` attribute, and a part limit of 60.
3. **ControlSurfaceController** (client): drives the Motor6Ds from each jet's flight input (ailerons from roll, stabilators from pitch, rudder from yaw, flaps from speed and AoA), and replicates the same animation for other players' jets from telemetry.
4. **Skins**: `Assets.Skins`, applying the `Camo` attribute at spawn, and the skin picker on the aircraft detail screen.
