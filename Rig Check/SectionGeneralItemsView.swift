//
//  SectionGeneralItemsView.swift
//  Rig Check
//
//  Created by ChatGPT on 9/2/25.
//

import SwiftUI

/// Interior Compartments – General Items
/// - Pedi-Mate (Present/Missing)
/// - K.E.D. (Present/Missing)
/// - Broom (Present/Missing)
/// - On-Board Suction Functional (Yes/No)
struct SectionGeneralItemsView: View {

    // Bindings provided by InteriorCompartmentsCheckView
    @Binding var pediMate: Bool?
    @Binding var ked: Bool?
    @Binding var broom: Bool?
    @Binding var suctionFunctional: Bool? // yes/no

    private let brandYellow = Brand.yellow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General Items")
                .font(.headline)
                .foregroundColor(.yellow)

            presentRow("Pedi-Mate", selection: $pediMate)
            presentRow("K.E.D.", selection: $ked)
            presentRow("Broom", selection: $broom)

            yesNoRow("On-Board Suction Functional", selection: $suctionFunctional)
        }
        .padding(.horizontal)
    }

    // MARK: - Row helpers (use your CheckUI binary control)
    private func presentRow(_ title: String, selection: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundColor(.white.opacity(0.9))
            ImageBinaryChoice(selection, kind: .presentMissing)
        }
    }

    private func yesNoRow(_ title: String, selection: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundColor(.white.opacity(0.9))
            ImageBinaryChoice(selection, kind: .yesNo)
        }
    }
}
