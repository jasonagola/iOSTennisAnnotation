//
//  CourtDetectionsTile.swift
//  Annotation
//
//  Created by Jason Agola on 3/31/25.
//

import SwiftUI

class CourtDetectionTileViewModel: ObservableObject {
    private var frameState: FrameState
    
    init(frameState: FrameState) {
        self.frameState = frameState
    }
    //Run Keypoint Wizard based on missed detections
    
    //Add Court
    
    func selectCourtDetection(_ detection: CourtDetection) async {
        await MainActor.run {
            frameState.selectedAnnotationUUID = detection.id
        }
    }
    
    func addCourtDetection(_ detection: CourtDetection) async {
        await MainActor.run {
            frameState.addCourtDetection(detection)
        }
    }
    
    //Delete Court
    
    
    
}

struct CourtDetectionsTileView: View {
    private var frameState: FrameState
    @StateObject var viewModel: CourtDetectionTileViewModel
    
    init(frameState: FrameState) {
        self.frameState = frameState
        _viewModel = StateObject(wrappedValue: CourtDetectionTileViewModel(frameState: frameState))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
    }
        
    @ViewBuilder
    var content: some View {
        if frameState.courtDetections.isEmpty {
            Text("No Court Detections")
                .foregroundColor(.gray)
        } else {
            ForEach(frameState.courtDetections, id: \.id) { detection in
                
            }
        }
    }
}

struct CourtDetectionItemView: View {
    let detection: CourtDetection
    let isSelected: Bool
    let onDelete: () -> Void
    @EnvironmentObject var frameState: FrameState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(isSelected ? .red : .gray)
                }
                .disabled(isSelected)
            }
            
            //CourtDetection Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Court Detection ID: \(detection.id.uuidString.prefix(8))")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("Court Priority")
                CourtPrioritySelection
            }
        }
    }
    
    private func backgroundColor(for option: CourtPriority) -> Color {
        if detection.courtPriority == option {
            switch option {
            case .primary:
                return Color.green.opacity(0.5)
            case .secondary:
                return Color.red.opacity(0.5)
            }
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    private var CourtPrioritySelection: some View {
        HStack(spacing: 6) {
            ForEach(CourtPriority.allCases, id: \.self) { option in
                Text(option.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    .background(backgroundColor(for: option))
                    .onTapGesture {
                        detection.courtPriority = option
                    }
            }
        }
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
        .padding(0.5)
    }
}
