module sampler;

import math;
import medium;
import random;

// ── sampler: path-integration algorithms over IMedium ─────────────────────────
// This layer sits above both `volume` (raw data) and `medium` (optical properties).
// It provides unbiased stochastic estimators for:
//   - sample_distance  : Woodcock / delta-tracking free-path sampler
//   - eval_transmittance: ratio-tracking beam transmittance estimator
//
// Both are generic over any M : IMedium — the concrete medium type is resolved
// at compile time via Slang static dispatch on M::sample_ray / M::sample_point.

public namespace sampler {

// ── Result types ──────────────────────────────────────────────────────────────

// Returned by sample_distance on a successful scatter event.
public struct DistanceSample {
    public float  t;     // sampled free-path distance from ray origin (world units)
    public float3 pos;   // world-space scatter position (== ray.o + t * ray.d)
    public float  g;     // HG phase asymmetry at the scatter point (from MediumProperties)
};

// ── Delta-tracking distance sampler ──────────────────────────────────────────
// Samples the distance to the first real scatter event along ray in [tMin, tMax].
// Uses the null-collision (Woodcock) algorithm: unbiased, no bias even for highly
// heterogeneous media with a global majorant.
//
// Returns none if the ray exits the medium without scattering (transmission).
public static func sample_distance<M : IMedium>(
    Ray ray, float tMin, float tMax, M.TParam param,
    inout random::RandomSampler rng
) -> Optional<DistanceSample> {
    medium::HomogeneousMajorantIterator iter = M::sample_ray(ray, tMin, tMax, param);

    medium::RayMajorantSegment seg = iter.next();
    while (seg.is_valid) {
        float sigma_maj = seg.sigma_maj.x;   // scalar medium; all channels equal

        float t = seg.tMin;
        while (true) {
            // Advance by an exponentially distributed free-flight step.
            t -= log(max(rng.next_float(), 1e-6f)) / sigma_maj;
            if (t >= seg.tMax) break;

            float3 pos = ray.o + t * ray.d;
            medium::MediumProperties mp = M::sample_point(pos, param);

            float sigma_s = mp.sigma_s.x;  // scattering extinction
            float sigma_t = mp.sigma_a.x + sigma_s;

            float u = rng.next_float();
            if (u < sigma_s / sigma_maj) {
                // Real scatter event — accept
                DistanceSample ds;
                ds.t   = t;
                ds.pos = pos;
                ds.g   = mp.g;
                return ds;
            }
            else if (u < sigma_t / sigma_maj) {
                // Absorption — path absorbed (return none to signal termination)
                return none;
            }
            // else: null collision — continue free-flight (no-op)
        }

        seg = iter.next();
    }
    return none;  // ray exited [tMin, tMax] without scattering
}

// ── Ratio-tracking transmittance estimator ────────────────────────────────────
// Estimates the unattenuated fraction T = exp(-∫ sigma_t dt) along the ray.
// Unlike delta tracking, this integrates ALL samples (never hard-terminates on
// absorption), giving an unbiased estimate for use in MIS / shadow rays.
//
// Returns float3 so it can represent wavelength-dependent absorption in future.
public static func eval_transmittance<M : IMedium>(
    Ray ray, float tMin, float tMax, M.TParam param,
    inout random::RandomSampler rng
) -> float3 {
    medium::HomogeneousMajorantIterator iter = M::sample_ray(ray, tMin, tMax, param);
    float3 Tr = float3(1.0f);

    medium::RayMajorantSegment seg = iter.next();
    while (seg.is_valid) {
        float sigma_maj = seg.sigma_maj.x;

        float t = seg.tMin;
        while (true) {
            t -= log(max(rng.next_float(), 1e-6f)) / sigma_maj;
            if (t >= seg.tMax) break;

            float3 pos = ray.o + t * ray.d;
            medium::MediumProperties mp = M::sample_point(pos, param);
            float sigma_t  = mp.sigma_a.x + mp.sigma_s.x;
            float sigma_n  = max(sigma_maj - sigma_t, 0.0f);

            // Ratio-tracking weight: the null fraction leaves transmittance intact.
            Tr *= sigma_n / sigma_maj;

            // Russian roulette early termination for near-zero transmittance.
            float maxTr = max(Tr.x, max(Tr.y, Tr.z));
            if (maxTr < 0.01f) {
                float q = max(0.05f, 1.0f - maxTr);
                if (rng.next_float() < q) return float3(0.0f);
                Tr /= (1.0f - q);
            }
        }

        seg = iter.next();
    }
    return Tr;
}

} // namespace sampler
