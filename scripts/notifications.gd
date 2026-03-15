extends PanelContainer

var _message_list: VBoxContainer

func _ready():
	# 1. Start hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 2. Setup the list
	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message_list)
	
	# 3. Connect signals to auto-hide/show the panel
	_message_list.child_entered_tree.connect(_on_list_changed)
	_message_list.child_exiting_tree.connect(_on_list_changed)

func _on_list_changed(_node = null):
	# Use call_deferred to ensure the child count is accurate 
	# after the tree finishes updating
	_update_visibility.call_deferred()

func _update_visibility():
	# Show the panel if there are labels, hide if empty
	visible = _message_list.get_child_count() > 0

func notify(message: String, is_important: bool = false):
	var label = Label.new()
	label.text = " > " + message
	label.modulate = Color.GREEN

	if is_important:
		label.modulate = Color.YELLOW

	_message_list.add_child(label)

	var timer = get_tree().create_timer(5.0 if is_important else 3.0)
	timer.timeout.connect(func():
		var tween = create_tween()
		tween.tween_property(label, "modulate:a", 0.0, 0.5)
		tween.tween_callback(label.queue_free)
	)
