//
//  TappedAnnotationsStateHandler.swift
//  Annotation
//
//  Created by Jason Agola on 4/1/25.
//

import SwiftUI

func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
}

extension FrameState {
    // Run the tap behavior, updating annotations and possibly cycling
    func runTapBehavior(location: CGPoint, selectedVisibleAnnotations: Set<String>, selectedAnnotationModuleTitle: String?) async {
        await MainActor.run {
             previousAnnotationsAtTapLocation = annotationsAtTapLocation
        }
       
        // Get all annotations at the tap location asynchronously.
        let currentAnnotations = await getTapLocationAnnotations(location: location, selectedVisibleAnnotations: selectedVisibleAnnotations, selectedAnnotationModuleTitle: selectedAnnotationModuleTitle)
        
        // Update annotations at tap location.
        await MainActor.run {
            annotationsAtTapLocation = currentAnnotations
        }
        
        // If annotations are stacked, cycle through them.
        if !annotationsAtTapLocation.isEmpty {
            await cycleAnnotations()
        }
    }
    
    func getTapLocationAnnotations(location: CGPoint, selectedVisibleAnnotations: Set<String>, selectedAnnotationModuleTitle: String?) async -> [UUID] {
        var currentTapLocationAnnotations: [UUID] = []
        
        if selectedAnnotationModuleTitle == "Ball Detection" || selectedVisibleAnnotations.contains("Ball Detection") {
            // Access ballDetections from the frameState.
            let foundDetections = findAnnotationsAtTapLocation(
                location: location,
                detections: ballDetections
            )
            currentTapLocationAnnotations.append(contentsOf: foundDetections)
        }
        
        //TODO: Make decision on unique location member because CourtDetection doesnt share a boundingBox value.
        
        if selectedAnnotationModuleTitle == "Court Detection" || selectedVisibleAnnotations.contains("Court Detection") {
            // Access courtDetections from the frameState.
            let foundDetections = findAnnotationsAtTapLocation(
                location: location,
                detections: courtDetections
            )
            currentTapLocationAnnotations.append(contentsOf: foundDetections)
        }
        
        return currentTapLocationAnnotations
    }
    
    // Find annotations at a given location based on the detection type.
    func findAnnotationsAtTapLocation(location: CGPoint, detections: [Any]) -> [UUID] {
        var foundAnnotations: [UUID] = []
        
        for detection in detections {
            if let detection = detection as? BallDetection {
                let boundingBox = CGRect(
                    x: detection.boundingBoxMinX,
                    y: detection.boundingBoxMinY,
                    width: detection.boundingBoxWidth,
                    height: detection.boundingBoxHeight
                )
                //TODO: ADD Threshold for ball detections as well 
                if boundingBox.contains(location) {
                    foundAnnotations.append(detection.id)
                }
            } else if let detection = detection as? CourtDetection {
                // For CourtDetection, iterate over its keypoints.
                let threshold: CGFloat = 20.0  // Define a threshold radius for selection.
                for keypoint in detection.keypoints {
                    if distance(from: keypoint.position, to: location) <= threshold {
                        foundAnnotations.append(keypoint.id)
                    }
                }
            }
        }
        return foundAnnotations
    }
    
    // Cycle through annotations when tapped multiple times.
    func cycleAnnotations() async {
        guard !annotationsAtTapLocation.isEmpty else { return }
        
        // Use the current selected annotation value (always non-optional)
        let currentSelected = selectedAnnotationUUID
        if annotationsAtTapLocation.contains(currentSelected),
           let currentIndex = annotationsAtTapLocation.firstIndex(of: currentSelected) {
            let nextIndex = (currentIndex + 1) % annotationsAtTapLocation.count
            await MainActor.run {
                selectedAnnotationUUID = annotationsAtTapLocation[nextIndex]
            }
        } else {
            // If the current selection isn't in the tap location list, select the first one.
            await MainActor.run {
                selectedAnnotationUUID = annotationsAtTapLocation.first!
            }
        }
    }
}

