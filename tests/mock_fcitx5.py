"""Stand-in for fcitx5 on a private test bus.

Owns org.fcitx.Fcitx5 and answers Controller1.CurrentInputMethod with the first
line of the file given as argv[1], so a test changes the "input method" by
rewriting that file. Needs PyGObject (Arch: python-gobject, Debian: python3-gi).
"""
import sys

from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.fcitx.Fcitx.Controller1">
    <method name="CurrentInputMethod"><arg type="s" direction="out"/></method>
  </interface>
</node>
"""
state_file = sys.argv[1]


def on_call(conn, sender, path, iface, method, params, invocation):
    with open(state_file) as f:
        invocation.return_value(GLib.Variant("(s)", (f.readline().strip(),)))


def on_bus(conn, name):
    iface = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
    conn.register_object("/controller", iface, on_call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.fcitx.Fcitx5",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
