# Curve Interpolator

https://github.com/surfbryce/Curve-Interpolator-Roblox/assets/80861823/c7ae034c-0a35-474c-a3eb-c4e7b0bb1a8b

This is @kjerandp's [Curve Interpolator](https://github.com/kjerandp/curve-interpolator) **implemented into Roblox** and **_fully-typed_ in Luau**.

As the original states, this library is for:
> Interpolating values over a cubic Cardinal/Catmull-Rom spline curve of n-dimenesions

In other words, if you want to create a closed/open path from
a set of points, this is what you use.

This is a fully-typed and documented Roblox Luau implementation.
So if you ever need to see how something works, understand a concept,
check the types, or find out what certain options do,
it'll all be in the code and explained.

This implementation is also _extremely_ optimized compared to the original, being able to call the GetPointAtTime method ***100,000 TIMES*** in only **18ms** with an equal amount of unique "time"s being used. It is also the fastest implementation available on the Roblox platform with an API this extensive.

There is also a demo provided which you can use to play around with
the options and points. **Start the demo by (Run)ning a Server in Studio**.
Common use-cases found in the Demo:
- Path Rendering
- Time to Point Location and Curvature Details at Time (Normal/Tangent being used)
- Locating Closest Point on Curve to a Provided Position

Get the [Roblox Model](https://create.roblox.com/marketplace/asset/15493350845/Curve-Interpolator) if you want to add it from within Studio.

There is also always a [rbxm file included within the latest release](https://github.com/surfbryce/Curve-Interpolator-Roblox/releases) which you can drap and drop into Studio.

### Changes from the Original
- Instead of points being represented as an array, all points
are represented in Vector3.
    - A benefit of this is that Luau gives a
      static type advantage to Vector3 by representing them with their
      own static type: "vector" (meaning faster processing-times).
    - Unfortunately, if you want to use Vector2 as your point-type
      you will be forced to convert them to Vector3 and then converting
      them back to Vector2. It's not worth the overhead to support both
      types especially since we lose the static type advantage with Vector2.
- "Position" and "Length" are now "Progress" and "Distance"
    - The reasoning behind this isn't too complicated.
      These are infinitely easier terms to comprehend with extremely easy
      adoptability. When you look at these two terms you instantly understand
      what they mean. "Progress" is progress on the curve. "Distance"
      is the actual measurement of that progress.
    - If you want a full-explanation of "Time", "Progress", and "Distance"
      then look into the CurveInterpolator class file and read the comment.
- "Tension" and "Alpha" are now "Curviness" and "Softness"
    - Most people may not be able to discern what "Tension" or "Alpha"
      (especially this one) mean in the context of a curve.
      So I've renamed them to accurately represent what they control.
    - "Curviness" determines whether or not we are linear or completely fluid.
    - "Softness" affects how aggressive/tight the curve is.
- Lots of internal name changes
    - There's quite frankly too much to even list. However, if you start
      comparing between the two codebases you will find out quickly where
      it begins and you'll have trouble finding where it ends.
    - This was done because the codebase was not capable of explaining itself
      and most names were simply confusing/ambiguous.
- Module/Function Collapsing
    - A lot of performance can be saved by localizing methods and collapsing functions
      into inline code. This can be done because a majority of these module functions
      and utility functions have only one location use, so inlining them into the code
      and transferring the comments is the best way to go not only for ease of debugging
      but also for the performance since its inlined and not having to go through
      another function call or reference.
- Equation Optimization
    - Optimized the function GetValueAtTime/GetDerivativeAtTime by switching from the standard polynomial calculation to Horner's method. This change reduces the number of multiplications required for each evaluation, enhancing the function's performance and efficiency.

