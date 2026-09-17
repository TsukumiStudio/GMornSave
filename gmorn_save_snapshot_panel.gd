@tool
extends VBoxContainer

const SNAPSHOTS := preload("gmorn_save_snapshots.gd")
const DEBUGGER := preload("gmorn_save_debugger.gd")
var save_path := "user://save.json"
var is_playing: Callable = func() -> bool:
	return Engine.is_editor_hint() and EditorInterface.is_playing_scene()
var _bridge: EditorDebuggerPlugin
var _playing := false
var _pending_until := 0
var _last_names := PackedStringArray()
var _populated := false

func _ready() -> void:
	$Save.pressed.connect(func() -> void: request("save", $Name.text))
	$Name.text_submitted.connect(func(value: String) -> void: request("save", value))
	$Refresh.pressed.connect(func() -> void: request("list"))
	_process(0.0)
	if not _playing:
		request("list")

func _process(_delta: float) -> void:
	if _bridge != DEBUGGER.current:
		if is_instance_valid(_bridge):
			_bridge.result_received.disconnect(_receive)
		_bridge = DEBUGGER.current
		if is_instance_valid(_bridge):
			_bridge.result_received.connect(_receive)
	var playing := bool(is_playing.call())
	if playing != _playing:
		_playing = playing
		_pending_until = 0
		_clear_rows()
		request("list")
	if _pending_until > 0 and Time.get_ticks_msec() > _pending_until:
		_pending_until = 0
		$Status.text = "応答がありません。接続後に一覧を更新してください"
	$Status.visible = not $Status.text.is_empty()
	$Save.disabled = _pending_until > 0
	$Refresh.disabled = _pending_until > 0
	for button: Button in $Saves.get_children():
		button.disabled = _pending_until > 0

func request(command: String, value := "") -> void:
	if _pending_until > 0:
		return
	if bool(is_playing.call()):
		if is_instance_valid(DEBUGGER.current) and DEBUGGER.current.request(command, value):
			_pending_until = Time.get_ticks_msec() + 5000
			$Status.text = "処理中…"
		else:
			$Status.text = "実行中のゲーム1つに接続してから一覧を更新してください"
		return
	var slots := SNAPSHOTS.new()
	slots.save_path = save_path
	var error := ""
	if command == "save":
		error = slots.create_snapshot(value)
	elif command == "load":
		error = slots.restore_snapshot(value)
	_receive({"names": slots.names(), "message": error if not error.is_empty() else (
		"保存しました" if command == "save" else "ロードしました。次回はタイトルから開始します" if command == "load" else "")})

func _receive(result: Dictionary) -> void:
	_pending_until = 0
	$Status.text = String(result.get("message", ""))
	var names := PackedStringArray(result.get("names", []))
	if _populated and names == _last_names:
		return
	_clear_rows()
	_last_names = names
	_populated = true
	for value: String in names:
		var button := Button.new()
		button.text = value
		button.tooltip_text = "このJSONをロードしてタイトルへ戻ります"
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(request.bind("load", value))
		$Saves.add_child(button)

func _clear_rows() -> void:
	_populated = false
	for child: Node in $Saves.get_children():
		$Saves.remove_child(child)
		child.queue_free()
