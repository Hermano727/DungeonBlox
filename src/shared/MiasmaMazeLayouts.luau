--[[
	MiasmaMazeLayouts -- the six authored valve mazes (data only).

	Format: a 7x7 cell grid drawn as 15x15 ASCII. Cell (col, row) sits at character
	(2*col+2, 2*row+2) in 1-based string terms.
		'+'  wall post (ignored)
		'-'  horizontal wall between two cells (or the outer border)
		'|'  vertical wall between two cells (or the outer border)
		'S'  the start cell (the drain the cursor starts in)
		'o'  one of the EIGHT symbol slots; runes are shuffled onto these per attempt
		' '  open

	Authoring rules, enforced by MiasmaMazeGeometry.Validate and tests/miasma_encounter.spec:
		- exactly one 'S' and exactly eight 'o';
		- every symbol sits in a dead end, so reaching one never forces the cursor through
		  another (any subset of runes can be the target);
		- with every symbol cell treated as blocked, all remaining cells stay connected to
		  the start, and every symbol cell opens onto one of them.

	Geometry, rotation/reflection and collision are all derived in MiasmaMazeGeometry.
	Change the maze by redrawing a grid here; no code changes needed.
]]

return table.freeze({
	{
		name = "Cistern",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|o|         |o|",
			"+ + + +-+-+ + +",
			"| |     |o|   |",
			"+ + +-+ + +-+ +",
			"|   |o| |     |",
			"+-+ + + + + +-+",
			"|S|     |   |o|",
			"+ + + + +-+ + +",
			"| |   |   |   |",
			"+ +-+-+-+ +-+ +",
			"|     |   |o| |",
			"+-+ + + +-+ + +",
			"|o      |o    |",
			"+-+-+-+-+-+-+-+",
		},
	},
	{
		name = "Undercroft",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|o|         |o|",
			"+ + + + +-+ + +",
			"|   |   |o  | |",
			"+ +-+ + +-+ + +",
			"| | |         |",
			"+ + +-+-+ +-+ +",
			"|    o|   |o| |",
			"+-+ +-+ +-+ + +",
			"|o|     | |   |",
			"+ + + +-+ + + +",
			"|   | |o  |   |",
			"+ +-+ +-+ +-+ +",
			"|  o|  S|     |",
			"+-+-+-+-+-+-+-+",
		},
	},
	{
		name = "Outfall",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|S|   |     |o|",
			"+ + + + +-+ + +",
			"|     |   |   |",
			"+-+-+ +-+ +-+ +",
			"|  o|   | |o  |",
			"+ +-+-+ + +-+ +",
			"|    o|     |o|",
			"+ + +-+ + + +-+",
			"|   |   |o|   |",
			"+ + + +-+-+ + +",
			"| |   |     | |",
			"+ + + + +-+ + +",
			"|o|     |o    |",
			"+-+-+-+-+-+-+-+",
		},
	},
	{
		name = "Sluiceway",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|o|         |o|",
			"+ + +-+ +-+ + +",
			"| | |o| |o    |",
			"+ + + + +-+ + +",
			"|         |   |",
			"+ +-+-+-+ +-+ +",
			"|   |   | |o| |",
			"+-+ + + + + + +",
			"|o| |     |   |",
			"+ + + + +-+ + +",
			"| | | |     |o|",
			"+ + + + +-+ +-+",
			"|   |    o|  S|",
			"+-+-+-+-+-+-+-+",
		},
	},
	{
		name = "Heart",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|     |o     o|",
			"+ +-+ +-+-+ +-+",
			"| |o      |   |",
			"+ +-+ + + + + +",
			"| |     |     |",
			"+ + +-+ +-+-+ +",
			"|   |o|S|     |",
			"+ + + +-+ +-+-+",
			"| | | |   |o  |",
			"+ + + + +-+-+ +",
			"|     | |o    |",
			"+-+-+ + +-+ + +",
			"|o          |o|",
			"+-+-+-+-+-+-+-+",
		},
	},
	{
		name = "Gullet",
		rows = {
			"+-+-+-+-+-+-+-+",
			"|o    |o      |",
			"+-+ + +-+ + + +",
			"|       |o| |o|",
			"+ + +-+ +-+ +-+",
			"|     |       |",
			"+ +-+ +-+ +-+ +",
			"|         |   |",
			"+ +-+-+ +-+ +-+",
			"|   |o| |o    |",
			"+ + + + +-+ + +",
			"|o| | |   |o| |",
			"+-+ + +-+ +-+ +",
			"|S  |         |",
			"+-+-+-+-+-+-+-+",
		},
	},
})
