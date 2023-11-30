-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)

-- Spline Modules
local SplineCurve = require(Root.Spline.SplineCurve)
local SplineSegment = require(Root.Spline.SplineSegment)

-- Our Types
type OnCacheUpdate = ((self: any) -> ())
export type Configuration = (
	SplineSegment.CurveParameters
	& {
		Points: InternalTypes.Points;
		Closed: boolean;

		OnCacheUpdate: OnCacheUpdate;
	}
)
type BaseCurveMapperInternal = (
	SplineSegment.CurveParameters
	& {
		SegmentCoefficientsPerAxis: {[number]: SplineSegment.CoefficientsPerAxis}; -- [SegmentIndex]: CoefficientsPerAxis
		OnCacheUpdate: OnCacheUpdate?;
		ConfigurationOnCacheUpdate: OnCacheUpdate?;

		Points: InternalTypes.Points;
		PointCount: number;
		Closed: boolean;
	}
)

--[[ Create our interface

	The curve mapper's main responsibility is to map between curve 'Progress' and segment  'Time'.

	Since it requires access to control points and curve parameters, it also keeps
	this data along with an internal cache. For this reason, the common
	functionality has been implemented here, so that the mapping specific implementation
	can be held at a minimum by using this interface.

]]
local Interface = {}

-- Storage Functions
do
	function CalculateCoefficientsPerAxisForSegments(self: BaseCurveMapperInternal)
		local points = self.Points
		local pointCount = self.PointCount
		local isClosed = self.Closed
		local segmentCoefficientsPerAxis = {}
		for segmentIndex = 1, (isClosed and pointCount or (pointCount - 1)) do
			local point1, point2, point3, point4 = SplineCurve.GetControlPoints(segmentIndex, points, isClosed)
			segmentCoefficientsPerAxis[segmentIndex] = SplineSegment.CalculateCoefficientsPerAxis(
				point1, point2, point3, point4,
				self.Curviness, self.Softness
			)
		end
		self.SegmentCoefficientsPerAxis = segmentCoefficientsPerAxis
	end
end

-- Worker Methods
do
	function ProcessAxisCoefficientsAtTime(
		self: BaseCurveMapperInternal,
		processor: SplineSegment.AxisCoefficientsProcessor,
		time: number
	): InternalTypes.Point
		--[[
			Find the spline segment index and the corresponding segment weight/fraction
			at the provided non-linear progress on the curve
		]]
		local segmentIndex, weight
		do
			-- This is equal to the last valid segment-index + full-weight (1)
			local maximumPointSegmentIndex = (
				self.Closed
				and (self.PointCount + 1)
				or self.PointCount
			)

			-- If we're at the end we can take this shortcut
			if time == 1 then
				segmentIndex, weight = (maximumPointSegmentIndex - 1), 1
			else
				local rawPointCountIndex = Utils.GetIndexFromScale(time, maximumPointSegmentIndex, true)
				segmentIndex = math.floor(rawPointCountIndex)
				weight = (rawPointCountIndex - segmentIndex)
			end
		end

		-- Finally, calculate our axis-coefficients
		return SplineSegment.ProcessAxisCoefficientsAtSegmentTime(
			processor,
			weight, self.SegmentCoefficientsPerAxis[segmentIndex]
		)
	end
end

-- State Management Functions
do
	function UpdateCache(self: BaseCurveMapperInternal)
		CalculateCoefficientsPerAxisForSegments(self)

		if self.OnCacheUpdate ~= nil then
			self.OnCacheUpdate(self)
		end

		if self.ConfigurationOnCacheUpdate ~= nil then
			self.ConfigurationOnCacheUpdate(self)
		end
	end

	function AssertPoints(points: InternalTypes.Points)
		if #points < 2 then
			error(`At least 2 points are required!`)
		end
	end
end

-- State Management Methods
do
	function SetCurviness(
		self: BaseCurveMapperInternal,
		curviness: number
	)
		-- Validate we are in range
		Utils.AssertInRange(curviness)

		-- Now check if we've changed
		if curviness ~= self.Curviness then
			self.Curviness = curviness
			UpdateCache(self)
		end
	end

	function SetSoftness(
		self: BaseCurveMapperInternal,
		softness: number
	)
		-- Validate we are in range
		Utils.AssertInRange(softness)

		-- Now check if we've changed
		if softness ~= self.Softness then
			self.Softness = softness
			UpdateCache(self)
		end
	end

	function SetPoints(
		self: BaseCurveMapperInternal,
		points: InternalTypes.Points
	)
		AssertPoints(points)

		self.Points, self.PointCount = points, #points
		UpdateCache(self)
	end

	function SetClosedState(
		self: BaseCurveMapperInternal,
		isClosed: boolean
	)
		if self.Closed ~= isClosed then
			self.Closed = isClosed
			UpdateCache(self)
		end
	end
end

-- Contructor
local InterfaceMethods = {
	-- Worker Methods
	ProcessAxisCoefficientsAtTime = ProcessAxisCoefficientsAtTime;

	-- State Management
	SetCurviness = SetCurviness;
	SetSoftness = SetSoftness;
	SetPoints = SetPoints;
	SetClosedState = SetClosedState;
}
export type BaseCurveMapper = (
	BaseCurveMapperInternal
	& {
		-- Worker Methods
		ProcessAxisCoefficientsAtTime: typeof(ProcessAxisCoefficientsAtTime);

		-- State Management
		SetCurviness: typeof(SetCurviness);
		SetSoftness: typeof(SetSoftness);
		SetPoints: typeof(SetPoints);
		SetClosedState: typeof(SetClosedState);
	}
)
function Interface.new(configuration: Configuration, doNotUpdateCache: true?): BaseCurveMapper
	AssertPoints(configuration.Points)
	Utils.AssertInRange(configuration.Curviness)
	Utils.AssertInRange(configuration.Softness)

	local base = {
		SegmentCoefficientsPerAxis = {};
		ConfigurationOnCacheUpdate = configuration.OnCacheUpdate;

		Curviness = configuration.Curviness;
		Softness = configuration.Softness;

		Points = configuration.Points;
		PointCount = #configuration.Points;
		Closed = configuration.Closed;
	}

	for methodName, methodReference in pairs(InterfaceMethods) do
		base[methodName] = methodReference
	end

	if doNotUpdateCache == nil then
		UpdateCache(base)
	end

	return base
end
export type ImplementedCurveMapper = (
	BaseCurveMapper
	& {
		OnCacheUpdate: ((self: ImplementedCurveMapper) -> ());
		GetDistanceFromProgress: ((self: ImplementedCurveMapper, progress: number) -> number);
		GetTimeFromProgress: ((self: ImplementedCurveMapper, progress: number) -> number);
		GetProgressFromTime: ((self: ImplementedCurveMapper, time: number) -> number);
	}
)
function Interface.Implement(
	configuration: Configuration,
	properties: any,
	onCacheUpdate: ((self: any) -> ()),
	getDistanceFromProgress: ((self: any, progress: number) -> number),
	getTimeFromProgress: ((self: any, progress: number) -> number),
	getProgressFromTime: ((self: any, time: number) -> number)
): ImplementedCurveMapper
	-- Create our base
	local base = Interface.new(configuration, true)

	-- Merge our properties
	for propertyName, propertyValue in pairs(properties) do
		base[propertyName] = propertyValue
	end

	-- Add our methods
	base.OnCacheUpdate = onCacheUpdate
	base.GetDistanceFromProgress = getDistanceFromProgress
	base.GetTimeFromProgress = getTimeFromProgress
	base.GetProgressFromTime = getProgressFromTime

	-- Update our cache
	UpdateCache(base)

	-- Return the implemented result
	return base
end

-- Freeze and then return our interface
table.freeze(Interface)
return Interface