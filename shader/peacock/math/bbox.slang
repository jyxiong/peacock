implementing math;

namespace peacock {
public struct BoundingBox {
  public float3 min;
  public float3 max;
}

public func inside(float3 p, BoundingBox bbox) -> bool {
  return all(p >= bbox.min) && all(p < bbox.max);
}

public func hit(Ray r, BoundingBox bbox) -> Optional<float3> {
  return Optional<float3>(); // TODO
}
}
