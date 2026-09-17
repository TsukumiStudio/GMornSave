extends SceneTree

## 壊れ方ごとに、どこまで守れるかを確かめる。
##
## 通る道だけを見ても意味がない。ここで見たいのは「壊したときに何が残るか」で
## ある。書きかけで落ちた、中身が切れた、本体だけ消えた、の3つを実際に作る。

class UnreadableFinalStore extends "res://addons/gmorn_save/gmorn_save_store.gd":
	var reject_final := false
	func is_readable(target: String) -> bool:
		if reject_final and target == path and not FileAccess.file_exists(temporary_path()):
			return false
		return super.is_readable(target)

const SAVE_PATH := "res://addons/gmorn_save/gmorn_save.gd"
const PROBE_DIRECTORY := "user://gmorn_save_verify"
const PROBE_PATH := PROBE_DIRECTORY + "/save.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service_script: GDScript = load(SAVE_PATH)
	var service: Node = service_script.new()
	root.add_child(service)
	await process_frame

	_clean()
	var store: RefCounted = service.open(PROBE_PATH)

	# 何も無いところから始めると、既定値がそのまま返る。
	var loaded: Dictionary = store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.MISSING,
		"初回が %d" % store.last_outcome)
	assert(int(loaded["money"]) == 0, "初回の所持金が %s" % loaded["money"])

	# 書いて読み直すと同じ内容が返る。
	loaded["money"] = 123456
	loaded["day"] = 17
	assert(store.save(loaded), "書き出せない")
	var reloaded: Dictionary = store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.LOADED, "本体から読めていない")
	assert(int(reloaded["money"]) == 123456, "所持金が %s" % reloaded["money"])
	assert(int(reloaded["day"]) == 17, "日数が %s" % reloaded["day"])

	# 項目を増やしても古い保存が読める。既定値のほうから埋まる。
	var extended := _defaults()
	extended["new_thing"] = "既定"
	var merged: Dictionary = store.load_data(extended)
	assert(String(merged["new_thing"]) == "既定", "増やした項目が埋まらない")
	assert(int(merged["money"]) == 123456, "増やしたら前の内容が消えた")

	# 既定値の辞書は汚さない。使い回されると次回の既定値が変わってしまう。
	assert(int(extended["money"]) == 0, "渡した既定値が書き換わっている")

	# 2回目の書き出しで控えができる。
	merged["money"] = 999
	assert(store.save(merged), "2回目を書き出せない")
	assert(FileAccess.file_exists(store.backup_path()), "控えができていない")

	# 本体を途中で切る。書いている最中に落ちた形。控えから戻れなければならない。
	var whole := FileAccess.get_file_as_string(PROBE_PATH)
	var broken := FileAccess.open(PROBE_PATH, FileAccess.WRITE)
	broken.store_string(whole.substr(0, int(whole.length() * 0.6)))
	broken.close()
	assert(not store.is_readable(PROBE_PATH), "切ったのに読めると言っている")
	var restored: Dictionary = store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.RESTORED_FROM_BACKUP,
		"控えから戻していない: %d" % store.last_outcome)
	# 控えは1つ前の内容。失うのは直前の1回ぶんだけ。
	assert(int(restored["money"]) == 123456,
		"控えの中身が %s" % restored["money"])

	# 壊れた本体で控えを上書きしない。上書きすると戻す先が無くなる。
	var backup_before := FileAccess.get_file_as_string(store.backup_path())
	store.save(restored)
	var backup_after := FileAccess.get_file_as_string(store.backup_path())
	assert(backup_before == backup_after or store.is_readable(store.backup_path()),
		"控えが読めない形になった")

	# 本体だけ消えても控えから戻る。同期の都合でこの形になることがある。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE_PATH))
	var from_backup: Dictionary = store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.RESTORED_FROM_BACKUP,
		"本体が消えたときに控えを見ていない")
	assert(int(from_backup["money"]) > 0, "控えから戻せていない")

	# 本体も控えも壊れていたら、無いのではなく読めないと言う。呼ぶ側は
	# 「無いとき」だけ旧版からの引き継ぎを試したい。読めないときに引き継ぐと、
	# 本体が消えただけの人の進行を古い内容で上書きしてしまう。
	for target: String in [PROBE_PATH, store.backup_path()]:
		var junk := FileAccess.open(target, FileAccess.WRITE)
		junk.store_string("これはJSONではない")
		junk.close()
	store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.UNREADABLE,
		"壊れているのに %d と言っている" % store.last_outcome)

	# 消すと控えも書きかけも消える。本体だけ消すと、次に読んだときに戻ってくる。
	store.save(_defaults())
	assert(store.erase() == OK, "消せない")
	assert(not FileAccess.file_exists(PROBE_PATH), "本体が残っている")
	assert(not FileAccess.file_exists(store.backup_path()), "控えが残っている")
	assert(not FileAccess.file_exists(store.temporary_path()), "書きかけが残っている")

	# 書き出しを切ってあれば、置き場に何も作らない。
	store.enabled = false
	assert(not store.save(_defaults()), "切ってあるのに書き出した")
	assert(not FileAccess.file_exists(PROBE_PATH), "切ってあるのにファイルができた")
	# 読み取りは止めない。読めるかどうかを見る検証は、書かずに回せる。
	store.load_data(_defaults())
	assert(store.last_outcome == store.Outcome.MISSING, "読み取りまで止まっている")

	_clean()
	print("結果=%d 控え=%s" % [store.last_outcome, store.backup_path()])
	var final_store := UnreadableFinalStore.new()
	final_store.path = PROBE_PATH
	assert(final_store.save({"money": 314}))
	final_store.reject_final = true
	assert(not final_store.save({"money": 999}), "差替え後の破損を成功扱いした")
	assert(JSON.parse_string(FileAccess.get_file_as_string(PROBE_PATH)).money == 314,
		"差替え後の検査失敗で前の保存を失った")
	_clean()
	var slots = load("res://addons/gmorn_save/gmorn_save_snapshots.gd").new()
	slots.save_path = PROBE_PATH
	assert(slots.create_snapshot("確認用", {"money": 42, "day": 8}).is_empty())
	assert(slots.names() == PackedStringArray(["確認用"]))
	assert(not slots.create_snapshot("確認用", {"money": 0}).is_empty())
	assert(not slots.create_snapshot("../別の場所", {}).is_empty())
	assert(slots.create_snapshot("削除用", {"money": 5}).is_empty())
	assert(slots.delete_snapshot("削除用").is_empty())
	assert(slots.names() == PackedStringArray(["確認用"]))
	assert(not slots.delete_snapshot("../save").is_empty())
	assert(slots.restore_snapshot("確認用").is_empty())
	assert(store.load_data({}).money == 42)
	FileAccess.open(slots.directory().path_join("破損.json"), FileAccess.WRITE).store_string("[]")
	assert(not slots.restore_snapshot("破損").is_empty())
	assert(store.load_data({}).money == 42)
	for file: String in DirAccess.get_files_at(slots.directory()):
		DirAccess.remove_absolute(slots.directory().path_join(file))
	DirAccess.remove_absolute(slots.directory())
	_clean()
	print("GMORN SAVE VERIFY: PASS")
	quit(0)

static func _defaults() -> Dictionary:
	return {
		"money": 0,
		"day": 1,
		"upgrades": [0, 0, 0],
	}

func _clean() -> void:
	for name: String in ["save.json", "save.json.bak", "save.json.tmp"]:
		var target := PROBE_DIRECTORY.path_join(name)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_DIRECTORY))
