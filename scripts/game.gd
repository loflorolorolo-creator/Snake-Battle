extends Node2D

const WORLD_SIZE := Vector2(4200, 3000)
const FOOD_COUNT := 260
const BOT_COUNT := 9
const SEGMENT_GAP := 17.0
const START_LENGTH := 14
const NORMAL_SPEED := 190.0
const BOOST_SPEED := 285.0

var rng := RandomNumberGenerator.new()
var state := "menu"
var snake: Array[Vector2] = []
var foods: Array[Vector3] = [] # x, y, value
var bots: Array = []
var heading := Vector2.RIGHT
var desired_heading := Vector2.RIGHT
var mass := 12
var score := 0
var stamina := 100.0
var boosting := false
var pointer_down := false
var pointer_pos := Vector2.ZERO
var joy_origin := Vector2.ZERO
var joy_vector := Vector2.ZERO
var boost_rect := Rect2()
var touch_start := Vector2.ZERO
var camera_pos := Vector2.ZERO
var message := ""
var message_time := 0.0
var paused_from := "game"

func _ready() -> void:
	rng.randomize()
	_refresh_controls()
	var music := AudioStreamPlayer.new()
	music.name = "AmbientMusic"
	music.stream = load("res://audio/plains_ambient.wav")
	music.volume_db = -13.0
	add_child(music)
	music.play()
	seed_world()
	set_process(true)
	set_process_input(true)

func seed_world() -> void:
	foods.clear()
	bots.clear()
	for i in FOOD_COUNT:
		spawn_food()
	for i in BOT_COUNT:
		var pos := Vector2(rng.randf_range(300, WORLD_SIZE.x-300), rng.randf_range(300, WORLD_SIZE.y-300))
		var body: Array[Vector2] = []
		var dir := Vector2.RIGHT.rotated(rng.randf_range(-PI, PI))
		for j in 13:
			body.append(pos - dir * j * SEGMENT_GAP)
		bots.append({"body": body, "dir": dir, "turn": rng.randf_range(0.5, 2.0), "color": Color.from_hsv(rng.randf(), .72, .95), "alive": true})

func spawn_food() -> void:
	foods.append(Vector3(rng.randf_range(100, WORLD_SIZE.x-100), rng.randf_range(100, WORLD_SIZE.y-100), rng.randi_range(1,3)))

func start_game() -> void:
	state = "game"
	mass = 12
	score = 0
	stamina = 100.0
	heading = Vector2.RIGHT
	desired_heading = heading
	snake.clear()
	var start := Vector2(780, 740)
	for i in START_LENGTH:
		snake.append(start - Vector2(i*SEGMENT_GAP, 0))
	camera_pos = start
	message = "Собирай светящиеся сферы и расти!"
	message_time = 3.0

func _process(delta: float) -> void:
	_refresh_controls()
	if state == "game":
		update_game(delta)
	if message_time > 0:
		message_time -= delta
	queue_redraw()

func _refresh_controls() -> void:
	var size := get_viewport_rect().size
	joy_origin = Vector2(size.x * 0.12, size.y * 0.82)
	boost_rect = Rect2(size.x - 205, size.y - 160, 170, 140)

func update_game(delta: float) -> void:
	var target := desired_heading
	if target.length() > 0.1:
		var angle := heading.angle_to(target)
		var max_turn := 2.7 * delta
		heading = heading.rotated(clamp(angle, -max_turn, max_turn)).normalized()
	boosting = Input.is_key_pressed(KEY_SPACE) or (pointer_down and boost_rect.has_point(pointer_pos))
	var speed := NORMAL_SPEED
	if boosting and stamina > 0:
		speed = BOOST_SPEED
		stamina = max(0.0, stamina - 34.0 * delta)
	else:
		stamina = min(100.0, stamina + 21.0 * delta)
	var next_pos := snake[0] + heading * speed * delta
	if next_pos.x < 45 or next_pos.y < 45 or next_pos.x > WORLD_SIZE.x-45 or next_pos.y > WORLD_SIZE.y-45:
		heading = heading.rotated(PI * 0.65)
		next_pos = snake[0] + heading * speed * delta
	snake.push_front(next_pos)
	for i in range(10, snake.size()):
		if snake[i].distance_to(snake[0]) < 15:
			end_game()
			return
	while snake.size() > START_LENGTH + mass * 2:
		snake.pop_back()
	for i in range(foods.size()-1, -1, -1):
		var p := Vector2(foods[i].x, foods[i].y)
		if p.distance_to(snake[0]) < 24:
			score += int(foods[i].z)
			mass += int(foods[i].z)
			foods.remove_at(i)
			spawn_food()
	for bot in bots:
		if not bot.get("alive", true):
			continue
		update_bot(bot, delta)
		for j in range(2, bot.body.size()):
			if bot.body[j].distance_to(snake[0]) < 19:
				end_game()
				return
		if bot.body[0].distance_to(snake[0]) < 20:
			bot.alive = false
			for k in range(7):
				foods.append(Vector3(bot.body[0].x + rng.randf_range(-35,35), bot.body[0].y + rng.randf_range(-35,35), 2))
		for i in range(foods.size()-1, -1, -1):
			if Vector2(foods[i].x, foods[i].y).distance_to(bot.body[0]) < 19:
				foods.remove_at(i)
				spawn_food()
	camera_pos = camera_pos.lerp(snake[0], min(1.0, delta*5.5))

func update_bot(bot: Dictionary, delta: float) -> void:
	bot.turn -= delta
	if bot.turn <= 0:
		bot.dir = bot.dir.rotated(rng.randf_range(-1.0, 1.0)).normalized()
		bot.turn = rng.randf_range(.45, 1.8)
	var body: Array = bot.body
	var head: Vector2 = body[0]
	var next := head + bot.dir * 112.0 * delta
	if next.x < 80 or next.y < 80 or next.x > WORLD_SIZE.x-80 or next.y > WORLD_SIZE.y-80:
		bot.dir = (Vector2(WORLD_SIZE.x/2, WORLD_SIZE.y/2)-head).normalized()
		next = head + bot.dir * 112.0 * delta
	body.push_front(next)
	while body.size() > 25:
		body.pop_back()
	bot.body = body

func end_game() -> void:
	state = "dead"
	message = "Змейка погибла — матч завершён"
	message_time = 4.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_down = true
			pointer_pos = event.position
			touch_start = event.position
			_handle_press(event.position)
		else:
			pointer_down = false
			boosting = false
			joy_vector = Vector2.ZERO
	elif event is InputEventScreenDrag:
		pointer_pos = event.position
		if state == "game" and touch_start.x < get_viewport_rect().size.x * 0.52:
			var delta_from_start := event.position - touch_start
			joy_vector = delta_from_start.limit_length(95.0) / 95.0
			if joy_vector.length() > 0.18:
				desired_heading = joy_vector.normalized()
	elif event is InputEventMouseButton:
		if event.pressed:
			pointer_down = true
			pointer_pos = event.position
			touch_start = event.position
			_handle_press(event.position)
		else:
			pointer_down = false
			boosting = false
			joy_vector = Vector2.ZERO
	elif event is InputEventMouseMotion and pointer_down and state == "game":
		pointer_pos = event.position
		if touch_start.x < get_viewport_rect().size.x * 0.52:
			joy_vector = (event.position - touch_start).limit_length(95.0) / 95.0
			if joy_vector.length() > 0.18:
				desired_heading = joy_vector.normalized()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			boosting = true
		if event.keycode == KEY_ESCAPE:
			if state == "game": state = "pause"
			elif state == "pause": state = "game"
		if event.keycode == KEY_ENTER and state in ["menu", "dead"]:
			start_game()
		if event.keycode == KEY_UP: desired_heading = Vector2.UP
		if event.keycode == KEY_DOWN: desired_heading = Vector2.DOWN
		if event.keycode == KEY_LEFT: desired_heading = Vector2.LEFT
		if event.keycode == KEY_RIGHT: desired_heading = Vector2.RIGHT

func _handle_press(pos: Vector2) -> void:
	var size := get_viewport_rect().size
	if state == "menu":
		start_game()
	elif state == "dead":
		state = "menu"
	elif state == "pause":
		state = "game"
	elif state == "game":
		if pos.x > size.x - 90 and pos.y < 90:
			state = "pause"
		elif boost_rect.has_point(pos):
			boosting = true

func _draw() -> void:
	var size := get_viewport_rect().size
	if state == "menu":
		draw_menu(size)
	else:
		draw_world(size)
		draw_hud(size)
		if state == "pause":
			draw_overlay(size, "ПАУЗА", "Нажми в любом месте, чтобы продолжить")
		elif state == "dead":
			draw_overlay(size, "МАТЧ ОКОНЧЕН", "Коснись экрана, чтобы вернуться в меню")
		if message_time > 0 and state == "game":
			draw_string(ThemeDB.fallback_font, Vector2(size.x/2-230, 78), message, HORIZONTAL_ALIGNMENT_CENTER, 460, 22, Color.WHITE)

func world_to_screen(p: Vector2, size: Vector2) -> Vector2:
	return p - camera_pos + size/2

func draw_world(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#356b42"))
	# Four connected regions around the central ancient ruins.
	var biome := _biome_at(camera_pos)
	var ground := Color("#3c7848")
	match biome:
		"volcano": ground = Color("#493c39")
		"caves": ground = Color("#303d49")
		"ice": ground = Color("#9bcbd5")
		"ruins": ground = Color("#686052")
	draw_rect(Rect2(Vector2.ZERO, size), ground)
	# Stylized terrain with soft patches and natural biome transitions
	for x in range(-1, 18):
		for y in range(-1, 12):
			var wx := floor(camera_pos.x/240)*240 + x*240
			var wy := floor(camera_pos.y/240)*240 + y*240
			var p := world_to_screen(Vector2(wx,wy), size)
			var col := _ground_color(Vector2(wx, wy))
			draw_circle(p, 145, col)
	for i in range(foods.size()):
		var p := world_to_screen(Vector2(foods[i].x, foods[i].y), size)
		if p.x > -30 and p.x < size.x+30 and p.y > -30 and p.y < size.y+30:
			var c := [Color("#ffe66d"), Color("#ff9f68"), Color("#8cf5e8")][int(foods[i].z)-1]
			draw_circle(p, 13, Color(c, .18))
			draw_circle(p, 7, c)
			draw_circle(p+Vector2(-2,-2), 2.5, Color.WHITE)
	for bot in bots:
		if bot.get("alive", true):
			draw_snake(bot.body, bot.color, size, false)
	draw_snake(snake, Color("#20d8c4"), size, true)
	# world boundary indicator
	var tl := world_to_screen(Vector2.ZERO, size)
	var br := world_to_screen(WORLD_SIZE, size)
	draw_rect(Rect2(tl, br-tl), Color("#a4d7b0"), false, 8)

func _biome_at(p: Vector2) -> String:
	var nx := p.x / WORLD_SIZE.x
	var ny := p.y / WORLD_SIZE.y
	if abs(nx - 0.5) < 0.16 and abs(ny - 0.5) < 0.18:
		return "ruins"
	if nx < 0.5 and ny < 0.5: return "plains"
	if nx >= 0.5 and ny < 0.5: return "volcano"
	if nx < 0.5 and ny >= 0.5: return "caves"
	return "ice"

func _ground_color(p: Vector2) -> Color:
	var base: Color
	match _biome_at(p):
		"volcano": base = Color("#51413a") if int(p.x/240 + p.y/240) % 2 == 0 else Color("#493a35")
		"caves": base = Color("#35434d") if int(p.x/240 + p.y/240) % 2 == 0 else Color("#303d47")
		"ice": base = Color("#a7d6df") if int(p.x/240 + p.y/240) % 2 == 0 else Color("#96c8d4")
		"ruins": base = Color("#756b58") if int(p.x/240 + p.y/240) % 2 == 0 else Color("#695f50")
		_: base = Color("#3c7848") if int(p.x/240 + p.y/240) % 2 == 0 else Color("#397044")
	return base

func draw_snake(body: Array, color: Color, size: Vector2, player: bool) -> void:
	for i in range(body.size()-1, -1, -1):
		var p: Vector2 = world_to_screen(body[i], size)
		var r := (12.5 if player else 10.0) * (1.0 - float(i)/max(1,body.size())*.24)
		draw_circle(p+Vector2(2,4), r+1, Color(0,0,0,.22))
		draw_circle(p, r, color.darkened(float(i)/max(1,body.size())*.22))
		draw_arc(p, r*.78, -2.6, -.5, 18, color.lightened(.42), 2.2)
		if i < body.size()-1:
			var toward_next: Vector2 = world_to_screen(body[i+1], size)
			draw_line(p, toward_next, r*1.35, color.darkened(.12), true)
	var h: Vector2 = world_to_screen(body[0], size)
	var forward := heading if player else Vector2.RIGHT
	if not player and body.size()>1: forward = (body[0]-body[1]).normalized()
	var side := forward.rotated(PI/2)
	for sign in [-1,1]:
		var eye := h + forward*5 + side*sign*5
		draw_circle(eye, 3.4, Color.WHITE)
		draw_circle(eye+forward*1.3, 1.8, Color("#15202a"))

func draw_hud(size: Vector2) -> void:
	draw_rect(Rect2(18,16,260,64), Color(0.025,.08,.13,.78), true, 16)
	draw_string(ThemeDB.fallback_font, Vector2(36,43), "МАССА  %d" % mass, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(36,68), "ЕДА  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#b9eee5"))
	draw_rect(Rect2(size.x/2-100,20,200,15), Color(.05,.08,.12,.8), true, 7)
	draw_rect(Rect2(size.x/2-98,22,196*stamina/100.0,11), Color("#5be6c1"), true, 5)
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-30,58), "ВЫНОСЛИВОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color.WHITE)
	# Mini-map
	draw_circle(Vector2(size.x-90,92), 64, Color(.02,.08,.12,.82))
	draw_circle(Vector2(size.x-90,92), 56, Color("#548d66"))
	draw_circle(Vector2(size.x-90+(snake[0].x/WORLD_SIZE.x-0.5)*100,92+(snake[0].y/WORLD_SIZE.y-0.5)*100),4,Color("#fff18a"))
	# Touch joystick
	draw_circle(joy_origin, 70, Color(.02,.07,.1,.38))
	draw_circle(joy_origin, 57, Color(.7,.95,.9,.13))
	draw_circle(joy_origin + joy_vector*48, 24, Color(.85,1,1,.48))
	draw_circle(boost_rect.get_center(), 67, Color(.25,.08,.06,.42))
	draw_circle(boost_rect.get_center(), 53, Color("#ec874e"))
	draw_string(ThemeDB.fallback_font, boost_rect.get_center() + Vector2(-47,7), "УСКОР", HORIZONTAL_ALIGNMENT_CENTER, 95, 20, Color.WHITE)
	draw_circle(Vector2(size.x-48,42), 25, Color(.02,.07,.1,.65))
	draw_string(ThemeDB.fallback_font, Vector2(size.x-60,50), "Ⅱ", HORIZONTAL_ALIGNMENT_CENTER, 24, 20, Color.WHITE)

func draw_menu(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO,size), Color("#102b36"))
	for i in 20:
		var p := Vector2(fposmod(i*211.0, size.x), fposmod(i*137.0,size.y))
		draw_circle(p, 38, Color("#1d4650"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-235, size.y*.28), "SNAKE BATTLE", HORIZONTAL_ALIGNMENT_CENTER, 470, 58, Color("#ffe28a"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-180, size.y*.37), "ОСТРОВ ЧЕТЫРЁХ БИОМОВ", HORIZONTAL_ALIGNMENT_CENTER, 360, 21, Color("#9de8dc"))
	draw_circle(Vector2(size.x/2,size.y*.56), 74, Color("#20d8c4"))
	draw_circle(Vector2(size.x/2-20,size.y*.54), 9, Color.WHITE)
	draw_circle(Vector2(size.x/2+20,size.y*.54), 9, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-130,size.y*.82), "КОСНИСЬ ЭКРАНА, ЧТОБЫ ИГРАТЬ", HORIZONTAL_ALIGNMENT_CENTER, 260, 20, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-150,size.y*.9), "Первая тестовая сборка", HORIZONTAL_ALIGNMENT_CENTER, 300, 14, Color("#b5d6d0"))

func draw_overlay(size: Vector2, title: String, subtitle: String) -> void:
	draw_rect(Rect2(Vector2.ZERO,size), Color(0,0,0,.62))
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-220,size.y*.46), title, HORIZONTAL_ALIGNMENT_CENTER, 440, 42, Color("#ffe28a"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x/2-280,size.y*.55), subtitle, HORIZONTAL_ALIGNMENT_CENTER, 560, 20, Color.WHITE)
