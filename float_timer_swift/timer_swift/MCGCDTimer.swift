//
//  MCGCDTimer.swift
//  GCD Timer
//
//  Created by Enhart on 2017/6/15.
//  Copyright © 2017 Enhart. All rights reserved.
//

import UIKit

typealias ActionBlock = () -> ()

class MCGCDTimer {
    //Singleton
    static let shared = MCGCDTimer()
    
    lazy var timerContainer = [String: DispatchSourceTimer]()
    
    /// Bộ hẹn giờ GCD
    ///
    /// - Parameters:
    ///   - name: Tên bộ hẹn giờ
    ///   - timeInterval: Khoảng thời gian
    ///   - queue: Hàng đợi
    ///   - repeats: Có lặp lại không
    ///   - action: Closure thực thi tác vụ
    func scheduledDispatchTimer(WithTimerName name: String?, timeInterval: Double, queue: DispatchQueue, repeats: Bool, action: @escaping ActionBlock) {
        
        if name == nil {
            return
        }
        
        var timer = timerContainer[name!]
        if timer == nil {
            timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
            timer?.resume()
            timerContainer[name!] = timer
        }
        //Độ chính xác 1 mili giây
        timer?.schedule(deadline: .now(), repeating: timeInterval, leeway: DispatchTimeInterval.milliseconds(1))
        timer?.setEventHandler(handler: { [weak self] in
            action()
            if repeats == false {
                self?.cancleTimer(WithTimerName: name)
            }
        })
    }
    
    /// Hủy bộ hẹn giờ
    ///
    /// - Parameter name: Tên bộ hẹn giờ
    func cancleTimer(WithTimerName name: String?) {
        let timer = timerContainer[name!]
        if timer == nil {
            return
        }
        timerContainer.removeValue(forKey: name!)
        timer?.cancel()
    }
    
    
    /// Kiểm tra bộ hẹn giờ đã tồn tại chưa
    ///
    /// - Parameter name: Tên bộ hẹn giờ
    /// - Returns: Bộ hẹn giờ đã tồn tại chưa
    func isExistTimer(WithTimerName name: String?) -> Bool {
        if timerContainer[name!] != nil {
            return true
        }
        return false
    }
    
}

