//
//  AnnotationsManager.swift
//  Annotation
//
//  Created by Jason Agola on 1/14/25.


import SwiftData
import SwiftUI

//Define Annotation Types
enum AnnotationType: String, Codable {
    case ballDetection
    case courtDetection
    case personDetection
}

//Project Table
@Model
final class Project {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()

    // Relationship to frames
    @Relationship(deleteRule: .cascade) var frames: [Frame] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Frame {
    @Attribute(.unique) var id: UUID = UUID()
    var frameName: String
    var project: Project
    
    // Store relative paths instead of absolute paths.
    var imagePath: String?
    var thumbnailPath: String?

    init(frameName: String, project: Project, imagePath: String? = nil, thumbnailPath: String? = nil) {
        self.frameName = frameName
        self.project = project
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
    }

    // Helper to construct an absolute path from a relative path.
    private func absolutePath(from relativePath: String) -> String? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to get Documents directory.")
            return nil
        }
        return documentsURL.appendingPathComponent(relativePath).path
    }
    
    // Computed property to load the full image.
    var image: UIImage? {
        guard let relPath = imagePath,
              let fullPath = absolutePath(from: relPath) else {
            return nil
        }
//        print("Attempting to load full image from: \(fullPath)")
        return UIImage(contentsOfFile: fullPath)
    }
    
    // Computed property to load the thumbnail.
    var thumbnail: UIImage? {
        guard let relPath = thumbnailPath,
              let fullPath = absolutePath(from: relPath) else {
            print("No thumbnail path to load from")
            return nil
        }
//        let exists = FileManager.default.fileExists(atPath: fullPath)
//        print("Attempting to load thumbnail from: \(fullPath), exists: \(exists)")
        return UIImage(contentsOfFile: fullPath)
    }
}

enum AnnotationStatus: String, Codable {
    case temporary
    case confirmed
}

@Model
final class AnnotationRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var annotationType: AnnotationType.RawValue
    var status: AnnotationStatus
    var isSelected: Bool = false

    // Reference to the Frame it belongs to
    var frame: Frame?

    init(annotationType: AnnotationType, status: AnnotationStatus, frame: Frame? = nil) {
        self.annotationType = annotationType.rawValue
        self.status = status
        self.frame = frame
    }
}

@Model
final class BallDetection {
    @Attribute(.unique) var id: UUID = UUID()
    
    var boundingBoxMinX: Double
    var boundingBoxMinY: Double
    var boundingBoxWidth: Double
    var boundingBoxHeight: Double
    
    var computedCenterX: Double
    var computedCenterY: Double

    var roiBoundingBoxOriginX: Double
    var roiBoundingBoxOriginY: Double
    var roiBoundingBoxWidth: Double
    var roiBoundingBoxHeight: Double
    
    var visibility: BallVisibility.RawValue
    
    // Mark behavior as an attribute and provide a default empty array.
    @Attribute var behavior: BallBehaviorOptions = []
    
    var annotationRecord: AnnotationRecord?
    
    var frameUUID: UUID?

    init(boundingBox: CGRect,
         computedCenter: CGPoint,
         roiBoundingBox: CGRect,
         visibility: BallVisibility,
         behavior: BallBehaviorOptions = [],
         annotationRecord: AnnotationRecord? = nil,
         frameUUID: UUID? = nil) {
        self.boundingBoxMinX = boundingBox.origin.x
        self.boundingBoxMinY = boundingBox.origin.y
        self.boundingBoxWidth = boundingBox.width
        self.boundingBoxHeight = boundingBox.height
        
        self.computedCenterX = computedCenter.x
        self.computedCenterY = computedCenter.y

        self.roiBoundingBoxOriginX = roiBoundingBox.origin.x
        self.roiBoundingBoxOriginY = roiBoundingBox.origin.y
        self.roiBoundingBoxWidth = roiBoundingBox.width
        self.roiBoundingBoxHeight = roiBoundingBox.height

        self.visibility = visibility.rawValue
        self.behavior = behavior

        self.annotationRecord = annotationRecord
        
        self.frameUUID = frameUUID
    }
    
    // Computed properties...
    var boundingBoxRect: CGRect {
        CGRect(x: boundingBoxMinX, y: boundingBoxMinY, width: boundingBoxWidth, height: boundingBoxHeight)
    }

    var computedCenterPoint: CGPoint {
        CGPoint(x: computedCenterX, y: computedCenterY)
    }
    
    var roiBoundingBoxRect: CGRect {
        CGRect(x: roiBoundingBoxOriginX, y: roiBoundingBoxOriginY, width: roiBoundingBoxWidth, height: roiBoundingBoxHeight)
    }
}


enum BallVisibility: String, Codable, CaseIterable {
    case visible, occluded, notVisible
}

struct BallBehaviorOptions: OptionSet, Codable {
    let rawValue: Int

    static let inHand          = BallBehaviorOptions(rawValue: 1 << 0)
    static let inFlight        = BallBehaviorOptions(rawValue: 1 << 1)
    static let still           = BallBehaviorOptions(rawValue: 1 << 2)
    static let hit             = BallBehaviorOptions(rawValue: 1 << 3)
    static let nearCourtBounce = BallBehaviorOptions(rawValue: 1 << 4)
    static let farCourtBounce  = BallBehaviorOptions(rawValue: 1 << 5)
    static let otherBounce     = BallBehaviorOptions(rawValue: 1 << 6)
    static let behindNet       = BallBehaviorOptions(rawValue: 1 << 7)
    static let behindPerson    = BallBehaviorOptions(rawValue: 1 << 8)
    static let inPlay          = BallBehaviorOptions(rawValue: 1 << 9)
    static let outOfPlay       = BallBehaviorOptions(rawValue: 1 << 10)
    
    static let all: [BallBehaviorOptions] = [
        .inHand, .inFlight, .still, .hit,
        .nearCourtBounce, .farCourtBounce, .otherBounce,
        .behindNet, .behindPerson,
        .inPlay, .outOfPlay
    ]
    
    var displayName: String {
        switch self {
        case .inHand:          return "In Hand"
        case .inFlight:        return "In Flight"
        case .still:           return "Still"
        case .hit:             return "Hit"
        case .nearCourtBounce: return "Near Court Bounce"
        case .farCourtBounce:  return "Far Court Bounce"
        case .otherBounce:     return "Other Bounce"
        case .behindNet:       return "Behind Net"
        case .behindPerson:    return "Behind Person"
        case .inPlay:          return "In Play"
        case .outOfPlay:       return "Out of Play"
        default:               return "Unknown"
        }
    }
}


// MARK: - CourtKeypoint Model
@Model
final class CourtKeypoint {
    @Attribute(.unique) var id: UUID = UUID()
    var label: String
    var position: CGPoint
    var visibility: CourtKeypointVisibility

    init(label: String, position: CGPoint = .zero, visibility: CourtKeypointVisibility = .notVisible) {
        self.label = label
        self.position = position
        self.visibility = visibility
    }
}

// MARK: - CourtKeypointLabels
struct CourtKeypointLabels {
    static let allKeypoints: [String] = [
        "NC_LDS_BL", "NC_LSS_BL", "NC_ML_BL", "NC_RSS_BL", "NC_RDS_BL",
        "NC_LSS_SL", "NC_ML_SL", "NC_RSS_SL",
        "FC_LSS_SL", "FC_ML_SL", "FC_RSS_SL",
        "FC_LDS_BL", "FC_LSS_BL", "FC_ML_BL", "FC_RSS_BL", "FC_RDS_BL",
        "NET_LDS", "NET_LSS", "NET_ML", "NET_RSS", "NET_RDS"
    ]
    
    static let friendlyNames: [String: String] = [
        "NC_LDS_BL": "Near Court: Left Doubles Sideline Baseline",
        "NC_LSS_BL": "Near Court: Left Singles Sideline Baseline",
        "NC_ML_BL": "Near Court: Middle Line Baseline",
        "NC_RSS_BL": "Near Court: Right Singles Sideline Baseline",
        "NC_RDS_BL": "Near Court: Right Doubles Sideline Baseline",
        "NC_LSS_SL": "Near Court: Left Singles Sideline",
        "NC_ML_SL": "Near Court: Middle Line",
        "NC_RSS_SL": "Near Court: Right Singles Sideline",
        "FC_LSS_SL": "Far Court: Left Singles Sideline",
        "FC_ML_SL": "Far Court: Middle Line",
        "FC_RSS_SL": "Far Court: Right Singles Sideline",
        "FC_LDS_BL": "Far Court: Left Doubles Sideline Baseline",
        "FC_LSS_BL": "Far Court: Left Singles Sideline Baseline",
        "FC_ML_BL": "Far Court: Middle Line Baseline",
        "FC_RSS_BL": "Far Court: Right Singles Sideline Baseline",
        "FC_RDS_BL": "Far Court: Right Doubles Sideline Baseline",
        "NET_LDS":    "Net: Left Doubles Sideline",
        "NET_LSS":    "Net: Left Singles Sideline",
        "NET_ML":     "Net: Middle",
        "NET_RSS":    "Net: Right Singles Sideline",
        "NET_RDS":    "Net: Right Doubles Sideline"
    ]
}

enum CourtPriority: String, Codable, CaseIterable {
    case primary
    case secondary
}
// MARK: - CourtDetection Model
@Model
final class CourtDetection {
    @Attribute(.unique) var id: UUID = UUID()
    var frameUUID: UUID?
    var courtPriority: CourtPriority
    /// Relationship: A CourtDetection has many CourtKeypoints.
    var keypoints: [CourtKeypoint]
    
    // MARK: - Initializer
    init(frameUUID: UUID? = nil, courtPriority: CourtPriority = .primary, keypoints: [CourtKeypoint]? = nil) {
        self.frameUUID = frameUUID
        self.courtPriority = courtPriority
        if let provided = keypoints {
            self.keypoints = provided
        } else {
            // Initialize with a default keypoint for each required label.
            self.keypoints = CourtKeypointLabels.allKeypoints.map { label in
                CourtKeypoint(label: label)
            }
        }
    }
    
    /// Computed property to return keypoints sorted by label (optional)
    var sortedKeypoints: [CourtKeypoint] {
        keypoints.sorted { $0.label < $1.label }
    }
}

extension CourtDetection {
    func getKeypoint(for label: String) -> CourtKeypoint {
        guard let keypoint = keypoints.first(where: { $0.label == label }) else {
            fatalError("Unknown keypoint label: \(label)")
        }
        return keypoint
    }
}

// MARK: - CourtKeypointVisibility
enum CourtKeypointVisibility: String, Codable, CaseIterable {
    case visible, occluded, notVisible
}

class AnnotationManager {
    private var ModelContext: ModelContext
    
    init(ModelContext: ModelContext) {
        self.ModelContext = ModelContext
    }
}

