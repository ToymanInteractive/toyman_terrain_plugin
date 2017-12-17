# Note: `tool` is optional but without it there are no error reporting in the editor
tool

# Performs a positive integer division rounded to upper (4/2 = 2, 5/3 = 2)
static func upDiv(a, b):
	if a % b != 0:
		return a / b + 1;
	return a / b;

# Creates a 2D array as an array of arrays
static func createGrid(width, height, v=null):
	var isCreateFunction = typeof(v) == TYPE_OBJECT && v is FuncRef;
	var grid = [];
	grid.resize(height);
	for y in range(grid.size()):
		var row = [];
		row.resize(width);
		if isCreateFunction:
			for x in range(row.size()):
				row[x] = v(x,y);
		else:
			for x in range(row.size()):
				row[x] = v;
		grid[y] = row;
	return grid;

# Creates a 2D array that is a copy of another 2D array
static func cloneGrid(otherGrid):
	var grid = [];
	grid.resize(otherGrid.size());
	for y in range(grid.size()):
		var row = [];
		var otherRow = otherGrid[y];
		row.resize(otherRow.size());
		grid[y] = row;
		for x in range(row.size()):
			row[x] = otherRow[x];
	return grid;

# Resizes a 2D array and allows to set or call functions for each deleted and created cells.
# This is especially useful if cells contain objects and you don't want to loose existing data.
static func resizeGrid(grid, newWidth, newHeight, createFunction=null, deleteFunction=null):
	# Check parameters
	assert(newWidth >= 0 && newHeight >= 0);
	assert(grid != null);
	if deleteFunction != null:
		assert(typeof(deleteFunction) == TYPE_OBJECT && deleteFunction is FuncRef);
	var isCreateFunction = typeof(createFunction) == TYPE_OBJECT && createFunction is FuncRef;

	# Get old size (supposed to be rectangular!)
	var oldHeight = grid.size();
	var oldWidth = 0;
	if grid.size() != 0:
		oldWidth = grid[0].size();

	# Delete old rows
	if newHeight < oldHeight:
		if deleteFunction != null:
			for y in range(newHeight, grid.size()):
				var row = grid[y];
				for x in range(row.size()):
					deleteFunction.call_func(row[x]);
		grid.resize(newHeight);

	# Delete old columns
	if newWidth < oldWidth:
		for y in range(grid.size()):
			var row = grid[y];
			if deleteFunction != null:
				for x in range(newWidth, row.size()):
					deleteFunction.call_func(row[x]);
			row.resize(newWidth);

	# Create new columns
	if newWidth > oldWidth:
		for y in range(grid.size()):
			var row = grid[y];
			row.resize(newWidth);
			if isCreateFunction:
				for x in range(oldWidth, newWidth):
					row[x] = createFunction.call_func(x, y);
			else:
				for x in range(oldWidth, newWidth):
					row[x] = createFunction;

	# Create new rows
	if newHeight > oldHeight:
		grid.resize(newHeight);
		for y in range(oldHeight, newHeight):
			var row = [];
			row.resize(newWidth);
			grid[y] = row;
			if isCreateFunction:
				for x in range(newWidth):
					row[x] = createFunction.call_func(x, y);
			else:
				for x in range(newWidth):
					row[x] = createFunction;

	# Debug test check
	assert(grid.size() == newHeight);
	for y in range(grid.size()):
		assert(grid[y].size() == newWidth);

# Retrieves the minimum and maximum values from a grid
static func gridMinMax(grid):
	if grid.size() == 0 || grid[0].size() == 0:
		return [0, 0];
	var vMin = grid[0][0];
	var vMax = vMin;
	for y in range(grid.size()):
		var row = grid[y];
		for x in range(row.size()):
			var v = row[x];
			if v > vMax:
				vMax = v;
			elif v < vMin:
				vMin = v;
	return [vMin, vMax];

# Copies a sub-region of a grid as a new grid. No boundary check!
static func gridExtractArea(srcGrid, x0, y0, width, height):
	var dst = createGrid(width, height);
	for y in range(height):
		var dstRow = dst[y];
		var srcRow = srcGrid[y0 + y];
		for x in range(width):
			dstRow[x] = srcRow[x0 + x];
	return dst;

# Extracts data and crops the result if the requested rect crosses the bounds
static func gridExtractAreaSafeCrop(srcGrid, x0, y0, width, height):
	# Return empty is completely out of bounds
	var gridWidth = srcGrid.size();
	if gridWidth == 0:
		return [];
	var gridHeight = srcGrid[0].size();
	if x0 >= gridWidth || y0 >= gridHeight:
		return [];

	# Crop min pos
	if x0 < 0:
		width += x0;
		x0 = 0;
	if y0 < 0:
		height += y0;
		y0 = 0;

	# Crop max pos
	if x0 + width >= gridWidth:
		width = gridWidth - x0;
	if y0 + height >= gridHeight:
		height = gridHeight - y0;

	return gridExtractArea(srcGrid, x0, y0, width, height);

# Sets values from a grid inside another grid. No boundary check!
static func gridPaste(srcGrid, dstGrid, x0, y0):
	for y in range(srcGrid.size()):
		var srcRow = srcGrid[y];
		var dstRow = dstGrid[y0 + y];
		for x in range(srcRow.size()):
			dstRow[x0+x] = srcRow[x];

# Tests if two grids are the same size and contain the same values
static func gridEquals(a, b):
	if a.size() != b.size():
		return false;
	for y in range(a.size()):
		var aRow = a[y];
		var bRow = b[y];
		if aRow.size() != bRow.size():
			return false;
		for x in range(bRow.size()):
			if aRow[x] != bRow[x]:
				return false;
	return true;
