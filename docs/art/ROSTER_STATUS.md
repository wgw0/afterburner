# Roster art status

Where each jet on the roster (DESIGN §6.2) stands in the [art pipeline](AIRCRAFT_PIPELINE.md): its exterior model, skins and cockpit. Built files are in the art branch's worktree under `tools/blender/out/`, which is kept out of git. The **Studio** column lists what's left to do in Studio: import, upload textures, add skin entries, play test.

Jets without flight data in `src/shared/AircraftData/` get the art only, under the Id in this table. Their flight data is separate design work.

| Tier | Jet | Id | Flight data | Branch | Exterior | Skins | Cockpit | Studio |
|---|---|---|---|---|---|---|---|---|
| I | F-5E Tiger II | `F5E` | Yes | master; `art/cockpits` | Done; cockpit well added | Ghost, Desert, Pacific, Lizard (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | MiG-21bis | `MiG21bis` | Yes | master; `art/cockpits` | Done; cockpit well added | Silver, Grey, Tactical (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | Mirage IIIE | `MirageIII` | Yes | `art/mirage3` (on `art/cockpits`) | Done | Tactical (default), Silver, Desert, Grey | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | Mirage F1C | `MirageF1` | Yes | `art/miragef1` (on `art/mirage3`) | Done | Interceptor (default), Tactical, Desert, Grey | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | F-4E Phantom II | `F4E` | Yes | `art/f4e` (on `art/miragef1`) | Done | SEA (default), HillGray, EuroOne, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | MiG-23MLD | `MiG23MLD` | Yes | `art/mig23` (on `art/f4e`) | Done (wings at 45°) | Tactical (default), TwoTone, Grey, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | F-16A | `F16A` | Yes | `art/f16a` (on `art/mig23`) | Done | Falcon (default), Blue, Desert, Euro | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | MiG-29A | `MiG29A` | Yes | `art/mig29` (on `art/f16a`) | Done | Grey (default), Euro, BlueGrey, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | F-14A Tomcat | `F14A` | No | `art/f14a` (on `art/mig29`) | Done (wings at 35°) | Navy (default), Gull, Ghost, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| III | Mirage 2000C | `Mirage2000C` | No | `art/mirage2000` (on `art/f14a`) | Done | AirDefence (default), Grey, Tactical, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| IV | F-15C Eagle | `F15C` | No | | | | | |
| IV | F/A-18C | `FA18C` | No | | | | | |
| IV | Su-27S | `Su27S` | No | | | | | |
| IV | Tornado F3 | `TornadoF3` | No | | | | | |
| V | F-16C Block 50 | `F16C` | No | | | | | |
| V | F-15E | `F15E` | No | | | | | |
| V | Su-30SM | `Su30SM` | No | | | | | |
| V | MiG-29SMT | `MiG29SMT` | No | | | | | |
| V | Gripen C | `GripenC` | No | | | | | |
| VI | F/A-18E Super Hornet | `FA18E` | No | | | | | |
| VI | Su-35S | `Su35S` | No | | | | | |
| VI | Eurofighter Typhoon | `Typhoon` | No | | | | | |
| VI | Rafale C | `RafaleC` | No | | | | | |
| VII | F-22A Raptor | `F22A` | No | | | | | |
| VII | F-35A | `F35A` | No | | | | | |
| VII | Su-57 | `Su57` | No | | | | | |
| VIII | Tempest-class concept | `Tempest` | No | | | | | |

## Cockpit system (`art/cockpits`)

The cockpit interiors and the code that shows them (art pipeline §7). The new code is in `tools/AircraftAssembler.luau` (`installCockpit`) and `src/client/Controllers/CockpitController.luau`. Jets without a cockpit model still get the greybox kit, so the branch can be merged before any cockpit is installed.

Files in `tools/blender/out/` (absolute paths are in the hand-over report):

| Jet | Exterior (re-import) | Cockpit | Cockpit textures | Previews |
|---|---|---|---|---|
| F-5E | `F5E_base.fbx` | `F5E_cockpit.fbx` | `F5E_Cockpit_{Color,Normal,Roughness,Metalness}.png` | `F5E_cockpit_{ahead,panel,left,outside}.png` |
| MiG-21bis | `MiG21bis_base.fbx` | `MiG21bis_cockpit.fbx` | `MiG21bis_Cockpit_{Color,Normal,Roughness,Metalness}.png` | `MiG21bis_cockpit_{ahead,panel,left,outside}.png` |

To do in Studio, for each jet:
1. Re-import `<Id>_base.fbx` and run `AircraftAssembler.install("<Id>", ...)`. The fuselage now has the cockpit well. The UVs haven't changed, so the existing skins still apply.
2. Upload the four `<Id>_Cockpit_*.png` maps.
3. Import `<Id>_cockpit.fbx`, then run `AircraftAssembler.installCockpit("<Id>", workspace.<Id>_cockpit, { Color = …, Normal = …, Roughness = …, Metalness = … })`.
4. Play test in the cockpit view. Check that the gauges sit in their bezels, the radar scope sweeps, nothing pokes through the canopy, and the view over the nose is clear.

Optional: repaint and re-upload the skins to paint the inside of the well dark for other players. Without a repaint, other players see the old paint stretched down into the well through the canopy.

## Mirage IIIE (`art/mirage3`)

Built on `art/cockpits`, so merge that branch first. This branch also adds the `ElevonL` and `ElevonR` controls to `Shared.ControlSurfaces`, with tests, and the four skin entries to `Shared.Config.Skins`.

Files in `tools/blender/out/`:
- Model: `MirageIII_base.fbx`, plus `MirageIII_manifest.json` and `tools/Manifests/MirageIII.luau`
- Skins: in `textures/`, `MirageIII_<Skin>_<Set>_<Map>.png` for the Tactical, Silver, Desert and Grey skins, 12 PNGs each
- Cockpit: `MirageIII_cockpit.fbx` and `MirageIII_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MirageIII_{side,top,front,threequarter}.png`, `MirageIII_overlay_{side,top}.png`, `textures/MirageIII_<Skin>_paint_*.png` and `MirageIII_cockpit_*.png`

To do in Studio:
1. Import `MirageIII_base.fbx`, then run `AircraftAssembler.install("MirageIII", workspace.MirageIII_base)`. The assembler lines up a single-nozzle import on `Nozzle`.
2. Upload the skins and make `Assets.Skins.MirageIII.<Skin>` with a SurfaceAppearance per set (Body, Wings, Details).
3. Import and install the cockpit, as for the F-5E.
4. Play test. Check that the elevons move with the stick (both up for pitch, opposite for roll), that the rudder works, and the view from the cockpit.

## Mirage F1C (`art/miragef1`)

Built on `art/mirage3` (which is built on `art/cockpits`), so merge those first. This branch also adds the shared skin painter `jet_paint.py`. The Mirage IIIE's paint script now uses it, and its four skins were repainted with it in `tools/blender/out/textures`; the change is only in fine panel lines, but upload these PNGs rather than the earlier ones.

Files in `tools/blender/out/`:
- Model: `MirageF1_base.fbx`, plus `tools/Manifests/MirageF1.luau`
- Skins: `textures/MirageF1_<Skin>_<Set>_<Map>.png` for the Interceptor, Tactical, Desert and Grey skins
- Cockpit: `MirageF1_cockpit.fbx` and `MirageF1_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MirageF1_{side,top,front,threequarter}.png`, `MirageF1_overlay_{side,top}.png`, `textures/MirageF1_<Skin>_paint_*.png` and `MirageF1_cockpit_*.png`

To do in Studio: import, `install("MirageF1", workspace.MirageF1_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The F1C uses the existing aileron, flap, leading-edge flap, stabilator and rudder controls.

## F-4E Phantom II (`art/f4e`)

Built on `art/miragef1`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `F4E_base.fbx`, plus `tools/Manifests/F4E.luau`
- Skins: `textures/F4E_<Skin>_<Set>_<Map>.png` for the SEA, HillGray, EuroOne and Desert skins
- Cockpit: `F4E_cockpit.fbx` and `F4E_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F4E_{side,top,front,threequarter}.png`, `F4E_overlay_{side,top}.png`, `textures/F4E_<Skin>_paint_*.png` and `F4E_cockpit_*.png`

To do in Studio: import the model, run `install("F4E", workspace.F4E_base)` (the assembler lines up twin nozzles on `NozzleL` and `NozzleR`), make the skin SurfaceAppearances, install the cockpit, then play test. The outer wing panels and outer leading-edge flaps are separate parts: `WingOuterL`, `WingOuterR`, `LEFlapOuterL` and `LEFlapOuterR`.

## MiG-23MLD (`art/mig23`)

Built on `art/f4e`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `MiG23MLD_base.fbx`, plus `tools/Manifests/MiG23MLD.luau`
- Skins: `textures/MiG23MLD_<Skin>_<Set>_<Map>.png` for the Tactical, TwoTone, Grey and Desert skins
- Cockpit: `MiG23MLD_cockpit.fbx` and `MiG23MLD_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MiG23MLD_{side,top,front,threequarter}.png`, `MiG23MLD_overlay_{side,top}.png` (with the wings spread, to compare with the drawing), `textures/MiG23MLD_<Skin>_paint_*.png` and `MiG23MLD_cockpit_*.png`

To do in Studio: import the model, run `install("MiG23MLD", workspace.MiG23MLD_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The tailerons use the elevon controls, so check that they move together for pitch and in opposite directions for roll.

## F-16A (`art/f16a`)

Built on `art/mig23`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `F16A_base.fbx`, plus `tools/Manifests/F16A.luau`
- Skins: `textures/F16A_<Skin>_<Set>_<Map>.png` for the Falcon, Blue, Desert and Euro skins
- Cockpit: `F16A_cockpit.fbx` and `F16A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F16A_{side,top,front,threequarter}.png`, `F16A_overlay_{side,top}.png`, `textures/F16A_<Skin>_paint_*.png` and `F16A_cockpit_*.png`

To do in Studio: import the model, run `install("F16A", workspace.F16A_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The tailerons use the elevon controls.

## MiG-29A (`art/mig29`)

Built on `art/f16a`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `MiG29A_base.fbx`, plus `tools/Manifests/MiG29A.luau`
- Skins: `textures/MiG29A_<Skin>_<Set>_<Map>.png` for the Grey, Euro, BlueGrey and Desert skins
- Cockpit: `MiG29A_cockpit.fbx` and `MiG29A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MiG29A_{side,top,front,threequarter}.png`, `MiG29A_overlay_{side,top}.png`, `textures/MiG29A_<Skin>_paint_*.png` and `MiG29A_cockpit_*.png`

To do in Studio: import the model, run `install("MiG29A", workspace.MiG29A_base)` (twin nozzles, `NozzleL` and `NozzleR`), make the skin SurfaceAppearances, install the cockpit, then play test. Both rudders are on the `Rudder` control, and the stabilators are on the elevon controls.

## F-14A Tomcat (`art/f14a`, art only)

Built on `art/mig29`. This branch also repaints the MiG-29A's Grey skin: its intake mouths were white, and are now dark ducts. Re-upload the 4 `MiG29A_Grey_Body_*.png` maps (only the Color map changed).

Files in `tools/blender/out/`:
- Model: `F14A_base.fbx`, plus `tools/Manifests/F14A.luau`
- Skins: `textures/F14A_<Skin>_<Set>_<Map>.png` for the Navy, Gull, Ghost and Desert skins
- Cockpit: `F14A_cockpit.fbx` and `F14A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F14A_{side,top,front,threequarter}.png`, `F14A_overlay_{side,top}.png`, `textures/F14A_<Skin>_paint_*.png` and `F14A_cockpit_*.png`

To do in Studio, when the F-14A gets flight data (an `AircraftData/F14A.luau` with `ModelName = "F14A"`): import the model, run `install("F14A", workspace.F14A_base)`, make the skin SurfaceAppearances, install the cockpit, then play test.

## Mirage 2000C (`art/mirage2000`, art only)

Built on `art/f14a`. Files in `tools/blender/out/`: `Mirage2000C_base.fbx` (manifest `tools/Manifests/Mirage2000C.luau`), `textures/Mirage2000C_<Skin>_<Set>_<Map>.png` for the AirDefence, Grey, Tactical and Desert skins, `Mirage2000C_cockpit.fbx` and `Mirage2000C_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Mirage2000C_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Mirage2000C_<Skin>_paint_*.png` and `Mirage2000C_cockpit_*.png`). Install it like the other jets once `AircraftData/Mirage2000C.luau` exists, with `ModelName = "Mirage2000C"`.
