#!/usr/bin/env python3

import math
import random
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import Gio, GLib, Gtk


def run_command(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


class SignalRadarWindow(Gtk.ApplicationWindow):
    SWEEP_SECONDS = 3.8
    TYPE_COLORS = {
        "wifi": (0.42, 0.80, 1.00),
        "bluetooth": (0.88, 0.62, 1.00),
        "universal": (0.58, 0.94, 0.74),
    }

    def __init__(self, app):
        super().__init__(application=app, title="Signal Radar")
        self.set_default_size(1260, 840)
        self.set_resizable(True)

        self.executor = ThreadPoolExecutor(max_workers=2)
        self.scan_token = 0
        self.scan_phase = "idle"
        self.scan_started_at = 0.0
        self.sweep_angle = 0.0
        self.last_scan_label = "No scans yet"
        self.devices = []
        self.visible_ids = set()
        self.selected_device_id = None
        self.bluetooth_details = {}
        self.detail_loading = False
        self.privacy_enabled = False
        self.point_hits = []
        self.password_entry = None
        self.popup_timeout_id = 0
        self.detail_reveal_timeout_id = 0
        self.action_token = 0
        self.hovered_point_id = None

        self._build_ui()
        self._apply_css()
        self._set_status()
        self._refresh_list()
        self._update_detail_panel()
        GLib.timeout_add(33, self._tick)

    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        root.set_margin_top(22)
        root.set_margin_bottom(22)
        root.set_margin_start(22)
        root.set_margin_end(22)
        root.add_css_class("app-root")

        scroll = Gtk.ScrolledWindow()
        scroll.add_css_class("flat-scroll")
        scroll.set_has_frame(False)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        header.add_css_class("hero")

        hero_copy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        eyebrow = Gtk.Label(label="FIT SCANNER")
        eyebrow.set_halign(Gtk.Align.START)
        eyebrow.add_css_class("eyebrow")
        title = Gtk.Label(label="FiT scanner (wifi-bluetooth scanner)")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("title")
        subtitle = Gtk.Label(
            label="a fancy thingi for scanning wifi-bt devices"
        )
        subtitle.set_wrap(True)
        subtitle.set_halign(Gtk.Align.START)
        subtitle.add_css_class("subtitle")
        hero_copy.append(eyebrow)
        hero_copy.append(title)
        hero_copy.append(subtitle)

        top_controls = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        top_controls.add_css_class("hero-side")

        self.status_chip = Gtk.Label(label="Idle")
        self.status_chip.set_halign(Gtk.Align.START)
        self.status_chip.add_css_class("status-chip")

        control_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.scan_button = Gtk.Button(label="Scan now")
        self.scan_button.connect("clicked", lambda *_: self.refresh_scan())
        self.scan_button.add_css_class("primary-button")

        privacy_toggle = Gtk.CheckButton(label="Privacy mode")
        privacy_toggle.connect("toggled", self._on_privacy_toggled)
        privacy_toggle.add_css_class("privacy-toggle")

        control_row.append(self.scan_button)
        control_row.append(privacy_toggle)

        self.status_meta = Gtk.Label(label="Open instantly, scan only when you ask.")
        self.status_meta.set_wrap(True)
        self.status_meta.set_halign(Gtk.Align.START)
        self.status_meta.add_css_class("status-meta")

        top_controls.append(self.status_chip)
        top_controls.append(control_row)
        top_controls.append(self.status_meta)

        header.append(hero_copy)
        header.append(top_controls)

        self.popup_revealer = Gtk.Revealer()
        self.popup_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.popup_revealer.set_reveal_child(False)
        self.popup_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.popup_box.add_css_class("popup")
        self.popup_label = Gtk.Label(label="")
        self.popup_label.set_halign(Gtk.Align.START)
        self.popup_label.set_wrap(True)
        self.popup_box.append(self.popup_label)
        self.popup_revealer.set_child(self.popup_box)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        content.set_hexpand(True)
        content.set_vexpand(True)

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        left.set_hexpand(True)
        left.set_vexpand(True)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        right.set_hexpand(True)
        right.set_vexpand(True)

        overview = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        overview.add_css_class("panel")
        overview.set_hexpand(True)

        stats = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        stats.set_hexpand(True)
        self.wifi_stat = self._build_stat("0", "Wi-Fi targets")
        self.bt_stat = self._build_stat("0", "Bluetooth targets")
        self.total_stat = self._build_stat("0", "Visible now")
        stats.append(self.wifi_stat["box"])
        stats.append(self.bt_stat["box"])
        stats.append(self.total_stat["box"])

        radar_shell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        radar_shell.add_css_class("radar-shell")
        radar_shell.set_hexpand(True)
        radar_shell.set_vexpand(True)

        self.drawing = Gtk.DrawingArea()
        self.drawing.set_content_width(320)
        self.drawing.set_content_height(320)
        self.drawing.set_hexpand(True)
        self.drawing.set_vexpand(True)
        self.drawing.set_draw_func(self._draw_radar)
        click = Gtk.GestureClick()
        click.connect("pressed", self._on_radar_click)
        self.drawing.add_controller(click)
        motion = Gtk.EventControllerMotion()
        motion.connect("motion", self._on_radar_motion)
        motion.connect("leave", self._on_radar_leave)
        self.drawing.add_controller(motion)

        legend = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        legend.set_halign(Gtk.Align.CENTER)
        legend.append(self._legend_chip("Wi-Fi", "wifi"))
        legend.append(self._legend_chip("Bluetooth", "bluetooth"))
        legend.append(self._legend_chip("Universal", "universal"))
        legend.append(self._legend_chip("Selected", "selected"))

        self.scan_meta = Gtk.Label(label="Ready. Start a scan when you want.")
        self.scan_meta.set_wrap(True)
        self.scan_meta.set_halign(Gtk.Align.START)
        self.scan_meta.add_css_class("caption")

        note = Gtk.Label(
            label="Placement is relative and collision-resolved. It scales with signal strength but is not a real-world map."
        )
        note.set_wrap(True)
        note.set_halign(Gtk.Align.START)
        note.add_css_class("caption")

        radar_shell.append(self.drawing)
        radar_shell.append(legend)
        radar_shell.append(self.scan_meta)
        radar_shell.append(note)

        overview.append(stats)
        overview.append(radar_shell)

        list_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        list_panel.add_css_class("panel")
        list_panel.set_hexpand(True)
        list_panel.set_vexpand(True)
        list_panel.set_size_request(-1, 280)
        list_head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        list_title = Gtk.Label(label="Nearby targets")
        list_title.set_halign(Gtk.Align.START)
        list_title.add_css_class("section-title")
        self.list_caption = Gtk.Label(label="Nothing scanned yet.")
        self.list_caption.set_halign(Gtk.Align.START)
        self.list_caption.add_css_class("caption")
        list_head.append(list_title)
        list_head.append(self.list_caption)

        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        list_scroll = Gtk.ScrolledWindow()
        list_scroll.add_css_class("flat-scroll")
        list_scroll.set_has_frame(False)
        list_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        list_scroll.set_child(self.list_box)
        list_scroll.set_vexpand(True)

        list_panel.append(list_head)
        list_panel.append(list_scroll)

        detail_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        detail_panel.add_css_class("panel")
        detail_panel.set_hexpand(True)
        detail_panel.set_vexpand(True)

        detail_title = Gtk.Label(label="Selected device")
        detail_title.set_halign(Gtk.Align.START)
        detail_title.add_css_class("section-title")
        self.detail_hint = Gtk.Label(label="Select a row or radar point to inspect more detail.")
        self.detail_hint.set_wrap(True)
        self.detail_hint.set_halign(Gtk.Align.START)
        self.detail_hint.add_css_class("caption")

        self.detail_name = Gtk.Label(label="No device selected")
        self.detail_name.set_halign(Gtk.Align.START)
        self.detail_name.add_css_class("detail-name")

        self.detail_badge = Gtk.Label(label="IDLE")
        self.detail_badge.set_halign(Gtk.Align.START)
        self.detail_badge.add_css_class("detail-badge")

        self.detail_grid = Gtk.Grid(column_spacing=10, row_spacing=8)
        self.detail_grid.set_column_homogeneous(False)
        self.detail_rows = {}
        detail_fields = [
            ("source", "Scanner"),
            ("signal", "Signal"),
            ("range", "Estimated range"),
            ("hardware", "Hardware ID"),
            ("security", "Security"),
            ("channel", "Channel"),
            ("rate", "Rate"),
            ("paired", "Paired"),
            ("trusted", "Trusted"),
            ("connected", "Connected"),
            ("placement", "Placement"),
        ]
        for row, (key, label) in enumerate(detail_fields):
            key_label = Gtk.Label(label=label)
            key_label.set_halign(Gtk.Align.START)
            key_label.add_css_class("detail-key")
            value_label = Gtk.Label(label="—")
            value_label.set_wrap(True)
            value_label.set_halign(Gtk.Align.START)
            value_label.add_css_class("detail-value")
            self.detail_grid.attach(key_label, 0, row, 1, 1)
            self.detail_grid.attach(value_label, 1, row, 1, 1)
            self.detail_rows[key] = value_label

        self.password_entry = Gtk.Entry()
        self.password_entry.set_placeholder_text("Wi-Fi password when needed")
        self.password_entry.set_visibility(False)
        self.password_entry.set_visible(False)
        self.password_entry.set_sensitive(False)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.connect_button = Gtk.Button(label="Connect")
        self.connect_button.connect("clicked", self._on_connect_clicked)
        self.connect_button.add_css_class("primary-button")
        self._attach_hover_effect(self.connect_button, "button-hover")
        self._attach_press_effect(self.connect_button, "button-pressed")

        refresh_button = Gtk.Button(label="Refresh")
        refresh_button.connect("clicked", lambda *_: self.refresh_scan())
        refresh_button.add_css_class("ghost-button")
        self._attach_hover_effect(refresh_button, "button-hover")
        self._attach_press_effect(refresh_button, "button-pressed")

        actions.append(self.connect_button)
        actions.append(refresh_button)

        self.action_status = Gtk.Label(label="Connection actions use local system tools only.")
        self.action_status.set_wrap(True)
        self.action_status.set_halign(Gtk.Align.START)
        self.action_status.add_css_class("caption")

        self.detail_revealer = Gtk.Revealer()
        self.detail_revealer.set_transition_type(Gtk.RevealerTransitionType.CROSSFADE)
        self.detail_revealer.set_transition_duration(180)
        self.detail_revealer.set_reveal_child(True)
        detail_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        detail_content.append(detail_title)
        detail_content.append(self.detail_hint)
        detail_content.append(self.detail_name)
        detail_content.append(self.detail_badge)
        detail_content.append(self.detail_grid)
        detail_content.append(self.password_entry)
        detail_content.append(actions)
        detail_content.append(self.action_status)
        self.detail_revealer.set_child(detail_content)
        detail_panel.append(self.detail_revealer)

        left.append(overview)
        left.append(list_panel)
        right.append(detail_panel)

        content.append(left)
        content.append(right)

        root.append(header)
        root.append(self.popup_revealer)
        root.append(content)
        scroll.set_child(root)
        self.set_child(scroll)

    def _apply_css(self):
        css = b"""
        window {
          background:
            radial-gradient(circle at 0% 0%, rgba(211, 169, 248, 0.12), transparent 30%),
            radial-gradient(circle at 100% 0%, rgba(128, 194, 255, 0.10), transparent 26%),
            linear-gradient(180deg, rgba(18, 14, 28, 0.99), rgba(10, 9, 19, 0.99));
          color: #f7f2ff;
          font-family: "IBM Plex Sans", "Inter", sans-serif;
        }
        .app-root {
          background: transparent;
        }
        .hero, .panel, .stat-card, .device-row, .empty-state, .legend-chip, .detail-badge, entry, .popup {
          background: rgba(28, 21, 42, 0.96);
          border: 1px solid rgba(220, 197, 255, 0.12);
          border-radius: 24px;
        }
        .hero {
          padding: 18px 20px;
        }
        .hero-side {
          min-width: 280px;
        }
        .panel {
          padding: 16px;
        }
        .panel,
        .radar-shell {
          min-width: 0;
        }
        .panel {
          min-height: 0;
        }
        .eyebrow, .detail-key {
          font-size: 11px;
          letter-spacing: 0.18em;
          color: #cdbce7;
          font-weight: 700;
        }
        .title {
          font-size: 34px;
          font-weight: 800;
          letter-spacing: -0.05em;
        }
        .subtitle, .caption, .status-meta, .stat-label, .detail-value, .device-meta, .device-signal {
          color: #ddd0f3;
          font-size: 12px;
          line-height: 1.5;
        }
        .status-chip {
          background: linear-gradient(135deg, rgba(211, 169, 248, 0.24), rgba(128, 194, 255, 0.18));
          border: 1px solid rgba(231, 215, 255, 0.18);
          border-radius: 999px;
          padding: 8px 12px;
          font-size: 12px;
          font-weight: 700;
        }
        .stat-card {
          padding: 14px;
          min-width: 130px;
        }
        .stat-value {
          font-size: 26px;
          font-weight: 800;
        }
        .section-title {
          font-size: 18px;
          font-weight: 700;
        }
        .detail-name {
          font-size: 22px;
          font-weight: 800;
        }
        .radar-shell {
          padding: 14px;
          border-radius: 24px;
          background:
            linear-gradient(180deg, rgba(19, 15, 30, 0.9), rgba(15, 12, 23, 0.94));
        }
        .legend-chip {
          padding: 8px 12px;
        }
        .dot {
          min-width: 10px;
          min-height: 10px;
          border-radius: 999px;
        }
        .dot.wifi { background: #80c2ff; }
        .dot.bluetooth { background: #d3a9f8; }
        .dot.universal { background: #8ef0bb; }
        .dot.selected { background: #f8c8ec; }
        button {
          border-radius: 14px;
          border: none;
          font-weight: 700;
          padding: 10px 16px;
          transition: 180ms ease;
        }
        .primary-button {
          color: #110c1c;
          background: linear-gradient(135deg, #f8c8ec, #d3a9f8 55%, #8ccfff);
        }
        .primary-button.button-hover {
          background: linear-gradient(135deg, #ffd7f0, #e0b9ff 55%, #a6ddff);
        }
        .primary-button.button-pressed {
          background: linear-gradient(135deg, #f2b9e0, #c993f0 55%, #79c6ff);
        }
        .ghost-button {
          color: #f7f2ff;
          background: rgba(211, 169, 248, 0.12);
          border: 1px solid rgba(220, 197, 255, 0.12);
        }
        .ghost-button.button-hover {
          background: rgba(211, 169, 248, 0.22);
          border-color: rgba(248, 200, 236, 0.24);
        }
        .ghost-button.button-pressed {
          background: rgba(211, 169, 248, 0.30);
          border-color: rgba(248, 200, 236, 0.30);
        }
        .detail-badge, .badge {
          border-radius: 999px;
          padding: 6px 10px;
          font-size: 10px;
          font-weight: 800;
          letter-spacing: 0.12em;
        }
        .popup {
          padding: 12px 14px;
        }
        .popup.success {
          border-color: rgba(142, 240, 187, 0.35);
          background: rgba(25, 52, 41, 0.95);
        }
        .popup.error {
          border-color: rgba(248, 113, 113, 0.35);
          background: rgba(66, 29, 42, 0.95);
        }
        .popup.progress {
          border-color: rgba(128, 194, 255, 0.35);
          background: rgba(27, 40, 66, 0.95);
        }
        .badge.wifi, .detail-badge.wifi {
          background: rgba(128, 194, 255, 0.16);
          color: #bfe4ff;
        }
        .badge.bluetooth, .detail-badge.bluetooth {
          background: rgba(211, 169, 248, 0.16);
          color: #efd9ff;
        }
        .badge.universal, .detail-badge.universal {
          background: rgba(142, 240, 187, 0.16);
          color: #cffff0;
        }
        .device-row {
          padding: 12px;
          transition: 180ms ease;
        }
        .device-row.selected-row {
          border-color: rgba(248, 200, 236, 0.35);
          background: rgba(46, 36, 68, 0.98);
        }
        .device-row.row-hover:not(.selected-row) {
          background: rgba(43, 33, 63, 0.98);
          border-color: rgba(220, 197, 255, 0.22);
        }
        .device-name {
          font-weight: 700;
        }
        .flat-scroll, .flat-scroll > viewport, .flat-scroll undershoot.top, .flat-scroll undershoot.bottom, .flat-scroll undershoot.left, .flat-scroll undershoot.right {
          background: transparent;
          border: none;
          box-shadow: none;
        }
        checkbutton {
          color: #f7f2ff;
        }
        checkbutton check {
          background: rgba(211, 169, 248, 0.12);
          border: 1px solid rgba(220, 197, 255, 0.16);
          border-radius: 999px;
        }
        checkbutton:checked check {
          background: #d3a9f8;
          border-color: #f8c8ec;
        }
        entry {
          padding: 12px;
          color: #f7f2ff;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _build_stat(self, value, label):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.add_css_class("stat-card")
        value_label = Gtk.Label(label=value)
        value_label.set_halign(Gtk.Align.START)
        value_label.add_css_class("stat-value")
        name_label = Gtk.Label(label=label)
        name_label.set_halign(Gtk.Align.START)
        name_label.add_css_class("stat-label")
        box.append(value_label)
        box.append(name_label)
        return {"box": box, "value": value_label}

    def _legend_chip(self, label, cls):
        chip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        chip.add_css_class("legend-chip")
        dot = Gtk.Box()
        dot.set_size_request(10, 10)
        dot.add_css_class("dot")
        dot.add_css_class(cls)
        text = Gtk.Label(label=label)
        chip.append(dot)
        chip.append(text)
        return chip

    def _attach_hover_effect(self, widget, css_class):
        motion = Gtk.EventControllerMotion()
        motion.connect("enter", lambda *_: widget.add_css_class(css_class))
        motion.connect("leave", lambda *_: widget.remove_css_class(css_class))
        widget.add_controller(motion)

    def _attach_press_effect(self, widget, css_class):
        gesture = Gtk.GestureClick()
        gesture.connect("pressed", lambda *_: widget.add_css_class(css_class))
        gesture.connect("released", lambda *_: widget.remove_css_class(css_class))
        gesture.connect("cancel", lambda *_: widget.remove_css_class(css_class))
        widget.add_controller(gesture)

    def _tick(self):
        if self.scan_phase == "sweeping":
            progress = min(1.0, (time.time() - self.scan_started_at) / self.SWEEP_SECONDS)
            self.sweep_angle = progress * math.tau
            self._update_visible_devices()
            if progress >= 1.0:
                self.scan_phase = "idle"
                self.last_scan_label = time.strftime("Last scan at %H:%M")
                self._set_status()
                self._refresh_list()
                self._update_detail_panel()
        self.drawing.queue_draw()
        return True

    def refresh_scan(self):
        if self.scan_phase == "collecting":
            return

        self.scan_phase = "collecting"
        self.visible_ids = set()
        self.devices = []
        self.selected_device_id = None
        self.scan_button.set_sensitive(False)
        self._set_status()
        self._refresh_list()
        self._update_detail_panel()

        self.scan_token += 1
        current_token = self.scan_token
        future = self.executor.submit(self._collect_devices)
        future.add_done_callback(lambda task: GLib.idle_add(self._finish_scan, current_token, task))

    def _collect_devices(self):
        wifi_devices = self._scan_wifi()
        bt_devices = self._scan_bluetooth()
        devices = self._merge_universal_devices(wifi_devices, bt_devices)
        return self._resolve_positions(devices)

    def _merge_universal_devices(self, wifi_devices, bt_devices):
        merged = list(wifi_devices)
        used_bt_ids = set()
        for wifi in merged:
            wifi_name = self._normalized_name(wifi["name"])
            if not wifi_name:
                continue
            for bt in bt_devices:
                if bt["id"] in used_bt_ids:
                    continue
                if wifi_name == self._normalized_name(bt["name"]):
                    wifi["type"] = "universal"
                    wifi["source"] = "Wi-Fi + Bluetooth"
                    wifi["subtitle"] = "Universal device"
                    wifi["paired"] = bt.get("paired", "—")
                    wifi["trusted"] = bt.get("trusted", "—")
                    wifi["connected"] = "Yes" if "Yes" in (wifi.get("connected", ""), bt.get("connected", "")) else bt.get("connected", wifi.get("connected", "—"))
                    wifi["security"] = f"{wifi.get('security', 'Unknown')} + Bluetooth"
                    wifi["bt_hardware_id"] = bt["hardware_id"]
                    used_bt_ids.add(bt["id"])
                    break
        for bt in bt_devices:
            if bt["id"] not in used_bt_ids:
                merged.append(bt)
        return merged

    def _normalized_name(self, name):
        return re.sub(r"[^a-z0-9]+", "", (name or "").lower())

    def _finish_scan(self, token, future):
        if token != self.scan_token:
            return False

        self.scan_button.set_sensitive(True)
        self.devices = future.result() if not future.cancelled() else []
        self.visible_ids = set()
        self.scan_started_at = time.time()
        self.sweep_angle = 0.0
        self.scan_phase = "sweeping"
        self.selected_device_id = self.devices[0]["id"] if self.devices else None
        self._set_status()
        self._refresh_list()
        self._update_detail_panel()
        return False

    def _scan_wifi(self):
        results = []
        output = run_command(
            ["nmcli", "-m", "multiline", "-f", "IN-USE,SSID,SIGNAL,BARS,SECURITY,BSSID,CHAN,RATE", "dev", "wifi", "list"]
        )
        if not output:
            return results

        records = []
        current = {}
        for line in output.splitlines():
            if not line.strip():
                if current:
                    records.append(current)
                    current = {}
                continue
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            current[key.strip()] = value.strip()
        if current:
            records.append(current)

        for record in records[:14]:
            bssid = record.get("BSSID")
            if not bssid:
                continue
            signal = self._safe_int(record.get("SIGNAL"), 0)
            results.append(
                {
                    "id": f"wifi-{bssid}",
                    "type": "wifi",
                    "name": record.get("SSID") or "Hidden network",
                    "signal": signal,
                    "dist": self._distance_from_signal(signal, 0.12, 0.92),
                    "angle": self._stable_angle(f"wifi-{bssid}"),
                    "range_m": max(2, int(2 + (100 - signal) * 0.18)),
                    "hardware_id": bssid,
                    "security": record.get("SECURITY") or "Unknown",
                    "channel": record.get("CHAN") or "—",
                    "rate": record.get("RATE") or "—",
                    "paired": "—",
                    "trusted": "—",
                    "connected": "Yes" if "*" in (record.get("IN-USE") or "") else "No",
                    "source": "Wi-Fi scan",
                    "placement": "Relative estimate based on signal strength and overlap resolution.",
                    "subtitle": self._wifi_subtitle(record),
                }
            )
        return results

    def _scan_bluetooth(self):
        results = []
        output = run_command(["bluetoothctl", "devices"])
        if not output:
            return results

        for index, line in enumerate(output.splitlines()[:14]):
            if not line.startswith("Device "):
                continue
            _, mac, name = line.split(" ", 2)
            results.append(
                {
                    "id": f"bluetooth-{mac}",
                    "type": "bluetooth",
                    "name": name.strip() or "Bluetooth device",
                    "signal": max(28, 76 - index * 5),
                    "dist": 0.20 + index * 0.05,
                    "angle": self._stable_angle(f"bluetooth-{mac}"),
                    "range_m": max(1, int(1 + index * 2)),
                    "hardware_id": mac,
                    "security": "Bluetooth device",
                    "channel": "—",
                    "rate": "—",
                    "paired": "—",
                    "trusted": "—",
                    "connected": "—",
                    "source": "Bluetooth scan",
                    "placement": "Relative estimate from nearby Bluetooth discovery and overlap resolution.",
                    "subtitle": "Bluetooth discovery target",
                }
            )
        return results

    def _load_bluetooth_detail(self, device):
        if device["hardware_id"] in self.bluetooth_details or self.detail_loading:
            return
        self.detail_loading = True
        target_id = device["id"]
        future = self.executor.submit(self._bluetooth_info, device["hardware_id"])
        future.add_done_callback(
            lambda task: GLib.idle_add(self._finish_bluetooth_detail, target_id, device["hardware_id"], task)
        )

    def _bluetooth_info(self, mac):
        output = run_command(["bluetoothctl", "info", mac])
        info = {}
        for line in output.splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            info[key.strip()] = value.strip()
        return info

    def _finish_bluetooth_detail(self, target_id, mac, future):
        self.detail_loading = False
        self.bluetooth_details[mac] = future.result() if not future.cancelled() else {}
        if self.selected_device_id == target_id:
            self._update_detail_panel()
        return False

    def _resolve_positions(self, devices):
        devices = sorted(devices, key=lambda item: (item["angle"], item["dist"]))
        for _ in range(10):
            changed = False
            for index, first in enumerate(devices):
                for second in devices[index + 1 :]:
                    if abs(first["dist"] - second["dist"]) < 0.07 and self._angle_distance(first["angle"], second["angle"]) < 0.22:
                        second["angle"] = (second["angle"] + 0.21) % math.tau
                        second["dist"] = min(0.94, second["dist"] + 0.05)
                        changed = True
            if not changed:
                break
        return devices

    def _stable_angle(self, key):
        return random.Random(key).random() * math.tau

    def _angle_distance(self, a, b):
        diff = abs(a - b) % math.tau
        return min(diff, math.tau - diff)

    def _distance_from_signal(self, signal, minimum, maximum):
        return max(minimum, min(maximum, minimum + (maximum - minimum) * (100 - signal) / 100))

    def _safe_int(self, value, default):
        try:
            return int(str(value).strip())
        except Exception:
            return default

    def _wifi_subtitle(self, record):
        security = record.get("SECURITY") or "Unknown"
        channel = record.get("CHAN") or "?"
        return f"{security} • channel {channel}"

    def _update_visible_devices(self):
        for device in self.devices:
            delta = (device["angle"] - self.sweep_angle) % math.tau
            if delta < 0.18 or delta > math.tau - 0.18:
                self.visible_ids.add(device["id"])
        self._set_status()
        self._refresh_list()

    def _visible_devices(self):
        if self.scan_phase == "sweeping":
            return [device for device in self.devices if device["id"] in self.visible_ids]
        return list(self.devices)

    def _device_by_id(self, device_id):
        for device in self.devices:
            if device["id"] == device_id:
                return device
        return None

    def _set_status(self):
        wifi_count = len([d for d in self.devices if d["type"] == "wifi"])
        bt_count = len([d for d in self.devices if d["type"] == "bluetooth"])
        visible_count = len(self._visible_devices())

        self.wifi_stat["value"].set_text(str(wifi_count))
        self.bt_stat["value"].set_text(str(bt_count))
        self.total_stat["value"].set_text(str(visible_count))

        if self.scan_phase == "collecting":
            self.status_chip.set_text("Collecting local data")
            self.status_meta.set_text("The window stays responsive while Wi-Fi and Bluetooth scans run in the background.")
            self.scan_meta.set_text("Gathering nearby device data…")
            self.list_caption.set_text("Waiting for scan results.")
        elif self.scan_phase == "sweeping":
            self.status_chip.set_text("Radar sweep in progress")
            self.status_meta.set_text("Devices appear as the sweep passes over their relative positions.")
            self.scan_meta.set_text("Rendering live radar sweep…")
            self.list_caption.set_text("Visible devices update during the sweep.")
        elif self.devices:
            self.status_chip.set_text("Scan complete")
            self.status_meta.set_text(self.last_scan_label)
            self.scan_meta.set_text(self.last_scan_label)
            self.list_caption.set_text("Select a target for detail or connection actions.")
        else:
            self.status_chip.set_text("Idle")
            self.status_meta.set_text("Open instantly, scan only when you ask.")
            self.scan_meta.set_text("Ready. Start a scan when you want.")
            self.list_caption.set_text("No targets yet.")

    def _refresh_list(self):
        child = self.list_box.get_first_child()
        while child:
            next_child = child.get_next_sibling()
            self.list_box.remove(child)
            child = next_child

        visible = sorted(self._visible_devices(), key=lambda item: item["signal"], reverse=True)
        if not visible:
            self.list_box.append(self._empty_state())
            return

        for device in visible:
            self.list_box.append(self._device_row(device))

    def _empty_state(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.add_css_class("empty-state")
        title = Gtk.Label(label="No visible targets" if self.scan_phase == "sweeping" else "Nothing scanned yet")
        title.set_halign(Gtk.Align.START)
        title.add_css_class("device-name")
        body = Gtk.Label(
            label="The sweep is still moving." if self.scan_phase == "sweeping" else "Press Scan now to fetch nearby devices."
        )
        body.set_wrap(True)
        body.set_halign(Gtk.Align.START)
        body.add_css_class("caption")
        box.append(title)
        box.append(body)
        return box

    def _device_row(self, device):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("device-row")
        if device["id"] == self.selected_device_id:
            row.add_css_class("selected-row")
        self._attach_hover_effect(row, "row-hover")

        click = Gtk.GestureClick()
        click.connect("pressed", lambda *_: self._select_device(device["id"]))
        row.add_controller(click)

        badge = Gtk.Label(label="WLAN" if device["type"] == "wifi" else "BT" if device["type"] == "bluetooth" else "UNI")
        badge.add_css_class("badge")
        badge.add_css_class(device["type"])

        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        center.set_hexpand(True)
        name = Gtk.Label(label=self._display_name(device))
        name.set_halign(Gtk.Align.START)
        name.add_css_class("device-name")
        meta = Gtk.Label(label=f"{self._display_subtitle(device)} • {self._strength_label(device['signal'])} • est {device['range_m']} m")
        meta.set_halign(Gtk.Align.START)
        meta.add_css_class("device-meta")
        center.append(name)
        center.append(meta)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        right.set_halign(Gtk.Align.END)
        bars = self._signal_bars(device)
        signal = Gtk.Label(label=f"{device['signal']}%")
        signal.set_halign(Gtk.Align.END)
        signal.add_css_class("device-signal")
        right.append(bars)
        right.append(signal)

        row.append(badge)
        row.append(center)
        row.append(right)
        return row

    def _signal_bars(self, device):
        bars = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=3)
        active_color = "#80c2ff" if device["type"] == "wifi" else "#d3a9f8" if device["type"] == "bluetooth" else "#8ef0bb"
        for threshold, height in zip((25, 45, 65, 85), (10, 14, 18, 22)):
            bar = Gtk.Box()
            bar.set_size_request(4, height)
            color = active_color if device["signal"] >= threshold else "rgba(220,197,255,0.14)"
            provider = Gtk.CssProvider()
            provider.load_from_data(f"box {{ background: {color}; border-radius: 999px; }}".encode("utf-8"))
            bar.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            bars.append(bar)
        return bars

    def _select_device(self, device_id):
        self.selected_device_id = device_id
        device = self._device_by_id(device_id)
        if device and device["type"] in ("bluetooth", "universal"):
            self._load_bluetooth_detail(device)
        self._refresh_list()
        self._update_detail_panel()
        self.drawing.queue_draw()

    def _update_detail_panel(self):
        self._animate_detail_refresh()
        device = self._device_by_id(self.selected_device_id)
        if not device:
            self.detail_name.set_text("No device selected")
            self.detail_badge.set_text("IDLE")
            self.detail_badge.remove_css_class("wifi")
            self.detail_badge.remove_css_class("bluetooth")
            self.detail_badge.remove_css_class("universal")
            for label in self.detail_rows.values():
                label.set_text("—")
            self.password_entry.set_text("")
            self.password_entry.set_visible(False)
            self.password_entry.set_sensitive(False)
            self.action_status.set_text("Connection actions use local system tools only.")
            return

        if device["type"] in ("bluetooth", "universal"):
            info_key = device.get("bt_hardware_id", device["hardware_id"])
            info = self.bluetooth_details.get(info_key, {})
            if info:
                device = {**device, **self._bluetooth_device_overlay(info)}

        self.detail_name.set_text(self._display_name(device))
        self.detail_badge.set_text("WLAN" if device["type"] == "wifi" else "BLUETOOTH" if device["type"] == "bluetooth" else "UNIVERSAL")
        self.detail_badge.remove_css_class("wifi")
        self.detail_badge.remove_css_class("bluetooth")
        self.detail_badge.remove_css_class("universal")
        self.detail_badge.add_css_class(device["type"])

        values = {
            "source": self._privacy_value(device.get("source", "—")),
            "signal": self._privacy_value(f"{device['signal']}% ({self._strength_label(device['signal'])})"),
            "range": self._privacy_value(f"Approx {device['range_m']} m"),
            "hardware": self._display_hardware(device["hardware_id"]),
            "security": self._display_detail(device, "security"),
            "channel": self._display_detail(device, "channel"),
            "rate": self._display_detail(device, "rate"),
            "paired": self._privacy_value(str(device.get("paired", "—"))),
            "trusted": self._privacy_value(str(device.get("trusted", "—"))),
            "connected": self._privacy_value(str(device.get("connected", "—"))),
            "placement": self._display_detail(device, "placement"),
        }
        for key, label in self.detail_rows.items():
            label.set_text(values.get(key, "—"))

        is_wifi = device["type"] in ("wifi", "universal")
        self.password_entry.set_visible(is_wifi)
        self.password_entry.set_sensitive(is_wifi)
        if not is_wifi:
            self.password_entry.set_text("")
        if device["type"] in ("wifi", "universal"):
            self.detail_hint.set_text("Use Connect for the selected Wi-Fi network. Enter a password only if the network is not already saved.")
        else:
            self.detail_hint.set_text("Bluetooth detail loads lazily. Connect uses bluetoothctl on the selected device.")

    def _animate_detail_refresh(self):
        if not hasattr(self, "detail_revealer"):
            return
        if self.detail_reveal_timeout_id:
            GLib.source_remove(self.detail_reveal_timeout_id)
            self.detail_reveal_timeout_id = 0
        self.detail_revealer.set_reveal_child(False)
        self.detail_reveal_timeout_id = GLib.timeout_add(70, self._reveal_detail_again)

    def _reveal_detail_again(self):
        self.detail_revealer.set_reveal_child(True)
        self.detail_reveal_timeout_id = 0
        return False

    def _bluetooth_device_overlay(self, info):
        return {
            "security": "Bluetooth device",
            "paired": self._yes_no(info.get("Paired")),
            "trusted": self._yes_no(info.get("Trusted")),
            "connected": self._yes_no(info.get("Connected")),
        }

    def _yes_no(self, value):
        lowered = (value or "").strip().lower()
        if lowered == "yes":
            return "Yes"
        if lowered == "no":
            return "No"
        return "—"

    def _on_connect_clicked(self, *_):
        device = self._device_by_id(self.selected_device_id)
        if not device:
            self.action_status.set_text("Select a device first.")
            return
        self.connect_button.set_sensitive(False)
        self.action_status.set_text("Connecting...")
        self._show_progress_popup(f"Connecting to {self._display_name(device)}...")

        self.action_token += 1
        token = self.action_token
        if device["type"] in ("wifi", "universal"):
            future = self.executor.submit(self._connect_wifi, dict(device))
        else:
            future = self.executor.submit(self._run_action, ["bluetoothctl", "connect", device["hardware_id"]])
        future.add_done_callback(lambda task: GLib.idle_add(self._finish_connect, token, device["id"], task))

    def _finish_connect(self, token, device_id, future):
        if token != self.action_token:
            return False
        self.connect_button.set_sensitive(True)
        success, message = future.result() if not future.cancelled() else (False, "Connection cancelled.")
        device = self._device_by_id(device_id)
        prefix = "Connected." if success else "Connection failed."
        self.action_status.set_text(f"{prefix} {message[:220]}")
        self._show_popup(success, f"{prefix} {message[:220]}")
        if success and device:
            device["connected"] = "Yes"
        self._update_detail_panel()
        self._refresh_list()
        return False

    def _show_popup(self, success, message):
        if self.popup_timeout_id:
            GLib.source_remove(self.popup_timeout_id)
        self.popup_timeout_id = 0
        self.popup_box.remove_css_class("success")
        self.popup_box.remove_css_class("error")
        self.popup_box.remove_css_class("progress")
        self.popup_box.add_css_class("success" if success else "error")
        self.popup_label.set_text(message)
        self.popup_revealer.set_reveal_child(True)
        self.popup_timeout_id = GLib.timeout_add(4200, self._hide_popup)

    def _show_progress_popup(self, message):
        if self.popup_timeout_id:
            GLib.source_remove(self.popup_timeout_id)
            self.popup_timeout_id = 0
        self.popup_box.remove_css_class("success")
        self.popup_box.remove_css_class("error")
        self.popup_box.add_css_class("progress")
        self.popup_label.set_text(message)
        self.popup_revealer.set_reveal_child(True)

    def _hide_popup(self):
        self.popup_revealer.set_reveal_child(False)
        self.popup_timeout_id = 0
        return False

    def _connect_wifi(self, device):
        password = self.password_entry.get_text().strip()
        args = ["nmcli", "dev", "wifi", "connect", device["hardware_id"]]
        security = str(device.get("security", "")).lower()
        if security not in ("", "open", "—", "--", "unknown") and password:
            args.extend(["password", password])
        return self._run_action(args)

    def _run_action(self, args):
        try:
            completed = subprocess.run(args, text=True, capture_output=True, timeout=20, check=False)
        except Exception as exc:
            return False, str(exc)
        output = completed.stdout.strip() or completed.stderr.strip() or "Command finished."
        return completed.returncode == 0, output

    def _on_privacy_toggled(self, button):
        self.privacy_enabled = button.get_active()
        self._refresh_list()
        self._update_detail_panel()
        self.drawing.queue_draw()

    def _on_radar_click(self, _gesture, _n_press, x, y):
        nearest = None
        best = None
        for hit in self.point_hits:
            distance = math.hypot(hit["x"] - x, hit["y"] - y)
            if distance <= 20 and (best is None or distance < best):
                nearest = hit["id"]
                best = distance
        if nearest:
            self._select_device(nearest)

    def _on_radar_motion(self, _controller, x, y):
        hovered = None
        best = None
        for hit in self.point_hits:
            distance = math.hypot(hit["x"] - x, hit["y"] - y)
            if distance <= 20 and (best is None or distance < best):
                hovered = hit["id"]
                best = distance
        if hovered != self.hovered_point_id:
            self.hovered_point_id = hovered
            self.drawing.queue_draw()

    def _on_radar_leave(self, _controller):
        if self.hovered_point_id is not None:
            self.hovered_point_id = None
            self.drawing.queue_draw()

    def _strength_label(self, signal):
        if signal >= 80:
            return "Excellent"
        if signal >= 60:
            return "Stable"
        if signal >= 40:
            return "Fair"
        return "Weak"

    def _draw_radar(self, _area, cr, width, height):
        size = min(width, height)
        radius = size / 2 - 26
        cx = width / 2
        cy = height / 2
        self.point_hits = []

        cr.set_source_rgba(0.12, 0.09, 0.20, 0.95)
        cr.arc(cx, cy, radius + 10, 0, math.tau)
        cr.fill()

        cr.set_line_width(1)
        cr.set_source_rgba(0.86, 0.77, 0.98, 0.14)
        cr.select_font_face("Sans", 0, 0)
        cr.set_font_size(max(10, size * 0.022))
        for i in range(1, 5):
            ring = radius * i / 4
            cr.arc(cx, cy, ring, 0, math.tau)
            cr.stroke()
            cr.move_to(cx + 10, cy - ring + 14)
            cr.show_text(f"{i * 5}m")

        for i in range(12):
            angle = i * math.pi / 6
            cr.move_to(cx, cy)
            cr.line_to(cx + radius * math.cos(angle), cy + radius * math.sin(angle))
            cr.stroke()

        if self.scan_phase == "sweeping":
            sweep = math.pi / 2.15
            cr.move_to(cx, cy)
            cr.arc(cx, cy, radius, self.sweep_angle - sweep, self.sweep_angle)
            cr.close_path()
            cr.set_source_rgba(0.90, 0.70, 0.98, 0.15)
            cr.fill()

            cr.move_to(cx, cy)
            cr.line_to(cx + radius * math.cos(self.sweep_angle), cy + radius * math.sin(self.sweep_angle))
            cr.set_source_rgba(0.98, 0.88, 1.0, 0.92)
            cr.set_line_width(2)
            cr.stroke()

        visible = sorted(self._visible_devices(), key=lambda item: item["signal"], reverse=True)
        label_limit = max(2, min(6, len(visible)))
        for index, device in enumerate(visible):
            color = self.TYPE_COLORS[device["type"]]
            px = cx + device["dist"] * radius * math.cos(device["angle"])
            py = cy + device["dist"] * radius * math.sin(device["angle"])
            self.point_hits.append({"id": device["id"], "x": px, "y": py})

            selected = device["id"] == self.selected_device_id
            hovered = device["id"] == self.hovered_point_id
            glow = max(12, size * (0.038 if selected else 0.031 if hovered else 0.026))
            dot = max(5.5, size * (0.018 if selected else 0.015 if hovered else 0.013))

            cr.set_source_rgba(color[0], color[1], color[2], 0.14)
            cr.arc(px, py, glow, 0, math.tau)
            cr.fill()

            if selected or hovered:
                cr.set_source_rgba(0.98, 0.80, 0.93, 0.92)
                cr.arc(px, py, dot + 5, 0, math.tau)
                cr.stroke()

            cr.set_source_rgba(color[0], color[1], color[2], 1.0)
            cr.arc(px, py, dot, 0, math.tau)
            cr.fill()

            if index < label_limit or selected:
                label = self._display_label(device, visible)
                cr.set_source_rgba(0.98, 0.95, 1.0, 0.90 if selected else 0.72)
                cr.set_font_size(max(10, size * (0.022 if selected else 0.019)))
                ext = cr.text_extents(label)
                offset = 22 if index % 2 == 0 else -26
                cr.move_to(px - ext.width / 2, py - offset)
                cr.show_text(label)

        cr.set_source_rgba(0.90, 0.70, 0.98, 0.12)
        cr.arc(cx, cy, max(18, size * 0.04), 0, math.tau)
        cr.fill()
        cr.set_source_rgba(0.90, 0.70, 0.98, 1.0)
        cr.arc(cx, cy, max(6, size * 0.013), 0, math.tau)
        cr.fill()

    def _display_label(self, device, visible):
        label = self._display_name(device)
        duplicates = [item for item in visible if item["name"] == device["name"] and item["id"] != device["id"]]
        if duplicates:
            return f"{label[:10]} [{self._display_hardware(device['hardware_id'])[-2:]}]"
        return label[:18]

    def _display_name(self, device):
        return self._privacy_name(device["name"])

    def _display_subtitle(self, device):
        return self._privacy_value(device.get("subtitle", ""))

    def _display_hardware(self, hardware_id):
        if not self.privacy_enabled:
            return hardware_id
        cleaned = hardware_id.replace(":", "")
        if len(cleaned) < 4:
            return self._privacy_name(hardware_id)
        return f"{cleaned[:2]}••••••••{cleaned[-2:]}"

    def _display_detail(self, device, key):
        value = str(device.get(key, "—"))
        if not self.privacy_enabled:
            return value
        if key == "range":
            return value
        if key in ("channel", "rate"):
            return "Hidden in privacy mode"
        if key == "placement":
            return "Relative position hidden in privacy mode"
        if key == "security":
            return "Protected detail hidden"
        return self._privacy_value(value)

    def _privacy_name(self, value):
        if not self.privacy_enabled:
            return value
        if value.lower().startswith("approx "):
            return value
        tokens = re.split(r"(\s+)", value)
        return "".join(self._mask_token(token) if not token.isspace() else token for token in tokens)

    def _privacy_value(self, value):
        if not self.privacy_enabled:
            return value
        return self._privacy_name(value)

    def _mask_token(self, token):
        chars = list(token)
        alnum_positions = [index for index, char in enumerate(chars) if char.isalnum()]
        if len(alnum_positions) <= 2:
            return token
        first = alnum_positions[0]
        last = alnum_positions[-1]
        for index, char in enumerate(chars):
            if index in (first, last):
                continue
            if char.isalnum():
                chars[index] = "*"
        return "".join(chars)

    def close(self):
        self.executor.shutdown(cancel_futures=True)
        return super().close()


class SignalRadarApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="signal-radar", flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_activate(self):
        window = self.props.active_window
        if not window:
            window = SignalRadarWindow(self)
        window.present()


def main():
    app = SignalRadarApp()
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
