//
//  CompositeVideoTask.swift
//  Annotation
//
//  Created by Jason Agola on 4/7/25.
//

import AVFoundation
import SwiftUI
import Combine
import SwiftData
import MetalKit
import CoreImage

enum CompositeVideoError: Error {
    case cannotAddInput
    case pixelBufferCreationFailed
}

/// A processing task that creates a composite video from a series of frames.
/// This task uses a sliding window to composite images with different opacity
/// values based on their distance from the current (center) frame.
final class CompositeVideoRenderingTask: ProcessingTask, ObservableObject {
    let id = UUID()
    let title = "Composite Video Rendering"
    
    @Published var state: ProcessingTaskState = .pending
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Pending"
    
    private let projectUUID: UUID
    private let modelContext: ModelContext
    private var isCancelled = false
    
    // Hardcoded FPS value; this may be dynamic in the future.
    private let fps: Int32 = 60
    
    // MARK: - GPU / Core Image Context Setup
    // Create a Metal-backed CIContext so that compositing runs on the GPU.
    private lazy var metalDevice: MTLDevice? = {
        let device = MTLCreateSystemDefaultDevice()
        print("CIContext: Created metal device: \(String(describing: device))")
        return device
    }()
    
    private lazy var ciContext: CIContext? = {
        guard let device = metalDevice else {
            print("CIContext: ERROR - Failed to obtain metal device.")
            return nil
        }
        let context = CIContext(mtlDevice: device, options: nil)
        print("CIContext: Successfully created CIContext with metal device.")
        return context
    }()
    
    // MARK: - Initialization
    init(projectUUID: UUID, modelContext: ModelContext) {
        self.projectUUID = projectUUID
        self.modelContext = modelContext
        print("CompositeVideoRenderingTask: Initialized for project \(projectUUID)")
    }
    
    // MARK: - Task State Publishers
    var statePublisher: AnyPublisher<ProcessingTaskState, Never> { $state.eraseToAnyPublisher() }
    var progressPublisher: AnyPublisher<Double, Never> { $progress.eraseToAnyPublisher() }
    var statusMessagePublisher: AnyPublisher<String, Never> { $statusMessage.eraseToAnyPublisher() }
    
    // MARK: - Task Start
    func start() async {
        await MainActor.run {
            self.state = .running
            self.statusMessage = "Starting video rendering..."
            self.progress = 0.0
        }
        print("CompositeVideoRenderingTask: Starting task.")
        
        // Use frameState only to obtain the list of frames and the project directory.
        let frameState = FrameState(modelContext: modelContext,
                                    projectUUID: projectUUID,
                                    selectedFrameUUID: nil)
//        print("CompositeVideoRenderingTask: Loading frames...")
        await frameState.loadFrames()
        
        let totalFrames = frameState.frames.count
        print("CompositeVideoRenderingTask: Loaded \(totalFrames) frames.")
        guard totalFrames > 0 else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "No frames available for processing."
            }
            print("CompositeVideoRenderingTask: ERROR - No frames available.")
            return
        }
        
        print("CompositeVideoRenderingTask: Configuring frame state for project \(projectUUID)")
        await frameState.configure(modelContext: modelContext, projectUUID: projectUUID)
        
        // Use the resolution of the first frame using loadImage.
        guard let firstImage = DirectoryLoader.loadImage(for: frameState.frames.first!) else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Failed to load first image."
            }
            print("CompositeVideoRenderingTask: ERROR - Failed to load the first image.")
            return
        }
        let canvasSize = firstImage.size
        print("CompositeVideoRenderingTask: Using canvas size: \(canvasSize)")
        
        // Get the project directory from frameState (without modifying its state).
        guard let projectDir = frameState.projectDir else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Project directory not found."
            }
            print("CompositeVideoRenderingTask: ERROR - Project directory not available.")
            return
        }
        let outputURL = projectDir.appendingPathComponent("compositeOverlay.mov")
        print("CompositeVideoRenderingTask: Output URL set to: \(outputURL)")
        
        // Do not attempt to create the output directory.
        // Assert that the output directory exists.
        let outputDirectory = outputURL.deletingLastPathComponent()
        assert(FileManager.default.fileExists(atPath: outputDirectory.path),
               "Output directory \(outputDirectory.path) does not exist! Please ensure that the project directory is created before running the composite task.")
        print("CompositeVideoRenderingTask: Verified output directory exists.")
        
        do {
            try await createCompositeVideo(for: frameState.frames,
                                             canvasSize: canvasSize,
                                             outputURL: outputURL)
            await MainActor.run {
                self.state = .completed
                self.statusMessage = "Video rendering complete."
                self.progress = 1.0
            }
            print("CompositeVideoRenderingTask: Composite video stored at \(outputURL)")
        } catch {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Video rendering failed: \(error)"
            }
            print("CompositeVideoRenderingTask: ERROR - Video rendering failed: \(error)")
        }
    }
    
    func cancel() {
        isCancelled = true
        Task {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Cancelled"
            }
        }
        print("CompositeVideoRenderingTask: Task cancelled.")
    }
    
    func pause() {
        state = .paused
        statusMessage = "Paused"
        print("CompositeVideoRenderingTask: Task paused.")
    }
    
    func resume() {
        if state == .paused {
            state = .running
            statusMessage = "Resumed"
            print("CompositeVideoRenderingTask: Task resumed.")
        }
    }
    
    // MARK: - Video Creation with Sliding Window Compositing
    func createCompositeVideo(for frames: [Frame],
                              canvasSize: CGSize,
                              outputURL: URL,
                              fps: Int32 = 60) async throws {
        print("CompositeVideoRenderingTask: Starting video creation...")
        
        // Remove any existing file at the output URL.
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
                print("CompositeVideoRenderingTask: Removed existing file at \(outputURL.path)")
            } catch {
                print("CompositeVideoRenderingTask: Failed to remove existing file at \(outputURL.path): \(error)")
            }
        }
        
        // ───────── Video settings ─────────
        let useHEVC = AVAssetExportSession.allExportPresets()
            .contains(AVAssetExportPresetHEVCHighestQuality)

        let codec: AVVideoCodecType
        let compression: [String: Any]

        if useHEVC {
            codec = .hevc
            compression = [
                AVVideoAverageBitRateKey: 12_000_000       // 12 Mbps for 4 K60
            ]
        } else {
            codec = .h264
            compression = [
                AVVideoAverageBitRateKey: 20_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                //  ↑ replaces the unavailable High51 constant
            ]
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: canvasSize.width,
            AVVideoHeightKey: canvasSize.height,
            AVVideoCompressionPropertiesKey: compression
        ]
        print("CompositeVideoRenderingTask: Video settings: \(videoSettings)")
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(writerInput) else {
            print("CompositeVideoRenderingTask: ERROR - Cannot add writer input.")
            throw CompositeVideoError.cannotAddInput
        }
        writer.add(writerInput)
        print("CompositeVideoRenderingTask: Writer input added.")
        
        // Pixel buffer attributes for Metal-based rendering.
        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: canvasSize.width,
            kCVPixelBufferHeightKey as String: canvasSize.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                           sourcePixelBufferAttributes: sourceBufferAttributes)
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        print("CompositeVideoRenderingTask: Writer session started at time zero.")
        
        let frameDuration = CMTime(value: 1, timescale: fps)
        print("CompositeVideoRenderingTask: Frame duration: \(frameDuration.seconds) seconds.")
        
        // Process each frame.
        for i in 0..<frames.count {
            if isCancelled {
                print("CompositeVideoRenderingTask: Rendering cancelled at frame \(i).")
                break
            }
            
            print("CompositeVideoRenderingTask: Processing frame \(i + 1) of \(frames.count)")
            let centerIndex = i
            
            guard let compositeCIImage = createCompositeCIImageForFrame(centerIndex: centerIndex,
                                                                        frames: frames,
                                                                        canvasSize: canvasSize) else {
                print("CompositeVideoRenderingTask: ERROR - Failed to composite CIImage for frame \(i + 1)")
                throw CompositeVideoError.pixelBufferCreationFailed
            }
            
            guard let pixelBuffer = createPixelBuffer(width: Int(canvasSize.width),
                                                      height: Int(canvasSize.height)) else {
                print("CompositeVideoRenderingTask: ERROR - Failed to create pixel buffer for frame \(i + 1)")
                throw CompositeVideoError.pixelBufferCreationFailed
            }
            print("CompositeVideoRenderingTask: Pixel buffer created for frame \(i + 1)")
            
            renderCIImage(compositeCIImage, to: pixelBuffer)
            print("CompositeVideoRenderingTask: Rendered CIImage to pixel buffer for frame \(i + 1)")
            
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            print("CompositeVideoRenderingTask: Appended frame \(i + 1) at time \(presentationTime.seconds) seconds.")
            
            await MainActor.run {
                self.progress = Double(i + 1) / Double(frames.count)
                self.statusMessage = "Rendered frame \(i + 1) of \(frames.count)"
            }
        }
        
        writerInput.markAsFinished()
        print("CompositeVideoRenderingTask: Marked writer input as finished.")
        
        // Wait for the writer to finish (suspends this task).
        await writer.finishWriting()
        
        // Check the final status.
        guard writer.status == .completed else {
            let error = writer.error ?? NSError(
                domain: "CompositeVideoRenderingTask",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                            "Writer finished with status \(writer.status)"]
            )
            print("CompositeVideoRenderingTask: ❌ \(error.localizedDescription)")
            throw error            // propagate to the caller
        }
        
        // Success – gather file info (optional but useful).
        let attrs     = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let bytes     = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let readable  = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let duration  = CMTimeMultiply(frameDuration, multiplier: Int32(frames.count))
        let seconds   = CMTimeGetSeconds(duration)
        
        print(String(format:
                        "CompositeVideoRenderingTask: ✅ Finished writing (%.2f s, %@).",
                     seconds, readable))
    }
    
    // MARK: - GPU Compositing with Core Image
    // MARK: - GPU Compositing with Core Image
    func createCompositeCIImageForFrame(centerIndex: Int,
                                        frames: [Frame],
                                        canvasSize: CGSize) -> CIImage? {

        // ── PARAMETERS ─────────────────────────────────────────────────────────
        let rings               = 4               // centre + 4 rings
        let targetPeak: CGFloat = 0.85            // desired brightness ceiling

        // ── HELPERS ────────────────────────────────────────────────────────────
        /// Centre = 1.0.  Ring 1 = 1/2^γ, Ring 2 = 1/3^γ, …
        let gamma: CGFloat = 1    // try 1.2 … 2.0

        func ringOpacity(for distance: Int) -> CGFloat {
            return 1.0 / pow(CGFloat(distance + 1), gamma)
        }

        func loadCI(for idx: Int) -> CIImage? {
            guard idx >= 0, idx < frames.count,
                  let ui = DirectoryLoader.loadImage(for: frames[idx]),
                  let cg = ui.cgImage else { return nil }
            return CIImage(cgImage: cg)
                .cropped(to: CGRect(origin: .zero, size: canvasSize))
        }

        // ── 1.  BUILD ONE IMAGE PER RING ───────────────────────────────────────
        var ringImages: [(distance: Int, image: CIImage)] = []

        for d in 0...rings {
            if d == 0 {
                if let img = loadCI(for: centerIndex) {
                    ringImages.append((distance: 0, image: img))
                }
            } else {
                var ring: CIImage?
                if let neg = loadCI(for: centerIndex - d) { ring = neg }
                if let pos = loadCI(for: centerIndex + d) {
                    ring = ring == nil
                        ? pos
                        : pos.applyingFilter("CIAdditionCompositing",
                                             parameters: [kCIInputBackgroundImageKey: ring!])
                }
                if let r = ring { ringImages.append((distance: d, image: r)) }
            }
        }

        // ── 2.  LIGHT‑BUDGET SCALE  (so Σweights ≤ targetPeak) ────────────────
        var totalWeight: CGFloat = 0
        for (d, _) in ringImages {
            let framesInRing = (d == 0) ? 1 : 2
            totalWeight += ringOpacity(for: d) * CGFloat(framesInRing)
        }
        let budgetScale = min(targetPeak / totalWeight, 1)
        print(String(format: "budgetScale = %.3f  (totalWeight = %.3f)",
                     budgetScale, totalWeight))

        // ── 3.  STACK THE RINGS WITH SCALED OPACITY ───────────────────────────
        var finalImage = CIImage(color: .black)
            .cropped(to: CGRect(origin: .zero, size: canvasSize))

        for (d, ring) in ringImages.sorted(by: { $0.distance < $1.distance }) {
            let ringAlpha = ring.applyingFilter(
                "CIOpacity",
                parameters: ["inputOpacity": ringOpacity(for: d) * budgetScale]
            )

            finalImage = ringAlpha.applyingFilter("CIAdditionCompositing",
                parameters: [kCIInputBackgroundImageKey: finalImage])
        }

        // ── 4.  PEAK‑BASED TONE‑MAP  (safety net) ─────────────────────────────
        if let ctx = ciContext {
            let maxImg = CIFilter(name: "CIAreaMaximum",
                parameters: [kCIInputImageKey  : finalImage,
                             kCIInputExtentKey : CIVector(cgRect: finalImage.extent)])!.outputImage!

            var px = [Float](repeating: 0, count: 4)
            ctx.render(maxImg,
                       toBitmap: &px,
                       rowBytes: 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

            let peak = CGFloat(max(px[0], px[1], px[2]))
            let scale = peak > 0 ? min(targetPeak / peak, 1) : 1
            print(String(format: "peak %.2f  →  clampScale %.3f", peak, scale))

            if scale < 1 {
                let tone = CIFilter(name: "CIColorMatrix")!
                tone.setValue(finalImage, forKey: kCIInputImageKey)
                tone.setValue(CIVector(x: scale, y: 0,     z: 0,     w: 0), forKey: "inputRVector")
                tone.setValue(CIVector(x: 0,     y: scale, z: 0,     w: 0), forKey: "inputGVector")
                tone.setValue(CIVector(x: 0,     y: 0,     z: scale, w: 0), forKey: "inputBVector")
                tone.setValue(CIVector(x: 0,     y: 0,     z: 0,     w: 1), forKey: "inputAVector")
                if let toned = tone.outputImage { finalImage = toned }
            }
        }

        return finalImage
    }
    
    /// Create a CVPixelBuffer in the BGRA format.
    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferBytesPerRowAlignmentKey: width * 4,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pixelBuffer)
        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            print("createPixelBuffer: Successfully created pixel buffer (\(width)x\(height))")
            return buffer
        } else {
            print("createPixelBuffer: ERROR - Could not create pixel buffer (status: \(status))")
            return nil
        }
    }
    
    /// Render a CIImage into a pixel buffer using the Metal-backed CIContext.
    private func renderCIImage(_ image: CIImage, to pixelBuffer: CVPixelBuffer) {
        guard let ciContext = ciContext else {
            print("renderCIImage: ERROR - CIContext is nil")
            return
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                         height: CVPixelBufferGetHeight(pixelBuffer)))
        ciContext.render(image,
                         to: pixelBuffer,
                         bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        print("renderCIImage: Rendered image into pixel buffer with bounds: \(bounds)")
    }
    
    /// Compute opacity based on the distance from the center frame.
//    func opacityForIndex(index: Int, centerIndex: Int) -> Double {
//        let distance = abs(index - centerIndex)
//        switch distance {
//        case 0: return 0.5   // Center frame.
//        case 1: return 0.8
//        case 2: return 0.9
//        case 3: return 1.0
//        default: return 1.0
//        }
//    }
    
    func opacityForIndex(index: Int,
                         centerIndex: Int,
                         sigma: Double = 4.0) -> Double {
        let d = Double(abs(index - centerIndex))
        return exp(-pow(d, 2) / (2 * sigma * sigma))
    }
}
