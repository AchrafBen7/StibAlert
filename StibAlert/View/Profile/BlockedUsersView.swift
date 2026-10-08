import SwiftUI

/// Utilisateurs bloqués.
///
/// La contrepartie obligatoire du blocage. Apple exige de pouvoir bloquer
/// (App Review Guideline 1.2) ; sans écran pour défaire, le geste devient un
/// piège : on masque quelqu'un par erreur et plus rien ne permet de revenir en
/// arrière. Le relecteur Apple cherche les deux.
struct BlockedUsersView: View {
    let onBack: () -> Void
    let onClose: () -> Void

    @State private var blocked: [BlockedUser] = []
    @State private var isLoading = true
    @State private var busyId: String?
    @State private var errorMessage: String?

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: AppLocalizer.string("profile.privacy", defaultValue: "Confidentialité"),
            title: AppLocalizer.string("block.list_title", defaultValue: "Utilisateurs bloqués"),
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                Text(AppLocalizer.string(
                    "block.list_hint",
                    defaultValue: "Leurs signalements n'apparaissent plus pour toi."
                ))
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.inkMute)

                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.statusCritical)
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Spacing.xl)
                } else if blocked.isEmpty {
                    Text(AppLocalizer.string(
                        "block.list_empty",
                        defaultValue: "Tu n'as bloqué personne."
                    ))
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .padding(.vertical, DS.Spacing.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(blocked.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(DS.Color.ink.opacity(0.08))
                            }
                            row(for: entry)
                        }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func row(for entry: BlockedUser) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "nosign")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)

            // Un compte supprimé depuis le blocage n'a plus de nom : on le dit,
            // plutôt que d'afficher une ligne vide.
            Text(entry.nom?.isEmpty == false
                 ? entry.nom!
                 : AppLocalizer.string("block.deleted_account", defaultValue: "Compte supprimé"))
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)

            Spacer()

            Button {
                unblock(entry)
            } label: {
                if busyId == entry.userId {
                    ProgressView()
                } else {
                    Text(AppLocalizer.string("block.unblock", defaultValue: "Débloquer"))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.community)
                }
            }
            .buttonStyle(.plain)
            .disabled(busyId != nil)
        }
        // 44 pt : la cible tactile minimale d'Apple.
        .frame(minHeight: 44)
    }

    private func reload() async {
        errorMessage = nil
        do {
            blocked = try await BlockService.list().blocks
        } catch {
            blocked = []
            errorMessage = AppLocalizer.string(
                "block.list_failed",
                defaultValue: "Impossible de charger la liste. Réessaie."
            )
        }
        isLoading = false
    }

    private func unblock(_ entry: BlockedUser) {
        guard busyId == nil else { return }
        busyId = entry.userId
        Task {
            do {
                try await BlockService.unblock(userId: entry.userId)
                await reload()
            } catch {
                errorMessage = AppLocalizer.string(
                    "block.unblock_failed",
                    defaultValue: "Impossible de débloquer. Réessaie."
                )
            }
            busyId = nil
        }
    }
}
