//
//  RenderedFrameAnnotations.swift
//  Annotation
//
//  Created by Jason Agola on 3/30/25.
//

import SwiftUI

struct RenderedAnnotationsView: View {
    @EnvironmentObject var frameState: FrameState
    let imageSize: CGSize
    let selectedVisibleAnnotations: Set<String>
    
    init(imageSize: CGSize, selectedVisibleAnnotations: Set<String>) {
        self.imageSize = imageSize
        self.selectedVisibleAnnotations = selectedVisibleAnnotations
        print("Selected Visible Annotations: \(selectedVisibleAnnotations)")
    }
    
    var body: some View {
        ZStack {
            // For example, if "Ball Detection" is one of the selected types:
            if selectedVisibleAnnotations.contains("Ball Detection") {
                AnnotationRenderUtilities.renderBallDetectionAnnotations(
                    imageSize: imageSize,
                    ballDetections: frameState.ballDetections,
                    selectedAnnotationUUID: frameState.selectedAnnotationUUID
                )
            }
            // Add conditions for other annotation types as needed.
        }
    }
}
