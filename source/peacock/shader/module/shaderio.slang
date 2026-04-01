module shaderio;

import math;

public enum class BindingIndex {
  eOutImage   = 0,
  eSceneDesc  = 1,
  eVolumeGrid = 2,
  eVolumeDesc = 3,
  eHdrImage = 4,
};

public struct SceneInfo {
  public float4x4 viewProjMatrix;
  public float4x4 projInvMatrix;
  public float4x4 viewInvMatrix;
  public float3   cameraPosition;
  public uint     sampleCount;
  public uint     frameIndex;
  public int      maxScatterDepth;
  public int      russianRouletteDepth;
  public int      pad;
};

public struct VolumeDesc {
  // ── Coordinate transform ──────────────────────────────────────────────────
  public float4x4 worldToIndex;

  // ── Bounding box (world space) ────────────────────────────────────────────
  public float3 bboxMin;    public float _pad0;
  public float3 bboxMax;    public float stepSize;   // ray-march step hint

  // ── Medium optical properties (scale factors applied to density) ──────────
  public float3 sigma_a;    public float majorant;       // absorption scale + global extinction bound
  public float3 sigma_s;    public float densityScale;   // scattering scale + raw→extinction factor
  public float3 Le;         public float g;              // emission scale + HG asymmetry

  public func boundingBox() -> BoundingBox { return { bboxMin, bboxMax }; }
  public func toIndex(float3 worldPos) -> float3 {
    return mul(float4(worldPos, 1.0), worldToIndex).xyz;
  }
  public func toIndexDirection(float3 worldDir) -> float3 {
    return mul(float4(worldDir, 0.0), worldToIndex).xyz;
  }
};
