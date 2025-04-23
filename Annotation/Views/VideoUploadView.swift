//
//  VideoUploadView.swift
//  Annotation
//
//  Created by Jason Agola on 1/9/25.
//

import SwiftUI
import SwiftData
import AVKit
import PhotosUI
import Combine
import UniformTypeIdentifiers

extension UIImage {
    func thumbnail(toMaxDimension maxDimension: CGFloat) -> UIImage? {
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
}

struct VideoUploadView: View {
    // Task Manager
    @ObservedObject var queueManager: ProcessingQueueManager
    @Environment(\.modelContext) private var modelContext
    
    // For PhotosPicker
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    // AV-related
    @State private var player: AVPlayer?
    
    // Video URL & AVAsset
    @State private var videoURL: URL?
    @State private var avAsset: AVAsset?
    
    // Metadata
    @State private var resolution: CGSize = .zero
    @State private var frameRate: Float = 0
    @State private var duration: Double = 0
    @State private var creationDate: Date?
    
    // Document picker
    @State private var showDocumentPicker = false
    
    // Project Name
    @State private var projectName: String = ""
    
    // Frame parsing
    @State private var frameSkipString: String = "1"  // UI text for the skip number
    @State private var isParsingFrames: Bool = false  // Whether we are in the middle of parsing
    @State private var parseMessage: String = ""      // A status message
    @State private var parseProgress: Double = 0.0      // 0...1 for progress bar
    
    // Enqueue confirmation and navigation to queue view.
    @State private var showEnqueueConfirmation = false
    @State private var navigateToProcessingQueue = false
    
    // Validation Alerts
//    @State private var isProjectNameValid: Bool = false\
    @State private var projectNameError: String? = nil
    
    @State private var projects: [Project] = []
    
//    init(queueMananger: ProcessingQueueManager) {
//        self.queueManager = queueManager
//    }
    
    private func validateProjectName(_ name: String) -> Bool {
        // Ensure non-empty and trim whitespace.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        
        let existingProjects = loadProjectNames()
        // Check for a duplicate, assuming project names are case-insensitive
        let duplicateExists = existingProjects.contains { $0.name.lowercased() == trimmedName.lowercased() }
        return !duplicateExists
    }

    
    private func loadProjectNames() -> [Project] {
        let fetchDescriptor = FetchDescriptor<Project>()
        do {
            let loadedProjects = try modelContext.fetch(fetchDescriptor)
            self.projects = loadedProjects.sorted { $0.name < $1.name }
            return projects
        } catch {
            print("Error fetching projects: \(error)")
            return [] // Returning an empty array in case of error
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // MARK: - Top: Video (AVPlayer)
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 300)
                        .onAppear {
                            // Autoplay if desired
                            player.play()
                        }
                } else {
                    // Placeholder if no video is selected
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 300)
                        .overlay(
                            Text("No video selected")
                                .foregroundColor(.gray)
                        )
                }
                
                // MARK: - Inline PhotosPicker for videos
                PhotosPicker("Select Video from Photo Library",
                             selection: $selectedPhotoItem,
                             matching: .videos)
                .padding(.top, 16)
                .onChange(of: selectedPhotoItem) { newItem in
                    Task {
                        guard let newItem else { return }
                        do {
                            // Load the video data
                            if let data = try await newItem.loadTransferable(type: Data.self) {
                                // Write it to a temporary file
                                let tmpURL = FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString)
                                    .appendingPathExtension("mov")
                                try data.write(to: tmpURL, options: .atomic)
                                
                                // Update state
                                videoURL = tmpURL
                                avAsset = AVURLAsset(url: tmpURL)
                                
                                // Create the player
                                player = AVPlayer(url: tmpURL)
                                
                                // Load metadata
                                await loadMetadata()
                            }
                        } catch {
                            print("Error loading video from PhotosPicker: \(error)")
                        }
                    }
                }
                
                // MARK: - Documents button (sheet)
                Button("Select Video from Documents") {
                    showDocumentPicker = true
                }
                .padding(.top, 16)
                .sheet(isPresented: $showDocumentPicker) {
                    DocumentPickerView { urls in
                        if let url = urls?.first {
                            // Update state
                            videoURL = url
                            avAsset = AVURLAsset(url: url)
                            
                            // Create player
                            player = AVPlayer(url: url)
                            
                            // Load metadata
                            Task {
                                await loadMetadata()
                            }
                        }
                    }
                }
                
                // MARK: - If video is loaded, show project & parsing tools
                if avAsset != nil {
                    projectAndParsingTools
                }
                
                // MARK: - NavigationLink to ProcessingQueueView
                NavigationLink(destination: ProcessingQueueView(queueManager: queueManager),
                               isActive: $navigateToProcessingQueue) {
                    EmptyView()
                }
                
                // MARK: - Spacer
                Spacer()
            }
            .padding()
            .alert("Enqueue Parse Task", isPresented: $showEnqueueConfirmation) {
                Button("Enqueue", role: .destructive) {
                    enqueueTask()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to enqueue this parse task?")
            }
        }
    }
    
    // MARK: - Project & Parsing Tools
    @ViewBuilder
    private var projectAndParsingTools: some View {
        // Project Name Input
        VStack(alignment: .leading, spacing: 8) {
            Text("Project Name:")
                .font(.headline)
            TextField("MyProject", text: $projectName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: projectName) { newValue in
                    // Update the error message in real time.
                    if !validateProjectName(newValue) {
                        projectNameError = "Project name already exists or is invalid."
                    } else {
                        projectNameError = nil
                    }
                }
            
            // Display error message if exists.
            if let error = projectNameError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        
        // Loaded Metadata Section
        metadataSection
        
        // Frame Skip + Estimated Frames
        let totalFrameCount = Int(Double(frameRate) * duration)
        let skipCount = Int(frameSkipString) ?? 1
        let estimatedFrameCount = max((totalFrameCount / max(skipCount, 1)), 0)
        
        HStack {
            Text("Skip frames:")
            // FIXME: Can't View options when keyboard is loaded
            TextField("2", text: $frameSkipString)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Text("Estimated: \(estimatedFrameCount) frames")
                .foregroundColor(.gray)
        }
        .padding(.top, 16)
        
        // Parse Frames Button & Progress
        HStack {
            // Button to trigger confirmation modal.
            Button("Enqueue Parse Task") {
                showEnqueueConfirmation = true
            }
            .disabled(!validateProjectName(projectName)) // Disable if validation fails.
            .padding()
            .cornerRadius(8)
            .foregroundColor(.white)
            .background(!validateProjectName(projectName) ? Color.gray : Color.blue)
            
            Spacer()
            
            // Show a progress bar if parsing
            if isParsingFrames {
                VStack {
                    ProgressView(value: parseProgress, total: 1.0)
                        .frame(width: 150)
                    Text("Progress: \(Int(parseProgress * 100))%")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.top, 16)
        
        // Parsing status message
        if !parseMessage.isEmpty {
            Text(parseMessage)
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
    }
    
    // MARK: - Metadata Section View
    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata:")
                .font(.headline)
            
            Text("Resolution: \(Int(resolution.width)) x \(Int(resolution.height))")
            Text("Frame Rate: \(frameRate, specifier: "%.2f") fps")
            Text("Duration: \(duration, specifier: "%.2f") seconds")
            
            if let date = creationDate {
                Text("Creation Date: \(date.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Creation Date: N/A")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
        .padding(.top, 16)
    }
    
    // MARK: - Enqueue Task Logic
    private func enqueueTask() {
        // Re-check validation before proceeding.
        guard validateProjectName(projectName) else {
            parseMessage = "Project name already exists or is invalid."
            return
        }
        
        guard let asset = avAsset,
              let skipCount = Int(frameSkipString),
              skipCount > 0 else {
            parseMessage = "Invalid asset or skip count."
            return
        }
        
        isParsingFrames = true
        parseMessage = "Enqueuing task..."
        
        let task = VideoProcessingTask(modelContext: modelContext,
                                       title: projectName,
                                       asset: asset,
                                       projectName: projectName,
                                       frameSkip: skipCount)
        queueManager.add(task: task)
        
        parseMessage = "Task enqueued!"
        isParsingFrames = false
        
        // Navigate to ProcessingQueueView after enqueuing.
        navigateToProcessingQueue = true
    }
    
    // MARK: - Load Metadata (Async/Await)
    private func loadMetadata() async {
        guard let avAsset = avAsset else { return }
        
        do {
            // Load tracks and duration first
            _ = try await avAsset.load(.tracks)
            let loadedDuration = try await avAsset.load(.duration)
            duration = loadedDuration.seconds
            
            // Get first video track for resolution & frame rate
            let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
            if let track = videoTracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                resolution = size.applying(transform)
                
                frameRate = try await track.load(.nominalFrameRate)
            }
            
            // Load creation date from metadata
            let allMetadata = try await avAsset.load(.metadata)
            if let creationDateMetadata = allMetadata.first(where: {
                $0.identifier == .quickTimeMetadataCreationDate
            }) {
                creationDate = try await creationDateMetadata.load(.dateValue)
            }
            
        } catch {
            print("Error loading AVAsset properties: \(error)")
        }
    }
    
    // MARK: - DocumentPickerView
    struct DocumentPickerView: UIViewControllerRepresentable {
        var onSelectURLs: ([URL]?) -> Void
        
        func makeCoordinator() -> Coordinator {
            Coordinator(onSelectURLs: onSelectURLs)
        }
        
        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let types = [UTType.movie, UTType.video]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.allowsMultipleSelection = false
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }
        
        class Coordinator: NSObject, UIDocumentPickerDelegate {
            var onSelectURLs: ([URL]?) -> Void
            
            init(onSelectURLs: @escaping ([URL]?) -> Void) {
                self.onSelectURLs = onSelectURLs
            }
            
            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                onSelectURLs(urls)
            }
            
            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                onSelectURLs(nil)
            }
        }
    }
    
    final class FrameBuffer {
        private var buffer: [Int: UIImage] = [:]
        private var accessOrder: [Int] = []
        private let maxSize: Int

        init(maxSize: Int = 10) {
            self.maxSize = maxSize
        }

        // Adds an image to the buffer under a unique index.
        // Note: Auto-deletion is removed; you'll need to manually call remove(_:) as appropriate.
        func set(_ index: Int, image: UIImage) {
            buffer[index] = image
            accessOrder.append(index)
        }

        // Retrieves an image from the buffer for the specified index.
        func get(_ index: Int) -> UIImage? {
            return buffer[index]
        }

        // Checks if the buffer contains an image for the given index.
        func contains(_ index: Int) -> Bool {
            return buffer[index] != nil
        }

        // Removes the image for the specified index, ensuring that the access order is updated.
        func remove(_ index: Int) {
            buffer.removeValue(forKey: index)
            accessOrder.removeAll { $0 == index }
        }

        // Clears the entire buffer.
        func clear() {
            buffer.removeAll()
            accessOrder.removeAll()
        }
        
        // Provides the current count of stored frames.
        var currentCount: Int {
            return buffer.count
        }
    }
    
    // MARK: - VideoProcessingTask
    final class VideoProcessingTask: ProcessingTask {
        let id = UUID()
        let title: String
        @Published var state: ProcessingTaskState = .pending
        @Published var progress: Double = 0.0
        @Published var statusMessage: String = "Pending"
        
        var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
            $state.eraseToAnyPublisher()
        }
        var progressPublisher: AnyPublisher<Double, Never> {
            $progress.eraseToAnyPublisher()
        }
        var statusMessagePublisher: AnyPublisher<String, Never> {
            $statusMessage.eraseToAnyPublisher()
        }
        
        // Video processing configuration
        private let modelContext: ModelContext
        private let avAsset: AVAsset
        private let projectName: String
        private let frameSkip: Int
        
        // Internal properties
        private var isCancelled = false
        
        // Our frame buffer (shared in-memory cache) with a max capacity.
        private let frameBuffer = FrameBuffer(maxSize: 10)
        
        // A dedicated queue for disk writing tasks.
        private let diskWriteQueue = DispatchQueue(label: "com.myapp.diskWriteQueue", qos: .background)
        
        init(modelContext: ModelContext, title: String, asset: AVAsset, projectName: String, frameSkip: Int) {
            self.modelContext = modelContext
            self.title = title
            self.avAsset = asset
            self.projectName = projectName
            self.frameSkip = max(frameSkip, 1)
        }
        
        func start() async {
            // Ensure we are in a valid starting state.
            guard state == .pending || state == .paused else { return }
            
            await MainActor.run {
                self.state = .running
                self.statusMessage = "Starting processing..."
            }
            
            do {
                // Load video metadata.
                let videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                let frameRate = try await videoTracks.first?.load(.nominalFrameRate) ?? 30.0
                let durationSeconds = (try await avAsset.load(.duration)).seconds
                let totalFrameCount = Int(Double(frameRate) * durationSeconds)
                
                guard totalFrameCount > 0 else {
                    await MainActor.run {
                        self.state = .failed
                        self.statusMessage = "No frames to process."
                    }
                    return
                }
                
                // Add/Update Project in Data Model.
                let modelContext = self.modelContext
                let targetName = projectName // local copy for consistency
                let projectDir = try createProjectDirectory(named: projectName)
                
                let fetchDescriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.name == targetName }
                )
                let existingProjects = try modelContext.fetch(fetchDescriptor)
                let project: Project
                if let existingProject = existingProjects.first {
                    project = existingProject
                } else {
                    project = Project(name: projectName, projectDir: projectDir)
                    modelContext.insert(project)
                    try modelContext.save()
                }
                
                // Create the thumbnails directory.
                let thumbnailsDir = projectDir.appendingPathComponent("thumbnails", isDirectory: true)
                try FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
                
                // Initialize the image generator.
                let imageGenerator = AVAssetImageGenerator(asset: avAsset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.requestedTimeToleranceBefore = .zero
                imageGenerator.requestedTimeToleranceAfter = .zero
                
                // Collect the frame times.
                var times = [CMTime]()
                for frameIndex in stride(from: 0, to: totalFrameCount, by: frameSkip) {
                    let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))
                    times.append(time)
                }
                
                var annotations: [String: Any] = [:]
                let total = times.count
                
                // Main processing loop; running on a background Task.
                try await Task(priority: .background) { [weak self] in
                    print("Starting Background Video Processing Tasks....")
                    guard let self = self else { return }
                    
                    for (i, time) in times.enumerated() {
                        
                        // Check for cancellation.
                        if self.isCancelled { break }
                        
                        // Rate limit: if the buffer count is at or above max, pause processing.
                        while self.frameBuffer.currentCount >= 10 {
                            try await Task.sleep(nanoseconds: 10_000_000) // 10 milliseconds
                        }
                        // Update progress on the main thread.
                        Task { @MainActor in
                            self.progress = Double(i) / Double(total)
                            self.statusMessage = "Processing frame \(i + 1) of \(total)"
                        }
                        
                        // Extract frame using an autoreleasepool.
                        let extractedFrame: Frame? = autoreleasepool { () -> Frame? in
                            do {
                                // 1. Extract the CGImage at the given time.
                                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                                let uiImage = UIImage(cgImage: cgImage)

                                // 2. Check for duplicate using the frameBuffer entry (e.g., previous frame).
                                if let previousImage = self.frameBuffer.get(i - 1),
                                   uiImage.pngData() == previousImage.pngData() {
                                    print("Skipping duplicate frame \(i) based on buffer comparison")
                                    return nil
                                }
                                
                                // 3. Save the newly extracted frame in the frameBuffer.
                                self.frameBuffer.set(i, image: uiImage)
                                
                                // 4. Compute file names and URLs *synchronously*.
                                let frameName = String(format: "frame_%05d.jpg", i + 1)
                                let fileURL = projectDir.appendingPathComponent(frameName)
                                let thumbnailName = String(format: "frame_%05d_thumbnail.jpg", i + 1)
                                let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailName)
                                
                                // 5. Dispatch disk writes asynchronously.
                                self.diskWriteQueue.async {
                                    // Full-size image write.
                                    if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                                        do {
                                            try jpegData.write(to: fileURL, options: .atomic)
                                            print("Saved full image to \(fileURL.path)")
                                        } catch {
                                            print("Error writing full image: \(error)")
                                        }
                                    } else {
                                        print("Failed to create JPEG data for full image.")
                                    }
                                    
                                    // Thumbnail write.
                                    if let thumbnail = uiImage.thumbnail(toMaxDimension: 128),
                                       let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                                        do {
                                            try thumbnailData.write(to: thumbnailURL, options: .atomic)
                                            print("Saved thumbnail to \(thumbnailURL.path)")
                                        } catch {
                                            print("Error writing thumbnail: \(error)")
                                        }
                                    } else {
                                        print("Thumbnail generation failed for frame \(i)")
                                    }
                                    
                                    // Once disk writes are complete, remove the frame from the buffer.
                                    DispatchQueue.main.async {
                                        self.frameBuffer.remove(i)
                                    }
                                }
                                
                                // 6. Compute relative file paths (this can be done immediately since fileURL and thumbnailURL are known).
                                guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                                    print("Could not access the Documents directory.")
                                    return nil
                                }
                                let relativeImagePath = fileURL.path.replacingOccurrences(of: docsURL.path + "/", with: "")
                                let relativeThumbnailPath = thumbnailURL.path.replacingOccurrences(of: docsURL.path + "/", with: "")
                                
                                // 7. Create and return the Frame object.
                                return Frame(frameName: frameName,
                                             project: project,
                                             index: i,
                                             imagePath: relativeImagePath,
                                             thumbnailPath: relativeThumbnailPath)
                            } catch {
                                print("Error extracting frame at \(time): \(error)")
                                return nil
                            }
                        }
                        
                        // If the frame was extracted and written, update modelContext (on the main actor).
                        if let frame = extractedFrame {
                            try await MainActor.run {
                                modelContext.insert(frame)
                                try modelContext.save()
                            }
                            // Update annotations.
                            annotations[frame.frameName] = [
                                "annotation": "placeholder",
                                "timestamp": CMTimeGetSeconds(time)
                            ]
                        }
                    } // end for loop
                    
                    Task { @MainActor in
                        self.progress = 1.0
                    }
                }.value
                
                await MainActor.run {
                    // FIXME: Enable Background Processing or Pausing.  (Sleep may cause premature crash.)
                    self.state = self.isCancelled ? .failed : .completed
                    let currentDate = Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    let formattedTime = formatter.string(from: currentDate)
                    let successMessage = "Processing complete at \(formattedTime)"
                    self.statusMessage = self.isCancelled ? "Cancelled" : successMessage
                }
                
            } catch {
                await MainActor.run {
                    self.state = .failed
                    self.statusMessage = "Processing failed: \(error.localizedDescription)"
                }
                print("Error in VideoProcessingTask: \(error)")
            }
        }

        
        func pause() {
            if state == .running {
                state = .paused
                statusMessage = "Paused"
            }
        }
        
        func resume() {
            if state == .paused {
                state = .running
                statusMessage = "Resumed"
            }
        }
        
        func cancel() {
            isCancelled = true
            state = .failed
            statusMessage = "Cancelled"
        }
        
        private func createProjectDirectory(named projectName: String) throws -> URL {
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let projectDir = docsURL.appendingPathComponent(projectName, isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            return projectDir
        }
    }
}
