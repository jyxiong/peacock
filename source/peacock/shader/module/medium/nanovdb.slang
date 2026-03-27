implementing medium;

// ── NanovdbMedium ──────────────────────────────────────────────────────────────
// Specialised version of GridMedium for pure-scattering NanoVDB smoke/fire grids.
// Assumes zero absorption (sigma_a = 0); the single densityScale value converts
// the raw NanoVDB floating-point voxel into an extinction coefficient.
// sigmaMax must be supplied by the host (typically: grid.maximum() * densityScale).

public struct NanovdbParam : IMediumParameter {
    public NanovdbVolume volume;      // NanoVDB grid wrapped as a Volume
    public float         sigmaMax;    // precomputed global extinction majorant
    public float         densityScale;// raw density → extinction scale factor
    public float         g;           // HG phase asymmetry in [-1, 1]

    public __init(NanovdbVolume vol, float smax, float dscale, float g_) {
        volume       = vol;
        sigmaMax     = smax;
        densityScale = dscale;
        g            = g_;
    }
};

public struct NanovdbMedium : IMedium {
    typedef NanovdbParam TParam;

    // Query density and return sigma_s = density; sigma_a = 0 (pure scattering).
    static func sample_point(float3 p, TParam param) -> medium::MediumProperties {
        float density = param.volume.sample(p) * param.densityScale;
        medium::MediumProperties mp;
        mp.sigma_a = float3(0);
        mp.sigma_s = float3(density);
        mp.Le      = float3(0);
        mp.g       = param.g;
        return mp;
    }

    // Single homogeneous majorant segment covering the full ray interval.
    static func sample_ray(Ray ray, float tMin, float tMax, TParam param)
        -> medium::HomogeneousMajorantIterator {
        return medium::HomogeneousMajorantIterator(
            tMin, tMax, float3(param.sigmaMax));
    }
};
