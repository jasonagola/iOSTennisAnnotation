//
//  ToolRenderOverlayView.swift
//  Annotation
//
//  Created by Jason Agola on 4/3/25.
//

import SwiftUI

struct ToolRenderOverlayView: View {
    @EnvironmentObject var frameState: FrameState
    let imageSize: CGSize
    let selectedAnnotationModule: (any AnnotationModule)?

    var body: some View {
        print("[ToolRenderOverlayView] Refresh triggered with token: \(frameState.toolRenderOverlayRefreshToken)")
        return ZStack {
            if let module = selectedAnnotationModule {
                module.renderToolOverlay(imageSize: imageSize)
            }
        }
        .id(frameState.toolRenderOverlayRefreshToken)
    }
}

