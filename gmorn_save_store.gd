@tool
extends RefCounted

## 書きかけで壊れない保存。1つの置き場ぶんを受け持つ。
##
## 本体へ直接書かない。書いている途中で落ちると切れたファイルが残り、次の保存が
## それを上書きして手で直す機会も無くなる。`.tmp` へ書いて読み直し、本体を `.bak` へ
## 写してから差し替える。読むときは本体 → 控え → 既定値の順。

## どこから戻したかで呼ぶ側の振る舞いが変わる。
enum Outcome {
	LOADED,
	## 呼ぶ側は書き戻して本体を作り直す。
	RESTORED_FROM_BACKUP,
	## 旧版からの引き継ぎを試すならここだけ。
	MISSING,
	## あるのに読めない。引き継ぎは試さない（本体が消えただけの人の進行を上書きする）。
	UNREADABLE,
}

signal restored_from_backup(backup_path: String)
## 本体は前回の内容のまま残っている。
signal save_failed(path: String)

var path := ""
## false で書き出しだけ止める。読み取りは止めない（読めるかを見る検証を書かずに回せる）。
var enabled := true
var backup_suffix := ".bak"
var temporary_suffix := ".tmp"

var last_outcome: Outcome = Outcome.MISSING

func backup_path() -> String:
	return path + backup_suffix

func temporary_path() -> String:
	return path + temporary_suffix

## 既定値の上に読めた内容を重ねて返す。`defaults` は毎回作り直したものを渡す。
## 使い回すと、返した辞書へ書き込んだ内容が次の呼び出しの既定値になる。
func load_data(defaults: Dictionary) -> Dictionary:
	var data := defaults.duplicate(true)
	if _apply_file(path, data):
		last_outcome = Outcome.LOADED
		_fill_missing(data, defaults)
		return data
	# 本体が無い側でも控えを見る。差し替えの途中で落ちる、同期の都合で本体だけ消える、
	# といった形がある。
	if _apply_file(backup_path(), data):
		last_outcome = Outcome.RESTORED_FROM_BACKUP
		_fill_missing(data, defaults)
		push_warning("保存を読めなかったため控えから戻しました: %s" % backup_path())
		restored_from_backup.emit(backup_path())
		return data
	# 無いのか読めないのかを区別する。呼ぶ側は無いときだけ旧版からの引き継ぎを試す。
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup_path()):
		last_outcome = Outcome.MISSING
	else:
		last_outcome = Outcome.UNREADABLE
		push_warning("保存を読めなかったため既定値で始めます: %s" % path)
	_fill_missing(data, defaults)
	return data

## 失敗しても本体には触らない。
func save(data: Dictionary) -> bool:
	if not enabled:
		return false
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir()))
	var temporary := temporary_path()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		save_failed.emit(path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	# 容量切れなどで書けたつもりで中身が欠けることがある。差し替える前に読み直す。
	if write_error != OK or not is_readable(temporary):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		push_warning("保存を書き出せなかったため前回の内容を残しました: %s" % path)
		save_failed.emit(path)
		return false
	# 壊れた本体で控えを上書きすると、戻す先が無くなる。
	var had_previous := FileAccess.file_exists(path) and is_readable(path)
	if had_previous:
		var backup_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(backup_path()))
		if backup_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			save_failed.emit(path)
			return false
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path))
	if replace_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		save_failed.emit(path)
		return false
	if not is_readable(path):
		if had_previous:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path()), ProjectSettings.globalize_path(path))
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		save_failed.emit(path)
		return false
	return true

## 控えと書きかけも消す。本体だけ消すと、次に読んだときに控えから戻ってくる。
func erase() -> Error:
	if not enabled:
		return OK
	var error := OK
	if FileAccess.file_exists(path):
		error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for extra: String in [backup_path(), temporary_path()]:
		if FileAccess.file_exists(extra):
			var extra_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(extra))
			if error == OK:
				error = extra_error
	return error

func is_readable(target: String) -> bool:
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	return json.parse(file.get_as_text()) == OK and json.data is Dictionary

## `JSON.parse_string` は使わない。失敗するとエンジンの ERROR が出て、壊れた保存が
## 見つかっただけで異常扱いになる。
func _apply_file(target: String, data: Dictionary) -> bool:
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return false
	for key: Variant in (json.data as Dictionary):
		data[key] = (json.data as Dictionary)[key]
	return true

## 既定値にしか無い項目だけ埋める。上書きはしない。読めた内容のほうが新しい。
static func _fill_missing(data: Dictionary, defaults: Dictionary) -> void:
	for key: Variant in defaults:
		if not data.has(key):
			data[key] = defaults[key]
