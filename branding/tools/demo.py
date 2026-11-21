#!/usr/bin/env python3
"""Records the omaplace feature GIFs from the REAL plugin on a spare, empty workspace 8 (never a virtual monitor).
Mouse only (uinput moves and clicks, never keys), hyprctl eval for pointer warps and window dispatch, plus the omaplace
CLI and settings file edits. gifkit.py turns each scene into a captioned GIF and MP4 in branding/demo/.
Scenes: desktops, snap, update, scenes. --calibrate takes screenshots for the coordinates below and records nothing.
Privacy: Do Not Disturb is on for the whole run. The update scene turns it off only from the click that triggers the
"Update plan" notification until its button is pressed, zooms the capture onto the notification area for that part,
and throws the GIF away if any other notification showed meanwhile. Demo windows show only this repository's README
(a terminal with class omaplace-demo, so your own terminals are never planned) and Omacalc.
Restore: scenes.toml, config.toml and their .bak files, the demo launcher entry, workspace 8's mode (Omarchy's own
toggle), Omarchy's mode file for 8 if it was new, Do Not Disturb, the pointer and your workspace are put back, also on
an error. Needs one monitor, grim, ffmpeg, kitty, bat, omacalc, gio, the plugin enabled with its Lua line loaded, and
the omahop repo next to this one (its uinput helper). Do not touch the keyboard or mouse while it runs (about 2 minutes).
Usage: python3 branding/tools/demo.py [scene ...]      (no argument: all scenes)
       python3 branding/tools/demo.py --calibrate      (screenshots to branding/demo/calibrate*.png, gitignored)"""
import json, os, re, shutil, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(os.path.dirname(ROOT), "omahop", "tests"))
from uinput_kbd import Mouse
import gifkit

OUT = os.path.join(ROOT, "branding", "demo")
BIN = os.path.join(ROOT, "bin", "omaplace")
HOME = os.path.expanduser("~")
CFG_DIR = os.path.join(HOME, ".config", "omaplace")
SCENES = os.path.join(CFG_DIR, "scenes.toml")
CONFIG = os.path.join(CFG_DIR, "config.toml")
PLANS = os.path.join(HOME, ".local", "state", "omaplace", "plans.lua")
ENTRY = os.path.join(HOME, ".local", "share", "applications", "omaplace-demo.desktop")
MOVES = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "omaplace", "plan-moves.json")
PLUGIN = "io.github.felipecpaiva.omaplace"
SPARE = 8
PLAN = "demo-desk"
DEMO_CLASS = "omaplace-demo"

# ---- coordinates, logical px of the whole screen. Read them from branding/demo/calibrate*.png (--calibrate).
SCREEN = (1600, 1000)        # logical size of the monitor (for example 2560x1600 at scale 1.6); checked before the run
DESKTOPS_TAB = (0, 0)        # the "Desktops" page button in the settings window (clicked so the page is sure to be first)
DESK8_CARD = (0, 0)          # the desktop 8 tile on the Desktops page
EDITOR_SCROLL = 0            # wheel clicks down after picking the tile, if "Open all" is below the fold
OPEN_ALL = (0, 0)            # the "Open all" button of desktop 8's editor (after EDITOR_SCROLL)
OMACALC_GRAB = (60, 14)      # where to press on Omacalc to drag it, from its top-left corner (its title bar)
DRAG_BY = -600               # how far the drag moves Omacalc: its centre ends in the left zone, a strip of the terminal stays
NOTIF_ZOOM = 2               # the notification part is captured at SCREEN / NOTIF_ZOOM, scaled up to the same frame size
NOTIF_AT = (800, 0)          # top-left of that zoomed region (Omarchy puts notifications top right)
NOTIF_BUTTON = (0, 0)        # the "Update plan" button on the notification card
FULL = f"0,0 {SCREEN[0]}x{SCREEN[1]}"
NOTIF = f"{NOTIF_AT[0]},{NOTIF_AT[1]} {SCREEN[0] // NOTIF_ZOOM}x{SCREEN[1] // NOTIF_ZOOM}"
assert SCREEN[0] % NOTIF_ZOOM == 0 and SCREEN[1] % NOTIF_ZOOM == 0, "the zoomed frames must have the full frames' pixel size"

REL = os.path.relpath(ROOT, HOME)
CD = ROOT if REL.startswith("..") else "~/" + REL   # ~ so the home folder's name is never written into the plan
README_CMD = f"cd {CD} && bat --paging=never --style=plain --color=always --line-range=9:60 README.md; sleep 3600"
DEMO_TERM = f"kitty --class {DEMO_CLASS} --title README.md -e sh -c '{README_CMD}'"

# The plan: 2 columns on desktop 8 of the focused monitor, the README terminal left, Omacalc right (design 14.2).
# scenes.toml strings hold no double quote, so the terminal command quotes with single quotes only.
PLAN_TOML = f"""schema = 1

[scene.{PLAN}]
plan = true
layout = "columns:2"
home_monitor = ""
home_slot = {SPARE}
open_at_login = false

[scene.{PLAN}.window.1]
app = "{DEMO_CLASS}"
class = "{DEMO_CLASS}"
launch = "{DEMO_TERM}"
zone = 1

[scene.{PLAN}.window.2]
app = "omacalc"
class = "omacalc"
zone = 2
"""
# app memory and the session snapshot are off during the run, so neither keeps the demo windows afterwards
CONFIG_TOML = 'schema = 1\napp_memory = "off"\nsession = "off"\n'
# A launcher entry for the demo terminal: the Desktops page shows "README" with kitty's icon and a confirmed class, and a
# saved scene can start it again. Exec quotes with double quotes, as the desktop entry spec wants.
ENTRY_TEXT = f"""[Desktop Entry]
Type=Application
Name=README
Comment=omaplace demo terminal, removed when the demo ends
Exec=kitty --class {DEMO_CLASS} --title README.md -e sh -c "{README_CMD}"
Icon=kitty
StartupWMClass={DEMO_CLASS}
"""

m = None
scale = 1.0
settings_open = False


def sh(*a): return subprocess.run(a, capture_output=True, text=True).stdout.strip()
def ev(lua): subprocess.run(["hyprctl", "eval", lua], capture_output=True)
def clients(): return json.loads(sh("hyprctl", "clients", "-j") or "[]")
def to(x, y): ev(f"hl.dispatch(hl.dsp.cursor.move({{ x = {round(x)}, y = {round(y)} }}))"); time.sleep(0.12)
def click(): m.press(); time.sleep(0.05); m.release()
def tap(x, y): to(x, y); time.sleep(0.3); click()
def focus_ws(ws): ev(f'hl.dispatch(hl.dsp.focus({{ workspace = "{ws}" }}))'); time.sleep(0.8)
def launch(cmd, rule=""): ev(f'hl.exec_cmd("{("[" + rule + "] ") if rule else ""}{cmd}")')
def notif(*a): return sh("omarchy-shell", "notifications", *a)
def dnd(on): notif("setDnd", "on" if on else "off")
def ws_mode(): return sh("omarchy-hyprland-workspace-layout-current", str(SPARE))
def trash(path):
    if os.path.lexists(path): subprocess.run(["gio", "trash", path], capture_output=True)


def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".demo-tmp"
    with open(tmp, "wb") as f: f.write(text if isinstance(text, bytes) else text.encode())
    os.replace(tmp, path)


def cli(*a, ok=(0,)):
    """bin/omaplace with its own notifications off (the service still sends run summaries, silenced by Do Not Disturb)."""
    p = subprocess.run([BIN, *a], capture_output=True, text=True, env={**os.environ, "OMAPLACE_NOTIFY": "0"})
    if p.returncode not in ok:
        raise RuntimeError(f"omaplace {' '.join(a)} exited {p.returncode}: {(p.stdout + p.stderr).strip()}")
    return p.stdout.strip()


def settings(want):
    """The settings window keeps the keyboard and refuses focus changes, so the script always knows whether it is open."""
    global settings_open
    if settings_open != want:
        sh("omarchy-shell", "shell", "toggle", PLUGIN); settings_open = want; time.sleep(1.5)


def rescan():
    """Opening the settings window reads scenes.toml again and rebuilds plans.lua (a watch can miss a new file, live-M5)."""
    settings(True); time.sleep(0.5); settings(False)


def ours(c): return c["workspace"]["id"] == SPARE or c["class"] in (DEMO_CLASS, "omacalc")


def wait_for(classes, seconds=10.0):
    end = time.time() + seconds
    while time.time() < end:
        have = {c["class"] for c in clients() if c["workspace"]["id"] == SPARE}
        if set(classes) <= have: return True
        time.sleep(0.25)
    print(f"  warning: {sorted(classes)} not all on desktop {SPARE} after {seconds:.0f} s", flush=True)
    return False


def close(cls=None):
    """Close the demo windows (preflight made sure every window on 8 and every window of these classes is ours)."""
    for c in clients():
        if ours(c) and (cls is None or c["class"] == cls):
            ev(f'local w = hl.get_window("address:{c["address"]}"); if w then hl.dispatch(hl.dsp.window.close({{ window = w }})) end')
    end = time.time() + 5
    while time.time() < end and any(ours(c) and (cls is None or c["class"] == cls) for c in clients()): time.sleep(0.2)
    time.sleep(0.5)


def window(cls): return next((c for c in clients() if c["class"] == cls and c["workspace"]["id"] == SPARE), None)


def zones():
    """{class: zone} of the demo plan in scenes.toml, read with a regex (the file is ours during the run)."""
    out, cls, inplan = {}, None, False
    try: text = open(SCENES).read()
    except OSError: return out
    for line in text.splitlines():
        if line.startswith("["): cls = None; inplan = line.startswith(f"[scene.{PLAN}.window.")
        elif inplan and (k := re.match(r'\s*class\s*=\s*"([^"]*)"', line)): cls = k.group(1)
        elif inplan and cls and (k := re.match(r"\s*zone\s*=\s*(\d+)", line)): out[cls] = int(k.group(1))
    return out


def moves_seq():
    try: return json.load(open(MOVES)).get("seq", 0)
    except (OSError, ValueError): return 0


class Recorder:
    """grim frame loop. region and zoom can change mid scene; every frame keeps the full region's pixel size."""
    def __init__(self, region=FULL):
        self.region, self.zoom, self.frames, self.marks, self.stop = region, 1, [], [], threading.Event()
        self.dir = tempfile.mkdtemp(prefix="omaplace-demo-")

    def __enter__(self):
        self.t0 = time.time()
        def grab():
            n = 0
            while not self.stop.is_set():
                p = os.path.join(self.dir, f"f{n:05d}.jpg"); a = time.time() - self.t0
                subprocess.run(["grim", "-s", str(self.zoom), "-g", self.region, "-t", "jpeg", "-q", "88", p], capture_output=True)
                self.frames.append((a, p)); n += 1
        self.th = threading.Thread(target=grab); self.th.start()
        return self

    def look(self, region, zoom=1): self.region, self.zoom = region, zoom
    def caption(self, text): self.marks.append((time.time() - self.t0, text))

    def finish(self, name):
        self.marks.append((time.time() - self.t0, ""))
        self.stop.set(); self.th.join()
        total = time.time() - self.t0
        gifkit.build(self.frames, total, self.marks, OUT, name)
        shutil.rmtree(self.dir, ignore_errors=True)
        print(f"wrote {name}.gif ({os.path.getsize(os.path.join(OUT, name + '.gif')) // 1024} KB, {total:.0f} s, {len(self.frames) / total:.0f} fps captured)", flush=True)

    def __exit__(self, *exc):
        self.stop.set()
        if self.th.is_alive(): self.th.join()
        shutil.rmtree(self.dir, ignore_errors=True)


class ToastWatch:
    """Counts the notification cards on screen while Do Not Disturb is off; the most seen decides if the GIF is clean."""
    def __enter__(self):
        self.most, self.stop = 0, threading.Event()
        def poll():
            while not self.stop.is_set():
                try: self.most = max(self.most, int(notif("count") or 0))
                except ValueError: pass
                time.sleep(0.15)
        self.th = threading.Thread(target=poll); self.th.start()
        return self

    def __exit__(self, *exc): self.stop.set(); self.th.join()


def baseline():
    """Desktop 8 empty, the settings window closed, scenes.toml holding only the demo plan."""
    settings(False); close(); put(SCENES, PLAN_TOML)


def open_plan():
    cli("open", PLAN, ok=(0, 4)); wait_for((DEMO_CLASS, "omacalc")); time.sleep(1.0)


def scene_desktops():
    baseline(); focus_ws(SPARE); to(SCREEN[0] // 2, SCREEN[1] - 80)
    with Recorder() as r:
        time.sleep(0.8); r.caption("The Desktops page: one card per desktop")
        settings(True); tap(*DESKTOPS_TAB); time.sleep(1.2)
        r.caption("Desktop 8 has a plan: 2 columns"); time.sleep(0.6)
        tap(*DESK8_CARD); time.sleep(1.4)
        if EDITOR_SCROLL: m.wheel(-EDITOR_SCROLL); time.sleep(0.6)
        r.caption("The preview shows each app in its zone"); time.sleep(2.2)
        r.caption("Open all starts the apps"); tap(*OPEN_ALL); time.sleep(2.5)
        settings(False)
        r.caption("Each app lands in its zone"); wait_for((DEMO_CLASS, "omacalc")); time.sleep(2.5)
        r.finish("desktops")


def scene_snap():
    baseline(); focus_ws(SPARE); open_plan(); close("omacalc"); to(SCREEN[0] // 2, SCREEN[1] - 80)
    with Recorder() as r:
        time.sleep(0.8); r.caption("Open a planned app, from anywhere"); time.sleep(1.0)
        launch("omacalc"); time.sleep(0.8)
        r.caption("It goes straight to its zone"); wait_for(("omacalc",)); time.sleep(2.5)
        r.finish("snap")


def scene_update():
    baseline(); focus_ws(SPARE); open_plan()
    calc = window("omacalc")
    if not calc: raise RuntimeError("Omacalc is not on desktop 8 after opening the plan")
    (x0, y0), (w, h) = calc["at"], calc["size"]
    notif("dismissAll"); time.sleep(0.5)
    with Recorder() as r:
        time.sleep(0.8); r.caption("Drag a planned window to another zone"); time.sleep(0.6)
        to(x0 + OMACALC_GRAB[0], y0 + OMACALC_GRAB[1]); time.sleep(0.3)
        m.press(); time.sleep(0.25)
        m.move(round(DRAG_BY * scale), 0, steps=45, pause=0.015); time.sleep(0.3); m.release(); time.sleep(0.6)
        calc = window("omacalc") or calc
        if abs(calc["at"][0] - x0) < 50:
            print("  warning: the drag did not move Omacalc (calibrate OMACALC_GRAB); moving it by dispatch instead", flush=True)
            ev(f'hl.dispatch(hl.dsp.window.move({{ x = {x0 + DRAG_BY}, y = {y0}, relative = false, window = "address:{calc["address"]}" }}))')
            time.sleep(0.6); calc = window("omacalc") or calc
        strip = calc["at"][0] // 2            # the part of the terminal Omacalc does not cover
        if strip < 20: raise RuntimeError("Omacalc covers the terminal: make DRAG_BY smaller")
        seq0 = moves_seq()
        r.caption("Click another window: omaplace notices")
        notif("dismissAll"); dnd(False)
        try:
            with ToastWatch() as tw:
                tap(strip, calc["at"][1] + h // 2)
                end = time.time() + 5
                while time.time() < end and not (tw.most >= 1 and moves_seq() > seq0): time.sleep(0.15)
                if moves_seq() <= seq0 or tw.most < 1: raise RuntimeError("no Update plan notification after the zone move")
                r.look(NOTIF, NOTIF_ZOOM); r.caption("One notification: Update plan?"); time.sleep(1.6)
                clean = tw.most == 1
                to(*NOTIF_BUTTON); time.sleep(0.4)
            if not clean: raise RuntimeError("another notification showed; nothing pressed, GIF not written: run the update scene again")
            click()
        finally:
            dnd(True)
        time.sleep(0.3); r.look(FULL)
        r.caption("Pressed: the two windows swap zones")
        end = time.time() + 4
        while time.time() < end and zones().get("omacalc") != 1: time.sleep(0.2)
        if zones().get("omacalc") != 1:
            print("  warning: the click missed the button (calibrate NOTIF_BUTTON); pressing it through the shell", flush=True)
            notif("invokeAction", "1"); time.sleep(2.0)
        time.sleep(2.5)
        r.finish("update")


def scene_scenes():
    baseline(); put(SCENES, ""); rescan(); focus_ws(SPARE)   # no plan here: the windows stay where they are put
    launch(DEMO_TERM, "float; size 760 520; move 60 110"); time.sleep(1.5)
    launch("omacalc", "float; size 420 560; move 980 300"); wait_for((DEMO_CLASS, "omacalc")); time.sleep(1.0)
    to(SCREEN[0] // 2, SCREEN[1] - 40)
    with Recorder() as r:
        time.sleep(0.8); r.caption("Arrange a desktop the way you like"); time.sleep(1.4)
        r.caption("omaplace save demo"); cli("save", "demo"); time.sleep(1.4)
        r.caption("Close everything"); close(); time.sleep(1.0)
        r.caption("omaplace open demo: it all comes back"); cli("open", "demo", ok=(0, 4))
        wait_for((DEMO_CLASS, "omacalc")); time.sleep(2.5)
        r.finish("scenes")


SCENES_BY_NAME = {"desktops": scene_desktops, "snap": scene_snap, "update": scene_update, "scenes": scene_scenes}
NEEDS = {"desktops": ("DESKTOPS_TAB", "DESK8_CARD", "OPEN_ALL"), "update": ("NOTIF_BUTTON",)}   # (0, 0) means not calibrated


def calibrate():
    """Screenshots, no recording: the Desktops page, then desktop 8's editor, then a made-up notification with a button."""
    baseline(); focus_ws(SPARE); settings(True); time.sleep(1.0)
    subprocess.run(["grim", "-s", "1", os.path.join(OUT, "calibrate.png")])
    if DESK8_CARD != (0, 0):
        tap(*DESK8_CARD); time.sleep(1.2)
        if EDITOR_SCROLL: m.wheel(-EDITOR_SCROLL); time.sleep(0.6)
        subprocess.run(["grim", "-s", "1", os.path.join(OUT, "calibrate-card.png")])
    settings(False)
    open_plan()
    subprocess.run(["grim", "-s", "1", os.path.join(OUT, "calibrate-windows.png")])
    notif("dismissAll"); dnd(False)
    try:
        sh("omarchy-notification-send", "-g", "󰕰", "omaplace", f"omacalc moved. Update the plan {PLAN}?", "--action", "Update plan", "true")
        time.sleep(1.5); subprocess.run(["grim", "-s", "1", os.path.join(OUT, "calibrate-notify.png")])
    finally:
        dnd(True); notif("dismissAll")
    print("wrote calibrate.png" + (", calibrate-card.png" if DESK8_CARD != (0, 0) else " (set DESK8_CARD and run again for the editor)")
          + ", calibrate-windows.png, calibrate-notify.png in branding/demo/", flush=True)


def preflight():
    for tool in ("grim", "ffmpeg", "kitty", "bat", "omacalc", "gio", "omarchy-shell", "omarchy-hyprland-workspace-layout-toggle"):
        if not shutil.which(tool): raise SystemExit(f"needs {tool}")
    mons = json.loads(sh("hyprctl", "monitors", "-j") or "[]")
    if len(mons) != 1: raise SystemExit("needs exactly one monitor (desktop 8 must be workspace 8, the coordinates are for one screen)")
    mon = mons[0]
    w, h = (mon["height"], mon["width"]) if mon["transform"] % 2 else (mon["width"], mon["height"])
    size = (round(w / mon["scale"]), round(h / mon["scale"]))
    if size != SCREEN or (mon["x"], mon["y"]) != (0, 0):
        raise SystemExit(f"the monitor is {size[0]}x{size[1]} at {mon['x']},{mon['y']}; SCREEN says {SCREEN[0]}x{SCREEN[1]} at 0,0")
    cl = clients()
    if any(c["workspace"]["id"] == SPARE for c in cl): raise SystemExit(f"workspace {SPARE} is not empty; not touching it")
    if any(c["class"] in (DEMO_CLASS, "omacalc") for c in cl): raise SystemExit("close Omacalc first (the demo closes its windows)")
    if os.path.exists(ENTRY): raise SystemExit(f"{ENTRY} exists; not writing over it")
    cli("status")   # exits 5 when the service is not running
    return mon["scale"]


def main():
    global m, scale, settings_open
    args = sys.argv[1:]
    cal = args == ["--calibrate"]
    wanted = [] if cal else (args or list(SCENES_BY_NAME))
    bad = [a for a in wanted if a not in SCENES_BY_NAME]
    if bad: raise SystemExit(f"unknown scene {bad[0]}; scenes: {', '.join(SCENES_BY_NAME)}, or --calibrate")
    todo = [c for n in wanted for c in NEEDS.get(n, ()) if globals()[c] == (0, 0)]
    if todo: raise SystemExit(f"calibrate first (--calibrate), then set {', '.join(todo)} at the top of this file")
    scale = preflight()
    origin = json.loads(sh("hyprctl", "activeworkspace", "-j"))["id"]
    cursor = json.loads(sh("hyprctl", "cursorpos", "-j") or '{"x":800,"y":500}')
    files = {p: (open(p, "rb").read() if os.path.exists(p) else None)
             for p in (SCENES, SCENES + ".bak", CONFIG, CONFIG + ".bak")}
    mode_file = os.path.join(HOME, ".local", "state", "omarchy", "workspace-layouts", f"{SPARE}.lua")
    had_mode_file, mode0, dnd0 = os.path.exists(mode_file), ws_mode(), notif("isDnd")
    os.makedirs(OUT, exist_ok=True)
    print("Starting in 10 s. Hands off the keyboard, mouse and screen.", flush=True); time.sleep(10)
    try:
        dnd(True)
        put(ENTRY, ENTRY_TEXT)
        put(CONFIG, CONFIG_TOML); ev("return _G.omaplace and _G.omaplace.reload_config()")
        put(SCENES, PLAN_TOML); time.sleep(1.0); rescan()
        with Mouse() as mouse:
            m = mouse; time.sleep(0.5)
            if cal: calibrate()
            for name in wanted:
                print("scene", name, flush=True)
                try: SCENES_BY_NAME[name]()
                finally: settings(False); close()
    finally:
        steps = []
        def step(what, fn):
            try: fn()
            except Exception as e: steps.append(f"{what} FAILED ({e})")
        if settings_open: sh("omarchy-shell", "shell", "toggle", PLUGIN); settings_open = False; time.sleep(1.0)
        step("windows", close)
        for path, data in files.items():
            step(path, (lambda p=path, d=data: trash(p) if d is None else put(p, d)))
        step("entry", lambda: trash(ENTRY))
        step("reload", lambda: ev("return _G.omaplace and _G.omaplace.reload_config()"))
        step("plans", rescan)
        def mode():
            focus_ws(SPARE)
            nxt = {"dwindle": "scrolling", "scrolling": "floating", "floating": "dwindle"}
            for _ in range(2):
                cur = ws_mode()
                if cur == mode0 or cur not in nxt: break
                sh("omarchy-hyprland-workspace-layout-toggle", "next" if nxt[cur] == mode0 else "back"); time.sleep(0.8)
            if not had_mode_file: trash(mode_file)
        step("mode", mode)
        step("workspace", lambda: focus_ws(origin))
        step("dnd", lambda: dnd(dnd0 == "on"))
        step("pointer", lambda: to(cursor["x"], cursor["y"]))
        try: plans_clean = PLAN not in open(PLANS).read()
        except OSError: plans_clean = True
        same = all((open(p, "rb").read() if os.path.exists(p) else None) == d for p, d in files.items())
        print("restored: files", "exact" if same else "DIFFERENT", "| plans.lua", "clean" if plans_clean else f"STILL NAMES {PLAN}",
              "| desktop 8", ws_mode(), "(was", mode0 + ")", "| dnd", notif("isDnd"), "(was", dnd0 + ")", flush=True)
        for s in steps: print("  " + s, flush=True)


if __name__ == "__main__":
    main()
