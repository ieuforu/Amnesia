#!/usr/bin/env python3
"""Build and restart just the local Amnesia preview when its source changes."""

import argparse
import fcntl
from pathlib import Path
import shutil
import signal
import subprocess
import time


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / ".build"
APP = BUILD / "Amnesia Preview.app"
STAGED = BUILD / "Amnesia Preview Next.app"
WATCH = ("Package.swift", "Sources", "Resources", "scripts/build-app.sh")


def snapshot():
    files = {}
    for relative in WATCH:
        path = ROOT / relative
        for file in path.rglob("*") if path.is_dir() else (path,):
            if file.name.startswith("."):
                continue
            try:
                if file.is_file():
                    stat = file.stat()
                    files[file] = (stat.st_mtime_ns, stat.st_size)
            except FileNotFoundError:
                pass  # Editors can replace files while we take a snapshot.
    return files


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def watch(demo, background):
    process = None
    compiler = None
    launched = False
    observed = snapshot()
    built = None
    changed_at = time.monotonic() - 1
    try:
        while True:
            current = snapshot()
            now = time.monotonic()
            if current != observed:
                observed = current
                changed_at = now
            if current != built and now - changed_at >= 0.25:
                built = current
                print("Building Amnesia preview…", flush=True)
                compiler = subprocess.Popen(["scripts/build-app.sh", "--preview"], cwd=ROOT)
                result = compiler.wait()
                compiler = None
                if result != 0:
                    message = "Build failed; the previous preview is still available." if launched else "Build failed."
                    print(message + " Watching for the next save.", flush=True)
                    continue
                if snapshot() != built:
                    continue  # Another edit arrived during compilation.
                stop(process)
                if APP.exists():
                    shutil.rmtree(APP)
                STAGED.rename(APP)
                flag = "--open-library-in-background" if launched or background else "--open-library"
                args = [str(APP / "Contents/MacOS/Amnesia"), flag]
                if demo:
                    args.append("--demo")
                process = subprocess.Popen(args, cwd=ROOT)
                launched = True
                print(f"Amnesia preview running (PID {process.pid}). Watching for saves.", flush=True)
            time.sleep(0.15)
    finally:
        stop(compiler)
        stop(process)


def interrupt(_signum, _frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo", action="store_true", help="Use sample sessions and collections.")
    parser.add_argument("--background", action="store_true", help="Open the first preview without taking focus, too.")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    with (BUILD / "amnesia-preview.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.exit(1, "Amnesia preview is already being watched.\n")
        signal.signal(signal.SIGTERM, interrupt)
        try:
            watch(args.demo, args.background)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
