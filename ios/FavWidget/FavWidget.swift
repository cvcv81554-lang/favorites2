// ويدجت «المفضلة»: نجمة اليوم + أقرب إصدار لمفضلاتك. البيانات يكتبها التطبيق في مجموعة التطبيق المشتركة.
// الوضع الخاص (اختياري، وتلقائي مع قفل التطبيق): بلا صورة ولا اسم ولا عنوان عمل.
import WidgetKit
import SwiftUI

private let appGroup = "group.com.favlib.favorites2"
private let gold = Color(red: 0.96, green: 0.80, blue: 0.48)

struct FavEntry: TimelineEntry {
  let date: Date
  let priv: Bool
  let name: String
  let meta: String
  let image: UIImage?
  let nextTitle: String
  let nextWhen: String
  let nextWeek: Int
  let total: Int
  let link: URL?
}

struct FavProvider: TimelineProvider {
  func load() -> FavEntry {
    let d = UserDefaults(suiteName: appGroup)
    let priv = d?.bool(forKey: "priv") ?? false
    let id = d?.string(forKey: "spot_id") ?? ""
    var img: UIImage? = nil
    if !priv, let p = d?.string(forKey: "spot_img"), !p.isEmpty { img = UIImage(contentsOfFile: p) }
    // رابط بلا مضيف ⇒ يفهمه موجّه التطبيق مسارًا مباشرة (/p/<id>)
    let link = URL(string: (priv || id.isEmpty) ? "favorites2:///?homeWidget" : "favorites2:///p/\(id)?homeWidget")
    return FavEntry(date: Date(), priv: priv, name: d?.string(forKey: "spot_name") ?? "", meta: d?.string(forKey: "spot_meta") ?? "", image: img,
                    nextTitle: d?.string(forKey: "next_title") ?? "", nextWhen: d?.string(forKey: "next_when") ?? "",
                    nextWeek: d?.integer(forKey: "next_week") ?? 0, total: d?.integer(forKey: "total") ?? 0, link: link)
  }
  func placeholder(in context: Context) -> FavEntry {
    FavEntry(date: Date(), priv: true, name: "", meta: "", image: nil, nextTitle: "", nextWhen: "", nextWeek: 0, total: 0, link: nil)
  }
  func getSnapshot(in context: Context, completion: @escaping (FavEntry) -> Void) { completion(load()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<FavEntry>) -> Void) {
    let cal = Calendar.current
    let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
    completion(Timeline(entries: [load()], policy: .after(next)))
  }
}

struct FavWidgetView: View {
  @Environment(\.widgetFamily) var family
  let e: FavEntry

  var showPhoto: Bool { !e.priv && e.image != nil }
  var title: String { (e.priv || e.name.isEmpty) ? (e.total > 0 ? "\(e.total) ممثلة" : "المفضلة") : e.name }

  var body: some View {
    Group { if family == .systemSmall { small } else { medium } }
      .environment(\.layoutDirection, .rightToLeft)
      .widgetURL(e.link)
      .containerBackground(for: .widget) { background }
  }

  @ViewBuilder var background: some View {
    if family == .systemSmall, showPhoto, let img = e.image {
      ZStack {
        Image(uiImage: img).resizable().scaledToFill()
        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
      }
    } else {
      LinearGradient(colors: [Color(red: 0.18, green: 0.09, blue: 0.19), Color(red: 0.04, green: 0.03, blue: 0.06)], startPoint: .topTrailing, endPoint: .bottomLeading)
    }
  }

  var small: some View {
    VStack(alignment: .leading, spacing: 2) {
      Spacer(minLength: 0)
      Text("نجمة اليوم").font(.caption2.weight(.semibold)).foregroundColor(gold)
      Text(title).font(.headline).foregroundColor(.white).lineLimit(2)
      if !e.priv && !e.meta.isEmpty { Text(e.meta).font(.caption2).foregroundColor(.white.opacity(0.8)).lineLimit(1) }
      if (e.priv || !showPhoto) && !e.nextWhen.isEmpty { Text("إصدار \(e.nextWhen)").font(.caption2).foregroundColor(gold).lineLimit(1) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }

  var medium: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("نجمة اليوم").font(.caption2.weight(.semibold)).foregroundColor(gold)
        Text(title).font(.headline).foregroundColor(.white).lineLimit(1)
        if !e.priv && !e.meta.isEmpty { Text(e.meta).font(.caption2).foregroundColor(.white.opacity(0.75)).lineLimit(1) }
        Spacer(minLength: 4)
        if !e.nextWhen.isEmpty {
          Text("أقرب إصدار لمفضلاتك: \(e.nextWhen)").font(.caption2.weight(.semibold)).foregroundColor(gold).lineLimit(1)
          if !e.priv && !e.nextTitle.isEmpty { Text(e.nextTitle).font(.caption).foregroundColor(.white).lineLimit(1) }
          if e.nextWeek > 1 { Text("\(e.nextWeek) إصدارات خلال أسبوع").font(.caption2).foregroundColor(.white.opacity(0.75)) }
        } else {
          Text("لا إصدارات قادمة لمفضلاتك").font(.caption2).foregroundColor(.white.opacity(0.6))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if showPhoto, let img = e.image {
        Image(uiImage: img).resizable().scaledToFill().frame(width: 118, height: 140).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    }
  }
}

@main
struct FavWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "FavWidget", provider: FavProvider()) { e in FavWidgetView(e: e) }
      .configurationDisplayName("المفضلة")
      .description("نجمة اليوم وأقرب إصدار لمفضلاتك")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
