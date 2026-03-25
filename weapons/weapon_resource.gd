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
@export var damage = 10;

# Weapon Sounds
@export var shoot_sound : AudioStream
@export var reload_sound : AudioStream
@export var equip_sound : AudioStream

# Weapon Logic
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

func on_trigger_down():
	fire_shot()


func on_trigger_up():
	pass

func on_equip():
	weapon_manager.play_anim(view_equip_anim)
	weapon_manager.queue_anim(view_idle_anim)


func on_unequip():
	pass

func fire_shot():
	weapon_manager.play_anim(view_shoot_anim)
	weapon_manager.play_sound(shoot_sound)
	weapon_manager.queue_anim(view_idle_anim)
