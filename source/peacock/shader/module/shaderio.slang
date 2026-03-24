module shaderio;

import math;

public enum class BindingIndex {
  eOutImage   = 0,
  eSceneDesc  = 1,
  eVolumeGrid = 2,
  eVolumeDesc = 3,
};

public struct SceneInfo {
  public float4x4 viewProjMatrix;
  public float4x4 projInvMatrix;
  public float4x4 viewInvMatrix;
  public float4   cameraPositionUseSky;
  public float4   cameraForwardTanHalfFov;
  public float4   cameraRightAspect;
  public float4   cameraUpPad;
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
};
