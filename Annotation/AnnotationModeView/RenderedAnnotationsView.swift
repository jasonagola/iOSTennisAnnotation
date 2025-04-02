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
    
    var body: some View {
        ZStack {
            if selectedVisibleAnnotations.contains("Ball Detection") {
                AnnotationRenderUtilities.renderBallDetectionAnnotations(
                    imageSize: imageSize,
                    ballDetections: frameState.ballDetections,
                    selectedAnnotationUUID: frameState.selectedAnnotationUUID
                )
            }
            // Additional annotation modules as needed.
        }  
    }
}
