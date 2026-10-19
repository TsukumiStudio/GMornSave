extends Node

## 保存の置き場（`gmorn_save_store.gd`）を作る自動読み込み。置き場は複数あってよい。

const STORE := preload("gmorn_save_store.gd")

func open(path: String) -> RefCounted:
	var store: RefCounted = STORE.new()
	store.path = path
	return store

## `is` で見たいときや、自前で作りたいときに使う。
func store_script() -> GDScript:
	return STORE

const SNAPSHOTS := preload("gmorn_save_snapshots.gd")
var snapshot_path: Callable
var snapshot_data: Callable
var snapshot_loaded: Callable

## `configure_snapshots()` 前は空。
func current_save_path() -> String:
	return String(snapshot_path.call()) if snapshot_path.is_valid() else ""

## ゲーム固有の保存先・現在値・読み直し（タイトル再起動など）を接続する。
func configure_snapshots(path_provider: Callable, data_provider: Callable, loaded: Callable) -> void:
	snapshot_path = path_provider
	snapshot_data = data_provider
	snapshot_loaded = loaded
	if EngineDebugger.is_active():
		EngineDebugger.send_message("gmorn_save:result", [snapshot_request("list")])

func _ready() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture("gmorn_save", _capture)

func _exit_tree() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture("gmorn_save")

func snapshot_request(command: String, value := "") -> Dictionary:
	if not snapshot_path.is_valid() or not snapshot_data.is_valid() or not snapshot_loaded.is_valid():
		return {"ok": false, "message": "ゲーム側の名前付きセーブ接続が未設定です", "names": []}
	var slots := SNAPSHOTS.new()
	slots.save_path = String(snapshot_path.call())
	var error := ""
	match command:
		"save":
			error = slots.create_snapshot(value, snapshot_data.call())
		"load":
			error = slots.restore_snapshot(value)
			if error.is_empty():
				error = String(snapshot_loaded.call())
		"delete":
			error = slots.delete_snapshot(value)
		"erase":
			var store := open(slots.save_path)
			var erased: Error = store.erase()
			error = "" if erased == OK else "削除できませんでした: " + error_string(erased)
			if error.is_empty():
				error = String(snapshot_loaded.call())
		"list":
			pass
		_:
			error = "不明なセーブ操作です"
	return {"ok": error.is_empty(), "message": error if not error.is_empty() else (
		"削除しました" if command == "delete" else "保存しました" if command == "save" else "ロードしました。タイトルから開始します" if command == "load"
		else "今のセーブを削除しました。タイトルから開始します" if command == "erase" else ""),
		"names": slots.names()}

func _capture(message: String, data: Array) -> bool:
	if message != "request" or data.size() != 2 or not data[0] is String or not data[1] is String:
		return false
	EngineDebugger.send_message("gmorn_save:result", [snapshot_request(data[0], data[1])])
	return true
