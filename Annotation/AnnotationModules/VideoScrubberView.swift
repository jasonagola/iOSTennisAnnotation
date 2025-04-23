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
    
    init(videoURL: URL, frameState: FrameState) {
        self.videoURL = videoURL
        self.frameState = frameState
        _viewModel = StateObject(wrappedValue: VideoScrubberViewModel(url: videoURL, frameState: frameState))
        runCheck()
    }
    
    var body: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .onAppear { viewModel.player.play() }
            
//            // Overlay the detection annotations.
//            if let currentDetections = viewModel.detections[viewModel.centerFrameUUID] {
//                ForEach(Array(currentDetections.enumerated()), id: \.element.id) { index, detection in
//                    annotationView(for: detection, index: index)
//                        .zIndex(100)
//                }
//            }
            
//            // Scrubber controls appear on top.
//            HStack {
//                holdButton(label: "⏪", action: viewModel.stepBackward, timer: $backwardTimer)
//                Spacer()
//                holdButton(label: "⏩", action: viewModel.stepForward, timer: $forwardTimer)
//            }
//            .padding()
//            .id("Scrubber")
        }
    }
    
    // MARK: - Annotation Overlay
    private func annotationView(for detection: BallDetection, index: Int) -> some View {
        Rectangle()
            .stroke(colorForAnnotation(index), lineWidth: 2)
            .id(detection.id)
            .frame(width: detection.boundingBoxWidth, height: detection.boundingBoxHeight)
            .position(x: detection.computedCenterX, y: detection.computedCenterY)
            .zIndex(zIndexForAnnotation(index))
            .contentShape(Rectangle())
            .onTapGesture {
                // Set the new frame based on detection tap.
                viewModel.centerFrameIndex = index
            }
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
