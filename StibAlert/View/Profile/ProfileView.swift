import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var nav: AppNavigation
    @State private var selectedSubpage: SettingsSubpage?
    @State private var selectedLanguageCode = "FR"
    @State private var pushNotificationsEnabled = true
    @State private var emailNotificationsEnabled = false
    @State private var smsNotificationsEnabled = false
    @State private var dataSharingEnabled = true
    @State private var locationTrackingEnabled = false
    @State private var adsPersonalizationEnabled = false
    @State private var firstName = "Achraf"
    @State private var lastName = "Benali"
    @State private var email = "Achrafb768@gmail.com"
    @State private var username = "user-48155848"

    private let items = SettingsMockData.items

    var body: some View {
        ZStack {
            Color(hex: "#1B1B1B").ignoresSafeArea()

            if selectedSubpage == .languages {
                LanguageSettingsView(
                    selectedLanguage: $selectedLanguageCode,
                    onBack: { selectedSubpage = nil },
                    onClose: {
                        selectedSubpage = nil
                        nav.currentPage = .home
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if selectedSubpage == .account {
                AccountSettingsView(
                    firstName: $firstName,
                    lastName: $lastName,
                    email: $email,
                    username: $username,
                    onBack: { selectedSubpage = nil },
                    onClose: {
                        selectedSubpage = nil
                        nav.currentPage = .home
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if selectedSubpage == .privacy {
                PrivacySettingsView(
                    dataSharingEnabled: $dataSharingEnabled,
                    locationTrackingEnabled: $locationTrackingEnabled,
                    adsPersonalizationEnabled: $adsPersonalizationEnabled,
                    onBack: { selectedSubpage = nil },
                    onClose: {
                        selectedSubpage = nil
                        nav.currentPage = .home
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if selectedSubpage == .support {
                SupportSettingsView(
                    onBack: { selectedSubpage = nil },
                    onClose: {
                        selectedSubpage = nil
                        nav.currentPage = .home
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if selectedSubpage == .notifications {
                NotificationSettingsView(
                    pushEnabled: $pushNotificationsEnabled,
                    emailEnabled: $emailNotificationsEnabled,
                    smsEnabled: $smsNotificationsEnabled,
                    onBack: { selectedSubpage = nil },
                    onClose: {
                        selectedSubpage = nil
                        nav.currentPage = .home
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 21)
                        .padding(.top, 12)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 15),
                            GridItem(.flexible(), spacing: 15)
                        ],
                        spacing: 17
                    ) {
                        ForEach(items) { item in
                            SettingsTile(item: item) {
                                selectedSubpage = item.subpage
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 43)

                    feedbackButton
                        .padding(.horizontal, 23)
                        .padding(.top, 33)

                    Text("Vos retours nous aident à améliorer l’app")
                        .font(.custom("Montserrat-Regular", size: 11))
                        .foregroundStyle(Color.white.opacity(0.18))
                        .padding(.top, 6)

                    Spacer()

                    Text("Version 1.0.0")
                        .font(.custom("Montserrat-Regular", size: 14))
                        .foregroundStyle(.white)
                        .padding(.bottom, 44)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        nav.showSideMenu = true
                    }
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 40)
                        .overlay(
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.8))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        nav.currentPage = .home
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Text("Parametres")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var feedbackButton: some View {
        Button {} label: {
            HStack(spacing: 8) {
                Text("Votre avis compte")
                    .font(.custom("Montserrat-Regular", size: 12))

                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsTile: View {
    let item: SettingsTileItem
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.custom("DelaGothicOne-Regular", size: 20))
                        .foregroundStyle(.black)

                    Spacer()

                    Circle()
                        .fill(Color(hex: "#7CB2FF"))
                        .frame(width: 12, height: 12)
                }

                Text(item.description)
                    .font(.custom("Montserrat-Regular", size: 11))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            .background(isPressed || item.isInitiallyHighlighted ? Color(hex: "#BBDCFF") : .white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color(hex: "#81B7FF"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.12)) { isPressed = true }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.12)) { isPressed = false }
        }
    }
}

private struct SettingsTileItem: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let isInitiallyHighlighted: Bool
    let subpage: SettingsSubpage?
}

private enum SettingsSubpage {
    case account
    case languages
    case notifications
    case privacy
    case support
}

private enum SettingsMockData {
    static let items: [SettingsTileItem] = [
        .init(title: "Compte", description: "Gérer vos informations\npersonnelles et préférences.", isInitiallyHighlighted: true, subpage: .account),
        .init(title: "Notifications", description: "Choisir quand et comment\nrecevoir des alertes.", isInitiallyHighlighted: false, subpage: .notifications),
        .init(title: "Langues", description: "Sélectionner votre langue\npréférée dans l’app.", isInitiallyHighlighted: false, subpage: .languages),
        .init(title: "A propos", description: "Découvrir la mission et\nl’équipe derrière l’application", isInitiallyHighlighted: false, subpage: nil),
        .init(title: "Privé", description: "Contrôler vos données et\nparamètres de confidentialité.", isInitiallyHighlighted: false, subpage: .privacy),
        .init(title: "Support", description: "Obtenir de l’aide ou signaler\nun problème.", isInitiallyHighlighted: false, subpage: .support)
    ]
}

private struct LanguageSettingsView: View {
    @Binding var selectedLanguage: String
    let onBack: () -> Void
    let onClose: () -> Void

    @State private var query = ""

    private var languages: [LanguageItem] {
        let all = LanguageMockData.items
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
            || $0.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            searchBar
                .padding(.horizontal, 17)
                .padding(.top, 30)

            Text("Choisissez la langue souhaitée :")
                .font(.custom("DelaGothicOne-Regular", size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .padding(.top, 32)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 11) {
                    ForEach(languages) { language in
                        Button {
                            selectedLanguage = language.code
                        } label: {
                            LanguageRow(language: language, isSelected: selectedLanguage == language.code)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }

            Button {} label: {
                Text("Continuer")
                    .font(.custom("DelaGothicOne-Regular", size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 63)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Langues")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            TextField("", text: $query)
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .frame(height: 49)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
        )
    }
}

private struct LanguageRow: View {
    let language: LanguageItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(language.code)
                .font(.custom("Montserrat-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.78))
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.title)
                    .font(.custom("Montserrat-Regular", size: 16))
                    .foregroundStyle(.black)

                Text(language.subtitle)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(Color(hex: "#A9AEB4"))
            }

            Spacer()
        }
        .padding(.horizontal, 21)
        .frame(height: 63)
        .background(isSelected ? Color(hex: "#BBDCFF") : .white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color(hex: "#4F8FFF") : Color(hex: "#E6E6E6"), lineWidth: 1)
        )
    }
}

private struct LanguageItem: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let subtitle: String
}

private enum LanguageMockData {
    static let items: [LanguageItem] = [
        .init(code: "FR", title: "Francais", subtitle: "Francais"),
        .init(code: "BE", title: "Nederlands", subtitle: "Néerlandais"),
        .init(code: "GB", title: "English", subtitle: "Anglais"),
        .init(code: "MA", title: "العربية", subtitle: "Arabe"),
        .init(code: "ES", title: "Español", subtitle: "Espagnol"),
        .init(code: "PT", title: "Português", subtitle: "Portugais"),
        .init(code: "ES", title: "Español", subtitle: "Espagnol")
    ]
}

private struct NotificationSettingsView: View {
    @Binding var pushEnabled: Bool
    @Binding var emailEnabled: Bool
    @Binding var smsEnabled: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Types de notifications")
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(.black)

                Text("Recevez des alertes sur vos arrêts favoris et restez informé des dernières actualités.")
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundStyle(.black)
                    .padding(.top, 22)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 34) {
                    NotificationToggleRow(icon: "bell.fill", title: "Push", isOn: $pushEnabled)
                    NotificationToggleRow(icon: "envelope.fill", title: "Email", isOn: $emailEnabled)
                    NotificationToggleRow(icon: "message.fill", title: "SMS", isOn: $smsEnabled)
                }
                .padding(.top, 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 23)
            .frame(maxWidth: .infinity, minHeight: 359, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .padding(.horizontal, 11)
            .padding(.top, 56)

            Spacer()

            Text("Version 1.0.0")
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .padding(.bottom, 44)
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Notifications")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black)

                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 14))
                    .foregroundStyle(.black)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color(hex: "#BBDCFF"))
        }
    }
}

private struct AccountSettingsView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var email: String
    @Binding var username: String
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            avatarSection
                .padding(.top, 18)

            settingsSectionTitle("Infos personnelles")
                .padding(.top, 23)

            Divider()
                .overlay(Color.white.opacity(0.7))
                .padding(.top, 8)

            VStack(spacing: 13) {
                AccountTextRow(icon: "person", text: $firstName, highlighted: true)
                AccountTextRow(icon: "person", text: $lastName, highlighted: true)
            }
            .padding(.horizontal, 38)
            .padding(.top, 16)

            settingsSectionTitle("Infos de connexion")
                .padding(.top, 29)

            Divider()
                .overlay(Color.white.opacity(0.7))
                .padding(.top, 8)

            VStack(spacing: 13) {
                AccountTextRow(icon: "person", text: $email, highlighted: false)
                AccountTextRow(icon: "person", text: $username, highlighted: false, fontSize: 14)
                PasswordRow()
            }
            .padding(.horizontal, 39)
            .padding(.top, 16)

            Button {} label: {
                Text("Enregistrer")
                    .font(.custom("DelaGothicOne-Regular", size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 63)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 23)
            .padding(.top, 25)

            Spacer()

            Text("Version 1.0.0")
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .padding(.bottom, 44)
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Compte")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#F1D6BE"), Color(hex: "#F7A36B")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .overlay(
                    Text("A")
                        .font(.custom("DelaGothicOne-Regular", size: 28))
                        .foregroundStyle(Color(hex: "#5B2F1C"))
                )

            Circle()
                .fill(Color.black.opacity(0.95))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("DelaGothicOne-Regular", size: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17)
    }
}

private struct AccountTextRow: View {
    let icon: String
    @Binding var text: String
    let highlighted: Bool
    var fontSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.black)
                .frame(width: 24)

            TextField("", text: $text)
                .font(.custom("Montserrat-Regular", size: fontSize))
                .foregroundStyle(.black)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 17)
        .frame(height: 51)
        .background(highlighted ? Color(hex: "#BBDCFF") : .white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(highlighted ? Color(hex: "#3E7BFE") : Color.black, lineWidth: 1)
        )
    }
}

private struct PasswordRow: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "key")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.black)
                .frame(width: 24)

            Text("Mots de passe")
                .font(.custom("Montserrat-Regular", size: 16))
                .foregroundStyle(.black)

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 17)
        .frame(height: 51)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.black, lineWidth: 1)
        )
    }
}

private struct PrivacySettingsView: View {
    @Binding var dataSharingEnabled: Bool
    @Binding var locationTrackingEnabled: Bool
    @Binding var adsPersonalizationEnabled: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 12)

                Text("Paramètres de confidentialité")
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.top, 45)

                VStack(spacing: 0) {
                    PrivacyToggleRow(
                        title: "Partage de données",
                        description: "Aide à améliorer l’app en envoyant des données d’usage anonymes.",
                        isOn: $dataSharingEnabled,
                        activeTint: .black
                    )

                    PrivacyToggleRow(
                        title: "Suivi de localisation",
                        description: "Permet d’identifier les arrêts proches pour signaler plus vite.",
                        isOn: $locationTrackingEnabled,
                        activeTint: .black
                    )

                    PrivacyToggleRow(
                        title: "Personnalisation des annonces",
                        description: "Utilise vos données pour adapter les publicités.",
                        isOn: $adsPersonalizationEnabled,
                        activeTint: .black
                    )
                }
                .padding(.horizontal, 13)
                .padding(.top, 13)

                Text("Gestion du compte")
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.top, 34)

                VStack(spacing: 0) {
                    PrivacyActionRow(
                        title: "Applications tierces",
                        description: "Certaines fonctionnalités peuvent s’appuyer sur des services externes.",
                        actionLabel: "Apps"
                    )
                    PrivacyActionRow(
                        title: "Télécharger vos données",
                        description: "Obtenez une copie de vos données personnelles enregistrées dans STIB Alert.",
                        actionLabel: "Telecharger"
                    )
                    PrivacyActionRow(
                        title: "Supprimer votre compte",
                        description: "Effacez définitivement votre compte et toutes les données associées.",
                        actionLabel: "Supprimer"
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Confidentialité")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let activeTint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 12))
                    .foregroundStyle(.black)

                Text(description)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(activeTint)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

private struct PrivacyActionRow: View {
    let title: String
    let description: String
    let actionLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 12))
                    .foregroundStyle(.black)

                Text(description)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)

                Button("En savoir plus") {}
                    .buttonStyle(.plain)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(Color(hex: "#3E7BFE"))
                    .padding(.top, 2)
            }

            Spacer(minLength: 12)

            Button(actionLabel) {}
                .buttonStyle(.plain)
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 13)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

private struct SupportSettingsView: View {
    private let items = SupportMockData.items
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            VStack(spacing: 22) {
                ForEach(items) { item in
                    SupportRow(item: item)
                }
            }
            .padding(.horizontal, 37)
            .padding(.top, 70)

            Spacer()

            Text("Version 1.0.0")
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .padding(.bottom, 44)
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Support")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }
}

private struct SupportRow: View {
    let item: SupportItem

    var body: some View {
        Button {} label: {
            HStack(spacing: 15) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.custom("Montserrat-SemiBold", size: 16))
                        .foregroundStyle(.black)

                    Text(item.subtitle)
                        .font(.custom("Montserrat-Regular", size: 14))
                        .foregroundStyle(Color(hex: "#C0C5CC"))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .padding(.horizontal, 15)
            .frame(height: 68)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(item.highlighted ? Color(hex: "#8A3A3A") : Color.black, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SupportItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let highlighted: Bool
}

private enum SupportMockData {
    static let items: [SupportItem] = [
        .init(title: "Centre d’aide", subtitle: "Trouvez rapidement une\nsolution ici.", highlighted: false),
        .init(title: "Signaler un bug", subtitle: "Un souci technique ?\nOn est là pour vous écouter.", highlighted: false),
        .init(title: "Communauté", subtitle: "Faites partie du changement.", highlighted: false),
        .init(title: "Nous contacter", subtitle: "Trouvez rapidement une\nsolution ici.", highlighted: true)
    ]
}

private struct PressEventsModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}
