import AppKit
import Metal

/// Offline visual fixture only. Never used as a desktop or lid sensor fallback.
@MainActor
func renderReference(_ renderer: MetalRenderer, config: AnimationConfig) throws {
    let width = 880, height = 570
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width*4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(starting: NSColor(red:0.15,green:0.24,blue:0.40,alpha:1), ending: NSColor(red:0.55,green:0.70,blue:0.82,alpha:1))!.draw(in: NSRect(x:0,y:0,width:width,height:height), angle: -90)
    for y in stride(from: 40, to: height, by: 90) {
        for x in stride(from: 30, to: width-30, by: 60) {
            NSColor.white.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect:NSRect(x:x,y:y,width:18,height:18),xRadius:3,yRadius:3).fill()
        }
    }
    let text: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize:78,weight:.medium), .foregroundColor:NSColor.white]
    ("9:41" as NSString).draw(at:NSPoint(x:345,y:390),withAttributes:text)
    ("Duo • Metal reference" as NSString).draw(at:NSPoint(x:315,y:495),withAttributes:[.font:NSFont.systemFont(ofSize:22),.foregroundColor:NSColor.white])
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect:NSRect(x:300,y:20,width:280,height:8),xRadius:4,yRadius:4).fill()
    NSGraphicsContext.restoreGraphicsState()
    let sourceDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
    sourceDesc.storageMode = .shared; sourceDesc.usage = .shaderRead
    let source = renderer.device.makeTexture(descriptor:sourceDesc)!
    source.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:bitmap.bitmapData!,bytesPerRow:width*4)
    let targetDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
    targetDesc.storageMode = .shared; targetDesc.usage = [.renderTarget,.shaderRead]
    let target = renderer.device.makeTexture(descriptor:targetDesc)!
    let queue = renderer.device.makeCommandQueue()!
    let folder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ReferenceFrames")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    for p: Float in [0,0.35,0.65,1] {
        let command = queue.makeCommandBuffer()!
        let blurred = try renderer.progressiveBlur.encode(command:command,source:source,strength:config.blurStrength)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store; pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1)
        let encoder = command.makeRenderCommandEncoder(descriptor:pass)!
        var u = ShaderUniforms(progress:p,perspective:config.perspectiveStrength,blur:config.blurStrength,darkness:config.darkness,compression:config.verticalCompression,width:Float(width),height:Float(height))
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setVertexBytes(&u,length:MemoryLayout<ShaderUniforms>.stride,index:0)
        encoder.setFragmentBytes(&u,length:MemoryLayout<ShaderUniforms>.stride,index:0)
        encoder.setFragmentTexture(source,index:0)
        for (index,t) in blurred.enumerated() { encoder.setFragmentTexture(t,index:index+1) }
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:32*48*6)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
        for i in stride(from:0,to:pixels.count,by:4) { pixels.swapAt(i,i+2) }
        let output = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
        pixels.withUnsafeBytes { output.bitmapData!.update(from:$0.baseAddress!.assumingMemoryBound(to:UInt8.self),count:pixels.count) }
        try output.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("fold-\(p).png"))
    }
    print("PASS: reference renders saved to \(folder.path)")
}
