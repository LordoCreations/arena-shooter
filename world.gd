extends Node

@export var pause: bool = false

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry

# --- Multiplayer ---
const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

const Player = preload("res://player.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		pause = !pause
		if pause:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_button_pressed() -> void:
	main_menu.hide()
	
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	
	add_player(multiplayer.get_unique_id())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	

func _on_join_button_pressed() -> void:
	main_menu.hide()
	
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
