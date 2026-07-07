import SwiftUI
import PhotosUI

/// One-time profile personalization — shown after terms acceptance and before the intro
/// tour. Everything here is optional: skipping keeps the defaults (male body map, the
/// region-seeded weight unit) and the profile stays editable later under My Profile.
struct ProfileSetupView: View {
    @AppStorage("completedProfileSetup") private var completedProfileSetup = false
    @AppStorage("bodyGender") private var bodyGenderRaw = "male"
    @AppStorage("weightInPounds") private var weightInPounds = true
    @AppStorage("profileBirthday") private var birthdayTS: Double = 0
    @AppStorage("profileHeightCm") private var heightCm: Double = 0
    @State private var auth = AuthManager.shared
    @State private var photos = ProfilePhotoStore.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var name = AuthManager.shared.displayName ?? ""
    @State private var birthday = ProfileFields.defaultBirthday
    @State private var birthdayTouched = false
    @State private var heightText = ""
    @State private var doneTrigger = 0

    var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()
            HeroMesh()
                .frame(height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Make it yours")
                        .font(Typo.title).textCase(.uppercase)
                        .foregroundStyle(BrandColor.textPrimary)
                        .padding(.top, Space.xxl)
                    Text("A minute of setup, all optional — everything can be changed later in My Profile.")
                        .font(Typo.body)
                        .foregroundStyle(BrandColor.textSecondary)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatar(name: name, size: 96, photo: photos.image)
                            Image(systemName: photos.image == nil ? "plus" : "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(BrandColor.onAccent)
                                .frame(width: 28, height: 28)
                                .background(BrandColor.accent, in: Circle())
                                .overlay(Circle().strokeBorder(BrandColor.background, lineWidth: 2))
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(photos.image == nil ? "Add profile photo" : "Change profile photo")

                    FieldRow("Your name", hint: "Shown on your profile and used to personalize the app.") {
                        TextField("Name", text: $name)
                            .pinwiseField()
                            .textContentType(.name)
                    }

                    FieldRow("Birthday") {
                        DatePicker("", selection: $birthday, in: ProfileFields.birthdayRange,
                                   displayedComponents: [.date])
                            .labelsHidden()
                            .onChange(of: birthday) { _, _ in birthdayTouched = true }
                    }

                    FieldRow("Sex", hint: "Helps tailor the app to you.") {
                        Picker("", selection: $bodyGenderRaw) {
                            Text("Male").tag("male")
                            Text("Female").tag("female")
                        }
                        .pickerStyle(.segmented)
                    }

                    FieldRow("Height") {
                        HStack {
                            TextField(weightInPounds ? "e.g. 70" : "e.g. 178", text: $heightText)
                                .keyboardType(.decimalPad).pinwiseField()
                            Text(weightInPounds ? "in" : "cm").foregroundStyle(BrandColor.textSecondary)
                        }
                    }

                    FieldRow("Body weight unit") {
                        Picker("", selection: $weightInPounds) {
                            Text("Pounds (lb)").tag(true)
                            Text("Kilograms (kg)").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    PrimaryButton(title: "Continue", systemImage: "arrow.right") { finish() }
                        .padding(.top, Space.sm)
                    Button { finish() } label: {
                        Text("Skip for now")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.xl)
            }
        }
        .tint(BrandColor.accent)
        .sensoryFeedback(.success, trigger: doneTrigger)
        // Keep the typed height meaning the same measurement when the unit toggle flips.
        .onChange(of: weightInPounds) { old, new in
            guard old != new, let v = heightText.decimalValue, v > 0 else { return }
            let cm = ProfileFields.heightCm(fromDisplay: v, imperial: old)
            let disp = ProfileFields.heightDisplay(fromCm: cm, imperial: new)
            heightText = disp == disp.rounded() ? String(Int(disp)) : String(format: "%.1f", disp)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            photoLoadTask?.cancel()
            photoLoadTask = Task {
                if let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled {
                    _ = await photos.set(imageData: data)
                }
                pickerItem = nil
            }
        }
    }

    private func finish() {
        auth.updateDisplayName(name)   // ignores empty input
        if birthdayTouched { birthdayTS = birthday.timeIntervalSince1970 }
        if let h = heightText.decimalValue, h > 0 {
            heightCm = ProfileFields.heightCm(fromDisplay: h, imperial: weightInPounds)
        }
        doneTrigger += 1
        withAnimation(.easeInOut(duration: 0.55)) { completedProfileSetup = true }
    }
}
