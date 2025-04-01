////
////  BallDetectionModule.swift
////  Annotation
////
////  Created by Jason Agola on 1/10/25.
////
//
//import SwiftUI
//import SwiftData
//import CoreML
//import Vision
//import Combine
//
//// MARK: - Ball Detection Specific Types
//
//struct RawDetection {
//    let normalizedBounds: CGRect  // Original 0-1 coordinates from Vision
//    let confidence: Float
//    let label: String
//}
//
//struct BallDetectionData: Codable {
//    var boundingBox: CGRect
//    var computedCenter: CGPoint
//    var roiBoundingBox: CGRect
//    var visibility: BallVisibility
//    var behavior: BallBehavior
//    
//    enum BallVisibility: String, Codable, CaseIterable {
//        case visible, occluded, notVisible
//    }
//    
//    enum BallBehavior: String, Codable, CaseIterable {
//        case inFlight, inHand, still, bouncing
//    }
//}
//
////struct BallAnnotation: BaseAnnotation {
////    let id: UUID
////    let annotationType: AnnotationType = .ballDetection
////    var status: AnnotationStatus
////    var isSelected: Bool
////    var data: BallDetectionData
////
////    init(data: BallDetectionData, status: AnnotationStatus = .temporary) {
////        self.id = UUID()
////        self.data = data
////        self.status = status
////        self.isSelected = false
////    }
////}
//
//// MARK: - Ball Detection Module
//
//class BallDetectionModule: AnnotationModule {
//    var title: String { "Ball Detection" }
//    var annotationType: AnnotationType = .ballDetection
//    var drawerManager: DetectionDrawerManager
//    internal let image: UIImage
//    private let frameID: Binding<String>
//    private let modelContext: ModelContext
//    
//    
//    private var model: VNCoreMLModel?
//    @Published private var internalTools: [AnnotationModuleTool] = []
//    @Published private var activeTool: AnnotationModuleTool?
//    
//    @Published private var showDebugModal: Bool = false
//    private var debugROIImage: UIImage?
//    private var debugROIRect: CGRect?
//    private var rawDetections: [RawDetection] = []
//    
////    @ObservedObject var annotationsManager = AnnotationManager.shared
//    
//    // The detection drawer manager is injected so that this module can update the drawer's tiles.
//    
//    
//    init(modelContext: ModelContext, showDetectionDrawer: Binding<Bool>, drawerManager: DetectionDrawerManager, frameID: Binding<String>, image: UIImage) {
//        print("Initializing Ball Detection Module...")
////        self.viewModel = viewModel
//        self.frameID = frameID
//        self.drawerManager = drawerManager
//        self.image = image
//        self.modelContext = modelContext
//        if let mlModel = try? performance_640_best(configuration: MLModelConfiguration()).model {
//            self.model = try? VNCoreMLModel(for: mlModel)
//        } else {
//            print("Failed to load CoreML model.")
//        }
//        setupTools()
//    }
//    
//    // MARK: - Protocol Requirements
//    
//    var tools: Binding<[AnnotationModuleTool]> {
//        Binding(
//            get: { self.internalTools },
//            set: { self.internalTools = $0 }
//        )
//    }
//    
//    func selectTool(_ tool: AnnotationModuleTool) {
//        activeTool = tool
//        print("\(tool.name) selected")
//        for index in internalTools.indices {
//            internalTools[index].isSelected = (internalTools[index].id == tool.id)
//        }
//    }
//    
//    func handleTap(at location: CGPoint, in image: UIImage, frameID: String) {
//        print("Tapping in the Ball Detection Module")
//        guard let tool = activeTool else {
//            print(">>> [BallDetectionModule] No active tool selected.")
//            return
//        }
//        
//        print("Received tap in Ball Detection Module at \(location).")
//        
//        // Convert tap point to image coordinates.
//        let imagePoint = CGPoint(
//            x: location.x * image.size.width,
//            y: location.y * image.size.height
//        )
//        
//        print("Received tap in Ball Detection Module at \(imagePoint).")
//        
//        switch tool.name {
//        case "Detect Ball":
//            print("Tool Selection: Detect Ball")
//            detectBall(at: imagePoint, in: image, frameID: frameID)
//        case "Manual Selection":
////            manualSelection(at: imagePoint, frameID: frameID)
//        default:
//            print(">>> [BallDetectionModule] Unsupported tool: \(tool.name).")
//        }
//    }
//    
//    func handleDragChanged(at location: CGPoint, in image: UIImage, frameID: String) {
//        print("Drag changed at \(location)")
//    }
//    
//    func handleDragEnded(at location: CGPoint, in image: UIImage, frameID: String) {
//        print("Drag ended at \(location)")
//    }
//    
//    func renderAnnotations(imageSize: CGSize) ->  AnyView {
//        print("Ball Detection Module rendering annotations... for frameID \(frameID.wrappedValue)")
//        
//        let fetchDescriptor = FetchDescriptor<BallDetection>(
//            predicate: #Predicate {$0.annotationRecord?.frame?.id === frameID.wrappedvalue}
//        )
//        
//        let ballDetections: [BallDetection]
//        
//        do {
//            ballDetections = try modelContext.fetch(fetchDescriptor)
//        } catch {
//            print("Error fetching ball detections: \(error)")
//            ballDetections = []
//        }
//        
////        let temporaryAnnotations: [BallAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
////            ofType: .ballDetection,
////            forFrame: frameID.wrappedValue,
////            as: BallAnnotation.self
////        )
//        
//        let annotationsInImageSpace = ballDetections.map { detection in
//            let boundingBox = CGRect(
//                x: detection.boundingBoxMinX * imageSize.width,
//                y: detection.boundingBoxMinY * imageSize.height,
//                width: detection.boundingBoxWidth * imageSize.width,
//                height: detection.boundingBoxHeight * imageSize.height
//            )
//            return (boundingBox, detection.id)
//        }
//        
////        let temporaryAnnotationsInImageSpace = temporaryAnnotations.map { annotation in
////            let normalizedBoundingBox = annotation.data.boundingBox
////            let boundingBox = CGRect(
////                x: normalizedBoundingBox.minX * imageSize.width,
////                y: normalizedBoundingBox.minY * imageSize.height,
////                width: (normalizedBoundingBox.maxX - normalizedBoundingBox.minX) * imageSize.width,
////                height: (normalizedBoundingBox.maxY - normalizedBoundingBox.minY) * imageSize.height
////            )
////            
////            return (boundingBox, annotation.id)
////        }
//        
//        print("temporaryAnnotationsInImageSpace: \(annotationsInImageSpace)")
//        
//        return AnyView(
//            ZStack {
//                ForEach(annotationsInImageSpace, id: \.0) { boundingBox, annotationId in
//                    Rectangle()
//                        .stroke(Color.red, lineWidth: 2)
//                        .frame(width: boundingBox.width, height: boundingBox.height)
//                        .position(x: boundingBox.midX, y: boundingBox.midY)
//                    }
//                }
//            )
//        }
//    
//    // MARK: - Private Helper Methods
//    
//    private func setupTools() {
//        self.internalTools = [
//            AnnotationModuleTool(
//                name: "Detect Ball",
//                action: { [weak self] in
//                    if let tool = self?.internalTools.first(where: { $0.name == "Detect Ball" }) {
//                        self?.selectTool(tool)
//                    }
//                },
//                isSelected: false,
//                detectionTiles: [
////                    generateSampleTile()
//                ]
//                
//            ),
//            AnnotationModuleTool(
//                name: "Manual Selection",
//                action: { [weak self] in
//                    if let tool = self?.internalTools.first(where: { $0.name == "Manual Selection" }) {
//                        self?.selectTool(tool)
//                    }
//                },
//                isSelected: false,
//                detectionTiles: [
////                    generateSampleTile()
//                ]
//            ),
//            AnnotationModuleTool(
//                name: "Process Entire Frame",
//                action: { [weak self] in
//                    if let tool = self?.internalTools.first(where: { $0.name == "Process Entire Frame" }) {
//                        self?.selectTool(tool)
//                        self?.processEntireFrame()
//                    }
//                },
//                isSelected: false,
//                detectionTiles: [
////                    generateSampleTile()
//                ]
//            )
//        ]
//        activeTool = internalTools.first(where: { $0.isSelected })
//    }
//
//
//    internal func processEntireFrame() {
//        print("Running Process Entire Frame")
//        guard let cgImage = image.cgImage else {
//            print("no image")
//            return
//        }
//        
//        let imageWidth = cgImage.width
//        let imageHeight = cgImage.height
//        let roiDimension: CGFloat = 640
//        var roiCollection = [CGPoint]()
//        
//        for y in stride(from: roiDimension/2, to: CGFloat(imageHeight), by: roiDimension) {
//            for x in stride(from: roiDimension/2, to: CGFloat(imageWidth), by: roiDimension) {
//                print("X: \(x), Y: \(y)")
//                roiCollection.append(CGPoint(x: x, y: y))
//            }
//        }
//        
//        print("Roi Collection: ", roiCollection )
//        
//        // Process each center point
//        for centerPoint in roiCollection {
//            detectBall(at: centerPoint, in: image, frameID: frameID.wrappedValue)
//        }
//        
//    
//    }
//    
//    private func detectBall(at point: CGPoint, in image: UIImage, frameID: String) {
//        print("Detect Ball Method")
////        print(">>> COORDINATE DEBUG >>>")
////        print("1. Input tap point: \(point)")
////        print("2. Image dimensions: width=\(image.size.width), height=\(image.size.height)")
//        
//        guard let model = model, let cgImage = image.cgImage else {
//            print(">>> [BallDetectionModule: detectBall] Error: CoreML model or CGImage not available")
//            return
//        }
//        
//        let roiDimension: CGFloat = 640
//        let roiOriginX = max(0, min(CGFloat(cgImage.width) - roiDimension, point.x - roiDimension / 2))
//        let roiOriginY = max(0, min(CGFloat(cgImage.height) - roiDimension, point.y - roiDimension / 2))
//        let roiRect = CGRect(x: roiOriginX, y: roiOriginY, width: roiDimension, height: roiDimension)
////        print("3. ROI rect: \(roiRect)")
//            
//        guard let croppedCGImage = cgImage.cropping(to: roiRect) else {
//            print(">>> [BallDetectionModule] Error: Failed to crop image to ROI: \(roiRect)")
//            return
//        }
//            
//        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
//            if let error = error {
//                print(">>> [BallDetectionModule] CoreML request error: \(error.localizedDescription)")
//                return
//            }
//                
//            if let observations = request.results as? [VNRecognizedObjectObservation] {
//                print("DetectBall: Model returned \(observations).")
//                self?.processDetectionResults(observations, roi: roiRect, originalImageSize: image.size, frameID: frameID)
//            }
//        }
//            
//        let handler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
//            
//        do {
//            try handler.perform([request])
//        } catch {
//            print(">>> [BallDetectionModule] Failed to perform CoreML request: \(error)")
//        }
//    }
//    
//    private func normalizeToImageSpace(_ rect: CGRect, imageSize: CGSize) -> CGRect {
//        return CGRect(
//            x: rect.origin.x / imageSize.width,
//            y: rect.origin.y / imageSize.height,
//            width: rect.width / imageSize.width,
//            height: rect.height / imageSize.height
//        )
//    }
//        
//    private func processDetectionResults(_ observations: [VNRecognizedObjectObservation], roi: CGRect, originalImageSize: CGSize, frameID: String) {
////        print("4. Processing detection with:")
////        print("   Original image size: \(originalImageSize)")
////        print("   ROI: \(roi)")
//        
//        for observation in observations {
//            guard let label = observation.labels.first?.identifier else { continue }
//            
////            print("5. Raw Vision observation bounds: \(observation.boundingBox)")
//            
//            let ballBoundingBoxInROI = CGRect(
//                x: observation.boundingBox.origin.x * roi.width,
//                y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * roi.height,
//                width: observation.boundingBox.width * roi.width,
//                height: observation.boundingBox.height * roi.height
//            )
////            print("6. Bounds in ROI space: \(ballBoundingBoxInROI)")
//            
//            let ballBoundingBoxInImage = CGRect(
//                x: roi.origin.x + ballBoundingBoxInROI.origin.x,
//                y: roi.origin.y + ballBoundingBoxInROI.origin.y,
//                width: ballBoundingBoxInROI.width,
//                height: ballBoundingBoxInROI.height
//            )
////            print("7. Bounds in image space: \(ballBoundingBoxInImage)")
//            
//            let normalizedBallBox = normalizeToImageSpace(ballBoundingBoxInImage, imageSize: originalImageSize)
////            print("8. Final normalized bounds: \(normalizedBallBox)")
//            
//            let normalizedROI = normalizeToImageSpace(roi, imageSize: originalImageSize)
//            
//            let data = BallDetectionData(
//                boundingBox: normalizedBallBox,
//                computedCenter: CGPoint(
//                    x: normalizedBallBox.midX,
//                    y: normalizedBallBox.midY
//                ),
//                roiBoundingBox: normalizedROI,
//                visibility: .visible,
//                behavior: .inFlight
//            )
//            
////            print("Original ROI: \(roi)")
////            print("Normalized ROI: \(normalizedROI)")
////            print("Original Ball Box: \(ballBoundingBoxInImage)")
////            print("Normalized Ball Box: \(normalizedBallBox)")
//            
////            let annotation = BallAnnotation(data: data)
//            
//            DispatchQueue.main.async {
////                AnnotationManager.shared.addTemporaryAnnotation(annotation, toFrame: frameID)
//            }
//        }
//    }
//    
////    private func manualSelection(at location: CGPoint, frameID: String) {
////        let defaultSize: CGFloat = 50
////        let boundingBox = CGRect(
////            x: location.x - defaultSize/2,
////            y: location.y - defaultSize/2,
////            width: defaultSize,
////            height: defaultSize
////        )
////        
////        let data = BallDetectionData(
////            boundingBox: boundingBox,
////            computedCenter: location,
////            roiBoundingBox: boundingBox.insetBy(dx: -20, dy: -20),
////            visibility: .visible,
////            behavior: .still
////        )
////        
////        let annotation = BallAnnotation(data: data)
////        AnnotationManager.shared.addTemporaryAnnotation(annotation, toFrame: frameID)
////    }
//    
//    func temporaryAnnotationView() -> DetectionTile {
////        let temporary: [BallAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
////            ofType: .ballDetection,
////            forFrame: frameID
////        )
//        
//        return DetectionTile(
//            title: "Temporary Ball Detections",
//            content: {
//                AnyView(
//                    Text("Temporary Ball Detection Annotation")
//            )}
//        )
//    }
//    
////    func annotationDetailView(for annotation: any BaseAnnotation, frameID: String) -> AnyView {
////        
////        return AnyView(Text("BallDetection Annotation Detail"))
////    }
//    
//    // MARK: - Annotation Detail View Using the Tile System
//    
////    struct SampleTileView: View {
////        @ObservedObject var annotationsManager = AnnotationManager.shared
////        let frameID: String  // Accept frameID as a parameter
////        let annotationType: AnnotationType = .ballDetection
////        
////        var body: some View {
////            let temporaryAnnotations: [BallAnnotation] = annotationsManager.getTemporaryAnnotations(
////                ofType: annotationType,
////                forFrame: frameID,
////                as: BallAnnotation.self
////            )
////            
////            return VStack(alignment: .leading, spacing: 10) {
////                Text("Temporary Annotations Count: \(temporaryAnnotations.count)")
////                    .font(.headline)
////                
////                List(temporaryAnnotations, id: \.id) { annotation in
////                    VStack(alignment: .leading) {
////                        Text("Annotation ID: \(annotation.id.uuidString.prefix(8))")
////                            .font(.subheadline)
////                        Text("Center: (\(annotation.data.computedCenter.x, specifier: "%.2f"), \(annotation.data.computedCenter.y, specifier: "%.2f"))")
////                            .font(.caption)
////                    }
////                }
////            }
////            .padding()
////            .background(Color.gray)
////            .cornerRadius(8)
////            .shadow(radius: 2)
////        }
////    }
//    
//    func generateSampleTile() -> DetectionTile {
////        return DetectionTile(
////            title: "Sample Tile", content: {SampleTileView(frameID: self.frameID.wrappedValue)})
//    }
////    
////    func sampleTile() -> DetectionTile {
////        return DetectionTile(
////            title: "Sample Ball Detection Tile",
////            content: {
////                AnyView(self.SampleTileView)
////            }
////        )
////    }
//
//    
//    /// Generates a tile view containing the ball detection annotation details.
//    func generateDetailTile(frameID: String) -> some View {
//        
//        return VStack{Text("Annotations Should Appear Here")}
//        //        let temporary: [BallAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
//        //            ofType: .ballDetection,
//        //            forFrame: frameID
//        //        )
//        //
//        //        return VStack(alignment: .leading, spacing: 8) {
//        //            Text("Ball Annotation Details")
//        //                .font(.headline)
//        //                .padding(.top, 5)
//        //
//        //            // Visibility Selector
//        //            Picker("Visibility", selection: Binding(
//        //                get: { annotation.data.visibility },
//        //                set: { [self] newValue in
//        //                    updateVisibility(for: annotation, newVisibility: newValue, frameID: frameID)
//        //                }
//        //            )) {
//        //                ForEach(BallDetectionData.BallVisibility.allCases, id: \.self) { visibility in
//        //                    Text(visibility.rawValue.capitalized).tag(visibility)
//        //                }
//        //            }
//        //            .pickerStyle(SegmentedPickerStyle())
//        //
//        //            // Behavior Selector
//        //            Picker("Behavior", selection: Binding(
//        //                get: { annotation.data.behavior },
//        //                set: { newValue in
//        //                    self.updateBehavior(for: annotation, newBehavior: newValue, frameID: frameID)
//        //                }
//        //            )) {
//        //                ForEach(BallDetectionData.BallBehavior.allCases, id: \.self) { behavior in
//        //                    Text(behavior.rawValue.capitalized).tag(behavior)
//        //                }
//        //            }
//        //            .pickerStyle(SegmentedPickerStyle())
//        //
//        //            // Commit & Delete Buttons
//        //            Button("Commit Annotation") {
//        //                self.commitAnnotation(annotation, frameID: frameID)
//        //            }
//        //            .frame(maxWidth: .infinity)
//        //            .padding()
//        //            .background(Color.green)
//        //            .foregroundColor(.white)
//        //            .cornerRadius(10)
//        //
//        //            Button("Delete Annotation") {
//        //                self.deleteAnnotation(annotation, frameID: frameID)
//        //            }
//        //            .frame(maxWidth: .infinity)
//        //            .padding()
//        //            .background(Color.red)
//        //            .foregroundColor(.white)
//        //            .cornerRadius(10)
//        //        }
//        //        .padding(8)
//        //        .background(Color.white.opacity(0.1))
//        //        .cornerRadius(8)
//        //    }
//    }
//    
//    // MARK: - Update, Commit & Delete Helper Methods
//    private func updateVisibility(for annotation: BallAnnotation, newVisibility: BallDetectionData.BallVisibility, frameID: String) {
//        var updatedAnnotation = annotation
//        updatedAnnotation.data.visibility = newVisibility
////        AnnotationManager.shared.updateAnnotation(updatedAnnotation, inFrame: frameID)
//    }
//    
//    private func updateBehavior(for annotation: BallAnnotation, newBehavior: BallDetectionData.BallBehavior, frameID: String) {
//        var updatedAnnotation = annotation
//        updatedAnnotation.data.behavior = newBehavior
////        AnnotationManager.shared.updateAnnotation(updatedAnnotation, inFrame: frameID)
//    }
//    
//    private func commitAnnotation(_ annotation: BallAnnotation, frameID: String) {
////        AnnotationManager.shared.commitAnnotation(annotation, fromFrame: frameID)
//    }
//    
//    private func deleteAnnotation(_ annotation: BallAnnotation, frameID: String) {
////        AnnotationManager.shared.deleteAnnotation(annotation, fromFrame: frameID)
//    }
//}
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
