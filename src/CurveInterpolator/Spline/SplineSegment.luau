-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Math = require(Root.Core.Math)
local Utils = require(Root.Core.Utils)

-- Define our interface
local Interface = {}

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
	local baseKnot = (Math.SumOfSquares(point2, point1) ^ rootVariant)
	local secondKnot = ((Math.SumOfSquares(point3, point2) ^ rootVariant) + baseKnot)
	return {
		0,
		baseKnot,
		secondKnot,
		((Math.SumOfSquares(point4, point3) ^ rootVariant) + secondKnot)
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
local function CalculateCoefficientsPerAxis(
	point1: InternalTypes.Point, point2: InternalTypes.Point, point3: InternalTypes.Point, point4: InternalTypes.Point,
	curveParameters: CurveParameters
): CoefficientsPerAxis
	-- Extract our parameters
	local curviness = curveParameters.Curviness
	local softness = curveParameters.Softness

	-- Determine our sequence to calculate our coefficients
	local knotSequence = (
		(softness > 0)
		and CalculateKnotSequence(point1, point2, point3, point4, softness)
		or nil
	)
	local coefficientsPerAxis = {}
	for _, axis in ipairs({"X", "Y", "Z"}) do
		-- Extract our axis-values per point
		local value1, value2 = (point1[axis] :: number), (point2[axis] :: number)
		local value3, value4 = (point3[axis] :: number), (point4[axis] :: number)

		-- Now calculate our u/v values
		local u, v = 0, 0
		if knotSequence == nil then
			u = (curviness * (value3 - value1) * 0.5)
			v = (curviness * (value4 - value2) * 0.5)
		else
			local knot1, knot2 = knotSequence[1], knotSequence[2]
			local knot3, knot4 = knotSequence[3], knotSequence[4]
			if (knot2 - knot3) ~= 0 then
				if ((knot1 - knot2) ~= 0) and ((knot1 - knot3) ~= 0) then
					u = (
						curviness
						* (knot3 - knot2)
						* (
							((value1 - value2) / (knot1 - knot2))
							- ((value1 - value3) / (knot1 - knot3))
							+ ((value2 - value3) / (knot2 - knot3))
						)
					)
				end

				if ((knot2 - knot4) ~= 0) and ((knot3 - knot4) ~= 0) then
					v = (
						curviness
						* (knot3 - knot2)
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
		coefficientsPerAxis[axis] = {
			((2 * value2) - (2 * value3) + u + v),
			((-3 * value2) + (3 * value3) - (2 * u) - v),
			u,
			value2
		}
	end

	return coefficientsPerAxis
end

-- Calculates vector component for a point along the curve segment at the specified time
local function GetValueAtTime(time: number, coefficients: Coefficients): number
	return (
		(coefficients[1] * (time ^ 3))
		+ (coefficients[2] * (time ^ 2))
		+ (coefficients[3] * time)
		+ coefficients[4]
	)
end

-- Calculates vector component for the derivative of the curve segment at the specified time
local function GetDerivativeAtTime(time: number, coefficients: Coefficients): number
	return (
		(3 * coefficients[1] * (time ^ 2))
		+ (2 * coefficients[2] * time)
		+ coefficients[3]
	)
end

-- Calculates vector component for the second derivative of the curve segment at the specified time
local function GetSecondDerivativeAtTime(time: number, coefficients: Coefficients): number
	return (
		(6 * coefficients[1] * time)
		+ (2 * coefficients[2])
	)
end

-- Solves the cubic spline for our intersection-value to get our segment-time points (the roots of the spline)
local function FindSegmentTimeIntersectionsOnAxis(valueToIntersect: number, axisCoefficients: Coefficients): {number}
	-- Extract our coefficients
	local degree3, degree2 = axisCoefficients[1], axisCoefficients[2]
	local degree1, constant = axisCoefficients[3], axisCoefficients[4]

	-- Check if our whole-segment matches
	local deltaConstant = (constant - valueToIntersect)
	if (degree3 == 0) and (degree2 == 0) and (degree1 == 0) and (constant == 0) then
		return {0}
	end

	-- Finally, return all the segment times where we intersect our provided value
	local validRoots = {}
	for _, root in ipairs(Math.GetCubicRoots(degree3, degree2, degree1, deltaConstant)) do
		if (root > -Math.Epsilon) and (root <= (1 + Math.Epsilon)) then
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
	local result = {
		X = -math.huge;
		Y = math.huge;
		Z = -math.huge;
	} -- Default for debugging

	for axis, coefficients in pairs(coefficientsPerAxis) do
		result[axis] = processor(segmentTime, coefficients)
	end

	return Vector3.new(result.X, result.Y, result.Z)
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