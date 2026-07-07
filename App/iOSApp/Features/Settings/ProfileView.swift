import SwiftUI
import UIKit
import PhotosUI

/// The user's profile photo, stored as a JPEG in Application Support — never uploaded.
/// All disk I/O and image work runs off the main actor; only the published `image` hops back.
@MainActor
@Observable
final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()
    private(set) var image: UIImage?

    nonisolated private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile-photo.jpg")
    }()

    private init() {
        // @MainActor is explicit — with an explicit capture list, some toolchains don't
        // inherit the enclosing actor context, which reads `image` off the main actor.
        Task { @MainActor [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                (try? Data(contentsOf: Self.fileURL)).flatMap(UIImage.init(data:))
            }.value
            // Don't clobber a photo the user picked while the disk load was in flight.
            if let loaded, let self, self.image == nil { self.image = loaded }
        }
    }

    /// Decodes, square-crops to 512px, and saves — all off the main actor.
    /// Returns false when the data isn't a decodable image.
    func set(imageData: Data) async -> Bool {
        let processed = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let raw = UIImage(data: imageData) else { return nil }
            let squared = Self.squareCropDownscale(raw, side: 512)
            if let jpeg = squared.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: Self.fileURL, options: .atomic)
            }
            return squared
        }.value
        guard let processed else { return false }
        image = processed
        return true
    }

    func clear() {
        image = nil
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: Self.fileURL)
        }
    }

    nonisolated private static func squareCropDownscale(_ image: UIImage, side: CGFloat) -> UIImage {
        let source = min(image.size.width, image.size.height)
        guard source > 0 else { return image }
        let target = min(side, source)   // center-crop to square; never upscale
        let scale = target / source
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }
}

/// Circular avatar with the brand gradient ring. Shows the profile photo when set; otherwise
/// an initials monogram on a deep-blue gradient (or a person glyph when there's no name yet).
struct ProfileAvatar: View {
    var name: String
    var size: CGFloat = 96
    var photo: UIImage?

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(parts).uppercased()
    }

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [BrandColor.accent, BrandColor.deepBlue],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(
                AngularGradient(colors: [BrandColor.accentText, BrandColor.accent, BrandColor.accentText],
                                center: .center),
                lineWidth: max(2, size / 34)
            )
        )
        .shadow(color: BrandColor.accent.opacity(0.35), radius: size / 8, y: size / 16)
        .accessibilityHidden(true)
    }
}

/// My Profile — the account home. A hero header (photo, name, membership badge) over cards
/// for account details, personalization, and the on-device privacy promise.
struct ProfileView: View {
    @AppStorage("bodyGender") private var bodyGenderRaw = "male"
    @State private var auth = AuthManager.shared
    @State private var photos = ProfilePhotoStore.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var photoError: String?
    /// Draft of the name while editing; committed to AuthManager on submit/close.
    @State private var name = AuthManager.shared.displayName ?? ""

    var body: some View {
        MenuSheet(title: "My Profile") {
            header
            accountCard
            personalizationCard
            privacyCard
        }
        .onDisappear { auth.updateDisplayName(name) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            photoLoadTask?.cancel()
            photoLoadTask = Task {
                let data = try? await item.loadTransferable(type: Data.self)
                guard !Task.isCancelled else { return }
                let ok: Bool
                if let data { ok = await photos.set(imageData: data) } else { ok = false }
                guard !Task.isCancelled else { return }
                photoError = ok ? nil : "Couldn't load that photo — try another."
                pickerItem = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.md) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(name: name, size: 108, photo: photos.image)
                    Image(systemName: photos.image == nil ? "plus" : "pencil")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BrandColor.onAccent)
                        .frame(width: 30, height: 30)
                        .background(BrandColor.accent, in: Circle())
                        .overlay(Circle().strokeBorder(BrandColor.background, lineWidth: 2))
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(photos.image == nil ? "Add profile photo" : "Change profile photo")

            VStack(spacing: Space.sm) {
                Text(name.isEmpty ? "Set up your profile" : name)
                    .font(Typo.title)
                    .foregroundStyle(BrandColor.textPrimary)
                    .multilineTextAlignment(.center)
                TagChip(text: auth.isGuest ? "Guest" : "PinWise Member",
                        color: BrandColor.accentText,
                        systemImage: auth.isGuest ? "person.crop.circle.dashed" : "checkmark.seal.fill")
            }

            if let photoError {
                Text(photoError)
                    .font(.caption)
                    .foregroundStyle(BrandColor.warning)
            }
            if photos.image != nil {
                Button("Remove photo") { photos.clear() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.sm)
    }

    // MARK: Cards

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Account")
                FieldRow("Your name", hint: "Shown on your profile and used to personalize the app.") {
                    TextField("Name", text: $name)
                        .pinwiseField()
                        .textContentType(.name)
                        .onSubmit { auth.updateDisplayName(name) }
                }
                if let email = auth.email, !email.isEmpty {
                    detailRow("Email", email)
                }
                detailRow("Sign-in", auth.providerLabel, icon: auth.provider == .apple ? "applelogo" : nil)
                if let since = auth.memberSince {
                    detailRow(auth.isGuest ? "Tracking since" : "Member since",
                              since.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    private var personalizationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Personalization")
                FieldRow("Injection map body", hint: "Which body the injection map draws.") {
                    Picker("", selection: $bodyGenderRaw) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(BrandColor.success)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Private by design")
                        .font(Typo.headline)
                        .foregroundStyle(BrandColor.textPrimary)
                    Text("Your profile, photo, and dose history live on this device. Nothing is uploaded or shared.")
                        .font(.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, icon: String? = nil) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            Spacer()
            HStack(spacing: Space.xs) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(value).font(.caption.weight(.medium))
            }
            .foregroundStyle(BrandColor.textSecondary)
        }
    }
}
