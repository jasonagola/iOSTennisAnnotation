//
//  AnnotationRenderUtilities.swift
//  Annotation
//
//  Created by Jason Agola on 3/30/25.
//

import SwiftUI

struct AnnotationRenderUtilities {
    /// Renders ball detection annotations.
    static func renderBallDetectionAnnotations(
        imageSize: CGSize,
        ballDetections: [BallDetection],
        selectedAnnotationUUID: UUID? = nil
    ) -> some View {
        // Transform detections into image space.
        print("Running Render Utilities: renderBallDetectionAnnotations")
        let annotationsInImageSpace = ballDetections.map { detection -> (CGRect, UUID) in
            let boundingBox = CGRect(
                x: detection.boundingBoxMinX * imageSize.width,
                y: detection.boundingBoxMinY * imageSize.height,
                width: detection.boundingBoxWidth * imageSize.width,
                height: detection.boundingBoxHeight * imageSize.height
            )
            return (boundingBox, detection.id)
        }
        return ForEach(annotationsInImageSpace, id: \.1) { (boundingBox, uuid) in
            Rectangle()
                .stroke(uuid == selectedAnnotationUUID ? Color.blue : Color.red, lineWidth: 4)
                .frame(width: boundingBox.width, height: boundingBox.height)
                .position(x: boundingBox.midX, y: boundingBox.midY)
        }
    }
    
    
//    static func renderCourtDetectionAnnotations(
//        imageSize:CGSize,
//        courtKeypointDetections: [KeypointDetection],
//        selectedAnnotationUUID: UUID? = nil
//    ) -> some View {
//        
//    }
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
//    )
    // Add similar static functions for other annotation types.
}
