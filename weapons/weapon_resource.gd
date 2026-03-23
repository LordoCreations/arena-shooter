class_name WeaponResource
extends Resource

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
