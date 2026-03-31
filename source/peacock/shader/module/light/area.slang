implementing light;

namespace light {

// ── Generic area light backed by any IShape ───────────────────────────────────
// TShape must conform to IShape; its TParam is carried as a member.
// Usage examples:
//   AreaLight<Rectangle, RectangleParam>
//   AreaLight<Disk,      DiskParam>
//   AreaLight<Triangle,  TriangleParam>
public struct AreaLight<TShape : IShape> : Light {
    public float3          radiance;
    public TShape.TParam   shapeParam;

    func eval(float3 dir) -> float3 {
        return radiance;
    }

    func sample(float3 p, float2 u) -> Interaction {
        shape::Sample s = TShape::sample(p, u, shapeParam);
        Interaction it;
        it.L   = radiance;
        it.wi  = normalize(s.position - p);
        it.p   = p;
        it.t   = length(s.position - p);
        it.pdf = s.pdf;
        return it;
    }

    func pdf(float3 p, float3 wi) -> float {
        Ray ray = { p, wi };
        shape::HitResult hit = TShape::intersect(ray, shapeParam);
        if (!hit.hit) return 0.f;
        float3 surfacePoint = p + hit.tHit * wi;
        return TShape::pdf(p, surfacePoint, hit.normal, shapeParam);
    }
};

// ── Convenience type aliases ──────────────────────────────────────────────────
public typealias RectAreaLight = AreaLight<Rectangle>;
public typealias DiskAreaLight = AreaLight<Disk>;
public typealias TriAreaLight  = AreaLight<Triangle>;

} // namespace light