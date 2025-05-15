    //
    //  BallDetectionTile.swift
    //  Annotation
    //
    //  Created by Jason Agola on 3/25/25.
    //

    import SwiftUI
    import SwiftData
    import Combine

    // MARK: - DetectionTileViewModel
    /// Manages the ball detection data for the current frame and tracks the selected detection.
class BallDetectionTileViewModel: ObservableObject {
    @Published var ballAnnotations: [BallDetection] = []
    //    @Published var selectedDetectionID: UUID? = nil
    @Published var needsRefresh: UUID = UUID() // Add this if you want view to update
    
    private var frameState: FrameState
    private var modelContext: ModelContext
    private var cancellables: Set<AnyCancellable> = [] // Use a Set to manage multiple subscriptions
    
    init(frameState: FrameState, modelContext: ModelContext) {
        self.frameState = frameState
        self.modelContext = modelContext
    }
    
    public func update() {
        //        loadBallAnnotations()
    }
    
    /// Sets the given detection as selected.
    func selectDetection(_ detection: BallDetection) async {
        await MainActor.run {
            frameState.selectedAnnotationUUID = detection.id
            self.needsRefresh = UUID()
        }
    }
    
    /// Deletes the currently selected detection.
    func deleteSelectedDetection(_ detection: BallDetection) async {
        print("Attempting to delete detection: \(detection)")
        let selectedID = frameState.selectedAnnotationUUID
        if let detection = frameState.ballDetections.first(where: { $0.id == selectedID }) {
            await frameState.deleteBallAnnotation(detection)
            await MainActor.run {
                // Update accordingly, e.g. setting to a default UUID or leaving it unchanged.
            }
        }
    }
    
    
    /// Placeholder for an editing action.
    func editSelectedDetection() async {
       
        let selectedID = frameState.selectedAnnotationUUID
        if let detection = frameState.ballDetections.first(where: { $0.id == selectedID }) {
            // Implement your editing logic here.
        } else  {
            
        }
    }
    
}


    // MARK: - BallDetectionTile
    /// The main view for displaying ball detections for the current frame.
struct BallDetectionTile: View {
    private var frameState: FrameState
    @StateObject private var viewModel: BallDetectionTileViewModel
    //    let title: String = "Ball Detection"
    
    /// Initialize with a FrameState and a ModelContext provided by the parent.
    init(frameState: FrameState, modelContext: ModelContext) {
        self.frameState = frameState
        _viewModel = StateObject(wrappedValue: BallDetectionTileViewModel(frameState: frameState, modelContext: modelContext))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
//        id(viewModel.needsRefresh)
//        .background(Color(UIColor.systemBackground))
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
//        .padding(12)
        .cornerRadius(8)
    }
        
    @ViewBuilder
    var content: some View {
        if frameState.ballDetections.isEmpty {
            Text("No ball detections available")
                .foregroundColor(.gray)
        } else {
            VStack {
                HStack {
                    Button {
                        Task { await frameState.copyPreviousDetectionBehavior() }
                    } label: {
                        Image(systemName: "document.on.document")
                    }
                }
                .background(Color.red)
                .cornerRadius(5)
                .padding(12)
                
                ForEach(frameState.ballDetections, id: \.id) { detection in
                    BallDetectionItemView(
                        detection: detection,
                        onDelete: {
                            Task {
                                await viewModel.selectDetection(detection)
                                await viewModel.deleteSelectedDetection(detection)
                            }
                        }
                    )
                    .onTapGesture {
                        Task {
                            await viewModel.selectDetection(detection)
                        }
                        
                    }// Optional: suppress default styling
                }
            }
            .padding(5)
        }
    }
    
    // MARK: - BallDetectionItemView
    /// A view for rendering a single BallDetection with a visual indicator if selected.
    struct BallDetectionItemView: View {
        let detection: BallDetection
        let onDelete: () -> Void
        @EnvironmentObject private var frameState: FrameState

        private var isSelected: Bool {
            frameState.selectedAnnotationUUID == detection.id
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Delete Button - Always visible but conditional style
                HStack {
                    Button(action: toggleKeyFrame) {
                        Image(systemName: "star")
                            .foregroundColor(isSelected ? .yellow : .white)
                    }
                    .disabled(!isSelected)
                    
                    Button(action: viewRally) {
                        Image(systemName: "tennisball")
                            .foregroundStyle(isSelected ? .green : .white)
                    }
                    
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(isSelected ? .red : .white)
                    }
                    .disabled(!isSelected)
                }
                .padding(5)
                .background(Color.blue.opacity(1))
                
                // Detection Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detection ID: \(detection.id.uuidString.prefix(8))")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("Center: (\(detection.computedCenterPoint.x, specifier: "%.2f"), \(detection.computedCenterPoint.y, specifier: "%.2f"))")
                        .font(.caption2)
                    
                    Text("BBox: \(Int(detection.boundingBoxWidth)) x \(Int(detection.boundingBoxHeight))")
                        .font(.caption2)
                }
                .padding(5)
                .background(Color.black.opacity(0.9))
                
                // Show options only if selected
                if frameState.selectedAnnotationUUID == detection.id {
                    visibilityRow
                    behaviorRow
                }
            }
            .background(isSelected ? Color.black.opacity(0.4) : Color.gray.opacity(0.2))
//            .padding(12)
            .cornerRadius(10)
        }
        
        // MARK: - Visibility Options
        private var visibilityRow: some View {
            HStack(spacing: 6) {
                ForEach(BallVisibility.allCases, id: \.self) { option in
                    Text(option.rawValue.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            detection.visibility == option.rawValue
                            ? (option == .visible ? Color.green.opacity(0.5) : Color.red.opacity(0.5))
                            : Color.gray.opacity(0.1)
                        )
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                        .onTapGesture {
                            detection.visibility = option.rawValue
                        }
                }
            }
            .background(.white.opacity(0.5))
            .cornerRadius(10)
            .padding(5)
        }
        
        // MARK: - Behavior Options
        private var behaviorRow: some View {
            VStack(alignment: .leading, spacing: 4) {
               Text("Behavior").font(.caption).foregroundStyle(.secondary)
               HFlow(spacing: 6) { // Assuming HFlow exists
                   ForEach(BallBehaviorOptions.all as [BallBehaviorOptions], id: \.rawValue) { (option: BallBehaviorOptions) in
                       let isActive = detection.behavior.contains(option)
                       Text(option.displayName)
                           .font(.caption)
                           .padding(.horizontal, 8)
                           .padding(.vertical, 4)
                           .background(isActive ? Color.green.opacity(0.6) : Color.gray.opacity(0.2))
                           .foregroundColor(isActive ? .white : .primary)
                           .clipShape(Capsule())
                           .onTapGesture {
                               toggleBehavior(option)
                           }
                   }
               }
            }
            .padding(5)
        }
    
        private func toggleBehavior(_ option: BallBehaviorOptions) {
            if detection.behavior.contains(option) {
                detection.behavior.remove(option)
            } else {
                detection.behavior.insert(option)
            }
            print("Updated behaviors: \(detection.behavior)")
        }
        
        private func toggleKeyFrame() {
            
        }
        
        private func viewRally() {
            
        }
    }
}


// TODO: IMplement a previous frame copy mechanism.  Find near Detections and Copy behavior.  Also implement a track/rallyID to string together the same ball temporally


