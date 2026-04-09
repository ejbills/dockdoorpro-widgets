import AppKit
import SwiftUI
import PDFKit
import AVFoundation
import AVKit
import Quartz

// MARK: - NSPanel personnalisé (accepte la saisie clavier)

/// Sous-classe de NSPanel qui autorise le focus clavier tout en restant non-activant.
/// Nécessaire pour que les champs de texte et les raccourcis clavier fonctionnent
/// dans le panneau flottant sans voler le focus à l'application active.
final class PanneauEditable: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Aide couleur d'accentuation

private extension Color {
    /// Couleur d'accentuation système assombrie d'environ 20 % pour un rendu moins vif.
    /// Mise en cache statique : évite de recalculer la blending à chaque accès.
    static let accentAttenuation: Color = {
        Color(NSColor.controlAccentColor.blended(withFraction: 0.22, of: .black) ?? .controlAccentColor)
    }()
}

// MARK: - Helpers partagés

private extension DateFormatter {
    // OPTIMISATION 1 : DateFormatter est coûteux à instancier — on le crée une seule fois
    // au démarrage (lazy static let) au lieu de le recréer à chaque affichage de date.
    static let heureSeule: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = L.localeDate; return f
    }()
    static let datePleine: DateFormatter = {
        let f = DateFormatter()
        f.locale = L.localeDate
        f.dateFormat = langueWidget() == "en" ? "MMM d, HH:mm" : "d MMMM HH:mm"
        return f
    }()
}

// MARK: - Helper PNG pour sauvegarde image

private func donneesPNG(depuis image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .png, properties: [:])
}

// MARK: - Enum de filtre

enum FiltrePressePapier: String, CaseIterable {
    case tout    = "tout"
    case medias  = "medias"
    case donnees = "donnees"

    /// Étiquette traduite selon la langue active.
    var etiquette: String {
        switch self {
        case .tout:    return L.tout
        case .medias:  return L.medias
        case .donnees: return L.donnees
        }
    }

    var icone: String {
        switch self {
        case .tout:    return "square.grid.2x2"
        case .medias:  return "photo"
        case .donnees: return "info.circle"
        }
    }
}

// MARK: - Détection de couleur
// OPTIMISATION 9 : les regex et la fonction detecterCouleur ont été déplacées dans
// ElementPressePapier (ClipboardMonitor.swift) et le résultat est mis en cache à la
// création de chaque élément dans `couleurCachee`. On conserve ici un alias local pour
// les quelques appels qui opèrent sur du texte brut en dehors d'un ElementPressePapier.
private func detecterCouleur(dans texte: String) -> Color? {
    ElementPressePapier.detecterCouleurStatique(dans: texte)
}

// MARK: - Échantillon de couleur

private struct VueEchantillonCouleur: View {
    let couleur: Color
    let etiquette: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(couleur)
                .frame(width: 20, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            Text(etiquette)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Aperçu de fichier (basé sur le contenu, sans QLPreviewView)

/// Aperçu PDF avec boutons de navigation de pages ← →
private struct ApercuPDFPages: View {
    let url: URL
    @State private var pageCourante: Int = 0
    @State private var nombrePages:  Int = 0

    var body: some View {
        VStack(spacing: 0) {
            VuePDFKit(url: url, pageCourante: $pageCourante, nombrePages: $nombrePages)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if nombrePages > 1 {
                HStack(spacing: 12) {
                    Button {
                        if pageCourante > 0 { pageCourante -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 28)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(pageCourante == 0)

                    Text("\(pageCourante + 1) / \(nombrePages)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48)

                    Button {
                        if pageCourante < nombrePages - 1 { pageCourante += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 28)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(pageCourante == nombrePages - 1)
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct VuePDFKit: NSViewRepresentable {
    let url: URL
    @Binding var pageCourante: Int
    @Binding var nombrePages:  Int

    func makeCoordinator() -> Coordinateur { Coordinateur(self) }

    func makeNSView(context: Context) -> PDFView {
        let vuePDF = PDFView()
        vuePDF.autoScales         = true
        vuePDF.displayMode        = .singlePage
        vuePDF.displayDirection   = .horizontal
        vuePDF.displaysPageBreaks = false
        vuePDF.backgroundColor    = .clear
        vuePDF.pageShadowsEnabled = false
        // Supprimer le fond de la vue de défilement interne
        if let scrollView = vuePDF.subviews.first as? NSScrollView {
            scrollView.drawsBackground = false
            scrollView.contentView.layer?.backgroundColor = .none
        }
        if let doc = PDFDocument(url: url) {
            vuePDF.document = doc
            DispatchQueue.main.async {
                nombrePages   = doc.pageCount
                pageCourante  = 0
            }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinateur.pageChangee(_:)),
            name: .PDFViewPageChanged,
            object: vuePDF
        )
        return vuePDF
    }

    func updateNSView(_ vuePDF: PDFView, context: Context) {
        guard let doc  = vuePDF.document,
              let page = doc.page(at: pageCourante),
              vuePDF.currentPage != page else { return }
        vuePDF.go(to: page)
    }

    class Coordinateur: NSObject {
        var parent: VuePDFKit
        init(_ parent: VuePDFKit) { self.parent = parent }

        @objc func pageChangee(_ notification: Notification) {
            guard let vuePDF = notification.object as? PDFView,
                  let doc    = vuePDF.document,
                  let page   = vuePDF.currentPage else { return }
            DispatchQueue.main.async {
                self.parent.pageCourante = doc.index(for: page)
            }
        }
    }
}

/// Aperçu texte : lit le fichier en UTF-8 et l'affiche dans une vue défilante.
/// Fonctionne pour .txt, .swift, .py, .js, .html, .css, .md, .json, .xml, etc.
private struct ApercuFichierTexte: View {
    let url: URL
    @State private var texte: String = ""
    @State private var echec: Bool = false

    var body: some View {
        Group {
            if echec {
                ApercuFichierNonSupporte(url: url)
            } else if texte.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(texte)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { charger() }
        .onChange(of: url) { charger() }
    }

    private func charger() {
        texte = ""
        echec = false
        DispatchQueue.global(qos: .userInitiated).async {
            // Lire jusqu'à 200 Ko pour éviter de bloquer l'interface avec de gros fichiers
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                DispatchQueue.main.async { echec = true }
                return
            }
            let data = handle.readData(ofLength: 200_000)
            handle.closeFile()
            let resultat = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1)
            DispatchQueue.main.async {
                if let resultat { texte = resultat } else { echec = true }
            }
        }
    }
}

/// Aperçu d'image (png, jpg, gif, webp, tiff, heic…)
private struct ApercuFichierImage: View {
    let url: URL
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = NSImage(contentsOf: url)
                DispatchQueue.main.async { image = img }
            }
        }
    }
}

/// NSView custom avec AVPlayerLayer en couche directe — aucun fond noir possible.
/// Contrairement à AVPlayerView, on contrôle exactement ce qui est dessiné.
private final class NSVuePlayerCouche: NSView {
    let couchePlayer: AVPlayerLayer

    init(lecteur: AVPlayer) {
        couchePlayer = AVPlayerLayer(player: lecteur)
        couchePlayer.videoGravity = .resizeAspect
        couchePlayer.backgroundColor = .clear
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.addSublayer(couchePlayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        couchePlayer.frame = bounds
        CATransaction.commit()
    }
}

/// Lecteur AVPlayer encapsulé dans NSViewRepresentable via couche directe.
/// Fond 100 % transparent : pas de bandes noires, pas de zoom.
private struct VueAVPlayer: NSViewRepresentable {
    let lecteur: AVPlayer

    func makeNSView(context: Context) -> NSVuePlayerCouche {
        NSVuePlayerCouche(lecteur: lecteur)
    }

    func updateNSView(_ vue: NSVuePlayerCouche, context: Context) {
        if vue.couchePlayer.player !== lecteur {
            vue.couchePlayer.player = lecteur
        }
    }
}

/// Aperçu vidéo : miniature (frame extraite à la taille de l'aperçu) + icône play.
/// Un clic lance la vidéo directement dans la vue via AVPlayer — pas de fenêtre externe.
private struct ApercuFichierVideo: View {
    let url: URL
    @State private var image: NSImage? = nil
    @State private var lecteur: AVPlayer? = nil
    @State private var videoPreteAfficher = false   // true dès la 1ère frame rendue
    @State private var estSilence = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Miniature en fond permanent ───────────────────────────────
                // Visible jusqu'à ce que la vidéo ait rendu sa 1ère frame réelle
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: geo.size.width, height: geo.size.height)
                    ProgressView()
                }

                // ── Lecteur — visible seulement après la 1ère frame ───────────
                if let lect = lecteur {
                    VueAVPlayer(lecteur: lect)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(videoPreteAfficher ? 1 : 0)
                }

                // ── Icône play (uniquement hors lecture) ──────────────────────
                if lecteur == nil {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                }

                // ── Bouton mute/unmute (visible uniquement pendant la lecture) ─
                if lecteur != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                if let lect = lecteur {
                                    lect.isMuted.toggle()
                                    estSilence.toggle()
                                }
                            } label: {
                                Image(systemName: estSilence ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(.black.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onTapGesture {
                if lecteur == nil {
                    let lect = AVPlayer(url: url)
                    lecteur = lect
                    lect.play()
                    // Afficher le player dès qu'il commence vraiment à jouer
                    observerPremiereLecture(lect)
                } else {
                    if lecteur?.timeControlStatus == .playing {
                        lecteur?.pause()
                    } else {
                        lecteur?.play()
                    }
                }
            }
            .onAppear { charger(taille: geo.size) }
            .onChange(of: url) {
                lecteur = nil
                videoPreteAfficher = false
                charger(taille: geo.size)
            }
        }
        .padding(8)
    }

    /// Surveille timeControlStatus : dès que le player joue réellement (1ère frame affichée),
    /// on rend le lecteur visible. Sondage léger toutes les 50 ms, s'arrête dès succès.
    private func observerPremiereLecture(_ lect: AVPlayer) {
        var tentatives = 0
        func verifier() {
            guard tentatives < 40 else { return }   // timeout 2 s
            tentatives += 1
            if lect.timeControlStatus == .playing {
                DispatchQueue.main.async { videoPreteAfficher = true }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { verifier() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { verifier() }
    }

    /// Décode la miniature au plus à la taille réelle de la vue — jamais en 4K.
    private func charger(taille: CGSize) {
        guard lecteur == nil else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPx = max(taille.width, taille.height, 1) * scale
        DispatchQueue.global(qos: .userInitiated).async {
            let img = MiniatureVideoURL.extraireFramePublic(de: url, tailleMax: maxPx)
            DispatchQueue.main.async { image = img }
        }
    }
}

// MARK: - Aperçu QuickLook réel (QLPreviewView) pour docx, pages, psd, xlsx, pptx, keynote…

private struct ApercuQuickLook: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let vue = QLPreviewView(frame: .zero, style: .normal)!
        vue.autostarts  = true
        vue.shouldCloseWithWindow = false
        vue.previewItem = url as QLPreviewItem
        return vue
    }

    func updateNSView(_ vue: QLPreviewView, context: Context) {
        if vue.previewItem as? URL != url {
            vue.previewItem = url as QLPreviewItem
        }
    }
}

// MARK: - Contenu d'une archive (zip / tar / gz / 7z…)

private struct ApercuArchive: View {
    let url: URL
    @State private var entrees: [String] = []
    @State private var tronque: Bool = false
    @State private var echec: Bool = false

    var body: some View {
        Group {
            if echec {
                ApercuFichierNonSupporte(url: url)
            } else if entrees.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // En-tête
                    HStack(spacing: 8) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.52, green: 0.34, blue: 0.20))
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(url.pathExtension.uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 0.52, green: 0.34, blue: 0.20).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(Color(red: 0.52, green: 0.34, blue: 0.20))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)

                    Divider().opacity(0.3)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(entrees, id: \.self) { entree in
                                HStack(spacing: 7) {
                                    Image(systemName: entree.hasSuffix("/") ? "folder.fill" : iconeEntreeArchive(entree))
                                        .font(.system(size: 11))
                                        .foregroundStyle(couleurEntreeArchive(entree))
                                        .frame(width: 16)
                                    Text(entree)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 3)
                            }
                            if tronque {
                                Text("…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14).padding(.bottom, 6)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .onAppear { listerContenu() }
        .onChange(of: url) { listerContenu() }
    }

    private func listerContenu() {
        entrees = []; echec = false; tronque = false
        let ext = url.pathExtension.lowercased()
        DispatchQueue.global(qos: .userInitiated).async {
            var lignes: [String] = []
            var coupe = false

            // ZIP et formats compatibles unzip
            if ["zip","docx","xlsx","pptx","pages","numbers","key","jar","ipa","apk","odt"].contains(ext) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                task.arguments = ["-l", url.path]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                try? task.run(); task.waitUntilExit()
                let sortie = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                lignes = sortie.components(separatedBy: "\n")
                    .dropFirst(3).dropLast(2)          // supprimer l'en-tête et le total
                    .compactMap { ligne -> String? in
                        let cols = ligne.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
                        guard cols.count >= 4 else { return nil }
                        return String(cols[3])
                    }
            }
            // TAR / GZ / BZ2 / XZ / TGZ
            else if ["tar","gz","tgz","bz2","xz"].contains(ext) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                var args = ["-tf", url.path]
                if ext == "gz" || ext == "tgz" { args.insert("-z", at: 0) }
                else if ext == "bz2"           { args.insert("-j", at: 0) }
                else if ext == "xz"            { args.insert("-J", at: 0) }
                task.arguments = args
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                try? task.run(); task.waitUntilExit()
                lignes = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                    .components(separatedBy: "\n").filter { !$0.isEmpty }
            }
            // 7z / RAR
            else if ["7z","rar"].contains(ext) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/local/bin/7z")
                    .existingOrNil() ?? URL(fileURLWithPath: "/opt/homebrew/bin/7z")
                task.arguments = ["l", url.path]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                try? task.run(); task.waitUntilExit()
                let sortie = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                lignes = sortie.components(separatedBy: "\n")
                    .compactMap { ligne -> String? in
                        let cols = ligne.split(separator: " ", omittingEmptySubsequences: true)
                        guard cols.count >= 5, ligne.contains("-") || ligne.contains("D") else { return nil }
                        return cols.dropFirst(4).joined(separator: " ")
                    }
            }

            if lignes.count > 200 { coupe = true; lignes = Array(lignes.prefix(200)) }
            if lignes.isEmpty { DispatchQueue.main.async { echec = true }; return }
            DispatchQueue.main.async { entrees = lignes; tronque = coupe }
        }
    }

    private func iconeEntreeArchive(_ nom: String) -> String {
        if nom.hasSuffix("/") { return "folder.fill" }
        let ext = (nom as NSString).pathExtension.lowercased()
        switch ext {
        case "swift","py","js","ts","rb","go","rs","kt","java","c","cpp","h","m": return "chevron.left.forwardslash.chevron.right"
        case "png","jpg","jpeg","gif","webp","tiff","heic","svg":                  return "photo"
        case "mp4","mov","avi","mkv":                                              return "film"
        case "mp3","aac","wav","flac","m4a":                                       return "music.note"
        case "pdf":                                                                 return "doc.richtext"
        case "json","yaml","yml","xml","toml":                                     return "curlybraces"
        case "txt","md","markdown":                                                return "doc.plaintext"
        case "zip","gz","tar","7z","rar":                                          return "archivebox"
        default:                                                                   return "doc"
        }
    }

    private func couleurEntreeArchive(_ nom: String) -> Color {
        if nom.hasSuffix("/") { return Color(red: 0.30, green: 0.60, blue: 0.95) }
        let ext = (nom as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                              return Color(red: 0.20, green: 0.78, blue: 0.35)
        case "png","jpg","jpeg","gif","webp","heic": return Color(red: 0.75, green: 0.35, blue: 0.90)
        case "mp4","mov","avi","mkv":              return Color(red: 0.10, green: 0.45, blue: 0.90)
        case "mp3","aac","wav","m4a":              return Color(red: 0.90, green: 0.35, blue: 0.65)
        case "pdf":                                return Color(red: 0.88, green: 0.20, blue: 0.20)
        case "json","yaml","yml","xml":            return Color(red: 0.55, green: 0.20, blue: 0.90)
        default:                                   return Color.secondary
        }
    }
}

private extension URL {
    func existingOrNil() -> URL? {
        FileManager.default.fileExists(atPath: path) ? self : nil
    }
}

// MARK: - Repli : icône de fichier + nom pour les types vraiment non supportés
private struct ApercuFichierNonSupporte: View {
    let url: URL

    var body: some View {
        let ext = url.pathExtension.lowercased()
        VStack(spacing: 16) {
            VueIconeFichier(ext: ext, taille: 90, rayon: 24, taillePolice: 38)
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Text(L.fichier(ext: url.pathExtension.uppercased()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Distributeur : choisit l'aperçu adapté selon l'extension du fichier.
private struct ApercuFichier: View {
    let url: URL

    private var ext: String { url.pathExtension.lowercased() }

    private static let extensionsTexte: Set<String> = [
        "txt","md","markdown","swift","py","js","ts","jsx","tsx",
        "html","htm","css","scss","sass","less",
        "json","xml","yaml","yml","toml","ini","cfg","conf",
        "sh","bash","zsh","fish","rb","php","go","rs","kt","java","c","cpp","h","m"
    ]
    static let extensionsImage: Set<String> = [
        "png","jpg","jpeg","gif","webp","tiff","tif","bmp","heic","heif","svg"
    ]
    static let extensionsVideo: Set<String> = [
        "mp4","mov","avi","mkv","m4v","wmv","flv","webm"
    ]
    /// Formats riches affichés via QLPreviewView (aperçu réel fidèle au document).
    private static let extensionsQL: Set<String> = [
        // Apple iWork
        "pages","numbers","key",
        // Microsoft Office
        "docx","doc","xlsx","xls","pptx","ppt","odt","ods","odp","rtf",
        // Adobe
        "psd","ai","indd","eps",
        // Sketch / Figma / autres
        "sketch",
        // ePub / livres
        "epub",
        // Audio
        "mp3","aac","wav","flac","m4a","aiff","ogg"
    ]
    /// Archives dont on affiche le contenu textuellement.
    private static let extensionsArchive: Set<String> = [
        "zip","tar","gz","tgz","bz2","xz","rar","7z",
        "jar","ipa","apk"
    ]

    var body: some View {
        Group {
            if ext == "pdf" {
                ApercuPDFPages(url: url)
            } else if Self.extensionsTexte.contains(ext) {
                ApercuFichierTexte(url: url)
            } else if Self.extensionsImage.contains(ext) {
                ApercuFichierImage(url: url)
            } else if Self.extensionsVideo.contains(ext) {
                ApercuFichierVideo(url: url)
            } else if Self.extensionsQL.contains(ext) {
                ApercuQuickLook(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if Self.extensionsArchive.contains(ext) {
                ApercuArchive(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ApercuFichierNonSupporte(url: url)
            }
        }
    }
}


// MARK: - Helper icône + couleur par type de fichier

/// Représentation d'une icône de fichier : soit un SF Symbol, soit un badge texte coloré (style Adobe).
enum IconeFichier {
    case symbole(String, Color)
    case badge(String, couleurFond: Color, couleurTexte: Color)
}

private func iconeFichier(ext: String) -> IconeFichier {
    switch ext {

    // ── PDF ──────────────────────────────────────────────────────────────────
    case "pdf":
        return .symbole("doc.richtext.fill", Color(red: 0.90, green: 0.15, blue: 0.10))

    // ── Suite Adobe ──────────────────────────────────────────────────────────
    // Photoshop — fond sombre #001E36, lettres bleu vif #31A8FF (fidèle à l'icône officielle)
    case "psd", "psb":
        return .badge("Ps", couleurFond: Color(red: 0.00, green: 0.12, blue: 0.21),
                           couleurTexte: Color(red: 0.19, green: 0.66, blue: 1.00))
    // Illustrator — fond sombre #330000, lettres orange vif #FF9A00
    case "ai":
        return .badge("Ai", couleurFond: Color(red: 0.20, green: 0.07, blue: 0.00),
                           couleurTexte: Color(red: 1.00, green: 0.60, blue: 0.00))
    // InDesign — fond sombre #49021F, lettres rose vif #FF3366
    case "indd", "indb", "indt":
        return .badge("Id", couleurFond: Color(red: 0.29, green: 0.01, blue: 0.12),
                           couleurTexte: Color(red: 1.00, green: 0.20, blue: 0.40))
    // Premiere Pro — fond sombre #00005B, lettres violet clair #9999FF
    case "prproj":
        return .badge("Pr", couleurFond: Color(red: 0.00, green: 0.00, blue: 0.36),
                           couleurTexte: Color(red: 0.60, green: 0.60, blue: 1.00))
    // After Effects — fond sombre #1A0050, lettres violet électrique #9999FF
    case "aep", "aet":
        return .badge("Ae", couleurFond: Color(red: 0.10, green: 0.00, blue: 0.31),
                           couleurTexte: Color(red: 0.60, green: 0.60, blue: 1.00))
    // XD — fond sombre #2B0040, lettres rose vif #FF61F6
    case "xd":
        return .badge("Xd", couleurFond: Color(red: 0.17, green: 0.00, blue: 0.25),
                           couleurTexte: Color(red: 1.00, green: 0.38, blue: 0.96))
    // Lightroom Classic — fond sombre #001122, lettres bleu Adobe #31A8FF
    case "lrcat", "lrtemplate", "lrsmcol":
        return .badge("Lr", couleurFond: Color(red: 0.00, green: 0.07, blue: 0.13),
                           couleurTexte: Color(red: 0.19, green: 0.66, blue: 1.00))
    // Animate — fond sombre #1A0800, lettres orange vif #ED6B25
    case "fla", "xfl":
        return .badge("An", couleurFond: Color(red: 0.10, green: 0.03, blue: 0.00),
                           couleurTexte: Color(red: 0.93, green: 0.42, blue: 0.15))
    // Audition — fond sombre #001219, lettres cyan vif #00E4BB
    case "sesx":
        return .badge("Au", couleurFond: Color(red: 0.00, green: 0.07, blue: 0.10),
                           couleurTexte: Color(red: 0.00, green: 0.89, blue: 0.73))
    // Dimension — fond sombre #001A3A, lettres bleu vif #4DAEFF
    case "dn":
        return .badge("Dn", couleurFond: Color(red: 0.00, green: 0.10, blue: 0.23),
                           couleurTexte: Color(red: 0.30, green: 0.68, blue: 1.00))

    // ── Figma ────────────────────────────────────────────────────────────────
    // Figma — violet/rose officiel
    case "fig":
        return .badge("Fig", couleurFond: Color(red: 0.65, green: 0.35, blue: 1.00),
                             couleurTexte: .white)

    // ── Sketch ───────────────────────────────────────────────────────────────
    // Sketch — jaune officiel
    case "sketch":
        return .badge("Sk", couleurFond: Color(red: 0.98, green: 0.73, blue: 0.17),
                           couleurTexte: Color(red: 0.15, green: 0.12, blue: 0.00))

    // ── Blender / 3D ─────────────────────────────────────────────────────────
    case "blend", "blend1":
        return .badge("Bl", couleurFond: Color(red: 1.00, green: 0.46, blue: 0.07),
                           couleurTexte: .white)
    case "fbx":
        return .badge("FBX", couleurFond: Color(red: 0.20, green: 0.55, blue: 0.85),
                             couleurTexte: .white)
    case "obj":
        return .badge("OBJ", couleurFond: Color(red: 0.45, green: 0.45, blue: 0.50),
                             couleurTexte: .white)
    case "stl":
        return .badge("STL", couleurFond: Color(red: 0.22, green: 0.68, blue: 0.72),
                             couleurTexte: .white)
    case "gltf", "glb":
        return .badge("glTF", couleurFond: Color(red: 0.53, green: 0.34, blue: 0.82),
                              couleurTexte: .white)

    // ── Bases de données ─────────────────────────────────────────────────────
    case "db", "sqlite", "sqlite3", "db3":
        return .symbole("cylinder.fill", Color(red: 0.40, green: 0.44, blue: 0.52))
    case "sql":
        return .badge("SQL", couleurFond: Color(red: 0.25, green: 0.48, blue: 0.72),
                             couleurTexte: .white)

    // ── Certificats / sécurité ────────────────────────────────────────────────
    case "pem", "p12", "pfx", "cer", "crt":
        return .symbole("lock.shield.fill", Color(red: 0.18, green: 0.62, blue: 0.28))

    // ── Exécutables / paquets macOS ───────────────────────────────────────────
    case "dmg":
        return .symbole("opticaldisc.fill", Color(red: 0.50, green: 0.52, blue: 0.56))
    case "pkg":
        return .symbole("shippingbox.fill", Color(red: 0.55, green: 0.38, blue: 0.18))
    case "app":
        return .symbole("app.fill", Color(red: 0.25, green: 0.50, blue: 0.92))

    // ── Livres numériques ─────────────────────────────────────────────────────
    case "epub":
        return .symbole("book.fill", Color(red: 0.15, green: 0.58, blue: 0.30))
    case "mobi", "azw", "azw3":
        return .symbole("book.closed.fill", Color(red: 0.12, green: 0.50, blue: 0.25))

    // ── CAO / plans ──────────────────────────────────────────────────────────
    case "dwg", "dxf":
        return .badge("DWG", couleurFond: Color(red: 0.20, green: 0.38, blue: 0.62),
                             couleurTexte: .white)
    case "step", "stp", "iges", "igs":
        return .badge("CAD", couleurFond: Color(red: 0.30, green: 0.45, blue: 0.65),
                             couleurTexte: .white)

    // ── Swift / code source compilé ───────────────────────────────────────────
    case "swift":
        return .symbole("swift", Color(red: 0.20, green: 0.78, blue: 0.35))
    case "c", "cpp", "h", "m", "mm":
        return .symbole("hammer.fill", Color(red: 0.18, green: 0.70, blue: 0.30))
    case "py":
        return .symbole("chevron.left.forwardslash.chevron.right", Color(red: 0.22, green: 0.72, blue: 0.38))
    case "js", "ts", "jsx", "tsx":
        return .symbole("function", Color(red: 0.25, green: 0.75, blue: 0.40))
    case "go":
        return .symbole("arrow.trianglehead.2.counterclockwise.rotate.90", Color(red: 0.20, green: 0.76, blue: 0.65))
    case "rs":
        return .symbole("gear.badge", Color(red: 0.62, green: 0.35, blue: 0.10))
    case "kt", "kts":
        return .symbole("k.circle.fill", Color(red: 0.45, green: 0.20, blue: 0.85))
    case "java":
        return .symbole("cup.and.heat.waves.fill", Color(red: 0.80, green: 0.30, blue: 0.10))
    case "rb":
        return .symbole("diamond.fill", Color(red: 0.85, green: 0.15, blue: 0.15))
    case "php":
        return .symbole("p.circle.fill", Color(red: 0.44, green: 0.46, blue: 0.80))
    case "dart":
        return .badge("Dt", couleurFond: Color(red: 0.00, green: 0.57, blue: 0.80),
                          couleurTexte: .white)
    case "lua":
        return .badge("Lua", couleurFond: Color(red: 0.18, green: 0.20, blue: 0.55),
                             couleurTexte: .white)
    case "r", "rmd":
        return .badge("R", couleurFond: Color(red: 0.27, green: 0.48, blue: 0.72),
                         couleurTexte: .white)

    // ── HTML / CSS ────────────────────────────────────────────────────────────
    case "html", "htm":
        return .symbole("globe", Color(red: 0.95, green: 0.45, blue: 0.05))
    case "css", "scss", "sass", "less":
        return .symbole("paintpalette.fill", Color(red: 0.95, green: 0.38, blue: 0.05))

    // ── JSON / YAML / config ─────────────────────────────────────────────────
    case "json":
        return .symbole("curlybraces", Color(red: 0.55, green: 0.20, blue: 0.90))
    case "yaml", "yml":
        return .symbole("list.bullet.indent", Color(red: 0.50, green: 0.18, blue: 0.85))
    case "toml", "ini", "cfg", "conf":
        return .symbole("gearshape.fill", Color(red: 0.48, green: 0.18, blue: 0.80))

    // ── Shell / scripts ───────────────────────────────────────────────────────
    case "sh", "bash", "zsh", "fish":
        return .symbole("terminal.fill", Color(red: 0.45, green: 0.48, blue: 0.52))

    // ── Archives ─────────────────────────────────────────────────────────────
    case "zip", "tar", "gz", "bz2", "xz", "rar", "7z":
        return .symbole("archivebox.fill", Color(red: 0.52, green: 0.34, blue: 0.20))

    // ── Vidéo ─────────────────────────────────────────────────────────────────
    case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm":
        return .symbole("film.fill", Color(red: 0.10, green: 0.45, blue: 0.90))

    // ── Audio ─────────────────────────────────────────────────────────────────
    case "mp3", "aac", "wav", "flac", "ogg", "m4a", "aiff":
        return .symbole("music.note", Color(red: 0.90, green: 0.35, blue: 0.65))

    // ── Tableur / Excel ───────────────────────────────────────────────────────
    case "xlsx", "xls", "csv", "numbers":
        return .symbole("tablecells.fill", Color(red: 0.10, green: 0.52, blue: 0.22))

    // ── Traitement de texte / Word ────────────────────────────────────────────
    case "docx", "doc", "rtf", "odt":
        return .symbole("doc.text.fill", Color(red: 0.10, green: 0.28, blue: 0.72))

    // ── Pages (Apple) ─────────────────────────────────────────────────────────
    case "pages":
        return .symbole("doc.richtext", Color(red: 0.85, green: 0.70, blue: 0.05))

    // ── PowerPoint / Keynote ──────────────────────────────────────────────────
    case "pptx", "ppt":
        return .symbole("rectangle.on.rectangle.angled.fill", Color(red: 0.88, green: 0.30, blue: 0.05))

    // ── Keynote (Apple) ───────────────────────────────────────────────────────
    case "key":
        return .symbole("rectangle.on.rectangle.angled.fill", Color(red: 0.10, green: 0.46, blue: 0.95))

    // ── Texte brut / Markdown ─────────────────────────────────────────────────
    case "txt":
        return .symbole("doc.plaintext.fill", Color(red: 0.40, green: 0.44, blue: 0.50))
    case "md", "markdown":
        return .symbole("doc.text", Color(red: 0.40, green: 0.44, blue: 0.50))

    // ── XML / SVG ─────────────────────────────────────────────────────────────
    case "xml":
        return .symbole("angle.left.and.angle.right.and.dot.point", Color(red: 0.55, green: 0.22, blue: 0.88))
    case "svg":
        return .symbole("skew", Color(red: 0.95, green: 0.42, blue: 0.05))

    // ── Polices ───────────────────────────────────────────────────────────────
    case "ttf", "otf", "woff", "woff2":
        return .symbole("textformat", Color(red: 0.60, green: 0.30, blue: 0.80))

    // ── Repli ─────────────────────────────────────────────────────────────────
    default:
        return .symbole("doc.fill", Color(red: 0.40, green: 0.44, blue: 0.50))
    }
}

/// Compatibilité : retourne (sfSymbol, couleur) pour les anciens appels.
/// Les badges utilisent un symbole générique ; la vue `VueIconeFichier` gère le rendu complet.
private func iconeEtCouleurFichier(ext: String) -> (String, Color) {
    switch iconeFichier(ext: ext) {
    case .symbole(let s, let c): return (s, c)
    case .badge(_, let fond, _): return ("doc.fill", fond)
    }
}

// MARK: - Vue d'icône fichier unifiée (symbole ou badge)

/// Remplace le ZStack inline dans LigneElementPressePapier et ApercuFichierNonSupporte.
private struct VueIconeFichier: View {
    let ext: String
    /// Taille du conteneur carré (ex: 36 pour liste, 90 pour aperçu).
    let taille: CGFloat
    /// Rayon des coins (ex: 20 pour liste, 24 pour aperçu).
    let rayon: CGFloat
    /// Taille de la police de l'icône (ex: 15 pour liste, 38 pour aperçu).
    let taillePolice: CGFloat
    /// Si true, fond plus opaque + texte blanc (état sélectionné dans la liste).
    var estSelectionne: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// En mode clair les couleurs vives sur fond blanc deviennent invisibles à 0.18 d'opacité ;
    /// on remonte l'opacité du fond et on assombrit l'icône avec un multiplicateur.
    private var estClair: Bool { colorScheme == .light }

    /// Opacité du fond du symbole : plus forte en mode clair pour compenser le fond blanc.
    private var opaciteFondSymbole: Double {
        if estSelectionne { return 0.40 }
        return estClair ? 0.16 : 0.18
    }

    /// La couleur de l'icône est assombrie en mode clair (×0.65 sur chaque composante)
    /// pour rester lisible sur fond blanc.
    private func couleurAdaptee(_ couleur: Color) -> Color {
        guard estClair, !estSelectionne else { return couleur }
        guard let components = NSColor(couleur).usingColorSpace(.sRGB) else { return couleur }
        return Color(
            red:   components.redComponent   * 0.62,
            green: components.greenComponent * 0.62,
            blue:  components.blueComponent  * 0.62
        )
    }

    var body: some View {
        let icone = iconeFichier(ext: ext)
        ZStack {
            switch icone {
            case .symbole(let nom, let couleur):
                let c = couleurAdaptee(couleur)
                RoundedRectangle(cornerRadius: rayon)
                    .fill(c.opacity(opaciteFondSymbole))
                Image(systemName: nom)
                    .font(.system(size: taillePolice, weight: .medium))
                    .foregroundStyle(estSelectionne ? .white : c)

            case .badge(let texte, let fond, let couleurTexte):
                // Les badges ont déjà un fond sombre opaque : on les laisse tels quels.
                RoundedRectangle(cornerRadius: rayon)
                    .fill(fond.opacity(estSelectionne ? 0.85 : 0.92))
                Text(texte)
                    .font(.system(size: taillePolice * 0.72, weight: .bold, design: .rounded))
                    .foregroundStyle(estSelectionne ? .white : couleurTexte)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: taille, height: taille)
    }
}

// MARK: - Miniature URL fichier image

private struct MiniatureFichierURL: View {
    let url: URL
    let chargerImmediatement: Bool

    // Cache partagé entre toutes les instances
    private static let cache = NSCache<NSURL, NSImage>()

    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.2)
                    .overlay(chargerImmediatement ? AnyView(ProgressView().scaleEffect(0.5)) : AnyView(EmptyView()))
            }
        }
        .onAppear { if chargerImmediatement { charger() } }
        .onChange(of: chargerImmediatement) { if chargerImmediatement { charger() } }
    }

    private func charger() {
        guard image == nil else { return }
        // Vérifier le cache d'abord
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = NSImage(contentsOf: url) else { return }
            Self.cache.setObject(img, forKey: url as NSURL)
            DispatchQueue.main.async { image = img }
        }
    }
}

// MARK: - Miniature vidéo (AVFoundation, lazy + cache partagé)

private struct MiniatureVideoURL: View {
    let url: URL
    let chargerImmediatement: Bool

    // Cache partagé entre toutes les instances — même pattern que MiniatureFichierURL
    private static let cache = NSCache<NSURL, NSImage>()

    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.2)
                    if chargerImmediatement {
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
        }
        .onAppear { if chargerImmediatement { charger() } }
        .onChange(of: chargerImmediatement) { if chargerImmediatement { charger() } }
    }

    private func charger() {
        guard image == nil else { return }
        // Cache en premier — aucun travail si déjà extrait
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached; return
        }
        DispatchQueue.global(qos: .utility).async {
            guard let img = MiniatureVideoURL.extraireFrame(de: url) else { return }
            Self.cache.setObject(img, forKey: url as NSURL)
            DispatchQueue.main.async { image = img }
        }
    }

    /// Extrait la première frame exploitable (à t = 0.5 s ou t = 0 si fichier court).
    /// Toute la charge est sur un background thread — jamais sur le main thread.
    /// `tailleMax` : dimension maximale du côté le plus long en pixels physiques.
    /// Passer 120 pour les miniatures de liste, la vraie taille de vue pour l'aperçu.
    /// AVAssetImageGenerator ne décodera jamais plus de pixels que nécessaire.
    static func extraireFramePublic(de url: URL, tailleMax: CGFloat = 120) -> NSImage? {
        extraireFrame(de: url, tailleMax: tailleMax)
    }

    private static func extraireFrame(de url: URL, tailleMax: CGFloat = 120) -> NSImage? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true   // respecte la rotation de la vidéo
        // Limiter le décodage à la taille réelle de la vue — jamais en pleine résolution.
        // Une vidéo 4K dans une fenêtre de 400 px sera décodée en 400 px max, pas en 4K.
        let cap = max(tailleMax, 1)
        gen.maximumSize = CGSize(width: cap, height: cap)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 1, preferredTimescale: 600)
        let temps = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImg = try? gen.copyCGImage(at: temps, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImg, size: .zero)
    }
}

// MARK: - Ligne d'élément

struct LigneElementPressePapier: View {
    let element: ElementPressePapier
    let estSelectionne: Bool
    var indexSequence: Int? = nil
    var chargerMiniature: Bool = true
    let surTap: () -> Void
    let surDoubleTap: () -> Void

    @State private var estSurvole = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if case .image(let img) = element.contenu {
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else if case .texte = element.contenu, let couleur = element.couleurCachee {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(couleur)
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                } else if case .urlFichier(let url) = element.contenu {
                    let ext = url.pathExtension.lowercased()
                    let estImageFichier = ApercuFichier.extensionsImage.contains(ext)
                    let estVideoFichier = ApercuFichier.extensionsVideo.contains(ext)
                    if estImageFichier {
                        MiniatureFichierURL(url: url, chargerImmediatement: chargerMiniature)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else if estVideoFichier {
                        MiniatureVideoURL(url: url, chargerImmediatement: chargerMiniature)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        VueIconeFichier(ext: ext, taille: 36, rayon: 20, taillePolice: 15,
                                        estSelectionne: estSelectionne)
                    }
                } else if case .texte(let t) = element.contenu, t.hasPrefix("http") || t.hasPrefix("www") {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.blue.opacity(estSelectionne ? 0.4 : 0.2))
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(estSelectionne ? .white : Color.blue)
                    }
                    .frame(width: 36, height: 36)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(element.couleurType.opacity(estSelectionne ? 0.4 : 0.2))
                        Image(systemName: element.iconeType)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(estSelectionne ? .white : element.couleurType)
                    }
                    .frame(width: 36, height: 36)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(element.titreAffiche)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .foregroundStyle(estSelectionne ? .white : .primary)
                Group {
                    if case .urlFichier(let url) = element.contenu, !url.pathExtension.isEmpty {
                        Text(url.pathExtension.uppercased())
                    } else if case .texte = element.contenu, element.couleurCachee != nil {
                        Text(L.couleur)
                    } else {
                        Text(element.labelType)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(estSelectionne ? .white.opacity(0.7) : .secondary)
            }
            Spacer()
            if let idx = indexSequence {
                ZStack {
                    Circle().fill(Color.accentAttenuation).frame(width: 18, height: 18)
                    Text("\(idx)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(
                estSelectionne ? Color.accentAttenuation :
                estSurvole  ? Color.primary.opacity(0.07) : Color.clear
            )
        )
        .contentShape(Rectangle())
        .onHover { estSurvole = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { surDoubleTap() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { surTap() })
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: element.estEpingle)
    }
}

// MARK: - Logique bouton « confirmé » partagée

private struct BoutonConfirme<Etiquette: View>: View {
    let texteAide: String
    let action: () -> Void
    @ViewBuilder let etiquette: (Bool) -> Etiquette

    @State private var afficherConfirme = false

    var body: some View {
        Button {
            guard !afficherConfirme else { return }
            action()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { afficherConfirme = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { afficherConfirme = false }
            }
        } label: {
            etiquette(afficherConfirme)
        }
        .buttonStyle(.plain)
        .help(texteAide)
        .disabled(afficherConfirme)
    }
}

// MARK: - Boutons d'action

private struct BoutonActionAnime: View {
    let titre: String
    let icone: String?
    let texteAide: String
    let pleineLargeur: Bool
    let action: () -> Void

    @State private var estSurvole = false

    var body: some View {
        BoutonConfirme(texteAide: texteAide, action: action) { confirme in
            ZStack {
                // Contenu visible : icône seule en mode confirmé, icône + texte sinon
                if confirme {
                    Image(systemName: "checkmark.circle.fill")
                        .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        if let icone { Image(systemName: icone) }
                        if !titre.isEmpty { Text(titre) }
                    }
                    .transition(.opacity)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            // Hauteur fixe identique à BoutonSauvegardeImage pour éviter tout décalage layout
            .frame(maxWidth: pleineLargeur ? .infinity : nil, minHeight: 34, maxHeight: 34)
            .padding(.horizontal, pleineLargeur ? 0 : 12)
            .background(
                confirme ? Color.green : (estSurvole ? Color.accentAttenuation.opacity(0.75) : Color.accentAttenuation),
                in: RoundedRectangle(cornerRadius: 26)
            )
        }
        .onHover { estSurvole = $0 }
    }
}

private struct BoutonIconeSurvol: View {
    let symbole: String
    let couleur: Color
    let texteAide: String
    let action: () -> Void

    @State private var estSurvole = false
    @State private var estPresse  = false

    // Rouge si la couleur passée est rouge (bouton supprimer)
    private var estRouge: Bool { couleur == .red }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) { estPresse = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { estPresse = false }
            }
        } label: {
            Image(systemName: symbole)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(estRouge
                    ? Color.red
                    : (estSurvole ? Color.accentColor : Color.secondary))
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 26).fill(estRouge
                        ? (estSurvole ? Color.red.opacity(0.15) : Color.primary.opacity(0.06))
                        : (estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)
        }
        .buttonStyle(.plain)
        .help(texteAide)
        .onHover { estSurvole = $0 }
    }
}

// MARK: - Bouton épingle d'un élément (avec animation d'épinglage)

private struct BoutonEpingleElement: View {
    let estEpingle: Bool
    let action: () -> Void

    @State private var estSurvole = false
    @State private var estPresse  = false
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1

    init(estEpingle: Bool, action: @escaping () -> Void) {
        self.estEpingle = estEpingle
        self.action = action
        self._rotation = State(initialValue: estEpingle ? 45 : 0)
    }

    var body: some View {
        Button {
            let versEpingle = !estEpingle
            if versEpingle {
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 14)) {
                    rotation = 45
                    scale = 1.25
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { scale = 1.0 }
                }
            } else {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    rotation = 0
                    scale = 0.85
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { scale = 1.0 }
                }
            }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) { estPresse = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { estPresse = false }
            }
        } label: {
            Image(systemName: estEpingle ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(estEpingle ? Color.accentColor : (estSurvole ? Color.accentColor : Color.secondary))
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 26).fill(estEpingle
                        ? Color.accentColor.opacity(0.15)
                        : (estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)

                .animation(.interpolatingSpring(stiffness: 280, damping: 14), value: scale)
        }
        .buttonStyle(.plain)
        .help(estEpingle ? L.epingler : L.epingler)
        .onHover { estSurvole = $0 }
        .onChange(of: estEpingle) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                rotation = estEpingle ? 45 : 0
            }
        }
    }
}

// MARK: - Bouton de sauvegarde d'image

private struct BoutonSauvegardeImage: View {
    let image: NSImage
    @State private var estSurvole = false

    var body: some View {
        BoutonConfirme(texteAide: "Enregistrer l'image sur le Bureau", action: sauvegarderSurBureau) { confirme in
            Group {
                if confirme {
                    Image(systemName: "checkmark.circle.fill").transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(confirme ? .white : (estSurvole ? Color.accentColor : Color.secondary))
            .frame(width: 36, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 26).fill(confirme
                    ? Color.green
                    : (estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
            )
            
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)
        }
        .onHover { estSurvole = $0 }
    }

    private func sauvegarderSurBureau() {
        guard let data = donneesPNG(depuis: image) else { return }
        let bureau   = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let nomFich  = "PressePapiers_\(DateFormatter.heureSeule.string(from: Date())).png"
        try? data.write(to: bureau.appendingPathComponent(nomFich))
    }
}

// MARK: - Bouton de sauvegarde de fichier (URL → Bureau)

private struct BoutonSauvegardeFichier: View {
    let url: URL
    @State private var estSurvole = false

    var body: some View {
        BoutonConfirme(texteAide: "Enregistrer le fichier sur le Bureau", action: sauvegarderSurBureau) { confirme in
            Group {
                if confirme {
                    Image(systemName: "checkmark.circle.fill").transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(confirme ? .white : (estSurvole ? Color.accentColor : Color.secondary))
            .frame(width: 36, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 26).fill(confirme
                    ? Color.green
                    : (estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
            )
            
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)
        }
        .onHover { estSurvole = $0 }
    }

    private func sauvegarderSurBureau() {
        let bureau = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let destination = bureau.appendingPathComponent(url.lastPathComponent)
        var dest = destination
        var compteur = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let nom = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            dest = bureau.appendingPathComponent("\(nom) \(compteur).\(ext)")
            compteur += 1
        }
        try? FileManager.default.copyItem(at: url, to: dest)
    }
}



// IcôneApplication supprimée — remplacée par le nom texte seul

private struct ControleFiltreSegmente: View {
    let filtres: [FiltrePressePapier]
    @Binding var filtreActif: FiltrePressePapier
    var iconesSeulement: Bool = false

    var body: some View {
        GeometryReader { geo in
            let nombre = CGFloat(filtres.count)
            let idx    = CGFloat(filtres.firstIndex(of: filtreActif) ?? 0)
            let l = geo.size.width / nombre
            let h = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .frame(width: l, height: h)
                    .offset(x: idx * l)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: filtreActif)

                HStack(spacing: 0) {
                    ForEach(filtres, id: \.self) { filtre in
                        BoutonSegment(filtre: filtre, estActif: filtreActif == filtre, largeur: l, hauteur: h, iconesSeulement: iconesSeulement) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { filtreActif = filtre }
                        }
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

private struct BoutonSegment: View {
    let filtre: FiltrePressePapier
    let estActif: Bool
    let largeur: CGFloat
    let hauteur: CGFloat
    var iconesSeulement: Bool = false
    let action: () -> Void

    @State private var estSurvole = false

    var body: some View {
        Button(action: action) {
            Group {
                if iconesSeulement {
                    Image(systemName: filtre.icone)
                        .font(.system(size: 10, weight: .medium))
                } else if estActif {
                    Text(filtre.etiquette)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .center)))
                } else {
                    Image(systemName: filtre.icone)
                        .font(.system(size: 10, weight: .medium))
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .center)))
                }
            }
            .foregroundStyle(estActif ? .primary : (estSurvole ? .primary : .secondary))
            .padding(.horizontal, 6)
            .frame(width: largeur, height: hauteur)
            .background(
                estSurvole && !estActif
                    ? RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(0.06))
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { estSurvole = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: estActif)
    }
}

// MARK: - CGEvent tap partagé (bloquant, niveau session)
//
// Pourquoi CGEvent tap et pas LocalMonitor / GlobalMonitor ?
// • .nonactivatingPanel rend makeKey() inopérant → LocalMonitor ne reçoit rien.
// • GlobalMonitor reçoit les touches mais ne peut pas les bloquer : elles
//   arrivent aussi à l'app en arrière-plan (double-frappe).
// • CGEvent tap opère en amont de toute distribution fenêtre. Retourner nil
//   dans le callback supprime définitivement l'événement — même avec
//   .nonactivatingPanel, et indépendamment de quelle fenêtre est keyWindow.
//   C'est le même mécanisme utilisé pour le raccourci d'ouverture.

private enum TapClavierActif {
    /// Installe un CGEvent tap bloquant pour les keyDown.
    /// - parameter handler: appelé sur le thread principal avec l'NSEvent correspondant.
    /// - returns: opaque wrapper à passer à `retirer(_:)` pour nettoyer.
    static func installer(handler: @escaping (NSEvent) -> Void) -> CFMachPort? {
        let masque = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // On stocke le handler dans une box pour le passer via refcon (UnsafeMutableRawPointer).
        let box = HandlerBox(handler)
        let refcon = Unmanaged.passRetained(box).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: masque,
            callback: { _, _, cgEvent, refcon -> Unmanaged<CGEvent>? in
                guard let refcon,
                      let nsEvent = NSEvent(cgEvent: cgEvent) else {
                    return Unmanaged.passRetained(cgEvent)
                }
                let box = Unmanaged<HandlerBox>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async { box.handler(nsEvent) }
                return nil   // bloque l'événement — il n'atteint aucune autre fenêtre
            },
            userInfo: refcon
        ) else {
            Unmanaged<HandlerBox>.fromOpaque(refcon).release()
            return nil
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    /// Désactive et libère le tap retourné par `installer`.
    static func retirer(_ tap: CFMachPort?) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    // Box pour transporter le closure Swift à travers le refcon C.
    private final class HandlerBox {
        let handler: (NSEvent) -> Void
        init(_ h: @escaping (NSEvent) -> Void) { handler = h }
    }
}

// MARK: - Bouton recherche

private struct BoutonRecherche: View {
    let action: () -> Void
    @State private var estSurvole = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(estSurvole ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                )
                
        }
        .buttonStyle(.plain)
        .onHover { estSurvole = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)
    }
}

// MARK: - Champ de recherche inline (remplace les filtres)

private struct ChampRechercheInline: View {
    @Binding var texte: String
    @Binding var actif: Bool

    @State private var curseurVisible = true
    @State private var timerCurseur: Timer? = nil
    @State private var moniteurClavier: CFMachPort? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                if texte.isEmpty {
                    Text(S("Rechercher…", "Search…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 0) {
                    Text(texte)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1.5, height: 14)
                        .opacity(curseurVisible ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Croix vide le texte si du texte est écrit, sinon ferme le champ
            Button {
                if texte.isEmpty { fermer() } else { texte = "" }
            } label: {
                Image(systemName: texte.isEmpty ? "xmark" : "xmark.circle.fill")
                    .font(.system(size: texte.isEmpty ? 10 : 12, weight: texte.isEmpty ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.08)))
        .frame(maxWidth: .infinity)
        .onAppear { installerMoniteur() }
        .onDisappear { retirerMoniteur() }
    }

    private func fermer() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            texte = ""
            actif = false
        }
    }

    private func installerMoniteur() {
        curseurVisible = true
        timerCurseur = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async { curseurVisible.toggle() }
        }

        // CGEvent tap bloquant : intercepte les keyDown en amont de toute distribution.
        // Retourner nil dans le callback bloque l'événement — il n'atteint pas l'app en fond.
        // C'est la seule solution fiable avec .nonactivatingPanel :
        //   • LocalMonitor ne reçoit rien car makeKey() est inopérant sur .nonactivatingPanel.
        //   • GlobalMonitor reçoit les touches mais ne peut pas les bloquer (double-frappe).
        moniteurClavier = TapClavierActif.installer(handler: { event in
            traiterEvenement(event)
        })
    }

    private func retirerMoniteur() {
        timerCurseur?.invalidate()
        timerCurseur = nil
        TapClavierActif.retirer(moniteurClavier)
        moniteurClavier = nil
    }

    private func traiterEvenement(_ event: NSEvent) {
        if event.keyCode == 53 { fermer(); return }
        if event.keyCode == 51 { if !texte.isEmpty { texte = String(texte.dropLast()) }; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.intersection([.command, .control, .option]).isEmpty { return }
        if let chars = event.characters {
            let filtrés = chars.filter { !$0.isNewline && $0 != "\t" && $0.asciiValue ?? 0 >= 32 }
            if !filtrés.isEmpty { texte += filtrés }
        }
    }
}

// MARK: - Bouton de réinitialisation

private struct BoutonReinitialisation: View {
    let action: () -> Void
    @State private var estSurvole = false
    @State private var rotation: Double = 0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { rotation -= 360 }
            action()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.red)
                .rotationEffect(.degrees(rotation))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(estSurvole ? Color.red.opacity(0.15) : Color.primary.opacity(0.06))
                )
                
        }
        .buttonStyle(.plain)
        .help(L.effacerHisto)
        .onHover { estSurvole = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)
    }
}

// MARK: - Pipette (sélecteur de couleur à l'écran)

/// Construit un curseur correspondant à la maquette de référence :
/// - Anneau coloré épais (extérieur) montrant la couleur détectée
/// - Intérieur semi-transparent sombre (20 % noir) pour voir le contenu en dessous
/// - Petit réticule propre au centre
private func creerCurseurLoupe(couleur: NSColor?) -> NSCursor {
    // Taille totale du canevas (en points). Les curseurs macOS sont rendus à 2× sur Retina.
    let taille: CGFloat = 52
    let echelle: CGFloat = 2          // échelle Retina explicite pour un rendu net
    let taillePixels = taille * echelle

    let repBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(taillePixels),
        pixelsHigh: Int(taillePixels),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: repBitmap)!
    ctx.cgContext.scaleBy(x: echelle, y: echelle)
    NSGraphicsContext.current = ctx

    let cg  = ctx.cgContext
    let cx  = taille / 2
    let cy  = taille / 2

    // ── Dimensions ───────────────────────────────────────────────
    let anneauExterieur: CGFloat = 24   // bord extérieur de l'anneau coloré
    let anneauInterieur: CGFloat = 16   // bord intérieur de l'anneau / extérieur de la zone sombre
    let reticuleDemo:    CGFloat = 4    // demi-longueur de chaque bras du réticule
    let reticulEcart:    CGFloat = 2    // espace entre le bras et le centre

    // ── 1. Anneau coloré (couleur détectée, opacité pleine) ──────
    let couleurAnneau = (couleur ?? NSColor(white: 0.75, alpha: 1))
        .usingColorSpace(.sRGB) ?? NSColor(white: 0.75, alpha: 1)

    // Dessiner un cercle plein puis découper le cercle intérieur
    cg.setFillColor(couleurAnneau.cgColor)
    cg.addArc(center: CGPoint(x: cx, y: cy),
              radius: anneauExterieur, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.fillPath()

    // ── 2. Fine bordure sombre autour de l'anneau pour le contraste ──
    cg.setStrokeColor(NSColor.black.withAlphaComponent(0.40).cgColor)
    cg.setLineWidth(1.0)
    // Bord extérieur
    cg.addArc(center: CGPoint(x: cx, y: cy),
              radius: anneauExterieur - 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()
    // Bord intérieur de l'anneau
    cg.addArc(center: CGPoint(x: cx, y: cy),
              radius: anneauInterieur + 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    // ── 3. Intérieur entièrement transparent — percer un vrai trou avec le mode clear ──
    cg.setBlendMode(.clear)
    cg.addArc(center: CGPoint(x: cx, y: cy),
              radius: anneauInterieur, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.fillPath()
    cg.setBlendMode(.normal)

    // ── 4. Petit réticule dans la zone sombre ────────────────────
    // Blanc avec légère ombre pour lisibilité sur tout fond
    let couleurReticule = NSColor.white.withAlphaComponent(0.90).cgColor
    cg.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.setLineWidth(2.5)   // passe d'ombre
    // Horizontal
    cg.move(to: CGPoint(x: cx - reticuleDemo - reticulEcart, y: cy))
    cg.addLine(to: CGPoint(x: cx - reticulEcart, y: cy))
    cg.move(to: CGPoint(x: cx + reticulEcart, y: cy))
    cg.addLine(to: CGPoint(x: cx + reticuleDemo + reticulEcart, y: cy))
    // Vertical
    cg.move(to: CGPoint(x: cx, y: cy - reticuleDemo - reticulEcart))
    cg.addLine(to: CGPoint(x: cx, y: cy - reticulEcart))
    cg.move(to: CGPoint(x: cx, y: cy + reticulEcart))
    cg.addLine(to: CGPoint(x: cx, y: cy + reticuleDemo + reticulEcart))
    cg.strokePath()

    cg.setStrokeColor(couleurReticule)
    cg.setLineWidth(1.5)   // passe de premier plan
    // Horizontal
    cg.move(to: CGPoint(x: cx - reticuleDemo - reticulEcart, y: cy))
    cg.addLine(to: CGPoint(x: cx - reticulEcart, y: cy))
    cg.move(to: CGPoint(x: cx + reticulEcart, y: cy))
    cg.addLine(to: CGPoint(x: cx + reticuleDemo + reticulEcart, y: cy))
    // Vertical
    cg.move(to: CGPoint(x: cx, y: cy - reticuleDemo - reticulEcart))
    cg.addLine(to: CGPoint(x: cx, y: cy - reticulEcart))
    cg.move(to: CGPoint(x: cx, y: cy + reticulEcart))
    cg.addLine(to: CGPoint(x: cx, y: cy + reticuleDemo + reticulEcart))
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()

    // Composer l'NSImage finale à partir du rep bitmap
    let img = NSImage(size: NSSize(width: taille, height: taille))
    img.addRepresentation(repBitmap)

    // Point chaud exactement au centre
    return NSCursor(image: img, hotSpot: NSPoint(x: taille / 2, y: taille / 2))
}

private final class EtatPipette: ObservableObject {
    @Published var estEnSelection: Bool = false
    @Published var couleurCourante: NSColor? = nil

    private var minuterieTracage: Timer?
    private var moniteurDeplacement: Any?

    // Tap CGEvent bloquant — remplace le globalClickMonitor pour
    // intercepter le clic gauche et l'annuler avant qu'il atteigne l'app cible.
    private var tapClic: CFMachPort?
    private var sourceRunLoopClic: CFRunLoopSource?

    // Callback transmis à demarrerSelection, stocké pour que le tap puisse l'appeler.
    private var callbackSelection: ((NSColor) -> Void)?

    func demarrerSelection(surSelection: @escaping (NSColor) -> Void) {
        estEnSelection = true
        callbackSelection = surSelection
        mettreAJourCurseur(pour: nil)

        minuterieTracage = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.echantillonnerPixel()
        }
        moniteurDeplacement = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, self.estEnSelection else { return }
            self.mettreAJourCurseur(pour: self.couleurCourante)
        }
        installerTapClic()
    }

    func arreterSelection() {
        estEnSelection = false
        callbackSelection = nil
        minuterieTracage?.invalidate(); minuterieTracage = nil
        if let m = moniteurDeplacement { NSEvent.removeMonitor(m); moniteurDeplacement = nil }
        supprimerTapClic()
        NSCursor.arrow.set()
    }

    // MARK: - Tap CGEvent bloquant

    private func installerTapClic() {
        let masque = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,   // en tête de chaîne pour intercepter avant tout le monde
            options: .defaultTap,          // mode bloquant (pas listenOnly)
            eventsOfInterest: masque,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let etat = Unmanaged<EtatPipette>.fromOpaque(refcon).takeUnretainedValue()
                guard etat.estEnSelection else { return Unmanaged.passRetained(event) }
                // Capturer couleur et callback AVANT arreterSelection (qui les remet à nil).
                let couleur   = etat.couleurCourante
                let callback  = etat.callbackSelection
                DispatchQueue.main.async {
                    etat.arreterSelection()
                    if let couleur, let callback { callback(couleur) }
                }
                return nil   // ← bloque l'événement, l'app en dessous ne le reçoit pas
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            // Pas de permission Accessibilité — repli sur le moniteur passif
            let repli = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let couleur = self.couleurCourante else { self?.arreterSelection(); return }
                    self.arreterSelection()
                    self.callbackSelection?(couleur)
                }
            }
            _ = repli   // silencieux, on ne peut pas bloquer sans le tap
            return
        }

        tapClic = tap
        sourceRunLoopClic = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), sourceRunLoopClic, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func supprimerTapClic() {
        if let tap = tapClic {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = sourceRunLoopClic {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            tapClic = nil
            sourceRunLoopClic = nil
        }
    }

    private func mettreAJourCurseur(pour couleur: NSColor?) {
        creerCurseurLoupe(couleur: couleur).set()
    }

    /// Échantillonne le pixel sous le curseur.
    /// Utilise CGDisplayCreateImage (non déprécié) plutôt que CGWindowListCreateImage.
    private func echantillonnerPixel() {
        let pos       = NSEvent.mouseLocation
        let idEcran   = CGMainDisplayID()
        let hauteurEc = CGFloat(CGDisplayPixelsHigh(idEcran))
        let rect      = CGRect(x: Int(pos.x), y: Int(hauteurEc - pos.y), width: 1, height: 1)

        guard let img    = CGDisplayCreateImage(idEcran, rect: rect),
              let couleur = NSBitmapImageRep(cgImage: img).colorAt(x: 0, y: 0) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.couleurCourante = couleur
            if self.estEnSelection { self.mettreAJourCurseur(pour: couleur) }
        }
    }
}

private struct BoutonPipette: View {
    let moniteur: MoniteurPressePapier
    let fermer: () -> Void
    /// Si fourni, appelé À LA PLACE de fermer() quand le panneau est épinglé —
    /// masque sans détruire le panneau pour pouvoir le rouvrir après.
    var masquerPourPipette: (() -> Void)? = nil
    /// Appelé après la sélection de couleur pour rouvrir le panneau s'il était épinglé.
    var rouvrirApresPipette: (() -> Void)? = nil
    @StateObject private var etatPipette = EtatPipette()
    @State private var estSurvole = false

    var body: some View {
        Button {
            if etatPipette.estEnSelection {
                etatPipette.arreterSelection()
            } else {
                // Si un masquage temporaire est disponible (panneau épinglé), l'utiliser ;
                // sinon fermer normalement.
                let actionCacher = masquerPourPipette ?? fermer
                actionCacher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    etatPipette.demarrerSelection { couleur in
                        guard let rgb = couleur.usingColorSpace(.sRGB) else { return }
                        let r = Int(rgb.redComponent   * 255)
                        let g = Int(rgb.greenComponent * 255)
                        let b = Int(rgb.blueComponent  * 255)
                        let hex    = String(format: "#%02X%02X%02X", r, g, b)
                        let app    = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Pipette"
                        let element = ElementPressePapier(contenu: .texte(hex), source: app, date: Date())
                        moniteur.elements.insert(element, at: 0)
                        moniteur.copierVersPressePapier(element: element)
                        // Rouvrir le panneau si épinglé
                        rouvrirApresPipette?()
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: etatPipette.estEnSelection ? "stop.circle.fill" : "eyedropper")
                    .font(.system(size: 10, weight: .medium))
                Text(etatPipette.estEnSelection ? L.annulerPipette : L.pipette)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(etatPipette.estEnSelection ? Color.red : (estSurvole ? .primary : .secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                etatPipette.estEnSelection
                    ? Color.red.opacity(0.08)
                    : (estSurvole ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .help(etatPipette.estEnSelection ? L.aideEnCoursPipette : L.aideDebutPipette)
        .onHover { estSurvole = $0 }
    }
}

// MARK: - Helper bouton survolable pour BarreSequence

private struct BoutonSurvolableSequence<Etiquette: View>: View {
    let action: () -> Void
    @ViewBuilder let etiquette: (Bool) -> Etiquette
    @State private var estSurvole = false

    var body: some View {
        Button(action: action) { etiquette(estSurvole) }
            .buttonStyle(.plain)
            .onHover { estSurvole = $0 }
    }
}

// MARK: - Bouton épinglage du panneau (garde la fenêtre ouverte au changement de focus)

private struct BoutonEpinglagePanneau: View {
    @Binding var estEpingle: Bool
    @State private var estSurvole = false
    @State private var estPresse  = false
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        Button {
            let epinglageVers = !estEpingle
            // Animation : rotation + rebond à l'épinglage, retour doux au désépinglage
            if epinglageVers {
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 14)) {
                    rotation = 45
                    scale = 1.25
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                        scale = 1.0
                    }
                }
            } else {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    rotation = 0
                    scale = 0.85
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                }
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                estEpingle = epinglageVers
            }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) { estPresse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { estPresse = false }
            }
        } label: {
            Image(systemName: estEpingle ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(estEpingle ? Color.accentColor : (estSurvole ? Color.accentColor : Color.secondary))
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(estEpingle
                        ? Color.accentColor.opacity(0.15)
                        : (estSurvole ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)))
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: estSurvole)

                .animation(.interpolatingSpring(stiffness: 280, damping: 14), value: scale)
        }
        .buttonStyle(.plain)
        .help(estEpingle
              ? S("Désépingler la fenêtre", "Unpin window")
              : S("Épingler la fenêtre (reste ouverte au changement d'app)", "Pin window (stays open when switching apps)"))
        .onHover { estSurvole = $0 }
    }
}

// MARK: - Bouton copies multiples

private struct BoutonFileCollage: View {
    @Binding var estActif: Bool
    @State private var estSurvole = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { estActif = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.number").font(.system(size: 10, weight: .medium))
                Text(L.copiesMultiples).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(estSurvole ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                estSurvole ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { estSurvole = $0 }
    }
}

// MARK: - Barre de séquence inférieure

private struct BarreSequence: View {
    @ObservedObject var moniteur: MoniteurPressePapier
    let fermer: () -> Void
    @Binding var estActif: Bool
    @Binding var file: [ElementPressePapier]
    var masquerPourPipette: (() -> Void)? = nil
    var rouvrirApresPipette: (() -> Void)? = nil
    var masquerPourSequence: (() -> Void)? = nil
    var rouvrirApresSequence: (() -> Void)? = nil
    @State private var panneauMasquePourSequence: Bool = false

    private var estEnAttente: Bool   { moniteur.estSequenceActive }
    private var indexCourant: Int    { moniteur.progressionSequence.actuel }
    private var total: Int           { moniteur.fileSequence.count }

    var body: some View {
        Group {
            if estActif || estEnAttente {
                HStack(spacing: 8) {
                    Circle()
                        .fill(estEnAttente ? Color.orange : Color.accentAttenuation)
                        .frame(width: 6, height: 6)

                    if estEnAttente {
                        HStack(spacing: 4) {
                            ForEach(Array(moniteur.fileSequence.enumerated()), id: \.element.id) { idx, _ in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        idx < indexCourant  ? Color.green.opacity(0.7) :
                                        idx == indexCourant ? Color.accentAttenuation :
                                                              Color.primary.opacity(0.15)
                                    )
                                    .frame(width: idx == indexCourant ? 18 : 10, height: 6)
                                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: indexCourant)
                            }
                        }
                        Text("\u{2318}V  \(indexCourant)/\(total)")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                        Spacer()
                        Button(action: annuler) {
                            Text(L.annuler)
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(file.isEmpty ? L.appuyerAjouter : L.nbElements(file.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(file.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        if !file.isEmpty {
                            BoutonSurvolableSequence {
                                file = []
                            } etiquette: { survole in
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(survole ? .primary : .secondary)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        survole ? Color.primary.opacity(0.13) : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .fixedSize()
                            BoutonSurvolableSequence(action: demarrer) { survole in
                                HStack(spacing: 3) {
                                    Image(systemName: "play.fill").font(.system(size: 9))
                                    Text(L.demarrer).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(
                                    survole ? Color.accentAttenuation.opacity(0.75) : Color.accentAttenuation,
                                    in: RoundedRectangle(cornerRadius: 20)
                                )
                            }
                            .fixedSize()
                        }
                        BoutonSurvolableSequence(action: annuler) { survole in
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(survole ? .primary : .secondary)
                                .frame(width: 18, height: 18)
                                .background(
                                    survole ? Color.primary.opacity(0.13) : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .background(
                    estEnAttente ? Color.orange.opacity(0.08) : Color.accentAttenuation.opacity(0.20),
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 8) {
                    BoutonFileCollage(estActif: $estActif)

                    BoutonPipette(moniteur: moniteur, fermer: fermer, masquerPourPipette: masquerPourPipette, rouvrirApresPipette: rouvrirApresPipette).frame(maxWidth: .infinity)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: estActif)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: estEnAttente)
        .onChange(of: moniteur.estSequenceActive) { _, actif in
            // La séquence vient de se terminer et on avait masqué le panneau → le rouvrir
            if !actif, panneauMasquePourSequence {
                panneauMasquePourSequence = false
                file = []
                estActif = false
                rouvrirApresSequence?()
            }
        }
    }

    private func demarrer() {
        guard !file.isEmpty else { return }
        moniteur.demarrerSequence(elements: file)
        if let masquer = masquerPourSequence {
            // Panneau épinglé : masquer sans détruire, sera rouvert à la fin
            masquer()
            panneauMasquePourSequence = true
        } else {
            fermer()
        }
    }

    private func annuler() {
        moniteur.annulerSequence()
        file = []
        estActif = false
    }
}

// MARK: - Panneau principal

struct PanneauPressePapier: View {
    @ObservedObject var moniteur: MoniteurPressePapier
    let fermer: () -> Void
    /// Passé uniquement par le NSPanel — absent du panel widget SDK
    var epingleBinding: Binding<Bool>? = nil
    /// Masque le panneau sans le détruire (pour la pipette quand épinglé)
    var masquerPourPipette: (() -> Void)? = nil
    /// Callback pour rouvrir le panneau après la pipette si épinglé
    var rouvrirApresPipette: (() -> Void)? = nil
    /// Masque le panneau sans le détruire (pour la séquence quand épinglé)
    var masquerPourSequence: (() -> Void)? = nil
    /// Callback pour rouvrir le panneau après la séquence si épinglé
    var rouvrirApresSequence: (() -> Void)? = nil

    private var afficherBoutonEpingle: Bool { epingleBinding != nil }

    @State private var selectionne: ElementPressePapier? = nil
    @State private var filtreActif: FiltrePressePapier = .tout
    @State private var afficherPanneauSequence: Bool = false
    @State private var fileSequence: [ElementPressePapier] = []
    @State private var rechercheActive: Bool = false
    @State private var texteRecherche: String = ""

    private var elementsFiltres: [ElementPressePapier] {
        let base: [ElementPressePapier]
        switch filtreActif {
        case .tout:    base = moniteur.elements
        case .medias:  base = moniteur.elements.filter {
            if case .image = $0.contenu { return true }
            if case .urlFichier(let url) = $0.contenu {
                let ext = url.pathExtension.lowercased()
                let extensionsMedia: Set<String> = [
                    "jpg","jpeg","png","gif","webp","svg","tiff","tif","bmp","heic","heif",
                    "mp4","mov","avi","mkv","m4v","wmv","webm",
                    "pdf","docx","doc","xlsx","xls","pptx","ppt","pages","numbers","key","odt"
                ]
                return extensionsMedia.contains(ext)
            }
            return false
        }
        case .donnees: base = moniteur.elements.filter {
            if case .texte = $0.contenu {
                let st = $0.sousTypeCache
                return st == .email || st == .telephone || st == .date || st == .url
            }
            return false
        }
        }
        // Appliquer la recherche textuelle par-dessus le filtre actif
        let q = texteRecherche.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.titreAffiche.lowercased().contains(q) }
    }

    private var elementsEpingles:    [ElementPressePapier] { elementsFiltres.filter { $0.estEpingle } }
    private var elementsNonEpingles: [ElementPressePapier] { elementsFiltres.filter { !$0.estEpingle } }

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                // Correctif : toujours lire l'élément depuis moniteur.elements pour que estEpingle et les autres
                // changements d'état soient reflétés immédiatement (évite la copie de struct périmée).
                if let element = (selectionne.flatMap { s in moniteur.elements.first(where: { $0.id == s.id }) })
                                ?? moniteur.elements.first { panneauApercu(element).id(element.id) }
                else { apercuVide }
            }
            .padding(.leading, 304)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if rechercheActive {
                        // ── Mode recherche : champ texte remplace les filtres ──
                        ChampRechercheInline(texte: $texteRecherche, actif: $rechercheActive)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                                removal:   .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
                            ))
                    } else {
                        // ── Mode normal : filtres + bouton recherche ───────────
                        ControleFiltreSegmente(filtres: FiltrePressePapier.allCases, filtreActif: $filtreActif, iconesSeulement: afficherBoutonEpingle)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity),
                                removal:   .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity)
                            ))
                        BoutonRecherche {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                rechercheActive = true
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    if let binding = epingleBinding {
                        BoutonEpinglagePanneau(estEpingle: binding)
                    }
                    BoutonReinitialisation {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { moniteur.toutEffacer(); selectionne = nil }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.top, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        if !elementsEpingles.isEmpty {
                            etiquetteSection(L.epingles)
                            ForEach(elementsEpingles) { element in
                                ligneElement(element)
                                    .id(element.id.uuidString + "\(element.estEpingle)")
                                    .transition(.opacity)
                            }
                        }
                        if !elementsNonEpingles.isEmpty {
                            if !elementsEpingles.isEmpty { etiquetteSection(L.recents) }
                            ForEach(elementsNonEpingles) { element in
                                ligneElement(element)
                                    .id(element.id.uuidString + "\(element.estEpingle)")
                                    .transition(.opacity)
                            }
                        }
                        if elementsFiltres.isEmpty { vueEtatVide }
                        Spacer().frame(height: 12)
                    }
                    .animation(.easeInOut(duration: 0.18), value: filtreActif)
                    .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 10)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20)
                        .allowsHitTesting(false)
                        .blendMode(.destinationOut)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: 20)
                        .allowsHitTesting(false)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                BarreSequence(moniteur: moniteur, fermer: fermer, estActif: $afficherPanneauSequence, file: $fileSequence,
                              masquerPourPipette: masquerPourPipette, rouvrirApresPipette: rouvrirApresPipette,
                              masquerPourSequence: masquerPourSequence, rouvrirApresSequence: rouvrirApresSequence)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .frame(width: 277).frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 4)
            )
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            .padding(12)
        }
        .frame(width: 765, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .onAppear { selectionne = moniteur.elements.first(where: { !$0.estEpingle }) ?? moniteur.elements.first }
    }

    @State private var doubleTapID: UUID? = nil

    private func ligneElement(_ element: ElementPressePapier) -> some View {
        let idxSeq = fileSequence.firstIndex(where: { $0.id == element.id })
        let estDejaSelectionne = !afficherPanneauSequence && selectionne?.id == element.id

        return LigneElementPressePapier(
            element: element,
            estSelectionne: estDejaSelectionne,
            indexSequence: afficherPanneauSequence ? idxSeq.map { $0 + 1 } : nil,
            chargerMiniature: true,
            surTap: {
                if afficherPanneauSequence {
                    if fileSequence.contains(where: { $0.id == element.id }) {
                        fileSequence.removeAll { $0.id == element.id }
                    } else {
                        fileSequence.append(element)
                    }
                } else {
                    // Si le double-tap vient de marquer cet élément, coller une seule fois
                    if doubleTapID == element.id {
                        doubleTapID = nil
                        moniteur.coller(element: element); fermer()
                    } else if estDejaSelectionne {
                        moniteur.coller(element: element); fermer()
                    } else {
                        selectionne = element
                    }
                }
            },
            surDoubleTap: {
                guard !afficherPanneauSequence else { return }
                // Marquer l'élément pour que surTap (qui arrive juste après) colle une seule fois
                doubleTapID = element.id
                selectionne = element
            }
        )
    }

    private func etiquetteSection(_ texte: String) -> some View {
        HStack {
            if texte == L.epingles {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.accentColor)
            }
            Text(texte).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
    }

    private func panneauApercu(_ element: ElementPressePapier) -> some View {
        // Structure : VStack en 3 blocs dans un conteneur 500px de haut
        //
        // ┌─────────────────────────────────────────┐
        // │  BLOC 1 : zoneApercu                    │  ← maxHeight: .infinity
        // │  (image / texte / fichier)              │
        // ├─────────────────────────────────────────┤
        // │  BLOC 2 : ligneInfos                    │  ← hauteur fixe naturelle
        // │  [icône app + nom]  [dimensions]  [date]│
        // ├─────────────────────────────────────────┤
        // │  BLOC 3 : ligneBoutons                  │  ← hauteur fixe naturelle
        // │  [Coller] [Copier] [💾] [📌] [🗑]       │
        // └─────────────────────────────────────────┘

        let zoneApercu = ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.secondary.opacity(0.10))
            contenuApercu(pour: element)
                .id(element.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: element.id)
        }

        let ligneInfos = HStack(alignment: .center) {
            HStack(spacing: 5) {
                Text(element.source)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DateFormatter.datePleine.string(from: element.date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }

        let ligneBoutons = HStack(spacing: 10) {
            BoutonActionAnime(titre: L.collerTitre, icone: "arrow.down.doc", texteAide: L.collerAide, pleineLargeur: true) {
                moniteur.coller(element: element); fermer()
            }
            BoutonActionAnime(titre: L.copierTitre, icone: "doc.on.doc", texteAide: L.copierAide, pleineLargeur: true) {
                moniteur.copierVersPressePapier(element: element)
            }
            if case .image(let img) = element.contenu { BoutonSauvegardeImage(image: img) }
            if case .urlFichier(let url) = element.contenu { BoutonSauvegardeFichier(url: url) }
            if case .texte(let t) = element.contenu, (t.hasPrefix("http") || t.hasPrefix("www")), let url = URL(string: t) {
                BoutonIconeSurvol(symbole: "globe.americas.fill", couleur: .secondary, texteAide: L.ouvrirNavig) {
                    NSWorkspace.shared.open(url)
                }
            }
            BoutonEpingleElement(estEpingle: element.estEpingle) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    moniteur.basculerEpingle(element: element)
                    if selectionne?.id == element.id {
                        selectionne = moniteur.elements.first(where: { $0.id == element.id })
                    }
                }
            }
            BoutonIconeSurvol(symbole: "trash", couleur: .red, texteAide: L.supprimer) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if selectionne?.id == element.id {
                        // Trouver l'élément suivant dans la liste filtrée avant suppression
                        let liste = elementsFiltres
                        if let idx = liste.firstIndex(where: { $0.id == element.id }) {
                            if idx + 1 < liste.count {
                                selectionne = liste[idx + 1]   // élément juste en dessous
                            } else if idx > 0 {
                                selectionne = liste[idx - 1]   // dernier de la liste → on remonte
                            } else {
                                selectionne = nil              // liste vide après suppression
                            }
                        }
                    }
                    moniteur.supprimer(element: element)
                }
            }
        }

        return VStack(spacing: 0) {
            zoneApercu
                .padding(.horizontal, 12)
                .padding(.top, 0)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ligneInfos
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            ligneBoutons
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // OPTIMISATION 8 : @ViewBuilder — SwiftUI voit le type concret de chaque branche
    // et peut diff efficacement sans passer par la boîte noire AnyView.
    @ViewBuilder
    private func contenuApercu(pour element: ElementPressePapier) -> some View {
        switch element.contenu {
        case .image(let img):
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .padding(16)
        case .texte(let t):
            // OPTIMISATION 9 : on utilise couleurCachee au lieu de recalculer la regex
            if let couleur = element.couleurCachee {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(couleur)
                        .frame(width: 180, height: 180)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    VueEchantillonCouleur(couleur: couleur, etiquette: t.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                ScrollView {
                    Text(t)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .urlFichier(let url):
            ApercuFichier(url: url).padding(12)
        case .inconnu:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }

    private var apercuVide: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard.fill").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(L.selectionnerElement).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var vueEtatVide: some View {
        VStack(spacing: 8) {
            Image(systemName: filtreActif.icone).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(L.videFiltre(filtre: filtreActif.etiquette)).foregroundStyle(.secondary).font(.caption)
        }
        .padding(.top, 40).frame(maxWidth: .infinity)
    }
}

// MARK: - Wrapper SDK : protège dismiss() contre la fermeture prématurée
//
// Problème : DD Pro surveille la souris sur son widget et appelle dismiss()
// dès qu'elle le quitte — même si elle se dirige vers notre panel popup.
// Quand la souris bouge vite, le dismiss est déclenché avant que la souris
// soit arrivée sur le panel, qui disparaît aussitôt.
//
// Solution : makePanelBody (ClipboardPlugin) enveloppe le dismiss DD Pro
// dans un dismissProtege qui attend 200 ms et vérifie via NSEvent.mouseLocation
// si la souris est dans le frame du panel. Si oui → fermeture annulée.
// La fermeture explicite (bouton ✕, raccourci) passe par `fermer` directement.

// MARK: - Contexte partagé Plugin ↔ Sentinelle

/// Objet de liaison transmis par ClipboardPlugin à PanneauPressePapierSDK
/// puis à SentinelleNSPanel. La sentinelle y dépose la fenêtre dès qu'elle
/// est insérée dans la hiérarchie, ce qui permet au dismissProtege de connaître
/// le frame du panel pour vérifier la position de la souris.
final class ContexteFenetrePanelSDK: @unchecked Sendable {
    weak var fenetre: NSWindow?
    var workItemEnCours: DispatchWorkItem?

    func annulerFermetureProgrammee() {
        workItemEnCours?.cancel()
        workItemEnCours = nil
    }
}

struct PanneauPressePapierSDK: View {
    let moniteur: MoniteurPressePapier
    /// Fermeture explicite (bouton ✕, raccourci) — toujours honorée.
    let dismiss: () -> Void
    /// Fermeture avec délai de grâce — appelée par DD Pro quand la souris quitte le widget.
    let dismissProtege: () -> Void
    let contexte: ContexteFenetrePanelSDK

    var body: some View {
        PanneauPressePapier(
            moniteur: moniteur,
            fermer: dismiss
        )
        .background(SentinelleNSPanel(contexte: contexte))
        .onHover { dedans in
            // Dès que la souris entre dans le panel, on annule la fermeture programmée.
            if dedans { contexte.annulerFermetureProgrammee() }
        }
    }
}

// MARK: - Sentinelle NSPanel

/// NSView invisible dont le seul rôle est de déposer la référence à la
/// NSWindow dans ContexteFenetrePanelSDK dès qu'elle est connue.
private struct SentinelleNSPanel: NSViewRepresentable {
    let contexte: ContexteFenetrePanelSDK

    func makeNSView(context: Context) -> VueSentinelle {
        let vue = VueSentinelle(contexte: contexte)
        vue.translatesAutoresizingMaskIntoConstraints = false
        return vue
    }

    func updateNSView(_ vue: VueSentinelle, context: Context) {}

    // NSView subclass : viewDidMoveToWindow est fiable dès l'insertion.
    class VueSentinelle: NSView {
        let contexte: ContexteFenetrePanelSDK
        init(contexte: ContexteFenetrePanelSDK) {
            self.contexte = contexte
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            contexte.fenetre = window
        }
    }
}
