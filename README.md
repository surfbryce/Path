# Path (Create a Path from any # of Points)

This is @kjerandp's [Curve Interpolator](https://github.com/kjerandp/curve-interpolator) **implemented into Roblox** and **_fully-typed_ in Luau**.

A module meant for **creating paths from a group of points** and then being able to **interact with the path to get what you want** (examples demonstrated in the Demo).

https://github.com/surfbryce/Path/assets/80861823/c7ae034c-0a35-474c-a3eb-c4e7b0bb1a8b

What you are seeing in this Demo are a few things you can do with this Module:
- *Rendering a Path* from **any number of points**
- Getting the **Point AND Curvature** on a Path at ***any Progress point***
   - Black dot traveling along the Path with its Pink (Tangent)/Blue (Normal) directional lines
- Locating the **Closest Point** on the Path to a **Provided Position**
  - Bright Yellow dot and Light Yellow dot
- Getting **all the Points** that ***INTERSECT*** an **Axis at the Provided Value**
- **Paths with different Curviness/Softness values**
   - All with Curviness = 1 and Softness: Red = 0, Green = 0.5, Blue = 1)

You can download this demo from the Repository and run (using the Server-View) exactly what is in the video.

This is a **fully-typed and documented** Roblox Luau implementation.
So if you ever need to see how something works, understand a concept,
check the types, or find out what certain options do,
**it'll all be in the code and explained**.

This implementation is also _extremely_ optimized compared to the original, being able to call the GetPointAtTime method ***100,000 TIMES*** in only **18ms** with an equal amount of unique "time"s being used. It is also the fastest implementation available on the Roblox platform with an API this extensive.

Get the [Roblox Model](https://create.roblox.com/marketplace/asset/15493350845/Path) if you want to add it from within Studio.

There is also always a [rbxm file included within the latest release](https://github.com/surfbryce/Path/releases) which you can drap and drop into Studio.

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
      what they mean. "Progress" is progress on the path. "Distance"
      is the actual measurement of that progress.
    - If you want a full-explanation of "Time", "Progress", and "Distance"
      then look into the Path class file and read the comment.
- "Tension" and "Alpha" are now "Curviness" and "Softness"
    - Most people may not be able to discern what "Tension" or "Alpha"
      (especially this one) mean in the context of a curve.
      So I've renamed them to accurately represent what they control.
    - "Curviness" determines whether or not we are linear or completely fluid.
    - "Softness" affects how aggressive/tight the path is.
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

