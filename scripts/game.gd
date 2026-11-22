extends Node2D

const WORLD_SIZE: Vector2 = Vector2(4200.0, 3000.0)
const FOOD_COUNT: int = 260
const BOT_COUNT: int = 9
const SEGMENT_GAP: float = 17.0
const START_LENGTH: int = 14
const NORMAL_SPEED: float = 190.0
const BOOST_SPEED: float = 285.0
const TURN_RATE: float = 3.2
const SPEED_RESPONSE: float = 5.0
const CAMERA_RESPONSE: float = 5.5
const BOOST_DRAIN: float = 34.0
const STAMINA_REGEN: float = 21.0
const BOOST_TOUCH_RADIUS: float = 78.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var state: String = "menu"
var snake: Array[Vector2] = []
var foods: Array[Vector3] = []
var bots: Array = []
var heading: Vector2 = Vector2.RIGHT
var desired_heading: Vector2 = Vector2.RIGHT
var mass: int = 12
var visual_mass: float = 12.0
var score: int = 0
var stamina: float = 100.0
var boosting: bool = false
var current_speed: float = NORMAL_SPEED
var pointer_down: bool = false
var pointer_pos: Vector2 = Vector2.ZERO
var joy_origin: Vector2 = Vector2.ZERO
var joy_vector: Vector2 = Vector2.ZERO
var boost_rect: Rect2 = Rect2()
var boost_touch_active: bool = false
var boost_touch_pos: Vector2 = Vector2.ZERO
var touch_start: Vector2 = Vector2.ZERO
var touch_mode: String = ""
var steer_touch_index: int = -1
var boost_touch_index: int = -1
var steer_touch_start: Vector2 = Vector2.ZERO
var mouse_control_mode: String = ""
var camera_pos: Vector2 = Vector2.ZERO
var message: String = ""
var message_time: float = 0.0

func _ready() -> void:
    rng.randomize()
    _refresh_controls()
    var music: AudioStreamPlayer = AudioStreamPlayer.new()
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
    for i in range(FOOD_COUNT):
        spawn_food()
    for i in range(BOT_COUNT):
        var pos: Vector2 = Vector2(rng.randf_range(300.0, WORLD_SIZE.x - 300.0), rng.randf_range(300.0, WORLD_SIZE.y - 300.0))
        var body: Array[Vector2] = []
        var dir: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(-PI, PI))
        for j in range(13):
            body.append(pos - dir * float(j) * SEGMENT_GAP)
        bots.append({"body": body, "dir": dir, "turn": rng.randf_range(0.5, 2.0), "color": Color.from_hsv(rng.randf(), 0.72, 0.95), "alive": true, "mass": 12})

func spawn_food() -> void:
    foods.append(Vector3(rng.randf_range(100.0, WORLD_SIZE.x - 100.0), rng.randf_range(100.0, WORLD_SIZE.y - 100.0), float(rng.randi_range(1, 3))))

func start_game() -> void:
    state = "game"
    mass = 12
    visual_mass = 12.0
    score = 0
    stamina = 100.0
    _clear_controls()
    current_speed = NORMAL_SPEED
    heading = Vector2.RIGHT
    desired_heading = heading
    snake.clear()
    var start: Vector2 = Vector2(780.0, 740.0)
    for i in range(START_LENGTH):
        snake.append(start - Vector2(float(i) * SEGMENT_GAP, 0.0))
    camera_pos = start
    message = "Собирай светящиеся сферы и расти!"
    message_time = 3.0

func _process(delta: float) -> void:
    _refresh_controls()
    if state == "game":
        update_game(delta)
    if message_time > 0.0:
        message_time -= delta
    queue_redraw()

func _refresh_controls() -> void:
    var viewport_size: Vector2 = get_viewport_rect().size
    joy_origin = Vector2(viewport_size.x * 0.12, viewport_size.y * 0.82)
    boost_rect = Rect2(viewport_size.x - 145.0, viewport_size.y - 145.0, 125.0, 125.0)

func _snake_radius(is_player: bool, index: int, body_size: int, mass_override: float = -1.0) -> float:
    var base_radius: float = 12.5 if is_player else 10.0
    # Player body scale follows mass smoothly instead of jumping after each food pickup.
    var current_mass: float = visual_mass if is_player else (mass_override if mass_override >= 0.0 else 12.0)
    var growth: float = clampf((current_mass - 12.0) / 110.0, 0.0, 1.0)
    # A gentle taper keeps the head readable while the whole body becomes thicker.
    var taper: float = 1.0 - float(index) / float(maxi(1, body_size)) * 0.20
    return base_radius * (1.0 + growth * 0.85) * taper

func update_game(delta: float) -> void:
    if snake.is_empty():
        return
    # Smoothly animate the visible segment thickness toward the actual collected mass.
    visual_mass = move_toward(visual_mass, float(mass), maxf(1.0, float(mass) * 0.9) * delta)
    var target: Vector2 = desired_heading
    if target.length() > 0.1:
        var angle: float = heading.angle_to(target)
        heading = heading.rotated(clampf(angle, -TURN_RATE * delta, TURN_RATE * delta)).normalized()
    boosting = (Input.is_key_pressed(KEY_SPACE) or boost_touch_active) and stamina > 0.0
    var target_speed: float = BOOST_SPEED if boosting else NORMAL_SPEED
    current_speed = lerpf(current_speed, target_speed, 1.0 - exp(-SPEED_RESPONSE * delta))
    if boosting:
        stamina = maxf(0.0, stamina - BOOST_DRAIN * delta)
    else:
        stamina = minf(100.0, stamina + STAMINA_REGEN * delta)
    var next_pos: Vector2 = snake[0] + heading * current_speed * delta
    if next_pos.x < 45.0 or next_pos.y < 45.0 or next_pos.x > WORLD_SIZE.x - 45.0 or next_pos.y > WORLD_SIZE.y - 45.0:
        heading = heading.rotated(PI * 0.65)
        desired_heading = heading
        next_pos = snake[0] + heading * current_speed * delta
    snake.push_front(next_pos)
    # Keep body spacing stable across different device frame rates.
    for segment_index in range(1, snake.size()):
        var segment_delta: Vector2 = snake[segment_index] - snake[segment_index - 1]
        var segment_distance: float = segment_delta.length()
        if segment_distance > SEGMENT_GAP and segment_distance > 0.001:
            snake[segment_index] = snake[segment_index - 1] + segment_delta / segment_distance * SEGMENT_GAP
    # Body contact with the player's own snake is deliberately harmless.
    while snake.size() > START_LENGTH + mass * 2:
        snake.pop_back()
    for i in range(foods.size() - 1, -1, -1):
        var food_pos: Vector2 = Vector2(foods[i].x, foods[i].y)
        if food_pos.distance_to(snake[0]) < 24.0 + _snake_radius(true, 0, snake.size()) * 0.25:
            var gained: int = int(foods[i].z)
            score += gained
            mass += gained
            foods.remove_at(i)
            spawn_food()
    for bot in bots:
        if not bot.get("alive", true):
            continue
        update_bot(bot, delta)
        var bot_body: Array = bot.body
        var bot_mass: int = int(bot.get("mass", 12))
        var player_head_radius: float = _snake_radius(true, 0, snake.size())
        var bot_head_radius: float = _snake_radius(false, 0, bot_body.size(), float(bot_mass))
        var head_distance: float = bot_body[0].distance_to(snake[0])
        if head_distance < player_head_radius + bot_head_radius:
            if mass > bot_mass:
                bot.alive = false
                _drop_bot_food(bot_body[0])
                continue
            else:
                end_game()
                return
        for j in range(2, bot_body.size()):
            if bot_body[j].distance_to(snake[0]) < player_head_radius + _snake_radius(false, j, bot_body.size(), float(bot_mass)):
                end_game()
                return
        var bot_destroyed: bool = false
        for j in range(2, snake.size()):
            if snake[j].distance_to(bot_body[0]) < bot_head_radius + _snake_radius(true, j, snake.size()):
                bot.alive = false
                _drop_bot_food(bot_body[0])
                bot_destroyed = true
                break
        if bot_destroyed:
            continue
        for i in range(foods.size() - 1, -1, -1):
            if Vector2(foods[i].x, foods[i].y).distance_to(bot_body[0]) < 19.0:
                foods.remove_at(i)
                spawn_food()
    camera_pos = camera_pos.lerp(snake[0], 1.0 - exp(-CAMERA_RESPONSE * delta))

func _drop_bot_food(position: Vector2) -> void:
    for k in range(7):
        foods.append(Vector3(position.x + rng.randf_range(-35.0, 35.0), position.y + rng.randf_range(-35.0, 35.0), 2.0))

func update_bot(bot: Dictionary, delta: float) -> void:
    bot.turn = float(bot.turn) - delta
    var bot_dir: Vector2 = bot.dir
    if bot.turn <= 0.0:
        bot_dir = bot_dir.rotated(rng.randf_range(-1.0, 1.0)).normalized()
        bot.dir = bot_dir
        bot.turn = rng.randf_range(0.45, 1.8)
    var body: Array = bot.body
    var head: Vector2 = body[0]
    var next_position: Vector2 = head + bot_dir * 112.0 * delta
    if next_position.x < 80.0 or next_position.y < 80.0 or next_position.x > WORLD_SIZE.x - 80.0 or next_position.y > WORLD_SIZE.y - 80.0:
        bot_dir = (Vector2(WORLD_SIZE.x / 2.0, WORLD_SIZE.y / 2.0) - head).normalized()
        bot.dir = bot_dir
        next_position = head + bot_dir * 112.0 * delta
    body.push_front(next_position)
    while body.size() > 25:
        body.pop_back()
    bot.body = body

func _clear_controls() -> void:
    boosting = false
    boost_touch_active = false
    steer_touch_index = -1
    boost_touch_index = -1
    mouse_control_mode = ""
    joy_vector = Vector2.ZERO
    touch_mode = ""

func end_game() -> void:
    state = "dead"
    _clear_controls()
    message = "Змейка погибла — матч завершён"
    message_time = 4.0

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            if state == "game":
                _begin_touch_control(event.index, event.position)
            else:
                _handle_press(event.position)
        else:
            _end_touch_control(event.index)
    elif event is InputEventScreenDrag:
        _move_touch_control(event.index, event.position)
    elif event is InputEventMouseButton:
        if event.pressed:
            _begin_mouse_control(event.position)
        else:
            _end_mouse_control()
    elif event is InputEventMouseMotion and not mouse_control_mode.is_empty():
        _move_mouse_control(event.position)
    elif event is InputEventKey and event.pressed:
        if event.keycode == KEY_SPACE:
            boosting = true
        elif event.keycode == KEY_ESCAPE:
            if state == "game":
                state = "pause"
            elif state == "pause":
                state = "game"
        elif event.keycode == KEY_ENTER and state in ["menu", "dead"]:
            start_game()
        elif event.keycode == KEY_UP:
            desired_heading = Vector2.UP
        elif event.keycode == KEY_DOWN:
            desired_heading = Vector2.DOWN
        elif event.keycode == KEY_LEFT:
            desired_heading = Vector2.LEFT
        elif event.keycode == KEY_RIGHT:
            desired_heading = Vector2.RIGHT

func _begin_touch_control(index: int, pos: Vector2) -> void:
    var viewport_size: Vector2 = get_viewport_rect().size
    if pos.x > viewport_size.x - 90.0 and pos.y < 90.0:
        state = "pause"
        _clear_controls()
        return
    if pos.x < viewport_size.x * 0.5 and steer_touch_index == -1:
        steer_touch_index = index
        steer_touch_start = pos
        joy_vector = Vector2.ZERO
    elif pos.x >= viewport_size.x * 0.5 and boost_touch_index == -1:
        boost_touch_index = index
        boost_touch_active = true
        boost_touch_pos = pos

func _move_touch_control(index: int, pos: Vector2) -> void:
    if index == steer_touch_index:
        var drag_delta: Vector2 = pos - steer_touch_start
        joy_vector = drag_delta.limit_length(105.0) / 105.0
        if joy_vector.length() > 0.12:
            desired_heading = joy_vector.normalized()
    elif index == boost_touch_index:
        boost_touch_pos = pos
        boost_touch_active = true

func _end_touch_control(index: int) -> void:
    if index == steer_touch_index:
        steer_touch_index = -1
        joy_vector = Vector2.ZERO
    if index == boost_touch_index:
        boost_touch_index = -1
        boost_touch_active = false

func _begin_mouse_control(pos: Vector2) -> void:
    if state != "game":
        _handle_press(pos)
        return
    var viewport_size: Vector2 = get_viewport_rect().size
    if pos.x > viewport_size.x - 90.0 and pos.y < 90.0:
        state = "pause"
        _clear_controls()
    elif pos.x >= viewport_size.x * 0.5:
        mouse_control_mode = "boost"
        boost_touch_active = true
        boost_touch_pos = pos
    else:
        mouse_control_mode = "steer"
        touch_start = pos
        joy_vector = Vector2.ZERO

func _move_mouse_control(pos: Vector2) -> void:
    if mouse_control_mode == "boost":
        boost_touch_pos = pos
    elif mouse_control_mode == "steer":
        var drag_delta: Vector2 = pos - touch_start
        joy_vector = drag_delta.limit_length(105.0) / 105.0
        if joy_vector.length() > 0.12:
            desired_heading = joy_vector.normalized()

func _end_mouse_control() -> void:
    if mouse_control_mode == "boost":
        boost_touch_active = false
    elif mouse_control_mode == "steer":
        joy_vector = Vector2.ZERO
    mouse_control_mode = ""

func _handle_press(_pos: Vector2) -> void:
    if state == "menu":
        start_game()
    elif state == "dead":
        state = "menu"
    elif state == "pause":
        state = "game"
        _clear_controls()

func _draw() -> void:
    var viewport_size: Vector2 = get_viewport_rect().size
    if state == "menu":
        draw_menu(viewport_size)
    else:
        draw_world(viewport_size)
        draw_hud(viewport_size)
        if state == "pause":
            draw_overlay(viewport_size, "ПАУЗА", "Коснись экрана, чтобы продолжить")
        elif state == "dead":
            draw_overlay(viewport_size, "МАТЧ ОКОНЧЕН", "Коснись экрана, чтобы вернуться в меню")
        if message_time > 0.0 and state == "game":
            draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 230.0, 78.0), message, HORIZONTAL_ALIGNMENT_CENTER, 460.0, 22, Color.WHITE)

func world_to_screen(world_point: Vector2, viewport_size: Vector2) -> Vector2:
    return world_point - camera_pos + viewport_size / 2.0

func draw_world(viewport_size: Vector2) -> void:
    draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#356b42"))
    var ground: Color = Color("#3c7848")
    match _biome_at(camera_pos):
        "volcano": ground = Color("#493c39")
        "caves": ground = Color("#303d49")
        "ice": ground = Color("#9bcbd5")
        "ruins": ground = Color("#686052")
    draw_rect(Rect2(Vector2.ZERO, viewport_size), ground)
    for x in range(-1, 18):
        for y in range(-1, 12):
            var world_x: float = floor(camera_pos.x / 240.0) * 240.0 + float(x) * 240.0
            var world_y: float = floor(camera_pos.y / 240.0) * 240.0 + float(y) * 240.0
            var screen_point: Vector2 = world_to_screen(Vector2(world_x, world_y), viewport_size)
            draw_circle(screen_point, 145.0, _ground_color(Vector2(world_x, world_y)))
    for i in range(foods.size()):
        var food_screen: Vector2 = world_to_screen(Vector2(foods[i].x, foods[i].y), viewport_size)
        if food_screen.x > -30.0 and food_screen.x < viewport_size.x + 30.0 and food_screen.y > -30.0 and food_screen.y < viewport_size.y + 30.0:
            var food_color: Color = [Color("#ffe66d"), Color("#ff9f68"), Color("#8cf5e8")][int(foods[i].z) - 1]
            draw_circle(food_screen, 13.0, Color(food_color, 0.18))
            draw_circle(food_screen, 7.0, food_color)
            draw_circle(food_screen + Vector2(-2.0, -2.0), 2.5, Color.WHITE)
    for bot in bots:
        if bot.get("alive", true):
            draw_snake(bot.body, bot.color, viewport_size, false)
    draw_snake(snake, Color("#20d8c4"), viewport_size, true)
    var top_left: Vector2 = world_to_screen(Vector2.ZERO, viewport_size)
    var bottom_right: Vector2 = world_to_screen(WORLD_SIZE, viewport_size)
    draw_rect(Rect2(top_left, bottom_right - top_left), Color("#a4d7b0"), false, 8.0)

func _biome_at(point: Vector2) -> String:
    var nx: float = point.x / WORLD_SIZE.x
    var ny: float = point.y / WORLD_SIZE.y
    if absf(nx - 0.5) < 0.16 and absf(ny - 0.5) < 0.18:
        return "ruins"
    if nx < 0.5 and ny < 0.5:
        return "plains"
    if nx >= 0.5 and ny < 0.5:
        return "volcano"
    if nx < 0.5 and ny >= 0.5:
        return "caves"
    return "ice"

func _ground_color(point: Vector2) -> Color:
    var parity: int = int(point.x / 240.0 + point.y / 240.0) % 2
    match _biome_at(point):
        "volcano": return Color("#51413a") if parity == 0 else Color("#493a35")
        "caves": return Color("#35434d") if parity == 0 else Color("#303d47")
        "ice": return Color("#a7d6df") if parity == 0 else Color("#96c8d4")
        "ruins": return Color("#756b58") if parity == 0 else Color("#695f50")
        _: return Color("#3c7848") if parity == 0 else Color("#397044")

func draw_snake(body: Array, snake_color: Color, viewport_size: Vector2, is_player: bool) -> void:
    if body.is_empty():
        return
    for i in range(body.size() - 1, -1, -1):
        var point: Vector2 = world_to_screen(body[i], viewport_size)
        var radius: float = _snake_radius(is_player, i, body.size())
        draw_circle(point + Vector2(2.0, 4.0), radius + 1.0, Color(0.0, 0.0, 0.0, 0.22))
        draw_circle(point, radius, snake_color.darkened(float(i) / float(maxi(1, body.size())) * 0.22))
        draw_arc(point, radius * 0.78, -2.6, -0.5, 18, snake_color.lightened(0.42), 2.2)
        if i < body.size() - 1:
            var toward_next: Vector2 = world_to_screen(body[i + 1], viewport_size)
            draw_line(point, toward_next, snake_color.darkened(0.12), radius * 1.35, true)
    var head_screen: Vector2 = world_to_screen(body[0], viewport_size)
    var forward: Vector2 = heading if is_player else Vector2.RIGHT
    if not is_player and body.size() > 1:
        forward = (body[0] - body[1]).normalized()
    var side: Vector2 = forward.rotated(PI / 2.0)
    for eye_sign in [-1, 1]:
        var eye_position: Vector2 = head_screen + forward * 5.0 + side * float(eye_sign) * 5.0
        draw_circle(eye_position, 3.4, Color.WHITE)
        draw_circle(eye_position + forward * 1.3, 1.8, Color("#15202a"))

func draw_hud(viewport_size: Vector2) -> void:
    draw_rect(Rect2(18.0, 16.0, 260.0, 64.0), Color(0.025, 0.08, 0.13, 0.78), true, 16.0)
    draw_string(ThemeDB.fallback_font, Vector2(36.0, 43.0), "МАССА  %d" % mass, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 23, Color.WHITE)
    draw_string(ThemeDB.fallback_font, Vector2(36.0, 68.0), "ЕДА  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("#b9eee5"))
    draw_rect(Rect2(viewport_size.x / 2.0 - 100.0, 20.0, 200.0, 15.0), Color(0.05, 0.08, 0.12, 0.8), true, 7.0)
    draw_rect(Rect2(viewport_size.x / 2.0 - 98.0, 22.0, 196.0 * stamina / 100.0, 11.0), Color("#5be6c1"), true, 5.0)
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 30.0, 58.0), "ВЫНОСЛИВОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, Color.WHITE)
    draw_circle(Vector2(viewport_size.x - 90.0, 92.0), 64.0, Color(0.02, 0.08, 0.12, 0.82))
    draw_circle(Vector2(viewport_size.x - 90.0, 92.0), 56.0, Color("#548d66"))
    if not snake.is_empty():
        draw_circle(Vector2(viewport_size.x - 90.0 + (snake[0].x / WORLD_SIZE.x - 0.5) * 100.0, 92.0 + (snake[0].y / WORLD_SIZE.y - 0.5) * 100.0), 4.0, Color("#fff18a"))
    draw_circle(joy_origin, 70.0, Color(0.02, 0.07, 0.1, 0.38))
    draw_circle(joy_origin, 57.0, Color(0.7, 0.95, 0.9, 0.13))
    draw_circle(joy_origin + joy_vector * 48.0, 24.0, Color(0.85, 1.0, 1.0, 0.48))
    var boost_center: Vector2 = boost_touch_pos if boost_touch_active else boost_rect.get_center()
    draw_circle(boost_center, BOOST_TOUCH_RADIUS, Color(0.25, 0.08, 0.06, 0.72 if boost_touch_active else 0.42))
    draw_circle(boost_center, 66.0, Color("#ec874e"))
    draw_string(ThemeDB.fallback_font, boost_center + Vector2(-47.0, 7.0), "УСКОР", HORIZONTAL_ALIGNMENT_CENTER, 95.0, 20, Color.WHITE)
    draw_circle(Vector2(viewport_size.x - 48.0, 42.0), 25.0, Color(0.02, 0.07, 0.1, 0.65))
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x - 60.0, 50.0), "Ⅱ", HORIZONTAL_ALIGNMENT_CENTER, 24.0, 20, Color.WHITE)

func draw_menu(viewport_size: Vector2) -> void:
    draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#102b36"))
    for i in range(20):
        var point: Vector2 = Vector2(fposmod(float(i) * 211.0, viewport_size.x), fposmod(float(i) * 137.0, viewport_size.y))
        draw_circle(point, 38.0, Color("#1d4650"))
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 235.0, viewport_size.y * 0.28), "SNAKE BATTLE", HORIZONTAL_ALIGNMENT_CENTER, 470.0, 58, Color("#ffe28a"))
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 180.0, viewport_size.y * 0.37), "ОСТРОВ ЧЕТЫРЁХ БИОМОВ", HORIZONTAL_ALIGNMENT_CENTER, 360.0, 21, Color("#9de8dc"))
    draw_circle(Vector2(viewport_size.x / 2.0, viewport_size.y * 0.56), 74.0, Color("#20d8c4"))
    draw_circle(Vector2(viewport_size.x / 2.0 - 20.0, viewport_size.y * 0.54), 9.0, Color.WHITE)
    draw_circle(Vector2(viewport_size.x / 2.0 + 20.0, viewport_size.y * 0.54), 9.0, Color.WHITE)
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 130.0, viewport_size.y * 0.82), "КОСНИСЬ ЭКРАНА, ЧТОБЫ ИГРАТЬ", HORIZONTAL_ALIGNMENT_CENTER, 260.0, 20, Color.WHITE)
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 150.0, viewport_size.y * 0.9), "Первая тестовая сборка", HORIZONTAL_ALIGNMENT_CENTER, 300.0, 14, Color("#b5d6d0"))

func draw_overlay(viewport_size: Vector2, title: String, subtitle: String) -> void:
    draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.0, 0.0, 0.0, 0.62))
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 220.0, viewport_size.y * 0.46), title, HORIZONTAL_ALIGNMENT_CENTER, 440.0, 42, Color("#ffe28a"))
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x / 2.0 - 280.0, viewport_size.y * 0.55), subtitle, HORIZONTAL_ALIGNMENT_CENTER, 560.0, 20, Color.WHITE)
