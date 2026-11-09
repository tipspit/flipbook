@tool
class_name FlipbookAtlas
## Properties of the atlas.
extends Resource

@export_group("Directories")
## Directory of the diffuse pages.
@export var dir_diffuse: String = ""
## Directory of the normal pages.
@export var dir_normal: String = ""

@export_group("Frames")
## Number of columns and rows in a frame.
@export var frame_grid := Vector2i.ZERO
## Slot index sequences grouped by frame, in the draw order that rebuilds it.
@export var frames: Array[PackedInt32Array] = []
## Animation frames drawn each second.
@export var tick_rate: int = 24

@export_group("Tiles")
## Width and height of a tile, in diffuse pixels.
@export var tile_px := Vector2i.ZERO
## Gutter per side in diffuse pixels.
@export var gutter: int = 0
## Width and height of a slot, core tile plus gutter.
@export var slot_px := Vector2i.ZERO

@export_group("Pages")
## Slots per page, total.
@export var slots_per_page: int = 0
## Number of columns and rows in a page.
@export var page_grid := Vector2i.ZERO


## Called by the inspector to show the baked values without letting them be edited.
func _validate_property(property: Dictionary) -> void:
	property.usage |= PROPERTY_USAGE_READ_ONLY
