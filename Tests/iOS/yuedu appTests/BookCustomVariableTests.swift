import Testing
@testable import yuedu_app

struct BookCustomVariableTests {
    @Test("the book variable is stored where the parser hands it to book.getVariable")
    func storesUnderBookVariablePrefix() {
        #expect(BookCustomVariable.key == "book.variable.custom")
    }

    @Test("setting the book variable writes only `custom`")
    func mergeKeepsOtherKeys() {
        let merged = BookCustomVariable.merged("token=1", into: ["bookId": "42"])
        #expect(merged == ["bookId": "42", "book.variable.custom": "token=1"])
        #expect(BookCustomVariable.value(in: merged) == "token=1")
    }

    @Test("clearing the book variable removes `custom` and nothing else")
    func clearRemovesOnlyCustom() {
        #expect(BookCustomVariable.merged("", into: ["bookId": "42", "book.variable.custom": "x"]) == ["bookId": "42"])
        #expect(BookCustomVariable.merged("", into: ["book.variable.custom": "x"]) == nil)
    }
}
