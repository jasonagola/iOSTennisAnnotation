import SwiftUI
import SwiftData
import CoreML
import Vision
import Combine

// MARK: - Ball Detection Specific Types

struct RawDetection {
    let normalizedBounds: CGRect  // Original 0-1 coordinates from Vision
    let confidence: Float
    let label: String
}

struct BallDetectionData: Codable {
    var boundingBox: CGRect
    var computedCenter: CGPoint
    var roiBoundingBox: CGRect
    var visibility: BallVisibility
    var behavior: BallBehavior
    
    enum BallVisibility: String, Codable, CaseIterable {
        case visible, occluded, notVisible
    }
    
    enum BallBehavior: String, Codable, CaseIterable {
        case inFlight, inHand, still, bouncing
    }
}

// MARK: - Ball Detection Module

final class BallDetectionModule: AnnotationModule, ObservableObject {
    private var frameState: FrameState

    var title: String { "Ball Detection" }
    var annotationType: AnnotationType = .ballDetection
    
    // Dependencies
    var drawerManager: DetectionDrawerManager
    private let modelContext: ModelContext
    private var model: VNCoreMLModel?
    private var showDetectionDrawer: Binding<Bool>
    
    // Tools
    internal var internalTools: [AnnotationModuleTool]
    @Published private var activeTool: AnnotationModuleTool?
    
    // Debug & internal data
//    @Published var showDebugModal: Bool = false
//    private var rawDetections: [RawDetection] = []
    
    init(
        modelContext: ModelContext,
        showDetectionDrawer: Binding<Bool>,
        drawerManager: DetectionDrawerManager,
        frameState: FrameState
    ) {
        self.drawerManager = drawerManager
        self.modelContext = modelContext
        self.showDetectionDrawer = showDetectionDrawer
        self.internalTools = []
        self.frameState = frameState

        // Load the CoreML model
        if let mlModel = try? performance_640_best(configuration: MLModelConfiguration()).model {
            self.model = try? VNCoreMLModel(for: mlModel)
            print("BDM #2: CoreML model loaded successfully")
        } else {
            print("BDM #2: Failed to load CoreML model.")
        }
        drawerManager.addTile(DetectionTile(title: "Ball Detection", content: {
            BallDetectionTile(frameState: self.frameState, modelContext: self.modelContext)
        }))
        setupTools()
    }
    
    // MARK: - Tool Setup
    private func setupTools() {
        self.internalTools = [
            AnnotationModuleTool(
                name: "Detect Ball",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: { $0.name == "Detect Ball" }) {
                        self?.selectTool(tool)
                        print("BDM #3: 'Detect Ball' tool selected")
                    }
                },
                isSelected: false,
                detectionTiles: [
                    DetectionTile(title: "Ball Detection", content: {
                        BallDetectionTile(frameState: self.frameState, modelContext: self.modelContext)
                    })
                ]
            ),
            AnnotationModuleTool(
                name: "Manual Selection",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: { $0.name == "Manual Selection" }) {
                        self?.selectTool(tool)
                        print("BDM #4: 'Manual Selection' tool selected")
                    }
                },
                isSelected: false,
                detectionTiles: []
            ),
            AnnotationModuleTool(
                name: "Process Entire Frame",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: { $0.name == "Process Entire Frame" }) {
                        self?.selectTool(tool)
                        // FIXME: Reset Tool Selection
                        print("BDM #5: 'Process Entire Frame' tool selected")
                        self?.processEntireFrame()
                    }
                },
                isSelected: false,
                detectionTiles: [
                    DetectionTile(title: "Ball Detections", content: {
                        BallDetectionTile(frameState: self.frameState, modelContext: self.modelContext)
                    })
                ]
            ),
            AnnotationModuleTool(
                //TODO: Create Render Layer for each module again and allow greenlighting for this layer
                //TODO: Fetch and create a combined image and related Annotations and render the combined image. 
                name: "Relate Temporal Detections",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: { $0.name == "Relate Temporal Detections" }) {
                        self?.selectTool(tool)
                        // FIXME: Reset Tool Selection
                    }
                },
                isSelected: false,
                detectionTiles: []
            )
        ]
        activeTool = internalTools.first(where: { $0.isSelected })
    }
    
    internal func selectTool(_ tool: AnnotationModuleTool) {
        activeTool = tool
        internalTools = internalTools.map { moduleTool in
            var updatedTool = moduleTool
            updatedTool.isSelected = (moduleTool.id == tool.id)
            return updatedTool
        }
//        print("BDM #6: Tool selected - \(tool.name) with current frameUUID: \(frameState.currentFrameUUID ?? )")
    }
    
    // MARK: - User Interaction
    
    func handleTap(at point: CGPoint) {
        guard let tool = activeTool else {
            print("BDM #8: No active tool selected in Ball Detection Module.")
            return
        }
        guard let currentImage = frameState.currentImage else {
            print("BDM #8b: No current image available in frameState.")
            return
        }
        // Convert normalized point to image coordinates.
        let imagePoint = CGPoint(
            x: point.x * currentImage.size.width,
            y: point.y * currentImage.size.height
        )
        switch tool.name {
        case "Detect Ball":
            print("BDM #9: Handling tap for 'Detect Ball'")
            detectBall(at: imagePoint, in: currentImage)
        default:
            print("BDM #10: Unsupported tool: \(tool.name)")
        }
    }
    
    func handleDragChanged(at point: CGPoint) {
        // Implement if needed.
    }
    
    func handleDragEnded(at point: CGPoint) {
        // Implement if needed.
    }
    
    // MARK: - Annotation Rendering
    
    func renderAnnotations(imageSize: CGSize) -> AnyView {
        let capturedFrameUUID = frameState.currentFrameUUID
//        print("BDM #11: renderAnnotations using current frameUUID: \(capturedFrameUUID)")
        
        let fetchDescriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate { detection in
                detection.frameUUID == capturedFrameUUID
            }
        )
        let ballDetections: [BallDetection]
        do {
            ballDetections = try modelContext.fetch(fetchDescriptor)
//            print("BDM #12: Render Ball Detections: \(ballDetections)")
        } catch {
            print("BDM #12: Error fetching ball detections: \(error)")
            ballDetections = []
        }
        let annotationsInImageSpace = ballDetections.map { detection -> (CGRect, UUID) in
            let boundingBox = CGRect(
                x: detection.boundingBoxMinX * imageSize.width,
                y: detection.boundingBoxMinY * imageSize.height,
                width: detection.boundingBoxWidth * imageSize.width,
                height: detection.boundingBoxHeight * imageSize.height
            )
            return (boundingBox, detection.id)
        }
        return AnyView(
            ZStack {
                ForEach(annotationsInImageSpace, id: \.1) { (boundingBox, uuid) in
                    Rectangle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: boundingBox.width, height: boundingBox.height)
                        .position(x: boundingBox.midX, y: boundingBox.midY)
                }
            }
        )
    }
    
    // MARK: - Processing Entire Frame
    
    func processEntireFrame() {
        guard let currentImage = frameState.currentImage, let cgImage = currentImage.cgImage else {
            print("BDM #13: No CGImage available from current image in frameState.")
            return
        }
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let roiDimension: CGFloat = 640
        var roiCollection = [CGPoint]()
        for y in stride(from: roiDimension / 2, to: CGFloat(imageHeight), by: roiDimension) {
            for x in stride(from: roiDimension / 2, to: CGFloat(imageWidth), by: roiDimension) {
                roiCollection.append(CGPoint(x: x, y: y))
            }
        }
        print("BDM #14: Processing entire frame - total ROIs: \(roiCollection.count)")
        for centerPoint in roiCollection {
            detectBall(at: centerPoint, in: currentImage)
        }
    }
    
    // MARK: - Ball Detection
    
    private func detectBall(at point: CGPoint, in image: UIImage) {
        print("BDM #15: Running Detect Ball")
        guard let model = model, let cgImage = image.cgImage else {
            print("BDM #16: CoreML model or CGImage not available.")
            return
        }

        guard let capturedFrameUUID = frameState.currentFrameUUID else {
            print("BDM #17a: No currentFrameUUID in frameState.")
            return
        }

        print("BDM #17: Captured frameUUID from frameState in detectBall: \(capturedFrameUUID)")

        let roiDimension: CGFloat = 640
        let roiOriginX = max(0, min(CGFloat(cgImage.width) - roiDimension, point.x - roiDimension / 2))
        let roiOriginY = max(0, min(CGFloat(cgImage.height) - roiDimension, point.y - roiDimension / 2))
        let roiRect = CGRect(x: roiOriginX, y: roiOriginY, width: roiDimension, height: roiDimension)

        guard let croppedCGImage = cgImage.cropping(to: roiRect) else {
            print("BDM #18: Failed to crop image to ROI: \(roiRect)")
            return
        }

        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            if let error = error {
                print("BDM #19: CoreML request error: \(error.localizedDescription)")
                return
            }

            if let observations = request.results as? [VNRecognizedObjectObservation] {
                self?.processDetectionResults(
                    observations,
                    roi: roiRect,
                    originalImageSize: image.size,
                    capturedFrameUUID: capturedFrameUUID
                )
            }
        }

        let handler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("BDM #20: Failed to perform CoreML request: \(error)")
        }
    }
    
    // MARK: - Utility
    private func normalizeToImageSpace(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        return CGRect(
            x: rect.origin.x / imageSize.width,
            y: rect.origin.y / imageSize.height,
            width: rect.width / imageSize.width,
            height: rect.height / imageSize.height
        )
    }
    
    // MARK: - Process Detection Results
    
    private func processDetectionResults(_ observations: [VNRecognizedObjectObservation],
                                         roi: CGRect,
                                         originalImageSize: CGSize,
                                         capturedFrameUUID: UUID
                                        ) {
        print("BDM #21: Processing detection results for capturedFrameUUID: \(capturedFrameUUID)")
        for observation in observations {
            guard let _ = observation.labels.first?.identifier else { continue }
            let ballBoundingBoxInROI = CGRect(
                x: observation.boundingBox.origin.x * roi.width,
                y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * roi.height,
                width: observation.boundingBox.width * roi.width,
                height: observation.boundingBox.height * roi.height
            )
            let ballBoundingBoxInImage = CGRect(
                x: roi.origin.x + ballBoundingBoxInROI.origin.x,
                y: roi.origin.y + ballBoundingBoxInROI.origin.y,
                width: ballBoundingBoxInROI.width,
                height: ballBoundingBoxInROI.height
            )
            let normalizedBallBox = normalizeToImageSpace(ballBoundingBoxInImage, imageSize: originalImageSize)
            let normalizedROI = normalizeToImageSpace(roi, imageSize: originalImageSize)
            
            let ballDetection = BallDetection(
                boundingBox: normalizedBallBox,
                computedCenter: CGPoint(x: normalizedBallBox.midX, y: normalizedBallBox.midY),
                roiBoundingBox: normalizedROI,
                visibility: .visible,
                behavior: [.inFlight],
                annotationRecord: nil,
                frameUUID: capturedFrameUUID
            )
            
            print("BDM #22: Inserting detection with frameUUID: \(capturedFrameUUID)")
            Task { @MainActor in
                frameState.addBallAnnotation(ballDetection)
//  FIXME:              frameState.triggerRefresh()
            }
            
        }
    }
}
