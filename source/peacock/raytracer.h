#pragma once

#include <nvapp/application.hpp>
#include <nvslang/slang.hpp>
#include <nvvk/acceleration_structures.hpp>
#include <nvvk/descriptors.hpp>
#include <nvvk/gbuffers.hpp>
#include <nvvk/pipeline.hpp>
#include <nvvk/resource_allocator.hpp>
#include <nvvk/sampler_pool.hpp>
#include <nvvk/sbt_generator.hpp>
#include <nvvk/staging.hpp>

namespace peacock {

class Raytracer : public nvapp::IAppElement {
public:
  Raytracer() = default;

  ~Raytracer() = default;

  void onAttach(nvapp::Application *app) override;
  void onDetach() override;
  void onResize(VkCommandBuffer cmd, const VkExtent2D &size) override;
  void onUIRender() override;
  void onUIMenu() override;
  void onRender(VkCommandBuffer cmd) override;

private:
  VkShaderModuleCreateInfo compileSlangShader(const std::filesystem::path& filename, const std::span<const uint32_t>& spirv);
  void createRaytraceDescriptorLayout();
  void createRayTracingPipeline();
  void createShaderBindingTable(const VkRayTracingPipelineCreateInfoKHR& rtPipelineInfo);
  void raytrace(const VkCommandBuffer &cmd);

private:
  // Application and core components
  nvapp::Application *m_app{};
  nvvk::ResourceAllocator m_allocator{};
  nvvk::StagingUploader m_stagingUploader{};
  nvvk::SamplerPool m_samplerPool{};
  nvvk::GBuffer m_gBuffers{};
  nvslang::SlangCompiler m_slangCompiler{};

  // Ray Tracing Pipeline Components
  nvvk::DescriptorPack m_rtDescPack;
  VkPipeline m_rtPipeline{};
  VkPipelineLayout m_rtPipelineLayout{};

  // Acceleration Structure Components
  nvvk::AccelerationStructureHelper m_asBuilder{};
  nvvk::SBTGenerator m_sbtGenerator;
  nvvk::Buffer m_sbtBuffer;

  // Ray Tracing Properties
  VkPhysicalDeviceRayTracingPipelinePropertiesKHR m_rtProperties{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR};
};

} // namespace peacock