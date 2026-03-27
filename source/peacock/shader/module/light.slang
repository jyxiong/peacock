module light;

__include light.environment;

import math;

namespace light {

// ── Return types ──────────────────────────────────────────────────────────────
public struct Interaction {
    public float4 L;    // radiance
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

    // Draw a direction sample and return the full Interaction record.
    func sample(float3 p, float2 u) -> Interaction;
};

} // namespace light
