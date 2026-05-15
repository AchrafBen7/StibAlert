import SwiftUI

struct MapLegendOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                legendHeader(left: "RÉSEAU", right: "AUCUN")

                VStack(spacing: 0) {
                    legendSimpleRow(letter: "M", fill: Color(hex: "#F05A22"), title: "Métro")
                    legendSimpleRow(letter: "T", fill: Color(hex: "#FFC20E"), title: "Tram", textColor: .black)
                    legendSimpleRow(letter: "B", fill: Color(hex: "#243F73"), title: "Bus")
                    legendSimpleRow(letter: "N", fill: Color(hex: "#6F3BA8"), title: "Noctis")
                }

                legendSubheader("AUTRES")

                VStack(spacing: 0) {
                    legendSimpleRow(letter: "V", fill: Color(hex: "#2E8B57"), title: "Villo!")
                    legendSimpleRow(letter: "E", fill: Color(hex: "#8E2AD1"), title: "Évènements")
                }
            }
            .frame(width: 248, alignment: .leading)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
            .padding(.top, 122)
            .padding(.trailing, 18)
        }
    }

    private func legendHeader(left: String, right: String) -> some View {
        HStack {
            Text(left)
            Spacer()
            Text(right)
        }
        .font(DS.Font.mono.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.paper)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(DS.Color.ink)
    }

    private func legendSubheader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .font(DS.Font.mono.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.inkMute)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(DS.Color.paper2.opacity(0.65))
    }

    private func legendSimpleRow(letter: String, fill: Color, title: String, textColor: Color = .white) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
                Text(letter)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(textColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.Color.ink)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.Color.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.ink.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 66)
        }
    }
}
