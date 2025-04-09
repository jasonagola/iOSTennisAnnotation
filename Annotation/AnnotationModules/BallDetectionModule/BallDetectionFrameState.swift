//
//  BallDetectionFrameState.swift
//  Annotation
//
//  Created by Jason Agola on 3/31/25.
//

import SwiftUI
import SwiftData

extension FrameState {
    //FIXME: Need to handle outside module processes and prevent circluar variable dependency
    struct InsertBallDetectionTask: FrameStateTask {
        var priority: Int = 0
        
        let detection: BallDetection

        func execute(in frameState: FrameState) async {
            frameState.safeContext.insert(detection)
            try? frameState.safeContext.save()
//            await frameState.loadBallDetections() // or a general `refresh()` method
        }
    }
    
    
    struct UpdateBallDetectionTask: FrameStateTask {
        var priority: Int = 0
        let detection: BallDetection
        let behavior: BallBehaviorOptions
        let visibility: BallVisibility

        func execute(in frameState: FrameState) async {
            detection.behavior = behavior
            detection.visibility = visibility.rawValue
            do {
                try frameState.safeContext.save()
                print("BallDetection \(detection.id) updated and saved.")
            } catch {
                print("Error updating ball detection: \(error)")
            }
        }
    }
    
    // MARK: - BallAnnotationManangement
    func loadBallDetections() async {
        guard let frameUUID = currentFrameUUID else {
            print("⚠️ loadBallDetections: No currentFrameUUID available")
            return
        }

        let descriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate { $0.frameUUID == frameUUID }
        )

        do {
            let results = try safeContext.fetch(descriptor)
            await MainActor.run {
                self.ballDetections = results
                print("✅ Loaded \(results.count) ball detections for frame \(frameUUID)")
            }
        } catch {
            print("❌ Error loading ball detections: \(error)")
        }
    }
    
    // MARK: Add Ball Annotation
    func addBallAnnotation(_ detection: BallDetection, frameUUID: UUID) {
//        guard let frameUUID = currentFrameUUID else {
//            print("⚠️ addBallAnnotation: No currentFrameUUID available")
//            return
//        }

        // Check for similar detection already in annotations
        let isDuplicate = ballDetections.contains(where: { existing in
            existing.frameUUID == frameUUID &&
            abs(existing.computedCenterX - detection.computedCenterX) < 0.01 &&
            abs(existing.computedCenterY - detection.computedCenterY) < 0.01 &&
            abs(existing.boundingBoxWidth - detection.boundingBoxWidth) < 0.01 &&
            abs(existing.boundingBoxHeight - detection.boundingBoxHeight) < 0.01
        })

        guard !isDuplicate else {
            print("⚠️ addBallAnnotation: Duplicate detection, skipping enqueue.")
            return
        }

        enqueue(InsertBallDetectionTask(detection: detection))
    }
    
    // MARK: Delete Ball Annotation
    func deleteBallAnnotation(_ detection: BallDetection) async {
        safeContext.delete(detection)
        do {
            try safeContext.save()
            print("🗑️ BallDetection deleted and saved")
        } catch {
            print("❌ Error deleting ball detection: \(error)")
        }
        await loadBallDetections()
        await triggerRefresh()
    }
    
    //FIXME: DO I NEED THIS?  Implement this in the detection tile on change handler?
    func updateBallDetection(_ detection: BallDetection, with behavior: BallBehaviorOptions, visibility: BallVisibility) async {
        // Update the detection's behaviors and visibility.
        detection.behavior = behavior
        detection.visibility = visibility.rawValue

        do {
            try safeContext.save()
            print("BallDetection updated and saved.")
        } catch {
            print("Error updating ball detection: \(error)")
        }
    }
    
    //MARK: Copy Previous Detection Behavior
    func copyPreviousDetectionBehavior() async {
        //TODO: Previous Frame Behavior Detections.
        
        //Get Previous Frame UUID
        guard let currentIndex = frames.firstIndex(where: { $0.id == currentFrameUUID }),
              currentIndex > 0 else {
            print("No previous frame available.")
            return
        }
        
        let previousFrameUUID = frames[currentIndex - 1].id
        
        //Fetch Last Frames BallDetections and Resolve Closest Detection
        
        let descriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate{ $0.frameUUID == previousFrameUUID }
        )
        
        do {
            let previousDetections = try safeContext.fetch(descriptor)
            guard !previousDetections.isEmpty else {
                print("No previous frame detections available.")
                return
            }
            
            // For each current detection, find the closest detection from the previous frame.
            for currentDetection in ballDetections {
                let currentCenter = CGPoint(x: currentDetection.computedCenterX,
                                            y: currentDetection.computedCenterY)
                
                guard let closestDetection = previousDetections.min(by: { (det1, det2) -> Bool in
                    let center1 = CGPoint(x: det1.computedCenterX, y: det1.computedCenterY)
                    let center2 = CGPoint(x: det2.computedCenterX, y: det2.computedCenterY)
                    return distance(from: currentCenter, to: center1) < distance(from: currentCenter, to: center2)
                }) else {
                    print("No previous detection found for current detection \(currentDetection.id)")
                    continue
                }
                
                // Enqueue an update task that copies the behavior and visibility.
                let updateTask = UpdateBallDetectionTask(
                    detection: currentDetection,
                    behavior: closestDetection.behavior,
                    visibility: BallVisibility(rawValue: closestDetection.visibility) ?? .visible
                )
                enqueue(updateTask)
                
                print("Enqueued update for detection \(currentDetection.id) using previous detection \(closestDetection.id)")
            }
        } catch {
            print("Error fetching previous frame detections: \(error)")
        }
    }

    /// Helper to calculate Euclidean distance between two CGPoints.
    func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    
    //MARK: String together Ball Id
    
}
