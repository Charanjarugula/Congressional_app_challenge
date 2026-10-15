import PhotosUI
import SwiftUI
import UIKit

enum ProfileSheet: String, Identifiable {
    case name, availability, level, formats, area

    var id: String { rawValue }
}

/// Grabber, Cancel / title row, scrolling content, Save at the bottom.
struct SheetScaffold<Content: View>: View {
    let title: String
    var saveTitle = "Save"
    var canSave = true
    var isSaving = false
    var detents: Set<PresentationDetent> = [.medium, .large]
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)
            ZStack {
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.blue)
                        .disabled(isSaving)   // a save already under way lands either way, so the sheet stays until it finishes
                    Spacer()
                }
            }
            .frame(height: 36)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: saveTitle, isEnabled: canSave, isLoading: isSaving, action: onSave)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .interactiveDismissDisabled(isSaving)
    }
}

/// 52pt white row that turns blue-tinted when picked.
struct OptionRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                SelectionMark(isSelected: isSelected)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, subtitle == nil ? 0 : 10)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(isSelected ? CourtlyColor.blueTint : CourtlyColor.card)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Level

struct LevelSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var level: PlayerLevel?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Level", canSave: level != nil, isSaving: isSaving, onSave: save) {
            VStack(spacing: 8) {
                ForEach(PlayerLevel.allCases) { option in
                    OptionRow(title: option.title, subtitle: option.description, isSelected: level == option) { level = option }
                }
            }
        }
        .onAppear { if level == nil { level = session.profile?.level } }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        guard let level else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile(["level": level.rawValue])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - What you play

struct FormatsSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var formats: Set<PlayFormat> = []
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "What you play", canSave: !formats.isEmpty, isSaving: isSaving, onSave: save) {
            VStack(spacing: 8) {
                ForEach(PlayFormat.allCases) { option in
                    OptionRow(title: option.title, subtitle: option.description, isSelected: formats.contains(option)) {
                        if formats.contains(option) { formats.remove(option) } else { formats.insert(option) }
                    }
                }
            }
        }
        .onAppear {
            if !seeded {
                seeded = true
                formats = Set(session.profile?.formats ?? [])
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        isSaving = true
        let ordered = PlayFormat.allCases.filter { formats.contains($0) }.map(\.rawValue)
        Task { @MainActor in
            do {
                try await session.updateProfile(["formats": ordered])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
