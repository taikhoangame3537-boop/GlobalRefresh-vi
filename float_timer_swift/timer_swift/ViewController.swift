//
//  ViewController.swift
//  timer_swift
//
//  Created by 无夜之星辰 on 2021/11/12.
//

import UIKit
import AVKit

class ViewController: UIViewController, AVPictureInPictureControllerDelegate {
    
    private let timerName = "floatTimer"
    
    // Trình phát
    private var playerLayer: AVPlayerLayer!
    // Hình trong hình
    var pipController: AVPictureInPictureController!
    // view tùy chỉnh của bạn
    var customView: FloatClockView! = FloatClockView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        print("Trước khi khởi tạo Hình trong hình: \(UIApplication.shared.windows)")
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print(error)
            }
            setupUI()
            setupCustomView()
            setupPlayer()
            setupPip()
        } else {
            let alertVC = UIAlertController(title: "Tính năng yêu cầu iOS 14 trở lên, vui lòng nâng cấp hệ điều hành", message: nil, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Đã hiểu", style: .cancel, handler: nil)
            alertVC.addAction(cancelAction)
            present(alertVC, animated: true)
        }
    }
    
    private func setupUI() {
        let pipButton = UIButton(type: .system)
        view.addSubview(pipButton)
        pipButton.setTitle("Mở/Đóng Hình trong hình", for: .normal)
        pipButton.addTarget(self, action: #selector(pipButtonClicked), for: .touchUpInside)
        pipButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(40)
        }
        
        let millisecondButton = UIButton(type: .system)
        view.addSubview(millisecondButton)
        millisecondButton.setTitle("Hiện/Ẩn mili giây", for: .normal)
        millisecondButton.addTarget(self, action: #selector(millisecondButtonClicked), for: .touchUpInside)
        millisecondButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.height.equalTo(pipButton)
            make.top.equalTo(pipButton.snp.bottom).offset(30)
        }
    }
    
    // Cấu hình trình phát
    private func setupPlayer() {
        playerLayer = AVPlayerLayer()
        playerLayer.frame = .init(x: 90, y: 90, width: 200, height: 150)
        
        let mp4Video = Bundle.main.url(forResource: "横向视频", withExtension: "MP4")
        let asset = AVAsset.init(url: mp4Video!)
        let playerItem = AVPlayerItem.init(asset: asset)
        
        let player = AVPlayer.init(playerItem: playerItem)
        playerLayer.player = player
        player.isMuted = true
        player.allowsExternalPlayback = true
        
        view.layer.addSublayer(playerLayer)
    }
    
    // Cấu hình Hình trong hình
    private func setupPip() {
        pipController = AVPictureInPictureController.init(playerLayer: playerLayer)!
        pipController.delegate = self
        // Ẩn nút phát và nút tua tới/tua lui
        pipController.setValue(1, forKey: "controlsStyle")
    }
    
    // Cấu hình view tùy chỉnh
    private func setupCustomView() {
        customView.isShowMilsecond = false
    }
    
    // Bật/Tắt Hình trong hình
    @objc private func pipButtonClicked() {
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
            countDown()
        }
    }
    
    // Đếm ngược
    @objc private func countDown() {
        
        // Hủy timer trước
        cancelTimer()
        
        // Màn hình làm mới khoảng mỗi 17s nên đặt đếm ngược 1s thực ra không có ý nghĩa. Ngoài ra mỗi lần đếm ngược đều có sai số, tần suất quá cao sẽ làm sai số quá lớn, thể hiện rõ trên các thiết bị cũ như 6s
        MCGCDTimer.shared.scheduledDispatchTimer(WithTimerName: timerName, timeInterval: 0.034, queue: .global(), repeats: true) {
            
            DispatchQueue.main.async {
                let timeInterval = Date().timeIntervalSince1970
                
                
                let date = Date.init(timeIntervalSince1970: timeInterval)
                let dateFormat = DateFormatter()
                
                if self.customView.isShowMilsecond {
                    // Hiện mili giây
                    dateFormat.dateFormat = "HH:mm:ss.SSS"
                } else {
                    dateFormat.dateFormat = "HH:mm:ss"
                }
                
                let dateString = dateFormat.string(from: date)
                self.customView.timeLabel.text = dateString
                //self.customView.offsetLabel.text = self.currentOffsetTimeLabel.text
            }
            
        }
        
    }
    
    private func cancelTimer() {
        if MCGCDTimer.shared.isExistTimer(WithTimerName: timerName) {
            MCGCDTimer.shared.cancleTimer(WithTimerName: timerName)
        }
    }
    
    // Hiện/Ẩn mili giây
    @objc private func millisecondButtonClicked() {
        customView.isShowMilsecond = !customView.isShowMilsecond
    }
    
    // MARK: - Delegate
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // In tất cả window, bạn sẽ thấy lúc này có thêm một window
        print("Sau khi khởi tạo Hình trong hình: \(UIApplication.shared.windows)")
        // Lưu ý là first window
        let window = UIApplication.shared.windows.first
        // Thêm view tùy chỉnh vào Hình trong hình
        window?.addSubview(customView)
        // Dùng Auto Layout
        customView.snp.makeConstraints { (make) -> Void in
            make.edges.equalToSuperview()
        }
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        //startTimer()
        // In tất cả window
        print("Sau khi Hình trong hình bật lên: \(UIApplication.shared.windows)")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        //stopTimer()
    }
    
}

