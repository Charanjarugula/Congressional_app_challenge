import SwiftUI

/// Report a player, with the option to block them in the same step.
struct ReportView: View {
    let player: PlayerCard
    var hitID: UUID? = nil
    /// A single message being reported, shown at the top of the sheet.
    var message: Message? = nil
    let onDone: (_ alsoBlocked: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(message == nil ? "Report \(player.firstName)" : "Report message")
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.blue)
                    Spacer()
                }
            }
            .frame(height: 52)
            .padding(.horizontal, CourtlyMetrics.screenPadding)

            ScrollView {
                VStack(spacing: 8) {
                    if let message {
                        Text("“\(message.body)”")
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
                            .padding(.bottom, 8)
                    }
                    ForEach(ReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(CourtlyFont.bodySemibold)
                                    .foregroundStyle(CourtlyColor.ink)
                                Spacer()
                                SelectionMark(isSelected: reason == option)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                                    .fill(reason == option ? CourtlyColor.blueTint : CourtlyColor.card)
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    HStack {
                        Text("Also block \(player.firstName)")
                            .font(CourtlyFont.body)
                            .foregroundStyle(CourtlyColor.ink)
                        Spacer()
                        Toggle("Also block", isOn: $alsoBlock)
                            .labelsHidden()
                            .tint(CourtlyColor.blue)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
                    .padding(.top, 16)
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Send report", isEnabled: reason != nil, isLoading: isSending, action: send)
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(CourtlyColor.groupedBackground)
        }
        .preferredColorScheme(.light)
        .errorAlert($errorMessage, title: "Couldn’t send the report")
    }

    private func send() {
        guard let reason else { return }
        isSending = true
        Task { @MainActor in
            do {
                try await API.People.report(player.id, reason: reason, details: nil, alsoBlock: alsoBlock, hitID: hitID, messageID: message?.id)
                isSending = false
                onDone(alsoBlock)
            } catch {
                isSending = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
