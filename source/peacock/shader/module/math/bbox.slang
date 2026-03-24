implementing math;

public struct BoundingBox {
  public float3 min;
  public float3 max;

  public func inside(float3 p) -> bool {
    return all(p >= min) && all(p < max);
  }
}
