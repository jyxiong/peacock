module math;

__include math.bbox;
__include math.define;
__include math.ray;

// ── Scalar helpers ──────────────────────────────────────────────────────────
public func sqr(float v) -> float { return v * v; }
public func safe_sqrt(float v) -> float { return sqrt(max(v, 0.0f)); }
public func safe_acos(float x) -> float { return acos(clamp(x, -1.0f, 1.0f)); }
public func safe_asin(float x) -> float { return asin(clamp(x, -1.0f, 1.0f)); }
public func luminance(float3 rgb) -> float { return dot(rgb, float3(0.212671f, 0.715160f, 0.072169f)); }
public func average(float3 v) -> float { return (v.x + v.y + v.z) / 3.0f; }

// ── Orthonormal frame built from a normal direction ─────────────────────────
// Follows Duff et al. "Building an Orthonormal Basis, Revisited" (JCGT 2017).
public struct Frame {
    public float3 n;   // forward / normal
    public float3 s;   // tangent
    public float3 t;   // bitangent

    public static func from_normal(float3 n_) -> Frame {
        Frame f;
        f.n = n_;
        if (n_.z < -0.99999f) {
            f.s = float3( 0.0f, -1.0f, 0.0f);
            f.t = float3(-1.0f,  0.0f, 0.0f);
        } else {
            const float a = 1.0f / (1.0f + n_.z);
            const float b = -n_.x * n_.y * a;
            f.s = float3(1.0f - n_.x * n_.x * a,  b,             -n_.x);
            f.t = float3(b,                         1.0f - n_.y * n_.y * a, -n_.y);
        }
        return f;
    }

    // Local (tangent-space) → world
    public func to_world(float3 v) -> float3 {
        return v.x * s + v.y * t + v.z * n;
    }
};

// ── Ray / AABB intersection ──────────────────────────────────────────────────
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