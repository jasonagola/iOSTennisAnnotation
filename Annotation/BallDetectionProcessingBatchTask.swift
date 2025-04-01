////
////  BallDetectionProcessingBatchTask.swift
////  Annotation
////
////  Created by Jason Agola on 3/28/25.
////
//
//
//final class BallDetectionProcessingBatchTask: ProcessingTask, ObservableObject {
//    let id = UUID()
//    let title: String
//    @Published var state: ProcessingTaskState = .pending
//    @Published var progress: Double = 0.0
//    @Published var statusMessage: String = "Pending"
//
//    // Array of full-resolution image paths to process.
//    let fullResPaths: [String]
//
//    // Internal cancellation flag.
//    private var isCancelled = false
//
//    init(title: String, fullResPaths: [String]) {
//        self.title = title
//        self.fullResPaths = fullResPaths
//    }
//
//    var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
//        $state.eraseToAnyPublisher()
//    }
//    var progressPublisher: AnyPublisher<Double, Never> {
//        $progress.eraseToAnyPublisher()
//    }
//    var statusMessagePublisher: AnyPublisher<String, Never> {
//        $statusMessage.eraseToAnyPublisher()
//    }
//
//    func start() async {
//        // Only start if pending or paused.
//        guard state == .pending || state == .paused else { return }
//
//        await MainActor.run {
//            self.state = .running
//            self.statusMessage = "Starting batch ball detection..."
//            self.progress = 0.0
//        }
//
//        do {
//            try await Task.detached(priority: .background) { [weak self] in
//                guard let self = self else { return }
//
//                let totalFrames = self.fullResPaths.count
//
//                for (frameIndex, path) in self.fullResPaths.enumerated() {
//                    if self.isCancelled { break }
//
//                    // Load the image from the given path.
//                    guard let image = UIImage(contentsOfFile: path) else {
//                        await MainActor.run {
//                            self.statusMessage = "Failed to load image at \(path)"
//                        }
//                        continue
//                    }
//
//                    // Update status for the current frame.
//                    await MainActor.run {
//                        self.statusMessage = "Processing image \(frameIndex + 1) of \(totalFrames)"
//                    }
//
//                    // Create a constant binding for the current frame ID.
//                    let frameIDBinding = Binding<String>(
//                        get: { path },
//                        set: { _ in }
//                    )
//
//                    // Instantiate a barebones Ball Detection module via the factory.
//                    guard let factory = AnnotationModules.availableModules["Ball Detection"] else { continue }
//                    let module = factory(
//                        DetectionDrawerManager(),  // Provide a shared or new instance as appropriate.
//                        .constant(false),           // No UI drawer needed.
//                        frameIDBinding,
//                        image
//                    )
//
//                    if let ballModule = module as? BallDetectionModule {
//                        // This call will process the entire frame (it handles ROI calculation internally).
//                        ballModule.processEntireFrame()
//                    }
//
//                    // Update overall progress.
//                    await MainActor.run {
//                        self.progress = Double(frameIndex + 1) / Double(totalFrames)
//                    }
//                }
//
//                // Final updates once all frames have been processed.
//                await MainActor.run {
//                    self.progress = 1.0
//                    self.state = self.isCancelled ? .failed : .completed
//                    self.statusMessage = self.isCancelled ? "Cancelled" : "Batch processing completed."
//                }
//            }.value
//        } catch {
//            await MainActor.run {
//                self.state = .failed
//                self.statusMessage = "Processing failed: \(error.localizedDescription)"
//            }
//        }
//    }
//
//    func pause() {
//        if state == .running {
//            state = .paused
//            statusMessage = "Paused"
//        }
//    }
//
//    func resume() {
//        if state == .paused {
//            state = .running
//            statusMessage = "Resumed"
//        }
//    }
//
//    func cancel() {
//        isCancelled = true
//        state = .failed
//        statusMessage = "Cancelled"
//    }
//}
