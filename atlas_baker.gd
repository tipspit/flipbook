@tool
class_name FlipbookBaker
## Packs frame and normal PNGs into a fast atlas the flipbook rebuilds the animation from.
extends Node

## Set the diffuse frames directory. All the PNGs are the same size.
@export_dir var dir_diffuse: String = ""
## Set the normal maps directory. Same PNGs names, 1/n the size. Folder name unlike the diffuse one.
@export_dir var dir_normal: String = ""
## Set the directory the baker writes its atlas folder into.
@export_dir var dir_out: String = ""
## Set the unique name of the output atlas resource and folder.
@export var atlas_name: String = "atlas"
## Set the width and height of a tile. Divides the frame exactly, each a multiple of 4n.
@export var tile_px := Vector2i(240, 240)
## Set the width and height of a page. Sheet of packed tiles, each a multiple of tile size + 8n.
@export var page_px := Vector2i(4096, 4096)
## Set the animation frames drawn each second. Free to choose, 24 suggested.
@export var tick_rate: int = 24

## Press to bake the atlas.
@export_tool_button("Bake") var bake: Callable = _bake

## Name of the atlas directory.
var _dir_atlas: String = ""
## Sorted list of the names of the source frames.
var _names: Array[String] = []
## Width and height of a frame.
var _frame_px := Vector2i.ZERO
## Number of columns and rows in a frame.
var _frame_grid := Vector2i.ZERO
## Scalar diffuse/normal ratio, n.
var _n: int = 1
## Gutter per side in normal texels.
var _gutter_n: int = 0
## Gutter per side in diffuse pixels.
var _gutter_d: int = 0
## Width and height of a slot, core tile plus gutter.
var _slot_px := Vector2i.ZERO
## Each unique slot's content hash, to its index.
var _slot_by_hash: Dictionary[String, int] = {}
## Slot index sequences grouped by frame, in the draw order that rebuilds it.
var _slot_seqs: Array[PackedInt32Array] = []
## Index of the next unique slot.
var _next_slot: int = 0
## Slots per page, total.
var _slots_per_page: int = 0
## Number of columns and rows in a page.
var _page_grid := Vector2i.ZERO
## Diffuse page being built.
var _page_d: Image
## Normal page being built.
var _page_n: Image
## Index of the next page to save.
var _next_page: int = 0


## Called by the inspector button to bake the atlas.
func _bake() -> void:
	@warning_ignore_start("integer_division")
	
	# Bake only the first time the button is pressed.
	if not _names.is_empty():
		print("Already baked. Reload the scene to bake again.")
		return
	print("Baking frames into atlas, wait for the done message.")
	
	# Setup the atlas directory name and the list of the names of the frames.
	_dir_atlas = dir_out.path_join(atlas_name)
	for file in DirAccess.get_files_at(dir_diffuse):
		if file.get_extension().to_lower() == "png":
			_names.append(file)
	_names.sort()
	
	# Setup the frame related variables.
	_frame_px = Image.load_from_file(dir_diffuse.path_join(_names[0])).get_size()
	_frame_grid = _frame_px / tile_px
	_n = _frame_px.x / Image.load_from_file(dir_normal.path_join(_names[0])).get_width()
	
	# Positive gutter of one BC5 block with neighbours, in diffuse pixels.
	_gutter_n = 0 if tile_px == _frame_px else 4
	_gutter_d = _gutter_n * _n
	
	# Setup the page related variables.
	_slot_px = tile_px + (2 * Vector2i(_gutter_d, _gutter_d))
	_page_grid = page_px / _slot_px
	_slots_per_page = _page_grid.x * _page_grid.y
	_page_d = Image.create(page_px.x, page_px.y, false, Image.FORMAT_RGBA8)
	_page_n = Image.create(page_px.x / _n, page_px.y / _n, false, Image.FORMAT_RGBA8)
	
	# Create the output directories.
	DirAccess.make_dir_recursive_absolute(_dir_atlas.path_join(dir_diffuse.get_file()))
	DirAccess.make_dir_recursive_absolute(_dir_atlas.path_join(dir_normal.get_file()))
	
	# Split each frame into slots, deduplicate them into the atlas pages.
	for frame_name in _names:
		var diffuse := Image.load_from_file(dir_diffuse.path_join(frame_name))
		var normal := Image.load_from_file(dir_normal.path_join(frame_name))
		
		# The rest of the baker works only on RGBA8.
		diffuse.convert(Image.FORMAT_RGBA8)
		normal.convert(Image.FORMAT_RGBA8)
		
		# Split this frame into slots, deduplicate them into the atlas pages.
		var slot_seq := PackedInt32Array()
		slot_seq.resize(_frame_grid.x * _frame_grid.y)
		for row in _frame_grid.y:
			for col in _frame_grid.x:
				var tile_rect := Rect2i(Vector2i(col, row) * tile_px, tile_px)
				var slot_d: Image = _make_slot(diffuse, tile_rect, _gutter_d, _slot_px)
				var slot_n: Image = _make_slot(normal, Rect2i(tile_rect.position / _n,
						tile_rect.size / _n), _gutter_n, _slot_px / _n)
				
				# Hash the slot pixels, diffuse + normal, so identical slots collapse to one.
				var ctx := HashingContext.new()
				ctx.start(HashingContext.HASH_SHA256)
				ctx.update(slot_d.get_data())
				ctx.update(slot_n.get_data())
				var slot_hash: String = ctx.finish().hex_encode()
				var slot: int = _next_slot
				if _slot_by_hash.has(slot_hash):
					slot = _slot_by_hash[slot_hash]
				else:
					_slot_by_hash[slot_hash] = slot
					
					# Place the new slot in the two pages, saving them when a page fills up.
					var slot_pos: int = _next_slot % _slots_per_page
					var dst := Vector2i(slot_pos % _page_grid.x,
							slot_pos / _page_grid.x) * _slot_px
					_page_d.blit_rect(slot_d, Rect2i(Vector2i.ZERO, slot_d.get_size()), dst)
					_page_n.blit_rect(slot_n, Rect2i(Vector2i.ZERO, slot_n.get_size()), dst / _n)
					_next_slot += 1
					if _next_slot % _slots_per_page == 0:
						_save_pages()
				slot_seq[row * _frame_grid.x + col] = slot
		_slot_seqs.append(slot_seq)
	
	# Save the last, partially filled page.
	if _next_slot % _slots_per_page != 0:
		_save_pages()
	
	# Save the atlas resource for the flipbook.
	var atlas := FlipbookAtlas.new()
	atlas.dir_diffuse = _dir_atlas.path_join(dir_diffuse.get_file())
	atlas.dir_normal = _dir_atlas.path_join(dir_normal.get_file())
	atlas.frame_grid = _frame_grid
	atlas.frames = _slot_seqs
	atlas.tile_px = tile_px
	atlas.gutter = _gutter_d
	atlas.slot_px = _slot_px
	atlas.slots_per_page = _slots_per_page
	atlas.page_grid = _page_grid
	atlas.tick_rate = tick_rate
	ResourceSaver.save(atlas, _dir_atlas.path_join(atlas_name + ".res"))
	print("Done baking.")
	@warning_ignore_restore("integer_division")


## Called to create a slot, the selected tile plus its gutter from the source image.
func _make_slot(src: Image, tile_rect: Rect2i, gutter: int, slot_px: Vector2i) -> Image:
	var full: Rect2i = tile_rect.grow(gutter)
	var real: Rect2i = full.intersection(Rect2i(Vector2i.ZERO, src.get_size()))
	var used: Rect2i = Rect2i(real.position - full.position, real.size)
	var slot: Image = Image.create(slot_px.x, slot_px.y, false, Image.FORMAT_RGBA8)
	
	# Build the slot from the frame and return it for interior or single tiles.
	slot.blit_rect(src, real, used.position)
	if used.size == slot_px:
		return slot
	
	# For edge tiles, fill the empty margins by replicating the used edge and return the slot.
	var left: int = used.position.x
	var right: int = used.position.x + used.size.x
	var top: int = used.position.y
	var bottom: int = used.position.y + used.size.y
	if left > 0:
		var col_strip: Image = slot.get_region(Rect2i(left, top, 1, used.size.y))
		for x in range(0, left):
			slot.blit_rect(col_strip, Rect2i(0, 0, 1, used.size.y), Vector2i(x, top))
	if right < slot_px.x:
		var col_strip: Image = slot.get_region(Rect2i(right - 1, top, 1, used.size.y))
		for x in range(right, slot_px.x):
			slot.blit_rect(col_strip, Rect2i(0, 0, 1, used.size.y), Vector2i(x, top))
	if top > 0:
		var row_strip: Image = slot.get_region(Rect2i(0, top, slot_px.x, 1))
		for y in range(0, top):
			slot.blit_rect(row_strip, Rect2i(0, 0, slot_px.x, 1), Vector2i(0, y))
	if bottom < slot_px.y:
		var row_strip: Image = slot.get_region(Rect2i(0, bottom - 1, slot_px.x, 1))
		for y in range(bottom, slot_px.y):
			slot.blit_rect(row_strip, Rect2i(0, 0, slot_px.x, 1), Vector2i(0, y))
	return slot


## Called to save the diffuse and normal pages with their .import files, then clear them for reuse.
func _save_pages() -> void:
	var page: String = "page_%03d.png" % _next_page
	
	# Save the diffuse page and its .import file, high quality and no normal map.
	var path_d: String = _dir_atlas.path_join(dir_diffuse.get_file()).path_join(page)
	_page_d.save_png(path_d)
	var f_d: FileAccess = FileAccess.open(path_d + ".import", FileAccess.WRITE)
	f_d.store_string('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]'
			+ '\n\ncompress/mode=2\ncompress/high_quality=true\ncompress/normal_map=0\n')
	f_d.close()
	
	# Save the normal page and its .import file, low quality and normal map on.
	var path_n: String = _dir_atlas.path_join(dir_normal.get_file()).path_join(page)
	_page_n.save_png(path_n)
	var f_n: FileAccess = FileAccess.open(path_n + ".import", FileAccess.WRITE)
	f_n.store_string('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]'
			+ '\n\ncompress/mode=2\ncompress/high_quality=false\ncompress/normal_map=1\n')
	f_n.close()
	
	# Prepare the pages for reuse.
	_page_d.fill(Color(0, 0, 0, 0))
	_page_n.fill(Color(0, 0, 0, 0))
	_next_page += 1
