"""Copies the plugin's pure js/ libraries into generated/js (ignored by git) and writes resources.qrc, so the app and
the plugin share one copy of the layout, zone and settings logic. The files are embedded unchanged in the binary."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parent
out = root / "generated" / "js"
out.mkdir(parents=True, exist_ok=True)
for p in (root.parent / "js").glob("*.js"):
    shutil.copyfile(p, out / p.name)
files = [("js/" + p.name, p) for p in sorted(out.glob("*.js"))]
files += [("qml/" + p.name, p) for p in sorted((root / "qml").glob("*")) if p.suffix in (".qml", ".js")]
files += [("icon.svg", root / "omaplace-settings.svg")]
entries = "".join(f'<file alias="{a}">{p.relative_to(root)}</file>' for a, p in files)
(root / "resources.qrc").write_text('<RCC><qresource prefix="/">' + entries + "</qresource></RCC>\n")
