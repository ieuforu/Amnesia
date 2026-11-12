import MetalKit
import SwiftUI

struct LibraryOpeningDot: Equatable {
    let position: CGPoint
    let isClaude: Bool
}

/// The animated marks on the map. Controls and hit targets live in the parent view.
struct LibraryOpeningParticles: View {
    let dots: [LibraryOpeningDot]
    let animationID: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pipeline: LibraryOpeningParticlePipeline?
    @State private var prepared = false

    static func prewarm() {
        _ = LibraryOpeningParticlePipeline.prepared
    }

    var body: some View {
        Group {
            if let pipeline {
                LibraryOpeningParticleSurface(
                    pipeline: pipeline, dots: dots, animationID: animationID,
                    reduceMotion: reduceMotion, dark: colorScheme == .dark
                )
            } else if prepared || reduceMotion {
                Canvas { context, _ in
                    for dot in dots {
                        let rect = CGRect(x: dot.position.x - 2, y: dot.position.y - 2, width: 4, height: 4)
                        let hue = dot.isClaude ? LibraryAppearance.claude : LibraryAppearance.accent
                        context.fill(Path(ellipseIn: rect), with: .color(hue.opacity(0.88)))
                    }
                }
            } else {
                Color.clear
            }
        }
        .task {
            let preparedPipeline = await LibraryOpeningParticlePipeline.prepared.value
            guard !Task.isCancelled else { return }
            pipeline = preparedPipeline
            prepared = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LibraryOpeningParticleSurface: NSViewRepresentable {
    let pipeline: LibraryOpeningParticlePipeline
    let dots: [LibraryOpeningDot]
    let animationID: Int?
    let reduceMotion: Bool
    let dark: Bool

    func makeCoordinator() -> Renderer { Renderer(pipeline: pipeline) }

    func makeNSView(context: Context) -> MTKView {
        let view = OpeningParticleView(frame: .zero, device: pipeline.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(view, dots: dots, animationID: animationID, reduceMotion: reduceMotion, dark: dark)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        private let pipeline: LibraryOpeningParticlePipeline
        private let duration: CFTimeInterval = 0.55
        private var dots: [LibraryOpeningDot] = []
        private var vertices: (any MTLBuffer)?
        private var lastAnimationID: Int?
        private var start: CFTimeInterval?
        private var dark = false

        init(pipeline: LibraryOpeningParticlePipeline) { self.pipeline = pipeline }

        func update(_ view: MTKView, dots: [LibraryOpeningDot], animationID: Int?, reduceMotion: Bool, dark: Bool) {
            let redraw = self.dots != dots || self.dark != dark
            if self.dots != dots {
                self.dots = dots
                let points = dots.map { SIMD4(Float($0.position.x), Float($0.position.y), $0.isClaude ? 1 : 0, 0) }
                vertices = points.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress, !bytes.isEmpty else { return nil }
                    return pipeline.device.makeBuffer(bytes: base, length: bytes.count)
                }
            }
            self.dark = dark
            let replay = animationID != nil && !dots.isEmpty && !reduceMotion && lastAnimationID != animationID
            if !dots.isEmpty { lastAnimationID = animationID }

            if replay {
                start = CACurrentMediaTime()
                view.enableSetNeedsDisplay = false
                view.isPaused = false
            } else if reduceMotion || dots.isEmpty {
                let wasAnimating = start != nil
                settle(view)
                if redraw || wasAnimating { view.setNeedsDisplay(view.bounds) }
            } else if redraw && start == nil {
                view.setNeedsDisplay(view.bounds)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            if start == nil { view.setNeedsDisplay(view.bounds) }
        }

        func draw(in view: MTKView) {
            let progress = start.map { min(max((CACurrentMediaTime() - $0) / duration, 0), 1) } ?? 1
            defer { if progress >= 1, start != nil { settle(view) } }
            guard let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = pipeline.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

            if let vertices, !dots.isEmpty {
                let size = view.bounds.size
                var input = SIMD4(Float(progress), Float(max(size.width, 1)), Float(max(size.height, 1)), dark ? 1 : 0)
                encoder.setRenderPipelineState(pipeline.state)
                encoder.setVertexBuffer(vertices, offset: 0, index: 0)
                encoder.setVertexBytes(&input, length: MemoryLayout.size(ofValue: input), index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: dots.count)
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }

        private func settle(_ view: MTKView) {
            start = nil
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        }
    }
}

private final class OpeningParticleView: MTKView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct LibraryOpeningParticlePipeline: Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let state: any MTLRenderPipelineState

    static let prepared = Task.detached(priority: .utility) { Self() }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let vertex = library.makeFunction(name: "mapParticleVertex"),
              let fragment = library.makeFunction(name: "mapParticleFragment") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        guard let color = descriptor.colorAttachments[0] else { return nil }
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

        vertex Dot mapParticleVertex(uint vertexID [[vertex_id]], uint index [[instance_id]],
                                     const device float4 *dots [[buffer(0)]],
                                     constant float4 &input [[buffer(1)]]) {
            const float2 corners[6] = {{-1,-1}, {1,-1}, {-1,1}, {-1,1}, {1,-1}, {1,1}};
            float4 dot = dots[index];
            float2 bounds = input.yz;
            float lane = fract(float(index) * 0.618034f + 0.13f);
            float jitter = fract(float(index) * 0.381966f + 0.51f);
            float time = clamp((input.x - 0.12f * jitter) / (1.0f - 0.12f * jitter), 0.0f, 1.0f);
            float remaining = pow(1.0f - time, 3.0f);
            float angle = (lane + time * 0.22f) * 6.2831853f;
            float2 origin = bounds * 0.5f + float2(cos(angle), sin(angle)) * (0.18f + 0.22f * jitter) * min(bounds.x, bounds.y);
            float2 center = mix(dot.xy, origin, remaining);
            float radius = 2.5f + 2.6f * sin(time * 3.14159265f);
            float2 point = corners[vertexID];
            float2 position = ((center + point * radius) * 2.0f) / bounds - 1.0f;
            position.y = -position.y;
            float3 claude = input.w > 0.5f ? float3(0.50f, 0.88f, 0.75f) : float3(0.02f, 0.49f, 0.38f);
            float3 codex = input.w > 0.5f ? float3(0.51f, 0.67f, 1.0f) : float3(0.17f, 0.35f, 0.77f);
            float alpha = 0.18f + 0.70f * smoothstep(0.0f, 0.42f, time);
            return { float4(position, 0, 1), point, float4(dot.z > 0.5f ? claude : codex, alpha) };
        }

        fragment half4 mapParticleFragment(Dot in [[stage_in]]) {
            float coverage = 1.0f - smoothstep(0.58f, 1.0f, length(in.point));
            return half4(half3(in.color.rgb), half(in.color.a * coverage));
        }
        """
}
