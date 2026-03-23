import SwiftUI

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
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.15, blue: 0.10),
                        Color(red: 0.36, green: 0.22, blue: 0.15),
                        Color(red: 0.30, green: 0.18, blue: 0.13),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            LoginAnimatedSpotsHero()
                                .padding(.top, 8)

                            VStack(alignment: .leading, spacing: 0) {
                                headerBlock
                                    .padding(.horizontal, 22)
                                    .padding(.top, 28)
                                    .padding(.bottom, 22)

                                Group {
                                    switch step {
                                    case .phone: phoneFields
                                    case .code: codeFields
                                    case .profile: profileFields
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.bottom, 32)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 28,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 28,
                                    style: .continuous
                                )
                                .fill(Color.white)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 24, y: -4)
                            .id("loginCard")

                            Color.clear.frame(height: 120)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(stepTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
            Text(stepSubtitle)
                .font(.system(size: 15))
                .foregroundColor(Color(white: 0.45))
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
                TextField("Mobile number", text: $phoneDigits)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 16))
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
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 18, weight: .semibold))
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
                .foregroundColor(Color.blue)
                Spacer()
                Button("Resend code") {
                    Task { await sendCode() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.blue)
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
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .font(.system(size: 16))
                    .focused($focus, equals: .firstName)
            }
            .id("anchor-firstName")
            loginPillField(icon: "person.fill") {
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .font(.system(size: 16))
                    .focused($focus, equals: .lastName)
            }
            .id("anchor-lastName")
            loginPillField(icon: "envelope.fill") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 16))
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
                .foregroundColor(Color(white: 0.55))
                .frame(width: 22)
            content()
                .foregroundColor(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.94))
        .clipShape(Capsule())
    }

    private func primaryButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(disabled || isLoading ? Color.black.opacity(0.35) : Color.black)
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
        do {
            try await api.completeAuthProfile(
                accessToken: pair.token,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces)
            )
            auth.completeSignIn(
                phone: pair.phone,
                token: pair.token,
                first: firstName,
                last: lastName,
                email: email
            )
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
