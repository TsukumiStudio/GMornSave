extends Node

## 保存の置き場を作る入口。
##
## 中身は `gmorn_save_store.gd` にある。ここは「どこからでも作れる」ようにする
## ためだけの薄い層で、状態は持たない。
##
## 置き場は複数あってよい。進行と設定を別のファイルに分ける、利用者ごとに
## 分ける、といったときに1つずつ作る。
##
##   var progress := GMornSave.open("user://progress.json")
##   var config := GMornSave.open("user://config.json")
##
## 使い方は README.md を参照。

const STORE := preload("gmorn_save_store.gd")

## 置き場を1つ作る。
func open(path: String) -> RefCounted:
	var store: RefCounted = STORE.new()
	store.path = path
	return store

## 置き場の型。`is` で見たいときや、自前で作りたいときに使う。
func store_script() -> GDScript:
	return STORE
