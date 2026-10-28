import SwiftUI

struct ProfileView: View {
    private var auth: AuthStore { .shared }

    var body: some View {
        Group {
            if let user = auth.user {
                LoggedInProfile(user: user)
            } else {
                LoginView()
            }
        }
        .navigationTitle("Профиль")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}

private struct LoggedInProfile: View {
    let user: UserRef

    @State private var profile: UserProfile?
    @State private var confirmLogout = false

    private var auth: AuthStore { .shared }

    var body: some View {
        List {
            Section {
                UserHeader(username: user.username, avatarURL: user.avatarURL, profile: profile)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink(value: Route.userPosts(user.username)) {
                    Label("Мои посты", systemImage: "square.grid.2x2")
                }
                NavigationLink(value: Route.favorites) {
                    Label("Избранное", systemImage: "bookmark")
                }
                NavigationLink(value: Route.subscriptions) {
                    Label("Подписки на теги", systemImage: "number")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmLogout = true
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadProfile() }
        .task { if profile == nil { await loadProfile() } }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await auth.logout() }
            }
        }
    }

    private func loadProfile() async {
        profile = try? await API.user(username: user.username)
    }
}

struct UserHeader: View {
    let username: String
    let avatarURL: URL?
    let profile: UserProfile?

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(url: avatarURL, name: username, size: 88)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            Text(username)
                .font(.title2.weight(.bold))
            if let profile {
                HStack {
                    StatLabel(value: Formatting.compact(Int(profile.rating)), title: "рейтинг")
                    StatLabel(value: Formatting.compact(profile.postNum), title: "постов")
                    StatLabel(value: Formatting.compact(profile.commentNum), title: "комментариев")
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                Text("На сайте с \(Formatting.shortDate(profile.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }
}

struct LoginView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "atom")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Color.accentColor.gradient)
                    Text("Вход в JoyReactor")
                        .font(.title2.weight(.bold))
                    Text("Голосуйте, сохраняйте посты в избранное, подписывайтесь на теги и комментируйте.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Логин", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(login)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button(action: login) {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text("Войти").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(busy || username.isEmpty || password.isEmpty)
            }

            Section {
                Link(destination: URL(string: "https://joyreactor.cc/register")!) {
                    Label("Регистрация на сайте", systemImage: "person.badge.plus")
                }
                Link(destination: URL(string: "https://joyreactor.cc/reset-password")!) {
                    Label("Забыли пароль?", systemImage: "key")
                }
            }
        }
    }

    private func login() {
        guard !username.isEmpty, !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await AuthStore.shared.login(name: username.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
                Haptics.tap()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct UserView: View {
    let username: String

    @State private var profile: UserProfile?
    @State private var store = PostListModelStore()

    var body: some View {
        PostFeed(model: store.model(for: .user(username: username))) {
            VStack(spacing: 0) {
                UserHeader(username: username, avatarURL: profile?.avatarURL, profile: profile)
                    .background(Color(.systemBackground))
                SectionSeparator()
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: "https://joyreactor.cc/user/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)") {
                    ShareLink(item: url)
                }
            }
        }
        .task { if profile == nil { profile = try? await API.user(username: username) } }
    }
}

struct SubscriptionsView: View {
    @State private var tags: [TagSummary] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                ErrorStateView(message: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
            } else if loaded && tags.isEmpty {
                ContentUnavailableView("Нет подписок", systemImage: "number",
                                       description: Text("Подписывайтесь на теги на их страницах"))
                    .listRowBackground(Color.clear)
            }
            ForEach(tags) { tag in
                TagRow(tag: tag)
            }
        }
        .overlay { if !loaded { ProgressView() } }
        .navigationTitle("Подписки")
        .refreshable { await load() }
        .task { if !loaded { await load() } }
    }

    private func load() async {
        do {
            tags = try await API.subscribedTags().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
        loaded = true
    }
}

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var confirmNSFW = false
    @State private var cacheSize = ImagePipeline.shared.diskUsage

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.showNSFW },
                    set: { newValue in
                        if newValue { confirmNSFW = true } else { settings.showNSFW = false }
                    })) {
                    Label("Показывать контент 18+", systemImage: "eye.trianglebadge.exclamationmark")
                }
                Toggle(isOn: $settings.autoplayVideo) {
                    Label("Автовоспроизведение видео", systemImage: "play.rectangle")
                }
                Toggle(isOn: $settings.fullQualityImages) {
                    Label("Картинки в полном качестве", systemImage: "photo")
                }
                Picker(selection: $settings.defaultFeed) {
                    ForEach(PostLineType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                } label: {
                    Label("Лента по умолчанию", systemImage: "house")
                }
            } header: {
                Text("Контент")
            } footer: {
                Text("Полное качество расходует больше трафика и памяти.")
            }

            Section("Хранилище") {
                LabeledContent("Кэш медиа", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                Button("Очистить кэш", role: .destructive) {
                    ImagePipeline.shared.clearCache()
                    cacheSize = ImagePipeline.shared.diskUsage
                    ToastCenter.shared.show("Кэш очищен")
                }
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Link(destination: URL(string: "https://joyreactor.cc")!) {
                    Label("joyreactor.cc", systemImage: "safari")
                }
            } header: {
                Text("О приложении")
            } footer: {
                Text("Неофициальный клиент JoyReactor. Весь контент принадлежит его авторам.")
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Вам есть 18 лет?", isPresented: $confirmNSFW) {
            Button("Да, мне есть 18") { settings.showNSFW = true }
            Button("Нет", role: .cancel) {}
        } message: {
            Text("Контент 18+ может содержать откровенные материалы.")
        }
    }
}
