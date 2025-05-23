//
//  DetailLijnPerHalte.swift
//  StibAlert
//
//  Created by studentehb on 12/05/2025.
//
import SwiftUI

struct LigneDetailHalteView: View {
    let line: LijnModel
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var halteVM = AlleHaltesViewModel()
    @State private var isAscending = true
    @State private var searchText = ""
    @State private var directionTitle: String = ""

    var body: some View {
        VStack(spacing: 8) {
            // --- HEADER ---
            headerView

            // --- BARRE DE DIRECTION ---
            directionBar

            // --- CHAMP DE RECHERCHE ---
            searchBar

            // --- CONTENU ---
            let haltesSource = isAscending ? halteVM.arretsAller : halteVM.arretsRetour

            if halteVM.isLoading {
                ProgressView("Chargement en cours...")
                    .padding()
            } else if let error = halteVM.errorMessage {
                Text("Erreur : \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else if haltesSource.isEmpty {
                Text("Aucun arrêt trouvé.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        let filtered = haltesSource
                            .filter { searchText.isEmpty || $0.nom.localizedCaseInsensitiveContains(searchText) }
                            .sorted { isAscending ? $0.nom < $1.nom : $0.nom > $1.nom }

                        let uniqueHaltes = Dictionary(grouping: filtered, by: { $0._id }).compactMap { $0.value.first }

                        ForEach(uniqueHaltes) { halte in
                            let count = halte.signalementsRecents?.count ?? 0

                            NavigationLink(destination: MeldingenPerHalteView(halte: halte)) {
                                HStack(spacing: 12) {
                                    Rectangle()
                                        .fill(statusColor(for: halte))
                                        .frame(width: 6)
                                        .cornerRadius(3)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(halte.nom)
                                            .font(.body)
                                            .bold()

                                        Text("\(count) signalement(s)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    if count >= 4 {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal)
                                .background(Color.white)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            directionTitle = extractTerminus(from: line.nomCompletRetour ?? line.nomComplet, isReversed: false)
            halteVM.fetchArrets(lineId: line.lineid, sortAsc: true)
        }
    }

    // --- Sous-vues pour structurer ton code ---

    var headerView: some View {
        HStack(spacing: 12) {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.blue)
                    .font(.system(size: 20, weight: .medium))
            }

            Text(line.lineid)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(LineColors.color(for: line.lineid))
                .cornerRadius(8)

            VStack(alignment: .leading) {
                Text(line.nomComplet.uppercased())
                    .font(.system(size: 16, weight: .bold))
                if let retour = line.nomCompletRetour {
                    Text(retour.uppercased())
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Button {
                print("Notification tapped")
            } label: {
                Image(systemName: "bell.badge")
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    var directionBar: some View {
        HStack {
            Text("Vers \(directionTitle)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button {
                isAscending.toggle()
                directionTitle = isAscending
                    ? extractTerminus(from: line.nomCompletRetour ?? line.nomComplet, isReversed: false)
                    : extractTerminus(from: line.nomComplet, isReversed: true)

                halteVM.fetchArrets(lineId: line.lineid, sortAsc: isAscending)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding()
        .background(Color(hex: "#4557A1"))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Rechercher un arrêt", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    func statusColor(for halte: HalteModel) -> Color {
        let count = halte.signalementsRecents?.count ?? 0
        if count >= 4 { return .red }
        else if count >= 2 { return .yellow }
        else { return .green }
    }

    func extractTerminus(from fullName: String, isReversed: Bool) -> String {
        let parts = fullName.components(separatedBy: " - ")
        return isReversed ? parts.first ?? fullName : parts.last ?? fullName
    }
}
