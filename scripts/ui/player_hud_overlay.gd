extends Control

const MAX_KILL_FEED_ITEMS := 6
const SCOREBOARD_WIDTH := 260.0
const SCOREBOARD_WIDTH_SCREEN_FRACTION := 0.2
const SCOREBOARD_ROW_HEIGHT := 30.0
const SCOREBOARD_COLUMN_RANK_FRACTION := 0.22
const SCOREBOARD_COLUMN_KILLS_FRACTION := 0.2
const SCOREBOARD_ROW_MIN_HEIGHT := 34.0
const ROW_OUTER_PADDING_X := 3.0
const ROW_OUTER_PADDING_Y := 2.0
const ROW_INNER_PADDING_X := 5.0
const ROW_INNER_PADDING_Y := 2.0
const SCOREBOARD_HEADER_COLOR := Color(0.95, 0.96, 0.98, 0.95)
const SCOREBOARD_TEXT_COLOR := Color(0.95, 0.95, 0.95, 0.95)
const SCOREBOARD_SEPARATOR_COLOR := Color(0.92, 0.92, 0.92, 0.4)
const KILL_FEED_ENTRY_LIFETIME_SECONDS := 3.0
const KILL_FEED_FADE_SECONDS := 0.3
const LOCAL_GRADIENT_COLOR := Color(0.15, 0.46, 0.96, 0.78)
const OTHER_GRADIENT_COLOR := Color(0.86, 0.22, 0.22, 0.74)
const SCOREBOARD_LOCAL_ROW_GRADIENT_COLOR := Color(0.95, 0.49, 0.12, 0.8)
const KILL_SEPARATOR := " ⁍ "

@onready var scoreboard_margin: MarginContainer = $ScoreboardMargin
@onready var scoreboard_panel: PanelContainer = $ScoreboardMargin/ScoreboardPanel
@onready var scoreboard_rows: VBoxContainer = $ScoreboardMargin/ScoreboardPanel/MarginContainer/VBoxContainer/ScoreboardRows
@onready var kill_feed_rows: VBoxContainer = $KillFeedMargin/KillFeedRows

var _local_peer_id: int = -1
var _local_gradient_texture: GradientTexture2D
var _other_gradient_texture: GradientTexture2D
var _scoreboard_local_row_gradient_texture: GradientTexture2D
var _scoreboard_target_width: float = SCOREBOARD_WIDTH

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_local_gradient_texture = _build_gradient_texture(LOCAL_GRADIENT_COLOR, false)
	_other_gradient_texture = _build_gradient_texture(OTHER_GRADIENT_COLOR, false)
	_scoreboard_local_row_gradient_texture = _build_gradient_texture(SCOREBOARD_LOCAL_ROW_GRADIENT_COLOR)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_update_scoreboard_dimensions()

func _on_viewport_size_changed() -> void:
	_update_scoreboard_dimensions()

func _update_scoreboard_dimensions() -> void:
	var viewport_width := get_viewport_rect().size.x
	_scoreboard_target_width = floor(viewport_width * SCOREBOARD_WIDTH_SCREEN_FRACTION)
	if scoreboard_margin != null:
		scoreboard_margin.offset_right = scoreboard_margin.offset_left + _scoreboard_target_width
	if scoreboard_panel != null:
		scoreboard_panel.custom_minimum_size = Vector2(_scoreboard_target_width, 0.0)

func set_local_peer_id(peer_id: int) -> void:
	_local_peer_id = peer_id

func update_scoreboard(entries: Array) -> void:
	for child in scoreboard_rows.get_children():
		child.queue_free()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Waiting for players..."
		empty_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 0.85))
		empty_label.add_theme_font_size_override("font_size", 18)
		scoreboard_rows.add_child(empty_label)
		return

	var typed_entries: Array = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		typed_entries.append(entry)

	if typed_entries.is_empty():
		return

	_update_scoreboard_dimensions()
	scoreboard_rows.add_child(_create_scoreboard_table_header_row())

	var top_count: int = min(3, typed_entries.size())
	var local_entry: Dictionary = {}
	var local_rank: int = -1
	var local_in_top: bool = false

	for i in range(typed_entries.size()):
		var entry: Dictionary = typed_entries[i]
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id == _local_peer_id:
			local_entry = entry
			local_rank = i + 1
			local_in_top = i < top_count
			break

	for i in range(top_count):
		var entry: Dictionary = typed_entries[i]
		var peer_id := int(entry.get("peer_id", -1))
		var player_name := str(entry.get("name", "Player %s" % peer_id))
		var kills := int(entry.get("kills", 0))
		scoreboard_rows.add_child(_create_scoreboard_table_row(i + 1, player_name, kills, peer_id == _local_peer_id))

	if not local_entry.is_empty() and not local_in_top:
		scoreboard_rows.add_child(_create_separator_row(_get_scoreboard_inner_width()))
		var local_peer_id := int(local_entry.get("peer_id", _local_peer_id))
		var local_player_name := str(local_entry.get("name", "Player %s" % local_peer_id))
		var local_kills := int(local_entry.get("kills", 0))
		var rank_value := local_rank if local_rank > 0 else (top_count + 1)
		scoreboard_rows.add_child(_create_scoreboard_table_row(rank_value, local_player_name, local_kills, true))

func _get_scoreboard_inner_width() -> float:
	return maxf(_scoreboard_target_width - 12.0, 120.0)

func _create_scoreboard_table_header_row() -> Control:
	var row_width := _get_scoreboard_inner_width()
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(row_width, SCOREBOARD_ROW_HEIGHT)

	var content := HBoxContainer.new()
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = ROW_INNER_PADDING_X
	content.offset_right = -ROW_INNER_PADDING_X
	content.offset_top = ROW_INNER_PADDING_Y
	content.offset_bottom = -ROW_INNER_PADDING_Y
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)

	var rank_width: float = floor(row_width * SCOREBOARD_COLUMN_RANK_FRACTION)
	var kills_width: float = floor(row_width * SCOREBOARD_COLUMN_KILLS_FRACTION)
	var name_width: float = maxf(row_width - rank_width - kills_width - 16.0, 80.0)

	content.add_child(_create_scoreboard_table_cell("Ranking", rank_width, HORIZONTAL_ALIGNMENT_LEFT, true))
	content.add_child(_create_scoreboard_table_cell("Name", name_width, HORIZONTAL_ALIGNMENT_LEFT, true))
	content.add_child(_create_scoreboard_table_cell("Kills", kills_width, HORIZONTAL_ALIGNMENT_LEFT, true))

	return row

func _create_scoreboard_table_row(rank: int, player_name: String, kills: int, highlight_local: bool) -> Control:
	var row_width := _get_scoreboard_inner_width()
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(row_width, SCOREBOARD_ROW_HEIGHT)

	if highlight_local:
		var background := TextureRect.new()
		background.anchor_right = 1.0
		background.anchor_bottom = 1.0
		background.expand_mode = TextureRect.EXPAND_FIT_WIDTH
		background.stretch_mode = TextureRect.STRETCH_SCALE
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.texture = _scoreboard_local_row_gradient_texture
		row.add_child(background)

	var content := HBoxContainer.new()
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = ROW_INNER_PADDING_X
	content.offset_right = -ROW_INNER_PADDING_X
	content.offset_top = ROW_INNER_PADDING_Y
	content.offset_bottom = -ROW_INNER_PADDING_Y
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)

	var rank_width: float = floor(row_width * SCOREBOARD_COLUMN_RANK_FRACTION)
	var kills_width: float = floor(row_width * SCOREBOARD_COLUMN_KILLS_FRACTION)
	var name_width: float = maxf(row_width - rank_width - kills_width - 16.0, 80.0)

	content.add_child(_create_scoreboard_table_cell("%d." % rank, rank_width, HORIZONTAL_ALIGNMENT_LEFT, false))
	content.add_child(_create_scoreboard_table_cell(player_name, name_width, HORIZONTAL_ALIGNMENT_LEFT, false))
	content.add_child(_create_scoreboard_table_cell(str(kills), kills_width, HORIZONTAL_ALIGNMENT_LEFT, false))

	return row

func _create_scoreboard_table_cell(text_value: String, width: float, align: HorizontalAlignment, is_header: bool) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size = Vector2(width, 0.0)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 16 if is_header else 17)
	label.add_theme_color_override("font_color", SCOREBOARD_HEADER_COLOR if is_header else SCOREBOARD_TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 2)
	return label

func clear_kill_feed() -> void:
	for child in kill_feed_rows.get_children():
		child.queue_free()

func push_kill_feed_entry(entry: Dictionary) -> void:
	var killer_id := int(entry.get("killer_id", 0))
	var killer_name := str(entry.get("killer_name", "World"))
	var victim_name := str(entry.get("victim_name", "Unknown"))
	var row_text := "%s%s%s" % [killer_name, KILL_SEPARATOR, victim_name]
	var row := _create_gradient_label_row(row_text, killer_id == _local_peer_id, false, true)

	kill_feed_rows.add_child(row)
	kill_feed_rows.move_child(row, 0)
	_schedule_kill_feed_fade(row)

	while kill_feed_rows.get_child_count() > MAX_KILL_FEED_ITEMS:
		kill_feed_rows.get_child(kill_feed_rows.get_child_count() - 1).queue_free()

func _schedule_kill_feed_fade(row: Control) -> void:
	var timer := get_tree().create_timer(KILL_FEED_ENTRY_LIFETIME_SECONDS)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(row):
			return
		var tween := create_tween()
		tween.tween_property(row, "modulate:a", 0.0, KILL_FEED_FADE_SECONDS)
		tween.tween_callback(row.queue_free)
	)

func _create_separator_row(line_width: float) -> Control:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(line_width, 12.0)

	var separator := ColorRect.new()
	separator.anchor_left = 0.0
	separator.anchor_top = 0.5
	separator.anchor_right = 1.0
	separator.anchor_bottom = 0.5
	separator.offset_top = -0.5
	separator.offset_bottom = 0.5
	separator.color = SCOREBOARD_SEPARATOR_COLOR
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(separator)

	return row

func _create_gradient_label_row(text: String, use_local_style: bool, allow_wrap: bool, align_to_end: bool = false) -> Control:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if align_to_end:
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var outer_margin := MarginContainer.new()
	outer_margin.anchor_right = 1.0
	outer_margin.anchor_bottom = 1.0
	outer_margin.offset_left = ROW_OUTER_PADDING_X
	outer_margin.offset_top = ROW_OUTER_PADDING_Y
	outer_margin.offset_right = -ROW_OUTER_PADDING_X
	outer_margin.offset_bottom = -ROW_OUTER_PADDING_Y
	outer_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(outer_margin)

	var bar_container := Control.new()
	bar_container.anchor_right = 1.0
	bar_container.anchor_bottom = 1.0
	bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_margin.add_child(bar_container)

	var texture_rect := TextureRect.new()
	texture_rect.anchor_right = 1.0
	texture_rect.anchor_bottom = 1.0
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = _local_gradient_texture if use_local_style else _other_gradient_texture
	bar_container.add_child(texture_rect)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = ROW_INNER_PADDING_X
	margin.offset_top = ROW_INNER_PADDING_Y
	margin.offset_right = -ROW_INNER_PADDING_X
	margin.offset_bottom = -ROW_INNER_PADDING_Y
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.add_child(margin)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if allow_wrap else TextServer.AUTOWRAP_OFF
	label.clip_text = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17 if allow_wrap else 17)
	label.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 2)
	if allow_wrap:
		label.custom_minimum_size = Vector2(SCOREBOARD_WIDTH - 12.0, 0.0)
	margin.add_child(label)

	if allow_wrap:
		row.custom_minimum_size = Vector2(SCOREBOARD_WIDTH, SCOREBOARD_ROW_MIN_HEIGHT)
	else:
		var single_line_width: float = _measure_text_width(label, text)
		row.custom_minimum_size = Vector2(
			single_line_width + (2.0 * (ROW_OUTER_PADDING_X + ROW_INNER_PADDING_X)),
			30.0
		)

	return row

func _measure_text_width(label: Label, text: String) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	if font:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return float(text.length()) * 11.0

func _build_gradient_texture(base_color: Color, to_right: bool = true) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	
	if (to_right):
		gradient.colors = PackedColorArray([
			base_color,
			Color(base_color.r, base_color.g, base_color.b, 0.0),
		])
	else:
		gradient.colors = PackedColorArray([
			Color(base_color.r, base_color.g, base_color.b, 0.0),
			base_color,
		])
		
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.width = 640
	texture.height = 4
	return texture
