import SwiftUI

// MARK: - MoYue 专属政策文档

/// In-app legal documents. MoYue ships its own privacy policy and user
/// agreement as local content; the upstream 閱讀 web pages are intentionally
/// not referenced. Each document is plain SwiftUI text so it stays readable
/// without network access and can never drift out of the shipped build.
enum MoYueLegalDocument {
    case privacy
    case userAgreement

    var navigationTitle: String {
        switch self {
        case .privacy:
            return localized("隱私權政策")
        case .userAgreement:
            return localized("使用者協議")
        }
    }

    var sections: [(heading: String, body: String)] {
        switch self {
        case .privacy:
            return Self.privacySections
        case .userAgreement:
            return Self.agreementSections
        }
    }

    // MARK: - 隐私权政策

    private static let privacySections: [(heading: String, body: String)] = [
        (
            "一、概述",
            "书悦（ShuYue）是一款开源电子书与书源阅读应用。我们非常重视你的隐私。本政策说明书悦如何处理你的数据。你使用书悦即表示你阅读并理解本政策。"
        ),
        (
            "二、我们收集哪些信息",
            "书悦以本地优先为设计原则。你的书架、阅读进度、书签、书源、主题设置、替换规则等数据默认只保存在你的设备本地。书悦本身不收集、不上传你的阅读记录、书源内容或个人信息。"
        ),
        (
            "三、云同步与 iCloud",
            "如果你主动开启 iCloud 同步，相关数据（如书架与阅读进度）会存储在你本人的 iCloud 账户中，并由 Apple 按其隐私政策处理。书悦无法访问你的 iCloud 账户凭据。"
        ),
        (
            "四、书源与网络请求",
            "书悦支持用户自行导入书源（Legado 格式）并从第三方网站获取内容。使用书源时，请求将由你的设备直接向对应网站发起。该网站可能记录你的网络请求信息，其数据处理行为由该网站决定，与书悦无关。请仅使用你已获得授权的书源。"
        ),
        (
            "五、第三方服务",
            "书悦可能通过你的系统提供的服务（如系统邮件、系统分享）帮助你完成操作，例如向我们发送反馈邮件。此类操作由系统服务完成，书悦不会在你的设备之外额外处理相关内容。"
        ),
        (
            "六、数据存储与删除",
            "卸载书悦或在应用内删除相关内容，即会清除相应本地数据。你随时可以在应用设置中管理或清空本地缓存与数据。"
        ),
        (
            "七、未成年人保护",
            "书悦面向一般用户提供服务。若你为未成年人，请在监护人指导下使用，并谨慎导入与阅读内容。"
        ),
        (
            "八、政策更新",
            "我们可能适时更新本政策。更新后的政策将在应用内公布，重大变更会以适当方式提示。继续使用书悦即表示你接受更新后的政策。"
        ),
        (
            "九、联系我们",
            "如你对本政策有任何疑问，可通过应用「关于」页中的电子邮箱与我们联系。"
        ),
    ]

    // MARK: - 用户协议

    private static let agreementSections: [(heading: String, body: String)] = [
        (
            "一、协议的接受",
            "本协议是您与书悦（ShuYue）之间关于使用本应用及服务的约定。您下载、安装或使用书悦，即表示您已阅读、理解并同意接受本协议的全部条款。"
        ),
        (
            "二、许可与使用",
            "书悦以开源方式发布（详见应用内「原始码与开源授权」）。您可以自由使用书悦进行个人阅读。未经明确授权，不得将书悦用于任何商业性规模化服务。"
        ),
        (
            "三、书源与内容责任",
            "书悦本身不提供任何书籍内容。您导入的书源（Legado 格式）由第三方维护，所获内容来自第三方网站。您应确保：仅使用已获授权的内容源；自行判断内容的合法性；理解第三方网站可能变更接口或失效。因书源或第三方内容产生的任何争议，由对应网站与使用者自行承担，书悦不因此承担连带责任。"
        ),
        (
            "四、网络与第三方服务",
            "使用书源、在线搜索、网页浏览等功能需要网络连接。相关网络服务由对应网站提供。书悦不对第三方服务的可用性、稳定性或内容负责。"
        ),
        (
            "五、知识产权",
            "书悦的源代码按开源协议（MPL-2.0）授权。您导入的书源、书籍及其内容的知识产权归相应权利人所有。请您尊重版权，仅阅读与使用您有权访问的内容。"
        ),
        (
            "六、禁止行为",
            "您不得利用书悦从事下列行为：传播违法或侵权内容；恶意攻击、干扰第三方网站或服务；绕过您并不拥有访问权的内容保护；以任何方式损害第三方合法权益。"
        ),
        (
            "七、免责声明",
            "书悦按「现状」提供服务。在适用法律允许的最大范围内，书悦不对服务的适销性、特定用途适用性作任何明示或暗示保证。因使用本应用产生的损失，书悦不承担超出法律规定范围的赔偿责任。"
        ),
        (
            "八、条款变更",
            "我们可能适时修订本协议。修订后的协议在应用内公布后即生效。您继续使用书悦，即视为接受修订后的协议。"
        ),
        (
            "九、法律适用与争议解决",
            "本协议的订立、履行与解释适用中华人民共和国法律。因本协议产生的争议，双方应友好协商解决；协商不成的，提交有管辖权的人民法院处理。"
        ),
        (
            "十、联系我们",
            "如您对本协议有任何疑问，可通过应用「关于」页中的电子邮箱与我们联系。"
        ),
    ]
}

/// Renders a single in-app legal document with a readable, settings-themed layout.
struct MoYueLegalDocumentView: View {
    let document: MoYueLegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(DSFont.headline.weight(.semibold))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(section.body)
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
        .softScrollEdges()
        .navigationTitle(document.navigationTitle)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }
}