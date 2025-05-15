//
//  DetectionDrawerView.swift
//  Annotation
//
//  Created by Jason Agola on 1/14/25.
//

import SwiftUI

/// Represents a tile in the Detection Drawer.
struct DetectionTile: Identifiable {
    let id = UUID()
    let title: String
    let content: AnyView

    init<T: View>(title: String, @ViewBuilder content: @escaping () -> T) {
        self.title = title
        // Wrap the passed content in a GeometryReader so it takes the size of its parent.
        self.content = AnyView(
            content()
        )
    }
}


struct DetectionDrawerView: View {
    @EnvironmentObject var frameState: FrameState
    @ObservedObject var drawerManager: DetectionDrawerManager
    @Binding var showDetectionDrawer: Bool  // Controls the drawer visibility
    
    private let drawerWidth: CGFloat = 250
    private let drawerHeight: CGFloat = UIScreen.main.bounds.height
    
    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading) {
                // Drawer Header
                HStack {
                    Text("Annotations")
                        .font(.headline)
                        .padding(5)
                    Spacer()
                    Button(action: { showDetectionDrawer = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .background(Color.gray.opacity(0.1))
                .padding(.top)
                
                Divider()
                
                // Display the tiles from the manager in a scrollable list.
                ScrollView {
                    ForEach(Array(drawerManager.tiles.enumerated()), id: \.element.id) { index, tile in
                        VStack(alignment: .leading) {
                            Text(tile.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(5)

                            tile.content
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(0)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)

                        // ✅ Add a visual divider if it's not the last tile
                        if index < drawerManager.tiles.count - 1 {
                            Divider()
                                .frame(height: 1)
                                .background(Color.white.opacity(0.3))
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)
                }
                
                Spacer()
            }
            .frame(width: drawerWidth)
            .background(Color.black.opacity(1))
            .offset(x: showDetectionDrawer ? 0 : drawerWidth)
            .animation(.easeInOut, value: showDetectionDrawer)
            .id(frameState.refreshToken)
        }
    }
        
}


//extension DetectionDrawerView {
//    /// A default tile showing temporary annotations.
//    func defaultTemporaryAnnotationsTile() -> AnyView {
//        AnyView(
//            VStack(alignment: .leading) {
//                Text("Temporary Annotations")
//                    .font(.subheadline)
//                    .foregroundColor(.red)
//                // You might iterate over temporary annotations here.
//                Text("List of temporary annotations…")
//                    .foregroundColor(.white)
//            }
//            .padding()
//            .background(Color.gray.opacity(0.3))
//            .cornerRadius(8)
//        )
//    }
//    
//    /// A default tile showing committed annotations.
//    func defaultCommittedAnnotationsTile() -> AnyView {
//        AnyView(
//            VStack(alignment: .leading) {
//                Text("Committed Annotations")
//                    .font(.subheadline)
//                    .foregroundColor(.green)
//                // You might iterate over committed annotations here.
//                Text("List of committed annotations…")
//                    .foregroundColor(.white)
//            }
//            .padding()
//            .background(Color.gray.opacity(0.3))
//            .cornerRadius(8)
//        )
//    }
//    
//    /// A default tile showing annotation details (for a selected annotation).
//    func defaultAnnotationDetailTile(for annotation: any BaseAnnotation) -> AnyView {
//        AnyView(
//            VStack(alignment: .leading) {
//                Text("Details")
//                    .font(.headline)
//                    .padding(.bottom, 5)
//                Text("ID: \(annotation.id.uuidString.prefix(6))...")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                Text("Type: \(annotation.annotationType.rawValue.capitalized)")
//                    .font(.body)
//                Text("Status: \(annotation.status.rawValue)")
//                    .font(.body)
//                    .foregroundColor(annotation.status == .temporary ? .red : .green)
//                // Add buttons or additional controls as needed.
//            }
//            .padding()
//            .background(Color.white.opacity(0.1))
//            .cornerRadius(8)
//        )
//    }

