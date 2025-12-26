extends Node

var is_owned: bool = false
const STEAMAPPID: int = 480 # test id
var steam_id: int = 0
var steam_username: String = ""

var lobby_id = 0
var lobby_max = 8

func _init() -> void:
	OS.set_environment("SteamAppId", str(STEAMAPPID))
	OS.set_environment("SteamGameId", str(STEAMAPPID))

func _process(delta: float) -> void:
	Steam.run_callbacks()

func initialize_steam() -> void:
	var initialize_response: Dictionary = Steam.steamInitEx()
	if initialize_response["status"] > 0:
		print("Failed to Initialize Steam! Error %s" % initialize_response)
		get_tree().quit()
	
	is_owned = Steam.isSubscribed()
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	
	print("steam id: %s" % steam_id)
	
	if !is_owned:
		print("Failed to find Ownership!")
		get_tree().quit()
