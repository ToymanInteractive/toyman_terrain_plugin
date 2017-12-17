tool
extends Node

const Util = preload('toy_terrain_utils.gd');
const Chunk = preload('toy_terrain_chunk.gd');
const Mesher = preload('toy_terrain_mesher.gd');

const CHUNK_SIZE = 16;
const MAX_TERRAIN_SIZE = 1024;

# Indexes for terrain data channels
const DATA_HEIGHT = 0;
const DATA_NORMALS = 1;
const DATA_COLOR = 2;
const DATA_CHANNEL_COUNT = 3;

# Note: the limit of 1024 is only because above this, GDScript and rendering become too slow
export(int, 0, 1024) var terrainSize = 48 setget setTerrainSize, getTerrainSize;
export(Vector3) var origin = Vector3(-24, 0, -24) setget setOrigin, getOrigin;
export(Material) var material = null setget setMaterial, getMaterial;
export var generateColliders = false setget setGenerateColliders;

# TODO reduz worked on float Image format recently, keep that in mind for future optimization
var _data = [];
var _colors = [];

# Calculated
var _normals = [];

var _chunks = [];
var _chunksX = 0;
var _chunksY = 0;
var _dirtyChunks = {};
var _undoChunks = {};

func _get_property_list():
	return [
		# We just want to hide the following properties
		{
			'name': '_data',
			'type': TYPE_ARRAY,
			'usage': PROPERTY_USAGE_STORAGE
		},
		{
			'name': '_colors',
			'type': TYPE_ARRAY,
			'usage': PROPERTY_USAGE_STORAGE
		}
	];

func _ready():
	# !!!
	# TODO MEGA WARNINGS OF THE DEATH:
	# - exporting an array will load it in COW mode!!! this will break everything!!!
	# - reloading the script makes data LOST FOREVER
	# UGLY FIX, remove asap when Godot will be fixed, it severely impacts loading performance on huge terrains
	_data = Util.cloneGrid(_data);
	_colors = Util.cloneGrid(_colors);

	_onTerrainSizeChanged();
	_onGenerateCollidersChanged();
	set_process(true);

func deserializeFromJson(jsonData):
	terrainSize = int(jsonData['size']);
	_data = Util.cloneGrid(jsonData['height']);
	origin.x = jsonData['origin_x'];
	origin.y = jsonData['origin_y'];
	origin.z = jsonData['origin_z'];
	_forceUpdateAllChunks();
	_onTerrainSizeChanged();

func serializeToJson():
	return {
		'size': terrainSize,
		'origin_x': origin.x,
		'origin_y': origin.y,
		'origin_z': origin.z,
		'height': getDataChannel(DATA_HEIGHT),
		'color': getDataChannel(DATA_COLOR)
	};

func getTerrainSize():
	return terrainSize;

func setTerrainSize(newSize):
	if newSize != terrainSize:
		if newSize > MAX_TERRAIN_SIZE:
			newSize = MAX_TERRAIN_SIZE;
			print('Max size reached, clamped at ' + str(MAX_TERRAIN_SIZE) + ' for your safety :p');
		terrainSize = newSize;
		_onTerrainSizeChanged();

func getOrigin():
	return origin;

func setOrigin(newOrigin):
	if newOrigin != origin:
		origin = newOrigin;
		_forceUpdateAllChunks();
		_onTerrainSizeChanged();

func getMaterial():
	return material;

func setMaterial(newMaterial):
	if newMaterial != material:
		material = newMaterial;
		for y in range(_chunks.size()):
			var row = _chunks[y];
			for x in range(row.size()):
				var chunk = row[x];
				chunk.meshInstance.set_material_override(material);

# Direct data access for better performance.
# If you want to modify the data through this, don't forget to set the area as dirty
func getDataChannel(channel):
	if channel == DATA_HEIGHT:
		return _data;
	elif channel == DATA_COLOR:
		return _colors;
	elif channel == DATA_NORMALS:
		return _normals;
	else:
		print('Unknown channel ' + str(channel));
		assert(channel < DATA_CHANNEL_COUNT);

func _onTerrainSizeChanged():
	var prevChunksX = _chunksX;
	var prevChunksY = _chunksY;

	_chunksX = Util.upDiv(terrainSize, CHUNK_SIZE);
	_chunksY = Util.upDiv(terrainSize, CHUNK_SIZE);

	if is_inside_tree():
		Util.resizeGrid(_data, terrainSize + 1, terrainSize + 1, 0);
		Util.resizeGrid(_normals, terrainSize + 1, terrainSize + 1, Vector3(0, 1, 0));
		Util.resizeGrid(_colors, terrainSize + 1, terrainSize + 1, Color(0, 0, 0, 0));
		Util.resizeGrid(_chunks, _chunksX, _chunksY, funcref(self, '_createChunk'), funcref(self, '_deleteChunk'));

		for key in _dirtyChunks.keys():
			if key.meshInstance == null:
				_dirtyChunks.erase(key);

		# The following update code is here to handle the case where terrain size
		# is not a multiple of chunk size. In that case, not-fully-filled edge chunks may be filled
		# and must be updated.

		# Set chunks dirty on the new edge of the terrain
		for y in range(_chunks.size() - 1):
			var row = _chunks[y];
			_setChunkDirty(row[row.size() - 1]);
		if _chunks.size() != 0:
			var lastRow = _chunks[_chunks.size() - 1];
			for x in range(lastRow.size()):
				_setChunkDirty(lastRow[x]);

		# Set chunks dirty on the previous edge
		if _chunksX - prevChunksX > 0:
			for y in range(prevChunksX-1):
				var row = _chunks[y];
				_setChunkDirty(row[prevChunksX - 1])
		if _chunksY - prevChunksY > 0:
			var previousLastRow = _chunks[prevChunksY - 1];
			for x in range(previousLastRow.size()):
				_setChunkDirty(previousLastRow[x]);

		_updateAllDirtyChunks();

func _deleteChunk(chunk):
	chunk.meshInstance.queue_free();
	chunk.meshInstance = null;

func _createChunk(x, y):
	var chunk = Chunk.new();
	chunk.meshInstance = MeshInstance.new();
	chunk.meshInstance.set_name('chunk_' + str(x) + '_' + str(y));
	chunk.meshInstance.set_translation(Vector3(x, 0, y) * CHUNK_SIZE);
	if material != null:
		chunk.meshInstance.set_material_override(material);
	chunk.position = Vector2(x, y);
	add_child(chunk.meshInstance);
	_setChunkDirty(chunk);
	return chunk;

# Call this just before modifying the terrain
func setAreaDirty(tx, ty, radius, markForUndo=false, dataChannel=DATA_HEIGHT):
	var cxMin = (tx - radius) / CHUNK_SIZE;
	var cyMin = (ty - radius) / CHUNK_SIZE;
	var cxMax = (tx + radius) / CHUNK_SIZE;
	var cyMax = (ty + radius) / CHUNK_SIZE;

	for cy in range(cyMin, cyMax + 1):
		for cx in range(cxMin, cxMax + 1):
			if cx >= 0 && cy >= 0 && cx < _chunksX && cy < _chunksY:
				_setChunkDirtyAt(cx, cy);
				if markForUndo:
					var chunk = _chunks[cy][cx];
					if not _undoChunks.has(chunk):
						var data = extractChunkData(cx, cy, dataChannel);
						_undoChunks[chunk] = data;

func extractChunkData(cx, cy, dataChannel):
	var x0 = cx * CHUNK_SIZE;
	var y0 = cy * CHUNK_SIZE;
	var grid = getDataChannel(dataChannel);
	var cellData = Util.gridExtractAreaSafeCrop(grid, x0, y0, CHUNK_SIZE, CHUNK_SIZE);
	var d = {
		'cx': cx,
		'cy': cy,
		'data': cellData,
		'channel': dataChannel
	};
	return d;

func applyChunksData(chunksData):
	for cdata in chunksData:
		_setChunkDirtyAt(cdata.cx, cdata.cy);
		var x0 = cdata.cx * CHUNK_SIZE;
		var y0 = cdata.cy * CHUNK_SIZE;
		var grid = getDataChannel(cdata.channel);
		Util.gridPaste(cdata.data, grid, x0, y0);

# Get this data just after finishing an edit action (if you use undo/redo)
func popUndoRedoData(dataChannel):
	var undoData = [];
	var redoData = [];

	for k in _undoChunks:
		var undo = _undoChunks[k];
		undoData.append(undo);

		var redo = extractChunkData(undo.cx, undo.cy, dataChannel);
		redoData.append(redo);

		# Debug check
		#assert(not Util.gridEquals(undo.data, redo.data));

	_undoChunks = {};
	return {undo = undoData, redo = redoData};

func _setChunkDirtyAt(cx, cy):
	_setChunkDirty(_chunks[cy][cx]);

func _setChunkDirty(chunk):
	_dirtyChunks[chunk] = true;

func _process(delta):
	_updateAllDirtyChunks();

func _updateAllDirtyChunks():
	for chunk in _dirtyChunks:
		updateChunkAt(chunk.position.x, chunk.position.y);
	_dirtyChunks.clear();

func _forceUpdateAllChunks():
	for y in range(_chunks.size()):
		var row = _chunks[y];
		for x in range(row.size()):
			updateChunk(row[x]);

func worldToCellPosition(wpos):
	return Vector2(int(wpos.x), int(wpos.z));

func cellPositionIsValid(x, y):
	return x >= 0 && y >= 0 && x <= terrainSize && y <= terrainSize;

func updateChunkAt(cx, cy):
	var chunk = _chunks[cy][cx];
	updateChunk(chunk);

# This function is the most time-consuming one in this tool.
func updateChunk(chunk):
	var x0 = chunk.position.x * CHUNK_SIZE;
	var y0 = chunk.position.y * CHUNK_SIZE;
	var width = CHUNK_SIZE;
	var height = CHUNK_SIZE;

	_updateNormalsDataAt(x0, y0, width + 1, height + 1);

	var mesh = Mesher.makeHeightmap(_data, _normals, _colors, x0, y0, width, height, origin);
	chunk.meshInstance.set_mesh(mesh);

	if !Engine.is_editor_hint():
		if generateColliders:
			chunk.updateCollider();
		else:
			chunk.clearCollider();

func getTerrainHeight(x, y):
	if x < 0 || y < 0 || x >= terrainSize || y >= terrainSize:
		return 0.0;
	return _data[y][x];

func getTerrainValueWorldV(position):
	return getTerrainHeight(int(position.x), int(position.z));

func positionIsAbove(position):
	position -= origin;
	return position.y > getTerrainValueWorldV(position);

func _calculateNormalAt(x, y):
	var left = getTerrainHeight(x - 1, y);
	var right = getTerrainHeight(x + 1, y);
	var fore = getTerrainHeight(x, y + 1);
	var back = getTerrainHeight(x, y - 1);
	return Vector3(left - right, 2.0, back - fore).normalized();

func _updateNormalsDataAt(x0, y0, widht, height):
	if x0 + widht > terrainSize:
		widht = terrainSize - x0;
	if y0 + height > terrainSize:
		height = terrainSize - y0;
	var maxX = x0 + widht;
	var maxY = y0 + height;
	for y in range(y0, maxY):
		var row = _normals[y];
		for x in range(x0, maxX):
			row[x] = _calculateNormalAt(x, y);

# This is a quick and dirty raycast, but it's enough for edition
func raycast(rayOrigin, rayDir):
	if not positionIsAbove(rayOrigin):
		return null;
	var position = rayOrigin;
	var unit = 1.0;
	var distance = 0.0;
	var maxDistance = 40000.0;
	while distance < maxDistance:
		position += rayDir * unit;
		if not positionIsAbove(position):
			return position - rayDir * unit - origin;
		distance += unit;
	return null;

func setGenerateColliders(needColliders):
	if generateColliders != needColliders:
		generateColliders = needColliders;
		_onGenerateCollidersChanged();

func _onGenerateCollidersChanged():
	# Don't generate colliders if not in tree yet, will produce errors otherwise
	if not is_inside_tree():
		return;
	# Don't generate colliders in the editor, it's useless and time consuming
	if Engine.is_editor_hint():
		return;

	for cy in range(_chunks.size()):
		var row = _chunks[cy];
		for cx in range(row.size()):
			var chunk = row[cx];
			if generateColliders:
				chunk.updateCollider();
			else:
				chunk.clearCollider();
