#!/usr/bin/env python3
"""Run the real omaplace QML service against a synthetic Hyprland session.

Usage: python3 tests/login_startup.test.py [--source /path/to/omaplace]
Requires Quickshell with Hyprland support. The real desktop is never contacted.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time

FAKE_HYPRCTL = r'''#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
rt = Path(os.environ["XDG_RUNTIME_DIR"]) / "omaplace"
if sys.argv[1] == "workspacerules":
    print("[]")
    raise SystemExit
if sys.argv[1] != "eval":
    raise SystemExit(1)
expr = sys.argv[2]
reply = re.search(r'io.open\("([^"]+)", "w"\)', expr)
if not reply:
    raise SystemExit
ans = "ok"
if '.open_file(' in expr:
    plan = Path(re.search(r'\.open_file\("([^"]+)"', expr)[1]).read_text()
    run = re.search(r'run\s*=\s*"([^"]+)"', plan)[1]
    kind = "restore" if 'kind = "session"' in plan else "desktop"
    busy = (rt / "hold").exists()
    with (rt / "calls").open("a") as f:
        print(kind, "busy" if busy else "started", file=f)
    if busy:
        ans = "busy"
    else:
        state = {"run": run, "state": "running" if kind == "restore" else "done", "items": [{"state": "moved"}]}
        (rt / "status-next").write_text(json.dumps(state))
        (rt / "status-next").replace(rt / "status.json")
Path(reply[1]).write_text("omaplace:" + ans)
'''

def wait_for(predicate, seconds, label):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.025)
    raise AssertionError(f"Timed out waiting for {label}")

def respond(server):
    while True:
        try:
            conn, _ = server.accept()
        except OSError:
            return
        with conn:
            request = conn.recv(4096)
            conn.sendall(b"[]" if b"monitors" in request or b"workspaces" in request else b"{}")

def exercise(source, simulate_reload):
    with tempfile.TemporaryDirectory(prefix="oml-") as directory:
        base = Path(directory)
        start = int(time.time())
        signature = f"f00ba4_{start}_1"
        previous = f"f00ba4_{start - 600}_1"
        runtime = base / "run"
        rt = runtime / "omaplace"
        sockdir = runtime / "hypr" / signature
        sockdir.mkdir(parents=True)
        rt.mkdir()
        runtime.chmod(0o700)
        home = base / "home"
        cfg = home / ".config/omaplace"
        state = home / ".local/state/omaplace"
        cfg.mkdir(parents=True)
        state.mkdir(parents=True)
        (cfg / "config.toml").write_text('restore_at_login = "auto"\n')
        (cfg / "scenes.toml").write_text(
            '[scene.example]\nplan = true\nlayout = "full"\nopen_at_login = true\nhome_slot = 1\n'
            '[scene.example.window.1]\nclass = "org.example.Editor"\nzone = 1\nrect = "0 0 1 1"\n'
        )
        (state / "sessions.json").write_text(json.dumps([{"instance": previous, "saved_at": start - 60}]))
        (state / f"session-{previous}.json").write_text(json.dumps({
            "monitors": [{"fp": {"identity": "test"}}],
            "windows": [{"class": "org.example.Editor", "slot": 1, "monitor": 0, "order": 1, "rect": [0, 0, 1, 1]}],
        }))
        shim = base / "bin"
        shim.mkdir()
        (shim / "hyprctl").write_text(FAKE_HYPRCTL)
        (shim / "hyprctl").chmod(0o755)
        (shim / "omarchy-notification-send").write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$XDG_RUNTIME_DIR/notices"\n')
        (shim / "omarchy-notification-send").chmod(0o755)
        (base / "Service.qml").symlink_to(source / "Service.qml")
        (base / "js").symlink_to(source / "js")
        (base / "shell.qml").write_text("import Quickshell\nShellRoot { Service {} }\n")
        env = {
            "PATH": f"{shim}:/usr/bin:/bin", "HOME": str(home), "XDG_RUNTIME_DIR": str(runtime),
            "QT_QPA_PLATFORM": "offscreen", "HYPRLAND_INSTANCE_SIGNATURE": signature, "LC_ALL": "C.UTF-8",
        }
        opens = rt / "calls"
        status = rt / "status.json"
        def calls():
            return opens.read_text().splitlines() if opens.exists() else []
        def set_status(value):
            (rt / "status-test").write_text(json.dumps(value))
            (rt / "status-test").replace(status)

        with socket.socket(socket.AF_UNIX) as ipc, socket.socket(socket.AF_UNIX) as events:
            ipc.bind(str(sockdir / ".socket.sock"))
            ipc.listen()
            threading.Thread(target=respond, args=(ipc,), daemon=True).start()
            events.bind(str(sockdir / ".socket2.sock"))
            events.listen()
            events.settimeout(0.1)
            with (base / "quickshell.log").open("w+") as log:
                proc = subprocess.Popen([shutil.which("quickshell"), "--no-color", "-p", str(base / "shell.qml")],
                                        env=env, stdout=log, stderr=subprocess.STDOUT)
                peer = None
                try:
                    wait_for(lambda: (rt / "workspace-plan.lua").exists(), 2, "initial workspace rules")
                    time.sleep(2)
                    before_reload = calls()
                    if simulate_reload:
                        if status.exists():
                            (rt / "hold").touch()
                            set_status({**json.loads(status.read_text()), "state": "interrupted"})
                        try:
                            peer, _ = events.accept()
                            peer.sendall(b"configreloaded>>\n")
                        except TimeoutError:
                            assert before_reload, "service did not subscribe to config reloads"
                    (rt / "login.json").write_text(json.dumps({"instance": signature, "plans": ["example"]}))
                    if simulate_reload:
                        time.sleep(1.4)
                        assert calls()[:2] != ["restore started", "desktop busy"], (
                            "reproduced: restore interrupted by reload, then login plan rejected as busy"
                        )
                        assert calls() == [], f"startup ignored the quiet period after reload: {calls()}"
                    wait_for(lambda: status.exists(), 4, "session restore to start")
                    assert calls() == ["restore started"], calls()
                    assert not (runtime / "notices").exists(), "a run was reported complete early"
                    set_status({**json.loads(status.read_text()), "state": "done"})
                    wait_for(lambda: calls() == ["restore started", "desktop started"], 3, "queued desktop plan")
                    wait_for(lambda: (rt / ("login-done-" + signature)).exists(), 3, "completed desktop plan")
                    assert (rt / ("restore-done-" + signature)).exists()
                    print(f"{'reload during startup' if simulate_reload else 'quiet startup'}: restored once, then opened the desktop once")
                except BaseException:
                    log.seek(0)
                    print(log.read(), end="")
                    print(calls(), (runtime / "notices").read_text() if (runtime / "notices").exists() else "")
                    raise
                finally:
                    if peer:
                        peer.close()
                    if proc.poll() is None:
                        proc.terminate()
                    proc.wait(timeout=3)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    exercise(args.source.resolve(), simulate_reload=True)
    exercise(args.source.resolve(), simulate_reload=False)
