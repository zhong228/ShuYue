import Foundation
import ReadiumShared

/// A sendable presentation snapshot of a resource failure. It carries no reader
/// state, credentials, response body, or source-controlled HTML into the alert.
struct RemoteLibraryReadFailure: Hashable, Sendable {
    let bookID: UUID
    let message: String

    init(bookID: UUID, message: String) {
        self.bookID = bookID
        self.message = message
    }

    init?(bookID: UUID, error: HTTPError) {
        self.bookID = bookID
        switch error {
        case .cancelled:
            return nil
        case .errorResponse(let response):
            switch response.status.rawValue {
            case 401, 403: message = localized("认证失败，请确认帐号和密码")
            case 412: message = localized("远端书籍已更新，请返回书籍详情重新开启")
            default: message = String(format: localized("连线失败（HTTP %d）"), response.status.rawValue)
            }
        case .offline, .unreachable:
            message = localized("无法连线至书库，请检查网路与伺服器。")
        case .timeout:
            message = localized("连线逾时")
        case .rangeNotSupported:
            message = localized("伺服器不支援分段读取")
        case .malformedRequest, .malformedResponse:
            message = localized("伺服器传回的书籍资料无效")
        case .security(let underlying):
            message = underlying?.localizedDescription ?? localized("无法建立安全连线")
        case .redirection(let underlying):
            message = underlying?.localizedDescription ?? localized("伺服器重新导向失败")
        case .fileSystem(let underlying):
            message = underlying.localizedDescription
        case .other(let underlying):
            message = underlying.localizedDescription
        }
    }
}
