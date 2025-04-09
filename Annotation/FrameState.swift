import SwiftUI
import SwiftData
import Combine

// MARK: - FrameState
/// A central source for current frame state, including the current frame UUID,
/// the loaded image, and the list of frames for navigation.
///
extension FrameState {
    convenience init() {
        self.init(modelContext: nil, projectUUID: nil, selectedFrameUUID: nil)
    }
}


//FIXME: Add Main Actor @MainActor to enforce all to main thread?
class FrameState: ObservableObject {
    @Published var refreshToken: UUID = UUID()
    @Published var toolRenderOverlayRefreshToken: UUID = UUID()
    
    //Frame Annotations
    @Published public var ballDetections: [BallDetection] = []
    @Published public var courtDetections: [CourtDetection] = []
    //    public var playerAnnotations = []
    
    @Published public var compositeFrames: [CompositeFrameItem] = []
    @Published public var selectedAnnotationUUID = UUID()
    @Published var annotationsAtTapLocation: [UUID] = []
    @Published var previousAnnotationsAtTapLocation: [UUID] = []
    
    private var projectUUID: UUID?
    @Published var projectDir:URL? = nil
    @Published var currentFrameUUID: UUID? {
        didSet {
            print("FrameState: Updated currentFrameUUID to \(String(describing: currentFrameUUID))")
            loadCurrentImage()
            Task {
                await globalDataRefresh()  // or await loadBallDetections() if you prefer
            }
        }
    }
    
    private var modelContext: ModelContext?
    @Published var currentImage: UIImage?
    @Published var frames: [Frame] = []
    
    init(
        modelContext: ModelContext? = nil,
        projectUUID: UUID? = nil,
        selectedFrameUUID: UUID? = nil
    ) {
        self.modelContext = modelContext
        self.projectUUID = projectUUID
        self.currentFrameUUID = selectedFrameUUID
        
        //Loaded Data
        self.currentImage = nil
        self.frames = []
    }
    
    @MainActor
    func configure(
        modelContext: ModelContext,
        projectUUID: UUID
//        currentFrameUUID: UUID
    ) async {
        self.modelContext = modelContext
        self.projectUUID = projectUUID
//        self.currentFrameUUID = currentFrameUUID
        
        await loadFrames()
        loadCurrentImage()
        await loadProjectInfo()
    }
    
    var safeContext: ModelContext {
        guard let context = modelContext else {
            fatalError("❌ FrameState.safeContext: modelContext is nil — must be configured before use.")
        }
        return context
    }
    
    /// Advances to the next frame if possible.
    func nextFrame() async {
        await MainActor.run {
            if let currentIndex = frames.firstIndex(where: { $0.id == currentFrameUUID }),
               currentIndex < frames.count - 1 {
                currentFrameUUID = frames[currentIndex + 1].id
            }
        }
        await globalDataRefresh()
    }

    func prevFrame() async {
        await MainActor.run {
            if let currentIndex = frames.firstIndex(where: { $0.id == currentFrameUUID }),
               currentIndex > 0 {
                currentFrameUUID = frames[currentIndex - 1].id
            }
        }
        await globalDataRefresh()
    }
    
    func triggerRefresh() async {
        await MainActor.run {
            self.refreshToken = UUID()
        }
    }
    
    func loadProjectInfo() async {
        guard let modelContext = modelContext,
              let projectUUID  = projectUUID else { return }

        let fetchDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectUUID }
        )

        do {
            let projects = try modelContext.fetch(fetchDescriptor)
            guard let project = projects.first else { return }

            // 🟢 Build a *current‑container* URL for this project
            let projectDirURL = FilePathResolver
                .resolveURL(for: project.name)          //  <-- now using your helper

            // Make sure it exists (first launch in a fresh sandbox, etc.)
            try? FileManager.default.createDirectory(at: projectDirURL,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)

            await MainActor.run {
                self.projectDir = projectDirURL         // <- always up‑to‑date
            }

        } catch {
            print("FrameState: unable to load project info: \(error)")
        }
    }
    
    
    func loadFrames() async {
        guard let modelContext, let projectUUID else {
            print("FrameState: Missing modelContext or projectUUID. Cannot load frames.")
            return
        }
        
        let fetchDescriptor = FetchDescriptor<Frame>(
            predicate: #Predicate { $0.project.id == projectUUID }
        )
        
        do {
            let fetchedFrames = try modelContext.fetch(fetchDescriptor)
            let sortedFrames = fetchedFrames.sorted { $0.frameName < $1.frameName }
            await MainActor.run {
                self.frames = sortedFrames
            }
            
            print("FrameState: Loaded and sorted \(frames.count) frames")
        } catch {
            print("FrameState: Error fetching frames: \(error)")
        }
    }
    
    func loadCurrentImage() {
        guard let modelContext, let currentFrameUUID else {
            print("FrameState: Cannot load image — modelContext or currentFrameUUID is nil.")
            DispatchQueue.main.async { self.currentImage = nil }
            return
        }
        
        print("FrameState: Loading image for frame UUID: \(currentFrameUUID)")
        
        let fetchDescriptor = FetchDescriptor<Frame>(
            predicate: #Predicate { $0.id == currentFrameUUID }
        )
        
        do {
            let fetchedFrames = try modelContext.fetch(fetchDescriptor)
            if let frame = fetchedFrames.first, let path = frame.imagePath {
                let resolvedPath = FilePathResolver.resolveFullPath(for: path)
                if FileManager.default.fileExists(atPath: resolvedPath),
                   let image = UIImage(contentsOfFile: resolvedPath) {
//                    print("Loaded image size: \(image.size)")
                    DispatchQueue.main.async {
                        self.currentImage = image
                        print("FrameState: Image loaded successfully for frame \(frame.frameName)")
                    }
                } else {
                    DispatchQueue.main.async { self.currentImage = nil }
                    print("FrameState: Failed to load image from path: \(resolvedPath)")
                }
            } else {
                DispatchQueue.main.async { self.currentImage = nil }
                print("FrameState: No frame found with UUID: \(currentFrameUUID)")
            }
        } catch {
            DispatchQueue.main.async { self.currentImage = nil }
            print("FrameState: Error loading image: \(error)")
        }
    }
    
    
    // MARK: - FrameState Queue
    protocol FrameStateTask {
        var priority: Int { get } // Optional
        func execute(in frameState: FrameState) async
    }
    

    
    struct InsertCourtDetectionTask: FrameStateTask {
        var priority: Int = 0
        
        let detection: CourtDetection

        func execute(in frameState: FrameState) async {
            frameState.safeContext.insert(detection)
            try? frameState.safeContext.save()
//            await frameState.globalDataRefresh() // or a general `refresh()` method
        }
    }
    
    private var taskQueue = [FrameStateTask]()
        private var isProcessingQueue = false

        func enqueue(_ task: FrameStateTask) {
            taskQueue.append(task)
            processNext()
        }
    
    private func processNext() {
        guard !isProcessingQueue else { return }

        if taskQueue.isEmpty {
            Task { await globalDataRefresh() }
            return
        }

        // Sort the queue so highest priority goes first
        taskQueue.sort { $0.priority > $1.priority }

        isProcessingQueue = true
        let task = taskQueue.removeFirst()

        Task {
            await task.execute(in: self)
            isProcessingQueue = false
            processNext()
        }
    }
    
    func globalDataRefresh() async {
        print("🔄 FrameState: Global data refresh triggered.")

        await loadBallDetections()
//        await loadCourtDetections()
//        await reloadOtherModels()

        await triggerRefresh() // View-bound UUID update, if needed
    }

    func loadCourtDetections() async {
        guard let frameUUID = currentFrameUUID else {
            print("⚠️ loadCourtDetections: No currentFrameUUID available")
            return
        }
        
        let descriptor = FetchDescriptor<CourtDetection>(
            predicate: #Predicate { $0.frameUUID == frameUUID }
        )
        
        do {
            let results = try safeContext.fetch(descriptor)
            if let existingDetection = results.first {
                await MainActor.run {
                    self.courtDetections = results
                    print("✅ Loaded \(results.count) court detections for frame \(frameUUID)")
                }
            } else {
                // No detection exists for this frame: create a new one.
                let newDetection = CourtDetection(frameUUID: frameUUID)
                safeContext.insert(newDetection)
                // Save the new detection to persist it.
                try safeContext.save()
                await MainActor.run {
                    self.courtDetections = [newDetection]
                    print("✅ Created a new court detection for frame \(frameUUID)")
                }
            }
        } catch {
            print("❌ Error loading court detections: \(error)")
        }
    }
    
    
    func addCourtDetection(_ detection: CourtDetection) {
        guard let frameUUID = currentFrameUUID else {
            print("⚠️ addCourtDetection: No currentFrameUUID available")
            return
        }
        
        enqueue(InsertCourtDetectionTask(detection: detection))
    }


}
