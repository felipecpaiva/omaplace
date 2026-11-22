"""Build the feature GIFs and MP4s from the frames the Qt demo test saved (OMAPLACE_DEMO_OUT), with omakit's gifkit
(the sibling ../omakit checkout, or OMAKIT_PATH). Usage: python3 app/tests/demo_gifs.py <frames folder>"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.environ.get("OMAKIT_PATH") or os.path.join(os.path.dirname(ROOT), "omakit"))
from omakit import gifkit

src = sys.argv[1]
out = os.path.join(ROOT, "branding", "demo")
for name in sorted(os.listdir(src)):
    scene = os.path.join(src, name, "scene.json")
    if not os.path.exists(scene):
        continue
    s = json.load(open(scene))
    frames = [(t, p) for t, p in s["frames"]]
    marks = [(t, m) for t, m in s["marks"]]
    print("wrote", gifkit.build(frames, s["total"], marks, out, name, y="h-64", fontsize=30)[0])
