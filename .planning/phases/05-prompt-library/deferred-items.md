# Deferred Items — Phase 05-prompt-library

## Pre-existing Test Failures

### PasteServiceTests.testPlainTextOnly (PRE-EXISTING)
- **Status:** Pre-existing failure, not caused by Phase 5 changes
- **Test:** FlycutTests/PasteServiceTests.swift → testPlainTextOnly()
- **Issue:** macOS 15 appends additional pasteboard types (possibly `public.utf8-string`) when NSPasteboard.setString is called, causing the test to fail its assertion that only `public.utf8-plain-text` is present
- **Not introduced by:** Phase 5 schema migration, PromptLibraryStore, TemplateSubstitutor
- **Recommended fix:** Update test to allow for macOS-internal pasteboard types, or check only that RTF/HTML are NOT present rather than asserting the complete type list

