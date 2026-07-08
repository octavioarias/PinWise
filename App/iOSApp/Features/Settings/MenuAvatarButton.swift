import SwiftUI

/// The app-wide identity anchor — every masthead's top-left corner. Shows the user's avatar
/// once they have an identity (photo or name), otherwise a hamburger; either way it always
/// opens the side menu, matching the drawer's leading-edge slide.
struct MenuAvatarButton: View {
    @Binding var showMenu: Bool
    @State private var auth = AuthManager.shared
    @State private var photos = ProfilePhotoStore.shared

    var body: some View {
        Button { showMenu = true } label: {
            if photos.image != nil || !(auth.displayName ?? "").isEmpty {
                ProfileAvatar(name: auth.displayName ?? "", size: 36, photo: photos.image)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BrandColor.textPrimary)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu — profile, settings, and health connections")
    }
}
