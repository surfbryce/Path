-- Root for ease-of-access
local Root = script.Parent.Parent

-- Types
local InternalTypes = require(Root.Core.InternalTypes)

-- Core Modules
local Utils = require(Root.Core.Utils)
local Math = require(Root.Core.Math)

-- Spline Modules
local SplineCurve = require(Root.Spline.SplineCurve)
local SplineSegment = require(Root.Spline.SplineSegment)

-- Our Types
type OnCacheInvalidation = (() -> ())
export type Configuration = (
	SplineSegment.CurveParameters
	& {
		Points: InternalTypes.Points;
		Closed: boolean;

		OnCacheInvalidation: OnCacheInvalidation;
	}
)
type BaseCurveMapperInternal = (
	SplineSegment.CurveParameters
	& {
		CachedCoefficientsPerAxis: {[number]: SplineSegment.CoefficientsPerAxis}; -- [SegmentIndex]: CoefficientsPerAxis
		OnCacheInvalidation: OnCacheInvalidation?;

		Points: InternalTypes.Points;
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

-- Worker Methods
do
	function CalculateCoefficientsPerAxisForSegment(
		baseCurveMapper: BaseCurveMapperInternal,
		segmentIndex: number
	): SplineSegment.CoefficientsPerAxis
		local coefficientsPerAxis = baseCurveMapper.CachedCoefficientsPerAxis[segmentIndex]
		if coefficientsPerAxis == nil then
			local controlPoints = SplineCurve.GetControlPoints(
				segmentIndex, baseCurveMapper.Points,
				baseCurveMapper.Closed
			)
			coefficientsPerAxis = SplineSegment.CalculateCoefficientsPerAxis(
				controlPoints[1], controlPoints[2], controlPoints[3], controlPoints[4],
				{
					Curviness = baseCurveMapper.Curviness;
					Softness = baseCurveMapper.Softness;
				}
			)
			baseCurveMapper.CachedCoefficientsPerAxis[segmentIndex] = coefficientsPerAxis
		end

		return coefficientsPerAxis
	end

	function ProcessAxisCoefficientsAtTime(
		baseCurveMapper: BaseCurveMapperInternal,
		processor: SplineSegment.AxisCoefficientsProcessor,
		time: number
	): InternalTypes.Point
		local segmentDetails = SplineCurve.GetSegmentDetailsAtTime(
			time, baseCurveMapper.Points,
			baseCurveMapper.Closed
		)
		local coefficientsPerAxis = CalculateCoefficientsPerAxisForSegment(baseCurveMapper, segmentDetails.Index)

		return SplineSegment.ProcessAxisCoefficientsAtSegmentTime(
			processor,
			segmentDetails.Weight, coefficientsPerAxis
		)
	end
end

-- State Management Methods
do
	function InvalidateCache(baseCurveMapper: BaseCurveMapperInternal)
		baseCurveMapper.CachedCoefficientsPerAxis = {}

		if baseCurveMapper.OnCacheInvalidation ~= nil then
			baseCurveMapper.OnCacheInvalidation()
		end
	end

	function SetCurviness(
		baseCurveMapper: BaseCurveMapperInternal,
		curviness: number
	)
		-- Validate we are in range
		Utils.AssertInRange(curviness)

		-- Now check if we've changed
		if curviness ~= baseCurveMapper.Curviness then
			baseCurveMapper.Curviness = curviness
			InvalidateCache(baseCurveMapper)
		end
	end

	function SetSoftness(
		baseCurveMapper: BaseCurveMapperInternal,
		softness: number
	)
		-- Validate we are in range
		Utils.AssertInRange(softness)

		-- Now check if we've changed
		if softness ~= baseCurveMapper.Softness then
			baseCurveMapper.Softness = softness
			InvalidateCache(baseCurveMapper)
		end
	end

	function SetPoints(
		baseCurveMapper: BaseCurveMapperInternal,
		points: InternalTypes.Points
	)
		if #points < 2 then
			error(`At least 2 points are required!`)
		end

		baseCurveMapper.Points = points
		InvalidateCache(baseCurveMapper)
	end

	function SetClosedState(
		baseCurveMapper: BaseCurveMapperInternal,
		isClosed: boolean
	)
		if baseCurveMapper.Closed ~= isClosed then
			baseCurveMapper.Closed = isClosed
			InvalidateCache(baseCurveMapper)
		end
	end
end

-- Contructor
local InterfaceMethods = {
	-- Worker Methods
	CalculateCoefficientsPerAxisForSegment = CalculateCoefficientsPerAxisForSegment;
	ProcessAxisCoefficientsAtTime = ProcessAxisCoefficientsAtTime;

	-- State Management
	InvalidateBaseCache = InvalidateCache;
	SetCurviness = SetCurviness;
	SetSoftness = SetSoftness;
	SetPoints = SetPoints;
	SetClosedState = SetClosedState;
}
export type BaseCurveMapper = (
	BaseCurveMapperInternal
	& {
		-- Worker Methods
		CalculateCoefficientsPerAxisForSegment: typeof(CalculateCoefficientsPerAxisForSegment);
		ProcessAxisCoefficientsAtTime: typeof(ProcessAxisCoefficientsAtTime);

		-- State Management
		InvalidateBaseCache: typeof(InvalidateCache);
		SetCurviness: typeof(SetCurviness);
		SetSoftness: typeof(SetSoftness);
		SetPoints: typeof(SetPoints);
		SetClosedState: typeof(SetClosedState);
	}
)
function Interface.new(configuration: Configuration): BaseCurveMapper
	local base = {
		CachedCoefficientsPerAxis = {};
		OnCacheInvalidation = configuration.OnCacheInvalidation;

		Curviness = configuration.Curviness;
		Softness = configuration.Softness;

		Points = configuration.Points;
		Closed = configuration.Closed;
	}

	for methodName, methodReference in pairs(InterfaceMethods) do
		base[methodName] = methodReference
	end

	return base
end
export type ImplementedCurveMapper = (
	BaseCurveMapper
	& {
		InvalidateCache: ((self: ImplementedCurveMapper) -> ());
		GetDistanceFromProgress: ((self: ImplementedCurveMapper, progress: number) -> number);
		GetTimeFromProgress: ((self: ImplementedCurveMapper, progress: number) -> number);
		GetProgressFromTime: ((self: ImplementedCurveMapper, time: number) -> number);
	}
)
function Interface.Implement(
	configuration: Configuration,
	properties: any,
	invalidateCache: ((self: any) -> ()),
	getDistanceFromProgress: ((self: any, progress: number) -> number),
	getTimeFromProgress: ((self: any, progress: number) -> number),
	getProgressFromTime: ((self: any, time: number) -> number)
): ImplementedCurveMapper
	-- Create our base
	local base = Interface.new(configuration)

	-- Merge our properties
	for propertyName, propertyValue in pairs(properties) do
		base[propertyName] = propertyValue
	end

	-- Add our methods
	base.InvalidateCache = invalidateCache
	base.GetDistanceFromProgress = getDistanceFromProgress
	base.GetTimeFromProgress = getTimeFromProgress
	base.GetProgressFromTime = getProgressFromTime

	-- Return the implemented result
	return base
end

-- Freeze and then return our interface
table.freeze(Interface)
return Interface