--!strict
--!native

-- Recursively flattens an LDraw file's composition tree into a triangle
-- soup in the root file's coordinate space (LDU).
--
-- Winding: parseLDrawFile normalizes certified files to CCW-viewed-from-
-- outside. Two things can flip the effective orientation of a subtree:
--   - a mirroring transform (negative determinant)
--   - a 0 BFC INVERTNEXT on the reference
-- These compose by XOR; when flipped we swap two vertices at emit time so
-- the output is uniformly CCW-out.
--
-- Geometry from non-certified files has unknown winding and is emitted
-- double-sided (both windings) so it renders correctly either way.

local Types = require(script.Parent.Types)
local LDrawLibrary = require(script.Parent.LDrawLibrary)

local kMaxDepth = 64
local kColorInherit = 16
local kColorInheritEdge = 24

local kHugeVector = Vector3.one * math.huge

type FlattenOptions = {
	colorCode: number?,
	-- Emit uncertified geometry single-sided (backface culling holes
	-- possible) — fallback for parts whose double-sided triangle count
	-- exceeds the MeshPart limit.
	forceSingleSided: boolean?,
}

local function flattenMesh(
	library: LDrawLibrary.LDrawLibrary,
	rootRef: string,
	options: FlattenOptions?
): Types.FlatMesh?
	local rootFile = library:getFile(rootRef)
	if rootFile == nil then
		return nil
	end

	local mTriangles: { Types.FlatTriangle } = {}
	local mSharpEdges: { Types.FlatEdge } = {}
	local mSmoothEdges: { Types.FlatEdge } = {}
	local mHasUncertified = false
	local mMissingFiles: { string } = {}
	local mMissingSet: { [string]: boolean } = {}
	local mBoundsMin = kHugeVector
	local mBoundsMax = -kHugeVector

	local function emit(colorCode: number, a: Vector3, b: Vector3, c: Vector3, flip: boolean, doubleSided: boolean)
		if flip then
			b, c = c, b
		end
		table.insert(mTriangles, { colorCode = colorCode, a = a, b = b, c = c })
		if doubleSided then
			table.insert(mTriangles, { colorCode = colorCode, a = a, b = c, c = b })
		end
		mBoundsMin = mBoundsMin:Min(a):Min(b):Min(c)
		mBoundsMax = mBoundsMax:Max(a):Max(b):Max(c)
	end

	local function resolveColor(faceColor: number, inherited: number): number
		if faceColor == kColorInherit or faceColor == kColorInheritEdge then
			return inherited
		end
		return faceColor
	end

	local function recurse(file: Types.ParsedFile, transform: CFrame, invert: boolean, colorCode: number, depth: number)
		if depth > kMaxDepth then
			error("flattenMesh: max recursion depth exceeded (reference cycle?)")
		end

		-- Edge sharpness markings (winding/inversion irrelevant for lines).
		for _, line in file.lines do
			table.insert(mSharpEdges, {
				a = transform:PointToWorldSpace(line.a),
				b = transform:PointToWorldSpace(line.b),
			})
		end
		for _, line in file.condLines do
			table.insert(mSmoothEdges, {
				a = transform:PointToWorldSpace(line.a),
				b = transform:PointToWorldSpace(line.b),
			})
		end

		local certified = file.certified == true
		local hasFaces = #file.triangles > 0 or #file.quads > 0
		if hasFaces then
			-- Mirroring flips winding.
			local determinant = transform.XVector:Cross(transform.YVector):Dot(transform.ZVector)
			local flip = invert ~= (determinant < 0)
			local doubleSided = not certified
			if doubleSided then
				mHasUncertified = true
			end
			if options ~= nil and options.forceSingleSided == true then
				doubleSided = false
			end

			for _, tri in file.triangles do
				emit(
					resolveColor(tri.colorCode, colorCode),
					transform:PointToWorldSpace(tri.a),
					transform:PointToWorldSpace(tri.b),
					transform:PointToWorldSpace(tri.c),
					flip,
					doubleSided
				)
			end
			for _, quad in file.quads do
				local a = transform:PointToWorldSpace(quad.a)
				local b = transform:PointToWorldSpace(quad.b)
				local c = transform:PointToWorldSpace(quad.c)
				local d = transform:PointToWorldSpace(quad.d)
				local faceColor = resolveColor(quad.colorCode, colorCode)
				emit(faceColor, a, b, c, flip, doubleSided)
				emit(faceColor, a, c, d, flip, doubleSided)
			end
		end

		for _, ref in file.subfiles do
			local subFile = library:getFile(ref.fileName)
			if subFile == nil then
				if not mMissingSet[ref.fileName] then
					mMissingSet[ref.fileName] = true
					table.insert(mMissingFiles, ref.fileName)
				end
				continue
			end
			recurse(
				subFile,
				transform * ref.transform,
				invert ~= ref.invert,
				resolveColor(ref.colorCode, colorCode),
				depth + 1
			)
		end
	end

	local rootColor = if options ~= nil and options.colorCode ~= nil then options.colorCode else kColorInherit
	recurse(rootFile, CFrame.identity, false, rootColor, 1)

	if #mTriangles == 0 then
		mBoundsMin = Vector3.zero
		mBoundsMax = Vector3.zero
	end

	return {
		triangles = mTriangles,
		sharpEdges = mSharpEdges,
		smoothEdges = mSmoothEdges,
		hasUncertified = mHasUncertified,
		missingFiles = mMissingFiles,
		boundsMin = mBoundsMin,
		boundsMax = mBoundsMax,
	}
end

return flattenMesh
