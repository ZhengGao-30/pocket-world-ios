import SwiftUI

struct CompanionView: View {
    @Bindable var store: WorldStore
    let onExplore: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cuddle = false
    @State private var interactionCount = 0
    @State private var feedback = "点点我，今天也一起出门吧"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "YOUR LITTLE EXPLORER")
                        Text("小伙伴，大冒险。").font(.system(size: 29, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer(minLength: 0)
                }
                petStage
                HStack {
                    Text("今天和谁一起？").font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Text("2 位小伙伴").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }.foregroundStyle(Palette.ink)
                HStack(spacing: 12) {
                    ForEach(PetKind.allCases) { pet in petChoice(pet) }
                }
                Button(action: onExplore) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("好奇心，准备好了。").font(.system(size: 16, weight: .bold))
                            Text("带\(store.pet.name)去发现附近的小惊喜").font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 22))
                    }
                    .foregroundStyle(.white).padding(22).background(Palette.teal, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(PressStyle())
                Text("原创宠物插画 · 伙伴选择保存在本地")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }.padding(.horizontal, 24).padding(.top, 12)
        }
        .scrollIndicators(.hidden).background(Palette.cream)
        .sensoryFeedback(.success, trigger: interactionCount)
    }

    private var petStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(
                LinearGradient(colors: [Palette.mint, Color(hex: 0xEDF3DA)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.5), lineWidth: 1).frame(width: 250, height: 250).offset(x: 85, y: -45)
            Circle().stroke(.white.opacity(0.55), lineWidth: 1).frame(width: 180, height: 180).offset(x: 85, y: -45)
            VStack {
                HStack {
                    PillLabel(text: "漫游搭子", symbol: "pawprint.fill", color: .white.opacity(0.7))
                    Spacer()
                    Image(systemName: "sparkle").foregroundStyle(Palette.teal).font(.system(size: 25))
                }
                Spacer()
                VStack(spacing: 6) {
                    Text(store.pet.name).font(.system(size: 27, weight: .heavy, design: .rounded))
                    Text(feedback).font(.system(size: 12)).foregroundStyle(Palette.teal)
                }.foregroundStyle(Palette.ink)
            }.padding(22)
            Button(action: petTapped) {
                Image(store.pet.asset).resizable().scaledToFit()
                    .frame(width: 240, height: 245)
                    .rotationEffect(.degrees(cuddle && !reduceMotion ? -9 : 3))
                    .scaleEffect(cuddle && !reduceMotion ? 1.08 : 1)
                    .offset(y: -12)
            }
            .buttonStyle(.plain).accessibilityLabel("摸摸\(store.pet.name)")
            if cuddle {
                Image(systemName: "heart.fill").font(.system(size: 27)).foregroundStyle(Palette.coral)
                    .offset(x: 93, y: -77).transition(.scale.combined(with: .opacity))
                Image(systemName: "sparkle").font(.system(size: 19)).foregroundStyle(Palette.teal)
                    .offset(x: -97, y: -38).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 346).clipShape(RoundedRectangle(cornerRadius: 34))
        .task(id: interactionCount) {
            guard interactionCount > 0 else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6)) { cuddle = false }
        }
    }

    private func petChoice(_ pet: PetKind) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                store.selectPet(pet)
                feedback = "点点我，今天也一起出门吧"
            }
        } label: {
            HStack(spacing: 6) {
                Image(pet.asset).resizable().scaledToFit().frame(width: 48, height: 65)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pet.name).font(.system(size: 16, weight: .bold))
                    Text(pet == .bunny ? "好奇小兔" : "温柔水獭").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                if pet == store.pet {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.teal)
                }
            }
            .padding(10).frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(pet == store.pet ? Palette.teal : .clear, lineWidth: 1.5))
            .foregroundStyle(Palette.ink)
        }.buttonStyle(PressStyle()).accessibilityLabel("选择\(pet.name)")
    }

    private func petTapped() {
        interactionCount += 1
        feedback = ["收到一份摸摸，快乐加满！", "把好奇心装好，我们走吧", "今天的小美好，会在哪里呢？"][interactionCount % 3]
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5)) { cuddle = true }
    }
}
