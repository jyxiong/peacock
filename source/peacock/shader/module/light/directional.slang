implementing light;

namespace light {

public struct DirectionalLight : Light {
    public float3 radiance;
    public float3 direction;  // world-space direction TO the light (normalized)

    func eval(float3 dir) -> float3 {
        // For a directional light, the radiance is constant for all directions.
        // The `dir` parameter is ignored, but we could check if it's opposite to
        // the light's direction and return 0 if not. For simplicity, we just
        // return the radiance unconditionally.
        return radiance;
    }

    func sample(float3 p, float2 u) -> Interaction {
        Interaction it;
        it.L   = radiance;
        it.wi  = direction;  // already points toward the light
        it.p   = p;
        it.t   = 1.0e30f;   // effectively infinite distance
        it.pdf = 1.0f;      // delta distribution (all probability mass at one direction)
        return it;
    }

    func pdf(float3 p, float3 wi) -> float {
        // PDF is 1 for the exact direction of the light, and 0 otherwise.
        // In practice, since we can't represent a true delta function, we just
        // return 1 for the correct direction and 0 for all others.
        return (wi.equals(direction)) ? 1.0f : 0.0f;
    }
};

} // namespace light