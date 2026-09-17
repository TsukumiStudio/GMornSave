extends Node

## 保存の置き場を作る入口。
##
## 中身は `gmorn_save_store.gd` にある。ここは「どこからでも作れる」ようにする
## ためだけの薄い層で、状態は持たない。
##
## 置き場は複数あってよい。進行と設定を別のファイルに分ける、利用者ごとに
## 分ける、といったときに1つずつ作る。
##
##   var progress := GMornSave.open("user://progress.json")
##   var config := GMornSave.open("user://config.json")
##
## 使い方は README.md を参照。

const STORE := preload("gmorn_save_store.gd")

## 置き場を1つ作る。
func open(path: String) -> RefCounted:
	var store: RefCounted = STORE.new()
	store.path = path
	return store

## 置き場の型。`is` で見たいときや、自前で作りたいときに使う。
func store_script() -> GDScript:
	return STORE

const SNAPSHOTS := preload("gmorn_save_snapshots.gd")
var snapshot_path: Callable
var snapshot_data: Callable
var snapshot_loaded: Callable

## ゲーム固有の保存先・現在値・タイトル再起動処理を接続する。
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
		"list":
			pass
		_:
			error = "不明なセーブ操作です"
	return {"ok": error.is_empty(), "message": error if not error.is_empty() else (
		"削除しました" if command == "delete" else "保存しました" if command == "save" else "ロードしました。タイトルから開始します" if command == "load" else ""),
		"names": slots.names()}

func _capture(message: String, data: Array) -> bool:
	if message != "request" or data.size() != 2 or not data[0] is String or not data[1] is String:
		return false
	EngineDebugger.send_message("gmorn_save:result", [snapshot_request(data[0], data[1])])
	return true
