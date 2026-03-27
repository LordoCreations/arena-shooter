class_name WeaponResource
extends Resource

var weapon_manager : WeaponManager

# First Person Perspective
@export var view_model : PackedScene

@export var view_model_pos : Vector3
@export var view_model_rot : Vector3
@export var view_model_scale := Vector3(1,1,1)

# Third Person Perspective
@export var world_model : PackedScene

@export var world_model_pos : Vector3
@export var world_model_rot : Vector3
@export var world_model_scale := Vector3(1,1,1)

# Animations
@export var view_idle_anim : String
@export var view_equip_anim : String
@export var view_shoot_anim : String
@export var view_reload_anim : String

# Weapon Stats
@export var damage: float = 10.0
@export var current_ammo: int = 12
@export var magazine_capacity: int = 12
@export var reserve_ammo: int = 36
@export var max_reserve_ammo: int = 120
@export var fire_rate_time: float = 0.2
@export var recoil_power: Vector2 = Vector2(0.5, 0.05)
@export var muzzle_flash_scene: PackedScene = preload("res://weapons/vfx/muzzle_flash.tscn")
@export var muzzle_flash_position: Vector3 = Vector3.ZERO

# Weapon Sounds
@export var shoot_sound : AudioStream
@export var reload_sound : AudioStream
@export var equip_sound : AudioStream

# Weapon Logic
var is_reloading := false
var _reload_start_time_ms := 0
var _reload_end_time_ms := 0

var trigger_down := false :
	set(v):
		if trigger_down != v:
			trigger_down = v
			if trigger_down:
				on_trigger_down()
			else:
				on_trigger_up()

var is_equipped := false :
	set(v):
		if is_equipped != v:
			is_equipped = v
			if is_equipped:
				on_equip()
			else:
				on_unequip()

func _manager_ready() -> bool:
	return weapon_manager != null and is_instance_valid(weapon_manager)

func on_trigger_down():
	pass


func on_trigger_up():
	pass

func on_equip():
	if not _manager_ready():
		return
	weapon_manager.play_anim(view_equip_anim)
	weapon_manager.queue_anim(view_idle_anim)


func on_unequip():
	is_reloading = false
	_reload_start_time_ms = 0
	_reload_end_time_ms = 0

func on_process(_delta: float) -> void:
	if not is_reloading:
		return
	if Time.get_ticks_msec() < _reload_end_time_ms:
		return
	reload()
	is_reloading = false
	_reload_start_time_ms = 0
	_reload_end_time_ms = 0

func can_fire_shot() -> bool:
	return current_ammo > 0 and not is_reloading

func get_amount_can_reload() -> int:
	if magazine_capacity <= 0:
		return 0
	var wish_reload = max(magazine_capacity - current_ammo, 0)
	return min(wish_reload, max(reserve_ammo, 0))

func reload_pressed() -> void:
	if not _manager_ready():
		return
	if is_reloading:
		return
	if get_amount_can_reload() <= 0:
		return
	var reload_duration := 0.0
	if view_reload_anim != "":
		reload_duration = weapon_manager.get_anim_length(view_reload_anim)
		weapon_manager.play_anim(view_reload_anim)
		weapon_manager.queue_anim(view_idle_anim)
	weapon_manager.play_sound(reload_sound)
	if reload_duration <= 0.0:
		reload()
		return
	is_reloading = true
	_reload_start_time_ms = Time.get_ticks_msec()
	_reload_end_time_ms = Time.get_ticks_msec() + int(reload_duration * 1000.0)

func get_reload_progress() -> float:
	if not is_reloading:
		return 0.0
	var total = float(_reload_end_time_ms - _reload_start_time_ms)
	if total <= 0.0:
		return 1.0
	var elapsed = float(Time.get_ticks_msec() - _reload_start_time_ms)
	return clamp(elapsed / total, 0.0, 1.0)

func reload() -> void:
	var can_reload = get_amount_can_reload()
	if can_reload <= 0:
		return
	current_ammo = min(magazine_capacity, current_ammo + can_reload)
	reserve_ammo = clamp(reserve_ammo - can_reload, 0, max_reserve_ammo)

func fire_shot():
	if not _manager_ready():
		return
	if not can_fire_shot():
		reload_pressed()
		return
	current_ammo -= 1
	weapon_manager.play_anim(view_shoot_anim)
	weapon_manager.play_sound(shoot_sound)
	weapon_manager.queue_anim(view_idle_anim)
