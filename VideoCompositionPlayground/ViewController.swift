//
//  ViewController.swift
//  VideoCompositionPlayground
//
//  Created by Reynaldo Aguilar on 14/8/19.
//

import UIKit
import AVKit
import AVFoundation

class ViewController: UIViewController {
    @IBOutlet weak var textField: UITextField!
    
    let renderSize = CGSize(width: 312, height: 424)
    var contentRect: CGRect = .zero
    let asset = AVAsset(url: Bundle.main.url(forResource: "video", withExtension: "MP4")!)
    let outputURL: URL = { () -> URL in
        let documentsDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return documentsDir.appendingPathComponent("video.mp4", isDirectory: false)
    }()
    
    @IBAction func trigger(_ sender: Any) {
        let width = Int(textField.text ?? "") ?? 0
        contentRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: 1920)
        
        let (reader, readerOutput) = buildReader()
        let (writer, writerInput) = buildWriter()
        
        writerInput.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
            while writerInput.isReadyForMoreMediaData {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    if let error = reader.error {
                        print("Finished with error: \(error)")
                    }
                    
                    writerInput.markAsFinished()
                    writer.finishWriting {
                        self.show(videoAt: writer.outputURL)
                    }
                    
                    return
                }
                
                writerInput.append(sampleBuffer)
            }
        }
    }
    
    private func show(videoAt url: URL) {
        DispatchQueue.main.async {
            let vc = AVPlayerViewController()
            vc.player = AVPlayer(url: url)
            self.show(vc, sender: self)
        }
    }
    
    private func buildReader() -> (AVAssetReader, AVAssetReaderOutput) {
        let reader = try! AVAssetReader(asset: asset)
        let videoTrack = asset.tracks(withMediaType: .video).first!
        
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        
        output.videoComposition = AVMutableVideoComposition(asset: asset, videoTrack: videoTrack, contentRect: contentRect, renderSize: renderSize)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        return (reader, output)
    }
    
    private func buildWriter() -> (AVAssetWriter, AVAssetWriterInput) {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try! FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try! AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: renderSize.width,
                AVVideoHeightKey: renderSize.height
            ]
        )
        
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        return (writer, input)
    }
}

extension AVMutableVideoComposition {
    convenience init(asset: AVAsset, videoTrack: AVAssetTrack, contentRect: CGRect, renderSize: CGSize) {
        // Compute transform for rendering the video content at `contentRect` with a size equal to `renderSize`.
        let trackFrame = CGRect(origin: .zero, size: videoTrack.naturalSize)
        let transformedFrame = trackFrame.applying(videoTrack.preferredTransform)
        let moveToOriginTransform = CGAffineTransform(translationX: -transformedFrame.minX, y: -transformedFrame.minY)
        let moveToContentRectTransform = CGAffineTransform(translationX: -contentRect.minX, y: -contentRect.minY)
        let scaleTransform = CGAffineTransform(scaleX: renderSize.width / contentRect.width, y: renderSize.height / contentRect.height)
        let transform = videoTrack.preferredTransform.concatenating(moveToOriginTransform).concatenating(moveToContentRectTransform).concatenating(scaleTransform)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layerInstruction]
        
        self.init(propertiesOf: asset)
        instructions = [instruction]
        self.renderSize = renderSize
    }
}
