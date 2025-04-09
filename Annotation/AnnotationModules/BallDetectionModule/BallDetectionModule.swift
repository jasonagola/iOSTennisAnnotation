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
    @EnvironmentObject private var queueManager: ProcessingQueueManager
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
    
    //Manual Selection
    private var dragStartPoint: CGPoint? = nil
    @Published var currentBoundingBox: CGRect? = nil
    
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
                detectionTiles: [
                    DetectionTile(title: "Ball Detections", content: {
                        BallDetectionTile(frameState: self.frameState, modelContext: self.modelContext)
                    })
                ]
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
    
    //TODO: Enable Drawing Features for ball concurrency
    func handleDragChanged(at point: CGPoint) {
        print("Drag is changing: \(point)")
        guard let tool = activeTool else  {
            return
        }
        
        guard let currentImage = frameState.currentImage else {
            return
        }
        
        let imagePoint = CGPoint(
            x: point.x * currentImage.size.width,
            y: point.y * currentImage.size.height
        )
        
        switch tool.name {
        case "Manual Selection":
            handleManualSelectionDragChanged(point)
        default:
            print("Unsupported tool in handleDragChanged: \(tool.name)")
        }

    }
    
    func handleDragEnded(at point: CGPoint) {
        print("DRAG ENDED: \(point)")
        guard let tool = activeTool else  {
            return
        }
        
        guard let currentImage = frameState.currentImage else {
            return
        }
        
        let imagePoint = CGPoint(
            x: point.x * currentImage.size.width,
            y: point.y * currentImage.size.height
        )
        
        switch tool.name {
        case "Manual Selection":
            handleManualSelectionDragEnded(point)
        default:
            print("Unsupported tool in handleDragChanged: \(tool.name)")
        }
    }
    
    
    private func handleManualSelectionDragChanged(_ point: CGPoint) {
        if dragStartPoint == nil {
            dragStartPoint = point
        }

        guard let start = dragStartPoint else { return }

        let origin = CGPoint(
            x: min(start.x, point.x),
            y: min(start.y, point.y)
        )
        let size = CGSize(
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        
        print("Current Bounding box during drag: \(origin) \(size)")
        currentBoundingBox = CGRect(origin: origin, size: size)
        frameState.toolRenderOverlayRefreshToken = UUID()
    }

    private func handleManualSelectionDragEnded(_ point: CGPoint) {
        guard let start = dragStartPoint else { return }

        let origin = CGPoint(
            x: min(start.x, point.x),
            y: min(start.y, point.y)
        )
        let size = CGSize(
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )

        let finalBox = CGRect(origin: origin, size: size)
        saveManualSelection(boundingBox: finalBox)
        frameState.toolRenderOverlayRefreshToken = UUID()

        dragStartPoint = nil
        currentBoundingBox = nil
    }
    
    func saveManualSelection(boundingBox: CGRect) {
        guard let imageSize = frameState.currentImage?.size else { return }
                
        let normalizedBallBox = normalizeToImageSpace(boundingBox)
        let computedCenter = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        
        let roiWidth: CGFloat = 640
        let roiHeight: CGFloat = 640

        let roiCenter = CGPoint(
            x: computedCenter.x * imageSize.width,
            y: computedCenter.y * imageSize.height
        )

        let roiOrigin = CGPoint(
            x: max(0, roiCenter.x - roiWidth / 2),
            y: max(0, roiCenter.y - roiHeight / 2)
        )

        let roiRect = CGRect(origin: roiOrigin, size: CGSize(width: roiWidth, height: roiHeight))
        let normalizedROI = normalizeToImageSpace(roiRect)
        
        let ballDetection = BallDetection(
            boundingBox: boundingBox,
            computedCenter: computedCenter,
            roiBoundingBox: roiRect,
            visibility: .visible,
            behavior: [.inFlight],
            annotationRecord: nil,
            frameUUID: frameState.currentFrameUUID
        )
        
        Task { @MainActor in
            frameState.addBallAnnotation(ballDetection, frameUUID: frameState.currentFrameUUID!)
//  FIXME:              frameState.triggerRefresh()
        }
    }
    // MARK: - Annotation Rendering
    
    func renderToolOverlay(imageSize: CGSize) -> AnyView {
        switch activeTool?.name {
        case "Manual Selection":
            return AnyView (
                ZStack {
                    if let currentBox = currentBoundingBox {
                        let rect = CGRect(
                            x: currentBox.origin.x * imageSize.width,
                            y: currentBox.origin.y * imageSize.height,
                            width: currentBox.width * imageSize.width,
                            height: currentBox.height * imageSize.height
                        )
                        
                        Rectangle()
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            )
            
        case "Relate Temporal Detections":
            print("Rendering tool overlay")
            
//            return AnyView(CompositeOverlayView(frameState: frameState))
            let videoUrl = frameState.projectDir!.appendingPathComponent("compositeOverlay.mov")
            print("Video url: \(videoUrl)")
            return AnyView(VideoScrubberView(videoURL: videoUrl, frameState: frameState))
            
        default:
            print("No tools to render")
            return AnyView(EmptyView()) // <- Add this!
        }
    }


    
    
    // MARK: - Processing Entire Frame
    
    func processEntireFrame(with externalImage: UIImage? = nil, frameUUID: UUID? = nil) {
        // Use the external image if provided; otherwise, fall back to frameState.currentImage.
        guard let currentImage = externalImage ?? frameState.currentImage,
              let cgImage = currentImage.cgImage else {
            print("BDM #13: No CGImage available from the provided image or frameState.")
            return
        }
        
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let roiDimension: CGFloat = 640
        var roiCollection = [CGPoint]()
        
        // Build a grid of ROIs.
        for y in stride(from: roiDimension / 2, to: CGFloat(imageHeight), by: roiDimension) {
            for x in stride(from: roiDimension / 2, to: CGFloat(imageWidth), by: roiDimension) {
                roiCollection.append(CGPoint(x: x, y: y))
            }
        }
        
        print("BDM #14: Processing entire frame - total ROIs: \(roiCollection.count)")
        
        // When calling detectBall, pass along the external frameUUID.
        for centerPoint in roiCollection {
            detectBall(at: centerPoint, in: currentImage, using: frameUUID)
        }
    }
    
    // MARK: - Ball Detection
    
    private func detectBall(at point: CGPoint, in image: UIImage, using frameUUID: UUID? = nil) {
        print("BDM #15: Running detectBall")
        guard let model = model, let cgImage = image.cgImage else {
            print("BDM #16: CoreML model or CGImage not available.")
            return
        }
        
        // Use the provided frameUUID if available; otherwise, fall back to frameState.currentFrameUUID.
        let capturedFrameUUID = frameUUID ?? frameState.currentFrameUUID
        guard let capturedFrameUUID = capturedFrameUUID else {
            print("BDM #17a: No frameUUID available either from the external parameter or from frameState.")
            return
        }
        
        print("BDM #17: Captured frameUUID in detectBall: \(capturedFrameUUID)")
        
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
    private func normalizeToImageSpace(_ rect: CGRect) -> CGRect {
        guard let imageSize = frameState.currentImage?.size else {
            print("BDM: normalizeToImageSpace failed — no current image in frameState.")
            return .zero
        }

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
            let normalizedBallBox = normalizeToImageSpace(ballBoundingBoxInImage)
            let normalizedROI = normalizeToImageSpace(roi)
            
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
                frameState.addBallAnnotation(ballDetection, frameUUID: capturedFrameUUID)
//  FIXME:              frameState.triggerRefresh()
            }
            
        }
    }
}
