implementing volume;

#include "PNanoVDB.slang"

public struct NanovdbVolume: Volume {
  BoundingBox m_bbox;

  public func toLocal(uint3 ijk) -> float3 { return float3(0); }
  public func toIndex(float3 pos) -> uint3 { return uint3(0); }

  public func dimension() -> uint3 { return uint3(0); }
  
  public func inside(uint3 pos) -> bool { return false; }
  public func inside(float3 pos) -> bool { return false; }

  public func boundingBox() -> BoundingBox { return m_bbox; }
  public func boundingBox(float3 pos) -> BoundingBox { return m_bbox; }
  public func boundingBox(uint3 ijk) -> BoundingBox { return m_bbox; }

  public float operator()(float3 pos) { return 0.0; /* TODO: sample from the actual volume data */ }
  public __subscript(uint3 ijk) -> float {get {
    return 0.0; // TODO: sample from the actual volume data
  }}
}
