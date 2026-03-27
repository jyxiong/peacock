module random;

// Random number generation — PCG32i (permuted congruential generator).
// Adapted from Reed et al. and the nvpro-samples mini path tracer tutorial.

namespace random {

// ── Seed utilities ────────────────────────────────────────────────────────────
// A single-step PCG/CRNG hash — mixes correlations out of sequential seeds.
uint hash_crng(uint seed) {
    const uint state = seed * 747796405u + 2891336453u;
    const uint word  = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// ── Sampler struct ────────────────────────────────────────────────────────────
public struct RandomSampler {
    public uint state;

    // Advance the state and return a raw 32-bit integer.
    [mutating]
    public func next_uint() -> uint {
        state = state * 747796405u + 1u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    // Return a uniform float in [0, 1).
    [mutating]
    public func next_float() -> float {
        return float(next_uint()) * (1.0f / 4294967296.0f);
    }

    [mutating]
    public func next_float2() -> float2 { return float2(next_float(), next_float()); }

    [mutating]
    public func next_float3() -> float3 { return float3(next_float(), next_float(), next_float()); }
};

// ── Factory helpers ───────────────────────────────────────────────────────────
// Initialise from a 2-D pixel position (upper 16 bits = x, lower 16 bits = y)
// plus a per-frame counter so each frame produces independent samples.
public func init_random_sampler(uint2 pixelPos, uint frameIndex) -> RandomSampler {
    RandomSampler r;
    r.state = frameIndex + hash_crng((pixelPos.x << 16u) | pixelPos.y);
    return r;
}

// Flat thread-index variant for compute shaders.
public func init_random_sampler(uint threadIndex, uint frameIndex) -> RandomSampler {
    RandomSampler r;
    r.state = frameIndex + hash_crng(threadIndex);
    return r;
}

// Sample / frame / spp variant — mix in an extra constant to decorrelate samples.
public func init_random_sampler(uint2 pixelPos, uint frameIndex, uint sampleIndex) -> RandomSampler {
    return init_random_sampler(pixelPos, frameIndex + sampleIndex * 1000003u);
}

} // namespace random
