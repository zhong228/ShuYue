import Testing
@testable import yuedu_app

struct BookIntroContentTests {
    @Test("block tags become indented paragraphs, as Legado's HtmlFormatter makes them")
    func formatsParagraphs() {
        let formatted = LegadoHTMLFormatter.format("<div><p>第一段</p><br><p>第二段</p></div>")
        #expect(formatted == "　　第一段\n　　第二段")
    }

    @Test("inline tags and comments are removed, spacing entities become spaces")
    func stripsInlineMarkup() {
        // Legado indents only text that began with whitespace or a block tag.
        let formatted = LegadoHTMLFormatter.format("<b>粗體</b>&nbsp;&nbsp;文字<!-- note --><span class=\"x\">尾</span>")
        #expect(formatted == "粗體 文字尾")
    }

    @Test("other entities are decoded")
    func decodesEntities() {
        #expect(LegadoHTMLFormatter.format("甲&amp;乙") == "甲&乙")
    }

    @Test("prefix modes are recognised regardless of case and lose their closing tag")
    func parsesPrefixModes() {
        #expect(BookIntroContent("  <usehtml><b>x</b></usehtml>") == .html("<b>x</b>"))
        #expect(BookIntroContent("<MD># 標題\n內文") == .markdown("# 標題\n內文"))
        #expect(BookIntroContent("<useweb><html><body>y</body></html></useweb>") == .web("<html><body>y</body></html>"))
        #expect(BookIntroContent("　　普通簡介") == .plain("　　普通簡介"))
    }

    @Test("sanitizing keeps a prefix-mode intro's markup and cleans a plain one")
    func sanitizeRespectsModes() {
        let rich = OnlineBookDetailPresentationPolicy.sanitizeIntro("<usehtml><p style=\"color:red\">紅</p>")
        #expect(rich == "<usehtml><p style=\"color:red\">紅</p>")
        let plain = OnlineBookDetailPresentationPolicy.sanitizeIntro("<p>甲</p><p>乙</p>")
        #expect(plain == "　　甲\n　　乙")
    }

    @Test("the detail intro indents every paragraph, the first included, as MD3 shows it")
    func indentsEveryParagraph() {
        let intro = OnlineBookDetailPresentationPolicy.sanitizeIntro("世间生灵，体生异骨。\n  此为，神通骨。\n\n身具骨者")
        #expect(intro == "　　世间生灵，体生异骨。\n　　此为，神通骨。\n　　身具骨者")
    }

    // MARK: Interactive <usehtml>

    @Test("a button shows its label and keeps its script, as legado-E and MD3 split it")
    func marksButtons() {
        let fragment = BookIntroInteractiveFragment(fragment: """
        <p>讀者 <button style="">💬 书籍讨论@onclick:showCmt("https://a.com/x","番茄",'本书讨论')</button></p>
        """)
        #expect(fragment.actions == [BookIntroAction(
            kind: .button,
            name: "💬 书籍讨论",
            script: #"showCmt("https://a.com/x","番茄",'本书讨论')"#
        )])
        #expect(!fragment.html.contains("@onclick"))
        #expect(fragment.html.contains(#"data-yd-action="0""#))
        #expect(fragment.html.contains(BookIntroInteractiveFragment.buttonClass))
        #expect(fragment.html.contains("💬 书籍讨论</button>"))
    }

    @Test("a button without the separator is plain text, a blank script runs nothing")
    func inertButtons() {
        let plain = BookIntroInteractiveFragment(fragment: "<button>只是文字</button>")
        #expect(plain.actions.isEmpty)
        #expect(!plain.html.contains("<button"))
        #expect(plain.html.contains("只是文字"))

        let blank = BookIntroInteractiveFragment(fragment: "<button>空的@onclick:  </button>")
        #expect(blank.actions.isEmpty)
        #expect(blank.html.contains("空的</button>"))
        #expect(!blank.html.contains(BookIntroInteractiveFragment.actionAttribute))
    }

    @Test("an image loads its bare URL and runs the click from its URL options")
    func marksImages() {
        let fragment = BookIntroInteractiveFragment(fragment: """
        <img src='https://a.com/c.png , {"click":"showPic(1)"}'><img src='https://a.com/d.png,{"headers":{"Referer":"https://a.com"}}'>
        """)
        #expect(fragment.actions == [BookIntroAction(kind: .image, name: "", script: "showPic(1)")])
        #expect(fragment.html.contains(#"src="https://a.com/c.png""#))
        #expect(fragment.html.contains(#"src="https://a.com/d.png""#))
        #expect(!fragment.html.contains("headers"))
        #expect(fragment.html.contains(#"role="button""#))
    }

    @Test("buttons and images share one index sequence")
    func indexesActions() {
        let fragment = BookIntroInteractiveFragment(fragment: """
        <button>甲@onclick:a()</button><img src='x.png,{"click":"b()"}'><button>乙@onclick:c()</button>
        """)
        #expect(fragment.actions.map(\.script) == ["a()", "c()", "b()"])
        #expect(fragment.html.contains(#"data-yd-action="2""#))
    }
}
