//
//  VideoScrubberView.swift
//  Annotation
//
//  Created by Jason Agola on 4/8/25.
//

import SwiftUI

import SwiftUI
import SwiftData
import AVFoundation
import AVKit

class VideoScrubberViewModel: ObservableObject {
    private var frameState: FrameState
    @Published var player: AVPlayer
    @Published var currentTime: CMTime = .zero
    @Published var detections: [UUID: [BallDetection]] = [:]

    // New properties to track the "center" frame.
    // We'll set centerFrameUUID to the first frame's id if it exists.
    @Published var centerFrameUUID: UUID
    @Published var centerFrameIndex: Int = 0 {
        didSet {
            // When the center frame changes, compute the corresponding time and seek.
            let targetTime = timeForFrame(centerFrameIndex, fps: fps)
            seek(to: targetTime)
        }
    }

    private var fps: Double = 60.0
    private var timeObserverToken: Any?

    init(url: URL, fps: Double = 60.0, frameState: FrameState)  {
        self.fps = fps
        self.player = AVPlayer(url: url)
        self.frameState = frameState

        // Establish the centerFrame as the first frame from frameState (if available)
        if let firstFrame = frameState.frames.first {
            self.centerFrameUUID = firstFrame.id
        } else {
            // Provide a fallback UUID, though you may want to handle this case more robustly
            self.centerFrameUUID = UUID()
        }
        
        addPeriodicTimeObserver()
        loadDetections()
    }
    
    func timeForFrame(_ frameIndex: Int, fps: Double) -> CMTime {
        // The value is the frame index (as an integer), and the timescale is the number of frames per second.
        return CMTimeMake(value: Int64(frameIndex), timescale: Int32(fps))
    }

    func stepForward() {
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        let newTime = currentTime + frameDuration
        seek(to: newTime)
    }

    func stepBackward() {
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        let newTime = CMTimeMaximum(currentTime - frameDuration, .zero)
        seek(to: newTime)
    }

    private func seek(to time: CMTime) {
        // Ensure we update on the main thread.
        DispatchQueue.main.async {
            self.player.pause()
            // The zero tolerances request that we seek as precisely as possible.
            self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    

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
    
    //Detection Handling
    func loadDetections() {
        let frameIDs = frameState.frames.map{$0.id}
        let context = frameState.safeContext
        
        let ballDetectionsFetchDescriptor = FetchDescriptor<BallDetection>(
            predicate:#Predicate {
                if let detectionFrameUUID = $0.frameUUID {
                    return frameIDs.contains(detectionFrameUUID)
                } else {
                    return false
                }
            }
        )
        
        do {
            let allBallDetections = try context.fetch(ballDetectionsFetchDescriptor)
            self.detections = Dictionary(grouping: allBallDetections, by: { $0.frameUUID!})

            } catch {
                print("Composite Video: Ball Detections Failed to Load: \(error)")
            }
    }
}

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
            // The video player is at the bottom.
            VideoPlayer(player: viewModel.player)
                .onAppear {
                    viewModel.player.pause()
                }

            // Overlay the detection annotations.
            // For this example, we assume that viewModel.centerFrameUUID is computed from the current time or selection.
            if let currentDetections = viewModel.detections[viewModel.centerFrameUUID] {
                ForEach(Array(currentDetections.enumerated()), id: \.element.id) { index, detection in
                    annotationView(for: detection, index: index)
                }
            }

            // Scrubber controls (or additional UI) appear on top.
            HStack {
                holdButton(label: "⏪", action: viewModel.stepBackward, timer: $backwardTimer)
                Spacer()
                holdButton(label: "⏩", action: viewModel.stepForward, timer: $forwardTimer)
            }
            .padding()
            .id("Scrubber")
        }
    }

    // Example annotation view – renders a rectangle around a detection.
    private func annotationView(for detection: BallDetection, index: Int) -> some View {
        Rectangle()
            .stroke(colorForAnnotation(index), lineWidth: 2)
            .id(detection.id)
            .frame(width: detection.boundingBoxWidth, height: detection.boundingBoxHeight)
            .position(x: detection.computedCenterX, y: detection.computedCenterY)
            .zIndex(zIndexForAnnotation(index))
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.centerFrameIndex = index
            }
    }
    

    private func colorForAnnotation(_ index: Int) -> Color {
        // Example: return red for the center detection and variants for others.
        let distance = abs(index - viewModel.centerFrameIndex)
        switch distance {
        case 0:
            return .red
        case 1:
            return .orange
        case 2...10:
            let blend = Double(distance - 2) / 8.0  // normalize 2–10 → 0.0–1.0
            return Color(red: 1.0, green: 1.0 - blend * 0.5, blue: 0.0)
        default:
            return .white
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
        // Checks file existence for the composite video.
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
