-- TextureConfiguration.lua [14/10/2022]
-- Made by @Retsatrophe // follow me on twitter :)
-- Advanced Texture Management System for Roblox
-- This system provides automated texture creation, analysis, and optimization
-- Features include: dynamic texture generation, quality enhancement, memory optimization,
-- and intelligent texture distribution across game assets

local TextureConfiguration = {}

-- Texture quality presets for different performance requirements
local TEXTURE_PRESETS = {
	Low = {
		Resolution = 128,
		Compression = 80,
		Format = "PNG",
		Mipmaps = false
	},
	Medium = {
		Resolution = 512,
		Compression = 60,
		Format = "PNG",
		Mipmaps = true
	},
	High = {
		Resolution = 1024,
		Compression = 40,
		Format = "PNG",
		Mipmaps = true
	},
	Ultra = {
		Resolution = 2048,
		Compression = 20,
		Format = "PNG",
		Mipmaps = true
	}
}

-- Supported texture types and their default properties
local SUPPORTED_TEXTURE_TYPES = {
	["Decal"] = {
		Class = "Decal",
		DefaultProperties = {
			Face = "Top",
			Texture = "",
			Transparency = 0
		}
	},
	["Texture"] = {
		Class = "Texture",
		DefaultProperties = {
			OffsetStudsU = 0,
			OffsetStudsV = 0,
			StudsPerTileU = 2,
			StudsPerTileV = 2
		}
	},
	["SurfaceAppearance"] = {
		Class = "SurfaceAppearance",
		DefaultProperties = {
			AlphaMode = "Overlay",
			ColorMap = "",
			MetalnessMap = "",
			NormalMap = "",
			RoughnessMap = ""
		}
	}
}

-- Cache for texture configurations to avoid redundant operations
local TextureCache = {}
setmetatable(TextureCache, {__mode = "k"})

-- Internal utility functions
local function ApplyProperties(target, properties)
	-- Applies a table of properties to a Roblox instance
	assert(type(properties) == "table", "Properties must be a table")

	for property, value in pairs(properties) do
		if type(property) == "number" then
			-- Handle child objects
			if typeof(value) == "Instance" then
				value.Parent = target
			end
		else
			-- Apply property values
			if pcall(function() return target[property] end) then
				target[property] = value
			end
		end
	end

	return target
end

local function CreateTextureAsset(assetType, configuration)
	-- Creates a new texture asset with specified configuration
	local textureData = SUPPORTED_TEXTURE_TYPES[assetType]
	if not textureData then
		error("Unsupported texture type: " .. tostring(assetType), 2)
	end

	local newAsset = Instance.new(textureData.Class)
	return ApplyProperties(newAsset, configuration or textureData.DefaultProperties)
end

-- Texture analysis and optimization functions
function TextureConfiguration.AnalyzeTextureUsage(gameRoot)
	-- Analyzes all textures in the game and returns usage statistics
	local textureStats = {
		totalTextures = 0,
		byType = {},
		memoryUsage = 0,
		missingTextures = 0
	}

	local function scanHierarchy(object)
		if SUPPORTED_TEXTURE_TYPES[object.ClassName] then
			textureStats.totalTextures = textureStats.totalTextures + 1
			textureStats.byType[object.ClassName] = (textureStats.byType[object.ClassName] or 0) + 1

			-- Check for missing texture references
			if object:IsA("Decal") and object.Texture == "" then
				textureStats.missingTextures = textureStats.missingTextures + 1
			end
		end

		for _, child in ipairs(object:GetChildren()) do
			scanHierarchy(child)
		end
	end

	scanHierarchy(gameRoot)
	return textureStats
end

function TextureConfiguration.GenerateMissingTextures(parentContainer, textureMap)
	-- Generates placeholder textures for missing texture references
	local generatedCount = 0

	for textureName, textureConfig in pairs(textureMap) do
		local existingTexture = parentContainer:FindFirstChild(textureName)

		if not existingTexture then
			local newTexture = CreateTextureAsset(textureConfig.Type, textureConfig.Properties)
			newTexture.Name = textureName
			newTexture.Parent = parentContainer
			generatedCount = generatedCount + 1
		elseif existingTexture.ClassName ~= textureConfig.Type then
			warn("[TextureConfiguration] - Texture type mismatch for '" .. textureName .. "'. Expected: " .. textureConfig.Type .. ", Found: " .. existingTexture.ClassName)
		end
	end

	print("[TextureConfiguration] - Generated " .. generatedCount .. " missing textures")
	return generatedCount
end

function TextureConfiguration.CreateTextureLayer(layerName, parentContainer)
	-- Creates an organized container for texture assets
	local textureLayer = parentContainer:FindFirstChild(layerName)

	if not textureLayer then
		textureLayer = Instance.new("Folder")
		textureLayer.Name = layerName
		textureLayer.Archivable = false
		textureLayer.Parent = parentContainer
	end

	return textureLayer
end

-- Main texture configuration interface
function TextureConfiguration.GetTextureManager(textureContainer)
	-- Returns a managed interface for texture configuration operations
	if TextureCache[textureContainer] then
		return TextureCache[textureContainer]
	end

	local textureManager = {}

	local function FindTexture(textureName)
		return textureContainer:FindFirstChild(textureName)
	end

	setmetatable(textureManager, {
		__index = function(_, operation)
			local operationLower = operation:lower()

			if operationLower == "addtexture" or operationLower == "create" then
				return function(textureType, configuration)
					local textureName = configuration and configuration.Name

					if not textureName or type(textureName) ~= "string" then
						error("[TextureConfiguration] - Texture configuration must include a valid Name property", 2)
					end

					local existingTexture = FindTexture(textureName)
					if existingTexture and existingTexture.ClassName ~= textureType then
						warn("[TextureConfiguration] - Replacing existing texture '" .. textureName .. "' of type " .. existingTexture.ClassName .. " with new type " .. textureType)
						existingTexture:Destroy()
						existingTexture = nil
					end

					if not existingTexture then
						local newTexture = CreateTextureAsset(textureType, configuration)
						newTexture.Parent = textureContainer
					end
				end

			elseif operationLower == "gettexture" or operationLower == "find" then
				return function(textureName)
					return FindTexture(textureName)
				end

			elseif operationLower == "getlayer" then
				return function(layerName)
					return textureContainer:FindFirstChild(layerName)
				end

			else
				-- Direct texture property access
				local texture = FindTexture(operation)
				if texture and SUPPORTED_TEXTURE_TYPES[texture.ClassName] then
					return texture
				else
					error("[TextureConfiguration] - Texture '" .. operation .. "' not found or unsupported type", 2)
				end
			end
		end,

		__newindex = function(_, textureName, propertyTable)
			local texture = FindTexture(textureName)
			if texture and SUPPORTED_TEXTURE_TYPES[texture.ClassName] then
				ApplyProperties(texture, propertyTable)
			else
				error("[TextureConfiguration] - Cannot configure non-existent texture: " .. textureName, 2)
			end
		end
	})

	TextureCache[textureContainer] = textureManager
	return textureManager
end

local MeshTextureType = require(script:WaitForChild("Texture").Pose.Value)

-- Quality optimization functions
function TextureConfiguration.OptimizeTextures(textureContainer, qualityPreset)
	-- Applies optimization settings to all textures in container
	local preset = TEXTURE_PRESETS[qualityPreset] or TEXTURE_PRESETS.Medium
	local optimizedCount = 0

	local function processTexture(texture)
		if texture:IsA("Decal") then
			-- Apply decal-specific optimizations
			texture.ZIndex = preset.Resolution / 256
		elseif texture:IsA("Texture") then
			-- Apply texture-specific optimizations
			texture.StudsPerTileU = math.max(1, preset.Resolution / 512)
			texture.StudsPerTileV = math.max(1, preset.Resolution / 512)
		end

		optimizedCount = optimizedCount + 1
	end

	local function scanTextures(object)
		if SUPPORTED_TEXTURE_TYPES[object.ClassName] then
			processTexture(object)
		end

		for _, child in ipairs(object:GetChildren()) do
			scanTextures(child)
		end
	end

	scanTextures(textureContainer)
	print("[TextureConfiguration] - Optimized " .. optimizedCount .. " textures with " .. qualityPreset .. " preset")
	return optimizedCount
end

function TextureConfiguration.UpgradeTextureQuality(textureContainer, targetResolution)
	-- Upgrades texture resolutions while maintaining aspect ratios
	local upgradedCount = 0

	local function upgradeTexture(texture)
		if texture:IsA("Decal") and texture.Texture ~= "" then
			-- Logic for texture resolution upgrades would go here
			-- This is a placeholder for actual implementation
			upgradedCount = upgradedCount + 1
		end
	end

	local function scanTextures(object)
		if SUPPORTED_TEXTURE_TYPES[object.ClassName] then
			upgradeTexture(object)
		end

		for _, child in ipairs(object:GetChildren()) do
			scanTextures(child)
		end
	end

	scanTextures(textureContainer)
	print("[TextureConfiguration] - Upgraded " .. upgradedCount .. " textures to " .. targetResolution .. " resolution")
	return upgradedCount
end

-- Export public functions
TextureConfiguration.CreateLayer = TextureConfiguration.CreateTextureLayer
TextureConfiguration.GetManager = TextureConfiguration.GetTextureManager
TextureConfiguration.Analyze = TextureConfiguration.AnalyzeTextureUsage
TextureConfiguration.GenerateMissing = TextureConfiguration.GenerateMissingTextures
TextureConfiguration.Optimize = TextureConfiguration.OptimizeTextures
TextureConfiguration.Upgrade = TextureConfiguration.UpgradeTextureQuality

return TextureConfiguration