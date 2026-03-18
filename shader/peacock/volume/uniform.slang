implementing volume;

namespace peacock {
public struct GridVolume: Volume {
  BoundingBox m_bbox;
  uint3 m_dimension;
  float3 m_spacing;

  public func toLocal(uint3 ijk) -> float3 { return m_bbox.min + ijk * m_spacing; }
  public func toIndex(float3 pos) -> uint3 { return uint3(floor((pos - m_bbox.min) / m_spacing)); }

  public func dimension() -> uint3 { return m_dimension; }

  public func inside(uint3 pos) -> bool { return all(pos < m_dimension); }
  public func inside(float3 pos) -> bool { return inside(toIndex(pos)); }

  public func boundingBox() -> BoundingBox { return m_bbox; }
  public func boundingBox(float3 pos) -> BoundingBox { return boundingBox(toIndex(pos)); }
  public func boundingBox(uint3 ijk) -> BoundingBox {
    if (all(ijk == clamp(ijk, uint3(0), m_dimension - 1))) return {
        m_bbox.min + float3(ijk + 0) * m_spacing,
        m_bbox.min + float3(ijk + 1) * m_spacing,
    }; else return m_bbox;
  }

  public float operator()(float3 pos) { return this[toIndex(pos)]; }
  public __subscript(uint3 ijk) -> float {get {
    return 0.0; // TODO: sample from the actual volume data
  }}
}
}
