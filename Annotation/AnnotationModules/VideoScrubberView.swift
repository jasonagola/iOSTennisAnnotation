//
//  VideoScrubberView.swift
//  Annotation
//
//  Created by Jason Agola on 4/8/25.
//

import SwiftUI

import SwiftUI
import AVFoundation
import AVKit

class VideoScrubberViewModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var currentTime: CMTime = .zero

    private var fps: Double = 60.0
    private var timeObserverToken: Any?

    init(url: URL, fps: Double = 60.0) {
        self.fps = fps
        self.player = AVPlayer(url: url)
        addPeriodicTimeObserver()
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
        player.pause()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
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
}

struct VideoScrubberView: View {
    @StateObject private var viewModel: VideoScrubberViewModel
    @State private var forwardTimer: Timer?
    @State private var backwardTimer: Timer?

    init(videoURL: URL) {
        _viewModel = StateObject(wrappedValue: VideoScrubberViewModel(url: videoURL))
    }

    var body: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .onAppear {
                    viewModel.player.pause()
                }

            HStack {
                holdButton(label: "⏪", action: viewModel.stepBackward, timer: $backwardTimer)
                Spacer()
                holdButton(label: "⏩", action: viewModel.stepForward, timer: $forwardTimer)
            }
            .padding()
            .id("Scrubber")
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
