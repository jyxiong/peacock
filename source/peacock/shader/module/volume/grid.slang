implementing volume;

public struct GridVolume: Volume {
  BoundingBox m_bbox;
  uint3 m_dimension;
  float3 m_spacing;

  public func toLocal(uint3 ijk) -> float3 { return m_bbox.min + ijk * m_spacing; }
  public func toIndex(float3 pos) -> uint3 { return uint3(floor((pos - m_bbox.min) / m_spacing)); }

  public func dimension() -> uint3 { return m_dimension; }

  public func inside(float3 pos) -> bool { return inside(toIndex(pos)); }

  public func boundingBox() -> BoundingBox { return m_bbox; }

  public func sample(float3 pos) -> float { return load(toIndex(pos)); }
  public func load(uint3 ijk) -> float {
    return 0.0; // TODO: sample from the actual volume data
  }
}
