//
//  VideoScrubberView.swift
//  Annotation
//
//  Created by Jason Agola on 4/8/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import AVKit

// MARK: - VideoMetaData
/// A simple struct to hold video meta data.
struct VideoMetaData {
    let duration: Double
    let size: CGSize
    let fps: Double
}

// MARK: - VideoScrubberViewModel
class VideoScrubberViewModel: ObservableObject {
    private var frameState: FrameState
    @Published var player: AVPlayer
    @Published var currentTime: CMTime = .zero
    @Published var totalDetections: Int = 0
    @Published var detections: [UUID: [BallDetection]] = [:]
    var imageSize: CGSize?
    
    // Video meta data property (optional until loaded)
    @Published var videoMetaData: VideoMetaData?
    
    // We now manage navigation using a frame index.
    @Published var centerFrameIndex: Int = 0 {
        didSet {
            // Update the center frame’s UUID from our sorted frames array.
            if let newFrame = sortedFrames[safe: centerFrameIndex] {
                centerFrameUUID = newFrame.id
                // Compute the corresponding time for this frame index.
                let targetTime = timeForFrame(centerFrameIndex, fps: fps)
                seek(to: targetTime)
            }
        }
    }
    
    /// Maintained for compatibility with your detections dictionary.
    @Published var centerFrameUUID: UUID = UUID()
    
    /// Sorted array of frames based on the new index property.
    var sortedFrames: [Frame] {
        return frameState.frames.sorted { $0.index < $1.index }
    }
    
    private var fps: Double = 60.0
    private var timeObserverToken: Any?
    private var avAsset: AVAsset
    
    init(url: URL, fps: Double = 60.0, frameState: FrameState) {
        self.fps = fps
        self.player = AVPlayer(url: url)
        self.avAsset = AVURLAsset(url: url)
        self.frameState = frameState
        
        // Use the sorted frames to set up the initial center frame.
        if let firstFrame = sortedFrames.first {
            self.centerFrameUUID = firstFrame.id
            self.centerFrameIndex = firstFrame.index
        } else {
            self.centerFrameUUID = UUID()
            self.centerFrameIndex = 0
        }
        
        addPeriodicTimeObserver()
        loadDetections()
        // Start an asynchronous task to load video meta data.
        Task {
            await loadVideoMetaData()
        }
    }
    
    /// Computes a CMTime for a given frame index.
    func timeForFrame(_ frameIndex: Int, fps: Double) -> CMTime {
        // For a constant frame rate, frameIndex/fps seconds is the frame’s time.
        return CMTimeMake(value: Int64(frameIndex), timescale: Int32(fps))
    }
    
    /// Moves to the next frame.
    func stepForward() {
        if centerFrameIndex < sortedFrames.count - 1 {
            centerFrameIndex += 1
        }
    }
    
    /// Moves to the previous frame.
    func stepBackward() {
        if centerFrameIndex > 0 {
            centerFrameIndex -= 1
        }
    }
    
    /// Seek the video player to a specified time.
    private func seek(to time: CMTime) {
        DispatchQueue.main.async {
            self.player.pause()
            // Use zero tolerance to seek as precisely as possible.
            self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    /// Adds a periodic time observer to update the current time.
    private func addPeriodicTimeObserver() {
        let interval = CMTimeMake(value: 1, timescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time
        }
    }
    
    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }
    
    // MARK: - Detection Handling
    func loadDetections() {
        let frameIDs = frameState.frames.map { $0.id }
        let context = frameState.safeContext
        
        let ballDetectionsFetchDescriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate {
                if let detectionFrameUUID = $0.frameUUID {
                    return frameIDs.contains(detectionFrameUUID)
                } else {
                    return false
                }
            }
        )
        
        do {
            let allBallDetections = try context.fetch(ballDetectionsFetchDescriptor)
            print("All Ball Detections Loaded: \(allBallDetections.count)")
            self.totalDetections = allBallDetections.count
            self.detections = Dictionary(grouping: allBallDetections, by: { $0.frameUUID! })
        } catch {
            print("Composite Video: Ball Detections Failed to Load: \(error)")
        }
    }
    
    // MARK: - Video Meta Data Loading
    /// Loads video meta data asynchronously.
    private func loadVideoMetaData() async {
        do {
            // Ensure necessary properties are loaded.
            _ = try await avAsset.load(.tracks)
            let durationCMTime = try await avAsset.load(.duration)
            let videoDuration = CMTimeGetSeconds(durationCMTime)
            print("Duration: \(videoDuration)")
            
            let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
            if let track = videoTracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                print("Size: \(size), Transform: \(transform)")
                
                let frameRate = try await track.load(.nominalFrameRate)
                print("Frame Rate: \(frameRate)")
                // Optionally update fps if necessary.
                DispatchQueue.main.async {
                    self.fps = frameRate > 0 ? Double(frameRate) : self.fps
                    self.videoMetaData = VideoMetaData(duration: videoDuration, size: size, fps: self.fps)
                }
            }
        } catch {
            print("VSV: Error loading video meta data: \(error)")
        }
    }
}

// MARK: - VideoScrubberView
struct VideoScrubberView: View {
    private var frameState: FrameState
    @StateObject private var viewModel: VideoScrubberViewModel
    @State private var forwardTimer: Timer?
    @State private var backwardTimer: Timer?
    private var videoURL: URL
    private var imageSize: CGSize
    
    init(videoURL: URL, frameState: FrameState, imageSize: CGSize) {
        self.videoURL = videoURL
        self.frameState = frameState
        self.imageSize = imageSize
        _viewModel = StateObject(wrappedValue: VideoScrubberViewModel(url: videoURL, frameState: frameState))
        runCheck()
    }
    
    var body: some View {
        // 1) Compute these outside of the ZStack builder
        let center = viewModel.centerFrameIndex
        let prevIndex = center - 1
        let futureIndices = (1...5)
            .map { center + $0 }
            .filter { $0 < viewModel.sortedFrames.count }
        
        return ZStack {
            VideoPlayer(player: viewModel.player)
                .opacity(1)
                .onAppear { viewModel.player.play() }
            
            // 1) Previous frame (red, lower z)
            if prevIndex >= 0 {
                let uuid = viewModel.sortedFrames[prevIndex].id
                if let dets = viewModel.detections[uuid] {
                    detectionRects(dets, color: .red,   z: 80)
                }
            }

            // 2) Current frame (blue, top z)
            if let currUUID = viewModel.sortedFrames[safe: center]?.id,
               let dets = viewModel.detections[currUUID] {
                detectionRects(dets, color: .blue,  z:100)
            }

            // 3) Next 5 frames (green, mid z)
            ForEach(futureIndices, id: \.self) { idx in
                let uuid = viewModel.sortedFrames[idx].id
                if let dets = viewModel.detections[uuid] {
                    detectionRects(dets, color: .green, z: 90)
                }
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // figure out if that press is inside the CURRENT‐frame box…
                    if let currUUID = viewModel.sortedFrames[safe: viewModel.centerFrameIndex]?.id,
                       let dets = viewModel.detections[currUUID] {
                        let loc = value.location
                        for det in dets {
                            let box = CGRect(
                                x: det.boundingBoxMinX * imageSize.width,
                                y: det.boundingBoxMinY * imageSize.height,
                                width: det.boundingBoxWidth  * imageSize.width,
                                height: det.boundingBoxHeight * imageSize.height
                            )
                            if box.contains(loc) {
                                // this fires on _finger-down_ and continues as you hold
                                viewModel.stepForward()
                                break
                            }
                        }
                    }
                }
        )
    }

    @ViewBuilder
       private func detectionRects(
           _ detections: [BallDetection],
           color: Color,
           z: Double
       ) -> some View {
           ForEach(detections, id: \.id) { det in
               detectionRectView(det, strokeColor: color, z: z)
           }
       }

       private func detectionRectView(
           _ det: BallDetection,
           strokeColor: Color,
           z: Double
       ) -> some View {
           // convert from normalized → image space
           let rect = CGRect(
               x: det.boundingBoxMinX * imageSize.width,
               y: det.boundingBoxMinY * imageSize.height,
               width: det.boundingBoxWidth  * imageSize.width,
               height: det.boundingBoxHeight * imageSize.height
           )
           return Rectangle()
               .stroke(strokeColor, lineWidth: 4)
               .frame(width: rect.width, height: rect.height)
               .position(x: rect.midX, y: rect.midY)
               .contentShape(Rectangle())
               .zIndex(z)
               .onLongPressGesture(minimumDuration: 0,
                                   maximumDistance: .infinity,
                                   pressing: { down in
                   if down && z == 100 {
                       // only advance on the current‐frame layer
                       viewModel.stepForward()
                   }
               }, perform: {})
       }

    private func colorForAnnotation(_ index: Int) -> Color {
        let distance = abs(index - viewModel.centerFrameIndex)
        switch distance {
        case 0: return .red
        case 1: return .orange
        case 2...10:
            let blend = Double(distance - 2) / 8.0
            return Color(red: 1.0, green: 1.0 - blend * 0.5, blue: 0.0)
        default: return .white
        }
    }
    

    
    private func zIndexForAnnotation(_ index: Int) -> Double {
        let distance = abs(index - viewModel.centerFrameIndex)
        switch distance {
        case 0: return 102
        case 1: return 101
        default: return 99
        }
    }
    
    private func runCheck() {
        if FileManager.default.fileExists(atPath: videoURL.path),
           let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
           let fileSize = attributes[.size] as? Int64, fileSize > 0 {
            print("VideoScrubberView: Composite video stored at \(videoURL)")
            print("File Size: \(fileSize) bytes")
        } else {
            print("File at \(videoURL.path) does not exist or is empty.")
        }
    }
    
    private func holdButton(label: String, action: @escaping () -> Void, timer: Binding<Timer?>) -> some View {
        Text(label)
            .font(.largeTitle)
            .padding()
            .background(Color.white.opacity(0.7))
            .clipShape(Circle())
            .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                if pressing {
                    timer.wrappedValue = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        action()
                    }
                } else {
                    timer.wrappedValue?.invalidate()
                    timer.wrappedValue = nil
                }
            }, perform: {})
    }
}

// MARK: - Array Extension for Safe Indexing
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
