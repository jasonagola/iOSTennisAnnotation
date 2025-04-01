//
//  AppEntryView.swift
//  Annotation
//
//  Created by Jason Agola on 3/26/25.
//

import SwiftUI

struct AppEntryView: View {
    @StateObject private var frameState = FrameState() // no parameters
    
    var body: some View {
        ContentView()
            .environmentObject(frameState)
    }
}
