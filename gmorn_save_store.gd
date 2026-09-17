@tool
extends RefCounted

## 壊れない保存。1つの置き場ぶんを受け持つ。
##
## 本体へ直接書くと、書いている途中で落ちた場合にそこで切れたファイルが残る。
## 実測では、正常な保存を6割の位置で切っただけで、日数も所持金も強化もすべて
## 消えて初期値に戻った。さらに次の保存がその壊れたファイルを上書きするため、
## 手で直す機会も無くなる。
##
## 書くときは3段にする。
##
##   1. 別名（`.tmp`）へ書く
##   2. 読み直せることを確かめる（容量切れなどで、書けたつもりで欠けることがある）
##   3. いまの本体を控え（`.bak`）へ写してから、別名を本体へ差し替える
##
## 読むときは3段で戻す。
##
##   1. 本体が読めれば、それが最新
##   2. 読めなければ控えから戻す。控えは前回きちんと読めた内容なので、
##      失うのは直前の1回ぶんだけで済む
##   3. どちらも無ければ、既定値で始める
##
## 中身が何かはこの部品では知らない。既定値の辞書を渡してもらい、その上に
## 読んだ内容を重ねる。項目が増えたときは既定値のほうから埋まるので、
## 古い保存でもそのまま読める。
##
## 使い方は README.md を参照。

## 読んだ結果。どこから戻したかで、呼ぶ側の振る舞いを変えられる。
enum Outcome {
	## 本体から読めた。いつもの経路。
	LOADED,
	## 本体が駄目で控えから戻した。呼ぶ側は書き戻しておくとよい。
	RESTORED_FROM_BACKUP,
	## 本体も控eも無い。初めて遊ぶとき、または消した後。
	MISSING,
	## どちらもあるのに読めない。既定値で始めるしかない。
	UNREADABLE,
}

## 控えから戻したときに流れる。
signal restored_from_backup(backup_path: String)
## 書き出しに失敗したときに流れる。本体は前回の内容のまま残っている。
signal save_failed(path: String)

## 本体の置き場。`user://save.json` のような形で渡す。
var path := ""
## 書き出しを行うか。検証で本物の置き場を触りたくないときに false にする。
##
## 読み取りは止めない。読めるかどうかを見る検証は、書かずに回せる。
var enabled := true
## 控えの後ろに付ける文字。
var backup_suffix := ".bak"
## 書きかけの後ろに付ける文字。
var temporary_suffix := ".tmp"

## 直近の `load()` がどう終わったか。
var last_outcome: Outcome = Outcome.MISSING

func backup_path() -> String:
	return path + backup_suffix

func temporary_path() -> String:
	return path + temporary_suffix

## 読み込む。既定値の上に、読めた内容を重ねて返す。
##
## `defaults` は毎回作り直したものを渡す。使い回すと、返した辞書へ書き込んだ
## 内容が次の呼び出しの既定値になる。
func load_data(defaults: Dictionary) -> Dictionary:
	var data := defaults.duplicate(true)
	# 本体が読めれば、それが最新。
	if _apply_file(path, data):
		last_outcome = Outcome.LOADED
		_fill_missing(data, defaults)
		return data
	# 本体が壊れているときも、丸ごと消えているときも、控えから戻す。差し替えの
	# 途中で落ちる、同期の都合で本体だけ消える、といった形は本体が無い側で起きる。
	if _apply_file(backup_path(), data):
		last_outcome = Outcome.RESTORED_FROM_BACKUP
		_fill_missing(data, defaults)
		push_warning("保存を読めなかったため控えから戻しました: %s" % backup_path())
		restored_from_backup.emit(backup_path())
		return data
	# どちらも無いのか、あるのに読めないのかを区別する。呼ぶ側は、無いときだけ
	# 旧版からの引き継ぎを試したい。読めないときに引き継ぐと、本体が消えただけの
	# 人の進行を古い内容で上書きしてしまう。
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup_path()):
		last_outcome = Outcome.MISSING
	else:
		last_outcome = Outcome.UNREADABLE
		push_warning("保存を読めなかったため既定値で始めます: %s" % path)
	_fill_missing(data, defaults)
	return data

## 書き出す。成功したら true。
##
## 失敗しても本体には触らない。前回の内容がそのまま残る。
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
	# 書けたつもりで中身が欠けていることがある（容量切れなど）。差し替える前に
	# 読み直して確かめる。駄目なら本体には触らない。
	if write_error != OK or not is_readable(temporary):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		push_warning("保存を書き出せなかったため前回の内容を残しました: %s" % path)
		save_failed.emit(path)
		return false
	# 控えは「読めた本体」だけから作る。壊れた本体で控えを上書きすると、
	# 戻す先が無くなる。
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

## 消す。控えと書きかけも一緒に消す。
##
## 本体だけ消すと、次に読んだときに控えから戻ってくる。消したはずの進行が
## 戻ってくるのは、消せていないのと同じである。
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

## その置き場が読める形かどうか。
func is_readable(target: String) -> bool:
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	return json.parse(file.get_as_text()) == OK and json.data is Dictionary

## 保存ファイルを読んで `data` へ重ねる。読めなければ何も変えずに false を返す。
##
## `JSON.parse_string` は失敗するとエンジン側がエラーを吐く。壊れた保存が
## 見つかっただけで異常として扱われると、原因を追うときの妨げになる。
## `JSON.new().parse()` なら受け止められる形で読める。
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

## 既定値にしか無い項目を埋める。項目を増やした後でも古い保存が読めるようにする。
##
## 上書きはしない。読めた内容のほうが新しい。
static func _fill_missing(data: Dictionary, defaults: Dictionary) -> void:
	for key: Variant in defaults:
		if not data.has(key):
			data[key] = defaults[key]
