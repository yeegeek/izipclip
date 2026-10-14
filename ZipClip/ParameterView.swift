import Photos
import SwiftUI

private enum AppRoute: Hashable {
    case library
    case processing(ids: [String])
}

struct ParameterView: View {
    @State private var settings = CompressSettings.load()
    @State private var path = NavigationPath()
    @State private var isLoadingLibrary = false
    @State private var libraryVideos: [LibraryVideo] = []
    @State private var videoByID: [String: LibraryVideo] = [:]
    @State private var libraryError: String?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(L10n.appName)
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    Toggle(isOn: $settings.deleteOriginal) {
                        Text(L10n.deleteOriginal)
                            .font(.subheadline)
                            .foregroundStyle(settings.deleteOriginal ? Color.primary : Color.secondary)
                    }
                    .tint(Color.zip)
                    .fixedSize()
                }
                .padding(.top, 28)

                HStack(alignment: .top, spacing: 28) {
                    limitControl(
                        value: settings.durationSeconds,
                        caption: L10n.duration,
                        unit: L10n.unitSeconds,
                        range: CompressSettings.durationRange,
                        step: CompressSettings.durationStep
                    ) { settings.durationSeconds = $0 }

                    limitControl(
                        value: settings.sizeMB,
                        caption: L10n.size,
                        unit: L10n.unitMB,
                        range: CompressSettings.sizeRange,
                        step: CompressSettings.sizeStep
                    ) { settings.sizeMB = $0 }
                }
                .padding(.top, 48)

                Spacer()

                if let libraryError {
                    Text(libraryError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }

                Button {
                    Task { await openLibrary() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoadingLibrary {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(isLoadingLibrary ? L10n.scanning : L10n.selectVideos)
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(Color.zip, in: Capsule())
                    .opacity(isLoadingLibrary ? 0.85 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingLibrary)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .library:
                    LibraryView(
                        videos: libraryVideos,
                        onStart: { selected in
                            guard !selected.isEmpty else { return }
                            for video in selected {
                                videoByID[video.id] = video
                            }
                            path.append(AppRoute.processing(ids: selected.map(\.id)))
                        }
                    )
                case .processing(let ids):
                    ProcessingView(
                        videos: ids.compactMap { videoByID[$0] },
                        settings: settings,
                        onFinishedReturnHome: {
                            path = NavigationPath()
                            libraryVideos = []
                            videoByID = [:]
                        }
                    )
                }
            }
            .onChange(of: settings) { _, newValue in
                newValue.persist()
            }
        }
    }

    @MainActor
    private func openLibrary() async {
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        libraryError = nil
        defer { isLoadingLibrary = false }

        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            libraryError = status == .denied || status == .restricted
                ? L10n.openPhotosSettings
                : L10n.needPhotos
            return
        }

        let found = await PhotoLibraryService.videosExceeding(settings: settings)
        guard !found.isEmpty else {
            libraryError = L10n.noneExceeding
            libraryVideos = []
            videoByID = [:]
            return
        }
        libraryVideos = found
        videoByID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        path.append(AppRoute.library)
    }

    private func limitControl(
        value: Double,
        caption: String,
        unit: String,
        range: ClosedRange<Double>,
        step: Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(value))")
                .font(.system(size: 56, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Slider(value: Binding(get: { value }, set: set), in: range, step: step)
                .tint(Color.zip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: value)
    }
}
