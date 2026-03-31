implementing medium;

// ── HeterogeneousMedium<V : Volume> ──────────────────────────────────────────
// Unified heterogeneous medium backed by any density volume (GridVolume,
// NanovdbVolume, or any future Volume implementor).
//
// Layout:
//   sigma_a(p) = sigma_a * density(p)     absorption coefficient
//   sigma_s(p) = sigma_s * density(p)     scattering coefficient
//   density(p) = V.sample(p) * densityScale
//
// `majorant` is the precomputed global upper bound on total extinction:
//   majorant = max_p(density(p)) = max_voxel * densityScale
//   sigma_maj = (sigma_a + sigma_s) * majorant
//
// For pure-scattering NanoVDB smoke (sigma_a=0, sigma_s=1):
//   sigma_maj = float3(majorant) = float3(sigmaMax)  — same as before.

public struct HeterogeneousParam<V : Volume> : IMediumParameter {
    public V      volume;        // density field (any Volume)
    public float3 sigma_a;       // absorption spectrum scale  (set to 0 for pure scatter)
    public float3 sigma_s;       // scattering spectrum scale  (set to 1 for unit scatter)
    public float3 Le;            // volumetric emission (set to 0 for non-emissive media)
    public float  majorant;      // max density * densityScale (global extinction bound)
    public float  densityScale;  // multiplier applied to raw voxel values
    public float  g;             // HG phase asymmetry in [-1, 1]

    public __init(V vol, float3 sa, float3 ss, float3 le, float maj, float dscale, float g_) {
        volume       = vol;
        sigma_a      = sa;
        sigma_s      = ss;
        Le           = le;
        majorant     = maj;
        densityScale = dscale;
        g            = g_;
    }
};

public struct HeterogeneousMedium<V : Volume> : IMedium {
    typealias TParam = HeterogeneousParam<V>;

    // Evaluate sigma_a, sigma_s at world point p by querying the volume.
    static func sample_point(float3 p, TParam param) -> medium::MediumProperties {
        float density = param.volume.sample(p) * param.densityScale;
        medium::MediumProperties mp;
        mp.sigma_a = param.sigma_a * density;
        mp.sigma_s = param.sigma_s * density;
        mp.Le      = param.Le;
        mp.g       = param.g;
        return mp;
    }

    // Single homogeneous majorant segment covering the full ray interval.
    static func sample_ray(Ray ray, float tMin, float tMax, TParam param)
        -> medium::HomogeneousMajorantIterator {
        float3 sigma_maj = (param.sigma_a + param.sigma_s) * param.majorant;
        return medium::HomogeneousMajorantIterator(tMin, tMax, sigma_maj);
    }
};
