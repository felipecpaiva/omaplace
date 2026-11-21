#!/usr/bin/env python3
"""Records the omaplace feature GIFs from the REAL plugin on a spare, empty workspace 8 (never a virtual monitor).
Mouse only (uinput moves and clicks, never keys), hyprctl eval for pointer warps and window dispatch, plus the omaplace
CLI and settings file edits. omakit (the sibling ../omakit checkout, or OMAKIT_PATH) records and builds each scene as a
captioned GIF and MP4 in branding/demo/, and its Stage guards workspace 8 and puts everything back.
Scenes: desktops, snap, update, scenes. --calibrate takes screenshots for the coordinates below and records nothing.
Privacy: Do Not Disturb is on for the whole run. Your notifications are never dismissed. The update scene turns Do Not
Disturb off only once no card is on screen (it waits up to 10 s), from the click that triggers the "Update plan"
notification until the pointer is on its button; it zooms onto the notification area for that part and writes no GIF
if any other card showed meanwhile. Demo windows show only this repository's README (a terminal with class
omaplace-demo, so your own terminals are never planned) and Omacalc.
Restore (also on an error): omakit's Stage puts back scenes.toml, config.toml, their .bak files, the temporary launcher
entry, workspace 8's layout mode and Omarchy's layout file for it, Do Not Disturb, the pointer and your workspace. Then
this script reloads omaplace's Lua settings and rebuilds plans.lua, and checks the demo plan is gone from it.
Needs one monitor, grim, ffmpeg, kitty, bat, omacalc, gio, the plugin enabled with its Lua line loaded.
Do not touch the keyboard or mouse while it runs (about 2 minutes).
Usage: python3 branding/tools/demo.py [scene ...]      (no argument: all scenes)
       python3 branding/tools/demo.py --calibrate      (screenshots to branding/demo/calibrate*.png, gitignored)"""
import json, os, re, shutil, sys, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.environ.get("OMAKIT_PATH") or os.path.join(os.path.dirname(ROOT), "omakit"))
from omakit.hypr import Hypr
from omakit.record import Recorder
from omakit.stage import Stage
from omakit.uinput import Mouse

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
CALIBRATED_FOR = (1600, 1000)  # the monitor's logical size these were read on; the run refuses another size
DESKTOPS_TAB = (0, 0)        # the "Desktops" page button in the settings window (clicked so the page is sure to be first)
DESK8_CARD = (0, 0)          # the desktop 8 tile on the Desktops page
EDITOR_SCROLL = 0            # wheel clicks down after picking the tile, if "Open all" is below the fold
OPEN_ALL = (0, 0)            # the "Open all" button of desktop 8's editor (after EDITOR_SCROLL)
OMACALC_GRAB = (60, 14)      # where to press on Omacalc to drag it, from its top-left corner (its title bar)
DRAG_BY = -600               # how far the drag moves Omacalc: its centre ends in the left zone, a strip of the terminal stays
NOTIF_ZOOM = 2               # the notification part shows the top right 1/NOTIF_ZOOM of the area, scaled up to the same size
NOTIF_BUTTON = (0, 0)        # the "Update plan" button on the notification card
TOAST_WAIT = 10              # seconds to wait for other notification cards to expire before the update scene

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

h = Hypr()
m = None
FULL = NOTIF = None          # (x, y, w, h) recording regions, set from the live monitor in main()
settings_open = False


def to(x, y): h.move_cursor(x, y); time.sleep(0.12)
def tap(x, y): to(x, y); time.sleep(0.3); m.click()
def focus_ws(ws): h.focus_ws(ws); time.sleep(0.8)
def launch(cmd, rule=""): h.ev(f'hl.exec_cmd("{("[" + rule + "] ") if rule else ""}{cmd}")')
def notif(*a): return h.sh("omarchy-shell", "notifications", *a)
def toasts():
    try: return int(notif("count") or 0)
    except ValueError: return 0
def dnd(on): notif("setDnd", "on" if on else "off")
def reload_lua(): h.ev("return _G.omaplace and _G.omaplace.reload_config()")


def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".demo-tmp"
    with open(tmp, "w") as f: f.write(text)
    os.replace(tmp, path)


def cli(*a, ok=(0,)):
    """bin/omaplace with its own notifications off (the service still sends run summaries, silenced by Do Not Disturb)."""
    p = h.run(["env", "OMAPLACE_NOTIFY=0", BIN, *a])
    if p.returncode not in ok:
        raise RuntimeError(f"omaplace {' '.join(a)} exited {p.returncode}: {(p.stdout + p.stderr).strip()}")
    return p.stdout.strip()


def settings(want):
    """The settings window keeps the keyboard and refuses focus changes, so the script always knows whether it is open."""
    global settings_open
    if settings_open != want:
        h.sh("omarchy-shell", "shell", "toggle", PLUGIN); settings_open = want; time.sleep(1.5)


def rescan():
    """Opening the settings window reads scenes.toml again and rebuilds plans.lua (a watch can miss a new file, live-M5)."""
    settings(True); time.sleep(0.5); settings(False)


def ours(c): return c["workspace"]["id"] == SPARE or c["class"] in (DEMO_CLASS, "omacalc")


def wait_for(classes, seconds=10.0):
    end = time.time() + seconds
    while time.time() < end:
        if set(classes) <= {c["class"] for c in h.clients() if c["workspace"]["id"] == SPARE}: return True
        time.sleep(0.25)
    print(f"  warning: {sorted(classes)} not all on desktop {SPARE} after {seconds:.0f} s", flush=True)
    return False


def close(cls=None):
    """Close the demo windows (preflight made sure every window of these classes is ours, Stage that 8 was empty)."""
    mine = lambda: [c for c in h.clients() if ours(c) and (cls is None or c["class"] == cls)]
    for c in mine(): h.close(c["address"])
    end = time.time() + 5
    while time.time() < end and mine(): time.sleep(0.2)
    time.sleep(0.5)


def window(cls): return next((c for c in h.clients() if c["class"] == cls and c["workspace"]["id"] == SPARE), None)


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


def quiet_screen():
    """Wait for every notification card on screen to expire by itself (never dismiss someone's notification)."""
    end = time.time() + TOAST_WAIT
    while toasts() and time.time() < end: time.sleep(0.25)
    if toasts(): raise RuntimeError(f"a notification card is still on screen after {TOAST_WAIT} s; run the update scene again")


class ToastWatch:
    """Counts the notification cards on screen while Do Not Disturb is off; the most seen decides if the GIF is clean."""
    def __enter__(self):
        self.most, self.stop = 0, threading.Event()
        def poll():
            while not self.stop.is_set(): self.most = max(self.most, toasts()); time.sleep(0.15)
        self.th = threading.Thread(target=poll); self.th.start()
        return self

    def __exit__(self, *exc): self.stop.set(); self.th.join()


def record(): return Recorder(FULL, hypr=h)
def finish(r, name): r.finish(name, out_dir=OUT, y="36")   # captions at the top, as omadials


def baseline():
    """Desktop 8 empty, the settings window closed, scenes.toml holding only the demo plan."""
    settings(False); close(); put(SCENES, PLAN_TOML)


def open_plan():
    cli("open", PLAN, ok=(0, 4)); wait_for((DEMO_CLASS, "omacalc")); time.sleep(1.0)


def low_middle(): to(FULL[2] // 2, FULL[1] + FULL[3] - 60)


def scene_desktops():
    baseline(); focus_ws(SPARE); low_middle()
    with record() as r:
        time.sleep(0.8); r.caption("The Desktops page: one card per desktop")
        settings(True); tap(*DESKTOPS_TAB); time.sleep(1.2)
        r.caption("Desktop 8 has a plan: 2 columns"); time.sleep(0.6)
        tap(*DESK8_CARD); time.sleep(1.4)
        if EDITOR_SCROLL: m.wheel(-EDITOR_SCROLL); time.sleep(0.6)
        r.caption("The preview shows each app in its zone"); time.sleep(2.2)
        r.caption("Open all starts the apps"); tap(*OPEN_ALL); time.sleep(2.5)
        settings(False)
        r.caption("Each app lands in its zone")
        if not wait_for((DEMO_CLASS, "omacalc")): raise RuntimeError("Open all placed nothing: is the plugin's Lua line loaded? (bin/omaplace save x exits 6 if not)")
        time.sleep(2.5)
        finish(r, "desktops")


def scene_snap():
    baseline(); focus_ws(SPARE); open_plan(); close("omacalc"); low_middle()
    with record() as r:
        time.sleep(0.8); r.caption("Open a planned app, from anywhere"); time.sleep(1.0)
        launch("omacalc"); time.sleep(0.8)
        r.caption("It goes straight to its zone"); wait_for(("omacalc",)); time.sleep(2.5)
        finish(r, "snap")


def scene_update():
    baseline(); focus_ws(SPARE); open_plan()
    calc = window("omacalc")
    if not calc: raise RuntimeError("Omacalc is not on desktop 8 after opening the plan")
    (x0, y0), (w, hh) = calc["at"], calc["size"]
    with record() as r:
        time.sleep(0.8); r.caption("Drag a planned window to another zone"); time.sleep(0.6)
        to(x0 + OMACALC_GRAB[0], y0 + OMACALC_GRAB[1]); time.sleep(0.3)
        m.press(); time.sleep(0.25)
        m.move(h.physical(DRAG_BY), 0, steps=45, pause=0.015); time.sleep(0.3); m.release(); time.sleep(0.6)
        calc = window("omacalc") or calc
        if abs(calc["at"][0] - x0) < 50:
            print("  warning: the drag did not move Omacalc (calibrate OMACALC_GRAB); moving it by dispatch instead", flush=True)
            h.ev(f'hl.dispatch(hl.dsp.window.move({{ x = {x0 + DRAG_BY}, y = {y0}, relative = false, window = "address:{calc["address"]}" }}))')
            time.sleep(0.6); calc = window("omacalc") or calc
        strip = calc["at"][0] // 2            # the part of the terminal Omacalc does not cover
        if strip < 20: raise RuntimeError("Omacalc covers the terminal: make DRAG_BY smaller")
        seq0 = moves_seq()
        r.caption("Click another window: omaplace notices")
        quiet_screen(); dnd(False)
        try:
            with ToastWatch() as tw:
                tap(strip, calc["at"][1] + hh // 2)
                end = time.time() + 5
                while time.time() < end and not (tw.most >= 1 and moves_seq() > seq0): time.sleep(0.15)
                if moves_seq() <= seq0 or tw.most < 1: raise RuntimeError("no Update plan notification after the zone move")
                r.look(NOTIF, NOTIF_ZOOM); r.caption("One notification: Update plan?"); time.sleep(1.6)
                to(*NOTIF_BUTTON); time.sleep(0.4)
                clean = tw.most == 1 and toasts() == 1   # read last, with the pointer already on the button
            if not clean: raise RuntimeError("another notification showed; nothing pressed, GIF not written: run the update scene again")
            m.click()
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
        finish(r, "update")


def scene_scenes():
    baseline(); put(SCENES, "schema = 1\n"); rescan(); focus_ws(SPARE)   # no plan here: the windows stay where they are put
    launch(DEMO_TERM, "float; size 760 520; move 60 110"); time.sleep(1.5)
    launch("omacalc", "float; size 420 560; move 980 300"); wait_for((DEMO_CLASS, "omacalc")); time.sleep(1.0)
    low_middle()
    with record() as r:
        time.sleep(0.8); r.caption("Arrange a desktop the way you like"); time.sleep(1.4)
        r.caption("omaplace save demo"); cli("save", "demo"); time.sleep(1.4)
        r.caption("Close everything"); close(); time.sleep(1.0)
        r.caption("omaplace open demo: it all comes back"); cli("open", "demo", ok=(0, 4))
        wait_for((DEMO_CLASS, "omacalc")); time.sleep(2.5)
        finish(r, "scenes")


SCENES_BY_NAME = {"desktops": scene_desktops, "snap": scene_snap, "update": scene_update, "scenes": scene_scenes}
NEEDS = {"desktops": ("DESKTOPS_TAB", "DESK8_CARD", "OPEN_ALL"), "update": ("NOTIF_BUTTON",)}   # (0, 0) means not calibrated


def grim(name): h.run(["grim", "-s", "1", os.path.join(OUT, name)])


def calibrate():
    """Screenshots, no recording: the Desktops page, desktop 8's editor, the plan opened, a made-up notification."""
    baseline(); focus_ws(SPARE); settings(True); time.sleep(1.0); grim("calibrate.png")
    if DESK8_CARD != (0, 0):
        tap(*DESK8_CARD); time.sleep(1.2)
        if EDITOR_SCROLL: m.wheel(-EDITOR_SCROLL); time.sleep(0.6)
        grim("calibrate-card.png")
    settings(False)
    open_plan(); grim("calibrate-windows.png")
    quiet_screen(); dnd(False)
    try:   # the made-up card expires by itself after 5 s; nothing is dismissed
        h.sh("omarchy-notification-send", "-t", "5000", "-g", "󰕰", "omaplace", f"omacalc moved. Update the plan {PLAN}?",
             "--action", "Update plan", "true")
        time.sleep(1.5); grim("calibrate-notify.png")
    finally:
        dnd(True)
    print("wrote calibrate.png" + (", calibrate-card.png" if DESK8_CARD != (0, 0) else " (set DESK8_CARD and run again for the editor)")
          + ", calibrate-windows.png, calibrate-notify.png in branding/demo/", flush=True)


def preflight():
    global FULL, NOTIF
    for tool in ("grim", "ffmpeg", "kitty", "bat", "omacalc", "gio", "omarchy-shell"):
        if not shutil.which(tool): raise SystemExit(f"needs {tool}")
    if len(h.json("monitors", default=[]) or []) != 1:
        raise SystemExit("needs exactly one monitor (desktop 8 must be workspace 8, the coordinates are for one screen)")
    mon = h.monitor()
    if (mon["width"], mon["height"]) != CALIBRATED_FOR or (mon["x"], mon["y"]) != (0, 0):
        raise SystemExit(f"the monitor is {mon['width']}x{mon['height']} at {mon['x']},{mon['y']}; the coordinates are for"
                         f" {CALIBRATED_FOR[0]}x{CALIBRATED_FOR[1]} at 0,0: calibrate again")
    bar = mon["reserved"][1]   # record below the bar; the height is a multiple of the zoom so both frame sizes match
    area_h = (mon["height"] - bar) // NOTIF_ZOOM * NOTIF_ZOOM
    if mon["width"] % NOTIF_ZOOM: raise SystemExit(f"the monitor width is not a multiple of NOTIF_ZOOM {NOTIF_ZOOM}")
    FULL = (0, bar, mon["width"], area_h)
    NOTIF = (mon["width"] - mon["width"] // NOTIF_ZOOM, bar, mon["width"] // NOTIF_ZOOM, area_h // NOTIF_ZOOM)
    if any(c["class"] in (DEMO_CLASS, "omacalc") for c in h.clients()): raise SystemExit("close Omacalc first (the demo closes its windows)")
    if os.path.exists(ENTRY): raise SystemExit(f"{ENTRY} exists; not writing over it")
    cli("status")   # exits 5 when the service is not running


def after():
    """omaplace's own restore, once Stage has put the files back: Lua's settings and plans.lua from the restored files."""
    notes = []
    for what, fn in (("lua reload", reload_lua), ("plans rebuild", rescan)):
        try: fn()
        except Exception as e: notes.append(f"{what} FAILED ({e})")
    try: clean = PLAN not in open(PLANS).read()
    except OSError: clean = True
    print("restored (omaplace): lua settings reloaded | plans.lua", "clean" if clean else f"STILL NAMES {PLAN}",
          *(["| " + n for n in notes]), flush=True)


def main():
    global m
    args = sys.argv[1:]
    cal = args == ["--calibrate"]
    wanted = [] if cal else (args or list(SCENES_BY_NAME))
    bad = [a for a in wanted if a not in SCENES_BY_NAME]
    if bad: raise SystemExit(f"unknown scene {bad[0]}; scenes: {', '.join(SCENES_BY_NAME)}, or --calibrate")
    todo = [c for n in wanted for c in NEEDS.get(n, ()) if globals()[c] == (0, 0)]
    if todo: raise SystemExit(f"calibrate first (--calibrate), then set {', '.join(todo)} at the top of this file")
    preflight()
    os.makedirs(OUT, exist_ok=True)
    files = [SCENES, SCENES + ".bak", CONFIG, CONFIG + ".bak", ENTRY]
    staged = False
    try:
        with Stage(spare=SPARE, restore_files=files, countdown=10, hypr=h):
            staged = True
            try:
                put(ENTRY, ENTRY_TEXT)
                put(CONFIG, CONFIG_TOML); reload_lua()
                put(SCENES, PLAN_TOML); time.sleep(1.0); rescan()
                with Mouse() as mouse:
                    m = mouse; time.sleep(0.5)
                    if cal: calibrate()
                    for name in wanted:
                        print("scene", name, flush=True)
                        try: SCENES_BY_NAME[name]()
                        finally: settings(False); close()
            finally:   # before Stage restores: the settings window must be shut, or it refuses the focus changes
                if settings_open: settings(False)
                close()
    finally:
        if staged: after()


if __name__ == "__main__":
    main()
