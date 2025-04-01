//
//  CourtModel.swift
//  Annotation
//
//  Created by Jason Agola on 2/3/25.
//

import SwiftUI
import Foundation
import CoreGraphics
import simd

class CourtModelKeypoint {
    var x: Double
    var y: Double
    
    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    
    func applyHomography(_ H: matrix_float3x3) -> CourtModelKeypoint {
        let point = simd_float3(Float(x), Float(y), 1.0)
        let transformed = H * point
        return CourtModelKeypoint(x: Double(transformed.x / transformed.z), y: Double(transformed.y / transformed.z))
    }
}

class CourtModel {
    static let COURT_LENGTH = 78.0
    static let SINGLES_WIDTH = 27.0
    static let DOUBLES_WIDTH = 36.0
    static let SERVICE_LINE_DISTANCE = 21.0
    static let NET_POSITION = COURT_LENGTH / 2
    static let CENTER_MARK_LENGTH = 0.333
    static let LINE_WIDTH = 0.167
    static let BASELINE_WIDTH = 0.333
    static let SIDELINE_OFFSET = (DOUBLES_WIDTH - SINGLES_WIDTH) / 2
    
    var keypoints: [String: CourtModelKeypoint] = [:]
    
    init() {
        keypoints = [
            "NC_LDS_BL": CourtModelKeypoint(x: 0.0, y: 0.0),
            "NC_LSS_BL": CourtModelKeypoint(x: CourtModel.SIDELINE_OFFSET, y: 0.0),
            "NC_ML_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH / 2, y: 0.0),
            "NC_RSS_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH - CourtModel.SIDELINE_OFFSET, y: 0.0),
            "NC_RDS_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH, y: 0.0),
            "NC_LSS_SL": CourtModelKeypoint(x: CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION - CourtModel.SERVICE_LINE_DISTANCE),
            "NC_ML_SL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH / 2, y: CourtModel.NET_POSITION - CourtModel.SERVICE_LINE_DISTANCE),
            "NC_RSS_SL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH - CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION - CourtModel.SERVICE_LINE_DISTANCE),
            "FC_LSS_SL": CourtModelKeypoint(x: CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION + CourtModel.SERVICE_LINE_DISTANCE),
            "FC_ML_SL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH / 2, y: CourtModel.NET_POSITION + CourtModel.SERVICE_LINE_DISTANCE),
            "FC_RSS_SL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH - CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION + CourtModel.SERVICE_LINE_DISTANCE),
            "FC_LDS_BL": CourtModelKeypoint(x: 0.0, y: CourtModel.COURT_LENGTH),
            "FC_LSS_BL": CourtModelKeypoint(x: CourtModel.SIDELINE_OFFSET, y: CourtModel.COURT_LENGTH),
            "FC_ML_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH / 2, y: CourtModel.COURT_LENGTH),
            "FC_RSS_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH - CourtModel.SIDELINE_OFFSET, y: CourtModel.COURT_LENGTH),
            "FC_RDS_BL": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH, y: CourtModel.COURT_LENGTH),
            "NET_LDS": CourtModelKeypoint(x: 0.0, y: CourtModel.NET_POSITION),
            "NET_LSS": CourtModelKeypoint(x: CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION),
            "NET_ML": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH / 2, y: CourtModel.NET_POSITION),
            "NET_RSS": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH - CourtModel.SIDELINE_OFFSET, y: CourtModel.NET_POSITION),
            "NET_RDS": CourtModelKeypoint(x: CourtModel.DOUBLES_WIDTH, y: CourtModel.NET_POSITION)
        ]
    }
    
    func applyHomographyToAll(_ H: matrix_float3x3) {
        for (key, point) in keypoints {
            keypoints[key] = point.applyHomography(H)
        }
    }
    
    func computeHomography(from sourcePoints: [simd_float2], to destinationPoints: [simd_float2]) -> matrix_float3x3? {
        guard sourcePoints.count == 4, destinationPoints.count == 4 else { return nil }
        
        // Convert to a suitable matrix format for calculation
        let homography = simd_float3x3(columns: (
            simd_float3(destinationPoints[0].x, destinationPoints[1].x, destinationPoints[2].x),
            simd_float3(destinationPoints[0].y, destinationPoints[1].y, destinationPoints[2].y),
            simd_float3(1, 1, 1)
        ))
        
        return homography
    }
    
    /// A SwiftUI view that draws a court using a CourtModel and displays its keypoints.
    func CourtDrawingView() -> AnyView {
        
        return AnyView(
            GeometryReader { geometry in
                // Compute a scale factor so that the doubles court fits in the view.
                // We assume the court dimensions are defined in CourtModel.
                let courtWidth = CGFloat(CourtModel.DOUBLES_WIDTH)
                let courtLength = CGFloat(CourtModel.COURT_LENGTH)
                let scale = min(geometry.size.width / courtWidth, geometry.size.height / courtLength)
                
                // Center the court in the available space.
                let offsetX = (geometry.size.width - courtWidth * scale) / 2
                let offsetY = (geometry.size.height - courtLength * scale) / 2
                
                ZStack {
                    // Draw the outer court boundary.
                    Path { path in
                        let rect = CGRect(x: offsetX, y: offsetY, width: courtWidth * scale, height: courtLength * scale)
                        path.addRect(rect)
                    }
                    .stroke(Color.white, lineWidth: 2)
                    
                    // (Optional) Draw additional court lines.
                    // For example, you could draw the service line, net, etc.
                    // Example: Draw a horizontal line for the net.
                    Path { path in
                        let netY = offsetY + (CGFloat(CourtModel.NET_POSITION) * scale)
                        path.move(to: CGPoint(x: offsetX, y: netY))
                        path.addLine(to: CGPoint(x: offsetX + courtWidth * scale, y: netY))
                    }
                    .stroke(Color.gray, lineWidth: 1)
                    
                    // Draw keypoints as small circles.
                    ForEach(Array(self.keypoints.keys), id: \.self) { key in
                        if let modelPoint = self.keypoints[key] {
                            // Convert model coordinates (which are in the court’s coordinate space)
                            // to view coordinates by scaling and offsetting.
                            let x = CGFloat(modelPoint.x) * scale + offsetX
                            let y = CGFloat(modelPoint.y) * scale + offsetY
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: y)
                        }
                    }
                }
                .background(Color.black) // or any background you prefer
            })
        }
    }
    

