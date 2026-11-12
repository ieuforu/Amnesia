import MetalKit
import SwiftUI

/// A transient overlay for the folder that received a drop. The saved result
/// is displayed separately, so skipping the effect never hides feedback.
struct LibraryDropParticles: View {
    static let duration: TimeInterval = 0.36

    let claudeCount: Int
    let codexCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pipeline: DropParticlePipeline?
    @State private var start = CACurrentMediaTime()

    static func prewarm() {
        _ = DropParticlePipeline.prepared
    }

    var body: some View {
        Group {
            if !reduceMotion, claudeCount > 0 || codexCount > 0 {
                if let pipeline {
                    DropParticleSurface(
                        pipeline: pipeline, start: start,
                        claudeParticles: particleCount(claudeCount),
                        codexParticles: particleCount(codexCount)
                    )
                } else {
                    Color.clear.task {
                        let prepared = await DropParticlePipeline.prepared.value
                        guard !Task.isCancelled else { return }
                        pipeline = prepared
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func particleCount(_ count: Int) -> Int {
        count > 0 ? 5 + 2 * min(count, 5) : 0
    }
}

private struct DropParticleSurface: NSViewRepresentable {
    let pipeline: DropParticlePipeline
    let start: CFTimeInterval
    let claudeParticles: Int
    let codexParticles: Int

    func makeCoordinator() -> Renderer {
        Renderer(pipeline: pipeline, start: start, claudeParticles: claudeParticles, codexParticles: codexParticles)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = ParticleView(frame: .zero, device: pipeline.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}

    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        private let pipeline: DropParticlePipeline
        private let start: CFTimeInterval
        private let claudeParticles: Int
        private let codexParticles: Int

        init(pipeline: DropParticlePipeline, start: CFTimeInterval, claudeParticles: Int, codexParticles: Int) {
            self.pipeline = pipeline
            self.start = start
            self.claudeParticles = claudeParticles
            self.codexParticles = codexParticles
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let progress = min((CACurrentMediaTime() - start) / LibraryDropParticles.duration, 1)
            guard let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = pipeline.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
                if progress >= 1 { view.isPaused = true }
                return
            }

            if progress < 1 {
                // Shaders work in points so the effect has the same size on
                // Retina and standard displays.
                let size = view.bounds.size
                var input = SIMD4(
                    Float(progress), Float(max(size.width, 1)),
                    Float(max(size.height, 1)), Float(claudeParticles)
                )
                encoder.setRenderPipelineState(pipeline.state)
                encoder.setVertexBytes(&input, length: MemoryLayout.size(ofValue: input), index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: (claudeParticles + codexParticles) * 6)
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
            if progress >= 1 { view.isPaused = true }
        }
    }
}

private final class ParticleView: MTKView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct DropParticlePipeline: Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let state: any MTLRenderPipelineState

    // One background compilation per process, independent of the drop event.
    static let prepared = Task.detached(priority: .utility) { Self() }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let vertex = library.makeFunction(name: "particleVertex"),
              let fragment = library.makeFunction(name: "particleFragment") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        self.device = device
        self.queue = queue
        self.state = state
    }

    private static let shader = """
        #include <metal_stdlib>
        using namespace metal;

        struct Dot {
            float4 position [[position]];
            float2 point;
            float4 color;
        };

        vertex Dot particleVertex(uint vertexID [[vertex_id]], constant float4 &input [[buffer(0)]]) {
            const float2 corners[6] = {
                {-1, -1}, {1, -1}, {-1, 1}, {-1, 1}, {1, -1}, {1, 1}
            };
            uint index = vertexID / 6;
            float lane = fract(float(index) * 0.618034f + 0.13f);
            float variation = fract(float(index) * 0.381966f + 0.51f);
            float time = clamp((input.x - 0.16f * variation) / (1.0f - 0.16f * variation), 0.0f, 1.0f);
            float approach = 1.0f - smoothstep(0.0f, 1.0f, time);
            float2 origin = float2((0.19f + 0.67f * lane) * input.y * 0.5f,
                                   (variation - 0.5f) * input.z * 0.78f);
            float2 center = origin * approach;
            center.y += sin(time * 3.14159f) * (lane - 0.5f) * 13.0f;
            float radius = (1.0f + 1.6f * lane) * (0.65f + 0.35f * approach);
            float2 point = corners[vertexID % 6];
            float2 position = (center + radius * point) * 2.0f / input.yz;
            float alpha = smoothstep(0.0f, 0.10f, input.x) * (1.0f - smoothstep(0.57f, 1.0f, time));
            float3 hue = index < uint(input.w) ? float3(0.07f, 0.66f, 0.53f) : float3(0.28f, 0.47f, 0.92f);
            return { float4(position, 0, 1), point, float4(hue, alpha * 0.78f) };
        }

        fragment half4 particleFragment(Dot in [[stage_in]]) {
            float coverage = 1.0f - smoothstep(0.64f, 1.0f, length(in.point));
            return half4(half3(in.color.rgb), half(in.color.a * coverage));
        }
        """
}
