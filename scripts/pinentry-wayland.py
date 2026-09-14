#!/usr/bin/env python3
"""A GnuPG pinentry that opens a real dialog, styled like the rest of the desktop.

The two stock pinentries both fall short here:

  pinentry-gtk-2    A proper window, but GTK 2 is X11-only. It needs Xwayland,
                    and when that is not up the agent waits out its 30s and
                    every signed commit fails with "signing failed: Timeout"
                    and no prompt on screen. It is also unthemed GTK 2.

  pinentry-bemenu   Wayland-native and reliable, but it is a bemenu strip across
                    the top of the screen, which reads as part of the bar rather
                    than as a question being asked.

So this speaks the pinentry protocol itself and draws the prompt as a GTK 3
layer-shell surface: native Wayland, no X, the same in sway and Hyprland, and
dressed like foot, waybar and wofi (#242424 at 0.85, square corners, no
outlines, Tokyo Night blue accent).

gpg-agent starts one of these per operation and talks Assuan over stdin/stdout:
SET* commands describe the prompt, then GETPIN / CONFIRM / MESSAGE show it and
wait for an answer. Only the commands gpg-agent actually sends are implemented;
the rest are acknowledged and ignored, which is what the stock pinentries do.
"""

import os
import sys

# Error codes are gpg-error values with the pinentry source (5) in the top byte.
ERR_CANCELED = 83886179  # GPG_ERR_CANCELED
ERR_NOT_CONFIRMED = 83886194  # GPG_ERR_NOT_CONFIRMED
ERR_TIMEOUT = 83886142  # GPG_ERR_TIMEOUT

CSS = b"""
.panel {
    /* Same ground as foot, waybar and wofi. */
    background-color: rgba(36, 36, 36, 0.85);
    /* No outlines anywhere: foot, waybar and wofi draw none, and sway's
       borders are transparent. Fills do the separating instead. */
    border: none;
    border-radius: 0;
    padding: 20px 22px 16px 22px;
}
.panel label {
    font-family: "SF Pro Text", "Inter", "Cantarell", sans-serif;
    color: #cccccc;
    font-size: 13px;
}
.panel .heading {
    color: #f5f5f5;
    font-size: 15px;
    font-weight: 600;
}
.panel .detail {
    color: #999999;
    font-size: 12px;
}
.panel .error {
    color: #f7768e;
    font-size: 12px;
}
.panel .caps {
    color: #e0af68;
    font-size: 12px;
}
/* A flat fill, no box and no underline. */
.panel entry {
    font-family: "SF Pro Text", "Inter", "Cantarell", sans-serif;
    font-size: 16px;
    color: #f5f5f5;
    caret-color: #7aa2f7;
    background-color: rgba(255, 255, 255, 0.06);
    background-image: none;
    border: none;
    border-radius: 0;
    box-shadow: none;
    outline: none;
    padding: 8px 10px;
    min-height: 0;
}
.panel entry:focus {
    background-color: rgba(255, 255, 255, 0.09);
}
.panel entry selection {
    background-color: rgba(122, 162, 247, 0.35);
    color: #ffffff;
}
.panel button {
    font-family: "SF Pro Text", "Inter", "Cantarell", sans-serif;
    font-size: 13px;
    color: #cccccc;
    background-color: transparent;
    background-image: none;
    border: none;
    border-radius: 0;
    box-shadow: none;
    text-shadow: none;
    outline: none;
    padding: 5px 16px;
    min-height: 0;
}
.panel button label {
    color: inherit;
}
.panel button:hover {
    background-color: rgba(255, 255, 255, 0.06);
    color: #ffffff;
}
.panel button.default {
    color: #ffffff;
    background-color: rgba(122, 162, 247, 0.18);
}
.panel button.default:hover {
    background-color: rgba(122, 162, 247, 0.28);
}
.panel button:active {
    background-color: rgba(122, 162, 247, 0.35);
}
"""


def find_wayland():
    """Point GTK at the compositor even if the agent's environment lacks it.

    gpg-agent hands the pinentry whatever environment the agent itself was
    started with, so an agent first launched from a TTY or an SSH shell has no
    WAYLAND_DISPLAY. The socket is still there to be found.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    os.environ.setdefault("XDG_RUNTIME_DIR", runtime)
    name = os.environ.get("WAYLAND_DISPLAY")
    if name and os.path.exists(os.path.join(runtime, name)):
        return True
    try:
        sockets = sorted(
            f for f in os.listdir(runtime) if f.startswith("wayland-") and not f.endswith(".lock")
        )
    except OSError:
        return False
    if not sockets:
        return False
    os.environ["WAYLAND_DISPLAY"] = sockets[0]
    return True


def unescape(s):
    """Assuan percent-decoding: %0A is a newline, %25 a literal percent."""
    out = bytearray()
    i = 0
    while i < len(s):
        if s[i] == 0x25 and i + 2 < len(s):
            try:
                out.append(int(s[i + 1 : i + 3], 16))
                i += 3
                continue
            except ValueError:
                pass
        out.append(s[i])
        i += 1
    return out.decode("utf-8", "replace")


def escape(s):
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


class Pinentry:
    def __init__(self):
        self.out = sys.stdout.buffer
        self.gtk = None
        self.reset()

    def reset(self):
        self.title = ""
        self.desc = ""
        self.prompt = ""
        self.error = ""
        self.ok = ""
        self.cancel = ""
        self.notok = ""
        self.repeat = None
        self.repeat_error = ""
        self.timeout = 0

    def send(self, line):
        self.out.write(line.encode("utf-8") + b"\n")
        self.out.flush()

    def send_data(self, text):
        data = escape(text)
        # Assuan caps a line at 1000 bytes; long data goes out as several D lines.
        while data:
            chunk = data[:900]
            # Never split a %XX escape across two lines.
            cut = chunk.find("%", len(chunk) - 2)
            if len(data) > 900 and cut != -1:
                chunk = chunk[:cut]
            self.send("D " + chunk)
            data = data[len(chunk) :]
        self.send("OK")

    def run(self):
        self.send("OK Pleased to meet you")
        for raw in sys.stdin.buffer:
            raw = raw.rstrip(b"\r\n")
            if not raw or raw.startswith(b"#"):
                continue
            cmd, _, arg = raw.partition(b" ")
            cmd = cmd.decode("ascii", "replace").upper()
            text = unescape(arg)
            if not self.dispatch(cmd, text):
                return

    def dispatch(self, cmd, text):
        if cmd in ("BYE", "END"):
            self.send("OK closing connection")
            return False
        if cmd == "RESET":
            self.reset()
        elif cmd == "SETTITLE":
            self.title = text
        elif cmd == "SETDESC":
            self.desc = text
        elif cmd == "SETPROMPT":
            self.prompt = text
        elif cmd == "SETERROR":
            self.error = text
        elif cmd == "SETOK":
            self.ok = text
        elif cmd == "SETCANCEL":
            self.cancel = text
        elif cmd == "SETNOTOK":
            self.notok = text
        elif cmd == "SETREPEAT":
            self.repeat = text or "Repeat:"
        elif cmd == "SETREPEATERROR":
            self.repeat_error = text
        elif cmd == "SETTIMEOUT":
            try:
                self.timeout = int(text)
            except ValueError:
                pass
        elif cmd == "GETINFO":
            info = {
                "flavor": "wayland",
                "version": "1.0",
                "pid": str(os.getpid()),
                "ttyinfo": "- - -",
            }.get(text.strip())
            if info is None:
                self.send("ERR 83886360 Parameter not found")
                return True
            self.send("D " + info)
        elif cmd == "GETPIN":
            self.getpin()
            return True
        elif cmd == "CONFIRM":
            self.confirm(one_button=text.strip() == "--one-button")
            return True
        elif cmd == "MESSAGE":
            self.confirm(one_button=True)
            return True
        # OPTION, SETKEYINFO, SETQUALITYBAR, SETGENPIN and the like need no
        # handling: acknowledging them is enough for the agent to carry on.
        self.send("OK")
        return True

    # Dialogs

    def load_gtk(self):
        if self.gtk:
            return self.gtk
        import gi

        # Pin Gdk too, or gi picks up Gdk 4.0 and GtkLayerShell refuses to load.
        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        gi.require_version("GtkLayerShell", "0.1")
        from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )
        self.gtk = (Gdk, GLib, Gtk, GtkLayerShell)
        return self.gtk

    def dialog(self, entries, buttons):
        """Show the prompt and block until it is answered.

        entries: list of prompt strings, one password field each.
        buttons: list of (label, result) from left to right; the last is default.
        Returns (result, [field texts]).
        """
        Gdk, GLib, Gtk, GtkLayerShell = self.load_gtk()
        state = {"result": "cancel"}

        window = Gtk.Window()
        window.set_title(self.title or "Passphrase")
        visual = window.get_screen().get_rgba_visual()
        if visual:
            window.set_visual(visual)
        window.set_app_paintable(True)

        def clear(_w, cr):
            # Transparent everywhere the panel does not paint, so the panel's
            # own translucent ground is all that shows.
            cr.save()
            cr.set_operator(0)  # cairo.OPERATOR_CLEAR
            cr.paint()
            cr.restore()
            return False

        window.connect("draw", clear)

        if GtkLayerShell.is_supported():
            GtkLayerShell.init_for_window(window)
            # OVERLAY so it lands above a fullscreen window as well; no anchors
            # centres it. The namespace lets Hyprland give it the blur the bar
            # and launcher get.
            GtkLayerShell.set_namespace(window, "pinentry")
            GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_exclusive_zone(window, -1)
            GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        else:
            window.set_position(Gtk.WindowPosition.CENTER)
            window.set_keep_above(True)
            window.set_decorated(False)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        panel.get_style_context().add_class("panel")
        panel.set_size_request(440, -1)
        window.add(panel)

        def label(text, css, top=0):
            lab = Gtk.Label(label=text, xalign=0)
            lab.set_line_wrap(True)
            lab.set_max_width_chars(52)
            lab.get_style_context().add_class(css)
            lab.set_margin_top(top)
            panel.pack_start(lab, False, False, 0)
            return lab

        # gpg-agent puts the question on the first line of the description and
        # the key details after it, so the first line doubles as the heading.
        lines = self.desc.strip("\n").split("\n") if self.desc else []
        heading = self.title or (lines.pop(0).rstrip(":") if lines else "Passphrase required")
        label(heading, "heading")
        if lines:
            label("\n".join(l.strip() for l in lines if l.strip()), "detail", top=2)

        error = label(self.error, "error", top=6)
        error.set_no_show_all(True)
        if self.error:
            error.show()

        fields = []
        for prompt in entries:
            if prompt:
                label(prompt.rstrip(":"), "body", top=8)
            entry = Gtk.Entry()
            entry.set_visibility(False)
            entry.set_invisible_char("•")
            entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
            entry.set_margin_top(2 if prompt else 10)
            panel.pack_start(entry, False, False, 0)
            fields.append(entry)

        caps = label("Caps Lock is on", "caps", top=4)
        caps.set_no_show_all(True)
        keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())

        def update_caps(*_):
            caps.set_visible(bool(fields) and keymap.get_caps_lock_state())

        keymap.connect("state-changed", update_caps)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        row.set_margin_top(14)
        panel.pack_start(row, False, False, 0)

        def finish(result):
            if result == "ok" and len(fields) == 2 and fields[0].get_text() != fields[1].get_text():
                error.set_text(self.repeat_error or "Passphrases do not match")
                error.show()
                fields[1].set_text("")
                fields[1].grab_focus()
                return
            state["result"] = result
            state["texts"] = [f.get_text() for f in fields]
            for f in fields:
                f.set_text("")
            Gtk.main_quit()

        default = None
        for text, result in buttons:
            button = Gtk.Button.new_with_mnemonic(text)
            button.set_can_focus(False)
            button.connect("clicked", lambda _b, r=result: finish(r))
            row.pack_start(button, False, False, 0)
            default = button
        default.get_style_context().add_class("default")

        for i, entry in enumerate(fields):
            if i + 1 < len(fields):
                entry.connect("activate", lambda _e, n=fields[i + 1]: n.grab_focus())
            else:
                entry.connect("activate", lambda _e: finish("ok"))

        def on_key(_w, event):
            if event.keyval == Gdk.KEY_Escape:
                finish("cancel")
                return True
            if not fields and event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                finish(buttons[-1][1])
                return True
            return False

        window.connect("key-press-event", on_key)
        window.connect("delete-event", lambda *_: finish("cancel") or True)

        sources = []
        if self.timeout > 0:
            # Returns True so the source stays alive until removed below;
            # removing one GLib already dropped logs a critical.
            sources.append(
                GLib.timeout_add_seconds(self.timeout, lambda: finish("timeout") or True)
            )
        # If gpg-agent goes away (the git command was interrupted, say), take
        # the dialog down with it rather than leaving an orphan on screen.
        sources.append(
            GLib.io_add_watch(
                sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_ERR, lambda *_: os._exit(1)
            )
        )

        window.show_all()
        update_caps()
        if fields:
            fields[0].grab_focus()
        Gtk.main()

        for source in sources:
            GLib.source_remove(source)
        window.destroy()
        # Let the compositor see the unmap now, not whenever the agent next
        # asks for something.
        while Gtk.events_pending():
            Gtk.main_iteration()
        self.error = ""
        return state["result"], state.get("texts", [])

    def getpin(self):
        entries = [self.prompt or "Passphrase:"]
        if self.repeat:
            entries.append(self.repeat)
        result, texts = self.dialog(
            entries, [(self.cancel or "_Cancel", "cancel"), (self.ok or "_OK", "ok")]
        )
        if result == "timeout":
            self.send(f"ERR {ERR_TIMEOUT} Timeout <Pinentry>")
        elif result != "ok":
            self.send(f"ERR {ERR_CANCELED} Operation cancelled <Pinentry>")
        else:
            if self.repeat:
                self.send("S PIN_REPEATED")
            self.send_data(texts[0])

    def confirm(self, one_button):
        if one_button:
            buttons = [(self.ok or "_OK", "ok")]
        else:
            buttons = [(self.cancel or "_Cancel", "cancel")]
            if self.notok:
                buttons.append((self.notok, "notok"))
            buttons.append((self.ok or "_OK", "ok"))
        result, _ = self.dialog([], buttons)
        if result == "ok":
            self.send("OK")
        elif result == "notok":
            self.send(f"ERR {ERR_NOT_CONFIRMED} Not confirmed <Pinentry>")
        elif result == "timeout":
            self.send(f"ERR {ERR_TIMEOUT} Timeout <Pinentry>")
        else:
            self.send(f"ERR {ERR_CANCELED} Operation cancelled <Pinentry>")


def main():
    # No compositor to draw on (an SSH login, a bare TTY): hand the whole
    # conversation to the curses pinentry before saying a word.
    if not find_wayland():
        curses = "/usr/bin/pinentry-curses"
        os.execv(curses, [curses] + sys.argv[1:])
    os.environ.setdefault("GDK_BACKEND", "wayland")
    # gpg-agent starts pinentries as `pinentry --display :0`. Importing Gtk
    # feeds sys.argv to gtk_init, which takes that as the display to open, tries
    # to reach X display :0 over the Wayland backend and gets no screen at all.
    del sys.argv[1:]
    Pinentry().run()


if __name__ == "__main__":
    main()
