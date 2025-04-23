//
//  CourtDetectionModule.swift
//  Annotation
//
//  Created by Jason Agola on 1/29/25.


import SwiftUI
import SwiftData


class CourtDetectionModule: AnnotationModule, ObservableObject {
    func toolOverlayPath(in imageSize: CGSize) -> CGPath? {
        return nil
    }
    
    private var frameState: FrameState
    
    var title: String { "Court Detection" }
    var annotationType: AnnotationType = .courtDetection
    
    private let modelContext: ModelContext
    private var showDetectionDrawer: Binding<Bool>
    
    
    internal var internalTools: [AnnotationModuleTool] = []
    @Published private var activeTool: AnnotationModuleTool?
    
    @Published var isWizardActive: Bool = false
    @Published var currentKeypointIndex: Int = 0
    @Published var currentKeypointName: String? = nil
    @Published var missingKeypoints: [String] = []
    
    @Published var wizardTapLocation: CGPoint? = nil
    
    // The detection drawer manager for dynamically adding tiles.
    var drawerManager: DetectionDrawerManager
    var courtModel = CourtModel()
    
    init(modelContext: ModelContext, showDetectionDrawer: Binding<Bool>, drawerManager: DetectionDrawerManager, frameState: FrameState) {
        self.modelContext = modelContext
        self.showDetectionDrawer = showDetectionDrawer
        self.drawerManager = drawerManager
        self.frameState = frameState
        
        // TODO: Add default tile behavior.
//        drawerManager.addTile()
        
        setupTools()
    }
    
    var tools: Binding<[AnnotationModuleTool]> {
        Binding(
            get: { self.internalTools },
            set: { self.internalTools = $0 }
        )
    }
    
    // MARK: - Setup Tools
    private func setupTools() {
        self.internalTools = [
            AnnotationModuleTool(
                name: "ML Court Detection",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: { $0.name == "ML Court Detection" }) {
                        self?.selectTool(tool)
                    }
                },
                isSelected: false,
                detectionTiles: [
                    //Add Tiles Here
                ]
            ),
            AnnotationModuleTool(
                name: "Keypoint Wizard",
                action: { [weak self] in
                    if let tool = self?.internalTools.first(where: {$0.name == "Keypoint Wizard"}) {
                        self?.selectTool(tool)
                    }
                },
                isSelected: false,
                detectionTiles: [
                    generateWizardTile(module: self)
                ]
                
            )
        ]
        activeTool = internalTools.first(where: { $0.isSelected })
    }
    
    // MARK: - Rendering
    func renderToolOverlay(imageSize: CGSize) ->  AnyView {
////        print("Court Detection Module rendering annotations...")
//        let temporaryAnnotations: [CourtKeypointAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
//            ofType: .courtDetection,
//            forFrame: frameID.wrappedValue,
//            as: CourtKeypointAnnotation.self
//        )
//        
//        let committedAnnotations: [CourtKeypointAnnotation] = AnnotationManager.shared.getCommittedAnnotations(
//            ofType: .courtDetection,
//            forFrame: frameID.wrappedValue,
//            as: CourtKeypointAnnotation.self
//        )
//        
//        //Filtered for non zero position transformed to imageSpace
////        print("Image Size: \(imageSize.width) x \(imageSize.height)")
////        print("Wizard Tap Location (Normalized): \(String(describing: wizardTapLocation))")
////        print("Wizard Tap Location (Image Space): \(String(describing: wizardTapLocation.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }))")
////        
////        print("Raw Court Keypoints Before Scaling: \(temporaryAnnotations.first?.data.keypoints ?? [:])")
//        
//        let temporaryCourtKeypoints: [(String, CourtKeypoint)] = temporaryAnnotations.first?.data.keypoints.map { (keypointName, keypoint) in
//            let scaledPosition = CGPoint(
//                x: keypoint.position.x * imageSize.width,
//                y: keypoint.position.y * imageSize.height
//            )
////            print("Keypoint '\(keypointName)' (Normalized): \(keypoint.position)")
////            print("Keypoint '\(keypointName)' (Image Space): \(scaledPosition)")
//            
//            return (
//                keypointName,
//                CourtKeypoint(
//                    position: scaledPosition,
//                    visibility: keypoint.visibility
//                )
//            )
//        } ?? []
//        
//        let committedCourtKeypoints: [(String, CourtKeypoint)] = committedAnnotations.first?.data.keypoints.map { (keypointName, keypoint) in
//            let scaledPosition = CGPoint(
//                x: keypoint.position.x * imageSize.width,
//                y: keypoint.position.y * imageSize.height
//            )
////            print("Keypoint '\(keypointName)' (Normalized): \(keypoint.position)")
////            print("Keypoint '\(keypointName)' (Image Space): \(scaledPosition)")
//            
//            return (
//                keypointName,
//                CourtKeypoint(
//                    position: scaledPosition,
//                    visibility: keypoint.visibility
//                )
//            )
//        } ?? []
//        
//        print("Final Court Keypoints in Image Space: \(committedCourtKeypoints)")
//        
//        
//        
//        return AnyView(
//            ZStack {
//                
//                // 2) Draw temporary Court Keypoints
//                ForEach(temporaryCourtKeypoints, id: \.0) { (keypointName, keypoint) in
//                    Circle()
//                        .stroke(keypoint.visibility == .visible ? Color.orange : Color.orange, lineWidth: 4)
//                        .frame(width: 16, height: 16)
//                        .position(x: keypoint.position.x, y: keypoint.position.y)
//                    Circle()
//                        .fill(Color.red)
//                        .frame(width: 4, height: 4)
//                        .position(x: keypoint.position.x, y: keypoint.position.y)
//
//                }
//                
//                ForEach(committedCourtKeypoints, id: \.0) { (keypointName, keypoint) in
//                    Circle()
//                        .stroke(keypoint.visibility == .visible ? Color.green : Color.green, lineWidth: 4)
//                        .frame(width: 16, height: 16)
//                        .position(x: keypoint.position.x, y: keypoint.position.y)
//                    Circle()
//                        .fill(Color.red)
//                        .frame(width: 4, height: 4)
//                        .position(x: keypoint.position.x, y: keypoint.position.y)
//                }
//            }
//        )
        return AnyView(
            ZStack {}
        )
    }

    
    func selectTool(_ tool: AnnotationModuleTool) {
        activeTool = tool
        
        for index in internalTools.indices {
            internalTools[index].isSelected = (internalTools[index].id == tool.id)
        }
        
        print("\(tool.name) selected")
        
        if tool.name == "Keypoint Wizard" {
            runKeypointWizard()
        }
    }
    
    //TODO: Decide how to choose which courtDetection to run the wizard on.  Instead of a tool maybe a button in the drawerTile
    
    
    private func runKeypointWizard() {
        let currentCourtDetection = frameState.courtDetections
        // Determine which keypoints are missing from the committed annotation.
//        missingKeypoints = CourtKeypointLabels.allKeypoints.filter { key in
//            let keypoint = currentCourtDetection.getKeypoint(for: key)
//            return keypoint.position == .zero
//        }
        
        if missingKeypoints.isEmpty {
            print("All keypoints are complete.")
            return
        }
        
        // Set up the wizard interface.
//        drawerManager.clearTiles()
//        drawerManager.addTile(courtModel.CourtDrawingView()) //Court Drawing View
//        drawerManager.addTile(generateWizardTile())
        
//        showDetectionDrawer = true
        isWizardActive = true
        currentKeypointIndex = 0
        currentKeypointName = missingKeypoints[currentKeypointIndex]
        print("Wizard started. Current keypoint: \(currentKeypointName ?? "none")")
    }
    
    /// Generates the wizard tile view.
    func generateWizardTile(module: CourtDetectionModule) -> DetectionTile {
//        print("Generating Keypoint Wizard Tile")
        return DetectionTile (title: "Keypoint Wizard", content: {KeypointWizardView(module: module)})
    }
    
    func handleTap(at point: CGPoint) {
        
        //Handle Keypoint Wizard Case
        guard isWizardActive, currentKeypointIndex < missingKeypoints.count else { return }
        handleWizardTapLocation(location: point)
        
    
    }
    
    func handleWizardTapLocation(location: CGPoint) {
//        // Ensure tap updates in real time
//        DispatchQueue.main.async {
//            self.wizardTapLocation = CGPoint(x: 0.5, y: 0.5)
//        }
//
//        // Get the existing temporary annotation for the current frame
//        var temporaryAnnotations: [CourtKeypointAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
//            ofType: .courtDetection,
//            forFrame: frameID.wrappedValue,
//            as: CourtKeypointAnnotation.self
//        )
//        
//        if temporaryAnnotations.isEmpty {
//            let newAnnotation = CourtKeypointAnnotation(data: CourtDetectionData(keypoints: [:]))
//            AnnotationManager.shared.addTemporaryAnnotation(newAnnotation, toFrame: frameID.wrappedValue)
//            temporaryAnnotations = [newAnnotation]
//        }
//        
//        // We work with the first temporary annotation.
//        var tempAnnotations = temporaryAnnotations.first!
//        
//
//        // Ensure a keypoint name is selected
//        guard let currentKeypointName = currentKeypointName else {
//            print("No current keypoint selected.")
//            return
//        }
//
//        tempAnnotations.data.keypoints[currentKeypointName] = CourtKeypoint(
//            position: location,
//            visibility: .visible
//        )
//
//        // ✅ Ensure update is stored in AnnotationManager
//        AnnotationManager.shared.updateAnnotation(tempAnnotations, inFrame: frameID.wrappedValue)
    }


    
    func handleDragChanged(at point: CGPoint) { }
    func handleDragEnded(at point: CGPoint) { }
    
    func moveToNextKeypoint() {
        print("Running moveToNextKeypoint")
        
//        // Get the committed annotation (the base for our wizard).
//        let committedAnnotations: [CourtKeypointAnnotation] = AnnotationManager.shared.getCommittedAnnotations(
//            ofType: .courtDetection,
//            forFrame: frameID.wrappedValue,
//            as: CourtKeypointAnnotation.self
//        )
//        
//        guard let committedAnnotation = committedAnnotations.first else {
//            print("No committed annotation available.")
//            return
//        }
//        
//        // Check that there is a temporary annotation with an updated keypoint for the current key.
//        let tempAnnotations: [CourtKeypointAnnotation] = AnnotationManager.shared.getTemporaryAnnotations(
//            ofType: .courtDetection,
//            forFrame: frameID.wrappedValue,
//            as: CourtKeypointAnnotation.self
//        )
//        
//        guard let tempAnnotation = tempAnnotations.first(where: { annotation in
//            if let keypoint = annotation.data.keypoints[currentKeypointName ?? ""] {
//                return keypoint.position != .zero
//            }
//            return false
//        }) else {
//            print("No temporary annotation with updated position found for keypoint: \(currentKeypointName ?? "none")")
//            // Instead of exiting the wizard, simply do not move on.
//            return
//        }
//        
//        // Commit the temporary annotation’s keypoint to the committed annotation.
//        // For simplicity, we assume you update the committed annotation with the new keypoint.
//        var updatedCommitted = committedAnnotation
//        if let newKeypoint = tempAnnotation.data.keypoints[currentKeypointName ?? ""] {
//            updatedCommitted.data.keypoints[currentKeypointName ?? ""] = newKeypoint
//        }
//        
//        
//        AnnotationManager.shared.updateAnnotation(updatedCommitted, inFrame: frameID.wrappedValue)
//        
//        print("Committed keypoint \(currentKeypointName ?? "none"). Current committed data: \(updatedCommitted.data)")
//        
//        // Update the missing keypoints list.
//        let updatedMissing = CourtKeypointLabels.allKeypoints.filter { !updatedCommitted.data.keypoints.keys.contains($0) }
//        missingKeypoints = updatedMissing
//        
//        // If there are still missing keypoints, move on.
//        if currentKeypointIndex < missingKeypoints.count - 1 {
//            currentKeypointIndex += 1
//            currentKeypointName = missingKeypoints[currentKeypointIndex]
//            print("Moving to next keypoint: \(currentKeypointName ?? "none")")
//        } else {
//            print("Keypoint Wizard Complete!")
//            isWizardActive = false
//            showDetectionDrawer = false
//        }
    }

    
//    func annotationDetailView(for annotation: any BaseAnnotation, frameID: String) -> AnyView {
//        // Always return the standard (non-wizard) detail view for now.
//        return AnyView(standardAnnotationDetailView(for: annotation))
//    }
    
//    func updateKeypointVisibility(_ visibility: CourtKeypointVisibility) {
//        
//    }

    // MARK: - Wizard View
    struct KeypointWizardView: View {
        @EnvironmentObject var frameState: FrameState
        @ObservedObject var module: CourtDetectionModule

        var body: some View {
            // Compute the current keypoint
            let currentKey: String? = module.missingKeypoints.indices.contains(module.currentKeypointIndex)
            ? module.missingKeypoints[module.currentKeypointIndex]
                : nil
            
            print("Current Keypoint \(String(describing: currentKey))")

            let currentFriendly: String = {
                if let currentKey = currentKey {
                    return CourtKeypointLabels.friendlyNames[currentKey] ?? currentKey
                } else {
                    return ""
                }
            }()

            return VStack(alignment: .leading) {
                //Scrollable List of Missing Keypoints
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(module.missingKeypoints, id: \.self) { key in
                            let friendly = CourtKeypointLabels.friendlyNames[key] ?? key
                            HStack {
                                Text(friendly)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
//                                Spacer()
                                if let current = currentKey, key == current {
//                                    Text("⟶ Current")
//                                        .font(.caption)
//                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(2)
                            .background((currentKey != nil && key == currentKey!) ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                        }
                    }
//                    .padding(.horizontal)
                }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.4)

                Divider()
                    .padding(.vertical, 8)

                if let _ = currentKey {
                    HStack {
                        Button("Out of Frame") {
//                            module.updateKeypointVisibility(.outOfFrame)
                        };
                        Button("Occluded") {
//                            module.updateKeypointVisibility(.occluded)
                        };
                        Button("Visible") {
//                            module.updateKeypointVisibility(.visible)
                        }
                    }
                } else {
                    Text("All keypoints placed!")
                        .font(.body)
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                }

                HStack {
                    Button(action: module.moveToNextKeypoint) {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(currentKey != nil ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(currentKey == nil)

                    Button(action: {
                        module.isWizardActive = false
//                        module.showDetectionDrawer = false
                    }) {
                        Text("Finish")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .frame(height: 30)
            }
            .padding()
        }
    }

    
    // MARK: - Standard Detail View
//    private func standardAnnotationDetailView(for annotation: any BaseAnnotation) -> some View {
//        guard let courtAnnotation = annotation as? CourtKeypointAnnotation else {
//            return AnyView(Text("Invalid Annotation"))
//        }
//        
//        return AnyView(
//            ScrollView {
//                VStack(alignment: .leading) {
//                    Text("Court Keypoint Details")
//                        .font(.headline)
//                        .padding(.bottom, 5)
//                    
//                    ForEach(CourtKeypointLabels.allKeypoints, id: \.self) { key in
//                        let friendly = CourtKeypointLabels.friendlyNames[key] ?? key
//                        HStack {
//                            Text(friendly)
//                                .font(.subheadline)
//                                .frame(width: 200, alignment: .leading)
//                            Spacer()
//                            if let keypoint = courtAnnotation.data.keypoints[key] {
//                                Text(String(format: "(%.2f, %.2f)", keypoint.position.x, keypoint.position.y))
//                                    .font(.caption)
//                                    .foregroundColor(.gray)
//                                Picker("", selection: Binding(
//                                    get: {
//                                        keypoint.visibility
//                                    },
//                                    set: { newValue in
//                                        var updatedAnnotation = courtAnnotation
//                                        updatedAnnotation.data.keypoints[key]?.visibility = newValue
//                                        AnnotationManager.shared.updateAnnotation(updatedAnnotation, inFrame: courtAnnotation.id.uuidString)
//                                    }
//                                )) {
//                                    ForEach(CourtKeypointVisibility.allCases, id: \.self) { vis in
//                                        Text(vis.rawValue.capitalized).tag(vis)
//                                    }
//                                }
//                                .pickerStyle(SegmentedPickerStyle())
//                                .frame(width: 180)
//                            } else {
//                                Text("Not Set")
//                                    .font(.caption)
//                                    .foregroundColor(.red)
//                            }
//                        }
//                        .padding(.vertical, 4)
//                    }
//                    
//                    Button(action: {
//                        AnnotationManager.shared.commitAnnotation(annotation, fromFrame: courtAnnotation.id.uuidString)
//                    }) {
//                        Text("Commit Annotation")
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(Color.green)
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
//                    .padding(.top, 10)
//                    
//                    Button(action: {
//                        AnnotationManager.shared.deleteAnnotation(annotation, fromFrame: courtAnnotation.id.uuidString)
//                    }) {
//                        Text("Delete Annotation")
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(Color.red)
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
//                    .padding(.top, 5)
//                }
//                .padding()
//            }
//        )
//    }
}
