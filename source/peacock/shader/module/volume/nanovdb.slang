implementing volume;

#include "PNanoVDB.slang"

public struct NanovdbVolume: Volume {
  StructuredBuffer<uint> m_gridBuffer;

  public __init(StructuredBuffer<uint> gridBuffer) {
    m_gridBuffer = gridBuffer;
  }

  public func toLocal(uint3 ijk) -> float3 {
    pnanovdb_grid_handle_t grid = {0};
    return pnanovdb_grid_index_to_worldf(m_gridBuffer, grid, ijk);
  }

  public func toIndex(float3 pos) -> uint3 {
    pnanovdb_grid_handle_t grid = {0};
    return uint3(pnanovdb_grid_world_to_indexf(m_gridBuffer, grid, pos));
   }

  public func dimension() -> uint3 {
    int3 bboxMin = pnanovdb_root_get_bbox_min(m_gridBuffer, root());
    int3 bboxMax = pnanovdb_root_get_bbox_max(m_gridBuffer, root());
    return abs(bboxMax - bboxMin) + 1;
  }
  
  public func inside(float3 pos) -> bool { 
    int3 bboxMin = pnanovdb_root_get_bbox_min(m_gridBuffer, root());
    int3 bboxMax = pnanovdb_root_get_bbox_max(m_gridBuffer, root());
    return all(pos >= float3(bboxMin) && pos <= float3(bboxMax));
   }

  public func boundingBox() -> BoundingBox {
    int3 bboxMin = pnanovdb_root_get_bbox_min(m_gridBuffer, root());
    int3 bboxMax = pnanovdb_root_get_bbox_max(m_gridBuffer, root());
    float3 worldMin = toLocal(uint3(bboxMin));
    float3 worldMax = toLocal(uint3(bboxMax));
    return { worldMin, worldMax };
  }

  public float operator()(float3 pos) {
    pnanovdb_readaccessor_t acc = accessor();

    // Convert world position to floating-point index space
    float3 idx = pnanovdb_grid_world_to_indexf(m_gridBuffer, grid(), pos);
    int3 i0 = int3(floor(idx));
    float3 t = idx - float3(i0);

    // Sample the 8 surrounding voxel corners
    pnanovdb_address_t a000 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(0, 0, 0));
    pnanovdb_address_t a100 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(1, 0, 0));
    pnanovdb_address_t a010 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(0, 1, 0));
    pnanovdb_address_t a110 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(1, 1, 0));
    pnanovdb_address_t a001 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(0, 0, 1));
    pnanovdb_address_t a101 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(1, 0, 1));
    pnanovdb_address_t a011 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(0, 1, 1));
    pnanovdb_address_t a111 = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, i0 + int3(1, 1, 1));

    float c000 = pnanovdb_read_float(m_gridBuffer, a000);
    float c100 = pnanovdb_read_float(m_gridBuffer, a100);
    float c010 = pnanovdb_read_float(m_gridBuffer, a010);
    float c110 = pnanovdb_read_float(m_gridBuffer, a110);
    float c001 = pnanovdb_read_float(m_gridBuffer, a001);
    float c101 = pnanovdb_read_float(m_gridBuffer, a101);
    float c011 = pnanovdb_read_float(m_gridBuffer, a011);
    float c111 = pnanovdb_read_float(m_gridBuffer, a111);

    // Trilinear interpolation along x, then y, then z
    float c00 = lerp(c000, c100, t.x);
    float c10 = lerp(c010, c110, t.x);
    float c01 = lerp(c001, c101, t.x);
    float c11 = lerp(c011, c111, t.x);

    float c0 = lerp(c00, c10, t.y);
    float c1 = lerp(c01, c11, t.y);

    return lerp(c0, c1, t.z);
  }

  public __subscript(uint3 ijk) -> float {
  get {
    pnanovdb_readaccessor_t acc;
    pnanovdb_address_t address = pnanovdb_readaccessor_get_value_address(type(), m_gridBuffer, acc, int3(ijk));
    return pnanovdb_read_float(m_gridBuffer, address);
  }}

  private func grid() -> pnanovdb_grid_handle_t {
    pnanovdb_grid_handle_t grid = {0};
    return grid;
  }

  private func type() -> uint {
    return pnanovdb_grid_get_grid_type(m_gridBuffer, grid());
  }

  private func tree() -> pnanovdb_tree_handle_t {
    return pnanovdb_grid_get_tree(m_gridBuffer, grid());
  }

  private func root() -> pnanovdb_root_handle_t {
    return pnanovdb_tree_get_root(m_gridBuffer, tree());
  }

  private func accessor() -> pnanovdb_readaccessor_t {
    pnanovdb_readaccessor_t acc;
    pnanovdb_readaccessor_init(acc, root());
    return acc;
  }

}
