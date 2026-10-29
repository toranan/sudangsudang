import SwiftUI

struct AppTabItem<Tag: Hashable>: Identifiable {
    let tag: Tag
    let title: String
    let systemImage: String

    var id: Tag { tag }
}

// 화면 아래 떠 있는 검정 알약 탭바. 선택된 탭만 이름까지 보인다.
struct AppTabBar<Tag: Hashable>: View {
    @Binding var selection: Tag
    let items: [AppTabItem<Tag>]

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
                if item.tag != items.last?.tag {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .background(Capsule().fill(Color.appInk))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
    }

    private func tabButton(_ item: AppTabItem<Tag>) -> some View {
        let isSelected = item.tag == selection
        return Button {
            guard !isSelected else { return }
            Haptics.tap()
            selection = item.tag
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if isSelected {
                    Text(item.title)
                        .font(.app(.callout, .bold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundColor(isSelected ? .appInk : Color(red: 154/255, green: 160/255, blue: 169/255))
            .padding(.horizontal, isSelected ? 16 : 12)
            .frame(height: 42)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.appOnInk)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// 탭바(42 + 위아래 8씩)와 아래 여백을 합친 높이. 스크롤 끝이 탭바에 가리지 않게 이만큼 비워 둔다.
private let appTabBarReservedHeight: CGFloat = 70

extension View {
    // TabView에 붙여 AppTabBar를 아래에 띄운다. 각 탭에는 .hidesSystemTabBar()를 붙인다.
    func appTabBar<Tag: Hashable>(selection: Binding<Tag>, items: [AppTabItem<Tag>]) -> some View {
        self.overlay(alignment: .bottom) {
            AppTabBar(selection: selection, items: items)
                .ignoresSafeArea(.keyboard)
        }
    }

    // 기본 탭바를 숨기고, 떠 있는 탭바 높이만큼 아래를 비운다. 내용은 탭바 뒤로 지나가며 끝까지 스크롤된다.
    func hidesSystemTabBar() -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: appTabBarReservedHeight)
            }
    }
}
