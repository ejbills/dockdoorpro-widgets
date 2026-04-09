import DockDoorWidgetSDK
import SwiftUI
import AppKit

// MARK: - Table de clavier unifiée (OPTIMISATION 5 : source unique au lieu de deux tables dupliquées)

/// Paires (nom, code virtuel) partagées par l'analyse et l'affichage.
private let tableClavier: [(String, UInt16)] = [
    ("a",0x00),("b",0x0B),("c",0x08),("d",0x02),("e",0x0E),("f",0x03),
    ("g",0x05),("h",0x04),("i",0x22),("j",0x26),("k",0x28),("l",0x25),
    ("m",0x2E),("n",0x2D),("o",0x1F),("p",0x23),("q",0x0C),("r",0x0F),
    ("s",0x01),("t",0x11),("u",0x20),("v",0x09),("w",0x0D),("x",0x07),
    ("y",0x10),("z",0x06),
    ("1",0x12),("2",0x13),("3",0x14),("4",0x15),("5",0x17),
    ("6",0x16),("7",0x1A),("8",0x1C),("9",0x19),("0",0x1D),
    ("return",0x24),("enter",0x24),("tab",0x30),("space",0x31),
    ("delete",0x33),("backspace",0x33),("escape",0x35),("esc",0x35),
    ("left",0x7B),("right",0x7C),("down",0x7D),("up",0x7E),
    ("f1",0x7A),("f2",0x78),("f3",0x63),("f4",0x76),("f5",0x60),
    ("f6",0x61),("f7",0x62),("f8",0x64),("f9",0x65),("f10",0x6D),
    ("f11",0x67),("f12",0x6F)
]

/// Symboles d'affichage pour les codes virtuels (dérivés de tableClavier + spéciaux)
private let tableAffichage: [UInt16: String] = {
    var t = [UInt16: String]()
    // Lettres et chiffres : majuscule pour l'affichage
    for (nom, code) in tableClavier where nom.count == 1 { t[code] = nom.uppercased() }
    // Touches spéciales
    t[0x24] = "↩"; t[0x30] = "⇥"; t[0x31] = "Espace"; t[0x33] = "⌫"; t[0x35] = "⎋"
    t[0x7B] = "←"; t[0x7C] = "→"; t[0x7D] = "↓"; t[0x7E] = "↑"
    t[0x7A] = "F1"; t[0x78] = "F2"; t[0x63] = "F3"; t[0x76] = "F4"
    t[0x60] = "F5"; t[0x61] = "F6"; t[0x62] = "F7"; t[0x64] = "F8"
    t[0x65] = "F9"; t[0x6D] = "F10"; t[0x67] = "F11"; t[0x6F] = "F12"
    return t
}()

private func codeTouchePourChaine(_ s: String) -> UInt16? {
    tableClavier.first(where: { $0.0 == s })?.1
}

// MARK: - Helpers d'analyse du raccourci clavier

struct DescripteurRaccourci {
    let modificateurs: NSEvent.ModifierFlags
    let codeTouche: UInt16

    static let defaultBrut = "option+v"

    static func analyser(_ brut: String) -> DescripteurRaccourci? {
        let parties = brut.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parties.count >= 2 else { return nil }

        var indicateurs: NSEvent.ModifierFlags = []
        for mod in parties.dropLast() {
            switch mod {
            case "cmd", "command":         indicateurs.insert(.command)
            case "option", "opt", "alt":   indicateurs.insert(.option)
            case "shift":                  indicateurs.insert(.shift)
            case "ctrl", "control":        indicateurs.insert(.control)
            default: return nil
            }
        }

        guard let codeTouche = codeTouchePourChaine(parties.last!) else { return nil }
        return DescripteurRaccourci(modificateurs: indicateurs, codeTouche: codeTouche)
    }

    /// Convertit les modificateurs NSEvent en CGEventFlags pour la comparaison dans le tap
    func versCGEventFlags() -> CGEventFlags {
        var f: CGEventFlags = []
        if modificateurs.contains(.command) { f.insert(.maskCommand) }
        if modificateurs.contains(.option)  { f.insert(.maskAlternate) }
        if modificateurs.contains(.shift)   { f.insert(.maskShift) }
        if modificateurs.contains(.control) { f.insert(.maskControl) }
        return f
    }

    var chaineAffichage: String {
        var s = ""
        if modificateurs.contains(.control) { s += "⌃" }
        if modificateurs.contains(.option)  { s += "⌥" }
        if modificateurs.contains(.shift)   { s += "⇧" }
        if modificateurs.contains(.command) { s += "⌘" }
        return s + (tableAffichage[codeTouche] ?? "?")
    }
}

// MARK: - Plugin

final class ClipboardPlugin: WidgetPlugin, DockDoorWidgetProvider {
    // Références statiques accessibles depuis le callback CGEvent (contexte C, pas de capture Swift)
    static weak var shared: ClipboardPlugin?
    static var raccourciActif: DescripteurRaccourci?

    var id: String { "clipboard-history" }
    var name: String { S("Presse-papiers", "Clipboard") }
    var iconSymbol: String { WidgetDefaults.string(key: "iconSymbol", widgetId: "clipboard-history", default: "clipboard.fill") }
    var widgetDescription: String { S("Accès rapide à l'historique du presse-papiers avec aperçu.", "Quick access to clipboard history with live preview.") }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let moniteur = MoniteurPressePapier.shared
    // Tap CGEvent (intercepte ET bloque le raccourci pour éviter l'insertion du caractère parasite)
    private var tapRaccourciEvenement: CFMachPort?
    private var sourceRunLoopRaccourci: CFRunLoopSource?
    private var panneauFlottant: PanneauEditable?
    private var observateurResignation: Any?
    /// Quand true, le panneau ignore la perte de focus et ne se ferme pas automatiquement.
    private var estEpingle: Bool = false

    // MARK: - Init / Deinit

    required init() {
        super.init()
        ClipboardPlugin.shared = self
        // OPTIMISATION 6 : le raccourci est enregistré une seule fois au démarrage.
        // Un changement de réglage nécessite un redémarrage — évite de réinstaller
        // un CGEventTap (opération système lourde) toutes les 0,5 s lors des
        // sauvegardes de l'historique qui déclenchaient UserDefaults.didChangeNotification.
        enregistrerRaccourci()
    }

    deinit {
        supprimerTapRaccourci()
        if let monitor = observateurResignation { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Raccourci clavier

    private func enregistrerRaccourci() {
        supprimerTapRaccourci()

        let brut = UserDefaults.standard.string(forKey: "widget.clipboard-history.hotkey") ?? DescripteurRaccourci.defaultBrut
        guard let raccourci = DescripteurRaccourci.analyser(brut) else { return }

        ClipboardPlugin.raccourciActif = raccourci

        let masque = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: masque,
            callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
                guard let raccourci = ClipboardPlugin.raccourciActif else {
                    return Unmanaged.passRetained(event)
                }
                let presse = event.flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
                let indicateursVoulus: CGEventFlags = raccourci.versCGEventFlags()
                let codeTouche = event.getIntegerValueField(.keyboardEventKeycode)
                guard presse == indicateursVoulus, codeTouche == Int64(raccourci.codeTouche) else {
                    return Unmanaged.passRetained(event)
                }
                DispatchQueue.main.async {
                    ClipboardPlugin.shared?.basculerPanneauFlottant()
                }
                return nil // ← bloque l'événement, le caractère ◊ ne s'insère pas
            },
            userInfo: nil
        )

        guard let tap else { return }
        tapRaccourciEvenement = tap
        sourceRunLoopRaccourci = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), sourceRunLoopRaccourci, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func supprimerTapRaccourci() {
        if let tap = tapRaccourciEvenement {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = sourceRunLoopRaccourci {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            tapRaccourciEvenement  = nil
            sourceRunLoopRaccourci = nil
        }
    }

    // MARK: - Panneau flottant

    func basculerPanneauFlottant() {
        if let existant = panneauFlottant, existant.isVisible {
            fermerPanneauFlottant(force: true)
            return
        }
        ouvrirPanneauFlottant()
    }

    // OPTIMISATION 7 : les animations masquer/rouvrir étaient dupliquées pour pipette et séquence.
    // Deux fonctions privées partagées évitent la répétition et centralisent les durées d'animation.

    private func animerMasquagePanneau(_ panneau: NSPanel) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panneau.animator().alphaValue = 0
        }, completionHandler: { panneau.orderOut(nil) })
    }

    private func animerRéouverturePanneau(_ panneau: NSPanel) {
        panneau.alphaValue = 0
        panneau.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panneau.animator().alphaValue = 1
        }
    }

    private func ouvrirPanneauFlottant() {
        panneauFlottant?.orderOut(nil)
        panneauFlottant = nil
        if let monitor = observateurResignation { NSEvent.removeMonitor(monitor); observateurResignation = nil }

        let panneau = PanneauEditable(
            contentRect: NSRect(x: 0, y: 0, width: 765, height: 500),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panneau.isMovableByWindowBackground = true
        panneau.isFloatingPanel = true
        panneau.level = .floating
        panneau.backgroundColor = .clear
        panneau.hasShadow = true
        panneau.isReleasedWhenClosed = false

        // Centrer sur l'écran où se trouve la souris, ou restaurer la dernière position
        if let savedX = UserDefaults.standard.object(forKey: "clipboard.panel.x") as? Double,
           let savedY = UserDefaults.standard.object(forKey: "clipboard.panel.y") as? Double {
            panneau.setFrameOrigin(NSPoint(x: savedX, y: savedY))
        } else {
            let ecran = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }) ?? NSScreen.main
            if let ecran = ecran {
                let x = ecran.visibleFrame.midX - 765 / 2
                let y = ecran.visibleFrame.midY - 500 / 2
                panneau.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        panneau.contentView = NSHostingView(rootView:
            PanneauPressePapier(moniteur: moniteur, fermer: { [weak self] in
                self?.fermerPanneauFlottant(force: true)
            }, epingleBinding: Binding(
                get: { [weak self] in self?.estEpingle ?? false },
                set: { [weak self] val in self?.estEpingle = val }
            ), masquerPourPipette: { [weak self] in
                guard let panneau = self?.panneauFlottant else { return }
                self?.animerMasquagePanneau(panneau)
            }, rouvrirApresPipette: { [weak self] in
                guard let self, self.estEpingle, let panneau = self.panneauFlottant else { return }
                self.animerRéouverturePanneau(panneau)
            }, masquerPourSequence: { [weak self] in
                guard let panneau = self?.panneauFlottant else { return }
                self?.animerMasquagePanneau(panneau)
            }, rouvrirApresSequence: { [weak self] in
                guard let self, self.estEpingle, let panneau = self.panneauFlottant else { return }
                self.animerRéouverturePanneau(panneau)
            })
        )

        panneauFlottant = panneau
        panneau.alphaValue = 0
        panneau.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panneau.animator().alphaValue = 1
        }

        // Fermer sur clic en dehors du panneau — ignoré si épinglé
        observateurResignation = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panneau] _ in
            guard let self, !self.estEpingle else { return }
            guard let panneau, panneau.isVisible else { return }
            self.fermerPanneauFlottant(force: false)
        }
    }

    /// - `force: true`  → fermeture explicite (raccourci, bouton ✕) : remet estEpingle à false et ferme toujours.
    /// - `force: false` → fermeture automatique (clic dehors) : bloquée si estEpingle est true.
    private func fermerPanneauFlottant(force: Bool = false) {
        guard force || !estEpingle else { return }
        if let panneau = panneauFlottant {
            UserDefaults.standard.set(Double(panneau.frame.origin.x), forKey: "clipboard.panel.x")
            UserDefaults.standard.set(Double(panneau.frame.origin.y), forKey: "clipboard.panel.y")
        }
        estEpingle = false
        if let panneau = panneauFlottant {
            let capturedPanneau = panneau
            panneauFlottant = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                capturedPanneau.animator().alphaValue = 0
            }, completionHandler: {
                capturedPanneau.orderOut(nil)
            })
        }
        if let monitor = observateurResignation { NSEvent.removeMonitor(monitor); observateurResignation = nil }
    }

    // MARK: - Paramètres

    func settingsSchema() -> [WidgetSetting] {
        let brut    = WidgetDefaults.string(key: "hotkey", widgetId: id, default: DescripteurRaccourci.defaultBrut)
        let affiche = DescripteurRaccourci.analyser(brut)?.chaineAffichage ?? brut

        return [
            .picker(
                key: "langue",
                label: L.labelLangue,
                options: ["en", "fr"],
                defaultValue: "en"
            ),
            .picker(
                key: "iconSymbol",
                label: L.labelIcone,
                options: [
                    "clipboard.fill", "clipboard",
                    "doc.on.clipboard.fill", "doc.on.clipboard",
                    "list.clipboard.fill", "list.clipboard",
                    "tray.full.fill", "tray.full",
                    "doc.plaintext.fill", "doc.plaintext",
                    "doc.fill", "note.text", "text.alignleft",
                    "bookmark.fill", "tag.fill", "pin.fill",
                    "paperclip", "archivebox.fill",
                    "clock.fill", "clock.arrow.circlepath",
                    "bolt.fill", "star.fill",
                ],
                defaultValue: "clipboard.fill"
            ),
            .toggle(
                key: "afficherIcone",
                label: S("Afficher l'icône dans la vue double", "Show icon in extended view"),
                defaultValue: false
            ),
            .textField(
                key: "hotkey",
                label: "\(L.labelRaccourci) (\(affiche))",
                placeholder: L.placeholderRaccourci,
                defaultValue: DescripteurRaccourci.defaultBrut
            ),
        ]
    }

    // MARK: - Vues

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        let symbole = WidgetDefaults.string(key: "iconSymbol", widgetId: id, default: "clipboard.fill")
        let afficherIcone = WidgetDefaults.bool(key: "afficherIcone", widgetId: id, default: false)
        return AnyView(VuePressePapiersWidget(taille: size, estVertical: isVertical, moniteur: moniteur, symboleIcone: symbole, afficherIcone: afficherIcone))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        let ctx = ContexteFenetrePanelSDK()
        let dismissProtege: () -> Void = {
            ctx.annulerFermetureProgrammee()
            let workItem = DispatchWorkItem {
                let souris = NSEvent.mouseLocation
                if let frame = ctx.fenetre?.frame, frame.contains(souris) { return }
                dismiss()
            }
            ctx.workItemEnCours = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
        }
        return AnyView(PanneauPressePapierSDK(moniteur: moniteur,
                                               dismiss: dismiss,
                                               dismissProtege: dismissProtege,
                                               contexte: ctx))
    }
}
