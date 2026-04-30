// MARK: - Onboarding View
// First-run experience: three-step setup guide that walks the user through
// enabling the System Extension and understanding the key interactions.

import SwiftUI

struct OnboardingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon:     "shield.lefthalf.filled",
            color:    .gwTeal,
            title:    "Welcome to GlassWall",
            subtitle: "Your personal network firewall",
            body:     "GlassWall watches every connection your apps make. When something connects somewhere new, you decide whether to allow it — no silent background activity.",
            action:   nil
        ),
        OnboardingStep(
            icon:     "puzzlepiece.extension.fill",
            color:    .gwBlue,
            title:    "Enable the Network Extension",
            subtitle: "One-time setup required",
            body:     "GlassWall uses a macOS System Extension to intercept connections. You'll need to approve it in System Settings → Privacy & Security the first time.",
            action:   OnboardingStep.Action(
                label:   "Open System Settings",
                sfIcon:  "gear",
                handler: {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                    )
                }
            )
        ),
        OnboardingStep(
            icon:     "hand.raised.fill",
            color:    .gwAllow,
            title:    "You're in Control",
            subtitle: "How to respond to connection requests",
            body:     "When an app tries to connect somewhere new, a card appears in the top-right corner. Choose:\n\n• Always Allow — trust this connection permanently\n• Allow 1 Hour — let it through temporarily\n• Block Session — block until you restart\n• Always Block — never allow this app",
            action:   nil
        ),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.gwBgElevated, .gwBgBase],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                progressBar
                    .padding(.top, GWS.xl)
                    .padding(.horizontal, GWS.xxxl)

                Spacer()

                // Step content
                stepContent(steps[step])
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(step)

                Spacer()

                // Navigation
                navigationRow
                    .padding(GWS.xl)
            }
        }
        .frame(width: 560, height: 460)
        .preferredColorScheme(.dark)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Progress Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var progressBar: some View {
        HStack(spacing: GWS.sm) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? steps[step].color : Color.gwBorder)
                    .frame(height: 3)
                    .animation(.gwSpring, value: step)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Step Content
    // ─────────────────────────────────────────────────────────────────────────

    private func stepContent(_ s: OnboardingStep) -> some View {
        VStack(spacing: GWS.xl) {
            // Large icon
            ZStack {
                Circle()
                    .fill(s.color.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: s.icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(s.color)
            }
            .breathingGlow(s.color, radius: 16)

            VStack(spacing: GWS.md) {
                Text(s.subtitle.uppercased())
                    .font(.gwCaptionMed)
                    .foregroundStyle(s.color)
                    .tracking(1.2)

                Text(s.title)
                    .font(.gwLargeTitle)
                    .foregroundStyle(.gwText1)
                    .multilineTextAlignment(.center)

                Text(s.body)
                    .font(.gwBody)
                    .foregroundStyle(.gwText2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }

            // Optional action button
            if let action = s.action {
                Button {
                    action.handler()
                } label: {
                    HStack(spacing: GWS.sm) {
                        Image(systemName: action.sfIcon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(action.label)
                            .font(.gwBodyMed)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, GWS.xl)
                    .padding(.vertical, GWS.md)
                    .background(s.color)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .gwGlowShadow(color: s.color, radius: 10)
            }
        }
        .padding(.horizontal, GWS.xxxl)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Navigation Row
    // ─────────────────────────────────────────────────────────────────────────

    private var navigationRow: some View {
        HStack {
            // Back / Skip
            if step == 0 {
                Button("Skip") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.gwBody)
                    .foregroundStyle(.gwText3)
            } else {
                Button {
                    withAnimation(.gwSpring) { step -= 1 }
                } label: {
                    HStack(spacing: GWS.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .font(.gwBody)
                .foregroundStyle(.gwText2)
            }

            Spacer()

            // Step counter
            Text("\(step + 1) of \(steps.count)")
                .font(.gwCaption)
                .foregroundStyle(.gwText3)

            Spacer()

            // Next / Done
            Button {
                withAnimation(.gwSpring) {
                    if step < steps.count - 1 { step += 1 } else { dismiss() }
                }
            } label: {
                HStack(spacing: GWS.xs) {
                    Text(step < steps.count - 1 ? "Next" : "Get Started")
                        .font(.gwBodyMed)
                    if step < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, GWS.lg)
                .padding(.vertical, GWS.sm + 2)
                .background(steps[step].color)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Model
// ─────────────────────────────────────────────────────────────────────────────

struct OnboardingStep {
    struct Action {
        let label:   String
        let sfIcon:  String
        let handler: () -> Void
    }

    let icon:     String
    let color:    Color
    let title:    String
    let subtitle: String
    let body:     String
    let action:   Action?
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    OnboardingView()
}
