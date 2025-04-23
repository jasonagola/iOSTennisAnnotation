//
//  ContentView.swift
//  Annotation
//
//  Created by Jason Agola on 1/8/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject var queueManager = ProcessingQueueManager()
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedProjectUUID: UUID? = nil
    @State private var navigateToProjectView = false
    @State private var showDeleteConfirmation = false
    @State private var refreshID = UUID() // used to force a refresh of the ProjectBrowserView
   
    
    
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left side: Preview view loads some thumbnails.
                
                PreviewView(selectedProjectUUID: selectedProjectUUID )
                    .frame(width: 360)
                    .border(Color.gray, width: 1)
            
                
                
                Divider()
                
                // Right side: Project browser.
                // The .id(refreshID) forces a refresh when refreshID changes.
                ProjectBrowserView(selectedProjectUUID: $selectedProjectUUID)
                    .id(refreshID)
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Open") {
                        if selectedProjectUUID != nil {
                            print("Open button selectedProjectUUID: \(selectedProjectUUID!)")
                            navigateToProjectView = true
                        }
                    }
                    Spacer()
                    NavigationLink(destination: VideoUploadView(queueManager: queueManager)) {
                        Text("Upload & Parse Video")
                    }
                    Spacer()
                    Button("Delete") {
                        if selectedProjectUUID != nil {
                            showDeleteConfirmation = true
                        }
                    }
                    Spacer()
                    //Manually Add History to Processing Queue View 
                    NavigationLink(destination: ProcessingQueueView(queueManager: queueManager)) {
                        Text("View Processing Queue")
                    }
                }
            }
            .navigationTitle("Projects")
            .background(
                Group {
                    if let validProjectID = selectedProjectUUID {
                        NavigationLink(
                            "",
                            destination: ProjectView(projectUUID: validProjectID, queueManager: queueManager, modelContext: modelContext),
                            isActive: $navigateToProjectView
                        )
                        .hidden()
                    } else {
                        EmptyView()
                    }
                }
            )            .alert("Delete Project", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelectedProject()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this project?")
            }
        }
    }
    
    private func deleteSelectedProject() {
        guard let projectUUID = selectedProjectUUID else {
            print("No project selected to delete.")
            return
        }
        
        let fetchDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectUUID }
        )
        
        do {
            if let selectedProject = try modelContext.fetch(fetchDescriptor).first {
                // Delete associated frames first
                let targetProjectID: UUID = selectedProject.id
                let frameFetchDescriptor = FetchDescriptor<Frame>(
                    predicate: #Predicate { (frame: Frame) -> Bool in
                        frame.project.id == targetProjectID
                    }
                )
                
                let frames = try modelContext.fetch(frameFetchDescriptor)
                
                for frame in frames {
                    modelContext.delete(frame)
                }
                
                // Delete the project
                modelContext.delete(selectedProject)
                
                // Save changes in SwiftData
                try modelContext.save()

                // Remove the directory from the filesystem
                deleteProjectDirectory(named: selectedProject.name)

                // Clear selection and refresh UI
                selectedProjectUUID = UUID() // Reset selection
                refreshID = UUID() // Force UI refresh
            }
        } catch {
            print("Error deleting project: \(error)")
        }
    }
    
    private func deleteProjectDirectory(named projectName: String) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to get document directory")
            return
        }

        let projectURL = documentsURL.appendingPathComponent(projectName)

        do {
            if fileManager.fileExists(atPath: projectURL.path) {
                try fileManager.removeItem(at: projectURL)
                print("Successfully deleted project folder: \(projectURL.path)")
            }
        } catch {
            print("Error deleting project folder: \(error)")
        }
    }
}

// MARK: - PreviewView
struct PreviewView: View {
    @Environment(\.modelContext) private var modelContext
    let selectedProjectUUID: UUID?
    @State private var previewThumbnailPaths: [String] = []
    
    var body: some View {
        VStack {
            Text("Project Preview")
                .font(.title)
                .padding(.top)
            
            if previewThumbnailPaths.isEmpty {
                Text("No thumbnails found for \(selectedProjectUUID)")
                    .padding()
            } else {
                // Display thumbnails at 5%, 30%, 70%, 95% of the available thumbnails.
                let totalThumbnails = previewThumbnailPaths.count
                
                let percentages = [0.05, 0.30, 0.70, 0.95]
                let indices = percentages.map { percent in
                    min(Int(round(percent * Double(max(totalThumbnails - 1, 1)))), totalThumbnails - 1)
                }
                
                ForEach(indices, id: \.self) { index in
                    let thumbPath = previewThumbnailPaths[index]
                    if let image = UIImage(contentsOfFile: thumbPath) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding(4)
                    }
                }
            }
            Spacer()
        }
        .onAppear {
            loadPreviewThumbnails()
        }
        .onChange(of: selectedProjectUUID) {
            // Use the zero-parameter closure version.
            loadPreviewThumbnails()
        }
    }
    
    
    private func loadPreviewThumbnails() {
        // Use a guard to ensure you have a valid project ID.
        guard let projectID = selectedProjectUUID else {
            previewThumbnailPaths = []
            return
        }
        
        // Clear out old thumbnails.
        previewThumbnailPaths = []
        
        
        let fetchDescriptor = FetchDescriptor<Frame>(
            predicate: #Predicate { frame in
                frame.project.id == projectID
            }
        )
        
        do {
            let frames = try modelContext.fetch(fetchDescriptor)
            previewThumbnailPaths = frames.compactMap { $0.thumbnailPath }.sorted()
        } catch {
            print("Error loading preview thumbnails: \(error)")
            previewThumbnailPaths = []
        }
    }
}
    
    // MARK: - ProjectBrowserView
    /// Shows a vertical list of projects taking full width.
struct ProjectBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedProjectUUID: UUID?
    @State private var projects: [Project] = []
    
    var body: some View {
        List(projects, id: \.self) { project in
            HStack {
                Text(project.name)
                    .font(.headline)
                    .padding(.vertical, 8)
                Spacer()
                if selectedProjectUUID == project.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedProjectUUID = project.id
            }
        }
        .listStyle(.plain)
        .onAppear {
            loadProjectNames()
        }
    }
    
    private func loadProjectNames() {
        let fetchDescriptor = FetchDescriptor<Project> ()
        
        do {
            let loadedProjects = try modelContext.fetch(fetchDescriptor)
            projects = loadedProjects.sorted { $0.name < $1.name }
        } catch {
            print("Error fetching projects: \(error)")
        }
    }
}
