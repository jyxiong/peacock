implementing medium;

namespace peacock {
public struct HeterogeneousMedium : Medium {
  Volume m_majorant;
  Volume m_density;
  float m_densityScale;

  public func sample() {}
};
}