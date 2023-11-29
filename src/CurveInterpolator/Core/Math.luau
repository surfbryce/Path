-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Constants
local Epsilon = (2 ^ -42)

-- Create our Interface
local Interface = {
	Epsilon = Epsilon;
}

-- Base Methods
do
	function IsFinite(value: number): boolean
		return ((value > -math.huge) and (value < math.huge))
	end
	
	-- Expose our methods
	Interface.IsFinite = IsFinite
end

-- Root Methods
do
	function SumOfSquares(a: Vector3, b: Vector3): number
		return (
			((a.X - b.X) ^ 2)
			+ ((a.Y - b.Y) ^ 2)
			+ ((a.Z - b.Z) ^ 2)
		)
	end

	function GetCubeRoot(value: number): number
		local cubeRoot = (math.abs(value) ^ (1 / 3))
		return ((cubeRoot < 0) and -cubeRoot or cubeRoot)
	end

	-- Solve 2nd degree equations
	function GetQuadRoots(degree2: number, degree1: number, constant: number): {number}
		if math.abs(degree2) < Epsilon then -- Linear case, (ax + b = 0)
			if math.abs(degree1) < Epsilon then -- Degenerate case
				return {}
			end

			return {-constant / degree1}
		end

		local d = ((degree1 ^ 2) - (4 * degree2 * constant))
		if math.abs(d) < Epsilon then
			return {-degree1 / (2 * degree2)}
		elseif d > 0 then
			local sqrtD, doubleDegree2 = math.sqrt(d), (2 * degree2)
			return {
				((-degree1 + sqrtD) / doubleDegree2),
				((-degree1 - sqrtD) / doubleDegree2)
			}
		end

		return {}
	end

	-- Solve 3rd degree equations
	function GetCubicRoots(degree3: number, degree2: number, degree1: number, constant: number): {number}
		if math.abs(degree3) < Epsilon then -- Quadratic Case, (((ax ^ 2) + bx + c) = 0)
			return GetQuadRoots(degree2, degree1, constant)
		end

		-- Convert to a depressed cubic ((t ^ 3) + pt + q) = 0 (subst x = (t - (b / 3a)))
		local p = (((3 * degree3 * degree1) - (degree2 ^ 2)) / (3 * (degree3 ^ 2)))
		local q = (
			((2 * (degree2 ^ 3)) - (9 * degree3 * degree2 * degree1) + (27 * (degree3 ^ 2) * constant))
			/ (27 * (degree3 ^ 3))
		)

		-- Now solve for our roots
		local roots: {number}
		if math.abs(p) < Epsilon then -- p = 0 -> (t ^ 3) = -q -> t = (-q ^ (1 / 3))
			roots = {GetCubeRoot(-q)}
		elseif math.abs(q) < Epsilon then -- q = 0 -> ((t ^ 3) + pt) = 0 -> (t * ((t ^ 2) + p)) = 0
			if p < 0 then
				local sqrtNegativeP = math.sqrt(-p)
				roots = {0, sqrtNegativeP, -sqrtNegativeP}
			else
				roots = {0}
			end
		else
			local qpRatio = (q / p)
			local d = (((q ^ 2) / 4) + ((p ^ 3) / 27))
			if math.abs(d) < Epsilon then -- D = 0 -> 2 Roots
				roots = {(-1.5 * qpRatio), (3 * qpRatio)}
			elseif d > 0 then -- Only one real root
				local u = GetCubeRoot((-q / 2) - math.sqrt(d))
				roots = {u - (p / (3 * u))}
			else -- D < 0, 3 Roots, but needs to use complex numbers/trigonometric solution
				local u = (2 * math.sqrt(-p / 3))
				local t = (math.acos((3 * qpRatio) / u) / 3) -- D < 0 implies p < 0 and acos argument in [-1 .. 1]
				local k = ((2 * math.pi) / 3)
				roots = {
					(u * math.cos(t)),
					(u * math.cos(t - k)),
					(u * math.cos(t - (2 * k)))
				}
			end
		end

		-- Convert roots back from our depressed-cubic roots
		for index, root in ipairs(roots) do
			roots[index] -= (degree2 / (3 * degree3))
		end

		return roots
	end

	-- Expose our methods
	Interface.SumOfSquares = SumOfSquares
	Interface.GetCubeRoot = GetCubeRoot
	Interface.GetQuadRoots = GetQuadRoots
	Interface.GetCubicRoots = GetCubicRoots
end

-- Vector Methods
do
	local function RotateVector(vector: Vector3, axis: Vector3, angle: number)
		return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(vector)
	end

	-- Expose our properties/methods
	Interface.DefaultRotationAxis = Vector3.new(0, 1, 0)
	Interface.RotateVector = RotateVector
end

-- Interface return
table.freeze(Interface)
return Interface