/// Non-web fallback. Viewing attachments inline is only wired for web in this
/// build; on other platforms callers should handle the thrown error.
void openFileInBrowser(List<int> bytes, String mimeType, String filename) {
  throw UnsupportedError(
      'Viewing attachments is only supported on the web build.');
}
