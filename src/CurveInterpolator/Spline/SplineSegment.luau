-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Define our interface
local Interface = {}

-- Math Functions
local Epsilon = (2 ^ -42)
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
		return ((value < 0) and -cubeRoot or cubeRoot)
	end

	function GetQuadRoots(degree2: number, degree1: number, constant: number): {number} -- Solve 2nd degree equations
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
end

--[[
	This function will calculate the knot sequence (for use in curve velocity vector calculations),
	based on a given value for softness, for a set of control points for a curve segment. It is used to
	calculate the velocity vectors, which determines the curvature of the segment.
	Softness = 0.5 produces a centripetal curve, while softness = 1 produces a chordal curve.
]]
local function CalculateKnotSequence(
	point1: InternalTypes.Point, point2: InternalTypes.Point, point3: InternalTypes.Point, point4: InternalTypes.Point,
	softness: number
): {number}
	if softness == 0 then
		return {0, 1, 2, 3}
	end

	local rootVariant = (0.5 * softness)
	local baseKnot = (SumOfSquares(point2, point1) ^ rootVariant)
	local secondKnot = ((SumOfSquares(point3, point2) ^ rootVariant) + baseKnot)
	return {
		0,
		baseKnot,
		secondKnot,
		((SumOfSquares(point4, point3) ^ rootVariant) + secondKnot)
	}
end

-- Calculate coefficients for a curve segment with specified parameters
export type Coefficients = {number}
export type CoefficientsPerAxis = {
	X: Coefficients;
	Y: Coefficients;
	Z: Coefficients;
}
export type CurveParameters = {
	Curviness: number; -- (0 = Linear Curve, 1 = Catmull-Rom curve)
	Softness: number; -- (0 = Uniform, 0.5 = Centripetal, 1 = Chordal)
}
local DefaultCurviness = 0.5
local DefaultSoftness = 0
local function CalculateAxisCoefficients(
	value1: number, value2: number, value3: number, value4: number,
	knotSequence: {number},
	curviness: number, softness: number
): Coefficients
	-- Now calculate our u/v values
	local u, v = 0, 0
	if knotSequence == nil then
		u = (curviness * (value3 - value1) * 0.5)
		v = (curviness * (value4 - value2) * 0.5)
	else
		local knot1, knot2 = knotSequence[1], knotSequence[2]
		local knot3, knot4 = knotSequence[3], knotSequence[4]
		if (knot2 - knot3) ~= 0 then
			local baseMultiplier = (curviness * (knot3 - knot2))

			if ((knot1 - knot2) ~= 0) and ((knot1 - knot3) ~= 0) then
				u = (
					baseMultiplier
					* (
						((value1 - value2) / (knot1 - knot2))
						- ((value1 - value3) / (knot1 - knot3))
						+ ((value2 - value3) / (knot2 - knot3))
					)
				)
			end

			if ((knot2 - knot4) ~= 0) and ((knot3 - knot4) ~= 0) then
				v = (
					baseMultiplier
					* (
						((value2 - value3) / (knot2 - knot3))
						- ((value2 - value4) / (knot2 - knot4))
						+ ((value3 - value4) / (knot3 - knot4))
					)
				)
			end
		end
	end

	-- Finally, calculate our coefficients
	return {
		((2 * value2) - (2 * value3) + u + v),
		((-3 * value2) + (3 * value3) - (2 * u) - v),
		u,
		value2
	}
end
local function CalculateCoefficientsPerAxis(
	point1: InternalTypes.Point, point2: InternalTypes.Point, point3: InternalTypes.Point, point4: InternalTypes.Point,
	curviness: number, softness: number
): CoefficientsPerAxis
	-- Determine our sequence to calculate our coefficients
	local knotSequence = (
		(softness > 0)
		and CalculateKnotSequence(point1, point2, point3, point4, softness)
		or nil
	)
	return {
		X = CalculateAxisCoefficients(
			point1.X, point2.X, point3.X, point4.X,
			knotSequence,
			curviness, softness
		);
		Y = CalculateAxisCoefficients(
			point1.Y, point2.Y, point3.Y, point4.Y,
			knotSequence,
			curviness, softness
		);
		Z = CalculateAxisCoefficients(
			point1.Z, point2.Z, point3.Z, point4.Z,
			knotSequence,
			curviness, softness
		);
	}
end

-- Calculates vector component for a point along the curve segment at the specified progress
local function GetValueAtTime(time: number, coefficients: Coefficients): number
	return (
		(coefficients[1] * (time ^ 3))
		+ (coefficients[2] * (time ^ 2))
		+ (coefficients[3] * time)
		+ coefficients[4]
	)
end

-- Calculates vector component for the derivative of the curve segment at the specified progress
local function GetDerivativeAtTime(time: number, coefficients: Coefficients): number
	return (
		(3 * coefficients[1] * (time ^ 2))
		+ (2 * coefficients[2] * time)
		+ coefficients[3]
	)
end

-- Calculates vector component for the second derivative of the curve segment at the specified progress
local function GetSecondDerivativeAtTime(time: number, coefficients: Coefficients): number
	return (
		(6 * coefficients[1] * time)
		+ (2 * coefficients[2])
	)
end

-- Solves the cubic spline for our intersection-value to get our progress-points (the roots of the spline)
local function FindSegmentTimeIntersectionsOnAxis(valueToIntersect: number, axisCoefficients: Coefficients): {number}
	-- Extract our coefficients
	local degree3, degree2 = axisCoefficients[1], axisCoefficients[2]
	local degree1, constant = axisCoefficients[3], axisCoefficients[4]

	-- Check if our whole-segment matches
	local deltaConstant = (constant - valueToIntersect)
	if (degree3 == 0) and (degree2 == 0) and (degree1 == 0) and (constant == 0) then
		return {0}
	end

	-- Finally, return all the progress-values where we intersect our provided value
	local validRoots = {}
	for _, root in ipairs(GetCubicRoots(degree3, degree2, degree1, deltaConstant)) do
		if (root > -Epsilon) and (root <= (1 + Epsilon)) then
			table.insert(validRoots, math.clamp(root, 0, 1))
		end
	end

	return validRoots
end

-- Convenience function for processing all components of a vector
export type AxisCoefficientsProcessor = ((segmentTime: number, axisCoefficients: Coefficients) -> number)
local function ProcessAxisCoefficientsAtSegmentTime(
	processor: AxisCoefficientsProcessor,
	segmentTime: number, coefficientsPerAxis: CoefficientsPerAxis
): InternalTypes.Point
	return Vector3.new(
		processor(segmentTime, coefficientsPerAxis.X),
		processor(segmentTime, coefficientsPerAxis.Y),
		processor(segmentTime, coefficientsPerAxis.Z)
	)
end

-- Expose our properties/methods
Interface.DefaultCurviness = DefaultCurviness
Interface.DefaultSoftness = DefaultSoftness

Interface.CalculateKnotSequence = CalculateKnotSequence
Interface.CalculateCoefficientsPerAxis = CalculateCoefficientsPerAxis
Interface.GetValueAtTime = GetValueAtTime
Interface.GetDerivativeAtTime = GetDerivativeAtTime
Interface.GetSecondDerivativeAtTime = GetSecondDerivativeAtTime
Interface.FindSegmentTimeIntersectionsOnAxis = FindSegmentTimeIntersectionsOnAxis
Interface.ProcessAxisCoefficientsAtSegmentTime = ProcessAxisCoefficientsAtSegmentTime

-- Now return our interface (and lock it)
table.freeze(Interface)
return Interface