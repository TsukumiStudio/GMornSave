@tool
extends EditorPlugin

## GMornSave を組み込むための入口。
##
## 保存はどこからでも作りたいので、自動読み込みに登録する。クラウド保存の送信
## （`GMornSaveCloud`）も同じアドオンに入っている。送り先を設定しなければ何も送らない。

const AUTOLOAD_NAME := "GMornSave"
const CLOUD_AUTOLOAD_NAME := "GMornSaveCloud"
const DEBUGGER := preload("gmorn_save_debugger.gd")
const CLOUD_PANEL := preload("gmorn_save_cloud_panel.tscn")
## プロジェクト設定の画面から変えられるように、型と既定値を登録する。
const CLOUD_MIN_INTERVAL_SETTING := "gmorn_save_cloud/min_interval_seconds"
var debugger: EditorDebuggerPlugin
var cloud_panel: Control
## このプラグインが自動読み込みを足したときだけ、外すときにも消す（手で書いた登録は残す）。
var added_cloud_autoload := false

## 置き場所を決め打ちにしない。submodule で好きな名前の場所へ入れられるように、
## 自分の居場所から辿る。
func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_save.gd")

func _enter_tree() -> void:
	debugger = DEBUGGER.new()
	DEBUGGER.current = debugger
	add_debugger_plugin(debugger)
	# 既に登録済みなら足さない。毎回足すとエディタの起動ごとに「自動読み込みを追加」の
	# 履歴が（アドオンの数だけ）並ぶ。project.godot に書いてあれば、それで動く。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())
	if not ProjectSettings.has_setting("autoload/" + CLOUD_AUTOLOAD_NAME):
		add_autoload_singleton(CLOUD_AUTOLOAD_NAME, _autoload_path().get_base_dir().path_join("gmorn_save_cloud.gd"))
		added_cloud_autoload = true
	# セーブの送信の最短間隔（秒）。0 なら保存のたびに（2秒の静かな間の後で）送る。
	if not ProjectSettings.has_setting(CLOUD_MIN_INTERVAL_SETTING):
		ProjectSettings.set_setting(CLOUD_MIN_INTERVAL_SETTING, 0.0)
	ProjectSettings.set_initial_value(CLOUD_MIN_INTERVAL_SETTING, 0.0)
	ProjectSettings.add_property_info({"name": CLOUD_MIN_INTERVAL_SETTING, "type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE, "hint_string": "0,600,1,or_greater,suffix:s"})
	ProjectSettings.set_as_basic(CLOUD_MIN_INTERVAL_SETTING, true)
	cloud_panel = CLOUD_PANEL.instantiate()
	if ProjectSettings.has_setting("gmorn_save_cloud/preview_path"):
		cloud_panel.save_path = String(ProjectSettings.get_setting("gmorn_save_cloud/preview_path"))
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, cloud_panel)

func _exit_tree() -> void:
	DEBUGGER.current = null
	if is_instance_valid(debugger):
		remove_debugger_plugin(debugger)
	if is_instance_valid(cloud_panel):
		remove_control_from_docks(cloud_panel)
		cloud_panel.queue_free()
	remove_autoload_singleton(AUTOLOAD_NAME)
	if added_cloud_autoload:
		remove_autoload_singleton(CLOUD_AUTOLOAD_NAME)
