import UIKit
import AVKit

// MARK: - ReaderMediaLinkOpener

// 视频源/音频源正文里出现的媒体直链（mp4/m3u8/…）。以前这些链接要么被
// 当普通文字渲染（plain 分支），要么点击后没有任何反应（HTML 分支的 <a>
// 走 onInternalLinkTap，而那条路只处理脚注/内部跳转）。现在：
//   * 生成层（ReaderHTMLUtilities.normalizedChapterHTML）把"整段是媒体
//     直链"的段落渲染成「▶ 點擊播放」锚点；
//   * 消费层（onInternalLinkTap 闭包）命中媒体直链时调本类型直接弹系统
//     播放器开播，不再把链接留在阅读页里。
enum ReaderMediaLinkOpener {
    /// 命中媒体直链则返回 URL，否则 nil。
    static func playableMediaURL(fromHref href: String) -> URL? {
        ReaderHTMLUtilities.playableMediaURL(fromHref: href)
    }

    /// 在最上层控制器上弹出系统播放器（pageSheet，可下拉关闭）。
    @MainActor
    static func presentPlayer(for url: URL) {
        guard let top = topPresenter() else { return }
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        top.present(controller, animated: true) {
            player.play()
        }
    }

    @MainActor
    private static func topPresenter() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
