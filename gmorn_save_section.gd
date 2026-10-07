@tool
extends "../gmorn_debug_menu/gmorn_debug_menu_section.gd"

const PANEL := preload("gmorn_save_section.tscn")

# OSのファイル管理（macOSはFinder、WindowsはExplorer）で開く。テストでは外部アプリを起動せず、要求したパスを検証する。
var show_in_file_manager: Callable = OS.shell_show_in_file_manager
const STORE := preload("gmorn_save_store.gd")

## このプロジェクトの削除対象。ディレクトリ単位の削除は行わない。
@export var save_path := "user://save.json"
## 旧版の自動取り込みを止める印が必要なプロジェクトのみ指定する。
@export var migration_marker_path := ""

func create_control() -> Control:
	var panel := PANEL.instantiate()
	panel.get_node("Snapshots").save_path = save_path
	var opener := panel.get_node("Open")
	opener.action_text = "セーブデータの場所を開く"
	opener.action = func() -> String:
		# セーブがあればそのファイルを選んだ状態で、まだ無ければ置き場のフォルダを開く。
		var target := save_path
		if not FileAccess.file_exists(save_path):
			target = save_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
				return "セーブデータの置き場がまだありません"
		var error: Error = show_in_file_manager.call(ProjectSettings.globalize_path(target))
		return "セーブデータの場所を開きました" if error == OK else "開けませんでした: " + error_string(error)
	var control := panel.get_node("Delete")
	control.action_text = "セーブデータの削除"
	control.requires_confirmation = true
	control.action = func() -> String:
		var error := erase_save()
		return "セーブデータを削除しました" if error == OK else "削除できませんでした: " + error_string(error)
	return panel

func erase_save() -> Error:
	if not save_path.begins_with("user://") or save_path.get_file().is_empty():
		return ERR_INVALID_PARAMETER
	# 先に印を書く。作れない場合は既存セーブを消さない。
	if not migration_marker_path.is_empty():
		if not migration_marker_path.begins_with("user://"):
			return ERR_INVALID_PARAMETER
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(migration_marker_path.get_base_dir()))
		if error != OK:
			return error
		var marker := FileAccess.open(migration_marker_path, FileAccess.WRITE)
		if marker == null:
			return FileAccess.get_open_error()
		marker.close()
	var store := STORE.new()
	store.path = save_path
	return store.erase()
