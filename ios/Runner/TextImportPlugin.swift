import CoreFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

// Injectable system operations let tests distinguish balanced scope ownership
// from synthetic local-file reads (which do not prove provider scope behavior).
struct TextDocumentReader {
  // Native ceiling also permits the opt-in direct-reader CI profile.
  static let maxReadBytes = 16 * 1024 * 1024

  var startScope: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
  var stopScope: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
  var coordinate: (URL, (URL) -> Void) throws -> Void = { url, accessor in
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: accessor)
    if let error = error { throw error }
  }
  var fileSize: (URL) throws -> Int = { url in
    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      throw CocoaError(.fileReadUnknown)
    }
    return size
  }
  var load: (URL, Int) throws -> Data = { url, maxBytes in
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var bytes = Data()
    // Also bound reads if the file size changed or was inaccurate.
    while let chunk = try file.read(upToCount: min(64 * 1024, maxBytes - bytes.count + 1)), !chunk.isEmpty {
      guard chunk.count <= maxBytes - bytes.count else { throw CocoaError(.fileReadTooLarge) }
      bytes.append(chunk)
    }
    return bytes
  }

  func read(_ url: URL, maxBytes: Int = TextDocumentReader.maxReadBytes) throws -> [String: Any] {
    guard (1...Self.maxReadBytes).contains(maxBytes) else { throw CocoaError(.fileReadTooLarge) }
    let scoped = startScope(url)
    defer { if scoped { stopScope(url) } }
    // A false start can mean a local URL needs no scope. Try the real read.
    let name = url.lastPathComponent
    guard [".txt", ".md", ".markdown"].contains(where: name.lowercased().hasSuffix) else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }
    var bytes: Data?
    var readError: Error?
    try coordinate(url) { readableURL in
      do {
        guard (0...maxBytes).contains(try fileSize(readableURL)) else { throw CocoaError(.fileReadTooLarge) }
        bytes = try load(readableURL, maxBytes)
      } catch { readError = error }
    }
    if let readError = readError { throw readError }
    guard let bytes = bytes else { throw CocoaError(.fileReadUnknown) }
    guard bytes.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
    return ["name": name, "bytes": FlutterStandardTypedData(bytes: bytes)]
  }
}

final class TextImportPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private final class Request {
    let maxBytes: Int
    var result: FlutterResult?
    var reading = false
    init(_ result: @escaping FlutterResult, maxBytes: Int) {
      self.result = result
      self.maxBytes = maxBytes
    }
  }
  private var attached = true
  private var pending: Request?
  private(set) var picker: UIDocumentPickerViewController?
  private weak var activePresentationController: UIPresentationController?
  var reader = TextDocumentReader()
  // The default uses UIKit. Native unit tests inject a non-presenting boundary so
  // they can exercise request/delegate lifecycle without launching Files UI.
  // Pass the controller created by UIKit back through the same delegate path.
  var presentPicker: (UIViewController, UIDocumentPickerViewController,
                      @escaping (UIPresentationController?) -> Void) -> Void = {
    presenter, picker, completion in
    presenter.present(picker, animated: true) { completion(picker.presentationController) }
  }
  var pickerIsPresented: (UIDocumentPickerViewController) -> Bool = { $0.presentingViewController != nil }
  var dismissPicker: (UIDocumentPickerViewController) -> Void = { $0.dismiss(animated: false) }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = TextImportPlugin()
    let channel = FlutterMethodChannel(name: "org.kotoha/text_import", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  static func activePresenter() -> UIViewController? {
    // Kotoha is single-scene. Never guess between several active windows.
    let windows = UIApplication.shared.connectedScenes
      .filter { $0.activationState == .foregroundActive }
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.filter { $0.isKeyWindow }
    guard windows.count == 1, var presenter = windows.first?.rootViewController else { return nil }
    while let presented = presenter.presentedViewController { presenter = presented }
    guard !presenter.isBeingDismissed, !presenter.isBeingPresented,
      presenter.transitionCoordinator == nil, presenter.viewIfLoaded?.window != nil else { return nil }
    return presenter
  }

  static func makePicker(presenter: UIViewController) -> UIDocumentPickerViewController {
    // Filters are advisory. Accept data so a provider's unknown Markdown UTI is
    // not excluded; validate the selected extension before loading bytes.
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.modalPresentationStyle = .formSheet
    if let popover = picker.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = presenter.view.bounds
    }
    return picker
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "open" else { result(FlutterMethodNotImplemented); return }
    guard let number = (call.arguments as? [String: Any])?["maxBytes"] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      !["f", "d"].contains(String(cString: number.objCType)),
      let maxBytes = number as? Int, (1...TextDocumentReader.maxReadBytes).contains(maxBytes) else {
      result(Self.failure("invalid_limit")); return
    }
    guard attached else { result(Self.failure("detached")); return }
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "Import already active.", details: nil)); return
    }
    guard let presenter = Self.activePresenter() else {
      result(FlutterError(code: "unavailable", message: "No active scene.", details: nil)); return
    }
    let request = Request(result, maxBytes: maxBytes)
    pending = request
    let picker = Self.makePicker(presenter: presenter)
    self.picker = picker
    picker.delegate = self
    presentPicker(presenter, picker) { [weak self, weak picker] presentationController in
      // Detach or a failed presentation must not leave a pending channel call.
      guard let picker = picker else { return }
      guard let self = self else { picker.dismiss(animated: false); return }
      guard self.pending === request else {
        self.dismissPicker(picker)
        return
      }
      guard self.pickerIsPresented(picker) else {
        self.finish(request, value: Self.failure("presentation_failed"))
        return
      }
      // UIKit creates this controller during presentation; install dismissal
      // handling only after that creation is complete. Retain it weakly so the
      // same delegate assignment is cleared when this request finishes.
      self.activePresentationController = presentationController
      presentationController?.delegate = self
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === picker,
      let request = pending, !request.reading else { return }
    finish(request, value: nil)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === picker, let request = pending, !request.reading else { return }
    finish(request, value: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === picker, let request = pending, !request.reading else { return }
    guard urls.count == 1, let url = urls.first, url.isFileURL else {
      finish(request, value: Self.failure("invalid_selection")); return
    }
    request.reading = true
    let reader = self.reader
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let value: Any
      do { value = try reader.read(url, maxBytes: request.maxBytes) } catch { value = Self.failure("read_failed") }
      DispatchQueue.main.async { [weak self] in self?.finish(request, value: value) }
    }
  }

  private static func failure(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "Could not import this document.", details: nil)
  }

  private func finish(_ request: Request, value: Any?) {
    guard pending === request else { return }
    pending = nil
    picker?.delegate = nil
    activePresentationController?.delegate = nil
    activePresentationController = nil
    picker = nil
    let result = request.result
    request.result = nil
    result?(value)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    attached = false
    let presented = picker
    if let request = pending { finish(request, value: Self.failure("detached")) }
    presented?.delegate = nil
    if let presented = presented { dismissPicker(presented) }
  }
}
