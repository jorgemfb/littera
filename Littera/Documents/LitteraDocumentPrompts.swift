import AppKit

enum LitteraUnsavedChoice { case save, discard, cancel }
enum LitteraExternalChangeChoice { case reload, keepMine }
enum LitteraConflictChoice { case keepBoth, keepMine, useOther }
enum LitteraRecoveryChoice { case recover, discard, later }

/// Preguntas que el almacén de documentos hace al usuario. Las pruebas usan
/// respuestas fijas; la app usa alertas nativas.
@MainActor
protocol LitteraDocumentPrompts: AnyObject {
    func unsavedChanges(fileName: String, locale: Locale) -> LitteraUnsavedChoice
    func externalChange(fileName: String, locale: Locale) -> LitteraExternalChangeChoice
    func confirmOverwrite(fileName: String, locale: Locale) -> Bool
    func conflict(fileName: String, deviceName: String?, date: Date?, locale: Locale) -> LitteraConflictChoice
    func showError(titleKey: String, detail: String, locale: Locale)
    func recovery(fileNames: [String], locale: Locale) -> LitteraRecoveryChoice
}

@MainActor
final class LitteraAlertPrompts: LitteraDocumentPrompts {
    func unsavedChanges(fileName: String, locale: Locale) -> LitteraUnsavedChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("ui.cambios.sin.guardar", locale: locale)
        alert.informativeText = L10n.formatted("ui.confirmar.cierre.documento", locale: locale, fileName)
        alert.addButton(withTitle: L10n.tr("ui.guardar.documento", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.no.guardar", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.cancelar", locale: locale))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    func externalChange(fileName: String, locale: Locale) -> LitteraExternalChangeChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.formatted("ui.archivo.cambiado.fuera", locale: locale, fileName)
        alert.informativeText = L10n.tr("ui.archivo.cambiado.fuera.detalle", locale: locale)
        alert.addButton(withTitle: L10n.tr("ui.mantener.mi.version", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.cargar.version.del.disco", locale: locale))
        return alert.runModal() == .alertSecondButtonReturn ? .reload : .keepMine
    }

    func confirmOverwrite(fileName: String, locale: Locale) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.formatted("ui.archivo.cambiado.fuera", locale: locale, fileName)
        alert.informativeText = L10n.tr("ui.sobrescribir.detalle", locale: locale)
        alert.addButton(withTitle: L10n.tr("ui.cancelar", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.sobrescribir", locale: locale))
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Conflicto de iCloud Drive (D50). «Conservar ambas» es la opción por
    /// omisión porque no descarta nada.
    func conflict(fileName: String, deviceName: String?, date: Date?, locale: Locale) -> LitteraConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.formatted("ui.conflicto.titulo", locale: locale, fileName)
        let device = deviceName ?? L10n.tr("ui.otro.dispositivo", locale: locale)
        let when = date.map {
            $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
        } ?? "—"
        alert.informativeText = L10n.formatted("ui.conflicto.detalle", locale: locale, device, when)
        alert.addButton(withTitle: L10n.tr("ui.conservar.ambas", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.conservar.la.de.este.mac", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.usar.la.otra", locale: locale))
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .keepMine
        case .alertThirdButtonReturn: return .useOther
        default: return .keepBoth
        }
    }

    /// Copias de recuperación al arrancar (LIT-001). «Recuperar» es la opción
    /// por omisión porque no descarta nada ni toca el archivo original.
    func recovery(fileNames: [String], locale: Locale) -> LitteraRecoveryChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("ui.recuperacion.titulo", locale: locale)
        let quoted = fileNames.map { L10n.formatted("ui.recuperacion.nombre", locale: locale, $0) }
        let list = ListFormatter()
        list.locale = locale
        let names = list.string(from: quoted) ?? quoted.joined(separator: ", ")
        alert.informativeText = L10n.formatted("ui.recuperacion.detalle", locale: locale, names)
        alert.addButton(withTitle: L10n.tr("ui.recuperacion.recuperar", locale: locale))
        alert.addButton(withTitle: L10n.tr("ui.recuperacion.mas.tarde", locale: locale))
        let discard = alert.addButton(withTitle: L10n.tr("ui.recuperacion.descartar", locale: locale))
        discard.hasDestructiveAction = true
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .later
        case .alertThirdButtonReturn: return .discard
        default: return .recover
        }
    }

    func showError(titleKey: String, detail: String, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr(titleKey, locale: locale)
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.tr("ui.aceptar", locale: locale))
        alert.runModal()
    }
}
