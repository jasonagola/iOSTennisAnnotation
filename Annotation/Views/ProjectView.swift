//
//  ProjectView.swift
//  Annotation
//
//  Created by Jason Agola on 1/9/25.
//

import SwiftUI
import SwiftData
import Combine

struct FrameIndex: Identifiable {
    let id = UUID() // Unique identifier
    let index: Int
}

final class ProjectViewModel: ObservableObject {
    var modelContext: ModelContext
    @Published var project: Project?
    @Published var frames: [Frame] = []
    @Published var projectName: String = ""
    
    let projectUUID: UUID

    init(projectUUID: UUID, modelContext: ModelContext) {
        self.projectUUID = projectUUID
        self.modelContext = modelContext
        loadProject()
    }
    
    func loadProject() {
        let fetchDescriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectUUID })
        do {
            let projects = try modelContext.fetch(fetchDescriptor)
            if let project = projects.first {
                self.project = project
                self.projectName = project.name
                loadFrames()
            }
        } catch {
            print("Error loading project: \(error)")
        }
    }
    
    func loadFrames() {
        guard let project = project else { return }
        let targetProjectID: UUID = project.id  // Capture the ID as a constant
        
        print("Load Frames Target Project ID: \(targetProjectID)")
        let fetchDescriptor = FetchDescriptor<Frame>(
            predicate: #Predicate { (frame: Frame) -> Bool in
                frame.project.id == targetProjectID
            }
        )
        do {
            let fetchedFrames = try modelContext.fetch(fetchDescriptor)
            self.frames = fetchedFrames.sorted { $0.frameName < $1.frameName }
        } catch {
            print("Error loading frames: \(error)")
        }
    }
}

struct ProjectView: View {
    private var modelContext: ModelContext
    @EnvironmentObject var frameState: FrameState
    @StateObject private var viewModel: ProjectViewModel
    @ObservedObject var queueManager: ProcessingQueueManager
    @State private var didConfigure = false

    // Instead of a separate UUID, we use the selected Frame.
    @State private var selectedFrame: Frame? = nil
    @State private var selectedIndex: Int = 0

    // Controls for full‑screen overlays
    @State private var isAnnotationModeActive: Bool = false
    @State private var isBatchProcessingActive: Bool = false

    init(projectUUID: UUID, queueManager: ProcessingQueueManager, modelContext: ModelContext) {
        self.queueManager = queueManager
        self.modelContext = modelContext
        _viewModel = StateObject(wrappedValue: ProjectViewModel(projectUUID: projectUUID, modelContext: modelContext))
    }
    
    var body: some View {
        VStack {
            headerView

            Divider()

            if viewModel.frames.isEmpty {
                Text("No images found in this project.")
                    .font(.headline)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 16) {
                        ForEach(Array(viewModel.frames.enumerated()), id: \.element.id) { index, frame in
                            Button(action: {
                                selectedIndex = index
                                selectedFrame = frame
                            }) {
                                VStack {
                                    if let thumbnail = frame.thumbnail {
                                        Image(uiImage: thumbnail)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 120, height: 120)
                                            .border(Color.gray, width: 1)
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 120, height: 120)
                                    }
                                    Text(cleanImageFilename(from: frame.thumbnailPath ?? ""))
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            
            Button("Batch Process Tasks") {
                isBatchProcessingActive = true
            }
            .padding()
        }
        .onAppear {
            viewModel.loadProject()
        }
        .onAppear {
            if !didConfigure {
                Task {
                    await frameState.configure(
                        modelContext: modelContext,
                        projectUUID: viewModel.projectUUID
                    )
                }
                didConfigure = true
            }
        }
        .navigationTitle("Project Details")
        // When a frame is selected, show its details.
        .fullScreenCover(item: $selectedFrame) { frame in
            FrameDetailView(frames: viewModel.frames, selectedIndex: $selectedIndex)
        }
        // Full screen cover for annotation mode.
        .fullScreenCover(isPresented: $isAnnotationModeActive) {
            // Use the selected frame's id if available; otherwise, fallback to first frame's id
            if let frame = selectedFrame ?? viewModel.frames.first {
                AnnotationModeView(
                    projectUUID: viewModel.projectUUID,
                    modelContext: modelContext,
                    selectedFrameUUID: frame.id
                )
            } else {
                // Handle the case where no frame is available
                Text("No frame selected")
            }
        }
        .fullScreenCover(isPresented: $isBatchProcessingActive) {
            NavigationView {
                BatchProcessingSelectionView(
                    projectName: viewModel.projectName,
                    projectUUID: viewModel.projectUUID,
                    queueManager: queueManager,
                    fullResPaths: viewModel.frames.compactMap { $0.imagePath }
                )
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Project Name: \(viewModel.projectName)")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: {
                    // When annotation mode is tapped, update selectedFrame if needed.
                    // You might choose to update the FrameState there.
                    isAnnotationModeActive = true
                }) {
                    Text("Annotation Mode")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            Text("Total Frames: \(viewModel.frames.count)")
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.2))
    }
    
    // MARK: - Helpers
    private func cleanImageFilename(from thumbnailPath: String) -> String {
        let url = URL(fileURLWithPath: thumbnailPath)
        let baseName = url.deletingPathExtension().lastPathComponent
        return baseName.replacingOccurrences(of: "_thumbnail", with: "")
    }
}

// MARK: - FrameDetailView Example
struct FrameDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let frames: [Frame]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var isAnnotationModeActive = false

    var body: some View {
        VStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                    VStack {
                        Text("Frame: \(frame.frameName)")
                            .font(.headline)
                            .padding(.top)
                        if let image = frame.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        } else {
                            Text("No image available.")
                                .padding()
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .automatic))

            HStack {
                Button(action: {
                    isAnnotationModeActive = true
                }) {
                    Text("Annotation Mode")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $isAnnotationModeActive) {
            let frame = frames[selectedIndex]
            AnnotationModeView(projectUUID: frame.project.id, modelContext: modelContext, selectedFrameUUID: frame.id)
        }
    }
}


// Helper function remains the same.
private func cleanImageFilename(from thumbnailPath: String) -> String {
    let url = URL(fileURLWithPath: thumbnailPath)
    let baseName = url.deletingPathExtension().lastPathComponent
    return baseName.replacingOccurrences(of: "_thumbnail", with: "")
}

struct BatchProcessingSelectionView: View {
    let projectName: String
    let projectUUID: UUID
    @ObservedObject var queueManager: ProcessingQueueManager
    @Environment(\.modelContext) private var modelContext
    
    // A dictionary of task names and whether they're selected.
    @State private var selectedTasks: [String: Bool] = [
        "Ball Detection": false,
        "Build Composite Video": false
        // Add additional tasks as needed.
    ]
    
    // Reference to your project's full resolution image paths.
    let fullResPaths: [String]
    
    // Environment dismiss value.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            List {
                ForEach(selectedTasks.keys.sorted(), id: \.self) { key in
                    Toggle(key, isOn: Binding(
                        get: { selectedTasks[key] ?? false },
                        set: { newValue in selectedTasks[key] = newValue }
                    ))
                }
            }
            .listStyle(.plain)
            
            Button("Run Batch Processing") {
                runBatchProcessing(projectUUID: projectUUID)
                dismiss() // Dismiss the view after queuing tasks.
            }
            .padding()
        }
        .navigationTitle("Batch Processing Tasks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
    
    func runBatchProcessing(projectUUID: UUID) {
//        Commmented Out During Refactor
        if selectedTasks["Ball Detection"] ?? false {
            let task = BallDetectionProcessingBatchTask(projectUUID: projectUUID, modelContext: modelContext)
            queueManager.add(task: task)
        }
        if selectedTasks["Build Composite Video"] ?? false {
            let task = CompositeVideoRenderingTask(projectUUID: projectUUID, modelContext: modelContext)
            queueManager.add(task: task)
        }
    }
}

final class BallDetectionProcessingBatchTask: ProcessingTask, ObservableObject {
    let id = UUID()
    let title = "Ball Detection"

    @Published var state: ProcessingTaskState = .pending
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Pending"

    private let projectUUID: UUID
    private let modelContext: ModelContext
    private var isCancelled = false

    // Initialize with the project ID and model context.
    init(projectUUID: UUID, modelContext: ModelContext) {
        self.projectUUID = projectUUID
        self.modelContext = modelContext
    }

    // Publishers for state, progress, and statusMessage.
    var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
        $state.eraseToAnyPublisher()
    }
    var progressPublisher: AnyPublisher<Double, Never> {
        $progress.eraseToAnyPublisher()
    }
    var statusMessagePublisher: AnyPublisher<String, Never> {
        $statusMessage.eraseToAnyPublisher()
    }

    // MARK: - ProcessingTask Methods
    //FIXME: Rapidly reassigning can cause data leaks 
    func start() async {
        await MainActor.run {
            self.state = .running
            self.statusMessage = "Starting batch detection..."
            self.progress = 0.0
        }

        // Create a FrameState and configure it.
        // First, initialize FrameState with available context.
        let frameState = FrameState(modelContext: modelContext, projectUUID: projectUUID, selectedFrameUUID: nil)
        // Load frames (if not already loaded via configure).
        await frameState.loadFrames()

        guard let firstFrame = frameState.frames.first else {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "No frames available for processing."
            }
            return
        }

        // Configure the FrameState with the first frame.
        await frameState.configure(modelContext: modelContext, projectUUID: projectUUID)

        let totalFrames = frameState.frames.count

        // Process each frame sequentially.
        for (index, frame) in frameState.frames.enumerated() {
            if isCancelled { break }

            // Update the FrameState's current frame.
            await MainActor.run {
                frameState.currentFrameUUID = frame.id
            }
            // The didSet on currentFrameUUID will trigger loadCurrentImage() and data refresh.

            // Wait for the image to be loaded.
            while frameState.currentImage == nil && !isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000_000) // 0.1 second delay.
            }
            if isCancelled { break }

            guard let image = frameState.currentImage else { continue }

            // Instantiate a BallDetectionModule using your factory.
            guard let factory = AnnotationModules.availableModules["Ball Detection"] else {
                continue
            }
            let module = await factory(
                modelContext,
                DetectionDrawerManager(),
                .constant(false),
                frameState
            )

            if let ballModule = module as? BallDetectionModule {
                // Process the entire frame (this should handle ROI internally).
                ballModule.processEntireFrame()
            }

            // Update progress and status.
            await MainActor.run {
                self.progress = Double(index + 1) / Double(totalFrames)
                self.statusMessage = "Processed frame \(index + 1) of \(totalFrames)"
            }
        }

        await MainActor.run {
            if isCancelled {
                self.state = .failed
                self.statusMessage = "Batch processing cancelled."
            } else {
                self.state = .completed
                self.statusMessage = "Batch processing completed."
                self.progress = 1.0
            }
        }
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

    func cancel() {
        isCancelled = true
        Task {
            await MainActor.run {
                self.state = .failed
                self.statusMessage = "Cancelled"
            }
        }
    }
}
