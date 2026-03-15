extends Node

@export var pause: bool = false

# --- Pause Menu ---
@onready var pause_menu = $CanvasLayer/PauseMenu
@onready var lobby_info_label = $CanvasLayer/PauseMenu/MarginContainer/VBoxContainer/LobbyInfo
@onready var lobby_controls_button = $CanvasLayer/PauseMenu/MarginContainer/VBoxContainer/LobbyControlsButton
@onready var lobby_controls_panel = $CanvasLayer/LobbyControls
@onready var lobby_controls_list = $CanvasLayer/LobbyControls/MarginContainer/VBoxContainer/PlayerScroll/PlayerList

func _ready() -> void:
	pause_menu.hide()
	lobby_controls_panel.hide()
	_start_pending_network()
	_update_lobby_info()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	MultiplayerManager.pending_action = ""
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	MultiplayerManager.multiplayer_mode_enabled = false
	MultiplayerManager.host_mode_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_game_pressed() -> void:
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
		lobby_controls_list.add_child(empty_label)
		return
	for member in members:
		var row = HBoxContainer.new()
		var name_label = Label.new()
		name_label.text = str(member.get("name", "Player"))
		row.add_child(name_label)
		if member.get("can_kick", false):
			var kick_button = Button.new()
			kick_button.text = "Kick"
			kick_button.connect("pressed", Callable(self, "_on_kick_member_pressed").bind(member.get("id"), member.get("id_type", "peer")))
			row.add_child(kick_button)
		if member.get("can_transfer", false):
			var transfer_button = Button.new()
			transfer_button.text = "Transfer"
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
	var error_dialog = AcceptDialog.new()
	error_dialog.title = "Steam Error"
	error_dialog.dialog_text = "Failed to connect to Steam. Please make sure the Steam app is running and restart the game."
	error_dialog.get_ok_button().text = "Return to Menu"
	error_dialog.connect("confirmed", Callable(self, "_on_steam_error_in_game_dismissed"))
	add_child(error_dialog)
	error_dialog.popup_centered_ratio(0.6)

func _on_steam_error_in_game_dismissed() -> void:
	_on_main_menu_pressed()
