#!/bin/sh
set -eu
addon_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
godot_bin=${GODOT_BIN:-$(command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/addons/gmorn_save"
cp "$addon_dir"/*.gd "$addon_dir"/*.gd.uid "$addon_dir"/*.tscn "$addon_dir/plugin.cfg" "$work_dir/addons/gmorn_save/"
cp "$addon_dir/verify_cloud.gd" "$work_dir/verify_cloud.gd"
cp "$addon_dir/verify_cloud_http.gd" "$work_dir/verify_cloud_http.gd"
unique_name=${work_dir##*/}
cat > "$work_dir/project.godot" <<PROJECT
config_version=5

[application]

config/name="GMornSaveCloud Verify $unique_name"
config/features=PackedStringArray("4.7")
run/main_scene="res://main.tscn"

[autoload]

GMornSave="*res://addons/gmorn_save/gmorn_save.gd"
GMornSaveCloud="*res://addons/gmorn_save/gmorn_save_cloud.gd"

[editor_plugins]

enabled=PackedStringArray("res://addons/gmorn_save/plugin.cfg")
PROJECT
cat > "$work_dir/main.tscn" <<'SCENE'
[gd_scene format=3]

[node name="Main" type="Node"]
SCENE
run_check() {
	log="$work_dir/godot.log"
	if "$@" > "$log" 2>&1; then status=0; else status=$?; fi
	cat "$log"
	if [ "$status" -ne 0 ] || rg -n 'ERROR:|SCRIPT ERROR:|Failed to load|WARNING:|Assertion failed|VERIFY TIMEOUT' "$log"; then
		return 1
	fi
}
run_check env -u GMORN_SAVE_CLOUD_PROJECT_ID -u GMORN_SAVE_CLOUD_ENDPOINT \
	"$godot_bin" --headless --editor --path "$work_dir" --quit
run_check "$godot_bin" --headless --path "$work_dir" --quit
run_check env -u GMORN_SAVE_CLOUD_PROJECT_ID -u GMORN_SAVE_CLOUD_ENDPOINT \
	"$godot_bin" --headless --path "$work_dir" --script verify_cloud.gd
if [ "${GMORN_SAVE_CLOUD_LIVE_TEST:-0}" = "1" ]; then
	run_check env GMORN_SAVE_CLOUD_TEST_OPT_IN=1 "$godot_bin" --headless --path "$work_dir" --script verify_cloud_http.gd
fi
