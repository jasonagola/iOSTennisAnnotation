//
//  CompositeOverlayView.swift
//  Annotation
//
//  Created by Jason Agola on 4/3/25.


import SwiftUI
import SwiftData

//Separate Image Loading and compositeframe Array logic from rerendering logic like(changed Opacity and z index)
//moveForward and moveBackward methods should change the viewing params(opacity and z index) then trigger async loading operations
//View in forEeach should only render a subset of the loaded images so as not to retrigger as items are added.
//.id adds to each annotation and frame to prevent rerender

struct CompositeFrameItem {
    let index: Int
    let uuid: UUID
    let image: UIImage
    let detections: [BallDetection]
    var opacity: Double
}

struct CompositeOverlayView: View {
    @EnvironmentObject var frameState: FrameState
//    @EnvironmentObject(./modelContext) private var modelContext

    @State private var compositeFrames: [CompositeFrameItem] = []
    @State private var centerFrameIndex: Int = 0
    let imageSize: CGSize = CGSize(width: 3480, height: 2640)

    let renderMargin = 5            // Render 5 frames before and after
    let preloadMargin = 8          // 2 extra before/after

    var body: some View {
        ZStack {
            ForEach(compositeFrames, id: \.uuid) { item in
                imageView(for: item)
                ForEach(item.detections, id: \.id) { detection in
                    annotationView(for: detection, index: item.index)
                }
            }
        }
        .onAppear {
            initializeCompositeFrames()
        }
    }
    
    private func imageView(for item: CompositeFrameItem) -> some View {
        Image(uiImage: item.image)
            .id(item.uuid)
            .scaledToFit()
            .opacity(opacityForIndex(item.index))
            .zIndex(zIndexForIndex(item.index))
            .animation(Animation.easeInOut(duration: 0.25), value: centerFrameIndex)
    }

    private func annotationView(for detection: BallDetection, index: Int) -> some View {
        Rectangle()
            .stroke(Color.blue, lineWidth: 2)
            .id(detection.id)
            .frame(width: detection.boundingBoxWidth, height: detection.boundingBoxHeight)
            .position(x: detection.computedCenterX, y: detection.computedCenterY)
            .zIndex(zIndexForAnnotation(index))
            .contentShape(Rectangle())
            .onTapGesture {
                if index == centerFrameIndex {
                    moveForward()
                }
                print("Annotation tapped")
            }
    }
    
    
//    var body: some View {
//        ZStack {
//            ForEach(compositeFrames, id: \.uuid) { item in
//                    Image(uiImage: item.image)
//                        .id(item.uuid)
////                            .resizable()
//                        .scaledToFit()
////                        .opacity(opacityForIndex(item.index))
////                        .zIndex(zIndexForIndex(item.index))
//                        .opacity(0.5)
//                        .zIndex(101)
//                        .animation(Animation.easeInOut(duration: 0.25), value: centerFrameIndex)
//
//                        ForEach(item.detections, id: \.id) { detection in
//                            Rectangle()
//                                .id(detection.id)
////                                .stroke(colorForAnnotation(index), lineWidth: 2)
//                                .stroke(Color.blue, lineWidth: 2)
//                                .frame(
//                                    width: detection.boundingBoxWidth,
//                                    height: detection.boundingBoxHeight
//                                )
//                                .position(
//                                    x: detection.computedCenterX,
//                                    y: detection.computedCenterY
//                                )
////                                .zIndex(zIndexForAnnotation(index))
//                                .zIndex(102)
//                                .contentShape(Rectangle())
//                                .onTapGesture {
//                                    if item.index == centerFrameIndex {
//                                        print("Tapped center frame annotation. Advancing...")
////                                        moveForward()
//                                    }
////                                }
//                        }
//                    }
//        }
//        .onAppear {
//            initializeCompositeFrames()
//        }
//    }

    private var preloadRange: ClosedRange<Int> {
        let start = max(centerFrameIndex - preloadMargin, 0)
        let end = min(centerFrameIndex + preloadMargin, frameState.frames.count - 1)
        return start...end
    }

    private var visibleRange: ClosedRange<Int> {
        let start = max(centerFrameIndex - renderMargin, 0)
        let end = min(centerFrameIndex + renderMargin, frameState.frames.count - 1)
        return start...end
    }

    //Should only fire on load: Possible caching necessary if behavior is erratic. onAppear behavior happens with parent view recalc
    private func initializeCompositeFrames() {
        // Only initialize if compositeFrames is empty
        guard compositeFrames.isEmpty else {
            print("Composite frames already initialized")
            return
        }
        
        print("Initializing the Composite frames...")
        
        guard let currentUUID = frameState.currentFrameUUID,
              let index = frameState.frames.firstIndex(where: { $0.id == currentUUID }) else {
            return
        }
        centerFrameIndex = index

        let range = preloadRange
        compositeFrames = range.map { i in
            let index = i
            let frame = frameState.frames[i]
            let image = loadImage(for: frame)
            let detections = loadDetections(for: frame.id)
            // Set opacity as desired; here it's hardcoded for simplicity.
            let opacity = 0.1
            return CompositeFrameItem(index: index,
                                      uuid: frame.id,
                                      image: image!,
                                      detections: detections,
                                      opacity: opacity)
        }
    }
    
    func moveForward() {
        print("Move Forward Method Called")
        let nextIndex = centerFrameIndex + 1
        guard nextIndex < frameState.frames.count else { return }
        
        // Advance the center frame index.
        centerFrameIndex = nextIndex
        
        // Remove the first composite frame if its frame index is now below the lower bound of our preload range.
        if let first = compositeFrames.first,
           let firstIndex = frameState.frames.firstIndex(where: { $0.id == first.uuid }),
           firstIndex < preloadRange.lowerBound {
            compositeFrames.removeFirst()
        }
        
        // Determine the new frame index to append.
        let newIndex = preloadRange.upperBound
        if newIndex < frameState.frames.count {
            let frame = frameState.frames[newIndex]
            guard let image = loadImage(for: frame) else {
                print("Error: could not load image for frame at index \(newIndex)")
                return
            }
            let detections = loadDetections(for: frame.id)
            // Optionally, set opacity based on whether the frame is within the visible range.
            let opacity = visibleRange.contains(newIndex) ? opacityForIndex(newIndex) : 0
            let newItem = CompositeFrameItem(index: newIndex,
                                               uuid: frame.id,
                                               image: image,
                                               detections: detections,
                                               opacity: opacity)
            compositeFrames.append(newItem)
        }
        
        // Optionally update opacities for all composite frames here if needed.
    }

//    func moveForward() {
//        let nextIndex = centerFrameIndex + 1
//        guard nextIndex < frameState.frames.count else { return }
//
//        centerFrameIndex = nextIndex
//
//        if let first = compositeFrames.first,
//           let firstIndex = frameState.frames.firstIndex(where: { $0.id == first.uuid }),
//           firstIndex < preloadRange.lowerBound {
//            compositeFrames.removeFirst()
//        }
//
//        let newIndex = preloadRange.upperBound
//        if newIndex < frameState.frames.count {
//            let frame = frameState.frames[newIndex]
//            let image = loadImage(for: frame)
//            let detections = loadDetections(for: frame.id)
//            let opacity = visibleRange.contains(newIndex) ? opacityForIndex(newIndex) : 0
//            let newItem = CompositeFrameItem(uuid: frame.id, image: image, detections: detections, opacity: opacity)
//            compositeFrames.append(newItem)
//        }
//
//        updateOpacities()
//    }

//    func moveBackward() {
//        let prevIndex = centerFrameIndex - 1
//        guard prevIndex >= 0 else { return }
//
//        centerFrameIndex = prevIndex
//
//        if let last = compositeFrames.last,
//           let lastIndex = frameState.frames.firstIndex(where: { $0.id == last.uuid }),
//           lastIndex > preloadRange.upperBound {
//            compositeFrames.removeLast()
//        }
//
//        let newIndex = preloadRange.lowerBound
//        if newIndex >= 0 {
//            let frame = frameState.frames[newIndex]
//            let image = loadImage(for: frame)
//            let detections = loadDetections(for: frame.id)
//            let opacity = visibleRange.contains(newIndex) ? opacityForIndex(newIndex) : 0
//            let newItem = CompositeFrameItem(uuid: frame.id, image: image, detections: detections, opacity: opacity)
//            compositeFrames.insert(newItem, at: 0)
//        }
//
//        updateOpacities()
//    }

    private func loadDetections(for uuid: UUID) -> [BallDetection] {
        let context = frameState.safeContext  // 💥 Will crash if not set, as intended

        let descriptor = FetchDescriptor<BallDetection>(
            predicate: #Predicate { $0.frameUUID == uuid }
        )

        do {
            let results = try context.fetch(descriptor)
            print("✅ Loaded \(results.count) detections for frame \(uuid)")
            if let imageSize = frameState.currentImage?.size {
                return convertDetectionsToImageSpace(results, imageSize: imageSize)
            } else {
                return results
            }
        } catch {
            print("❌ Error fetching detections for frame \(uuid): \(error)")
            return []
        }
    }
    
    func convertDetectionsToImageSpace(_ detections: [BallDetection], imageSize: CGSize) -> [BallDetection] {
        for detection in detections {
            detection.boundingBoxMinX *= Double(imageSize.width)
            detection.boundingBoxMinY *= Double(imageSize.height)
            detection.boundingBoxWidth  *= Double(imageSize.width)
            detection.boundingBoxHeight *= Double(imageSize.height)
            
            detection.computedCenterX *= Double(imageSize.width)
            detection.computedCenterY *= Double(imageSize.height)
            
            detection.roiBoundingBoxOriginX *= Double(imageSize.width)
            detection.roiBoundingBoxOriginY *= Double(imageSize.height)
            detection.roiBoundingBoxWidth   *= Double(imageSize.width)
            detection.roiBoundingBoxHeight  *= Double(imageSize.height)
        }
        return detections
    }
    
    private func updateOpacities() {
        for i in 0..<compositeFrames.count {
            let frameIndex = centerFrameIndex - preloadMargin + i
            compositeFrames[i].opacity = visibleRange.contains(frameIndex) ? opacityForIndex(frameIndex) : 0
        }
    }

    func loadImage(for frame: Frame) -> UIImage? {
        guard let path = frame.imagePath else {
            print("⚠️ loadImage: No imagePath for frame \(frame.frameName)")
            return nil
        }

        let resolvedPath = FilePathResolver.resolveFullPath(for: path)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("❌ loadImage: File does not exist at path: \(resolvedPath)")
            return nil
        }

        if let image = UIImage(contentsOfFile: resolvedPath) {
            print("✅ loadImage: Successfully loaded image for frame \(frame.frameName) (\(frame.id))")
            return image
        } else {
            print("❌ loadImage: Failed to decode image from file at path: \(resolvedPath)")
            return nil
        }
    }

    private func opacityForIndex(_ index: Int) -> Double {
        let distance = abs(index - centerFrameIndex)
        
        switch distance {
        case 0: return 0.5   // center frame
        case 1: return 0.8
        case 2: return 0.9
        case 3: return 1.0
        default: return 1.0  // furthest frames — strongest blend base
        }
    }

    private func zIndexForIndex(_ index: Int) -> Double {
        let distance = abs(index - centerFrameIndex)
        // Reverse order: closer frames go on top
        return Double(100 - distance)
    }
    
    private func colorForAnnotation(_ index: Int) -> Color {
        let distance = abs(index - centerFrameIndex)
        
        switch distance {
        case 0:
            return .red
        case 1:
            return .orange
        case 2...10:
            let blend = Double(distance - 2) / 8.0  // normalize 2–10 → 0.0–1.0
            let yellow = UIColor.yellow
            let white = UIColor.white
            
            var yRed: CGFloat = 0, yGreen: CGFloat = 0, yBlue: CGFloat = 0, yAlpha: CGFloat = 0
            var wRed: CGFloat = 0, wGreen: CGFloat = 0, wBlue: CGFloat = 0, wAlpha: CGFloat = 0

            yellow.getRed(&yRed, green: &yGreen, blue: &yBlue, alpha: &yAlpha)
            white.getRed(&wRed, green: &wGreen, blue: &wBlue, alpha: &wAlpha)

            let red = yRed * (1 - blend) + wRed * blend
            let green = yGreen * (1 - blend) + wGreen * blend
            let blue = yBlue * (1 - blend) + wBlue * blend

            return Color(red: Double(red), green: Double(green), blue: Double(blue))
            
        default:
            return .white
        }
    }
    
    private func zIndexForAnnotation(_ index: Int) -> Double {
        let distance = abs(index - centerFrameIndex)
        
        switch distance {
        case 0: return 102
        case 1: return 101
            // Center frame annotations go above image layers
        default: return 99 // Other annotations go below top image layer
        }
    }
}

//MARK: Composite Render Version --Too compute heavy
//
//import SwiftUI
//import SwiftData
//
//struct CompositeFrameItem {
//    let uuid: UUID
//    let image: UIImage?
//    let detections: [BallDetection]
//    var opacity: Double
//}
//
//struct CompositeOverlayView: View {
//    @EnvironmentObject var frameState: FrameState
//    
//    // The final composite image (built from the 21 neighboring frames)
//    @State private var compositeImage: UIImage?
//    
//    // We use 10 frames before and 10 after the center frame.
//    let neighborCount = 10
//
//    var body: some View {
//        ZStack {
//            if let compositeImage = compositeImage {
//                Image(uiImage: compositeImage)
//                    .resizable()
//                    .scaledToFit()
//            } else {
//                Text("🔄 Building composite...")
//            }
//        }
//        .onAppear {
//            buildAndSetCompositeImage()
//        }
//    }
//    
//    /// Builds the composite image from the current frame and its neighbors.
//    private func buildAndSetCompositeImage() {
//        guard let currentUUID = frameState.currentFrameUUID,
//              let centerIndex = frameState.frames.firstIndex(where: { $0.id == currentUUID }) else {
//            return
//        }
//        
//        // Determine the slice: 10 frames before and 10 after (if available)
//        let startIndex = max(0, centerIndex - neighborCount)
//        let endIndex = min(frameState.frames.count - 1, centerIndex + neighborCount)
//        
//        // Create composite items for each frame in the slice.
//        // Here we compute the opacity relative to the center.
//        let compositeItems: [CompositeFrameItem] = (startIndex...endIndex).map { i in
//            let frame = frameState.frames[i]
//            let image = loadImage(for: frame)
//            let detections = loadDetections(for: frame.id)
//            let relativeDistance = abs(i - centerIndex)
//            let opacity = compositeOpacity(for: relativeDistance)
//            return CompositeFrameItem(uuid: frame.id, image: image, detections: detections, opacity: opacity)
//        }
//        
//        // The center of our compositeItems array corresponds to the current frame.
//        let centerRelativeIndex = centerIndex - startIndex
//        
//        // Render the composite image
//        compositeImage = renderCompositeImage(from: compositeItems, centerRelativeIndex: centerRelativeIndex)
//    }
//    
//    /// Renders a single composite image from the provided composite frame items.
//    /// Items are drawn in order so that frames furthest from the center (with lower opacity)
//    /// are drawn first, and the center frame (with its annotations) on top.
//    private func renderCompositeImage(from items: [CompositeFrameItem], centerRelativeIndex: Int) -> UIImage? {
//        // Use the center frame’s image size (or a default if missing)
//        guard let centerItem = items[safe: centerRelativeIndex],
//              let baseImage = centerItem.image else {
//            return nil
//        }
//        let size = baseImage.size
//        
//        // Set up a graphics renderer.
//        let renderer = UIGraphicsImageRenderer(size: size)
//        let composite = renderer.image { context in
//            // Sort items so that those with the greatest distance from the center are drawn first.
//            let sortedItems = items.enumerated().sorted { (lhs, rhs) -> Bool in
//                let lhsDistance = abs(lhs.offset - centerRelativeIndex)
//                let rhsDistance = abs(rhs.offset - centerRelativeIndex)
//                return lhsDistance > rhsDistance
//            }
//            
//            // Draw each image and its annotations.
//            for (index, item) in sortedItems {
//                let distance = abs(index - centerRelativeIndex)
//                let opacity = compositeOpacity(for: distance)
//                
//                if let img = item.image {
//                    img.draw(in: CGRect(origin: .zero, size: size),
//                             blendMode: .normal,
//                             alpha: opacity)
//                }
//                
//                // Draw each detection as a stroked rectangle.
//                // (Assumes detection values are normalized relative to image dimensions.)
//                for detection in item.detections {
//                    let rectWidth = detection.boundingBoxWidth * size.width
//                    let rectHeight = detection.boundingBoxHeight * size.height
//                    let centerX = detection.computedCenterPoint.x * size.width
//                    let centerY = detection.computedCenterPoint.y * size.height
//                    let rect = CGRect(x: centerX - rectWidth / 2,
//                                      y: centerY - rectHeight / 2,
//                                      width: rectWidth,
//                                      height: rectHeight)
//                    
//                    let strokeColor = compositeColor(for: distance)
//                    context.cgContext.setStrokeColor(strokeColor.cgColor)
//                    context.cgContext.setLineWidth(2)
//                    context.cgContext.stroke(rect)
//                }
//            }
//        }
//        
//        return composite
//    }
//    
//    // MARK: - Helper Functions
//    
//    /// Returns an opacity value based on the distance from the center frame.
//    /// The center frame (distance 0) is fully opaque, and the further frames are less visible.
//    private func compositeOpacity(for distance: Int) -> CGFloat {
//        switch distance {
//        case 0: return 0.5    // Center frame: fully visible.
//        case 1: return 0.5
//        case 2: return 0.5
//        case 3: return 0.6
//        case 4: return 0.7
//        default: return 0.8  // Furthest frames: lowest opacity.
//        }
//    }
//    
//    /// Returns a stroke color for annotations based on the distance from the center.
//    /// For example, the center frame gets red; immediate neighbors get orange;
//    /// further frames are blended between yellow and white.
//    private func compositeColor(for distance: Int) -> UIColor {
//        if distance == 0 {
//            return .red
//        } else if distance == 1 {
//            return .orange
//        } else if distance <= 10 {
//            let blend = CGFloat(distance - 2) / 8.0
//            let yellow = UIColor.yellow
//            let white = UIColor.white
//            
//            var yRed: CGFloat = 0, yGreen: CGFloat = 0, yBlue: CGFloat = 0, yAlpha: CGFloat = 0
//            yellow.getRed(&yRed, green: &yGreen, blue: &yBlue, alpha: &yAlpha)
//            
//            var wRed: CGFloat = 0, wGreen: CGFloat = 0, wBlue: CGFloat = 0, wAlpha: CGFloat = 0
//            white.getRed(&wRed, green: &wGreen, blue: &wBlue, alpha: &wAlpha)
//            
//            let red = yRed * (1 - blend) + wRed * blend
//            let green = yGreen * (1 - blend) + wGreen * blend
//            let blue = yBlue * (1 - blend) + wBlue * blend
//            
//            return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
//        } else {
//            return .white
//        }
//    }
//    
//    /// Loads the detections (annotations) for a given frame UUID from the data context.
//    private func loadDetections(for uuid: UUID) -> [BallDetection] {
//        let context = frameState.safeContext  // Assumes safeContext is set.
//        let descriptor = FetchDescriptor<BallDetection>(
//            predicate: #Predicate { $0.frameUUID == uuid }
//        )
//        do {
//            let results = try context.fetch(descriptor)
//            return results
//        } catch {
//            print("Error fetching detections for frame \(uuid): \(error)")
//            return []
//        }
//    }
//    
//    /// Loads the image for a given frame from its file path.
//    private func loadImage(for frame: Frame) -> UIImage? {
//        guard let path = frame.imagePath else {
//            print("No imagePath for frame \(frame.frameName)")
//            return nil
//        }
//        
//        let resolvedPath = FilePathResolver.resolveFullPath(for: path)
//        guard FileManager.default.fileExists(atPath: resolvedPath) else {
//            print("File does not exist at path: \(resolvedPath)")
//            return nil
//        }
//        
//        return UIImage(contentsOfFile: resolvedPath)
//    }
//}
//
//// A safe array extension to avoid index-out-of-range errors.
//extension Collection {
//    subscript (safe index: Index) -> Element? {
//        return indices.contains(index) ? self[index] : nil
//    }
//}
