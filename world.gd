extends Node

@export var pause: bool = false

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu

# --- Steam ---
@onready var steam_menu := $CanvasLayer/SteamHUD 


func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		pause = !pause
		if pause:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_button_pressed() -> void:
	%NetworkManager.become_host()
	start_game()


func _on_join_button_pressed() -> void:
	%NetworkManager.join_as_client()
	start_game()


func start_game() -> void:
	main_menu.hide()
	steam_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Steam Functionality ---

func _on_join_steam_pressed() -> void:
	main_menu.hide()
	steam_menu.show()
	%NetworkManager.active_network_type = %NetworkManager.NETWORK_TYPE.STEAM
	SteamManager.initialize_steam()

func _on_list_lobbies_pressed() -> void:
	%NetworkManager.list_lobbies()
