/// Native build: there is no browser to hand the file to.
///
/// Returns false so the caller can say so — the previous version
/// silently did nothing while the UI reported "Download started!".
bool downloadFile(List<int> bytes, String fileName) => false;
