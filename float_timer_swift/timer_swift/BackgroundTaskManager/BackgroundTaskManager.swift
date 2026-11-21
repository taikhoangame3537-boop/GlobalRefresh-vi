//
//  BackgroundTaskManager.swift
//  pip_swift
//
//  Created by 无夜之星辰 on 2022/8/31.
//

import Foundation
import AVFAudio
import AVKit

class BackgroundTaskManager: NSObject {
    
    static let shared = BackgroundTaskManager()
    
    func startPlay() {
        audioPlayer.play()
    }
    
    func stopPlay() {
        audioPlayer.stop()
    }
    
    var audioPlayer: AVAudioPlayer!
    
    private override init() {
        super.init()
        
        do {
            // Cho phép tiếp tục phát khi ở chế độ nền và khóa màn hình
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let mp4Video = Bundle.main.url(forResource: "slience", withExtension: "mp3")
            try audioPlayer = AVAudioPlayer.init(contentsOf: mp4Video!)
            audioPlayer.volume = 0
            audioPlayer.numberOfLoops = -1
            print("Thành công")
        } catch {
            print(error)
        }
    }
    
}
