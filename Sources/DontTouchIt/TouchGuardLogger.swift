import AppKit
import CoreGraphics
import Foundation

final class TouchGuardLogger {
    static let shared = TouchGuardLogger()

    let fileURL: URL

    private let queue = DispatchQueue(label: "com.dont-touch-it.guard-log")
    private let dateFormatter = ISO8601DateFormatter()
    private let maximumFileSize = 256 * 1024
    private let formatHeader = "===== PRIVACY-SAFE LOG FORMAT V1 ====="
    private var fileHandle: FileHandle?
    private var currentFileSize = 0

    private init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        fileURL = libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Don't Touch It", isDirectory: true)
            .appendingPathComponent("TouchGuard.log", isDirectory: false)
        dateFormatter.formatOptions = [.withInternetDateTime]
    }

    func beginGuard(context: [String]) {
        queue.sync {
            openFileIfNeeded()
            writeLine("===== TOUCH GUARD START =====")
            context.forEach(writeLine)
        }
    }

    func record(_ message: String) {
        queue.async { [weak self] in
            self?.openFileIfNeeded()
            self?.writeLine(message)
        }
    }

    func endGuard(summary: String) {
        queue.sync {
            openFileIfNeeded()
            writeLine("TOUCH GUARD STOP: \(summary)")
            writeLine("===== TOUCH GUARD END =====")
            do {
                try fileHandle?.synchronize()
                try fileHandle?.close()
            } catch {
                NSLog("Don't Touch It log close failed")
            }
            fileHandle = nil
            currentFileSize = 0
        }
    }

    func revealLogInFinder() {
        queue.sync {
            openFileIfNeeded()
            fileHandle?.synchronizeFile()
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func clear() throws {
        try queue.sync {
            try fileHandle?.close()
            fileHandle = nil
            currentFileSize = 0
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            let directoryURL = fileURL.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path),
               contents.isEmpty {
                try FileManager.default.removeItem(at: directoryURL)
            }
        }
    }

    private func openFileIfNeeded() {
        guard fileHandle == nil else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            } else {
                try trimExistingLogIfNeeded()
                try clearLegacyLogIfNeeded()
            }
            fileHandle = try FileHandle(forWritingTo: fileURL)
            currentFileSize = Int(try fileHandle?.seekToEnd() ?? 0)
            if currentFileSize == 0 {
                writeLine(formatHeader)
            }
        } catch {
            NSLog("Don't Touch It log open failed")
        }
    }

    private func clearLegacyLogIfNeeded() throws {
        let contents = try Data(contentsOf: fileURL)
        if contents.range(of: Data(formatHeader.utf8)) == nil {
            try Data().write(to: fileURL, options: .atomic)
        }
    }

    private func trimExistingLogIfNeeded() throws {
        let reader = try FileHandle(forReadingFrom: fileURL)
        defer { try? reader.close() }
        let size = try reader.seekToEnd()
        guard size > UInt64(maximumFileSize) else { return }
        try reader.seek(toOffset: size - UInt64(maximumFileSize))
        let tail = try reader.read(upToCount: maximumFileSize) ?? Data()
        try tail.write(to: fileURL, options: .atomic)
    }

    private func writeLine(_ message: String) {
        guard let fileHandle else { return }
        let singleLine = message.replacingOccurrences(of: "\n", with: " ")
        let line = "\(dateFormatter.string(from: Date())) \(singleLine)\n"
        do {
            let data = Data(line.utf8)
            if currentFileSize + data.count > maximumFileSize {
                try fileHandle.truncate(atOffset: 0)
                try fileHandle.seek(toOffset: 0)
                currentFileSize = 0
                let marker = Data("\(dateFormatter.string(from: Date())) LOG ROTATED AT SIZE LIMIT\n".utf8)
                try fileHandle.write(contentsOf: marker)
                currentFileSize += marker.count
                let header = Data("\(dateFormatter.string(from: Date())) \(formatHeader)\n".utf8)
                try fileHandle.write(contentsOf: header)
                currentFileSize += header.count
            }
            try fileHandle.write(contentsOf: data)
            currentFileSize += data.count
        } catch {
            NSLog("Don't Touch It log write failed")
        }
    }
}
