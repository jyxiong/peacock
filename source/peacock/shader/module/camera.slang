module camera;

import math;

public struct Film {
  public uint2 resolution;   // full render resolution in pixels

  // Returns the jittered NDC position for the given pixel.
  // u: uniform random sample in [0, 1)^2 (from RandomSampler.next_float2())
  public func sample(uint2 pixel, float2 u) -> float2 {
      float2 jittered = float2(pixel) + u;
      return jittered / float2(resolution) * 2.0f - 1.0f;
  }
};

// ── Camera ─────────────────────────────────────────────────────────────
// A pinhole (perspective) camera defined by inverse projection and view matrices.
// Given a clip-space sample from Film::sample(), it produces a world-space ray.

public struct Camera {
    public float4x4 projInvMatrix;  // inverse projection matrix
    public float4x4 viewInvMatrix;  // inverse view (camera-to-world) matrix

    public __init(float4x4 projInv, float4x4 viewInv) {
        projInvMatrix = projInv;
        viewInvMatrix = viewInv;
    }

    // Convert a clip-space coordinate to a world-space ray.
    // clipPos: output of Film::sample() — NDC in [-1, 1]^2.
    public func sample_ray(float2 clipPos) -> Ray {
        float4 viewCoords = mul(float4(clipPos, 1.0f, 1.0f), projInvMatrix);
        float3 worldOri   = mul(float4(0.0f, 0.0f, 0.0f, 1.0f), viewInvMatrix).xyz;
        float3 worldDir   = mul(float4(normalize(viewCoords.xyz), 0.0f), viewInvMatrix).xyz;
        Ray ray = { worldOri, worldDir };
        return ray;
    }
};