"""
Afterburner: builds a jet's cockpit interior (see cockpit_kit.py and art pipeline §7).

  blender -b --python tools/blender/cockpit_generate.py -- --airframe F5E --out <dir> \
      --manifest-luau tools/Manifests/Cockpits/F5E.luau

Writes <Id>_cockpit.blend, <Id>_cockpit.fbx and <Id>_cockpit_manifest.json. The jet's own generator script
holds its COCKPIT spec and configures the shared kit, so the cockpit fits that jet's canopy and fuselage.
"""

import argparse
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Airframe Id -> the generator script that describes it
GENERATORS = {
    "F5E": "f5e_generate",
    "MiG21bis": "mig21_generate",
    "MirageIII": "mirage3_generate",
    "MirageF1": "miragef1_generate",
    "F4E": "f4e_generate",
    "MiG23MLD": "mig23_generate",
    "F16A": "f16a_generate",
    "MiG29A": "mig29_generate",
    "F14A": "f14a_generate",
    "Mirage2000C": "mirage2000_generate",
    "F15C": "f15c_generate",
    "FA18C": "fa18c_generate",
    "Su27S": "su27s_generate",
    "TornadoF3": "tornadof3_generate",
    "F16C": "f16c_generate",
    "F15E": "f15e_generate",
    "Su30SM": "su30sm_generate",
    "MiG29SMT": "mig29smt_generate",
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--airframe", required=True)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--manifest-luau", default=None)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    importlib.import_module(GENERATORS[args.airframe])  # configures the shared kit for this jet
    import cockpit_kit

    cockpit_kit.build(args.out, args.manifest_luau)


if __name__ == "__main__":
    main()
