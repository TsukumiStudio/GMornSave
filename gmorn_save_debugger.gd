@tool
extends EditorDebuggerPlugin

static var current: EditorDebuggerPlugin
signal result_received(result: Dictionary)

func _has_capture(capture: String) -> bool:
	return capture == "gmorn_save"

func request(command: String, value := "") -> bool:
	var active: Array[EditorDebuggerSession] = []
	for session: EditorDebuggerSession in get_sessions():
		if session.is_active():
			active.append(session)
	# 複数実行時は、どのゲームの保存かを勝手に選ばない。
	if active.size() != 1:
		return false
	active[0].send_message("gmorn_save:request", [command, value])
	return true

func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message != "gmorn_save:result" or data.size() != 1 or not data[0] is Dictionary:
		return false
	result_received.emit(data[0])
	return true
