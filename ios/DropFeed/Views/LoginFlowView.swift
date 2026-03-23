import SwiftUI

#if DEBUG
/// Skip FastAPI `/chat/auth/*` while the backend isn’t wired; Release builds always use the real API.
private enum LoginFlowMock {
    static let enabled = true
    static let accessToken = "mock-snag-access-token"
}
#endif

/// Phone → SMS code → name & email, then enters the main app.
struct LoginFlowView: View {
    @EnvironmentObject private var auth: AuthSessionManager

    private enum Step {
        case phone
        case code
        case profile
    }

    private enum LoginFocus: String, Hashable {
        case phone, code, firstName, lastName, email
    }

    @State private var step: Step = .phone
    @State private var phoneDigits = ""
    @State private var code = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focus: LoginFocus?

    private let api = APIService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LoginAnimatedSpotsHero()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            #if DEBUG
                            if LoginFlowMock.enabled {
                                Text("Dev build: mock login (no server). Any 6-digit code works.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SnagDesignSystem.exploreCoralSolid.opacity(0.95))
                                    .padding(.horizontal, 22)
                                    .padding(.top, 18)
                                    .padding(.bottom, 4)
                            }
                            #endif
                            headerBlock
                                .padding(.horizontal, 22)
                                .padding(.top, 22)
                                .padding(.bottom, 18)

                            Group {
                                switch step {
                                case .phone: phoneFields
                                case .code: codeFields
                                case .profile: profileFields
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 28)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("loginCard")
                    }
                    .frame(maxWidth: .infinity)
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 28,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 28,
                            style: .continuous
                        )
                        .fill(Color.black)
                    }
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 28,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 28,
                            style: .continuous
                        )
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 24, y: -6)
                    .onChange(of: focus) { _, new in
                        guard let new else { return }
                        let id = "anchor-\(new.rawValue)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            withAnimation(.easeOut(duration: 0.32)) {
                                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.28))
                            }
                        }
                    }
                    .onChange(of: step) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.28)) {
                                proxy.scrollTo("loginCard", anchor: .top)
                            }
                        }
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if auth.awaitingProfile, let pair = auth.pendingPhoneAndToken() {
                step = .profile
                phoneDigits = Self.displayDigits(fromE164: pair.phone)
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(stepTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            if step == .phone {
                Text("Always booked. Sometimes open.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(stepSubtitle)
                .font(.system(size: 15))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepTitle: String {
        switch step {
        case .phone: return "Sign in"
        case .code: return "Verify"
        case .profile: return "Almost there"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .phone:
            return "Enter your mobile number. We’ll text you a verification code."
        case .code:
            return "Enter the 6-digit code we sent."
        case .profile:
            return "Tell us your name and email so we can personalize Snag."
        }
    }

    private var phoneFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            loginPillField(icon: "phone.fill") {
                TextField(
                    "",
                    text: $phoneDigits,
                    prompt: Text("Mobile number").foregroundColor(.white.opacity(0.42))
                )
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .focused($focus, equals: .phone)
            }
            .id("anchor-phone")
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.85))
            }
            primaryButton(title: isLoading ? "Sending…" : "Continue", disabled: !canSubmitPhone) {
                Task { await sendCode() }
            }
        }
    }

    private var codeFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            loginPillField(icon: "lock.shield.fill") {
                TextField(
                    "",
                    text: $code,
                    prompt: Text("6-digit code").foregroundColor(.white.opacity(0.42))
                )
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .focused($focus, equals: .code)
                    .onChange(of: code) { _, new in
                        let filtered = new.filter { $0.isNumber }
                        code = String(filtered.prefix(6))
                    }
            }
            .id("anchor-code")
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.85))
            }
            HStack {
                Button("Change number") {
                    errorMessage = nil
                    step = .phone
                    code = ""
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                Spacer()
                Button("Resend code") {
                    Task { await sendCode() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                .disabled(isLoading)
            }
            primaryButton(title: isLoading ? "Checking…" : "Verify", disabled: code.count != 6) {
                Task { await verifyCode() }
            }
        }
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            loginPillField(icon: "person.fill") {
                TextField(
                    "",
                    text: $firstName,
                    prompt: Text("First name").foregroundColor(.white.opacity(0.42))
                )
                    .textContentType(.givenName)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .focused($focus, equals: .firstName)
            }
            .id("anchor-firstName")
            loginPillField(icon: "person.fill") {
                TextField(
                    "",
                    text: $lastName,
                    prompt: Text("Last name").foregroundColor(.white.opacity(0.42))
                )
                    .textContentType(.familyName)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .focused($focus, equals: .lastName)
            }
            .id("anchor-lastName")
            loginPillField(icon: "envelope.fill") {
                TextField(
                    "",
                    text: $email,
                    prompt: Text("Email").foregroundColor(.white.opacity(0.42))
                )
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .focused($focus, equals: .email)
            }
            .id("anchor-email")
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.85))
            }
            primaryButton(title: isLoading ? "Saving…" : "Get started", disabled: !canSubmitProfile) {
                Task { await completeProfile() }
            }
        }
    }

    private func loginPillField<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func primaryButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    disabled || isLoading
                        ? Color.white.opacity(0.14)
                        : SnagDesignSystem.exploreCoralSolid
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }

    private var canSubmitPhone: Bool {
        Self.e164(fromDigitsInput: phoneDigits) != nil
    }

    private var canSubmitProfile: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
    }

    private func sendCode() async {
        guard let e164 = Self.e164(fromDigitsInput: phoneDigits) else {
            errorMessage = "Enter a valid US mobile number."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        if LoginFlowMock.enabled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            step = .code
            return
        }
        #endif
        do {
            try await api.requestAuthCode(phoneE164: e164)
            step = .code
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode() async {
        guard let e164 = Self.e164(fromDigitsInput: phoneDigits) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        if LoginFlowMock.enabled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            auth.setPendingVerification(phone: e164, token: LoginFlowMock.accessToken)
            step = .profile
            return
        }
        #endif
        do {
            let token = try await api.verifyAuthCode(phoneE164: e164, code: code)
            auth.setPendingVerification(phone: e164, token: token)
            step = .profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeProfile() async {
        guard let pair = auth.pendingPhoneAndToken() else {
            errorMessage = "Session expired. Start again."
            step = .phone
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let f = firstName.trimmingCharacters(in: .whitespaces)
        let l = lastName.trimmingCharacters(in: .whitespaces)
        let em = email.trimmingCharacters(in: .whitespaces)
        #if DEBUG
        if LoginFlowMock.enabled {
            try? await Task.sleep(nanoseconds: 250_000_000)
            auth.completeSignIn(phone: pair.phone, token: pair.token, first: f, last: l, email: em)
            return
        }
        #endif
        do {
            try await api.completeAuthProfile(
                accessToken: pair.token,
                firstName: f,
                lastName: l,
                email: em
            )
            auth.completeSignIn(phone: pair.phone, token: pair.token, first: f, last: l, email: em)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// US-focused: 10 digits → +1…
    private static func e164(fromDigitsInput raw: String) -> String? {
        let d = raw.filter { $0.isNumber }
        if d.count == 10 { return "+1" + d }
        if d.count == 11, d.hasPrefix("1") { return "+" + d }
        return nil
    }

    private static func displayDigits(fromE164 e164: String) -> String {
        let d = e164.filter { $0.isNumber }
        if d.count == 11, d.hasPrefix("1") { return String(d.dropFirst()) }
        return d
    }
}

#Preview {
    LoginFlowView()
        .environmentObject(AuthSessionManager())
}
