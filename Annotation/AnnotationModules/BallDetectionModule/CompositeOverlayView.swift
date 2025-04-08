//
//  CompositeOverlayView.swift
//  Annotation
//
//  Created by Jason Agola on 4/3/25.


import SwiftUI
import SwiftData
import AVFoundation

extension FrameState {
    static var placeholder: FrameState {
        let state = FrameState()
        // configure default values if needed
        return state
    }
}

//Separate Image Loading and compositeframe Array logic from rerendering logic like(changed Opacity and z index)
//moveForward and moveBackward methods should change the viewing params(opacity and z index) then trigger async loading operations
//View in forEeach should only render a subset of the loaded images so as not to retrigger as items are added.
//.id adds to each annotation and frame to prevent rerender

struct CompositeFrameItem {
    let index: Int
    let uuid: UUID
    let image: UIImage
    let detections: [BallDetection]
    var opacity: Double
}

final class CompositeOverlayViewModel: ObservableObject {
    @Published var compositeFrames: [CompositeFrameItem] = []
    @Published var centerFrameIndex: Int = 0

    // Store a reference to your shared frameState.
    private var frameState: FrameState

    // You can inject the frameState dependency via the initializer.
    init(frameState: FrameState) {
        self.frameState = frameState
        initializeCompositeFrames()
    }
    
    private var preloadMargin: Int { 5 }
    private var renderMargin: Int { 3 }
    
    private var preloadRange: ClosedRange<Int> {
        let start = max(centerFrameIndex - preloadMargin, 0)
        let end = min(centerFrameIndex + preloadMargin, frameState.frames.count - 1)
        return start...end
    }
    
    private var visibleRange: ClosedRange<Int> {
        let start = max(centerFrameIndex - renderMargin, 0)
        let end = min(centerFrameIndex + renderMargin, frameState.frames.count - 1)
        return start...end
    }

    func initializeCompositeFrames() {
        // Only initialize if the compositeFrames array is empty
        guard compositeFrames.isEmpty else {
            print("Composite frames already initialized")
            return
        }
        print("Initializing the Composite frames...")
        
        guard let currentUUID = frameState.currentFrameUUID,
              let index = frameState.frames.firstIndex(where: { $0.id == currentUUID }) else {
            print("Failing to find current frame UUID in frames")
            return
        }
        centerFrameIndex = index
        
        compositeFrames = preloadRange.map { i in
            let frame = frameState.frames[i]
            // loadImage(for:) and loadDetections(for:) are your helper methods.
            let image = loadImage(for: frame)
            let detections = loadDetections(for: frame.id)
            // Hardcoding opacity for simplicity.
            let opacity = 0.1
            return CompositeFrameItem(index: i,
                                      uuid: frame.id,
                                      image: image!, // Force unwrap since you expect a valid image.
                                      detections: detections,
                                      opacity: opacity)
        }
        //Instead what if I

       
    }
    
    // Example helper methods:
    func loadImage(for frame: Frame) -> UIImage? {
        print("Calling Load Image...")
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
    
    func loadDetections(for uuid: UUID) -> [BallDetection] {
        let context = frameState.safeContext  // Will crash if not set, as intended
        let descriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate { $0.frameUUID == uuid }
        )
        do {
            let results = try context.fetch(descriptor)
            print("✅ Loaded \(results.count) detections for frame \(uuid)")
            return results
        } catch {
            print("❌ Error fetching detections for frame \(uuid): \(error)")
            return []
        }
    }
    
    // Optionally, implement moveForward() and other navigation methods here.
    func moveForward() {
        let nextIndex = centerFrameIndex + 1
        guard nextIndex < frameState.frames.count else { return }
        
        centerFrameIndex = nextIndex
        
        // Remove frames from the beginning if they're outside the preload range.
        if let first = compositeFrames.first,
           let firstIndex = frameState.frames.firstIndex(where: { $0.id == first.uuid }),
           firstIndex < preloadRange.lowerBound {
            compositeFrames.removeFirst()
        }
        
        // Append a new frame at the upper bound of the preload range.
        let newIndex = preloadRange.upperBound
        if newIndex < frameState.frames.count {
            let frame = frameState.frames[newIndex]
            guard let image = loadImage(for: frame) else { return }
            let detections = loadDetections(for: frame.id)
            let opacity = visibleRange.contains(newIndex) ? 0.5 : 0.1
            let newItem = CompositeFrameItem(index: newIndex,
                                             uuid: frame.id,
                                             image: image,
                                             detections: detections,
                                             opacity: opacity)
            compositeFrames.append(newItem)
        }
        
        // You could update opacities here if needed.
    }
}

struct CompositeOverlayView: View {
//    @EnvironmentObject var frameState: FrameState
    @StateObject private var viewModel: CompositeOverlayViewModel
    private var frameState: FrameState
    //    @EnvironmentObject(./modelContext) private var modelContext
    
//    @State private var compositeFrames: [CompositeFrameItem] = []
//    @State private var centerFrameIndex: Int = 0
//    let imageSize: CGSize = CGSize(width: 3480, height: 2640)
    
    init(frameState: FrameState) {
        // You can pass a placeholder here if needed; the real frameState
        // will be injected by the environment. Alternatively, you might
        // delay creating the view model until onAppear.
        self.frameState = frameState
        _viewModel = StateObject(wrappedValue: CompositeOverlayViewModel(frameState: frameState))
    }
    
//    let renderMargin = 5            // Render 5 frames before and after
//    let preloadMargin = 8          // 2 extra before/after
    
    var body: some View {
        ZStack {
            ForEach(viewModel.compositeFrames, id: \.uuid) { item in
                imageView(for: item)
                ForEach(item.detections, id: \.id) { detection in
                    annotationView(for: detection, index: item.index)
                }
            }
        }
    }
    
    private func imageView(for item: CompositeFrameItem) -> some View {
        Image(uiImage: item.image)
            .id(item.uuid)
            .scaledToFit()
            .opacity(opacityForIndex(item.index))
            .zIndex(zIndexForIndex(item.index))
            .animation(Animation.easeInOut(duration: 0.05), value: viewModel.centerFrameIndex)
    }
    
    private func annotationView(for detection: BallDetection, index: Int) -> some View {
        Rectangle()
            .stroke(Color.blue, lineWidth: 2)
            .id(detection.id)
            .frame(width: detection.boundingBoxWidth, height: detection.boundingBoxHeight)
            .position(x: detection.computedCenterX, y: detection.computedCenterY)
            .zIndex(zIndexForAnnotation(index))
            .contentShape(Rectangle())
            .onTapGesture {
                if index == viewModel.centerFrameIndex {
                    viewModel.moveForward()
                }
                print("Annotation tapped")
            }
    }
    
    private func opacityForIndex(_ index: Int) -> Double {
        let distance = abs(index - viewModel.centerFrameIndex)
        
        switch distance {
        case 0: return 0.5   // center frame
        case 1: return 0.8
        case 2: return 0.9
        case 3: return 1.0
        default: return 1.0  // furthest frames — strongest blend base
        }
    }
    
    private func zIndexForIndex(_ index: Int) -> Double {
        let distance = abs(index - viewModel.centerFrameIndex)
        // Reverse order: closer frames go on top
        return Double(100 - distance)
    }
    
    private func colorForAnnotation(_ index: Int) -> Color {
        let distance = abs(index - viewModel.centerFrameIndex)
        
        switch distance {
        case 0:
            return .red
        case 1:
            return .orange
        case 2...10:
            let blend = Double(distance - 2) / 8.0  // normalize 2–10 → 0.0–1.0
            let yellow = UIColor.yellow
            let white = UIColor.white
            
            var yRed: CGFloat = 0, yGreen: CGFloat = 0, yBlue: CGFloat = 0, yAlpha: CGFloat = 0
            var wRed: CGFloat = 0, wGreen: CGFloat = 0, wBlue: CGFloat = 0, wAlpha: CGFloat = 0
            
            yellow.getRed(&yRed, green: &yGreen, blue: &yBlue, alpha: &yAlpha)
            white.getRed(&wRed, green: &wGreen, blue: &wBlue, alpha: &wAlpha)
            
            let red = yRed * (1 - blend) + wRed * blend
            let green = yGreen * (1 - blend) + wGreen * blend
            let blue = yBlue * (1 - blend) + wBlue * blend
            
            return Color(red: Double(red), green: Double(green), blue: Double(blue))
            
        default:
            return .white
        }
    }
    
    private func zIndexForAnnotation(_ index: Int) -> Double {
        let distance = abs(index - viewModel.centerFrameIndex)
        
        switch distance {
        case 0: return 102
        case 1: return 101
            // Center frame annotations go above image layers
        default: return 99 // Other annotations go below top image layer
        }
    }

    enum CompositeVideoError: Error {
        case cannotAddInput
        case pixelBufferCreationFailed
    }

    func createCompositeVideo(from frames: [CompositeFrameItem],
                              outputURL: URL,
                              fps: Int32 = 60) throws {
        guard let firstImage = frames.first?.image else { return }
        let outputSize = firstImage.size

        // Create asset writer.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                           sourcePixelBufferAttributes: sourceBufferAttributes)

        guard writer.canAdd(writerInput) else {
            throw CompositeVideoError.cannotAddInput
        }
        writer.add(writerInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTimeMake(value: 1, timescale: fps)

        for (i, composite) in frames.enumerated() {
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            guard let pixelBuffer = createPixelBuffer(from: composite.image, size: outputSize) else {
                throw CompositeVideoError.pixelBufferCreationFailed
            }
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        writer.finishWriting {
            print("Video writing finished at \(outputURL)")
        }
    }

    /// Helper function to convert UIImage to CVPixelBuffer.
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
        let pixelData = CVPixelBufferGetBaseAddress(buffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        guard let cgImage = image.cgImage else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}
    
