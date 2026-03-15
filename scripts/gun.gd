extends Node3D

@export var fire_rate_time: float = 0.25
@export var recoil_power: Vector2 = Vector2(2, 0.03)

@onready var fire_rate_timer: Timer = $Firerate
@onready var flash_parent = $Pistol/MuzzleFlash
@onready var bullet_cast: RayCast3D = $Pistol/RayCast3D

var can_shoot: bool = true
var muzzle_flash_scene := preload("res://scenes/muzzle_flash.tscn")

func _ready() -> void:
	fire_rate_timer.wait_time = fire_rate_time

func try_shoot() -> bool:
	if not can_shoot:
		return false
	can_shoot = false
	fire_rate_timer.start()
	return true

@rpc("call_local")
func play_fire_effects() -> void:
	var flash = muzzle_flash_scene.instantiate()
	flash_parent.add_child(flash)
	flash.global_transform = flash_parent.global_transform
	flash.emitting = true

func _on_firerate_timeout() -> void:
	can_shoot = true
