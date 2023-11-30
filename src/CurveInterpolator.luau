-- Root for ease-of-access
local Root = script

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Spline Modules
local SplineCurve = require(Root.Spline.SplineCurve)
local SplineSegment = require(Root.Spline.SplineSegment)

-- CurveMapper Modules
local BaseCurveMapper = require(Root.CurveMappers.BaseCurveMapper)
local SegmentedCurveMapper = require(Root.CurveMappers.SegmentedCurveMapper)
local NumericalCurveMapper = require(Root.CurveMappers.NumericalCurveMapper)

-- Our Types
type LookupTable<V> = {[number]: V}
type CachedLookupTables = {[string]: LookupTable<any>}
type CurveInterpolatorInternal = (
	BaseCurveMapper.ImplementedCurveMapper
	& {
		IntersectionMargin: number;
		CachedLookupTables: CachedLookupTables;
	}
)

--[[ Create our Interface

	It's very important to understand the difference between "Time" and "Progress".

	Imagine you have to run 1 mile.
	You run 0.5 miles in 2.5 minutes. You run 0.25 miles in another 2.5 minutes.
	Then finally, you run the last 0.25 miles in 5 minutes.

	In total, it took 10 minutes to run the whole mile.
	At 50% of the total time (5 minutes), you had ran 0.75 miles (75% progress).
	But at 50% progress (0.5 miles), you had only ran for 2.5 minutes (25% of the total time).

	This is the difference between "Time" and "Progress".
	How quickly you "Progress" can change; you might start fast and then slow down.
	However, "Time" always moves forward consistently, and no matter your pace,
	at any given "Time", it shows how far you've progressed.

	Both "Progress" and "Time" are normalized values ranging [0, 1].
	"Distance" is the actual measurement of "Progress".

	"Time" doesn't have a fixed measurement because our total duration can vary.
	This is why we treat it more like a timeline, where we can see the actual "Progress" at
	any point between the start (0) and end (1).

]]
local Interface = {}

-- Behavior Constants
local DefaultSearchThreshold = 0.00001
local DefaultSearchSteps = 200

-- Worker Functions
do
	-- Create and cache a lookup table of n=samples points, indexed by progress
	type LookupTableGenerationOptions = {
		From: number?;
		To: number?;

		CacheKey: string?;
		ForceCacheUpdate: true?;
	}
	function CreateLookupTable<V>(
		self: CurveInterpolatorInternal,
		valueGenerator: ((progress: number) -> V),
		samples: number, cacheKey: string
	): LookupTable<V>
		-- Verify our samples
		if samples <= 1 then
			error(`CreateLookupTable must have 2 Samples or more, Got: {samples}`)
		end

		-- Retrieve our lut and if it doesn't exist, create it.
		local lut = self.CachedLookupTables[cacheKey]
		if lut == nil then
			lut = {}

			for count = 1, samples do
				local iterationProgress = Utils.GetIterationProgress(count, samples)
				local progress = iterationProgress
				lut[progress] = valueGenerator(progress)
			end

			self.CachedLookupTables[cacheKey] = lut
		end

		return lut
	end
end

-- Worker Methods
do
	function GetPointAtTime(
		self: CurveInterpolatorInternal,
		time: number
	): InternalTypes.Point
		-- Validate we are in range
		Utils.AssertInRange(time)

		-- Handle result shortcutting
		local points: InternalTypes.Points = self.Points
		if time == 0 then
			return points[1]
		elseif time == 1 then
			return (self.Closed and points[1] or points[self.PointCount])
		end

		-- Finally, find our point by solving our axis-values
		return self:ProcessAxisCoefficientsAtTime(SplineSegment.GetValueAtTime, time)
	end

	function GetPointAtProgress(
		self: CurveInterpolatorInternal,
		progress: number
	): InternalTypes.Point
		return GetPointAtTime(self, self:GetTimeFromProgress(progress))
	end

	function GetTangentAtTime(
		self: CurveInterpolatorInternal,
		time: number
	): InternalTypes.Point
		return self:ProcessAxisCoefficientsAtTime(SplineSegment.GetDerivativeAtTime, Utils.AssertInRange(time)).Unit
	end

	function GetTangentAtProgress(
		self: CurveInterpolatorInternal,
		progress: number
	): InternalTypes.Point
		return GetTangentAtTime(self, self:GetTimeFromProgress(progress))
	end

	function GetNormalAtTime(
		self: CurveInterpolatorInternal,
		time: number
	): InternalTypes.Point
		Utils.AssertInRange(time)

		local derivative = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetDerivativeAtTime, time).Unit
		local secondDerivative = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetSecondDerivativeAtTime, time).Unit
		return derivative:Cross(secondDerivative):Cross(derivative).Unit
	end

	function GetNormalAtProgress(
		self: CurveInterpolatorInternal,
		progress: number
	): InternalTypes.Point
		return GetNormalAtTime(self, self:GetTimeFromProgress(progress))
	end

	--[[
		Finds the curvature and radius at the specified time [0, 1] on the curve. The unsigned curvature
		is returned along with radius, tangent vector and a direction vector (which points toward the center of the curvature).
	]]
	type CurvatureDetails = {
		Curvature: number;
		Radius: number;

		Normal: InternalTypes.Point;
		Tangent: InternalTypes.Point;
	}
	function GetCurvatureAtTime(
		self: CurveInterpolatorInternal,
		time: number
	): CurvatureDetails
		Utils.AssertInRange(time)

		local derivative = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetDerivativeAtTime, time)
		local secondDerivative = self:ProcessAxisCoefficientsAtTime(SplineSegment.GetSecondDerivativeAtTime, time)
		local derivativeLength = derivative.Magnitude
		local derivativeCross = derivative:Cross(secondDerivative)

		local curvature = (
			if derivativeLength > 0 then
				(derivativeCross.Magnitude / (derivativeLength ^ 3))
			else
				0
		)
		return {
			Curvature = curvature;
			Radius = ((curvature > 0) and (1 / curvature) or 0);

			Normal = derivativeCross:Cross(derivative).Unit;
			Tangent = derivative.Unit;
		}
	end

	function GetCurvatureAtProgress(
		self: CurveInterpolatorInternal,
		progress: number
	): CurvatureDetails
		return GetCurvatureAtTime(self, self:GetTimeFromProgress(progress))
	end

	--[[
		Get the closest progress, time, point, and distance on the curve to a point. This is an approximation and its
		accuracy is determined by the threshold value (smaller number requires more passes but is more precise)
	]]
	type ClosestDetails = {
		Progress: number;
		Time: number;

		Point: InternalTypes.Point;
		Distance: number;
	}
	function GetClosestDetailsToPoint(
		self: CurveInterpolatorInternal,
		point: InternalTypes.Point,
		threshold: number?, samples: number?
	): ClosestDetails
		-- Default our threshold and samples
		local threshold = (threshold or DefaultSearchThreshold)
		local samples = (samples or ((self.PointCount - 1) * 10))

		-- Verify our threshold
		if (threshold <= 0) then
			error(`Invalid Threshold ({threshold}) for GetClosestProgressToPoint`)
		end

		-- Now create our LUT
		local lut = CreateLookupTable(
			self,
			function(progress)
				return GetPointAtProgress(self, progress)
			end,
			samples,
			`LUT_Closest_{samples}`
		)

		-- First pass, find the closest point out of uniform samples along the curve
		local closestDistance, closestProgress = math.huge, 0
		for progress, pointAtProgress in pairs(lut) do
			local distance = (pointAtProgress - point).Magnitude
			if distance < closestDistance then
				closestDistance, closestProgress = distance, progress
			end
		end

		-- Grab our closest time
		local closestTime = self:GetTimeFromProgress(closestProgress)

		-- Handle bisecting our curve to narrow down our closest-time
		local closestPoint = GetPointAtTime(self, closestTime)
		local function Bisect(time: number): boolean
			if (time >= 0) and (time <= 1) then
				local pointAtTime = GetPointAtTime(self, time)
				local distance = (pointAtTime - point).Magnitude
				if distance < closestDistance then
					closestDistance, closestTime, closestPoint = distance, time, pointAtTime
				end
			end

			return false
		end

		-- Second pass, iteratively refine solution until we reach desired precision
		local step = (1 / DefaultSearchSteps)
		while step > threshold do
			if (Bisect(closestTime - step) == false) and (Bisect(closestTime + step) == false) then
				step /= 2
			end
		end

		-- Finally, return everything we've gotten
		return {
			Progress = self:GetProgressFromTime(closestTime);
			Time = closestTime;

			Point = closestPoint;
			Distance = closestDistance;
		}
	end

	type Axis = ("X" | "Y" | "Z")
	function FindTimeIntersectionsOnAxis(
		self: CurveInterpolatorInternal,
		valueToIntersect: number, axis: Axis,
		margin: number?
	): {number}
		-- Default our options
		local margin = (margin or self.IntersectionMargin)

		-- Go through and find all our time-intersections
		local timeIntersections = {}
		local pointCount = (self.Closed and (self.PointCount + 1) or self.PointCount)
		for segmentIndex = 1, (pointCount - 1) do
			-- Determine our main parameters for our segment
			local _, controlExtremeA, controlExtremeB = SplineCurve.GetControlPoints(segmentIndex, self.Points, self.Closed)
			local controlExtremeA, controlExtremeB = controlExtremeA[axis], controlExtremeB[axis]
			local coefficients = self.SegmentCoefficientsPerAxis[segmentIndex][axis]

			-- Determine the minimum/maximum value for our axis
			local axisMinimum = math.min(controlExtremeA, controlExtremeB)
			local axisMaximum = math.max(controlExtremeA, controlExtremeB)

			-- Now see if our value we want to intersect falls into our segment range
			if ((valueToIntersect + margin) >= axisMinimum) and ((valueToIntersect - margin) <= axisMaximum) then
				-- Calculate where we intersect
				local segmentTimeIntersections = SplineSegment.FindSegmentTimeIntersectionsOnAxis(
					valueToIntersect, coefficients
				)

				-- Now sort our intersections to solve in order of curve-length
				table.sort(segmentTimeIntersections)

				-- Turn our segment-time into curve-time
				for _, segmentTime in ipairs(segmentTimeIntersections) do
					table.insert(timeIntersections, Utils.GetIterationProgress((segmentTime + segmentIndex), pointCount))
				end
			end
		end

		-- Return our intersection
		return timeIntersections
	end

	function FindProgressIntersectionsOnAxis(
		self: CurveInterpolatorInternal,
		valueToIntersect: number, axis: Axis,
		margin: number?
	): {number}
		local intersections = FindTimeIntersectionsOnAxis(self, valueToIntersect, axis, margin)
		for index, time in ipairs(intersections) do
			intersections[index] = self:GetProgressFromTime(time)
		end
		return intersections
	end

	function FindPointIntersectionsOnAxis(
		self: CurveInterpolatorInternal,
		valueToIntersect: number, axis: Axis,
		margin: number?
	): {InternalTypes.Point}
		local intersections = FindTimeIntersectionsOnAxis(self, valueToIntersect, axis, margin)
		for index, time in ipairs(intersections) do
			intersections[index] = GetPointAtTime(self, time)
		end
		return intersections
	end

	function GetTotalDistance(self: CurveInterpolatorInternal)
		return self:GetDistanceFromProgress(1)
	end
end

-- State Management Functions
function OnCacheUpdate(self: CurveInterpolatorInternal)
	self.CachedLookupTables = {}
end

-- Constructor
local InterfaceMethods = {
	-- Worker Methods
	GetPointAtTime = GetPointAtTime;
	GetPointAtProgress = GetPointAtProgress;

	GetTangentAtTime = GetTangentAtTime;
	GetTangentAtProgress = GetTangentAtProgress;

	GetNormalAtTime = GetNormalAtTime;
	GetNormalAtProgress = GetNormalAtProgress;

	GetCurvatureAtTime = GetCurvatureAtTime;
	GetCurvatureAtProgress = GetCurvatureAtProgress;

	GetClosestDetailsToPoint = GetClosestDetailsToPoint;

	FindTimeIntersectionsOnAxis = FindTimeIntersectionsOnAxis;
	FindProgressIntersectionsOnAxis = FindProgressIntersectionsOnAxis;
	FindPointIntersectionsOnAxis = FindPointIntersectionsOnAxis;

	-- State Management Methods
	GetTotalDistance = GetTotalDistance;
}
export type CurveInterpolator = (
	CurveInterpolatorInternal
	& {
		-- Worker Methods
		GetPointAtTime: typeof(GetPointAtTime);
		GetPointAtProgress: typeof(GetPointAtProgress);

		GetTangentAtTime: typeof(GetTangentAtTime);
		GetTangentAtProgress: typeof(GetTangentAtProgress);

		GetNormalAtTime: typeof(GetNormalAtTime);
		GetNormalAtProgress: typeof(GetNormalAtProgress);

		GetCurvatureAtTime: typeof(GetCurvatureAtTime);
		GetCurvatureAtProgress: typeof(GetCurvatureAtProgress);

		GetClosestDetailsToPoint: typeof(GetClosestDetailsToPoint);

		FindTimeIntersectionsOnAxis: typeof(FindTimeIntersectionsOnAxis);
		FindProgressIntersectionsOnAxis: typeof(FindProgressIntersectionsOnAxis);
		FindPointIntersectionsOnAxis: typeof(FindPointIntersectionsOnAxis);

		-- State Management Methods
		GetTotalDistance: typeof(GetTotalDistance);
	}
)

export type Options = {
	Curviness: number?; -- (0 = Linear Curve, 1 = Catmull-Rom curve)
	Softness: number?; -- (0 = Uniform, 0.5 = Centripetal, 1 = Chordal)
	Closed: boolean?;

	IntersectionMargin: number?;
	ArcDivisions: number?;
	NumericalApproximationOrder: number?;
	NumericalInverseSamples: number?;
}

function Interface.new(points: InternalTypes.Points, options: Options?): CurveInterpolator
	-- Default our options
	local curviness = (((options ~= nil) and options.Curviness) or SplineSegment.DefaultCurviness)
	local softness = (((options ~= nil) and options.Softness) or SplineSegment.DefaultSoftness)
	local closed = (((options ~= nil) and options.Closed) or false)
	local intersectionMargin = (((options ~= nil) and options.IntersectionMargin) or curviness)

	-- Now create our curve-mapper
	local curveInterpolator
	local configuration: BaseCurveMapper.Configuration = {
		Curviness = curviness;
		Softness = softness;

		Points = points;
		Closed = closed;

		OnCacheUpdate = OnCacheUpdate;
	}
	curveInterpolator = (
		if (options ~= nil) and (options.ArcDivisions ~= nil) then
			SegmentedCurveMapper.new(
				(((options ~= nil) and options.ArcDivisions) or SegmentedCurveMapper.DefaultSubDivisions),
				configuration
			)
		else
			NumericalCurveMapper.new(
				(((options ~= nil) and options.NumericalApproximationOrder) or NumericalCurveMapper.DefaultQuadraturePointCount),
				(((options ~= nil) and options.NumericalInverseSamples) or NumericalCurveMapper.DefaultInverseSamples),
				configuration
			)
	)

	-- Add our properties
	curveInterpolator.IntersectionMargin = intersectionMargin
	curveInterpolator.CachedLookupTables = {}

	-- Add our methods
	for methodName, methodReference in pairs(InterfaceMethods) do
		curveInterpolator[methodName] = methodReference
	end

	-- Return our interface
	return curveInterpolator
end

-- Freeze and then return our interface
table.freeze(Interface)
return Interface