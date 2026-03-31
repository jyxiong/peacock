implementing medium;

// ── HomogeneousMedium ─────────────────────────────────────────────────────────
// Spatially constant extinction throughout the entire volume.
// sigma_a and sigma_s are specified directly (not scaled by a density field).

public struct HomogeneousParam : IMediumParameter {
    public float3 sigma_a;   // absorption coefficient
    public float3 sigma_s;   // scattering coefficient
    public float3 Le;        // volumetric emission (set to 0 for non-emissive media)
    public float  g;         // HG phase asymmetry in [-1, 1]

    public __init(float3 sigma_a_, float3 sigma_s_, float g_) {
        sigma_a = sigma_a_;
        sigma_s = sigma_s_;
        Le      = float3(0);
        g       = g_;
    }
};

public struct HomogeneousMedium : IMedium {
    typealias TParam = HomogeneousParam;

    // Constant properties everywhere — no spatial lookup needed.
    static func sample_point(float3 p, TParam param) -> medium::MediumProperties {
        medium::MediumProperties mp;
        mp.sigma_a = param.sigma_a;
        mp.sigma_s = param.sigma_s;
        mp.Le      = param.Le;
        mp.g       = param.g;
        return mp;
    }

    // The medium is uniform, so the full interval [tMin, tMax] has a single
    // constant majorant equal to the total extinction coefficient.
    static func sample_ray(Ray ray, float tMin, float tMax, TParam param)
        -> medium::HomogeneousMajorantIterator {
        float3 sigma_maj = param.sigma_a + param.sigma_s;
        return medium::HomogeneousMajorantIterator(tMin, tMax, sigma_maj);
    }
};
