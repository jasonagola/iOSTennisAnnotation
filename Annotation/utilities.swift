//
//  utilities.swift
//  Annotation
//
//  Created by Jason Agola on 3/21/25.
//

import Foundation
import SwiftUI

enum FilePathResolver {
    
    /// Resolves a relative path to an absolute path in the user's documents directory.
    static func resolveFullPath(for relativePath: String) -> String {
        let baseURL = documentsDirectory()
        let fullPath = baseURL.appendingPathComponent(relativePath).path
        return fullPath
    }

    /// Returns true if the file exists at the resolved full path.
    static func fileExists(at relativePath: String) -> Bool {
        let fullPath = resolveFullPath(for: relativePath)
        return FileManager.default.fileExists(atPath: fullPath)
    }

    /// Optionally resolves a path to a URL (e.g., for AVFoundation).
    static func resolveURL(for relativePath: String) -> URL {
        return documentsDirectory().appendingPathComponent(relativePath)
    }

    /// Base documents directory for the app sandbox.
    private static func documentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}


enum DirectoryLoader {
    //Safe container loading 
    static func loadImage(for frame: Frame) -> UIImage? {
        guard let path = frame.imagePath else {
            print("loadImage: ERROR - No imagePath for frame \(frame.frameName)")
            return nil
        }
        let resolvedPath = FilePathResolver.resolveFullPath(for: path)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("loadImage: ERROR - File does not exist at path: \(resolvedPath)")
            return nil
        }
        if let image = UIImage(contentsOfFile: resolvedPath) {
            print("loadImage: ✅ Successfully loaded image for frame \(frame.frameName) (\(frame.id))")
            return image
        } else {
            print("loadImage: ❌ Failed to decode image from file at path: \(resolvedPath)")
            return nil
        }
    }
}

