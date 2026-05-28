extends Node2D

# Level Devil — a troll platformer.
# Everything is drawn from primitives. Levels are data + per-level mutation logic.

const VIEW_W := 960.0
const VIEW_H := 540.0

const PLAYER_W := 22.0
const PLAYER_H := 30.0
const GRAVITY := 1800.0
const JUMP_SPEED := -620.0
const MOVE_SPEED := 270.0
const COYOTE_TIME := 0.08
const JUMP_BUFFER := 0.1

const TILE := 32.0

# Update launcher integration (see launcher/ at repo root)
const LAUNCHER_NAME := "LevelDevilLauncher.exe"

enum State { PLAYING, DYING, WIN, MENU, PAUSED }

var state: int = State.PLAYING
var current_level: int = 0
var levels_total: int = 6

var player_pos: Vector2 = Vector2.ZERO  # bottom-center
var player_vel: Vector2 = Vector2.ZERO
var on_ground: bool = false
var coyote: float = 0.0
var jump_buffer: float = 0.0
var facing: int = 1

var platforms: Array = []          # Array[Rect2]
var spikes: Array = []             # Array[Rect2] — kill on touch
var doors: Array = []              # Array[Dictionary] {rect: Rect2, real: bool}
var sign_text: String = ""
var sign_pos: Vector2 = Vector2.ZERO

var level_state: Dictionary = {}   # Per-level mutable state
var death_timer: float = 0.0
var win_timer: float = 0.0
var shake: float = 0.0
var menu_button_rects: Array = []  # [Rect2, ...] for click hit-testing
var deaths: int = 0
var time_in_level: float = 0.0


func _ready() -> void:
	randomize()
	_show_title()
	set_process(true)
	set_physics_process(true)


func _show_title() -> void:
	state = State.MENU
	queue_redraw()


# ============================================================
# Input
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match state:
			State.PLAYING:
				if event.keycode == KEY_W or event.keycode == KEY_UP or event.keycode == KEY_SPACE:
					jump_buffer = JUMP_BUFFER
				elif event.keycode == KEY_R:
					_kill_player()
				elif event.keycode == KEY_ESCAPE:
					state = State.PAUSED
					queue_redraw()
			State.PAUSED:
				if event.keycode == KEY_ESCAPE:
					state = State.PLAYING
					queue_redraw()
			State.MENU:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_start_game()
			State.WIN:
				if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
					_show_title()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		var mp: Vector2 = mb.position
		for i in range(menu_button_rects.size()):
			var r: Rect2 = menu_button_rects[i]
			if r.has_point(mp):
				_handle_menu_click(i)
				return


func _handle_menu_click(index: int) -> void:
	match state:
		State.MENU:
			match index:
				0: _start_game()
				1: _trigger_update()
				2: get_tree().quit()
		State.PAUSED:
			match index:
				0: state = State.PLAYING; queue_redraw()
				1: _kill_player(); state = State.PLAYING
				2: _trigger_update()
				3: _show_title()


func _start_game() -> void:
	current_level = 0
	deaths = 0
	_load_level(current_level)
	state = State.PLAYING


# ============================================================
# Update flow — spawn launcher, pass our pid, exit
# ============================================================

func _trigger_update() -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var launcher := exe_dir.path_join(LAUNCHER_NAME)
	if FileAccess.file_exists(launcher):
		var pid := OS.get_process_id()
		OS.create_process(launcher, ["--update", "--wait-pid", str(pid)])
	get_tree().quit()


# ============================================================
# Level loading
# ============================================================

func _load_level(n: int) -> void:
	platforms = []
	spikes = []
	doors = []
	level_state = {}
	sign_text = ""
	sign_pos = Vector2.ZERO
	time_in_level = 0.0
	player_vel = Vector2.ZERO

	match n:
		0: _build_level_0()
		1: _build_level_1()
		2: _build_level_2()
		3: _build_level_3()
		4: _build_level_4()
		5: _build_level_5()
		_: _build_level_0()

	queue_redraw()


# ---- Level 0: Tutorial (honest, sets expectations) ----
func _build_level_0() -> void:
	# Floor
	platforms.append(Rect2(0, VIEW_H - TILE, VIEW_W, TILE))
	# Small gap with a pit (no, actually keep this one safe)
	# Add a small step
	platforms.append(Rect2(420, VIEW_H - TILE * 3, TILE * 3, TILE))
	# Door at right
	doors.append({"rect": Rect2(VIEW_W - 80, VIEW_H - TILE - 56, 36, 56), "real": true})
	sign_text = "Arrows or A/D to move. W/Up/Space to jump. Reach the green door."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(80, VIEW_H - TILE)


# ---- Level 1: Falling spike trap ----
func _build_level_1() -> void:
	platforms.append(Rect2(0, VIEW_H - TILE, VIEW_W, TILE))
	doors.append({"rect": Rect2(VIEW_W - 80, VIEW_H - TILE - 56, 36, 56), "real": true})
	level_state["trap_armed"] = true
	level_state["trap_fired"] = false
	level_state["spike_y"] = -60.0
	level_state["spike_x"] = VIEW_W - 200.0
	sign_text = "Looks easy. Run for it."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(80, VIEW_H - TILE)


# ---- Level 2: Disappearing floor ----
func _build_level_2() -> void:
	# Floor in chunks; each chunk vanishes shortly after the player steps on it.
	var chunk_w := 80.0
	var x := 0.0
	var i := 0
	while x < VIEW_W:
		platforms.append(Rect2(x, VIEW_H - TILE, chunk_w, TILE))
		x += chunk_w
		i += 1
	level_state["floor_count"] = i
	level_state["floor_timers"] = []  # [-1 means stable; >=0 means counting down]
	for _j in range(i):
		level_state["floor_timers"].append(-1.0)
	# Safe end platform
	platforms.append(Rect2(VIEW_W - 100, VIEW_H - TILE * 2, 100, TILE))
	doors.append({"rect": Rect2(VIEW_W - 80, VIEW_H - TILE * 2 - 56, 36, 56), "real": true})
	sign_text = "Don't stand still."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(40, VIEW_H - TILE)


# ---- Level 3: The retreating door ----
func _build_level_3() -> void:
	platforms.append(Rect2(0, VIEW_H - TILE, VIEW_W, TILE))
	# Door that flees the player horizontally, wrapping around.
	var door_rect := Rect2(VIEW_W - 80, VIEW_H - TILE - 56, 36, 56)
	doors.append({"rect": door_rect, "real": true})
	level_state["door_index"] = 0
	level_state["door_speed"] = 0.0
	sign_text = "Catch the door."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(80, VIEW_H - TILE)


# ---- Level 4: Spikes from the floor ----
func _build_level_4() -> void:
	platforms.append(Rect2(0, VIEW_H - TILE, VIEW_W, TILE))
	# Hidden spike slots at fixed x positions; raise when player crosses.
	var slot_xs := [220, 360, 500, 640, 780]
	level_state["slot_xs"] = slot_xs
	level_state["slot_fired"] = []
	level_state["active_spikes"] = []  # [{x,y,t}] for animated rising spikes
	for _i in slot_xs.size():
		level_state["slot_fired"].append(false)
	doors.append({"rect": Rect2(VIEW_W - 80, VIEW_H - TILE - 56, 36, 56), "real": true})
	sign_text = "Watch your step."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(60, VIEW_H - TILE)


# ---- Level 5: The finale (combo) ----
func _build_level_5() -> void:
	platforms.append(Rect2(0, VIEW_H - TILE, VIEW_W, TILE))
	# Ceiling spike row (decoration / hint)
	for i in range(0, 20):
		spikes.append(Rect2(i * TILE, 0, TILE, 20))
	# Mid platform
	platforms.append(Rect2(360, VIEW_H - TILE * 4, TILE * 4, TILE))
	# Three doors at the right — only middle is real
	doors.append({"rect": Rect2(VIEW_W - 220, VIEW_H - TILE - 56, 36, 56), "real": false})
	doors.append({"rect": Rect2(VIEW_W - 140, VIEW_H - TILE - 56, 36, 56), "real": true})
	doors.append({"rect": Rect2(VIEW_W - 60,  VIEW_H - TILE - 56, 36, 56), "real": false})
	# Falling spike at midpoint, like level 1 but harder
	level_state["trap_armed"] = true
	level_state["trap_fired"] = false
	level_state["spike_y"] = -60.0
	level_state["spike_x"] = VIEW_W * 0.5
	# Spike slots for surprise
	level_state["slot_xs"] = [200, 600]
	level_state["slot_fired"] = [false, false]
	level_state["active_spikes"] = []
	sign_text = "One door is honest. The other two lie."
	sign_pos = Vector2(VIEW_W * 0.5, 80)
	player_pos = Vector2(60, VIEW_H - TILE)


# ============================================================
# Physics + game loop
# ============================================================

func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		_update_player(delta)
		_update_level_logic(delta)
		_check_hazards()
		_check_doors()
		time_in_level += delta
	elif state == State.DYING:
		death_timer -= delta
		if death_timer <= 0.0:
			_load_level(current_level)
			state = State.PLAYING
	elif state == State.WIN:
		win_timer += delta

	if shake > 0.0:
		shake = max(0.0, shake - delta * 4.0)
	queue_redraw()


func _update_player(delta: float) -> void:
	var ix := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		ix -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		ix += 1.0
	if ix != 0.0:
		facing = int(sign(ix))
	player_vel.x = ix * MOVE_SPEED

	player_vel.y += GRAVITY * delta
	if player_vel.y > 1400.0:
		player_vel.y = 1400.0

	# Jump buffer + coyote
	jump_buffer = max(0.0, jump_buffer - delta)
	coyote = max(0.0, coyote - delta)
	if jump_buffer > 0.0 and coyote > 0.0:
		player_vel.y = JUMP_SPEED
		jump_buffer = 0.0
		coyote = 0.0

	# X movement & collide
	player_pos.x += player_vel.x * delta
	_resolve_collisions_axis(true)

	# Y movement & collide
	var was_on_ground := on_ground
	player_pos.y += player_vel.y * delta
	on_ground = false
	_resolve_collisions_axis(false)
	if on_ground:
		coyote = COYOTE_TIME
	elif was_on_ground:
		coyote = COYOTE_TIME

	# World bounds
	if player_pos.y > VIEW_H + 200.0:
		_kill_player()
	if player_pos.x < -50.0:
		player_pos.x = -50.0
		player_vel.x = 0.0
	if player_pos.x > VIEW_W + 50.0:
		player_pos.x = VIEW_W + 50.0
		player_vel.x = 0.0


func _player_rect() -> Rect2:
	return Rect2(player_pos.x - PLAYER_W * 0.5, player_pos.y - PLAYER_H, PLAYER_W, PLAYER_H)


func _resolve_collisions_axis(is_x: bool) -> void:
	# Resolve against each platform; player is treated as AABB.
	for plat in platforms:
		var pr := _player_rect()
		if pr.intersects(plat):
			if is_x:
				if player_vel.x > 0.0:
					player_pos.x = plat.position.x - PLAYER_W * 0.5
				elif player_vel.x < 0.0:
					player_pos.x = plat.position.x + plat.size.x + PLAYER_W * 0.5
				player_vel.x = 0.0
			else:
				if player_vel.y > 0.0:
					player_pos.y = plat.position.y
					player_vel.y = 0.0
					on_ground = true
				elif player_vel.y < 0.0:
					player_pos.y = plat.position.y + plat.size.y + PLAYER_H
					player_vel.y = 0.0


# ============================================================
# Per-level mutation logic
# ============================================================

func _update_level_logic(delta: float) -> void:
	match current_level:
		1: _logic_level_1(delta)
		2: _logic_level_2(delta)
		3: _logic_level_3(delta)
		4: _logic_level_4(delta)
		5: _logic_level_5(delta)


func _logic_level_1(_delta: float) -> void:
	# Spike falls from the ceiling when player crosses 2/3 of the screen.
	if level_state.get("trap_armed", false) and player_pos.x > VIEW_W * 0.62:
		level_state["trap_fired"] = true
		level_state["trap_armed"] = false
		shake = 0.6
	if level_state.get("trap_fired", false):
		level_state["spike_y"] += 1200.0 * _delta
		var sx: float = level_state["spike_x"]
		var sy: float = level_state["spike_y"]
		# Maintain a falling spike rect that kills on touch
		spikes.clear()
		spikes.append(Rect2(sx - 22, sy, 44, 44))
		if sy > VIEW_H:
			# Stop the spike from infinitely descending; clamp at floor.
			level_state["spike_y"] = VIEW_H - TILE - 44.0


func _logic_level_2(delta: float) -> void:
	var timers: Array = level_state["floor_timers"]
	var pr := _player_rect()
	# Start a vanish timer for chunks the player stands on.
	for i in range(level_state["floor_count"]):
		var plat: Rect2 = platforms[i]
		if pr.intersects(Rect2(plat.position.x, plat.position.y - 1.0, plat.size.x, 2.0)) and on_ground:
			if timers[i] < 0.0:
				timers[i] = 0.45  # seconds until vanish
	# Tick down and remove
	var to_remove: Array = []
	for i in range(level_state["floor_count"]):
		if timers[i] > 0.0:
			timers[i] -= delta
			if timers[i] <= 0.0:
				to_remove.append(i)
	# Mark for removal by shrinking width to zero (keeps indices stable in this list)
	for i in to_remove:
		platforms[i] = Rect2(platforms[i].position.x, platforms[i].position.y, 0, 0)


func _logic_level_3(delta: float) -> void:
	if doors.is_empty():
		return
	const TRIGGER_DIST := 200.0
	const FLEE_SPEED := 320.0
	const MAX_WRAPS := 3
	const COMMIT_TIME := 12.0

	var d: Dictionary = doors[0]
	var r: Rect2 = d["rect"]
	var cur_speed: float = float(level_state.get("door_speed", 0.0))
	var grace: float = float(level_state.get("door_grace", 0.0))
	var wraps: int = int(level_state.get("door_wraps", 0))
	var committed: bool = wraps >= MAX_WRAPS or time_in_level > COMMIT_TIME

	if committed:
		cur_speed = 0.0
	elif grace > 0.0:
		# After a wrap, the door briefly holds still so the player can spot it.
		grace = maxf(0.0, grace - delta)
		cur_speed = lerpf(cur_speed, 0.0, 0.2)
	else:
		var dx: float = r.position.x - player_pos.x
		if absf(dx) < TRIGGER_DIST:
			cur_speed = lerpf(cur_speed, FLEE_SPEED, 0.06)
			var dir: float = 1.0 if dx >= 0.0 else -1.0
			r.position.x += cur_speed * delta * dir
		else:
			cur_speed = lerpf(cur_speed, 0.0, 0.15)

	# Wrap to a visible spot on the opposite side and start a grace window.
	if r.position.x > VIEW_W - 8.0:
		r.position.x = 16.0
		grace = 0.8
		wraps += 1
	elif r.position.x + r.size.x < 8.0:
		r.position.x = VIEW_W - r.size.x - 16.0
		grace = 0.8
		wraps += 1

	d["rect"] = r
	doors[0] = d
	level_state["door_speed"] = cur_speed
	level_state["door_grace"] = grace
	level_state["door_wraps"] = wraps


func _logic_level_4(delta: float) -> void:
	var slot_xs: Array = level_state["slot_xs"]
	var slot_fired: Array = level_state["slot_fired"]
	var active: Array = level_state["active_spikes"]
	for i in range(slot_xs.size()):
		if not slot_fired[i] and player_pos.x > slot_xs[i] - 8.0:
			slot_fired[i] = true
			active.append({"x": float(slot_xs[i]), "y": VIEW_H - TILE, "t": 0.0})
			shake = 0.25
	# Animate rising spikes; build spikes list each frame.
	spikes.clear()
	for s in active:
		s["t"] += delta * 3.5
		var h: float = clamp(s["t"], 0.0, 1.0) * 40.0
		spikes.append(Rect2(s["x"] - 16.0, VIEW_H - TILE - h, 32.0, h))
	level_state["slot_fired"] = slot_fired
	level_state["active_spikes"] = active


func _logic_level_5(delta: float) -> void:
	# Combination: falling spike + emerging floor spikes
	_logic_level_1(delta)
	# Append slot spikes to the existing spikes array
	var slot_xs: Array = level_state["slot_xs"]
	var slot_fired: Array = level_state["slot_fired"]
	var active: Array = level_state["active_spikes"]
	for i in range(slot_xs.size()):
		if not slot_fired[i] and player_pos.x > slot_xs[i] - 8.0:
			slot_fired[i] = true
			active.append({"x": float(slot_xs[i]), "y": VIEW_H - TILE, "t": 0.0})
			shake = 0.25
	for s in active:
		s["t"] += delta * 3.5
		var h: float = clamp(s["t"], 0.0, 1.0) * 40.0
		spikes.append(Rect2(s["x"] - 16.0, VIEW_H - TILE - h, 32.0, h))


# ============================================================
# Hazard / door checks
# ============================================================

func _check_hazards() -> void:
	var pr := _player_rect()
	for s in spikes:
		var sr: Rect2 = s
		if sr.size.x <= 0.0 or sr.size.y <= 0.0:
			continue
		# Slight inset for fairness
		var inset := sr.grow(-2.0)
		if pr.intersects(inset):
			_kill_player()
			return


func _check_doors() -> void:
	var pr := _player_rect()
	for d in doors:
		var dr: Rect2 = d["rect"]
		if pr.intersects(dr):
			if d["real"]:
				_advance_level()
			else:
				_kill_player()
			return


func _kill_player() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	death_timer = 0.45
	shake = 0.8
	deaths += 1


func _advance_level() -> void:
	current_level += 1
	if current_level >= levels_total:
		state = State.WIN
		win_timer = 0.0
		queue_redraw()
		return
	_load_level(current_level)


# ============================================================
# Rendering — everything from primitives
# ============================================================

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var offset := Vector2.ZERO
	if shake > 0.0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 6.0

	draw_set_transform(offset, 0.0, Vector2.ONE)

	# Background
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.07, 0.07, 0.1), true)

	# Decorative grid
	var grid_c := Color(1, 1, 1, 0.03)
	for x in range(0, int(VIEW_W), int(TILE)):
		draw_line(Vector2(x, 0), Vector2(x, VIEW_H), grid_c)
	for y in range(0, int(VIEW_H), int(TILE)):
		draw_line(Vector2(0, y), Vector2(VIEW_W, y), grid_c)

	# Platforms
	for plat in platforms:
		var p: Rect2 = plat
		if p.size.x <= 0.0 or p.size.y <= 0.0:
			continue
		draw_rect(p, Color(0.32, 0.22, 0.18), true)
		draw_rect(Rect2(p.position, Vector2(p.size.x, 4.0)), Color(0.55, 0.42, 0.30), true)

	# Spikes (triangles)
	for s in spikes:
		_draw_spike_rect(s)

	# Doors
	for d in doors:
		var r: Rect2 = d["rect"]
		# Real and fake doors look identical — that's the troll.
		var col: Color = Color(0.25, 0.75, 0.35)
		draw_rect(r, col, true)
		draw_rect(r, Color(0, 0, 0, 0.4), false, 2.0)
		# Knob
		draw_circle(r.position + Vector2(r.size.x - 8.0, r.size.y * 0.55), 2.5, Color(0.1, 0.1, 0.1))

	# Sign / hint
	if sign_text != "":
		_draw_text_centered(sign_text, sign_pos, Color(0.85, 0.85, 0.9))

	# Player
	if state != State.DYING:
		var pr := _player_rect()
		draw_rect(pr, Color(0.92, 0.92, 0.97), true)
		draw_rect(pr, Color(0.0, 0.0, 0.0, 0.6), false, 1.5)
		# Eye
		var eye_x := pr.position.x + (pr.size.x * 0.65 if facing > 0 else pr.size.x * 0.25)
		var eye_y := pr.position.y + 8.0
		draw_rect(Rect2(eye_x - 2.0, eye_y, 4.0, 4.0), Color(0.05, 0.05, 0.08), true)

	# Death flash
	if state == State.DYING:
		var t: float = 1.0 - clampf(death_timer / 0.45, 0.0, 1.0)
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.8, 0.1, 0.1, 0.35 + 0.3 * t), true)
		_draw_text_centered("OUCH", Vector2(VIEW_W * 0.5, VIEW_H * 0.5), Color(1, 1, 1, 0.95), 64)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# HUD
	_draw_text("Level %d / %d" % [current_level + 1, levels_total], Vector2(16, 24), Color(0.85, 0.85, 0.95))
	_draw_text("Deaths: %d" % deaths, Vector2(16, 46), Color(0.85, 0.85, 0.95))
	_draw_text("ESC: pause   R: restart", Vector2(VIEW_W - 220, 24), Color(0.6, 0.6, 0.7))

	# Overlays
	if state == State.MENU:
		_draw_title_menu()
	elif state == State.PAUSED:
		_draw_pause_menu()
	elif state == State.WIN:
		_draw_win_screen()


func _draw_spike_rect(s: Rect2) -> void:
	if s.size.x <= 0.0 or s.size.y <= 0.0:
		return
	var spike_w := 16.0
	var x := s.position.x
	var top := s.position.y
	var bot := s.position.y + s.size.y
	# Determine orientation: tall thin spikes (rising/falling) vs ceiling/floor rows
	if s.size.y >= s.size.x:
		# Tall single spike — apex at bottom (falling spike) or top depending on context
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(x, top),
			Vector2(x + s.size.x, top),
			Vector2(x + s.size.x * 0.5, bot)
		])
		draw_colored_polygon(pts, Color(0.85, 0.2, 0.25))
	else:
		# Row of spikes (ceiling or floor)
		var pointing_down := top < 60.0  # near ceiling
		var n := int(s.size.x / spike_w)
		for i in range(n):
			var sx := x + i * spike_w
			var pts: PackedVector2Array
			if pointing_down:
				pts = PackedVector2Array([
					Vector2(sx, top),
					Vector2(sx + spike_w, top),
					Vector2(sx + spike_w * 0.5, bot)
				])
			else:
				pts = PackedVector2Array([
					Vector2(sx, bot),
					Vector2(sx + spike_w, bot),
					Vector2(sx + spike_w * 0.5, top)
				])
			draw_colored_polygon(pts, Color(0.85, 0.2, 0.25))


# ============================================================
# Menu overlays
# ============================================================

func _draw_title_menu() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0, 0, 0, 0.65), true)
	_draw_text_centered("LEVEL DEVIL", Vector2(VIEW_W * 0.5, 180), Color(0.95, 0.3, 0.3), 72)
	_draw_text_centered("the level is out to get you", Vector2(VIEW_W * 0.5, 230), Color(0.8, 0.8, 0.85), 20)
	menu_button_rects = []
	var labels := ["Play", "Check for updates", "Quit"]
	var y := 310.0
	for label in labels:
		var r := Rect2(VIEW_W * 0.5 - 110, y, 220, 44)
		menu_button_rects.append(r)
		draw_rect(r, Color(0.15, 0.15, 0.22), true)
		draw_rect(r, Color(0.95, 0.3, 0.3, 0.6), false, 2.0)
		_draw_text_centered(label, r.position + r.size * 0.5 + Vector2(0, 6), Color(0.95, 0.95, 1.0), 22)
		y += 56.0


func _draw_pause_menu() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0, 0, 0, 0.55), true)
	_draw_text_centered("PAUSED", Vector2(VIEW_W * 0.5, 160), Color(0.95, 0.95, 1.0), 56)
	menu_button_rects = []
	var labels := ["Resume", "Restart level", "Check for updates", "Back to title"]
	var y := 230.0
	for label in labels:
		var r := Rect2(VIEW_W * 0.5 - 130, y, 260, 42)
		menu_button_rects.append(r)
		draw_rect(r, Color(0.15, 0.15, 0.22), true)
		draw_rect(r, Color(0.6, 0.6, 0.8, 0.6), false, 2.0)
		_draw_text_centered(label, r.position + r.size * 0.5 + Vector2(0, 6), Color(0.95, 0.95, 1.0), 22)
		y += 54.0


func _draw_win_screen() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0, 0, 0, 0.7), true)
	_draw_text_centered("YOU SURVIVED", Vector2(VIEW_W * 0.5, 200), Color(0.4, 0.95, 0.4), 64)
	_draw_text_centered("Deaths: %d" % deaths, Vector2(VIEW_W * 0.5, 260), Color(0.9, 0.9, 1.0), 28)
	_draw_text_centered("Press Enter to return to title", Vector2(VIEW_W * 0.5, 340), Color(0.7, 0.7, 0.8), 20)


# ============================================================
# Text helpers (uses Godot's default fallback font)
# ============================================================

func _default_font() -> Font:
	return ThemeDB.fallback_font


func _draw_text(text: String, pos: Vector2, color: Color, size: int = 16) -> void:
	var f := _default_font()
	draw_string(f, pos + Vector2(0, size), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _draw_text_centered(text: String, pos: Vector2, color: Color, size: int = 18) -> void:
	var f := _default_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(f, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
