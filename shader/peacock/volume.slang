module volume;
__include volume.nanovdb;
__include volume.uniform;
import math;

namespace peacock {
public interface Volume {
  public func toLocal(uint3 ijk) -> float3;
  public func toIndex(float3 pos) -> uint3;

  public func dimension() -> uint3;

  public func inside(uint3 pos) -> bool;
  public func inside(float3 pos) -> bool;

  public func boundingBox() -> BoundingBox;
  public func boundingBox(float3 pos) -> BoundingBox;
  public func boundingBox(uint3 ijk) -> BoundingBox;

  public float operator()(float3 pos);
  public __subscript(uint3 ijk) -> float;
}
}
