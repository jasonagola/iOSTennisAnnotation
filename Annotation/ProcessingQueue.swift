//
//  ProcessingQueue.swift
//  Annotation
//
//  Created by Jason Agola on 2/21/25.
//

import SwiftUI
import Combine

// MARK: - ProcessingTask State

enum ProcessingTaskState: String, CaseIterable {
    case pending, running, paused, completed, failed
}

// MARK: - ProcessingTask Protocol

protocol ProcessingTask: Identifiable, ObservableObject where ID == UUID {
    var title: String { get }
    var state: ProcessingTaskState { get set }
    var progress: Double { get set }
    var statusMessage: String { get set }
    
    // Publishers for live updates.
    var statePublisher: AnyPublisher<ProcessingTaskState, Never> { get }
    var progressPublisher: AnyPublisher<Double, Never> { get }
    var statusMessagePublisher: AnyPublisher<String, Never> { get }
    
    func start() async
    func pause()
    func resume()
    func cancel()
}

// MARK: - Type-Erased Processing Task

final class AnyProcessingTask: ProcessingTask, ObservableObject {
    private let _id: UUID
    var id: UUID { _id }
    
    let title: String
    @Published var state: ProcessingTaskState
    @Published var progress: Double
    @Published var statusMessage: String

    private let _start: () async -> Void
    private let _pause: () -> Void
    private let _resume: () -> Void
    private let _cancel: () -> Void
    
    private var cancellables = Set<AnyCancellable>()

    init<T: ProcessingTask & ObservableObject>(_ task: T) where T.ID == UUID {
        self._id = task.id
        self.title = task.title
        self.state = task.state
        self.progress = task.progress
        self.statusMessage = task.statusMessage

        self._start = task.start
        self._pause = task.pause
        self._resume = task.resume
        self._cancel = task.cancel

        // Subscribe to published properties for live updates.
        task.statePublisher
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] newState in
                self?.state = newState
                print("AnyProcessingTask state update: \(newState)")
            }
            .store(in: &cancellables)
        
        task.progressPublisher
            .sink { [weak self] newProgress in
                self?.progress = newProgress
                print("AnyProcessingTask progress update: \(newProgress)")
            }
            .store(in: &cancellables)
        
        task.statusMessagePublisher
            .sink { [weak self] newMessage in
                self?.statusMessage = newMessage
                print("AnyProcessingTask status update: \(newMessage)")
            }
            .store(in: &cancellables)
    }
    
    func start() async { await _start() }
    func pause() { _pause() }
    func resume() { _resume() }
    func cancel() { _cancel() }
    
    // Conformance: Expose publishers.
    var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
        $state.eraseToAnyPublisher()
    }
    var progressPublisher: AnyPublisher<Double, Never> {
        $progress.eraseToAnyPublisher()
    }
    var statusMessagePublisher: AnyPublisher<String, Never> {
        $statusMessage.eraseToAnyPublisher()
    }
}

// MARK: - Processing Queue Manager

final class ProcessingQueueManager: ObservableObject {
    @Published var tasks: [AnyProcessingTask] = []
    private var isProcessing = false
    
    /// Adds a new task to the queue.
    func add<T: ProcessingTask & ObservableObject>(task: T) {
        print("Adding Processing Queue Task: \(task.title)")
        let anyTask = AnyProcessingTask(task)
        tasks.append(anyTask)
        autoRunQueue()
    }
    
    /// Allow reordering of tasks.
    func move(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        tasks.move(fromOffsets: indices, toOffset: newOffset)
    }
    
    /// Automatically run the next pending task.
    private func autoRunQueue() {
        // If already processing, no need to start a new loop.
        guard !isProcessing else { return }
        
        // Find the first task that is pending.
        guard let nextTask = tasks.first(where: { $0.state == .pending }) else {
            isProcessing = false
            return
        }
        
        isProcessing = true
        
        Task {
            print("Starting \(nextTask.title)...")
            await nextTask.start()
            // When finished, mark processing as false and check for another task.
            await MainActor.run {
                self.isProcessing = false
                self.autoRunQueue()
            }
        }
    }
    
    /// (Optional) Start processing all pending tasks sequentially.
    func startProcessing() {
        Task {
            for task in tasks where task.state == .pending {
                await task.start()
            }
        }
    }
}

// MARK: - Processing Queue View

struct ProcessingTaskRow: View {
    @ObservedObject var task: AnyProcessingTask

    var body: some View {
        VStack(alignment: .leading) {
            Text(task.title)
                .font(.headline)
            Text("State: \(task.state.rawValue)")
                .font(.subheadline)
            ProgressView(value: task.progress)
            Text(task.statusMessage)
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct ProcessingQueueView: View {
    @ObservedObject var queueManager: ProcessingQueueManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(queueManager.tasks) { task in
                    ProcessingTaskRow(task: task)
                }
                .onMove { indices, newOffset in
                    queueManager.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .navigationTitle("Processing Queue")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Projects")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
}



// MARK: - Dummy Processing Task
//
//final class DummyProcessingTask: ProcessingTask {
//    let id = UUID()
//    let title: String
//    @Published var state: ProcessingTaskState = .pending
//    @Published var progress: Double = 0.0
//    @Published var statusMessage: String = "Pending"
//
//    init(title: String) {
//        self.title = title
//    }
//
//    var statePublisher: AnyPublisher<ProcessingTaskState, Never> {
//        $state.eraseToAnyPublisher()
//    }
//    var progressPublisher: AnyPublisher<Double, Never> {
//        $progress.eraseToAnyPublisher()
//    }
//    var statusMessagePublisher: AnyPublisher<String, Never> {
//        $statusMessage.eraseToAnyPublisher()
//    }
//
//    func start() async {
//        await MainActor.run {
//            self.state = .running
//            self.statusMessage = "Starting..."
//        }
//        for i in 1...100 {
//            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms per step
//            await MainActor.run {
//                self.progress = Double(i) / 100.0
//                self.statusMessage = "Step \(i) of 100"
//                print("DummyProcessingTask update: \(self.statusMessage) (\(self.progress))")
//            }
//            while self.state == .paused {
//                try? await Task.sleep(nanoseconds: 100_000_000)
//            }
//        }
//        await MainActor.run {
//            self.state = .completed
//            self.statusMessage = "Completed"
//        }
//    }
//
//    func pause() {
//        state = .paused
//        statusMessage = "Paused"
//    }
//
//    func resume() {
//        if state == .paused {
//            state = .running
//            statusMessage = "Resumed"
//        }
//    }
//
//    func cancel() {
//        state = .failed
//        statusMessage = "Cancelled"
//    }
//}
