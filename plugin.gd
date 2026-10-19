@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GMornSave"
const CLOUD_AUTOLOAD_NAME := "GMornSaveCloud"
const DEBUGGER := preload("gmorn_save_debugger.gd")
const CLOUD_MIN_INTERVAL_SETTING := "gmorn_save_cloud/min_interval_seconds"
var debugger: EditorDebuggerPlugin
## 手で書いた登録は外すときに消さない。
var added_cloud_autoload := false

## 置き場所を決め打ちにしない。submodule で任意の場所へ入れられるよう自分の居場所から辿る。
func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_save.gd")

func _enter_tree() -> void:
	debugger = DEBUGGER.new()
	DEBUGGER.current = debugger
	add_debugger_plugin(debugger)
	# 登録済みなら足さない。毎回足すとエディタ起動ごとに「自動読み込みを追加」の履歴が並ぶ。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())
	if not ProjectSettings.has_setting("autoload/" + CLOUD_AUTOLOAD_NAME):
		add_autoload_singleton(CLOUD_AUTOLOAD_NAME, _autoload_path().get_base_dir().path_join("gmorn_save_cloud.gd"))
		added_cloud_autoload = true
	if not ProjectSettings.has_setting(CLOUD_MIN_INTERVAL_SETTING):
		ProjectSettings.set_setting(CLOUD_MIN_INTERVAL_SETTING, 0.0)
	ProjectSettings.set_initial_value(CLOUD_MIN_INTERVAL_SETTING, 0.0)
	ProjectSettings.add_property_info({"name": CLOUD_MIN_INTERVAL_SETTING, "type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE, "hint_string": "0,600,1,or_greater,suffix:s"})
	ProjectSettings.set_as_basic(CLOUD_MIN_INTERVAL_SETTING, true)

func _exit_tree() -> void:
	DEBUGGER.current = null
	if is_instance_valid(debugger):
		remove_debugger_plugin(debugger)
	remove_autoload_singleton(AUTOLOAD_NAME)
	if added_cloud_autoload:
		remove_autoload_singleton(CLOUD_AUTOLOAD_NAME)
