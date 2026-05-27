#!/usr/bin/swift

// Import necessary frameworks
import Foundation
import AppKit // Required for NSPasteboard

// --- Configuration ---
// If true, reads file paths from command line arguments.
// If false, uses the hardcoded 'exampleFileURLs'.
let useCommandLineArgs = false

// Example file URLs (used if useCommandLineArgs is false)
let exampleFileURLs: [URL] = [
    URL(fileURLWithPath: "/Users/atacan/Developer/Repositories/doubledock/Sources/Server/ServerAPI.swift"),
    URL(fileURLWithPath: "/Users/atacan/Developer/Repositories/doubledock/Sources/Server/specs/postgres_ddls.sql"),
    URL(fileURLWithPath: "/Users/atacan/Developer/Repositories/doubledock/Sources/Server/specs/openapi.yaml"),
    URL(fileURLWithPath: "/Users/atacan/Developer/Repositories/doubledock/Sources/Server/StripeWebhookController.swift")
]
// --- End Configuration ---


// --- Core Logic ---

/// Takes an array of file URLs, reads their content, formats them into
/// Markdown code blocks, combines them, and copies the result to the pasteboard.
///
/// - Parameter fileURLs: An array of `URL` objects pointing to the files.
func combineFilesToMarkdownClipboard(fileURLs: [URL]) {
    var combinedMarkdown = ""
    var processedFileURLs: [URL] = []
    var skippedFiles: [String: String] = [:] // [FilePath: ErrorMessage]

    print("Processing files...")

    for fileURL in fileURLs {
        // Ensure we are dealing with standard file paths
        guard fileURL.isFileURL else {
            let path = fileURL.absoluteString // Use absoluteString for non-file URLs
            print("⚠️ Skipping non-file URL: \(path)")
            skippedFiles[path] = "Not a file URL"
            continue
        }

        let filePath = fileURL.path // Get the standard path string
        let filename = fileURL.lastPathComponent

        print("  - Reading: \(filePath)")

        do {
            // Read file content
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            // Create Markdown code block
            // Using """ for multi-line string literal simplifies formatting
            let markdownBlock = """
            ```\(filename)
            \(content.trimmingCharacters(in: .whitespacesAndNewlines))
            ```
            """

            // Add the block to the combined string, prefixed with a newline
            // if this isn't the first block.
            if !combinedMarkdown.isEmpty {
                combinedMarkdown += "\n\n" // Add separation between blocks
            }
            combinedMarkdown += markdownBlock
            processedFileURLs.append(fileURL)

        } catch {
            // Handle errors (file not found, permission denied, encoding issue)
            print("❌ Error reading file \(filePath): \(error.localizedDescription)")
            skippedFiles[filePath] = error.localizedDescription
        }
    }

    print("\n--- Processing Summary ---")
    print("✅ Processed \(processedFileURLs.count) file(s):")
    for url in processedFileURLs {
        print("  - \(url.path)")
    }

    if !skippedFiles.isEmpty {
        print("\n⚠️ Skipped \(skippedFiles.count) file(s):")
        for (path, reason) in skippedFiles {
            print("  - \(path): \(reason)")
        }
    }

    // Check if any content was generated
    if combinedMarkdown.isEmpty {
        print("\nNo content generated. Nothing copied to clipboard.")
        return
    }

    // Copy to pasteboard
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents() // Clear previous content
    // Set the string content for the pasteboard
    if pasteboard.setString(combinedMarkdown, forType: .string) {
        print("\n🚀 Combined content successfully copied to clipboard!")
    } else {
        print("\n❌ Failed to copy content to clipboard.")
    }
}


// --- Execution ---

// Determine the source of file URLs
let targetFileURLs: [URL]
if useCommandLineArgs {
    // Get arguments from command line, skipping the script name itself (index 0)
    let arguments = CommandLine.arguments
    if arguments.count <= 1 {
        print("Usage: \(arguments[0]) <file1> <file2> ...")
        print("Please provide at least one file path as a command line argument.")
        // Exit if no arguments are provided when expected
        exit(1) // Use exit(0) for success, non-zero for error
    }
     // Convert argument strings to file URLs
    targetFileURLs = arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    print("Reading file paths from command line arguments.")
} else {
    targetFileURLs = exampleFileURLs
    print("Using hardcoded example file paths.")
}

// Run the main function
combineFilesToMarkdownClipboard(fileURLs: targetFileURLs)