@tool
extends EditorPlugin

## GMornSave を組み込むための入口。
##
## 保存はどこからでも作りたいので、自動読み込みに登録する。

const AUTOLOAD_NAME := "GMornSave"

## 置き場所を決め打ちにしない。submodule で好きな名前の場所へ入れられるように、
## 自分の居場所から辿る。
func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_save.gd")

func _enter_tree() -> void:
	# 既に登録済みなら足さない。毎回足すとエディタの起動ごとに「自動読み込みを追加」の
	# 履歴が（アドオンの数だけ）並ぶ。project.godot に書いてあれば、それで動く。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
