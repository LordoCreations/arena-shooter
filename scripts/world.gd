extends Node

@export var pause: bool = false
var popup_template_scene := preload("res://scenes/ui/menu_popup_template.tscn")
@export var ammo_box_scene: PackedScene = preload("res://scenes/ammo_box.tscn")
@export var gun_box_scene: PackedScene = preload("res://scenes/gun_box.tscn")
@export var ammo_spawn_interval_seconds: float = 10.0
@export var gun_spawn_interval_seconds: float = 30.0
@export var gun_boxes_per_cycle: int = 2
@export var max_active_ammo_boxes: int = 10
@export var max_active_gun_boxes: int = 6
@export var loot_spawn_radius: float = 45.0
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
@onready var volume_slider = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label = $CanvasLayer/InGameMenu/PauseMenu/MarginContainer/VBoxContainer/VolumeRow/VolumeValue
@onready var lobby_controls_panel = $CanvasLayer/InGameMenu/LobbyControls
@onready var lobby_controls_list = $CanvasLayer/InGameMenu/LobbyControls/MarginContainer/VBoxContainer/PlayerScroll/PlayerList
@onready var loot_root: Node3D = get_node_or_null("Loot")

var _steam_error_popup
var _ammo_spawn_timer: Timer
var _gun_spawn_timer: Timer
var _loot_id_counter: int = 1
var _loot_nodes: Dictionary = {}
var _loot_spawn_data: Dictionary = {}

const LOOT_TYPE_AMMO := 0
const LOOT_TYPE_GUN := 1

func _ready() -> void:
	pause_menu.hide()
	lobby_controls_panel.hide()
	_sync_volume_slider_from_master()
	_setup_loot_spawning()
	if not multiplayer.peer_connected.is_connected(_on_peer_connected_sync_loot):
		multiplayer.peer_connected.connect(_on_peer_connected_sync_loot)
	_start_pending_network()
	_update_lobby_info()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	if not _is_loot_spawn_host():
		return

	for loot_id in _loot_nodes.keys():
		var loot_node = _loot_nodes.get(loot_id)
		if not (loot_node is Node3D) or not is_instance_valid(loot_node):
			continue

		var body := loot_node as Node3D
		var spawn_data: Dictionary = _loot_spawn_data.get(loot_id, {})
		var loot_type: int = int(spawn_data.get("loot_type", LOOT_TYPE_AMMO))
		var authority_peer_id: int = int(spawn_data.get("authority_peer_id", multiplayer.get_unique_id()))
		var weapon_path: String = str(spawn_data.get("weapon_path", ""))
		_spawn_loot_box.rpc_id(peer_id, int(loot_id), loot_type, body.global_position, body.rotation.y, authority_peer_id, weapon_path)

func _find_random_loot_spawn_position() -> Vector3:
	var center: Vector3 = MultiplayerManager.respawn_point
	var world_3d: World3D = get_viewport().world_3d
	if world_3d == null:
		return center + Vector3(0.0, loot_drop_height, 0.0)
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	for _attempt in range(18):
		var offset := Vector2(randf_range(-loot_spawn_radius, loot_spawn_radius), randf_range(-loot_spawn_radius, loot_spawn_radius))
		if offset.length() > loot_spawn_radius:
			offset = offset.normalized() * randf_range(0.0, loot_spawn_radius)
		var ray_start := center + Vector3(offset.x, loot_ground_probe_height, offset.y)
		var ray_end := ray_start - Vector3.UP * loot_ground_probe_depth
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			return hit_position + Vector3.UP * loot_drop_height

	return center + Vector3(randf_range(-loot_spawn_radius, loot_spawn_radius), loot_drop_height, randf_range(-loot_spawn_radius, loot_spawn_radius))

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
	body.global_position = spawn_position
	body.rotation.y = yaw
	loot_root.add_child(body, true)

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
		volume_value_label.text = "100%"
		return

	var volume_percent := 100.0
	if AudioServer.is_bus_mute(bus_idx):
		volume_percent = 0.0
	else:
		volume_percent = clamp(db_to_linear(AudioServer.get_bus_volume_db(bus_idx)) * 100.0, 0.0, 100.0)

	var rounded = int(round(volume_percent))
	volume_slider.set_value_no_signal(float(rounded))
	volume_value_label.text = "%d%%" % rounded

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

	volume_value_label.text = "%d%%" % int(round(clamped))

func _on_volume_slider_value_changed(value: float) -> void:
	_set_master_volume_percent(value)

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
	MultiplayerManager.controls_enabled = not pause
	if pause:
		_update_lobby_info()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		lobby_controls_panel.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_game_pressed() -> void:
	if has_node("%NetworkManager"):
		%NetworkManager.shutdown_lobby(true)
	get_tree().quit()

func _on_lobby_controls_pressed() -> void:
	lobby_controls_panel.show()
	_refresh_lobby_controls()

func _on_close_lobby_controls_pressed() -> void:
	lobby_controls_panel.hide()

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
