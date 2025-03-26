import SwiftUI

struct MeldingenView: View {
    @ObservedObject var viewModel = MeldingenViewModel()
    
    // Formatter om de datum leesbaar te maken
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            List {
                if let error = viewModel.errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                } else {
                    ForEach(viewModel.meldingen) { melding in
                        VStack(alignment: .leading, spacing: 4) {
                            // Toon de halte naam
                            Text("Halte: \(melding.arretId.nom)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            // Toon lijn en type melding
                            Text("Lijn: \(melding.ligne)")
                                .font(.headline)
                            Text("Type: \(melding.typeProbleme)")
                                .font(.subheadline)
                            
                            // Toon beschrijving van de melding
                            Text("Beschrijving: \(melding.description)")
                                .font(.body)
                            
                            // Toon de datum, geformatteerd
                            Text("Datum: \(MeldingenView.dateFormatter.string(from: melding.dateSignalement))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Toon stemmen
                            HStack {
                                Text("👍 \(melding.votesPositifs)")
                                Text("👎 \(melding.votesNegatifs)")
                            }
                            .font(.caption)
                            
                            // Toon het vertrouwensniveau
                            Text("Vertrouwen: \(melding.confiance)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Alle Meldingen")
            .onAppear {
                viewModel.fetchMeldingen()
            }
        }
    }
}

struct MeldingenView_Previews: PreviewProvider {
    static var previews: some View {
        MeldingenView()
    }
}

