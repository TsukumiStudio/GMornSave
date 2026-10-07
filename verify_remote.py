#!/usr/bin/env python3
"""ヘッドレスEditorとゲームを接続し、2回の実行でドックの釦が届くか確認する。"""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

ADDON = Path(__file__).resolve().parent
GODOT = os.environ.get("GODOT_BIN", shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")

PROBE = '''@tool
extends EditorPlugin

func _enter_tree() -> void:
	EditorInterface.get_editor_settings().set_setting("network/debug/remote_port", int(OS.get_environment("GMORN_REMOTE_PORT")))
	_run.call_deferred()

func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var panel = load("res://addons/gmorn_save/gmorn_save_snapshot_panel.tscn").instantiate()
	add_child(panel)
	for index in 2:
		EditorInterface.play_custom_scene("res://client.tscn")
		var deadline := Time.get_ticks_msec() + 10000
		while not (panel._playing and panel._populated and panel._pending_until == 0):
			if Time.get_ticks_msec() > deadline:
				_finish("FAIL: 実行開始時に一覧が届かない")
				return
			await get_tree().process_frame
		var title := "名前付き%d" % index
		panel.get_node("Create/Name").text = title
		panel.get_node("Create/Save").pressed.emit()
		var button: Button
		deadline = Time.get_ticks_msec() + 10000
		while button == null:
			for row: Node in panel.get_node("Saves").get_children():
				if row.get_node("Name").text == title:
					button = row.get_node("Load")
			if Time.get_ticks_msec() > deadline:
				_finish("FAIL: 実行中の名前付き保存が一覧に出ない: " + panel.get_node("Status").text)
				return
			await get_tree().process_frame
		button.pressed.emit()
		deadline = Time.get_ticks_msec() + 10000
		while not FileAccess.file_exists("res://loaded"):
			if Time.get_ticks_msec() > deadline:
				_finish("FAIL: 一覧のロードがゲームへ届かない")
				return
			await get_tree().process_frame
		while panel._pending_until > 0:
			await get_tree().process_frame
		button.get_parent().get_node("Delete").pressed.emit()
		deadline = Time.get_ticks_msec() + 5000
		while panel._last_names.has(title):
			if Time.get_ticks_msec() > deadline:
				_finish("FAIL: 実行中の削除が一覧に反映されない")
				return
			await get_tree().process_frame
		EditorInterface.stop_playing_scene()
		DirAccess.remove_absolute("res://loaded")
		while EditorInterface.is_playing_scene() or panel._playing:
			await get_tree().process_frame
	_finish("GMORN SAVE REMOTE VERIFY: PASS（開始・保存・ロード・停止・再実行）")

func _finish(result: String) -> void:
	EditorInterface.stop_playing_scene()
	FileAccess.open("res://result.txt", FileAccess.WRITE).store_string(result)
'''
CLIENT = '''extends Node

func _ready() -> void:
	get_node("/root/GMornSave").configure_snapshots(
		func() -> String: return "user://remote.json",
		func() -> Dictionary: return {"money": 321},
		func() -> String:
			var data = JSON.parse_string(FileAccess.get_file_as_string("user://remote.json"))
			if data.money != 321:
				return "内容不一致"
			FileAccess.open("res://loaded", FileAccess.WRITE).store_string("ok")
			return ""
	)
'''


def run():
    with tempfile.TemporaryDirectory(prefix="gmorn-remote-") as temporary:
        work = Path(temporary)
        addon = work / "addons/gmorn_save"
        addon.mkdir(parents=True)
        for source in ADDON.iterdir():
            if source.suffix in (".gd", ".tscn", ".cfg") and not source.name.startswith("gmorn_save_section"):
                shutil.copy2(source, addon / source.name)
        probe = work / "addons/probe"
        probe.mkdir()
        (probe / "plugin.cfg").write_text('[plugin]\nname="Probe"\ndescription="検証"\nauthor=""\nversion="1"\nscript="probe.gd"\n')
        (probe / "probe.gd").write_text(PROBE)
        (work / "client.gd").write_text(CLIENT)
        (work / "client.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://client.gd" id="1"]\n[node name="Client" type="Node"]\nscript=ExtResource("1")\n')
        (work / "project.godot").write_text('''config_version=5
[application]
config/name="GMorn Remote Verify"
[autoload]
GMornSave="*res://addons/gmorn_save/gmorn_save.gd"
[editor]
run/main_run_args="--headless --ignore-error-breaks"
[editor_plugins]
enabled=PackedStringArray("res://addons/gmorn_save/plugin.cfg", "res://addons/probe/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
''')
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            address = f"tcp://127.0.0.1:{listener.getsockname()[1]}"
        # 実際のプロジェクトやユーザーの保存・Editor設定へ触れない。
        environment = dict(os.environ, HOME=str(work / "home"), XDG_DATA_HOME=str(work / "data"), XDG_CONFIG_HOME=str(work / "config"), GMORN_REMOTE_PORT=address.rsplit(":", 1)[1])
        base = [GODOT, "--headless", "--path", str(work)]
        project = work / "project.godot"
        project.write_text(project.read_text().replace("--headless --ignore-error-breaks", f"--headless --ignore-error-breaks --remote-debug {address}"))
        with (work / "editor.log").open("w") as log:
            editor = subprocess.Popen(base + ["--editor", "--debug-server", address], stdout=log, stderr=subprocess.STDOUT, env=environment)
            try:
                result = work / "result.txt"
                deadline = time.monotonic() + 35
                while not result.exists():
                    if editor.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("デバッガ検証が完了しない")
                    time.sleep(0.05)
                outcome = result.read_text()
                if "PASS" not in outcome:
                    raise RuntimeError(outcome)
                print(outcome)
            except Exception:
                print((work / "editor.log").read_text())
                raise
            finally:
                editor.terminate()
                try:
                    editor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    editor.kill()
                    editor.wait()


if __name__ == "__main__":
    run()
