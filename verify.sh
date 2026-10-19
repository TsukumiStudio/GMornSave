#!/bin/sh
# この部品だけをヘッドレスで確かめる。
#
# リポジトリ直下に project.godot は置けない。submodule として取り込まれた先に
# project.godot があると、Godot がそこを別プロジェクトと見なして書き出しから外す。
# 代わりに一時の最小プロジェクトへ写して回す。
set -eu

addon_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
godot_bin=${GODOT_BIN:-$(command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/addons/gmorn_save"
cp "$addon_dir"/*.gd "$addon_dir"/plugin.cfg "$work_dir/addons/gmorn_save/"
cp "$addon_dir/verify.gd" "$work_dir/verify.gd"

cat > "$work_dir/project.godot" <<'PROJECT'
config_version=5

[application]

config/name="GMornSave Verify"
config/features=PackedStringArray("4.7")
PROJECT

"$godot_bin" --headless --path "$work_dir" --script verify.gd
