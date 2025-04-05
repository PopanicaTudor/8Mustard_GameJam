
extends Node2D

# Factor de scală al zonei exterioare (ex: 1.5 = 50% mai mare)
@export var outside_scale: float = 2.0

@onready var ground := $TileMapGround
@onready var obstacles := $TileMapObstacles
@onready var props := $TileMapProps

# Dimensiunea zonei principale (unde se generează pereții, apa)
@export var width: int = 128
@export var height: int = 128
@export var fill_percent: float = 23.0

# Raza cercului în care nu vrem pereți sau apă (rămâne ca la tine)
@export var restricted_radius: float = 20.0

# Harta principală (zona normală)
var map_data: Array = []

# Harta mare (exterior + interior)
var big_map_data: Array = []
var big_width: int
var big_height: int
var offset_x: int
var offset_y: int

# Tile-urile din atlas
@export var tile_floor: Vector2i = Vector2i(0, 0)
@export var tile_wall: Vector2i  = Vector2i(0, 0)

const SOURCE_FLOORS: int = 1
const SOURCE_WALLS: int = 0
const SOURCE_PROPS: int = 2

func _ready():
	# 1) Calculăm dimensiunea hărții mari
	big_width = int(width * outside_scale)
	big_height = int(height * outside_scale)
	
	# 2) Calculăm offset-ul unde să plasăm harta principală
	offset_x = int((big_width - width) / 2)
	offset_y = int((big_height - height) / 2)
	
	# 3) Generăm harta principală (map_data) prin cellular automata
	generate_map()

	# 4) Eliminăm pereții & apa în cercul restricted_radius din harta principală
	remove_walls_and_water_in_circle(restricted_radius)

	# 5) Creăm big_map_data = doar floor (0) peste tot
	create_big_map()

	# 6) Copiem map_data în interiorul lui big_map_data
	copy_map_data_to_big()
	
	# 7) Mapăm big_map_data în tilemap
	
	fill_tilemap()

	# 8) Plasăm props, apă, pereți (pe big_map_data)
	place_decor_prefabs()
	place_water_prefabs()
	place_wall_prefabs()
	create_level_boundaries()

# ----------------------------------------------------------------------------
# GENEREAZĂ HARTA PRINCIPALĂ (map_data) - EXACT CA ÎN SCRIPTUL TĂU
# ----------------------------------------------------------------------------

func create_level_boundaries():
	var tile_size = 16
	var margin = 340  # cât să intrăm spre centru
	var bounds = StaticBody2D.new()
	bounds.name = "LevelBounds"
	add_child(bounds)

	var thickness = 16

	var map_pixel_width = big_width * tile_size
	var map_pixel_height = big_height * tile_size

	# SUS
	var top = CollisionShape2D.new()
	top.shape = RectangleShape2D.new()
	top.shape.extents = Vector2((map_pixel_width - margin * 2) / 2, thickness / 2)
	top.position = Vector2(map_pixel_width / 2, margin - thickness / 2)
	bounds.add_child(top)

	# JOS
	var bottom = CollisionShape2D.new()
	bottom.shape = RectangleShape2D.new()
	bottom.shape.extents = Vector2((map_pixel_width - margin * 2) / 2, thickness / 2)
	bottom.position = Vector2(map_pixel_width / 2, map_pixel_height - margin + thickness / 2)
	bounds.add_child(bottom)

	# STÂNGA
	var left = CollisionShape2D.new()
	left.shape = RectangleShape2D.new()
	left.shape.extents = Vector2(thickness / 2, (map_pixel_height - margin * 2) / 2)
	left.position = Vector2((margin + 230) - thickness / 2, map_pixel_height / 2)
	bounds.add_child(left)

	# DREAPTA
	var right = CollisionShape2D.new()
	right.shape = RectangleShape2D.new()
	right.shape.extents = Vector2(thickness / 2, (map_pixel_height - margin * 2) / 2)
	right.position = Vector2(map_pixel_width - margin + thickness / 2, map_pixel_height / 2)
	bounds.add_child(right)

func generate_map():
	randomize()
	map_data.resize(width)
	for x in range(width):
		map_data[x] = []
		for y in range(height):
			if randf() * 100 < fill_percent:
				map_data[x].append(1)
			else:
				map_data[x].append(0)
	# 2 pași de simulare
	for i in range(2):
		map_data = simulation_step(map_data)

func simulation_step(old_map: Array) -> Array:
	var new_map := []
	new_map.resize(width)
	for x in range(width):
		new_map[x] = []
		for y in range(height):
			var n = count_neighbors(old_map, x, y)
			if n > 4:
				new_map[x].append(1)
			else:
				new_map[x].append(0)
	return new_map

func count_neighbors(grid: Array, cx: int, cy: int) -> int:
	var c = 0
	for nx in range(cx - 1, cx + 2):
		for ny in range(cy - 1, cy + 2):
			if nx == cx and ny == cy: continue
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				c += 1
			elif grid[nx][ny] == 1:
				c += 1
	return c

# ----------------------------------------------------------------------------
# RESTRICTED RADIUS
# ----------------------------------------------------------------------------
func remove_walls_and_water_in_circle(radius: float):
	for x in range(width):
		for y in range(height):
			var dx = x - 1150
			var dy = y - 637
			var dist = sqrt(float(dx*dx + dy*dy))
			if dist < radius:
				# Forțăm tile-ul să fie 0 (podea)
				map_data[x][y] = 0  # forțăm podea

# ----------------------------------------------------------------------------
# CREATE BIG_MAP (EXTERIOR)
# ----------------------------------------------------------------------------
func create_big_map():
	big_map_data.resize(big_width)
	for x in range(big_width):
		big_map_data[x] = []
		for y in range(big_height):
			# Exterior default = 0 (floor)
			big_map_data[x].append(0)

# ----------------------------------------------------------------------------
# COPY map_data (zona principală) ÎN big_map_data
# ----------------------------------------------------------------------------
func copy_map_data_to_big():
	for x in range(width):
		for y in range(height):
			big_map_data[offset_x + x][offset_y + y] = map_data[x][y]

# ----------------------------------------------------------------------------
# MAPĂM big_map_data ÎN TILEMAP
# ----------------------------------------------------------------------------
func fill_tilemap():
	ground.clear()
	obstacles.clear()
	props.clear()
	for x in range(big_width):
		for y in range(big_height):
			if big_map_data[x][y] == 1:
				if can_place_wall(x, y):
					obstacles.set_cell(Vector2i(x, y), SOURCE_WALLS, tile_wall)
			else:
				ground.set_cell(Vector2i(x, y), SOURCE_FLOORS, tile_floor)

func can_place_wall(x:int, y:int, radius:int=1, max_walls:float=4) -> bool:
	var c=0
	for i in range(x - radius, x + radius + 1):
		for j in range(y - radius, y + radius + 1):
			if i==x and j==y: continue
			if i<0 or j<0 or i>=big_width or j>=big_height:
				c+=1
			elif big_map_data[i][j] == 1:
				c+=1
	return c<max_walls

# ----------------------------------------------------------------------------
# DECO
# ----------------------------------------------------------------------------
func place_decor_prefabs():
	var decor_scenes = [
		preload("res://Assets/Prefabs/prop_1.tscn"),
		preload("res://Assets/Prefabs/prop_2.tscn"),
		preload("res://Assets/Prefabs/prop_3.tscn")
	]
	for x in range(big_width):
		for y in range(big_height):
			if big_map_data[x][y] == 0 and can_place_decor(x,y,1) and randf()<0.15:
				var scn = decor_scenes[randi() % decor_scenes.size()]
				var inst = scn.instantiate()
				inst.position = Vector2(x,y)*16
				inst.z_index=0
				add_child(inst)

func can_place_decor(x:int, y:int, radius:int=1) -> bool:
	for i in range(x - radius, x + radius + 1):
		for j in range(y - radius, y + radius + 1):
			if i<0 or j<0 or i>=big_width or j>=big_height:
				continue
			if big_map_data[i][j] == 1:
				return false
	return true

# ----------------------------------------------------------------------------
# WATER
# ----------------------------------------------------------------------------
func place_water_prefabs():
	var water_scenes = [
		preload("res://Assets/Prefabs/water.tscn")
	]
	for x in range(big_width):
		for y in range(big_height):
			if big_map_data[x][y] == 0 and can_place_decor(x,y,1) and randf()<0.002:
				var scn = water_scenes[randi() % water_scenes.size()]
				var inst = scn.instantiate()
				inst.position = Vector2(x,y)*16
				inst.z_index=0
				add_child(inst)

# ----------------------------------------------------------------------------
# WALLS
# ----------------------------------------------------------------------------
func place_wall_prefabs():
	var wall_scenes = [
		preload("res://Assets/Prefabs/wall_1.tscn"),
		preload("res://Assets/Prefabs/wall_2.tscn"),
		preload("res://Assets/Prefabs/wall_3.tscn")
	]
	for x in range(big_width):
		for y in range(big_height):
			if big_map_data[x][y] == 1:
				if can_place_wall(x, y):
					var scn = wall_scenes[randi() % wall_scenes.size()]
					var inst = scn.instantiate()
					inst.position = Vector2(x,y)*16
					inst.z_index=1
					add_child(inst)
