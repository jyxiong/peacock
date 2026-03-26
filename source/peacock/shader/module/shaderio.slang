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
  public int     useSky;
  public uint     sampleCount;
  public uint     frameIndex;
  public int      maxScatterDepth;
  public int      pad;
};

public struct VolumeDesc {
  public float4x4 worldToIndex;
  public float4 bboxMinDensityScale;
  public float4 bboxMaxStepSize;
  public uint4 nanoGridInfo;

  public func toIndex(float3 worldPos) -> float3 {
    return mul(float4(worldPos, 1.0), worldToIndex).xyz;
  }

  public func toIndexDirection(float3 worldDir) -> float3 {
    return mul(float4(worldDir, 0.0), worldToIndex).xyz;
  }

  public func boundingBox() -> BoundingBox {
    return { bboxMinDensityScale.xyz, bboxMaxStepSize.xyz };
  }

  public func densityScale() -> float { return bboxMinDensityScale.w; }
  public func stepSize() -> float { return bboxMaxStepSize.w; }
  public func gridByteSize() -> uint { return nanoGridInfo.x; }
  public func gridWordCount() -> uint { return nanoGridInfo.y; }
  // Maximum extinction (majorant) for delta tracking, stored as float bits in nanoGridInfo.z
  public func sigmaMax() -> float { return asfloat(nanoGridInfo.z); }
  // Henyey-Greenstein anisotropy g in [-1, 1], stored as float bits in nanoGridInfo.w
  public func hgG() -> float { return asfloat(nanoGridInfo.w); }
};
