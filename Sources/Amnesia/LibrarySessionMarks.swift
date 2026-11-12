import MetalKit
import SwiftUI

struct LibrarySessionMark: Equatable {
    let frame: CGRect
    let isClaude: Bool
    let isEmphasized: Bool
}

/// Draws the library's session stamps. Interaction and accessibility live in the controls above it.
struct LibrarySessionMarks: View {
    let marks: [LibrarySessionMark]

    @Environment(\.colorScheme) private var colorScheme
    @State private var pipeline: LibraryStampPipeline?

    static func prewarm() { _ = LibraryStampPipeline.prepared }

    var body: some View {
        let dark = colorScheme == .dark
        Group {
            if let pipeline {
                LibraryStampSurface(pipeline: pipeline, marks: marks, dark: dark)
            } else {
                Canvas { context, _ in
                    for mark in marks {
                        guard let stamp = LibraryStamp(mark, dark: dark) else { continue }
                        let color = Color(.sRGB, red: Double(stamp.tint.x), green: Double(stamp.tint.y), blue: Double(stamp.tint.z))
                        context.fill(Path(roundedRect: stamp.frame, cornerRadius: stamp.radius), with: .color(color.opacity(Double(stamp.tint.w))))
                        for offset in stamp.separation == 0 ? [0] : [-stamp.separation, stamp.separation] {
                            let slit = stamp.perforation.offsetBy(dx: 0, dy: offset)
                            context.fill(Path(roundedRect: slit, cornerRadius: slit.height / 2), with: .color(color.opacity(0.93)))
                        }
                    }
                }
            }
        }
        .task {
            let prepared = await LibraryStampPipeline.prepared.value
            guard !Task.isCancelled else { return }
            pipeline = prepared
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LibraryStamp {
    let frame: CGRect
    let perforation: CGRect
    let separation: CGFloat
    let radius: CGFloat
    let tint: SIMD4<Float>

    init?(_ mark: LibrarySessionMark, dark: Bool) {
        let frame = mark.frame
        guard !frame.isEmpty, !frame.isInfinite, frame.midX.isFinite, frame.midY.isFinite else { return nil }
        let emph = mark.isEmphasized
        let width = min(emph ? 12 : 8, frame.width * (emph ? 0.69 : 0.54))
        let height = min(emph ? 2.3 : 1.5, frame.height * (emph ? 0.17 : 0.13))
        self.frame = frame
        perforation = CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
        separation = mark.isClaude ? min(emph ? 3.0 : 2.3, frame.height * 0.18) : 0
        radius = min(4, frame.width / 2, frame.height / 2)
        let opacity: Float = emph ? (dark ? 0.42 : 0.29) : (dark ? 0.22 : 0.15)
        if mark.isClaude {
            tint = dark ? SIMD4(0.29, 0.84, 0.67, opacity) : SIMD4(0.04, 0.43, 0.35, opacity)
        } else {
            tint = dark ? SIMD4(0.42, 0.60, 1, opacity) : SIMD4(0.12, 0.32, 0.91, opacity)
        }
    }

    var vertex: LibraryStampVertex {
        LibraryStampVertex(
            frame: SIMD4(Float(frame.midX), Float(frame.midY), Float(frame.width), Float(frame.height)),
            shape: SIMD4(Float(perforation.width), Float(perforation.height), Float(separation), Float(radius)),
            tint: tint
        )
    }
}

private struct LibraryStampVertex {
    let frame: SIMD4<Float>
    let shape: SIMD4<Float>
    let tint: SIMD4<Float>
}

private struct LibraryStampSurface: NSViewRepresentable {
    let pipeline: LibraryStampPipeline
    let marks: [LibrarySessionMark]
    let dark: Bool

    func makeCoordinator() -> Renderer { Renderer(pipeline: pipeline) }

    func makeNSView(context: Context) -> MTKView {
        let view = LibraryStampView(frame: .zero, device: pipeline.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.setAccessibilityElement(false)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(view, marks: marks, dark: dark)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Renderer) {
        view.delegate = nil
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        private let pipeline: LibraryStampPipeline
        private var marks: [LibrarySessionMark] = []
        private var dark = false
        private var vertices: (any MTLBuffer)?
        private var count = 0

        init(pipeline: LibraryStampPipeline) { self.pipeline = pipeline }

        func update(_ view: MTKView, marks: [LibrarySessionMark], dark: Bool) {
            guard marks != self.marks || dark != self.dark else { return }
            self.marks = marks
            self.dark = dark
            let payload = marks.compactMap { LibraryStamp($0, dark: dark)?.vertex }
            count = payload.count
            vertices = payload.withUnsafeBytes { bytes in
                guard !bytes.isEmpty, let base = bytes.baseAddress else { return nil }
                return pipeline.device.makeBuffer(bytes: base, length: bytes.count)
            }
            view.setNeedsDisplay(view.bounds)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay(view.bounds)
        }

        func draw(in view: MTKView) {
            let size = view.bounds.size
            guard size.width > 0, size.height > 0,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = pipeline.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            if let vertices, count > 0 {
                var bounds = SIMD2(Float(size.width), Float(size.height))
                encoder.setRenderPipelineState(pipeline.state)
                encoder.setVertexBuffer(vertices, offset: 0, index: 0)
                encoder.setVertexBytes(&bounds, length: MemoryLayout.size(ofValue: bounds), index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

private final class LibraryStampView: MTKView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct LibraryStampPipeline: Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let state: any MTLRenderPipelineState

    static let prepared = Task.detached(priority: .utility) { Self() }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let vertex = library.makeFunction(name: "libraryStampVertex"),
              let fragment = library.makeFunction(name: "libraryStampFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        guard let color = descriptor.colorAttachments[0] else { return nil }
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
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

        struct Stamp { float4 frame; float4 shape; float4 tint; };
        struct StampFragment {
            float4 position [[position]];
            float2 point;
            float2 size;
            float4 shape;
            float4 tint;
        };

        vertex StampFragment libraryStampVertex(uint vertexID [[vertex_id]], uint index [[instance_id]],
                                                 const device Stamp *stamps [[buffer(0)]],
                                                 constant float2 &bounds [[buffer(1)]]) {
            const float2 corners[6] = {{-1,-1}, {1,-1}, {-1,1}, {-1,1}, {1,-1}, {1,1}};
            Stamp stamp = stamps[index];
            float2 point = corners[vertexID] * (stamp.frame.zw * 0.5f + 1.0f);
            float2 clip = (stamp.frame.xy + point) * 2.0f / bounds - 1.0f;
            return { float4(clip.x, -clip.y, 0, 1), point, stamp.frame.zw, stamp.shape, stamp.tint };
        }

        float roundCoverage(float2 point, float2 size, float radius) {
            float2 p = abs(point) - size * 0.5f + radius;
            float distance = length(max(p, 0.0f)) + min(max(p.x, p.y), 0.0f) - radius;
            float aa = max(fwidth(distance) * 0.5f, 0.18f);
            return 1.0f - smoothstep(-aa, aa, distance);
        }

        fragment half4 libraryStampFragment(StampFragment input [[stage_in]]) {
            float base = roundCoverage(input.point, input.size, input.shape.w) * input.tint.a;
            float2 slitPoint = float2(input.point.x, abs(input.point.y) - input.shape.z);
            float slitRadius = min(input.shape.x, input.shape.y) * 0.5f;
            float ink = roundCoverage(slitPoint, input.shape.xy, slitRadius) * 0.93f;
            float alpha = ink + base * (1.0f - ink);
            return half4(half3(input.tint.rgb * alpha), half(alpha));
        }
        """
}
