import SwiftUI

/// A small SwiftUI view that renders the text from the Figma node
/// "Sélectionnez le type de problème recontré".
///
/// Integration notes:
/// - Add the localization key `select_problem_type` to your Localizable files.
/// - Ensure the Montserrat font (Regular) is added to the project and Info.plist.
/// - Prefer using your project's design system fonts/colors if available.
struct SelectionTypeProblemView: View {
    var body: some View {
        Text(LocalizedStringKey("select_problem_type"))
            .font(DesignSystem.Typography.description)
            .foregroundStyle(DesignSystem.Colors.primaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("selection_problem_type_text")
            .padding(.vertical, 0)
    }
}

struct SelectionTypeProblemView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            SelectionTypeProblemView()
                .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}
