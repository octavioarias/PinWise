import SwiftUI
import UIKit
import PhotosUI

/// The user's profile photo, stored as a JPEG in Application Support — never uploaded.
/// Square-cropped and downscaled once on save so the file stays small and loads instantly.
@MainActor
@Observable
final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()
    private(set) var image: UIImage?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile-photo.jpg")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL) { image = UIImage(data: data) }
    }

    func set(_ raw: UIImage) {
        let squared = Self.squareCropDownscale(raw, side: 512)
        image = squared
        if let data = squared.jpegData(compressionQuality: 0.85) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private static func squareCropDownscale(_ image: UIImage, side: CGFloat) -> UIImage {
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileName") private var name = ""
    @AppStorage("bodyGender") private var bodyGenderRaw = "male"
    @State private var auth = AuthManager.shared
    @State private var photos = ProfilePhotoStore.shared
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.lg) {
                    header
                    accountCard
                    personalizationCard
                    privacyCard
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            // Prefill from the Apple ID name captured at sign-in, so the profile never starts blank.
            if name.isEmpty, let appleName = auth.displayName { name = appleName }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    photos.set(ui)
                }
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
                membershipBadge
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

    private var membershipBadge: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: auth.isGuest ? "person.crop.circle.dashed" : "checkmark.seal.fill")
                .font(.caption2.weight(.bold))
            Text(auth.isGuest ? "GUEST" : "PINWISE MEMBER")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs + 1)
        .background(BrandColor.accentText.opacity(0.16), in: Capsule())
        .foregroundStyle(BrandColor.accentText)
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
                        .onChange(of: name) { _, new in auth.updateDisplayName(new) }
                }
                if let email = auth.email, !email.isEmpty {
                    detailRow("Email", email)
                }
                detailRow("Sign-in", signInLabel, icon: auth.provider == .apple ? "applelogo" : nil)
                if let since = auth.memberSince {
                    detailRow(auth.isGuest ? "Tracking since" : "Member since",
                              since.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    private var signInLabel: String {
        switch auth.provider {
        case .apple: return "Apple ID"
        case .google: return "Google"
        case .email: return "Email"
        case .guest, .none: return "Guest — not signed in"
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
