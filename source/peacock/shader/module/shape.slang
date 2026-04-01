module shape;

__include shape.disk;
__include shape.rectangle;
__include shape.triangle;

import math;

namespace shape {

public struct Sample {
    public float3 position;  // sampled point on the shape's surface
    public float3 normal;    // surface normal at the sampled point
    public float  pdf;       // probability density of the sample (solid-angle measure)
};

// Return type for ray-primitive intersection.
public struct HitResult {
    public bool   hit;
    public float  tHit;
    public float3 normal;
};

}

public interface IShapeParameter {};

public interface IShape {
    associatedtype TParam : IShapeParameter;

    // Ray-primitive intersection test.
    static func intersect(Ray ray, TParam param) -> shape::HitResult;

    // Sample a point on the shape's surface. Returns position, normal, and PDF
    // (solid-angle measure as seen from refPoint).
    static func sample(float3 refPoint, float2 u, TParam param)
        -> shape::Sample;

    // Compute the PDF (solid-angle measure) of having sampled surfacePoint with
    // normal surfaceNormal on this shape, as seen from refPoint.
    static func pdf(float3 refPoint, float3 surfacePoint, float3 surfaceNormal, TParam param)
        -> float;
};
