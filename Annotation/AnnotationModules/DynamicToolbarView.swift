//
//  BaseToolbar.swift
//  Annotation
//
//  Created by Jason Agola on 1/10/25.
//

import SwiftUI

struct AnnotationModuleTool: Identifiable {
    let id = UUID()
    let name: String
    var action: () -> Void
    var isSelected: Bool
    var isTransient: Bool = false
    var transientClearDelay: TimeInterval? = nil
    var detectionTiles: [DetectionTile] = []
}

/// The dynamic toolbar rendering tools for the active AnnotationModule.
struct DynamicToolbar: View {
    let selectedModule: (any AnnotationModule)?
    @State private var selectedTool: AnnotationModuleTool? = nil
    @Binding var showDetectionDrawer: Bool //Bind From Parent
    var drawerManager: DetectionDrawerManager
    
    private func handleToolSwitching(_ index: Int, module: any AnnotationModule) {
        print("Switching Tools...")
        let tools = module.internalTools
        guard tools.indices.contains(index) else { return }

        let selected = tools[index]

        drawerManager.clearTiles()
        if let tiles = selected.detectionTiles as? [DetectionTile] {
            for tile in tiles {
                drawerManager.addTile(tile)
            }
        }

        selected.action()

        if selected.isTransient {
            selectedTool = selected

            let delay = selected.transientClearDelay ?? 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTool = nil
                }
            }
        } else {
            withAnimation {
                selectedTool = selected
            }
        }
    }
    
        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let module = selectedModule {
                        // Module title
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                Text(module.title)
                                    .font(.headline)
                                
                                Divider()
                                
                                ForEach(module.internalTools.indices, id: \.self) { index in
                                    let tool = module.internalTools[index]
                                    Button(action: {
                                        handleToolSwitching(index, module: module)
                                    }) {
                                        Text(tool.name)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(tool.id == selectedTool?.id ? Color.green : Color.blue)
                                                    .animation(.easeInOut(duration: 0.25), value: selectedTool?.id)
                                            )
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                                
                                // Toggle Detection Drawer Button
                                Button(action: { showDetectionDrawer.toggle(); print("Detection drawer toggled to: \(showDetectionDrawer ? "Open" : "Closed")")}) {
                                    Image(systemName: "list.bullet.rectangle")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    } else {
                        // Default message if no module is selected
                        HStack {
                            Spacer()
                            Text("Select an annotation type to view tools")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(red: 0.18, green: 0.18, blue: 0.2))
            }
        }

        
        private func selectTool(_ tool: AnnotationModuleTool) {
            selectedTool = tool
            
            if let module = selectedModule {
                var updatedTools = module.internalTools
                for index in updatedTools.indices {
                    updatedTools[index].isSelected = updatedTools[index].id == tool.id
                }
                module.internalTools = updatedTools
                tool.action()
            }
        }
    }

    
