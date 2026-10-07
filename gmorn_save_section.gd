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
	panel.get_node("%FileName").tooltip_text = save_path
	var opener := panel.get_node("%Open")
	opener.action_text = "開く"
	opener.action = func() -> String:
		# セーブがあればそのファイルを選んだ状態で、まだ無ければ置き場のフォルダを開く。
		var target := save_path
		if not FileAccess.file_exists(save_path):
			target = save_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
				return "セーブデータの置き場がまだありません"
		var error: Error = show_in_file_manager.call(ProjectSettings.globalize_path(target))
		return "セーブデータの場所を開きました" if error == OK else "開けませんでした: " + error_string(error)
	var control := panel.get_node("%Delete")
	control.action_text = "削除"
	control.requires_confirmation = true
	control.action = func() -> String:
		var error := erase_save()
		_refresh_updated(panel)
		return "セーブデータを削除しました" if error == OK else "削除できませんでした: " + error_string(error)
	# 実行中のゲームが保存しても追いつくよう、毎秒見直す。
	panel.get_node("%RefreshTimer").timeout.connect(_refresh_updated.bind(panel))
	_refresh_updated(panel)
	return panel

## 「ファイル名（最終更新時刻）」を今のファイルに合わせる。手元の時刻で出す。
func _refresh_updated(panel: Control) -> void:
	var label := panel.get_node("%FileName") as Label
	label.text = "%s（%s）" % [save_path.get_file(), updated_text()]

func updated_text() -> String:
	if not FileAccess.file_exists(save_path):
		return "まだありません"
	var modified := FileAccess.get_modified_time(save_path)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(modified + bias)
	return "%04d/%02d/%02d %02d:%02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute, date.second]

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
