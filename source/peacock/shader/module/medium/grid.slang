implementing medium;

// ── GridMedium ────────────────────────────────────────────────────────────────
// Heterogeneous medium backed by a uniform GridVolume (dense 3-D grid).
// Density is queried via nearest-voxel lookup; sigma_a and sigma_s are
// specified as spectral scale factors applied to the raw density value.
// A single global majorant (sigmaMax) bounds the extinction over the entire grid.

public struct GridMediumParam : IMediumParameter {
    public GridVolume volume;        // dense density grid
    public float3     sigma_a;       // absorption spectrum scale
    public float3     sigma_s;       // scattering spectrum scale
    public float      sigmaMax;      // precomputed global extinction majorant
    public float      densityScale;  // multiplier applied to raw voxel values
    public float      g;             // HG phase asymmetry in [-1, 1]

    public __init(GridVolume vol, float3 sa, float3 ss, float smax, float dscale, float g_) {
        volume       = vol;
        sigma_a      = sa;
        sigma_s      = ss;
        sigmaMax     = smax;
        densityScale = dscale;
        g            = g_;
    }
};

public struct GridMedium : IMedium {
    typedef GridMediumParam TParam;

    // Sample the density from the volume and scale by the spectrum coefficients.
    static func sample_point(float3 p, TParam param) -> medium::MediumProperties {
        float density = param.volume.sample(p) * param.densityScale;
        medium::MediumProperties mp;
        mp.sigma_a = param.sigma_a * density;
        mp.sigma_s = param.sigma_s * density;
        mp.Le      = float3(0);
        mp.g       = param.g;
        return mp;
    }

    // Use the precomputed global majorant as a single homogeneous bound.
    static func sample_ray(Ray ray, float tMin, float tMax, TParam param)
        -> medium::HomogeneousMajorantIterator {
        float3 sigma_maj = (param.sigma_a + param.sigma_s) * param.sigmaMax;
        return medium::HomogeneousMajorantIterator(tMin, tMax, sigma_maj);
    }
};

