extends Node

# Scenes to pool
var BulletDecalScene := preload("res://bullet_decal.tscn")
var TerrainPartScene := preload("res://terrain_part.tscn")
var EnemyPartScene := preload("res://enemy_part.tscn")

# Pool settings
var pool_size = 30
var light_pool_size = 15

# Storage for the nodes
var decal_pool = []
var terrain_pool = []
var enemy_pool = []
var light_pool = []

# Current index trackers
var d_idx = 0
var t_idx = 0
var e_idx = 0
var l_idx = 0

func _ready():
	# Initialize all pools on startup
	for i in range(pool_size):
		decal_pool.append(create_instance(BulletDecalScene))
		terrain_pool.append(create_instance(TerrainPartScene))
		enemy_pool.append(create_instance(EnemyPartScene))
	
	for i in range(light_pool_size):
		var l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.4)
		l.light_energy = 0.5
		l.omni_range = 1.5
		l.visible = false
		add_child(l)
		light_pool.append(l)

func create_instance(scene: PackedScene) -> Node:
	var inst = scene.instantiate()
	add_child(inst)
	if inst is GPUParticles3D or inst is CPUParticles3D:
		inst.emitting = false
		inst.one_shot = true
	else:
		inst.visible = false
	return inst

# We add bullet_dir so we know which way the bullet was traveling
func spawn_impact(type: String, pos: Vector3, normal: Vector3, bullet_dir: Vector3):
	var node: Node
	
	match type:
		"decal":
			node = decal_pool[d_idx]
			d_idx = (d_idx + 1) % pool_size
		"terrain":
			node = terrain_pool[t_idx]
			t_idx = (t_idx + 1) % pool_size
		"enemy":
			node = enemy_pool[e_idx]
			e_idx = (e_idx + 1) % pool_size

	node.global_position = pos + (normal * 0.01)

	# 1. Determine the primary orientation (for decals/static effects)
	# If the normal is pointing straight up or down, change the 'up' vector
	if abs(normal.dot(Vector3.UP)) > 0.99:
		node.look_at(pos + normal, Vector3.FORWARD)
	else:
		node.look_at(pos + normal, Vector3.UP)

	# 2. Handle Particle-specific bounce directions
	if node is GPUParticles3D or node is CPUParticles3D:
		var bounce_dir = bullet_dir.reflect(normal).normalized()
		node.restart()
		node.emitting = true

		# Check if bounce_dir is colinear with UP
		if abs(bounce_dir.dot(Vector3.UP)) > 0.99:
			node.look_at(pos + bounce_dir, Vector3.FORWARD)
		else:
			node.look_at(pos + bounce_dir, Vector3.UP)
	else:
		node.visible = true 

	spawn_pooled_light(pos)
	
func spawn_pooled_light(pos: Vector3):
	var l = light_pool[l_idx]
	l_idx = (l_idx + 1) % light_pool_size
	
	l.global_position = pos
	l.visible = true
	
	# Hide the light after a tiny delay
	get_tree().create_timer(0.06).timeout.connect(func(): l.visible = false)
