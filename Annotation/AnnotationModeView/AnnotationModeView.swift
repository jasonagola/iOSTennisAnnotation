import SwiftUI
import SwiftData
import Combine
import UIKit
import AVFoundation

// MARK: - Updated Protocol
enum AnnotationGestureEvent {
    case dragChanged(CGPoint)
    case dragEnded(CGPoint)
    case tap(CGPoint)
    // Add more if you like: pinch, rotate, long press, etc.
}

protocol AnnotationModule: ObservableObject {
    var title: String { get }
    var annotationType: AnnotationType { get }
//    var image: UIImage { get }
    var internalTools: [AnnotationModuleTool] { get set}
    
    //Render Method
    
    func renderToolOverlay(
        imageSize: CGSize
    ) -> AnyView
    
    func handleTap(at point: CGPoint)
    func handleDragChanged(at point: CGPoint)
    func handleDragEnded(at point: CGPoint)
    
    func selectTool(_ tool: AnnotationModuleTool)
}

// MARK: - Module Collection
struct AnnotationModules {
    static let availableModules: [String: (ModelContext, DetectionDrawerManager, Binding<Bool>, FrameState) -> (any AnnotationModule)] = [
        "Ball Detection": { modelContext, drawerManager, showDetectionDrawer, frameState in
            BallDetectionModule(
                modelContext: modelContext,
                showDetectionDrawer: showDetectionDrawer,
                drawerManager: drawerManager,
                frameState: frameState
            )
        },
        "Court Detection": { modelContext, drawerManager, showDetectionDrawer, frameState in
            CourtDetectionModule(
                modelContext: modelContext,
                showDetectionDrawer: showDetectionDrawer,
                drawerManager: drawerManager,
                frameState: frameState
            )
        }
    ]
}


class AnnotationCanvasView: UIView {
    private var cancellable: AnyCancellable?
    @EnvironmentObject private var frameState: FrameState
    private var lastTapLocation: CGPoint?
    
    // The image to display.
    var image: UIImage? {
        didSet {
            if let image = image {
                print("[AnnotationCanvasView] image set with size: \(image.size)")
            } else {
                print("[AnnotationCanvasView] image set to nil")
            }

            guard let image = image else { return }

            let imageSize = image.size
            if self.frame.size != imageSize {
                print("[AnnotationCanvasView] resizing frame from \(self.frame.size) to \(imageSize)")
                self.frame = CGRect(origin: .zero, size: imageSize)
            }

            imageView.image = image
            print("[AnnotationCanvasView] image assigned to imageView")
            setNeedsLayout()
        }
    }
    
    var selectedAnnotationModule: (any AnnotationModule)? {
        didSet {
            renderOverlays()
        }
    }
    
    var selectedVisibleAnnotations: Set<String> = [] {
        didSet {
            renderOverlays()
        }
    }

    // Subviews for annotation overlay, gestures, etc.
    private let imageView = UIImageView()
    let overlayView = UIView()
    
    // Gesture callbacks
    var onGesture: ((CGPoint, AnnotationGestureEvent) -> Void)?
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
       
        // Capture the tap location in the overlay's coordinate space.
        let location = gesture.location(in: overlayView)
        print("AnnotationCanvasView HandleTap Gesture with location: \(location)")
        // Instead of sending upward, call the onGesture callback if set.
        onGesture?(location, .tap(location))
//        renderOverlays()
    }
    
    // -----------------------------------------------------------------
    // MARK: - Init
    // -----------------------------------------------------------------
    init() {
        super.init(frame: .zero)
        setupViews()
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        clipsToBounds = true
        
        // Here, to get a 1:1 mapping of coordinates inside this view,
        // usually you want contentMode = .topLeft (no extra scaling).
        // If you do .scaleAspectFit, it will re-scale again inside the view
        // which can complicate coordinate mapping for annotations.
        imageView.contentMode = .topLeft
        imageView.frame = bounds
//        addSubview(imageView)
        
        overlayView.backgroundColor = .clear
        overlayView.frame = bounds
        addSubview(overlayView)
        
        setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delegate = self
        overlayView.addGestureRecognizer(tapGesture)
        
        // Pan gesture for drag events.
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        //Enforce pass down drag events to Annotation Modules to be 1 finger drag gestures only for drawing or other methods
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        overlayView.addGestureRecognizer(panGesture)
    }
    
    // -----------------------------------------------------------------
    // MARK: - Layout
    // -----------------------------------------------------------------
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        overlayView.frame = bounds

//        print("[AnnotationCanvasView] layoutSubviews called. Bounds: \(bounds)")
    }
    
    // -----------------------------------------------------------------
    // MARK: - Gesture Handling
    // -----------------------------------------------------------------
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: overlayView)
        switch gesture.state {
        case .changed:
            onGesture?(location, .dragChanged(location))
        case .ended, .cancelled:
            onGesture?(location, .dragEnded(location))
        default:
            break
        }
    }
    
    private var annotationHost: UIHostingController<RenderedAnnotationsView>?
    private var toolHost: UIHostingController<ToolRenderOverlayView>?

    func renderOverlays() {
        print("Render Overlays being called")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let image = self.image else { return }
            
            // Update existing hosting controllers instead of creating new ones:
            if let host = self.annotationHost {
                let newRoot = RenderedAnnotationsView(
                    imageSize: image.size,
                    selectedVisibleAnnotations: self.selectedVisibleAnnotations,
                    selectedAnnotationModule: self.selectedAnnotationModule
                )
                host.rootView = newRoot
            } else {
                let renderedAnnotationsView = RenderedAnnotationsView(
                    imageSize: image.size,
                    selectedVisibleAnnotations: self.selectedVisibleAnnotations,
                    selectedAnnotationModule: self.selectedAnnotationModule
                )
                let host = UIHostingController(rootView: renderedAnnotationsView)
                host.view.backgroundColor = .clear
                self.embed(hostingController: host)
                self.annotationHost = host
            }

            if let host = self.toolHost {
                let newRoot = ToolRenderOverlayView(
                    imageSize: image.size,
                    selectedAnnotationModule: self.selectedAnnotationModule
                )
                host.rootView = newRoot
            } else {
                let toolOverlay = ToolRenderOverlayView(
                    imageSize: image.size,
                    selectedAnnotationModule: self.selectedAnnotationModule
                )
                let host = UIHostingController(rootView: toolOverlay)
                host.view.backgroundColor = .clear
                self.embed(hostingController: host)
                self.toolHost = host
            }
        }
    }
    
    private func embed(hostingController: UIHostingController<some View>) {
        // Add hostingController.view as a subview and pin to overlayView bounds.
        overlayView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: overlayView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor)
        ])
    }
//    func renderOverlays() {
//        print("Render Overlays being called again")
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self else { return }
//
//    //        // Remove old views
//    //        self.annotationOverlayView.subviews.forEach { $0.removeFromSuperview() }
//            
//            guard let image = self.image else {
//                print("No image loaded in renderModuleAnnotations")
//                return
//            }
//            
//            let renderedAnnotationsView = RenderedAnnotationsView(
//                imageSize: image.size,
//                selectedVisibleAnnotations: self.selectedVisibleAnnotations,
//                selectedAnnotationModule: selectedAnnotationModule
//            )
//            
//            let annotationHost = UIHostingController(rootView: renderedAnnotationsView)
//            annotationHost.view.backgroundColor = .clear
//            embed(hostingController: annotationHost)
//
//            // 🧩 Tool Overlay (e.g., live drawing)
//            let toolOverlay = ToolRenderOverlayView(
//                imageSize: image.size,
//                selectedAnnotationModule: selectedAnnotationModule
//            )
//
//            let toolHost = UIHostingController(rootView: toolOverlay)
//            toolHost.view.backgroundColor = .clear
//            embed(hostingController: toolHost)
//            
//            
//        }
//    }
//    
//    private func embed(hostingController: UIHostingController<some View>) {
//        overlayView.addSubview(hostingController.view)
//
//        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
//        NSLayoutConstraint.activate([
//            hostingController.view.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
//            hostingController.view.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
//            hostingController.view.topAnchor.constraint(equalTo: overlayView.topAnchor),
//            hostingController.view.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor)
//        ])
//    }
}

extension AnnotationCanvasView: UIGestureRecognizerDelegate {
    // Allow simultaneous recognition (so the scroll view can still handle zooming/panning).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

// MARK: - ScrollableAnnotationCanvasView (UIScrollView Subclass)
class ScrollableAnnotationCanvasView: UIScrollView, UIScrollViewDelegate {
    let canvasView = AnnotationCanvasView()
    
    /// To ensure we only do the "zoom out to fit" once:
    private var didSetInitialZoom = false
    
    // Forward gesture handling
    var onGesture: ((CGPoint, AnnotationGestureEvent) -> Void)? {
        didSet { canvasView.onGesture = onGesture }
    }
    
    // -----------------------------------------------------------------
    // MARK: - Init
    // -----------------------------------------------------------------
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScroll()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScroll()
    }
    
    // -----------------------------------------------------------------
    // MARK: - Setup
    // -----------------------------------------------------------------
    private func setupScroll() {
        delegate = self
        alwaysBounceVertical   = true
        alwaysBounceHorizontal = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator   = false
        decelerationRate       = .fast
        
        //Enforce 2 finger scroll gestures.  Separate gesture concerns
        self.panGestureRecognizer.minimumNumberOfTouches = 2
        self.panGestureRecognizer.maximumNumberOfTouches = 2
        
        // Add the canvasView as a subview.
        addSubview(canvasView)
    }
    
    // -----------------------------------------------------------------
    // MARK: - Layout
    // -----------------------------------------------------------------
    override func layoutSubviews() {
//        print("Layout Subviews Running")
        super.layoutSubviews()
        
        // If the canvas has a valid image, it will have a non-zero size.
        let canvasSize = CGSize(width: canvasView.bounds.size.width * 15, height: canvasView.bounds.size.height * 15)
        guard canvasSize.width > 0 && canvasSize.height > 0 else { return }
        contentSize = canvasSize
        
//        print("Layout subviews: ContentSize:\(contentSize), Container Size: \(self.bounds.size)")
        
        // Compute the minScale that fits the entire canvasView in the visible bounds
        let containerSize = self.bounds.size
        let widthScale  = containerSize.width  / canvasSize.width * 15
        let heightScale = containerSize.height / canvasSize.height * 15
        let minScale    = min(widthScale, heightScale)
        
        // Typical max zoom
        maximumZoomScale = 15
        
        // Update the minimum
        minimumZoomScale = minScale
        
        // The first time layout is done, we "zoom out" so the entire image is visible:
        if !didSetInitialZoom {
            didSetInitialZoom = true
            zoomScale = minScale
        }
        
        updateContentInset()
    }
    
    // -----------------------------------------------------------------
    // MARK: - UIScrollViewDelegate
    // -----------------------------------------------------------------
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return canvasView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
//        print("Zoom scale: \(scrollView.zoomScale) and offset: \(scrollView.contentOffset)")
        updateContentInset()
    }
    
    private func updateContentInset() {
//        print("UpdateContentInset Running")
        if zoomScale <= minimumZoomScale + 0.001 {
//            print("UCI: zoomScale smaller than minimumZoomScale")
            let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
            let verticalInset   = max((bounds.height - contentSize.height) / 2, 0)
            contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        } else {
//            print("UCI setting content inset to .zero")
            contentInset = .zero
        }
    }
}

struct ScrollableAnnotationCanvasRepresentable: UIViewRepresentable {
    var image: UIImage?
    var selectedAnnotationModule: (any AnnotationModule)?
    var selectedVisibleAnnotations: Set<String>
    let onGesture: (CGPoint, AnnotationGestureEvent) -> Void
    var refreshToken: UUID

    func makeUIView(context: Context) -> ScrollableAnnotationCanvasView {
        let scrollableView = ScrollableAnnotationCanvasView(frame: .zero)
        scrollableView.canvasView.image = image
        scrollableView.onGesture = onGesture
        scrollableView.canvasView.selectedAnnotationModule = selectedAnnotationModule
        scrollableView.canvasView.selectedVisibleAnnotations = selectedVisibleAnnotations
        context.coordinator.lastRefreshToken = refreshToken
        return scrollableView
    }

    func updateUIView(_ uiView: ScrollableAnnotationCanvasView, context: Context) {
        if uiView.canvasView.image != image {
            uiView.canvasView.image = image
        }
        
        uiView.canvasView.selectedVisibleAnnotations = selectedVisibleAnnotations

        if context.coordinator.lastRefreshToken != refreshToken {
            uiView.canvasView.overlayView.subviews.forEach { $0.removeFromSuperview() }
            uiView.canvasView.renderOverlays()
            context.coordinator.lastRefreshToken = refreshToken
        }

        uiView.canvasView.selectedAnnotationModule = selectedAnnotationModule
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastRefreshToken: UUID?
    }
}

// MARK: - AnnotationModeViewModel
class AnnotationModeViewModel: ObservableObject {
    let modelContext: ModelContext
    
    var projectUUID: UUID
    var selectedFrameUUID: UUID
    @Published var selectedVisibleAnnotations: Set<String> = []
    
    @Published var project: Project?
    @Published var selectedAnnotationModule: (any AnnotationModule)? = nil
    @Published var showDetectionDrawer: Bool = false

    init(projectUUID: UUID, modelContext: ModelContext, selectedFrameUUID: UUID) {
        self.projectUUID = projectUUID
        self.selectedFrameUUID = selectedFrameUUID
        self.modelContext = modelContext
    }
    
    // MARK: - Navigation Helpers
}

// MARK: - AnnotationModeView
struct AnnotationModeView: View {
    @StateObject private var viewModel: AnnotationModeViewModel
    @EnvironmentObject var frameState: FrameState
    @Environment(\.dismiss) var dismiss
//    @State private var didConfigure = false
    private var modelContext: ModelContext
    
    @StateObject private var drawerManager: DetectionDrawerManager
    @State private var selectedAnnotationModule: (any AnnotationModule)? = nil
    
    init(projectUUID: UUID, modelContext: ModelContext, selectedFrameUUID: UUID) {
        self.modelContext = modelContext
        
        // Initialize drawerManager inside the init method
        _drawerManager = StateObject(wrappedValue: DetectionDrawerManager())
        
        _viewModel = StateObject(
            wrappedValue: AnnotationModeViewModel(
                projectUUID: projectUUID,
                modelContext: modelContext,
                selectedFrameUUID: selectedFrameUUID
            )
        )
    }
    
    func nextImage() async {
        await frameState.nextFrame()
    }
    
    func prevImage() async {
        await frameState.prevFrame()
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geo in
                content
            }
        }
        .onAppear {
            frameState.currentFrameUUID = viewModel.selectedFrameUUID
//            frameState.loadCurrentImage()
        }
        // Listen for changes to currentImage
        .onReceive(frameState.$currentImage) { newImage in
        }
        .navigationViewStyle(StackNavigationViewStyle())
//        .id(frameState.refreshToken)
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            VStack {
                topToolbar
                Divider()
                
                if let uiImage = frameState.currentImage {
                    // The representable that draws the image + annotations:
                    ScrollableAnnotationCanvasRepresentable(
                        image: uiImage,
                        selectedAnnotationModule: viewModel.selectedAnnotationModule,
                        selectedVisibleAnnotations: viewModel.selectedVisibleAnnotations,
                        onGesture: { location, event in
                            Task {
                                await handleGesture(event, location: location, image: uiImage)
                            }
                        },
                        refreshToken: frameState.refreshToken
                    )
                    .background(Color.black)
                } else {
                    Text("No images available for annotation.")
                        .foregroundColor(.white)
                    
                    // Additional debug text
                    Text("FrameState Image: nil")
                        .foregroundColor(.gray)
                }
                
                Divider()
                
                DynamicToolbar(
                    selectedModule: viewModel.selectedAnnotationModule,
                    showDetectionDrawer: $viewModel.showDetectionDrawer,
                    drawerManager: drawerManager
                )
            }
            .frame(maxWidth: viewModel.showDetectionDrawer ? .infinity : nil)
            .animation(.easeInOut, value: viewModel.showDetectionDrawer)
            
            if viewModel.showDetectionDrawer {
                DetectionDrawerView(
                    drawerManager: drawerManager,
                    showDetectionDrawer: $viewModel.showDetectionDrawer
                )
                .transition(.move(edge: .trailing))
                .animation(.easeInOut, value: viewModel.showDetectionDrawer)
                .padding(5)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Gesture Handling
    private func handleGesture(
        _ event: AnnotationGestureEvent,
        location: CGPoint,
        image: UIImage
    ) async {
        let normalizedTap = CGPoint(
            x: location.x / image.size.width,
            y: location.y / image.size.height
        )
        
        switch event {
        case .tap:
            if let module = viewModel.selectedAnnotationModule {
                module.handleTap(at: normalizedTap)
            }
            
            await frameState.runTapBehavior(location: normalizedTap, selectedVisibleAnnotations: viewModel.selectedVisibleAnnotations, selectedAnnotationModuleTitle: viewModel.selectedAnnotationModule?.title)
            
        case .dragChanged:
            print("AMV: drag changed")
            if let module = viewModel.selectedAnnotationModule {
                module.handleDragChanged(at: normalizedTap)
            }
            
        case .dragEnded:
            print("AMV: drag ended")
            if let module = viewModel.selectedAnnotationModule {
                module.handleDragEnded(at: normalizedTap)
            }
        }
        
    }

    struct MultiSelectAnnotationTypes: View {
        @Binding var selections: Set<String>
        let options: [String]
        
        @State private var isExpanded = false
        @State private var buttonFrame: CGRect = .zero
  
        var body: some View {
            // Use a full-screen ZStack so the overlay isn't clipped.
            ZStack(alignment: .topLeading) {
                // The trigger button.
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        if selections.isEmpty {
                            Text("Select annotation types")
                                .foregroundColor(.gray)
                        } else {
                            Text(selections.sorted().joined(separator: ", "))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                    .padding(10)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ButtonFramePreferenceKey.self, value: geo.frame(in: .global))
                        }
                    )
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                }
                .onPreferenceChange(ButtonFramePreferenceKey.self) { frame in
                    self.buttonFrame = frame
                }
                
                // When expanded, add an overlay to capture outside taps.
                if isExpanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation { isExpanded = false }
                        }
                }
                
                // The dropdown list overlay.
                if isExpanded {
                    DropdownList(options: options, selections: $selections)
                        .frame(width: max(buttonFrame.width, 150))
                        // Position the dropdown so its top-left aligns with the button's bottom-left.
                        .position(
                            x: buttonFrame.minX + buttonFrame.width / 2,
                            y: buttonFrame.maxY + dropdownListHeight() / 2
                        )
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // Ensure the ZStack occupies the full screen (or at least isn't clipped).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        
        // Helper: estimate the height of the dropdown.
        private func dropdownListHeight() -> CGFloat {
            // For example, assume each option row is 44 points tall.
            return CGFloat(options.count) * 44.0
        }
    }

    struct ButtonFramePreferenceKey: PreferenceKey {
        typealias Value = CGRect
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    struct DropdownList: View {
        let options: [String]
        @Binding var selections: Set<String>
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        if selections.contains(option) {
                            selections.remove(option)
                        } else {
                            selections.insert(option)
                        }
                    }) {
                        HStack {
                            Text(option)
                                .foregroundColor(.primary)
                            Spacer()
                            if selections.contains(option) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(10)
                    }
                    if option != options.last {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .shadow(radius: 3)
        }
    }
    
    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack {
            
            Button(action: { dismiss() }) {
                Text("Close")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Horizontal scroll for modules
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnnotationModules.availableModules.keys.sorted(), id: \.self) { key in
                        ModuleButton(
                            key: key,
                            showDetectionDrawer: $viewModel.showDetectionDrawer,
                            selectedAnnotationModule: $viewModel.selectedAnnotationModule
                        )
                        .environmentObject(drawerManager)
                    }
                }
            }
            
            // Navigation arrows
            HStack(spacing: 8) {
                MultiSelectAnnotationTypes(
                    selections: Binding(
                        get: { viewModel.selectedVisibleAnnotations },
                        set: { viewModel.selectedVisibleAnnotations = $0 }
                    ),
                    options: AnnotationModules.availableModules.keys.sorted()
                )
                .padding()
                Button(action: {
                    Task {
                        await prevImage()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .padding(8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                Button(action: {
                    Task {
                        await nextImage()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .padding(8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .font(.headline)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color.purple.opacity(0.2))
        .frame(height: 50)
    }
}

// MARK: - ModuleButton
@MainActor
private struct ModuleButton: View {
    @EnvironmentObject var frameState: FrameState
    let key: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var drawerManager: DetectionDrawerManager
    
    @Binding var showDetectionDrawer: Bool
    @Binding var selectedAnnotationModule: (any AnnotationModule)?
    
    var body: some View {
        Button(action: {
            if let factory = AnnotationModules.availableModules[key] {
                drawerManager.clearTiles()
                let module = factory(
                    modelContext,
                    drawerManager,
                    $showDetectionDrawer,
                    frameState
                )
                selectedAnnotationModule = module
            }
        }) {
            Text(key)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    (selectedAnnotationModule?.title == key)
                    ? Color.blue
                    : Color.gray.opacity(0.3)
                )
                .foregroundColor(
                    (selectedAnnotationModule?.title == key)
                    ? .white
                    : .black
                )
                .cornerRadius(8)
        }
    }
}
