@tool
extends RefCounted

## 通常保存とは別に、名前付きのJSONを保持する。
const STORE := preload("gmorn_save_store.gd")
var save_path := "user://save.json"

func directory() -> String:
	return save_path + ".snapshots"

func names() -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory()):
		return result
	for file: String in DirAccess.get_files_at(directory()):
		if file.ends_with(".json"):
			result.append(file.trim_suffix(".json"))
	result.sort()
	return result

func valid_name(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges() and value.length() <= 80 \
		and value.is_valid_filename() and not value.begins_with(".") \
		and not value.ends_with(".") and not value.contains("\n") and not value.contains("\r")

func create_snapshot(value: String, data: Variant = null) -> String:
	if not valid_name(value):
		return "名前を1〜80文字で入力してください（パス・前後の空白・使用できない文字を除く）"
	var target := directory().path_join(value + ".json")
	if FileAccess.file_exists(target):
		return "同じ名前が存在します。別の名前を付けてください"
	var source := STORE.new()
	source.path = save_path
	if data == null:
		if not source.is_readable(save_path):
			return "保存元のJSONが存在しないか、読み込めません"
		data = source.load_data({})
	if not data is Dictionary:
		return "保存データがJSONの辞書ではありません"
	var snapshot := STORE.new()
	snapshot.path = target
	return "" if snapshot.save(data) else "名前付きセーブを保存できませんでした"

func restore_snapshot(value: String) -> String:
	if not valid_name(value):
		return "セーブ名が不正です"
	var snapshot := STORE.new()
	snapshot.path = directory().path_join(value + ".json")
	# 指定したJSON自身が壊れていたら拒否し、現在の保存を維持する。
	if not snapshot.is_readable(snapshot.path):
		return "選択したJSONが存在しないか、読み込めません"
	var current := STORE.new()
	current.path = save_path
	return "" if current.save(snapshot.load_data({})) else "現在のセーブを置き換えられませんでした"

func delete_snapshot(value: String) -> String:
	if not valid_name(value):
		return "セーブ名が不正です"
	var snapshot := STORE.new()
	snapshot.path = directory().path_join(value + ".json")
	var error: Error = snapshot.erase()
	return "" if error == OK else "削除できませんでした: " + error_string(error)
