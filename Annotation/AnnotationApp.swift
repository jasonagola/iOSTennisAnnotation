//
//  AnnotationApp.swift
//  Annotation
//
//  Created by Jason Agola on 1/8/25.
//

import SwiftUI
import SwiftData

@main
struct AnnotationApp: App {
    
    var AnnotationModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Frame.self,
            AnnotationRecord.self,
            BallDetection.self,
            CourtDetection.self,
            CourtKeypoint.self
        ])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to load ModelContainer: \(error)")
        }
    }()
        
    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
        .modelContainer(AnnotationModelContainer)
    }
}
