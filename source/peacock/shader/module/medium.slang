module medium;

import math;
import volume;
import random;
import phase;

__include medium.homogeneous;
__include medium.grid;
__include medium.nanovdb;

// ── medium: shared return types ──────────────────────────────────────────────
public namespace medium {

    // A parametric interval [tMin, tMax] with a constant extinction majorant.
    public struct RayMajorantSegment {
        public float3 sigma_maj;
        public float  tMin;
        public float  tMax;
        public bool   is_valid;
    };

    // Single-segment majorant iterator — used when sigma_maj is spatially constant.
    // Call next() once to get the single valid segment, then again to get is_valid=false.
    public struct HomogeneousMajorantIterator {
        public RayMajorantSegment seg;
        public bool called;

        public __init(float tMin, float tMax, float3 sigma_maj) {
            seg = { sigma_maj, tMin, tMax, true };
            called = false;
        }

        [mutating]
        public func next() -> RayMajorantSegment {
            if (called) {
                RayMajorantSegment s;
                s.is_valid = false;
                return s;
            }
            called = true;
            return seg;
        }
    };

    // Scattering and emission properties at a single world-space point.
    public struct MediumProperties {
        public float3 sigma_a;   // absorption coefficient
        public float3 sigma_s;   // scattering coefficient
        public float3 Le;        // volumetric emission
        public float  g;         // HG phase asymmetry in [-1, 1]
    };

} // namespace medium

// ── IMedium interface ─────────────────────────────────────────────────────────
// All methods are static so the caller never allocates the medium struct —
// only the lightweight TParam data is passed around.
public interface IMediumParameter {}

public interface IMedium {
    associatedtype TParam : IMediumParameter;

    // Evaluate absorption, scattering, and emission properties at world point p.
    static func sample_point(float3 p, TParam param) -> medium::MediumProperties;

    // Return a majorant iterator for the ray segment [tMin, tMax].
    // The iterator yields RayMajorantSegment(s) with conservative sigma_maj bounds.
    static func sample_ray(Ray ray, float tMin, float tMax, TParam param)
        -> medium::HomogeneousMajorantIterator;
}
