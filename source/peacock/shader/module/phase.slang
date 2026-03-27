module phase;

__include phase.henyey_greenstein;

import math;

// ── Return type for phase-function sampling ───────────────────────────────────
public namespace phase {
    public struct SampleResult {
        public float3 wi;   // sampled outgoing direction
        public float3 p;    // phase-function value f(wo, wi)
        public float  pdf;  // probability density of the sample
    };
}

// ── Interface for phase-function parameters ───────────────────────────────────
public interface IPhaseParameter {}

// ── Generic phase-function interface ─────────────────────────────────────────
// All methods are static so callers never need to instantiate the type.
public interface IPhaseFunction {
    associatedtype TParam : IPhaseParameter;

    // Evaluate f(wo, wi).
    static func p(float3 wo, float3 wi, TParam param) -> float;

    // Draw a sample from the phase distribution given wo and two uniform numbers.
    static func sample_p(float3 wo, float2 u, TParam param) -> phase::SampleResult;

    // PDF of the sampling distribution for the given (wo, wi) pair.
    static func pdf(float3 wo, float3 wi, TParam param) -> float;
}