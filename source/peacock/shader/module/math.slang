module math;

__include math.ray;
__include math.bbox;

public func rayBoxIntersect(Ray r, BoundingBox bbox) -> Optional<float2> {
  float3 invDir = 1.0 / r.d;
  float3 t0 = (bbox.min - r.o) * invDir;
  float3 t1 = (bbox.max - r.o) * invDir;

  float3 hitMin = min(t0, t1);
  float3 hitMax = max(t0, t1);

  float tMin = max(max(hitMin.x, hitMin.y), hitMin.z);
  float tMax = min(min(hitMax.x, hitMax.y), hitMax.z); 

  if (tMin < tMax && tMax > 0) return float2(tMin, tMax);
  else return none;
}