#pragma once

#include <nvh/fileoperations.hpp>
#include <nvvk/context_vk.hpp> 
#include <nvvk/structs_vk.hpp>
#include <nvvk/resourceallocator_vk.hpp>
#include <nvvk/error_vk.hpp>
#include <nvvk/shaders_vk.hpp>
#include <nvvk/descriptorsets_vk.hpp>
#include <nvvk/raytraceKHR_vk.hpp>

struct ObjModel
{
  uint32_t     numIndices{0};
  uint32_t     numVertices{0};
  nvvk::Buffer vertexBuffer;    // Device buffer of all 'Vertex'
  nvvk::Buffer indexBuffer;     // Device buffer of the indices forming triangles
};

class Renderer
{
private:
  nvvk::Context m_context;
  nvvk::ResourceAllocatorDedicated m_allocator;
  VkCommandPool m_cmdPool;
  nvvk::RaytracingBuilderKHR m_raytracingBuilder;
  nvvk::DescriptorSetContainer m_descriptorSetContainer;

  ObjModel m_objModel;
  std::vector<nvvk::RaytracingBuilderKHR::BlasInput> m_blases;
  std::vector<VkAccelerationStructureInstanceKHR> m_instances;

  VkShaderModule m_raytraceModule;
  VkPipeline m_computePipeline;

  nvvk::Buffer m_buffer;

public:
  Renderer();

  ~Renderer();

  // buffer of result
  void createBuffer();

  void loadModel(const std::string& filename, const std::vector<std::string>& searchPaths);
  void createBottomLevelAS();
  void createTopLevelAS();

  void loadShader(const std::string& filename, const std::vector<std::string>& searchPaths);
  void createComputePipeline();

  void updateDescriptorSet();

  void rayTrace();

  void saveImage(const std::string& filename);

};