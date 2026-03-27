implementing phase;

// ── HG phase parameter ────────────────────────────────────────────────────────
public struct HGParam : IPhaseParameter {
    public float g;   // asymmetry parameter in [-1, 1]

    public __init(float g_) { g = g_; }
};

// ── Henyey-Greenstein phase function ─────────────────────────────────────────
public struct HGPhaseFunction : IPhaseFunction {
    typedef HGParam TParam;

    // Analytic HG value for a given cosine angle between wo and wi.
    static func hg_value(float cosTheta, float g) -> float {
        float denom = 1.0f + g * g + 2.0f * g * cosTheta;
        return M_INV_4PI * (1.0f - g * g) / (denom * safe_sqrt(denom));
    }

    // Evaluate f(wo, wi).
    static func p(float3 wo, float3 wi, TParam param) -> float {
        return hg_value(dot(wo, wi), param.g);
    }

    // Importance-sample a direction from the HG distribution.
    static func sample_p(float3 wo, float2 u, TParam param) -> phase::SampleResult {
        const float g = param.g;

        // Sample cosTheta analytically.
        float cosTheta;
        if (abs(g) < 1e-3f) {
            cosTheta = 1.0f - 2.0f * u.x;
        } else {
            float xi  = (1.0f - g * g) / (1.0f - g + 2.0f * g * u.x);
            cosTheta  = (1.0f + g * g - xi * xi) / (2.0f * g);
        }
        cosTheta = clamp(cosTheta, -1.0f, 1.0f);

        float sinTheta = safe_sqrt(1.0f - cosTheta * cosTheta);
        float phi      = M_2PI * u.y;

        // Build an orthnormal frame around wo and transform.
        Frame frame      = Frame::from_normal(wo);
        float3 wi        = frame.to_world(float3(sinTheta * cos(phi),
                                                  sinTheta * sin(phi),
                                                  cosTheta));
        float fval = hg_value(cosTheta, g);

        phase::SampleResult result;
        result.wi  = wi;
        result.p   = float3(fval, fval, fval);
        result.pdf = fval;    // HG is its own PDF (normalised)
        return result;
    }

    // PDF equals the phase-function value for HG (self-normalised distribution).
    static func pdf(float3 wo, float3 wi, TParam param) -> float {
        return hg_value(dot(wo, wi), param.g);
    }
};