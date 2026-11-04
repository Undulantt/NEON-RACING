extends RefCounted

static func install_gamepad_bindings() -> void:
	# Runtime additions preserve keyboard mappings and do not rewrite project settings.
	for binding in [["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["brake_reverse", JOY_AXIS_TRIGGER_LEFT, 1.0], ["steer_left", JOY_AXIS_LEFT_X, -1.0], ["steer_right", JOY_AXIS_LEFT_X, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = binding[1]
		event.axis_value = binding[2]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)
	for binding in [["handbrake", JOY_BUTTON_A], ["turbo", JOY_BUTTON_X], ["pause", JOY_BUTTON_START], ["recover", JOY_BUTTON_Y]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = binding[1]
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)
