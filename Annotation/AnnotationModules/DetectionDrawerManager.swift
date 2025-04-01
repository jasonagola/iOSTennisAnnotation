//
//  DetectionDrawerManager.swift
//  Annotation
//
//  Created by Jason Agola on 2/4/25.
//

//struct DetectionTile: Identifiable {
//    let id = UUID()
//    let title: String
//    let content: AnyView // Supports dynamic content
//
//    init<T: View>(title: String, @ViewBuilder content: () -> T) {
//        self.title = title
//        self.content = AnyView(content())
//    }
//}

import SwiftUI
import SwiftData

class DetectionDrawerManager: ObservableObject {
    @Published var tiles: [DetectionTile] = []
    @EnvironmentObject var frameState: FrameState
    @Environment(\.modelContext) private var modelContext
    
    // Adds a new tile to the manager
    func addTile(_ tile: DetectionTile) {
        DispatchQueue.main.async {
            self.tiles.append(tile)
            print("Added tile: \(tile.title)")
        }
    }

    // Clears all tiles
    func clearTiles() {
        DispatchQueue.main.async {
            self.tiles.removeAll()
            print("Cleared tiles, current count: \(self.tiles.count)")
        }
    }

    // Replaces the current tiles with a new set
    func setTiles(_ newTiles: [DetectionTile]) {
        DispatchQueue.main.async {
            self.tiles = newTiles
            print("Set new tiles, current titles: \(self.tiles.map { $0.title })")
        }
    }
    
    // Function to create and inject state into DetectionTiles
    func createBallDetectionTile() {
        // Create the BallDetectionTile and inject FrameState and ModelContext
        let ballDetectionTile = DetectionTile(
            title: "Ball Detection",
            content: {
                BallDetectionTile(frameState: self.frameState, modelContext: self.modelContext)
            }
        )
        self.addTile(ballDetectionTile)
    }
}
