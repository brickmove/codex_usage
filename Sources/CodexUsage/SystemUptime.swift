import Foundation
import Darwin

enum SystemUptime {
    static func text(now: Date) -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0,
              bootTime.tv_sec > 0 else { return "开机时长暂不可用" }
        return text(elapsed: now.timeIntervalSince1970 - Double(bootTime.tv_sec))
    }

    static func text(elapsed: TimeInterval) -> String {
        let minutes = Int(max(0, elapsed) / 60)
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        let remainder = minutes % 60
        if days > 0 { return "已开机 \(days)天 \(hours)小时 \(remainder)分" }
        if hours > 0 { return "已开机 \(hours)小时 \(remainder)分" }
        return minutes > 0 ? "已开机 \(minutes)分" : "已开机不足 1 分钟"
    }
}
