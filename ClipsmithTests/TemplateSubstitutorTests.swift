import XCTest
@testable import Clipsmith

final class TemplateSubstitutorTests: XCTestCase {

    // MARK: - testBasicSubstitution

    func testBasicSubstitution() {
        let result = TemplateSubstitutor.substitute(in: "Hello {{name}}", variables: ["name": "World"])
        XCTAssertEqual(result, "Hello World")
    }

    // MARK: - testClipboardSubstitution

    func testClipboardSubstitution() {
        let result = TemplateSubstitutor.substitute(in: "{{clipboard}}", variables: ["clipboard": "code"])
        XCTAssertEqual(result, "code")
    }

    // MARK: - testUnknownVariableLeftAsIs

    func testUnknownVariableLeftAsIs() {
        let result = TemplateSubstitutor.substitute(in: "{{unknown}}", variables: [:])
        XCTAssertEqual(result, "{{unknown}}", "Unknown variables should be left unchanged")
    }

    // MARK: - testMultipleVariablesReplaced

    func testMultipleVariablesReplaced() {
        let result = TemplateSubstitutor.substitute(
            in: "Hello {{first}} {{last}}",
            variables: ["first": "John", "last": "Doe"]
        )
        XCTAssertEqual(result, "Hello John Doe")
    }

    // MARK: - testAdjacentVariablesBothReplaced

    func testAdjacentVariablesBothReplaced() {
        let result = TemplateSubstitutor.substitute(
            in: "{{a}}{{b}}",
            variables: ["a": "Hello", "b": "World"]
        )
        XCTAssertEqual(result, "HelloWorld")
    }

    // MARK: - testWhitespaceTrimmedInVariableName

    func testWhitespaceTrimmedInVariableName() {
        let result = TemplateSubstitutor.substitute(
            in: "{{ name }}",
            variables: ["name": "World"]
        )
        XCTAssertEqual(result, "World", "Whitespace in {{  name  }} should be trimmed before dict lookup")
    }

    // MARK: - testNoVariablesUnchanged

    func testNoVariablesUnchanged() {
        let input = "This is a plain string with no variables."
        let result = TemplateSubstitutor.substitute(in: input, variables: ["name": "World"])
        XCTAssertEqual(result, input, "String with no variables should be returned unchanged")
    }

    // MARK: - testExtractVariables

    func testExtractVariables() {
        let vars = TemplateSubstitutor.extractVariables(from: "Hello {{name}} and {{age}}")
        XCTAssertEqual(vars, ["name", "age"])
    }

    // MARK: - testExtractVariablesDeduplicates

    func testExtractVariablesDeduplicates() {
        let vars = TemplateSubstitutor.extractVariables(from: "{{x}} and {{x}} again")
        XCTAssertEqual(vars, ["x"], "Duplicate variable names should be deduplicated")
    }

    // MARK: - testExtractVariablesEmpty

    func testExtractVariablesEmpty() {
        let vars = TemplateSubstitutor.extractVariables(from: "No variables here")
        XCTAssertEqual(vars, [], "No variables should return empty array")
    }

    // MARK: - testPartiallyKnownVariables

    func testPartiallyKnownVariables() {
        // Known vars substituted, unknown vars left as-is
        let result = TemplateSubstitutor.substitute(
            in: "Hello {{name}}, today is {{date}}",
            variables: ["name": "Alice"]
        )
        XCTAssertEqual(result, "Hello Alice, today is {{date}}")
    }

    // MARK: - testClipboardTemplateWithSurroundingText

    func testClipboardTemplateWithSurroundingText() {
        let result = TemplateSubstitutor.substitute(
            in: "Review this code:\n\n{{clipboard}}",
            variables: ["clipboard": "let x = 42"]
        )
        XCTAssertEqual(result, "Review this code:\n\nlet x = 42")
    }
}
