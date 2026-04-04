extends Node

signal scoreboard_changed(entries: Array)
signal kill_feed_added(entry: Dictionary)

@export var pause: bool = false
var popup_template_scene := preload("res://scenes/ui/menu_popup_template.tscn")
@export var ammo_box_scene: PackedScene = preload("res://scenes/ammo_box.tscn")
@export var gun_box_scene: PackedScene = preload("res://scenes/gun_box.tscn")
@export var ammo_spawn_interval_seconds: float = 10.0
@export var gun_spawn_interval_seconds: float = 30.0
@export var gun_boxes_per_cycle: int = 2
@export var max_active_ammo_boxes: int = 10
@export var max_active_gun_boxes: int = 6
@export var loot_spawn_area_size_meters: Vector2 = Vector2(25.0, 25.0)
@export var loot_drop_height: float = 8.0
@export var loot_ground_probe_height: float = 120.0
@export var loot_ground_probe_depth: float = 260.0
@export var loot_despawn_y_threshold: float = -50.0
@export var gun_box_weapon_pool: Array[WeaponResource] = [
	preload("res://weapons/blaster/blaster.tres"),
	preload("res://weapons/pistol/pistol.tres"),
]

# --- Pause Menu ---
@onready var pause_menu = $CanvasLayer/InGameMenu/PauseMenu
@onready var lobby_info_label = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/LobbyInfo
@onready var lobby_controls_button = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/LobbyControlsButton
@onready var username_input = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/UsernameRow/UsernameInput
@onready var apply_username_button = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/UsernameRow/ApplyUsername
@onready var volume_slider = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_input = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/VolumeRow/VolumeInput
@onready var sensitivity_slider = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/SensitivityRow/SensitivitySlider
@onready var sensitivity_input = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/SensitivityRow/SensitivityInput
@onready var leaderboard_panel = $CanvasLayer/InGameMenu/LeaderboardPanel
@onready var leaderboard_rows = $CanvasLayer/InGameMenu/LeaderboardPanel/MarginContainer/VBoxContainer/ScoreScroll/ScoreRows
@onready var lobby_controls_panel = $CanvasLayer/InGameMenu/LobbyControls
@onready var lobby_controls_list = $CanvasLayer/InGameMenu/LobbyControls/MarginContainer/VBoxContainer/PlayerScroll/PlayerList
@onready var notifications = $CanvasLayer/Notifications
@onready var loot_root: Node3D = get_node_or_null("Loot")

var _steam_error_popup
var _ammo_spawn_timer: Timer
var _gun_spawn_timer: Timer
var _loot_id_counter: int = 1
var _loot_nodes: Dictionary = {}
var _loot_spawn_data: Dictionary = {}

const LOOT_TYPE_AMMO := 0
const LOOT_TYPE_GUN := 1
const MAX_KILL_FEED_ENTRIES := 8

var _player_stats: Dictionary = {}
var _kill_feed_entries: Array = []
var _scoreboard_entries: Array = []

func _ready() -> void:
	pause_menu.hide()
	leaderboard_panel.hide()
	lobby_controls_panel.hide()
	_wire_in_game_menu_signals()
	_sync_username_input_with_profile()
	_sync_volume_slider_from_master()
	_sync_sensitivity_control_from_profile()
	_setup_loot_spawning()
	if not multiplayer.peer_connected.is_connected(_on_peer_connected_sync_loot):
		multiplayer.peer_connected.connect(_on_peer_connected_sync_loot)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected_cleanup_state):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected_cleanup_state)
	if not MultiplayerManager.username_changed.is_connected(_on_username_changed):
		MultiplayerManager.username_changed.connect(_on_username_changed)
	_start_pending_network()
	_initialize_match_state()
	_update_lobby_info()
	_refresh_input_state()

func _process(_delta: float) -> void:
	_refresh_input_state()

func _wire_in_game_menu_signals() -> void:
	var return_game_button := get_node_or_null("CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/ReturnGame") as Button
	if return_game_button and not return_game_button.pressed.is_connected(_on_return_game_pressed):
		return_game_button.pressed.connect(_on_return_game_pressed)

	var main_menu_button := get_node_or_null("CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/MainMenu") as Button
	if main_menu_button and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)

	var quit_game_button := get_node_or_null("CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/QuitGame") as Button
	if quit_game_button and not quit_game_button.pressed.is_connected(_on_quit_game_pressed):
		quit_game_button.pressed.connect(_on_quit_game_pressed)

	if lobby_controls_button and not lobby_controls_button.pressed.is_connected(_on_lobby_controls_pressed):
		lobby_controls_button.pressed.connect(_on_lobby_controls_pressed)

	if apply_username_button and not apply_username_button.pressed.is_connected(_on_apply_username_pressed):
		apply_username_button.pressed.connect(_on_apply_username_pressed)

	if username_input and not username_input.text_submitted.is_connected(_on_username_text_submitted):
		username_input.text_submitted.connect(_on_username_text_submitted)

	var close_lobby_controls_button := get_node_or_null("CanvasLayer/InGameMenu/LobbyControls/MarginContainer/VBoxContainer/CloseLobbyControls") as Button
	if close_lobby_controls_button and not close_lobby_controls_button.pressed.is_connected(_on_close_lobby_controls_pressed):
		close_lobby_controls_button.pressed.connect(_on_close_lobby_controls_pressed)

	if volume_slider and not volume_slider.value_changed.is_connected(_on_volume_slider_value_changed):
		volume_slider.value_changed.connect(_on_volume_slider_value_changed)

	if volume_input:
		if not volume_input.text_submitted.is_connected(_on_volume_input_text_submitted):
			volume_input.text_submitted.connect(_on_volume_input_text_submitted)
		if not volume_input.focus_exited.is_connected(_on_volume_input_focus_exited):
			volume_input.focus_exited.connect(_on_volume_input_focus_exited)

	if sensitivity_slider and not sensitivity_slider.value_changed.is_connected(_on_sensitivity_slider_value_changed):
		sensitivity_slider.value_changed.connect(_on_sensitivity_slider_value_changed)

	if sensitivity_input:
		if not sensitivity_input.text_submitted.is_connected(_on_sensitivity_input_text_submitted):
			sensitivity_input.text_submitted.connect(_on_sensitivity_input_text_submitted)
		if not sensitivity_input.focus_exited.is_connected(_on_sensitivity_input_focus_exited):
			sensitivity_input.focus_exited.connect(_on_sensitivity_input_focus_exited)

func _setup_loot_spawning() -> void:
	if loot_root == null:
		loot_root = Node3D.new()
		loot_root.name = "Loot"
		add_child(loot_root)

	_ammo_spawn_timer = Timer.new()
	_ammo_spawn_timer.one_shot = false
	_ammo_spawn_timer.autostart = true
	_ammo_spawn_timer.wait_time = max(ammo_spawn_interval_seconds, 0.1)
	_ammo_spawn_timer.timeout.connect(_on_ammo_spawn_timer_timeout)
	add_child(_ammo_spawn_timer)

	_gun_spawn_timer = Timer.new()
	_gun_spawn_timer.one_shot = false
	_gun_spawn_timer.autostart = true
	_gun_spawn_timer.wait_time = max(gun_spawn_interval_seconds, 0.1)
	_gun_spawn_timer.timeout.connect(_on_gun_spawn_timer_timeout)
	add_child(_gun_spawn_timer)

func _is_loot_spawn_host() -> bool:
	if not has_node("%NetworkManager"):
		return false
	return %NetworkManager.is_host()

func _on_ammo_spawn_timer_timeout() -> void:
	if not _is_loot_spawn_host():
		return
	_spawn_loot_batch(LOOT_TYPE_AMMO, 1)

func _on_gun_spawn_timer_timeout() -> void:
	if not _is_loot_spawn_host():
		return
	_spawn_loot_batch(LOOT_TYPE_GUN, max(gun_boxes_per_cycle, 0))

func _spawn_loot_batch(loot_type: int, count: int) -> void:
	if count <= 0:
		return

	var max_allowed := _get_max_loot_count_for_type(loot_type)
	if max_allowed <= 0:
		return

	var active_count := _get_active_loot_count_for_type(loot_type)
	var available_slots: int = max(max_allowed - active_count, 0)
	if available_slots <= 0:
		return

	var spawn_count: int = min(count, available_slots)
	for _i in range(spawn_count):
		var loot_id := _loot_id_counter
		_loot_id_counter += 1
		var spawn_position := _find_random_loot_spawn_position()
		var yaw := randf_range(0.0, TAU)
		var weapon_path := ""
		if loot_type == LOOT_TYPE_GUN:
			weapon_path = _pick_random_weapon_path()
			if weapon_path == "":
				continue
		_loot_spawn_data[loot_id] = {
			"loot_type": loot_type,
			"authority_peer_id": multiplayer.get_unique_id(),
			"weapon_path": weapon_path,
		}
		_spawn_loot_box.rpc(loot_id, loot_type, spawn_position, yaw, multiplayer.get_unique_id(), weapon_path)

func _get_max_loot_count_for_type(loot_type: int) -> int:
	if loot_type == LOOT_TYPE_AMMO:
		return max(max_active_ammo_boxes, 0)
	if loot_type == LOOT_TYPE_GUN:
		return max(max_active_gun_boxes, 0)
	return 0

func _get_active_loot_count_for_type(loot_type: int) -> int:
	var count := 0
	for loot_id in _loot_nodes.keys():
		var loot_node = _loot_nodes.get(loot_id)
		if loot_node == null or not is_instance_valid(loot_node):
			continue
		var spawn_data: Dictionary = _loot_spawn_data.get(loot_id, {})
		if int(spawn_data.get("loot_type", -1)) == loot_type:
			count += 1
	return count

func _on_peer_connected_sync_loot(peer_id: int) -> void:
	if multiplayer.is_server():
		_ensure_player_stats(peer_id)
		_broadcast_scoreboard_state()
		_sync_match_state_to_peer(peer_id)
		MultiplayerManager.sync_all_usernames_to_peer(peer_id)

	if not _is_loot_spawn_host():
		return

	for loot_id in _loot_nodes.keys():
		var loot_node = _loot_nodes.get(loot_id)
		if not (loot_node is Node3D) or not is_instance_valid(loot_node):
			continue

		var body := loot_node as Node3D
		if not body.is_inside_tree():
			continue
		var spawn_data: Dictionary = _loot_spawn_data.get(loot_id, {})
		var loot_type: int = int(spawn_data.get("loot_type", LOOT_TYPE_AMMO))
		var authority_peer_id: int = int(spawn_data.get("authority_peer_id", multiplayer.get_unique_id()))
		var weapon_path: String = str(spawn_data.get("weapon_path", ""))
		_spawn_loot_box.rpc_id(peer_id, int(loot_id), loot_type, body.global_position, body.rotation.y, authority_peer_id, weapon_path)

func _find_random_loot_spawn_position() -> Vector3:
	var center: Vector3 = MultiplayerManager.respawn_point
	var half_width: float = max(loot_spawn_area_size_meters.x * 0.5, 0.5)
	var half_depth: float = max(loot_spawn_area_size_meters.y * 0.5, 0.5)
	var world_3d: World3D = get_viewport().world_3d
	if world_3d == null:
		return center + Vector3(0.0, loot_drop_height, 0.0)
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	for _attempt in range(18):
		var offset := Vector2(randf_range(-half_width, half_width), randf_range(-half_depth, half_depth))
		var ray_start := center + Vector3(offset.x, loot_ground_probe_height, offset.y)
		var ray_end := ray_start - Vector3.UP * loot_ground_probe_depth
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			return hit_position + Vector3.UP * loot_drop_height

	return center + Vector3(randf_range(-half_width, half_width), loot_drop_height, randf_range(-half_depth, half_depth))

@rpc("authority", "call_local", "reliable")
func _spawn_loot_box(loot_id: int, loot_type: int, spawn_position: Vector3, yaw: float, authority_peer_id: int, weapon_path: String = "") -> void:
	if _loot_nodes.has(loot_id):
		return
	var scene: PackedScene = ammo_box_scene if loot_type == LOOT_TYPE_AMMO else gun_box_scene
	if scene == null:
		return
	if loot_root == null:
		loot_root = get_node_or_null("Loot")
		if loot_root == null:
			return

	var loot_node = scene.instantiate()
	if not (loot_node is Node3D):
		if loot_node is Node:
			(loot_node as Node).queue_free()
		return

	var body := loot_node as Node3D
	body.name = "LootBox_%s" % loot_id
	loot_root.add_child(body, true)
	body.global_position = spawn_position
	body.rotation.y = yaw

	if body.has_method("setup_loot_box"):
		body.call("setup_loot_box", loot_id, authority_peer_id)
	if body.has_method("set_despawn_y_threshold"):
		body.call("set_despawn_y_threshold", loot_despawn_y_threshold)
	if body.has_method("set_contained_weapon_path"):
		body.call("set_contained_weapon_path", weapon_path)

	_loot_nodes[loot_id] = body

func consume_loot_box(loot_id: int, peer_id: int, loot_type: int) -> void:
	if not _is_loot_spawn_host():
		return
	if not _loot_nodes.has(loot_id):
		return
	var loot_node = _loot_nodes.get(loot_id)

	var player = _get_player_for_peer(peer_id)
	if player == null:
		return

	if loot_type == LOOT_TYPE_AMMO:
		_grant_max_reserve_ammo(player, peer_id)
	elif loot_type == LOOT_TYPE_GUN:
		var spawn_data: Dictionary = _loot_spawn_data.get(loot_id, {})
		var weapon_path: String = str(spawn_data.get("weapon_path", ""))
		if weapon_path == "":
			weapon_path = _pick_random_weapon_path()
		_grant_weapon_by_path(player, peer_id, weapon_path)

	if loot_node is Node3D and loot_node.has_method("sync_open_sound"):
		var sound_origin := (loot_node as Node3D).global_position
		if multiplayer.multiplayer_peer == null:
			loot_node.call("sync_open_sound", sound_origin)
		else:
			(loot_node as Node).rpc("sync_open_sound", sound_origin)

	_remove_loot_box.rpc(loot_id)

func _get_player_for_peer(peer_id: int) -> Node:
	var players := get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null(str(peer_id))

func _grant_max_reserve_ammo(player: Node, peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		if player.has_method("give_full_reserve_ammo_local"):
			player.call("give_full_reserve_ammo_local")
		return
	if player.has_method("give_full_reserve_ammo"):
		player.rpc_id(peer_id, "give_full_reserve_ammo")

func _grant_weapon_by_path(player: Node, peer_id: int, weapon_path: String) -> void:
	if weapon_path == "":
		return

	if peer_id == multiplayer.get_unique_id():
		if player.has_method("equip_weapon_full_from_path_local"):
			player.call("equip_weapon_full_from_path_local", weapon_path)
		return
	if player.has_method("equip_weapon_full_from_path"):
		player.rpc_id(peer_id, "equip_weapon_full_from_path", weapon_path)

func _pick_random_weapon_path() -> String:
	var valid_paths: Array[String] = []
	for weapon_resource in gun_box_weapon_pool:
		if weapon_resource == null:
			continue
		if weapon_resource.resource_path == "":
			continue
		if ResourceLoader.exists(weapon_resource.resource_path):
			valid_paths.append(weapon_resource.resource_path)
	if valid_paths.is_empty():
		return ""
	return valid_paths[randi() % valid_paths.size()]

@rpc("authority", "call_local", "reliable")
func _remove_loot_box(loot_id: int) -> void:
	var loot_node = _loot_nodes.get(loot_id)
	if loot_node != null and is_instance_valid(loot_node):
		loot_node.queue_free()
	_loot_nodes.erase(loot_id)
	_loot_spawn_data.erase(loot_id)

func despawn_loot_box(loot_id: int) -> void:
	if not _is_loot_spawn_host():
		return
	if not _loot_nodes.has(loot_id):
		return
	_remove_loot_box.rpc(loot_id)

func _sync_volume_slider_from_master() -> void:
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx < 0:
		volume_slider.set_value_no_signal(100.0)
		if volume_input:
			volume_input.text = "100"
		return

	var volume_percent := 100.0
	if AudioServer.is_bus_mute(bus_idx):
		volume_percent = 0.0
	else:
		volume_percent = clamp(db_to_linear(AudioServer.get_bus_volume_db(bus_idx)) * 100.0, 0.0, 100.0)

	var rounded = int(round(volume_percent))
	volume_slider.set_value_no_signal(float(rounded))
	if volume_input:
		volume_input.text = str(rounded)

func _set_master_volume_percent(value: float) -> void:
	var clamped = clamp(value, 0.0, 100.0)
	var bus_idx = AudioServer.get_bus_index("Master")
	if bus_idx < 0:
		return

	if clamped <= 0.0:
		AudioServer.set_bus_mute(bus_idx, true)
		AudioServer.set_bus_volume_db(bus_idx, -80.0)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped / 100.0))

	var rounded: int = int(round(clamped))
	if volume_slider:
		volume_slider.set_value_no_signal(float(rounded))
	if volume_input:
		volume_input.text = str(rounded)

func _on_volume_slider_value_changed(value: float) -> void:
	_set_master_volume_percent(value)

func _parse_float_text(raw_text: String) -> Variant:
	var cleaned := raw_text.strip_edges().replace("%", "")
	if cleaned.is_empty():
		return null
	if not cleaned.is_valid_float():
		return null
	return float(cleaned)

func _on_volume_input_text_submitted(new_text: String) -> void:
	_apply_volume_from_input_text(new_text)

func _on_volume_input_focus_exited() -> void:
	if volume_input == null:
		return
	_apply_volume_from_input_text(volume_input.text)

func _apply_volume_from_input_text(raw_text: String) -> void:
	var parsed: Variant = _parse_float_text(raw_text)
	if parsed == null:
		_sync_volume_slider_from_master()
		return
	_set_master_volume_percent(parsed)

func _sync_sensitivity_control_from_profile() -> void:
	var applied: float = MultiplayerManager.get_mouse_sensitivity_multiplier()
	if sensitivity_slider:
		sensitivity_slider.set_value_no_signal(applied)
	if sensitivity_input:
		sensitivity_input.text = "%.1f" % applied

func _on_sensitivity_slider_value_changed(value: float) -> void:
	_apply_sensitivity_value(value)

func _on_sensitivity_input_text_submitted(new_text: String) -> void:
	_apply_sensitivity_from_input_text(new_text)

func _on_sensitivity_input_focus_exited() -> void:
	if sensitivity_input == null:
		return
	_apply_sensitivity_from_input_text(sensitivity_input.text)

func _apply_sensitivity_from_input_text(raw_text: String) -> void:
	var parsed: Variant = _parse_float_text(raw_text)
	if parsed == null:
		_sync_sensitivity_control_from_profile()
		return
	_apply_sensitivity_value(parsed)

func _apply_sensitivity_value(value: float) -> void:
	var applied := MultiplayerManager.set_mouse_sensitivity_multiplier(value)
	if sensitivity_slider:
		sensitivity_slider.set_value_no_signal(applied)
	if sensitivity_input:
		sensitivity_input.text = "%.1f" % applied

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		_toggle_pause_menu()

func _start_pending_network() -> void:
	if MultiplayerManager.pending_action == "":
		return
	%NetworkManager.active_network_type = MultiplayerManager.pending_network_type
	if MultiplayerManager.pending_network_type == MultiplayerManager.NETWORK_TYPE.STEAM:
		if not SteamManager.initialize_steam():
			_show_steam_error_in_game()
			return
	match MultiplayerManager.pending_action:
		"host":
			%NetworkManager.become_host()
		"join":
			if MultiplayerManager.pending_network_type == MultiplayerManager.NETWORK_TYPE.STEAM:
				%NetworkManager.join_as_client(MultiplayerManager.pending_lobby_id)
			else:
				%NetworkManager.join_as_client(0, MultiplayerManager.pending_address)
	MultiplayerManager.pending_action = ""

func _toggle_pause_menu() -> void:
	pause = !pause
	pause_menu.visible = pause
	if pause:
		leaderboard_panel.show()
		_sync_username_input_with_profile()
		_sync_sensitivity_control_from_profile()
		_update_lobby_info()
		_refresh_pause_leaderboard()
	else:
		leaderboard_panel.hide()
		lobby_controls_panel.hide()
	_refresh_input_state()

func _refresh_pause_leaderboard() -> void:
	if leaderboard_rows == null:
		return
	for child in leaderboard_rows.get_children():
		child.queue_free()

	var entries := get_scoreboard_snapshot()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No scores yet."
		empty_label.add_theme_font_size_override("font_size", 20)
		leaderboard_rows.add_child(empty_label)
		return

	var table := GridContainer.new()
	table.columns = 3
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 12)
	table.add_theme_constant_override("v_separation", 6)
	leaderboard_rows.add_child(table)

	table.add_child(_create_leaderboard_table_cell("Name", HORIZONTAL_ALIGNMENT_LEFT, true, false))
	table.add_child(_create_leaderboard_table_cell("K 🗡", HORIZONTAL_ALIGNMENT_CENTER, true, true))
	table.add_child(_create_leaderboard_table_cell("D 💀", HORIZONTAL_ALIGNMENT_CENTER, true, true))

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		table.add_child(_create_leaderboard_table_cell(str(entry.get("name", "Player")), HORIZONTAL_ALIGNMENT_LEFT, false, false))
		table.add_child(_create_leaderboard_table_cell(str(int(entry.get("kills", 0))), HORIZONTAL_ALIGNMENT_CENTER, false, true))
		table.add_child(_create_leaderboard_table_cell(str(int(entry.get("deaths", 0))), HORIZONTAL_ALIGNMENT_CENTER, false, true))

func _create_leaderboard_table_cell(text_value: String, alignment: HorizontalAlignment, is_header: bool, is_stat_column: bool) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF

	if is_stat_column:
		label.custom_minimum_size = Vector2(72.0, 0.0)
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true

	if is_header:
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98, 0.95))
	else:
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.92))

	return label

func _is_local_player_dead() -> bool:
	var local_player := _get_local_authority_player()
	if local_player == null:
		return false
	if local_player.has_method("is_dead"):
		return bool(local_player.call("is_dead"))
	return false

func _refresh_input_state() -> void:
	var menu_open: bool = bool(pause_menu.visible or lobby_controls_panel.visible)
	var dead_menu_open: bool = _is_local_player_dead()
	var should_free_cursor: bool = menu_open or dead_menu_open
	MultiplayerManager.controls_enabled = not should_free_cursor
	var desired_mouse_mode := Input.MOUSE_MODE_VISIBLE if should_free_cursor else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != desired_mouse_mode:
		Input.mouse_mode = desired_mouse_mode

func _sync_username_input_with_profile() -> void:
	if username_input == null:
		return
	username_input.max_length = MultiplayerManager.USERNAME_MAX_LENGTH
	var local_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else -1
	var preferred := MultiplayerManager.set_local_preferred_username(MultiplayerManager.player_username, local_id)
	username_input.text = preferred

func _on_username_text_submitted(_new_text: String) -> void:
	_on_apply_username_pressed()

func _on_apply_username_pressed() -> void:
	if username_input == null:
		return

	var local_id := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else -1
	var cleaned_username := MultiplayerManager.set_local_username_and_broadcast(username_input.text, local_id)
	username_input.text = cleaned_username

	var local_player := _get_local_authority_player()
	if local_player != null and local_player.has_method("set_username"):
		local_player.call("set_username", cleaned_username)

	if notifications:
		notifications.notify("Username updated to %s" % cleaned_username, false)

	_refresh_lobby_controls()
	if multiplayer.is_server():
		_broadcast_scoreboard_state()

func _update_lobby_info() -> void:
	var lobby_display = %NetworkManager.get_lobby_display()
	if lobby_display == "":
		lobby_info_label.text = "Lobby Info: N/A"
	elif %NetworkManager.active_network_type == %NetworkManager.NETWORK_TYPE.STEAM:
		lobby_info_label.text = "Lobby ID: %s" % lobby_display
	else:
		lobby_info_label.text = "Lobby IP: %s" % lobby_display
	lobby_controls_button.visible = %NetworkManager.is_host()

func _on_return_game_pressed() -> void:
	if pause:
		_toggle_pause_menu()

func _on_main_menu_pressed() -> void:
	if has_node("%NetworkManager"):
		%NetworkManager.shutdown_lobby(true)
	MultiplayerManager.pending_action = ""
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	MultiplayerManager.multiplayer_mode_enabled = false
	MultiplayerManager.host_mode_enabled = false
	MultiplayerManager.player_usernames.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_game_pressed() -> void:
	if has_node("%NetworkManager"):
		%NetworkManager.shutdown_lobby(true)
	get_tree().quit()

func _on_lobby_controls_pressed() -> void:
	lobby_controls_panel.show()
	_refresh_lobby_controls()
	_refresh_input_state()

func _on_close_lobby_controls_pressed() -> void:
	lobby_controls_panel.hide()
	_refresh_input_state()

func _refresh_lobby_controls() -> void:
	for child in lobby_controls_list.get_children():
		child.queue_free()
	var members = %NetworkManager.get_lobby_members()
	if members.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No players found."
		empty_label.add_theme_font_size_override("font_size", 24)
		lobby_controls_list.add_child(empty_label)
		return
	for member in members:
		var row = HBoxContainer.new()
		var name_label = Label.new()
		name_label.text = str(member.get("name", "Player"))
		name_label.add_theme_font_size_override("font_size", 24)
		row.add_child(name_label)
		if member.get("can_kick", false):
			var kick_button = Button.new()
			kick_button.text = "Kick"
			kick_button.add_theme_font_size_override("font_size", 24)
			kick_button.connect("pressed", Callable(self, "_on_kick_member_pressed").bind(member.get("id"), member.get("id_type", "peer")))
			row.add_child(kick_button)
		if member.get("can_transfer", false):
			var transfer_button = Button.new()
			transfer_button.text = "Transfer"
			transfer_button.add_theme_font_size_override("font_size", 24)
			transfer_button.connect("pressed", Callable(self, "_on_transfer_owner_pressed").bind(member.get("id"), member.get("id_type", "peer")))
			row.add_child(transfer_button)
		lobby_controls_list.add_child(row)

func _on_kick_member_pressed(member_id, id_type: String) -> void:
	%NetworkManager.kick_member(member_id, id_type)
	_refresh_lobby_controls()

func _on_transfer_owner_pressed(member_id, id_type: String) -> void:
	%NetworkManager.transfer_lobby_ownership(member_id, id_type)
	_refresh_lobby_controls()

func _get_local_authority_player() -> Node:
	var players := get_node_or_null("Players")
	if players == null:
		return null

	for player_node in players.get_children():
		if player_node is Node and player_node.has_method("is_multiplayer_authority") and player_node.is_multiplayer_authority():
			return player_node

	return null

func _initialize_match_state() -> void:
	_player_stats.clear()
	_kill_feed_entries.clear()
	_scoreboard_entries.clear()

	_ensure_player_stats(multiplayer.get_unique_id())
	if multiplayer.multiplayer_peer != null:
		for peer_id in multiplayer.get_peers():
			_ensure_player_stats(int(peer_id))

	_broadcast_scoreboard_state()

func _set_scoreboard_snapshot_local(entries: Array) -> void:
	_scoreboard_entries = entries.duplicate(true)
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_player_stats.clear()
		for entry in _scoreboard_entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var peer_id := int(entry.get("peer_id", -1))
			if peer_id <= 0:
				continue
			_player_stats[peer_id] = {
				"kills": int(entry.get("kills", 0)),
				"deaths": int(entry.get("deaths", 0)),
			}
	if leaderboard_panel and leaderboard_panel.visible:
		_refresh_pause_leaderboard()

func _on_peer_disconnected_cleanup_state(peer_id: int) -> void:
	_player_stats.erase(peer_id)
	MultiplayerManager.clear_peer_username(peer_id)
	_broadcast_scoreboard_state()
	if lobby_controls_panel.visible:
		_refresh_lobby_controls()

func _on_username_changed(_peer_id: int, _username: String) -> void:
	if lobby_controls_panel.visible:
		_refresh_lobby_controls()
	if leaderboard_panel.visible:
		_refresh_pause_leaderboard()
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_broadcast_scoreboard_state()

func _ensure_player_stats(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if _player_stats.has(peer_id):
		return
	_player_stats[peer_id] = {
		"kills": 0,
		"deaths": 0,
	}

func _get_player_display_name(peer_id: int) -> String:
	if peer_id <= 0:
		return "World"
	return MultiplayerManager.get_display_name(peer_id)

func _build_scoreboard_snapshot() -> Array:
	var entries: Array = []
	for peer_id in _player_stats.keys():
		var stats: Dictionary = _player_stats[peer_id]
		entries.append({
			"peer_id": int(peer_id),
			"name": _get_player_display_name(int(peer_id)),
			"kills": int(stats.get("kills", 0)),
			"deaths": int(stats.get("deaths", 0)),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var kills_a := int(a.get("kills", 0))
		var kills_b := int(b.get("kills", 0))
		if kills_a != kills_b:
			return kills_a > kills_b

		var deaths_a := int(a.get("deaths", 0))
		var deaths_b := int(b.get("deaths", 0))
		if deaths_a != deaths_b:
			return deaths_a < deaths_b

		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	return entries

func get_scoreboard_snapshot() -> Array:
	if not _scoreboard_entries.is_empty():
		return _scoreboard_entries.duplicate(true)
	return _build_scoreboard_snapshot()

func get_kill_feed_snapshot() -> Array:
	return _kill_feed_entries.duplicate(true)

func _broadcast_scoreboard_state() -> void:
	var snapshot := _build_scoreboard_snapshot()
	_set_scoreboard_snapshot_local(snapshot)
	if multiplayer.multiplayer_peer == null:
		scoreboard_changed.emit(snapshot)
		return
	if multiplayer.is_server():
		_sync_scoreboard_state.rpc(snapshot)

@rpc("any_peer", "call_local", "reliable")
func _sync_scoreboard_state(entries: Array) -> void:
	_set_scoreboard_snapshot_local(entries)
	scoreboard_changed.emit(_scoreboard_entries.duplicate(true))

func _sync_match_state_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return

	_sync_scoreboard_state.rpc_id(peer_id, _build_scoreboard_snapshot())
	for entry_index in range(_kill_feed_entries.size() - 1, -1, -1):
		var entry: Dictionary = _kill_feed_entries[entry_index]
		_sync_kill_feed_entry.rpc_id(
			peer_id,
			int(entry.get("killer_id", 0)),
			int(entry.get("victim_id", 0)),
			str(entry.get("killer_name", "World")),
			str(entry.get("victim_name", "Unknown"))
		)

func _append_kill_feed_entry(killer_id: int, victim_id: int, killer_name: String, victim_name: String) -> void:
	var entry := {
		"killer_id": killer_id,
		"victim_id": victim_id,
		"killer_name": killer_name,
		"victim_name": victim_name,
	}
	_kill_feed_entries.push_front(entry)
	while _kill_feed_entries.size() > MAX_KILL_FEED_ENTRIES:
		_kill_feed_entries.pop_back()
	kill_feed_added.emit(entry)

@rpc("any_peer", "call_local", "reliable")
func _sync_kill_feed_entry(killer_id: int, victim_id: int, killer_name: String, victim_name: String) -> void:
	_append_kill_feed_entry(killer_id, victim_id, killer_name, victim_name)

@rpc("any_peer", "call_remote", "reliable")
func report_player_death(victim_id: int, killer_id: int) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	if multiplayer.multiplayer_peer != null:
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id > 0 and sender_id != victim_id:
			return

	_ensure_player_stats(victim_id)
	var victim_stats: Dictionary = _player_stats.get(victim_id, {"kills": 0, "deaths": 0})
	var victim_kills := int(victim_stats.get("kills", 0))
	victim_stats["deaths"] = int(victim_stats.get("deaths", 0)) + 1
	victim_stats["kills"] = int(floor(float(victim_kills) * 0.5))
	_player_stats[victim_id] = victim_stats

	var credited_killer := killer_id
	if credited_killer <= 0 or credited_killer == victim_id:
		credited_killer = 0
	else:
		_ensure_player_stats(credited_killer)
		var killer_stats: Dictionary = _player_stats.get(credited_killer, {"kills": 0, "deaths": 0})
		killer_stats["kills"] = int(killer_stats.get("kills", 0)) + 1
		_player_stats[credited_killer] = killer_stats

	var killer_name := _get_player_display_name(credited_killer)
	var victim_name := _get_player_display_name(victim_id)

	if multiplayer.multiplayer_peer == null:
		_append_kill_feed_entry(credited_killer, victim_id, killer_name, victim_name)
		var snapshot := _build_scoreboard_snapshot()
		_set_scoreboard_snapshot_local(snapshot)
		scoreboard_changed.emit(snapshot)
		return

	if multiplayer.is_server():
		_sync_kill_feed_entry.rpc(credited_killer, victim_id, killer_name, victim_name)
		_broadcast_scoreboard_state()

func _show_steam_error_in_game() -> void:
	var popup = _ensure_steam_error_popup()
	popup.open_popup("Steam Error", "Failed to connect to Steam. Please make sure the Steam app is running and restart the game.", "Return to Menu")

func _ensure_steam_error_popup():
	if is_instance_valid(_steam_error_popup):
		return _steam_error_popup

	_steam_error_popup = popup_template_scene.instantiate()
	var popup_parent = get_node_or_null("CanvasLayer")
	if popup_parent:
		popup_parent.add_child(_steam_error_popup)
	else:
		add_child(_steam_error_popup)
	if not _steam_error_popup.confirmed.is_connected(Callable(self, "_on_steam_error_in_game_dismissed")):
		_steam_error_popup.confirmed.connect(Callable(self, "_on_steam_error_in_game_dismissed"))
	return _steam_error_popup

func _on_steam_error_in_game_dismissed() -> void:
	if is_instance_valid(_steam_error_popup):
		_steam_error_popup.close_popup()
	_on_main_menu_pressed()

func _on_multiplayer_spawner_spawned(_node: Node) -> void:
	pass
