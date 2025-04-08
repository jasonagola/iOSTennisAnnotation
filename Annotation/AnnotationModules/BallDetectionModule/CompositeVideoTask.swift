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
    
    // Hardcoded for now; in future, these may be retrieved from the project model.
    private let fps: Int32 = 60
    
    // MARK: - Initialization
    init(projectUUID: UUID, modelContext: ModelContext) {
        self.projectUUID = projectUUID
        self.modelContext = modelContext
    }
    
    // Publishers for task state
    var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
        $state.eraseToAnyPublisher()
    }
    var progressPublisher: AnyPublisher<Double, Never> {
        $progress.eraseToAnyPublisher()
    }
    var statusMessagePublisher: AnyPublisher<String, Never> {
        $statusMessage.eraseToAnyPublisher()
    }
    
    // MARK: - Task Start
    func start() async {
        await MainActor.run {
            self.state = .running
            self.statusMessage = "Starting video rendering..."
            self.progress = 0.0
        }
        
        // Create and configure your FrameState.
        let frameState = FrameState(modelContext: modelContext,
                                    projectUUID: projectUUID,
                                    selectedFrameUUID: nil)
        // Load frames (assumes an async function exists).
        await frameState.loadFrames()
        
        guard frameState.frames.count > 0 else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "No frames available for processing."
            }
            return
        }
        
        // Configure FrameState (e.g. setting initial currentFrameUUID).
        await frameState.configure(modelContext: modelContext, projectUUID: projectUUID)
        
        let frames = frameState.frames
        let totalFrames = frames.count
        
        // Use the resolution of the first frame as the video canvas size.
        guard let firstImage = loadImage(for: frames.first!) else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Failed to load first image."
            }
            return
        }
        let canvasSize = firstImage.size
        
        // Determine the output URL.
        let projectDir = frameState.projectDir!
        let outputURL = projectDir.appendingPathComponent("compositeOverlay.mov")
        
        do {
            try await createCompositeVideo(for: frames, canvasSize: canvasSize, outputURL: outputURL)
            await MainActor.run {
                self.state = .completed
                self.statusMessage = "Video rendering complete."
                self.progress = 1.0
            }
            print("Composite video stored at \(outputURL)")
        } catch {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Video rendering failed: \(error)"
            }
        }
    }
    
    func cancel() {
        isCancelled = true
        Task { await MainActor.run { self.state = .failed; self.statusMessage = "Cancelled" } }
    }
    
    func pause() {
        state = .paused
        statusMessage = "Paused"
    }

    func resume() {
        if state == .paused {
            state = .running
            statusMessage = "Resumed"
        }
    }
    
    // MARK: - Video Creation with Sliding Window Compositing
    
    /// Create a composite video from the base frames.
    /// - Parameters:
    ///   - frames: The array of Frame objects (assumed to have imagePath and id).
    ///   - canvasSize: The desired resolution (matching the first image's size).
    ///   - outputURL: The file URL where the video will be written.
    ///   - fps: Frames per second (default 60).
    func createCompositeVideo(for frames: [Frame],
                              canvasSize: CGSize,
                              outputURL: URL,
                              fps: Int32 = 60) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: canvasSize.width,
            AVVideoHeightKey: canvasSize.height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(writerInput) else {
            throw CompositeVideoError.cannotAddInput
        }
        writer.add(writerInput)
        
        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: canvasSize.width,
            kCVPixelBufferHeightKey as String: canvasSize.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                           sourcePixelBufferAttributes: sourceBufferAttributes)
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let frameDuration = CMTime(value: 1, timescale: fps)
        
        // For each frame index, use a sliding window to composite a single output image.
        for i in 0..<frames.count {
            if isCancelled { break }
            
            // The center frame for the composite
            let centerIndex = i
            let compositeImage = compositeImageForFrame(centerIndex: centerIndex, frames: frames, canvasSize: canvasSize)
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            
            guard let pixelBuffer = createPixelBuffer(from: compositeImage, size: canvasSize) else {
                throw CompositeVideoError.pixelBufferCreationFailed
            }
            
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            
            await MainActor.run {
                self.progress = Double(i + 1) / Double(frames.count)
                self.statusMessage = "Rendered frame \(i + 1) of \(frames.count)"
            }
        }
        
        writerInput.markAsFinished()
        writer.finishWriting {
            print("Video writing finished at \(outputURL)")
        }
    }
    
    /// Composite a single image from a sliding window of frames.
    /// This function applies a sliding window (using a fixed preload margin) to determine
    /// which frames to composite, then sorts those images by how far their index is from the center.
    /// The images are drawn with the specified opacity.
    func compositeImageForFrame(centerIndex: Int, frames: [Frame], canvasSize: CGSize) -> UIImage {
        // Define your preload margin (number of frames to include on each side).
        let preloadMargin = 8
        let start = max(centerIndex - preloadMargin, 0)
        let end = min(centerIndex + preloadMargin, frames.count - 1)
        var compositeItems: [CompositeFrameItem] = []
        
        // For each frame in the sliding window, load the image and compute the desired opacity.
        for i in start...end {
            let frame = frames[i]
            guard let image = loadImage(for: frame) else { continue }
            let opacity = opacityForIndex(index: i, centerIndex: centerIndex)
            let item = CompositeFrameItem(index: i,
                                          uuid: frame.id,
                                          image: image,
                                          detections: [], // Detections not used here.
                                          opacity: opacity)
            compositeItems.append(item)
        }
        
        // Sort items so that items with higher distance from the center are drawn first.
        let sortedItems = compositeItems.sorted { abs($0.index - centerIndex) > abs($1.index - centerIndex) }
        
        // Composite the images into one using Core Graphics.
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let compositeImage = renderer.image { context in
            for item in sortedItems {
                let drawRect = CGRect(origin: .zero, size: canvasSize)
                item.image.draw(in: drawRect, blendMode: .normal, alpha: item.opacity)
            }
        }
        return compositeImage
    }
    
    /// Compute opacity using your provided function.
    func opacityForIndex(index: Int, centerIndex: Int) -> Double {
        let distance = abs(index - centerIndex)
        switch distance {
        case 0: return 0.5   // center frame
        case 1: return 0.8
        case 2: return 0.9
        case 3: return 1.0
        default: return 1.0
        }
    }
    
    /// Convert a UIImage to a CVPixelBuffer.
    func createPixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         options as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let pixelData = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        guard let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    // MARK: - Image Loading Helper
    
    func loadImage(for frame: Frame) -> UIImage? {
        guard let path = frame.imagePath else {
            print("No imagePath for frame \(frame.frameName)")
            return nil
        }
        let resolvedPath = FilePathResolver.resolveFullPath(for: path)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("File does not exist at path: \(resolvedPath)")
            return nil
        }
        if let image = UIImage(contentsOfFile: resolvedPath) {
            print("✅ loadImage: Successfully loaded image for frame \(frame.frameName) (\(frame.id))")
            return image
        } else {
            print("❌ loadImage: Failed to decode image from file at path: \(resolvedPath)")
            return nil
        }
    }
}
