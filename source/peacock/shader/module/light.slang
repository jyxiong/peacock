module light;

__include light.directional;
__include light.environment;
__include light.area;

import math;
import shape;

namespace light {

// ── Return types ──────────────────────────────────────────────────────────────
public struct Sample {
    public float3 L;    // radiance
    public float3 wi;   // direction toward the light (world space)
    public float3 p;    // query position
    public float  t;    // parametric distance (FLT_MAX for infinite lights)
    public float  pdf;  // probability density of the sampled direction
};

// ── Light interface ───────────────────────────────────────────────────────────
public interface Light {
    // Evaluate the emitted radiance for a ray arriving from world-space
    // direction `dir` (pointing away from the query point, toward the light).
    func eval(float3 dir) -> float3;

    // Draw a direction sample and return the full Sample record.
    func sample(float3 p, float2 u) -> Sample;

    // 
    func pdf(float3 p, float3 wi) -> float;
};

} // namespace light
