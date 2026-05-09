#!/usr/bin/env python3
"""Tikunchik - Fixes text typed in the wrong keyboard layout (Hebrew <-> English)"""

import sys
import time
import platform
import threading

import pyperclip
from pynput import keyboard
from pynput.keyboard import Key, Controller
import pystray
from PIL import Image, ImageDraw

from converter import convert_text, SpellChecker

SYSTEM = platform.system()
kb = Controller()
_processing_lock = threading.Lock()
_is_processing = False
spell_checker = SpellChecker()


def fix_text(switch_language=False):
    global _is_processing
    with _processing_lock:
        if _is_processing:
            return
        _is_processing = True

    try:
        _do_fix(switch_language)
    finally:
        with _processing_lock:
            _is_processing = False


def _do_fix(switch_language):
    try:
        saved = pyperclip.paste()
    except Exception:
        saved = ""

    ctrl = Key.cmd if SYSTEM == "Darwin" else Key.ctrl

    with kb.pressed(ctrl):
        kb.tap("a")
    time.sleep(0.08)

    with kb.pressed(ctrl):
        kb.tap("c")
    time.sleep(0.12)

    try:
        text = pyperclip.paste()
    except Exception:
        return

    if not text or text == saved:
        _restore(saved)
        return

    converted = convert_text(text, spell_checker)
    if converted == text:
        _restore(saved)
        return

    pyperclip.copy(converted)
    with kb.pressed(ctrl):
        kb.tap("v")
    time.sleep(0.1)

    _restore(saved)

    if switch_language:
        _switch_keyboard_layout()

    _notify(converted)


def _restore(saved):
    if saved:
        time.sleep(0.05)
        pyperclip.copy(saved)


def _switch_keyboard_layout():
    if SYSTEM == "Windows":
        with kb.pressed(Key.alt):
            kb.tap(Key.shift)
    elif SYSTEM == "Linux":
        import subprocess
        try:
            subprocess.run(["xdotool", "key", "super+space"], timeout=2,
                           capture_output=True)
        except FileNotFoundError:
            with kb.pressed(Key.cmd):
                kb.tap(Key.space)


def _notify(text):
    preview = text[:80] + ("…" if len(text) > 80 else "")
    title = "תיקונצ׳יק"

    if SYSTEM == "Windows":
        try:
            from plyer import notification
            notification.notify(title=title, message=f"תוקן: {preview}", timeout=3)
        except Exception:
            pass
    elif SYSTEM == "Linux":
        import subprocess
        try:
            subprocess.run(["notify-send", title, f"תוקן: {preview}"],
                           timeout=2, capture_output=True)
        except FileNotFoundError:
            pass


def _create_icon():
    img = Image.new("RGBA", (64, 64), (74, 120, 190, 255))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([10, 22, 54, 46], radius=4, fill=(220, 220, 230), outline=(60, 60, 80))
    for row in range(3):
        for col in range(5):
            x = 14 + col * 8
            y = 25 + row * 6
            draw.rectangle([x, y, x + 5, y + 3], fill=(60, 60, 80))
    draw.line([32, 14, 32, 52], fill=(200, 200, 50), width=3)
    draw.line([28, 18, 36, 18], fill=(200, 200, 50), width=2)
    return img


def main():
    hotkeys = keyboard.GlobalHotKeys({
        "<ctrl>+<shift>+k": lambda: threading.Thread(target=fix_text, daemon=True).start(),
        "<ctrl>+<alt>+<space>": lambda: threading.Thread(
            target=lambda: fix_text(switch_language=True), daemon=True
        ).start(),
    })
    hotkeys.start()

    def on_fix(icon, item):
        threading.Thread(target=fix_text, daemon=True).start()

    def on_fix_switch(icon, item):
        threading.Thread(target=lambda: fix_text(switch_language=True), daemon=True).start()

    def on_quit(icon, item):
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem("Fix Text  (Ctrl+Shift+K)", on_fix),
        pystray.MenuItem("Fix + Switch Language  (Ctrl+Alt+Space)", on_fix_switch),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit Tikunchik", on_quit),
    )

    tray = pystray.Icon("Tikunchik", _create_icon(), "Tikunchik", menu)
    tray.run()


if __name__ == "__main__":
    main()
