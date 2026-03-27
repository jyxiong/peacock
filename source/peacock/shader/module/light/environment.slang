implementing light;

namespace light {

// ── Environment (IBL) light ───────────────────────────────────────────────────
// Wraps an equirectangular HDR texture and provides:
//   eval(dir)      — direction → RGB radiance  (used on ray miss)
//   sample(p, u)   — uniform-sphere sample (reserved for NEE)
public struct EnvironmentLight : Light {
    public Sampler2D<float4> m_texture;

    // Convert a world-space direction to equirectangular UV coordinates.
    static func dir_to_uv(float3 dir) -> float2 {
        float phi   = atan2(dir.z, dir.x);                    // [-PI, PI]
        float theta = asin(clamp(dir.y, -1.0f, 1.0f));        // [-PI/2, PI/2]
        return float2(phi * M_INV_2PI + 0.5f,
                      0.5f - theta * M_INV_PI);
    }

    // Evaluate radiance in the given direction.
    public func eval(float3 dir) -> float3 {
        float2 uv = dir_to_uv(normalize(dir));
        return m_texture.SampleLevel(uv, 0).rgb;
    }

    // Uniform-sphere directional sample (crude; no importance sampling).
    public func sample(float3 p, float2 u) -> Interaction {
        float cosTheta  = 1.0f - 2.0f * u.y;
        float sinTheta  = safe_sqrt(1.0f - cosTheta * cosTheta);
        float phi       = M_2PI * u.x;
        float3 wi       = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

        float2 uv = dir_to_uv(wi);
        float4 L  = m_texture.SampleLevel(uv, 0);

        Interaction it;
        it.L   = L;
        it.wi  = wi;
        it.p   = p;
        it.t   = 1.0e30f;
        it.pdf = M_INV_4PI;   // uniform sphere PDF
        return it;
    }
};

} // namespace light