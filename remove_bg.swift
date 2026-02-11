import AppKit
import CoreGraphics

func removeBackgroundFloodFill(inputPath: String, outputPath: String) {
    guard let image = NSImage(contentsOfFile: inputPath) else {
        print("Failed to load image at \(inputPath)")
        exit(1)
    }

    guard let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) else {
        print("Failed to get bitmap representation")
        exit(1)
    }

    let width = bitmapRep.pixelsWide
    let height = bitmapRep.pixelsHigh
    
    // Create a context
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("Failed to create context")
        exit(1)
    }
    
    if let cgImage = bitmapRep.cgImage {
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    guard let data = context.data else {
        print("Failed to get context data")
        exit(1)
    }

    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var visited = [Bool](repeating: false, count: width * height)
    var queue: [(Int, Int)] = []

    // Threshold for background color (assumed white/off-white)
    let threshold: UInt8 = 240

    // Seed from corners
    let seeds = [(0, 0), (width-1, 0), (0, height-1), (width-1, height-1)]
    
    for seed in seeds {
        queue.append(seed)
        visited[seed.1 * width + seed.0] = true
    }

    // BFS Flood Fill to find background
    while !queue.isEmpty {
        let (cx, cy) = queue.removeFirst()
        let offset = (cy * width + cx) * 4
        
        let r = buffer[offset]
        let g = buffer[offset + 1]
        let b = buffer[offset + 2]

        // Check if pixel is "white" enough to be background
        if r > threshold && g > threshold && b > threshold {
            // Make transparent
            buffer[offset + 3] = 0
            
            // Add neighbors
            let behaviors = [(0, 1), (0, -1), (1, 0), (-1, 0)]
            for (dx, dy) in behaviors {
                let nx = cx + dx
                let ny = cy + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let idx = ny * width + nx
                    if !visited[idx] {
                        visited[idx] = true
                        queue.append((nx, ny))
                    }
                }
            }
        }
    }

    guard let newCGImage = context.makeImage() else {
        print("Failed to create new CGImage")
        exit(1)
    }

    let newRep = NSBitmapImageRep(cgImage: newCGImage)
    guard let pngData = newRep.representation(using: .png, properties: [:]) else {
        print("Failed to convert to PNG")
        exit(1)
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Successfully performed flood-fill transparency at \(outputPath)")
    } catch {
        print("Failed to write output file: \(error)")
        exit(1)
    }
}

let args = CommandLine.arguments
if args.count < 3 {
    print("Usage: swift remove_bg.swift <input> <output>")
    exit(1)
}

removeBackgroundFloodFill(inputPath: args[1], outputPath: args[2])
