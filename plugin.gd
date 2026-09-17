@tool
extends EditorPlugin

## GMornSave を組み込むための入口。
##
## 保存はどこからでも作りたいので、自動読み込みに登録する。

const AUTOLOAD_NAME := "GMornSave"
const DEBUGGER := preload("gmorn_save_debugger.gd")
var debugger: EditorDebuggerPlugin

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

func _exit_tree() -> void:
	DEBUGGER.current = null
	if is_instance_valid(debugger):
		remove_debugger_plugin(debugger)
	remove_autoload_singleton(AUTOLOAD_NAME)
