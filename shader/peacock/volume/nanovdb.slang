implementing volume;
#include "PNanoVDB.slang"

namespace peacock {
public struct NanovdbVolume: Volume {
  BoundingBox m_bbox;

  public func toLocal(int3 ijk) -> float3 { return float3(0); }
  public func toIndex(float3 pos) -> int3 { return int3(0); }

  public func dimension() -> uint3 { return uint3(0); }

  public func inside(int3 pos) -> bool { return false; }
  public func inside(float3 pos) -> bool { return false; }

  public func boundingBox() -> BoundingBox { return m_bbox; }
  public func boundingBox(float3 pos) -> BoundingBox { return m_bbox; }
  public func boundingBox(int3 ijk) -> BoundingBox { return m_bbox; }

  public float operator()(float3 pos) { return 0.0; /* TODO: sample from the actual volume data */ }
  public __subscript(int3 ijk) -> float {get {
    return 0.0; // TODO: sample from the actual volume data
  }}
}
}
