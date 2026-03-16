module shaderio;

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
  public float3   cameraPosition;
  public int      useSky;
};

public struct VolumeDesc {
  public float4x4 worldToIndex;  // affine world→index
  public float3   bboxMin;
  public float    densityScale;
  public float3   bboxMax;
  public float    stepSize;
};