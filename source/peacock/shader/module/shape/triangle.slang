implementing shape;

// ── Triangle shape ─────────────────────────────────────────────────────────────
// Defined by three world-space vertices v0, v1, v2 (counter-clockwise order).
// The face normal points in the direction of (v1-v0) × (v2-v0).

public struct TriangleParam : IShapeParameter {
    public float3 v0;
    public float3 v1;
    public float3 v2;
};

public struct Triangle : IShape {
    public typealias TParam = TriangleParam;

    // Möller–Trumbore ray-triangle intersection.
    static func intersect(Ray ray, TParam param) -> shape::HitResult {
        float3 e1  = param.v1 - param.v0;
        float3 e2  = param.v2 - param.v0;
        float3 h   = cross(ray.d, e2);
        float  det = dot(e1, h);
        if (abs(det) < M_MACHINE_EPSILON)
            return shape::HitResult(false, 0.f, float3(0.f));
        float  invDet = 1.f / det;
        float3 tvec   = ray.o - param.v0;
        float  bu     = dot(tvec, h) * invDet;
        if (bu < 0.f || bu > 1.f)
            return shape::HitResult(false, 0.f, float3(0.f));
        float3 qvec = cross(tvec, e1);
        float  bv   = dot(ray.d, qvec) * invDet;
        if (bv < 0.f || bu + bv > 1.f)
            return shape::HitResult(false, 0.f, float3(0.f));
        float tval = dot(e2, qvec) * invDet;
        if (tval <= 0.f)
            return shape::HitResult(false, 0.f, float3(0.f));
        float3 n = normalize(cross(e1, e2));
        return shape::HitResult(true, tval, n);
    }

    // Uniform area sample via barycentric coordinates.
    // PDF is in solid-angle measure w.r.t. refPoint.
    static func sample(float3 refPoint, float2 u, TParam param) -> shape::Sample {
        // Uniform barycentric: sqrt-warp avoids clustering at v0
        float  su0     = sqrt(u.x);
        float  b0      = 1.f - su0;
        float  b1      = u.y * su0;
        float3 worldPos = b0 * param.v0 + b1 * param.v1 + (1.f - b0 - b1) * param.v2;
        float3 e1       = param.v1 - param.v0;
        float3 e2       = param.v2 - param.v0;
        float3 n        = normalize(cross(e1, e2));
        float3 dir      = worldPos - refPoint;
        float  dist2    = dot(dir, dir);
        float  cosTheta = abs(dot(n, -normalize(dir)));
        shape::Sample s;
        s.position = worldPos;
        s.normal   = n;
        s.pdf      = (cosTheta > 0.f) ? dist2 / (_area(param) * cosTheta) : 0.f;
        return s;
    }

    // PDF (solid-angle measure) for an already-found surface point.
    static func pdf(float3 refPoint, float3 surfacePoint, float3 surfaceNormal, TParam param) -> float {
        float3 dir      = surfacePoint - refPoint;
        float  dist2    = dot(dir, dir);
        float  cosTheta = abs(dot(surfaceNormal, -normalize(dir)));
        return (cosTheta > 0.f) ? dist2 / (_area(param) * cosTheta) : 0.f;
    }

    // World-space surface area = 0.5 * |(v1-v0) × (v2-v0)|.
    static func _area(TParam param) -> float {
        float3 e1 = param.v1 - param.v0;
        float3 e2 = param.v2 - param.v0;
        return 0.5f * length(cross(e1, e2));
    }
};
