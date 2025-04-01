//
//  utilities.swift
//  Annotation
//
//  Created by Jason Agola on 3/21/25.
//

import Foundation

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
