import SwiftUI

struct ContactAvatarView: View {
    let contact: Contact
    var size: CGFloat = 48
    var showsStar = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar

            if showsStar, contact.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(.yellow, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: max(2, size * 0.04))
                    }
                    .offset(x: size * 0.04, y: size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL = contact.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    fallbackAvatar
                @unknown default:
                    fallbackAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(avatarColor)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    private var initial: String {
        contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }

    private var avatarColor: Color {
        let colors: [Color] = [.purple, .blue, .teal, .green, .orange, .pink, .indigo]
        let hash = abs(contact.displayName.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return colors[hash % colors.count]
    }
}
