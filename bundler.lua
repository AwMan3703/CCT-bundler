local INFO = {
	NAME = 'Bundler.lua',
	VERSION = '0.1.0.dev'
}
local ARGS = {...}

local DEFAULT_OUTPUT_PATH = function (path, name) return fs.combine(path, name..'_bundled.lua') end

local IMPORTED_LIBRARY_PERIMETER_PREFIX_START = function (libraryName) return '-- '..INFO.NAME:upper()..' IMPORT START '..libraryName end
local IMPORTED_LIBRARY_PERIMETER_PREFIX_END = function (libraryName) return '-- '..INFO.NAME:upper()..' IMPORT END '..libraryName end
local IMPORTED_LIBRARY_FUNCTION_NAME = function (libraryName) return 'IMPORTED_LIBRARY_' .. libraryName end
local IMPORTED_LIBRARY_INITIALIZATION = function (variableName, libraryName) return (variableName and 'local ' .. variableName .. ' = ' or '') .. IMPORTED_LIBRARY_FUNCTION_NAME(libraryName) .. '()' end

local requirePatternVariabled = '([%w_]*)[%s]*([%w_]*)%s-=%s-require%s-[(]?%s-"(.-)"%s-[)]?'
local requirePatternUnvariabled = '^%s*require%s-[(]?%s-"(.-)"%s-[)]?'


-- Gets the name portion of a file url.
--
-- Parameters:
-- - path - The location of the file.
--
-- Returns:
-- The name portion of the url.
local function getFileName(path) return path:match('[/](.-)%..-$') end

-- Gets the name & extension portion of a file url.
--
-- Parameters:
-- - path - The location of the file.
--
-- Returns:
-- The name & extension portion of the url.
local function getFileNameExtension(path) return path:match('[/](.-)$') end

-- Gets the path portion of a file url.
--
-- Parameters:
-- - path - The location of the file.
--
-- Returns:
-- The path portion of the url.
local function getFileDirectory(path) return path:match('(.*)/') end

-- Reads a file and returns a list of its lines.
--
-- Parameters:
-- - path - The location of the file.
--
-- Returns:
-- The list of file lines.
local function getFileLines(path)
	assert(fs.exists(path), path..' does not exist!')
    assert(not fs.isDir(path, path..' is a directory!'))

    local lines = {}
    for line in io.lines(path) do table.insert(lines, line) end

    return lines
end

-- If this script line is requiring an external library (local x = require("y")), extracts the variable and library name.
--
-- Parameters:
-- - line - The line to test.
--
-- Returns:
-- The variable's name (x) and the library's name (y).
local function extractRequireData(line)
    -- skip if there's no chance
    if not string.find(line, 'require') then return nil, nil end

    local variable1, variable2, libraryName = line:match(requirePatternVariabled)
	if not libraryName then libraryName = line:match(requirePatternUnvariabled) end
	if not libraryName then return nil, nil end
	-- "prefix" captures the "local" keyword. If such keyword is not found, "prefix" captures the variable name instead, so we have to switch the variables out.
	if not variable2 or #variable2 <= 0 then variable2 = variable1 end

    return variable2, libraryName
end

-- Reads code and lists all the dependencies that are imported with `require`.
--
-- Parameters:
-- - scriptlines - The lines of the script to examine.
--
-- Returns:
-- The list of dependency names and the total dependency count.
local function getScriptDependencies(scriptDirectory, scriptLines)
	local dependencies = {}
	local dependenciesCount = 0
	for i, line in ipairs(scriptLines) do
		local variableName, dependencyName = extractRequireData(line)
		if dependencyName then 
			local dependencyLines = getFileLines(fs.combine(scriptDirectory, dependencyName:gsub('%.', '/')..'.lua'))
			dependencies[dependencyName] = dependencyLines
			dependenciesCount = dependenciesCount + 1
		end
	end
	return dependencies, dependenciesCount
end

-- Creates a metadata table.
--
-- Parameters:
-- - originalScriptName - The name of the script that's being bundled
--
-- Returns:
-- The metadata table
local function createMetadataTable(originalScriptName)
	return {
		bundlerVersion = INFO.VERSION,
		bundlingDate = os.date('%D@%T'),
		bundlingComputerId = os.getComputerID(),
		originalScriptName = originalScriptName
	}
end

-- Converts between free metadata and string-bundled metadata.
--
-- Parameters:
-- - data - Either a string to extract metadata from, or a table to build the string with.
--
-- Returns:
-- Either the metadata as a table, or the built metadata string
local function metadataString(data)
	local separator = '-'

	-- If the parameter is a table, we are building the metadata string
	if type(data) == "table" then
		return ('%s'..separator..'%s'..separator..'%s'..separator..'%s'):format(
			data.bundlerVersion,
			data.bundlingDate,
			'#'..data.bundlingComputerId,
			data.originalScriptName
		)

	-- If the parameter is a string, we are extracting metadata
	elseif type(data) == "string" then
		local d = string.gmatch(data, '([^'..separator..']+)')
		return {
			bundlerVersion = d(),
			bundlingDate = d(),
			bundlingComputerId = d(),
			originalScriptName = d()
		}
	end

	error('Invalid data format: "'..tostring(data)..'"')
end

-- Bundles dependencies into file lines tables.
--
-- Parameters:
-- - scriptLines - The lines of the main script to bundle into.
-- - dependencies - A dictionary of lists, where, for each entry, the key is the name of the dependency as it appears in the require() statement (meaning, without the '.lua' extension) and the value is a list of code lines.
--
-- Returns:
-- The scriptLines table, correctly bundled with all dependencies.
local function bundle(scriptName, scriptLines, dependencies)
	local outputLines = {}
	-- Takes the contents of the the library code, wraps them in a function, and writes it in the main script.
	for i, scriptLine in ipairs(scriptLines) do
		local variableName, libraryName = extractRequireData(scriptLines[i])
		if not libraryName then
			table.insert(outputLines, scriptLine)
			goto continue
		end

		local libraryLines = dependencies[libraryName]
		if not libraryLines then goto continue end

		-- 1. Import start
		-- 2. Heading comment
		-- 3. Declare library as a function
		-- 4. All library code
		-- 5. End library as a function
		-- 6. Import end
		-- 7. Call library as a function
		table.insert(outputLines, '\n'..IMPORTED_LIBRARY_PERIMETER_PREFIX_START(libraryName))
		table.insert(outputLines, '-- Imported into '..scriptName..' with '..string.upper( INFO.NAME )..' --')
		table.insert(outputLines, 'local function '..IMPORTED_LIBRARY_FUNCTION_NAME(libraryName)..'()'..'\n')
		for il, libraryLine in ipairs(libraryLines) do
			table.insert(outputLines, '    '..libraryLine) end
		table.insert(outputLines, '\n'..'end')
		table.insert(outputLines, IMPORTED_LIBRARY_INITIALIZATION(variableName, libraryName))
		table.insert(outputLines, IMPORTED_LIBRARY_PERIMETER_PREFIX_END(libraryName)..'\n')

		::continue::
	end

	-- Add the metadata string at the beginning of the output
	local metadataString = metadataString(createMetadataTable(scriptName))
	table.insert(outputLines, 1, '-- '..metadataString)

	return outputLines
end


-- Command Line Interface
if ARGS[1] == 'build' or ARGS[1] == 'test' then
	-- Determine parameters
	local originPath = ARGS[2]
	local destinationPath = ARGS[3]

	-- Check filesystem state
	if (not fs.exists(originPath) or fs.isDir(originPath)) then printError('"'..originPath..'": file not found.') return end
	if not destinationPath then destinationPath = DEFAULT_OUTPUT_PATH(getFileDirectory(originPath), getFileName(originPath)) end
	if fs.exists(destinationPath) then printError('"'..originPath..'": already exists.') return end

	-- Get script data
	local scriptLines = getFileLines(originPath)
	local dependencies, dependencyCount = getScriptDependencies(getFileDirectory(originPath), scriptLines)
	for d,l in pairs(dependencies) do print("Found dependency: "..d) end

	-- Create bundle
	local outputLines = bundle(getFileNameExtension(originPath), scriptLines, dependencies)

	-- Run if testing, save if actually building
	if ARGS[1] == 'build' then
		-- Generate test function
		local code = table.concat(outputLines)
		local testfn = load(code)
		if not testfn then printError('Testing failed: no test function was generated') return end

		-- Run test function
		local startTimeMs = os.epoch('utc')
		testfn()
		local endTimeMs = os.epoch('utc')

		-- Print output
		print('Generated test function at: '..tostring(testfn):match(':%s*(.*)'))
	else
		-- Save file
		local ofh = fs.open(destinationPath, 'w')
		for i, line in ipairs(outputLines) do ofh.writeLine(line) end
		ofh.close()

		-- Print output
		print('Generated bundled output at: '..destinationPath)
		print('Bundle size: 1 script, '..dependencyCount..' dependencies')
		print('File size: '..#outputLines..' lines ('..(fs.getSize(destinationPath) / 1000)..' MB)')
	end
elseif not ARGS[1] or ARGS[1] == '' then
	printError('Please specify a command')
else
	printError('Invalid command')
end
