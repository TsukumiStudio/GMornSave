extends VBoxContainer

## ゲームの中（デバッグ板など）に置く、Editorの欄と同じ並びのセーブ欄。
##
## 今のセーブ（最終更新時刻） [削除][開く]
## セーブデータ一覧 [一覧を更新] / セーブ名 [保存] / 各行 [削除][使う]
##
## 保存先・現在値・読み直しは `GMornSave.configure_snapshots()` で作品が接続したものを使う。
## Editorを介さず、その場で処理する。Editor専用の型に触れないので、書き出したゲームでも動く
## （Editorの欄 `gmorn_save_snapshot_panel` は EditorDebuggerPlugin を使うため、ここでは使わない）。

const ROW := preload("gmorn_save_snapshot_row.tscn")
const CONFIRM_MSEC := 3000
## OSのファイル管理（macOSはFinder、WindowsはExplorer）で開く。検証では差し替える。
var show_in_file_manager: Callable = OS.shell_show_in_file_manager
var service: Node
var _armed_until := 0

func _ready() -> void:
	service = get_node_or_null("/root/GMornSave")
	%Delete.pressed.connect(_delete)
	%Refresh.pressed.connect(_request.bind("list", ""))
	%Save.pressed.connect(func() -> void: _request("save", %Name.text))
	%Name.text_submitted.connect(func(value: String) -> void: _request("save", value))
	%Open.pressed.connect(_open)
	%RefreshTimer.timeout.connect(refresh)
	%Status.hide()
	refresh()
	_request("list", "")

func _process(_delta: float) -> void:
	if _armed_until > 0 and Time.get_ticks_msec() > _armed_until:
		_armed_until = 0
		%Delete.text = "削除"

## 「今のセーブ（最終更新時刻）」を今のファイルに合わせる。手元の時刻で出す。
func refresh() -> void:
	var path := _path()
	%FileName.tooltip_text = path
	%FileName.text = "今のセーブ（%s）" % _updated_text(path)

func _path() -> String:
	return service.current_save_path() if service != null else ""

func _updated_text(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return "まだありません"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(FileAccess.get_modified_time(path) + bias)
	return "%04d/%02d/%02d %02d:%02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute, date.second]

## 押し間違えで進行を消さないよう、3秒以内の二度押しで消す。
func _delete() -> void:
	if service == null:
		return
	if _armed_until == 0:
		_armed_until = Time.get_ticks_msec() + CONFIRM_MSEC
		%Delete.text = "もう一度押して削除"
		_show_status("今のセーブを消します。3秒以内にもう一度押してください。")
		return
	_armed_until = 0
	%Delete.text = "削除"
	_show_status(String(service.snapshot_request("erase").get("message", "")))
	refresh()

func _open() -> void:
	var path := _path()
	var target := path
	if not FileAccess.file_exists(path):
		target = path.get_base_dir()
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
			_show_status("セーブデータの置き場がまだありません")
			return
	var error: Error = show_in_file_manager.call(ProjectSettings.globalize_path(target))
	_show_status("セーブデータの場所を開きました" if error == OK else "この環境では開けません: " + error_string(error))

## 名前付きセーブの保存・使う・削除・一覧。結果の一覧で並びを作り直す。
func _request(command: String, value: String) -> void:
	if service == null:
		_show_status("GMornSave が見つかりません")
		return
	var result: Dictionary = service.snapshot_request(command, value)
	if command != "list":
		_show_status(String(result.get("message", "")))
	_rebuild(PackedStringArray(result.get("names", [])))
	refresh()

func _rebuild(names: PackedStringArray) -> void:
	for child: Node in %Saves.get_children():
		%Saves.remove_child(child)
		child.queue_free()
	for value: String in names:
		var row := ROW.instantiate()
		var label: Label = row.get_node("Name")
		label.text = value
		label.tooltip_text = value
		row.get_node("Delete").pressed.connect(_request.bind("delete", value))
		var use: Button = row.get_node("Load")
		use.tooltip_text = "このセーブを今のセーブにしてタイトルへ戻ります"
		use.pressed.connect(_request.bind("load", value))
		%Saves.add_child(row)

func _show_status(message: String) -> void:
	%Status.text = message
	%Status.visible = not message.is_empty()
